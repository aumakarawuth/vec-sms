import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  SetMetadata,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { createHash } from 'node:crypto';
import { Request, Response } from 'express';

import { DbService } from '../db/db.service';

/**
 * จำกัดจำนวนคำขอต่อไอพี
 *
 * ─── นับสองชั้น และทั้งสองชั้นต้องผ่าน ───
 * ชั้นแรกอยู่ในหน่วยความจำของโปรเซส เร็วและไม่แตะฐานข้อมูล กันการยิงรัว
 * ใส่เครื่องเดียวได้ทันที ชั้นที่สองอยู่ในฐานข้อมูล (`request_rate_hit`)
 * ซึ่งนับรวมทุก instance
 *
 * ─── ทำไมต้องมีชั้นที่สอง ───
 * ตัวนับในหน่วยความจำถูกแบ่งตามจำนวน instance — รัน 3 instance แปลว่า
 * เพดานจริงเป็นสามเท่าของที่ตั้งไว้ และรีสตาร์ททีเดียวตัวนับคืนค่าใหม่
 * เรื่องนี้ไม่ใช่ "หลวมนิดหน่อย" สำหรับเส้นทางที่ตั้งเพดานแน่นไว้โดยตั้งใจ
 * เช่น `POST /provisioning/institutions` ที่ตั้งไว้ 3 ครั้งต่อนาทีเพราะ
 * ทุกคำขอที่ผ่านสร้างวิทยาลัยใหม่หนึ่งแห่ง — เพดานถูกเลือกจากผลที่ตามมา
 * การคูณสามคือเพดานคนละตัวกับที่ตัดสินใจไว้ และไม่มีอะไรฟ้องเลยตอน scale out
 *
 * การเข้าสู่ระบบมีตัวนับของตัวเองอยู่แล้วใน `login_rate_status()` (0021)
 * ซึ่งนับเฉพาะครั้งที่**ล้มเหลว** — คนละหน้าที่กับตัวนี้ที่นับทุกคำขอ
 *
 * ─── ราคาที่จ่าย ───
 * หนึ่ง query ต่อคำขอที่ถูกจำกัด (เส้นทางที่ติด `@NoThrottle` ไม่จ่ายเลย)
 * ตั้ง `THROTTLE_STORE=memory` เพื่อกลับไปนับในหน่วยความจำอย่างเดียวได้
 * ถ้ารัน instance เดียวจริง ๆ — แต่ค่าเริ่มต้นคือ `db` เพราะค่าเริ่มต้น
 * ที่ถูกต้องสำคัญกว่าค่าเริ่มต้นที่เร็ว การ scale out แล้วเพดานเปลี่ยนเงียบ ๆ
 * คือความผิดพลาดที่ไม่มีใครสังเกตจนกว่าจะมีคนใช้ประโยชน์จากมัน
 */

export const THROTTLE_KEY = 'throttle';

export interface ThrottleOptions {
  /** จำนวนคำขอสูงสุดในหนึ่งช่วงเวลา */
  limit: number;
  /** ความยาวช่วงเวลา หน่วยวินาที */
  windowSecs: number;
}

export const Throttle = (limit: number, windowSecs: number) =>
  SetMetadata(THROTTLE_KEY, { limit, windowSecs } satisfies ThrottleOptions);

/** ยกเว้นการจำกัด เช่น health check ที่ระบบตรวจสอบยิงถี่โดยตั้งใจ */
export const NoThrottle = () => SetMetadata(THROTTLE_KEY, null);

interface Bucket {
  hits: number[];
}

interface RateRow {
  allowed: boolean;
  remaining: number;
  retry_after_secs: number;
}

@Injectable()
export class ThrottleGuard implements CanActivate {
  private readonly log = new Logger('Throttle');
  private readonly buckets = new Map<string, Bucket>();
  private lastSweep = Date.now();
  private lastDbWarn = 0;

  constructor(
    private readonly reflector: Reflector,
    private readonly config: ConfigService,
    private readonly db: DbService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (this.config.get('THROTTLE_ENABLED') === 'false') return true;
    if (ctx.getType() !== 'http') return true;

    const options = this.reflector.getAllAndOverride<ThrottleOptions | null>(
      THROTTLE_KEY,
      [ctx.getHandler(), ctx.getClass()],
    );

    // null แปลว่าตั้งใจยกเว้น ส่วน undefined แปลว่าไม่ได้ระบุ ให้ใช้ค่าเริ่มต้น
    if (options === null) return true;

    const limit = options?.limit ?? Number(this.config.get('THROTTLE_LIMIT') ?? 300);
    const windowSecs =
      options?.windowSecs ?? Number(this.config.get('THROTTLE_WINDOW_SECS') ?? 60);

    const req = ctx.switchToHttp().getRequest<Request>();
    const res = ctx.switchToHttp().getResponse<Response>();

    // แยกถังตามเส้นทางด้วย เพื่อไม่ให้การยิง endpoint หนึ่งกินโควตาของอีกอันจนหมด
    const ip = this.clientIp(req);
    const key = `${ip}|${req.method}|${req.route?.path ?? req.path}`;

    const local = this.checkLocal(key, limit, windowSecs);
    if (!local.allowed) {
      this.reject(res, limit, local.retryAfter);
    }

    let remaining = local.remaining;

    if (this.config.get('THROTTLE_STORE') !== 'memory') {
      const shared = await this.checkShared(key, limit, windowSecs);
      if (shared && !shared.allowed) {
        this.reject(res, limit, shared.retry_after_secs);
      }
      if (shared) remaining = Math.min(remaining, shared.remaining);
    }

    res.setHeader('RateLimit-Limit', String(limit));
    res.setHeader('RateLimit-Remaining', String(remaining));
    return true;
  }

  /** ตัวนับประจำโปรเซส — หน้าต่างเลื่อนจริง ไม่ใช่ค่าประมาณ */
  private checkLocal(
    key: string,
    limit: number,
    windowSecs: number,
  ): { allowed: boolean; remaining: number; retryAfter: number } {
    const now = Date.now();
    const windowMs = windowSecs * 1000;

    this.sweep(now, windowMs);

    const bucket = this.buckets.get(key) ?? { hits: [] };
    bucket.hits = bucket.hits.filter((t) => now - t < windowMs);

    if (bucket.hits.length >= limit) {
      this.buckets.set(key, bucket);
      return {
        allowed: false,
        remaining: 0,
        retryAfter: Math.ceil((windowMs - (now - bucket.hits[0])) / 1000),
      };
    }

    bucket.hits.push(now);
    this.buckets.set(key, bucket);
    return { allowed: true, remaining: limit - bucket.hits.length, retryAfter: 0 };
  }

  /**
   * ตัวนับที่ใช้ร่วมกันทุก instance
   *
   * ─── ทำไมยอมให้ผ่านเมื่อฐานข้อมูลมีปัญหา ───
   * ตัวจำกัดคำขอที่ทำให้ทั้งระบบตอบไม่ได้เมื่อฐานข้อมูลสะดุด เสียหายกว่า
   * สิ่งที่มันป้องกัน และเส้นทางที่อ่อนไหวทุกเส้นก็ต้องใช้ฐานข้อมูลอยู่ดี
   * — ฐานข้อมูลล่มแปลว่ามันทำอะไรไม่ได้อยู่แล้ว ตัวนับในหน่วยความจำยัง
   * ทำงานอยู่ตลอดจึงไม่ได้เปิดโล่ง
   */
  private async checkShared(
    key: string,
    limit: number,
    windowSecs: number,
  ): Promise<RateRow | null> {
    try {
      // ต้องเป็น queryWithoutContext() ไม่ใช่ query() — ตัวจำกัดคำขอทำงาน
      // ก่อน AuthGuard จึงไม่มีบริบทผู้ใช้ให้ตั้ง และ query() โยนทิ้งทันที
      // เมื่อไม่มีบริบท ซึ่งจะทำให้ตัวนับร่วมไม่เคยถูกเรียกเลยสักครั้ง
      // โดยระบบยังตอบ 429 จากตัวนับในหน่วยความจำได้ถูกต้อง — ล้มเหลวเงียบ
      // แบบที่มองไม่ออกจากภายนอกเลย (RATE-07 จับข้อนี้ได้ตอนเขียนครั้งแรก)
      const rows = await this.db.queryWithoutContext<RateRow>(
        'select allowed, remaining, retry_after_secs from request_rate_hit($1, $2, $3)',
        [this.bucketKey(key), limit, windowSecs],
      );
      return rows[0] ?? null;
    } catch (e) {
      // เตือนอย่างมากนาทีละครั้ง — ถ้าฐานข้อมูลล่ม ทุกคำขอจะเข้าทางนี้
      // แล้ว log จะกลบเหตุผลจริงจนหาไม่เจอ
      const now = Date.now();
      if (now - this.lastDbWarn > 60_000) {
        this.lastDbWarn = now;
        this.log.warn(
          `นับคำขอร่วมทุก instance ไม่ได้ ใช้ตัวนับในหน่วยความจำแทนชั่วคราว — ${
            (e as Error).message
          }`,
        );
      }
      return null;
    }
  }

  /**
   * คีย์ของถัง — เก็บเป็นค่าแฮชเพราะไอพีเป็นข้อมูลส่วนบุคคลตาม PDPA
   * หลักเดียวกับ `login_attempt.ip_hash` ที่ใช้ IP_HASH_SECRET อยู่แล้ว
   */
  private bucketKey(key: string): Buffer {
    const pepper = this.config.get<string>('IP_HASH_SECRET') ?? 'vec-sms';
    return createHash('sha256').update(`${pepper}:${key}`).digest();
  }

  private reject(res: Response, limit: number, retryAfter: number): never {
    res.setHeader('Retry-After', String(retryAfter));
    res.setHeader('RateLimit-Limit', String(limit));
    res.setHeader('RateLimit-Remaining', '0');

    throw new HttpException(
      {
        statusCode: HttpStatus.TOO_MANY_REQUESTS,
        message: `คำขอถี่เกินไป ลองใหม่อีกครั้งใน ${retryAfter} วินาที`,
        error: 'Too Many Requests',
      },
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }

  /**
   * ไอพีของผู้เรียกจริง
   *
   * เชื่อ X-Forwarded-For เฉพาะเมื่อตั้ง TRUST_PROXY=true เท่านั้น
   * เพราะถ้าเชื่อเสมอ ใครก็ปลอมเฮดเดอร์นี้เพื่อให้ได้ถังใหม่ทุกคำขอได้
   * ซึ่งทำให้การจำกัดจำนวนครั้งไร้ผลทั้งหมด
   */
  private clientIp(req: Request): string {
    if (this.config.get('TRUST_PROXY') === 'true') {
      const forwarded = req.header('x-forwarded-for');
      if (forwarded) return forwarded.split(',')[0].trim();
    }
    return req.ip ?? req.socket?.remoteAddress ?? 'unknown';
  }

  /** ล้างถังที่หมดอายุ กันหน่วยความจำโตไม่หยุดเมื่อไอพีเปลี่ยนไปเรื่อย ๆ */
  private sweep(now: number, windowMs: number): void {
    if (now - this.lastSweep < 60_000) return;
    this.lastSweep = now;
    for (const [key, bucket] of this.buckets) {
      if (bucket.hits.every((t) => now - t >= windowMs)) this.buckets.delete(key);
    }
  }
}

import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
  SetMetadata,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { Request, Response } from 'express';

/**
 * จำกัดจำนวนคำขอต่อไอพี
 *
 * ─── ขอบเขตที่ตัวนี้ทำได้และทำไม่ได้ ───
 * ตัวนับอยู่ในหน่วยความจำของโปรเซส จึงถูกแบ่งตามจำนวน instance —
 * รัน 3 instance แปลว่าเพดานจริงเป็นสามเท่าของที่ตั้งไว้ และรีสตาร์ท
 * ทีเดียวตัวนับก็คืนค่าใหม่
 *
 * ยอมรับข้อจำกัดนี้ได้สำหรับ endpoint ทั่วไป เพราะเป้าหมายคือกันการยิงรัว
 * จนเซิร์ฟเวอร์ล้ม ไม่ใช่การบังคับโควตาที่แม่นยำ
 *
 * **แต่การเข้าสู่ระบบไม่ยอมรับข้อจำกัดนี้** เพราะโควตาที่คลาดเคลื่อนแปลว่า
 * ผู้โจมตีเดารหัสผ่านได้มากกว่าที่ตั้งใจ การนับของ /auth/login จึงอยู่ใน
 * ฐานข้อมูลผ่าน login_rate_status() ซึ่งนับรวมทุก instance
 * ดู migration 0021 — สองชั้นนี้ทำงานคนละหน้าที่กัน
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

@Injectable()
export class ThrottleGuard implements CanActivate {
  private readonly buckets = new Map<string, Bucket>();
  private lastSweep = Date.now();

  constructor(
    private readonly reflector: Reflector,
    private readonly config: ConfigService,
  ) {}

  canActivate(ctx: ExecutionContext): boolean {
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
    const key = `${this.clientIp(req)}|${req.method}|${req.route?.path ?? req.path}`;
    const now = Date.now();
    const windowMs = windowSecs * 1000;

    this.sweep(now, windowMs);

    const bucket = this.buckets.get(key) ?? { hits: [] };
    bucket.hits = bucket.hits.filter((t) => now - t < windowMs);

    if (bucket.hits.length >= limit) {
      const retryAfter = Math.ceil((windowMs - (now - bucket.hits[0])) / 1000);
      res.setHeader('Retry-After', String(retryAfter));
      res.setHeader('RateLimit-Limit', String(limit));
      res.setHeader('RateLimit-Remaining', '0');
      this.buckets.set(key, bucket);

      throw new HttpException(
        {
          statusCode: HttpStatus.TOO_MANY_REQUESTS,
          message: `คำขอถี่เกินไป ลองใหม่อีกครั้งใน ${retryAfter} วินาที`,
          error: 'Too Many Requests',
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    bucket.hits.push(now);
    this.buckets.set(key, bucket);

    res.setHeader('RateLimit-Limit', String(limit));
    res.setHeader('RateLimit-Remaining', String(limit - bucket.hits.length));
    return true;
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

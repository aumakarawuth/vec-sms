import {
  CallHandler,
  ExecutionContext,
  Injectable,
  Logger,
  NestInterceptor,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { Request } from 'express';
import { createHash } from 'node:crypto';
import { tap } from 'rxjs';
import { DbService } from '../db/db.service';
import { RequestContext, UserContext } from '../context/request-context';

/**
 * บันทึกว่าใครเข้าถึงหรือเปลี่ยนแปลงข้อมูลของใคร
 *
 * ─── ทำไมต้องมี ทั้งที่มี grade_ledger อยู่แล้ว ───
 * grade_ledger บันทึกเฉพาะการ **เขียน** ผลการเรียน แต่การรั่วไหลของข้อมูล
 * ส่วนบุคคลส่วนใหญ่คือการ **อ่าน** แล้วคัดลอกออกไป ซึ่งไม่ทิ้งร่องรอยเลย
 * ในระบบที่บันทึกเฉพาะการเขียน
 *
 * PDPA มาตรา 37 กำหนดให้ผู้ควบคุมข้อมูลมีมาตรการตรวจสอบย้อนหลังได้
 * และมาตรา 30 ให้สิทธิเจ้าของข้อมูลขอดูว่าข้อมูลตนถูกใช้อย่างไร
 * ทั้งสองข้อตอบไม่ได้เลยถ้าไม่มีบันทึกการเข้าถึง
 *
 * ─── บันทึกอะไรบ้าง ───
 * ทุกคำขอที่เปลี่ยนแปลงข้อมูล (ไม่ใช่ GET) บันทึกอัตโนมัติ
 * ส่วนการอ่านบันทึกเฉพาะที่ติด @Audit() ไว้ เพราะการบันทึกทุก GET
 * จะทำให้ตารางโตเร็วกว่าข้อมูลจริงหลายเท่าจนหาอะไรไม่เจอ
 * และค่าใช้จ่ายในการเก็บสูงกว่าประโยชน์
 *
 * ─── ทำไมบันทึกล้มเหลวไม่ทำให้คำขอล้มเหลว ───
 * ถ้าบันทึกไม่ได้แล้วปฏิเสธคำขอ ปัญหาที่ตารางบันทึกจะทำให้ระบบทั้งระบบหยุด
 * ซึ่งแลกไม่คุ้ม แต่ต้อง log ระดับ error ไว้ให้เห็น เพราะช่วงที่บันทึกหาย
 * คือช่วงที่ตรวจสอบย้อนหลังไม่ได้
 */

export const AUDIT_KEY = 'audit';

export interface AuditOptions {
  /** ชื่อสิ่งที่ถูกเข้าถึง เช่น 'student' 'invoice' */
  entity: string;
  /** พารามิเตอร์ที่เป็น id ของเจ้าของข้อมูล ถ้ามี */
  subjectParam?: string;
}

/** ทำเครื่องหมายว่า endpoint นี้ต้องบันทึกแม้เป็นการอ่าน */
export const Audit = (entity: string, subjectParam?: string) =>
  SetMetadata(AUDIT_KEY, { entity, subjectParam } satisfies AuditOptions);

@Injectable()
export class AuditInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditInterceptor.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly db: DbService,
    private readonly config: ConfigService,
  ) {}

  intercept(ctx: ExecutionContext, next: CallHandler) {
    if (ctx.getType() !== 'http') return next.handle();
    if (this.config.get('AUDIT_ENABLED') === 'false') return next.handle();

    const req = ctx.switchToHttp().getRequest<Request>();
    const options = this.reflector.getAllAndOverride<AuditOptions | undefined>(
      AUDIT_KEY,
      [ctx.getHandler(), ctx.getClass()],
    );

    const method = req.method.toUpperCase();
    const isMutation = method !== 'GET' && method !== 'OPTIONS';

    // อ่านที่ไม่ได้ติด @Audit() ไม่บันทึก มิฉะนั้นตารางจะโตเร็วกว่าข้อมูลจริง
    if (!isMutation && !options) return next.handle();

    // ต้องจับบริบทตรงนี้ ไม่ใช่ใน callback ของ tap
    //
    // ContextInterceptor ใช้ RequestContext.run(ctx, () => next.handle())
    // ซึ่งครอบแค่ช่วงที่ **สร้าง** observable ส่วน callback ของ tap ยิงทีหลัง
    // ตอนที่ observable ปล่อยค่า ซึ่งหลุดออกจาก AsyncLocalStorage ไปแล้ว
    // ถ้าไปอ่าน RequestContext.get() ในนั้นจะได้ undefined เสมอ
    // แล้วบันทึกจะเงียบหายไปทั้งหมดโดยไม่มี error ให้เห็น
    const userCtx = RequestContext.get();
    if (!userCtx) return next.handle();

    /*
     * ─── ทำไมข้ามคำขอของฝั่งผู้ให้บริการ ───
     * access_log มี institution_id แบบ not null และนโยบายของมันอ่านได้
     * เฉพาะคนในวิทยาลัยนั้น บริบทของผู้ให้บริการไม่มีวิทยาลัย การเขียนลง
     * ตารางนี้จึงล้มทุกครั้ง แล้ว log จะเต็มไปด้วยข้อความ "บันทึกไม่สำเร็จ"
     * ที่กลบข้อผิดพลาดจริงจนมองไม่เห็น
     *
     * การกระทำของผู้ให้บริการถูกบันทึกที่ platform_action_log แทน ซึ่งเป็น
     * ตารางที่ **ผู้ให้บริการเองแก้และลบไม่ได้** ต่างจาก access_log ที่เป็น
     * บันทึกภายในของแต่ละวิทยาลัย (ดู migration 0040)
     */
    if (!userCtx.institutionId) return next.handle();

    return next.handle().pipe(
      tap({
        next: (body) => void this.record(req, userCtx, options, body, true),
        // คำขอที่ถูกปฏิเสธก็ต้องบันทึก — ความพยายามเข้าถึงข้อมูลที่ไม่มีสิทธิ์
        // คือสิ่งที่ผู้ตรวจสอบสนใจที่สุด ไม่ใช่ครั้งที่สำเร็จ
        error: () => void this.record(req, userCtx, options, null, false),
      }),
    );
  }

  private async record(
    req: Request,
    userCtx: UserContext,
    options: AuditOptions | undefined,
    body: unknown,
    succeeded: boolean,
  ): Promise<void> {
    try {
      const entity = options?.entity ?? this.entityFrom(req);
      const params = (req.params ?? {}) as Record<string, string>;

      await this.db.runAs(userCtx, (c) =>
        c.query(
        `insert into access_log
           (institution_id, actor_id, actor_role, action, entity, entity_id,
            subject_id, route, detail, ip_hash)
         values (current_institution_id(), current_actor_id(), $1, $2::audit_action,
                 $3, $4, $5, $6, $7::jsonb, $8)`,
        [
          userCtx.role,
          this.actionFrom(req.method),
          entity,
          this.uuidOrNull(params.id ?? params[`${entity}Id`]),
          this.uuidOrNull(options?.subjectParam ? params[options.subjectParam] : undefined),
          `${req.method} ${req.route?.path ?? req.path}`,
          JSON.stringify({
            succeeded,
            requestId: userCtx.requestId,
            // ไม่เก็บ body ของคำขอ เพราะมีรหัสผ่านและข้อมูลส่วนบุคคลปนอยู่
            // การเก็บไว้เท่ากับสร้างสำเนาข้อมูลอ่อนไหวชุดที่สอง
            resultCount: Array.isArray(body) ? body.length : undefined,
          }),
          this.hashIp(req),
        ],
        ),
      );
    } catch (err) {
      this.logger.error(
        `บันทึกการเข้าถึงไม่สำเร็จ — ช่วงนี้ตรวจสอบย้อนหลังไม่ได้: ${(err as Error).message}`,
      );
    }
  }

  private actionFrom(method: string): string {
    switch (method.toUpperCase()) {
      case 'POST':
        return 'create';
      case 'PATCH':
      case 'PUT':
        return 'update';
      case 'DELETE':
        return 'delete';
      default:
        return 'read';
    }
  }

  /** เดาชื่อสิ่งที่ถูกเข้าถึงจากส่วนแรกของเส้นทาง */
  private entityFrom(req: Request): string {
    const path = req.route?.path ?? req.path;
    const first = path.replace(/^\/?(api\/v1\/)?/, '').split('/')[0];
    return first || 'unknown';
  }

  private uuidOrNull(value?: string): string | null {
    return value && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
      ? value
      : null;
  }

  /** ไอพีเป็นข้อมูลส่วนบุคคลตาม PDPA เก็บเป็นค่าแฮชเหมือน login_attempt */
  private hashIp(req: Request): Buffer | null {
    const ip =
      this.config.get('TRUST_PROXY') === 'true'
        ? req.header('x-forwarded-for')?.split(',')[0].trim() ?? req.ip
        : req.ip;
    if (!ip) return null;
    const pepper = this.config.get<string>('IP_HASH_SECRET') ?? 'vec-sms';
    return createHash('sha256').update(`${pepper}:${ip}`).digest();
  }
}

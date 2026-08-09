import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { DatabaseError } from 'pg';

/**
 * แปลงข้อผิดพลาดจาก PostgreSQL เป็นสถานะ HTTP ที่ถูกต้อง
 *
 * ─── ทำไมต้องมีตัวนี้ ───
 * กฎทางธุรกิจจำนวนมากของระบบนี้อยู่ในฐานข้อมูล ไม่ใช่ในโค้ด เช่น
 *   - ผลการเรียนแก้ทับไม่ได้
 *   - ฉบับหลักสูตรห้ามครอบคลุมปีเข้าศึกษาทับกัน
 *   - รายการบัญชีต้องเดบิตเท่ากับเครดิต
 *   - ลงทะเบียนไม่ได้เพราะติดเงื่อนไข
 * ข้อความเหล่านั้นเป็นภาษาไทยที่เขียนไว้ให้ผู้ใช้อ่านรู้เรื่องอยู่แล้ว
 * ตัวกรองนี้จึงส่งต่อข้อความจริงแทนที่จะกลบเป็น 500 Internal Server Error
 */
@Catch()
export class PgExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(PgExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const http = host.switchToHttp();
    const res = http.getResponse<Response>();
    const req = http.getRequest<Request>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      res.status(status).json(this.body(status, exception.getResponse(), req));
      return;
    }

    if (this.isPgError(exception)) {
      const mapped = this.mapPgError(exception);
      if (mapped.status >= 500) {
        this.logger.error(
          `${exception.code} ${exception.message}`,
          exception.stack,
        );
      }
      res.status(mapped.status).json(
        this.body(mapped.status, { message: mapped.message, code: exception.code }, req),
      );
      return;
    }

    // ─── คำขอใหญ่เกินเพดาน ───────────────────────────────────────
    //
    // body-parser โยน PayloadTooLargeError ซึ่งไม่ใช่ HttpException
    // ถ้าไม่ดักตรงนี้จะกลายเป็น 500 ซึ่งบอกผู้เรียกไม่ได้ว่าผิดอะไร
    // และคนที่นำเข้าไฟล์ใหญ่เกินจะเข้าใจว่าระบบพัง แทนที่จะรู้ว่าต้องแบ่งไฟล์
    if (this.isPayloadTooLarge(exception)) {
      const status = HttpStatus.PAYLOAD_TOO_LARGE;
      res.status(status).json(
        this.body(
          status,
          {
            message:
              'ข้อมูลที่ส่งมาใหญ่เกินกำหนด — ถ้าเป็นการนำเข้าข้อมูล ให้แบ่งไฟล์ให้เล็กลงแล้วส่งทีละส่วน',
            error: 'Payload Too Large',
          },
          req,
        ),
      );
      return;
    }

    const err = exception as Error;
    this.logger.error(err?.message ?? String(exception), err?.stack);
    res
      .status(HttpStatus.INTERNAL_SERVER_ERROR)
      .json(this.body(HttpStatus.INTERNAL_SERVER_ERROR, { message: 'เกิดข้อผิดพลาดภายในระบบ' }, req));
  }

  private isPayloadTooLarge(e: unknown): boolean {
    return (
      typeof e === 'object' &&
      e !== null &&
      ('type' in e ? (e as { type?: string }).type === 'entity.too.large' : false)
    );
  }

  private isPgError(e: unknown): e is DatabaseError {
    return (
      typeof e === 'object' && e !== null && 'code' in e && 'severity' in e
    );
  }

  private mapPgError(e: DatabaseError): { status: number; message: string } {
    switch (e.code) {
      // raise exception จากฟังก์ชันของเรา — ข้อความเป็นภาษาไทยพร้อมแสดงผู้ใช้
      case 'P0001':
        return { status: HttpStatus.UNPROCESSABLE_ENTITY, message: e.message };

      // register_courses ใช้ errcode นี้เมื่อยังติดเงื่อนไขที่ห้ามผ่าน
      case '23514':
        return { status: HttpStatus.UNPROCESSABLE_ENTITY, message: e.message };

      case '23505':
        return {
          status: HttpStatus.CONFLICT,
          message: `ข้อมูลซ้ำกับที่มีอยู่แล้ว (${e.constraint ?? 'unique'})`,
        };

      case '23P01':
        return {
          status: HttpStatus.CONFLICT,
          message: `ข้อมูลทับซ้อนกับรายการที่มีอยู่ (${e.constraint ?? 'exclusion'})`,
        };

      case '23503':
        return {
          status: HttpStatus.BAD_REQUEST,
          message: `อ้างถึงข้อมูลที่ไม่มีอยู่จริง (${e.constraint ?? 'foreign key'})`,
        };

      case '23502':
        return {
          status: HttpStatus.BAD_REQUEST,
          message: `ข้อมูลที่จำเป็นขาดหายไป (${e.column ?? 'not null'})`,
        };

      case '42501':
        return {
          status: HttpStatus.FORBIDDEN,
          message: 'ไม่มีสิทธิ์ดำเนินการนี้',
        };

      case '57014':
        return {
          status: HttpStatus.REQUEST_TIMEOUT,
          message: 'คำสั่งใช้เวลานานเกินกำหนดและถูกยกเลิก',
        };

      default:
        return {
          status: HttpStatus.INTERNAL_SERVER_ERROR,
          message: 'เกิดข้อผิดพลาดในการเข้าถึงข้อมูล',
        };
    }
  }

  private body(status: number, payload: unknown, req: Request) {
    const base =
      typeof payload === 'string' ? { message: payload } : (payload as object);
    return {
      statusCode: status,
      path: req.originalUrl,
      timestamp: new Date().toISOString(),
      ...base,
    };
  }
}

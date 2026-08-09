import {
  ArgumentMetadata,
  BadRequestException,
  Injectable,
  PipeTransform,
} from '@nestjs/common';
import { applyDecorators } from '@nestjs/common';
import { Matches } from 'class-validator';

/**
 * PostgreSQL ยอมรับ uuid ทุกรูปแบบที่เป็นเลขฐานสิบหก 8-4-4-4-12
 * ไม่สนใจว่าเป็นเวอร์ชันไหนตาม RFC 4122
 *
 * ส่วน @IsUUID() และ ParseUUIDPipe ของ Nest ตรวจเวอร์ชันด้วย จึงปฏิเสธรหัส
 * ที่กำหนดเองในไฟล์ seed และรหัสที่ระบบภายนอกส่งมา ทำให้ชั้นแอปเข้มงวดกว่า
 * ฐานข้อมูลโดยไม่มีเหตุผล ตัวตรวจในไฟล์นี้จึงยึดตามสิ่งที่ฐานข้อมูลรับจริง
 */
export const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const IsUuid = () =>
  applyDecorators(
    Matches(UUID_PATTERN, { message: '$property ต้องเป็นรหัสรูปแบบ UUID' }),
  );

export const IsUuidArray = () =>
  applyDecorators(
    Matches(UUID_PATTERN, {
      each: true,
      message: '$property ทุกรายการต้องเป็นรหัสรูปแบบ UUID',
    }),
  );

@Injectable()
export class ParseUuidPipe implements PipeTransform<string, string> {
  transform(value: string, metadata: ArgumentMetadata): string {
    if (!UUID_PATTERN.test(value ?? '')) {
      throw new BadRequestException(
        `${metadata.data ?? 'พารามิเตอร์'} ต้องเป็นรหัสรูปแบบ UUID`,
      );
    }
    return value;
  }
}

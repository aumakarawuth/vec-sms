/**
 * ปฏิเสธวันที่รูปแบบ ISO ที่ใส่ปีพุทธศักราชมา ทุกช่องของทุกคำขอ
 *
 * ─── ทำไมต้องมี ───
 * ทั้งระบบแสดงปี พ.ศ. ให้ผู้ใช้เห็น แต่รับ/เก็บวันที่เป็น ISO ปี ค.ศ.
 * ส่วน `@IsISO8601()` ตรวจแค่รูปแบบตัวเลข "2569-03-31" จึงผ่านแล้วถูกเก็บเป็น
 * วันที่ในปี ค.ศ. 2569 (อีก 500 กว่าปีข้างหน้า) โดยไม่มี error — แล้วไปโผล่ตอน
 * แสดงผลเป็น "31 มี.ค. 3112" หรือทำให้เงื่อนไขช่วงวันที่ผิดทั้งชุดเงียบ ๆ
 * เคยแก้เฉพาะช่องวางรายการธนาคารที่หน้าจอ (บทเรียนข้อ 23) แต่ทางที่ไม่ผ่าน
 * หน้าจอ (นำเข้าไฟล์ · สคริปต์ · เทสต์) ยังเข้าได้ทุกช่อง จึงย้ายมากันที่จุดเดียว
 * ก่อนตัวตรวจของแต่ละ DTO
 *
 * ─── ทำไมปฏิเสธ ไม่แปลงให้เอง ───
 * ปีที่เกิน 2400 แทบไม่มีทางเป็น ค.ศ. ที่ตั้งใจ แต่การลบ 543 เงียบ ๆ แปลว่า
 * ต้นทางที่ส่งผิดจะไม่มีวันรู้ตัว และวันที่ที่เกิดจากการพิมพ์ผิดอื่น ๆ ก็จะถูก
 * "ซ่อม" ไปด้วย ข้อความบอกตรง ๆ ว่าช่องไหนและควรเป็นปีอะไร
 *
 * จับเฉพาะสตริงที่ขึ้นต้นด้วยรูป YYYY-MM-DD จริง — เลขที่เอกสาร ปีการศึกษา
 * แบบตัวเลขล้วน (2569) หรือรหัสที่มีขีดแต่ไม่ใช่วันที่ ไม่ถูกแตะ
 */
import { BadRequestException, PipeTransform } from '@nestjs/common';

const ISO_DATE = /^(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])(?:$|T)/;
const MAX_CE_YEAR = 2400;

function findBuddhistDate(value: unknown, path: string, depth = 0): string | null {
  if (depth > 6 || value === null || value === undefined) return null;
  if (typeof value === 'string') {
    const m = ISO_DATE.exec(value);
    return m && Number(m[1]) > MAX_CE_YEAR ? `${path || 'ค่า'} = ${value}` : null;
  }
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) {
      const hit = findBuddhistDate(value[i], `${path}[${i}]`, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  if (typeof value === 'object') {
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      const hit = findBuddhistDate(v, path ? `${path}.${k}` : k, depth + 1);
      if (hit) return hit;
    }
  }
  return null;
}

export class RejectBuddhistYearPipe implements PipeTransform {
  transform(value: unknown) {
    const hit = findBuddhistDate(value, '');
    if (hit) {
      throw new BadRequestException(
        `วันที่ต้องเป็นปีคริสต์ศักราช (${hit}) — ถ้าเป็นปี พ.ศ. ให้ลบ 543 ก่อนส่ง`,
      );
    }
    return value;
  }
}

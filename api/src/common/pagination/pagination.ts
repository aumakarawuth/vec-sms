import { BadRequestException } from '@nestjs/common';

/**
 * การแบ่งหน้าที่มีเพดานตายตัว
 *
 * ─── ทำไมต้องมีเพดานที่ผู้เรียกเพิ่มไม่ได้ ───
 * endpoint ที่คืนทุกแถวทำงานได้ดีมากตอนทดสอบกับข้อมูลตัวอย่างสิบแถว
 * แล้วล่มตอนวิทยาลัยจริงมีนักศึกษาห้าพันคน ซึ่งเป็นจังหวะที่แย่ที่สุด
 *
 * ที่สำคัญกว่าคือมันเป็นช่องทำให้ระบบล่มที่ถูกที่สุดสำหรับผู้โจมตี —
 * ยิงคำขอเดียวที่ดึงทุกแถวพร้อมกันหลายสิบครั้ง ใช้ทั้งหน่วยความจำของ
 * เซิร์ฟเวอร์และ connection ของฐานข้อมูลจนหมด โดยไม่ต้องใช้ทรัพยากรอะไรเลย
 *
 * เพดานจึงต้องอยู่ฝั่งเซิร์ฟเวอร์และผู้เรียกเพิ่มไม่ได้ ไม่ใช่ค่าเริ่มต้น
 * ที่ส่ง ?limit= มาทับได้
 */

/** เพดานสูงสุดที่ endpoint ใดก็เพิ่มเกินนี้ไม่ได้ */
export const MAX_PAGE_SIZE = 200;
export const DEFAULT_PAGE_SIZE = 50;

export interface PageParams {
  limit: number;
  offset: number;
}

export interface Page<T> {
  items: T[];
  limit: number;
  offset: number;
  /** มีข้อมูลต่ออีกไหม — คำนวณจากการดึงเกินมาหนึ่งแถว ไม่ใช่ count(*) */
  hasMore: boolean;
}

/**
 * อ่านค่าแบ่งหน้าจาก query string
 *
 * ค่าที่เกินเพดานถูกลดลงเงียบ ๆ ไม่ใช่ปฏิเสธคำขอ เพราะผู้เรียกที่ขอมากเกิน
 * มักไม่ได้ตั้งใจโจมตี แค่อยากได้ครบ การลดให้แล้วบอกจำนวนจริงกลับไป
 * ใช้งานได้ทันที ส่วนค่าที่ผิดรูปแบบถึงจะปฏิเสธ เพราะแปลว่าฝั่งเรียกเขียนผิด
 */
export function parsePage(
  limitRaw?: string,
  offsetRaw?: string,
  defaultLimit = DEFAULT_PAGE_SIZE,
): PageParams {
  const limit = limitRaw === undefined ? defaultLimit : Number(limitRaw);
  const offset = offsetRaw === undefined ? 0 : Number(offsetRaw);

  if (!Number.isFinite(limit) || limit < 1) {
    throw new BadRequestException('limit ต้องเป็นจำนวนเต็มบวก');
  }
  if (!Number.isFinite(offset) || offset < 0) {
    throw new BadRequestException('offset ต้องเป็นจำนวนเต็มไม่ติดลบ');
  }

  return {
    limit: Math.min(Math.floor(limit), MAX_PAGE_SIZE),
    offset: Math.floor(offset),
  };
}

/**
 * ตัดแถวที่ดึงเกินมาออก แล้วบอกว่ายังมีต่อไหม
 *
 * ─── ทำไมไม่ใช้ count(*) ───
 * การนับทั้งตารางเพื่อบอกจำนวนหน้าต้องสแกนทุกแถวที่ตรงเงื่อนไข
 * ซึ่งแพงกว่าการดึงข้อมูลหน้าเดียวหลายเท่าเมื่อข้อมูลเยอะ
 * และหน้าจอส่วนใหญ่ต้องการแค่ปุ่ม "ถัดไป" ไม่ใช่เลขหน้าทั้งหมด
 *
 * วิธีนี้จึงขอ limit+1 แถว ถ้าได้เกินมาแปลว่ายังมีต่อ
 */
export function toPage<T>(rows: T[], params: PageParams): Page<T> {
  const hasMore = rows.length > params.limit;
  return {
    items: hasMore ? rows.slice(0, params.limit) : rows,
    limit: params.limit,
    offset: params.offset,
    hasMore,
  };
}

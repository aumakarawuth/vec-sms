/**
 * การจัดรูปแบบที่ใช้ทั้งระบบ
 *
 * ─── ทำไมปีพุทธศักราชอยู่ที่นี่ที่เดียว ───
 * ทั้งโปรเจกต์ใช้ พ.ศ. ในข้อมูลและเอกสาร ถ้าปล่อยให้แต่ละหน้าจอ +543 เอง
 * จะมีสักหน้าที่ลืม แล้วเอกสารที่ออกไปจะมีปีผิด 543 ปีโดยไม่มีใครทัน
 * สังเกตจนกว่าจะมีคนถือกระดาษมาถาม
 */

const TH = 'th-TH';

/** วันที่จากฐานข้อมูล (ISO หรือ YYYY-MM-DD) → 15 พ.ค. 2569 */
export function thaiDate(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString(TH, { day: 'numeric', month: 'short', year: 'numeric' });
}

/** วันที่พร้อมเวลา — ใช้ในบันทึกการเข้าถึงและประวัติการทำรายการ */
export function thaiDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString(TH, {
    day: 'numeric', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

/** จำนวนเงิน — ทศนิยมสองตำแหน่งเสมอ เพราะเป็นตัวเลขที่ต้องกระทบยอดได้ */
export function money(value: number | string | null | undefined): string {
  const n = typeof value === 'string' ? Number(value) : value;
  if (n === null || n === undefined || Number.isNaN(n)) return '—';
  return n.toLocaleString(TH, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** หน่วยกิตและตัวเลขทั่วไปที่มีทศนิยมได้ */
export function num(value: number | string | null | undefined, digits = 1): string {
  const n = typeof value === 'string' ? Number(value) : value;
  if (n === null || n === undefined || Number.isNaN(n)) return '—';
  return n.toLocaleString(TH, { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

/** เปอร์เซ็นต์เวลาเรียน — ปัดทศนิยมหนึ่งตำแหน่ง */
export function pct(value: number | string | null | undefined): string {
  const n = typeof value === 'string' ? Number(value) : value;
  if (n === null || n === undefined || Number.isNaN(n)) return '—';
  return `${n.toLocaleString(TH, { maximumFractionDigits: 1 })}%`;
}

export const STUDENT_STATUS: Record<string, string> = {
  active: 'กำลังศึกษา',
  on_leave: 'พักการเรียน',
  suspended: 'ถูกพักการเรียน',
  graduated: 'สำเร็จการศึกษา',
  withdrawn: 'ลาออก',
  dismissed: 'พ้นสภาพ',
  // ชื่อใน enum คือ transferred_out — คีย์ที่สะกดไม่ตรงทำให้หน้าจอ
  // แสดงค่าดิบแทนคำไทยโดยไม่มีอะไรฟ้อง
  transferred_out: 'ย้ายสถานศึกษา',
};

export const TERM_STATUS: Record<string, string> = {
  planning: 'กำลังวางแผน',
  registration: 'ช่วงลงทะเบียน',
  open: 'กำลังเรียน',
  grading: 'ช่วงส่งเกรด',
  closed: 'ปิดภาคเรียน',
};

export const LEVEL: Record<string, string> = { PVC: 'ปวช.', PVS: 'ปวส.' };

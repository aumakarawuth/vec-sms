/**
 * ปฏิทินการศึกษาและกลุ่มเรียน — ข้อมูลที่แทบทุกหน้าจอต้องเลือกก่อนทำอะไร
 *
 * ─── ทำไมภาคเรียนอยู่ใน query string ───
 * เจ้าหน้าที่ส่งลิงก์หากันตลอด ("ดูห้องนี้หน่อย") ถ้าภาคเรียนอยู่ใน state
 * อย่างเดียว ลิงก์ที่ส่งไปจะเปิดมาคนละภาคกับที่ตั้งใจ แล้วอีกฝ่ายจะเห็น
 * ตัวเลขคนละชุดโดยไม่รู้ตัว
 */
import { useAsync } from '../ui/kit';
import { api, qs } from './api';

export interface Term {
  id: string;
  ordinal: number;
  kind: string;
  status: string;
  starts_on: string;
  ends_on: string;
  add_drop_ends_on: string | null;
  withdraw_ends_on: string | null;
  grade_due_on: string | null;
  category_id: string | null;
  short_name: string | null;
  sort_order: number;
  is_normal: boolean;
  registration_starts_on: string | null;
  gradebook_starts_on: string | null;
  payment_starts_on: string | null;
  payment_ends_on: string | null;
  audit_starts_on: string | null;
  audit_ends_on: string | null;
  year_be: number;
  academic_year_id: string;
}

export interface TermCategory {
  id: string;
  title: string;
  sort_order: number;
}

export interface Period {
  id: string;
  ordinal: number;
  title: string;
  short_name: string | null;
  starts_at: string | null;
  ends_at: string | null;
}

export const fetchPeriods = () => api.get<Period[]>('/academic/periods');

/** "1–2" → "1–2 (08:30–10:30)" เมื่อมีข้อมูลเวลาให้ทั้งคาบแรกและคาบสุดท้าย */
export function periodRangeLabel(periods: Period[], from: number, to: number): string {
  const base = from === to ? `${from}` : `${from}–${to}`;
  const p1 = periods.find((p) => p.ordinal === from);
  const p2 = periods.find((p) => p.ordinal === to);
  if (p1?.starts_at && p2?.ends_at) return `${base} (${p1.starts_at.slice(0, 5)}–${p2.ends_at.slice(0, 5)})`;
  return base;
}

/**
 * ใช้ตรงในหน้าจอที่ต้องแสดงเลขคาบเป็นเวลาจริง (จัดตารางสอน/ตารางสอบ)
 * โดยไม่ต้องส่ง props คาบเรียนไล่ผ่านทุกคอมโพเนนต์ย่อย
 */
export function usePeriodLabel() {
  const periods = useAsync(fetchPeriods, []);
  return (from: number, to: number) => periodRangeLabel(periods.data ?? [], from, to);
}

export interface Section {
  id: string;
  section_no: string;
  capacity: number;
  planned_periods: number;
  delivery_mode: string;
  is_locked: boolean;
  course_id: string;
  code: string;
  name_th: string;
  credits: string;
  teacher_id: string | null;
  teacher_name: string;
  room_name: string | null;
  enrolled: string | number;
}

export const fetchTerms = () => api.get<Term[]>('/academic/terms');

export const fetchSections = (termId: string, q?: string) =>
  api.get<Section[]>(`/academic/sections${qs({ termId, q })}`);

export function termLabel(t: Term): string {
  return `ภาคเรียนที่ ${t.ordinal}/${t.year_be}`;
}

/** ภาคเรียนที่ควรเลือกให้เองเมื่อยังไม่ได้เลือก — ที่กำลังเรียนอยู่ก่อนเสมอ */
export function defaultTerm(terms: Term[]): Term | undefined {
  return (
    terms.find((t) => t.status === 'open') ??
    terms.find((t) => t.status === 'grading') ??
    terms.find((t) => t.status === 'registration') ??
    terms[0]
  );
}

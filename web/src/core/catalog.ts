/**
 * ปฏิทินการศึกษาและกลุ่มเรียน — ข้อมูลที่แทบทุกหน้าจอต้องเลือกก่อนทำอะไร
 *
 * ─── ทำไมภาคเรียนอยู่ใน query string ───
 * เจ้าหน้าที่ส่งลิงก์หากันตลอด ("ดูห้องนี้หน่อย") ถ้าภาคเรียนอยู่ใน state
 * อย่างเดียว ลิงก์ที่ส่งไปจะเปิดมาคนละภาคกับที่ตั้งใจ แล้วอีกฝ่ายจะเห็น
 * ตัวเลขคนละชุดโดยไม่รู้ตัว
 */
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
  year_be: number;
  academic_year_id: string;
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

/**
 * ปีการศึกษาและภาคเรียนที่เลือกทั้งระบบ
 *
 * ─── ทำไมเลือกที่เดียวแล้วมีผลทั้งหน้าเว็บ ───
 * เดิมแต่ละหน้าจอมีดรอปดาวน์เลือกปี/ภาคเรียนของตัวเอง เจ้าหน้าที่ต้องเลือก
 * ซ้ำทุกครั้งที่เปลี่ยนหน้า ค่านี้เก็บใน localStorage ไม่ใช่ sessionStorage
 * เพราะเป็นแค่ตัวกรองการแสดงผล ไม่ใช่ความลับ และเจ้าหน้าที่มักตั้งค่าครั้งเดียว
 * ตอนต้นเทอมแล้วไม่อยากตั้งใหม่ทุกครั้งที่เปิดแท็บ (ต่างจาก token ที่ต้องหาย
 * เมื่อปิดแท็บ — ดู core/session.tsx)
 */
import {
  createContext, useContext, useEffect, useMemo, useState, type ReactNode,
} from 'react';
import { api } from './api';
import { defaultTerm, fetchTerms, type Term } from './catalog';

export interface AcademicYearOption { id: string; year_be: number; status?: string }

interface ScopeApi {
  years: AcademicYearOption[];
  terms: Term[];
  yearId: string;
  termId: string;
  year: AcademicYearOption | null;
  term: Term | null;
  termsInYear: Term[];
  setYearId: (id: string) => void;
  setTermId: (id: string) => void;
}

const Ctx = createContext<ScopeApi | null>(null);

export function useScope(): ScopeApi {
  const s = useContext(Ctx);
  if (!s) throw new Error('useScope ต้องอยู่ภายใต้ ScopeProvider');
  return s;
}

const YEAR_KEY = 'vecsms.scopeYearId';
const TERM_KEY = 'vecsms.scopeTermId';

export function ScopeProvider({ children }: { children: ReactNode }) {
  const [years, setYears] = useState<AcademicYearOption[]>([]);
  const [terms, setTerms] = useState<Term[]>([]);
  // แยกจาก terms.length === 0 เพราะ "ยังไม่ตอบกลับ" กับ "ตอบกลับแล้วแต่ไม่มี
  // ภาคเรียนเลย" ต้องแยกออกจากกัน มิฉะนั้นตัวเลือกปีเริ่มต้นจะแข่งกับคำตอบของ
  // /academic/terms ที่มาช้ากว่า แล้วค้างอยู่ที่ปีซึ่งยังไม่มีภาคเรียนเลย
  const [termsLoaded, setTermsLoaded] = useState(false);
  const [yearId, setYearIdState] = useState(() => localStorage.getItem(YEAR_KEY) ?? '');
  const [termId, setTermIdState] = useState(() => localStorage.getItem(TERM_KEY) ?? '');

  useEffect(() => {
    api.get<AcademicYearOption[]>('/academic/years').then(setYears).catch(() => {});
    fetchTerms().then((t) => { setTerms(t); setTermsLoaded(true); }).catch(() => setTermsLoaded(true));
  }, []);

  const setYearId = (id: string) => { setYearIdState(id); localStorage.setItem(YEAR_KEY, id); };
  const setTermId = (id: string) => { setTermIdState(id); localStorage.setItem(TERM_KEY, id); };

  /**
   * ยังไม่เคยเลือกปี หรือปีที่เคยเลือกไว้ถูกลบไปแล้ว — เลือกให้เองจากภาคเรียน
   * ที่กำลังเรียนอยู่จริง ไม่ใช่แค่ปีที่ พ.ศ. มากที่สุด เพราะปีการศึกษาที่เพิ่ง
   * เปิดไว้ล่วงหน้ายังไม่มีภาคเรียนเลยสักภาค เลือกปีนั้นแล้วหน้าจอจะว่างเปล่า
   * ทั้งที่ข้อมูลจริงทั้งหมดยังอยู่ปีก่อนหน้า
   */
  useEffect(() => {
    if (years.length === 0 || !termsLoaded) return;
    if (years.some((y) => y.id === yearId)) return;
    const active = defaultTerm(terms);
    const fromActiveTerm = active ? years.find((y) => y.id === active.academic_year_id) : undefined;
    const latest = fromActiveTerm ?? [...years].sort((a, b) => b.year_be - a.year_be)[0];
    if (latest) setYearId(latest.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [years, terms, termsLoaded, yearId]);

  const termsInYear = useMemo(() => terms.filter((t) => t.academic_year_id === yearId), [terms, yearId]);

  // ยังไม่มีภาคที่เลือก หรือภาคที่เลือกไว้ไม่ได้อยู่ในปีที่เลือกแล้ว — เลือกภาค
  // ที่กำลังเรียนอยู่ในปีนั้นให้เอง (เช่น เพิ่งเปลี่ยนปีการศึกษาที่ด้านบน)
  useEffect(() => {
    if (termsInYear.length === 0) return;
    if (termsInYear.some((t) => t.id === termId)) return;
    const fallback = defaultTerm(termsInYear) ?? termsInYear[0];
    if (fallback) setTermId(fallback.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [termsInYear, termId]);

  const value = useMemo<ScopeApi>(() => ({
    years,
    terms,
    yearId,
    termId,
    year: years.find((y) => y.id === yearId) ?? null,
    term: terms.find((t) => t.id === termId) ?? null,
    termsInYear,
    setYearId,
    setTermId,
  }), [years, terms, yearId, termId, termsInYear]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

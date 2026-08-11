/**
 * ตัวเลือกภาคเรียนที่ใช้ร่วมทุกหน้าจอ
 *
 * เก็บค่าไว้ใน query string ของ hash เพื่อให้ลิงก์ที่ส่งต่อกันเปิดมาตรงภาค
 * และเลือกภาคที่กำลังเรียนอยู่ให้เองเมื่อยังไม่ได้เลือก เพราะเป็นภาคที่
 * เจ้าหน้าที่ต้องการ 99% ของเวลา
 */
import { useEffect } from 'react';
import { defaultTerm, fetchTerms, termLabel, type Term } from '../core/catalog';
import { TERM_STATUS, thaiDate } from '../core/fmt';
import { navigate, useRoute } from '../core/router';
import { useAsync, type Async } from './kit';

export function useTermPicker(): {
  terms: Async<Term[]>;
  termId: string;
  term: Term | undefined;
  setTerm: (id: string) => void;
} {
  const route = useRoute();
  const terms = useAsync(fetchTerms, []);
  const fromUrl = route.query.get('termId') ?? '';

  const setTerm = (id: string) => {
    const q = new URLSearchParams(route.query);
    q.set('termId', id);
    navigate(`${route.path}?${q.toString()}`);
  };

  // ยังไม่ได้เลือก แต่โหลดรายการมาแล้ว — เลือกภาคที่กำลังเรียนอยู่ให้
  useEffect(() => {
    if (fromUrl || !terms.data?.length) return;
    const d = defaultTerm(terms.data);
    if (d) setTerm(d.id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [terms.data, fromUrl]);

  const termId = fromUrl;
  const term = terms.data?.find((t) => t.id === termId);

  return { terms, termId, term, setTerm };
}

export function TermSelect({
  terms,
  termId,
  onChange,
}: {
  terms: Term[];
  termId: string;
  onChange: (id: string) => void;
}) {
  return (
    <select value={termId} onChange={(e) => onChange(e.target.value)}>
      {terms.map((t) => (
        <option key={t.id} value={t.id}>
          {termLabel(t)} — {TERM_STATUS[t.status] ?? t.status}
        </option>
      ))}
    </select>
  );
}

/** แถบสรุปวันสำคัญของภาคที่เลือก — ใช้ตัดสินใจว่ายังลงทะเบียนทันไหม */
export function TermDates({ term }: { term: Term }) {
  return (
    <span className="sub">
      เรียน {thaiDate(term.starts_on)} – {thaiDate(term.ends_on)}
      {term.add_drop_ends_on && ` · เพิ่ม/ถอนถึง ${thaiDate(term.add_drop_ends_on)}`}
      {term.grade_due_on && ` · ส่งเกรด ${thaiDate(term.grade_due_on)}`}
    </span>
  );
}

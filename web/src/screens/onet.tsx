/**
 * ผลสอบ O-NET/V-NET — โครงตารางทั่วไป (ดูคอมเมนต์เต็มที่ migration 0071)
 *
 * ยังไม่ได้เทียบกับรูปแบบไฟล์จริงที่ สอศ./สทศ. ส่งมา วางจากตารางเป็นรายวิชา
 * รายคนได้เลย ไม่ต้องผ่านขั้นตรวจแยกเหมือนนำเข้าข้อมูลนักศึกษา เพราะแถวหนึ่ง
 * ผิดไม่ทำให้แถวอื่นเสีย (register_courses_bulk pattern) — เห็นผลได้ทันที
 */
import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { num } from '../core/fmt';
import type { Role } from '../core/session';
import { Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useCan } from '../ui/kit';

const ONET_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];

interface ResultRow {
  studentCode: string;
  examYearBe: string;
  subjectCode: string;
  subjectTh: string;
  score: number;
}

interface BulkOutcome {
  total: number; saved: number; failed: number;
  rows: { row_no: number; student_code: string; subject_code: string; status: string; detail: string | null }[];
}

interface SummaryRow {
  subject_code: string; subject_th: string; students: string;
  avg_score: string; min_score: string; max_score: string;
}

const SAMPLE = `69201010101\t2569\tTHAI\tภาษาไทย\t65.5
69201010101\t2569\tMATH\tคณิตศาสตร์\t58
69201010102\t2569\tTHAI\tภาษาไทย\t72`;

function parse(text: string): { rows: ResultRow[]; bad: number } {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const rows: ResultRow[] = [];
  let bad = 0;
  for (const line of lines) {
    const cells = line.split(/\t|,/).map((c) => c.trim());
    const [studentCode, examYearBe, subjectCode, subjectTh, scoreStr] = cells;
    const score = Number(scoreStr);
    if (!studentCode || !examYearBe || !subjectCode || !subjectTh || !Number.isFinite(score)) {
      bad += 1;
      continue;
    }
    rows.push({ studentCode, examYearBe, subjectCode, subjectTh, score });
  }
  return { rows, bad };
}

export function OnetScreen() {
  const canUse = useCan(...ONET_ROLES);
  const [text, setText] = useState('');
  const [examYearBe, setExamYearBe] = useState('2569');
  const [result, setResult] = useState<BulkOutcome | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [summary, setSummary] = useState<SummaryRow[] | null>(null);
  const [summaryLoaded, setSummaryLoaded] = useState(false);

  const { rows, bad } = useMemo(() => parse(text), [text]);

  async function loadSummary() {
    const s = await api.get<SummaryRow[]>(`/onet/summary?examYearBe=${examYearBe}`);
    setSummary(s);
    setSummaryLoaded(true);
  }

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      const r = await api.post<BulkOutcome>('/onet/bulk', { rows });
      setResult(r);
      setText('');
      if (summaryLoaded) void loadSummary();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'บันทึกไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHead title="ผลสอบ O-NET / V-NET" sub="โครงตารางทั่วไป — ยังไม่ได้เทียบกับรูปแบบไฟล์จริงที่หน่วยงานส่งมา" />

      {!canUse ? (
        <RestrictedNotice roles={ONET_ROLES} />
      ) : (
      <>
      <Notice kind="info">
        รูปแบบยังเป็นแบบทั่วไป (รหัสนักศึกษา + ปีที่สอบ + รหัส/ชื่อวิชา + คะแนน) เมื่อมีไฟล์ผลสอบจริงจาก
        สอศ./สทศ. ให้ปรับตัวอ่านให้ตรงกับคอลัมน์ในไฟล์นั้นแทน
      </Notice>

      <Card title="วางผลสอบจากตาราง">
        <p className="hint">
          คัดลอกจาก Excel มาวางได้ทั้งก้อน หนึ่งบรรทัดต่อหนึ่งวิชา/หนึ่งคน — รูปแบบ{' '}
          <span className="mono">รหัสนักศึกษา, ปีที่สอบ (พ.ศ.), รหัสวิชา, ชื่อวิชา, คะแนน</span>
        </p>
        <Field label="ข้อมูลผลสอบ">
          <textarea
            rows={8}
            value={text}
            spellCheck={false}
            placeholder={SAMPLE}
            onChange={(e) => { setText(e.target.value); setResult(null); }}
            style={{ fontFamily: 'var(--mono, monospace)', whiteSpace: 'pre', width: '100%' }}
          />
        </Field>
        {rows.length > 0 && (
          <p className="hint">
            อ่านได้ <b>{rows.length}</b> แถว
            {bad > 0 && <> · ข้ามบรรทัดที่อ่านไม่ออก <b>{bad}</b> แถว</>}
          </p>
        )}
        {error && <Notice kind="error">{error}</Notice>}
        <div className="row">
          <div className="shrink">
            <button className="primary" disabled={busy || rows.length === 0} onClick={() => void submit()}>
              {busy ? 'กำลังบันทึก…' : `บันทึก ${rows.length} แถว`}
            </button>
          </div>
        </div>
      </Card>

      {result && (
        <Card title="ผลการบันทึก">
          <Notice kind={result.failed > 0 ? 'warn' : 'ok'}>
            บันทึกสำเร็จ {result.saved} จาก {result.total} แถว
            {result.failed > 0 && ` · ผิด ${result.failed} แถว`}
          </Notice>
          {result.failed > 0 && (
            <table>
              <thead><tr><th>รหัสนักศึกษา</th><th>รหัสวิชา</th><th>ปัญหา</th></tr></thead>
              <tbody>
                {result.rows.filter((r) => r.status === 'error').map((r) => (
                  <tr key={r.row_no}>
                    <td className="mono">{r.student_code}</td>
                    <td className="mono">{r.subject_code}</td>
                    <td style={{ whiteSpace: 'normal' }}>{r.detail}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      )}

      <TableCard
        title="สรุปคะแนนเฉลี่ยรายวิชา"
        actions={
          <span style={{ display: 'inline-flex', gap: 8, alignItems: 'center' }}>
            <input
              type="number" value={examYearBe} onChange={(e) => setExamYearBe(e.target.value)}
              style={{ width: 90 }}
            />
            <button onClick={() => void loadSummary()}>ดูสรุป</button>
          </span>
        }
      >
        {!summary && <div className="empty">กดปุ่ม "ดูสรุป" เพื่อโหลดข้อมูล</div>}
        {summary && (
          summary.length === 0 ? (
            <div className="empty">ยังไม่มีผลสอบของปี {examYearBe}</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>วิชา</th>
                  <th className="num" style={{ width: 100 }}>คนสอบ</th>
                  <th className="num" style={{ width: 100 }}>เฉลี่ย</th>
                  <th className="num" style={{ width: 90 }}>ต่ำสุด</th>
                  <th className="num" style={{ width: 90 }}>สูงสุด</th>
                </tr>
              </thead>
              <tbody>
                {summary.map((r) => (
                  <tr key={r.subject_code}>
                    <td>{r.subject_th} <span className="hint mono">{r.subject_code}</span></td>
                    <td className="num">{num(r.students, 0)}</td>
                    <td className="num">{num(r.avg_score, 2)}</td>
                    <td className="num">{num(r.min_score, 2)}</td>
                    <td className="num">{num(r.max_score, 2)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        )}
      </TableCard>
      </>
      )}
    </>
  );
}

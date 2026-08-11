/**
 * งานวิชาการรายปี — เลื่อนชั้นปี จัดห้อง และรอบสอบซ่อม
 *
 * ─── ทำไมรอบสอบซ่อมไม่เขียนเกรดเอง ───
 * `record_regrade_result()` ยื่นคำร้องผ่าน `grade_change_request` ทางเดิม
 * ไม่เขียน `enrollment_result` เอง — ถ้าเปิดทางที่สอง ใครที่สร้างรอบสอบซ่อมได้
 * จะแก้เกรดใครก็ได้โดยไม่ต้องผ่านการอนุมัติของใครเลย (หลักข้อ 3ก)
 * ผลของหน้านี้จึงไปโผล่ที่หน้า "คำร้องขอแก้เกรด" ที่ต้องมีผู้อนุมัติสองคน
 *
 * ─── ทำไมการเลื่อนชั้นปีคืนผลรายคน ───
 * นักศึกษาที่ยังไม่ครบเกณฑ์เลื่อนชั้นต้องไม่ทำให้ทั้งรุ่นเลื่อนไม่ได้
 * ฟังก์ชันจึงคืนผลรายคนแทนการ raise เหมือนการลงทะเบียนเป็นกลุ่ม
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDate, thaiDateTime } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { useTermPicker } from '../ui/term-picker';

interface RolloverLog {
  id: string;
  from_year_be: number;
  to_year_be: number;
  summary: Record<string, unknown>;
  ran_at: string;
}

interface Placement {
  study_year: number;
  group_code: string | null;
  student_code: string;
  full_name: string;
}

interface RegradeSession {
  id: string;
  code: string;
  name_th: string;
  kind: string;
  level: string | null;
  status?: string;
  opens_on?: string;
  closes_on?: string;
  courses: number;
  candidates: number;
}

export function AcademicYearScreen() {
  const { terms } = useTermPicker();
  const rollovers = useAsync(() => api.get<RolloverLog[]>('/rollover'), []);
  const sessions = useAsync(() => api.get<RegradeSession[]>('/regrade/sessions'), []);

  const [fromYear, setFromYear] = useState('2569');
  const [toYear, setToYear] = useState('2570');
  const [ayId, setAyId] = useState('');
  const [rolloverResult, setRolloverResult] = useState<unknown>(null);

  const years = [...new Set((terms.data ?? []).map((t) => t.academic_year_id))];
  const placements = useAsync(
    () =>
      ayId
        ? api.get<Placement[]>(`/rollover/placements${qs({ academicYearId: ayId })}`)
        : Promise.resolve([]),
    [ayId],
  );

  return (
    <>
      <PageHead title="งานวิชาการรายปี" />

      <Card title="เลื่อนชั้นปีการศึกษา">
        <div className="row">
          <Field label="จากปีการศึกษา">
            <input value={fromYear} onChange={(e) => setFromYear(e.target.value)} inputMode="numeric" />
          </Field>
          <Field label="ไปปีการศึกษา">
            <input value={toYear} onChange={(e) => setToYear(e.target.value)} inputMode="numeric" />
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              confirm="เลื่อนชั้นปีให้นักศึกษาทั้งรุ่น ยืนยันหรือไม่"
              onRun={() =>
                api.post('/rollover/students', {
                  fromYearBe: Number(fromYear),
                  toYearBe: Number(toYear),
                })
              }
              onDone={(r) => {
                setRolloverResult(r);
                rollovers.reload();
              }}
            >
              เลื่อนชั้นปี
            </ActionButton>
          </div>
          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            คนที่ยังไม่ครบเกณฑ์จะถูกข้ามและรายงานกลับมา ไม่ทำให้ทั้งรุ่นล้ม
          </div>
        </div>

        {rolloverResult !== null && (
          <Notice kind="info">
            <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 12 }}>
              {JSON.stringify(rolloverResult, null, 2)}
            </pre>
          </Notice>
        )}
      </Card>

      <TableCard title="ประวัติการเลื่อนชั้นปี">
        <AsyncView state={rollovers} empty="ยังไม่เคยเลื่อนชั้นปี">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 200 }}>จากปี → ไปปี</th>
                  <th>สรุปผล</th>
                  <th style={{ width: 190 }}>เมื่อ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td>
                      {r.from_year_be} → {r.to_year_be}
                    </td>
                    <td style={{ whiteSpace: 'normal' }}>
                      {Object.entries(r.summary ?? {})
                        .map(([k, v]) => `${k}: ${String(v)}`)
                        .join(' · ') || '—'}
                    </td>
                    <td>{thaiDateTime(r.ran_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <Card title="การจัดห้องเรียนของปีการศึกษา">
        <div className="row">
          <label className="field" style={{ maxWidth: 320 }}>
            <span>ปีการศึกษา</span>
            <select value={ayId} onChange={(e) => setAyId(e.target.value)}>
              <option value="">— เลือกปีการศึกษา —</option>
              {years.map((id) => {
                const t = (terms.data ?? []).find((x) => x.academic_year_id === id);
                return (
                  <option key={id} value={id}>
                    ปีการศึกษา {t?.year_be}
                  </option>
                );
              })}
            </select>
          </label>
        </div>
      </Card>

      {ayId && (
        <TableCard title="นักศึกษาแยกตามชั้นปีและห้อง">
          <AsyncView state={placements} empty="ยังไม่ได้จัดห้องให้ปีการศึกษานี้">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 100 }}>ชั้นปี</th>
                    <th style={{ width: 120 }}>ห้อง</th>
                    <th style={{ width: 150 }}>รหัสนักศึกษา</th>
                    <th>ชื่อ — นามสกุล</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((p) => (
                    <tr key={p.student_code}>
                      <td>ปวช. {p.study_year}</td>
                      <td>{p.group_code ?? '—'}</td>
                      <td className="mono">{p.student_code}</td>
                      <td>{p.full_name}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>
      )}

      <TableCard title="รอบสอบซ่อมและเรียนปรับเกรด">
        <AsyncView state={sessions} empty="ยังไม่เคยเปิดรอบสอบซ่อม">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัสรอบ</th>
                  <th>ชื่อรอบ</th>
                  <th style={{ width: 140 }}>ประเภท</th>
                  <th style={{ width: 200 }}>ช่วงเวลา</th>
                  <th className="num" style={{ width: 90 }}>รายวิชา</th>
                  <th className="num" style={{ width: 110 }}>ผู้เข้าซ่อม</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((s) => (
                  <tr key={s.id}>
                    <td className="mono">{s.code}</td>
                    <td>{s.name_th}</td>
                    <td>
                      <Badge kind={s.kind === 'retest' ? 'info' : 'warn'}>
                        {s.kind === 'retest' ? 'สอบซ่อม' : 'เรียนปรับเกรด'}
                      </Badge>
                    </td>
                    <td>
                      {s.opens_on ? thaiDate(s.opens_on) : '—'}
                      {s.closes_on ? ` – ${thaiDate(s.closes_on)}` : ''}
                    </td>
                    <td className="num">{s.courses}</td>
                    <td className="num">{s.candidates}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <Notice kind="info">
        ผลของรอบสอบซ่อม <strong>ไม่ได้เขียนเกรดลงระเบียนโดยตรง</strong> —
        ยื่นเป็นคำร้องผ่านทางเดิมที่ต้องมีผู้อนุมัติสองคน ดูที่หน้า “คำร้องขอแก้เกรด”
        ถ้าเปิดทางที่สอง ใครที่สร้างรอบสอบซ่อมได้จะแก้เกรดใครก็ได้โดยไม่ต้องผ่านใครเลย
      </Notice>
    </>
  );
}

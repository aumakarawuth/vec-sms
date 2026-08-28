/**
 * รายงานผลการเรียน + นักศึกษาที่ผลการเรียนไม่ผ่านเกณฑ์
 *
 * ─── ที่มา ───
 * เมนู "รายงาน" ของระบบเดิม (SISA) มีรายงานผลการเรียนแยกขอบเขต (ระหว่างเรียน ·
 * ภาคเรียน · ปีการศึกษา · ทุกภาคเรียน) และรายชื่อนักศึกษาที่ไม่ผ่านเกณฑ์
 * แยกต่างหาก — ทั้งสองอย่างไม่เคยมีในระบบนี้มาก่อน ทั้งที่ข้อมูลที่ต้องใช้
 * (enrollment_result) มีอยู่แล้วเต็มระบบ
 *
 * ─── ทำไม "นักศึกษาที่ไม่ผ่านเกณฑ์" ใช้ฟังก์ชันเดียวกับหน้าลงทะเบียนรายคน ───
 * `student_failed_courses()` (0089) ตอบคำถาม "นักศึกษาคนนี้ยังไม่ผ่านวิชา
 * อะไรบ้าง" อยู่แล้ว — รายงานนี้แค่กวาดทุกคนที่ยัง active มาต่อกัน ไม่ต้อง
 * เขียนตรรกะ "ไม่ผ่านเกณฑ์" ซ้ำเป็นชุดที่สอง ซึ่งเสี่ยงนิยามเพี้ยนไปจากที่
 * หน้าลงทะเบียนใช้จริง
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { termLabel } from '../core/catalog';
import { AsyncView, Card, Notice, PageHead, PrintButton, TableCard, useAsync } from '../ui/kit';
import { useTermPicker } from '../ui/term-picker';

interface GradeRow {
  student_code: string;
  full_name: string;
  course_code: string;
  course_name: string;
  credits: string;
  grade_symbol: string;
  earns_credit: boolean;
  term_label: string;
}

interface FailingRow {
  student_code: string;
  full_name: string;
  failed_count: string;
  failed_courses: string;
}

type Scope = 'term' | 'year' | 'all';

export function GradeReportsScreen() {
  const { terms, termId, term, setTerm } = useTermPicker();
  const [scope, setScope] = useState<Scope>('term');
  const [onlyFailed, setOnlyFailed] = useState(false);

  const scopeQuery =
    scope === 'term' ? { termId } : scope === 'year' ? { academicYearId: term?.academic_year_id } : { allTerms: 'true' };
  const scopeReady = scope === 'all' || (scope === 'term' && termId) || (scope === 'year' && term?.academic_year_id);

  const scopeLabel =
    scope === 'term' && term ? termLabel(term)
    : scope === 'year' && term ? `ปีการศึกษา ${term.year_be}`
    : scope === 'all' ? 'ทุกภาคเรียน'
    : '';

  const grades = useAsync(
    () =>
      scopeReady
        ? api.get<GradeRow[]>(`/reports/grades${qs({ ...scopeQuery, onlyFailed: onlyFailed ? 'true' : undefined })}`)
        : Promise.resolve([]),
    [scope, termId, term?.academic_year_id, onlyFailed],
  );

  const failing = useAsync(() => api.get<FailingRow[]>('/reports/failing-students'), []);

  return (
    <>
      <PageHead title="รายงานผลการเรียน" sub="ดูผลการเรียนตามขอบเขตที่เลือก และรายชื่อนักศึกษาที่ยังไม่ผ่านเกณฑ์" />

      <Card title="เลือกขอบเขต">
        <div className="row" style={{ alignItems: 'end' }}>
          <label className="field" style={{ maxWidth: 220 }}>
            <span>ขอบเขต</span>
            <select value={scope} onChange={(e) => setScope(e.target.value as Scope)}>
              <option value="term">ภาคเรียนเดียว</option>
              <option value="year">ทั้งปีการศึกษา</option>
              <option value="all">ทุกภาคเรียน</option>
            </select>
          </label>

          {scope !== 'all' && (
            <label className="field" style={{ maxWidth: 260 }}>
              <span>ภาคเรียน{scope === 'year' ? ' (ใช้กำหนดปีการศึกษา)' : ''}</span>
              <AsyncView state={terms} empty="ยังไม่มีภาคเรียน">
                {(list) => (
                  <select value={termId} onChange={(e) => setTerm(e.target.value)}>
                    <option value="">— เลือกภาคเรียน —</option>
                    {list.map((t) => (
                      <option key={t.id} value={t.id}>{termLabel(t)}</option>
                    ))}
                  </select>
                )}
              </AsyncView>
            </label>
          )}

          <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <input type="checkbox" checked={onlyFailed} onChange={(e) => setOnlyFailed(e.target.checked)} />
            เฉพาะที่ไม่ผ่าน
          </label>

          <div className="shrink">
            {scopeReady ? (
              <PrintButton
                path={`/reports/grades/print${qs({
                  ...scopeQuery,
                  onlyFailed: onlyFailed ? 'true' : undefined,
                  scopeLabel,
                })}`}
              >
                พิมพ์รายงาน
              </PrintButton>
            ) : (
              <button disabled title="เลือกขอบเขตให้ครบก่อน">พิมพ์รายงาน</button>
            )}
          </div>
        </div>
      </Card>

      {!scopeReady ? (
        <Notice kind="info">เลือกภาคเรียนหรือปีการศึกษาก่อน — ยกเว้นเลือก "ทุกภาคเรียน" ที่ดูได้ทันที</Notice>
      ) : (
        <TableCard title={`ผลการเรียน — ${scopeLabel}${onlyFailed ? ' (เฉพาะที่ไม่ผ่าน)' : ''}`}>
          <AsyncView state={grades} empty="ไม่มีข้อมูลตามเงื่อนไขที่เลือก">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                    <th>ชื่อ — นามสกุล</th>
                    <th style={{ width: 110 }}>รหัสวิชา</th>
                    <th>ชื่อวิชา</th>
                    <th className="num" style={{ width: 60 }}>นก.</th>
                    <th style={{ width: 90 }}>ผลการเรียน</th>
                    <th style={{ width: 150 }}>ภาคเรียน</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r, i) => (
                    <tr key={`${r.student_code}-${r.course_code}-${i}`}>
                      <td className="mono">{r.student_code}</td>
                      <td>{r.full_name}</td>
                      <td className="mono">{r.course_code}</td>
                      <td>{r.course_name}</td>
                      <td className="num">{r.credits}</td>
                      <td style={{ color: r.earns_credit ? undefined : 'var(--danger, #c0392b)' }}>{r.grade_symbol}</td>
                      <td>{r.term_label}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>
      )}

      <TableCard
        title="นักศึกษาที่ผลการเรียนไม่ผ่านเกณฑ์"
        actions={
          <PrintButton path="/reports/failing-students/print">พิมพ์รายงาน</PrintButton>
        }
      >
        <AsyncView state={failing} empty="ไม่มีนักศึกษาที่ผลการเรียนไม่ผ่านเกณฑ์ในขณะนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                  <th style={{ width: 220 }}>ชื่อ — นามสกุล</th>
                  <th className="num" style={{ width: 110 }}>จำนวนวิชาที่ตก</th>
                  <th>รายวิชาที่ยังไม่ผ่าน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.student_code}>
                    <td className="mono">{r.student_code}</td>
                    <td>{r.full_name}</td>
                    <td className="num">{r.failed_count}</td>
                    <td style={{ whiteSpace: 'normal' }}>{r.failed_courses}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <Notice kind="info">
        "ไม่ผ่านเกณฑ์" นับจากผลฉบับปัจจุบันที่ไม่ได้หน่วยกิต (0, ข.ร., ถ.น., ม.ผ. ฯลฯ)
        และยังไม่เคยผ่านวิชานั้นในความพยายามครั้งไหนเลย — หลักการเดียวกับที่ใช้กรองวิชา
        ในหน้าลงทะเบียนเรียนเสริม/เรียนปรับเกรดรายคน
      </Notice>
    </>
  );
}

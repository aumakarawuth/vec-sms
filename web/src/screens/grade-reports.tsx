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
import { fetchSections, termLabel, type Section, type Term } from '../core/catalog';
import { AsyncView, Badge, Card, Notice, PageHead, PrintButton, TableCard, useAsync, type Async } from '../ui/kit';
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

interface CurriculumRow {
  suggested_year: number | null;
  suggested_term: number | null;
  requirement: string;
  category_name: string;
  course_code: string;
  course_name: string;
  credits: string;
  enrollment_status: string | null;
  grade_symbol: string | null;
  earns_credit: boolean | null;
}

interface WeeklyRow {
  week_no: number;
  starts_on: string;
  ends_on: string;
  meetings_held: string;
  present_count: string;
  late_count: string;
  absent_count: string;
  leave_count: string;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

const ENROLLMENT_STATUS_LABEL: Record<string, string> = {
  enrolled: 'กำลังเรียน',
  dropped: 'ถอนแล้ว',
  completed: 'เรียนจบแล้ว',
};

function courseStatus(r: CurriculumRow): { label: string; kind: 'ok' | 'warn' | 'danger' | 'default' } {
  if (r.grade_symbol) {
    return r.earns_credit ? { label: 'ผ่านแล้ว', kind: 'ok' } : { label: 'ไม่ผ่าน', kind: 'danger' };
  }
  if (r.enrollment_status) {
    return { label: ENROLLMENT_STATUS_LABEL[r.enrollment_status] ?? r.enrollment_status, kind: 'default' };
  }
  return { label: 'ยังไม่ลง', kind: 'warn' };
}

function CurriculumCheckCard() {
  const [typed, setTyped] = useState('');
  const [q, setQ] = useState('');
  const [studentId, setStudentId] = useState('');

  const students = useAsync(
    () => (q ? api.get<StudentRow[]>(`/students${qs({ q, limit: 20 })}`) : Promise.resolve([])),
    [q],
  );
  const rows = useAsync(
    () => (studentId ? api.get<CurriculumRow[]>(`/reports/curriculum-check/${studentId}`) : Promise.resolve([])),
    [studentId],
  );
  const student = students.data?.find((s) => s.id === studentId);

  return (
    <TableCard
      title={student ? `ตรวจสอบหลักสูตร — ${student.student_code} ${student.full_name}` : 'ตรวจสอบหลักสูตร'}
      actions={
        <div className="row" style={{ gap: 10, alignItems: 'center' }}>
          <form onSubmit={(e) => { e.preventDefault(); setQ(typed.trim()); }}>
            <input
              placeholder="ค้นหารหัสหรือชื่อนักศึกษา"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              style={{ width: 200 }}
            />
          </form>
          {studentId ? (
            <PrintButton path={`/reports/curriculum-check/${studentId}/print${qs({ studentLabel: student ? `${student.student_code} ${student.full_name}` : undefined })}`}>
              พิมพ์รายงาน
            </PrintButton>
          ) : (
            <button disabled title="เลือกนักศึกษาก่อน">พิมพ์รายงาน</button>
          )}
        </div>
      }
    >
      {q && !studentId && (
        <div style={{ padding: '8px 0' }}>
          <AsyncView state={students} empty="ไม่พบนักศึกษาที่ตรงกับคำค้น">
            {(list) => (
              <div className="row" style={{ flexWrap: 'wrap', gap: 6 }}>
                {list.map((s) => (
                  <button key={s.id} className="ghost" onClick={() => setStudentId(s.id)}>
                    {s.student_code} {s.full_name}
                  </button>
                ))}
              </div>
            )}
          </AsyncView>
        </div>
      )}
      {!studentId ? (
        <div className="empty">ค้นหาแล้วเลือกนักศึกษาหนึ่งคน — แผนการเรียนตามหลักสูตรและสถานะรายวิชาจะปรากฏที่นี่</div>
      ) : (
        <AsyncView state={rows} empty="นักศึกษาคนนี้ยังไม่ได้ผูกหลักสูตร">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 110 }}>รหัสวิชา</th>
                  <th>ชื่อวิชา</th>
                  <th style={{ width: 160 }}>หมวดวิชา</th>
                  <th className="num" style={{ width: 60 }}>นก.</th>
                  <th style={{ width: 90 }}>ปี/ภาคที่แนะนำ</th>
                  <th style={{ width: 110 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r, i) => {
                  const st = courseStatus(r);
                  return (
                    <tr key={`${r.course_code}-${i}`}>
                      <td className="mono">{r.course_code}</td>
                      <td>{r.course_name}</td>
                      <td>{r.category_name}</td>
                      <td className="num">{r.credits}</td>
                      <td>{r.suggested_year ? `${r.suggested_year}/${r.suggested_term ?? '—'}` : '—'}</td>
                      <td><Badge kind={st.kind}>{st.label}{r.grade_symbol ? ` (${r.grade_symbol})` : ''}</Badge></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      )}
    </TableCard>
  );
}

function WeeklyAttendanceCard({ terms }: { terms: Async<Term[]> }) {
  const [termId, setTermId] = useState('');
  const [sectionId, setSectionId] = useState('');
  const sections = useAsync(() => (termId ? fetchSections(termId) : Promise.resolve([])), [termId]);
  const section = (sections.data ?? []).find((s) => s.id === sectionId);
  const sectionLabel = section ? `${section.code} ${section.name_th} · กลุ่ม ${section.section_no}` : '';

  const rows = useAsync(
    () => (sectionId ? api.get<WeeklyRow[]>(`/reports/weekly-attendance/${sectionId}`) : Promise.resolve([])),
    [sectionId],
  );

  return (
    <TableCard
      title="เวลาเรียนรายสัปดาห์"
      actions={
        <div className="row" style={{ gap: 10, alignItems: 'center' }}>
          <AsyncView state={terms} empty="ยังไม่มีภาคเรียน">
            {(list) => (
              <select value={termId} onChange={(e) => { setTermId(e.target.value); setSectionId(''); }} style={{ maxWidth: 200 }}>
                <option value="">— เลือกภาคเรียน —</option>
                {list.map((t) => (
                  <option key={t.id} value={t.id}>{termLabel(t)}</option>
                ))}
              </select>
            )}
          </AsyncView>
          <select value={sectionId} onChange={(e) => setSectionId(e.target.value)} style={{ maxWidth: 320 }} disabled={!termId}>
            <option value="">— เลือกกลุ่มเรียน —</option>
            {(sections.data ?? []).map((s: Section) => (
              <option key={s.id} value={s.id}>{s.code} {s.name_th} · กลุ่ม {s.section_no}</option>
            ))}
          </select>
          {sectionId ? (
            <PrintButton path={`/reports/weekly-attendance/${sectionId}/print${qs({ sectionLabel })}`}>
              พิมพ์รายงาน
            </PrintButton>
          ) : (
            <button disabled title="เลือกกลุ่มเรียนก่อน">พิมพ์รายงาน</button>
          )}
        </div>
      }
    >
      {!termId ? (
        <div className="empty">เลือกภาคเรียนก่อน</div>
      ) : !sectionId ? (
        <div className="empty">เลือกกลุ่มเรียน — สรุปเวลาเรียนแบ่งเป็นสัปดาห์จะปรากฏที่นี่</div>
      ) : (
        <AsyncView state={rows} empty="กลุ่มเรียนนี้ยังไม่มีคาบที่สอนจริง">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 90 }}>สัปดาห์ที่</th>
                  <th style={{ width: 180 }}>ช่วงวันที่</th>
                  <th className="num" style={{ width: 90 }}>คาบที่สอน</th>
                  <th className="num" style={{ width: 90 }}>มาเรียน</th>
                  <th className="num" style={{ width: 90 }}>มาสาย</th>
                  <th className="num" style={{ width: 90 }}>ขาดเรียน</th>
                  <th className="num" style={{ width: 80 }}>ลา</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.week_no}>
                    <td>{r.week_no}</td>
                    <td>{r.starts_on} – {r.ends_on}</td>
                    <td className="num">{r.meetings_held}</td>
                    <td className="num">{r.present_count}</td>
                    <td className="num">{r.late_count}</td>
                    <td className="num">{r.absent_count}</td>
                    <td className="num">{r.leave_count}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      )}
    </TableCard>
  );
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

      <CurriculumCheckCard />

      <WeeklyAttendanceCard terms={terms} />
    </>
  );
}

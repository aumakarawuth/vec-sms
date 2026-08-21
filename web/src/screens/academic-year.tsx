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
import type { Term } from '../core/catalog';
import { TERM_STATUS, thaiDate, thaiDateTime } from '../core/fmt';
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

interface AcademicYear {
  id: string;
  year_be: number;
  starts_on: string;
  ends_on: string;
}

interface StaffRow {
  id: string;
  person_id: string;
  staff_code: string;
  full_name: string;
}

interface CourseRow {
  id: string;
  code: string;
  name_th: string;
  credits: string;
}

interface RoomRow {
  id: string;
  code: string;
  name_th: string;
}

interface SessionCourse {
  id: string;
  course_code: string;
  course_name: string;
  credits: string;
  fee_amount: string;
  capacity: number | null;
  registered: number;
}

interface RegradeCandidate {
  id: string;
  student_code: string;
  full_name: string;
  status: string;
  change_request_id: string | null;
  registered_at: string;
}

interface GradeSymbol {
  id: string;
  symbol: string;
  name_th: string;
  scheme_code: string;
}

interface EligibleStudent {
  student_id: string;
  student_code: string;
  full_name: string;
  grade_symbol: string;
  term_label: string;
}

/** ลำดับที่ advance_term_status() (0073) ยอมให้เดิน — ต้องตรงกับฐานข้อมูลเป๊ะ */
const NEXT_STATUS: Record<string, string[]> = {
  planning: ['registration'],
  registration: ['open', 'planning'],
  open: ['grading'],
  grading: ['closed'],
  closed: [],
};

function CreateYearForm({ onDone }: { onDone: () => void }) {
  const [yearBe, setYearBe] = useState('');
  const [startsOn, setStartsOn] = useState('');
  const [endsOn, setEndsOn] = useState('');

  return (
    <Card title="เปิดปีการศึกษาใหม่">
      <div className="row">
        <Field label="ปีการศึกษา (พ.ศ.)">
          <input value={yearBe} onChange={(e) => setYearBe(e.target.value.replace(/\D/g, ''))} inputMode="numeric" style={{ maxWidth: 100 }} />
        </Field>
        <Field label="วันเปิดปีการศึกษา">
          <input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} />
        </Field>
        <Field label="วันปิดปีการศึกษา">
          <input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!yearBe || !startsOn || !endsOn) throw new Error('กรอกไม่ครบ');
              return api.post('/academic/years', { yearBe: Number(yearBe), startsOn, endsOn });
            }}
            onDone={() => {
              setYearBe(''); setStartsOn(''); setEndsOn('');
              onDone();
            }}
          >
            เปิดปีการศึกษา
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function CreateTermForm({ years, onDone }: { years: AcademicYear[]; onDone: () => void }) {
  const [academicYearId, setAcademicYearId] = useState('');
  const [ordinal, setOrdinal] = useState('1');
  const [kind, setKind] = useState('regular');
  const [startsOn, setStartsOn] = useState('');
  const [endsOn, setEndsOn] = useState('');
  const [addDropEndsOn, setAddDropEndsOn] = useState('');
  const [withdrawEndsOn, setWithdrawEndsOn] = useState('');
  const [gradeDueOn, setGradeDueOn] = useState('');

  return (
    <Card title="เปิดภาคเรียนใหม่">
      <div className="row">
        <label className="field">
          <span>ปีการศึกษา</span>
          <select value={academicYearId} onChange={(e) => setAcademicYearId(e.target.value)}>
            <option value="">— เลือกปีการศึกษา —</option>
            {years.map((y) => (
              <option key={y.id} value={y.id}>ปีการศึกษา {y.year_be}</option>
            ))}
          </select>
        </label>
        <Field label="ภาคเรียนที่">
          <select value={ordinal} onChange={(e) => setOrdinal(e.target.value)} style={{ maxWidth: 90 }}>
            <option value="1">1</option>
            <option value="2">2</option>
            <option value="3">3</option>
          </select>
        </Field>
        <Field label="ประเภท">
          <select value={kind} onChange={(e) => setKind(e.target.value)} style={{ maxWidth: 120 }}>
            <option value="regular">ภาคปกติ</option>
            <option value="summer">ภาคฤดูร้อน</option>
          </select>
        </Field>
        <Field label="วันเปิดภาค">
          <input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} />
        </Field>
        <Field label="วันปิดภาค">
          <input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
        </Field>
      </div>
      <div className="row">
        <Field label="เพิ่ม/ถอนถึงวันที่ (ถ้ามี)">
          <input type="date" value={addDropEndsOn} onChange={(e) => setAddDropEndsOn(e.target.value)} />
        </Field>
        <Field label="ถอนแบบติด ถ.น. ถึงวันที่ (ถ้ามี)">
          <input type="date" value={withdrawEndsOn} onChange={(e) => setWithdrawEndsOn(e.target.value)} />
        </Field>
        <Field label="กำหนดส่งเกรด (ถ้ามี)">
          <input type="date" value={gradeDueOn} onChange={(e) => setGradeDueOn(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!academicYearId || !startsOn || !endsOn) throw new Error('กรอกไม่ครบ');
              return api.post(`/academic/years/${academicYearId}/terms`, {
                ordinal: Number(ordinal), kind, startsOn, endsOn,
                ...(addDropEndsOn ? { addDropEndsOn } : {}),
                ...(withdrawEndsOn ? { withdrawEndsOn } : {}),
                ...(gradeDueOn ? { gradeDueOn } : {}),
              });
            }}
            onDone={() => {
              setStartsOn(''); setEndsOn(''); setAddDropEndsOn(''); setWithdrawEndsOn(''); setGradeDueOn('');
              onDone();
            }}
          >
            เปิดภาคเรียน
          </ActionButton>
        </div>
      </div>
      <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
        ภาคเรียนเริ่มที่สถานะ “กำลังวางแผน” เสมอ — เดินสถานะต่อได้จากตารางด้านบนเมื่อพร้อม
      </div>
    </Card>
  );
}

function CreateSectionForm({
  terms, courses, staff, rooms, onDone,
}: { terms: Term[]; courses: CourseRow[]; staff: StaffRow[]; rooms: RoomRow[]; onDone: () => void }) {
  const [termId, setTermId] = useState('');
  const [courseId, setCourseId] = useState('');
  const [sectionNo, setSectionNo] = useState('1/1');
  const [teacherId, setTeacherId] = useState('');
  const [roomId, setRoomId] = useState('');
  const [capacity, setCapacity] = useState('40');

  return (
    <Card title="เปิดกลุ่มเรียน">
      <div className="row">
        <label className="field">
          <span>ภาคเรียน</span>
          <select value={termId} onChange={(e) => setTermId(e.target.value)}>
            <option value="">— เลือกภาคเรียน —</option>
            {terms.map((t) => (
              <option key={t.id} value={t.id}>ภาคเรียนที่ {t.ordinal}/{t.year_be} — {TERM_STATUS[t.status] ?? t.status}</option>
            ))}
          </select>
        </label>
        <label className="field" style={{ flex: 2 }}>
          <span>รายวิชา</span>
          <select value={courseId} onChange={(e) => setCourseId(e.target.value)}>
            <option value="">— เลือกรายวิชา —</option>
            {courses.map((c) => (
              <option key={c.id} value={c.id}>{c.code} {c.name_th} ({c.credits} นก.)</option>
            ))}
          </select>
        </label>
        <Field label="รหัสกลุ่มเรียน">
          <input value={sectionNo} onChange={(e) => setSectionNo(e.target.value)} style={{ maxWidth: 90 }} />
        </Field>
      </div>
      <div className="row">
        <label className="field">
          <span>ผู้สอน (ถ้ามี)</span>
          <select value={teacherId} onChange={(e) => setTeacherId(e.target.value)}>
            <option value="">— ยังไม่ระบุผู้สอน —</option>
            {staff.map((s) => (
              <option key={s.id} value={s.id}>{s.full_name} ({s.staff_code})</option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>ห้อง (ถ้ามี)</span>
          <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
            <option value="">— ยังไม่ระบุห้อง —</option>
            {rooms.map((r) => (
              <option key={r.id} value={r.id}>{r.code} {r.name_th}</option>
            ))}
          </select>
        </label>
        <Field label="ที่นั่ง">
          <input type="number" min={1} value={capacity} onChange={(e) => setCapacity(e.target.value)} style={{ maxWidth: 90 }} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!termId || !courseId || !sectionNo.trim()) throw new Error('กรอกไม่ครบ');
              return api.post('/academic/sections', {
                termId, courseId, sectionNo: sectionNo.trim(),
                ...(teacherId ? { teacherId } : {}),
                ...(roomId ? { roomId } : {}),
                capacity: Number(capacity),
              });
            }}
            onDone={() => { setCourseId(''); onDone(); }}
          >
            เปิดกลุ่มเรียน
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function CreateRegradeSessionForm({ terms, onDone }: { terms: Term[]; onDone: () => void }) {
  const [termId, setTermId] = useState('');
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');
  const [kind, setKind] = useState('retest');
  const [opensOn, setOpensOn] = useState('');
  const [closesOn, setClosesOn] = useState('');

  return (
    <Card title="เปิดรอบสอบซ่อม/เรียนปรับเกรด">
      <div className="row">
        <label className="field">
          <span>ภาคเรียน</span>
          <select value={termId} onChange={(e) => setTermId(e.target.value)}>
            <option value="">— เลือกภาคเรียน —</option>
            {terms.map((t) => (
              <option key={t.id} value={t.id}>ภาคเรียนที่ {t.ordinal}/{t.year_be}</option>
            ))}
          </select>
        </label>
        <Field label="รหัสรอบ">
          <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น RETEST-2569-1" style={{ maxWidth: 160 }} />
        </Field>
        <label className="field" style={{ flex: 2 }}>
          <span>ชื่อรอบ</span>
          <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น สอบซ่อมภาคเรียนที่ 1/2569" />
        </label>
        <Field label="ประเภท">
          <select value={kind} onChange={(e) => setKind(e.target.value)} style={{ maxWidth: 140 }}>
            <option value="retest">สอบซ่อม</option>
            <option value="restudy">เรียนปรับเกรด</option>
          </select>
        </Field>
      </div>
      <div className="row">
        <Field label="เปิดรับตั้งแต่">
          <input type="date" value={opensOn} onChange={(e) => setOpensOn(e.target.value)} />
        </Field>
        <Field label="ถึงวันที่">
          <input type="date" value={closesOn} onChange={(e) => setClosesOn(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!termId || !code.trim() || !nameTh.trim() || !opensOn || !closesOn) {
                throw new Error('กรอกไม่ครบ');
              }
              return api.post('/regrade/sessions', {
                termId, code: code.trim(), nameTh: nameTh.trim(), kind, opensOn, closesOn,
              });
            }}
            onDone={() => { setCode(''); setNameTh(''); setOpensOn(''); setClosesOn(''); onDone(); }}
          >
            เปิดรอบ
          </ActionButton>
        </div>
      </div>
      <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
        รอบใหม่เริ่มที่สถานะร่าง — ต้องเพิ่มรายวิชาก่อนจึงเปิดรับได้
      </div>
    </Card>
  );
}

function RegradeSessionDetail({
  sessionId, courses: allCourses, gradeSymbols,
}: { sessionId: string; courses: CourseRow[]; gradeSymbols: GradeSymbol[] }) {
  const sessionCourses = useAsync(() => api.get<SessionCourse[]>(`/regrade/sessions/${sessionId}/courses`), [sessionId]);
  const [courseId, setCourseId] = useState('');
  const [feeAmount, setFeeAmount] = useState('');
  const [scId, setScId] = useState('');

  const eligible = useAsync(
    () => (scId ? api.get<EligibleStudent[]>(`/regrade/courses/${scId}/eligible`) : Promise.resolve([])),
    [scId],
  );
  const candidates = useAsync(
    () => (scId ? api.get<RegradeCandidate[]>(`/regrade/courses/${scId}/candidates`) : Promise.resolve([])),
    [scId],
  );

  return (
    <>
      <Card title="วิชาที่เปิดในรอบนี้">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>เพิ่มรายวิชา</span>
            <select value={courseId} onChange={(e) => setCourseId(e.target.value)}>
              <option value="">— เลือกรายวิชา —</option>
              {allCourses.map((c) => (
                <option key={c.id} value={c.id}>{c.code} {c.name_th}</option>
              ))}
            </select>
          </label>
          <Field label="ค่าธรรมเนียม (ถ้ามี)">
            <input type="number" min={0} value={feeAmount} onChange={(e) => setFeeAmount(e.target.value)} style={{ maxWidth: 110 }} />
          </Field>
          <div className="shrink">
            <ActionButton
              onRun={() => {
                if (!courseId) throw new Error('เลือกรายวิชาก่อน');
                return api.post(`/regrade/sessions/${sessionId}/courses`, {
                  courseId, ...(feeAmount ? { feeAmount: Number(feeAmount) } : {}),
                });
              }}
              onDone={() => { setCourseId(''); setFeeAmount(''); sessionCourses.reload(); }}
            >
              เพิ่มวิชา
            </ActionButton>
          </div>
          <div className="shrink">
            <ActionButton
              confirm="เปิดรับสมัครรอบนี้ ยืนยันหรือไม่"
              onRun={() => api.post(`/regrade/sessions/${sessionId}/open`)}
              onDone={() => sessionCourses.reload()}
            >
              เปิดรับ
            </ActionButton>
          </div>
          <div className="shrink">
            <ActionButton
              confirm="ปิดรับสมัครรอบนี้ ยืนยันหรือไม่"
              onRun={() => api.post(`/regrade/sessions/${sessionId}/close`)}
              onDone={() => sessionCourses.reload()}
            >
              ปิดรับ
            </ActionButton>
          </div>
        </div>

        <AsyncView state={sessionCourses} empty="ยังไม่มีรายวิชาในรอบนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 30 }} />
                  <th>วิชา</th>
                  <th className="num" style={{ width: 90 }}>หน่วยกิต</th>
                  <th className="num" style={{ width: 100 }}>ลงแล้ว</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <input type="radio" name="sc" checked={scId === r.id} onChange={() => setScId(scId === r.id ? '' : r.id)} />
                    </td>
                    <td>{r.course_code} {r.course_name}</td>
                    <td className="num">{r.credits}</td>
                    <td className="num">{r.registered}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </Card>

      {scId && (
        <>
          <TableCard title="ผู้มีสิทธิ์ — คำนวณจากผลการเรียนจริง">
            <AsyncView state={eligible} empty="ไม่มีผู้มีสิทธิ์ในวิชานี้">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                      <th>ชื่อ — นามสกุล</th>
                      <th style={{ width: 90 }}>เกรดเดิม</th>
                      <th style={{ width: 140 }}>ภาคที่เรียน</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((s) => (
                      <tr key={s.student_id}>
                        <td className="mono">{s.student_code}</td>
                        <td>{s.full_name}</td>
                        <td>{s.grade_symbol}</td>
                        <td>{s.term_label}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
            {(eligible.data?.length ?? 0) > 0 && (
              <div style={{ marginTop: 10 }}>
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post(`/regrade/courses/${scId}/register`, {
                      studentIds: (eligible.data ?? []).map((s) => s.student_id),
                    })
                  }
                  onDone={() => { candidates.reload(); sessionCourses.reload(); }}
                >
                  ลงทะเบียนผู้มีสิทธิ์ทั้งหมด ({eligible.data?.length ?? 0} คน)
                </ActionButton>
              </div>
            )}
          </TableCard>

          <TableCard title="ผู้ลงทะเบียนแล้ว">
            <AsyncView state={candidates} empty="ยังไม่มีใครลงทะเบียน">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                      <th>ชื่อ — นามสกุล</th>
                      <th style={{ width: 130 }}>สถานะ</th>
                      <th style={{ width: 160 }} />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((c) => (
                      <RegradeCandidateRow key={c.id} candidate={c} gradeSymbols={gradeSymbols} onDone={() => candidates.reload()} />
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>
        </>
      )}
    </>
  );
}

function RegradeCandidateRow({
  candidate, gradeSymbols, onDone,
}: { candidate: RegradeCandidate; gradeSymbols: GradeSymbol[]; onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const [gradeSymbolId, setGradeSymbolId] = useState('');
  const [reason, setReason] = useState('');

  return (
    <>
      <tr>
        <td className="mono">{candidate.student_code}</td>
        <td>{candidate.full_name}</td>
        <td>
          <Badge kind={candidate.change_request_id ? 'ok' : 'info'}>
            {candidate.change_request_id ? 'ยื่นคำร้องแล้ว' : candidate.status}
          </Badge>
        </td>
        <td>
          {!candidate.change_request_id && (
            <button className="ghost" onClick={() => setOpen(!open)}>
              {open ? 'ปิด' : 'บันทึกผล'}
            </button>
          )}
        </td>
      </tr>
      {open && (
        <tr>
          <td colSpan={4}>
            <div className="row">
              <label className="field">
                <span>ผลการเรียนใหม่</span>
                <select value={gradeSymbolId} onChange={(e) => setGradeSymbolId(e.target.value)}>
                  <option value="">— เลือกสัญลักษณ์ —</option>
                  {gradeSymbols.map((g) => (
                    <option key={g.id} value={g.id}>{g.symbol} — {g.name_th} ({g.scheme_code})</option>
                  ))}
                </select>
              </label>
              <label className="field" style={{ flex: 2 }}>
                <span>เหตุผล</span>
                <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="เช่น สอบซ่อมผ่านแล้ว" />
              </label>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() => {
                    if (!gradeSymbolId.trim() || !reason.trim()) throw new Error('กรอกไม่ครบ');
                    return api.post(`/regrade/candidates/${candidate.id}/result`, {
                      toGradeSymbolId: gradeSymbolId.trim(), reason: reason.trim(),
                    });
                  }}
                  onDone={() => { setOpen(false); onDone(); }}
                >
                  ยื่นคำร้องแก้เกรด
                </ActionButton>
              </div>
            </div>
            <Notice kind="info">
              บันทึกที่นี่ไม่ได้เขียนเกรดทันที — ยื่นเป็นคำร้องผ่านทางเดิมที่ต้องมีผู้อนุมัติสองคน (หน้า “คำร้องขอแก้เกรด”)
            </Notice>
          </td>
        </tr>
      )}
    </>
  );
}

export function AcademicYearScreen() {
  const { terms } = useTermPicker();
  const rollovers = useAsync(() => api.get<RolloverLog[]>('/rollover'), []);
  const sessions = useAsync(() => api.get<RegradeSession[]>('/regrade/sessions'), []);
  const academicYears = useAsync(() => api.get<AcademicYear[]>('/academic/years'), []);
  const courses = useAsync(() => api.get<CourseRow[]>('/curriculum/courses'), []);
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=100'), []);
  const rooms = useAsync(() => api.get<RoomRow[]>('/timetable/rooms'), []);
  const gradeSymbols = useAsync(() => api.get<GradeSymbol[]>('/gradebook/grade-symbols'), []);

  const [fromYear, setFromYear] = useState('2569');
  const [toYear, setToYear] = useState('2570');
  const [ayId, setAyId] = useState('');
  const [rolloverResult, setRolloverResult] = useState<unknown>(null);
  const [sessionId, setSessionId] = useState('');

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

      <TableCard title="ภาคเรียนทั้งหมด">
        <AsyncView state={terms} empty="ยังไม่มีภาคเรียนในระบบ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 160 }}>ภาคเรียน</th>
                  <th style={{ width: 220 }}>ช่วงเวลา</th>
                  <th style={{ width: 150 }}>สถานะ</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {rows.map((t) => {
                  const next = NEXT_STATUS[t.status] ?? [];
                  return (
                    <tr key={t.id}>
                      <td>ภาคเรียนที่ {t.ordinal}/{t.year_be}</td>
                      <td>{thaiDate(t.starts_on)} – {thaiDate(t.ends_on)}</td>
                      <td><Badge kind={t.status === 'open' ? 'ok' : t.status === 'closed' ? 'info' : 'warn'}>{TERM_STATUS[t.status] ?? t.status}</Badge></td>
                      <td>
                        {next.map((n) => (
                          <ActionButton
                            key={n}
                            confirm={n === 'planning' ? 'ถอยกลับไปสถานะกำลังวางแผน ยืนยันหรือไม่' : undefined}
                            onRun={() => api.post(`/academic/terms/${t.id}/status`, { status: n })}
                            onDone={() => terms.reload()}
                          >
                            {n === 'planning' ? '↺ ถอยกลับวางแผน' : `→ ${TERM_STATUS[n] ?? n}`}
                          </ActionButton>
                        ))}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <CreateYearForm onDone={() => academicYears.reload()} />
      <CreateTermForm years={academicYears.data ?? []} onDone={() => terms.reload()} />

      <CreateSectionForm
        terms={terms.data ?? []}
        courses={courses.data ?? []}
        staff={staff.data?.items ?? []}
        rooms={rooms.data ?? []}
        onDone={() => {}}
      />

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

      <CreateRegradeSessionForm terms={terms.data ?? []} onDone={() => sessions.reload()} />

      <TableCard title="รอบสอบซ่อมและเรียนปรับเกรด">
        <AsyncView state={sessions} empty="ยังไม่เคยเปิดรอบสอบซ่อม">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 30 }} />
                  <th style={{ width: 130 }}>รหัสรอบ</th>
                  <th>ชื่อรอบ</th>
                  <th style={{ width: 140 }}>ประเภท</th>
                  <th style={{ width: 110 }}>สถานะ</th>
                  <th style={{ width: 200 }}>ช่วงเวลา</th>
                  <th className="num" style={{ width: 90 }}>รายวิชา</th>
                  <th className="num" style={{ width: 110 }}>ผู้เข้าซ่อม</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <input type="radio" name="regrade-session" checked={sessionId === s.id} onChange={() => setSessionId(sessionId === s.id ? '' : s.id)} />
                    </td>
                    <td className="mono">{s.code}</td>
                    <td>{s.name_th}</td>
                    <td>
                      <Badge kind={s.kind === 'retest' ? 'info' : 'warn'}>
                        {s.kind === 'retest' ? 'สอบซ่อม' : 'เรียนปรับเกรด'}
                      </Badge>
                    </td>
                    <td>{s.status ?? '—'}</td>
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

      {sessionId && (
        <RegradeSessionDetail
          sessionId={sessionId}
          courses={courses.data ?? []}
          gradeSymbols={gradeSymbols.data ?? []}
        />
      )}

      <Notice kind="info">
        ผลของรอบสอบซ่อม <strong>ไม่ได้เขียนเกรดลงระเบียนโดยตรง</strong> —
        ยื่นเป็นคำร้องผ่านทางเดิมที่ต้องมีผู้อนุมัติสองคน ดูที่หน้า “คำร้องขอแก้เกรด”
        ถ้าเปิดทางที่สอง ใครที่สร้างรอบสอบซ่อมได้จะแก้เกรดใครก็ได้โดยไม่ต้องผ่านใครเลย
      </Notice>
    </>
  );
}

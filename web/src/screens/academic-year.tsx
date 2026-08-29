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
import { api, emptyPage, qs } from '../core/api';
import { href } from '../core/router';
import { useScope } from '../core/scope';
import { termLabel, type Term } from '../core/catalog';
import { TERM_STATUS, thaiDate, thaiDateTime } from '../core/fmt';
import type { Role } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useAsync, useCan,
} from '../ui/kit';
import { useTermPicker } from '../ui/term-picker';

/** /rollover ผูก registrar/director/admin (ไม่มี academic) — เข้มกว่า /academic/* ทั่วไป */
const ACADEMIC_YEAR_ROLES: Role[] = ['registrar', 'director', 'admin'];
/** /timetable/rooms, /staff, /class-groups ผูก registrar/academic/director/admin เหมือนกันหมด */
const OFFICE_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];

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
  class_number: number | null;
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
  kind?: string;
  capacity?: number | null;
  building?: string | null;
}

interface ClassGroup {
  id: string;
  level: string;
  study_year: number;
  code: string;
  cohort: string | null;
  finance_group_th: string | null;
  students: number;
  advisors: { id: string; nameTh: string }[];
}

const LEVEL_LABEL: Record<string, string> = { PVC: 'ปวช.', PVS: 'ปวส.', TVB: 'ทล.บ.' };

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

interface PlaceableStudent {
  id: string;
  student_code: string;
  full_name: string;
  status: string;
  study_year: number | null;
  group_code: string | null;
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

/**
 * จัดนักศึกษาเข้าชั้นปี/ห้อง — เป็นก้อนละไม่เกิน 500 คน (เพดานของ place_students())
 *
 * เหตุผลเดียวกับ registerInChunks ใน registration.tsx — กอง "ยังไม่จัดห้อง"
 * ของวิทยาลัยที่เพิ่งเริ่มใช้ระบบคือนักศึกษาทั้งรุ่น ถ้าไม่แบ่งก้อน ปุ่มจะกดไม่ได้เลย
 */
async function placeInChunks(
  academicYearId: string,
  studentIds: string[],
  studyYear: number,
  groupCode: string | undefined,
): Promise<{ requested: number; placed: number; skipped: { studentId: string; action: string; note: string | null }[] }> {
  const CHUNK = 500;
  const merged = { requested: 0, placed: 0, skipped: [] as { studentId: string; action: string; note: string | null }[] };
  for (let i = 0; i < studentIds.length; i += CHUNK) {
    const chunk = studentIds.slice(i, i + CHUNK);
    const r = await api.post<typeof merged>('/rollover/placements', {
      academicYearId, studentIds: chunk, studyYear, ...(groupCode ? { groupCode } : {}),
    });
    merged.requested += r.requested;
    merged.placed += r.placed;
    merged.skipped.push(...r.skipped);
  }
  return merged;
}

function PlaceStudentsForm({ academicYearId, onDone }: { academicYearId: string; onDone: () => void }) {
  // ต้องส่ง academicYearId ไปด้วยเสมอ — ฝั่ง API join student_class_placement
  // ด้วยเงื่อนไข academic_year_id = $3 ถ้าไม่ส่งไป group_code จะเป็น null
  // เสมอไม่ว่าจะจัดห้องไว้แล้วหรือยัง เพราะ "อะไรก็ตาม = null" ไม่จริงใน SQL
  const students = useAsync(
    () => api.get<PlaceableStudent[]>(`/students${qs({ limit: '200', academicYearId })}`),
    [academicYearId],
  );
  const classGroups = useAsync(() => api.get<ClassGroup[]>('/class-groups'), []);
  const [q, setQ] = useState('');
  const [onlyUnplaced, setOnlyUnplaced] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [studyYear, setStudyYear] = useState('1');
  const [groupCode, setGroupCode] = useState('');
  const [result, setResult] = useState<Awaited<ReturnType<typeof placeInChunks>> | null>(null);
  const [mode, setMode] = useState<'search' | 'place'>('search');

  const visible = (students.data ?? []).filter((s) => {
    if (onlyUnplaced && s.group_code) return false;
    if (s.status !== 'active') return false;
    const needle = q.trim().toLowerCase();
    if (!needle) return true;
    return s.student_code.includes(needle) || s.full_name.toLowerCase().includes(needle);
  });

  const toggleOne = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };
  const selectVisible = () => setSelected(new Set(visible.map((s) => s.id)));
  const clearSelected = () => setSelected(new Set());
  const selectedNames = (students.data ?? []).filter((s) => selected.has(s.id)).map((s) => s.full_name);

  return (
    <Card title="จัดห้องเรียน">
      <div className="classroom-mode-tabs"><button className={mode === 'search' ? 'active' : ''} onClick={() => setMode('search')}>1. ค้นหาและเลือกรายชื่อ</button><button className={mode === 'place' ? 'active' : ''} onClick={() => setMode('place')}>2. กำหนดห้องเรียน <span>{selected.size}</span></button></div>
      {mode === 'search' && <>
      <div className="row">
        <Field label="ค้นหารหัสหรือชื่อ">
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="เช่น 69201 หรือ ปวริศ" />
        </Field>
        <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 22 }}>
          <input type="checkbox" checked={onlyUnplaced} onChange={(e) => setOnlyUnplaced(e.target.checked)} />
          แสดงเฉพาะที่ยังไม่จัดห้อง
        </label>
        <div className="shrink classroom-selection-actions"><button onClick={selectVisible} disabled={visible.length === 0}>เลือกทั้งหมดที่แสดง ({visible.length})</button><button onClick={clearSelected} disabled={selected.size === 0}>ล้างที่เลือก</button></div>
      </div>

      <AsyncView state={students} empty="ไม่มีนักศึกษา">
        {() => (
          <div style={{ maxHeight: 260, overflowY: 'auto', border: '1px solid var(--line)', borderRadius: 8 }}>
            <table>
              <thead>
                <tr>
                  <th style={{ width: 30 }} />
                  <th style={{ width: 150 }}>รหัสนักศึกษา</th>
                  <th>ชื่อ — นามสกุล</th>
                  <th style={{ width: 160 }}>ห้องปัจจุบัน</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <input type="checkbox" checked={selected.has(s.id)} onChange={() => toggleOne(s.id)} />
                    </td>
                    <td className="mono">{s.student_code}</td>
                    <td>{s.full_name}</td>
                    <td>{s.group_code ? `ปี ${s.study_year} ห้อง ${s.group_code}` : 'ยังไม่จัดห้อง'}</td>
                  </tr>
                ))}
                {visible.length === 0 && (
                  <tr><td colSpan={4} style={{ textAlign: 'center', color: 'var(--ink-soft)' }}>ไม่พบรายชื่อ</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </AsyncView>

      <div className="classroom-next"><span>เลือกรายชื่อแล้ว <b>{selected.size}</b> คน</span><button className="primary" disabled={selected.size === 0} onClick={() => setMode('place')}>ไปกำหนดห้องเรียน →</button></div>
      </>}

      {mode === 'place' && <><Notice kind="info">กำหนดชั้นปีและห้องให้กับนักศึกษาที่เลือก {selected.size} คน หากต้องการเปลี่ยนรายชื่อ ให้กลับไปที่ขั้นตอนค้นหา</Notice><div className="classroom-selected-summary"><b>รายชื่อที่เลือก</b><span>{selectedNames.slice(0, 5).join(' · ')}{selectedNames.length > 5 ? ` และอีก ${selectedNames.length - 5} คน` : ''}</span><button className="link" onClick={() => setMode('search')}>แก้ไขรายชื่อ</button></div><div className="row" style={{ marginTop: 10 }}>
        <Field label="ชั้นปี">
          <select value={studyYear} onChange={(e) => setStudyYear(e.target.value)} style={{ maxWidth: 90 }}>
            {[1, 2, 3, 4, 5, 6].map((y) => (
              <option key={y} value={y}>{y}</option>
            ))}
          </select>
        </Field>
        <Field label="ห้องเรียน">
          <AsyncView state={classGroups}>
            {(groups) => <select value={groupCode} onChange={(e) => { const group = groups.find((x) => x.code === e.target.value); setGroupCode(e.target.value); if (group) setStudyYear(String(group.study_year)); }}><option value="">— ยังไม่กำหนดห้อง —</option>{groups.map((group) => <option key={group.id} value={group.code}>{LEVEL_LABEL[group.level]} {group.study_year} / {group.code}</option>)}</select>}
          </AsyncView>
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            confirm={selected.size > 20 ? `จัดห้องให้ ${selected.size} คนพร้อมกัน ยืนยันหรือไม่` : undefined}
            onRun={() => {
              if (selected.size === 0) throw new Error('เลือกนักศึกษาก่อน');
              return placeInChunks(academicYearId, [...selected], Number(studyYear), groupCode.trim() || undefined);
            }}
            onDone={(r) => {
              setResult(r as Awaited<ReturnType<typeof placeInChunks>>);
              setSelected(new Set());
              students.reload();
              onDone();
            }}
          >
            จัดห้องให้ผู้ที่เลือก
          </ActionButton>
        </div>
      </div>

      {result && (
        <Notice kind={result.skipped.length === 0 ? 'ok' : 'warn'}>
          จัดห้องสำเร็จ {result.placed} จาก {result.requested} คน
          {result.skipped.length > 0 && (
            <> — ข้าม {result.skipped.length} คน: {result.skipped.map((s) => s.note).filter(Boolean).join(', ')}</>
          )}
        </Notice>
      )}
      </>}
    </Card>
  );
}

interface GradebookCopyResult {
  sections: number;
  copied: number;
  itemsCopied: number;
  needsAttention: { section: string; note: string | null }[];
}

/**
 * คัดลอกโครงสร้างสมุดคะแนนข้ามภาคเรียน
 *
 * ก่อนหน้านี้ `POST /rollover/gradebooks` มีแล้วและมีเทสต์ (API-58) แต่ไม่มี
 * ปุ่มให้กดเลย — ครูต้องสร้างรายการคะแนนใหม่มือทุกภาคเรียน กดซ้ำได้เสมอ
 * เพราะฝั่ง API ข้ามห้องที่คัดลอกไปแล้วโดยไม่คัดลอกซ้อน (มิฉะนั้นน้ำหนัก
 * คะแนนรวมจะเกินร้อย)
 */
function CopyGradebooksCard({ terms }: { terms: Term[] }) {
  const [fromTermId, setFromTermId] = useState('');
  const [toTermId, setToTermId] = useState('');
  const [result, setResult] = useState<GradebookCopyResult | null>(null);

  return (
    <Card title="คัดลอกโครงสร้างสมุดคะแนนข้ามภาคเรียน">
      <div className="row">
        <label className="field">
          <span>จากภาคเรียน</span>
          <select value={fromTermId} onChange={(e) => setFromTermId(e.target.value)}>
            <option value="">— เลือกภาคเรียนต้นทาง —</option>
            {terms.map((t) => (
              <option key={t.id} value={t.id}>{termLabel(t)}</option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>ไปภาคเรียน</span>
          <select value={toTermId} onChange={(e) => setToTermId(e.target.value)}>
            <option value="">— เลือกภาคเรียนปลายทาง —</option>
            {terms.map((t) => (
              <option key={t.id} value={t.id}>{termLabel(t)}</option>
            ))}
          </select>
        </label>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!fromTermId || !toTermId) throw new Error('เลือกภาคเรียนทั้งสองฝั่งก่อน');
              if (fromTermId === toTermId) throw new Error('ต้นทางกับปลายทางต้องเป็นคนละภาคเรียน');
              return api.post<GradebookCopyResult>('/rollover/gradebooks', { fromTermId, toTermId });
            }}
            onDone={(r) => setResult(r as GradebookCopyResult)}
          >
            คัดลอกโครงสร้างสมุดคะแนน
          </ActionButton>
        </div>
      </div>
      <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
        คัดลอกเฉพาะกลุ่มเรียนที่จับคู่รายวิชาเดียวกันได้ระหว่างสองภาคเรียน — กดซ้ำได้เสมอ ไม่คัดลอกซ้อนให้น้ำหนักคะแนนเกินร้อย
      </div>

      {result && (
        <Notice kind={result.needsAttention.length === 0 ? 'ok' : 'warn'}>
          จับคู่ห้องได้ {result.sections} ห้อง · คัดลอกแล้ว {result.copied} ห้อง ({result.itemsCopied} รายการ)
          {result.needsAttention.length > 0 && (
            <> — ต้องไปตั้งเอง {result.needsAttention.length} ห้อง: {result.needsAttention.map((x) => `${x.section}${x.note ? ` (${x.note})` : ''}`).join(', ')}</>
          )}
        </Notice>
      )}
    </Card>
  );
}

export function AcademicYearScreen() {
  const canUse = useCan(...ACADEMIC_YEAR_ROLES);
  const { terms } = useTermPicker();
  const rollovers = useAsync(() => (canUse ? api.get<RolloverLog[]>('/rollover') : Promise.resolve([])), [canUse]);
  const academicYears = useAsync(
    () => (canUse ? api.get<AcademicYear[]>('/academic/years') : Promise.resolve([])),
    [canUse],
  );

  const [fromYear, setFromYear] = useState('2569');
  const [toYear, setToYear] = useState('2570');
  const [rolloverResult, setRolloverResult] = useState<unknown>(null);
  const [feeScheduleResult, setFeeScheduleResult] = useState<{ linesCopied: number; note: string } | null>(null);

  return (
    <>
      <PageHead
        title="งานวิชาการรายปี"
        sub="เปิดปีการศึกษา ตั้งภาคเรียน และเลื่อนชั้นทั้งรุ่น"
        actions={
          <div className="row" style={{ gap: 8 }}>
            <a href={href('/registry')}>← ศูนย์งานทะเบียน</a>
            <a href={href('/academic-year/sections')}>เปิดกลุ่มเรียน →</a>
            <a href={href('/academic-year/classes')}>จัดห้องเรียน →</a>
            <a href={href('/academic-year/remedial')}>สอบซ่อม/ปรับเกรด →</a>
          </div>
        }
      />

      {!canUse ? (
        <RestrictedNotice roles={ACADEMIC_YEAR_ROLES} />
      ) : (
      <>
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
                        {t.status === 'closed' && (
                          <ActionButton
                            className="ghost"
                            onRun={() => api.post<{ students: number }>(`/gradebook/terms/${t.id}/summary`)}
                          >
                            คำนวณ GPA/GPAX ใหม่
                          </ActionButton>
                        )}
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

      <Card title="คัดลอกค่าเทอมข้ามปีการศึกษา">
        <div className="row">
          <div style={{ color: 'var(--ink-soft)', fontSize: 12, flex: 1 }}>
            ใช้ช่วงปีการศึกษาต้นทาง/ปลายทางเดียวกับด้านบน ({fromYear} → {toYear}) —
            คัดลอกเป็นแบบยังไม่เปิดใช้ งานการเงินต้องตรวจตัวเลขแล้วเปิดเองที่หน้าค่าเทอม
          </div>
          <div className="shrink">
            <ActionButton
              onRun={() =>
                api.post<{ linesCopied: number; active: boolean; note: string }>('/rollover/fee-schedules', {
                  fromYearBe: Number(fromYear),
                  toYearBe: Number(toYear),
                })
              }
              onDone={(r) => setFeeScheduleResult(r as { linesCopied: number; note: string })}
            >
              คัดลอกค่าเทอม
            </ActionButton>
          </div>
        </div>
        {feeScheduleResult && (
          <Notice kind={feeScheduleResult.linesCopied > 0 ? 'ok' : 'warn'}>
            คัดลอกแล้ว {feeScheduleResult.linesCopied} รายการ — {feeScheduleResult.note}
          </Notice>
        )}
      </Card>

      <Card title="จัดห้องเรียน">
        <div className="row" style={{ alignItems: 'center' }}>
          <span>สร้างห้องประจำชั้น และนำรายชื่อนักศึกษาเข้าห้องอยู่ที่หน้าแยก</span>
          <a href={href('/academic-year/classes')} className="button">ไปหน้าจัดห้องเรียน →</a>
        </div>
      </Card>
      </>
      )}
    </>
  );
}

/**
 * หน้าจอแยก: เปิดกลุ่มเรียน + คัดลอกโครงสร้างสมุดคะแนนข้ามภาคเรียน
 *
 * เดิมทั้งสองเรื่องนี้อยู่รวมในหน้า "งานวิชาการรายปี" เดียวกับที่การ์ด
 * "เรียนเสริม/สอบซ่อม/ปรับเกรด" ในศูนย์งานตารางเรียนก็ชี้ไปที่เดียวกัน —
 * สองปุ่มที่อธิบายงานคนละอย่างเปิดมาแล้วเห็นฟอร์มเดียวกันทั้งหมด แยกที่นี่
 * เพื่อให้ "กำหนดอาจารย์ผู้สอนและเปิดกลุ่มเรียน" เปิดมาแล้วเจอเฉพาะงานเปิด
 * กลุ่มเรียนจริง ๆ
 */
export function AcademicSectionsScreen() {
  const canUse = useCan(...OFFICE_ROLES);
  const { terms } = useTermPicker();
  const courses = useAsync(
    () => (canUse ? api.get<CourseRow[]>('/curriculum/courses') : Promise.resolve([])),
    [canUse],
  );
  const staff = useAsync(
    () => (canUse ? api.getPage<StaffRow>('/staff?limit=100') : Promise.resolve(emptyPage<StaffRow>())),
    [canUse],
  );
  const rooms = useAsync(() => (canUse ? api.get<RoomRow[]>('/timetable/rooms') : Promise.resolve([])), [canUse]);

  return (
    <>
      <PageHead
        title="กำหนดอาจารย์ผู้สอนและเปิดกลุ่มเรียน"
        sub="เปิดกลุ่มเรียนพร้อมเลือกผู้สอนประจำรายวิชา แล้วคัดลอกโครงสร้างสมุดคะแนนจากภาคก่อนได้ทันที"
        actions={<a href={href('/academic-year')}>← งานวิชาการรายปี</a>}
      />

      {!canUse ? (
        <RestrictedNotice roles={OFFICE_ROLES} />
      ) : (
      <>
      <CreateSectionForm
        terms={terms.data ?? []}
        courses={courses.data ?? []}
        staff={staff.data?.items ?? []}
        rooms={rooms.data ?? []}
        onDone={() => {}}
      />

      <CopyGradebooksCard terms={terms.data ?? []} />

      <Card>
        <div className="row" style={{ alignItems: 'center' }}>
          <span>วางคาบเรียนและตรวจคาบชนกันได้ที่หน้าจัดตารางสอน</span>
          <a href={href('/timetable')} className="button">ไปหน้าจัดตารางสอน →</a>
        </div>
      </Card>
      </>
      )}
    </>
  );
}

/**
 * หน้าจอแยก: เปิดรอบสอบซ่อม/เรียนปรับเกรด — ดูเหตุผลการแยกที่ AcademicSectionsScreen
 */
export function RemedialScreen() {
  const canUse = useCan(...OFFICE_ROLES);
  const { terms } = useTermPicker();
  const courses = useAsync(
    () => (canUse ? api.get<CourseRow[]>('/curriculum/courses') : Promise.resolve([])),
    [canUse],
  );
  const gradeSymbols = useAsync(
    () => (canUse ? api.get<GradeSymbol[]>('/gradebook/grade-symbols') : Promise.resolve([])),
    [canUse],
  );
  const sessions = useAsync(
    () => (canUse ? api.get<RegradeSession[]>('/regrade/sessions') : Promise.resolve([])),
    [canUse],
  );
  const [sessionId, setSessionId] = useState('');

  return (
    <>
      <PageHead
        title="เรียนเสริม/สอบซ่อม/ปรับเกรด"
        sub="เปิดรอบแก้ผล บันทึกผลสอบซ่อม และลงทะเบียนผู้มีสิทธิ์"
        actions={<a href={href('/academic-year')}>← งานวิชาการรายปี</a>}
      />

      {!canUse ? (
        <RestrictedNotice roles={OFFICE_ROLES} />
      ) : (
      <>
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
      )}
    </>
  );
}

/** หน้าจอแยก: สร้างห้องก่อน แล้วจึงนำรายชื่อนักศึกษาเข้าห้องในอีกหน้าหนึ่ง */
export function AcademicClassroomScreen() {
  const canUse = useCan(...OFFICE_ROLES);
  const years = useAsync(() => (canUse ? api.get<AcademicYear[]>('/academic/years') : Promise.resolve([])), [canUse]);
  const staff = useAsync(
    () => (canUse ? api.getPage<StaffRow>('/staff?limit=100') : Promise.resolve(emptyPage<StaffRow>())),
    [canUse],
  );
  const groups = useAsync(() => (canUse ? api.get<ClassGroup[]>('/class-groups') : Promise.resolve([])), [canUse]);
  const [academicYearId, setAcademicYearId] = useState('');
  const [level, setLevel] = useState('PVC');
  const [studyYear, setStudyYear] = useState('1');
  const [code, setCode] = useState('');
  const [cohort, setCohort] = useState('');
  const [advisorStaffId, setAdvisorStaffId] = useState('');
  const [financeGroupTh, setFinanceGroupTh] = useState('');

  return <>
    <PageHead title="จัดชั้นปีและห้อง" sub="สร้างห้องประจำชั้น เช่น ปวช.1 / CA.1/1 แยกจากห้องกายภาพสำหรับตารางสอน" actions={<div className="row" style={{ gap: 8 }}><a href={href('/registry')}>← ศูนย์งานทะเบียน</a><a href={href('/academic-year/placements')}>จัดนักศึกษาเข้าห้อง →</a></div>} />
    {!canUse ? (
      <RestrictedNotice roles={OFFICE_ROLES} />
    ) : (
    <>
    <Card title="สร้างห้องประจำชั้นใหม่">
      <div className="row">
        <Field label="ปีการศึกษา"><select value={academicYearId} onChange={(e) => setAcademicYearId(e.target.value)}><option value="">— เลือกปีการศึกษา —</option>{(years.data ?? []).map((year) => <option key={year.id} value={year.id}>{year.year_be}</option>)}</select></Field>
        <Field label="ระดับ"><select value={level} onChange={(e) => setLevel(e.target.value)}><option value="PVC">ปวช.</option><option value="PVS">ปวส.</option><option value="TVB">ทล.บ.</option></select></Field>
        <Field label="ชั้นปี"><select value={studyYear} onChange={(e) => setStudyYear(e.target.value)}>{[1,2,3,4,5,6].map((year) => <option key={year} value={year}>{year}</option>)}</select></Field>
        <Field label="ห้อง"><input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น CA.1/1" /></Field>
        <Field label="รุ่นที่ (ถ้ามี)"><input value={cohort} onChange={(e) => setCohort(e.target.value)} placeholder="เช่น 2569" /></Field>
        <Field label="อาจารย์ที่ปรึกษา"><select value={advisorStaffId} onChange={(e) => setAdvisorStaffId(e.target.value)}><option value="">— ยังไม่ระบุ —</option>{(staff.data?.items ?? []).map((person) => <option key={person.id} value={person.id}>{person.full_name}</option>)}</select></Field>
        <Field label="กลุ่มการเงิน (ถ้ามี)"><input value={financeGroupTh} onChange={(e) => setFinanceGroupTh(e.target.value)} /></Field>
        <div className="shrink"><ActionButton className="primary" onRun={() => {
          if (!academicYearId || !code.trim()) throw new Error('เลือกปีการศึกษาและกรอกห้องให้ครบ');
          return api.post('/class-groups', { academicYearId, level, studyYear: Number(studyYear), code: code.trim(), ...(cohort.trim() ? { cohort: cohort.trim() } : {}), ...(advisorStaffId ? { advisorStaffIds: [advisorStaffId] } : {}), ...(financeGroupTh.trim() ? { financeGroupTh: financeGroupTh.trim() } : {}) });
        }} onDone={() => { setCode(''); setCohort(''); setAdvisorStaffId(''); setFinanceGroupTh(''); groups.reload(); }}>สร้างห้องประจำชั้น</ActionButton></div>
      </div>
    </Card>
    <TableCard title="ห้องประจำชั้นที่สร้างแล้ว">
      <AsyncView state={groups} empty="ยังไม่มีห้องประจำชั้น">{(items) => <table><thead><tr><th>เกรด</th><th>ห้อง</th><th>รุ่นที่</th><th className="num">นักศึกษา</th><th>ข้อมูล</th><th></th></tr></thead><tbody>
        {items.map((group) => <ClassGroupRow key={group.id} group={group} onDone={() => groups.reload()} />)}
      </tbody></table>}</AsyncView>
    </TableCard>
    </>
    )}
  </>;
}

function ClassGroupRow({ group, onDone }: { group: ClassGroup; onDone: () => void }) {
  const [editing, setEditing] = useState(false);
  const [code, setCode] = useState(group.code);
  const [cohort, setCohort] = useState(group.cohort ?? '');
  const [financeGroupTh, setFinanceGroupTh] = useState(group.finance_group_th ?? '');

  if (!editing) {
    return <tr>
      <td>{LEVEL_LABEL[group.level]} {group.study_year}</td>
      <td>{group.code}</td>
      <td>{group.cohort ?? '—'}</td>
      <td className="num">{group.students}</td>
      <td>{group.advisors.map((advisor) => advisor.nameTh).join(', ') || '—'}{group.finance_group_th ? ` · ${group.finance_group_th}` : ''}</td>
      <td className="row" style={{ gap: 6 }}>
        <button onClick={() => setEditing(true)}>แก้ไข</button>
        <ActionButton
          confirm={`ปิดใช้งานห้อง ${group.code} — นักศึกษาที่จัดไว้แล้วไม่ถูกย้ายออก แต่ห้องนี้จะไม่ขึ้นให้เลือกอีก ยืนยันหรือไม่`}
          onRun={() => api.del(`/class-groups/${group.id}`)}
          onDone={onDone}
        >
          ปิดใช้งาน
        </ActionButton>
      </td>
    </tr>;
  }

  return <tr>
    <td>{LEVEL_LABEL[group.level]} {group.study_year}</td>
    <td><input value={code} onChange={(e) => setCode(e.target.value)} style={{ width: 100 }} /></td>
    <td><input value={cohort} onChange={(e) => setCohort(e.target.value)} style={{ width: 90 }} /></td>
    <td className="num">{group.students}</td>
    <td><input value={financeGroupTh} onChange={(e) => setFinanceGroupTh(e.target.value)} placeholder="กลุ่มการเงิน" style={{ width: 140 }} /></td>
    <td className="row" style={{ gap: 6 }}>
      <ActionButton
        className="primary"
        onRun={() => {
          if (!code.trim()) throw new Error('กรอกรหัสห้องก่อน');
          return api.patch(`/class-groups/${group.id}`, {
            level: group.level,
            studyYear: group.study_year,
            code: code.trim(),
            ...(cohort.trim() ? { cohort: cohort.trim() } : {}),
            ...(financeGroupTh.trim() ? { financeGroupTh: financeGroupTh.trim() } : {}),
          });
        }}
        onDone={() => { setEditing(false); onDone(); }}
      >
        บันทึก
      </ActionButton>
      <button onClick={() => setEditing(false)}>ยกเลิก</button>
    </td>
  </tr>;
}

/** หน้าจอแยก: จัดรายชื่อนักศึกษาเข้าชั้นปี/ห้องหลังจากสร้างห้องแล้ว */
export function AcademicPlacementScreen() {
  const canUse = useCan(...ACADEMIC_YEAR_ROLES);
  const scope = useScope();
  const ayId = scope.yearId;
  const placements = useAsync(
    () => (canUse && ayId ? api.get<Placement[]>(`/rollover/placements${qs({ academicYearId: ayId })}`) : Promise.resolve([])),
    [canUse, ayId],
  );

  return <>
    <PageHead title="จัดห้องเรียน" sub="ค้นหารายชื่อ เลือกนักศึกษา แล้วกำหนดชั้นปีและห้องเรียน" actions={<div className="row" style={{ gap: 8 }}><a href={href('/student-center')}>← ศูนย์นักศึกษา</a><a href={href('/academic-year/classes')}>จัดการห้องประจำชั้น</a></div>} />
    {!canUse ? (
      <RestrictedNotice roles={ACADEMIC_YEAR_ROLES} />
    ) : (
    <>
    {!ayId && <Notice kind="info">ยังไม่มีปีการศึกษาในส่วนหัวของระบบ ให้ผู้ดูแลเพิ่มปีการศึกษาก่อนจึงจะจัดห้องได้</Notice>}
    {ayId && <PlaceStudentsForm academicYearId={ayId} onDone={() => placements.reload()} />}
    {ayId && <RenumberClassNumbersCard academicYearId={ayId} placements={placements.data ?? []} onDone={() => placements.reload()} />}
    {ayId && <TableCard title="นักศึกษาแยกตามชั้นปีและห้อง">
      <AsyncView state={placements} empty="ยังไม่ได้จัดห้องให้ปีการศึกษานี้">
        {(rows) => <table><thead><tr><th style={{ width: 100 }}>ชั้นปี</th><th style={{ width: 120 }}>ห้อง</th><th style={{ width: 80 }}>เลขที่</th><th style={{ width: 150 }}>รหัสนักศึกษา</th><th>ชื่อ — นามสกุล</th></tr></thead><tbody>
          {rows.map((student) => <tr key={student.student_code}><td>ปวช. {student.study_year}</td><td>{student.group_code ?? '—'}</td><td>{student.class_number ?? '—'}</td><td className="mono">{student.student_code}</td><td>{student.full_name}</td></tr>)}
        </tbody></table>}
      </AsyncView>
    </TableCard>}
    </>
    )}
  </>;
}

function RenumberClassNumbersCard({ academicYearId, placements, onDone }: { academicYearId:string; placements:Placement[]; onDone:()=>void }) {
  const rooms = [...new Map(placements.filter((p) => p.group_code).map((p) => [`${p.study_year}|${p.group_code}`, p])).values()];
  const [roomKey, setRoomKey] = useState('');
  const selected = rooms.find((room) => `${room.study_year}|${room.group_code}` === roomKey);
  return <Card title="เรียงเลขที่ในห้อง"><div className="row"><Field label="ห้องเรียน"><select value={roomKey} onChange={(e) => setRoomKey(e.target.value)}><option value="">— เลือกห้อง —</option>{rooms.map((room) => <option key={`${room.study_year}|${room.group_code}`} value={`${room.study_year}|${room.group_code}`}>ชั้นปี {room.study_year} / ห้อง {room.group_code}</option>)}</select></Field><div style={{ flex:2, color:'var(--ink-soft)', fontSize:12 }}>ระบบจะเรียงเลขที่ใหม่ตามรหัสนักศึกษา จากน้อยไปมาก แล้วบันทึกลงระเบียนของทุกคนในห้อง</div><div className="shrink"><ActionButton className="primary" confirm={selected ? `เรียงเลขที่ใหม่ให้ห้อง ${selected.group_code} จำนวน ${placements.filter((p) => p.study_year === selected.study_year && p.group_code === selected.group_code).length} คน ยืนยันหรือไม่` : undefined} onRun={() => { if (!selected?.group_code) throw new Error('เลือกห้องก่อน'); return api.post('/rollover/placements/renumber', { academicYearId, studyYear:selected.study_year, groupCode:selected.group_code }); }} onDone={onDone}>เรียงเลขที่ใหม่</ActionButton></div></div></Card>;
}

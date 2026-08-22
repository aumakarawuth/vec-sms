/**
 * ตารางสอบ
 *
 * ─── ทำไมเริ่มจากภาคเรียนแล้วค่อยเลือกกลุ่มเรียน ไม่ใช่ค้นหากลุ่มเรียนตรง ๆ ───
 * งานทะเบียนวางตารางสอบทีละภาคเรียน (กลางภาค/ปลายภาค) — เห็นทุกกลุ่มเรียน
 * ของภาคนั้นพร้อมกันช่วยจับได้ว่ากลุ่มไหนยังไม่ได้จัดสอบก่อนหมดเวลา
 *
 * ─── ทำไมชนกันแล้วปฏิเสธพร้อมบอกเหตุผล ไม่ใช่แค่เตือน ───
 * ห้องสอบ/กรรมการคุมสอบ/นักศึกษาชนกันคือความผิดพลาดที่แก้หน้างานไม่ได้เลย
 * (ถึงเวลาสอบจริงแล้วห้องไม่ว่างหรือกรรมการไปคุมที่อื่น) API ปฏิเสธการชน
 * ไว้ตั้งแต่ก่อนบันทึกเสมอ (exam_conflicts() — ดู 0075/0076)
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { fetchSections, type Section } from '../core/catalog';
import { thaiDate } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

interface Room {
  id: string;
  code: string;
  name_th: string;
}

interface StaffRow {
  id: string;
  staff_code: string;
  full_name: string;
}

interface Proctor {
  staffId: string;
  staffCode: string;
  fullName: string;
}

interface ExamSession {
  id: string;
  kind: string;
  exam_date: string;
  period_from: number;
  period_to: number;
  note: string | null;
  class_section_id: string;
  section_no: string;
  course_code: string;
  course_name: string;
  room_id: string | null;
  room_code: string | null;
  room_name: string | null;
  proctors: Proctor[];
}

const KIND_LABEL: Record<string, string> = { midterm: 'กลางภาค', final: 'ปลายภาค' };

function CreateExamForm({
  sections, rooms, onDone,
}: { sections: Section[]; rooms: Room[]; onDone: () => void }) {
  const [classSectionId, setClassSectionId] = useState('');
  const [kind, setKind] = useState('final');
  const [examDate, setExamDate] = useState('');
  const [periodFrom, setPeriodFrom] = useState('1');
  const [periodTo, setPeriodTo] = useState('2');
  const [roomId, setRoomId] = useState('');

  return (
    <Card title="จัดตารางสอบ">
      <div className="row">
        <label className="field" style={{ flex: 2 }}>
          <span>กลุ่มเรียน</span>
          <select value={classSectionId} onChange={(e) => setClassSectionId(e.target.value)}>
            <option value="">— เลือกกลุ่มเรียน —</option>
            {sections.map((s) => (
              <option key={s.id} value={s.id}>
                {s.code} {s.name_th} · กลุ่ม {s.section_no} · {s.teacher_name || 'ยังไม่มีครู'}
              </option>
            ))}
          </select>
        </label>
        <Field label="ประเภทสอบ">
          <select value={kind} onChange={(e) => setKind(e.target.value)} style={{ maxWidth: 130 }}>
            <option value="midterm">กลางภาค</option>
            <option value="final">ปลายภาค</option>
          </select>
        </Field>
        <Field label="วันที่สอบ">
          <input type="date" value={examDate} onChange={(e) => setExamDate(e.target.value)} />
        </Field>
        <Field label="คาบเริ่ม">
          <input type="number" min={1} max={20} value={periodFrom} onChange={(e) => setPeriodFrom(e.target.value)} style={{ maxWidth: 80 }} />
        </Field>
        <Field label="คาบสิ้นสุด">
          <input type="number" min={1} max={20} value={periodTo} onChange={(e) => setPeriodTo(e.target.value)} style={{ maxWidth: 80 }} />
        </Field>
        <label className="field">
          <span>ห้องสอบ (ถ้ามี)</span>
          <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
            <option value="">— ยังไม่ระบุห้อง —</option>
            {rooms.map((r) => (
              <option key={r.id} value={r.id}>{r.code} {r.name_th}</option>
            ))}
          </select>
        </label>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!classSectionId) throw new Error('เลือกกลุ่มเรียนก่อน');
              if (!examDate) throw new Error('เลือกวันที่สอบ');
              return api.post('/exam-schedule', {
                classSectionId, kind, examDate,
                periodFrom: Number(periodFrom), periodTo: Number(periodTo),
                ...(roomId ? { roomId } : {}),
              });
            }}
            onDone={() => { setClassSectionId(''); setExamDate(''); onDone(); }}
          >
            จัดตารางสอบ
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function ProctorList({
  session, staff, onDone,
}: { session: ExamSession; staff: StaffRow[]; onDone: () => void }) {
  const [staffId, setStaffId] = useState('');
  const assigned = new Set(session.proctors.map((p) => p.staffId));
  const available = staff.filter((s) => !assigned.has(s.id));

  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center' }}>
      {session.proctors.map((p) => (
        <span key={p.staffId} className="badge default" style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
          {p.fullName}
          <ActionButton
            className="ghost"
            confirm={`เอา ${p.fullName} ออกจากกรรมการคุมสอบนี้ ยืนยันหรือไม่`}
            onRun={() => api.del(`/exam-schedule/${session.id}/proctors/${p.staffId}`)}
            onDone={onDone}
          >
            ×
          </ActionButton>
        </span>
      ))}
      {session.proctors.length === 0 && <span className="hint">ยังไม่มีกรรมการคุมสอบ</span>}
      <select value={staffId} onChange={(e) => setStaffId(e.target.value)} style={{ maxWidth: 220 }}>
        <option value="">— เพิ่มกรรมการ —</option>
        {available.map((s) => (
          <option key={s.id} value={s.id}>{s.full_name} ({s.staff_code})</option>
        ))}
      </select>
      <ActionButton
        onRun={() => {
          if (!staffId) throw new Error('เลือกกรรมการก่อน');
          return api.post(`/exam-schedule/${session.id}/proctors`, { staffId });
        }}
        onDone={() => { setStaffId(''); onDone(); }}
      >
        เพิ่ม
      </ActionButton>
    </div>
  );
}

export function ExamScheduleScreen() {
  const { terms, termId, term, setTerm } = useTermPicker();
  const sections = useAsync(() => (termId ? fetchSections(termId) : Promise.resolve([])), [termId]);
  const rooms = useAsync(() => api.get<Room[]>('/timetable/rooms'), []);
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=100'), []);
  const exams = useAsync(
    () => (termId ? api.get<ExamSession[]>(`/exam-schedule${qs({ termId })}`) : Promise.resolve([])),
    [termId],
  );

  return (
    <>
      <PageHead
        title="ตารางสอบ"
        sub="จัดวัน เวลา ห้อง และกรรมการคุมสอบของแต่ละกลุ่มเรียน"
        actions={terms.data && <TermSelect terms={terms.data} termId={termId} onChange={setTerm} />}
      />

      {!termId && <Notice kind="info">เลือกภาคเรียนก่อน</Notice>}

      {termId && (
        <CreateExamForm
          sections={sections.data ?? []}
          rooms={rooms.data ?? []}
          onDone={() => exams.reload()}
        />
      )}

      {termId && (
        <TableCard title={`ตารางสอบที่จัดไว้แล้ว${term ? ` — ภาคเรียนที่ ${term.ordinal}/${term.year_be}` : ''}`}>
          <AsyncView state={exams} empty="ยังไม่มีตารางสอบในภาคเรียนนี้">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 90 }}>วันสอบ</th>
                    <th style={{ width: 90 }}>คาบ</th>
                    <th style={{ width: 90 }}>ประเภท</th>
                    <th>รายวิชา</th>
                    <th style={{ width: 130 }}>ห้องสอบ</th>
                    <th>กรรมการคุมสอบ</th>
                    <th style={{ width: 70 }} />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((x) => (
                    <tr key={x.id}>
                      <td>{thaiDate(x.exam_date)}</td>
                      <td>{x.period_from}–{x.period_to}</td>
                      <td><Badge kind="default">{KIND_LABEL[x.kind] ?? x.kind}</Badge></td>
                      <td className="mono">{x.course_code} <span className="hint">กลุ่ม {x.section_no}</span></td>
                      <td>{x.room_code ? `${x.room_code} ${x.room_name}` : <span className="hint">— ไม่ระบุห้อง —</span>}</td>
                      <td><ProctorList session={x} staff={staff.data?.items ?? []} onDone={() => exams.reload()} /></td>
                      <td>
                        <ActionButton
                          className="ghost"
                          confirm={`ยกเลิกตารางสอบวิชา ${x.course_code} วันที่ ${thaiDate(x.exam_date)} ยืนยันหรือไม่`}
                          onRun={() => api.del(`/exam-schedule/${x.id}`)}
                          onDone={() => exams.reload()}
                        >
                          ยกเลิก
                        </ActionButton>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>
      )}
    </>
  );
}

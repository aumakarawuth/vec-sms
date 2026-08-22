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

/** ฟิลด์แก้ไขได้ของ POST /exam-schedule/:id — roomId: null ถอดห้องออกได้จริง ต่างจากไม่ส่งมาเลย */
interface UpdateExamPayload {
  examDate: string;
  periodFrom: number;
  periodTo: number;
  roomId: string | null;
  note?: string;
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
  const [note, setNote] = useState('');

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
        <label className="field" style={{ flex: 2 }}>
          <span>หมายเหตุ (ถ้ามี)</span>
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="เช่น นำบัตรนักศึกษามาด้วย" />
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
                ...(note.trim() ? { note: note.trim() } : {}),
              });
            }}
            onDone={() => { setClassSectionId(''); setExamDate(''); setNote(''); onDone(); }}
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

function ExamEditRow({
  session, rooms, onDone, onCancel,
}: { session: ExamSession; rooms: Room[]; onDone: () => void; onCancel: () => void }) {
  const [examDate, setExamDate] = useState(session.exam_date.slice(0, 10));
  const [periodFrom, setPeriodFrom] = useState(String(session.period_from));
  const [periodTo, setPeriodTo] = useState(String(session.period_to));
  const [roomId, setRoomId] = useState(session.room_id ?? '');
  const [note, setNote] = useState(session.note ?? '');

  return (
    <tr>
      <td colSpan={7}>
        <div className="row">
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
            <span>ห้องสอบ</span>
            <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
              <option value="">— ไม่ระบุห้อง —</option>
              {rooms.map((r) => (
                <option key={r.id} value={r.id}>{r.code} {r.name_th}</option>
              ))}
            </select>
          </label>
          <label className="field" style={{ flex: 2 }}>
            <span>หมายเหตุ</span>
            <input value={note} onChange={(e) => setNote(e.target.value)} />
          </label>
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() => {
                if (!examDate) throw new Error('เลือกวันที่สอบ');
                const payload: UpdateExamPayload = {
                  examDate,
                  periodFrom: Number(periodFrom),
                  periodTo: Number(periodTo),
                  // ส่ง null ตรง ๆ เมื่อเลือก "ไม่ระบุห้อง" — ต่างจากไม่ส่งฟิลด์นี้เลย
                  // ซึ่งฝั่ง API ตีความว่า "ไม่แตะห้องเดิม" (ดูคอมเมนต์ที่ service)
                  roomId: roomId || null,
                  ...(note.trim() ? { note: note.trim() } : {}),
                };
                return api.post(`/exam-schedule/${session.id}`, payload);
              }}
              onDone={onDone}
            >
              บันทึกการแก้ไข
            </ActionButton>
          </div>
          <div className="shrink">
            <button className="ghost" onClick={onCancel}>ยกเลิกการแก้ไข</button>
          </div>
        </div>
        <div className="hint">ตรวจการชนห้อง/กรรมการคุมสอบ/นักศึกษาใหม่ทั้งหมดก่อนบันทึกเสมอ</div>
      </td>
    </tr>
  );
}

function ExamRow({
  session, rooms, staff, onDone,
}: { session: ExamSession; rooms: Room[]; staff: StaffRow[]; onDone: () => void }) {
  const [editing, setEditing] = useState(false);

  if (editing) {
    return (
      <ExamEditRow
        session={session}
        rooms={rooms}
        onCancel={() => setEditing(false)}
        onDone={() => { setEditing(false); onDone(); }}
      />
    );
  }

  return (
    <tr>
      <td>{thaiDate(session.exam_date)}</td>
      <td>{session.period_from}–{session.period_to}</td>
      <td><Badge kind="default">{KIND_LABEL[session.kind] ?? session.kind}</Badge></td>
      <td className="mono">
        {session.course_code} <span className="hint">กลุ่ม {session.section_no}</span>
        {session.note && <div className="hint">{session.note}</div>}
      </td>
      <td>{session.room_code ? `${session.room_code} ${session.room_name}` : <span className="hint">— ไม่ระบุห้อง —</span>}</td>
      <td><ProctorList session={session} staff={staff} onDone={onDone} /></td>
      <td>
        <button className="ghost" onClick={() => setEditing(true)}>แก้ไข</button>{' '}
        <ActionButton
          className="ghost"
          confirm={`ยกเลิกตารางสอบวิชา ${session.course_code} วันที่ ${thaiDate(session.exam_date)} ยืนยันหรือไม่`}
          onRun={() => api.del(`/exam-schedule/${session.id}`)}
          onDone={onDone}
        >
          ยกเลิก
        </ActionButton>
      </td>
    </tr>
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
                    <ExamRow
                      key={x.id}
                      session={x}
                      rooms={rooms.data ?? []}
                      staff={staff.data?.items ?? []}
                      onDone={() => exams.reload()}
                    />
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

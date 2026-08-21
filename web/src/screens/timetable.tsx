/**
 * ตารางสอน
 *
 * ─── ทำไมตัวจัดอัตโนมัติไม่ใช่ปุ่มเดียวจบ ───
 * ตัวจัดเป็นแบบโลภ ไม่ใช่หาคำตอบที่ดีที่สุด — วางให้ได้มากที่สุดเท่าที่
 * ไม่ชน แล้วรายงานวิชาที่วางไม่ครบให้คนไปตัดสินใจต่อ หน้าจอจึงต้องแสดง
 * ผลที่วางไม่ได้ให้เห็น ไม่ใช่บอกแค่ว่า "สำเร็จ"
 *
 * ─── ทำไมต้องดูคาบที่ชนหลังวางเสร็จ ───
 * exclusion constraint กันการชนของห้องและครูไว้แล้วตอนเขียน แต่การชนที่
 * เกิดกับ**ผู้เรียน** (นักศึกษาคนเดียวลงสองวิชาที่คาบเดียวกัน) เป็นเรื่อง
 * ของการลงทะเบียนซึ่งเกิดทีหลัง — จึงต้องตรวจซ้ำหลังตารางนิ่งแล้ว
 */
import { useEffect, useState } from 'react';
import { api } from '../core/api';
import { fetchSections, type Section } from '../core/catalog';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const DAY = ['', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

const ROOM_KIND: Record<string, string> = {
  classroom: 'ห้องเรียน',
  workshop: 'ห้องฝึกปฏิบัติ',
  lab: 'ห้องปฏิบัติการ',
  computer: 'ห้องคอมพิวเตอร์',
  auditorium: 'หอประชุม',
  outdoor: 'กลางแจ้ง',
};

interface Room {
  id: string;
  code: string;
  name_th: string;
  kind: string;
  capacity: number | null;
  building: string | null;
}

interface Conflict {
  class_section_id: string;
  label: string;
  day_of_week: number;
  period_from: number;
  period_to: number;
  message_th?: string;
  kind?: string;
}

interface Suggestion {
  day_of_week: number;
  period_from: number;
  period_to: number;
  avoids: boolean;
  note: string | null;
}

interface Timeslot {
  id: string;
  day_of_week: number;
  period_from: number;
  period_to: number;
  room_id: string | null;
  room_code: string | null;
  room_name: string | null;
}

interface StaffRow {
  id: string;
  person_id: string;
  staff_code: string;
  full_name: string;
}

function TransferRow({ slot, rooms, onDone }: { slot: Timeslot; rooms: Room[]; onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const [dayOfWeek, setDayOfWeek] = useState(String(slot.day_of_week));
  const [periodFrom, setPeriodFrom] = useState(String(slot.period_from));
  const [periodTo, setPeriodTo] = useState(String(slot.period_to));
  const [roomId, setRoomId] = useState(slot.room_id ?? '');

  return (
    <>
      <tr>
        <td>{DAY[slot.day_of_week]}</td>
        <td>{slot.period_from}–{slot.period_to}</td>
        <td>{slot.room_code ? `${slot.room_code} ${slot.room_name}` : '— ไม่ระบุห้อง —'}</td>
        <td>
          <button className="ghost" onClick={() => setOpen(!open)}>{open ? 'ปิด' : 'ย้าย'}</button>{' '}
          <ActionButton
            confirm="ยกเลิกคาบนี้ ยืนยันหรือไม่ — ไม่มีคาบใหม่มาแทน"
            onRun={() => api.post(`/timetable/slots/${slot.id}/remove`)}
            onDone={onDone}
          >
            ยกเลิก
          </ActionButton>
        </td>
      </tr>
      {open && (
        <tr>
          <td colSpan={4}>
            <div className="row">
              <Field label="วัน">
                <select value={dayOfWeek} onChange={(e) => setDayOfWeek(e.target.value)} style={{ maxWidth: 130 }}>
                  {[1, 2, 3, 4, 5, 6, 7].map((d) => (
                    <option key={d} value={d}>{DAY[d]}</option>
                  ))}
                </select>
              </Field>
              <Field label="คาบเริ่ม">
                <input type="number" min={1} max={20} value={periodFrom} onChange={(e) => setPeriodFrom(e.target.value)} style={{ maxWidth: 80 }} />
              </Field>
              <Field label="คาบสิ้นสุด">
                <input type="number" min={1} max={20} value={periodTo} onChange={(e) => setPeriodTo(e.target.value)} style={{ maxWidth: 80 }} />
              </Field>
              <label className="field">
                <span>ห้อง (ถ้ามี)</span>
                <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
                  <option value="">— ไม่ระบุห้อง —</option>
                  {rooms.map((r) => (
                    <option key={r.id} value={r.id}>{r.code} {r.name_th}</option>
                  ))}
                </select>
              </label>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post(`/timetable/slots/${slot.id}/move`, {
                      dayOfWeek: Number(dayOfWeek),
                      periodFrom: Number(periodFrom),
                      periodTo: Number(periodTo),
                      ...(roomId ? { roomId } : {}),
                    })
                  }
                  onDone={() => { setOpen(false); onDone(); }}
                >
                  ย้ายคาบนี้
                </ActionButton>
              </div>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}

function TransferSectionForm({
  sections, rooms, staff,
}: { sections: Section[]; rooms: Room[]; staff: StaffRow[] }) {
  const [sectionId, setSectionId] = useState('');
  const slots = useAsync(
    () => (sectionId ? api.get<Timeslot[]>(`/academic/sections/${sectionId}/timeslots`) : Promise.resolve([])),
    [sectionId],
  );
  const [teacherId, setTeacherId] = useState('');
  const [reassignRoomId, setReassignRoomId] = useState('');

  const current = sections.find((s) => s.id === sectionId);

  return (
    <Card title="โอนย้ายตารางสอน — เปลี่ยนผู้สอน/ห้อง หรือย้าย/ยกเลิกคาบ">
      <div className="row">
        <label className="field" style={{ flex: 2 }}>
          <span>กลุ่มเรียน</span>
          <select value={sectionId} onChange={(e) => { setSectionId(e.target.value); setTeacherId(''); setReassignRoomId(''); }}>
            <option value="">— เลือกกลุ่มเรียน —</option>
            {sections.map((s) => (
              <option key={s.id} value={s.id}>
                {s.code} {s.name_th} · กลุ่ม {s.section_no} · {s.teacher_name || 'ยังไม่มีครู'}
              </option>
            ))}
          </select>
        </label>
      </div>

      {sectionId && (
        <>
          <div className="row">
            <label className="field">
              <span>เปลี่ยนผู้สอนเป็น</span>
              <select value={teacherId} onChange={(e) => setTeacherId(e.target.value)}>
                <option value="">— ไม่เปลี่ยน —</option>
                {staff.map((t) => (
                  <option key={t.id} value={t.id}>{t.full_name} ({t.staff_code})</option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>เปลี่ยนห้องประจำกลุ่มเป็น</span>
              <select value={reassignRoomId} onChange={(e) => setReassignRoomId(e.target.value)}>
                <option value="">— ไม่เปลี่ยน —</option>
                {rooms.map((r) => (
                  <option key={r.id} value={r.id}>{r.code} {r.name_th}</option>
                ))}
              </select>
            </label>
            <div className="shrink">
              <ActionButton
                onRun={() => {
                  if (!teacherId && !reassignRoomId) throw new Error('เลือกผู้สอนใหม่หรือห้องใหม่ก่อน');
                  return api.post(`/academic/sections/${sectionId}/reassign`, {
                    ...(teacherId ? { teacherId } : {}),
                    ...(reassignRoomId ? { roomId: reassignRoomId } : {}),
                  });
                }}
                onDone={() => { setTeacherId(''); setReassignRoomId(''); }}
              >
                บันทึกการเปลี่ยนแปลง
              </ActionButton>
            </div>
          </div>
          {current && (
            <div style={{ color: 'var(--ink-soft)', fontSize: 12, marginBottom: 10 }}>
              ปัจจุบัน — ผู้สอน: {current.teacher_name || 'ยังไม่มี'} · ห้องประจำกลุ่ม: {current.room_name ?? 'ยังไม่มี'}
            </div>
          )}

          <AsyncView state={slots} empty="กลุ่มเรียนนี้ยังไม่มีคาบที่วางไว้">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 110 }}>วัน</th>
                    <th style={{ width: 110 }}>คาบ</th>
                    <th>ห้อง</th>
                    <th style={{ width: 160 }} />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((s) => (
                    <TransferRow key={s.id} slot={s} rooms={rooms} onDone={() => slots.reload()} />
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </>
      )}
    </Card>
  );
}

export function TimetableScreen() {
  const { terms, termId, setTerm } = useTermPicker();
  const rooms = useAsync(() => api.get<Room[]>('/timetable/rooms'), []);
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=100'), []);
  const sections = useAsync(
    () => (termId ? fetchSections(termId) : Promise.resolve([])),
    [termId],
  );
  // เส้นทางนี้คืน { total, conflicts } ไม่ใช่อาร์เรย์เปล่า
  const conflicts = useAsync(
    () =>
      termId
        ? api.get<{ total: number; conflicts: Conflict[] }>(
            `/timetable/terms/${termId}/conflicts`,
          )
        : Promise.resolve({ total: 0, conflicts: [] }),
    [termId],
  );

  const [sectionId, setSectionId] = useState('');
  const [periods, setPeriods] = useState('2');
  const [roomId, setRoomId] = useState('');
  const [suggestions, setSuggestions] = useState<Suggestion[] | null>(null);
  const [autoResult, setAutoResult] = useState<unknown>(null);

  const [roomCode, setRoomCode] = useState('');
  const [roomName, setRoomName] = useState('');
  const [roomKind, setRoomKind] = useState('classroom');
  const [roomCapacity, setRoomCapacity] = useState('');
  const [roomBuilding, setRoomBuilding] = useState('');

  useEffect(() => {
    setSectionId('');
    setSuggestions(null);
    setAutoResult(null);
  }, [termId]);

  return (
    <>
      <PageHead
        title="ตารางสอน"
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <Card title="จัดตารางอัตโนมัติทั้งภาคเรียน">
        <div className="row">
          <div className="shrink">
            <ActionButton
              className="primary"
              confirm="ตัวจัดจะวางคาบให้กลุ่มเรียนที่ยังไม่มีตาราง ยืนยันหรือไม่"
              onRun={() => api.post(`/timetable/terms/${termId}/auto-schedule`)}
              onDone={(r) => {
                setAutoResult(r);
                conflicts.reload();
              }}
            >
              จัดตารางอัตโนมัติ
            </ActionButton>
          </div>
          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            ตัวจัดเป็นแบบโลภ — วางให้ได้มากที่สุดเท่าที่ไม่ชน แล้วรายงานวิชาที่วางไม่ครบ
            ให้คนไปตัดสินใจต่อ ไม่ใช่การหาคำตอบที่ดีที่สุด
          </div>
        </div>
        {autoResult !== null && (
          <Notice kind="info">
            <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 12 }}>
              {JSON.stringify(autoResult, null, 2)}
            </pre>
          </Notice>
        )}
      </Card>

      <Card title="วางคาบให้กลุ่มเรียนทีละกลุ่ม">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>กลุ่มเรียน</span>
            <AsyncView state={sections} empty="ภาคเรียนนี้ยังไม่มีกลุ่มเรียน">
              {(rows) => (
                <select value={sectionId} onChange={(e) => setSectionId(e.target.value)}>
                  <option value="">— เลือกกลุ่มเรียน —</option>
                  {rows.map((s: Section) => (
                    <option key={s.id} value={s.id}>
                      {s.code} {s.name_th} · กลุ่ม {s.section_no} · {s.teacher_name || 'ยังไม่มีครู'}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
          <label className="field" style={{ maxWidth: 140 }}>
            <span>จำนวนคาบติดกัน</span>
            <select value={periods} onChange={(e) => setPeriods(e.target.value)}>
              {[1, 2, 3, 4].map((n) => (
                <option key={n} value={n}>{n} คาบ</option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>ห้อง (ถ้าระบุ)</span>
            <AsyncView state={rooms}>
              {(list) => (
                <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
                  <option value="">— ไม่ระบุห้อง —</option>
                  {list.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.code} {r.name_th}
                      {r.capacity ? ` (${r.capacity} ที่)` : ''}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
          <div className="shrink">
            <ActionButton
              onRun={() =>
                api.get<Suggestion[]>(
                  `/timetable/suggest?classSectionId=${sectionId}&periods=${periods}` +
                    (roomId ? `&roomId=${roomId}` : '') +
                    (termId ? `&termId=${termId}` : ''),
                )
              }
              onDone={(r) => setSuggestions(r as Suggestion[])}
            >
              หาคาบว่าง
            </ActionButton>
          </div>
        </div>

        {suggestions && (
          suggestions.length === 0 ? (
            <Notice kind="warn">
              ไม่มีคาบว่างที่วางได้เลย — ลองลดจำนวนคาบติดกัน หรือไม่ระบุห้อง
            </Notice>
          ) : (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>วัน</th>
                  <th style={{ width: 120 }}>คาบ</th>
                  <th style={{ width: 150 }}>เลี่ยงคำขอครู</th>
                  <th>หมายเหตุ</th>
                  <th style={{ width: 110 }}>วางคาบนี้</th>
                </tr>
              </thead>
              <tbody>
                {suggestions.map((s, i) => (
                  <tr key={i}>
                    <td>{DAY[s.day_of_week]}</td>
                    <td>
                      {s.period_from}–{s.period_to}
                    </td>
                    <td>
                      {s.avoids ? (
                        <Badge kind="warn">ครูขอเลี่ยง</Badge>
                      ) : (
                        <Badge kind="ok">ไม่ติดคำขอ</Badge>
                      )}
                    </td>
                    <td style={{ whiteSpace: 'normal' }}>{s.note ?? '—'}</td>
                    <td>
                      <ActionButton
                        onRun={() =>
                          api.post('/timetable/slots', {
                            classSectionId: sectionId,
                            dayOfWeek: s.day_of_week,
                            periodFrom: s.period_from,
                            periodTo: s.period_to,
                            ...(roomId ? { roomId } : {}),
                          })
                        }
                        onDone={() => {
                          setSuggestions(null);
                          conflicts.reload();
                        }}
                      >
                        วาง
                      </ActionButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        )}
      </Card>

      <TransferSectionForm sections={sections.data ?? []} rooms={rooms.data ?? []} staff={staff.data?.items ?? []} />

      <TableCard
        title="คาบที่ชนกันในภาคเรียนนี้"
        actions={<button onClick={() => conflicts.reload()}>ตรวจใหม่</button>}
      >
        <AsyncView state={conflicts} empty="ไม่มีคาบที่ชนกัน">
          {({ conflicts: rows }) =>
            rows.length === 0 ? (
              <div className="empty">ไม่มีคาบที่ชนกัน</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>กลุ่มเรียน</th>
                    <th style={{ width: 120 }}>วัน</th>
                    <th style={{ width: 100 }}>คาบ</th>
                    <th>ชนกับอะไร</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((c, i) => (
                    <tr key={`${c.class_section_id}-${i}`}>
                      <td>{c.label}</td>
                      <td>{DAY[c.day_of_week]}</td>
                      <td>
                        {c.period_from}–{c.period_to}
                      </td>
                      <td style={{ whiteSpace: 'normal' }}>{c.message_th ?? c.kind ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          }
        </AsyncView>
      </TableCard>

      <Card title="เพิ่มห้องเรียน">
        <div className="row">
          <Field label="รหัสห้อง">
            <input value={roomCode} onChange={(e) => setRoomCode(e.target.value)} placeholder="เช่น 301" />
          </Field>
          <Field label="ชื่อห้อง">
            <input value={roomName} onChange={(e) => setRoomName(e.target.value)} placeholder="เช่น ห้อง 301 อาคาร 3" />
          </Field>
          <Field label="ประเภท">
            <select value={roomKind} onChange={(e) => setRoomKind(e.target.value)}>
              {Object.entries(ROOM_KIND).map(([k, label]) => (
                <option key={k} value={k}>{label}</option>
              ))}
            </select>
          </Field>
          <Field label="อาคาร (ถ้ามี)">
            <input value={roomBuilding} onChange={(e) => setRoomBuilding(e.target.value)} placeholder="เช่น อาคาร 3" />
          </Field>
          <Field label="ความจุ (ถ้ามี)">
            <input
              type="number" min={1} max={500}
              value={roomCapacity}
              onChange={(e) => setRoomCapacity(e.target.value)}
              style={{ maxWidth: 100 }}
            />
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() =>
                api.post('/timetable/rooms', {
                  code: roomCode.trim(),
                  nameTh: roomName.trim(),
                  kind: roomKind,
                  ...(roomBuilding.trim() ? { building: roomBuilding.trim() } : {}),
                  ...(roomCapacity ? { capacity: Number(roomCapacity) } : {}),
                })
              }
              onDone={() => {
                setRoomCode('');
                setRoomName('');
                setRoomBuilding('');
                setRoomCapacity('');
                rooms.reload();
              }}
            >
              เพิ่มห้อง
            </ActionButton>
          </div>
        </div>
      </Card>

      <TableCard title="ห้องเรียนของวิทยาลัย">
        <AsyncView state={rooms} empty="ยังไม่ได้บันทึกห้องเรียน">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัสห้อง</th>
                  <th>ชื่อห้อง</th>
                  <th style={{ width: 150 }}>ประเภท</th>
                  <th style={{ width: 130 }}>อาคาร</th>
                  <th className="num" style={{ width: 90 }}>ความจุ</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.id}>
                    <td className="mono">{r.code}</td>
                    <td>{r.name_th}</td>
                    <td>{ROOM_KIND[r.kind] ?? r.kind}</td>
                    <td>{r.building ?? '—'}</td>
                    <td className="num">{r.capacity ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <TableCard title="ภาระงานสอนของอาจารย์ — ภาคเรียนนี้">
        <AsyncView state={sections} empty="ยังไม่มีกลุ่มเรียนในภาคเรียนนี้">
          {(rows) => {
            const byTeacher = new Map<string, { name: string; courses: number; periods: number; students: number }>();
            for (const s of rows) {
              const key = s.teacher_id ?? '';
              const name = s.teacher_name || 'ยังไม่ระบุผู้สอน';
              const entry = byTeacher.get(key) ?? { name, courses: 0, periods: 0, students: 0 };
              entry.courses += 1;
              entry.periods += Number(s.planned_periods) || 0;
              entry.students += Number(s.enrolled) || 0;
              byTeacher.set(key, entry);
            }
            const summary = [...byTeacher.entries()].sort((a, b) => b[1].periods - a[1].periods);
            return (
              <table>
                <thead>
                  <tr>
                    <th>ผู้สอน</th>
                    <th className="num" style={{ width: 100 }}>รายวิชา</th>
                    <th className="num" style={{ width: 140 }}>คาบ/สัปดาห์รวม</th>
                    <th className="num" style={{ width: 120 }}>นักศึกษารวม</th>
                  </tr>
                </thead>
                <tbody>
                  {summary.map(([id, v]) => (
                    <tr key={id || 'none'}>
                      <td>{v.name}</td>
                      <td className="num">{v.courses}</td>
                      <td className="num">{v.periods}</td>
                      <td className="num">{v.students}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            );
          }}
        </AsyncView>
        <div style={{ color: 'var(--ink-soft)', fontSize: 12, marginTop: 6 }}>
          นับจากคาบที่วางแผนไว้ต่อสัปดาห์ของแต่ละกลุ่มเรียน — วิชาที่ยังไม่ได้วางคาบยังนับรวมด้วย
          เพราะเป็นภาระที่รับไว้แล้วแม้จะยังไม่ได้ลงตาราง
        </div>
      </TableCard>
    </>
  );
}

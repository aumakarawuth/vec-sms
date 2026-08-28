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
import { fetchPeriods, fetchSections, usePeriodLabel, type Section } from '../core/catalog';
import { href } from '../core/router';
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

interface Availability {
  id: string;
  day_of_week: number;
  period_from: number;
  period_to: number;
  kind: string;
  reason: string | null;
  term_id: string | null;
  term_ordinal: number | null;
}

const AVAILABILITY_KIND: Record<string, string> = { unavailable: 'ห้ามวาง (ติดจริง)', prefer_not: 'ขอเลี่ยง (ถ้าได้)' };

/**
 * ข้อจำกัดเวลาสอนของครู
 *
 * ตัวจัดตารางอัตโนมัติอ่านตารางนี้อยู่แล้ว (badge "เลี่ยงคำขอครู" ในผลแนะนำ
 * คาบด้านล่าง) แต่ไม่เคยมีที่ให้กรอกเข้ามาเลย — กั้นไว้ที่งานทะเบียน/วิชาการ
 * โดยตั้งใจ ไม่ให้ครูกรอกเอง มิฉะนั้นตารางสอนจะกลายเป็นเรื่องต่อรองกันเอง
 * และคนที่กรอกก่อนได้คาบที่ดีที่สุดเสมอ (ดูคอมเมนต์ที่ API)
 */
function TeacherAvailabilityCard({ staff, termId }: { staff: StaffRow[]; termId: string }) {
  const [staffId, setStaffId] = useState('');
  const periodLabel = usePeriodLabel();
  const avail = useAsync(
    () => (staffId ? api.get<Availability[]>(`/timetable/availability?staffId=${staffId}`) : Promise.resolve([])),
    [staffId],
  );
  const [dayOfWeek, setDayOfWeek] = useState('1');
  const [periodFrom, setPeriodFrom] = useState('1');
  const [periodTo, setPeriodTo] = useState('2');
  const [kind, setKind] = useState('unavailable');
  const [reason, setReason] = useState('');
  const [limitToTerm, setLimitToTerm] = useState(false);

  return (
    <Card title="ข้อจำกัดเวลาสอนของครู">
      <label className="field" style={{ maxWidth: 320 }}>
        <span>ผู้สอน</span>
        <select value={staffId} onChange={(e) => setStaffId(e.target.value)}>
          <option value="">— เลือกผู้สอน —</option>
          {staff.map((s) => (
            <option key={s.id} value={s.id}>{s.full_name} ({s.staff_code})</option>
          ))}
        </select>
      </label>

      {staffId && (
        <>
          <div className="row" style={{ marginTop: 10 }}>
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
            <Field label="ประเภท">
              <select value={kind} onChange={(e) => setKind(e.target.value)} style={{ maxWidth: 150 }}>
                <option value="unavailable">ห้ามวาง (ติดจริง)</option>
                <option value="prefer_not">ขอเลี่ยง (ถ้าได้)</option>
              </select>
            </Field>
            <label className="field" style={{ flex: 2 }}>
              <span>เหตุผล (ถ้ามี)</span>
              <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="เช่น สอนที่วิทยาเขตอื่น" />
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 22, whiteSpace: 'nowrap' }}>
              <input
                type="checkbox" checked={limitToTerm}
                onChange={(e) => setLimitToTerm(e.target.checked)}
                disabled={!termId}
              />
              เฉพาะภาคเรียนที่เลือกอยู่
            </label>
            <div className="shrink">
              <ActionButton
                className="primary"
                onRun={() =>
                  api.post('/timetable/availability', {
                    staffId,
                    dayOfWeek: Number(dayOfWeek),
                    periodFrom: Number(periodFrom),
                    periodTo: Number(periodTo),
                    kind,
                    ...(reason.trim() ? { reason: reason.trim() } : {}),
                    ...(limitToTerm && termId ? { termId } : {}),
                  })
                }
                onDone={() => { setReason(''); avail.reload(); }}
              >
                เพิ่มข้อจำกัด
              </ActionButton>
            </div>
          </div>

          <AsyncView state={avail} empty="ครูคนนี้ยังไม่มีข้อจำกัดเวลาสอน">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 110 }}>วัน</th>
                    <th style={{ width: 100 }}>คาบ</th>
                    <th style={{ width: 130 }}>ประเภท</th>
                    <th>เหตุผล</th>
                    <th style={{ width: 150 }}>ขอบเขต</th>
                    <th style={{ width: 70 }} />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((a) => (
                    <tr key={a.id}>
                      <td>{DAY[a.day_of_week]}</td>
                      <td>{periodLabel(a.period_from, a.period_to)}</td>
                      <td>
                        <Badge kind={a.kind === 'unavailable' ? 'danger' : 'warn'}>
                          {AVAILABILITY_KIND[a.kind] ?? a.kind}
                        </Badge>
                      </td>
                      <td style={{ whiteSpace: 'normal' }}>{a.reason ?? '—'}</td>
                      <td>{a.term_ordinal ? `เฉพาะภาคเรียนที่ ${a.term_ordinal}` : 'ทุกภาคเรียน'}</td>
                      <td>
                        <ActionButton
                          className="ghost"
                          confirm="ลบข้อจำกัดนี้ ยืนยันหรือไม่"
                          onRun={() => api.post(`/timetable/availability/${a.id}/remove`)}
                          onDone={() => avail.reload()}
                        >
                          ลบ
                        </ActionButton>
                      </td>
                    </tr>
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

function TransferRow({ slot, rooms, onDone }: { slot: Timeslot; rooms: Room[]; onDone: () => void }) {
  const [open, setOpen] = useState(false);
  const periodLabel = usePeriodLabel();
  const [dayOfWeek, setDayOfWeek] = useState(String(slot.day_of_week));
  const [periodFrom, setPeriodFrom] = useState(String(slot.period_from));
  const [periodTo, setPeriodTo] = useState(String(slot.period_to));
  const [roomId, setRoomId] = useState(slot.room_id ?? '');

  return (
    <>
      <tr>
        <td>{DAY[slot.day_of_week]}</td>
        <td>{periodLabel(slot.period_from, slot.period_to)}</td>
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

/**
 * วางคาบแบบเห็นภาพ — คลิกช่องว่างเพื่อวางทันที แทนอ่านตารางแนะนำแล้วกดปุ่มแยก
 *
 * ─── ทำไมเปลี่ยนมาเป็นกริดวัน×คาบ ───
 * รูปแบบเดิม (เลือกกลุ่ม → กด "หาคาบว่าง" → อ่านตารางผลลัพธ์เป็นแถว [วัน, คาบ]
 * → กดปุ่ม "วาง" ทีละแถว) บังคับให้แปลตัวเลขวัน/คาบกลับเป็นภาพตารางในหัวเอง
 * ทุกครั้ง ทั้งที่ปฏิทินทั่วไป (Google Calendar/Outlook) และโปรแกรมจัดตาราง
 * สอนของสถานศึกษา (เช่น ASC Timetables, FET) ใช้กริดวัน×คาบเป็นมาตรฐานอยู่
 * แล้ว เพราะคนอ่านตารางสอนเป็นภาพสองมิติอยู่แล้วในชีวิตจริง — ให้คลิกช่อง
 * สีเขียวตรง ๆ ตัดขั้นตอน "อ่านแถว → แปลงเป็นภาพ → หาปุ่ม" ทิ้งไปทั้งหมด
 * คาบว่างคำนวณใหม่อัตโนมัติทันทีที่เปลี่ยนกลุ่มเรียน/จำนวนคาบ/ห้อง ไม่ต้อง
 * กดปุ่ม "หาคาบว่าง" เองอีกต่อไป
 */
function SectionScheduleGrid({
  sections, rooms, termId, onChanged,
}: { sections: Section[]; rooms: Room[]; termId: string; onChanged: () => void }) {
  const periodsCatalog = useAsync(fetchPeriods, []);
  const periodLabel = usePeriodLabel();
  const [sectionId, setSectionId] = useState('');
  const [span, setSpan] = useState('2');
  const [roomId, setRoomId] = useState('');
  const [selected, setSelected] = useState<Timeslot | null>(null);

  const slots = useAsync(
    () => (sectionId ? api.get<Timeslot[]>(`/academic/sections/${sectionId}/timeslots`) : Promise.resolve([])),
    [sectionId],
  );
  const suggestions = useAsync(
    () =>
      sectionId
        ? api.get<Suggestion[]>(
            `/timetable/suggest?classSectionId=${sectionId}&periods=${span}` +
              (roomId ? `&roomId=${roomId}` : '') +
              (termId ? `&termId=${termId}` : ''),
          )
        : Promise.resolve([]),
    [sectionId, span, roomId, termId],
  );

  useEffect(() => setSelected(null), [sectionId]);

  const reload = () => {
    slots.reload();
    suggestions.reload();
    onChanged();
    setSelected(null);
  };

  const maxPeriod = Math.max(10, ...(periodsCatalog.data ?? []).map((p) => p.ordinal));
  const days = [1, 2, 3, 4, 5, 6];

  // ช่อง (วัน-คาบ) ที่มีคาบอยู่แล้ว — เก็บเฉพาะคาบแรกของบล็อกไว้ทำ rowSpan
  const busyStart = new Map<string, Timeslot & { span: number }>();
  const busyCovered = new Set<string>();
  for (const s of slots.data ?? []) {
    busyStart.set(`${s.day_of_week}-${s.period_from}`, { ...s, span: s.period_to - s.period_from + 1 });
    for (let p = s.period_from; p <= s.period_to; p++) busyCovered.add(`${s.day_of_week}-${p}`);
  }

  const suggestStart = new Map<string, Suggestion>();
  const suggestCovered = new Set<string>();
  for (const s of suggestions.data ?? []) {
    suggestStart.set(`${s.day_of_week}-${s.period_from}`, s);
    for (let p = s.period_from; p <= s.period_to; p++) suggestCovered.add(`${s.day_of_week}-${p}`);
  }

  return (
    <Card title="วางคาบให้กลุ่มเรียน — คลิกช่องว่างเพื่อวางทันที">
      <div className="row">
        <label className="field" style={{ flex: 2 }}>
          <span>กลุ่มเรียน</span>
          <select value={sectionId} onChange={(e) => setSectionId(e.target.value)}>
            <option value="">— เลือกกลุ่มเรียน —</option>
            {sections.map((s) => (
              <option key={s.id} value={s.id}>
                {s.code} {s.name_th} · กลุ่ม {s.section_no} · {s.teacher_name || 'ยังไม่มีครู'}
              </option>
            ))}
          </select>
        </label>
        <label className="field" style={{ maxWidth: 140 }}>
          <span>จำนวนคาบติดกัน</span>
          <select value={span} onChange={(e) => setSpan(e.target.value)}>
            {[1, 2, 3, 4].map((n) => (
              <option key={n} value={n}>{n} คาบ</option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>ห้อง (ถ้าระบุ)</span>
          <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
            <option value="">— ไม่ระบุห้อง —</option>
            {rooms.map((r) => (
              <option key={r.id} value={r.id}>{r.code} {r.name_th}</option>
            ))}
          </select>
        </label>
      </div>

      {!sectionId ? (
        <div className="empty">เลือกกลุ่มเรียนก่อน — ช่องสีเขียวจะปรากฏเป็นคาบว่างที่วางได้ทันที</div>
      ) : (
        <>
          <div className="week-grid-legend">
            <span><i className="week-swatch busy" /> มีคาบแล้ว (คลิกเพื่อย้าย/ยกเลิก)</span>
            <span><i className="week-swatch suggest" /> ว่าง วางได้ทันที</span>
            <span><i className="week-swatch avoid" /> ว่างแต่ครูขอเลี่ยง</span>
          </div>
          <div className="week-grid-wrap">
            <table className="week-grid">
              <thead>
                <tr>
                  <th style={{ width: 90 }}>คาบ</th>
                  {days.map((d) => <th key={d}>{DAY[d]}</th>)}
                </tr>
              </thead>
              <tbody>
                {Array.from({ length: maxPeriod }, (_, i) => i + 1).map((p) => (
                  <tr key={p}>
                    <th className="week-grid-period">{periodLabel(p, p)}</th>
                    {days.map((d) => {
                      const key = `${d}-${p}`;
                      if (busyCovered.has(key) && !busyStart.has(key)) return null;
                      const busy = busyStart.get(key);
                      if (busy) {
                        return (
                          <td
                            key={d}
                            rowSpan={busy.span}
                            className={`week-cell busy${selected?.id === busy.id ? ' selected' : ''}`}
                            onClick={() => setSelected(busy)}
                          >
                            {busy.room_code ?? 'ไม่ระบุห้อง'}
                          </td>
                        );
                      }
                      if (suggestCovered.has(key) && !suggestStart.has(key)) return null;
                      const sug = suggestStart.get(key);
                      if (sug) {
                        return (
                          <td key={d} rowSpan={Number(span)} className={`week-cell suggest${sug.avoids ? ' avoid' : ''}`}>
                            <ActionButton
                              className="week-cell-place"
                              onRun={() =>
                                api.post('/timetable/slots', {
                                  classSectionId: sectionId,
                                  dayOfWeek: sug.day_of_week,
                                  periodFrom: sug.period_from,
                                  periodTo: sug.period_to,
                                  ...(roomId ? { roomId } : {}),
                                })
                              }
                              onDone={reload}
                            >
                              {sug.avoids ? '+ ครูขอเลี่ยง' : '+ ว่าง'}
                            </ActionButton>
                          </td>
                        );
                      }
                      return <td key={d} className="week-cell" />;
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {suggestions.data?.length === 0 && (
            <Notice kind="warn">ไม่มีคาบว่างที่วางได้เลย — ลองลดจำนวนคาบติดกัน หรือไม่ระบุห้อง</Notice>
          )}

          {selected && (
            <SelectedSlotPanel slot={selected} rooms={rooms} onDone={reload} onClose={() => setSelected(null)} />
          )}
        </>
      )}
    </Card>
  );
}

/** แผงแก้ไข/ยกเลิกคาบที่คลิกเลือกจากกริด — เปิดขึ้นแทนการค้นแถวในตารางแยก */
function SelectedSlotPanel({
  slot, rooms, onDone, onClose,
}: { slot: Timeslot; rooms: Room[]; onDone: () => void; onClose: () => void }) {
  const periodLabel = usePeriodLabel();
  const [dayOfWeek, setDayOfWeek] = useState(String(slot.day_of_week));
  const [periodFrom, setPeriodFrom] = useState(String(slot.period_from));
  const [periodTo, setPeriodTo] = useState(String(slot.period_to));
  const [roomId, setRoomId] = useState(slot.room_id ?? '');

  return (
    <Card
      title={`คาบที่เลือก — ${DAY[slot.day_of_week]} ${periodLabel(slot.period_from, slot.period_to)}`}
      actions={<button className="ghost" onClick={onClose}>ปิด</button>}
    >
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
            onDone={onDone}
          >
            ย้ายคาบนี้
          </ActionButton>
        </div>
        <div className="shrink">
          <ActionButton
            className="ghost"
            confirm="ยกเลิกคาบนี้ ยืนยันหรือไม่"
            onRun={() => api.post(`/timetable/slots/${slot.id}/remove`)}
            onDone={onDone}
          >
            ยกเลิกคาบนี้
          </ActionButton>
        </div>
      </div>
    </Card>
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
  const periodLabel = usePeriodLabel();
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

  const [autoResult, setAutoResult] = useState<unknown>(null);

  const [roomCode, setRoomCode] = useState('');
  const [roomName, setRoomName] = useState('');
  const [roomKind, setRoomKind] = useState('classroom');
  const [roomCapacity, setRoomCapacity] = useState('');
  const [roomBuilding, setRoomBuilding] = useState('');

  useEffect(() => {
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

      <TeacherAvailabilityCard staff={staff.data?.items ?? []} termId={termId} />

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

      <SectionScheduleGrid
        sections={sections.data ?? []}
        rooms={rooms.data ?? []}
        termId={termId}
        onChanged={() => conflicts.reload()}
      />

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
                        {periodLabel(c.period_from, c.period_to)}
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

      <Card>
        <div className="row" style={{ alignItems: 'center' }}>
          <span>ดูภาระงานสอนของอาจารย์ทุกคนแบบละเอียด (คาบ/สัปดาห์ vs คาบทั้งภาค แยกคอลัมน์)</span>
          <a href={href('/workload')} className="button">ไปหน้าภาระงานสอน →</a>
        </div>
      </Card>
    </>
  );
}

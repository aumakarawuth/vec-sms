/**
 * เช็คชื่อรายคาบ
 *
 * ─── ทำไมต้องมีปุ่มสร้างคาบเรียนอยู่ในหน้านี้ ───
 * คาบเรียนเกิดจาก `generate_class_meetings()` ที่ขยายตารางสอนรายสัปดาห์
 * ไปตลอดภาคเรียนแล้วข้ามวันหยุด ถ้ายังไม่เคยสร้าง หน้านี้จะว่างเปล่า
 * โดยไม่มีอะไรบอกว่าต้องไปทำอะไรก่อน — ซึ่งเป็นความว่างเปล่าแบบที่
 * แยกไม่ออกจาก "ระบบพัง" ถ้าไม่บอกตรง ๆ
 *
 * ─── ทำไมค่าเริ่มต้นของทุกคนคือ "มาเรียน" ───
 * ครูเช็คชื่อโดยหาคนที่ไม่มา ไม่ใช่ไล่กดทีละคนว่ามา การตั้งต้นเป็นขาดเรียน
 * แล้วให้ครูกดทีละคนทั้งห้อง แปลว่าคาบที่ครูลืมกดจะกลายเป็นขาดทั้งห้อง
 */
import { useEffect, useState } from 'react';
import { api } from '../core/api';
import { fetchSections, type Section } from '../core/catalog';
import { pct, thaiDate } from '../core/fmt';
import { AsyncView, Badge, Card, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const STATUS: { value: string; label: string; short: string }[] = [
  { value: 'present', label: 'มาเรียน', short: 'มา' },
  { value: 'late', label: 'มาสาย', short: 'สาย' },
  { value: 'leave_sick', label: 'ลาป่วย', short: 'ป่วย' },
  { value: 'leave_personal', label: 'ลากิจ', short: 'กิจ' },
  { value: 'activity', label: 'ไปกิจกรรม', short: 'กิจกรรม' },
  { value: 'absent', label: 'ขาดเรียน', short: 'ขาด' },
];

interface Meeting {
  id: string;
  meets_on: string;
  period_from: number;
  period_to: number;
  period_count: number;
  status: string;
  note: string | null;
  marked: string | number;
}

interface RosterStudent {
  enrollment_id: string;
  student_code: string;
  full_name: string;
  status: string | null;
  pct_projected: string | null;
  absences_left: number | null;
  attendance_state: string | null;
}

interface Roster {
  meeting: {
    id: string;
    meets_on: string;
    period_from: number;
    period_to: number;
    course_code: string;
    course_name: string;
    section_no: string;
  };
  students: RosterStudent[];
}

export function AttendanceScreen() {
  const { terms, termId, setTerm } = useTermPicker();
  const [sectionId, setSectionId] = useState('');
  const [meetingId, setMeetingId] = useState('');

  const sections = useAsync(
    () => (termId ? fetchSections(termId) : Promise.resolve([])),
    [termId],
  );
  const meetings = useAsync(
    () =>
      sectionId
        ? api.get<Meeting[]>(`/academic/sections/${sectionId}/meetings`)
        : Promise.resolve([]),
    [sectionId],
  );

  // เปลี่ยนกลุ่มเรียนแล้วคาบที่เลือกไว้ไม่เกี่ยวกันอีก
  useEffect(() => setMeetingId(''), [sectionId]);
  useEffect(() => setSectionId(''), [termId]);

  return (
    <>
      <PageHead
        title="เช็คชื่อรายคาบ"
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(list) => <TermSelect terms={list} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <Card>
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
        </div>
      </Card>

      {sectionId && (
        <MeetingList
          sectionId={sectionId}
          meetings={meetings}
          selected={meetingId}
          onSelect={setMeetingId}
        />
      )}

      {meetingId && <RosterPanel meetingId={meetingId} onSaved={() => meetings.reload()} />}
    </>
  );
}

function MeetingList({
  sectionId,
  meetings,
  selected,
  onSelect,
}: {
  sectionId: string;
  meetings: ReturnType<typeof useAsync<Meeting[]>>;
  selected: string;
  onSelect: (id: string) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function generate() {
    setBusy(true);
    setError(null);
    try {
      const r = await api.post<{ created: number }>(`/academic/sections/${sectionId}/meetings`);
      meetings.reload();
      if (r.created === 0) {
        setError('สร้างได้ 0 คาบ — กลุ่มเรียนนี้ยังไม่มีตารางสอน ต้องวางคาบในตารางสอนก่อน');
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'สร้างคาบเรียนไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  const empty = !meetings.loading && (meetings.data?.length ?? 0) === 0;

  return (
    <TableCard
      title="คาบเรียนตลอดภาค"
      actions={
        <button disabled={busy} onClick={() => void generate()}>
          {busy ? 'กำลังสร้าง…' : 'สร้างคาบจากตารางสอน'}
        </button>
      }
    >
      {error && (
        <div style={{ padding: 12 }}>
          <Notice kind="warn">{error}</Notice>
        </div>
      )}
      {empty ? (
        <div className="empty">
          ยังไม่มีคาบเรียน — วางตารางสอนให้กลุ่มนี้ก่อน แล้วกด “สร้างคาบจากตารางสอน”
          <br />
          ระบบจะขยายแบบแผนรายสัปดาห์ไปตลอดภาคเรียนและข้ามวันหยุดให้เอง
        </div>
      ) : (
        <AsyncView state={meetings}>
          {(rows) => (
            <div style={{ maxHeight: 260, overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 34 }} />
                    <th style={{ width: 150 }}>วันที่</th>
                    <th style={{ width: 100 }}>คาบ</th>
                    <th style={{ width: 120 }}>สถานะ</th>
                    <th>เช็คชื่อแล้ว</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((m) => (
                    <tr key={m.id}>
                      <td>
                        <input
                          type="radio"
                          name="meeting"
                          style={{ width: 'auto' }}
                          checked={selected === m.id}
                          onChange={() => onSelect(m.id)}
                        />
                      </td>
                      <td>{thaiDate(m.meets_on)}</td>
                      <td>
                        {m.period_from}–{m.period_to}
                      </td>
                      <td>
                        <Badge kind={m.status === 'held' ? 'ok' : m.status === 'cancelled' ? 'danger' : 'default'}>
                          {m.status === 'held' ? 'สอนแล้ว' : m.status === 'cancelled' ? 'ยกเลิก' : 'ตามแผน'}
                        </Badge>
                      </td>
                      <td>
                        {Number(m.marked) > 0 ? `${m.marked} คน` : <span style={{ color: 'var(--ink-faint)' }}>ยังไม่ได้เช็ค</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </AsyncView>
      )}
    </TableCard>
  );
}

function RosterPanel({ meetingId, onSaved }: { meetingId: string; onSaved: () => void }) {
  const roster = useAsync(() => api.get<Roster>(`/attendance/meetings/${meetingId}/roster`), [meetingId]);
  const [marks, setMarks] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState<string | null>(null);

  // ตั้งต้นจากที่บันทึกไว้แล้ว ถ้ายังไม่เคยเช็คให้เป็น "มาเรียน" ทั้งห้อง
  useEffect(() => {
    if (!roster.data) return;
    const next: Record<string, string> = {};
    for (const s of roster.data.students) next[s.enrollment_id] = s.status ?? 'present';
    setMarks(next);
  }, [roster.data]);

  // ล้างข้อความยืนยันเมื่อเปลี่ยนคาบเท่านั้น ไม่ใช่ตอนโหลดข้อมูลใหม่หลังบันทึก
  // มิฉะนั้นข้อความ "บันทึกแล้ว" จะหายไปทันทีที่ตารางรีเฟรช ซึ่งทำให้ครู
  // ไม่แน่ใจว่ากดติดหรือเปล่าแล้วกดซ้ำ
  useEffect(() => setSaved(null), [meetingId]);

  async function save() {
    if (!roster.data) return;
    setBusy(true);
    setError(null);
    try {
      const records = roster.data.students.map((s) => ({
        enrollmentId: s.enrollment_id,
        status: marks[s.enrollment_id] ?? 'present',
      }));
      await api.post(`/attendance/meetings/${meetingId}`, { records });
      setSaved(`บันทึกแล้ว ${records.length} คน`);
      roster.reload();
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'บันทึกไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  const setAll = (status: string) => {
    if (!roster.data) return;
    const next: Record<string, string> = {};
    for (const s of roster.data.students) next[s.enrollment_id] = status;
    setMarks(next);
  };

  return (
    <AsyncView state={roster}>
      {(r) => (
        <TableCard
          title={`${r.meeting.course_code} ${r.meeting.course_name} · กลุ่ม ${r.meeting.section_no} · ${thaiDate(r.meeting.meets_on)} คาบ ${r.meeting.period_from}–${r.meeting.period_to}`}
          actions={
            <>
              <button className="link" onClick={() => setAll('present')}>
                มาทั้งห้อง
              </button>
              <button className="primary" disabled={busy} onClick={() => void save()}>
                {busy ? 'กำลังบันทึก…' : 'บันทึกการเช็คชื่อ'}
              </button>
            </>
          }
        >
          {error && (
            <div style={{ padding: 12 }}>
              <Notice kind="error">{error}</Notice>
            </div>
          )}
          {saved && (
            <div style={{ padding: 12 }}>
              <Notice kind="ok">{saved}</Notice>
            </div>
          )}

          <table>
            <thead>
              <tr>
                <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                <th style={{ width: 180 }}>ชื่อ — นามสกุล</th>
                {STATUS.map((s) => (
                  <th key={s.value} style={{ width: 62, textAlign: 'center' }}>
                    {s.short}
                  </th>
                ))}
                <th className="num" style={{ width: 90 }}>เวลาเรียน</th>
                <th className="num" style={{ width: 90 }}>ขาดได้อีก</th>
              </tr>
            </thead>
            <tbody>
              {r.students.map((s) => (
                <tr key={s.enrollment_id}>
                  <td className="mono">{s.student_code}</td>
                  <td>{s.full_name}</td>
                  {STATUS.map((st) => (
                    <td key={st.value} style={{ textAlign: 'center' }}>
                      <input
                        type="radio"
                        style={{ width: 'auto' }}
                        name={`att-${s.enrollment_id}`}
                        checked={(marks[s.enrollment_id] ?? 'present') === st.value}
                        onChange={() =>
                          setMarks((m) => ({ ...m, [s.enrollment_id]: st.value }))
                        }
                        title={st.label}
                      />
                    </td>
                  ))}
                  <td className="num">{pct(s.pct_projected)}</td>
                  <td className="num">
                    {s.absences_left === null ? '—' : (
                      <Badge kind={s.absences_left <= 0 ? 'danger' : s.absences_left <= 2 ? 'warn' : 'default'}>
                        {s.absences_left}
                      </Badge>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </TableCard>
      )}
    </AsyncView>
  );
}

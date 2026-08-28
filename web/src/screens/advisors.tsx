/**
 * มอบหมายอาจารย์ที่ปรึกษาแบบกลุ่ม — เริ่มจากห้อง ไม่ใช่รายชื่อคน
 *
 * ─── ทำไมต้องมีหน้านี้ ───
 * ก่อนหน้านี้การ์ด "กำหนดอาจารย์ที่ปรึกษา" ในศูนย์งานตารางเรียนเขียนว่า
 * "แต่งตั้งอาจารย์ที่ปรึกษารายคนหรือแบบกลุ่ม" แต่ชี้ไปที่ /students ซึ่งมี
 * แค่ทางรายคน (ต้องเปิดระเบียนทีละคนแล้วมอบหมายทีละคน) — ทาง API มี
 * `POST /advisors/bulk` (`assignAdvisorBulk`) มาตั้งแต่ต้น แต่ไม่เคยมีหน้าจอ
 * ไหนเรียกมันเลย เป็นรูปแบบเดียวกับ `take_usage_snapshot()` และ
 * `generate_class_meetings()` ที่ CLAUDE.md บันทึกไว้ — ของที่ประกาศเจตนา
 * ไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น
 *
 * ─── ทำไมเลือกห้องก่อน ไม่ใช่ค้นหาทีละคน ───
 * ที่ปรึกษามอบหมายเป็นห้องเกือบทั้งหมด (ครูประจำชั้นดูแลทั้งห้อง) เหมือนกับ
 * เหตุผลที่หน้าลงทะเบียนเรียนเปลี่ยนมาเริ่มจากห้องใน API-180 — วิทยาลัยพันคน
 * มีห้องราวสามสิบห้อง อ่านครบได้ในหน้าจอเดียว ส่วนทางรายคนที่ /students
 * ยังอยู่เหมือนเดิมสำหรับคนที่ยังไม่มีห้องหรือต้องแก้เฉพาะราย
 */
import { useEffect, useState } from 'react';
import { api, qs } from '../core/api';
import { href, navigate, useRoute } from '../core/router';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync,
} from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

interface Room {
  academic_year_id: string;
  study_year: number;
  group_code: string | null;
  students_total: number;
  students_registered: number;
  students_pending: number;
  pct: string | null;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
  status: string;
}

interface StaffOption {
  id: string;
  full_name: string;
}

interface BulkResult {
  total: number;
  ok: number;
  results: { studentId: string; ok: boolean; message?: string }[];
}

const roomLabel = (r: { study_year: number; group_code: string | null }) =>
  r.group_code ? `ปี ${r.study_year} ห้อง ${r.group_code}` : `ปี ${r.study_year} — ยังไม่จัดห้อง`;

export function AdvisorsScreen() {
  const route = useRoute();
  const { terms, termId, setTerm } = useTermPicker();

  const studyYear = route.query.get('studyYear');
  const groupCode = route.query.get('groupCode');
  const roomKey = studyYear ? `${studyYear}/${groupCode ?? ''}` : '';

  const setQuery = (patch: Record<string, string | null>) => {
    const q = new URLSearchParams(route.query);
    for (const [k, v] of Object.entries(patch)) {
      if (v === null || v === '') q.delete(k);
      else q.set(k, v);
    }
    navigate(`${route.path}?${q.toString()}`);
  };

  const rooms = useAsync(
    () => (termId ? api.get<Room[]>(`/registration/rooms${qs({ termId })}`) : Promise.resolve([])),
    [termId],
  );
  const room = rooms.data?.find((r) => `${r.study_year}/${r.group_code ?? ''}` === roomKey);

  const students = useAsync(
    () =>
      room
        ? api.get<StudentRow[]>(
            `/students${qs({
              academicYearId: room.academic_year_id,
              studyYear: String(room.study_year),
              groupCode: room.group_code ?? undefined,
              status: 'active',
            })}`,
          )
        : Promise.resolve([]),
    [room?.academic_year_id, room?.study_year, room?.group_code],
  );

  const [staff, setStaff] = useState<StaffOption[]>([]);
  useEffect(() => {
    api.getPage<StaffOption>('/staff?limit=300').then((p) => setStaff(p.items)).catch(() => setStaff([]));
  }, []);

  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [staffId, setStaffId] = useState('');
  const [isPrimary, setIsPrimary] = useState(true);
  const [note, setNote] = useState('');
  const [result, setResult] = useState<BulkResult | null>(null);

  // เปลี่ยนห้องแล้วเลือกทุกคนในห้องให้ใหม่ ล้างผลเดิมทิ้ง
  useEffect(() => {
    setSelected(new Set((students.data ?? []).map((s) => s.id)));
    setResult(null);
  }, [students.data]);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };

  return (
    <>
      <PageHead
        title="กำหนดอาจารย์ที่ปรึกษา"
        sub="มอบหมายทั้งห้องพร้อมกัน — ต่างจาก /students ที่มอบหมายได้ทีละคน"
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <Card title="เลือกห้อง">
        <AsyncView state={rooms} empty="ภาคเรียนนี้ยังไม่มีห้อง">
          {(list) => (
            <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
              {list.map((r) => {
                const key = `${r.study_year}/${r.group_code ?? ''}`;
                return (
                  <button
                    key={key}
                    className={key === roomKey ? 'primary' : 'ghost'}
                    onClick={() => setQuery({ studyYear: String(r.study_year), groupCode: r.group_code })}
                  >
                    {roomLabel(r)} · {r.students_total} คน
                  </button>
                );
              })}
            </div>
          )}
        </AsyncView>
      </Card>

      {!room ? (
        <div className="empty">เลือกห้องก่อน — รายชื่อนักศึกษาในห้องจะปรากฏพร้อมติ๊กเลือกให้ทุกคนโดยอัตโนมัติ</div>
      ) : (
        <>
          <TableCard
            title={`รายชื่อในห้อง — ${roomLabel(room)}`}
            actions={<span className="sub">{selected.size} / {students.data?.length ?? 0} คน</span>}
          >
            <AsyncView state={students} empty="ห้องนี้ยังไม่มีนักศึกษาที่กำลังศึกษา">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 40 }}>
                        <input
                          type="checkbox"
                          checked={selected.size === rows.length && rows.length > 0}
                          onChange={(e) => setSelected(e.target.checked ? new Set(rows.map((s) => s.id)) : new Set())}
                        />
                      </th>
                      <th style={{ width: 140 }}>รหัสนักศึกษา</th>
                      <th>ชื่อ-สกุล</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((s) => (
                      <tr key={s.id}>
                        <td><input type="checkbox" checked={selected.has(s.id)} onChange={() => toggle(s.id)} /></td>
                        <td className="mono">{s.student_code}</td>
                        <td>
                          <a href={href(`/students/${s.id}?tab=advisor`)}>{s.full_name}</a>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

          <Card title="มอบหมายที่ปรึกษาให้คนที่เลือก">
            <div className="row">
              <Field label="อาจารย์">
                <select value={staffId} onChange={(e) => setStaffId(e.target.value)}>
                  <option value="">— เลือกอาจารย์ —</option>
                  {staff.map((t) => (
                    <option key={t.id} value={t.id}>{t.full_name}</option>
                  ))}
                </select>
              </Field>
              <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 22 }}>
                <input type="checkbox" checked={isPrimary} onChange={(e) => setIsPrimary(e.target.checked)} />
                มอบหมายเป็นที่ปรึกษาหลัก
              </label>
              <label className="field" style={{ flex: 2 }}>
                <span>หมายเหตุ (ถ้ามี)</span>
                <input value={note} onChange={(e) => setNote(e.target.value)} />
              </label>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  confirm={`มอบหมายที่ปรึกษาให้ ${selected.size} คน ยืนยันหรือไม่ — คนที่มีที่ปรึกษาหลักอยู่แล้วในปีนี้จะถูกปิดของเดิมให้`}
                  onRun={() => {
                    if (!staffId) throw new Error('เลือกอาจารย์ก่อน');
                    if (selected.size === 0) throw new Error('เลือกนักศึกษาอย่างน้อยหนึ่งคน');
                    return api.post<BulkResult>('/advisors/bulk', {
                      studentIds: [...selected],
                      staffId,
                      academicYearId: room.academic_year_id,
                      isPrimary,
                      ...(note.trim() ? { note: note.trim() } : {}),
                    });
                  }}
                  onDone={(r) => setResult(r as BulkResult)}
                >
                  มอบหมายที่ปรึกษา
                </ActionButton>
              </div>
            </div>
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              มอบหมายได้ครั้งละไม่เกิน 200 คน — ห้องหนึ่งไม่เกินนี้อยู่แล้วตามปกติ
            </div>
          </Card>

          {result && (
            <TableCard title="ผลการมอบหมาย">
              {result.ok < result.total && (
                <Notice kind="warn">มอบหมายสำเร็จ {result.ok} จาก {result.total} คน — ที่เหลือติดเงื่อนไข ดูรายละเอียดในตาราง</Notice>
              )}
              <table>
                <thead>
                  <tr>
                    <th>รหัสนักศึกษา</th>
                    <th>ชื่อ-สกุล</th>
                    <th style={{ width: 100 }}>ผล</th>
                    <th>รายละเอียด</th>
                  </tr>
                </thead>
                <tbody>
                  {result.results.map((r) => {
                    const s = students.data?.find((x) => x.id === r.studentId);
                    return (
                      <tr key={r.studentId}>
                        <td className="mono">{s?.student_code ?? r.studentId}</td>
                        <td>{s?.full_name ?? '—'}</td>
                        <td>{r.ok ? <Badge kind="ok">สำเร็จ</Badge> : <Badge kind="danger">ล้มเหลว</Badge>}</td>
                        <td style={{ whiteSpace: 'normal' }}>{r.message ?? '—'}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </TableCard>
          )}
        </>
      )}
    </>
  );
}

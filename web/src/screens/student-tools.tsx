/**
 * เครื่องมืองานทะเบียนรายห้อง/ทั้งวิทยาลัย — แยกหน้าละงานแบบ SISA
 * (หมวดนักศึกษา: รายงานรับเข้า/ออก · ใบรายชื่อ/ฉลากที่อยู่ · เปลี่ยนคำนำหน้า
 * อายุ 15 ปี · ผลงานและเกียรติประวัติ) ใบรายชื่อกับฉลากเป็นเอกสารทำงาน
 * พิมพ์สดทุกครั้ง ไม่มีเลขที่ (หลักข้อ 4ก)
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDate } from '../core/fmt';
import { useScope } from '../core/scope';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, PrintButton, TableCard, useAsync,
} from '../ui/kit';

export const STUDENT_TOOL_SECTIONS = {
  'status-changes': { title: 'รายงานการรับเข้า/ออก', sub: 'การรับเข้า ลาพัก ออก กลับเข้าเรียน และสำเร็จการศึกษา ตามช่วงวันที่' },
  rosters: { title: 'ใบรายชื่อและฉลากที่อยู่', sub: 'พิมพ์ใบรายชื่อห้องประจำ และฉลากที่อยู่สำหรับซองจดหมายถึงผู้ปกครอง' },
  prefix: { title: 'เปลี่ยนคำนำหน้าชื่อ (อายุ 15 ปี)', sub: 'เด็กชาย/เด็กหญิง ที่อายุครบ 15 ปีแล้ว เปลี่ยนเป็น นาย/นางสาว พร้อมกัน' },
  achievements: { title: 'ผลงานและเกียรติประวัติ', sub: 'รางวัลและผลงานของนักศึกษาทั้งวิทยาลัย' },
} as const;
export type StudentToolSection = keyof typeof STUDENT_TOOL_SECTIONS;

const STATUS_TH: Record<string, string> = {
  active: 'กำลังศึกษา', on_leave: 'ลาพัก', suspended: 'พักการเรียน', withdrawn: 'ลาออก',
  transferred_out: 'ย้ายสถานศึกษา', dismissed: 'พ้นสภาพ', graduated: 'สำเร็จการศึกษา',
};

export function StudentToolsScreen({ section }: { section: StudentToolSection }) {
  const meta = STUDENT_TOOL_SECTIONS[section];
  return (
    <>
      <PageHead title={meta.title} sub={meta.sub} />
      {section === 'status-changes' && <StatusChanges />}
      {section === 'rosters' && <Rosters />}
      {section === 'prefix' && <Prefix />}
      {section === 'achievements' && <Achievements />}
    </>
  );
}

interface ChangeRow {
  id: string; effective_on: string; from_status: string | null; to_status: string;
  reason: string | null; document_no: string | null; student_code: string; full_name: string; student_id: string;
}

function StatusChanges() {
  const [kind, setKind] = useState('all');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const rows = useAsync(
    () => api.get<ChangeRow[]>(`/student-tools/status-changes${qs({ kind, from: from || undefined, to: to || undefined })}`),
    [kind, from, to],
  );
  return (
    <>
      <Card title="เงื่อนไข">
        <div className="row">
          <Field label="ชนิด">
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="all">ทั้งหมด</option>
              <option value="admit">รับเข้า</option>
              <option value="leave">ลาพัก</option>
              <option value="out">ออก (ลาออก · ย้าย · พ้นสภาพ)</option>
              <option value="back">กลับเข้าเรียน</option>
              <option value="graduate">สำเร็จการศึกษา</option>
            </select>
          </Field>
          <Field label="ตั้งแต่วันที่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label="ถึงวันที่"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      </Card>
      <TableCard title="รายการ (สูงสุด 1,000 รายการ)">
        <AsyncView state={rows} empty="ไม่มีรายการตามเงื่อนไข">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 110 }}>วันที่มีผล</th>
                  <th style={{ width: 120 }}>รหัส</th>
                  <th>ชื่อ</th>
                  <th style={{ width: 220 }}>เปลี่ยนสถานะ</th>
                  <th>เหตุผล / เลขที่คำสั่ง</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.id}>
                    <td>{thaiDate(r.effective_on)}</td>
                    <td className="mono">{r.student_code}</td>
                    <td><a href={`#/students/${r.student_id}`}>{r.full_name}</a></td>
                    <td>{r.from_status ? `${STATUS_TH[r.from_status] ?? r.from_status} → ` : 'รับเข้า → '}{STATUS_TH[r.to_status] ?? r.to_status}</td>
                    <td>{[r.reason, r.document_no].filter(Boolean).join(' · ') || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}

interface Room { study_year: number; group_code: string | null; students_total: number }

function Rosters() {
  const scope = useScope();
  const [blank, setBlank] = useState('10');
  const rooms = useAsync(
    () => (scope.termId ? api.get<Room[]>(`/registration/rooms${qs({ termId: scope.termId })}`) : Promise.resolve([])),
    [scope.termId],
  );
  const q = (r: Room) => qs({ academicYearId: scope.yearId, groupCode: r.group_code ?? undefined });
  return (
    <>
      <Card title="ตัวเลือกการพิมพ์">
        <Field label="ช่องว่างท้ายใบรายชื่อ (ให้ครูขีด)">
          <select value={blank} onChange={(e) => setBlank(e.target.value)}>
            {[0, 5, 10, 15, 20].map((n) => <option key={n} value={n}>{n} ช่อง</option>)}
          </select>
        </Field>
      </Card>
      <TableCard title="ห้องประจำของปีการศึกษาที่เลือกด้านบน">
        <AsyncView state={rooms} empty="ยังไม่มีห้อง — จัดนักศึกษาเข้าห้องที่ “จัดห้องเรียน” ก่อน">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th>ห้อง</th>
                  <th className="num" style={{ width: 100 }}>นักศึกษา</th>
                  <th style={{ width: 260 }} />
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={`${r.study_year}|${r.group_code}`}>
                    <td>{r.group_code ? `ชั้นปี ${r.study_year} · ห้อง ${r.group_code}` : <Badge kind="warn">ยังไม่จัดห้อง</Badge>}</td>
                    <td className="num">{r.students_total}</td>
                    <td>
                      <div className="row" style={{ gap: 6 }}>
                        <PrintButton path={`/student-tools/rooms/roster/print${q(r)}&blankCols=${blank}`}>ใบรายชื่อ</PrintButton>
                        <PrintButton path={`/student-tools/rooms/labels/print${q(r)}`}>ฉลากที่อยู่</PrintButton>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}

interface Candidate { person_id: string; student_code: string; full_name: string; prefix_th: string; new_prefix: string; birth_date: string }

function Prefix() {
  const rows = useAsync(() => api.get<Candidate[]>('/student-tools/prefix-candidates'), []);
  const [done, setDone] = useState<{ updated: number; skipped: number } | null>(null);
  return (
    <>
      {done && (
        <Notice kind="ok">
          เปลี่ยนแล้ว {done.updated} คน{done.skipped ? ` · ข้าม ${done.skipped} คนที่ไม่เข้าเงื่อนไขแล้ว` : ''}
        </Notice>
      )}
      <TableCard
        title="ผู้ที่อายุครบ 15 ปีแล้วแต่ยังใช้ เด็กชาย/เด็กหญิง"
        actions={
          rows.data && rows.data.length > 0 ? (
            <ActionButton
              className="primary"
              confirm={`เปลี่ยนคำนำหน้าทั้ง ${rows.data.length} คน — ยืนยันหรือไม่`}
              onRun={() => api.post<{ updated: number; skipped: number }>('/student-tools/prefix-apply', { personIds: rows.data!.map((r) => r.person_id) })}
              onDone={(r) => { setDone(r as { updated: number; skipped: number }); rows.reload(); }}
            >
              เปลี่ยนทั้งหมด
            </ActionButton>
          ) : undefined
        }
      >
        <AsyncView state={rows} empty="ไม่มีใครต้องเปลี่ยน (คนที่ไม่มีวันเกิดในระบบจะไม่ถูกเสนอ)">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัส</th>
                  <th>ชื่อปัจจุบัน</th>
                  <th style={{ width: 120 }}>วันเกิด</th>
                  <th style={{ width: 140 }}>คำนำหน้าใหม่</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.person_id}>
                    <td className="mono">{r.student_code}</td>
                    <td>{r.full_name}</td>
                    <td>{thaiDate(r.birth_date)}</td>
                    <td>{r.prefix_th} → <strong>{r.new_prefix}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}

interface Achievement {
  id: string; title_th: string; category_th: string | null; level_th: string | null; issuer_th: string | null;
  awarded_on: string; student_id: string; student_code: string; full_name: string;
}

function Achievements() {
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const rows = useAsync(
    () => api.get<Achievement[]>(`/student-tools/achievements${qs({ from: from || undefined, to: to || undefined })}`),
    [from, to],
  );
  return (
    <TableCard
      title="ผลงานและเกียรติประวัติ"
      actions={
        <div className="row" style={{ gap: 8 }}>
          <Field label="ตั้งแต่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label="ถึง"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      }
    >
      <AsyncView state={rows} empty="ยังไม่มีผลงานที่บันทึกไว้ — เพิ่มได้ที่แท็บผลงานของแฟ้มนักศึกษา">
        {(list) => (
          <table>
            <thead>
              <tr>
                <th style={{ width: 110 }}>วันที่</th>
                <th>ผลงาน</th>
                <th style={{ width: 120 }}>ประเภท</th>
                <th style={{ width: 140 }}>ระดับ</th>
                <th>นักศึกษา</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td>{thaiDate(r.awarded_on)}</td>
                  <td>{r.title_th}{r.issuer_th ? <small className="muted"> · {r.issuer_th}</small> : null}</td>
                  <td>{r.category_th ?? '—'}</td>
                  <td>{r.level_th ?? '—'}</td>
                  <td><a href={`#/students/${r.student_id}`}>{r.student_code} {r.full_name}</a></td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

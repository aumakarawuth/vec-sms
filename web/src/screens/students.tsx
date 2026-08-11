/**
 * ระเบียนนักศึกษา — หน้าจอที่งานทะเบียนเปิดบ่อยที่สุด
 *
 * ─── ทำไมค้นหาแล้วยิงทันทีไม่ได้ ───
 * ช่องค้นหายิง API ทุกครั้งที่พิมพ์จะได้คำขอหนึ่งครั้งต่อหนึ่งตัวอักษร
 * ซึ่งเป็นการยิงรัวใส่เส้นทางที่แตะฐานข้อมูล และ `request_rate_hit()`
 * นับรวมทุก instance อยู่แล้ว เจ้าหน้าที่คนเดียวจะกินโควตาของทั้งวิทยาลัย
 * จึงหน่วงไว้ 300 มิลลิวินาทีหลังหยุดพิมพ์
 */
import { useEffect, useState } from 'react';
import { api, qs } from '../core/api';
import { LEVEL, STUDENT_STATUS, thaiDate, money, pct } from '../core/fmt';
import { href, navigate, useRoute } from '../core/router';
import { AsyncView, Badge, Card, Field, PageHead, TableCard, Tabs, useAsync } from '../ui/kit';
import {
  AddressTab,
  AdvisorTab,
  GeneralTab,
  ParentTab,
  PriorEducationTab,
  SensitiveTab,
  type FullProfile,
} from './student-record';

interface StudentRow {
  id: string;
  student_code: string;
  status: string;
  full_name: string;
  program_name: string | null;
  level: string | null;
}

function statusKind(status: string): 'ok' | 'warn' | 'danger' | 'info' | 'default' {
  if (status === 'active') return 'ok';
  if (status === 'graduated') return 'info';
  if (status === 'on_leave') return 'warn';
  if (status === 'suspended' || status === 'dismissed') return 'danger';
  return 'default';
}

export function StudentsScreen() {
  const [typed, setTyped] = useState('');
  const [q, setQ] = useState('');

  // หน่วงหลังหยุดพิมพ์ ไม่ใช่ยิงทุกตัวอักษร
  useEffect(() => {
    const t = setTimeout(() => setQ(typed.trim()), 300);
    return () => clearTimeout(t);
  }, [typed]);

  const list = useAsync(
    () => api.get<StudentRow[]>(`/students${qs({ q, limit: 200 })}`),
    [q],
  );

  return (
    <>
      <PageHead
        title="ระเบียนนักศึกษา"
        sub={list.data ? `${list.data.length} รายการ` : undefined}
      />

      <Card>
        <div className="row">
          <Field label="ค้นหาด้วยรหัสนักศึกษา ชื่อ หรือนามสกุล">
            <input
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              placeholder="เช่น 69201010001 หรือ กิตติ"
              autoFocus
            />
          </Field>
          <div className="shrink">
            <button onClick={() => list.reload()}>โหลดใหม่</button>
          </div>
        </div>
      </Card>

      <TableCard>
        <AsyncView state={list} empty="ไม่พบนักศึกษาที่ตรงกับคำค้น">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                  <th>ชื่อ — นามสกุล</th>
                  <th style={{ width: 70 }}>ระดับ</th>
                  <th>สาขาวิชา</th>
                  <th style={{ width: 120 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} style={{ cursor: 'pointer' }} onClick={() => navigate(`/students/${r.id}`)}>
                    <td className="mono">
                      <a href={href(`/students/${r.id}`)}>{r.student_code}</a>
                    </td>
                    <td>{r.full_name}</td>
                    <td>{r.level ? LEVEL[r.level] ?? r.level : '—'}</td>
                    <td>{r.program_name ?? '—'}</td>
                    <td>
                      <Badge kind={statusKind(r.status)}>
                        {STUDENT_STATUS[r.status] ?? r.status}
                      </Badge>
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

/* ─── หน้ารายบุคคล ──────────────────────────────────────────────── */

interface StudentDetail {
  id: string;
  student_code: string;
  status: string;
  admitted_year_be: number;
  first_name_th: string;
  last_name_th: string;
  birth_date: string | null;
  curriculum_edition: number | null;
  curriculum_name: string | null;
  level: string | null;
}

interface Balance {
  billed: number | string;
  paid: number | string;
  outstanding: number | string;
  next_due_on: string | null;
  days_overdue: number | null;
}

interface AttendanceRow {
  code: string;
  name_th: string;
  pct_to_date: string | number;
  pct_projected: string | number;
  absences_left: number;
  attendance_state: string;
  min_pct: string | number;
}

const ATT_STATE: Record<string, { label: string; kind: 'ok' | 'warn' | 'danger' }> = {
  ok: { label: 'ปกติ', kind: 'ok' },
  warning: { label: 'ใกล้ตกเกณฑ์', kind: 'warn' },
  at_risk: { label: 'เสี่ยงหมดสิทธิ์', kind: 'danger' },
  failed: { label: 'หมดสิทธิ์', kind: 'danger' },
};

const TABS = [
  { key: 'general', label: 'ข้อมูลทั่วไป' },
  { key: 'address', label: 'ที่อยู่' },
  { key: 'parent', label: 'บิดามารดา' },
  { key: 'sensitive', label: 'สุขภาพและข้อมูลอ่อนไหว' },
  { key: 'prior', label: 'การศึกษาเดิม' },
  { key: 'advisor', label: 'ที่ปรึกษาและผู้ปกครอง' },
  { key: 'study', label: 'การเรียนและการเงิน' },
];

export function StudentDetailScreen({ id }: { id: string }) {
  const route = useRoute();
  const termId = route.query.get('termId') ?? '';
  const tab = route.query.get('tab') ?? 'general';

  const detail = useAsync(() => api.get<StudentDetail>(`/students/${id}`), [id]);
  const profile = useAsync(() => api.get<FullProfile>(`/students/${id}/profile`), [id]);
  const balance = useAsync(
    () => (tab === 'study' ? api.get<Balance>(`/students/${id}/balance`) : Promise.resolve(null)),
    [id, tab],
  );
  const attendance = useAsync(
    () =>
      tab === 'study' && termId
        ? api.get<AttendanceRow[]>(`/students/${id}/attendance${qs({ termId })}`)
        : Promise.resolve([]),
    [id, termId, tab],
  );

  function setTab(key: string) {
    const q = new URLSearchParams(route.query);
    q.set('tab', key);
    navigate(`/students/${id}?${q.toString()}`);
  }

  return (
    <>
      <PageHead
        title="ระเบียนนักศึกษา"
        sub={<a href={href('/students')}>← กลับรายชื่อ</a>}
      />

      <AsyncView state={detail}>
        {(s) => (
          <>
            <Card title={`${s.first_name_th} ${s.last_name_th}`}>
              <div className="row">
                <Field label="รหัสนักศึกษา">
                  <input value={s.student_code} readOnly />
                </Field>
                <Field label="ระดับ">
                  <input value={s.level ? LEVEL[s.level] ?? s.level : '—'} readOnly />
                </Field>
                <Field label="ปีที่เข้าศึกษา">
                  <input value={`${s.admitted_year_be}`} readOnly />
                </Field>
                <Field label="วันเกิด">
                  <input value={thaiDate(s.birth_date)} readOnly />
                </Field>
                <Field label="สถานะ">
                  <input value={STUDENT_STATUS[s.status] ?? s.status} readOnly />
                </Field>
              </div>
              <div className="row">
                <Field label="หลักสูตร">
                  <input
                    value={
                      s.curriculum_name
                        ? `${s.curriculum_name}${s.curriculum_edition ? ` (ฉบับ ${s.curriculum_edition})` : ''}`
                        : 'ยังไม่ได้กำหนดหลักสูตร'
                    }
                    readOnly
                  />
                </Field>
              </div>
            </Card>

            <Tabs
              tabs={TABS.map((t) =>
                t.key === 'sensitive' && profile.data && !profile.data.canSeeSensitive
                  ? { ...t, badge: 'ไม่มีสิทธิ์' }
                  : t.key === 'parent'
                    ? { ...t, badge: profile.data?.parents.length || undefined }
                    : t.key === 'prior'
                      ? { ...t, badge: profile.data?.priorEducation.length || undefined }
                      : t,
              )}
              active={tab}
              onChange={setTab}
            />

            {tab !== 'study' && (
              <AsyncView state={profile}>
                {(pf) => (
                  <>
                    {tab === 'general' && <GeneralTab p={pf} reload={profile.reload} />}
                    {tab === 'address' && <AddressTab p={pf} reload={profile.reload} />}
                    {tab === 'parent' && <ParentTab p={pf} reload={profile.reload} />}
                    {tab === 'sensitive' && <SensitiveTab p={pf} reload={profile.reload} />}
                    {tab === 'prior' && <PriorEducationTab p={pf} reload={profile.reload} />}
                    {tab === 'advisor' && <AdvisorTab p={pf} reload={profile.reload} />}
                  </>
                )}
              </AsyncView>
            )}

            {tab === 'study' && (
              <>
            <Card title="ยอดค้างชำระ">
              <AsyncView state={balance} empty="ยังไม่มีใบแจ้งหนี้">
                {(b) => b == null ? null : (
                  <div className="row">
                    <Field label="ยอดเรียกเก็บ">
                      <input value={money(b.billed)} readOnly />
                    </Field>
                    <Field label="ชำระแล้ว">
                      <input value={money(b.paid)} readOnly />
                    </Field>
                    <Field label="คงค้าง">
                      <input value={money(b.outstanding)} readOnly />
                    </Field>
                    <Field label="กำหนดชำระถัดไป">
                      <input value={thaiDate(b.next_due_on)} readOnly />
                    </Field>
                    <Field label="เกินกำหนด">
                      <input value={b.days_overdue ? `${b.days_overdue} วัน` : '—'} readOnly />
                    </Field>
                  </div>
                )}
              </AsyncView>
            </Card>

            <TableCard title="เวลาเรียนรายวิชา">
              {!termId ? (
                <div className="empty">เลือกภาคเรียนจากหน้าลงทะเบียนเพื่อดูเวลาเรียน</div>
              ) : (
                <AsyncView state={attendance} empty="ยังไม่ได้ลงทะเบียนในภาคเรียนนี้">
                  {(rows) => (
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 120 }}>รหัสวิชา</th>
                          <th>ชื่อวิชา</th>
                          <th className="num" style={{ width: 100 }}>ถึงปัจจุบัน</th>
                          <th className="num" style={{ width: 100 }}>คาดการณ์</th>
                          <th className="num" style={{ width: 100 }}>ขาดได้อีก</th>
                          <th style={{ width: 130 }}>สถานะ</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((r) => {
                          const st = ATT_STATE[r.attendance_state];
                          return (
                            <tr key={r.code}>
                              <td className="mono">{r.code}</td>
                              <td>{r.name_th}</td>
                              <td className="num">{pct(r.pct_to_date)}</td>
                              <td className="num">{pct(r.pct_projected)}</td>
                              <td className="num">{r.absences_left}</td>
                              <td>
                                <Badge kind={st?.kind ?? 'default'}>
                                  {st?.label ?? r.attendance_state}
                                </Badge>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  )}
                </AsyncView>
              )}
            </TableCard>
              </>
            )}
          </>
        )}
      </AsyncView>
    </>
  );
}

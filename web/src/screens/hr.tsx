/**
 * งานบุคลากร — หน่วยงาน ระเบียน ทช.1 และการลา
 *
 * ─── ทำไมการอนุมัติใบลาต้องเลือกผู้อนุมัติ ───
 * ฐานข้อมูลกันไม่ให้คนอนุมัติใบลาของตัวเอง (trigger จาก 0049) การส่ง
 * `decidedBy` มาจากหน้าจอจึงไม่ใช่ช่องโหว่ — ถ้าใส่ตัวเองจะถูกปฏิเสธที่
 * ฐานข้อมูลอยู่ดี และการให้เลือกทำให้บันทึกตรงกับคนที่ลงนามจริง
 *
 * ─── ทำไม ทช.1 สำคัญ ───
 * ระเบียนประวัติบุคลากรใช้ยันคุณวุฒิและชั่วโมงอบรมตอนถูกตรวจ ครูแก้ของ
 * ตัวเองไม่ได้ (0049) งานบุคคลเป็นคนบันทึกให้เท่านั้น
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num, thaiDate } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface Department {
  id: string;
  parent_id: string | null;
  code: string;
  name_th: string;
  kind: string;
  depth: number;
  path_th: string;
}

interface StaffRow {
  id: string;
  person_id: string;
  staff_code: string;
  full_name: string;
  is_teacher: boolean;
  active: boolean;
  roles: string[] | null;
  effective_role: string | null;
}

interface Leave {
  id: string;
  kind: string;
  from_date: string;
  to_date: string;
  days: string;
  reason: string;
  status: string;
  full_name: string;
}

interface StaffRecord {
  id: string;
  kind: string;
  title_th: string;
  organization_th: string | null;
  started_on: string | null;
  ended_on: string | null;
  hours: string | null;
}

const LEAVE_KIND: Record<string, string> = {
  personal: 'ลากิจ',
  sick: 'ลาป่วย',
  maternity: 'ลาคลอด',
  ordination: 'ลาบวช',
  military: 'ลาทหาร',
  training: 'ลาอบรม',
  unpaid: 'ลาไม่รับเงินเดือน',
  other: 'อื่น ๆ',
};

const LEAVE_STATUS: Record<string, { label: string; kind: 'warn' | 'ok' | 'danger' }> = {
  pending: { label: 'รออนุมัติ', kind: 'warn' },
  approved: { label: 'อนุมัติแล้ว', kind: 'ok' },
  rejected: { label: 'ไม่อนุมัติ', kind: 'danger' },
};

const RECORD_KIND: Record<string, string> = {
  education: 'คุณวุฒิการศึกษา',
  experience: 'ประสบการณ์',
  training: 'อบรม/พัฒนา',
  award: 'รางวัล',
};

export function HrScreen() {
  const departments = useAsync(() => api.get<Department[]>('/hr/departments'), []);
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=200'), []);
  const [leaveStatus, setLeaveStatus] = useState('pending');
  const leaves = useAsync(() => api.get<Leave[]>(`/hr/leaves${qs({ status: leaveStatus })}`), [leaveStatus]);

  const [staffId, setStaffId] = useState('');
  const [decidedBy, setDecidedBy] = useState('');

  const records = useAsync(
    () => (staffId ? api.get<StaffRecord[]>(`/hr/staff/${staffId}/records`) : Promise.resolve([])),
    [staffId],
  );

  return (
    <>
      <PageHead title="งานบุคลากร" />

      <TableCard title="โครงสร้างหน่วยงาน">
        <AsyncView state={departments} empty="ยังไม่ได้ตั้งหน่วยงาน">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัส</th>
                  <th>ชื่อหน่วยงาน</th>
                  <th style={{ width: 150 }}>ประเภท</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((d) => (
                  <tr key={d.id}>
                    <td className="mono">{d.code}</td>
                    <td style={{ paddingLeft: 10 + d.depth * 22 }}>{d.name_th}</td>
                    <td>{d.kind}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <TableCard title="บุคลากร">
        <AsyncView state={staff}>
          {({ items: rows }) => rows.length === 0 ? (
            <div className="empty">ยังไม่มีบุคลากร</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 34 }} />
                  <th style={{ width: 120 }}>รหัส</th>
                  <th>ชื่อ — นามสกุล</th>
                  <th style={{ width: 90 }}>เป็นครู</th>
                  <th style={{ width: 200 }}>บทบาทที่ได้รับ</th>
                  <th style={{ width: 100 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <input
                        type="radio"
                        name="staff"
                        style={{ width: 'auto' }}
                        checked={staffId === s.id}
                        onChange={() => setStaffId(s.id)}
                      />
                    </td>
                    <td className="mono">{s.staff_code}</td>
                    <td>{s.full_name}</td>
                    <td>{s.is_teacher ? 'ใช่' : '—'}</td>
                    <td>
                      {(s.roles ?? []).length === 0
                        ? <span style={{ color: 'var(--ink-faint)' }}>ยังไม่ได้แต่งตั้ง</span>
                        : (s.roles ?? []).join(' · ')}
                    </td>
                    <td>
                      <Badge kind={s.active ? 'ok' : 'default'}>
                        {s.active ? 'ปฏิบัติงาน' : 'พ้นสภาพ'}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {staffId && (
        <TableCard title="ระเบียนประวัติ (ทช.1) ของคนที่เลือก">
          <AsyncView state={records} empty="ยังไม่มีระเบียนประวัติของคนนี้">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 150 }}>ประเภท</th>
                    <th>เรื่อง</th>
                    <th style={{ width: 200 }}>หน่วยงาน</th>
                    <th style={{ width: 200 }}>ช่วงเวลา</th>
                    <th className="num" style={{ width: 90 }}>ชั่วโมง</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.id}>
                      <td>{RECORD_KIND[r.kind] ?? r.kind}</td>
                      <td>{r.title_th}</td>
                      <td>{r.organization_th ?? '—'}</td>
                      <td>
                        {r.started_on ? thaiDate(r.started_on) : '—'}
                        {r.ended_on ? ` – ${thaiDate(r.ended_on)}` : ''}
                      </td>
                      <td className="num">{r.hours ? num(r.hours, 0) : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>
      )}

      <Card>
        <div className="row">
          <Field label="สถานะใบลาที่ดู">
            <select value={leaveStatus} onChange={(e) => setLeaveStatus(e.target.value)}>
              <option value="pending">รออนุมัติ</option>
              <option value="approved">อนุมัติแล้ว</option>
              <option value="rejected">ไม่อนุมัติ</option>
              <option value="">ทั้งหมด</option>
            </select>
          </Field>
          <label className="field" style={{ flex: 2 }}>
            <span>ผู้พิจารณา (ใช้ตอนกดอนุมัติ/ไม่อนุมัติ)</span>
            <AsyncView state={staff}>
              {({ items: rows }) => (
                <select value={decidedBy} onChange={(e) => setDecidedBy(e.target.value)}>
                  <option value="">— เลือกผู้พิจารณา —</option>
                  {rows.map((s) => (
                    <option key={s.person_id} value={s.person_id}>
                      {s.full_name} ({s.staff_code})
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
        <Notice kind="info">
          ฐานข้อมูลกันไม่ให้อนุมัติใบลาของตัวเอง — ถ้าเลือกคนเดียวกับผู้ยื่นจะถูกปฏิเสธ
        </Notice>
      </Card>

      <TableCard title="ใบลา">
        <AsyncView state={leaves} empty="ไม่มีใบลาในสถานะนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 170 }}>ผู้ยื่น</th>
                  <th style={{ width: 130 }}>ประเภท</th>
                  <th style={{ width: 210 }}>ช่วงวันที่</th>
                  <th className="num" style={{ width: 70 }}>วัน</th>
                  <th>เหตุผล</th>
                  <th style={{ width: 110 }}>สถานะ</th>
                  <th style={{ width: 190 }}>การทำงาน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((l) => {
                  const st = LEAVE_STATUS[l.status];
                  return (
                    <tr key={l.id}>
                      <td>{l.full_name}</td>
                      <td>{LEAVE_KIND[l.kind] ?? l.kind}</td>
                      <td>
                        {thaiDate(l.from_date)} – {thaiDate(l.to_date)}
                      </td>
                      <td className="num">{num(l.days, 1)}</td>
                      <td style={{ whiteSpace: 'normal' }}>{l.reason}</td>
                      <td>
                        <Badge kind={st?.kind ?? 'default'}>{st?.label ?? l.status}</Badge>
                      </td>
                      <td>
                        {l.status === 'pending' && decidedBy ? (
                          <span style={{ display: 'inline-flex', gap: 8 }}>
                            <ActionButton
                              className="primary"
                              onRun={() =>
                                api.post(`/hr/leaves/${l.id}/decision`, {
                                  status: 'approved',
                                  decidedBy,
                                })
                              }
                              onDone={() => leaves.reload()}
                            >
                              อนุมัติ
                            </ActionButton>
                            <ActionButton
                              className="danger"
                              onRun={() =>
                                api.post(`/hr/leaves/${l.id}/decision`, {
                                  status: 'rejected',
                                  decidedBy,
                                })
                              }
                              onDone={() => leaves.reload()}
                            >
                              ไม่อนุมัติ
                            </ActionButton>
                          </span>
                        ) : l.status === 'pending' ? (
                          <span style={{ color: 'var(--ink-faint)' }}>เลือกผู้พิจารณาก่อน</span>
                        ) : (
                          '—'
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
    </>
  );
}

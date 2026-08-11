/**
 * การลาของนักศึกษา
 *
 * ─── ทำไมหน้านี้ต้องบอกจำนวนคาบที่ปรับได้ ไม่ใช่แค่ "อนุมัติแล้ว" ───
 * การอนุมัติใบลาแก้ `attendance_record` จริง แต่แก้ได้เฉพาะคาบที่ยังไม่มี
 * การเช็คชื่อหรือที่เช็คไว้ว่าขาดเรียน — คาบที่ครูเช็คว่า "มาเรียน" จะถูกข้าม
 * ถ้าหน้าจอบอกแค่ว่าอนุมัติสำเร็จ เจ้าหน้าที่จะเข้าใจว่าเวลาเรียนถูกปรับครบแล้ว
 * ทั้งที่อาจไม่ได้ปรับสักคาบ แล้วนักศึกษาจะยังตกเกณฑ์ 80% โดยไม่มีใครรู้
 * จนถึงวันตัดเกรด
 *
 * ─── ทำไมการยกเลิกต้องกรอกเหตุผล ───
 * ฐานข้อมูลบังคับอยู่แล้ว (`cancel_student_leave` ปฏิเสธเหตุผลว่าง) —
 * หน้าจอถามก่อนเพื่อให้ได้ข้อความไทยที่อ่านรู้เรื่อง ไม่ใช่ error จาก plpgsql
 * และเพราะการยกเลิกใบที่อนุมัติแล้วจะ **คืนค่าเวลาเรียนกลับ** ซึ่งอาจทำให้
 * นักศึกษากลับไปตกเกณฑ์ทันที คนกดต้องรู้ตัวว่ากำลังทำอะไร
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDate, thaiDateTime } from '../core/fmt';
import { useSession } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync,
} from '../ui/kit';

interface Leave {
  id: string;
  student_id: string;
  kind: string;
  from_date: string;
  to_date: string;
  days: number;
  reason: string;
  evidence_note: string | null;
  status: string;
  applied_periods: number;
  requested_at: string;
  decided_at: string | null;
  decision_note: string | null;
  guardian_ack_at: string | null;
  student_code: string;
  full_name: string;
  requested_by_name: string | null;
  decided_by_name: string | null;
  guardian_ack_name: string | null;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

const KIND: Record<string, string> = {
  sick: 'ลาป่วย',
  personal: 'ลากิจ',
  activity: 'ไปราชการ/กิจกรรม',
};

const STATUS: Record<string, { label: string; kind: 'default' | 'ok' | 'warn' | 'danger' | 'info' }> = {
  submitted: { label: 'รออนุมัติ', kind: 'warn' },
  approved: { label: 'อนุมัติแล้ว', kind: 'ok' },
  rejected: { label: 'ไม่อนุมัติ', kind: 'danger' },
  cancelled: { label: 'ยกเลิกแล้ว', kind: 'default' },
};

export function StudentLeaveScreen() {
  const { role } = useSession();
  const canDecide = role != null &&
    ['registrar', 'student_affairs', 'director', 'admin'].includes(role);

  const [status, setStatus] = useState('submitted');
  const leaves = useAsync(() => api.get<Leave[]>(`/leaves${qs({ status })}`), [status]);

  const [typed, setTyped] = useState('');
  const [studentId, setStudentId] = useState('');
  const [kind, setKind] = useState('sick');
  const [fromDate, setFromDate] = useState('');
  const [toDate, setToDate] = useState('');
  const [reason, setReason] = useState('');
  const [evidenceNote, setEvidenceNote] = useState('');
  const [result, setResult] = useState<string | null>(null);

  const found = useAsync(
    () => (typed.trim().length >= 2
      ? api.get<StudentRow[]>(`/students${qs({ q: typed.trim(), limit: 20 })}`)
      : Promise.resolve([])),
    [typed],
  );

  return (
    <>
      <PageHead
        title="การลาของนักศึกษา"
        sub={leaves.data ? `${leaves.data.length} รายการ` : undefined}
      />

      <Notice kind="info">
        ใบลาที่อนุมัติแล้ว <strong>แก้เวลาเรียนจริง</strong> — คาบที่ครูยังไม่ได้เช็ค
        หรือเช็คไว้ว่าขาดเรียนจะกลายเป็นการลา ส่วนคาบที่ครูเช็คว่า “มาเรียน”
        จะถูกข้ามและรายงานกลับมา เพราะครูเห็นตัวจริง ใบลาไม่มีสิทธิ์เขียนทับ
      </Notice>

      <Card>
        <div className="row">
          <Field label="กรองตามสถานะ">
            <select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">ทุกสถานะ</option>
              {Object.entries(STATUS).map(([k, v]) => (
                <option key={k} value={k}>{v.label}</option>
              ))}
            </select>
          </Field>
          <div className="shrink">
            <button onClick={() => leaves.reload()}>โหลดใหม่</button>
          </div>
        </div>
      </Card>

      {result && <Notice kind="ok">{result}</Notice>}

      <TableCard title="ใบลา">
        <AsyncView state={leaves} empty="ไม่มีใบลาในสถานะนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                  <th style={{ width: 170 }}>ชื่อ — นามสกุล</th>
                  <th style={{ width: 120 }}>ประเภท</th>
                  <th style={{ width: 190 }}>ช่วงวันลา</th>
                  <th className="num" style={{ width: 60 }}>วัน</th>
                  <th>เหตุผล</th>
                  <th className="num" style={{ width: 90 }}>คาบที่ปรับ</th>
                  <th style={{ width: 120 }}>สถานะ</th>
                  {canDecide && <th style={{ width: 210 }}>การทำงาน</th>}
                </tr>
              </thead>
              <tbody>
                {rows.map((l) => {
                  const st = STATUS[l.status];
                  return (
                    <tr key={l.id}>
                      <td className="mono">{l.student_code}</td>
                      <td>{l.full_name}</td>
                      <td>{KIND[l.kind] ?? l.kind}</td>
                      <td>
                        {thaiDate(l.from_date)}
                        {l.from_date !== l.to_date && ` – ${thaiDate(l.to_date)}`}
                      </td>
                      <td className="num">{l.days}</td>
                      <td style={{ whiteSpace: 'normal' }}>
                        {l.reason}
                        {l.evidence_note && (
                          <div style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
                            เอกสาร: {l.evidence_note}
                          </div>
                        )}
                        <div style={{ color: 'var(--ink-faint)', fontSize: 11 }}>
                          ยื่นโดย {l.requested_by_name ?? '—'} · {thaiDateTime(l.requested_at)}
                          {l.guardian_ack_at &&
                            ` · ผู้ปกครองรับรอง (${l.guardian_ack_name ?? '—'})`}
                          {l.decided_at &&
                            ` · ${l.decided_by_name ?? '—'} ${thaiDateTime(l.decided_at)}`}
                          {l.decision_note && ` · ${l.decision_note}`}
                        </div>
                      </td>
                      <td className="num">
                        {l.status === 'approved' ? l.applied_periods : '—'}
                      </td>
                      <td>
                        <Badge kind={st?.kind ?? 'default'}>{st?.label ?? l.status}</Badge>
                      </td>
                      {canDecide && (
                        <td>
                          <span style={{ display: 'inline-flex', gap: 8 }}>
                            {l.status === 'submitted' && (
                              <>
                                <ActionButton
                                  className="primary"
                                  onRun={() =>
                                    api.post<{ applied_periods: number; skipped_present: number }>(
                                      `/leaves/${l.id}/decision`, { decision: 'approve' },
                                    )
                                  }
                                  onDone={(r) => {
                                    const x = r as { applied_periods: number; skipped_present: number };
                                    setResult(
                                      `อนุมัติแล้ว — ปรับเวลาเรียน ${x.applied_periods} คาบ` +
                                      (x.skipped_present > 0
                                        ? ` · ข้าม ${x.skipped_present} คาบที่ครูเช็คว่ามาเรียนแล้ว`
                                        : ''),
                                    );
                                    leaves.reload();
                                  }}
                                >
                                  อนุมัติ
                                </ActionButton>
                                <ActionButton
                                  className="danger"
                                  onRun={() =>
                                    api.post(`/leaves/${l.id}/decision`, { decision: 'reject' })
                                  }
                                  onDone={() => {
                                    setResult('บันทึกว่าไม่อนุมัติแล้ว');
                                    leaves.reload();
                                  }}
                                >
                                  ไม่อนุมัติ
                                </ActionButton>
                              </>
                            )}
                            {(l.status === 'submitted' || l.status === 'approved') && (
                              <CancelButton leave={l} onDone={(msg) => {
                                setResult(msg);
                                leaves.reload();
                              }} />
                            )}
                            {l.status !== 'submitted' && l.status !== 'approved' && '—'}
                          </span>
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {canDecide && (
        <Card title="บันทึกใบลาที่ส่งมาเป็นกระดาษ">
          <div className="row">
            <Field label="ค้นหานักศึกษา">
              <input
                value={typed}
                onChange={(e) => { setTyped(e.target.value); setStudentId(''); }}
                placeholder="รหัสนักศึกษา ชื่อ หรือนามสกุล"
              />
            </Field>
            <Field label="นักศึกษา">
              <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                <option value="">— เลือกจากผลค้นหา —</option>
                {(found.data ?? []).map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.student_code} {s.full_name}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="ประเภท">
              <select value={kind} onChange={(e) => setKind(e.target.value)}>
                {Object.entries(KIND).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
            </Field>
          </div>
          <div className="row">
            <Field label="ตั้งแต่วันที่">
              <input type="date" value={fromDate} onChange={(e) => setFromDate(e.target.value)} />
            </Field>
            <Field label="ถึงวันที่">
              <input type="date" value={toDate} onChange={(e) => setToDate(e.target.value)} />
            </Field>
            <Field label="เหตุผล">
              <input value={reason} onChange={(e) => setReason(e.target.value)} />
            </Field>
            <Field label="เอกสารประกอบ">
              <input
                value={evidenceNote}
                onChange={(e) => setEvidenceNote(e.target.value)}
                placeholder="เช่น ใบรับรองแพทย์ รพ.… เลขที่ … ตัวจริงอยู่ที่งานปกครอง"
              />
            </Field>
            <div className="shrink">
              <ActionButton
                className="primary"
                onRun={() =>
                  api.post('/leaves', {
                    studentId, kind,
                    fromDate, toDate: toDate || fromDate,
                    reason,
                    evidenceNote: evidenceNote || undefined,
                  })
                }
                onDone={() => {
                  setResult('บันทึกใบลาแล้ว — ยังไม่อนุมัติ ต้องกดอนุมัติอีกครั้ง');
                  setReason(''); setEvidenceNote('');
                  setStatus('submitted');
                  leaves.reload();
                }}
              >
                บันทึกใบลา
              </ActionButton>
            </div>
          </div>
          <Notice kind="info">
            บันทึกแล้ว<strong>ยังไม่มีผลกับเวลาเรียน</strong> จนกว่าจะกดอนุมัติ —
            แยกสองขั้นโดยตั้งใจ เพราะการรับใบกับการตัดสินใจเป็นคนละหน้าที่
            และระบบต้องบอกได้ว่าใครเป็นคนอนุมัติ
          </Notice>
        </Card>
      )}
    </>
  );
}

/** ปุ่มยกเลิกที่ถามเหตุผลก่อน — ฐานข้อมูลปฏิเสธเหตุผลว่างอยู่แล้ว */
function CancelButton({ leave, onDone }: { leave: Leave; onDone: (msg: string) => void }) {
  return (
    <ActionButton
      onRun={async () => {
        const reason = window.prompt(
          leave.status === 'approved'
            ? 'ยกเลิกใบลาที่อนุมัติแล้ว — เวลาเรียนจะถูกคืนค่าเดิม ระบุเหตุผล'
            : 'ยกเลิกใบลานี้ — ระบุเหตุผล',
        );
        if (reason == null || reason.trim() === '') {
          throw new Error('ต้องระบุเหตุผลที่ยกเลิก');
        }
        return api.post<{ reverted: number }>(`/leaves/${leave.id}/cancel`, { reason });
      }}
      onDone={(r) => {
        const x = r as { reverted: number };
        onDone(`ยกเลิกแล้ว — คืนค่าเวลาเรียน ${x.reverted} แถว`);
      }}
    >
      ยกเลิก
    </ActionButton>
  );
}

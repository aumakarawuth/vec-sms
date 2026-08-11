/**
 * คำร้องขอแก้เกรด
 *
 * ─── ทำไมหน้าจอนี้สำคัญกว่าที่หน้าตาบอก ───
 * `grade_change_request` เป็น **ทางเดียว** ที่เกรดที่ล็อกแล้วเปลี่ยนได้
 * ทั้งระบบ — แม้แต่รอบสอบซ่อมก็ยื่นผ่านทางนี้ ไม่ได้เขียน `enrollment_result`
 * เอง (หลักข้อ 3ก) ถ้าเปิดทางที่สอง ใครที่สร้างรอบสอบซ่อมได้จะแก้เกรดใครก็ได้
 * โดยไม่ต้องผ่านการอนุมัติของใครเลย
 *
 * ─── ทำไมต้องมีผู้อนุมัติสองคน ───
 * บังคับที่ trigger ในฐานข้อมูล ไม่ใช่ที่หน้าจอ — คนเดียวกันกดอนุมัติซ้ำ
 * สองครั้งไม่นับเป็นสองคน หน้าจอนี้แค่แสดงว่าอนุมัติไปแล้วกี่คน
 * และปุ่มที่กดได้จะถูกฐานข้อมูลปฏิเสธเองถ้าเป็นคนเดิม
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDateTime } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface ChangeRequest {
  id: string;
  enrollment_id: string;
  status: string;
  reason: string;
  document_no: string | null;
  to_raw_score: string | null;
  created_at: string;
  requested_by: string | null;
  approver_1_id: string | null;
  approver_2_id: string | null;
  student_code: string;
  full_name: string;
  course_code: string;
  course_name: string;
  from_symbol: string;
  to_symbol: string;
}

const STATUS: Record<string, { label: string; kind: 'warn' | 'ok' | 'danger' | 'info' }> = {
  pending: { label: 'รออนุมัติ', kind: 'warn' },
  approved: { label: 'อนุมัติแล้ว', kind: 'ok' },
  rejected: { label: 'ไม่อนุมัติ', kind: 'danger' },
  applied: { label: 'บันทึกลงระเบียนแล้ว', kind: 'ok' },
};

export function ChangeRequestsScreen() {
  const [status, setStatus] = useState('pending');
  const list = useAsync(
    () => api.get<ChangeRequest[]>(`/gradebook/change-requests${qs({ status })}`),
    [status],
  );

  return (
    <>
      <PageHead
        title="คำร้องขอแก้เกรด"
        sub={list.data ? `${list.data.length} รายการ` : undefined}
      />

      <Notice kind="info">
        นี่คือทางเดียวที่เกรดซึ่งล็อกแล้วจะเปลี่ยนได้ — รอบสอบซ่อมก็ยื่นผ่านทางนี้
        และต้องมีผู้อนุมัติ <strong>สองคนที่ไม่ใช่คนเดียวกัน</strong>
        ซึ่งบังคับที่ฐานข้อมูล ไม่ใช่ที่หน้าจอนี้
      </Notice>

      <Card>
        <div className="row">
          <label className="field" style={{ maxWidth: 220 }}>
            <span>สถานะ</span>
            <select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="pending">รออนุมัติ</option>
              <option value="approved">อนุมัติแล้ว</option>
              <option value="rejected">ไม่อนุมัติ</option>
              <option value="">ทั้งหมด</option>
            </select>
          </label>
          <div className="shrink">
            <button onClick={() => list.reload()}>โหลดใหม่</button>
          </div>
        </div>
      </Card>

      <TableCard title="รายการคำร้อง">
        <AsyncView state={list} empty="ไม่มีคำร้องในสถานะนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                  <th style={{ width: 150 }}>ชื่อ — นามสกุล</th>
                  <th style={{ width: 200 }}>รายวิชา</th>
                  <th style={{ width: 110 }}>เปลี่ยนเกรด</th>
                  <th>เหตุผล</th>
                  <th style={{ width: 110 }}>ผู้อนุมัติ</th>
                  <th style={{ width: 110 }}>สถานะ</th>
                  <th style={{ width: 190 }}>การทำงาน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const approvals = [r.approver_1_id, r.approver_2_id].filter(Boolean).length;
                  const st = STATUS[r.status];
                  return (
                    <tr key={r.id}>
                      <td className="mono">{r.student_code}</td>
                      <td>{r.full_name}</td>
                      <td>
                        <span className="mono">{r.course_code}</span> {r.course_name}
                      </td>
                      <td>
                        <Badge kind="danger">{r.from_symbol}</Badge>
                        {' → '}
                        <Badge kind="ok">{r.to_symbol}</Badge>
                      </td>
                      <td style={{ whiteSpace: 'normal' }}>
                        {r.reason}
                        {r.document_no && (
                          <span style={{ color: 'var(--ink-soft)' }}> · เลขที่ {r.document_no}</span>
                        )}
                        <div style={{ color: 'var(--ink-faint)', fontSize: 11 }}>
                          ยื่นเมื่อ {thaiDateTime(r.created_at)}
                        </div>
                      </td>
                      <td>
                        <Badge kind={approvals >= 2 ? 'ok' : approvals === 1 ? 'warn' : 'default'}>
                          {approvals}/2 คน
                        </Badge>
                      </td>
                      <td>
                        <Badge kind={st?.kind ?? 'default'}>{st?.label ?? r.status}</Badge>
                      </td>
                      <td>
                        {r.status === 'pending' ? (
                          <Actions id={r.id} onDone={() => list.reload()} />
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

function Actions({ id, onDone }: { id: string; onDone: () => void }) {
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState('');

  if (rejecting) {
    return (
      <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="เหตุผลที่ไม่อนุมัติ"
          style={{ width: 150 }}
          autoFocus
        />
        <ActionButton
          className="danger"
          onRun={() => api.post(`/gradebook/change-requests/${id}/reject`, { reason: reason.trim() })}
          onDone={() => {
            setRejecting(false);
            setReason('');
            onDone();
          }}
        >
          ยืนยัน
        </ActionButton>
        <button className="link" onClick={() => setRejecting(false)}>ยกเลิก</button>
      </span>
    );
  }

  return (
    <span style={{ display: 'inline-flex', gap: 8, alignItems: 'center' }}>
      <ActionButton
        className="primary"
        confirm="ลงชื่ออนุมัติคำร้องนี้ — ต้องมีผู้อนุมัติสองคนจึงจะมีผล ยืนยันหรือไม่"
        onRun={() => api.post(`/gradebook/change-requests/${id}/approve`)}
        onDone={onDone}
      >
        อนุมัติ
      </ActionButton>
      <button className="link" onClick={() => setRejecting(true)}>
        ไม่อนุมัติ
      </button>
    </span>
  );
}

/**
 * รายงานการเงินแบบ SISA — หนึ่งการ์ดตอบหนึ่งคำถาม และมีตัวกรองของคำถามนั้น
 * (docs/sisa-function-audit-2026-10-31.md หมวดการเงิน ข้อ 7–9 · 20–30 · 8)
 *
 * ทุกการ์ดอ่านอย่างเดียว — ตัวเลขใบเสร็จมาจาก payload ที่ตรึงไว้ตอนออกใบ
 * จึงตรงกับกระดาษที่ผู้ปกครองถืออยู่เสมอ
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { money, thaiDate } from '../core/fmt';
import { useScope } from '../core/scope';
import { AsyncView, Badge, Card, Field, PrintButton, TableCard, useAsync } from '../ui/kit';

interface ReceiptRow {
  id: string; doc_no: string; issued_on: string; voided_at: string | null; void_reason: string | null;
  amount: string; method: string; student_code: string; student_name: string; received_by: string | null;
}
interface CashierRow {
  receivedBy: string | null; method: string; receipts: number; amount: number; voided: number; voidedAmount: number;
}
interface RoomRow {
  studyYear: number | null; groupCode: string | null; students: number;
  billed: number; paid: number; outstanding: number; owing: number;
}
interface ArrearsRow { student_id: string; student_code: string; full_name: string; billed: string; paid: string; outstanding: string }
interface FundingRow {
  id: string; student_code: string; full_name: string; kind: string; source_name: string;
  percent_off: string | null; amount: string | null; fee_item_name: string | null; document_no: string | null;
}

export function ReceiptSearchCard({ methods }: { methods: Record<string, string> }) {
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [method, setMethod] = useState('');
  const [status, setStatus] = useState('');
  const [q, setQ] = useState('');
  const [docFrom, setDocFrom] = useState('');
  const [docTo, setDocTo] = useState('');
  const rows = useAsync(
    () => api.get<ReceiptRow[]>(`/finance/receipts/search${qs({
      from: from || undefined, to: to || undefined, method: method || undefined,
      status: status || undefined, q: q.trim() || undefined,
      docFrom: docFrom.trim() || undefined, docTo: docTo.trim() || undefined,
    })}`),
    [from, to, method, status, q, docFrom, docTo],
  );

  return (
    <>
      <Card title="ค้นหาใบเสร็จ">
        <div className="row">
          <Field label="ตั้งแต่วันที่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label="ถึงวันที่"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
          <Field label="เลขที่ใบเสร็จ ตั้งแต่"><input value={docFrom} onChange={(e) => setDocFrom(e.target.value)} /></Field>
          <Field label="ถึงเลขที่"><input value={docTo} onChange={(e) => setDocTo(e.target.value)} /></Field>
        </div>
        <div className="row">
          <Field label="นักศึกษา (รหัสหรือชื่อ)"><input value={q} onChange={(e) => setQ(e.target.value)} /></Field>
          <Field label="ช่องทางชำระ">
            <select value={method} onChange={(e) => setMethod(e.target.value)}>
              <option value="">ทุกช่องทาง</option>
              {Object.entries(methods).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </Field>
          <Field label="สถานะ">
            <select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">ทั้งหมด</option>
              <option value="active">ใช้งาน</option>
              <option value="void">ยกเลิกแล้ว</option>
            </select>
          </Field>
        </div>
      </Card>
      <TableCard title="ผลการค้นหา (สูงสุด 500 ใบ)">
        <AsyncView state={rows} empty="ไม่พบใบเสร็จตามเงื่อนไข">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>เลขที่</th>
                  <th style={{ width: 110 }}>วันที่</th>
                  <th>นักศึกษา</th>
                  <th style={{ width: 120 }}>ช่องทาง</th>
                  <th style={{ width: 160 }}>ผู้รับเงิน</th>
                  <th className="num" style={{ width: 110 }}>จำนวนเงิน</th>
                  <th style={{ width: 110 }} />
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.id} style={{ opacity: r.voided_at ? 0.55 : 1 }}>
                    <td className="mono">{r.doc_no}</td>
                    <td>{thaiDate(r.issued_on)}</td>
                    <td>
                      {r.student_code} {r.student_name}
                      {r.voided_at && <> <Badge kind="danger">ยกเลิกแล้ว</Badge>{r.void_reason ? ` — ${r.void_reason}` : ''}</>}
                    </td>
                    <td>{methods[r.method] ?? r.method}</td>
                    <td>{r.received_by ?? '—'}</td>
                    <td className="num">{money(r.amount)}</td>
                    <td><PrintButton path={`/finance/receipts/${r.id}/print`}>พิมพ์ซ้ำ</PrintButton></td>
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

/** ปิดยอดตามผู้รับเงิน — นับจากใบเสร็จทุกใบ ไม่ใช่เฉพาะที่กระทบยอดแล้ว */
export function CashierSummaryCard({ methods }: { methods: Record<string, string> }) {
  const today = new Date().toISOString().slice(0, 10);
  const [from, setFrom] = useState(today);
  const [to, setTo] = useState(today);
  const rows = useAsync(
    () => api.get<CashierRow[]>(`/finance/reports/cashier${qs({ from: from || undefined, to: to || undefined })}`),
    [from, to],
  );

  return (
    <TableCard
      title="ปิดยอดตามผู้รับเงิน"
      actions={
        <div className="row" style={{ gap: 8, alignItems: 'center' }}>
          <Field label="ตั้งแต่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label="ถึง"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      }
    >
      <AsyncView state={rows} empty="ไม่มีใบเสร็จในช่วงนี้">
        {(list) => (
          <table>
            <thead>
              <tr>
                <th>ผู้รับเงิน</th>
                <th style={{ width: 140 }}>ช่องทาง</th>
                <th className="num" style={{ width: 90 }}>ใบเสร็จ</th>
                <th className="num" style={{ width: 130 }}>ยอดรับ</th>
                <th className="num" style={{ width: 90 }}>ยกเลิก</th>
                <th className="num" style={{ width: 130 }}>ยอดที่ยกเลิก</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={`${r.receivedBy}|${r.method}`}>
                  <td>{r.receivedBy ?? '—'}</td>
                  <td>{methods[r.method] ?? r.method}</td>
                  <td className="num">{r.receipts}</td>
                  <td className="num">{money(r.amount)}</td>
                  <td className="num">{r.voided || ''}</td>
                  <td className="num">{r.voided ? money(r.voidedAmount) : ''}</td>
                </tr>
              ))}
              <tr style={{ fontWeight: 600 }}>
                <td colSpan={2}>รวม</td>
                <td className="num">{list.reduce((t, r) => t + r.receipts, 0)}</td>
                <td className="num">{money(list.reduce((t, r) => t + r.amount, 0))}</td>
                <td className="num">{list.reduce((t, r) => t + r.voided, 0) || ''}</td>
                <td />
              </tr>
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

/**
 * ชำระ/ค้างชำระแยกห้อง — คลิกห้องเพื่อดูรายชื่อคนที่ยังค้าง (ไล่จากภาพรวม
 * ลงรายคน แบบเดียวกับหน้ารายงานของ SISA)
 */
export function RoomSummaryCard() {
  const scope = useScope();
  const yearId = scope.yearId;
  const rooms = useAsync(
    () => (yearId ? api.get<RoomRow[]>(`/finance/reports/rooms${qs({ academicYearId: yearId })}`) : Promise.resolve([])),
    [yearId],
  );
  const [picked, setPicked] = useState<RoomRow | null>(null);
  const arrears = useAsync(
    () =>
      picked && yearId
        ? api.get<ArrearsRow[]>(`/finance/reports/rooms/arrears${qs({ academicYearId: yearId, groupCode: picked.groupCode ?? undefined })}`)
        : Promise.resolve([]),
    [picked, yearId],
  );
  const label = (r: RoomRow) => (r.groupCode ? `ชั้นปี ${r.studyYear ?? '—'} · ห้อง ${r.groupCode}` : 'ยังไม่จัดห้อง');

  return (
    <>
      <TableCard title="การชำระแยกตามห้อง (ทั้งปีการศึกษาที่เลือกด้านบน)">
        <AsyncView state={rooms} empty="ยังไม่มีใบแจ้งหนี้ในปีการศึกษานี้">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th>ห้อง</th>
                  <th className="num" style={{ width: 90 }}>นักศึกษา</th>
                  <th className="num" style={{ width: 130 }}>เรียกเก็บ</th>
                  <th className="num" style={{ width: 130 }}>ชำระแล้ว</th>
                  <th className="num" style={{ width: 90 }}>ชำระ (%)</th>
                  <th className="num" style={{ width: 130 }}>ค้าง</th>
                  <th className="num" style={{ width: 90 }}>คนที่ค้าง</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr
                    key={r.groupCode ?? '-'}
                    onClick={() => setPicked(r)}
                    style={{ cursor: 'pointer', background: picked?.groupCode === r.groupCode ? 'var(--row-active, #eef2ff)' : undefined }}
                  >
                    <td>{label(r)}</td>
                    <td className="num">{r.students}</td>
                    <td className="num">{money(r.billed)}</td>
                    <td className="num">{money(r.paid)}</td>
                    <td className="num">{r.billed ? Math.round((r.paid / r.billed) * 100) : 0}</td>
                    <td className="num">{money(r.outstanding)}</td>
                    <td className="num">{r.owing ? <Badge kind="warn">{r.owing}</Badge> : 0}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
      {picked && (
        <TableCard title={`รายชื่อค้างชำระ — ${label(picked)}`}>
          <AsyncView state={arrears} empty="ห้องนี้ไม่มีคนค้างชำระ">
            {(list) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 130 }}>รหัส</th>
                    <th>ชื่อ</th>
                    <th className="num" style={{ width: 130 }}>เรียกเก็บ</th>
                    <th className="num" style={{ width: 130 }}>ชำระแล้ว</th>
                    <th className="num" style={{ width: 130 }}>ค้าง</th>
                  </tr>
                </thead>
                <tbody>
                  {list.map((r) => (
                    <tr key={r.student_id}>
                      <td className="mono">{r.student_code}</td>
                      <td><a href={`#/finance/payments?studentId=${r.student_id}`}>{r.full_name}</a></td>
                      <td className="num">{money(r.billed)}</td>
                      <td className="num">{money(r.paid)}</td>
                      <td className="num">{money(r.outstanding)}</td>
                    </tr>
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

export function FundingReportCard() {
  const yearId = useScope().yearId;
  const rows = useAsync(
    () => (yearId ? api.get<FundingRow[]>(`/finance/reports/funding${qs({ academicYearId: yearId })}`) : Promise.resolve([])),
    [yearId],
  );
  return (
    <TableCard title="นักศึกษาที่ได้รับทุนและส่วนลด (ปีการศึกษาที่เลือกด้านบน)">
      <AsyncView state={rows} empty="ยังไม่มีนักศึกษาได้รับทุนหรือส่วนลดในปีนี้">
        {(list) => (
          <table>
            <thead>
              <tr>
                <th>แหล่งทุน</th>
                <th style={{ width: 130 }}>รหัส</th>
                <th>ชื่อ</th>
                <th>ลดรายการ</th>
                <th className="num" style={{ width: 130 }}>ส่วนลด</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td>{r.source_name}</td>
                  <td className="mono">{r.student_code}</td>
                  <td>{r.full_name}</td>
                  <td>{r.fee_item_name ?? 'ทุกรายการ'}</td>
                  <td className="num">{r.percent_off ? `${Number(r.percent_off)}%` : money(r.amount)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

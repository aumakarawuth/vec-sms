/**
 * งานการเงิน — ออกใบแจ้งหนี้ รับชำระ และดูยอดค้าง
 *
 * ─── ทำไมไม่มีปุ่มแก้ยอดในใบแจ้งหนี้ ───
 * ใบแจ้งหนี้ออกจาก `fee_schedule` ของชั้นปีและปีการศึกษานั้น ไม่ใช่ตัวเลข
 * ที่เจ้าหน้าที่พิมพ์เอง — โรงเรียนเอกชนถูกตรวจย้อนหลังได้ว่าเก็บตรงกับ
 * ประกาศที่แจ้งไว้หรือไม่ ถ้าให้แก้ยอดรายคนจากหน้าจอ ความสอดคล้องนั้นหายทันที
 * ส่วนลดและทุนไปที่ `funding_source` ซึ่งบันทึกว่าลดเพราะอะไร
 *
 * ─── ทำไมปุ่มปรับสถานะระงับสิทธิ์อยู่ตรงนี้ ───
 * งานประจำวันปรับให้คืนละครั้ง แต่เจ้าหน้าที่ที่เพิ่งรับชำระเงินต้องปลดให้
 * นักศึกษาลงทะเบียนได้เดี๋ยวนี้ ไม่ใช่พรุ่งนี้
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { money, thaiDate } from '../core/fmt';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, PrintButton, TableCard, useAsync,
} from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const METHOD: Record<string, string> = {
  cash: 'เงินสด',
  bank_transfer: 'โอนเงิน',
  promptpay: 'พร้อมเพย์',
  credit_card: 'บัตรเครดิต',
  counter_service: 'เคาน์เตอร์เซอร์วิส',
  direct_debit: 'หักบัญชีอัตโนมัติ',
  gov_subsidy: 'เงินอุดหนุนรัฐ',
  student_loan: 'กองทุนกู้ยืม',
  scholarship: 'ทุนการศึกษา',
  adjustment: 'ปรับปรุงรายการ',
};

/*
 * `v_ar_aging.bucket` คืนข้อความไทยมาแล้ว ไม่ใช่รหัส — หน้าจอจึงไม่แปลซ้ำ
 * เหลือแค่เลือกสีตามความหนักของหนี้ ถ้าแปลซ้ำที่นี่แล้ววันหนึ่งฐานข้อมูล
 * เปลี่ยนช่วงวัน หน้าจอจะแสดงช่วงเก่าทับค่าจริงโดยไม่มีอะไรฟ้อง
 */
function bucketKind(bucket: string): 'default' | 'warn' | 'danger' {
  if (bucket.includes('ยังไม่')) return 'default';
  if (bucket.includes('60 วันขึ้นไป')) return 'danger';
  return 'warn';
}

interface AgingRow {
  bucket: string;
  students: string | number;
  amount: string | number;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

interface Receipt {
  id: string;
  doc_no: string;
  issued_on: string;
  voided_at: string | null;
  void_reason: string | null;
  amount: string | number;
  method: string;
  amount_text: string;
}

interface PaymentResult {
  paymentId: string;
  receipt: { id: string; doc_no: string } | null;
  overpaid: number;
}

interface Balance {
  billed: number | string;
  paid: number | string;
  outstanding: number | string;
  next_due_on: string | null;
  days_overdue: number | null;
}

export function FinanceScreen() {
  const { terms, termId, setTerm } = useTermPicker();
  const aging = useAsync(() => api.get<AgingRow[]>('/finance/ar-aging'), []);
  const students = useAsync(() => api.get<StudentRow[]>('/students?limit=200'), []);

  const [studentId, setStudentId] = useState('');
  const [installments, setInstallments] = useState('2');
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState('cash');
  const [note, setNote] = useState('');
  /** ใบเสร็จของการรับเงินครั้งล่าสุด — สิ่งที่ต้องพิมพ์ให้คนที่ยืนรออยู่ */
  const [justIssued, setJustIssued] = useState<{ id: string; doc_no: string } | null>(null);

  const balance = useAsync(
    () =>
      studentId
        ? api.get<Balance>(`/students/${studentId}/balance`)
        : Promise.resolve(null as unknown as Balance),
    [studentId],
  );

  const receipts = useAsync(
    () =>
      studentId
        ? api.get<Receipt[]>(`/finance/receipts${qs({ studentId })}`)
        : Promise.resolve([]),
    [studentId],
  );

  return (
    <>
      <PageHead
        title="งานการเงิน"
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <TableCard
        title="ยอดลูกหนี้แยกตามอายุหนี้"
        actions={
          <ActionButton onRun={() => api.post('/finance/holds/refresh')} onDone={() => aging.reload()}>
            ปรับสถานะระงับสิทธิ์
          </ActionButton>
        }
      >
        <AsyncView state={aging} empty="ยังไม่มียอดค้างชำระ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th>ช่วงอายุหนี้</th>
                  <th className="num" style={{ width: 120 }}>จำนวนนักศึกษา</th>
                  <th className="num" style={{ width: 160 }}>ยอดเงิน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.bucket}>
                    <td>
                      <Badge kind={bucketKind(r.bucket)}>{r.bucket}</Badge>
                    </td>
                    <td className="num">{r.students}</td>
                    <td className="num">{money(r.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <Card title="เลือกนักศึกษา">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>นักศึกษา</span>
            <AsyncView state={students}>
              {(rows) => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {rows.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.student_code} {s.full_name}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
      </Card>

      {studentId && (
        <>
          <Card title="ยอดของนักศึกษาคนนี้">
            <AsyncView state={balance}>
              {(b) => (
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

          <Card title="ออกใบแจ้งหนี้ของภาคเรียนที่เลือก">
            <div className="row">
              <Field label="จำนวนงวด">
                <select value={installments} onChange={(e) => setInstallments(e.target.value)}>
                  {[1, 2, 3, 4, 5, 6].map((n) => (
                    <option key={n} value={n}>{n} งวด</option>
                  ))}
                </select>
              </Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post('/finance/invoices', {
                      studentId,
                      termId,
                      installments: Number(installments),
                    })
                  }
                  onDone={() => balance.reload()}
                >
                  ออกใบแจ้งหนี้
                </ActionButton>
              </div>
              <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                ยอดมาจากโครงสร้างค่าธรรมเนียมของชั้นปีและปีการศึกษานั้น
                ไม่ใช่ตัวเลขที่กรอกเอง — เพื่อให้ตรงกับประกาศที่แจ้งไว้เสมอ
              </div>
            </div>
          </Card>

          <Card title="รับชำระเงิน">
            <div className="row">
              <Field label="จำนวนเงิน">
                <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" />
              </Field>
              <Field label="ช่องทาง">
                <select value={method} onChange={(e) => setMethod(e.target.value)}>
                  {Object.entries(METHOD).map(([v, l]) => (
                    <option key={v} value={v}>{l}</option>
                  ))}
                </select>
              </Field>
              <Field label="หมายเหตุ (ถ้ามี)">
                <input value={note} onChange={(e) => setNote(e.target.value)} />
              </Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post<PaymentResult>('/finance/payments', {
                      studentId,
                      amount: Number(amount),
                      method,
                      ...(note.trim() ? { note: note.trim() } : {}),
                    })
                  }
                  onDone={(r) => {
                    setAmount('');
                    setNote('');
                    setJustIssued((r as PaymentResult).receipt);
                    balance.reload();
                    aging.reload();
                    receipts.reload();
                  }}
                >
                  บันทึกการรับชำระ
                </ActionButton>
              </div>
            </div>
            {/*
              ─── ไม่มีช่องให้กรอกเลขที่ใบเสร็จอีกแล้ว ───
              เลขออกจากสายเลขของสถานศึกษาตอนบันทึกการรับชำระ (0068) ของเดิม
              ให้พิมพ์เอง ซึ่งแปลว่าเลขซ้ำกันสองใบก็ได้ เว้นว่างก็ได้ และไม่มี
              อะไรผูกเลขนั้นกับกระดาษที่พิมพ์ออกไปเลย
            */}
            {justIssued && (
              <Notice kind="ok">
                <div className="row" style={{ alignItems: 'center' }}>
                  <span>
                    รับชำระแล้ว — ใบเสร็จเลขที่ <strong>{justIssued.doc_no}</strong>
                  </span>
                  <div className="shrink">
                    <PrintButton path={`/finance/receipts/${justIssued.id}/print`}>
                      พิมพ์ใบเสร็จ
                    </PrintButton>
                  </div>
                </div>
              </Notice>
            )}
          </Card>

          <TableCard title="ใบเสร็จที่ออกให้นักศึกษาคนนี้">
            <AsyncView state={receipts} empty="ยังไม่เคยออกใบเสร็จให้นักศึกษาคนนี้">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 130 }}>เลขที่</th>
                      <th style={{ width: 130 }}>วันที่</th>
                      <th className="num" style={{ width: 120 }}>จำนวนเงิน</th>
                      <th>ตัวอักษร</th>
                      <th style={{ width: 130 }} />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.id} style={{ opacity: r.voided_at ? 0.55 : 1 }}>
                        <td className="mono">{r.doc_no}</td>
                        <td>{thaiDate(r.issued_on)}</td>
                        <td className="num">{money(r.amount)}</td>
                        <td>
                          {r.amount_text}
                          {r.voided_at && (
                            <>
                              {' '}
                              <Badge kind="danger">ยกเลิกแล้ว</Badge>
                              {r.void_reason ? ` — ${r.void_reason}` : ''}
                            </>
                          )}
                        </td>
                        <td>
                          {/*
                            พิมพ์ซ้ำอ่านจาก payload ที่ตรึงไว้ ไม่ได้ออกใบใหม่ —
                            เลขที่จึงไม่เดินและกระดาษที่ได้เหมือนใบแรกทุกตัวอักษร
                          */}
                          <PrintButton path={`/finance/receipts/${r.id}/print`}>
                            พิมพ์ซ้ำ
                          </PrintButton>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

          <Notice kind="info">
            เงินที่รับเข้ามาจะถูกตัดกับงวดที่ครบกำหนดก่อนเสมอตามลำดับที่
            ฐานข้อมูลกำหนด ไม่ใช่ให้เจ้าหน้าที่เลือกว่าจะตัดงวดไหน
          </Notice>
        </>
      )}
    </>
  );
}

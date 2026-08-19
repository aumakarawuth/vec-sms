/**
 * แม่แบบพิมพ์ใบเสร็จรับเงิน (0068)
 *
 * ─── แม่แบบห้ามแตะฐานข้อมูล ───
 * ทุกอย่างบนกระดาษอ่านจาก `payload` เท่านั้น หลักเดียวกับอีกแปดใบ —
 * ใบเสร็จเป็นใบที่ข้อนี้สำคัญที่สุด เพราะผู้ปกครองถือฉบับหนึ่งและฝ่ายบัญชี
 * ถือสำเนาอีกฉบับ ถ้าพิมพ์ซ้ำแล้วยอดขยับตามข้อมูลที่เปลี่ยนไปทีหลัง
 * กระดาษสองใบที่ควรเหมือนกันจะไม่ตรงกันโดยไม่มีใครรู้
 *
 * ─── ทำไมรายการบนใบคือ "งวดที่ตัด" ไม่ใช่ "รายการค่าธรรมเนียม" ───
 * ใบเสร็จรับรองว่ารับเงินไปเท่าไรและเงินนั้นไปหักอะไร ถ้าพิมพ์รายการทั้ง
 * ใบแจ้งหนี้ (ค่าลงทะเบียน ค่าบำรุง ...) ยอดรวมบนใบจะไม่เท่ากับเงินที่รับ
 * ในครั้งนั้น ซึ่งเป็นกระดาษที่อธิบายให้ผู้ปกครองไม่ได้
 */
import type { IssuedDocument } from './templates';
import { thaiDate } from './templates';

function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function money(v: unknown): string {
  const n = Number(v ?? 0);
  return n.toLocaleString('th-TH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** ป้ายวิธีชำระเงิน — ค่าเดียวกับ enum `payment_method` ใน 0010 */
const METHOD_TH: Record<string, string> = {
  cash: 'เงินสด',
  bank_transfer: 'โอนเงินผ่านธนาคาร',
  promptpay: 'พร้อมเพย์',
  credit_card: 'บัตรเครดิต',
  counter_service: 'เคาน์เตอร์เซอร์วิส',
  direct_debit: 'หักบัญชีอัตโนมัติ',
  gov_subsidy: 'เงินอุดหนุนจากรัฐ',
  student_loan: 'กองทุนเงินให้กู้ยืมเพื่อการศึกษา',
  scholarship: 'ทุนการศึกษา',
};

/** วิธีที่เงินยังไม่ถึงมือจริงจนกว่าจะเรียกเก็บได้ — ต้องมีข้อความกำกับบนใบ */
const NON_CASH = new Set([
  'bank_transfer', 'promptpay', 'credit_card', 'counter_service',
  'direct_debit', 'gov_subsidy', 'student_loan', 'scholarship',
]);

interface ReceiptLine {
  invoice_no?: string;
  term?: { year_be?: number; ordinal?: number };
  seq?: number;
  due_on?: string;
  amount?: number | string;
}

export interface ReceiptPayload {
  kind: string;
  payment_id?: string;
  institution?: { name_th?: string; code?: string };
  student?: { student_code?: string; full_name?: string };
  payment?: {
    received_on?: string;
    amount?: number | string;
    method?: string;
    bank_ref?: string | null;
    note?: string | null;
  };
  lines?: ReceiptLine[];
  unallocated?: number | string;
  amount_text?: string;
  received_by?: string;
}

export interface ReceiptDocument extends Omit<IssuedDocument, 'payload'> {
  payload: ReceiptPayload;
}

const RECEIPT_STYLE = `
  @page { size: A5 landscape; margin: 10mm 12mm; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', 'Tahoma', sans-serif;
    font-size: 14pt; line-height: 1.4; color: #000;
  }
  .sheet { position: relative; }
  .stamp {
    position: fixed; top: 34%; left: 0; right: 0; text-align: center;
    font-size: 72pt; font-weight: 700; letter-spacing: 0.15em;
    transform: rotate(-20deg); pointer-events: none;
  }
  .stamp.void { color: rgba(190, 0, 0, 0.18); }
  .stamp.copy { color: rgba(0, 0, 0, 0.09); }
  .void-note {
    border: 1.2pt solid #b00; color: #b00; padding: 3pt 6pt;
    margin-bottom: 6pt; font-size: 12pt;
  }
  .school { font-size: 18pt; font-weight: 700; text-align: center; }
  .code { text-align: center; font-size: 11.5pt; color: #333; }
  .title { font-size: 17pt; font-weight: 700; text-align: center; margin: 8pt 0 2pt; }
  .doc-line { display: flex; justify-content: space-between; margin-top: 6pt; font-size: 13pt; }
  .who { margin-top: 8pt; }
  table { width: 100%; border-collapse: collapse; margin: 8pt 0 4pt; font-size: 13pt; }
  th, td { border: 0.7pt solid #000; padding: 3pt 5pt; vertical-align: top; }
  th { background: #eee; font-weight: 700; }
  td.num, th.num { text-align: right; }
  td.no, th.no { text-align: center; width: 8%; }
  .total-row td { font-weight: 700; }
  .amount-text {
    border: 0.9pt solid #000; padding: 4pt 6pt; text-align: center;
    font-weight: 700; margin-top: 2pt;
  }
  .meta { margin-top: 8pt; font-size: 12.5pt; }
  .note { margin-top: 6pt; font-size: 11.5pt; color: #333; }
  .sign-row { display: flex; justify-content: flex-end; margin-top: 20pt; }
  .sign { text-align: center; min-width: 45%; }
  .sign .line { margin-top: 26pt; border-top: 1pt dotted #000; padding-top: 3pt; }
  @media screen {
    body { background: #f4f4f4; padding: 16px; }
    .sheet { background: #fff; margin: 0 auto; padding: 10mm 12mm;
             max-width: 210mm; box-shadow: 0 1px 6px rgba(0,0,0,.2); }
  }`;

function lineLabel(l: ReceiptLine): string {
  const parts: string[] = [];
  if (l.invoice_no) parts.push(`ใบแจ้งหนี้ ${esc(l.invoice_no)}`);
  if (l.term?.ordinal && l.term?.year_be) {
    parts.push(`ภาคเรียนที่ ${esc(l.term.ordinal)}/${esc(l.term.year_be)}`);
  }
  if (l.seq) parts.push(`งวดที่ ${esc(l.seq)}`);
  if (l.due_on) parts.push(`กำหนดชำระ ${esc(thaiDate(l.due_on))}`);
  return parts.join(' · ');
}

export function renderReceipt(doc: ReceiptDocument): string {
  const d = doc.payload;
  const pay = d.payment ?? {};
  const lines = Array.isArray(d.lines) ? d.lines : [];
  const unallocated = Number(d.unallocated ?? 0);

  const stamps: string[] = [];
  if (doc.voided_at) {
    stamps.push('<div class="stamp void">ยกเลิก</div>');
    stamps.push(
      `<div class="void-note">ใบเสร็จฉบับนี้ถูกยกเลิกเมื่อ ${esc(thaiDate(doc.voided_at))}` +
        `${doc.void_reason ? ` — ${esc(doc.void_reason)}` : ''}</div>`,
    );
  }
  /*
   * สำเนาต้องดูออกจากตัวกระดาษเอง ไม่ใช่จากระบบ — ใบเสร็จที่ถ่ายเอกสาร
   * แล้วดูเหมือนต้นฉบับทุกอย่างคือช่องให้ยื่นเบิกซ้ำได้สองรอบ
   */
  if (doc.copy_no > 1) stamps.push('<div class="stamp copy">สำเนา</div>');

  const rows = lines
    .map(
      (l, i) => `
        <tr>
          <td class="no">${i + 1}</td>
          <td>${lineLabel(l)}</td>
          <td class="num">${money(l.amount)}</td>
        </tr>`,
    )
    .join('');

  /*
   * ชำระเกินต้องขึ้นใบเป็นบรรทัดของตัวเอง — ถ้าไม่พิมพ์ ยอดรวมของรายการ
   * จะน้อยกว่าเงินที่รับจริง แล้วผู้ปกครองจะอ่านว่าจ่ายเกินไปโดยไม่มีใครรับ
   */
  const overRow =
    unallocated > 0
      ? `
        <tr>
          <td class="no">${lines.length + 1}</td>
          <td>ชำระเกิน — ยกไปหักงวดถัดไป</td>
          <td class="num">${money(unallocated)}</td>
        </tr>`
      : '';

  const emptyRow =
    lines.length === 0 && unallocated <= 0
      ? `<tr><td class="no">1</td><td>รับชำระเงิน</td><td class="num">${money(pay.amount)}</td></tr>`
      : '';

  const method = String(pay.method ?? '');
  const methodTh = METHOD_TH[method] ?? method;

  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<title>ใบเสร็จรับเงิน ${esc(doc.doc_no)}</title>
<style>${RECEIPT_STYLE}</style>
</head>
<body>
<div class="sheet">
${stamps.join('\n')}
  <div class="school">${esc(d.institution?.name_th)}</div>
  ${d.institution?.code ? `<div class="code">รหัสสถานศึกษา ${esc(d.institution.code)}</div>` : ''}
  <div class="title">ใบเสร็จรับเงิน</div>

  <div class="doc-line">
    <span>เล่มที่ / เลขที่ <strong>${esc(doc.doc_no)}</strong>${
      doc.copy_no > 1 ? ` (ฉบับที่ ${esc(doc.copy_no)})` : ''
    }</span>
    <span>วันที่ ${esc(thaiDate(pay.received_on ?? doc.issued_on))}</span>
  </div>

  <div class="who">
    ได้รับเงินจาก <strong>${esc(d.student?.full_name)}</strong>
    รหัสนักศึกษา <strong>${esc(d.student?.student_code)}</strong>
  </div>

  <table>
    <thead>
      <tr>
        <th class="no">ที่</th>
        <th>รายการ</th>
        <th class="num" style="width: 22%">จำนวนเงิน (บาท)</th>
      </tr>
    </thead>
    <tbody>
      ${rows}${overRow}${emptyRow}
      <tr class="total-row">
        <td class="no"></td>
        <td style="text-align: right">รวมเป็นเงิน</td>
        <td class="num">${money(pay.amount)}</td>
      </tr>
    </tbody>
  </table>

  <div class="amount-text">(${esc(d.amount_text)})</div>

  <div class="meta">
    ชำระโดย ${esc(methodTh)}${pay.bank_ref ? ` · เลขอ้างอิง ${esc(pay.bank_ref)}` : ''}
    ${pay.note ? `<br>หมายเหตุ ${esc(pay.note)}` : ''}
  </div>

  ${
    NON_CASH.has(method)
      ? `<div class="note">ใบเสร็จนี้จะสมบูรณ์เมื่อสถานศึกษาได้รับเงินตามรายการข้างต้นเรียบร้อยแล้ว</div>`
      : ''
  }

  <div class="sign-row">
    <div class="sign">
      <div class="line">(${esc(d.received_by || '                    ')})</div>
      <div>ผู้รับเงิน</div>
    </div>
  </div>
</div>
</body>
</html>`;
}

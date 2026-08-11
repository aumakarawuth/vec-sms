/**
 * แม่แบบพิมพ์ของหนังสือถึงผู้ปกครองและใบรับรองความประพฤติ (0055)
 *
 * ─── แม่แบบห้ามแตะฐานข้อมูล ───
 * ทุกอย่างที่พิมพ์อ่านจาก `payload` เท่านั้น หลักเดียวกับแม่แบบอีกห้าใบ
 * ถ้าต้องดึงข้อมูลเพิ่มตอนพิมพ์ แปลว่า payload ไม่ครบ ให้แก้
 * `issue_student_letter()` ไม่ใช่แก้ที่นี่ — มิฉะนั้นการพิมพ์ซ้ำใบเดิม
 * ในอีกหกเดือนจะได้กระดาษคนละใบกับที่ผู้ปกครองถืออยู่
 *
 * ─── ทำไมจดหมายสองใบแรกเป็นรูปแบบหนังสือราชการ ไม่ใช่ใบประกาศ ───
 * มันคือหนังสือที่ส่งถึงคนหนึ่งคนโดยเฉพาะ จึงต้องมี "เรียน" ระบุชื่อผู้รับ
 * ที่อยู่สำหรับจ่าหน้าซอง และช่องลงนามของครูที่ปรึกษา — ต่างจากใบรับรอง
 * ที่ออกให้ผู้ถือเอาไปยื่นกับใครก็ได้
 */
import type { IssuedDocument } from './templates';
import { thaiDate } from './templates';

/* ─── ตัวช่วยที่ซ้ำกับ templates.ts แต่ไม่ export ออกมา ────────────── */

function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function pct(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  return `${Number(v).toFixed(1)}%`;
}

const ATT_STATE_TH: Record<string, string> = {
  ok: 'ปกติ',
  warning: 'ใกล้ตกเกณฑ์',
  at_risk: 'เสี่ยงหมดสิทธิ์',
  failed: 'หมดสิทธิ์สอบแล้ว',
};

const PARENT_ROLE_TH: Record<string, string> = { father: 'บิดา', mother: 'มารดา' };

/* ─── รูปแบบของ payload ที่ 0055 สร้าง ─────────────────────────────── */

interface Recipient {
  role: string;
  name_th: string;
  phone: string;
  address_th: string;
}

interface LetterPayload {
  kind: string;
  issued_at: string;
  year_be: number;
  issued_by: string | null;
  note: string;
  institution: { code: string; name_th: string; name_en?: string };
  student: {
    student_code: string;
    full_name_th: string;
    class_number: number | null;
    status: string;
  };
  class: { study_year: number; group_code: string; year_be: number } | null;
  program: { name_th: string; level: string; abbr_th: string } | null;
  advisor: { name_th: string } | null;
  recipients: Recipient[];

  term?: { year_be: number; ordinal: number; label: string } | null;
  courses?: {
    code: string;
    name_th: string;
    section_no: string;
    pct_to_date: string | number;
    pct_projected: string | number;
    absences_left: number;
    min_pct: string | number;
    state: string;
    teacher_th: string;
  }[];
  meeting?: { meet_on: string; meet_time: string; place_th: string; with_th: string };
  reason_th?: string;
  behavior?: { balance: number | null; deduct_count: number; award_count: number };
  purpose_th?: string;
  admitted_on?: number | null;
}

export interface LetterDocument extends Omit<IssuedDocument, 'payload'> {
  payload: LetterPayload;
}

/* ─── ส่วนประกอบร่วม ────────────────────────────────────────────────── */

const LETTER_STYLE = `
  @page { size: A4 portrait; margin: 16mm 18mm; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', 'Tahoma', sans-serif;
    font-size: 16pt; line-height: 1.55; color: #000;
  }
  .sheet { position: relative; }
  .stamp {
    position: fixed; top: 38%; left: 0; right: 0; text-align: center;
    font-size: 90pt; font-weight: 700; letter-spacing: 0.15em;
    transform: rotate(-22deg); pointer-events: none;
  }
  .stamp.void { color: rgba(190, 0, 0, 0.18); }
  .stamp.copy { color: rgba(0, 0, 0, 0.10); }
  .void-note {
    border: 1.5pt solid #b00; color: #b00; padding: 4pt 8pt;
    margin-bottom: 8pt; font-size: 13pt;
  }
  .center { text-align: center; }
  .right { text-align: right; }
  .muted { color: #444; }
  .school { font-size: 21pt; font-weight: 700; text-align: center; }
  .doc-line { display: flex; justify-content: space-between; margin-top: 10pt; font-size: 14pt; }
  .title { font-size: 20pt; font-weight: 700; text-align: center; margin: 14pt 0 6pt; }
  .salute { margin-top: 14pt; }
  .subject { font-weight: 700; }
  p.body-text { text-indent: 2.5em; margin: 8pt 0; }
  table { width: 100%; border-collapse: collapse; margin: 10pt 0; font-size: 14pt; }
  th, td { border: 0.7pt solid #000; padding: 3pt 5pt; }
  th { background: #eee; font-weight: 700; }
  td.num { text-align: right; }
  .sign-row { display: flex; justify-content: flex-end; margin-top: 26pt; }
  .sign { text-align: center; min-width: 45%; }
  .sign .line { margin-top: 34pt; border-top: 1pt dotted #000; padding-top: 3pt; }
  .cut { border-top: 1pt dashed #666; margin-top: 26pt; padding-top: 8pt; font-size: 14pt; }
  .foot { margin-top: 16pt; font-size: 12pt; }
  @media screen {
    body { background: #f4f4f4; padding: 16px; }
    .sheet { background: #fff; margin: 0 auto; padding: 16mm 18mm;
             max-width: 210mm; box-shadow: 0 1px 6px rgba(0,0,0,.2); }
  }`;

function letterPage(title: string, body: string): string {
  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>${LETTER_STYLE}</style>
</head>
<body>
<div class="sheet">
${body}
</div>
</body>
</html>`;
}

function stamps(doc: LetterDocument): string {
  const out: string[] = [];
  if (doc.voided_at) {
    out.push(`<div class="stamp void">ยกเลิก</div>`);
    out.push(
      `<div class="void-note">เอกสารฉบับนี้ถูกยกเลิกเมื่อ ${esc(thaiDate(doc.voided_at))}` +
        ` — ${esc(doc.void_reason ?? '')}</div>`,
    );
  }
  if (Number(doc.copy_no) > 1) out.push(`<div class="stamp copy">สำเนา</div>`);
  return out.join('\n');
}

/** ชั้นปีและห้อง — ประกอบเป็นข้อความเดียวที่คนอ่านจดหมายเข้าใจ */
function classLabel(d: LetterPayload): string {
  if (!d.class) return '—';
  const level = d.program?.abbr_th ?? '';
  const group = d.class.group_code ? ` กลุ่ม ${d.class.group_code}` : '';
  const no = d.student.class_number ? ` เลขที่ ${d.student.class_number}` : '';
  return `${level}${d.class.study_year}${group}${no}`;
}

/**
 * หัวจดหมาย
 *
 * ผู้รับคนแรกขึ้น "เรียน" ส่วนที่เหลือรวมอยู่ในบล็อกที่อยู่ — ถ้าไม่มี
 * ผู้ปกครองในระเบียนเลย ต้องพิมพ์ว่า "ผู้ปกครองของ..." ไม่ใช่เว้นว่าง
 * เพราะจดหมายที่ขึ้นต้นว่า "เรียน" แล้วตามด้วยที่ว่างคือจดหมายที่ส่งไม่ได้
 */
function letterHead(doc: LetterDocument, title: string, subject: string): string {
  const d = doc.payload;
  const first = d.recipients[0];
  const to = first
    ? `${esc(first.name_th)} (${esc(PARENT_ROLE_TH[first.role] ?? first.role)}ของ${esc(d.student.full_name_th)})`
    : `ผู้ปกครองของ${esc(d.student.full_name_th)}`;

  const address = first?.address_th?.trim()
    ? `<div class="muted" style="font-size:14pt">ที่อยู่ ${esc(first.address_th)}` +
      `${first.phone ? ` · โทร. ${esc(first.phone)}` : ''}</div>`
    : `<div class="muted" style="font-size:14pt">— ยังไม่มีที่อยู่ผู้ปกครองในระเบียน กรุณาส่งผ่านนักศึกษา —</div>`;

  return `
${stamps(doc)}
<div class="school">${esc(d.institution.name_th)}</div>
<div class="doc-line">
  <span>ที่ ${esc(doc.doc_no)}</span>
  <span>วันที่ ${esc(thaiDate(doc.issued_on))}</span>
</div>

<div class="title">${esc(title)}</div>

<div class="salute"><span class="subject">เรื่อง</span> ${esc(subject)}</div>
<div><span class="subject">เรียน</span> ${to}</div>
${address}
`;
}

/**
 * ช่องลงนาม
 *
 * ─── ตำแหน่งใต้ลายเซ็นต้องตรงกับคนที่ชื่ออยู่ตรงนั้น ───
 * เดิมเขียนว่า `advisor?.name_th ?? issued_by` แล้วพิมพ์ "ครูที่ปรึกษา"
 * ใต้ชื่อเสมอ ผลคือนักศึกษาที่**ยังไม่ได้มอบหมายที่ปรึกษา** (ซึ่งเป็นสภาพ
 * เริ่มต้นของทุกคน) จะได้จดหมายที่ระบุว่าเจ้าหน้าที่ทะเบียนเป็นครูที่ปรึกษา
 * ของตัวเอง — ข้อความเท็จบนเอกสารที่ส่งถึงบ้านและแก้ไม่ได้อีกเลย
 * เจอตอนอ่านใบที่พิมพ์ออกมาจริง ไม่ใช่ตอนอ่านโค้ด
 */
function signBlock(d: LetterPayload, advisorRole: string): string {
  const hasAdvisor = Boolean(d.advisor?.name_th);
  const name = hasAdvisor ? d.advisor!.name_th : (d.issued_by ?? '');
  const role = hasAdvisor ? advisorRole : 'ผู้ออกหนังสือ';
  return `
<div class="sign-row">
  <div class="sign">
    <div>ขอแสดงความนับถือ</div>
    <div class="line">${esc(name)}</div>
    <div>${esc(role)}</div>
  </div>
</div>`;
}

/* ─── จดหมายแจ้งขาดเรียน ────────────────────────────────────────────── */

export function renderAbsenceNotice(doc: LetterDocument): string {
  const d = doc.payload;
  const courses = d.courses ?? [];

  /*
   * ใบนี้มีท่อนตัดกลับด้านล่างโดยตั้งใจ — โรงเรียนไทยส่งจดหมายกลับบ้าน
   * แล้วให้ผู้ปกครองเซ็นชื่อฉีกส่วนล่างส่งคืน ถ้าไม่มีท่อนนี้ ครูจะไม่มี
   * หลักฐานว่าผู้ปกครองได้รับจริง ซึ่งเป็นสิ่งเดียวที่ยันได้ตอนมีปัญหา
   */
  const rows = courses
    .map(
      (c) => `<tr>
      <td>${esc(c.code)}</td>
      <td>${esc(c.name_th)}</td>
      <td>${esc(c.teacher_th)}</td>
      <td class="num">${esc(pct(c.pct_to_date))}</td>
      <td class="num">${esc(pct(c.pct_projected))}</td>
      <td class="num">${esc(c.absences_left)}</td>
      <td>${esc(ATT_STATE_TH[c.state] ?? c.state)}</td>
    </tr>`,
    )
    .join('\n');

  const worst = courses.reduce(
    (acc, c) => Math.min(acc, Number(c.pct_projected)),
    Number.POSITIVE_INFINITY,
  );
  const minPct = courses[0]?.min_pct ?? 80;

  const body = `
${letterHead(doc, 'หนังสือแจ้งเวลาเรียนไม่ถึงเกณฑ์', 'แจ้งเวลาเรียนของนักศึกษาในความปกครอง')}

<p class="body-text">
  ด้วย${esc(d.institution.name_th)} ได้ตรวจสอบเวลาเรียนของ
  <strong>${esc(d.student.full_name_th)}</strong>
  เลขประจำตัว ${esc(d.student.student_code)} ${esc(classLabel(d))}
  ${d.term ? `ประจำ${esc(d.term.label)}` : ''}
  แล้วพบว่ามีเวลาเรียนไม่ถึงเกณฑ์ร้อยละ ${esc(minPct)} ของเวลาเรียนทั้งหมด
  ในรายวิชาต่อไปนี้
</p>

<table>
  <thead>
    <tr>
      <th style="width:16%">รหัสวิชา</th>
      <th>ชื่อวิชา</th>
      <th style="width:20%">ผู้สอน</th>
      <th style="width:11%">ถึงปัจจุบัน</th>
      <th style="width:11%">คาดการณ์</th>
      <th style="width:9%">ขาดได้อีก</th>
      <th style="width:14%">สถานะ</th>
    </tr>
  </thead>
  <tbody>${rows}</tbody>
</table>

<p class="body-text">
  ตามระเบียบว่าด้วยการวัดผลและประเมินผล นักศึกษาที่มีเวลาเรียนต่ำกว่าเกณฑ์
  จะ<strong>หมดสิทธิ์เข้าสอบปลายภาคในรายวิชานั้น</strong>
  ${Number.isFinite(worst) ? `ขณะนี้วิชาที่ต่ำที่สุดอยู่ที่ ${esc(pct(worst))}` : ''}
  จึงเรียนมาเพื่อขอความร่วมมือท่านกำกับดูแลให้นักศึกษามาเรียนอย่างสม่ำเสมอ
  หากมีเหตุจำเป็นต้องหยุดเรียน กรุณายื่นใบลาต่อสถานศึกษาทุกครั้ง
  ${d.note ? `<br>หมายเหตุ ${esc(d.note)}` : ''}
</p>

${signBlock(d, 'ครูที่ปรึกษา')}

<div class="cut">
  <div class="center subject">ส่วนตอบรับ — กรุณาลงชื่อและส่งคืนสถานศึกษา</div>
  <p style="margin:6pt 0">
    ข้าพเจ้า ..................................................... ผู้ปกครองของ
    ${esc(d.student.full_name_th)} เลขประจำตัว ${esc(d.student.student_code)}
    ได้รับทราบหนังสือที่ ${esc(doc.doc_no)} ลงวันที่ ${esc(thaiDate(doc.issued_on))} แล้ว
  </p>
  <div class="right" style="margin-top:14pt">
    ลงชื่อ ................................................ ผู้ปกครอง
  </div>
</div>

<div class="muted foot">
  เอกสารเลขที่ ${esc(doc.doc_no)} · ออกโดย ${esc(d.issued_by ?? '')}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
  <br>ตัวเลขเวลาเรียนในหนังสือนี้เป็นค่า ณ วันที่ออกเอกสาร
</div>`;

  return letterPage(`หนังสือแจ้งเวลาเรียน ${doc.doc_no}`, body);
}

/* ─── หนังสือเชิญผู้ปกครอง ──────────────────────────────────────────── */

export function renderGuardianInvitation(doc: LetterDocument): string {
  const d = doc.payload;
  const m = d.meeting;

  const body = `
${letterHead(doc, 'หนังสือเชิญผู้ปกครอง', 'ขอเชิญผู้ปกครองมาพบ')}

<p class="body-text">
  ด้วย${esc(d.institution.name_th)} มีความประสงค์จะขอพบท่าน
  เพื่อปรึกษาหารือเกี่ยวกับ<strong>${esc(d.student.full_name_th)}</strong>
  เลขประจำตัว ${esc(d.student.student_code)} ${esc(classLabel(d))}
  ${d.reason_th ? `ในเรื่อง ${esc(d.reason_th)}` : ''}
</p>

<table>
  <tbody>
    <tr><th style="width:26%">วันที่นัดพบ</th><td>${esc(thaiDate(m?.meet_on))}</td></tr>
    <tr><th>เวลา</th><td>${esc(m?.meet_time || 'ตามที่สะดวก กรุณาติดต่อล่วงหน้า')}</td></tr>
    <tr><th>สถานที่</th><td>${esc(m?.place_th || '—')}</td></tr>
    <tr><th>พบกับ</th><td>${esc(m?.with_th || d.advisor?.name_th || '—')}</td></tr>
  </tbody>
</table>

<p class="body-text">
  จึงเรียนมาเพื่อขอความร่วมมือจากท่าน หากไม่สะดวกในวันเวลาดังกล่าว
  กรุณาติดต่อสถานศึกษาเพื่อนัดหมายใหม่
  ${d.note ? `<br>หมายเหตุ ${esc(d.note)}` : ''}
</p>

${signBlock(d, 'ครูที่ปรึกษา')}

<div class="muted foot">
  เอกสารเลขที่ ${esc(doc.doc_no)} · ออกโดย ${esc(d.issued_by ?? '')}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
</div>`;

  return letterPage(`หนังสือเชิญผู้ปกครอง ${doc.doc_no}`, body);
}

/* ─── ใบรับรองความประพฤติ ───────────────────────────────────────────── */

export function renderConductCertificate(doc: LetterDocument): string {
  const d = doc.payload;
  const b = d.behavior;

  /*
   * ใบนี้พูดถึง "ไม่ปรากฏพฤติกรรมเสียหาย" ได้ก็ต่อเมื่อไม่เคยถูกหักคะแนนเลย
   * ถ้าเคยถูกหักแล้วคะแนนกลับมาเต็มเพราะทำกิจกรรมชดเชย ต้องใช้ถ้อยคำที่
   * ไม่โกหก — วิทยาลัยเซ็นชื่อรับรองสิ่งที่เขียนบนใบนี้
   */
  const clean = (b?.deduct_count ?? 0) === 0;
  const conductText = clean
    ? 'เป็นผู้มีความประพฤติเรียบร้อย ไม่ปรากฏประวัติการถูกตัดคะแนนความประพฤติ'
    : `เป็นผู้อยู่ในระเบียบวินัยของสถานศึกษา โดยมีคะแนนความประพฤติคงเหลือ ` +
      `${esc(b?.balance ?? '—')} คะแนน`;

  const body = `
${stamps(doc)}
<div class="school">${esc(d.institution.name_th)}</div>
<div class="doc-line">
  <span>ที่ ${esc(doc.doc_no)}</span>
  <span>วันที่ ${esc(thaiDate(doc.issued_on))}</span>
</div>

<div class="title" style="font-size:24pt;margin-top:18pt">ใบรับรองความประพฤติ</div>

<p class="body-text" style="margin-top:16pt">
  ${esc(d.institution.name_th)} ขอรับรองว่า
</p>
<div class="center" style="font-size:22pt;font-weight:700;margin:8pt 0 2pt">
  ${esc(d.student.full_name_th)}
</div>
<p class="center" style="margin:0 0 12pt">
  เลขประจำตัวนักศึกษา ${esc(d.student.student_code)} ${esc(classLabel(d))}
</p>

<p class="body-text">
  เป็นนักศึกษาของสถานศึกษานี้
  ${d.program ? `ในหลักสูตร${esc(d.program.abbr_th)} สาขาวิชา${esc(d.program.name_th)}` : ''}
  ${d.admitted_on ? `เข้าศึกษาเมื่อปีการศึกษา ${esc(d.admitted_on)}` : ''}
  และ${conductText}
  ${b && (b.award_count ?? 0) > 0
    ? ` ทั้งได้รับการบันทึกความดีความชอบ ${esc(b.award_count)} ครั้ง`
    : ''}
  ${d.purpose_th ? `<br>ใบรับรองนี้ออกให้เพื่อ${esc(d.purpose_th)}` : ''}
</p>

<p style="margin-top:22pt;text-align:right;padding-right:6%">
  ให้ไว้ ณ วันที่ ${esc(thaiDate(doc.issued_on))}
</p>

<div class="sign-row" style="justify-content:space-around">
  <div class="sign"><div class="line">ครูที่ปรึกษา</div></div>
  <div class="sign"><div class="line">ผู้อำนวยการ</div></div>
</div>

<div class="muted foot">
  ใบรับรองฉบับนี้ใช้ได้เฉพาะกิจการที่ระบุไว้ · เอกสารเลขที่ ${esc(doc.doc_no)}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
  <br>ข้อมูลความประพฤติเป็นค่า ณ วันที่ออกเอกสาร
</div>`;

  return letterPage(`ใบรับรองความประพฤติ ${doc.doc_no}`, body);
}

/** ประเภทที่ไฟล์นี้พิมพ์ได้ — ตัวส่งต่อใน templates.ts ใช้ตรวจก่อนเรียก */
export const LETTER_KINDS = [
  'absence_notice',
  'guardian_invitation',
  'conduct_certificate',
] as const;

export function renderLetter(doc: LetterDocument): string {
  switch (doc.kind) {
    case 'absence_notice':
      return renderAbsenceNotice(doc);
    case 'guardian_invitation':
      return renderGuardianInvitation(doc);
    case 'conduct_certificate':
      return renderConductCertificate(doc);
    default:
      throw new Error(`ยังไม่มีแม่แบบพิมพ์สำหรับเอกสารประเภท ${doc.kind}`);
  }
}

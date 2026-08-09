/**
 * แม่แบบพิมพ์เอกสารของงานทะเบียน
 *
 * ─── ทำไมเรนเดอร์ที่เซิร์ฟเวอร์ ไม่ใช่ที่แอป ───
 * เอกสารพวกนี้เป็นกระดาษทางราชการที่มีเลขที่ติดตัว ถ้าให้แต่ละช่องทาง
 * (เว็บ แอป สคริปต์ออกใบย้อนหลัง) วาดเอง วันหนึ่งจะได้ใบที่หน้าตาไม่ตรงกัน
 * จากเลขที่เดียวกัน — ที่นี่จึงเป็นทางเดียวที่แปลง payload เป็นกระดาษ
 *
 * ─── ทำไมไม่ใช้ template engine ───
 * ทั้งไฟล์นี้ต้องการแค่การแทนค่าและวนลูป การเพิ่ม dependency เพื่อสิ่งนี้
 * แลกมาด้วยการต้องตามอัปเกรดมันไปตลอดอายุระบบ (หลักเดียวกับที่ใช้ scrypt
 * ที่มากับ Node แทน bcrypt และเขียน security headers เอง)
 *
 * ─── ทำไมห้ามอ้างอิงไฟล์ภายนอกเลย ───
 * ไม่มี CDN ไม่มีฟอนต์จากเน็ต ไม่มีรูปจาก URL — เพราะวันที่งานทะเบียนต้อง
 * พิมพ์ใบให้นักศึกษาที่มายืนรออยู่ตรงหน้า แล้วอินเทอร์เน็ตวิทยาลัยล่ม
 * เอกสารต้องยังออกได้ ฟอนต์จึงใช้ที่มีอยู่ในเครื่องเท่านั้น
 *
 * ─── ทุกอย่างที่พิมพ์มาจาก payload เท่านั้น ───
 * ไฟล์นี้ห้ามแตะฐานข้อมูล ถ้าวันหนึ่งพบว่าต้องดึงข้อมูลเพิ่มตอนพิมพ์
 * แปลว่า payload ยังไม่ครบ ให้ไปแก้ issue_document() ไม่ใช่แก้ที่นี่
 * (มิฉะนั้นใบที่พิมพ์ซ้ำปีหน้าจะไม่ตรงกับใบเดิม)
 */

/** เอกสารหนึ่งใบตามที่อ่านมาจาก issued_document */
export interface IssuedDocument {
  id: string;
  kind: string;
  doc_no: string;
  copy_no: number;
  issued_on: string;
  voided_at: string | null;
  void_reason: string | null;
  payload: DocumentPayload;
}

export interface DocumentPayload {
  kind: string;
  year_be?: number;
  institution: { code: string; name_th: string; name_en?: string };
  student: {
    student_code: string;
    full_name_th: string;
    birth_date: string | null;
    admitted_year_be: number | null;
    status: string;
  };
  program: {
    type_th: string;
    name_th: string;
    track_th: string;
    curriculum_th: string;
    shift: string;
    level: string;
    edition_be: number;
    qualification_th: string;
    qualification_abbr_th: string;
  } | null;
  graduation: {
    completed_on: string;
    transcript_no: string | null;
    certificate_no: string | null;
    professional_standard_no: string | null;
  } | null;
  summary: { credits_earned: number | string; gpax: number | string | null; source: string };
  term_summaries: Array<{
    year_be: number; ordinal: number; label: string;
    gpa: number | string | null; gpax: number | string | null;
    credits_earned: number | string | null;
  }>;
  courses: Array<{
    year_be: number; term_ordinal: number; term_label: string;
    course_code: string; course_name_th: string;
    credits: number | string; grade_symbol: string;
    grade_point: number | string | null; credits_earned: number | string | null;
    category_th: string | null;
  }>;

  // ── เฉพาะสมุดพก ──
  term?: {
    year_be: number; ordinal: number; label: string;
    gpa: number | string | null; gpax: number | string | null;
    credits_earned: number | string | null;
  } | null;
  term_courses?: Array<{
    course_code: string; course_name_th: string; credits: number | string;
    grade_symbol: string | null; attendance_pct: number | string | null;
    attendance_state: string | null; absences_left: number | null;
  }>;
  activities?: Array<{
    activity_name: string; sessions_required: number | null;
    sessions_attended: number | null; result: string | null;
  }>;

  // ── สมุดพกและระเบียนสะสม ──
  behavior?: {
    starting_points: number; deducted: number; awarded: number;
    current: number; warn_below: number; critical_below: number;
  } | null;

  // ── เฉพาะระเบียนสะสม (ปพ.8) ──
  guardians?: Array<{
    relation: string; full_name: string; phone: string; is_primary: boolean;
  }>;
  screenings?: Array<{ instrument: string; assessed_on: string; band: string }>;
  behavior_history?: Array<{
    occurred_on: string; points: number; direction: string | null;
    rule_th: string; document_no: string;
  }>;
  activities_all?: Array<{ activity_name: string; result: string; term_label: string }>;
  home_visits?: { count: number | string; last_visited_on: string | null } | null;
}

const MONTHS_TH = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

const SHIFT_TH: Record<string, string> = {
  morning: 'รอบเช้า',
  afternoon: 'รอบบ่าย',
  evening: 'รอบค่ำ',
  weekend: 'รอบวันหยุด',
};

const ATTENDANCE_STATE_TH: Record<string, string> = {
  ok: 'ปกติ',
  warning: 'เฝ้าระวัง',
  failed: 'ไม่ผ่านเกณฑ์',
};

const RELATION_TH: Record<string, string> = {
  father: 'บิดา',
  mother: 'มารดา',
  guardian: 'ผู้ปกครอง',
  relative: 'ญาติ',
  other: 'อื่น ๆ',
};

const RESULT_TH: Record<string, string> = {
  pass: 'ผ่าน',
  fail: 'ไม่ผ่าน',
  absent: 'ขาดสอบ',
  pending: 'รอผล',
};

/**
 * ระดับผลการคัดกรองเป็นข้อความไทย
 *
 * ใช้ถ้อยคำกลาง ๆ โดยตั้งใจ เพราะกระดาษใบนี้ถูกส่งต่อระหว่างครูที่ปรึกษา
 * และบางครั้งถึงมือผู้ปกครอง คำที่ตีตราเด็กจะติดตัวไปนานกว่าตัวปัญหาเอง
 */
const SCREENING_BAND_TH: Record<string, string> = {
  normal: 'ปกติ',
  at_risk: 'กลุ่มเสี่ยง',
  has_problem: 'ต้องดูแลใกล้ชิด',
  special_needs: 'ต้องการการดูแลเฉพาะทาง',
};

/**
 * ชื่อ-สกุลของคนจริงอาจมีอักขระที่ทำให้ HTML เพี้ยนได้ และหน้านี้เปิดใน
 * เบราว์เซอร์ของเจ้าหน้าที่ จึง escape ทุกค่าที่มาจากข้อมูลโดยไม่มีข้อยกเว้น
 */
function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** วันที่แบบไทยเต็ม เช่น 31 มีนาคม 2569 — ปีพุทธศักราชเสมอตามระเบียบเอกสาร */
export function thaiDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso));
  if (!m) return String(iso);
  const [, y, mo, d] = m;
  const month = MONTHS_TH[Number(mo) - 1] ?? '';
  return `${Number(d)} ${month} ${Number(y) + 543}`;
}

function num(v: unknown, digits = 2): string {
  if (v === null || v === undefined || v === '') return '—';
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(digits) : String(v);
}

/**
 * ตราประทับบอกสถานะของใบ
 *
 * ใบที่ยกเลิกแล้วยังพิมพ์ได้โดยตั้งใจ เพราะบางครั้งต้องพิมพ์มาแนบเรื่อง
 * ว่าใบไหนถูกยกเลิก แต่ต้องมองปราดเดียวรู้ ไม่ใช่ต้องอ่านตัวเล็ก ๆ ที่มุมกระดาษ
 */
function stamps(doc: IssuedDocument): string {
  const out: string[] = [];
  if (doc.voided_at) {
    out.push(`<div class="stamp void">ยกเลิก</div>`);
    out.push(
      `<div class="void-note">เอกสารฉบับนี้ถูกยกเลิกเมื่อ ${esc(thaiDate(doc.voided_at))}` +
        ` — ${esc(doc.void_reason ?? '')}</div>`,
    );
  }
  if (Number(doc.copy_no) > 1) {
    out.push(`<div class="stamp copy">สำเนา</div>`);
  }
  return out.join('\n');
}

function baseStyle(orientation: 'portrait' | 'landscape'): string {
  return `
  @page { size: A4 ${orientation}; margin: ${orientation === 'portrait' ? '14mm 15mm' : '12mm'}; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    /* ฟอนต์ในเครื่องเท่านั้น — TH Sarabun New เป็นฟอนต์มาตรฐานราชการไทย
       ที่เครื่องงานทะเบียนมีอยู่แล้ว ที่เหลือเป็นตัวสำรองตามลำดับ */
    font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', 'Tahoma', sans-serif;
    font-size: 15pt;
    line-height: 1.45;
    color: #000;
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
  .right  { text-align: right; }
  .muted  { color: #444; }
  .doc-no { font-size: 13pt; }
  table { width: 100%; border-collapse: collapse; }
  .sign-row { display: flex; justify-content: space-around; margin-top: 22pt; }
  .sign { text-align: center; min-width: 45%; }
  .sign .line { margin-top: 30pt; border-top: 1pt dotted #000; padding-top: 3pt; }
  @media screen {
    body { background: #f4f4f4; padding: 16px; }
    .sheet { background: #fff; margin: 0 auto; padding: 14mm 15mm;
             max-width: ${orientation === 'portrait' ? '210mm' : '297mm'};
             box-shadow: 0 1px 6px rgba(0,0,0,.2); }
  }`;
}

function page(title: string, orientation: 'portrait' | 'landscape', body: string): string {
  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>${baseStyle(orientation)}</style>
</head>
<body>
<div class="sheet">
${body}
</div>
</body>
</html>`;
}

// ── ระเบียนแสดงผลการเรียน (รบ.) ─────────────────────────────────────
export function renderTranscript(doc: IssuedDocument): string {
  const d = doc.payload;
  const prog = d.program;
  const grad = d.graduation;

  // จัดกลุ่มรายวิชาตามภาคเรียน — payload เรียงมาแล้วตามปีและภาค
  const groups = new Map<string, typeof d.courses>();
  for (const c of d.courses ?? []) {
    const key = c.term_label;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(c);
  }

  const gpaOf = (label: string) =>
    (d.term_summaries ?? []).find((t) => t.label === label);

  const termBlocks = [...groups.entries()]
    .map(([label, rows]) => {
      const ts = gpaOf(label);
      const body = rows
        .map(
          (c) => `      <tr>
        <td>${esc(c.course_code)}</td>
        <td>${esc(c.course_name_th)}</td>
        <td class="center">${num(c.credits, 1)}</td>
        <td class="center">${esc(c.grade_symbol)}</td>
      </tr>`,
        )
        .join('\n');

      return `  <div class="term">
    <div class="term-head">${esc(label)}</div>
    <table class="courses">
      <thead>
        <tr><th style="width:18%">รหัสวิชา</th><th>ชื่อวิชา</th>
            <th style="width:12%">หน่วยกิต</th><th style="width:16%">ผลการเรียน</th></tr>
      </thead>
      <tbody>
${body}
      </tbody>
    </table>
    <div class="right term-foot">
      หน่วยกิตที่ได้ ${num(ts?.credits_earned, 1)} ·
      ผลการเรียนเฉลี่ยประจำภาค ${num(ts?.gpa)}
    </div>
  </div>`;
    })
    .join('\n');

  const noCourses = `<p class="center muted">— ยังไม่มีรายวิชาที่ประเมินผลแล้ว —</p>`;

  const body = `
${stamps(doc)}
<div class="right doc-no">เลขที่ ${esc(grad?.transcript_no || doc.doc_no)}</div>

<div class="center head">
  <div class="title">ระเบียนแสดงผลการเรียน</div>
  <div class="subtitle">ตามหลักสูตร${esc(prog?.qualification_th ?? '')} พุทธศักราช ${esc(prog?.edition_be ?? '')}</div>
  <div class="school">${esc(d.institution.name_th)}</div>
  <div class="muted school-code">รหัสสถานศึกษา ${esc(d.institution.code)}</div>
</div>

<table class="facts">
  <tr>
    <td class="k">ชื่อ-สกุล</td><td class="v">${esc(d.student.full_name_th)}</td>
    <td class="k">เลขประจำตัวนักศึกษา</td><td class="v">${esc(d.student.student_code)}</td>
  </tr>
  <tr>
    <td class="k">วันเกิด</td><td class="v">${esc(thaiDate(d.student.birth_date))}</td>
    <td class="k">ปีที่เข้าศึกษา</td><td class="v">${esc(d.student.admitted_year_be ?? '—')}</td>
  </tr>
  <tr>
    <td class="k">ประเภทวิชา</td><td class="v">${esc(prog?.type_th ?? '—')}</td>
    <td class="k">สาขาวิชา</td><td class="v">${esc(prog?.name_th ?? '—')}</td>
  </tr>
  <tr>
    <td class="k">สาขางาน</td><td class="v">${esc(prog?.track_th ?? '—')}</td>
    <td class="k">รอบเรียน</td><td class="v">${esc(SHIFT_TH[prog?.shift ?? ''] ?? '—')}</td>
  </tr>
</table>

${termBlocks || noCourses}

<table class="summary">
  <tr>
    <td class="k">หน่วยกิตสะสม</td><td class="v">${num(d.summary?.credits_earned, 1)}</td>
    <td class="k">ผลการเรียนเฉลี่ยสะสม</td><td class="v">${num(d.summary?.gpax)}</td>
  </tr>
  <tr>
    <td class="k">วันที่สำเร็จการศึกษา</td><td class="v">${esc(thaiDate(grad?.completed_on))}</td>
    <td class="k">เลขที่มาตรฐานวิชาชีพ</td><td class="v">${esc(grad?.professional_standard_no || '—')}</td>
  </tr>
</table>

<div class="sign-row">
  <div class="sign"><div class="line">นายทะเบียน</div></div>
  <div class="sign"><div class="line">ผู้อำนวยการ</div></div>
</div>

<div class="muted foot">
  ออกให้เมื่อ ${esc(thaiDate(doc.issued_on))} · เอกสารเลขที่ ${esc(doc.doc_no)}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
</div>

<style>
  .head { margin-bottom: 10pt; }
  .title { font-size: 24pt; font-weight: 700; }
  .subtitle { font-size: 15pt; }
  .school { font-size: 18pt; margin-top: 4pt; }
  .school-code { font-size: 13pt; }
  .facts, .summary { margin: 8pt 0 12pt; font-size: 14pt; }
  .facts td, .summary td { padding: 2pt 4pt; vertical-align: top; }
  .facts .k, .summary .k { white-space: nowrap; color: #333; width: 15%; }
  .facts .v, .summary .v { border-bottom: 0.5pt dotted #999; }
  .summary { border-top: 1pt solid #000; padding-top: 6pt; }
  .term { margin-bottom: 10pt; break-inside: avoid; }
  .term-head { font-weight: 700; margin-bottom: 3pt; }
  .courses th, .courses td { border: 0.5pt solid #666; padding: 2pt 5pt; font-size: 14pt; }
  .courses th { background: #eee; font-weight: 600; }
  .term-foot { font-size: 13pt; margin-top: 2pt; }
  .foot { margin-top: 14pt; font-size: 12pt; }
</style>`;

  return page(`ระเบียนแสดงผลการเรียน ${doc.doc_no}`, 'portrait', body);
}

// ── ใบประกาศนียบัตร ─────────────────────────────────────────────────
export function renderCertificate(doc: IssuedDocument): string {
  const d = doc.payload;
  const prog = d.program;
  const grad = d.graduation;

  // เลขที่พิมพ์ที่มุมบนขวาตามที่ระเบียบกำหนดตำแหน่งไว้
  const body = `
${stamps(doc)}
<div class="right cert-no">เลขที่ ${esc(grad?.certificate_no || doc.doc_no)}</div>

<div class="center cert">
  <div class="school">${esc(d.institution.name_th)}</div>
  <div class="kind">${esc(prog?.qualification_th ?? 'ประกาศนียบัตร')}</div>

  <p class="lead">ประกาศนียบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า</p>
  <div class="name">${esc(d.student.full_name_th)}</div>

  <p class="body-text">
    ได้สำเร็จการศึกษาตามหลักสูตร${esc(prog?.qualification_th ?? '')}
    พุทธศักราช ${esc(prog?.edition_be ?? '')}<br>
    ประเภทวิชา${esc(prog?.type_th ?? '')}
    สาขาวิชา${esc(prog?.name_th ?? '')}
    สาขางาน${esc(prog?.track_th ?? '')}
  </p>

  <p class="given">ให้ไว้ ณ วันที่ ${esc(thaiDate(grad?.completed_on))}</p>

  <div class="sign-row">
    <div class="sign"><div class="line">ผู้อำนวยการ</div></div>
  </div>
</div>

<div class="muted foot center">
  เอกสารเลขที่ ${esc(doc.doc_no)} · ออกให้เมื่อ ${esc(thaiDate(doc.issued_on))}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
</div>

<style>
  .cert-no { font-size: 14pt; }
  .cert { padding-top: 6mm; }
  .school { font-size: 26pt; font-weight: 700; }
  .kind { font-size: 34pt; font-weight: 700; margin: 8pt 0 14pt; letter-spacing: 0.04em; }
  .lead { font-size: 17pt; margin: 0 0 6pt; }
  .name { font-size: 30pt; font-weight: 700; margin: 6pt 0 12pt;
          border-bottom: 0.5pt dotted #666; display: inline-block; padding: 0 30pt 4pt; }
  .body-text { font-size: 17pt; margin: 6pt 0 16pt; line-height: 1.7; }
  .given { font-size: 17pt; margin-top: 10pt; }
  .sign-row { justify-content: center; }
  .foot { margin-top: 10pt; font-size: 12pt; }
</style>`;

  return page(`ใบประกาศนียบัตร ${doc.doc_no}`, 'landscape', body);
}

// ── ใบรับรอง ────────────────────────────────────────────────────────
export function renderCertification(doc: IssuedDocument): string {
  const d = doc.payload;
  const prog = d.program;
  const grad = d.graduation;

  /*
   * ใบรับรองมีสองแบบที่ใช้คนละถ้อยคำ และแยกจากกันด้วยสถานะของนักศึกษา
   * ณ เวลาที่ออกใบ ซึ่งตรึงอยู่ใน payload แล้ว — ไม่ใช่สถานะปัจจุบัน
   * คนที่ลาออกไปแล้ววันนี้ ยังต้องได้ใบที่รับรองตามความจริงของวันที่ออก
   */
  const graduated = d.student.status === 'graduated' && grad;

  const bodyText = graduated
    ? `สำเร็จการศึกษาตามหลักสูตร${esc(prog?.qualification_th ?? '')}
       พุทธศักราช ${esc(prog?.edition_be ?? '')}
       ประเภทวิชา${esc(prog?.type_th ?? '')} สาขาวิชา${esc(prog?.name_th ?? '')}
       สาขางาน${esc(prog?.track_th ?? '')}
       เมื่อวันที่ ${esc(thaiDate(grad?.completed_on))}`
    : `กำลังศึกษาอยู่ในหลักสูตร${esc(prog?.qualification_th ?? '')}
       พุทธศักราช ${esc(prog?.edition_be ?? '')}
       ประเภทวิชา${esc(prog?.type_th ?? '')} สาขาวิชา${esc(prog?.name_th ?? '')}
       สาขางาน${esc(prog?.track_th ?? '')} ${esc(SHIFT_TH[prog?.shift ?? ''] ?? '')}
       ของสถานศึกษานี้จริง`;

  const body = `
${stamps(doc)}
<div class="right doc-no">เลขที่ ${esc(doc.doc_no)}</div>

<div class="center head">
  <div class="school">${esc(d.institution.name_th)}</div>
  <div class="title">หนังสือรับรอง</div>
</div>

<p class="lead">หนังสือฉบับนี้ให้ไว้เพื่อรับรองว่า</p>
<div class="center name">${esc(d.student.full_name_th)}</div>
<p class="center sub">เลขประจำตัวนักศึกษา ${esc(d.student.student_code)}</p>

<p class="body-text">${bodyText}</p>

<p class="given">ให้ไว้ ณ วันที่ ${esc(thaiDate(doc.issued_on))}</p>

<div class="sign-row">
  <div class="sign"><div class="line">นายทะเบียน</div></div>
  <div class="sign"><div class="line">ผู้อำนวยการ</div></div>
</div>

<div class="muted foot">
  หนังสือรับรองฉบับนี้ใช้ได้เฉพาะกิจการที่ผู้ขอระบุไว้ · เอกสารเลขที่ ${esc(doc.doc_no)}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
</div>

<style>
  .head { margin-bottom: 16pt; }
  .school { font-size: 22pt; font-weight: 700; }
  .title { font-size: 28pt; font-weight: 700; margin-top: 6pt; letter-spacing: 0.05em; }
  .lead { font-size: 17pt; text-indent: 2.5em; margin-bottom: 4pt; }
  .name { font-size: 24pt; font-weight: 700; margin: 8pt 0 2pt; }
  .sub { font-size: 15pt; margin: 0 0 12pt; }
  .body-text { font-size: 17pt; line-height: 1.9; text-indent: 2.5em; }
  .given { font-size: 17pt; margin-top: 20pt; text-align: right; padding-right: 8%; }
  .foot { margin-top: 18pt; font-size: 12pt; }
</style>`;

  return page(`หนังสือรับรอง ${doc.doc_no}`, 'portrait', body);
}

// ── สมุดพก (ใบแจ้งผลการเรียนรายภาค) ─────────────────────────────────
export function renderGradeReport(doc: IssuedDocument): string {
  const d = doc.payload;
  const prog = d.program;
  const term = d.term;
  const bh = d.behavior;

  const rows = (d.term_courses ?? [])
    .map(
      (c) => `      <tr>
        <td>${esc(c.course_code)}</td>
        <td>${esc(c.course_name_th)}</td>
        <td class="center">${num(c.credits, 1)}</td>
        <td class="center">${esc(c.grade_symbol ?? '—')}</td>
        <td class="center">${c.attendance_pct === null || c.attendance_pct === undefined
          ? '—' : num(c.attendance_pct, 1) + '%'}</td>
        <td class="center">${esc(ATTENDANCE_STATE_TH[c.attendance_state ?? ''] ?? '—')}</td>
      </tr>`,
    )
    .join('\n');

  const activities = (d.activities ?? [])
    .map(
      (a) => `<li>${esc(a.activity_name)} — เข้าร่วม ${esc(a.sessions_attended ?? 0)}/${esc(
        a.sessions_required ?? 0,
      )} ครั้ง · ${esc(RESULT_TH[a.result ?? ''] ?? a.result ?? '—')}</li>`,
    )
    .join('\n');

  // เตือนเรื่องความประพฤติเฉพาะเมื่อต่ำกว่าเกณฑ์จริง ไม่ใช่แปะไว้ทุกใบ
  const behaviorWarn =
    bh && Number(bh.current) < Number(bh.warn_below)
      ? `<div class="warn">คะแนนความประพฤติต่ำกว่าเกณฑ์เฝ้าระวัง (${esc(bh.warn_below)} คะแนน)
         — ขอความร่วมมือผู้ปกครองติดต่อครูที่ปรึกษา</div>`
      : '';

  const body = `
${stamps(doc)}
<div class="right doc-no">เลขที่ ${esc(doc.doc_no)}</div>

<div class="center head">
  <div class="title">ใบแจ้งผลการเรียน</div>
  <div class="school">${esc(d.institution.name_th)}</div>
  <div class="term-label">${esc(term?.label ?? '—')}</div>
</div>

<table class="facts">
  <tr>
    <td class="k">ชื่อ-สกุล</td><td class="v">${esc(d.student.full_name_th)}</td>
    <td class="k">เลขประจำตัว</td><td class="v">${esc(d.student.student_code)}</td>
  </tr>
  <tr>
    <td class="k">สาขาวิชา</td><td class="v">${esc(prog?.name_th ?? '—')}</td>
    <td class="k">สาขางาน</td><td class="v">${esc(prog?.track_th ?? '—')}</td>
  </tr>
</table>

<table class="courses">
  <thead>
    <tr><th style="width:15%">รหัสวิชา</th><th>ชื่อวิชา</th>
        <th style="width:9%">นก.</th><th style="width:12%">ผลการเรียน</th>
        <th style="width:12%">เวลาเรียน</th><th style="width:14%">สถานะเวลาเรียน</th></tr>
  </thead>
  <tbody>
${rows || '<tr><td colspan="6" class="center muted">— ไม่มีรายวิชาที่ลงทะเบียนในภาคเรียนนี้ —</td></tr>'}
  </tbody>
</table>

<table class="summary">
  <tr>
    <td class="k">ผลการเรียนเฉลี่ยประจำภาค</td><td class="v">${num(term?.gpa)}</td>
    <td class="k">ผลการเรียนเฉลี่ยสะสม</td><td class="v">${num(term?.gpax ?? d.summary?.gpax)}</td>
  </tr>
  <tr>
    <td class="k">หน่วยกิตที่ได้ประจำภาค</td><td class="v">${num(term?.credits_earned, 1)}</td>
    <td class="k">คะแนนความประพฤติคงเหลือ</td>
    <td class="v">${bh ? `${esc(bh.current)} จาก ${esc(bh.starting_points)}` : '—'}</td>
  </tr>
</table>

${behaviorWarn}

${activities ? `<div class="block"><div class="block-head">กิจกรรมเสริมหลักสูตร</div><ul>${activities}</ul></div>` : ''}

<div class="sign-row">
  <div class="sign"><div class="line">ครูที่ปรึกษา</div></div>
  <div class="sign"><div class="line">ลงชื่อผู้ปกครอง</div></div>
</div>

<div class="muted foot">
  ออกให้เมื่อ ${esc(thaiDate(doc.issued_on))} · เอกสารเลขที่ ${esc(doc.doc_no)}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
</div>

<style>
  .head { margin-bottom: 10pt; }
  .title { font-size: 24pt; font-weight: 700; }
  .school { font-size: 17pt; }
  .term-label { font-size: 16pt; margin-top: 2pt; }
  .facts, .summary { margin: 8pt 0; font-size: 14pt; }
  .facts td, .summary td { padding: 2pt 4pt; }
  .facts .k, .summary .k { white-space: nowrap; color: #333; width: 18%; }
  .facts .v, .summary .v { border-bottom: 0.5pt dotted #999; }
  .summary { border-top: 1pt solid #000; padding-top: 6pt; }
  .courses th, .courses td { border: 0.5pt solid #666; padding: 3pt 5pt; font-size: 14pt; }
  .courses th { background: #eee; font-weight: 600; }
  .warn { border: 1pt solid #a60; background: #fff8e8; padding: 5pt 8pt;
          font-size: 14pt; margin: 8pt 0; }
  .block { margin-top: 10pt; }
  .block-head { font-weight: 700; margin-bottom: 2pt; }
  .block ul { margin: 0; padding-left: 20pt; font-size: 14pt; }
  .foot { margin-top: 14pt; font-size: 12pt; }
</style>`;

  return page(`ใบแจ้งผลการเรียน ${doc.doc_no}`, 'portrait', body);
}

// ── ระเบียนสะสม (ปพ.8) ──────────────────────────────────────────────
export function renderCumulativeRecord(doc: IssuedDocument): string {
  const d = doc.payload;
  const prog = d.program;
  const bh = d.behavior;

  const guardians = (d.guardians ?? [])
    .map(
      (g) => `      <tr>
        <td>${esc(RELATION_TH[g.relation] ?? g.relation)}${g.is_primary ? ' (หลัก)' : ''}</td>
        <td>${esc(g.full_name)}</td>
        <td>${esc(g.phone || '—')}</td>
      </tr>`,
    )
    .join('\n');

  const terms = (d.term_summaries ?? [])
    .map(
      (t) => `      <tr>
        <td>${esc(t.label)}</td>
        <td class="center">${num(t.credits_earned, 1)}</td>
        <td class="center">${num(t.gpa)}</td>
        <td class="center">${num(t.gpax)}</td>
      </tr>`,
    )
    .join('\n');

  // เครื่องหมายมาจาก direction ไม่ใช่จากค่าของ points ซึ่งเป็นบวกเสมอ
  const behaviorRows = (d.behavior_history ?? [])
    .map((b) => {
      const deduct = b.direction === 'deduct';
      return `      <tr>
        <td>${esc(thaiDate(b.occurred_on))}</td>
        <td>${esc(b.rule_th || '—')}</td>
        <td class="center ${deduct ? 'minus' : 'plus'}">${deduct ? '−' : '+'}${esc(
          Math.abs(Number(b.points)),
        )}</td>
        <td>${esc(b.document_no || '—')}</td>
      </tr>`;
    })
    .join('\n');

  const screenings = (d.screenings ?? [])
    .map(
      (s) => `      <tr>
        <td>${esc(s.instrument)}</td>
        <td>${esc(thaiDate(s.assessed_on))}</td>
        <td>${esc(SCREENING_BAND_TH[s.band] ?? s.band)}</td>
      </tr>`,
    )
    .join('\n');

  const activities = (d.activities_all ?? [])
    .map(
      (a) =>
        `<li>${esc(a.term_label)} — ${esc(a.activity_name)} · ${esc(
          RESULT_TH[a.result] ?? a.result,
        )}</li>`,
    )
    .join('\n');

  const hv = d.home_visits;

  const section = (title: string, inner: string) =>
    `<div class="block"><div class="block-head">${esc(title)}</div>${inner}</div>`;

  const empty = (what: string) => `<p class="muted small">— ไม่มี${esc(what)} —</p>`;

  const body = `
${stamps(doc)}
<div class="right doc-no">เลขที่ ${esc(doc.doc_no)}</div>

<div class="center head">
  <div class="title">ระเบียนสะสม</div>
  <div class="school">${esc(d.institution.name_th)}</div>
  <div class="muted school-code">รหัสสถานศึกษา ${esc(d.institution.code)}</div>
</div>

<table class="facts">
  <tr>
    <td class="k">ชื่อ-สกุล</td><td class="v">${esc(d.student.full_name_th)}</td>
    <td class="k">เลขประจำตัว</td><td class="v">${esc(d.student.student_code)}</td>
  </tr>
  <tr>
    <td class="k">วันเกิด</td><td class="v">${esc(thaiDate(d.student.birth_date))}</td>
    <td class="k">ปีที่เข้าศึกษา</td><td class="v">${esc(d.student.admitted_year_be ?? '—')}</td>
  </tr>
  <tr>
    <td class="k">สาขาวิชา</td><td class="v">${esc(prog?.name_th ?? '—')}</td>
    <td class="k">สาขางาน</td><td class="v">${esc(prog?.track_th ?? '—')}</td>
  </tr>
</table>

${section(
  'ผู้ปกครอง',
  guardians
    ? `<table class="grid"><thead><tr><th style="width:22%">ความเกี่ยวข้อง</th><th>ชื่อ-สกุล</th><th style="width:24%">โทรศัพท์</th></tr></thead><tbody>
${guardians}
</tbody></table>`
    : empty('ผู้ปกครองที่ยืนยันตัวตนแล้ว'),
)}

${section(
  'ผลการเรียนรายภาค',
  terms
    ? `<table class="grid"><thead><tr><th>ภาคเรียน</th><th style="width:16%">หน่วยกิตที่ได้</th><th style="width:14%">ผลการเรียนเฉลี่ย</th><th style="width:14%">เฉลี่ยสะสม</th></tr></thead><tbody>
${terms}
</tbody></table>
<div class="right small">รวมหน่วยกิตสะสม ${num(d.summary?.credits_earned, 1)} · เฉลี่ยสะสม ${num(d.summary?.gpax)}</div>`
    : empty('ผลการเรียนที่ประมวลแล้ว'),
)}

${section(
  'ความประพฤติ',
  `${bh ? `<p class="small">คะแนนตั้งต้น ${esc(bh.starting_points)} · เพิ่ม ${esc(bh.awarded)} · หัก ${esc(Math.abs(Number(bh.deducted)))} · <strong>คงเหลือ ${esc(bh.current)}</strong></p>` : ''}
${
  behaviorRows
    ? `<table class="grid"><thead><tr><th style="width:20%">วันที่</th><th>รายการ</th><th style="width:12%">คะแนน</th><th style="width:20%">เลขที่หนังสือ</th></tr></thead><tbody>
${behaviorRows}
</tbody></table>`
    : empty('บันทึกพฤติกรรม')
}`,
)}

${section('กิจกรรมเสริมหลักสูตร', activities ? `<ul>${activities}</ul>` : empty('บันทึกกิจกรรม'))}

${section(
  'การคัดกรองและการดูแลช่วยเหลือ',
  `${
    screenings
      ? `<table class="grid"><thead><tr><th style="width:34%">เครื่องมือ</th><th style="width:26%">วันที่ประเมิน</th><th>ผลการคัดกรอง</th></tr></thead><tbody>
${screenings}
</tbody></table>`
      : empty('ผลการคัดกรอง')
  }
<p class="small">การเยี่ยมบ้าน ${esc(hv?.count ?? 0)} ครั้ง${
    hv?.last_visited_on ? ` · ครั้งล่าสุด ${esc(thaiDate(hv.last_visited_on))}` : ''
  }</p>
<p class="muted small note">
  ระเบียนนี้บันทึกเฉพาะระดับผลและวันที่ รายละเอียดของแบบคัดกรองและข้อค้นพบ
  จากการเยี่ยมบ้านอยู่ในระบบ เปิดดูได้เฉพาะผู้มีสิทธิ์ตามหน้าที่
</p>`,
)}

<div class="sign-row">
  <div class="sign"><div class="line">ครูที่ปรึกษา</div></div>
  <div class="sign"><div class="line">นายทะเบียน</div></div>
</div>

<div class="muted foot">
  ออกให้เมื่อ ${esc(thaiDate(doc.issued_on))} · เอกสารเลขที่ ${esc(doc.doc_no)}
  ${Number(doc.copy_no) > 1 ? `· ฉบับที่ ${esc(doc.copy_no)}` : ''}
</div>

<style>
  .head { margin-bottom: 10pt; }
  .title { font-size: 24pt; font-weight: 700; }
  .school { font-size: 17pt; }
  .school-code { font-size: 13pt; }
  .facts { margin: 8pt 0 12pt; font-size: 14pt; }
  .facts td { padding: 2pt 4pt; }
  .facts .k { white-space: nowrap; color: #333; width: 16%; }
  .facts .v { border-bottom: 0.5pt dotted #999; }
  .block { margin-bottom: 12pt; break-inside: avoid; }
  .block-head { font-weight: 700; border-bottom: 1pt solid #000;
                margin-bottom: 4pt; padding-bottom: 2pt; }
  .grid th, .grid td { border: 0.5pt solid #666; padding: 2pt 5pt; font-size: 13.5pt; }
  .grid th { background: #eee; font-weight: 600; }
  .block ul { margin: 0; padding-left: 20pt; font-size: 13.5pt; }
  .small { font-size: 13pt; margin: 3pt 0; }
  .minus { color: #a00; }
  .plus  { color: #060; }
  .note { border-left: 2pt solid #999; padding-left: 6pt; }
  .foot { margin-top: 14pt; font-size: 12pt; }
</style>`;

  return page(`ระเบียนสะสม ${doc.doc_no}`, 'portrait', body);
}

/**
 * เลือกแม่แบบตามประเภทเอกสาร
 *
 * ประเภทที่ยังไม่มีแม่แบบต้องโยนข้อผิดพลาดที่อ่านรู้เรื่อง ไม่ใช่คืนหน้าเปล่า
 * เพราะหน้าเปล่าที่พิมพ์ออกมาแล้วดูเหมือนกระดาษเสีย ไม่ใช่ระบบยังทำไม่เสร็จ
 */
export function renderDocument(doc: IssuedDocument): string {
  switch (doc.kind) {
    case 'transcript':
      return renderTranscript(doc);
    case 'certificate':
      return renderCertificate(doc);
    case 'certification':
      return renderCertification(doc);
    case 'grade_report':
      return renderGradeReport(doc);
    case 'cumulative_record':
      return renderCumulativeRecord(doc);
    default:
      throw new Error(`ยังไม่มีแม่แบบพิมพ์สำหรับเอกสารประเภท ${doc.kind}`);
  }
}

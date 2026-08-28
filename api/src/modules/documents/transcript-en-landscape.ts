/**
 * ใบ รบ. ภาษาอังกฤษ แนวนอน — รูปแบบสุดท้ายของ 5 กลุ่มที่วัดจากไฟล์จริง
 *
 * ═══ ทำไมทำท้ายสุดและทำไมเรียบง่ายกว่าตระกูล 62/67 ═══
 * วัดจาก `ระเบียนแสดงผลการเรียนภาษาอังกฤษ.pdf` (A4 แนวนอน 842×595, ฟอนต์
 * AngsanaNew) พบว่าตารางแบ่งสองคอลัมน์ต่อหน้า ตีเส้นด้วยกล่องสีขาวทับ
 * เส้นตารางที่ **พิมพ์มาแล้วบนกระดาษตรา** ไม่ใช่เส้นที่ซอฟต์แวร์วาดเอง —
 * ต่างจากตระกูล 62/67 ที่วาดกรอบตารางเองทั้งหมด แปลว่าการเลียนแบบพิกัด
 * เส้นทุกเส้นจากไฟล์ต้นฉบับไม่มีความหมายสำหรับกระดาษเปล่า (ซึ่งเป็นโหมด
 * เริ่มต้นของระบบนี้ตามหลักข้อ 4 — กระดาษตราเป็นตัวเลือกตอนพิมพ์ ไม่ใช่
 * แม่แบบแยก)
 *
 * แม่แบบนี้จึงวาดกรอบตารางเองแบบเดียวกับตระกูล 62/67 (เพื่อให้พิมพ์ลง
 * กระดาษเปล่าได้ถูกต้อง) แต่ใช้**ตารางไหลตามเนื้อหาปกติของเบราว์เซอร์**
 * แทนระบบคำนวณความจุ/ยุบฟอนต์ทีละขั้นแบบตระกูล 62/67 (`fitColumns`/
 * `packColumns`) — ระบบนั้นวัดมาจากกรอบที่ตรึงขนาดคงที่ของกระดาษตรา
 * ต้นฉบับ ซึ่งไม่มีความหมายอีกต่อไปเมื่อไม่มีกระดาษตรา แนวนอนให้พื้นที่
 * กว้างกว่าแนวตั้งมากพออยู่แล้ว การไหลตามธรรมชาติจึงพอเพียงและลดความเสี่ยง
 * บั๊กจากการมัดพิกัดตายตัวที่ผูกกับกระดาษเฉพาะแผ่นที่ไม่มีอยู่แล้ว
 *
 * ใช้ payload ชุดเดียวกับตระกูล 62 (`term_tree`) เพราะเป็นข้อมูลเดียวกัน
 * แค่จัดวางหน้าต่างออกไป — ไม่ใช่ตัวเลขคนละชุด
 */
import { TRANSCRIPT_FONT_FACE } from './fonts';
import { engDate } from './templates';
import { GRADE_LETTERS_62, has62TermTree, type Transcript62Document } from './transcript-62';

function esc(v: unknown): string {
  if (v === null || v === undefined) return '';
  return String(v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function credits(v: unknown): string {
  if (v === null || v === undefined || v === '') return '-';
  const n = Number(v);
  if (!Number.isFinite(n)) return '-';
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function gpa(v: unknown): string {
  if (v === null || v === undefined || v === '') return '-';
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(2) : '-';
}

/** ระดับผลการเรียนพิมพ์เป็นสัญลักษณ์ (ผ./ม.ผ.) เมื่อไม่มีแต้ม */
function gradeCell(grade: string, gradePoint: string | number | null): string {
  if (gradePoint === null || gradePoint === undefined) return esc(grade);
  const n = Number(gradePoint);
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

interface CourseEn {
  code: string;
  name_en: string;
  name_th: string;
  credits: string | number;
  grade: string;
  grade_point: string | number | null;
  credits_earned: string | number | null;
}

interface TermEn {
  year_be: number;
  ordinal: number;
  credits_earned: string | number | null;
  credits_cum: string | number | null;
  gpa: string | number | null;
  gpax: string | number | null;
  courses: CourseEn[];
}

/**
 * เกณฑ์การสำเร็จหลักสูตร — ข้อความคงที่ตามระเบียบ สอศ. ไม่ใช่ค่าตั้งของ
 * วิทยาลัย (เหมือนที่ตระกูล 62/67 อ่านจาก `institution_document_text`)
 * ที่นี่ใช้ค่าคงที่ภาษาอังกฤษเพราะยังไม่มีวิทยาลัยไหนต้องแก้ข้อความชุดนี้
 * เป็นภาษาอื่น — ถ้าต้องแก้ทีหลังค่อยย้ายไปอ่านจากตารางเดียวกับตระกูลอื่น
 */
const GRADUATION_REQUIREMENTS_EN = [
  'Not less than the credits required in accordance with the program structure',
  'Obtain a cumulative G.P.A. of not less than 2.00',
  'Join student activities with a minimum requirement of 2 periods/week',
  'in accordance with the program structure',
];

const GRADE_SCALE_EN: [string, string][] = [
  ['4', 'Excellent'], ['3.5', 'Very Good'],
  ['3', 'Good'], ['2.5', 'Fairly Good'],
  ['2', 'Fair'], ['1.5', 'Fairly Poor'],
  ['1', 'Poor'], ['0', 'Fail'],
];

function style(): string {
  return `
  ${TRANSCRIPT_FONT_FACE}
  @page { size: A4 landscape; margin: 18pt 20pt 18pt 20pt; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: 'TH Sarabun New', 'TH SarabunPSK', 'THSarabunNew', 'Sarabun',
                 'Angsana New', 'AngsanaUPC', 'Cordia New', serif;
    font-size: 13pt; line-height: 1.25; color: #000;
  }
  .page { position: relative; page-break-after: always; padding-bottom: 4pt; }
  .page:last-child { page-break-after: auto; }

  .docno { text-align: right; font-size: 12pt; }
  h1 { font-size: 17pt; font-weight: 700; text-align: center; margin: 0 0 2pt; }
  h1.sub { font-size: 15pt; font-weight: 700; margin: 0 0 8pt; }

  .head { display: grid; grid-template-columns: 1fr 1fr; gap: 0 24pt;
          font-size: 12.5pt; margin-bottom: 8pt; }
  .head dl { display: grid; grid-template-columns: max-content 1fr;
             column-gap: 6pt; row-gap: 1pt; margin: 0; }
  .head dt { white-space: nowrap; }
  .head dd { margin: 0; border-bottom: 0.5pt dotted #999; }

  table.grid { width: 100%; border-collapse: collapse; table-layout: fixed;
               font-size: 11.5pt; margin-bottom: 4pt; }
  table.grid th, table.grid td { border: 0.6pt solid #000; padding: 1.5pt 4pt; vertical-align: top; }
  table.grid th { text-align: center; font-weight: 400; background: #f2f2f2; }
  table.grid td.num { text-align: center; }
  table.grid tr.term td { font-weight: 700; background: #fafafa; }
  table.grid tr.sum td { font-size: 10.6pt; }
  table.grid tr { page-break-inside: avoid; }

  .cols { display: grid; grid-template-columns: 1fr 1fr; gap: 0 16pt; }

  .leave { display: flex; gap: 30pt; font-size: 12pt; margin: 4pt 0; }
  .signs { display: flex; justify-content: space-around; margin-top: 10pt; text-align: center; }
  .sign { width: 38%; font-size: 12pt; }
  .sign div { height: 15pt; line-height: 15pt; }
  .sign .role { font-size: 11.5pt; }

  .legend { display: grid; grid-template-columns: 1.4fr 1fr; gap: 0 20pt; font-size: 11pt; margin-top: 6pt; }
  .legend h2 { font-size: 12pt; font-weight: 700; margin: 0 0 3pt; }
  .legend table { border-collapse: collapse; width: 100%; }
  .legend td { padding: 0.5pt 4pt; vertical-align: top; }

  .stamp { position: absolute; top: 220pt; left: 0; right: 0; text-align: center;
    font-size: 60pt; font-weight: 700; color: rgba(200,0,0,.22);
    transform: rotate(-20deg); pointer-events: none; }
  .stamp.copy { top: 320pt; font-size: 40pt; }
  .void-note { color: #a00; font-size: 10pt; text-align: center; }

  @media screen {
    body { background: #f4f4f4; padding: 14px; }
    .page { background: #fff; width: 841.9pt; height: 595.3pt;
            margin: 0 auto 14px; padding: 18pt 20pt;
            box-shadow: 0 1px 6px rgba(0,0,0,.25); overflow: hidden; }
  }
`;
}

function stamps(doc: Transcript62Document): string {
  const out: string[] = [];
  if (doc.voided_at) {
    out.push('<div class="stamp void">VOID</div>');
    out.push(`<div class="void-note">This document was voided on ${esc(engDate(doc.voided_at))}` +
      ` — ${esc(doc.void_reason ?? '')}</div>`);
  }
  if (Number(doc.copy_no) > 1) out.push('<div class="stamp copy">COPY</div>');
  return out.join('\n');
}

function courseRows(term: TermEn): string {
  const head = `<tr class="term"><td colspan="5">Academic Year ${term.year_be - 543}` +
    `&nbsp;&nbsp;${term.ordinal === 1 ? '1st' : term.ordinal === 2 ? '2nd' : term.ordinal === 3 ? '3rd' : `${term.ordinal}th`} Semester</td></tr>`;
  const rows = (term.courses ?? []).map((c) => {
    const hasPoint = c.grade_point !== null && c.grade_point !== undefined;
    return `<tr>
      <td>${esc(c.code)}</td>
      <td>${esc(c.name_en || c.name_th)}</td>
      <td class="num">${hasPoint ? credits(c.credits) : '-'}</td>
      <td class="num">${gradeCell(c.grade, c.grade_point)}</td>
    </tr>`;
  }).join('');
  const sum = `<tr class="sum"><td colspan="4">Credits earned this semester ${credits(term.credits_earned)}` +
    `&nbsp;&nbsp;Cumulative credits ${credits(term.credits_cum)}` +
    `&nbsp;&nbsp;G.P.A. ${gpa(term.gpa)}&nbsp;&nbsp;Cumulative G.P.A. ${gpa(term.gpax)}</td></tr>`;
  return head + rows + sum;
}

function table(terms: TermEn[]): string {
  return `<table class="grid"><colgroup>
    <col style="width:16%"><col style="width:56%"><col style="width:14%"><col style="width:14%">
  </colgroup><thead><tr>
    <th>Course Code</th><th>Course Title</th><th>Credit</th><th>Grade</th>
  </tr></thead><tbody>
    ${terms.map(courseRows).join('')}
  </tbody></table>`;
}

/**
 * ปฏิเสธ (ไม่พิมพ์) แม่แบบนี้ถ้าไม่มี `term_tree` — เหตุผลเดียวกับ
 * `has62TermTree` เพราะใช้ payload ชุดเดียวกัน
 */
export function hasTermTree(payload: { term_tree?: unknown }): boolean {
  return has62TermTree(payload);
}

export function renderTranscriptEnLandscape(doc: Transcript62Document): string {
  const d = doc.payload;
  const name = d.student.full_name_en || d.student.full_name_th;
  const school = d.institution.name_en || d.institution.name_th;
  const prog = d.program;
  const D = engDate;

  const terms = (d.term_tree ?? []) as unknown as TermEn[];
  const half = Math.ceil(terms.length / 2);
  const left = terms.slice(0, half);
  const right = terms.slice(half);

  const qual = prog?.level === 'PVS' ? 'DIPLOMA IN VOCATIONAL EDUCATION'
    : prog?.level === 'PVC' ? 'CERTIFICATE IN VOCATIONAL EDUCATION'
    : (prog?.qualification_en ?? '');

  const field = (label: string, value: string) => `<dt>${label}</dt><dd>${value}</dd>`;
  const issuedOn = `Issued on ${D(doc.issued_on)}`;

  const signs = `<div class="signs">
    <div class="sign"><div>(&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)</div>
      <div class="role">Registrar</div><div class="role">${esc(issuedOn)}</div></div>
    <div class="sign"><div>(&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)</div>
      <div class="role">Director</div><div class="role">${esc(issuedOn)}</div></div>
  </div>`;

  const page1 = `
<div class="page">
  ${stamps(doc)}
  <div class="docno">Transcript No. ${esc(doc.doc_no)}</div>
  <h1>TRANSCRIPT</h1>
  <h1 class="sub">THE CERTIFICATE OF VOCATIONAL EDUCATION — ${esc(qual)}${
    prog?.is_continuing ? ' (CONTINUING PROGRAM)' : ''}</h1>

  <div class="head">
    <dl>
      ${field('Student No.', esc(d.student.student_code))}
      ${field("Student's Name", esc(name))}
      ${field('Date of Birth', esc(D(d.student.birth_date)))}
      ${field('ID No.', esc(d.student.national_id ?? ''))}
      ${field('Area of Study', esc(prog?.type_en ?? ''))}
      ${field('Program', esc(prog?.name_en ?? ''))}
      ${field('Field of Specialization', esc(prog?.track_en ?? ''))}
    </dl>
    <dl>
      ${field('College Name', esc(school))}
      ${field('College Code', esc(d.institution.code))}
      ${field('Entry Qualification', esc(d.prior_education?.level_th ?? ''))}
      ${field('Previous School', esc(d.prior_education?.school_th ?? ''))}
      ${field('Credits Transferred', '-')}
      ${field('Total Credits', esc(credits(d.graduation?.credits_earned ?? d.summary?.credits_earned)))}
      ${field('Cumulative G.P.A.', esc(gpa(d.graduation?.gpax ?? d.summary?.gpax)))}
      ${field('Date of Completion', esc(d.graduation?.completed_on ? D(d.graduation.completed_on) : '-'))}
    </dl>
  </div>

  <div class="cols">
    <div>${table(left)}</div>
    <div>${table(right)}</div>
  </div>

  <div class="leave"><span>Date of Leaving: -</span><span>Reason for Leaving: -</span></div>
  ${signs}
</div>`;

  const page2 = `
<div class="page">
  ${stamps(doc)}
  <div style="display:flex;justify-content:space-between;font-size:12pt">
    <span>Name: ${esc(name)}</span>
    <span>Student No.: ${esc(d.student.student_code)}</span>
    <span>page 2</span>
  </div>
  <div class="legend">
    <div>
      <h2>Graduation Requirements</h2>
      ${GRADUATION_REQUIREMENTS_EN.map((x, i) => `<div>${i + 1}. ${esc(x)}</div>`).join('')}
    </div>
    <div>
      <h2>Grade System</h2>
      <table><tbody>
        ${(() => {
          const out: string[] = [];
          for (let i = 0; i < GRADE_SCALE_EN.length; i += 2) {
            const [a, alabel] = GRADE_SCALE_EN[i];
            const b = GRADE_SCALE_EN[i + 1];
            out.push(`<tr><td style="width:14%">${a}</td><td style="width:36%">${alabel}</td>` +
              `<td style="width:14%">${b ? b[0] : ''}</td><td>${b ? b[1] : ''}</td></tr>`);
          }
          return out.join('');
        })()}
      </tbody></table>
      <h2 style="margin-top:8pt">Mark System</h2>
      <table><tbody>
        ${GRADE_LETTERS_62.map(([, en, , den]) => `<tr><td style="width:14%">${en}</td><td>${den}</td></tr>`).join('')}
      </tbody></table>
    </div>
  </div>
</div>`;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${esc(`Transcript ${doc.doc_no}`)}</title>
<style>${style()}</style>
</head>
<body>
${page1}
${page2}
</body>
</html>`;
}

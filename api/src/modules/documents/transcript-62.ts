/**
 * ใบ รบ. ตระกูล 62 — จัดกลุ่มตามภาคเรียน ทั้งฉบับไทยและอังกฤษ
 *
 * ═══ ตัวเลขทั้งหมดวัดจากไฟล์จริง ไม่ได้เดา ═══
 * วัดจาก `ระเบียนแสดงผลการเรียนภาษาไทย (แนวตั้ง 62).pdf` และฉบับอังกฤษคู่กัน
 *   A4 แนวตั้ง 595 × 842 pt · ฟอนต์ TH Sarabun New 12.5 pt
 *   ขอบซ้าย 22.6 · ขวา 24 · ล่าง 13
 *   ขอบคอลัมน์ครึ่งซ้าย x = 23 · 71 · 228 · 251 · 274 · 296
 *   → รหัสวิชา 48 · ชื่อวิชา 157 · หน่วยกิต 23 · ผลการเรียน 23 · (1)×(2) 22
 *   ครึ่งขวาสมมาตร เริ่มที่ 298
 *
 * ═══ สามอย่างที่ต่างจากตระกูล 67 อย่างมีนัย ═══
 * 1. **จัดกลุ่มตามปีการศึกษา → ภาคเรียน** ไม่ใช่ตามหมวด/กลุ่มวิชา
 *    และสรุปสี่ตัวเลขท้ายทุกภาค (หน่วยกิตที่ได้ · สะสม · GPA · GPAX)
 *    ซึ่งไหลอยู่ในตารางเดียวกับรายวิชา ไม่ใช่บล็อกแยกท้ายใบ
 * 2. **มีคอลัมน์ผลคูณ (1)×(2)** ที่ตระกูล 67 ไม่มีเลย
 * 3. **ฉบับไทยไม่มีบรรทัดชื่อเรื่องและไม่มีเลขที่ รบ.** — เว้นพื้นที่ 76 pt
 *    ด้านบนไว้ให้หัวกระดาษที่พิมพ์มาแล้ว ส่วน**ฉบับอังกฤษมีทั้งสองอย่าง**
 *    (วัดแล้ว ฉบับอังกฤษเริ่มบล็อกหัวที่ 100.7 คือเลื่อนลงมา 24.5 pt)
 *    ข้อนี้เดาไม่ถูกเลยถ้าไม่ได้เปิดสองไฟล์เทียบกัน
 *
 * ═══ ถ้อยคำระดับผลการเรียนของตระกูลนี้ต่างจาก 67 จริง ═══
 * 62: 1.5 = อ่อน · 1 = อ่อนมาก   ส่วน 67: 1.5 = ค่อนข้างอ่อน · 1 = อ่อน
 * ทั้งคู่วัดจากไฟล์จริงของตัวเอง — อย่ารวมเป็นชุดเดียวแล้วให้ใบใดใบหนึ่งผิด
 *
 * ═══ ที่จงใจไม่ทำตามไฟล์ต้นฉบับ ═══
 * ฉบับอังกฤษของ SISA สะกดผิดสี่แห่ง — "Fairy good" · "Fairy poor" ·
 * "standaed" · "courser" (และหัวคอลัมน์กลางของฉบับไทยเขียน "บันทึก"
 * ซ้ำกับช่องบันทึกจริงท้ายหน้า ทั้งที่ฉบับอังกฤษเขียน "Notes" คือ "หมายเหตุ")
 * แม่แบบนี้สะกดถูก เพราะใบนี้เป็นเอกสารทางการที่คนถือไปยื่นที่อื่น —
 * ความเหมือนต้นฉบับไม่ได้มีค่ามากกว่าความถูกต้องของภาษาบนกระดาษ
 */
import type { IssuedDocument } from './templates';
import { engDate, engYear, thaiDate } from './templates';

/* ─── ชนิดข้อมูลของ payload ที่ 0060 สร้าง ──────────────────────── */

interface Course62 {
  code: string;
  name_th: string;
  name_en: string;
  credits: string | number;
  grade: string;
  grade_point: string | number | null;
  /** ผลคูณหน่วยกิต × ระดับผลการเรียน — null เมื่อไม่นับ GPA */
  grade_points: string | number | null;
  counts_in_gpa: boolean;
  credits_earned: string | number | null;
}

interface Term62 {
  year_be: number;
  ordinal: number;
  credits_earned: string | number | null;
  /** null เมื่อมีภาคก่อนหน้าที่ยังไม่ได้ตัดยอด — พิมพ์ "-" ไม่ใช่เดา */
  credits_cum: string | number | null;
  has_summary: boolean;
  gpa: string | number | null;
  gpax: string | number | null;
  courses: Course62[];
}

export interface Transcript62Payload {
  kind: string;
  lang: 'th' | 'en';
  year_be: number;
  institution: { code: string; name_th: string; name_en?: string };
  student: {
    student_code: string;
    full_name_th: string;
    full_name_en?: string;
    birth_date: string | null;
    admitted_year_be: number | null;
    status: string;
    /** เติมโดยชั้น API ตอนพิมพ์ — payload เก็บแต่ไบต์ที่เข้ารหัสแล้ว */
    national_id?: string;
  };
  program: {
    type_th: string; name_th: string; track_th: string;
    curriculum_th: string; level: string; edition_be: number;
    qualification_th: string; qualification_abbr_th: string;
    type_en?: string; name_en?: string; track_en?: string;
    qualification_en?: string;
    is_continuing?: boolean;
  } | null;
  graduation: { completed_on: string; gpax: string; credits_earned: string } | null;
  summary: { credits_earned: string | number; gpax: string | number | null };
  term_tree: Term62[];
  prior_education?: {
    level_th: string; school_th: string; province_th: string;
    program_th: string; year_be: number | null; gpax: string | number | null;
  } | null;
  /** หน่วยกิตที่ลงเรียน — คนละตัวกับหน่วยกิตที่ได้ (0060) */
  credits_attempted?: string | number | null;
  institution_text?: Record<string, { th: string; en: string }>;
  professional_standard?: { no: string; passed: boolean | null; on_date: string | null };
}

export interface Transcript62Document extends Omit<IssuedDocument, 'payload'> {
  payload: Transcript62Payload;
}

/* ─── ตัวช่วย ────────────────────────────────────────────────────── */

function esc(v: unknown): string {
  if (v === null || v === undefined) return '';
  return String(v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/** หน่วยกิตบนใบเขียนเป็นจำนวนเต็มเมื่อลงตัว — ใบจริงพิมพ์ "1" ไม่ใช่ "1.0" */
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

/** ผลคูณพิมพ์ทศนิยมหนึ่งตำแหน่งเสมอ — ใบจริงพิมพ์ "2.0" ไม่ใช่ "2" */
function product(v: unknown): string {
  if (v === null || v === undefined || v === '') return '-';
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(1) : '-';
}

/**
 * ผลการเรียนบนใบ
 *
 * วิชาที่ได้ ผ./ม.ผ. ไม่มีแต้ม ใบจริงจึงพิมพ์สัญลักษณ์แทนตัวเลข —
 * ถ้าแปลงเป็น 0 จะอ่านได้ว่าตก ซึ่งคนละเรื่องกับผ่านแบบไม่คิดแต้ม
 */
function gradeCell(c: Course62): string {
  if (c.grade_point === null || c.grade_point === undefined) return esc(c.grade);
  const n = Number(c.grade_point);
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

/**
 * หัวภาคเรียน
 *
 * ฉบับอังกฤษใช้ **ปีคริสต์ศักราช** — ใบจริงพิมพ์ "Academic year 2025"
 * คู่กับ "ปีการศึกษา 2568" ในฉบับไทย เป็นข้อเดียวกับหัวเรื่องของตระกูล 67
 */
function termHeading(t: Term62, lang: 'th' | 'en'): string {
  if (lang === 'en') {
    const suffix = t.ordinal === 1 ? 'st' : t.ordinal === 2 ? 'nd' : t.ordinal === 3 ? 'rd' : 'th';
    return `Academic year ${t.year_be - 543}&nbsp;&nbsp;${t.ordinal}${suffix} Semester`;
  }
  return `ปีการศึกษา ${t.year_be}&nbsp;&nbsp;ภาคเรียนที่ ${t.ordinal}`;
}

const L = {
  th: {
    title: (edition: number, q: string) => `ระเบียนแสดงผลการเรียนตามหลักสูตร${q} พุทธศักราช ${edition}`,
    docNo: 'เลขที่',
    schoolCode: 'รหัสสถานศึกษา', schoolName: 'ชื่อสถานศึกษา', province: 'จังหวัด',
    studentCode: 'รหัสประจำตัว', name: 'ชื่อ - ชื่อสกุล',
    ethnic: 'เชื้อชาติ    สัญชาติ    ศาสนา', birth: 'วัน เดือน ปีเกิด',
    citizenId: 'เลขประจำตัวประชาชน', father: 'ชื่อบิดา', mother: 'ชื่อมารดา',
    progType: 'ประเภทวิชา', progName: 'สาขาวิชา', progTrack: 'สาขางาน',
    prevSchool: 'สถานศึกษาเดิม', prevLevel: 'ระดับการศึกษาที่จบ',
    prevYear: 'ปีการศึกษาที่จบ', prevProgram: 'สาขาวิชาเดิม',
    admitted: 'เข้าศึกษาเมื่อ',
    transferred: 'หน่วยกิตที่รับโอน', attempted: 'หน่วยกิตที่เรียน',
    earned: 'หน่วยกิตที่ได้', gpax: 'ระดับคะแนนเฉลี่ยสะสม',
    profStd: 'ผ่านเกณฑ์การประเมินมาตรฐานวิชาชีพเมื่อ', graduated: 'สำเร็จการศึกษาเมื่อ',
    photo: 'รูปถ่าย',
    colCode: 'รหัสวิชา', colName: 'ชื่อวิชา',
    colCredit: 'หน่วย<br>กิต<br>(1)', colGrade: 'ผล<br>การ<br>เรียน<br>(2)',
    colProduct: '(1)<br>x<br>(2)',
    termCredits: 'หน่วยกิตที่ได้ในภาค', cumCredits: 'หน่วยกิตสะสม',
    termGpa: 'คะแนนเฉลี่ยในภาค', cumGpa: 'คะแนนเฉลี่ยสะสม',
    leftOn: 'ออกจากสถานศึกษาเมื่อ', leftWhy: 'เหตุที่ออก',
    registrar: 'หัวหน้างานทะเบียน', director: 'ผู้อำนวยการ',
    page2: 'หน้าที่ 2',
    gradeScale: 'ระดับผลการเรียน',
    criteria: 'เกณฑ์การสำเร็จหลักสูตร', notes: 'หมายเหตุ', memo: 'บันทึก',
    meaning: 'หมายถึง',
  },
  en: {
    title: (edition: number, q: string) => `${edition - 543} CURRICULUM OF THE ${q}`,
    docNo: 'No.',
    schoolCode: 'College Code', schoolName: 'College Name', province: 'Province',
    studentCode: 'Student No.', name: "Student's Name",
    ethnic: 'Race    Nationality    Religion', birth: 'Date of Birth',
    citizenId: 'ID No.', father: "Father's Name", mother: "Mother's Name",
    progType: 'Area of Study', progName: 'Program', progTrack: 'Field of Specialization',
    prevSchool: 'Previous School', prevLevel: 'Entry Qualification',
    prevYear: 'Year of Graduated', prevProgram: 'Previous Field of Study',
    admitted: 'Date of Admission',
    transferred: 'Credits Transferred', attempted: 'Credits Enrolled',
    earned: 'Total Credits', gpax: 'Cumulative G.P.A.',
    profStd: 'Date of Vocational Education Standard Assessment Achieved',
    graduated: 'Date of Completion',
    photo: 'photo',
    colCode: 'Course<br>Code', colName: 'Course Title',
    colCredit: 'Credit<br>(1)', colGrade: 'Grade<br>(2)',
    colProduct: '(1)<br>x<br>(2)',
    termCredits: 'Credits obtained per semester', cumCredits: 'Cumulative credits',
    termGpa: 'G.P.A. per semester', cumGpa: 'Cumulative G.P.A.',
    leftOn: 'Date of Leaving', leftWhy: 'Reason for Leaving',
    registrar: 'Registrar', director: 'Director',
    page2: 'page 2',
    gradeScale: 'System of Grading',
    criteria: 'Criteria for Completion', notes: 'Notes', memo: 'Notes',
    meaning: 'Refers to',
  },
} as const;

/**
 * ระดับผลการเรียนของตระกูล 62
 *
 * ต่างจาก 67 ที่ 1.5 กับ 1 — ทั้งสองชุดวัดจากไฟล์จริงของตระกูลตัวเอง
 * ฉบับอังกฤษสะกดถูกที่นี่ ("Fairly") ต่างจากต้นฉบับที่เขียน "Fairy"
 */
const GRADE_SCALE_62: [string, string, string][] = [
  ['4', 'ดีเยี่ยม', 'Excellent'],
  ['3.5', 'ดีมาก', 'Very good'],
  ['3', 'ดี', 'Good'],
  ['2.5', 'ค่อนข้างดี', 'Fairly good'],
  ['2', 'พอใช้', 'Fair'],
  ['1.5', 'อ่อน', 'Fairly poor'],
  ['1', 'อ่อนมาก', 'Poor'],
  ['0', 'ตก', 'Fail'],
];

/**
 * ตัวอักษรแสดงระดับผลการเรียน พร้อม**รหัสฉบับอังกฤษ**
 *
 * รหัสอังกฤษชุดนี้ได้มาจากการเทียบไฟล์ฉบับอังกฤษกับฉบับไทยบรรทัดต่อบรรทัด
 * (I.C. ↔ ข.ร. · N.Cr ↔ ม.ก. …) — ไม่ใช่การแปลเอง ซึ่งจะได้รหัสที่ไม่ตรง
 * กับใบที่หน่วยงานอื่นเคยเห็น แล้วกลายเป็นใบที่อ่านไม่ออกว่าหมายถึงอะไร
 */
export const GRADE_LETTERS_62: [string, string, string, string][] = [
  ['ข.ร.', 'I.C.', 'ขาดเรียนไม่มีสิทธิ์วัดผลปลายภาคเรียน', 'Insufficient class attendance'],
  ['ข.ส.', 'I.L.', 'ขาดการวัดผลปลายภาคเรียน', 'Incomplete learning assessment'],
  ['ข.ป.', 'I.P.', 'ขาดการปฏิบัติงาน', 'Incomplete practical assignment'],
  ['ถ.น.', 'W.W.', 'ถอนรายวิชาภายในกำหนด', 'Withdraw within time line'],
  ['ถ.ล.', 'W.A.', 'ถอนรายวิชาหลังกำหนด', 'Withdraw after date line'],
  ['ม.ส.', 'N.C.', 'ไม่สมบูรณ์', 'Not complete'],
  ['ม.ท.', 'U.T.', 'ไม่สามารถเข้าวัดผลปลายภาคเรียนทดแทน', 'Unable to undertake substitute assessment'],
  ['ม.ก.', 'N.Cr', 'ไม่นับหน่วยกิตเพื่อสำเร็จการศึกษา', 'Non-credit'],
  ['ท.', 'C.', 'ทุจริต', 'Cheating'],
  ['ผ.', 'P.', 'ผ่าน', 'Pass'],
  ['ม.ผ.', 'F.', 'ไม่ผ่าน', 'Fail'],
];

/* ─── สไตล์ที่ตรงกับตัวเลขที่วัดมา ──────────────────────────────── */

/**
 * ─── ขอบบนต่างกันตามภาษาโดยตั้งใจ ───
 * ฉบับไทยไม่มีบรรทัดชื่อเรื่อง จึงเว้น 76 pt ให้หัวกระดาษที่พิมพ์มาแล้ว
 * ฉบับอังกฤษมีชื่อเรื่องอยู่ในเนื้อ จึงเริ่มที่ 12 pt แล้วชื่อเรื่องกินที่แทน
 */
function style(lang: 'th' | 'en'): string {
  const topMargin = lang === 'en' ? 12 : 76;
  return `
  @page { size: A4 portrait; margin: ${topMargin}pt 24pt 13pt 23pt; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', 'Tahoma', sans-serif;
    font-size: 12.5pt; line-height: 1.27; color: #000;
  }
  .page { position: relative; page-break-after: always; }
  .page:last-child { page-break-after: auto; }

  .docno { text-align: right; font-size: 13.5pt; margin-bottom: 2pt; }
  h1 { font-size: 19.3pt; font-weight: 700; text-align: center; margin: 0 0 2pt; }
  h1.sub { font-size: 19.3pt; margin-bottom: 10pt; }

  /* บล็อกหัว — สองคอลัมน์ label/value พร้อมกรอบรูปถ่ายขวาสุด */
  .head { display: flex; gap: 0; align-items: flex-start; margin-bottom: 8pt; }
  .head dl {
    display: grid; grid-template-columns: max-content 1fr;
    column-gap: 6pt; row-gap: 0; margin: 0;
  }
  .head dl.left  { width: 41.4%; }
  .head dl.right { width: 47.4%; }
  .head dt { white-space: nowrap; }
  .head dd { margin: 0; }
  .photo {
    width: 71pt; height: 85pt; border: 0.6pt solid #000;
    display: flex; align-items: center; justify-content: center;
    margin-left: auto; font-size: 12.5pt;
  }

  /* ตารางรายวิชาสองคอลัมน์ที่ไหลซ้าย → ขวา */
  table.courses { border-collapse: collapse; table-layout: fixed; }
  table.courses th, table.courses td {
    border: 0.6pt solid #000; padding: 0 2pt; vertical-align: top;
  }
  table.courses th { font-weight: 400; text-align: center; line-height: 1.05; }
  table.courses td.code { white-space: nowrap; }
  table.courses td.num  { text-align: center; }
  /* หัวภาคเรียนกินเต็มความกว้างของครึ่งหน้า */
  table.courses td.term { text-align: center; font-weight: 700; border-top-width: 0.6pt; }
  table.courses td.termsum { text-align: center; font-size: 11.6pt; border: 0; }

  .leave { margin-top: 6pt; }
  .signs { display: flex; justify-content: space-around; margin-top: 10pt; text-align: center; }
  .sign { width: 40%; font-size: 13.5pt; }
  .sign .role { font-size: 12.5pt; }

  /* ท้ายหน้า 2 — สามบล็อกคำอธิบาย */
  .legend { display: flex; gap: 10pt; font-size: 11.6pt; margin-top: 10pt; }
  .legend .col1 { width: 30%; }
  .legend .col2 { width: 34%; }
  .legend .col3 { width: 36%; }
  .legend h2 { font-size: 11.6pt; font-weight: 700; margin: 0 0 3pt; }
  .legend table { border-collapse: collapse; width: 100%; }
  .legend td { padding: 0; vertical-align: top; }
  .memo { margin-top: 8pt; font-size: 13.5pt; }
  .memo .lines { font-size: 12.5pt; letter-spacing: 0.4pt; }

  .stamp {
    position: absolute; top: 300pt; left: 0; right: 0; text-align: center;
    font-size: 64pt; font-weight: 700; color: rgba(200, 0, 0, 0.22);
    transform: rotate(-20deg); pointer-events: none;
  }
  .stamp.copy { top: 420pt; font-size: 44pt; }
  .void-note { color: #a00; font-size: 11pt; text-align: center; }
`;
}

/* ─── ตาราง ─────────────────────────────────────────────────────── */

/**
 * แถวหนึ่งของตาราง — เป็นหัวภาค รายวิชา หรือบรรทัดสรุปท้ายภาค
 *
 * ทั้งสามชนิดอยู่ในลำดับเดียวกันเพราะใบจริงให้มันไหลต่อกันในคอลัมน์เดียว
 * ถ้าแยกบรรทัดสรุปออกไปเป็นบล็อกอื่น มันจะไม่ตามภาคไปเมื่อภาคนั้นตกไป
 * อยู่หัวคอลัมน์ขวา ซึ่งเกิดจริงในไฟล์ที่วัด (สรุปของภาคสุดท้ายอยู่บนสุด
 * ของครึ่งขวา ห่างจากรายวิชาของมันคนละคอลัมน์)
 */
type Row62 =
  | { kind: 'term'; text: string }
  | { kind: 'course'; course: Course62 }
  | { kind: 'sum'; line1: string; line2: string };

function buildRows(terms: Term62[], lang: 'th' | 'en', t: typeof L['th'] | typeof L['en']): Row62[] {
  const out: Row62[] = [];
  for (const term of terms) {
    out.push({ kind: 'term', text: termHeading(term, lang) });
    for (const c of term.courses ?? []) out.push({ kind: 'course', course: c });
    out.push({
      kind: 'sum',
      line1: `${t.termCredits} ${credits(term.credits_earned)} ${t.cumCredits} ${credits(term.credits_cum)}`,
      line2: `${t.termGpa} ${gpa(term.gpa)} ${t.cumGpa} ${gpa(term.gpax)}`,
    });
  }
  return out;
}

function renderRow(r: Row62, lang: 'th' | 'en'): string {
  if (r.kind === 'term') return `<tr><td class="term" colspan="5">${r.text}</td></tr>`;
  if (r.kind === 'sum') {
    return `<tr><td class="termsum" colspan="5">${esc(r.line1)}</td></tr>
            <tr><td class="termsum" colspan="5">${esc(r.line2)}</td></tr>`;
  }
  const c = r.course;
  /*
   * ─── ชื่อวิชาภาษาไทยบนใบภาษาอังกฤษคือสิ่งที่ต้องไม่เกิด ───
   * ไฟล์ที่ SISA ออกจริงมีชื่อวิชาไทยปนอยู่ในตารางอังกฤษ เพราะยอมออกใบ
   * ทั้งที่ข้อมูลอังกฤษไม่ครบ — 0057 ปฏิเสธไปแล้วตั้งแต่ขั้นออกใบ
   * ตรงนี้จึงใช้ชื่ออังกฤษตรง ๆ ได้โดยไม่ต้อง fallback เป็นไทย
   */
  const courseName = lang === 'en' ? c.name_en : c.name_th;
  /*
   * วิชาที่ไม่นับ GPA พิมพ์ "-" ทั้งช่องหน่วยกิตและช่องผลคูณ
   * (วัดจากไฟล์จริง — กิจกรรมลูกเสือวิสามัญได้ ผ. พิมพ์ "-" ไม่ใช่ "0")
   * การพิมพ์ 0 จะอ่านได้ว่าลงเรียนแล้วไม่ได้หน่วยกิต ซึ่งคนละเรื่องกัน
   */
  /*
   * ─── ช่องหน่วยกิตพิมพ์ "-" เมื่อรายวิชา**ไม่มีระดับคะแนน** ───
   * ไม่ใช่เมื่อ "ไม่นับ GPA" ซึ่งเป็นคนละเงื่อนไข วิชาเทียบโอนไม่นับ GPA
   * แต่ได้หน่วยกิตจริง ถ้าใช้เงื่อนไขเดียวกัน ใบจะพิมพ์ "-" ให้วิชาที่
   * นักศึกษาได้หน่วยกิตมาแล้ว แล้วหน่วยกิตในตารางจะบวกไม่ครบตามหัวใบ
   * (วัดจากไฟล์จริง — กิจกรรมลูกเสือได้ ผ. พิมพ์ "-" ส่วนวิชาที่ได้ ขร.
   *  ซึ่งมีระดับคะแนน 0 พิมพ์หน่วยกิตจริงคู่กับผลคูณ 0.0)
   */
  const hasPoint = c.grade_point !== null && c.grade_point !== undefined;
  const creditCell = hasPoint ? credits(c.credits) : '-';
  return `<tr>
    <td class="code">${esc(c.code)}</td>
    <td>${esc(courseName)}</td>
    <td class="num">${creditCell}</td>
    <td class="num">${gradeCell(c)}</td>
    <td class="num">${product(c.grade_points)}</td>
  </tr>`;
}

/** ความกว้างคอลัมน์เป็นสัดส่วนของครึ่งหน้า (273 pt) ตามที่วัดมา */
const COLS = `<colgroup>
  <col style="width:17.6%"><col style="width:57.5%"><col style="width:8.4%">
  <col style="width:8.4%"><col style="width:8.1%"></colgroup>`;

function courseTable(rows: Row62[], t: typeof L['th'] | typeof L['en'], lang: 'th' | 'en'): string {
  const head = `<tr>
    <th>${t.colCode}</th><th>${t.colName}</th>
    <th>${t.colCredit}</th><th>${t.colGrade}</th><th>${t.colProduct}</th>
  </tr>`;
  /*
   * ─── ห้ามให้หัวภาคเป็นบรรทัดสุดท้ายของครึ่งซ้าย ───
   * ถ้าตัดตรงนั้น รายวิชาของภาคนั้นจะขึ้นไปอยู่ครึ่งขวาโดยไม่มีหัวกำกับ
   * ผู้อ่านจะนับรวมกับภาคก่อนหน้า ซึ่งเป็นความผิดพลาดที่อ่านไม่ออกจากใบ
   * — เลื่อนหัวภาคไปอยู่ต้นครึ่งขวาแทน
   */
  let half = Math.ceil(rows.length / 2);
  while (half > 0 && rows[half - 1]?.kind === 'term') half -= 1;

  const left = rows.slice(0, half);
  const right = rows.slice(half);
  return `<table class="courses" style="width:49.6%;float:left">
    ${COLS}<thead>${head}</thead><tbody>${left.map((r) => renderRow(r, lang)).join('')}</tbody>
  </table>
  <table class="courses" style="width:49.6%;float:right">
    ${COLS}<thead>${head}</thead><tbody>${right.map((r) => renderRow(r, lang)).join('')}</tbody>
  </table>
  <div style="clear:both"></div>`;
}

/**
 * ตราประทับยกเลิกและสำเนา
 *
 * ใบที่ยกเลิกแล้วต้องยังพิมพ์ได้ เพราะต้องพิสูจน์ย้อนหลังได้ว่าเคยออกอะไรไป
 * และใบนั้นอาจอยู่ในมือคนอื่นแล้ว — แต่ต้องมองปราดเดียวรู้ว่ายกเลิก
 */
function stamps(doc: Transcript62Document): string {
  const out: string[] = [];
  if (doc.voided_at) {
    out.push('<div class="stamp void">ยกเลิก</div>');
    out.push(
      `<div class="void-note">เอกสารฉบับนี้ถูกยกเลิกเมื่อ ${esc(thaiDate(doc.voided_at))}` +
        ` — ${esc(doc.void_reason ?? '')}</div>`,
    );
  }
  if (Number(doc.copy_no) > 1) out.push('<div class="stamp copy">สำเนา</div>');
  return out.join('\n');
}

/* ─── ตัวหลัก ────────────────────────────────────────────────────── */

export function renderTranscript62(doc: Transcript62Document): string {
  const d = doc.payload;
  const lang: 'th' | 'en' = d.lang === 'en' ? 'en' : 'th';
  const t = L[lang];
  const prog = d.program;

  const name = lang === 'en' ? (d.student.full_name_en || d.student.full_name_th)
                             : d.student.full_name_th;
  const school = lang === 'en' ? (d.institution.name_en || d.institution.name_th)
                               : d.institution.name_th;


  /*
   * ─── ทุกวันที่และทุกปีบนใบฉบับอังกฤษเป็นคริสต์ศักราช ───
   * วัดจากไฟล์จริง — "5 เมษายน 2552" ตรงกับ "April 5, 2009" และ
   * "ปีการศึกษาที่จบ 2567" ตรงกับ "Year of Graduated 2024"
   * ผูกไว้ที่ตัวแปรเดียวเพื่อไม่ให้มีที่ใดหลุดไปเรียก thaiDate() บนใบอังกฤษ
   */
  const D = lang === 'en' ? engDate : thaiDate;
  const Y = (v: unknown) => (v === null || v === undefined || v === ''
    ? '' : lang === 'en' ? engYear(v) : String(v));

  const cont = prog?.is_continuing ? ' (ต่อเนื่อง)' : '';
  const qual = lang === 'en'
    ? (prog?.level === 'PVS' ? 'DIPLOMA IN VOCATIONAL EDUCATION'
      : prog?.level === 'PVC' ? 'CERTIFICATE IN VOCATIONAL EDUCATION'
      : (prog?.qualification_en ?? ''))
    : `${prog?.qualification_th ?? ''}${cont}`;

  const rows = buildRows(d.term_tree ?? [], lang, t);
  // สองหน้าตายตัวเหมือนตระกูล 67 — หน้า 2 มีของประจำที่ต้องอยู่หน้า 2
  const perPage = 96;
  const p1 = rows.slice(0, perPage);
  const p2 = rows.slice(perPage);

  const field = (label: string, value: string) => `<dt>${label}</dt><dd>${value}</dd>`;

  const issuedOn = `${lang === 'en' ? 'Issued on' : 'ออกให้เมื่อ'} ${D(doc.issued_on)}`;

  /*
   * ─── ชื่อเรื่องและเลขที่ รบ. มีเฉพาะฉบับอังกฤษ ───
   * ฉบับไทยของตระกูลนี้พิมพ์ลงกระดาษที่มีหัวอยู่แล้ว การพิมพ์ชื่อเรื่องซ้ำ
   * จะได้ใบที่มีหัวสองชั้น (วัดแล้ว ฉบับไทยไม่มีข้อความใดเหนือ y = 76)
   */
  /*
   * ─── มุมขวาบนของฉบับอังกฤษ ───
   * ใบจริงพิมพ์ "Transcript 1 Cert.24 No." คือ "รบ.1" แปลตรงตัว ตามด้วย
   * ตัวย่อคุณวุฒิและ **ปีหลักสูตรเป็นคริสต์ศักราชสองหลัก** (2567 → 24)
   * ซึ่งต่างจากฉบับไทยที่ใช้ "ปวช.67" คือ พ.ศ. สองหลัก
   */
  const enKind = prog?.level === 'PVS' ? 'Dip.' : 'Cert.';
  const enEdition = String(Math.max(0, Number(prog?.edition_be ?? 0) - 543) % 100)
    .padStart(2, '0');
  const titleBlock = lang === 'en' ? `
  <div class="docno">Transcript 1 ${enKind}${enEdition} ${t.docNo} ${esc(doc.doc_no)}</div>
  <h1>TRANSCRIPT</h1>
  <h1 class="sub">${esc(t.title(Number(prog?.edition_be ?? 0), qual))}${
    prog?.is_continuing ? '<br>(CONTINUING PROGRAM)' : ''}</h1>` : '';

  const signs = `<div class="signs">
    <div class="sign"><div>(&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)</div>
      <div class="role">${t.registrar}</div><div class="role">${esc(issuedOn)}</div></div>
    <div class="sign"><div>(&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)</div>
      <div class="role">${t.director}</div><div class="role">${esc(issuedOn)}</div></div>
  </div>`;

  const page1 = `
<div class="page">
  ${stamps(doc)}
  ${titleBlock}
  <div class="head">
    <dl class="left">
      ${field(t.schoolCode, esc(d.institution.code))}
      ${field(t.province, '')}
      ${field(t.studentCode, esc(d.student.student_code))}
      ${field(t.name, esc(name))}
      ${field(t.ethnic, '')}
      ${field(t.birth, esc(D(d.student.birth_date)))}
      ${field(t.citizenId, esc(d.student.national_id ?? ''))}
      ${field(t.father, '')}
      ${field(t.mother, '')}
      ${field(t.progType, esc(lang === 'en' ? (prog?.type_en ?? '') : (prog?.type_th ?? '')))}
      ${field(t.progName, esc(lang === 'en' ? (prog?.name_en ?? '') : (prog?.name_th ?? '')))}
      ${field(t.progTrack, esc(lang === 'en' ? (prog?.track_en ?? '') : (prog?.track_th ?? '')))}
    </dl>
    <dl class="right">
      ${field(t.schoolName, esc(school))}
      ${field(t.prevSchool, esc(d.prior_education?.school_th ?? ''))}
      ${field(t.province, esc(d.prior_education?.province_th ?? ''))}
      ${field(t.prevLevel, esc(d.prior_education?.level_th ?? ''))}
      ${prog?.level === 'PVS'
        ? field(t.prevProgram, esc(d.prior_education?.program_th ?? '-'))
        : ''}
      ${field(t.prevYear, esc(Y(d.prior_education?.year_be)))}
      ${field(t.admitted, esc(Y(d.student.admitted_year_be)))}
      ${field(t.transferred, '-')}
      ${field(t.attempted, esc(credits(d.credits_attempted)))}
      ${field(t.earned, esc(credits(d.graduation?.credits_earned ?? d.summary?.credits_earned)))}
      ${field(t.gpax, esc(gpa(d.graduation?.gpax ?? d.summary?.gpax)))}
      ${field(t.profStd, esc(d.professional_standard?.on_date
                             ? D(d.professional_standard.on_date) : '-'))}
      ${field(t.graduated, esc(d.graduation?.completed_on
                               ? D(d.graduation.completed_on) : '-'))}
    </dl>
    <div class="photo">${t.photo}</div>
  </div>

  ${courseTable(p1, t, lang)}

  <div class="leave">${t.leftOn}<br>${t.leftWhy}</div>
  ${signs}
</div>`;

  const criteria = [1, 2, 3, 4, 5]
    .map((i) => d.institution_text?.[`transcript_criteria_${i}`])
    .map((x) => (lang === 'en' ? x?.en : x?.th))
    .filter((x) => x && x.trim() !== '');

  const notes = [1, 2, 3, 4, 5]
    .map((i) => d.institution_text?.[`transcript_note_${i}`])
    .map((x) => (lang === 'en' ? x?.en : x?.th))
    .filter((x) => x && x.trim() !== '');

  const page2 = `
<div class="page">
  ${stamps(doc)}
  ${lang === 'en' ? `<h1>TRANSCRIPT</h1>
  <h1 class="sub">${esc(t.title(Number(prog?.edition_be ?? 0), qual))}</h1>` : ''}
  <div style="display:flex;justify-content:space-between;font-size:13.5pt">
    <span>${t.name} ${esc(name)}</span>
    <span>${t.studentCode} ${esc(d.student.student_code)}</span>
    <span>${t.page2}</span>
  </div>

  ${courseTable(p2, t, lang)}

  <div class="legend">
    <div class="col1">
      <h2>${t.criteria}</h2>
      ${criteria.length
        ? criteria.map((c, i) => `<div>${i + 1}&nbsp; ${esc(c)}</div>`).join('')
        : '<div>&nbsp;</div>'}
    </div>
    <div class="col2">
      <h2>${t.notes}</h2>
      ${notes.length
        ? notes.map((n, i) => `<div>(*${i + 1})&nbsp; ${t.meaning}&nbsp; ${esc(n)}</div>`).join('')
        : '<div>&nbsp;</div>'}
    </div>
    <div class="col3">
      <h2>${t.gradeScale}</h2>
      <table><tbody>
        ${(() => {
          const out: string[] = [];
          for (let i = 0; i < GRADE_SCALE_62.length; i += 2) {
            const [a, ath, aen] = GRADE_SCALE_62[i];
            const b = GRADE_SCALE_62[i + 1];
            out.push(`<tr><td style="width:12%">${a}</td><td style="width:5%">=</td>
              <td style="width:28%">${lang === 'en' ? aen : ath}</td>
              <td style="width:12%">${b ? b[0] : ''}</td><td style="width:5%">${b ? '=' : ''}</td>
              <td>${b ? (lang === 'en' ? b[2] : b[1]) : ''}</td></tr>`);
          }
          for (const [th, en, dth, den] of GRADE_LETTERS_62) {
            out.push(`<tr><td>${lang === 'en' ? en : th}</td><td>=</td>
              <td colspan="4">${lang === 'en' ? den : dth}</td></tr>`);
          }
          return out.join('');
        })()}
      </tbody></table>
    </div>
  </div>

  <div class="memo">${t.memo}
    <div class="lines">${'.'.repeat(120)}<br>${'.'.repeat(120)}<br>${'.'.repeat(120)}<br>${'.'.repeat(120)}<br>${'.'.repeat(120)}</div>
  </div>
</div>`;

  const heading = lang === 'en'
    ? `Transcript ${doc.doc_no}`
    : `ระเบียนแสดงผลการเรียน ${doc.doc_no}`;

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<title>${esc(heading)}</title>
<style>${style(lang)}</style>
</head>
<body>
${page1}
${page2}
</body>
</html>`;
}

/**
 * ใบนี้ใช้กับหลักสูตรรุ่นก่อน 67 ที่จัดกลุ่มตามภาคเรียน
 *
 * ตัดสินจาก `term_tree` ที่ 0060 ตรึงลง payload ไม่ใช่จากรุ่นหลักสูตรอย่างเดียว
 * เพราะใบที่ออกก่อน 0060 ไม่มีโครงนี้เลย ถ้าเลือกจากรุ่นอย่างเดียว การพิมพ์ซ้ำ
 * ใบเก่าจะได้ตารางเปล่าโดยไม่มีอะไรฟ้อง — ให้ตกไปใช้แม่แบบเดิมแทน
 *
 * ─── ตรวจว่า "มีคีย์" ไม่ใช่ "มีสมาชิก" ───
 * นักศึกษาที่ยังไม่มีผลการเรียนสักวิชาก็ได้ `[]` มาอย่างถูกต้อง ถ้าตัดสิน
 * ด้วยความยาว ใบของคนกลุ่มนั้นจะไปได้แม่แบบเดิมทั้งที่หลักสูตรเป็นรุ่น 62
 * — ได้ใบผิดแบบให้กับคนที่ขอใบระหว่างเรียน ซึ่งเป็นกรณีที่พบบ่อยกว่าคนจบ
 */
export function has62TermTree(payload: { term_tree?: unknown }): boolean {
  return Array.isArray(payload.term_tree);
}

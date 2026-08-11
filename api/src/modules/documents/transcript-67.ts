/**
 * ใบ รบ. ตระกูลหลักสูตร 67 — ปวช. และ ปวส. ทั้งฉบับไทยและอังกฤษ
 *
 * ═══ ตัวเลขทั้งหมดวัดจากไฟล์จริง ไม่ได้เดา ═══
 * วัดจาก PDF ที่ SISA ออกให้จริงด้วย PyMuPDF (ดู docs/transcript-formats.md)
 *   A4 แนวตั้ง 595 × 842 pt · ขอบ ซ้าย 23.4 บน 27.4 ขวา 23.8 ล่าง 42.2
 *   ฟอนต์ TH Sarabun New — เนื้อหา 12 pt · ชื่อเรื่อง 16 pt
 *   ขอบคอลัมน์ครึ่งซ้าย x = 24 · 65 · 113 · 250 · 274 · 298
 *   → ภาคเรียน/ปี 41 · รหัสวิชา 47 · ชื่อวิชา 136 · หน่วยกิต 23 · ผลการเรียน 23
 *   ครึ่งขวาสมมาตร เริ่มที่ 300
 *
 * ═══ ทำไมสองหน้าตายตัว ไม่ใช่ "ล้นแล้วขึ้นหน้าใหม่" ═══
 * หน้า 2 ของใบจริงมีของประจำที่อยู่ตายตัว — สรุปรายภาคเรียน · ระดับผลการเรียน ·
 * ตัวอักษรแสดงระดับผลการเรียน · เกณฑ์การสำเร็จหลักสูตร · หมายเหตุ · ช่องบันทึก
 * ถ้าทำเป็นการไหลต่อเนื่อง ของเหล่านี้จะไปโผล่หน้า 3 เมื่อรายวิชาเยอะ
 * แล้วใบจะไม่ใช่ใบเดียวกับที่ สอศ. รับ
 *
 * ═══ ทำไมแม่แบบไม่คำนวณอะไรเลย ═══
 * คะแนนเฉลี่ยรายกลุ่มและรายหมวดมาจาก `transcript_category_tree()` ใน 0058
 * ซึ่งตรึงลง payload ตั้งแต่วันที่ออก ถ้าแม่แบบรวมเอง จะกลายเป็นสูตรชุดที่สอง
 * ที่ค่อย ๆ เพี้ยนไปจากตัวเลขที่ระบบใช้ตัดสินการจบจริง (หลักข้อ 1 และ 5)
 *
 * ═══ ช่องที่ยังว่างโดยรู้ตัว ═══
 * เลขประจำตัวประชาชน · หน่วยกิตที่รับโอน · กลุ่มอาชีพ · รูปถ่าย —
 * ระบบยังไม่มีที่เก็บ (ดู docs/transcript-formats.md) แม่แบบจึงพิมพ์หัวข้อ
 * ไว้พร้อมเส้นว่าง **ไม่ใช่ซ่อนหัวข้อทิ้ง** เพราะใบที่ขาดหัวข้อไปเลยดูเหมือน
 * ใบคนละแบบ ส่วนใบที่มีหัวข้อแต่ค่าว่างบอกได้ว่ายังกรอกไม่ครบ
 */
import type { IssuedDocument } from './templates';
import { engDate, engYear, thaiDate } from './templates';

/* ─── ชนิดข้อมูลของ payload ที่ 0057/0058 สร้าง ─────────────────── */

interface Course67 {
  term_label: string;
  year_be: number;
  term_ordinal: number;
  code: string;
  name_th: string;
  name_en: string;
  credits: string | number;
  grade: string;
  grade_point: string | number | null;
  credits_earned: string | number | null;
  /**
   * ตั้งแต่ 0060 — บอกว่ารายวิชานี้ถูกนับใน GPA ที่พิมพ์อยู่บนใบเดียวกันหรือไม่
   * (เป็น "และ" ของ grade_symbol.counts_in_gpa กับ enrollment.counts_toward_gpa)
   */
  counts_in_gpa?: boolean;
}

/**
 * สรุปรายภาคจาก `transcript_term_tree()` (0060)
 *
 * ต่างจาก `term_summaries` ตรงที่มี `credits_cum` ซึ่งเป็นตัวเลขที่หน้า 2
 * ของใบจริงพิมพ์คู่กับหน่วยกิตรายภาคเสมอ และเป็นตัวที่แม่แบบนี้เคยพิมพ์ผิด
 */
interface TermNode {
  year_be: number;
  ordinal: number;
  credits_earned: string | number | null;
  credits_cum: string | number | null;
  gpa: string | number | null;
  gpax: string | number | null;
}

interface Group67 {
  code: string;
  name_th: string;
  min_credits: string | number | null;
  credits_earned: string | number;
  gpa: string | number | null;
  courses: Course67[];
}

interface Head67 {
  code: string;
  name_th: string;
  min_credits: string | number | null;
  credits_earned: string | number;
  gpa: string | number | null;
  groups: Group67[];
}

interface TermSummary {
  year_be: number;
  ordinal: number;
  label: string;
  gpa: string | number | null;
  gpax: string | number | null;
  credits_earned: string | number | null;
}

export interface Transcript67Payload {
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
  term_summaries: TermSummary[];
  term_tree?: TermNode[];
  category_tree: Head67[];
  prior_education?: {
    level_th: string; school_th: string; province_th: string;
    program_th: string; year_be: number | null; gpax: string | number | null;
  } | null;
  /** หน่วยกิตที่ลงเรียน — คนละตัวกับหน่วยกิตที่ได้ (0060) */
  credits_attempted?: string | number | null;
  institution_text?: Record<string, { th: string; en: string }>;
  professional_standard?: { no: string; passed: boolean | null; on_date: string | null };
}

export interface Transcript67Document extends Omit<IssuedDocument, 'payload'> {
  payload: Transcript67Payload;
}

/* ─── ตัวช่วย ────────────────────────────────────────────────────── */

/** ปีหลักสูตรบนหัวใบเป็นเลขสองหลัก — ใบจริงพิมพ์ "รบ.1 ปวช.67" */
function edition2(v: unknown): string {
  const n = Number(v);
  return Number.isFinite(n) ? String(n % 100).padStart(2, '0') : '';
}

/**
 * ข้อความมุมขวาบน — คนละรูปแบบกันสองภาษา
 *
 * ฉบับไทย  "รบ.1 ปวช.67 เลขที่ <เลข>/"
 * ฉบับอังกฤษ "Cert. Transcript No. <เลข>/"  (วัดจากไฟล์จริงทั้ง ปวช. และ ปวส.)
 *
 * ─── ที่จงใจไม่ทำตามต้นฉบับ ───
 * ใบ ปวส. ของ SISA พิมพ์มุมขวาบนว่า "รบ.1 **ปวช.**67" เหมือนใบ ปวช. ทุกตัวอักษร
 * ซึ่งเป็นข้อผิดพลาดของตัวโปรแกรม — ใบ ปวส. ที่ประทับว่าเป็น รบ. ของ ปวช.
 * ทำให้เอกสารขัดแย้งกับหัวเรื่องของตัวเอง ที่นี่จึงใช้ตัวย่อตามระดับจริง
 */
function docCorner(
  prog: { qualification_abbr_th?: string; level?: string; edition_be?: number } | null,
  lang: 'th' | 'en',
  docNo: string,
): string {
  if (lang === 'en') {
    const kind = prog?.level === 'PVS' ? 'Dip.' : 'Cert.';
    return `${kind} Transcript No. ${esc(docNo)}/`;
  }
  return `รบ.1 ${esc(prog?.qualification_abbr_th ?? '')}${esc(edition2(prog?.edition_be))}`
    + ` เลขที่ ${esc(docNo)}/`;
}

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
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function gpa(v: unknown): string {
  if (v === null || v === undefined || v === '') return '-';
  return Number(v).toFixed(2);
}

/**
 * ผลการเรียนบนใบ
 *
 * วิชาที่ได้ ผ./ม.ผ. ไม่มีแต้ม ใบจริงจึงพิมพ์สัญลักษณ์แทนตัวเลข —
 * ถ้าแปลงเป็น 0 จะอ่านได้ว่าตก ซึ่งคนละเรื่องกับผ่านแบบไม่คิดแต้ม
 */
function gradeCell(c: Course67): string {
  if (c.grade_point === null || c.grade_point === undefined) return esc(c.grade);
  const n = Number(c.grade_point);
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

const L = {
  th: {
    title: (edition: number, q: string) => `ระเบียนแสดงผลการเรียนตามหลักสูตร${q} พุทธศักราช ${edition}`,
    prevProgram: 'สาขาวิชาเดิม',
    schoolCode: 'รหัสสถานศึกษา', schoolName: 'ชื่อสถานศึกษา', province: 'จังหวัด',
    studentCode: 'รหัสประจำตัว', name: 'ชื่อ - ชื่อสกุล',
    ethnic: 'เชื้อชาติ    สัญชาติ    ศาสนา', birth: 'วัน เดือน ปีเกิด',
    citizenId: 'เลขประจำตัวประชาชน', father: 'ชื่อบิดา', mother: 'ชื่อมารดา',
    progType: 'ประเภทวิชา', careerGroup: 'กลุ่มอาชีพ', progName: 'สาขาวิชา',
    prevSchool: 'สถานศึกษาเดิม', prevLevel: 'ระดับการศึกษาที่จบ',
    prevYear: 'ปีการศึกษาที่จบ', admitted: 'เข้าศึกษาเมื่อ',
    transferred: 'หน่วยกิตที่รับโอน', attempted: 'หน่วยกิตที่เรียน',
    earned: 'หน่วยกิตที่ได้', gpax: 'ระดับคะแนนเฉลี่ยสะสม',
    profStd: 'ผ่านเกณฑ์การประเมินมาตรฐานวิชาชีพเมื่อ', graduated: 'สำเร็จการศึกษาเมื่อ',
    photo: 'รูปถ่าย<br>2.5 × 3 ซม.',
    colTerm: 'ภาคเรียน/<br>ปีการศึกษา', colCode: 'รหัสวิชา', colName: 'ชื่อวิชา',
    colCredit: 'หน่วย<br>กิต', colGrade: 'ผล<br>การ<br>เรียน',
    unitCredit: 'หน่วยกิต',
    reqCredits: 'จำนวนหน่วยกิตตามหลักสูตร', gotCredits: 'จำนวนหน่วยกิตที่ได้',
    groupGpa: 'คะแนนเฉลี่ยสะสม', headGpa: 'คะแนนเฉลี่ยสะสม',
    leftOn: 'ออกจากสถานศึกษาเมื่อ', leftWhy: 'เหตุที่ออก',
    registrar: 'หัวหน้างานทะเบียน', director: 'ผู้อำนวยการ',
    signDate: 'วันที่    เดือน    พ.ศ.',
    page2: 'หน้าที่ 2',
    termCredits: 'หน่วยกิตที่ได้ในภาค', cumCredits: 'หน่วยกิตสะสม',
    termGpa: 'คะแนนเฉลี่ยในภาค', cumGpa: 'คะแนนเฉลี่ยสะสม',
    gradeScale: 'ระดับผลการเรียน', gradeLetters: 'ตัวอักษรแสดงระดับผลการเรียน',
    criteria: 'เกณฑ์การสำเร็จหลักสูตร', notes: 'หมายเหตุ', memo: 'บันทึก',
  },
  en: {
    /*
     * ─── ฉบับอังกฤษใช้ปีคริสต์ศักราช ไม่ใช่ พ.ศ. ───
     * ใบจริงพิมพ์ "2024 CURRICULUM OF THE …" ซึ่งเป็นข้อที่เดาไม่ถูก
     * ถ้าไม่ได้เปิดไฟล์ดู — แปลง พ.ศ. เป็น ค.ศ. ที่นี่ที่เดียว
     */
    title: (edition: number, q: string) => `${edition - 543} CURRICULUM OF THE ${q}`,
    prevProgram: 'Previous Field of Study',
    schoolCode: 'School Code', schoolName: 'School Name', province: 'Province',
    studentCode: 'Student ID', name: 'Name - Surname',
    ethnic: 'Ethnicity    Nationality    Religion', birth: 'Date of Birth',
    citizenId: 'Citizen ID', father: "Father's Name", mother: "Mother's Name",
    progType: 'Type of Program', careerGroup: 'Career Group', progName: 'Field of Study',
    prevSchool: 'Previous School', prevLevel: 'Entry Qualification',
    prevYear: 'Year Completed', admitted: 'Date of Admission',
    transferred: 'Credits Transferred', attempted: 'Credits Attempted',
    earned: 'Credits Earned', gpax: 'Cumulative G.P.A.',
    profStd: 'Professional Standard Passed On', graduated: 'Date of Graduation',
    photo: 'Photo<br>2.5 × 3 cm.',
    colTerm: 'Semester/<br>Academic Year', colCode: 'Course No.', colName: 'Course Title',
    colCredit: 'Credit<br>Hours', colGrade: 'Grade<br>Earned',
    unitCredit: 'credits',
    reqCredits: 'Required credits', gotCredits: 'Credits earned',
    groupGpa: 'Group G.P.A.', headGpa: 'Category G.P.A.',
    leftOn: 'Date of Leaving', leftWhy: 'Reason for Leaving',
    registrar: 'Registrar', director: 'Director',
    signDate: 'Date    Month    Year',
    page2: 'Page 2',
    termCredits: 'Credits earned', cumCredits: 'Cumulative credits',
    termGpa: 'G.P.A.', cumGpa: 'Cumulative G.P.A.',
    gradeScale: 'Grading System', gradeLetters: 'Grade Symbols',
    criteria: 'Graduation Requirements', notes: 'Remarks', memo: 'Notes',
  },
} as const;

const GRADE_SCALE: [string, string, string][] = [
  ['4.0', 'ดีเยี่ยม', 'Excellent'],
  ['3.5', 'ดีมาก', 'Very Good'],
  ['3.0', 'ดี', 'Good'],
  ['2.5', 'ค่อนข้างดี', 'Fairly Good'],
  ['2.0', 'พอใช้', 'Fair'],
  ['1.5', 'ค่อนข้างอ่อน', 'Poor'],
  ['1.0', 'อ่อน', 'Very Poor'],
  ['0', 'ตก', 'Failed'],
];

/**
 * ตัวอักษรแสดงระดับผลการเรียน — สัญลักษณ์ไทย · สัญลักษณ์อังกฤษ · คำอธิบายทั้งคู่
 *
 * ─── ฉบับอังกฤษเคยพิมพ์สัญลักษณ์ไทยล้วน ───
 * ตารางนี้เคยมีแค่สองช่อง (สัญลักษณ์ไทย + คำอธิบายไทย) ใบ รบ. ฉบับอังกฤษ
 * จึงพิมพ์ "ข.ร. = ขาดเรียน…" อยู่กลางหน้าที่เหลือเป็นภาษาอังกฤษทั้งหมด
 * ซึ่งทำให้ส่วนที่ **อธิบายความหมายของเกรด** เป็นส่วนเดียวที่ผู้อ่านชาว
 * ต่างชาติอ่านไม่ออก — คือส่วนที่เขาต้องการที่สุดพอดี
 *
 * รหัสอังกฤษได้จากการเทียบไฟล์ฉบับอังกฤษกับฉบับไทยบรรทัดต่อบรรทัด
 * ไม่ใช่การแปลเอง เพราะรหัสที่ไม่ตรงกับใบที่หน่วยงานอื่นเคยเห็นจะอ่านไม่ออก
 */
const GRADE_LETTERS: [string, string, string, string][] = [
  ['ข.ร.', 'I.C.', 'ขาดเรียน ไม่มีสิทธิ์วัดผลสัมฤทธิ์ปลายภาคเรียน', 'Insufficient class attendance'],
  ['ข.ป.', 'I.P.', 'ขาดการปฏิบัติงาน', 'Incomplete practical assignment'],
  ['ข.ส.', 'I.L.', 'ขาดการวัดผลสัมฤทธิ์ปลายภาคเรียน', 'Incomplete learning assessment'],
  ['ท.', 'C.', 'ทุจริต', 'Cheating'],
  ['ผ.', 'P.', 'ผ่าน', 'Pass'],
  ['ม.ผ.', 'F.', 'ไม่ผ่าน', 'Fail'],
  ['ถ.น.', 'W.W.', 'ถอนรายวิชาภายในกำหนด', 'Withdraw within time line'],
  ['ถ.ล.', 'W.A.', 'ถอนรายวิชาหลังกำหนด', 'Withdraw after date line'],
  ['ม.ส.', 'N.C.', 'ไม่สมบูรณ์', 'Not complete'],
  ['ม.ท.', 'U.T.', 'ไม่สามารถเข้าวัดผลสัมฤทธิ์ปลายภาคเรียนทดแทน', 'Unable to undertake substitute assessment'],
  ['ม.ก.', 'N.Cr', 'ไม่นับหน่วยกิตเพื่อสำเร็จการศึกษา', 'Non-credit'],
];

/* ─── สไตล์ที่ตรงกับตัวเลขที่วัดมา ──────────────────────────────── */

const STYLE = `
  @page { size: A4 portrait; margin: 27pt 24pt 42pt 23pt; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', 'Tahoma', sans-serif;
    font-size: 12pt; line-height: 1.25; color: #000;
  }
  .page { position: relative; page-break-after: always; }
  .page:last-child { page-break-after: auto; }
  .docno { text-align: right; font-size: 12pt; }
  h1 { font-size: 16pt; font-weight: 700; text-align: center; margin: 4pt 0 8pt; }
  .head { display: grid; grid-template-columns: 1fr 1fr 100pt; gap: 0 10pt; font-size: 12pt; }
  .head dl { margin: 0; display: grid; grid-template-columns: 120pt 1fr; row-gap: 1.5pt; }
  .head dt { color: #000; }
  .head dd { margin: 0; }
  .photo {
    border: 0.8pt solid #000; height: 92pt; display: flex;
    align-items: center; justify-content: center; text-align: center;
    font-size: 11pt; margin-top: 24pt;
  }
  table.courses {
    width: 100%; border-collapse: collapse; margin-top: 8pt;
    table-layout: fixed;
  }
  table.courses th, table.courses td {
    border: 0.8pt solid #000; padding: 0 2pt; vertical-align: top;
  }
  table.courses th { text-align: center; font-weight: 400; font-size: 11.5pt; }
  /* ความกว้างจากที่วัดมา: 41 · 47 · 136 · 23 · 23 (รวมครึ่งละ 270 pt) */
  col.c-term   { width: 41pt; }
  col.c-code   { width: 47pt; }
  col.c-name   { width: auto; }
  col.c-credit { width: 23pt; }
  col.c-grade  { width: 23pt; }
  td.term, td.credit, td.grade { text-align: center; }
  /* หัวข้อหมวด/กลุ่ม และบรรทัดสรุป อยู่ในคอลัมน์ชื่อวิชาโดยไม่มีเส้นคั่น */
  .cat-head { text-align: center; font-weight: 700; }
  .grp-head { font-weight: 700; }
  .sum { }
  .foot-note { font-size: 11.5pt; }
  .leave { margin-top: 4pt; font-size: 12pt; }
  .stamp {
    position: fixed; top: 38%; left: 0; right: 0; text-align: center;
    font-size: 90pt; font-weight: 700; letter-spacing: 0.15em;
    transform: rotate(-22deg); pointer-events: none;
  }
  .stamp.void { color: rgba(190, 0, 0, 0.18); }
  .stamp.copy { color: rgba(0, 0, 0, 0.10); }
  .void-note {
    border: 1.5pt solid #b00; color: #b00; padding: 3pt 6pt;
    margin-bottom: 5pt; font-size: 12pt;
  }
  .signs { display: flex; justify-content: space-around; margin-top: 14pt; }
  .sign { text-align: center; min-width: 40%; }
  .legend { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 0 12pt; margin-top: 8pt; }
  .legend h2 { font-size: 12pt; font-weight: 700; margin: 0 0 2pt; }
  .legend table { width: 100%; border-collapse: collapse; font-size: 11.5pt; }
  .legend td { border: none; padding: 0; }
  .letters { margin-top: 6pt; }
  .letters h2 { font-size: 12pt; font-weight: 700; margin: 0 0 2pt; }
  .letters table { width: 100%; border-collapse: collapse; font-size: 11pt; }
  .letters td { border: none; padding: 0 6pt 0 0; }
  .memo { margin-top: 6pt; }
  .memo .lines div { border-bottom: 0.6pt dotted #000; height: 13pt; }
  @media screen {
    body { background: #f4f4f4; padding: 14px; }
    .page { background: #fff; width: 595pt; min-height: 842pt;
            margin: 0 auto 14px; padding: 27pt 24pt 42pt 23pt;
            box-shadow: 0 1px 6px rgba(0,0,0,.25); }
  }`;

/* ─── ชิ้นส่วน ───────────────────────────────────────────────────── */

/**
 * แปลงโครงหมวด/กลุ่มเป็นแถวของตาราง
 *
 * แถวมีสี่ชนิด — หัวหมวด · หัวกลุ่ม · รายวิชา · บรรทัดสรุป — ทั้งหมด
 * ใช้จำนวนคอลัมน์เดียวกันเพื่อให้ไหลข้ามสองคอลัมน์ของหน้าได้โดยไม่เพี้ยน
 */
type Row =
  | { t: 'cat'; text: string }
  | { t: 'grp'; text: string }
  | { t: 'course'; c: Course67 }
  | { t: 'sum'; text: string };

function buildRows(tree: Head67[], lang: 'th' | 'en'): Row[] {
  const t = L[lang];
  const rows: Row[] = [];
  tree.forEach((head, hi) => {
    rows.push({ t: 'cat', text: `${hi + 1}. ${head.name_th}` });
    for (const g of head.groups) {
      // กลุ่มที่ชื่อซ้ำกับหมวด แปลว่าไม่มีกลุ่มย่อยจริง — ไม่ต้องพิมพ์ซ้ำ
      if (g.name_th !== head.name_th) rows.push({ t: 'grp', text: g.name_th });
      for (const c of g.courses) rows.push({ t: 'course', c });
      if (g.min_credits != null) {
        rows.push({ t: 'sum', text: `${t.reqCredits} ${credits(g.min_credits)} ${t.unitCredit}` });
      }
      rows.push({ t: 'sum', text: `${t.gotCredits} ${credits(g.credits_earned)} ${t.unitCredit}` });
      if (g.gpa != null) {
        rows.push({ t: 'sum', text: `${t.groupGpa}${g.name_th} ${gpa(g.gpa)}` });
      }
    }
    if (head.gpa != null) {
      rows.push({ t: 'sum', text: `${t.headGpa}${hi + 1}. ${head.name_th} ${gpa(head.gpa)}` });
    }
  });
  return rows;
}

/**
 * ช่อง "ภาคเรียน/ปีการศึกษา" — ฉบับอังกฤษใช้ปีคริสต์ศักราช
 *
 * ─── ข้อนี้ไฟล์ต้นฉบับทำไม่ตรงกันเอง ───
 * ใบ ปวช.67 ฉบับอังกฤษของ SISA พิมพ์ "1/2568" คือปีพุทธศักราช ทั้งที่
 * ใบเดียวกันแปลง `Date of Birth` เป็น "April 5, 2009" · `Year of Graduated`
 * เป็น "2024" และหัวเรื่องเป็น "2024 CURRICULUM" — คือแปลงทุกที่ยกเว้นตรงนี้
 * และใบตระกูล 62 ฉบับอังกฤษของระบบเดียวกันก็แปลง ("Academic year 2025")
 *
 * เมื่อสองอย่างในเอกสารเดียวกันขัดกัน ต้องเลือกข้างที่ทำให้ทั้งใบอ่านได้
 * เป็นชุดเดียว — ไม่อย่างนั้นผู้อ่านจะเห็นปี 2568 คู่กับปี 2024 บนกระดาษ
 * แผ่นเดียวแล้วไม่รู้ว่าอันไหนคือเวลาจริง
 */
function termCell(c: Course67, lang: 'th' | 'en'): string {
  const year = lang === 'en' ? Number(c.year_be) - 543 : Number(c.year_be);
  return `${c.term_ordinal}/${year}`;
}

function renderRow(r: Row, lang: 'th' | 'en'): string {
  if (r.t === 'course') {
    const c = r.c;
    const name = lang === 'en' && c.name_en ? c.name_en : c.name_th;
    return `<tr>
      <td class="term">${esc(termCell(c, lang))}</td>
      <td>${esc(c.code)}</td>
      <td>${esc(name)}</td>
      <td class="credit">${esc(c.grade_point === null || c.grade_point === undefined
                                 ? '-' : credits(c.credits))}</td>
      <td class="grade">${esc(gradeCell(c))}</td>
    </tr>`;
  }
  const cls = r.t === 'cat' ? 'cat-head' : r.t === 'grp' ? 'grp-head' : 'sum';
  return `<tr><td></td><td></td><td class="${cls}" colspan="3">${esc(r.text)}</td></tr>`;
}

function courseTable(rows: Row[], lang: 'th' | 'en'): string {
  const t = L[lang];
  const half = Math.ceil(rows.length / 2);
  const cols = `
    <colgroup>
      <col class="c-term"><col class="c-code"><col class="c-name">
      <col class="c-credit"><col class="c-grade">
    </colgroup>`;
  const head = `
    <tr>
      <th>${t.colTerm}</th><th>${t.colCode}</th><th>${t.colName}</th>
      <th>${t.colCredit}</th><th>${t.colGrade}</th>
    </tr>`;

  return `<table class="courses" style="width:49.6%;float:left">
    ${cols}<thead>${head}</thead>
    <tbody>${rows.slice(0, half).map((r) => renderRow(r, lang)).join('')}</tbody>
  </table>
  <table class="courses" style="width:49.6%;float:right">
    ${cols}<thead>${head}</thead>
    <tbody>${rows.slice(half).map((r) => renderRow(r, lang)).join('')}</tbody>
  </table>
  <div style="clear:both"></div>`;
}

/**
 * ตราประทับยกเลิกและสำเนา
 *
 * ─── ทำไมใบที่ยกเลิกแล้วต้องยังพิมพ์ได้ ───
 * เพราะต้องพิสูจน์ย้อนหลังได้ว่าเคยออกอะไรไป และใบที่ยกเลิกอาจอยู่ในมือ
 * คนอื่นแล้ว การซ่อนไม่ให้พิมพ์ทำให้ตรวจสอบไม่ได้ — แต่ต้องมองปราดเดียว
 * รู้ว่ายกเลิก ไม่ใช่รู้ตอนอ่านตัวเล็กท้ายกระดาษ
 */
function stamps(doc: Transcript67Document): string {
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

/**
 * สรุปรายภาคเรียนท้ายหน้า 2
 *
 * ─── ข้อผิดพลาดที่เพิ่งแก้ (0060) ───
 * แม่แบบนี้เคยพิมพ์ "หน่วยกิตที่ได้ในภาค" กับ "หน่วยกิตสะสม" จากค่าเดียวกัน
 * คือ `credits_earned` ของภาคนั้น ภาคที่สองจึงพิมพ์ 11/11 แทนที่จะเป็น 11/28
 * — ตัวเลขผิดบนเอกสารที่แก้ไม่ได้ ไม่มีอะไรฟ้องเพราะทั้งคู่ดูสมเหตุสมผล
 *
 * ค่าสะสมมาจาก `term_tree` ที่ฐานข้อมูลคำนวณให้ ไม่ใช่แม่แบบบวกเอง
 * (หลักข้อ 1 — ถ้าบวกเอง จะกลายเป็นสูตรชุดที่สองที่ค่อย ๆ เพี้ยน)
 * ใบที่ออกก่อน 0060 ไม่มี `term_tree` จึงตกไปใช้ `term_summaries` เดิม
 * แล้วพิมพ์ "-" ในช่องสะสม — บอกว่า "ไม่รู้" ดีกว่าพิมพ์ตัวเลขที่รู้ว่าผิด
 */
function termLines(
  d: Transcript67Payload,
  lang: 'th' | 'en',
  t: typeof L['th'] | typeof L['en'],
): string {
  const label = (year: number, ordinal: number) =>
    lang === 'en'
      ? `Semester ${ordinal} / ${year - 543}`
      : `ภาคเรียนที่ ${ordinal} ปีการศึกษา ${year}`;

  const rows = (d.term_tree ?? []).length > 0
    ? (d.term_tree ?? []).map((s) => ({
        label: label(s.year_be, s.ordinal),
        earned: s.credits_earned, cum: s.credits_cum, gpa: s.gpa, gpax: s.gpax,
      }))
    : (d.term_summaries ?? [])
        .slice()
        .sort((a, b) => a.year_be - b.year_be || a.ordinal - b.ordinal)
        .map((s) => ({
          label: s.label, earned: s.credits_earned, cum: null, gpa: s.gpa, gpax: s.gpax,
        }));

  return rows
    .map(
      (s) => `<div style="text-align:center;font-weight:700">${esc(s.label)}</div>
        <div style="text-align:center">${t.termCredits} ${esc(credits(s.earned))}
          ${t.cumCredits} ${esc(credits(s.cum))}</div>
        <div style="text-align:center">${t.termGpa} ${esc(gpa(s.gpa))}
          ${t.cumGpa} ${esc(gpa(s.gpax))}</div>`,
    )
    .join('');
}

function signBlock(t: typeof L['th'] | typeof L['en'], issuedOn: string): string {
  return `<div class="signs">
    <div class="sign"><div>(&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)</div>
      <div>${t.registrar}</div><div>${esc(issuedOn)}</div></div>
    <div class="sign"><div>(&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)</div>
      <div>${t.director}</div><div>${esc(issuedOn)}</div></div>
  </div>`;
}

/* ─── ตัวหลัก ────────────────────────────────────────────────────── */

export function renderTranscript67(doc: Transcript67Document): string {
  const d = doc.payload;
  const lang: 'th' | 'en' = d.lang === 'en' ? 'en' : 'th';
  const t = L[lang];
  const prog = d.program;

  const name = lang === 'en' ? (d.student.full_name_en || d.student.full_name_th)
                             : d.student.full_name_th;
  const school = lang === 'en' ? (d.institution.name_en || d.institution.name_th)
                               : d.institution.name_th;
  /*
   * ─── ชื่อคุณวุฒิบนหัวเรื่องต่างจากในบล็อกหัว ───
   * หัวเรื่องของใบจริงใช้ถ้อยคำเฉพาะ (CERTIFICATE / DIPLOMA IN VOCATIONAL
   * EDUCATION) และเติม "(ต่อเนื่อง)" ให้หลักสูตรต่อเนื่องเฉพาะฉบับไทย
   * — ฉบับอังกฤษของ ปวส. ต่อเนื่องใช้ชื่อเดียวกับ ปวส. ปกติ (วัดจากไฟล์จริง)
   */

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

  /*
   * ─── ฉบับอังกฤษของหลักสูตรต่อเนื่องมีบรรทัดที่สอง ───
   * ผมเคยสรุปผิดใน 0059 ว่าฉบับอังกฤษของ ปวส. ต่อเนื่องใช้ชื่อเดียวกับ
   * ปวส. ปกติ — เปิดไฟล์ดูละเอียดแล้วมีบรรทัด "(CONTINUING PROGRAM)"
   * อยู่ใต้ชื่อเรื่องอีกบรรทัด ถ้าไม่มี ใบจะไม่ได้บอกเลยว่าเป็นหลักสูตร
   * ต่อเนื่อง ทั้งที่ฉบับไทยบอกด้วยคำว่า "(ต่อเนื่อง)" ในชื่อเรื่อง
   */
  const titleBlock = `<h1>${esc(t.title(Number(prog?.edition_be ?? 0), qual))}${
    lang === 'en' && prog?.is_continuing ? '<br>(CONTINUING PROGRAM)' : ''}</h1>`;

  const rows = buildRows(d.category_tree ?? [], lang);
  // แบ่งสองหน้าตามใบจริง — กิจกรรมเสริมหลักสูตรและบรรทัดสรุปท้ายอยู่หน้า 2
  const perPage = 96;
  const p1 = rows.slice(0, perPage);
  const p2 = rows.slice(perPage);

  const field = (label: string, value: string) =>
    `<dt>${label}</dt><dd>${value}</dd>`;

  // ใบจริงเว้นบรรทัดวันที่ไว้ให้เขียนมือ แต่ระบบรู้วันที่อยู่แล้ว
  // การพิมพ์ลงไปทำให้ใบที่พิมพ์ซ้ำในอีกห้าปียังบอกได้ว่าออกเมื่อไร
  const issuedOn = `${lang === 'en' ? 'Issued on' : 'ออกให้เมื่อ'} ${D(doc.issued_on)}`;

  const page1 = `
<div class="page">
  ${stamps(doc)}
  <div class="docno">${docCorner(prog, lang, doc.doc_no)}</div>
  ${titleBlock}

  <div class="head">
    <dl>
      ${field(t.schoolCode, esc(d.institution.code))}
      ${field(t.schoolName, esc(school))}
      ${field(t.province, '')}
      ${field(t.studentCode, esc(d.student.student_code))}
      ${field(t.name, esc(name))}
      ${field(t.ethnic, '')}
      ${field(t.birth, esc(D(d.student.birth_date)))}
      ${field(t.citizenId, esc(d.student.national_id ?? ''))}
      ${field(t.father, '')}
      ${field(t.mother, '')}
      ${field(t.progType, esc(lang === 'en' ? (prog?.type_en ?? '') : (prog?.type_th ?? '')))}
      ${field(t.careerGroup, '')}
      ${field(t.progName, esc(lang === 'en' ? (prog?.name_en ?? '') : (prog?.name_th ?? '')))}
    </dl>
    <dl>
      ${field(t.prevSchool, esc(d.prior_education?.school_th ?? ''))}
      ${field(t.province, esc(d.prior_education?.province_th ?? ''))}
      ${field(t.prevLevel, esc(d.prior_education?.level_th ?? ''))}
      ${/*
          ปวส. มีช่อง "สาขาวิชาเดิม" เพิ่มมาหนึ่งช่องที่ ปวช. ไม่มี
          เพราะผู้เข้า ปวส. จบ ปวช. มา สาขาเดิมจึงมีความหมายกับการเทียบโอน
        */ ''}
      ${prog?.level === 'PVS'
        ? field(t.prevProgram, esc(d.prior_education?.program_th ?? '-'))
        : ''}
      ${field(t.prevYear, esc(Y(d.prior_education?.year_be)))}
      ${field(t.admitted, esc(Y(d.student.admitted_year_be)))}
      ${field(t.transferred, '-')}
      ${/*
          "หน่วยกิตที่เรียน" กับ "หน่วยกิตที่ได้" เป็นคนละตัวเลข — เคยพิมพ์
          ค่าเดียวกันสองครั้ง ทำให้ทุกใบบอกว่าไม่เคยตกและไม่เคยถอนรายวิชา
        */ ''}
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

  ${courseTable(p1, lang)}

  <div class="leave">${t.leftOn}<br>${t.leftWhy}</div>
  ${signBlock(t, issuedOn)}
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
  ${titleBlock}
  <div style="display:flex;justify-content:space-between;font-size:12pt">
    <span>${t.name} ${esc(name)}</span>
    <span>${t.studentCode} ${esc(d.student.student_code)}
      ${docCorner(prog, lang, doc.doc_no)}</span>
    <span>${t.page2}</span>
  </div>

  ${p2.length > 0 ? courseTable(p2, lang) : ''}

  <div style="margin-top:6pt">
    ${termLines(d, lang, t)}
  </div>

  <div class="legend">
    <div>
      <h2>${t.gradeScale}</h2>
      <table><tbody>
        ${GRADE_SCALE.map(
          ([n, th, en]) => `<tr><td style="width:34pt">${n}</td><td>= ${lang === 'en' ? en : th}</td></tr>`,
        ).join('')}
      </tbody></table>
    </div>
    <div>
      <h2>${t.criteria}</h2>
      ${criteria.length
        ? criteria.map((c, i) => `<div>${i + 1}. ${esc(c)}</div>`).join('')
        : `<div style="color:#555">— ยังไม่ได้ตั้งเกณฑ์การสำเร็จหลักสูตรของสถานศึกษา —</div>`}
    </div>
    <div>
      <h2>${t.notes}</h2>
      ${notes.map((n, i) => `<div>(*${i + 1}) ${esc(n)}</div>`).join('')}
    </div>
  </div>

  <div class="letters">
    <h2>${t.gradeLetters}</h2>
    <table><tbody>
      ${(() => {
        const cells = GRADE_LETTERS.map(
          ([kth, ken, vth, ven]) =>
            `<td>${lang === 'en' ? `${ken} = ${ven}` : `${kth} = ${vth}`}</td>`,
        );
        const out: string[] = [];
        for (let i = 0; i < cells.length; i += 3) {
          out.push(`<tr>${cells.slice(i, i + 3).join('')}</tr>`);
        }
        return out.join('');
      })()}
    </tbody></table>
  </div>

  <div class="memo">
    <h2 style="font-size:12pt;font-weight:700;margin:0">${t.memo}</h2>
    <div class="lines"><div></div><div></div><div></div><div></div><div></div></div>
  </div>

  ${signBlock(t, issuedOn)}
</div>`;

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<title>${esc(lang === 'en' ? 'Transcript' : 'ระเบียนแสดงผลการเรียน')} ${esc(doc.doc_no)}</title>
<style>${STYLE}</style>
</head>
<body>
${page1}
${page2}
</body>
</html>`;
}

/**
 * ใบนี้ใช้กับหลักสูตรรุ่น 67 เท่านั้น
 *
 * รุ่นอื่นจัดกลุ่มรายวิชาคนละแบบ (ตระกูล 62 จัดตามภาคเรียนและมีคอลัมน์
 * ผลคูณหน่วยกิต × เกรด) การเอาแม่แบบนี้ไปพิมพ์จะได้ใบที่หน้าตาถูกแต่
 * จัดกลุ่มผิดหลักสูตร ซึ่งมองไม่ออกถ้าไม่รู้ว่าควรเป็นแบบไหน
 */
export function is67Edition(payload: { program?: { edition_be?: number } | null }): boolean {
  return Number(payload.program?.edition_be) === 2567;
}

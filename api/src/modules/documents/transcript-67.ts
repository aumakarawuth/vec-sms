/**
 * ใบ รบ. ตระกูลหลักสูตร 67 — ปวช. และ ปวส. ทั้งฉบับไทยและอังกฤษ
 *
 * ═══ ตัวเลขทั้งหมดวัดจากไฟล์จริง ไม่ได้เดา ═══
 * วัดจาก PDF ที่ SISA ออกให้จริงด้วย PyMuPDF (ดู docs/transcript-formats.md)
 *   A4 แนวตั้ง 595 × 842 pt · ขอบ ซ้าย 22.5 บน 27.4 ขวา 19.0 ล่าง 42.2
 *   ฟอนต์ THSarabunNew — เนื้อหา 12 pt · ชื่อเรื่อง 16 pt (วัดจากตัวไฟล์
 *   ไม่ใช่ AngsanaNew ซึ่งใช้เฉพาะใบฉบับอังกฤษแนวนอนที่ยังไม่ได้ทำ)
 *   เส้นกริดเป็นแท่งทึบหนา 1.5 pt (52 แท่งต่อหน้า) ไม่ใช่เส้นผม
 *   เส้นตั้ง 11 เส้นที่ x = 22.5 · 65.2 · 113.2 · 250.5 · 274.5 · 298.5 ·
 *                        341.2 · 389.2 · 526.5 · 550.5 · 574.5
 *   เส้นนอน **สามเส้นเท่านั้น** — ขอบบน ใต้หัวตาราง ขอบล่าง
 *   → ไม่มีเส้นคั่นระหว่างแถว ตารางจึงเป็นกรอบเปล่าที่รายวิชาไหลลงไปข้างใน
 *
 * ═══ ตารางถูกตีกรอบไว้ก่อน รายวิชาค่อยไหลลงไป ═══
 * กรอบตารางมีความสูง **คงที่** (หน้า 1 สูง 458.2 pt · หน้า 2 สูง 432.0 pt)
 * ไม่ได้โตตามจำนวนรายวิชา นักศึกษาที่ลงสิบวิชากับคนที่ลงหกสิบวิชาจึงได้
 * กระดาษที่มีกรอบเท่ากันเป๊ะ — ซึ่งเป็นสิ่งที่ทำให้ใบพิมพ์ทับแบบฟอร์มได้
 * และเป็นเหตุผลที่ความจุคิดเป็น "จำนวนบรรทัด" (หน้า 1 คอลัมน์ละ 28 บรรทัด ·
 * หน้า 2 คอลัมน์ละ 26) ไม่ใช่ "จำนวนแถว" เพราะชื่อวิชายาวกินสองบรรทัด
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
import { TRANSCRIPT_FONT_FACE } from './fonts';
import { engDate, engYear, thaiDate } from './templates';

/* ─── ชนิดข้อมูลของ payload ที่ 0057/0058 สร้าง ─────────────────── */

interface Course67 {
  term_label: string;
  /** ภาคที่**ลงทะเบียนจริง** — ใช้เมื่อรายวิชาไม่ได้อยู่ในโครงสร้างหลักสูตร */
  year_be: number;
  term_ordinal: number;
  /**
   * ภาคตาม**โครงสร้างหลักสูตร** (0063) — เป็นค่าที่พิมพ์บนใบ
   *
   * null เมื่อรายวิชาไม่ได้อยู่ในแผน (เลือกเสรีนอกแผน · เทียบโอน) หรือ
   * เมื่อเป็นใบที่ออกก่อน 0063 ซึ่ง payload ยังไม่มีช่องนี้ — ทั้งสองกรณี
   * ตกไปใช้ภาคที่ลงจริง ใบเก่าจึงพิมพ์ซ้ำได้เหมือนวันที่ออกทุกประการ
   */
  plan_year_be?: number | null;
  plan_term_ordinal?: number | null;
  /**
   * เลขเครื่องหมาย (*1)–(*5) ที่ต้องพิมพ์ท้ายชื่อวิชา
   *
   * ตัวเลือก เพราะใบที่ออกก่อน 0066 ไม่มีช่องนี้ใน payload และ payload
   * แก้ไม่ได้ — ใบเก่าต้องพิมพ์ซ้ำได้เหมือนวันที่ออกทุกประการ คือไม่มี
   * เครื่องหมาย ไม่ใช่ขึ้นเครื่องหมายที่วันนั้นยังไม่มีใครตัดสินใจ
   */
  notes?: number[] | null;
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
  /* ─── ช่องบนหัวใบที่ 0062 ต่อสายมาให้ ─────────────────────────── */
  /** จังหวัดที่ตั้งสถานศึกษา */
  institution_province?: string | null;
  /** กลุ่มอาชีพของสาขาวิชา — ช่องระหว่างประเภทวิชากับสาขาวิชาของ ปวช.67 */
  career_group_th?: string | null;
  /** เชื้อชาติ · สัญชาติ · ศาสนา — สามช่องบนบรรทัดเดียวของใบจริง */
  person_extra?: { ethnicity: string; nationality: string; religion: string } | null;
  /** ชื่อบิดา · ชื่อมารดา (ชื่ออย่างเดียว ใบไม่ได้พิมพ์อาชีพหรือที่อยู่) */
  parents?: { father?: string; mother?: string } | null;
  /** ออกจากสถานศึกษาเมื่อ · เหตุที่ออก — เฉพาะสถานะที่แปลว่าออกจริง */
  leaving?: { on_date: string | null; reason: string; status: string } | null;
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
    ethnic: 'เชื้อชาติ    สัญชาติ    ศาสนา',
    ethnicParts: ['เชื้อชาติ', 'สัญชาติ', 'ศาสนา'],
    birth: 'วัน เดือน ปีเกิด',
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
    criteria: 'เกณฑ์การสำเร็จหลักสูตร', notes: 'หมายเหตุ', meaning: 'หมายถึง', memo: 'บันทึก',
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
    ethnic: 'Ethnicity    Nationality    Religion',
    ethnicParts: ['Ethnicity', 'Nationality', 'Religion'],
    birth: 'Date of Birth',
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
    criteria: 'Graduation Requirements', notes: 'Remarks', meaning: 'means', memo: 'Notes',
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

/* ─── เรขาคณิตที่วัดจากไฟล์จริง (pt) ────────────────────────────── */

/**
 * ทุกค่าในก้อนนี้มาจากการวัด PDF ต้นฉบับ ไม่มีค่าไหนเลือกเอาเอง
 *
 * เก็บรวมไว้ที่เดียวเพราะตัวเลขพวกนี้ **สัมพันธ์กันเป็นชุด** — ขยับเส้นตั้ง
 * เส้นเดียวโดยไม่ขยับความกว้างคอลัมน์ที่คู่กัน จะได้ตารางที่เส้นไม่ตรงกับ
 * ข้อความโดยที่คอมไพเลอร์ไม่มีทางรู้
 */
const G = {
  /** ขอบซ้ายของตาราง = ขอบซ้ายของกระดาษที่ใช้ได้ */
  left: 22.5,
  /** ความกว้างตารางทั้งใบ 22.5 → 576.0 */
  width: 553.5,
  /** ความหนาของแท่งเส้น (วัดได้ 1.5 pt — เป็นแท่งทึบ ไม่ใช่เส้นผม) */
  rule: 1.5,
  /** ตำแหน่งเส้นตั้ง 11 เส้น นับจากขอบซ้ายของตาราง */
  vRules: [0, 42.7, 90.7, 228.0, 252.0, 276.0, 318.7, 366.7, 504.0, 528.0, 552.0],
  /** ความกว้างคอลัมน์ (รวมเส้น) ของครึ่งหน้าหนึ่งข้าง — รวม 277.5 */
  cols: [44.3, 48.0, 137.2, 24.0, 24.0],
  /** ครึ่งขวาเริ่มตรงเส้นกลาง จึงใช้เส้นร่วมกับครึ่งซ้าย */
  halfWidth: 277.5,
  rightHalf: 276.0,
  /** หัวตารางสูง 39 pt (262.5 → 301.5) แล้วต่อด้วยเส้น 1.5 pt */
  headHeight: 39,
  /** ความสูงหนึ่งบรรทัดในตาราง — คิดเป็น em เพื่อให้ย่อตามฟอนต์ */
  rowEm: 1.2167,
  /** ความสูงหนึ่งบรรทัดที่ฟอนต์ 12 pt (= 12 × rowEm) */
  rowPt: 14.6,
  /** ความสูงกรอบตารางแต่ละหน้า (คงที่ ไม่โตตามจำนวนรายวิชา) */
  gridH: { p1: 458.2, p2: 432.0 },
  /** ที่ว่างใต้หัวตาราง = สูงกรอบ − เส้นบน − หัวตาราง − เส้นกลาง − เส้นล่าง */
  body: { p1: 414.7, p2: 388.5 },
  /** ความกว้างที่ข้อความในคอลัมน์ชื่อวิชาใช้ได้จริง (137.2 − ระยะขอบซ้ายขวา) */
  nameWidth: 134.1,
} as const;

/* ─── สไตล์ที่ตรงกับตัวเลขที่วัดมา ──────────────────────────────── */

/**
 * ─── ทำไมกรอบตารางเป็น div วางทับ ไม่ใช่ border ของ <table> ───
 * เพราะกรอบต้องมีความสูง**คงที่**และปิดที่ตำแหน่งเดิมเสมอ ส่วน `<table>`
 * ใน CSS สูงตามเนื้อหาเสมอ (`height` เป็นแค่ค่าต่ำสุด และเบราว์เซอร์เกลี่ย
 * ส่วนเกินให้ทุกแถวแทนที่จะเว้นท้ายตาราง) ผลคือใบของคนที่ลงสิบวิชาจะได้
 * ตารางเตี้ยกว่าใบของคนที่ลงหกสิบวิชา ซึ่งเป็นสิ่งที่แบบฟอร์มราชการไม่ทำ
 *
 * ตัวกรอบจึงเป็น `.grid` ที่สูงคงที่ มีแท่งเส้นวางทับตามพิกัดที่วัดมา
 * แล้ว `<table>` ที่อยู่ข้างในไม่มีเส้นของตัวเองเลย ทำหน้าที่จัดข้อความ
 * ลงช่องอย่างเดียว — ตารางเตรียมไว้ก่อน รายวิชาค่อยไหลลงไป
 */
const STYLE = `
  ${TRANSCRIPT_FONT_FACE}
  @page { size: A4 portrait; margin: 27.4pt 19pt 42.2pt 22.5pt; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    /*
     * ─── ฟอนต์เป้าหมายคือ THSarabunNew ตามที่วัดได้จากไฟล์ต้นฉบับ ───
     * ไม่ใช่ AngsanaNew (ซึ่งใบฉบับอังกฤษ**แนวนอน**ใช้ และยังไม่ได้ทำ)
     * เรขาคณิตทั้งใบคิดบนความกว้างตัวอักษรของฟอนต์นี้ — ฟอนต์จึงเป็น
     * **ส่วนหนึ่งของเรขาคณิต** ไม่ใช่เรื่องความสวย
     *
     * ─── ฝังมากับหน้าแล้ว (TRANSCRIPT_FONT_FACE) ───
     * ชื่อในรายการนี้จึงตรงกับ @font-face ที่ฝังไว้ ไม่ใช่ฟอนต์ในเครื่อง
     * หน้าตาของใบจึงไม่ขึ้นกับว่าเครื่องไหนลงฟอนต์อะไรไว้อีกต่อไป
     *
     * ─── ตัวสำรองยังต้องมี และเรียงตามความกว้างที่วัดจริง ───
     * เผื่อกรณีที่ฟอนต์ฝังโหลดไม่ขึ้น (em ต่ออักขระไทย ที่ 12 pt)
     *   THSarabunNew 0.361 (จากไฟล์ฟอนต์) / 0.376 (ที่เบราว์เซอร์วางจริง) ·
     *   AngsanaNew 0.389 · CordiaNew 0.395 · BrowalliaNew 0.397 ·
     *   **LeelawadeeUI 0.530** · Tahoma 0.575
     * ของเดิมวาง Leelawadee UI ไว้เป็นตัวสำรองตัวแรก ซึ่งกว้างกว่าเป้าหมาย
     * **45%** — ชื่อวิชาที่ใบจริงพิมพ์บรรทัดเดียวจะกลายเป็นสองบรรทัดเกือบทุกตัว
     * แล้วตารางล้นกรอบทั้งใบ โดยที่หน้าจอไม่มีอะไรฟ้องเลยนอกจากตาคนดู
     */
    font-family: 'TH Sarabun New', 'TH SarabunPSK', 'THSarabunNew', 'Sarabun',
                 'Angsana New', 'AngsanaUPC', 'Cordia New', serif;
    font-size: 12pt; line-height: 1.2; color: #000;
  }
  .page { position: relative; page-break-after: always; }
  .page:last-child { page-break-after: auto; }

  /* บล็อกบนหน้า 1 สูงตายตัว เพื่อให้เส้นบนสุดของตารางตกที่ y = 261.0 พอดี */
  .docno { text-align: right; height: 14.5pt; line-height: 14.5pt; }
  h1 { font-size: 16pt; font-weight: 700; text-align: center;
       margin: 0; height: 33.3pt; line-height: 33.3pt; }
  h1 .cont { display: block; font-size: 16pt; }

  .head { position: relative; height: 185.8pt; padding-left: 0.9pt; }
  .head .col { position: absolute; top: 0; }
  .head .col.l { left: 0.9pt; width: 241.6pt; }
  .head .col.r { left: 243.4pt; width: 215.2pt; }
  .head .f { height: 14.29pt; line-height: 14.29pt; white-space: nowrap; }
  .head .k { display: inline-block; }
  /* สามช่องบนบรรทัดเดียว — ใบจริงวางป้ายห่างกัน 42.5 pt เพราะช่องค่าว่างเปล่า
     ทั้งสามช่อง ตอนนี้มีค่าจริงแล้วจึงต้องกว้างขึ้น มิฉะนั้นค่าจะทับป้ายถัดไป */
  .head .k3 { display: inline-block; width: 78pt; }
  .head .k3:last-child { width: auto; }
  /* กรอบรูปถ่ายวัดได้ 71.3 × 93.0 ที่ x 481.1 y 142.1 */
  .photo {
    position: absolute; left: 458.6pt; top: 66.9pt; width: 71.3pt; height: 93pt;
    border: 0.75pt solid #000; display: flex; align-items: center;
    justify-content: center; text-align: center; font-size: 11pt; line-height: 1.15;
  }

  /* ─── กรอบตารางที่สูงคงที่ ─── */
  .grid { position: relative; height: var(--gh); }
  .grid.g1 { --gh: calc(${G.gridH.p1}pt - var(--shrink, 0pt)); }
  .grid.g2 { --gh: calc(${G.gridH.p2}pt - var(--shrink, 0pt)); }
  .grid i { position: absolute; background: #000; }
  .grid i.v { top: 0; bottom: 0; width: ${G.rule}pt; }
  .grid i.h { left: 0; right: 0; height: ${G.rule}pt; }
  .grid i.h.top { top: 0; }
  .grid i.h.mid { top: ${G.rule + G.headHeight}pt; }
  .grid i.h.bot { bottom: 0; }

  /* --k คือตัวคูณขนาดฟอนต์ที่ fitColumns() เลือกให้รายวิชาลงครบในกรอบ
     (เขียนเป็นตัวแปร CSS ไม่ใช่ style ที่ตัว element เพื่อให้ชั้นทับตอนพิมพ์
      กระดาษตราซึ่งตั้ง font-size ของ table.courses ยังทับได้ตามเดิม) */
  table.courses {
    position: absolute; width: ${G.halfWidth}pt;
    table-layout: fixed; border-collapse: collapse;
    font-size: calc(12pt * var(--k, 1));
  }
  /* หัวตารางกับเนื้อตารางเป็นคนละตาราง เพราะแต่ละตัวถูกตรึงไว้คนละที่ —
     ถ้าอยู่ตารางเดียวกัน หัวที่บังเอิญสูงกว่าที่คิด (ฟอนต์สำรองกว้างกว่า
     THSarabunNew) จะดันแถวแรกของรายวิชาให้หลุดจากเส้นใต้หัวตาราง */
  table.courses.hd { top: ${G.rule}pt; }
  table.courses.bd { top: ${G.rule * 2 + G.headHeight}pt; }
  table.courses.r { left: ${G.rightHalf}pt; }
  table.courses th, table.courses td {
    border: 0; padding: 0 1.6pt 0 ${G.rule}pt; vertical-align: top;
  }
  /* หัวตารางเป็นตัวหนา — แยกหัวคอลัมน์ออกจากเนื้อรายวิชาให้ชัด */
  table.courses.hd th { height: ${G.headHeight}pt; text-align: center;
    font-weight: 700; vertical-align: middle; }
  table.courses.hd th span {
    display: block; height: ${G.headHeight}pt; line-height: 12.7pt;
    overflow: hidden; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
  }
  table.courses td {
    height: ${G.rowEm}em; line-height: ${G.rowEm}em;
  }
  td.term, td.credit, td.grade { text-align: center; }
  /* หัวหมวด · หัวกลุ่ม · บรรทัดสรุป อยู่ใน**คอลัมน์ชื่อวิชาเท่านั้น**
     ไม่กินคอลัมน์หน่วยกิต/ผลการเรียน ตามที่ใบจริงวางไว้ */
  td.cat  { text-align: center; font-weight: 700; }
  td.grp  { font-weight: 700; }
  td.tsum { text-align: center; }
  td.thead2 { text-align: center; font-weight: 700; }

  /* หัวข้อสองบรรทัดใต้ตารางเป็นตัวหนา ส่วนค่าที่กรอกไม่หนา —
     ให้อ่านออกว่าอันไหนเป็นหัวข้อของแบบฟอร์ม อันไหนเป็นข้อมูลของคนนี้ */
  .leave { height: 28.6pt; padding-left: 8.7pt; font-weight: 700; }
  .leave div { height: 14.3pt; line-height: 14.3pt; }
  .leave span { font-weight: 400; }

  .signs { position: relative; height: 62pt; margin-top: 4pt; }
  .sign { position: absolute; top: 0; width: 190pt; text-align: center; }
  .sign.a { left: 190pt; }
  .sign.b { left: 380pt; }
  .sign div { height: 17.2pt; line-height: 17.2pt; }

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

  /* หน้า 2 ไม่มีบรรทัดเลขที่มุมขวาบน ชื่อเรื่องจึงลงมาต่ำกว่าหน้า 1 อยู่ 3 pt
     — เว้นที่ตรงนั้นแทน เพื่อให้เส้นบนสุดของตารางตกที่ y = 87.8 เหมือนใบจริง */
  .p2 h1 { margin-top: 23.9pt; height: 22.7pt; line-height: 22.7pt; }
  .page2head { position: relative; height: 13.9pt; line-height: 13.9pt; }
  .page2head span { position: absolute; top: 0; white-space: nowrap; }
  .page2head .a { left: 0.2pt; }
  .page2head .b { left: 241.1pt; }
  .page2head .c { right: 0; }
  .p2 .signs { margin-top: 12pt; }

  /*
   * ท้ายหน้า 2 — สามบล็อกเรียงตามพิกัดที่วัดได้ x = 22.7 · 206.9 · 391.2
   *
   * ─── ทำไมเป็น grid ไม่ใช่บล็อกวางทับตามพิกัดเหมือนที่อื่น ───
   * เพราะเนื้อในสามคอลัมน์นี้เป็นข้อความของ**วิทยาลัย** (เกณฑ์การสำเร็จ
   * หลักสูตรและหมายเหตุจาก institution_document_text) ซึ่งยาวเท่าไรก็ได้
   * ถ้าตรึงความสูงไว้ วิทยาลัยที่เขียนเกณฑ์ยาวจะได้ข้อความทับบล็อกถัดไป
   * — x ตรึงได้เพราะวัดมา ส่วน y ต้องยืดตามเนื้อหาจริง
   */
  .legend { display: grid; grid-template-columns: 184.2pt 184.3pt 185pt; margin-top: 11.4pt; }
  .legend h2 { font-size: 12pt; font-weight: 700; margin: 0; height: 14.3pt; line-height: 14.3pt; }
  .legend table { width: 100%; border-collapse: collapse; }
  .legend td { border: none; padding: 0; line-height: 13.4pt; }
  .legend div { line-height: 13.4pt; }
  .letters { margin-top: 6.4pt; }
  .letters h2 { font-size: 12pt; font-weight: 700; margin: 0 0 2pt; }
  .letters table { width: 100%; border-collapse: collapse; }
  .letters td { border: none; padding: 0 6pt 0 0; line-height: 13.4pt; }
  .memo { margin-top: 6.4pt; }
  .memo h2 { font-size: 12pt; font-weight: 700; margin: 0; }
  .memo .lines div { border-bottom: 0.6pt dotted #000; height: 14.3pt; }

  @media screen {
    body { background: #f4f4f4; padding: 14px; }
    .page { background: #fff; width: 595pt; height: 841.9pt;
            margin: 0 auto 14px; padding: 27.4pt 19pt 42.2pt 22.5pt;
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
  | { t: 'sum'; text: string }
  | { t: 'termhead'; text: string }
  /**
   * `pt` คือขนาดฟอนต์ของบรรทัดนั้น — วัดจากใบจริงได้ 10.5 กับ 10.0
   * ไม่ใช่ 12 เหมือนแถวอื่น เพราะสองบรรทัดนี้ยาวเกินคอลัมน์ชื่อวิชา
   * (135.7 pt) ที่ขนาดปกติ และบรรทัดที่สองยาวกว่าจึงเล็กกว่าอีกครึ่งพอยต์
   */
  | { t: 'termsum'; text: string; pt: number };

/**
 * ป้ายบอกหลักสูตรที่ต่อท้ายชื่อหมวด เช่น "(ปวช.67)"
 *
 * ใบจริงเขียนไว้ที่หัวหมวด เพื่อให้อ่านออกว่ายอดสรุปก้อนนี้เป็นของหลักสูตรไหน
 * — ใบของคนที่เทียบโอนมาจากหลักสูตรอื่นมีหมวดชื่อเดียวกันได้หลายชุด
 * ถ้าชื่อหมวดในฐานข้อมูลมีวงเล็บอยู่แล้วก็ไม่เติมซ้ำ
 */
function editionTag(
  prog: { qualification_abbr_th?: string; edition_be?: number } | null,
): string {
  const abbr = prog?.qualification_abbr_th ?? '';
  const ed = edition2(prog?.edition_be);
  return abbr && ed ? ` (${abbr}${ed})` : '';
}

function buildRows(
  tree: Head67[],
  lang: 'th' | 'en',
  prog: { qualification_abbr_th?: string; edition_be?: number } | null,
): Row[] {
  const t = L[lang];
  const rows: Row[] = [];
  const tag = editionTag(prog);
  const withTag = (name: string) => (name.includes('(') ? name : `${name}${tag}`);
  tree.forEach((head, hi) => {
    rows.push({ t: 'cat', text: `${hi + 1}. ${withTag(head.name_th)}` });
    for (const g of head.groups) {
      // กลุ่มที่ชื่อซ้ำกับหมวด แปลว่าไม่มีกลุ่มย่อยจริง — ไม่ต้องพิมพ์ซ้ำ
      if (g.name_th !== head.name_th) rows.push({ t: 'grp', text: g.name_th });
      for (const c of g.courses) rows.push({ t: 'course', c });
      if (g.min_credits != null) {
        rows.push({ t: 'sum', text: `${t.reqCredits} ${credits(g.min_credits)} ${t.unitCredit}` });
      }
      rows.push({ t: 'sum', text: `${t.gotCredits} ${credits(g.credits_earned)} ${t.unitCredit}` });
      if (g.gpa != null) {
        rows.push({ t: 'sum', text: `${t.groupGpa} ${g.name_th} ${gpa(g.gpa)}` });
      }
    }
    /*
     * ─── ต้องเว้นวรรคหลังคำว่า "คะแนนเฉลี่ยสะสม" ───
     * ใบจริงพิมพ์ติดกันเป็น "คะแนนเฉลี่ยสะสม3. หมวดวิชา…" ซึ่งอ่านได้ว่า
     * เกรดเฉลี่ยเท่ากับ "3." คือเลขที่ขาดทศนิยมไป ทั้งที่ 3 เป็น**เลขที่หมวด**
     * และค่าเกรดจริงอยู่ท้ายบรรทัด — เป็นตัวเลขที่คนอ่านใบตีความผิดได้ทันที
     * บนเอกสารที่แก้ไม่ได้ จึงเว้นวรรคและต่อป้ายหลักสูตรให้ชัดว่าเป็นหมวดอะไร
     */
    if (head.gpa != null) {
      rows.push({
        t: 'sum',
        text: `${t.headGpa} ${hi + 1}. ${withTag(head.name_th)} ${gpa(head.gpa)}`,
      });
    }
  });
  return rows;
}

/* ─── ความจุของกรอบ ─────────────────────────────────────────────── */

/** สระบน/ล่างและวรรณยุกต์ไทยลอยอยู่เหนือหรือใต้ตัวอักษร ไม่กินความกว้าง */
const THAI_MARKS = /[ัิ-ฺ็-๎]/g;

/**
 * เดาว่าข้อความหนึ่งชิ้นกินกี่บรรทัดในคอลัมน์ชื่อวิชา
 *
 * ─── ทำไมต้องเดา แทนที่จะปล่อยให้เบราว์เซอร์ตัดเอง ───
 * เพราะกรอบตารางสูงคงที่ การแบ่งรายวิชาลงสี่ช่อง (ซ้าย/ขวา × สองหน้า)
 * ต้องรู้ล่วงหน้าว่าแต่ละแถวสูงกี่บรรทัด ถ้าแบ่งด้วย "จำนวนแถว" เฉย ๆ
 * คอลัมน์ที่บังเอิญได้ชื่อวิชายาวหลายตัวจะล้นออกนอกกรอบ ส่วนคอลัมน์ถัดไป
 * เหลือที่ว่าง — และมองไม่ออกจากโค้ดเลยว่าใบไหนจะล้น
 *
 * ค่าเฉลี่ยความกว้างต่ออักขระวัดจากไฟล์ต้นฉบับ (THSarabunNew: ไทย 0.365 em ·
 * ละติน 0.33 em) — ตรวจกับบรรทัดที่ใบจริงตัดจริง: 31 อักขระไทยพอดีหนึ่งบรรทัด
 * ในคอลัมน์กว้าง 134.1 pt ที่ฟอนต์ 12 pt
 */
function estimateLines(text: string, availPt = G.nameWidth, fontPt = 12): number {
  let em = 0;
  for (const ch of text.replace(THAI_MARKS, '')) {
    em += ch >= '฀' && ch <= '๿' ? 0.365 : 0.33;
  }
  return Math.max(1, Math.ceil((em * fontPt * WIDTH_SAFETY) / availPt));
}

/**
 * เผื่อความกว้างไว้ 5%
 *
 * ─── ทำไมต้องเผื่อ ทั้งที่รู้ความกว้างของฟอนต์แน่นอนแล้ว ───
 * ค่า 0.365 มาจากการวัด**ไฟล์ต้นฉบับ** และไฟล์ฟอนต์ให้ 0.361 แต่เวลา
 * เบราว์เซอร์วางจริงได้ **0.376** (ปัดตำแหน่งเป็นพิกเซลกับ kern ของฟอนต์เอง)
 * — ตัวประมาณจึงต้องเผื่อ มิฉะนั้นจะคิดว่าลงพอดีแล้วไปเกินตอนพิมพ์จริง
 * 0.365 × 1.05 = 0.383 ซึ่งยังมากกว่า 0.376 อยู่ 2% คือเผื่อพอดีไม่มากไป
 *
 * และเผื่อไว้ครอบคลุมกรณีฟอนต์ฝังโหลดไม่ขึ้นแล้วตกไปใช้ Angsana (0.389) ด้วย
 *
 * **ทางที่ผิดสองทางไม่เท่ากัน** — เผื่อมากไปแค่ทำให้คอลัมน์จบก่อนถึงเส้นล่าง
 * นิดหน่อย ซึ่งมองไม่ออกเพราะกรอบสูงเท่าเดิมอยู่แล้ว ส่วนเผื่อน้อยไปทำให้
 * รายวิชาทะลุกรอบไปทับบรรทัดใต้ตาราง
 */
const WIDTH_SAFETY = 1.05;

/** ข้อความที่อยู่ในคอลัมน์ชื่อวิชาของแถวนั้น — ตัวเดียวที่ตัดบรรทัดได้ */
function rowText(r: Row, lang: 'th' | 'en'): string {
  if (r.t !== 'course') return r.text;
  /*
   * ต้องรวม (*n) เข้าไปด้วย เพราะข้อความนี้คือสิ่งที่ตัวคำนวณความจุใช้
   * ตัดสินว่าจะย่อฟอนต์กี่ขั้น ถ้าวัดชื่อเปล่าแล้วพิมพ์ชื่อ+เครื่องหมาย
   * ตารางจะล้นกรอบเฉพาะใบของคนที่มีวิชาเทียบโอน — ซึ่งมองไม่เห็นจน
   * กระดาษออกมาจากเครื่องพิมพ์
   */
  const name = (lang === 'en' && r.c.name_en ? r.c.name_en : r.c.name_th) ?? '';
  return name + noteSuffix(r.c.notes);
}

/**
 * แบ่งแถวลงสี่ช่อง — ครึ่งซ้าย/ครึ่งขวาของหน้า 1 แล้วต่อด้วยหน้า 2
 *
 * คืน `null` เมื่อใส่ไม่ครบ เพื่อให้ผู้เรียกลองย่อฟอนต์แล้วเรียกใหม่
 */
function packColumns(rows: Row[], lang: 'th' | 'en', k: number): Row[][] | null {
  const fontPt = 12 * k;
  const caps = [
    Math.floor(G.body.p1 / (G.rowPt * k)), Math.floor(G.body.p1 / (G.rowPt * k)),
    Math.floor(G.body.p2 / (G.rowPt * k)), Math.floor(G.body.p2 / (G.rowPt * k)),
  ];
  const out: Row[][] = [[], [], [], []];
  let slot = 0;
  let used = 0;
  for (const r of rows) {
    const need = estimateLines(rowText(r, lang), G.nameWidth, fontPt);
    if (used + need > caps[slot]) {
      slot += 1;
      used = 0;
      if (slot >= out.length) return null;
    }
    out[slot].push(r);
    used += need;
  }
  return out;
}

/** ขั้นการย่อฟอนต์ในตาราง — หยุดที่ 0.75 เพราะต่ำกว่านั้นอ่านด้วยตาเปล่าไม่ไหว */
const FIT_SCALES = [1, 0.95, 0.9, 0.85, 0.8, 0.75] as const;

/**
 * หาขนาดฟอนต์ที่ทำให้รายวิชาลงครบในกรอบสองหน้าที่มีอยู่
 *
 * ─── ทำไมย่อฟอนต์ ไม่ใช่ต่อหน้าที่สาม หรือปล่อยล้น ───
 * • ต่อหน้าที่สามไม่ได้ เพราะของประจำหน้า 2 (สรุปรายภาค · คำอธิบายเกรด ·
 *   เกณฑ์การสำเร็จหลักสูตร · ช่องลงนาม) ต้องอยู่หน้าสุดท้ายเสมอ ใบสามหน้า
 *   ไม่ใช่ใบเดียวกับที่ สอศ. รับ
 * • ปล่อยล้นคือให้รายวิชาทับบรรทัด "ออกจากสถานศึกษาเมื่อ" และช่องลงนาม
 * • ตัดทิ้งคือออกใบที่ขาดรายวิชาโดยไม่มีอะไรบอก ซึ่งแย่ที่สุดในสามทาง
 *   เพราะคนถือใบไม่มีวันรู้ และ payload ที่ตรึงแล้วก็แก้ไม่ได้
 *
 * SISA เองก็แก้ด้วยวิธีนี้ — ใบกระดาษตราที่มีที่น้อยกว่า 61 pt ใช้ฟอนต์
 * 10 pt แทน 12.5 pt เพื่อให้จำนวนบรรทัดเท่าเดิม (ดู docs/transcript-formats.md)
 *
 * ─── ทำไมต้องวนลอง ไม่ใช่หารครั้งเดียว ───
 * เพราะการย่อฟอนต์ให้ผลสองทางพร้อมกัน — แถวเตี้ยลง **และ** ชื่อวิชาที่เคย
 * ยาวเกินหนึ่งบรรทัดกลับมาอยู่บรรทัดเดียว จำนวนบรรทัดรวมจึงไม่ได้ลดเป็น
 * สัดส่วนตรง ๆ กับขนาดฟอนต์
 */
function fitColumns(rows: Row[], lang: 'th' | 'en'): { k: number; cols: Row[][] } {
  for (const k of FIT_SCALES) {
    const cols = packColumns(rows, lang, k);
    if (cols) return { k, cols };
  }
  /*
   * เล็กสุดแล้วยังไม่พอ — ยัดส่วนที่เหลือลงช่องสุดท้ายให้ล้นออกมาให้เห็น
   * เจ้าหน้าที่จะเห็นตั้งแต่ยังไม่กดพิมพ์ว่าใบนี้มีปัญหา ดีกว่าได้ใบสวย
   * ที่ขาดรายวิชาไปเงียบ ๆ
   */
  const k = FIT_SCALES[FIT_SCALES.length - 1];
  const cap = Math.floor(G.body.p1 / (G.rowPt * k));
  const out: Row[][] = [[], [], [], []];
  let slot = 0;
  let used = 0;
  for (const r of rows) {
    const need = estimateLines(rowText(r, lang), G.nameWidth, 12 * k);
    if (used + need > cap && slot < out.length - 1) { slot += 1; used = 0; }
    out[slot].push(r);
    used += need;
  }
  return { k, cols: out };
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
  /*
   * ─── พิมพ์ภาคตามโครงสร้างหลักสูตร ไม่ใช่ภาคที่ลงทะเบียนจริง (0063) ───
   * นักศึกษาที่ลงวิชาไว้ปี 1 ภาค 1 แต่หลักสูตรวางไว้ปี 2 ภาค 1 ต้องเห็น
   * "1/ปีที่สอง" บนใบ เพราะใบ รบ. แสดงว่าเรียนครบตาม**หลักสูตร**
   * ไม่ใช่ปูมว่าไปนั่งเรียนเมื่อไร — คนที่เอาใบไปเทียบกับโครงสร้างของ สอศ.
   * ต้องเห็นรายวิชาอยู่ตำแหน่งเดียวกับที่หลักสูตรกำหนด
   *
   * ตกไปใช้ภาคที่ลงจริงเมื่อไม่มีค่าตามแผน (วิชานอกแผน หรือใบที่ออกก่อน 0063)
   */
  const yearBe = Number(c.plan_year_be ?? c.year_be);
  const ordinal = c.plan_term_ordinal ?? c.term_ordinal;
  const year = lang === 'en' ? yearBe - 543 : yearBe;
  return `${ordinal}/${year}`;
}

/**
 * แถวหนึ่งของตาราง — ห้าช่องเสมอ ไม่ว่าจะเป็นแถวชนิดไหน
 *
 * ─── ทำไมหัวหมวด/หัวกลุ่ม/บรรทัดสรุปไม่ใช้ colspan ───
 * ใบจริงพิมพ์ข้อความพวกนี้อยู่ใน**คอลัมน์ชื่อวิชาช่องเดียว** ช่องหน่วยกิต
 * กับผลการเรียนเว้นว่างไว้ (วัดแล้ว — มีอักขระช่องว่างวางอยู่ที่พิกัดของ
 * ทั้งห้าช่องทุกแถว) ถ้าใช้ colspan ข้อความสรุปที่ยาวจะไหลไปทับคอลัมน์
 * ตัวเลข แล้วบรรทัดสรุปจะดูเหมือนเป็นรายวิชาที่ไม่มีหน่วยกิต
 */
/**
 * เครื่องหมาย (*n) ท้ายชื่อวิชา
 *
 * ─── ทำไมต่อท้ายชื่อ ไม่ใช่คอลัมน์ใหม่ ───
 * กรอบตารางของใบวัดมาจากไฟล์จริงแล้วตรึงไว้ (เส้นตั้ง 11 เส้น) การเพิ่ม
 * คอลัมน์แปลว่าต้องวัดใหม่ทั้งใบ และใบจริงก็พิมพ์เครื่องหมายไว้ท้ายชื่อวิชา
 * ในคอลัมน์เดียวกันอยู่แล้ว
 *
 * หลายเครื่องหมายพร้อมกันเขียนติดกันเป็น `(*4)(*5)` ตามที่ปรากฏบนใบจริง
 * ไม่ใช่ `(*4, *5)` ซึ่งเป็นรูปที่ไม่มีใครใช้
 */
function noteSuffix(notes?: number[] | null): string {
  if (!notes || notes.length === 0) return '';
  return ' ' + notes.map((n) => `(*${n})`).join('');
}

function renderRow(r: Row, lang: 'th' | 'en'): string {
  if (r.t === 'course') {
    const c = r.c;
    const name = lang === 'en' && c.name_en ? c.name_en : c.name_th;
    return `<tr>
      <td class="term">${esc(termCell(c, lang))}</td>
      <td>${esc(c.code)}</td>
      <td>${esc(name + noteSuffix(c.notes))}</td>
      <td class="credit">${esc(c.grade_point === null || c.grade_point === undefined
                                 ? '-' : credits(c.credits))}</td>
      <td class="grade">${esc(gradeCell(c))}</td>
    </tr>`;
  }
  const cls = r.t === 'cat' ? 'cat'
    : r.t === 'grp' ? 'grp'
    : r.t === 'termhead' ? 'thead2'
    : r.t === 'termsum' ? 'tsum' : 'sum';
  // บรรทัดสรุปรายภาคมีขนาดของตัวเอง ที่เหลือใช้ขนาดของตาราง
  const size = r.t === 'termsum' ? ` style="font-size:calc(${r.pt}pt * var(--k,1))"` : '';
  return `<tr><td></td><td></td><td class="${cls}"${size}>${esc(r.text)}</td>`
    + `<td></td><td></td></tr>`;
}

/**
 * กรอบตารางหนึ่งหน้า — ตีเส้นก่อน แล้วค่อยวางรายวิชาลงไป
 *
 * เส้นตั้ง 11 เส้นกับเส้นนอน 3 เส้นวางตามพิกัดที่วัดมา และไม่ขึ้นกับ
 * เนื้อหาเลยสักเส้น หน้าที่ยังไม่มีรายวิชาจึงได้กรอบเปล่าเต็มใบ
 * เหมือนแบบฟอร์มที่ยังไม่ได้กรอก ซึ่งตรงกับใบจริง
 */
function courseGrid(
  page: 'g1' | 'g2', left: Row[], right: Row[], lang: 'th' | 'en', k: number,
): string {
  const t = L[lang];
  const cols = `<colgroup>${G.cols.map((w) => `<col style="width:${w}pt">`).join('')}</colgroup>`;
  const head = (side: 'l' | 'r') => `<table class="courses hd ${side}">${cols}<tbody><tr>`
    + [t.colTerm, t.colCode, t.colName, t.colCredit, t.colGrade]
      .map((h) => `<th><span>${h}</span></th>`).join('')
    + '</tr></tbody></table>';
  const body = (rows: Row[], side: 'l' | 'r') => `<table class="courses bd ${side}">
      ${cols}<tbody>${rows.map((r) => renderRow(r, lang)).join('')}</tbody>
    </table>`;

  const rules = G.vRules.map((x) => `<i class="v" style="left:${x}pt"></i>`).join('')
    + '<i class="h top"></i><i class="h mid"></i><i class="h bot"></i>';

  return `<div class="grid ${page}" style="--k:${k}">${rules}`
    + head('l') + head('r') + body(left, 'l') + body(right, 'r')
    + '</div>';
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
 * สรุปรายภาคเรียน — เป็น**แถวในตาราง** ไม่ใช่บล็อกที่ต่อท้ายตาราง
 *
 * ─── ที่แก้รอบนี้ ───
 * เดิมพิมพ์อยู่ใต้ตาราง ซึ่งทำให้กรอบตารางต้องสั้นลงมารับมัน วัดใบจริงแล้ว
 * ตัวเลขชุดนี้อยู่ในคอลัมน์ชื่อวิชาของตารางเอง (x 115.6–231.6 คือในกรอบ)
 * ต่อจากรายวิชากลุ่มสุดท้ายเลย — กรอบจึงเต็มความสูงเสมอ
 *
 * ─── ข้อผิดพลาดที่แก้ไปแล้วใน 0060 ───
 * แม่แบบนี้เคยพิมพ์ "หน่วยกิตที่ได้ในภาค" กับ "หน่วยกิตสะสม" จากค่าเดียวกัน
 * คือ `credits_earned` ของภาคนั้น ภาคที่สองจึงพิมพ์ 11/11 แทนที่จะเป็น 11/28
 * — ตัวเลขผิดบนเอกสารที่แก้ไม่ได้ ไม่มีอะไรฟ้องเพราะทั้งคู่ดูสมเหตุสมผล
 *
 * ค่าสะสมมาจาก `term_tree` ที่ฐานข้อมูลคำนวณให้ ไม่ใช่แม่แบบบวกเอง
 * (หลักข้อ 1 — ถ้าบวกเอง จะกลายเป็นสูตรชุดที่สองที่ค่อย ๆ เพี้ยน)
 * ใบที่ออกก่อน 0060 ไม่มี `term_tree` จึงตกไปใช้ `term_summaries` เดิม
 * แล้วพิมพ์ "-" ในช่องสะสม — บอกว่า "ไม่รู้" ดีกว่าพิมพ์ตัวเลขที่รู้ว่าผิด
 */
function termRows(
  d: Transcript67Payload,
  lang: 'th' | 'en',
  t: typeof L['th'] | typeof L['en'],
): Row[] {
  const label = (year: number, ordinal: number) =>
    lang === 'en'
      ? `Semester ${ordinal} / ${year - 543}`
      : `ภาคเรียนที่ ${ordinal} ปีการศึกษา ${year}`;

  const terms = (d.term_tree ?? []).length > 0
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

  const out: Row[] = [];
  for (const s of terms) {
    out.push({ t: 'termhead', text: s.label });
    out.push({
      t: 'termsum', pt: 10.5,
      text: `${t.termCredits} ${credits(s.earned)}  ${t.cumCredits} ${credits(s.cum)}`,
    });
    out.push({
      t: 'termsum', pt: 10,
      text: `${t.termGpa} ${gpa(s.gpa)}  ${t.cumGpa} ${gpa(s.gpax)}`,
    });
  }
  return out;
}

/**
 * ช่องลงนามสองช่อง — วางที่ x 307.5 และ 497.5 ตามที่วัดจากใบจริง
 *
 * ทั้งสองช่องอยู่**ครึ่งขวาของกระดาษ** ไม่ได้กระจายเต็มหน้า เพราะครึ่งซ้าย
 * เป็นที่ของ "ออกจากสถานศึกษาเมื่อ / เหตุที่ออก"
 */
function signBlock(
  t: typeof L['th'] | typeof L['en'],
  issuedOn: string,
  d: Transcript67Payload,
): string {
  /*
   * ─── ชื่อผู้ลงนามตรึงใน payload ตั้งแต่วันที่ออก ───
   * ต่างจาก SISA ที่ส่งชื่อมาตอนกดพิมพ์ — ใบที่พิมพ์ซ้ำหลังเปลี่ยนผู้อำนวยการ
   * จะได้ชื่อคนใหม่บนเอกสารของปีเก่า แล้วตรวจย้อนหลังไม่ได้ว่าตอนนั้นใครเซ็น
   *
   * วิทยาลัยที่ยังไม่ได้ตั้งชื่อผู้ลงนามจะได้วงเล็บว่างไว้ให้เขียนมือ
   * ซึ่งเป็นสภาพเดิมของใบ ไม่ใช่ความผิดพลาด
   */
  const blank = '&nbsp;'.repeat(20);
  const nameOf = (key: string) => {
    const v = d.institution_text?.[key];
    const s = (d.lang === 'en' ? v?.en : v?.th) ?? '';
    return s.trim() === '' ? blank : esc(s);
  };
  return `<div class="signs">
    <div class="sign a"><div>( ${nameOf('transcript_signer_registrar')} )</div>
      <div>${t.registrar}</div><div>${esc(issuedOn)}</div></div>
    <div class="sign b"><div>( ${nameOf('transcript_signer_director')} )</div>
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

  /*
   * ─── ลำดับของแถวคือสายเดียวยาวต่อเนื่อง แล้วค่อยตัดตามความจุของกรอบ ───
   * รายวิชาตามหมวด/กลุ่ม → สรุปรายภาคเรียน ทั้งหมดเป็นเนื้อของตารางเดียวกัน
   * เหมือนใบจริง แล้ว fitColumns() เป็นคนตัดว่าอะไรตกช่องไหน โดยดูจาก
   * **จำนวนบรรทัดที่กินจริง** ไม่ใช่จำนวนแถว
   */
  const rows = [
    ...buildRows(d.category_tree ?? [], lang, prog),
    ...termRows(d, lang, t),
  ];
  const { k, cols: [c1, c2, c3, c4] } = fitColumns(rows, lang);

  const field = (label: string, value: string) =>
    `<div class="f"><span class="k">${label}</span>&nbsp;&nbsp;${value}</div>`;

  /** สามช่องบนบรรทัดเดียว วางที่ x ตายตัวตามที่วัดจากใบจริง (23.4 · 65.9 · 107.9) */
  const triple = (labels: readonly string[], values: (string | undefined)[]) =>
    `<div class="f">${labels
      .map((k, i) => `<span class="k3"><span class="k">${k}</span> ${esc(values[i] ?? '')}</span>`)
      .join('')}</div>`;

  // ใบจริงเว้นบรรทัดวันที่ไว้ให้เขียนมือ แต่ระบบรู้วันที่อยู่แล้ว
  // การพิมพ์ลงไปทำให้ใบที่พิมพ์ซ้ำในอีกห้าปียังบอกได้ว่าออกเมื่อไร
  const issuedOn = `${lang === 'en' ? 'Issued on' : 'ออกให้เมื่อ'} ${D(doc.issued_on)}`;

  const page1 = `
<div class="page">
  ${stamps(doc)}
  <div class="docno">${docCorner(prog, lang, doc.doc_no)}</div>
  ${titleBlock}

  <div class="head">
    <div class="col l">
      ${field(t.schoolCode, esc(d.institution.code))}
      ${field(t.schoolName, esc(school))}
      ${field(t.province, esc(d.institution_province ?? ''))}
      ${field(t.studentCode, esc(d.student.student_code))}
      ${field(t.name, esc(name))}
      ${/*
          เชื้อชาติ · สัญชาติ · ศาสนา อยู่บนบรรทัดเดียวกันสามช่อง
          ค่าทั้งสามมาจาก person_sensitive กับ person.nationality (0062)
          — ก่อนหน้านี้แม่แบบฮาร์ดโค้ดค่าว่างไว้ ทั้งที่ฐานข้อมูลมีข้อมูลอยู่
        */ ''}
      ${triple(t.ethnicParts, [d.person_extra?.ethnicity, d.person_extra?.nationality,
                               d.person_extra?.religion])}
      ${field(t.birth, esc(D(d.student.birth_date)))}
      ${field(t.citizenId, esc(d.student.national_id ?? ''))}
      ${field(t.father, esc(d.parents?.father ?? ''))}
      ${field(t.mother, esc(d.parents?.mother ?? ''))}
      ${field(t.progType, esc(lang === 'en' ? (prog?.type_en ?? '') : (prog?.type_th ?? '')))}
      ${field(t.careerGroup, esc(d.career_group_th ?? ''))}
      ${field(t.progName, esc(lang === 'en' ? (prog?.name_en ?? '') : (prog?.name_th ?? '')))}
    </div>
    <div class="col r">
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
    </div>
    <div class="photo">${t.photo}</div>
  </div>

  ${courseGrid('g1', c1, c2, lang, k)}

  ${/*
      ค่าสองช่องนี้มาจาก student_status_history (0062) ไม่ใช่ช่องว่างให้เขียนมือ
      — และมีเฉพาะเมื่อสถานะปัจจุบันแปลว่าออกจากสถานศึกษาจริง คนที่กำลังเรียน
      อยู่จะได้หัวข้อพร้อมช่องว่าง ซึ่งตรงกับใบจริงที่ออกให้ระหว่างเรียน
    */ ''}
  <div class="leave">
    <div>${t.leftOn} <span>${esc(d.leaving?.on_date ? D(d.leaving.on_date) : '')}</span></div>
    <div>${t.leftWhy} <span>${esc(d.leaving?.reason ?? '')}</span></div>
  </div>
  ${signBlock(t, issuedOn, d)}
</div>`;

  const criteria = [1, 2, 3, 4, 5]
    .map((i) => d.institution_text?.[`transcript_criteria_${i}`])
    .map((x) => (lang === 'en' ? x?.en : x?.th))
    .filter((x) => x && x.trim() !== '');

  const notes = [1, 2, 3, 4, 5]
    .map((i) => d.institution_text?.[`transcript_note_${i}`])
    .map((x) => (lang === 'en' ? x?.en : x?.th))
    .filter((x) => x && x.trim() !== '');

  /*
   * ─── หน้า 2 ตีกรอบตารางเสมอ แม้จะไม่มีรายวิชาเหลือมาลง ───
   * ใบจริงเป็นแบบฟอร์มที่มีกรอบพิมพ์มาแล้วทั้งสองหน้า นักศึกษาที่ลงวิชาน้อย
   * จึงได้กรอบเปล่าที่หน้า 2 ไม่ใช่หน้าที่หายไปทั้งตาราง — ถ้าเว้นกรอบทิ้ง
   * ใบสองใบของวิทยาลัยเดียวกันจะหน้าตาไม่เหมือนกัน แล้วคนรับใบจะสงสัย
   */
  const page2 = `
<div class="page p2">
  ${stamps(doc)}
  ${titleBlock}
  <div class="page2head">
    <span class="a">${t.name} ${esc(name)}</span>
    <span class="b">${t.studentCode} ${esc(d.student.student_code)}
      ${docCorner(prog, lang, doc.doc_no)}</span>
    <span class="c">${t.page2}</span>
  </div>

  ${courseGrid('g2', c3, c4, lang, k)}

  <div class="legend">
    <div class="col c1">
      <h2>${t.gradeScale}</h2>
      ${/*
          ─── ระดับผลการเรียนเรียงสองคู่ต่อบรรทัด ไม่ใช่แปดบรรทัด ───
          วัดจากใบจริง — เนื้อหาอยู่ที่ x 23.4 กับ x 94.4 บนบรรทัดเดียวกัน
          รวมสี่บรรทัด (544.5 · 558.8 · 573.0 · 588.0) ถ้าเรียงลงมาแปดบรรทัด
          บล็อกนี้จะสูงเป็นสองเท่าแล้วดันช่องลงนามตกขอบกระดาษ
        */ ''}
      <table><tbody>
        ${(() => {
          /*
           * เรียง**คู่ที่ติดกัน**ลงบรรทัดเดียว — 4.0/3.5 · 3.0/2.5 · 2.0/1.5 · 1.0/0
           * ไม่ใช่ผ่าครึ่งรายการ (ซึ่งจะได้ 4.0/2.0 · 3.5/1.5 …) เพราะผู้อ่าน
           * ไล่ระดับคะแนนจากมากไปน้อยทีละครึ่งขั้น การผ่าครึ่งทำให้ต้อง
           * อ่านสลับซ้ายขวาถึงจะเรียงลำดับได้
           */
          const cell = (x: [string, string, string] | undefined) => (x
            ? `<td style="width:16pt">${x[0]}</td><td>= ${lang === 'en' ? x[2] : x[1]}</td>`
            : '<td></td><td></td>');
          const out: string[] = [];
          for (let i = 0; i < GRADE_SCALE.length; i += 2) {
            out.push(`<tr>${cell(GRADE_SCALE[i])}${cell(GRADE_SCALE[i + 1])}</tr>`);
          }
          return out.join('');
        })()}
      </tbody></table>
    </div>
    <div class="col c2">
      <h2>${t.criteria}</h2>
      ${criteria.length
        ? criteria.map((c, i) => `<div>${i + 1}. ${esc(c)}</div>`).join('')
        : `<div style="color:#555">— ยังไม่ได้ตั้งเกณฑ์การสำเร็จหลักสูตรของสถานศึกษา —</div>`}
    </div>
    <div class="col c3">
      <h2>${t.notes}</h2>
      ${notes.map((n, i) => `<div>(*${i + 1})&nbsp; ${t.meaning}&nbsp; ${esc(n)}</div>`).join('')}
    </div>
  </div>

  <div class="letters">
    <h2>${t.gradeLetters}</h2>
    <table><tbody>
      ${(() => {
        /*
         * ─── เรียงลงก่อนแล้วค่อยข้าม ไม่ใช่เรียงข้ามก่อนแล้วค่อยลง ───
         * ใบจริงเรียงตามคอลัมน์ — คอลัมน์แรก ข.ร./ข.ป./ข.ส./ท. คอลัมน์ที่สอง
         * ผ./ม.ผ./ถ.น./ถ.ล. ซึ่งจับกลุ่มความหมายไว้ด้วยกัน (ขาด… · ผ่าน/ถอน ·
         * ไม่สมบูรณ์) การเรียงทีละแถวจะฉีกกลุ่มเหล่านั้นกระจายคนละคอลัมน์
         */
        const cols = 3;
        const rowsN = Math.ceil(GRADE_LETTERS.length / cols);
        const out: string[] = [];
        for (let r = 0; r < rowsN; r += 1) {
          const cells: string[] = [];
          for (let c = 0; c < cols; c += 1) {
            const x = GRADE_LETTERS[c * rowsN + r];
            cells.push(x
              ? `<td>${lang === 'en' ? `${x[1]} = ${x[3]}` : `${x[0]} = ${x[2]}`}</td>`
              : '<td></td>');
          }
          out.push(`<tr>${cells.join('')}</tr>`);
        }
        return out.join('');
      })()}
    </tbody></table>
  </div>

  <div class="memo">
    <h2>${t.memo}</h2>
    ${/* ใบจริงมีเส้นประสี่บรรทัด (704.2 · 717.0 · 730.5 · 743.2) ไม่ใช่ห้า */ ''}
    <div class="lines"><div></div><div></div><div></div><div></div></div>
  </div>

  ${signBlock(t, issuedOn, d)}
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

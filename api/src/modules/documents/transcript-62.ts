/**
 * ใบ รบ. ตระกูล 62 — จัดกลุ่มตามภาคเรียน ทั้งฉบับไทยและอังกฤษ
 *
 * ═══ ตัวเลขทั้งหมดวัดจากไฟล์จริง ไม่ได้เดา ═══
 * วัดจาก `ระเบียนแสดงผลการเรียนภาษาไทย (แนวตั้ง 62).pdf` และฉบับอังกฤษคู่กัน
 *   A4 แนวตั้ง 595 × 842 pt · ฟอนต์ THSarabunNew 12.5 pt
 *   กรอบตารางอยู่ที่ x 22.0 → 572.1 · เส้นหนา 0.72 pt (บางกว่าตระกูล 67
 *   ที่ใช้ 1.5 pt) และเส้นใต้หัวตารางเป็น**เส้นคู่** รวมหนา 1.45 pt
 *   ขอบคอลัมน์ x = 22.4 · 70.8 · 227.7 · 250.8 · 273.9 · 297.1 (ครึ่งซ้าย)
 *   → รหัสวิชา 48.4 · ชื่อวิชา 156.9 · หน่วยกิต 23.1 · ผลการเรียน 23.1 ·
 *     (1)×(2) 23.2
 *   ครึ่งขวาสมมาตร เริ่มที่ 297.1
 *
 * ═══ ตารางถูกตีกรอบไว้ก่อน รายวิชาค่อยไหลลงไป ═══
 * เหมือนตระกูล 67 ทุกประการ ต่างแค่ตัวเลข — กรอบสูงคงที่ (หน้า 1 สูง 481.4 pt ·
 * หน้า 2 สูง 437.6 pt) หนึ่งบรรทัดสูง 15.43 pt จึงจุคอลัมน์ละ 28 บรรทัด
 * ที่หน้า 1 และ 25 บรรทัดที่หน้า 2 ไม่ว่านักศึกษาจะลงกี่วิชา
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
import { TRANSCRIPT_FONT_FACE } from './fonts';
import { engDate, engYear, thaiDate } from './templates';

/**
 * รูปแบบย่อยของตระกูลนี้
 *
 * ═══ ทำไมรูปแบบนี้ผู้ใช้เลือกได้ ทั้งที่รุ่นหลักสูตรเลือกไม่ได้ ═══
 * การเลือกระหว่างตระกูล 67 กับ 62 **ต้องมาจาก payload** เพราะสองตระกูล
 * จัดกลุ่มรายวิชาคนละแบบ (หมวดวิชา ↔ ภาคเรียน) เอาผิดรุ่นไปพิมพ์จะได้ใบที่
 * จัดกลุ่มผิดหลักสูตร ซึ่งคนที่ไม่รู้ว่าควรเป็นแบบไหนมองไม่ออก
 *
 * ส่วน `62` กับ `sorsor` **จัดกลุ่มเหมือนกันทุกประการ** ต่างกันแค่ที่วาง
 * สรุปรายภาค (ไหลในตาราง ↔ ตารางสรุปแนวนอนหน้า 2) กับถ้อยคำระดับผลการเรียน
 * หนึ่งคำ — ตัวเลขบนใบเหมือนกันหมด การเลือกจึงเป็นเรื่องของหน่วยงาน
 * ที่จะยื่นให้ ไม่ใช่ข้อเท็จจริงของนักศึกษา
 */
export type Transcript62Form = '62' | 'sorsor';

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
  /**
   * เลขเครื่องหมาย (*1)–(*5) ที่ต้องพิมพ์ท้ายชื่อวิชา
   *
   * ตัวเลือก เพราะใบที่ออกก่อน 0066 ไม่มีช่องนี้ใน payload และ payload
   * แก้ไม่ได้ — ใบเก่าต้องพิมพ์ซ้ำได้เหมือนวันที่ออกทุกประการ
   */
  notes?: number[] | null;
}

/**
 * เครื่องหมาย (*n) ท้ายชื่อวิชา
 *
 * ต่อท้ายชื่อในคอลัมน์เดิม ไม่เพิ่มคอลัมน์ใหม่ — กรอบตารางวัดมาจากไฟล์จริง
 * แล้วตรึงไว้ (เส้นตั้ง 11 เส้น สูง 480.6/437.3 pt) และใบจริงก็พิมพ์
 * เครื่องหมายไว้ท้ายชื่อวิชาอยู่แล้ว
 */
function noteSuffix(notes?: number[] | null): string {
  if (!notes || notes.length === 0) return '';
  return ' ' + notes.map((n) => `(*${n})`).join('');
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
    summaryTitle: 'สรุปผลการเรียน', semester: 'ภาคเรียน',
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
    summaryTitle: 'Summary of Results', semester: 'Semester',
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
 * แบบ สอศ. ใช้ถ้อยคำไทยของ 2.5 ต่างออกไปหนึ่งคำ
 *
 * `ดีพอใช้` ไม่ใช่ `ค่อนข้างดี` — วัดจากไฟล์จริงทั้งสองแบบ ส่วนฉบับอังกฤษ
 * ใช้ถ้อยคำชุดเดียวกันทั้งคู่ ความต่างจึงอยู่ฝั่งไทยที่เดียว
 *
 * รวมเป็นชุดเดียวไม่ได้ เพราะจะทำให้ใบใดใบหนึ่งผิดเสมอ
 */
const GRADE_SCALE_SORSOR: [string, string, string][] = GRADE_SCALE_62.map(
  (row) => (row[0] === '2.5' ? ['2.5', 'ดีพอใช้', row[2]] : row),
) as [string, string, string][];

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

/* ─── เรขาคณิตที่วัดจากไฟล์จริง (pt) ────────────────────────────── */

/**
 * เหมือน `G` ของตระกูล 67 แต่เป็นตัวเลขของตระกูลนี้ — ห้ามใช้ปนกัน
 *
 * พิกัดทุกตัวนับจากมุมซ้ายบนของกรอบตาราง (x = 22.4 · y = 271.04 ที่หน้า 1)
 */
const G = {
  /** ความหนาเส้น — บางกว่าตระกูล 67 ครึ่งหนึ่ง */
  rule: 0.72,
  /** เส้นตั้ง 11 เส้น (x จริง 22.4 · 70.8 · 227.7 · 250.8 · 273.9 · 297.1 · … · 571.7) */
  vRules: [0, 48.4, 205.3, 228.4, 251.5, 274.7, 323.1, 479.9, 503.0, 526.2, 549.3],
  /** ความกว้างกรอบ = เส้นขวาสุด + ความหนาเส้น */
  width: 550.02,
  /** ความกว้างคอลัมน์ครึ่งซ้าย รวม 274.7 */
  cols: [48.4, 156.9, 23.1, 23.1, 23.2],
  halfWidth: 274.7,
  /** ครึ่งขวาใช้เส้นกลางร่วมกับครึ่งซ้าย */
  rightHalf: 274.7,
  /** หัวตารางสูง 45.53 pt แล้วต่อด้วย**เส้นคู่**หนารวม 1.45 */
  headHeight: 45.53,
  headRule: 1.45,
  /** เส้นใต้หัวตารางอยู่ที่ 46.25 จากขอบบนกรอบ */
  headRuleTop: 46.25,
  /** แถวแรกของเนื้อตารางเริ่มที่ 47.70 จากขอบบนกรอบ */
  bodyTop: 47.7,
  /** ความสูงหนึ่งบรรทัด — 15.43 pt ที่ฟอนต์ 12.5 pt */
  rowEm: 1.2344,
  rowPt: 15.43,
  /** ความสูงกรอบ (คงที่) — หน้า 1 271.04→751.67 · หน้า 2 93.96→531.23 */
  gridH: { p1: 480.63, p2: 437.27 },
  /** ที่ว่างใต้หัวตาราง */
  body: { p1: 432.21, p2: 388.85 },
  /** ความกว้างที่ข้อความในคอลัมน์ชื่อวิชาใช้ได้ (156.9 − ระยะขอบ) */
  nameWidth: 153.5,
} as const;

/* ─── สไตล์ที่ตรงกับตัวเลขที่วัดมา ──────────────────────────────── */

/**
 * ─── ขอบบนต่างกันตามภาษาโดยตั้งใจ ───
 * ฉบับไทยไม่มีบรรทัดชื่อเรื่อง จึงเว้น 76 pt ให้หัวกระดาษที่พิมพ์มาแล้ว
 * ฉบับอังกฤษมีชื่อเรื่องอยู่ในเนื้อ จึงเริ่มที่ 12 pt แล้วชื่อเรื่องกินที่แทน
 */
function style(lang: 'th' | 'en', form: Transcript62Form): string {
  const topMargin = lang === 'en' ? 12 : 76;
  // แบบ สอศ. วัดได้ 10.6 pt ในตาราง เพราะต้องเว้นที่ให้ตารางสรุปหน้า 2
  const tableFont = form === 'sorsor' ? 10.6 : 12.5;
  return `
  ${TRANSCRIPT_FONT_FACE}
  @page { size: A4 portrait; margin: ${topMargin}pt 22.6pt 13pt 22.4pt; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    /*
     * ─── ฟอนต์เป้าหมายคือ THSarabunNew และ**ฝังมากับหน้าแล้ว** ───
     * ชื่อในรายการนี้ตรงกับ @font-face ที่ฝังไว้ ไม่ใช่ฟอนต์ในเครื่อง
     * ตัวสำรองมีไว้เผื่อฟอนต์ฝังโหลดไม่ขึ้น และเรียงตามความกว้างที่วัดจริง —
     * THSarabunNew 0.361 em/อักขระไทย · AngsanaNew 0.389 · **LeelawadeeUI 0.530**
     * ของเดิมวาง Leelawadee UI ไว้ก่อน ซึ่งกว้างกว่าเป้าหมาย 45% แล้วตารางล้น
     * กรอบทั้งใบ (เหตุผลเต็มอยู่ใน transcript-67.ts ซึ่งใช้ตรรกะเดียวกัน)
     */
    font-family: 'TH Sarabun New', 'TH SarabunPSK', 'THSarabunNew', 'Sarabun',
                 'Angsana New', 'AngsanaUPC', 'Cordia New', serif;
    font-size: 12.5pt; line-height: 1.27; color: #000;
  }
  .page { position: relative; page-break-after: always; }
  .page:last-child { page-break-after: auto; }

  .docno { text-align: right; font-size: 13.5pt; margin-bottom: 2pt; }
  h1 { font-size: 19.3pt; font-weight: 700; text-align: center; margin: 0 0 2pt; }
  h1.sub { font-size: 19.3pt; margin-bottom: 10pt; }

  /* บล็อกหัว — สองคอลัมน์ label/value พร้อมกรอบรูปถ่ายขวาสุด
     ระยะใต้บล็อกตั้งไว้ 4.24 pt เพื่อให้เส้นบนสุดของตารางตกที่ y = 271.0
     พอดีตามที่วัดจากใบจริง (76 ขอบบน + 190.8 บล็อกหัว + 4.24) */
  .head { display: flex; gap: 0; align-items: flex-start; margin-bottom: 4.24pt; }
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

  /*
   * ─── กรอบตารางสูงคงที่ ตีเส้นก่อน แล้วรายวิชาค่อยไหลลงไป ───
   * เหตุผลเดียวกับตระกูล 67 — ตาราง HTML สูงตามเนื้อหาเสมอ กรอบจึง
   * ต้องเป็นกล่องต่างหากที่รู้ความสูงของตัวเอง ส่วนตารางข้างในไม่มี
   * เส้นของตัวเองเลย ทำหน้าที่จัดข้อความลงช่องอย่างเดียว
   */
  .grid { position: relative; width: ${G.width}pt; height: var(--gh); }
  .grid.g1 { --gh: calc(${G.gridH.p1}pt - var(--shrink, 0pt)); }
  .grid.g2 { --gh: calc(${G.gridH.p2}pt - var(--shrink, 0pt)); }
  .grid i { position: absolute; background: #000; }
  .grid i.v { top: 0; bottom: 0; width: ${G.rule}pt; }
  .grid i.h { left: 0; right: 0; height: ${G.rule}pt; }
  .grid i.h.top { top: 0; }
  /* เส้นใต้หัวตารางของตระกูลนี้เป็น**เส้นคู่** (วัดได้ 317.29–318.02 และ
     318.02–318.74) ต่างจากตระกูล 67 ที่เป็นเส้นเดี่ยวหนา 1.5 */
  .grid i.h.mid { top: ${G.headRuleTop}pt; height: ${G.headRule}pt; }
  .grid i.h.bot { bottom: 0; }

  table.courses {
    position: absolute; width: ${G.halfWidth}pt;
    table-layout: fixed; border-collapse: collapse;
    font-size: calc(${tableFont}pt * var(--k, 1));
  }
  table.courses.hd { top: ${G.rule}pt; }
  table.courses.bd { top: ${G.bodyTop}pt; }
  table.courses.r  { left: ${G.rightHalf}pt; }
  table.courses th, table.courses td {
    border: 0; padding: 0 1.6pt 0 1.6pt; vertical-align: top;
  }
  table.courses.hd th { height: ${G.headHeight}pt; font-weight: 400;
    text-align: center; vertical-align: middle; }
  table.courses.hd th span {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    height: ${G.headHeight}pt; line-height: 1.05; overflow: hidden;
  }
  table.courses td { height: ${G.rowEm}em; line-height: ${G.rowEm}em; }
  table.courses td.code { white-space: nowrap; }
  table.courses td.num  { text-align: center; }
  /* หัวภาคเรียนและบรรทัดสรุปอยู่ในคอลัมน์ชื่อวิชา ไม่กินคอลัมน์ตัวเลข */
  table.courses td.term { text-align: center; font-weight: 700; }
  table.courses td.termsum { text-align: center; font-size: 0.928em; }

  /* ใต้ตารางหน้า 1 — วัดจากใบจริง: ออกจากสถานศึกษาเมื่อ 763.2 · เหตุที่ออก
     777.0 · ชื่อในวงเล็บ 790.7 · ตำแหน่ง 807.3 · บรรทัดวันที่ 823.2
     ตรึงความสูงไว้เพื่อไม่ให้ช่องลงนามตกขอบล่างของกระดาษ */
  .leave { margin-top: 0; padding-left: 7.6pt; }
  .leave div { height: 13.8pt; line-height: 13.8pt; }
  .signs { display: flex; justify-content: space-around; margin-top: 0; text-align: center; }
  .sign { width: 40%; font-size: 13.5pt; }
  .sign div { height: 16.5pt; line-height: 16.5pt; }
  .sign .role { font-size: 12.5pt; }

  /*
   * ท้ายหน้า 2 — วางตาม x ที่วัดได้ 16 · 183 · 382 และช่องบันทึกอยู่
   * **ใต้สองคอลัมน์แรก** ไม่ใช่ใต้ทั้งสามคอลัมน์ (เส้นประวัดได้ x 51.9–323.8)
   */
  .legend { display: flex; gap: 0; font-size: 11.6pt; margin-top: 14.5pt; }
  .legend .lcol { width: 365.6pt; }
  .legend .sub { display: flex; gap: 0; }
  .legend .col1 { width: 166.6pt; }
  .legend .col2 { width: 199pt; }
  .legend .col3 { width: 184.4pt; }
  .legend h2 { font-size: 11.6pt; font-weight: 700; margin: 0 0 3pt; }
  .legend table { border-collapse: collapse; width: 100%; }
  .legend td { padding: 0; vertical-align: top; }
  .legend div { line-height: 14.45pt; }
  /* ตารางสรุปผลการเรียนของแบบ สอศ. — หนึ่งคอลัมน์ต่อหนึ่งภาคเรียน */
  .matrix { margin-top: 8pt; font-size: 11.6pt; }
  .matrix h2 { font-size: 11.6pt; font-weight: 700; margin: 0 0 3pt; }
  .matrix table { border-collapse: collapse; }
  .matrix th, .matrix td {
    border: 0.6pt solid #000; padding: 0 5pt; text-align: center; font-weight: 400;
    min-width: 34pt;
  }
  .matrix th.lab { text-align: left; font-weight: 400; white-space: nowrap; }

  /* ช่องบันทึก — หัวข้อ 13.5 pt แล้วเส้นประห้าบรรทัดกว้าง 272 pt ที่ x 51.9
     (เดิมพิมพ์เป็นจุด 120 ตัวซึ่งความยาวขึ้นกับฟอนต์ที่เครื่องมี — ใช้เส้น
      ใต้กรอบแทน ความยาวจึงเท่าที่วัดมาเสมอ) */
  .memo { margin-top: 22.6pt; font-size: 13.5pt; }
  .memo .lines { margin-left: 29.5pt; width: 271.9pt; }
  .memo .lines div { border-bottom: 0.6pt dotted #000; height: 14.45pt; }

  .stamp {
    position: absolute; top: 300pt; left: 0; right: 0; text-align: center;
    font-size: 64pt; font-weight: 700; color: rgba(200, 0, 0, 0.22);
    transform: rotate(-20deg); pointer-events: none;
  }
  .stamp.copy { top: 420pt; font-size: 44pt; }
  .void-note { color: #a00; font-size: 11pt; text-align: center; }

  /*
   * ─── หน้าจอต้องเท่ากับกระดาษ ───
   * เจ้าหน้าที่เปิดหน้านี้ในแท็บใหม่แล้วกด Ctrl+P ถ้าบนจอไหลเต็มความกว้าง
   * เบราว์เซอร์ จะไม่มีทางรู้ก่อนกดพิมพ์ว่าตารางล้นกรอบหรือตกหน้าหรือเปล่า
   * — ซึ่งเป็นเรื่องเดียวกับที่ทำให้ปุ่มพิมพ์ทุกปุ่มเคยได้ 401 โดยไม่มีใครเห็น
   */
  @media screen {
    body { background: #f4f4f4; padding: 14px; }
    .page { background: #fff; width: 595pt; height: 841.9pt;
            margin: 0 auto 14px; padding: ${topMargin}pt 22.6pt 13pt 22.4pt;
            box-shadow: 0 1px 6px rgba(0,0,0,.25); }
  }
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

function buildRows(
  terms: Term62[],
  lang: 'th' | 'en',
  t: typeof L['th'] | typeof L['en'],
  form: Transcript62Form,
): Row62[] {
  const out: Row62[] = [];
  for (const term of terms) {
    out.push({ kind: 'term', text: termHeading(term, lang) });
    for (const c of term.courses ?? []) out.push({ kind: 'course', course: c });
    /*
     * แบบ สอศ. ย้ายสรุปรายภาคทั้งหมดไปเป็นตารางแนวนอนที่หน้า 2
     * (หนึ่งคอลัมน์ต่อหนึ่งภาค) — ถ้าพิมพ์ทั้งสองที่จะได้ตัวเลขชุดเดียวกัน
     * สองครั้งบนใบเดียว ซึ่งคนอ่านจะสงสัยว่าทำไมไม่เท่ากัน (ทั้งที่เท่ากัน)
     */
    if (form === '62') {
      out.push({
        kind: 'sum',
        line1: `${t.termCredits} ${credits(term.credits_earned)} ${t.cumCredits} ${credits(term.credits_cum)}`,
        line2: `${t.termGpa} ${gpa(term.gpa)} ${t.cumGpa} ${gpa(term.gpax)}`,
      });
    }
  }
  return out;
}

/**
 * ตารางสรุปผลการเรียนแนวนอน — หนึ่งคอลัมน์ต่อหนึ่งภาคเรียน
 *
 * เป็นตัวเลขชุดเดียวกับที่แบบ 62 พิมพ์ไหลอยู่ในตารางรายวิชา แค่จัดวางใหม่
 * — ไม่ได้คำนวณอะไรเพิ่ม ทุกค่ามาจาก `term_tree` ที่ตรึงลง payload แล้ว
 */
function summaryMatrix(
  terms: Term62[],
  lang: 'th' | 'en',
  t: typeof L['th'] | typeof L['en'],
): string {
  if (terms.length === 0) return '';
  const head = terms
    .map((x) => `<th>${lang === 'en' ? `${x.ordinal}/${x.year_be - 543}` : `${x.ordinal}/${x.year_be}`}</th>`)
    .join('');
  const row = (label: string, cells: string[]) =>
    `<tr><th class="lab">${label}</th>${cells.map((c) => `<td>${c}</td>`).join('')}</tr>`;

  return `<div class="matrix">
    <h2>${t.summaryTitle}</h2>
    <table><tbody>
      <tr><th class="lab">${t.semester}</th>${head}</tr>
      ${row(t.termCredits, terms.map((x) => credits(x.credits_earned)))}
      ${row(t.cumCredits, terms.map((x) => credits(x.credits_cum)))}
      ${row(t.termGpa, terms.map((x) => gpa(x.gpa)))}
      ${row(t.cumGpa, terms.map((x) => gpa(x.gpax)))}
    </tbody></table>
  </div>`;
}

function renderRow(r: Row62, lang: 'th' | 'en'): string {
  /*
   * ─── หัวภาคและบรรทัดสรุปอยู่ในคอลัมน์ชื่อวิชาช่องเดียว ไม่ใช่ colspan ───
   * เหตุผลเดียวกับตระกูล 67 — ใบจริงเว้นช่องหน่วยกิต/ผลการเรียน/ผลคูณไว้ว่าง
   * ถ้ากินทั้งแถว ข้อความยาวจะไหลไปทับคอลัมน์ตัวเลข แล้วบรรทัดสรุปจะดูเหมือน
   * รายวิชาที่ไม่มีหน่วยกิต
   */
  if (r.kind === 'term') {
    return `<tr><td></td><td class="term">${r.text}</td><td></td><td></td><td></td></tr>`;
  }
  if (r.kind === 'sum') {
    const line = (x: string) =>
      `<tr><td></td><td class="termsum">${esc(x)}</td><td></td><td></td><td></td></tr>`;
    return line(r.line1) + line(r.line2);
  }
  const c = r.course;
  /*
   * ─── ชื่อวิชาภาษาไทยบนใบภาษาอังกฤษคือสิ่งที่ต้องไม่เกิด ───
   * ไฟล์ที่ SISA ออกจริงมีชื่อวิชาไทยปนอยู่ในตารางอังกฤษ เพราะยอมออกใบ
   * ทั้งที่ข้อมูลอังกฤษไม่ครบ — 0057 ปฏิเสธไปแล้วตั้งแต่ขั้นออกใบ
   * ตรงนี้จึงใช้ชื่ออังกฤษตรง ๆ ได้โดยไม่ต้อง fallback เป็นไทย
   */
  const courseName = (lang === 'en' ? c.name_en : c.name_th) + noteSuffix(c.notes);
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

/* ─── ความจุของกรอบ ─────────────────────────────────────────────── */

/** สระบน/ล่างและวรรณยุกต์ไทยลอยอยู่เหนือหรือใต้ตัวอักษร ไม่กินความกว้าง */
const THAI_MARKS = /[ัิ-ฺ็-๎]/g;

/**
 * เผื่อความกว้างไว้ 5% เพราะเครื่องที่ไม่มี TH Sarabun จะได้ Angsana ซึ่ง
 * กว้างกว่า 6.6% — เผื่อมากไปแค่ทำให้คอลัมน์จบก่อนถึงเส้นล่างนิดหน่อย
 * ส่วนเผื่อน้อยไปทำให้รายวิชาทะลุกรอบไปทับบรรทัดใต้ตาราง
 */
const WIDTH_SAFETY = 1.05;

/** ความกว้างเฉลี่ยต่ออักขระของ THSarabunNew วัดจากไฟล์ต้นฉบับ */
function estimateLines(text: string, availPt: number, fontPt: number): number {
  let em = 0;
  for (const ch of text.replace(THAI_MARKS, '')) {
    em += ch >= '฀' && ch <= '๿' ? 0.365 : 0.33;
  }
  return Math.max(1, Math.ceil((em * fontPt * WIDTH_SAFETY) / availPt));
}

/** จำนวนบรรทัดที่แถวหนึ่งกินจริง — แถวสรุปเป็นสองบรรทัดเสมอ */
function rowLines(r: Row62, lang: 'th' | 'en', fontPt: number): number {
  if (r.kind === 'course') {
    /*
     * ต้องนับความกว้างของ (*n) เข้าไปด้วย มิฉะนั้นตัวคำนวณความจุจะบอกว่า
     * ลงครบทั้งที่ชื่อวิชายาวขึ้นจนตัดบรรทัดเพิ่ม แล้วตารางล้นกรอบ —
     * เป็นอาการเดียวกับเรื่องฟอนต์สำรองที่กว้างกว่าเดิม 47%
     */
    return estimateLines(
      (lang === 'en' ? r.course.name_en : r.course.name_th) + noteSuffix(r.course.notes),
      G.nameWidth, fontPt);
  }
  if (r.kind === 'term') return estimateLines(r.text, G.nameWidth, fontPt);
  // บรรทัดสรุปพิมพ์ที่ 0.928 em ของขนาดตาราง จึงเตี้ยกว่าแถวปกติเล็กน้อย
  return estimateLines(r.line1, G.nameWidth, fontPt * 0.928)
       + estimateLines(r.line2, G.nameWidth, fontPt * 0.928);
}

function packColumns(
  rows: Row62[], lang: 'th' | 'en', baseFont: number, k: number,
): Row62[][] | null {
  const fontPt = baseFont * k;
  const caps = [G.body.p1, G.body.p1, G.body.p2, G.body.p2]
    .map((h) => Math.floor(h / (G.rowPt * k)));
  const out: Row62[][] = [[], [], [], []];
  let slot = 0;
  let used = 0;
  for (const r of rows) {
    const need = rowLines(r, lang, fontPt);
    if (used + need > caps[slot]) { slot += 1; used = 0; }
    /*
     * ─── ห้ามให้หัวภาคเป็นบรรทัดสุดท้ายของคอลัมน์ ───
     * ถ้าตัดตรงนั้น รายวิชาของภาคนั้นจะขึ้นไปอยู่คอลัมน์ถัดไปโดยไม่มีหัวกำกับ
     * ผู้อ่านจะนับรวมกับภาคก่อนหน้า ซึ่งเป็นความผิดพลาดที่อ่านไม่ออกจากใบ
     */
    if (slot >= out.length) return null;
    out[slot].push(r);
    used += need;
  }
  // ย้ายหัวภาคที่ค้างอยู่ท้ายคอลัมน์ไปต้นคอลัมน์ถัดไป
  for (let i = 0; i < out.length - 1; i += 1) {
    while (out[i].length > 0 && out[i][out[i].length - 1].kind === 'term') {
      out[i + 1].unshift(out[i].pop()!);
    }
  }
  return out;
}

const FIT_SCALES = [1, 0.95, 0.9, 0.85, 0.8, 0.75] as const;

/**
 * หาขนาดฟอนต์ที่ทำให้รายวิชาลงครบในกรอบสองหน้าที่มีอยู่
 *
 * เหตุผลเดียวกับตระกูล 67 — ต่อหน้าที่สามไม่ได้เพราะของประจำหน้า 2 ต้องอยู่
 * หน้าสุดท้าย · ปล่อยล้นคือให้รายวิชาทับช่องลงนาม · ตัดทิ้งคือออกใบที่ขาด
 * รายวิชาโดยไม่มีอะไรบอก ซึ่งแย่ที่สุดเพราะ payload ที่ตรึงแล้วแก้ไม่ได้
 */
function fitColumns(
  rows: Row62[], lang: 'th' | 'en', baseFont: number,
): { k: number; cols: Row62[][] } {
  for (const k of FIT_SCALES) {
    const cols = packColumns(rows, lang, baseFont, k);
    if (cols) return { k, cols };
  }
  const k = FIT_SCALES[FIT_SCALES.length - 1];
  const cap = Math.floor(G.body.p1 / (G.rowPt * k));
  const out: Row62[][] = [[], [], [], []];
  let slot = 0;
  let used = 0;
  for (const r of rows) {
    const need = rowLines(r, lang, baseFont * k);
    if (used + need > cap && slot < out.length - 1) { slot += 1; used = 0; }
    out[slot].push(r);
    used += need;
  }
  return { k, cols: out };
}

/**
 * กรอบตารางหนึ่งหน้า — ตีเส้นก่อน แล้วค่อยวางรายวิชาลงไป
 *
 * เส้นตั้ง 9 เส้นภายใน (ขอบนอกซ้าย-ขวาเป็น border ของกรอบเอง) กับเส้นคู่
 * ใต้หัวตารางหนึ่งเส้น ทั้งหมดวางตามพิกัดที่วัดมาและไม่ขึ้นกับเนื้อหาเลย
 */
function courseGrid(
  page: 'g1' | 'g2', left: Row62[], right: Row62[],
  t: typeof L['th'] | typeof L['en'], lang: 'th' | 'en', k: number,
): string {
  const cols = `<colgroup>${G.cols.map((w) => `<col style="width:${w}pt">`).join('')}</colgroup>`;
  const head = (side: 'l' | 'r') => `<table class="courses hd ${side}">${cols}<tbody><tr>`
    + [t.colCode, t.colName, t.colCredit, t.colGrade, t.colProduct]
      .map((h) => `<th><span>${h}</span></th>`).join('')
    + '</tr></tbody></table>';
  const body = (rows: Row62[], side: 'l' | 'r') => `<table class="courses bd ${side}">`
    + `${cols}<tbody>${rows.map((r) => renderRow(r, lang)).join('')}</tbody></table>`;

  const rules = G.vRules.map((x) => `<i class="v" style="left:${x}pt"></i>`).join('')
    + '<i class="h top"></i><i class="h mid"></i><i class="h bot"></i>';

  return `<div class="grid ${page}" style="--k:${k}">${rules}`
    + head('l') + head('r') + body(left, 'l') + body(right, 'r')
    + '</div>';
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

export function renderTranscript62(
  doc: Transcript62Document,
  form: Transcript62Form = '62',
): string {
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

  const rows = buildRows(d.term_tree ?? [], lang, t, form);
  /*
   * สองหน้าตายตัวเหมือนตระกูล 67 — หน้า 2 มีของประจำที่ต้องอยู่หน้า 2
   * ตัดตาม**จำนวนบรรทัดที่กินจริง** ไม่ใช่จำนวนแถว เพราะกรอบสูงคงที่
   */
  const { k, cols: [c1, c2, c3, c4] } =
    fitColumns(rows, lang, form === 'sorsor' ? 10.6 : 12.5);

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

  ${courseGrid('g1', c1, c2, t, lang, k)}

  <div class="leave"><div>${t.leftOn}</div><div>${t.leftWhy}</div></div>
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

  ${courseGrid('g2', c3, c4, t, lang, k)}

  ${form === 'sorsor' ? summaryMatrix(d.term_tree ?? [], lang, t) : ''}

  ${/*
      ─── ท้ายหน้า 2 เป็นสองภาค ไม่ใช่สามคอลัมน์เรียงกัน ───
      วัดจากใบจริง — เกณฑ์การสำเร็จหลักสูตร (x 16) กับหมายเหตุ (x 183) จบที่
      y ≈ 628 แล้ว **ช่องบันทึกเริ่มที่ y 651 กินความกว้างของสองคอลัมน์นั้น**
      (เส้นประวัดได้ x 51.9–323.8) ส่วนคอลัมน์ระดับผลการเรียน (x 382) ไหลยาว
      ลงไปถึง y 772 อยู่ข้าง ๆ ช่องบันทึก
      ถ้าวางช่องบันทึกไว้ใต้ทั้งสามคอลัมน์ตามที่เคยทำ เนื้อหาจะยาวเกินกระดาษ
      แล้วหน้า 2 จะล้นไปหน้า 3 ซึ่งทำให้ใบไม่ใช่ใบสองหน้าอีกต่อไป
    */ ''}
  <div class="legend">
    <div class="lcol">
      <div class="sub">
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
      </div>
      <div class="memo">${t.memo}
        <div class="lines">${('<div></div>').repeat(5)}</div>
      </div>
    </div>
    <div class="col3">
      <h2>${t.gradeScale}</h2>
      <table><tbody>
        ${(() => {
          const scale = form === 'sorsor' ? GRADE_SCALE_SORSOR : GRADE_SCALE_62;
          const out: string[] = [];
          for (let i = 0; i < scale.length; i += 2) {
            const [a, ath, aen] = scale[i];
            const b = scale[i + 1];
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
</div>`;

  const heading = lang === 'en'
    ? `Transcript ${doc.doc_no}`
    : `ระเบียนแสดงผลการเรียน ${doc.doc_no}`;

  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<title>${esc(heading)}</title>
<style>${style(lang, form)}</style>
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

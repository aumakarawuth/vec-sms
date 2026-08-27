/**
 * แม่แบบไฟล์นำเข้านักศึกษา ImportFull_VocationalEducation.xlsx (รูปแบบ SISA)
 *
 * ไฟล์นี้มีหัวตารางสองแถว (แถวที่ 2 แตกคอลัมน์ที่อยู่ออกเป็นรายละเอียด) แล้ว
 * ข้อมูลจริงเริ่มแถวที่ 3 — ตำแหน่งคอลัมน์คงที่ตามแม่แบบ ไม่อ่านจากชื่อหัว
 * เพราะหัวคอลัมน์ซ้ำกัน (เช่น "ที่อยู่"/"จังหวัด" ปรากฏสองรอบสำหรับที่อยู่
 * ปัจจุบันกับตามทะเบียนบ้าน) อ้างชื่อไม่ได้ ต้องอ้างตำแหน่ง
 *
 * คอลัมน์ 9–12 (ประเภทวิชา/สาขาวิชา/หลักสูตร/ระดับชั้น) ไม่ถูกแมปไปที่ไหน
 * โดยตั้งใจ — ดูเหตุผลในคอมเมนต์บนสุดของ db/migrations/0087_*.sql
 * (ต้นไม้หลักสูตรของระบบนี้ลึกกว่าที่ไฟล์ให้ข้อมูลพอจะเดา)
 *
 * ไฟล์ไม่มีคอลัมน์ "ปีที่เข้าศึกษา" (admitted_year_be) เลย เพราะ SISA ผูก
 * ปีเข้ากับรอบรับสมัครของตัวเองอยู่แล้ว — หน้าจอนำเข้าจึงต้องถามค่านี้แยก
 * แล้วใส่ให้ทุกแถวเหมือนกัน (ดู studentImportBatchDefaults ในหน้าจอ)
 */

type CellValue = string | number | null;

function s(v: CellValue | undefined): string {
  if (v == null) return '';
  return String(v).trim();
}

const GENDER_TH: Record<string, string> = {
  'ชาย': 'male',
  'หญิง': 'female',
  'อื่นๆ': 'other',
  'อื่น ๆ': 'other',
};

function mapGender(v: CellValue | undefined): string {
  const t = s(v);
  return GENDER_TH[t] ?? (t ? 'other' : '');
}

/** วันที่จากไฟล์อาจเป็นเลข serial ของ Excel หรือข้อความ "YYYY-MM-DD" อยู่แล้ว */
function mapDate(v: CellValue | undefined): string {
  if (v == null || v === '') return '';
  if (typeof v === 'number') {
    const ms = Math.round((v - 25569) * 86400 * 1000);
    return new Date(ms).toISOString().slice(0, 10);
  }
  return String(v).trim();
}

/**
 * แปลงหนึ่งแถวของไฟล์ (array ตามตำแหน่งคอลัมน์ 0-based) เป็น payload
 * ที่ `POST /import` (kind: 'student') รับได้ตรง ๆ — ชื่อคีย์ต้องตรงกับ
 * ที่ validate_student_row / apply_student_import อ่านใน 0023 และ 0087
 */
export function mapStudentImportRow(
  row: CellValue[],
  admittedYearBe: string,
): Record<string, string> {
  const p: Record<string, string> = {};
  const set = (key: string, v: string) => {
    if (v !== '') p[key] = v;
  };

  set('student_code', s(row[1]));
  set('prefix_th', s(row[2]));
  set('first_name_th', s(row[3]));
  set('last_name_th', s(row[4]));
  set('prefix_en', s(row[5]));
  set('first_name_en', s(row[6]));
  set('last_name_en', s(row[7]));
  set('birth_date', mapDate(row[8]));
  set('room_code', s(row[13]));
  set('class_number', s(row[14]));
  set('national_id', s(row[15]));
  set('phone', s(row[16]));
  set('phone2', s(row[17]));
  set('guardian_national_id', s(row[18]));
  set('guardian_prefix_th', s(row[19]));
  set('guardian_first_name_th', s(row[20]));
  set('guardian_last_name_th', s(row[21]));
  set('guardian_phone', s(row[22]));
  set('guardian_phone2', s(row[23]));
  set('father_national_id', s(row[24]));
  set('father_prefix_th', s(row[25]));
  set('father_first_name_th', s(row[26]));
  set('father_last_name_th', s(row[27]));
  set('father_phone', s(row[28]));
  set('father_phone2', s(row[29]));
  set('mother_national_id', s(row[30]));
  set('mother_prefix_th', s(row[31]));
  set('mother_first_name_th', s(row[32]));
  set('mother_last_name_th', s(row[33]));
  set('mother_phone', s(row[34]));
  set('mother_phone2', s(row[35]));
  set('prior_level_th', s(row[36]));
  set('prior_province_th', s(row[37]));
  set('prior_credit_units', s(row[38]));
  set('prior_gpax', s(row[39]));
  set('prior_school_th', s(row[40]));
  set('prior_completed_year_be', s(row[41]));
  set('address_same_as_registered', s(row[42]).toUpperCase() || 'Y');
  set('current_address_line', s(row[43]));
  set('current_village_no', s(row[44]));
  set('current_road', s(row[45]));
  set('current_alley', s(row[46]));
  set('current_soi', s(row[47]));
  set('current_country', s(row[48]));
  set('current_province_th', s(row[49]));
  set('current_district_th', s(row[50]));
  set('current_subdistrict_th', s(row[51]));
  set('current_postal_code', s(row[52]));
  set('registered_address_line', s(row[53]));
  set('registered_village_no', s(row[54]));
  set('registered_road', s(row[55]));
  set('registered_alley', s(row[56]));
  set('registered_soi', s(row[57]));
  set('registered_country', s(row[58]));
  set('registered_province_th', s(row[59]));
  set('registered_district_th', s(row[60]));
  set('registered_subdistrict_th', s(row[61]));
  set('registered_postal_code', s(row[62]));
  set('gender', mapGender(row[63]));
  set('ethnicity', s(row[64]));
  set('nationality', s(row[65]));
  set('religion', s(row[66]));
  set('weight_kg', s(row[67]));
  set('height_cm', s(row[68]));
  set('blood_type', s(row[69]));
  set('drug_allergy', s(row[70]));
  set('chronic_disease', s(row[71]));
  set('siblings_count', s(row[72]));
  set('birth_order', s(row[73]));
  set('siblings_studying', s(row[74]));
  set('nickname_th', s(row[75]));
  set('email', s(row[76]));
  set('guardian_email', s(row[77]));
  set('father_email', s(row[78]));
  set('mother_email', s(row[79]));

  set('admitted_year_be', admittedYearBe.trim());

  return p;
}

/** แถวข้อมูลจริงของไฟล์แม่แบบนี้เริ่มที่แถว index 2 (แถวที่ 3 ของ Excel) */
export const STUDENT_IMPORT_DATA_START_ROW = 2;

/** แถวว่างทั้งแถว (ไม่มีรหัสนักศึกษาและไม่มีชื่อ) ถือว่าเป็นแถวท้ายไฟล์ที่เผลอเว้นไว้ */
export function isBlankStudentRow(row: CellValue[]): boolean {
  return s(row[1]) === '' && s(row[3]) === '' && s(row[4]) === '';
}

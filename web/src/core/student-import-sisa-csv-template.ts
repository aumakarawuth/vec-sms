/**
 * แม่แบบไฟล์นำเข้านักศึกษา — ไฟล์ export จากระบบทะเบียนกลาง (student.csv)
 *
 * ─── ต่างจาก ImportFull_VocationalEducation.xlsx (student-import-template.ts) อย่างไร ───
 * เป็นไฟล์ export จริงจากระบบเดิม (SISA) คนละรูปแบบกับแม่แบบนำเข้าที่ทำไว้ก่อนหน้า
 * — คอลัมน์ไม่ตรงกันเลยสักคอลัมน์ ต้องมีตัวแมปของตัวเอง แต่ปลายทางเดียวกันคือ
 * payload ของ `apply_student_import()`
 *
 * ─── คอลัมน์ที่ไม่แมป (ตั้งใจ) ───
 * - รหัสสาขาวิชา/ชื่อสาขางาน/ชื่อสาขาวิชา/หลักสูตร(ปวช.2567) — เหตุผลเดียวกับ
 *   student-import-template.ts: ต้นไม้หลักสูตรของระบบนี้ลึกกว่าที่ไฟล์ให้ข้อมูลพอจะเดา
 * - เกรดเฉลี่ย — เป็นเกรดเฉลี่ย**ปัจจุบัน**ของนักศึกษาในสถาบันนี้ ไม่ใช่ผลการเรียน
 *   ก่อนเข้า จึงแมปเป็น `prior_gpax` ไม่ได้ (จะเป็นการยัดค่าทับตัวเลขที่ต้องคำนวณ
 *   จาก `compute_term_summary()` เท่านั้น — หลักข้อ 5 ห้ามคำนวณค่าที่ตรึงไว้ใหม่)
 * - ความพิการทางร่างกาย/รายได้/อาชีพ/สถานะสมรสของบิดามารดา/รหัสประจำบ้าน —
 *   ไม่มีคอลัมน์รองรับในสคีมาปัจจุบัน
 * - สถานะภาพของนักเรียน — ไม่รู้ชุดค่าจริงที่ไฟล์ใช้ (ตัวอย่างว่างทุกแถว) เดาไป
 *   แล้วชนกับ `student_status` enum จะทำให้ทั้งแถวตกไม่รู้สาเหตุ ปลอดภัยกว่าไม่แมป
 *
 * ─── "ปีที่เข้า" กับปีที่แปลก ───
 * ไฟล์ตัวอย่างมีค่า 2025/2026 ทั้งที่ระบบใช้ พ.ศ. (ปีปัจจุบันคือ 2569) — ต่างกัน
 * 543 พอดี แสดงว่าฟิลด์นี้ส่งออกมาเป็น ค.ศ. ไม่ใช่ พ.ศ. เหมือนช่องอื่นในระบบ
 * (ปัญหาเดียวกับ API-220..224 เรื่องวันที่ พ.ศ./ค.ศ. ปนกัน) แปลงให้เป็น พ.ศ.
 * อัตโนมัติเมื่อค่าต่ำกว่า 2500 ก่อนส่งเข้า `admitted_year_be`
 */

function s(v: string | undefined): string {
  return (v ?? '').trim();
}

const GENDER_CODE: Record<string, string> = { '1': 'male', '2': 'female' };

function mapGender(v: string | undefined): string {
  const t = s(v);
  return GENDER_CODE[t] ?? (t ? 'other' : '');
}

/** ค่าปีที่ดูเหมือน ค.ศ. (ต่ำกว่า 2500) แปลงเป็น พ.ศ. — ปีจริงของระบบนี้ไม่มีวันต่ำกว่า 2500 */
function toBuddhistYear(v: string | undefined): string {
  const t = s(v);
  if (!t || !/^\d{4}$/.test(t)) return t;
  const n = Number(t);
  return n < 2500 ? String(n + 543) : t;
}

export function mapSisaCsvRow(row: string[]): Record<string, string> {
  const p: Record<string, string> = {};
  const set = (key: string, v: string) => { if (v !== '') p[key] = v; };

  set('national_id', s(row[4]));
  set('prefix_th', s(row[5]));
  set('first_name_th', s(row[6]));
  set('last_name_th', s(row[7]));
  set('gender', mapGender(row[8]));
  set('birth_date', s(row[9]));
  set('nationality', s(row[10]));
  set('current_address_line', s(row[11]));
  set('current_village_no', s(row[12]));
  set('current_road', s(row[13]));
  set('current_subdistrict_th', s(row[14]));
  set('height_cm', s(row[16]));
  set('weight_kg', s(row[17]));

  // บิดา (18–24: หัวข้อ, ชื่อ, นามสกุล, ความพิการ, มีชีวิตอยู่, รายได้, อาชีพ)
  set('father_prefix_th', s(row[18]));
  set('father_first_name_th', s(row[19]));
  set('father_last_name_th', s(row[20]));

  // มารดา (25–31: ชุดเดียวกับบิดา)
  set('mother_prefix_th', s(row[25]));
  set('mother_first_name_th', s(row[26]));
  set('mother_last_name_th', s(row[27]));

  set('siblings_count', s(row[33]));
  set('siblings_studying', s(row[34]));

  // ผู้ปกครอง (35–39: หัวข้อ, ชื่อ, นามสกุล, รายได้, อาชีพ)
  set('guardian_prefix_th', s(row[35]));
  set('guardian_first_name_th', s(row[36]));
  set('guardian_last_name_th', s(row[37]));

  set('admitted_year_be', toBuddhistYear(row[40]));
  set('student_code', s(row[47]));
  set('room_code', s(row[48]));
  set('nickname_th', s(row[49]));
  set('religion', s(row[50]));
  set('prior_school_th', s(row[52]));
  set('mother_phone', s(row[53]));
  set('father_phone', s(row[54]));
  set('guardian_phone', s(row[55]));
  set('blood_type', s(row[56]));

  return p;
}

/** แถวว่างทั้งแถว (ไม่มีรหัสบัตร/ชื่อ) ข้ามไป — กันแถวท้ายไฟล์ที่เผลอเว้นไว้ */
export function isBlankSisaCsvRow(row: string[]): boolean {
  return s(row[4]) === '' && s(row[6]) === '' && s(row[7]) === '';
}

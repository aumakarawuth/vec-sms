/**
 * แม่แบบไฟล์นำเข้าผลการเรียน — ไฟล์ export ผลการเรียนจากระบบเดิม (finalgrades.csv)
 * หัวตาราง: ภาคเรียน,ปี,รหัส,รหัสวิชา,ชื่อวิชา,คะแนน,ผลการเรียน,หน่วยกิต
 *
 * ─── ทำไมข้ามแถวที่ "ผลการเรียน" เป็น "-" หรือไม่มีคะแนนตัวเลข ───
 * "-" คือยังไม่ตัดเกรด ไม่มีอะไรให้นำเข้า (ไฟล์จริงมีสัดส่วนนี้ถึง ~98%
 * เพราะเป็นไฟล์ export รายชื่อทั้งภาคเรียน ไม่ใช่เฉพาะที่ตัดเกรดแล้ว)
 * ส่วนแถวที่มีสัญลักษณ์อย่าง ข.ร./ผ./ข.ส. แต่ไม่มีคะแนน ก็ไม่มีตัวเลข
 * ให้ใส่ใน `gradebook_score.score` — ดูเหตุผลเต็มในคอมเมนต์บนสุดของ
 * db/migrations/0088_grade_import.sql
 */

function s(v: string | undefined): string {
  return (v ?? '').trim();
}

export function mapGradeImportRow(row: string[]): Record<string, string> | null {
  const grade = s(row[6]);
  const score = s(row[5]);
  // "-" คือยังไม่ตัดเกรด และแถวที่ไม่มีคะแนนตัวเลขไม่มีอะไรให้นำเข้า
  if (grade === '' || grade === '-' || score === '') return null;
  if (!/^\d+(\.\d+)?$/.test(score)) return null;

  const payload: Record<string, string> = {
    term_ordinal: s(row[0]),
    academic_year_be: s(row[1]),
    student_code: s(row[2]),
    course_code: s(row[3]),
    score,
  };
  return payload;
}

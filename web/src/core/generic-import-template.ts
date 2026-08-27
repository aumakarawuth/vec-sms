/**
 * อ่านไฟล์ Excel แบบทั่วไปสำหรับนำเข้าบุคลากร/ประวัติการเรียนเดิม
 *
 * ─── ทำไมต่างจาก student-import-template.ts ───
 * ไฟล์นักศึกษามีแม่แบบตายตัวจากภายนอก (SISA) จึงอ้างตำแหน่งคอลัมน์ได้ตรง ๆ
 * แต่บุคลากรกับประวัติการเรียนเดิมไม่มีแม่แบบภายนอกแบบนั้น — วิทยาลัยแต่ละ
 * แห่งเตรียมไฟล์เอง จึงอ่านจาก**แถวหัวตาราง**แทน (บรรทัดแรกของชีตต้องเป็น
 * ชื่อคอลัมน์ภาษาอังกฤษตรงกับที่ `validate_staff_row`/`validate_academic_history_row`
 * อ่าน — ดูตัวอย่างหัวตารางใน TEMPLATE ของ screens/import.tsx) หลักการเดียว
 * กับตอนวาง CSV เดิม ต่างแค่แหล่งข้อมูลเป็นไฟล์ .xlsx แทนข้อความที่พิมพ์เอง
 */

type CellValue = string | number | null;

/** แถวว่างทั้งแถว (ไม่มีค่าคอลัมน์ไหนเลย) ข้ามไป — กันแถวท้ายไฟล์ที่เผลอเว้นไว้ */
function isBlankRow(row: CellValue[] | undefined): boolean {
  return !(row ?? []).some((c) => c != null && String(c).trim() !== '');
}

export function mapGenericExcelRows(
  sheet: CellValue[][],
): { rowNo: number; payload: Record<string, string> }[] {
  const headerRow = sheet[0] ?? [];
  const headers = headerRow.map((h) => (h == null ? '' : String(h).trim()));
  const dataRows = sheet.slice(1).filter((r) => !isBlankRow(r));

  return dataRows.map((row, i) => {
    const payload: Record<string, string> = {};
    headers.forEach((h, j) => {
      if (!h) return;
      const v = (row ?? [])[j];
      if (v == null) return;
      const s = String(v).trim();
      if (s !== '') payload[h] = s;
    });
    return { rowNo: i + 1, payload };
  });
}

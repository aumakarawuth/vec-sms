/**
 * ตัวอ่าน CSV แบบ RFC 4180 (รองรับเซลล์ที่มีจุลภาค/บรรทัดใหม่/เครื่องหมายคำพูดในตัว)
 *
 * ─── ทำไมแยกจากตัวแยกจุลภาคง่าย ๆ ที่เคยใช้ในช่องวาง CSV เดิม ───
 * ไฟล์ export จริงจากระบบทะเบียนกลาง (เช่น student.csv) มีชื่อโรงเรียนที่ใส่
 * เครื่องหมายคำพูดคร่อมไว้ (`"โรงเรียนบางมดวิทยา ""สีสุกหวาดจวนอุปถัมภ์"""`)
 * ถ้าแยกด้วย `split(',')` ตรง ๆ แถวนั้นจะเลื่อนคอลัมน์ทั้งแถวโดยไม่มีอะไรฟ้อง
 */
export function parseCsv(text: string): string[][] {
  // ตัด BOM ของ UTF-8 ที่ Excel/ระบบทะเบียนมักแนบมา
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let inQuotes = false;
  let i = 0;

  const pushCell = () => { row.push(cell); cell = ''; };
  const pushRow = () => { pushCell(); rows.push(row); row = []; };

  while (i < src.length) {
    const ch = src[i]!;
    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') { cell += '"'; i += 2; continue; }
        inQuotes = false; i += 1; continue;
      }
      cell += ch; i += 1; continue;
    }
    if (ch === '"') { inQuotes = true; i += 1; continue; }
    if (ch === ',') { pushCell(); i += 1; continue; }
    if (ch === '\r') { i += 1; continue; }
    if (ch === '\n') { pushRow(); i += 1; continue; }
    cell += ch; i += 1;
  }
  // แถวสุดท้ายอาจไม่มี \n ปิดท้าย
  if (cell !== '' || row.length > 0) pushRow();

  return rows.filter((r) => !(r.length === 1 && r[0] === ''));
}

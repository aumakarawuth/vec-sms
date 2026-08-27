/**
 * อ่านไฟล์ .xlsx ในเบราว์เซอร์โดยไม่พึ่งไลบรารีภายนอก
 *
 * ─── ทำไมไม่ใช้ไลบรารี xlsx สำเร็จรูป ───
 * ทั้งโปรเจกต์ตั้งใจพึ่งไลบรารีน้อยที่สุด (ดู CLAUDE.md หัวข้อสไตล์) และ
 * ไฟล์ .xlsx คือ ZIP ที่ข้างในเป็น XML ล้วน — ส่วนที่เคยต้องพึ่งไลบรารีคือ
 * การ inflate (deflate) ซึ่งตอนนี้เบราว์เซอร์สมัยใหม่มี
 * `DecompressionStream('deflate-raw')` ในตัวอยู่แล้ว ที่เหลือ (อ่านโครง ZIP
 * กับแปลง XML) ใช้ `DOMParser` ที่มีอยู่ในเบราว์เซอร์ทำได้ตรง ๆ
 *
 * ครอบคลุมเฉพาะเท่าที่ไฟล์แม่แบบนำเข้าต้องใช้ — ไม่รองรับ merge cell,
 * สไตล์ตัวเลข/วันที่แบบเต็มรูป, หรือหลายชีตพร้อมกัน
 */

type CellValue = string | number | null;

function readUint16(view: DataView, offset: number): number {
  return view.getUint16(offset, true);
}
function readUint32(view: DataView, offset: number): number {
  return view.getUint32(offset, true);
}

/** หา End Of Central Directory โดยไล่จากท้ายไฟล์ (comment length แปรผันได้) */
function findEocd(view: DataView): number {
  const sig = 0x06054b50;
  const min = Math.max(0, view.byteLength - 65557);
  for (let i = view.byteLength - 22; i >= min; i--) {
    if (readUint32(view, i) === sig) return i;
  }
  throw new Error('ไม่ใช่ไฟล์ .xlsx ที่ถูกต้อง (หา End Of Central Directory ไม่พบ)');
}

interface ZipEntry {
  name: string;
  compressionMethod: number;
  compressedSize: number;
  localHeaderOffset: number;
}

function parseCentralDirectory(buf: ArrayBuffer): ZipEntry[] {
  const view = new DataView(buf);
  const eocd = findEocd(view);
  const total = readUint16(view, eocd + 10);
  let offset = readUint32(view, eocd + 16);
  const entries: ZipEntry[] = [];
  const decoder = new TextDecoder('utf-8');

  for (let i = 0; i < total; i++) {
    if (readUint32(view, offset) !== 0x02014b50) {
      throw new Error('โครง ZIP ของไฟล์ไม่ตรงตามที่คาด (central directory เพี้ยน)');
    }
    const compressionMethod = readUint16(view, offset + 10);
    const compressedSize = readUint32(view, offset + 20);
    const nameLen = readUint16(view, offset + 28);
    const extraLen = readUint16(view, offset + 30);
    const commentLen = readUint16(view, offset + 32);
    const localHeaderOffset = readUint32(view, offset + 42);
    const nameBytes = new Uint8Array(buf, offset + 46, nameLen);
    entries.push({
      name: decoder.decode(nameBytes),
      compressionMethod,
      compressedSize,
      localHeaderOffset,
    });
    offset += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

async function inflateRaw(bytes: Uint8Array): Promise<Uint8Array> {
  const ds = new DecompressionStream('deflate-raw');
  const stream = new Blob([bytes.slice().buffer]).stream().pipeThrough(ds);
  const buf = await new Response(stream).arrayBuffer();
  return new Uint8Array(buf);
}

async function readZipEntryText(buf: ArrayBuffer, entry: ZipEntry): Promise<string> {
  const view = new DataView(buf);
  const lh = entry.localHeaderOffset;
  if (readUint32(view, lh) !== 0x04034b50) {
    throw new Error(`ไฟล์ภายใน ZIP เพี้ยน: ${entry.name}`);
  }
  const nameLen = readUint16(view, lh + 26);
  const extraLen = readUint16(view, lh + 28);
  const dataStart = lh + 30 + nameLen + extraLen;
  const raw = new Uint8Array(buf, dataStart, entry.compressedSize);
  const bytes = entry.compressionMethod === 0 ? raw : await inflateRaw(raw);
  return new TextDecoder('utf-8').decode(bytes);
}

/** "AB12" → { col: เลขคอลัมน์เริ่มที่ 0, row: เลขแถวเริ่มที่ 1 } */
function parseCellRef(ref: string): { col: number; row: number } {
  const m = /^([A-Z]+)(\d+)$/.exec(ref);
  if (!m) return { col: 0, row: 1 };
  let col = 0;
  for (const ch of m[1]!) col = col * 26 + (ch.charCodeAt(0) - 64);
  return { col: col - 1, row: Number(m[2]) };
}

/** เลขวันที่แบบ Excel serial (epoch 1899-12-30 พร้อมบั๊กปีอธิกสุรทิน 1900 ของ Excel เอง) → ISO */
function excelSerialToIso(serial: number): string {
  const ms = Math.round((serial - 25569) * 86400 * 1000);
  const d = new Date(ms);
  return d.toISOString().slice(0, 10);
}

/** ค่าที่ "ดูเหมือน" วันเดือนปีเกิด (เลขจำนวนเต็มในช่วงปีที่สมเหตุสมผล) แปลงเป็น ISO ให้ */
export function coerceDateCell(v: CellValue): string {
  if (v == null) return '';
  if (typeof v === 'number' && v > 15000 && v < 80000) return excelSerialToIso(v);
  return String(v).trim();
}

function parseSharedStrings(xml: string): string[] {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');
  return Array.from(doc.getElementsByTagName('si')).map((si) =>
    Array.from(si.getElementsByTagName('t'))
      .map((t) => t.textContent ?? '')
      .join(''),
  );
}

function parseSheet(xml: string, shared: string[]): CellValue[][] {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');
  const rows: CellValue[][] = [];
  for (const rowEl of Array.from(doc.getElementsByTagName('row'))) {
    const rowNo = Number(rowEl.getAttribute('r') ?? rows.length + 1);
    const out: CellValue[] = rows[rowNo - 1] ?? [];
    for (const cellEl of Array.from(rowEl.getElementsByTagName('c'))) {
      const ref = cellEl.getAttribute('r');
      const { col } = ref ? parseCellRef(ref) : { col: out.length };
      const type = cellEl.getAttribute('t');
      let value: CellValue = null;
      if (type === 'inlineStr') {
        value = cellEl.getElementsByTagName('t')[0]?.textContent ?? '';
      } else {
        const raw = cellEl.getElementsByTagName('v')[0]?.textContent ?? '';
        if (raw === '') {
          value = null;
        } else if (type === 's') {
          value = shared[Number(raw)] ?? '';
        } else if (type === 'str' || type === 'b') {
          value = raw;
        } else {
          const n = Number(raw);
          value = Number.isFinite(n) ? n : raw;
        }
      }
      out[col] = value;
    }
    rows[rowNo - 1] = out;
  }
  return rows;
}

/** อ่านชีตแรกของไฟล์ .xlsx คืนเป็นตาราง (แถว × คอลัมน์ เริ่มที่ 0 ทั้งคู่) */
export async function readXlsxFirstSheet(file: File): Promise<CellValue[][]> {
  if (typeof DecompressionStream === 'undefined') {
    throw new Error(
      'เบราว์เซอร์นี้ไม่รองรับการอ่านไฟล์ .xlsx โดยตรง — ใช้ Chrome หรือ Edge รุ่นใหม่ ' +
        'หรือแปลงไฟล์เป็น CSV แล้ววางในช่องข้อความแทน',
    );
  }
  const buf = await file.arrayBuffer();
  const entries = parseCentralDirectory(buf);
  const byName = new Map(entries.map((e) => [e.name, e] as const));

  // หาไฟล์ชีตแรกจาก workbook.xml เผื่อลำดับชีตไม่ตรงกับชื่อไฟล์ sheetN.xml ตรง ๆ
  let sheetTarget = 'xl/worksheets/sheet1.xml';
  const workbookEntry = byName.get('xl/workbook.xml');
  const relsEntry = byName.get('xl/_rels/workbook.xml.rels');
  if (workbookEntry && relsEntry) {
    const workbookXml = await readZipEntryText(buf, workbookEntry);
    const relsXml = await readZipEntryText(buf, relsEntry);
    const wbDoc = new DOMParser().parseFromString(workbookXml, 'application/xml');
    const relsDoc = new DOMParser().parseFromString(relsXml, 'application/xml');
    const firstSheet = wbDoc.getElementsByTagName('sheet')[0];
    const rId = firstSheet?.getAttribute('r:id');
    if (rId) {
      const rel = Array.from(relsDoc.getElementsByTagName('Relationship')).find(
        (r) => r.getAttribute('Id') === rId,
      );
      const target = rel?.getAttribute('Target');
      if (target) sheetTarget = `xl/${target.replace(/^\/?xl\//, '')}`;
    }
  }

  const sheetEntry = byName.get(sheetTarget) ?? byName.get('xl/worksheets/sheet1.xml');
  if (!sheetEntry) throw new Error('ไม่พบชีตข้อมูลในไฟล์ .xlsx นี้');

  const sharedEntry = byName.get('xl/sharedStrings.xml');
  const shared = sharedEntry ? parseSharedStrings(await readZipEntryText(buf, sharedEntry)) : [];
  const sheetXml = await readZipEntryText(buf, sheetEntry);
  return parseSheet(sheetXml, shared);
}

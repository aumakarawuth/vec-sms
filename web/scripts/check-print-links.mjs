/**
 * กันไม่ให้กลับไปเปิดเส้นทางของ API ด้วยลิงก์ตรง
 *
 * ─── ทำไมต้องมีตัวตรวจ ไม่ใช่แค่คอมเมนต์ ───
 * `AuthGuard` อ่าน token จากเฮดเดอร์ `Authorization` อย่างเดียว ส่วน
 * `<a href>` และ `window.open()` ตั้งเฮดเดอร์ไม่ได้เลย ปุ่มพิมพ์ทุกปุ่มใน
 * หน้าจอเจ้าหน้าที่จึงเคยได้ 401 ทุกครั้ง — ใบรายชื่อ · ใบเช็คชื่อเปล่า ·
 * ประกาศผู้มีสิทธิ์สอบ · ใบลงทะเบียน · หนังสือถึงผู้ปกครอง · และการพิมพ์
 * เอกสารจากต้นฉบับ รวมเป็นความสามารถด้านการพิมพ์ทั้งหมดของชั้นนี้
 *
 * **ไม่มีเทสต์ไหนจับได้** เพราะเทสต์ทุกชุดยิง HTTP พร้อมเฮดเดอร์อยู่แล้ว
 * ทางที่เบราว์เซอร์เดินจริงจึงไม่เคยถูกเดินเลยสักครั้ง (รูปเดียวกับ AUTH-26
 * ที่ผ่านมาตลอดเพราะหยิบ token จากทางที่ระบบจริงไม่มี)
 *
 * คอมเมนต์บอกเจตนา แต่ไม่มีอะไรตรวจว่าเจตนานั้นเกิดขึ้นจริง — ตัวนี้ตรวจ
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

// fileURLToPath ไม่ใช่ .pathname เพราะพาธของโปรเจกต์นี้มีภาษาไทย
// ซึ่ง URL เก็บเป็น percent-encoding แล้วเปิดไดเรกทอรีไม่เจอ
const ROOT = fileURLToPath(new URL('../src', import.meta.url));

/** ใช้ API_BASE ประกอบ URL แล้วยัดใส่ href/window.open — สองรูปแบบที่พังเหมือนกัน */
const BAD = [
  { re: /window\.open\(\s*`\$\{API_BASE\}/, why: 'window.open() ตั้งเฮดเดอร์ Authorization ไม่ได้' },
  { re: /href=\{\s*`\$\{API_BASE\}/, why: '<a href> ตั้งเฮดเดอร์ Authorization ไม่ได้' },
];

/** ที่อนุญาต — ตัวเดียวที่ควรรู้จัก API_BASE คือตัวเรียก API เอง */
const ALLOW = new Set(['core/api.ts']);

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) out.push(...walk(full));
    else if (/\.(ts|tsx)$/.test(name)) out.push(full);
  }
  return out;
}

const problems = [];
for (const file of walk(ROOT)) {
  const rel = file.slice(ROOT.length + 1).replace(/\\/g, '/');
  if (ALLOW.has(rel)) continue;
  const lines = readFileSync(file, 'utf8').split('\n');
  lines.forEach((line, i) => {
    for (const { re, why } of BAD) {
      if (re.test(line)) problems.push(`  src/${rel}:${i + 1} — ${why}`);
    }
  });
}

if (problems.length > 0) {
  console.error('เปิดเส้นทางของ API ด้วยลิงก์ตรงไม่ได้ — จะได้ 401 ทุกครั้ง\n');
  console.error(problems.join('\n'));
  console.error('\nใช้ <PrintButton path="…"> หรือ api.openPrintable() แทน');
  process.exit(1);
}

console.log(`ตรวจลิงก์พิมพ์ผ่าน — ไม่มีที่ไหนเปิด API ด้วยลิงก์ตรง`);

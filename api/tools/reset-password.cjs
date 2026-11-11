#!/usr/bin/env node
/**
 * ตั้งรหัสผ่านใหม่ให้บัญชีหนึ่งจากเครื่องเซิร์ฟเวอร์ — ทางสุดท้ายเมื่อผู้ดูแลคนเดียวของ
 * วิทยาลัยลืมรหัสผ่าน และไม่มีเจ้าหน้าที่คนอื่นออกรหัสรีเซ็ตให้ได้
 *
 * ─── ทำไมต้องรันบนเครื่องเท่านั้น ไม่เปิดเป็น API ───
 * เส้นทางที่ตั้งรหัสผ่านให้ใครก็ได้คือประตูหลังเข้าไปเป็น admin ของลูกค้า (หลัก 5ค)
 * สคริปต์นี้ต้องมีสิทธิ์ sudo บนเครื่องที่ถือฐานข้อมูลอยู่แล้ว ซึ่งเป็นสิทธิ์ที่เหนือกว่า
 * ทุกอย่างในระบบอยู่แล้ว จึงไม่ได้เปิดช่องใหม่
 *
 * ─── ทำไมถามรหัสผ่านทางแป้นพิมพ์ ไม่รับเป็นอาร์กิวเมนต์ ───
 * อาร์กิวเมนต์ไปโผล่ใน `ps` และประวัติคำสั่งของ shell — รหัสผ่านต้องไม่อยู่ที่ไหนเลย
 * นอกจากค่าแฮชในฐานข้อมูล
 *
 * ใช้: sudo -u postgres node /opt/vecsms/app/api/tools/reset-password.cjs <รหัสวิทยาลัย> <ชื่อผู้ใช้>
 * (ต้อง build api ก่อน — ใช้ hashPassword() ตัวเดียวกับระบบ ไม่เขียนสูตรแฮชซ้ำ)
 */
const path = require('path');
const readline = require('readline');
const { Client } = require(path.join(__dirname, '..', 'node_modules', 'pg'));
const { hashPassword } = require(path.join(__dirname, '..', 'dist', 'common', 'auth', 'password.js'));

const [code, username] = process.argv.slice(2);
if (!code || !username) {
  console.error('ใช้: node reset-password.cjs <รหัสวิทยาลัย 10 หลัก> <ชื่อผู้ใช้>');
  process.exit(2);
}

function ask(q) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    // ไม่สะท้อนตัวอักษรที่พิมพ์บนจอ
    rl._writeToOutput = (s) => { if (s.startsWith(q)) rl.output.write(s); };
    rl.question(q, (a) => { rl.close(); process.stdout.write('\n'); resolve(a); });
  });
}

(async () => {
  const pw = await ask('รหัสผ่านใหม่ (อย่างน้อย 8 ตัว): ');
  const again = await ask('พิมพ์ซ้ำอีกครั้ง: ');
  if (pw.length < 8) throw new Error('รหัสผ่านสั้นเกินไป');
  if (pw !== again) throw new Error('รหัสผ่านสองครั้งไม่ตรงกัน');

  const db = new Client({
    host: process.env.PGHOST || '/var/run/postgresql',
    port: Number(process.env.PGPORT || 5434),
    database: process.env.PGDATABASE || 'vecsms',
    user: process.env.PGUSER || 'postgres',
  });
  await db.connect();
  try {
    // ล้างการล็อกด้วย เหมือน consume_password_reset() — คนลืมรหัสมักโดนล็อกมาก่อนแล้ว
    // must_change = false เพราะคนตั้งคือเจ้าของบัญชีเองที่หน้าเครื่อง ไม่ใช่เจ้าหน้าที่ตั้งให้
    const r = await db.query(
      `update user_credential uc
          set password_hash = $3, failed_attempts = 0, locked_until = null,
              must_change = false, password_changed_at = now()
         from institution i
        where i.id = uc.institution_id and i.code = $1 and uc.username = $2
      returning uc.username`,
      [code, username, await hashPassword(pw)],
    );
    if (r.rowCount !== 1) throw new Error(`ไม่พบบัญชี ${username} ในวิทยาลัย ${code} (ชื่อผู้ใช้แยกตัวพิมพ์เล็กใหญ่)`);
    console.log(`ตั้งรหัสผ่านใหม่ให้ ${username} แล้ว และปลดล็อกบัญชีแล้ว`);
  } finally {
    await db.end();
  }
})().catch((e) => { console.error(e.message); process.exit(1); });

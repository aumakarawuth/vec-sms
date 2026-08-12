/*
 * ═══════════════════════════════════════════════════════════════════
 * บัญชีตัวอย่างครบทุกบทบาท สำหรับกดดูหน้าจอตอนพัฒนา
 *
 * สร้างคนละหนึ่งบัญชีต่อหนึ่งค่าใน staff_role_kind บวก teacher · student ·
 * guardian แล้วตรวจด้วยการล็อกอินจริงผ่าน API ไม่ใช่แค่ดูว่า insert ผ่าน
 *
 *   node api/tools/seed-demo-users.cjs
 *
 * ═══ ห้ามรันกับฐานข้อมูลของวิทยาลัยจริงเด็ดขาด ═══
 * ไฟล์นี้เขียนรหัสผ่านไว้ในตัวมันเอง และหนึ่งในบัญชีที่สร้างคือ admin
 * ซึ่งเห็นข้อมูลทั้งวิทยาลัย ใครที่อ่าน repo ได้จึงเข้าระบบนั้นได้ทันที
 * — จึงมีรายชื่อฐานที่อนุญาตอยู่ข้างล่าง และปฏิเสธทุกชื่อที่ไม่อยู่ในนั้น
 * (หลักข้อ 6 — ล้มตั้งแต่ต้นดีกว่าทำงานผิดเงียบ ๆ)
 *
 * ─── ทำไมแฮชรหัสผ่านที่ชั้น Node ไม่ใช่ใน SQL ───
 * ระบบนี้แฮชด้วย scrypt ที่มากับ Node (api/src/common/auth/password.ts)
 * ซึ่งฐานข้อมูลทำเองไม่ได้ ถ้าลอกสูตรแฮชมาไว้ในสคริปต์นี้ วันที่
 * SCRYPT_PARAMS เปลี่ยน บัญชีตัวอย่างจะล็อกอินไม่ได้โดยไม่มีอะไรฟ้อง
 * จึง require ตัวจริงจาก dist มาใช้ — แลกกับการต้อง build ก่อน
 *
 * ─── ทำไมต้องเดินเส้นทาง MFA จริง ไม่ insert mfa_credential ตรง ๆ ───
 * ความลับ TOTP เข้ารหัสด้วย MFA_SECRET_KEY ที่อยู่นอกฐานข้อมูล สคริปต์นี้
 * ไม่รู้กุญแจนั้น (อยู่ใน env ของโปรเซส API) การเขียนไบต์ลงตารางเองจะได้
 * ค่าที่ API ถอดไม่ออก แล้วบัญชีนั้นเข้าระบบไม่ได้ตลอดไป — ทางที่ถูกคือ
 * ให้ API เป็นคนออกความลับ แล้วอ่านกลับมาจาก otpauthUri
 *
 * รันซ้ำได้ — ทุกขั้นเป็น upsert และล้างสถานะ MFA เดิมก่อนเริ่มใหม่
 * ═══════════════════════════════════════════════════════════════════
 */
'use strict';

const path = require('node:path');
const fs = require('node:fs');
const { createHmac } = require('node:crypto');

const API_ROOT = path.join(__dirname, '..');

// ── ตั้งค่าได้ทาง env ทั้งหมด ค่าเริ่มต้นคือสภาพบนเครื่องพัฒนา ──────────
const DSN = process.env.SEED_DATABASE_URL
  ?? 'postgres://postgres@localhost:5433/vecsms_api_test';
const API = process.env.SEED_API_BASE_URL ?? 'http://127.0.0.1:3111/api/v1';
const INST = process.env.SEED_INSTITUTION_ID ?? '11111111-1111-1111-1111-111111111111';

/** รหัสผ่านเดียวกันทุกบัญชี เพราะเป็นชุดสาธิต ไม่ใช่ของใครจริง ๆ */
const PASSWORD = process.env.SEED_PASSWORD ?? 'Demo!vec2569';

/*
 * ─── รายชื่อฐานที่ยอมให้เขียน ───
 * เป็นรายชื่อ ไม่ใช่สวิตช์ boolean โดยตั้งใจ — สวิตช์แบบ FORCE=1 กดผ่านได้
 * ด้วยความเคยชิน ส่วนการต้องพิมพ์ชื่อฐานให้ตรงบังคับให้อ่านว่ากำลังจะเขียน
 * ใส่ฐานไหนอยู่ (ข้ามด้วย ALLOW_DEMO_SEED_ON=<ชื่อฐาน>)
 */
const SAFE_DATABASES = new Set(['vecsms_api_test', 'vecsms_dev', 'vecsms_demo']);

// ── บุคลากรที่ต้องสร้างใหม่ หนึ่งคนต่อหนึ่งค่าใน staff_role_kind ──────
const STAFF = [
  { role: 'admin',           person: '20000000-0000-0000-0000-000000000001', staff: '21000000-0000-0000-0000-000000000001',
    code: 'S-ADM01', username: 'admin.demo',     prefix: 'นาย',    first: 'อดิศร',     last: 'มั่นคงระบบ',   label: 'ผู้ดูแลระบบ' },
  { role: 'director',        person: '20000000-0000-0000-0000-000000000002', staff: '21000000-0000-0000-0000-000000000002',
    code: 'S-DIR01', username: 'director.demo',  prefix: 'นาย',    first: 'ดำรงศักดิ์', last: 'วิสัยทัศน์',  label: 'ผู้อำนวยการ' },
  { role: 'registrar',       person: '20000000-0000-0000-0000-000000000003', staff: '21000000-0000-0000-0000-000000000003',
    code: 'S-REG01', username: 'registrar.demo', prefix: 'นางสาว', first: 'ทิพวรรณ',   last: 'ทะเบียนดี',   label: 'งานทะเบียน' },
  { role: 'academic',        person: '20000000-0000-0000-0000-000000000004', staff: '21000000-0000-0000-0000-000000000004',
    code: 'S-ACA01', username: 'academic.demo',  prefix: 'นาง',    first: 'วิชญา',     last: 'หลักสูตรงาม', label: 'ฝ่ายวิชาการ' },
  { role: 'finance',         person: '20000000-0000-0000-0000-000000000005', staff: '21000000-0000-0000-0000-000000000005',
    code: 'S-FIN01', username: 'finance.demo',   prefix: 'นางสาว', first: 'พรทิพย์',   last: 'บัญชีแม่น',   label: 'การเงิน' },
  { role: 'student_affairs', person: '20000000-0000-0000-0000-000000000006', staff: '21000000-0000-0000-0000-000000000006',
    code: 'S-AFF01', username: 'affairs.demo',   prefix: 'นาย',    first: 'สุรชัย',    last: 'ปกครองดี',    label: 'งานปกครองและแนะแนว' },
];

/*
 * ─── คนที่มีอยู่แล้วในฐาน — ออกบัญชีให้เฉย ๆ ไม่สร้างคนซ้ำ ───
 * ผูกกับ person ที่ **db/deploy/demo-data.sql** สร้าง เพราะสองคนนี้ต้องมี
 * ข้อมูลจริงห้อยอยู่ (กลุ่มเรียน · เกรด · ค่าเทอม) การสร้างคนใหม่จะได้บัญชี
 * ที่เข้าไปแล้วหน้าจอว่างเปล่า ซึ่งใช้ทดสอบอะไรไม่ได้
 *
 * ─── ที่เคยชี้ผิด ───
 * เดิมชี้ไปที่ person ของ fixture เทสต์ (`10000000-…`) พร้อมคอมเมนต์ว่า
 * "db/seed สร้างไว้" ซึ่งไม่จริง — `db/seed/` มีแต่ข้อมูลอ้างอิง ไม่มีคน
 * เลยสักคน สคริปต์จึงทำงานได้เฉพาะบนฐานที่เพิ่งรันเทสต์ e2e มา และล้ม
 * ด้วย foreign key ทันทีบนฐานที่สร้างใหม่
 */
const EXISTING = [
  { role: 'teacher', person: 'e0000000-0000-0000-0000-000000000001', username: 'teacher.demo',
    label: 'ครูผู้สอน (ประสิทธิ์ เครื่องยนต์ดี)' },
  { role: 'student', person: 'f0000000-0000-0000-0000-000000000001', username: 'student.demo',
    label: 'นักศึกษา (กิตติศักดิ์ ตั้งใจเรียน · 69201010101)' },
];

/*
 * ─── ผู้ปกครอง ───
 * ต้องมีแถวใน student_guardian ที่ verified_at ไม่เป็น null มิฉะนั้น
 * login_role_for() ไม่คืน guardian แล้วล็อกอินจะถูกปฏิเสธด้วย
 * "บัญชีนี้ยังไม่ได้รับมอบหมายบทบาท" ซึ่งอ่านแล้วนึกไม่ถึงว่าสาเหตุอยู่ตรงนี้
 */
const GUARDIAN = {
  role: 'guardian',
  person: '20000000-0000-0000-0000-000000000009',
  student: 'f1000000-0000-0000-0000-000000000001',
  username: 'guardian.demo',
  prefix: 'นาง', first: 'มาลี', last: 'ตั้งใจเรียน',
  label: 'ผู้ปกครอง (มารดาของ กิตติศักดิ์ ตั้งใจเรียน)',
};

// ── TOTP: สร้างรหัสหกหลัก (ฝั่ง API มีแต่ verify ไม่มี generate) ──────
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function base32Decode(s) {
  let bits = 0, value = 0;
  const out = [];
  for (const ch of s.replace(/=+$/, '').toUpperCase()) {
    const i = B32.indexOf(ch);
    if (i === -1) continue;
    value = (value << 5) | i;
    bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
  }
  return Buffer.from(out);
}
function totpCode(secret, atMs = Date.now()) {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(atMs / 1000 / 30)));
  const d = createHmac('sha1', secret).update(counter).digest();
  const o = d[d.length - 1] & 0x0f;
  const bin = ((d[o] & 0x7f) << 24) | ((d[o + 1] & 0xff) << 16)
            | ((d[o + 2] & 0xff) << 8) | (d[o + 3] & 0xff);
  return String(bin % 1e6).padStart(6, '0');
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function post(pathname, body, token) {
  const res = await fetch(API + pathname, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body ?? {}),
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { status: res.status, json };
}

/*
 * ─── ทำไมไม่ hardcode ว่า admin/director ต้องยืนยันสองชั้น ───
 * นโยบายอยู่ที่ auth_policy.require_mfa_roles ซึ่งแก้ได้รายวิทยาลัย
 * สคริปต์ที่ตัดสินใจเองจะรายงานผิดทันทีที่นโยบายไม่ตรงกับที่มันเดา —
 * เคยเกิดจริงตอนปิด MFA แล้วสคริปต์ฟ้องว่า "ไม่ได้ challengeToken"
 * ทั้งที่บัญชีล็อกอินสำเร็จเรียบร้อย ให้ดูจากคำตอบของเซิร์ฟเวอร์อย่างเดียว
 */
const needsMfa = (body) => body.mfaRequired === true;

/** ล็อกอินพร้อมทนกับตัวจำกัดคำขอ — /auth/login ยอม 10 ครั้ง/นาที ซึ่งชุดนี้ชนพอดี */
async function login(username) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const r = await post('/auth/login', { institutionId: INST, username, password: PASSWORD });
    if (r.status !== 429) return r;
    const wait = (r.json.retryAfter ?? 60) * 1000 + 2000;
    process.stdout.write(`   (ถูกจำกัดคำขอ รออีก ${Math.ceil(wait / 1000)} วิ)\n`);
    await sleep(wait);
  }
  return { status: 429, json: { message: 'ถูกจำกัดคำขอตลอด' } };
}

// ── ด่านตรวจก่อนแตะอะไรทั้งสิ้น ────────────────────────────────────
function guard() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('NODE_ENV=production — สคริปต์นี้สร้างบัญชี admin ด้วยรหัสผ่านที่เขียนไว้ในไฟล์');
  }

  const dbName = decodeURIComponent(new URL(DSN).pathname.replace(/^\//, ''));
  const allowed = process.env.ALLOW_DEMO_SEED_ON;
  if (!SAFE_DATABASES.has(dbName) && allowed !== dbName) {
    throw new Error(
      `ฐาน "${dbName}" ไม่อยู่ในรายชื่อที่อนุญาต (${[...SAFE_DATABASES].join(' · ')})\n` +
      `ถ้าตั้งใจจริงให้ระบุชื่อซ้ำอีกครั้ง: ALLOW_DEMO_SEED_ON=${dbName}\n` +
      `— แต่ห้ามทำกับฐานของวิทยาลัยจริง เพราะรหัสผ่านของ admin อยู่ในไฟล์นี้`,
    );
  }

  const passwordJs = path.join(API_ROOT, 'dist', 'common', 'auth', 'password.js');
  if (!fs.existsSync(passwordJs)) {
    throw new Error(`ยังไม่ได้ build — หา ${passwordJs} ไม่เจอ ให้รัน "cd api && npm run build" ก่อน`);
  }
  return dbName;
}

async function main() {
  const dbName = guard();
  const { Client } = require(path.join(API_ROOT, 'node_modules', 'pg'));
  const { hashPassword } = require(path.join(API_ROOT, 'dist', 'common', 'auth', 'password.js'));

  console.log(`ฐานข้อมูล : ${dbName}`);
  console.log(`API       : ${API}`);
  console.log(`วิทยาลัย   : ${INST}\n`);

  const db = new Client({ connectionString: DSN, client_encoding: 'UTF8' });
  await db.connect();

  const hash = await hashPassword(PASSWORD);
  const accounts = [...STAFF, GUARDIAN, ...EXISTING];
  const allPersons = accounts.map((a) => a.person);

  try {
    await db.query('begin');

    // ล้างสถานะ MFA เดิม เพื่อให้รันซ้ำแล้วผูก authenticator ใหม่ได้
    await db.query(
      `delete from mfa_recovery_code
        where credential_id in (select id from mfa_credential where person_id = any($1))`,
      [allPersons],
    );
    await db.query(`delete from mfa_credential where person_id = any($1)`, [allPersons]);

    // ── บุคลากร ──────────────────────────────────────────────────────
    for (const s of STAFF) {
      await db.query(
        `insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
         values ($1, $2, $3, $4, $5, 'undisclosed')
         on conflict (id) do update
           set prefix_th = excluded.prefix_th,
               first_name_th = excluded.first_name_th,
               last_name_th = excluded.last_name_th`,
        [s.person, INST, s.prefix, s.first, s.last],
      );

      // is_teacher = false เพราะเป็นงานสำนักงาน ไม่ใช่ครูผู้สอน
      // (ค่าเริ่มต้นของคอลัมน์คือ true จึงต้องระบุเอง)
      await db.query(
        `insert into staff (id, institution_id, person_id, staff_code, is_teacher, active)
         values ($1, $2, $3, $4, false, true)
         on conflict (id) do update
           set staff_code = excluded.staff_code, is_teacher = false, active = true`,
        [s.staff, INST, s.person, s.code],
      );

      // exclusion constraint ของ staff_role ใช้ on conflict ไม่ได้ — ลบก่อนใส่
      await db.query(`delete from staff_role where staff_id = $1`, [s.staff]);
      await db.query(
        `insert into staff_role (staff_id, role, effective_from, reason)
         values ($1, $2, current_date, 'บัญชีตัวอย่างสำหรับทดสอบหน้าจอ')`,
        [s.staff, s.role],
      );
    }

    // ── ผู้ปกครอง ────────────────────────────────────────────────────
    await db.query(
      `insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
       values ($1, $2, $3, $4, $5, 'female')
       on conflict (id) do update
         set prefix_th = excluded.prefix_th,
             first_name_th = excluded.first_name_th,
             last_name_th = excluded.last_name_th`,
      [GUARDIAN.person, INST, GUARDIAN.prefix, GUARDIAN.first, GUARDIAN.last],
    );
    await db.query(
      `insert into student_guardian
         (student_id, person_id, relation, is_primary, can_approve_leave, verified_at)
       values ($1, $2, 'mother', true, true, now())
       on conflict (student_id, person_id) do update
         set verified_at = now(), is_primary = true, can_approve_leave = true`,
      [GUARDIAN.student, GUARDIAN.person],
    );

    // ── บัญชีผู้ใช้ ────────────────────────────────────────────────────
    // must_change = false เพราะเป็นบัญชีสาธิต ถ้าเป็น true หน้าจอจะบังคับ
    // เปลี่ยนรหัสก่อนทุกครั้ง แล้วรหัสในไฟล์นี้จะใช้ไม่ได้ตั้งแต่ครั้งที่สอง
    for (const a of accounts) {
      await db.query(
        `insert into user_credential
           (institution_id, person_id, username, password_hash, must_change)
         values ($1, $2, $3, $4, false)
         on conflict (institution_id, username) do update
           set person_id = excluded.person_id,
               password_hash = excluded.password_hash,
               must_change = false,
               failed_attempts = 0,
               locked_until = null,
               disabled_at = null,
               password_changed_at = now()`,
        [INST, a.person, a.username, hash],
      );
    }

    await db.query('commit');
    console.log(`เขียนลงฐานข้อมูลแล้ว ${accounts.length} บัญชี\n`);
  } catch (e) {
    await db.query('rollback');
    throw e;
  } finally {
    await db.end();
  }

  /*
   * ─── ตรวจด้วยการล็อกอินจริง ไม่ใช่แค่ดูว่า insert ผ่าน ───
   * บทเรียนที่ซ้ำที่สุดใน CLAUDE.md คือเทสต์ที่ไม่เดินเส้นทางที่ระบบจริงเดิน
   * ไม่ได้พิสูจน์อะไร — แถวใน user_credential ที่ครบทุกคอลัมน์ยังล็อกอิน
   * ไม่ได้ได้ ถ้าบทบาทผูกไม่ครบหรือ นโยบายบังคับ MFA ที่ตั้งค่าไม่ได้
   */
  console.log('ตรวจด้วยการล็อกอินจริงผ่าน API\n');
  const results = [];

  for (const a of accounts) {
    const r = await login(a.username);

    if (r.status !== 200 && r.status !== 201) {
      results.push({ ...a, ok: false, note: `${r.status} ${r.json.message ?? ''}` });
      console.log(`✗ ${a.username} — ${r.status} ${r.json.message ?? ''}`);
      continue;
    }

    if (!needsMfa(r.json)) {
      const ok = Boolean(r.json.accessToken) && r.json.role === a.role;
      results.push({ ...a, ok, note: `role=${r.json.role}` });
      console.log(`${ok ? '✓' : '✗'} ${a.username} — role=${r.json.role}`);
      continue;
    }

    // บทบาทที่ถูกบังคับยืนยันสองชั้น: ได้ challenge token ไปตั้งค่าก่อน
    const challenge = r.json.challengeToken;
    if (!challenge) {
      results.push({ ...a, ok: false, note: 'ไม่ได้ challengeToken' });
      console.log(`✗ ${a.username} — ไม่ได้ challengeToken`);
      continue;
    }

    const enroll = await post('/auth/mfa/enroll', {}, challenge);
    if (!enroll.json.otpauthUri) {
      results.push({ ...a, ok: false, note: `enroll ล้ม: ${enroll.json.message ?? enroll.status}` });
      console.log(`✗ ${a.username} — enroll ล้ม: ${enroll.json.message ?? enroll.status}`);
      continue;
    }

    const secretB32 = new URL(enroll.json.otpauthUri).searchParams.get('secret');
    const confirm = await post('/auth/mfa/confirm',
      { code: totpCode(base32Decode(secretB32)) }, challenge);

    const ok = Boolean(confirm.json.accessToken);
    results.push({
      ...a, ok,
      note: ok ? `role=${confirm.json.role}` : `confirm ล้ม: ${confirm.json.message ?? confirm.status}`,
      totpSecret: secretB32,
      otpauthUri: enroll.json.otpauthUri,
      recoveryCodes: confirm.json.recoveryCodes ?? confirm.json.codes,
    });
    console.log(`${ok ? '✓' : '✗'} ${a.username} — MFA ผูกแล้ว · role=${confirm.json.role ?? '-'}`);
  }

  // ── สรุป ─────────────────────────────────────────────────────────
  console.log('\n' + '='.repeat(74));
  console.log('บัญชีตัวอย่าง — รหัสผ่านเดียวกันทุกบัญชี: ' + PASSWORD);
  console.log('='.repeat(74));
  for (const r of results) {
    console.log(`${r.ok ? 'ok  ' : 'FAIL'} | ${r.username.padEnd(16)} | ` +
                `${String(r.role).padEnd(16)} | ${r.label ?? ''}`);
  }
  for (const r of results.filter((x) => x.totpSecret)) {
    console.log(`\n── ${r.username} (ต้องยืนยันสองชั้น) ──`);
    console.log(`   TOTP secret : ${r.totpSecret}`);
    console.log(`   otpauth URI : ${r.otpauthUri}`);
    if (r.recoveryCodes) console.log(`   รหัสกู้คืน   : ${[].concat(r.recoveryCodes).join(' ')}`);
  }

  const failed = results.filter((r) => !r.ok);
  if (failed.length) {
    console.log(`\nมี ${failed.length} บัญชีที่ยังล็อกอินไม่ผ่าน`);
    // admin/director ล้มเพราะ MFA_SECRET_KEY เป็นอาการที่เจอซ้ำได้ง่ายที่สุด
    // จึงบอกทางออกตรงนี้เลย แทนที่จะให้ไปไล่หาเอง
    if (failed.some((f) => String(f.note).includes('MFA_SECRET_KEY'))) {
      console.log(
        'ตั้ง MFA_SECRET_KEY ให้โปรเซส API แล้วบูตใหม่ — สร้างด้วย\n' +
        '  node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'base64\'))"\n' +
        'หรือปิดการบังคับชั่วคราวด้วย api/tools/demo-mfa-off.sql (อ่านหัวไฟล์ก่อน)',
      );
    }
    process.exitCode = 1;
  }
}

main().catch((e) => { console.error('\n' + (e.message ?? e)); process.exit(1); });

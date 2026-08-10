/**
 * ทดสอบมาตรการสำหรับระบบจริง
 *
 *   npm run test:hardening
 *
 * ─── ทำไมต้องมีชุดนี้ ───
 * มาตรการในชุดนี้เป็นแบบ "ไม่มีใครสังเกตว่าหายไป" ทั้งหมด — ถ้าเฮดเดอร์
 * ความปลอดภัยหลุด ถ้าเพดานขนาดคำขอถูกถอด หรือถ้าการแบ่งหน้าถูกยกเลิก
 * ระบบยังทำงานได้ปกติทุกอย่าง จนกว่าจะมีคนใช้ช่องนั้นโจมตี
 *
 * สิ่งที่พังแล้วไม่มีอะไรฟ้อง ต้องมีเทสต์คุมเสมอ
 */
import 'reflect-metadata';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createApp } from '../src/main';
import { checkProductionConfig } from '../src/common/config/production-guard';
import { MAX_PAGE_SIZE, parsePage } from '../src/common/pagination/pagination';

process.env.THROTTLE_ENABLED = 'false';

const INST = '11111111-1111-1111-1111-111111111111';

// เส้นทางเปิดวิทยาลัยปิดสนิทถ้าไม่ได้ตั้งกุญแจ จึงต้องมีค่าให้ทดสอบทั้งสองด้าน
const provisionKey = process.env.PROVISION_KEY ?? 'test-provision-key';
process.env.PROVISION_KEY = provisionKey;

let passed = 0;
const failures: string[] = [];

async function check(name: string, fn: () => Promise<string | void> | string | void) {
  try {
    const extra = await fn();
    passed++;
    console.log(`  ${name} ผ่าน${extra ? ' — ' + extra : ''}`);
  } catch (err) {
    failures.push(`${name}: ${(err as Error).message}`);
    console.log(`  ${name} ล้มเหลว — ${(err as Error).message}`);
  }
}

function expect(cond: unknown, message: string): asserts cond {
  if (!cond) throw new Error(message);
}

async function main() {
  console.log('\n══ ตรวจการตั้งค่าก่อนเริ่มระบบ ══');

  await check('HARD-01 การตั้งค่าที่ไม่ปลอดภัยถูกจับครบทุกข้อ', () => {
    const { errors } = checkProductionConfig({
      NODE_ENV: 'production',
      DEV_AUTH: 'true',
      JWT_SECRET: 'test-secret',
      IP_HASH_SECRET: 'test-ip-salt',
      CORS_ORIGINS: '*',
      THROTTLE_ENABLED: 'false',
      AUDIT_ENABLED: 'false',
      ALLOW_SUPERUSER: 'true',
    } as NodeJS.ProcessEnv);

    // ทุกข้อในนี้คือค่าที่ถูกเปิดไว้ตอนพัฒนาแล้วลืมปิดตอน deploy
    expect(errors.length >= 7, `ควรจับได้อย่างน้อย 7 ข้อ จับได้ ${errors.length}`);
    return `จับได้ ${errors.length} ข้อ`;
  });

  await check('HARD-02 การตั้งค่าที่ปลอดภัยผ่านได้', () => {
    const { errors } = checkProductionConfig({
      NODE_ENV: 'production',
      DEV_AUTH: 'false',
      JWT_SECRET: 'x'.repeat(48),
      IP_HASH_SECRET: 'y'.repeat(48),
      CORS_ORIGINS: 'https://app.example.ac.th',
      DATABASE_URL: 'postgres://u:p@db/vecsms?sslmode=require',
      MFA_SECRET_KEY: Buffer.alloc(32, 3).toString('base64'),
      TZ: 'Asia/Bangkok',
    } as NodeJS.ProcessEnv);
    expect(errors.length === 0, `ไม่ควรมีข้อผิดพลาด แต่มี: ${errors.join(' | ')}`);
    return 'ไม่มีข้อทักท้วง';
  });

  await check('HARD-02b ไม่ตั้ง MFA_SECRET_KEY ในระบบจริงถูกจับตั้งแต่บูต', () => {
    // ถ้าไม่มีคีย์นี้ บทบาทที่ถูกบังคับยืนยันสองชั้นจะตั้งค่าไม่ได้เลย
    // ผลคือผู้ดูแลเข้าระบบไม่ได้ทั้งวิทยาลัย — ต้องรู้ตั้งแต่บูต ไม่ใช่ตอนล็อกอิน
    const { errors } = checkProductionConfig({
      NODE_ENV: 'production',
      DEV_AUTH: 'false',
      JWT_SECRET: 'x'.repeat(48),
      IP_HASH_SECRET: 'y'.repeat(48),
      CORS_ORIGINS: 'https://app.example.ac.th',
      DATABASE_URL: 'postgres://u:p@db/vecsms?sslmode=require',
      TZ: 'Asia/Bangkok',
    } as NodeJS.ProcessEnv);
    expect(errors.some((e) => e.includes('MFA_SECRET_KEY')), 'ต้องทักท้วงเรื่องคีย์ MFA');

    const short = checkProductionConfig({
      NODE_ENV: 'production',
      DEV_AUTH: 'false',
      JWT_SECRET: 'x'.repeat(48),
      IP_HASH_SECRET: 'y'.repeat(48),
      CORS_ORIGINS: 'https://app.example.ac.th',
      DATABASE_URL: 'postgres://u:p@db/vecsms?sslmode=require',
      MFA_SECRET_KEY: Buffer.alloc(16, 1).toString('base64'),
      TZ: 'Asia/Bangkok',
    } as NodeJS.ProcessEnv);
    expect(short.errors.some((e) => e.includes('32 ไบต์')), 'คีย์สั้นเกินต้องถูกจับด้วย');
    return 'จับทั้งกรณีไม่ตั้งและตั้งสั้นเกิน';
  });

  await check('HARD-03 JWT_SECRET กับ IP_HASH_SECRET ซ้ำกันถูกจับ', () => {
    const same = 'z'.repeat(48);
    const { errors } = checkProductionConfig({
      NODE_ENV: 'production',
      DEV_AUTH: 'false',
      JWT_SECRET: same,
      IP_HASH_SECRET: same,
      DATABASE_URL: 'postgres://localhost/x',
      TZ: 'Asia/Bangkok',
    } as NodeJS.ProcessEnv);
    expect(
      errors.some((e) => e.includes('ค่าเดียวกัน')),
      'ควรจับได้ว่าใช้ค่าเดียวกัน',
    );
    return 'ถ้าค่าใดรั่ว จะเสียทั้งสองอย่างพร้อมกัน';
  });

  console.log('\n══ เพดานการแบ่งหน้า ══');

  await check('HARD-04 ผู้เรียกเพิ่มเพดานเกินที่ระบบกำหนดไม่ได้', () => {
    const page = parsePage('999999', '0');
    expect(
      page.limit === MAX_PAGE_SIZE,
      `ควรถูกลดเหลือ ${MAX_PAGE_SIZE} ได้ ${page.limit}`,
    );
    return `ขอ 999999 → ได้ ${page.limit}`;
  });

  await check('HARD-05 ค่าที่ผิดรูปแบบถูกปฏิเสธ', () => {
    for (const bad of ['0', '-5', 'abc']) {
      let threw = false;
      try {
        parsePage(bad, '0');
      } catch {
        threw = true;
      }
      expect(threw, `limit=${bad} ควรถูกปฏิเสธ`);
    }
    return 'limit ที่เป็น 0 ติดลบ หรือไม่ใช่ตัวเลข ถูกปฏิเสธ';
  });

  const app = await createApp();
  await app.listen(0);
  const base = `http://127.0.0.1:${(app.getHttpServer().address() as { port: number }).port}/api/v1`;

  const token = async (role: string, personId: string): Promise<string> => {
    const res = await fetch(`${base}/auth/dev-token`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ institutionId: INST, personId, role }),
    });
    const json = (await res.json()) as { accessToken: string };
    return json.accessToken;
  };

  console.log('\n══ เฮดเดอร์ความปลอดภัย ══');

  await check('HARD-06 เฮดเดอร์ที่จำเป็นถูกส่งครบ', async () => {
    const res = await fetch(`${base}/health`);
    const required = {
      'x-content-type-options': 'nosniff',
      'x-frame-options': 'DENY',
      'referrer-policy': 'no-referrer',
    };
    for (const [key, value] of Object.entries(required)) {
      expect(
        res.headers.get(key) === value,
        `${key} ควรเป็น ${value} ได้ ${res.headers.get(key)}`,
      );
    }
    expect(res.headers.get('content-security-policy'), 'ต้องมี Content-Security-Policy');
    expect(!res.headers.get('x-powered-by'), 'ต้องไม่บอกว่าใช้เทคโนโลยีอะไร');
    return 'nosniff · DENY · no-referrer · CSP · ไม่มี X-Powered-By';
  });

  console.log('\n══ เพดานขนาดคำขอ ══');

  await check('HARD-02c เปิดวิทยาลัยต้องมีกุญแจที่ถูกต้อง', async () => {
    /*
     * เส้นทางนี้สร้างวิทยาลัยใหม่ได้ ซึ่งอยู่นอกขอบเขตของทุกบทบาทในระบบ
     * ถ้าไม่มีกุญแจกั้น ใครก็สร้างวิทยาลัยปลอมได้ไม่จำกัด
     */
    const body = JSON.stringify({
      code: '1399991234', nameTh: 'วิทยาลัยทดสอบกุญแจ',
      adminFirstNameTh: 'ทดสอบ', adminLastNameTh: 'กุญแจ',
      adminUsername: 'keytest01',
      yearBe: 2569, yearStartsOn: '2026-05-11', yearEndsOn: '2027-03-31',
    });
    const post = (headers: Record<string, string> = {}) =>
      fetch(`${base}/provisioning/institutions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', ...headers },
        body,
      });

    const none = await post();
    expect(none.status === 403 || none.status === 503,
      `ไม่มีกุญแจควรถูกปฏิเสธ ได้ ${none.status}`);

    // ค่าใน HTTP header ต้องเป็น ASCII จึงใช้ข้อความไทยเป็นกุญแจทดสอบไม่ได้
    const wrong = await post({ 'x-provision-key': 'not-the-real-key' });
    expect(wrong.status === 403 || wrong.status === 503,
      `กุญแจผิดควรถูกปฏิเสธ ได้ ${wrong.status}`);
    return 'ไม่มีกุญแจและกุญแจผิดถูกปฏิเสธทั้งคู่';
  });

  await check('HARD-02e เปิดวิทยาลัยด้วยกุญแจถูกต้องแล้วใช้งานได้จริง', async () => {
    /*
     * ─── ทำไมต้องทดสอบเส้นทางที่ "สำเร็จ" ด้วย ───
     * เดิมมีแต่เทสต์ที่ยืนยันว่ากุญแจผิดถูกปฏิเสธ ซึ่งผ่านมาตลอด
     * แต่เส้นทางที่ผ่านกุญแจแล้วล้มด้วย 500 ทุกครั้ง — ขั้นออกรหัสรีเซ็ต
     * เรียก db.tx() ที่ต้องมีบริบทผู้ใช้ ทั้งที่เส้นทางนี้เป็น @Public
     * จึงไม่มีบริบทให้
     *
     * ที่แย่กว่าคือวิทยาลัยถูก commit ไปแล้วก่อนจะล้ม เหลือค้างพร้อมบัญชี
     * ผู้ดูแลที่เข้าด้วยรหัสผ่านไม่ได้และไม่มีรหัสรีเซ็ต — เข้าไม่ได้ตลอดกาล
     * และเปิดซ้ำก็ไม่ได้เพราะรหัสสถานศึกษาชนตัวเอง
     *
     * เทสต์นี้จึงตรวจถึงขั้น "ผู้ดูแลตั้งรหัสผ่านแล้วล็อกอินได้" ไม่ใช่แค่ 201
     */
    const code = String(Date.now()).slice(-10);
    const created = await fetch(`${base}/provisioning/institutions`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-provision-key': provisionKey },
      body: JSON.stringify({
        code, nameTh: 'วิทยาลัยอาชีวศึกษาเปิดใหม่',
        adminPrefixTh: 'นาย', adminFirstNameTh: 'สมศักดิ์', adminLastNameTh: 'ผู้ดูแล',
        adminUsername: 'NEWADMIN01',
        yearBe: 2569, yearStartsOn: '2026-05-16', yearEndsOn: '2027-03-31',
      }),
    });
    const body = (await created.json()) as {
      institutionId?: string; resetCode?: string; adminUsername?: string;
    };
    expect(created.status === 201,
      `เปิดวิทยาลัยด้วยกุญแจถูกต้องต้องสำเร็จ ได้ ${created.status}: ${JSON.stringify(body)}`);
    expect(body.resetCode,
      'ต้องได้รหัสรีเซ็ตกลับมา มิฉะนั้นไม่มีใครเข้าวิทยาลัยที่เพิ่งเปิดได้เลย');

    // ผู้ดูแลตั้งรหัสผ่านเอง — ผู้ให้บริการไม่เคยรู้รหัสผ่านของลูกค้า
    const pass = 'Wittaya-2569-Kaset';
    const reset = await fetch(`${base}/auth/reset-password`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        institutionId: body.institutionId, username: 'NEWADMIN01',
        code: body.resetCode, newPassword: pass,
      }),
    });
    expect(reset.status === 201 || reset.status === 200,
      `รหัสรีเซ็ตที่ได้ต้องใช้ตั้งรหัสผ่านได้จริง ได้ ${reset.status}`);

    const login = await fetch(`${base}/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ institutionId: body.institutionId, username: 'NEWADMIN01', password: pass }),
    });
    const out = (await login.json()) as { mfaRequired?: boolean; challengeToken?: string };
    expect(out.mfaRequired === true && !!out.challengeToken,
      'ผู้ดูแลคนแรกต้องล็อกอินได้และถูกพาไปตั้งการยืนยันสองชั้น');

    return `เปิดวิทยาลัย ${code} · ผู้ดูแลตั้งรหัสผ่านเองแล้วล็อกอินได้`;
  });

  await check('HARD-02d วิทยาลัยเปลี่ยนแพ็กเกจของตัวเองไม่ได้', async () => {
    /*
     * ถ้าวิทยาลัยเพิ่มที่นั่งให้ตัวเองได้ ก็เท่ากับซื้อแพ็กเกจฟรี
     * ฝั่งวิทยาลัยจึงมีแต่เส้นทางอ่าน และการเขียนถูกปฏิเสธที่ RLS อีกชั้น
     */
    const admin = await token('admin', '30000000-0000-0000-0000-000000000001');
    const get = (p: string) =>
      fetch(`${base}${p}`, { headers: { authorization: `Bearer ${admin}` } });

    const cur = await get('/subscription');
    expect(cur.status === 200, `อ่านแพ็กเกจของตัวเองควรได้ ได้ ${cur.status}`);
    const body = (await cur.json()) as { state?: string; usage?: { students_active?: number } };
    expect(typeof body.state === 'string', 'ต้องบอกสถานะเป็นข้อความให้หน้าจอใช้ได้เลย');

    const plans = await get('/subscription/plans');
    expect(plans.status === 200, `อ่านรายการแพ็กเกจควรได้ ได้ ${plans.status}`);

    // ไม่มีเส้นทางเขียนฝั่งวิทยาลัยเลย — POST ต้องไม่มีอยู่จริง
    const write = await fetch(`${base}/subscription`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${admin}` },
      body: JSON.stringify({ seatsPurchased: 999999 }),
    });
    expect(write.status === 404 || write.status === 405,
      `ไม่ควรมีเส้นทางเขียนฝั่งวิทยาลัย ได้ ${write.status}`);
    return `${body.state} · นักศึกษา ${body.usage?.students_active ?? '-'} คน`;
  });

  await check('HARD-07 คำขอใหญ่เกินได้ 413 ไม่ใช่ 500', async () => {
    const admin = await token('admin', '30000000-0000-0000-0000-000000000001');
    // 2MB ที่เส้นทางทั่วไป (เพดาน 256KB)
    const big = { scores: Array.from({ length: 30000 }, () => ({ enrollmentId: INST, score: 1 })) };
    const res = await fetch(`${base}/gradebook/items/${INST}/scores`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${admin}` },
      body: JSON.stringify(big),
    });
    expect(res.status === 413, `ควรได้ 413 ได้ ${res.status}`);
    const body = (await res.json()) as { message?: string };
    expect(
      typeof body.message === 'string' && body.message.includes('ใหญ่เกิน'),
      'ข้อความต้องบอกผู้ใช้ว่าต้องทำอย่างไรต่อ',
    );
    return body.message;
  });

  await check('HARD-08 เส้นทางนำเข้าข้อมูลรับไฟล์ใหญ่ได้', async () => {
    const registrar = await token('registrar', '30000000-0000-0000-0000-000000000001');
    // ไฟล์นักศึกษา 800 คนเป็น JSON ราว 130KB ซึ่งเกินเพดานทั่วไป 256KB ไม่ได้
    // แต่ต้องผ่านที่เส้นทางนำเข้า มิฉะนั้นฟีเจอร์นำเข้าใช้กับไฟล์จริงไม่ได้เลย
    const rows = Array.from({ length: 900 }, (_, i) => ({
      rowNo: i + 1,
      payload: {
        student_code: `69HARD${String(i).padStart(4, '0')}`,
        first_name_th: `ทดสอบเพดานขนาดคำขอ${i}`,
        last_name_th: 'นามสกุลทดสอบระบบ',
        admitted_year_be: '2569',
      },
    }));
    const body = JSON.stringify({ kind: 'student', sourceName: 'hardening.xlsx', rows });
    const sizeKb = Math.round(Buffer.byteLength(body) / 1024);

    const res = await fetch(`${base}/import`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${registrar}` },
      body,
    });
    expect(res.status < 400, `ควรรับได้ ได้ ${res.status}`);
    const json = (await res.json()) as { total_rows?: number };
    expect(json.total_rows === 900, `ควรรับครบ 900 แถว ได้ ${json.total_rows}`);
    return `${sizeKb} KB · ${json.total_rows} แถว ผ่านเพดานทั่วไป`;
  });

  await check('HARD-09 ค่าที่ render.yaml เตรียมให้ต้องบูตได้จริง', async () => {
    /*
     * ─── ทำไมต้องมีข้อนี้ ───
     * production-guard ทำงานถูกต้องทุกข้อ และมีเทสต์ยืนยันว่ามัน**ปฏิเสธ**
     * ค่าที่ไม่ปลอดภัย แต่ไม่เคยมีเทสต์ไหนถามว่า "ค่าที่คู่มือ deploy
     * บอกให้ตั้ง มันผ่านหรือเปล่า"
     *
     * ผลคือ `MFA_SECRET_KEY` หายไปจากทั้ง render.yaml, .env.example และ
     * ตัวอย่าง docker run — แอปจึงบูตไม่ขึ้นบนทุกผู้ให้บริการเหมือนกันหมด
     * โดยที่เทสต์ทั้ง 152 ข้อยังเขียวสนิท เพราะทุกชุดรันด้วย NODE_ENV
     * ที่ไม่ใช่ production
     *
     * บทเรียนเดียวกับ AUTH-26 — เทสต์ที่เดินทางที่ระบบจริงไม่มี
     * ไม่ได้พิสูจน์อะไรเลย
     */
    // คอมไพล์แล้วไฟล์นี้อยู่ที่ api/dist-test/test/ จึงย้อนขึ้นสามชั้นถึงรากรีโป
    const yaml = await readFile(resolve(__dirname, '..', '..', '..', 'render.yaml'), 'utf8');

    // อ่านชื่อตัวแปรจาก render.yaml ตรง ๆ ไม่ใช่คัดลอกมาไว้ในเทสต์
    const declared = [...yaml.matchAll(/^\s*-\s*key:\s*([A-Z_]+)\s*$/gm)].map((m) => m[1]);
    expect(declared.includes('DATABASE_URL'), 'อ่าน render.yaml ไม่ออก');

    /*
     * ─── ทำไมอ่านจากไฟล์อย่างเดียวไม่พอ ───
     * การไล่ตามรายชื่อที่ไฟล์ประกาศ จับได้แค่ตัวที่**เพิ่มเข้ามา**โดยคู่มือ
     * ไม่ได้บอกวิธีตั้ง แต่จับ "ตัวที่หายไปทั้งตัว" ไม่ได้เลย เพราะสิ่งที่
     * ไม่ได้ประกาศไว้ก็ไม่มีอยู่ในสายตาของเทสต์ตั้งแต่แรก
     *
     * นั่นคือรูปของ PROVISION_KEY ที่หายไปจาก render.yaml ทั้งไฟล์ — deploy
     * ผ่านสนิท health เขียว แล้ว POST /platform/bootstrap ตอบ 503 ทุกครั้ง
     * ซึ่งเป็นขั้นตอนที่ทำได้ครั้งเดียวตลอดอายุระบบ
     *
     * รายชื่อข้างล่างคือตัวแปรที่ **เส้นทางในคู่มือจะใช้ไม่ได้ถ้าขาด** จึงต้อง
     * ยาวขึ้นได้เท่านั้น การลบชื่อออกจากรายชื่อนี้เพื่อให้เทสต์ผ่าน คือการ
     * ลบสัญญาณเตือน ไม่ใช่การแก้ปัญหา
     */
    const REQUIRED = [
      'DATABASE_URL',      // ไม่มี = ไม่บูต
      'JWT_SECRET',        // ไม่มี = ไม่บูต
      'IP_HASH_SECRET',    // ไม่มี = ไม่บูต
      'MFA_SECRET_KEY',    // ไม่มี = ไม่บูต (รอบที่แล้วพังที่ตัวนี้)
      'PROVISION_KEY',     // ไม่มี = เปิดวิทยาลัยและตั้งบัญชีผู้ให้บริการไม่ได้ (503)
      'CORS_ORIGINS',      // ไม่มี = แอปเว็บเรียก API ไม่ได้ หน้าจอว่างแบบไม่มีข้อความ
      'TRUST_PROXY',       // ไม่มี = ทั้งวิทยาลัยแชร์ถังจำกัดคำขอใบเดียว และ ip_hash ไร้ค่า
      'JOBS_ENABLED',      // ไม่มี = ค่าเริ่มต้นเปิด ซึ่งถูกเฉพาะตอน instance เดียว
      'DEV_AUTH',          // ไม่มี = ไม่ได้ประกาศเจตนาว่าปิด
      'TZ',                // ไม่มี = งานประจำวันรันผิดเวลา 7 ชั่วโมง
    ];
    const absent = REQUIRED.filter((k) => !declared.includes(k));
    expect(
      absent.length === 0,
      `render.yaml ไม่ได้ประกาศตัวแปรที่เส้นทางในคู่มือต้องใช้: ${absent.join(', ')}`,
    );

    // ค่าที่ผู้ให้บริการสุ่มให้หรือคนตั้งเองตามคู่มือ — ใช้ค่าที่ถูกต้องตามรูปแบบ
    const supplied: Record<string, string> = {
      DATABASE_URL: 'postgres://vecsms_app:pw@db.example.com:5432/vecsms?sslmode=require',
      JWT_SECRET: 'j'.repeat(48),
      IP_HASH_SECRET: 'i'.repeat(48),
      MFA_SECRET_KEY: Buffer.alloc(32, 7).toString('base64'),
      PROVISION_KEY: 'p'.repeat(48),
      CORS_ORIGINS: 'https://vecsms.pages.dev',
    };

    const env: NodeJS.ProcessEnv = { NODE_ENV: 'production' };
    for (const key of declared) {
      // ค่าที่ render.yaml กำหนดไว้ตายตัวอ่านจากไฟล์ ส่วนที่เหลือใช้ตารางข้างบน
      const fixed = yaml.match(
        new RegExp(`-\\s*key:\\s*${key}\\s*\\n\\s*value:\\s*"?([^"\\n]+)"?`),
      );
      env[key] = fixed ? fixed[1].trim() : supplied[key];
    }

    const missing = declared.filter((k) => env[k] === undefined);
    expect(
      missing.length === 0,
      `render.yaml ประกาศตัวแปรที่คู่มือไม่ได้บอกวิธีตั้ง: ${missing.join(', ')}`,
    );

    const { errors } = checkProductionConfig(env);
    expect(
      errors.length === 0,
      `ค่าที่ deploy จริงจะได้ทำให้แอปไม่บูต ${errors.length} ข้อ — ${errors.join(' · ')}`,
    );

    // และต้องครบจริง ไม่ใช่ผ่านเพราะ guard ไม่ได้ตรวจอะไรเลย
    const { errors: emptyErrors } = checkProductionConfig({ NODE_ENV: 'production' });
    expect(
      emptyErrors.length > 0,
      'guard ไม่ปฏิเสธ env ที่ว่างเปล่า — เทสต์นี้จึงไม่ได้พิสูจน์อะไร',
    );

    return (
      `ตัวแปร ${declared.length} ตัวจาก render.yaml บูตผ่าน · ` +
      `ที่จำเป็นครบ ${REQUIRED.length} ตัว · env ว่างยังถูกปฏิเสธ ${emptyErrors.length} ข้อ`
    );
  });

  await app.close();

  console.log('');
  if (failures.length) {
    console.log(`════ ล้มเหลว ${failures.length} ข้อ จากทั้งหมด ${passed + failures.length} ════`);
    failures.forEach((f) => console.log(`  ✕ ${f}`));
    process.exit(1);
  }
  console.log(`════ ทดสอบมาตรการสำหรับระบบจริงผ่านครบ ${passed} ข้อ ════`);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

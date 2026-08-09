/**
 * ทดสอบหน้าจอผู้ดูแลข้ามวิทยาลัยแบบ end-to-end
 *
 *   npm run test:platform
 *
 * ─── สิ่งที่ชุดนี้ต้องพิสูจน์ให้ได้ ───
 * หน้าจอนี้เป็นที่เดียวในระบบที่ตั้งใจให้เห็นทุกวิทยาลัยพร้อมกัน ข้อผิดพลาด
 * ข้อเดียวจึงเท่ากับข้อมูลส่วนบุคคลของทุกวิทยาลัยหลุดจากที่เดียว
 *
 *   1. token สองชนิดข้ามฝั่งกันไม่ได้ทั้งสองทาง
 *   2. ผู้ให้บริการเข้าถึงข้อมูลของวิทยาลัยไม่ได้ แม้ผ่าน endpoint ของวิทยาลัยเอง
 *   3. ต้องผ่านสองชั้นเสมอ — รหัสผ่านอย่างเดียวไม่พอสำหรับบัญชีระดับนี้
 *   4. การระงับปิดทางเข้าจริง และคืนสิทธิ์แล้วกลับมาใช้ได้ทันที
 *   5. ทุกการกระทำถูกบันทึกพร้อมชื่อบัญชีที่ทำ
 */
import 'reflect-metadata';
import { Client } from 'pg';
import { createHmac } from 'node:crypto';
import { createApp } from '../src/main';
import { base32Decode, currentStep } from '../src/modules/auth/totp';

// ชุดนี้ยิงล็อกอินหลายรอบโดยตั้งใจ ตัวจำกัดจำนวนครั้งมีชุดทดสอบของตัวเอง
process.env.THROTTLE_ENABLED = 'false';
process.env.MFA_SECRET_KEY ??= Buffer.alloc(32, 9).toString('base64');
process.env.PROVISION_KEY ??= 'test-provision-key';

const PROVISION_KEY = process.env.PROVISION_KEY;
const INST = '11111111-1111-1111-1111-111111111111';
const PERSON = '30000000-0000-0000-0000-0000000000d1';

const OWNER_PASSWORD = 'ผู้ให้บริการ-รหัสผ่านยาวพอ-2569';
const SUPPORT_PASSWORD = 'ฝ่ายสนับสนุน-รหัสผ่านยาวพอ-2569';

let passed = 0;
const failures: string[] = [];

async function check(name: string, fn: () => Promise<string | void>) {
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

/** คำนวณรหัส TOTP เองตาม RFC 6238 ไม่เรียกโค้ดของแอป (เหตุผลเดียวกับ auth.e2e) */
function totpCode(secret: Buffer, step = currentStep()): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const d = createHmac('sha1', secret).update(counter).digest();
  const o = d[d.length - 1] & 0x0f;
  const bin =
    ((d[o] & 0x7f) << 24) | ((d[o + 1] & 0xff) << 16) |
    ((d[o + 2] & 0xff) << 8) | (d[o + 3] & 0xff);
  return String(bin % 1_000_000).padStart(6, '0');
}

/**
 * ล้างบัญชีผู้ให้บริการก่อนเริ่ม
 *
 * bootstrap_platform_owner() ยอมทำงานเฉพาะตอนที่ยังไม่มีบัญชีสักคน ซึ่งเป็น
 * คุณสมบัติที่ต้องมี — แต่แปลว่าเทสต์ต้องเริ่มจากศูนย์ทุกครั้ง
 */
async function resetPlatformUsers() {
  const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
  await admin.connect();
  await admin.query('delete from platform_action_log');
  await admin.query('delete from platform_session');
  await admin.query('delete from platform_login_attempt');
  await admin.query('delete from platform_user');
  await admin.query(
    `update institution set suspended_at = null, suspended_reason = null, suspended_by = null`,
  );
  // บุคลากรที่ใช้ทดสอบว่าการระงับปิดทางเข้าจริง — บทบาท registrar
  // เพราะบทบาทนี้ไม่ถูกบังคับ MFA จึงได้ token จริงตั้งแต่ล็อกอินครั้งเดียว
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th)
     values ($1, $2, 'ทดสอบ', 'ระงับวิทยาลัย') on conflict (id) do nothing`,
    [PERSON, INST],
  );
  const staff = await admin.query<{ id: string }>(
    `insert into staff (institution_id, person_id, staff_code, is_teacher)
     values ($1, $2, 'PLAT-REG-01', false)
     on conflict (institution_id, staff_code) do update set is_teacher = false
     returning id`,
    [INST, PERSON],
  );
  await admin.query(
    `insert into staff_role (staff_id, role, effective_from, granted_by, reason)
     values ($1, 'registrar', current_date - 1, $1, 'ทดสอบการระงับวิทยาลัย')
     on conflict do nothing`,
    [staff.rows[0].id],
  );
  await admin.query(`delete from user_credential where username = 'platsuspend01'`);
  await admin.end();
}

async function main() {
  await resetPlatformUsers();

  const app = await createApp();
  await app.listen(0);
  const base = `http://127.0.0.1:${(app.getHttpServer().address() as { port: number }).port}/api/v1`;

  const post = (path: string, body?: unknown, headers: Record<string, string> = {}) =>
    fetch(`${base}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...headers },
      body: JSON.stringify(body ?? {}),
    });

  const get = (path: string, headers: Record<string, string> = {}) =>
    fetch(`${base}${path}`, { headers });

  const json = async (res: Response) => {
    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    return { status: res.status, body };
  };

  let ownerSetupCode = '';
  let ownerToken = '';
  let ownerSecret: Buffer | undefined;
  let supportToken = '';

  console.log('\n══ ติดตั้งครั้งแรก ══');

  await check('PLAT-01 สร้างบัญชีผู้ให้บริการคนแรกต้องมีกุญแจติดตั้ง', async () => {
    const body = { username: 'vendor.owner', displayName: 'เจ้าของระบบ' };

    const none = await post('/platform/bootstrap', body);
    expect(none.status === 403 || none.status === 503,
      `ไม่มีกุญแจควรถูกปฏิเสธ ได้ ${none.status}`);

    const wrong = await post('/platform/bootstrap', body, { 'x-provision-key': 'wrong-key' });
    expect(wrong.status === 403 || wrong.status === 503,
      `กุญแจผิดควรถูกปฏิเสธ ได้ ${wrong.status}`);

    const ok = await json(await post('/platform/bootstrap', body,
      { 'x-provision-key': PROVISION_KEY }));
    expect(ok.status === 201 || ok.status === 200, `ควรสำเร็จ ได้ ${ok.status}`);
    expect(typeof ok.body.setupCode === 'string', 'ต้องได้รหัสตั้งค่ากลับมา');
    // สิ่งที่ห้ามคืนเด็ดขาดคือรหัสผ่าน — คนที่ติดตั้งต้องไม่รู้รหัสของเจ้าตัว
    expect(!('password' in ok.body), 'ต้องไม่คืนรหัสผ่านกลับมาเลย');

    ownerSetupCode = String(ok.body.setupCode);
    return 'ไม่มีกุญแจและกุญแจผิดถูกปฏิเสธ · ได้รหัสตั้งค่าไม่ใช่รหัสผ่าน';
  });

  await check('PLAT-02 สร้างบัญชีคนแรกซ้ำไม่ได้แม้มีกุญแจที่ถูกต้อง', async () => {
    /*
     * ข้อนี้คือสิ่งที่ทำให้ PROVISION_KEY ไม่กลายเป็นประตูหลังถาวร
     * กุญแจที่รั่วภายหลังต้องแต่งตั้งใครเป็น owner ไม่ได้อีกเลย
     */
    const again = await json(await post('/platform/bootstrap',
      { username: 'vendor.evil', displayName: 'ผู้บุกรุก' },
      { 'x-provision-key': PROVISION_KEY }));
    expect(again.status >= 400, `ควรถูกปฏิเสธ ได้ ${again.status}`);
    expect(String(again.body.message ?? '').includes('มีบัญชีผู้ให้บริการอยู่แล้ว'),
      `ข้อความควรบอกเหตุผล ได้ "${again.body.message}"`);
    return `ถูกปฏิเสธด้วย ${again.status}`;
  });

  await check('PLAT-03 ตั้งรหัสผ่านครั้งแรกด้วยรหัสตั้งค่า และรหัสผิดใช้ไม่ได้', async () => {
    const wrong = await json(await post('/platform/setup', {
      username: 'vendor.owner', code: 'ZZZZ-ZZZZ', newPassword: OWNER_PASSWORD,
    }));
    expect(wrong.status === 401, `รหัสผิดควรได้ 401 ได้ ${wrong.status}`);

    const ok = await json(await post('/platform/setup', {
      username: 'vendor.owner', code: ownerSetupCode, newPassword: OWNER_PASSWORD,
    }));
    expect(ok.status === 200 || ok.status === 201, `ควรสำเร็จ ได้ ${ok.status} ${ok.body.message}`);

    // ใช้ซ้ำไม่ได้ — รหัสตั้งค่าเป็นของใช้ครั้งเดียวเหมือนรหัสรีเซ็ต
    const reuse = await json(await post('/platform/setup', {
      username: 'vendor.owner', code: ownerSetupCode, newPassword: OWNER_PASSWORD,
    }));
    expect(reuse.status === 401, `ใช้รหัสซ้ำควรถูกปฏิเสธ ได้ ${reuse.status}`);
    return 'รหัสผิดถูกปฏิเสธ · ตั้งได้ครั้งเดียว · ใช้ซ้ำไม่ได้';
  });

  console.log('\n══ เข้าสู่ระบบสองชั้น ══');

  await check('PLAT-04 ล็อกอินด้วยรหัสผ่านอย่างเดียวไม่เคยได้ token จริง', async () => {
    const bad = await json(await post('/platform/login', {
      username: 'vendor.owner', password: 'ผิดแน่นอน-ไม่ใช่รหัสนี้',
    }));
    expect(bad.status === 401, `รหัสผ่านผิดควรได้ 401 ได้ ${bad.status}`);

    const out = await json(await post('/platform/login', {
      username: 'vendor.owner', password: OWNER_PASSWORD,
    }));
    expect(out.status === 200 || out.status === 201, `ควรสำเร็จ ได้ ${out.status}`);
    expect(out.body.mfaRequired === true, 'ต้องบังคับยืนยันสองชั้นเสมอ');
    expect(!out.body.accessToken, 'ต้องไม่คืน access token จากรหัสผ่านอย่างเดียว');
    expect(typeof out.body.challengeToken === 'string', 'ต้องได้ challenge token');
    expect(out.body.enrollmentRequired === true, 'บัญชีใหม่ต้องถูกบอกให้ตั้ง MFA ก่อน');
    return 'ได้ challenge token เท่านั้น';
  });

  await check('PLAT-05 challenge token ใช้กับเส้นทางอื่นไม่ได้', async () => {
    const login = await json(await post('/platform/login', {
      username: 'vendor.owner', password: OWNER_PASSWORD,
    }));
    const challenge = String(login.body.challengeToken);

    const res = await get('/platform/institutions', { authorization: `Bearer ${challenge}` });
    expect(res.status === 401,
      `challenge token ต้องใช้กับเส้นทางข้อมูลไม่ได้ ได้ ${res.status}`);
    return 'ถูกปฏิเสธ 401 ตามที่ควร';
  });

  await check('PLAT-06 ตั้ง MFA ด้วย challenge token แล้วได้ token จริงทันที', async () => {
    /*
     * บทเรียนจาก 0036 ข้อ 6 — ถ้าเส้นทางตั้งค่าไม่รับ challenge token
     * บัญชีที่ยังไม่เคยตั้งจะไม่มีวันตั้งได้ และเข้าระบบไม่ได้ตลอดไป
     * ซึ่งกระทบผู้ให้บริการคนแรกเสมอ คือทุกคนตอนติดตั้ง
     */
    const login = await json(await post('/platform/login', {
      username: 'vendor.owner', password: OWNER_PASSWORD,
    }));
    const challenge = String(login.body.challengeToken);
    const auth = { authorization: `Bearer ${challenge}` };

    const enroll = await json(await post('/platform/mfa/enroll', {}, auth));
    expect(enroll.status === 200 || enroll.status === 201,
      `ตั้งค่าด้วย challenge token ควรทำได้ ได้ ${enroll.status}`);
    const m = /secret=([A-Z2-7]+)/.exec(String(enroll.body.otpauthUri));
    expect(m, 'ต้องได้ URI สำหรับสร้าง QR');
    ownerSecret = base32Decode(m![1]);

    // ใช้ช่วงเวลาก่อนหน้าหนึ่งช่วง เพื่อให้รหัสของช่วงปัจจุบันยังใช้ได้ต่อ
    const confirm = await json(await post('/platform/mfa/confirm',
      { code: totpCode(ownerSecret!, currentStep() - 1) }, auth));
    expect(confirm.status === 200 || confirm.status === 201,
      `ยืนยันควรสำเร็จ ได้ ${confirm.status} ${confirm.body.message}`);
    expect(typeof confirm.body.accessToken === 'string',
      'ตั้งค่าเสร็จต้องได้ token จริงเลย ไม่ใช่ให้กลับไปล็อกอินใหม่');
    expect(confirm.body.role === 'owner', `บทบาทควรเป็น owner ได้ ${confirm.body.role}`);

    ownerToken = String(confirm.body.accessToken);
    return 'ตั้งค่าด้วย challenge token ได้ และได้ token จริงกลับมาเลย';
  });

  await check('PLAT-07 ล็อกอินรอบถัดไปต้องใส่รหัสจากแอปเสมอ', async () => {
    const login = await json(await post('/platform/login', {
      username: 'vendor.owner', password: OWNER_PASSWORD,
    }));
    expect(!login.body.accessToken, 'ต้องไม่ได้ token จริงจากรหัสผ่าน');
    expect(login.body.enrollmentRequired === false, 'ตั้ง MFA แล้วต้องไม่ขอให้ตั้งอีก');

    const verify = await json(await post('/platform/mfa/verify', {
      challengeToken: String(login.body.challengeToken),
      code: totpCode(ownerSecret!),
    }));
    expect(verify.status === 200 || verify.status === 201,
      `ยืนยันควรสำเร็จ ได้ ${verify.status} ${verify.body.message}`);
    expect(typeof verify.body.accessToken === 'string', 'ต้องได้ token จริง');

    // รหัสของช่วงเวลาเดิมใช้ซ้ำไม่ได้ — คนที่แอบเห็นรหัสบนหน้าจอใช้ตามไม่ได้
    const login2 = await json(await post('/platform/login', {
      username: 'vendor.owner', password: OWNER_PASSWORD,
    }));
    const again = await json(await post('/platform/mfa/verify', {
      challengeToken: String(login2.body.challengeToken),
      code: totpCode(ownerSecret!),
    }));
    expect(again.status === 401, `รหัสซ้ำควรถูกปฏิเสธ ได้ ${again.status}`);
    return 'ต้องใส่รหัสทุกครั้ง และรหัสเดิมใช้ซ้ำไม่ได้';
  });

  console.log('\n══ กำแพงระหว่างสองฝั่ง ══');

  await check('PLAT-08 token ของวิทยาลัยใช้กับหน้าจอผู้ให้บริการไม่ได้', async () => {
    const dev = await json(await post('/auth/dev-token', {
      institutionId: INST, personId: PERSON, role: 'admin',
    }));
    expect(typeof dev.body.accessToken === 'string',
      'ต้องได้ token ของวิทยาลัยมาทดสอบ (ต้องเปิด DEV_AUTH=true)');

    const auth = { authorization: `Bearer ${dev.body.accessToken}` };
    for (const path of ['/platform/institutions', '/platform/plans', '/platform/audit']) {
      const res = await get(path, auth);
      expect(res.status === 403,
        `${path} ด้วย token ของวิทยาลัยควรได้ 403 ได้ ${res.status}`);
    }
    return 'admin ของวิทยาลัยถูกปฏิเสธทุกเส้นทางของผู้ให้บริการ';
  });

  await check('PLAT-09 token ของผู้ให้บริการใช้กับเส้นทางของวิทยาลัยไม่ได้', async () => {
    /*
     * ด้านนี้สำคัญกว่าอีกด้าน — ถ้าผ่านได้ ผู้ให้บริการจะอ่านข้อมูลนักศึกษา
     * ของทุกวิทยาลัยได้จากบัญชีเดียว ซึ่งเป็นเหตุละเมิดข้อมูลตาม PDPA
     */
    const auth = { authorization: `Bearer ${ownerToken}` };
    for (const path of ['/students', '/staff', '/subscription', '/jobs']) {
      const res = await get(path, auth);
      expect(res.status === 401 || res.status === 403,
        `${path} ด้วย token ของผู้ให้บริการควรถูกปฏิเสธ ได้ ${res.status}`);
    }
    return 'ถูกปฏิเสธทุกเส้นทางของวิทยาลัย';
  });

  await check('PLAT-10 หน้าจอผู้ให้บริการไม่มีข้อมูลส่วนบุคคลของใครเลย', async () => {
    const auth = { authorization: `Bearer ${ownerToken}` };
    const list = await json(await get('/platform/institutions', auth));
    expect(list.status === 200, `ควรอ่านได้ ได้ ${list.status}`);

    const rows = (list.body.rows ?? []) as Record<string, unknown>[];
    expect(rows.length > 0, 'ต้องเห็นทะเบียนสถานศึกษา มิฉะนั้นหน้าจอใช้ไม่ได้');

    // ชื่อคอลัมน์ที่บ่งบอกว่ามีข้อมูลของคนติดมาด้วย
    const forbidden = ['first_name', 'last_name', 'national_id', 'student_code', 'email', 'phone'];
    const leaked = Object.keys(rows[0]).filter((k) =>
      forbidden.some((f) => k.toLowerCase().includes(f)));
    expect(leaked.length === 0, `มีข้อมูลส่วนบุคคลติดมาด้วย: ${leaked.join(', ')}`);

    const detail = await json(await get(`/platform/institutions/${INST}`, auth));
    expect(detail.status === 200, `รายละเอียดควรอ่านได้ ได้ ${detail.status}`);
    const text = JSON.stringify(detail.body);
    expect(!/"students"\s*:\s*\[/.test(text), 'รายละเอียดต้องไม่มีรายชื่อนักศึกษา');
    return `เห็น ${rows.length} วิทยาลัย โดยไม่มีข้อมูลส่วนบุคคลสักช่อง`;
  });

  console.log('\n══ ขอบเขตของบทบาทฝั่งผู้ให้บริการ ══');

  await check('PLAT-11 owner สร้างบัญชีอื่นได้ และได้รหัสตั้งค่าไม่ใช่รหัสผ่าน', async () => {
    const auth = { authorization: `Bearer ${ownerToken}` };
    const created = await json(await post('/platform/users', {
      username: 'vendor.support', displayName: 'ฝ่ายสนับสนุน', role: 'support',
    }, auth));
    expect(created.status === 200 || created.status === 201,
      `ควรสำเร็จ ได้ ${created.status} ${created.body.message}`);
    expect(typeof created.body.setupCode === 'string', 'ต้องได้รหัสตั้งค่า');

    await post('/platform/setup', {
      username: 'vendor.support',
      code: String(created.body.setupCode),
      newPassword: SUPPORT_PASSWORD,
    });

    // เดินครบสองชั้นให้บัญชีใหม่ เพื่อเอา token ไปทดสอบขอบเขตบทบาท
    const login = await json(await post('/platform/login', {
      username: 'vendor.support', password: SUPPORT_PASSWORD,
    }));
    const challenge = { authorization: `Bearer ${login.body.challengeToken}` };
    const enroll = await json(await post('/platform/mfa/enroll', {}, challenge));
    const secret = base32Decode(/secret=([A-Z2-7]+)/.exec(String(enroll.body.otpauthUri))![1]);
    const confirm = await json(await post('/platform/mfa/confirm',
      { code: totpCode(secret, currentStep() - 1) }, challenge));
    expect(typeof confirm.body.accessToken === 'string',
      `บัญชีใหม่ต้องเข้าระบบได้ ได้ ${confirm.status} ${confirm.body.message}`);
    supportToken = String(confirm.body.accessToken);
    return 'สร้างบัญชี support และเข้าระบบครบสองชั้นได้';
  });

  await check('PLAT-12 support ระงับวิทยาลัยหรือแก้แพ็กเกจไม่ได้', async () => {
    const auth = { authorization: `Bearer ${supportToken}` };

    const suspend = await post(`/platform/institutions/${INST}/suspend`,
      { reason: 'ทดสอบว่าบทบาทนี้ทำไม่ได้จริง' }, auth);
    expect(suspend.status === 403, `support ระงับได้ไม่ควรเกิดขึ้น ได้ ${suspend.status}`);

    const plan = await post('/platform/plans',
      { code: 'evil', nameTh: 'แพ็กเกจที่ไม่ควรถูกสร้าง' }, auth);
    expect(plan.status === 403, `support แก้แพ็กเกจได้ไม่ควรเกิดขึ้น ได้ ${plan.status}`);

    const users = await get('/platform/users', auth);
    expect(users.status === 403, `support เห็นบัญชีผู้ให้บริการได้ไม่ควรเกิดขึ้น ได้ ${users.status}`);

    // แต่ต้องอ่านสิ่งที่จำเป็นต่อการตอบลูกค้าได้ มิฉะนั้นบทบาทนี้ไร้ประโยชน์
    const list = await get('/platform/institutions', auth);
    expect(list.status === 200, `support ควรอ่านทะเบียนได้ ได้ ${list.status}`);
    return 'เขียนไม่ได้ทุกทาง แต่ยังอ่านได้ตามหน้าที่';
  });

  console.log('\n══ การระงับวิทยาลัย ══');

  await check('PLAT-13 ระงับแล้วผู้ใช้ของวิทยาลัยเข้าระบบไม่ได้ คืนสิทธิ์แล้วได้ทันที', async () => {
    const auth = { authorization: `Bearer ${ownerToken}` };

    // เตรียมบัญชีจริงของวิทยาลัยไว้ทดสอบ
    const dev = await json(await post('/auth/dev-token', {
      institutionId: INST, personId: PERSON, role: 'registrar',
    }));
    const tenantAuth = { authorization: `Bearer ${dev.body.accessToken}` };
    const issued = await post('/auth/credentials', {
      personId: PERSON, username: 'platsuspend01', temporaryPassword: 'รหัสผ่านทดสอบระงับ-2569',
    }, tenantAuth);
    expect(issued.status === 200 || issued.status === 201,
      `ออกบัญชีทดสอบไม่สำเร็จ ได้ ${issued.status}`);

    const login = async () =>
      json(
        await post('/auth/login', {
          institutionId: INST,
          username: 'platsuspend01',
          password: 'รหัสผ่านทดสอบระงับ-2569',
        }),
      );

    const before = await login();
    expect(typeof before.body.accessToken === 'string',
      `ก่อนระงับต้องเข้าระบบได้ ได้ ${before.status} ${before.body.message}`);

    // ── ระงับ ──
    const suspended = await json(await post(`/platform/institutions/${INST}/suspend`,
      { reason: 'ค้างชำระค่าบริการเกิน 60 วัน — ติดต่อฝ่ายบัญชีเพื่อเปิดใช้งาน' }, auth));
    expect(suspended.status === 200 || suspended.status === 201,
      `ระงับควรสำเร็จ ได้ ${suspended.status} ${suspended.body.message}`);

    const during = await login();
    expect(during.status === 403 || during.status === 422,
      `ระหว่างถูกระงับต้องเข้าไม่ได้ ได้ ${during.status}`);
    expect(String(during.body.message ?? '').includes('ระงับ'),
      `ข้อความต้องบอกว่าถูกระงับ ได้ "${during.body.message}"`);
    expect(String(during.body.message ?? '').includes('ค้างชำระ'),
      'ข้อความต้องมีเหตุผลที่ผู้ให้บริการเขียนไว้ มิฉะนั้นลูกค้าไม่รู้ว่าต้องทำอะไร');

    // เหตุผลว่างต้องถูกปฏิเสธตั้งแต่ชั้น DTO
    const noReason = await post(`/platform/institutions/${INST}/suspend`, { reason: 'สั้น' }, auth);
    expect(noReason.status === 400, `เหตุผลสั้นเกินไปควรถูกปฏิเสธ ได้ ${noReason.status}`);

    // ── คืนสิทธิ์ ──
    const resumed = await json(await post(`/platform/institutions/${INST}/resume`, {}, auth));
    expect(resumed.status === 200 || resumed.status === 201,
      `คืนสิทธิ์ควรสำเร็จ ได้ ${resumed.status}`);

    const after = await login();
    expect(typeof after.body.accessToken === 'string',
      `คืนสิทธิ์แล้วต้องเข้าได้ทันที ได้ ${after.status} ${after.body.message}`);
    return 'เข้าได้ → ถูกระงับพร้อมเหตุผล → คืนสิทธิ์แล้วเข้าได้ทันที';
  });

  console.log('\n══ บันทึกการกระทำ ══');

  await check('PLAT-14 ทุกการกระทำถูกบันทึกพร้อมชื่อบัญชีที่ทำ', async () => {
    const auth = { authorization: `Bearer ${ownerToken}` };
    const res = await json(await get('/platform/audit', auth));
    expect(res.status === 200, `ควรอ่านได้ ได้ ${res.status}`);

    const rows = res.body as unknown as { username: string; action: string }[];
    const actions = new Set(rows.map((r) => r.action));
    for (const wanted of ['suspend_institution', 'resume_institution', 'create_platform_user']) {
      expect(actions.has(wanted), `ต้องมีบันทึกของ ${wanted} — มี ${[...actions].join(', ')}`);
    }
    expect(rows.every((r) => typeof r.username === 'string' && r.username.length > 0),
      'ทุกบรรทัดต้องระบุว่าบัญชีไหนเป็นคนทำ');
    return `บันทึกครบ ${rows.length} รายการ`;
  });

  await check('PLAT-15 บันทึกการกระทำแก้ไม่ได้แม้ผ่านชั้นฐานข้อมูล', async () => {
    // ยิงตรงเข้าฐานข้อมูลด้วยผู้ใช้ของแอป (ไม่ใช่ superuser) ในบริบทผู้ให้บริการ
    // ถ้าแก้ได้ บันทึกนี้ใช้ตอบลูกค้าไม่ได้เลยเพราะพิสูจน์อะไรไม่ได้
    const c = new Client({ connectionString: process.env.DATABASE_URL });
    await c.connect();
    try {
      await c.query('begin');
      await c.query(
        `select set_config('app.institution_id', '', true),
                set_config('app.role', 'platform', true)`,
      );
      const r = await c.query(`update platform_action_log set action = 'ถูกแก้'`);
      expect(r.rowCount === 0, `แก้บันทึกได้ ${r.rowCount} แถว`);
      const d = await c.query(`delete from platform_action_log`);
      expect(d.rowCount === 0, `ลบบันทึกได้ ${d.rowCount} แถว`);
      await c.query('rollback');
      return 'แก้ไม่ได้และลบไม่ได้';
    } catch (err) {
      await c.query('rollback').catch(() => undefined);
      // RLS ปฏิเสธด้วย error ก็ถือว่าผ่าน — สิ่งที่ผิดคือแก้ได้สำเร็จ
      const message = (err as Error).message;
      expect(/policy|permission|insufficient/i.test(message), message);
      return 'ถูกปฏิเสธด้วยนโยบาย';
    } finally {
      await c.end();
    }
  });

  await app.close();

  console.log(`\n══ สรุป ══`);
  console.log(`  ผ่าน ${passed} ข้อ · ล้มเหลว ${failures.length} ข้อ`);
  if (failures.length > 0) {
    failures.forEach((f) => console.log(`  ✗ ${f}`));
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

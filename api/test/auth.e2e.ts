/**
 * ทดสอบการยืนยันตัวตนแบบ end-to-end
 *
 *   npm run test:auth
 */
import 'reflect-metadata';
import { Client } from 'pg';
import { createApp } from '../src/main';
import { base32Decode, currentStep } from '../src/modules/auth/totp';
import { createHmac } from 'node:crypto';

// ชุดนี้ทดสอบตรรกะการยืนยันตัวตน จึงยิงเข้าสู่ระบบรัว ๆ โดยตั้งใจ
// การจำกัดจำนวนครั้งจะไปขวางจนเทสต์ล้มเหลวด้วยเหตุผลที่ไม่เกี่ยวกัน
// ตัวจำกัดมีชุดทดสอบของตัวเองที่ test/ratelimit.e2e.ts
process.env.THROTTLE_ENABLED = 'false';

// กุญแจเข้ารหัสความลับ TOTP — ในระบบจริงมาจากที่เก็บความลับของผู้ให้บริการ
process.env.MFA_SECRET_KEY ??= Buffer.alloc(32, 7).toString('base64');


const INST = '11111111-1111-1111-1111-111111111111';
const PERSON = '30000000-0000-0000-0000-000000000001';
const STUDENT = '30000000-0000-0000-0000-000000000011';
const PERSON2 = '30000000-0000-0000-0000-000000000002';
const STUDENT2 = '30000000-0000-0000-0000-000000000022';
const STAFF = '30000000-0000-0000-0000-0000000000a1';
const ADMIN_PERSON = '30000000-0000-0000-0000-0000000000b1';

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

/**
 * คำนวณรหัส TOTP ฝั่งเทสต์เอง — จงใจไม่เรียกฟังก์ชันของแอป
 *
 * ถ้าเทสต์ใช้โค้ดตัวเดียวกับที่กำลังทดสอบ ความผิดพลาดในสูตรจะผ่านเทสต์ไปได้
 * เพราะทั้งสองฝั่งผิดเหมือนกัน การเขียนซ้ำตาม RFC 6238 ตรง ๆ จึงเป็นการ
 * ตรวจสูตรจริง ๆ ไม่ใช่ตรวจว่าโค้ดเรียกตัวเองได้
 */
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

async function seed() {
  const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
  await admin.connect();
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th) values
       ($1, $3, 'กิตติพงษ์', 'แสงทอง'), ($2, $3, 'วรรณิศา', 'บุญมี')
     on conflict (id) do nothing`,
    [PERSON, PERSON2, INST],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be) values
       ($1, $3, $4, '69AUTH0001', 2569), ($2, $3, $5, '69AUTH0002', 2569)
     on conflict (id) do nothing`,
    [STUDENT, STUDENT2, INST, PERSON, PERSON2],
  );

  // การออกรหัสรีเซ็ตหน้าเคาน์เตอร์ต้องระบุตัวเจ้าหน้าที่ผู้ยืนยันตัวตน
  // token ที่มีบทบาท registrar เฉย ๆ ยังออกไม่ได้ ต้องผูกกับ staff จริง
  // ซึ่งเป็นข้อกำหนดที่ตั้งใจ — บันทึกต้องตอบได้ว่าใครปล่อยรหัสออกไป
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th)
     values ($1, $2, 'อารีย์', 'ทะเบียนดี') on conflict (id) do nothing`,
    [STAFF, INST],
  );
  await admin.query(
    `insert into staff (institution_id, person_id, staff_code, is_teacher)
     values ($1, $2, 'REG-AUTH-01', false)
     on conflict (institution_id, staff_code) do nothing`,
    [INST, STAFF],
  );
  // ── บัญชีผู้ดูแลสำหรับทดสอบการยืนยันสองชั้น ────────────────────
  // บทบาท admin อยู่ในรายชื่อที่ auth_policy บังคับ MFA ตั้งแต่ 0036
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th)
     values ($1, $2, 'ผู้ดูแล', 'ระบบทดสอบ') on conflict (id) do nothing`,
    [ADMIN_PERSON, INST],
  );
  const st = await admin.query<{ id: string }>(
    `insert into staff (institution_id, person_id, staff_code, is_teacher)
     values ($1, $2, 'ADM-AUTH-01', false)
     on conflict (institution_id, staff_code) do update set is_teacher = false
     returning id`,
    [INST, ADMIN_PERSON],
  );
  // granted_by อ้าง staff ไม่ใช่ person — ผู้ให้สิทธิ์ต้องเป็นบุคลากรจริง
  await admin.query(
    `insert into staff_role (staff_id, role, effective_from, granted_by)
     select $1, 'admin', current_date - 1, s.id
       from staff s where s.institution_id = $2 and s.staff_code = 'REG-AUTH-01'
     on conflict do nothing`,
    [st.rows[0].id, INST],
  );

  await admin.end();
}

function api(base: string, tok?: string) {
  return async (path: string, init: RequestInit = {}) => {
    const res = await fetch(`${base}${path}`, {
      ...init,
      headers: {
        'content-type': 'application/json',
        ...(tok ? { authorization: `Bearer ${tok}` } : {}),
        ...(init.headers ?? {}),
      },
    });
    const text = await res.text();
    let body: unknown = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      body = text;
    }
    return { status: res.status, body: body as Record<string, string> };
  };
}

async function main() {
  console.log('▸ เตรียมข้อมูล');
  await seed();

  const app = await createApp();
  await app.listen(0);
  const url = await app.getUrl();
  const base = `${url.replace('[::1]', '127.0.0.1')}/api/v1`;
  const anon = api(base);

  const devTok = (
    await anon('/auth/dev-token', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, personId: PERSON, role: 'registrar' }),
    })
  ).body.accessToken;
  const registrar = api(base, devTok);

  console.log('');
  console.log('══ การออกและใช้รหัสผ่าน ══');

  await check('AUTH-01 งานทะเบียนออกรหัสผ่านชุดแรกได้', async () => {
    const r = await registrar('/auth/credentials', {
      method: 'POST',
      body: JSON.stringify({
        personId: PERSON,
        username: '69AUTH0001',
        temporaryPassword: 'Temp-2569-xyz',
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    await registrar('/auth/credentials', {
      method: 'POST',
      body: JSON.stringify({
        personId: PERSON2,
        username: '69AUTH0002',
        temporaryPassword: 'Temp-2569-abc',
      }),
    });
    return r.body.username;
  });

  await check('AUTH-02 บทบาทอื่นออกรหัสผ่านให้คนอื่นไม่ได้', async () => {
    const t = (
      await anon('/auth/dev-token', {
        method: 'POST',
        body: JSON.stringify({ institutionId: INST, personId: PERSON, role: 'student' }),
      })
    ).body.accessToken;
    const r = await api(base, t)('/auth/credentials', {
      method: 'POST',
      body: JSON.stringify({
        personId: PERSON2,
        username: 'hack',
        temporaryPassword: 'Whatever-1234',
      }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  let refreshToken = '';
  let accessToken = '';

  await check('AUTH-03 เข้าสู่ระบบด้วยรหัสผ่านถูกต้อง', async () => {
    const r = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'Temp-2569-xyz',
        deviceId: 'device-A',
        deviceLabel: 'Samsung A15',
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.accessToken && r.body.refreshToken, 'ต้องได้ทั้งสอง token');
    expect(
      (r.body as unknown as { mustChangePassword: boolean }).mustChangePassword === true,
      'ต้องบังคับเปลี่ยนรหัสครั้งแรก',
    );
    expect(r.body.role === 'student', `บทบาทควรเป็น student ได้ ${r.body.role}`);
    accessToken = r.body.accessToken;
    refreshToken = r.body.refreshToken;
    return `บทบาท ${r.body.role} · หมดอายุใน ${r.body.expiresInSeconds} วินาที`;
  });

  await check('AUTH-04 รหัสผ่านผิดถูกปฏิเสธและนับจำนวนครั้ง', async () => {
    const r = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'ผิดแน่นอน',
      }),
    });
    expect(r.status === 401, `ควรได้ 401 ได้ ${r.status}`);
    expect(
      String(r.body.message).includes('เหลืออีก'),
      `ควรบอกจำนวนครั้งที่เหลือ: ${r.body.message}`,
    );
    return r.body.message;
  });

  await check('AUTH-05 ไม่บอกว่ารหัสประจำตัวมีอยู่จริงหรือไม่', async () => {
    const r = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: 'ไม่มีคนนี้',
        password: 'อะไรก็ได้',
      }),
    });
    expect(r.status === 401, `ควรได้ 401 ได้ ${r.status}`);
    expect(
      !String(r.body.message).includes('ไม่พบ'),
      `ข้อความไม่ควรเปิดเผยว่าไม่มีผู้ใช้: ${r.body.message}`,
    );
    return r.body.message;
  });

  await check('AUTH-06 ใส่ผิดครบจำนวนแล้วบัญชีถูกล็อก', async () => {
    let last = { status: 0, body: {} as Record<string, string> };
    for (let i = 0; i < 5; i++) {
      last = await anon('/auth/login', {
        method: 'POST',
        body: JSON.stringify({
          institutionId: INST,
          username: '69AUTH0002',
          password: 'ผิดทุกครั้ง',
        }),
      });
    }
    expect(last.status === 403, `ควรได้ 403 ได้ ${last.status}`);
    expect(String(last.body.message).includes('ล็อก'), `ควรแจ้งว่าถูกล็อก: ${last.body.message}`);

    const correct = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        password: 'Temp-2569-abc',
      }),
    });
    expect(correct.status === 403, `ล็อกแล้วต้องเข้าไม่ได้แม้รหัสถูก ได้ ${correct.status}`);
    return last.body.message;
  });

  console.log('');
  console.log('══ อุปกรณ์ที่ผูกกับบัญชี ══');

  await check('AUTH-07 เครื่องเดิมเข้าได้ตามปกติ', async () => {
    const r = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'Temp-2569-xyz',
        deviceId: 'device-A',
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
  });

  await check('AUTH-08 เครื่องที่สองต้องรออนุมัติ', async () => {
    const r = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'Temp-2569-xyz',
        deviceId: 'device-B',
        deviceLabel: 'iPhone ของเพื่อน',
      }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
    expect(String(r.body.message).includes('อนุมัติ'), String(r.body.message));
    return r.body.message;
  });

  console.log('');
  console.log('══ Refresh token ══');

  let rotated = '';

  await check('AUTH-09 ต่ออายุแล้วได้ token ชุดใหม่', async () => {
    const r = await anon('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, refreshToken }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.refreshToken !== refreshToken, 'refresh token ต้องหมุนทุกครั้ง');
    rotated = r.body.refreshToken;
  });

  await check('AUTH-10 ใช้ token เดิมซ้ำต้องถูกปฏิเสธและเตะทุกอุปกรณ์ออก', async () => {
    const reuse = await anon('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, refreshToken }),
    });
    expect(reuse.status === 401, `ควรได้ 401 ได้ ${reuse.status}`);

    const after = await anon('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, refreshToken: rotated }),
    });
    expect(after.status === 401, `token ที่เหลือต้องใช้ไม่ได้ด้วย ได้ ${after.status}`);
    return 'เพิกถอนทุก session เมื่อพบการใช้ token ซ้ำ';
  });

  console.log('');
  console.log('══ เปลี่ยนรหัสผ่าน ══');

  await check('AUTH-11 เปลี่ยนรหัสผ่านต้องยืนยันรหัสเดิม', async () => {
    const login = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'Temp-2569-xyz',
        deviceId: 'device-A',
      }),
    });
    accessToken = login.body.accessToken;

    const wrong = await api(base, accessToken)('/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({
        currentPassword: 'ไม่ใช่รหัสเดิม',
        newPassword: 'Suan-2569-ok',
      }),
    });
    expect(wrong.status === 401, `ควรได้ 401 ได้ ${wrong.status}`);
  });

  await check('AUTH-12 ปฏิเสธรหัสผ่านที่เดาง่ายและที่มีรหัสประจำตัวอยู่ในนั้น', async () => {
    const weak = await api(base, accessToken)('/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({ currentPassword: 'Temp-2569-xyz', newPassword: '12345678' }),
    });
    expect(weak.status === 400, `ควรได้ 400 ได้ ${weak.status}`);

    const withCode = await api(base, accessToken)('/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({
        currentPassword: 'Temp-2569-xyz',
        newPassword: 'x69AUTH0001x',
      }),
    });
    expect(withCode.status === 400, `ควรได้ 400 ได้ ${withCode.status}`);
    return withCode.body.message;
  });

  await check('AUTH-13 เปลี่ยนสำเร็จแล้วรหัสเดิมใช้ไม่ได้', async () => {
    const ok = await api(base, accessToken)('/auth/change-password', {
      method: 'POST',
      body: JSON.stringify({
        currentPassword: 'Temp-2569-xyz',
        newPassword: 'Chang-Yon-2569',
      }),
    });
    expect(ok.status === 201 || ok.status === 200, `ได้ ${ok.status}: ${JSON.stringify(ok.body)}`);

    const old = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'Temp-2569-xyz',
        deviceId: 'device-A',
      }),
    });
    expect(old.status === 401, `รหัสเดิมต้องใช้ไม่ได้ ได้ ${old.status}`);

    const fresh = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0001',
        password: 'Chang-Yon-2569',
        deviceId: 'device-A',
      }),
    });
    expect(
      fresh.status === 201 || fresh.status === 200,
      `รหัสใหม่ต้องใช้ได้ ได้ ${fresh.status}`,
    );
    expect(
      (fresh.body as unknown as { mustChangePassword: boolean }).mustChangePassword === false,
      'ไม่ต้องบังคับเปลี่ยนอีกแล้ว',
    );
    return 'รหัสเดิมใช้ไม่ได้ · รหัสใหม่ใช้ได้ · ไม่บังคับเปลี่ยนซ้ำ';
  });

  console.log('');
  console.log('══ บันทึกการเข้าสู่ระบบ ══');

  await check('AUTH-14 บันทึกทุกครั้งและเก็บไอพีเป็นค่าแฮช', async () => {
    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    const r = await admin.query<{ n: string; with_ip: string; raw: string }>(
      `select count(*) as n,
              count(*) filter (where ip_hash is not null) as with_ip,
              count(*) filter (where encode(ip_hash, 'escape') like '%127.0.0.1%') as raw
         from login_attempt where username like '69AUTH%'`,
    );
    await admin.end();
    const { n, with_ip: withIp, raw } = r.rows[0];
    expect(Number(n) >= 8, `ควรมีบันทึกอย่างน้อย 8 รายการ ได้ ${n}`);
    expect(Number(raw) === 0, 'ห้ามเก็บไอพีเป็นค่าจริง');
    return `${n} รายการ · มีค่าแฮชไอพี ${withIp} รายการ · ไม่มีไอพีดิบ`;
  });

  console.log('');
  console.log('══ รีเซ็ตรหัสผ่าน ══');

  // เจ้าหน้าที่ที่ผูกกับ staff จริง — ต่างจาก devTok ข้างบนที่เป็นนักศึกษา
  // ซึ่งได้บทบาท registrar มาจาก dev-token เฉย ๆ
  const staffTok = (
    await anon('/auth/dev-token', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, personId: STAFF, role: 'registrar' }),
    })
  ).body.accessToken;
  const counter = api(base, staffTok);

  await check('AUTH-15 ยังไม่ตั้งช่องทางส่ง ต้องบอกให้ติดต่องานทะเบียน ไม่ใช่ทำเป็นส่งแล้ว', async () => {
    delete process.env.RESET_DELIVERY;
    const r = await anon('/auth/forgot-password', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, username: '69AUTH0001' }),
    });
    expect(r.status === 503, `ควรได้ 503 ได้ ${r.status}`);
    expect(
      String(r.body.message).includes('งานทะเบียน'),
      `ต้องบอกทางออกที่ใช้ได้จริง: ${r.body.message}`,
    );
    return r.body.message;
  });

  await check('AUTH-16 ไม่บอกว่ารหัสประจำตัวมีอยู่จริงหรือไม่', async () => {
    process.env.RESET_DELIVERY = 'log';

    // บัญชีนี้มีอยู่จริงแต่ไม่มีอีเมลหรือเบอร์บันทึกไว้ จึงไม่มีรหัสถูกส่งออกไป
    // ส่วนอีกบัญชีไม่มีอยู่เลย — ทั้งสองกรณีต้องตอบเหมือนกันทุกตัวอักษร
    const real = await anon('/auth/forgot-password', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, username: '69AUTH0001' }),
    });
    const fake = await anon('/auth/forgot-password', {
      method: 'POST',
      body: JSON.stringify({ institutionId: INST, username: '69NOBODY99' }),
    });

    expect(real.status === fake.status, `สถานะต่างกัน ${real.status} vs ${fake.status}`);
    expect(
      real.body.message === fake.body.message,
      `ข้อความต่างกัน:\n  ${real.body.message}\n  ${fake.body.message}`,
    );
    return real.body.message;
  });

  let resetCode = '';

  await check('AUTH-17 งานทะเบียนออกรหัสรีเซ็ตได้ และได้รหัสที่ใช้ครั้งเดียว ไม่ใช่รหัสผ่าน', async () => {
    const r = await counter('/auth/credentials/reset-code', {
      method: 'POST',
      body: JSON.stringify({ personId: PERSON2 }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(typeof r.body.code === 'string' && r.body.code.length >= 8, 'ต้องได้รหัสกลับมา');
    expect(r.body.expiresAt != null, 'ต้องบอกเวลาหมดอายุ');
    resetCode = r.body.code;

    // รหัสต้องเก็บไว้เป็นค่าแฮชเท่านั้น ถ้าเก็บค่าจริงไว้ด้วย ใครที่อ่าน
    // ตารางได้จะยึดบัญชีที่กำลังรอรีเซ็ตอยู่ได้ทันทีโดยไม่ต้องรู้รหัสผ่านเดิม
    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    const stored = await admin.query<{ n: string }>(
      `select count(*) as n from password_reset
        where encode(token_hash, 'escape') like $1`,
      [`%${resetCode.replace('-', '')}%`],
    );
    await admin.end();
    expect(Number(stored.rows[0].n) === 0, 'ห้ามเก็บรหัสรีเซ็ตแบบอ่านออกได้');
    return `${resetCode} · หมดอายุ ${r.body.expiresAt}`;
  });

  await check('AUTH-18 รหัสผ่านใหม่ที่อ่อนถูกปฏิเสธโดยไม่เผารหัสรีเซ็ตทิ้ง', async () => {
    const weak = await anon('/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        code: resetCode,
        newPassword: '12345678',
      }),
    });
    expect(weak.status === 400, `ควรได้ 400 ได้ ${weak.status}`);

    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    const r = await admin.query<{ attempts: number; consumed_at: Date | null }>(
      `select attempts, consumed_at from password_reset
         where person_id = $1 order by created_at desc limit 1`,
      [PERSON2],
    );
    await admin.end();
    expect(r.rows[0].consumed_at === null, 'รหัสรีเซ็ตถูกใช้ไปทั้งที่รหัสผ่านใหม่ไม่ผ่าน');
    expect(
      r.rows[0].attempts === 0,
      `ตัวนับไม่ควรขยับเพราะยังไม่ได้เทียบรหัสเลย ได้ ${r.rows[0].attempts}`,
    );
    return weak.body.message;
  });

  await check('AUTH-19 กรอกรหัสรีเซ็ตผิดถูกปฏิเสธและถูกนับ', async () => {
    const r = await anon('/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        code: 'ZZZZ-ZZZZ',
        newPassword: 'Reset-Mai-2569',
      }),
    });
    expect(r.status === 401, `ควรได้ 401 ได้ ${r.status}`);

    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    const c = await admin.query<{ attempts: number }>(
      `select attempts from password_reset where person_id = $1 order by created_at desc limit 1`,
      [PERSON2],
    );
    await admin.end();
    expect(
      c.rows[0].attempts === 1,
      `ตัวนับต้องขยับเป็น 1 ได้ ${c.rows[0].attempts} — ถ้าไม่ขยับแปลว่าเดารหัสได้ไม่จำกัด`,
    );
    return r.body.message;
  });

  await check('AUTH-20 ใช้รหัสถูกต้องแล้วบัญชีที่ถูกล็อกกลับเข้าระบบได้ทันที', async () => {
    // บัญชีนี้ถูกล็อกไว้ตั้งแต่ AUTH-06 การรีเซ็ตต้องปลดล็อกให้ด้วย
    // มิฉะนั้นผู้ใช้จะตั้งรหัสใหม่สำเร็จแล้วยังเข้าไม่ได้อยู่ดี
    const ok = await anon('/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        code: resetCode.toLowerCase().replace('-', ' '),
        newPassword: 'Reset-Mai-2569',
      }),
    });
    expect(ok.status === 201 || ok.status === 200, `ได้ ${ok.status}: ${JSON.stringify(ok.body)}`);

    const login = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        password: 'Reset-Mai-2569',
      }),
    });
    expect(
      login.status === 201 || login.status === 200,
      `ต้องเข้าได้ทันที ได้ ${login.status}: ${JSON.stringify(login.body)}`,
    );
    expect(
      (login.body as unknown as { mustChangePassword: boolean }).mustChangePassword === false,
      'ไม่ต้องบังคับเปลี่ยนอีก เพราะเจ้าตัวเป็นคนพิมพ์รหัสเอง',
    );
    return 'ปลดล็อก · รหัสใหม่ใช้ได้ · ไม่บังคับเปลี่ยนซ้ำ · รับรหัสที่พิมพ์ต่างรูปแบบได้';
  });

  await check('AUTH-21 รหัสรีเซ็ตใช้ซ้ำไม่ได้ และรหัสผ่านเดิมใช้ไม่ได้', async () => {
    const again = await anon('/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        code: resetCode,
        newPassword: 'Reset-Song-2569',
      }),
    });
    expect(again.status === 401, `ควรได้ 401 ได้ ${again.status}`);

    const old = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST,
        username: '69AUTH0002',
        password: 'Temp-2569-abc',
      }),
    });
    expect(old.status === 401, `รหัสผ่านเดิมต้องใช้ไม่ได้ ได้ ${old.status}`);
    return again.body.message;
  });

  await check('AUTH-22 บทบาทอื่นออกรหัสรีเซ็ตให้คนอื่นไม่ได้', async () => {
    const t = (
      await anon('/auth/dev-token', {
        method: 'POST',
        body: JSON.stringify({ institutionId: INST, personId: PERSON, role: 'student' }),
      })
    ).body.accessToken;
    const r = await api(base, t)('/auth/credentials/reset-code', {
      method: 'POST',
      body: JSON.stringify({ personId: PERSON2 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('AUTH-23 บทบาท registrar ที่ไม่ใช่บุคลากรจริงออกรหัสไม่ได้', async () => {
    // devTok เป็นนักศึกษาที่ได้บทบาท registrar มาจาก dev-token
    // ถ้าออกรหัสได้ บันทึกจะตอบไม่ได้ว่าใครเป็นผู้ยืนยันตัวตนและปล่อยรหัสออกไป
    const r = await registrar('/auth/credentials/reset-code', {
      method: 'POST',
      body: JSON.stringify({ personId: PERSON2 }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(String(r.body.message).includes('บุคลากร'), String(r.body.message));
    return r.body.message;
  });

  console.log('');
  console.log('══ การยืนยันตัวตนสองชั้น ══');

  let challenge = '';
  let mfaSecret: Buffer | null = null;
  let recoveryCodes: string[] = [];

  await check('AUTH-24 ผู้ดูแลล็อกอินแล้วยังไม่ได้ token จริง', async () => {
    await registrar('/auth/credentials', {
      method: 'POST',
      body: JSON.stringify({
        personId: ADMIN_PERSON, username: 'ADMIN01',
        temporaryPassword: 'Admin-2569-xyz',
      }),
    });

    const r = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(!r.body.accessToken, 'ต้องไม่ได้ access token ก่อนผ่านชั้นที่สอง');
    expect((r.body as any).mfaRequired === true, 'ต้องบอกว่าต้องยืนยันสองชั้น');
    expect((r.body as any).enrollmentRequired === true,
      'คนที่ยังไม่ได้ตั้ง MFA ต้องถูกพาไปตั้ง ไม่ใช่ปล่อยเข้าเลย');
    challenge = (r.body as any).challengeToken;
    expect(challenge, 'ต้องได้ token ชั่วคราวไว้ตั้งค่า');
    return 'ได้ challenge token แทน access token';
  });

  await check('AUTH-25 challenge token ใช้กับเส้นทางอื่นไม่ได้', async () => {
    /*
     * นี่คือทั้งหมดของ MFA — ถ้า token ชั่วคราวใช้แทน access token ได้
     * ชั้นที่สองจะกลายเป็นแค่หน้าจอที่ข้ามได้ด้วยการเรียก endpoint อื่นตรง ๆ
     * โดยไม่ต้องใส่รหัสอะไรเลย
     */
    const c = api(base, challenge);
    const r = await c('/students');
    expect(r.status === 401, `ควรได้ 401 ได้ ${r.status}`);
    expect(/ยืนยันตัวตนสองชั้น/.test(String(r.body.message)),
      `ข้อความควรบอกว่าต้องยืนยันก่อน ได้ ${r.body.message}`);

    const s = await c('/auth/mfa/status');
    expect(s.status === 401, `challenge token ต้องใช้กับ /auth/mfa/status ไม่ได้เช่นกัน ได้ ${s.status}`);
  });

  await check('AUTH-26 ตั้งค่า MFA ด้วย challenge token ล้วน ๆ แล้วได้ token จริง', async () => {
    /*
     * ─── ต้องเดินด้วย challenge token เท่านั้น ห้ามใช้ dev-token ───
     * เดิมเทสต์ข้อนี้หยิบ token จริงจาก /auth/dev-token มาตั้งค่า ซึ่งเป็น
     * เส้นทางที่ **ไม่มีในระบบจริง** เพราะ production-guard ห้าม DEV_AUTH=true
     *
     * ผลคือเทสต์ผ่านมาตลอดทั้งที่ในระบบจริงผู้ดูแลที่ยังไม่ได้ตั้ง MFA
     * เข้าไม่ได้เลยสักทาง — ล็อกอินได้แต่ challenge token ใช้กับ
     * /auth/mfa/enroll ไม่ได้ จึงไม่มีวันตั้งค่าเสร็จและไม่มีวันได้ token จริง
     * ซึ่งเกิดกับผู้ดูแลคนแรกของทุกวิทยาลัยที่เปิดใหม่
     *
     * เทสต์นี้จึงต้องใช้ทางเดียวกับที่ผู้ใช้จริงมีอยู่ในมือเท่านั้น
     */
    const challengeApi = api(base, challenge);

    const e = await challengeApi('/auth/mfa/enroll', { method: 'POST' });
    expect(e.status === 201, `ตั้งค่าด้วย challenge token ต้องได้ 201 ได้ ${e.status}: ${JSON.stringify(e.body)}`);
    expect(/^otpauth:\/\/totp\//.test(String(e.body.otpauthUri)), 'ต้องได้ URI สำหรับสร้าง QR');

    const m = /secret=([A-Z2-7]+)/.exec(String(e.body.otpauthUri));
    expect(m, 'URI ต้องมีความลับแบบฐาน 32');
    mfaSecret = base32Decode(m![1]);

    // ยังไม่ยืนยัน = ยังไม่เปิดใช้ คนที่สแกน QR ไม่สำเร็จต้องไม่ถูกล็อกออกจากระบบ
    // ตรวจผ่านการล็อกอินใหม่ เพราะ /auth/mfa/status ไม่รับ challenge token (AUTH-25)
    const midway = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
      }),
    });
    expect((midway.body as any).enrollmentRequired === true,
      'สแกน QR แล้วแต่ยังไม่ยืนยัน ต้องยังถือว่ายังไม่ได้ตั้ง');

    // ใช้รหัสของช่วงก่อนหน้าโดยตั้งใจ — ทดสอบว่ายอมรับนาฬิกาที่เดินช้าหนึ่งช่วง
    // และทำให้ AUTH-27 ใช้รหัสของช่วงปัจจุบันได้ (ต้องใหม่กว่าเสมอ)
    const c = await api(base, (midway.body as any).challengeToken)('/auth/mfa/confirm', {
      method: 'POST',
      body: JSON.stringify({ code: totpCode(mfaSecret!, currentStep() - 1) }),
    });
    expect(c.status === 201, `ได้ ${c.status}: ${JSON.stringify(c.body)}`);
    recoveryCodes = (c.body as any).recoveryCodes;
    expect(recoveryCodes?.length === 8, `ควรได้รหัสกู้คืน 8 ใบ ได้ ${recoveryCodes?.length}`);

    /*
     * ต้องได้ token จริงติดมากับการยืนยันเลย
     *
     * ถ้าไม่ได้ ผู้ใช้ต้องไปเรียก /auth/mfa/verify ต่อด้วยรหัสของ**ช่วงถัดไป**
     * เพราะ mfa_verify_step กันการใช้ช่วงเดิมซ้ำ แปลว่าต้องนั่งรอให้แอป
     * เปลี่ยนตัวเลขก่อนถึงจะเข้าได้ ทั้งที่เพิ่งพิสูจน์ครบสองชั้นไปเมื่อครู่
     */
    const tok = (c.body as any).accessToken;
    expect(tok, 'ยืนยันเสร็จด้วย challenge token ต้องได้ access token กลับมาเลย');

    const usable = await api(base, tok)('/auth/mfa/status');
    expect(usable.status === 200 && (usable.body as any).confirmed === true,
      `token ที่ได้ต้องใช้งานได้จริง ได้ ${usable.status}`);

    /*
     * ต้องคืน `role` มาด้วย เหมือนกับที่ /auth/login คืน
     *
     * เดิม `issueTokens()` ไม่ได้คืนบทบาท มีแต่ /auth/login ที่เติมเองทีหลัง
     * ทางนี้จึงคืน token ที่ใช้งานได้ทุกเส้นทางแต่ไม่บอกว่าเป็นบทบาทอะไร
     * ผลคือหน้าจอที่กรองเมนูตามบทบาทแสดงเมนูว่างให้ผู้ดูแลที่เพิ่งตั้ง MFA
     * เสร็จ — บั๊กที่ยิง API อย่างเดียวไม่มีวันเห็น เพราะทุกคำขอยังผ่านหมด
     */
    expect((c.body as any).role === 'admin',
      `ต้องคืนบทบาทมาด้วยเหมือน /auth/login ได้ ${JSON.stringify((c.body as any).role)}`);

    return `ตั้งค่าครบด้วย challenge token · รหัสกู้คืน ${recoveryCodes.length} ใบ · ได้ token จริงพร้อมบทบาททันที`;
  });

  await check('AUTH-27 ล็อกอินแล้วยืนยันด้วยรหัสจากแอป ได้ token จริง', async () => {
    const login = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
      }),
    });
    expect((login.body as any).enrollmentRequired === false,
      'ตั้งค่าแล้วต้องไม่ขอให้ตั้งอีก');
    challenge = (login.body as any).challengeToken;

    const v = await anon('/auth/mfa/verify', {
      method: 'POST',
      body: JSON.stringify({ challengeToken: challenge, code: totpCode(mfaSecret!) }),
    });
    expect(v.status === 201, `ได้ ${v.status}: ${JSON.stringify(v.body)}`);
    expect(v.body.accessToken && v.body.refreshToken, 'ต้องได้ token จริงทั้งสอง');

    // token ที่ได้ต้องใช้งานได้จริง
    const ok = await api(base, v.body.accessToken)('/auth/mfa/status');
    expect(ok.status === 200, `token จริงควรใช้ได้ ได้ ${ok.status}`);
    return 'ได้ token จริงและใช้งานได้';
  });

  await check('AUTH-28 รหัสเดิมใช้ซ้ำไม่ได้', async () => {
    /*
     * รหัส TOTP หนึ่งตัวใช้ได้ 30 วินาที ถ้าไม่จำว่าใช้ไปแล้ว ผู้ที่แอบเห็น
     * รหัสบนหน้าจอจะใช้ซ้ำได้ภายในหน้าต่างนั้น ซึ่งพอสำหรับเข้าระบบหนึ่งครั้ง
     * และไม่มีอาการอะไรให้เห็นเลย
     */
    const login = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
      }),
    });
    const r = await anon('/auth/mfa/verify', {
      method: 'POST',
      body: JSON.stringify({
        challengeToken: (login.body as any).challengeToken,
        code: totpCode(mfaSecret!),
      }),
    });
    expect(r.status === 401, `รหัสที่ใช้ไปแล้วควรถูกปฏิเสธ ได้ ${r.status}`);
    expect(/ใช้ไปแล้ว/.test(JSON.stringify(r.body)),
      `ข้อความควรบอกว่ารหัสถูกใช้ไปแล้ว ได้ ${JSON.stringify(r.body)}`);
  });

  await check('AUTH-29 รหัสกู้คืนใช้ได้ครั้งเดียว', async () => {
    const code = recoveryCodes[0];

    const login1 = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
      }),
    });
    const r1 = await anon('/auth/mfa/recovery', {
      method: 'POST',
      body: JSON.stringify({
        challengeToken: (login1.body as any).challengeToken, code,
      }),
    });
    expect(r1.status === 201, `ได้ ${r1.status}: ${JSON.stringify(r1.body)}`);
    expect(r1.body.accessToken, 'ต้องได้ token จริง');
    expect((r1.body as any).recoveryCodesRemaining === 7,
      `ควรเหลือ 7 ใบ ได้ ${(r1.body as any).recoveryCodesRemaining}`);

    const login2 = await anon('/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
      }),
    });
    const r2 = await anon('/auth/mfa/recovery', {
      method: 'POST',
      body: JSON.stringify({
        challengeToken: (login2.body as any).challengeToken, code,
      }),
    });
    expect(r2.status === 401, `รหัสกู้คืนใบเดิมควรใช้ซ้ำไม่ได้ ได้ ${r2.status}`);
    return 'ใช้ได้หนึ่งครั้ง เหลือ 7 ใบ';
  });

  await check('AUTH-30 ใส่รหัสผิดหลายครั้งถูกระงับชั่วคราว', async () => {
    // ตัวนับต้องอยู่ในฐานข้อมูล ถ้าฟังก์ชันตรวจ raise ตัวนับจะถูก rollback
    // ทุกครั้งแล้วเดารหัสหกหลักได้ไม่จำกัดจำนวนครั้ง
    let last: { status: number; body: Record<string, string> } | null = null;
    for (let i = 0; i < 6; i++) {
      const login = await anon('/auth/login', {
        method: 'POST',
        body: JSON.stringify({
          institutionId: INST, username: 'ADMIN01', password: 'Admin-2569-xyz',
        }),
      });
      last = await anon('/auth/mfa/verify', {
        method: 'POST',
        body: JSON.stringify({
          challengeToken: (login.body as any).challengeToken, code: '000000',
        }),
      });
    }
    expect(last!.status === 401, `ได้ ${last!.status}`);
    expect(/ระงับ/.test(JSON.stringify(last!.body)),
      `ควรถูกระงับหลังผิดหลายครั้ง ได้ ${JSON.stringify(last!.body)}`);
    return String((last!.body as any).message?.message ?? last!.body.message);
  });

  await app.close();

  console.log('');
  if (failures.length) {
    console.log(`════ ล้มเหลว ${failures.length} ข้อ จากทั้งหมด ${passed + failures.length} ════`);
    for (const f of failures) console.log(`  ✕ ${f}`);
    process.exit(1);
  }
  console.log(`════ ทดสอบการยืนยันตัวตนผ่านครบ ${passed} ข้อ ════`);
}

main().catch((err) => {
  console.error('เทสต์ล้มเหลว:', err);
  process.exit(1);
});

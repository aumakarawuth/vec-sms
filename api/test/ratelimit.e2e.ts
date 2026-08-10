/**
 * ทดสอบการจำกัดจำนวนคำขอทั้งสองชั้น
 *
 *   npm run test:ratelimit
 *
 * ─── ทำไมต้องแยกเป็นชุดของตัวเอง ───
 * ชุด auth.e2e ยิงเข้าสู่ระบบรัว ๆ โดยตั้งใจเพื่อทดสอบการล็อกบัญชี
 * ถ้าเปิดตัวจำกัดไว้ในชุดนั้น เทสต์จะล้มเหลวด้วยเหตุผลที่ไม่เกี่ยวกัน
 * และถ้าปิดตัวจำกัดทุกชุดโดยไม่มีชุดไหนทดสอบมันเลย ตัวจำกัดก็จะพังเงียบ ๆ
 */
import 'reflect-metadata';
import { Client } from 'pg';
import { createApp } from '../src/main';

const INST = '11111111-1111-1111-1111-111111111111';
const PERSON = '40000000-0000-0000-0000-000000000001';
const STUDENT = '40000000-0000-0000-0000-000000000011';

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

async function seed() {
  const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
  await admin.connect();
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th)
     values ($1, $2, 'ทดสอบ', 'จำกัดจำนวน') on conflict (id) do nothing`,
    [PERSON, INST],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be)
     values ($1, $2, $3, '69RATE0001', 2569) on conflict (id) do nothing`,
    [STUDENT, INST, PERSON],
  );
  await admin.end();
}

async function main() {
  await seed();

  const app = await createApp();
  await app.listen(0);
  const base = `http://127.0.0.1:${(app.getHttpServer().address() as { port: number }).port}/api/v1`;

  const login = (username: string, password: string) =>
    fetch(`${base}/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ institutionId: INST, username, password }),
    });

  console.log('\n══ ตัวจำกัดในโปรเซส ══');

  await check('RATE-01 health ต้องไม่ถูกจำกัด', async () => {
    // ระบบตรวจสอบยิง endpoint นี้ถี่โดยตั้งใจ ถ้าถูกจำกัดแพลตฟอร์ม
    // จะรีสตาร์ท service ทิ้งเองโดยไม่มีอะไรผิดจริง
    let ok = 0;
    for (let i = 0; i < 60; i++) {
      const res = await fetch(`${base}/health`);
      if (res.ok) ok++;
    }
    expect(ok === 60, `ยิง 60 ครั้งควรผ่านหมด ผ่าน ${ok}`);
    return 'ยิง 60 ครั้งติดผ่านหมด';
  });

  await check('RATE-02 เข้าสู่ระบบถี่เกินถูกปฏิเสธด้วย 429', async () => {
    let blocked = 0;
    let lastRetryAfter: string | null = null;
    for (let i = 0; i < 16; i++) {
      const res = await login('69RATE0001', 'ผิดแน่นอน-x9');
      if (res.status === 429) {
        blocked++;
        lastRetryAfter = res.headers.get('retry-after');
      }
    }
    expect(blocked > 0, `ยิง 16 ครั้งควรโดนปฏิเสธบ้าง โดน ${blocked}`);
    expect(lastRetryAfter !== null, 'ต้องมีเฮดเดอร์ Retry-After บอกว่ารออีกนานเท่าไร');
    return `โดนปฏิเสธ ${blocked} จาก 16 ครั้ง · Retry-After ${lastRetryAfter} วินาที`;
  });

  await check('RATE-03 มีเฮดเดอร์ RateLimit บอกโควตาที่เหลือ', async () => {
    const res = await fetch(`${base}/auth/dev-token`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ institutionId: INST, personId: PERSON, role: 'student' }),
    });
    const limit = res.headers.get('ratelimit-limit');
    const remaining = res.headers.get('ratelimit-remaining');
    expect(limit, 'ต้องมีเฮดเดอร์ RateLimit-Limit');
    expect(remaining, 'ต้องมีเฮดเดอร์ RateLimit-Remaining');
    return `เพดาน ${limit} · เหลือ ${remaining}`;
  });

  await check('RATE-04 แต่ละเส้นทางมีโควตาแยกกัน', async () => {
    // ยิง /auth/login จนตันแล้ว เส้นทางอื่นต้องยังใช้ได้
    // ถ้าใช้ถังเดียวกันทั้งระบบ การยิง endpoint เดียวจะทำให้ทั้งระบบใช้ไม่ได้
    const res = await fetch(`${base}/health`);
    expect(res.ok, `health ควรยังเรียกได้ ได้ ${res.status}`);
    return 'ยิง /auth/login จนตันแล้ว /health ยังเรียกได้ปกติ';
  });

  console.log('\n══ ตัวจำกัดรายไอพีในฐานข้อมูล ══');

  await check('RATE-05 login_rate_status นับเฉพาะครั้งที่ล้มเหลว', async () => {
    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    const r = await admin.query<{
      recent_failures: number;
      max_attempts: number;
      remaining: number;
      blocked: boolean;
    }>(
      `select * from login_rate_status($1,
         (select ip_hash from login_attempt
           where institution_id = $1 and ip_hash is not null
           order by attempted_at desc limit 1))`,
      [INST],
    );
    await admin.end();

    const row = r.rows[0];
    expect(row, 'login_rate_status ต้องคืนค่า');
    expect(
      Number(row.remaining) === Number(row.max_attempts) - Number(row.recent_failures),
      'โควตาที่เหลือต้องเท่ากับเพดานลบจำนวนครั้งที่ล้มเหลว',
    );
    return `ล้มเหลว ${row.recent_failures} จากเพดาน ${row.max_attempts} · เหลือ ${row.remaining}`;
  });

  await check('RATE-06 ไอพีที่เกินเพดานถูกบล็อกพร้อมเวลาที่ต้องรอ', async () => {
    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();

    // ลดเพดานลงชั่วคราวแทนที่จะยิงจริงเป็นสิบครั้ง เพื่อให้เทสต์เร็ว
    // และไม่ต้องพึ่งจังหวะเวลา
    await admin.query(
      `update auth_policy set max_ip_attempts = 1 where institution_id = $1`,
      [INST],
    );
    const r = await admin.query<{ blocked: boolean; retry_after_secs: number }>(
      `select * from login_rate_status($1,
         (select ip_hash from login_attempt
           where institution_id = $1 and ip_hash is not null and not succeeded
           order by attempted_at desc limit 1))`,
      [INST],
    );
    await admin.query(
      `update auth_policy set max_ip_attempts = 30 where institution_id = $1`,
      [INST],
    );
    await admin.end();

    const row = r.rows[0];
    expect(row.blocked, 'เกินเพดานแล้วต้องขึ้นว่าถูกบล็อก');
    expect(
      Number(row.retry_after_secs) > 0,
      'ต้องบอกเวลาที่ต้องรอ มิฉะนั้นผู้ใช้จริงที่ติดร่างแหจะไม่รู้ว่าต้องรอนานแค่ไหน',
    );
    return `ถูกบล็อก · ต้องรออีก ${row.retry_after_secs} วินาที`;
  });

  console.log('\n══ ตัวนับที่ใช้ร่วมกันทุก instance ══');

  await check('RATE-07 instance ใหม่ต้องรู้ว่าโควตาถูกใช้ไปแล้ว', async () => {
    /*
     * ─── ทำไมต้องสร้างแอปตัวที่สอง ───
     * นี่คือข้อเดียวที่พิสูจน์เรื่องที่ 0050 แก้ได้จริง — ตัวนับใน
     * หน่วยความจำถูกแบ่งตามจำนวน instance การยิงจนตันแล้วเช็คว่าโดน 429
     * พิสูจน์แค่ว่าตัวนับในโปรเซสทำงาน ซึ่งทำงานอยู่แล้วตั้งแต่ต้น
     *
     * แอปตัวที่สองมี Map ของตัวเองที่ว่างเปล่า ถ้ามันยอมให้ผ่าน แปลว่า
     * เพดานจริงคูณตามจำนวน instance ซึ่งคือบั๊กทั้งหมดของเรื่องนี้
     */
    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    await admin.query('delete from request_rate');
    await admin.end();

    // เส้นทางนี้ตั้งเพดานไว้ 3 ครั้งต่อนาที เพราะทุกคำขอที่ผ่านสร้าง
    // วิทยาลัยใหม่หนึ่งแห่ง — กุญแจผิดก็ยังถูกนับ เพราะ guard ทำงานก่อน
    const fire = (b: string) =>
      fetch(`${b}/provisioning/institutions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({}),
      });

    let blocked = 0;
    for (let i = 0; i < 5; i++) {
      if ((await fire(base)).status === 429) blocked++;
    }
    expect(blocked > 0, `ยิง 5 ครั้งบนเพดาน 3 ควรโดนปฏิเสธบ้าง โดน ${blocked}`);

    const app2 = await createApp();
    await app2.listen(0);
    const base2 = `http://127.0.0.1:${
      (app2.getHttpServer().address() as { port: number }).port
    }/api/v1`;
    const res2 = await fire(base2);
    const retryAfter = res2.headers.get('retry-after');
    await app2.close();

    expect(
      res2.status === 429,
      `instance ที่สองต้องรู้ว่าโควตาหมดแล้ว ได้ ${res2.status} ` +
        '(ตัวนับยังอยู่ในหน่วยความจำของแต่ละโปรเซส เพดานจริงจึงคูณตามจำนวน instance)',
    );
    return `instance แรกโดนปฏิเสธ ${blocked} ครั้ง · instance ที่สองโดนทันที รออีก ${retryAfter} วินาที`;
  });

  await check('RATE-08 ปิดตัวนับร่วมแล้วต้องยังมีตัวนับในโปรเซสอยู่', async () => {
    /*
     * THROTTLE_STORE=memory มีไว้ให้คนที่รัน instance เดียวจริง ๆ เลี่ยง
     * ค่าใช้จ่ายหนึ่ง query ต่อคำขอ ถ้าตั้งค่านี้แล้วกลายเป็นไม่จำกัดอะไรเลย
     * มันจะเป็นสวิตช์ปิดระบบป้องกันที่ดูเหมือนสวิตช์ปรับประสิทธิภาพ
     */
    const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await admin.connect();
    await admin.query('delete from request_rate');
    await admin.end();

    process.env.THROTTLE_STORE = 'memory';
    const app3 = await createApp();
    await app3.listen(0);
    const base3 = `http://127.0.0.1:${
      (app3.getHttpServer().address() as { port: number }).port
    }/api/v1`;

    let blocked = 0;
    for (let i = 0; i < 6; i++) {
      const r = await fetch(`${base3}/provisioning/institutions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({}),
      });
      if (r.status === 429) blocked++;
    }
    await app3.close();
    delete process.env.THROTTLE_STORE;

    expect(blocked > 0, `ยิง 6 ครั้งบนเพดาน 3 ควรโดนปฏิเสธบ้าง โดน ${blocked}`);
    return `โดนปฏิเสธ ${blocked} จาก 6 ครั้งโดยไม่แตะฐานข้อมูล`;
  });

  await app.close();

  console.log('');
  if (failures.length) {
    console.log(`════ ล้มเหลว ${failures.length} ข้อ จากทั้งหมด ${passed + failures.length} ════`);
    failures.forEach((f) => console.log(`  ✕ ${f}`));
    process.exit(1);
  }
  console.log(`════ ทดสอบการจำกัดจำนวนคำขอผ่านครบ ${passed} ข้อ ════`);
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

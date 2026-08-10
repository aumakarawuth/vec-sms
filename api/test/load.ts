/**
 * ทดสอบโหลด — รับพร้อมกันได้กี่คน และคอขวดอยู่ตรงไหน
 *
 *   npm run test:load
 *
 * ─── ทำไมต้องรัน API เป็นคนละโปรเซส ───
 * ชุดเทสต์อื่นเรียก createApp() ในโปรเซสเดียวกับตัวทดสอบ ซึ่งใช้ได้เพราะ
 * ยิงทีละคำขอ แต่การวัดโหลดแบบนั้นจะผิดทั้งหมด — ตัวยิงกับเซิร์ฟเวอร์
 * แย่ง event loop เดียวกัน เวลาที่วัดได้จะรวมเวลาที่ตัวยิงเองรอคิวอยู่
 * แล้วสรุปว่า "เซิร์ฟเวอร์ช้า" ทั้งที่เป็นเครื่องมือวัดเอง
 *
 * ─── ทำไมปิดตัวจำกัดคำขอ ───
 * ทุกคำขอมาจากไอพีเดียว เพดาน 300 ครั้งต่อนาทีจะตันในไม่กี่วินาที
 * แล้วสิ่งที่วัดได้จะเป็นความเร็วของการตอบ 429 ไม่ใช่ความเร็วของระบบ
 * (ตั้ง THROTTLE_ENABLED=false เฉพาะการวัดนี้เท่านั้น)
 *
 * ─── สิ่งที่การวัดนี้ตอบได้และตอบไม่ได้ ───
 * ตอบได้: รับคำขอพร้อมกันได้กี่คำขอต่อวินาที · หน่วงเท่าไร · คอขวดอยู่ที่
 *         CPU ของ Node หรือที่ฐานข้อมูล · เพิ่ม connection แล้วดีขึ้นไหม
 * ตอบไม่ได้: ผลของ**ปริมาณข้อมูล** ชุดข้อมูลทดสอบมีนักศึกษาไม่กี่คน
 *         แต่ทุก query กรองด้วยรหัสนักศึกษาคนเดียวผ่านดัชนีอยู่แล้ว และ
 *         ต้นทุนหลักของสคีมานี้คือ**การวางแผนคำสั่งที่กางนโยบาย RLS**
 *         ซึ่งไม่ขึ้นกับจำนวนแถว (วัดไว้แล้วตอนแก้ 0048 — planning 12 ms
 *         ต่อ execution 1.7 ms) ตัวเลขที่ได้จึงใช้ได้กับข้อมูลจริง
 *         ยกเว้นรายงานที่กวาดทั้งตาราง ซึ่งต้องวัดแยกด้วยข้อมูลจริง
 */
import 'reflect-metadata';
import { spawn, ChildProcess } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { resolve } from 'node:path';
import { Client } from 'pg';

const INST = '11111111-1111-1111-1111-111111111111';
const PORT = Number(process.env.LOAD_PORT ?? 3199);
const BASE = `http://127.0.0.1:${PORT}/api/v1`;

const SECONDS = Number(process.env.LOAD_SECONDS ?? 5);
const WARMUP_MS = Number(process.env.LOAD_WARMUP_MS ?? 1500);
const LEVELS = (process.env.LOAD_LEVELS ?? '1,4,16,64')
  .split(',')
  .map((n) => Number(n.trim()));

interface Sample {
  ms: number;
  status: number;
}

interface Result {
  name: string;
  conns: number;
  rps: number;
  p50: number;
  p95: number;
  p99: number;
  max: number;
  errors: Record<number, number>;
  total: number;
}

function pct(sorted: number[], p: number): number {
  if (!sorted.length) return 0;
  const i = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[i];
}

/** ยิงแบบวงปิด — worker แต่ละตัวยิงคำขอถัดไปทันทีที่คำขอก่อนหน้าจบ */
async function run(
  name: string,
  conns: number,
  fire: () => Promise<Response>,
): Promise<Result> {
  // อุ่นเครื่องก่อนโดยไม่นับ — คำขอแรก ๆ ต้องจ่ายค่า JIT ของ Node
  // ค่าเปิด connection ของ pool และการวางแผนคำสั่งครั้งแรกของทุก query
  const warmEnd = performance.now() + WARMUP_MS;
  await Promise.all(
    Array.from({ length: Math.min(conns, 4) }, async () => {
      while (performance.now() < warmEnd) await fire().then((r) => r.arrayBuffer());
    }),
  );

  const samples: Sample[] = [];
  const end = performance.now() + SECONDS * 1000;
  const started = performance.now();

  await Promise.all(
    Array.from({ length: conns }, async () => {
      while (performance.now() < end) {
        const t0 = performance.now();
        try {
          const res = await fire();
          await res.arrayBuffer(); // ต้องอ่าน body ให้จบ ไม่งั้นวัดแค่เวลาถึง header
          samples.push({ ms: performance.now() - t0, status: res.status });
        } catch {
          samples.push({ ms: performance.now() - t0, status: 0 });
        }
      }
    }),
  );

  const elapsed = (performance.now() - started) / 1000;
  const sorted = samples.map((s) => s.ms).sort((a, b) => a - b);
  const errors: Record<number, number> = {};
  for (const s of samples) {
    if (s.status < 200 || s.status >= 300) errors[s.status] = (errors[s.status] ?? 0) + 1;
  }

  return {
    name,
    conns,
    total: samples.length,
    rps: samples.length / elapsed,
    p50: pct(sorted, 50),
    p95: pct(sorted, 95),
    p99: pct(sorted, 99),
    max: sorted[sorted.length - 1] ?? 0,
    errors,
  };
}

function table(rows: Result[]): void {
  console.log(
    '  ' +
      'สถานการณ์'.padEnd(30) +
      'พร้อมกัน'.padStart(9) +
      'คำขอ/วินาที'.padStart(13) +
      'p50'.padStart(9) +
      'p95'.padStart(9) +
      'p99'.padStart(9) +
      '  ข้อผิดพลาด',
  );
  for (const r of rows) {
    const err = Object.entries(r.errors)
      .map(([s, n]) => `${s === '0' ? 'เชื่อมต่อไม่ได้' : s}×${n}`)
      .join(' ');
    console.log(
      '  ' +
        r.name.padEnd(30) +
        String(r.conns).padStart(9) +
        r.rps.toFixed(0).padStart(13) +
        `${r.p50.toFixed(1)}`.padStart(9) +
        `${r.p95.toFixed(1)}`.padStart(9) +
        `${r.p99.toFixed(1)}`.padStart(9) +
        (err ? `  ${err}` : ''),
    );
  }
}

async function waitForHealth(child: ChildProcess): Promise<void> {
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) {
      throw new Error(`API หยุดทำงานตั้งแต่ยังไม่เริ่มวัด (exit ${child.exitCode})`);
    }
    try {
      const r = await fetch(`${BASE}/health`);
      if (r.ok) return;
    } catch {
      /* ยังไม่ขึ้น */
    }
    await new Promise((r) => setTimeout(r, 300));
  }
  throw new Error('API ไม่ขึ้นภายใน 30 วินาที');
}

async function main() {
  const child = spawn(process.execPath, ['dist/main.js'], {
    // คอมไพล์แล้วไฟล์นี้อยู่ที่ api/dist-test/test/ จึงย้อนขึ้นสองชั้นถึง api/
    cwd: resolve(__dirname, '..', '..'),
    env: {
      ...process.env,
      PORT: String(PORT),
      THROTTLE_ENABLED: 'false',
      JOBS_ENABLED: 'false',
      DEV_AUTH: 'true',
      LOG_LEVEL: 'error',
    },
    stdio: ['ignore', 'ignore', 'pipe'],
  });
  let stderr = '';
  child.stderr?.on('data', (d) => (stderr += String(d)));

  try {
    await waitForHealth(child);
  } catch (e) {
    console.error((e as Error).message);
    if (stderr) console.error(stderr.slice(0, 2000));
    child.kill();
    process.exit(1);
  }

  // นักศึกษาจริงจากข้อมูลทดสอบ — ต้องเป็นคนที่มีผลการเรียนจริง
  // มิฉะนั้นจะวัดเส้นทาง "ไม่พบข้อมูล" ซึ่งเบากว่าของจริงมาก
  const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
  await admin.connect();
  const term = await admin.query<{ id: string }>(
    `select t.id from term t
       join class_section cs on cs.term_id = t.id
      where cs.institution_id = $1
      group by t.id order by count(*) desc limit 1`,
    [INST],
  );
  const stu = await admin.query<{ id: string; person_id: string; n: number }>(
    `select s.id, s.person_id, count(e.id)::int as n
       from student s
       left join enrollment e on e.student_id = s.id
      where s.institution_id = $1
      group by s.id, s.person_id
      order by n desc, s.id
      limit 1`,
    [INST],
  );
  await admin.end();

  if (!stu.rows.length) {
    // ข้อมูลนักศึกษาถูกสร้างโดยชุด e2e ไม่ใช่โดย prepare-db.sh
    // ถ้าวัดโหลดบนฐานข้อมูลเปล่า ทุกเส้นทางจะตอบ "ไม่พบข้อมูล" ซึ่งเบากว่า
    // ของจริงมาก แล้วตัวเลขที่ได้จะสวยโดยไม่มีความหมายเลย
    child.kill();
    throw new Error(
      'ไม่มีนักศึกษาในฐานข้อมูลทดสอบ — รัน `npm run test:e2e` ก่อนหนึ่งครั้ง ' +
        'เพื่อสร้างข้อมูลตัวอย่าง แล้วค่อยรัน `npm run test:load`',
    );
  }
  if (stu.rows[0].n === 0) {
    console.log('  ⚠ นักศึกษาที่เลือกยังไม่มีการลงทะเบียน ตัวเลขจะเบากว่าของจริง');
  }
  const { id: studentId, person_id: personId } = stu.rows[0];

  const tok = await fetch(`${BASE}/auth/dev-token`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ institutionId: INST, personId, role: 'student' }),
  });
  const { accessToken } = (await tok.json()) as { accessToken: string };
  const auth = { authorization: `Bearer ${accessToken}` };

  const get = (path: string) => () => fetch(`${BASE}${path}`, { headers: auth });

  console.log(`\n══ ทดสอบโหลด · ${SECONDS} วินาทีต่อระดับ · หน่วยเป็นมิลลิวินาที ══\n`);

  const results: Result[] = [];

  // 1. เพดานของกองซ้อน — ไม่แตะฐานข้อมูลเลย
  //    ใช้เทียบว่าเวลาที่เหลือหายไปกับฐานข้อมูลเท่าไร
  for (const c of LEVELS) {
    results.push(await run('health (ไม่แตะฐานข้อมูล)', c, () => fetch(`${BASE}/health`)));
  }

  // 2. อ่านข้อมูลตัวเองหนึ่งรายการ — auth + RLS + query เดียว
  for (const c of LEVELS) {
    results.push(await run('อ่านข้อมูลนักศึกษา', c, get(`/students/${studentId}`)));
  }

  // 3. เวลาเรียน — view ที่รวมหลายตาราง
  //    ต้องส่ง termId ด้วย มิฉะนั้นได้ 400 ทุกคำขอแล้ววัดความเร็วของการ
  //    ปฏิเสธแทนความเร็วของงานจริง (รอบแรกที่วัดพลาดแบบนี้จริง ๆ —
  //    ตัวเลขออกมา 3,700 คำขอ/วินาที ซึ่งเร็วกว่างานจริงสามเท่า)
  const termId = term.rows[0]?.id;
  if (termId) {
    for (const c of LEVELS) {
      results.push(
        await run('เวลาเรียน', c, get(`/students/${studentId}/attendance?termId=${termId}`)),
      );
    }
  }

  // 4. ตรวจจบ — หนักที่สุดในเส้นทางที่นักศึกษาเรียกเอง
  //    ช่วงประกาศผลคือช่วงที่ทุกคนกดพร้อมกัน
  for (const c of LEVELS) {
    results.push(await run('ตรวจเกณฑ์การจบ', c, get(`/students/${studentId}/graduation`)));
  }

  table(results);

  const health = results.filter((r) => r.name.startsWith('health'));
  const heavy = results.filter((r) => r.name === 'ตรวจเกณฑ์การจบ');
  const bestHealth = Math.max(...health.map((r) => r.rps));
  const bestHeavy = Math.max(...heavy.map((r) => r.rps));

  console.log('');
  console.log(`  เพดานของกองซ้อนโดยไม่แตะฐานข้อมูล : ${bestHealth.toFixed(0)} คำขอ/วินาที`);
  console.log(`  เส้นทางที่หนักที่สุดของนักศึกษา    : ${bestHeavy.toFixed(0)} คำขอ/วินาที`);
  console.log(
    `  สัดส่วนที่หายไปกับฐานข้อมูล        : ${(100 - (bestHeavy / bestHealth) * 100).toFixed(0)}%`,
  );

  const failures = results.filter((r) => Object.keys(r.errors).length > 0);
  if (failures.length) {
    console.log('');
    console.log('  ⚠ มีคำขอที่ไม่สำเร็จ — ตัวเลขข้างบนใช้ไม่ได้จนกว่าจะแก้');
  }

  child.kill();
  console.log('');
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

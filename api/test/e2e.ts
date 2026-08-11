/**
 * ทดสอบ API แบบ end-to-end กับฐานข้อมูลจริง
 *
 *   DATABASE_URL=... JWT_SECRET=... DEV_AUTH=true npx tsx test/e2e.ts
 *
 * ฐานข้อมูลต้องผ่าน migrations และ seed มาแล้ว และ DATABASE_URL ต้องชี้ไปที่
 * ผู้ใช้ที่ไม่ใช่ superuser มิฉะนั้นแอปจะปฏิเสธการเริ่มทำงาน ซึ่งเป็นพฤติกรรมที่ต้องการ
 */
import 'reflect-metadata';
import { Client } from 'pg';
import type { INestApplication } from '@nestjs/common';
import { createApp } from '../src/main';

// ชุดนี้ทดสอบตรรกะการยืนยันตัวตน จึงยิงเข้าสู่ระบบรัว ๆ โดยตั้งใจ
// การจำกัดจำนวนครั้งจะไปขวางจนเทสต์ล้มเหลวด้วยเหตุผลที่ไม่เกี่ยวกัน
// ตัวจำกัดมีชุดทดสอบของตัวเองที่ test/ratelimit.e2e.ts
process.env.THROTTLE_ENABLED = 'false';


const INST = '11111111-1111-1111-1111-111111111111';
const INST2 = '11111111-2222-2222-2222-111111111111';
const TERM1 = '33333333-3333-3333-3333-333333333331';
const TERM2 = '33333333-3333-3333-3333-333333333332';
const AY    = '22222222-2222-2222-2222-222222222222';
const CV = '77777777-7777-7777-7777-777777777767';
const COURSE = '99999999-0000-0000-0000-000000000001';
const POLICY = '55555555-5555-5555-5555-555555555555';

const F = {
  personStudent: '10000000-0000-0000-0000-000000000001',
  student: '10000000-0000-0000-0000-000000000011',
  personTeacher: '10000000-0000-0000-0000-000000000002',
  staff: '10000000-0000-0000-0000-000000000022',
  personOther: '10000000-0000-0000-0000-000000000003',
  studentOther: '10000000-0000-0000-0000-000000000033',
  section: '20000000-0000-0000-0000-000000000001',
  personAdmin2: '10000000-0000-0000-0000-0000000000a2',
  // สองคนนี้มีไว้ทดสอบการลงทะเบียนเป็นกลุ่มโดยเฉพาะ —
  // คนหนึ่งติดระงับ อีกคนไม่ติดอะไร เพื่อพิสูจน์ว่าคนที่ติดไม่ลากคนอื่นล้มไปด้วย
  personBulkOk: '10000000-0000-0000-0000-0000000000b1',
  studentBulkOk: '10000000-0000-0000-0000-0000000000b2',
  personBulkHeld: '10000000-0000-0000-0000-0000000000b3',
  studentBulkHeld: '10000000-0000-0000-0000-0000000000b4',
  // คนนี้มีผลการเรียนที่ยังไม่ได้หน่วยกิต ใช้ทดสอบรอบสอบซ่อมโดยเฉพาะ
  personRegrade: '10000000-0000-0000-0000-0000000000c1',
  studentRegrade: '10000000-0000-0000-0000-0000000000c2',
  // ห้องเป็นข้อมูลจริงตั้งแต่ 0034 ไม่ใช่ข้อความอิสระ
  room: '30000000-0000-0000-0000-0000000000e1',
  roomLecture: '30000000-0000-0000-0000-0000000000e2',
};

let passed = 0;
const failures: string[] = [];
/** ref2 ของใบแจ้งหนี้ เก็บไว้ตอน API-13 เพื่อใช้ทดสอบการกระทบยอด */
let REF2 = '';

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

// ── เตรียมข้อมูลทดสอบด้วยสิทธิ์เจ้าของฐานข้อมูล ───────────────────
async function seedFixtures() {
  const admin = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
  await admin.connect();
  await admin.query('begin');

  await admin.query(
    `insert into institution (id, code, name_th)
     values ($1, '1300000099', 'วิทยาลัยอื่นสำหรับทดสอบการแยกข้อมูล')
     on conflict (id) do nothing`,
    [INST2],
  );

  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th) values
       ($1, $5, 'ปิยะพงศ์', 'ศรีสุข'),
       ($2, $5, 'สมชาย', 'ใจงาม'),
       ($3, $6, 'นักศึกษาวิทยาลัยอื่น', 'ทดสอบ'),
       ($4, $6, 'ผู้ดูแลวิทยาลัยอื่น', 'ทดสอบ')
     on conflict (id) do nothing`,
    [F.personStudent, F.personTeacher, F.personOther, F.personAdmin2, INST, INST2],
  );

  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be)
     values ($1, $2, $3, '69201010001', 2569) on conflict (id) do nothing`,
    [F.student, INST, F.personStudent],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be)
     values ($1, $2, $3, '69999990001', 2569) on conflict (id) do nothing`,
    [F.studentOther, INST2, F.personOther],
  );
  await admin.query(
    `insert into staff (id, institution_id, person_id, staff_code, is_teacher)
     values ($1, $2, $3, 'T-9001', true) on conflict (id) do nothing`,
    [F.staff, INST, F.personTeacher],
  );
  await admin.query(
    `insert into student_curriculum (student_id, curriculum_version_id)
     values ($1, $2) on conflict do nothing`,
    [F.student, CV],
  );

  // ── ข้อมูลสำหรับทดสอบการลงทะเบียนเป็นกลุ่ม ──────────────────────
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th) values
       ($1, $3, 'ณัฐวุฒิ', 'พร้อมลง'),
       ($2, $3, 'กมลชนก', 'ค้างค่าเทอม')
     on conflict (id) do nothing`,
    [F.personBulkOk, F.personBulkHeld, INST],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be) values
       ($1, $3, $4, '69201010777', 2569),
       ($2, $3, $5, '69201010778', 2569)
     on conflict (id) do nothing`,
    [F.studentBulkOk, F.studentBulkHeld, INST, F.personBulkOk, F.personBulkHeld],
  );
  await admin.query(
    `insert into student_curriculum (student_id, curriculum_version_id) values ($1, $3), ($2, $3)
     on conflict do nothing`,
    [F.studentBulkOk, F.studentBulkHeld, CV],
  );
  // คนที่สองค้างค่าเทอม จึงถูกงานการเงินระงับการลงทะเบียนไว้
  await admin.query(
    `insert into registration_hold
       (student_id, kind, reason, blocks_registration, placed_by)
     values ($1, 'finance', 'ค้างชำระค่าเทอมภาคเรียนที่แล้ว', true, $2)
     on conflict do nothing`,
    [F.studentBulkHeld, F.personTeacher],
  );

  await admin.query(
    `insert into room (id, institution_id, code, name_th, kind, capacity) values
       ($1, $3, 'W-03', 'โรงฝึกงานช่างยนต์ 3', 'workshop', 30),
       ($2, $3, '401',  'ห้องบรรยาย 401',      'classroom', 45)
     on conflict (id) do nothing`,
    [F.room, F.roomLecture, INST],
  );

  await admin.query(
    `insert into class_section
       (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
        teacher_id, attendance_policy_id, planned_periods, capacity, room_id)
     values ($1, $2, $3, $4, $5, '9/1', $6, $7, 40, 30, $8)
     on conflict (id) do nothing`,
    [F.section, INST, TERM1, COURSE, CV, F.staff, POLICY, F.room],
  );
  await admin.query(
    `insert into section_timeslot (class_section_id, day_of_week, period_from, period_to, room_id)
     values ($1, 3, 1, 2, $2)
     on conflict do nothing`,
    [F.section, F.room],
  );

  // แพ็กเกจเป็นรายการสินค้าของผู้ให้บริการ ไม่ได้มากับ seed ของวิทยาลัย
  await admin.query(
    `insert into plan (code, name_th, max_students, max_staff, price_per_year,
                       enforcement, grace_percent) values
       ('SMALL-SOFT', 'เล็ก (เตือน)', 200, 20, 30000, 'soft', 10),
       ('UNLIMITED',  'ไม่จำกัด',     null, null, 200000, 'hard', 0)
     on conflict (code) do nothing`,
  );

  // นโยบายตารางสอน — ตัวเสนอคาบว่างและตัวจัดอัตโนมัติอ่านจากตรงนี้
  await admin.query(
    `insert into timetable_policy
       (institution_id, periods_per_day, days_per_week, lunch_period, max_consecutive)
     values ($1, 8, 5, 5, 4) on conflict (institution_id) do nothing`,
    [INST],
  );

  // ห้องเดียวกันในภาคเรียนที่ 2 — ปลายทางของการคัดลอกสมุดคะแนนข้ามภาค
  // ถ้าไม่มีห้องนี้ เทสต์การคัดลอกจะผ่านโดยไม่ได้คัดลอกอะไรเลย
  await admin.query(
    `insert into class_section
       (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
        teacher_id, attendance_policy_id, planned_periods, capacity)
     values ('20000000-0000-0000-0000-0000000000d0', $1, $2, $3, $4, '9/1', $5, $6, 40, 30)
     on conflict (id) do nothing`,
    [INST, TERM2, COURSE, CV, F.staff, POLICY],
  );

  // ── นักศึกษาที่สอบตก ใช้ทดสอบรอบสอบซ่อม ────────────────────────
  // ต้องมี enrollment_result จริง เพราะสิทธิ์เข้ารอบคำนวณจากผลการเรียน
  // ไม่ใช่จากรายชื่อที่ใครพิมพ์ไว้
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th)
     values ($1, $2, 'ศักดิ์ดา', 'สอบซ่อม') on conflict (id) do nothing`,
    [F.personRegrade, INST],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be)
     values ($1, $2, $3, '69201010779', 2569) on conflict (id) do nothing`,
    [F.studentRegrade, INST, F.personRegrade],
  );
  await admin.query(
    `insert into student_curriculum (student_id, curriculum_version_id)
     values ($1, $2) on conflict do nothing`,
    [F.studentRegrade, CV],
  );
  // ห้องแยกต่างหาก — ถ้าใส่คนนี้ลงห้องเดียวกับ F.section เทสต์การเช็คชื่อ
  // และเวลาเรียนที่นับจำนวนคนในห้องจะเพี้ยนไปด้วย
  await admin.query(
    `insert into class_section
       (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
        teacher_id, attendance_policy_id, planned_periods, capacity)
     values ('20000000-0000-0000-0000-0000000000c0', $1, $2, $3, $4, '9/2', $5, $6, 40, 30)
     on conflict (id) do nothing`,
    [INST, TERM1, COURSE, CV, F.staff, POLICY],
  );
  await admin.query(
    `insert into enrollment (id, student_id, class_section_id, term_id, registered_by)
     values ('20000000-0000-0000-0000-0000000000c3', $1,
             '20000000-0000-0000-0000-0000000000c0', $2, $3)
     on conflict (id) do nothing`,
    [F.studentRegrade, TERM1, F.personTeacher],
  );

  // รอบส่งเกรดต้องล็อกแล้ว มิฉะนั้นยื่นคำร้องแก้เกรดไม่ได้ — เป็นกฎจริง
  // (ก่อนล็อกให้ครูส่งใหม่ ไม่ใช่ยื่นคำร้อง) รอบสอบซ่อมจึงเกิดขึ้นได้
  // หลังปิดเกรดแล้วเท่านั้น ซึ่งตรงกับความเป็นจริง
  await admin.query(
    `insert into grade_submission
       (id, class_section_id, term_id, stage, submitted_by, submitted_at, locked_at)
     values ('20000000-0000-0000-0000-0000000000c4',
             '20000000-0000-0000-0000-0000000000c0', $1, 'locked', $2, now(), now())
     on conflict (id) do nothing`,
    [TERM1, F.personTeacher],
  );
  await admin.query(
    `insert into enrollment_result
       (enrollment_id, submission_id, revision, raw_score, attendance_pct,
        grade_symbol_id, grade_point, credits_earned, computed_by, reason)
     select '20000000-0000-0000-0000-0000000000c3',
            '20000000-0000-0000-0000-0000000000c4', 1, 32.0, 71.0, gs.id,
            0.0, 0.0, $1, 'ผลการเรียนตั้งต้นสำหรับทดสอบรอบสอบซ่อม'
       from grade_symbol gs
       join grade_scheme sch on sch.id = gs.grade_scheme_id
      where sch.institution_id = $2 and gs.symbol = '0'
      limit 1
     on conflict do nothing`,
    [F.personTeacher, INST],
  );

  await admin.query('commit');

  // สร้างคาบเรียนจากตารางสอน แล้วดึงคาบแรกมาใช้ทดสอบการเช็คชื่อ
  await admin.query(`select generate_class_meetings($1)`, [F.section]);
  const meeting = await admin.query<{ id: string }>(
    `select id from class_meeting where class_section_id = $1 order by meets_on limit 1`,
    [F.section],
  );

  // รหัสของสัญลักษณ์ผลการเรียนถูกสร้างตอน seed จึงต้องหาเอา ไม่ใช่ค่าคงที่
  const passSymbol = await admin.query<{ id: string }>(
    `select gs.id from grade_symbol gs
       join grade_scheme sch on sch.id = gs.grade_scheme_id
      where sch.institution_id = $1 and gs.symbol = '1.0' limit 1`,
    [INST],
  );

  await admin.end();
  return { meetingId: meeting.rows[0].id, passSymbolId: passSymbol.rows[0].id };
}

async function token(app: INestApplication, base: string, personId: string, role: string, inst = INST) {
  const res = await fetch(`${base}/auth/dev-token`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ institutionId: inst, personId, role }),
  });
  const body = (await res.json()) as { accessToken?: string };
  expect(res.status === 201 || res.status === 200, `ออก token ไม่สำเร็จ: ${JSON.stringify(body)}`);
  expect(body.accessToken, 'ไม่ได้รับ accessToken');
  return body.accessToken as string;
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
    let body: any = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = text; }
    return { status: res.status, body };
  };
}

async function main() {
  console.log('▸ เตรียมข้อมูลทดสอบ');
  const { meetingId, passSymbolId } = await seedFixtures();

  console.log('▸ เริ่ม API');
  const app = await createApp();
  await app.listen(0);
  const url = await app.getUrl();
  const base = `${url.replace('[::1]', '127.0.0.1')}/api/v1`;

  const anon = api(base);
  const tRegistrar = await token(app, base, F.personTeacher, 'registrar');
  const tTeacher = await token(app, base, F.personTeacher, 'teacher');
  const tStudent = await token(app, base, F.personStudent, 'student');
  const tFinance = await token(app, base, F.personTeacher, 'finance');
  const tOtherInst = await token(app, base, F.personAdmin2, 'registrar', INST2);
  const tDirector = await token(app, base, F.personTeacher, 'director');

  const registrar = api(base, tRegistrar);
  const teacher = api(base, tTeacher);
  const student = api(base, tStudent);
  const finance = api(base, tFinance);
  const other = api(base, tOtherInst);
  const director = api(base, tDirector);

  console.log('');
  console.log('══ ความปลอดภัยและบริบท ══');

  await check('API-01 health เปิดสาธารณะได้', async () => {
    const r = await anon('/health');
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.database === 'up', 'ฐานข้อมูลไม่พร้อม');
    return r.body.serverVersion;
  });

  await check('API-02 ไม่มี token ต้องถูกปฏิเสธ', async () => {
    const r = await anon('/students');
    expect(r.status === 401, `ควรได้ 401 ได้ ${r.status}`);
    return r.body.message;
  });

  await check('API-03 token ปลอมต้องถูกปฏิเสธ', async () => {
    const r = await api(base, 'not-a-valid-token')('/students');
    expect(r.status === 401, `ควรได้ 401 ได้ ${r.status}`);
  });

  await check('API-04 แยกข้อมูลข้ามสถานศึกษา', async () => {
    const mine = await registrar('/students');
    const theirs = await other('/students');
    expect(mine.status === 200 && theirs.status === 200, 'เรียกไม่สำเร็จ');
    expect(mine.body.length >= 1, 'วิทยาลัยตัวเองควรเห็นนักศึกษาของตน');
    const leaked = theirs.body.filter((s: any) => s.student_code === '69201010001');
    expect(leaked.length === 0, `วิทยาลัยอื่นเห็นนักศึกษาที่ไม่ใช่ของตน ${leaked.length} คน`);
    return `ของตน ${mine.body.length} คน · วิทยาลัยอื่นเห็น ${theirs.body.length} คน`;
  });

  await check('API-05 บทบาทที่ไม่มีอำนาจยกเว้นกฎไม่ได้', async () => {
    const r = await teacher('/registration/overrides', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, termId: TERM1, code: 'CREDIT_MAX',
        reason: 'ทดสอบ', approvedBy: F.staff,
      }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
    return r.body.message;
  });

  console.log('');
  console.log('══ ทะเบียนและการลงทะเบียน ══');

  await check('API-06 ตรวจเงื่อนไขคืนปัญหาเป็นภาษาไทย', async () => {
    const r = await registrar('/registration/check', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, termId: TERM1, sectionIds: [F.section] }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Array.isArray(r.body.problems), 'ไม่ได้รายการปัญหา');
    expect(typeof r.body.canRegister === 'boolean', 'ไม่มีข้อสรุปว่าลงได้หรือไม่');
    return `ลงได้=${r.body.canRegister} block=${r.body.blockingCount} warn=${r.body.warningCount}`;
  });

  await check('API-07 ลงทะเบียนสำเร็จ', async () => {
    const r = await registrar('/registration/register', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, termId: TERM1, sectionIds: [F.section] }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.registered === 1, `ควรลงได้ 1 รายวิชา ได้ ${r.body.registered}`);
    return `ลงทะเบียน ${r.body.registered} รายวิชา`;
  });

  await check('API-08 ตรวจจบเรียกได้ทุกเมื่อ', async () => {
    const r = await registrar(`/students/${F.student}/graduation`);
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.length === 10, `ควรได้กฎ 10 ข้อ ได้ ${r.body.length}`);
    return `กฎ ${r.body.length} ข้อ`;
  });

  console.log('');
  console.log('══ การเช็คชื่อและกฎเวลาเรียน ══');

  let enrollmentId = '';

  await check('API-09 รายชื่อสำหรับหน้าเช็คชื่อ', async () => {
    const r = await teacher(`/attendance/meetings/${meetingId}/roster`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.students.length === 1, `ควรมี 1 คน ได้ ${r.body.students.length}`);
    enrollmentId = r.body.students[0].enrollment_id;
    return `${r.body.meeting.course_name} คาบ ${r.body.meeting.period_from}–${r.body.meeting.period_to}`;
  });

  await check('API-10 บันทึกการเช็คชื่อและปิดคาบ', async () => {
    const r = await teacher(`/attendance/meetings/${meetingId}`, {
      method: 'POST',
      body: JSON.stringify({
        records: [{ enrollmentId, status: 'absent', capturedAt: new Date().toISOString() }],
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.saved === 1, `ควรบันทึก 1 รายการ ได้ ${r.body.saved}`);
  });

  await check('API-11 คำนวณเวลาเรียนและจำนวนคาบที่ขาดได้อีก', async () => {
    const r = await teacher(`/attendance/enrollments/${enrollmentId}`);
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.periods_held === '2', `ควรสอนไปแล้ว 2 คาบ ได้ ${r.body.periods_held}`);
    expect(Number(r.body.absences_left) > 0, 'ควรยังขาดได้อีก');
    return `เรียนไป ${r.body.periods_held} คาบ ขาดได้อีก ${r.body.absences_left} คาบ สถานะ ${r.body.attendance_state}`;
  });

  await check('API-11ก นักศึกษาแก้เวลาเรียนของตัวเองไม่ได้', async () => {
    /*
     * ─── ช่องนี้เคยเปิดอยู่จริง ───
     * AttendanceController เป็น controller เดียวที่ไม่มี @Roles และนโยบาย RLS
     * attendance_scope มีแต่ `using` ไม่มี `with check` ซึ่ง PostgreSQL จะเอา
     * `using` มาใช้เป็น `with check` ให้เอง สิทธิ์ "อ่านของตัวเอง" จึงกลายเป็น
     * สิทธิ์ "เขียนของตัวเอง"
     *
     * ผลคือนักศึกษาเปลี่ยน "ขาดเรียน" เป็น "มาเรียน" ได้เอง แล้วหา meeting_id
     * ครบทุกคาบจาก /students/:id/schedule ของตัวเอง — กฎเวลาเรียน 80%
     * จึงไม่มีผลกับใครที่รู้วิธีนี้เลย และไม่มีอาการอะไรให้เห็นจากภายนอก
     *
     * ปิดสองชั้น: @Roles ที่ controller (migration 0039 ปิดที่ฐานข้อมูล)
     * เทสต์นี้ยิงจากมุมของนักศึกษาจริง จึงจับได้ทั้งกรณีที่ชั้นใดชั้นหนึ่งหลุด
     */
    const before = await teacher(`/attendance/enrollments/${enrollmentId}`);

    const write = await student(`/attendance/meetings/${meetingId}`, {
      method: 'POST',
      body: JSON.stringify({ records: [{ enrollmentId, status: 'present' }] }),
    });
    expect(write.status === 403,
      `นักศึกษาต้องเขียนการเช็คชื่อไม่ได้ ได้ ${write.status}: ${JSON.stringify(write.body)}`);

    // รายชื่อทั้งห้องเป็นหน้าจอของครู ไม่ใช่ของนักศึกษา
    const roster = await student(`/attendance/meetings/${meetingId}/roster`);
    expect(roster.status === 403,
      `นักศึกษาต้องเปิดรายชื่อทั้งห้องไม่ได้ ได้ ${roster.status}`);

    // แต่ต้องยังดูเวลาเรียนของตัวเองได้ — ถ้าปิดหมดคือหน้าจอนักศึกษาใช้ไม่ได้
    const own = await student(`/attendance/enrollments/${enrollmentId}`);
    expect(own.status === 200, `นักศึกษาต้องดูเวลาเรียนของตัวเองได้ ได้ ${own.status}`);

    const after = await teacher(`/attendance/enrollments/${enrollmentId}`);
    expect(after.body.periods_credited === before.body.periods_credited,
      `เวลาเรียนต้องไม่ขยับ ก่อน ${before.body.periods_credited} หลัง ${after.body.periods_credited}`);

    return `เขียนไม่ได้ · เปิดรายชื่อทั้งห้องไม่ได้ · ดูของตัวเองได้ (สถานะ ${own.body.attendance_state})`;
  });

  await check('API-12 นักศึกษาเห็นเวลาเรียนของตัวเองในแอป', async () => {
    const r = await student(`/students/${F.student}/attendance?termId=${TERM1}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.length === 1, `ควรเห็น 1 รายวิชา ได้ ${r.body.length}`);
    return `${r.body[0].name_th} ขาดได้อีก ${r.body[0].absences_left} คาบ`;
  });

  console.log('');
  console.log('══ การเงิน ══');

  let invoiceTotal = 0;

  await check('API-13 ออกใบแจ้งหนี้พร้อมแบ่งงวด', async () => {
    const r = await finance('/finance/invoices', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, termId: TERM1, installments: 3 }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    invoiceTotal = Number(r.body.total);
    expect(invoiceTotal === 12600, `ยอดควรเป็น 12,600 ได้ ${invoiceTotal}`);
    expect(r.body.installments.length === 3, `ควรมี 3 งวด ได้ ${r.body.installments.length}`);
    expect(r.body.ref2 && /^\d+$/.test(r.body.ref2), 'ต้องมี Reference 2 เป็นตัวเลขล้วนสำหรับพร้อมเพย์');
    REF2 = r.body.ref2;
    return `${r.body.invoice_no} ยอด ${invoiceTotal} บาท ref2=${r.body.ref2}`;
  });

  await check('API-14 บทบาทที่ไม่ใช่การเงินออกใบแจ้งหนี้ไม่ได้', async () => {
    const r = await teacher('/finance/invoices', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, termId: TERM1 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-15 รับชำระแล้วตัดยอดทันที', async () => {
    const r = await finance('/finance/payments', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, amount: 4200, method: 'promptpay', receiptNo: 'E2E-0001',
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Number(r.body.overpaid) === 0, 'ไม่ควรมีเงินเหลือ');
    expect(Number(r.body.balance.outstanding) === 8400, `ควรเหลือค้าง 8,400 ได้ ${r.body.balance.outstanding}`);
    return `ค้างอยู่ ${r.body.balance.outstanding} บาท`;
  });

  await check('API-16 กระทบยอดอัตโนมัติจาก Reference 2', async () => {
    expect(REF2, 'ยังไม่มี ref2 จากใบแจ้งหนี้');

    const r0 = await finance('/finance/bank-transactions', {
      method: 'POST',
      body: JSON.stringify({
        transactions: [
          { postedAt: new Date().toISOString(), amount: 4200,
            counterparty: 'น.ส. สมหญิง ศรีสุข', bankRef: 'E2E-BK-1', ref2: REF2 },
          { postedAt: new Date().toISOString(), amount: 13.5,
            counterparty: 'ไม่ทราบผู้โอน', bankRef: 'E2E-BK-2' },
        ],
      }),
    });
    expect(r0.status === 201 || r0.status === 200, `นำเข้าไม่สำเร็จ: ${JSON.stringify(r0.body)}`);

    const r = await finance('/finance/reconcile', { method: 'POST' });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.autoMatched >= 1, `ควรจับคู่เองอย่างน้อย 1 รายการ ได้ ${r.body.autoMatched}`);
    return `จับคู่เอง ${r.body.autoMatched} · ค้างให้คนดู ${r.body.unmatched}`;
  });

  await check('API-17 รายการที่จับคู่ไม่ได้ขึ้นให้เจ้าหน้าที่', async () => {
    const r = await finance('/finance/reconcile/pending');
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.length >= 1, 'ควรมีรายการค้างอย่างน้อย 1 รายการ');
    return `${r.body.length} รายการรอเจ้าหน้าที่ตัดสิน`;
  });

  console.log('');
  console.log('══ เตือนก่อนออกกลางคัน ══');

  await check('API-18 คำนวณคะแนนความเสี่ยงทั้งสถานศึกษา', async () => {
    const r = await director('/risk/compute', {
      method: 'POST',
      body: JSON.stringify({ termId: TERM1 }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.evaluated >= 1, 'ควรประเมินอย่างน้อย 1 คน');
    return `ประเมิน ${r.body.evaluated} คน`;
  });

  await check('API-19 รายชื่อกลุ่มเสี่ยงพร้อมสัญญาณภาษาไทย', async () => {
    const r = await teacher(`/risk/students?termId=${TERM1}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    // ตั้งแต่เพิ่มการแบ่งหน้า endpoint นี้คืน { items, limit, offset, hasMore }
    // แทน array เปล่า เพราะการคืนทุกแถวโดยไม่มีเพดานเป็นทั้งปัญหาเรื่องขนาด
    // และเป็นช่องทำให้ระบบล่มด้วยคำขอเดียว
    expect(Array.isArray(r.body.items), 'ต้องคืนเป็นหน้าที่มี items');
    expect(r.body.limit <= 200, 'เพดานต่อหน้าต้องไม่เกิน 200');
    const target = r.body.items.find((s: any) => s.student_code === '69201010001');
    expect(target, 'ไม่พบนักศึกษาที่สร้างไว้ในรายชื่อกลุ่มเสี่ยง');
    expect(typeof target.signals_th === 'string' && target.signals_th.length > 0,
      'สัญญาณต้องเป็นข้อความไทยที่อ่านออกเสียงได้');
    return `${target.full_name} คะแนน ${target.score} (${target.band}) — ${target.signals_th}`;
  });

  await check('API-20 มูลค่ารายได้ที่เสี่ยงจะสูญเป็นตัวเงิน', async () => {
    const r = await director(`/risk/revenue-at-risk?termId=${TERM1}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    if (r.body.length === 0) return 'ไม่มีนักศึกษาระดับส้มหรือแดงในภาคนี้';
    return r.body
      .map((x: any) => `${x.band} ${x.students} คน ${Number(x.revenue_at_risk).toLocaleString('th-TH')} บาท`)
      .join(' · ');
  });

  await check('API-21 ครูผู้สอนดูรายได้ที่เสี่ยงไม่ได้', async () => {
    const r = await teacher(`/risk/revenue-at-risk?termId=${TERM1}`);
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ ข้อมูลสำหรับแอปมือถือ ══');

  await check('API-24 ตารางเรียนของวันที่ระบุ', async () => {
    const meets = await registrar(`/attendance/meetings/${meetingId}/roster`);
    const on = String(meets.body.meeting.meets_on);
    // ชนิด date ต้องส่งกลับมาเป็น YYYY-MM-DD ตรง ๆ ไม่ใช่ ISO timestamp
    // มิฉะนั้นเขตเวลา UTC+7 จะทำให้วันเลื่อนไปหนึ่งวัน
    expect(/^\d{4}-\d{2}-\d{2}$/.test(on), `meets_on ควรเป็น YYYY-MM-DD ได้ "${on}"`);
    const r = await student(`/students/${F.student}/schedule?date=${on}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.length === 1, `ควรมี 1 คาบ ได้ ${r.body.length}`);
    return `${on} · ${r.body[0].course_name} คาบ ${r.body[0].period_from}–${r.body[0].period_to}`;
  });

  await check('API-25 วันที่ผิดรูปแบบถูกปฏิเสธ', async () => {
    const r = await student(`/students/${F.student}/schedule?date=8%2F8%2F2569`);
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await check('API-26 ใบแจ้งหนี้พร้อมงวดสำหรับแอป', async () => {
    const r = await student(`/students/${F.student}/invoices`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.length === 1, `ควรมี 1 ใบ ได้ ${r.body.length}`);
    const inv = r.body[0];
    expect(inv.installments.length === 3, `ควรมี 3 งวด ได้ ${inv.installments.length}`);
    expect(inv.ref1 && inv.ref2, 'ต้องมีเลขอ้างอิงสำหรับพร้อมเพย์');
    return `${inv.invoice_no} ค้าง ${inv.outstanding} บาท · ${inv.installments.length} งวด`;
  });

  console.log('');
  console.log('══ งานทะเบียนและงานวิชาการ ══');

  await check('API-27 ลงทะเบียนทั้งห้อง คนที่ติดระงับไม่ลากคนอื่นล้ม', async () => {
    const r = await registrar('/registration/register-bulk', {
      method: 'POST',
      body: JSON.stringify({
        studentIds: [F.studentBulkHeld, F.studentBulkOk],
        termId: TERM1,
        sectionIds: [F.section],
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.requested === 2, `ควรขอ 2 คน ได้ ${r.body.requested}`);
    expect(r.body.succeeded === 1 && r.body.blocked === 1,
      `ควรผ่าน 1 ติด 1 ได้ ผ่าน ${r.body.succeeded} ติด ${r.body.blocked}`);

    const held = r.body.results.find((x: any) => x.studentId === F.studentBulkHeld);
    const ok = r.body.results.find((x: any) => x.studentId === F.studentBulkOk);
    expect(held.registered === 0, 'คนที่ติดระงับต้องไม่ถูกลงทะเบียน');
    expect(held.blockers.length > 0 && /[ก-๙]/.test(held.blockers[0]),
      'เหตุผลที่ติดต้องเป็นข้อความไทยที่ผู้ใช้อ่านรู้เรื่อง');
    expect(ok.registered === 1, `คนที่ไม่ติดต้องลงได้ 1 วิชา ได้ ${ok.registered}`);
    return `ติด: ${held.blockers[0]}`;
  });

  await check('API-28 คนที่ผ่านถูกบันทึกจริง ไม่ถูก rollback ไปด้วย', async () => {
    // ข้อนี้คือหัวใจของ API-27 — ถ้าฟังก์ชันในฐานข้อมูล raise เมื่อเจอคนติด
    // เงื่อนไข transaction จะถูก rollback ทั้งก้อน แล้วคนที่ผ่านจะหายไปเงียบ ๆ
    // โดยที่คำตอบยังบอกว่าสำเร็จ ซึ่งเป็นการพังแบบที่จับได้ยากที่สุด
    // ลงซ้ำคนเดิมวิชาเดิม — ถ้าแถวแรกยังอยู่ จะได้ registered = 0 โดยไม่ติดอะไร
    // (on conflict do nothing) แต่ถ้าแถวแรกหายไปเพราะถูก rollback จะได้ 1 อีกครั้ง
    const r = await registrar('/registration/register-bulk', {
      method: 'POST',
      body: JSON.stringify({
        studentIds: [F.studentBulkOk], termId: TERM1, sectionIds: [F.section],
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    const again = r.body.results[0];
    expect(again.blockers.length === 0, `ไม่ควรติดอะไร ติด: ${again.blockers.join(' / ')}`);
    expect(again.registered === 0,
      `แถวแรกต้องยังอยู่ จึงต้องลงเพิ่มไม่ได้อีก แต่ลงได้ ${again.registered} วิชา`);
    return 'ลงซ้ำได้ 0 วิชา แปลว่าแถวจากรอบแรกถูกบันทึกไว้จริง';
  });

  await check('API-29 ครูลงทะเบียนแทนทั้งห้องไม่ได้', async () => {
    const r = await teacher('/registration/register-bulk', {
      method: 'POST',
      body: JSON.stringify({
        studentIds: [F.studentBulkOk], termId: TERM1, sectionIds: [F.section],
      }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-30 ยิงทั้งวิทยาลัยมาในคำขอเดียวถูกปฏิเสธ', async () => {
    // เพดานนี้กันคำขอที่ล็อกตาราง enrollment ค้างไว้จนทั้งวิทยาลัยลงทะเบียนไม่ได้
    const many = Array.from({ length: 201 }, (_, i) =>
      `10000000-0000-0000-0000-${String(i).padStart(12, '0')}`);
    const r = await registrar('/registration/register-bulk', {
      method: 'POST',
      body: JSON.stringify({ studentIds: many, termId: TERM1, sectionIds: [F.section] }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await check('API-31 ความคืบหน้าการตัดเกรดรายครู', async () => {
    const r = await registrar(`/gradebook/terms/${TERM1}/cutoff-progress`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.sectionsTotal >= 1, 'ต้องนับห้องเรียนที่มีครูผู้สอนได้อย่างน้อยหนึ่งห้อง');
    expect(r.body.submitted + r.body.remaining === r.body.sectionsTotal,
      'ส่งแล้วบวกค้างต้องเท่ากับทั้งหมด');
    const t = r.body.teachers[0];
    expect(t.teacher_name && t.teacher_name.trim().length > 0,
      'ชื่อครูต้องไม่ว่าง — ต่อสตริงกับ null ได้ null ทั้งก้อน');
    return `${t.teacher_name} สอน ${t.sections_total} ส่งแล้ว ${t.submitted} เหลือ ${t.remaining}`;
  });

  await check('API-32 ความคืบหน้าการลงทะเบียนรายหลักสูตร แยกรอบ', async () => {
    const r = await registrar(`/registration/progress?termId=${TERM1}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.length >= 1, 'ต้องมีอย่างน้อยหนึ่งหลักสูตร');
    const c = r.body[0];
    expect(c.shift, 'ต้องบอกรอบเรียนได้ ไม่ใช่ต้องไปแกะจากชื่อหลักสูตร');
    expect(Number(c.students_total) >= Number(c.students_registered),
      'คนที่ลงทะเบียนต้องไม่มากกว่าคนทั้งหมดในหลักสูตร');
    return `${c.curriculum_name} (${c.shift}) ${c.students_registered}/${c.students_total} = ${c.pct}%`;
  });

  await check('API-33 วิทยาลัยอื่นเปิดรายงานของเราไม่เห็นข้อมูลเลย', async () => {
    const a = await other(`/registration/progress?termId=${TERM1}`);
    expect(a.status === 200, `ได้ ${a.status}`);
    expect(a.body.length === 0, `ควรไม่เห็นอะไรเลย เห็น ${a.body.length} หลักสูตร`);
    const b = await other(`/gradebook/terms/${TERM1}/cutoff-progress`);
    expect(b.status === 200, `ได้ ${b.status}`);
    expect(b.body.sectionsTotal === 0, `ควรนับได้ 0 ห้อง ได้ ${b.body.sectionsTotal}`);
  });

  await check('API-34 termId ผิดรูปแบบถูกปฏิเสธก่อนถึงฐานข้อมูล', async () => {
    const r = await registrar('/registration/progress?termId=1%20or%201%3D1');
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ เอกสารและรายงานหน่วยงานรัฐ ══');

  let docId = '';
  let docNo = '';
  let approvalId = '';

  await check('API-35 ออกระเบียนแสดงผลการเรียนแล้วได้เลขที่', async () => {
    const r = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript', yearBe: 2569 }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.doc_no, 'ต้องได้เลขที่เอกสาร');
    expect(r.body.payload?.student?.student_code === '69201010001',
      'เนื้อหาต้องตรึงข้อมูลนักศึกษาไว้ในใบ');
    docId = r.body.id;
    docNo = r.body.doc_no;
    return `เลขที่ ${docNo}`;
  });

  await check('API-36 พิมพ์ซ้ำอ่านใบเดิม ไม่กินเลขที่ใหม่', async () => {
    // ถ้าการพิมพ์ซ้ำเรียกออกเอกสารใหม่ เลขที่จะเดินทุกครั้งที่มีคนกดพิมพ์
    // และจะมีเอกสารหลายใบที่เนื้อหาเดียวกันแต่คนละเลขลอยอยู่
    const r = await registrar(`/documents/${docId}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.doc_no === docNo, `เลขที่ต้องเป็นใบเดิม ${docNo} ได้ ${r.body.doc_no}`);
    expect(r.body.payload, 'ต้องคืนเนื้อหาที่ตรึงไว้');

    const list = await registrar(`/documents/students/${F.student}`);
    expect(list.body.length === 1, `ควรมีเอกสารใบเดียว ได้ ${list.body.length} ใบ`);
    return `อ่านซ้ำได้เลขที่เดิม ${r.body.doc_no} และยังมีใบเดียว`;
  });

  await check('API-37 ยกเลิกเอกสารต้องบอกเหตุผล', async () => {
    const bad = await registrar(`/documents/${docId}/void`, {
      method: 'POST', body: JSON.stringify({}),
    });
    expect(bad.status === 400, `ยกเลิกโดยไม่มีเหตุผลควรได้ 400 ได้ ${bad.status}`);

    const ok = await registrar(`/documents/${docId}/void`, {
      method: 'POST', body: JSON.stringify({ reason: 'พิมพ์ผิด ออกใบใหม่แทน' }),
    });
    expect(ok.status === 201, `ได้ ${ok.status}: ${JSON.stringify(ok.body)}`);
    expect(ok.body.voided_at, 'ต้องบันทึกเวลาที่ยกเลิก');
    return ok.body.void_reason;
  });

  await check('API-38 มติอนุมัติจบและเพิ่มผู้สำเร็จการศึกษา', async () => {
    const a = await registrar('/graduation/approvals', {
      method: 'POST',
      body: JSON.stringify({
        approvedOn: '2026-03-31',
        termId: TERM1,
        documentNo: 'ที่ ศธ 0210/2569',
        approvedBy: F.personTeacher,
      }),
    });
    expect(a.status === 201, `ได้ ${a.status}: ${JSON.stringify(a.body)}`);
    approvalId = a.body.id;

    const g = await registrar(`/graduation/approvals/${approvalId}/students`, {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student,
        curriculumVersionId: CV,
        completedOn: '2026-03-31',
        completedTermId: TERM1,
        gpax: 3.25,
        creditsEarned: 106,
        transcriptNo: '2569000123',
        certificateNo: '25690000456',
        professionalStandardNo: 'มฐ.2569/001',
      }),
    });
    expect(g.status === 201, `ได้ ${g.status}: ${JSON.stringify(g.body)}`);
    return `มติ ${a.body.document_no} · ใบประกาศฯ เลขที่ ${g.body.certificate_no}`;
  });

  await check('API-39 เลขที่ใบประกาศนียบัตรที่มีตัวอักษรถูกปฏิเสธพร้อมเหตุผลภาษาไทย', async () => {
    const r = await registrar(`/graduation/approvals/${approvalId}/students`, {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.studentBulkOk, curriculumVersionId: CV,
        completedOn: '2026-03-31', gpax: 3.0, creditsEarned: 106,
        certificateNo: 'CERT-2569-002',
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    const msg = JSON.stringify(r.body);
    expect(/ระเบียบกระทรวง/.test(msg), `ข้อความควรบอกว่าผิดระเบียบอะไร ได้ ${msg}`);
    return 'ตัวเลขล้วนเท่านั้น ตามระเบียบกระทรวง';
  });

  await check('API-40 รายงาน PVRS ประกอบครบและเตือนก่อนส่ง', async () => {
    const r = await registrar(`/graduation/approvals/${approvalId}/pvrs`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.total === 1, `ควรมี 1 ราย ได้ ${r.body.total}`);
    // ต้องบอกให้ชัดว่ารูปแบบไฟล์ยังไม่ได้ยืนยันกับสเปกจริง
    expect(r.body.formatConfirmed === false,
      'ต้องไม่อ้างว่ารูปแบบไฟล์ยืนยันแล้ว ตราบใดที่ยังไม่ได้เทียบกับสเปก สอศ.');
    const row = r.body.rows[0];
    expect(row.full_name && row.full_name.trim().length > 0, 'ชื่อต้องไม่ว่าง');
    expect(row.certificate_no && row.approved_on && row.completed_on,
      'ต้องมีเลขที่ใบประกาศฯ วันที่อนุมัติ และวันที่สำเร็จการศึกษา');
    return `${row.student_code} ${row.full_name} วุฒิ ${row.qualification} เลขที่ ${row.certificate_no}`;
  });

  await check('API-41 ครูออกเอกสารและเปิด PVRS ไม่ได้', async () => {
    const a = await teacher('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certificate' }),
    });
    expect(a.status === 403, `ควรได้ 403 ได้ ${a.status}`);
    const b = await teacher(`/graduation/approvals/${approvalId}/pvrs`);
    expect(b.status === 403, `ควรได้ 403 ได้ ${b.status}`);
  });

  await check('API-43 พิมพ์ระเบียนแสดงผลการเรียนได้เป็นหน้ากระดาษ', async () => {
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript', yearBe: 2569 }),
    });
    expect(issued.status === 201, `ออกใบไม่ได้: ${JSON.stringify(issued.body)}`);

    const r = await registrar(`/documents/${issued.body.id}/print`);
    expect(r.status === 200, `ได้ ${r.status}`);
    const html = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);

    expect(/ระเบียนแสดงผลการเรียน/.test(html), 'ต้องมีหัวเอกสารภาษาไทย');
    expect(html.includes('ปิยะพงศ์'), 'ต้องมีชื่อนักศึกษาบนกระดาษ');
    expect(html.includes('69201010001'), 'ต้องมีเลขประจำตัวนักศึกษา');
    expect(/@page/.test(html) && /A4/.test(html), 'ต้องมี CSS สำหรับพิมพ์ขนาด A4');
    // ชนิด date ต้องมาถึงแม่แบบเป็นสตริง YYYY-MM-DD (ดู common/db/pg-types.ts)
    // ถ้าตัวแปลงชนิดหายไป node-postgres จะคืน Date object แล้ววันที่บนกระดาษ
    // จะกลายเป็น "Sun Aug 09 2026 00:00:00 GMT+0700" ซึ่งพิมพ์แจกไปแล้วแก้ไม่ได้
    expect(/ออกให้เมื่อ \d{1,2} [ก-๙]+ 25\d\d/.test(html),
      'วันที่ออกบนกระดาษต้องเป็นวันที่ไทยแบบเต็ม ไม่ใช่สตริงวันที่ของ JavaScript');
    // ห้ามอ้างอิงไฟล์ภายนอกเลย มิฉะนั้นวันที่เน็ตล่มจะพิมพ์ใบไม่ได้
    expect(!/https?:\/\//.test(html), 'แม่แบบต้องไม่อ้างอิงไฟล์จากอินเทอร์เน็ต');
    return `${html.length} ตัวอักษร · ไม่มีการอ้างอิงภายนอก`;
  });

  await check('API-44 ใบประกาศนียบัตรพิมพ์ได้และเป็นปีพุทธศักราช', async () => {
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certificate', yearBe: 2569 }),
    });
    expect(issued.status === 201, `ออกใบไม่ได้: ${JSON.stringify(issued.body)}`);

    const r = await registrar(`/documents/${issued.body.id}/print`);
    const html = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    expect(/ประกาศนียบัตรวิชาชีพ/.test(html), 'ต้องระบุวุฒิการศึกษาเป็นถ้อยคำตามหลักสูตร');
    expect(html.includes('25690000456'), 'ต้องพิมพ์เลขที่ใบประกาศนียบัตรที่ออกไว้');
    // จบวันที่ 2026-03-31 ต้องแสดงเป็น 31 มีนาคม 2569
    expect(/31 มีนาคม 2569/.test(html),
      'วันที่ต้องเป็นปีพุทธศักราชแบบไทยเต็ม ไม่ใช่ ค.ศ. หรือ ISO');
    return 'ให้ไว้ ณ วันที่ 31 มีนาคม 2569';
  });

  await check('API-45 ออกใบประกาศนียบัตรให้คนที่ยังไม่อนุมัติจบไม่ได้', async () => {
    // ใบที่ออกไปแล้วมีเลขที่ทางราชการติดตัวไป การพบทีหลังว่าออกผิดคน
    // แก้ไม่ได้แล้ว ต้องยกเลิกและเสียเลขนั้นทิ้ง
    const r = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.studentBulkOk, kind: 'certificate' }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
    const msg = JSON.stringify(r.body);
    expect(/ยังไม่มีมติอนุมัติ/.test(msg), `ข้อความควรบอกเหตุผล ได้ ${msg}`);
  });

  await check('API-46 ใบที่ยกเลิกแล้วพิมพ์ได้แต่ต้องมีตราว่ายกเลิก', async () => {
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    await registrar(`/documents/${issued.body.id}/void`, {
      method: 'POST', body: JSON.stringify({ reason: 'ออกผิดปีการศึกษา' }),
    });
    const r = await registrar(`/documents/${issued.body.id}/print`);
    const html = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    expect(/ยกเลิก/.test(html), 'ใบที่ยกเลิกต้องมองปราดเดียวรู้ว่ายกเลิก');
    expect(html.includes('ออกผิดปีการศึกษา'), 'ต้องแสดงเหตุผลที่ยกเลิกบนกระดาษ');
  });

  await check('API-47 หนังสือรับรองพิมพ์ได้และเลือกถ้อยคำตามสถานะ', async () => {
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certification' }),
    });
    expect(issued.status === 201, `ออกใบไม่ได้: ${JSON.stringify(issued.body)}`);
    const r = await registrar(`/documents/${issued.body.id}/print`);
    const html = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    expect(/หนังสือรับรอง/.test(html), 'ต้องมีหัวเอกสาร');
    // นักศึกษาคนนี้ยังไม่ได้เปลี่ยนสถานะเป็น graduated จึงต้องเป็นใบรับรองกำลังศึกษา
    expect(/กำลังศึกษาอยู่ในหลักสูตร/.test(html),
      'สถานะยัง active ต้องได้ถ้อยคำรับรองว่ากำลังศึกษา ไม่ใช่สำเร็จการศึกษา');
    return 'รับรองว่ากำลังศึกษา';
  });

  await check('API-48 สมุดพกต้องระบุภาคเรียน', async () => {
    // ออกโดยไม่ระบุภาคเรียนจะได้ใบที่ดูถูกต้องทุกอย่าง แต่เป็นข้อมูลของภาค
    // ที่ผู้ออกไม่ได้ตั้งใจ ซึ่งไปโผล่ในมือผู้ปกครองแล้วแก้ไม่ได้
    const bad = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'grade_report' }),
    });
    expect(bad.status >= 400, `ควรถูกปฏิเสธ ได้ ${bad.status}`);
    expect(/ระบุภาคเรียน/.test(JSON.stringify(bad.body)), 'ต้องบอกว่าขาดอะไร');

    const ok = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'grade_report', termId: TERM1 }),
    });
    expect(ok.status === 201, `ได้ ${ok.status}: ${JSON.stringify(ok.body)}`);

    const r = await registrar(`/documents/${ok.body.id}/print`);
    const html = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    expect(/ใบแจ้งผลการเรียน/.test(html), 'ต้องมีหัวเอกสาร');
    expect(/ภาคเรียนที่ 1/.test(html), 'ต้องระบุภาคเรียนบนกระดาษ');
    expect(/เวลาเรียน/.test(html), 'สมุดพกต้องแสดงเวลาเรียนด้วย ไม่ใช่แค่เกรด');
    expect(/ลงชื่อผู้ปกครอง/.test(html), 'สมุดพกต้องมีช่องให้ผู้ปกครองลงนาม');
    return 'ภาคเรียนที่ 1 · มีเวลาเรียนและช่องลงนามผู้ปกครอง';
  });

  await check('API-49 ระเบียนสะสม ปพ.8 พิมพ์ได้', async () => {
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'cumulative_record' }),
    });
    expect(issued.status === 201, `ออกใบไม่ได้: ${JSON.stringify(issued.body)}`);
    const r = await registrar(`/documents/${issued.body.id}/print`);
    const html = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    expect(/ระเบียนสะสม/.test(html), 'ต้องมีหัวเอกสาร');
    expect(/ผู้ปกครอง/.test(html) && /ความประพฤติ/.test(html),
      'ต้องมีหมวดผู้ปกครองและความประพฤติ');
    expect(/การคัดกรองและการดูแลช่วยเหลือ/.test(html), 'ต้องมีหมวดการดูแลช่วยเหลือ');
    return 'มีครบทุกหมวด';
  });

  await check('API-50 ข้อมูลอ่อนไหวไม่ติดไปกับเอกสารที่ไม่ได้ใช้มัน', async () => {
    /*
     * payload คือสำเนาถาวรที่ลบไม่ได้ ถ้าผลคัดกรอง SDQ บันทึกเยี่ยมบ้าน และ
     * ข้อมูลผู้ปกครองถูกคัดลอกลงระเบียนแสดงผลการเรียนทุกใบ จะกลายเป็นการ
     * เก็บข้อมูลเกินความจำเป็นตาม PDPA ที่ตรวจพบยากมาก เพราะระบบทำงาน
     * ถูกต้องทุกประการจากภายนอก
     */
    const t = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const doc = await registrar(`/documents/${t.body.id}`);
    const keys = Object.keys(doc.body.payload);
    for (const forbidden of ['screenings', 'home_visits', 'guardians', 'behavior_history']) {
      expect(!keys.includes(forbidden),
        `ระเบียนแสดงผลการเรียนไม่ควรมี ${forbidden} ติดไปด้วย`);
    }

    const c = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'cumulative_record' }),
    });
    const cum = await registrar(`/documents/${c.body.id}`);
    expect(Object.keys(cum.body.payload).includes('screenings'),
      'ระเบียนสะสมต้องมีผลคัดกรอง มิฉะนั้นเทสต์นี้ไม่ได้พิสูจน์อะไร');
    // แต่ต้องเก็บแค่ระดับผล ไม่ใช่คำตอบรายข้อ
    const s = cum.body.payload.screenings;
    if (s.length > 0) {
      expect(!('detail' in s[0]), 'ระเบียนสะสมต้องไม่เก็บรายละเอียดของแบบคัดกรอง');
    }
    return `รบ. มี ${keys.length} หมวด ไม่มีข้อมูลอ่อนไหว`;
  });

  await check('API-42 วิทยาลัยอื่นเปิด PVRS ของเราไม่เห็นข้อมูล', async () => {
    const r = await other(`/graduation/approvals/${approvalId}/pvrs`);
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.total === 0, `ควรไม่เห็นอะไรเลย เห็น ${r.body.total} ราย`);
    const list = await other('/graduation/approvals');
    expect(list.body.length === 0, `ควรไม่เห็นมติของเรา เห็น ${list.body.length} มติ`);
  });

  console.log('');
  console.log('══ สอบซ่อมและเลื่อนชั้นปี ══');

  let regradeCourseId = '';
  let candidateId = '';

  await check('API-51 สร้างรอบสอบซ่อมและหาผู้มีสิทธิ์จากผลการเรียนจริง', async () => {
    const s = await registrar('/regrade/sessions', {
      method: 'POST',
      body: JSON.stringify({
        termId: TERM1, code: 'RG-1-2569', nameTh: 'เรียนปรับเกรด 1/2569 (ปวช.)',
        kind: 'restudy', opensOn: '2026-05-01', closesOn: '2027-05-01',
      }),
    });
    expect(s.status === 201, `ได้ ${s.status}: ${JSON.stringify(s.body)}`);
    expect(s.body.status === 'draft', 'รอบใหม่ต้องเริ่มที่ draft ไม่ใช่เปิดรับทันที');

    const c = await registrar(`/regrade/sessions/${s.body.id}/courses`, {
      method: 'POST',
      body: JSON.stringify({ courseId: COURSE, feeAmount: 600, capacity: 5 }),
    });
    expect(c.status === 201, `ได้ ${c.status}: ${JSON.stringify(c.body)}`);
    regradeCourseId = c.body.id;

    await registrar(`/regrade/sessions/${s.body.id}/open`, { method: 'POST' });

    const e = await registrar(`/regrade/courses/${regradeCourseId}/eligible`);
    expect(e.status === 200, `ได้ ${e.status}`);
    const codes = e.body.map((x: any) => x.student_code);
    expect(codes.includes('69201010779'), 'คนที่ได้เกรด 0 ต้องมีสิทธิ์สอบซ่อม');
    expect(!codes.includes('69201010001'), 'คนที่ยังไม่มีผลการเรียนต้องไม่อยู่ในรายชื่อ');
    return `มีสิทธิ์ ${e.body.length} คน`;
  });

  await check('API-52 ลงทะเบียนกลุ่ม คนไม่มีสิทธิ์ไม่ลากคนอื่นล้ม', async () => {
    const r = await registrar(`/regrade/courses/${regradeCourseId}/register`, {
      method: 'POST',
      body: JSON.stringify({ studentIds: [F.studentRegrade, F.student] }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.succeeded === 1 && r.body.rejected === 1,
      `ควรผ่าน 1 ปฏิเสธ 1 ได้ ผ่าน ${r.body.succeeded} ปฏิเสธ ${r.body.rejected}`);
    const no = r.body.results.find((x: any) => !x.registered);
    expect(/[ก-๙]/.test(no.reason ?? ''), 'เหตุผลที่ไม่มีสิทธิ์ต้องเป็นภาษาไทย');

    const list = await registrar(`/regrade/courses/${regradeCourseId}/candidates`);
    candidateId = list.body[0].id;
    return no.reason;
  });

  await check('API-53 บันทึกผลได้คำร้องแก้เกรด เกรดยังไม่เปลี่ยน', async () => {
    /*
     * ถ้ารอบสอบซ่อมเขียนเกรดได้เอง ใครก็ตามที่สร้างรอบขึ้นมาได้จะแก้เกรด
     * ใครก็ได้โดยไม่ต้องผ่านการอนุมัติของใครเลย — เป็นช่องที่ใหญ่กว่าตัว
     * ฟีเจอร์เองมาก
     */
    const before = await registrar(`/documents/transcript/${F.studentRegrade}`);
    const symBefore = before.body[0]?.grade_symbol;
    expect(symBefore === '0', `ตั้งต้นควรเป็นเกรด 0 ได้ ${symBefore}`);

    const r = await registrar(`/regrade/candidates/${candidateId}/result`, {
      method: 'POST',
      body: JSON.stringify({
        toGradeSymbolId: passSymbolId, reason: 'สอบซ่อมผ่านตามรอบ RG-1-2569',
        documentNo: 'ที่ ศธ 999/2569',
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.changeRequestId, 'ต้องได้รหัสคำร้องแก้เกรดกลับมา');

    const after = await registrar(`/documents/transcript/${F.studentRegrade}`);
    expect(after.body[0]?.grade_symbol === symBefore,
      `เกรดต้องยังเป็น ${symBefore} จนกว่าคำร้องจะผ่านการอนุมัติสองชั้น`);
    return `ยื่นคำร้องแล้ว เกรดยังเป็น ${symBefore}`;
  });

  await check('API-54 เลื่อนชั้นปีต้องมีปีการศึกษาปลายทางก่อน', async () => {
    const r = await registrar('/rollover/students', {
      method: 'POST',
      body: JSON.stringify({ fromYearBe: 2569, toYearBe: 2599 }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
    expect(/ยังไม่ได้สร้างปีการศึกษา/.test(JSON.stringify(r.body)),
      'ต้องบอกว่าให้ไปสร้างปีการศึกษาก่อน ไม่ใช่สร้างปฏิทินให้เองด้วยการเดาวันที่');
  });

  await check('API-55 ครูเลื่อนชั้นปีทั้งวิทยาลัยไม่ได้', async () => {
    const r = await teacher('/rollover/students', {
      method: 'POST',
      body: JSON.stringify({ fromYearBe: 2569, toYearBe: 2570 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-57 จัดชั้นปีและห้องประจำเป็นกลุ่ม', async () => {
    const r = await registrar('/rollover/placements', {
      method: 'POST',
      body: JSON.stringify({
        academicYearId: AY,
        studentIds: [F.student, F.studentRegrade],
        studyYear: 1,
        groupCode: 'ปวช.1/1',
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.placed === 2, `ควรจัดได้ 2 คน ได้ ${r.body.placed}`);

    const list = await registrar(`/rollover/placements?academicYearId=${AY}`);
    expect(list.status === 200, `ได้ ${list.status}`);
    expect(list.body.some((x: any) => x.group_code === 'ปวช.1/1'),
      'ต้องอ่านห้องที่จัดไว้กลับมาได้');

    // จัดใหม่ต้องทับของเดิมในปีเดียวกัน ไม่ใช่สร้างแถวซ้ำ
    const again = await registrar('/rollover/placements', {
      method: 'POST',
      body: JSON.stringify({
        academicYearId: AY, studentIds: [F.student], studyYear: 1, groupCode: 'ปวช.1/2',
      }),
    });
    expect(again.body.placed === 1, 'จัดใหม่ต้องทำได้');
    const after = await registrar(`/rollover/placements?academicYearId=${AY}`);
    expect(after.body.length === list.body.length,
      `จัดใหม่ไม่ควรเพิ่มแถว มี ${list.body.length} กลายเป็น ${after.body.length}`);
    return `จัด ${r.body.placed} คน และจัดใหม่ทับของเดิมได้`;
  });

  await check('API-58 คัดลอกสมุดคะแนนข้ามภาค และรายงานห้องที่จับคู่ไม่ได้', async () => {
    // สร้างรายการคะแนนในห้องต้นทางก่อน
    const item = await teacher(`/gradebook/sections/${F.section}/items`, {
      method: 'POST',
      body: JSON.stringify({
        nameTh: 'สอบกลางภาค', category: 'midterm', maxScore: 30, weight: 30,
      }),
    });
    expect(item.status === 201, `สร้างรายการคะแนนไม่ได้: ${JSON.stringify(item.body)}`);

    const r = await registrar('/rollover/gradebooks', {
      method: 'POST',
      body: JSON.stringify({ fromTermId: TERM1, toTermId: TERM2 }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Array.isArray(r.body.needsAttention),
      'ต้องรายงานห้องที่ต้องไปตั้งเอง ไม่ใช่ข้ามเงียบ ๆ');
    expect(r.body.sections > 0,
      'ต้องมีห้องปลายทางให้คัดลอก มิฉะนั้นเทสต์นี้ผ่านโดยไม่ได้ทดสอบอะไร');
    expect(r.body.itemsCopied > 0,
      `ต้องคัดลอกรายการคะแนนได้จริง ได้ ${r.body.itemsCopied} รายการ`);

    // กดซ้ำต้องไม่คัดลอกซ้อน มิฉะนั้นน้ำหนักคะแนนรวมจะเกินร้อย
    const again = await registrar('/rollover/gradebooks', {
      method: 'POST',
      body: JSON.stringify({ fromTermId: TERM1, toTermId: TERM2 }),
    });
    expect(again.body.itemsCopied === 0,
      `กดซ้ำต้องไม่คัดลอกเพิ่ม ได้ ${again.body.itemsCopied} รายการ`);
    return `${r.body.sections} ห้อง · คัดลอก ${r.body.itemsCopied} รายการ · กดซ้ำได้ 0`;
  });

  await check('API-59 วิทยาลัยอื่นจัดห้องให้นักศึกษาของเราไม่ได้', async () => {
    const r = await other('/rollover/placements', {
      method: 'POST',
      body: JSON.stringify({
        academicYearId: AY, studentIds: [F.student], studyYear: 1, groupCode: 'แทรก',
      }),
    });
    // ปีการศึกษาเป็นของอีกวิทยาลัย จึงต้องถูกปฏิเสธตั้งแต่ต้นทาง
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-56 วิทยาลัยอื่นไม่เห็นรอบสอบซ่อมของเรา', async () => {
    const r = await other('/regrade/sessions');
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.length === 0, `ควรไม่เห็นรอบของเรา เห็น ${r.body.length} รอบ`);
  });

  console.log('');
  console.log('══ งานบุคลากร ══');

  let deptId = '';
  let leaveId = '';

  await check('API-74 โครงสร้างหน่วยงานเป็นต้นไม้และวนกลับไม่ได้', async () => {
    const top = await registrar('/hr/departments', {
      method: 'POST',
      body: JSON.stringify({ code: 'ACAD', nameTh: 'ฝ่ายวิชาการ', kind: 'division' }),
    });
    expect(top.status === 201, `ได้ ${top.status}: ${JSON.stringify(top.body)}`);

    const child = await registrar('/hr/departments', {
      method: 'POST',
      body: JSON.stringify({
        parentId: top.body.id, code: 'MECH',
        nameTh: 'แผนกวิชาช่างยนต์', kind: 'department', headStaffId: F.staff,
      }),
    });
    expect(child.status === 201, `ได้ ${child.status}: ${JSON.stringify(child.body)}`);
    deptId = child.body.id;

    const tree = await registrar('/hr/departments');
    const leaf = tree.body.find((d: any) => d.code === 'MECH');
    expect(leaf.depth === 1, `ชั้นของแผนกควรเป็น 1 ได้ ${leaf.depth}`);
    expect(/›/.test(leaf.path_th), 'ต้องมีเส้นทางเต็มของหน่วยงาน');
    return leaf.path_th;
  });

  await check('API-75 ระเบียนบุคลากร ทช.1 และชั่วโมงอบรม', async () => {
    await registrar(`/hr/staff/${F.staff}/assignments`, {
      method: 'POST',
      body: JSON.stringify({ departmentId: deptId, positionTh: 'หัวหน้าแผนกวิชาช่างยนต์' }),
    });

    await registrar(`/hr/staff/${F.staff}/records`, {
      method: 'POST',
      body: JSON.stringify({
        kind: 'education', titleTh: 'ครุศาสตร์อุตสาหกรรมบัณฑิต',
        organizationTh: 'มหาวิทยาลัยเทคโนโลยีทดสอบ', fieldTh: 'วิศวกรรมเครื่องกล',
      }),
    });
    await registrar(`/hr/staff/${F.staff}/records`, {
      method: 'POST',
      body: JSON.stringify({
        kind: 'training', titleTh: 'อบรมการจัดการเรียนรู้ฐานสมรรถนะ',
        organizationTh: 'สอศ.', hours: 18,
      }),
    });

    const r = await registrar(`/hr/staff/${F.staff}/records`);
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.education.length === 1, 'ต้องมีประวัติการศึกษา');
    expect(r.body.trainingHours === 18,
      `ชั่วโมงอบรมควรเป็น 18 ได้ ${r.body.trainingHours}`);
    return `วุฒิ ${r.body.education.length} รายการ · อบรม ${r.body.trainingHours} ชั่วโมง`;
  });

  await check('API-76 ผู้ยื่นใบลาอนุมัติใบลาของตัวเองไม่ได้', async () => {
    /*
     * สิทธิ์อนุมัติที่ใช้กับตัวเองได้ไม่ใช่การอนุมัติ แต่เป็นการประทับตรา
     * และหัวหน้าแผนกทุกคนมีสิทธิ์อนุมัติ ถ้าไม่กันไว้ ใบลาของหัวหน้า
     * จะไม่เคยผ่านสายตาใครเลย
     */
    const r = await registrar('/hr/leaves', {
      method: 'POST',
      body: JSON.stringify({
        staffId: F.staff, kind: 'sick',
        fromDate: '2026-09-10', toDate: '2026-09-11', days: 2,
        reason: 'ป่วยเป็นไข้หวัดใหญ่',
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.status === 'pending', 'ใบลาใหม่ต้องรออนุมัติ ไม่ใช่อนุมัติเอง');
    leaveId = r.body.id;

    // F.personTeacher คือเจ้าของใบลา
    const self = await registrar(`/hr/leaves/${leaveId}/decision`, {
      method: 'POST',
      body: JSON.stringify({ status: 'approved', decidedBy: F.personTeacher }),
    });
    expect(self.status >= 400, `อนุมัติเองควรถูกปฏิเสธ ได้ ${self.status}`);
    expect(/ตัวเอง/.test(JSON.stringify(self.body)), 'ข้อความควรบอกว่าอนุมัติเองไม่ได้');

    const ok = await registrar(`/hr/leaves/${leaveId}/decision`, {
      method: 'POST',
      body: JSON.stringify({
        status: 'approved', decidedBy: F.personStudent, note: 'อนุมัติตามใบรับรองแพทย์',
      }),
    });
    expect(ok.status === 201, `ได้ ${ok.status}: ${JSON.stringify(ok.body)}`);
    expect(ok.body.decided_at, 'ต้องบันทึกเวลาที่ตัดสิน');
    return 'อนุมัติเองไม่ได้ · ผู้บังคับบัญชาอนุมัติได้';
  });

  await check('API-77 ใบลาที่อนุมัติแล้วซ้อนวันกันไม่ได้', async () => {
    // ลาป่วยทับลากิจในวันเดียวกันแปลว่ามีใบใดใบหนึ่งผิด และวันลาสะสมจะนับซ้ำ
    const dup = await registrar('/hr/leaves', {
      method: 'POST',
      body: JSON.stringify({
        staffId: F.staff, kind: 'personal',
        fromDate: '2026-09-11', toDate: '2026-09-12', days: 2, reason: 'ธุระส่วนตัว',
      }),
    });
    expect(dup.status === 201, 'ยื่นใบลาที่ยังไม่อนุมัติต้องทำได้');

    const r = await registrar(`/hr/leaves/${dup.body.id}/decision`, {
      method: 'POST',
      body: JSON.stringify({ status: 'approved', decidedBy: F.personStudent }),
    });
    expect(r.status >= 400, `อนุมัติใบที่ซ้อนวันควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-78 สรุปเวลาทำการต้องนับวันลาที่อนุมัติแล้ว', async () => {
    // ถ้านับจากการสแกนบัตรอย่างเดียว คนที่ลาถูกต้องจะกลายเป็นขาดงาน
    // ในรายงานที่ใช้ประเมินผลงานประจำปี
    const rec = await registrar('/hr/attendance', {
      method: 'POST',
      body: JSON.stringify({
        onDate: '2026-09-01',
        rows: [{ staffId: F.staff, status: 'late', checkIn: '08:40' }],
      }),
    });
    expect(rec.status === 201, `ได้ ${rec.status}: ${JSON.stringify(rec.body)}`);

    const r = await registrar('/hr/worktime?from=2026-08-01&to=2026-10-31');
    expect(r.status === 200, `ได้ ${r.status}`);
    const me = r.body.rows.find((x: any) => x.staff_id === F.staff);
    expect(me, 'ต้องมีบุคลากรคนนี้ในสรุป');
    expect(Number(me.late) === 1, `มาสายควรเป็น 1 ได้ ${me.late}`);
    expect(Number(me.leave_days) > 0,
      'ต้องนับวันลาที่อนุมัติแล้ว มิฉะนั้นคนที่ลาถูกต้องจะกลายเป็นขาดงาน');
    expect(me.department, 'ต้องรู้ว่าสังกัดหน่วยงานไหน');
    return `${me.full_name} (${me.department}) สาย ${me.late} · วันลา ${me.leave_days}`;
  });

  await check('API-79 บุตรบุคลากรผูกกับนักศึกษาได้ครั้งเดียว', async () => {
    // funding_kind มี staff_child อยู่แล้วตั้งแต่ 0010 แต่ก่อน 0035
    // ไม่มีทางรู้ว่าใครเป็นบุตรของใคร ส่วนลดจึงตรวจสอบย้อนหลังไม่ได้
    const r = await registrar(`/hr/staff/${F.staff}/children`, {
      method: 'POST',
      body: JSON.stringify({
        fullNameTh: 'ด.ญ. ทดสอบ ใจงาม', birthDate: '2012-01-15',
        studentId: F.student,
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);

    const dup = await registrar(`/hr/staff/${F.staff}/children`, {
      method: 'POST',
      body: JSON.stringify({ fullNameTh: 'ชื่ออื่น', studentId: F.student }),
    });
    expect(dup.status >= 400, `ผูกนักศึกษาคนเดิมซ้ำควรถูกปฏิเสธ ได้ ${dup.status}`);

    const list = await registrar(`/hr/staff/${F.staff}/children`);
    expect(list.body.length === 1, `ควรมีบุตร 1 คน ได้ ${list.body.length}`);
    expect(list.body[0].student_code, 'ต้องบอกรหัสนักศึกษาของบุตรที่เรียนที่นี่');
  });

  await check('API-80 ครูเปิดใบลาและเวลาทำการของทั้งวิทยาลัยไม่ได้', async () => {
    const a = await teacher('/hr/leaves');
    expect(a.status === 403, `ควรได้ 403 ได้ ${a.status}`);
    const b = await teacher('/hr/worktime?from=2026-08-01&to=2026-10-31');
    expect(b.status === 403, `ควรได้ 403 ได้ ${b.status}`);
    // แต่ต้องดูโครงสร้างหน่วยงานได้ เพราะต้องรู้ว่าตัวเองสังกัดที่ไหน
    const c = await teacher('/hr/departments');
    expect(c.status === 200, `ครูควรดูโครงสร้างหน่วยงานได้ ได้ ${c.status}`);
  });

  await check('API-81 วิทยาลัยอื่นไม่เห็นข้อมูลบุคลากรของเรา', async () => {
    const a = await other('/hr/departments');
    expect(a.body.length === 0, `ควรไม่เห็นหน่วยงานของเรา เห็น ${a.body.length}`);
    const b = await other('/hr/leaves');
    expect(b.body.length === 0, `ควรไม่เห็นใบลาของเรา เห็น ${b.body.length}`);
  });

  console.log('');
  console.log('══ จัดตารางสอน ══');

  await check('API-69 ตรวจการชนก่อนวางคาบ', async () => {
    // F.section อยู่วันพุธ คาบ 1–2 ห้องโรงฝึกงาน 3 อยู่แล้ว
    const bad = await registrar('/timetable/check', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: '20000000-0000-0000-0000-0000000000c0',
        dayOfWeek: 3, periodFrom: 2, periodTo: 3, roomId: F.room,
      }),
    });
    expect(bad.status === 201, `ได้ ${bad.status}: ${JSON.stringify(bad.body)}`);
    expect(bad.body.canPlace === false, 'คาบที่ทับของเดิมต้องวางไม่ได้');
    const kinds = bad.body.conflicts.map((c: any) => c.kind);
    expect(kinds.includes('teacher') || kinds.includes('room'),
      `ต้องบอกว่าชนเพราะอะไร ได้ ${JSON.stringify(kinds)}`);
    expect(bad.body.conflicts.every((c: any) => /[ก-๙]/.test(c.message_th)),
      'ข้อความต้องเป็นภาษาไทย');

    const ok = await registrar('/timetable/check', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: '20000000-0000-0000-0000-0000000000c0',
        dayOfWeek: 4, periodFrom: 1, periodTo: 2, roomId: F.room,
      }),
    });
    expect(ok.body.canPlace === true,
      `คาบว่างจริงควรวางได้ ติด: ${JSON.stringify(ok.body.conflicts)}`);
    return `ชน ${bad.body.conflicts.length} รายการ: ${bad.body.conflicts[0].message_th}`;
  });

  await check('API-70 วางคาบที่ชนไม่ได้ พร้อมบอกว่าชนกับอะไร', async () => {
    const r = await registrar('/timetable/slots', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: '20000000-0000-0000-0000-0000000000c0',
        dayOfWeek: 3, periodFrom: 1, periodTo: 2, roomId: F.room,
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
    expect(Array.isArray(r.body.conflicts) && r.body.conflicts.length > 0,
      'ต้องบอกรายการที่ชนกลับมาด้วย ไม่ใช่แค่ปฏิเสธ');

    const ok = await registrar('/timetable/slots', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: '20000000-0000-0000-0000-0000000000c0',
        dayOfWeek: 4, periodFrom: 1, periodTo: 2, roomId: F.room,
      }),
    });
    expect(ok.status === 201, `ได้ ${ok.status}: ${JSON.stringify(ok.body)}`);
    return 'ปฏิเสธพร้อมเหตุผล และวางคาบว่างได้';
  });

  await check('API-71 คาบที่เสนอต้องไม่ทับคาบพักกลางวัน', async () => {
    const r = await registrar(
      `/timetable/suggest?classSectionId=20000000-0000-0000-0000-0000000000c0&periods=2`);
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.length > 0, 'ต้องเสนอคาบว่างได้อย่างน้อยหนึ่งคาบ');
    // นโยบายของ fixture: 8 คาบต่อวัน 5 วัน พักกลางวันคาบ 5
    const bad = r.body.filter(
      (s: any) => s.period_to > 8 || s.day_of_week > 5 ||
        (s.period_from <= 5 && s.period_to >= 5));
    expect(bad.length === 0,
      `เสนอคาบที่ผิดนโยบาย ${bad.length} รายการ: ${JSON.stringify(bad[0] ?? {})}`);
    return `เสนอ ${r.body.length} คาบ`;
  });

  await check('API-72 จัดตารางอัตโนมัติแล้วต้องไม่มีการชนใหม่', async () => {
    const before = await registrar(`/timetable/terms/${TERM1}/conflicts`);
    expect(before.status === 200, `ได้ ${before.status}`);

    const r = await registrar(`/timetable/terms/${TERM1}/auto-schedule`, { method: 'POST' });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.sections > 0, 'ต้องมีห้องเรียนให้จัด');
    expect(Array.isArray(r.body.needsAttention),
      'ต้องรายงานวิชาที่จัดไม่ครบ ไม่ใช่ยัดลงไปให้ครบแล้วเงียบ');

    const after = await registrar(`/timetable/terms/${TERM1}/conflicts`);
    expect(after.body.total <= before.body.total,
      `ตัวจัดอัตโนมัติสร้างการชนใหม่ ${before.body.total} → ${after.body.total}`);
    return `จัด ${r.body.periodsPlaced} คาบ · ต้องดูเอง ${r.body.needsAttention.length} วิชา · การชน ${after.body.total}`;
  });

  await check('API-73 ครูจัดตารางทั้งภาคเรียนไม่ได้', async () => {
    const r = await teacher(`/timetable/terms/${TERM1}/auto-schedule`, { method: 'POST' });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ ปฏิทินการศึกษาและกลุ่มเรียน ══');

  /*
   * ─── ทำไมชุดนี้เพิ่งมามี ───
   * ทั้งระบบเคยไม่มีเส้นทางไหนคืน "รายการภาคเรียน" หรือ "รายการกลุ่มเรียน"
   * เลยสักเส้น มีแต่เส้นทางที่**รับ** termId/sectionId เข้าไป — ซึ่งเทสต์
   * ทุกชุดไม่เคยสะดุด เพราะรู้ uuid จาก seed อยู่แล้ว และแอปนักศึกษารับค่า
   * มาตอน build ช่องนี้จึงมองไม่เห็นจนกว่าจะมีคนสร้างหน้าจอของเจ้าหน้าที่จริง
   */

  await check('API-85 รายการภาคเรียนต้องมีวันสำคัญครบ', async () => {
    const r = await registrar('/academic/terms');
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(Array.isArray(r.body) && r.body.length >= 2, 'ควรเห็นอย่างน้อยสองภาคเรียน');

    const t1 = r.body.find((t: any) => t.id === TERM1);
    expect(t1, 'ไม่พบภาคเรียนที่ 1 ในรายการ');
    expect(t1.year_be === 2569, `ปีการศึกษาควรเป็น 2569 ได้ ${t1.year_be}`);
    // วันสำคัญสามค่านี้บังคับใช้จริง หน้าจอต้องใช้ตัดสินใจว่ายังเพิ่ม/ถอนทันไหม
    expect(t1.add_drop_ends_on && t1.grade_due_on, 'ต้องคืนวันสิ้นสุดเพิ่ม/ถอนและกำหนดส่งเกรด');
    return `${r.body.length} ภาคเรียน`;
  });

  await check('API-86 รายการกลุ่มเรียนต้องบอกจำนวนที่ลงแล้ว', async () => {
    const r = await registrar(`/academic/sections?termId=${TERM1}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(r.body.length > 0, 'ควรเห็นกลุ่มเรียนอย่างน้อยหนึ่งกลุ่ม');

    const s = r.body[0];
    // ต้องรู้ว่าเต็มหรือยัง**ก่อน**กดลงทะเบียน ไม่ใช่รู้ตอนที่ฐานข้อมูลปฏิเสธ
    expect(s.code && s.name_th, 'ต้องคืนรหัสและชื่อวิชา');
    expect(s.enrolled !== undefined && s.capacity !== undefined,
      'ต้องคืนจำนวนที่ลงแล้วและความจุ');
    return `${r.body.length} กลุ่มเรียน`;
  });

  let newSection = '';

  await check('API-87 เปิดกลุ่มเรียนใหม่แล้วผูกฉบับหลักสูตรให้เอง', async () => {
    /*
     * `compute_section_grades()` ปฏิเสธกลุ่มเรียนที่ไม่ได้ผูกฉบับหลักสูตร
     * แต่ข้อผิดพลาดนั้นโผล่ตอน**ตัดเกรดปลายภาค** ซึ่งห่างจากตอนเปิดกลุ่ม
     * หลายเดือน การเปิดกลุ่มที่ตัดเกรดไม่ได้จึงเท่ากับซ่อนปัญหาไว้ทั้งภาค
     */
    const r = await registrar('/academic/sections', {
      method: 'POST',
      body: JSON.stringify({
        termId: TERM2, courseId: COURSE, sectionNo: 'ทดสอบ-1', teacherId: F.staff,
      }),
    });
    expect(r.status === 201 || r.status === 200, `ควรสร้างได้ ได้ ${r.status} ${JSON.stringify(r.body)}`);

    expect(r.body.curriculum_version_id === CV,
      'ต้องผูกฉบับหลักสูตรให้เองเมื่อรายวิชาอยู่ในฉบับที่ใช้งานอยู่ฉบับเดียว');
    expect(r.body.attendance_policy_id === POLICY, 'ต้องผูกนโยบายเวลาเรียนให้เอง');
    // 2 หน่วยกิต × 18 สัปดาห์ — ตัวหารของกฎเวลาเรียน 80%
    expect(Number(r.body.planned_periods) === 36,
      `คาบที่วางแผนควรเป็น 36 ได้ ${r.body.planned_periods}`);

    // กลุ่มที่เพิ่งเปิดต้องโผล่ในรายการของภาคนั้นทันที
    const list = await registrar(`/academic/sections?termId=${TERM2}`);
    expect(list.body.some((s: any) => s.id === r.body.id), 'กลุ่มที่เพิ่งเปิดควรอยู่ในรายการ');

    newSection = r.body.id;
    return 'ผูกหลักสูตร นโยบายเวลาเรียน และคาบที่วางแผนให้ครบ';
  });

  await check('API-88 ครูเปิดกลุ่มเรียนเองไม่ได้', async () => {
    const r = await teacher('/academic/sections', {
      method: 'POST',
      body: JSON.stringify({ termId: TERM2, courseId: COURSE, sectionNo: 'ครูเปิดเอง' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-89 สร้างคาบเรียนจากตารางสอนแล้วเช็คชื่อได้จริง', async () => {
    /*
     * `generate_class_meetings()` มีในฐานข้อมูลตั้งแต่ 0009 แต่ไม่เคยมี
     * เส้นทางไหนเรียกเลย — คาบเรียนจึงไม่เคยเกิดขึ้น และเมื่อไม่มีคาบ
     * ก็เช็คชื่อไม่ได้ทั้งระบบ ทั้งที่ชั้นเช็คชื่อและกฎเวลาเรียน 80%
     * เขียนเสร็จมานานแล้ว (รูปเดียวกับ take_usage_snapshot ในข้อ 8)
     */
    expect(newSection, 'ต้องมีกลุ่มเรียนจาก API-87 ก่อน');

    // ยังไม่วางตารางสอน = ไม่มีคาบให้สร้าง ซึ่งต้องไม่ล้ม แต่ต้องได้ศูนย์
    const none = await registrar(`/academic/sections/${newSection}/meetings`, { method: 'POST' });
    expect(none.status < 400, `ควรไม่ล้ม ได้ ${none.status}`);
    expect(none.body.created === 0, `ยังไม่มีตารางสอนควรได้ 0 คาบ ได้ ${none.body.created}`);

    const slot = await registrar('/timetable/slots', {
      method: 'POST',
      body: JSON.stringify({
        // ศุกร์บ่าย คาบ 7–8 — เลี่ยงคาบพักกลางวัน (คาบ 5) เลี่ยงเสาร์อาทิตย์
        // (timetable_policy จำกัด 5 วันเรียนต่อสัปดาห์) และเลี่ยงคาบที่เทสต์
        // ก่อนหน้าวางให้ครูคนเดียวกันไปแล้ว
        classSectionId: newSection, dayOfWeek: 5, periodFrom: 7, periodTo: 8,
      }),
    });
    expect(slot.status < 400, `วางคาบไม่สำเร็จ: ${JSON.stringify(slot.body)}`);

    const gen = await registrar(`/academic/sections/${newSection}/meetings`, { method: 'POST' });
    expect(gen.status < 400, `ควรสร้างได้ ได้ ${gen.status} ${JSON.stringify(gen.body)}`);
    expect(gen.body.created > 0, 'วางตารางสอนแล้วต้องสร้างคาบได้');

    const after = await registrar(`/academic/sections/${newSection}/meetings`);
    expect(after.body.length === gen.body.created,
      `จำนวนคาบที่อ่านได้ควรเท่ากับที่สร้าง (${after.body.length} เทียบ ${gen.body.created})`);
    expect(after.body[0].marked !== undefined, 'ต้องบอกว่าคาบนั้นเช็คชื่อไปกี่คนแล้ว');

    return `สร้าง ${gen.body.created} คาบ`;
  });

  await check('API-91 สร้างห้องเรียนแล้วเอาไปวางคาบได้จริง', async () => {
    /*
     * ห้องเป็นตารางจริงตั้งแต่ 0034 (เลิกเทียบด้วยสตริง เพราะ "ห้อง 301"
     * กับ "301" กลายเป็นคนละห้องแล้วมองไม่เห็นการชนที่เกิดจริง) แต่ไม่เคยมี
     * เส้นทางสร้างห้องเลย — วิทยาลัยที่เพิ่งเปิดจึงจัดตารางไม่ได้
     */
    const code = `T${Date.now() % 100000}`;
    const r = await registrar('/timetable/rooms', {
      method: 'POST',
      body: JSON.stringify({ code, nameTh: 'ห้องทดสอบ', kind: 'lab', capacity: 25, building: 'อาคารทดสอบ' }),
    });
    expect(r.status === 201 || r.status === 200, `ควรสร้างได้ ได้ ${r.status} ${JSON.stringify(r.body)}`);
    expect(r.body.kind === 'lab', `ประเภทห้องควรเป็น lab ได้ ${r.body.kind}`);

    const list = await registrar('/timetable/rooms');
    expect(list.body.some((x: any) => x.id === r.body.id), 'ห้องที่เพิ่งสร้างควรอยู่ในรายการ');

    // ต้องใช้วางคาบได้จริง ไม่ใช่แค่มีแถวในตาราง
    const place = await registrar('/timetable/check', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: newSection, dayOfWeek: 4, periodFrom: 7, periodTo: 8, roomId: r.body.id,
      }),
    });
    expect(place.status === 200 || place.status === 201, `ตรวจคาบไม่สำเร็จ ได้ ${place.status}`);
    expect(place.body.canPlace === true,
      `ห้องใหม่ที่ยังไม่มีใครใช้ควรวางได้ ติด: ${JSON.stringify(place.body.conflicts)}`);

    return `ห้อง ${code} · วางคาบได้จริง`;
  });

  await check('API-92 ครูสร้างห้องเรียนเองไม่ได้', async () => {
    const r = await teacher('/timetable/rooms', {
      method: 'POST',
      body: JSON.stringify({ code: 'X-999', nameTh: 'ห้องที่ครูสร้างเอง' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-90 สร้างคาบใหม่ทับกลุ่มที่สอนไปแล้วไม่ได้', async () => {
    /*
     * การสร้างใหม่คือการลบคาบเดิมทิ้งทั้งหมด ซึ่งจะลบเวลาเรียนที่บันทึกไว้
     * ไปด้วย — เท่ากับลบหลักฐานว่าใครมาเรียนกี่คาบ แล้วกฎ 80% จะคิดจาก
     * ตัวหารชุดใหม่ที่ไม่ตรงกับที่นักศึกษาเคยเห็น
     */
    const r = await registrar(`/academic/sections/${F.section}/meetings`, { method: 'POST' });
    expect(r.status === 422, `ควรได้ 422 ได้ ${r.status}`);
    expect(String(r.body.message).includes('สอนไปแล้ว'), `ข้อความควรบอกเหตุผล ได้ ${r.body.message}`);
    return String(r.body.message);
  });

  console.log('');
  console.log('══ งานรับสมัคร ══');

  let roundId = '';
  let appId = '';

  await check('API-60 เปิดรอบรับสมัครพร้อมโควตาที่นั่ง', async () => {
    const today = new Date();
    const iso = (d: number) =>
      new Date(today.getTime() + d * 86400000).toISOString().slice(0, 10);

    const r = await registrar('/admissions/rounds', {
      method: 'POST',
      body: JSON.stringify({
        academicYearId: AY, code: 'R1-2569', nameTh: 'รอบรับตรง 1/2569',
        appliesFrom: iso(-7), appliesTo: iso(7),
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.status === 'draft', 'รอบใหม่ต้องเริ่มที่ draft ไม่ใช่เปิดรับทันที');
    roundId = r.body.id;

    const q = await registrar(`/admissions/rounds/${roundId}/quotas`, {
      method: 'POST',
      body: JSON.stringify({ curriculumVersionId: CV, seats: 1 }),
    });
    expect(q.status === 201, `ได้ ${q.status}: ${JSON.stringify(q.body)}`);

    await registrar(`/admissions/rounds/${roundId}/status`, {
      method: 'POST', body: JSON.stringify({ status: 'open' }),
    });
    return `โควตา ${q.body.seats} ที่นั่ง`;
  });

  await check('API-61 รับใบสมัครและยื่น', async () => {
    const r = await registrar('/admissions/applications', {
      method: 'POST',
      body: JSON.stringify({
        roundId, firstNameTh: 'ณัฐดนัย', lastNameTh: 'ผู้สมัครหนึ่ง',
        nationalId: '1100000000001', priorSchoolTh: 'โรงเรียนทดสอบวิทยา',
        priorQualificationTh: 'ม.3', priorGpax: 2.85,
        referralSource: 'เพจเฟซบุ๊กของวิทยาลัย',
        choices: [{ preference: 1, curriculumVersionId: CV }],
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(/^R1-2569-\d{4}$/.test(r.body.applicationNo),
      `เลขที่ใบสมัครควรอยู่ในรูป R1-2569-0001 ได้ ${r.body.applicationNo}`);
    appId = r.body.id;

    const s = await registrar(`/admissions/applications/${appId}/submit`, { method: 'POST' });
    expect(s.status === 201, `ได้ ${s.status}: ${JSON.stringify(s.body)}`);
    expect(s.body.status === 'submitted', `ควรเป็น submitted ได้ ${s.body.status}`);
    return `เลขที่ ${r.body.applicationNo}`;
  });

  await check('API-62 เลขบัตรประชาชนซ้ำในรอบเดียวกันสมัครไม่ได้', async () => {
    // สมัครสองใบจะกินโควตาสองที่นั่ง และถ้าผ่านทั้งคู่จะได้รหัสนักศึกษาสองรหัส
    const r = await registrar('/admissions/applications', {
      method: 'POST',
      body: JSON.stringify({
        roundId, firstNameTh: 'ณัฐดนัย', lastNameTh: 'สมัครซ้ำ',
        nationalId: '1100000000001',
        choices: [{ preference: 1, curriculumVersionId: CV }],
      }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-63 เลขบัตรที่ไม่ใช่ 13 หลักถูกปฏิเสธพร้อมข้อความไทย', async () => {
    const r = await registrar('/admissions/applications', {
      method: 'POST',
      body: JSON.stringify({
        roundId, firstNameTh: 'ทดสอบ', lastNameTh: 'เลขบัตรผิด',
        nationalId: '123',
        choices: [{ preference: 1, curriculumVersionId: CV }],
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
    expect(/13 หลัก/.test(JSON.stringify(r.body)), 'ข้อความควรบอกว่าต้อง 13 หลัก');
  });

  await check('API-64 ประกาศผ่านเกินที่นั่งไม่ได้ แต่ขึ้นสำรองได้', async () => {
    const d = await registrar(`/admissions/applications/${appId}/decision`, {
      method: 'POST',
      body: JSON.stringify({
        outcome: 'passed', curriculumVersionId: CV, rankNo: 1, score: 78.5,
      }),
    });
    expect(d.status === 201, `ได้ ${d.status}: ${JSON.stringify(d.body)}`);

    const second = await registrar('/admissions/applications', {
      method: 'POST',
      body: JSON.stringify({
        roundId, firstNameTh: 'ปาริชาต', lastNameTh: 'ผู้สมัครสอง',
        nationalId: '1100000000002',
        choices: [{ preference: 1, curriculumVersionId: CV }],
      }),
    });
    await registrar(`/admissions/applications/${second.body.id}/submit`, { method: 'POST' });

    const over = await registrar(`/admissions/applications/${second.body.id}/decision`, {
      method: 'POST',
      body: JSON.stringify({ outcome: 'passed', curriculumVersionId: CV, rankNo: 2 }),
    });
    expect(over.status >= 400, `ที่นั่งเต็มแล้วควรถูกปฏิเสธ ได้ ${over.status}`);
    expect(/เต็มแล้ว/.test(JSON.stringify(over.body)), 'ข้อความควรบอกว่าที่นั่งเต็ม');

    const wl = await registrar(`/admissions/applications/${second.body.id}/decision`, {
      method: 'POST',
      body: JSON.stringify({ outcome: 'waitlisted', rankNo: 2 }),
    });
    expect(wl.status === 201, `ขึ้นสำรองควรทำได้ ได้ ${wl.status}`);
    return 'ผ่านเกินที่นั่งไม่ได้ · สำรองได้';
  });

  await check('API-65 รับเข้าเป็นนักศึกษาครบทุกชั้นและทำได้ครั้งเดียว', async () => {
    const r = await registrar(`/admissions/applications/${appId}/admit`, {
      method: 'POST',
      body: JSON.stringify({
        studentCode: '69ADM00001', academicYearId: AY, studyYear: 1, groupCode: 'ปวช.1/1',
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.studentId, 'ต้องได้รหัสนักศึกษากลับมา');

    // นักศึกษาที่รับเข้าต้องมีชั้นปีทันที มิฉะนั้นคิดค่าเทอมตามชั้นปีไม่ได้
    const places = await registrar(`/rollover/placements?academicYearId=${AY}`);
    expect(places.body.some((x: any) => x.student_code === '69ADM00001'),
      'นักศึกษาที่รับเข้าต้องมีชั้นปีทันที');

    const again = await registrar(`/admissions/applications/${appId}/admit`, {
      method: 'POST',
      body: JSON.stringify({ studentCode: '69ADM00099', academicYearId: AY }),
    });
    expect(again.status >= 400, `รับเข้าซ้ำควรถูกปฏิเสธ ได้ ${again.status}`);
    return `ได้นักศึกษา 69ADM00001 พร้อมชั้นปี`;
  });

  await check('API-66 สรุปยอดรับสมัครตรงกับความจริง', async () => {
    const r = await registrar(`/admissions/rounds/${roundId}/summary`);
    expect(r.status === 200, `ได้ ${r.status}`);
    const row = r.body[0];
    expect(Number(row.enrolled) === 1, `รับเข้าแล้ว 1 คน สรุปว่า ${row.enrolled}`);
    expect(Number(row.seats_left) === 0, `ที่นั่งเหลือควรเป็น 0 ได้ ${row.seats_left}`);
    return `${row.curriculum_th} · สมัคร ${row.applied} · ผ่าน ${row.passed} · รับเข้า ${row.enrolled}`;
  });

  await check('API-67 ครูผู้สอนเปิดข้อมูลผู้สมัครไม่ได้', async () => {
    // ใบสมัครมีเลขบัตรประชาชนและข้อมูลผู้เยาว์ ครูไม่มีหน้าที่เกี่ยวข้อง
    const a = await teacher('/admissions/rounds');
    expect(a.status === 403, `ควรได้ 403 ได้ ${a.status}`);
    const b = await teacher(`/admissions/applications?roundId=${roundId}`);
    expect(b.status === 403, `ควรได้ 403 ได้ ${b.status}`);
  });

  await check('API-68 วิทยาลัยอื่นไม่เห็นผู้สมัครของเรา', async () => {
    const r = await other('/admissions/rounds');
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.length === 0, `ควรไม่เห็นรอบของเรา เห็น ${r.body.length} รอบ`);
    const l = await other(`/admissions/applications?roundId=${roundId}`);
    expect(l.body.length === 0, `ควรไม่เห็นใบสมัคร เห็น ${l.body.length} ใบ`);
  });

  console.log('');
  console.log('══ แพ็กเกจและโควตา ══');

  await check('API-82 เส้นทางผู้ให้บริการที่กั้นด้วยกุญแจอย่างเดียวถูกตัดแล้ว', async () => {
    /*
     * การผูกแพ็กเกจและการดูปริมาณใช้งานย้ายไปหน้าจอผู้ให้บริการ (/platform/*)
     * ซึ่งรู้ว่าใครเป็นคนทำและบันทึกไว้ ต่างจากกุญแจที่ทั้งทีมใช้ร่วมกัน
     *
     * เทสต์ข้อนี้กันการเผลอเปิดกลับมา — เส้นทางที่ไม่มีใครรับผิดชอบ
     * เป็นสิ่งที่ถูกเพิ่มกลับได้ง่ายมากตอนรีบแก้ปัญหาหน้างาน
     */
    const key = { 'x-provision-key': process.env.PROVISION_KEY ?? '' };

    for (const path of ['/provisioning/subscriptions', '/provisioning/usage']) {
      const r = await anon(path, { method: 'POST', headers: key, body: '{}' });
      expect(r.status === 404, `${path} ควรถูกตัดแล้ว (404) ได้ ${r.status}`);
    }
    return 'ทั้งสองเส้นทางไม่มีแล้ว';
  });

  await check('API-83 วิทยาลัยเห็นโควตาของตัวเอง', async () => {
    // ใบเรียกเก็บที่ลูกค้าตรวจสอบเองไม่ได้คือใบที่จะถูกเถียงทุกงวด
    // (การเทียบว่าตัวเลขตรงกับฝั่งผู้ให้บริการอยู่ที่ PLAT-16 ซึ่งเข้าผ่าน
    //  หน้าจอผู้ให้บริการจริง ไม่ใช่ผ่านกุญแจ)
    const r = await director('/subscription');
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    const usage = (r.body as any).usage;
    expect(Number(usage.students_active) > 0, 'ต้องนับนักศึกษาได้');
    return `นักศึกษา ${usage.students_active} คน`;
  });

  await check('API-84 ครูเปิดข้อมูลแพ็กเกจไม่ได้', async () => {
    const r = await teacher('/subscription');
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ ระเบียนนักศึกษาฉบับเต็ม (0053) ══');

  await check('API-101 ระเบียนฉบับเต็มคืนครบทุกกลุ่มในคำขอเดียว', async () => {
    /*
     * หกกลุ่มข้อมูลอยู่คนละตาราง ถ้าให้หน้าจอยิงหกคำขอ ต้นทุนไม่ได้อยู่ที่
     * การอ่านข้อมูลแต่อยู่ที่**การวางแผนคำสั่ง** ซึ่งกางนโยบาย RLS ใหม่ทุกครั้ง
     */
    const up = await registrar(`/students/${F.student}/profile`, {
      method: 'PATCH',
      body: JSON.stringify({
        nicknameTh: 'ต้น', nationality: 'ไทย', siblingsCount: 3, birthOrder: 2,
        parentsMarital: 'together', classNumber: 7, travelMode: 'motorcycle',
      }),
    });
    expect(up.status < 400, `แก้ข้อมูลทั่วไปไม่สำเร็จ ${up.status} ${JSON.stringify(up.body)}`);

    for (const body of [
      { kind: 'registered', addressLine: '99/1 หมู่ 4', provinceTh: 'เชียงใหม่', postalCode: '50200' },
      { kind: 'current', addressLine: '12 ซอย 3', provinceTh: 'เชียงใหม่' },
    ]) {
      const r = await registrar(`/students/${F.student}/addresses`, {
        method: 'POST', body: JSON.stringify(body),
      });
      expect(r.status < 400, `บันทึกที่อยู่ไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    }

    const dad = await registrar(`/students/${F.student}/parents`, {
      method: 'POST',
      body: JSON.stringify({
        role: 'father', firstNameTh: 'สมชาย', lastNameTh: 'ใจดี',
        nationalId: '1234567890123', occupationTh: 'รับจ้าง', incomeMonthly: 15000,
      }),
    });
    expect(dad.status < 400, `บันทึกบิดาไม่สำเร็จ ${dad.status} ${JSON.stringify(dad.body)}`);

    const sen = await registrar(`/students/${F.student}/sensitive`, {
      method: 'POST',
      body: JSON.stringify({ bloodType: 'O', drugAllergy: 'แพ้เพนิซิลลิน', religion: 'พุทธ' }),
    });
    expect(sen.status < 400, `บันทึกข้อมูลอ่อนไหวไม่สำเร็จ ${sen.status} ${JSON.stringify(sen.body)}`);

    const pe = await registrar(`/students/${F.student}/prior-education`, {
      method: 'POST',
      body: JSON.stringify({ levelTh: 'ม.3', schoolTh: 'โรงเรียนทดสอบวิทยา', completedYearBe: 2568, gpax: 3.15 }),
    });
    expect(pe.status < 400, `บันทึกการศึกษาเดิมไม่สำเร็จ ${pe.status} ${JSON.stringify(pe.body)}`);

    // ตรวจวุฒิเป็นการ**รับรอง** ไม่ใช่การกรอก จึงเป็นคนละเส้นทาง
    const ver = await registrar(`/students/${F.student}/prior-education/${pe.body.id}/verify`, {
      method: 'POST', body: '{}',
    });
    expect(ver.status < 400, `ตรวจวุฒิไม่สำเร็จ ${ver.status}`);
    expect(ver.body.verified_at, 'ต้องคืนเวลาที่ตรวจวุฒิ');

    const adv = await registrar(`/students/${F.student}/advisors`, {
      method: 'POST', body: JSON.stringify({ staffId: F.staff, isPrimary: true }),
    });
    expect(adv.status < 400, `มอบหมายที่ปรึกษาไม่สำเร็จ ${adv.status} ${JSON.stringify(adv.body)}`);

    const p = await registrar(`/students/${F.student}/profile`);
    expect(p.status === 200, `ควรได้ 200 ได้ ${p.status}`);
    expect(p.body.nickname_th === 'ต้น', 'ชื่อเล่นไม่ถูกบันทึก');
    expect(p.body.class_number === 7, 'เลขที่ในห้องไม่ถูกบันทึก');
    expect(p.body.addresses.length === 2, `ที่อยู่ควรมี 2 ได้ ${p.body.addresses.length}`);
    expect(p.body.parents.length >= 1, 'ต้องเห็นข้อมูลบิดามารดา');
    expect(p.body.priorEducation.length >= 1, 'ต้องเห็นประวัติการศึกษาเดิม');
    expect(p.body.advisors.some((a: any) => !a.ended_on), 'ต้องมีที่ปรึกษาที่ยังไม่สิ้นสุด');
    expect(p.body.sensitive?.blood_type === 'O', 'ต้องเห็นข้อมูลอ่อนไหว');
    return 'ที่อยู่ บิดามารดา สุขภาพ การศึกษาเดิม ที่ปรึกษา ครบในคำขอเดียว';
  });

  await check('API-102 เลขบัตรประชาชนของบิดามารดาไม่โผล่กลับมา', async () => {
    /*
     * ฐานข้อมูลเก็บเฉพาะค่าแฮช หน้าจอจึงกรอกได้แต่อ่านกลับไม่ได้ — ถ้ามีวันไหน
     * ที่คอลัมน์นี้หลุดออกมาทาง API แปลว่ามีคนเปลี่ยนเป็นเก็บเลขจริง
     */
    const p = await registrar(`/students/${F.student}/profile`);
    const dad = p.body.parents.find((x: any) => x.role === 'father');
    expect(dad, 'ไม่พบข้อมูลบิดาจาก API-101');
    expect(dad.has_national_id === true, 'ควรบอกได้ว่ามีเลขบัตรเก็บไว้แล้ว');
    expect(!('national_id_hash' in dad) && !('national_id' in dad),
      'ต้องไม่คืนเลขบัตรหรือค่าแฮชออกมาเลย');

    // แก้ช่องอื่นโดยไม่ส่งเลขบัตร ต้องไม่ล้างค่าเดิมทิ้ง
    await registrar(`/students/${F.student}/parents`, {
      method: 'POST',
      body: JSON.stringify({ role: 'father', firstNameTh: 'สมชาย', occupationTh: 'ค้าขาย' }),
    });
    const after = await registrar(`/students/${F.student}/profile`);
    const dad2 = after.body.parents.find((x: any) => x.role === 'father');
    expect(dad2.has_national_id === true, 'การแก้ช่องอื่นไม่ควรล้างเลขบัตรที่เคยกรอกไว้');
    return 'คืนแค่ว่ามีหรือไม่มี และไม่ถูกล้างตอนแก้ช่องอื่น';
  });

  await check('API-103 ครูที่ปรึกษาเห็นข้อมูลอ่อนไหวของเด็กในที่ปรึกษาตัวเอง', async () => {
    const r = await teacher(`/students/${F.student}/profile`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(r.body.canSeeSensitive === true, 'ครูที่ปรึกษาควรมีสิทธิ์ดู');
    expect(r.body.sensitive?.drug_allergy, 'ต้องเห็นประวัติแพ้ยาของเด็กในที่ปรึกษา');
    return 'เห็นประวัติแพ้ยาได้ตามที่ออกแบบ';
  });

  await check('API-104 ครูที่ไม่ใช่ที่ปรึกษาเปิดระเบียนได้ แต่ข้อมูลอ่อนไหวเป็นว่าง', async () => {
    /*
     * จุดสำคัญคือ **ไม่ใช่ 403** — ครูผู้สอนต้องเปิดระเบียนดูเรื่องอื่นได้ตามปกติ
     * ถ้าโยน 403 เมื่ออ่านข้อมูลอ่อนไหวไม่ได้ ทั้งหน้าจอจะพังทั้งที่มีสิทธิ์เกือบทุกส่วน
     */
    await registrar(`/students/${F.studentBulkOk}/sensitive`, {
      method: 'POST', body: JSON.stringify({ bloodType: 'A', drugAllergy: 'ไม่มี' }),
    });

    const r = await teacher(`/students/${F.studentBulkOk}/profile`);
    expect(r.status === 200, `ต้องเปิดระเบียนได้ ไม่ใช่ 403 — ได้ ${r.status}`);
    expect(r.body.canSeeSensitive === false, 'ครูผู้สอนไม่ควรมีสิทธิ์ดูข้อมูลอ่อนไหว');
    expect(r.body.sensitive === null, 'ข้อมูลอ่อนไหวต้องเป็น null');
    expect(r.body.student_code, 'ยังต้องเห็นข้อมูลทั่วไปตามปกติ');
    return 'เปิดได้ 200 · sensitive = null · การสอนอยู่ไม่ให้สิทธิ์เห็นประวัติแพ้ยา';
  });

  await check('API-105 ครูแก้ข้อมูลอ่อนไหวไม่ได้แม้เป็นที่ปรึกษา', async () => {
    // ข้อมูลสุขภาพต้องมาจากเอกสารที่ผู้ปกครองกรอก ไม่ใช่จากความจำของครู
    const r = await teacher(`/students/${F.student}/sensitive`, {
      method: 'POST', body: JSON.stringify({ bloodType: 'AB' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-106 การเงินเห็นรายได้ผู้ปกครองแต่ไม่เห็นข้อมูลสุขภาพ', async () => {
    /*
     * ต้องใช้นักศึกษาที่ผู้เรียก**ไม่ได้เป็นที่ปรึกษา** เพราะ may_see_sensitive()
     * ให้สิทธิ์ตามความสัมพันธ์ที่ปรึกษาโดยไม่สนบทบาทที่ล็อกอินเข้ามา —
     * คนเดียวกันที่เป็นที่ปรึกษาอยู่ ต่อให้เข้าด้วยบทบาทการเงินก็ยังเห็นของเด็กตัวเอง
     */
    await registrar(`/students/${F.studentBulkOk}/parents`, {
      method: 'POST', body: JSON.stringify({ role: 'mother', firstNameTh: 'ทดสอบ', incomeMonthly: 9000 }),
    });

    const r = await finance(`/students/${F.studentBulkOk}/profile`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(r.body.parents.length >= 1, 'การเงินต้องเห็นรายได้ผู้ปกครองเพื่อพิจารณาทุนและ กยศ.');
    expect(r.body.sensitive === null && r.body.canSeeSensitive === false,
      'การเงินไม่ควรเห็นข้อมูลสุขภาพ');
    return 'เห็นรายได้ ไม่เห็นสุขภาพ';
  });

  await check('API-107 นักศึกษาอ่านระเบียนตัวเองได้ แต่แก้ไม่ได้', async () => {
    const r = await student(`/students/${F.student}/profile`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(r.body.sensitive, 'เจ้าตัวควรเห็นข้อมูลของตัวเอง');

    const w = await student(`/students/${F.student}/profile`, {
      method: 'PATCH', body: JSON.stringify({ nicknameTh: 'แก้เอง' }),
    });
    expect(w.status === 403, `ควรได้ 403 ได้ ${w.status}`);

    const w2 = await student(`/students/${F.student}/sensitive`, {
      method: 'POST', body: JSON.stringify({ bloodType: 'AB' }),
    });
    expect(w2.status === 403, `แก้ข้อมูลสุขภาพของตัวเองควรได้ 403 ได้ ${w2.status}`);
    return 'อ่านได้ · แก้ไม่ได้ทั้งข้อมูลทั่วไปและข้อมูลสุขภาพ';
  });

  await check('API-108 มอบหมายที่ปรึกษาคนใหม่ต้องปิดคนเดิม ไม่ใช่ชนดัชนี', async () => {
    /*
     * `student_advisor_primary` เป็น unique บางส่วนของที่ปรึกษาหลักที่ยัง
     * ไม่สิ้นสุด ถ้าชั้น API ไม่ปิดของเดิมให้ การเปลี่ยนที่ปรึกษาจะล้มด้วย
     * ข้อความจากดัชนีที่ผู้ใช้อ่านไม่รู้เรื่อง
     */
    const again = await registrar(`/students/${F.student}/advisors`, {
      method: 'POST', body: JSON.stringify({ staffId: F.staff, isPrimary: true }),
    });
    expect(again.status < 400, `มอบหมายซ้ำควรสำเร็จ ได้ ${again.status} ${JSON.stringify(again.body)}`);

    const p = await registrar(`/students/${F.student}/profile`);
    const live = p.body.advisors.filter((a: any) => !a.ended_on);
    expect(live.length === 1, `ที่ปรึกษาที่ยังไม่สิ้นสุดควรเหลือคนเดียว ได้ ${live.length}`);
    expect(p.body.advisors.some((a: any) => a.ended_on),
      'คนเดิมต้องถูกปิดด้วย ended_on ไม่ใช่ลบทิ้ง — ต้องรู้ย้อนหลังว่าใครดูแลอยู่ตอนเกิดเรื่อง');
    return `ประวัติ ${p.body.advisors.length} รายการ · ยังดูแลอยู่ 1 คน`;
  });

  await check('API-109 รายชื่อเด็กในที่ปรึกษาคืนเฉพาะของผู้เรียก', async () => {
    const r = await teacher('/students/advisees');
    // 400 ที่นี่แปลว่าเส้นทางถูก @Get(':id') จับกินไปแล้ว — ParseUuidPipe
    // จะปฏิเสธคำว่า 'advisees' ด้วยข้อความที่อธิบายอะไรไม่ได้เลย
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status} — 400 แปลว่าถูก :id จับกิน`);
    expect(Array.isArray(r.body), 'ควรคืนอาร์เรย์');
    expect(r.body.some((s: any) => s.id === F.student), 'ต้องเห็นเด็กในที่ปรึกษาตัวเอง');
    expect(!r.body.some((s: any) => s.id === F.studentBulkOk),
      'ต้องไม่เห็นนักศึกษาที่ไม่ได้อยู่ในที่ปรึกษา');
    return `${r.body.length} คน`;
  });

  await check('API-110 มอบหมายที่ปรึกษาเป็นกลุ่มคืนผลรายคน', async () => {
    // หลักเดียวกับ register_courses_bulk — คนหนึ่งล้มต้องไม่ทำให้ทั้งห้องล้ม
    const r = await registrar('/advisors/bulk', {
      method: 'POST',
      body: JSON.stringify({
        staffId: F.staff,
        studentIds: [F.studentBulkOk, F.studentBulkHeld, '00000000-0000-0000-0000-000000000000'],
      }),
    });
    expect(r.status < 400, `ควรสำเร็จ ได้ ${r.status} ${JSON.stringify(r.body)}`);
    expect(r.body.total === 3, `ควรรายงานครบ 3 คน ได้ ${r.body.total}`);
    expect(r.body.ok === 2, `สองคนที่มีจริงควรผ่าน ได้ ${r.body.ok}`);
    expect(r.body.results.some((x: any) => !x.ok),
      'คนที่ไม่มีตัวตนต้องรายงานว่าล้ม ไม่ใช่ทำให้ทั้งชุดล้ม');
    return `${r.body.ok}/${r.body.total} สำเร็จ`;
  });

  await check('API-111 วิทยาลัยอื่นเปิดระเบียนของเราไม่ได้', async () => {
    const r = await other(`/students/${F.student}/profile`);
    expect(r.status === 404, `ควรได้ 404 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ การลาของนักศึกษา (0054) ══');

  let stuLeaveId = '';

  /*
   * วันที่ที่มีคาบเรียนจริงของนักศึกษาคนนี้ — ต้องมีคาบ มิฉะนั้น API-114
   * จะผ่านโดยไม่ได้พิสูจน์อะไร (อนุมัติได้แต่ไม่มีอะไรให้ปรับ)
   * ผลที่ตาราง attendance_record พิสูจน์ละเอียดที่ TEST 237–239 ฝั่ง DB
   */
  const meetingDays = await registrar(`/academic/sections/${F.section}/meetings`);
  const LEAVE_DAY: string =
    (meetingDays.body?.[0]?.meets_on ?? '2026-06-01').slice(0, 10);

  await check('API-112 นักศึกษายื่นใบลาของตัวเองได้ แต่อนุมัติเองไม่ได้', async () => {
    const r = await student('/leaves', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, kind: 'sick',
        fromDate: LEAVE_DAY, toDate: LEAVE_DAY,
        reason: 'เป็นไข้ มีใบรับรองแพทย์',
      }),
    });
    expect(r.status < 400, `ยื่นใบลาไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    stuLeaveId = r.body.id;
    expect(r.body.status === 'submitted', `สถานะเริ่มต้นควรเป็น submitted ได้ ${r.body.status}`);

    // เส้นทางอนุมัติปิดไว้ที่ @Roles แล้ว และฐานข้อมูลปิดซ้ำอีกชั้น
    const d = await student(`/leaves/${stuLeaveId}/decision`, {
      method: 'POST', body: JSON.stringify({ decision: 'approve' }),
    });
    expect(d.status === 403, `ควรได้ 403 ได้ ${d.status}`);
    return 'ยื่นได้ · อนุมัติเองไม่ได้';
  });

  await check('API-113 ครูผู้สอนอนุมัติใบลาไม่ได้', async () => {
    /*
     * ครูเขียน attendance_record ของกลุ่มตัวเองได้อยู่แล้ว ข้อนี้จึงพิสูจน์ว่า
     * "เขียนเวลาเรียนได้" ไม่เท่ากับ "อนุมัติใบลาได้" — ใบลาหนึ่งใบมีผลกับ
     * ทุกวิชาที่นักศึกษาลงทะเบียน ไม่ใช่แค่วิชาของครูคนที่กด
     */
    const r = await teacher(`/leaves/${stuLeaveId}/decision`, {
      method: 'POST', body: JSON.stringify({ decision: 'approve' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-114 อนุมัติแล้วเวลาเรียนเปลี่ยนจริง', async () => {
    /*
     * ใบลาที่ไม่แตะเวลาเรียนคือใบลาที่ไม่มีประโยชน์ — กฎ 80% จะยังตัดสิทธิ์
     * คนที่ลาป่วยโดยมีใบรับรองแพทย์อยู่ดี ข้อนี้จึงยืนยันผลที่ตารางจริง
     * ไม่ใช่ยืนยันแค่ว่าสถานะใบเปลี่ยนเป็น approved
     */
    const r = await registrar(`/leaves/${stuLeaveId}/decision`, {
      method: 'POST',
      body: JSON.stringify({ decision: 'approve', note: 'มีใบรับรองแพทย์' }),
    });
    expect(r.status < 400, `อนุมัติไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    expect(r.body.status === 'approved', `ควรเป็น approved ได้ ${r.body.status}`);
    expect(r.body.applied_periods !== undefined && r.body.skipped_present !== undefined,
      'ต้องรายงานทั้งจำนวนคาบที่ปรับได้และจำนวนที่ข้าม');

    const list = await registrar('/leaves?status=approved');
    const mine = list.body.find((x: any) => x.id === stuLeaveId);
    expect(mine, 'ใบที่อนุมัติแล้วต้องอยู่ในรายการ');
    expect(mine.decided_by_name, 'ต้องบอกได้ว่าใครอนุมัติ');
    return `ปรับ ${r.body.applied_periods} คาบ · ข้าม ${r.body.skipped_present} คาบ`;
  });

  await check('API-115 อนุมัติซ้ำใบเดิมไม่ได้', async () => {
    // ถ้าอนุมัติซ้ำได้ จะเขียน student_leave_applied รอบสองด้วยค่า "เดิม"
    // ที่เป็นผลของรอบแรก แล้วการยกเลิกจะคืนค่ากลับเป็นสถานะลา ไม่ใช่ค่าจริง
    const r = await registrar(`/leaves/${stuLeaveId}/decision`, {
      method: 'POST', body: JSON.stringify({ decision: 'reject' }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-116 ยกเลิกใบลาที่อนุมัติแล้วคืนค่าเวลาเรียน', async () => {
    const r = await registrar(`/leaves/${stuLeaveId}/cancel`, {
      method: 'POST', body: JSON.stringify({ reason: 'ยื่นผิดวัน' }),
    });
    expect(r.status < 400, `ยกเลิกไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    expect(r.body.reverted !== undefined, 'ต้องรายงานจำนวนแถวที่คืนค่า');

    const list = await registrar('/leaves');
    const mine = list.body.find((x: any) => x.id === stuLeaveId);
    expect(mine.status === 'cancelled', `ควรเป็น cancelled ได้ ${mine.status}`);
    expect(Number(mine.applied_periods) === 0, 'ยกเลิกแล้วจำนวนคาบที่ปรับต้องเป็น 0');
    return `คืนค่า ${r.body.reverted} แถว`;
  });

  await check('API-117 งานทะเบียนบันทึกใบลากระดาษแล้วอนุมัติเองได้', async () => {
    /*
     * เส้นทางที่ใช้บ่อยที่สุดจริง ๆ — นักศึกษาส่งใบลาเป็นกระดาษ เจ้าหน้าที่
     * พิมพ์เข้าระบบแล้วอนุมัติ กฎเดิมเขียนว่า "ผู้ยื่นอนุมัติเองไม่ได้"
     * ซึ่งไปกันเจ้าหน้าที่คนที่พิมพ์ ผลคือวิทยาลัยที่มีเจ้าหน้าที่ทะเบียน
     * คนเดียวใช้ฟีเจอร์นี้ไม่ได้เลย — เจอตอนกดปุ่มจริงบนหน้าจอ ไม่ใช่ตอน
     * เขียนเทสต์ เพราะเทสต์ข้ออื่นยื่นด้วยบัญชีนักศึกษาทุกข้อ
     */
    const mk = await registrar('/leaves', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, kind: 'personal',
        fromDate: LEAVE_DAY, toDate: LEAVE_DAY, reason: 'ใบลากระดาษที่รับมาหน้าเคาน์เตอร์',
      }),
    });
    expect(mk.status < 400, `บันทึกแทนไม่สำเร็จ ${mk.status} ${JSON.stringify(mk.body)}`);

    const ok = await registrar(`/leaves/${mk.body.id}/decision`, {
      method: 'POST', body: JSON.stringify({ decision: 'approve' }),
    });
    expect(ok.status < 400,
      `เจ้าหน้าที่ที่บันทึกใบต้องอนุมัติเองได้ ได้ ${ok.status} ${JSON.stringify(ok.body)}`);

    const r = await registrar(`/leaves/${mk.body.id}/cancel`, {
      method: 'POST', body: JSON.stringify({ reason: '   ' }),
    });
    expect(r.status >= 400, `ยกเลิกโดยไม่ระบุเหตุผลควรถูกปฏิเสธ ได้ ${r.status}`);
    return 'บันทึก · อนุมัติเอง · และยกเลิกโดยไม่ระบุเหตุผลไม่ได้';
  });

  await check('API-118 นักศึกษายื่นใบลาให้คนอื่นไม่ได้', async () => {
    /*
     * นโยบาย leave_insert เทียบ student_id กับ actor_student_ids() ซึ่ง
     * เป็นของตัวเองและบุตรหลานเท่านั้น — ถ้าช่องนี้เปิด นักศึกษาจะยื่นใบลา
     * ให้เพื่อนแล้วรอเจ้าหน้าที่กดอนุมัติ ซึ่งเป็นการลบเวลาขาดเรียนของคนอื่น
     */
    const r = await student('/leaves', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.studentBulkOk, kind: 'sick',
        fromDate: '2026-03-03', toDate: '2026-03-03', reason: 'ยื่นแทนเพื่อน',
      }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-119 สรุปวันลารายคนตอบได้', async () => {
    // คำถามที่ไม่มีใครตอบได้เลยก่อนมี 0054 เพราะการลาอยู่ในสถานะเช็คชื่อ
    // รายคาบเท่านั้น ไม่มีที่ไหนบอกว่า "คนนี้ลาไปกี่วัน"
    const r = await registrar(`/leaves/summary/${F.student}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(Array.isArray(r.body), 'ควรคืนอาร์เรย์');
    return `${r.body.length} ประเภท`;
  });

  await check('API-120 ครูที่ปรึกษาเห็นเฉพาะใบลาของเด็กในที่ปรึกษาตัวเอง', async () => {
    /*
     * ต้องมีใบลาของคนที่**ไม่ใช่**เด็กในที่ปรึกษาอยู่จริงในระบบตอนตรวจ
     * มิฉะนั้นข้อนี้จะผ่านเพราะไม่มีอะไรให้เห็น ไม่ใช่เพราะนโยบายกันไว้
     * (F.studentRegrade ไม่ได้ถูกมอบหมายที่ปรึกษาใน API-108/110)
     */
    const other = await registrar('/leaves', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.studentRegrade, kind: 'sick',
        fromDate: LEAVE_DAY, toDate: LEAVE_DAY, reason: 'ใบลาของนักศึกษาคนอื่น',
      }),
    });
    expect(other.status < 400, `เตรียมข้อมูลไม่สำเร็จ ${other.status}`);

    const r = await teacher('/leaves');
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(r.body.some((x: any) => x.student_id === F.student),
      'ครูที่ปรึกษาต้องเห็นใบลาของเด็กในที่ปรึกษา');
    expect(!r.body.some((x: any) => x.id === other.body.id),
      'ต้องไม่เห็นใบลาของนักศึกษาที่ไม่ได้อยู่ในที่ปรึกษา');
    return `${r.body.length} ใบ`;
  });

  console.log('');
  console.log('══ หนังสือถึงผู้ปกครองและใบรับรองความประพฤติ (0055) ══');

  await check('API-121 รายชื่อผู้ที่ควรได้รับจดหมายแจ้งขาดเรียน', async () => {
    /*
     * หน้าจอต้องไม่ต้องเดาว่าจะออกจดหมายให้ใคร — `last_notice_on` เป็น null
     * แปลว่ายังไม่เคยส่ง ไม่ใช่ส่งแล้วไม่ได้ผล ซึ่งเป็นความต่างที่คนทำงาน
     * ต้องเห็น มิฉะนั้นจะส่งซ้ำคนเดิมทุกสัปดาห์
     */
    const r = await registrar(`/documents/absence-candidates/${TERM1}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(Array.isArray(r.body), 'ควรคืนอาร์เรย์');
    if (r.body.length > 0) {
      const x = r.body[0];
      expect(x.student_code && x.courses_at_risk !== undefined,
        'ต้องบอกรหัสนักศึกษาและจำนวนวิชาที่ตกเกณฑ์');
      expect('last_notice_on' in x, 'ต้องบอกว่าเคยออกจดหมายล่าสุดเมื่อไร');
    }
    return `${r.body.length} คน`;
  });

  let noticeId = '';

  await check('API-122 จดหมายแจ้งขาดเรียนไม่มี GPAX แต่มีที่อยู่ผู้ปกครอง', async () => {
    /*
     * payload ของ `issue_document()` มี `summary`/`graduation` ทุกใบ
     * ถ้าหนังสือใช้ส่วนหัวเดียวกัน GPAX จะติดมาโดยไม่มีอะไรฟ้อง แล้วกลายเป็น
     * การเก็บข้อมูลเกินจำเป็นในที่ที่ลบไม่ได้ (หลักข้อ 5ก · PDPA ม.22)
     */
    const cand = await registrar(`/documents/absence-candidates/${TERM1}`);
    const target = cand.body.find((x: any) => x.student_id === F.student) ?? cand.body[0];
    if (!target) return 'ข้าม — ไม่มีผู้ที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคนี้';

    const r = await registrar('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({
        studentId: target.student_id, kind: 'absence_notice', termId: TERM1,
      }),
    });
    expect(r.status < 400, `ออกจดหมายไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    noticeId = r.body.id;

    const pl = r.body.payload;
    expect(!('summary' in pl) && !('graduation' in pl),
      'จดหมายแจ้งขาดเรียนต้องไม่มี GPAX หรือข้อมูลการจบติดมาด้วย');
    expect(Array.isArray(pl.recipients), 'ต้องมีรายชื่อผู้รับ');
    expect(Array.isArray(pl.courses) && pl.courses.length > 0,
      'ต้องมีรายวิชาที่ตกเกณฑ์');
    return `เลขที่ ${r.body.doc_no} · ${pl.courses.length} วิชา`;
  });

  await check('API-123 พิมพ์จดหมายได้เป็น HTML ที่ไม่อ้างไฟล์ภายนอก', async () => {
    if (!noticeId) return 'ข้าม — ไม่มีจดหมายจาก API-122';
    const r = await registrar(`/documents/${noticeId}/print`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    const html = String(r.body);
    expect(html.includes('<!doctype html>'), 'ควรได้หน้า HTML เต็มหน้า');
    expect(html.includes('ส่วนตอบรับ'),
      'จดหมายแจ้งขาดเรียนต้องมีท่อนตัดกลับให้ผู้ปกครองเซ็นชื่อส่งคืน');
    // พิมพ์ได้แม้อินเทอร์เน็ตของวิทยาลัยล่ม
    expect(!/(src|href)\s*=\s*["']https?:/i.test(html),
      'แม่แบบต้องไม่อ้างไฟล์ภายนอกเลย');
    return `${html.length} ตัวอักษร`;
  });

  await check('API-124 ตำแหน่งใต้ลายเซ็นต้องตรงกับคนที่ชื่ออยู่ตรงนั้น', async () => {
    /*
     * แม่แบบเดิมเขียน `advisor ?? issued_by` แล้วพิมพ์ "ครูที่ปรึกษา" ใต้ชื่อ
     * เสมอ ผลคือนักศึกษาที่ยังไม่ได้มอบหมายที่ปรึกษา (สภาพเริ่มต้นของทุกคน)
     * ได้จดหมายที่ระบุว่าเจ้าหน้าที่ทะเบียนเป็นครูที่ปรึกษาของตัวเอง —
     * ข้อความเท็จบนเอกสารที่ส่งถึงบ้านและแก้ไม่ได้อีกเลย
     */
    // F.studentRegrade ไม่ได้ถูกมอบหมายที่ปรึกษาใน API-108 หรือ API-110
    // — ต้องเป็นคนที่ไม่มีที่ปรึกษาจริง มิฉะนั้นข้อนี้ข้ามแล้วไม่พิสูจน์อะไร
    const notice = await registrar('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.studentRegrade, kind: 'guardian_invitation',
        meetOn: '2026-09-20', placeTh: 'ห้องประชุม',
      }),
    });
    expect(notice.status < 400, `ออกหนังสือไม่สำเร็จ ${notice.status} ${JSON.stringify(notice.body)}`);
    expect(!notice.body.payload.advisor,
      'ข้อนี้ต้องใช้นักศึกษาที่ยังไม่มีที่ปรึกษา — ถ้ามีแล้วให้เปลี่ยนตัวอย่าง');

    const html = String((await registrar(`/documents/${notice.body.id}/print`)).body);
    expect(!html.includes('ครูที่ปรึกษา'),
      'ยังไม่มีที่ปรึกษา แต่หนังสือระบุว่ามี — ข้อความเท็จบนเอกสารที่แก้ไม่ได้');
    expect(html.includes('ผู้ออกหนังสือ'),
      'ต้องระบุตำแหน่งที่ตรงกับคนที่ลงนามจริง');
    return 'ไม่มีที่ปรึกษา → ลงนามในฐานะผู้ออกหนังสือ';
  });

  await check('API-128 หนังสือเชิญผู้ปกครองต้องมีวันนัดพบ', async () => {
    const none = await registrar('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'guardian_invitation' }),
    });
    expect(none.status >= 400, `ควรถูกปฏิเสธ ได้ ${none.status}`);

    const r = await registrar('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, kind: 'guardian_invitation',
        meetOn: '2026-09-15', meetTime: '10:00 น.',
        placeTh: 'ห้องงานปกครอง อาคาร 1', reasonTh: 'ปรึกษาเรื่องเวลาเรียน',
      }),
    });
    expect(r.status < 400, `ออกหนังสือไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    expect(r.body.payload.meeting?.meet_on, 'ต้องเก็บวันนัดพบไว้ใน payload');

    const html = String((await registrar(`/documents/${r.body.id}/print`)).body);
    expect(html.includes('ห้องงานปกครอง'), 'หน้าที่พิมพ์ต้องมีสถานที่นัดพบ');
    return `เลขที่ ${r.body.doc_no}`;
  });

  await check('API-129 ใบรับรองความประพฤติออกได้และพิมพ์ได้', async () => {
    const r = await registrar('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, kind: 'conduct_certificate', purposeTh: 'สมัครงาน',
      }),
    });
    expect(r.status < 400, `ออกใบรับรองไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    expect(r.body.payload.behavior, 'ต้องมีข้อมูลความประพฤติ');
    expect(r.body.payload.behavior.deduct_count !== undefined,
      'ต้องนับจำนวนครั้งที่ถูกหักคะแนน — คะแนนเต็มเพราะไม่เคยมีประวัติ กับเต็มเพราะชดเชยแล้ว คนละเรื่อง');

    const html = String((await registrar(`/documents/${r.body.id}/print`)).body);
    expect(html.includes('ใบรับรองความประพฤติ'), 'หน้าที่พิมพ์ต้องเป็นใบรับรองความประพฤติ');
    return `เลขที่ ${r.body.doc_no}`;
  });

  await check('API-130 ครูผู้สอนออกหนังสือถึงผู้ปกครองไม่ได้', async () => {
    // ครูเห็นว่าใครตกเกณฑ์ได้ (ต้องใช้สอน) แต่การออกหนังสือในนามวิทยาลัย
    // เป็นงานของงานปกครองและงานทะเบียน
    const see = await teacher(`/documents/absence-candidates/${TERM1}`);
    expect(see.status === 200, `ครูควรเห็นรายชื่อได้ ได้ ${see.status}`);

    const r = await teacher('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'conduct_certificate' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-131 นักศึกษาออกใบรับรองให้ตัวเองไม่ได้', async () => {
    const r = await student('/documents/letters', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'conduct_certificate' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ พฤติกรรม คัดกรอง และเยี่ยมบ้าน (0056) ══');

  let deductRule = '';

  await check('API-132 ตั้งกฎพฤติกรรมและมองเห็นได้ทั้งวิทยาลัย', async () => {
    // กฎที่ไม่มีใครรู้ล่วงหน้าไม่ใช่กฎ — นักศึกษาต้องเห็นว่าทำอะไรแล้วถูกหักเท่าไร
    const mk = await director('/behavior/rules', {
      method: 'POST',
      body: JSON.stringify({
        code: 'LATE-01', nameTh: 'มาสายเกิน 15 นาที', direction: 'deduct', points: 5,
      }),
    });
    expect(mk.status < 400, `สร้างกฎไม่สำเร็จ ${mk.status} ${JSON.stringify(mk.body)}`);
    deductRule = mk.body.id;

    const seen = await student('/behavior/rules');
    expect(seen.status === 200, `นักศึกษาควรอ่านกฎได้ ได้ ${seen.status}`);
    expect(seen.body.some((r: any) => r.id === deductRule), 'นักศึกษาต้องเห็นกฎที่ประกาศใช้');
    return `${seen.body.length} ข้อ`;
  });

  await check('API-133 นักศึกษาตั้งกฎเองไม่ได้', async () => {
    const r = await student('/behavior/rules', {
      method: 'POST',
      body: JSON.stringify({ code: 'HACK', nameTh: 'ให้คะแนนตัวเอง', direction: 'award', points: 99 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  let recordId = '';

  await check('API-134 บันทึกพฤติกรรมแล้วคืนยอดใหม่มาด้วย', async () => {
    /*
     * คนบันทึกต้องรู้ทันทีว่าคนนี้ตกเกณฑ์แล้วหรือยัง ถ้าไม่คืนยอดมาด้วย
     * หน้าจอต้องยิงอีกคำขอเพื่อรู้เรื่องเดียวกัน — และคนที่ไม่ยิงจะไม่รู้เลย
     */
    const r = await teacher('/behavior/records', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, ruleId: deductRule, detail: 'มาสายคาบแรก',
      }),
    });
    expect(r.status < 400, `บันทึกไม่สำเร็จ ${r.status} ${JSON.stringify(r.body)}`);
    recordId = r.body.id;
    expect(r.body.points === 5, `ควรใช้คะแนนของกฎ (5) ได้ ${r.body.points}`);
    expect(r.body.status?.balance !== undefined, 'ต้องคืนยอดคะแนนใหม่มาด้วย');
    expect(r.body.status?.band, 'ต้องคืนระดับเตือนมาด้วย ไม่ใช่ตัวเลขเปล่า');
    return `ยอดคงเหลือ ${r.body.status.balance} · ระดับ ${r.body.status.band}`;
  });

  await check('API-135 นักศึกษาบันทึกพฤติกรรมของตัวเองไม่ได้', async () => {
    /*
     * ก่อน 0056 ยิง SQL ตรงแล้วนักศึกษาให้คะแนนตัวเอง 50 คะแนน แก้คะแนน
     * ที่ถูกหักเป็น 0 และลบประวัติทั้งหมดของตัวเองได้ (ยอด 90 → 100)
     * ข้อนี้ปิดที่ชั้น API ส่วนชั้นฐานข้อมูลปิดที่ TEST 251
     */
    const r = await student('/behavior/records', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, ruleId: deductRule }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);

    const del = await student(`/behavior/records/${recordId}`, { method: 'DELETE' });
    expect(del.status === 403, `ลบประวัติของตัวเองควรได้ 403 ได้ ${del.status}`);
  });

  await check('API-136 นักศึกษาอ่านคะแนนของตัวเองได้', async () => {
    // การปิดช่องเขียนต้องไม่ปิดการอ่านไปด้วย — นโยบาย restrictive แบบ
    // for all กิน select ซึ่งเป็นกับดักที่เจอมาแล้วใน 0053
    const r = await student(`/behavior/students/${F.student}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(r.body.status?.balance !== undefined, 'ต้องเห็นยอดคะแนนของตัวเอง');
    expect(r.body.records.length > 0, 'ต้องเห็นประวัติของตัวเอง');
    return `${r.body.records.length} รายการ · ยอด ${r.body.status.balance}`;
  });

  await check('API-137 รายชื่อผู้ที่คะแนนต่ำกว่าเกณฑ์', async () => {
    const r = await director('/behavior/watchlist');
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(Array.isArray(r.body), 'ควรคืนอาร์เรย์');
    // ทุกแถวต้องไม่ใช่ 'ok' มิฉะนั้นรายการเฝ้าระวังจะเต็มไปด้วยคนปกติ
    expect(r.body.every((x: any) => x.band !== 'ok'), 'ต้องไม่มีคนที่คะแนนปกติในรายการ');
    return `${r.body.length} คน`;
  });

  await check('API-138 บันทึกผลคัดกรองและเยี่ยมบ้าน', async () => {
    const sc = await director('/behavior/screenings', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, instrument: 'SDQ', assessedOn: '2026-06-01',
        band: 'at_risk', score: 18,
      }),
    });
    expect(sc.status < 400, `บันทึกผลคัดกรองไม่สำเร็จ ${sc.status} ${JSON.stringify(sc.body)}`);

    const hv = await director('/behavior/home-visits', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, visitedOn: '2026-06-10',
        findings: 'อาศัยกับยาย', followUp: 'ติดตามอีกครั้งภาคหน้า',
      }),
    });
    expect(hv.status < 400, `บันทึกเยี่ยมบ้านไม่สำเร็จ ${hv.status} ${JSON.stringify(hv.body)}`);

    const list = await director(`/behavior/screenings/${F.student}`);
    expect(list.body.length > 0, 'ต้องเห็นผลคัดกรองที่เพิ่งบันทึก');
    return `คัดกรอง ${list.body.length} ครั้ง`;
  });

  await check('API-139 ครูผู้สอนเปิดผลคัดกรองไม่ได้', async () => {
    /*
     * ต้องได้ 403 ไม่ใช่อาร์เรย์ว่าง — อาร์เรย์ว่างอ่านได้ว่า "ยังไม่เคย
     * คัดกรอง" ซึ่งทำให้ครูไปถามเจ้าตัวหรือผู้ปกครองเอง แล้วข้อมูลอ่อนไหว
     * จะไปอยู่นอกระบบ (เหตุผลเดียวกับแท็บข้อมูลอ่อนไหวใน 0053)
     */
    const r = await teacher(`/behavior/screenings/${F.student}`);
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-140 ปิดกฎแทนการลบ เพื่อไม่ให้ประวัติเก่าเสียความหมาย', async () => {
    const r = await director(`/behavior/rules/${deductRule}`, { method: 'DELETE' });
    expect(r.status < 400, `ปิดกฎไม่สำเร็จ ${r.status}`);

    const active = await director('/behavior/rules');
    expect(!active.body.some((x: any) => x.id === deductRule), 'กฎที่ปิดแล้วต้องไม่อยู่ในรายการปกติ');

    const all = await director('/behavior/rules?all=true');
    expect(all.body.some((x: any) => x.id === deductRule), 'แต่ต้องยังค้นเจอได้ เพราะประวัติเก่าอ้างอยู่');

    // ประวัติที่บันทึกไว้ยังต้องอ่านได้และยังรู้ว่าหักด้วยเหตุผลอะไร
    const hist = await director(`/behavior/students/${F.student}`);
    const old = hist.body.records.find((x: any) => x.id === recordId);
    expect(old?.rule_th, 'ประวัติเก่าต้องยังบอกได้ว่าหักด้วยกฎข้อไหน');
    return 'ปิดแล้วแต่ประวัติยังอ่านได้';
  });

  console.log('');
  console.log('══ การตรวจสอบข้อมูลเข้า ══');

  await check('API-22 ข้อมูลผิดรูปแบบถูกปฏิเสธก่อนถึงฐานข้อมูล', async () => {
    const r = await registrar('/registration/check', {
      method: 'POST',
      body: JSON.stringify({ studentId: 'ไม่ใช่ uuid', termId: TERM1, sectionIds: [] }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await check('API-23 ฟิลด์แปลกปลอมถูกปฏิเสธ', async () => {
    const r = await registrar('/registration/check', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, termId: TERM1, sectionIds: [], isAdmin: true,
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await app.close();

  console.log('');
  if (failures.length) {
    console.log(`════ ล้มเหลว ${failures.length} ข้อ จากทั้งหมด ${passed + failures.length} ════`);
    for (const f of failures) console.log(`  ✕ ${f}`);
    process.exit(1);
  }
  console.log(`════ ทดสอบ API ผ่านครบ ${passed} ข้อ ════`);
}

main().catch((err) => {
  console.error('เทสต์ล้มเหลว:', err);
  process.exit(1);
});

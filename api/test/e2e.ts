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
/** ฉบับ 2562 — มีอยู่ใน seed แต่ไม่มีรายวิชาผูกไว้ ใช้ทดสอบห้องที่คละหลักสูตร */
const CV_OLD = '77777777-7777-7777-7777-777777777762';
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
  // คนนี้อยู่ในห้องแต่ยังไม่ได้ผูกหลักสูตร — ทำให้ "วิชานี้ของทั้งห้องไหม" เป็นเท็จ
  personNoPlan: '10000000-0000-0000-0000-0000000000d1',
  studentNoPlan: '10000000-0000-0000-0000-0000000000d2',
  // คนนี้อยู่ในห้องและยังไม่มีรายวิชาเลย — เป็นตัวพิสูจน์ว่าการกดลงทั้งห้อง
  // ทำให้ตัวเลข "ยังไม่ลง" ลดลงจริง ไม่ใช่แค่คืน 200 กลับมา
  personRoomFresh: '10000000-0000-0000-0000-0000000000d3',
  studentRoomFresh: '10000000-0000-0000-0000-0000000000d4',
  // คนนี้อยู่ห้องเดียวกันแต่สังกัดหลักสูตร**คนละฉบับ** — ห้องที่คละหลักสูตร
  // มีจริง (ตกซ้ำชั้น · ย้ายหลักสูตร) และเป็นเหตุผลทั้งหมดที่ต้องรายงาน
  // ความครอบคลุมของแต่ละวิชา แทนที่จะติ๊กให้ทั้งห้องแล้วจบ
  personOtherPlan: '10000000-0000-0000-0000-0000000000d5',
  studentOtherPlan: '10000000-0000-0000-0000-0000000000d6',
  // ห้องเป็นข้อมูลจริงตั้งแต่ 0034 ไม่ใช่ข้อความอิสระ
  room: '30000000-0000-0000-0000-0000000000e1',
  roomLecture: '30000000-0000-0000-0000-0000000000e2',
  // ── ตารางสอบ — ชุดฟิกซ์เจอร์แยกทั้งหมด ไม่แตะ F.section/F.student เลย ──
  //
  // ครั้งแรกที่เขียนพลาดใช้ F.section/F.student ร่วมกับข้อมูลใหม่ แล้วทำให้
  // API-07 (คาดว่า F.student ยังไม่เคยลง F.section มาก่อน) · API-09/API-12
  // (คาดจำนวนคนในกลุ่มเรียน/รายวิชาที่เห็นเป็นตัวเลขตายตัว) ล้มทั้งชุด เพราะ
  // ไฟล์นี้ทดสอบแบบมีสถานะร่วมกันตลอดทั้งไฟล์ ไม่ได้แยก transaction ต่อเทสต์
  // เหมือนเทสต์ระดับฐานข้อมูล — ฟิกซ์เจอร์ใหม่จึงต้องเป็นวิชา/กลุ่มเรียน/
  // นักศึกษาของตัวเองล้วน ๆ ไม่ยืมของที่เทสต์อื่นนับเลขไว้แล้ว
  personTeacherExamA: '10000000-0000-0000-0000-0000000000f1',
  staffExamA: '10000000-0000-0000-0000-0000000000f2',
  personTeacherExamB: '10000000-0000-0000-0000-0000000000f3',
  staffExamB: '10000000-0000-0000-0000-0000000000f4',
  courseExamA: '99999999-0000-0000-0000-0000000000f1',
  courseExamB: '99999999-0000-0000-0000-0000000000f2',
  sectionExamA: '20000000-0000-0000-0000-0000000000f1',
  sectionExamB: '20000000-0000-0000-0000-0000000000f2',
  personExamStudent: '10000000-0000-0000-0000-0000000000f5',
  studentExamOverlap: '10000000-0000-0000-0000-0000000000f6',
};

let passed = 0;
const failures: string[] = [];
/** ref2 ของใบแจ้งหนี้ เก็บไว้ตอน API-13 เพื่อใช้ทดสอบการกระทบยอด */
let REF2 = '';
/** ใบเสร็จที่ออกตอน API-15 — ชุด API-191 ถึง 197 ใช้ต่อ */
let RECEIPT_ID = '';
let RECEIPT_NO = '';

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

  // ── ห้องประจำ ตัวตั้งของการลงทะเบียนเป็นห้อง ─────────────────────
  //
  // `student_class_placement` ไม่มีแถวเดียวเลยทั้งใน seed และ fixture มาก่อน
  // ทั้งที่มีตารางมาตั้งแต่ 0031 — เส้นทางที่เริ่มจากห้องจึงไม่มีทางถูกเดิน
  // ถ้าไม่จัดห้องให้ก่อน (รูปเดียวกับ take_usage_snapshot ที่ไม่มีใครเรียก)
  //
  // คนที่ยังไม่ได้ผูกหลักสูตรมีจริงในวิทยาลัย (เพิ่งมอบตัว งานทะเบียนยังไม่ผูก)
  // และเป็นตัวที่ทำให้ "วิชานี้อยู่ในแผนของทั้งห้องไหม" ตอบว่าไม่ — ซึ่งเป็น
  // สิ่งที่ต้องเห็นก่อนกดลงทั้งห้อง
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th) values
       ($1, $4, 'ปาริชาต', 'ยังไม่ผูกหลักสูตร'),
       ($2, $4, 'ฐิติมา',  'เพิ่งเข้าห้อง'),
       ($3, $4, 'อัมพร',   'หลักสูตรฉบับเก่า')
     on conflict (id) do nothing`,
    [F.personNoPlan, F.personRoomFresh, F.personOtherPlan, INST],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be) values
       ($1, $4, $5, '69201010780', 2569),
       ($2, $4, $6, '69201010781', 2569),
       ($3, $4, $7, '69201010782', 2569)
     on conflict (id) do nothing`,
    [
      F.studentNoPlan, F.studentRoomFresh, F.studentOtherPlan, INST,
      F.personNoPlan, F.personRoomFresh, F.personOtherPlan,
    ],
  );
  await admin.query(
    `insert into student_curriculum (student_id, curriculum_version_id) values
       ($1, $3),
       -- ฉบับ 2562 ของ seed ไม่มีรายวิชาผูกไว้เลย คนนี้จึงไม่มีวิชาไหนในแผน
       -- ของภาคนี้ — ผลคือทุกวิชาของห้องกลายเป็น "ไม่ใช่ของทั้งห้อง" ซึ่งตรงกับ
       -- ห้องคละหลักสูตรจริง ๆ ที่ต้องเลือกเองก่อนกด
       ($2, $4)
     on conflict do nothing`,
    [F.studentRoomFresh, F.studentOtherPlan, CV, CV_OLD],
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

  // จัดห้องประจำ — ต้องมาหลังนักศึกษาทุกคนถูกสร้างแล้ว มิฉะนั้นล้มที่คีย์นอก
  await admin.query(
    `insert into student_class_placement
       (institution_id, student_id, academic_year_id, study_year, group_code) values
       ($2, $3, $1, 1, '9/1'),
       ($2, $4, $1, 1, '9/1'),
       ($2, $5, $1, 1, '9/1'),
       ($2, $6, $1, 1, '9/1'),
       ($2, $7, $1, 1, '9/1'),
       ($2, $8, $1, 1, '9/1'),
       -- คนนี้ถูกเลื่อนชั้นมาแต่ยังไม่ถูกจัดห้อง (rollover_students ตั้ง null)
       -- ซึ่งเป็นกองที่ต้องมองเห็น ไม่ใช่ถูกกรองทิ้งจากรายการห้อง
       ($2, $9, $1, 1, null)
     on conflict (student_id, academic_year_id) do update
       set study_year = excluded.study_year, group_code = excluded.group_code`,
    [
      AY, INST, F.student, F.studentBulkOk, F.studentBulkHeld,
      F.studentNoPlan, F.studentRoomFresh, F.studentOtherPlan, F.studentRegrade,
    ],
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

  // ── ตารางสอบ — วิชา/ครู/กลุ่มเรียน/นักศึกษาของตัวเองล้วน ๆ (ดูเหตุผลที่ F object) ──
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th) values
       ($1, $3, 'ครู', 'สอบเอ'),
       ($2, $3, 'ครู', 'สอบบี')
     on conflict (id) do nothing`,
    [F.personTeacherExamA, F.personTeacherExamB, INST],
  );
  await admin.query(
    `insert into staff (id, institution_id, person_id, staff_code, is_teacher) values
       ($1, $3, $4, 'T-EXAM-A', true),
       ($2, $3, $5, 'T-EXAM-B', true)
     on conflict (id) do nothing`,
    [F.staffExamA, F.staffExamB, INST, F.personTeacherExamA, F.personTeacherExamB],
  );
  await admin.query(
    `insert into course (id, institution_id, edition_be, code, name_th, credits, theory_hours, practice_hours) values
       ($1, $3, 2567, 'EXAM-CRS-A', 'วิชาทดสอบตารางสอบ เอ', 2, 2, 0),
       ($2, $3, 2567, 'EXAM-CRS-B', 'วิชาทดสอบตารางสอบ บี', 2, 2, 0)
     on conflict (id) do nothing`,
    [F.courseExamA, F.courseExamB, INST],
  );
  await admin.query(
    `insert into class_section
       (id, institution_id, term_id, course_id, section_no, teacher_id, attendance_policy_id, planned_periods) values
       ($1, $5, $6, $3, 'EXAM-A', $7, $8, 2),
       ($2, $5, $6, $4, 'EXAM-B', $9, $8, 2)
     on conflict (id) do nothing`,
    [F.sectionExamA, F.sectionExamB, F.courseExamA, F.courseExamB, INST, TERM1, F.staffExamA, POLICY, F.staffExamB],
  );
  await admin.query(
    `insert into person (id, institution_id, first_name_th, last_name_th) values
       ($1, $2, 'นักศึกษา', 'สอบซ้อนสองวิชา')
     on conflict (id) do nothing`,
    [F.personExamStudent, INST],
  );
  await admin.query(
    `insert into student (id, institution_id, person_id, student_code, admitted_year_be) values
       ($1, $2, $3, '69EXAMOVERLAP', 2569)
     on conflict (id) do nothing`,
    [F.studentExamOverlap, INST, F.personExamStudent],
  );
  // ลงทั้งสองกลุ่มโดยตั้งใจ — ใช้พิสูจน์ว่าตารางสอบของสองวิชานี้ชนกันไม่ได้
  // (คนเดียวกันสอบสองวิชาพร้อมกันไม่ได้จริง)
  await admin.query(
    `insert into enrollment (student_id, class_section_id, term_id, registered_by) values
       ($1, $2, $4, $5),
       ($1, $3, $4, $5)
     on conflict do nothing`,
    [F.studentExamOverlap, F.sectionExamA, F.sectionExamB, TERM1, F.personTeacherExamA],
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
  const tAdmin = await token(app, base, F.personTeacher, 'admin');
  const tTeacherExamB = await token(app, base, F.personTeacherExamB, 'teacher');
  const tExamStudent = await token(app, base, F.personExamStudent, 'student');

  const registrar = api(base, tRegistrar);
  const teacher = api(base, tTeacher);
  const teacherExamB = api(base, tTeacherExamB);
  const examStudent = api(base, tExamStudent);
  const student = api(base, tStudent);
  const finance = api(base, tFinance);
  const other = api(base, tOtherInst);
  const director = api(base, tDirector);
  const admin = api(base, tAdmin);

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
        studentId: F.student, amount: 4200, method: 'promptpay',
      }),
    });
    expect(r.status === 201 || r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Number(r.body.overpaid) === 0, 'ไม่ควรมีเงินเหลือ');
    expect(Number(r.body.balance.outstanding) === 8400, `ควรเหลือค้าง 8,400 ได้ ${r.body.balance.outstanding}`);
    RECEIPT_ID = r.body.receipt?.id ?? '';
    RECEIPT_NO = r.body.receipt?.doc_no ?? '';
    return `ค้างอยู่ ${r.body.balance.outstanding} บาท · ใบเสร็จ ${RECEIPT_NO}`;
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
  console.log('══ ใบเสร็จรับเงิน (0068) ══');

  /*
   * ─── ทำไมชุดนี้ต้องพิมพ์ใบออกมาอ่าน ไม่ใช่ตรวจแค่ว่ามีแถว ───
   * ก่อน 0068 ระบบมีช่อง `receipt_no` ให้กรอกอยู่แล้ว เทสต์ที่ตรวจว่า
   * "บันทึกการรับชำระได้" จึงเขียวมาตลอดโดยที่ไม่มีใบเสร็จจริงสักใบ
   * สิ่งที่ต้องพิสูจน์คือมี**กระดาษ**ที่มีเลขที่ ยอดเงิน และตัวอักษรอยู่บนนั้น
   */
  await check('API-191 รับชำระแล้วได้เลขที่ใบเสร็จกลับมาทันที', async () => {
    expect(RECEIPT_ID && RECEIPT_NO, 'API-15 ต้องได้ใบเสร็จติดมากับคำตอบของการรับชำระ');
    const list = await finance(`/finance/receipts?studentId=${F.student}`);
    expect(list.status === 200, `ได้ ${list.status}: ${JSON.stringify(list.body)}`);
    const mine = list.body.find((x: any) => x.id === RECEIPT_ID);
    expect(mine, 'ใบที่เพิ่งออกต้องอยู่ในรายการใบเสร็จของนักศึกษาคนนั้น');
    expect(Number(mine.amount) === 4200, `ยอดบนใบต้องเป็น 4,200 ได้ ${mine.amount}`);
    expect(String(mine.amount_text).includes('บาท'), 'ต้องมีจำนวนเงินตัวอักษรเก็บไว้กับใบ');
    return `${RECEIPT_NO} — ${mine.amount_text}`;
  });

  await check('API-192 พิมพ์ใบเสร็จได้กระดาษที่มีเลขที่และยอดจริง', async () => {
    const r = await finance(`/finance/receipts/${RECEIPT_ID}/print`);
    expect(r.status === 200, `ได้ ${r.status}`);
    const html = String(r.body);
    expect(html.includes('ใบเสร็จรับเงิน'), 'ต้องมีหัวเรื่องใบเสร็จ');
    expect(html.includes(RECEIPT_NO), `ต้องมีเลขที่ ${RECEIPT_NO} บนกระดาษ`);
    expect(html.includes('4,200.00'), 'ต้องมียอดเงินบนกระดาษ');
    expect(/บาท(ถ้วน|[ก-๙])/.test(html), 'ต้องมีจำนวนเงินตัวอักษรบนกระดาษ');
    // ต้องไม่มีหัวข้อที่ไม่มีค่าอยู่ใต้มัน — ช่องว่างบนใบเสร็จอ่านไม่ออกว่า
    // ระบบยังไม่เสร็จหรือข้อมูลหาย (บทเรียนเดียวกับ API-172)
    expect(!html.includes('ได้รับเงินจาก <strong></strong>'), 'ชื่อผู้จ่ายเงินต้องไม่ว่าง');
    return `${html.length} ตัวอักษร`;
  });

  await check('API-193 พิมพ์ซ้ำได้ใบเดิม ไม่กินเลขใหม่', async () => {
    const before = await finance(`/finance/receipts?studentId=${F.student}`);
    const again = await finance(`/finance/receipts/${RECEIPT_ID}/print`);
    expect(again.status === 200, `ได้ ${again.status}`);
    expect(String(again.body).includes(RECEIPT_NO), 'พิมพ์ซ้ำต้องได้เลขที่เดิม');
    const after = await finance(`/finance/receipts?studentId=${F.student}`);
    expect(after.body.length === before.body.length,
      `พิมพ์ซ้ำต้องไม่ออกใบใหม่ — จาก ${before.body.length} เป็น ${after.body.length}`);
  });

  await check('API-194 บทบาทอื่นเปิดใบเสร็จไม่ได้', async () => {
    // งานทะเบียนออกใบ รบ. ได้ แต่ไม่ใช่คนรับเงิน — และครูยิ่งไม่ใช่
    const a = await registrar(`/finance/receipts?studentId=${F.student}`);
    expect(a.status === 403, `งานทะเบียนควรได้ 403 ได้ ${a.status}`);
    const b = await teacher(`/finance/receipts/${RECEIPT_ID}/print`);
    expect(b.status === 403, `ครูควรได้ 403 ได้ ${b.status}`);
  });

  await check('API-195 เส้นทางพิมพ์ใบเสร็จปฏิเสธเอกสารชนิดอื่น', async () => {
    /*
     * เปิดให้ finance พิมพ์ "เอกสารอะไรก็ได้ที่รู้รหัส" แปลว่างานการเงิน
     * เปิดใบ รบ. กับระเบียนสะสมของใครก็ได้ ซึ่งเป็นข้อมูลคนละเรื่องกับ
     * หน้าที่ของตำแหน่ง — เส้นทางนี้จึงต้องดูชนิดเอกสารก่อนเสมอ
     */
    const doc = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certification', yearBe: 2569 }),
    });
    expect(doc.status === 201, `เตรียมข้อมูลไม่สำเร็จ ${doc.status}`);
    const r = await finance(`/finance/receipts/${doc.body.id}/print`);
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await check('API-196 ส่งเลขที่ใบเสร็จมาเองไม่ได้อีกแล้ว', async () => {
    // เลขต้องมาจากสายเลขของสถานศึกษา ไม่ใช่จากผู้เรียก — ฟิลด์ที่ไม่รู้จัก
    // ถูกปฏิเสธด้วย 400 ผู้เรียกเก่าจึงรู้ตัวทันที ไม่ใช่ถูกเมินเงียบ ๆ
    const r = await finance('/finance/payments', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, amount: 10, method: 'cash', receiptNo: 'ปลอม-0001',
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await check('API-197 วิทยาลัยอื่นเปิดใบเสร็จของเราไม่ได้', async () => {
    /*
     * ต้องเป็น**งานการเงินของอีกวิทยาลัย** ไม่ใช่บทบาทอื่น มิฉะนั้นจะติด
     * ด่านบทบาทก่อนถึง RLS แล้วเทสต์จะเขียวโดยไม่ได้พิสูจน์การแยกข้อมูลเลย
     * (เหมือน API-194 ที่ทดสอบคนละเรื่องกัน)
     */
    const otherFinance = api(base, await token(app, base, F.personAdmin2, 'finance', INST2));
    const a = await otherFinance(`/finance/receipts?studentId=${F.student}`);
    expect(a.status === 200, `ได้ ${a.status}: ${JSON.stringify(a.body)}`);
    expect(a.body.length === 0, `ควรไม่เห็นใบเสร็จเลย เห็น ${a.body.length} ใบ`);
    const b = await otherFinance(`/finance/receipts/${RECEIPT_ID}/print`);
    expect(b.status === 404, `ควรได้ 404 ได้ ${b.status}`);
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
  console.log('══ ลงทะเบียนเป็นห้อง — เส้นทางที่หน้าจอเดินจริง ══');

  /*
   * ชุดนี้เดินทั้งเส้นทางตั้งแต่ "เปิดหน้าจอมาเห็นอะไร" ถึง "กดแล้วตัวเลขขยับ"
   *
   * เทสต์เดิมของการลงทะเบียนเป็นกลุ่ม (API-24 ถึง 30) ส่ง `studentIds` ที่
   * เขียนไว้ในไฟล์เทสต์เอง ซึ่งพิสูจน์ว่าฟังก์ชันทำงานถูก แต่ไม่เคยตอบว่า
   * **เจ้าหน้าที่จะได้รายชื่อนั้นมาจากไหน** — คำตอบเดิมคือ "จากรายชื่อสองร้อย
   * คนแรกของทั้งวิทยาลัย" ซึ่งใช้กับวิทยาลัยพันคนไม่ได้ และไม่มีเทสต์ไหน
   * เดินทางนั้นเลยเพราะทางนั้นเดินไม่ได้ตั้งแต่แรก (รูปเดียวกับ AUTH-26)
   */
  let roomPendingBefore = -1;

  await check('API-180 รายการห้องบอกจำนวนคนและความคืบหน้าได้', async () => {
    const r = await registrar(`/registration/rooms?termId=${TERM1}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    const room = r.body.find((x: any) => x.group_code === '9/1');
    expect(room, `ต้องเห็นห้อง 9/1 เห็น ${JSON.stringify(r.body.map((x: any) => x.group_code))}`);
    expect(Number(room.students_total) === 6,
      `ห้อง 9/1 มีหกคนที่ยังกำลังศึกษา ได้ ${room.students_total}`);
    expect(
      Number(room.students_registered) + Number(room.students_pending)
        === Number(room.students_total),
      'ลงแล้วบวกยังไม่ลงต้องเท่ากับจำนวนคนในห้อง',
    );
    roomPendingBefore = Number(room.students_pending);
    return `ห้อง 9/1 ${room.students_registered}/${room.students_total} = ${room.pct}%`;
  });

  await check('API-181 ห้องที่ยังไม่ได้จัดเป็นแถวหนึ่ง ไม่ใช่ถูกกรองทิ้ง', async () => {
    // กองนี้คือคนที่ถูกเลื่อนชั้นมาแล้วยังไม่มีใครจัดห้องให้ — ถ้าไม่แสดง
    // จะไม่มีใครรู้ว่ามีคนตกค้างอยู่ จนกระทั่งเลยกำหนดเพิ่ม-ถอนไปแล้ว
    const r = await registrar(`/registration/rooms?termId=${TERM1}`);
    const un = r.body.find((x: any) => x.group_code === null);
    expect(un, 'ต้องมีแถวของคนที่ยังไม่ถูกจัดห้อง');
    expect(Number(un.students_total) >= 1, `ต้องนับคนได้ ได้ ${un.students_total}`);

    // และต้องเปิดดูได้จริงด้วย ไม่ใช่เห็นแต่กดไม่ได้ —
    // `group_code is null` ต้องเทียบด้วย `is not distinct from` ที่ชั้น SQL
    const plan = await registrar(`/registration/rooms/plan?termId=${TERM1}&studyYear=1`);
    expect(plan.status === 200, `ได้ ${plan.status}: ${JSON.stringify(plan.body)}`);
    expect(plan.body.students.length === Number(un.students_total),
      `รายชื่อต้องได้ ${un.students_total} คน ได้ ${plan.body.students.length}`);
    expect(plan.body.room.groupCode === null, 'ต้องรู้ว่านี่คือห้องที่ยังไม่ได้จัด');

    // ห้องนี้มีคนเดียวและผูกหลักสูตรแล้ว ทุกวิชาในแผนจึงเป็นของ "ทั้งห้อง"
    // — ด้านบวกของกฎเดียวกับ API-183 ซึ่งเป็นตัวตัดสินว่าหน้าจอจะติ๊กให้ล่วงหน้าไหม
    expect(plan.body.courses.length >= 1, 'ต้องได้รายวิชาตามแผน');
    expect(plan.body.courses.every((c: any) => c.wholeRoom === true),
      'ทุกคนในห้องนี้มีแผนเดียวกัน จึงต้องรายงานว่าเป็นวิชาของทั้งห้อง');
    return `${un.students_total} คนยังไม่ถูกจัดห้อง`;
  });

  await check('API-182 ชุดวิชามาจากแผนการเรียน และบอกที่มาของกลุ่มเรียนที่เดาให้', async () => {
    const r = await registrar(
      `/registration/rooms/plan?termId=${TERM1}&studyYear=1&groupCode=9%2F1`,
    );
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.courses.length >= 1, 'ต้องได้รายวิชาจากแผนการเรียนของหลักสูตร');

    const target = r.body.courses.find((c: any) => c.courseId === COURSE);
    expect(target, 'วิชาที่แผนกำหนดไว้สำหรับชั้นปี 1 ภาค 1 ต้องอยู่ในชุด');
    // วิชานี้เปิดสองกลุ่มในภาคนี้ (9/1 กับ 9/2) การเดาถูกจึงไม่ใช่เพราะ
    // "มีกลุ่มเดียว" แต่เพราะรหัสกลุ่มตรงกับรหัสห้องจริง ๆ
    expect(target.sections.length >= 2,
      `ต้องเห็นทุกกลุ่มที่เปิด ได้ ${target.sections.length}`);
    expect(target.suggestedSectionId === F.section,
      `ต้องเดากลุ่ม 9/1 ได้ ${target.suggestedSectionId}`);
    expect(target.suggestedReason === 'รหัสกลุ่มเรียนตรงกับรหัสห้อง',
      `ต้องบอกที่มาของการเดา ได้ ${target.suggestedReason}`);

    // วิชาในแผนที่ยังไม่เปิดกลุ่มต้องอยู่ในชุดด้วย พร้อมรายการกลุ่มที่ว่าง
    // — ถ้ากรองทิ้ง เจ้าหน้าที่จะไม่รู้ว่ายังมีวิชาที่ต้องเปิดกลุ่มก่อน
    const noSection = r.body.courses.find((c: any) => c.sections.length === 0);
    expect(noSection, 'วิชาที่ยังไม่เปิดกลุ่มเรียนต้องยังแสดงอยู่');
    return `${r.body.courses.length} วิชา · ยังไม่เปิดกลุ่ม ${noSection.code}`;
  });

  await check('API-183 วิชาที่ไม่ได้อยู่ในแผนของทั้งห้องต้องดูออกก่อนกด', async () => {
    /*
     * ห้องนี้มีคนที่ยังไม่ได้ผูกหลักสูตรอยู่หนึ่งคน ตัวเลขความครอบคลุมจึง
     * ต้องต่ำกว่าจำนวนคนที่ลงทะเบียนได้ ถ้ารายงานว่า "ทั้งห้อง" ทั้งที่ไม่ใช่
     * หน้าจอจะติ๊กให้ล่วงหน้าแล้วคนที่ไม่ได้เรียนวิชานั้นจะได้ติดไปด้วย
     */
    const r = await registrar(
      `/registration/rooms/plan?termId=${TERM1}&studyYear=1&groupCode=9%2F1`,
    );
    expect(r.body.registerable === 6, `ต้องลงทะเบียนได้หกคน ได้ ${r.body.registerable}`);
    expect(r.body.plannable === 5, `ห้าคนผูกหลักสูตรแล้ว ได้ ${r.body.plannable}`);
    expect(r.body.withoutCurriculum === 1,
      `หนึ่งคนยังไม่ผูกหลักสูตร ได้ ${r.body.withoutCurriculum}`);

    // ต้องชี้ตัวได้เป็นรายคน ไม่ใช่รู้แค่จำนวนรวม เพราะสิ่งที่ต้องทำต่อคือ
    // ไปผูกหลักสูตรให้**คนนั้น** ที่หน้าระเบียนนักศึกษา
    const noPlan = r.body.students.filter((s: any) => s.hasCurriculum === false);
    expect(noPlan.length === 1 && noPlan[0].studentCode === '69201010780',
      `ต้องชี้ตัวคนที่ยังไม่ผูกหลักสูตรได้ ได้ ${JSON.stringify(noPlan.map((x: any) => x.studentCode))}`);

    const c = r.body.courses.find((x: any) => x.courseId === COURSE);
    expect(c.studentsInPlan === 4,
      `สี่คนที่อยู่หลักสูตรฉบับปัจจุบันเท่านั้นที่มีวิชานี้ในแผน ได้ ${c.studentsInPlan}`);
    expect(c.wholeRoom === false,
      'ห้องนี้คละหลักสูตร จึงต้องไม่รายงานว่าเป็นวิชาของทั้งห้อง');
    return `${c.studentsInPlan} จาก ${r.body.plannable} คนที่มีแผน · ยังไม่ผูกหลักสูตร ${r.body.withoutCurriculum}`;
  });

  await check('API-184 ลงทั้งห้องแล้วความคืบหน้าขยับจริง', async () => {
    const plan = await registrar(
      `/registration/rooms/plan?termId=${TERM1}&studyYear=1&groupCode=9%2F1`,
    );
    // เดินแบบเดียวกับหน้าจอ — เอากลุ่มเรียนที่ระบบเดาให้ ไม่ใช่รหัสที่พิมพ์ไว้ในเทสต์
    const sectionIds = plan.body.courses
      .map((c: any) => c.suggestedSectionId)
      .filter((id: string | null) => id !== null);
    expect(sectionIds.length >= 1, 'ต้องมีกลุ่มเรียนที่จับคู่ได้อย่างน้อยหนึ่งวิชา');

    const studentIds = plan.body.students
      .filter((s: any) => s.status === 'active')
      .map((s: any) => s.id);
    expect(studentIds.length === 6, `ต้องได้หกคน ได้ ${studentIds.length}`);

    const r = await registrar('/registration/register-bulk', {
      method: 'POST',
      body: JSON.stringify({ studentIds, termId: TERM1, sectionIds }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.results.length === studentIds.length,
      'ต้องคืนผลครบทุกคน แม้คนที่ลงไม่ได้');

    // คนที่ค้างค่าเทอมต้องติดเงื่อนไข และต้องไม่ทำให้คนอื่นล้มไปด้วย
    const held = r.body.results.find((x: any) => x.studentId === F.studentBulkHeld);
    expect(held && held.blockers.length > 0, 'คนที่ถูกระงับต้องติดเงื่อนไข');
    expect(r.body.succeeded >= 1, `ต้องมีคนลงสำเร็จ ได้ ${r.body.succeeded}`);

    const after = await registrar(`/registration/rooms?termId=${TERM1}`);
    const room = after.body.find((x: any) => x.group_code === '9/1');
    /*
     * ต้องลดลงจริง ไม่ใช่แค่ตอบ 201 กลับมา — ห้องนี้มีคนที่ยังไม่มีรายวิชาเลย
     * อยู่หนึ่งคนโดยตั้งใจ ถ้าตัวเลขไม่ขยับแปลว่าเส้นทางนี้เขียน enrollment
     * ไม่สำเร็จ ซึ่งเป็นสิ่งที่ผลรายคนอย่างเดียวมองไม่ออก (คนที่ลงไว้แล้ว
     * ได้ 0 วิชาเหมือนกันเป๊ะกับคนที่เขียนไม่สำเร็จ)
     */
    expect(Number(room.students_pending) < roomPendingBefore,
      `คนที่ยังไม่ลงต้องลดลงจาก ${roomPendingBefore} ได้ ${room.students_pending}`);
    return `สำเร็จ ${r.body.succeeded} · ติดเงื่อนไข ${r.body.blocked} · เหลือ ${room.students_pending} คน`;
  });

  await check('API-185 กดลงห้องเดิมซ้ำได้ 0 วิชาโดยไม่ติดเงื่อนไข', async () => {
    /*
     * เป็นสิ่งที่เกิดทุกครั้งที่มีคนย้ายเข้าห้องกลางภาคแล้วเจ้าหน้าที่กดลง
     * ทั้งห้องอีกรอบ — `on conflict do nothing` ทำให้คนเดิมได้ 0 กลับมา
     * โดยไม่ติดอะไรสักข้อ ซึ่ง**ไม่ใช่ความล้มเหลว** หน้าจอที่ทาสีแดงให้ทุกแถว
     * ที่ได้ 0 จะทำให้เจ้าหน้าที่เข้าใจว่าพังทั้งห้องทั้งที่ไม่มีอะไรผิด
     */
    const r = await registrar('/registration/register-bulk', {
      method: 'POST',
      body: JSON.stringify({
        studentIds: [F.student, F.studentBulkOk], termId: TERM1, sectionIds: [F.section],
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    for (const row of r.body.results) {
      expect(row.blockers.length === 0,
        `ไม่ควรติดอะไร แต่ ${row.studentId} ติด ${row.blockers.join(' / ')}`);
      expect(row.registered === 0,
        `ลงไว้แล้วจึงต้องลงเพิ่มไม่ได้ แต่ได้ ${row.registered} วิชา`);
    }
    expect(r.body.blocked === 0, `ไม่ควรมีใครติดเงื่อนไข ได้ ${r.body.blocked}`);
  });

  await check('API-186 ตัวกรองห้องของรายชื่อนักศึกษากรองได้จริง', async () => {
    const r = await registrar(
      `/students?academicYearId=${AY}&studyYear=1&groupCode=9%2F1&limit=200`,
    );
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Array.isArray(r.body), 'ยังต้องคืนอาร์เรย์ — แอปนักศึกษา cast เป็น List ตรง ๆ');
    expect(r.body.length === 6, `ต้องได้เฉพาะหกคนในห้อง ได้ ${r.body.length}`);
    expect(r.body.every((s: any) => s.group_code === '9/1'), 'ทุกแถวต้องเป็นห้อง 9/1');
    expect(!r.body.some((s: any) => s.student_code === '69201010779'),
      'คนที่ยังไม่ถูกจัดห้องต้องไม่ปนมาในห้อง 9/1');

    // ค้นหาต้องยังทำงานร่วมกับตัวกรอง ไม่ใช่เลือกได้อย่างเดียว
    const one = await registrar(
      `/students?academicYearId=${AY}&studyYear=1&groupCode=9%2F1&q=69201010777`,
    );
    expect(one.body.length === 1, `ค้นในห้องต้องได้คนเดียว ได้ ${one.body.length}`);
    return `${r.body.length} คนในห้อง 9/1`;
  });

  await check('API-187 กรองห้องโดยไม่บอกปีการศึกษาถูกปฏิเสธ', async () => {
    /*
     * รหัสห้อง `9/1` มีอยู่ทุกปีการศึกษาและหมายถึงคนละกลุ่มคนทุกครั้ง
     * ถ้ายอมให้กรองโดยไม่ระบุปี จะได้รุ่นพี่ที่จบไปแล้วปนมาโดยไม่มีอะไรทัก
     */
    const a = await registrar('/students?groupCode=9%2F1');
    expect(a.status === 400, `ควรได้ 400 ได้ ${a.status}`);
    const b = await registrar('/students?studyYear=1');
    expect(b.status === 400, `ควรได้ 400 ได้ ${b.status}`);
    // ค่าที่พิมพ์ผิดต้องบอกว่าผิด ไม่ใช่คืนรายชื่อว่างซึ่งดูเหมือน "ไม่มีใคร"
    const c = await registrar(`/students?academicYearId=${AY}&status=activee`);
    expect(c.status === 400, `สถานะที่ไม่รู้จักควรได้ 400 ได้ ${c.status}`);
    const d = await registrar(`/students?academicYearId=${AY}&studyYear=9`);
    expect(d.status === 400, `ชั้นปีเกินช่วงควรได้ 400 ได้ ${d.status}`);
  });

  await check('API-188 ครูเปิดรายการห้องและแผนของทั้งวิทยาลัยไม่ได้', async () => {
    const a = await teacher(`/registration/rooms?termId=${TERM1}`);
    expect(a.status === 403, `ควรได้ 403 ได้ ${a.status}`);
    const b = await teacher(
      `/registration/rooms/plan?termId=${TERM1}&studyYear=1&groupCode=9%2F1`,
    );
    expect(b.status === 403, `ควรได้ 403 ได้ ${b.status}`);
  });

  await check('API-189 วิทยาลัยอื่นไม่เห็นห้องของเราเลยสักห้อง', async () => {
    const a = await other(`/registration/rooms?termId=${TERM1}`);
    expect(a.status === 200, `ได้ ${a.status}`);
    expect(a.body.length === 0, `ควรไม่เห็นอะไรเลย เห็น ${a.body.length} ห้อง`);

    // แผนของห้องต้องเป็น 404 ไม่ใช่ผลว่าง เพราะภาคเรียนนั้นไม่มีอยู่ในสายตาเขา
    const b = await other(
      `/registration/rooms/plan?termId=${TERM1}&studyYear=1&groupCode=9%2F1`,
    );
    expect(b.status === 404, `ควรได้ 404 ได้ ${b.status}`);
  });

  await check('API-190 พารามิเตอร์ของแผนห้องถูกตรวจก่อนถึงฐานข้อมูล', async () => {
    const a = await registrar(`/registration/rooms/plan?termId=${TERM1}`);
    expect(a.status === 400, `ไม่ส่งชั้นปีควรได้ 400 ได้ ${a.status}`);
    const b = await registrar('/registration/rooms/plan?termId=1%20or%201%3D1&studyYear=1');
    expect(b.status === 400, `termId ผิดรูปแบบควรได้ 400 ได้ ${b.status}`);
    const c = await registrar('/registration/rooms?termId=not-a-uuid');
    expect(c.status === 400, `ควรได้ 400 ได้ ${c.status}`);
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

    /*
     * นับเฉพาะใบ รบ. ไม่ใช่ทุกใบของนักศึกษาคนนี้ — ตั้งแต่ 0068 ใบเสร็จ
     * รับเงินอยู่ในตารางเดียวกัน การนับรวมจึงกลายเป็นการนับสิ่งที่งานการเงิน
     * ทำไว้ก่อนหน้า ซึ่งไม่เกี่ยวกับสิ่งที่ข้อนี้ทดสอบ
     */
    const list = await registrar(`/documents/students/${F.student}`);
    const transcripts = list.body.filter((d: any) => d.kind === 'transcript');
    expect(transcripts.length === 1, `ควรมีใบ รบ. ใบเดียว ได้ ${transcripts.length} ใบ`);
    return `อ่านซ้ำได้เลขที่เดิม ${r.body.doc_no} และยังมีใบ รบ. ใบเดียว`;
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
        fatherFirstNameTh: 'สมชาย', fatherLastNameTh: 'ผู้สมัครหนึ่ง',
        fatherOccupationTh: 'รับราชการ', fatherIncomeMonthly: 30000, fatherPhone: '0811111111',
        motherFirstNameTh: 'สมหญิง', motherLastNameTh: 'ผู้สมัครหนึ่ง',
        motherOccupationTh: 'ค้าขาย', motherIncomeMonthly: 15000, motherPhone: '0822222222',
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

  await check('API-246 รับเข้าแล้วบิดามารดาและวุฒิเดิมที่กรอกในใบสมัครไปถึงแฟ้มนักศึกษาอัตโนมัติ', async () => {
    const app = await registrar(`/admissions/applications/${appId}`);
    expect(app.status === 200, `ได้ ${app.status}`);
    expect(!!app.body.student_id, 'ใบสมัครต้องผูกกับนักศึกษาแล้วหลังรับเข้า');
    expect(app.body.father_first_name_th === 'สมชาย', 'ใบสมัครต้องยังเก็บชื่อบิดาไว้ครบ');

    const profile = await registrar(`/students/${app.body.student_id}/profile`);
    expect(profile.status === 200, `ได้ ${profile.status}`);

    const father = profile.body.parents.find((x: any) => x.role === 'father');
    const mother = profile.body.parents.find((x: any) => x.role === 'mother');
    expect(!!father && father.first_name_th === 'สมชาย' && father.occupation_th === 'รับราชการ',
      `บิดาต้องถูกคัดลอกมาครบ ได้ ${JSON.stringify(father)}`);
    expect(!!mother && mother.first_name_th === 'สมหญิง' && Number(mother.income_monthly) === 15000,
      `มารดาต้องถูกคัดลอกมาครบ ได้ ${JSON.stringify(mother)}`);

    const prior = profile.body.priorEducation.find((x: any) => x.level_th === 'ม.3');
    expect(!!prior && prior.school_th === 'โรงเรียนทดสอบวิทยา' && Number(prior.gpax) === 2.85,
      `วุฒิเดิมต้องถูกคัดลอกมาครบ ได้ ${JSON.stringify(prior)}`);
    return 'บิดา มารดา และวุฒิเดิม คัดลอกมาครบจากใบสมัคร';
  });

  await check('API-247 งานทะเบียนออกใบแจ้งหนี้และให้ทุนนักศึกษาที่เพิ่งรับเข้าได้ทันที', async () => {
    /*
     * RLS ของ invoice/student_funding (0041 · 0080) อนุญาต registrar ไว้แล้ว
     * แต่ @Roles ของ FinanceController เดิมแคบกว่านั้น (เฉพาะ finance) —
     * งานรับสมัครต้องตั้งค่าเทอมนักศึกษาใหม่ได้ทันทีไม่ต้องโอนงานไปให้
     * ฝ่ายการเงินทำแทน (ดูคอมเมนต์ในคอนโทรลเลอร์)
     */
    const studentId = (await registrar(`/admissions/applications/${appId}`)).body.student_id;

    const src = await registrar('/finance/funding-sources', {
      method: 'POST',
      body: JSON.stringify({ kind: 'other', nameTh: 'ทุนทดสอบ API-247' }),
    });
    expect(src.status === 201, `ควรได้ 201 ได้ ${src.status}: ${JSON.stringify(src.body)}`);

    const fund = await registrar(`/finance/students/${studentId}/funding`, {
      method: 'POST',
      body: JSON.stringify({ fundingSourceId: src.body.id, academicYearId: AY, percentOff: 20 }),
    });
    expect(fund.status === 201, `ควรได้ 201 ได้ ${fund.status}: ${JSON.stringify(fund.body)}`);

    // ใบเสร็จ (รับเงินแล้ว) ยังเป็นของฝ่ายการเงินล้วน — คนละงานกับตั้งยอด
    const receipts = await registrar(`/finance/receipts?studentId=${studentId}`);
    expect(receipts.status === 403, `ใบเสร็จควรยังปิดสำหรับงานทะเบียน ได้ ${receipts.status}`);
    return 'ตั้งทุนได้ผ่าน registrar · ใบเสร็จยังปิดตามเดิม';
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

  await check('API-248 ผู้อำนวยการรับเข้าใบสมัครที่มีข้อมูลบิดามารดาได้โดยไม่ชน RLS', async () => {
    /*
     * parent_insert/prior_education_insert (0053) เดิมไม่มี 'director' อยู่เลย
     * ทั้งที่ AdmissionsController เปิดให้ director เรียก /admit ได้ — ถ้า
     * ไม่แก้ policy การรับเข้าที่มีข้อมูลบิดา/มารดามาด้วยจะพังกลางทางทันที
     * ที่ director เป็นคนกด (ดูคอมเมนต์ใน 0092)
     */
    const dRound = await registrar('/admissions/rounds', {
      method: 'POST',
      body: JSON.stringify({
        academicYearId: AY, code: 'R-DIR-248', nameTh: 'รอบทดสอบผู้อำนวยการ',
        appliesFrom: '2026-01-01', appliesTo: '2026-12-31',
      }),
    });
    await registrar(`/admissions/rounds/${dRound.body.id}/quotas`, {
      method: 'POST', body: JSON.stringify({ curriculumVersionId: CV, seats: 1 }),
    });
    await registrar(`/admissions/rounds/${dRound.body.id}/status`, {
      method: 'POST', body: JSON.stringify({ status: 'open' }),
    });

    const app = await registrar('/admissions/applications', {
      method: 'POST',
      body: JSON.stringify({
        roundId: dRound.body.id, firstNameTh: 'ทดสอบ', lastNameTh: 'ผู้อำนวยการรับเข้า',
        fatherFirstNameTh: 'บิดา', fatherLastNameTh: 'ทดสอบ',
        choices: [{ preference: 1, curriculumVersionId: CV }],
      }),
    });
    await registrar(`/admissions/applications/${app.body.id}/submit`, { method: 'POST' });
    await registrar(`/admissions/applications/${app.body.id}/decision`, {
      method: 'POST', body: JSON.stringify({ outcome: 'passed', curriculumVersionId: CV }),
    });

    const admitted = await director(`/admissions/applications/${app.body.id}/admit`, {
      method: 'POST',
      body: JSON.stringify({ studentCode: '69ADMDIR001', academicYearId: AY }),
    });
    expect(admitted.status === 201, `ผู้อำนวยการรับเข้าควรได้ 201 ได้ ${admitted.status}: ${JSON.stringify(admitted.body)}`);

    const profile = await registrar(`/students/${admitted.body.studentId}/profile`);
    const father = profile.body.parents.find((x: any) => x.role === 'father');
    expect(!!father && father.first_name_th === 'บิดา', 'ข้อมูลบิดาต้องถูกคัดลอกมาแม้ผู้รับเข้าเป็นผู้อำนวยการ');
    return 'ผู้อำนวยการรับเข้าได้ พร้อมข้อมูลบิดามารดาไม่ชน RLS';
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
  console.log('══ เอกสารทำงานที่พิมพ์สด ══');

  await check('API-141 ใบลงทะเบียนพิมพ์สดและตรงกับใบแจ้งหนี้ที่ออกจริง', async () => {
    /*
     * ยอดเงินอ่านจาก `invoice` ที่ออกจริง ไม่ใช่คำนวณจาก fee_schedule ใหม่
     * เพราะใบแจ้งหนี้อาจมีส่วนลดหรือทุนที่ระบบคิดเองไม่ได้ — ถ้าคำนวณใหม่
     * ตัวเลขบนใบลงทะเบียนจะไม่ตรงกับที่นักศึกษาต้องจ่ายจริง
     */
    const r = await registrar(`/reports/registration/${F.student}?termId=${TERM1}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    const html = String(r.body);
    expect(html.includes('ใบลงทะเบียนเรียน'), 'ต้องเป็นใบลงทะเบียน');
    expect(html.includes('รวมหน่วยกิต'), 'ต้องสรุปหน่วยกิตรวม');
    expect(html.includes('พิมพ์เมื่อ'),
      'เอกสารทำงานต้องบอกว่าเป็นภาพ ณ เวลาไหน มิฉะนั้นคนที่หยิบขึ้นมาอีกเดือนจะไม่รู้ว่ามันเก่าแค่ไหน');
    expect(!/(src|href)\s*=\s*["']https?:/i.test(html), 'ต้องไม่อ้างไฟล์ภายนอก');

    // ยอดบนกระดาษต้องตรงกับใบแจ้งหนี้จริง
    const inv = await registrar(`/students/${F.student}/invoices`);
    if (inv.body.length > 0) {
      const live = inv.body.find((x: any) => x.term_id === TERM1);
      if (live) {
        expect(html.includes(String(live.invoice_no)),
          'ต้องอ้างเลขที่ใบแจ้งหนี้ที่ออกจริง ไม่ใช่คำนวณยอดใหม่เอง');
      }
    }
    return `${html.length} ตัวอักษร`;
  });

  await check('API-142 ใบรายชื่อมีสองโหมด — ดูสถานะ และเปล่าไว้เขียนมือ', async () => {
    /*
     * ใบเปล่าคือกระดาษที่ครูถือเดินเข้าห้องตอนอินเทอร์เน็ตล่มหรือแบตหมด
     * ถ้าไม่มีช่องว่างเลย มันเป็นแค่รายชื่อที่ดูสวย ไม่ใช่เครื่องมือทำงาน
     */
    const view = await teacher(`/reports/roster/${F.section}`);
    expect(view.status === 200, `ควรได้ 200 ได้ ${view.status}`);
    expect(String(view.body).includes('เวลาเรียน'), 'โหมดปกติต้องแสดงเวลาเรียน');

    const blank = await teacher(`/reports/roster/${F.section}?mode=blank`);
    expect(blank.status === 200, `ควรได้ 200 ได้ ${blank.status}`);
    const b = String(blank.body);
    expect(b.includes('class="blank"'), 'โหมดเปล่าต้องมีช่องว่างให้เขียน');
    expect(b.includes('landscape'), 'โหมดเปล่าควรเป็นแนวนอนเพื่อให้มีที่พอ');
    expect(!b.includes('เวลาเรียน</th>'), 'โหมดเปล่าไม่ควรมีคอลัมน์เวลาเรียนมาแย่งที่');
    return 'สองโหมดต่างกันจริง';
  });

  await check('API-143 คอลัมน์แรกของใบรายชื่อต้องไม่ปนเลขที่จริงกับลำดับแถว', async () => {
    /*
     * ถ้าบางคนมีเลขที่ในห้องและบางคนไม่มี แล้วเติมด้วยลำดับแถวแทน
     * จะได้คอลัมน์ที่ปนกันสองความหมาย — ครูที่ขานชื่อตามเลขจะเรียกผิดคน
     * และไม่มีอะไรบนกระดาษบอกว่ามันปนกันอยู่
     * (เจอตอนอ่านใบที่พิมพ์ออกมาจริง คนแรกขึ้น "7" แล้วคนถัดไปขึ้น 2, 3, 4)
     */
    const html = String((await teacher(`/reports/roster/${F.section}`)).body);
    const hasClassCol = html.includes('>เลขที่</th>');
    const hasSeqCol = html.includes('>ลำดับ</th>');
    expect(hasClassCol !== hasSeqCol, 'ต้องเลือกอย่างใดอย่างหนึ่ง ไม่ใช่ทั้งคู่หรือไม่มีเลย');

    if (hasSeqCol) {
      expect(html.includes('ไม่ใช่เลขที่ในห้อง'),
        'เมื่อใช้ลำดับแถว ต้องบอกบนกระดาษว่าไม่ใช่เลขที่ในห้อง');
    }
    return hasClassCol ? 'ทุกคนมีเลขที่ → ใช้เลขที่จริง' : 'มีคนยังไม่มีเลขที่ → ใช้ลำดับพร้อมคำอธิบาย';
  });

  await check('API-144 ประกาศผู้มีสิทธิ์สอบแยกสองรายการบนแผ่นเดียว', async () => {
    /*
     * ประกาศที่มีแต่รายชื่อผู้มีสิทธิ์ ทำให้คนที่ไม่เห็นชื่อตัวเองไม่รู้ว่า
     * "ตกหล่น" หรือ "หมดสิทธิ์" ซึ่งต้องไปทำคนละอย่าง
     */
    const r = await teacher(`/reports/exam-eligibility/${F.section}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    const html = String(r.body);
    expect(html.includes('ผู้มีสิทธิ์เข้าสอบ'), 'ต้องมีรายการผู้มีสิทธิ์');
    expect(html.includes('ผู้หมดสิทธิ์เข้าสอบ'), 'ต้องมีรายการผู้หมดสิทธิ์บนแผ่นเดียวกัน');
    expect(html.includes('ยังไม่ได้ลงทะเบียน'),
      'ต้องอธิบายว่าคนที่ไม่พบชื่อในทั้งสองรายการหมายถึงอะไร');
    return 'ครบทั้งสองรายการพร้อมคำอธิบาย';
  });

  await check('API-145 นักศึกษาเปิดใบรายชื่อของกลุ่มเรียนไม่ได้', async () => {
    // ใบรายชื่อมีชื่อและรหัสของเพื่อนทั้งห้อง รวมถึงเปอร์เซ็นต์เวลาเรียน
    // ซึ่งเป็นข้อมูลของคนอื่น
    const r = await student(`/reports/roster/${F.section}`);
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-146 วิทยาลัยอื่นเปิดเอกสารทำงานของเราไม่ได้', async () => {
    const a = await other(`/reports/registration/${F.student}?termId=${TERM1}`);
    expect(a.status === 404, `ควรได้ 404 ได้ ${a.status}`);
    const b = await other(`/reports/roster/${F.section}`);
    expect(b.status === 404, `ควรได้ 404 ได้ ${b.status}`);
  });

  console.log('');
  console.log('══ ทวิภาคีและสถานประกอบการ ══');

  /*
   * โมดูลนี้มี 20 กว่าเส้นทางและ **ไม่เคยมีเทสต์ HTTP เลยสักข้อ** —
   * รูปเดียวกับที่ทำให้ข้อ 6, 14 และ 16 หลุดมาได้ คือของที่มีอยู่จริง
   * แต่ไม่มีอะไรเดินเส้นทางของมันตั้งแต่ต้นจนจบ
   */
  let workplaceId = '';
  let placementId = '';

  await check('API-147 สถานประกอบการที่ยังไม่อนุมัติ ส่งนักศึกษาไปฝึกไม่ได้', async () => {
    /*
     * การประเมินสถานประกอบการก่อนส่งเด็กไปเป็นข้อกำหนดของหลักสูตรทวิภาคี
     * — ถ้าข้ามได้ วิทยาลัยจะส่งนักศึกษาไปที่ที่ยังไม่มีใครไปดูเลย
     */
    const mk = await registrar('/workplaces', {
      method: 'POST',
      body: JSON.stringify({
        code: `WP-T${Math.floor(Math.random() * 9000 + 1000)}`,
        nameTh: 'บริษัททดสอบทวิภาคี จำกัด',
        industry: 'ซ่อมบำรุงยานยนต์', province: 'เชียงใหม่',
        lat: 18.79, lng: 98.98, checkinRadiusM: 200,
      }),
    });
    expect(mk.status < 400, `สร้างไม่สำเร็จ ${mk.status} ${JSON.stringify(mk.body)}`);
    workplaceId = mk.body.id;
    expect(mk.body.status === 'draft', `สร้างใหม่ต้องเป็น draft ได้ ${mk.body.status}`);

    const early = await registrar('/dual/placements', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, workplaceId,
        startsOn: '2026-06-01', endsOn: '2026-09-30', targetHours: 400,
      }),
    });
    expect(early.status >= 400,
      `ส่งไปที่ที่ยังไม่อนุมัติควรถูกปฏิเสธ ได้ ${early.status}`);
    return 'สร้างได้ · แต่ส่งเด็กไปยังไม่ได้';
  });

  await check('API-148 งานทะเบียนสร้างสถานประกอบการได้ แต่อนุมัติไม่ได้', async () => {
    // คนที่กรอกข้อมูลกับคนที่รับรองว่าไปประเมินมาแล้วต้องไม่ใช่คนเดียวกัน
    const deny = await registrar(`/workplaces/${workplaceId}/approve`, {
      method: 'POST', body: JSON.stringify({ assessedOn: '2026-05-01' }),
    });
    expect(deny.status === 403, `ควรได้ 403 ได้ ${deny.status}`);

    const ok = await director(`/workplaces/${workplaceId}/approve`, {
      method: 'POST', body: JSON.stringify({ assessedOn: '2026-05-01' }),
    });
    expect(ok.status < 400, `ผู้บริหารควรอนุมัติได้ ได้ ${ok.status} ${JSON.stringify(ok.body)}`);
    return 'แยกคนกรอกกับคนรับรอง';
  });

  await check('API-149 ชั่วโมงที่ยังไม่รับรองต้องไม่ถูกนับรวมกับที่รับรองแล้ว', async () => {
    /*
     * สองตัวเลขนี้ตอบคนละคำถาม — "รับรองแล้ว" คือความคืบหน้าจริงตามหลักสูตร
     * "รอรับรอง" คือภาระงานของครูนิเทศ ถ้ารวมเป็นตัวเดียว นักศึกษาที่
     * "ครบ 400 ชั่วโมง" อาจแค่กรอกครบโดยไม่มีใครรับรองสักชั่วโมง
     */
    const pl = await registrar('/dual/placements', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, workplaceId,
        startsOn: '2026-06-01', endsOn: '2026-09-30', targetHours: 400,
      }),
    });
    expect(pl.status < 400, `สร้างใบส่งตัวไม่สำเร็จ ${pl.status} ${JSON.stringify(pl.body)}`);
    placementId = pl.body.id;

    for (const d of ['2026-06-01', '2026-06-02']) {
      const lg = await registrar('/practicum/logs', {
        method: 'POST',
        body: JSON.stringify({
          studentId: F.student, placementId, workplaceId,
          workedOn: d, hours: 7.5, description: 'ซ่อมบำรุงเครื่องยนต์',
          source: 'teacher',
        }),
      });
      expect(lg.status < 400, `บันทึกชั่วโมงไม่สำเร็จ ${lg.status} ${JSON.stringify(lg.body)}`);
    }

    const before = await registrar('/dual/placements?status=planned');
    const mine = before.body.find((x: any) => x.id === placementId);
    expect(Number(mine.verified_hours) === 0,
      `ยังไม่รับรอง ชั่วโมงที่นับต้องเป็น 0 ได้ ${mine.verified_hours}`);
    expect(Number(mine.pending_hours) === 15,
      `รอรับรองควรเป็น 15 ได้ ${mine.pending_hours}`);

    const pend = await registrar('/practicum/pending?all=true');
    const ids = pend.body
      .filter((x: any) => x.student_code)
      .map((x: any) => x.id);
    expect(ids.length >= 2, 'ต้องเห็นรายการที่รอรับรอง');

    const vr = await registrar('/practicum/verify', {
      method: 'POST', body: JSON.stringify({ logIds: ids, verify: true }),
    });
    expect(vr.status < 400, `รับรองไม่สำเร็จ ${vr.status} ${JSON.stringify(vr.body)}`);

    const after = await registrar('/dual/placements?status=planned');
    const now = after.body.find((x: any) => x.id === placementId);
    expect(Number(now.verified_hours) === 15,
      `รับรองแล้วต้องนับ 15 ได้ ${now.verified_hours}`);
    expect(Number(now.pending_hours) === 0,
      `รอรับรองต้องเหลือ 0 ได้ ${now.pending_hours}`);
    return 'ก่อนรับรอง 0/15 · หลังรับรอง 15/0';
  });

  await check('API-150 นักศึกษาบันทึกชั่วโมงเองได้ แต่รับรองเองไม่ได้', async () => {
    const lg = await student('/practicum/logs', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, placementId, workplaceId,
        workedOn: '2026-06-03', hours: 8, description: 'บันทึกเอง',
        source: 'student_app',
      }),
    });
    expect(lg.status < 400, `นักศึกษาควรบันทึกได้ ได้ ${lg.status} ${JSON.stringify(lg.body)}`);

    const vr = await student('/practicum/verify', {
      method: 'POST', body: JSON.stringify({ logIds: [lg.body.id], verify: true }),
    });
    expect(vr.status === 403,
      `รับรองเองควรได้ 403 ได้ ${vr.status} — มิฉะนั้นชั่วโมงฝึกจะเป็นตัวเลขที่เจ้าตัวกรอกเองล้วน`);
    return 'บันทึกได้ · รับรองเองไม่ได้';
  });

  await check('API-151 ใบส่งตัวที่ซ้อนช่วงเวลากันไม่ได้', async () => {
    /*
     * นักศึกษาคนหนึ่งไปฝึกสองที่พร้อมกันไม่ได้ — ฐานข้อมูลกันด้วย
     * exclusion constraint ซึ่งกันได้ทุกทางที่เขียนเข้ามา ไม่ใช่แค่ทางนี้
     */
    const dup = await registrar('/dual/placements', {
      method: 'POST',
      body: JSON.stringify({
        studentId: F.student, workplaceId,
        startsOn: '2026-08-01', endsOn: '2026-10-31', targetHours: 200,
      }),
    });
    expect(dup.status >= 400, `ควรถูกปฏิเสธ ได้ ${dup.status}`);
  });

  console.log('');
  console.log('══ เอกสารฉบับภาษาอังกฤษ (0057) ══');

  await check('API-152 บอกได้ก่อนกดว่าออกฉบับอังกฤษได้หรือยัง', async () => {
    /*
     * การรู้**ก่อน**กดต่างจากการรู้ตอนกดมาก สำหรับงานที่ทำทีละหลายสิบคน —
     * เจ้าหน้าที่ที่กดแล้วล้มทีละคนจะเลิกใช้ แล้วกลับไปพิมพ์ด้วยมือ
     */
    const r = await registrar(`/documents/english-readiness/${F.student}`);
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}`);
    expect(typeof r.body.ready === 'boolean', 'ต้องตอบว่าพร้อมหรือยัง');
    expect(Array.isArray(r.body.missing), 'ต้องบอกรายชื่อช่องที่ยังว่าง');
    return r.body.ready
      ? 'พร้อมออกฉบับอังกฤษ'
      : `ยังขาด ${r.body.missing.length} ช่อง · ${r.body.courses.length} รายวิชา`;
  });

  await check('API-153 ออกฉบับอังกฤษไม่ได้ถ้าข้อมูลยังไม่ครบ และบอกว่าขาดอะไร', async () => {
    /*
     * ปล่อยให้ออกโดยเติมภาษาไทยแทนช่องที่ว่าง จะได้เอกสารทางการที่หัวเป็น
     * อังกฤษแต่ชื่อสาขาเป็นไทย และแก้ไม่ได้อีกเลยเพราะ payload ตรึงแล้ว
     */
    const ready = await registrar(`/documents/english-readiness/${F.student}`);
    if (ready.body.ready) return 'ข้าม — ข้อมูลอังกฤษครบแล้วในฐานทดสอบ';

    const r = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript', lang: 'en' }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
    expect(String(JSON.stringify(r.body)).includes('ภาษาอังกฤษ'),
      'ข้อความต้องบอกว่าขาดข้อมูลภาษาอังกฤษ ไม่ใช่ error ดิบจากฐานข้อมูล');
    return 'ปฏิเสธพร้อมบอกสิ่งที่ขาด';
  });

  await check('API-154 ฉบับไทยกับอังกฤษเดินเลขคนละสาย', async () => {
    // ถ้าใช้สายเดียวกัน เลขที่บนใบไทยจะกระโดดทุกครั้งที่มีคนออกใบอังกฤษ
    // ซึ่งงานทะเบียนอธิบายกับผู้ตรวจไม่ได้
    const a = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certification', yearBe: 2569 }),
    });
    expect(a.status < 400, `ออกฉบับไทยไม่สำเร็จ ${a.status} ${JSON.stringify(a.body)}`);

    const b = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certification', yearBe: 2569 }),
    });
    expect(b.status < 400, `ออกฉบับไทยใบที่สองไม่สำเร็จ ${b.status}`);

    const seqA = Number(String(a.body.doc_no).slice(-5));
    const seqB = Number(String(b.body.doc_no).slice(-5));
    expect(seqB === seqA + 1, `ฉบับไทยต้องเดินต่อกัน ได้ ${a.body.doc_no} → ${b.body.doc_no}`);
    expect(String(a.body.doc_no).startsWith('2569'),
      `เลขที่ต้องมีปีการศึกษานำหน้า มิฉะนั้นปีถัดไปจะออกเลขซ้ำ ได้ ${a.body.doc_no}`);
    return `${a.body.doc_no} → ${b.body.doc_no}`;
  });

  await check('API-155 ภาษาที่ไม่รองรับถูกปฏิเสธตั้งแต่ชั้น API', async () => {
    const r = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'certification', lang: 'jp' }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  console.log('');
  console.log('══ แม่แบบใบ รบ. ตระกูล 67 (0058) ══');

  await check('API-156 ใบ รบ. รุ่น 67 จัดกลุ่มตามหมวดและกลุ่มวิชา', async () => {
    /*
     * วัดจากใบจริงแล้วรุ่น 67 จัดกลุ่มตามหมวด → กลุ่มวิชา พร้อมสรุปสามบรรทัด
     * ใต้ทุกกลุ่ม ต่างจากรุ่น 62 ที่จัดตามภาคเรียน — เอาแม่แบบผิดรุ่นไปพิมพ์
     * จะได้ใบที่หน้าตาถูกแต่จัดกลุ่มผิดหลักสูตร ซึ่งมองไม่ออกถ้าไม่รู้ว่า
     * ควรเป็นแบบไหน
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    expect(issued.status < 400, `ออกใบไม่ได้ ${issued.status}`);
    expect(Number(issued.body.payload.program?.edition_be) === 2567,
      'ข้อนี้ต้องใช้นักศึกษาหลักสูตรรุ่น 67');
    expect(Array.isArray(issued.body.payload.category_tree),
      'payload ต้องมีโครงหมวด/กลุ่มวิชา');

    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    expect(html.includes('รบ.1 ปวช.67'),
      'หัวใบต้องเป็นเลขปีสองหลักตามใบจริง ไม่ใช่ ปวช.2567');
    expect(html.includes('ระเบียนแสดงผลการเรียนตามหลักสูตรประกาศนียบัตรวิชาชีพ'),
      'ต้องเลือกแม่แบบรุ่น 67 ไม่ใช่แม่แบบเดิม');
    expect(html.includes('ผ่านเกณฑ์การประเมินมาตรฐานวิชาชีพเมื่อ'),
      'หัวใบรุ่น 67 มีช่องมาตรฐานวิชาชีพซึ่งแม่แบบเดิมไม่มี');
    expect(!/(src|href)\s*=\s*["']https?:/i.test(html), 'ต้องไม่อ้างไฟล์ภายนอก');
    /*
     * ข้อมูลตัวอย่างของชุดนี้ยังไม่มีผลการเรียน จึงพิสูจน์ได้แค่ว่าเลือก
     * แม่แบบถูกและหัวใบถูก — ส่วนการจัดกลุ่มตามหมวด/กลุ่มวิชาและยอดสรุป
     * พิสูจน์ที่ TEST 263 ซึ่งรันบนฐานที่มีผลการเรียนจริง
     * (การยืนยันสิ่งที่ fixture ผลิตไม่ได้ คือเทสต์ที่เขียวโดยไม่ได้ตรวจอะไร)
     */
    return `เลือกแม่แบบรุ่น 67 · ${issued.body.payload.category_tree.length} หมวด`;
  });

  await check('API-157 หน้า 2 มีของประจำครบทุกบล็อก', async () => {
    /*
     * หน้า 2 ของใบจริงมีของตายตัวหกอย่าง ถ้าทำเป็นการไหลต่อเนื่องแล้วรายวิชา
     * เยอะ ของเหล่านี้จะไปโผล่หน้า 3 แล้วใบจะไม่ใช่ใบเดียวกับที่ สอศ. รับ
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    for (const block of [
      'ระดับผลการเรียน', 'ตัวอักษรแสดงระดับผลการเรียน',
      'เกณฑ์การสำเร็จหลักสูตร', 'หมายเหตุ', 'บันทึก', 'หน้าที่ 2',
    ]) {
      expect(html.includes(block), `หน้า 2 ต้องมีบล็อก "${block}"`);
    }
    /*
     * สองหน้าเสมอ ไม่ใช่ไหลตามจำนวนรายวิชา
     * นับด้วย `class="page` ไม่ใช่ `class="page"` เพราะหน้า 2 มีคลาสกำกับ
     * เพิ่ม (`page p2`) — การนับแบบเดิมผูกกับสตริงที่บังเอิญตรง ไม่ใช่กับ
     * สิ่งที่ต้องพิสูจน์ ซึ่งคือ "มีสองหน้า"
     */
    expect((html.match(/class="page[ "]/g) ?? []).length === 2,
      'ใบต้องมีสองหน้าตายตัว');
    /*
     * และกรอบตารางต้องถูกตีไว้ครบทั้งสองหน้า — ใบของนักศึกษาที่ลงวิชาน้อย
     * ต้องได้กรอบเปล่าที่หน้า 2 ไม่ใช่หน้าที่ไม่มีตารางเลย มิฉะนั้นใบสองใบ
     * ของวิทยาลัยเดียวกันจะหน้าตาไม่เหมือนกัน
     */
    expect((html.match(/class="grid g[12]"/g) ?? []).length === 2,
      'ต้องตีกรอบตารางไว้ทั้งสองหน้า ไม่ว่าจะมีรายวิชากี่ตัว');
    return 'ครบหกบล็อก · สองหน้า · กรอบตารางครบสองหน้า';
  });

  await check('API-158 ใบรุ่น 67 ที่ยกเลิกแล้วต้องมีตราและวันที่ออก', async () => {
    // ใบที่ยกเลิกยังพิมพ์ได้เพราะต้องตรวจย้อนหลัง แต่ต้องมองปราดเดียวรู้
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    await registrar(`/documents/${issued.body.id}/void`, {
      method: 'POST', body: JSON.stringify({ reason: 'ทดสอบ' }),
    });
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    expect(html.includes('ยกเลิก'), 'ต้องมีตราว่ายกเลิก');
    expect(/ออกให้เมื่อ \d{1,2} [ก-๙]+ 25\d\d/.test(html),
      'ต้องมีวันที่ออกเป็นวันที่ไทยแบบเต็ม');
  });

  console.log('');
  await check('API-159 หัวเรื่องใบ รบ. ต่างตามระดับและหลักสูตรต่อเนื่อง', async () => {
    /*
     * วัดจากไฟล์จริง — ปวช. กับ ปวส. ใช้ถ้อยคำคุณวุฒิต่างกัน และ ปวส.
     * ต่อเนื่องเติม "(ต่อเนื่อง)" เฉพาะฉบับไทย ส่วนฉบับอังกฤษใช้ชื่อเดียว
     * กับ ปวส. ปกติ · และฉบับอังกฤษใช้ **ปีคริสต์ศักราช** ไม่ใช่ พ.ศ.
     * ซึ่งเป็นข้อที่เดาไม่ถูกถ้าไม่ได้เปิดไฟล์ดู
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    const level = issued.body.payload.program?.level;

    if (level === 'PVC') {
      expect(html.includes('ประกาศนียบัตรวิชาชีพ พุทธศักราช'),
        'ปวช. ต้องใช้ถ้อยคำ "ประกาศนียบัตรวิชาชีพ"');
      expect(!html.includes('สาขาวิชาเดิม'),
        'ปวช. ไม่มีช่องสาขาวิชาเดิม — ช่องนี้มีเฉพาะ ปวส.');
    } else if (level === 'PVS') {
      expect(html.includes('ประกาศนียบัตรวิชาชีพชั้นสูง'),
        'ปวส. ต้องใช้ถ้อยคำ "ประกาศนียบัตรวิชาชีพชั้นสูง"');
      expect(html.includes('สาขาวิชาเดิม'), 'ปวส. ต้องมีช่องสาขาวิชาเดิม');
    }
    return `ระดับ ${level}`;
  });

  console.log('');
  console.log('══ แม่แบบใบ รบ. ตระกูล 62 (0060) ══');

  /*
   * ─── ทำไมต้องสลับรุ่นหลักสูตรชั่วคราว ───
   * นักศึกษาตัวอย่างของชุดนี้อยู่หลักสูตรรุ่น 67 ซึ่งเป็นรุ่นปัจจุบันและ
   * เป็นสิ่งที่เทสต์อีกหลายข้อพึ่งอยู่ ถ้าไม่สลับ แม่แบบตระกูล 62 จะไม่มี
   * ทางถูกเรียกผ่าน HTTP เลยสักครั้ง — เทสต์ที่ทดสอบเฉพาะเส้นทางที่ระบบจริง
   * เดินอยู่แล้ว ไม่ได้พิสูจน์ว่าเส้นทางอีกเส้นทำงาน (บทเรียนเดียวกับ AUTH-26
   * ที่ผ่านมาตลอดเพราะหยิบ token จากทางที่ระบบจริงไม่มี)
   *
   * คืนค่าเดิมใน finally เสมอ มิฉะนั้นเทสต์ที่รันทีหลังจะเห็นรุ่นผิด
   */
  async function withEdition<T>(editionBe: number, fn: () => Promise<T>): Promise<T> {
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    const before = await db.query(
      `select cv.id, cv.edition_be from curriculum_version cv
         join student_curriculum sc on sc.curriculum_version_id = cv.id
        where sc.student_id = $1 limit 1`,
      [F.studentRegrade],
    );
    const cvId = before.rows[0]?.id;
    const cvWas = before.rows[0]?.edition_be;
    try {
      if (cvId) {
        await db.query('update curriculum_version set edition_be = $2 where id = $1',
          [cvId, editionBe]);
      }
      return await fn();
    } finally {
      if (cvId) {
        await db.query('update curriculum_version set edition_be = $2 where id = $1',
          [cvId, cvWas]);
      }
      await db.end();
    }
  }

  await check('API-160 รุ่นก่อน 67 ได้แม่แบบที่จัดตามภาคเรียนและมีคอลัมน์ผลคูณ', async () => {
    /*
     * ใบตระกูล 62 ต่างจาก 67 สามอย่างที่วัดจากไฟล์จริง — จัดตามภาคเรียน ·
     * มีคอลัมน์ (1)×(2) · และ**ฉบับไทยไม่มีบรรทัดชื่อเรื่องเลย** เพราะพิมพ์
     * ลงกระดาษที่มีหัวอยู่แล้ว การพิมพ์ชื่อเรื่องซ้ำจะได้ใบที่มีหัวสองชั้น
     */
    // 2562 มีอยู่แล้วในหลักสูตรเดียวกัน (unique curriculum_id, edition_be)
    // จึงใช้ 2556 ซึ่งเป็นรุ่นที่ยังมีนักศึกษาค้างอยู่จริงในวิทยาลัยหลายแห่ง
    const html = await withEdition(2556, async () => {
      const issued = await registrar('/documents/issue', {
        method: 'POST',
        body: JSON.stringify({ studentId: F.studentRegrade, kind: 'transcript' }),
      });
      expect(issued.status < 400, `ออกใบไม่ได้ ${issued.status}`);
      const tree = issued.body.payload.term_tree;
      expect(Array.isArray(tree) && tree.length > 0,
        'นักศึกษาคนนี้มีผลการเรียนอยู่ ต้องได้โครงภาคเรียนกลับมา');
      return String((await registrar(`/documents/${issued.body.id}/print`)).body);
    });

    expect(html.includes('(1)') && html.includes('(2)'),
      'ต้องมีคอลัมน์ผลคูณ (1)×(2) ซึ่งตระกูล 67 ไม่มี');
    expect(html.includes('หน่วยกิตที่ได้ในภาค') && html.includes('หน่วยกิตสะสม'),
      'ต้องมีบรรทัดสรุปท้ายภาคทั้งสองตัว');
    expect(/ปีการศึกษา \d{4}(&nbsp;)+ภาคเรียนที่ \d/.test(html),
      'ต้องมีหัวภาคเรียนคั่นกลางตาราง — ตระกูลนี้จัดกลุ่มตามภาค ไม่ใช่ตามหมวด');
    expect(!html.includes('<h1>'),
      'ฉบับไทยของตระกูลนี้ต้องไม่มีบรรทัดชื่อเรื่อง — เว้นที่ไว้ให้หัวกระดาษ');
    expect(!html.includes('รบ.1'),
      'ฉบับไทยของตระกูลนี้ไม่มีเลขที่ รบ. ที่มุมขวาบน (วัดแล้วไม่มีข้อความใดเหนือ y = 76)');
    expect(!html.includes('หมวดวิชา') && !html.includes('กลุ่มวิชา'),
      'ต้องไม่ปนโครงหมวด/กลุ่มวิชาของตระกูล 67 เข้ามา');
    expect(!/(src|href)\s*=\s*["']https?:/i.test(html), 'ต้องไม่อ้างไฟล์ภายนอก');
    return 'เลือกแม่แบบตระกูล 62 ได้ถูก · มีคอลัมน์ผลคูณและหัวภาคเรียน';
  });

  await check('API-161 ภาคที่ยังไม่ได้ตัดยอดต้องพิมพ์ "-" ไม่ใช่ตัวเลขที่เดา', async () => {
    /*
     * นักศึกษาคนนี้มีผลการเรียนแล้วแต่ยังไม่มีแถวใน `term_summary`
     * (ยังไม่ได้ตัดยอดภาค) ซึ่งเป็นสภาพปกติของคนที่ขอใบระหว่างเรียน
     *
     * ถ้าคืน 0 หรือบวกเท่าที่มี ใบจะพิมพ์หน่วยกิตสะสมที่ต่ำกว่าความจริงและ
     * ดูสมเหตุสมผลทุกประการ — คนถือใบไปยื่นที่อื่นไม่มีทางรู้ว่าตัวเลขขาด
     * `transcript_term_tree()` จึงคืน null แล้วแม่แบบพิมพ์ "-" ซึ่งอ่านออกว่า
     * "ยังไม่รู้" (ส่วนการบวกสะสมเมื่อตัดยอดครบ พิสูจน์ที่ TEST 265)
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.studentRegrade, kind: 'transcript' }),
    });
    const tree = issued.body.payload.term_tree as Array<Record<string, unknown>>;
    expect(Array.isArray(tree) && tree.length > 0, 'payload ต้องมี term_tree ที่ไม่ว่าง');

    let unsummarised = 0;
    for (const t of tree) {
      expect('credits_cum' in t, 'ทุกภาคต้องมีหน่วยกิตสะสมมาด้วย ไม่ใช่ให้แม่แบบบวกเอง');
      expect('gpax' in t && 'gpa' in t, 'ทุกภาคต้องมีทั้งคะแนนเฉลี่ยรายภาคและสะสม');
      if (!t.has_summary) {
        unsummarised++;
        expect(t.credits_cum === null,
          'ภาคที่ยังไม่ได้ตัดยอดต้องคืนหน่วยกิตสะสมเป็น null ไม่ใช่ 0');
      }
    }
    expect(unsummarised > 0,
      'ข้อนี้ต้องมีภาคที่ยังไม่ได้ตัดยอดอย่างน้อยหนึ่ง มิฉะนั้นผ่านโดยไม่ได้ตรวจอะไร');
    return `${tree.length} ภาค · ยังไม่ตัดยอด ${unsummarised} ภาค`;
  });

  await check('API-162 ใบที่ออกก่อนมีโครงภาคเรียนต้องไม่พิมพ์ตารางเปล่า', async () => {
    /*
     * ใบที่ออกก่อน 0060 ไม่มี `term_tree` ใน payload และแก้เพิ่มไม่ได้เลย
     * ถ้าเลือกแม่แบบจากรุ่นหลักสูตรอย่างเดียว การพิมพ์ซ้ำใบเก่าจะได้ตาราง
     * รายวิชาว่างโดยที่หัวใบยังถูกทุกช่อง — เป็นใบที่ดูใช้ได้แต่ไม่มีเนื้อ
     */
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    try {
      const issued = await withEdition(2556, async () => {
        const r = await registrar('/documents/issue', {
          method: 'POST',
          body: JSON.stringify({ studentId: F.studentRegrade, kind: 'transcript' }),
        });
        expect(r.status < 400, `ออกใบไม่ได้ ${r.status}`);
        return r.body;
      });
      // จำลองใบเก่า — payload ของ issued_document แก้ไม่ได้ด้วย trigger
      // จึงต้องปิด trigger ชั่วคราวด้วยสิทธิ์เจ้าของตาราง
      await db.query('alter table issued_document disable trigger user');
      await db.query(
        `update issued_document set payload = payload - 'term_tree' - 'category_tree'
          where id = $1`, [issued.id]);
      await db.query('alter table issued_document enable trigger user');

      const html = String((await registrar(`/documents/${issued.id}/print`)).body);
      expect(html.includes('ระเบียนแสดงผลการเรียน'),
        'ต้องตกไปใช้แม่แบบเดิมที่พิมพ์จาก courses ได้ ไม่ใช่แม่แบบที่ต้องมีโครง');
      expect(!html.includes('หน่วยกิตที่ได้ในภาค'),
        'ใบเก่าต้องไม่ถูกส่งเข้าแม่แบบตระกูล 62 ซึ่งจะได้ตารางเปล่า');
      return 'ใบเก่าตกไปใช้แม่แบบเดิม';
    } finally {
      await db.query('alter table issued_document enable trigger user').catch(() => undefined);
      await db.end();
    }
  });

  await check('API-163 ใบฉบับอังกฤษต้องไม่มีเดือนไทยและปีพุทธศักราช', async () => {
    /*
     * ─── ทุกวันที่และทุกปีบนใบฉบับอังกฤษเป็นคริสต์ศักราช ───
     * วัดจากไฟล์จริงคู่กัน — "5 เมษายน 2552" ตรงกับ "April 5, 2009" และ
     * "ปีการศึกษาที่จบ 2567" ตรงกับ "Year of Graduated 2024"
     *
     * ก่อนหน้านี้แม่แบบทั้งสองตระกูลเรียก `thaiDate()` ทุกที่ ใบฉบับอังกฤษ
     * จึงพิมพ์ "31 มีนาคม 2569" อยู่กลางเอกสารภาษาอังกฤษ ซึ่งผู้อ่านต่างชาติ
     * อ่านไม่ออกทั้งเดือนและปี — และถ้าอ่านตัวเลขปีออก จะเข้าใจว่าเป็นวันที่
     * ในอนาคตอีก 543 ปี ข้อนี้ไม่มีอะไรฟ้องเลยเพราะใบยังพิมพ์ออกมาสวยงาม
     */
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    try {
      // เติมข้อมูลอังกฤษให้ครบก่อน มิฉะนั้น 0057 ปฏิเสธการออกใบ (ซึ่งถูก)
      await db.query(
        `update person set prefix_en = 'Mr.', first_name_en = 'Withaya',
                last_name_en = 'Sombat'
          where id = $1`, [F.personRegrade]);
      await db.query(`update program_type set name_en = 'Industry' where name_en is null`);
      await db.query(`update program set name_en = 'Automotive Technology' where name_en is null`);
      await db.query(`update program_track set name_en = 'Automotive Works' where name_en is null`);
      await db.query(`update course set name_en = 'Small Engine Work'
                       where name_en is null or name_en = code`);

      const issued = await registrar('/documents/issue', {
        method: 'POST',
        body: JSON.stringify({ studentId: F.studentRegrade, kind: 'transcript', lang: 'en' }),
      });
      expect(issued.status < 400,
        `ออกฉบับอังกฤษไม่ได้ ${issued.status} ${JSON.stringify(issued.body).slice(0, 200)}`);

      const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
      const months = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
        'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];
      for (const m of months) {
        expect(!html.includes(m), `ใบฉบับอังกฤษต้องไม่มีชื่อเดือนไทย "${m}"`);
      }
      expect(/(January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}/.test(html),
        'ต้องมีวันที่แบบอังกฤษอย่างน้อยหนึ่งที่ (เช่น August 10, 2026)');
      /*
       * เลขที่เอกสารมีปีการศึกษาเป็น พ.ศ. อยู่ในตัว (E256900001) โดยตั้งใจ
       * เพราะเป็นเลขทะเบียนของงานทะเบียนไทย ไม่ใช่ข้อความที่แปลได้ —
       * ตัดออกก่อนตรวจ มิฉะนั้นข้อนี้จะบังคับให้เปลี่ยนระบบเลขที่ทั้งระบบ
       */
      const withoutDocNo = html.split(String(issued.body.doc_no)).join('');
      expect(!/\b25[0-9]{2}\b/.test(withoutDocNo.replace(/[0-9]{6,}/g, '')),
        'ใบฉบับอังกฤษต้องไม่มีปีพุทธศักราช 25xx นอกเหนือจากเลขที่เอกสาร');
      return 'เดือนอังกฤษ · ปีคริสต์ศักราช';
    } finally {
      await db.end();
    }
  });

  console.log('');
  console.log('══ ตัวเลือกตอนพิมพ์ (กระดาษตรา) ══');

  await check('API-164 กระดาษตราไม่พิมพ์หัวซ้ำและย่อตารางลง', async () => {
    /*
     * วัดจากไฟล์คู่ `แนวตั้ง 62` กับ `แนวตั้ง 62 กระดาษตรา` ที่เป็นข้อมูล
     * ชุดเดียวกัน — ฉบับกระดาษตรา**ไม่มีทั้งชื่อเรื่องและเลขที่** เพราะ
     * กระดาษพิมพ์มาแล้ว ถ้าพิมพ์ซ้ำจะได้ใบที่มีหัวสองชั้น
     * และเส้นบนสุดของตารางต่ำลง 17.6 pt · ขอบล่างเพิ่ม 43.7 pt ·
     * ฟอนต์ในตารางย่อจาก 12.5 เหลือ 10
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const base = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    const head = String(
      (await registrar(`/documents/${issued.body.id}/print?paper=letterhead`)).body,
    );

    expect(base.includes('<h1>'), 'ใบบนกระดาษเปล่าต้องมีชื่อเรื่อง');
    expect(head.includes('display: none !important'),
      'กระดาษตราต้องซ่อนชื่อเรื่องและเลขที่ มิฉะนั้นจะได้ใบที่มีหัวสองชั้น');
    expect(head.includes('padding-top: 17.6pt') && head.includes('padding-bottom: 43.7pt'),
      'กระดาษตราต้องเลื่อนเนื้อหาลงและเว้นขอบล่างตามที่วัดจากไฟล์จริง');
    expect(head.includes('table.courses { font-size: 10pt; }'),
      'ตารางต้องย่อลงเพื่อชดเชยพื้นที่ที่หายไป');
    // เนื้อหาต้องเป็นใบเดียวกัน — ตัวเลือกนี้เปลี่ยนการวางหน้า ไม่ใช่เนื้อหา
    expect(head.includes(String(issued.body.doc_no)),
      'เลขที่ยังต้องอยู่ในเอกสาร (แค่ไม่พิมพ์ที่มุมขวาบน)');
    return 'ซ่อนหัว · เลื่อนลง · ย่อตาราง';
  });

  await check('API-165 ระยะเลื่อนถูกจำกัดและค่าผิดรูปแบบถูกปฏิเสธ', async () => {
    /*
     * ─── ทำไมต้องมีเพดาน ───
     * ไม่มีหน้าตัวอย่างให้ดูก่อนพิมพ์ คนที่พิมพ์ 200 ลงไปจะได้กระดาษเปล่า
     * ทั้งใบโดยไม่รู้ว่าเนื้อหาไปอยู่ไหน — จำกัดที่ครึ่งนิ้วซึ่งเกินพอสำหรับ
     * ความเหลื่อมของถาดป้อนกระดาษ
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const ok = String(
      (await registrar(`/documents/${issued.body.id}/print?offsetX=4.5&offsetY=-8`)).body,
    );
    expect(ok.includes('left: 4.5pt; top: -8pt'), 'ระยะเลื่อนต้องถูกนำไปใช้จริง');

    const clamped = String((await registrar(`/documents/${issued.body.id}/print?offsetY=99`)).body);
    expect(clamped.includes('top: 36pt'), `ต้องจำกัดที่ 36 pt ได้ ${clamped.slice(0, 0)}`);

    for (const bad of ['paper=banana', 'offsetX=abc', 'offsetY=1e9', 'zoom=2']) {
      const r = await registrar(`/documents/${issued.body.id}/print?${bad}`);
      expect(r.status === 400, `"${bad}" ควรถูกปฏิเสธ ได้ ${r.status}`);
    }
    return 'ใช้ได้ในช่วง · เกินถูกจำกัด · ค่าผิดถูกปฏิเสธ';
  });

  await check('API-166 เอกสารทำงานไม่รับตัวเลือกกระดาษตรา', async () => {
    /*
     * ใบรายชื่อและใบเช็คชื่อเปล่าเป็น**เอกสารทำงาน** (หลักข้อ 4ก) พิมพ์ลง
     * กระดาษเปล่าเสมอ การเปิดตัวเลือกให้ด้วยจะทำให้เจ้าหน้าที่ตั้งครั้งเดียว
     * แล้วใบรายชื่อย่อฟอนต์ลงตามไปด้วยโดยไม่มีเหตุผล
     */
    const r = await registrar(`/reports/roster/${F.section}?paper=letterhead`);
    expect(r.status === 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
    const ok = await registrar(`/reports/roster/${F.section}`);
    expect(ok.status < 400, `ใบรายชื่อปกติต้องยังพิมพ์ได้ ได้ ${ok.status}`);
    return 'ปฏิเสธตัวเลือกที่ไม่เกี่ยว';
  });

  await check('API-170 แบบ สอศ. ย้ายสรุปรายภาคไปเป็นตารางแนวนอนหน้า 2', async () => {
    /*
     * วัดจากไฟล์จริง — แบบ สอศ. ใช้ตัวเลขชุดเดียวกับแบบ 62 แต่วางเป็น
     * **ตารางแนวนอนหนึ่งคอลัมน์ต่อหนึ่งภาค** แทนที่จะไหลอยู่ในตารางรายวิชา
     * และใช้ถ้อยคำไทยของ 2.5 ต่างออกไปหนึ่งคำ (ดีพอใช้ ไม่ใช่ ค่อนข้างดี)
     *
     * ─── ทำไมเลือกได้ตอนพิมพ์ ต่างจากการเลือกตระกูล ───
     * สองแบบนี้จัดกลุ่มรายวิชาเหมือนกันทุกประการ ตัวเลขบนใบเท่ากันหมด
     * ต่างแค่การวางหน้า — เป็นเรื่องของหน่วยงานที่จะยื่นให้ ไม่ใช่ข้อเท็จจริง
     * ของนักศึกษา ส่วนการเลือกตระกูล 67/62 ต้องมาจากรุ่นหลักสูตรใน payload
     * เพราะจัดกลุ่มคนละแบบจริง ๆ
     */
    const [plain, sorsor] = await withEdition(2556, async () => {
      const issued = await registrar('/documents/issue', {
        method: 'POST',
        body: JSON.stringify({ studentId: F.studentRegrade, kind: 'transcript' }),
      });
      expect(issued.status < 400, `ออกใบไม่ได้ ${issued.status}`);
      return [
        String((await registrar(`/documents/${issued.body.id}/print`)).body),
        String((await registrar(`/documents/${issued.body.id}/print?form=sorsor`)).body),
      ];
    });

    /*
     * ตรวจที่โครงสร้าง ไม่ใช่ที่คำ — คำว่า "สรุปผลการเรียน" อยู่ในคอมเมนต์
     * ของ CSS ซึ่งติดไปกับทุกใบอยู่แล้ว เทสต์ที่ค้นคำจึงเขียวทั้งที่ผิด
     */
    expect(sorsor.includes('<div class="matrix">'), 'แบบ สอศ. ต้องมีตารางสรุปผลการเรียน');
    expect(!plain.includes('<div class="matrix">'), 'แบบ 62 ต้องไม่มีตารางนั้น');
    expect(sorsor.includes('ดีพอใช้') && !sorsor.includes('ค่อนข้างดี'),
      'แบบ สอศ. ใช้ "ดีพอใช้" สำหรับ 2.5');
    expect(plain.includes('ค่อนข้างดี') && !plain.includes('ดีพอใช้'),
      'แบบ 62 ใช้ "ค่อนข้างดี" สำหรับ 2.5');

    /*
     * ตัวเลขชุดเดียวกันต้องไม่ถูกพิมพ์สองที่บนใบเดียว — คนอ่านจะสงสัยว่า
     * ทำไมไม่เท่ากัน ทั้งที่เท่ากัน
     */
    const inlineCount = (sorsor.match(/หน่วยกิตที่ได้ในภาค/g) ?? []).length;
    expect(inlineCount === 1, `แบบ สอศ. ต้องมีสรุปที่เดียว พบ ${inlineCount} ที่`);

    const bad = await registrar(`/documents/${'0'.repeat(8)}-0000-0000-0000-000000000000/print?form=xx`);
    expect(bad.status === 400, `รูปแบบที่ไม่รู้จักควรได้ 400 ได้ ${bad.status}`);
    return 'ตารางแนวนอน · ถ้อยคำต่างกันหนึ่งคำ · ไม่พิมพ์ซ้ำสองที่';
  });

  await check('API-171 ใบ รบ. ต้องฝังฟอนต์มาในหน้า ไม่ใช่พึ่งฟอนต์ในเครื่อง', async () => {
    /*
     * ─── ทำไมข้อนี้ต้องมี ───
     * เรขาคณิตของใบ รบ. ทั้งใบคิดบนความกว้างตัวอักษรของ TH Sarabun New
     * เครื่องที่ไม่มีฟอนต์นี้จะตกไปใช้ตัวสำรองซึ่งกว้างกว่า 8% (Angsana)
     * ถึง 47% (Leelawadee UI) แล้วชื่อวิชาจะตัดบรรทัดคนละที่กับใบจริง
     * จนตารางล้นกรอบ — **โดยที่ไม่มีอะไรฟ้องนอกจากตาคนที่ถือกระดาษ**
     *
     * และฟอนต์อยู่ใน `fonts.ts` ไม่ใช่ไฟล์ .woff2 ข้าง ๆ เพราะ `tsc`
     * ไม่คัดลอกไฟล์ที่ไม่ใช่ .ts ไป dist/ — ถ้าวันหนึ่งมีคนย้ายไปเป็นไฟล์
     * ฟอนต์จริง ระบบจริงจะไม่มีฟอนต์ติดไปด้วยโดยที่เทสต์ยังเขียว
     * ข้อนี้จึงตรวจที่ **ผลลัพธ์ที่ส่งออกไป** ไม่ใช่ตรวจว่าไฟล์มีอยู่
     */
    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);

    // นับเฉพาะประกาศจริง ไม่ใช่คำว่า @font-face ที่โผล่ในคอมเมนต์ของ CSS
    const faces = (html.match(/@font-face\s*\{/g) ?? []).length;
    expect(faces === 2, `ต้องฝังทั้งน้ำหนักปกติและตัวหนา พบ ${faces} หน้าตัด`);
    expect(html.includes("font-family: 'TH Sarabun New'"),
      'ฟอนต์ที่ฝังต้องชื่อตรงกับที่ font-family ของแม่แบบเรียกใช้');
    for (const weight of ['font-weight: 400', 'font-weight: 700']) {
      expect(html.includes(weight), `ต้องมี @font-face ของ ${weight}`);
    }
    const embedded = (html.match(/url\(data:font\/woff2;base64,/g) ?? []).length;
    expect(embedded >= 2, `ฟอนต์ต้องฝังเป็น data: URI พบ ${embedded} ชุด`);

    /*
     * และต้องไม่มีทางที่หน้านี้จะไปดึงอะไรจากเน็ต — เจ้าหน้าที่ต้องพิมพ์ใบได้
     * แม้อินเทอร์เน็ตของวิทยาลัยล่ม (API-156 ตรวจเฉพาะ src=/href= ซึ่งจับ
     * `url(https://…)` ใน CSS ไม่ได้ — ฟอนต์เข้ามาทางนั้นพอดี)
     */
    expect(!/url\(\s*["']?https?:/i.test(html), 'CSS ต้องไม่ดึงไฟล์จากภายนอก');
    return `ฝัง ${faces} หน้าตัด · ${Math.round(html.length / 1024)} KB`;
  });

  await check('API-172 ช่องบนหัวใบต้องมีค่าจริง ไม่ใช่หัวข้อพร้อมช่องว่าง', async () => {
    /*
     * ─── สิ่งที่ข้อนี้ดัก ───
     * แม่แบบเคย**ฮาร์ดโค้ดค่าว่าง**ลงในช่องเชื้อชาติ · สัญชาติ · ศาสนา ·
     * ชื่อบิดา · ชื่อมารดา · จังหวัด · กลุ่มอาชีพ ทั้งที่ฐานข้อมูลมีข้อมูล
     * อยู่ตั้งแต่ 0053 — ใบทุกใบจึงพิมพ์หัวข้อครบแล้วเว้นค่าว่างไว้หมด
     *
     * เป็นความผิดพลาดที่**เทสต์ payload จับไม่ได้เลย** เพราะ payload ถูกต้อง
     * มาตลอด ต้องดูที่ HTML ที่พิมพ์ออกมาจริงถึงจะเห็น — รูปเดียวกับสามข้อ
     * ที่เจอตอนอ่านกระดาษที่พิมพ์ออกมา (หน่วยกิตสะสม · หน่วยกิตที่เรียน ·
     * วันที่ไทยบนใบอังกฤษ)
     */
    const save = async (path: string, body: unknown) => {
      const r = await registrar(path, { method: 'POST', body: JSON.stringify(body) });
      expect(r.status < 400, `บันทึกไม่ได้ ${path} → ${r.status} ${JSON.stringify(r.body)}`);
    };
    await save(`/students/${F.student}/sensitive`,
      { ethnicity: 'ไทยทดสอบ', religion: 'พุทธทดสอบ' });
    await save(`/students/${F.student}/parents`,
      { role: 'father', prefixTh: 'นาย', firstNameTh: 'บิดาทดสอบ', lastNameTh: 'นามสมมติ' });
    await save(`/students/${F.student}/parents`,
      { role: 'mother', prefixTh: 'นาง', firstNameTh: 'มารดาทดสอบ', lastNameTh: 'นามสมมติ' });

    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    expect(issued.status < 400, `ออกใบไม่ได้ ${issued.status}`);
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);

    for (const [what, value] of [
      ['เชื้อชาติ', 'ไทยทดสอบ'], ['ศาสนา', 'พุทธทดสอบ'],
      ['ชื่อบิดา', 'บิดาทดสอบ'], ['ชื่อมารดา', 'มารดาทดสอบ'],
    ] as const) {
      expect(html.includes(value), `ช่อง "${what}" ต้องมีค่าจริงบนใบ ไม่ใช่หัวข้อเปล่า`);
    }
    /*
     * และ payload ต้องมีเฉพาะสามช่องของ person_sensitive ที่ใบแสดงจริง
     * ไม่ใช่ทั้งตาราง — หมู่เลือด โรคประจำตัว ความพิการ ห้ามติดไปด้วย
     * เพราะ payload ลบไม่ได้ (หลักข้อ 5ก)
     */
    const extra = issued.body.payload.person_extra ?? {};
    expect(Object.keys(extra).sort().join(',') === 'ethnicity,nationality,religion',
      `payload ต้องมีสามช่องเท่านั้น พบ ${Object.keys(extra).join(',')}`);
    return 'เชื้อชาติ · ศาสนา · บิดา · มารดา ขึ้นใบจริง · payload ไม่เกินสามช่อง';
  });

  await check('API-173 เหตุที่ออกกรอกได้จริงและขึ้นใบ รบ.', async () => {
    /*
     * ─── สิ่งที่ข้อนี้ดัก ───
     * `student_status_history.reason` กับ `document_no` มีคอลัมน์มาตั้งแต่
     * 0002 แล้ว **ไม่มีอะไรเขียนลงไปเลยสักแถว** เพราะ trigger เขียนแค่สี่ช่อง
     * ใบ รบ. จึงพิมพ์หัวข้อ "เหตุที่ออก" ไว้แล้วเว้นว่างเสมอ และไม่มีที่ให้กรอก
     *
     * ตรวจถึง HTML ที่พิมพ์ออกมา ไม่ใช่แค่ว่า API ตอบ 200 — เพราะโซ่นี้ยาว
     * (API → student → trigger → history → transcript_extra → payload → แม่แบบ)
     * ขาดข้อไหนก็ได้ใบเปล่าเหมือนกันหมด
     */
    const st = await registrar(`/students/${F.student}/status`, {
      method: 'POST',
      body: JSON.stringify({
        status: 'graduated', effectiveOn: '2569-03-31',
        reason: 'สำเร็จการศึกษาตามหลักสูตร', documentNo: 'คำสั่งที่ 12/2569',
      }),
    });
    expect(st.status < 400, `เปลี่ยนสถานะไม่ได้ ${st.status} ${JSON.stringify(st.body)}`);

    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    expect(html.includes('สำเร็จการศึกษาตามหลักสูตร'),
      'เหตุที่ออกต้องขึ้นบนใบ ไม่ใช่หัวข้อพร้อมช่องว่าง');
    expect(issued.body.payload.leaving?.reason === 'สำเร็จการศึกษาตามหลักสูตร',
      'payload ต้องมีเหตุที่ออก');

    /*
     * ─── สถานะที่แปลว่าออกจากสถานศึกษาต้องบังคับเหตุผล ───
     * ใบที่พิมพ์ "เหตุที่ออก" ว่างไว้คือเอกสารที่ตอบคำถามของคนอ่านไม่ได้
     * และตอนที่นักศึกษามาขอใบก็สายเกินกว่าจะย้อนไปถามว่าตอนนั้นเกิดอะไรขึ้น
     */
    const noReason = await registrar(`/students/${F.student}/status`, {
      method: 'POST',
      body: JSON.stringify({ status: 'dismissed', effectiveOn: '2569-03-31' }),
    });
    expect(noReason.status === 400, `สถานะที่ออกจากสถานศึกษาต้องบังคับเหตุผล ได้ ${noReason.status}`);

    // ส่วนสถานะที่ยังอยู่ในสถานศึกษาไม่ต้องบังคับ — ถามในสิ่งที่ไม่มีใครใช้
    // จะได้จุดเดียวไปให้พ้น ๆ ซึ่งแย่กว่าไม่ถาม
    const back = await registrar(`/students/${F.student}/status`, {
      method: 'POST',
      body: JSON.stringify({ status: 'active', effectiveOn: '2569-04-01' }),
    });
    expect(back.status < 400, `สถานะที่ยังอยู่ต้องไม่บังคับเหตุผล ได้ ${back.status}`);
    return 'กรอกได้ · ขึ้นใบ · บังคับเฉพาะสถานะที่ออกจริง';
  });

  await check('API-174 แก้วันสำเร็จการศึกษาได้ แต่แก้ GPAX ไม่ได้', async () => {
    /*
     * จบช้าหรือกรอกวันผิดต้องแก้ได้ — แต่แก้ที่**ระเบียนจบ** ไม่ใช่ตอนกดพิมพ์
     * เพราะ payload ตรึงแล้ว คนที่พิมพ์ผิดจะต้องยกเลิกใบแล้วออกใหม่ ซึ่งกิน
     * เลขที่เพิ่มทุกครั้ง · และ gpax ตรึงตอนอนุมัติจบ (หลักข้อ 5) ห้ามแก้ทางนี้
     */
    /*
     * ─── อ่านค่าเดิมจากผลของ PATCH เอง ไม่พึ่งเส้นทางอื่น ───
     * ถ้าตรวจก่อนว่ามีระเบียนจบไหมแล้วข้ามเมื่อไม่มี ข้อนี้จะกลายเป็นเทสต์ที่
     * ผ่านโดยไม่ได้ตรวจอะไร — ซึ่งแย่กว่าไม่มีเทสต์ เพราะดูเหมือนมีคนดูแลอยู่
     */
    const first = await registrar(`/graduation/students/${F.student}/completed-on`, {
      method: 'PATCH', body: JSON.stringify({ completedOn: '2569-09-30' }),
    });
    expect(first.status < 400,
      `แก้วันจบไม่ได้ ${first.status} ${JSON.stringify(first.body)} — ` +
      'ข้อนี้ต้องรันหลังเทสต์ที่อนุมัติจบให้นักศึกษาตัวอย่างแล้ว');
    expect(String(first.body.completed_on).startsWith('2569-09-30'),
      `วันจบต้องเปลี่ยนจริง ได้ ${first.body.completed_on}`);
    const gpaxBefore = String(first.body.gpax);

    const r = await registrar(`/graduation/students/${F.student}/completed-on`, {
      method: 'PATCH', body: JSON.stringify({ completedOn: '2570-03-31' }),
    });
    expect(r.status < 400, `แก้วันจบรอบสองไม่ได้ ${r.status}`);
    expect(String(r.body.completed_on).startsWith('2570-03-31'),
      `วันจบต้องเปลี่ยนได้อีก ได้ ${r.body.completed_on}`);
    expect(String(r.body.gpax) === gpaxBefore,
      `GPAX ต้องไม่เปลี่ยน — ${gpaxBefore} → ${r.body.gpax}`);

    // ฟิลด์ที่ไม่ได้ประกาศใน DTO ต้องถูกปฏิเสธ ไม่ใช่เมินเงียบ ๆ
    const sneaky = await registrar(`/graduation/students/${F.student}/completed-on`, {
      method: 'PATCH',
      body: JSON.stringify({ completedOn: '2569-09-30', gpax: 4.0 }),
    });
    expect(sneaky.status === 400, `ฟิลด์แปลกปลอมต้องถูกปฏิเสธ ได้ ${sneaky.status}`);
    return 'แก้วันได้ · GPAX ไม่ขยับ · ฟิลด์แปลกปลอมถูกปฏิเสธ';
  });

  await check('API-175 จัดลำดับและย้ายภาคของรายวิชาในหลักสูตรได้', async () => {
    /*
     * สองค่านี้เป็นตัวกำหนดหน้าตาของใบ รบ. — suggested_year/term บอกว่า
     * รายวิชาไปอยู่ภาคไหน (0063) ส่วน sort_order บอกลำดับภายในภาคนั้น
     * ก่อนหน้านี้ตั้งได้ครั้งเดียวตอนเพิ่มรายวิชา แก้ทีหลังไม่ได้เลย
     */
    const versions = await registrar('/curriculum/versions');
    const version = (versions.body as any[])?.find((v) => Number(v.courses) >= 2);
    if (!version) return 'ข้ามเพราะไม่มีฉบับหลักสูตรที่มีรายวิชาพอให้สลับ';

    const st = await registrar(`/curriculum/versions/${version.id}`);
    const flat: any[] = [];
    const walk = (nodes: any[]) => {
      for (const n of nodes ?? []) {
        flat.push(...(n.courses ?? []));
        walk(n.children ?? []);
      }
    };
    walk(st.body?.categories ?? []);
    if (flat.length < 2) return 'ข้ามเพราะโครงสร้างมีรายวิชาไม่พอ';

    const one = await registrar(`/curriculum/courses/${flat[0].id}`, {
      method: 'PATCH', body: JSON.stringify({ suggestedYear: 2, suggestedTerm: 2 }),
    });
    expect(one.status < 400, `แก้ภาคตามแผนไม่ได้ ${one.status} ${JSON.stringify(one.body)}`);
    expect(Number(one.body.suggested_year) === 2 && Number(one.body.suggested_term) === 2,
      'ภาคตามแผนต้องเปลี่ยนจริง');

    // สลับลำดับสองตัวแรกแล้วอ่านกลับมาดู
    const ids = flat.map((c) => c.id);
    const swapped = [ids[1], ids[0], ...ids.slice(2)];
    const re = await registrar(`/curriculum/versions/${version.id}/courses/reorder`, {
      method: 'POST', body: JSON.stringify({ courseIds: swapped }),
    });
    expect(re.status < 400, `จัดลำดับไม่ได้ ${re.status} ${JSON.stringify(re.body)}`);
    expect(Number(re.body.reordered) === swapped.length,
      `ต้องจัดครบทุกตัว ได้ ${re.body.reordered}/${swapped.length}`);

    /*
     * รายวิชาของหลักสูตรฉบับอื่นต้องถูกปฏิเสธทั้งชุด ไม่ใช่ข้ามเงียบ ๆ
     * — ถ้าข้าม คนกดจะเห็นว่าสำเร็จแล้วลำดับไม่ตรงกับที่จัด โดยไม่รู้ว่าทำไม
     */
    const bogus = await registrar(`/curriculum/versions/${version.id}/courses/reorder`, {
      method: 'POST',
      body: JSON.stringify({ courseIds: [...swapped, '00000000-0000-0000-0000-000000000001'] }),
    });
    expect(bogus.status === 400, `รายวิชานอกฉบับต้องถูกปฏิเสธ ได้ ${bogus.status}`);
    return `ย้ายภาคได้ · จัดลำดับ ${swapped.length} รายวิชา · ตัวนอกฉบับถูกปฏิเสธ`;
  });

  await check('API-179 วิชาเทียบโอนขึ้นใบ รบ. พร้อมเครื่องหมาย (*n)', async () => {
    /*
     * ─── ทำไมข้อนี้ต้องพิมพ์ใบออกมาอ่าน ไม่ใช่ตรวจแค่ payload ───
     * ก่อน 0066 ทั้ง `prior_academic_record` และ `transfer_credits_total()`
     * ทำงานถูกต้องครบทุกอย่าง — สิ่งที่ขาดคือใบ รบ. ไม่เคย join ตารางนั้น
     * เข้ามาเลย เทสต์ที่ตรวจว่า "บันทึกได้" หรือ "นับหน่วยกิตถูก" จึงเขียว
     * สนิทมาตลอดโดยที่กระดาษขาดรายวิชาไปทั้งชุด
     *
     * และคำอธิบาย (*1)–(*5) ก็พิมพ์อยู่ท้ายใบมาตั้งแต่ต้นโดยไม่มีเครื่องหมาย
     * ไหนปรากฏจริงสักตัว — สองอย่างนี้เห็นได้ทางเดียวคืออ่านใบที่พิมพ์ออกมา
     */
    const added = await registrar('/prior-records', {
      method: 'POST',
      body: JSON.stringify({
        records: [{
          studentId: F.student,
          sourceTh: 'วิทยาลัยเดิม',
          courseCode: 'XFER-901',
          courseNameTh: 'วิชาที่เทียบโอนมาเพื่อทดสอบ',
          credits: 3,
          gradeSymbol: 'B',
          gradePoint: 3,
          termLabel: '1/2566',
          transferKind: 'transferred_grade',
        }],
      }),
    });
    expect(added.status < 400, `บันทึกวิชาเทียบโอนไม่ได้ ${added.status} ${JSON.stringify(added.body)}`);

    // เส้นทางนี้คืน **ออบเจ็กต์** `{records, summary}` ไม่ใช่อาร์เรย์
    // — รูปเดียวกับ `/staff` ที่เคยทำให้หน้าจอขาวทั้งหน้า
    const list = await registrar(`/prior-records/students/${F.student}`);
    const rec = ((list.body as any)?.records as any[])?.find((r) => r.course_code === 'XFER-901');
    expect(Boolean(rec), 'อ่านวิชาเทียบโอนที่เพิ่งบันทึกกลับมาไม่ได้');

    // ยังไม่อนุมัติต้องยังไม่ขึ้นใบ — แถวที่ยังไม่อนุมัติคือคำขอ ไม่ใช่หน่วยกิต
    const before = await registrar('/documents/issue', {
      method: 'POST', body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const htmlBefore = String((await registrar(`/documents/${before.body.id}/print`)).body);
    expect(!htmlBefore.includes('XFER-901') && !htmlBefore.includes('วิชาที่เทียบโอนมาเพื่อทดสอบ'),
      'วิชาที่ยังไม่อนุมัติต้องไม่ขึ้นใบ');

    /*
     * ─── คนกรอกกับคนอนุมัติต้องไม่ใช่คนเดียวกัน ───
     * งานทะเบียนบันทึกวิชาที่เทียบโอนมาได้ แต่อนุมัติไม่ได้ (403) —
     * การรับรองว่าหน่วยกิตจากที่อื่นใช้แทนหลักสูตรของเราได้เป็นเรื่องของ
     * ฝ่ายวิชาการ หลักเดียวกับที่งานทะเบียนสร้างสถานประกอบการได้แต่
     * อนุมัติไม่ได้ (API-148) — ยืนยันไว้ตรงนี้ด้วย ไม่ใช่แค่เลี่ยงไปใช้
     * บัญชีที่ผ่าน
     */
    const denied = await registrar('/prior-records/approve', {
      method: 'POST', body: JSON.stringify({ recordIds: [rec.id] }),
    });
    expect(denied.status === 403, `งานทะเบียนต้องอนุมัติเองไม่ได้ ได้ ${denied.status}`);

    const ok = await director('/prior-records/approve', {
      method: 'POST', body: JSON.stringify({ recordIds: [rec.id] }),
    });
    expect(ok.status < 400, `อนุมัติเทียบโอนไม่ได้ ${ok.status} ${JSON.stringify(ok.body)}`);

    const after = await registrar('/documents/issue', {
      method: 'POST', body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    const html = String((await registrar(`/documents/${after.body.id}/print`)).body);

    expect(html.includes('วิชาที่เทียบโอนมาเพื่อทดสอบ'),
      'อนุมัติแล้ววิชาเทียบโอนต้องขึ้นใบ');
    expect(html.includes('(*1)'),
      'วิชาที่โอนผลการเรียนมาต้องมีเครื่องหมาย (*1) ท้ายชื่อวิชา');

    /*
     * ใบเก่าที่ออกก่อนอนุมัติต้องพิมพ์ซ้ำได้เหมือนเดิมทุกประการ —
     * payload ตรึงแล้วแก้ไม่ได้ (หลักข้อ 5) การเพิ่มเครื่องหมายให้ใบเก่า
     * ย้อนหลังจะทำให้ใบที่คนถืออยู่ไม่ตรงกับที่ระบบพิมพ์ใหม่
     */
    const reprint = String((await registrar(`/documents/${before.body.id}/print`)).body);
    expect(!reprint.includes('วิชาที่เทียบโอนมาเพื่อทดสอบ'),
      'ใบที่ออกก่อนอนุมัติต้องพิมพ์ซ้ำได้เหมือนเดิม ไม่ใช่เปลี่ยนตามข้อมูลใหม่');

    return 'งานทะเบียนอนุมัติเองไม่ได้ · ยังไม่อนุมัติไม่ขึ้นใบ · อนุมัติแล้วขึ้นพร้อม (*1) · ใบเก่าพิมพ์ซ้ำได้เหมือนเดิม';
  });

  console.log('');
  console.log('══ ลงข้อมูลรายวิชาเข้าคลังและหลักสูตร (0065) ══');

  await check('API-176 สร้างรายวิชาในคลังได้ และคาบต่อสัปดาห์คำนวณให้เอง', async () => {
    /*
     * ─── ทำไมเส้นทางนี้เพิ่งมี ───
     * ก่อนหน้านี้ **ไม่มีทางสร้างรายวิชาในระบบเลยสักทาง** — ค้นทั้ง repo
     * แล้ว `insert into course` มีอยู่สองที่คือ `db/seed` กับ
     * `db/deploy/demo-data.sql` วิทยาลัยที่เปิดใหม่จึงลงหลักสูตรของตัวเอง
     * ไม่ได้เลย ทั้งที่หน้าจอโครงสร้างหลักสูตรเปิดดูได้ปกติ
     *
     * และ `weekly_periods` ต้องมาจาก ท+ป เสมอ ไม่ใช่ช่องให้กรอก — ถ้ากรอกเอง
     * มันเพี้ยนจาก ท-ป-น ได้ทันทีที่มีคนแก้ค่าเดียว แล้วตารางสอนกับหนังสือ
     * หลักสูตรจะบอกจำนวนคาบไม่ตรงกันโดยไม่มีอะไรฟ้อง (SISA เก็บสองค่านี้
     * แยกกันจริง ๆ และประกอบกลับเป็น ท-ป-น ไม่ได้)
     */
    const code = `T${Date.now().toString().slice(-7)}`;
    const made = await registrar('/curriculum/catalog', {
      method: 'POST',
      body: JSON.stringify({
        code, nameTh: 'รายวิชาทดสอบการลงข้อมูล', nameEn: 'Data Entry Test',
        editionBe: 2567, theoryHours: 1, practiceHours: 2, credits: 2,
      }),
    });
    expect(made.status < 400, `สร้างรายวิชาไม่ได้ ${made.status} ${JSON.stringify(made.body)}`);
    expect(Number(made.body.weekly_periods) === 3,
      `คาบต่อสัปดาห์ต้องเป็น 1+2=3 ได้ ${made.body.weekly_periods}`);

    // รหัสซ้ำในฉบับเดียวกันต้องถูกปฏิเสธพร้อมบอกว่าซ้ำกับฉบับไหน
    const dup = await registrar('/curriculum/catalog', {
      method: 'POST',
      body: JSON.stringify({
        code, nameTh: 'ซ้ำ', editionBe: 2567,
        theoryHours: 1, practiceHours: 0, credits: 1,
      }),
    });
    expect(dup.status === 400, `รหัสซ้ำต้องได้ 400 ได้ ${dup.status}`);

    const edited = await registrar(`/curriculum/catalog/${made.body.id}`, {
      method: 'PATCH', body: JSON.stringify({ theoryHours: 2, practiceHours: 0 }),
    });
    expect(Number(edited.body.weekly_periods) === 2,
      `แก้ ท-ป แล้วคาบต้องคิดใหม่เป็น 2 ได้ ${edited.body.weekly_periods}`);
    return `${code} · 1-2-2 → คาบ 3 · แก้เป็น 2-0 → คาบ 2 · รหัสซ้ำถูกปฏิเสธ`;
  });

  await check('API-177 ครูสร้างรายวิชาเองไม่ได้', async () => {
    // หน่วยกิตของรายวิชาคือตัวตั้งของการตรวจจบทั้งรุ่น
    const r = await teacher('/curriculum/catalog', {
      method: 'POST',
      body: JSON.stringify({
        code: 'TCH-001', nameTh: 'ครูสร้างเอง', editionBe: 2567,
        theoryHours: 1, practiceHours: 0, credits: 1,
      }),
    });
    expect(r.status === 403, `ครูต้องได้ 403 ได้ ${r.status}`);
    return 'ครูถูกปฏิเสธที่ชั้น API';
  });

  await check('API-178 วางทั้งตารางแล้วได้ผลรายบรรทัด ไม่ล้มทั้งก้อน', async () => {
    /*
     * ─── ทำไมต้องคืนผลรายบรรทัด ───
     * หลักสูตรฉบับหนึ่งมีร้อยกว่ารายวิชา ถ้ามีบรรทัดเดียวชนของเดิมแล้ว
     * `rollback` ทั้งชุด คนกรอกจะต้องไล่หาบรรทัดที่ผิดเองโดยไม่มีอะไรบอก
     * แล้ววางใหม่ทั้งก้อน (หลักเดียวกับ `register_courses_bulk`)
     *
     * ─── และรายวิชาที่มีอยู่แล้วแต่ ท-ป-น ไม่ตรง ต้องไม่ถูกเขียนทับ ───
     * หน่วยกิตของรายวิชาที่มีคนเรียนไปแล้วคือเกณฑ์จบย้อนหลังของคนกลุ่มนั้น
     * การวางตารางผิดฉบับแล้วเขียนทับเงียบ ๆ จะเปลี่ยนเกณฑ์จบของคนที่เรียน
     * ไปครึ่งทาง — รายงานว่าไม่ตรงแล้วให้คนตัดสินใจ
     */
    const versions = await registrar('/curriculum/versions');
    const version = (versions.body as any[])?.[0];
    if (!version) return 'ข้ามเพราะยังไม่มีฉบับหลักสูตร';

    const st = await registrar(`/curriculum/versions/${version.id}`);
    const category = (st.body?.categories ?? [])[0];
    if (!category) return 'ข้ามเพราะฉบับนี้ยังไม่มีหมวดวิชา';

    const stamp = Date.now().toString().slice(-6);
    const rows = [
      { code: `B${stamp}1`, nameTh: 'วิชาวางใหม่หนึ่ง', theoryHours: 2, practiceHours: 0, credits: 2 },
      { code: `B${stamp}2`, nameTh: 'วิชาวางใหม่สอง', theoryHours: 0, practiceHours: 2, credits: 1 },
    ];

    const first = await registrar(`/curriculum/versions/${version.id}/courses/bulk`, {
      method: 'POST',
      body: JSON.stringify({ curriculumCategoryId: category.id, rows }),
    });
    expect(first.status < 400, `วางตารางไม่ได้ ${first.status} ${JSON.stringify(first.body)}`);
    expect(first.body.created === 2, `ต้องสร้างใหม่ 2 ได้ ${first.body.created}`);

    // วางซ้ำก้อนเดิม — ต้องไม่สร้างซ้ำและไม่ผูกซ้ำ
    const again = await registrar(`/curriculum/versions/${version.id}/courses/bulk`, {
      method: 'POST',
      body: JSON.stringify({ curriculumCategoryId: category.id, rows }),
    });
    expect(again.body.created === 0 && again.body.already === 2,
      `วางซ้ำต้องได้ already 2 ได้ created=${again.body.created} already=${again.body.already}`);

    // ก้อนเดียวกันแต่หน่วยกิตต่างจากของเดิม — ต้องรายงาน ไม่ใช่เขียนทับ
    const changed = await registrar(`/curriculum/versions/${version.id}/courses/bulk`, {
      method: 'POST',
      body: JSON.stringify({
        curriculumCategoryId: category.id,
        rows: [{ ...rows[0], credits: 9 }],
      }),
    });
    expect(changed.body.mismatch === 1, `ต้องรายงานว่าไม่ตรง 1 ได้ ${changed.body.mismatch}`);

    const after = await registrar('/curriculum/courses?q=' + encodeURIComponent(rows[0].code));
    const still = (after.body as any[])?.find((c) => c.code === rows[0].code);
    expect(still && Number(still.credits) === 2,
      `หน่วยกิตเดิมต้องไม่ถูกเขียนทับ ได้ ${still?.credits}`);

    // หมวดวิชาของฉบับอื่นต้องถูกปฏิเสธ ไม่ใช่เพิ่มไปผิดที่เงียบ ๆ
    const wrong = await registrar(`/curriculum/versions/${version.id}/courses/bulk`, {
      method: 'POST',
      body: JSON.stringify({
        curriculumCategoryId: '00000000-0000-0000-0000-000000000001', rows,
      }),
    });
    expect(wrong.status === 400, `หมวดนอกฉบับต้องได้ 400 ได้ ${wrong.status}`);

    return `สร้าง 2 · วางซ้ำได้ already 2 · ท-ป-น ไม่ตรงรายงาน 1 โดยไม่เขียนทับ`;
  });

  console.log('');
  console.log('══ เลขประจำตัวประชาชนบนใบ รบ. (0061) ══');

  await check('API-167 เลขบัตรขึ้นใบ รบ. ได้ แต่ฐานข้อมูลไม่เคยมีเลขเปล่า', async () => {
    /*
     * ─── ตัวบล็อกที่หนักที่สุดของงานเอกสารทั้งหมด ───
     * ใบ รบ. ทุกรูปแบบพิมพ์เลขบัตรเต็มบนกระดาษ ระบบเก็บแค่ค่าแฮชมาตั้งแต่
     * 0002 แม่แบบทั้งสี่แบบจึงพิมพ์ช่องนั้นว่างทุกใบ — ใบที่ครบถ้วนทุก
     * ประการแต่ใช้ยื่นจริงไม่ได้เลย
     *
     * ข้อนี้พิสูจน์สามอย่างพร้อมกัน: เลขขึ้นกระดาษจริง · payload ที่ลบไม่ได้
     * ไม่เคยมีเลขเปล่า · และการพิมพ์ซ้ำได้เลขเดิม
     */
    const nid = '1104000247449';
    const set = await registrar(`/students/${F.student}/profile`, {
      method: 'PATCH',
      body: JSON.stringify({ nationalId: nid }),
    });
    expect(set.status < 400, `บันทึกเลขบัตรไม่สำเร็จ ${set.status} ${JSON.stringify(set.body)}`);

    const issued = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    expect(issued.status < 400, `ออกใบไม่ได้ ${issued.status}`);

    // payload ที่ตรึงลงฐานข้อมูลต้องไม่มีเลขเปล่าอยู่เลย
    const raw = JSON.stringify(issued.body.payload);
    expect(!raw.includes(nid), 'payload ต้องไม่มีเลขบัตรเป็นข้อความเปล่า — payload ลบไม่ได้');
    expect(typeof issued.body.payload.national_id_enc === 'string',
      'payload ต้องมีไบต์ที่เข้ารหัสไว้ มิฉะนั้นพิมพ์ซ้ำแล้วเลขหาย');

    // แต่กระดาษต้องมีเลขจริง ในรูปแบบที่ใบจริงพิมพ์
    const html = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    expect(html.includes('1 1040 00247 44 9'),
      'ใบที่พิมพ์ต้องมีเลขบัตรในรูปแบบ 1 1040 00247 44 9 ตามใบจริง');

    // พิมพ์ซ้ำต้องได้เลขเดิม (ไบต์ชุดเดิมเสมอ)
    const again = String((await registrar(`/documents/${issued.body.id}/print`)).body);
    expect(again.includes('1 1040 00247 44 9'), 'พิมพ์ซ้ำต้องได้เลขเดิม');
    return 'ขึ้นกระดาษ · ไม่อยู่ใน payload · พิมพ์ซ้ำได้เลขเดิม';
  });

  await check('API-168 อ่านเลขบัตรได้เฉพาะเส้นทางที่บันทึกว่าใครเปิดดู', async () => {
    /*
     * ระเบียนนักศึกษาถูกเปิดวันละหลายสิบครั้งเพื่อดูเรื่องอื่น ถ้าเลขบัตร
     * ติดไปด้วยทุกครั้ง access_log จะบอกไม่ได้เลยว่าใคร**ตั้งใจ**ดูเลขบัตร
     * ของใคร ซึ่งเป็นสิ่งเดียวที่หลักฐาน 90 วันตาม PDPA ม.37 ต้องตอบให้ได้
     */
    const profile = await registrar(`/students/${F.student}/profile`);
    expect(profile.status < 400, `อ่านระเบียนไม่ได้ ${profile.status}`);
    expect(!JSON.stringify(profile.body).includes('1104000247449'),
      'ระเบียนตามปกติต้องไม่มีเลขบัตรติดมาด้วย');

    const direct = await registrar(`/students/${F.student}/national-id`);
    expect(direct.status < 400, `อ่านเลขบัตรไม่ได้ ${direct.status}`);
    expect(direct.body.nationalId === '1104000247449', 'เส้นทางเฉพาะต้องคืนเลขจริง');
    expect(direct.body.formatted === '1 1040 00247 44 9', 'ต้องมีรูปแบบที่พิมพ์ลงกระดาษด้วย');

    // ครูดูไม่ได้ — ไม่ต้องใช้เลขนี้เพื่อดูแลนักศึกษา
    const asTeacher = await teacher(`/students/${F.student}/national-id`);
    expect(asTeacher.status === 403, `ครูควรได้ 403 ได้ ${asTeacher.status}`);
    return 'ไม่ติดมากับระเบียน · เส้นทางเฉพาะอ่านได้ · ครูอ่านไม่ได้';
  });

  await check('API-169 เลขบัตรที่หลักตรวจสอบผิดถูกปฏิเสธก่อนเข้ารหัส', async () => {
    /*
     * ต้องตรวจ**ก่อน**เข้ารหัส เพราะเลขที่ผิดเมื่อเข้ารหัสไปแล้วจะหาไม่เจอ
     * อีกเลยโดยไม่ถอดรหัสออกมาทั้งฐาน แล้วมันจะไปโผล่บนใบ รบ. ที่แก้ไม่ได้
     */
    const bad = await registrar(`/students/${F.student}/profile`, {
      method: 'PATCH',
      body: JSON.stringify({ nationalId: '1104000247448' }),
    });
    expect(bad.status === 400, `ควรได้ 400 ได้ ${bad.status}`);
    expect(JSON.stringify(bad.body).includes('หลักตรวจสอบ'),
      'ข้อความต้องบอกว่าเป็นเรื่องหลักตรวจสอบ ไม่ใช่ error ดิบ');

    // และค่าเดิมต้องไม่ถูกล้างทิ้งเพราะคำขอที่ถูกปฏิเสธ
    const still = await registrar(`/students/${F.student}/national-id`);
    expect(still.body.nationalId === '1104000247449', 'เลขเดิมต้องยังอยู่');
    return 'ปฏิเสธและไม่ล้างค่าเดิม';
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

  console.log('');
  console.log('══ ตารางสอบ (0075) ══');

  let examA = '';
  let examB = '';

  await check('API-198 ครูเปิดตารางสอบเองไม่ได้', async () => {
    const r = await teacher('/exam-schedule', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: F.sectionExamA, kind: 'final', examDate: '2026-09-15',
        periodFrom: 1, periodTo: 2, roomId: F.room,
      }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-199 งานทะเบียนเปิดตารางสอบได้', async () => {
    const r = await registrar('/exam-schedule', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: F.sectionExamA, kind: 'final', examDate: '2026-09-15',
        periodFrom: 1, periodTo: 2, roomId: F.room,
      }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    examA = r.body.id;
  });

  await check('API-200 ห้องสอบชนกันถูกปฏิเสธพร้อมบอกเหตุผล', async () => {
    const r = await registrar('/exam-schedule', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: F.sectionExamB, kind: 'final', examDate: '2026-09-15',
        periodFrom: 1, periodTo: 2, roomId: F.room,
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
    expect(Array.isArray(r.body.conflicts) && r.body.conflicts.some((m: string) => m.includes('ห้อง')),
      `ควรมีข้อความเรื่องห้องชนกัน ได้ ${JSON.stringify(r.body)}`);
  });

  await check('API-201 คนละห้องแต่มีนักศึกษาลงทั้งสองวิชาก็ยังถูกปฏิเสธ', async () => {
    const r = await registrar('/exam-schedule', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: F.sectionExamB, kind: 'final', examDate: '2026-09-15',
        periodFrom: 1, periodTo: 2, roomId: F.roomLecture,
      }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
    expect(Array.isArray(r.body.conflicts) && r.body.conflicts.some((m: string) => m.includes('ลงทะเบียน')),
      `ควรมีข้อความเรื่องนักศึกษาลงทั้งสองวิชา ได้ ${JSON.stringify(r.body)}`);
  });

  await check('API-202 ช่วงเวลาที่ว่างจริงเปิดตารางสอบได้', async () => {
    const r = await registrar('/exam-schedule', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: F.sectionExamB, kind: 'final', examDate: '2026-09-15',
        periodFrom: 6, periodTo: 7, roomId: F.roomLecture,
      }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    examB = r.body.id;
  });

  await check('API-203 มอบหมายกรรมการคุมสอบได้', async () => {
    const r = await registrar(`/exam-schedule/${examA}/proctors`, {
      method: 'POST',
      body: JSON.stringify({ staffId: F.staffExamB }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
  });

  await check('API-204 ครูเห็นตารางสอบของวิชาที่ตัวเองสอนและที่ตัวเองต้องคุม', async () => {
    const r = await teacherExamB(`/exam-schedule?termId=${TERM1}`);
    expect(r.status === 200, `อ่านไม่ได้ ${r.status}`);
    const ids = r.body.map((x: { id: string }) => x.id);
    expect(ids.includes(examA), 'ครู B ควรเห็นสอบ A เพราะต้องไปคุม');
    expect(ids.includes(examB), 'ครู B ควรเห็นสอบ B เพราะเป็นครูผู้สอน');
    return `เห็น ${ids.length} รายการ`;
  });

  await check('API-205 นักศึกษาที่ลงทั้งสองวิชาเห็นตารางสอบทั้งสองวิชา', async () => {
    const r = await examStudent(`/exam-schedule?termId=${TERM1}`);
    expect(r.status === 200, `อ่านไม่ได้ ${r.status}`);
    const ids = r.body.map((x: { id: string }) => x.id);
    expect(ids.includes(examA) && ids.includes(examB), `ควรเห็นทั้งสองวิชา ได้ ${JSON.stringify(ids)}`);
  });

  await check('API-206 ลบตารางสอบได้ และลบซ้ำได้ 404', async () => {
    const r = await registrar(`/exam-schedule/${examB}`, { method: 'DELETE' });
    expect(r.status === 200, `ลบไม่ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    const again = await registrar(`/exam-schedule/${examB}`, { method: 'DELETE' });
    expect(again.status === 404, `ลบซ้ำควรได้ 404 ได้ ${again.status}`);
  });

  await check('API-207 ครูแก้กำหนดสอบเองไม่ได้', async () => {
    const r = await teacher(`/exam-schedule/${examA}`, {
      method: 'POST',
      body: JSON.stringify({ periodFrom: 3, periodTo: 4 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-208 งานทะเบียนเลื่อนกำหนดสอบได้ โดยไม่ต้องส่งทุกช่อง', async () => {
    const r = await registrar(`/exam-schedule/${examA}`, {
      method: 'POST',
      body: JSON.stringify({ examDate: '2026-09-16' }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(String(r.body.exam_date).startsWith('2026-09-16'), `วันที่ควรเปลี่ยน ได้ ${JSON.stringify(r.body)}`);
    expect(Number(r.body.period_from) === 1 && Number(r.body.period_to) === 2,
      `ไม่ได้ส่งคาบมา คาบไม่ควรเปลี่ยน ได้ ${JSON.stringify(r.body)}`);
  });

  await check('API-209 เลื่อนกำหนดสอบไปชนห้องที่มีสอบอื่นอยู่แล้วถูกปฏิเสธ', async () => {
    const other = await registrar('/exam-schedule', {
      method: 'POST',
      body: JSON.stringify({
        classSectionId: F.sectionExamB, kind: 'midterm', examDate: '2026-09-20',
        periodFrom: 5, periodTo: 6, roomId: F.roomLecture,
      }),
    });
    expect(other.status === 201, `เตรียมข้อมูลไม่สำเร็จ: ${JSON.stringify(other.body)}`);

    const r = await registrar(`/exam-schedule/${examA}`, {
      method: 'POST',
      body: JSON.stringify({ examDate: '2026-09-20', periodFrom: 5, periodTo: 6, roomId: F.roomLecture }),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
    expect(Array.isArray(r.body.conflicts) && r.body.conflicts.some((m: string) => m.includes('ห้อง')),
      `ควรมีข้อความเรื่องห้องชนกัน ได้ ${JSON.stringify(r.body)}`);

    // ปฏิเสธแล้วต้องไม่แก้อะไรเลย — กำหนดเดิมจาก API-208 ต้องยังอยู่
    const list = await registrar(`/exam-schedule?termId=${TERM1}`);
    const still = list.body.find((x: { id: string }) => x.id === examA);
    expect(String(still.exam_date).startsWith('2026-09-16'), 'ถูกปฏิเสธแล้วกำหนดเดิมต้องไม่เปลี่ยน');
  });

  await check('API-210 ถอดห้องสอบออกได้ด้วยการส่ง roomId เป็น null ตรง ๆ', async () => {
    const r = await registrar(`/exam-schedule/${examA}`, {
      method: 'POST',
      body: JSON.stringify({ examDate: '2026-09-15', periodFrom: 1, periodTo: 2, roomId: null }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.room_id === null, `ส่ง roomId เป็น null ต้องถอดห้องออกได้จริง ได้ ${JSON.stringify(r.body)}`);
  });

  console.log('');
  console.log('══ ข้อจำกัดเวลาสอนของครู (0046) ══');

  let availabilityId = '';

  await check('API-211 งานทะเบียนเพิ่มข้อจำกัดเวลาสอนของครูได้', async () => {
    const r = await registrar('/timetable/availability', {
      method: 'POST',
      body: JSON.stringify({
        staffId: F.staffExamA, dayOfWeek: 2, periodFrom: 1, periodTo: 2,
        kind: 'unavailable', reason: 'สอนที่วิทยาเขตอื่น',
      }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.kind === 'unavailable', `ค่าที่ส่งไปควรถูกบันทึกตรงตัว ได้ ${JSON.stringify(r.body)}`);
    availabilityId = r.body.id;
  });

  await check('API-212 ครูกรอกข้อจำกัดเวลาสอนของตัวเองไม่ได้', async () => {
    // ตั้งใจกั้นไว้ที่งานทะเบียน/วิชาการ — ถ้าครูกรอกเองได้ ตารางสอนจะกลาย
    // เป็นเรื่องต่อรองกันเอง และคนที่กรอกก่อนได้คาบที่ดีที่สุดเสมอ
    const r = await teacher('/timetable/availability', {
      method: 'POST',
      body: JSON.stringify({
        staffId: F.staffExamA, dayOfWeek: 3, periodFrom: 1, periodTo: 2, kind: 'unavailable',
      }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-213 อ่านข้อจำกัดของครูคนหนึ่งได้ครบ', async () => {
    const r = await registrar(`/timetable/availability?staffId=${F.staffExamA}`);
    expect(r.status === 200, `ได้ ${r.status}`);
    expect(r.body.some((a: any) => a.id === availabilityId), 'ต้องเห็นรายการที่เพิ่งเพิ่ม');
  });

  await check('API-214 ลบข้อจำกัดได้ และลบซ้ำถูกปฏิเสธ', async () => {
    const r = await registrar(`/timetable/availability/${availabilityId}/remove`, { method: 'POST' });
    expect(r.status === 201, `ลบไม่ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    const again = await registrar(`/timetable/availability/${availabilityId}/remove`, { method: 'POST' });
    expect(again.status === 403, `ลบซ้ำควรถูกปฏิเสธ ได้ ${again.status}`);
  });

  console.log('');
  console.log('══ คัดลอกค่าเทอมข้ามปีการศึกษา (0031) ══');

  await check('API-215 คัดลอกค่าเทอมไปปีที่ยังไม่มีอยู่ถูกปฏิเสธ', async () => {
    const r = await registrar('/rollover/fee-schedules', {
      method: 'POST',
      body: JSON.stringify({ fromYearBe: 2569, toYearBe: 2599 }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
    expect(/ไม่พบปีการศึกษา/.test(JSON.stringify(r.body)),
      `ต้องบอกว่าไม่พบปีการศึกษาต้นทางหรือปลายทาง ไม่ใช่ error ดิบ ได้ ${JSON.stringify(r.body)}`);
  });

  await check('API-216 ครูคัดลอกค่าเทอมของทั้งวิทยาลัยไม่ได้', async () => {
    const r = await teacher('/rollover/fee-schedules', {
      method: 'POST',
      body: JSON.stringify({ fromYearBe: 2569, toYearBe: 2570 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-217 งานทะเบียนคัดลอกค่าเทอมไปปีใหม่ได้ แบบยังไม่เปิดใช้ และกดซ้ำได้โดยไม่ซ้อน', async () => {
    const newYear = await registrar('/academic/years', {
      method: 'POST',
      body: JSON.stringify({ yearBe: 2570, startsOn: '2570-05-01', endsOn: '2571-03-31' }),
    });
    expect(newYear.status === 201, `เตรียมปีการศึกษาใหม่ไม่สำเร็จ: ${JSON.stringify(newYear.body)}`);

    const r = await registrar('/rollover/fee-schedules', {
      method: 'POST',
      body: JSON.stringify({ fromYearBe: 2569, toYearBe: 2570 }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(typeof r.body.linesCopied === 'number', `ต้องคืนจำนวนรายการที่คัดลอก ได้ ${JSON.stringify(r.body)}`);
    expect(r.body.active === false,
      'ต้องเริ่มเป็นยังไม่เปิดใช้เสมอ — งานการเงินต้องตรวจตัวเลขก่อนเปิดเอง');

    // กดซ้ำต้องไม่คัดลอกซ้อน เหมือนสมุดคะแนน (API-58) — มิฉะนั้นค่าเทอมจะซ้อนกันทุกครั้งที่กด
    const again = await registrar('/rollover/fee-schedules', {
      method: 'POST',
      body: JSON.stringify({ fromYearBe: 2569, toYearBe: 2570 }),
    });
    expect(again.status === 201 && again.body.linesCopied === 0,
      `กดซ้ำต้องไม่คัดลอกเพิ่ม ได้ ${JSON.stringify(again.body)}`);
    return `คัดลอก ${r.body.linesCopied} รายการ · กดซ้ำได้ 0`;
  });

  console.log('');
  console.log('══ คำนวณสรุปผลภาคเรียน (0078) ══');

  await check('API-218 ครูคำนวณสรุปผลภาคเรียนเองไม่ได้', async () => {
    const r = await teacher(`/gradebook/terms/${TERM1}/summary`, { method: 'POST' });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-219 งานทะเบียนคำนวณสรุปผลภาคเรียนได้ พร้อมรายชื่อที่มีผลจริง', async () => {
    const r = await registrar(`/gradebook/terms/${TERM1}/summary`, { method: 'POST' });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(typeof r.body.students === 'number' && r.body.students > 0,
      `ควรคำนวณให้อย่างน้อยหนึ่งคน (มีผลการเรียนสะสมจากเทสต์ก่อนหน้า) ได้ ${JSON.stringify(r.body)}`);
    return `คำนวณให้ ${r.body.students} คน`;
  });

  console.log('');
  console.log('══ ยืนยัน/ข้ามรายการกระทบยอด (0079) ══');

  // เตรียมรายการทดสอบผ่าน SQL ตรง — 0079 แก้แค่ขั้นยืนยัน ไม่ใช่ตัวให้คะแนน
  // ซึ่ง API-16/17 คุมอยู่แล้ว จึงไม่ต้องประกอบเงื่อนไขคะแนนที่แม่นยำผ่าน API ซ้ำ
  let pendingBtSuggested = '';
  let pendingBtUnmatched = '';
  let pendingBtStudent = '';
  {
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    const inv = await db.query(
      `select id, student_id from invoice where institution_id = $1 and status in ('issued','partially_paid') limit 1`,
      [INST],
    );
    if (inv.rows.length === 0) {
      throw new Error('ต้องมีใบแจ้งหนี้ค้างอยู่อย่างน้อยหนึ่งใบให้ทดสอบ API-220 ถึง 223');
    }
    pendingBtStudent = inv.rows[0].student_id;

    const r1 = await db.query(
      `insert into bank_transaction
         (institution_id, posted_at, amount, counterparty, bank_ref, state, matched_invoice_id, confidence, match_reason)
       values ($1, now(), 999.00, 'ทดสอบ กระทบยอด หนึ่ง', 'E2E-BANK-1', 'suggested', $2, 60, 'ทดสอบ')
       returning id`,
      [INST, inv.rows[0].id],
    );
    pendingBtSuggested = r1.rows[0].id;

    const r2 = await db.query(
      `insert into bank_transaction (institution_id, posted_at, amount, counterparty, state)
       values ($1, now(), 111.00, 'ทดสอบ กระทบยอด สอง', 'unmatched')
       returning id`,
      [INST],
    );
    pendingBtUnmatched = r2.rows[0].id;
    await db.end();
  }

  await check('API-220 ครูยืนยันรายการกระทบยอดเองไม่ได้', async () => {
    const r = await teacher(`/finance/reconcile/${pendingBtSuggested}/confirm`, { method: 'POST' });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-221 การเงินยืนยันข้อเสนอเดิมได้ — ได้ใบเสร็จจริงเหมือนรับชำระปกติ', async () => {
    const r = await finance(`/finance/reconcile/${pendingBtSuggested}/confirm`, { method: 'POST' });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(!!r.body.paymentId, 'ต้องได้ paymentId กลับมา');
    expect(!!r.body.receipt?.doc_no,
      `ยืนยันแล้วต้องออกใบเสร็จให้ ไม่มีทางลัดข้ามได้ ได้ ${JSON.stringify(r.body)}`);

    const again = await finance(`/finance/reconcile/${pendingBtSuggested}/confirm`, { method: 'POST' });
    expect(again.status >= 400, `ยืนยันซ้ำควรถูกปฏิเสธ ได้ ${again.status}`);
    return `ใบเสร็จเลขที่ ${r.body.receipt.doc_no}`;
  });

  await check('API-222 รายการที่ไม่มีข้อเสนอ ต้องระบุนักศึกษาเองถึงยืนยันได้', async () => {
    const noStudent = await finance(`/finance/reconcile/${pendingBtUnmatched}/confirm`, { method: 'POST' });
    expect(noStudent.status >= 400, `ไม่ระบุนักศึกษาควรถูกปฏิเสธ ได้ ${noStudent.status}`);

    const r = await finance(`/finance/reconcile/${pendingBtUnmatched}/confirm`, {
      method: 'POST',
      body: JSON.stringify({ studentId: pendingBtStudent }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
  });

  await check('API-223 ยืนยันแล้วจำชื่อผู้โอนไว้ใช้จับคู่อัตโนมัติครั้งถัดไป', async () => {
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    const hint = await db.query(
      `select student_id, hit_count from reconciliation_hint
        where institution_id = $1 and counterparty = 'ทดสอบ กระทบยอด หนึ่ง'`,
      [INST],
    );
    await db.end();
    expect(hint.rows.length === 1, 'ควรมี hint บันทึกไว้หนึ่งแถว — ไม่เคยมีมาก่อน 0079');
    expect(hint.rows[0].student_id === pendingBtStudent, 'hint ต้องผูกกับนักศึกษาที่ยืนยันไป');
  });

  await check('API-224 ข้ามรายการที่ไม่ใช่ค่าเทอมได้ และข้ามซ้ำถูกปฏิเสธ', async () => {
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    const r3 = await db.query(
      `insert into bank_transaction (institution_id, posted_at, amount, state)
       values ($1, now(), 5.00, 'unmatched') returning id`,
      [INST],
    );
    await db.end();
    const btId = r3.rows[0].id;

    const r = await finance(`/finance/reconcile/${btId}/ignore`, { method: 'POST' });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);

    const again = await finance(`/finance/reconcile/${btId}/ignore`, { method: 'POST' });
    expect(again.status >= 400, `ข้ามซ้ำควรถูกปฏิเสธ ได้ ${again.status}`);
  });

  console.log('');
  console.log('══ มอบ/ถอนบทบาทพนักงาน (0022 — เพิ่งมีทางเรียกจริงจากหน้าจอ) ══');

  let grantedRoleId = '';

  await check('API-225 งานทะเบียนมอบบทบาทเองไม่ได้ — เฉพาะผู้ดูแลระบบและผู้อำนวยการ', async () => {
    const r = await registrar(`/staff/${F.staffExamA}/roles`, {
      method: 'POST',
      body: JSON.stringify({ role: 'student_affairs' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-226 ผู้ดูแลระบบมอบบทบาทได้ และเห็นในระเบียนของคนนั้นทันที', async () => {
    const r = await admin(`/staff/${F.staffExamA}/roles`, {
      method: 'POST',
      body: JSON.stringify({ role: 'student_affairs', reason: 'ทดสอบ API-226' }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    grantedRoleId = r.body.id;

    const detail = await admin(`/staff/${F.staffExamA}`);
    expect(detail.status === 200, `อ่านระเบียนไม่ได้ ${detail.status}`);
    const row = detail.body.roles.find((x: { id: string }) => x.id === grantedRoleId);
    expect(row && row.active_now === true, `บทบาทที่เพิ่งมอบต้องขึ้นว่าใช้งานอยู่ ได้ ${JSON.stringify(row)}`);
  });

  await check('API-227 มอบบทบาทเดียวกันซ้อนช่วงเวลาเดิมไม่ได้ — exclusion constraint กันไว้', async () => {
    const r = await admin(`/staff/${F.staffExamA}/roles`, {
      method: 'POST',
      body: JSON.stringify({ role: 'student_affairs' }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-228 ถอนบทบาทโดยไม่ระบุเหตุผลไม่ได้', async () => {
    const r = await director(`/staff/roles/${grantedRoleId}/revoke`, {
      method: 'PATCH',
      body: JSON.stringify({}),
    });
    expect(r.status === 400, `ควรได้ 400 ได้ ${r.status}`);
  });

  await check('API-229 ผู้อำนวยการถอนบทบาทได้ มีผลทันที', async () => {
    const r = await director(`/staff/roles/${grantedRoleId}/revoke`, {
      method: 'PATCH',
      body: JSON.stringify({ reason: 'ทดสอบ API-229' }),
    });
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(!!r.body.revoked_at, 'ต้องมีเวลาที่ถอน');

    const detail = await admin(`/staff/${F.staffExamA}`);
    const row = detail.body.roles.find((x: { id: string }) => x.id === grantedRoleId);
    expect(row && row.active_now === false, `ถอนแล้วต้องไม่ active_now อีก ได้ ${JSON.stringify(row)}`);
  });

  await check('API-230 ถอนซ้ำบทบาทที่ถอนไปแล้วถูกปฏิเสธ', async () => {
    const r = await director(`/staff/roles/${grantedRoleId}/revoke`, {
      method: 'PATCH',
      body: JSON.stringify({ reason: 'ลองถอนซ้ำ' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  console.log('══ โครงสร้างค่าเทอมและส่วนลดรายคน (0080 — ไม่เคยมีทางเรียกจริงตั้งแต่ 0010) ══');
  let feeItemId = '';
  let combinedScheduleId = '';
  let fundingSourceId = '';
  let grantedFundingId = '';

  await check('API-231 ครูสร้างรายการค่าธรรมเนียมเองไม่ได้', async () => {
    const r = await teacher('/finance/fee-items', {
      method: 'POST',
      body: JSON.stringify({ code: 'HACK', nameTh: 'ครูสร้างเอง', kind: 'other' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-232 การเงินสร้างรายการค่าธรรมเนียมได้', async () => {
    const r = await finance('/finance/fee-items', {
      method: 'POST',
      body: JSON.stringify({ code: 'TEST231', nameTh: 'ค่าทดสอบ API-231', kind: 'other' }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    feeItemId = r.body.id;
  });

  await check('API-233 กำหนดโครงสร้างค่าเทอมแบบ "รวม" ได้ — ไม่ระบุระดับ/ชั้นปี/สาขา', async () => {
    const r = await finance('/finance/fee-schedules', {
      method: 'POST',
      body: JSON.stringify({ academicYearId: AY, announcementNo: 'ทดสอบ API-233' }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.level == null && r.body.study_year == null && r.body.program_id == null,
      `ควรว่างทั้งสามช่อง ได้ ${JSON.stringify(r.body)}`);
    combinedScheduleId = r.body.id;

    const list = await finance(`/finance/fee-schedules?academicYearId=${AY}`);
    expect(list.status === 200, `ได้ ${list.status}`);
    expect(list.body.some((x: any) => x.id === combinedScheduleId), 'ควรเห็นโครงสร้างที่เพิ่งสร้างในรายการ');
  });

  await check('API-234 ตั้งค่ารายการในโครงสร้างค่าเทอมเป็นชุดได้ และแก้ราคาซ้ำไม่สร้างรายการซ้อน', async () => {
    const r = await finance(`/finance/fee-schedules/${combinedScheduleId}/lines`, {
      method: 'POST',
      body: JSON.stringify({ lines: [{ feeItemId, termOrdinal: 1, amount: 111.11 }] }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.length === 1, `ควรมี 1 รายการ ได้ ${r.body.length}`);
    expect(Number(r.body[0].amount) === 111.11, `ราคาควรเป็น 111.11 ได้ ${r.body[0].amount}`);

    const again = await finance(`/finance/fee-schedules/${combinedScheduleId}/lines`, {
      method: 'POST',
      body: JSON.stringify({ lines: [{ feeItemId, termOrdinal: 1, amount: 222.22 }] }),
    });
    expect(again.status === 201, `ควรได้ 201 ได้ ${again.status}`);
    expect(again.body.length === 1, `แก้ราคาซ้ำต้องไม่เพิ่มแถวใหม่ ได้ ${again.body.length} แถว`);
    expect(Number(again.body[0].amount) === 222.22, `ราคาควรอัปเดตเป็น 222.22 ได้ ${again.body[0].amount}`);
  });

  await check('API-235 ครูมอบส่วนลดให้นักศึกษาเองไม่ได้', async () => {
    const r = await teacher(`/finance/students/${F.student}/funding`, {
      method: 'POST',
      body: JSON.stringify({ fundingSourceId: '00000000-0000-0000-0000-000000000000', academicYearId: AY, percentOff: 100 }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-236 การเงินมอบส่วนลดเฉพาะรายการได้ และอนุมัติให้ทันทีในตัว', async () => {
    const src = await finance('/finance/funding-sources', {
      method: 'POST',
      body: JSON.stringify({ kind: 'other', nameTh: 'ส่วนลดทดสอบ API-236' }),
    });
    expect(src.status === 201, `ควรได้ 201 ได้ ${src.status}: ${JSON.stringify(src.body)}`);
    fundingSourceId = src.body.id;

    const r = await finance(`/finance/students/${F.student}/funding`, {
      method: 'POST',
      body: JSON.stringify({
        fundingSourceId, academicYearId: AY, feeItemId, percentOff: 50, note: 'ทดสอบ API-236',
      }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(!!r.body.approved_at, 'การกระทำนี้คือการอนุมัติในตัว — ต้องมี approved_at ทันทีโดยไม่ต้องมีขั้นแยก');
    grantedFundingId = r.body.id;

    const list = await finance(`/finance/students/${F.student}/funding`);
    expect(list.status === 200, `ได้ ${list.status}`);
    expect(list.body.some((x: any) => x.id === grantedFundingId), 'ควรเห็นส่วนลดที่เพิ่งมอบในระเบียนของนักศึกษาคนนั้น');
  });

  await check('API-237 ถอนส่วนลดได้ และถอนซ้ำได้ 404', async () => {
    const r = await finance(`/finance/students/${F.student}/funding/${grantedFundingId}`, { method: 'DELETE' });
    expect(r.status === 200, `ควรได้ 200 ได้ ${r.status}: ${JSON.stringify(r.body)}`);

    const list = await finance(`/finance/students/${F.student}/funding`);
    expect(!list.body.some((x: any) => x.id === grantedFundingId), 'ถอนแล้วต้องไม่เห็นในรายการอีก');

    const again = await finance(`/finance/students/${F.student}/funding/${grantedFundingId}`, { method: 'DELETE' });
    expect(again.status === 404, `ถอนซ้ำควรได้ 404 ได้ ${again.status}`);
  });

  console.log('');
  console.log('══ ผลงานและเกียรติประวัติของนักศึกษา (0090) ══');

  let achievementId = '';

  await check('API-238 ครูบันทึกผลงานนักศึกษาเองไม่ได้', async () => {
    const r = await teacher(`/students/${F.student}/achievements`, {
      method: 'POST',
      body: JSON.stringify({ titleTh: 'รางวัลทดสอบโดยครู' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-239 งานทะเบียนบันทึกผลงานได้ พร้อมระดับและผู้มอบ', async () => {
    const r = await registrar(`/students/${F.student}/achievements`, {
      method: 'POST',
      body: JSON.stringify({
        titleTh: 'รางวัลชนะเลิศแข่งขันหุ่นยนต์ API-239',
        categoryTh: 'วิชาการ',
        levelTh: 'ระดับจังหวัด',
        issuerTh: 'สอศ.',
        awardedOn: '2026-06-01',
      }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    achievementId = r.body.id;
  });

  await check('API-240 ครูอ่านผลงานของนักศึกษาที่สอนได้ แต่แก้ไข/ลบไม่ได้', async () => {
    const list = await teacher(`/students/${F.student}/achievements`);
    expect(list.status === 200, `ควรอ่านได้ ได้ ${list.status}`);
    expect(list.body.some((x: any) => x.id === achievementId), 'ควรเห็นรายการที่เพิ่งบันทึก');

    const upd = await teacher(`/achievements/${achievementId}`, {
      method: 'PATCH',
      body: JSON.stringify({ titleTh: 'แก้โดยครู' }),
    });
    expect(upd.status === 403, `แก้ไขควรได้ 403 ได้ ${upd.status}`);

    const del = await teacher(`/achievements/${achievementId}`, { method: 'DELETE' });
    expect(del.status === 403, `ลบควรได้ 403 ได้ ${del.status}`);
  });

  await check('API-241 งานทะเบียนแก้ไขและลบผลงานได้ ลบซ้ำได้ 404', async () => {
    const upd = await registrar(`/achievements/${achievementId}`, {
      method: 'PATCH',
      body: JSON.stringify({ levelTh: 'ระดับชาติ' }),
    });
    expect(upd.status === 200, `ควรได้ 200 ได้ ${upd.status}: ${JSON.stringify(upd.body)}`);
    expect(upd.body.level_th === 'ระดับชาติ', 'ระดับต้องอัปเดตเป็นค่าใหม่');

    const del = await registrar(`/achievements/${achievementId}`, { method: 'DELETE' });
    expect(del.status === 200, `ลบควรได้ 200 ได้ ${del.status}`);

    const again = await registrar(`/achievements/${achievementId}`, { method: 'DELETE' });
    expect(again.status === 404, `ลบซ้ำควรได้ 404 ได้ ${again.status}`);
  });

  console.log('');
  console.log('══ ประกาศ/ข่าวสารถึงนักศึกษา (0091) ══');

  let announcementId = '';

  await check('API-242 ครูสร้างประกาศเองไม่ได้', async () => {
    const r = await teacher('/announcements', {
      method: 'POST',
      body: JSON.stringify({ titleTh: 'ประกาศทดสอบโดยครู', bodyTh: 'เนื้อหา' }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-243 งานทะเบียนสร้างประกาศเป็นฉบับร่างได้ก่อน แล้วค่อยเผยแพร่', async () => {
    const created = await registrar('/announcements', {
      method: 'POST',
      body: JSON.stringify({ titleTh: 'ปิดภาคเรียน API-243', bodyTh: 'ประกาศปิดภาคเรียน', categoryTh: 'ทั่วไป' }),
    });
    expect(created.status === 201, `ควรได้ 201 ได้ ${created.status}: ${JSON.stringify(created.body)}`);
    expect(created.body.published_at === null, 'ไม่ส่ง publishNow ต้องเป็นฉบับร่าง (published_at เป็น null)');
    announcementId = created.body.id;

    const published = await registrar(`/announcements/${announcementId}/publish`, { method: 'POST' });
    expect(published.status === 201, `เผยแพร่ควรได้ 201 ได้ ${published.status}`);
    expect(!!published.body.published_at, 'เผยแพร่แล้วต้องมี published_at');
  });

  await check('API-244 เผยแพร่ทันทีตอนสร้างได้ด้วย publishNow', async () => {
    const r = await registrar('/announcements', {
      method: 'POST',
      body: JSON.stringify({ titleTh: 'ประกาศด่วน API-244', bodyTh: 'เนื้อหา', publishNow: true }),
    });
    expect(r.status === 201, `ควรได้ 201 ได้ ${r.status}`);
    expect(!!r.body.published_at, 'publishNow=true ต้องได้ published_at ทันที');
  });

  await check('API-245 ลบประกาศได้ และลบซ้ำได้ 404', async () => {
    const del = await registrar(`/announcements/${announcementId}`, { method: 'DELETE' });
    expect(del.status === 200, `ควรได้ 200 ได้ ${del.status}`);

    const again = await registrar(`/announcements/${announcementId}`, { method: 'DELETE' });
    expect(again.status === 404, `ลบซ้ำควรได้ 404 ได้ ${again.status}`);
  });

  console.log('');
  console.log('══ ค่าซ่อมรายวิชา (0093) ══');

  // F.section (TERM1) เปิดรับลงทะเบียนอยู่แล้ว (เทสต์อื่นลงทะเบียนสำเร็จ
  // มาก่อนหน้านี้) และ F.studentRegrade ยังไม่เคยลงทะเบียนกลุ่มนี้ — ต่างจาก
  // กลุ่ม 'c0' ที่ใช้เก็บผลสอบตกของนักศึกษาคนนี้ไปแล้ว จึงใช้ได้โดยไม่ต้อง
  // เปิดภาคเรียน/สร้างกลุ่มเรียนใหม่เอง
  const RETAKE_SECTION = F.section;
  let retakeChargeId = '';

  await check('API-246 ยังไม่ได้ตั้งอัตราค่าซ่อม — ลงทะเบียนซ่อมถูกปฏิเสธ', async () => {
    const r = await registrar('/retake-fee/register', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.studentRegrade, termId: TERM1, sectionId: RETAKE_SECTION }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
    expect(/อัตรา/.test(JSON.stringify(r.body)), `ข้อความควรบอกว่ายังไม่ได้ตั้งอัตรา ได้ ${JSON.stringify(r.body)}`);
  });

  await check('API-247 ครูตั้งอัตราค่าซ่อมเองไม่ได้ แต่การเงินตั้งได้', async () => {
    const denied = await teacher('/retake-fee/policy', {
      method: 'POST', body: JSON.stringify({ feePerCredit: 300 }),
    });
    expect(denied.status === 403, `ครูควรได้ 403 ได้ ${denied.status}`);

    const r = await finance('/retake-fee/policy', {
      method: 'POST', body: JSON.stringify({ feePerCredit: 300 }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Number(r.body.fee_per_credit) === 300, `อัตราควรเป็น 300 ได้ ${r.body.fee_per_credit}`);
  });

  await check('API-248 ลงทะเบียนซ่อมแล้วออกยอดอัตโนมัติ — 2 หน่วยกิต × 300 = 600 บาท สถานะรอชำระ', async () => {
    const r = await registrar('/retake-fee/register', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.studentRegrade, termId: TERM1, sectionId: RETAKE_SECTION }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(Number(r.body.charge.amount) === 600, `ยอดควรเป็น 600 ได้ ${r.body.charge.amount}`);
    expect(r.body.charge.status === 'pending', `สถานะควรเป็น pending ได้ ${r.body.charge.status}`);
    retakeChargeId = r.body.charge.id;
  });

  await check('API-249 ระหว่างรอชำระเงิน ชื่อนักศึกษาคนนี้ยังไม่ขึ้นสมุดคะแนนของครู แต่คนอื่นในห้องเดียวกันเห็นตามปกติ', async () => {
    const r = await teacher(`/gradebook/sections/${RETAKE_SECTION}/scores`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(
      !r.body.students.some((s: any) => s.student_code === '69201010779'),
      `นักศึกษาที่ยังไม่ชำระค่าซ่อมไม่ควรขึ้นสมุดคะแนน ได้ ${JSON.stringify(r.body.students)}`,
    );
    expect(
      r.body.students.length > 0,
      'นักศึกษาคนอื่นในห้องเดียวกัน (ที่ไม่มีค่าซ่อมค้าง) ยังต้องขึ้นสมุดคะแนนตามปกติ',
    );
  });

  await check('API-250 ครูยืนยันการชำระเองไม่ได้ แต่การเงินยืนยันได้ แล้วชื่อขึ้นสมุดคะแนนทันที', async () => {
    const denied = await teacher(`/retake-fee/${retakeChargeId}/confirm-payment`, {
      method: 'POST', body: JSON.stringify({ method: 'cash' }),
    });
    expect(denied.status === 403, `ครูควรได้ 403 ได้ ${denied.status}`);

    const r = await finance(`/retake-fee/${retakeChargeId}/confirm-payment`, {
      method: 'POST', body: JSON.stringify({ method: 'cash' }),
    });
    expect(r.status === 201, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.status === 'paid', `สถานะควรเป็น paid ได้ ${r.body.status}`);

    const roster = await teacher(`/gradebook/sections/${RETAKE_SECTION}/scores`);
    expect(
      roster.body.students.some((s: any) => s.student_code === '69201010779'),
      `ชำระแล้วต้องขึ้นสมุดคะแนนทันที ได้ ${JSON.stringify(roster.body.students)}`,
    );
  });

  await check('API-251 ยืนยันซ้ำรายการที่จ่ายแล้วถูกปฏิเสธ', async () => {
    const r = await finance(`/retake-fee/${retakeChargeId}/confirm-payment`, {
      method: 'POST', body: JSON.stringify({ method: 'cash' }),
    });
    expect(r.status >= 400, `ควรถูกปฏิเสธ ได้ ${r.status}`);
  });

  await check('API-252 ยอดค่าซ่อมไม่ปนกับยอดใบแจ้งหนี้ค่าเทอมของนักศึกษาคนเดียวกัน', async () => {
    // ออกใบแจ้งหนี้ค่าเทอมให้นักศึกษาคนเดียวกันในภาคเดียวกัน แล้วตรวจว่า
    // ยอดค้างชำระค่าเทอมไม่ขยับเพราะค่าซ่อม (คนละบัญชี คนละตารางกันจริง)
    const before = await registrar(`/students/${F.studentRegrade}/balance`);
    const inv = await registrar('/finance/invoices', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.studentRegrade, termId: TERM2, installments: 1 }),
    });
    const after = await registrar(`/students/${F.studentRegrade}/balance`);
    expect(inv.status === 201, `ออกใบแจ้งหนี้ควรได้ 201 ได้ ${inv.status}: ${JSON.stringify(inv.body)}`);
    expect(
      Number(after.body.billed) - Number(before.body.billed) !== 600,
      `ยอดเรียกเก็บค่าเทอมต้องไม่รวมค่าซ่อม 600 เข้าไปด้วย ก่อน ${before.body.billed} หลัง ${after.body.billed}`,
    );

    const charges = await registrar(`/retake-fee/students/${F.studentRegrade}`);
    expect(charges.status === 200, `ได้ ${charges.status}`);
    expect(
      charges.body.some((c: any) => c.id === retakeChargeId && c.status === 'paid'),
      'ต้องยังเห็นรายการค่าซ่อมที่จ่ายแล้วอยู่ในบัญชีของตัวเอง แยกจากใบแจ้งหนี้ค่าเทอม',
    );
  });

  console.log('');
  console.log('══ บล็อกใบ รบ. เมื่อมียอดค้าง + รายงานรายรับ (0094) ══');

  await check('API-253 เปิดบล็อกใบ รบ. เป็นทางเลือกที่ปิดโดยค่าเริ่มต้น', async () => {
    const r = await finance('/finance/late-policy');
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    // ฐานทดสอบตั้งนโยบายไว้แล้วตั้งแต่ prepare-db (TEST 13/28) — ตรวจแค่ว่า
    // คอลัมน์ใหม่มีอยู่จริงและอ่านได้ ไม่ตรวจค่าเริ่มต้นเพราะ fixture อาจตั้งไว้แล้ว
    expect('blocks_transcript_after_hold' in r.body, 'ต้องมีคอลัมน์นี้ในนโยบาย');
  });

  await check('API-254 ครูตั้งนโยบายค้างชำระเองไม่ได้', async () => {
    const r = await teacher('/finance/late-policy', {
      method: 'POST',
      body: JSON.stringify({ effectiveFromYearBe: 2569, blocksTranscriptAfterHold: true }),
    });
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  await check('API-255 การเงินเปิดบล็อกใบ รบ. แล้วมีการระงับที่บล็อกจริงถึงพิมพ์ไม่ได้', async () => {
    const set = await finance('/finance/late-policy', {
      method: 'POST',
      body: JSON.stringify({ effectiveFromYearBe: 2569, blocksTranscriptAfterHold: true }),
    });
    expect(set.status === 201, `ตั้งนโยบายไม่สำเร็จ ${set.status}: ${JSON.stringify(set.body)}`);
    expect(set.body.blocks_transcript_after_hold === true, 'นโยบายต้องเปิดแล้ว');

    // ก่อนมีการระงับ — พิมพ์ได้ตามปกติ แม้เปิดนโยบายไว้แล้วก็ตาม
    const before = await registrar('/documents/issue', {
      method: 'POST',
      body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
    });
    expect(before.status === 201, `เปิดนโยบายเฉย ๆ ไม่ควรบล็อกคนที่ไม่มีการระงับ ได้ ${before.status}`);

    // จำลองการระงับสิทธิ์ที่ตั้งใจให้บล็อกใบ รบ. ด้วย (เหมือนที่
    // refresh_finance_holds() จะตั้งให้เองเมื่อค้างชำระเกินกำหนดจริง)
    const db = new Client({ connectionString: process.env.ADMIN_DATABASE_URL });
    await db.connect();
    let holdId = '';
    try {
      const ins = await db.query(
        `insert into registration_hold
           (student_id, kind, reason, source_module, blocks_registration, blocks_transcript)
         values ($1, 'finance', 'ทดสอบ API-255', 'finance', false, true)
         returning id`,
        [F.student],
      );
      holdId = ins.rows[0].id;

      const blocked = await registrar('/documents/issue', {
        method: 'POST',
        body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
      });
      expect(blocked.status >= 400, `ควรถูกปฏิเสธ ได้ ${blocked.status}`);
      expect(/ระงับสิทธิ์/.test(JSON.stringify(blocked.body)), `ข้อความต้องบอกเหตุผล ได้ ${JSON.stringify(blocked.body)}`);

      // ใบเอกสารประเภทอื่นต้องไม่ถูกบล็อกด้วย — ตั้งใจบล็อกเฉพาะใบ รบ.
      const cert = await registrar('/documents/issue', {
        method: 'POST',
        body: JSON.stringify({ studentId: F.student, kind: 'certification' }),
      });
      expect(cert.status === 201, `ใบรับรองไม่ควรถูกบล็อกด้วย ได้ ${cert.status}: ${JSON.stringify(cert.body)}`);

      // ปลดการระงับแล้วพิมพ์ได้ตามปกติ
      await db.query(`update registration_hold set released_at = now() where id = $1`, [holdId]);
      const after = await registrar('/documents/issue', {
        method: 'POST',
        body: JSON.stringify({ studentId: F.student, kind: 'transcript' }),
      });
      expect(after.status === 201, `ปลดแล้วควรพิมพ์ได้ ได้ ${after.status}: ${JSON.stringify(after.body)}`);
    } finally {
      await db.end();
    }
  });

  await check('API-256 รายงานรายรับรวมยอดที่กระทบยอดแล้วเท่านั้น', async () => {
    const r = await finance(`/finance/revenue?from=2000-01-01&to=2999-12-31`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(typeof r.body.total === 'number', 'ต้องมียอดรวม');
    expect(Array.isArray(r.body.byMethod), 'ต้องแยกตามช่องทางชำระ');
    // API-15 รับชำระ 4,200 ผ่าน promptpay ไว้แล้วก่อนหน้านี้ในชุดทดสอบนี้
    const pp = r.body.byMethod.find((x: any) => x.method === 'promptpay');
    expect(pp && pp.amount >= 4200, `ต้องเห็นยอด promptpay ที่รับไปแล้ว ได้ ${JSON.stringify(r.body.byMethod)}`);
    return `รวม ${r.body.total} บาท ใน ${r.body.byMethod.length} ช่องทาง`;
  });

  await check('API-257 บทบาทอื่นที่ไม่ใช่งานการเงินขึ้นไปดูรายงานรายรับไม่ได้', async () => {
    const r = await teacher('/finance/revenue');
    expect(r.status === 403, `ควรได้ 403 ได้ ${r.status}`);
  });

  // ─── รายงานการเงินแบบ SISA — ค้นใบเสร็จ · ปิดยอดผู้รับเงิน · รายห้อง · ทุน ───

  await check('API-258 ค้นใบเสร็จทั้งวิทยาลัยได้ และกรองด้วยช่องทางชำระได้จริง', async () => {
    const all = await finance('/finance/receipts/search');
    expect(all.status === 200, `ได้ ${all.status}: ${JSON.stringify(all.body)}`);
    expect(all.body.length > 0, 'ชุดทดสอบรับชำระไปแล้ว ต้องมีใบเสร็จอย่างน้อยหนึ่งใบ');
    const pp = await finance('/finance/receipts/search?method=promptpay');
    expect(pp.body.every((r: any) => r.method === 'promptpay'), 'ตัวกรองช่องทางต้องมีผลจริง');
    const none = await finance('/finance/receipts/search?from=2999-01-01');
    expect(none.body.length === 0, 'ช่วงวันที่ในอนาคตต้องไม่มีใบเสร็จ');
    return `${all.body.length} ใบ · promptpay ${pp.body.length} ใบ`;
  });

  await check('API-259 ปิดยอดตามผู้รับเงินรวมได้เท่ากับยอดใบเสร็จที่ไม่ถูกยกเลิก', async () => {
    const sum = await finance('/finance/reports/cashier');
    expect(sum.status === 200, `ได้ ${sum.status}: ${JSON.stringify(sum.body)}`);
    const receipts = await finance('/finance/receipts/search?status=active');
    const a = sum.body.reduce((t: number, r: any) => t + r.amount, 0);
    const b = receipts.body.reduce((t: number, r: any) => t + Number(r.amount), 0);
    // ใช้ได้เพราะชุดทดสอบมีใบเสร็จไม่ถึงเพดาน 500 ใบของการค้น
    expect(Math.abs(a - b) < 0.01, `ยอดปิดผู้รับเงิน ${a} ต้องเท่ากับผลรวมใบเสร็จ ${b}`);
    return `รวม ${a} บาท`;
  });

  await check('API-260 สรุปรายห้องรวมกันได้เท่ากับยอดทั้งวิทยาลัย (รวมกองที่ยังไม่จัดห้อง)', async () => {
    const r = await finance(`/finance/reports/rooms?academicYearId=${AY}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.length > 0, 'ชุดทดสอบออกใบแจ้งหนี้ไปแล้ว ต้องมีอย่างน้อยหนึ่งแถว');
    for (const row of r.body) {
      expect(Math.abs(row.billed - row.paid - row.outstanding) < 0.01, `ห้อง ${row.groupCode}: เรียกเก็บ − ชำระ ต้องเท่ากับค้าง`);
    }
    const owingRoom = r.body.find((x: any) => x.owing > 0);
    if (owingRoom) {
      const q = owingRoom.groupCode ? `&groupCode=${encodeURIComponent(owingRoom.groupCode)}` : '';
      const list = await finance(`/finance/reports/rooms/arrears?academicYearId=${AY}${q}`);
      expect(list.status === 200, `ได้ ${list.status}`);
      expect(list.body.length === owingRoom.owing, `รายชื่อค้าง ${list.body.length} คน ต้องเท่ากับจำนวนในสรุป ${owingRoom.owing}`);
    }
    return `${r.body.length} ห้อง`;
  });

  // มอบเองในข้อนี้ — ส่วนลดของ API-236 ถูก API-237 ถอนไปแล้ว
  await check('API-261 รายงานทุนเห็นส่วนลดที่เพิ่งมอบ และไม่เห็นที่ถอนไปแล้ว', async () => {
    const src = await finance('/finance/funding-sources', {
      method: 'POST',
      body: JSON.stringify({ kind: 'other', nameTh: 'ทุนทดสอบ API-261' }),
    });
    expect(src.status === 201, `สร้างแหล่งทุนได้ ${src.status}: ${JSON.stringify(src.body)}`);
    const grant = await finance(`/finance/students/${F.student}/funding`, {
      method: 'POST',
      body: JSON.stringify({ fundingSourceId: src.body.id, academicYearId: AY, amount: 500 }),
    });
    expect(grant.status === 201, `มอบทุนได้ ${grant.status}: ${JSON.stringify(grant.body)}`);
    const r = await finance(`/finance/reports/funding?academicYearId=${AY}`);
    expect(r.status === 200, `ได้ ${r.status}: ${JSON.stringify(r.body)}`);
    expect(r.body.some((x: any) => x.source_name === 'ทุนทดสอบ API-261'), 'ต้องเห็นทุนที่เพิ่งมอบ');
    expect(!r.body.some((x: any) => x.source_name === 'ส่วนลดทดสอบ API-236'), 'ส่วนลดที่ถอนแล้วต้องไม่อยู่ในรายงาน');
    return `${r.body.length} รายการ`;
  });

  await check('API-262 ครูค้นใบเสร็จและดูปิดยอดผู้รับเงินไม่ได้', async () => {
    expect((await teacher('/finance/receipts/search')).status === 403, 'ค้นใบเสร็จต้องได้ 403');
    expect((await teacher('/finance/reports/cashier')).status === 403, 'ปิดยอดต้องได้ 403');
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

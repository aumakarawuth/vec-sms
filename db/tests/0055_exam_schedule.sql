-- ═══════════════════════════════════════════════════════════════════
-- 0055_exam_schedule.sql — ทดสอบตารางสอบ (0075)
--
-- ครอบคลุมสามเรื่องที่เสี่ยงที่สุดของไฟล์นี้: เลขคณิตของ exam_conflicts()
-- (ห้อง/กรรมการ/นักศึกษาชนกัน), exclusion constraint เป็นตัวกันจริงไม่ใช่
-- แค่คำแนะนำ, และฟังก์ชัน current_actor_is_exam_proctor() ตัดวงจร RLS
-- ระหว่าง exam_session ↔ exam_proctor ได้จริงโดยไม่ recursion
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare
  v_inst uuid := '11111111-1111-1111-1111-111111111111';
  v_ay uuid; v_term uuid;
  v_teacher_a_person uuid; v_teacher_b_person uuid;
  v_student1_person uuid; v_student2_person uuid;
begin
  insert into academic_year (institution_id, year_be, starts_on, ends_on)
  values (v_inst, 2598, '2598-05-01', '2599-03-31')
  returning id into v_ay;
  insert into term (id, academic_year_id, ordinal, starts_on, ends_on)
  values ('99999999-0000-0000-0000-000000000e01', v_ay, 1, '2598-05-11', '2598-09-30')
  returning id into v_term;

  insert into person (id, institution_id, first_name_th, last_name_th, gender)
  values
    ('99999999-0000-0000-0000-000000000e11', v_inst, 'ครู', 'สอบเอ', 'undisclosed'),
    ('99999999-0000-0000-0000-000000000e12', v_inst, 'ครู', 'สอบบี', 'undisclosed'),
    ('99999999-0000-0000-0000-000000000e13', v_inst, 'นักศึกษา', 'สอบหนึ่ง', 'undisclosed'),
    ('99999999-0000-0000-0000-000000000e14', v_inst, 'นักศึกษา', 'สอบสอง', 'undisclosed');

  insert into staff (id, institution_id, person_id, staff_code, is_teacher)
  values
    ('99999999-0000-0000-0000-000000000e21', v_inst, '99999999-0000-0000-0000-000000000e11', 'T-EXAM-A', true),
    ('99999999-0000-0000-0000-000000000e22', v_inst, '99999999-0000-0000-0000-000000000e12', 'T-EXAM-B', true);

  insert into student (id, institution_id, person_id, student_code, admitted_year_be, status)
  values
    ('99999999-0000-0000-0000-000000000e31', v_inst, '99999999-0000-0000-0000-000000000e13', '69EXAM001', 2569, 'active'),
    ('99999999-0000-0000-0000-000000000e32', v_inst, '99999999-0000-0000-0000-000000000e14', '69EXAM002', 2569, 'active');

  insert into room (id, institution_id, code, name_th, kind)
  values ('99999999-0000-0000-0000-000000000e41', v_inst, 'EXAM-R1', 'ห้องสอบทดสอบ 1', 'classroom');

  -- ใช้รายวิชาที่มีอยู่แล้ว (99999999-...0001/0002) เพื่อไม่ต้องสร้างรายวิชาใหม่
  insert into class_section
    (id, institution_id, term_id, course_id, section_no, teacher_id, attendance_policy_id, planned_periods)
  values
    ('99999999-0000-0000-0000-000000000e51', v_inst, v_term,
     '99999999-0000-0000-0000-000000000001', 'EXAM-A',
     '99999999-0000-0000-0000-000000000e21', '55555555-5555-5555-5555-555555555555', 2),
    ('99999999-0000-0000-0000-000000000e52', v_inst, v_term,
     '99999999-0000-0000-0000-000000000002', 'EXAM-B',
     '99999999-0000-0000-0000-000000000e22', '55555555-5555-5555-5555-555555555555', 2);

  -- นักศึกษาสอบหนึ่งลงทั้งสองวิชา (ใช้ทดสอบการชนแบบ enrolled)
  -- นักศึกษาสอบสองลงแค่วิชา A (ใช้ทดสอบว่าอ่านของวิชา B ไม่ได้)
  insert into enrollment (term_id, student_id, class_section_id)
  values
    (v_term, '99999999-0000-0000-0000-000000000e31', '99999999-0000-0000-0000-000000000e51'),
    (v_term, '99999999-0000-0000-0000-000000000e31', '99999999-0000-0000-0000-000000000e52'),
    (v_term, '99999999-0000-0000-0000-000000000e32', '99999999-0000-0000-0000-000000000e51');

  raise notice 'เตรียมฐาน — กลุ่มเรียน EXAM-A (ครู A) และ EXAM-B (ครู B) · นักศึกษาสอบหนึ่งลงทั้งคู่ · นักศึกษาสอบสองลงแค่ A';
end $$;

-- ── TEST 323–325 ───────────────────────────────────────────────────
-- exam_conflicts() จับครบสามแบบก่อนมีการสอบจริงสักครั้งในระบบ
do $$
declare v_n integer;
begin
  -- ตั้งสอบ A ไว้ก่อน วันเดียวกัน คาบ 1-3 ห้อง EXAM-R1 กรรมการคือครู B
  insert into exam_session (id, institution_id, class_section_id, kind, exam_date, period_from, period_to, room_id)
  values ('99999999-0000-0000-0000-000000000e61', '11111111-1111-1111-1111-111111111111',
          '99999999-0000-0000-0000-000000000e51', 'final', '2598-09-15', 1, 3,
          '99999999-0000-0000-0000-000000000e41');
  insert into exam_proctor (exam_session_id, staff_id)
  values ('99999999-0000-0000-0000-000000000e61', '99999999-0000-0000-0000-000000000e22');

  -- TEST 323 — ห้องเดียวกัน วันเดียวกัน คาบทับกัน
  select count(*) into v_n from exam_conflicts(
    '99999999-0000-0000-0000-000000000e52'::uuid, '2598-09-15'::date, 2::smallint, 4::smallint,
    '99999999-0000-0000-0000-000000000e41'::uuid, null::uuid[]);
  if v_n = 0 then
    raise exception 'TEST 323 ล้มเหลว: ห้องชนกันแต่ exam_conflicts() ไม่รายงาน';
  end if;

  -- TEST 324 — คนละห้อง แต่กรรมการคุมสอบคนเดียวกัน (ครู B) คาบทับกัน
  select count(*) into v_n from exam_conflicts(
    '99999999-0000-0000-0000-000000000e52'::uuid, '2598-09-15'::date, 2::smallint, 4::smallint,
    null::uuid, array['99999999-0000-0000-0000-000000000e22'::uuid]);
  if v_n = 0 then
    raise exception 'TEST 324 ล้มเหลว: กรรมการคุมสอบชนกันแต่ exam_conflicts() ไม่รายงาน';
  end if;

  -- TEST 325 — คนละห้อง คนละกรรมการ แต่นักศึกษาสอบหนึ่งลงทั้งสองวิชา
  select count(*) into v_n from exam_conflicts(
    '99999999-0000-0000-0000-000000000e52'::uuid, '2598-09-15'::date, 2::smallint, 4::smallint,
    null::uuid, null::uuid[]);
  if v_n = 0 then
    raise exception 'TEST 325 ล้มเหลว: นักศึกษาชนกันแต่ exam_conflicts() ไม่รายงาน';
  end if;

  raise notice 'TEST 323 ผ่าน — ห้องสอบชนกันถูกจับ';
  raise notice 'TEST 324 ผ่าน — กรรมการคุมสอบชนกันถูกจับ';
  raise notice 'TEST 325 ผ่าน — นักศึกษาที่ลงทั้งสองวิชาชนกันถูกจับ';
end $$;

-- ── TEST 326 ───────────────────────────────────────────────────────
-- ช่วงเวลาที่ไม่ชนอะไรเลยต้องผ่าน insert ได้จริง (ไม่ใช่แค่ exam_conflicts() ว่าง)
do $$
declare v_n integer;
begin
  select count(*) into v_n from exam_conflicts(
    '99999999-0000-0000-0000-000000000e52'::uuid, '2598-09-15'::date, 6::smallint, 8::smallint,
    '99999999-0000-0000-0000-000000000e41'::uuid, array['99999999-0000-0000-0000-000000000e21'::uuid]);
  if v_n <> 0 then
    raise exception 'TEST 326 ล้มเหลว: ช่วงที่ไม่ชนอะไรเลยกลับรายงานปัญหา % ข้อ', v_n;
  end if;

  insert into exam_session (id, institution_id, class_section_id, kind, exam_date, period_from, period_to, room_id)
  values ('99999999-0000-0000-0000-000000000e62', '11111111-1111-1111-1111-111111111111',
          '99999999-0000-0000-0000-000000000e52', 'final', '2598-09-15', 6, 8,
          '99999999-0000-0000-0000-000000000e41');
  insert into exam_proctor (exam_session_id, staff_id)
  values ('99999999-0000-0000-0000-000000000e62', '99999999-0000-0000-0000-000000000e21');

  raise notice 'TEST 326 ผ่าน — ช่วงเวลาที่ว่างจริงบันทึกสอบ B ได้';
end $$;

-- ── TEST 327 ───────────────────────────────────────────────────────
-- exclusion constraint กันห้องชนกันจริงที่ชั้นฐานข้อมูล ไม่ใช่แค่คำแนะนำจากฟังก์ชัน
-- (ยิง insert ตรง ๆ ข้าม exam_conflicts() ไปเลย เพื่อพิสูจน์ว่ามีคนลืมเรียกฟังก์ชัน
-- ก็ยังชนไม่ได้)
do $$
begin
  begin
    insert into exam_session (institution_id, class_section_id, kind, exam_date, period_from, period_to, room_id)
    values ('11111111-1111-1111-1111-111111111111', '99999999-0000-0000-0000-000000000e52',
            'midterm', '2598-09-15', 2, 4, '99999999-0000-0000-0000-000000000e41');
    raise exception 'TEST 327 ล้มเหลว: จองห้องซ้อนคาบเดิมสำเร็จทั้งที่ควรถูก exclusion constraint กัน';
  exception
    when exclusion_violation then
      raise notice 'TEST 327 ผ่าน — exclusion constraint กันห้องสอบชนกันที่ชั้นฐานข้อมูล';
  end;
end $$;

-- ═══ นักศึกษาอ่านสอบของตัวเองได้ อ่านของวิชาที่ไม่ได้ลงไม่ได้ เขียนไม่ได้เลย ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.actor_id',       '99999999-0000-0000-0000-000000000e14', true) as b,
       set_config('app.role',           'student', true) as c \gset ctx_

do $$
declare v_n integer;
begin
  -- ── TEST 328 ──
  select count(*) into v_n from exam_session
   where class_section_id in ('99999999-0000-0000-0000-000000000e51', '99999999-0000-0000-0000-000000000e52');
  if v_n <> 1 then
    raise exception 'TEST 328 ล้มเหลว: นักศึกษาสอบสองควรเห็นสอบแค่วิชา A (1 แถว) แต่เห็น % แถว', v_n;
  end if;

  -- ── TEST 329 ──
  begin
    insert into exam_session (institution_id, class_section_id, kind, exam_date, period_from, period_to)
    values ('11111111-1111-1111-1111-111111111111', '99999999-0000-0000-0000-000000000e51',
            'midterm', '2598-08-01', 1, 2);
    raise exception 'TEST 329 ล้มเหลว: นักศึกษาสร้างตารางสอบเองได้';
  exception
    when insufficient_privilege then null;
  end;

  raise notice 'TEST 328 ผ่าน — นักศึกษาเห็นเฉพาะสอบของวิชาที่ตัวเองลงทะเบียน (% แถว)', v_n;
  raise notice 'TEST 329 ผ่าน — นักศึกษาสร้างตารางสอบเองไม่ได้';
end $$;
rollback;

-- ═══ ครูเห็นสอบของวิชาที่ตัวเองสอน และสอบที่ตัวเองต้องไปคุม ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.actor_id',       '99999999-0000-0000-0000-000000000e12', true) as b,
       set_config('app.role',           'teacher', true) as c \gset ctx2_

do $$
declare v_session_n integer; v_proctor_n integer; v_updated_n integer;
begin
  -- ── TEST 330 ── ครู B สอนวิชา B และเป็นกรรมการคุมสอบของวิชา A
  select count(*) into v_session_n from exam_session
   where class_section_id in ('99999999-0000-0000-0000-000000000e51', '99999999-0000-0000-0000-000000000e52');
  if v_session_n <> 2 then
    raise exception 'TEST 330 ล้มเหลว: ครู B ควรเห็นสอบทั้งสองวิชา (สอนวิชา B + คุมสอบวิชา A) แต่เห็น % แถว', v_session_n;
  end if;

  -- ── TEST 331 ── อ่าน exam_proctor ผ่านสาขา "เป็นกรรมการคุมสอบเอง" ได้
  select count(*) into v_proctor_n from exam_proctor
   where exam_session_id = '99999999-0000-0000-0000-000000000e61';
  if v_proctor_n <> 1 then
    raise exception 'TEST 331 ล้มเหลว: ครู B ควรเห็นรายชื่อกรรมการคุมสอบของสอบที่ตัวเองคุม แต่เห็น % แถว', v_proctor_n;
  end if;

  -- ── TEST 332 ──
  --
  -- ต่างจากฝั่งนักศึกษาด้านบนที่เป็น insert (with check ล้มเหลว → raise
  -- exception) ฝั่งนี้เป็น update ที่ using ของ academic_update กรองแถวออก
  -- ไปตั้งแต่ต้น จึงไม่มีอะไรให้ update แล้วจบแบบ 0 แถวเงียบ ๆ ไม่ raise
  update exam_session set room_id = null where id = '99999999-0000-0000-0000-000000000e61';
  get diagnostics v_updated_n = row_count;
  if v_updated_n > 0 then
    raise exception 'TEST 332 ล้มเหลว: ครูแก้ตารางสอบเองได้ % แถว', v_updated_n;
  end if;

  raise notice 'TEST 330 ผ่าน — ครู B เห็นสอบของวิชาที่ตัวเองสอนและสอบที่ตัวเองต้องคุม (% แถว)', v_session_n;
  raise notice 'TEST 331 ผ่าน — ครูอ่านรายชื่อกรรมการคุมสอบของสอบที่ตัวเองเกี่ยวข้องได้';
  raise notice 'TEST 332 ผ่าน — ครูแก้ตารางสอบเองไม่ได้';
end $$;
rollback;

-- ═══ ครู A อ่านรายชื่อกรรมการคุมสอบของวิชาที่ตัวเองสอนได้ (แม้ไม่ได้เป็นกรรมการเอง) ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.actor_id',       '99999999-0000-0000-0000-000000000e11', true) as b,
       set_config('app.role',           'teacher', true) as c \gset ctx3_

do $$
declare v_n integer;
begin
  select count(*) into v_n from exam_proctor
   where exam_session_id = '99999999-0000-0000-0000-000000000e61';
  if v_n <> 1 then
    raise exception 'TEST 333 ล้มเหลว: ครู A (เจ้าของวิชา) ควรเห็นรายชื่อกรรมการคุมสอบวิชาตัวเอง แต่เห็น % แถว', v_n;
  end if;
  raise notice 'TEST 333 ผ่าน — ครูเจ้าของวิชาอ่านรายชื่อกรรมการคุมสอบได้แม้ไม่ได้เป็นกรรมการเอง';
end $$;
rollback;

-- ═══ ฝ่ายวิชาการสร้าง/แก้/ลบตารางสอบและกรรมการคุมสอบได้ตามปกติ ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.actor_id',       '99999999-0000-0000-0000-000000000e11', true) as b,
       set_config('app.role',           'academic', true) as c \gset ctx4_

do $$
declare v_id uuid; v_n integer;
begin
  insert into exam_session (institution_id, class_section_id, kind, exam_date, period_from, period_to, room_id)
  values ('11111111-1111-1111-1111-111111111111', '99999999-0000-0000-0000-000000000e51',
          'midterm', '2598-07-01', 1, 2, '99999999-0000-0000-0000-000000000e41')
  returning id into v_id;

  insert into exam_proctor (exam_session_id, staff_id)
  values (v_id, '99999999-0000-0000-0000-000000000e22');

  update exam_session set period_to = 3 where id = v_id;
  select period_to into v_n from exam_session where id = v_id;
  if v_n <> 3 then
    raise exception 'TEST 334 ล้มเหลว: ฝ่ายวิชาการแก้กำหนดการสอบไม่ได้';
  end if;

  delete from exam_proctor where exam_session_id = v_id;
  delete from exam_session where id = v_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'TEST 334 ล้มเหลว: ฝ่ายวิชาการลบตารางสอบไม่ได้';
  end if;

  raise notice 'TEST 334 ผ่าน — ฝ่ายวิชาการสร้าง/แก้/ลบตารางสอบและกรรมการคุมสอบได้ตามปกติ';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบตารางสอบครบทุกข้อ ════'; end $$;

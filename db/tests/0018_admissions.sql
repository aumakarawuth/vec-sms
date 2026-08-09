-- ═══════════════════════════════════════════════════════════════════
-- 0018_admissions.sql
-- ทดสอบงานรับสมัครนักศึกษาใหม่
--
-- ─── สามอย่างที่ชุดนี้จับ ───
-- 1. **สมัครซ้ำด้วยเลขบัตรเดิม** ถ้าผ่านทั้งสองใบจะได้รหัสนักศึกษาสองรหัส
--    ซึ่งแก้ทีหลังยากมากเพราะข้อมูลกระจายไปทั้งระบบแล้ว
-- 2. **ประกาศผ่านเกินที่นั่ง** วิทยาลัยจะรับนักศึกษาเกินที่รองรับได้จริง
--    แล้วไปรู้ตอนเปิดเทอมว่าห้องไม่พอ
-- 3. **รับเข้าซ้ำ** จะได้นักศึกษาสองคนจากใบสมัครใบเดียว
--
-- ทั้งสามข้อไม่มีอาการอะไรให้เห็นในวันที่เกิด
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมรอบรับสมัครและโควตา ──────────────────────────────────────
insert into admission_round
  (id, institution_id, academic_year_id, code, name_th,
   applies_from, applies_to, status)
values ('aa000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        'R1-2569', 'รอบรับตรง 1/2569',
        current_date - 7, current_date + 7, 'open')
on conflict do nothing;

insert into admission_quota (id, round_id, curriculum_version_id, seats)
values ('aa000000-0000-0000-0000-000000000002',
        'aa000000-0000-0000-0000-000000000001',
        '77777777-7777-7777-7777-777777777767', 1)
on conflict do nothing;

-- ── TEST 153 ───────────────────────────────────────────────────────
-- ยื่นใบสมัคร — ต้องเลือกหลักสูตรก่อน และเลขที่ต้องไม่ซ้ำ
do $$
declare
  v_a1 uuid; v_a2 uuid;
  v_no1 text; v_no2 text;
  v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  v_no1 := next_application_no('aa000000-0000-0000-0000-000000000001');

  insert into application
    (institution_id, round_id, application_no, first_name_th, last_name_th,
     national_id_hash, prior_school_th, prior_qualification_th, prior_gpax, referral_source)
  values ('11111111-1111-1111-1111-111111111111',
          'aa000000-0000-0000-0000-000000000001', v_no1,
          'ณัฐดนัย', 'ผู้สมัครหนึ่ง', digest('1100000000001', 'sha256'),
          'โรงเรียนทดสอบวิทยา', 'ม.3', 2.85, 'เพจเฟซบุ๊กของวิทยาลัย')
  returning id into v_a1;

  -- ยังไม่เลือกหลักสูตร ยื่นไม่ได้
  begin
    perform submit_application(v_a1);
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  insert into application_choice (application_id, preference, curriculum_version_id)
  values (v_a1, 1, '77777777-7777-7777-7777-777777777767');

  perform submit_application(v_a1);

  if (select status from application where id = v_a1) <> 'submitted' then
    raise exception 'TEST 153 ล้มเหลว: ยื่นใบสมัครแล้วสถานะไม่เปลี่ยน';
  end if;

  -- ยื่นซ้ำไม่ได้
  begin
    perform submit_application(v_a1);
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  v_no2 := next_application_no('aa000000-0000-0000-0000-000000000001');
  if v_no2 = v_no1 then
    raise exception 'TEST 153 ล้มเหลว: จ่ายเลขที่ใบสมัครซ้ำ (%)', v_no1;
  end if;

  if v_blocked <> 2 then
    raise exception 'TEST 153 ล้มเหลว: ควรถูกบล็อกสองทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  raise notice 'TEST 153 ผ่าน — เลขที่ % แล้ว % · ไม่เลือกหลักสูตรยื่นไม่ได้ · ยื่นซ้ำไม่ได้',
    v_no1, v_no2;
end $$;

-- ── TEST 154 ───────────────────────────────────────────────────────
-- สมัครซ้ำด้วยเลขบัตรประชาชนเดิมในรอบเดียวกันไม่ได้
do $$
declare v_no text;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  v_no := next_application_no('aa000000-0000-0000-0000-000000000001');
  begin
    insert into application
      (institution_id, round_id, application_no, first_name_th, last_name_th, national_id_hash)
    values ('11111111-1111-1111-1111-111111111111',
            'aa000000-0000-0000-0000-000000000001', v_no,
            'ณัฐดนัย', 'สมัครซ้ำ', digest('1100000000001', 'sha256'));
    raise exception 'TEST 154 ล้มเหลว: สมัครสองใบด้วยเลขบัตรเดิมในรอบเดียวกันได้';
  exception when unique_violation then null;
  end;

  raise notice 'TEST 154 ผ่าน — เลขบัตรเดิมสมัครซ้ำในรอบเดียวกันไม่ได้';
end $$;

-- ── TEST 155 ───────────────────────────────────────────────────────
-- ประกาศผ่านเกินที่นั่งไม่ได้ (โควตาของรอบนี้คือ 1 ที่นั่ง)
do $$
declare
  v_a1 uuid; v_a2 uuid; v_no text;
  v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select id into v_a1 from application
   where round_id = 'aa000000-0000-0000-0000-000000000001' and status = 'submitted' limit 1;

  perform decide_application(v_a1, 'passed',
    '77777777-7777-7777-7777-777777777767', 1::smallint, 78.5, 'ผ่านการคัดเลือก');

  if (select status from application where id = v_a1) <> 'passed' then
    raise exception 'TEST 155 ล้มเหลว: ตัดสินผ่านแล้วสถานะไม่เปลี่ยน';
  end if;

  -- ผู้สมัครคนที่สอง — ที่นั่งเต็มแล้ว
  v_no := next_application_no('aa000000-0000-0000-0000-000000000001');
  insert into application
    (institution_id, round_id, application_no, first_name_th, last_name_th, national_id_hash)
  values ('11111111-1111-1111-1111-111111111111',
          'aa000000-0000-0000-0000-000000000001', v_no,
          'ปาริชาต', 'ผู้สมัครสอง', digest('1100000000002', 'sha256'))
  returning id into v_a2;

  insert into application_choice (application_id, preference, curriculum_version_id)
  values (v_a2, 1, '77777777-7777-7777-7777-777777777767');
  perform submit_application(v_a2);

  begin
    perform decide_application(v_a2, 'passed',
      '77777777-7777-7777-7777-777777777767', 2::smallint, 70.0, null);
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  -- แต่ขึ้นสำรองได้ ไม่ติดโควตา
  perform decide_application(v_a2, 'waitlisted', null, 2::smallint, 70.0, 'ลำดับสำรอง');

  if v_blocked <> 1 then
    raise exception 'TEST 155 ล้มเหลว: ประกาศผ่านเกินที่นั่งได้';
  end if;
  if (select status from application where id = v_a2) <> 'waitlisted' then
    raise exception 'TEST 155 ล้มเหลว: ขึ้นสำรองไม่ได้';
  end if;

  raise notice 'TEST 155 ผ่าน — ผ่านเกินที่นั่งไม่ได้ แต่ขึ้นสำรองได้';
end $$;

-- ── TEST 156 ───────────────────────────────────────────────────────
-- รับเข้าเป็นนักศึกษา — ครบทุกชั้น และทำได้ครั้งเดียว
do $$
declare
  v_app     uuid;
  v_student uuid;
  v_blocked integer := 0;
  v_cur     integer;
  v_place   integer;
  v_prior   integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select id into v_app from application
   where round_id = 'aa000000-0000-0000-0000-000000000001' and status = 'passed' limit 1;

  v_student := admit_applicant(v_app, '69ADM00001',
                 '22222222-2222-2222-2222-222222222222', 1::smallint, 'ปวช.1/1');

  select count(*) into v_cur   from student_curriculum where student_id = v_student;
  select count(*) into v_place from student_class_placement where student_id = v_student;
  -- วุฒิเดิมต้องยังตามหาได้จากใบสมัคร แต่ต้องไม่ไปโผล่ใน prior_academic_record
  -- ซึ่งเป็นตารางของผลรายวิชาที่เทียบโอน ไม่ใช่ของวุฒิที่จบมา
  select count(*) into v_prior from prior_academic_record where student_id = v_student;

  if v_cur = 0 then
    raise exception 'TEST 156 ล้มเหลว: รับเข้าแล้วไม่ได้สังกัดหลักสูตร';
  end if;
  if v_place = 0 then
    raise exception 'TEST 156 ล้มเหลว: รับเข้าแล้วไม่มีชั้นปี จะคิดค่าเทอมตามชั้นปีไม่ได้';
  end if;
  if v_prior <> 0 then
    raise exception 'TEST 156 ล้มเหลว: วุฒิเดิมถูกยัดลง prior_academic_record % แถว จะทำให้รายงานเทียบโอนมีขยะปน', v_prior;
  end if;
  if not exists (select 1 from application a
                  where a.student_id = v_student and a.prior_school_th is not null) then
    raise exception 'TEST 156 ล้มเหลว: ตามหาวุฒิเดิมจากใบสมัครไม่ได้';
  end if;
  if (select status from application where id = v_app) <> 'enrolled' then
    raise exception 'TEST 156 ล้มเหลว: ใบสมัครไม่ได้เปลี่ยนเป็นรับเข้าแล้ว';
  end if;

  -- รับเข้าซ้ำต้องไม่ได้ มิฉะนั้นได้นักศึกษาสองคนจากใบสมัครใบเดียว
  begin
    perform admit_applicant(v_app, '69ADM00002',
              '22222222-2222-2222-2222-222222222222', 1::smallint, null);
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  -- คนที่ยังไม่ผ่านการคัดเลือกรับเข้าไม่ได้
  begin
    perform admit_applicant(
      (select id from application where status = 'waitlisted' limit 1),
      '69ADM00003', '22222222-2222-2222-2222-222222222222', 1::smallint, null);
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 2 then
    raise exception 'TEST 156 ล้มเหลว: ควรถูกบล็อกสองทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  raise notice 'TEST 156 ผ่าน — ได้นักศึกษา + หลักสูตร + ชั้นปี · วุฒิเดิมอยู่บนใบสมัครไม่ปนตารางเทียบโอน · รับเข้าซ้ำและรับคนไม่ผ่านไม่ได้';
end $$;

-- ── TEST 157 ───────────────────────────────────────────────────────
-- สรุปยอดรับสมัครต้องตรงกับความจริง
do $$
declare r record;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  select * into r from admission_summary('aa000000-0000-0000-0000-000000000001');

  if r.seats is null then
    raise exception 'TEST 157 ล้มเหลว: ไม่มีสรุปยอดของรอบนี้';
  end if;
  if r.enrolled <> 1 then
    raise exception 'TEST 157 ล้มเหลว: รับเข้าไปแล้ว 1 คน แต่สรุปว่า %', r.enrolled;
  end if;
  if r.seats_left <> 0 then
    raise exception 'TEST 157 ล้มเหลว: ที่นั่งเหลือควรเป็น 0 ได้ %', r.seats_left;
  end if;

  raise notice 'TEST 157 ผ่าน — % · ที่นั่ง % · สมัคร % · ผ่าน % · รับเข้า % · เหลือ %',
    r.curriculum_th, r.seats, r.applied, r.passed, r.enrolled, r.seats_left;
end $$;

-- ── TEST 158 ───────────────────────────────────────────────────────
-- ข้อมูลผู้สมัครมีเลขบัตรประชาชนและข้อมูลผู้เยาว์ — ครูและวิทยาลัยอื่นต้องไม่เห็น
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_a integer; v_r integer;
begin
  select count(*) into v_a from application;
  select count(*) into v_r from admission_round;
  if v_a + v_r <> 0 then
    raise exception 'TEST 158 ล้มเหลว: ครูผู้สอนเห็นใบสมัคร % ใบ รอบรับสมัคร % รอบ', v_a, v_r;
  end if;
end $$;
rollback;

begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_a integer; v_q integer; v_c integer;
begin
  select count(*) into v_a from application;
  select count(*) into v_q from admission_quota;
  select count(*) into v_c from application_choice;
  if v_a + v_q + v_c <> 0 then
    raise exception 'TEST 158 ล้มเหลว: วิทยาลัยอื่นเห็นใบสมัคร % โควตา % อันดับ %', v_a, v_q, v_c;
  end if;
  raise notice 'TEST 158 ผ่าน — ครูผู้สอนและวิทยาลัยอื่นไม่เห็นข้อมูลผู้สมัครเลย';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบงานรับสมัครครบทุกข้อ ════'; end $$;

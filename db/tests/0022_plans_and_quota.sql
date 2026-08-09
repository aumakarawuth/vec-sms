-- ═══════════════════════════════════════════════════════════════════
-- 0022_plans_and_quota.sql
-- ทดสอบแพ็กเกจ โควตา และการวัดปริมาณใช้งาน
--
-- ─── สามอย่างที่ชุดนี้จับ ───
-- 1. **วิทยาลัยที่ยังไม่ได้ผูกแพ็กเกจต้องไม่ถูกล็อก** ถ้า deploy แล้ววิทยาลัย
--    ที่ใช้อยู่รับนักศึกษาไม่ได้ทันที นั่นคือความเสียหายที่ผู้ให้บริการก่อเอง
-- 2. **soft ต้องไม่บล็อก** การหยุดงานทะเบียนกลางภาคเพราะเกินโควตาสิบคน
--    เสียหายกับลูกค้ามากกว่ามูลค่าที่ได้เพิ่ม
-- 3. **วิทยาลัยแก้โควตาของตัวเองไม่ได้** มิฉะนั้นเท่ากับซื้อแพ็กเกจฟรี
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

insert into plan (id, code, name_th, max_students, max_staff,
                  price_per_year, enforcement, grace_percent)
values ('99000000-0000-0000-0000-000000000001', 'SMALL-SOFT', 'เล็ก (เตือน)',
        2, 10, 30000, 'soft', 10),
       ('99000000-0000-0000-0000-000000000002', 'SMALL-HARD', 'เล็ก (บังคับ)',
        2, 10, 30000, 'hard', 0),
       ('99000000-0000-0000-0000-000000000003', 'UNLIMITED', 'ไม่จำกัด',
        null, null, 200000, 'hard', 0)
on conflict (code) do nothing;

-- ── TEST 177 ───────────────────────────────────────────────────────
-- วิทยาลัยที่ยังไม่ได้ผูกแพ็กเกจต้องทำงานได้ตามปกติ
do $$
declare
  u        record;
  v_person uuid;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);
  perform set_config('app.role', 'registrar', true);

  select * into u from institution_usage('11111111-1111-1111-1111-111111111111');

  if u.plan_code is not null then
    raise exception 'TEST 177 ล้มเหลว: ไม่ควรมีแพ็กเกจผูกอยู่ก่อน';
  end if;
  if u.students_active is null or u.students_active = 0 then
    raise exception 'TEST 177 ล้มเหลว: นับนักศึกษาไม่ได้';
  end if;

  -- ต้องรับนักศึกษาใหม่ได้ตามปกติทั้งที่ยังไม่มีแพ็กเกจ
  insert into person (id, institution_id, first_name_th, last_name_th)
  values ('99000000-0000-0000-0000-0000000000a1',
          '11111111-1111-1111-1111-111111111111', 'ก่อนผูก', 'แพ็กเกจ')
  returning id into v_person;

  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values ('11111111-1111-1111-1111-111111111111', v_person, '69QUOTA001', 2569);

  raise notice 'TEST 177 ผ่าน — ยังไม่ผูกแพ็กเกจก็รับนักศึกษาได้ (ใช้อยู่ % คน)', u.students_active;
end $$;

-- ── TEST 178 ───────────────────────────────────────────────────────
-- แพ็กเกจแบบ soft เกินได้แต่ต้องขึ้นในรายงาน
do $$
declare
  u        record;
  v_person uuid;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  -- ผูกแพ็กเกจเล็กแบบเตือน (ครอบ 2 คน ทั้งที่มีอยู่แล้วหลายคน)
  insert into institution_subscription
    (institution_id, plan_id, starts_on, status)
  values ('11111111-1111-1111-1111-111111111111',
          '99000000-0000-0000-0000-000000000001', current_date - 30, 'active');

  select * into u from institution_usage('11111111-1111-1111-1111-111111111111');

  if u.plan_code <> 'SMALL-SOFT' then
    raise exception 'TEST 178 ล้มเหลว: ไม่ได้ใช้แพ็กเกจที่ผูกไว้ (%)', u.plan_code;
  end if;
  if u.over_students <= 0 then
    raise exception 'TEST 178 ล้มเหลว: ใช้เกินแล้วแต่รายงานว่าไม่เกิน (ใช้ % จาก %)',
      u.students_active, u.students_limit;
  end if;

  -- เกินแล้วแต่ยังต้องรับเพิ่มได้ เพราะเป็น soft
  insert into person (id, institution_id, first_name_th, last_name_th)
  values ('99000000-0000-0000-0000-0000000000a2',
          '11111111-1111-1111-1111-111111111111', 'เกินโควตา', 'แบบเตือน')
  returning id into v_person;

  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values ('11111111-1111-1111-1111-111111111111', v_person, '69QUOTA002', 2569);

  raise notice 'TEST 178 ผ่าน — % ครอบ % คน ใช้ % คน เกิน % คน และยังรับเพิ่มได้',
    u.plan_name_th, u.students_limit, u.students_active, u.over_students;
end $$;

-- ── TEST 179 ───────────────────────────────────────────────────────
-- แพ็กเกจแบบ hard ต้องบล็อก และข้อความต้องบอกว่าต้องทำอะไรต่อ
do $$
declare
  v_person uuid;
  v_msg    text;
  u        record;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  -- ปิดสัญญาเดิมแล้วผูกแบบบังคับ
  update institution_subscription set ends_on = current_date - 1
   where institution_id = '11111111-1111-1111-1111-111111111111'
     and ends_on is null;

  insert into institution_subscription
    (institution_id, plan_id, starts_on, status)
  values ('11111111-1111-1111-1111-111111111111',
          '99000000-0000-0000-0000-000000000002', current_date, 'active');

  insert into person (id, institution_id, first_name_th, last_name_th)
  values ('99000000-0000-0000-0000-0000000000a3',
          '11111111-1111-1111-1111-111111111111', 'เกินโควตา', 'แบบบังคับ')
  returning id into v_person;

  begin
    insert into student (institution_id, person_id, student_code, admitted_year_be)
    values ('11111111-1111-1111-1111-111111111111', v_person, '69QUOTA003', 2569);
    raise exception 'TEST 179 ล้มเหลว: แพ็กเกจแบบบังคับไม่ได้บล็อก';
  exception when check_violation then
    get stacked diagnostics v_msg = message_text;
  end;

  if v_msg not like '%เพิ่มที่นั่ง%' then
    raise exception 'TEST 179 ล้มเหลว: ข้อความไม่ได้บอกว่าต้องทำอะไรต่อ (%)', v_msg;
  end if;

  -- ซื้อที่นั่งเพิ่มแล้วต้องรับได้
  select * into u from institution_usage('11111111-1111-1111-1111-111111111111');
  update institution_subscription
     set seats_purchased = u.students_active + 5
   where institution_id = '11111111-1111-1111-1111-111111111111'
     and ends_on is null;

  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values ('11111111-1111-1111-1111-111111111111', v_person, '69QUOTA003', 2569);

  raise notice 'TEST 179 ผ่าน — บล็อกพร้อมบอกทางแก้ (%) · ซื้อที่นั่งเพิ่มแล้วรับได้', v_msg;
end $$;

-- ── TEST 180 ───────────────────────────────────────────────────────
-- ภาพนิ่งปริมาณใช้งาน — เก็บซ้ำวันเดิมคือการแก้ไข ไม่ใช่แถวใหม่
do $$
declare
  s1 usage_snapshot;
  s2 usage_snapshot;
  v_rows integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  s1 := take_usage_snapshot('11111111-1111-1111-1111-111111111111');
  s2 := take_usage_snapshot('11111111-1111-1111-1111-111111111111');

  select count(*) into v_rows from usage_snapshot
   where institution_id = '11111111-1111-1111-1111-111111111111'
     and taken_on = current_date;

  if v_rows <> 1 then
    raise exception 'TEST 180 ล้มเหลว: เก็บซ้ำวันเดิมได้ % แถว ควรได้ 1', v_rows;
  end if;
  if s1.students_active = 0 then
    raise exception 'TEST 180 ล้มเหลว: ภาพนิ่งนับนักศึกษาได้ 0 คน';
  end if;
  if s2.taken_at < s1.taken_at then
    raise exception 'TEST 180 ล้มเหลว: เก็บซ้ำแล้วเวลาไม่อัปเดต';
  end if;

  raise notice 'TEST 180 ผ่าน — นักศึกษา % · บุคลากร % · เอกสาร % · ใบสมัคร % (เก็บซ้ำไม่เกิดแถวใหม่)',
    s1.students_active, s1.staff_active, s1.documents_issued, s1.applications;
end $$;

-- ── TEST 181 ───────────────────────────────────────────────────────
-- วิทยาลัยแก้โควตาของตัวเองไม่ได้ และไม่เห็นสัญญาของวิทยาลัยอื่น
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'admin';

do $$
declare
  v_mine   integer;
  v_all    integer;
  v_blocked integer := 0;
begin
  select count(*) into v_mine from institution_subscription;
  if v_mine = 0 then
    raise exception 'TEST 181 ล้มเหลว: วิทยาลัยไม่เห็นสัญญาของตัวเอง';
  end if;

  -- เพิ่มที่นั่งให้ตัวเองไม่ได้ = ซื้อแพ็กเกจฟรีไม่ได้
  begin
    update institution_subscription set seats_purchased = 999999
     where institution_id = '11111111-1111-1111-1111-111111111111';
    -- with check ปฏิเสธ แต่บาง PostgreSQL คืน 0 แถวแทนการ raise
    if (select max(seats_purchased) from institution_subscription) = 999999 then
      raise exception 'TEST 181 ล้มเหลว: วิทยาลัยเพิ่มที่นั่งให้ตัวเองได้';
    end if;
    v_blocked := v_blocked + 1;
  exception when insufficient_privilege or check_violation then
    v_blocked := v_blocked + 1;
  end;

  -- สร้างสัญญาใหม่ให้ตัวเองไม่ได้
  begin
    insert into institution_subscription (institution_id, plan_id, starts_on, status)
    values ('11111111-1111-1111-1111-111111111111',
            '99000000-0000-0000-0000-000000000003', current_date + 400, 'active');
    raise exception 'TEST 181 ล้มเหลว: วิทยาลัยผูกแพ็กเกจไม่จำกัดให้ตัวเองได้';
  exception when insufficient_privilege or check_violation then
    v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 2 then
    raise exception 'TEST 181 ล้มเหลว: ควรถูกกันสองทาง กันได้จริง % ทาง', v_blocked;
  end if;

  -- แต่ต้องอ่านรายการแพ็กเกจได้ เพราะต้องรู้ว่ามีอะไรให้อัปเกรด
  select count(*) into v_all from plan;
  if v_all = 0 then
    raise exception 'TEST 181 ล้มเหลว: อ่านรายการแพ็กเกจไม่ได้ จะอัปเกรดอย่างไร';
  end if;

  raise notice 'TEST 181 ผ่าน — เห็นสัญญาของตัวเอง อ่านแพ็กเกจได้ % รายการ แต่แก้โควตาไม่ได้', v_all;
end $$;
rollback;

-- ── TEST 182 ───────────────────────────────────────────────────────
-- วิทยาลัยอื่นไม่เห็นสัญญาและปริมาณใช้งานของเรา
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_sub integer; v_use integer;
begin
  select count(*) into v_sub from institution_subscription;
  select count(*) into v_use from usage_snapshot;
  if v_sub + v_use <> 0 then
    raise exception 'TEST 182 ล้มเหลว: วิทยาลัยอื่นเห็นสัญญา % และปริมาณใช้งาน %', v_sub, v_use;
  end if;
  raise notice 'TEST 182 ผ่าน — วิทยาลัยอื่นไม่เห็นสัญญาหรือปริมาณใช้งานของเราเลย';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบแพ็กเกจและโควตาครบทุกข้อ ════'; end $$;

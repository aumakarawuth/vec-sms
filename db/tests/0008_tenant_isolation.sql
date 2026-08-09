-- ═══════════════════════════════════════════════════════════════════
-- 0008_tenant_isolation.sql
-- ทดสอบว่าตารางลูกที่เพิ่งได้ RLS ใน migration 0017 กันข้ามวิทยาลัยได้จริง
--
-- ─── ทำไมต้องมีชุดนี้แยกจาก TEST 45b ───
-- TEST 45b ตรวจแค่ว่า "เปิด RLS แล้วหรือยัง" ซึ่งเป็นการตรวจการมีอยู่ของ
-- นโยบาย ไม่ใช่ความถูกต้องของมัน นโยบายที่เขียนเส้นทางสังกัดผิด
-- จะผ่าน 45b สบาย ๆ แต่ยังรั่วอยู่ ชุดนี้จึงอ่านและเขียนจริงข้ามวิทยาลัย
--
-- ─── สองอย่างที่ชุดนี้จับเป็นพิเศษ ───
-- 1. infinite recursion — student_guardian กับ class_meeting อยู่ในวงจร
--    ที่นโยบายอ้างกันไปมา ถ้าเขียนผิด PostgreSQL จะ error ทันทีที่ query
-- 2. ผู้ปกครองเข้าไม่ได้ทั้งระบบ — นโยบายของ invoice และ student ตรวจว่า
--    "มีผู้ปกครองที่ยืนยันแล้วไหม" โดย join student_guardian ถ้า
--    student_guardian ถูกปิดแน่นเกินไป การตรวจนั้นจะหาไม่เจอ
--    แล้วผู้ปกครองจะหมดสิทธิ์ทุกหน้าจอโดยที่ไม่มี error ให้เห็นเลย
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_runtime') then
    create role app_runtime nologin;
  end if;
end $$;

grant usage on schema public to app_runtime;
grant select, insert, update, delete on all tables    in schema public to app_runtime;
grant usage, select                  on all sequences in schema public to app_runtime;
grant execute                        on all functions in schema public to app_runtime;

-- ── เตรียมข้อมูล: ผู้ปกครองที่ยืนยันตัวตนแล้วของ ปิยะพงศ์ ─────────
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender, phone)
values ('aaaa0000-0000-0000-0000-0000000000f1',
        '11111111-1111-1111-1111-111111111111',
        'นาง', 'สุนีย์', 'ศรีสุข', 'female', '0812345678')
on conflict (id) do nothing;

insert into student_guardian
  (id, student_id, person_id, relation, is_primary,
   can_view_grades, can_view_finance, can_approve_leave, verified_at)
values ('aaaa0000-0000-0000-0000-0000000000f2',
        'aaaa0000-0000-0000-0000-000000000011',
        'aaaa0000-0000-0000-0000-0000000000f1',
        'mother', true, true, true, true, now())
on conflict (id) do nothing;

-- ผู้ปกครองอีกคนที่ยังไม่ได้ยืนยันตัวตน — ต้องไม่เห็นอะไรเลย
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
values ('aaaa0000-0000-0000-0000-0000000000f3',
        '11111111-1111-1111-1111-111111111111',
        'นาย', 'ไม่ยืนยัน', 'ตัวตน', 'male')
on conflict (id) do nothing;

insert into student_guardian
  (id, student_id, person_id, relation, is_primary,
   can_view_grades, can_view_finance, verified_at)
values ('aaaa0000-0000-0000-0000-0000000000f4',
        'aaaa0000-0000-0000-0000-000000000011',
        'aaaa0000-0000-0000-0000-0000000000f3',
        'relative', false, true, true, null)
on conflict (id) do nothing;

-- ── TEST 64 ────────────────────────────────────────────────────────
-- วิทยาลัยอื่นต้องไม่เห็นตารางลูกเหล่านี้เลยสักแถว
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare r record; v_leaks text := '';
begin
  for r in
    select unnest(array[
      'installment', 'invoice_line', 'payment_allocation', 'ledger_entry',
      'student_guardian', 'class_meeting', 'curriculum_course', 'student_curriculum',
      'curriculum_version', 'competency', 'graduation_rule', 'program_track',
      'student_status_history', 'intervention_action', 'fee_schedule_line',
      'attendance_status_weight', 'risk_policy', 'behavior_policy'
    ]) as t
  loop
    declare v_n bigint;
    begin
      execute format('select count(*) from %I', r.t) into v_n;
      if v_n <> 0 then
        v_leaks := v_leaks || format('%s=%s ', r.t, v_n);
      end if;
    end;
  end loop;

  if v_leaks <> '' then
    raise exception 'TEST 64 ล้มเหลว: วิทยาลัยอื่นยังเห็นข้อมูล — %', v_leaks;
  end if;
  raise notice 'TEST 64 ผ่าน — วิทยาลัยอื่นไม่เห็นตารางลูกทั้ง 18 ตารางเลยสักแถว';
end $$;

-- ── TEST 65 ────────────────────────────────────────────────────────
-- อ่านไม่เห็นอย่างเดียวไม่พอ เขียนข้ามวิทยาลัยก็ต้องไม่ได้
do $$
declare v_invoice uuid; v_section uuid;
begin
  -- ใช้ id จริงของวิทยาลัยที่ 1 ซึ่งผู้โจมตีอาจได้มาจากที่อื่น
  select id into v_invoice from invoice limit 1;   -- ต้องเป็น null เพราะ RLS
  if v_invoice is not null then
    raise exception 'TEST 65 เตรียมข้อมูลผิด: ไม่ควรเห็นใบแจ้งหนี้ของวิทยาลัยอื่น';
  end if;

  begin
    insert into installment (invoice_id, seq, due_on, amount)
    values ('8cc4fbc6-1990-4bc3-821f-116b287c0910', 99, current_date, 1);
    raise exception 'TEST 65 ล้มเหลว: เขียนงวดผ่อนชำระเข้าใบแจ้งหนี้ของวิทยาลัยอื่นได้';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into class_meeting (class_section_id, meets_on, period_from, period_to)
    values ('bbbb0000-0000-0000-0000-000000000001', current_date, 1, 2);
    raise exception 'TEST 65 ล้มเหลว: เขียนคาบเรียนเข้ากลุ่มของวิทยาลัยอื่นได้';
  exception
    when insufficient_privilege then null;
  end;

  begin
    insert into student_guardian (student_id, person_id, relation)
    values ('aaaa0000-0000-0000-0000-000000000011',
            'aaaa0000-0000-0000-0000-000000000002', 'guardian');
    raise exception 'TEST 65 ล้มเหลว: ผูกผู้ปกครองให้นักศึกษาของวิทยาลัยอื่นได้';
  exception
    when insufficient_privilege then null;
  end;

  raise notice 'TEST 65 ผ่าน — เขียนข้ามวิทยาลัยถูกปฏิเสธทั้งงวดผ่อนชำระ คาบเรียน และผู้ปกครอง';
end $$;
commit;

-- ── TEST 66 ────────────────────────────────────────────────────────
-- วิทยาลัยตัวเองต้องยังทำงานได้ครบเหมือนเดิม
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'registrar';

do $$
declare v_inst int; v_line int; v_meet int; v_cc int; v_sg int;
begin
  select count(*) into v_inst from installment;
  select count(*) into v_line from invoice_line;
  select count(*) into v_meet from class_meeting;
  select count(*) into v_cc   from curriculum_course;
  select count(*) into v_sg   from student_guardian;

  if v_inst = 0 or v_line = 0 or v_meet = 0 or v_cc = 0 or v_sg = 0 then
    raise exception
      'TEST 66 ล้มเหลว: วิทยาลัยตัวเองมองไม่เห็นข้อมูลของตน — งวด % · รายการ % · คาบ % · รายวิชา % · ผู้ปกครอง %',
      v_inst, v_line, v_meet, v_cc, v_sg;
  end if;
  raise notice 'TEST 66 ผ่าน — งานทะเบียนเห็นครบ (งวด % · รายการ % · คาบ % · รายวิชาในหลักสูตร % · ผู้ปกครอง %)',
    v_inst, v_line, v_meet, v_cc, v_sg;
end $$;
commit;

-- ── TEST 67 ────────────────────────────────────────────────────────
-- ต้องไม่เกิด infinite recursion ในนโยบาย
--
-- student_guardian อยู่ในวงจรกับ student และ class_meeting อยู่ในวงจรกับ
-- class_section ถ้าเขียนนโยบายให้อ้างกลับตรง ๆ PostgreSQL จะ error
-- ทันทีที่ query ไม่ใช่ตอน migration — บั๊กแบบนี้จึงหลุดขึ้นระบบจริงได้ง่าย
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';

do $$
declare v int;
begin
  select count(*) into v from student_guardian;
  select count(*) into v from class_meeting;
  select count(*) into v from student;
  select count(*) into v from invoice;
  select count(*) into v from installment;
  raise notice 'TEST 67 ผ่าน — ไม่มี infinite recursion ในนโยบายที่อ้างกันไปมา';
exception
  when others then
    raise exception 'TEST 67 ล้มเหลว: % (%)', sqlerrm, sqlstate;
end $$;

-- นักศึกษาต้องเห็นงวดผ่อนชำระของตัวเอง แต่ไม่เห็นการตัดยอดหลังบ้าน
do $$
declare v_inst int; v_alloc int;
begin
  select count(*) into v_inst  from installment;
  select count(*) into v_alloc from payment_allocation;

  if v_inst = 0 then
    raise exception 'TEST 67b ล้มเหลว: นักศึกษาดูงวดผ่อนชำระของตัวเองไม่ได้';
  end if;
  if v_alloc <> 0 then
    raise exception 'TEST 67b ล้มเหลว: นักศึกษาเห็นการตัดยอดหลังบ้าน % รายการ', v_alloc;
  end if;
  raise notice 'TEST 67b ผ่าน — นักศึกษาเห็นงวดของตัวเอง % งวด แต่ไม่เห็นการตัดยอดหลังบ้าน', v_inst;
end $$;
commit;

-- ── TEST 68 ────────────────────────────────────────────────────────
-- ผู้ปกครองที่ยืนยันตัวตนแล้วต้องยังเข้าถึงข้อมูลบุตรได้
--
-- ข้อนี้คือการถดถอยที่น่ากลัวที่สุดของ migration 0017 — ถ้า student_guardian
-- ถูกปิดแน่นเกินไป นโยบายของ invoice ที่ join หาผู้ปกครองจะหาไม่เจอ
-- ผู้ปกครองจะเห็นหน้าจอว่างทุกหน้าโดยไม่มี error ให้ตามหาสาเหตุ
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'guardian';
set local app.actor_id = 'aaaa0000-0000-0000-0000-0000000000f1';

do $$
declare v_stu int; v_inv int; v_inst int; v_own int;
begin
  select count(*) into v_own  from student_guardian;
  select count(*) into v_stu  from student;
  select count(*) into v_inv  from invoice;
  select count(*) into v_inst from installment;

  if v_own = 0 then
    raise exception 'TEST 68 ล้มเหลว: ผู้ปกครองมองไม่เห็นแถวความสัมพันธ์ของตัวเอง';
  end if;
  if v_stu = 0 then
    raise exception 'TEST 68 ล้มเหลว: ผู้ปกครองมองไม่เห็นข้อมูลบุตร';
  end if;
  if v_inv = 0 or v_inst = 0 then
    raise exception
      'TEST 68 ล้มเหลว: ผู้ปกครองที่มีสิทธิ์ดูการเงินเห็นใบแจ้งหนี้ % ใบ งวด % งวด',
      v_inv, v_inst;
  end if;
  raise notice 'TEST 68 ผ่าน — ผู้ปกครองที่ยืนยันแล้วเห็นบุตร % คน ใบแจ้งหนี้ % ใบ งวด % งวด',
    v_stu, v_inv, v_inst;
end $$;
commit;

-- ── TEST 69 ────────────────────────────────────────────────────────
-- ผู้ปกครองที่ยังไม่ยืนยันตัวตนต้องไม่เห็นอะไรเลย
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'guardian';
set local app.actor_id = 'aaaa0000-0000-0000-0000-0000000000f3';

do $$
declare v_stu int; v_inv int; v_inst int;
begin
  select count(*) into v_stu  from student;
  select count(*) into v_inv  from invoice;
  select count(*) into v_inst from installment;

  if v_stu <> 0 or v_inv <> 0 or v_inst <> 0 then
    raise exception
      'TEST 69 ล้มเหลว: ผู้ปกครองที่ยังไม่ยืนยันตัวตนเห็น นักศึกษา % · ใบแจ้งหนี้ % · งวด %',
      v_stu, v_inv, v_inst;
  end if;
  raise notice 'TEST 69 ผ่าน — ผู้ปกครองที่ยังไม่ยืนยันตัวตนไม่เห็นอะไรเลย (มาตรการคุ้มครองผู้เยาว์)';
end $$;
commit;

-- ── TEST 70 ────────────────────────────────────────────────────────
-- ครูเห็นคาบเรียนของกลุ่มที่ตนสอนเท่านั้น
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v int;
begin
  select count(*) into v from class_meeting;
  if v = 0 then
    raise exception 'TEST 70 ล้มเหลว: ครูผู้สอนมองไม่เห็นคาบเรียนของกลุ่มตนเอง';
  end if;
  raise notice 'TEST 70 ผ่าน — ครูผู้สอนเห็นคาบเรียนของกลุ่มตน % คาบ', v;
end $$;

-- ครูแก้โครงสร้างหลักสูตรเองไม่ได้ — กระทบการตรวจจบของทุกคนย้อนหลัง
do $$
begin
  begin
    insert into graduation_rule (curriculum_version_id, kind, name_th, threshold, sort_order)
    values ('77777777-7777-7777-7777-777777777767', 'gpax_min', 'เกณฑ์ที่ครูเพิ่มเอง', 1.0, 99);
    raise exception 'TEST 70b ล้มเหลว: ครูเพิ่มเงื่อนไขจบเองได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 70b ผ่าน — ครูแก้โครงสร้างหลักสูตรไม่ได้ ต้องเป็นฝ่ายวิชาการ';
  end;
end $$;
commit;

-- ── TEST 71 ────────────────────────────────────────────────────────
-- ฝ่ายวิชาการแก้โครงสร้างหลักสูตรได้ตามหน้าที่
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'academic';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_id uuid;
begin
  insert into graduation_rule (curriculum_version_id, kind, name_th, threshold, sort_order)
  values ('77777777-7777-7777-7777-777777777767', 'gpax_min', 'เกณฑ์ทดสอบสิทธิ์ฝ่ายวิชาการ', 1.0, 98)
  returning id into v_id;

  delete from graduation_rule where id = v_id;
  raise notice 'TEST 71 ผ่าน — ฝ่ายวิชาการเพิ่มและลบเงื่อนไขจบได้ตามหน้าที่';
end $$;
commit;

\echo ''
\echo '════ ทดสอบการแยกข้อมูลของตารางลูกครบทุกข้อ ════'

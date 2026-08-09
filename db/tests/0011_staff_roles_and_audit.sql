-- ═══════════════════════════════════════════════════════════════════
-- 0011_staff_roles_and_audit.sql
-- ทดสอบสิทธิของบุคลากร และบันทึกการเข้าถึงหรือเปลี่ยนแปลงข้อมูล
--
-- ─── ทำไมชุดนี้สำคัญ ───
-- ก่อน migration 0022 บทบาท registrar, finance, academic, director และ admin
-- ไม่มีทางผูกกับคนจริงได้เลย นโยบาย RLS ทั้งหมดที่เขียนไว้สำหรับบทบาทเหล่านั้น
-- จึงไม่เคยถูกใช้จริงในระบบที่ปิด DEV_AUTH
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

-- บุคลากรอีกคนสำหรับทดสอบ (สมชายเป็น staff อยู่แล้วจาก seed)
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
values ('aaaa0000-0000-0000-0000-0000000000c1',
        '11111111-1111-1111-1111-111111111111', 'นาง', 'อารีย์', 'ทะเบียนดี', 'female')
on conflict (id) do nothing;

insert into staff (id, institution_id, person_id, staff_code, employment_kind, is_teacher)
values ('aaaa0000-0000-0000-0000-0000000000c2',
        '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-0000000000c1', 'REG-001', 'permanent', false)
on conflict (id) do nothing;

-- ── TEST 91 ────────────────────────────────────────────────────────
-- บุคลากรที่ยังไม่ได้รับมอบหมายบทบาท และไม่ใช่ครูผู้สอน เข้าระบบไม่ได้
--
-- เดิมทุกคนที่เป็นบุคลากรจะได้ teacher โดยอัตโนมัติ แปลว่าบัญชีที่
-- ตั้งค่าไม่ครบเห็นข้อมูลนักศึกษาได้ทันที
do $$
declare v_role text;
begin
  select login_role_for('aaaa0000-0000-0000-0000-0000000000c1',
                        '11111111-1111-1111-1111-111111111111') into v_role;
  if v_role is not null then
    raise exception 'TEST 91 ล้มเหลว: บุคลากรที่ไม่มีบทบาทได้บทบาท % ไปแล้ว', v_role;
  end if;
  raise notice 'TEST 91 ผ่าน — บุคลากรที่ยังไม่ได้รับมอบหมายบทบาทเข้าระบบไม่ได้';
end $$;

-- ── TEST 92 ────────────────────────────────────────────────────────
-- ครูผู้สอนได้บทบาท teacher · นักศึกษาได้ student
do $$
declare v_teacher text; v_student text;
begin
  select login_role_for('aaaa0000-0000-0000-0000-000000000002',
                        '11111111-1111-1111-1111-111111111111') into v_teacher;
  select login_role_for('aaaa0000-0000-0000-0000-000000000001',
                        '11111111-1111-1111-1111-111111111111') into v_student;

  if v_teacher <> 'teacher' then
    raise exception 'TEST 92 ล้มเหลว: ครูผู้สอนควรได้ teacher ได้ %', coalesce(v_teacher, 'ไม่ได้เลย');
  end if;
  if v_student <> 'student' then
    raise exception 'TEST 92 ล้มเหลว: นักศึกษาควรได้ student ได้ %', coalesce(v_student, 'ไม่ได้เลย');
  end if;
  raise notice 'TEST 92 ผ่าน — ครูผู้สอนได้ % · นักศึกษาได้ %', v_teacher, v_student;
end $$;

-- ── TEST 93 ────────────────────────────────────────────────────────
-- มอบหมายบทบาทแล้วบทบาทตอนล็อกอินเปลี่ยนตาม
--
-- นี่คือสิ่งที่ทำให้ registrar, finance และบทบาทอื่นมีตัวตนจริงขึ้นมาได้
do $$
declare v_role text;
begin
  insert into staff_role (staff_id, role, granted_by, reason)
  values ('aaaa0000-0000-0000-0000-0000000000c2', 'registrar',
          'aaaa0000-0000-0000-0000-000000000022', 'หัวหน้างานทะเบียน');

  select login_role_for('aaaa0000-0000-0000-0000-0000000000c1',
                        '11111111-1111-1111-1111-111111111111') into v_role;
  if v_role <> 'registrar' then
    raise exception 'TEST 93 ล้มเหลว: ควรได้ registrar ได้ %', coalesce(v_role, 'ไม่ได้เลย');
  end if;
  raise notice 'TEST 93 ผ่าน — มอบหมายบทบาทแล้วล็อกอินได้เป็น %', v_role;
end $$;

-- ── TEST 94 ────────────────────────────────────────────────────────
-- ถือหลายบทบาทแล้วได้บทบาทที่แรงที่สุด
do $$
declare v_role text;
begin
  insert into staff_role (staff_id, role, reason)
  values ('aaaa0000-0000-0000-0000-0000000000c2', 'director', 'รักษาการผู้อำนวยการ');

  select login_role_for('aaaa0000-0000-0000-0000-0000000000c1',
                        '11111111-1111-1111-1111-111111111111') into v_role;
  if v_role <> 'director' then
    raise exception 'TEST 94 ล้มเหลว: ถือ registrar + director ควรได้ director ได้ %', v_role;
  end if;
  raise notice 'TEST 94 ผ่าน — ถือสองบทบาทได้ตัวที่แรงที่สุดคือ %', v_role;
end $$;

-- ── TEST 95 ────────────────────────────────────────────────────────
-- บทบาทเดิมซ้อนช่วงเวลากันไม่ได้
--
-- ถ้าซ้อนได้ คำถาม "วันนั้นคนนี้มีสิทธิ์ไหม" จะได้หลายคำตอบพร้อมกัน
do $$
begin
  begin
    insert into staff_role (staff_id, role, effective_from)
    values ('aaaa0000-0000-0000-0000-0000000000c2', 'registrar', current_date + 10);
    raise exception 'TEST 95 ล้มเหลว: บทบาทเดิมซ้อนช่วงเวลากันได้';
  exception
    when exclusion_violation then
      raise notice 'TEST 95 ผ่าน — บทบาทเดิมซ้อนช่วงเวลากันไม่ได้';
  end;
end $$;

-- ── TEST 96 ────────────────────────────────────────────────────────
-- ตัดสิทธิ์ทันทีแล้วสิทธิหายเดี๋ยวนั้น แต่ประวัติยังอยู่
--
-- ต้องตัดได้ทันที ไม่ใช่รอถึงพรุ่งนี้ เพราะกรณีที่ต้องใช้จริงคือ
-- พบการใช้สิทธิ์ในทางมิชอบหรือถูกให้ออกจากงาน
do $$
declare v_role text; v_history int;
begin
  -- ตัดสิทธิ์ทันทีด้วย revoked_at ไม่ใช่ effective_to
  -- เพราะบทบาทที่เพิ่งมอบวันนี้ตั้ง effective_to ให้น้อยกว่าวันเริ่มไม่ได้
  update staff_role
     set revoked_at = now(), revoke_reason = 'พ้นวาระรักษาการ'
   where staff_id = 'aaaa0000-0000-0000-0000-0000000000c2' and role = 'director';

  select login_role_for('aaaa0000-0000-0000-0000-0000000000c1',
                        '11111111-1111-1111-1111-111111111111') into v_role;
  select count(*) into v_history from staff_role
   where staff_id = 'aaaa0000-0000-0000-0000-0000000000c2';

  if v_role <> 'registrar' then
    raise exception 'TEST 96 ล้มเหลว: ถอน director แล้วควรเหลือ registrar ได้ %', v_role;
  end if;
  if v_history < 2 then
    raise exception 'TEST 96 ล้มเหลว: ประวัติบทบาทหายไป เหลือ % แถว', v_history;
  end if;
  raise notice 'TEST 96 ผ่าน — ตัดสิทธิ์ director ทันทีแล้วเหลือ % · ประวัติยังอยู่ครบ % แถว', v_role, v_history;
end $$;

-- ── TEST 97 ────────────────────────────────────────────────────────
-- ยกระดับตัวเองเป็น admin ไม่ได้
--
-- ข้อนี้สำคัญที่สุดในชุด — ถ้าบทบาทอื่นเขียน staff_role ได้
-- ใครก็ตามที่มีสิทธิ์เขียนตารางนี้จะยกระดับตัวเองในคำสั่งเดียว
-- แล้วระบบสิทธิทั้งระบบก็ไม่มีความหมาย
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'registrar';
set local app.actor_id = 'aaaa0000-0000-0000-0000-0000000000c1';

do $$
begin
  begin
    insert into staff_role (staff_id, role, reason)
    values ('aaaa0000-0000-0000-0000-0000000000c2', 'admin', 'ยกระดับตัวเอง');
    raise exception 'TEST 97 ล้มเหลว: งานทะเบียนยกระดับตัวเองเป็น admin ได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 97 ผ่าน — บทบาทอื่นมอบหมายสิทธิไม่ได้ ต้องเป็น admin หรือ director';
  end;
end $$;

-- แต่ต้องอ่านได้ เพราะต้องรู้ว่าใครรับผิดชอบอะไร
do $$
declare v int;
begin
  select count(*) into v from staff_role;
  if v = 0 then
    raise exception 'TEST 97b ล้มเหลว: อ่านทะเบียนบทบาทไม่ได้เลย';
  end if;
  raise notice 'TEST 97b ผ่าน — บทบาทอื่นอ่านทะเบียนสิทธิได้ % แถว แต่แก้ไม่ได้', v;
end $$;
commit;

-- ── TEST 98 ────────────────────────────────────────────────────────
-- วิทยาลัยอื่นไม่เห็นทะเบียนสิทธิและบันทึกการเข้าถึง
insert into access_log
  (institution_id, actor_id, actor_role, action, entity, entity_id, subject_id, route)
values
  ('11111111-1111-1111-1111-111111111111',
   'aaaa0000-0000-0000-0000-000000000002', 'teacher', 'read', 'student',
   'aaaa0000-0000-0000-0000-000000000011',
   'aaaa0000-0000-0000-0000-000000000001', 'GET /api/v1/students/:id');

begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_roles int; v_log int;
begin
  select count(*) into v_roles from staff_role;
  select count(*) into v_log   from access_log;
  if v_roles <> 0 or v_log <> 0 then
    raise exception 'TEST 98 ล้มเหลว: วิทยาลัยอื่นเห็นบทบาท % · บันทึกการเข้าถึง %', v_roles, v_log;
  end if;
  raise notice 'TEST 98 ผ่าน — วิทยาลัยอื่นไม่เห็นทะเบียนสิทธิและบันทึกการเข้าถึง';
end $$;
commit;

-- ── TEST 99 ────────────────────────────────────────────────────────
-- เจ้าของข้อมูลดูได้ว่าใครเข้าถึงข้อมูลตน — PDPA มาตรา 30
-- แต่ต้องไม่เห็นของคนอื่น
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';

do $$
declare v_mine int; v_all int;
begin
  select count(*) into v_mine from access_log
   where subject_id = 'aaaa0000-0000-0000-0000-000000000001';
  select count(*) into v_all from access_log;

  if v_mine = 0 then
    raise exception 'TEST 99 ล้มเหลว: เจ้าของข้อมูลดูประวัติการเข้าถึงข้อมูลตนไม่ได้';
  end if;
  if v_all <> v_mine then
    raise exception 'TEST 99 ล้มเหลว: เห็นบันทึกของคนอื่นด้วย (% จาก %)', v_mine, v_all;
  end if;
  raise notice 'TEST 99 ผ่าน — เจ้าของข้อมูลเห็นเฉพาะบันทึกที่เกี่ยวกับตน % รายการ', v_mine;
end $$;
commit;

-- ── TEST 100 ───────────────────────────────────────────────────────
-- บันทึกการเข้าถึงแก้ไม่ได้ และลบของใหม่ไม่ได้แม้เป็น admin
--
-- บันทึกการตรวจสอบที่แก้หรือลบได้ ไม่มีค่าในการตรวจสอบเลย
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'admin';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_before int; v_after int;
begin
  select count(*) into v_before from access_log;

  update access_log set action = 'create' where action = 'read';
  delete from access_log;

  select count(*) into v_after from access_log;

  if v_after <> v_before then
    raise exception 'TEST 100 ล้มเหลว: admin ลบบันทึกการเข้าถึงได้ (% → %)', v_before, v_after;
  end if;
  if exists (select 1 from access_log where action = 'create'
              and route = 'GET /api/v1/students/:id') then
    raise exception 'TEST 100 ล้มเหลว: admin แก้บันทึกการเข้าถึงได้';
  end if;
  raise notice 'TEST 100 ผ่าน — admin แก้และลบบันทึกการเข้าถึงไม่ได้ (เหลือ % รายการเท่าเดิม)', v_after;
end $$;
commit;

-- ── TEST 101 ───────────────────────────────────────────────────────
-- ล้างบันทึกได้เฉพาะที่เกินระยะเก็บ และตั้งต่ำกว่า 90 วันไม่ได้
do $$
declare v_n int;
begin
  begin
    perform purge_access_log(30);
    raise exception 'TEST 101 ล้มเหลว: ตั้งระยะเก็บต่ำกว่า 90 วันได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 101%' then raise; end if;
      null;
  end;

  -- แถวเก่าที่เกินระยะเก็บต้องลบได้
  insert into access_log
    (institution_id, actor_role, action, entity, route, occurred_at)
  values ('11111111-1111-1111-1111-111111111111', 'admin', 'read', 'student',
          'GET /old', now() - interval '200 days');

  select purge_access_log(90) into v_n;
  if v_n < 1 then
    raise exception 'TEST 101 ล้มเหลว: ล้างบันทึกเก่าไม่ได้เลย';
  end if;
  raise notice 'TEST 101 ผ่าน — ตั้งต่ำกว่า 90 วันไม่ได้ · ล้างของเก่าได้ % รายการ', v_n;
end $$;

\echo ''
\echo '════ ทดสอบสิทธิบุคลากรและบันทึกการเข้าถึงครบทุกข้อ ════'

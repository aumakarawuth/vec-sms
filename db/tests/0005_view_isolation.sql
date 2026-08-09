-- ═══════════════════════════════════════════════════════════════════
-- 0005_view_isolation.sql
-- ทดสอบว่า Row-Level Security ทำงานผ่าน view ด้วย ไม่ใช่แค่ตาราง
--
-- เทสต์ชุดนี้เกิดจากช่องโหว่จริงที่พบตอนทดสอบ API — ตารางกันข้ามวิทยาลัย
-- ได้ถูกต้องแต่ทุก view รั่ว เพราะ view รันด้วยสิทธิ์เจ้าของซึ่งเป็น superuser
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_runtime') then
    create role app_runtime nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'rls_probe') then
    create role rls_probe login in role app_runtime;
  end if;
end $$;

grant usage on schema public to app_runtime;
grant select on all tables in schema public to app_runtime;

insert into institution (id, code, name_th)
values ('99999999-9999-9999-9999-999999999999', '1300009999', 'วิทยาลัยสำหรับทดสอบการรั่วของ view')
on conflict (id) do nothing;

-- ── TEST 41 ────────────────────────────────────────────────────────
-- ทุก view ต้องตั้ง security_invoker แล้ว
do $$
declare v_missing text;
begin
  select string_agg(c.relname, ', ') into v_missing
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'v' and n.nspname = 'public'
    and coalesce((select option_value from pg_options_to_table(c.reloptions)
                  where option_name = 'security_invoker'), 'false') <> 'true';

  if v_missing is not null then
    raise exception 'TEST 41 ล้มเหลว: view ที่ยังไม่ได้ตั้ง security_invoker — %', v_missing;
  end if;
  raise notice 'TEST 41 ผ่าน — ทุก view ตั้ง security_invoker แล้ว';
end $$;

-- ── TEST 42 ────────────────────────────────────────────────────────
-- อ่านผ่าน view ด้วยบริบทของวิทยาลัยที่ไม่มีข้อมูล ต้องได้ศูนย์แถวทุก view
begin;
set local role rls_probe;
set local app.institution_id = '99999999-9999-9999-9999-999999999999';
set local app.role = 'registrar';
set local app.actor_id = '99999999-9999-9999-9999-999999999999';

do $$
declare
  v record;
  v_n bigint;
  v_leaks text := '';
begin
  for v in
    select c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'v' and n.nspname = 'public'
      -- มุมมองโครงสร้างหลักสูตรไม่ได้ผูกกับสถานศึกษาโดยตรง จึงยกเว้น
      and c.relname not in ('v_curriculum_structure')
    order by 1
  loop
    execute format('select count(*) from public.%I', v.relname) into v_n;
    if v_n > 0 then
      v_leaks := v_leaks || format('%s=%s ', v.relname, v_n);
    end if;
  end loop;

  if v_leaks <> '' then
    raise exception 'TEST 42 ล้มเหลว: view รั่วข้ามสถานศึกษา — %', v_leaks;
  end if;
  raise notice 'TEST 42 ผ่าน — ไม่มี view ใดรั่วข้ามสถานศึกษา';
end $$;
commit;

-- ── TEST 43 ────────────────────────────────────────────────────────
-- วิทยาลัยของตัวเองต้องยังเห็นข้อมูลผ่าน view ได้ตามปกติ
begin;
set local role rls_probe;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'registrar';
set local app.actor_id = '11111111-1111-1111-1111-111111111111';

do $$
declare v_n bigint;
begin
  select count(*) into v_n from v_student_credits_by_category;
  if v_n = 0 then
    raise exception 'TEST 43 ล้มเหลว: วิทยาลัยตัวเองมองไม่เห็นข้อมูลของตนผ่าน view';
  end if;
  raise notice 'TEST 43 ผ่าน — วิทยาลัยตัวเองยังอ่านผ่าน view ได้ (% แถว)', v_n;
end $$;
commit;

-- ── TEST 44 ────────────────────────────────────────────────────────
-- นักศึกษาต้องเห็นเวลาเรียนของตัวเอง แต่ไม่เห็นของคนอื่น
begin;
set local role rls_probe;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';  -- person ของปิยะพงศ์

do $$
declare v_own bigint; v_all bigint;
begin
  select count(*) into v_own
  from enrollment e
  join student s on s.id = e.student_id
  where s.person_id = 'aaaa0000-0000-0000-0000-000000000001';

  select count(*) into v_all from enrollment;

  if v_own = 0 then
    raise exception 'TEST 44 ล้มเหลว: นักศึกษามองไม่เห็นการลงทะเบียนของตัวเอง';
  end if;
  if v_all <> v_own then
    raise exception 'TEST 44 ล้มเหลว: นักศึกษาเห็นการลงทะเบียนของคนอื่นด้วย (ของตน % จากทั้งหมด %)',
      v_own, v_all;
  end if;
  raise notice 'TEST 44 ผ่าน — นักศึกษาเห็นเฉพาะการลงทะเบียนของตัวเอง % รายการ', v_own;
end $$;
commit;

\echo ''
\echo '════ ทดสอบการแยกข้อมูลผ่าน view ครบทุกข้อ ════'

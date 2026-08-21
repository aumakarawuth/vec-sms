-- ═══════════════════════════════════════════════════════════════════
-- 0054_program_type_write_scope.sql
-- ทดสอบว่า program_type เขียนได้เฉพาะฝ่ายวิชาการ (0074)
--
-- ─── ทำไมต้องยิง SQL ตรง ไม่ใช่ยิงผ่าน API ───
-- program_type ไม่เคยมีเส้นทาง API แตะเลยจนถึงไฟล์นี้ — เหมือน `course`
-- ก่อน 0065 เป๊ะ (ดู 0045_course_catalog_write_scope.sql) การอ่านโค้ด
-- ฝั่ง API ให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้ามกับความจริง
--
-- ─── ต้อง set local role app_runtime เสมอ ───
-- run.sh ต่อด้วย postgres ซึ่งข้าม RLS ทุกกรณีแม้ตารางตั้ง force ไว้
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select pt.id             as pt_id,
       pt.code           as pt_code,
       pt.institution_id as inst_id,
       p.id              as owner_person
  from program_type pt
  join student s on s.institution_id = pt.institution_id
  join person p  on p.id = s.person_id
 order by pt.code
 limit 1 \gset

-- ═══ นักศึกษาแตะหมวดสาขาไม่ได้เลยสักทาง ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',      true) as a,
       set_config('app.actor_id',       :'owner_person', true) as b,
       set_config('app.role',           'student',       true) as c,
       set_config('test.pt_id',         :'pt_id',        true) as d,
       set_config('test.pt_code',       :'pt_code',      true) as e \gset ctx_

do $$
declare n integer; v_code text := current_setting('test.pt_code');
begin
  -- ── TEST 318 แก้ชื่อหมวดสาขาไม่ได้ ──────────────────────────────
  update program_type set name_th = 'ทดสอบ' where id = current_setting('test.pt_id')::uuid;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'TEST 318 ล้มเหลว: นักศึกษาแก้ชื่อหมวดสาขา % ได้ % แถว', v_code, n;
  end if;

  -- ── TEST 319 สร้างหมวดสาขาใหม่ไม่ได้ ────────────────────────────
  begin
    insert into program_type (institution_id, code, name_th)
    values (current_setting('app.institution_id')::uuid, '99', 'หมวดที่ไม่ควรถูกสร้าง');
    raise exception 'TEST 319 ล้มเหลว: นักศึกษาสร้างหมวดสาขาเองได้';
  exception
    when insufficient_privilege then null;   -- ถูกปฏิเสธตามที่ควรเป็น
  end;

  -- ── TEST 320 ลบหมวดสาขาไม่ได้ ───────────────────────────────────
  delete from program_type where id = current_setting('test.pt_id')::uuid;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'TEST 320 ล้มเหลว: นักศึกษาลบหมวดสาขา % ได้', v_code;
  end if;

  -- ── TEST 321 แต่ยัง **อ่าน** รายชื่อหมวดสาขาได้ตามปกติ ──────────
  select count(*) into n from program_type;
  if n = 0 then
    raise exception 'TEST 321 ล้มเหลว: นักศึกษาอ่านหมวดสาขาไม่ได้เลย — ปิดเกินไป';
  end if;

  raise notice 'TEST 318 ผ่าน — นักศึกษาแก้ชื่อหมวดสาขาไม่ได้';
  raise notice 'TEST 319 ผ่าน — นักศึกษาสร้างหมวดสาขาเองไม่ได้';
  raise notice 'TEST 320 ผ่าน — นักศึกษาลบหมวดสาขาไม่ได้';
  raise notice 'TEST 321 ผ่าน — แต่ยังอ่านหมวดสาขาได้ % แถว', n;
end $$;
rollback;

-- ═══ ฝ่ายวิชาการยังสร้าง/แก้/ลบหมวดสาขาได้ตามปกติ ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'owner_person', true) as b,
       set_config('app.role',           'academic',   true) as c \gset ctx2_

do $$
declare n integer; v_name text; v_inst uuid := current_setting('app.institution_id')::uuid;
begin
  insert into program_type (institution_id, code, name_th)
  values (v_inst, 'T54', 'หมวดทดสอบขอบเขตการเขียน');
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'TEST 322 ล้มเหลว: ฝ่ายวิชาการสร้างหมวดสาขาไม่ได้';
  end if;

  update program_type set name_th = 'หมวดทดสอบ (แก้แล้ว)'
   where institution_id = v_inst and code = 'T54';
  select name_th into v_name from program_type
   where institution_id = v_inst and code = 'T54';
  if v_name <> 'หมวดทดสอบ (แก้แล้ว)' then
    raise exception 'TEST 322 ล้มเหลว: ฝ่ายวิชาการแก้ชื่อหมวดสาขาไม่ได้ — ได้ %', v_name;
  end if;

  delete from program_type where institution_id = v_inst and code = 'T54';
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'TEST 322 ล้มเหลว: ฝ่ายวิชาการลบหมวดสาขาที่ไม่มีใครอ้างถึงไม่ได้';
  end if;

  raise notice 'TEST 322 ผ่าน — ฝ่ายวิชาการสร้าง/แก้/ลบหมวดสาขาได้ตามปกติ';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนของหมวดสาขาครบทุกข้อ ════'; end $$;

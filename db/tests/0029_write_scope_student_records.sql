-- ═══════════════════════════════════════════════════════════════════
-- 0029_write_scope_student_records.sql
-- ทดสอบว่านักศึกษาเขียนระเบียนของตัวเองไม่ได้ แต่ยังอ่านได้ครบ
--
-- ─── สิ่งที่ต้องระวังที่สุดในชุดนี้ ───
-- 0045 ปิดการเขียนด้วยการ **เพิ่ม** นโยบาย ไม่ใช่เขียนของเดิมทับ
-- ถ้าเผลอเขียนผิดเป็น `for all` แทน `for insert/update/delete`
-- สิทธิ์ **อ่าน** ของเจ้าของจะหายไปด้วยทั้งสิบห้าตาราง แล้วหน้าจอนักศึกษา
-- จะว่างเปล่าทั้งแอปโดยที่เทสต์ที่ตรวจแค่ "เขียนไม่ได้" ยังผ่านหมด
--
-- TEST 208 จึงตรวจการอ่านเป็นเรื่องหลัก ไม่ใช่ของแถม
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select s.id as sid, s.person_id as pid, s.institution_id as inst
  from student s join enrollment e on e.student_id = s.id limit 1 \gset

-- ── TEST 207 ───────────────────────────────────────────────────────
-- เขียนและลบระเบียนของตัวเองไม่ได้สักตาราง
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst', true) as a,
       set_config('app.actor_id',       :'pid',  true) as b,
       set_config('app.role',           'student', true) as c,
       set_config('test.sid',           :'sid',  true) as d \gset ctx_

do $$
declare
  v_sid uuid := current_setting('test.sid')::uuid;
  v_n   integer;
  v_ok  text[] := '{}';
begin
  -- เทียบโอนให้ตัวเอง — อันตรายที่สุดตั้งแต่ 0044 ทำให้หน่วยกิตเทียบโอน
  -- นับในการตรวจจบ ถ้าเขียนเองได้พร้อม approved_at ก็จบเองได้ทันที
  begin
    insert into prior_academic_record
      (student_id, source_th, course_code, course_name_th, credits,
       grade_symbol, counts_in_gpa, earns_credit, approved_at)
    values (v_sid, 'ปลอม', 'FAKE-1', 'ปลอม', 99, '4', false, true, now());
    v_ok := array_append(v_ok, 'เทียบโอนให้ตัวเอง');
  exception when others then null; end;

  begin
    update student_curriculum set effective_to = null where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'student_curriculum'); end if;
  exception when others then null; end;

  begin
    update student_guardian set can_view_grades = false where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'student_guardian'); end if;
  exception when others then null; end;

  begin
    update enrollment_result set attendance_pct = 100
     where enrollment_id in (select id from enrollment where student_id = v_sid);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'enrollment_result'); end if;
  exception when others then null; end;

  begin
    delete from enrollment_result
     where enrollment_id in (select id from enrollment where student_id = v_sid);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ลบ enrollment_result'); end if;
  exception when others then null; end;

  begin
    delete from issued_document where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ลบเอกสารที่ออกให้'); end if;
  exception when others then null; end;

  begin
    delete from screening_result where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ลบผลคัดกรอง'); end if;
  exception when others then null; end;

  begin
    update student_graduation_status set satisfied = true where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'student_graduation_status'); end if;
  exception when others then null; end;

  if array_length(v_ok, 1) > 0 then
    raise exception 'TEST 207 ล้มเหลว: นักศึกษายังเขียนระเบียนของตัวเองได้ — %',
      array_to_string(v_ok, ' · ');
  end if;

  raise notice 'TEST 207 ผ่าน — เขียนและลบระเบียนของตัวเองไม่ได้สักตาราง';
end $$;
rollback;

-- ── TEST 208 ───────────────────────────────────────────────────────
-- แต่ยังอ่านได้ครบทุกตาราง — ข้อนี้สำคัญกว่าข้อบน
--
-- 0045 เพิ่มนโยบายที่คุมเฉพาะ insert/update/delete ถ้าเผลอเขียนเป็น
-- `for all` สิทธิ์อ่านของเจ้าของจะหายไปด้วย แล้วหน้าจอนักศึกษาจะว่างทั้งแอป
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst', true) as a,
       set_config('app.actor_id',       :'pid',  true) as b,
       set_config('app.role',           'student', true) as c,
       set_config('test.sid',           :'sid',  true) as d \gset ctx_

do $$
declare
  v_sid uuid := current_setting('test.sid')::uuid;
  v_n   integer;
begin
  -- ผลการเรียนของตัวเองต้องอ่านได้ มิฉะนั้นหน้าจอผลการเรียนว่างเปล่า
  select count(*) into v_n from enrollment_result er
   join enrollment e on e.id = er.enrollment_id
   where e.student_id = v_sid;
  if v_n = 0 then
    raise exception 'TEST 208 ล้มเหลว: นักศึกษาอ่านผลการเรียนของตัวเองไม่ได้ '
      '(นโยบายใหม่ปิดสิทธิ์อ่านไปด้วย — ตรวจว่าเขียน for insert/update/delete ครบ)';
  end if;

  -- หลักสูตรของตัวเองต้องอ่านได้ หน้าจอเส้นทางสู่การจบพึ่งข้อนี้
  select count(*) into v_n from student_curriculum where student_id = v_sid;
  if v_n = 0 then
    raise exception 'TEST 208 ล้มเหลว: นักศึกษาอ่านหลักสูตรของตัวเองไม่ได้';
  end if;

  raise notice 'TEST 208 ผ่าน — เจ้าของยังอ่านผลการเรียนและหลักสูตรของตัวเองได้ครบ';
end $$;
rollback;

-- ── TEST 209 ───────────────────────────────────────────────────────
-- งานทะเบียนยังเขียนได้ตามปกติ — ปิดเกินไปคือระบบใช้งานไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst', true) as a,
       set_config('app.actor_id',       :'pid',  true) as b,
       set_config('app.role',           'registrar', true) as c,
       set_config('test.sid',           :'sid',  true) as d \gset ctx_

do $$
declare v_sid uuid := current_setting('test.sid')::uuid; v_n integer;
begin
  insert into prior_academic_record
    (student_id, source_th, course_code, course_name_th, credits,
     grade_symbol, counts_in_gpa, earns_credit, approved_at)
  values (v_sid, 'วิทยาลัยเดิม', 'REG-1', 'งานทะเบียนบันทึก', 3, '3', false, true, now());

  -- เขียนค่าเดิมทับตัวเอง — ทดสอบว่า "เขียนได้" โดยไม่เปลี่ยนข้อมูลจริง
  update student_curriculum set reason = reason where student_id = v_sid;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 209 ล้มเหลว: งานทะเบียนแก้หลักสูตรของนักศึกษาไม่ได้';
  end if;

  raise notice 'TEST 209 ผ่าน — งานทะเบียนยังบันทึกเทียบโอนและแก้หลักสูตรได้';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนระเบียนนักศึกษาครบทุกข้อ ════'; end $$;

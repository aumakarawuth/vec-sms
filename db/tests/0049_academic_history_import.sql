-- ═══════════════════════════════════════════════════════════════════
-- 0049_academic_history_import.sql
-- ทดสอบการนำเข้าประวัติการเรียนเดิมเป็นชุด (import_kind = 'academic_history')
--
-- สร้างนักศึกษาและรายวิชาของตัวเองแทนการยืมรหัสจากไฟล์เทสต์อื่น — เพราะ
-- db/seed/ ไม่มีนักศึกษาเลยสักคน (มีแค่ข้อมูลอ้างอิง) รหัสที่ "มีอยู่จริง"
-- ตอนพัฒนาบนเครื่องมักมาจาก demo-data.sql ซึ่งไม่ได้รันใน db/run.sh
-- ยืมรหัสจากที่นั่นมาเขียนเทสต์แล้วเทสต์จะเขียวเฉพาะบนเครื่องที่เคยรัน
-- demo-reset.sh มาก่อน แต่แดงใน CI ที่รันจากฐานที่สะอาด — อาการเดียวกับ
-- ที่ทำให้ต้องแยกเทสต์ของงานยังไม่ commit ออกจาก repo มาแล้วครั้งหนึ่ง
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare v_inst uuid := '11111111-1111-1111-1111-111111111111'; v_person uuid;
begin
  insert into person (institution_id, prefix_th, first_name_th, last_name_th, gender)
  values (v_inst, 'นางสาว', 'ทดสอบ', 'นำเข้าประวัติเดิม', 'undisclosed')
  returning id into v_person;

  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values (v_inst, v_person, '69ACH0001', 2569);

  insert into course (institution_id, edition_be, code, name_th, credits)
  values (v_inst, 2567, '00700-0001', 'วิชาทดสอบสำหรับผูกประวัติเดิม', 1);

  raise notice 'เตรียมฐาน — นักศึกษา 69ACH0001 และวิชา 00700-0001 สำหรับเทสต์ชุดนี้โดยเฉพาะ';
end $$;

-- ── TEST 297 ───────────────────────────────────────────────────────
-- ตรวจแล้วคืนปัญหาทั้งหมดของแถว ไม่ใช่ข้อแรกที่เจอ
do $$
declare v_errs text[];
begin
  v_errs := validate_academic_history_row(
    '11111111-1111-1111-1111-111111111111',
    '{"student_code":"","credits":"0"}'::jsonb);

  if cardinality(v_errs) < 5 then
    raise exception 'TEST 297 ล้มเหลว: ควรคืนปัญหาอย่างน้อย 5 ข้อ คืน % ข้อ (%)',
      cardinality(v_errs), array_to_string(v_errs, ' · ');
  end if;
  raise notice 'TEST 297 ผ่าน — คืนปัญหาครบ % ข้อในรอบเดียว: %',
    cardinality(v_errs), array_to_string(v_errs, ' · ');
end $$;

-- ── TEST 298 ───────────────────────────────────────────────────────
-- นักศึกษาที่ไม่มีอยู่จริงถูกจับได้ — สลับขั้วกับ validate_student_row
-- ที่ต้องห้ามรหัสซ้ำ ตัวนี้ต้องมีอยู่แล้วเท่านั้น
do $$
declare v_errs text[];
begin
  v_errs := validate_academic_history_row(
    '11111111-1111-1111-1111-111111111111',
    '{"student_code":"ไม่มีรหัสนี้","source_th":"วิทยาลัยเดิม","course_code":"20000-1001",
      "course_name_th":"ภาษาไทยพื้นฐาน","credits":"2","grade_symbol":"3.0"}'::jsonb);

  if not exists (select 1 from unnest(v_errs) e where e like '%ไม่พบนักศึกษา%') then
    raise exception 'TEST 298 ล้มเหลว: รหัสนักศึกษาที่ไม่มีจริงไม่ถูกจับ (%)', array_to_string(v_errs, ' · ');
  end if;
  raise notice 'TEST 298 ผ่าน — รหัสนักศึกษาที่ไม่มีอยู่จริงถูกจับได้';
end $$;

-- ── TEST 299 ───────────────────────────────────────────────────────
-- มีแถวผิดแม้แถวเดียว ต้องไม่เขียนอะไรลงฐานข้อมูลเลย
do $$
declare
  v_batch uuid; v_before int; v_after int;
begin
  select count(*) into v_before from prior_academic_record;

  insert into import_batch (institution_id, kind, source_name, total_rows)
  values ('11111111-1111-1111-1111-111111111111', 'academic_history', 'prior-grades.xlsx', 2)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, '{"student_code":"69ACH0001","source_th":"วิทยาลัยเทคนิคเดิม",
                   "term_label":"2566/1","course_code":"20000-9001",
                   "course_name_th":"วิชาทดสอบ","credits":"2","grade_symbol":"3.0",
                   "grade_point":"3.0","transfer_kind":"transferred_grade"}'::jsonb),
    -- แถวนี้ผิด: ไม่มีหน่วยกิต
    (v_batch, 2, '{"student_code":"69ACH0001","source_th":"วิทยาลัยเทคนิคเดิม",
                   "term_label":"2566/1","course_code":"20000-9002",
                   "course_name_th":"วิชาทดสอบสอง","grade_symbol":"2.5"}'::jsonb);

  begin
    perform apply_academic_history_import(v_batch);
    raise exception 'TEST 299 ล้มเหลว: นำเข้าได้ทั้งที่มีแถวผิด';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 299%' then raise; end if;
      null;
  end;

  select count(*) into v_after from prior_academic_record;
  if v_after <> v_before then
    raise exception 'TEST 299 ล้มเหลว: เขียนประวัติไป % รายการทั้งที่ควรยกเลิกทั้งชุด',
      v_after - v_before;
  end if;

  raise notice 'TEST 299 ผ่าน — มีแถวผิด 1 แถว ไม่เขียนอะไรเลย (ประวัติยังเท่าเดิม % รายการ)', v_after;
end $$;

-- ── TEST 300 ───────────────────────────────────────────────────────
-- แก้แถวที่ผิดแล้วนำเข้าได้ครบ — batch_id ถูกผูกกับทุกแถวที่สร้าง
-- และ mapped_course_code เดิมพันหาแล้วผูก mapped_course_id ให้จริง
do $$
declare v_batch uuid; v_before int; v_after int; v_imported int; v_mapped uuid; v_expect uuid;
begin
  select count(*) into v_before from prior_academic_record;

  select id into v_batch from import_batch
   where source_name = 'prior-grades.xlsx' order by created_at desc limit 1;

  select id into v_expect from course
   where institution_id = '11111111-1111-1111-1111-111111111111' and code = '00700-0001';

  update import_row
     set payload = payload || '{"credits":"2","mapped_course_code":"00700-0001"}'::jsonb
   where batch_id = v_batch and row_no = 2;

  select imported into v_imported from apply_academic_history_import(v_batch);
  select count(*) into v_after from prior_academic_record;

  if v_imported <> 2 or v_after - v_before <> 2 then
    raise exception 'TEST 300 ล้มเหลว: ควรนำเข้า 2 รายการ นำเข้า % และเพิ่มจริง %',
      v_imported, v_after - v_before;
  end if;

  if exists (select 1 from prior_academic_record where batch_id <> v_batch
              and student_id = (select id from student where student_code = '69ACH0001')
              and course_code in ('20000-9001','20000-9002')) then
    raise exception 'TEST 300 ล้มเหลว: มีแถวที่ไม่ได้ผูก batch_id ให้ตามรอยได้';
  end if;

  select mapped_course_id into v_mapped from prior_academic_record
   where course_code = '20000-9002' and batch_id = v_batch;
  if v_mapped is distinct from v_expect then
    raise exception 'TEST 300 ล้มเหลว: mapped_course_code ไม่ได้ถูก resolve เป็น mapped_course_id ที่ถูกต้อง';
  end if;

  raise notice 'TEST 300 ผ่าน — แก้แถวที่ผิดแล้วนำเข้าครบ % รายการ ผูก batch_id และ mapped_course_id ถูกต้อง', v_imported;
end $$;

-- ── TEST 301 ───────────────────────────────────────────────────────
-- ประวัติซ้ำ (นักศึกษาเดิม + วิชาเดิม + ภาคเดิม) ถูกจับตั้งแต่ขั้นตรวจ
do $$
declare v_errs text[];
begin
  v_errs := validate_academic_history_row(
    '11111111-1111-1111-1111-111111111111',
    '{"student_code":"69ACH0001","source_th":"วิทยาลัยเทคนิคเดิม","term_label":"2566/1",
      "course_code":"20000-9001","course_name_th":"วิชาทดสอบ","credits":"2",
      "grade_symbol":"3.0"}'::jsonb);

  if not exists (select 1 from unnest(v_errs) e where e like '%มีประวัติวิชา%อยู่แล้ว%') then
    raise exception 'TEST 301 ล้มเหลว: ประวัติซ้ำไม่ถูกจับ (%)', array_to_string(v_errs, ' · ');
  end if;
  raise notice 'TEST 301 ผ่าน — ประวัติวิชาเดิมในภาคเดิมของนักศึกษาคนเดิมถูกจับได้';
end $$;

-- ── TEST 302 ───────────────────────────────────────────────────────
-- นำเข้าซ้ำรอบเดิมไม่ได้
do $$
declare v_batch uuid;
begin
  select id into v_batch from import_batch
   where source_name = 'prior-grades.xlsx' order by created_at desc limit 1;
  begin
    perform apply_academic_history_import(v_batch);
    raise exception 'TEST 302 ล้มเหลว: นำเข้ารอบเดิมซ้ำได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 302%' then raise; end if;
      raise notice 'TEST 302 ผ่าน — %', sqlerrm;
  end;
end $$;

-- ── TEST 303 ───────────────────────────────────────────────────────
-- บทบาทที่ไม่มีอำนาจสร้างรอบนำเข้าประวัติการเรียนเดิมไม่ได้ — เหมือน TEST 111
-- แต่ตรวจ kind นี้โดยเฉพาะ เพราะเป็น enum คนละค่ากับที่ TEST 111 ยิง
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
begin
  begin
    insert into import_batch (institution_id, kind, total_rows)
    values ('11111111-1111-1111-1111-111111111111', 'academic_history', 1);
    raise exception 'TEST 303 ล้มเหลว: ครูสร้างรอบนำเข้าประวัติการเรียนเดิมได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 303 ผ่าน — ครูนำเข้าประวัติการเรียนเดิมไม่ได้ ต้องเป็นงานทะเบียนขึ้นไป';
  end;
end $$;
commit;

-- ── TEST 304 ───────────────────────────────────────────────────────
-- transfer_kind กำหนด counts_in_gpa ให้ถูกทิศทาง — โอนเกรดมานับ GPA
-- เทียบโอนความรู้/ประสบการณ์ให้แค่หน่วยกิต ไม่มาปนกับ GPA
do $$
declare v_batch uuid; v_grade boolean; v_exp boolean; v_default boolean;
begin
  insert into import_batch (institution_id, kind, source_name, total_rows)
  values ('11111111-1111-1111-1111-111111111111', 'academic_history', 'gpa-kind.xlsx', 3)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, '{"student_code":"69ACH0001","source_th":"ก","term_label":"2565/2",
                   "course_code":"20000-9101","course_name_th":"ก1","credits":"1",
                   "grade_symbol":"3.0","transfer_kind":"transferred_grade"}'::jsonb),
    (v_batch, 2, '{"student_code":"69ACH0001","source_th":"ก","term_label":"2565/2",
                   "course_code":"20000-9102","course_name_th":"ก2","credits":"1",
                   "grade_symbol":"ผ่าน","transfer_kind":"transferred_experience"}'::jsonb),
    (v_batch, 3, '{"student_code":"69ACH0001","source_th":"ก","term_label":"2565/2",
                   "course_code":"20000-9103","course_name_th":"ก3","credits":"1",
                   "grade_symbol":"ผ่าน"}'::jsonb);

  perform apply_academic_history_import(v_batch);

  select counts_in_gpa into v_grade   from prior_academic_record where course_code = '20000-9101';
  select counts_in_gpa into v_exp     from prior_academic_record where course_code = '20000-9102';
  select counts_in_gpa into v_default from prior_academic_record where course_code = '20000-9103';

  if v_grade is not true then
    raise exception 'TEST 304 ล้มเหลว: transferred_grade ควรนับ GPA';
  end if;
  if v_exp is not false then
    raise exception 'TEST 304 ล้มเหลว: transferred_experience ไม่ควรนับ GPA';
  end if;
  if v_default is not false then
    raise exception 'TEST 304 ล้มเหลว: ไม่ระบุ transfer_kind ควรตกเป็น transferred_experience (ไม่นับ GPA)';
  end if;

  raise notice 'TEST 304 ผ่าน — counts_in_gpa ตามทิศทาง transfer_kind ถูกต้องทั้งสามกรณี';
end $$;

\echo ''
\echo '════ ทดสอบการนำเข้าประวัติการเรียนเดิมครบทุกข้อ ════'

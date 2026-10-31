-- ═══════════════════════════════════════════════════════════════════
-- 0057_hr_secretary_working.sql
-- ทดสอบ 0097 — งานบุคคล/เลขาทำงานของตัวเองได้จริง และช่องที่ปิดไปพร้อมกัน
--
-- คู่กับ 0056 (TEST 338–341) ที่เฝ้า "ไม่เกินสิทธิ์" — ไฟล์นี้เพิ่ม "ทำได้จริง"
-- ตามที่คอมเมนต์ของ 0056 สั่งไว้ว่าต้องมีคู่กันเมื่อเปิดสิทธิ์ ไม่ใช่ลบข้อเดิมทิ้ง
--
-- ข้อที่ต้อง "ถูกปฏิเสธ" ใช้ธงบูลีน ไม่ raise ในบล็อกที่ตัวเองดักอยู่
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select s.institution_id as inst_id, s.person_id as stu_person, s.id as stu_id
  from student s order by s.id limit 1 \gset
select st.id as staff_a, st.person_id as person_a from staff st
 where st.institution_id = :'inst_id' order by st.id limit 1 \gset
select st.id as staff_b, st.person_id as person_b from staff st
 where st.institution_id = :'inst_id' and st.id <> :'staff_a' order by st.id limit 1 \gset

select set_config('test.inst', :'inst_id', false) a, set_config('test.staff_a', :'staff_a', false) b,
       set_config('test.person_a', :'person_a', false) c, set_config('test.person_b', :'person_b', false) d,
       set_config('test.staff_b', :'staff_b', false) e \gset ctx_

-- ── TEST 342 ───────────────────────────────────────────────────────
-- นักศึกษาสร้าง/แก้แผนก และลงเวลาทำงานแทนบุคลากรไม่ได้อีกแล้ว
-- (ก่อน 0097 ทำได้ทั้งสามอย่าง — ยิงจริงแล้ว)
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) a, set_config('app.actor_id', :'stu_person', true) b,
       set_config('app.role', 'student', true) c, set_config('app.roles', 'student', true) d \gset ctx_
do $$
declare
  v_dept boolean := false; v_att boolean := false; v_n integer;
begin
  begin
    insert into department (institution_id, code, name_th) values (current_setting('test.inst')::uuid, 'T342', 'แผนกปลอม');
    v_dept := true;
  exception when others then null; end;
  begin
    insert into staff_attendance (institution_id, staff_id, on_date, status)
    values (current_setting('test.inst')::uuid, current_setting('test.staff_a')::uuid, current_date + 500, 'present');
    v_att := true;
  exception when others then null; end;
  update department set name_th = name_th || ' (T342)';
  get diagnostics v_n = row_count;
  if v_dept or v_att or v_n > 0 then
    raise exception 'TEST 342 ล้มเหลว: นักศึกษายังเขียนงานบุคคลได้ แผนก=% ลงเวลา=% แก้แผนก=%', v_dept, v_att, v_n;
  end if;
  raise notice 'TEST 342 ผ่าน — นักศึกษาสร้าง/แก้แผนกและลงเวลาแทนบุคลากรไม่ได้';
end $$;
rollback;

-- ── TEST 343 ───────────────────────────────────────────────────────
-- งานบุคคลทำงานของตัวเองได้จริง — สร้างแผนก · เพิ่มระเบียน ทช.1 ให้คนอื่น ·
-- ลงเวลาทำงาน (0095 เปิดแค่อ่าน)
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) a, set_config('app.actor_id', :'person_b', true) b,
       set_config('app.role', 'hr', true) c, set_config('app.roles', 'hr', true) d \gset ctx_
do $$
begin
  insert into department (institution_id, code, name_th) values (current_setting('test.inst')::uuid, 'T343', 'แผนกทดสอบ 343');
  insert into staff_record (staff_id, kind, title_th, hours)
  values (current_setting('test.staff_a')::uuid, 'training', 'อบรมทดสอบ 343', 6);
  insert into staff_attendance (institution_id, staff_id, on_date, status)
  values (current_setting('test.inst')::uuid, current_setting('test.staff_a')::uuid, current_date + 500, 'present');
  raise notice 'TEST 343 ผ่าน — งานบุคคลสร้างแผนก เพิ่มระเบียน และลงเวลาให้บุคลากรได้';
end $$;
rollback;

-- ── TEST 344 ───────────────────────────────────────────────────────
-- ครูอนุมัติใบลาของตัวเองโดยใส่ชื่อคนอื่นเป็นผู้ตัดสินไม่ได้ · ยกเลิกเองได้
-- (ก่อน 0097 trigger กันแค่ "ผู้ตัดสินต้องไม่ใช่เจ้าของ" จึงปลอมชื่อได้)
-- ═══════════════════════════════════════════════════════════════════
begin;
insert into staff_leave (institution_id, staff_id, kind, from_date, to_date, days, reason, requested_by)
values (:'inst_id', :'staff_a', 'personal', current_date + 600, current_date + 600, 1, 'TEST 344', :'person_a');
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) a, set_config('app.actor_id', :'person_a', true) b,
       set_config('app.role', 'teacher', true) c, set_config('app.roles', 'teacher', true) d \gset ctx_
do $$
declare v_forged boolean := false; v_n integer;
begin
  begin
    update staff_leave set status = 'approved', decided_by = current_setting('test.person_b')::uuid
     where reason = 'TEST 344';
    get diagnostics v_n = row_count;
    v_forged := v_n > 0;
  exception when others then null; end;
  if v_forged then
    raise exception 'TEST 344 ล้มเหลว: ครูอนุมัติใบลาของตัวเองโดยอ้างชื่อผู้อื่นได้';
  end if;
  update staff_leave set status = 'cancelled' where reason = 'TEST 344';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'TEST 344 ล้มเหลว: เจ้าของใบต้องยกเลิกใบของตัวเองได้ ได้ % แถว', v_n;
  end if;
  raise notice 'TEST 344 ผ่าน — ปลอมการอนุมัติไม่ได้ แต่ยกเลิกเองได้';
end $$;
rollback;

-- ── TEST 345 ───────────────────────────────────────────────────────
-- งานบุคคลตัดสินใบลาของคนอื่นได้ (trigger ยังกันการอนุมัติของตัวเองเหมือนเดิม)
-- ═══════════════════════════════════════════════════════════════════
begin;
insert into staff_leave (institution_id, staff_id, kind, from_date, to_date, days, reason, requested_by)
values (:'inst_id', :'staff_a', 'sick', current_date + 610, current_date + 610, 1, 'TEST 345', :'person_a');
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) a, set_config('app.actor_id', :'person_b', true) b,
       set_config('app.role', 'hr', true) c, set_config('app.roles', 'hr', true) d \gset ctx_
do $$
declare v_n integer;
begin
  update staff_leave set status = 'approved', decided_by = current_setting('test.person_b')::uuid
   where reason = 'TEST 345';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'TEST 345 ล้มเหลว: งานบุคคลต้องอนุมัติใบลาของคนอื่นได้ ได้ % แถว', v_n;
  end if;
  raise notice 'TEST 345 ผ่าน — งานบุคคลอนุมัติใบลาได้';
end $$;
rollback;

-- ── TEST 346 ───────────────────────────────────────────────────────
-- เลขาเห็นหนังสือถึงผู้ปกครองที่ออกแล้ว แต่ไม่เห็นใบ รบ. และ insert เองไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
insert into issued_document (institution_id, student_id, kind, doc_no, payload)
values (:'inst_id', :'stu_id', 'conduct_certificate', 'T346-L', '{"t":346}'),
       (:'inst_id', :'stu_id', 'transcript',          'T346-T', '{"t":346}');
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) a, set_config('app.actor_id', :'person_b', true) b,
       set_config('app.role', 'secretary', true) c, set_config('app.roles', 'secretary', true) d \gset ctx_
do $$
declare v_letter integer; v_tr integer; v_forged boolean := false;
begin
  select count(*) into v_letter from issued_document where doc_no = 'T346-L';
  select count(*) into v_tr     from issued_document where doc_no = 'T346-T';
  begin
    insert into issued_document (institution_id, student_id, kind, doc_no, payload)
    select institution_id, student_id, 'conduct_certificate', 'T346-FORGED', '{"forged":true}'
      from issued_document where doc_no = 'T346-L';
    v_forged := true;
  exception when others then null; end;
  if v_letter <> 1 or v_tr <> 0 or v_forged then
    raise exception 'TEST 346 ล้มเหลว: หนังสือ=% (ต้อง 1) ใบ รบ.=% (ต้อง 0) ปลอมได้=%', v_letter, v_tr, v_forged;
  end if;
  raise notice 'TEST 346 ผ่าน — เลขาเปิดหนังสือที่ออกแล้วได้ ไม่เห็นใบ รบ. และปลอมใบรับรองไม่ได้';
end $$;
rollback;

-- ── TEST 347 ───────────────────────────────────────────────────────
-- เลขาที่เป็นครูด้วย (บทบาทหลัก teacher) ยังลงประกาศได้ — 0095 อ่าน
-- current_app_role() ตัวเดียว บทบาทรองจึงหายทุกครั้งที่มีบทบาทหลักอื่นซ้อน
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) a, set_config('app.actor_id', :'person_b', true) b,
       set_config('app.role', 'teacher', true) c, set_config('app.roles', 'teacher,secretary', true) d \gset ctx_
do $$
begin
  insert into announcement (institution_id, title_th, body_th, created_by)
  values (current_setting('test.inst')::uuid, 'ประกาศ TEST 347', 'ทดสอบ', current_setting('test.person_b')::uuid);
  raise notice 'TEST 347 ผ่าน — เลขาที่มีบทบาทหลักเป็นครูลงประกาศได้';
end $$;
rollback;

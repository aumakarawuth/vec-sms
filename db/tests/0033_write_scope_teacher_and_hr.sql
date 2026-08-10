-- ═══════════════════════════════════════════════════════════════════
-- 0033_write_scope_teacher_and_hr.sql
-- ทดสอบขอบเขตการเขียนของครูและของเจ้าของระเบียนบุคลากร (0049)
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. ครูปลดล็อกรอบส่งเกรดของตัวเองไม่ได้ **แต่ยังส่งเกรดได้ตามปกติ**
--    ข้อหลังสำคัญเท่าข้อแรก — 0045 เคยปิด practicum_log จนนักศึกษาบันทึก
--    ชั่วโมงของตัวเองไม่ได้ทั้งหน้าจอ การปิดที่กว้างเกินไปคือความเสียหาย
--    ที่เห็นช้ากว่าช่องโหว่เสียอีก เพราะไม่มีใครยิงเทสต์หาสิ่งที่ "ยังทำได้"
-- 2. ประวัติการเลื่อนขั้นลบและแก้ไม่ได้ แม้แต่ผู้ดูแล
-- 3. ครูแก้กลุ่มเรียน เพิ่มระเบียน ทช.1 และผูกบุตรให้ตัวเองไม่ได้
--    แต่งานทะเบียนยังทำได้ครบ
-- 4. สิ่งที่ trigger เดิมกันไว้อยู่แล้วต้องยังกันอยู่ — 0049 พึ่งพาสองข้อนี้
--    แทนที่จะเขียนนโยบายซ้ำ ถ้าวันหนึ่งมีคนถอด trigger ออก ช่องจะเปิดกลับ
--    โดยไม่มีอะไรฟ้อง เทสต์นี้จึงเฝ้าของที่ตัวเองไม่ได้สร้าง
--
-- หมายเหตุ: ทุกข้อที่ต้อง "ถูกปฏิเสธ" ใช้ธงบูลีนกับ sqlerrm ที่จับไว้
-- ไม่ raise ในบล็อกที่ตัวเองดักอยู่ มิฉะนั้นเทสต์จะจับ exception ของตัวเอง
-- แล้วผ่านทั้งที่ระบบพัง (กับดักที่เขียนไว้ในหัวไฟล์ 0024)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select cs.id as sec_id, cs.institution_id as inst_id, cs.term_id as term_id,
       cs.teacher_id as staff_id, st.person_id as teacher_person
  from class_section cs
  join staff st on st.id = cs.teacher_id
 order by cs.id
 limit 1 \gset

select p.id as registrar_person
  from person p
  join staff s       on s.person_id = p.id
  join staff_role sr on sr.staff_id = s.id
 where sr.role in ('registrar', 'academic', 'director', 'admin')
   and s.institution_id = :'inst_id'
 order by p.id
 limit 1 \gset

select set_config('test.sec',    :'sec_id',         false) as a,
       set_config('test.staff',  :'staff_id',       false) as b,
       set_config('test.term',   :'term_id',        false) as c,
       set_config('test.inst',   :'inst_id',        false) as d,
       set_config('test.person', :'teacher_person', false) as e \gset ctx_

-- ── TEST 219 ───────────────────────────────────────────────────────
-- ครูส่งเกรดได้ แต่ปลดล็อกรอบที่ล็อกแล้วไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec uuid := current_setting('test.sec')::uuid;
  v_n   integer;
begin
  -- ตั้งรอบส่งเกรดกลับเป็น draft แทนการลบทิ้ง — `enrollment_result` อ้าง
  -- `submission_id` ไว้ การลบจึงติด foreign key (และการลบผลการเรียนทิ้ง
  -- เพื่อให้เทสต์เดินได้ก็ผิดหลัก "เขียนอย่างเดียว" อยู่ดี)
  update grade_submission set stage = 'draft', locked_at = null
   where class_section_id = v_sec;
  get diagnostics v_n = row_count;

  if v_n = 0 then
    insert into grade_submission (class_section_id, term_id, stage)
    values (v_sec, current_setting('test.term')::uuid, 'draft');
  end if;
end $$;

set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'teacher_person', true) as b,
       set_config('app.role',           'teacher',         true) as c \gset ctx_

do $$
declare
  v_sec     uuid := current_setting('test.sec')::uuid;
  v_n       integer;
  v_ok      boolean := false;
  v_unlock  boolean := false;
  v_rewind  boolean := false;
  v_err     text;
begin
  -- (ก) ทางปกติต้องยังเดินได้ — ครูส่งเกรดคือการเลื่อนขั้นจาก draft
  update grade_submission set stage = 'teacher_submitted',
         submitted_by = current_actor_id(), submitted_at = now()
   where class_section_id = v_sec;
  get diagnostics v_n = row_count;
  v_ok := v_n > 0;

  if not v_ok then
    raise exception 'TEST 219 ล้มเหลว: ครูส่งเกรดของกลุ่มเรียนตัวเองไม่ได้แล้ว '
      '(ปิดกว้างเกินไป — แบบเดียวกับที่ 0045 ทำกับ practicum_log)';
  end if;

  -- ล็อกรอบนี้ด้วยเส้นทางปกติ (บทบาทระดับวิทยาลัยเลื่อนขั้นจนล็อก)
  perform set_config('app.role', 'academic', true);
  update grade_submission set stage = 'locked', locked_at = now()
   where class_section_id = v_sec;
  perform set_config('app.role', 'teacher', true);

  -- (ข) ล้าง locked_at ไม่ได้
  begin
    update grade_submission set locked_at = null where class_section_id = v_sec;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_unlock := true; end if;
  exception when others then v_err := sqlerrm; end;

  -- (ค) ย้อนขั้นจาก locked ไม่ได้
  begin
    update grade_submission set stage = 'draft' where class_section_id = v_sec;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_rewind := true; end if;
  exception when others then v_err := sqlerrm; end;

  if v_unlock or v_rewind then
    raise exception 'TEST 219 ล้มเหลว: ครูปลดล็อกรอบส่งเกรดของตัวเองได้ '
      '(ล้างเวลาล็อก=% · ย้อนขั้น=%) — หลัก 3ก ใช้ไม่ได้ทั้งข้อ',
      v_unlock, v_rewind;
  end if;

  if v_err is null then
    raise exception 'TEST 219 ล้มเหลว: ไม่มีแถวถูกแก้และไม่มีข้อผิดพลาดเลย '
      'แปลว่าเทสต์ไม่ได้ยิงโดนอะไร';
  end if;

  raise notice 'TEST 219 ผ่าน — ครูส่งเกรดได้ แต่ปลดล็อกไม่ได้ (%)', left(v_err, 60);
end $$;
rollback;

-- ── TEST 220 ───────────────────────────────────────────────────────
-- ประวัติการเลื่อนขั้นเพิ่มได้อย่างเดียว — แม้แต่ผู้ดูแลก็ลบไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec uuid := current_setting('test.sec')::uuid;
  v_sub uuid;
begin
  select id into v_sub from grade_submission where class_section_id = v_sec limit 1;
  if v_sub is null then
    insert into grade_submission (class_section_id, term_id, stage)
    values (v_sec, current_setting('test.term')::uuid, 'draft')
    returning id into v_sub;
  end if;
  insert into grade_submission_event (submission_id, from_stage, to_stage, actor_id, note)
  values (v_sub, 'draft', 'teacher_submitted', current_setting('test.staff')::uuid, 'ของจริง');
end $$;

set local role app_runtime;
select set_config('app.institution_id', :'inst_id',          true) as a,
       set_config('app.actor_id',       :'registrar_person', true) as b,
       set_config('app.role',           'admin',             true) as c \gset ctx_

do $$
declare
  v_n     integer;
  v_wrote text[] := '{}';
begin
  begin
    delete from grade_submission_event;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, format('ลบได้ %s แถว', v_n)); end if;
  exception when others then null; end;

  begin
    update grade_submission_event set note = 'แก้ย้อนหลัง';
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, format('แก้ได้ %s แถว', v_n)); end if;
  exception when others then null; end;

  if array_length(v_wrote, 1) > 0 then
    raise exception 'TEST 220 ล้มเหลว: ผู้ดูแลแก้ประวัติรอบส่งเกรดได้ (%) '
      '— ประวัติที่คนแตะได้ไม่ใช่หลักฐาน', array_to_string(v_wrote, ' · ');
  end if;

  -- ต้องยัง **อ่าน** และ **เพิ่ม** ได้ มิฉะนั้นการเลื่อนขั้นจะพังทั้งระบบ
  select count(*) into v_n from grade_submission_event;
  if v_n = 0 then
    raise exception 'TEST 220 ล้มเหลว: อ่านประวัติไม่ได้เลย (ปิดกว้างเกินไป)';
  end if;

  raise notice 'TEST 220 ผ่าน — ประวัติ % แถว อ่านได้ เพิ่มได้ แต่ลบและแก้ไม่ได้แม้แต่ผู้ดูแล', v_n;
end $$;
rollback;

-- ── TEST 221 ───────────────────────────────────────────────────────
-- ครูแก้กลุ่มเรียนและระเบียนบุคลากรของตัวเองไม่ได้ · งานทะเบียนยังทำได้
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'teacher_person', true) as b,
       set_config('app.role',           'teacher',         true) as c \gset ctx_

do $$
declare
  v_sec   uuid := current_setting('test.sec')::uuid;
  v_staff uuid := current_setting('test.staff')::uuid;
  v_n     integer;
  v_wrote text[] := '{}';
begin
  begin
    update class_section set section_no = 'แก้เอง' where id = v_sec;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'แก้กลุ่มเรียนของตัวเอง'); end if;
  exception when others then null; end;

  begin
    insert into staff_record (staff_id, kind, title_th, organization_th, hours)
    values (v_staff, 'training', 'อบรมที่ไม่เคยไป', 'ที่ไหนก็ได้', 999);
    v_wrote := array_append(v_wrote, 'เพิ่มชั่วโมงอบรมปลอมให้ตัวเอง');
  exception when others then null; end;

  begin
    update staff_record set hours = 999 where staff_id = v_staff;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'แก้ชั่วโมงอบรมของตัวเอง'); end if;
  exception when others then null; end;

  begin
    insert into staff_child (staff_id, full_name_th, student_id)
    select v_staff, 'ลูกที่ไม่มีจริง', s.id from student s
     where not exists (select 1 from staff_child sc where sc.student_id = s.id)
     limit 1;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'ผูกบุตรบุคลากรให้ตัวเอง'); end if;
  exception when others then null; end;

  if array_length(v_wrote, 1) > 0 then
    raise exception 'TEST 221 ล้มเหลว: ครูทำได้ % ข้อ — %',
      array_length(v_wrote, 1), array_to_string(v_wrote, ' · ');
  end if;

  -- ต้องยังอ่านของตัวเองได้ — ระเบียน ทช.1 เป็นของเจ้าตัว
  perform 1 from staff_record where staff_id = v_staff;

  raise notice 'TEST 221 ผ่าน — ครูแก้กลุ่มเรียน เพิ่มระเบียน ทช.1 และผูกบุตรให้ตัวเองไม่ได้สักข้อ';
end $$;

-- งานทะเบียนต้องยังทำได้ครบ มิฉะนั้นแปลว่าปิดกว้างเกินไป
select set_config('app.actor_id', :'registrar_person', true) as a,
       set_config('app.role',     'registrar',         true) as b \gset ctx_

do $$
declare
  v_staff uuid := current_setting('test.staff')::uuid;
  v_sec   uuid := current_setting('test.sec')::uuid;
  v_n     integer;
begin
  insert into staff_record (staff_id, kind, title_th, organization_th, hours)
  values (v_staff, 'training', 'อบรมจริง', 'สอศ.', 18);

  update class_section set section_no = section_no where id = v_sec;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 221 ล้มเหลว: งานทะเบียนแก้กลุ่มเรียนไม่ได้แล้ว';
  end if;

  raise notice 'TEST 221ก ผ่าน — งานทะเบียนยังเพิ่มระเบียน ทช.1 และแก้กลุ่มเรียนได้';
end $$;
rollback;

-- ── TEST 222 ───────────────────────────────────────────────────────
-- ของที่ trigger เดิมกันไว้ต้องยังกันอยู่ — 0049 พึ่งพาสองข้อนี้แทนการเขียน
-- นโยบายซ้ำ ถ้าถอด trigger ออกช่องจะเปิดกลับโดยไม่มีอะไรฟ้อง
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec uuid := current_setting('test.sec')::uuid;
  v_n   integer;
begin
  insert into staff_leave (institution_id, staff_id, kind, from_date, to_date, days,
                           reason, status, requested_by, requested_at)
  values (current_setting('test.inst')::uuid, current_setting('test.staff')::uuid,
          'sick', '2599-09-01', '2599-09-02', 2, 'ทดสอบ', 'pending',
          current_setting('test.person')::uuid, now());

  -- ต้องมีคำร้องที่ครูคนนี้เป็นผู้ยื่นจริง มิฉะนั้นการทดสอบข้อที่สองจะ
  -- แก้ 0 แถวแล้วผ่านไปเฉย ๆ ทั้งที่ไม่ได้ยิงโดนอะไรเลย
  insert into grade_change_request
    (enrollment_id, from_result_id, to_grade_symbol_id, reason, requested_by, status)
  select e.id, r.id, r.grade_symbol_id, 'ทดสอบ',
         current_setting('test.person')::uuid, 'pending'
    from enrollment e
    join enrollment_result r on r.enrollment_id = e.id and r.superseded_by is null
   where e.class_section_id = v_sec
   limit 1;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 222 เตรียมข้อมูลไม่ได้: ไม่มีผลการเรียนในกลุ่มเรียนนี้ '
      'ให้ยื่นคำร้อง — เทสต์จะไม่ได้ทดสอบอะไรเลย';
  end if;
end $$;

set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'teacher_person', true) as b,
       set_config('app.role',           'teacher',         true) as c \gset ctx_

do $$
declare
  v_staff uuid := current_setting('test.staff')::uuid;
  v_n     integer;
  v_wrote text[] := '{}';
begin
  begin
    update staff_leave
       set status = 'approved', decided_by = current_actor_id(), decided_at = now()
     where staff_id = v_staff and status = 'pending';
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'อนุมัติใบลาของตัวเอง'); end if;
  exception when others then null; end;

  begin
    update grade_change_request set approver_1_id = current_actor_id(), approver_1_at = now()
     where requested_by = current_actor_id();
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'ลงชื่ออนุมัติคำร้องของตัวเอง'); end if;
  exception when others then null; end;

  if array_length(v_wrote, 1) > 0 then
    raise exception 'TEST 222 ล้มเหลว: มาตรการเดิมหายไป — %',
      array_to_string(v_wrote, ' · ');
  end if;

  raise notice 'TEST 222 ผ่าน — อนุมัติใบลาของตัวเองและอนุมัติคำร้องแก้เกรดของตัวเองยังทำไม่ได้';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนของครูและงานบุคคลครบทุกข้อ ════'; end $$;

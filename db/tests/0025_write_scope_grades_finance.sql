-- ═══════════════════════════════════════════════════════════════════
-- 0025_write_scope_grades_finance.sql
-- ทดสอบว่านักศึกษาเขียนคะแนน เกรด สถานะ และหนี้ของตัวเองไม่ได้
--
-- ─── ทำไมต้องมีชุดนี้ ───
-- ทั้งเจ็ดช่องข้างล่างนี้เปิดอยู่จริงและยิงสำเร็จจริง ไม่ใช่ความเสี่ยง
-- เชิงทฤษฎี — ทดสอบด้วยการ update จริงก่อนเขียน 0041 แล้วทุกคำสั่งผ่าน
--
-- อาการแบบนี้มองไม่เห็นจากการอ่านโค้ดชั้น API เลย เพราะชั้นนั้นไม่มี
-- endpoint ให้เรียกด้วยซ้ำ สิ่งที่เปิดช่องคือกฎในฐานข้อมูลที่เขียน
-- `using` ไว้แต่ไม่เขียน `with check`
--
-- ─── สามอย่างที่ชุดนี้จับ ───
-- 1. เจ้าของยัง **อ่าน** ของตัวเองได้ (ถ้าปิดหมดคือหน้าจอนักศึกษาพัง)
-- 2. เจ้าของ **เขียนและลบ** ไม่ได้ ทั้ง update และ delete
--    (delete ต้องทดสอบแยกเสมอ เพราะ with check ไม่มีผลกับ delete)
-- 3. คนที่ต้องเขียนได้จริงยังเขียนได้ — ครูกรอกคะแนน งานทะเบียนแก้สถานะ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── หาเป้าหมายก่อนสลับบทบาท (ยังเป็น superuser จึงเห็นทุกแถว) ────────
--
-- ต้องหาทุกค่าตรงนี้ให้ครบ ห้ามไปหาหลัง `set local role app_runtime`
-- เพราะตอนนั้น RLS กรองตามบริบทที่ยังไม่ได้ตั้ง แล้วได้ศูนย์แถวเสมอ
-- (\gset จะล้มด้วย "no rows returned" ซึ่งดูเหมือนข้อมูลไม่มี ทั้งที่มี)
select s.id             as sid,
       s.person_id      as person_id,
       s.institution_id as inst_id
  from student s
  join enrollment e on e.student_id = s.id
 limit 1 \gset

select gs.id             as score_id,
       st.person_id      as teacher_person,
       cs.institution_id as t_inst
  from gradebook_score gs
  join gradebook_item gi on gi.id = gs.gradebook_item_id
  join class_section cs  on cs.id = gi.class_section_id
  join staff st          on st.id = cs.teacher_id
 limit 1 \gset

-- ── TEST 193 ───────────────────────────────────────────────────────
-- นักศึกษาเขียนของตัวเองไม่ได้สักตาราง แต่ยังอ่านได้ทุกตาราง
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'student',    true) as c,
       set_config('test.sid',           :'sid',       true) as d \gset ctx_

do $$
declare
  v_sid    uuid := current_setting('test.sid')::uuid;
  v_n      integer;
  v_wrote  text[] := '{}';
  v_seen   integer;
begin
  -- ── 1. ต้องยังอ่านของตัวเองได้ ────────────────────────────────
  select count(*) into v_seen from invoice where student_id = v_sid;
  if v_seen = 0 then
    raise exception 'TEST 193 ล้มเหลว: นักศึกษาอ่านใบแจ้งหนี้ของตัวเองไม่ได้ '
      '(ปิดเกินไปจนหน้าจอยอดค้างชำระใช้ไม่ได้)';
  end if;

  -- ── 2. เขียนไม่ได้สักตาราง ────────────────────────────────────
  --
  -- นับ row_count แทนการดักข้อผิดพลาด เพราะ RLS ปฏิเสธได้สองแบบ —
  -- โยน insufficient_privilege หรือกรองแถวออกเงียบ ๆ ทั้งสองแบบถือว่า
  -- ปิดสำเร็จ สิ่งที่ผิดคือ "แก้ได้จริง" ซึ่งเห็นจาก row_count > 0
  begin
    update gradebook_score set score = 100
     where enrollment_id in (select id from enrollment where student_id = v_sid);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'gradebook_score'); end if;
  exception when insufficient_privilege then null; end;

  begin
    update term_summary set gpa = 4.00 where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'term_summary'); end if;
  exception when insufficient_privilege then null; end;

  begin
    update student set status = 'graduated' where id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'student'); end if;
  exception when insufficient_privilege then null; end;

  begin
    update invoice set status = 'paid' where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'invoice'); end if;
  exception when insufficient_privilege then null; end;

  begin
    update installment set due_on = current_date + 365
     where invoice_id in (select id from invoice where student_id = v_sid);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'installment'); end if;
  exception when insufficient_privilege then null; end;

  begin
    update invoice_line set amount = 0
     where invoice_id in (select id from invoice where student_id = v_sid);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'invoice_line'); end if;
  exception when insufficient_privilege then null; end;

  begin
    update enrollment set status = 'enrolled' where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'enrollment'); end if;
  exception when insufficient_privilege then null; end;

  if array_length(v_wrote, 1) > 0 then
    raise exception 'TEST 193 ล้มเหลว: นักศึกษายังเขียนของตัวเองได้ — % '
      '(คะแนนและเกรดที่เจ้าของแก้เองได้ทำให้ผลการเรียนทั้งระบบเชื่อถือไม่ได้)',
      array_to_string(v_wrote, ', ');
  end if;

  raise notice 'TEST 193 ผ่าน — เจ้าของอ่านได้ (ใบแจ้งหนี้ % ใบ) แต่เขียนไม่ได้สักตาราง', v_seen;
end $$;
rollback;

-- ── TEST 194 ───────────────────────────────────────────────────────
-- ลบก็ต้องไม่ได้ — with check ไม่มีผลกับ delete จึงต้องมีนโยบายแยก
--
-- ใบแจ้งหนี้ที่หายไปคือหนี้ที่หายไป และคะแนนที่หายไปคือคะแนนที่ไม่เคยมี
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'student',    true) as c,
       set_config('test.sid',           :'sid',       true) as d \gset ctx_

do $$
declare
  v_sid     uuid := current_setting('test.sid')::uuid;
  v_n       integer;
  v_deleted text[] := '{}';
begin
  begin
    delete from invoice where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_deleted := array_append(v_deleted, 'invoice'); end if;
  exception when insufficient_privilege then null; end;

  begin
    delete from gradebook_score
     where enrollment_id in (select id from enrollment where student_id = v_sid);
    get diagnostics v_n = row_count;
    if v_n > 0 then v_deleted := array_append(v_deleted, 'gradebook_score'); end if;
  exception when insufficient_privilege then null; end;

  begin
    delete from student_status_history where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_deleted := array_append(v_deleted, 'student_status_history'); end if;
  exception when insufficient_privilege then null; end;

  begin
    delete from term_summary where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_deleted := array_append(v_deleted, 'term_summary'); end if;
  exception when insufficient_privilege then null; end;

  begin
    delete from enrollment where student_id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_deleted := array_append(v_deleted, 'enrollment'); end if;
  exception when insufficient_privilege then null; end;

  if array_length(v_deleted, 1) > 0 then
    raise exception 'TEST 194 ล้มเหลว: นักศึกษาลบของตัวเองได้ — %', array_to_string(v_deleted, ', ');
  end if;

  raise notice 'TEST 194 ผ่าน — ลบไม่ได้สักตาราง (with check ไม่มีผลกับ delete จึงมีนโยบายแยก)';
end $$;
rollback;

-- ── TEST 195 ───────────────────────────────────────────────────────
-- คนที่ต้องเขียนได้จริงยังเขียนได้ — ปิดเกินไปคือระบบใช้งานไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'t_inst',         true) as a,
       set_config('app.actor_id',       :'teacher_person', true) as b,
       set_config('app.role',           'teacher',         true) as c,
       set_config('test.score_id',      :'score_id',       true) as d \gset ctx_

do $$
declare v_n integer;
begin
  update gradebook_score set score = score
   where id = current_setting('test.score_id')::uuid;
  get diagnostics v_n = row_count;

  if v_n = 0 then
    raise exception 'TEST 195 ล้มเหลว: ครูผู้สอนกรอกคะแนนของห้องตัวเองไม่ได้ '
      '(ปิดเกินไปจนงานหลักของครูทำไม่ได้)';
  end if;

  raise notice 'TEST 195 ผ่าน — ครูผู้สอนยังกรอกคะแนนของห้องตัวเองได้';
end $$;
rollback;

-- ── TEST 195ก ──────────────────────────────────────────────────────
-- งานทะเบียนยังแก้สถานะนักศึกษาและงานการเงินยังแก้ใบแจ้งหนี้ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'registrar',  true) as c,
       set_config('test.sid',           :'sid',       true) as d \gset ctx_

do $$
declare v_sid uuid := current_setting('test.sid')::uuid; v_n integer;
begin
  update student set status = status where id = v_sid;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 195ก ล้มเหลว: งานทะเบียนแก้ทะเบียนนักศึกษาไม่ได้';
  end if;

  perform set_config('app.role', 'finance', true);
  -- เขียนค่าเดิมทับตัวเอง — ทดสอบว่า "เขียนได้" โดยไม่เปลี่ยนข้อมูลจริง
  update invoice set ref1 = ref1 where student_id = v_sid;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 195ก ล้มเหลว: งานการเงินแก้ใบแจ้งหนี้ไม่ได้';
  end if;

  raise notice 'TEST 195ก ผ่าน — งานทะเบียนและงานการเงินยังทำงานได้ตามปกติ';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนคะแนน เกรด และการเงินครบทุกข้อ ════'; end $$;

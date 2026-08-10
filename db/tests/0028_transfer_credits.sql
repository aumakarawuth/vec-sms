-- ═══════════════════════════════════════════════════════════════════
-- 0028_transfer_credits.sql
-- ทดสอบว่าการตรวจจบนับหน่วยกิตเทียบโอน
--
-- ─── ทำไมต้องมี ───
-- เดิมนักศึกษาเทียบโอนเห็นหน้าจอ "เส้นทางสู่การจบ" ว่ายังขาดอีกหลายสิบ
-- หน่วยกิตทั้งที่งานทะเบียนอนุมัติให้แล้ว แล้วงานทะเบียนต้องอนุมัติจบ
-- ด้วยมือโดยข้ามผลการตรวจ — ซึ่งแปลว่ากฎการจบทั้งชุดไม่ได้ถูกใช้กับ
-- คนกลุ่มนี้เลยสักข้อ
--
-- ─── สิ่งที่ต้องไม่หลุด ───
-- ระเบียนที่ยัง **ไม่อนุมัติ** ต้องไม่ถูกนับ มิฉะนั้นผู้สมัครกรอกหน่วยกิต
-- ให้ตัวเองจนจบได้ (TEST 204)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select s.id as sid, s.institution_id as inst_id
  from student s
  join student_curriculum sc on sc.student_id = s.id and sc.effective_to is null
 limit 1 \gset

-- ฝากค่าไว้ใน GUC ระดับ session (is_local = false) เพราะ psql ไม่แทนค่า
-- ตัวแปรใน dollar-quoted block และแต่ละเทสต์อยู่คนละทรานแซกชัน
select set_config('test.sid', :'sid', false) as x \gset ctx_

-- ── TEST 203 ───────────────────────────────────────────────────────
-- หน่วยกิตเทียบโอนที่อนุมัติแล้วถูกนับในกฎหน่วยกิตรวม
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sid    uuid := current_setting('test.sid')::uuid;
  v_before numeric;
  v_after  numeric;
begin
  select achieved into v_before
    from evaluate_graduation(v_sid) where kind = 'credits_total';

  insert into prior_academic_record
    (student_id, source_th, course_code, course_name_th, credits,
     grade_symbol, counts_in_gpa, earns_credit, approved_at)
  values (v_sid, 'วิทยาลัยเดิม', 'PRIOR-101', 'วิชาที่เทียบโอนมา', 6,
          '3', false, true, now());

  select achieved into v_after
    from evaluate_graduation(v_sid) where kind = 'credits_total';

  if v_after is null then
    raise notice 'TEST 203 ข้าม — หลักสูตรนี้ไม่มีกฎหน่วยกิตรวม';
    return;
  end if;

  if v_after <> coalesce(v_before, 0) + 6 then
    raise exception 'TEST 203 ล้มเหลว: หน่วยกิตรวมไม่ขยับตามที่เทียบโอน (% → % ควรได้ %)',
      v_before, v_after, coalesce(v_before, 0) + 6;
  end if;

  raise notice 'TEST 203 ผ่าน — หน่วยกิตเทียบโอน 6 หน่วยถูกนับ (% → %)', v_before, v_after;
end $$;
rollback;

-- ── TEST 204 ───────────────────────────────────────────────────────
-- ระเบียนที่ยังไม่อนุมัติต้องไม่ถูกนับ
--
-- prior_academic_record เขียนตอนนำเข้าข้อมูลหรือตอนรับเข้า ซึ่งเป็น
-- "สิ่งที่ผู้สมัครแจ้งมา" ไม่ใช่ "สิ่งที่วิทยาลัยรับรอง"
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sid    uuid := current_setting('test.sid')::uuid;
  v_before numeric;
  v_after  numeric;
begin
  select achieved into v_before
    from evaluate_graduation(v_sid) where kind = 'credits_total';

  insert into prior_academic_record
    (student_id, source_th, course_code, course_name_th, credits,
     grade_symbol, counts_in_gpa, earns_credit, approved_at)
  values (v_sid, 'วิทยาลัยเดิม', 'PRIOR-999', 'ยังไม่อนุมัติ', 99,
          '4', false, true, null);

  select achieved into v_after
    from evaluate_graduation(v_sid) where kind = 'credits_total';

  if v_before is null then
    raise notice 'TEST 204 ข้าม — หลักสูตรนี้ไม่มีกฎหน่วยกิตรวม';
    return;
  end if;

  if v_after <> v_before then
    raise exception 'TEST 204 ล้มเหลว: นับหน่วยกิตที่ยังไม่อนุมัติ (% → %) '
      '(ผู้สมัครกรอกหน่วยกิตให้ตัวเองจนจบได้)', v_before, v_after;
  end if;

  raise notice 'TEST 204 ผ่าน — ระเบียนที่ยังไม่อนุมัติไม่ถูกนับ';
end $$;
rollback;

-- ── TEST 205 ───────────────────────────────────────────────────────
-- รายวิชาบังคับที่เทียบโอนมาแล้วต้องไม่นับว่ายังขาด
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sid     uuid := current_setting('test.sid')::uuid;
  v_cv      uuid;
  v_course  uuid;
  v_before  numeric;
  v_after   numeric;
begin
  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = v_sid and sc.effective_to is null;

  select achieved into v_before
    from evaluate_graduation(v_sid) where kind = 'required_courses';

  if v_before is null or v_before = 0 then
    raise notice 'TEST 205 ข้าม — ไม่มีรายวิชาบังคับที่ยังขาดให้ทดสอบ';
    return;
  end if;

  -- หยิบรายวิชาบังคับที่ยังขาดมาหนึ่งวิชาแล้วเทียบโอนให้
  select cc.course_id into v_course
    from curriculum_course cc
   where cc.curriculum_version_id = v_cv
     and cc.requirement = 'required'
     and not exists (select 1 from v_student_course_credit v
                      where v.student_id = v_sid and v.course_id = cc.course_id
                        and v.earns_credit)
   limit 1;

  insert into prior_academic_record
    (student_id, source_th, course_code, course_name_th, credits,
     grade_symbol, counts_in_gpa, earns_credit, mapped_course_id, approved_at)
  values (v_sid, 'วิทยาลัยเดิม', 'PRIOR-REQ', 'วิชาบังคับที่เทียบโอน', 3,
          '3', false, true, v_course, now());

  select achieved into v_after
    from evaluate_graduation(v_sid) where kind = 'required_courses';

  if v_after <> v_before - 1 then
    raise exception 'TEST 205 ล้มเหลว: วิชาบังคับที่เทียบโอนแล้วยังนับว่าขาด (% → % ควรได้ %)',
      v_before, v_after, v_before - 1;
  end if;

  raise notice 'TEST 205 ผ่าน — วิชาบังคับที่เทียบโอนแล้วไม่นับว่าขาด (% → %)', v_before, v_after;
end $$;
rollback;

-- ── TEST 206 ───────────────────────────────────────────────────────
-- GPAX ต้องไม่ขยับตามเกรดเทียบโอน — หน่วยกิตโอนได้แต่เกรดไม่โอน
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sid    uuid := current_setting('test.sid')::uuid;
  v_before numeric;
  v_after  numeric;
begin
  select achieved into v_before
    from evaluate_graduation(v_sid) where kind = 'gpax_min';

  insert into prior_academic_record
    (student_id, source_th, course_code, course_name_th, credits,
     grade_symbol, grade_point, counts_in_gpa, earns_credit, approved_at)
  values (v_sid, 'วิทยาลัยเดิม', 'PRIOR-GPA', 'เกรดสี่เต็ม', 30,
          '4', 4.00, false, true, now());

  select achieved into v_after
    from evaluate_graduation(v_sid) where kind = 'gpax_min';

  if v_before is null then
    raise notice 'TEST 206 ข้าม — หลักสูตรนี้ไม่มีกฎ GPAX';
    return;
  end if;

  if v_after is distinct from v_before then
    raise exception 'TEST 206 ล้มเหลว: GPAX ขยับตามเกรดเทียบโอน (% → %) '
      '(คนเทียบโอนจะคำนวณ GPAX คนละสูตรกับคนอื่น)', v_before, v_after;
  end if;

  raise notice 'TEST 206 ผ่าน — GPAX ไม่ขยับตามเกรดเทียบโอน (%)', v_after;
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบหน่วยกิตเทียบโอนครบทุกข้อ ════'; end $$;

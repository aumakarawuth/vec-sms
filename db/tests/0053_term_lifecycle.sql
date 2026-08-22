-- ═══════════════════════════════════════════════════════════════════
-- 0053_term_lifecycle.sql — ทดสอบลำดับสถานะภาคเรียน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare v_inst uuid := '11111111-1111-1111-1111-111111111111'; v_ay uuid;
begin
  insert into academic_year (institution_id, year_be, starts_on, ends_on)
  values (v_inst, 2599, '2599-05-01', '2600-03-31')
  returning id into v_ay;
  insert into term (id, academic_year_id, ordinal, starts_on, ends_on)
  values ('99999999-0000-0000-0000-000000000001', v_ay, 1, '2599-05-11', '2599-09-30');
  raise notice 'เตรียมฐาน — ปีการศึกษา 2599 ภาคเรียนที่ 1 (id ลงท้าย ...0001) สถานะเริ่มต้น planning';
end $$;

-- ผลการเรียนหนึ่งรายการในภาคเรียนนี้ — เพื่อพิสูจน์ใน TEST 335 ว่าปิดภาคเรียน
-- แล้ว term_summary ได้ค่าจริงจากข้อมูลจริง ไม่ใช่แค่ไม่ error โดยไม่มีอะไรให้คำนวณ
do $$
declare
  v_section     uuid := '99990000-0000-0000-0000-000000000001';
  v_enroll      uuid := '99990000-0000-0000-0000-0000000000e1';
  v_grade_id    uuid;
  v_grade_point numeric;
begin
  select id, grade_point into v_grade_id, v_grade_point
    from grade_symbol where counts_in_gpa order by grade_point desc nulls last limit 1;

  insert into class_section
    (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
     teacher_id, capacity, attendance_policy_id, planned_periods)
  select v_section, cs.institution_id, '99999999-0000-0000-0000-000000000001',
         cs.course_id, cs.curriculum_version_id, '99/99',
         cs.teacher_id, 30, cs.attendance_policy_id, 2
    from class_section cs where cs.id = 'bbbb0000-0000-0000-0000-000000000001'
  on conflict (id) do nothing;

  insert into enrollment (id, student_id, class_section_id, term_id, status, counts_toward_gpa)
  values (v_enroll, 'aaaa0000-0000-0000-0000-000000000011', v_section,
          '99999999-0000-0000-0000-000000000001', 'enrolled', true)
  on conflict (id) do nothing;

  insert into enrollment_result (enrollment_id, grade_symbol_id, grade_point, credits_earned)
  select v_enroll, v_grade_id, v_grade_point, co.credits
    from class_section cs join course co on co.id = cs.course_id
   where cs.id = v_section
  on conflict (enrollment_id, revision) do nothing;
end $$;

-- ── TEST 314 ───────────────────────────────────────────────────────
-- ข้ามขั้นตอนไม่ได้ — planning ไป open ตรง ๆ ต้องถูกปฏิเสธ
do $$
begin
  begin
    perform advance_term_status('99999999-0000-0000-0000-000000000001', 'open');
    raise exception 'TEST 314 ล้มเหลว: ข้ามจาก planning ไป open ตรง ๆ ได้';
  exception
    when raise_exception then
      raise notice 'TEST 314 ผ่าน — ข้ามขั้นตอนจาก planning ไป open ถูกปฏิเสธ';
  end;
end $$;

-- ── TEST 315 ───────────────────────────────────────────────────────
-- เดินหน้าทีละขั้นได้ครบ planning → registration → open → grading → closed
do $$
declare v_status term_status;
begin
  perform advance_term_status('99999999-0000-0000-0000-000000000001', 'registration');
  perform advance_term_status('99999999-0000-0000-0000-000000000001', 'open');
  perform advance_term_status('99999999-0000-0000-0000-000000000001', 'grading');
  select status into v_status from advance_term_status('99999999-0000-0000-0000-000000000001', 'closed');
  if v_status <> 'closed' then
    raise exception 'TEST 315 ล้มเหลว: สถานะสุดท้ายควรเป็น closed ได้ %', v_status;
  end if;
  raise notice 'TEST 315 ผ่าน — เดินครบ planning → registration → open → grading → closed';
end $$;

-- ── TEST 316 ───────────────────────────────────────────────────────
-- closed แล้วเดินต่อไม่ได้อีกเลย แม้แต่ถอยกลับ
do $$
begin
  begin
    perform advance_term_status('99999999-0000-0000-0000-000000000001', 'grading');
    raise exception 'TEST 316 ล้มเหลว: ภาคเรียนที่ closed แล้วยังเปลี่ยนสถานะได้';
  exception
    when raise_exception then
      raise notice 'TEST 316 ผ่าน — closed แล้วเปลี่ยนสถานะอะไรต่อไม่ได้อีกเลย';
  end;
end $$;

-- ── TEST 317 ───────────────────────────────────────────────────────
-- ถอยจาก registration กลับ planning ได้ทางเดียวที่ยอมให้ถอย
do $$
declare v_ay uuid; v_term uuid; v_status term_status;
begin
  select id into v_ay from academic_year where year_be = 2599;
  insert into term (academic_year_id, ordinal, starts_on, ends_on)
  values (v_ay, 2, '2599-11-01', '2600-03-15')
  returning id into v_term;

  perform advance_term_status(v_term, 'registration');
  select status into v_status from advance_term_status(v_term, 'planning');
  if v_status <> 'planning' then
    raise exception 'TEST 317 ล้มเหลว: ควรถอยกลับ planning ได้ ได้ %', v_status;
  end if;

  begin
    perform advance_term_status(v_term, 'grading');
    raise exception 'TEST 317 ล้มเหลว: จาก planning กระโดดไป grading ได้';
  exception
    when raise_exception then
      raise notice 'TEST 317 ผ่าน — ถอยจาก registration กลับ planning ได้ครั้งเดียว แล้วยังข้ามขั้นต่อไม่ได้';
  end;
end $$;

-- ── TEST 335 ───────────────────────────────────────────────────────
-- ปิดภาคเรียน (TEST 315) ต้องคำนวณ term_summary ให้เองเสมอ — ห้ามพลาด
-- เพราะ evaluate_graduation() อ่าน gpax จากตารางนี้ตรง ๆ ถ้าไม่มีแถวเลย
-- นักศึกษาจะไม่ผ่านเกณฑ์ GPA ไม่ว่าจะเรียนดีแค่ไหน (ปิดใน 0078)
do $$
declare
  v_gpa            numeric;
  v_credits_earned numeric;
begin
  select gpa, credits_earned into v_gpa, v_credits_earned
    from term_summary
   where student_id = 'aaaa0000-0000-0000-0000-000000000011'
     and term_id = '99999999-0000-0000-0000-000000000001';

  if v_gpa is null then
    raise exception 'TEST 335 ล้มเหลว: ปิดภาคเรียนแล้วแต่ term_summary ไม่มีข้อมูล — advance_term_status(''closed'') ไม่ได้เรียก compute_term_summary() ให้';
  end if;
  if v_credits_earned <= 0 then
    raise exception 'TEST 335 ล้มเหลว: ควรได้หน่วยกิตจากรายวิชาที่ลงไว้ ได้ %', v_credits_earned;
  end if;

  raise notice 'TEST 335 ผ่าน — ปิดภาคเรียนแล้ว term_summary มีข้อมูลจริงโดยอัตโนมัติ (gpa %)', v_gpa;
end $$;

\echo ''
\echo '════ ทดสอบลำดับสถานะภาคเรียนครบทุกข้อ ════'

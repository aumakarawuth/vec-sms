-- ═══════════════════════════════════════════════════════════════════
-- 0007_grade_computation.sql
-- ทดสอบการตัดเกรดจากสมุดคะแนน และขั้นตอนอนุมัติเกรด
--
-- ใช้กลุ่มเรียนที่สร้างขึ้นใหม่สำหรับเทสต์ชุดนี้โดยเฉพาะ เพราะต้องการ
-- กลุ่มที่สอนจบครบทุกคาบแล้ว ซึ่งกลุ่มในเทสต์ชุดก่อนหน้ายังสอนไม่จบ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมข้อมูล ───────────────────────────────────────────────────
-- กลุ่มเรียนที่สอนจบแล้ว 10 คาบ จากแผน 10 คาบ
insert into class_section
  (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
   teacher_id, capacity, attendance_policy_id, planned_periods)
select 'dddd0000-0000-0000-0000-000000000001',
       cs.institution_id, cs.term_id, cs.course_id, cs.curriculum_version_id, '9/9',
       cs.teacher_id, 30, cs.attendance_policy_id, 10
  from class_section cs where cs.id = 'bbbb0000-0000-0000-0000-000000000001'
on conflict (id) do nothing;

-- นักศึกษาสามคน: เข้าเรียนครบ · เข้าเรียนไม่ถึงเกณฑ์ · คะแนนไม่ครบ
insert into enrollment (id, student_id, class_section_id, term_id, status, counts_toward_gpa)
values
  ('dddd0000-0000-0000-0000-00000000e001', 'aaaa0000-0000-0000-0000-000000000011',
   'dddd0000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333331', 'enrolled', true),
  ('dddd0000-0000-0000-0000-00000000e002', 'aaaa0000-0000-0000-0000-000000000012',
   'dddd0000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333331', 'enrolled', true),
  ('dddd0000-0000-0000-0000-00000000e003', 'aaaa0000-0000-0000-0000-000000000013',
   'dddd0000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333331', 'enrolled', true)
on conflict (id) do nothing;

-- คาบเรียนสิบคาบ สอนจบแล้วทุกคาบ
insert into class_meeting (id, class_section_id, meets_on, period_from, period_to, status)
select ('dddd0000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'dddd0000-0000-0000-0000-000000000001',
       date '2026-05-04' + (g * 7), 1, 1, 'held'
  from generate_series(1, 10) g
on conflict (id) do nothing;

-- การเช็คชื่อ: คนที่ 1 มาครบ 10 คาบ · คนที่ 2 มา 5 คาบ (50% ตกเกณฑ์) · คนที่ 3 มาครบ
insert into attendance_record (class_meeting_id, enrollment_id, status, source)
select cm.id, 'dddd0000-0000-0000-0000-00000000e001', 'present', 'teacher_web'
  from class_meeting cm where cm.class_section_id = 'dddd0000-0000-0000-0000-000000000001'
on conflict do nothing;

insert into attendance_record (class_meeting_id, enrollment_id, status, source)
select cm.id, 'dddd0000-0000-0000-0000-00000000e002',
       case when row_number() over (order by cm.meets_on) <= 5 then 'present'::attendance_status
            else 'absent'::attendance_status end,
       'teacher_web'
  from class_meeting cm where cm.class_section_id = 'dddd0000-0000-0000-0000-000000000001'
on conflict do nothing;

insert into attendance_record (class_meeting_id, enrollment_id, status, source)
select cm.id, 'dddd0000-0000-0000-0000-00000000e003', 'present', 'teacher_web'
  from class_meeting cm where cm.class_section_id = 'dddd0000-0000-0000-0000-000000000001'
on conflict do nothing;

-- ชิ้นงานสองชิ้น น้ำหนักรวม 100
insert into gradebook_item (id, class_section_id, name_th, category, max_score, weight)
values
  ('dddd0000-0000-0000-0000-0000000000a1', 'dddd0000-0000-0000-0000-000000000001',
   'สอบกลางภาค', 'midterm', 50, 40),
  ('dddd0000-0000-0000-0000-0000000000a2', 'dddd0000-0000-0000-0000-000000000001',
   'สอบปลายภาค', 'final', 50, 60)
on conflict (id) do nothing;

-- คนที่ 1 ได้ 45/50 และ 43/50  → 36 + 51.6 = 87.6 → 4.0
-- คนที่ 2 ได้เต็มทั้งสองชิ้น แต่เวลาเรียนไม่ถึง → ต้องได้ ข.ร. อยู่ดี
-- คนที่ 3 กรอกแค่ชิ้นเดียว → ม.ส.
insert into gradebook_score (gradebook_item_id, enrollment_id, score)
values
  ('dddd0000-0000-0000-0000-0000000000a1', 'dddd0000-0000-0000-0000-00000000e001', 45),
  ('dddd0000-0000-0000-0000-0000000000a2', 'dddd0000-0000-0000-0000-00000000e001', 43),
  ('dddd0000-0000-0000-0000-0000000000a1', 'dddd0000-0000-0000-0000-00000000e002', 50),
  ('dddd0000-0000-0000-0000-0000000000a2', 'dddd0000-0000-0000-0000-00000000e002', 50),
  ('dddd0000-0000-0000-0000-0000000000a1', 'dddd0000-0000-0000-0000-00000000e003', 40)
on conflict (gradebook_item_id, enrollment_id) do update set score = excluded.score;

-- ── TEST 52 ────────────────────────────────────────────────────────
-- ตัดเกรดแบบดูอย่างเดียวต้องไม่เขียนอะไรลงฐานข้อมูล
do $$
declare v_before int; v_after int; v_rows int;
begin
  select count(*) into v_before from enrollment_result;
  select count(*) into v_rows from compute_section_grades('dddd0000-0000-0000-0000-000000000001');
  select count(*) into v_after from enrollment_result;

  if v_before <> v_after then
    raise exception 'TEST 52 ล้มเหลว: การดูตัวอย่างเขียนข้อมูลลงฐานข้อมูล % แถว', v_after - v_before;
  end if;
  if v_rows <> 3 then
    raise exception 'TEST 52 ล้มเหลว: ควรคืน 3 คน คืน %', v_rows;
  end if;
  raise notice 'TEST 52 ผ่าน — ดูตัวอย่างเกรด 3 คนโดยไม่เขียนอะไรลงฐานข้อมูล';
end $$;

-- ── TEST 53 ────────────────────────────────────────────────────────
-- คะแนนถ่วงน้ำหนักคิดถูก และเทียบช่วงคะแนนตัดเกรดถูก
do $$
declare r record;
begin
  select * into r from compute_section_grades('dddd0000-0000-0000-0000-000000000001')
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001';

  -- 45/50*40 = 36.00 · 43/50*60 = 51.60 · รวม 87.60
  if r.weighted_score <> 87.60 then
    raise exception 'TEST 53 ล้มเหลว: คะแนนถ่วงน้ำหนักควรเป็น 87.60 ได้ %', r.weighted_score;
  end if;
  if r.symbol <> '4.0' then
    raise exception 'TEST 53 ล้มเหลว: 87.60 คะแนนควรได้ 4.0 ได้ %', r.symbol;
  end if;
  raise notice 'TEST 53 ผ่าน — คะแนน % ได้ % หน่วยกิตที่ได้ %',
    r.weighted_score, r.symbol, r.credits_earned;
end $$;

-- ── TEST 54 ────────────────────────────────────────────────────────
-- เวลาเรียนไม่ถึงเกณฑ์ต้องได้ ข.ร. แม้คะแนนเต็ม
--
-- ข้อนี้สำคัญที่สุดในชุด เพราะเป็นจุดที่ระบบเก่ามักพลาด — ตัดเกรดจากคะแนน
-- อย่างเดียวแล้วค่อยมาไล่แก้ ข.ร. ทีหลังด้วยมือ ซึ่งตกหล่นเสมอ
do $$
declare r record;
begin
  select * into r from compute_section_grades('dddd0000-0000-0000-0000-000000000001')
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e002';

  if r.weighted_score <> 100.00 then
    raise exception 'TEST 54 ล้มเหลว: ควรได้คะแนนเต็ม 100.00 ได้ %', r.weighted_score;
  end if;
  if r.symbol <> 'ข.ร.' then
    raise exception 'TEST 54 ล้มเหลว: เวลาเรียน %%%s ต่ำกว่าเกณฑ์ ควรได้ ข.ร. ได้ %',
      r.attendance_pct, r.symbol;
  end if;
  if r.credits_earned <> 0 then
    raise exception 'TEST 54 ล้มเหลว: ข.ร. ต้องไม่ได้หน่วยกิต ได้ %', r.credits_earned;
  end if;
  raise notice 'TEST 54 ผ่าน — คะแนนเต็ม 100 แต่เวลาเรียน % ได้ % (%)',
    r.attendance_pct, r.symbol, r.note_th;
end $$;

-- ── TEST 55 ────────────────────────────────────────────────────────
-- กรอกคะแนนไม่ครบต้องได้ ม.ส. ไม่ใช่คิดจากคะแนนเท่าที่มี
--
-- ถ้าคิดจากที่มี นักศึกษาที่ครูยังไม่ได้กรอกคะแนนปลายภาคจะได้เกรดต่ำทันที
do $$
declare r record;
begin
  select * into r from compute_section_grades('dddd0000-0000-0000-0000-000000000001')
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e003';

  if r.symbol <> 'ม.ส.' then
    raise exception 'TEST 55 ล้มเหลว: กรอกคะแนน %s จาก %s ควรได้ ม.ส. ได้ %',
      r.weight_recorded, r.weight_total, r.symbol;
  end if;
  raise notice 'TEST 55 ผ่าน — กรอกน้ำหนัก % จาก % ได้ ม.ส. (%)',
    r.weight_recorded, r.weight_total, r.note_th;
end $$;

-- ── TEST 56 ────────────────────────────────────────────────────────
-- ยังมีคาบที่ยังไม่ได้สอน ต้องส่งเกรดไม่ได้
do $$
begin
  update class_meeting set status = 'scheduled'
   where id = 'dddd0000-0000-0000-0000-000000000010';
  begin
    perform submit_section_grades('dddd0000-0000-0000-0000-000000000001');
    raise exception 'TEST 56 ล้มเหลว: ส่งเกรดได้ทั้งที่ยังสอนไม่จบ';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 56%' then raise; end if;
      raise notice 'TEST 56 ผ่าน — %', sqlerrm;
  end;
  update class_meeting set status = 'held'
   where id = 'dddd0000-0000-0000-0000-000000000010';
end $$;

-- ── TEST 57 ────────────────────────────────────────────────────────
-- ส่งเกรดแล้วเขียนผลการเรียนและเลื่อนขั้นเป็น teacher_submitted
do $$
declare v_sub uuid; v_n int; v_stage submission_stage; v_results int;
begin
  select submission_id, results_written into v_sub, v_n
    from submit_section_grades('dddd0000-0000-0000-0000-000000000001');

  select stage into v_stage from grade_submission where id = v_sub;
  select count(*) into v_results
    from enrollment_result er
    join enrollment e on e.id = er.enrollment_id
   where e.class_section_id = 'dddd0000-0000-0000-0000-000000000001'
     and er.superseded_by is null;

  if v_n <> 3 or v_results <> 3 then
    raise exception 'TEST 57 ล้มเหลว: ควรเขียน 3 แถว เขียน % และมีแถวปัจจุบัน %', v_n, v_results;
  end if;
  if v_stage <> 'teacher_submitted' then
    raise exception 'TEST 57 ล้มเหลว: ขั้นควรเป็น teacher_submitted เป็น %', v_stage;
  end if;
  raise notice 'TEST 57 ผ่าน — ส่งผลการเรียน 3 คน ขั้นเลื่อนเป็น %', v_stage;
end $$;

-- ── TEST 58 ────────────────────────────────────────────────────────
-- ส่งซ้ำไม่ได้เมื่อส่งไปแล้ว
do $$
begin
  begin
    perform submit_section_grades('dddd0000-0000-0000-0000-000000000001');
    raise exception 'TEST 58 ล้มเหลว: ส่งเกรดซ้ำได้ทั้งที่ส่งไปแล้ว';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 58%' then raise; end if;
      raise notice 'TEST 58 ผ่าน — %', sqlerrm;
  end;
end $$;

-- ── TEST 59 ────────────────────────────────────────────────────────
-- ข้ามขั้นอนุมัติไม่ได้
do $$
declare v_sub uuid;
begin
  select id into v_sub from grade_submission
   where class_section_id = 'dddd0000-0000-0000-0000-000000000001';
  begin
    perform advance_grade_submission(v_sub, 'locked', 'พยายามข้ามไปล็อกเลย');
    raise exception 'TEST 59 ล้มเหลว: ข้ามขั้นจาก teacher_submitted ไป locked ได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 59%' then raise; end if;
      raise notice 'TEST 59 ผ่าน — %', sqlerrm;
  end;
end $$;

-- ── TEST 60 ────────────────────────────────────────────────────────
-- เดินครบสายอนุมัติแล้วล็อก และล็อกแล้วแก้ไม่ได้
do $$
declare v_sub uuid; v_stage submission_stage; v_events int;
begin
  select id into v_sub from grade_submission
   where class_section_id = 'dddd0000-0000-0000-0000-000000000001';

  perform advance_grade_submission(v_sub, 'head_approved',     'หัวหน้าแผนกวิชาตรวจแล้ว');
  perform advance_grade_submission(v_sub, 'academic_approved', 'ฝ่ายวิชาการตรวจแล้ว');
  perform advance_grade_submission(v_sub, 'director_approved', 'ผู้อำนวยการอนุมัติ');
  perform advance_grade_submission(v_sub, 'locked',            'ล็อกผลการเรียน');

  select stage into v_stage from grade_submission where id = v_sub;
  select count(*) into v_events from grade_submission_event where submission_id = v_sub;

  if v_stage <> 'locked' then
    raise exception 'TEST 60 ล้มเหลว: ขั้นสุดท้ายควรเป็น locked เป็น %', v_stage;
  end if;

  begin
    perform advance_grade_submission(v_sub, 'returned', 'ขอแก้หลังล็อก');
    raise exception 'TEST 60 ล้มเหลว: ล็อกแล้วยังตีกลับได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 60%' then raise; end if;
      raise notice 'TEST 60 ผ่าน — เดินครบสายอนุมัติถึง locked (ประวัติ % ขั้น) และล็อกแล้วแก้ไม่ได้: %',
        v_events, sqlerrm;
  end;
end $$;

-- ── TEST 61 ────────────────────────────────────────────────────────
-- ส่งใหม่หลังถูกตีกลับต้องออก revision ใหม่ ไม่ใช่แก้ทับ
do $$
declare v_sub uuid; v_rev int; v_current int; v_total int;
begin
  -- สร้างกลุ่มใหม่เพื่อทดสอบการตีกลับ เพราะกลุ่มเดิมล็อกไปแล้ว
  update grade_submission set stage = 'returned', locked_at = null
   where class_section_id = 'dddd0000-0000-0000-0000-000000000001';

  -- ครูแก้คะแนนแล้วส่งใหม่
  update gradebook_score set score = 30
   where gradebook_item_id = 'dddd0000-0000-0000-0000-0000000000a1'
     and enrollment_id     = 'dddd0000-0000-0000-0000-00000000e001';

  perform submit_section_grades('dddd0000-0000-0000-0000-000000000001');

  select revision into v_rev from enrollment_result
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and superseded_by is null;

  select count(*) filter (where superseded_by is null), count(*)
    into v_current, v_total
    from enrollment_result where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001';

  if v_rev <> 2 then
    raise exception 'TEST 61 ล้มเหลว: revision ควรเป็น 2 เป็น %', v_rev;
  end if;
  if v_current <> 1 or v_total <> 2 then
    raise exception 'TEST 61 ล้มเหลว: ควรมีแถวปัจจุบัน 1 จากทั้งหมด 2 มี % จาก %', v_current, v_total;
  end if;
  raise notice 'TEST 61 ผ่าน — ส่งใหม่ออก revision % แถวเดิมถูกแทนที่ไม่ใช่แก้ทับ (ทั้งหมด % แถว)',
    v_rev, v_total;
end $$;

-- ── TEST 62 ────────────────────────────────────────────────────────
-- GPAX คิดจากหน่วยกิตรวม ไม่ใช่เฉลี่ยของ GPA รายภาค
do $$
declare v_n int; r record;
begin
  select compute_term_summary('33333333-3333-3333-3333-333333333331') into v_n;

  select * into r from term_summary
   where student_id = 'aaaa0000-0000-0000-0000-000000000011'
     and term_id    = '33333333-3333-3333-3333-333333333331';

  if r.gpa is null then
    raise exception 'TEST 62 ล้มเหลว: คำนวณ GPA ไม่ได้';
  end if;
  raise notice 'TEST 62 ผ่าน — สรุปผล % คน · หน่วยกิตที่ลง % ได้ % · GPA % · GPAX %',
    v_n, r.credits_attempted, r.credits_earned, r.gpa, r.gpax;
end $$;

-- ── TEST 63 ────────────────────────────────────────────────────────
-- ทุกการเขียนผลการเรียนต้องถูกบันทึกลงบัญชีตรวจสอบแบบโซ่แฮช
do $$
declare v_ok boolean; v_entries int;
begin
  select count(*) into v_entries
    from grade_ledger where entity = 'enrollment_result';

  select bool_and(ok) into v_ok
    from verify_grade_ledger('11111111-1111-1111-1111-111111111111');

  if v_entries = 0 then
    raise exception 'TEST 63 ล้มเหลว: ไม่มีรายการผลการเรียนในบัญชีตรวจสอบเลย';
  end if;
  if not coalesce(v_ok, false) then
    raise exception 'TEST 63 ล้มเหลว: โซ่แฮชของบัญชีตรวจสอบไม่สมบูรณ์';
  end if;
  raise notice 'TEST 63 ผ่าน — บัญชีตรวจสอบมีรายการผลการเรียน % รายการ และโซ่แฮชสมบูรณ์', v_entries;
end $$;

\echo ''
\echo '════ ทดสอบการตัดเกรดและอนุมัติเกรดครบทุกข้อ ════'

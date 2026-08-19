-- ═══════════════════════════════════════════════════════════════════
-- 0051_national_exam_results.sql — ทดสอบผลสอบ O-NET/V-NET แบบทั่วไป
--
-- record_onet_results_bulk() อ่าน current_institution_id() เอง (เหมือน
-- ฟังก์ชันที่เรียกผ่าน API ทั่วไป ไม่ใช่รับ institution_id เป็นอาร์กิวเมนต์
-- แบบ validate_academic_history_row) จึงต้องตั้งบริบท app.* ก่อนเรียกเสมอ
-- มิฉะนั้น current_institution_id() เป็น null แล้วหาไม่เจอทุกแถว
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare v_inst uuid := '11111111-1111-1111-1111-111111111111'; v_person uuid;
begin
  insert into person (institution_id, first_name_th, last_name_th, gender)
  values (v_inst, 'ทดสอบ', 'ผลสอบ', 'undisclosed')
  returning id into v_person;
  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values (v_inst, v_person, '69ONET0001', 2569);
  raise notice 'เตรียมฐาน — นักศึกษา 69ONET0001';
end $$;

-- ── TEST 308 ───────────────────────────────────────────────────────
-- แถวหนึ่งผิด (รหัสนักศึกษาไม่มีจริง) ไม่ทำให้แถวอื่นบันทึกไม่ได้
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'registrar';
set local app.actor_id = '20000000-0000-0000-0000-000000000001';

do $$
declare v_rows jsonb; v_saved int; v_errors int;
begin
  v_rows := '[
    {"studentCode":"69ONET0001","examYearBe":"2569","subjectCode":"THAI","subjectTh":"ภาษาไทย","score":"65.5"},
    {"studentCode":"ไม่มีจริง","examYearBe":"2569","subjectCode":"THAI","subjectTh":"ภาษาไทย","score":"70"},
    {"studentCode":"69ONET0001","examYearBe":"2569","subjectCode":"MATH","subjectTh":"คณิตศาสตร์","score":"58"}
  ]'::jsonb;

  select count(*) filter (where status = 'saved'), count(*) filter (where status = 'error')
    into v_saved, v_errors
    from record_onet_results_bulk(v_rows);

  if v_saved <> 2 or v_errors <> 1 then
    raise exception 'TEST 308 ล้มเหลว: ควรบันทึกสำเร็จ 2 ผิด 1 ได้สำเร็จ % ผิด %', v_saved, v_errors;
  end if;
  raise notice 'TEST 308 ผ่าน — บันทึกสำเร็จ % แถว ผิด % แถว โดยไม่กระทบกัน', v_saved, v_errors;
end $$;
commit;

-- ── TEST 309 ───────────────────────────────────────────────────────
-- บันทึกซ้ำวิชาเดิมปีเดิมของคนเดิม — อัปเดตคะแนน ไม่ใช่สร้างแถวใหม่
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'registrar';
set local app.actor_id = '20000000-0000-0000-0000-000000000001';

do $$
declare v_count_before int; v_count_after int; v_score numeric;
begin
  select count(*) into v_count_before from national_exam_result
   where student_id = (select id from student where student_code = '69ONET0001')
     and subject_code = 'THAI';

  perform record_onet_results_bulk(
    '[{"studentCode":"69ONET0001","examYearBe":"2569","subjectCode":"THAI","subjectTh":"ภาษาไทย","score":"72.0"}]'::jsonb);

  select count(*) into v_count_after from national_exam_result
   where student_id = (select id from student where student_code = '69ONET0001')
     and subject_code = 'THAI';
  select score into v_score from national_exam_result
   where student_id = (select id from student where student_code = '69ONET0001')
     and subject_code = 'THAI';

  if v_count_after <> v_count_before then
    raise exception 'TEST 309 ล้มเหลว: บันทึกซ้ำควรอัปเดตแถวเดิม ไม่ใช่สร้างใหม่ (ก่อน % หลัง %)',
      v_count_before, v_count_after;
  end if;
  if v_score <> 72.0 then
    raise exception 'TEST 309 ล้มเหลว: คะแนนควรอัปเดตเป็น 72.0 ได้ %', v_score;
  end if;
  raise notice 'TEST 309 ผ่าน — บันทึกซ้ำอัปเดตคะแนนเป็น % โดยไม่เพิ่มแถวใหม่', v_score;
end $$;
commit;

-- ── TEST 310 ───────────────────────────────────────────────────────
-- ครูบันทึกผลสอบเองไม่ได้ ต้องเป็นงานทะเบียน/วิชาการ/ผู้บริหารขึ้นไป
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
begin
  begin
    insert into national_exam_result
      (institution_id, student_id, exam_year_be, subject_code, subject_th, score)
    values ('11111111-1111-1111-1111-111111111111',
            (select id from student where student_code = '69ONET0001'),
            2569, 'ENG', 'ภาษาอังกฤษ', 50);
    raise exception 'TEST 310 ล้มเหลว: ครูบันทึกผลสอบเองได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 310 ผ่าน — ครูบันทึกผลสอบเองไม่ได้';
  end;
end $$;
commit;

\echo ''
\echo '════ ทดสอบผลสอบ O-NET/V-NET ครบทุกข้อ ════'

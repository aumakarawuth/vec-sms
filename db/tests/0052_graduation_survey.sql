-- ═══════════════════════════════════════════════════════════════════
-- 0052_graduation_survey.sql — ทดสอบแบบสำรวจภาวะการมีงานทำ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare v_inst uuid := '11111111-1111-1111-1111-111111111111'; v_person uuid;
begin
  insert into person (institution_id, first_name_th, last_name_th, gender)
  values (v_inst, 'ทดสอบ', 'สำรวจภาวะงาน', 'undisclosed')
  returning id into v_person;
  insert into student (institution_id, person_id, student_code, admitted_year_be, status)
  values (v_inst, v_person, '69GSV0001', 2566, 'graduated');
  raise notice 'เตรียมฐาน — นักศึกษา 69GSV0001 (สำเร็จการศึกษา)';
end $$;

-- ── TEST 311 ───────────────────────────────────────────────────────
-- ตอบว่า "ทำงานแล้ว" ต้องระบุสถานประกอบการด้วย มิฉะนั้นฐานข้อมูลปฏิเสธ
do $$
declare v_student uuid;
begin
  select id into v_student from student where student_code = '69GSV0001';
  begin
    insert into graduation_survey_response (institution_id, student_id, status)
    values ('11111111-1111-1111-1111-111111111111', v_student, 'employed');
    raise exception 'TEST 311 ล้มเหลว: บันทึก "ทำงานแล้ว" โดยไม่มีสถานประกอบการได้';
  exception
    when check_violation then
      raise notice 'TEST 311 ผ่าน — "ทำงานแล้ว" ต้องระบุสถานประกอบการเสมอ';
  end;
end $$;

-- ── TEST 312 ───────────────────────────────────────────────────────
-- ตอบครบตามเงื่อนไขแล้วบันทึกได้ และสำรวจซ้ำได้อีกรอบ (ไม่ผูก unique)
do $$
declare v_student uuid; v_n int;
begin
  select id into v_student from student where student_code = '69GSV0001';

  insert into graduation_survey_response
    (institution_id, student_id, status, employer_name_th, job_title_th, field_matches_study)
  values
    ('11111111-1111-1111-1111-111111111111', v_student, 'employed', 'บริษัททดสอบ จำกัด', 'ช่างเทคนิค', true);

  insert into graduation_survey_response
    (institution_id, student_id, status, employer_name_th, job_title_th, field_matches_study, note)
  values
    ('11111111-1111-1111-1111-111111111111', v_student, 'employed', 'บริษัททดสอบ จำกัด', 'หัวหน้าช่าง', true, 'สำรวจซ้ำหลังจบ 1 ปี — เลื่อนตำแหน่ง');

  select count(*) into v_n from graduation_survey_response where student_id = v_student;
  if v_n <> 2 then
    raise exception 'TEST 312 ล้มเหลว: ควรสำรวจซ้ำได้ 2 รอบ มี % รอบ', v_n;
  end if;
  raise notice 'TEST 312 ผ่าน — บันทึกได้เมื่อข้อมูลครบ และสำรวจซ้ำได้ % รอบโดยไม่ติด unique', v_n;
end $$;

-- ── TEST 313 ───────────────────────────────────────────────────────
-- ครูบันทึกแบบสำรวจเองไม่ได้ ต้องเป็นงานทะเบียน/ปกครอง/วิชาการ/ผู้บริหารขึ้นไป
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
begin
  begin
    insert into graduation_survey_response (institution_id, student_id, status)
    values ('11111111-1111-1111-1111-111111111111',
            (select id from student where student_code = '69GSV0001'), 'seeking');
    raise exception 'TEST 313 ล้มเหลว: ครูบันทึกแบบสำรวจเองได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 313 ผ่าน — ครูบันทึกแบบสำรวจเองไม่ได้';
  end;
end $$;
commit;

\echo ''
\echo '════ ทดสอบแบบสำรวจภาวะการมีงานทำครบทุกข้อ ════'

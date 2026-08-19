-- ═══════════════════════════════════════════════════════════════════
-- 0050_clubs.sql — ทดสอบวิชาชุมนุม/ชมรม (บันทึกพื้นฐาน)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare v_inst uuid := '11111111-1111-1111-1111-111111111111';
        v_person uuid; v_ay uuid; v_club uuid;
begin
  insert into person (institution_id, prefix_th, first_name_th, last_name_th, gender)
  values (v_inst, 'นาย', 'ทดสอบ', 'สมาชิกชมรม', 'undisclosed')
  returning id into v_person;
  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values (v_inst, v_person, '69CLUB0001', 2569);

  insert into academic_year (institution_id, year_be, starts_on, ends_on)
  values (v_inst, 2569, '2569-05-01', '2570-03-31')
  on conflict (institution_id, year_be) do update set year_be = excluded.year_be
  returning id into v_ay;

  insert into club (institution_id, code, name_th)
  values (v_inst, 'CLB-TEST', 'ชมรมทดสอบระบบ')
  returning id into v_club;

  raise notice 'เตรียมฐาน — นักศึกษา 69CLUB0001 ปีการศึกษา 2569 ชมรม CLB-TEST';
end $$;

-- ── TEST 305 ───────────────────────────────────────────────────────
-- ครูสร้างชมรมเองไม่ได้ ต้องเป็นงานทะเบียน/วิชาการ/ปกครอง/ผู้บริหารขึ้นไป
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
begin
  begin
    insert into club (institution_id, code, name_th)
    values ('11111111-1111-1111-1111-111111111111', 'CLB-BAD', 'ชมรมที่ไม่ควรสร้างได้');
    raise exception 'TEST 305 ล้มเหลว: ครูสร้างชมรมเองได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 305 ผ่าน — ครูสร้างชมรมเองไม่ได้';
  end;
end $$;
commit;

-- ── TEST 306 ───────────────────────────────────────────────────────
-- นักศึกษาเห็นสมาชิกภาพของตัวเอง ไม่เห็นของคนอื่น
do $$
declare v_club uuid; v_ay uuid; v_student uuid; v_other uuid; v_other_person uuid;
begin
  select id into v_club from club where code = 'CLB-TEST';
  select id into v_ay from academic_year
   where institution_id = '11111111-1111-1111-1111-111111111111' and year_be = 2569;
  select id into v_student from student where student_code = '69CLUB0001';

  insert into person (institution_id, first_name_th, last_name_th, gender)
  values ('11111111-1111-1111-1111-111111111111', 'อีกคน', 'ไม่เกี่ยว', 'undisclosed')
  returning id into v_other_person;
  insert into student (institution_id, person_id, student_code, admitted_year_be)
  values ('11111111-1111-1111-1111-111111111111', v_other_person, '69CLUB0002', 2569)
  returning id into v_other;

  insert into club_member (club_id, student_id, academic_year_id, role)
  values (v_club, v_student, v_ay, 'leader'), (v_club, v_other, v_ay, 'member');
end $$;

-- หาค่าก่อนสลับบทบาท — ห้ามหาหลัง set local role เพราะ RLS จะกรองด้วย
-- บริบทที่ยังไม่ได้ตั้งแล้วได้ศูนย์แถวเสมอ (รูปแบบเดียวกับ 0025)
select person_id::text as own_person_id
  from student where student_code = '69CLUB0001' \gset

begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
select set_config('app.actor_id', :'own_person_id', true);

do $$
declare v_seen int;
begin
  select count(*) into v_seen from club_member cm
    join student s on s.id = cm.student_id
   where s.student_code = '69CLUB0001';
  if v_seen <> 1 then
    raise exception 'TEST 306 ล้มเหลว: นักศึกษาควรเห็นสมาชิกภาพของตัวเอง 1 แถว เห็น %', v_seen;
  end if;

  select count(*) into v_seen from club_member cm
    join student s on s.id = cm.student_id
   where s.student_code = '69CLUB0002';
  if v_seen <> 0 then
    raise exception 'TEST 306 ล้มเหลว: นักศึกษาเห็นสมาชิกภาพของคนอื่น % แถว', v_seen;
  end if;

  raise notice 'TEST 306 ผ่าน — นักศึกษาเห็นสมาชิกภาพของตัวเองเท่านั้น';
end $$;
commit;

-- ── TEST 307 ───────────────────────────────────────────────────────
-- สมัครซ้ำชมรมเดิมในปีการศึกษาเดิมไม่ได้
do $$
declare v_club uuid; v_ay uuid; v_student uuid;
begin
  select id into v_club from club where code = 'CLB-TEST';
  select id into v_ay from academic_year
   where institution_id = '11111111-1111-1111-1111-111111111111' and year_be = 2569;
  select id into v_student from student where student_code = '69CLUB0001';

  begin
    insert into club_member (club_id, student_id, academic_year_id)
    values (v_club, v_student, v_ay);
    raise exception 'TEST 307 ล้มเหลว: สมัครซ้ำชมรมเดิมปีเดิมได้';
  exception
    when unique_violation then
      raise notice 'TEST 307 ผ่าน — สมัครซ้ำชมรมเดิมในปีการศึกษาเดิมไม่ได้';
  end;
end $$;

\echo ''
\echo '════ ทดสอบวิชาชุมนุม/ชมรมครบทุกข้อ ════'

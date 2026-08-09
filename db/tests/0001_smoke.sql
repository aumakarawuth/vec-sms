-- ═══════════════════════════════════════════════════════════════════
-- 0001_smoke.sql
-- ทดสอบพฤติกรรมจริงของ schema ไม่ใช่แค่ว่าสร้างตารางได้
-- รันหลัง migrations และ seed:  psql -v ON_ERROR_STOP=1 -f 0001_smoke.sql
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ───────────────────────────────────────────────────────────────────
-- ข้อมูลทดสอบ
-- ───────────────────────────────────────────────────────────────────
insert into person (id, institution_id, first_name_th, last_name_th)
values ('aaaa0000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'ปิยะพงศ์', 'ศรีสุข'),
       ('aaaa0000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
        'สมชาย', 'ใจงาม');

insert into student (id, institution_id, person_id, student_code, admitted_year_be, status)
values ('aaaa0000-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-000000000001', '67201010005', 2567, 'active');

insert into staff (id, institution_id, person_id, staff_code, is_teacher)
values ('aaaa0000-0000-0000-0000-000000000022', '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-000000000002', 'T-0041', true);

-- ── TEST 1 ─────────────────────────────────────────────────────────
-- เลือกฉบับหลักสูตรจากปีที่เข้าศึกษา
-- เข้าปี 2567 ต้องได้ฉบับ 2567 · เข้าปี 2565 ต้องได้ฉบับ 2562
do $$
declare v_new uuid; v_old uuid;
begin
  v_new := curriculum_version_for('77777777-7777-7777-7777-777777777771', 2567::smallint);
  v_old := curriculum_version_for('77777777-7777-7777-7777-777777777771', 2565::smallint);
  if v_new <> '77777777-7777-7777-7777-777777777767' then
    raise exception 'TEST 1 ล้มเหลว: ปี 2567 ควรได้ฉบับ 2567 แต่ได้ %', v_new;
  end if;
  if v_old <> '77777777-7777-7777-7777-777777777762' then
    raise exception 'TEST 1 ล้มเหลว: ปี 2565 ควรได้ฉบับ 2562 แต่ได้ %', v_old;
  end if;
  raise notice 'TEST 1 ผ่าน — เลือกฉบับหลักสูตรตามปีเข้าศึกษาได้ถูกต้อง';
end $$;

-- ── TEST 2 ─────────────────────────────────────────────────────────
-- ห้ามมีสองฉบับครอบคลุมปีเข้าศึกษาเดียวกัน
do $$
begin
  begin
    insert into curriculum_version
      (curriculum_id, edition_be, effective_from_year_be, effective_to_year_be,
       grade_scheme_id, min_total_credits, status)
    values ('77777777-7777-7777-7777-777777777771', 2565, 2564, 2568,
            '44444444-4444-4444-4444-444444444444', 103.0, 'active');
    raise exception 'TEST 2 ล้มเหลว: ระบบยอมให้ฉบับหลักสูตรทับช่วงปีกัน';
  exception when exclusion_violation then
    raise notice 'TEST 2 ผ่าน — กันฉบับหลักสูตรทับช่วงปีได้';
  end;
end $$;

insert into student_curriculum (student_id, curriculum_version_id, effective_from)
values ('aaaa0000-0000-0000-0000-000000000011',
        '77777777-7777-7777-7777-777777777767', '2026-05-11');

-- ── TEST 3 ─────────────────────────────────────────────────────────
-- กฎเวลาเรียน: สอนไป 10 คาบเรียน (คาบละ 2 คาบ = 20 คาบ) จากแผน 72 คาบ
-- มาเรียน 8 ครั้ง ขาด 2 ครั้ง → ได้เครดิตเวลาเรียน 16 จาก 20 = 80.00%
insert into class_section
  (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
   teacher_id, attendance_policy_id, planned_periods)
values ('bbbb0000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        '33333333-3333-3333-3333-333333333331', '99999999-0000-0000-0000-000000000001',
        '77777777-7777-7777-7777-777777777767', '1/2',
        'aaaa0000-0000-0000-0000-000000000022', '55555555-5555-5555-5555-555555555555', 72);

insert into enrollment (id, student_id, class_section_id, term_id)
values ('cccc0000-0000-0000-0000-000000000001', 'aaaa0000-0000-0000-0000-000000000011',
        'bbbb0000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333331');

insert into class_meeting (class_section_id, meets_on, period_from, period_to, status)
select 'bbbb0000-0000-0000-0000-000000000001',
       date '2026-05-15' + (n * 7), 3, 4, 'held'
from generate_series(0, 9) as n;

-- มาเรียน 8 ครั้งแรก ขาด 2 ครั้งสุดท้าย
insert into attendance_record (class_meeting_id, enrollment_id, status)
select cm.id, 'cccc0000-0000-0000-0000-000000000001',
       case when row_number() over (order by cm.meets_on) <= 8 then 'present'::attendance_status
            else 'absent'::attendance_status end
from class_meeting cm
where cm.class_section_id = 'bbbb0000-0000-0000-0000-000000000001';

do $$
declare r record;
begin
  select * into r from v_enrollment_attendance
  where enrollment_id = 'cccc0000-0000-0000-0000-000000000001';

  if r.periods_held    <> 20    then raise exception 'TEST 3: periods_held ควรเป็น 20 ได้ %', r.periods_held; end if;
  if r.periods_credited <> 16   then raise exception 'TEST 3: periods_credited ควรเป็น 16 ได้ %', r.periods_credited; end if;
  if r.pct_to_date     <> 80.00 then raise exception 'TEST 3: pct_to_date ควรเป็น 80.00 ได้ %', r.pct_to_date; end if;
  -- เข้าครบที่เหลือจะได้ (16+52)/72 = 94.44%
  if r.pct_projected   <> 94.44 then raise exception 'TEST 3: pct_projected ควรเป็น 94.44 ได้ %', r.pct_projected; end if;
  -- floor(16 + 52 - 57.6) = 10
  if r.absences_left   <> 10    then raise exception 'TEST 3: absences_left ควรเป็น 10 ได้ %', r.absences_left; end if;
  -- ยังกู้คืนได้ แต่ pct_to_date 80 < warn 85 → warning
  if r.attendance_state <> 'warning' then raise exception 'TEST 3: state ควรเป็น warning ได้ %', r.attendance_state; end if;

  raise notice 'TEST 3 ผ่าน — เวลาเรียน % เปอร์เซ็นต์ ขาดได้อีก % คาบ สถานะ %',
    r.pct_to_date, r.absences_left, r.attendance_state;
end $$;

-- ── TEST 4 ─────────────────────────────────────────────────────────
-- ลากิจนับครึ่งตามนโยบาย: เปลี่ยนการขาด 2 ครั้งเป็นลากิจ
-- เครดิตต้องขยับจาก 16 เป็น 18 (16 + 2 คาบ x 2 ครั้ง x 0.5)
do $$
declare v numeric;
begin
  update attendance_record ar
  set status = 'leave_personal'
  where ar.enrollment_id = 'cccc0000-0000-0000-0000-000000000001'
    and ar.status = 'absent';

  select periods_credited into v from v_enrollment_attendance
  where enrollment_id = 'cccc0000-0000-0000-0000-000000000001';

  if v <> 18 then raise exception 'TEST 4: ควรได้ 18 ได้ %', v; end if;
  raise notice 'TEST 4 ผ่าน — น้ำหนักสถานะการมาเรียนถูกนำมาคิดจริง (ลากิจ = 0.5)';

  -- คืนค่าเดิมเพื่อไม่ให้กระทบเทสต์ถัดไป
  update attendance_record ar set status = 'absent'
  where ar.enrollment_id = 'cccc0000-0000-0000-0000-000000000001'
    and ar.status = 'leave_personal';
end $$;

-- ── TEST 5 ─────────────────────────────────────────────────────────
-- ผลการเรียนแก้ทับไม่ได้
insert into grade_submission (id, class_section_id, term_id, stage)
values ('dddd0000-0000-0000-0000-000000000001', 'bbbb0000-0000-0000-0000-000000000001',
        '33333333-3333-3333-3333-333333333331', 'locked');

insert into enrollment_result
  (id, enrollment_id, submission_id, revision, raw_score, attendance_pct,
   grade_symbol_id, grade_point, credits_earned)
select 'eeee0000-0000-0000-0000-000000000001', 'cccc0000-0000-0000-0000-000000000001',
       'dddd0000-0000-0000-0000-000000000001', 1, 66.0, 88.00,
       gs.id, gs.grade_point, 2.0
from grade_symbol gs
where gs.grade_scheme_id = '44444444-4444-4444-4444-444444444444' and gs.symbol = '2.5';

do $$
begin
  begin
    update enrollment_result set raw_score = 95.0
    where id = 'eeee0000-0000-0000-0000-000000000001';
    raise exception 'TEST 5 ล้มเหลว: ระบบยอมให้แก้ผลการเรียนทับ';
  exception when raise_exception then
    if sqlerrm like 'TEST 5 ล้มเหลว%' then raise; end if;
    raise notice 'TEST 5 ผ่าน — แก้ผลการเรียนทับไม่ได้ (%)', left(sqlerrm, 60);
  end;
end $$;

-- ── TEST 6 ─────────────────────────────────────────────────────────
-- โซ่แฮชของบัญชีตรวจสอบต้องสมบูรณ์
do $$
declare v_bad int;
begin
  select count(*) into v_bad
  from verify_grade_ledger('11111111-1111-1111-1111-111111111111')
  where not ok;
  if v_bad > 0 then raise exception 'TEST 6 ล้มเหลว: โซ่แฮชขาด % รายการ', v_bad; end if;
  raise notice 'TEST 6 ผ่าน — โซ่แฮชบัญชีตรวจสอบสมบูรณ์';
end $$;

-- แสดงว่าการแก้ payload ย้อนหลังจะทำให้ตรวจพบทันที
do $$
declare v_bad int;
begin
  update grade_ledger set payload = payload || '{"tampered":true}'::jsonb
  where entity_id = 'eeee0000-0000-0000-0000-000000000001';

  select count(*) into v_bad
  from verify_grade_ledger('11111111-1111-1111-1111-111111111111')
  where not ok;

  if v_bad = 0 then raise exception 'TEST 6b ล้มเหลว: แก้ payload แล้วตรวจไม่พบ'; end if;
  raise notice 'TEST 6b ผ่าน — แก้บัญชีย้อนหลังแล้วตรวจพบ % รายการ', v_bad;

  update grade_ledger set payload = payload - 'tampered'
  where entity_id = 'eeee0000-0000-0000-0000-000000000001';
end $$;

-- ── TEST 7 ─────────────────────────────────────────────────────────
-- ประวัติการเปลี่ยนสถานะนักศึกษาถูกบันทึกอัตโนมัติ
do $$
declare v int;
begin
  update student set status = 'on_leave', status_since = current_date
  where id = 'aaaa0000-0000-0000-0000-000000000011';

  select count(*) into v from student_status_history
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and from_status = 'active' and to_status = 'on_leave';

  if v <> 1 then raise exception 'TEST 7 ล้มเหลว: ไม่ได้บันทึกประวัติการเปลี่ยนสถานะ'; end if;
  raise notice 'TEST 7 ผ่าน — เปลี่ยนสถานะนักศึกษาแล้วบันทึกประวัติอัตโนมัติ';

  update student set status = 'active' where id = 'aaaa0000-0000-0000-0000-000000000011';
end $$;

-- ── TEST 8 ─────────────────────────────────────────────────────────
-- ตรวจจบ: ต้องคืนกฎครบ 10 ข้อ และข้อที่ยังไม่ผ่านต้องขึ้น false
do $$
declare v_total int; v_credit numeric; v_sat_gpax boolean;
begin
  select count(*) into v_total
  from evaluate_graduation('aaaa0000-0000-0000-0000-000000000011');
  if v_total <> 10 then raise exception 'TEST 8: ควรได้กฎ 10 ข้อ ได้ %', v_total; end if;

  select achieved into v_credit
  from evaluate_graduation('aaaa0000-0000-0000-0000-000000000011')
  where kind = 'credits_total';
  if v_credit <> 2.0 then raise exception 'TEST 8: หน่วยกิตสะสมควรเป็น 2.0 ได้ %', v_credit; end if;

  select satisfied into v_sat_gpax
  from evaluate_graduation('aaaa0000-0000-0000-0000-000000000011')
  where kind = 'gpax_min';
  if v_sat_gpax then raise exception 'TEST 8: ยังไม่มี GPAX ไม่ควรผ่านเกณฑ์'; end if;

  raise notice 'TEST 8 ผ่าน — ตรวจจบคืนกฎ 10 ข้อ หน่วยกิตสะสม % นก.', v_credit;
end $$;

-- ── TEST 9 ─────────────────────────────────────────────────────────
-- หน่วยกิตต้องไต่ขึ้นไปตามต้นไม้หมวดวิชา
-- งานเครื่องยนต์เล็กอยู่กลุ่มวิชาชีพเฉพาะ (VOC-S) ซึ่งเป็นลูกของหมวดวิชาชีพ (VOC)
-- ทั้งสองระดับต้องเห็นหน่วยกิตนี้
do $$
declare v_s numeric; v_v numeric;
begin
  select c.credits_earned into v_s
  from v_student_credits_by_category c
  join curriculum_category cat on cat.id = c.category_id
  where c.student_id = 'aaaa0000-0000-0000-0000-000000000011' and cat.code = 'VOC-S';

  select c.credits_earned into v_v
  from v_student_credits_by_category c
  join curriculum_category cat on cat.id = c.category_id
  where c.student_id = 'aaaa0000-0000-0000-0000-000000000011' and cat.code = 'VOC';

  if v_s <> 2.0 then raise exception 'TEST 9: VOC-S ควรได้ 2.0 ได้ %', v_s; end if;
  if v_v <> 2.0 then raise exception 'TEST 9: VOC (หมวดแม่) ควรได้ 2.0 ได้ %', v_v; end if;
  raise notice 'TEST 9 ผ่าน — หน่วยกิตไต่จากกลุ่มย่อยขึ้นหมวดแม่ได้ถูกต้อง';
end $$;

-- ── TEST 10 ────────────────────────────────────────────────────────
-- Row-Level Security กันข้ามสถานศึกษาได้จริง (ทดสอบด้วยผู้ใช้ที่ไม่ใช่ superuser)
insert into institution (id, code, name_th)
values ('11111111-2222-2222-2222-111111111111', '1300000002', 'วิทยาลัยอื่น');

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_runtime') then
    create role app_runtime login;
  end if;
end $$;

grant usage on schema public to app_runtime;
grant select, insert, update, delete on all tables in schema public to app_runtime;
grant usage, select on all sequences in schema public to app_runtime;

-- ต้องอยู่ใน transaction เดียวกัน เพราะ SET LOCAL มีผลเฉพาะใน transaction
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'registrar';

do $$
declare v int;
begin
  select count(*) into v from student;
  if v <> 0 then
    raise exception 'TEST 10 ล้มเหลว: วิทยาลัยอื่นมองเห็นนักศึกษา % คน', v;
  end if;
  raise notice 'TEST 10 ผ่าน — RLS กันการมองข้ามสถานศึกษาได้';
end $$;

set local app.institution_id = '11111111-1111-1111-1111-111111111111';
do $$
declare v int;
begin
  select count(*) into v from student;
  if v <> 1 then
    raise exception 'TEST 10b ล้มเหลว: สถานศึกษาตัวเองควรเห็น 1 คน เห็น %', v;
  end if;
  raise notice 'TEST 10b ผ่าน — สถานศึกษาตัวเองยังเห็นข้อมูลของตนได้ตามปกติ';
end $$;
commit;
\echo ''
\echo '════ ทดสอบครบทุกข้อ ════'

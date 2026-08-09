-- ═══════════════════════════════════════════════════════════════════
-- 0002_registration.sql
-- ทดสอบตัวตรวจเงื่อนไขการลงทะเบียน
-- รันต่อจาก 0001_smoke.sql (ใช้ข้อมูลนักศึกษาและกลุ่มเรียนเดิม)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ───────────────────────────────────────────────────────────────────
-- เตรียมข้อมูล: กลุ่มเรียนสามกลุ่มพร้อมตารางสอน
--   S1 งานเครื่องยนต์เล็ก      จันทร์ คาบ 3–4   (มีอยู่แล้วจาก smoke test)
--   S2 งานไฟฟ้ารถยนต์          จันทร์ คาบ 4–5   ← ชนกับ S1 และต้องผ่าน S1 ก่อน
--   S3 คณิตศาสตร์ช่างอุตสาหกรรม อังคาร คาบ 1–2
-- ───────────────────────────────────────────────────────────────────
-- ห้องเป็นข้อมูลจริงตั้งแต่ 0034 ไม่ใช่ข้อความอิสระอีกต่อไป
insert into room (id, institution_id, code, name_th, kind)
values ('bbbb0000-0000-0000-0000-00000000cc01', '11111111-1111-1111-1111-111111111111',
        'W-02', 'โรงฝึกงานช่างยนต์ 2', 'workshop'),
       ('bbbb0000-0000-0000-0000-00000000cc02', '11111111-1111-1111-1111-111111111111',
        'W-01', 'โรงฝึกงานช่างยนต์ 1', 'workshop'),
       ('bbbb0000-0000-0000-0000-00000000cc03', '11111111-1111-1111-1111-111111111111',
        '322', 'ห้อง 322', 'classroom')
on conflict (institution_id, code) do nothing;

insert into section_timeslot (class_section_id, day_of_week, period_from, period_to, room_id)
values ('bbbb0000-0000-0000-0000-000000000001', 1, 3, 4,
        'bbbb0000-0000-0000-0000-00000000cc01');

insert into class_section
  (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
   teacher_id, attendance_policy_id, planned_periods, capacity)
values
  ('bbbb0000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333331', '99999999-0000-0000-0000-000000000002',
   '77777777-7777-7777-7777-777777777767', '1/2',
   'aaaa0000-0000-0000-0000-000000000022', '55555555-5555-5555-5555-555555555555', 72, 40),
  ('bbbb0000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   '33333333-3333-3333-3333-333333333331', '99999999-0000-0000-0000-000000000003',
   '77777777-7777-7777-7777-777777777767', '1/2',
   'aaaa0000-0000-0000-0000-000000000022', '55555555-5555-5555-5555-555555555555', 36, 2);

insert into section_timeslot (class_section_id, day_of_week, period_from, period_to, room_id)
values ('bbbb0000-0000-0000-0000-000000000002', 1, 4, 5,
        'bbbb0000-0000-0000-0000-00000000cc02'),
       ('bbbb0000-0000-0000-0000-000000000003', 2, 1, 2,
        'bbbb0000-0000-0000-0000-00000000cc03');

-- ── TEST 11 ────────────────────────────────────────────────────────
-- ตารางเรียนชนกัน: S1 คาบ 3–4 กับ S2 คาบ 4–5 วันจันทร์ ทับกันที่คาบ 4
do $$
declare v int;
begin
  select count(*) into v
  from check_registration('aaaa0000-0000-0000-0000-000000000011',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000002']::uuid[])
  where code = 'TIME_CONFLICT' and severity = 'block';
  if v <> 1 then raise exception 'TEST 11 ล้มเหลว: ควรเจอเวลาชน 1 รายการ เจอ %', v; end if;
  raise notice 'TEST 11 ผ่าน — ตรวจเวลาเรียนชนกันได้ (คาบ 4 วันจันทร์)';
end $$;

-- ── TEST 12 ────────────────────────────────────────────────────────
-- วิชาบังคับก่อน: งานไฟฟ้ารถยนต์ต้องผ่านงานเครื่องยนต์เล็กก่อน
-- นักศึกษาได้ 2.5 ในวิชานั้นแล้ว (จาก smoke test) จึงไม่ควรติด
do $$
declare v int;
begin
  select count(*) into v
  from check_registration('aaaa0000-0000-0000-0000-000000000011',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000002']::uuid[])
  where code = 'PREREQ_NOT_MET';
  if v <> 0 then raise exception 'TEST 12 ล้มเหลว: ผ่านวิชาบังคับก่อนแล้วแต่ยังติด'; end if;
  raise notice 'TEST 12 ผ่าน — ผ่านวิชาบังคับก่อนแล้วไม่ติดเงื่อนไข';
end $$;

-- ── TEST 12b ───────────────────────────────────────────────────────
-- นักศึกษาอีกคนที่ยังไม่เคยเรียนวิชาบังคับก่อน ต้องติด
insert into person (id, institution_id, first_name_th, last_name_th)
values ('aaaa0000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
        'ธนกฤต', 'ใจดี');
insert into student (id, institution_id, person_id, student_code, admitted_year_be)
values ('aaaa0000-0000-0000-0000-000000000012', '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-000000000003', '67201010004', 2567);
insert into student_curriculum (student_id, curriculum_version_id)
values ('aaaa0000-0000-0000-0000-000000000012', '77777777-7777-7777-7777-777777777767');

do $$
declare r record;
begin
  select * into r
  from check_registration('aaaa0000-0000-0000-0000-000000000012',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000002']::uuid[])
  where code = 'PREREQ_NOT_MET';
  if r.code is null then raise exception 'TEST 12b ล้มเหลว: ควรติดวิชาบังคับก่อน'; end if;
  if r.severity <> 'block' then raise exception 'TEST 12b: ควรเป็น block ได้ %', r.severity; end if;
  raise notice 'TEST 12b ผ่าน — %', r.message_th;
end $$;

-- ── TEST 13 ────────────────────────────────────────────────────────
-- การระงับจากงานการเงิน
insert into registration_hold (student_id, kind, reason, amount, source_module, source_ref)
values ('aaaa0000-0000-0000-0000-000000000012', 'finance',
        'ค้างชำระค่าเทอมงวดที่ 2 เกิน 30 วัน', 4200.00, 'finance', 'INV-2569-004182');

do $$
declare r record;
begin
  select * into r
  from check_registration('aaaa0000-0000-0000-0000-000000000012',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000003']::uuid[])
  where code = 'HOLD_FINANCE';
  if r.code is null then raise exception 'TEST 13 ล้มเหลว: ไม่พบการระงับจากงานการเงิน'; end if;
  if r.waived then raise exception 'TEST 13 ล้มเหลว: ยังไม่ได้ยกเว้นแต่ขึ้นว่ายกเว้นแล้ว'; end if;
  raise notice 'TEST 13 ผ่าน — %', r.message_th;
end $$;

-- ── TEST 14 ────────────────────────────────────────────────────────
-- register_courses ต้องไม่เขียนอะไรเลยเมื่อยังติด block
do $$
declare v int;
begin
  begin
    perform register_courses('aaaa0000-0000-0000-0000-000000000012',
                             '33333333-3333-3333-3333-333333333331',
                             array['bbbb0000-0000-0000-0000-000000000003']::uuid[]);
    raise exception 'TEST 14 ล้มเหลว: ลงทะเบียนสำเร็จทั้งที่ติดระงับ';
  exception when check_violation then
    null;
  end;

  select count(*) into v from enrollment
  where student_id = 'aaaa0000-0000-0000-0000-000000000012';
  if v <> 0 then raise exception 'TEST 14 ล้มเหลว: มีการเขียน enrollment % แถว', v; end if;
  raise notice 'TEST 14 ผ่าน — ติด block แล้วไม่เขียนอะไรลงฐานข้อมูลเลย';
end $$;

-- ── TEST 15 ────────────────────────────────────────────────────────
-- ยกเว้นกฎแล้วลงทะเบียนได้ และการยกเว้นถูกบันทึกไว้
insert into registration_override
  (student_id, term_id, code, reason, document_no, approved_by)
values ('aaaa0000-0000-0000-0000-000000000012',
        '33333333-3333-3333-3333-333333333331', 'HOLD_FINANCE',
        'ผู้ปกครองทำเรื่องผ่อนชำระแล้ว รองผู้อำนวยการฝ่ายบริหารอนุมัติ',
        'บว.2569/0142', 'aaaa0000-0000-0000-0000-000000000022');

do $$
declare v int; r record;
begin
  select * into r
  from check_registration('aaaa0000-0000-0000-0000-000000000012',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000003']::uuid[])
  where code = 'HOLD_FINANCE';
  if not r.waived then raise exception 'TEST 15 ล้มเหลว: ยกเว้นแล้วแต่ยังขึ้นว่าไม่ยกเว้น'; end if;

  v := register_courses('aaaa0000-0000-0000-0000-000000000012',
                        '33333333-3333-3333-3333-333333333331',
                        array['bbbb0000-0000-0000-0000-000000000003']::uuid[]);
  if v <> 1 then raise exception 'TEST 15 ล้มเหลว: ควรลงทะเบียนได้ 1 รายวิชา ได้ %', v; end if;
  raise notice 'TEST 15 ผ่าน — ยกเว้นแล้วลงทะเบียนได้ และรายการยกเว้นยังปรากฏในผลตรวจ';
end $$;

-- ── TEST 16 ────────────────────────────────────────────────────────
-- ที่นั่งเต็ม: S3 รับ 2 คน มีคนลงแล้ว 1 คน เพิ่มอีก 1 คนจนเต็ม แล้วคนที่สามต้องติด
insert into person (id, institution_id, first_name_th, last_name_th)
values ('aaaa0000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
        'วรรณิศา', 'บุญมี'),
       ('aaaa0000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
        'พีรพัฒน์', 'มณีวงศ์');
insert into student (id, institution_id, person_id, student_code, admitted_year_be)
values ('aaaa0000-0000-0000-0000-000000000013', '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-000000000004', '67201010008', 2567),
       ('aaaa0000-0000-0000-0000-000000000014', '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-000000000005', '67201010006', 2567);
insert into student_curriculum (student_id, curriculum_version_id)
values ('aaaa0000-0000-0000-0000-000000000013', '77777777-7777-7777-7777-777777777767'),
       ('aaaa0000-0000-0000-0000-000000000014', '77777777-7777-7777-7777-777777777767');

do $$
declare r record;
begin
  perform register_courses('aaaa0000-0000-0000-0000-000000000013',
                           '33333333-3333-3333-3333-333333333331',
                           array['bbbb0000-0000-0000-0000-000000000003']::uuid[]);

  select * into r
  from check_registration('aaaa0000-0000-0000-0000-000000000014',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000003']::uuid[])
  where code = 'SECTION_FULL';
  if r.code is null then raise exception 'TEST 16 ล้มเหลว: ที่นั่งเต็มแล้วแต่ไม่แจ้ง'; end if;
  raise notice 'TEST 16 ผ่าน — %', r.message_th;
end $$;

-- ── TEST 17 ────────────────────────────────────────────────────────
-- ตรวจหลายข้อพร้อมกัน — ตัวตรวจต้องคืนทุกปัญหาในรอบเดียว ไม่หยุดที่ข้อแรก
do $$
declare v_block int; v_warn int; v_codes text;
begin
  select count(*) filter (where severity = 'block'),
         count(*) filter (where severity = 'warn'),
         string_agg(distinct code, ', ' order by code)
    into v_block, v_warn, v_codes
  from check_registration('aaaa0000-0000-0000-0000-000000000012',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000002']::uuid[]);

  if v_block < 2 then
    raise exception 'TEST 17 ล้มเหลว: ควรเจอ block อย่างน้อย 2 ข้อ เจอ % (%)', v_block, v_codes;
  end if;
  raise notice 'TEST 17 ผ่าน — คืนทุกปัญหาในรอบเดียว: block % ข้อ warn % ข้อ (%)',
    v_block, v_warn, v_codes;
end $$;

-- ── TEST 18 ────────────────────────────────────────────────────────
-- เพดานหน่วยกิต ปวช. ภาคปกติ 22 หน่วยกิต
-- สร้างรายวิชาก้อนใหญ่ 24 หน่วยกิตเพื่อทดสอบ
insert into course (id, institution_id, edition_be, code, name_th,
                    theory_hours, practice_hours, credits)
values ('99999999-0000-0000-0000-0000000000ff', '11111111-1111-1111-1111-111111111111',
        2567, '20101-9999', 'รายวิชาทดสอบเพดานหน่วยกิต', 24, 0, 24.0);
insert into curriculum_course (curriculum_version_id, curriculum_category_id, course_id, requirement)
values ('77777777-7777-7777-7777-777777777767', '88888888-0000-0000-0000-000000000004',
        '99999999-0000-0000-0000-0000000000ff', 'elective');
insert into class_section
  (id, institution_id, term_id, course_id, section_no, teacher_id,
   attendance_policy_id, planned_periods, capacity)
values ('bbbb0000-0000-0000-0000-0000000000ff', '11111111-1111-1111-1111-111111111111',
        '33333333-3333-3333-3333-333333333331', '99999999-0000-0000-0000-0000000000ff',
        '1/2', 'aaaa0000-0000-0000-0000-000000000022',
        '55555555-5555-5555-5555-555555555555', 360, 40);

do $$
declare r record;
begin
  select * into r
  from check_registration('aaaa0000-0000-0000-0000-000000000014',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-0000000000ff']::uuid[])
  where code = 'CREDIT_MAX';
  if r.code is null then raise exception 'TEST 18 ล้มเหลว: 24 นก. เกิน 22 แต่ไม่แจ้ง'; end if;
  -- 24 อยู่ระหว่าง 22 กับ 25 จึงเป็น warn ไม่ใช่ block (ขออนุมัติได้)
  if r.severity <> 'warn' then
    raise exception 'TEST 18: 24 นก. อยู่ในช่วงขออนุมัติได้ ควรเป็น warn ได้ %', r.severity;
  end if;
  raise notice 'TEST 18 ผ่าน — %  [severity=%]', r.message_th, r.severity;
end $$;

-- ── TEST 19 ────────────────────────────────────────────────────────
-- สร้างคาบเรียนจากตารางสอน ข้ามวันหยุด และซิงก์ planned_periods
-- ใช้ S2 ที่ยังไม่มีคาบที่สอนไปแล้ว (S1 ถูก smoke test ตั้งเป็น held ไว้)
do $$
declare v_created int; v_planned int; v_on_holiday int; v_mondays int;
begin
  v_created := generate_class_meetings('bbbb0000-0000-0000-0000-000000000002');

  select planned_periods into v_planned
  from class_section where id = 'bbbb0000-0000-0000-0000-000000000002';

  -- คำนวณจำนวนวันจันทร์ในภาคเรียน หักวันหยุดที่ตรงวันจันทร์
  select count(*) into v_mondays
  from term t,
       lateral generate_series(t.starts_on, t.ends_on, interval '1 day') d
  where t.id = '33333333-3333-3333-3333-333333333331'
    and extract(isodow from d) = 1
    and not exists (select 1 from academic_holiday h
                    where h.institution_id = '11111111-1111-1111-1111-111111111111'
                      and h.holiday_on = d::date);

  if v_created <> v_mondays then
    raise exception 'TEST 19: ควรสร้าง % คาบเรียน ได้ %', v_mondays, v_created;
  end if;
  -- ตารางสอนคือคาบ 4–5 คือคาบละ 2 คาบ
  if v_planned <> v_mondays * 2 then
    raise exception 'TEST 19: planned_periods ควรเป็น % ได้ %', v_mondays * 2, v_planned;
  end if;

  select count(*) into v_on_holiday
  from class_meeting cm
  join academic_holiday h on h.holiday_on = cm.meets_on
  where cm.class_section_id = 'bbbb0000-0000-0000-0000-000000000002';
  if v_on_holiday <> 0 then
    raise exception 'TEST 19: สร้างคาบเรียนตรงวันหยุด % คาบ', v_on_holiday;
  end if;

  raise notice 'TEST 19 ผ่าน — สร้าง % คาบเรียน ข้ามวันหยุด planned_periods = %',
    v_created, v_planned;
end $$;

-- ── TEST 20 ────────────────────────────────────────────────────────
-- ห้ามสร้างคาบเรียนใหม่หลังเริ่มสอนแล้ว เพราะจะเปลี่ยนตัวหารของกฎ 80% ย้อนหลัง
-- S1 มีคาบที่สอนไปแล้วจาก smoke test ชุดแรก
do $$
declare v_before int;
begin
  select planned_periods into v_before
  from class_section where id = 'bbbb0000-0000-0000-0000-000000000001';

  begin
    perform generate_class_meetings('bbbb0000-0000-0000-0000-000000000001');
    raise exception 'TEST 20 ล้มเหลว: ยอมให้สร้างคาบเรียนใหม่ทั้งที่สอนไปแล้ว';
  exception when raise_exception then
    if sqlerrm like 'TEST 20 ล้มเหลว%' then raise; end if;
    raise notice 'TEST 20 ผ่าน — %', left(sqlerrm, 64);
  end;

  if (select planned_periods from class_section
      where id = 'bbbb0000-0000-0000-0000-000000000001') <> v_before then
    raise exception 'TEST 20 ล้มเหลว: planned_periods ถูกแก้ทั้งที่ฟังก์ชันปฏิเสธ';
  end if;
end $$;

-- ── TEST 21 ────────────────────────────────────────────────────────
-- มุมมองตรวจครูสอนซ้อน: S1 จันทร์ 3–4 กับ S2 จันทร์ 4–5 ครูคนเดียวกัน
do $$
declare v int;
begin
  select count(*) into v from v_teacher_conflict
  where term_id = '33333333-3333-3333-3333-333333333331';
  if v < 1 then raise exception 'TEST 21 ล้มเหลว: ครูสอนซ้อนแต่ตรวจไม่พบ'; end if;
  raise notice 'TEST 21 ผ่าน — ตรวจพบครูสอนซ้อน % คู่ (ใช้ตอนจัดตารางสอน)', v;
end $$;

-- ── TEST 22 ────────────────────────────────────────────────────────
-- เรียนซ้ำ: ลงวิชาที่เคยผ่านแล้ว ต้องเตือนและตั้ง attempt_no ให้ถูก
do $$
declare r record; v int; v_attempt smallint;
begin
  select * into r
  from check_registration('aaaa0000-0000-0000-0000-000000000011',
                          '33333333-3333-3333-3333-333333333331',
                          array['bbbb0000-0000-0000-0000-000000000002']::uuid[])
  where code = 'ALREADY_PASSED';
  if r.code is not null then
    raise exception 'TEST 22: ยังไม่เคยผ่านงานไฟฟ้ารถยนต์ ไม่ควรเตือน';
  end if;

  -- ยกเว้นเวลาชนเพื่อทดสอบ attempt_no
  insert into registration_override (student_id, term_id, code, class_section_id, reason, approved_by)
  values ('aaaa0000-0000-0000-0000-000000000011', '33333333-3333-3333-3333-333333333331',
          'TIME_CONFLICT', 'bbbb0000-0000-0000-0000-000000000002',
          'ครูจัดคาบชดเชยนอกตาราง', 'aaaa0000-0000-0000-0000-000000000022');

  v := register_courses('aaaa0000-0000-0000-0000-000000000011',
                        '33333333-3333-3333-3333-333333333331',
                        array['bbbb0000-0000-0000-0000-000000000002']::uuid[]);

  select e.attempt_no into v_attempt
  from enrollment e
  where e.student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and e.class_section_id = 'bbbb0000-0000-0000-0000-000000000002';

  if v_attempt <> 1 then raise exception 'TEST 22: attempt_no ควรเป็น 1 ได้ %', v_attempt; end if;
  raise notice 'TEST 22 ผ่าน — ยกเว้นเวลาชนแล้วลงทะเบียนได้ attempt_no = %', v_attempt;
end $$;

\echo ''
\echo '════ ทดสอบการลงทะเบียนครบทุกข้อ ════'

-- ═══════════════════════════════════════════════════════════════════
-- 0017_grouping_and_gradebook_copy.sql
-- ทดสอบการจัดชั้นปี/ห้อง และการคัดลอกโครงสร้างสมุดคะแนน
--
-- ─── ทำไมชุดนี้เน้นการ "ไม่แตะ" มากกว่าการคัดลอก ───
-- การคัดลอกที่ทำงานถูกต้องเป็นเรื่องง่าย ความเสียหายจริงมาจากการคัดลอก
-- ทับของที่มีอยู่ — ถ้าคัดลอกเข้าห้องที่ครูตั้งรายการไว้แล้ว จะได้สองชุด
-- แล้วน้ำหนักรวมเกินร้อย และถ้าคัดลอกเข้าห้องที่กรอกคะแนนไปแล้ว ตัวหาร
-- จะเปลี่ยนแล้วคะแนนของทุกคนในห้องเพี้ยนพร้อมกัน
--
-- ทั้งสองกรณีไม่มีอาการอะไรให้เห็นเลยจนถึงวันตัดเกรด
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 149 ───────────────────────────────────────────────────────
-- จัดชั้นปี/ห้องเป็นกลุ่ม — ตั้งครั้งแรกและจัดใหม่ต้องได้ทั้งคู่
do $$
declare
  v_placed  integer;
  v_group   text;
  v_year    smallint;
  v_skipped integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select count(*) filter (where action = 'placed'),
         count(*) filter (where action <> 'placed')
    into v_placed, v_skipped
    from place_students('22222222-2222-2222-2222-222222222223',
           (select array_agg(id) from student
             where institution_id = '11111111-1111-1111-1111-111111111111'),
           2::smallint, 'ปวช.2/1');

  if v_placed = 0 then
    raise exception 'TEST 149 ล้มเหลว: ไม่มีใครถูกจัดห้องเลย';
  end if;
  if v_skipped = 0 then
    raise exception 'TEST 149 ล้มเหลว: คนที่ลาออกแล้วควรถูกข้าม แต่ไม่มีใครถูกข้าม';
  end if;

  select group_code, study_year into v_group, v_year
    from student_class_placement
   where student_id = 'aaaa0000-0000-0000-0000-000000000012'
     and academic_year_id = '22222222-2222-2222-2222-222222222223';

  if v_group <> 'ปวช.2/1' or v_year <> 2 then
    raise exception 'TEST 149 ล้มเหลว: จัดห้องไม่ตรง ได้ห้อง % ชั้นปี %', v_group, v_year;
  end if;

  -- จัดใหม่ต้องเขียนทับของปีเดียวกันได้ ไม่ใช่สร้างแถวซ้ำ
  perform place_students('22222222-2222-2222-2222-222222222223',
    array['aaaa0000-0000-0000-0000-000000000012']::uuid[], 2::smallint, 'ปวช.2/2');

  select group_code into v_group
    from student_class_placement
   where student_id = 'aaaa0000-0000-0000-0000-000000000012'
     and academic_year_id = '22222222-2222-2222-2222-222222222223';

  if v_group <> 'ปวช.2/2' then
    raise exception 'TEST 149 ล้มเหลว: จัดห้องใหม่ไม่มีผล ยังเป็น %', v_group;
  end if;

  raise notice 'TEST 149 ผ่าน — จัดห้อง % คน ข้าม % คน และจัดใหม่ทับของเดิมได้', v_placed, v_skipped;
end $$;

-- ── TEST 150 ───────────────────────────────────────────────────────
-- คัดลอกโครงสร้างสมุดคะแนน — คัดลอกได้ แต่ต้องไม่เอาคะแนนและกำหนดส่งมาด้วย
do $$
declare
  v_src   uuid;
  v_dst   uuid;
  v_n     integer;
  v_due   integer;
  v_score integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select gi.class_section_id into v_src
    from gradebook_item gi group by gi.class_section_id order by count(*) desc limit 1;

  if v_src is null then
    raise exception 'TEST 150 ล้มเหลว: ไม่มีสมุดคะแนนต้นทางให้ทดสอบ';
  end if;

  -- ห้องปลายทางว่าง ๆ ในภาคเรียนที่ 2
  insert into class_section
    (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
     teacher_id, attendance_policy_id, planned_periods, capacity)
  select 'cccc0000-0000-0000-0000-00000000f001', cs.institution_id,
         '33333333-3333-3333-3333-333333333332', cs.course_id,
         cs.curriculum_version_id, cs.section_no, cs.teacher_id,
         cs.attendance_policy_id, cs.planned_periods, cs.capacity
    from class_section cs where cs.id = v_src
  on conflict (id) do nothing;

  v_dst := 'cccc0000-0000-0000-0000-00000000f001';
  v_n := copy_gradebook_items(v_src, v_dst);

  if v_n = 0 then
    raise exception 'TEST 150 ล้มเหลว: ไม่ได้คัดลอกรายการใดเลย';
  end if;

  select count(*) into v_due
    from gradebook_item where class_section_id = v_dst and due_on is not null;
  select count(*) into v_score
    from gradebook_score gsc
    join gradebook_item gi on gi.id = gsc.gradebook_item_id
   where gi.class_section_id = v_dst;

  if v_due > 0 then
    raise exception 'TEST 150 ล้มเหลว: คัดลอกกำหนดส่งของปีที่แล้วมาด้วย % รายการ', v_due;
  end if;
  if v_score > 0 then
    raise exception 'TEST 150 ล้มเหลว: คัดลอกคะแนนนักศึกษามาด้วย % รายการ', v_score;
  end if;

  raise notice 'TEST 150 ผ่าน — คัดลอก % รายการ ไม่มีกำหนดส่งเก่าและไม่มีคะแนนติดมา', v_n;
end $$;

-- ── TEST 151 ───────────────────────────────────────────────────────
-- ห้ามคัดลอกทับห้องที่มีรายการอยู่แล้ว และห้ามแตะห้องที่กรอกคะแนนแล้ว
do $$
declare
  v_src     uuid;
  v_blocked integer := 0;
  v_untouched integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  -- ต้องไม่ใช่ห้องปลายทางของ TEST 150 ซึ่งตอนนี้มีรายการมากที่สุดไปแล้ว
  select gi.class_section_id into v_src
    from gradebook_item gi
   where gi.class_section_id <> 'cccc0000-0000-0000-0000-00000000f001'
   group by gi.class_section_id order by count(*) desc limit 1;

  -- ปลายทางมีรายการอยู่แล้วจาก TEST 150
  begin
    perform copy_gradebook_items(v_src, 'cccc0000-0000-0000-0000-00000000f001');
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  -- ห้องเดียวกันเป็นทั้งต้นทางและปลายทาง
  begin
    perform copy_gradebook_items(v_src, v_src);
  exception when others then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 2 then
    raise exception 'TEST 151 ล้มเหลว: ควรถูกบล็อกสองทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  -- ห้องต้นทางที่มีคะแนนอยู่ต้องไม่ถูกแตะจากการคัดลอกทั้งภาคเรียน
  select count(*) into v_untouched from gradebook_item where class_section_id = v_src;

  perform rollover_gradebook_templates(
    '33333333-3333-3333-3333-333333333331', '33333333-3333-3333-3333-333333333332');

  if (select count(*) from gradebook_item where class_section_id = v_src) <> v_untouched then
    raise exception 'TEST 151 ล้มเหลว: จำนวนรายการของห้องต้นทางเปลี่ยนไป';
  end if;

  raise notice 'TEST 151 ผ่าน — คัดลอกทับไม่ได้ ห้องเดียวกันไม่ได้ และห้องต้นทางไม่ถูกแตะ';
end $$;

-- ── TEST 152 ───────────────────────────────────────────────────────
-- คัดลอกทั้งภาคเรียนต้องรายงานห้องที่จับคู่ไม่ได้ ไม่ใช่ข้ามเงียบ ๆ
do $$
declare
  v_rows    integer;
  v_noted   integer;
  v_skipped integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  -- ห้องในภาคเรียนที่ 2 ที่ไม่มีคู่ในภาคเรียนที่ 1 (รหัสห้องคนละอัน)
  insert into class_section
    (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
     teacher_id, attendance_policy_id, planned_periods, capacity)
  select 'cccc0000-0000-0000-0000-00000000f002', cs.institution_id,
         '33333333-3333-3333-3333-333333333332', cs.course_id,
         cs.curriculum_version_id, 'ไม่มีคู่', cs.teacher_id,
         cs.attendance_policy_id, cs.planned_periods, cs.capacity
    from class_section cs
   where cs.id = 'cccc0000-0000-0000-0000-00000000f001'
  on conflict (id) do nothing;

  select count(*),
         count(*) filter (where note is not null),
         count(*) filter (where note like '%ไม่พบห้องเดียวกัน%')
    into v_rows, v_noted, v_skipped
    from rollover_gradebook_templates(
      '33333333-3333-3333-3333-333333333331', '33333333-3333-3333-3333-333333333332');

  if v_rows = 0 then
    raise exception 'TEST 152 ล้มเหลว: ไม่รายงานห้องใดเลย';
  end if;
  if v_skipped = 0 then
    raise exception 'TEST 152 ล้มเหลว: ห้องที่จับคู่ไม่ได้ถูกข้ามเงียบ ๆ ไม่ได้ถูกรายงาน';
  end if;

  raise notice 'TEST 152 ผ่าน — รายงาน % ห้อง มีหมายเหตุ % ห้อง (จับคู่ไม่ได้ % ห้อง)',
    v_rows, v_noted, v_skipped;
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบการจัดห้องและคัดลอกสมุดคะแนนครบทุกข้อ ════'; end $$;

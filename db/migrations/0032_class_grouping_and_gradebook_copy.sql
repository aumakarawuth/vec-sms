-- ═══════════════════════════════════════════════════════════════════
-- 0032_class_grouping_and_gradebook_copy.sql
--
-- จัดชั้นปี/ห้องเรียนเป็นกลุ่ม และคัดลอกโครงสร้างสมุดคะแนนข้ามปี
--
-- ─── สองข้อที่ค้างจาก 0031 ───
-- 0031 เลื่อนชั้นนักศึกษาได้แล้ว แต่ตั้ง group_code เป็น null เสมอ เพราะ
-- การจัดห้องเป็นการตัดสินใจของคน ไม่ใช่การคัดลอก และนักศึกษาปีหนึ่งที่
-- เพิ่งเข้ามายังไม่มีชั้นปีเลยเพราะไม่เคยถูกเลื่อนมาจากปีไหน — จึงต้องมี
-- ทางตั้งชั้นปีและห้องเป็นกลุ่ม
--
-- ส่วนสมุดคะแนน ระบบที่วิทยาลัยใช้อยู่คัดลอกโครงสร้างข้ามปีให้ ของเรา
-- ยังต้องให้ครูตั้งใหม่ทุกภาคเรียน ซึ่งเป็นงานที่ทำซ้ำ ๆ และเป็นจุดที่
-- น้ำหนักคะแนนพิมพ์ผิดได้ง่ายที่สุด
--
-- ─── ทำไมคัดลอกสมุดคะแนนแล้วต้องไม่ทับของที่มีอยู่ ───
-- ถ้าห้องปลายทางมีรายการคะแนนอยู่แล้ว แปลว่าครูเริ่มตั้งเองไปแล้ว
-- การคัดลอกทับจะทำให้มีรายการซ้ำสองชุด แล้วน้ำหนักรวมเกินร้อย
-- โดยที่ไม่มีใครสังเกตจนกว่าจะถึงตอนตัดเกรด
--
-- ─── ทำไมห้องที่มีคะแนนบันทึกแล้วห้ามแตะเด็ดขาด ───
-- gradebook_score ผูกกับ gradebook_item ถ้าเพิ่มรายการเข้าไปในห้องที่
-- กรอกคะแนนไปแล้วบางส่วน คะแนนที่กรอกไว้จะยังอยู่แต่ตัวหารเปลี่ยน
-- ผลคือคะแนนของทุกคนในห้องนั้นเพี้ยนพร้อมกันโดยไม่มีอะไรฟ้อง
--
-- ─── ทำไมจับคู่ห้องด้วยรายวิชาและรหัสห้อง ไม่ใช่เดาให้ ───
-- การจับคู่ผิดห้องแล้วคัดลอกน้ำหนักคะแนนของวิชาอื่นเข้ามา เป็นความผิดพลาด
-- ที่ไม่มีอาการจนถึงวันตัดเกรด ฟังก์ชันจึงจับคู่เฉพาะกรณีที่ตรงกันชัดเจน
-- (รายวิชาเดียวกัน หลักสูตรฉบับเดียวกัน รหัสห้องเดียวกัน) และรายงาน
-- ห้องที่จับคู่ไม่ได้ออกมาให้คนตัดสินใจ แทนที่จะเดาให้ใกล้เคียงที่สุด
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- จัดชั้นปีและห้องเป็นกลุ่ม
--
-- ใช้ได้ทั้งการตั้งครั้งแรกให้นักศึกษาปีหนึ่ง และการจัดห้องใหม่หลังเลื่อนชั้น
-- คืนผลรายคนตามหลักเดียวกับงานกลุ่มอื่นในระบบนี้
-- ───────────────────────────────────────────────────────────────────
create or replace function place_students(
  p_academic_year_id uuid,
  p_student_ids      uuid[],
  p_study_year       smallint,
  p_group_code       text default null
) returns table (
  student_id uuid,
  action     text,
  note       text
) language plpgsql as $$
#variable_conflict use_column
declare
  v_inst    uuid := current_institution_id();
  v_student uuid;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;
  if not exists (select 1 from academic_year ay
                  where ay.id = p_academic_year_id and ay.institution_id = v_inst) then
    raise exception 'ไม่พบปีการศึกษาที่ระบุในสถานศึกษานี้';
  end if;
  if p_study_year is null or p_study_year < 1 or p_study_year > 6 then
    raise exception 'ชั้นปีต้องอยู่ระหว่าง 1 ถึง 6 (ได้ %)', p_study_year;
  end if;

  foreach v_student in array coalesce(p_student_ids, '{}'::uuid[]) loop
    -- นักศึกษาของวิทยาลัยอื่นถูก RLS กันไว้อยู่แล้ว ตรงนี้จับกรณีรหัสผิด
    if not exists (select 1 from student s where s.id = v_student) then
      return query select v_student, 'not_found'::text, 'ไม่พบนักศึกษารหัสนี้'::text;
      continue;
    end if;

    if (select status from student where id = v_student) <> 'active' then
      return query select v_student, 'inactive'::text,
        'สถานะไม่ใช่กำลังศึกษา จึงไม่จัดห้องให้'::text;
      continue;
    end if;

    insert into student_class_placement
      (institution_id, student_id, academic_year_id, study_year, group_code)
    values (v_inst, v_student, p_academic_year_id, p_study_year, p_group_code)
    on conflict (student_id, academic_year_id) do update
      set study_year = excluded.study_year,
          group_code = excluded.group_code;

    return query select v_student, 'placed'::text, null::text;
  end loop;
end $$;

comment on function place_students(uuid, uuid[], smallint, text) is
  'จัดชั้นปีและห้องประจำเป็นกลุ่ม — ใช้ทั้งตอนรับนักศึกษาใหม่และตอนจัดห้องใหม่หลังเลื่อนชั้น';

-- ───────────────────────────────────────────────────────────────────
-- คัดลอกโครงสร้างสมุดคะแนนจากห้องหนึ่งไปอีกห้องหนึ่ง
--
-- คัดลอกเฉพาะ "โครงสร้าง" — ชื่อรายการ หมวด คะแนนเต็ม น้ำหนัก ลำดับ
-- ไม่คัดลอกคะแนนของนักศึกษา และไม่คัดลอกกำหนดส่ง เพราะวันที่ของปีที่แล้ว
-- ใช้กับปีนี้ไม่ได้ ถ้าคัดลอกมาด้วยจะกลายเป็นกำหนดส่งที่เลยไปแล้วทุกอัน
-- ───────────────────────────────────────────────────────────────────
create or replace function copy_gradebook_items(
  p_from_section_id uuid,
  p_to_section_id   uuid
) returns integer language plpgsql as $$
declare
  v_count integer;
begin
  if p_from_section_id = p_to_section_id then
    raise exception 'ห้องต้นทางและปลายทางเป็นห้องเดียวกัน';
  end if;

  if not exists (select 1 from class_section cs where cs.id = p_to_section_id) then
    raise exception 'ไม่พบห้องเรียนปลายทาง';
  end if;

  -- มีรายการอยู่แล้ว = ครูเริ่มตั้งเองไปแล้ว คัดลอกทับจะได้สองชุด
  if exists (select 1 from gradebook_item gi where gi.class_section_id = p_to_section_id) then
    raise exception 'ห้องปลายทางมีรายการคะแนนอยู่แล้ว คัดลอกทับจะทำให้น้ำหนักรวมเกิน'
      using errcode = 'check_violation';
  end if;

  insert into gradebook_item
    (class_section_id, name_th, category, max_score, weight,
     competency_id, publish_to_student, sort_order)
  select p_to_section_id, gi.name_th, gi.category, gi.max_score, gi.weight,
         gi.competency_id, gi.publish_to_student, gi.sort_order
    from gradebook_item gi
   where gi.class_section_id = p_from_section_id
   order by gi.sort_order;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

comment on function copy_gradebook_items(uuid, uuid) is
  'คัดลอกโครงสร้างสมุดคะแนนระหว่างห้อง — ไม่คัดลอกคะแนนและไม่คัดลอกกำหนดส่ง';

-- ───────────────────────────────────────────────────────────────────
-- คัดลอกสมุดคะแนนทั้งภาคเรียน
--
-- จับคู่ห้องด้วย (รายวิชา · หลักสูตรฉบับ · รหัสห้อง) ซึ่งตรงกันชัดเจน
-- ห้องที่จับคู่ไม่ได้หรือแตะไม่ได้จะถูกรายงานออกมาพร้อมเหตุผล ไม่ถูกข้ามเงียบ ๆ
-- ───────────────────────────────────────────────────────────────────
create or replace function rollover_gradebook_templates(
  p_from_term_id uuid,
  p_to_term_id   uuid
) returns table (
  to_section_id   uuid,
  from_section_id uuid,
  section_label   text,
  items_copied    integer,
  note            text
) language plpgsql as $$
#variable_conflict use_column
declare
  r      record;
  v_from uuid;
  v_n    integer;
begin
  if p_from_term_id = p_to_term_id then
    raise exception 'ภาคเรียนต้นทางและปลายทางเป็นภาคเดียวกัน';
  end if;

  for r in
    select cs.id, cs.course_id, cs.curriculum_version_id, cs.section_no,
           c.code as course_code
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.term_id = p_to_term_id
     order by c.code, cs.section_no
  loop
    select cs2.id into v_from
      from class_section cs2
     where cs2.term_id = p_from_term_id
       and cs2.course_id = r.course_id
       and cs2.curriculum_version_id is not distinct from r.curriculum_version_id
       and cs2.section_no is not distinct from r.section_no
     limit 1;

    if v_from is null then
      return query select r.id, null::uuid,
        (r.course_code || ' ' || coalesce(r.section_no, ''))::text, 0,
        'ไม่พบห้องเดียวกันในภาคเรียนต้นทาง ต้องตั้งสมุดคะแนนเอง'::text;
      continue;
    end if;

    -- ห้องที่กรอกคะแนนไปแล้วห้ามแตะ การเพิ่มรายการเข้าไปจะทำให้ตัวหาร
    -- เปลี่ยนแล้วคะแนนของทุกคนในห้องเพี้ยนพร้อมกันโดยไม่มีอะไรฟ้อง
    if exists (select 1 from gradebook_item gi
                join gradebook_score gsc on gsc.gradebook_item_id = gi.id
               where gi.class_section_id = r.id) then
      return query select r.id, v_from,
        (r.course_code || ' ' || coalesce(r.section_no, ''))::text, 0,
        'ห้องนี้กรอกคะแนนไปแล้ว ไม่แตะโครงสร้างสมุดคะแนน'::text;
      continue;
    end if;

    if exists (select 1 from gradebook_item gi where gi.class_section_id = r.id) then
      return query select r.id, v_from,
        (r.course_code || ' ' || coalesce(r.section_no, ''))::text, 0,
        'มีรายการคะแนนอยู่แล้ว ข้ามไป'::text;
      continue;
    end if;

    v_n := copy_gradebook_items(v_from, r.id);

    return query select r.id, v_from,
      (r.course_code || ' ' || coalesce(r.section_no, ''))::text, v_n, null::text;
  end loop;
end $$;

comment on function rollover_gradebook_templates(uuid, uuid) is
  'คัดลอกโครงสร้างสมุดคะแนนทั้งภาคเรียนโดยจับคู่ห้องที่ตรงกันชัดเจน — ห้องที่จับคู่ไม่ได้ถูกรายงาน ไม่ใช่เดาให้';

commit;

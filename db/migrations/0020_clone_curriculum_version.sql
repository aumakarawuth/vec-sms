-- ═══════════════════════════════════════════════════════════════════
-- 0020_clone_curriculum_version.sql
--
-- ออกฉบับหลักสูตรใหม่จากฉบับเดิมทั้งก้อน
--
-- ─── ทำไมต้องเป็นฟังก์ชัน ไม่ใช่ให้แอปคัดลอกทีละตาราง ───
-- ฉบับหนึ่งมีหมวดวิชาเป็น **ต้นไม้** รายวิชาที่ชี้เข้าหมวด สมรรถนะ
-- วิชาบังคับก่อน เส้นทางเข้าศึกษาพร้อมวิชาปรับพื้นฐาน และเงื่อนไขจบ
-- ทั้งหมดผูกกันด้วย uuid ที่ต้องถูก map ใหม่พร้อมกันทั้งชุด
--
-- ถ้าคัดลอกทีละตารางจากฝั่งแอป จุดที่พลาดคือ parent_id ของหมวดวิชา
-- ซึ่งจะยังชี้ไปที่หมวดของฉบับเก่า ผลคือฉบับใหม่มีหมวดวิชาที่แขวนอยู่
-- ใต้ต้นไม้ของฉบับเดิม แล้ว v_student_credits_by_category จะไต่ขึ้นไป
-- นับหน่วยกิตข้ามฉบับ — ตรวจจบผ่านทั้งที่เรียนไม่ครบ และไม่มีอะไรฟ้อง
--
-- ─── ฉบับใหม่เกิดมาเป็น draft เสมอ ───
-- exclusion constraint กันช่วงปีทับกันจะไม่บังคับกับฉบับ draft
-- ทำให้เตรียมฉบับใหม่คู่ขนานกับฉบับที่ใช้อยู่ได้ แล้วค่อยปิดช่วงปี
-- ของฉบับเดิมกับเปิดใช้ฉบับใหม่พร้อมกันในธุรกรรมเดียวตอนประกาศใช้
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function clone_curriculum_version(
  p_source_id             uuid,
  p_edition_be            smallint,
  p_effective_from_year_be smallint,
  p_effective_to_year_be   smallint default null
) returns uuid
language plpgsql as $$
declare
  v_src curriculum_version%rowtype;
  v_new uuid;
begin
  select * into v_src from curriculum_version where id = p_source_id;
  if not found then
    raise exception 'ไม่พบฉบับหลักสูตรต้นทาง % (หรือไม่มีสิทธิ์เข้าถึง)', p_source_id;
  end if;

  if exists (select 1 from curriculum_version
              where curriculum_id = v_src.curriculum_id and edition_be = p_edition_be) then
    raise exception 'หลักสูตรนี้มีฉบับปี %  อยู่แล้ว', p_edition_be;
  end if;

  insert into curriculum_version (
    curriculum_id, edition_be, effective_from_year_be, effective_to_year_be,
    grade_scheme_id, min_total_credits, min_gpax, min_practicum_hours,
    requires_prof_standard, requires_all_activity, normal_duration_terms, status
  ) values (
    v_src.curriculum_id, p_edition_be, p_effective_from_year_be, p_effective_to_year_be,
    v_src.grade_scheme_id, v_src.min_total_credits, v_src.min_gpax, v_src.min_practicum_hours,
    v_src.requires_prof_standard, v_src.requires_all_activity, v_src.normal_duration_terms,
    'draft'
  ) returning id into v_new;

  -- ── หมวดวิชา ────────────────────────────────────────────────────
  -- คัดลอกพร้อมจำคู่ id เก่า→ใหม่ไว้ แล้วค่อยเดินซ่อมสายพ่อแม่ทีหลัง
  -- ทำสองรอบเพราะหมวดลูกอาจถูกคัดลอกก่อนหมวดแม่
  create temporary table _cat_map (old_id uuid primary key, new_id uuid not null)
    on commit drop;

  with copied as (
    insert into curriculum_category
      (curriculum_version_id, parent_id, kind, code, name_th,
       min_credits, max_credits, sort_order)
    select v_new, null, kind, code, name_th, min_credits, max_credits, sort_order
      from curriculum_category
     where curriculum_version_id = p_source_id
    returning id, code
  )
  insert into _cat_map (old_id, new_id)
  select src.id, copied.id
    from copied
    join curriculum_category src
      on src.curriculum_version_id = p_source_id and src.code = copied.code;

  -- ซ่อมสายพ่อแม่ให้ชี้ไปหมวดของฉบับใหม่ ไม่ใช่ของฉบับเดิม
  update curriculum_category tgt
     set parent_id = pm.new_id
    from curriculum_category src
    join _cat_map cm on cm.old_id = src.id
    left join _cat_map pm on pm.old_id = src.parent_id
   where tgt.id = cm.new_id
     and src.parent_id is not null;

  -- ── สมรรถนะ ────────────────────────────────────────────────────
  create temporary table _comp_map (old_id uuid primary key, new_id uuid not null)
    on commit drop;

  with copied as (
    insert into competency (curriculum_version_id, code, statement_th, sort_order)
    select v_new, code, statement_th, sort_order
      from competency where curriculum_version_id = p_source_id
    returning id, code
  )
  insert into _comp_map (old_id, new_id)
  select src.id, copied.id
    from copied
    join competency src
      on src.curriculum_version_id = p_source_id and src.code = copied.code;

  -- ── รายวิชาในหลักสูตร ──────────────────────────────────────────
  insert into curriculum_course
    (curriculum_version_id, curriculum_category_id, course_id,
     requirement, suggested_year, suggested_term, sort_order)
  select v_new, cm.new_id, cc.course_id,
         cc.requirement, cc.suggested_year, cc.suggested_term, cc.sort_order
    from curriculum_course cc
    left join _cat_map cm on cm.old_id = cc.curriculum_category_id
   where cc.curriculum_version_id = p_source_id;

  -- ── รายวิชาสอนสมรรถนะอะไร ──────────────────────────────────────
  insert into course_competency (curriculum_version_id, course_id, competency_id, is_primary)
  select v_new, cc.course_id, km.new_id, cc.is_primary
    from course_competency cc
    join _comp_map km on km.old_id = cc.competency_id
   where cc.curriculum_version_id = p_source_id;

  -- ── วิชาบังคับก่อน ─────────────────────────────────────────────
  insert into course_prerequisite
    (curriculum_version_id, course_id, prerequisite_course_id, kind)
  select v_new, course_id, prerequisite_course_id, kind
    from course_prerequisite where curriculum_version_id = p_source_id;

  -- ── เส้นทางเข้าศึกษาและวิชาปรับพื้นฐาน ─────────────────────────
  create temporary table _path_map (old_id uuid primary key, new_id uuid not null)
    on commit drop;

  with copied as (
    insert into entry_pathway (curriculum_version_id, code, name_th, extra_min_credits, note)
    select v_new, code, name_th, extra_min_credits, note
      from entry_pathway where curriculum_version_id = p_source_id
    returning id, code
  )
  insert into _path_map (old_id, new_id)
  select src.id, copied.id
    from copied
    join entry_pathway src
      on src.curriculum_version_id = p_source_id and src.code = copied.code;

  insert into pathway_bridging_course (entry_pathway_id, course_id, is_credit_bearing)
  select pm.new_id, pb.course_id, pb.is_credit_bearing
    from pathway_bridging_course pb
    join _path_map pm on pm.old_id = pb.entry_pathway_id;

  -- ── เงื่อนไขจบ ─────────────────────────────────────────────────
  insert into graduation_rule
    (curriculum_version_id, kind, name_th, params, threshold, is_blocking, sort_order)
  select v_new, kind, name_th, params, threshold, is_blocking, sort_order
    from graduation_rule where curriculum_version_id = p_source_id;

  return v_new;
end $$;

comment on function clone_curriculum_version(uuid, smallint, smallint, smallint) is
  'ออกฉบับหลักสูตรใหม่จากฉบับเดิมทั้งก้อน พร้อม map uuid ของหมวดวิชา สมรรถนะ และเส้นทางเข้าใหม่ทั้งชุด — ฉบับใหม่เกิดเป็น draft เสมอ';

commit;

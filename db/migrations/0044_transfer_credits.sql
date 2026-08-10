-- ═══════════════════════════════════════════════════════════════════
-- 0044_transfer_credits.sql
--
-- ให้การตรวจจบนับหน่วยกิตเทียบโอนจากสถานศึกษาเดิม
--
-- ─── อาการเดิม ───
-- `evaluate_graduation()` นับเฉพาะรายวิชาที่เรียนที่นี่ (v_student_course_credit)
-- ส่วน `prior_academic_record` ที่งานทะเบียนอนุมัติเทียบโอนไปแล้ว ไม่ถูกนับเลย
-- สักหน่วยกิต ผลคือนักศึกษาเทียบโอนเห็นหน้าจอ "เส้นทางสู่การจบ" ว่ายังขาด
-- อีกหลายสิบหน่วยกิต ทั้งที่งานทะเบียนอนุมัติให้แล้ว
--
-- และเมื่อถึงเวลาจริง งานทะเบียนจะต้องอนุมัติจบด้วยมือโดยข้ามผลการตรวจ
-- ซึ่งแปลว่ากฎการจบทั้งชุดไม่ได้ถูกใช้กับคนกลุ่มนี้เลย
--
-- ─── นับเฉพาะที่อนุมัติแล้วเท่านั้น ───
-- `prior_academic_record` ถูกเขียนตอนนำเข้าข้อมูลหรือตอนรับเข้า ซึ่งเป็น
-- "สิ่งที่ผู้สมัครแจ้งมา" ยังไม่ใช่ "สิ่งที่วิทยาลัยรับรอง" การนับก่อนอนุมัติ
-- เท่ากับให้ผู้สมัครกรอกหน่วยกิตให้ตัวเองจนจบได้
--
-- เกณฑ์คือ `approved_at is not null` และ `earns_credit` เป็นจริง
--
-- ─── กฎสามข้อที่ต้องแก้ ───
-- 1. credits_total       บวกหน่วยกิตเทียบโอนเข้าไป
-- 2. credits_by_category ต้องรู้ว่าเทียบโอนเข้าหมวดไหน — ใช้ mapped_course_id
--    เทียบกับหมวดของรายวิชานั้นในฉบับหลักสูตรที่นักศึกษาสังกัด
-- 3. required_courses    รายวิชาบังคับที่เทียบโอนมาแล้วต้องไม่นับว่ายังขาด
--
-- ─── ที่ไม่แก้และเหตุผล ───
-- `gpax_min` ไม่นับเกรดเทียบโอน เพราะ `counts_in_gpa` ของระเบียนเหล่านั้น
-- เป็นเท็จตามระเบียบการเทียบโอน — หน่วยกิตโอนได้แต่เกรดไม่โอน
-- การเอามาเฉลี่ยจะทำให้ GPAX ของคนเทียบโอนคำนวณคนละสูตรกับคนอื่น
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- หน่วยกิตเทียบโอนที่อนุมัติแล้วของนักศึกษาคนหนึ่ง
--
-- แยกเป็นฟังก์ชันเพื่อให้ทั้งการตรวจจบและหน้าจออื่นใช้ตัวเลขชุดเดียวกัน
-- (หลักเดียวกับ v_behavior_balance — อย่าเขียนสูตรซ้ำสองที่)
-- ───────────────────────────────────────────────────────────────────
create or replace function transfer_credits_total(p_student_id uuid)
returns numeric
language sql stable as $$
  select coalesce(sum(pr.credits), 0)
    from prior_academic_record pr
   where pr.student_id = p_student_id
     and pr.earns_credit
     and pr.approved_at is not null
$$;

comment on function transfer_credits_total(uuid) is
  'หน่วยกิตเทียบโอนที่งานทะเบียนอนุมัติแล้ว — ที่ยังไม่อนุมัติไม่นับ เพราะเป็นสิ่งที่ผู้สมัครแจ้งมาเอง';

-- หน่วยกิตเทียบโอนแยกตามหมวดของหลักสูตร
--
-- เทียบเข้าหมวดผ่าน mapped_course_id — ระเบียนที่ยังไม่ได้จับคู่กับรายวิชา
-- ในหลักสูตรจะนับรวมในหน่วยกิตรวมได้ แต่ระบุหมวดไม่ได้ ซึ่งถูกต้องแล้ว
-- เพราะไม่มีใครรู้ว่ามันควรอยู่หมวดไหนจนกว่าจะมีคนจับคู่
create or replace function transfer_credits_by_category(
  p_student_id uuid,
  p_category_id uuid
) returns numeric
language sql stable as $$
  with recursive tree as (
    select cat.id as category_id, cat.id as source_category_id
      from curriculum_category cat
    union all
    select parent.id, t.source_category_id
      from tree t
      join curriculum_category child  on child.id = t.category_id
      join curriculum_category parent on parent.id = child.parent_id
  )
  select coalesce(sum(pr.credits), 0)
    from prior_academic_record pr
    join curriculum_course cc on cc.course_id = pr.mapped_course_id
    join tree t               on t.source_category_id = cc.curriculum_category_id
   where pr.student_id = p_student_id
     and pr.earns_credit
     and pr.approved_at is not null
     and t.category_id = p_category_id
$$;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจจบใหม่ — เหมือนเดิมทุกอย่าง ยกเว้นสามกฎที่นับเทียบโอนเพิ่ม
-- ───────────────────────────────────────────────────────────────────
create or replace function evaluate_graduation(p_student_id uuid)
returns table (
  rule_id     uuid,
  kind        graduation_rule_kind,
  name_th     text,
  required    numeric,
  achieved    numeric,
  satisfied   boolean,
  is_blocking boolean
)
language plpgsql stable as $$
declare
  v_cv    uuid;
  v_gpax  numeric;
begin
  select sc.curriculum_version_id into v_cv
  from student_curriculum sc
  where sc.student_id = p_student_id and sc.effective_to is null;

  if v_cv is null then
    return;
  end if;

  select ts.gpax into v_gpax
  from term_summary ts
  where ts.student_id = p_student_id
  order by ts.computed_at desc
  limit 1;

  return query
  select
    g.id,
    g.kind,
    g.name_th,
    g.threshold,
    a.achieved,
    -- กฎสามข้อล่างเป็น "จำนวนที่ยังค้าง" ยิ่งน้อยยิ่งดี เกณฑ์คือไม่เกิน threshold (ปกติ 0)
    -- ที่เหลือเป็น "สะสมได้เท่าไร" ต้องไม่น้อยกว่า threshold
    case when g.kind in ('cocurricular_all_terms', 'no_pending_grade', 'required_courses')
         then a.achieved <= coalesce(g.threshold, 0)
         else a.achieved >= coalesce(g.threshold, 0)
    end as satisfied,
    g.is_blocking
  from graduation_rule g
  cross join lateral (select (case g.kind

      when 'credits_total' then
        coalesce((select sum(v.credits_earned)
                  from v_student_course_credit v
                  where v.student_id = p_student_id and v.earns_credit), 0)
        -- หน่วยกิตที่เทียบโอนมาและอนุมัติแล้ว
        + transfer_credits_total(p_student_id)

      when 'credits_by_category' then
        coalesce((select c.credits_earned
                  from v_student_credits_by_category c
                  join curriculum_category cat on cat.id = c.category_id
                  where c.student_id = p_student_id
                    and cat.curriculum_version_id = v_cv
                    and cat.code = g.params ->> 'category_code'), 0)
        + coalesce((select transfer_credits_by_category(p_student_id, cat.id)
                    from curriculum_category cat
                    where cat.curriculum_version_id = v_cv
                      and cat.code = g.params ->> 'category_code'), 0)

      when 'gpax_min' then
        -- ไม่รวมเกรดเทียบโอนโดยตั้งใจ — หน่วยกิตโอนได้แต่เกรดไม่โอน
        coalesce(v_gpax, 0)

      when 'professional_standard' then
        (select count(*) from professional_standard_assessment a
         where a.student_id = p_student_id and a.result = 'pass')

      when 'cocurricular_all_terms' then
        -- จำนวนภาคเรียนที่ยังไม่ผ่าน ยิ่งน้อยยิ่งดี เกณฑ์คือ 0
        (select count(*) from cocurricular_result cr
         where cr.student_id = p_student_id and cr.result <> 'pass')

      when 'practicum_hours' then
        coalesce((select sum(p.hours) from practicum_log p
                  where p.student_id = p_student_id and p.verified_at is not null), 0)

      when 'no_pending_grade' then
        (select count(*) from v_student_course_credit v
         where v.student_id = p_student_id and v.is_provisional)

      when 'required_courses' then
        -- จำนวนรายวิชาบังคับที่ยังไม่ผ่าน เกณฑ์คือ 0
        (select count(*)
         from curriculum_course cc
         where cc.curriculum_version_id = v_cv
           and cc.requirement = 'required'
           and not exists (
             select 1 from v_student_course_credit v
             where v.student_id = p_student_id
               and v.course_id  = cc.course_id
               and v.earns_credit
           )
           -- รายวิชาบังคับที่เทียบโอนมาแล้วต้องไม่นับว่ายังขาด
           and not exists (
             select 1 from prior_academic_record pr
             where pr.student_id = p_student_id
               and pr.mapped_course_id = cc.course_id
               and pr.earns_credit
               and pr.approved_at is not null
           ))

      else 0
    end)::numeric as achieved) a
  where g.curriculum_version_id = v_cv
  order by g.sort_order;
end $$;

comment on function evaluate_graduation is
  'ตรวจจบแบบเรียกได้ทุกเมื่อ — นับหน่วยกิตเทียบโอนที่อนุมัติแล้วด้วย แต่ไม่นับเกรดเทียบโอนใน GPAX';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant execute on function transfer_credits_total(uuid)              to app_runtime;
    grant execute on function transfer_credits_by_category(uuid, uuid)  to app_runtime;
  end if;
end $$;

commit;

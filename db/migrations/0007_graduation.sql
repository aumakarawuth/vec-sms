-- ═══════════════════════════════════════════════════════════════════
-- 0007_graduation.sql
-- เงื่อนไขจบและการตรวจจบ
--
-- ตามระเบียบ ปวช./ปวส. นักศึกษาจะสำเร็จการศึกษาได้ต้องครบห้าข้อ
--   1. ได้หน่วยกิตสะสมครบตามโครงสร้างหลักสูตรทุกหมวด
--   2. ได้ค่าระดับคะแนนเฉลี่ยสะสมไม่ต่ำกว่า 2.00
--   3. ผ่านการประเมินมาตรฐานวิชาชีพ
--   4. เข้าร่วมกิจกรรมเสริมหลักสูตรและผ่านทุกภาคเรียน
--   5. ผ่านการฝึกประสบการณ์สมรรถนะวิชาชีพครบตามชั่วโมงที่กำหนด
--
-- เงื่อนไขเก็บเป็นข้อมูล ไม่ใช่โค้ด เพราะแต่ละฉบับหลักสูตรกำหนดไม่เหมือนกัน
-- และการตรวจจบต้องทำได้ทุกภาคเรียน ไม่ใช่รอปีสุดท้าย
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- การประเมินมาตรฐานวิชาชีพ
-- ───────────────────────────────────────────────────────────────────
create type assessment_result as enum ('pass', 'fail', 'absent', 'pending');

create table professional_standard_assessment (
  id                     uuid              primary key default gen_random_uuid(),
  student_id             uuid              not null references student            on delete restrict,
  curriculum_version_id  uuid              not null references curriculum_version on delete restrict,
  term_id                uuid              references term,
  round_no               smallint          not null default 1,   -- ครั้งที่ประเมิน รวมการสอบซ่อม
  theory_score           numeric(5,2),
  practice_score         numeric(5,2),
  result                 assessment_result not null default 'pending',
  assessed_on            date,
  committee_note         text,
  created_at             timestamptz       not null default now(),
  unique (student_id, curriculum_version_id, round_no)
);
create index on professional_standard_assessment (student_id) where result = 'pass';

-- ผลรายสมรรถนะ ใช้บอกว่าต้องซ่อมสมรรถนะไหน ไม่ใช่ซ่อมทั้งชุด
create table professional_standard_competency_result (
  id            uuid              primary key default gen_random_uuid(),
  assessment_id uuid              not null references professional_standard_assessment on delete cascade,
  competency_id uuid              not null references competency on delete restrict,
  result        assessment_result not null,
  score         numeric(5,2),
  unique (assessment_id, competency_id)
);

-- ───────────────────────────────────────────────────────────────────
-- กิจกรรมเสริมหลักสูตร — ต้องผ่านทุกภาคเรียน ไม่ใช่ผ่านรวม
-- นักศึกษาอาชีวะจำนวนมากไม่จบเพราะข้อนี้ข้อเดียว จึงต้องแสดงในแอปตลอด
-- ───────────────────────────────────────────────────────────────────
create table cocurricular_result (
  student_id         uuid              not null references student on delete cascade,
  term_id            uuid              not null references term    on delete cascade,
  activity_name      text              not null,   -- 'องค์การนักวิชาชีพในอนาคตแห่งประเทศไทย'
  sessions_required  smallint          not null default 0,
  sessions_attended  smallint          not null default 0,
  result             assessment_result not null default 'pending',
  evaluated_by       uuid,
  evaluated_at       timestamptz,
  primary key (student_id, term_id)
);

-- ───────────────────────────────────────────────────────────────────
-- ฝึกประสบการณ์สมรรถนะวิชาชีพ
-- ชั่วโมงจะนับเป็นทางการเมื่อครูฝึกในสถานประกอบการรับรองแล้วเท่านั้น
-- (โมดูลทวิภาคีเต็มรูปแบบอยู่ในเฟส 4 ตารางนี้เป็นแกนที่โมดูลนั้นจะต่อยอด)
-- ───────────────────────────────────────────────────────────────────
create type practicum_source as enum ('student_app', 'supervisor', 'teacher', 'import');

create table practicum_log (
  id             uuid             primary key default gen_random_uuid(),
  student_id     uuid             not null references student on delete cascade,
  enrollment_id  uuid             references enrollment,          -- ผูกกับรายวิชาฝึกประสบการณ์
  worked_on      date             not null,
  hours          numeric(4,1)     not null check (hours > 0 and hours <= 24),
  workplace_id   uuid,                                            -- โมดูล M07 จะเพิ่ม FK ภายหลัง
  description    text,
  source         practicum_source not null default 'student_app',
  checkin_at     timestamptz,
  checkin_lat    numeric(9,6),                                    -- บันทึกเฉพาะขณะเช็คอิน ไม่ติดตามต่อเนื่อง
  checkin_lng    numeric(9,6),
  photo_key      text,
  verified_by    uuid,                                            -- person_id ของครูฝึก
  verified_at    timestamptz,
  created_at     timestamptz      not null default now(),
  unique (student_id, worked_on)
);
create index on practicum_log (student_id) where verified_at is not null;

comment on column practicum_log.verified_at is
  'ชั่วโมงที่ยังไม่รับรองจะไม่ถูกนับในการตรวจจบ แต่แสดงในแอปเป็นยอดรอรับรอง';

-- ───────────────────────────────────────────────────────────────────
-- กฎการจบ — เก็บเป็นข้อมูล
-- ───────────────────────────────────────────────────────────────────
create type graduation_rule_kind as enum (
  'credits_total',           -- หน่วยกิตรวมขั้นต่ำ
  'credits_by_category',     -- หน่วยกิตขั้นต่ำรายหมวด   params: {"category_code":"..."}
  'required_courses',        -- ต้องผ่านรายวิชาบังคับทุกวิชา
  'gpax_min',                -- GPAX ขั้นต่ำ
  'professional_standard',   -- ผ่านการประเมินมาตรฐานวิชาชีพ
  'cocurricular_all_terms',  -- กิจกรรมเสริมหลักสูตรผ่านทุกภาคเรียน
  'practicum_hours',         -- ชั่วโมงฝึกประสบการณ์ที่รับรองแล้ว
  'no_pending_grade'         -- ไม่มี ม.ส. หรือ ข.ส. ค้าง
);

create table graduation_rule (
  id                    uuid                 primary key default gen_random_uuid(),
  curriculum_version_id uuid                 not null references curriculum_version on delete cascade,
  kind                  graduation_rule_kind not null,
  name_th               text                 not null,
  params                jsonb                not null default '{}'::jsonb,
  threshold             numeric(6,2),
  is_blocking           boolean              not null default true,
  sort_order            smallint             not null default 0
);
create index on graduation_rule (curriculum_version_id);

-- ───────────────────────────────────────────────────────────────────
-- หน่วยกิตสะสมของนักศึกษา แยกตามหมวดของหลักสูตรที่ตนสังกัด
-- ───────────────────────────────────────────────────────────────────
create view v_student_course_credit as
select
  e.student_id,
  sc.curriculum_version_id,
  cc.curriculum_category_id,
  cs.course_id,
  e.counts_toward_gpa,
  er.credits_earned,
  er.grade_point,
  gs.earns_credit,
  gs.is_provisional
from enrollment e
join class_section        cs on cs.id = e.class_section_id
join enrollment_result    er on er.enrollment_id = e.id and er.superseded_by is null
join grade_symbol         gs on gs.id = er.grade_symbol_id
join student_curriculum   sc on sc.student_id = e.student_id and sc.effective_to is null
left join curriculum_course cc
       on cc.curriculum_version_id = sc.curriculum_version_id
      and cc.course_id             = cs.course_id
where e.status in ('enrolled', 'credit_transfer');

-- รวมหน่วยกิตขึ้นไปตามต้นไม้หมวดวิชา
create view v_student_credits_by_category as
with recursive tree as (
  -- ใบ: หมวดที่รายวิชาผูกอยู่โดยตรง
  select cat.id as category_id, cat.id as source_category_id, cat.curriculum_version_id
  from curriculum_category cat
  union all
  -- ไต่ขึ้นหาแม่
  select parent.id, t.source_category_id, t.curriculum_version_id
  from tree t
  join curriculum_category child  on child.id = t.category_id
  join curriculum_category parent on parent.id = child.parent_id
)
select
  scc.student_id,
  t.category_id,
  sum(scc.credits_earned) filter (where scc.earns_credit) as credits_earned
from v_student_course_credit scc
join tree t on t.source_category_id = scc.curriculum_category_id
group by scc.student_id, t.category_id;

-- ───────────────────────────────────────────────────────────────────
-- ประเมินเงื่อนไขจบ — เรียกได้ทุกเมื่อ ไม่ต้องรอปีสุดท้าย
-- คืนค่าเป็นแถวละหนึ่งกฎ พร้อมความคืบหน้าเป็นตัวเลข เพื่อให้แอปนักศึกษา
-- แสดงเป็นแถบความคืบหน้าได้ตรง ๆ
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

      when 'credits_by_category' then
        coalesce((select c.credits_earned
                  from v_student_credits_by_category c
                  join curriculum_category cat on cat.id = c.category_id
                  where c.student_id = p_student_id
                    and cat.curriculum_version_id = v_cv
                    and cat.code = g.params ->> 'category_code'), 0)

      when 'gpax_min' then
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
           ))

      else 0
    end)::numeric as achieved) a
  where g.curriculum_version_id = v_cv
  order by g.sort_order;
end $$;

comment on function evaluate_graduation is
  'ตรวจจบแบบเรียกได้ทุกเมื่อ ใช้ทั้งในแอปนักศึกษา (หน้าเส้นทางสู่การจบ) และงานทะเบียนตอนออก รบ.1';

-- สแนปช็อตผลการตรวจจบ เก็บไว้เพื่อทำรายงานและดูย้อนหลัง
create table student_graduation_status (
  student_id  uuid        not null references student on delete cascade,
  rule_id     uuid        not null references graduation_rule on delete cascade,
  required    numeric,
  achieved    numeric,
  satisfied   boolean,
  evaluated_at timestamptz not null default now(),
  primary key (student_id, rule_id)
);

commit;

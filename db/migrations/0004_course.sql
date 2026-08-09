-- ═══════════════════════════════════════════════════════════════════
-- 0004_course.sql
-- รายวิชา · การผูกเข้าหลักสูตร · วิชาบังคับก่อน · สมรรถนะรายวิชา
--
-- การตัดสินใจที่สำคัญ
-- หน่วยกิตอาชีวะไม่ได้คิดเหมือนสามัญ ทฤษฎี 1 ชม./สัปดาห์ = 1 นก. แต่
-- ปฏิบัติ 2–3 ชม./สัปดาห์ = 1 นก. และรายวิชาฝึกประสบการณ์คิดเป็นชั่วโมง
-- สะสม จึงต้องเก็บ ชม.ทฤษฎี ชม.ปฏิบัติ และหน่วยกิต แยกจากกันสามคอลัมน์
-- ไม่ใช่ credits ตัวเดียว เพราะตัวเลขสามชุดนี้ถูกใช้คนละที่:
--   ชม.ทฤษฎี+ปฏิบัติ → จัดตารางสอนและคิดภาระงานครู
--   หน่วยกิต         → ตรวจจบและคิด GPA
--   ชั่วโมงรวม       → เบิกวัสดุฝึกและนับชั่วโมงฝึกงาน
-- ═══════════════════════════════════════════════════════════════════
begin;

create type grading_mode as enum ('point', 'pass_fail');
comment on type grading_mode is
  'point = ให้ระดับผลการเรียน 0–4 · pass_fail = ผ่าน/ไม่ผ่าน ใช้กับกิจกรรมเสริมหลักสูตรและบางรายวิชา';

create table course (
  id                 uuid         primary key default gen_random_uuid(),
  institution_id     uuid         not null references institution on delete restrict,

  -- รหัสวิชาผูกกับฉบับหลักสูตร รหัสเดียวกันในหลักสูตรคนละฉบับคือคนละรายวิชา
  -- เช่น 20101-2003 ของฉบับ 2562 กับฉบับ 2567 อาจมีหน่วยกิตไม่เท่ากัน
  edition_be         smallint     not null,
  code               text         not null,        -- '20101-2003'
  name_th            text         not null,
  name_en            text,

  theory_hours       smallint     not null default 0,   -- ชม./สัปดาห์
  practice_hours     smallint     not null default 0,   -- ชม./สัปดาห์
  self_study_hours   smallint     not null default 0,
  credits            numeric(3,1) not null,
  total_hours        smallint,                          -- ชั่วโมงรวมทั้งภาค ใช้กับฝึกประสบการณ์
  weekly_periods     smallint generated always as (theory_hours + practice_hours) stored,

  grading_mode       grading_mode not null default 'point',
  is_practicum       boolean      not null default false,  -- ฝึกประสบการณ์สมรรถนะวิชาชีพ
  is_project         boolean      not null default false,  -- โครงงานพัฒนาสมรรถนะวิชาชีพ
  needs_workshop     boolean      not null default false,  -- ต้องใช้โรงฝึกงาน/ห้องปฏิบัติการ
  material_cost      numeric(9,2) not null default 0,      -- ต้นทุนวัสดุฝึกต่อหัวโดยประมาณ

  active             boolean      not null default true,
  created_at         timestamptz  not null default now(),
  updated_at         timestamptz  not null default now(),

  unique (institution_id, edition_be, code),
  check (credits >= 0),
  check (theory_hours >= 0 and practice_hours >= 0)
);
create trigger course_touch before update on course
  for each row execute function set_updated_at();

comment on column course.material_cost is
  'ใช้คิดต้นทุนต่อหัวรายสาขา ซึ่งเป็นตัวเลขที่ผู้บริหารเอกชนใช้ตัดสินใจเปิด-ปิดสาขา';
comment on column course.total_hours is
  'ใช้กับรายวิชาฝึกประสบการณ์ที่วัดเป็นชั่วโมงสะสม เช่น 320 ชม. ไม่ใช่คาบต่อสัปดาห์';

-- ───────────────────────────────────────────────────────────────────
-- รายวิชาในหลักสูตร
-- ตารางเชื่อมนี้คือจุดที่บอกว่า "รายวิชานี้อยู่หมวดไหนของหลักสูตรฉบับไหน
-- และเป็นวิชาบังคับหรือเลือก" ซึ่งเป็นข้อมูลที่การตรวจจบใช้ทั้งหมด
-- ───────────────────────────────────────────────────────────────────
create type requirement_kind as enum ('required', 'elective');

create table curriculum_course (
  id                      uuid             primary key default gen_random_uuid(),
  curriculum_version_id   uuid             not null references curriculum_version  on delete cascade,
  curriculum_category_id  uuid             not null references curriculum_category on delete cascade,
  course_id               uuid             not null references course              on delete restrict,
  requirement             requirement_kind not null default 'required',
  suggested_year          smallint         check (suggested_year between 1 and 4),
  suggested_term          smallint         check (suggested_term between 1 and 3),
  sort_order              smallint         not null default 0,
  unique (curriculum_version_id, course_id)
);
create index on curriculum_course (curriculum_category_id);
create index on curriculum_course (course_id);

comment on column curriculum_course.suggested_year is
  'แผนการเรียนแนะนำ ใช้สร้างแผนรายบุคคลตอนมอบตัวและใช้เตือนเมื่อนักศึกษาเรียนไม่ตามแผน';

-- ───────────────────────────────────────────────────────────────────
-- วิชาบังคับก่อน
-- ผูกกับฉบับหลักสูตร เพราะเงื่อนไขบังคับก่อนเปลี่ยนได้ระหว่างฉบับ
-- ───────────────────────────────────────────────────────────────────
create type prerequisite_kind as enum (
  'must_pass',    -- ต้องผ่านรายวิชานั้นก่อน
  'must_enroll',  -- ต้องเคยลงทะเบียนแล้ว (ผ่านหรือไม่ผ่านก็ได้)
  'concurrent'    -- ลงทะเบียนพร้อมกันได้
);

create table course_prerequisite (
  id                     uuid              primary key default gen_random_uuid(),
  curriculum_version_id  uuid              not null references curriculum_version on delete cascade,
  course_id              uuid              not null references course on delete cascade,
  prerequisite_course_id uuid              not null references course on delete restrict,
  kind                   prerequisite_kind not null default 'must_pass',
  unique (curriculum_version_id, course_id, prerequisite_course_id),
  check (course_id <> prerequisite_course_id)
);

-- ───────────────────────────────────────────────────────────────────
-- สมรรถนะรายวิชา
-- ใช้สามทาง: วัดผลตามสมรรถนะในชั้นเรียน · แผนการฝึกอาชีพของทวิภาคี
-- และการประเมินมาตรฐานวิชาชีพตอนจบ
-- ───────────────────────────────────────────────────────────────────
create table course_competency (
  id                     uuid    primary key default gen_random_uuid(),
  curriculum_version_id  uuid    not null references curriculum_version on delete cascade,
  course_id              uuid    not null references course     on delete cascade,
  competency_id          uuid    not null references competency on delete cascade,
  is_primary             boolean not null default false,
  unique (curriculum_version_id, course_id, competency_id)
);

-- ───────────────────────────────────────────────────────────────────
-- รายวิชาปรับพื้นฐานตามเส้นทางเข้าศึกษา
-- ───────────────────────────────────────────────────────────────────
create table pathway_bridging_course (
  id                 uuid    primary key default gen_random_uuid(),
  entry_pathway_id   uuid    not null references entry_pathway on delete cascade,
  course_id          uuid    not null references course        on delete restrict,
  is_credit_bearing  boolean not null default false,  -- ปกติไม่นับหน่วยกิตสะสม
  unique (entry_pathway_id, course_id)
);
comment on column pathway_bridging_course.is_credit_bearing is
  'รายวิชาปรับพื้นฐานส่วนใหญ่ไม่นับหน่วยกิตและไม่คิด GPA แต่บังคับให้ผ่าน';

-- ───────────────────────────────────────────────────────────────────
-- มุมมองสรุปโครงสร้างหน่วยกิตของแต่ละฉบับหลักสูตร
-- ใช้ตรวจสอบตอนอนุมัติหลักสูตรว่าหน่วยกิตที่กำหนดไว้กับรายวิชาที่ใส่จริงตรงกันไหม
-- ───────────────────────────────────────────────────────────────────
create view v_curriculum_structure as
select
  cc.curriculum_version_id,
  cat.id                       as category_id,
  cat.code                     as category_code,
  cat.name_th                  as category_name,
  cat.kind                     as category_kind,
  cat.min_credits              as required_credits,
  count(*) filter (where cc.requirement = 'required') as required_course_count,
  count(*) filter (where cc.requirement = 'elective') as elective_course_count,
  sum(c.credits) filter (where cc.requirement = 'required') as required_credit_sum,
  sum(c.credits)                                            as offered_credit_sum
from curriculum_course cc
join curriculum_category cat on cat.id = cc.curriculum_category_id
join course c                on c.id   = cc.course_id
group by cc.curriculum_version_id, cat.id;

comment on view v_curriculum_structure is
  'ถ้า required_credit_sum น้อยกว่า required_credits แปลว่าหลักสูตรใส่รายวิชาไม่ครบ ต้องเตือนก่อนอนุมัติ';

commit;

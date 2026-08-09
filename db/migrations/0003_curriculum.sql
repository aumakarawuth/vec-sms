-- ═══════════════════════════════════════════════════════════════════
-- 0003_curriculum.sql
-- แกนหลักสูตรฐานสมรรถนะแบบมีเวอร์ชัน — ไฟล์ที่สำคัญที่สุดของทั้งระบบ
--
-- ปัญหาที่ต้องแก้
-- ในปีการศึกษาหนึ่ง วิทยาลัยจะมี ปวช.1 อยู่ภายใต้หลักสูตรฉบับใหม่
-- ขณะที่ ปวช.3 ยังอยู่ภายใต้ฉบับเดิม การตรวจจบ การออก รบ.1 และการคิด
-- หน่วยกิต ต้องอิงฉบับที่นักศึกษาคนนั้นเข้าศึกษา ห้ามใช้โครงสร้างเดียว
-- ทั้งวิทยาลัยเด็ดขาด เพราะจะทำให้เอกสารย้อนหลังผิดทั้งหมด
--
-- โครงสร้าง
--   ประเภทวิชา → สาขาวิชา → สาขางาน → หลักสูตร → เวอร์ชันหลักสูตร
--                                                    ├─ หมวด/กลุ่มวิชา (ต้นไม้)
--                                                    ├─ รายวิชาในหลักสูตร
--                                                    ├─ สมรรถนะ
--                                                    └─ เส้นทางเข้าศึกษา
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ระดับคุณวุฒิ
create type qualification_level as enum ('PVC', 'PVS', 'TVB');
comment on type qualification_level is 'PVC = ปวช. · PVS = ปวส. · TVB = ปริญญาตรีสายเทคโนโลยี';

-- ───────────────────────────────────────────────────────────────────
-- การจัดหมวดตามโครงสร้างของ สอศ.
-- ───────────────────────────────────────────────────────────────────
create table program_type (               -- ประเภทวิชา
  id              uuid     primary key default gen_random_uuid(),
  institution_id  uuid     not null references institution on delete restrict,
  code            text     not null,      -- '01'
  name_th         text     not null,      -- 'อุตสาหกรรม'
  sort_order      smallint not null default 0,
  unique (institution_id, code)
);

create table program (                    -- สาขาวิชา
  id              uuid                primary key default gen_random_uuid(),
  institution_id  uuid                not null references institution  on delete restrict,
  program_type_id uuid                not null references program_type on delete restrict,
  level           qualification_level not null,
  code            text                not null,   -- '20101'
  name_th         text                not null,   -- 'ช่างยนต์'
  name_en         text,
  active          boolean             not null default true,
  unique (institution_id, level, code)
);

create table program_track (              -- สาขางาน
  id          uuid    primary key default gen_random_uuid(),
  program_id  uuid    not null references program on delete restrict,
  code        text    not null,           -- '20101010'
  name_th     text    not null,           -- 'ยานยนต์'
  active      boolean not null default true,
  unique (program_id, code)
);
comment on table program_track is
  'สาขางาน — เป็นหน่วยที่ผูกกับหลักสูตรจริง เพราะสาขาวิชาเดียวกันอาจมีหลายสาขางานที่โครงสร้างหน่วยกิตต่างกัน';

-- ───────────────────────────────────────────────────────────────────
-- หลักสูตรและเวอร์ชัน
-- ───────────────────────────────────────────────────────────────────
create table curriculum (
  id                uuid        primary key default gen_random_uuid(),
  institution_id    uuid        not null references institution   on delete restrict,
  program_track_id  uuid        not null references program_track on delete restrict,
  name_th           text        not null,
  created_at        timestamptz not null default now(),
  unique (institution_id, program_track_id)
);

create type curriculum_status as enum ('draft', 'active', 'retired');

create table curriculum_version (
  id                      uuid              primary key default gen_random_uuid(),
  curriculum_id           uuid              not null references curriculum on delete restrict,

  -- ปีของฉบับหลักสูตร เช่น 2562 หรือ 2567
  edition_be              smallint          not null check (edition_be between 2500 and 2700),

  -- ช่วงปีที่เข้าศึกษาที่ฉบับนี้บังคับใช้ — นี่คือกุญแจของการทำเวอร์ชัน
  -- นักศึกษาที่ admitted_year_be อยู่ในช่วงนี้ จะถูกตรวจจบด้วยฉบับนี้ตลอดไป
  effective_from_year_be  smallint          not null,
  effective_to_year_be    smallint,         -- null = ยังบังคับใช้อยู่

  grade_scheme_id         uuid,             -- ระเบียบวัดผลที่ผูกอยู่ (FK เพิ่มใน 0006)

  min_total_credits       numeric(5,1)      not null,          -- ปวช. ไม่ต่ำกว่า 103 นก.
  min_gpax                numeric(3,2)      not null default 2.00,
  min_practicum_hours     smallint,                            -- ฝึกประสบการณ์ เช่น 320 ชม.
  requires_prof_standard  boolean           not null default true,  -- ต้องผ่านการประเมินมาตรฐานวิชาชีพ
  requires_all_activity   boolean           not null default true,  -- กิจกรรมเสริมหลักสูตรต้องผ่านทุกภาคเรียน
  normal_duration_terms   smallint          not null default 6,

  status                  curriculum_status not null default 'draft',
  approved_at             timestamptz,
  approved_by             uuid references staff,
  created_at              timestamptz       not null default now(),
  updated_at              timestamptz       not null default now(),

  unique (curriculum_id, edition_be),
  check (effective_to_year_be is null or effective_to_year_be >= effective_from_year_be),

  -- ห้ามมีสองฉบับที่ครอบคลุมปีเข้าศึกษาเดียวกัน มิฉะนั้นระบบจะเลือกฉบับไม่ได้
  -- ฉบับที่ยังเป็น draft ได้รับการยกเว้นเพื่อให้ร่างฉบับถัดไปคู่ขนานได้
  constraint curriculum_version_no_overlap exclude using gist (
    curriculum_id with =,
    int4range(effective_from_year_be, coalesce(effective_to_year_be, 9999), '[]') with &&
  ) where (status <> 'draft')
);
create trigger curriculum_version_touch before update on curriculum_version
  for each row execute function set_updated_at();

comment on constraint curriculum_version_no_overlap on curriculum_version is
  'กันไม่ให้ปีเข้าศึกษาหนึ่งปีตกอยู่ใต้หลักสูตรสองฉบับพร้อมกัน';

-- ฟังก์ชันเลือกฉบับหลักสูตรจากปีที่เข้าศึกษา
create or replace function curriculum_version_for(p_curriculum_id uuid, p_year_be smallint)
returns uuid language sql stable as $$
  select cv.id
  from curriculum_version cv
  where cv.curriculum_id = p_curriculum_id
    and cv.status = 'active'
    and p_year_be between cv.effective_from_year_be
                      and coalesce(cv.effective_to_year_be, 9999)
  limit 1
$$;

-- ───────────────────────────────────────────────────────────────────
-- หมวดและกลุ่มวิชา — เก็บเป็นต้นไม้เพราะโครงสร้างอาชีวะซ้อนสองชั้น
--   หมวดวิชาสมรรถนะวิชาชีพ
--     ├─ กลุ่มสมรรถนะวิชาชีพพื้นฐาน
--     ├─ กลุ่มสมรรถนะวิชาชีพเฉพาะ
--     ├─ กลุ่มสมรรถนะวิชาชีพเลือก
--     ├─ ฝึกประสบการณ์สมรรถนะวิชาชีพ
--     └─ โครงงานพัฒนาสมรรถนะวิชาชีพ
-- ───────────────────────────────────────────────────────────────────
create type category_kind as enum (
  'core_competency',  -- หมวดวิชาสมรรถนะแกนกลาง
  'vocational',       -- หมวดวิชาสมรรถนะวิชาชีพ (โหนดแม่)
  'voc_basic',        -- กลุ่มสมรรถนะวิชาชีพพื้นฐาน
  'voc_specific',     -- กลุ่มสมรรถนะวิชาชีพเฉพาะ
  'voc_elective',     -- กลุ่มสมรรถนะวิชาชีพเลือก
  'practicum',        -- ฝึกประสบการณ์สมรรถนะวิชาชีพ
  'project',          -- โครงงานพัฒนาสมรรถนะวิชาชีพ
  'free_elective',    -- หมวดวิชาเลือกเสรี
  'activity'          -- กิจกรรมเสริมหลักสูตร
);

create table curriculum_category (
  id                    uuid          primary key default gen_random_uuid(),
  curriculum_version_id uuid          not null references curriculum_version on delete cascade,
  parent_id             uuid          references curriculum_category on delete cascade,
  kind                  category_kind not null,
  code                  text          not null,
  name_th               text          not null,
  min_credits           numeric(5,1)  not null default 0,
  max_credits           numeric(5,1),
  sort_order            smallint      not null default 0,
  unique (curriculum_version_id, code),
  check (max_credits is null or max_credits >= min_credits)
);
create index on curriculum_category (curriculum_version_id, parent_id);

comment on column curriculum_category.min_credits is
  'เกณฑ์หน่วยกิตขั้นต่ำของหมวด ใช้เป็นกฎตรวจจบโดยตรง ไม่ต้องเขียนกฎซ้ำในโค้ด';

-- ───────────────────────────────────────────────────────────────────
-- สมรรถนะ — จำเป็นสำหรับหลักสูตรฐานสมรรถนะ ทวิภาคี และการประเมิน
-- มาตรฐานวิชาชีพ ทั้งสามอย่างอ้างถึงชุดสมรรถนะเดียวกัน
-- ───────────────────────────────────────────────────────────────────
create table competency (
  id                    uuid     primary key default gen_random_uuid(),
  curriculum_version_id uuid     not null references curriculum_version on delete cascade,
  code                  text     not null,
  statement_th          text     not null,
  sort_order            smallint not null default 0,
  unique (curriculum_version_id, code)
);

-- ───────────────────────────────────────────────────────────────────
-- เส้นทางเข้าศึกษา
-- ปวส. รับจาก ปวช.ตรงสาขา / ปวช.ต่างสาขา / ม.6 ซึ่งแต่ละทางต้องเรียน
-- รายวิชาปรับพื้นฐานไม่เท่ากัน ต้องคำนวณแผนการเรียนรายบุคคลตั้งแต่วันมอบตัว
-- ───────────────────────────────────────────────────────────────────
create table entry_pathway (
  id                     uuid         primary key default gen_random_uuid(),
  curriculum_version_id  uuid         not null references curriculum_version on delete cascade,
  code                   text         not null,   -- 'PVC_SAME' | 'PVC_DIFF' | 'M6' | 'TRANSFER'
  name_th                text         not null,
  extra_min_credits      numeric(5,1) not null default 0,
  note                   text,
  unique (curriculum_version_id, code)
);

-- ───────────────────────────────────────────────────────────────────
-- นักศึกษาผูกกับฉบับหลักสูตร
-- เก็บเป็นประวัติ ไม่ใช่คอลัมน์เดียวบน student เพราะการย้ายแผนการเรียน
-- และการเทียบโอนทำให้ผูกใหม่ได้ และต้องรู้ย้อนหลังว่าเคยอยู่ฉบับไหน
-- ───────────────────────────────────────────────────────────────────
create table student_curriculum (
  id                     uuid        primary key default gen_random_uuid(),
  student_id             uuid        not null references student          on delete cascade,
  curriculum_version_id  uuid        not null references curriculum_version on delete restrict,
  entry_pathway_id       uuid        references entry_pathway,
  effective_from         date        not null default current_date,
  effective_to           date,
  reason                 text,                     -- ย้ายแผนการเรียน / เทียบโอน / แก้ไขข้อมูล
  created_at             timestamptz not null default now(),
  check (effective_to is null or effective_to > effective_from)
);
create unique index student_curriculum_current
  on student_curriculum (student_id) where effective_to is null;
create index on student_curriculum (curriculum_version_id);

comment on index student_curriculum_current is
  'นักศึกษาหนึ่งคนมีหลักสูตรที่ยังใช้อยู่ได้เพียงหนึ่งฉบับ ณ เวลาหนึ่ง';

commit;

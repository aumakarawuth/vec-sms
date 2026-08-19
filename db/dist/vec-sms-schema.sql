-- ═══════════════════════════════════════════════════════════════════
-- ระบบบริหารวิทยาลัยอาชีวศึกษาเอกชน — โครงสร้างฐานข้อมูล
-- แกนหลักสูตรฐานสมรรถนะ · การวัดผลตามระเบียบ ปวช./ปวส. · การลงทะเบียน
--
-- migration ล่าสุด  0072
-- ลายนิ้วมือต้นทาง  9539b91a421b7786
-- ต้องการ           PostgreSQL 14 ขึ้นไป (ใช้ pgcrypto และ btree_gist)
--
-- ไฟล์นี้มีเฉพาะโครงสร้าง ไม่มีข้อมูลใด ๆ ใช้กับระบบจริง
--
-- วิธีนำเข้า
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f <ไฟล์นี้>
--   หรือวางทั้งไฟล์ลงใน pgAdmin / DBeaver / Supabase SQL Editor
--
-- ไฟล์นี้สร้างจาก db/build.sh อย่าแก้โดยตรง ให้แก้ที่ db/migrations/ แล้ว build ใหม่
-- ═══════════════════════════════════════════════════════════════════



-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0000_migrations.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0000_migrations.sql
-- ตารางติดตามว่า migration ไหนถูกใช้ไปแล้ว
--
-- ต้องมีตัวนี้ก่อนทุกอย่าง เพราะการ deploy จริงคือการ "เติมส่วนที่ยังไม่มี"
-- ลงฐานข้อมูลที่มีข้อมูลอยู่แล้ว ไม่ใช่การสร้างใหม่ทั้งก้อน
--
-- เก็บ checksum ไว้ด้วย เพื่อจับกรณีที่มีคนแก้ไฟล์ migration ที่ deploy
-- ไปแล้ว ซึ่งจะทำให้ฐานข้อมูลแต่ละเครื่องไม่ตรงกันโดยไม่มีใครรู้
-- ═══════════════════════════════════════════════════════════════════

create table if not exists schema_migrations (
  version     text        primary key,
  checksum    text        not null,
  applied_at  timestamptz not null default now(),
  applied_by  text        not null default current_user,
  duration_ms integer
);

comment on table schema_migrations is
  'บันทึกว่า migration ไหนถูกใช้ไปแล้ว deploy.sh อ่านตารางนี้เพื่อข้ามไฟล์ที่ทำไปแล้ว';
comment on column schema_migrations.checksum is
  'SHA-256 ของไฟล์ ณ เวลาที่ใช้ ถ้าไฟล์ถูกแก้ทีหลัง deploy.sh จะหยุดและแจ้งเตือน';


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0001_foundation.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0001_foundation.sql
-- รากฐาน: ส่วนขยาย · สถานศึกษา (tenant) · ปฏิทินการศึกษา · ฟังก์ชันช่วย
-- PostgreSQL 16
-- ═══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pgcrypto;    -- gen_random_uuid()
create extension if not exists btree_gist;  -- exclusion constraint บนช่วงปีการศึกษา

-- ───────────────────────────────────────────────────────────────────
-- สถานศึกษา — ขอบเขตการแยกข้อมูลของทั้งระบบ
-- ทุกตารางที่มีข้อมูลของสถานศึกษาต้องมี institution_id เพื่อให้ RLS ทำงาน
-- ───────────────────────────────────────────────────────────────────
create table institution (
  id          uuid primary key default gen_random_uuid(),
  code        text        not null unique,   -- รหัสสถานศึกษา 10 หลักของ สอศ.
  name_th     text        not null,
  name_en     text,
  sector      text        not null default 'private'
              check (sector in ('private', 'public')),
  timezone    text        not null default 'Asia/Bangkok',
  created_at  timestamptz not null default now()
);
comment on table  institution is 'สถานศึกษา — เป็น tenant ของระบบ ใช้แยกข้อมูลด้วย Row-Level Security';
comment on column institution.code is 'รหัสสถานศึกษาตามระบบของ สอศ. ใช้เป็นกุญแจตอนส่งข้อมูลเข้า ศธ.02';

-- ───────────────────────────────────────────────────────────────────
-- ปฏิทินการศึกษา
-- ปีการศึกษาเก็บเป็นพุทธศักราชเสมอ เพราะทุกเอกสารราชการใช้ พ.ศ.
-- และการแปลงไปมาระหว่าง ค.ศ./พ.ศ. คือแหล่งบั๊กที่พบบ่อยที่สุดในระบบไทย
-- ───────────────────────────────────────────────────────────────────
create table academic_year (
  id              uuid     primary key default gen_random_uuid(),
  institution_id  uuid     not null references institution on delete restrict,
  year_be         smallint not null check (year_be between 2500 and 2700),
  starts_on       date     not null,
  ends_on         date     not null,
  unique (institution_id, year_be),
  check (ends_on > starts_on)
);
comment on column academic_year.year_be is 'ปีการศึกษาเป็น พ.ศ. เช่น 2569';

create type term_kind   as enum ('regular', 'summer');
create type term_status as enum ('planning', 'registration', 'open', 'grading', 'closed');

create table term (
  id                uuid        primary key default gen_random_uuid(),
  academic_year_id  uuid        not null references academic_year on delete restrict,
  ordinal           smallint    not null check (ordinal between 1 and 3),
  kind              term_kind   not null default 'regular',
  starts_on         date        not null,
  ends_on           date        not null,
  add_drop_ends_on  date,       -- วันสุดท้ายของการเพิ่ม-ถอนรายวิชา
  withdraw_ends_on  date,       -- วันสุดท้ายของการถอนแบบติด ถ.น.
  grade_due_on      date,       -- กำหนดส่งเกรด ใช้ตั้งเตือนอัตโนมัติ
  status            term_status not null default 'planning',
  unique (academic_year_id, ordinal),
  check (ends_on > starts_on)
);
comment on column term.status is
  'planning → registration → open → grading → closed ; เมื่อ closed แล้วห้ามแก้ผลการเรียนโดยตรง ต้องผ่านคำร้องแก้เกรด';

-- ───────────────────────────────────────────────────────────────────
-- ฟังก์ชันช่วย
-- ───────────────────────────────────────────────────────────────────
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ผู้ใช้ปัจจุบันและสถานศึกษาปัจจุบัน — ชั้นแอปตั้งค่าผ่าน SET LOCAL ทุก transaction
-- ค่าเหล่านี้เป็นฐานของ Row-Level Security ทั้งหมด (ดู 0008_rls.sql)
create or replace function current_actor_id() returns uuid
language sql stable as $$
  select nullif(current_setting('app.actor_id', true), '')::uuid
$$;

create or replace function current_institution_id() returns uuid
language sql stable as $$
  select nullif(current_setting('app.institution_id', true), '')::uuid
$$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0002_person_student.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0002_person_student.sql
-- ชั้นบุคคล: person แยกจาก role
--
-- การตัดสินใจที่สำคัญที่สุดของไฟล์นี้
-- คนหนึ่งคนอาจเป็นทั้งครู ผู้ปกครอง และศิษย์เก่าในสถานศึกษาเดียวกัน
-- ระบบที่ออกแบบเป็นตาราง students / teachers แยกขาดจากกัน จะเจอข้อมูลซ้ำ
-- และแก้ไม่ได้ตลอดอายุระบบ จึงแยก "คน" ออกจาก "บทบาท" ตั้งแต่วันแรก
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บุคคล
-- เลขบัตรประชาชนเป็นข้อมูลส่วนบุคคลที่ต้องเข้ารหัสระดับฟิลด์
-- เก็บสองคอลัมน์: ciphertext สำหรับอ่านกลับ และ hash สำหรับค้นหา/กันซ้ำ
-- คีย์ถอดรหัสอยู่ใน KMS ไม่อยู่ในฐานข้อมูล
-- ───────────────────────────────────────────────────────────────────
create type gender_kind as enum ('male', 'female', 'other', 'undisclosed');

create table person (
  id                uuid        primary key default gen_random_uuid(),
  institution_id    uuid        not null references institution on delete restrict,
  national_id_enc   bytea,                    -- เลขบัตรประชาชน (เข้ารหัสแล้ว)
  national_id_hash  bytea,                    -- HMAC-SHA256 สำหรับค้นหาและกันซ้ำ
  passport_no_enc   bytea,                    -- สำหรับนักศึกษาต่างชาติ
  prefix_th         text,
  first_name_th     text        not null,
  last_name_th      text        not null,
  first_name_en     text,
  last_name_en      text,
  birth_date        date,
  gender            gender_kind not null default 'undisclosed',
  phone             text,
  email             text,
  photo_key         text,                     -- คีย์ใน object storage ไม่ใช่ URL
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (institution_id, national_id_hash)
);
create trigger person_touch before update on person
  for each row execute function set_updated_at();

comment on column person.national_id_hash is
  'ใช้ค้นหาและกันข้อมูลซ้ำโดยไม่ต้องถอดรหัส ห้าม index บน national_id_enc';

-- ───────────────────────────────────────────────────────────────────
-- บทบาท: นักศึกษา
-- ───────────────────────────────────────────────────────────────────
create type student_status as enum (
  'active',           -- กำลังศึกษา
  'on_leave',         -- ลาพักการเรียน
  'suspended',        -- พักการเรียนจากการลงโทษ
  'withdrawn',        -- ลาออก
  'transferred_out',  -- ย้ายสถานศึกษา
  'dismissed',        -- พ้นสภาพ
  'graduated'         -- สำเร็จการศึกษา
);

create table student (
  id                uuid           primary key default gen_random_uuid(),
  institution_id    uuid           not null references institution on delete restrict,
  person_id         uuid           not null references person      on delete restrict,
  student_code      text           not null,      -- 67201010001
  admitted_year_be  smallint       not null,      -- ปีการศึกษาที่เข้าศึกษา
  admitted_term_id  uuid           references term,
  status            student_status not null default 'active',
  status_since      date           not null default current_date,
  created_at        timestamptz    not null default now(),
  updated_at        timestamptz    not null default now(),
  unique (institution_id, student_code),
  unique (institution_id, person_id, admitted_year_be)
);
create trigger student_touch before update on student
  for each row execute function set_updated_at();

comment on column student.admitted_year_be is
  'ปีที่เข้าศึกษา — ใช้เลือกเวอร์ชันหลักสูตรที่นักศึกษาคนนี้อยู่ภายใต้ (ดู 0003)';

-- ประวัติการเปลี่ยนสถานะ — ห้าม UPDATE student.status โดยไม่บันทึกประวัติ
-- บังคับด้วย trigger ด้านล่าง เพราะข้อมูลนี้ใช้ยันจำนวนนักศึกษาที่ขอเงินอุดหนุน
create table student_status_history (
  id           uuid           primary key default gen_random_uuid(),
  student_id   uuid           not null references student on delete restrict,
  from_status  student_status,
  to_status    student_status not null,
  effective_on date           not null,
  reason       text,
  document_no  text,                       -- เลขที่คำสั่ง/หนังสือที่อ้างอิง
  actor_id     uuid,
  recorded_at  timestamptz    not null default now()
);
create index on student_status_history (student_id, effective_on desc);

create or replace function student_status_guard() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status then
    insert into student_status_history (student_id, from_status, to_status, effective_on, actor_id)
    values (new.id, old.status, new.status, coalesce(new.status_since, current_date), current_actor_id());
  end if;
  return new;
end $$;

create trigger student_status_audit after update of status on student
  for each row execute function student_status_guard();

-- ───────────────────────────────────────────────────────────────────
-- บทบาท: บุคลากร
-- ───────────────────────────────────────────────────────────────────
create type employment_kind as enum ('civil_servant', 'permanent', 'contract', 'part_time', 'industry_expert');

create table staff (
  id               uuid            primary key default gen_random_uuid(),
  institution_id   uuid            not null references institution on delete restrict,
  person_id        uuid            not null references person      on delete restrict,
  staff_code       text            not null,
  employment_kind  employment_kind not null default 'permanent',
  is_teacher       boolean         not null default true,
  license_no       text,                       -- ใบอนุญาตประกอบวิชาชีพครู
  license_expires  date,                       -- ใช้ตั้งเตือนก่อนหมดอายุ
  active           boolean         not null default true,
  created_at       timestamptz     not null default now(),
  unique (institution_id, staff_code)
);
comment on column staff.employment_kind is
  'industry_expert = ครูพิเศษจากสถานประกอบการ ซึ่งพบมากในอาชีวศึกษาและมักไม่มีใบอนุญาตประกอบวิชาชีพ';

-- ───────────────────────────────────────────────────────────────────
-- ความสัมพันธ์ผู้ปกครอง
-- แยกสิทธิ์การดูข้อมูลออกจากความสัมพันธ์ เพราะผู้ปกครองตามทะเบียนบ้าน
-- อาจไม่ใช่คนที่มีสิทธิ์ดูเกรดหรืออนุมัติการลา
-- ───────────────────────────────────────────────────────────────────
create type guardian_relation as enum ('father', 'mother', 'guardian', 'relative', 'other');

create table student_guardian (
  id                 uuid              primary key default gen_random_uuid(),
  student_id         uuid              not null references student on delete cascade,
  person_id          uuid              not null references person   on delete restrict,
  relation           guardian_relation not null,
  is_primary         boolean           not null default false,
  can_view_grades    boolean           not null default true,
  can_view_finance   boolean           not null default true,
  can_approve_leave  boolean           not null default false,
  verified_at        timestamptz,               -- ยืนยันตัวตนแล้วเมื่อไร (ThaID/บัตรประชาชน)
  created_at         timestamptz       not null default now(),
  unique (student_id, person_id)
);
create unique index on student_guardian (student_id) where is_primary;

comment on column student_guardian.verified_at is
  'ยังไม่ยืนยันตัวตน = ห้ามส่งข้อมูลตำแหน่งหรือผลการเรียนออกไป (มาตรการคุ้มครองผู้เยาว์)';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0003_curriculum.sql
-- ───────────────────────────────────────────────────────────────────

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


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0004_course.sql
-- ───────────────────────────────────────────────────────────────────

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


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0005_registration_attendance.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0005_registration_attendance.sql
-- กลุ่มเรียน · การลงทะเบียน · การเช็คชื่อ · กฎเวลาเรียน 80%
--
-- หัวใจของไฟล์นี้คือกฎเวลาเรียน
-- ตามระเบียบ ปวช./ปวส. นักศึกษาต้องมีเวลาเรียนไม่ต่ำกว่า 80% ของรายวิชา
-- จึงมีสิทธิ์เข้ารับการประเมินสรุปผล ต่ำกว่านั้นจะได้ ข.ร. ซึ่งเท่ากับ 0
-- ระบบต้องคำนวณตัวเลขนี้ตลอดเวลา ไม่ใช่ตอนปลายภาค เพราะการเตือนล่วงหน้า
-- คือกลไกป้องกันการออกกลางคันที่ได้ผลที่สุด
--
-- นโยบายเวลาเรียนถูกตรึงไว้ที่กลุ่มเรียนตั้งแต่วันเปิดภาค การแก้นโยบาย
-- กลางภาคจึงไม่ย้อนไปเปลี่ยนผลของกลุ่มที่เปิดไปแล้ว
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- นโยบายเวลาเรียน — ตั้งค่าได้เอง เพราะแต่ละสถานศึกษาตีความไม่เหมือนกัน
-- โดยเฉพาะเรื่อง "ลาป่วยที่มีใบรับรองแพทย์นับเป็นเวลาเรียนหรือไม่"
-- ───────────────────────────────────────────────────────────────────
create table attendance_policy (
  id                     uuid          primary key default gen_random_uuid(),
  institution_id         uuid          not null references institution on delete restrict,
  name_th                text          not null,
  effective_from_year_be smallint      not null,
  min_pct                numeric(5,2)  not null default 80.00,  -- เกณฑ์ผ่าน
  discretion_floor_pct   numeric(5,2)  not null default 60.00,  -- ต่ำกว่านี้ยื่นคำร้องไม่ได้
  warn_pct               numeric(5,2)  not null default 85.00,  -- เริ่มเตือนที่กี่เปอร์เซ็นต์
  created_at             timestamptz   not null default now(),
  unique (institution_id, effective_from_year_be),
  check (discretion_floor_pct <= min_pct and min_pct <= warn_pct)
);
comment on column attendance_policy.discretion_floor_pct is
  'ระหว่าง discretion_floor_pct ถึง min_pct ให้ยื่นคำร้องเข้าดุลยพินิจสถานศึกษาได้ ต่ำกว่านั้นติด ข.ร. ทันที';

create type attendance_status as enum (
  'present',         -- มาเรียน
  'late',            -- มาสาย
  'leave_sick',      -- ลาป่วย
  'leave_personal',  -- ลากิจ
  'activity',        -- ไปราชการ/ทำกิจกรรมของวิทยาลัย
  'absent'           -- ขาดเรียน
);

-- น้ำหนักของแต่ละสถานะในการคิดเวลาเรียน 1.00 = นับเต็ม, 0 = ไม่นับ
create table attendance_status_weight (
  attendance_policy_id uuid              not null references attendance_policy on delete cascade,
  status               attendance_status not null,
  weight               numeric(3,2)      not null check (weight between 0 and 1),
  primary key (attendance_policy_id, status)
);

-- ───────────────────────────────────────────────────────────────────
-- กลุ่มเรียน
-- ───────────────────────────────────────────────────────────────────
create type delivery_mode as enum ('onsite', 'dvt', 'internship', 'online', 'block');
comment on type delivery_mode is
  'dvt = ทวิภาคี · internship = ฝึกประสบการณ์ · block = เรียนแบบบล็อกคอร์ส ซึ่งอาชีวะบางแห่งใช้';

create table class_section (
  id                    uuid          primary key default gen_random_uuid(),
  institution_id        uuid          not null references institution on delete restrict,
  term_id               uuid          not null references term        on delete restrict,
  course_id             uuid          not null references course      on delete restrict,
  curriculum_version_id uuid          references curriculum_version,
  section_no            text          not null,        -- '1/2'
  teacher_id            uuid          references staff,
  room                  text,
  capacity              smallint      not null default 40,
  delivery_mode         delivery_mode not null default 'onsite',

  -- ตรึงนโยบายเวลาเรียนไว้ตั้งแต่เปิดกลุ่ม
  attendance_policy_id  uuid          not null references attendance_policy on delete restrict,
  planned_periods       smallint      not null,        -- จำนวนคาบทั้งภาคตามแผน ใช้เป็นตัวหาร

  is_locked             boolean       not null default false,
  created_at            timestamptz   not null default now(),
  unique (term_id, course_id, section_no),
  check (planned_periods > 0)
);
create index on class_section (term_id, teacher_id);

comment on column class_section.planned_periods is
  'ตัวหารของเวลาเรียน กำหนดตอนเปิดกลุ่มและห้ามแก้หลังเริ่มภาคเรียน เพราะจะเปลี่ยนผลย้อนหลังของทุกคน';

-- ───────────────────────────────────────────────────────────────────
-- การลงทะเบียน
-- ───────────────────────────────────────────────────────────────────
create type enrollment_status as enum (
  'enrolled',       -- ลงทะเบียนปกติ
  'withdrawn',      -- ถอนรายวิชา (ติด ถ.น.)
  'dropped',        -- ถอนภายในกำหนดเพิ่ม-ถอน ไม่ปรากฏในระเบียน
  'credit_transfer' -- เทียบโอน
);

create table enrollment (
  id                uuid              primary key default gen_random_uuid(),
  student_id        uuid              not null references student      on delete restrict,
  class_section_id  uuid              not null references class_section on delete restrict,
  term_id           uuid              not null references term          on delete restrict,
  status            enrollment_status not null default 'enrolled',
  attempt_no        smallint          not null default 1,   -- เรียนซ้ำครั้งที่เท่าไร
  counts_toward_gpa boolean           not null default true,
  registered_at     timestamptz       not null default now(),
  registered_by     uuid,
  withdrawn_at      timestamptz,
  created_at        timestamptz       not null default now(),
  unique (student_id, class_section_id)
);
create index on enrollment (class_section_id) where status = 'enrolled';
create index on enrollment (student_id, term_id);

comment on column enrollment.counts_toward_gpa is
  'รายวิชาปรับพื้นฐานและรายวิชาเทียบโอนตั้งเป็น false เพราะต้องผ่านแต่ไม่นำมาคิด GPA';

-- ───────────────────────────────────────────────────────────────────
-- คาบเรียนและการเช็คชื่อ
-- ───────────────────────────────────────────────────────────────────
create type meeting_status as enum ('scheduled', 'held', 'cancelled', 'substituted');

create table class_meeting (
  id                uuid           primary key default gen_random_uuid(),
  class_section_id  uuid           not null references class_section on delete cascade,
  meets_on          date           not null,
  period_from       smallint       not null,
  period_to         smallint       not null,
  period_count      smallint generated always as (period_to - period_from + 1) stored,
  status            meeting_status not null default 'scheduled',
  taught_by         uuid           references staff,   -- ครูสอนแทนจะต่างจาก teacher_id ของกลุ่ม
  closed_at         timestamptz,                       -- ปิดคาบแล้ว = ห้ามแก้การเช็คชื่อโดยตรง
  note              text,
  unique (class_section_id, meets_on, period_from),
  check (period_to >= period_from)
);
create index on class_meeting (class_section_id, meets_on);

create type attendance_source as enum ('teacher_web', 'teacher_mobile', 'gate_import', 'guardian_leave', 'system');

create table attendance_record (
  id                 uuid              primary key default gen_random_uuid(),
  class_meeting_id   uuid              not null references class_meeting on delete cascade,
  enrollment_id      uuid              not null references enrollment    on delete cascade,
  status             attendance_status not null,
  source             attendance_source not null default 'teacher_mobile',
  recorded_by        uuid,
  recorded_at        timestamptz       not null default now(),
  captured_at        timestamptz,      -- เวลาที่กดจริงบนเครื่อง กรณีเช็คชื่อออฟไลน์แล้วส่งทีหลัง
  note               text,
  unique (class_meeting_id, enrollment_id)
);
create index on attendance_record (enrollment_id);

comment on column attendance_record.captured_at is
  'เวลาที่ครูกดบนเครื่องขณะออฟไลน์ ต่างจาก recorded_at ที่เป็นเวลาที่ข้อมูลถึงเซิร์ฟเวอร์ ใช้ตรวจสอบย้อนหลังได้';

-- ───────────────────────────────────────────────────────────────────
-- คำนวณเวลาเรียน
-- pct_to_date  = เทียบกับคาบที่สอนไปแล้ว ใช้แสดงผลระหว่างภาค
-- pct_final    = เทียบกับคาบตามแผนทั้งภาค ใช้ตัดสิน ข.ร. ตอนปลายภาค
-- absences_left = ขาดได้อีกกี่คาบก่อนตกเกณฑ์ — ตัวเลขที่แสดงในแอปนักศึกษา
-- ───────────────────────────────────────────────────────────────────
create view v_enrollment_attendance as
with agg as (
  select
    e.id                                   as enrollment_id,
    e.class_section_id,
    cs.planned_periods,
    ap.min_pct,
    ap.warn_pct,
    ap.discretion_floor_pct,
    coalesce(sum(cm.period_count), 0)      as periods_held,
    coalesce(sum(cm.period_count * coalesce(w.weight, 0)), 0) as periods_credited
  from enrollment e
  join class_section     cs on cs.id = e.class_section_id
  join attendance_policy ap on ap.id = cs.attendance_policy_id
  left join class_meeting cm
         on cm.class_section_id = e.class_section_id
        and cm.status = 'held'
  left join attendance_record ar
         on ar.class_meeting_id = cm.id
        and ar.enrollment_id    = e.id
  left join attendance_status_weight w
         on w.attendance_policy_id = cs.attendance_policy_id
        and w.status               = ar.status
  where e.status = 'enrolled'
  group by e.id, e.class_section_id, cs.planned_periods,
           ap.min_pct, ap.warn_pct, ap.discretion_floor_pct
)
select
  enrollment_id,
  class_section_id,
  planned_periods,
  periods_held,
  periods_credited,

  -- เทียบกับคาบที่สอนไปแล้ว — ตัวเลขที่แสดงให้นักศึกษาเห็นระหว่างภาค
  case when periods_held = 0 then null
       else round(periods_credited * 100.0 / periods_held, 2) end   as pct_to_date,

  -- เทียบกับคาบตามแผนทั้งภาค — ตัวเลขทางการที่ใช้ตัดสิน ข.ร. ตอนปลายภาค
  round(periods_credited * 100.0 / planned_periods, 2)              as pct_final,

  -- ถ้าเข้าเรียนครบทุกคาบที่เหลือจะจบภาคที่กี่เปอร์เซ็นต์
  -- ใช้ตัดสินสถานะระหว่างภาค เพราะ pct_final กลางเทอมจะต่ำเสมอโดยธรรมชาติ
  round((periods_credited + (planned_periods - periods_held)) * 100.0 / planned_periods, 2)
                                                                    as pct_projected,

  -- ขาดได้อีกกี่คาบก่อนตกเกณฑ์ (ปัดลง ไม่เคยแสดงค่าติดลบ)
  greatest(
    floor(periods_credited + (planned_periods - periods_held)
          - (planned_periods * min_pct / 100.0)),
    0
  )::int                                                            as absences_left,

  min_pct,
  warn_pct,
  discretion_floor_pct,

  case
    -- เข้าเรียนครบทุกคาบที่เหลือก็ยังต่ำกว่าเกณฑ์ดุลยพินิจ = หมดสิทธิ์แน่นอนแล้ว
    when round((periods_credited + (planned_periods - periods_held)) * 100.0 / planned_periods, 2)
         < discretion_floor_pct then 'failed'
    -- เข้าครบที่เหลือก็ยังไม่ถึง 80% = ต้องยื่นคำร้องเข้าดุลยพินิจ
    when round((periods_credited + (planned_periods - periods_held)) * 100.0 / planned_periods, 2)
         < min_pct then 'discretion'
    -- ยังกู้คืนได้แต่เริ่มน่าเป็นห่วง = จุดที่ระบบเริ่มเตือน
    when periods_held > 0
     and round(periods_credited * 100.0 / periods_held, 2) < warn_pct then 'warning'
    else 'ok'
  end                                                               as attendance_state
from agg;

comment on view v_enrollment_attendance is
  'แหล่งความจริงเดียวของเวลาเรียน ทั้งแอปนักศึกษา หน้าบันทึกคะแนน และการตัดเกรด ต้องอ่านจากมุมมองนี้เท่านั้น';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0006_assessment.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0006_assessment.sql
-- ระเบียบวัดผล · สมุดคะแนน · ผลการเรียน · ขั้นตอนอนุมัติเกรด · บัญชีตรวจสอบ
--
-- หลักสามข้อของไฟล์นี้
-- 1. สัญลักษณ์ผลการเรียนเป็นข้อมูล ไม่ใช่โค้ด — ระเบียบ ปวช. กับ ปวส.
--    ใช้คนละฉบับ และแก้ไขได้ในอนาคต จึงเก็บเป็นตารางที่ผูกกับหลักสูตร
-- 2. ผลการเรียนแก้ทับไม่ได้ — เก็บเป็นเวอร์ชัน การแก้เกรดคือการออกแถวใหม่
--    ที่ชี้กลับไปแถวเดิม ทำให้พิสูจน์ได้เสมอว่าใครแก้อะไรเมื่อไรและทำไม
-- 3. ทุกการเปลี่ยนแปลงผลการเรียนถูกผูกเป็นโซ่แฮช — แก้ย้อนหลังในฐานข้อมูล
--    โดยตรงจะทำให้โซ่ขาดและตรวจพบได้ ข้อนี้จำเป็นเพราะข้อมูลชุดนี้ใช้ยัน
--    การขอรับเงินอุดหนุนและใช้ออกเอกสารราชการ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ระเบียบวัดผล
-- ───────────────────────────────────────────────────────────────────
create table grade_scheme (
  id                     uuid                primary key default gen_random_uuid(),
  institution_id         uuid                not null references institution on delete restrict,
  code                   text                not null,   -- 'PVC-2562'
  name_th                text                not null,   -- 'ระเบียบวัดผล ปวช. พ.ศ. 2562'
  level                  qualification_level not null,
  effective_from_year_be smallint            not null,
  unique (institution_id, code)
);

-- ตอนนี้ผูก curriculum_version กับระเบียบวัดผลได้แล้ว
alter table curriculum_version
  add constraint curriculum_version_grade_scheme_fk
  foreign key (grade_scheme_id) references grade_scheme on delete restrict;

create table grade_symbol (
  id                    uuid         primary key default gen_random_uuid(),
  grade_scheme_id       uuid         not null references grade_scheme on delete cascade,
  symbol                text         not null,   -- '4.0' '3.5' ... '0' 'ข.ร.' 'ข.ส.' 'ม.ส.' 'ถ.น.' 'ผ.' 'ม.ผ.'
  name_th               text         not null,
  grade_point           numeric(2,1),            -- null สำหรับสัญลักษณ์ที่ไม่มีค่าระดับคะแนน
  counts_in_gpa         boolean      not null default true,
  earns_credit          boolean      not null default true,
  is_provisional        boolean      not null default false,  -- ม.ส. / ข.ส. ต้องแก้ภายในกำหนด
  resolve_within_days   smallint,                             -- จำนวนวันที่ต้องแก้ให้เสร็จ
  appears_on_transcript boolean      not null default true,
  sort_order            smallint     not null default 0,
  unique (grade_scheme_id, symbol)
);
comment on column grade_symbol.is_provisional is
  'ม.ส. และ ข.ส. เป็นผลชั่วคราว ระบบต้องตั้งนาฬิกานับถอยหลังและ escalate ไปครูผู้สอน หัวหน้าแผนก และฝ่ายวิชาการ';

-- ช่วงคะแนนสำหรับตัดเกรดอัตโนมัติ
create table grade_cutoff (
  id              uuid         primary key default gen_random_uuid(),
  grade_scheme_id uuid         not null references grade_scheme on delete cascade,
  grade_symbol_id uuid         not null references grade_symbol on delete cascade,
  min_score       numeric(5,2) not null,   -- คะแนนขั้นต่ำที่ได้สัญลักษณ์นี้
  unique (grade_scheme_id, grade_symbol_id)
);

-- ───────────────────────────────────────────────────────────────────
-- สมุดคะแนน
-- ครูกำหนดชิ้นงานและน้ำหนักเอง ระบบไม่บังคับรูปแบบ
-- ───────────────────────────────────────────────────────────────────
create type gradebook_category as enum ('formative', 'midterm', 'final', 'affective', 'practical');

create table gradebook_item (
  id                uuid               primary key default gen_random_uuid(),
  class_section_id  uuid               not null references class_section on delete cascade,
  name_th           text               not null,
  category          gradebook_category not null default 'formative',
  max_score         numeric(6,2)       not null check (max_score > 0),
  weight            numeric(5,2)       not null check (weight >= 0),  -- น้ำหนักในคะแนนเต็ม 100
  competency_id     uuid               references competency,          -- ผูกกับสมรรถนะได้
  due_on            date,
  publish_to_student boolean           not null default false,
  sort_order        smallint           not null default 0,
  created_at        timestamptz        not null default now()
);
create index on gradebook_item (class_section_id);

comment on column gradebook_item.publish_to_student is
  'วิทยาลัยเลือกได้ว่าจะเปิดให้นักศึกษาเห็นคะแนนเก็บระหว่างภาคหรือไม่ ค่าเริ่มต้นคือไม่เปิด';

create table gradebook_score (
  id                uuid         primary key default gen_random_uuid(),
  gradebook_item_id uuid         not null references gradebook_item on delete cascade,
  enrollment_id     uuid         not null references enrollment     on delete cascade,
  score             numeric(6,2),
  recorded_by       uuid,
  recorded_at       timestamptz  not null default now(),
  captured_at       timestamptz,               -- กรณีกรอกออฟไลน์
  unique (gradebook_item_id, enrollment_id)
);
create index on gradebook_score (enrollment_id);

-- ───────────────────────────────────────────────────────────────────
-- ขั้นตอนอนุมัติเกรด
-- ครูผู้สอน → หัวหน้าแผนกวิชา → ฝ่ายวิชาการ → ผู้อำนวยการ → ล็อก
-- ───────────────────────────────────────────────────────────────────
create type submission_stage as enum (
  'draft',
  'teacher_submitted',
  'head_approved',
  'academic_approved',
  'director_approved',
  'locked',
  'returned'          -- ตีกลับให้ครูแก้
);

create table grade_submission (
  id                uuid             primary key default gen_random_uuid(),
  class_section_id  uuid             not null references class_section on delete restrict,
  term_id           uuid             not null references term          on delete restrict,
  stage             submission_stage not null default 'draft',
  submitted_by      uuid,
  submitted_at      timestamptz,
  locked_at         timestamptz,
  created_at        timestamptz      not null default now(),
  unique (class_section_id)
);

create table grade_submission_event (
  id             uuid             primary key default gen_random_uuid(),
  submission_id  uuid             not null references grade_submission on delete cascade,
  from_stage     submission_stage,
  to_stage       submission_stage not null,
  actor_id       uuid,
  note           text,
  occurred_at    timestamptz      not null default now()
);
create index on grade_submission_event (submission_id, occurred_at);

-- ───────────────────────────────────────────────────────────────────
-- ผลการเรียนรายวิชา — เขียนอย่างเดียว
-- แถวปัจจุบันคือแถวที่ superseded_by is null
-- ───────────────────────────────────────────────────────────────────
create table enrollment_result (
  id               uuid         primary key default gen_random_uuid(),
  enrollment_id    uuid         not null references enrollment    on delete restrict,
  submission_id    uuid         references grade_submission,
  revision         smallint     not null default 1,

  raw_score        numeric(6,2),
  attendance_pct   numeric(5,2),                       -- ค่าที่ใช้ตัดสินจริง ตรึงไว้ ณ เวลาตัดเกรด
  grade_symbol_id  uuid         not null references grade_symbol on delete restrict,
  grade_point      numeric(2,1),
  credits_earned   numeric(3,1) not null default 0,

  computed_by      uuid,
  computed_at      timestamptz  not null default now(),
  reason           text,                               -- เหตุผล บังคับเมื่อ revision > 1
  superseded_by    uuid         references enrollment_result,

  unique (enrollment_id, revision)
);
create unique index enrollment_result_current
  on enrollment_result (enrollment_id) where superseded_by is null;
create index on enrollment_result (grade_symbol_id);

comment on column enrollment_result.attendance_pct is
  'ตรึงค่าเวลาเรียน ณ เวลาตัดเกรด ห้ามคำนวณใหม่ตอนพิมพ์เอกสาร มิฉะนั้นเอกสารย้อนหลังจะไม่ตรงกับที่เคยออกไป';

-- ห้าม UPDATE โดยตรง ยกเว้นการตั้งค่า superseded_by
create or replace function enrollment_result_immutable() returns trigger
language plpgsql as $$
begin
  if (to_jsonb(new) - 'superseded_by') is distinct from (to_jsonb(old) - 'superseded_by') then
    raise exception 'ผลการเรียนแก้ทับไม่ได้ ให้ออก revision ใหม่ผ่านคำร้องแก้เกรด (enrollment_id=%)', old.enrollment_id;
  end if;
  return new;
end $$;

create trigger enrollment_result_no_update before update on enrollment_result
  for each row execute function enrollment_result_immutable();

create or replace function enrollment_result_no_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'ผลการเรียนลบไม่ได้';
end $$;

create trigger enrollment_result_block_delete before delete on enrollment_result
  for each row execute function enrollment_result_no_delete();

-- ───────────────────────────────────────────────────────────────────
-- คำร้องแก้เกรดหลังล็อก — ต้องมีผู้อนุมัติสองคน
-- ───────────────────────────────────────────────────────────────────
create type change_request_status as enum ('pending', 'approved', 'rejected', 'applied');

create table grade_change_request (
  id                  uuid                  primary key default gen_random_uuid(),
  enrollment_id       uuid                  not null references enrollment        on delete restrict,
  from_result_id      uuid                  not null references enrollment_result on delete restrict,
  to_grade_symbol_id  uuid                  not null references grade_symbol      on delete restrict,
  to_raw_score        numeric(6,2),
  reason              text                  not null,
  document_no         text,                                     -- เลขที่คำร้อง
  requested_by        uuid                  not null,
  approver_1_id       uuid,
  approver_1_at       timestamptz,
  approver_2_id       uuid,
  approver_2_at       timestamptz,
  status              change_request_status not null default 'pending',
  applied_result_id   uuid                  references enrollment_result,
  created_at          timestamptz           not null default now(),
  check (approver_1_id is null or approver_2_id is null or approver_1_id <> approver_2_id)
);
comment on constraint grade_change_request_check on grade_change_request is
  'ผู้อนุมัติสองคนต้องเป็นคนละคน — dual control กันการแก้เกรดโดยคนเดียว';

-- ───────────────────────────────────────────────────────────────────
-- บัญชีตรวจสอบแบบโซ่แฮช
-- ทุกการเขียนผลการเรียนถูกบันทึกและผูกกับแฮชของรายการก่อนหน้า
-- การแก้แถวเก่าย้อนหลังจะทำให้แฮชที่คำนวณใหม่ไม่ตรงกับที่เก็บไว้
-- ───────────────────────────────────────────────────────────────────
create table grade_ledger (
  seq            bigserial   primary key,
  institution_id uuid        not null references institution,
  entity         text        not null,          -- 'enrollment_result' | 'attendance_record' | ...
  entity_id      uuid        not null,
  action         text        not null,          -- 'insert' | 'supersede'
  payload        jsonb       not null,
  actor_id       uuid,
  occurred_at    timestamptz not null default now(),
  prev_hash      bytea,
  hash           bytea       not null
);
create index on grade_ledger (entity, entity_id);
create index on grade_ledger (institution_id, occurred_at);

create or replace function grade_ledger_chain() returns trigger
language plpgsql as $$
declare
  v_prev bytea;
begin
  select l.hash into v_prev
  from grade_ledger l
  where l.institution_id = new.institution_id
  order by l.seq desc
  limit 1;

  new.prev_hash := v_prev;
  new.hash := digest(
    coalesce(v_prev, '\x00'::bytea)
      || convert_to(new.entity, 'UTF8')
      || decode(replace(new.entity_id::text, '-', ''), 'hex')
      || convert_to(new.action, 'UTF8')
      || convert_to(new.payload::text, 'UTF8')
      || convert_to(new.occurred_at::text, 'UTF8'),
    'sha256'
  );
  return new;
end $$;

create trigger grade_ledger_hash before insert on grade_ledger
  for each row execute function grade_ledger_chain();

-- บันทึกลง ledger ทุกครั้งที่มีผลการเรียนใหม่
create or replace function enrollment_result_to_ledger() returns trigger
language plpgsql as $$
declare
  v_inst uuid;
begin
  select s.institution_id into v_inst
  from enrollment e
  join student s on s.id = e.student_id
  where e.id = new.enrollment_id;

  insert into grade_ledger (institution_id, entity, entity_id, action, payload, actor_id)
  values (v_inst, 'enrollment_result', new.id, 'insert', to_jsonb(new), current_actor_id());
  return null;
end $$;

create trigger enrollment_result_ledger after insert on enrollment_result
  for each row execute function enrollment_result_to_ledger();

-- ตรวจความสมบูรณ์ของโซ่ — ให้งานตรวจสอบภายในเรียกใช้เป็นระยะ
create or replace function verify_grade_ledger(p_institution_id uuid)
returns table (seq bigint, ok boolean)
language sql stable as $$
  select l.seq,
         l.hash = digest(
           coalesce(lag(l.hash) over (order by l.seq), '\x00'::bytea)
             || convert_to(l.entity, 'UTF8')
             || decode(replace(l.entity_id::text, '-', ''), 'hex')
             || convert_to(l.action, 'UTF8')
             || convert_to(l.payload::text, 'UTF8')
             || convert_to(l.occurred_at::text, 'UTF8'),
           'sha256'
         ) as ok
  from grade_ledger l
  where l.institution_id = p_institution_id
  order by l.seq
$$;

-- ───────────────────────────────────────────────────────────────────
-- สรุปผลรายภาคเรียน
-- ───────────────────────────────────────────────────────────────────
create table term_summary (
  student_id        uuid         not null references student on delete cascade,
  term_id           uuid         not null references term    on delete cascade,
  credits_attempted numeric(5,1) not null default 0,
  credits_earned    numeric(5,1) not null default 0,
  gpa               numeric(3,2),
  gpax              numeric(3,2),
  computed_at       timestamptz  not null default now(),
  primary key (student_id, term_id)
);

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0007_graduation.sql
-- ───────────────────────────────────────────────────────────────────

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


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0008_rls.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0008_rls.sql
-- Row-Level Security
--
-- สิทธิ์ต้องบังคับที่ฐานข้อมูล ไม่ใช่ที่ชั้นแอปพลิเคชันเพียงอย่างเดียว
-- ถ้าโค้ดชั้นแอปลืมใส่เงื่อนไข where สักที่เดียว ข้อมูลนักศึกษาทั้งวิทยาลัย
-- จะรั่ว การวางกำแพงไว้ที่ชั้นล่างสุดทำให้บั๊กแบบนั้นกลายเป็นแถวว่าง
-- แทนที่จะกลายเป็นเหตุละเมิดข้อมูลส่วนบุคคล
--
-- ─── กติกาที่ต้องเข้าใจก่อนแก้ไฟล์นี้ ───
-- PostgreSQL รวม policy สองแบบไม่เหมือนกัน
--   PERMISSIVE  (ค่าเริ่มต้น) → รวมกันด้วย OR   = "ทางใดทางหนึ่งอนุญาตก็พอ"
--   RESTRICTIVE               → รวมกันด้วย AND  = "ต้องผ่านทุกข้อ"
-- ถ้าเขียนนโยบายขอบเขตบทบาทเป็น permissive มันจะไป OR กับนโยบายแยกสถานศึกษา
-- แล้วเปิดข้อมูลข้ามวิทยาลัยทันที (บั๊กนี้ถูกจับได้ด้วย tests/0001_smoke.sql TEST 10)
--
-- โครงสร้างที่ใช้จึงเป็นสองชั้น
--   ชั้นที่ 1  permissive  — เข้าถึงได้เมื่ออยู่ในสถานศึกษาเดียวกัน
--   ชั้นที่ 2  restrictive — แล้วยังต้องผ่านขอบเขตของบทบาทอีกชั้น
--
-- ชั้นแอปต้องตั้งค่าทุก transaction:
--   SET LOCAL app.institution_id = '...';
--   SET LOCAL app.actor_id       = '...';   -- person_id ของผู้ใช้
--   SET LOCAL app.role           = 'teacher' | 'registrar' | 'finance' | ...
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function current_app_role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('app.role', true), ''), 'none')
$$;

-- บทบาทที่มีหน้าที่ดูข้อมูลได้ทั้งสถานศึกษา
create or replace function is_institution_wide_role() returns boolean
language sql stable as $$
  select current_app_role() in ('registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin')
$$;

-- ═══ ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา (permissive) ═══════════

-- 1ก. ตารางที่มี institution_id อยู่บนตัวเอง
do $$
declare t text;
begin
  foreach t in array array[
    'person', 'student', 'staff',
    'academic_year', 'program_type', 'program', 'curriculum',
    'course', 'class_section', 'grade_scheme', 'attendance_policy'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- 1ข. ตารางที่สืบทอดสถานศึกษาผ่านคีย์นอก
alter table term enable row level security;
alter table term force  row level security;
create policy tenant_isolation on term
  using (exists (select 1 from academic_year ay
                 where ay.id = term.academic_year_id
                   and ay.institution_id = current_institution_id()));

alter table enrollment enable row level security;
alter table enrollment force  row level security;
create policy tenant_isolation on enrollment
  using (exists (select 1 from student s
                 where s.id = enrollment.student_id
                   and s.institution_id = current_institution_id()));

alter table enrollment_result enable row level security;
alter table enrollment_result force  row level security;
create policy tenant_isolation on enrollment_result
  using (exists (select 1 from enrollment e
                 join student s on s.id = e.student_id
                 where e.id = enrollment_result.enrollment_id
                   and s.institution_id = current_institution_id()));

alter table gradebook_score enable row level security;
alter table gradebook_score force  row level security;
create policy tenant_isolation on gradebook_score
  using (exists (select 1 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 where gi.id = gradebook_score.gradebook_item_id
                   and cs.institution_id = current_institution_id()));

alter table attendance_record enable row level security;
alter table attendance_record force  row level security;
create policy tenant_isolation on attendance_record
  using (exists (select 1 from class_meeting cm
                 join class_section cs on cs.id = cm.class_section_id
                 where cm.id = attendance_record.class_meeting_id
                   and cs.institution_id = current_institution_id()));

-- ═══ ชั้นที่ 2 — ขอบเขตของบทบาท (restrictive, AND ทับชั้นที่ 1) ═══

-- ครูเห็นเฉพาะกลุ่มเรียนที่ตนสอน บทบาทระดับสถานศึกษาเห็นทั้งหมด
create policy teacher_scope on class_section
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
               where st.id = class_section.teacher_id
                 and st.person_id = current_actor_id())
  );

create policy teacher_scope on gradebook_score
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from gradebook_item gi
               join class_section cs on cs.id = gi.class_section_id
               join staff st         on st.id = cs.teacher_id
               where gi.id = gradebook_score.gradebook_item_id
                 and st.person_id = current_actor_id())
  );

-- ครูสอนแทนต้องเช็คชื่อได้ด้วย จึงเทียบกับ coalesce(taught_by, teacher_id)
create policy teacher_scope on attendance_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st         on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
  );

-- นักศึกษาเห็นข้อมูลตนเอง ผู้ปกครองเห็นได้เมื่อยืนยันตัวตนแล้วเท่านั้น
create policy subject_scope on student
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from person p
               where p.id = student.person_id
                 and p.id = current_actor_id())
    or exists (select 1 from student_guardian sg
               where sg.student_id = student.id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null)
  );

create policy subject_scope on enrollment_result
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1
               from enrollment e
               join student s on s.id = e.student_id
               where e.id = enrollment_result.enrollment_id
                 and s.person_id = current_actor_id())
    or exists (select 1
               from enrollment e
               join student_guardian sg on sg.student_id = e.student_id
               where e.id = enrollment_result.enrollment_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_grades)
  );

-- ═══ บัญชีตรวจสอบ: อ่านได้ เพิ่มได้ แก้และลบไม่ได้ ═══════════════
alter table grade_ledger enable row level security;
alter table grade_ledger force  row level security;
create policy ledger_read on grade_ledger
  for select using (institution_id = current_institution_id());
create policy ledger_append on grade_ledger
  for insert with check (institution_id = current_institution_id());
-- ไม่มีนโยบาย update และ delete โดยเจตนา — RLS จึงปฏิเสธทั้งสองอย่างเสมอ
-- แม้แต่บทบาท admin ก็แก้บัญชีย้อนหลังไม่ได้ผ่านการเชื่อมต่อปกติ

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0009_registration_rules.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0009_registration_rules.sql
-- ตรวจเงื่อนไขตอนลงทะเบียน
--
-- โจทย์
-- การลงทะเบียนคือจุดที่กฎเยอะที่สุดในระบบทะเบียน และเป็นจุดที่ระบบเดิม
-- ของวิทยาลัยมักตรวจไม่ครบ จนได้นักศึกษาที่ลงเกินหน่วยกิต ลงวิชาที่ยังไม่ผ่าน
-- วิชาบังคับก่อน หรือมีตารางชนกันสองวิชาในคาบเดียว แล้วมารู้ตอนปลายภาค
--
-- หลักการออกแบบ
-- 1. ตัวตรวจคืน "รายการปัญหา" ไม่ใช่ true/false — หน้าจอจึงบอกได้ว่าติดอะไร
--    กี่ข้อ และข้อไหนแค่เตือนกับข้อไหนห้ามผ่าน
-- 2. ตัวตรวจไม่รู้จักการเงิน — งานการเงินเขียน registration_hold เข้ามา
--    ตัวตรวจแค่ดูว่ามีการระงับค้างอยู่ไหม โมดูลการเงินจึงพัฒนาแยกได้
-- 3. การยกเว้นต้องบันทึกเสมอ — registrar ปลดล็อกได้แต่ต้องมีเหตุผลและผู้อนุมัติ
--    ระบบเก่ามักปล่อยให้ธุรการกดข้ามได้เงียบ ๆ ซึ่งตรวจสอบย้อนหลังไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- วันหยุดของสถานศึกษา — ใช้ตอนสร้างคาบเรียนจากตารางสอน
-- ───────────────────────────────────────────────────────────────────
create table academic_holiday (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institution on delete cascade,
  holiday_on     date not null,
  name_th        text not null,
  unique (institution_id, holiday_on)
);

-- ───────────────────────────────────────────────────────────────────
-- ตารางสอนประจำสัปดาห์
-- แยกจาก class_meeting เพราะอันนี้คือ "แบบแผน" ส่วน class_meeting คือ
-- "คาบที่เกิดขึ้นจริงในปฏิทิน" ตัวตรวจเวลาชนใช้แบบแผน ส่วนการเช็คชื่อ
-- ใช้คาบจริง
-- ───────────────────────────────────────────────────────────────────
create table section_timeslot (
  id               uuid     primary key default gen_random_uuid(),
  class_section_id uuid     not null references class_section on delete cascade,
  day_of_week      smallint not null check (day_of_week between 1 and 7),  -- 1 = จันทร์
  period_from      smallint not null,
  period_to        smallint not null,
  room             text,
  check (period_to >= period_from),

  -- กลุ่มเรียนเดียวกันห้ามมีคาบซ้อนกันเองในวันเดียวกัน
  constraint section_timeslot_no_self_overlap exclude using gist (
    class_section_id with =,
    day_of_week      with =,
    int4range(period_from, period_to, '[]') with &&
  )
);
create index on section_timeslot (class_section_id);
create index on section_timeslot (day_of_week, period_from);

-- ครูสอนซ้อนกัน — ตรวจข้ามตารางจึงทำเป็นมุมมอง ไม่ใช่ constraint
create view v_teacher_conflict as
select
  cs1.term_id,
  cs1.teacher_id,
  t1.day_of_week,
  cs1.id as section_a, cs2.id as section_b,
  int4range(t1.period_from, t1.period_to, '[]') *
  int4range(t2.period_from, t2.period_to, '[]') as overlapping_periods
from section_timeslot t1
join class_section cs1 on cs1.id = t1.class_section_id
join section_timeslot t2 on t2.day_of_week = t1.day_of_week
                        and int4range(t2.period_from, t2.period_to, '[]')
                         && int4range(t1.period_from, t1.period_to, '[]')
join class_section cs2 on cs2.id = t2.class_section_id
where cs1.teacher_id is not null
  and cs1.teacher_id = cs2.teacher_id
  and cs1.term_id    = cs2.term_id
  and cs1.id < cs2.id;

-- ห้องเรียนถูกจองซ้อน
create view v_room_conflict as
select
  cs1.term_id,
  t1.room,
  t1.day_of_week,
  cs1.id as section_a, cs2.id as section_b,
  int4range(t1.period_from, t1.period_to, '[]') *
  int4range(t2.period_from, t2.period_to, '[]') as overlapping_periods
from section_timeslot t1
join class_section cs1 on cs1.id = t1.class_section_id
join section_timeslot t2 on t2.day_of_week = t1.day_of_week
                        and t2.room = t1.room
                        and int4range(t2.period_from, t2.period_to, '[]')
                         && int4range(t1.period_from, t1.period_to, '[]')
join class_section cs2 on cs2.id = t2.class_section_id
where t1.room is not null
  and cs1.term_id = cs2.term_id
  and cs1.id < cs2.id;

-- ───────────────────────────────────────────────────────────────────
-- สร้างคาบเรียนจริงจากตารางสอน
-- ขยายแบบแผนรายสัปดาห์ไปตลอดภาคเรียน ข้ามวันหยุด แล้วซิงก์ planned_periods
-- ให้ตรงกับจำนวนคาบที่สร้างจริง ซึ่งเป็นตัวหารของกฎเวลาเรียน 80%
-- ───────────────────────────────────────────────────────────────────
create or replace function generate_class_meetings(p_section_id uuid)
returns integer language plpgsql as $$
declare
  v_created integer;
  v_total   integer;
  v_inst    uuid;
begin
  if exists (select 1 from class_meeting
             where class_section_id = p_section_id and status = 'held') then
    raise exception 'สร้างคาบเรียนใหม่ไม่ได้ กลุ่มเรียนนี้มีคาบที่สอนไปแล้ว (section=%)', p_section_id;
  end if;

  select cs.institution_id into v_inst from class_section cs where cs.id = p_section_id;

  delete from class_meeting where class_section_id = p_section_id;

  with span as (
    select t.starts_on, t.ends_on
    from class_section cs join term t on t.id = cs.term_id
    where cs.id = p_section_id
  ),
  days as (
    select d::date as on_date from span, generate_series(span.starts_on, span.ends_on, interval '1 day') d
  )
  insert into class_meeting (class_section_id, meets_on, period_from, period_to, status)
  select p_section_id, d.on_date, ts.period_from, ts.period_to, 'scheduled'
  from days d
  join section_timeslot ts
    on ts.class_section_id = p_section_id
   and ts.day_of_week = extract(isodow from d.on_date)::smallint
  where not exists (
    select 1 from academic_holiday h
    where h.institution_id = v_inst and h.holiday_on = d.on_date
  );

  get diagnostics v_created = row_count;

  select coalesce(sum(period_count), 0) into v_total
  from class_meeting where class_section_id = p_section_id;

  update class_section set planned_periods = greatest(v_total, 1) where id = p_section_id;

  return v_created;
end $$;

comment on function generate_class_meetings is
  'เรียกหลังจัดตารางเสร็จและก่อนเปิดภาคเรียน จะปฏิเสธถ้ามีคาบที่สอนไปแล้ว เพราะ planned_periods เปลี่ยนย้อนหลังไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- นโยบายการลงทะเบียน
-- แยกตามระดับและชนิดภาคเรียน เพราะภาคฤดูร้อนกำหนดเพดานต่างจากภาคปกติ
-- ───────────────────────────────────────────────────────────────────
create table registration_policy (
  id                        uuid                primary key default gen_random_uuid(),
  institution_id            uuid                not null references institution on delete cascade,
  level                     qualification_level not null,
  term_kind                 term_kind           not null default 'regular',
  effective_from_year_be    smallint            not null,
  min_credits               numeric(4,1)        not null default 0,
  max_credits               numeric(4,1)        not null,
  max_credits_with_approval numeric(4,1),
  allow_time_conflict       boolean             not null default false,
  block_when_on_hold        boolean             not null default true,
  unique (institution_id, level, term_kind, effective_from_year_be),
  check (max_credits >= min_credits)
);

-- ───────────────────────────────────────────────────────────────────
-- การระงับสิทธิ์
-- โมดูลอื่นเขียนเข้ามาที่นี่ ตัวตรวจการลงทะเบียนไม่ต้องรู้จักโมดูลเหล่านั้น
-- ───────────────────────────────────────────────────────────────────
create type hold_kind as enum ('finance', 'discipline', 'document', 'health', 'academic', 'other');

create table registration_hold (
  id                  uuid        primary key default gen_random_uuid(),
  student_id          uuid        not null references student on delete cascade,
  kind                hold_kind   not null,
  reason              text        not null,
  amount              numeric(12,2),          -- ใช้กับ kind = finance
  source_module       text,                   -- 'finance' | 'student_affairs' | ...
  source_ref          text,                   -- เลขที่ใบแจ้งหนี้ หรือเลขที่คำสั่ง
  blocks_registration boolean     not null default true,
  blocks_transcript   boolean     not null default false,
  blocks_grade_view   boolean     not null default false,
  placed_by           uuid,
  placed_at           timestamptz not null default now(),
  released_by         uuid,
  released_at         timestamptz,
  release_reason      text
);
create index on registration_hold (student_id) where released_at is null;

comment on table registration_hold is
  'จุดเชื่อมระหว่างงานการเงิน งานปกครอง กับงานทะเบียน โดยไม่ต้องผูกโมดูลเข้าหากันโดยตรง';

-- ───────────────────────────────────────────────────────────────────
-- การยกเว้นกฎ — ปลดล็อกได้ แต่ต้องมีเหตุผลและผู้อนุมัติเสมอ
-- ───────────────────────────────────────────────────────────────────
create table registration_override (
  id               uuid        primary key default gen_random_uuid(),
  student_id       uuid        not null references student on delete cascade,
  term_id          uuid        not null references term    on delete cascade,
  code             text        not null,       -- รหัสกฎที่ยกเว้น เช่น 'CREDIT_MAX'
  class_section_id uuid        references class_section on delete cascade,  -- null = ยกเว้นทั้งภาค
  reason           text        not null,
  document_no      text,
  approved_by      uuid        not null,
  approved_at      timestamptz not null default now(),
  expires_on       date
);
create index on registration_override (student_id, term_id, code);

create or replace function registration_waived(
  p_student_id uuid, p_term_id uuid, p_code text, p_section_id uuid
) returns boolean language sql stable as $$
  select exists (
    select 1 from registration_override o
    where o.student_id = p_student_id
      and o.term_id    = p_term_id
      and o.code       = p_code
      and (o.class_section_id is null or o.class_section_id = p_section_id)
      and (o.expires_on is null or o.expires_on >= current_date)
  )
$$;

-- ───────────────────────────────────────────────────────────────────
-- ตัวตรวจเงื่อนไขการลงทะเบียน
--
-- คืนรายการปัญหาทั้งหมด ไม่หยุดที่ข้อแรก เพราะนักศึกษาต้องเห็นทุกอย่าง
-- ที่ต้องแก้ในรอบเดียว ไม่ใช่แก้ทีละข้อแล้วกดใหม่ห้ารอบ
--
-- severity  block = ลงทะเบียนไม่ได้ · warn = ลงได้แต่ควรรู้ · info = แจ้งให้ทราบ
-- waived    ยกเว้นแล้วโดยผู้มีอำนาจ — ยังคืนแถวออกมาเพื่อให้เห็นว่าเคยติดอะไร
-- ───────────────────────────────────────────────────────────────────
create type registration_check_severity as enum ('block', 'warn', 'info');

create or replace function check_registration(
  p_student_id  uuid,
  p_term_id     uuid,
  p_section_ids uuid[]
) returns table (
  code             text,
  severity         registration_check_severity,
  message_th       text,
  class_section_id uuid,
  waived           boolean,
  detail           jsonb
) language plpgsql stable as $$
declare
  v_cv        uuid;
  v_level     qualification_level;
  v_year_be   smallint;
  v_term      term%rowtype;
  v_policy    registration_policy%rowtype;
  v_status    student_status;
  v_inst      uuid;
  v_new       uuid[];   -- กลุ่มเรียนที่กำลังจะเพิ่ม
  v_sections  uuid[];   -- ที่กำลังจะเพิ่ม + ที่ลงไปแล้วในภาคนี้
  v_credits   numeric(6,1);
begin
  v_new := coalesce(p_section_ids, '{}'::uuid[]);
  select s.status, s.institution_id, s.admitted_year_be
    into v_status, v_inst, v_year_be
  from student s where s.id = p_student_id;

  if v_status is null then
    return query select 'STUDENT_NOT_FOUND', 'block'::registration_check_severity,
      'ไม่พบนักศึกษา', null::uuid, false, '{}'::jsonb;
    return;
  end if;

  select * into v_term from term where id = p_term_id;

  -- ── กฎระดับภาพรวม ───────────────────────────────────────────────
  if v_term.status not in ('registration', 'open') then
    return query select 'TERM_NOT_OPEN', 'block'::registration_check_severity,
      format('ภาคเรียนนี้ยังไม่เปิดให้ลงทะเบียน (สถานะ %s)', v_term.status),
      null::uuid,
      registration_waived(p_student_id, p_term_id, 'TERM_NOT_OPEN', null),
      jsonb_build_object('term_status', v_term.status);
  end if;

  if v_status <> 'active' then
    return query select 'STUDENT_NOT_ACTIVE', 'block'::registration_check_severity,
      format('สถานะนักศึกษาไม่พร้อมลงทะเบียน (%s)', v_status),
      null::uuid,
      registration_waived(p_student_id, p_term_id, 'STUDENT_NOT_ACTIVE', null),
      jsonb_build_object('student_status', v_status);
  end if;

  select sc.curriculum_version_id into v_cv
  from student_curriculum sc
  where sc.student_id = p_student_id and sc.effective_to is null;

  if v_cv is null then
    return query select 'NO_CURRICULUM', 'block'::registration_check_severity,
      'ยังไม่ได้กำหนดหลักสูตรให้นักศึกษาคนนี้', null::uuid, false, '{}'::jsonb;
    return;
  end if;

  select p.level into v_level
  from curriculum_version cv
  join curriculum c        on c.id = cv.curriculum_id
  join program_track pt    on pt.id = c.program_track_id
  join program p           on p.id = pt.program_id
  where cv.id = v_cv;

  -- ── การระงับสิทธิ์จากโมดูลอื่น ──────────────────────────────────
  return query
  select 'HOLD_' || upper(h.kind::text),
         'block'::registration_check_severity,
         case when h.kind = 'finance' and h.amount is not null
              then format('ติดระงับจากงานการเงิน ค้างชำระ %s บาท — %s',
                          to_char(h.amount, 'FM999,999,990.00'), h.reason)
              else format('ติดระงับการลงทะเบียน — %s', h.reason) end,
         null::uuid,
         registration_waived(p_student_id, p_term_id, 'HOLD_' || upper(h.kind::text), null),
         jsonb_build_object('hold_id', h.id, 'amount', h.amount,
                            'source_module', h.source_module, 'source_ref', h.source_ref)
  from registration_hold h
  where h.student_id = p_student_id
    and h.released_at is null
    and h.blocks_registration;

  -- ── ชุดกลุ่มเรียนที่พิจารณา = ที่เลือกใหม่ + ที่ลงไปแล้วในภาคนี้ ──
  select array_agg(distinct sid) into v_sections
  from (
    select unnest(v_new) as sid
    union
    select e.class_section_id
    from enrollment e
    where e.student_id = p_student_id
      and e.term_id    = p_term_id
      and e.status     = 'enrolled'
  ) x;

  v_sections := coalesce(v_sections, '{}'::uuid[]);

  -- ── กลุ่มเรียนต้องอยู่ในภาคเรียนที่กำลังลง ─────────────────────
  return query
  select 'SECTION_WRONG_TERM', 'block'::registration_check_severity,
         format('%s กลุ่ม %s ไม่ได้เปิดในภาคเรียนนี้', c.name_th, cs.section_no),
         cs.id, false,
         jsonb_build_object('section_term_id', cs.term_id)
  from unnest(v_sections) sid
  join class_section cs on cs.id = sid
  join course c         on c.id  = cs.course_id
  where cs.term_id <> p_term_id;

  -- ── เพดานและพื้นหน่วยกิต ────────────────────────────────────────
  select * into v_policy
  from registration_policy rp
  where rp.institution_id = v_inst
    and rp.level          = v_level
    and rp.term_kind      = v_term.kind
    and rp.effective_from_year_be <= v_year_be
  order by rp.effective_from_year_be desc
  limit 1;

  select coalesce(sum(c.credits), 0) into v_credits
  from unnest(v_sections) sid
  join class_section cs on cs.id = sid
  join course c         on c.id  = cs.course_id;

  if v_policy.id is not null then
    if v_credits > v_policy.max_credits then
      return query select 'CREDIT_MAX',
        case when v_policy.max_credits_with_approval is not null
              and v_credits <= v_policy.max_credits_with_approval
             then 'warn'::registration_check_severity
             else 'block'::registration_check_severity end,
        format('ลงทะเบียน %s หน่วยกิต เกินเพดาน %s หน่วยกิต',
               to_char(v_credits, 'FM999990.0'), to_char(v_policy.max_credits, 'FM999990.0')),
        null::uuid,
        registration_waived(p_student_id, p_term_id, 'CREDIT_MAX', null),
        jsonb_build_object('credits', v_credits, 'max', v_policy.max_credits,
                           'max_with_approval', v_policy.max_credits_with_approval);
    end if;

    if v_credits < v_policy.min_credits then
      return query select 'CREDIT_MIN', 'warn'::registration_check_severity,
        format('ลงทะเบียน %s หน่วยกิต ต่ำกว่าเกณฑ์ขั้นต่ำ %s หน่วยกิต',
               to_char(v_credits, 'FM999990.0'), to_char(v_policy.min_credits, 'FM999990.0')),
        null::uuid,
        registration_waived(p_student_id, p_term_id, 'CREDIT_MIN', null),
        jsonb_build_object('credits', v_credits, 'min', v_policy.min_credits);
    end if;
  end if;

  -- ── วิชาบังคับก่อน ──────────────────────────────────────────────
  return query
  select 'PREREQ_NOT_MET', 'block'::registration_check_severity,
         format('%s ต้องผ่าน %s (%s) ก่อน', c.name_th, pc.name_th, pc.code),
         cs.id,
         registration_waived(p_student_id, p_term_id, 'PREREQ_NOT_MET', cs.id),
         jsonb_build_object('prerequisite_course_id', pc.id, 'prerequisite_code', pc.code)
  from unnest(v_sections) sid
  join class_section cs        on cs.id = sid
  join course c                on c.id  = cs.course_id
  join course_prerequisite cp  on cp.course_id = cs.course_id
                              and cp.curriculum_version_id = v_cv
                              and cp.kind = 'must_pass'
  join course pc               on pc.id = cp.prerequisite_course_id
  where not exists (
    select 1 from v_student_course_credit v
    where v.student_id = p_student_id
      and v.course_id  = cp.prerequisite_course_id
      and v.earns_credit
  );

  -- ── ตารางเรียนชนกัน ─────────────────────────────────────────────
  -- รายงานผูกกับกลุ่มเรียนที่ "กำลังจะเพิ่ม" เสมอ ไม่ใช่กลุ่มที่ลงไปแล้ว
  -- เพราะนั่นคือสิ่งที่ผู้ใช้กำลังทำและเป็นสิ่งที่การยกเว้นต้องชี้ไปหา
  if v_policy.id is null or not v_policy.allow_time_conflict then
    return query
    select 'TIME_CONFLICT', 'block'::registration_check_severity,
           format('%s ชนกับ %s วัน%s คาบ %s–%s',
                  pick.subject_name, pick.other_name,
                  (array['จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์','อาทิตย์'])[t1.day_of_week],
                  greatest(t1.period_from, t2.period_from),
                  least(t1.period_to,   t2.period_to)),
           pick.subject_id,
           registration_waived(p_student_id, p_term_id, 'TIME_CONFLICT', pick.subject_id),
           jsonb_build_object('conflicts_with', pick.other_id, 'day_of_week', t1.day_of_week)
    from unnest(v_sections) s1
    join unnest(v_sections) s2 on s2 > s1
    join class_section cs1 on cs1.id = s1
    join class_section cs2 on cs2.id = s2
    join course c1 on c1.id = cs1.course_id
    join course c2 on c2.id = cs2.course_id
    join section_timeslot t1 on t1.class_section_id = cs1.id
    join section_timeslot t2 on t2.class_section_id = cs2.id
                            and t2.day_of_week = t1.day_of_week
                            and int4range(t2.period_from, t2.period_to, '[]')
                             && int4range(t1.period_from, t1.period_to, '[]')
    cross join lateral (
      select case when flip then cs2.id      else cs1.id      end as subject_id,
             case when flip then cs1.id      else cs2.id      end as other_id,
             case when flip then c2.name_th  else c1.name_th  end as subject_name,
             case when flip then c1.name_th  else c2.name_th  end as other_name
      from (select cs2.id = any(v_new) and cs1.id <> all(v_new) as flip) f
    ) pick;
  end if;

  -- ── ที่นั่งเต็ม ──────────────────────────────────────────────────
  return query
  select 'SECTION_FULL', 'block'::registration_check_severity,
         format('%s กลุ่ม %s เต็มแล้ว (%s จาก %s ที่นั่ง)',
                c.name_th, cs.section_no, taken.n, cs.capacity),
         cs.id,
         registration_waived(p_student_id, p_term_id, 'SECTION_FULL', cs.id),
         jsonb_build_object('taken', taken.n, 'capacity', cs.capacity)
  from unnest(v_new) sid
  join class_section cs on cs.id = sid
  join course c         on c.id  = cs.course_id
  cross join lateral (
    select count(*) as n from enrollment e
    where e.class_section_id = cs.id and e.status = 'enrolled'
  ) taken
  where taken.n >= cs.capacity
    and not exists (select 1 from enrollment e2
                    where e2.class_section_id = cs.id
                      and e2.student_id = p_student_id
                      and e2.status = 'enrolled');

  -- ── เคยผ่านรายวิชานี้แล้ว ───────────────────────────────────────
  return query
  select 'ALREADY_PASSED', 'warn'::registration_check_severity,
         format('เคยผ่าน %s มาแล้ว การลงซ้ำจะนับเป็นการเรียนซ้ำ', c.name_th),
         cs.id,
         registration_waived(p_student_id, p_term_id, 'ALREADY_PASSED', cs.id),
         '{}'::jsonb
  from unnest(v_new) sid
  join class_section cs on cs.id = sid
  join course c         on c.id  = cs.course_id
  where exists (
    select 1 from v_student_course_credit v
    where v.student_id = p_student_id and v.course_id = cs.course_id and v.earns_credit
  );

  -- ── รายวิชาไม่อยู่ในหลักสูตรของนักศึกษา ────────────────────────
  return query
  select 'NOT_IN_CURRICULUM', 'warn'::registration_check_severity,
         format('%s ไม่อยู่ในโครงสร้างหลักสูตรของนักศึกษา จะไม่ถูกนับในการตรวจจบ', c.name_th),
         cs.id,
         registration_waived(p_student_id, p_term_id, 'NOT_IN_CURRICULUM', cs.id),
         jsonb_build_object('curriculum_version_id', v_cv)
  from unnest(v_new) sid
  join class_section cs on cs.id = sid
  join course c         on c.id  = cs.course_id
  where not exists (
    select 1 from curriculum_course cc
    where cc.curriculum_version_id = v_cv and cc.course_id = cs.course_id
  );
end $$;

comment on function check_registration is
  'คืนรายการปัญหาทั้งหมดในครั้งเดียว ไม่หยุดที่ข้อแรก เพราะนักศึกษาต้องเห็นทุกอย่างที่ต้องแก้ในรอบเดียว';

-- ───────────────────────────────────────────────────────────────────
-- ลงทะเบียนจริง
-- ตรวจก่อนเสมอ ถ้ายังมีข้อ block ที่ไม่ได้ยกเว้น จะไม่เขียนอะไรลงฐานข้อมูลเลย
-- ───────────────────────────────────────────────────────────────────
create or replace function register_courses(
  p_student_id  uuid,
  p_term_id     uuid,
  p_section_ids uuid[]
) returns integer language plpgsql as $$
declare
  v_blockers text;
  v_count    integer;
begin
  select string_agg(format('[%s] %s', code, message_th), E'\n')
    into v_blockers
  from check_registration(p_student_id, p_term_id, p_section_ids)
  where severity = 'block' and not waived;

  if v_blockers is not null then
    raise exception E'ลงทะเบียนไม่ได้ ติดเงื่อนไขต่อไปนี้\n%', v_blockers
      using errcode = 'check_violation';
  end if;

  insert into enrollment (student_id, class_section_id, term_id, attempt_no, registered_by)
  select p_student_id, cs.id, p_term_id,
         1 + (select count(*)
              from enrollment e
              join class_section cs2 on cs2.id = e.class_section_id
              where e.student_id = p_student_id
                and cs2.course_id = cs.course_id
                and e.status in ('enrolled', 'withdrawn')),
         current_actor_id()
  from unnest(coalesce(p_section_ids, '{}'::uuid[])) sid
  join class_section cs on cs.id = sid
  on conflict (student_id, class_section_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security ของตารางใหม่
-- ───────────────────────────────────────────────────────────────────
alter table academic_holiday enable row level security;
alter table academic_holiday force  row level security;
create policy tenant_isolation on academic_holiday
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

alter table registration_policy enable row level security;
alter table registration_policy force  row level security;
create policy tenant_isolation on registration_policy
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

alter table section_timeslot enable row level security;
alter table section_timeslot force  row level security;
create policy tenant_isolation on section_timeslot
  using (exists (select 1 from class_section cs
                 where cs.id = section_timeslot.class_section_id
                   and cs.institution_id = current_institution_id()));

alter table registration_hold enable row level security;
alter table registration_hold force  row level security;
create policy tenant_isolation on registration_hold
  using (exists (select 1 from student s
                 where s.id = registration_hold.student_id
                   and s.institution_id = current_institution_id()));

alter table registration_override enable row level security;
alter table registration_override force  row level security;
create policy tenant_isolation on registration_override
  using (exists (select 1 from student s
                 where s.id = registration_override.student_id
                   and s.institution_id = current_institution_id()));

-- เฉพาะบทบาทที่มีอำนาจเท่านั้นจึงยกเว้นกฎได้
create policy override_by_authority on registration_override
  as restrictive
  using (current_app_role() in ('registrar', 'academic', 'director', 'admin'))
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0010_finance.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0010_finance.sql
-- การเงิน — ค่าธรรมเนียม ใบแจ้งหนี้ ผ่อนชำระ รับชำระ กระทบยอด บัญชีแยกประเภท
--
-- ทำไมโมดูลนี้สำคัญที่สุดสำหรับวิทยาลัยเอกชน
-- รายได้มาจากสองทางเท่านั้น คือค่าเทอมกับเงินอุดหนุนรายบุคคล ทั้งสองทางผูก
-- กับ "จำนวนนักศึกษาที่มีตัวตนจริงและยังอยู่" ระบบนี้จึงไม่ใช่งานธุรการ
-- แต่เป็นระบบรักษารายได้
--
-- หลักสี่ข้อ
-- 1. บัญชีเป็น double-entry ตั้งแต่วันแรก — ย้ายทีหลังแทบเป็นไปไม่ได้
--    ทุกรายการต้องเดบิตเท่ากับเครดิต บังคับด้วย constraint trigger แบบ deferred
-- 2. เงินที่รับมาไม่ผูกกับใบแจ้งหนี้โดยตรง แต่ผ่าน payment_allocation
--    เพราะเงินก้อนเดียวอาจตัดหลายงวด และงวดเดียวอาจมาจากหลายก้อน
-- 3. กระทบยอดอัตโนมัติเป็นหัวใจ — เจ้าหน้าที่ควรทำงานกับรายการที่จับคู่ไม่ได้
--    ไม่ใช่ทั้งหมด ระบบให้คะแนนความมั่นใจและจำรูปแบบที่ยืนยันแล้วไว้ใช้ครั้งต่อไป
-- 4. การระงับสิทธิ์ไปที่ registration_hold ไม่ใช่ให้งานทะเบียนมาอ่านใบแจ้งหนี้เอง
--
-- นอกขอบเขตไฟล์นี้ — จัดซื้อจัดจ้าง งบประมาณ เจ้าหนี้ และ e-Tax Invoice
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บัญชีแยกประเภท
-- ───────────────────────────────────────────────────────────────────
create type ledger_account_type as enum ('asset', 'liability', 'equity', 'revenue', 'expense');

create table ledger_account (
  id             uuid                primary key default gen_random_uuid(),
  institution_id uuid                not null references institution on delete restrict,
  code           text                not null,     -- '1102' ลูกหนี้ค่าเล่าเรียน
  name_th        text                not null,
  type           ledger_account_type not null,
  active         boolean             not null default true,
  unique (institution_id, code)
);

create table ledger_transaction (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  occurred_on    date        not null,
  memo           text        not null,
  ref_type       text,                             -- 'invoice' | 'payment' | 'writeoff'
  ref_id         uuid,
  posted_at      timestamptz not null default now(),
  posted_by      uuid
);
create index on ledger_transaction (institution_id, occurred_on);
create index on ledger_transaction (ref_type, ref_id);

create table ledger_entry (
  id             uuid         primary key default gen_random_uuid(),
  transaction_id uuid         not null references ledger_transaction on delete cascade,
  account_id     uuid         not null references ledger_account on delete restrict,
  debit          numeric(14,2) not null default 0,
  credit         numeric(14,2) not null default 0,
  memo           text,
  check (debit >= 0 and credit >= 0),
  check ((debit = 0) <> (credit = 0))              -- ต้องเป็นด้านใดด้านหนึ่งเท่านั้น
);
create index on ledger_entry (transaction_id);
create index on ledger_entry (account_id);

-- ทุกรายการต้องสมดุล ตรวจตอน commit เพื่อให้ใส่บรรทัดทีละบรรทัดได้
create or replace function ledger_balanced() returns trigger
language plpgsql as $$
declare v_diff numeric(14,2);
begin
  select coalesce(sum(debit) - sum(credit), 0) into v_diff
  from ledger_entry where transaction_id = coalesce(new.transaction_id, old.transaction_id);

  if v_diff <> 0 then
    raise exception 'รายการบัญชีไม่สมดุล เดบิตต่างจากเครดิต % บาท (transaction=%)',
      v_diff, coalesce(new.transaction_id, old.transaction_id);
  end if;
  return null;
end $$;

create constraint trigger ledger_entry_balanced
  after insert or update or delete on ledger_entry
  deferrable initially deferred
  for each row execute function ledger_balanced();

comment on trigger ledger_entry_balanced on ledger_entry is
  'ตรวจตอน commit ไม่ใช่ตอน insert เพื่อให้ใส่บรรทัดเดบิตกับเครดิตทีละบรรทัดได้';

-- ───────────────────────────────────────────────────────────────────
-- โครงสร้างค่าธรรมเนียม
-- ต้องเก็บเลขที่ประกาศอัตราค่าธรรมเนียมไว้ด้วย เพราะโรงเรียนเอกชนต้อง
-- ได้รับอนุมัติก่อนเก็บ และถูกตรวจสอบย้อนหลังได้
-- ───────────────────────────────────────────────────────────────────
create type fee_item_kind as enum (
  'tuition',       -- ค่าเล่าเรียน
  'lab_material',  -- ค่าวัสดุฝึก
  'activity',      -- ค่ากิจกรรม
  'insurance',     -- ค่าประกันอุบัติเหตุ
  'uniform',       -- ค่าเครื่องแบบและชุดปฏิบัติการ
  'book',          -- ค่าหนังสือและอุปกรณ์การเรียน
  'exam',          -- ค่าธรรมเนียมการสอบ
  'dormitory',     -- ค่าหอพัก
  'other'
);

create table fee_item (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  code           text          not null,
  name_th        text          not null,
  kind           fee_item_kind not null,
  subsidised     boolean       not null default false,  -- อยู่ในเงินอุดหนุนเรียนฟรี 15 ปีหรือไม่
  refundable     boolean       not null default false,
  revenue_account_id uuid      references ledger_account,
  unique (institution_id, code)
);
comment on column fee_item.subsidised is
  'รายการที่รัฐอุดหนุนสำหรับ ปวช. แต่ ปวส. ต้องจ่ายเอง ระบบจึงคิดคนละสูตรตามระดับ';

create table fee_schedule (
  id                 uuid                primary key default gen_random_uuid(),
  institution_id     uuid                not null references institution   on delete restrict,
  academic_year_id   uuid                not null references academic_year on delete restrict,
  level              qualification_level not null,
  study_year         smallint            not null check (study_year between 1 and 4),
  program_id         uuid                references program,   -- null = ใช้กับทุกสาขา
  announcement_no    text,                                     -- เลขที่ประกาศอัตราค่าธรรมเนียม
  announced_on       date,
  active             boolean             not null default true,
  unique (institution_id, academic_year_id, level, study_year, program_id)
);

create table fee_schedule_line (
  id               uuid          primary key default gen_random_uuid(),
  fee_schedule_id  uuid          not null references fee_schedule on delete cascade,
  fee_item_id      uuid          not null references fee_item     on delete restrict,
  term_ordinal     smallint      not null check (term_ordinal between 1 and 3),
  amount           numeric(12,2) not null check (amount >= 0),
  unique (fee_schedule_id, fee_item_id, term_ordinal)
);

-- ───────────────────────────────────────────────────────────────────
-- ส่วนลด ทุน และแหล่งเงินภายนอก
-- ───────────────────────────────────────────────────────────────────
create type funding_kind as enum (
  'scholarship',    -- ทุนการศึกษาของวิทยาลัย
  'sibling',        -- ส่วนลดพี่น้อง
  'staff_child',    -- ส่วนลดบุตรบุคลากร
  'gov_subsidy',    -- เงินอุดหนุนรายบุคคล
  'student_loan',   -- กยศ.
  'employer',       -- ทุนสถานประกอบการ
  'other'
);

create table funding_source (
  id             uuid         primary key default gen_random_uuid(),
  institution_id uuid         not null references institution on delete restrict,
  kind           funding_kind not null,
  name_th        text         not null,
  external_ref   text,                                -- เลขที่โครงการหรือรหัสผู้ให้ทุน
  active         boolean      not null default true
);

create table student_funding (
  id                uuid          primary key default gen_random_uuid(),
  student_id        uuid          not null references student        on delete cascade,
  funding_source_id uuid          not null references funding_source on delete restrict,
  academic_year_id  uuid          not null references academic_year  on delete restrict,
  term_id           uuid          references term,          -- null = ใช้ทั้งปี
  percent_off       numeric(5,2)  check (percent_off between 0 and 100),
  amount            numeric(12,2) check (amount >= 0),
  approved_by       uuid,
  approved_at       timestamptz,
  document_no       text,
  note              text,
  check (percent_off is not null or amount is not null)
);
create index on student_funding (student_id, academic_year_id);

-- กยศ. — ต้องติดตามเป็นขั้น เพราะเงินเข้าช้ากว่ากำหนดชำระเสมอ
create type loan_status as enum (
  'draft', 'submitted', 'college_certified', 'approved', 'disbursed', 'rejected', 'cancelled'
);

create table student_loan (
  id                 uuid          primary key default gen_random_uuid(),
  student_id         uuid          not null references student       on delete cascade,
  academic_year_id   uuid          not null references academic_year on delete restrict,
  term_id            uuid          references term,
  loan_type          text          not null default 'ลักษณะที่ 1',
  requested_amount   numeric(12,2) not null,
  approved_amount    numeric(12,2),
  disbursed_amount   numeric(12,2) not null default 0,
  status             loan_status   not null default 'draft',
  submitted_on       date,
  certified_on       date,
  approved_on        date,
  disbursed_on       date,
  external_ref       text,
  note               text,
  unique (student_id, academic_year_id, term_id)
);
create index on student_loan (status) where status <> 'disbursed';

-- ───────────────────────────────────────────────────────────────────
-- ใบแจ้งหนี้และงวดผ่อนชำระ
-- ───────────────────────────────────────────────────────────────────
create type invoice_status as enum ('draft', 'issued', 'partially_paid', 'paid', 'void', 'written_off');

create table invoice (
  id             uuid           primary key default gen_random_uuid(),
  institution_id uuid           not null references institution on delete restrict,
  student_id     uuid           not null references student     on delete restrict,
  term_id        uuid           not null references term        on delete restrict,
  invoice_no     text           not null,
  issued_on      date           not null default current_date,
  due_on         date           not null,
  subtotal       numeric(12,2)  not null default 0,
  discount_total numeric(12,2)  not null default 0,
  total          numeric(12,2)  not null default 0,
  paid_total     numeric(12,2)  not null default 0,
  status         invoice_status not null default 'draft',
  -- อ้างอิงสำหรับ PromptPay Bill Payment
  ref1           text,          -- รหัสนักศึกษา
  ref2           text,          -- เลขที่ใบแจ้งหนี้แบบตัวเลขล้วน
  void_reason    text,
  created_at     timestamptz    not null default now(),
  unique (institution_id, invoice_no),
  unique (student_id, term_id),
  check (total >= 0 and paid_total >= 0)
);
create index on invoice (student_id);
create index on invoice (status, due_on) where status in ('issued', 'partially_paid');
create index on invoice (ref2);

comment on column invoice.ref2 is
  'ตัวเลขล้วน ใช้เป็น Reference 2 ของ PromptPay Bill Payment ซึ่งเป็นกุญแจของการกระทบยอดอัตโนมัติ';

create table invoice_line (
  id           uuid          primary key default gen_random_uuid(),
  invoice_id   uuid          not null references invoice  on delete cascade,
  fee_item_id  uuid          not null references fee_item on delete restrict,
  description  text          not null,
  amount       numeric(12,2) not null,
  discount     numeric(12,2) not null default 0,
  funding_id   uuid          references student_funding,   -- ที่มาของส่วนลด
  check (amount >= 0 and discount >= 0 and discount <= amount)
);
create index on invoice_line (invoice_id);

create type installment_status as enum ('pending', 'partially_paid', 'paid', 'overdue', 'waived');

create table installment (
  id          uuid               primary key default gen_random_uuid(),
  invoice_id  uuid               not null references invoice on delete cascade,
  seq         smallint           not null check (seq > 0),
  due_on      date               not null,
  amount      numeric(12,2)      not null check (amount > 0),
  paid_amount numeric(12,2)      not null default 0,
  penalty     numeric(12,2)      not null default 0,
  status      installment_status not null default 'pending',
  unique (invoice_id, seq)
);
create index on installment (due_on) where status in ('pending', 'partially_paid', 'overdue');

-- ───────────────────────────────────────────────────────────────────
-- การรับชำระ
-- ───────────────────────────────────────────────────────────────────
create type payment_method as enum (
  'cash', 'bank_transfer', 'promptpay', 'credit_card',
  'counter_service', 'direct_debit', 'gov_subsidy', 'student_loan', 'scholarship', 'adjustment'
);
create type payment_status as enum ('pending', 'reconciled', 'rejected', 'refunded');

create table payment (
  id             uuid           primary key default gen_random_uuid(),
  institution_id uuid           not null references institution on delete restrict,
  student_id     uuid           references student,        -- null ได้ตอนยังจับคู่ไม่ได้
  received_on    date           not null,
  amount         numeric(12,2)  not null check (amount > 0),
  method         payment_method not null,
  bank_ref       text,                                     -- เลขอ้างอิงจากธนาคาร
  receipt_no     text,
  status         payment_status not null default 'pending',
  reconciled_at  timestamptz,
  received_by    uuid,
  note           text,
  created_at     timestamptz    not null default now(),
  unique (institution_id, receipt_no)
);
create index on payment (student_id);
create index on payment (status, received_on);

-- เงินก้อนเดียวตัดได้หลายงวด และงวดเดียวรับเงินได้หลายก้อน
create table payment_allocation (
  id             uuid          primary key default gen_random_uuid(),
  payment_id     uuid          not null references payment     on delete cascade,
  installment_id uuid          not null references installment on delete restrict,
  amount         numeric(12,2) not null check (amount > 0),
  allocated_at   timestamptz   not null default now(),
  unique (payment_id, installment_id)
);
create index on payment_allocation (installment_id);

-- ───────────────────────────────────────────────────────────────────
-- รายการเดินบัญชีจากธนาคารและการจับคู่
-- ───────────────────────────────────────────────────────────────────
create type match_state as enum ('unmatched', 'suggested', 'confirmed', 'ignored');

create table bank_transaction (
  id                uuid          primary key default gen_random_uuid(),
  institution_id    uuid          not null references institution on delete restrict,
  posted_at         timestamptz   not null,
  amount            numeric(12,2) not null,
  counterparty      text,                                   -- ชื่อผู้โอน
  bank_ref          text,
  ref1              text,
  ref2              text,
  raw               jsonb         not null default '{}'::jsonb,
  state             match_state   not null default 'unmatched',
  matched_invoice_id uuid         references invoice,
  confidence        smallint      check (confidence between 0 and 100),
  match_reason      text,
  payment_id        uuid          references payment,
  imported_at       timestamptz   not null default now(),
  unique (institution_id, bank_ref, posted_at, amount)
);
create index on bank_transaction (state) where state <> 'confirmed';
create index on bank_transaction (institution_id, posted_at);

-- จำรูปแบบที่เจ้าหน้าที่ยืนยันด้วยมือ เพื่อให้ครั้งต่อไปจับคู่เองได้
create table reconciliation_hint (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  counterparty   text        not null,
  student_id     uuid        not null references student on delete cascade,
  hit_count      integer     not null default 1,
  last_used_at   timestamptz not null default now(),
  unique (institution_id, counterparty)
);
comment on table reconciliation_hint is
  'ผู้ปกครองมักโอนจากบัญชีเดิมทุกงวด การจำชื่อผู้โอนคู่กับนักศึกษาทำให้ครั้งต่อไปจับคู่อัตโนมัติได้';

-- ───────────────────────────────────────────────────────────────────
-- ออกใบแจ้งหนี้จากโครงสร้างค่าธรรมเนียม
-- ───────────────────────────────────────────────────────────────────
create sequence if not exists invoice_no_seq;

-- p_installments เป็น integer ไม่ใช่ smallint เพราะ PostgreSQL ไม่แปลงเลขจำนวนเต็ม
-- ธรรมดาให้เป็น smallint ตอนเลือกฟังก์ชัน ทำให้ผู้เรียกต้อง cast เองทุกครั้ง
create or replace function issue_invoice(
  p_student_id  uuid,
  p_term_id     uuid,
  p_installments integer default 1
) returns uuid language plpgsql as $$
declare
  v_inst      uuid;
  v_year_id   uuid;
  v_level     qualification_level;
  v_study_yr  smallint;
  v_program   uuid;
  v_ordinal   smallint;
  v_sched     uuid;
  v_invoice   uuid;
  v_no        text;
  v_code      text;
  v_subtotal  numeric(12,2) := 0;
  v_discount  numeric(12,2) := 0;
  v_due       date;
  v_year_be   smallint;   -- ปีการศึกษาที่กำลังออกใบแจ้งหนี้
  v_admitted  smallint;   -- ปีที่นักศึกษาเข้าศึกษา ใช้คำนวณชั้นปี
  i           smallint;
begin
  select s.institution_id, s.student_code, s.admitted_year_be
    into v_inst, v_code, v_admitted
  from student s where s.id = p_student_id;

  if v_inst is null then
    raise exception 'ไม่พบนักศึกษา %', p_student_id;
  end if;

  select t.academic_year_id, t.ordinal, ay.year_be
    into v_year_id, v_ordinal, v_year_be
  from term t join academic_year ay on ay.id = t.academic_year_id
  where t.id = p_term_id;

  select p.level, p.id into v_level, v_program
  from student_curriculum sc
  join curriculum_version cv on cv.id = sc.curriculum_version_id
  join curriculum c          on c.id  = cv.curriculum_id
  join program_track pt      on pt.id = c.program_track_id
  join program p             on p.id  = pt.program_id
  where sc.student_id = p_student_id and sc.effective_to is null;

  if v_level is null then
    raise exception 'นักศึกษา % ยังไม่ได้กำหนดหลักสูตร ออกใบแจ้งหนี้ไม่ได้', p_student_id;
  end if;

  -- ชั้นปีคำนวณจากปีการศึกษาที่ออกใบแจ้งหนี้ เทียบกับปีที่เข้าศึกษา
  v_study_yr := least(greatest(v_year_be - v_admitted + 1, 1), 4);

  -- เลือกโครงสร้างค่าธรรมเนียม เจาะจงสาขาก่อน ถ้าไม่มีจึงใช้แบบทั่วไป
  select fs.id into v_sched
  from fee_schedule fs
  where fs.institution_id   = v_inst
    and fs.academic_year_id = v_year_id
    and fs.level            = v_level
    and fs.study_year       = v_study_yr
    and fs.active
    and (fs.program_id = v_program or fs.program_id is null)
  order by fs.program_id nulls last
  limit 1;

  if v_sched is null then
    raise exception 'ไม่พบโครงสร้างค่าธรรมเนียมสำหรับ % ชั้นปี % ปีการศึกษา %', v_level, v_study_yr, v_year_be;
  end if;

  v_no := to_char(v_year_be, 'FM0000') || '-' || lpad(nextval('invoice_no_seq')::text, 6, '0');
  select t.starts_on + 30 into v_due from term t where t.id = p_term_id;

  insert into invoice (institution_id, student_id, term_id, invoice_no, due_on, ref1, ref2, status)
  values (v_inst, p_student_id, p_term_id, 'INV-' || v_no, v_due,
          v_code, regexp_replace(v_no, '\D', '', 'g'), 'draft')
  returning id into v_invoice;

  -- บรรทัดค่าธรรมเนียม พร้อมหักส่วนลดและทุนที่นักศึกษาได้รับ
  insert into invoice_line (invoice_id, fee_item_id, description, amount, discount, funding_id)
  select
    v_invoice,
    fi.id,
    fi.name_th,
    fsl.amount,
    least(
      coalesce(sum(coalesce(sf.amount, fsl.amount * sf.percent_off / 100)), 0),
      fsl.amount
    ),
    (array_agg(sf.id order by sf.id) filter (where sf.id is not null))[1]
  from fee_schedule_line fsl
  join fee_item fi on fi.id = fsl.fee_item_id
  left join student_funding sf
         on sf.student_id       = p_student_id
        and sf.academic_year_id = v_year_id
        and (sf.term_id is null or sf.term_id = p_term_id)
        and sf.approved_at is not null
  where fsl.fee_schedule_id = v_sched
    and fsl.term_ordinal    = v_ordinal
  group by fi.id, fi.name_th, fsl.amount;

  select coalesce(sum(amount), 0), coalesce(sum(discount), 0)
    into v_subtotal, v_discount
  from invoice_line where invoice_id = v_invoice;

  update invoice
  set subtotal = v_subtotal, discount_total = v_discount, total = v_subtotal - v_discount,
      status = 'issued'
  where id = v_invoice;

  -- แบ่งงวด งวดสุดท้ายรับเศษ เพื่อให้ผลรวมตรงกับยอดใบแจ้งหนี้เสมอ
  for i in 1..greatest(p_installments, 1) loop
    insert into installment (invoice_id, seq, due_on, amount)
    values (
      v_invoice, i,
      v_due + ((i - 1) * 60),
      case when i < greatest(p_installments, 1)
           then round((v_subtotal - v_discount) / greatest(p_installments, 1), 2)
           else (v_subtotal - v_discount)
                - round((v_subtotal - v_discount) / greatest(p_installments, 1), 2)
                  * (greatest(p_installments, 1) - 1)
      end
    );
  end loop;

  return v_invoice;
end $$;

comment on function issue_invoice is
  'ออกใบแจ้งหนี้หนึ่งใบต่อนักศึกษาต่อภาคเรียน หักทุนและส่วนลดที่อนุมัติแล้วให้อัตโนมัติ';

-- ───────────────────────────────────────────────────────────────────
-- รับชำระและตัดยอด
-- ตัดงวดที่ครบกำหนดก่อนเสมอ (FIFO) เพื่อให้ค่าปรับล่าช้าคำนวณถูก
-- ───────────────────────────────────────────────────────────────────
create or replace function post_payment(p_payment_id uuid)
returns numeric language plpgsql as $$
declare
  v_remaining numeric(12,2);
  v_student   uuid;
  r           record;
  v_take      numeric(12,2);
begin
  select amount, student_id into v_remaining, v_student
  from payment where id = p_payment_id;

  if v_student is null then
    raise exception 'เงินรับก้อนนี้ยังไม่ได้ระบุว่าเป็นของนักศึกษาคนไหน (payment=%)', p_payment_id;
  end if;

  for r in
    select i.id, i.amount + i.penalty - i.paid_amount as outstanding
    from installment i
    join invoice inv on inv.id = i.invoice_id
    where inv.student_id = v_student
      and inv.status not in ('void', 'written_off')
      and i.status <> 'paid'
      and i.amount + i.penalty - i.paid_amount > 0
    order by i.due_on, i.seq
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, r.outstanding);

    insert into payment_allocation (payment_id, installment_id, amount)
    values (p_payment_id, r.id, v_take)
    on conflict (payment_id, installment_id)
      do update set amount = payment_allocation.amount + excluded.amount;

    update installment
    set paid_amount = paid_amount + v_take,
        status = case when paid_amount + v_take >= amount + penalty
                      then 'paid'::installment_status
                      else 'partially_paid'::installment_status end
    where id = r.id;

    v_remaining := v_remaining - v_take;
  end loop;

  -- ปรับยอดบนใบแจ้งหนี้
  update invoice inv
  set paid_total = sub.paid,
      status = case when sub.paid >= inv.total then 'paid'::invoice_status
                    when sub.paid > 0          then 'partially_paid'::invoice_status
                    else inv.status end
  from (
    select i.invoice_id, sum(i.paid_amount) as paid
    from installment i
    join invoice v on v.id = i.invoice_id
    where v.student_id = v_student
    group by i.invoice_id
  ) sub
  where inv.id = sub.invoice_id;

  update payment
  set status = 'reconciled', reconciled_at = now()
  where id = p_payment_id;

  return v_remaining;   -- เงินเหลือที่ยังไม่ได้ตัด (ชำระเกิน)
end $$;

comment on function post_payment is
  'คืนค่าเงินที่เหลือหลังตัดครบทุกงวด ถ้ามากกว่าศูนย์แปลว่าชำระเกิน ต้องให้เจ้าหน้าที่ตัดสินใจว่าจะยกไปงวดหน้าหรือคืนเงิน';

-- ───────────────────────────────────────────────────────────────────
-- กระทบยอดอัตโนมัติ
-- ให้คะแนนความมั่นใจแล้วจับคู่เองเฉพาะที่มั่นใจสูง ที่เหลือส่งให้คนตัดสิน
-- ───────────────────────────────────────────────────────────────────
create or replace function reconcile_bank_transactions(p_institution_id uuid)
returns table (auto_matched integer, suggested integer, unmatched integer)
language plpgsql as $$
declare
  bt        record;
  v_inv     uuid;
  v_conf    smallint;
  v_reason  text;
  v_student uuid;
  v_pay     uuid;
  v_auto    integer := 0;
  v_sug     integer := 0;
begin
  for bt in
    select * from bank_transaction
    where institution_id = p_institution_id and state = 'unmatched' and amount > 0
    order by posted_at
  loop
    v_inv := null; v_conf := 0; v_reason := null;

    -- ระดับ 1: Reference 2 ตรงกับใบแจ้งหนี้ตรง ๆ
    select i.id into v_inv from invoice i
    where i.institution_id = p_institution_id and i.ref2 = bt.ref2
      and i.status in ('issued', 'partially_paid')
    limit 1;
    if v_inv is not null then
      v_conf := 100; v_reason := 'เลขอ้างอิงที่สองตรงกับใบแจ้งหนี้';
    end if;

    -- ระดับ 2: Reference 1 คือรหัสนักศึกษา และยอดตรงกับงวดที่ค้าง
    if v_inv is null and bt.ref1 is not null then
      select i.id into v_inv
      from invoice i
      join student s     on s.id = i.student_id and s.student_code = bt.ref1
      join installment n on n.invoice_id = i.id
      where i.institution_id = p_institution_id
        and i.status in ('issued', 'partially_paid')
        and n.amount + n.penalty - n.paid_amount = bt.amount
      limit 1;
      if v_inv is not null then
        v_conf := 90; v_reason := 'รหัสนักศึกษาและยอดเงินตรงกับงวดที่ค้าง';
      end if;
    end if;

    -- ระดับ 3: เคยยืนยันชื่อผู้โอนคนนี้ไว้แล้ว
    if v_inv is null and bt.counterparty is not null then
      select h.student_id into v_student
      from reconciliation_hint h
      where h.institution_id = p_institution_id and h.counterparty = bt.counterparty;

      if v_student is not null then
        select i.id into v_inv
        from invoice i
        where i.student_id = v_student and i.status in ('issued', 'partially_paid')
        order by i.due_on
        limit 1;
        if v_inv is not null then
          v_conf := 80; v_reason := 'ผู้โอนคนนี้เคยชำระให้นักศึกษาคนนี้มาก่อน';
        end if;
      end if;
    end if;

    -- ระดับ 4: ยอดตรงกับงวดที่ค้างเพียงงวดเดียวในระบบ
    if v_inv is null then
      select i.id into v_inv
      from invoice i
      join installment n on n.invoice_id = i.id
      where i.institution_id = p_institution_id
        and i.status in ('issued', 'partially_paid')
        and n.amount + n.penalty - n.paid_amount = bt.amount
        and n.due_on between bt.posted_at::date - 45 and bt.posted_at::date + 15
      group by i.id
      having count(*) = 1
      limit 1;
      if v_inv is not null then
        v_conf := 60; v_reason := 'ยอดเงินตรงกับงวดที่ค้างเพียงงวดเดียวในช่วงเวลาใกล้เคียง';
      end if;
    end if;

    if v_inv is null then
      continue;
    end if;

    if v_conf >= 90 then
      -- มั่นใจพอที่จะตัดยอดเอง
      select student_id into v_student from invoice where id = v_inv;

      insert into payment (institution_id, student_id, received_on, amount, method,
                           bank_ref, status, note)
      values (p_institution_id, v_student, bt.posted_at::date, bt.amount, 'promptpay',
              bt.bank_ref, 'pending', v_reason)
      returning id into v_pay;

      perform post_payment(v_pay);

      update bank_transaction
      set state = 'confirmed', matched_invoice_id = v_inv, confidence = v_conf,
          match_reason = v_reason, payment_id = v_pay
      where id = bt.id;

      v_auto := v_auto + 1;
    else
      update bank_transaction
      set state = 'suggested', matched_invoice_id = v_inv,
          confidence = v_conf, match_reason = v_reason
      where id = bt.id;

      v_sug := v_sug + 1;
    end if;
  end loop;

  return query
  select v_auto, v_sug,
         (select count(*)::integer from bank_transaction
          where institution_id = p_institution_id and state = 'unmatched');
end $$;

comment on function reconcile_bank_transactions is
  'ตัดยอดเองเฉพาะที่มั่นใจตั้งแต่ 90 ขึ้นไป ที่เหลือขึ้นเป็นข้อเสนอให้เจ้าหน้าที่กดยืนยัน';

-- ───────────────────────────────────────────────────────────────────
-- ค่าปรับล่าช้าและการระงับสิทธิ์
-- งานการเงินเขียน registration_hold งานทะเบียนไม่ต้องรู้จักใบแจ้งหนี้
-- ───────────────────────────────────────────────────────────────────
create table late_fee_policy (
  id                    uuid          primary key default gen_random_uuid(),
  institution_id        uuid          not null references institution on delete cascade,
  effective_from_year_be smallint     not null,
  grace_days            smallint      not null default 7,
  flat_amount           numeric(10,2) not null default 0,
  daily_amount          numeric(10,2) not null default 0,
  max_amount            numeric(10,2),
  hold_after_days       smallint      not null default 30,   -- ค้างกี่วันจึงระงับการลงทะเบียน
  unique (institution_id, effective_from_year_be)
);

create or replace function refresh_finance_holds(p_institution_id uuid)
returns table (placed integer, released integer)
language plpgsql as $$
declare
  v_policy late_fee_policy%rowtype;
  v_placed   integer := 0;
  v_released integer := 0;
  r          record;
begin
  select * into v_policy from late_fee_policy
  where institution_id = p_institution_id
  order by effective_from_year_be desc limit 1;

  if v_policy.id is null then
    raise exception 'ยังไม่ได้ตั้งนโยบายค่าปรับและการระงับสิทธิ์ของสถานศึกษานี้';
  end if;

  -- ตั้งสถานะเกินกำหนดให้งวดที่พ้นกำหนดแล้ว
  update installment i
  set status = 'overdue'
  from invoice inv
  where inv.id = i.invoice_id
    and inv.institution_id = p_institution_id
    and inv.status in ('issued', 'partially_paid')
    and i.status in ('pending', 'partially_paid')
    and i.due_on < current_date - v_policy.grace_days;

  -- ระงับสิทธิ์คนที่ค้างเกินกำหนดและยังไม่ถูกระงับ
  for r in
    select inv.student_id,
           sum(i.amount + i.penalty - i.paid_amount) as owed,
           min(i.due_on)                             as oldest_due,
           min(inv.invoice_no)                       as ref
    from installment i
    join invoice inv on inv.id = i.invoice_id
    where inv.institution_id = p_institution_id
      and inv.status in ('issued', 'partially_paid')
      and i.status <> 'paid'
      and i.due_on < current_date - v_policy.hold_after_days
      and i.amount + i.penalty - i.paid_amount > 0
    group by inv.student_id
  loop
    if not exists (
      select 1 from registration_hold h
      where h.student_id = r.student_id and h.kind = 'finance' and h.released_at is null
    ) then
      insert into registration_hold
        (student_id, kind, reason, amount, source_module, source_ref, blocks_registration)
      values (r.student_id, 'finance',
              format('ค้างชำระเกิน %s วัน ครบกำหนดตั้งแต่ %s',
                     v_policy.hold_after_days, to_char(r.oldest_due, 'DD/MM/YYYY')),
              r.owed, 'finance', r.ref, true);
      v_placed := v_placed + 1;
    end if;
  end loop;

  -- ปลดคนที่ชำระครบแล้ว
  with cleared as (
    select h.id
    from registration_hold h
    join student s on s.id = h.student_id
    where s.institution_id = p_institution_id
      and h.kind = 'finance'
      and h.released_at is null
      and not exists (
        select 1
        from installment i
        join invoice inv on inv.id = i.invoice_id
        where inv.student_id = h.student_id
          and inv.status in ('issued', 'partially_paid')
          and i.status <> 'paid'
          and i.amount + i.penalty - i.paid_amount > 0
      )
  )
  update registration_hold h
  set released_at = now(), release_reason = 'ชำระครบแล้ว ระบบปลดอัตโนมัติ'
  from cleared c where c.id = h.id;

  get diagnostics v_released = row_count;
  return query select v_placed, v_released;
end $$;

comment on function refresh_finance_holds is
  'ให้ตั้งเป็นงานประจำวัน งานทะเบียนไม่ต้องรู้จักใบแจ้งหนี้ เห็นแค่ registration_hold';

-- ───────────────────────────────────────────────────────────────────
-- มุมมองที่หน้าจอใช้
-- ───────────────────────────────────────────────────────────────────
create view v_student_balance as
select
  inv.student_id,
  inv.institution_id,
  sum(inv.total)                                  as billed,
  sum(inv.paid_total)                             as paid,
  sum(inv.total - inv.paid_total)                 as outstanding,
  min(i.due_on) filter (where i.status <> 'paid') as next_due_on,
  max(current_date - i.due_on) filter (where i.status <> 'paid' and i.due_on < current_date)
                                                  as days_overdue
from invoice inv
left join installment i on i.invoice_id = inv.id
where inv.status in ('issued', 'partially_paid')
group by inv.student_id, inv.institution_id;

create view v_ar_aging as
select
  inv.institution_id,
  case
    when i.due_on >= current_date            then 'ยังไม่ครบกำหนด'
    when current_date - i.due_on <= 30       then 'เกิน 1–30 วัน'
    when current_date - i.due_on <= 60       then 'เกิน 31–60 วัน'
    else                                          'เกิน 60 วันขึ้นไป'
  end                                              as bucket,
  count(distinct inv.student_id)                   as students,
  sum(i.amount + i.penalty - i.paid_amount)        as amount
from installment i
join invoice inv on inv.id = i.invoice_id
where inv.status in ('issued', 'partially_paid')
  and i.status <> 'paid'
  and i.amount + i.penalty - i.paid_amount > 0
group by inv.institution_id, 2;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'ledger_account', 'ledger_transaction', 'fee_item', 'fee_schedule',
    'funding_source', 'invoice', 'payment', 'bank_transaction',
    'reconciliation_hint', 'late_fee_policy'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

alter table student_funding enable row level security;
alter table student_funding force  row level security;
create policy tenant_isolation on student_funding
  using (exists (select 1 from student s
                 where s.id = student_funding.student_id
                   and s.institution_id = current_institution_id()));

alter table student_loan enable row level security;
alter table student_loan force  row level security;
create policy tenant_isolation on student_loan
  using (exists (select 1 from student s
                 where s.id = student_loan.student_id
                   and s.institution_id = current_institution_id()));

-- นักศึกษาและผู้ปกครองที่ยืนยันตัวตนแล้วเห็นใบแจ้งหนี้ของตน
create policy subject_scope on invoice
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from student s
               where s.id = invoice.student_id and s.person_id = current_actor_id())
    or exists (select 1 from student_guardian sg
               where sg.student_id = invoice.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_finance)
  );

-- บัญชีแยกประเภทแก้ย้อนหลังไม่ได้
create policy ledger_no_rewrite on ledger_transaction
  as restrictive
  using (true)
  with check (posted_at >= now() - interval '1 day');

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0011_early_warning.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0011_early_warning.sql
-- ระบบเตือนก่อนออกกลางคัน · ความประพฤติ · การดูแลช่วยเหลือ
--
-- นี่คือโมดูลเรือธง เหตุผลที่วิทยาลัยเอกชนจะยอมจ่ายเงินค่าระบบ
-- อาชีวะมีอัตราออกกลางคันสูงที่สุดในระบบการศึกษาไทย และจุดที่หลุดมากที่สุด
-- คือ ปวช.1 ภาคเรียนที่ 1 ถึง 2 นักศึกษาที่หลุดหนึ่งคนคือรายได้ที่หายไป
-- ตลอดสองถึงสามปีที่เหลือ ไม่ใช่แค่ภาคเรียนเดียว
--
-- หลักสามข้อ
-- 1. คะแนนความเสี่ยงต้องอธิบายได้ ไม่ใช่กล่องดำ — ใช้กฎถ่วงน้ำหนักที่ผู้ดูแล
--    ปรับเองได้ และเก็บ "สัญญาณ" แต่ละตัวไว้เป็นข้อความจริง เพราะครูต้อง
--    อ่านออกเสียงให้ผู้ปกครองฟังได้ว่าทำไมถึงโทรมา
-- 2. ไม่ใช่แค่แจ้งเตือน แต่สั่งงาน — ระบบเปิดเคสและกำหนดวันครบกำหนดให้
--    ครูที่ปรึกษาเอง แล้วติดตามว่าทำหรือยัง และผลเป็นอย่างไร
-- 3. ต้องแปลงเป็นตัวเงินได้ — ผู้บริหารเอกชนตัดสินใจจากบรรทัดที่เป็นบาท
--    ไม่ใช่จากจำนวนคน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ความประพฤติ
-- บันทึกทั้งด้านลบและด้านบวก ระบบส่วนใหญ่บันทึกแต่ความผิด ทำให้แฟ้ม
-- นักศึกษามีแต่เรื่องเสีย และครูที่ปรึกษาไม่มีอะไรใช้คุยเชิงบวกกับผู้ปกครอง
-- ───────────────────────────────────────────────────────────────────
create type behavior_direction as enum ('deduct', 'award');

create table behavior_rule (
  id             uuid               primary key default gen_random_uuid(),
  institution_id uuid               not null references institution on delete cascade,
  code           text               not null,
  name_th        text               not null,
  direction      behavior_direction not null,
  points         smallint           not null check (points > 0),
  -- ขั้นตอนที่ระเบียบกำหนดเมื่อคะแนนสะสมถึงเกณฑ์
  triggers_action text,
  active         boolean            not null default true,
  unique (institution_id, code)
);

create table behavior_record (
  id           uuid     primary key default gen_random_uuid(),
  student_id   uuid     not null references student      on delete cascade,
  rule_id      uuid     not null references behavior_rule on delete restrict,
  occurred_on  date     not null default current_date,
  points       smallint not null,        -- คัดลอกมา ณ เวลาบันทึก กันกฎเปลี่ยนย้อนหลัง
  detail       text,
  recorded_by  uuid,
  recorded_at  timestamptz not null default now(),
  document_no  text
);
create index on behavior_record (student_id, occurred_on desc);

create table behavior_policy (
  institution_id uuid     primary key references institution on delete cascade,
  starting_points smallint not null default 100,
  warn_below      smallint not null default 80,
  critical_below  smallint not null default 60
);

create view v_behavior_balance as
select
  s.id as student_id,
  s.institution_id,
  coalesce(bp.starting_points, 100)
    - coalesce(sum(br.points) filter (where r.direction = 'deduct'), 0)
    + coalesce(sum(br.points) filter (where r.direction = 'award'),  0) as balance
from student s
left join behavior_policy bp on bp.institution_id = s.institution_id
left join behavior_record br on br.student_id = s.id
left join behavior_rule   r  on r.id = br.rule_id
group by s.id, s.institution_id, bp.starting_points;

-- ───────────────────────────────────────────────────────────────────
-- การคัดกรองและเยี่ยมบ้าน
-- ───────────────────────────────────────────────────────────────────
create type screening_band as enum ('normal', 'at_risk', 'has_problem', 'special_needs');

create table screening_result (
  id           uuid           primary key default gen_random_uuid(),
  student_id   uuid           not null references student on delete cascade,
  instrument   text           not null default 'SDQ',
  assessed_on  date           not null,
  band         screening_band not null,
  score        numeric(6,2),
  detail       jsonb          not null default '{}'::jsonb,
  assessed_by  uuid,
  unique (student_id, instrument, assessed_on)
);
create index on screening_result (student_id, assessed_on desc);

create table home_visit (
  id           uuid        primary key default gen_random_uuid(),
  student_id   uuid        not null references student on delete cascade,
  visited_on   date        not null,
  visited_by   uuid,
  latitude     numeric(9,6),
  longitude    numeric(9,6),
  findings     text        not null,
  photo_key    text,
  follow_up    text,
  created_at   timestamptz not null default now()
);
create index on home_visit (student_id, visited_on desc);

-- ───────────────────────────────────────────────────────────────────
-- ปัจจัยเสี่ยง — เก็บเป็นข้อมูล ผู้ดูแลปรับน้ำหนักเองได้
-- ───────────────────────────────────────────────────────────────────
create table risk_factor (
  id             uuid     primary key default gen_random_uuid(),
  institution_id uuid     not null references institution on delete cascade,
  code           text     not null,      -- 'ABSENT_STREAK' ฯลฯ
  name_th        text     not null,
  weight         smallint not null check (weight between 0 and 100),
  params         jsonb    not null default '{}'::jsonb,
  active         boolean  not null default true,
  sort_order     smallint not null default 0,
  unique (institution_id, code)
);

create table risk_policy (
  institution_id      uuid     primary key references institution on delete cascade,
  yellow_at           smallint not null default 25,
  orange_at           smallint not null default 50,
  red_at              smallint not null default 75,
  respond_within_days smallint not null default 3,
  check (yellow_at < orange_at and orange_at < red_at)
);

create type risk_band as enum ('green', 'yellow', 'orange', 'red');

-- สัญญาณที่ตรวจพบ เก็บข้อความจริงไว้ให้ครูอ่านออกเสียงได้
create table student_risk_signal (
  id           uuid        primary key default gen_random_uuid(),
  student_id   uuid        not null references student on delete cascade,
  term_id      uuid        not null references term    on delete cascade,
  factor_code  text        not null,
  points       smallint    not null,
  message_th   text        not null,
  measured     jsonb       not null default '{}'::jsonb,
  computed_at  timestamptz not null default now(),
  unique (student_id, term_id, factor_code)
);
create index on student_risk_signal (term_id, factor_code);

create table student_risk_score (
  student_id  uuid        not null references student on delete cascade,
  term_id     uuid        not null references term    on delete cascade,
  score       smallint    not null,
  band        risk_band   not null,
  computed_at timestamptz not null default now(),
  primary key (student_id, term_id)
);
create index on student_risk_score (term_id, band) where band in ('orange', 'red');

-- ───────────────────────────────────────────────────────────────────
-- เคสติดตาม — ระบบสั่งงาน ไม่ใช่แค่แจ้งเตือน
-- ───────────────────────────────────────────────────────────────────
create type case_status as enum ('open', 'in_progress', 'resolved', 'escalated', 'closed_dropout');

create table intervention_case (
  id             uuid        primary key default gen_random_uuid(),
  student_id     uuid        not null references student on delete cascade,
  term_id        uuid        not null references term    on delete cascade,
  opened_on      date        not null default current_date,
  band_at_open   risk_band   not null,
  score_at_open  smallint    not null,
  owner_staff_id uuid        references staff,
  respond_by     date        not null,
  status         case_status not null default 'open',
  closed_on      date,
  outcome        text,
  created_at     timestamptz not null default now()
);
create unique index intervention_case_active
  on intervention_case (student_id, term_id)
  where status in ('open', 'in_progress', 'escalated');
create index on intervention_case (owner_staff_id, status);

create type action_kind as enum (
  'call_guardian',      -- โทรหาผู้ปกครอง
  'meet_student',       -- คุยรายบุคคล
  'summon_guardian',    -- เชิญผู้ปกครองมาพบ
  'home_visit',         -- เยี่ยมบ้าน
  'refer_counselling',  -- ส่งต่องานแนะแนว
  'refer_finance',      -- ส่งต่องานการเงินเรื่องผ่อนชำระ
  'academic_support',   -- สอนเสริมหรือแก้เกรด
  'other'
);

create table intervention_action (
  id          uuid        primary key default gen_random_uuid(),
  case_id     uuid        not null references intervention_case on delete cascade,
  kind        action_kind not null,
  due_on      date,
  note        text,
  suggested_by_system boolean not null default false,
  done_at     timestamptz,
  done_by     uuid,
  result      text,
  document_no text,
  created_at  timestamptz not null default now()
);
create index on intervention_action (case_id);
create index on intervention_action (due_on) where done_at is null;

-- ───────────────────────────────────────────────────────────────────
-- คำนวณคะแนนความเสี่ยง
-- ตั้งเป็นงานประจำคืน ผลลัพธ์คือสัญญาณรายตัวบวกคะแนนรวมและระดับสี
-- ───────────────────────────────────────────────────────────────────
create or replace function compute_risk_scores(p_institution_id uuid, p_term_id uuid)
returns integer language plpgsql as $$
declare
  v_policy risk_policy%rowtype;
  v_count  integer;
  w        smallint;
  p        jsonb;
begin
  select * into v_policy from risk_policy where institution_id = p_institution_id;
  if v_policy.institution_id is null then
    raise exception 'ยังไม่ได้ตั้งเกณฑ์ระดับความเสี่ยงของสถานศึกษานี้';
  end if;

  delete from student_risk_signal s
  using student st
  where s.student_id = st.id and st.institution_id = p_institution_id and s.term_id = p_term_id;

  -- ── ขาดเรียนติดต่อกัน ────────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'ABSENT_STREAK' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select st.id, p_term_id, 'ABSENT_STREAK', w,
           format('ขาดเรียนติดต่อกัน %s วันเรียน', streak.n),
           jsonb_build_object('school_days', streak.n)
    from student st
    cross join lateral (
      -- นับเป็น "วันเรียนติดกัน" ไม่ใช่วันปฏิทินติดกัน
      -- เพราะรายวิชาที่สอนสัปดาห์ละครั้ง วันที่ขาดจะห่างกัน 7 วันเสมอ
      -- ถ้านับตามปฏิทินจะไม่มีทางเจอการขาดติดต่อกันเลย
      select coalesce(max(cnt), 0) as n
      from (
        select count(*) as cnt
        from (
          select d.all_absent,
                 row_number() over (order by d.meets_on)
                   - row_number() over (partition by d.all_absent order by d.meets_on) as grp
          from (
            -- วันเรียนของนักศึกษาคนนี้ พร้อมสถานะว่าขาดทุกคาบของวันนั้นหรือไม่
            select cm.meets_on, bool_and(ar.status = 'absent') as all_absent
            from enrollment e
            join class_meeting cm on cm.class_section_id = e.class_section_id
                                 and cm.status = 'held'
            left join attendance_record ar on ar.class_meeting_id = cm.id
                                          and ar.enrollment_id    = e.id
            where e.student_id = st.id and e.term_id = p_term_id and e.status = 'enrolled'
            group by cm.meets_on
          ) d
        ) g
        where g.all_absent
        group by g.grp
      ) runs
    ) streak
    where st.institution_id = p_institution_id
      and st.status = 'active'
      and streak.n >= coalesce((p ->> 'days')::int, 3);
  end if;

  -- ── เวลาเรียนใกล้ตกเกณฑ์ ─────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'ATTENDANCE_LOW' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select st.id, p_term_id, 'ATTENDANCE_LOW', w,
           format('เวลาเรียนต่ำกว่าเกณฑ์ใน %s รายวิชา ต่ำสุด %s เปอร์เซ็นต์',
                  a.n, trim(to_char(a.worst, 'FM990.0'))),
           jsonb_build_object('courses', a.n, 'worst_pct', a.worst)
    from student st
    cross join lateral (
      select count(*) as n, min(v.pct_projected) as worst
      from enrollment e
      join v_enrollment_attendance v on v.enrollment_id = e.id
      where e.student_id = st.id and e.term_id = p_term_id
        and v.attendance_state in ('warning', 'discretion', 'failed')
    ) a
    where st.institution_id = p_institution_id
      and st.status = 'active'
      and a.n > 0;
  end if;

  -- ── มาสายบ่อย ────────────────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'LATE_FREQUENT' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select st.id, p_term_id, 'LATE_FREQUENT', w,
           format('มาสาย %s ครั้งในรอบ 30 วัน', l.n),
           jsonb_build_object('count', l.n)
    from student st
    cross join lateral (
      select count(*) as n
      from attendance_record ar
      join class_meeting cm on cm.id = ar.class_meeting_id
      join enrollment e     on e.id = ar.enrollment_id
      where e.student_id = st.id and e.term_id = p_term_id
        and ar.status = 'late'
        and cm.meets_on >= current_date - 30
    ) l
    where st.institution_id = p_institution_id
      and st.status = 'active'
      and l.n >= coalesce((p ->> 'count')::int, 5);
  end if;

  -- ── ค้างชำระ ─────────────────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'OVERDUE_PAYMENT' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select b.student_id, p_term_id, 'OVERDUE_PAYMENT', w,
           format('ค้างชำระ %s บาท เกินกำหนด %s วัน',
                  to_char(b.outstanding, 'FM999,999,990'), b.days_overdue),
           jsonb_build_object('outstanding', b.outstanding, 'days_overdue', b.days_overdue)
    from v_student_balance b
    join student st on st.id = b.student_id and st.status = 'active'
    where b.institution_id = p_institution_id
      and b.days_overdue >= coalesce((p ->> 'days')::int, 30);
  end if;

  -- ── ผลการเรียนต่ำ ────────────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'LOW_GPA' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select ts.student_id, p_term_id, 'LOW_GPA', w,
           format('ผลการเรียนเฉลี่ยสะสม %s ต่ำกว่าเกณฑ์จบ 2.00', to_char(ts.gpax, 'FM0.00')),
           jsonb_build_object('gpax', ts.gpax)
    from term_summary ts
    join student st on st.id = ts.student_id and st.status = 'active'
    where st.institution_id = p_institution_id
      and ts.gpax is not null
      and ts.gpax < coalesce((p ->> 'gpax')::numeric, 2.00)
      and ts.term_id = (select t2.term_id from term_summary t2
                        where t2.student_id = ts.student_id
                        order by t2.computed_at desc limit 1);
  end if;

  -- ── ผลการเรียนค้างแก้ ───────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'PENDING_GRADE' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select st.id, p_term_id, 'PENDING_GRADE', w,
           format('มีผลการเรียนค้างแก้ %s รายวิชา', g.n),
           jsonb_build_object('count', g.n)
    from student st
    cross join lateral (
      select count(*) as n from v_student_course_credit v
      where v.student_id = st.id and v.is_provisional
    ) g
    where st.institution_id = p_institution_id
      and st.status = 'active'
      and g.n >= coalesce((p ->> 'count')::int, 1);
  end if;

  -- ── คะแนนความประพฤติเหลือน้อย ───────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'BEHAVIOR_LOW' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select bb.student_id, p_term_id, 'BEHAVIOR_LOW', w,
           format('คะแนนความประพฤติเหลือ %s', bb.balance),
           jsonb_build_object('balance', bb.balance)
    from v_behavior_balance bb
    join student st on st.id = bb.student_id and st.status = 'active'
    where bb.institution_id = p_institution_id
      and bb.balance < coalesce((p ->> 'below')::int, 80);
  end if;

  -- ── ยังไม่ลงทะเบียน ─────────────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'NOT_REGISTERED' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select st.id, p_term_id, 'NOT_REGISTERED', w,
           'ยังไม่ลงทะเบียนเรียนในภาคเรียนนี้',
           '{}'::jsonb
    from student st
    where st.institution_id = p_institution_id
      and st.status = 'active'
      and not exists (select 1 from enrollment e
                      where e.student_id = st.id and e.term_id = p_term_id
                        and e.status = 'enrolled');
  end if;

  -- ── ผลคัดกรองอยู่กลุ่มเสี่ยง ────────────────────────────────────
  select weight, params into w, p from risk_factor
  where institution_id = p_institution_id and code = 'SCREENING_RISK' and active;
  if w is not null then
    insert into student_risk_signal (student_id, term_id, factor_code, points, message_th, measured)
    select distinct on (sr.student_id)
           sr.student_id, p_term_id, 'SCREENING_RISK', w,
           format('ผลคัดกรอง %s อยู่ในกลุ่ม%s', sr.instrument,
                  case sr.band when 'at_risk'      then 'เสี่ยง'
                               when 'has_problem'  then 'มีปัญหา'
                               else 'ต้องการความช่วยเหลือพิเศษ' end),
           jsonb_build_object('band', sr.band, 'assessed_on', sr.assessed_on)
    from screening_result sr
    join student st on st.id = sr.student_id and st.status = 'active'
    where st.institution_id = p_institution_id
      and sr.band <> 'normal'
    order by sr.student_id, sr.assessed_on desc;
  end if;

  -- ── รวมคะแนนและจัดระดับสี ───────────────────────────────────────
  insert into student_risk_score (student_id, term_id, score, band, computed_at)
  select
    s.student_id, p_term_id, least(sum(s.points), 100)::smallint,
    case
      when least(sum(s.points), 100) >= v_policy.red_at    then 'red'::risk_band
      when least(sum(s.points), 100) >= v_policy.orange_at then 'orange'::risk_band
      when least(sum(s.points), 100) >= v_policy.yellow_at then 'yellow'::risk_band
      else 'green'::risk_band
    end,
    now()
  from student_risk_signal s
  where s.term_id = p_term_id
  group by s.student_id
  on conflict (student_id, term_id) do update
    set score = excluded.score, band = excluded.band, computed_at = excluded.computed_at;

  -- นักศึกษาที่ไม่มีสัญญาณเลย = เขียว
  insert into student_risk_score (student_id, term_id, score, band, computed_at)
  select st.id, p_term_id, 0, 'green', now()
  from student st
  where st.institution_id = p_institution_id and st.status = 'active'
    and not exists (select 1 from student_risk_signal s
                    where s.student_id = st.id and s.term_id = p_term_id)
  on conflict (student_id, term_id) do update
    set score = 0, band = 'green', computed_at = now();

  select count(*) into v_count
  from student_risk_score r
  join student st on st.id = r.student_id
  where st.institution_id = p_institution_id and r.term_id = p_term_id;

  return v_count;
end $$;

comment on function compute_risk_scores is
  'ตั้งเป็นงานประจำคืน คะแนนมาจากกฎถ่วงน้ำหนักที่ปรับได้ ไม่ใช่โมเดลกล่องดำ เพราะครูต้องอธิบายให้ผู้ปกครองฟังได้';

-- ───────────────────────────────────────────────────────────────────
-- เปิดเคสอัตโนมัติสำหรับระดับส้มและแดง พร้อมเสนอขั้นตอนตามระเบียบ
-- ───────────────────────────────────────────────────────────────────
create or replace function open_intervention_cases(p_institution_id uuid, p_term_id uuid)
returns integer language plpgsql as $$
declare
  v_policy risk_policy%rowtype;
  v_opened integer := 0;
  r        record;
  v_case   uuid;
begin
  select * into v_policy from risk_policy where institution_id = p_institution_id;

  for r in
    select rs.student_id, rs.band, rs.score
    from student_risk_score rs
    join student st on st.id = rs.student_id
    where st.institution_id = p_institution_id
      and rs.term_id = p_term_id
      and rs.band in ('orange', 'red')
      and not exists (
        select 1 from intervention_case c
        where c.student_id = rs.student_id and c.term_id = p_term_id
          and c.status in ('open', 'in_progress', 'escalated')
      )
  loop
    insert into intervention_case
      (student_id, term_id, band_at_open, score_at_open, respond_by, owner_staff_id)
    values (
      r.student_id, p_term_id, r.band, r.score,
      current_date + v_policy.respond_within_days,
      -- มอบหมายให้ครูที่ปรึกษาโดยอนุมานจากครูผู้สอนที่นักศึกษาเรียนด้วยมากที่สุด
      (select cs.teacher_id
       from enrollment e join class_section cs on cs.id = e.class_section_id
       where e.student_id = r.student_id and e.term_id = p_term_id and cs.teacher_id is not null
       group by cs.teacher_id order by count(*) desc limit 1)
    )
    returning id into v_case;

    -- เสนอขั้นตอนตามสัญญาณที่พบจริง ไม่ใช่ชุดสำเร็จรูปเดียวกันทุกคน
    insert into intervention_action (case_id, kind, due_on, note, suggested_by_system)
    select v_case, k.kind, current_date + v_policy.respond_within_days, k.note, true
    from (
      select 'call_guardian'::action_kind as kind,
             'ติดต่อผู้ปกครองเพื่อสอบถามสาเหตุ' as note
      union all
      select 'refer_finance', 'ส่งต่องานการเงินเรื่องผ่อนชำระ'
      where exists (select 1 from student_risk_signal s
                    where s.student_id = r.student_id and s.term_id = p_term_id
                      and s.factor_code = 'OVERDUE_PAYMENT')
      union all
      select 'home_visit', 'เยี่ยมบ้านตามระเบียบ เนื่องจากขาดเรียนติดต่อกัน'
      where exists (select 1 from student_risk_signal s
                    where s.student_id = r.student_id and s.term_id = p_term_id
                      and s.factor_code = 'ABSENT_STREAK')
      union all
      select 'academic_support', 'จัดสอนเสริมหรือวางแผนแก้ผลการเรียนค้าง'
      where exists (select 1 from student_risk_signal s
                    where s.student_id = r.student_id and s.term_id = p_term_id
                      and s.factor_code in ('LOW_GPA', 'PENDING_GRADE', 'ATTENDANCE_LOW'))
      union all
      select 'refer_counselling', 'ส่งต่องานแนะแนวเพื่อประเมินซ้ำ'
      where exists (select 1 from student_risk_signal s
                    where s.student_id = r.student_id and s.term_id = p_term_id
                      and s.factor_code = 'SCREENING_RISK')
    ) k;

    v_opened := v_opened + 1;
  end loop;

  return v_opened;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- มุมมองสำหรับหน้าจอครูที่ปรึกษาและผู้บริหาร
-- ───────────────────────────────────────────────────────────────────
create view v_students_at_risk as
select
  rs.student_id,
  st.institution_id,
  st.student_code,
  p.first_name_th || ' ' || p.last_name_th as full_name,
  rs.term_id,
  rs.score,
  rs.band,
  -- ข้อความสัญญาณเรียงต่อกัน ครูอ่านออกเสียงให้ผู้ปกครองฟังได้ทันที
  string_agg(sig.message_th, ' · ' order by sig.points desc) as signals_th,
  count(sig.*)                                               as signal_count,
  c.id                                                       as case_id,
  c.status                                                   as case_status,
  c.respond_by
from student_risk_score rs
join student st on st.id = rs.student_id
join person  p  on p.id  = st.person_id
left join student_risk_signal sig
       on sig.student_id = rs.student_id and sig.term_id = rs.term_id
left join intervention_case c
       on c.student_id = rs.student_id and c.term_id = rs.term_id
      and c.status in ('open', 'in_progress', 'escalated')
where rs.band <> 'green'
group by rs.student_id, st.institution_id, st.student_code, p.first_name_th, p.last_name_th,
         rs.term_id, rs.score, rs.band, c.id, c.status, c.respond_by;

-- มูลค่ารายได้ที่เสี่ยงจะสูญ — ตัวเลขที่ทำให้ผู้บริหารเอกชนลงมือ
-- คิดจากค่าเทอมของภาคปัจจุบัน คูณจำนวนภาคเรียนที่เหลือจนจบตามหลักสูตร
create view v_revenue_at_risk as
select
  st.institution_id,
  rs.term_id,
  rs.band,
  count(*)                                                       as students,
  sum(coalesce(inv.total, 0))                                    as current_term_value,
  sum(coalesce(inv.total, 0) * greatest(remaining.terms, 0))      as revenue_at_risk
from student_risk_score rs
join student st on st.id = rs.student_id and st.status = 'active'
left join invoice inv on inv.student_id = rs.student_id and inv.term_id = rs.term_id
                     and inv.status <> 'void'
cross join lateral (
  select greatest(
           cv.normal_duration_terms
             - (select count(*) from term_summary ts where ts.student_id = rs.student_id),
           0)::int as terms
  from student_curriculum sc
  join curriculum_version cv on cv.id = sc.curriculum_version_id
  where sc.student_id = rs.student_id and sc.effective_to is null
  limit 1
) remaining
where rs.band in ('orange', 'red')
group by st.institution_id, rs.term_id, rs.band;

comment on view v_revenue_at_risk is
  'ค่าเทอมภาคปัจจุบัน คูณจำนวนภาคเรียนที่เหลือจนจบ เพราะนักศึกษาที่หลุดหนึ่งคนคือรายได้ที่หายไปตลอดหลักสูตร ไม่ใช่แค่ภาคเดียว';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['behavior_rule', 'risk_factor'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;

  foreach t in array array[
    'behavior_record', 'screening_result', 'home_visit',
    'student_risk_signal', 'student_risk_score', 'intervention_case'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from student s
                     where s.id = %I.student_id
                       and s.institution_id = current_institution_id()))
    $f$, t, t);
  end loop;
end $$;

-- ผลคัดกรองและบันทึกเยี่ยมบ้านเป็นข้อมูลชั้นความลับสูง
-- ครูผู้สอนทั่วไปไม่ควรเห็น เห็นเฉพาะงานแนะแนว ปกครอง และครูที่ปรึกษาที่เป็นเจ้าของเคส
create policy sensitive_scope on screening_result
  as restrictive
  using (
    current_app_role() in ('student_affairs', 'director', 'admin')
    or exists (select 1 from intervention_case c
               join staff sf on sf.id = c.owner_staff_id
               where c.student_id = screening_result.student_id
                 and sf.person_id = current_actor_id())
  );

create policy sensitive_scope on home_visit
  as restrictive
  using (
    current_app_role() in ('student_affairs', 'director', 'admin')
    or exists (select 1 from intervention_case c
               join staff sf on sf.id = c.owner_staff_id
               where c.student_id = home_visit.student_id
                 and sf.person_id = current_actor_id())
  );

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0012_view_security_and_subject_scope.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0012_view_security_and_subject_scope.sql
--
-- แก้ช่องโหว่ความปลอดภัยสองจุดที่พบตอนทดสอบ API
--
-- ─── จุดที่ 1: view ข้าม Row-Level Security ทั้งหมด ───
-- ใน PostgreSQL view จะรันด้วยสิทธิ์ของ "เจ้าของ view" ไม่ใช่ผู้เรียก
-- เมื่อเจ้าของเป็นผู้ใช้ที่สร้างฐานข้อมูล (ซึ่งมักเป็น superuser) RLS ของ
-- ตารางที่อยู่ข้างใต้จะถูกข้ามทั้งหมด
--
-- ผลคือ ตารางกันข้ามวิทยาลัยได้ถูกต้อง แต่ทุก view รั่ว
-- ยืนยันแล้วด้วยการทดลอง: ตั้งบริบทเป็นวิทยาลัยที่ 2 ซึ่งมีใบแจ้งหนี้ 0 ใบ
--   select count(*) from invoice            → 0   ถูกต้อง
--   select count(*) from v_student_balance  → 1   รั่ว
--
-- แก้ด้วย security_invoker = true ซึ่งทำให้ view ใช้สิทธิ์ของผู้เรียกแทน
-- และ RLS ของตารางข้างใต้กลับมาทำงาน
--
-- security_invoker ต้องใช้ PostgreSQL 15 ขึ้นไป ความต้องการขั้นต่ำของระบบ
-- จึงเปลี่ยนจาก 14 เป็น 15 ตั้งแต่ migration นี้เป็นต้นไป
--
-- ─── จุดที่ 2: นักศึกษาดูข้อมูลของตัวเองไม่ได้ ───
-- นโยบาย teacher_scope บน class_section และ attendance_record เป็นแบบ
-- restrictive ที่อนุญาตเฉพาะบทบาทระดับสถานศึกษากับครูผู้สอน
-- นักศึกษาจึงมองไม่เห็นกลุ่มเรียนของตัวเอง ทำให้หน้าจอเวลาเรียนในแอปว่างเปล่า
-- ═══════════════════════════════════════════════════════════════════
begin;

do $$
declare
  v_major int;
begin
  select current_setting('server_version_num')::int / 10000 into v_major;
  if v_major < 15 then
    raise exception
      'migration นี้ต้องใช้ PostgreSQL 15 ขึ้นไป เพราะใช้ security_invoker บน view (พบเวอร์ชัน %)',
      v_major;
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ให้ทุก view ใช้สิทธิ์ของผู้เรียก ไม่ใช่ของเจ้าของ
-- ───────────────────────────────────────────────────────────────────
do $$
declare v record;
begin
  for v in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'v' and n.nspname = 'public'
  loop
    execute format('alter view public.%I set (security_invoker = true)', v.relname);
  end loop;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ฟังก์ชันช่วยหาว่าผู้ใช้ปัจจุบันเกี่ยวข้องกับนักศึกษาคนไหนบ้าง
--
-- ต้องเป็น security definer เพื่อตัดวงจรของนโยบาย RLS
-- ถ้าเขียนเงื่อนไข "นักศึกษาเห็นกลุ่มเรียนของตัวเอง" ตรง ๆ นโยบายของ
-- class_section จะไปอ่าน enrollment ซึ่งนโยบายของมันก็อ่าน class_section กลับมา
-- PostgreSQL จะฟ้อง infinite recursion detected in policy
--
-- ฟังก์ชันเหล่านี้เปิดเผยเฉพาะความสัมพันธ์ของผู้เรียกเองเท่านั้น
-- ไม่ได้เปิดข้อมูลของคนอื่น จึงปลอดภัยที่จะให้รันด้วยสิทธิ์ของเจ้าของ
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if not (select rolsuper or rolbypassrls from pg_roles where rolname = current_user) then
    raise exception
      'migration นี้ต้องรันด้วยผู้ใช้ที่ข้าม RLS ได้ (superuser หรือ BYPASSRLS) '
      'เพราะสร้างฟังก์ชัน security definer ที่ต้องอ่านข้ามนโยบาย — ผู้ใช้ปัจจุบันคือ %',
      current_user;
  end if;
end $$;

create or replace function actor_student_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  -- ตัวเองถ้าเป็นนักศึกษา
  select s.id from student s where s.person_id = current_actor_id()
  union
  -- บุตรหลานถ้าเป็นผู้ปกครองที่ยืนยันตัวตนแล้ว
  select sg.student_id from student_guardian sg
   where sg.person_id = current_actor_id()
     and sg.verified_at is not null
$$;

create or replace function actor_enrollment_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select e.id from enrollment e where e.student_id in (select actor_student_ids())
$$;

create or replace function actor_section_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select distinct e.class_section_id from enrollment e
   where e.student_id in (select actor_student_ids())
$$;

-- ───────────────────────────────────────────────────────────────────
-- ขอบเขตของกลุ่มเรียน — เพิ่มนักศึกษาและผู้ปกครองที่ยืนยันตัวตนแล้ว
-- ───────────────────────────────────────────────────────────────────
drop policy if exists teacher_scope on class_section;
drop policy if exists section_scope on class_section;

create policy section_scope on class_section
  as restrictive
  using (
    is_institution_wide_role()
    -- ครูผู้สอนประจำกลุ่ม
    or exists (select 1 from staff st
               where st.id = class_section.teacher_id
                 and st.person_id = current_actor_id())
    -- ครูสอนแทนในคาบใดคาบหนึ่งของกลุ่มนี้
    or exists (select 1 from class_meeting cm
               join staff st2 on st2.id = cm.taught_by
               where cm.class_section_id = class_section.id
                 and st2.person_id = current_actor_id())
    -- นักศึกษาที่ลงทะเบียน และผู้ปกครองที่ยืนยันตัวตนแล้ว
    or class_section.id in (select actor_section_ids())
  );

-- ───────────────────────────────────────────────────────────────────
-- ขอบเขตของการเช็คชื่อ — เดิมนักศึกษาดูของตัวเองไม่ได้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists teacher_scope on attendance_record;
drop policy if exists attendance_scope on attendance_record;

create policy attendance_scope on attendance_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
    or attendance_record.enrollment_id in (select actor_enrollment_ids())
  );

-- ───────────────────────────────────────────────────────────────────
-- ขอบเขตของการลงทะเบียน — เดิมนักศึกษาเห็นการลงทะเบียนของทุกคนในวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
drop policy if exists enrollment_scope on enrollment;

create policy enrollment_scope on enrollment
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_section cs
               join staff st on st.id = cs.teacher_id
               where cs.id = enrollment.class_section_id
                 and st.person_id = current_actor_id())
    or enrollment.student_id in (select actor_student_ids())
  );

-- ───────────────────────────────────────────────────────────────────
-- คะแนนเก็บ — นักศึกษาเห็นเฉพาะชิ้นงานที่ครูเปิดเผยแล้วเท่านั้น
-- ตรงกับการตั้งค่า gradebook_item.publish_to_student ที่ออกแบบไว้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists teacher_scope on gradebook_score;
drop policy if exists gradebook_scope on gradebook_score;

create policy gradebook_scope on gradebook_score
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from gradebook_item gi
               join class_section cs on cs.id = gi.class_section_id
               join staff st on st.id = cs.teacher_id
               where gi.id = gradebook_score.gradebook_item_id
                 and st.person_id = current_actor_id())
    or (gradebook_score.enrollment_id in (select actor_enrollment_ids())
        and exists (select 1 from gradebook_item gi
                    where gi.id = gradebook_score.gradebook_item_id
                      and gi.publish_to_student))
  );

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0013_fix_student_balance_fanout.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0013_fix_student_balance_fanout.sql
--
-- แก้บั๊กยอดค้างชำระถูกคูณด้วยจำนวนงวดผ่อนชำระ
--
-- ─── อาการ ───
-- นักศึกษามีใบแจ้งหนี้ใบเดียว 12,600 บาท แบ่งสามงวด
-- v_student_balance รายงานว่าค้าง 37,800 บาท คือ 12,600 คูณสาม
--
-- ─── สาเหตุ ───
-- มุมมองเดิม join invoice กับ installment แล้ว sum(invoice.total)
-- การ join แบบหนึ่งต่อหลายทำให้แถวของใบแจ้งหนี้ถูกทำซ้ำตามจำนวนงวด
-- ผลรวมจึงถูกนับเกิน เป็นความผิดพลาดคลาสสิกของการรวมข้อมูลข้ามระดับ
--
-- ─── ผลกระทบที่เกิดขึ้นจริงก่อนแก้ ───
-- ยอดค้างในแอปนักศึกษาสูงเกินจริง · ข้อความเตือนความเสี่ยงบอกตัวเลขผิด
-- และถ้าเจ้าหน้าที่ใช้ยอดนี้เรียกเก็บเงิน จะเรียกเกินสามเท่า
--
-- ─── วิธีแก้ ───
-- รวมยอดที่ระดับใบแจ้งหนี้กับที่ระดับงวด แยกกันคนละชั้น แล้วค่อยเชื่อมกัน
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace view v_student_balance as
with by_invoice as (
  -- รวมที่ระดับใบแจ้งหนี้ ไม่แตะตารางงวด จึงไม่มีการทำซ้ำแถว
  select
    inv.student_id,
    inv.institution_id,
    sum(inv.total)                    as billed,
    sum(inv.paid_total)               as paid,
    sum(inv.total - inv.paid_total)   as outstanding
  from invoice inv
  where inv.status in ('issued', 'partially_paid')
  group by inv.student_id, inv.institution_id
),
by_installment as (
  -- รวมที่ระดับงวดแยกต่างหาก เพื่อหาวันครบกำหนดถัดไปและจำนวนวันที่เลยกำหนด
  select
    inv.student_id,
    min(n.due_on) filter (where n.status <> 'paid')                     as next_due_on,
    max((current_date - n.due_on)) filter (
      where n.status <> 'paid' and n.due_on < current_date
    )                                                                    as days_overdue
  from installment n
  join invoice inv on inv.id = n.invoice_id
  where inv.status in ('issued', 'partially_paid')
  group by inv.student_id
)
select
  b.student_id,
  b.institution_id,
  b.billed,
  b.paid,
  b.outstanding,
  d.next_due_on,
  d.days_overdue
from by_invoice b
left join by_installment d on d.student_id = b.student_id;

-- create or replace view ไม่รับประกันว่าตัวเลือกเดิมจะติดมาด้วย จึงตั้งซ้ำให้ชัดเจน
alter view v_student_balance set (security_invoker = true);

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0014_authentication.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0014_authentication.sql
-- การยืนยันตัวตนจริง — แทนช่องทางสำหรับพัฒนาที่ไม่ตรวจรหัสผ่าน
--
-- ─── หลักที่ยึด ───
-- 1. ไม่เก็บรหัสผ่าน เก็บเฉพาะค่าที่ผ่านฟังก์ชันหน่วงแล้ว และเก็บพารามิเตอร์
--    ไว้ในสตริงเดียวกัน เพื่อให้เปลี่ยนความแรงในอนาคตได้โดยไม่ต้องรีเซ็ตทุกคน
-- 2. ไม่เก็บ refresh token เก็บเฉพาะค่าแฮช ถ้าฐานข้อมูลรั่วผู้โจมตีก็ยัง
--    สวมสิทธิ์ไม่ได้
-- 3. ผูกอุปกรณ์กับบัญชีนักศึกษา เครื่องแรกอนุมัติเอง เครื่องถัดไปต้องให้
--    เจ้าหน้าที่อนุมัติ — กันการยืมบัญชีกันเช็คอินแทน
-- 4. เผื่อทางไว้ให้ผู้ให้บริการภายนอก (ThaID สำหรับผู้ปกครอง Google
--    Workspace สำหรับนักศึกษาและครู) โดยไม่ต้องรื้อโครงสร้างทีหลัง
--
-- ─── บทบาทพิเศษ 'auth' ───
-- ตอนล็อกอินยังไม่รู้ว่าผู้ใช้เป็นใคร จึงยังตั้ง app.actor_id ไม่ได้
-- ระบบจึงมีบทบาท 'auth' ที่อ่านได้เฉพาะข้อมูลที่จำเป็นต่อการตรวจรหัสผ่าน
-- ภายในสถานศึกษาที่ระบุเท่านั้น ไม่ใช่การให้สิทธิ์ admin ชั่วคราว
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- รหัสผ่านภายในระบบ
-- ───────────────────────────────────────────────────────────────────
create table user_credential (
  id                 uuid        primary key default gen_random_uuid(),
  institution_id     uuid        not null references institution on delete cascade,
  person_id          uuid        not null references person      on delete cascade,

  -- ชื่อผู้ใช้คือรหัสนักศึกษาหรือรหัสบุคลากร ไม่ใช่อีเมล
  -- เพราะนักศึกษาอาชีวะจำนวนมากไม่มีอีเมลของตัวเองตอนเข้าเรียน
  username           text        not null,

  -- รูปแบบ: scrypt$N$r$p$saltBase64$hashBase64
  -- เก็บพารามิเตอร์ไว้ในสตริงเดียวกัน เพื่อให้เพิ่มความแรงในอนาคตได้
  -- โดยผู้ใช้เดิมยังล็อกอินได้และค่อยอัปเกรดตอนเข้าสู่ระบบครั้งถัดไป
  password_hash      text        not null,

  must_change        boolean     not null default true,
  failed_attempts    smallint    not null default 0,
  locked_until       timestamptz,
  last_login_at      timestamptz,
  password_changed_at timestamptz not null default now(),
  disabled_at        timestamptz,
  created_at         timestamptz not null default now(),

  unique (institution_id, username)
);
create index on user_credential (person_id);

comment on column user_credential.must_change is
  'รหัสผ่านชุดแรกออกโดยงานทะเบียน ต้องบังคับเปลี่ยนตอนเข้าใช้ครั้งแรก';

-- ───────────────────────────────────────────────────────────────────
-- ตัวตนจากผู้ให้บริการภายนอก
-- เตรียมไว้ให้ ThaID และ Google Workspace เชื่อมเข้ามาโดยไม่ต้องรื้อของเดิม
-- ───────────────────────────────────────────────────────────────────
create type identity_provider as enum ('local', 'thaid', 'google', 'line');

create table auth_identity (
  id             uuid              primary key default gen_random_uuid(),
  institution_id uuid              not null references institution on delete cascade,
  person_id      uuid              not null references person      on delete cascade,
  provider       identity_provider not null,
  subject        text              not null,     -- รหัสผู้ใช้ฝั่งผู้ให้บริการ
  email          text,
  linked_at      timestamptz       not null default now(),
  last_used_at   timestamptz,
  unique (provider, subject)
);
create index on auth_identity (person_id);

-- ───────────────────────────────────────────────────────────────────
-- อุปกรณ์ที่ผูกกับบัญชี
--
-- นักศึกษาหนึ่งคนใช้ได้หนึ่งเครื่อง เครื่องแรกอนุมัติอัตโนมัติ
-- เครื่องถัดไปต้องให้เจ้าหน้าที่อนุมัติ พร้อมบันทึกว่าใครอนุมัติเมื่อไร
-- เพราะการยืมบัญชีกันเช็คอินแทนเป็นปัญหาที่เกิดจริงและตรวจย้อนหลังยาก
-- ───────────────────────────────────────────────────────────────────
create table device_binding (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  person_id      uuid        not null references person      on delete cascade,
  device_id      text        not null,          -- ตัวระบุที่แอปสร้างและเก็บใน secure storage
  device_label   text,                          -- 'Samsung A15' ให้เจ้าหน้าที่อ่านเข้าใจ
  platform       text,
  approved_at    timestamptz,
  approved_by    uuid references staff,
  revoked_at     timestamptz,
  revoke_reason  text,
  first_seen_at  timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  unique (institution_id, device_id)
);
create index on device_binding (person_id) where revoked_at is null;

-- ───────────────────────────────────────────────────────────────────
-- Refresh token
-- เก็บเฉพาะแฮช ถ้าฐานข้อมูลรั่วผู้โจมตีก็สวมสิทธิ์ไม่ได้
-- ───────────────────────────────────────────────────────────────────
create table auth_session (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  person_id      uuid        not null references person      on delete cascade,
  token_hash     bytea       not null,
  device_id      text,
  app_role       text        not null,
  issued_at      timestamptz not null default now(),
  expires_at     timestamptz not null,
  last_used_at   timestamptz,
  revoked_at     timestamptz,
  revoke_reason  text,
  user_agent     text,
  unique (token_hash)
);
create index on auth_session (person_id) where revoked_at is null;
create index on auth_session (expires_at) where revoked_at is null;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกความพยายามเข้าสู่ระบบ
--
-- เก็บที่อยู่ไอพีเป็นค่าแฮช ไม่ใช่ค่าจริง เพราะไอพีเป็นข้อมูลส่วนบุคคล
-- ตาม PDPA แต่ยังต้องใช้จำกัดจำนวนครั้งและตรวจสอบย้อนหลังได้
-- ───────────────────────────────────────────────────────────────────
create table login_attempt (
  id             bigserial   primary key,
  institution_id uuid        references institution on delete cascade,
  username       text,
  person_id      uuid        references person on delete set null,
  succeeded      boolean     not null,
  reason         text,
  ip_hash        bytea,
  user_agent     text,
  attempted_at   timestamptz not null default now()
);
create index on login_attempt (institution_id, username, attempted_at desc);
create index on login_attempt (attempted_at);

comment on table login_attempt is
  'เก็บไว้ไม่น้อยกว่า 90 วันตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26 แล้วลบอัตโนมัติ';

-- ลบบันทึกที่เกินระยะเก็บ — ตั้งเป็นงานประจำวัน
create or replace function purge_login_attempts(p_keep_days integer default 90)
returns integer language plpgsql as $$
declare v_n integer;
begin
  delete from login_attempt where attempted_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- นโยบายการเข้าสู่ระบบ
-- ───────────────────────────────────────────────────────────────────
create table auth_policy (
  institution_id        uuid     primary key references institution on delete cascade,
  max_failed_attempts   smallint not null default 5,
  lockout_minutes       smallint not null default 15,
  access_token_minutes  smallint not null default 30,
  refresh_token_days    smallint not null default 30,
  min_password_length   smallint not null default 8,
  bind_student_device   boolean  not null default true,
  max_devices_student   smallint not null default 1
);

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ตารางกลุ่มนี้อ่อนไหวที่สุดในระบบ ผู้ใช้ทั่วไปต้องเห็นได้เฉพาะของตัวเอง
-- ส่วนบทบาท 'auth' ใช้ได้เฉพาะตอนล็อกอินและอ่านได้เท่าที่จำเป็น
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'user_credential', 'auth_identity', 'device_binding',
    'auth_session', 'login_attempt', 'auth_policy'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- ตัวเองเห็นของตัวเอง · เจ้าหน้าที่ที่ดูแลบัญชีเห็นได้ทั้งหมด
-- บทบาท auth ใช้ได้เฉพาะช่วงตรวจรหัสผ่าน
create policy credential_scope on user_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

create policy identity_scope on auth_identity
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

create policy session_scope on auth_session
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  );

-- การอนุมัติอุปกรณ์เป็นงานของทะเบียนและปกครอง
create policy device_scope on device_binding
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin')
    or person_id = current_actor_id()
  );

-- บันทึกความพยายามเข้าสู่ระบบ เขียนได้ อ่านได้เฉพาะผู้ดูแล ห้ามแก้และลบ
create policy attempt_scope on login_attempt
  as restrictive
  using (current_app_role() in ('auth', 'admin', 'director'));

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0015_assessment_rls.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0015_assessment_rls.sql
--
-- ปิดช่องโหว่ — ตารางฝั่งวัดผลหกตารางไม่มี Row-Level Security เลย
--
-- ─── อาการ ───
-- select relname, relrowsecurity from pg_class
--  where relname in ('gradebook_item', 'grade_submission', ...)
-- คืนค่า false ทั้งหมด แปลว่าใครก็ตามที่เชื่อมต่อด้วย vecsms_app
-- อ่านและเขียนตารางเหล่านี้ของ **ทุกวิทยาลัย** ได้
--
-- ─── ทำไมยังไม่มีใครเจอ ───
-- เพราะยังไม่มี endpoint ไหนแตะตารางกลุ่มนี้เลย ช่องโหว่จึงยังไม่ถูกใช้
-- แต่วินาทีที่โมดูลสมุดคะแนนขึ้น มันจะกลายเป็นการรั่วข้ามวิทยาลัยทันที
-- migration นี้จึงต้องมาก่อน endpoint ไม่ใช่ตามหลัง
--
-- ─── ตารางที่ได้รับผลกระทบและความรุนแรง ───
-- gradebook_item          คะแนนเก็บของทุกกลุ่มเรียนทุกวิทยาลัย
-- grade_submission        สถานะการอนุมัติเกรด แก้ให้ข้ามขั้นได้
-- grade_submission_event  ประวัติการอนุมัติ ปลอมได้
-- grade_change_request    คำร้องแก้เกรด — อันตรายที่สุด เพราะ dual control
--                         ที่ตั้งใจไว้จะถูกข้ามได้ถ้าเขียนตารางนี้ตรง ๆ
-- term_summary            GPA และ GPAX รายคน
-- grade_symbol/cutoff     ช่วงคะแนนตัดเกรดของวิทยาลัยอื่น
--
-- ─── โครงสร้างเดิมที่ยังใช้ต่อ ───
-- ชั้นที่ 1 permissive  — อยู่วิทยาลัยเดียวกันไหม
-- ชั้นที่ 2 restrictive — แล้วยังต้องผ่านขอบเขตของบทบาทอีกชั้น
-- PostgreSQL รวม permissive ด้วย OR และ restrictive ด้วย AND
-- ถ้าเขียนขอบเขตบทบาทเป็น permissive มันจะไป OR กับการแยกวิทยาลัย
-- แล้วเปิดข้อมูลข้ามวิทยาลัยทันที
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ═══ ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา (permissive) ═══════════

-- สมุดคะแนนและรอบส่งเกรด สืบทอดวิทยาลัยผ่านกลุ่มเรียน
do $$
declare t text;
begin
  foreach t in array array['gradebook_item', 'grade_submission'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from class_section cs
                     where cs.id = %I.class_section_id
                       and cs.institution_id = current_institution_id()))
      with check (exists (select 1 from class_section cs
                          where cs.id = %I.class_section_id
                            and cs.institution_id = current_institution_id()))
    $f$, t, t, t);
  end loop;
end $$;

-- ประวัติขั้นอนุมัติ สืบทอดผ่านรอบส่งเกรดอีกทอด
alter table grade_submission_event enable row level security;
alter table grade_submission_event force  row level security;
create policy tenant_isolation on grade_submission_event
  using (exists (select 1 from grade_submission gs
                 join class_section cs on cs.id = gs.class_section_id
                 where gs.id = grade_submission_event.submission_id
                   and cs.institution_id = current_institution_id()))
  with check (exists (select 1 from grade_submission gs
                      join class_section cs on cs.id = gs.class_section_id
                      where gs.id = grade_submission_event.submission_id
                        and cs.institution_id = current_institution_id()));

-- คำร้องแก้เกรด สืบทอดผ่านการลงทะเบียน
alter table grade_change_request enable row level security;
alter table grade_change_request force  row level security;
create policy tenant_isolation on grade_change_request
  using (exists (select 1 from enrollment e
                 join class_section cs on cs.id = e.class_section_id
                 where e.id = grade_change_request.enrollment_id
                   and cs.institution_id = current_institution_id()))
  with check (exists (select 1 from enrollment e
                      join class_section cs on cs.id = e.class_section_id
                      where e.id = grade_change_request.enrollment_id
                        and cs.institution_id = current_institution_id()));

-- สรุปผลรายภาคเรียน สืบทอดผ่านนักศึกษา
alter table term_summary enable row level security;
alter table term_summary force  row level security;
create policy tenant_isolation on term_summary
  using (exists (select 1 from student s
                 where s.id = term_summary.student_id
                   and s.institution_id = current_institution_id()))
  with check (exists (select 1 from student s
                      where s.id = term_summary.student_id
                        and s.institution_id = current_institution_id()));

-- สัญลักษณ์ผลการเรียนและช่วงคะแนน สืบทอดผ่านระเบียบวัดผล
do $$
declare t text;
begin
  foreach t in array array['grade_symbol', 'grade_cutoff'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from grade_scheme g
                     where g.id = %I.grade_scheme_id
                       and g.institution_id = current_institution_id()))
      with check (exists (select 1 from grade_scheme g
                          where g.id = %I.grade_scheme_id
                            and g.institution_id = current_institution_id()))
    $f$, t, t, t);
  end loop;
end $$;

-- ═══ ชั้นที่ 2 — ขอบเขตของบทบาท (restrictive) ═══════════════════

-- ชิ้นงานในสมุดคะแนน
-- นักศึกษาเห็นเฉพาะชิ้นงานที่ครูเปิดเผยแล้ว ให้ตรงกับนโยบายที่มีอยู่แล้ว
-- บน gradebook_score — ถ้าปล่อยให้เห็นชิ้นงานทั้งหมด นักศึกษาจะรู้ว่ามี
-- ชิ้นงานที่ยังไม่เปิดเผยกี่ชิ้นและคะแนนเต็มเท่าไร ซึ่งเป็นการรั่วทางอ้อม
create policy gradebook_item_scope on gradebook_item
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from class_section cs
               join staff st on st.id = cs.teacher_id
               where cs.id = gradebook_item.class_section_id
                 and st.person_id = current_actor_id())
    or (gradebook_item.publish_to_student
        and gradebook_item.class_section_id in (select actor_section_ids()))
  );

-- รอบส่งเกรดและประวัติขั้นอนุมัติ เป็นงานของครูกับฝ่ายบริหาร
-- นักศึกษาไม่ต้องเห็นว่าเกรดของตัวเองค้างอยู่ขั้นไหน
create policy submission_scope on grade_submission
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from class_section cs
               join staff st on st.id = cs.teacher_id
               where cs.id = grade_submission.class_section_id
                 and st.person_id = current_actor_id())
  );

create policy submission_event_scope on grade_submission_event
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from grade_submission gs
               join class_section cs on cs.id = gs.class_section_id
               join staff st on st.id = cs.teacher_id
               where gs.id = grade_submission_event.submission_id
                 and st.person_id = current_actor_id())
  );

-- คำร้องแก้เกรด — เจ้าตัวควรตามสถานะคำร้องของตัวเองได้
create policy change_request_scope on grade_change_request
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from enrollment e
               join class_section cs on cs.id = e.class_section_id
               join staff st on st.id = cs.teacher_id
               where e.id = grade_change_request.enrollment_id
                 and st.person_id = current_actor_id())
    or grade_change_request.enrollment_id in (select actor_enrollment_ids())
  );

-- GPA และ GPAX — ตรงกับขอบเขตของ enrollment_result ที่ใช้อยู่แล้ว
-- ผู้ปกครองต้องยืนยันตัวตนแล้วและมีสิทธิ์ดูผลการเรียนเท่านั้น
create policy term_summary_scope on term_summary
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or term_summary.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = term_summary.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_grades)
  );

-- grade_symbol และ grade_cutoff เป็นข้อมูลอ้างอิงระดับวิทยาลัย
-- ทุกบทบาทในวิทยาลัยเดียวกันอ่านได้ จึงมีแค่ชั้นที่ 1 พอ
-- แต่แก้ไขต้องเป็นฝ่ายวัดผล — ระเบียบวัดผลเปลี่ยนแล้วกระทบทุกคนย้อนหลัง
create policy grade_symbol_write on grade_symbol
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy grade_cutoff_write on grade_cutoff
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0016_grade_computation.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0016_grade_computation.sql
--
-- ตัดเกรดจากสมุดคะแนน และขั้นตอนอนุมัติเกรด
--
-- ─── ทำไมกฎอยู่ในฐานข้อมูล ไม่ใช่ในโค้ดแอป ───
-- เหตุผลเดียวกับ check_registration() และ issue_invoice() — กฎที่อยู่ใน
-- ฐานข้อมูลบังคับใช้กับทุกทางที่เข้าถึงข้อมูล ไม่ว่าจะผ่าน API ผ่าน pgAdmin
-- หรือผ่านสคริปต์นำเข้าข้อมูลจากระบบเดิม การตัดเกรดเป็นจุดที่ผิดแล้ว
-- แก้ยากที่สุด เพราะเอกสาร รบ.1 ที่ออกไปแล้วต้องเรียกคืน
--
-- ─── ลำดับการตัดสิน ───
-- 1. เวลาเรียนไม่ถึงเกณฑ์  → ข.ร. ไม่ต้องดูคะแนนเลย
-- 2. ยังกรอกคะแนนไม่ครบ    → ม.ส. ผลชั่วคราวที่ต้องแก้ภายในกำหนด
-- 3. นอกนั้น               → เทียบคะแนนถ่วงน้ำหนักกับช่วงคะแนนตัดเกรด
--
-- ข้อ 1 มาก่อนข้อ 3 เสมอ เพราะระเบียบกำหนดว่านักศึกษาที่เวลาเรียนไม่ถึง
-- ไม่มีสิทธิ์เข้ารับการประเมินสรุปผล ต่อให้คะแนนเก็บสูงแค่ไหนก็ตาม
--
-- ─── ทำไม attendance_pct ถูกตรึงไว้ในแถวผลการเรียน ───
-- ห้ามคำนวณใหม่ตอนพิมพ์เอกสาร มิฉะนั้นเอกสารที่ออกย้อนหลังจะไม่ตรงกับ
-- ที่เคยออกไป เพราะคาบเรียนอาจถูกเพิ่มหรือแก้ทีหลัง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตัดเกรดแบบดูอย่างเดียว — ไม่เขียนอะไรลงฐานข้อมูล
--
-- ครูเปิดหน้าจอนี้ดูก่อนกดส่งได้เสมอ และดูได้กี่ครั้งก็ได้
-- ระบบเก่าที่คำนวณตอนกดส่งอย่างเดียวทำให้ครูไม่กล้ากด เพราะไม่รู้ว่าจะได้อะไร
-- ───────────────────────────────────────────────────────────────────
create or replace function compute_section_grades(p_class_section_id uuid)
returns table (
  enrollment_id    uuid,
  student_code     text,
  full_name        text,
  weighted_score   numeric,
  weight_recorded  numeric,
  weight_total     numeric,
  attendance_pct   numeric,
  attendance_state text,
  grade_symbol_id  uuid,
  symbol           text,
  grade_point      numeric,
  credits_earned   numeric,
  note_th          text
)
language plpgsql stable as $$
declare
  v_scheme_id  uuid;
  v_credits    numeric;
  v_mode       text;
  v_weight_all numeric;
  r            record;
  v_symbol     record;
  v_note       text;
begin
  select cv.grade_scheme_id, c.credits, c.grading_mode::text
    into v_scheme_id, v_credits, v_mode
    from class_section cs
    join course c on c.id = cs.course_id
    left join curriculum_version cv on cv.id = cs.curriculum_version_id
   where cs.id = p_class_section_id;

  if not found then
    raise exception 'ไม่พบกลุ่มเรียน % (หรือไม่มีสิทธิ์เข้าถึง)', p_class_section_id;
  end if;

  if v_scheme_id is null then
    raise exception 'กลุ่มเรียนนี้ยังไม่ได้ผูกกับฉบับหลักสูตร จึงไม่รู้ว่าใช้ระเบียบวัดผลชุดไหน';
  end if;

  select coalesce(sum(weight), 0) into v_weight_all
    from gradebook_item where class_section_id = p_class_section_id;

  for r in
    select e.id                                             as enr_id,
           s.student_code                                   as code,
           p.first_name_th || ' ' || p.last_name_th         as name,
           -- คะแนนถ่วงน้ำหนัก: แต่ละชิ้นเทียบสัดส่วนของคะแนนเต็มแล้วคูณน้ำหนัก
           coalesce(sum(gsc.score / gi.max_score * gi.weight), 0)                  as weighted,
           coalesce(sum(gi.weight) filter (where gsc.score is not null), 0)        as w_recorded,
           va.pct_final                                     as att_pct,
           va.attendance_state                              as att_state,
           va.min_pct                                       as att_min
      from enrollment e
      join student s on s.id = e.student_id
      join person  p on p.id = s.person_id
      left join v_enrollment_attendance va on va.enrollment_id = e.id
      left join gradebook_item  gi  on gi.class_section_id = p_class_section_id
      left join gradebook_score gsc on gsc.gradebook_item_id = gi.id
                                   and gsc.enrollment_id     = e.id
     where e.class_section_id = p_class_section_id
       and e.status = 'enrolled'
     group by e.id, s.student_code, p.first_name_th, p.last_name_th,
              va.pct_final, va.attendance_state, va.min_pct
     order by s.student_code
  loop
    v_note := null;

    -- ── 1. เวลาเรียนไม่ถึงเกณฑ์ → ข.ร. ไม่ต้องดูคะแนน ───────────
    if r.att_pct is not null and r.att_min is not null and r.att_pct < r.att_min then
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_symbol gs
       where gs.grade_scheme_id = v_scheme_id and gs.symbol = 'ข.ร.';
      v_note := format('เวลาเรียน %s%% ต่ำกว่าเกณฑ์ %s%%', r.att_pct, r.att_min);

    -- ── 2. กรอกคะแนนไม่ครบ → ม.ส. ผลชั่วคราว ────────────────────
    elsif v_weight_all = 0 or r.w_recorded < v_weight_all then
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_symbol gs
       where gs.grade_scheme_id = v_scheme_id and gs.symbol = 'ม.ส.';
      v_note := case
                  when v_weight_all = 0 then 'ยังไม่ได้กำหนดชิ้นงานในสมุดคะแนน'
                  else format('กรอกคะแนนแล้ว %s จากน้ำหนักรวม %s', r.w_recorded, v_weight_all)
                end;

    -- ── 3. รายวิชาแบบผ่าน/ไม่ผ่าน ────────────────────────────────
    elsif v_mode = 'pass_fail' then
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_symbol gs
       where gs.grade_scheme_id = v_scheme_id
         and gs.symbol = case when r.weighted >= 50 then 'ผ.' else 'ม.ผ.' end;

    -- ── 4. เทียบช่วงคะแนนตัดเกรด ─────────────────────────────────
    else
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_cutoff gc
        join grade_symbol gs on gs.id = gc.grade_symbol_id
       where gc.grade_scheme_id = v_scheme_id
         and gc.min_score <= r.weighted
       order by gc.min_score desc
       limit 1;
    end if;

    if v_symbol.id is null then
      raise exception
        'ระเบียบวัดผลของหลักสูตรนี้ไม่มีสัญลักษณ์ที่ต้องใช้ (นักศึกษา %) — ตรวจ grade_symbol และ grade_cutoff',
        r.code;
    end if;

    enrollment_id    := r.enr_id;
    student_code     := r.code;
    full_name        := r.name;
    weighted_score   := round(r.weighted, 2);
    weight_recorded  := r.w_recorded;
    weight_total     := v_weight_all;
    attendance_pct   := r.att_pct;
    attendance_state := r.att_state;
    grade_symbol_id  := v_symbol.id;
    symbol           := v_symbol.symbol;
    grade_point      := v_symbol.grade_point;
    credits_earned   := case when v_symbol.earns_credit then v_credits else 0 end;
    note_th          := v_note;
    return next;
  end loop;
end $$;

comment on function compute_section_grades(uuid) is
  'ตัดเกรดจากสมุดคะแนนแบบดูอย่างเดียว ไม่เขียนอะไรลงฐานข้อมูล ครูเปิดดูก่อนกดส่งได้เสมอ';

-- ───────────────────────────────────────────────────────────────────
-- ครูส่งเกรด — เขียน enrollment_result แล้วเลื่อนขั้นเป็น teacher_submitted
--
-- ทั้งหมดอยู่ในธุรกรรมเดียว ถ้านักศึกษาคนใดคนหนึ่งตัดเกรดไม่ได้
-- จะไม่มีใครถูกบันทึกเลย เพราะเกรดที่ลงครึ่งห้องแย่กว่าไม่ลงเลย
-- ───────────────────────────────────────────────────────────────────

-- การส่งใหม่หลังถูกตีกลับต้องแทนที่แถวเดิม ไม่ใช่แก้ทับ
-- ลำดับที่จำเป็นคือ ชี้แถวเดิมไปหาแถวใหม่ก่อน แล้วค่อยเพิ่มแถวใหม่
-- เพราะดัชนี enrollment_result_current ยอมให้มีแถวที่ superseded_by is null
-- ได้แค่แถวเดียวต่อการลงทะเบียนหนึ่งรายการ
--
-- ตอนชี้ แถวใหม่ยังไม่มีอยู่จริง คีย์นอกจึงต้องเลื่อนไปตรวจตอน commit
alter table enrollment_result
  drop constraint enrollment_result_superseded_by_fkey;
alter table enrollment_result
  add constraint enrollment_result_superseded_by_fkey
  foreign key (superseded_by) references enrollment_result(id)
  deferrable initially deferred;

create or replace function submit_section_grades(p_class_section_id uuid)
returns table (submission_id uuid, results_written integer)
language plpgsql as $$
declare
  v_sub     grade_submission%rowtype;
  v_term    uuid;
  v_n       integer := 0;
  v_new_id  uuid;
  v_current enrollment_result%rowtype;
  r         record;
begin
  select cs.term_id into v_term from class_section cs where cs.id = p_class_section_id;
  if not found then
    raise exception 'ไม่พบกลุ่มเรียน % (หรือไม่มีสิทธิ์เข้าถึง)', p_class_section_id;
  end if;

  select * into v_sub from grade_submission where class_section_id = p_class_section_id;

  if not found then
    insert into grade_submission (class_section_id, term_id, stage)
    values (p_class_section_id, v_term, 'draft')
    returning * into v_sub;
  end if;

  -- ส่งซ้ำได้เฉพาะตอนยังไม่ส่ง หรือถูกตีกลับมาแก้
  if v_sub.stage not in ('draft', 'returned') then
    raise exception
      'รอบส่งเกรดของกลุ่มนี้อยู่ขั้น % แล้ว ส่งซ้ำไม่ได้ ถ้าต้องแก้ให้ผู้อนุมัติตีกลับก่อน',
      v_sub.stage;
  end if;

  -- ยังมีคาบที่ยังไม่ได้สอน = เวลาเรียนยังไม่ใช่ตัวเลขสุดท้าย
  --
  -- ถ้าปล่อยให้ส่งตอนนี้ pct_final จะต่ำโดยธรรมชาติเพราะตัวหารคือคาบทั้งภาค
  -- ผลคือทั้งห้องได้ ข.ร. ทั้งที่ยังเรียนไม่จบ ซึ่งเป็นความผิดพลาดที่
  -- มองไม่ออกจากหน้าจอ — ครูเห็นแค่ว่า "ระบบตัดเกรดให้แล้ว"
  declare v_pending integer;
  begin
    select count(*) into v_pending
      from class_meeting
     where class_section_id = p_class_section_id and status = 'scheduled';

    if v_pending > 0 then
      raise exception
        'กลุ่มนี้ยังมีคาบที่ยังไม่ได้สอนอีก % คาบ เวลาเรียนจึงยังไม่ใช่ตัวเลขสุดท้าย ส่งเกรดไม่ได้',
        v_pending;
    end if;
  end;

  for r in select * from compute_section_grades(p_class_section_id) loop
    select * into v_current
      from enrollment_result er
     where er.enrollment_id = r.enrollment_id
       and er.superseded_by is null;

    -- ผลเดิมเหมือนเดิมทุกอย่างก็ไม่ต้องออก revision ใหม่
    -- ไม่งั้นการกดส่งซ้ำจะสร้างประวัติปลอมเต็มบัญชีตรวจสอบ
    if found
       and v_current.grade_symbol_id = r.grade_symbol_id
       and v_current.raw_score      is not distinct from r.weighted_score
       and v_current.attendance_pct is not distinct from r.attendance_pct then
      continue;
    end if;

    v_new_id := gen_random_uuid();

    if found then
      update enrollment_result
         set superseded_by = v_new_id
       where id = v_current.id;
    end if;

    insert into enrollment_result (
      id, enrollment_id, submission_id, revision,
      raw_score, attendance_pct, grade_symbol_id, grade_point, credits_earned,
      computed_by, reason
    )
    values (
      v_new_id, r.enrollment_id, v_sub.id,
      coalesce(v_current.revision, 0) + 1,
      r.weighted_score, r.attendance_pct, r.grade_symbol_id,
      r.grade_point, r.credits_earned,
      current_actor_id(),
      case when v_current.id is not null then 'ส่งเกรดใหม่หลังถูกตีกลับ' end
    );

    v_n := v_n + 1;
  end loop;

  update grade_submission
     set stage = 'teacher_submitted',
         submitted_by = current_actor_id(),
         submitted_at = now()
   where id = v_sub.id;

  insert into grade_submission_event (submission_id, from_stage, to_stage, actor_id, note)
  values (v_sub.id, v_sub.stage, 'teacher_submitted', current_actor_id(),
          format('ส่งผลการเรียน %s คน', v_n));

  submission_id   := v_sub.id;
  results_written := v_n;
  return next;
end $$;

comment on function submit_section_grades(uuid) is
  'ครูส่งเกรดทั้งกลุ่มในธุรกรรมเดียว ถ้าคนใดคนหนึ่งตัดไม่ได้จะไม่มีใครถูกบันทึกเลย';

-- ───────────────────────────────────────────────────────────────────
-- เลื่อนขั้นอนุมัติ
--
-- ครูผู้สอน → หัวหน้าแผนกวิชา → ฝ่ายวิชาการ → ผู้อำนวยการ → ล็อก
--
-- บังคับลำดับไว้ในฐานข้อมูล ไม่ใช่ในโค้ดแอป เพราะการข้ามขั้นคือช่องทาง
-- ที่ใช้แก้เกรดโดยไม่ผ่านการตรวจสอบ ซึ่งเป็นเหตุผลที่ขั้นตอนนี้มีอยู่ตั้งแต่แรก
-- ───────────────────────────────────────────────────────────────────
create or replace function advance_grade_submission(
  p_submission_id uuid,
  p_to_stage      submission_stage,
  p_note          text default null
) returns submission_stage
language plpgsql as $$
declare
  v_sub      grade_submission%rowtype;
  v_expected submission_stage;
begin
  select * into v_sub from grade_submission where id = p_submission_id;
  if not found then
    raise exception 'ไม่พบรอบส่งเกรด % (หรือไม่มีสิทธิ์เข้าถึง)', p_submission_id;
  end if;

  if v_sub.stage = 'locked' then
    raise exception 'รอบส่งเกรดนี้ล็อกแล้ว การแก้ต้องยื่นคำร้องแก้เกรดที่ต้องมีผู้อนุมัติสองคน';
  end if;

  -- ตีกลับให้ครูแก้ ทำได้จากทุกขั้นก่อนล็อก
  if p_to_stage = 'returned' then
    if v_sub.stage = 'draft' then
      raise exception 'รอบส่งเกรดนี้ยังไม่ถูกส่ง จึงตีกลับไม่ได้';
    end if;
  else
    v_expected := case v_sub.stage
                    when 'teacher_submitted' then 'head_approved'
                    when 'head_approved'     then 'academic_approved'
                    when 'academic_approved' then 'director_approved'
                    when 'director_approved' then 'locked'
                    when 'returned'          then 'teacher_submitted'
                  end::submission_stage;

    if v_expected is null then
      raise exception 'ขั้น % เลื่อนต่อไม่ได้ ต้องให้ครูส่งเกรดก่อน', v_sub.stage;
    end if;

    if p_to_stage <> v_expected then
      raise exception 'ข้ามขั้นไม่ได้ — จากขั้น % ไปได้เฉพาะ % (ขอไป %)',
        v_sub.stage, v_expected, p_to_stage;
    end if;
  end if;

  update grade_submission
     set stage = p_to_stage,
         locked_at = case when p_to_stage = 'locked' then now() else locked_at end
   where id = p_submission_id;

  insert into grade_submission_event (submission_id, from_stage, to_stage, actor_id, note)
  values (p_submission_id, v_sub.stage, p_to_stage, current_actor_id(), p_note);

  return p_to_stage;
end $$;

comment on function advance_grade_submission(uuid, submission_stage, text) is
  'เลื่อนขั้นอนุมัติเกรดทีละขั้น ห้ามข้ามขั้น เพราะการข้ามขั้นคือช่องทางแก้เกรดโดยไม่ผ่านการตรวจสอบ';

-- ───────────────────────────────────────────────────────────────────
-- คำนวณ GPA และ GPAX ลง term_summary
--
-- ─── ทำไม GPAX ต้องคิดสะสมจากทุกภาคเรียน ไม่ใช่เฉลี่ยของ GPA ───
-- ค่าเฉลี่ยของค่าเฉลี่ยไม่เท่ากับค่าเฉลี่ยรวม ถ้าภาคหนึ่งลง 21 หน่วยกิต
-- อีกภาคลง 9 หน่วยกิต การเฉลี่ย GPA สองตัวจะให้น้ำหนักภาคเล็กเกินจริง
-- GPAX ที่ผิดกระทบการจบและการสมัครเรียนต่อโดยตรง
-- ───────────────────────────────────────────────────────────────────
create or replace function compute_term_summary(p_term_id uuid)
returns integer
language plpgsql as $$
declare v_n integer := 0;
begin
  insert into term_summary (student_id, term_id, credits_attempted, credits_earned, gpa, gpax, computed_at)
  select t.student_id,
         p_term_id,
         t.credits_attempted,
         t.credits_earned,
         t.gpa,
         x.gpax,
         now()
    from (
      -- ภาคเรียนนี้
      select e.student_id,
             sum(co.credits)                                              as credits_attempted,
             sum(er.credits_earned)                                       as credits_earned,
             case when sum(co.credits) filter (where sy.counts_in_gpa) > 0
                  then round(sum(er.grade_point * co.credits) filter (where sy.counts_in_gpa)
                             / sum(co.credits) filter (where sy.counts_in_gpa), 2)
             end                                                          as gpa
        from enrollment_result er
        join enrollment    e  on e.id  = er.enrollment_id
        join class_section cs on cs.id = e.class_section_id
        join course        co on co.id = cs.course_id
        join grade_symbol  sy on sy.id = er.grade_symbol_id
       where er.superseded_by is null
         and e.term_id = p_term_id
         and e.counts_toward_gpa
       group by e.student_id
    ) t
    join lateral (
      -- สะสมทุกภาคเรียนจนถึงภาคนี้ — คิดจากหน่วยกิตรวม ไม่ใช่เฉลี่ยของ GPA
      select case when sum(co.credits) filter (where sy.counts_in_gpa) > 0
                  then round(sum(er.grade_point * co.credits) filter (where sy.counts_in_gpa)
                             / sum(co.credits) filter (where sy.counts_in_gpa), 2)
             end as gpax
        from enrollment_result er
        join enrollment    e2 on e2.id = er.enrollment_id
        join class_section cs on cs.id = e2.class_section_id
        join course        co on co.id = cs.course_id
        join grade_symbol  sy on sy.id = er.grade_symbol_id
        join term          tm on tm.id = e2.term_id
       where er.superseded_by is null
         and e2.student_id = t.student_id
         and e2.counts_toward_gpa
         and tm.starts_on <= (select starts_on from term where id = p_term_id)
    ) x on true
      on conflict (student_id, term_id) do update
      set credits_attempted = excluded.credits_attempted,
          credits_earned    = excluded.credits_earned,
          gpa               = excluded.gpa,
          gpax              = excluded.gpax,
          computed_at       = excluded.computed_at;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function compute_term_summary(uuid) is
  'คำนวณ GPA รายภาคและ GPAX สะสมลง term_summary — GPAX คิดจากหน่วยกิตรวม ไม่ใช่เฉลี่ยของ GPA';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0017_close_rls_gaps.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0017_close_rls_gaps.sql
--
-- ปิด Row-Level Security ให้ตารางที่เหลืออีก 28 ตาราง
--
-- ─── ทำไมตารางกลุ่มนี้ถึงหลุด ───
-- ทั้งหมดเป็น "ตารางลูก" ที่ตอนออกแบบคิดว่าเข้าถึงผ่านตารางแม่เท่านั้น
-- ซึ่งตารางแม่มี RLS ครบอยู่แล้ว แต่ **RLS ใน PostgreSQL ไม่ถ่ายทอด
-- ผ่านคีย์นอก** — ถ้าใครเขียน
--
--   select * from installment where due_on < current_date
--
-- จะได้งวดผ่อนชำระของทุกวิทยาลัย ไม่ใช่แค่ของตัวเอง การป้องกันที่มีอยู่
-- ทำงานก็ต่อเมื่อ query นั้นบังเอิญ join ผ่านตารางแม่เท่านั้น ซึ่งเป็น
-- การพึ่งวินัยของคนเขียน query ไม่ใช่การบังคับของระบบ
--
-- ─── กับดักที่ต้องเลี่ยง: policy ที่อ้างกันเองจนวนไม่รู้จบ ───
-- นโยบาย subject_scope ของ student อ้าง student_guardian อยู่แล้ว
-- ถ้า student_guardian อ้างกลับไปที่ student เพื่อหาว่าอยู่วิทยาลัยไหน
-- PostgreSQL จะฟ้อง "infinite recursion detected in policy"
-- นโยบาย section_scope ของ class_section อ้าง class_meeting ก็เข้าคู่เดียวกัน
--
-- ทางแก้คือฟังก์ชัน security definer ที่หาสังกัดโดยไม่ผ่าน RLS
-- วิธีเดียวกับที่ migration 0012 ใช้กับ actor_student_ids()
-- ได้ผลพลอยได้คือเร็วขึ้นด้วย เพราะไม่ต้องประเมินนโยบายของตารางแม่
-- ซ้ำทุกแถวของตารางลูก
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตัวช่วยหาสังกัด — ข้าม RLS โดยเจตนา
--
-- ปลอดภัยเพราะรับ id เข้ามาแล้วคืน "รหัสวิทยาลัย" ออกไปอย่างเดียว
-- ไม่ได้คืนข้อมูลส่วนบุคคลใด ๆ ผู้เรียกต้องรู้ id อยู่แล้วจึงจะเรียกได้
-- และค่าที่ได้ถูกเอาไปเทียบกับ current_institution_id() ทันที
-- ───────────────────────────────────────────────────────────────────
create or replace function student_institution(p_student_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select institution_id from student where id = p_student_id
$$;

create or replace function class_section_institution(p_section_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select institution_id from class_section where id = p_section_id
$$;

create or replace function curriculum_version_institution(p_version_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select cu.institution_id
    from curriculum_version cv join curriculum cu on cu.id = cv.curriculum_id
   where cv.id = p_version_id
$$;

-- ครูผู้สอนประจำกลุ่ม — ใช้ในนโยบายของ class_meeting โดยไม่แตะ class_section
create or replace function section_teacher_person_id(p_section_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select st.person_id
    from class_section cs join staff st on st.id = cs.teacher_id
   where cs.id = p_section_id
$$;

revoke all on function student_institution(uuid)            from public;
revoke all on function class_section_institution(uuid)      from public;
revoke all on function curriculum_version_institution(uuid) from public;
revoke all on function section_teacher_person_id(uuid)      from public;

-- ─── ทำไมต้องเช็คว่ามีบทบาทก่อน ───
-- บทบาทใน PostgreSQL อยู่ระดับ cluster ไม่ใช่ระดับฐานข้อมูล บนเครื่อง
-- ที่เคยรัน db/deploy/roles.sql มาแล้ว app_runtime จะค้างอยู่ใน cluster
-- ทำให้ migrations ผ่านทุกครั้งจนดูเหมือนไม่มีปัญหา
--
-- แต่บน cluster ใหม่เอี่ยม (CI · เครื่องคนอื่น · เซิร์ฟเวอร์จริงตอน deploy
-- ครั้งแรก) บทบาทยังไม่มี แล้ว migration นี้จะล้มทั้งไฟล์ — ซึ่งแปลว่า
-- ไม่มีใครติดตั้งระบบนี้จากศูนย์ได้เลย ทั้งที่บนเครื่องคนเขียนผ่านตลอด
--
-- ข้ามไปได้เพราะ roles.sql มี `grant execute on all functions` อยู่แล้ว
-- ฟังก์ชันเหล่านี้จึงได้สิทธิ์ตอนรัน roles.sql ทีหลัง (แบบเดียวกับ 0022 ·
-- 0023 · 0025 · 0040 ที่เขียนไว้ถูกอยู่แล้ว)
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant execute on function student_institution(uuid)            to app_runtime;
    grant execute on function class_section_institution(uuid)      to app_runtime;
    grant execute on function curriculum_version_institution(uuid) to app_runtime;
    grant execute on function section_teacher_person_id(uuid)      to app_runtime;
  end if;
end $$;

-- ═══ ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา (permissive) ═══════════

-- 1ก. มี institution_id อยู่บนตัวเอง
do $$
declare t text;
begin
  foreach t in array array['behavior_policy', 'risk_policy'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- 1ข. สืบทอดผ่านตารางแม่ที่มี institution_id อยู่บนตัวเอง
do $$
declare r record;
begin
  for r in
    select * from (values
      ('attendance_status_weight', 'attendance_policy',  'attendance_policy_id'),
      ('program_track',            'program',            'program_id'),
      ('curriculum_version',       'curriculum',         'curriculum_id'),
      ('fee_schedule_line',        'fee_schedule',       'fee_schedule_id'),
      ('installment',              'invoice',            'invoice_id'),
      ('invoice_line',             'invoice',            'invoice_id'),
      ('payment_allocation',       'payment',            'payment_id'),
      ('ledger_entry',             'ledger_transaction', 'transaction_id')
    ) as t(child, parent, fk)
  loop
    execute format('alter table %I enable row level security', r.child);
    execute format('alter table %I force  row level security', r.child);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from %I p
                     where p.id = %I.%I and p.institution_id = current_institution_id()))
      with check (exists (select 1 from %I p
                          where p.id = %I.%I and p.institution_id = current_institution_id()))
    $f$, r.child, r.parent, r.child, r.fk, r.parent, r.child, r.fk);
  end loop;
end $$;

-- 1ค. สืบทอดผ่านนักศึกษา — ใช้ตัวช่วย definer กันวนไม่รู้จบกับ student_guardian
do $$
declare t text;
begin
  foreach t in array array[
    'cocurricular_result', 'practicum_log', 'student_curriculum',
    'student_graduation_status', 'student_guardian', 'student_status_history',
    'professional_standard_assessment'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (student_institution(%I.student_id) = current_institution_id())
      with check (student_institution(%I.student_id) = current_institution_id())
    $f$, t, t, t);
  end loop;
end $$;

-- 1ง. สืบทอดผ่านฉบับหลักสูตร
do $$
declare t text;
begin
  foreach t in array array[
    'competency', 'course_competency', 'course_prerequisite',
    'curriculum_category', 'curriculum_course', 'entry_pathway', 'graduation_rule'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (curriculum_version_institution(%I.curriculum_version_id) = current_institution_id())
      with check (curriculum_version_institution(%I.curriculum_version_id) = current_institution_id())
    $f$, t, t, t);
  end loop;
end $$;

-- 1จ. คาบเรียน — ใช้ตัวช่วย definer กันวนไม่รู้จบกับ section_scope ของ class_section
alter table class_meeting enable row level security;
alter table class_meeting force  row level security;
create policy tenant_isolation on class_meeting
  using (class_section_institution(class_meeting.class_section_id) = current_institution_id())
  with check (class_section_institution(class_meeting.class_section_id) = current_institution_id());

-- 1ฉ. โซ่ที่ลึกกว่าหนึ่งชั้น
alter table pathway_bridging_course enable row level security;
alter table pathway_bridging_course force  row level security;
create policy tenant_isolation on pathway_bridging_course
  using (exists (select 1 from entry_pathway ep
                 where ep.id = pathway_bridging_course.entry_pathway_id
                   and curriculum_version_institution(ep.curriculum_version_id) = current_institution_id()))
  with check (exists (select 1 from entry_pathway ep
                      where ep.id = pathway_bridging_course.entry_pathway_id
                        and curriculum_version_institution(ep.curriculum_version_id) = current_institution_id()));

alter table professional_standard_competency_result enable row level security;
alter table professional_standard_competency_result force  row level security;
create policy tenant_isolation on professional_standard_competency_result
  using (exists (select 1 from professional_standard_assessment a
                 where a.id = professional_standard_competency_result.assessment_id
                   and student_institution(a.student_id) = current_institution_id()))
  with check (exists (select 1 from professional_standard_assessment a
                      where a.id = professional_standard_competency_result.assessment_id
                        and student_institution(a.student_id) = current_institution_id()));

alter table intervention_action enable row level security;
alter table intervention_action force  row level security;
create policy tenant_isolation on intervention_action
  using (exists (select 1 from intervention_case ic
                 where ic.id = intervention_action.case_id
                   and student_institution(ic.student_id) = current_institution_id()))
  with check (exists (select 1 from intervention_case ic
                      where ic.id = intervention_action.case_id
                        and student_institution(ic.student_id) = current_institution_id()));

-- ═══ ชั้นที่ 2 — ขอบเขตของบทบาท (restrictive) ═══════════════════

-- ── คาบเรียน — ตรงกับ section_scope ของกลุ่มเรียน ─────────────────
-- ครูสอนแทนต้องเห็นคาบที่ตนสอน แม้ไม่ใช่ครูประจำกลุ่ม
create policy meeting_scope on class_meeting
  as restrictive
  using (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
    or class_meeting.class_section_id in (select actor_section_ids())
  );

-- ── การเงิน — ตรงกับ subject_scope ของใบแจ้งหนี้ ─────────────────
-- ผู้ปกครองต้องยืนยันตัวตนแล้วและมีสิทธิ์ดูการเงิน จึงจะเห็นงวดผ่อนชำระ
do $$
declare t text;
begin
  foreach t in array array['installment', 'invoice_line'] loop
    execute format($f$
      create policy finance_subject_scope on %I
        as restrictive
        using (
          current_app_role() in ('finance', 'registrar', 'director', 'admin')
          or exists (select 1 from invoice i
                     join student s on s.id = i.student_id
                     where i.id = %I.invoice_id
                       and s.person_id = current_actor_id())
          or exists (select 1 from invoice i
                     join student_guardian sg on sg.student_id = i.student_id
                     where i.id = %I.invoice_id
                       and sg.person_id  = current_actor_id()
                       and sg.verified_at is not null
                       and sg.can_view_finance)
        )
    $f$, t, t, t);
  end loop;
end $$;

-- การตัดยอดและบัญชีแยกประเภทเป็นงานหลังบ้านล้วน นักศึกษาไม่ต้องเห็น
create policy allocation_scope on payment_allocation
  as restrictive
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy ledger_entry_scope on ledger_entry
  as restrictive
  using (current_app_role() in ('finance', 'director', 'admin'));

-- แก้บัญชีย้อนหลังไม่ได้ ให้ตรงกับ ledger_no_rewrite ของรายการแม่
-- ถ้ากันแต่ที่ตารางแม่ การเพิ่มบรรทัดเข้ารายการเก่ายังทำได้อยู่
create policy ledger_entry_no_rewrite on ledger_entry
  as restrictive
  for all
  using (true)
  with check (exists (select 1 from ledger_transaction lt
                      where lt.id = ledger_entry.transaction_id
                        and lt.posted_at >= now() - interval '1 day'));

-- ── ข้อมูลรายบุคคลของนักศึกษา ────────────────────────────────────
-- ตรงกับ subject_scope ของ enrollment_result ที่ใช้อยู่แล้ว
do $$
declare t text;
begin
  foreach t in array array[
    'cocurricular_result', 'student_graduation_status',
    'professional_standard_assessment', 'student_curriculum'
  ] loop
    execute format($f$
      create policy subject_scope on %I
        as restrictive
        using (
          is_institution_wide_role()
          or current_app_role() = 'teacher'
          or %I.student_id in (select actor_student_ids())
          or exists (select 1 from student_guardian sg
                     where sg.student_id = %I.student_id
                       and sg.person_id  = current_actor_id()
                       and sg.verified_at is not null
                       and sg.can_view_grades)
        )
    $f$, t, t, t);
  end loop;
end $$;

-- ประวัติการเปลี่ยนสถานะเป็นเอกสารทางทะเบียน ครูผู้สอนทั่วไปไม่ต้องเห็น
create policy status_history_scope on student_status_history
  as restrictive
  using (
    is_institution_wide_role()
    or student_status_history.student_id in (select actor_student_ids())
  );

/*
 * บันทึกฝึกประสบการณ์มีพิกัดเช็คอินและรูปถ่าย จึงอ่อนไหวกว่าข้อมูลเรียนทั่วไป
 * ครูผู้สอนทั่วไปไม่ควรเห็นว่านักศึกษาอยู่พิกัดไหนตอนไหน
 * เห็นได้เฉพาะครูนิเทศที่รับรองชั่วโมง และเจ้าตัวกับผู้ปกครองที่ยืนยันแล้ว
 */
create policy practicum_scope on practicum_log
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
               where st.id = practicum_log.verified_by
                 and st.person_id = current_actor_id())
    or practicum_log.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = practicum_log.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null)
  );

/*
 * ความสัมพันธ์ผู้ปกครอง — ห้ามอ้าง student ในนโยบายนี้
 *
 * subject_scope ของ student อ้าง student_guardian อยู่แล้ว ถ้าอ้างกลับ
 * PostgreSQL จะฟ้อง infinite recursion จึงใช้ actor_student_ids()
 * ซึ่งเป็น security definer และไม่ปลุกนโยบายของ student ขึ้นมาอีกรอบ
 *
 * ผู้ปกครองต้องเห็นแถวของตัวเองได้ มิฉะนั้นนโยบายของ invoice และ student
 * ที่ตรวจ "มีผู้ปกครองที่ยืนยันแล้วไหม" จะหาไม่เจอ แล้วผู้ปกครองจะเข้าไม่ได้ทั้งระบบ
 */
create policy guardian_scope on student_guardian
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or student_guardian.person_id = current_actor_id()
    or student_guardian.student_id in (select actor_student_ids())
  );

-- ── ข้อมูลอ้างอิงระดับวิทยาลัย ───────────────────────────────────
-- อ่านได้ทุกบทบาทในวิทยาลัยเดียวกัน เพราะเป็นโครงสร้างหลักสูตรที่ทุกคนต้องใช้
-- แต่แก้ไขต้องเป็นฝ่ายวิชาการ — เปลี่ยนโครงสร้างหลักสูตรกระทบการตรวจจบย้อนหลัง
do $$
declare t text;
begin
  foreach t in array array[
    'curriculum_version', 'competency', 'course_competency', 'course_prerequisite',
    'curriculum_category', 'curriculum_course', 'entry_pathway', 'graduation_rule',
    'pathway_bridging_course', 'program_track'
  ] loop
    execute format($f$
      create policy academic_write_only on %I
        as restrictive
        for all
        using (true)
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- นโยบายค่าธรรมเนียมและเกณฑ์ความเสี่ยงเป็นค่าตั้งที่กระทบทุกคนทันทีที่แก้
create policy finance_write_only on fee_schedule_line
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

do $$
declare t text;
begin
  foreach t in array array['risk_policy', 'behavior_policy'] loop
    execute format($f$
      create policy affairs_write_only on %I
        as restrictive
        for all
        using (true)
        with check (current_app_role() in ('student_affairs', 'academic', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

create policy attendance_policy_write_only on attendance_status_weight
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0018_grade_change_request.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0018_grade_change_request.sql
--
-- คำร้องแก้เกรดหลังล็อก — ทางเดียวที่แก้ผลการเรียนที่อนุมัติแล้วได้
--
-- ─── ทำไมต้องมีทางนี้ ───
-- migration 0016 ทำให้ผลการเรียนที่เดินครบสายอนุมัติแล้วแตะไม่ได้เลย
-- ซึ่งถูกต้อง แต่ความผิดพลาดเกิดขึ้นจริงเสมอ — กรอกคะแนนสลับคน
-- นักศึกษายื่นใบรับรองแพทย์ย้อนหลัง หรือ ม.ส. ที่แก้เสร็จแล้ว
-- ถ้าไม่มีทางแก้ที่ตรวจสอบได้ คนจะไปแก้ที่ฐานข้อมูลตรง ๆ แทน
-- ซึ่งแย่กว่ามาก เพราะไม่เหลือร่องรอยว่าใครแก้และเพราะอะไร
--
-- ─── dual control: ผู้อนุมัติสองคน และห้ามเป็นคนขอ ───
-- ตาราง grade_change_request มี constraint บังคับว่าผู้อนุมัติสองคน
-- ต้องเป็นคนละคนอยู่แล้ว แต่ constraint นั้นไม่ได้ห้าม **คนขอ**
-- มาอนุมัติคำร้องของตัวเอง ซึ่งทำให้ dual control ไม่มีความหมาย
-- เพราะครูคนเดียวขอเองแล้วกดอนุมัติหนึ่งในสองช่องเองได้
-- ฟังก์ชันในไฟล์นี้จึงปิดช่องนั้นอีกชั้น
--
-- ─── ทำไมลงมือแก้อัตโนมัติเมื่อครบสองคน ───
-- ถ้าแยกขั้น "อนุมัติแล้ว" กับ "ลงมือแก้" ออกจากกัน จะเกิดสถานะค้าง
-- ที่อนุมัติครบแล้วแต่ไม่มีใครกดใช้ แล้วเกรดในระบบยังเป็นค่าเดิม
-- ทั้งที่ทุกคนเข้าใจว่าแก้ไปแล้ว — เป็นความไม่ตรงกันที่ตรวจไม่เจอจนออกเอกสาร
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ยื่นคำร้อง
-- ───────────────────────────────────────────────────────────────────
create or replace function request_grade_change(
  p_enrollment_id      uuid,
  p_to_grade_symbol_id uuid,
  p_reason             text,
  p_to_raw_score       numeric default null,
  p_document_no        text    default null
) returns uuid
language plpgsql as $$
declare
  v_current  enrollment_result%rowtype;
  v_stage    submission_stage;
  v_scheme   uuid;
  v_id       uuid;
begin
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'ต้องระบุเหตุผลของการแก้เกรด';
  end if;

  -- คำร้องที่ไม่รู้ว่าใครยื่นตรวจสอบย้อนหลังไม่ได้ และทำให้ dual control
  -- พังทันที เพราะกฎ "ผู้ยื่นอนุมัติเองไม่ได้" ต้องรู้ว่าผู้ยื่นคือใคร
  if current_actor_id() is null then
    raise exception 'การยื่นคำร้องแก้เกรดต้องระบุตัวผู้ยื่น';
  end if;

  select * into v_current
    from enrollment_result er
   where er.enrollment_id = p_enrollment_id and er.superseded_by is null;

  if not found then
    raise exception 'การลงทะเบียนนี้ยังไม่มีผลการเรียน จึงยังไม่มีอะไรให้แก้';
  end if;

  -- ยังไม่ล็อกก็ไม่ต้องใช้คำร้อง ให้ผู้อนุมัติตีกลับแล้วครูส่งใหม่ ซึ่งเบากว่ามาก
  select gs.stage into v_stage
    from grade_submission gs
    join enrollment e on e.class_section_id = gs.class_section_id
   where e.id = p_enrollment_id;

  if v_stage is distinct from 'locked' then
    raise exception
      'รอบส่งเกรดของกลุ่มนี้ยังไม่ล็อก (ขั้น %) ให้ผู้อนุมัติตีกลับแล้วครูส่งใหม่แทนการยื่นคำร้อง',
      coalesce(v_stage::text, 'ยังไม่ได้ส่ง');
  end if;

  if exists (select 1 from grade_change_request
              where enrollment_id = p_enrollment_id and status = 'pending') then
    raise exception 'มีคำร้องแก้เกรดของการลงทะเบียนนี้ค้างอยู่แล้ว ต้องดำเนินการให้เสร็จก่อน';
  end if;

  -- ไม่ส่งคะแนนมาแปลว่าไม่ขอแก้คะแนน ถ้าสัญลักษณ์ก็เท่าเดิมด้วยก็ไม่มีอะไรต้องแก้
  if p_to_grade_symbol_id = v_current.grade_symbol_id
     and (p_to_raw_score is null or p_to_raw_score = v_current.raw_score) then
    raise exception 'ผลการเรียนที่ขอแก้เหมือนเดิมทุกอย่าง ไม่มีอะไรต้องแก้';
  end if;

  -- สัญลักษณ์ที่ขอต้องอยู่ในระเบียบวัดผลของหลักสูตรเดียวกัน
  -- ไม่งั้นจะได้เกรดของ ปวส. ไปโผล่ในผลการเรียน ปวช.
  select cv.grade_scheme_id into v_scheme
    from enrollment e
    join class_section cs      on cs.id = e.class_section_id
    join curriculum_version cv on cv.id = cs.curriculum_version_id
   where e.id = p_enrollment_id;

  if not exists (select 1 from grade_symbol
                  where id = p_to_grade_symbol_id and grade_scheme_id = v_scheme) then
    raise exception 'สัญลักษณ์ผลการเรียนที่ขอไม่ได้อยู่ในระเบียบวัดผลของหลักสูตรนี้';
  end if;

  insert into grade_change_request
    (enrollment_id, from_result_id, to_grade_symbol_id, to_raw_score,
     reason, document_no, requested_by)
  values
    (p_enrollment_id, v_current.id, p_to_grade_symbol_id, p_to_raw_score,
     btrim(p_reason), p_document_no, current_actor_id())
  returning id into v_id;

  return v_id;
end $$;

comment on function request_grade_change(uuid, uuid, text, numeric, text) is
  'ยื่นคำร้องแก้เกรดที่ล็อกแล้ว — ต้องมีเหตุผลเสมอ และใช้ได้เฉพาะเมื่อรอบส่งเกรดล็อกไปแล้ว';

-- ───────────────────────────────────────────────────────────────────
-- ลงมือแก้ — เรียกจาก approve_grade_change() เมื่อครบสองคนเท่านั้น
--
-- ออก revision ใหม่แล้วชี้แถวเดิมมาหา ไม่ใช่แก้ทับ เหมือนตอนส่งเกรดใหม่
-- attendance_pct ยกมาจากแถวเดิมโดยไม่คำนวณใหม่ เพราะเป็นค่าที่ตรึงไว้
-- ณ เวลาตัดเกรด ถ้าคำนวณใหม่ เอกสารที่ออกย้อนหลังจะไม่ตรงกับที่เคยออกไป
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_grade_change(p_request_id uuid)
returns uuid
language plpgsql as $$
declare
  v_req     grade_change_request%rowtype;
  v_current enrollment_result%rowtype;
  v_symbol  record;
  v_credits numeric;
  v_new_id  uuid;
begin
  select * into v_req from grade_change_request where id = p_request_id;
  if not found then
    raise exception 'ไม่พบคำร้อง % (หรือไม่มีสิทธิ์เข้าถึง)', p_request_id;
  end if;

  select * into v_current
    from enrollment_result where enrollment_id = v_req.enrollment_id and superseded_by is null;

  select gs.grade_point, gs.earns_credit, gs.symbol
    into v_symbol
    from grade_symbol gs where gs.id = v_req.to_grade_symbol_id;

  select co.credits into v_credits
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join course        co on co.id = cs.course_id
   where e.id = v_req.enrollment_id;

  v_new_id := gen_random_uuid();

  update enrollment_result
     set superseded_by = v_new_id
   where id = v_current.id;

  insert into enrollment_result (
    id, enrollment_id, submission_id, revision,
    raw_score, attendance_pct, grade_symbol_id, grade_point, credits_earned,
    computed_by, reason
  )
  values (
    v_new_id, v_req.enrollment_id, v_current.submission_id, v_current.revision + 1,
    coalesce(v_req.to_raw_score, v_current.raw_score),
    v_current.attendance_pct,
    v_req.to_grade_symbol_id, v_symbol.grade_point,
    case when v_symbol.earns_credit then v_credits else 0 end,
    current_actor_id(),
    format('แก้เกรดตามคำร้อง %s: %s',
           coalesce(v_req.document_no, p_request_id::text), v_req.reason)
  );

  update grade_change_request
     set status = 'applied', applied_result_id = v_new_id
   where id = p_request_id;

  return v_new_id;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- อนุมัติ — คนที่สองที่กดคือคนที่ทำให้การแก้มีผลจริง
-- ───────────────────────────────────────────────────────────────────
create or replace function approve_grade_change(p_request_id uuid)
returns change_request_status
language plpgsql as $$
declare
  v_req   grade_change_request%rowtype;
  v_actor uuid := current_actor_id();
begin
  if v_actor is null then
    raise exception 'การอนุมัติต้องระบุตัวผู้อนุมัติ';
  end if;

  select * into v_req from grade_change_request where id = p_request_id;
  if not found then
    raise exception 'ไม่พบคำร้อง % (หรือไม่มีสิทธิ์เข้าถึง)', p_request_id;
  end if;

  if v_req.status <> 'pending' then
    raise exception 'คำร้องนี้อยู่สถานะ % แล้ว อนุมัติซ้ำไม่ได้', v_req.status;
  end if;

  -- หัวใจของ dual control — constraint ในตารางกันได้แค่ผู้อนุมัติซ้ำคน
  -- แต่ไม่ได้กันคนขอมาอนุมัติเอง ถ้าไม่ปิดตรงนี้ ครูคนเดียวก็ขอเอง
  -- แล้วกดอนุมัติหนึ่งในสองช่องเองได้ เหลือให้หาคนกดอีกคนเดียว
  if v_actor = v_req.requested_by then
    raise exception 'ผู้ยื่นคำร้องอนุมัติคำร้องของตัวเองไม่ได้';
  end if;

  if v_req.approver_1_id is null then
    update grade_change_request
       set approver_1_id = v_actor, approver_1_at = now()
     where id = p_request_id;
    return 'pending';
  end if;

  if v_req.approver_1_id = v_actor then
    raise exception 'คุณอนุมัติคำร้องนี้ไปแล้ว ต้องให้ผู้อนุมัติอีกคนเป็นคนละคน';
  end if;

  -- คนที่สอง — อนุมัติครบแล้วลงมือแก้ทันทีในธุรกรรมเดียว
  update grade_change_request
     set approver_2_id = v_actor, approver_2_at = now(), status = 'approved'
   where id = p_request_id;

  perform apply_grade_change(p_request_id);
  return 'applied';
end $$;

comment on function approve_grade_change(uuid) is
  'อนุมัติคำร้องแก้เกรด ต้องสองคนคนละคน และห้ามเป็นผู้ยื่นคำร้อง คนที่สองกดแล้วระบบแก้ให้ทันที';

-- ───────────────────────────────────────────────────────────────────
-- ปฏิเสธคำร้อง
-- ───────────────────────────────────────────────────────────────────
create or replace function reject_grade_change(p_request_id uuid, p_reason text)
returns change_request_status
language plpgsql as $$
declare v_req grade_change_request%rowtype; v_actor uuid := current_actor_id();
begin
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'ต้องระบุเหตุผลที่ปฏิเสธ เพื่อให้ผู้ยื่นรู้ว่าต้องแก้อะไร';
  end if;

  select * into v_req from grade_change_request where id = p_request_id;
  if not found then
    raise exception 'ไม่พบคำร้อง % (หรือไม่มีสิทธิ์เข้าถึง)', p_request_id;
  end if;

  if v_req.status <> 'pending' then
    raise exception 'คำร้องนี้อยู่สถานะ % แล้ว ปฏิเสธไม่ได้', v_req.status;
  end if;

  if v_actor = v_req.requested_by then
    raise exception 'ผู้ยื่นคำร้องปฏิเสธคำร้องของตัวเองไม่ได้ ถ้าต้องการยกเลิกให้แจ้งงานทะเบียน';
  end if;

  update grade_change_request
     set status = 'rejected',
         reason = reason || E'\n[ปฏิเสธ] ' || btrim(p_reason)
   where id = p_request_id;

  return 'rejected';
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ด่านสุดท้าย: บังคับ dual control ที่ตัวตาราง ไม่ใช่แค่ในฟังก์ชัน
--
-- ─── ทำไมไม่ใช้ security definer แล้วปิดการเขียนตรงด้วย RLS ───
-- security definer ทำให้ฟังก์ชันรันด้วยสิทธิ์เจ้าของ ซึ่งข้าม RLS ทั้งหมด
-- แปลว่าครูของวิทยาลัยหนึ่งส่ง id ของอีกวิทยาลัยเข้ามาก็ทำงานได้
-- เป็นการแลกช่องโหว่ใหญ่กับการปิดช่องโหว่เล็ก
--
-- trigger บังคับได้ทุกเส้นทางโดยไม่ต้องยกสิทธิ์ให้ใคร — ผ่านฟังก์ชัน
-- ผ่าน pgAdmin หรือผ่านสคริปต์ย้ายข้อมูล ก็ติดกฎเดียวกันหมด
-- และ RLS ยังทำงานตามปกติเพราะฟังก์ชันรันด้วยสิทธิ์ผู้เรียก
-- ───────────────────────────────────────────────────────────────────
create or replace function grade_change_request_guard() returns trigger
language plpgsql as $$
begin
  -- ตั้งผู้อนุมัติทั้งสองคนพร้อมกันในคำสั่งเดียวไม่ได้
  -- นี่คือช่องที่ทำให้ dual control ไร้ความหมายที่สุด เพราะคนเดียวกดจบได้เลย
  if old.approver_1_id is null and old.approver_2_id is null
     and new.approver_1_id is not null and new.approver_2_id is not null then
    raise exception 'ตั้งผู้อนุมัติสองคนพร้อมกันในคำสั่งเดียวไม่ได้ ต้องอนุมัติทีละคน';
  end if;

  -- ผู้ยื่นคำร้องเป็นผู้อนุมัติเองไม่ได้
  if new.approver_1_id = new.requested_by or new.approver_2_id = new.requested_by then
    raise exception 'ผู้ยื่นคำร้องเป็นผู้อนุมัติคำร้องของตัวเองไม่ได้';
  end if;

  -- ลบผู้อนุมัติที่ลงไปแล้วเพื่อกดใหม่ไม่ได้
  if (old.approver_1_id is not null and new.approver_1_id is distinct from old.approver_1_id)
     or (old.approver_2_id is not null and new.approver_2_id is distinct from old.approver_2_id) then
    raise exception 'ผู้อนุมัติที่ลงไปแล้วเปลี่ยนไม่ได้';
  end if;

  -- สาระของคำร้องต้องไม่ถูกสลับหลังมีคนอนุมัติไปแล้ว
  -- ไม่งั้นจะขออย่างหนึ่งให้คนอนุมัติ แล้วเปลี่ยนเป็นอีกอย่างก่อนคนที่สองกด
  if old.approver_1_id is not null
     and (new.enrollment_id      is distinct from old.enrollment_id
       or new.from_result_id     is distinct from old.from_result_id
       or new.to_grade_symbol_id is distinct from old.to_grade_symbol_id
       or new.to_raw_score       is distinct from old.to_raw_score
       or new.requested_by       is distinct from old.requested_by) then
    raise exception 'แก้สาระของคำร้องหลังมีผู้อนุมัติแล้วไม่ได้ ให้ยื่นคำร้องใหม่';
  end if;

  -- สถานะเดินได้ทางเดียว: pending → approved → applied หรือ pending → rejected
  if new.status is distinct from old.status then
    if not ((old.status = 'pending'  and new.status in ('approved', 'rejected'))
         or (old.status = 'approved' and new.status = 'applied')) then
      raise exception 'เปลี่ยนสถานะคำร้องจาก % ไป % ไม่ได้', old.status, new.status;
    end if;
  end if;

  -- ขึ้นเป็นอนุมัติได้ต่อเมื่อมีผู้อนุมัติครบสองคนจริง
  if new.status = 'approved'
     and (new.approver_1_id is null or new.approver_2_id is null) then
    raise exception 'คำร้องจะเป็นอนุมัติได้ต่อเมื่อมีผู้อนุมัติครบสองคน';
  end if;

  return new;
end $$;

create trigger grade_change_request_dual_control
  before update on grade_change_request
  for each row execute function grade_change_request_guard();

-- คำร้องที่ปิดไปแล้วลบทิ้งไม่ได้ ต้องเหลือไว้ให้ตรวจสอบย้อนหลัง
create or replace function grade_change_request_no_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'คำร้องแก้เกรดลบไม่ได้ ต้องเก็บไว้เป็นหลักฐานการตรวจสอบ';
end $$;

create trigger grade_change_request_block_delete
  before delete on grade_change_request
  for each row execute function grade_change_request_no_delete();

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0019_dual_vocational.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0019_dual_vocational.sql
--
-- ทวิภาคีและการฝึกประสบการณ์สมรรถนะวิชาชีพ
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- practicum_log.workplace_id มีคอลัมน์มาตั้งแต่ migration 0007 แต่
-- **ไม่มีตารางให้อ้างถึง** จึงไม่มีคีย์นอก ค่าที่ใส่เข้าไปเป็น uuid อะไรก็ได้
-- ระบบไม่มีทางรู้เลยว่านักศึกษาฝึกอยู่ที่ไหน ทั้งที่กฎจบข้อหนึ่งคือ
-- ฝึกให้ครบ 320 ชั่วโมง — ตรวจจบผ่านได้โดยไม่รู้ว่าชั่วโมงนั้นมาจากที่ใด
--
-- ─── ทำไมสถานประกอบการต้องมีสถานะอนุมัติ ───
-- ระเบียบทวิภาคีกำหนดว่าสถานประกอบการต้องผ่านการประเมินความพร้อมก่อน
-- จึงรับนักศึกษาได้ ถ้าเก็บเป็นข้อความอิสระในใบส่งตัว จะไม่มีทางรู้ว่า
-- ที่ไหนผ่านประเมินแล้วบ้าง และนักศึกษาจะถูกส่งไปที่ที่ยังไม่ผ่าน
--
-- ─── ทำไมต้องเก็บพิกัดของสถานประกอบการ ───
-- ใช้ตรวจเช็คอินของนักศึกษาที่ส่งมาจากแอป (practicum_log.checkin_lat/lng)
-- ถ้าไม่มีพิกัดอ้างอิง การเช็คอินก็เป็นแค่ตัวเลขที่ไม่มีใครตรวจได้
-- ═══════════════════════════════════════════════════════════════════
begin;

create type workplace_status as enum ('draft', 'approved', 'suspended', 'terminated');
create type placement_status as enum ('planned', 'active', 'completed', 'terminated');

-- ───────────────────────────────────────────────────────────────────
-- สถานประกอบการ
-- ───────────────────────────────────────────────────────────────────
create table workplace (
  id              uuid             primary key default gen_random_uuid(),
  institution_id  uuid             not null references institution on delete restrict,
  code            text             not null,
  name_th         text             not null,
  name_en         text,
  branch_th       text,
  tax_id          text,                          -- เลขประจำตัวผู้เสียภาษี 13 หลัก
  industry        text,
  address_th      text,
  province        text,
  postal_code     text,

  -- ใช้ตรวจว่าการเช็คอินของนักศึกษาอยู่ในรัศมีของสถานประกอบการจริง
  lat             numeric(9,6),
  lng             numeric(9,6),
  checkin_radius_m smallint        not null default 300,

  contact_name    text,
  contact_phone   text,
  contact_email   text,
  capacity        smallint         check (capacity is null or capacity > 0),

  status          workplace_status not null default 'draft',
  assessed_on     date,                          -- วันที่ประเมินความพร้อม
  approved_by     uuid             references staff,
  approved_at     timestamptz,
  note            text,
  created_at      timestamptz      not null default now(),
  updated_at      timestamptz      not null default now(),
  unique (institution_id, code),
  check (tax_id is null or tax_id ~ '^[0-9]{13}$'),
  check ((lat is null) = (lng is null))
);
create index on workplace (institution_id, status);
create trigger workplace_touch before update on workplace
  for each row execute function set_updated_at();

comment on table  workplace is 'สถานประกอบการที่รับนักศึกษาฝึกอาชีพ ต้องผ่านประเมินความพร้อมก่อนจึงรับได้';
comment on column workplace.checkin_radius_m is
  'รัศมีที่ยอมรับการเช็คอิน หน่วยเมตร โรงงานใหญ่ต้องตั้งกว้างกว่าร้านเล็ก';

-- ครูฝึกในสถานประกอบการ — เป็นคนนอกวิทยาลัย จึงไม่ได้อยู่ในตาราง person
create table workplace_supervisor (
  id            uuid        primary key default gen_random_uuid(),
  workplace_id  uuid        not null references workplace on delete cascade,
  full_name_th  text        not null,
  position_th   text,
  phone         text,
  email         text,
  is_primary    boolean     not null default false,
  active        boolean     not null default true,
  created_at    timestamptz not null default now()
);
create index on workplace_supervisor (workplace_id) where active;

comment on table workplace_supervisor is
  'ครูฝึกประจำสถานประกอบการ เป็นบุคคลภายนอกจึงเก็บข้อมูลติดต่อตรงนี้ ไม่ผูกกับตาราง person';

-- ───────────────────────────────────────────────────────────────────
-- ข้อตกลงความร่วมมือ
-- ───────────────────────────────────────────────────────────────────
create table dual_training_agreement (
  id                    uuid        primary key default gen_random_uuid(),
  institution_id        uuid        not null references institution on delete restrict,
  workplace_id          uuid        not null references workplace   on delete restrict,
  curriculum_version_id uuid        references curriculum_version,
  agreement_no          text        not null,
  signed_on             date,
  starts_on             date        not null,
  ends_on               date        not null,
  seats                 smallint    check (seats is null or seats > 0),
  scope_th              text,
  active                boolean     not null default true,
  created_at            timestamptz not null default now(),
  unique (institution_id, agreement_no),
  check (ends_on > starts_on)
);
create index on dual_training_agreement (workplace_id);

-- ───────────────────────────────────────────────────────────────────
-- การส่งนักศึกษาไปฝึก
-- ───────────────────────────────────────────────────────────────────
create table student_placement (
  id               uuid             primary key default gen_random_uuid(),
  student_id       uuid             not null references student   on delete cascade,
  workplace_id     uuid             not null references workplace on delete restrict,
  agreement_id     uuid             references dual_training_agreement,
  term_id          uuid             references term,
  enrollment_id    uuid             references enrollment,
  supervisor_id    uuid             references workplace_supervisor,
  advisor_staff_id uuid             references staff,          -- ครูนิเทศฝ่ายวิทยาลัย
  starts_on        date             not null,
  ends_on          date             not null,
  target_hours     numeric(6,1)     check (target_hours is null or target_hours > 0),
  status           placement_status not null default 'planned',
  terminated_note  text,
  created_at       timestamptz      not null default now(),
  check (ends_on > starts_on),

  -- นักศึกษาคนเดียวฝึกสองที่ในช่วงเวลาเดียวกันไม่ได้
  -- เคยเกิดจริงเมื่อครูสองคนส่งตัวคนเดียวกันไปคนละที่ แล้วชั่วโมงถูกนับซ้ำ
  exclude using gist (
    student_id with =,
    daterange(starts_on, ends_on, '[]') with &&
  ) where (status <> 'terminated')
);
create index on student_placement (workplace_id, status);
create index on student_placement (advisor_staff_id);

comment on constraint student_placement_student_id_daterange_excl on student_placement is
  'กันส่งนักศึกษาคนเดียวไปฝึกสองที่พร้อมกัน ซึ่งทำให้ชั่วโมงฝึกถูกนับซ้ำ';

-- ───────────────────────────────────────────────────────────────────
-- ผูก practicum_log เข้ากับสถานประกอบการเสียที
-- ───────────────────────────────────────────────────────────────────
alter table practicum_log
  add constraint practicum_log_workplace_id_fkey
  foreign key (workplace_id) references workplace on delete restrict;

alter table practicum_log
  add column if not exists placement_id uuid references student_placement on delete set null;

create index on practicum_log (placement_id);

comment on column practicum_log.workplace_id is
  'สถานประกอบการที่ฝึก — ก่อน migration 0019 คอลัมน์นี้ไม่มีตารางให้อ้างถึง';

-- ───────────────────────────────────────────────────────────────────
-- รับรองชั่วโมงฝึก
--
-- ชั่วโมงที่ยังไม่รับรองไม่ถูกนับในการตรวจจบ แต่แสดงในแอปเป็นยอดรอรับรอง
-- การรับรองจึงเป็นการกระทำที่ต้องรู้ว่าใครทำ ไม่ใช่แค่ตั้งค่า flag
-- ───────────────────────────────────────────────────────────────────
create or replace function verify_practicum_hours(
  p_log_ids uuid[],
  p_verify  boolean default true
) returns integer
language plpgsql as $$
declare v_n integer; v_staff uuid;
begin
  if current_actor_id() is null then
    raise exception 'การรับรองชั่วโมงฝึกต้องระบุตัวผู้รับรอง';
  end if;

  select id into v_staff from staff where person_id = current_actor_id();
  if v_staff is null then
    raise exception 'ผู้รับรองชั่วโมงฝึกต้องเป็นบุคลากรของวิทยาลัย (ครูนิเทศ)';
  end if;

  if p_verify then
    update practicum_log
       set verified_by = v_staff, verified_at = now()
     where id = any(p_log_ids) and verified_at is null;
  else
    -- ถอนการรับรอง เช่นตรวจพบภายหลังว่าเช็คอินไม่ตรงสถานที่
    update practicum_log
       set verified_by = null, verified_at = null
     where id = any(p_log_ids) and verified_at is not null;
  end if;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function verify_practicum_hours(uuid[], boolean) is
  'ครูนิเทศรับรองหรือถอนการรับรองชั่วโมงฝึกเป็นชุด — ชั่วโมงที่ยังไม่รับรองไม่นับในการตรวจจบ';

-- ───────────────────────────────────────────────────────────────────
-- สรุปชั่วโมงฝึกรายคน
--
-- แยกชั่วโมงที่รับรองแล้วออกจากที่รอรับรองอย่างชัดเจน เพราะสองตัวนี้
-- ใช้คนละที่ — ตัวแรกใช้ตรวจจบ ตัวหลังใช้แสดงในแอปให้นักศึกษาเห็นว่า
-- ที่ส่งไปแล้วยังรอครูรับรองอยู่เท่าไร ไม่ใช่หายไปเฉย ๆ
-- ───────────────────────────────────────────────────────────────────
create or replace view v_student_practicum as
select
  p.student_id,
  coalesce(sum(p.hours) filter (where p.verified_at is not null), 0)  as verified_hours,
  coalesce(sum(p.hours) filter (where p.verified_at is null), 0)      as pending_hours,
  count(*)                                                            as entries,
  count(distinct p.workplace_id)                                      as workplaces,
  max(p.worked_on)                                                    as last_worked_on,
  (select gr.threshold
     from student_curriculum sc
     join graduation_rule gr on gr.curriculum_version_id = sc.curriculum_version_id
                            and gr.kind = 'practicum_hours'
    where sc.student_id = p.student_id
    order by sc.effective_from desc nulls last
    limit 1)                                                          as required_hours
from practicum_log p
group by p.student_id;

alter view v_student_practicum set (security_invoker = true);

comment on view v_student_practicum is
  'สรุปชั่วโมงฝึกรายคน แยกที่รับรองแล้วออกจากที่รอรับรอง — ตัวแรกใช้ตรวจจบ ตัวหลังแสดงในแอป';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────

-- ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา
do $$
declare t text;
begin
  foreach t in array array['workplace', 'dual_training_agreement'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

alter table workplace_supervisor enable row level security;
alter table workplace_supervisor force  row level security;
create policy tenant_isolation on workplace_supervisor
  using (exists (select 1 from workplace w
                 where w.id = workplace_supervisor.workplace_id
                   and w.institution_id = current_institution_id()))
  with check (exists (select 1 from workplace w
                      where w.id = workplace_supervisor.workplace_id
                        and w.institution_id = current_institution_id()));

alter table student_placement enable row level security;
alter table student_placement force  row level security;
create policy tenant_isolation on student_placement
  using (student_institution(student_placement.student_id) = current_institution_id())
  with check (student_institution(student_placement.student_id) = current_institution_id());

-- ชั้นที่ 2 — ขอบเขตของบทบาท
--
-- ทะเบียนสถานประกอบการเป็นข้อมูลที่ทุกคนในวิทยาลัยดูได้ เพราะนักศึกษา
-- ต้องเลือกที่ฝึกเองได้ แต่แก้ไขและอนุมัติต้องเป็นฝ่ายที่รับผิดชอบ
do $$
declare t text;
begin
  foreach t in array array['workplace', 'workplace_supervisor', 'dual_training_agreement'] loop
    execute format($f$
      create policy dual_write_only on %I
        as restrictive
        for all
        using (true)
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

/*
 * บันทึกฝึกประสบการณ์ — แทนที่นโยบายเดิมจาก migration 0017
 *
 * นโยบายเดิมให้ครูเห็นเฉพาะรายการที่ตน "รับรองไปแล้ว" (verified_by)
 * ซึ่งเป็นไก่กับไข่ — ครูนิเทศมองไม่เห็นรายการที่ยังไม่รับรอง
 * จึงไม่มีทางรับรองมันได้เลย คิวรอรับรองว่างเปล่าตลอดโดยไม่มี error
 *
 * ที่ถูกคือให้สิทธิ์จาก **ใบส่งตัว** ซึ่งเป็นตัวบอกว่าใครนิเทศใคร
 * ไม่ใช่จากผลลัพธ์ของการกระทำที่ยังไม่ได้ทำ
 */
drop policy if exists practicum_scope on practicum_log;

create policy practicum_scope on practicum_log
  as restrictive
  using (
    is_institution_wide_role()
    -- ครูนิเทศที่รับผิดชอบใบส่งตัวของนักศึกษาคนนี้
    or exists (select 1 from student_placement sp
               join staff st on st.id = sp.advisor_staff_id
               where sp.student_id = practicum_log.student_id
                 and st.person_id = current_actor_id())
    -- ครูที่เคยรับรองรายการนี้ ยังต้องเห็นย้อนหลังได้แม้เปลี่ยนครูนิเทศแล้ว
    or exists (select 1 from staff st
               where st.id = practicum_log.verified_by
                 and st.person_id = current_actor_id())
    or practicum_log.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = practicum_log.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null)
  );

-- นักศึกษาเห็นใบส่งตัวของตัวเอง ครูนิเทศเห็นของนักศึกษาที่ตนดูแล
create policy placement_scope on student_placement
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
               where st.id = student_placement.advisor_staff_id
                 and st.person_id = current_actor_id())
    or student_placement.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = student_placement.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null)
  );

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0020_clone_curriculum_version.sql
-- ───────────────────────────────────────────────────────────────────

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


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0021_login_rate_limit.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0021_login_rate_limit.sql
--
-- จำกัดจำนวนครั้งการเข้าสู่ระบบ **รายไอพี**
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- ระบบมีการล็อกบัญชีอยู่แล้ว — ใส่รหัสผิด 5 ครั้ง บัญชีถูกล็อก 15 นาที
-- ซึ่งกันการเดารหัสผ่านของ "บัญชีหนึ่ง" ได้ดี
--
-- แต่กัน credential stuffing ไม่ได้เลย — ผู้โจมตีที่มีรายชื่อรหัสประจำตัว
-- นักศึกษาทั้งวิทยาลัย (ซึ่งเดาได้จากรูปแบบ 67201010xxx) ลองรหัสผ่านยอดนิยม
-- **หนึ่งตัว** กับ **ทุกบัญชี** จะไม่ทำให้บัญชีไหนถูกล็อกเลยสักบัญชี
-- เพราะแต่ละบัญชีถูกลองแค่ครั้งเดียว แต่ผู้โจมตีได้ลองไปแล้วเป็นพันครั้ง
-- และมักได้บัญชีที่ตั้งรหัสง่าย ๆ ไปอย่างน้อยหนึ่งบัญชีเสมอ
--
-- การนับรายไอพีจึงเป็นคนละมิติกับการล็อกบัญชี ต้องมีทั้งคู่
--
-- ─── ทำไมนับในฐานข้อมูล ไม่ใช่ในหน่วยความจำของโปรเซส ───
-- ตัวนับในหน่วยความจำจะถูกแบ่งตามจำนวน instance — รัน 3 instance
-- แปลว่าผู้โจมตีได้โควตาสามเท่าโดยอัตโนมัติ และรีสตาร์ททีเดียวโควตาก็คืนมาใหม่
-- ตาราง login_attempt เก็บ ip_hash กับ attempted_at ไว้อยู่แล้วตาม
-- พ.ร.บ.คอมพิวเตอร์ มาตรา 26 จึงใช้เป็นตัวนับได้เลยโดยไม่ต้องเพิ่มอะไร
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table auth_policy
  add column if not exists max_ip_attempts    smallint not null default 30,
  add column if not exists ip_window_minutes  smallint not null default 15,
  add column if not exists ip_block_minutes   smallint not null default 30;

comment on column auth_policy.max_ip_attempts is
  'จำนวนครั้งที่ล้มเหลวสูงสุดต่อไอพีในหนึ่งช่วงเวลา — กัน credential stuffing ที่การล็อกบัญชีกันไม่ได้';

-- ดัชนีสำหรับนับรายไอพีในช่วงเวลาย้อนหลัง
-- ต้องมีเพราะทุกคำขอเข้าสู่ระบบจะยิง query นี้ ถ้าสแกนทั้งตารางจะช้าลง
-- เรื่อย ๆ ตามอายุระบบ จนกลายเป็นช่องทาง DoS เสียเอง
create index if not exists login_attempt_ip_window_idx
  on login_attempt (institution_id, ip_hash, attempted_at desc)
  where not succeeded;

-- ───────────────────────────────────────────────────────────────────
-- สถานะของไอพีหนึ่ง ณ ขณะนี้
--
-- คืนค่าแทนที่จะ raise เพราะชั้น API ต้องเอาตัวเลขไปใส่เฮดเดอร์
-- RateLimit-Remaining และ Retry-After ให้ผู้เรียกรู้ว่าเหลือกี่ครั้ง
-- และรออีกนานเท่าไร การ raise อย่างเดียวทำให้บอกไม่ได้
-- ───────────────────────────────────────────────────────────────────
create or replace function login_rate_status(
  p_institution_id uuid,
  p_ip_hash        bytea
) returns table (
  recent_failures  integer,
  max_attempts     integer,
  remaining        integer,
  blocked          boolean,
  retry_after_secs integer
)
language plpgsql stable as $$
declare
  v_max     smallint;
  v_window  smallint;
  v_block   smallint;
  v_oldest  timestamptz;
begin
  select coalesce(ap.max_ip_attempts, 30),
         coalesce(ap.ip_window_minutes, 15),
         coalesce(ap.ip_block_minutes, 30)
    into v_max, v_window, v_block
    from auth_policy ap where ap.institution_id = p_institution_id;

  -- สถานศึกษาที่ยังไม่ได้ตั้งนโยบายใช้ค่าเริ่มต้น ไม่ใช่ปล่อยผ่าน
  -- ค่าเริ่มต้นที่ปลอดภัยสำคัญกว่าความสะดวกตอนตั้งระบบใหม่
  v_max    := coalesce(v_max, 30);
  v_window := coalesce(v_window, 15);
  v_block  := coalesce(v_block, 30);

  if p_ip_hash is null then
    -- ไม่รู้ไอพี (เช่นเรียกจากภายในเครื่อง) ไม่นับ แต่ก็ไม่ปลดล็อกให้ใคร
    return query select 0, v_max::integer, v_max::integer, false, 0;
    return;
  end if;

  select count(*)::integer, min(la.attempted_at)
    into recent_failures, v_oldest
    from login_attempt la
   where la.institution_id = p_institution_id
     and la.ip_hash        = p_ip_hash
     and not la.succeeded
     and la.attempted_at > now() - make_interval(mins => v_window);

  max_attempts     := v_max;
  remaining        := greatest(v_max - recent_failures, 0);
  blocked          := recent_failures >= v_max;
  retry_after_secs := case
                        when recent_failures >= v_max
                        then greatest(
                               extract(epoch from
                                 (v_oldest + make_interval(mins => v_block)) - now())::integer,
                               1)
                        else 0
                      end;
  return next;
end $$;

comment on function login_rate_status(uuid, bytea) is
  'สถานะการจำกัดจำนวนครั้งรายไอพี — คืนค่าให้ชั้น API เอาไปใส่เฮดเดอร์ RateLimit ไม่ใช่ raise ทิ้ง';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0022_staff_roles_and_audit.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0022_staff_roles_and_audit.sql
--
-- สิทธิของบุคลากร และบันทึกการเข้าถึงหรือเปลี่ยนแปลงข้อมูล
--
-- ─── ช่องโหว่ที่ปิดในไฟล์นี้ ───
-- ระบบมีบทบาทเก้าตัวที่ RLS ทั้งหมดพึ่งพา แต่ roleOf() ในชั้น API
-- คืนได้แค่ teacher กับ student เท่านั้น — ใครที่เป็นบุคลากรจะได้ teacher
-- ทุกคนไม่ว่าจะทำงานอะไร
--
-- ผลคือในระบบจริงที่ปิด DEV_AUTH **ไม่มีใครเป็น registrar, finance,
-- academic, director หรือ admin ได้เลย** งานทะเบียนออกใบแจ้งหนี้ไม่ได้
-- ฝ่ายวิชาการอนุมัติเกรดไม่ได้ ผู้อำนวยการดูรายงานไม่ได้
-- นโยบาย RLS ที่เขียนไว้อย่างละเอียดสำหรับบทบาทเหล่านั้นไม่เคยถูกใช้จริง
--
-- ─── ทำไมบทบาทต้องมีช่วงเวลา ───
-- หัวหน้าแผนกและรักษาการมีวาระ การเก็บเป็นคอลัมน์เดียวบน staff
-- ทำให้ตอบไม่ได้ว่า "ตอนอนุมัติเกรดใบนั้นเมื่อปีที่แล้ว คนนี้มีสิทธิ์ไหม"
-- ซึ่งเป็นคำถามแรกที่ผู้ตรวจสอบถาม
--
-- ─── ทำไมต้องมีบันทึกการเข้าถึง ไม่ใช่แค่การเปลี่ยนแปลง ───
-- grade_ledger บันทึกการ "เขียน" ผลการเรียนไว้แล้ว แต่ PDPA มาตรา 37
-- กำหนดให้ผู้ควบคุมข้อมูลต้องมีมาตรการตรวจสอบย้อนหลังได้ว่าใคร **เข้าถึง**
-- ข้อมูลส่วนบุคคลบ้าง การรั่วไหลส่วนใหญ่คือการอ่านแล้วคัดลอกออกไป
-- ซึ่งไม่ทิ้งร่องรอยใด ๆ ในระบบที่บันทึกเฉพาะการเขียน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บทบาทของบุคลากร
-- ───────────────────────────────────────────────────────────────────
create type staff_role_kind as enum (
  'registrar',        -- งานทะเบียน
  'academic',         -- ฝ่ายวิชาการ
  'finance',          -- การเงิน
  'student_affairs',  -- งานปกครองและแนะแนว
  'director',         -- ผู้อำนวยการ
  'admin'             -- ผู้ดูแลระบบ
);

comment on type staff_role_kind is
  'บทบาทที่มอบหมายให้บุคลากรได้ — ไม่มี teacher เพราะการเป็นครูผู้สอนมาจาก staff.is_teacher และการถูกกำหนดเป็นครูประจำกลุ่มเรียน ไม่ใช่การมอบหมายสิทธิ';

create table staff_role (
  id             uuid            primary key default gen_random_uuid(),
  staff_id       uuid            not null references staff on delete cascade,
  role           staff_role_kind not null,
  effective_from date            not null default current_date,
  effective_to   date,
  granted_by     uuid            references staff,
  reason         text,

  -- ─── ทำไมมีทั้ง effective_to และ revoked_at ───
  -- effective_to คือวันสุดท้ายของวาระที่วางแผนไว้ล่วงหน้า เช่นรักษาการ
  -- ถึงสิ้นเดือน ส่วน revoked_at คือการตัดสิทธิ์ทันทีเมื่อมีเหตุ เช่นถูกให้
  -- ออกจากงานหรือพบการใช้สิทธิ์ในทางมิชอบ
  --
  -- ถ้ามีแต่ effective_to จะตัดสิทธิ์คนที่เพิ่งได้รับมอบหมายวันนี้ไม่ได้เลย
  -- เพราะ effective_to ต้องไม่น้อยกว่า effective_from — ต้องรอถึงพรุ่งนี้
  -- ซึ่งใช้ไม่ได้กับสถานการณ์ที่ต้องตัดสิทธิ์เดี๋ยวนั้น
  revoked_at     timestamptz,
  revoked_by     uuid            references staff,
  revoke_reason  text,

  created_at     timestamptz     not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (revoked_at is null or revoke_reason is not null),

  -- คนเดียวถือบทบาทเดิมซ้อนช่วงเวลากันไม่ได้
  -- ถ้าซ้อนได้ การตอบว่า "วันนั้นมีสิทธิ์ไหม" จะได้หลายคำตอบพร้อมกัน
  -- btree_gist รองรับ enum ได้โดยตรง ไม่ต้อง cast เป็น text
  -- (การ cast enum เป็น text เป็น STABLE ไม่ใช่ IMMUTABLE จึงใช้ในดัชนีไม่ได้)
  exclude using gist (
    staff_id with =,
    role with =,
    daterange(effective_from, coalesce(effective_to, date '9999-12-31'), '[]') with &&
  ) where (revoked_at is null)
);
create index on staff_role (staff_id) where effective_to is null;
create index on staff_role (role, effective_from desc);

comment on table staff_role is
  'บทบาทที่บุคลากรถืออยู่ พร้อมช่วงเวลา — ตอบได้ว่า ณ วันใดวันหนึ่งใครมีสิทธิ์อะไร';

-- ───────────────────────────────────────────────────────────────────
-- บทบาทที่ใช้ได้จริง ณ วันนี้
--
-- คืนบทบาทเดียวที่ "แรงที่สุด" เพราะ token มีช่องบทบาทช่องเดียว
-- และ RLS อ่านค่าเดียว การให้เลือกเองตอนล็อกอินจะทำให้ผู้ใช้สับสน
-- และเปิดช่องให้เลือกบทบาทที่ตัวเองไม่ควรใช้ในงานนั้น
--
-- ลำดับความแรงตามขอบเขตที่มองเห็นข้อมูล ไม่ใช่ตามตำแหน่งในองค์กร
-- ───────────────────────────────────────────────────────────────────
create or replace function effective_staff_role(p_person_id uuid, p_on date default current_date)
returns text
language sql stable as $$
  select sr.role::text
    from staff_role sr
    join staff st on st.id = sr.staff_id
   where st.person_id = p_person_id
     and st.active
     and sr.revoked_at is null
     and sr.effective_from <= p_on
     and (sr.effective_to is null or sr.effective_to >= p_on)
   order by case sr.role
              when 'admin'           then 1
              when 'director'        then 2
              when 'registrar'       then 3
              when 'academic'        then 4
              when 'finance'         then 5
              when 'student_affairs' then 6
            end
   limit 1
$$;

comment on function effective_staff_role(uuid, date) is
  'บทบาทที่แรงที่สุดที่บุคลากรคนนี้ถืออยู่ ณ วันที่ระบุ — ชั้น API ใช้ตอนล็อกอินแทนการเดาว่าทุกคนเป็น teacher';

-- ───────────────────────────────────────────────────────────────────
-- บทบาทที่ผู้ใช้ได้ตอนล็อกอิน
--
-- ─── ทำไมต้องเป็น security definer ───
-- ตอนล็อกอินยังไม่รู้ว่าผู้ใช้เป็นใคร บริบทจึงเป็นบทบาท 'auth' ที่
-- ไม่ใช่บทบาทระดับสถานศึกษา นโยบาย subject_scope ของ student จึงบล็อก
-- การอ่าน ทำให้หาไม่เจอว่าคนนี้เป็นนักศึกษา
--
-- โค้ดเดิมในชั้น API ไม่เจอปัญหานี้เพราะมันตกไปเป็น 'student' เสมอ
-- เมื่ออ่านไม่เห็นอะไร ซึ่งบังเอิญให้ผลถูกกับนักศึกษา แต่ซ่อนความจริงว่า
-- การอ่านถูกบล็อกอยู่ และทำให้บุคลากรทุกคนได้ teacher ไปด้วย
--
-- ปลอดภัยเพราะรับ person_id ที่ผู้เรียกรู้อยู่แล้ว (ผ่านการตรวจรหัสผ่านมาแล้ว)
-- และคืนออกไปแค่ชื่อบทบาท ไม่ใช่ข้อมูลส่วนบุคคลใด ๆ
-- ───────────────────────────────────────────────────────────────────
create or replace function login_role_for(p_person_id uuid, p_institution_id uuid)
returns text
language sql stable security definer
set search_path = public as $$
  select coalesce(
    -- บุคลากรที่ได้รับมอบหมายบทบาท
    (select effective_staff_role(p_person_id)
       from staff st
      where st.person_id = p_person_id
        and st.institution_id = p_institution_id
        and st.active
      limit 1),
    -- บุคลากรที่เป็นครูผู้สอน
    (select 'teacher' from staff st
      where st.person_id = p_person_id
        and st.institution_id = p_institution_id
        and st.active and st.is_teacher limit 1),
    -- นักศึกษา
    (select 'student' from student s
      where s.person_id = p_person_id
        and s.institution_id = p_institution_id limit 1),
    -- ผู้ปกครองที่ยืนยันตัวตนแล้ว
    (select 'guardian' from student_guardian sg
       join student s on s.id = sg.student_id
      where sg.person_id = p_person_id
        and sg.verified_at is not null
        and s.institution_id = p_institution_id limit 1)
  )
$$;

comment on function login_role_for(uuid, uuid) is
  'บทบาทที่ผู้ใช้ได้ตอนล็อกอิน — คืน null ถ้าไม่ผูกกับบทบาทใดเลย ซึ่งแปลว่าเข้าระบบไม่ได้';

revoke all on function login_role_for(uuid, uuid) from public;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการเข้าถึงและเปลี่ยนแปลงข้อมูล
--
-- ─── ทำไมแยกจาก grade_ledger ───
-- grade_ledger เป็นโซ่แฮชที่ออกแบบมาเพื่อ "พิสูจน์ว่าไม่ถูกแก้ย้อนหลัง"
-- ซึ่งจำเป็นกับผลการเรียนที่ใช้ยันเงินอุดหนุนและออกเอกสารราชการ
-- ส่วนตารางนี้เป็นบันทึกปริมาณมากที่เขียนทุกคำขอ การใส่โซ่แฮชกับมัน
-- จะทำให้ทุกคำขอต้องล็อกแถวสุดท้ายของตารางเรียงกัน กลายเป็นคอขวด
-- ───────────────────────────────────────────────────────────────────
create type audit_action as enum ('read', 'create', 'update', 'delete', 'export', 'login');

create table access_log (
  id             bigserial    primary key,
  institution_id uuid         not null references institution,
  actor_id       uuid,                       -- person_id ของผู้กระทำ
  actor_role     text,
  action         audit_action not null,
  entity         text         not null,      -- 'student' | 'invoice' | ...
  entity_id      uuid,
  subject_id     uuid,                       -- เจ้าของข้อมูล ถ้าข้อมูลนั้นเป็นของใครคนหนึ่ง
  route          text,
  detail         jsonb        not null default '{}'::jsonb,
  ip_hash        bytea,                      -- ไอพีเป็นข้อมูลส่วนบุคคล เก็บเป็นค่าแฮชเหมือน login_attempt
  occurred_at    timestamptz  not null default now()
);
create index on access_log (institution_id, occurred_at desc);
create index on access_log (subject_id, occurred_at desc) where subject_id is not null;
create index on access_log (actor_id, occurred_at desc);
create index on access_log (entity, entity_id);

comment on table access_log is
  'ใครเข้าถึงหรือเปลี่ยนแปลงข้อมูลของใครเมื่อไร — ตาม PDPA มาตรา 37 ที่ต้องตรวจสอบย้อนหลังได้ เก็บไม่น้อยกว่า 90 วันตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26';
comment on column access_log.subject_id is
  'person_id ของเจ้าของข้อมูล ใช้ตอบคำถาม "ใครดูข้อมูลของลูกฉันบ้าง" ซึ่งเจ้าของข้อมูลมีสิทธิ์ถามตาม PDPA มาตรา 30';

-- ล้างบันทึกที่เกินระยะเก็บ — ตั้งเป็นงานประจำวันเหมือน purge_login_attempts
create or replace function purge_access_log(p_keep_days integer default 90)
returns integer language plpgsql as $$
declare v_n integer;
begin
  if p_keep_days < 90 then
    raise exception 'ระยะเก็บบันทึกการเข้าถึงต่ำกว่า 90 วันไม่ได้ตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26';
  end if;
  delete from access_log where occurred_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table staff_role enable row level security;
alter table staff_role force  row level security;
create policy tenant_isolation on staff_role
  using (exists (select 1 from staff st
                 where st.id = staff_role.staff_id
                   and st.institution_id = current_institution_id()))
  with check (exists (select 1 from staff st
                      where st.id = staff_role.staff_id
                        and st.institution_id = current_institution_id()));

/*
 * การมอบหมายสิทธิเป็นงานของผู้ดูแลระบบและผู้อำนวยการเท่านั้น
 *
 * ถ้าปล่อยให้บทบาทอื่นเขียนได้ ใครก็ตามที่มีสิทธิ์เขียนตารางนี้จะยกระดับ
 * ตัวเองเป็น admin ได้ในคำสั่งเดียว แล้วสิทธิทั้งระบบก็ไม่มีความหมาย
 * ส่วนการอ่านเปิดให้ทุกคนในวิทยาลัย เพราะต้องรู้ว่าใครรับผิดชอบอะไร
 */
create policy staff_role_write on staff_role
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('admin', 'director'));

alter table access_log enable row level security;
alter table access_log force  row level security;

-- อ่านได้เฉพาะผู้ดูแล ผู้อำนวยการ และเจ้าของข้อมูลเอง
create policy access_log_read on access_log
  for select using (
    institution_id = current_institution_id()
    and (
      current_app_role() in ('admin', 'director')
      or subject_id = current_actor_id()
    )
  );

-- เขียนได้ทุกบทบาท เพราะทุกคำขอต้องบันทึกได้
create policy access_log_append on access_log
  for insert with check (institution_id = current_institution_id());

-- ไม่มีนโยบาย update โดยเจตนา — บันทึกการตรวจสอบที่แก้ได้ไม่มีค่าในการตรวจสอบ
--
-- ส่วน delete อนุญาตเฉพาะแถวที่เกินระยะเก็บขั้นต่ำแล้ว
-- ตั้งใจให้เป็นนโยบายไม่ใช่ปล่อยว่าง เพราะ force row level security
-- มีผลกับเจ้าของตารางด้วย ถ้าไม่มีนโยบาย delete เลย purge_access_log()
-- จะลบไม่ได้สักแถวและบันทึกจะโตไปเรื่อย ๆ จนเต็มดิสก์
--
-- เงื่อนไขในนโยบายทำให้ **ไม่มีใครลบบันทึกของเมื่อวานได้** แม้แต่ admin
-- ซึ่งเป็นคุณสมบัติที่ทำให้บันทึกนี้ใช้เป็นหลักฐานได้จริง
create policy access_log_purge_aged on access_log
  for delete using (occurred_at < now() - interval '90 days');

-- ต้องให้สิทธิ์หลังสร้างตารางใหม่ เพราะ roles.sql รันไปก่อนหน้านี้แล้ว
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on staff_role, access_log to app_runtime;
    grant usage, select on sequence access_log_id_seq to app_runtime;
    grant execute on function login_role_for(uuid, uuid)          to app_runtime;
    grant execute on function effective_staff_role(uuid, date)    to app_runtime;
    grant execute on function purge_access_log(integer)           to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0023_data_import.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0023_data_import.sql
--
-- นำเข้าข้อมูลนักศึกษาและประวัติการเรียนจากระบบเดิม
--
-- ─── ปัญหาที่แก้ ───
-- วิทยาลัยที่ย้ายมาใช้ระบบนี้มีนักศึกษาอยู่แล้วหลักพันคน พร้อมผลการเรียน
-- ย้อนหลังหลายภาคเรียน จะเริ่มจากฐานข้อมูลเปล่าไม่ได้ และการให้เจ้าหน้าที่
-- กรอกทีละคนใช้เวลาเป็นเดือนและผิดพลาดมากกว่าการนำเข้า
--
-- ─── ทำไมต้องมีรอบทดลอง (dry run) ───
-- การนำเข้าที่ล้มเหลวกลางคันแล้วเหลือข้อมูลครึ่ง ๆ กลาง ๆ แก้ยากกว่าไม่นำเข้าเลย
-- เพราะเจ้าหน้าที่ไม่รู้ว่าแถวไหนเข้าไปแล้วบ้าง รอบทดลองตรวจทุกแถวแล้วรายงาน
-- ปัญหาทั้งหมดกลับไปโดยไม่เขียนอะไรเลย ให้แก้ไฟล์ให้ถูกก่อนค่อยนำเข้าจริง
--
-- ─── ทำไมประวัติการเรียนที่นำเข้าต้องแยกออกจากผลที่ระบบตัดเอง ───
-- enrollment_result เป็นตารางเขียนอย่างเดียวที่มีโซ่แฮชกำกับ ใช้ยันจำนวน
-- นักศึกษาที่ขอรับเงินอุดหนุนและออกเอกสารราชการ ผลที่นำเข้ามาจากระบบเดิม
-- ไม่ได้ผ่านการตัดเกรดของระบบนี้ จึงต้องแยกให้เห็นชัดว่าแถวไหนมาจากไหน
-- มิฉะนั้นตอนตรวจสอบจะแยกไม่ออกระหว่าง "ระบบคำนวณให้" กับ "คนกรอกเข้ามา"
-- ═══════════════════════════════════════════════════════════════════
begin;

create type import_kind   as enum ('student', 'academic_history', 'staff');
create type import_status as enum ('draft', 'validated', 'applied', 'failed');

create table import_batch (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  kind           import_kind   not null,
  source_name    text,                       -- ชื่อไฟล์ต้นทาง ใช้ตามรอยว่ามาจากไหน
  status         import_status not null default 'draft',
  total_rows     integer       not null default 0,
  ok_rows        integer       not null default 0,
  error_rows     integer       not null default 0,
  created_by     uuid,
  created_at     timestamptz   not null default now(),
  applied_at     timestamptz,
  note           text
);
create index on import_batch (institution_id, created_at desc);

comment on table import_batch is
  'หนึ่งรอบการนำเข้า — เก็บไว้เพื่อตอบว่าข้อมูลแถวไหนมาจากไฟล์ไหนเมื่อไร ซึ่งจำเป็นตอนพบข้อมูลผิดแล้วต้องตามหาต้นตอ';

create table import_row (
  id           uuid        primary key default gen_random_uuid(),
  batch_id     uuid        not null references import_batch on delete cascade,
  row_no       integer     not null,
  payload      jsonb       not null,
  ok           boolean     not null default false,
  errors       text[]      not null default '{}',
  created_ref  uuid,                        -- id ของแถวที่สร้างขึ้นจริง
  unique (batch_id, row_no)
);
create index on import_row (batch_id) where not ok;

comment on column import_row.errors is
  'ปัญหาทั้งหมดของแถวนี้ ไม่ใช่ข้อแรกที่เจอ — เจ้าหน้าที่ต้องเห็นทุกอย่างที่ต้องแก้ในรอบเดียว เหมือน check_registration()';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจข้อมูลนักศึกษาหนึ่งแถว
--
-- คืนรายการปัญหาทั้งหมด ไม่หยุดที่ข้อแรก ด้วยเหตุผลเดียวกับ
-- check_registration() — ถ้าหยุดที่ข้อแรก เจ้าหน้าที่จะต้องแก้แล้วนำเข้าใหม่
-- หลายรอบกว่าจะครบ ซึ่งกับไฟล์พันแถวคือการทำงานหลายวัน
-- ───────────────────────────────────────────────────────────────────
create or replace function validate_student_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors text[] := '{}';
  v_code   text := nullif(btrim(p_payload->>'student_code'), '');
  v_first  text := nullif(btrim(p_payload->>'first_name_th'), '');
  v_last   text := nullif(btrim(p_payload->>'last_name_th'), '');
  v_year   text := p_payload->>'admitted_year_be';
  v_nat    text := nullif(btrim(p_payload->>'national_id'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวนักศึกษา');
  elsif exists (select 1 from student s
                 where s.institution_id = p_institution_id and s.student_code = v_code) then
    v_errors := array_append(v_errors, format('รหัสประจำตัว %s มีอยู่ในระบบแล้ว', v_code));
  end if;

  if v_first is null then v_errors := array_append(v_errors, 'ไม่มีชื่อ'); end if;
  if v_last  is null then v_errors := array_append(v_errors, 'ไม่มีนามสกุล'); end if;

  if v_year is null or v_year !~ '^\d{4}$' then
    v_errors := array_append(v_errors, 'ปีที่เข้าศึกษาต้องเป็นพุทธศักราชสี่หลัก');
  elsif v_year::int < 2500 or v_year::int > 2700 then
    v_errors := array_append(v_errors, format('ปีที่เข้าศึกษา %s ไม่อยู่ในช่วงที่รับได้ (2500-2700)', v_year));
  end if;

  -- เลขประจำตัวประชาชนตรวจ checksum ได้ จึงควรตรวจตั้งแต่ตอนนำเข้า
  -- ไม่ใช่ปล่อยให้ผิดแล้วไปเจอตอนออกเอกสารราชการ
  if v_nat is not null then
    if v_nat !~ '^\d{13}$' then
      v_errors := array_append(v_errors, 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก');
    elsif not thai_national_id_valid(v_nat) then
      v_errors := array_append(v_errors, format('เลขประจำตัวประชาชน %s ไม่ผ่านการตรวจหลักที่ 13', v_nat));
    end if;
  end if;

  if p_payload ? 'status'
     and p_payload->>'status' not in
         ('active','on_leave','suspended','withdrawn','transferred_out','dismissed','graduated') then
    v_errors := array_append(v_errors, format('สถานะ "%s" ไม่ถูกต้อง', p_payload->>'status'));
  end if;

  return v_errors;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจหลักที่ 13 ของเลขประจำตัวประชาชน
--
-- ตรวจได้ตั้งแต่ตอนนำเข้าโดยไม่ต้องต่อระบบภายนอก จับการพิมพ์ผิดได้เกือบทั้งหมด
-- ซึ่งสำคัญเพราะเลขนี้ใช้ยันตัวตนตอนขอรับเงินอุดหนุนและออกเอกสารราชการ
-- ───────────────────────────────────────────────────────────────────
create or replace function thai_national_id_valid(p_id text)
returns boolean
language plpgsql immutable as $$
declare v_sum integer := 0; i integer;
begin
  if p_id is null or p_id !~ '^\d{13}$' then return false; end if;
  for i in 1..12 loop
    v_sum := v_sum + substr(p_id, i, 1)::int * (14 - i);
  end loop;
  return ((11 - (v_sum % 11)) % 10) = substr(p_id, 13, 1)::int;
end $$;

comment on function thai_national_id_valid(text) is
  'ตรวจหลักที่ 13 ของเลขประจำตัวประชาชน — จับการพิมพ์ผิดได้ตั้งแต่ตอนนำเข้า ไม่ต้องรอไปเจอตอนออกเอกสาร';

-- ───────────────────────────────────────────────────────────────────
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย
--
-- ถ้ามีแถวใดผิด จะไม่เขียนอะไรเลยและคืนรายการปัญหาทั้งหมด
-- เหตุผลเดียวกับ register_courses() — ข้อมูลที่เข้าไปครึ่งเดียว
-- แก้ยากกว่าไม่เข้าเลย เพราะไม่มีใครรู้ว่าแถวไหนเข้าไปแล้ว
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_student_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch  import_batch%rowtype;
  r        record;
  v_person uuid;
  v_student uuid;
  v_bad    integer := 0;
  v_ok     integer := 0;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'student' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ข้อมูลนักศึกษา', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_student_row(v_batch.institution_id, r.payload);
      update import_row
         set errors = v_errs, ok = (cardinality(v_errs) = 0)
       where id = r.id;
      if cardinality(v_errs) > 0 then v_bad := v_bad + 1; end if;
    end;
  end loop;

  if v_bad > 0 then
    update import_batch
       set status = 'failed', error_rows = v_bad,
           ok_rows = (select count(*) from import_row where batch_id = p_batch_id and ok)
     where id = p_batch_id;
    -- ข้อความไม่ชี้ไปที่ import_row เพราะ `raise` rollback การเขียน errors
    -- ข้างบนไปด้วย รายละเอียดรายแถวจึงหายไปพร้อมข้อผิดพลาด (ดู 0043)
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email)
    values (
      v_batch.institution_id,
      nullif(btrim(r.payload->>'prefix_th'), ''),
      btrim(r.payload->>'first_name_th'),
      btrim(r.payload->>'last_name_th'),
      -- เก็บเป็นค่าแฮชเพื่อตรวจซ้ำได้โดยไม่ต้องเก็บเลขจริงไว้แบบอ่านออก
      -- คอลัมน์ national_id_enc รอเชื่อม KMS จึงยังไม่เขียนเลขจริงลงไป
      case when nullif(btrim(r.payload->>'national_id'), '') is not null
           then digest(btrim(r.payload->>'national_id'), 'sha256') end,
      (nullif(btrim(r.payload->>'birth_date'), ''))::date,
      coalesce(nullif(btrim(r.payload->>'gender'), ''), 'undisclosed')::gender_kind,
      nullif(btrim(r.payload->>'phone'), ''),
      nullif(btrim(r.payload->>'email'), '')
    )
    returning id into v_person;

    insert into student
      (institution_id, person_id, student_code, admitted_year_be, status)
    values (
      v_batch.institution_id, v_person,
      btrim(r.payload->>'student_code'),
      (r.payload->>'admitted_year_be')::smallint,
      coalesce(nullif(btrim(r.payload->>'status'), ''), 'active')::student_status
    )
    returning id into v_student;

    update import_row set created_ref = v_student, ok = true where id = r.id;
    v_ok := v_ok + 1;
  end loop;

  update import_batch
     set status = 'applied', applied_at = now(),
         ok_rows = v_ok, error_rows = 0, total_rows = v_ok
   where id = p_batch_id;

  imported := v_ok;
  failed   := 0;
  return next;
end $$;

comment on function apply_student_import(uuid) is
  'นำเข้าข้อมูลนักศึกษาทั้งชุด — มีแถวใดผิดจะไม่เขียนอะไรเลย เพราะข้อมูลที่เข้าไปครึ่งเดียวแก้ยากกว่าไม่เข้าเลย';

-- ───────────────────────────────────────────────────────────────────
-- ประวัติการเรียนที่นำเข้าจากระบบเดิม
--
-- ─── ทำไมไม่เขียนลง enrollment_result ตรง ๆ ───
-- enrollment_result ต้องผูกกับ enrollment ซึ่งต้องผูกกับ class_section
-- ของภาคเรียนที่มีอยู่จริงในระบบนี้ ประวัติจากระบบเดิมไม่มีสิ่งเหล่านั้น
-- การสร้างกลุ่มเรียนปลอมย้อนหลังให้ครบเพื่อรองรับประวัติ จะทำให้รายงาน
-- จำนวนกลุ่มเรียนและภาระงานครูผิดไปทั้งหมด
--
-- ตารางนี้จึงเก็บประวัติเป็นข้อมูลของตัวเอง แล้วให้การตรวจจบนับรวม
-- ซึ่งตรงกับความจริงว่า "หน่วยกิตนี้ได้มาจากที่อื่น ไม่ใช่จากระบบนี้"
-- ───────────────────────────────────────────────────────────────────
create table prior_academic_record (
  id              uuid         primary key default gen_random_uuid(),
  student_id      uuid         not null references student on delete cascade,
  batch_id        uuid         references import_batch,
  source_th       text         not null,          -- ชื่อสถานศึกษาเดิม
  term_label      text,                           -- เช่น '2566/1' ตามที่ระบบเดิมใช้
  course_code     text         not null,
  course_name_th  text         not null,
  credits         numeric(3,1) not null check (credits > 0),
  grade_symbol    text         not null,
  grade_point     numeric(2,1),
  counts_in_gpa   boolean      not null default true,
  earns_credit    boolean      not null default true,
  -- เทียบโอนเข้ารายวิชาใดในหลักสูตรปัจจุบัน ถ้าเทียบได้
  mapped_course_id uuid        references course,
  approved_by     uuid         references staff,
  approved_at     timestamptz,
  note            text,
  created_at      timestamptz  not null default now(),
  unique (student_id, term_label, course_code)
);
create index on prior_academic_record (student_id);
create index on prior_academic_record (batch_id);

comment on table prior_academic_record is
  'ผลการเรียนจากสถานศึกษาเดิม แยกจาก enrollment_result โดยเจตนา เพราะไม่ได้ผ่านการตัดเกรดของระบบนี้ และไม่มีกลุ่มเรียนจริงรองรับ';
comment on column prior_academic_record.approved_at is
  'หน่วยกิตที่ยังไม่อนุมัติเทียบโอนจะไม่ถูกนับในการตรวจจบ เหมือนชั่วโมงฝึกที่ยังไม่รับรอง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table import_batch enable row level security;
alter table import_batch force  row level security;
create policy tenant_isolation on import_batch
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- การนำเข้าข้อมูลเป็นงานของทะเบียนและผู้ดูแลระบบ
-- ถ้าบทบาทอื่นนำเข้าได้ จะสร้างนักศึกษาปลอมเข้าระบบได้ในไฟล์เดียว
create policy import_write on import_batch
  as restrictive
  for all
  using (current_app_role() in ('registrar', 'academic', 'director', 'admin'))
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

alter table import_row enable row level security;
alter table import_row force  row level security;
create policy tenant_isolation on import_row
  using (exists (select 1 from import_batch b
                 where b.id = import_row.batch_id
                   and b.institution_id = current_institution_id()))
  with check (exists (select 1 from import_batch b
                      where b.id = import_row.batch_id
                        and b.institution_id = current_institution_id()));

alter table prior_academic_record enable row level security;
alter table prior_academic_record force  row level security;
create policy tenant_isolation on prior_academic_record
  using (student_institution(prior_academic_record.student_id) = current_institution_id())
  with check (student_institution(prior_academic_record.student_id) = current_institution_id());

-- นักศึกษาเห็นประวัติของตัวเอง ครูและงานทะเบียนเห็นตามหน้าที่
create policy prior_record_scope on prior_academic_record
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or prior_academic_record.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = prior_academic_record.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_grades)
  );

-- อนุมัติเทียบโอนเป็นงานของฝ่ายวิชาการ ไม่ใช่ของคนที่นำเข้าไฟล์
create policy prior_record_write on prior_academic_record
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete
      on import_batch, import_row, prior_academic_record to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0024_scale_indexes.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0024_scale_indexes.sql
--
-- ดัชนีสำหรับเส้นทางที่ถูกเรียกบ่อยที่สุดเมื่อข้อมูลโตขึ้น
--
-- ─── ทำไมเรื่องนี้สำคัญกว่าที่เห็นในระบบหลายผู้เช่า ───
-- ทุกวิทยาลัยใช้ตารางชุดเดียวกัน แยกกันด้วย Row-Level Security
-- แปลว่าการค้นหานักศึกษาของวิทยาลัยหนึ่ง **สแกนแถวของทุกวิทยาลัย**
-- แล้วค่อยให้ RLS กรองทิ้ง
--
-- วิทยาลัยเดียว 5,000 คนสแกน 5,000 แถว — ยอมรับได้
-- ยี่สิบวิทยาลัยรวม 100,000 คน การค้นหาของวิทยาลัยที่มีนักศึกษา 200 คน
-- ก็ยังสแกน 100,000 แถวอยู่ดี ซึ่งเป็นภาระที่ลูกค้ารายเล็กไม่ได้ก่อ
-- แต่ต้องแบกด้วย และแย่ลงเรื่อย ๆ ทุกครั้งที่ขายลูกค้าเพิ่ม
--
-- ─── ทำไม ilike '%คำ%' ใช้ดัชนีปกติไม่ได้ ───
-- ดัชนี btree เรียงตามลำดับตัวอักษรจากซ้าย จึงหา "ขึ้นต้นด้วย" ได้เร็ว
-- แต่ "มีคำนี้อยู่ตรงไหนก็ได้" ต้องดูทุกแถว ช่องค้นหาที่พิมพ์แล้วค้นทันที
-- จึงกลายเป็นการสแกนเต็มตารางทุกตัวอักษรที่พิมพ์
--
-- pg_trgm ตัดข้อความเป็นชุดสามตัวอักษรแล้วทำดัชนีจากชุดเหล่านั้น
-- ทำให้ค้นแบบมีคำอยู่ตรงกลางได้เร็ว และใช้ได้กับภาษาไทยด้วย
-- ═══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pg_trgm;

-- ───────────────────────────────────────────────────────────────────
-- ค้นหานักศึกษาและบุคลากร — เส้นทางที่เจ้าหน้าที่ใช้บ่อยที่สุด
-- ───────────────────────────────────────────────────────────────────
create index if not exists student_code_trgm_idx
  on student using gin (student_code gin_trgm_ops);

create index if not exists person_first_name_trgm_idx
  on person using gin (first_name_th gin_trgm_ops);

create index if not exists person_last_name_trgm_idx
  on person using gin (last_name_th gin_trgm_ops);

create index if not exists staff_code_trgm_idx
  on staff using gin (staff_code gin_trgm_ops);

-- ───────────────────────────────────────────────────────────────────
-- ดัชนีที่ขึ้นต้นด้วย institution_id
--
-- RLS เติมเงื่อนไข institution_id = current_institution_id() ให้ทุก query
-- อยู่แล้ว ดัชนีที่ขึ้นต้นด้วยคอลัมน์นั้นจึงตัดข้อมูลของวิทยาลัยอื่นทิ้ง
-- ตั้งแต่ระดับดัชนี ไม่ต้องอ่านแถวขึ้นมาก่อนแล้วค่อยกรอง
-- ───────────────────────────────────────────────────────────────────
create index if not exists student_institution_status_idx
  on student (institution_id, status, student_code);

create index if not exists person_institution_idx
  on person (institution_id);

-- ───────────────────────────────────────────────────────────────────
-- เส้นทางของแอปนักศึกษา — ถูกเรียกพร้อมกันมากที่สุดตอนประกาศผล
--
-- ช่วงประกาศผลคือช่วงที่ทุกคนเปิดแอปพร้อมกันภายในไม่กี่นาที
-- ซึ่งเป็นภาระสูงสุดของทั้งปี และเป็นช่วงที่ระบบล่มแล้วเสียหายที่สุด
-- ───────────────────────────────────────────────────────────────────
create index if not exists enrollment_student_term_idx
  on enrollment (student_id, term_id) where status = 'enrolled';

create index if not exists attendance_record_enrollment_idx
  on attendance_record (enrollment_id);

create index if not exists enrollment_result_current_lookup_idx
  on enrollment_result (enrollment_id) where superseded_by is null;

create index if not exists invoice_student_term_idx
  on invoice (student_id, term_id);

create index if not exists installment_due_idx
  on installment (invoice_id, due_on) where status <> 'paid';

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการเข้าถึง — เขียนทุกคำขอที่เปลี่ยนแปลงข้อมูล
--
-- ตารางนี้โตเร็วที่สุดในระบบ การล้างตามระยะเก็บต้องหาแถวเก่าได้เร็ว
-- มิฉะนั้นงานประจำวันจะสแกนทั้งตารางทุกคืนและช้าลงเรื่อย ๆ
-- ───────────────────────────────────────────────────────────────────
create index if not exists access_log_occurred_idx on access_log (occurred_at);

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0025_password_reset.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0025_password_reset.sql
--
-- การรีเซ็ตรหัสผ่านด้วยรหัสใช้ครั้งเดียว
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- ก่อนหน้านี้ทางเดียวที่คนลืมรหัสผ่านจะกลับเข้าระบบได้คือให้งานทะเบียนเรียก
-- POST /auth/credentials ออกรหัสผ่านชั่วคราวให้ใหม่ ซึ่งมีปัญหาสองอย่าง
--
--   1. เจ้าหน้าที่ **รู้รหัสผ่านของนักศึกษา** ตั้งแต่วินาทีที่ออกให้
--      จนถึงตอนที่นักศึกษาเข้ามาเปลี่ยน ช่วงนั้นเข้าระบบแทนกันได้จริง
--      และบันทึกการเข้าถึงจะระบุว่าเป็นฝีมือของนักศึกษา ไม่ใช่เจ้าหน้าที่
--   2. ต้องเดินไปที่งานทะเบียนเท่านั้น เพราะบอกรหัสผ่านทางโทรศัพท์
--      แล้วปล่อยให้ใช้ได้ตลอดไปนั้นยอมรับไม่ได้
--
-- ไฟล์นี้เปลี่ยนของที่ส่งมอบจาก "รหัสผ่าน" เป็น "รหัสรีเซ็ต" ที่
-- ใช้ได้ครั้งเดียว หมดอายุใน 30 นาที และ **ตั้งรหัสผ่านใหม่โดยเจ้าตัวเอง**
-- เจ้าหน้าที่จึงไม่มีวันรู้รหัสผ่านของใคร และบอกรหัสรีเซ็ตทางโทรศัพท์ได้
--
-- ─── ทำไมรหัสสั้นแทนลิงก์ยาว ───
-- นักศึกษาอาชีวะจำนวนมากไม่มีอีเมลของตัวเองตอนเข้าเรียน (เหตุผลเดียวกับที่
-- ชื่อผู้ใช้เป็นรหัสประจำตัวไม่ใช่อีเมล ดู 0014) ลิงก์รีเซ็ตทางอีเมลจึง
-- ครอบคลุมคนไม่ถึงครึ่ง รหัสสั้นที่อ่านให้ฟังทางโทรศัพท์หรือส่ง SMS ได้
-- ครอบคลุมทุกคน และยังใช้กับช่องทางอีเมลได้ด้วยเมื่อมีอีเมลบันทึกไว้
--
-- ─── ทำไมเก็บเฉพาะค่าแฮชของรหัส ───
-- หลักเดียวกับ refresh token — ถ้าฐานข้อมูลรั่ว ผู้โจมตีต้องไม่ได้อะไรไป
-- ชั้น API แฮชด้วยกุญแจที่อยู่นอกฐานข้อมูลก่อนส่งมาเก็บ (แบบเดียวกับ ip_hash)
-- เพราะรหัสแปดตัวอักษรที่แฮชด้วย sha256 เปล่า ๆ ถอดกลับได้ในไม่กี่วินาที
-- ด้วยการไล่เดาทุกความเป็นไปได้ ซึ่งจะทำให้ตารางนี้กลายเป็นจุดที่อ่อนที่สุด
-- ของทั้งระบบแทนที่จะเป็นจุดที่แข็งที่สุด
--
-- ─── ทำไมฟังก์ชันคืนค่าแทนที่จะ raise ───
-- ผลข้างเคียงด้านความปลอดภัยต้องคงอยู่แม้คำขอจะล้มเหลว — ตัวนับจำนวนครั้ง
-- ที่เดารหัสผิด และการเพิกถอนรหัสที่ถูกเดาจนครบโควตา ถ้าฟังก์ชัน raise
-- ฐานข้อมูลจะ rollback ทั้ง transaction ผลคือ **เดารหัสได้ไม่จำกัดครั้ง**
-- โดยที่ตัวนับไม่เคยขยับเลย ซึ่งเป็นกับดักเดียวกับที่ 0021 และ auth.service
-- อธิบายไว้ ชั้น API จึงต้องอ่านค่าที่คืนมาแล้วค่อยโยนข้อผิดพลาดเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ช่องทางส่งรหัสรีเซ็ต
--
-- staff_counter คือเจ้าหน้าที่ยืนยันตัวตนแล้วส่งมอบรหัสให้เอง ต่อหน้าหรือ
-- ทางโทรศัพท์ เก็บแยกจากช่องทางอัตโนมัติเพราะต้องตอบผู้ตรวจสอบได้ว่า
-- ครั้งไหนมีมนุษย์เป็นผู้ยืนยันตัวตน และเป็นใคร
-- ───────────────────────────────────────────────────────────────────
create type password_reset_channel as enum ('staff_counter', 'email', 'sms');

-- ───────────────────────────────────────────────────────────────────
-- นโยบายเพิ่มเติม — ต่อจาก 0014 และ 0021
-- ───────────────────────────────────────────────────────────────────
alter table auth_policy
  add column if not exists reset_code_minutes    smallint not null default 30,
  add column if not exists reset_code_attempts   smallint not null default 5,
  add column if not exists max_reset_per_day     smallint not null default 3,
  add column if not exists max_reset_per_ip_day  smallint not null default 15;

comment on column auth_policy.reset_code_minutes is
  'อายุของรหัสรีเซ็ต — สั้นพอที่รหัสซึ่งบอกทางโทรศัพท์แล้วมีคนได้ยินจะหมดอายุก่อนถูกใช้';
comment on column auth_policy.reset_code_attempts is
  'จำนวนครั้งที่กรอกรหัสผิดได้ก่อนรหัสนั้นถูกเพิกถอน — รหัสสั้นไม่มีตัวนับนี้เท่ากับเดาได้ไม่จำกัด';
comment on column auth_policy.max_reset_per_ip_day is
  'เพดานรายไอพี — กันการยิงขอรีเซ็ตให้คนทั้งวิทยาลัยจนค่า SMS บานปลายและกล่องข้อความของผู้ใช้เต็ม';

-- ───────────────────────────────────────────────────────────────────
-- คำขอรีเซ็ตรหัสผ่าน
--
-- ทุกแถวอยู่ต่อไปแม้ใช้ไปแล้วหรือหมดอายุแล้ว เพราะเป็นหลักฐานว่าใคร
-- ขอรีเซ็ตบัญชีของใครเมื่อไร ซึ่งเป็นคำถามแรกเวลาสงสัยว่าบัญชีถูกยึด
-- การล้างทำโดย purge_password_reset() ตามระยะเก็บเท่านั้น
-- ───────────────────────────────────────────────────────────────────
create table password_reset (
  id                uuid  primary key default gen_random_uuid(),
  institution_id    uuid  not null references institution    on delete cascade,
  person_id         uuid  not null references person         on delete cascade,
  credential_id     uuid  not null references user_credential on delete cascade,

  -- HMAC-SHA256 ของรหัสที่ normalize แล้ว กุญแจอยู่ในชั้น API ไม่ใช่ในนี้
  token_hash        bytea not null,

  channel           password_reset_channel not null,

  -- 'so***@example.com' หรือ '08******78' — ไว้ให้เจ้าหน้าที่ยืนยันปลายทาง
  -- โดยไม่ต้องเปิดดูข้อมูลติดต่อจริงของนักศึกษา
  destination_hint  text,

  issued_by         uuid  references staff,   -- เฉพาะช่องทางเคาน์เตอร์
  requested_ip_hash bytea,                    -- แฮชเหมือน login_attempt ตาม PDPA

  attempts          smallint    not null default 0,
  expires_at        timestamptz not null,
  consumed_at       timestamptz,
  revoked_at        timestamptz,
  revoke_reason     text,
  created_at        timestamptz not null default now(),

  check (expires_at > created_at),
  check (revoked_at is null or revoke_reason is not null),

  -- ช่องทางเคาน์เตอร์ต้องรู้ว่าเจ้าหน้าที่คนไหนเป็นผู้ยืนยันตัวตน
  -- ถ้าไม่บังคับ บันทึกจะตอบไม่ได้ว่าใครปล่อยรหัสออกไป ซึ่งเป็นข้อมูล
  -- ชิ้นเดียวที่มีค่าจริงเวลาสอบสวนกรณีบัญชีถูกยึด
  check (channel <> 'staff_counter' or issued_by is not null),

  unique (token_hash)
);

-- ค้นรหัสที่ยังใช้ได้ของคนหนึ่ง — ทุกครั้งที่มีคนกรอกรหัสจะยิง query นี้
create index password_reset_active_idx
  on password_reset (person_id, created_at desc)
  where consumed_at is null and revoked_at is null;

-- นับโควตารายวันของคนหนึ่งและของไอพีหนึ่ง
create index password_reset_person_day_idx on password_reset (person_id, created_at desc);
create index password_reset_ip_day_idx
  on password_reset (institution_id, requested_ip_hash, created_at desc)
  where requested_ip_hash is not null;

-- ล้างของเก่าตามระยะเก็บ
create index password_reset_created_idx on password_reset (created_at);

comment on table password_reset is
  'คำขอรีเซ็ตรหัสผ่าน เก็บเฉพาะค่าแฮชของรหัส — ใครขอรีเซ็ตบัญชีของใครเมื่อไร เป็นคำถามแรกเวลาสงสัยว่าบัญชีถูกยึด';
comment on column password_reset.token_hash is
  'HMAC-SHA256 ของรหัสรีเซ็ต กุญแจอยู่นอกฐานข้อมูล — sha256 เปล่า ๆ ของรหัสแปดตัวถอดกลับได้ในไม่กี่วินาที';

-- ───────────────────────────────────────────────────────────────────
-- ห้ามเขียนทับประวัติ
--
-- แถวที่ใช้ไปแล้วต้องแตะไม่ได้อีก และสาระสำคัญของคำขอต้องแก้ย้อนหลังไม่ได้
-- มิฉะนั้นคนที่เขียนตารางนี้ได้จะ "ต่ออายุ" รหัสของตัวเอง หรือย้ายรหัสที่
-- ตัวเองรู้ไปผูกกับบัญชีคนอื่นได้ ซึ่งทำให้ทั้งกลไกไม่มีความหมาย
-- ───────────────────────────────────────────────────────────────────
create or replace function password_reset_guard() returns trigger
language plpgsql as $$
begin
  if old.consumed_at is not null then
    raise exception 'รหัสรีเซ็ตที่ใช้ไปแล้วแก้ไขไม่ได้';
  end if;

  if new.institution_id is distinct from old.institution_id
     or new.person_id     is distinct from old.person_id
     or new.credential_id is distinct from old.credential_id
     or new.token_hash    is distinct from old.token_hash
     or new.channel       is distinct from old.channel
     or new.expires_at    is distinct from old.expires_at
     or new.created_at    is distinct from old.created_at then
    raise exception 'แก้สาระสำคัญของคำขอรีเซ็ตรหัสผ่านย้อนหลังไม่ได้ ให้ออกคำขอใหม่แทน';
  end if;

  return new;
end $$;

create trigger password_reset_no_rewrite before update on password_reset
  for each row execute function password_reset_guard();

-- ───────────────────────────────────────────────────────────────────
-- ปิดบังปลายทางก่อนแสดงให้เจ้าหน้าที่เห็น
--
-- งานทะเบียนต้องยืนยันได้ว่า "รหัสถูกส่งไปที่เบอร์ที่ลงท้าย 78 ใช่ไหม"
-- โดยไม่ต้องเปิดดูเบอร์เต็มของนักศึกษา ซึ่งเป็นหลักการเก็บข้อมูลเท่าที่
-- จำเป็นตาม PDPA มาตรา 22
-- ───────────────────────────────────────────────────────────────────
create or replace function mask_destination(
  p_value   text,
  p_channel password_reset_channel
) returns text
language sql immutable as $$
  select case
    when p_value is null then null
    when p_channel = 'email' and position('@' in p_value) > 0 then
      -- เก็บสองตัวแรกของชื่อกล่องไว้ให้จำได้ ที่เหลือปิดหมด โดเมนไม่ปิด
      -- เพราะโดเมนไม่ได้ระบุตัวบุคคล และช่วยให้ผู้ใช้รู้ว่าต้องไปเปิดกล่องไหน
      left(split_part(p_value, '@', 1), 2)
        || repeat('*', greatest(length(split_part(p_value, '@', 1)) - 2, 1))
        || '@' || split_part(p_value, '@', 2)
    when p_channel = 'sms' then
      left(p_value, 2)
        || repeat('*', greatest(length(p_value) - 4, 1))
        || right(p_value, 2)
    else null
  end
$$;

-- ───────────────────────────────────────────────────────────────────
-- ขอรหัสรีเซ็ต
--
-- p_channel เป็น null แปลว่า "ให้ระบบเลือกจากช่องทางที่บันทึกไว้"
-- ซึ่งเป็นกรณีที่ผู้ใช้กดขอเอง ส่วนช่องทางเคาน์เตอร์ต้องระบุมาชัดเจน
-- พร้อม person_id ของเจ้าหน้าที่ผู้ยืนยันตัวตน
--
-- คืน issued = false พร้อมเหตุผลเสมอ ไม่ raise เพราะชั้น API ต้องตอบ
-- ข้อความเดียวกันทุกกรณีเพื่อไม่ให้บอกได้ว่ารหัสประจำตัวไหนมีอยู่จริง
-- แต่ยังต้องเขียนบันทึกและนับโควตาให้ติดถาวรก่อนตอบกลับ
-- ───────────────────────────────────────────────────────────────────
create or replace function request_password_reset(
  p_institution_id uuid,
  p_username       text,
  p_channel        password_reset_channel,
  p_token_hash     bytea,
  p_ip_hash        bytea default null,
  p_issued_by      uuid  default null
) returns table (
  issued           boolean,
  reason           text,
  person_id        uuid,
  channel          password_reset_channel,
  destination_hint text,
  expires_at       timestamptz
)
language plpgsql as $$
declare
  v_cred        record;
  v_person      record;
  v_minutes     smallint;
  v_per_day     smallint;
  v_per_ip_day  smallint;
  v_channel     password_reset_channel;
  v_destination text;
  v_hint        text;
  v_staff_id    uuid;
  v_expires     timestamptz;
  v_count       integer;
begin
  issued := false;
  reason := null;
  person_id := null;
  channel := null;
  destination_hint := null;
  expires_at := null;

  select coalesce(ap.reset_code_minutes, 30),
         coalesce(ap.max_reset_per_day, 3),
         coalesce(ap.max_reset_per_ip_day, 15)
    into v_minutes, v_per_day, v_per_ip_day
    from auth_policy ap where ap.institution_id = p_institution_id;

  -- สถานศึกษาที่ยังไม่ได้ตั้งนโยบายใช้ค่าเริ่มต้นที่ปลอดภัย ไม่ใช่ปล่อยผ่าน
  v_minutes    := coalesce(v_minutes, 30);
  v_per_day    := coalesce(v_per_day, 3);
  v_per_ip_day := coalesce(v_per_ip_day, 15);

  -- ── เพดานรายไอพี ต้องตรวจก่อนแตะบัญชีใด ๆ ────────────────────
  --
  -- ตรวจก่อนค้นหาบัญชีโดยเจตนา เพราะการยิงขอรีเซ็ตรัว ๆ ให้คนทั้งวิทยาลัย
  -- ทำให้ค่า SMS บานปลายและกล่องข้อความของผู้ใช้เต็ม โดยที่โควตารายคน
  -- กันไม่ได้เลย — แต่ละบัญชีถูกขอแค่ครั้งเดียว หลักเดียวกับ 0021
  --
  -- ─── ทำไมยกเว้นช่องทางเคาน์เตอร์ ───
  -- คำขอของงานทะเบียนออกจากเครื่องเดียวกันทั้งวัน ช่วงเปิดเทอมวันเดียว
  -- อาจเป็นร้อยราย ถ้านับรวมด้วย เคาน์เตอร์จะตันตั้งแต่สายและเจ้าหน้าที่
  -- จะกลับไปใช้วิธีตั้งรหัสผ่านให้เองซึ่งเป็นสิ่งที่ไฟล์นี้ต้องการเลิก
  -- ที่สำคัญคือช่องทางนี้มีมนุษย์ยืนยันตัวตนทุกครั้งและมีชื่อกำกับอยู่แล้ว
  if p_ip_hash is not null and coalesce(p_channel, 'email') <> 'staff_counter' then
    select count(*) into v_count
      from password_reset pr
     where pr.institution_id    = p_institution_id
       and pr.requested_ip_hash = p_ip_hash
       and pr.created_at > now() - interval '1 day';

    if v_count >= v_per_ip_day then
      reason := 'ขอรีเซ็ตจากที่อยู่นี้บ่อยเกินกำหนด';
      return next;
      return;
    end if;
  end if;

  select uc.id, uc.person_id, uc.disabled_at
    into v_cred
    from user_credential uc
   where uc.institution_id = p_institution_id
     and uc.username       = p_username;

  if v_cred is null then
    reason := 'ไม่พบรหัสประจำตัว';
    return next;
    return;
  end if;

  if v_cred.disabled_at is not null then
    -- บัญชีที่ถูกระงับต้องกู้คืนโดยเจ้าหน้าที่เท่านั้น การรีเซ็ตรหัสผ่าน
    -- ไม่ควรเป็นทางลัดที่ทำให้บัญชีซึ่งถูกสั่งระงับกลับมาใช้ได้เอง
    person_id := v_cred.person_id;
    reason := 'บัญชีถูกระงับ';
    return next;
    return;
  end if;

  -- ── เพดานรายบัญชี ────────────────────────────────────────────
  --
  -- ยกเว้นช่องทางเคาน์เตอร์ด้วยเหตุผลเดียวกับเพดานรายไอพี บวกอีกข้อ —
  -- คนที่มาถึงเคาน์เตอร์แล้วกรอกรหัสผิดจนถูกยกเลิก ทำกระดาษหาย แล้วมาใหม่
  -- จะติดเพดานตั้งแต่ครั้งที่สี่และไม่มีทางออกเลยจนกว่าจะพ้นยี่สิบสี่ชั่วโมง
  -- ซึ่งแย่กว่าความเสี่ยงที่เพดานนี้กันได้ เพราะทุกใบมีชื่อเจ้าหน้าที่กำกับอยู่แล้ว
  if p_channel is distinct from 'staff_counter' then
    select count(*) into v_count
      from password_reset pr
     where pr.person_id = v_cred.person_id
       and pr.created_at > now() - interval '1 day';

    if v_count >= v_per_day then
      person_id := v_cred.person_id;
      reason := 'ขอรีเซ็ตบัญชีนี้บ่อยเกินกำหนด';
      return next;
      return;
    end if;
  end if;

  -- ── เลือกช่องทางส่ง ──────────────────────────────────────────
  select p.email, p.phone into v_person
    from person p where p.id = v_cred.person_id;

  if p_channel = 'staff_counter' then
    select st.id into v_staff_id
      from staff st
     where st.person_id     = p_issued_by
       and st.institution_id = p_institution_id
       and st.active;

    if v_staff_id is null then
      person_id := v_cred.person_id;
      reason := 'ผู้ออกรหัสไม่ใช่บุคลากรที่ยังปฏิบัติงานอยู่';
      return next;
      return;
    end if;
    v_channel := 'staff_counter';
    v_hint := null;
  else
    -- ผู้ใช้กดขอเอง — ใช้ช่องทางที่ระบุ ถ้าไม่ระบุให้เลือกอีเมลก่อน
    -- เพราะส่งฟรีและมีร่องรอยให้ผู้ใช้ตรวจย้อนหลังได้ ต่างจาก SMS
    v_channel := coalesce(
      p_channel,
      case when nullif(trim(coalesce(v_person.email, '')), '') is not null then 'email'::password_reset_channel
           when nullif(trim(coalesce(v_person.phone, '')), '') is not null then 'sms'::password_reset_channel
      end
    );

    v_destination := case v_channel
                       when 'email' then nullif(trim(coalesce(v_person.email, '')), '')
                       when 'sms'   then nullif(trim(coalesce(v_person.phone, '')), '')
                     end;

    if v_destination is null then
      -- ไม่มีช่องทางติดต่อที่บันทึกไว้ — ต้องไปที่งานทะเบียน
      -- ตอบตามความจริงตรงนี้ แต่ชั้น API จะกลบเป็นข้อความกลางก่อนส่งออก
      person_id := v_cred.person_id;
      reason := 'ไม่มีช่องทางติดต่อที่บันทึกไว้';
      return next;
      return;
    end if;

    v_hint := mask_destination(v_destination, v_channel);
  end if;

  -- ── เพิกถอนรหัสเดิมที่ยังค้างอยู่ ─────────────────────────────
  --
  -- ต้องเหลือรหัสที่ใช้ได้ครั้งละหนึ่งใบเท่านั้น ถ้าปล่อยให้ค้างหลายใบ
  -- ผู้โจมตีที่กดขอซ้ำ ๆ จะได้พื้นที่เดาเพิ่มเป็นเท่าตัวตามจำนวนใบ
  -- ทั้งที่ตัวนับจำนวนครั้งของแต่ละใบยังไม่ถูกแตะเลย
  update password_reset pr
     set revoked_at = now(),
         revoke_reason = 'ออกรหัสใหม่ทับ'
   where pr.person_id   = v_cred.person_id
     and pr.consumed_at is null
     and pr.revoked_at  is null;

  v_expires := now() + make_interval(mins => v_minutes);

  insert into password_reset
    (institution_id, person_id, credential_id, token_hash, channel,
     destination_hint, issued_by, requested_ip_hash, expires_at)
  values
    (p_institution_id, v_cred.person_id, v_cred.id, p_token_hash, v_channel,
     v_hint, v_staff_id, p_ip_hash, v_expires);

  issued := true;
  person_id := v_cred.person_id;
  channel := v_channel;
  destination_hint := v_hint;
  expires_at := v_expires;
  return next;
end $$;

comment on function request_password_reset(uuid, text, password_reset_channel, bytea, bytea, uuid) is
  'ออกรหัสรีเซ็ตหนึ่งใบ เพิกถอนใบเดิมที่ค้างอยู่ — คืนเหตุผลแทนการ raise เพราะโควตาและบันทึกต้องติดถาวรแม้คำขอจะถูกปฏิเสธ';

-- ───────────────────────────────────────────────────────────────────
-- ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่
--
-- ค้นแถวจาก "รหัสประจำตัว" ก่อน แล้วค่อยเทียบค่าแฮช ไม่ใช่ค้นจากค่าแฮช
-- ตรง ๆ เพราะการค้นจากค่าแฮชทำให้รหัสที่กรอกผิดไม่ตรงกับแถวใด จึงไม่มี
-- แถวไหนให้เพิ่มตัวนับ ผลคือเดารหัสแปดตัวได้ไม่จำกัดครั้งจนกว่าจะหมดอายุ
--
-- must_change ตั้งเป็น false เพราะรหัสผ่านที่ได้มาเจ้าตัวเป็นคนพิมพ์เอง
-- ไม่มีใครอื่นรู้ ต่างจากรหัสชั่วคราวที่เจ้าหน้าที่ออกให้ซึ่งต้องบังคับเปลี่ยน
-- ───────────────────────────────────────────────────────────────────
create or replace function consume_password_reset(
  p_institution_id uuid,
  p_username       text,
  p_token_hash     bytea,
  p_new_hash       text
) returns table (
  ok            boolean,
  reason        text,
  person_id     uuid,
  attempts_left integer
)
language plpgsql as $$
declare
  v_cred     record;
  v_reset    record;
  v_max      smallint;
  v_attempts smallint;
begin
  ok := false;
  reason := null;
  person_id := null;
  attempts_left := 0;

  select coalesce(ap.reset_code_attempts, 5) into v_max
    from auth_policy ap where ap.institution_id = p_institution_id;
  v_max := coalesce(v_max, 5);

  select uc.id, uc.person_id, uc.disabled_at
    into v_cred
    from user_credential uc
   where uc.institution_id = p_institution_id
     and uc.username       = p_username;

  if v_cred is null or v_cred.disabled_at is not null then
    reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    return next;
    return;
  end if;

  select pr.id, pr.token_hash, pr.attempts, pr.expires_at
    into v_reset
    from password_reset pr
   where pr.person_id   = v_cred.person_id
     and pr.consumed_at is null
     and pr.revoked_at  is null
   order by pr.created_at desc
   limit 1;

  if v_reset is null then
    reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    return next;
    return;
  end if;

  if v_reset.expires_at <= now() then
    -- เพิกถอนทิ้งเลย เพื่อไม่ให้แถวที่หมดอายุค้างเป็นเป้าให้เดาต่อ
    -- และเพื่อให้การขอใบใหม่ไม่ต้องรอให้ใบเก่าถูกเก็บกวาด
    update password_reset pr
       set revoked_at = now(), revoke_reason = 'หมดอายุ'
     where pr.id = v_reset.id;
    reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    return next;
    return;
  end if;

  -- ── เพิ่มตัวนับก่อนเทียบเสมอ ─────────────────────────────────
  --
  -- ถ้าเพิ่มหลังเทียบแล้วรีบ return ตัวนับจะขยับเฉพาะตอนเดาถูก
  -- ซึ่งเท่ากับไม่มีตัวนับ
  v_attempts := v_reset.attempts + 1;
  update password_reset pr set attempts = v_attempts where pr.id = v_reset.id;

  if v_reset.token_hash is distinct from p_token_hash then
    if v_attempts >= v_max then
      update password_reset pr
         set revoked_at = now(),
             revoke_reason = 'กรอกรหัสผิดครบจำนวนที่กำหนด'
       where pr.id = v_reset.id;
      reason := 'กรอกรหัสรีเซ็ตผิดหลายครั้ง รหัสนี้ถูกยกเลิกแล้ว ต้องขอใหม่';
    else
      reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    end if;
    attempts_left := greatest(v_max - v_attempts, 0);
    return next;
    return;
  end if;

  -- ── ถูกต้อง ──────────────────────────────────────────────────
  update password_reset pr set consumed_at = now() where pr.id = v_reset.id;

  update user_credential uc
     set password_hash       = p_new_hash,
         must_change         = false,
         failed_attempts     = 0,
         locked_until        = null,   -- คนที่ถูกล็อกเพราะจำรหัสไม่ได้ต้องกลับเข้าได้
         password_changed_at = now()
   where uc.id = v_cred.id;

  -- ตั้งรหัสผ่านใหม่แล้วต้องเตะทุกอุปกรณ์ออก หลักเดียวกับการเปลี่ยนรหัสผ่าน
  -- และสำคัญกว่าด้วย เพราะเหตุผลที่ต้องรีเซ็ตมักคือสงสัยว่าบัญชีถูกยึดไปแล้ว
  update auth_session s
     set revoked_at = now(), revoke_reason = 'รีเซ็ตรหัสผ่าน'
   where s.person_id = v_cred.person_id
     and s.revoked_at is null;

  ok := true;
  person_id := v_cred.person_id;
  attempts_left := v_max;
  return next;
end $$;

comment on function consume_password_reset(uuid, text, bytea, text) is
  'ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่ — ปลดล็อกบัญชี ล้างตัวนับรหัสผิด และเพิกถอนทุก session';

-- ───────────────────────────────────────────────────────────────────
-- ล้างคำขอที่เกินระยะเก็บ — ตั้งเป็นงานประจำวันเหมือน purge_login_attempts
-- ───────────────────────────────────────────────────────────────────
create or replace function purge_password_reset(p_keep_days integer default 90)
returns integer language plpgsql as $$
declare v_n integer;
begin
  if p_keep_days < 90 then
    raise exception 'ระยะเก็บบันทึกคำขอรีเซ็ตรหัสผ่านต่ำกว่า 90 วันไม่ได้ตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26';
  end if;
  delete from password_reset where created_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ตารางนี้อ่อนไหวเท่า user_credential — คนที่อ่านได้จะรู้ว่าบัญชีไหน
-- กำลังมีรหัสรีเซ็ตค้างอยู่ ซึ่งเป็นข้อมูลที่ใช้เลือกเป้าหมายได้โดยตรง
-- ───────────────────────────────────────────────────────────────────
alter table password_reset enable row level security;
alter table password_reset force  row level security;

create policy tenant_isolation on password_reset
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- บทบาท auth ใช้ได้เฉพาะช่วงขอและใช้รหัสรีเซ็ต · งานทะเบียนดูได้เพื่อช่วย
-- ผู้ใช้ที่โทรมาถาม · เจ้าตัวเห็นของตัวเองได้ ตรงกับ credential_scope ของ 0014
create policy reset_scope on password_reset
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

-- ลบได้เฉพาะแถวที่เกินระยะเก็บแล้ว — แม้แต่ admin ก็ลบคำขอของเมื่อวานไม่ได้
--
-- ต้องเขียนเป็นนโยบายไม่ใช่ปล่อยว่าง เพราะ force row level security
-- มีผลกับเจ้าของตารางด้วย ถ้าไม่มีนโยบาย delete เลย purge_password_reset()
-- จะลบไม่ได้สักแถวและตารางจะโตไปเรื่อย ๆ (กับดักเดียวกับ access_log ใน 0022)
create policy reset_purge_aged on password_reset
  as restrictive for delete
  using (created_at < now() - interval '90 days');

-- ───────────────────────────────────────────────────────────────────
-- สิทธิ์ — ต้องให้หลังสร้างตารางใหม่ เพราะ roles.sql รันไปก่อนหน้านี้แล้ว
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on password_reset to app_runtime;
    grant execute on function request_password_reset(uuid, text, password_reset_channel, bytea, bytea, uuid) to app_runtime;
    grant execute on function consume_password_reset(uuid, text, bytea, text) to app_runtime;
    grant execute on function purge_password_reset(integer)                   to app_runtime;
    grant execute on function mask_destination(text, password_reset_channel)  to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0026_registrar_gaps.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0026_registrar_gaps.sql
--
-- ปิดช่องว่างของงานทะเบียนและงานวิชาการที่พบตอนเทียบกับระบบที่วิทยาลัย
-- ใช้งานจริงอยู่ (SISA) สี่เรื่อง ทุกเรื่องเป็นงานที่งานทะเบียนทำทุกภาคเรียน
--
-- ─── 1. ภาคเรียนปรับพื้นฐาน ───
-- term_kind เดิมมีแค่ regular กับ summer ทั้งที่วิทยาลัยอาชีวศึกษารับ
-- นักศึกษาที่จบมาจากคนละสายและคนละสถานศึกษาเข้ามาปนกันในห้องเดียวกัน
-- จึงต้องเปิด "ภาคเรียนปรับพื้นฐาน" ก่อนภาคเรียนที่ 1 เพื่อปรับพื้นให้เท่ากัน
--
-- ระบบนี้มี entry_pathway และ pathway_bridging_course อยู่แล้ว คือรู้ว่า
-- ใครมาจากทางไหนและต้องเรียนปรับพื้นวิชาอะไรบ้าง แต่ **ไม่มีภาคเรียนให้ลง**
-- ผลคือข้อมูลที่ออกแบบไว้ดีแล้วใช้จริงไม่ได้เลย
--
-- ordinal ของภาคเรียนปรับพื้นฐานใช้ 0 เพราะเรียงตาม ordinal แล้วต้องมา
-- ก่อนภาคเรียนที่ 1 ตามลำดับเวลาจริง ไม่ใช่ต่อท้ายเป็นภาคเรียนที่ 4
--
-- ─── 2. รอบเช้า/รอบบ่าย ───
-- วิทยาลัยอาชีวศึกษาเอกชนเปิดหลายรอบในหลักสูตรเดียวกันเป็นเรื่องปกติ
-- คนทำงานกลางวันเรียนรอบบ่ายหรือรอบค่ำ ระบบที่ใช้อยู่แยกเป็นหลักสูตร
-- คนละตัวไปเลย ("การบัญชี (ปวช.) - รอบเช้า" กับ "- รอบบ่าย")
--
-- ของเราพอจะใส่คำว่ารอบไว้ในชื่อ curriculum ได้เหมือนกัน แต่ชื่อที่เป็น
-- ข้อความเปล่า ๆ ทำให้ **นับแยกรอบไม่ได้ กรองตารางสอนตามรอบไม่ได้ และ
-- ตั้งค่าเทอมแยกรอบไม่ได้** ทั้งที่สามอย่างนี้คืองานประจำของงานทะเบียน
-- จึงยกขึ้นมาเป็นคอลัมน์ที่ query ได้
--
-- วางไว้ที่ curriculum ไม่ใช่ class_section เพราะรอบเป็นคุณสมบัติของ
-- หลักสูตรที่นักศึกษาสังกัด ไม่ใช่ของห้องเรียนรายวิชา — class_section
-- ชี้ไป curriculum_version อยู่แล้ว จึงหารอบได้ด้วยการ join ไม่ต้องเก็บซ้ำ
-- (เก็บซ้ำสองที่แล้วไม่ตรงกันคือปัญหาที่แก้ยากกว่าการ join)
--
-- ─── 3. ลงทะเบียนทั้งห้อง ───
-- register_courses() รับนักศึกษาทีละคน ซึ่งใช้ไม่ได้จริงกับวิทยาลัยที่มี
-- นักศึกษาสองพันคน งานทะเบียนลงทะเบียนเป็น "ทั้งห้อง" ไม่ใช่ทีละคน
--
-- ข้อสำคัญคือฟังก์ชันนี้ **ห้าม raise เมื่อมีคนติดเงื่อนไข** เพราะการ raise
-- จะ rollback ทั้ง transaction ผลคือคนที่ผ่านเงื่อนไขอีกสามสิบเก้าคนไม่ได้
-- ลงทะเบียนไปด้วย เพียงเพราะมีคนหนึ่งค้างค่าเทอม — งานทะเบียนจะติดตาย
-- ทั้งห้องโดยแก้อะไรไม่ได้จนกว่าคนนั้นจะไปจ่ายเงิน
--
-- จึงคืน "ผลรายคน" ออกมาแทน ใครผ่านลงให้เลย ใครติดบอกว่าติดอะไร
-- หลักเดียวกับ check_registration() ที่คืนรายการปัญหาแทน true/false
-- และหลักเดียวกับ login_rate_status() ที่คืนสถานะให้ชั้น API ตัดสินใจเอง
--
-- ─── 4. รายงานคุมงานของงานทะเบียน ───
-- ข้อมูลสองชุดนี้มีอยู่ในฐานข้อมูลครบแล้ว แต่ไม่มีใครรวมให้ดู
--
--   grade_cutoff_progress()  ครูคนไหนยังไม่ส่งเกรดกี่วิชา — เปิดดูก่อนถึง
--                            กำหนดส่งเกรดทุกครั้ง ไม่มีตัวนี้ก็ต้องไล่ถาม
--                            ทีละคนซึ่งไม่มีใครทำจริง แล้วไปรู้ตอนเลยกำหนด
--   registration_progress()  หลักสูตรไหนลงทะเบียนไปแล้วกี่เปอร์เซ็นต์ —
--                            ใช้จับห้องที่ตกหล่นก่อนหมดเวลาเพิ่ม-ถอน
--
-- ทั้งคู่ **ไม่ใช่ security definer** โดยตั้งใจ ต้องถูก RLS กรองตามสิทธิ์
-- ของคนเรียกเหมือนการอ่านตารางตรง ๆ มิฉะนั้นรายงานจะกลายเป็นทางลัด
-- ที่เห็นข้อมูลข้ามวิทยาลัยได้
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- 1. ภาคเรียนปรับพื้นฐาน
-- ───────────────────────────────────────────────────────────────────

-- หมายเหตุ: ห้ามอ้างถึงค่า 'bridging' ที่เพิ่งเพิ่มในไฟล์นี้อีก
-- PostgreSQL ปฏิเสธการใช้ค่า enum ใหม่ใน transaction เดียวกับที่เพิ่มมัน
-- ("unsafe use of new value of enum type") จึงเขียนกฎที่อ้างค่านี้ไม่ได้
-- จนกว่าจะ commit — เงื่อนไข ordinal ข้างล่างจึงคุมด้วยช่วงตัวเลขล้วน
alter type term_kind add value if not exists 'bridging';

alter table term drop constraint if exists term_ordinal_check;
alter table term add constraint term_ordinal_check check (ordinal between 0 and 3);

comment on column term.ordinal is
  '0 = ภาคเรียนปรับพื้นฐาน (มาก่อนภาคเรียนที่ 1) · 1-2 = ภาคเรียนปกติ · 3 = ภาคฤดูร้อน';

-- ───────────────────────────────────────────────────────────────────
-- 2. รอบเรียน
-- ───────────────────────────────────────────────────────────────────
create type class_shift as enum ('morning', 'afternoon', 'evening', 'weekend');

comment on type class_shift is
  'รอบเรียนของหลักสูตร — เช้า บ่าย ค่ำ และรอบวันหยุด (เรียนเสาร์-อาทิตย์)';

-- ค่าเริ่มต้นเป็นรอบเช้าเพราะหลักสูตรที่มีอยู่ก่อน migration นี้เป็นรอบเช้า
-- ทั้งหมด และเพราะการปล่อยให้เป็น null จะทำให้หลักสูตรหายไปจากรายงาน
-- ที่นับแยกรอบโดยไม่มีใครสังเกต — ค่าที่ผิดแต่มองเห็นแก้ได้ ค่าที่หายเงียบแก้ไม่ได้
alter table curriculum add column if not exists shift class_shift not null default 'morning';

comment on column curriculum.shift is
  'รอบเรียน — นักศึกษาสังกัดรอบผ่านหลักสูตร ส่วน class_section หารอบได้โดย join ผ่าน curriculum_version';

create index if not exists curriculum_shift_idx on curriculum (institution_id, shift);

-- ───────────────────────────────────────────────────────────────────
-- 3. ลงทะเบียนเป็นกลุ่ม
--
-- คืนหนึ่งแถวต่อนักศึกษาหนึ่งคนเสมอ แม้คนนั้นจะลงไม่ได้ เพื่อให้หน้าจอ
-- แสดงได้ว่าใครผ่านใครไม่ผ่านโดยไม่ต้องเรียกซ้ำอีกรอบ
-- ───────────────────────────────────────────────────────────────────
create or replace function register_courses_bulk(
  p_student_ids uuid[],
  p_term_id     uuid,
  p_section_ids uuid[]
) returns table (
  student_id uuid,
  registered integer,
  blockers   text
) language plpgsql as $$
-- ชื่อคอลัมน์ที่คืนออกไป (student_id) ซ้ำกับชื่อคอลัมน์ใน enrollment
-- plpgsql จึงไม่รู้ว่า on conflict (student_id, ...) หมายถึงตัวแปรหรือคอลัมน์
-- แล้วล้มด้วย "column reference is ambiguous" — สั่งให้ตีความเป็นคอลัมน์เสมอ
-- และคืนค่าด้วย return query แทนการกำหนดค่าให้ตัวแปร OUT ทีละตัว
#variable_conflict use_column
declare
  v_student  uuid;
  v_blockers text;
  v_count    integer;
begin
  foreach v_student in array coalesce(p_student_ids, '{}'::uuid[]) loop
    select string_agg(format('[%s] %s', code, message_th), E'\n')
      into v_blockers
    from check_registration(v_student, p_term_id, p_section_ids)
    where severity = 'block' and not waived;

    if v_blockers is not null then
      -- ไม่ raise โดยตั้งใจ — คนที่เหลือในห้องต้องลงทะเบียนได้ต่อ
      return query select v_student, 0, v_blockers;
      continue;
    end if;

    insert into enrollment (student_id, class_section_id, term_id, attempt_no, registered_by)
    select v_student, cs.id, p_term_id,
           1 + (select count(*)
                from enrollment e
                join class_section cs2 on cs2.id = e.class_section_id
                where e.student_id = v_student
                  and cs2.course_id = cs.course_id
                  and e.status in ('enrolled', 'withdrawn')),
           current_actor_id()
    from unnest(coalesce(p_section_ids, '{}'::uuid[])) sid
    join class_section cs on cs.id = sid
    on conflict (student_id, class_section_id) do nothing;

    get diagnostics v_count = row_count;

    return query select v_student, v_count, null::text;
  end loop;
end $$;

comment on function register_courses_bulk(uuid[], uuid, uuid[]) is
  'ลงทะเบียนหลายคนพร้อมกัน คืนผลรายคน — คนที่ติดเงื่อนไขไม่ทำให้คนอื่นในกลุ่มล้มไปด้วย';

-- ───────────────────────────────────────────────────────────────────
-- 4ก. ความคืบหน้าการตัดเกรดรายครู
--
-- นับจากห้องเรียนรายวิชาที่ครูคนนั้นเป็นผู้สอนในภาคเรียนที่ระบุ
-- "ส่งแล้ว" หมายถึงผ่านมือครูไปแล้ว — draft และ returned ยังไม่นับ
-- เพราะ returned คือถูกตีกลับมาให้แก้ ซึ่งงานยังอยู่ที่ครูคนเดิม
-- ───────────────────────────────────────────────────────────────────
create or replace function grade_cutoff_progress(p_term_id uuid)
returns table (
  teacher_id     uuid,
  teacher_name   text,
  sections_total integer,
  submitted      integer,
  remaining      integer,
  grade_due_on   date,
  is_overdue     boolean
) language sql stable as $$
  select
    cs.teacher_id,
    -- coalesce ทุกชิ้น เพราะต่อสตริงกับ null ได้ null ทั้งก้อน
    trim(coalesce(p.first_name_th, '') || ' ' || coalesce(p.last_name_th, '')) as teacher_name,
    count(*)::integer,
    count(*) filter (
      where gs.stage is not null and gs.stage not in ('draft', 'returned')
    )::integer,
    count(*) filter (
      where gs.stage is null or gs.stage in ('draft', 'returned')
    )::integer,
    t.grade_due_on,
    (t.grade_due_on is not null
     and current_date > t.grade_due_on
     and count(*) filter (
           where gs.stage is null or gs.stage in ('draft', 'returned')
         ) > 0)
  from class_section cs
  join term t on t.id = cs.term_id
  left join grade_submission gs on gs.class_section_id = cs.id
  left join staff  st on st.id = cs.teacher_id
  left join person p  on p.id  = st.person_id
  where cs.term_id = p_term_id
    and cs.teacher_id is not null
  group by cs.teacher_id, p.first_name_th, p.last_name_th, t.grade_due_on
  order by 5 desc, 2;
$$;

comment on function grade_cutoff_progress(uuid) is
  'ครูแต่ละคนสอนกี่ห้อง ส่งเกรดแล้วกี่ห้อง เหลือกี่ห้อง — งานทะเบียนใช้ไล่ตามก่อนถึงกำหนดส่ง';

-- ───────────────────────────────────────────────────────────────────
-- 4ข. ความคืบหน้าการลงทะเบียนรายหลักสูตร
--
-- ตัวหารคือนักศึกษาที่ยัง active และสังกัดหลักสูตรนั้นอยู่ ณ วันที่เรียก
-- ไม่ใช่ทุกคนที่เคยสังกัด — มิฉะนั้นคนที่ลาออกไปแล้วจะทำให้ทุกหลักสูตร
-- ค้างอยู่ที่เก้าสิบกว่าเปอร์เซ็นต์ตลอดกาลและรายงานจะไร้ประโยชน์
-- ───────────────────────────────────────────────────────────────────
create or replace function registration_progress(p_term_id uuid)
returns table (
  curriculum_id      uuid,
  curriculum_name    text,
  shift              class_shift,
  students_total     integer,
  students_registered integer,
  pct                numeric(5,2)
) language sql stable as $$
  with roster as (
    select c.id as curriculum_id, c.name_th, c.shift, s.id as student_id
    from student_curriculum sc
    join curriculum_version cv on cv.id = sc.curriculum_version_id
    join curriculum c          on c.id  = cv.curriculum_id
    join student s             on s.id  = sc.student_id
    where s.status = 'active'
      and (sc.effective_to is null or sc.effective_to >= current_date)
  ),
  registered as (
    select distinct e.student_id
    from enrollment e
    where e.term_id = p_term_id
      and e.status = 'enrolled'
  )
  select
    r.curriculum_id,
    r.name_th,
    r.shift,
    count(*)::integer,
    count(*) filter (where reg.student_id is not null)::integer,
    round(100.0 * count(*) filter (where reg.student_id is not null)
          / nullif(count(*), 0), 2)
  from roster r
  left join registered reg on reg.student_id = r.student_id
  group by r.curriculum_id, r.name_th, r.shift
  order by 6 nulls first, 2;
$$;

comment on function registration_progress(uuid) is
  'แต่ละหลักสูตร (แยกรอบ) ลงทะเบียนไปแล้วกี่เปอร์เซ็นต์ — ใช้จับห้องที่ตกหล่นก่อนหมดเวลาเพิ่ม-ถอน';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0027_documents_and_pvrs.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0027_documents_and_pvrs.sql
--
-- เอกสารของงานทะเบียนและรายงานสำหรับหน่วยงานรัฐ
--
-- ─── ทำไมข้อนี้สำคัญกว่าทุกข้อที่เหลือ ───
-- ระบบนี้จะดีกว่าระบบเดิมของวิทยาลัยแค่ไหนก็ไม่มีความหมาย ถ้าออกระเบียน
-- แสดงผลการเรียนกับใบประกาศนียบัตรไม่ได้ และส่งรายงานให้หน่วยงานรัฐไม่ได้
-- เพราะสองอย่างนี้ไม่ใช่ความสะดวก แต่เป็นระเบียบที่ไม่ทำแล้วผิด
--
-- ─── หลักที่คุมทั้งไฟล์ — เอกสารที่ออกไปแล้วเปลี่ยนไม่ได้ ───
-- เอกสารที่พิมพ์ออกไปแล้วอยู่ในมือคนอื่น ฐานข้อมูลจึงต้องจำ **เนื้อหา ณ
-- เวลาที่ออก** ไม่ใช่วิธีคำนวณเนื้อหา ถ้าเก็บแค่วิธีคำนวณ แล้ววันหนึ่งมีการ
-- แก้เกรดย้อนหลังผ่านคำร้อง หรือแก้ชื่อ-นามสกุล หรือแก้เกณฑ์การจบ
-- การพิมพ์ใบเดิมซ้ำจะได้เอกสารที่ **ไม่ตรงกับใบที่เคยออกไป** โดยไม่มีใคร
-- รู้ตัว ซึ่งกับเอกสารทางราชการแปลว่ามีเอกสารสองใบที่เลขที่เดียวกันแต่
-- เนื้อหาต่างกันลอยอยู่ในโลก
--
-- issued_document.payload จึงเก็บเนื้อหาทั้งใบเป็น jsonb และแถวแก้ไม่ได้
-- หลักเดียวกับ enrollment_result (0006) และ grade_ledger — ยกเลิกได้
-- แต่แก้ทับไม่ได้ เพราะการยกเลิกทิ้งร่องรอยไว้ ส่วนการแก้ทับลบร่องรอย
--
-- ─── ทำไมเลขที่เอกสารต้องมาจากตารางแยก ───
-- เลขที่ใบประกาศนียบัตรและเลขที่ระเบียนแสดงผลการเรียนเป็นเลขทางราชการ
-- ซ้ำกันสองใบไม่ได้ และข้ามเลขโดยไม่มีคำอธิบายก็ไม่ได้ การให้ชั้นแอป
-- คิดเลขถัดไปเองด้วยการ select max()+1 จะชนกันทันทีที่มีเจ้าหน้าที่สองคน
-- กดพร้อมกัน — document_series จึงจ่ายเลขด้วยการ update ที่ล็อกแถวไว้
--
-- ─── ทำไมบังคับว่าเลขที่ใบประกาศนียบัตรเป็นตัวเลขล้วน ───
-- เป็นข้อบังคับตามระเบียบกระทรวง ระบบที่วิทยาลัยใช้อยู่เขียนเตือนไว้ข้างช่อง
-- กรอกว่า "ตามระเบียบกระทรวงต้องเป็นตัวเลขเท่านั้น" ซึ่งเป็นการเตือนที่
-- ข้ามได้ทุกทางที่ไม่ผ่านหน้าจอนั้น กฎแบบนี้จึงต้องอยู่ในฐานข้อมูล
--
-- ─── ทำไมการอนุมัติจบเป็น "ชุด" ไม่ใช่รายคน ───
-- คณะกรรมการวิทยาลัยอนุมัติผู้สำเร็จการศึกษาเป็นมติในวันหนึ่ง ครอบคลุม
-- คนจำนวนหนึ่งพร้อมกัน วันที่อนุมัติจึงเป็นคุณสมบัติของมติ ไม่ใช่ของนักศึกษา
-- ถ้าเก็บวันที่อนุมัติไว้บนตัวนักศึกษาแต่ละคน จะไม่มีทางตอบได้ว่ามติวันนั้น
-- ครอบคลุมใครบ้าง ซึ่งเป็นคำถามแรกที่ถูกถามเวลามีคนมาขอตรวจสอบ
--
-- ─── ขอบเขตที่ยังไม่ครอบคลุม (อ่านก่อนใช้กับข้อมูลจริง) ───
-- ฟังก์ชัน pvrs_rows() ในไฟล์นี้ประกอบ **ข้อมูล** ครบตามช่องที่ระบบเดิม
-- ของวิทยาลัยเก็บไว้ แต่ **รูปแบบไฟล์จริงที่ สอศ. รับ** (ลำดับคอลัมน์
-- ตัวคั่น รหัสอักขระ ชื่อไฟล์) ยังไม่ได้ยืนยันกับสเปกฉบับจริง ต้องเทียบ
-- กับไฟล์ที่วิทยาลัยเคยส่งสำเร็จก่อนใช้งานจริงเสมอ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ประเภทเอกสาร
-- ───────────────────────────────────────────────────────────────────
create type document_kind as enum (
  'transcript',    -- ระเบียนแสดงผลการเรียน (รบ.)
  'certificate',   -- ใบประกาศนียบัตร
  'certification', -- ใบรับรอง (กำลังศึกษา / สำเร็จการศึกษา)
  'grade_report'   -- ใบแจ้งผลการเรียนรายภาค (สมุดพก)
);

comment on type document_kind is
  'ประเภทเอกสารที่งานทะเบียนออกให้ — แต่ละประเภทมีสายเลขที่ของตัวเองแยกกัน';

-- ───────────────────────────────────────────────────────────────────
-- สายเลขที่เอกสาร
-- ───────────────────────────────────────────────────────────────────
create table document_series (
  institution_id uuid          not null references institution on delete restrict,
  kind           document_kind not null,
  year_be        smallint      not null check (year_be between 2500 and 2700),
  prefix         text          not null default '',
  next_no        integer       not null default 1 check (next_no > 0),
  width          smallint      not null default 5 check (width between 1 and 12),
  primary key (institution_id, kind, year_be),

  -- ระเบียบกระทรวงบังคับว่าเลขที่ใบประกาศนียบัตรเป็นตัวเลขเท่านั้น
  -- คำนำหน้าที่มีตัวอักษรจึงใช้กับสายนี้ไม่ได้ตั้งแต่ต้นทาง
  constraint certificate_prefix_digits_only
    check (kind <> 'certificate' or prefix ~ '^[0-9]*$')
);

comment on table document_series is
  'ตัวจ่ายเลขที่เอกสารแยกตามสถานศึกษา ประเภท และปีการศึกษา — จ่ายด้วยการล็อกแถว ไม่ใช่ max()+1';
comment on column document_series.next_no is
  'เลขถัดไปที่จะจ่าย ค่าปัจจุบันคือเลขที่ยังไม่ถูกใช้';

-- ───────────────────────────────────────────────────────────────────
-- มติอนุมัติผู้สำเร็จการศึกษา
-- ───────────────────────────────────────────────────────────────────
create table graduation_approval (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  approved_on    date        not null,
  term_id        uuid        references term on delete restrict,
  document_no    text,       -- เลขที่หนังสือหรือมติที่ประชุม
  note           text,
  approved_by    uuid        references person on delete restrict,
  created_at     timestamptz not null default now(),
  unique (institution_id, approved_on, document_no)
);

comment on table graduation_approval is
  'มติอนุมัติผู้สำเร็จการศึกษาหนึ่งครั้ง ครอบคลุมนักศึกษาหลายคน — วันที่อนุมัติเป็นของมติ ไม่ใช่ของรายคน';

-- ───────────────────────────────────────────────────────────────────
-- ผู้สำเร็จการศึกษารายคน — หนึ่งแถวคือหนึ่งบรรทัดในรายงานส่ง สอศ.
--
-- gpax และหน่วยกิตถูก "ตรึง" ไว้ที่นี่ ไม่อ่านจาก term_summary ตอนพิมพ์
-- เหตุผลเดียวกับ enrollment_result.attendance_pct — ถ้ามีการแก้เกรด
-- ย้อนหลังหลังอนุมัติจบไปแล้ว ตัวเลขบนใบที่ออกไปแล้วต้องไม่ขยับตาม
-- ───────────────────────────────────────────────────────────────────
create table student_graduation (
  id                       uuid    primary key default gen_random_uuid(),
  institution_id           uuid    not null references institution on delete restrict,
  student_id               uuid    not null references student on delete restrict,
  approval_id              uuid    not null references graduation_approval on delete restrict,
  curriculum_version_id    uuid    not null references curriculum_version on delete restrict,
  completed_on             date    not null,
  completed_term_id        uuid    references term on delete restrict,
  gpax                     numeric(3,2) not null check (gpax >= 0 and gpax <= 4),
  credits_earned           numeric(5,1) not null check (credits_earned >= 0),
  transcript_no            text,
  certificate_no           text,
  professional_standard_no text,
  note                     text,
  created_at               timestamptz not null default now(),

  unique (student_id, approval_id),

  -- ระเบียบกระทรวง — เลขที่ใบประกาศนียบัตรต้องเป็นตัวเลขล้วน
  constraint certificate_no_digits_only
    check (certificate_no is null or certificate_no ~ '^[0-9]+$')
);

-- เลขทางราชการซ้ำกันสองใบไม่ได้ ใช้ดัชนีบางส่วนเพราะช่องนี้ว่างได้
-- ระหว่างที่ยังไม่ได้ออกเลขให้
create unique index student_graduation_certificate_no_uniq
  on student_graduation (institution_id, certificate_no)
  where certificate_no is not null;

create unique index student_graduation_transcript_no_uniq
  on student_graduation (institution_id, transcript_no)
  where transcript_no is not null;

create index student_graduation_approval_idx on student_graduation (approval_id);
create index student_graduation_student_idx   on student_graduation (student_id);

comment on column student_graduation.gpax is
  'ตรึง ณ เวลาอนุมัติจบ ห้ามอ่านใหม่จาก term_summary ตอนพิมพ์ มิฉะนั้นใบที่ออกซ้ำจะไม่ตรงกับใบเดิม';

-- ───────────────────────────────────────────────────────────────────
-- เอกสารที่ออกไปแล้ว
-- ───────────────────────────────────────────────────────────────────
create table issued_document (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  student_id     uuid          not null references student on delete restrict,
  kind           document_kind not null,
  doc_no         text          not null,
  copy_no        smallint      not null default 1 check (copy_no > 0),
  issued_on      date          not null default current_date,
  issued_by      uuid          references person on delete restrict,
  payload        jsonb         not null,
  void_reason    text,
  voided_at      timestamptz,
  voided_by      uuid          references person on delete restrict,
  created_at     timestamptz   not null default now(),

  unique (institution_id, kind, doc_no, copy_no),

  -- ยกเลิกแล้วต้องมีเหตุผลเสมอ การยกเลิกเงียบ ๆ ตรวจสอบย้อนหลังไม่ได้
  constraint void_needs_reason
    check ((voided_at is null and void_reason is null)
        or (voided_at is not null and void_reason is not null))
);

create index issued_document_student_idx on issued_document (student_id, kind, issued_on desc);

comment on table issued_document is
  'เอกสารที่พิมพ์ออกไปแล้ว เก็บเนื้อหาทั้งใบไว้ใน payload — ออกซ้ำต้องได้ใบเดิมเป๊ะ';
comment on column issued_document.copy_no is
  'ฉบับที่ — การออกซ้ำใช้เลขที่เดิมแต่เพิ่มฉบับที่ เพื่อให้รู้ว่ามีกี่ใบลอยอยู่';
comment on column issued_document.payload is
  'เนื้อหาเอกสาร ณ เวลาที่ออก ไม่คำนวณใหม่ตอนพิมพ์ซ้ำ (หลักเดียวกับ enrollment_result.attendance_pct)';

-- แก้ทับไม่ได้ ยกเว้นการยกเลิก
create or replace function issued_document_immutable() returns trigger
language plpgsql as $$
begin
  if (to_jsonb(new) - 'void_reason' - 'voided_at' - 'voided_by')
     is distinct from
     (to_jsonb(old) - 'void_reason' - 'voided_at' - 'voided_by') then
    raise exception 'เอกสารที่ออกไปแล้วแก้ไม่ได้ ให้ยกเลิกแล้วออกใบใหม่ (เลขที่ %)', old.doc_no;
  end if;

  if old.voided_at is not null and new.voided_at is distinct from old.voided_at then
    raise exception 'เอกสารที่ยกเลิกไปแล้วเปลี่ยนการยกเลิกไม่ได้ (เลขที่ %)', old.doc_no;
  end if;

  return new;
end $$;

create trigger issued_document_no_update before update on issued_document
  for each row execute function issued_document_immutable();

create or replace function issued_document_no_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'เอกสารที่ออกไปแล้วลบไม่ได้ ให้ยกเลิกแทน (เลขที่ %)', old.doc_no;
end $$;

create trigger issued_document_block_delete before delete on issued_document
  for each row execute function issued_document_no_delete();

-- ───────────────────────────────────────────────────────────────────
-- จ่ายเลขที่เอกสาร
--
-- update ... returning ล็อกแถวไว้จนจบ transaction เจ้าหน้าที่สองคนที่กด
-- พร้อมกันจึงได้คนละเลขเสมอ ไม่ใช่เลขเดียวกันแบบที่ select max()+1 จะให้
-- ───────────────────────────────────────────────────────────────────
create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint
) returns text language plpgsql as $$
declare
  v_inst   uuid := current_institution_id();
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  insert into document_series (institution_id, kind, year_be)
  values (v_inst, p_kind, p_year_be)
  on conflict (institution_id, kind, year_be) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = v_inst and kind = p_kind and year_be = p_year_be
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint) is
  'จ่ายเลขที่เอกสารถัดไปแบบกันชนกัน — ล็อกแถวใน document_series ไม่ใช่ select max()+1';

-- ───────────────────────────────────────────────────────────────────
-- เนื้อหาระเบียนแสดงผลการเรียน
--
-- อ่านเฉพาะผลที่เป็นฉบับปัจจุบัน (superseded_by is null) และเฉพาะสัญลักษณ์
-- ที่ระเบียบให้แสดงบนเอกสาร — สัญลักษณ์ชั่วคราวอย่าง ร. หรือ ม.ส. ที่ยัง
-- ไม่ได้แก้ไม่ควรไปโผล่บนใบจริง
-- ───────────────────────────────────────────────────────────────────
create or replace function transcript_data(p_student_id uuid)
returns table (
  year_be        smallint,
  term_ordinal   smallint,
  term_label     text,
  course_code    text,
  course_name_th text,
  credits        numeric(3,1),
  grade_symbol   text,
  grade_point    numeric(2,1),
  credits_earned numeric(3,1),
  category_th    text
) language sql stable as $$
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    c.code,
    c.name_th,
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    cat.name_th
  from enrollment e
  join class_section cs      on cs.id = e.class_section_id
  join course c              on c.id  = cs.course_id
  join term t                on t.id  = e.term_id
  join academic_year ay      on ay.id = t.academic_year_id
  join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym     on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by ay.year_be, t.ordinal, c.code;
$$;

comment on function transcript_data(uuid) is
  'รายวิชาทั้งหมดที่ขึ้นระเบียนแสดงผลการเรียน — ใช้ผลฉบับปัจจุบันและค่าที่ตรึงไว้แล้วเท่านั้น';

-- ───────────────────────────────────────────────────────────────────
-- ออกเอกสารและตรึงเนื้อหา
--
-- คืนแถวใน issued_document ที่เพิ่งสร้าง ชั้น API เอา payload ไปวางลง
-- แม่แบบเพื่อพิมพ์ — การพิมพ์ซ้ำต้องอ่านจาก payload ใบเดิม ไม่ใช่เรียก
-- ฟังก์ชันนี้ใหม่ (เรียกใหม่ = เอกสารคนละใบ คนละเลขที่)
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null
) returns issued_document language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
begin
  -- RLS กันนักศึกษาของวิทยาลัยอื่นไว้แล้ว ตรงนี้กันกรณีรหัสไม่มีอยู่จริง
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;

  v_year := coalesce(
    p_year_be,
    (select max(ay.year_be)
       from student_curriculum sc
       join curriculum_version cv on cv.id = sc.curriculum_version_id
       join academic_year ay on ay.institution_id = v_inst
      where sc.student_id = p_student_id),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year);

  select jsonb_build_object(
    'kind',        p_kind,
    'issued_at',   now(),
    'institution', jsonb_build_object('code', i.code, 'name_th', i.name_th),
    'student',     jsonb_build_object(
                     'student_code', s.student_code,
                     'prefix_th',    coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'birth_date',    p.birth_date,
                     'status',        s.status),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'courses',     coalesce((select jsonb_agg(to_jsonb(td))
                               from transcript_data(p_student_id) td), '[]'::jsonb)
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint) is
  'ออกเอกสารใหม่พร้อมตรึงเนื้อหา — การพิมพ์ซ้ำต้องอ่าน payload ของใบเดิม ไม่ใช่เรียกฟังก์ชันนี้อีกครั้ง';

-- ───────────────────────────────────────────────────────────────────
-- รายงานผู้สำเร็จการศึกษาสำหรับหน่วยงานรัฐ (PVRS)
--
-- ช่องทั้งหมดตรงกับที่ระบบเดิมของวิทยาลัยเก็บ — ดูหมายเหตุเรื่องขอบเขต
-- ที่หัวไฟล์ก่อนนำไปส่งจริง
-- ───────────────────────────────────────────────────────────────────
create or replace function pvrs_rows(p_approval_id uuid)
returns table (
  seq                      bigint,
  student_code             text,
  full_name                text,
  program_name             text,
  qualification            qualification_level,
  completed_on             date,
  completed_term           text,
  exit_reason              text,
  approved_on              date,
  transcript_no            text,
  certificate_no           text,
  professional_standard_no text,
  gpax                     numeric(3,2),
  credits_earned           numeric(5,1),
  note                     text
) language sql stable as $$
  select
    row_number() over (order by s.student_code),
    s.student_code,
    -- coalesce ทุกชิ้น มิฉะนั้นคนที่ไม่มีคำนำหน้าจะได้ชื่อเป็น null ทั้งช่อง
    trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
         || ' ' || coalesce(p.last_name_th, '')),
    pt.name_th || ' - ' || pr.name_th,
    pr.level,
    sg.completed_on,
    case when t.id is null then null
         else 'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be end,
    -- สาเหตุที่ออก อ่านจากประวัติสถานะที่บันทึกไว้ ไม่ใช่เดาจากสถานะปัจจุบัน
    coalesce(
      (select ssh.reason from student_status_history ssh
        where ssh.student_id = s.id and ssh.to_status = 'graduated'
        order by ssh.effective_on desc limit 1),
      'สำเร็จการศึกษาตามหลักสูตร'),
    ga.approved_on,
    sg.transcript_no,
    sg.certificate_no,
    sg.professional_standard_no,
    sg.gpax,
    sg.credits_earned,
    sg.note
  from student_graduation sg
  join graduation_approval ga on ga.id = sg.approval_id
  join student s              on s.id  = sg.student_id
  join person p               on p.id  = s.person_id
  join curriculum_version cv  on cv.id = sg.curriculum_version_id
  join curriculum cur         on cur.id = cv.curriculum_id
  join program_track ptr      on ptr.id = cur.program_track_id
  join program pr             on pr.id  = ptr.program_id
  join program_type pt        on pt.id  = pr.program_type_id
  left join term t            on t.id   = sg.completed_term_id
  left join academic_year ay  on ay.id  = t.academic_year_id
  where sg.approval_id = p_approval_id
  order by s.student_code;
$$;

comment on function pvrs_rows(uuid) is
  'บรรทัดรายงานผู้สำเร็จการศึกษาตามมติหนึ่งครั้ง — ต้องเทียบรูปแบบไฟล์กับสเปก สอศ. ฉบับจริงก่อนส่ง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security ของตารางใหม่ทั้งสี่
--
-- ทุกตารางต้อง force เสมอ ไม่มีข้อยกเว้น (TEST 45b ตรวจทั้งสคีมา)
-- และ RLS ไม่ถ่ายทอดผ่านคีย์นอก ตารางลูกจึงต้องมีนโยบายของตัวเอง
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['document_series', 'graduation_approval',
                           'student_graduation', 'issued_document'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- ชั้นที่ 2 — ขอบเขตตามบทบาท (restrictive จึงถูก AND กับการแยกวิทยาลัย
-- ถ้าเขียนเป็น permissive มันจะไป OR แล้วเปิดข้อมูลข้ามวิทยาลัยทันที)
--
-- นักศึกษาเห็นเอกสารของตัวเองได้ เพื่อให้แอปแสดงว่าเคยออกใบอะไรไปแล้วบ้าง
-- แต่คนอื่นที่ไม่ใช่เจ้าหน้าที่ต้องไม่เห็นของใครเลย
create policy issued_document_scope on issued_document
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from student s
                where s.id = issued_document.student_id
                  and s.person_id = current_actor_id())
  );

-- เลขที่เอกสารและมติอนุมัติเป็นงานของเจ้าหน้าที่เท่านั้น
create policy document_series_scope on document_series
  as restrictive using (is_institution_wide_role());

create policy graduation_approval_scope on graduation_approval
  as restrictive using (is_institution_wide_role());

create policy student_graduation_scope on student_graduation
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from student s
                where s.id = student_graduation.student_id
                  and s.person_id = current_actor_id())
  );

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0028_document_payload_detail.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0028_document_payload_detail.sql
--
-- เติมข้อมูลใน payload ของเอกสารให้ครบเท่าที่หน้ากระดาษต้องแสดง
--
-- ─── ทำไมต้องเติมก่อนทำแม่แบบพิมพ์ ───
-- 0027 เก็บ payload ไว้แค่ข้อมูลนักศึกษากับรายวิชา ซึ่งไม่พอสำหรับระเบียน
-- แสดงผลการเรียนจริง — ยังขาดสาขาวิชา หน่วยกิตสะสม ผลการเรียนเฉลี่ยสะสม
-- และผลการเรียนเฉลี่ยรายภาค
--
-- ถ้าปล่อยให้ตัวเรนเดอร์ไป join เอาเองตอนพิมพ์ หลักการตรึงเนื้อหาทั้งหมด
-- จะพังทันที เพราะครึ่งหนึ่งของกระดาษจะมาจากข้อมูลสด ผลคือใบที่พิมพ์ซ้ำ
-- ปีหน้าจะมีชื่อสาขาวิชาหรือ GPAX ไม่ตรงกับใบเดิม ถ้าระหว่างนั้นมีการ
-- เปลี่ยนชื่อสาขา แก้เกรด หรือคำนวณ term_summary ใหม่ — และจะไม่มีใครรู้
-- เพราะกระดาษสองใบไม่เคยถูกเอามาวางเทียบกัน
--
-- หลักที่ใช้ตัดสินคือ **ทุกตัวอักษรที่ปรากฏบนกระดาษต้องอยู่ใน payload**
--
-- ─── ทำไม gpax มีสองแหล่ง ───
-- คนที่อนุมัติจบแล้วใช้ค่าที่ตรึงไว้ใน student_graduation เสมอ เพราะเป็น
-- ตัวเลขที่คณะกรรมการอนุมัติ ส่วนคนที่ยังเรียนอยู่ (ขอใบรับรองหรือใบแสดงผล
-- ระหว่างเรียน) ยังไม่มีมติอนุมัติ จึงต้องใช้ค่าล่าสุดจาก term_summary
-- payload บอก source ไว้ด้วยเพื่อให้ตรวจสอบย้อนหลังได้ว่าเลขนั้นมาจากไหน
--
-- ─── ทำไมข้อความวุฒิการศึกษาคำนวณในฐานข้อมูล ───
-- "ประกาศนียบัตรวิชาชีพ" กับ "ประกาศนียบัตรวิชาชีพชั้นสูง" เป็นถ้อยคำตาม
-- หลักสูตร ไม่ใช่การจัดรูปแบบ ถ้าให้ตัวเรนเดอร์แปล PVC/PVS เอง วันที่มี
-- ช่องทางพิมพ์ที่สอง (แอป หรือสคริปต์ออกใบย้อนหลัง) จะแปลไม่เหมือนกัน
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null
) returns issued_document language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;

  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  --
  -- กฎนี้อยู่ที่ฐานข้อมูลไม่ใช่ที่ตัวเรนเดอร์ เพราะใบที่ออกไปแล้วมีเลขที่
  -- ทางราชการติดตัวไป การไปพบทีหลังว่าออกให้คนที่ยังไม่จบแก้ไม่ได้แล้ว
  -- ต้องยกเลิกและเสียเลขนั้นทิ้ง — ต้องกันไม่ให้เกิดตั้งแต่แรก
  if p_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;

  -- หลักสูตรที่นักศึกษาสังกัดอยู่ ณ วันนี้ ถ้าเคยย้ายหลักสูตรให้ใช้ฉบับล่าสุด
  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;

  v_year := coalesce(
    p_year_be,
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year);

  select jsonb_build_object(
    'kind',        p_kind,
    'issued_at',   now(),
    'year_be',     v_year,

    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),

    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status),

    -- ─── สาขาวิชาและวุฒิ ───
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),

    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),

    -- ─── สรุปผลการเรียน ───
    -- คนที่อนุมัติจบแล้วใช้ค่าที่คณะกรรมการอนุมัติเสมอ ไม่คำนวณใหม่
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t       on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none')),

    'term_summaries',
                   coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                               from (select ay.year_be, t.ordinal,
                                            'ภาคเรียนที่ ' || t.ordinal
                                              || ' ปีการศึกษา ' || ay.year_be as label,
                                            ts.gpa, ts.gpax, ts.credits_earned
                                       from term_summary ts
                                       join term t           on t.id  = ts.term_id
                                       join academic_year ay on ay.id = t.academic_year_id
                                      where ts.student_id = p_student_id) x),
                            '[]'::jsonb),

    'courses',     coalesce((select jsonb_agg(to_jsonb(td))
                               from transcript_data(p_student_id) td), '[]'::jsonb)
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint) is
  'ออกเอกสารใหม่พร้อมตรึงเนื้อหาทั้งใบ — ทุกตัวอักษรที่ปรากฏบนกระดาษต้องอยู่ใน payload ไม่ใช่ดึงสดตอนพิมพ์';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0029_more_document_kinds.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0029_more_document_kinds.sql
--
-- เอกสารที่เหลือของงานทะเบียน — ใบรับรอง สมุดพก และระเบียนสะสม (ปพ.8)
--
-- ─── ทำไม payload ต้องแยกตามประเภทเอกสาร ไม่ใช่ใส่ทุกอย่างทุกใบ ───
-- ทางที่ง่ายกว่าคือประกอบข้อมูลทุกส่วนใส่ไว้ในทุกใบ แล้วให้แม่แบบหยิบเฉพาะ
-- ส่วนที่ต้องใช้ ซึ่งใช้งานได้และโค้ดสั้นกว่า — แต่ทำไม่ได้ที่นี่
--
-- เพราะ payload คือ **สำเนาถาวรที่ลบไม่ได้** ถ้าใส่ผลคัดกรอง SDQ บันทึก
-- เยี่ยมบ้าน และข้อมูลผู้ปกครองลงไปในระเบียนแสดงผลการเรียนทุกใบ ข้อมูล
-- อ่อนไหวของผู้เยาว์จะถูกคัดลอกไปเก็บถาวรในเอกสารที่ไม่มีเหตุผลต้องใช้มันเลย
-- และลบทิ้งไม่ได้ด้วย (issued_document แก้/ลบไม่ได้ตั้งแต่ 0027)
--
-- นี่คือการเก็บข้อมูลเกินความจำเป็นตาม PDPA มาตรา 22 ซึ่งเป็นความผิดที่
-- ตรวจพบยากมาก เพราะระบบทำงานถูกต้องทุกประการจากภายนอก แต่ละใบจึงได้
-- เฉพาะส่วนที่หน้ากระดาษของมันต้องแสดงจริง
--
-- ─── ทำไมระเบียนสะสมเก็บแค่ระดับผล ไม่เก็บรายละเอียด ───
-- ปพ.8 ต้องแสดงว่านักศึกษาเคยถูกคัดกรองและอยู่ในกลุ่มไหน ซึ่งพอสำหรับ
-- ครูที่ปรึกษาคนถัดไปใช้ทำงาน ส่วนคำตอบรายข้อของแบบคัดกรองและข้อค้นพบ
-- จากการเยี่ยมบ้านเป็นคนละเรื่อง — อยู่ในระบบให้คนที่มีสิทธิ์เปิดดูได้
-- แต่ไม่ควรถูกพิมพ์ลงกระดาษที่ส่งต่อกันไปเรื่อย ๆ
--
-- ─── ทำไมสมุดพกบังคับว่าต้องระบุภาคเรียน ───
-- สมุดพกคือผลการเรียน "ประจำภาค" การออกโดยไม่ระบุภาคเรียนแล้วให้ระบบเดา
-- ให้เองจะได้ใบที่ดูถูกต้องทุกอย่างแต่เป็นข้อมูลของภาคเรียนที่ผู้ออกไม่ได้ตั้งใจ
-- ซึ่งไปโผล่ในมือผู้ปกครองแล้วแก้ไม่ได้
--
-- ─── หมายเหตุเรื่องค่า enum ใหม่ ───
-- ไฟล์นี้เพิ่ม 'cumulative_record' เข้า document_kind แล้วต้องใช้ค่านั้น
-- ในตัวฟังก์ชันด้วย PostgreSQL ห้ามใช้ค่า enum ใหม่ใน transaction เดียวกับ
-- ที่เพิ่มมัน การเปรียบเทียบจึงทำผ่าน p_kind::text เทียบกับข้อความธรรมดา
-- ซึ่งไม่นับเป็นการอ้างถึงค่า enum (กับดักเดียวกับที่ 0026 เจอกับ 'bridging')
-- ═══════════════════════════════════════════════════════════════════
begin;

alter type document_kind add value if not exists 'cumulative_record';

comment on type document_kind is
  'ประเภทเอกสารที่งานทะเบียนออกให้ — transcript รบ. · certificate ใบประกาศนียบัตร · certification ใบรับรอง · grade_report สมุดพก · cumulative_record ระเบียนสะสม (ปพ.8)';

-- เปลี่ยนลายเซ็นฟังก์ชันเพื่อรับภาคเรียน จึงต้อง drop ก่อน
-- (create or replace เปลี่ยนรายการพารามิเตอร์ไม่ได้ จะกลายเป็นฟังก์ชันคนละตัว
--  แล้วการเรียกแบบสามอาร์กิวเมนต์จะกำกวมทันที)
drop function if exists issue_document(uuid, document_kind, smallint);

create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null,
  p_term_id    uuid     default null
) returns issued_document language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;

  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  if v_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;

  if v_kind = 'grade_report' and p_term_id is null then
    raise exception 'ออกสมุดพกต้องระบุภาคเรียน มิฉะนั้นจะได้ผลการเรียนของภาคที่ไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;

  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;

  v_year := coalesce(
    p_year_be,
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year);

  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
    'issued_at',   now(),
    'year_be',     v_year,
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status),
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t           on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none'))
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  -- ── ระเบียนแสดงผลการเรียน — ต้องมีรายวิชาทั้งหมดและผลรายภาค ───────
  if v_kind in ('transcript', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'term_summaries',
        coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                    from (select ay.year_be, t.ordinal,
                                 'ภาคเรียนที่ ' || t.ordinal
                                   || ' ปีการศึกษา ' || ay.year_be as label,
                                 ts.gpa, ts.gpax, ts.credits_earned
                            from term_summary ts
                            join term t           on t.id  = ts.term_id
                            join academic_year ay on ay.id = t.academic_year_id
                           where ts.student_id = p_student_id) x), '[]'::jsonb),
      'courses',
        coalesce((select jsonb_agg(to_jsonb(td))
                    from transcript_data(p_student_id) td), '[]'::jsonb));
  end if;

  -- ── สมุดพก — ผลการเรียนประจำภาคพร้อมเวลาเรียนและความประพฤติ ───────
  if v_kind = 'grade_report' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
                  'gpa',     ts.gpa,
                  'gpax',    ts.gpax,
                  'credits_earned', ts.credits_earned)
           from term t
           join academic_year ay on ay.id = t.academic_year_id
           left join term_summary ts
                  on ts.term_id = t.id and ts.student_id = p_student_id
          where t.id = p_term_id),

      -- เวลาเรียนมาจาก v_enrollment_attendance ซึ่งเป็นค่าสด ณ เวลาออกใบ
      -- ต่างจากระเบียนแสดงผลการเรียนที่ใช้ attendance_pct ที่ตรึงตอนตัดเกรด
      -- เพราะสมุดพกมักออกกลางภาคตอนที่ยังไม่มีการตัดเกรด
      'term_courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'course_code',   c.code,
                           'course_name_th', c.name_th,
                           'credits',       c.credits,
                           'grade_symbol',  gsym.symbol,
                           'attendance_pct', v.pct_to_date,
                           'attendance_state', v.attendance_state,
                           'absences_left', v.absences_left)
                           order by c.code)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    left join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join enrollment_result er
                           on er.enrollment_id = e.id and er.superseded_by is null
                    left join grade_symbol gsym on gsym.id = er.grade_symbol_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'), '[]'::jsonb),

      'activities',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'sessions_required', cr.sessions_required,
                           'sessions_attended', cr.sessions_attended,
                           'result', cr.result))
                    from cocurricular_result cr
                   where cr.student_id = p_student_id
                     and cr.term_id = p_term_id), '[]'::jsonb));
  end if;

  -- ── ความประพฤติ — สมุดพกและระเบียนสะสมต้องมี ─────────────────────
  --
  -- behavior_record.points เป็นจำนวนบวกเสมอ (check points > 0 ใน 0011)
  -- ทิศทางหักหรือเพิ่มอยู่ที่ behavior_rule.direction ไม่ใช่ที่เครื่องหมาย
  -- ของตัวเลข การรวมยอดโดยดูเครื่องหมายจึงได้คำตอบผิดแบบดูไม่ออก —
  -- "หนีเรียน" จะกลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์อยู่บนกระดาษ
  --
  -- ยอดคงเหลือจึงอ่านจาก v_behavior_balance ซึ่งเป็นสูตรเดียวกับที่ระบบ
  -- เตือนก่อนออกกลางคันใช้ ไม่เขียนสูตรซ้ำที่นี่ให้มีโอกาสไม่ตรงกัน
  if v_kind in ('grade_report', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'behavior',
        (select jsonb_build_object(
                  'starting_points', bp.starting_points,
                  'deducted', coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'deduct'), 0),
                  'awarded',  coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'award'), 0),
                  'current',  (select vb.balance from v_behavior_balance vb
                                where vb.student_id = p_student_id),
                  'warn_below', bp.warn_below,
                  'critical_below', bp.critical_below)
           from behavior_policy bp
          where bp.institution_id = v_inst));
  end if;

  -- ── ระเบียนสะสม (ปพ.8) ────────────────────────────────────────────
  if v_kind = 'cumulative_record' then
    v_payload := v_payload || jsonb_build_object(
      'guardians',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'relation',  sg.relation,
                           'full_name', trim(coalesce(gp.prefix_th, '')
                                          || coalesce(gp.first_name_th, '')
                                          || ' ' || coalesce(gp.last_name_th, '')),
                           'phone',     coalesce(gp.phone, ''),
                           'is_primary', sg.is_primary)
                           order by sg.is_primary desc)
                    from student_guardian sg
                    join person gp on gp.id = sg.person_id
                   where sg.student_id = p_student_id
                     and sg.verified_at is not null), '[]'::jsonb),

      -- เก็บแค่ระดับผลกับวันที่ ไม่เก็บคำตอบรายข้อ (detail) โดยตั้งใจ
      -- ดูเหตุผลที่หัวไฟล์ — เอกสารนี้ลบไม่ได้และถูกส่งต่อกันไปเรื่อย ๆ
      'screenings',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'instrument',  sr.instrument,
                           'assessed_on', sr.assessed_on,
                           'band',        sr.band)
                           order by sr.assessed_on)
                    from screening_result sr
                   where sr.student_id = p_student_id), '[]'::jsonb),

      -- ส่ง direction ไปด้วยเสมอ เพราะ points เป็นบวกทั้งคู่
      -- ถ้าให้แม่แบบเดาเครื่องหมายเอง ใบจะพิมพ์ว่าหนีเรียนแล้วได้คะแนนเพิ่ม
      'behavior_history',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'occurred_on', br.occurred_on,
                           'points',      br.points,
                           'direction',   brl.direction,
                           'rule_th',     coalesce(brl.name_th, ''),
                           'document_no', coalesce(br.document_no, ''))
                           order by br.occurred_on)
                    from behavior_record br
                    left join behavior_rule brl on brl.id = br.rule_id
                   where br.student_id = p_student_id), '[]'::jsonb),

      'activities_all',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'result',        cr.result,
                           'term_label',    'ภาคเรียนที่ ' || t.ordinal
                                              || '/' || ay.year_be))
                    from cocurricular_result cr
                    join term t           on t.id  = cr.term_id
                    join academic_year ay on ay.id = t.academic_year_id
                   where cr.student_id = p_student_id), '[]'::jsonb),

      -- บันทึกเยี่ยมบ้านมีข้อค้นพบเป็นข้อความอิสระที่อ่อนไหวมาก
      -- ระเบียนสะสมจึงบันทึกแค่ว่า "เคยเยี่ยมกี่ครั้ง ครั้งล่าสุดเมื่อไร"
      'home_visits',
        (select jsonb_build_object(
                  'count', count(*),
                  'last_visited_on', max(hv.visited_on))
           from home_visit hv where hv.student_id = p_student_id));
  end if;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint, uuid) is
  'ออกเอกสารพร้อมตรึงเนื้อหาทั้งใบ — payload มีเฉพาะส่วนที่กระดาษใบนั้นต้องแสดง ไม่ใส่ข้อมูลอ่อนไหวที่ใบนั้นไม่ได้ใช้';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0030_regrade_sessions.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0030_regrade_sessions.sql
--
-- รอบสอบซ่อมและเรียนปรับเกรด
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- ระบบมี enrollment.attempt_no (เรียนซ้ำได้) และ grade_change_request
-- (แก้เกรดได้) อยู่แล้ว แต่ **ไม่มีตัวคุมรอบ** — ไม่มีที่บอกว่ารอบนี้เปิด
-- วิชาไหน ใครมีสิทธิ์เข้า และปิดรับเมื่อไร
--
-- ผลคือทุกอย่างขึ้นกับความจำของเจ้าหน้าที่ ซึ่งพังในสองทางที่เจ็บทั้งคู่ —
-- นักศึกษาที่ไม่มีสิทธิ์เข้าสอบซ่อมได้เพราะไม่มีใครตรวจ และนักศึกษาที่มีสิทธิ์
-- ตกหล่นเพราะไม่มีรายชื่อกลาง กว่าจะรู้ก็จบภาคเรียนไปแล้ว
--
-- ─── ทำไมสิทธิ์เข้าสอบซ่อมต้องคำนวณ ไม่ใช่ให้เจ้าหน้าที่พิมพ์รายชื่อเอง ───
-- คำถามว่า "ใครมีสิทธิ์" มีคำตอบที่ตายตัวอยู่แล้วในข้อมูล — คนที่ลงวิชานี้
-- และผลปัจจุบันยังไม่ได้หน่วยกิต ถ้าให้พิมพ์รายชื่อเอง รายชื่อจะคลาดเคลื่อน
-- ทุกครั้งที่มีการแก้เกรดหลังจากพิมพ์ และไม่มีใครรู้ว่าคลาดเคลื่อน
--
-- regrade_eligible() จึงคำนวณให้ และการลงทะเบียนตรวจซ้ำอีกชั้นตอนเขียนจริง
--
-- ─── ทำไมผลสอบซ่อมไม่เขียนเกรดตรง ๆ ───
-- เกรดในระบบนี้เปลี่ยนได้ทางเดียวคือผ่าน grade_change_request ซึ่งมี
-- dual control (ผู้ยื่นอนุมัติเองไม่ได้) และทิ้ง revision ไว้ให้ตรวจสอบ
-- ถ้าเปิดทางที่สองให้รอบสอบซ่อมเขียนเกรดได้เอง กฎนั้นจะหายไปทันที
-- และจะกลายเป็นช่องที่ใช้แก้เกรดโดยไม่ต้องผ่านใครเลย เพียงแค่สร้าง
-- "รอบสอบซ่อม" ขึ้นมาหนึ่งรอบ
--
-- record_regrade_result() จึงเรียก request_grade_change() ซึ่งเป็นทางเดิม
-- ไม่ได้เขียน enrollment_result เอง
--
-- ─── ทำไมการลงทะเบียนเป็นกลุ่มไม่ raise ───
-- หลักเดียวกับ register_courses_bulk (0026) — คนหนึ่งไม่มีสิทธิ์ต้องไม่ทำให้
-- อีกยี่สิบเก้าคนที่มีสิทธิ์ลงทะเบียนไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;

create type regrade_kind as enum ('retest', 'restudy');
comment on type regrade_kind is
  'retest = สอบซ่อม (สอบใหม่ในวิชาเดิม) · restudy = เรียนปรับเกรด (เรียนซ้ำทั้งวิชา)';

create type regrade_status as enum ('draft', 'open', 'closed');

create type regrade_candidate_status as enum ('registered', 'withdrawn', 'passed', 'failed');

-- ───────────────────────────────────────────────────────────────────
-- รอบสอบซ่อม/เรียนปรับเกรด
-- ───────────────────────────────────────────────────────────────────
create table regrade_session (
  id             uuid           primary key default gen_random_uuid(),
  institution_id uuid           not null references institution on delete restrict,
  term_id        uuid           not null references term on delete restrict,
  code           text           not null,
  name_th        text           not null,
  kind           regrade_kind   not null,
  -- null = เปิดให้ทุกระดับ ส่วนใหญ่วิทยาลัยแยกรอบ ปวช. กับ ปวส.
  level          qualification_level,
  opens_on       date           not null,
  closes_on      date           not null,
  status         regrade_status not null default 'draft',
  note           text,
  created_at     timestamptz    not null default now(),

  unique (institution_id, term_id, code),
  check (closes_on >= opens_on)
);

comment on table regrade_session is
  'รอบสอบซ่อมหรือเรียนปรับเกรดหนึ่งรอบ — คุมว่าเปิดวิชาไหน ใครมีสิทธิ์ และปิดรับเมื่อไร';

create index regrade_session_term_idx on regrade_session (institution_id, term_id, status);

-- ───────────────────────────────────────────────────────────────────
-- รายวิชาที่เปิดในรอบ
-- ───────────────────────────────────────────────────────────────────
create table regrade_session_course (
  id         uuid    primary key default gen_random_uuid(),
  session_id uuid    not null references regrade_session on delete cascade,
  course_id  uuid    not null references course on delete restrict,
  fee_amount numeric(9,2) not null default 0 check (fee_amount >= 0),
  capacity   smallint check (capacity is null or capacity > 0),
  created_at timestamptz not null default now(),
  unique (session_id, course_id)
);

create index regrade_session_course_session_idx on regrade_session_course (session_id);

-- ───────────────────────────────────────────────────────────────────
-- ผู้เข้ารอบ
--
-- source_enrollment_id ชี้กลับไปที่การลงทะเบียนเดิมที่ยังไม่ได้หน่วยกิต
-- เก็บไว้เพราะเวลาบันทึกผลต้องรู้ว่าจะแก้เกรดของการลงทะเบียนครั้งไหน
-- ───────────────────────────────────────────────────────────────────
create table regrade_candidate (
  id                  uuid    primary key default gen_random_uuid(),
  session_course_id   uuid    not null references regrade_session_course on delete cascade,
  student_id          uuid    not null references student on delete restrict,
  source_enrollment_id uuid   not null references enrollment on delete restrict,
  status              regrade_candidate_status not null default 'registered',
  change_request_id   uuid    references grade_change_request on delete restrict,
  registered_at       timestamptz not null default now(),
  registered_by       uuid    references person on delete restrict,
  unique (session_course_id, student_id)
);

create index regrade_candidate_student_idx on regrade_candidate (student_id);

comment on column regrade_candidate.change_request_id is
  'คำร้องแก้เกรดที่เกิดจากผลของรอบนี้ — เกรดจริงเปลี่ยนเมื่อคำร้องผ่านการอนุมัติสองชั้น ไม่ใช่ตอนบันทึกผล';

-- ───────────────────────────────────────────────────────────────────
-- ใครมีสิทธิ์เข้ารอบนี้ในวิชานี้
--
-- เงื่อนไข: เคยลงวิชานี้ และผลฉบับปัจจุบันยังไม่ได้หน่วยกิต และยังไม่เคย
-- ผ่านวิชานี้ในความพยายามครั้งไหนเลย (คนที่เรียนซ้ำแล้วผ่านไม่ต้องซ่อมอีก)
-- ───────────────────────────────────────────────────────────────────
create or replace function regrade_eligible(p_session_course_id uuid)
returns table (
  student_id     uuid,
  student_code   text,
  full_name      text,
  enrollment_id  uuid,
  grade_symbol   text,
  term_label     text
) language sql stable as $$
  with target as (
    select rsc.course_id, rs.level
      from regrade_session_course rsc
      join regrade_session rs on rs.id = rsc.session_id
     where rsc.id = p_session_course_id
  ),
  attempts as (
    select e.id as enrollment_id, e.student_id, cs.course_id,
           gsym.symbol, gsym.earns_credit,
           ay.year_be, t.ordinal
      from enrollment e
      join class_section cs      on cs.id = e.class_section_id
      join term t                on t.id  = e.term_id
      join academic_year ay      on ay.id = t.academic_year_id
      join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
      join grade_symbol gsym     on gsym.id = er.grade_symbol_id
      join target tg             on tg.course_id = cs.course_id
     where e.status = 'enrolled'
  )
  select a.student_id, s.student_code,
         trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
              || ' ' || coalesce(p.last_name_th, '')),
         a.enrollment_id, a.symbol,
         'ภาคเรียนที่ ' || a.ordinal || '/' || a.year_be
    from attempts a
    join student s on s.id = a.student_id
    join person  p on p.id = s.person_id
    join curriculum_version cv
      on cv.id = (select sc.curriculum_version_id from student_curriculum sc
                   where sc.student_id = a.student_id
                   order by sc.effective_from desc nulls last limit 1)
    join curriculum cur    on cur.id = cv.curriculum_id
    join program_track ptr on ptr.id = cur.program_track_id
    join program pr        on pr.id  = ptr.program_id
    cross join target tg
   where not a.earns_credit
     and s.status = 'active'
     and (tg.level is null or pr.level = tg.level)
     -- เคยผ่านวิชานี้แล้วในครั้งไหนก็ตาม = ไม่ต้องซ่อม
     and not exists (select 1 from attempts a2
                      where a2.student_id = a.student_id
                        and a2.course_id  = a.course_id
                        and a2.earns_credit)
   order by s.student_code;
$$;

comment on function regrade_eligible(uuid) is
  'รายชื่อผู้มีสิทธิ์เข้ารอบสอบซ่อมในวิชาหนึ่ง — คำนวณจากผลการเรียนจริง ไม่ใช่รายชื่อที่พิมพ์ไว้';

-- ───────────────────────────────────────────────────────────────────
-- ลงทะเบียนเข้ารอบเป็นกลุ่ม
--
-- คืนผลรายคนเสมอ ไม่ raise — คนที่ไม่มีสิทธิ์ต้องไม่ทำให้ทั้งกลุ่มล้ม
-- ───────────────────────────────────────────────────────────────────
create or replace function register_regrade(
  p_session_course_id uuid,
  p_student_ids       uuid[]
) returns table (
  student_id  uuid,
  registered  boolean,
  reason      text
) language plpgsql as $$
#variable_conflict use_column
declare
  v_student  uuid;
  v_status   regrade_status;
  v_opens    date;
  v_closes   date;
  v_cap      smallint;
  v_taken    integer;
  v_enroll   uuid;
begin
  select rs.status, rs.opens_on, rs.closes_on, rsc.capacity
    into v_status, v_opens, v_closes, v_cap
    from regrade_session_course rsc
    join regrade_session rs on rs.id = rsc.session_id
   where rsc.id = p_session_course_id;

  if v_status is null then
    raise exception 'ไม่พบรายวิชาที่เปิดในรอบนี้';
  end if;

  -- รอบที่ยังไม่เปิดหรือปิดไปแล้วรับคนไม่ได้ — ข้อนี้ raise ได้เพราะเป็น
  -- ปัญหาของทั้งคำขอ ไม่ใช่ของนักศึกษาคนใดคนหนึ่ง
  if v_status <> 'open' then
    raise exception 'รอบนี้ยังไม่เปิดรับหรือปิดรับไปแล้ว (สถานะ %)', v_status
      using errcode = 'check_violation';
  end if;
  if current_date < v_opens or current_date > v_closes then
    raise exception 'อยู่นอกช่วงวันที่รับสมัคร (% ถึง %)', v_opens, v_closes
      using errcode = 'check_violation';
  end if;

  foreach v_student in array coalesce(p_student_ids, '{}'::uuid[]) loop
    -- ตรวจสิทธิ์ซ้ำตอนเขียนจริง ไม่เชื่อรายชื่อที่ส่งมาจากหน้าจอ
    -- เพราะระหว่างที่หน้าจอเปิดค้างไว้ เกรดอาจถูกแก้ไปแล้ว
    select el.enrollment_id into v_enroll
      from regrade_eligible(p_session_course_id) el
     where el.student_id = v_student
     limit 1;

    if v_enroll is null then
      return query select v_student, false,
        'ไม่มีสิทธิ์เข้ารอบนี้ — ไม่พบผลการเรียนที่ยังไม่ได้หน่วยกิตในวิชานี้'::text;
      continue;
    end if;

    if exists (select 1 from regrade_candidate rc
                where rc.session_course_id = p_session_course_id
                  and rc.student_id = v_student) then
      return query select v_student, false, 'ลงทะเบียนในรอบนี้ไปแล้ว'::text;
      continue;
    end if;

    if v_cap is not null then
      select count(*) into v_taken from regrade_candidate rc
       where rc.session_course_id = p_session_course_id
         and rc.status <> 'withdrawn';
      if v_taken >= v_cap then
        return query select v_student, false,
          format('ที่นั่งเต็มแล้ว (รับได้ %s คน)', v_cap)::text;
        continue;
      end if;
    end if;

    insert into regrade_candidate
      (session_course_id, student_id, source_enrollment_id, registered_by)
    values (p_session_course_id, v_student, v_enroll, current_actor_id());

    return query select v_student, true, null::text;
  end loop;
end $$;

comment on function register_regrade(uuid, uuid[]) is
  'ลงทะเบียนเข้ารอบสอบซ่อมเป็นกลุ่ม คืนผลรายคน — คนที่ไม่มีสิทธิ์ไม่ทำให้คนอื่นล้ม';

-- ───────────────────────────────────────────────────────────────────
-- บันทึกผลของรอบ
--
-- ไม่เขียนเกรดเอง แต่ยื่นคำร้องแก้เกรดผ่านทางเดิม ซึ่งมี dual control
-- และทิ้ง revision ไว้ให้ตรวจสอบย้อนหลังได้
-- ───────────────────────────────────────────────────────────────────
create or replace function record_regrade_result(
  p_candidate_id       uuid,
  p_to_grade_symbol_id uuid,
  p_reason             text,
  p_document_no        text default null
) returns uuid language plpgsql as $$
declare
  v_enroll  uuid;
  v_earns   boolean;
  v_req     uuid;
  v_status  regrade_candidate_status;
begin
  select rc.source_enrollment_id, rc.status
    into v_enroll, v_status
    from regrade_candidate rc
   where rc.id = p_candidate_id;

  if v_enroll is null then
    raise exception 'ไม่พบผู้เข้ารอบตามรหัสที่ระบุ';
  end if;
  if v_status <> 'registered' then
    raise exception 'บันทึกผลซ้ำไม่ได้ ผู้เข้ารอบรายนี้มีผลแล้ว (%)', v_status
      using errcode = 'check_violation';
  end if;

  select gsym.earns_credit into v_earns
    from grade_symbol gsym where gsym.id = p_to_grade_symbol_id;

  if v_earns is null then
    raise exception 'ไม่พบสัญลักษณ์ผลการเรียนที่ระบุ';
  end if;

  v_req := request_grade_change(v_enroll, p_to_grade_symbol_id, p_reason, null, p_document_no);

  -- cast เอง เพราะ case ... end คืน text ไม่ใช่ enum
  update regrade_candidate
     set status = (case when v_earns then 'passed' else 'failed' end)::regrade_candidate_status,
         change_request_id = v_req
   where id = p_candidate_id;

  return v_req;
end $$;

comment on function record_regrade_result(uuid, uuid, text, text) is
  'บันทึกผลสอบซ่อมโดยยื่นคำร้องแก้เกรด — เกรดจริงเปลี่ยนเมื่อผ่านการอนุมัติสองชั้น ไม่ใช่ตอนบันทึก';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table regrade_session enable row level security;
alter table regrade_session force  row level security;
create policy tenant_isolation on regrade_session
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- ตารางลูกไม่ได้สืบทอด RLS ผ่านคีย์นอก ต้องมีนโยบายของตัวเอง
alter table regrade_session_course enable row level security;
alter table regrade_session_course force  row level security;
create policy tenant_isolation on regrade_session_course
  using (exists (select 1 from regrade_session rs
                  where rs.id = regrade_session_course.session_id
                    and rs.institution_id = current_institution_id()));

alter table regrade_candidate enable row level security;
alter table regrade_candidate force  row level security;
create policy tenant_isolation on regrade_candidate
  using (exists (select 1 from student s
                  where s.id = regrade_candidate.student_id
                    and s.institution_id = current_institution_id()));

-- ชั้นที่ 2 — นักศึกษาเห็นเฉพาะรายการของตัวเอง (restrictive จึงถูก AND)
create policy regrade_candidate_scope on regrade_candidate
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from student s
                where s.id = regrade_candidate.student_id
                  and s.person_id = current_actor_id())
  );

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0031_class_placement_and_rollover.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0031_class_placement_and_rollover.sql
--
-- ชั้นปี/ห้องเรียนของนักศึกษา และการเลื่อนชั้นปีการศึกษา
--
-- ─── ช่องว่างที่พบตอนเทียบกับระบบที่วิทยาลัยใช้อยู่ ───
-- ระบบนั้นมี "ประเภทวิชา / สาขา / ชั้นเรียน / ห้องเรียน" เป็นข้อมูลหลัก
-- และมีเมนู "จัดห้องเรียน" กับ "เลื่อนชั้นปีการศึกษา" ที่ใช้ทุกปี
--
-- ของเราไม่มี **ชั้นปี** อยู่ที่ไหนเลย — ตาราง student มีแค่ปีที่เข้าศึกษา
-- ส่วนห้องเป็นข้อความอิสระใน class_section.section_no ซึ่งเป็นห้องของ
-- รายวิชา ไม่ใช่ห้องประจำของนักศึกษา
--
-- ที่เจ็บกว่านั้นคือ fee_schedule.study_year มีอยู่แล้วตั้งแต่ 0010 —
-- ระบบการเงินตั้งค่าเทอมตามชั้นปีได้ แต่ **ไม่มีทางรู้ว่านักศึกษาคนไหน
-- อยู่ชั้นปีอะไร** จึงจับคู่ไม่ได้จริง เป็นข้อมูลที่ออกแบบไว้แล้วใช้ไม่ได้
-- แบบเดียวกับ entry_pathway ก่อน 0026
--
-- ─── ทำไมชั้นปีอยู่ในตารางแยกที่ผูกกับปีการศึกษา ───
-- ทางที่ง่ายกว่าคือใส่คอลัมน์ study_year ลงในตาราง student ตรง ๆ แต่ทำ
-- แบบนั้นแล้วจะตอบไม่ได้ว่า "ปีการศึกษา 2568 คนนี้อยู่ชั้นปีอะไร ห้องไหน"
-- ซึ่งเป็นคำถามที่ต้องตอบทุกครั้งที่ออกเอกสารย้อนหลังหรือตรวจสอบข้อมูลเก่า
-- และการเลื่อนชั้นจะกลายเป็นการเขียนทับค่าเดิม ทำให้ประวัติหายไปทุกปี
--
-- ─── ทำไมไม่เก็บหลักสูตรซ้ำในตารางนี้ ───
-- student_curriculum ตอบอยู่แล้วว่านักศึกษาสังกัดหลักสูตรฉบับไหนช่วงไหน
-- ถ้าเก็บซ้ำที่นี่ด้วย วันหนึ่งสองที่จะไม่ตรงกันแล้วไม่มีใครรู้ว่าอันไหนจริง
--
-- ─── ทำไมการเลื่อนชั้นคืนผลรายคน ไม่ raise ───
-- หลักเดียวกับ register_courses_bulk (0026) และ register_regrade (0030) —
-- การเลื่อนชั้นทำกับนักศึกษาทั้งวิทยาลัยพร้อมกัน ถ้ามีคนหนึ่งเรียนเกิน
-- เวลาที่หลักสูตรกำหนดแล้ว raise ทั้งงานจะ rollback แล้วอีกสองพันคน
-- ไม่ได้เลื่อนชั้นไปด้วย งานทะเบียนจะติดตายทั้งวิทยาลัยเพราะคนคนเดียว
--
-- ─── ทำไมไม่สร้างปีการศึกษาปลายทางให้เอง ───
-- ปีการศึกษามีวันเปิด-ปิดและภาคเรียนที่ต้องตัดสินใจ ไม่ใช่ข้อมูลที่คัดลอก
-- มาได้ ถ้าสร้างให้เองด้วยการเดาวันที่ จะได้ปฏิทินที่ผิดโดยไม่มีใครทักท้วง
-- แล้วกำหนดส่งเกรดกับวันสุดท้ายของการถอนรายวิชาจะผิดตามไปทั้งปี
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ชั้นปีและห้องประจำของนักศึกษาในแต่ละปีการศึกษา
-- ───────────────────────────────────────────────────────────────────
create table student_class_placement (
  id               uuid        primary key default gen_random_uuid(),
  institution_id   uuid        not null references institution on delete restrict,
  student_id       uuid        not null references student on delete restrict,
  academic_year_id uuid        not null references academic_year on delete restrict,
  study_year       smallint    not null check (study_year between 1 and 6),
  group_code       text,
  note             text,
  created_at       timestamptz not null default now(),

  -- ปีการศึกษาหนึ่งนักศึกษาคนหนึ่งอยู่ชั้นปีเดียว
  unique (student_id, academic_year_id)
);

comment on table student_class_placement is
  'ชั้นปีและห้องประจำของนักศึกษาในปีการศึกษาหนึ่ง — เก็บแยกรายปีเพื่อให้ตอบย้อนหลังได้ว่าปีนั้นอยู่ชั้นไหน';
comment on column student_class_placement.study_year is
  'ชั้นปี 1-6 · ใช้จับคู่กับ fee_schedule.study_year เพื่อคิดค่าเทอมตามชั้นปี';
comment on column student_class_placement.group_code is
  'ห้องประจำ เช่น 1/1 — ต่างจาก class_section.section_no ซึ่งเป็นห้องของรายวิชา';

create index student_class_placement_year_idx
  on student_class_placement (institution_id, academic_year_id, study_year);
create index student_class_placement_student_idx
  on student_class_placement (student_id);

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการเลื่อนชั้นปีการศึกษา
--
-- ต้องรู้ย้อนหลังได้ว่าใครกดเลื่อนเมื่อไร และผลเป็นอย่างไร เพราะเป็น
-- งานที่ทำปีละครั้งและกระทบทุกคน คนที่มาถามทีหลังว่า "ทำไมคนนี้ไม่ถูก
-- เลื่อนชั้น" ต้องหาคำตอบได้โดยไม่ต้องเดา
-- ───────────────────────────────────────────────────────────────────
create table rollover_log (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  from_year_be   smallint    not null,
  to_year_be     smallint    not null,
  summary        jsonb       not null,
  ran_at         timestamptz not null default now(),
  ran_by         uuid        references person on delete restrict
);

comment on table rollover_log is
  'ประวัติการเลื่อนชั้นปีการศึกษา — ตอบได้ว่าใครกดเมื่อไร เลื่อนไปกี่คน และใครตกหล่นเพราะอะไร';

-- ───────────────────────────────────────────────────────────────────
-- เลื่อนชั้นปีการศึกษา
--
-- คืนหนึ่งแถวต่อนักศึกษาหนึ่งคนเสมอ รวมถึงคนที่ไม่ถูกเลื่อนและเหตุผล
-- ───────────────────────────────────────────────────────────────────
create or replace function rollover_students(
  p_from_year_be smallint,
  p_to_year_be   smallint
) returns table (
  student_id  uuid,
  action      text,
  study_year  smallint,
  note        text
) language plpgsql as $$
#variable_conflict use_column
declare
  v_inst    uuid := current_institution_id();
  v_from_ay uuid;
  v_to_ay   uuid;
  r         record;
  v_next    smallint;
  v_max     smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;
  if p_to_year_be <= p_from_year_be then
    raise exception 'ปีปลายทาง (%) ต้องมากกว่าปีต้นทาง (%)', p_to_year_be, p_from_year_be;
  end if;

  select id into v_from_ay from academic_year
   where institution_id = v_inst and year_be = p_from_year_be;
  select id into v_to_ay   from academic_year
   where institution_id = v_inst and year_be = p_to_year_be;

  if v_from_ay is null then
    raise exception 'ไม่พบปีการศึกษา % ในสถานศึกษานี้', p_from_year_be;
  end if;
  if v_to_ay is null then
    raise exception 'ยังไม่ได้สร้างปีการศึกษา % — ต้องสร้างพร้อมกำหนดวันเปิด-ปิดก่อนจึงจะเลื่อนชั้นได้',
      p_to_year_be;
  end if;

  for r in
    select s.id,
           scp.study_year as current_year,
           -- จำนวนภาคเรียนปกติของหลักสูตร แปลงเป็นจำนวนชั้นปี
           -- (ภาคฤดูร้อนไม่นับเป็นชั้นปี จึงหารสอง)
           coalesce(ceil(cv.normal_duration_terms / 2.0), 3)::smallint as max_year
      from student s
      join student_class_placement scp
        on scp.student_id = s.id and scp.academic_year_id = v_from_ay
      left join lateral (
        select sc.curriculum_version_id
          from student_curriculum sc
         where sc.student_id = s.id
         order by sc.effective_from desc nulls last
         limit 1
      ) cur on true
      left join curriculum_version cv on cv.id = cur.curriculum_version_id
     where s.institution_id = v_inst
     order by s.student_code
  loop
    -- มีที่อยู่ในปีปลายทางแล้ว — ไม่เขียนทับ เพื่อให้กดซ้ำได้โดยไม่เสียหาย
    if exists (select 1 from student_class_placement scp2
                where scp2.student_id = r.id and scp2.academic_year_id = v_to_ay) then
      return query select r.id, 'skipped'::text, r.current_year,
        'มีชั้นปีในปีการศึกษาปลายทางอยู่แล้ว'::text;
      continue;
    end if;

    if exists (select 1 from student_graduation sg where sg.student_id = r.id) then
      return query select r.id, 'graduated'::text, r.current_year,
        'สำเร็จการศึกษาแล้ว ไม่ต้องเลื่อนชั้น'::text;
      continue;
    end if;

    if (select status from student where id = r.id) <> 'active' then
      return query select r.id, 'inactive'::text, r.current_year,
        'สถานะไม่ใช่กำลังศึกษา'::text;
      continue;
    end if;

    v_next := r.current_year + 1;
    v_max  := r.max_year;

    -- เกินเวลาเรียนปกติของหลักสูตร ต้องให้คนตัดสินใจ ไม่ใช่เลื่อนต่อเงียบ ๆ
    if v_next > v_max then
      return query select r.id, 'exceeded'::text, r.current_year,
        format('เกินจำนวนชั้นปีปกติของหลักสูตร (%s ปี) ต้องพิจารณาเป็นรายกรณี', v_max)::text;
      continue;
    end if;

    insert into student_class_placement
      (institution_id, student_id, academic_year_id, study_year)
    values (v_inst, r.id, v_to_ay, v_next);

    return query select r.id, 'promoted'::text, v_next, null::text;
  end loop;
end $$;

comment on function rollover_students(smallint, smallint) is
  'เลื่อนชั้นปีนักศึกษาไปยังปีการศึกษาถัดไป คืนผลรายคน — คนที่เลื่อนไม่ได้ไม่ทำให้ทั้งวิทยาลัยล้ม';

-- ───────────────────────────────────────────────────────────────────
-- คัดลอกรายการชำระเงินตามระดับชั้นไปยังปีการศึกษาถัดไป
--
-- คัดลอกโครงสร้างและจำนวนเงินเดิม ให้งานการเงินไปปรับตัวเลขเอง
-- ดีกว่าให้ตั้งใหม่ทั้งหมดทุกปี ซึ่งเป็นจุดที่พิมพ์ตัวเลขผิดได้ง่ายที่สุด
-- ───────────────────────────────────────────────────────────────────
create or replace function rollover_fee_schedules(
  p_from_year_be smallint,
  p_to_year_be   smallint
) returns integer language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_from_ay uuid;
  v_to_ay   uuid;
  v_count   integer := 0;
begin
  select id into v_from_ay from academic_year
   where institution_id = v_inst and year_be = p_from_year_be;
  select id into v_to_ay   from academic_year
   where institution_id = v_inst and year_be = p_to_year_be;

  if v_from_ay is null or v_to_ay is null then
    raise exception 'ไม่พบปีการศึกษาต้นทางหรือปลายทางในสถานศึกษานี้';
  end if;

  with copied as (
    insert into fee_schedule
      (institution_id, academic_year_id, level, study_year, program_id, active)
    select fs.institution_id, v_to_ay, fs.level, fs.study_year, fs.program_id, false
      from fee_schedule fs
     where fs.institution_id = v_inst
       and fs.academic_year_id = v_from_ay
       -- ไม่คัดลอกทับของที่มีอยู่แล้ว กดซ้ำจึงไม่ทำให้ค่าเทอมซ้อนกัน
       and not exists (
         select 1 from fee_schedule t
          where t.institution_id = v_inst
            and t.academic_year_id = v_to_ay
            and t.level = fs.level
            and t.study_year is not distinct from fs.study_year
            and t.program_id is not distinct from fs.program_id)
    returning id, level, study_year, program_id
  )
  insert into fee_schedule_line (fee_schedule_id, fee_item_id, term_ordinal, amount)
  select c.id, l.fee_item_id, l.term_ordinal, l.amount
    from copied c
    join fee_schedule src
      on src.institution_id = v_inst
     and src.academic_year_id = v_from_ay
     and src.level = c.level
     and src.study_year is not distinct from c.study_year
     and src.program_id is not distinct from c.program_id
    join fee_schedule_line l on l.fee_schedule_id = src.id;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

comment on function rollover_fee_schedules(smallint, smallint) is
  'คัดลอกรายการชำระเงินตามระดับชั้นไปปีถัดไป โดยยังไม่เปิดใช้ (active = false) ให้งานการเงินตรวจตัวเลขก่อน';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table student_class_placement enable row level security;
alter table student_class_placement force  row level security;
create policy tenant_isolation on student_class_placement
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- นักศึกษาเห็นชั้นปีของตัวเองได้ แต่ไม่เห็นรายชื่อทั้งห้องทั้งวิทยาลัย
create policy student_class_placement_scope on student_class_placement
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from student s
                where s.id = student_class_placement.student_id
                  and s.person_id = current_actor_id())
  );

alter table rollover_log enable row level security;
alter table rollover_log force  row level security;
create policy tenant_isolation on rollover_log
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy rollover_log_scope on rollover_log
  as restrictive using (is_institution_wide_role());

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0032_class_grouping_and_gradebook_copy.sql
-- ───────────────────────────────────────────────────────────────────

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


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0033_admissions.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0033_admissions.sql
--
-- งานรับสมัครนักศึกษาใหม่
--
-- ─── ทำไมข้อนี้สำคัญกว่าที่เห็น ───
-- ก่อนไฟล์นี้ นักศึกษาเข้าสู่ระบบได้สองทางเท่านั้น — นำเข้าไฟล์จากระบบเดิม
-- หรือรัน SQL เอง แปลว่าวิทยาลัยที่เริ่มใช้ระบบนี้ตั้งแต่ต้นปีไม่มีทาง
-- รับนักศึกษาใหม่เข้ามาได้เลย ต้องไปใช้ระบบอื่นรับสมัครแล้วค่อยนำเข้า
--
-- ─── ทำไมใบสมัครไม่ใช่ตาราง student ตั้งแต่แรก ───
-- ผู้สมัครส่วนใหญ่ไม่ได้เป็นนักศึกษา การสร้างแถวใน student ตั้งแต่ตอนสมัคร
-- จะทำให้ทุกรายงาน ทุกยอดนับ และทุกไฟล์ส่งหน่วยงานรัฐมีคนที่ไม่ได้เรียน
-- ปนอยู่ และต้องไปเติม "where status = ..." ทุกที่ ซึ่งจะลืมสักที่แน่นอน
--
-- ผู้สมัครจึงอยู่คนละตาราง และ **ข้ามมาเป็นนักศึกษาได้ทางเดียว** คือผ่าน
-- admit_applicant() ซึ่งเป็นจุดเดียวที่สร้าง person + student + หลักสูตร
-- + ชั้นปี พร้อมกันในทรานแซกชันเดียว
--
-- ─── ทำไมกันสมัครซ้ำด้วยเลขบัตรประชาชน ───
-- คนที่สมัครสองใบในรอบเดียวกันจะกินโควตาสองที่นั่ง และถ้าผ่านทั้งคู่จะได้
-- รหัสนักศึกษาสองรหัส ซึ่งแก้ทีหลังยากมากเพราะข้อมูลกระจายไปทั้งระบบแล้ว
-- เก็บเป็นค่าแฮชแบบเดียวกับ person (ดู 0002) จึงกันซ้ำได้โดยไม่ต้องเก็บ
-- เลขจริงไว้แบบอ่านออก
--
-- ─── ทำไมโควตาตรวจตอนประกาศผล ไม่ใช่ตอนสมัคร ───
-- ตอนสมัครยังไม่รู้ว่าใครจะผ่าน การจำกัดจำนวนใบสมัครตามที่นั่งจะปิดกั้น
-- คนที่ควรได้เรียนโดยไม่มีเหตุผล — โควตาคือจำนวน "ที่นั่ง" ไม่ใช่จำนวน
-- "ใบสมัคร" การตรวจจึงอยู่ที่ตอนตัดสินผลว่าผ่าน
--
-- ─── ทำไม admit_applicant() ใช้ person เดิมถ้ามีอยู่แล้ว ───
-- คนที่เคยเรียนแล้วลาออกไปสมัครใหม่มีอยู่จริง ถ้าสร้าง person ใหม่จะชน
-- unique (institution_id, national_id_hash) แล้วรับเข้าไม่ได้เลย
-- โดยที่ข้อความผิดพลาดไม่ได้บอกว่าปัญหาคืออะไร
-- ═══════════════════════════════════════════════════════════════════
begin;

create type admission_round_status as enum
  ('draft', 'open', 'closed', 'announced', 'completed');

comment on type admission_round_status is
  'draft → open (เปิดรับ) → closed (ปิดรับ) → announced (ประกาศผล) → completed (รายงานตัวเสร็จ)';

create type application_status as enum
  ('draft', 'submitted', 'passed', 'failed', 'waitlisted', 'withdrawn', 'enrolled');

create type document_check_status as enum ('pending', 'received', 'verified', 'rejected');

-- ───────────────────────────────────────────────────────────────────
-- รอบรับสมัคร
-- ───────────────────────────────────────────────────────────────────
create table admission_round (
  id               uuid        primary key default gen_random_uuid(),
  institution_id   uuid        not null references institution on delete restrict,
  academic_year_id uuid        not null references academic_year on delete restrict,
  code             text        not null,
  name_th          text        not null,
  applies_from     date        not null,
  applies_to       date        not null,
  exam_on          date,
  announce_on      date,
  report_from      date,
  report_to        date,
  status           admission_round_status not null default 'draft',
  note             text,
  created_at       timestamptz not null default now(),

  unique (institution_id, academic_year_id, code),
  check (applies_to >= applies_from),
  check (report_to is null or report_from is null or report_to >= report_from)
);

comment on table admission_round is
  'รอบรับสมัครหนึ่งรอบ — คุมว่าเปิดรับเมื่อไร สอบวันไหน ประกาศผลและรายงานตัวช่วงไหน';

create index admission_round_year_idx
  on admission_round (institution_id, academic_year_id, status);

-- ───────────────────────────────────────────────────────────────────
-- โควตาที่นั่งต่อหลักสูตร
-- ───────────────────────────────────────────────────────────────────
create table admission_quota (
  id                    uuid     primary key default gen_random_uuid(),
  round_id              uuid     not null references admission_round on delete cascade,
  curriculum_version_id uuid     not null references curriculum_version on delete restrict,
  seats                 smallint not null check (seats > 0),
  note                  text,
  unique (round_id, curriculum_version_id)
);

comment on column admission_quota.seats is
  'จำนวนที่นั่ง ไม่ใช่จำนวนใบสมัคร — ตรวจตอนตัดสินผลว่าผ่าน ไม่ใช่ตอนรับใบสมัคร';

-- ───────────────────────────────────────────────────────────────────
-- ใบสมัคร
--
-- เก็บผลการคัดเลือกและการรายงานตัวไว้บนใบเดียวกัน เพราะใบสมัครหนึ่งใบ
-- มีผลเดียวและรายงานตัวครั้งเดียว การแยกตารางจะเพิ่ม join โดยไม่ได้อะไร
-- ───────────────────────────────────────────────────────────────────
create table application (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  round_id       uuid        not null references admission_round on delete restrict,
  application_no text        not null,

  prefix_th        text,
  first_name_th    text        not null,
  last_name_th     text        not null,
  national_id_hash bytea,
  birth_date       date,
  gender           gender_kind not null default 'undisclosed',
  phone            text,
  email            text,
  address_th       text,

  -- วุฒิเดิม ใช้ทั้งตรวจคุณสมบัติและกรอก prior_academic_record ตอนรับเข้า
  prior_school_th        text,
  prior_qualification_th text,
  prior_gpax             numeric(3,2) check (prior_gpax is null or (prior_gpax >= 0 and prior_gpax <= 4)),

  -- รู้จักวิทยาลัยจากช่องทางไหน — งานประชาสัมพันธ์ใช้วัดผลว่าช่องทางไหนได้ผล
  referral_source text,

  status       application_status not null default 'draft',
  submitted_at timestamptz,

  -- ผลการคัดเลือก
  admitted_curriculum_version_id uuid references curriculum_version on delete restrict,
  rank_no    smallint check (rank_no is null or rank_no > 0),
  score      numeric(6,2),
  decided_by uuid references person on delete restrict,
  decided_at timestamptz,
  decision_note text,

  -- การรายงานตัวและการรับเข้าเป็นนักศึกษา
  reported_on date,
  student_id  uuid references student on delete restrict,

  created_at timestamptz not null default now(),

  unique (institution_id, round_id, application_no),
  -- ผ่านการคัดเลือกแล้วต้องรู้ว่าได้หลักสูตรไหน มิฉะนั้นรับเข้าไม่ได้
  constraint passed_needs_curriculum
    check (status <> 'passed' or admitted_curriculum_version_id is not null)
);

-- คนเดียวกันสมัครสองใบในรอบเดียวกันไม่ได้ — จะกินโควตาสองที่นั่ง
-- และถ้าผ่านทั้งคู่จะได้รหัสนักศึกษาสองรหัส
create unique index application_round_national_id_uniq
  on application (round_id, national_id_hash)
  where national_id_hash is not null;

create unique index application_student_uniq
  on application (student_id) where student_id is not null;

create index application_round_status_idx on application (round_id, status);

comment on column application.national_id_hash is
  'ค่าแฮชของเลขบัตรประชาชน ใช้กันสมัครซ้ำและจับคู่กับ person เดิม — หลักเดียวกับ person.national_id_hash';

-- ───────────────────────────────────────────────────────────────────
-- อันดับหลักสูตรที่เลือก
-- ───────────────────────────────────────────────────────────────────
create table application_choice (
  id                    uuid     primary key default gen_random_uuid(),
  application_id        uuid     not null references application on delete cascade,
  preference            smallint not null check (preference between 1 and 5),
  curriculum_version_id uuid     not null references curriculum_version on delete restrict,
  unique (application_id, preference),
  unique (application_id, curriculum_version_id)
);

comment on table application_choice is
  'อันดับที่ผู้สมัครเลือก — เลือกหลักสูตรเดิมซ้ำสองอันดับไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- หลักฐานประกอบการสมัคร
-- ───────────────────────────────────────────────────────────────────
create table application_document (
  id             uuid                  primary key default gen_random_uuid(),
  application_id uuid                  not null references application on delete cascade,
  kind           text                  not null,
  status         document_check_status not null default 'pending',
  file_key       text,
  note           text,
  checked_by     uuid                  references person on delete restrict,
  checked_at     timestamptz,
  unique (application_id, kind)
);

comment on column application_document.file_key is
  'คีย์ของไฟล์ในที่เก็บภายนอก ไม่เก็บตัวไฟล์ในฐานข้อมูล';

-- ───────────────────────────────────────────────────────────────────
-- เลขที่ใบสมัคร — นับแยกตามรอบ
-- ───────────────────────────────────────────────────────────────────
create or replace function next_application_no(p_round_id uuid)
returns text language plpgsql as $$
declare
  v_code text;
  v_next integer;
begin
  -- ล็อกแถวของรอบไว้ กันเจ้าหน้าที่สองคนกดพร้อมกันแล้วได้เลขเดียวกัน
  select ar.code into v_code from admission_round ar
   where ar.id = p_round_id for update;

  if v_code is null then
    raise exception 'ไม่พบรอบรับสมัครที่ระบุ';
  end if;

  select coalesce(max(substring(a.application_no from '[0-9]+$')::integer), 0) + 1
    into v_next
    from application a where a.round_id = p_round_id;

  return v_code || '-' || lpad(v_next::text, 4, '0');
end $$;

comment on function next_application_no(uuid) is
  'เลขที่ใบสมัครถัดไปของรอบ — ล็อกแถวรอบไว้ระหว่างคิด กันเจ้าหน้าที่สองคนได้เลขเดียวกัน';

-- ───────────────────────────────────────────────────────────────────
-- ยื่นใบสมัคร
-- ───────────────────────────────────────────────────────────────────
create or replace function submit_application(p_application_id uuid)
returns application language plpgsql as $$
declare
  v_app   application;
  v_round admission_round;
begin
  select * into v_app from application where id = p_application_id;
  if v_app.id is null then
    raise exception 'ไม่พบใบสมัครที่ระบุ';
  end if;
  if v_app.status <> 'draft' then
    raise exception 'ใบสมัครนี้ยื่นไปแล้ว (สถานะ %)', v_app.status
      using errcode = 'check_violation';
  end if;

  select * into v_round from admission_round where id = v_app.round_id;

  if v_round.status <> 'open' then
    raise exception 'รอบรับสมัครนี้ยังไม่เปิดรับหรือปิดรับไปแล้ว (สถานะ %)', v_round.status
      using errcode = 'check_violation';
  end if;
  if current_date < v_round.applies_from or current_date > v_round.applies_to then
    raise exception 'อยู่นอกช่วงวันที่รับสมัคร (% ถึง %)',
      v_round.applies_from, v_round.applies_to
      using errcode = 'check_violation';
  end if;
  if not exists (select 1 from application_choice ac where ac.application_id = p_application_id) then
    raise exception 'ต้องเลือกหลักสูตรอย่างน้อยหนึ่งอันดับก่อนยื่นใบสมัคร'
      using errcode = 'check_violation';
  end if;

  update application
     set status = 'submitted', submitted_at = now()
   where id = p_application_id
  returning * into v_app;

  return v_app;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ตัดสินผลการคัดเลือก
--
-- ตรวจโควตาที่นี่ ไม่ใช่ตอนรับใบสมัคร — โควตาคือจำนวนที่นั่ง
-- ───────────────────────────────────────────────────────────────────
create or replace function decide_application(
  p_application_id uuid,
  p_outcome        text,
  p_curriculum_version_id uuid default null,
  p_rank_no        smallint default null,
  p_score          numeric  default null,
  p_note           text     default null
) returns application language plpgsql as $$
declare
  v_app    application;
  v_seats  smallint;
  v_taken  integer;
begin
  if p_outcome not in ('passed', 'failed', 'waitlisted') then
    raise exception 'ผลการคัดเลือกต้องเป็น passed, failed หรือ waitlisted (ได้ %)', p_outcome;
  end if;

  select * into v_app from application where id = p_application_id;
  if v_app.id is null then
    raise exception 'ไม่พบใบสมัครที่ระบุ';
  end if;
  if v_app.status not in ('submitted', 'waitlisted') then
    raise exception 'ตัดสินผลได้เฉพาะใบที่ยื่นแล้วและยังไม่ได้รับเข้า (สถานะ %)', v_app.status
      using errcode = 'check_violation';
  end if;

  if p_outcome = 'passed' then
    if p_curriculum_version_id is null then
      raise exception 'ผู้ที่ผ่านการคัดเลือกต้องระบุหลักสูตรที่ได้'
        using errcode = 'check_violation';
    end if;

    select aq.seats into v_seats
      from admission_quota aq
     where aq.round_id = v_app.round_id
       and aq.curriculum_version_id = p_curriculum_version_id;

    if v_seats is null then
      raise exception 'หลักสูตรนี้ไม่ได้เปิดรับในรอบนี้'
        using errcode = 'check_violation';
    end if;

    select count(*) into v_taken
      from application a
     where a.round_id = v_app.round_id
       and a.admitted_curriculum_version_id = p_curriculum_version_id
       and a.status in ('passed', 'enrolled')
       and a.id <> p_application_id;

    if v_taken >= v_seats then
      raise exception 'ที่นั่งของหลักสูตรนี้เต็มแล้ว (รับได้ % ที่นั่ง)', v_seats
        using errcode = 'check_violation';
    end if;
  end if;

  update application
     set status = p_outcome::application_status,
         admitted_curriculum_version_id =
           case when p_outcome = 'passed' then p_curriculum_version_id else null end,
         rank_no = p_rank_no,
         score   = p_score,
         decision_note = p_note,
         decided_by = current_actor_id(),
         decided_at = now()
   where id = p_application_id
  returning * into v_app;

  return v_app;
end $$;

comment on function decide_application(uuid, text, uuid, smallint, numeric, text) is
  'ตัดสินผลการคัดเลือกพร้อมตรวจโควตาที่นั่ง — ประกาศผ่านเกินที่นั่งไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- รับเข้าเป็นนักศึกษา
--
-- จุดเดียวในระบบที่เปลี่ยนผู้สมัครเป็นนักศึกษา สร้าง person + student
-- + สังกัดหลักสูตร + ชั้นปี พร้อมกันในทรานแซกชันเดียว
-- ───────────────────────────────────────────────────────────────────
create or replace function admit_applicant(
  p_application_id   uuid,
  p_student_code     text,
  p_academic_year_id uuid,
  p_study_year       smallint default 1,
  p_group_code       text     default null
) returns uuid language plpgsql as $$
declare
  v_app     application;
  v_inst    uuid := current_institution_id();
  v_person  uuid;
  v_student uuid;
begin
  select * into v_app from application where id = p_application_id;
  if v_app.id is null then
    raise exception 'ไม่พบใบสมัครที่ระบุ';
  end if;
  if v_app.status <> 'passed' then
    raise exception 'รับเข้าได้เฉพาะผู้ที่ผ่านการคัดเลือก (สถานะ %)', v_app.status
      using errcode = 'check_violation';
  end if;
  if v_app.student_id is not null then
    raise exception 'ใบสมัครนี้รับเข้าไปแล้ว'
      using errcode = 'check_violation';
  end if;
  if coalesce(btrim(p_student_code), '') = '' then
    raise exception 'ต้องระบุรหัสนักศึกษา';
  end if;

  -- คนที่เคยเรียนแล้วลาออกไปสมัครใหม่มีอยู่จริง ใช้ person เดิมต่อ
  -- มิฉะนั้นจะชน unique (institution_id, national_id_hash) แล้วรับเข้าไม่ได้
  if v_app.national_id_hash is not null then
    select p.id into v_person from person p
     where p.institution_id = v_inst
       and p.national_id_hash = v_app.national_id_hash;
  end if;

  if v_person is null then
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email)
    values (v_inst, v_app.prefix_th, v_app.first_name_th, v_app.last_name_th,
            v_app.national_id_hash, v_app.birth_date, v_app.gender,
            v_app.phone, v_app.email)
    returning id into v_person;
  end if;

  insert into student
    (institution_id, person_id, student_code, admitted_year_be, status)
  values (v_inst, v_person, btrim(p_student_code),
          (select ay.year_be from academic_year ay where ay.id = p_academic_year_id),
          'active')
  returning id into v_student;

  insert into student_curriculum (student_id, curriculum_version_id, effective_from)
  values (v_student, v_app.admitted_curriculum_version_id, current_date);

  insert into student_class_placement
    (institution_id, student_id, academic_year_id, study_year, group_code)
  values (v_inst, v_student, p_academic_year_id, p_study_year, p_group_code);

  -- ─── ทำไมไม่คัดลอกวุฒิเดิมลง prior_academic_record ───
  -- ตารางนั้นเก็บ **ผลรายวิชา** เพื่อเทียบโอนหน่วยกิต (มี credits > 0
  -- เป็นข้อบังคับ) ไม่ใช่ "วุฒิที่จบมา" การยัดแถวปลอมที่มีรหัสวิชาเป็น '-'
  -- และหน่วยกิตเป็นศูนย์ลงไป จะทำให้ทุกรายงานที่นับรายวิชาเทียบโอนมีขยะปน
  --
  -- วุฒิเดิมยังอยู่บนใบสมัครและตามหาได้จาก application.student_id
  -- ถ้าวันหนึ่งต้องเทียบโอนรายวิชาจริง ให้กรอกผ่านเส้นทางเทียบโอนโดยตรง
  update application
     set student_id = v_student,
         status     = 'enrolled',
         reported_on = coalesce(reported_on, current_date)
   where id = p_application_id;

  return v_student;
end $$;

comment on function admit_applicant(uuid, text, uuid, smallint, text) is
  'เปลี่ยนผู้สมัครเป็นนักศึกษา — จุดเดียวในระบบที่ทำเรื่องนี้ ทำได้ครั้งเดียวต่อใบสมัคร';

-- ───────────────────────────────────────────────────────────────────
-- สรุปยอดรับสมัครรายหลักสูตร
-- ───────────────────────────────────────────────────────────────────
create or replace function admission_summary(p_round_id uuid)
returns table (
  curriculum_version_id uuid,
  curriculum_th text,
  shift         class_shift,
  seats         smallint,
  applied       integer,
  passed        integer,
  enrolled      integer,
  seats_left    integer
) language sql stable as $$
  select aq.curriculum_version_id,
         cur.name_th,
         cur.shift,
         aq.seats,
         (select count(*) from application_choice ac
            join application a on a.id = ac.application_id
           where ac.curriculum_version_id = aq.curriculum_version_id
             and a.round_id = aq.round_id
             and a.status <> 'draft')::integer,
         (select count(*) from application a
           where a.round_id = aq.round_id
             and a.admitted_curriculum_version_id = aq.curriculum_version_id
             and a.status in ('passed', 'enrolled'))::integer,
         (select count(*) from application a
           where a.round_id = aq.round_id
             and a.admitted_curriculum_version_id = aq.curriculum_version_id
             and a.status = 'enrolled')::integer,
         aq.seats - (select count(*) from application a
                      where a.round_id = aq.round_id
                        and a.admitted_curriculum_version_id = aq.curriculum_version_id
                        and a.status in ('passed', 'enrolled'))::integer
    from admission_quota aq
    join curriculum_version cv on cv.id = aq.curriculum_version_id
    join curriculum cur        on cur.id = cv.curriculum_id
   where aq.round_id = p_round_id
   order by cur.name_th;
$$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['admission_round', 'application'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- ตารางลูกไม่ได้สืบทอด RLS ผ่านคีย์นอก
alter table admission_quota enable row level security;
alter table admission_quota force  row level security;
create policy tenant_isolation on admission_quota
  using (exists (select 1 from admission_round ar
                  where ar.id = admission_quota.round_id
                    and ar.institution_id = current_institution_id()));

alter table application_choice enable row level security;
alter table application_choice force  row level security;
create policy tenant_isolation on application_choice
  using (exists (select 1 from application a
                  where a.id = application_choice.application_id
                    and a.institution_id = current_institution_id()));

alter table application_document enable row level security;
alter table application_document force  row level security;
create policy tenant_isolation on application_document
  using (exists (select 1 from application a
                  where a.id = application_document.application_id
                    and a.institution_id = current_institution_id()));

-- ชั้นที่ 2 — ข้อมูลผู้สมัครมีเลขบัตรประชาชนและข้อมูลผู้เยาว์
-- ครูผู้สอนไม่มีหน้าที่เกี่ยวข้องกับการรับสมัคร จึงไม่เห็นเลย
create policy application_scope on application
  as restrictive using (is_institution_wide_role());

create policy admission_round_scope on admission_round
  as restrictive using (is_institution_wide_role());

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0034_rooms_and_timetable.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0034_rooms_and_timetable.sql
--
-- ห้องเรียนเป็นข้อมูลจริง และการจัดตารางสอน
--
-- ─── ทำไมต้องทำห้องให้เป็นตารางก่อน ───
-- ก่อนไฟล์นี้ ห้องเป็นข้อความอิสระใน class_section.room และ
-- section_timeslot.room ซึ่งใช้ตรวจการชนของห้องไม่ได้เลย — "ห้อง 301"
-- กับ "ห้อง301" กับ "301" เป็นคนละห้องในสายตาฐานข้อมูล ผลคือจัดสองวิชา
-- ลงห้องเดียวกันเวลาเดียวกันได้โดยไม่มีอะไรฟ้อง แล้วไปรู้ตอนครูสองคน
-- พานักศึกษามายืนหน้าห้องเดียวกัน
--
-- และห้องปฏิบัติการต้องแยกจากห้องบรรยาย เพราะวิชาที่ต้องใช้โรงฝึกงาน
-- จัดลงห้องบรรยายไม่ได้ ซึ่งข้อความอิสระบอกไม่ได้
--
-- ─── ทำไมกล้าลบคอลัมน์ข้อความทิ้ง ───
-- ทั้งระบบมีที่เขียนค่าห้องสามแห่งและอ่านหนึ่งแห่ง ทั้งหมดอยู่ในมือเรา
-- การเก็บทั้งข้อความและคีย์ไว้คู่กันจะกลายเป็นความจริงสองชุดที่ค่อย ๆ
-- ไม่ตรงกัน แล้ววันหนึ่งจะไม่มีใครรู้ว่าอันไหนคือห้องจริง
--
-- ─── การชนกันสี่แบบที่ตัวตรวจจับ ───
-- 1. ครูคนเดียวสอนสองที่พร้อมกัน
-- 2. ห้องเดียวถูกใช้สองวิชาพร้อมกัน
-- 3. นักศึกษากลุ่มเดียวกันมีสองวิชาพร้อมกัน (หลักสูตรฉบับเดียวกัน + ห้องเดียวกัน)
-- 4. นักศึกษาที่ลงทะเบียนแล้วมีสองวิชาชนกันจริง
--
-- ข้อ 3 กับข้อ 4 ต่างกันตรงเวลาที่ใช้ได้ — ตอนจัดตารางยังไม่มีใครลงทะเบียน
-- จึงต้องใช้ "กลุ่มตามแผน" (ข้อ 3) ส่วนข้อ 4 ใช้ตรวจย้อนหลังหลังเปิดเทอม
-- ว่ามีใครติดตารางชนจริงไหม ถ้ามีแต่ข้อ 4 อย่างเดียวจะตรวจอะไรไม่ได้เลย
-- ตอนที่ยังจัดตารางอยู่ ซึ่งเป็นตอนที่ต้องการมันที่สุด
--
-- ─── ทำไมตัวจัดอัตโนมัติเป็นแบบโลภ ไม่ใช่หาคำตอบที่ดีที่สุด ───
-- การจัดตารางที่ดีที่สุดเป็นปัญหา NP-hard การหาคำตอบที่ดีที่สุดจริง ๆ
-- กับวิชาสองพันกว่าตัวใช้เวลานานเกินกว่าจะรอในหน้าจอ และคำตอบที่ "ดีที่สุด"
-- ตามสูตรมักขัดกับข้อจำกัดจริงที่ไม่ได้อยู่ในฐานข้อมูล (ครูคนนี้ไม่สอนเช้า
-- เพราะต้องส่งลูก) ตัวจัดนี้จึงวางให้ได้มากที่สุดเท่าที่ไม่ชน แล้ว
-- **รายงานว่าวิชาไหนวางไม่ได้และเพราะอะไร** ให้คนไปตัดสินใจต่อ
-- ไม่ใช่ยัดลงไปให้ครบแล้วปล่อยให้ไปเจอปัญหาหน้างาน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ห้องเรียน
-- ───────────────────────────────────────────────────────────────────
create type room_kind as enum
  ('classroom', 'workshop', 'lab', 'computer', 'auditorium', 'outdoor');

comment on type room_kind is
  'ประเภทห้อง — workshop คือโรงฝึกงาน ใช้กับวิชาที่ course.needs_workshop';

create table room (
  id             uuid      primary key default gen_random_uuid(),
  institution_id uuid      not null references institution on delete restrict,
  code           text      not null,
  name_th        text      not null,
  kind           room_kind not null default 'classroom',
  capacity       smallint  check (capacity is null or capacity > 0),
  building       text,
  active         boolean   not null default true,
  created_at     timestamptz not null default now(),
  unique (institution_id, code)
);

comment on table room is
  'ห้องเรียนจริง — ก่อนหน้านี้เป็นข้อความอิสระ ซึ่งทำให้ตรวจการชนของห้องไม่ได้';

create index room_institution_idx on room (institution_id, kind) where active;

-- ── ย้ายข้อมูลเดิมจากคอลัมน์ข้อความ ────────────────────────────────
insert into room (institution_id, code, name_th, kind)
select distinct cs.institution_id, btrim(cs.room), btrim(cs.room),
       case when cs.room ilike '%โรงฝึก%' or cs.room ilike '%ปฏิบัติการ%'
            then 'workshop'::room_kind else 'classroom'::room_kind end
  from class_section cs
 where nullif(btrim(cs.room), '') is not null
on conflict (institution_id, code) do nothing;

insert into room (institution_id, code, name_th, kind)
select distinct cs.institution_id, btrim(st.room), btrim(st.room),
       case when st.room ilike '%โรงฝึก%' or st.room ilike '%ปฏิบัติการ%'
            then 'workshop'::room_kind else 'classroom'::room_kind end
  from section_timeslot st
  join class_section cs on cs.id = st.class_section_id
 where nullif(btrim(st.room), '') is not null
on conflict (institution_id, code) do nothing;

alter table class_section    add column room_id uuid references room on delete restrict;
alter table section_timeslot add column room_id uuid references room on delete restrict;

update class_section cs
   set room_id = r.id
  from room r
 where r.institution_id = cs.institution_id
   and r.code = btrim(cs.room);

update section_timeslot st
   set room_id = r.id
  from class_section cs, room r
 where cs.id = st.class_section_id
   and r.institution_id = cs.institution_id
   and r.code = btrim(st.room);

-- v_room_conflict จาก 0009 เทียบห้องด้วยข้อความ ซึ่งเป็นเหตุผลที่ไฟล์นี้มีอยู่ —
-- "ห้อง 301" กับ "301" ไม่เท่ากัน วิวจึงมองไม่เห็นการชนที่เกิดขึ้นจริง
-- สร้างใหม่ให้เทียบด้วยคีย์ของห้องแทน
drop view if exists v_room_conflict;

-- ความจริงสองชุดที่ค่อย ๆ ไม่ตรงกันแก้ยากกว่าการย้ายให้จบตั้งแต่ตอนนี้
alter table class_section    drop column room;
alter table section_timeslot drop column room;

create view v_room_conflict as
select cs1.term_id,
       t1.room_id,
       r.code as room_code,
       t1.day_of_week,
       cs1.id as section_a,
       cs2.id as section_b,
       int4range(t1.period_from, t1.period_to, '[]')
         * int4range(t2.period_from, t2.period_to, '[]') as overlapping_periods
  from section_timeslot t1
  join class_section cs1 on cs1.id = t1.class_section_id
  join room r            on r.id   = t1.room_id
  join section_timeslot t2
    on t2.day_of_week = t1.day_of_week
   and t2.room_id = t1.room_id
   and int4range(t2.period_from, t2.period_to, '[]')
       && int4range(t1.period_from, t1.period_to, '[]')
  join class_section cs2 on cs2.id = t2.class_section_id
 where cs1.term_id = cs2.term_id and cs1.id < cs2.id;

alter view v_room_conflict set (security_invoker = true);

create index section_timeslot_room_idx on section_timeslot (room_id, day_of_week);

-- ───────────────────────────────────────────────────────────────────
-- นโยบายตารางสอน
-- ───────────────────────────────────────────────────────────────────
create table timetable_policy (
  institution_id  uuid     primary key references institution on delete cascade,
  periods_per_day smallint not null default 10 check (periods_per_day between 1 and 20),
  days_per_week   smallint not null default 5  check (days_per_week between 1 and 7),
  lunch_period    smallint check (lunch_period is null or lunch_period > 0),
  max_consecutive smallint not null default 4  check (max_consecutive between 1 and 10)
);

comment on column timetable_policy.lunch_period is
  'คาบพักกลางวัน — ตัวจัดอัตโนมัติจะไม่วางคาบเรียนทับ และตัวตรวจจะเตือนถ้ามีคนวางเอง';
comment on column timetable_policy.max_consecutive is
  'จำนวนคาบติดกันสูงสุดที่ยอมให้จัดในวันเดียว — กันวิชาเดียวยาวทั้งวัน';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจการชนของคาบที่เสนอ
--
-- คืน "รายการปัญหา" ไม่ใช่ true/false — หน้าจอจึงบอกได้ว่าชนกับอะไรบ้าง
-- หลักเดียวกับ check_registration() ใน 0009
-- ───────────────────────────────────────────────────────────────────
create or replace function timeslot_conflicts(
  p_class_section_id uuid,
  p_day_of_week      smallint,
  p_period_from      smallint,
  p_period_to        smallint,
  p_room_id          uuid default null,
  p_ignore_slot_id   uuid default null
) returns table (
  kind             text,
  message_th       text,
  other_section_id uuid
) language sql stable as $$
  with me as (
    select cs.id, cs.term_id, cs.teacher_id, cs.curriculum_version_id,
           cs.section_no, cs.institution_id, c.needs_workshop
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.id = p_class_section_id
  ),
  policy as (
    select tp.* from timetable_policy tp
     join me on me.institution_id = tp.institution_id
  ),
  overlapping as (
    select st.id as slot_id, st.class_section_id, st.room_id,
           cs2.teacher_id, cs2.curriculum_version_id, cs2.section_no,
           c2.code as course_code, c2.name_th as course_name
      from section_timeslot st
      join class_section cs2 on cs2.id = st.class_section_id
      join course c2         on c2.id  = cs2.course_id
      cross join me
     where cs2.term_id = me.term_id
       and st.class_section_id <> p_class_section_id
       and (p_ignore_slot_id is null or st.id <> p_ignore_slot_id)
       and st.day_of_week = p_day_of_week
       and int4range(st.period_from, st.period_to, '[]')
           && int4range(p_period_from, p_period_to, '[]')
  )
  -- 1. ครูคนเดียวสอนสองที่พร้อมกัน
  select 'teacher',
         'ครูผู้สอนติดสอน ' || o.course_code || ' ' || o.course_name || ' ในคาบเดียวกัน',
         o.class_section_id
    from overlapping o cross join me
   where me.teacher_id is not null and o.teacher_id = me.teacher_id

  union all
  -- 2. ห้องเดียวถูกใช้สองวิชาพร้อมกัน
  select 'room',
         'ห้องนี้ถูกใช้โดย ' || o.course_code || ' ' || o.course_name || ' ในคาบเดียวกัน',
         o.class_section_id
    from overlapping o
   where p_room_id is not null and o.room_id = p_room_id

  union all
  -- 3. นักศึกษากลุ่มเดียวกันตามแผน — ใช้ได้ตั้งแต่ตอนจัดตาราง
  --    ก่อนที่จะมีใครลงทะเบียน ซึ่งเป็นตอนที่ต้องการมันที่สุด
  select 'cohort',
         'ห้องเรียน ' || coalesce(me.section_no, '-') || ' ติดเรียน '
           || o.course_code || ' ' || o.course_name || ' ในคาบเดียวกัน',
         o.class_section_id
    from overlapping o cross join me
   where me.curriculum_version_id is not null
     and o.curriculum_version_id = me.curriculum_version_id
     and o.section_no is not distinct from me.section_no

  union all
  -- 4. นักศึกษาที่ลงทะเบียนแล้วชนจริง — ใช้ตรวจย้อนหลังหลังเปิดเทอม
  select distinct 'enrolled',
         'มีนักศึกษาที่ลงทะเบียนทั้งวิชานี้และ ' || o.course_code || ' อยู่แล้ว',
         o.class_section_id
    from overlapping o
   where exists (
     select 1 from enrollment e1
       join enrollment e2 on e2.student_id = e1.student_id
      where e1.class_section_id = p_class_section_id
        and e2.class_section_id = o.class_section_id
        and e1.status = 'enrolled' and e2.status = 'enrolled')

  union all
  -- 5. ห้องเรียนรายวิชานี้มีคาบอยู่แล้วในช่วงเวลานั้น
  --
  --    ข้อนี้ดูเหมือนซ้ำซ้อนกับ exclusion constraint ที่กันไว้อยู่แล้ว
  --    แต่จำเป็น เพราะตัวเสนอคาบว่างต้องรู้ล่วงหน้าว่าวางไม่ได้
  --    ไม่ใช่ไปรู้ตอนที่ insert แล้วล้ม — ตัวจัดอัตโนมัติที่วางหลายบล็อก
  --    ให้วิชาเดียวกันจะเสนอคาบเดิมซ้ำไปเรื่อย ๆ ถ้าไม่มีข้อนี้
  select 'self',
         'ห้องเรียนรายวิชานี้มีคาบเรียนอยู่แล้วในช่วงเวลานี้',
         null::uuid
    from section_timeslot st
   where st.class_section_id = p_class_section_id
     and (p_ignore_slot_id is null or st.id <> p_ignore_slot_id)
     and st.day_of_week = p_day_of_week
     and int4range(st.period_from, st.period_to, '[]')
         && int4range(p_period_from, p_period_to, '[]')

  union all
  -- 6. วิชาที่ต้องใช้โรงฝึกงานจัดลงห้องบรรยายไม่ได้
  select 'room_kind',
         'วิชานี้ต้องใช้โรงฝึกงาน แต่ห้องที่เลือกเป็น ' || r.name_th,
         null::uuid
    from me join room r on r.id = p_room_id
   where me.needs_workshop and r.kind not in ('workshop', 'lab', 'computer')

  union all
  -- 7. ทับคาบพักกลางวันหรือเกินจำนวนคาบต่อวัน
  select 'policy',
         case when p.lunch_period is not null
                   and p.lunch_period between p_period_from and p_period_to
              then 'คาบนี้ทับคาบพักกลางวัน (คาบ ' || p.lunch_period || ')'
              when p_period_to > p.periods_per_day
              then 'เกินจำนวนคาบต่อวันที่กำหนดไว้ (' || p.periods_per_day || ' คาบ)'
              else 'เกินจำนวนวันเรียนต่อสัปดาห์ที่กำหนดไว้ (' || p.days_per_week || ' วัน)'
         end,
         null::uuid
    from policy p
   where (p.lunch_period is not null
          and p.lunch_period between p_period_from and p_period_to)
      or p_period_to > p.periods_per_day
      or p_day_of_week > p.days_per_week;
$$;

comment on function timeslot_conflicts(uuid, smallint, smallint, smallint, uuid, uuid) is
  'ตรวจว่าคาบที่เสนอชนกับอะไรบ้าง — คืนรายการปัญหาทั้งหมด ไม่ใช่หยุดที่ข้อแรก';

-- ───────────────────────────────────────────────────────────────────
-- คาบว่างที่วางได้
--
-- ไล่ทุกวันทุกคาบแล้วคัดเฉพาะที่ไม่ชนอะไรเลย เรียงตามวันและคาบ
-- เพื่อให้ตารางกระจุกอยู่ต้นสัปดาห์และต้นวัน ซึ่งเป็นรูปแบบที่วิทยาลัยใช้จริง
-- ───────────────────────────────────────────────────────────────────
create or replace function suggest_timeslots(
  p_class_section_id uuid,
  p_periods          smallint default 2,
  p_room_id          uuid default null,
  p_limit            integer default 10
) returns table (
  day_of_week smallint,
  period_from smallint,
  period_to   smallint
) language sql stable as $$
  with me as (
    select cs.institution_id from class_section cs where cs.id = p_class_section_id
  ),
  policy as (
    select coalesce(tp.periods_per_day, 10) as periods_per_day,
           coalesce(tp.days_per_week, 5)    as days_per_week
      from me left join timetable_policy tp on tp.institution_id = me.institution_id
  ),
  candidates as (
    select d::smallint as day_of_week,
           s::smallint as period_from,
           (s + p_periods - 1)::smallint as period_to
      from policy p,
           generate_series(1, p.days_per_week) d,
           generate_series(1, p.periods_per_day) s
     where s + p_periods - 1 <= p.periods_per_day
  )
  select c.day_of_week, c.period_from, c.period_to
    from candidates c
   where not exists (
     select 1 from timeslot_conflicts(
       p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_room_id))
   order by c.day_of_week, c.period_from
   limit p_limit;
$$;

comment on function suggest_timeslots(uuid, smallint, uuid, integer) is
  'คาบว่างที่วางห้องเรียนรายวิชานี้ได้โดยไม่ชนอะไรเลย';

-- ───────────────────────────────────────────────────────────────────
-- จัดตารางอัตโนมัติทั้งภาคเรียน
--
-- คืนผลรายห้องเรียนเสมอ รวมถึงห้องที่วางไม่ได้และเหตุผล
-- ไม่ raise เพราะห้องหนึ่งวางไม่ได้ต้องไม่ทำให้ทั้งภาคเรียนล้ม
-- ───────────────────────────────────────────────────────────────────
create or replace function auto_schedule_term(p_term_id uuid)
returns table (
  class_section_id uuid,
  label            text,
  action           text,
  periods_placed   smallint,
  note             text
) language plpgsql as $$
#variable_conflict use_column
declare
  r         record;
  v_need    smallint;
  v_have    smallint;
  v_block   smallint;
  v_max     smallint;
  v_placed  smallint;
  v_slot    record;
begin
  select coalesce(max(tp.max_consecutive), 4) into v_max
    from class_section cs
    join timetable_policy tp on tp.institution_id = cs.institution_id
   where cs.term_id = p_term_id;

  for r in
    select cs.id, cs.room_id, c.code, c.name_th, c.weekly_periods,
           coalesce(cs.section_no, '-') as section_no
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.term_id = p_term_id
       and not cs.is_locked
     order by c.code, cs.section_no
  loop
    select coalesce(sum(st.period_to - st.period_from + 1), 0)::smallint
      into v_have
      from section_timeslot st where st.class_section_id = r.id;

    v_need := coalesce(r.weekly_periods, 0)::smallint - v_have;

    if coalesce(r.weekly_periods, 0) = 0 then
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'skipped'::text, v_have,
        'หลักสูตรไม่ได้กำหนดจำนวนคาบต่อสัปดาห์ของรายวิชานี้'::text;
      continue;
    end if;

    if v_need <= 0 then
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'already_full'::text, v_have, null::text;
      continue;
    end if;

    v_placed := 0;

    while v_need > 0 loop
      v_block := least(v_need, v_max)::smallint;

      select * into v_slot
        from suggest_timeslots(r.id, v_block, r.room_id, 1);

      -- ลองบล็อกที่สั้นลงก่อนยอมแพ้ — ตารางที่แตกเป็นคาบเดี่ยวยังดีกว่าไม่มี
      while v_slot is null and v_block > 1 loop
        v_block := (v_block - 1)::smallint;
        select * into v_slot
          from suggest_timeslots(r.id, v_block, r.room_id, 1);
      end loop;

      exit when v_slot is null;

      insert into section_timeslot
        (class_section_id, day_of_week, period_from, period_to, room_id)
      values (r.id, v_slot.day_of_week, v_slot.period_from, v_slot.period_to, r.room_id);

      v_placed := (v_placed + v_block)::smallint;
      v_need   := (v_need - v_block)::smallint;
      v_slot   := null;
    end loop;

    if v_need > 0 then
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'partial'::text, v_placed,
        format('วางได้ %s คาบ ยังขาดอีก %s คาบ ไม่มีคาบว่างที่ไม่ชน', v_placed, v_need)::text;
    else
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'scheduled'::text, v_placed, null::text;
    end if;
  end loop;
end $$;

comment on function auto_schedule_term(uuid) is
  'จัดตารางสอนทั้งภาคเรียนแบบโลภ — วางให้ได้มากที่สุดเท่าที่ไม่ชน แล้วรายงานวิชาที่วางไม่ครบ';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจการชนของตารางทั้งภาคเรียน
--
-- ใช้ตรวจหลังจัดเสร็จหรือหลังมีคนแก้ตารางเอง
-- ───────────────────────────────────────────────────────────────────
create or replace function timetable_conflicts(p_term_id uuid)
returns table (
  class_section_id uuid,
  label            text,
  day_of_week      smallint,
  period_from      smallint,
  period_to        smallint,
  kind             text,
  message_th       text
) language sql stable as $$
  select st.class_section_id,
         (c.code || ' ' || coalesce(cs.section_no, '-'))::text,
         st.day_of_week, st.period_from, st.period_to,
         cf.kind, cf.message_th
    from section_timeslot st
    join class_section cs on cs.id = st.class_section_id
    join course c         on c.id  = cs.course_id
    cross join lateral timeslot_conflicts(
      st.class_section_id, st.day_of_week, st.period_from, st.period_to,
      st.room_id, st.id) cf
   where cs.term_id = p_term_id
   order by st.day_of_week, st.period_from, c.code;
$$;

comment on function timetable_conflicts(uuid) is
  'การชนทั้งหมดในตารางของภาคเรียน — เปิดดูหลังจัดเสร็จหรือหลังมีคนแก้ตารางเอง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table room enable row level security;
alter table room force  row level security;
create policy tenant_isolation on room
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

alter table timetable_policy enable row level security;
alter table timetable_policy force  row level security;
create policy tenant_isolation on timetable_policy
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0035_hr.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0035_hr.sql
--
-- งานบุคลากร — โครงสร้างหน่วยงาน ระเบียนบุคลากร (ทช.1) การลา และเวลาทำการ
--
-- ─── สิ่งที่มีอยู่ก่อนไฟล์นี้ ───
-- ตาราง staff เก็บแค่รหัสบุคลากร ประเภทการจ้าง และเลขที่ใบประกอบวิชาชีพ
-- ส่วน staff_role เก็บสิทธิ์ในระบบ ทั้งคู่รวมกันตอบได้แค่ว่า "คนนี้เป็นครู
-- และเข้าถึงอะไรได้บ้าง" ซึ่งไม่ใช่งานบุคลากร
--
-- ตอบไม่ได้ว่าใครสังกัดแผนกไหน ใครเป็นหัวหน้าใคร จบอะไรมา อบรมอะไรไปแล้วบ้าง
-- ลาไปกี่วันในปีนี้ และมาสายกี่ครั้ง ซึ่งเป็นคำถามที่ถูกถามทุกเดือน
--
-- ─── ทำไมประวัติสี่แบบอยู่ตารางเดียว ───
-- ประวัติการศึกษา การทำงาน การอบรม และรางวัล มีรูปร่างเดียวกันหมด —
-- ชื่อเรื่อง หน่วยงาน ช่วงเวลา เอกสารอ้างอิง การแยกเป็นสี่ตารางที่เหมือนกัน
-- จะทำให้ทุก query ที่ประกอบระเบียน ทช.1 ต้อง union สี่ทางตลอดไป
-- โดยไม่ได้อะไรกลับมา
--
-- ─── ทำไมผู้ยื่นใบลาอนุมัติเองไม่ได้ ───
-- หลักเดียวกับคำร้องแก้เกรด (0018) — สิทธิ์อนุมัติที่ใช้กับตัวเองได้ไม่ใช่
-- การอนุมัติ แต่เป็นการประทับตรา และหัวหน้าแผนกทุกคนก็มีสิทธิ์อนุมัติ
-- ถ้าไม่กันไว้ ใบลาของหัวหน้าจะไม่เคยผ่านสายตาใครเลย
--
-- ─── ทำไมการลาที่อนุมัติแล้วซ้อนกันไม่ได้ ───
-- ลาป่วยทับลากิจในวันเดียวกันแปลว่ามีใบใดใบหนึ่งผิด และจำนวนวันลาสะสม
-- จะนับซ้ำ ซึ่งไปโผล่ในรายงานตอนสิ้นปีโดยไม่มีใครสังเกต
-- ใช้ exclusion constraint กันตั้งแต่ระดับฐานข้อมูล (btree_gist มีอยู่แล้ว)
--
-- ─── ทำไมหน่วยงานเป็นต้นไม้ที่กันวงจร ───
-- โครงสร้างการบริหารเป็นลำดับชั้น (วิทยาลัย → ฝ่าย → แผนกวิชา → งาน)
-- ถ้าเผลอตั้งหน่วยงานให้เป็นลูกของตัวเองหรือของลูกตัวเอง ทุก query ที่ไล่
-- สายบังคับบัญชาจะวนไม่รู้จบและทำให้ทั้งระบบค้าง
-- ═══════════════════════════════════════════════════════════════════
begin;

create type department_kind as enum
  ('faculty', 'division', 'department', 'section', 'office');

comment on type department_kind is
  'faculty คณะ · division ฝ่าย · department แผนกวิชา · section งาน · office สำนักงาน';

create type staff_record_kind as enum ('education', 'experience', 'training', 'award');

create type leave_kind as enum
  ('personal', 'sick', 'maternity', 'ordination', 'military', 'training', 'unpaid', 'other');

comment on type leave_kind is
  'ลากิจ · ลาป่วย · ลาคลอด · ลาอุปสมบท · ลาเกณฑ์ทหาร · ลาไปอบรม · ลาไม่รับเงินเดือน · อื่น ๆ';

create type leave_status as enum ('pending', 'approved', 'rejected', 'cancelled');

create type work_attendance_status as enum
  ('present', 'late', 'leave', 'absent', 'holiday', 'off_duty');

-- ───────────────────────────────────────────────────────────────────
-- โครงสร้างหน่วยงาน
-- ───────────────────────────────────────────────────────────────────
create table department (
  id             uuid            primary key default gen_random_uuid(),
  institution_id uuid            not null references institution on delete restrict,
  parent_id      uuid            references department on delete restrict,
  code           text            not null,
  name_th        text            not null,
  kind           department_kind not null default 'department',
  head_staff_id  uuid            references staff on delete set null,
  sort_order     smallint        not null default 0,
  active         boolean         not null default true,
  created_at     timestamptz     not null default now(),
  unique (institution_id, code)
);

comment on table department is
  'หน่วยงานตามโครงสร้างการบริหาร — เป็นต้นไม้ กันวงจรด้วย trigger';

create index department_parent_idx on department (institution_id, parent_id) where active;

-- หน่วยงานที่เป็นลูกของตัวเองทำให้ทุก query ที่ไล่สายบังคับบัญชาวนไม่รู้จบ
create or replace function department_no_cycle() returns trigger
language plpgsql as $$
declare
  v_cur   uuid := new.parent_id;
  v_steps integer := 0;
begin
  if new.parent_id is null then return new; end if;
  if new.parent_id = new.id then
    raise exception 'หน่วยงานเป็นหน่วยงานแม่ของตัวเองไม่ได้';
  end if;

  while v_cur is not null loop
    if v_cur = new.id then
      raise exception 'โครงสร้างหน่วยงานวนกลับมาที่ตัวเอง (%)', new.name_th;
    end if;
    select parent_id into v_cur from department where id = v_cur;

    -- กันวงจรที่มีอยู่แล้วในข้อมูลไม่ให้ทำให้ trigger เองวนไม่รู้จบ
    v_steps := v_steps + 1;
    if v_steps > 50 then
      raise exception 'โครงสร้างหน่วยงานลึกเกิน 50 ชั้น สงสัยว่ามีวงจร';
    end if;
  end loop;

  return new;
end $$;

create trigger department_cycle_guard
  before insert or update of parent_id on department
  for each row execute function department_no_cycle();

-- ───────────────────────────────────────────────────────────────────
-- การสังกัดหน่วยงานและตำแหน่ง
-- ───────────────────────────────────────────────────────────────────
create table staff_assignment (
  id             uuid    primary key default gen_random_uuid(),
  staff_id       uuid    not null references staff on delete restrict,
  department_id  uuid    not null references department on delete restrict,
  position_th    text    not null,
  is_primary     boolean not null default true,
  effective_from date    not null default current_date,
  effective_to   date,
  note           text,
  created_at     timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),

  -- สังกัดหลักซ้อนกันสองที่ในเวลาเดียวกันไม่ได้ — สายบังคับบัญชาจะกำกวม
  -- และรายงานจำนวนคนต่อแผนกจะนับซ้ำ
  constraint staff_assignment_one_primary
    exclude using gist (
      staff_id with =,
      daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&
    ) where (is_primary)
);

create index staff_assignment_dept_idx on staff_assignment (department_id);

-- ───────────────────────────────────────────────────────────────────
-- ระเบียนบุคลากร (ทช.1)
-- ───────────────────────────────────────────────────────────────────
create table staff_record (
  id              uuid              primary key default gen_random_uuid(),
  staff_id        uuid              not null references staff on delete restrict,
  kind            staff_record_kind not null,
  title_th        text              not null,
  organization_th text,
  field_th        text,
  started_on      date,
  ended_on        date,
  hours           numeric(6,1)      check (hours is null or hours >= 0),
  document_no     text,
  note            text,
  created_at      timestamptz       not null default now(),
  check (ended_on is null or started_on is null or ended_on >= started_on)
);

comment on table staff_record is
  'ประวัติการศึกษา การทำงาน การอบรม และรางวัลของบุคลากร — รูปร่างเดียวกันจึงอยู่ตารางเดียว';
comment on column staff_record.hours is
  'จำนวนชั่วโมง ใช้กับการอบรมเพื่อนับชั่วโมงพัฒนาตนเองต่อปี';

create index staff_record_staff_idx on staff_record (staff_id, kind, started_on);

-- ───────────────────────────────────────────────────────────────────
-- บุตรบุคลากร
--
-- funding_kind มี 'staff_child' อยู่แล้วตั้งแต่ 0010 แต่ไม่มีทางรู้ว่าใคร
-- เป็นบุตรของใคร ส่วนลดค่าเทอมบุตรบุคลากรจึงตั้งได้แต่ตรวจสอบไม่ได้ —
-- รูปแบบเดียวกับ fee_schedule.study_year ก่อน 0031
-- ───────────────────────────────────────────────────────────────────
create table staff_child (
  id          uuid    primary key default gen_random_uuid(),
  staff_id    uuid    not null references staff on delete restrict,
  full_name_th text   not null,
  birth_date  date,
  -- ผูกกับนักศึกษาถ้าบุตรเรียนที่วิทยาลัยนี้ ซึ่งเป็นกรณีที่ต้องใช้สิทธิ์
  student_id  uuid    references student on delete restrict,
  note        text,
  created_at  timestamptz not null default now(),
  unique (staff_id, full_name_th, birth_date)
);

create unique index staff_child_student_uniq
  on staff_child (student_id) where student_id is not null;

comment on table staff_child is
  'บุตรบุคลากร — ทำให้ส่วนลดค่าเทอมประเภท staff_child ตรวจสอบย้อนหลังได้ว่าใครมีสิทธิ์จริง';

-- ───────────────────────────────────────────────────────────────────
-- การลา
-- ───────────────────────────────────────────────────────────────────
create table staff_leave (
  id             uuid         primary key default gen_random_uuid(),
  institution_id uuid         not null references institution on delete restrict,
  staff_id       uuid         not null references staff on delete restrict,
  kind           leave_kind   not null,
  from_date      date         not null,
  to_date        date         not null,
  days           numeric(4,1) not null check (days > 0),
  reason         text         not null,
  document_no    text,
  status         leave_status not null default 'pending',
  requested_by   uuid         references person on delete restrict,
  requested_at   timestamptz  not null default now(),
  decided_by     uuid         references person on delete restrict,
  decided_at     timestamptz,
  decision_note  text,
  check (to_date >= from_date),

  -- ใบลาที่อนุมัติแล้วซ้อนกันแปลว่ามีใบใดใบหนึ่งผิด และวันลาสะสมจะนับซ้ำ
  constraint staff_leave_no_overlap
    exclude using gist (
      staff_id with =,
      daterange(from_date, to_date, '[]') with &&
    ) where (status = 'approved')
);

create index staff_leave_staff_idx on staff_leave (staff_id, from_date);
create index staff_leave_pending_idx on staff_leave (institution_id, status)
  where status = 'pending';

-- ผู้ยื่นอนุมัติใบลาของตัวเองไม่ได้ — หลักเดียวกับคำร้องแก้เกรด (0018)
create or replace function staff_leave_guard() returns trigger
language plpgsql as $$
declare
  v_owner uuid;
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status in ('approved', 'rejected') then
    if new.decided_by is null then
      raise exception 'การอนุมัติหรือไม่อนุมัติใบลาต้องระบุผู้ตัดสิน';
    end if;

    select s.person_id into v_owner from staff s where s.id = new.staff_id;

    if new.decided_by = v_owner then
      raise exception 'ผู้ยื่นใบลาอนุมัติใบลาของตัวเองไม่ได้';
    end if;
    if new.decided_by = new.requested_by then
      raise exception 'ผู้ยื่นคำขออนุมัติเองไม่ได้ ต้องให้ผู้บังคับบัญชาเป็นผู้ตัดสิน';
    end if;

    new.decided_at := coalesce(new.decided_at, now());
  end if;

  if old.status in ('approved', 'rejected') and new.status = 'pending' then
    raise exception 'ใบลาที่ตัดสินไปแล้วย้อนกลับเป็นรออนุมัติไม่ได้';
  end if;

  return new;
end $$;

create trigger staff_leave_dual_control
  before update on staff_leave
  for each row execute function staff_leave_guard();

-- ───────────────────────────────────────────────────────────────────
-- เวลาทำการรายวัน
-- ───────────────────────────────────────────────────────────────────
create table staff_attendance (
  id             uuid                   primary key default gen_random_uuid(),
  institution_id uuid                   not null references institution on delete restrict,
  staff_id       uuid                   not null references staff on delete restrict,
  on_date        date                   not null,
  status         work_attendance_status not null,
  check_in       time,
  check_out      time,
  note           text,
  recorded_at    timestamptz            not null default now(),
  unique (staff_id, on_date),
  check (check_out is null or check_in is null or check_out >= check_in)
);

create index staff_attendance_date_idx on staff_attendance (institution_id, on_date);

-- ───────────────────────────────────────────────────────────────────
-- โครงสร้างหน่วยงานแบบต้นไม้
-- ───────────────────────────────────────────────────────────────────
create or replace function department_tree()
returns table (
  id        uuid,
  parent_id uuid,
  code      text,
  name_th   text,
  kind      department_kind,
  depth     integer,
  path_th   text,
  head_name text,
  staff_count integer
) language sql stable as $$
  with recursive tree as (
    select d.id, d.parent_id, d.code, d.name_th, d.kind, d.sort_order,
           0 as depth, d.name_th as path_th
      from department d
     where d.parent_id is null and d.active
    union all
    select d.id, d.parent_id, d.code, d.name_th, d.kind, d.sort_order,
           t.depth + 1, t.path_th || ' › ' || d.name_th
      from department d
      join tree t on t.id = d.parent_id
     where d.active
  )
  select t.id, t.parent_id, t.code, t.name_th, t.kind, t.depth, t.path_th,
         trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
              || ' ' || coalesce(p.last_name_th, '')),
         (select count(*) from staff_assignment sa
           where sa.department_id = t.id
             and sa.is_primary
             and (sa.effective_to is null or sa.effective_to >= current_date))::integer
    from tree t
    left join department d2 on d2.id = t.id
    left join staff s       on s.id  = d2.head_staff_id
    left join person p      on p.id  = s.person_id
   order by t.path_th;
$$;

comment on function department_tree() is
  'โครงสร้างการบริหารทั้งต้นไม้พร้อมจำนวนคนในแต่ละหน่วยงาน';

-- ───────────────────────────────────────────────────────────────────
-- สรุปเวลาทำการ
--
-- นับจาก staff_attendance เป็นหลัก และเติมวันลาที่อนุมัติแล้วเข้าไป
-- เพราะวันลาที่ได้รับอนุมัติมักไม่มีการสแกนบัตร ถ้านับจากการสแกนอย่างเดียว
-- คนที่ลาถูกต้องจะกลายเป็นขาดงานในรายงาน
-- ───────────────────────────────────────────────────────────────────
create or replace function staff_worktime_summary(p_from date, p_to date)
returns table (
  staff_id    uuid,
  staff_code  text,
  full_name   text,
  department  text,
  present     integer,
  late        integer,
  on_leave    integer,
  absent      integer,
  leave_days  numeric
) language sql stable as $$
  select s.id, s.staff_code,
         trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
              || ' ' || coalesce(p.last_name_th, '')),
         d.name_th,
         count(a.*) filter (where a.status = 'present')::integer,
         count(a.*) filter (where a.status = 'late')::integer,
         count(a.*) filter (where a.status = 'leave')::integer,
         count(a.*) filter (where a.status = 'absent')::integer,
         coalesce((select sum(l.days) from staff_leave l
                    where l.staff_id = s.id
                      and l.status = 'approved'
                      and l.from_date <= p_to and l.to_date >= p_from), 0)
    from staff s
    join person p on p.id = s.person_id
    left join staff_attendance a
           on a.staff_id = s.id and a.on_date between p_from and p_to
    left join lateral (
      select dp.name_th
        from staff_assignment sa
        join department dp on dp.id = sa.department_id
       where sa.staff_id = s.id and sa.is_primary
         and (sa.effective_to is null or sa.effective_to >= current_date)
       limit 1
    ) d on true
   where s.active
   group by s.id, s.staff_code, p.prefix_th, p.first_name_th, p.last_name_th, d.name_th
   order by s.staff_code;
$$;

comment on function staff_worktime_summary(date, date) is
  'สรุปเวลาทำการรายคน — รวมวันลาที่อนุมัติแล้วด้วย มิฉะนั้นคนที่ลาถูกต้องจะกลายเป็นขาดงาน';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['department', 'staff_leave', 'staff_attendance'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- ตารางลูกไม่ได้สืบทอด RLS ผ่านคีย์นอก ต้องมีนโยบายของตัวเอง
do $$
declare t text;
begin
  foreach t in array array['staff_assignment', 'staff_record', 'staff_child'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from staff s
                      where s.id = %I.staff_id
                        and s.institution_id = current_institution_id()))
    $f$, t, t);
  end loop;
end $$;

-- ชั้นที่ 2 — ประวัติบุคลากรและใบลาเป็นข้อมูลส่วนบุคคลของพนักงาน
-- บุคลากรเห็นของตัวเองได้ ส่วนคนอื่นต้องเป็นงานบุคคลหรือผู้บริหาร
create policy staff_leave_scope on staff_leave
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff s
                where s.id = staff_leave.staff_id
                  and s.person_id = current_actor_id())
  );

create policy staff_record_scope on staff_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff s
                where s.id = staff_record.staff_id
                  and s.person_id = current_actor_id())
  );

create policy staff_child_scope on staff_child
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff s
                where s.id = staff_child.staff_id
                  and s.person_id = current_actor_id())
  );

-- โครงสร้างหน่วยงานเปิดให้ทุกบทบาทในวิทยาลัยอ่านได้ เพราะเป็นข้อมูลสาธารณะ
-- ภายในองค์กร และครูต้องรู้ว่าตัวเองสังกัดแผนกไหนและใครเป็นหัวหน้า

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0036_mfa.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0036_mfa.sql
--
-- การยืนยันตัวตนสองชั้นสำหรับบทบาทที่เห็นข้อมูลทั้งวิทยาลัย
--
-- ─── ทำไมบทบาทเหล่านี้ต้องมีชั้นที่สอง ───
-- บัญชี admin และ director เห็นข้อมูลนักศึกษาทั้งวิทยาลัย รวมถึงเลขบัตร
-- ประชาชน ผลคัดกรอง SDQ และบันทึกเยี่ยมบ้าน บัญชีเดียวที่หลุดจึงเท่ากับ
-- ข้อมูลทั้งวิทยาลัยหลุด ซึ่งเข้าเงื่อนไขการแจ้งเหตุละเมิดตาม PDPA
--
-- ─── หน้าที่แบ่งกันอย่างไร ───
-- การคำนวณรหัส TOTP อยู่ที่ชั้นแอป เพราะต้องถอดรหัสความลับด้วยกุญแจที่
-- อยู่นอกฐานข้อมูล (หลักเดียวกับ IP_HASH_SECRET) ถ้าฐานข้อมูลรั่ว
-- ผู้โจมตีต้องไม่ได้ความลับ TOTP ไปด้วย
--
-- ส่วนไฟล์นี้ถือ **สถานะที่ต้องอะตอมมิก** — กันการใช้รหัสซ้ำ นับครั้งที่ผิด
-- และการล็อก สามอย่างนี้อยู่ที่ชั้นแอปไม่ได้ เพราะรันหลาย instance แล้ว
-- ต่างคนต่างนับ
--
-- ─── กับดักที่ระบบ MFA ส่วนใหญ่พลาด — รหัสเดิมใช้ซ้ำได้ ───
-- รหัส TOTP หนึ่งตัวใช้ได้ 30 วินาที ถ้าไม่จำว่าใช้ไปแล้ว ผู้ที่แอบเห็น
-- รหัสบนหน้าจอหรือดักจับได้จะใช้ซ้ำได้ภายในหน้าต่างนั้น ซึ่งเพียงพอ
-- สำหรับการเข้าระบบหนึ่งครั้ง — และไม่มีอาการอะไรให้เห็นเลย
-- last_step จึงบันทึกช่วงเวลาล่าสุดที่ใช้ไปแล้ว และรับเฉพาะช่วงที่ใหม่กว่า
--
-- ─── ทำไมฟังก์ชันตรวจไม่ raise ───
-- หลักเดียวกับ login_rate_status และ consume_password_reset (0021, 0025) —
-- ถ้า raise ฐานข้อมูลจะ rollback ตัวนับครั้งที่ผิดทิ้งทุกครั้ง แล้วเดารหัส
-- หกหลักได้ไม่จำกัดจำนวนครั้ง ซึ่งเดาถูกภายในไม่กี่ชั่วโมง
--
-- ─── ทำไมต้องมีรหัสกู้คืน ───
-- โทรศัพท์หายคือเรื่องปกติ ถ้าไม่มีทางกลับเข้าระบบเลย ทางแก้เดียวคือให้
-- คนอื่นปิด MFA ให้ ซึ่งกลายเป็นช่องที่ใหญ่กว่าตัว MFA เอง
-- รหัสกู้คืนเก็บเป็นค่าแฮชและใช้ได้ครั้งเดียว หลักเดียวกับรหัสรีเซ็ตรหัสผ่าน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- บทบาทที่ต้องยืนยันสองชั้น ตั้งได้รายวิทยาลัย
alter table auth_policy
  add column if not exists require_mfa_roles text[] not null default '{admin,director}';

comment on column auth_policy.require_mfa_roles is
  'บทบาทที่ต้องยืนยันตัวตนสองชั้น — ค่าเริ่มต้นคือบทบาทที่เห็นข้อมูลทั้งวิทยาลัย';

alter table auth_policy
  add column if not exists mfa_max_attempts smallint not null default 5
    check (mfa_max_attempts between 1 and 20);
alter table auth_policy
  add column if not exists mfa_lockout_minutes smallint not null default 15
    check (mfa_lockout_minutes between 1 and 1440);

-- ───────────────────────────────────────────────────────────────────
-- ความลับ TOTP
-- ───────────────────────────────────────────────────────────────────
create table mfa_credential (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  person_id      uuid        not null references person on delete restrict,

  -- เข้ารหัสที่ชั้นแอปด้วยกุญแจนอกฐานข้อมูล ฐานข้อมูลไม่เคยเห็นค่าจริง
  secret_enc     bytea       not null,

  confirmed_at   timestamptz,
  -- ช่วงเวลา TOTP ล่าสุดที่ใช้ไปแล้ว — กันการใช้รหัสเดิมซ้ำ
  last_step      bigint,
  failed_attempts smallint   not null default 0,
  locked_until   timestamptz,
  created_at     timestamptz not null default now(),
  disabled_at    timestamptz,
  disabled_by    uuid        references person on delete restrict,

  unique (person_id)
);

comment on table mfa_credential is
  'ความลับ TOTP ของผู้ใช้หนึ่งคน — ค่าจริงเข้ารหัสด้วยกุญแจนอกฐานข้อมูล';
comment on column mfa_credential.last_step is
  'ช่วงเวลา TOTP ล่าสุดที่ใช้ไปแล้ว รับเฉพาะช่วงที่ใหม่กว่า มิฉะนั้นรหัสที่ถูกแอบเห็นใช้ซ้ำได้';

create index mfa_credential_person_idx on mfa_credential (institution_id, person_id)
  where disabled_at is null;

-- ───────────────────────────────────────────────────────────────────
-- รหัสกู้คืน
-- ───────────────────────────────────────────────────────────────────
create table mfa_recovery_code (
  id            uuid        primary key default gen_random_uuid(),
  credential_id uuid        not null references mfa_credential on delete cascade,
  code_hash     bytea       not null,
  used_at       timestamptz,
  used_ip_hash  bytea,
  created_at    timestamptz not null default now(),
  unique (credential_id, code_hash)
);

comment on table mfa_recovery_code is
  'รหัสกู้คืนใช้ครั้งเดียว เก็บเฉพาะค่าแฮช — หลักเดียวกับรหัสรีเซ็ตรหัสผ่าน (0025)';

-- ───────────────────────────────────────────────────────────────────
-- บทบาทนี้ต้องยืนยันสองชั้นหรือไม่
-- ───────────────────────────────────────────────────────────────────
create or replace function mfa_required_for(p_institution_id uuid, p_role text)
returns boolean language sql stable as $$
  select coalesce(
    (select p_role = any(ap.require_mfa_roles)
       from auth_policy ap where ap.institution_id = p_institution_id),
    p_role in ('admin', 'director'));
$$;

comment on function mfa_required_for(uuid, text) is
  'บทบาทนี้ต้องยืนยันสองชั้นไหม — ค่าเริ่มต้นครอบ admin/director แม้วิทยาลัยยังไม่ได้ตั้งนโยบาย';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจรหัส TOTP
--
-- ชั้นแอปคำนวณว่ารหัสตรงหรือไม่ (p_matched) แล้วส่งช่วงเวลามาให้
-- ฟังก์ชันนี้ตัดสินขั้นสุดท้าย เพราะสามเรื่องนี้ต้องอะตอมมิก —
-- การล็อก การกันใช้ซ้ำ และการนับครั้งที่ผิด
--
-- **ห้าม raise** มิฉะนั้นตัวนับจะถูก rollback แล้วเดารหัสได้ไม่จำกัด
-- ───────────────────────────────────────────────────────────────────
create or replace function mfa_verify_step(
  p_person_id uuid,
  p_step      bigint,
  p_matched   boolean
) returns table (
  ok               boolean,
  reason           text,
  retry_after_secs integer
) language plpgsql as $$
declare
  v_cred    mfa_credential;
  v_max     smallint;
  v_lock    smallint;
begin
  select * into v_cred from mfa_credential
   where person_id = p_person_id and disabled_at is null;

  if v_cred.id is null then
    return query select false, 'ยังไม่ได้ตั้งค่าการยืนยันตัวตนสองชั้น'::text, 0;
    return;
  end if;

  select coalesce(ap.mfa_max_attempts, 5), coalesce(ap.mfa_lockout_minutes, 15)
    into v_max, v_lock
    from auth_policy ap where ap.institution_id = v_cred.institution_id;
  v_max  := coalesce(v_max, 5);
  v_lock := coalesce(v_lock, 15);

  if v_cred.locked_until is not null and v_cred.locked_until > now() then
    return query select false, 'ใส่รหัสผิดหลายครั้ง ถูกระงับชั่วคราว'::text,
      ceil(extract(epoch from (v_cred.locked_until - now())))::integer;
    return;
  end if;

  if not p_matched then
    update mfa_credential
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= v_max then now() + (v_lock || ' minutes')::interval
             else locked_until end
     where id = v_cred.id;

    return query select false, 'รหัสยืนยันไม่ถูกต้อง'::text, 0;
    return;
  end if;

  -- รหัสถูก แต่เป็นช่วงเวลาที่ใช้ไปแล้ว = มีคนดักรหัสมาใช้ซ้ำ
  --
  -- นับเป็นความพยายามที่ผิดด้วย เพราะเจ้าของตัวจริงไม่มีทางส่งรหัสของ
  -- ช่วงเวลาที่ผ่านไปแล้ว — แอปของเขาแสดงรหัสปัจจุบันเสมอ
  if v_cred.last_step is not null and p_step <= v_cred.last_step then
    update mfa_credential
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= v_max then now() + (v_lock || ' minutes')::interval
             else locked_until end
     where id = v_cred.id;

    return query select false, 'รหัสนี้ถูกใช้ไปแล้ว รอรหัสถัดไป'::text, 0;
    return;
  end if;

  update mfa_credential
     set last_step = p_step, failed_attempts = 0, locked_until = null
   where id = v_cred.id;

  return query select true, null::text, 0;
end $$;

comment on function mfa_verify_step(uuid, bigint, boolean) is
  'ตัดสินผลการยืนยันสองชั้น — คุมการล็อก การกันใช้รหัสซ้ำ และตัวนับ ห้าม raise เพราะตัวนับจะถูก rollback';

-- ───────────────────────────────────────────────────────────────────
-- ใช้รหัสกู้คืน
--
-- ค้นจากเจ้าของก่อนแล้วค่อยเทียบค่าแฮช เหตุผลเดียวกับ consume_password_reset —
-- ถ้าค้นจากค่าแฮชตรง ๆ การเดาผิดจะไม่เจอแถวใดเลย แล้วตัวนับไม่ขยับ
-- ───────────────────────────────────────────────────────────────────
create or replace function mfa_consume_recovery(
  p_person_id uuid,
  p_code_hash bytea,
  p_ip_hash   bytea default null
) returns table (
  ok     boolean,
  reason text,
  remaining integer
) language plpgsql as $$
declare
  v_cred mfa_credential;
  v_id   uuid;
  v_max  smallint;
  v_lock smallint;
begin
  select * into v_cred from mfa_credential
   where person_id = p_person_id and disabled_at is null;

  if v_cred.id is null then
    return query select false, 'ยังไม่ได้ตั้งค่าการยืนยันตัวตนสองชั้น'::text, 0;
    return;
  end if;

  select coalesce(ap.mfa_max_attempts, 5), coalesce(ap.mfa_lockout_minutes, 15)
    into v_max, v_lock
    from auth_policy ap where ap.institution_id = v_cred.institution_id;
  v_max  := coalesce(v_max, 5);
  v_lock := coalesce(v_lock, 15);

  if v_cred.locked_until is not null and v_cred.locked_until > now() then
    return query select false, 'ใส่รหัสผิดหลายครั้ง ถูกระงับชั่วคราว'::text, 0;
    return;
  end if;

  select rc.id into v_id
    from mfa_recovery_code rc
   where rc.credential_id = v_cred.id
     and rc.code_hash = p_code_hash
     and rc.used_at is null;

  if v_id is null then
    update mfa_credential
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= v_max then now() + (v_lock || ' minutes')::interval
             else locked_until end
     where id = v_cred.id;

    return query select false, 'รหัสกู้คืนไม่ถูกต้องหรือถูกใช้ไปแล้ว'::text, 0;
    return;
  end if;

  update mfa_recovery_code
     set used_at = now(), used_ip_hash = p_ip_hash
   where id = v_id;

  update mfa_credential
     set failed_attempts = 0, locked_until = null
   where id = v_cred.id;

  return query select true, null::text,
    (select count(*)::integer from mfa_recovery_code rc
      where rc.credential_id = v_cred.id and rc.used_at is null);
end $$;

comment on function mfa_consume_recovery(uuid, bytea, bytea) is
  'ใช้รหัสกู้คืนหนึ่งครั้ง — ใช้ซ้ำไม่ได้ และเดาผิดถูกนับเข้าตัวนับเดียวกับรหัส TOTP';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ตารางนี้ถูกอ่านตอนล็อกอิน ซึ่งบริบทเป็นบทบาท auth เหมือน user_credential
-- ───────────────────────────────────────────────────────────────────
alter table mfa_credential enable row level security;
alter table mfa_credential force  row level security;
create policy tenant_isolation on mfa_credential
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- เจ้าของเห็นและจัดการของตัวเองได้ · admin ปิดให้คนอื่นได้เมื่อโทรศัพท์หาย
-- · บทบาท auth อ่านได้ตอนล็อกอิน
create policy mfa_credential_scope on mfa_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  );

alter table mfa_recovery_code enable row level security;
alter table mfa_recovery_code force  row level security;
create policy tenant_isolation on mfa_recovery_code
  using (exists (select 1 from mfa_credential mc
                  where mc.id = mfa_recovery_code.credential_id
                    and mc.institution_id = current_institution_id()));

create policy mfa_recovery_code_scope on mfa_recovery_code
  as restrictive
  using (
    current_app_role() = 'auth'
    or exists (select 1 from mfa_credential mc
                where mc.id = mfa_recovery_code.credential_id
                  and mc.person_id = current_actor_id())
  );

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0037_provisioning.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0037_provisioning.sql
--
-- เปิดวิทยาลัยใหม่โดยไม่ต้องรัน SQL เอง
--
-- ─── ทำไมข้อนี้บล็อกการขาย ───
-- ก่อนไฟล์นี้ การรับวิทยาลัยใหม่หนึ่งแห่งต้องมีคนเปิด psql แล้ว insert
-- ทีละตาราง — สถานศึกษา นโยบายยืนยันตัวตน นโยบายตารางสอน นโยบายพฤติกรรม
-- ปีการศึกษา และบัญชีผู้ดูแลคนแรก ถ้าลืมสักตาราง ระบบจะทำงานผิดแบบ
-- ที่หาสาเหตุยากมาก (เช่น auth_policy หายไป แล้วบัญชีไม่มีวันถูกล็อก)
--
-- และไม่มีทางขายแบบให้ลูกค้าสมัครเองได้เลยตราบใดที่ต้องมีคนรันคำสั่ง
--
-- ─── ทำไมไม่ตั้งรหัสผ่านให้ผู้ดูแลคนแรก ───
-- หลักเดียวกับ 0025 — คนที่เปิดระบบให้จะรู้รหัสผ่านของผู้ดูแลวิทยาลัย
-- ตั้งแต่วินาทีแรก ซึ่งแปลว่าผู้ให้บริการเข้าถึงข้อมูลของลูกค้าได้
-- โดยที่บันทึกการเข้าถึงจะระบุว่าเป็นฝีมือของผู้ดูแลวิทยาลัย
--
-- ฟังก์ชันนี้จึงสร้าง **บัญชีที่ยังไม่มีรหัสผ่าน** แล้วคืน person_id
-- ให้ชั้นแอปออกรหัสรีเซ็ตผ่านทางเดิม (issueResetCode) ผู้ดูแลตัวจริง
-- เป็นคนตั้งรหัสผ่านเอง และผู้ให้บริการไม่มีวันรู้
--
-- ─── ทำไมเป็นฟังก์ชันเดียวที่ทำทุกอย่าง ───
-- ถ้าแยกเป็นหลายขั้นแล้วขาดกลางทาง จะเหลือวิทยาลัยครึ่ง ๆ กลาง ๆ ที่
-- ล็อกอินได้แต่ทำงานไม่ได้ และไม่มีใครรู้ว่าต้องเติมอะไรบ้าง
-- ทั้งหมดอยู่ในทรานแซกชันเดียว — สำเร็จทั้งหมดหรือไม่เกิดอะไรเลย
--
-- ─── ทำไมฟังก์ชันนี้เป็น security definer ───
-- ทุกตารางในระบบถูก RLS กรองด้วย current_institution_id() ซึ่งตอน
-- เปิดวิทยาลัยใหม่ยังไม่มีค่าให้ตั้ง — วิทยาลัยที่กำลังจะสร้างยังไม่มีอยู่
--
-- นี่เป็นข้อยกเว้นเดียวของหลัก "อย่าใช้ security definer เพื่อเลี่ยงนโยบาย"
-- เพราะไม่ได้เลี่ยงการกรอง แต่เป็นการสร้างขอบเขตใหม่ขึ้นมา ฟังก์ชันจึง
-- **สร้างได้อย่างเดียว** ไม่มีคำสั่ง select/update/delete ที่แตะข้อมูลของ
-- วิทยาลัยที่มีอยู่แล้วเลย และตรวจว่ารหัสสถานศึกษาไม่ซ้ำก่อนเสมอ
-- ═══════════════════════════════════════════════════════════════════
begin;

create table provisioning_log (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  code           text        not null,
  name_th        text        not null,
  admin_person_id uuid       not null references person on delete restrict,
  requested_by   text,
  created_at     timestamptz not null default now()
);

comment on table provisioning_log is
  'ประวัติการเปิดวิทยาลัยใหม่ — ตอบได้ว่าใครเปิดให้ใครเมื่อไร';

-- ไม่เปิด RLS เหมือน institution เพราะเป็นข้อมูลระดับผู้ให้บริการ
-- ไม่ใช่ของวิทยาลัยใด และผู้ใช้ทั่วไปไม่มีทางเข้าถึง (ไม่มี endpoint ให้อ่าน)
alter table provisioning_log enable row level security;
alter table provisioning_log force  row level security;
create policy tenant_isolation on provisioning_log
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- ───────────────────────────────────────────────────────────────────
-- เปิดวิทยาลัยใหม่
-- ───────────────────────────────────────────────────────────────────
create or replace function provision_institution(
  p_code            text,
  p_name_th         text,
  p_admin_prefix_th text,
  p_admin_first_th  text,
  p_admin_last_th   text,
  p_admin_username  text,
  p_year_be         smallint,
  p_year_starts_on  date,
  p_year_ends_on    date,
  p_name_en         text default null,
  p_admin_email     text default null,
  p_admin_phone     text default null,
  p_requested_by    text default null
) returns table (
  institution_id  uuid,
  admin_person_id uuid,
  admin_staff_id  uuid,
  academic_year_id uuid
) language plpgsql security definer set search_path = public as $$
declare
  v_inst   uuid;
  v_person uuid;
  v_staff  uuid;
  v_year   uuid;
begin
  if coalesce(btrim(p_code), '') = '' or coalesce(btrim(p_name_th), '') = '' then
    raise exception 'ต้องระบุรหัสสถานศึกษาและชื่อสถานศึกษา';
  end if;
  if coalesce(btrim(p_admin_username), '') = '' then
    raise exception 'ต้องระบุชื่อผู้ใช้ของผู้ดูแลคนแรก';
  end if;
  if p_year_ends_on <= p_year_starts_on then
    raise exception 'วันสิ้นปีการศึกษาต้องอยู่หลังวันเริ่ม';
  end if;

  if exists (select 1 from institution i where i.code = btrim(p_code)) then
    raise exception 'รหัสสถานศึกษา % ถูกใช้ไปแล้ว', btrim(p_code)
      using errcode = 'unique_violation';
  end if;

  insert into institution (code, name_th, name_en)
  values (btrim(p_code), btrim(p_name_th), nullif(btrim(p_name_en), ''))
  returning id into v_inst;

  -- ── นโยบายพื้นฐาน ──────────────────────────────────────────────
  -- ใช้ค่าเริ่มต้นของแต่ละตาราง การไม่มีแถวเหล่านี้คือสาเหตุของอาการ
  -- ที่หายากที่สุด — บัญชีไม่มีวันถูกล็อก ตารางสอนไม่มีเพดานคาบ
  -- และคะแนนความประพฤติไม่มีค่าตั้งต้น
  insert into auth_policy (institution_id) values (v_inst);
  insert into timetable_policy (institution_id) values (v_inst);
  insert into behavior_policy (institution_id) values (v_inst);

  insert into academic_year (institution_id, year_be, starts_on, ends_on)
  values (v_inst, p_year_be, p_year_starts_on, p_year_ends_on)
  returning id into v_year;

  -- ── ผู้ดูแลคนแรก ───────────────────────────────────────────────
  insert into person
    (institution_id, prefix_th, first_name_th, last_name_th, email, phone)
  values (v_inst, nullif(btrim(p_admin_prefix_th), ''),
          btrim(p_admin_first_th), btrim(p_admin_last_th),
          nullif(btrim(p_admin_email), ''), nullif(btrim(p_admin_phone), ''))
  returning id into v_person;

  insert into staff (institution_id, person_id, staff_code, is_teacher)
  values (v_inst, v_person, 'ADMIN-001', false)
  returning id into v_staff;

  insert into staff_role (staff_id, role, effective_from, granted_by, reason)
  values (v_staff, 'admin', current_date, v_staff,
          'ผู้ดูแลคนแรกที่สร้างพร้อมการเปิดวิทยาลัย');

  -- บัญชีที่ยังไม่มีรหัสผ่าน — ผู้ดูแลตัวจริงตั้งเองผ่านรหัสรีเซ็ต
  --
  -- must_change = true และค่าแฮชเป็นค่าที่เทียบกับอะไรไม่ได้เลย จึงเข้าระบบ
  -- ด้วยรหัสผ่านไม่ได้จนกว่าจะรีเซ็ต ต่างจากการตั้งรหัสชั่วคราวให้ตรงที่
  -- ไม่มีใครนอกจากเจ้าตัวรู้รหัสผ่านได้เลยแม้แต่วินาทีเดียว
  insert into user_credential
    (institution_id, person_id, username, password_hash, must_change)
  values (v_inst, v_person, btrim(p_admin_username),
          'locked$' || encode(gen_random_bytes(32), 'hex'), true);

  insert into provisioning_log
    (institution_id, code, name_th, admin_person_id, requested_by)
  values (v_inst, btrim(p_code), btrim(p_name_th), v_person, p_requested_by);

  return query select v_inst, v_person, v_staff, v_year;
end $$;

comment on function provision_institution is
  'เปิดวิทยาลัยใหม่ทั้งชุดในทรานแซกชันเดียว — สร้างบัญชีผู้ดูแลที่ยังไม่มีรหัสผ่าน ผู้ให้บริการจึงไม่มีวันรู้รหัสของลูกค้า';

-- ให้เฉพาะเจ้าของฐานข้อมูลเรียกได้ ผู้ใช้ของแอปเรียกไม่ได้โดยตรง
-- ชั้นแอปเข้าถึงผ่าน ADMIN_DATABASE_URL ซึ่งใช้เฉพาะเส้นทางเปิดวิทยาลัย
revoke execute on function provision_institution from public;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0038_plans_and_quota.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0038_plans_and_quota.sql
--
-- แพ็กเกจ โควตา และการวัดปริมาณใช้งานรายวิทยาลัย
--
-- ─── ทำไมข้อนี้บล็อกการขาย ───
-- ก่อนไฟล์นี้ไม่มีอะไรบอกได้เลยว่าวิทยาลัยหนึ่งซื้ออะไรไว้ ใช้ไปเท่าไร
-- และเกินที่ซื้อหรือยัง การออกใบเรียกเก็บเงินจึงต้องเดาจากการนับมือ
-- และไม่มีทางขายแบบคิดตามจำนวนนักศึกษาได้เลย
--
-- ─── ทำไมแยกจากระบบการเงินของวิทยาลัยเด็ดขาด ───
-- invoice/payment ในระบบนี้คือ **นักศึกษาจ่ายให้วิทยาลัย** ส่วนตารางในไฟล์นี้
-- คือ **วิทยาลัยจ่ายให้ผู้ให้บริการ** ถ้าปนกัน งานการเงินของวิทยาลัยจะเห็น
-- และแก้ยอดที่วิทยาลัยต้องจ่ายผู้ให้บริการได้ ซึ่งเป็นคนละสัญญากันคนละคู่
--
-- ─── ทำไมโควตาแบบ soft เป็นค่าเริ่มต้น ───
-- การบล็อกไม่ให้รับนักศึกษาเพิ่มกลางภาคเรียนเพราะเกินโควตาสิบคน แปลว่า
-- งานทะเบียนทำงานไม่ได้ทั้งวิทยาลัย ซึ่งเสียหายกับลูกค้ามากกว่ามูลค่าที่
-- ผู้ให้บริการจะได้เพิ่ม และเป็นวิธีที่ทำให้ลูกค้าเลิกใช้
--
-- ค่าเริ่มต้นจึงเป็น soft — เกินได้แต่ขึ้นในรายงานให้ทั้งสองฝ่ายเห็น
-- ส่วน hard มีไว้สำหรับกรณีที่ตกลงกันแล้วว่าจะบังคับ และยังมี grace_percent
-- กันการล็อกเพราะเกินไปคนสองคน
--
-- ─── ทำไมกฎโควตาเป็น trigger ไม่ใช่การตรวจในชั้น API ───
-- นักศึกษาเข้าระบบได้สามทาง — รับสมัคร (0033) นำเข้าข้อมูล (0023) และ
-- สคริปต์ย้ายข้อมูล ถ้าตรวจที่ชั้น API สองทางหลังจะข้ามได้ทั้งคู่
--
-- ─── ทำไม take_usage_snapshot ไม่ใช่ security definer ───
-- มันนับข้อมูลของวิทยาลัยเดียวและต้องถูก RLS กรองตามปกติ งานเบื้องหลัง
-- วนเรียกทีละวิทยาลัยพร้อมตั้งบริบทเอง — การทำเป็น security definer
-- เพื่อความสะดวกจะเปิดทางให้อ่านข้ามวิทยาลัยได้โดยไม่จำเป็น
-- ═══════════════════════════════════════════════════════════════════
begin;

create type plan_enforcement as enum ('soft', 'hard');

comment on type plan_enforcement is
  'soft = เกินได้แต่ขึ้นรายงาน · hard = เกินแล้วรับนักศึกษาเพิ่มไม่ได้';

create type subscription_status as enum
  ('trial', 'active', 'past_due', 'suspended', 'cancelled');

-- ───────────────────────────────────────────────────────────────────
-- แพ็กเกจ — รายการสินค้าของผู้ให้บริการ ไม่ใช่ข้อมูลของวิทยาลัยใด
-- ───────────────────────────────────────────────────────────────────
create table plan (
  id                uuid             primary key default gen_random_uuid(),
  code              text             not null unique,
  name_th           text             not null,
  max_students      integer          check (max_students is null or max_students > 0),
  max_staff         integer          check (max_staff is null or max_staff > 0),
  price_per_year    numeric(12,2)    not null default 0 check (price_per_year >= 0),
  price_per_student numeric(9,2)     not null default 0 check (price_per_student >= 0),
  enforcement       plan_enforcement not null default 'soft',
  grace_percent     smallint         not null default 10 check (grace_percent between 0 and 100),
  features          jsonb            not null default '{}'::jsonb,
  active            boolean          not null default true,
  sort_order        smallint         not null default 0
);

comment on column plan.max_students is
  'จำนวนนักศึกษาที่ยังศึกษาอยู่ที่แพ็กเกจครอบ — null คือไม่จำกัด';
comment on column plan.grace_percent is
  'ผ่อนผันกี่เปอร์เซ็นต์ก่อนบังคับจริง กันการล็อกทั้งวิทยาลัยเพราะเกินไปคนสองคน';

-- ───────────────────────────────────────────────────────────────────
-- สัญญาของแต่ละวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
create table institution_subscription (
  id              uuid                primary key default gen_random_uuid(),
  institution_id  uuid                not null references institution on delete restrict,
  plan_id         uuid                not null references plan on delete restrict,
  starts_on       date                not null,
  ends_on         date,
  status          subscription_status not null default 'trial',
  -- ที่นั่งที่ซื้อเพิ่มจากที่แพ็กเกจให้มา
  seats_purchased integer             not null default 0 check (seats_purchased >= 0),
  note            text,
  created_at      timestamptz         not null default now(),
  check (ends_on is null or ends_on >= starts_on),

  -- สัญญาสองฉบับซ้อนช่วงเวลากันแปลว่าไม่มีทางรู้ว่าตอนนี้ใช้แพ็กเกจไหน
  constraint institution_subscription_no_overlap
    exclude using gist (
      institution_id with =,
      daterange(starts_on, coalesce(ends_on, 'infinity'::date), '[]') with &&
    )
);

create index institution_subscription_active_idx
  on institution_subscription (institution_id, status);

-- ───────────────────────────────────────────────────────────────────
-- การวัดปริมาณใช้งาน
--
-- เก็บเป็นภาพนิ่งรายวัน ไม่ใช่คำนวณย้อนหลังตอนออกใบเรียกเก็บ เพราะ
-- จำนวนนักศึกษาเปลี่ยนทุกวัน การคำนวณย้อนหลังจะได้ตัวเลขคนละอย่าง
-- ทุกครั้งที่คำนวณ แล้วเถียงกับลูกค้าไม่จบ
-- ───────────────────────────────────────────────────────────────────
create table usage_snapshot (
  id               uuid    primary key default gen_random_uuid(),
  institution_id   uuid    not null references institution on delete restrict,
  taken_on         date    not null default current_date,
  students_active  integer not null,
  staff_active     integer not null,
  documents_issued integer not null default 0,
  applications     integer not null default 0,
  taken_at         timestamptz not null default now(),
  unique (institution_id, taken_on)
);

comment on table usage_snapshot is
  'ภาพนิ่งปริมาณใช้งานรายวัน — เป็นหลักฐานการเรียกเก็บที่ตรวจย้อนหลังได้ ไม่ใช่คำนวณใหม่ทุกครั้ง';

-- ───────────────────────────────────────────────────────────────────
-- แพ็กเกจที่ใช้อยู่จริงของวิทยาลัยหนึ่ง ณ วันนี้
-- ───────────────────────────────────────────────────────────────────
create or replace function active_plan(p_institution_id uuid)
returns table (
  subscription_id uuid,
  plan_id         uuid,
  plan_code       text,
  plan_name_th    text,
  status          subscription_status,
  max_students    integer,
  max_staff       integer,
  enforcement     plan_enforcement,
  grace_percent   smallint,
  seats_purchased integer
) language sql stable as $$
  select s.id, p.id, p.code, p.name_th, s.status,
         p.max_students, p.max_staff, p.enforcement, p.grace_percent, s.seats_purchased
    from institution_subscription s
    join plan p on p.id = s.plan_id
   where s.institution_id = p_institution_id
     and s.status in ('trial', 'active', 'past_due')
     and s.starts_on <= current_date
     and (s.ends_on is null or s.ends_on >= current_date)
   order by s.starts_on desc
   limit 1;
$$;

comment on function active_plan(uuid) is
  'แพ็กเกจที่บังคับใช้อยู่ ณ วันนี้ — suspended และ cancelled ไม่นับ';

-- ───────────────────────────────────────────────────────────────────
-- ปริมาณใช้งานปัจจุบันเทียบกับที่ซื้อไว้
-- ───────────────────────────────────────────────────────────────────
create or replace function institution_usage(p_institution_id uuid)
returns table (
  plan_code        text,
  plan_name_th     text,
  status           subscription_status,
  enforcement      plan_enforcement,
  students_active  integer,
  students_limit   integer,
  students_allowed integer,
  over_students    integer,
  staff_active     integer,
  staff_limit      integer
) language sql stable as $$
  with ap as (select * from active_plan(p_institution_id)),
  counts as (
    select
      (select count(*) from student s
        where s.institution_id = p_institution_id and s.status = 'active')::integer as students,
      (select count(*) from staff st
        where st.institution_id = p_institution_id and st.active)::integer as staff
  )
  select ap.plan_code, ap.plan_name_th, ap.status, ap.enforcement,
         c.students,
         case when ap.max_students is null then null
              else ap.max_students + coalesce(ap.seats_purchased, 0) end,
         case when ap.max_students is null then null
              else floor((ap.max_students + coalesce(ap.seats_purchased, 0))
                         * (1 + ap.grace_percent / 100.0))::integer end,
         case when ap.max_students is null then 0
              else greatest(0, c.students
                     - (ap.max_students + coalesce(ap.seats_purchased, 0))) end,
         c.staff,
         ap.max_staff
    from counts c
    left join ap on true;
$$;

comment on function institution_usage(uuid) is
  'ใช้ไปเท่าไรเทียบกับที่ซื้อไว้ — students_allowed คือเพดานหลังรวมการผ่อนผันแล้ว';

-- ───────────────────────────────────────────────────────────────────
-- โควตานักศึกษา
--
-- ตรวจตอนเพิ่มคนใหม่และตอนเปลี่ยนสถานะกลับมาเป็นกำลังศึกษา ซึ่งเป็น
-- สองทางเดียวที่ทำให้จำนวนที่นับเพิ่มขึ้น
--
-- ข้อความต้องบอกว่าต้องทำอะไรต่อ ไม่ใช่แค่ว่าเกินโควตา — คนที่เจอข้อความนี้
-- คือเจ้าหน้าที่งานทะเบียนที่มีนักศึกษายืนรออยู่ตรงหน้า
-- ───────────────────────────────────────────────────────────────────
create or replace function student_quota_guard() returns trigger
language plpgsql as $$
declare
  u record;
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'active' then
    return new;
  end if;

  select * into u from institution_usage(new.institution_id);

  -- ไม่มีสัญญา = ยังไม่ได้ผูกแพ็กเกจ ไม่บังคับอะไร
  -- (วิทยาลัยที่ใช้อยู่ก่อนไฟล์นี้ต้องไม่ถูกล็อกทันทีที่ deploy)
  if u.plan_code is null or u.students_allowed is null then
    return new;
  end if;

  if u.enforcement = 'hard' and u.students_active >= u.students_allowed then
    raise exception
      'รับนักศึกษาเพิ่มไม่ได้ — แพ็กเกจ % ครอบ % คน ใช้ไปแล้ว % คน (ผ่อนผันถึง % คน) ต้องเพิ่มที่นั่งก่อน',
      u.plan_name_th, u.students_limit, u.students_active, u.students_allowed
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

create trigger student_quota_check
  before insert or update of status on student
  for each row execute function student_quota_guard();

-- ───────────────────────────────────────────────────────────────────
-- เก็บภาพนิ่งปริมาณใช้งานของวิทยาลัยหนึ่ง
--
-- เก็บซ้ำวันเดิมได้ ถือเป็นการแก้ไขภาพของวันนั้น ไม่ใช่ความผิดพลาด
-- ───────────────────────────────────────────────────────────────────
create or replace function take_usage_snapshot(p_institution_id uuid)
returns usage_snapshot language plpgsql as $$
declare
  u   record;
  row usage_snapshot;
begin
  select * into u from institution_usage(p_institution_id);

  insert into usage_snapshot
    (institution_id, taken_on, students_active, staff_active,
     documents_issued, applications)
  values (
    p_institution_id, current_date,
    coalesce(u.students_active, 0),
    coalesce(u.staff_active, 0),
    (select count(*) from issued_document d
      where d.institution_id = p_institution_id and d.voided_at is null),
    (select count(*) from application a
      where a.institution_id = p_institution_id and a.status <> 'draft'))
  on conflict (institution_id, taken_on) do update
    set students_active  = excluded.students_active,
        staff_active     = excluded.staff_active,
        documents_issued = excluded.documents_issued,
        applications     = excluded.applications,
        taken_at         = now()
  returning * into row;

  return row;
end $$;

comment on function take_usage_snapshot(uuid) is
  'เก็บภาพนิ่งปริมาณใช้งานของวันนี้ — ไม่ใช่ security definer โดยตั้งใจ ต้องถูก RLS กรองตามบริบทที่เรียก';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────

-- plan เป็นรายการสินค้าของผู้ให้บริการ ทุกวิทยาลัยอ่านได้ (ต้องรู้ว่ามี
-- แพ็กเกจอะไรให้อัปเกรด) แต่แก้ไม่ได้ — การเขียนทำได้เฉพาะเมื่อไม่มีบริบท
-- วิทยาลัย ซึ่งคือเส้นทางของผู้ให้บริการเท่านั้น
alter table plan enable row level security;
alter table plan force  row level security;
create policy plan_readable on plan
  using (true)
  with check (current_institution_id() is null);

-- สัญญาและปริมาณใช้งาน — วิทยาลัยเห็นของตัวเอง แต่แก้ไม่ได้
-- (จะแก้โควตาของตัวเองได้ก็เท่ากับซื้อแพ็กเกจฟรี)
alter table institution_subscription enable row level security;
alter table institution_subscription force  row level security;
create policy tenant_isolation on institution_subscription
  using (institution_id = current_institution_id()
         or current_institution_id() is null)
  with check (current_institution_id() is null);

alter table usage_snapshot enable row level security;
alter table usage_snapshot force  row level security;
create policy tenant_isolation on usage_snapshot
  using (institution_id = current_institution_id()
         or current_institution_id() is null)
  -- ต่างจากสัญญา — งานเบื้องหลังเก็บภาพนิ่งในบริบทของวิทยาลัยนั้นเอง
  with check (institution_id = current_institution_id()
              or current_institution_id() is null);

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0039_attendance_write_scope.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0039_attendance_write_scope.sql
--
-- ปิดช่องที่นักศึกษาแก้เวลาเรียนของตัวเองได้
--
-- ─── อาการที่เกิดขึ้นจริง ───
-- นักศึกษาเรียก POST /attendance/meetings/:id ด้วย enrollment ของตัวเอง
-- แล้วเปลี่ยน "ขาดเรียน" เป็น "มาเรียน" ได้สำเร็จ ทดสอบแล้วได้ผลดังนี้
--
--   ก่อน  pct_to_date 50.00 · absences_left 6 · attendance_state 'warning'
--   หลัง  pct_to_date 100.00 · absences_left 8 · attendance_state 'ok'
--
-- หา meeting_id ครบทุกคาบได้จาก GET /students/:id/schedule ของตัวเอง
-- แล้ววนยิงทีละคาบ กฎเวลาเรียน 80% จึงไม่มีผลกับใครที่รู้วิธีนี้เลย
-- และลบแถวการเช็คชื่อของตัวเองทิ้งได้ด้วย
--
-- ─── ต้นเหตุ — กฎของ PostgreSQL ที่มองข้ามได้ง่ายที่สุด ───
-- policy ที่เขียน `using` ไว้แต่ไม่เขียน `with check` PostgreSQL จะเอา
-- `using` **มาใช้เป็น `with check` ให้เอง** สิทธิ์ที่ตั้งใจให้ "อ่านของตัวเอง"
-- จึงกลายเป็นสิทธิ์ "เขียนของตัวเอง" โดยไม่มีใครเขียนบรรทัดไหนอนุญาต
--
--   attendance_scope (0012) ... or enrollment_id in (actor_enrollment_ids())
--   meeting_scope    (0017) ... or class_section_id in (actor_section_ids())
--
-- ทั้งสองประโยคเขียนไว้ให้นักศึกษา**ดู**เวลาเรียนและตารางของตัวเองได้
--
-- ─── ทำไมคาบเรียนต้องแก้ด้วย ───
-- ตัวบันทึกการเช็คชื่อปิดคาบให้อัตโนมัติ (status = 'held') ซึ่งเพิ่ม
-- ตัวหารของกฎ 80% ให้ **ทุกคน** ในกลุ่มเรียน นักศึกษาคนเดียวจึงยิงคาบที่
-- ยังไม่ถึงกำหนดเพื่อกดเปอร์เซ็นต์ของเพื่อนทั้งห้องให้ต่ำกว่าเกณฑ์ได้
-- (ทดสอบแล้ว — B ยิงหนึ่งคาบ periods_held ของ A ขยับจาก 2 เป็น 4)
--
-- ─── ทำไม with check อย่างเดียวไม่พอ ───
-- `with check` มีผลกับ insert และ update เท่านั้น **delete ไม่มี with check**
-- PostgreSQL ใช้ `using` ตัดสิน delete ล้วน ๆ ถ้าไม่เพิ่มนโยบายเฉพาะ
-- นักศึกษาจะยังลบแถวของตัวเองทิ้งได้ ซึ่งได้ผลเหมือนแก้เป็นมาเรียน
-- (แถวที่ไม่มี = ไม่ถูกนับเป็นขาด) จึงต้องมีนโยบาย for delete แยกอีกตัว
--
-- ─── ขอบเขตของไฟล์นี้ ───
-- ปิดเฉพาะเส้นทางเขียนเวลาเรียน ซึ่งเป็นจุดเดียวที่มี endpoint ให้นักศึกษา
-- เรียกถึงได้จริง รูปแบบ using-ไม่มี-with-check ยังมีอยู่อีกหลายสิบตาราง
-- (ดู TEST 183 ที่นับไว้ให้) ตารางเหล่านั้นยังกันด้วย @Roles ที่ชั้น API
-- ชั้นเดียว ซึ่งขัดกับหลักข้อ 1 ที่ว่าฐานข้อมูลเป็นเจ้าของกฎ — ต้องตามปิดต่อ
--
-- ─── ถ้าวันหน้าทำ A-05 ให้นักศึกษาเช็คอินเอง ───
-- ห้ามแก้ด้วยการเอาประโยค actor_enrollment_ids() กลับเข้า with check
-- เพราะนั่นคือการเปิดช่องนี้คืน ให้ทำเป็นตารางคำขอเช็คอินแยกที่ครูยืนยัน
-- แล้วค่อยกลายเป็น attendance_record — คนถูกเช็คต้องไม่ใช่คนเขียนผลเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- การเช็คชื่อ — อ่านของตัวเองได้ แต่เขียนได้เฉพาะครูผู้สอนและงานส่วนกลาง
-- ───────────────────────────────────────────────────────────────────
drop policy if exists attendance_scope on attendance_record;

create policy attendance_scope on attendance_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
    -- นักศึกษาและผู้ปกครองที่ยืนยันแล้ว — **อ่านอย่างเดียว**
    -- ประโยคนี้ต้องไม่ปรากฏใน with check ด้านล่างเด็ดขาด
    or attendance_record.enrollment_id in (select actor_enrollment_ids())
  )
  with check (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
  );

-- delete ไม่ผ่าน with check จึงต้องมีนโยบายของตัวเอง
create policy attendance_no_subject_delete on attendance_record
  as restrictive for delete
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
  );

comment on policy attendance_scope on attendance_record is
  'เจ้าของอ่านได้ แต่เขียนได้เฉพาะครูผู้สอนและงานส่วนกลาง — with check ต้องไม่มีประโยคของเจ้าของ';

-- ───────────────────────────────────────────────────────────────────
-- คาบเรียน — นักศึกษาเห็นตารางของตัวเอง แต่ปิดคาบเองไม่ได้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists meeting_scope on class_meeting;

create policy meeting_scope on class_meeting
  as restrictive
  using (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
    -- นักศึกษาที่ลงทะเบียนในกลุ่มนี้ — **อ่านอย่างเดียว**
    or class_meeting.class_section_id in (select actor_section_ids())
  )
  with check (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
  );

create policy meeting_no_student_delete on class_meeting
  as restrictive for delete
  using (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
  );

comment on policy meeting_scope on class_meeting is
  'นักศึกษาเห็นตารางของตัวเอง แต่ปิดคาบไม่ได้ — การปิดคาบเพิ่มตัวหารกฎ 80% ให้ทั้งห้อง';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0040_platform_admin.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0040_platform_admin.sql
--
-- ผู้ดูแลระดับผู้ให้บริการ — ผู้ใช้ที่ไม่ได้อยู่ในวิทยาลัยไหนเลย
--
-- ─── ทำไมข้อนี้บล็อกการขาย ───
-- ทุกบทบาทในระบบนี้อยู่ **ภายใน** วิทยาลัยหนึ่ง ๆ — admin ของวิทยาลัย ก
-- ไม่มีความหมายในวิทยาลัย ข งานของผู้ให้บริการ (เปิดวิทยาลัยใหม่ ผูกแพ็กเกจ
-- ดูปริมาณใช้งานเพื่อออกใบเรียกเก็บ ระงับลูกค้าที่ไม่ชำระ) จึงไม่มีบทบาทไหน
-- ที่ถูกต้องจะใช้ได้เลย
--
-- ทางที่ใช้อยู่ก่อนไฟล์นี้คือความลับระดับการติดตั้ง (PROVISION_KEY ใน 0037)
-- ซึ่งพอสำหรับคนเดียวที่ถือกุญแจ แต่ขายจริงไม่ได้ เพราะ
--   · กุญแจเดียวใช้ร่วมกันทั้งทีม ตอบไม่ได้ว่าใครเปิดวิทยาลัยให้ใคร
--   · เพิกถอนสิทธิ์คนที่ลาออกไม่ได้ ต้องเปลี่ยนกุญแจแล้วแจ้งใหม่ทั้งทีม
--   · แบ่งหน้าที่ไม่ได้ คนดูแลใบเรียกเก็บกับคนตอบปัญหาลูกค้าได้สิทธิ์เท่ากัน
--
-- ─── หลักที่ห้ามละเมิดของไฟล์นี้ — ผู้ให้บริการต้องไม่เห็นข้อมูลนักศึกษา ───
-- ข้อมูลชุดนี้มีเลขบัตรประชาชน ข้อมูลผู้เยาว์ ผลคัดกรอง SDQ และบันทึก
-- เยี่ยมบ้าน ผู้ให้บริการเป็นผู้ประมวลผลข้อมูลตาม PDPA ไม่ใช่เจ้าของข้อมูล
-- การเปิดหน้าจอข้ามวิทยาลัยแบบเห็นทุกอย่างคือการสร้างบัญชีที่ดูดข้อมูล
-- ของทุกวิทยาลัยได้จากที่เดียว ซึ่งเป็นสิ่งที่ระบบทั้งระบบพยายามกันมาตลอด
--
-- กำแพงจึงไม่ได้อยู่ที่ "ไม่มี endpoint ให้เรียก" แต่อยู่ที่ **บริบทของ
-- ผู้ให้บริการไม่มีวิทยาลัย** — RLS ชั้นที่ 1 ของทุกตารางเทียบ
-- `institution_id = current_institution_id()` เมื่อค่านั้นเป็น null
-- ทุกตารางคืนศูนย์แถวโดยอัตโนมัติ ไม่ต้องเขียนกฎเพิ่มสักข้อ
--
-- ตารางที่ผู้ให้บริการเห็นจึงมีเท่าที่เปิดไว้อย่างจงใจใน 0038 เท่านั้น
-- (plan · institution_subscription · usage_snapshot) บวก institution
-- ซึ่งมีแค่รหัสกับชื่อสถานศึกษา — ไม่มีข้อมูลส่วนบุคคลเลยสักช่อง
-- เทสต์ TEST 186 ยิงจริงทุกตารางที่มีข้อมูลส่วนบุคคลเพื่อยืนยันข้อนี้
--
-- ─── ทำไมผู้ให้บริการออกรหัสรีเซ็ตให้ผู้ใช้ของวิทยาลัยไม่ได้ ───
-- ถ้าออกได้ ประตูหลังจะเปิดทันที — ออกรหัสรีเซ็ตให้ admin ของวิทยาลัย
-- ตั้งรหัสผ่านใหม่ แล้วเข้าไปในบริบทของวิทยาลัยนั้นเต็มสิทธิ์ กำแพง
-- ข้างบนทั้งหมดจะไม่มีความหมายอะไรเลย
--
-- ข้อยกเว้นเดียวคือ **ผู้ดูแลคนแรกตอนเปิดวิทยาลัย** (0037) ซึ่งเลี่ยงไม่ได้
-- เพราะยังไม่มีใครในวิทยาลัยนั้นให้ออกรหัสให้ และรหัสนั้นใช้ได้ครั้งเดียว
-- มีอายุสั้น และการเปิดวิทยาลัยทุกครั้งถูกบันทึกไว้ว่าใครเป็นคนทำ
--
-- ─── ทำไมการระงับเป็นการปิดทางเข้า ไม่ใช่การลบหรือซ่อนข้อมูล ───
-- ลูกค้าที่ค้างชำระยังเป็นเจ้าของข้อมูลของตัวเองอยู่ การลบหรือทำให้อ่าน
-- ไม่ได้คือการยึดข้อมูลของเจ้าของไปเป็นตัวประกัน ซึ่งผิดทั้งทางกฎหมาย
-- และทางธุรกิจ การระงับจึงห้ามแค่ **การสร้าง session ใหม่** ข้อมูลทุกแถว
-- ยังอยู่ครบ ส่งออกได้ และกลับมาใช้ได้ทันทีที่ปลดระงับ
--
-- และการระงับต้องเป็นการกระทำที่มีคนกดเท่านั้น ห้ามผูกกับสถานะสัญญา
-- ให้เกิดเองอัตโนมัติ — บั๊กในการคิดเงินหนึ่งตัวจะกลายเป็นวิทยาลัย
-- ทั้งประเทศเข้าระบบไม่ได้พร้อมกันตอนเช้าวันจันทร์ (หลักเดียวกับ 5ข)
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บทบาทของฝั่งผู้ให้บริการ
--
-- แยกสามระดับเพราะงานสามอย่างนี้ความเสี่ยงต่างกันมาก — คนตอบปัญหาลูกค้า
-- ต้องเปิดดูได้ว่าวิทยาลัยไหนใช้แพ็กเกจอะไร แต่ไม่ควรระงับใครได้
-- ───────────────────────────────────────────────────────────────────
create type platform_role as enum ('owner', 'billing', 'support');

comment on type platform_role is
  'owner = ดูแลบัญชีผู้ให้บริการด้วยกันเองได้ · billing = แพ็กเกจ สัญญา ระงับ/ปลดระงับ · support = อ่านอย่างเดียว';

-- ───────────────────────────────────────────────────────────────────
-- บัญชีของผู้ให้บริการ
--
-- ─── ทำไมไม่ใช้ตาราง person/user_credential เดิม ───
-- ทั้งสองตารางมี institution_id แบบ not null และถูก RLS กรองด้วย
-- current_institution_id() การยัดผู้ให้บริการลงไปแปลว่าต้องสร้าง
-- "วิทยาลัยปลอม" ขึ้นมาหนึ่งแห่งให้เขาสังกัด ซึ่งจะกลายเป็นวิทยาลัยที่
-- โผล่ในรายงาน ในโควตา และในการนับยอดขายตลอดไป
--
-- และที่สำคัญกว่านั้น — บัญชีที่อยู่ในตารางเดียวกับผู้ใช้ของลูกค้า
-- มีโอกาสหลุดเข้าไปใน query ของฝั่งวิทยาลัยได้เสมอ การแยกตารางทำให้
-- นโยบายเดียว (`is_platform_context()`) ปิดได้ทั้งก้อน
-- ───────────────────────────────────────────────────────────────────
create table platform_user (
  id              uuid          primary key default gen_random_uuid(),
  username        text          not null unique,
  display_name    text          not null,
  email           text,
  role            platform_role not null default 'support',

  -- ─── ทำไมค่าเริ่มต้นคือแฮชที่เทียบกับอะไรไม่ได้ ───
  -- หลักเดียวกับ 0037 — คนที่สร้างบัญชีให้ต้องไม่รู้รหัสผ่านของเจ้าตัว
  -- แม้แต่วินาทีเดียว บัญชีใหม่จึงเข้าด้วยรหัสผ่านไม่ได้จนกว่าเจ้าตัว
  -- จะตั้งเองผ่านรหัสตั้งค่าที่ออกให้ครั้งเดียว
  password_hash   text          not null,
  must_change     boolean       not null default false,

  -- ─── รหัสตั้งค่าครั้งแรก ───
  -- เก็บเป็นค่าแฮชเหมือนรหัสรีเซ็ตของฝั่งวิทยาลัย (0025) ฐานข้อมูลที่รั่ว
  -- จึงไม่ได้แถมรหัสที่ยังใช้ได้ไปด้วย
  setup_code_hash bytea,
  setup_expires_at timestamptz,
  setup_attempts  smallint      not null default 0,

  -- ─── การยืนยันสองชั้นบังคับเสมอ ไม่มีนโยบายให้ปิด ───
  -- บัญชีเดียวในตารางนี้เปิดวิทยาลัยใหม่ได้ ระงับลูกค้าได้ และเห็นตัวเลข
  -- ธุรกิจของทุกวิทยาลัย ต่างจากฝั่งวิทยาลัยที่ตั้งได้รายแห่ง (0036)
  -- ตรงที่ตรงนี้ไม่มีลูกค้าคนไหนเป็นผู้รับความเสี่ยงแทนได้
  totp_secret_enc bytea,
  totp_confirmed_at timestamptz,
  totp_last_step  bigint,
  mfa_failed_attempts smallint  not null default 0,
  mfa_locked_until timestamptz,

  failed_attempts smallint      not null default 0,
  locked_until    timestamptz,
  disabled_at     timestamptz,
  last_login_at   timestamptz,
  created_at      timestamptz   not null default now(),
  created_by      uuid          references platform_user on delete set null,

  check (setup_expires_at is null or setup_code_hash is not null)
);

comment on table platform_user is
  'บัญชีของผู้ให้บริการ — อยู่นอกวิทยาลัยทุกแห่ง จึงไม่มี institution_id และมองไม่เห็นข้อมูลของวิทยาลัยใดเลย';
comment on column platform_user.totp_secret_enc is
  'ความลับ TOTP ที่เข้ารหัสด้วยกุญแจนอกฐานข้อมูล — ฐานข้อมูลไม่เคยเห็นค่าจริง (หลักเดียวกับ 0036)';
comment on column platform_user.totp_last_step is
  'ช่วงเวลา TOTP ล่าสุดที่ใช้ไปแล้ว รับเฉพาะช่วงที่ใหม่กว่า มิฉะนั้นรหัสที่ถูกแอบเห็นใช้ซ้ำได้';

create index platform_user_active_idx on platform_user (role)
  where disabled_at is null;

-- ───────────────────────────────────────────────────────────────────
-- session ของผู้ให้บริการ
-- แยกจาก auth_session เพราะตารางนั้นมี institution_id แบบ not null
-- และทุกนโยบายของมันอ้างวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
create table platform_session (
  id               uuid        primary key default gen_random_uuid(),
  platform_user_id uuid        not null references platform_user on delete cascade,
  token_hash       bytea       not null unique,
  expires_at       timestamptz not null,
  revoked_at       timestamptz,
  revoke_reason    text,
  user_agent       text,
  created_at       timestamptz not null default now()
);

create index platform_session_user_idx on platform_session (platform_user_id)
  where revoked_at is null;

-- ───────────────────────────────────────────────────────────────────
-- ความพยายามเข้าสู่ระบบฝั่งผู้ให้บริการ
--
-- มีไว้สองอย่าง — เป็นตัวนับรายไอพี (หลักเดียวกับ 0021 คือนับในฐานข้อมูล
-- ไม่ใช่ในหน่วยความจำของโปรเซส เพราะหลาย instance จะต่างคนต่างนับ)
-- และเป็นหลักฐานว่ามีใครพยายามเข้าบัญชีผู้ให้บริการหรือไม่
-- ───────────────────────────────────────────────────────────────────
create table platform_login_attempt (
  id               bigserial   primary key,
  username         text        not null,
  platform_user_id uuid        references platform_user on delete set null,
  succeeded        boolean     not null,
  reason           text,
  ip_hash          bytea,
  user_agent       text,
  attempted_at     timestamptz not null default now()
);

create index platform_login_attempt_ip_idx
  on platform_login_attempt (ip_hash, attempted_at desc)
  where not succeeded;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการกระทำของผู้ให้บริการ
--
-- ─── ทำไมต้องมีแยกจาก access_log ───
-- access_log มี institution_id แบบ not null และอ่านได้เฉพาะคนในวิทยาลัยนั้น
-- การกระทำของผู้ให้บริการหลายอย่างไม่ได้อยู่ในวิทยาลัยไหน (แก้ราคาแพ็กเกจ
-- สร้างบัญชีผู้ให้บริการ) และที่สำคัญกว่าคือ **ลูกค้าต้องตรวจสอบได้ว่า
-- ผู้ให้บริการทำอะไรกับวิทยาลัยของตนบ้าง** จึงต้องเป็นบันทึกที่ผู้ให้บริการ
-- เองแก้ไม่ได้ ไม่ใช่บันทึกที่อยู่ในมือฝ่ายเดียว
--
-- username ตรึงเป็นข้อความไว้ด้วยโดยตั้งใจ — ลบบัญชีทิ้งแล้วยังต้อง
-- ตอบได้ว่าใครเป็นคนทำ ถ้าเก็บแค่คีย์นอก การลบบัญชีจะลบร่องรอยไปด้วย
-- ───────────────────────────────────────────────────────────────────
create table platform_action_log (
  id               bigserial   primary key,
  platform_user_id uuid        references platform_user on delete set null,
  username         text        not null,
  action           text        not null,
  institution_id   uuid        references institution on delete restrict,
  detail           jsonb       not null default '{}'::jsonb,
  ip_hash          bytea,
  occurred_at      timestamptz not null default now()
);

comment on table platform_action_log is
  'ผู้ให้บริการทำอะไรกับวิทยาลัยไหนเมื่อไร — เขียนได้อย่างเดียว แก้ไม่ได้ ลบได้เฉพาะที่เกินระยะเก็บ';

create index platform_action_log_time_idx on platform_action_log (occurred_at desc);
create index platform_action_log_inst_idx on platform_action_log (institution_id, occurred_at desc)
  where institution_id is not null;

-- ───────────────────────────────────────────────────────────────────
-- การระงับการใช้งานของวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
alter table institution
  add column if not exists suspended_at     timestamptz,
  add column if not exists suspended_reason text,
  add column if not exists suspended_by     uuid references platform_user on delete set null;

comment on column institution.suspended_at is
  'ระงับการเข้าสู่ระบบชั่วคราว — ข้อมูลทุกแถวยังอยู่ครบ ปลดระงับแล้วใช้ได้ทันที';
comment on column institution.suspended_reason is
  'เหตุผลที่ระงับ — แสดงให้ผู้ใช้ของวิทยาลัยเห็นตอนพยายามเข้าระบบ จึงต้องเขียนแบบที่ลูกค้าอ่านแล้วรู้ว่าต้องทำอะไรต่อ';

-- ───────────────────────────────────────────────────────────────────
-- ตัวช่วยของนโยบาย
--
-- ─── ทำไมต้องเช็คทั้งสองอย่าง ───
-- `current_institution_id() is null` อย่างเดียวไม่พอ เพราะงานเบื้องหลัง
-- บางตัวก็ไม่มีวิทยาลัย และ `app.role` อย่างเดียวก็ไม่พอ เพราะค่านั้นมาจาก
-- token ที่ชั้นแอปตั้งให้ การบังคับทั้งคู่แปลว่า token ของฝั่งวิทยาลัย
-- (ซึ่ง AuthGuard บังคับว่าต้องมี inst เสมอ) ไปถึงตรงนี้ไม่ได้เลย
-- ───────────────────────────────────────────────────────────────────
create or replace function is_platform_context() returns boolean
language sql stable as $$
  select current_institution_id() is null
     and current_app_role() in ('platform', 'platform_auth')
$$;

comment on function is_platform_context() is
  'บริบทนี้เป็นของผู้ให้บริการหรือไม่ — ต้องไม่มีวิทยาลัย และบทบาทต้องเป็นของฝั่งผู้ให้บริการเท่านั้น';

-- บทบาทของผู้ให้บริการที่กำลังทำคำขอนี้
--
-- ─── ทำไมต้องเป็น security definer ───
-- ฟังก์ชันนี้ถูกเรียกจาก **ในนโยบายของ platform_user เอง** ถ้าไม่ตัดวงจร
-- การอ่าน platform_user จะไปเรียกนโยบายที่เรียกฟังก์ชันที่อ่าน platform_user
-- อีกรอบ PostgreSQL จะล้มด้วย infinite recursion detected in policy
-- (กับดักเดียวกับ student ↔ student_guardian ใน 0008)
--
-- ปลอดภัยเพราะคืนได้แค่บทบาท **ของผู้เรียกเอง** ไม่รับพารามิเตอร์ใด ๆ
-- และไม่คืนแถวหรือคอลัมน์อื่นออกไปเลย
create or replace function current_platform_role() returns platform_role
language sql stable security definer set search_path = public as $$
  select pu.role from platform_user pu
   where pu.id = current_actor_id() and pu.disabled_at is null
$$;

-- ───────────────────────────────────────────────────────────────────
-- สร้างบัญชีผู้ให้บริการคนแรก
--
-- ─── ทำไมต้องมีฟังก์ชันแยกและเป็น security definer ───
-- ไก่กับไข่ — นโยบาย insert ของ platform_user ต้องการ owner ที่ล็อกอินแล้ว
-- แต่ตอนติดตั้งระบบครั้งแรกยังไม่มี owner สักคนให้ล็อกอิน ถ้าไม่มีทางนี้
-- การติดตั้งครั้งแรกต้องเปิด psql เขียนแถวเอง ซึ่งคือปัญหาเดิมที่ 0037
-- ตั้งใจแก้
--
-- นี่เป็นข้อยกเว้นแบบเดียวกับ provision_institution — **สร้างได้อย่างเดียว
-- และสร้างได้ครั้งเดียวจริง ๆ** มีแถวอยู่แล้วแม้แถวเดียวก็ล้มทันที
-- จึงไม่ใช่ประตูหลังที่เรียกซ้ำเพื่อแต่งตั้งตัวเองเป็น owner ได้
--
-- ชั้นแอปยังกั้นด้วย PROVISION_KEY อีกชั้นก่อนถึงตรงนี้
-- ───────────────────────────────────────────────────────────────────
create or replace function bootstrap_platform_owner(
  p_username        text,
  p_display_name    text,
  p_email           text,
  p_setup_code_hash bytea,
  p_setup_minutes   integer default 60
) returns platform_user language plpgsql security definer set search_path = public as $$
declare v platform_user;
begin
  if exists (select 1 from platform_user) then
    raise exception 'มีบัญชีผู้ให้บริการอยู่แล้ว — การสร้างบัญชีเพิ่มต้องทำโดยผู้ดูแลระดับ owner ที่เข้าสู่ระบบแล้ว';
  end if;
  if coalesce(btrim(p_username), '') = '' or coalesce(btrim(p_display_name), '') = '' then
    raise exception 'ต้องระบุชื่อผู้ใช้และชื่อที่แสดง';
  end if;
  if p_setup_code_hash is null then
    raise exception 'ต้องมีรหัสตั้งค่า — บัญชีที่ไม่มีทางตั้งรหัสผ่านคือบัญชีที่เข้าไม่ได้ตลอดไป';
  end if;

  insert into platform_user
    (username, display_name, email, role, password_hash, must_change,
     setup_code_hash, setup_expires_at)
  values (btrim(p_username), btrim(p_display_name), nullif(btrim(p_email), ''), 'owner',
          -- เข้าด้วยรหัสผ่านไม่ได้จนกว่าเจ้าตัวจะตั้งเองผ่านรหัสตั้งค่า
          'locked$' || encode(gen_random_bytes(32), 'hex'), true,
          p_setup_code_hash, now() + make_interval(mins => p_setup_minutes))
  returning * into v;

  -- บันทึกการติดตั้งไว้ด้วย มิฉะนั้นบัญชีแรกของระบบจะเป็นบัญชีเดียวที่
  -- ไม่มีร่องรอยว่าเกิดขึ้นเมื่อไรและกลายเป็นช่องว่างในบันทึกตั้งแต่แถวแรก
  -- (log_platform_action() ใช้ไม่ได้ตรงนี้เพราะยังไม่มี current_actor_id())
  insert into platform_action_log (platform_user_id, username, action, detail)
  values (v.id, v.username, 'bootstrap_platform_owner',
          jsonb_build_object('note', 'สร้างด้วยกุญแจติดตั้ง PROVISION_KEY'));

  return v;
end $$;

revoke execute on function bootstrap_platform_owner(text, text, text, bytea, integer) from public;

-- ───────────────────────────────────────────────────────────────────
-- จำกัดจำนวนครั้งการเข้าสู่ระบบรายไอพี
--
-- **ห้าม raise** ด้วยเหตุผลเดียวกับ login_rate_status (0021) — ถ้า raise
-- ฐานข้อมูลจะ rollback ตัวนับทิ้งทุกครั้ง แล้วเดารหัสผ่านได้ไม่จำกัด
--
-- เข้มกว่าฝั่งวิทยาลัยเพราะบัญชีฝั่งนี้มีไม่กี่บัญชีและไม่มีนักศึกษา
-- เป็นพันคนที่พิมพ์รหัสผิดตอนเปิดเทอม โควตาต่ำจึงไม่รบกวนใคร
-- ───────────────────────────────────────────────────────────────────
create or replace function platform_login_rate_status(p_ip_hash bytea)
returns table (
  recent_failures  integer,
  max_attempts     integer,
  remaining        integer,
  blocked          boolean,
  retry_after_secs integer
) language plpgsql stable as $$
declare
  v_max    constant integer := 10;
  v_window constant integer := 15;   -- นาที
  v_block  constant integer := 30;   -- นาที
  v_count  integer;
  v_oldest timestamptz;
begin
  if p_ip_hash is null then
    -- ไม่รู้ไอพี (เรียกจากในเครื่อง) ไม่นับ แต่ก็ไม่ปลดล็อกให้ใคร
    return query select 0, v_max, v_max, false, 0;
    return;
  end if;

  select count(*)::integer, min(la.attempted_at)
    into v_count, v_oldest
    from platform_login_attempt la
   where la.ip_hash = p_ip_hash
     and not la.succeeded
     and la.attempted_at > now() - make_interval(mins => v_window);

  return query select
    v_count,
    v_max,
    greatest(0, v_max - v_count),
    v_count >= v_max,
    case when v_count >= v_max
         then greatest(0, ceil(extract(epoch from
                (coalesce(v_oldest, now()) + make_interval(mins => v_block) - now())))::integer)
         else 0 end;
end $$;

comment on function platform_login_rate_status(bytea) is
  'สถานะการจำกัดจำนวนครั้งรายไอพีของฝั่งผู้ให้บริการ — คืนค่า ไม่ raise เพราะตัวนับต้องไม่ถูก rollback';

-- ───────────────────────────────────────────────────────────────────
-- ใช้รหัสตั้งค่าครั้งแรก
--
-- ─── ทำไมค้นจากชื่อผู้ใช้ก่อน แล้วค่อยเทียบค่าแฮช ───
-- ถ้าค้นด้วย `where setup_code_hash = $1` ตรง ๆ การเดาผิดจะไม่เจอแถวใดเลย
-- แล้วไม่มีแถวให้เพิ่มตัวนับ ผลคือเดารหัสได้ไม่จำกัดครั้งโดยที่ระบบยัง
-- ปฏิเสธรหัสผิดถูกต้องทุกครั้ง (กับดักเดียวกับ consume_password_reset ใน 0025)
--
-- **ห้าม raise** ด้วยเหตุผลเดิม — rollback จะล้างตัวนับทิ้ง
-- ───────────────────────────────────────────────────────────────────
create or replace function consume_platform_setup(
  p_username  text,
  p_code_hash bytea
) returns table (
  ok        boolean,
  user_id   uuid,
  reason    text
) language plpgsql as $$
declare
  v     platform_user;
  v_max constant smallint := 5;
begin
  select * into v from platform_user where username = p_username;

  -- ข้อความเดียวกันทุกกรณีที่เดาไม่ถูก เพื่อไม่บอกว่าชื่อผู้ใช้ไหนมีอยู่จริง
  if v.id is null then
    return query select false, null::uuid, 'ชื่อผู้ใช้หรือรหัสตั้งค่าไม่ถูกต้อง'::text;
    return;
  end if;
  if v.setup_code_hash is null then
    return query select false, null::uuid, 'บัญชีนี้ตั้งรหัสผ่านไปแล้ว'::text;
    return;
  end if;
  if v.setup_expires_at is null or v.setup_expires_at < now() then
    return query select false, null::uuid, 'รหัสตั้งค่าหมดอายุแล้ว ขอรหัสใหม่จากผู้ดูแลระดับ owner'::text;
    return;
  end if;
  if v.setup_attempts >= v_max then
    return query select false, null::uuid, 'ใส่รหัสตั้งค่าผิดหลายครั้งเกินไป ขอรหัสใหม่'::text;
    return;
  end if;

  if v.setup_code_hash <> p_code_hash then
    update platform_user set setup_attempts = setup_attempts + 1 where id = v.id;
    return query select false, null::uuid, 'ชื่อผู้ใช้หรือรหัสตั้งค่าไม่ถูกต้อง'::text;
    return;
  end if;

  update platform_user
     set setup_code_hash = null, setup_expires_at = null, setup_attempts = 0
   where id = v.id;

  return query select true, v.id, null::text;
end $$;

comment on function consume_platform_setup(text, bytea) is
  'ตรวจรหัสตั้งค่าครั้งแรก — ค้นจากชื่อผู้ใช้ก่อนเพื่อให้มีแถวให้เพิ่มตัวนับเมื่อเดาผิด และห้าม raise';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจรหัส TOTP ของผู้ให้บริการ
--
-- โครงเดียวกับ mfa_verify_step (0036) — ชั้นแอปเป็นคนบอกว่ารหัสตรงไหม
-- เพราะต้องถอดรหัสความลับด้วยกุญแจที่อยู่นอกฐานข้อมูล ส่วนฟังก์ชันนี้
-- ถือสถานะที่ต้องอะตอมมิก คือการล็อก การกันใช้รหัสซ้ำ และตัวนับ
--
-- **ห้าม raise** เหตุผลเดียวกับข้างบน
-- ───────────────────────────────────────────────────────────────────
create or replace function platform_totp_verify(
  p_user_id uuid,
  p_step    bigint,
  p_matched boolean
) returns table (
  ok               boolean,
  reason           text,
  retry_after_secs integer
) language plpgsql as $$
declare
  v_user    platform_user;
  v_max     constant smallint := 5;
  v_lock    constant smallint := 15;  -- นาที
begin
  select * into v_user from platform_user
   where id = p_user_id and disabled_at is null;

  if v_user.id is null then
    return query select false, 'ไม่พบบัญชีผู้ให้บริการ'::text, 0;
    return;
  end if;

  if v_user.totp_secret_enc is null then
    return query select false, 'ยังไม่ได้ตั้งค่าการยืนยันตัวตนสองชั้น'::text, 0;
    return;
  end if;

  if v_user.mfa_locked_until is not null and v_user.mfa_locked_until > now() then
    return query select false, 'ใส่รหัสผิดหลายครั้ง ถูกระงับชั่วคราว'::text,
      ceil(extract(epoch from (v_user.mfa_locked_until - now())))::integer;
    return;
  end if;

  if not p_matched then
    update platform_user
       set mfa_failed_attempts = mfa_failed_attempts + 1,
           mfa_locked_until = case
             when mfa_failed_attempts + 1 >= v_max then now() + make_interval(mins => v_lock)
             else mfa_locked_until end
     where id = v_user.id;

    return query select false, 'รหัสยืนยันไม่ถูกต้อง'::text, 0;
    return;
  end if;

  -- รหัสถูกแต่เป็นช่วงเวลาที่ใช้ไปแล้ว = มีคนดักรหัสมาใช้ซ้ำ
  -- นับเป็นความพยายามที่ผิดด้วย เพราะแอปของเจ้าตัวแสดงรหัสปัจจุบันเสมอ
  if v_user.totp_last_step is not null and p_step <= v_user.totp_last_step then
    update platform_user
       set mfa_failed_attempts = mfa_failed_attempts + 1,
           mfa_locked_until = case
             when mfa_failed_attempts + 1 >= v_max then now() + make_interval(mins => v_lock)
             else mfa_locked_until end
     where id = v_user.id;

    return query select false, 'รหัสนี้ถูกใช้ไปแล้ว รอรหัสถัดไป'::text, 0;
    return;
  end if;

  update platform_user
     set totp_last_step = p_step, mfa_failed_attempts = 0, mfa_locked_until = null
   where id = v_user.id;

  return query select true, null::text, 0;
end $$;

comment on function platform_totp_verify(uuid, bigint, boolean) is
  'ตัดสินผลการยืนยันสองชั้นของผู้ให้บริการ — ห้าม raise เพราะตัวนับจะถูก rollback แล้วเดารหัสหกหลักได้ไม่จำกัด';

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการกระทำ
--
-- ตรึง username ลงไปด้วยเพื่อให้บันทึกยังตอบได้แม้บัญชีถูกลบ
-- ───────────────────────────────────────────────────────────────────
create or replace function log_platform_action(
  p_action         text,
  p_institution_id uuid    default null,
  p_detail         jsonb   default '{}'::jsonb,
  p_ip_hash        bytea   default null
) returns bigint language plpgsql as $$
declare
  v_id   bigint;
  v_name text;
begin
  select pu.username into v_name from platform_user pu where pu.id = current_actor_id();

  insert into platform_action_log
    (platform_user_id, username, action, institution_id, detail, ip_hash)
  values (current_actor_id(), coalesce(v_name, 'ไม่ทราบ'), p_action,
          p_institution_id, coalesce(p_detail, '{}'::jsonb), p_ip_hash)
  returning id into v_id;

  return v_id;
end $$;

-- ล้างบันทึกที่เกินระยะเก็บ — เก็บนานกว่า access_log เพราะเป็นหลักฐาน
-- ของสัญญาระหว่างนิติบุคคลสองราย ไม่ใช่บันทึกการเข้าถึงรายวัน
create or replace function purge_platform_action_log(p_keep_days integer default 730)
returns integer language plpgsql as $$
declare v_deleted integer;
begin
  delete from platform_action_log where occurred_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ตัด session ทั้งหมดของวิทยาลัยหนึ่ง
--
-- security definer เพราะบริบทผู้ให้บริการไม่มีวิทยาลัย จึงมองไม่เห็น
-- auth_session ของใครเลย (ซึ่งเป็นสิ่งที่ตั้งใจ) ฟังก์ชันนี้ **เขียน
-- อย่างเดียว** ไม่คืนข้อมูลอะไรออกมานอกจากจำนวนแถว จึงไม่ได้เปิดช่อง
-- ให้อ่านข้ามวิทยาลัยแม้แต่ช่องเดียว
-- ───────────────────────────────────────────────────────────────────
create or replace function revoke_institution_sessions(
  p_institution_id uuid,
  p_reason         text
) returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  update auth_session
     set revoked_at = now(), revoke_reason = p_reason
   where institution_id = p_institution_id and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

comment on function revoke_institution_sessions(uuid, text) is
  'ตัด session ที่ค้างอยู่ของวิทยาลัยหนึ่ง — เขียนอย่างเดียว ไม่คืนข้อมูลของวิทยาลัยออกมา';

revoke execute on function revoke_institution_sessions(uuid, text) from public;

-- ───────────────────────────────────────────────────────────────────
-- ระงับ / ปลดระงับวิทยาลัย
--
-- ต้องมีเหตุผลเสมอ เพราะข้อความนี้คือสิ่งเดียวที่ผู้ใช้ของวิทยาลัยจะเห็น
-- ตอนเข้าระบบไม่ได้ — "ถูกระงับ" เฉย ๆ ทำให้ทั้งวิทยาลัยโทรหาผู้ให้บริการ
-- พร้อมกันโดยไม่มีใครรู้ว่าต้องทำอะไร
--
-- ไม่ใช่ security definer — ต้องผ่านนโยบายของ institution ตามปกติ
-- แปลว่าเรียกได้เฉพาะบริบทผู้ให้บริการเท่านั้น วิทยาลัยปลดระงับตัวเองไม่ได้
-- ───────────────────────────────────────────────────────────────────
create or replace function suspend_institution(
  p_institution_id uuid,
  p_reason         text
) returns institution language plpgsql as $$
declare v institution;
begin
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'ต้องระบุเหตุผลที่ระงับ — ผู้ใช้ของวิทยาลัยจะเห็นข้อความนี้ตอนเข้าระบบไม่ได้';
  end if;

  update institution
     set suspended_at = coalesce(suspended_at, now()),
         suspended_reason = btrim(p_reason),
         suspended_by = current_actor_id()
   where id = p_institution_id
  returning * into v;

  if v.id is null then
    raise exception 'ไม่พบสถานศึกษาที่ระบุ หรือไม่มีสิทธิ์ระงับ';
  end if;

  -- session ที่ค้างอยู่ต้องถูกตัดด้วย มิฉะนั้นคนที่ล็อกอินค้างไว้ยังใช้งาน
  -- ต่อได้อีกหลายชั่วโมงจนกว่า access token จะหมดอายุ ซึ่งทำให้การระงับ
  -- ดูเหมือนไม่ทำงานในสายตาของคนที่กดปุ่ม
  --
  -- ทำผ่าน security definer เพราะ auth_session ถูก RLS กรองด้วยวิทยาลัย
  -- ซึ่งบริบทผู้ให้บริการไม่มี — เป็นการ "ปิดทางเข้า" ไม่ใช่การอ่านข้อมูล
  perform revoke_institution_sessions(p_institution_id, 'สถานศึกษาถูกระงับการใช้งาน');

  return v;
end $$;

create or replace function resume_institution(p_institution_id uuid)
returns institution language plpgsql as $$
declare v institution;
begin
  update institution
     set suspended_at = null, suspended_reason = null, suspended_by = null
   where id = p_institution_id
  returning * into v;

  if v.id is null then
    raise exception 'ไม่พบสถานศึกษาที่ระบุ หรือไม่มีสิทธิ์ปลดระงับ';
  end if;

  return v;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ประตูที่บังคับการระงับจริง ๆ
--
-- ─── ทำไมเป็น trigger ไม่ใช่ if ในชั้น API ───
-- ชั้น API ตรวจอยู่แล้วเพื่อให้ได้ข้อความที่อ่านรู้เรื่อง แต่การตรวจที่นั่น
-- อย่างเดียวแปลว่าเส้นทางไหนก็ตามที่สร้าง session ได้โดยไม่ผ่านโค้ดนั้น
-- (สคริปต์ย้ายข้อมูล เส้นทางใหม่ที่เขียนทีหลัง การหมุน token) จะข้ามการ
-- ระงับได้ทั้งหมด — กฎอยู่ที่ฐานข้อมูลจึงบังคับกับทุกทาง (หลักข้อ 1)
--
-- ─── ทำไมดักที่ insert เท่านั้น ───
-- การ update ใช้เพิกถอน session (ออกจากระบบ · หมุน token · ตัดตอนระงับ)
-- ถ้าดักด้วยจะทำให้ "ออกจากระบบ" ล้มเหลวหลังวิทยาลัยถูกระงับ ซึ่งกลาย
-- เป็นการบังคับให้ token ค้างอยู่กับเครื่องลูกค้าแทนที่จะถูกเพิกถอน
-- และการหมุน token ก็ออก session แถวใหม่เสมอ (issueTokens) จึงถูกดักอยู่ดี
-- ───────────────────────────────────────────────────────────────────
create or replace function block_session_when_suspended() returns trigger
language plpgsql as $$
declare v_reason text; v_at timestamptz;
begin
  select i.suspended_reason, i.suspended_at into v_reason, v_at
    from institution i where i.id = new.institution_id;

  if v_at is not null then
    raise exception 'สถานศึกษานี้ถูกระงับการใช้งานชั่วคราว (%) กรุณาติดต่อผู้ให้บริการ',
      coalesce(nullif(btrim(v_reason), ''), 'ไม่ได้ระบุเหตุผล');
  end if;

  return new;
end $$;

create trigger auth_session_suspension_check
  before insert on auth_session
  for each row execute function block_session_when_suspended();

-- ───────────────────────────────────────────────────────────────────
-- กันการยกระดับสิทธิ์ของตัวเอง
--
-- ─── ทำไม RLS อย่างเดียวไม่พอ ───
-- นโยบายข้างล่างต้องยอมให้ผู้ใช้แก้แถวของตัวเองได้ (เปลี่ยนรหัสผ่าน
-- ตั้ง TOTP) ซึ่งแปลว่า support คนหนึ่งเขียนแถวของตัวเองได้ และถ้าไม่มี
-- อะไรกั้น เขาก็ตั้ง role ของตัวเองเป็น owner ได้ในคำสั่งเดียวกัน
--
-- นโยบายแยกตามคอลัมน์ทำไม่ได้ใน PostgreSQL (RLS เป็นระดับแถว) จึงต้อง
-- ใช้ trigger — ซึ่งเป็นทางที่หลักข้อ "อย่าใช้ security definer เลี่ยง
-- นโยบาย" แนะนำไว้อยู่แล้ว
-- ───────────────────────────────────────────────────────────────────
create or replace function platform_user_guard() returns trigger
language plpgsql as $$
declare v_owners integer;
begin
  -- ขั้นตอนล็อกอินแตะได้เฉพาะตัวนับกับเวลา ไม่ใช่สิทธิ์
  if current_app_role() = 'platform_auth' then
    if new.role <> old.role or new.disabled_at is distinct from old.disabled_at then
      raise exception 'ขั้นตอนเข้าสู่ระบบเปลี่ยนสิทธิ์ของบัญชีไม่ได้';
    end if;
    return new;
  end if;

  if new.role <> old.role then
    if old.id = current_actor_id() then
      raise exception 'เปลี่ยนบทบาทของตัวเองไม่ได้ — ต้องให้ผู้ดูแลระบบคนอื่นเป็นคนเปลี่ยน';
    end if;
    if current_platform_role() <> 'owner' then
      raise exception 'ต้องเป็นผู้ดูแลระดับ owner จึงจะเปลี่ยนบทบาทของบัญชีอื่นได้';
    end if;
  end if;

  if new.disabled_at is distinct from old.disabled_at then
    if old.id = current_actor_id() then
      raise exception 'ระงับหรือเปิดบัญชีของตัวเองไม่ได้';
    end if;
    if current_platform_role() <> 'owner' then
      raise exception 'ต้องเป็นผู้ดูแลระดับ owner จึงจะระงับบัญชีอื่นได้';
    end if;
  end if;

  -- ต้องเหลือ owner ที่ใช้งานได้อย่างน้อยหนึ่งคนเสมอ
  --
  -- ถ้าเหลือศูนย์ จะไม่มีใครแต่งตั้ง owner คนใหม่ได้อีกเลย ทางแก้เดียวคือ
  -- เข้าไปแก้ในฐานข้อมูลตรง ๆ ซึ่งเป็นสถานการณ์ที่ระบบไม่ควรพาไปถึง
  if (old.role = 'owner' and new.role <> 'owner')
     or (old.role = 'owner' and new.disabled_at is not null and old.disabled_at is null) then
    select count(*) into v_owners from platform_user
     where role = 'owner' and disabled_at is null and id <> old.id;
    if v_owners = 0 then
      raise exception 'ต้องเหลือผู้ดูแลระดับ owner ที่ใช้งานได้อย่างน้อยหนึ่งบัญชี';
    end if;
  end if;

  return new;
end $$;

create trigger platform_user_role_guard
  before update on platform_user
  for each row execute function platform_user_guard();

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ─── ข้อที่สำคัญที่สุดในส่วนนี้ ───
-- ตารางทั้งสี่ต้องมองไม่เห็นจากบริบทของวิทยาลัย **โดยสิ้นเชิง**
-- ไม่ใช่แค่ "ไม่มี endpoint ให้เรียก" — app_runtime มีสิทธิ์ select ทุกตาราง
-- อยู่แล้ว ถ้าไม่ปิดที่ RLS โค้ดฝั่งวิทยาลัยบรรทัดเดียวที่เขียนผิดจะอ่าน
-- ค่าแฮชรหัสผ่านของผู้ให้บริการได้
-- ───────────────────────────────────────────────────────────────────
alter table platform_user enable row level security;
alter table platform_user force  row level security;

-- อ่านได้เฉพาะฝั่งผู้ให้บริการ (รวมขั้นตอนล็อกอินที่ต้องอ่านค่าแฮชมาเทียบ)
create policy platform_user_scope on platform_user
  for select using (is_platform_context());

-- สร้างบัญชีใหม่ได้เฉพาะ owner และเฉพาะบริบทที่ล็อกอินเสร็จแล้ว
--
-- ห้ามเขียนเงื่อนไข "หรือยังไม่มีบัญชีสักคน" ไว้ตรงนี้เพื่อรองรับการติดตั้ง
-- ครั้งแรก — subquery ที่อ่าน platform_user จากในนโยบายของ platform_user เอง
-- ทำให้เกิด infinite recursion บัญชีแรกจึงใช้ bootstrap_platform_owner()
create policy platform_user_insert on platform_user
  for insert with check (
    current_institution_id() is null
    and current_app_role() = 'platform'
    and current_platform_role() = 'owner'
  );

-- ─── ทำไมยอมให้แก้แถวของตัวเองและของคนอื่น ───
-- ขั้นล็อกอินต้องแก้ตัวนับของบัญชีที่กำลังถูกลอง (ยังไม่รู้ว่าเป็นใคร)
-- เจ้าตัวต้องแก้รหัสผ่านและ TOTP ของตัวเอง และ owner ต้องจัดการบัญชีอื่น
-- ส่วนการยกระดับสิทธิ์ถูกกันด้วย trigger ข้างบน ไม่ใช่ด้วยนโยบายนี้
create policy platform_user_update on platform_user
  for update using (is_platform_context())
  with check (is_platform_context());

-- ไม่มีนโยบาย delete โดยเจตนา — บัญชีที่ทำอะไรไปแล้วต้องระงับ ไม่ใช่ลบ
-- มิฉะนั้น platform_action_log จะเหลือแต่ชื่อที่ตามตัวไม่ได้

alter table platform_session enable row level security;
alter table platform_session force  row level security;
create policy platform_session_scope on platform_session
  using (is_platform_context())
  with check (is_platform_context());

alter table platform_login_attempt enable row level security;
alter table platform_login_attempt force  row level security;
create policy platform_login_attempt_scope on platform_login_attempt
  using (is_platform_context())
  with check (is_platform_context());

alter table platform_action_log enable row level security;
alter table platform_action_log force  row level security;

-- ─── ทำไมอ่านได้อย่างเดียวและแก้ไม่ได้เลย ───
-- บันทึกที่ผู้ให้บริการลบเองได้ ใช้ตอบลูกค้าไม่ได้ว่า "ไม่มีใครเข้าไปยุ่ง
-- กับข้อมูลของท่าน" เพราะคำตอบนั้นพิสูจน์ไม่ได้ (หลักเดียวกับ access_log)
create policy platform_action_log_read on platform_action_log
  for select using (is_platform_context());
create policy platform_action_log_append on platform_action_log
  for insert with check (is_platform_context());
create policy platform_action_log_purge_aged on platform_action_log
  for delete using (occurred_at < now() - interval '730 days');

-- ───────────────────────────────────────────────────────────────────
-- provisioning_log — ประวัติการเปิดวิทยาลัย
--
-- 0037 เขียนไว้ว่าตารางนี้เป็น "ข้อมูลระดับผู้ให้บริการ" แต่นโยบายที่ใส่ไว้
-- กรองด้วย current_institution_id() ล้วน ๆ ผลคือฝั่งที่เป็นเจ้าของข้อมูล
-- จริง ๆ กลับเป็นฝ่ายเดียวที่อ่านไม่ได้ — หน้าจอ "ใครเปิดวิทยาลัยนี้ให้เมื่อไร"
-- จึงว่างเปล่าเสมอ เพิ่มนโยบายสำหรับบริบทผู้ให้บริการให้ตรงกับที่ตั้งใจไว้
--
-- อ่านอย่างเดียว — แถวถูกเขียนโดย provision_institution() เท่านั้น
create policy provisioning_log_platform_read on provisioning_log
  for select using (is_platform_context());

-- ───────────────────────────────────────────────────────────────────
-- institution — เปิดให้อ่านเหมือนเดิม แต่เขียนได้เฉพาะผู้ให้บริการ
--
-- ─── ทำไมต้องเพิ่ม RLS ตอนนี้ ───
-- ตารางนี้ไม่เคยมี RLS เพราะเป็นตัวกำหนดขอบเขตเอง (กรองด้วยตัวเองไม่ได้)
-- ซึ่งเดิมไม่เป็นปัญหาเพราะมีแค่รหัสกับชื่อ แต่ไฟล์นี้เพิ่ม suspended_at
-- ลงไป — ถ้าไม่ปิดการเขียน วิทยาลัยที่ถูกระงับจะ `update institution
-- set suspended_at = null` ปลดระงับตัวเองได้ที่ชั้นฐานข้อมูล แล้วการระงับ
-- จะไม่มีความหมายอะไรเลย
--
-- ─── ทำไมการอ่านยังเปิดกว้าง ───
-- งานเบื้องหลังวนทุกวิทยาลัยโดยไม่มีบริบทผู้ใช้ (DbService.listInstitutions)
-- และนโยบายของตารางอื่นหลายข้ออ้าง institution ระหว่างตรวจสิทธิ์
-- การปิดการอ่านตรงนี้จะทำให้ทั้งสองอย่างพังเงียบ ๆ และแถวในตารางนี้
-- ไม่มีข้อมูลส่วนบุคคลเลยสักช่อง — การจำกัดการอ่านเป็นงานแยกที่ต้องมี
-- เทสต์ของตัวเอง ไม่ใช่ของแถมในไฟล์นี้
-- ───────────────────────────────────────────────────────────────────
alter table institution enable row level security;
alter table institution force  row level security;

create policy institution_read on institution
  for select using (true);

create policy institution_manage on institution
  for update using (is_platform_context())
  with check (is_platform_context());

-- provision_institution() เป็น security definer จึงข้าม RLS อยู่แล้วเมื่อ
-- เจ้าของฟังก์ชันเป็น superuser แต่การพึ่งข้อนั้นอย่างเดียวแปลว่าการเปิด
-- วิทยาลัยจะพังทันทีที่ deploy ด้วยเจ้าของที่ไม่ใช่ superuser — เขียนนโยบาย
-- ไว้ให้ตรงกับสิ่งที่ตั้งใจดีกว่าปล่อยให้ขึ้นกับสิทธิ์ของคนที่รัน migration
create policy institution_create on institution
  for insert with check (is_platform_context());

-- ไม่มีนโยบาย delete — การลบวิทยาลัยไม่ควรทำได้จากที่ไหนเลย
-- (คีย์นอกแบบ restrict ทั้งระบบชี้มาที่ตารางนี้อยู่แล้ว)

-- ───────────────────────────────────────────────────────────────────
-- สิทธิ์ระดับตาราง — roles.sql รันไปก่อนหน้านี้แล้ว
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete
      on platform_user, platform_session, platform_login_attempt, platform_action_log
      to app_runtime;
    grant usage, select on sequence platform_login_attempt_id_seq to app_runtime;
    grant usage, select on sequence platform_action_log_id_seq    to app_runtime;
    grant execute on function is_platform_context()                       to app_runtime;
    grant execute on function bootstrap_platform_owner(text, text, text, bytea, integer)
      to app_runtime;
    grant execute on function current_platform_role()                     to app_runtime;
    grant execute on function platform_login_rate_status(bytea)           to app_runtime;
    grant execute on function consume_platform_setup(text, bytea)         to app_runtime;
    grant execute on function platform_totp_verify(uuid, bigint, boolean) to app_runtime;
    grant execute on function log_platform_action(text, uuid, jsonb, bytea) to app_runtime;
    grant execute on function purge_platform_action_log(integer)          to app_runtime;
    grant execute on function suspend_institution(uuid, text)             to app_runtime;
    grant execute on function resume_institution(uuid)                    to app_runtime;
    grant execute on function revoke_institution_sessions(uuid, text)     to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0041_write_scope_grades_finance.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0041_write_scope_grades_finance.sql
--
-- ปิดช่องที่นักศึกษาเขียนคะแนน เกรดเฉลี่ย สถานะ และหนี้ของตัวเองได้
--
-- ─── อาการที่ทดสอบแล้วเกิดขึ้นจริง ───
-- ตั้งบริบทเป็นนักศึกษาคนหนึ่ง (app.role = 'student') แล้วยิง update ตรง ๆ
-- ที่ชั้นฐานข้อมูล ทุกคำสั่งข้างล่างนี้สำเร็จ ไม่ใช่ถูกกรองเป็นศูนย์แถว
--
--   update gradebook_score   set score  = 100          → ให้คะแนนตัวเอง
--   update term_summary      set gpa    = 4.00         → แก้เกรดเฉลี่ยตัวเอง
--   update student           set status = 'graduated'  → ทำให้ตัวเองจบ
--   update invoice           set status = 'paid'       → ล้างหนี้ตัวเอง
--   update installment       set due_on = +365 วัน     → เลื่อนกำหนดชำระ
--   update enrollment        set status = ...          → แก้สถานะลงทะเบียน
--   delete from student_status_history                 → ลบร่องรอยของตัวเอง
--
-- ─── ต้นเหตุเดิมกับ 0039 ───
-- policy ที่เขียน `using` ไว้แต่ไม่เขียน `with check` PostgreSQL จะเอา
-- `using` **มาใช้เป็น `with check` ให้เอง** ประโยคที่เขียนไว้ให้เจ้าของ
-- **ดู**ของตัวเองได้ จึงกลายเป็นสิทธิ์ **เขียน** ของตัวเองไปด้วยทุกข้อ
--
--   subject_scope        ... or s.person_id = current_actor_id()
--   term_summary_scope   ... or student_id in (select actor_student_ids())
--   gradebook_scope      ... or enrollment_id in (select actor_enrollment_ids())
--
-- ทั้งสามประโยคเขียนไว้ให้นักศึกษาเปิดดูคะแนนและใบแจ้งหนี้ของตัวเอง
-- ซึ่งเป็นสิ่งที่ต้องมี — สิ่งที่ผิดคือมันเปิดทางเขียนไปด้วย
--
-- ─── ทำไมต้องมีนโยบาย for delete แยกทุกตาราง ───
-- `with check` มีผลกับ insert และ update เท่านั้น **delete ไม่มี with check**
-- PostgreSQL ใช้ `using` ตัดสิน delete ล้วน ๆ ถ้าไม่เพิ่มนโยบายเฉพาะ
-- เจ้าของจะยังลบแถวของตัวเองทิ้งได้ ซึ่งมักได้ผลเท่ากับแก้ค่า —
-- ใบแจ้งหนี้ที่หายไปคือหนี้ที่หายไป และคะแนนที่หายไปคือคะแนนที่ไม่เคยมี
--
-- ─── ใครยังต้องเขียนได้บ้าง (ตรวจกับเส้นทางจริงแล้วทุกข้อ) ───
-- · gradebook_score  ครูผู้สอนของรายการคะแนนนั้น — เป็นคนกรอกคะแนนตัวจริง
-- · term_summary     เฉพาะบทบาทระดับวิทยาลัย เพราะ compute_term_summary()
--                    ถูกเรียกจาก POST /gradebook/terms/:id/summary ซึ่งกั้น
--                    ด้วย @Roles('registrar','academic','director','admin')
-- · invoice · invoice_line · installment  งานการเงินและงานทะเบียน
-- · student · enrollment · student_status_history  บทบาทระดับวิทยาลัย
--   (ครูอ่านได้เหมือนเดิมแต่เขียนไม่ได้ — การแก้ทะเบียนนักศึกษาไม่ใช่งานครู)
--
-- ─── ที่เหลืออีก 38 ตาราง ───
-- รูปแบบเดียวกันนี้ยังมีอยู่ในตารางกลุ่มยืนยันตัวตน (user_credential ·
-- mfa_credential · password_reset) ซึ่ง **ต้องให้เจ้าของเขียนได้** เพราะ
-- เจ้าตัวเป็นคนเปลี่ยนรหัสผ่านและตั้ง MFA เอง การปิดตรงนั้นต้องกันรายคอลัมน์
-- ด้วย trigger ไม่ใช่ปิดทั้งแถว จึงเป็นงานคนละก้อนที่ต้องมีเทสต์ของตัวเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- คะแนนในสมุดคะแนน — ครูผู้สอนกรอก นักศึกษาดูได้เมื่อครูเผยแพร่แล้ว
--
-- ข้อนี้ร้ายแรงที่สุดในไฟล์ เพราะคะแนนคือที่มาของเกรด และเกรดคือที่มา
-- ของการจบการศึกษา การแก้ที่ต้นทางจึงไหลไปทุกอย่างที่คำนวณต่อจากมัน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists gradebook_scope on gradebook_score;

create policy gradebook_scope on gradebook_score
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
                 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 join staff st         on st.id = cs.teacher_id
                where gi.id = gradebook_score.gradebook_item_id
                  and st.person_id = current_actor_id())
    -- เจ้าของดูได้เฉพาะรายการที่ครูเผยแพร่แล้ว — อ่านอย่างเดียว
    or (enrollment_id in (select actor_enrollment_ids())
        and exists (select 1 from gradebook_item gi
                     where gi.id = gradebook_score.gradebook_item_id
                       and gi.publish_to_student))
  )
  with check (
    is_institution_wide_role()
    or exists (select 1
                 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 join staff st         on st.id = cs.teacher_id
                where gi.id = gradebook_score.gradebook_item_id
                  and st.person_id = current_actor_id())
  );

create policy gradebook_score_no_owner_delete on gradebook_score
  as restrictive for delete
  using (
    is_institution_wide_role()
    or exists (select 1
                 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 join staff st         on st.id = cs.teacher_id
                where gi.id = gradebook_score.gradebook_item_id
                  and st.person_id = current_actor_id())
  );

comment on policy gradebook_scope on gradebook_score is
  'นักศึกษาดูคะแนนที่ครูเผยแพร่แล้วได้ แต่กรอกและแก้ไม่ได้ — ทดสอบแล้วว่าเดิมตั้ง score = 100 ให้ตัวเองได้';

-- ───────────────────────────────────────────────────────────────────
-- เกรดเฉลี่ยรายภาคและสะสม — คำนวณจากผลการเรียน ไม่ใช่ค่าที่ใครกรอกเอง
-- ───────────────────────────────────────────────────────────────────
drop policy if exists term_summary_scope on term_summary;

create policy term_summary_scope on term_summary
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = term_summary.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_grades)
  )
  -- compute_term_summary() ถูกเรียกจากเส้นทางที่กั้นด้วยบทบาทระดับวิทยาลัย
  -- เท่านั้น ครูจึงไม่ต้องเขียนตารางนี้แม้จะเป็นคนส่งเกรดต้นทาง
  with check (is_institution_wide_role());

create policy term_summary_no_owner_delete on term_summary
  as restrictive for delete
  using (is_institution_wide_role());

comment on policy term_summary_scope on term_summary is
  'เจ้าของและผู้ปกครองที่ได้รับสิทธิ์ดูเกรดเฉลี่ยได้ แต่แก้ไม่ได้ — เดิมนักศึกษาตั้ง gpa = 4.00 ให้ตัวเองได้';

-- ───────────────────────────────────────────────────────────────────
-- ทะเบียนนักศึกษา — สถานะเป็นตัวตัดสินว่ายังเรียนอยู่หรือจบแล้ว
--
-- สถานะยังเป็นตัวคูณของโควตาแพ็กเกจ (0038) ด้วย การแก้สถานะตัวเองจึง
-- กระทบทั้งการจบการศึกษาและยอดที่วิทยาลัยต้องจ่ายผู้ให้บริการ
-- ───────────────────────────────────────────────────────────────────
drop policy if exists subject_scope on student;

create policy subject_scope on student
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from person p
                where p.id = student.person_id and p.id = current_actor_id())
    or exists (select 1 from student_guardian sg
                where sg.student_id = student.id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null)
  )
  with check (is_institution_wide_role());

create policy student_no_owner_delete on student
  as restrictive for delete
  using (is_institution_wide_role());

comment on policy subject_scope on student is
  'ครู เจ้าตัว และผู้ปกครองที่ยืนยันแล้วอ่านได้ แต่เขียนได้เฉพาะบทบาทระดับวิทยาลัย — เดิมนักศึกษาตั้งสถานะตัวเองเป็น graduated ได้';

-- ───────────────────────────────────────────────────────────────────
-- ประวัติการเปลี่ยนสถานะ — เขียนโดย trigger บน student
--
-- ลบได้เท่ากับลบหลักฐานว่าเคยพ้นสภาพหรือเคยถูกพักการเรียน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists status_history_scope on student_status_history;

create policy status_history_scope on student_status_history
  as restrictive
  using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())
  )
  with check (is_institution_wide_role());

create policy status_history_no_owner_delete on student_status_history
  as restrictive for delete
  using (is_institution_wide_role());

-- ───────────────────────────────────────────────────────────────────
-- การลงทะเบียนเรียน
--
-- ครูผู้สอนอ่านได้เพราะต้องเห็นรายชื่อคนในห้อง แต่การเพิ่ม-ถอนรายวิชา
-- เป็นงานทะเบียน ไม่ใช่งานครู
-- ───────────────────────────────────────────────────────────────────
drop policy if exists enrollment_scope on enrollment;

create policy enrollment_scope on enrollment
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from class_section cs
                 join staff st on st.id = cs.teacher_id
                where cs.id = enrollment.class_section_id
                  and st.person_id = current_actor_id())
    or student_id in (select actor_student_ids())
  )
  with check (is_institution_wide_role());

create policy enrollment_no_owner_delete on enrollment
  as restrictive for delete
  using (is_institution_wide_role());

-- ───────────────────────────────────────────────────────────────────
-- การเงิน — ใบแจ้งหนี้ รายการในใบ และงวดผ่อนชำระ
--
-- ทั้งสามตารางใช้ประโยคเดียวกันคือ "เจ้าของหรือผู้ปกครองที่ได้รับสิทธิ์
-- ดูการเงิน" ซึ่งต้องอ่านได้จริง เพราะหน้าจอยอดค้างชำระของนักศึกษา
-- และผู้ปกครองพึ่งข้อนี้ทั้งหมด — ปิดเฉพาะการเขียน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists subject_scope on invoice;

create policy subject_scope on invoice
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from student s
                where s.id = invoice.student_id and s.person_id = current_actor_id())
    or exists (select 1 from student_guardian sg
                where sg.student_id = invoice.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  )
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy invoice_no_owner_delete on invoice
  as restrictive for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

drop policy if exists finance_subject_scope on invoice_line;

create policy finance_subject_scope on invoice_line
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from invoice i
                 join student s on s.id = i.student_id
                where i.id = invoice_line.invoice_id
                  and s.person_id = current_actor_id())
    or exists (select 1 from invoice i
                 join student_guardian sg on sg.student_id = i.student_id
                where i.id = invoice_line.invoice_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  )
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy invoice_line_no_owner_delete on invoice_line
  as restrictive for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

drop policy if exists finance_subject_scope on installment;

create policy finance_subject_scope on installment
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from invoice i
                 join student s on s.id = i.student_id
                where i.id = installment.invoice_id
                  and s.person_id = current_actor_id())
    or exists (select 1 from invoice i
                 join student_guardian sg on sg.student_id = i.student_id
                where i.id = installment.invoice_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  )
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy installment_no_owner_delete on installment
  as restrictive for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

comment on policy subject_scope on invoice is
  'เจ้าของและผู้ปกครองที่ได้รับสิทธิ์ดูยอดค้างชำระได้ แต่แก้ไม่ได้ — เดิมนักศึกษาตั้ง status = paid ให้ตัวเองได้';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0042_write_scope_auth.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0042_write_scope_auth.sql
--
-- ปิดช่องที่เจ้าของบัญชียกระดับสิทธิ์ตัวเองผ่านตารางกลุ่มยืนยันตัวตน
--
-- ─── อาการที่ทดสอบแล้วเกิดขึ้นจริง ───
-- ตั้งบริบทเป็นเจ้าของบัญชี (app.role = 'student') แล้วยิง update ตรง ๆ
-- เจ็ดข้อนี้สำเร็จหมด ทุกข้อคือการถอดมาตรการที่ระบบสร้างไว้กันตัวเอง
--
--   ปลดล็อกบัญชีตัวเอง        การล็อกหลังใส่รหัสผิด 5 ครั้งไม่มีความหมาย
--   ยกเลิกการระงับบัญชีตัวเอง  งานทะเบียนระงับบัญชีแล้วเจ้าตัวเปิดคืนได้
--   เปลี่ยนชื่อผู้ใช้ตัวเอง     สวมชื่อผู้ใช้ที่ยังว่างอยู่ได้
--   ปิด MFA ของตัวเอง          ถอดชั้นที่สองทิ้งโดยไม่ต้องใส่รหัสสักครั้ง
--   ล้างตัวนับ MFA             เดารหัสหกหลักได้ไม่จำกัดจำนวนครั้ง
--   ลบ MFA ทิ้งทั้งแถว         เหมือนไม่เคยตั้งชั้นที่สองเลย
--   อนุมัติอุปกรณ์ของตัวเอง    การผูกบัญชีกับเครื่องเดียวไม่มีความหมาย
--
-- ─── ทำไมกลุ่มนี้แก้ยากกว่า 0039 กับ 0041 ───
-- สองไฟล์นั้นตัดสิทธิ์เขียนของเจ้าของทิ้งได้เลย เพราะเจ้าของไม่เคยต้อง
-- เขียนคะแนนหรือใบแจ้งหนี้ของตัวเอง แต่กลุ่มนี้ **เจ้าของต้องเขียนได้จริง**
-- — เปลี่ยนรหัสผ่านเอง และเพิกถอน session ของตัวเองตอนเปลี่ยนรหัสผ่าน
--
-- จึงแยกเป็นสองแบบตามที่เส้นทางจริงเขียนจริง (ตรวจกับโค้ดทุกเส้นทางแล้ว)
--
--   ก. ตารางที่ **บทบาท auth เขียนล้วน ๆ** — mfa_credential ·
--      mfa_recovery_code · device_binding · password_reset · auth_identity
--      ทั้งหมดเขียนผ่าน AuthService ที่ใช้ db.runAs(authCtx) เสมอ
--      เจ้าของจึงไม่ต้องมีสิทธิ์เขียนเลยแม้แต่คอลัมน์เดียว → ปิดด้วย RLS ล้วน
--
--   ข. ตารางที่ **เจ้าของเขียนบางคอลัมน์** — user_credential กับ auth_session
--      RLS เป็นกฎระดับแถว แยกรายคอลัมน์ไม่ได้ จึงต้องใช้ trigger
--      (ตรงกับหลักที่ว่า "อย่าใช้ security definer เลี่ยงนโยบาย ใช้ trigger แทน")
--
-- ─── auth_session ใช้ RLS อย่างเดียวได้โดยไม่ต้องมี trigger ───
-- เจ้าของต้องทำได้อย่างเดียวคือ **เพิกถอน** session ของตัวเอง เงื่อนไข
-- "แถวหลังเขียนต้องมี revoked_at" เขียนใน with check ได้ตรง ๆ — การต่ออายุ
-- session ที่ยังใช้งานอยู่จึงเป็นไปไม่ได้ เพราะผลลัพธ์จะยังไม่ถูกเพิกถอน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ก. ตารางที่บทบาท auth เขียนล้วน ๆ — เจ้าของอ่านได้อย่างเดียว
-- ───────────────────────────────────────────────────────────────────

-- ความลับ TOTP — ออก ยืนยัน นับครั้งที่ผิด และปิด ล้วนทำผ่าน AuthService
-- ที่รันในบทบาท auth ทั้งหมด (mfaEnroll · mfaConfirm · mfaDisable ·
-- verifyStepCommitted) เจ้าตัวจึงไม่ต้องเขียนแถวนี้เองเลย
drop policy if exists mfa_credential_scope on mfa_credential;

create policy mfa_credential_scope on mfa_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'admin'));

create policy mfa_credential_no_owner_delete on mfa_credential
  as restrictive for delete
  using (current_app_role() in ('auth', 'admin'));

comment on policy mfa_credential_scope on mfa_credential is
  'เจ้าของดูสถานะ MFA ของตัวเองได้ แต่ปิดหรือลบเองไม่ได้ — เดิมสั่ง disabled_at = now() ถอดชั้นที่สองทิ้งได้';

drop policy if exists mfa_recovery_code_scope on mfa_recovery_code;

create policy mfa_recovery_code_scope on mfa_recovery_code
  as restrictive
  using (
    current_app_role() = 'auth'
    or exists (select 1 from mfa_credential mc
                where mc.id = mfa_recovery_code.credential_id
                  and mc.person_id = current_actor_id())
  )
  with check (current_app_role() = 'auth');

create policy mfa_recovery_code_no_owner_delete on mfa_recovery_code
  as restrictive for delete
  using (current_app_role() = 'auth');

-- การผูกบัญชีกับอุปกรณ์ — กันการยืมบัญชีกันเช็คอินแทน
-- ถ้าเจ้าตัวอนุมัติเครื่องใหม่ให้ตัวเองได้ มาตรการนี้เท่ากับไม่มี
drop policy if exists device_scope on device_binding;

create policy device_scope on device_binding
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin'));

create policy device_binding_no_owner_delete on device_binding
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin'));

comment on policy device_scope on device_binding is
  'เจ้าของเห็นรายการอุปกรณ์ของตัวเองได้ แต่อนุมัติเองไม่ได้ — เดิมตั้ง approved_at ให้เครื่องใหม่ของตัวเองได้';

-- คำขอรหัสรีเซ็ตรหัสผ่าน — ออกและใช้ผ่านบทบาท auth เท่านั้น
-- (งานทะเบียนออกให้ที่เคาน์เตอร์ผ่านบทบาทของตัวเอง)
drop policy if exists reset_scope on password_reset;

create policy reset_scope on password_reset
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'registrar', 'admin'));

create policy password_reset_no_owner_delete on password_reset
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'admin'));

drop policy if exists identity_scope on auth_identity;

create policy identity_scope on auth_identity
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'registrar', 'admin'));

create policy auth_identity_no_owner_delete on auth_identity
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'admin'));

-- ───────────────────────────────────────────────────────────────────
-- ข.1 session — เจ้าของเพิกถอนของตัวเองได้ แต่ต่ออายุไม่ได้
--
-- เงื่อนไขคือ "แถวหลังเขียนต้องถูกเพิกถอนแล้ว" ซึ่งครอบทั้งการออกจากระบบ
-- และการเตะทุกอุปกรณ์ตอนเปลี่ยนรหัสผ่าน (changePassword เพิกถอน session
-- ในบริบทของเจ้าตัวเอง ไม่ใช่บทบาท auth)
--
-- ส่วนการต่ออายุเป็นไปไม่ได้ เพราะผลลัพธ์จะยังมี revoked_at เป็น null
-- และการสร้าง session ใหม่ก็ไม่ได้ด้วยเหตุผลเดียวกัน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists session_scope on auth_session;

create policy session_scope on auth_session
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  )
  with check (
    current_app_role() in ('auth', 'admin')
    or (person_id = current_actor_id() and revoked_at is not null)
  );

create policy auth_session_no_owner_delete on auth_session
  as restrictive for delete
  using (current_app_role() in ('auth', 'admin'));

comment on policy session_scope on auth_session is
  'เจ้าของออกจากระบบของตัวเองได้ (เขียนได้เฉพาะผลลัพธ์ที่ถูกเพิกถอนแล้ว) แต่ต่ออายุ session ไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- ข.2 บัญชีผู้ใช้ — เจ้าของเปลี่ยนได้เฉพาะรหัสผ่านของตัวเอง
--
-- ─── ทำไมต้องเป็น trigger ไม่ใช่ RLS ───
-- RLS ตัดสินเป็นราย **แถว** ไม่ใช่ราย **คอลัมน์** แต่สิ่งที่ต้องแยกตรงนี้
-- คือคอลัมน์ — password_hash เจ้าตัวเปลี่ยนได้ ส่วน locked_until,
-- disabled_at, username, person_id เปลี่ยนไม่ได้ ถ้าใช้ RLS อย่างเดียว
-- ต้องเลือกระหว่าง "เจ้าตัวเปลี่ยนรหัสผ่านเองไม่ได้" กับ "เจ้าตัวปลดล็อก
-- บัญชีตัวเองได้" ซึ่งทั้งสองทางยอมรับไม่ได้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists credential_scope on user_credential;

create policy credential_scope on user_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  )
  -- เจ้าของยังผ่านชั้นนี้ได้เพื่อเปลี่ยนรหัสผ่าน คอลัมน์ที่แตะได้จริง
  -- ถูกจำกัดด้วย trigger ข้างล่าง
  with check (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

create policy user_credential_no_owner_delete on user_credential
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'admin'));

create or replace function user_credential_owner_guard() returns trigger
language plpgsql as $$
begin
  -- บทบาทที่ดูแลบัญชีคนอื่นได้อยู่แล้ว ไม่ต้องผ่านด่านนี้
  if current_app_role() in ('auth', 'registrar', 'admin') then
    return new;
  end if;

  /*
   * ─── ทำไมต้องปล่อยผ่านเมื่อไม่มีบริบทแอปเลย ───
   * trigger ยิงกับ **ทุกคน** รวมถึง superuser และฟังก์ชันที่ถูกเรียกตรง
   * จากฐานข้อมูล ต่างจาก RLS ที่ superuser ข้ามได้
   *
   * consume_password_reset() (0025) ล้าง failed_attempts และ locked_until
   * โดยตั้งใจ — คนที่ลืมรหัสผ่านจนบัญชีถูกล็อกต้องกลับเข้าระบบได้ ถ้าไม่
   * ปล่อยผ่าน การรีเซ็ตรหัสผ่านจะพังทั้งเส้นทางสำหรับคนที่ถูกล็อกอยู่
   * ซึ่งคือคนส่วนใหญ่ที่ใช้ทางนี้
   *
   * ปล่อยผ่านตรงนี้ไม่ได้เปิดช่องให้ใครเพิ่ม เพราะบริบทที่ไม่มี app.role
   * ก็ไม่มี app.institution_id กับ app.actor_id ด้วย นโยบาย RLS ของตาราง
   * นี้จึงปฏิเสธทุกแถวอยู่แล้วสำหรับผู้ใช้ที่ไม่ใช่ superuser
   */
  if current_app_role() = 'none' then
    return new;
  end if;

  -- ถึงตรงนี้แปลว่าเจ้าของบัญชีเป็นคนเขียนเอง — เปลี่ยนได้เฉพาะรหัสผ่าน
  -- (ตรงกับที่ AuthService.changePassword เขียนจริงสามคอลัมน์)
  if new.username        is distinct from old.username
     or new.person_id       is distinct from old.person_id
     or new.institution_id  is distinct from old.institution_id then
    raise exception 'เปลี่ยนชื่อผู้ใช้หรือเจ้าของบัญชีเองไม่ได้ ต้องให้งานทะเบียนเป็นผู้ดำเนินการ';
  end if;

  if new.disabled_at is distinct from old.disabled_at then
    raise exception 'ยกเลิกการระงับบัญชีของตัวเองไม่ได้ ต้องให้งานทะเบียนเป็นผู้ดำเนินการ';
  end if;

  -- ข้อนี้สำคัญที่สุด — ถ้าปลดล็อกเองได้ การล็อกบัญชีหลังเดารหัสผิด
  -- ห้าครั้งจะไม่มีความหมายเลย เพราะผู้ที่ยึด session ไปแล้วปลดเองได้ทันที
  if new.locked_until    is distinct from old.locked_until
     or new.failed_attempts is distinct from old.failed_attempts then
    raise exception 'ปลดล็อกบัญชีของตัวเองไม่ได้ กรุณารอจนครบกำหนดหรือติดต่องานทะเบียน';
  end if;

  return new;
end $$;

create trigger user_credential_owner_columns
  before update on user_credential
  for each row execute function user_credential_owner_guard();

comment on function user_credential_owner_guard() is
  'เจ้าของบัญชีเปลี่ยนได้เฉพาะรหัสผ่าน — RLS แยกรายคอลัมน์ไม่ได้จึงต้องใช้ trigger';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0043_staff_import.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0043_staff_import.sql
--
-- นำเข้าข้อมูลบุคลากรจากไฟล์ — ปิดข้อสุดท้ายของการย้ายระบบ
--
-- ─── ทำไมข้อนี้ขวางการย้ายระบบจริง ───
-- `import_kind` มี `'staff'` เตรียมไว้ตั้งแต่ 0023 แต่ไม่เคยมีตัวนำเข้าจริง
-- วิทยาลัยที่ย้ายจากระบบเดิมจึงนำเข้านักศึกษาได้เป็นพันคนในนาทีเดียว
-- แต่ต้องกรอกบุคลากรทีละคนเป็นร้อยคน ซึ่งเป็นงานที่ทำให้การย้ายระบบ
-- ค้างอยู่ตรงนั้นทั้งสัปดาห์ และเป็นจุดที่คนตัดสินใจเลิกย้าย
--
-- ─── ทำไมนำเข้าบุคลากรเสี่ยงกว่านำเข้านักศึกษา ───
-- แถวบุคลากรหนึ่งแถวสร้าง **สิทธิ์** ในระบบ ไม่ใช่แค่ข้อมูล — ถ้าไฟล์
-- กำหนดบทบาทได้อย่างอิสระ ใครที่แก้ไฟล์ CSV ระหว่างทางจะแต่งตั้งตัวเอง
-- เป็น admin ได้ทันที
--
-- ไฟล์นี้จึง **ตั้งบทบาทไม่ได้เลยสักค่า** เพราะทุกค่าใน staff_role_kind
-- (registrar · academic · finance · student_affairs · director · admin)
-- เห็นข้อมูลทั้งวิทยาลัย ต้องแต่งตั้งทีละคนผ่าน staff_role ซึ่งบันทึกว่า
-- ใครแต่งตั้งใครเมื่อไรและด้วยเหตุผลอะไร
--
-- ส่วน "เป็นครูหรือไม่" ไม่ใช่บทบาท แต่เป็น `staff.is_teacher` ซึ่งไฟล์ตั้งได้
-- เพราะให้สิทธิ์เห็นเฉพาะห้องที่ตัวเองสอน — ค่าเริ่มต้นเป็น false เสมอ
--
-- ─── โครงเดียวกับการนำเข้านักศึกษาทุกอย่าง ───
-- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด · คืนปัญหาทั้งหมดของแถว
-- ไม่ใช่ข้อแรกที่เจอ · นำเข้าซ้ำรอบเดิมไม่ได้ (หลักเดียวกับ 0023)
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจข้อมูลบุคลากรหนึ่งแถว
--
-- คืนรายการปัญหาทั้งหมด ไม่หยุดที่ข้อแรก — ไฟล์ร้อยแถวที่ต้องแก้ทีละข้อ
-- แล้วนำเข้าใหม่ทุกครั้งคือการทำงานหลายวัน
-- ───────────────────────────────────────────────────────────────────
create or replace function validate_staff_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors text[] := '{}';
  v_code   text := nullif(btrim(p_payload->>'staff_code'), '');
  v_first  text := nullif(btrim(p_payload->>'first_name_th'), '');
  v_last   text := nullif(btrim(p_payload->>'last_name_th'), '');
  v_nat    text := nullif(btrim(p_payload->>'national_id'), '');
  v_emp    text := nullif(btrim(p_payload->>'employment_kind'), '');
  v_dept   text := nullif(btrim(p_payload->>'department_code'), '');
  v_role   text := nullif(btrim(p_payload->>'role'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวบุคลากร');
  elsif exists (select 1 from staff st
                 where st.institution_id = p_institution_id and st.staff_code = v_code) then
    v_errors := array_append(v_errors, format('รหัสประจำตัวบุคลากร %s มีอยู่ในระบบแล้ว', v_code));
  end if;

  if v_first is null then v_errors := array_append(v_errors, 'ไม่มีชื่อ'); end if;
  if v_last  is null then v_errors := array_append(v_errors, 'ไม่มีนามสกุล'); end if;

  -- ตรวจ checksum ตั้งแต่ตอนนำเข้า เหตุผลเดียวกับฝั่งนักศึกษา —
  -- เลขนี้ใช้ยันตัวตนตอนออกเอกสารและตอนเบิกจ่าย
  if v_nat is not null then
    if v_nat !~ '^\d{13}$' then
      v_errors := array_append(v_errors, 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก');
    elsif not thai_national_id_valid(v_nat) then
      v_errors := array_append(v_errors, format('เลขประจำตัวประชาชน %s ไม่ผ่านการตรวจหลักที่ 13', v_nat));
    end if;
  end if;

  if v_emp is not null
     and v_emp not in ('civil_servant','permanent','contract','part_time','industry_expert') then
    v_errors := array_append(v_errors,
      format('ประเภทการจ้าง "%s" ไม่ถูกต้อง (civil_servant · permanent · contract · part_time · industry_expert)', v_emp));
  end if;

  -- หน่วยงานต้องมีอยู่จริงก่อน ไม่สร้างให้อัตโนมัติ — แผนกที่เกิดจาก
  -- การพิมพ์ผิดในไฟล์จะกลายเป็นแผนกผีที่มีคนสังกัดอยู่จริงหนึ่งคน
  if v_dept is not null
     and not exists (select 1 from department d
                      where d.institution_id = p_institution_id and d.code = v_dept) then
    v_errors := array_append(v_errors,
      format('ไม่พบหน่วยงานรหัส %s — ต้องสร้างหน่วยงานก่อนนำเข้าบุคลากร', v_dept));
  end if;

  if v_dept is not null and nullif(btrim(p_payload->>'position_th'), '') is null then
    v_errors := array_append(v_errors, 'ระบุหน่วยงานแล้วต้องระบุตำแหน่งด้วย');
  end if;

  /*
   * ─── ข้อนี้คือความต่างสำคัญที่สุดจากการนำเข้านักศึกษา ───
   * แถวบุคลากรสร้าง **สิทธิ์** ในระบบ ไม่ใช่แค่ข้อมูล ไฟล์จึงตั้งบทบาท
   * ไม่ได้เลยสักค่า ต่อให้คนที่กดนำเข้าจะเป็น admin เองก็ตาม — เพราะไฟล์
   * ผ่านมือหลายคนและไม่มีใครตรวจทุกแถวด้วยตาก่อนกดนำเข้า
   *
   * ทุกค่าใน staff_role_kind (registrar · academic · finance ·
   * student_affairs · director · admin) เห็นข้อมูลทั้งวิทยาลัย จึงต้อง
   * แต่งตั้งทีละคนผ่าน staff_role ซึ่งบันทึกว่าใครแต่งตั้ง เมื่อไร
   * และด้วยเหตุผลอะไร
   *
   * ส่วน "เป็นครูหรือไม่" ไม่ใช่บทบาท แต่เป็น staff.is_teacher ซึ่งไฟล์
   * ตั้งได้ตามปกติ เพราะมันให้สิทธิ์เห็นเฉพาะห้องที่ตัวเองสอนเท่านั้น
   */
  if v_role is not null then
    v_errors := array_append(v_errors,
      format('ไฟล์นำเข้าตั้งบทบาท "%s" ไม่ได้ — ทุกบทบาทในระบบเห็นข้อมูลทั้งวิทยาลัย ' ||
             'ต้องแต่งตั้งทีละคนผ่านงานบุคลากร (ระบุการเป็นครูด้วยช่อง is_teacher แทน)', v_role));
  end if;

  return v_errors;
end $$;

comment on function validate_staff_row(uuid, jsonb) is
  'ตรวจข้อมูลบุคลากรหนึ่งแถว — คืนปัญหาทั้งหมด และปฏิเสธการตั้งบทบาทจากไฟล์ทุกกรณี';

-- ───────────────────────────────────────────────────────────────────
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_staff_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch  import_batch%rowtype;
  r        record;
  v_person uuid;
  v_staff  uuid;
  v_dept   uuid;
  v_bad    integer := 0;
  v_ok     integer := 0;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'staff' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ข้อมูลบุคลากร', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_staff_row(v_batch.institution_id, r.payload);
      update import_row
         set errors = v_errs, ok = (cardinality(v_errs) = 0)
       where id = r.id;
      if cardinality(v_errs) > 0 then v_bad := v_bad + 1; end if;
    end;
  end loop;

  if v_bad > 0 then
    update import_batch
       set status = 'failed', error_rows = v_bad,
           ok_rows = (select count(*) from import_row where batch_id = p_batch_id and ok)
     where id = p_batch_id;
    /*
     * ─── ทำไมข้อความไม่ชี้ไปที่ import_row ───
     * `raise` ทำให้ rollback กลับไปก่อนหน้าฟังก์ชันนี้ทั้งหมด รวมถึงบรรทัด
     * update import_row set errors = ... ที่เพิ่งเขียนไปข้างบน รายละเอียด
     * รายแถวจึงหายไปพร้อมกับข้อผิดพลาด — บอกให้ไปดูที่นั่นคือส่งคนไปดู
     * ตารางว่าง (กับดักเดียวกับตัวนับใน login_rate_status · 0021)
     *
     * เส้นทางที่ถูกต้องคือเรียกตรวจ (validate) ก่อน ซึ่ง commit ผลไว้จริง
     * แล้วค่อยนำเข้า — ชั้น API ทำแบบนั้นอยู่แล้ว
     */
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email)
    values (
      v_batch.institution_id,
      nullif(btrim(r.payload->>'prefix_th'), ''),
      btrim(r.payload->>'first_name_th'),
      btrim(r.payload->>'last_name_th'),
      -- ค่าแฮชเท่านั้น เหตุผลเดียวกับ 0023 — national_id_enc รอเชื่อม KMS
      case when nullif(btrim(r.payload->>'national_id'), '') is not null
           then digest(btrim(r.payload->>'national_id'), 'sha256') end,
      (nullif(btrim(r.payload->>'birth_date'), ''))::date,
      coalesce(nullif(btrim(r.payload->>'gender'), ''), 'undisclosed')::gender_kind,
      nullif(btrim(r.payload->>'phone'), ''),
      nullif(btrim(r.payload->>'email'), '')
    )
    returning id into v_person;

    insert into staff
      (institution_id, person_id, staff_code, employment_kind, is_teacher,
       license_no, license_expires)
    values (
      v_batch.institution_id, v_person,
      btrim(r.payload->>'staff_code'),
      coalesce(nullif(btrim(r.payload->>'employment_kind'), ''), 'permanent')::employment_kind,
      -- ค่าเริ่มต้นเป็น "ไม่ใช่ครู" โดยตั้งใจ — is_teacher เปิดสิทธิ์เห็น
      -- ข้อมูลนักศึกษาในห้องที่สอน ถ้าเดาให้เป็น true คนที่ไม่ได้สอน
      -- จะได้สิทธิ์นั้นไปด้วยทั้งไฟล์
      coalesce((r.payload->>'is_teacher')::boolean, false),
      nullif(btrim(r.payload->>'license_no'), ''),
      (nullif(btrim(r.payload->>'license_expires'), ''))::date
    )
    returning id into v_staff;

    -- สังกัดหน่วยงาน (ถ้าระบุมา — validate_staff_row ตรวจแล้วว่ามีอยู่จริง)
    if nullif(btrim(r.payload->>'department_code'), '') is not null then
      select d.id into v_dept
        from department d
       where d.institution_id = v_batch.institution_id
         and d.code = btrim(r.payload->>'department_code');

      insert into staff_assignment (staff_id, department_id, position_th, is_primary)
      values (v_staff, v_dept, btrim(r.payload->>'position_th'), true);
    end if;

    -- ไม่มีการเขียน staff_role ที่นี่โดยเจตนา — ดูเหตุผลใน validate_staff_row
    update import_row set created_ref = v_staff, ok = true where id = r.id;
    v_ok := v_ok + 1;
  end loop;

  update import_batch
     set status = 'applied', applied_at = now(),
         ok_rows = v_ok, error_rows = 0, total_rows = v_ok
   where id = p_batch_id;

  imported := v_ok;
  failed   := 0;
  return next;
end $$;

comment on function apply_staff_import(uuid) is
  'นำเข้าบุคลากรทั้งชุดหรือไม่เขียนเลย — สร้าง person + staff + สังกัดหน่วยงาน และให้บทบาทได้แค่ teacher';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant execute on function validate_staff_row(uuid, jsonb) to app_runtime;
    grant execute on function apply_staff_import(uuid)        to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0044_transfer_credits.sql
-- ───────────────────────────────────────────────────────────────────

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


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0045_write_scope_student_records.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0045_write_scope_student_records.sql
--
-- ปิดช่องเขียนของเจ้าของในระเบียนนักศึกษาที่เหลือ
--
-- ─── อาการที่ทดสอบแล้วเกิดขึ้นจริง ───
-- ในบริบทนักศึกษา สามตารางนี้เขียนได้จริง (ยิง update แล้วมีแถวถูกแก้)
--
--   student_curriculum  เปลี่ยนฉบับหลักสูตรของตัวเอง = เปลี่ยนกฎการจบ
--                       ที่ใช้กับตัวเองไปเป็นฉบับที่ผ่านง่ายกว่า
--   student_guardian    แก้สิทธิ์ของผู้ปกครองตัวเอง เช่นปิดไม่ให้เห็นเกรด
--   enrollment_result   แถวผลการเรียนของตัวเอง (มี trigger กันการแก้ทับอยู่
--                       อีกชั้น แต่ไม่ควรผ่านมาถึง trigger ตั้งแต่แรก)
--
-- ตารางที่เหลือในไฟล์นี้ทดสอบแล้วไม่พบแถวให้เขียน — ซึ่ง**ไม่ได้แปลว่าปิดอยู่**
-- แค่แปลว่าข้อมูลตัวอย่างไม่มีแถวของนักศึกษาคนที่ทดสอบ นโยบายของทุกตาราง
-- ในรายการนี้มีประโยคเจ้าของอยู่ใน `using` เหมือนกันหมด จึงเปิดช่องเดียวกัน
-- เมื่อมีข้อมูลจริง
--
-- ─── ทำไมเพิ่มนโยบายใหม่แทนการเขียนของเดิมทับ ───
-- ไฟล์ก่อนหน้า (0039 · 0041 · 0042) เขียนนโยบายเดิมทับทั้งก้อน ซึ่งต้อง
-- คัดลอกประโยค `using` ที่ยาวและซับซ้อนมาใหม่ให้ตรงทุกตัวอักษร — สิบห้า
-- ตารางแบบนั้นคือสิบห้าโอกาสที่จะพิมพ์ตกแล้ว**เปิดสิทธิ์อ่านกว้างขึ้น**
-- โดยไม่มีใครเห็น
--
-- restrictive policy รวมกันด้วย AND การเพิ่มนโยบายที่คุมเฉพาะ
-- insert/update/delete จึงบีบสิทธิ์เขียนให้แคบลงโดย**ไม่แตะสิทธิ์อ่านเลย**
-- เจ้าของยังเห็นข้อมูลของตัวเองครบเหมือนเดิมทุกตาราง
--
-- ─── ใครยังเขียนได้ ───
-- บทบาทระดับวิทยาลัยเท่านั้น (registrar · academic · finance ·
-- student_affairs · director · admin) ตรงกับ @Roles ของทุกเส้นทางที่เขียน
-- ตารางเหล่านี้อยู่แล้ว — ตรวจทีละเส้นทางแล้ว ไม่มีเส้นทางไหนให้ครูหรือ
-- นักศึกษาเขียน
-- ═══════════════════════════════════════════════════════════════════
begin;

do $$
declare
  t text;
  tables constant text[] := array[
    -- ระเบียนการเรียนและการจบ
    'enrollment_result', 'student_curriculum', 'student_graduation',
    'student_graduation_status', 'cocurricular_result',
    'professional_standard_assessment', 'prior_academic_record',
    'regrade_candidate',
    -- การจัดชั้นเรียน
    'student_placement', 'student_class_placement',
    -- ผู้ปกครอง
    'student_guardian',
    -- เอกสารที่ออกให้
    'issued_document',
    -- ข้อมูลอ่อนไหวของผู้เยาว์ตาม PDPA — ผลคัดกรองและบันทึกเยี่ยมบ้าน
    'screening_result', 'home_visit'
  ];
begin
  foreach t in array tables loop
    -- นโยบายเดิมยังอยู่ครบ ไม่ถูกแตะ — สามข้อนี้ AND ทับลงไปเฉพาะการเขียน
    execute format($f$
      create policy %1$I_staff_insert on %1$I
        as restrictive for insert
        with check (is_institution_wide_role())
    $f$, t);

    execute format($f$
      create policy %1$I_staff_update on %1$I
        as restrictive for update
        using (is_institution_wide_role())
        with check (is_institution_wide_role())
    $f$, t);

    execute format($f$
      create policy %1$I_staff_delete on %1$I
        as restrictive for delete
        using (is_institution_wide_role())
    $f$, t);
  end loop;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกฝึกอาชีพ — ต้องรวมครูด้วย
--
-- ─── ทำไมแยกจากรายการข้างบน ───
-- ครูนิเทศเป็นคนรับรองชั่วโมงฝึกอาชีพ ไม่ใช่งานทะเบียน (verify_practicum_hours
-- ถูกเรียกในบริบท teacher และ POST ของ dual module กั้นด้วย @Roles ที่มี
-- teacher อยู่) ถ้าใช้ is_institution_wide_role() ล้วนเหมือนตารางอื่น
-- ครูจะรับรองชั่วโมงไม่ได้เลย แล้วกฎการจบข้อ practicum_hours จะไม่มีวันผ่าน
--
-- เจอเพราะ TEST 86 ล้มทันทีที่ใส่ practicum_log ลงในรายการข้างบน
-- ───────────────────────────────────────────────────────────────────
-- ─── และนักศึกษาบันทึกชั่วโมงของตัวเองได้ ตราบใดที่ยังไม่รับรอง ───
--
-- แอปของนักศึกษา (A-06) บันทึกชั่วโมงฝึกอาชีพเองได้โดยการออกแบบ —
-- คนที่อยู่ในสถานประกอบการคือคนที่รู้ว่าทำงานกี่ชั่วโมง ไม่ใช่ครูที่อยู่
-- คนละที่ ถ้าปิดตรงนี้ POST /practicum/logs ของนักศึกษาจะพังทันที
--
-- สิ่งที่ต้องกันคือ **การรับรองตัวเอง** ไม่ใช่การบันทึก — เงื่อนไข
-- `verified_at is null` เขียนใน with check ได้ตรง ๆ ชั่วโมงที่เจ้าตัว
-- บันทึกจึงไม่มีผลกับกฎการจบจนกว่าครูนิเทศจะรับรอง (evaluate_graduation
-- นับเฉพาะ verified_at ที่ไม่เป็น null อยู่แล้ว)
create policy practicum_log_staff_insert on practicum_log
  as restrictive for insert
  with check (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or (student_id in (select actor_student_ids()) and verified_at is null)
  );

create policy practicum_log_staff_update on practicum_log
  as restrictive for update
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or student_id in (select actor_student_ids())
  )
  with check (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or (student_id in (select actor_student_ids()) and verified_at is null)
  );

create policy practicum_log_staff_delete on practicum_log
  as restrictive for delete
  using (is_institution_wide_role() or current_app_role() = 'teacher');

comment on policy practicum_log_staff_update on practicum_log is
  'นักศึกษาดูชั่วโมงฝึกอาชีพของตัวเองได้ แต่บันทึกและรับรองเองไม่ได้ — ครูนิเทศเป็นผู้รับรอง';

comment on policy student_curriculum_staff_update on student_curriculum is
  'เจ้าของเปลี่ยนฉบับหลักสูตรของตัวเองไม่ได้ — เดิมทำได้ ซึ่งเท่ากับเลือกกฎการจบที่ผ่านง่ายกว่าให้ตัวเอง';
comment on policy student_guardian_staff_update on student_guardian is
  'เจ้าของแก้สิทธิ์ของผู้ปกครองตัวเองไม่ได้ — เดิมปิดไม่ให้ผู้ปกครองเห็นเกรดของตัวเองได้';
comment on policy home_visit_staff_update on home_visit is
  'บันทึกเยี่ยมบ้านเป็นข้อมูลอ่อนไหวของผู้เยาว์ตาม PDPA — เจ้าของอ่านได้แต่แก้และลบไม่ได้';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0046_teacher_availability.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0046_teacher_availability.sql
--
-- ข้อจำกัดเวลาสอนรายบุคคล — "ครูคนนี้ไม่สอนเช้าวันจันทร์"
--
-- ─── ทำไมตัวจัดตารางที่ไม่รู้ข้อจำกัดนี้ใช้งานจริงไม่ได้ ───
-- ทุกวิทยาลัยมีข้อจำกัดแบบนี้เสมอ — ครูที่สอนสองวิทยาเขต ครูที่ลาศึกษาต่อ
-- ครึ่งวัน ครูที่เป็นวิทยากรภายนอกซึ่งมาได้แค่บ่ายวันพุธ
--
-- ตัวจัดอัตโนมัติที่ไม่รู้เรื่องนี้จะวางคาบทับเวลาที่ครูไม่อยู่ แล้วคนจัด
-- ต้องมานั่งแก้ทีละคาบ ซึ่งใช้เวลามากกว่าจัดเองตั้งแต่แรก — ผลคือไม่มีใคร
-- ใช้ตัวจัดอัตโนมัติเลย
--
-- ─── ทำไมเก็บเป็น "ช่วงที่ไม่ว่าง" ไม่ใช่ "ช่วงที่ว่าง" ───
-- ครูส่วนใหญ่ว่างเกือบทั้งสัปดาห์ ถ้าเก็บช่วงที่ว่าง ทุกคนต้องกรอกทุกคาบ
-- ของทุกวันตั้งแต่ต้น และครูที่ยังไม่ได้กรอกจะกลายเป็น "ไม่ว่างเลย"
-- ซึ่งทำให้ตัวจัดตารางวางอะไรไม่ได้เลยทั้งวิทยาลัยในวันแรกที่เปิดใช้
--
-- เก็บเป็นช่วงที่ไม่ว่างแทน — ครูที่ไม่ได้กรอกอะไรคือครูที่ว่างตลอด
-- ซึ่งตรงกับความจริงและทำให้ deploy แล้วไม่มีอะไรพัง
--
-- ─── ทำไมมีทั้งแบบ "ห้าม" และ "เลี่ยงถ้าได้" ───
-- ครูที่ติดสอนอีกวิทยาเขตคือ **ห้าม** วางจริง ๆ ส่วนครูที่ขอไม่สอนคาบแรก
-- เพราะบ้านไกลคือ **เลี่ยงถ้าได้** ถ้าปนกันเป็นข้อห้ามทั้งหมด ตารางจะจัด
-- ไม่ลงเมื่อมีคำขอมาก และคนจัดจะเริ่มลบคำขอทิ้งเพื่อให้จัดได้ —
-- ซึ่งทำให้ข้อมูลนี้เชื่อถือไม่ได้ทั้งตาราง
-- ═══════════════════════════════════════════════════════════════════
begin;

create type availability_kind as enum ('unavailable', 'prefer_not');

comment on type availability_kind is
  'unavailable = ห้ามวาง (ติดภารกิจจริง) · prefer_not = เลี่ยงถ้าได้ (ความสะดวกส่วนตัว)';

create table teacher_availability (
  id             uuid              primary key default gen_random_uuid(),
  institution_id uuid              not null references institution on delete restrict,
  staff_id       uuid              not null references staff on delete cascade,
  term_id        uuid              references term on delete cascade,
  day_of_week    smallint          not null check (day_of_week between 1 and 7),
  period_from    smallint          not null check (period_from >= 1),
  period_to      smallint          not null check (period_to >= period_from),
  kind           availability_kind not null default 'unavailable',
  reason         text,
  created_by     uuid,
  created_at     timestamptz       not null default now()
);

comment on table teacher_availability is
  'ช่วงเวลาที่ครูสอนไม่ได้หรือขอเลี่ยง — ไม่กรอกอะไรเลยคือว่างตลอด';
comment on column teacher_availability.term_id is
  'จำกัดเฉพาะภาคเรียนนี้ — null คือใช้ทุกภาคเรียน (เช่นครูที่สอนสองวิทยาเขตประจำ)';

create index teacher_availability_lookup_idx
  on teacher_availability (staff_id, day_of_week);

-- ───────────────────────────────────────────────────────────────────
-- ครูของกลุ่มเรียนนี้ติดอะไรในช่วงเวลาที่จะวางหรือไม่
--
-- คืนเป็นแถว ไม่ใช่ boolean เพราะตัวเสนอคาบต้องบอกได้ว่า **ทำไม** วางไม่ได้
-- (หลักเดียวกับ timeslot_conflicts ที่คืนชนิดของการชน)
-- ───────────────────────────────────────────────────────────────────
create or replace function teacher_unavailable(
  p_class_section_id uuid,
  p_day_of_week      smallint,
  p_period_from      smallint,
  p_period_to        smallint,
  p_term_id          uuid default null
) returns table (
  kind   availability_kind,
  reason text
) language sql stable as $$
  select ta.kind, ta.reason
    from class_section cs
    join teacher_availability ta on ta.staff_id = cs.teacher_id
   where cs.id = p_class_section_id
     and ta.day_of_week = p_day_of_week
     -- ช่วงคาบซ้อนกัน (ไม่ใช่แค่เริ่มตรงกัน)
     and ta.period_from <= p_period_to
     and ta.period_to   >= p_period_from
     -- ข้อจำกัดที่ไม่ผูกภาคเรียนใช้ได้ทุกภาค
     and (ta.term_id is null or ta.term_id = coalesce(p_term_id, ta.term_id))
$$;

comment on function teacher_unavailable(uuid, smallint, smallint, smallint, uuid) is
  'ครูของกลุ่มเรียนติดอะไรในช่วงนี้ — คืนชนิดและเหตุผล เพื่อให้ตัวเสนอคาบบอกได้ว่าทำไมวางไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- ตัวเสนอคาบว่าง — เคารพข้อจำกัดของครู
--
-- คืน `avoids` มาด้วยว่าคาบนี้ตรงกับคำขอ "เลี่ยงถ้าได้" หรือไม่ และเรียง
-- คาบที่ไม่ตรงกับคำขอไว้ก่อน — คนจัดจะได้เลือกคาบที่ทุกฝ่ายพอใจก่อนเสมอ
-- โดยยังเห็นตัวเลือกที่เหลือถ้าจำเป็น
-- ───────────────────────────────────────────────────────────────────
-- ต้อง drop ตัวเดิมก่อน ไม่ใช่ create or replace — ชนิดที่คืนเปลี่ยนไป
-- (เพิ่ม avoids กับ note) และถ้าปล่อยตัวเก่าไว้จะกลายเป็นสองตัวซ้อนกัน
-- แล้วผู้เรียกเดิมที่ส่งสี่อาร์กิวเมนต์จะได้ตัวเก่าที่ไม่รู้จักข้อจำกัดของครู
-- ซึ่งเป็นความล้มเหลวแบบเงียบที่สุด — ระบบทำงานได้แต่ไม่เคารพข้อจำกัดเลย
--
-- อาร์กิวเมนต์ที่ห้าเป็น default จึงเรียกด้วยสี่ตัวได้เหมือนเดิม
-- (auto_schedule_term เรียกแบบนั้นและได้ตัวใหม่ไปโดยไม่ต้องแก้)
drop function if exists suggest_timeslots(uuid, smallint, uuid, integer);

create or replace function suggest_timeslots(
  p_class_section_id uuid,
  p_periods          smallint default 2,
  p_room_id          uuid default null,
  p_limit            integer default 10,
  p_term_id          uuid default null
) returns table (
  day_of_week smallint,
  period_from smallint,
  period_to   smallint,
  avoids      boolean,
  note        text
) language sql stable as $$
  with me as (
    select cs.institution_id from class_section cs where cs.id = p_class_section_id
  ),
  policy as (
    select coalesce(tp.periods_per_day, 10) as periods_per_day,
           coalesce(tp.days_per_week, 5)    as days_per_week
      from me left join timetable_policy tp on tp.institution_id = me.institution_id
  ),
  candidates as (
    select d::smallint as day_of_week,
           s::smallint as period_from,
           (s + p_periods - 1)::smallint as period_to
      from policy p,
           generate_series(1, p.days_per_week) d,
           generate_series(1, p.periods_per_day) s
     where s + p_periods - 1 <= p.periods_per_day
  ),
  usable as (
    select c.*,
           (select ta.kind from teacher_unavailable(
              p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_term_id) ta
             order by ta.kind limit 1) as block_kind,
           (select ta.reason from teacher_unavailable(
              p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_term_id) ta
             order by ta.kind limit 1) as block_reason
      from candidates c
     where not exists (
       select 1 from timeslot_conflicts(
         p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_room_id))
  )
  -- ต้อง coalesce เป็น false ทั้งในคอลัมน์และใน order by
  --
  -- คาบที่ไม่มีข้อจำกัดจะได้ block_kind เป็น null ทำให้ (null = 'prefer_not')
  -- เป็น null ไม่ใช่ false และ PostgreSQL เรียง null ไว้ **ท้ายสุด** ในลำดับ
  -- ขึ้น — ผลคือคาบที่ครูขอเลี่ยง (true) จะถูกเสนอมาก่อนคาบที่ไม่ติดอะไรเลย
  -- ซึ่งกลับด้านกับสิ่งที่ตั้งใจทั้งหมด
  select u.day_of_week, u.period_from, u.period_to,
         coalesce(u.block_kind = 'prefer_not', false) as avoids,
         case when u.block_kind = 'prefer_not'
              then coalesce(u.block_reason, 'ครูขอเลี่ยงคาบนี้') end as note
    from usable u
   -- ห้ามวางถูกตัดออกทั้งหมด ส่วนที่ขอเลี่ยงยังเสนอได้แต่ไปอยู่ท้ายรายการ
   where u.block_kind is distinct from 'unavailable'
   order by coalesce(u.block_kind = 'prefer_not', false),
            u.day_of_week, u.period_from
   limit p_limit;
$$;

comment on function suggest_timeslots(uuid, smallint, uuid, integer, uuid) is
  'คาบว่างที่วางได้จริง — ตัดช่วงที่ครูสอนไม่ได้ออก และเรียงคาบที่ครูขอเลี่ยงไว้ท้ายสุด';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on teacher_availability to app_runtime;
    grant execute on function teacher_unavailable(uuid, smallint, smallint, smallint, uuid)
      to app_runtime;
    grant execute on function suggest_timeslots(uuid, smallint, uuid, integer, uuid)
      to app_runtime;
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ครูอ่านของตัวเองได้ (ต้องเห็นว่าที่แจ้งไปถูกบันทึกแล้ว) แต่เขียนไม่ได้ —
-- ถ้าครูกรอกเองได้ ตารางสอนจะกลายเป็นเรื่องที่ต่อรองกันเองโดยไม่มีใคร
-- ตัดสิน และคนที่กรอกก่อนจะได้คาบที่ดีที่สุดเสมอ
-- ───────────────────────────────────────────────────────────────────
alter table teacher_availability enable row level security;
alter table teacher_availability force  row level security;

create policy tenant_isolation on teacher_availability
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy availability_scope on teacher_availability
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
                where st.id = teacher_availability.staff_id
                  and st.person_id = current_actor_id())
  )
  with check (is_institution_wide_role());

create policy availability_no_teacher_delete on teacher_availability
  as restrictive for delete
  using (is_institution_wide_role());

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0047_student_checkin.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0047_student_checkin.sql
--
-- คำขอเช็คอินของนักศึกษา (A-05) — คนถูกเช็คไม่ใช่คนเขียนผล
--
-- ─── ข้อกำหนดที่ 0039 เขียนไว้ล่วงหน้า ───
-- migration 0039 ปิดช่องที่นักศึกษาแก้เวลาเรียนของตัวเองได้ และเขียนไว้ตรง ๆ
-- ว่าถ้าวันหน้าทำ A-05 ให้นักศึกษาเช็คอินเอง **ห้ามแก้ด้วยการเอาประโยค
-- actor_enrollment_ids() กลับเข้า with check** เพราะนั่นคือการเปิดช่องเดิมคืน
--
-- ทางที่ถูกคือตารางคำขอแยก ที่ครูยืนยันแล้วจึงกลายเป็น attendance_record
-- ไฟล์นี้ทำตามนั้น
--
-- ─── ทำไมคำขอไม่ใช่การเช็คชื่อ ───
-- แถวใน attendance_checkin ไม่มีผลกับกฎเวลาเรียน 80% เลยสักนิดจนกว่าครู
-- จะยืนยัน — นักศึกษาจึงกดได้ไม่จำกัดโดยไม่กระทบใคร และครูยังเป็นคนเดียว
-- ที่ตัดสินว่าใครมาเรียนจริง
--
-- ─── ทำไมเก็บพิกัดเป็นระยะห่าง ไม่ใช่พิกัดจริง ───
-- พิกัดของผู้เยาว์เป็นข้อมูลอ่อนไหวตาม PDPA และเก็บไว้ก็ตอบคำถามเดียว
-- ที่ระบบต้องการไม่ได้ดีไปกว่าระยะห่าง — "อยู่ในบริเวณวิทยาลัยไหม"
-- เก็บระยะห่างเป็นเมตรจึงพอ และย้อนกลับเป็นตำแหน่งบ้านใครไม่ได้
--
-- ─── ทำไมไม่บังคับพิกัด ───
-- โรงฝึกงานเป็นอาคารคอนกรีตหนาที่ GPS เข้าไม่ถึง ถ้าบังคับ นักศึกษาที่อยู่
-- ในห้องเรียนจริงจะเช็คอินไม่ได้ ส่วนคนที่อยากโกงก็ปลอมพิกัดได้อยู่ดี —
-- ค่านี้จึงเป็นข้อมูลประกอบให้ครูเห็น ไม่ใช่เงื่อนไขที่ระบบตัดสินเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

create type checkin_status as enum ('pending', 'accepted', 'rejected');

create table attendance_checkin (
  id               uuid           primary key default gen_random_uuid(),
  institution_id   uuid           not null references institution on delete restrict,
  class_meeting_id uuid           not null references class_meeting on delete cascade,
  enrollment_id    uuid           not null references enrollment on delete cascade,
  status           checkin_status not null default 'pending',

  -- ระยะห่างจากจุดที่วิทยาลัยกำหนด (เมตร) — null คือไม่มีสัญญาณหรือปฏิเสธ
  distance_m       integer        check (distance_m is null or distance_m >= 0),
  device_id        text,
  note             text,

  submitted_at     timestamptz    not null default now(),
  decided_at       timestamptz,
  decided_by       uuid           references staff on delete restrict,
  decision_note    text,

  -- กดซ้ำในคาบเดิมไม่สร้างแถวใหม่ — มิฉะนั้นครูจะเห็นคำขอสิบแถวของคนเดียว
  unique (class_meeting_id, enrollment_id)
);

comment on table attendance_checkin is
  'คำขอเช็คอินของนักศึกษา — ไม่มีผลกับกฎเวลาเรียนจนกว่าครูจะยืนยัน คนถูกเช็คต้องไม่ใช่คนเขียนผล';
comment on column attendance_checkin.distance_m is
  'ระยะห่างจากวิทยาลัยเป็นเมตร ไม่ใช่พิกัด — พิกัดของผู้เยาว์เป็นข้อมูลอ่อนไหวและเก็บไว้ก็ไม่ได้ตอบอะไรเพิ่ม';

create index attendance_checkin_pending_idx
  on attendance_checkin (class_meeting_id) where status = 'pending';

-- ───────────────────────────────────────────────────────────────────
-- นักศึกษาส่งคำขอเช็คอิน
--
-- ปฏิเสธคาบที่ปิดไปแล้วเพราะการเช็คอินย้อนหลังคือสิ่งที่มาตรการนี้กันอยู่
-- ───────────────────────────────────────────────────────────────────
create or replace function submit_checkin(
  p_class_meeting_id uuid,
  p_enrollment_id    uuid,
  p_distance_m       integer default null,
  p_device_id        text default null
) returns attendance_checkin
language plpgsql as $$
declare
  v_row    attendance_checkin;
  v_status text;
  v_inst   uuid;
begin
  select cm.status::text, cs.institution_id into v_status, v_inst
    from class_meeting cm
    join class_section cs on cs.id = cm.class_section_id
   where cm.id = p_class_meeting_id;

  if v_status is null then
    raise exception 'ไม่พบคาบเรียนนี้ หรือไม่มีสิทธิ์เข้าถึง';
  end if;
  if v_status <> 'scheduled' then
    raise exception 'คาบนี้ปิดไปแล้ว เช็คอินย้อนหลังไม่ได้ ติดต่อครูผู้สอน';
  end if;

  insert into attendance_checkin
    (institution_id, class_meeting_id, enrollment_id, distance_m, device_id)
  values (v_inst, p_class_meeting_id, p_enrollment_id, p_distance_m, p_device_id)
  on conflict (class_meeting_id, enrollment_id) do update
    set submitted_at = now(),
        distance_m   = excluded.distance_m,
        device_id    = excluded.device_id
    -- กดซ้ำหลังครูตัดสินไปแล้วไม่ล้างผลทิ้ง
    where attendance_checkin.status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'คำขอของคาบนี้ถูกตัดสินไปแล้ว ติดต่อครูผู้สอนถ้าไม่ถูกต้อง';
  end if;

  return v_row;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ครูยืนยันคำขอ — จุดเดียวที่คำขอกลายเป็นการเช็คชื่อจริง
--
-- เขียน attendance_record ให้ในบริบทของครูซึ่งมีสิทธิ์อยู่แล้วตาม 0039
-- ไม่ต้องใช้ security definer และไม่ต้องผ่อนนโยบายของ attendance_record เลย
-- ───────────────────────────────────────────────────────────────────
create or replace function decide_checkin(
  p_checkin_id uuid,
  p_accept     boolean,
  p_status     attendance_status default 'present',
  p_note       text default null
) returns attendance_checkin
language plpgsql as $$
declare
  v_row   attendance_checkin;
  v_staff uuid;
begin
  select st.id into v_staff
    from staff st where st.person_id = current_actor_id();

  update attendance_checkin
     set status        = case when p_accept then 'accepted' else 'rejected' end::checkin_status,
         decided_at    = now(),
         decided_by    = v_staff,
         decision_note = p_note
   where id = p_checkin_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ไม่พบคำขอนี้ หรือถูกตัดสินไปแล้ว';
  end if;

  if p_accept then
    -- เขียนผลจริง ณ จุดนี้เท่านั้น ถ้ามีแถวอยู่แล้วถือว่าครูแก้ผลเดิม
    insert into attendance_record (class_meeting_id, enrollment_id, status, note)
    values (v_row.class_meeting_id, v_row.enrollment_id, p_status,
            coalesce(p_note, 'ยืนยันจากคำขอเช็คอินของนักศึกษา'))
    on conflict (class_meeting_id, enrollment_id) do update
      set status = excluded.status, note = excluded.note;
  end if;

  return v_row;
end $$;

comment on function decide_checkin(uuid, boolean, attendance_status, text) is
  'ครูยืนยันหรือปฏิเสธคำขอเช็คอิน — จุดเดียวที่คำขอกลายเป็นเวลาเรียนจริง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- นักศึกษาสร้างคำขอของตัวเองได้ (นี่คือทั้งหมดที่เขาทำได้) แต่ตัดสินไม่ได้
-- — เงื่อนไขคือแถวที่เขียนต้องมีสถานะ pending เสมอ
-- ───────────────────────────────────────────────────────────────────
alter table attendance_checkin enable row level security;
alter table attendance_checkin force  row level security;

create policy tenant_isolation on attendance_checkin
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy checkin_scope on attendance_checkin
  as restrictive
  using (
    is_institution_wide_role()
    or section_teacher_person_id(
         (select cm.class_section_id from class_meeting cm
           where cm.id = attendance_checkin.class_meeting_id)) = current_actor_id()
    or enrollment_id in (select actor_enrollment_ids())
  )
  with check (
    is_institution_wide_role()
    or section_teacher_person_id(
         (select cm.class_section_id from class_meeting cm
           where cm.id = attendance_checkin.class_meeting_id)) = current_actor_id()
    -- เจ้าของเขียนได้เฉพาะแถวที่ยังเป็นคำขอ — ตัดสินให้ตัวเองไม่ได้
    or (enrollment_id in (select actor_enrollment_ids()) and status = 'pending')
  );

create policy checkin_no_student_delete on attendance_checkin
  as restrictive for delete
  using (
    is_institution_wide_role()
    or section_teacher_person_id(
         (select cm.class_section_id from class_meeting cm
           where cm.id = attendance_checkin.class_meeting_id)) = current_actor_id()
  );

comment on policy checkin_scope on attendance_checkin is
  'นักศึกษาส่งคำขอของตัวเองได้เฉพาะสถานะ pending — ยืนยันเองไม่ได้ และลบคำขอทิ้งไม่ได้';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on attendance_checkin to app_runtime;
    grant execute on function submit_checkin(uuid, uuid, integer, text) to app_runtime;
    grant execute on function decide_checkin(uuid, boolean, attendance_status, text)
      to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0048_timetable_scan_once.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0048_timetable_scan_once.sql
--
-- ตัวจัดตารางอ่านคาบที่ถูกจองไว้ "ครั้งเดียว" แทนที่จะถามทีละคาบ
--
-- ─── อาการที่พาให้มาแก้ตรงนี้ ───
-- `POST /timetable/terms/:id/auto-schedule` ตอบ 408 (statement_timeout
-- 15 วินาที รหัส 57014) บนเครื่อง CI ส่วน `GET /timetable/suggest`
-- ซึ่งเรียก suggest_timeslots **ครั้งเดียว** ใช้เวลา 7 วินาที
--
-- ─── ทำไมช้าขนาดนั้นทั้งที่ข้อมูลมีไม่กี่สิบแถว ───
-- ต้นทุนไม่ได้อยู่ที่การอ่านข้อมูล แต่อยู่ที่ **การวางแผนคำสั่ง**
-- timeslot_conflicts เป็นคำสั่งเจ็ดท่อน union กัน แตะ section_timeslot ·
-- class_section · course · enrollment · room · timetable_policy ซึ่ง
-- ทุกตารางมีนโยบาย RLS ที่ถูกกางออกเป็นเงื่อนไขซ้อนกันตอนวางแผน
-- แผนที่ได้ยาว ~400 บรรทัด มี SubPlan เกินร้อยชุด — วัดจริงบนเครื่องพัฒนา
-- ได้ planning 12 ms ต่อ execution 1.7 ms คือเวลาหมดไปกับการวางแผนล้วน ๆ
--
-- suggest_timeslots เดิมเรียก timeslot_conflicts **หนึ่งครั้งต่อคาบผู้สมัคร**
-- (8 คาบ × 5 วัน = 40 ครั้ง) และ auto_schedule_term เรียก suggest_timeslots
-- ซ้ำอีกทุกกลุ่มเรียนคูณทุกขนาดบล็อกที่ลองย่อลง — รวมแล้วหลักพันครั้ง
-- ต่อคำขอเดียว
--
-- **สังเกตว่านี่ไม่ใช่ของใหม่** รอบ CI ที่ผ่านครั้งล่าสุดก่อนหน้านี้
-- API-72 ใช้เวลา 14.6 วินาทีจากเพดาน 15 วินาที — ผ่านมาตลอดด้วยเสี้ยววินาที
-- 0046 เพิ่มการตรวจข้อจำกัดของครูเข้าไปอีกชั้นจึงเป็นฟางเส้นสุดท้าย
-- ถ้าแก้แค่ให้ 0046 เบาลง เทสต์จะกลับไปนั่งอยู่ที่ขอบเพดานเหมือนเดิม
-- แล้วแดงอีกเมื่อใดก็ได้ที่ runner ช้ากว่าปกติ จึงแก้ที่รูปแบบการเรียกแทน
--
-- ─── วิธีแก้ ───
-- แยก "คาบไหนถูกจองไปแล้วบ้าง" ออกมาเป็น blocked_periods() ที่คืนผล
-- **ทั้งสัปดาห์ในครั้งเดียว** เป็นรายคาบ แล้วให้ทั้งสองตัวใช้ร่วมกัน
--   · suggest_timeslots เรียกครั้งเดียวแล้ว anti-join กับคาบผู้สมัคร
--   · timeslot_conflicts กรองผลของมันด้วยวันและช่วงคาบที่ถาม
-- กฎการชนจึงยังมีที่อยู่ที่เดียว ไม่ได้คัดลอกไปเขียนซ้ำในตัวเสนอคาบ
-- ซึ่งเป็นสิ่งที่ต้องระวังที่สุดของการแก้แบบนี้ — ตัวเสนอที่รู้กฎไม่ครบ
-- จะเสนอคาบที่วางไม่ได้จริง แล้วตัวจัดอัตโนมัติจะวนเสนอคาบเดิมไม่รู้จบ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- คาบที่ถูกจองไว้แล้วทั้งสัปดาห์ สำหรับกลุ่มเรียนหนึ่ง
--
-- คืนเป็น **รายคาบ** (period ทีละคาบ) ไม่ใช่ช่วง เพราะผู้เรียกทั้งสองฝั่ง
-- ต้องการถามว่า "คาบนี้ว่างไหม" การเทียบช่วงกับช่วงในทุกจุดที่ใช้
-- เปิดโอกาสให้เขียนเงื่อนไขซ้อนทับผิดได้ง่าย (เคยพลาดมาแล้วกับ
-- ta.period_from <= p_period_to and ta.period_to >= p_period_from)
-- ส่วนจำนวนแถวที่เพิ่มขึ้นนั้นไม่มีนัยสำคัญ — คาบต่อวันมีสิบคาบเป็นอย่างมาก
--
-- ครอบคลุมการชนห้าข้อแรกของ timeslot_conflicts ที่เป็น "คาบถูกใช้ไปแล้ว"
-- ส่วนอีกสองข้อ (ห้องผิดประเภท · ผิดนโยบายคาบ) ไม่ขึ้นกับการจองของคนอื่น
-- และคิดได้จากตัวคาบเอง จึงอยู่ที่ผู้เรียกทั้งคู่
-- ───────────────────────────────────────────────────────────────────
create or replace function blocked_periods(
  p_class_section_id uuid,
  p_room_id          uuid default null,
  p_ignore_slot_id   uuid default null
) returns table (
  day_of_week      smallint,
  period           smallint,
  kind             text,
  other_section_id uuid,
  course_code      text,
  course_name      text
) language sql stable as $$
  -- `materialized` ทั้งสองตัวโดยตั้งใจ — ถ้าปล่อยให้ PostgreSQL inline
  -- เข้าไปในแต่ละท่อนของ union ข้างล่าง คำสั่งจะกลับไปกางนโยบาย RLS
  -- ของ class_section กับ course ซ้ำห้ารอบ ซึ่งคือต้นทุนที่มาแก้ตรงนี้
  with me as materialized (
    select cs.id, cs.term_id, cs.teacher_id, cs.curriculum_version_id,
           cs.section_no
      from class_section cs
     where cs.id = p_class_section_id
  ),
  slots as materialized (
    select st.id as slot_id, st.class_section_id, st.room_id,
           st.day_of_week, st.period_from, st.period_to,
           cs2.teacher_id, cs2.curriculum_version_id, cs2.section_no,
           c2.code as course_code, c2.name_th as course_name
      from section_timeslot st
      join class_section cs2 on cs2.id = st.class_section_id
      join course c2         on c2.id  = cs2.course_id
      cross join me
     where cs2.term_id = me.term_id
       and (p_ignore_slot_id is null or st.id <> p_ignore_slot_id)
  ),
  others as (
    select s.* from slots s where s.class_section_id <> p_class_section_id
  ),
  hits as (
    -- 1. ครูคนเดียวสอนสองที่พร้อมกัน
    select o.day_of_week, o.period_from, o.period_to, 'teacher'::text as kind,
           o.class_section_id as other_section_id, o.course_code, o.course_name
      from others o cross join me
     where me.teacher_id is not null and o.teacher_id = me.teacher_id

    union all
    -- 2. ห้องเดียวถูกใช้สองวิชาพร้อมกัน
    select o.day_of_week, o.period_from, o.period_to, 'room',
           o.class_section_id, o.course_code, o.course_name
      from others o
     where p_room_id is not null and o.room_id = p_room_id

    union all
    -- 3. นักศึกษากลุ่มเดียวกันตามแผน — ใช้ได้ตั้งแต่ก่อนมีใครลงทะเบียน
    select o.day_of_week, o.period_from, o.period_to, 'cohort',
           o.class_section_id, o.course_code, o.course_name
      from others o cross join me
     where me.curriculum_version_id is not null
       and o.curriculum_version_id = me.curriculum_version_id
       and o.section_no is not distinct from me.section_no

    union all
    -- 4. นักศึกษาที่ลงทะเบียนแล้วชนจริง — ใช้ตรวจย้อนหลังหลังเปิดเทอม
    select o.day_of_week, o.period_from, o.period_to, 'enrolled',
           o.class_section_id, o.course_code, o.course_name
      from others o
     where exists (
       select 1 from enrollment e1
         join enrollment e2 on e2.student_id = e1.student_id
        where e1.class_section_id = p_class_section_id
          and e2.class_section_id = o.class_section_id
          and e1.status = 'enrolled' and e2.status = 'enrolled')

    union all
    -- 5. กลุ่มเรียนนี้เองมีคาบอยู่แล้ว
    --
    --    ข้อนี้ดูซ้ำซ้อนกับ exclusion constraint ที่กันไว้อยู่แล้ว แต่จำเป็น
    --    เพราะตัวเสนอคาบต้องรู้ล่วงหน้าว่าวางไม่ได้ ไม่ใช่ไปรู้ตอน insert
    --    แล้วล้ม — ตัวจัดอัตโนมัติที่วางหลายบล็อกให้วิชาเดียวกันจะเสนอ
    --    คาบเดิมซ้ำไม่รู้จบถ้าไม่มีข้อนี้
    select s.day_of_week, s.period_from, s.period_to, 'self',
           null::uuid, null::text, null::text
      from slots s
     where s.class_section_id = p_class_section_id
  )
  select h.day_of_week, p::smallint, h.kind, h.other_section_id,
         h.course_code, h.course_name
    -- ต้อง cast เป็น integer เอง — generate_series(smallint, smallint) กำกวม
    -- (PostgreSQL เลือกไม่ได้ระหว่างตัวที่รับ int, bigint และ numeric)
    from hits h, generate_series(h.period_from::integer, h.period_to::integer) p;
$$;

comment on function blocked_periods(uuid, uuid, uuid) is
  'คาบที่ถูกจองไว้แล้วทั้งสัปดาห์ของกลุ่มเรียนนี้ — อ่านครั้งเดียวแล้วใช้ทั้งตัวตรวจและตัวเสนอคาบ';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจการชนของคาบที่เสนอ (เหมือนเดิมทุกอย่างจากมุมผู้เรียก)
--
-- ยังคืน "รายการปัญหา" ไม่ใช่ true/false และข้อความยังเป็นภาษาไทยชุดเดิม
-- เปลี่ยนแค่ที่มาของข้อ 1–5 ให้มาจาก blocked_periods()
-- ───────────────────────────────────────────────────────────────────
create or replace function timeslot_conflicts(
  p_class_section_id uuid,
  p_day_of_week      smallint,
  p_period_from      smallint,
  p_period_to        smallint,
  p_room_id          uuid default null,
  p_ignore_slot_id   uuid default null
) returns table (
  kind             text,
  message_th       text,
  other_section_id uuid
) language sql stable as $$
  with me as materialized (
    select cs.section_no, cs.institution_id, c.needs_workshop
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.id = p_class_section_id
  ),
  policy as (
    select tp.* from timetable_policy tp
     join me on me.institution_id = tp.institution_id
  ),
  -- คาบเดียวกันอาจถูกจองทับหลายคาบติดกัน ต้องยุบเป็นหนึ่งข้อความต่อหนึ่ง
  -- ปัญหา มิฉะนั้นหน้าจอจะขึ้น "ครูติดสอน..." ซ้ำเท่าจำนวนคาบที่ทับกัน
  hit as (
    select distinct b.kind, b.other_section_id, b.course_code, b.course_name
      from blocked_periods(p_class_section_id, p_room_id, p_ignore_slot_id) b
     where b.day_of_week = p_day_of_week
       and b.period between p_period_from and p_period_to
  )
  select h.kind,
         case h.kind
           when 'teacher' then
             'ครูผู้สอนติดสอน ' || h.course_code || ' ' || h.course_name
               || ' ในคาบเดียวกัน'
           when 'room' then
             'ห้องนี้ถูกใช้โดย ' || h.course_code || ' ' || h.course_name
               || ' ในคาบเดียวกัน'
           when 'cohort' then
             'ห้องเรียน ' || coalesce(me.section_no, '-') || ' ติดเรียน '
               || h.course_code || ' ' || h.course_name || ' ในคาบเดียวกัน'
           when 'enrolled' then
             'มีนักศึกษาที่ลงทะเบียนทั้งวิชานี้และ ' || h.course_code || ' อยู่แล้ว'
           else 'ห้องเรียนรายวิชานี้มีคาบเรียนอยู่แล้วในช่วงเวลานี้'
         end,
         h.other_section_id
    from hit h cross join me

  union all
  -- 6. วิชาที่ต้องใช้โรงฝึกงานจัดลงห้องบรรยายไม่ได้
  select 'room_kind',
         'วิชานี้ต้องใช้โรงฝึกงาน แต่ห้องที่เลือกเป็น ' || r.name_th,
         null::uuid
    from me join room r on r.id = p_room_id
   where me.needs_workshop and r.kind not in ('workshop', 'lab', 'computer')

  union all
  -- 7. ทับคาบพักกลางวันหรือเกินจำนวนคาบต่อวัน
  select 'policy',
         case when p.lunch_period is not null
                   and p.lunch_period between p_period_from and p_period_to
              then 'คาบนี้ทับคาบพักกลางวัน (คาบ ' || p.lunch_period || ')'
              when p_period_to > p.periods_per_day
              then 'เกินจำนวนคาบต่อวันที่กำหนดไว้ (' || p.periods_per_day || ' คาบ)'
              else 'เกินจำนวนวันเรียนต่อสัปดาห์ที่กำหนดไว้ (' || p.days_per_week || ' วัน)'
         end,
         null::uuid
    from policy p
   where (p.lunch_period is not null
          and p.lunch_period between p_period_from and p_period_to)
      or p_period_to > p.periods_per_day
      or p_day_of_week > p.days_per_week;
$$;

comment on function timeslot_conflicts(uuid, smallint, smallint, smallint, uuid, uuid) is
  'ตรวจว่าคาบที่เสนอชนกับอะไรบ้าง — คืนรายการปัญหาทั้งหมด ไม่ใช่หยุดที่ข้อแรก';

-- ───────────────────────────────────────────────────────────────────
-- คาบว่างที่วางได้ — อ่านของที่จองไว้ครั้งเดียว
--
-- ผลลัพธ์ต้องเหมือน 0046 ทุกประการ เปลี่ยนแค่จำนวนครั้งที่ถามฐานข้อมูล
-- ───────────────────────────────────────────────────────────────────
create or replace function suggest_timeslots(
  p_class_section_id uuid,
  p_periods          smallint default 2,
  p_room_id          uuid default null,
  p_limit            integer default 10,
  p_term_id          uuid default null
) returns table (
  day_of_week smallint,
  period_from smallint,
  period_to   smallint,
  avoids      boolean,
  note        text
) language sql stable as $$
  with me as materialized (
    select cs.institution_id, cs.teacher_id, c.needs_workshop
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.id = p_class_section_id
  ),
  policy as materialized (
    select coalesce(tp.periods_per_day, 10) as periods_per_day,
           coalesce(tp.days_per_week, 5)    as days_per_week,
           tp.lunch_period
      from me left join timetable_policy tp on tp.institution_id = me.institution_id
  ),
  -- ห้องผิดประเภทแปลว่าวางไม่ได้ทุกคาบเท่ากันหมด ตรวจครั้งเดียวจบ
  -- ไม่ต้องถามซ้ำทุกคาบเหมือนตอนที่ยังเรียก timeslot_conflicts รายคาบ
  room_bad as materialized (
    select 1 from me join room r on r.id = p_room_id
     where me.needs_workshop and r.kind not in ('workshop', 'lab', 'computer')
  ),
  taken as materialized (
    select b.day_of_week, b.period
      from blocked_periods(p_class_section_id, p_room_id) b
  ),
  avoidance as materialized (
    select ta.day_of_week, ta.period_from, ta.period_to, ta.kind, ta.reason
      from me
      join teacher_availability ta on ta.staff_id = me.teacher_id
     where ta.term_id is null or ta.term_id = coalesce(p_term_id, ta.term_id)
  ),
  candidates as (
    select d::smallint as day_of_week,
           s::smallint as period_from,
           (s + p_periods - 1)::smallint as period_to
      from policy p,
           generate_series(1, p.days_per_week) d,
           generate_series(1, p.periods_per_day) s
     where s + p_periods - 1 <= p.periods_per_day
       -- ข้อ 7 ของ timeslot_conflicts: ห้ามคร่อมคาบพักกลางวัน
       -- (เพดานคาบต่อวันและวันต่อสัปดาห์ถูกบังคับด้วยตัว generate_series แล้ว)
       and (p.lunch_period is null
            or p.lunch_period not between s and s + p_periods - 1)
       and not exists (select 1 from room_bad)
  ),
  usable as (
    select c.day_of_week, c.period_from, c.period_to,
           b.kind as block_kind, b.reason as block_reason
      from candidates c
      left join lateral (
        select k.kind, k.reason
          from avoidance k
         where k.day_of_week = c.day_of_week
           -- ช่วงคาบซ้อนกัน (ไม่ใช่แค่เริ่มตรงกัน)
           and k.period_from <= c.period_to
           and k.period_to   >= c.period_from
         -- 'unavailable' มาก่อน 'prefer_not' ตามลำดับที่ประกาศไว้ใน enum
         order by k.kind
         limit 1
      ) b on true
     where not exists (
       select 1 from taken t
        where t.day_of_week = c.day_of_week
          and t.period between c.period_from and c.period_to)
  )
  -- ต้อง coalesce เป็น false ทั้งในคอลัมน์และใน order by
  --
  -- คาบที่ไม่มีข้อจำกัดจะได้ block_kind เป็น null ทำให้ (null = 'prefer_not')
  -- เป็น null ไม่ใช่ false และ PostgreSQL เรียง null ไว้ **ท้ายสุด** ในลำดับ
  -- ขึ้น — ผลคือคาบที่ครูขอเลี่ยง (true) จะถูกเสนอมาก่อนคาบที่ไม่ติดอะไรเลย
  -- ซึ่งกลับด้านกับสิ่งที่ตั้งใจทั้งหมด
  select u.day_of_week, u.period_from, u.period_to,
         coalesce(u.block_kind = 'prefer_not', false) as avoids,
         case when u.block_kind = 'prefer_not'
              then coalesce(u.block_reason, 'ครูขอเลี่ยงคาบนี้') end as note
    from usable u
   -- ห้ามวางถูกตัดออกทั้งหมด ส่วนที่ขอเลี่ยงยังเสนอได้แต่ไปอยู่ท้ายรายการ
   where u.block_kind is distinct from 'unavailable'
   order by coalesce(u.block_kind = 'prefer_not', false),
            u.day_of_week, u.period_from
   limit p_limit;
$$;

comment on function suggest_timeslots(uuid, smallint, uuid, integer, uuid) is
  'คาบว่างที่วางได้จริง — ตัดช่วงที่ครูสอนไม่ได้ออก และเรียงคาบที่ครูขอเลี่ยงไว้ท้ายสุด';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant execute on function blocked_periods(uuid, uuid, uuid) to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0049_write_scope_teacher_and_hr.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0049_write_scope_teacher_and_hr.sql
--
-- ปิดช่องเขียนของ **ครู** และของ **เจ้าของระเบียนบุคลากร**
--
-- ─── ยิงจริงในบริบทครูแล้วทำได้ทั้งห้าข้อนี้ ───
--   1. `update grade_submission set locked_at = null, stage = 'draft'`
--      ปลดล็อกรอบส่งเกรดของตัวเอง แล้วกลับไปแก้เกรดตรง ๆ ได้เลย
--      **ข้อนี้ล้มหลัก 3ก ทั้งข้อ** — เหตุผลเดียวที่คำร้องแก้เกรดต้องมี
--      ผู้อนุมัติสองคน คือเพราะรอบที่ล็อกแล้วแก้ไม่ได้ ถ้าปลดล็อกเองได้
--      ไม่มีใครต้องยื่นคำร้องอีกเลย
--   2. `delete from grade_submission_event` ลบประวัติว่าใครเลื่อนขั้นเมื่อไร
--      (ยืนยันแล้วว่าลบได้จริง 1 แถว) — หลักฐานของข้อ 1 อยู่ตรงนี้
--   3. `update class_section` แก้รายละเอียดกลุ่มเรียนของตัวเอง
--   4. `insert/update staff_record` เพิ่มวุฒิและชั่วโมงอบรมปลอมให้ตัวเอง
--      (ระเบียน ทช.1 ใช้ประกอบการต่อใบอนุญาตและการเลื่อนวิทยฐานะ)
--   5. `insert staff_child` ผูกตัวเองเป็นผู้ปกครองของนักศึกษาคนใดก็ได้
--      ที่ยังไม่ถูกผูก (มีผลต่อสิทธิ์ลดหย่อนค่าเล่าเรียน)
--
-- ─── สิ่งที่ตรวจแล้วพบว่า "กันไว้แล้ว" ไม่ต้องแตะ ───
-- ทดสอบสามข้อนี้แล้วถูกปฏิเสธด้วย trigger ที่มีอยู่เดิม ไม่ใช่ด้วยความบังเอิญ
--   · ครูอนุมัติคำร้องแก้เกรดของตัวเองไม่ได้ ('ผู้ยื่นคำร้องเป็นผู้อนุมัติ
--     คำร้องของตัวเองไม่ได้') และตั้งสถานะเป็นอนุมัติโดยไม่มีผู้อนุมัติครบ
--     สองคนไม่ได้ — ลองทั้งแบบคำสั่งเดียวและแบบแยกทีละคำสั่งแล้ว
--   · ครูอนุมัติใบลาของตัวเองไม่ได้ ('ผู้ยื่นใบลาอนุมัติใบลาของตัวเองไม่ได้')
--   · ครูถอดตัวเองออกจากกลุ่มเรียนไม่ได้ (`teacher_id = null` ทำให้แถวใหม่
--     ตกนโยบายเดิม เพราะ `using` ถูกใช้เป็น `with check` — บังเอิญกันไว้ให้
--     แต่กันได้แค่คอลัมน์เดียว คอลัมน์อื่นยังแก้ได้ตามข้อ 3)
--
-- ─── ทำไมสองตารางเกรดใช้ trigger ไม่ใช่นโยบายอย่างเดียว ───
-- `submit_section_grades()` กับ `advance_grade_submission()` **ไม่ใช่**
-- security definer จึงทำงานในบทบาทของผู้เรียก — ครูที่ส่งเกรดต้องเขียน
-- `grade_submission` ได้จริง การปิดด้วย restrictive policy ทั้งตารางจะทำให้
-- ครูส่งเกรดไม่ได้เลย ซึ่งเป็นความผิดพลาดแบบเดียวกับที่ 0045 เคยทำกับ
-- `practicum_log` (ปิดจนนักศึกษาบันทึกชั่วโมงของตัวเองไม่ได้ = A-06 พังทั้งจอ)
--
-- สิ่งที่ต้องห้ามจึงไม่ใช่ "ครูเขียนตารางนี้" แต่คือ "การย้อนสิ่งที่ล็อกแล้ว"
-- ซึ่งเป็นเงื่อนไขระดับค่าในแถว ไม่ใช่ระดับตาราง — RLS ทำไม่ได้ trigger ทำได้
-- และ trigger บังคับกับ**ทุกทาง**ที่เข้าถึงข้อมูล ไม่ใช่แค่ทางที่ผ่านฟังก์ชัน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- 1. ล็อกแล้วคือล็อก — บังคับที่แถว ไม่ใช่ที่ฟังก์ชัน
--
-- `advance_grade_submission()` ปฏิเสธการเลื่อนขั้นของรอบที่ล็อกแล้วอยู่ก่อน
-- แต่การ `update` ตรง ๆ ไม่ผ่านฟังก์ชันจึงไม่เจอเงื่อนไขนั้นเลย
-- trigger ย้ายกฎเดียวกันมาไว้ที่แถว ทางไหนก็หนีไม่พ้น
-- ───────────────────────────────────────────────────────────────────
create or replace function grade_submission_lock_guard()
returns trigger language plpgsql as $$
begin
  -- ต้องปล่อยผ่านให้ superuser และให้บริบทที่ไม่มีผู้ใช้
  --
  -- trigger ยิงกับ superuser ด้วย ต่างจาก RLS ที่ superuser ข้ามอยู่แล้ว
  -- งานย้ายข้อมูล การกู้คืน และการเตรียมข้อมูลของเทสต์จึงติดกับดักของ
  -- ตัวเองทันทีถ้าไม่ปล่อย (บทเรียนเดียวกับ user_credential_owner_guard()
  -- ใน 0042 — ครั้งนั้นดูแค่ `current_app_role() = 'none'` ซึ่ง**ไม่พอ**
  -- เพราะสคริปต์ที่รันเป็น postgres มักตั้ง `app.role` ไว้ด้วยเพื่อทดสอบ
  -- มุมมองของบทบาทหนึ่ง แล้วค่อยกลับมาเตรียมข้อมูลต่อ)
  --
  -- ปล่อยให้ superuser ไม่ได้ลดความปลอดภัยลงเลย เพราะคนที่เป็น superuser
  -- ถอด trigger ทิ้งได้อยู่แล้ว และแอปไม่ยอมบูตถ้าต่อ DB ด้วย superuser
  -- (หลัก 6) ส่วนบริบทที่ไม่มี `app.role` ก็ไม่มี `app.institution_id`
  -- นโยบาย RLS ชั้นแรกจึงปฏิเสธทุกแถวอยู่แล้ว
  if current_setting('is_superuser', true) = 'on' or current_app_role() = 'none' then
    return new;
  end if;

  if old.locked_at is not null and new.locked_at is distinct from old.locked_at then
    raise exception 'รอบส่งเกรดที่ล็อกแล้วปลดล็อกไม่ได้ '
      'การแก้เกรดหลังล็อกต้องยื่นคำร้องแก้เกรดที่มีผู้อนุมัติสองคน';
  end if;

  if old.stage = 'locked' and new.stage is distinct from old.stage then
    raise exception 'รอบส่งเกรดที่ล็อกแล้วย้อนขั้นไม่ได้ (ขอย้อนไป %) '
      'การแก้เกรดหลังล็อกต้องยื่นคำร้องแก้เกรดที่มีผู้อนุมัติสองคน', new.stage;
  end if;

  return new;
end $$;

comment on function grade_submission_lock_guard() is
  'ล็อกแล้วคือล็อก — ห้ามล้าง locked_at และห้ามย้อนขั้นจาก locked ไม่ว่าจะเข้าทางไหน';

create trigger grade_submission_lock_guard
  before update on grade_submission
  for each row execute function grade_submission_lock_guard();

-- ลบทั้งแถวได้ผลเท่ากับปลดล็อก จึงต้องปิดด้วยกัน
-- (งานทะเบียนยังลบรอบที่ยังไม่ล็อกทิ้งได้ เช่นเปิดผิดกลุ่มเรียน)
create policy grade_submission_staff_delete on grade_submission
  as restrictive for delete
  using (is_institution_wide_role() and locked_at is null);

-- ───────────────────────────────────────────────────────────────────
-- 2. ประวัติการเลื่อนขั้นเป็นบันทึกที่เพิ่มได้อย่างเดียว
--
-- หลักการเดียวกับ access_log และ grade_ledger — ถ้าคนที่เลื่อนขั้นลบหรือ
-- แก้ประวัติของตัวเองได้ ประวัตินั้นไม่ใช่หลักฐาน มันเป็นแค่ความเห็นของ
-- คนล่าสุดที่แตะมัน
--
-- ห้ามทุกบทบาทรวมถึงผู้ดูแล ไม่ใช่ห้ามเฉพาะครู — ผู้ดูแลที่ลบประวัติได้
-- คือจุดเดียวที่ทำให้บันทึกทั้งชุดใช้เป็นหลักฐานไม่ได้
-- ───────────────────────────────────────────────────────────────────
create policy grade_submission_event_no_update on grade_submission_event
  as restrictive for update using (false);

create policy grade_submission_event_no_delete on grade_submission_event
  as restrictive for delete using (false);

-- ───────────────────────────────────────────────────────────────────
-- 3. กลุ่มเรียน · ระเบียนบุคลากร · บุตรบุคลากร — เขียนได้เฉพาะระดับวิทยาลัย
--
-- ตรวจทุกเส้นทางที่เขียนสามตารางนี้แล้ว
--   · `class_section` ไม่มีเส้นทาง API ไหนเขียนเลยสักเส้น ตัวที่เขียนคือ
--     `generate_class_meetings()` ซึ่งเรียกจากงานทะเบียนก่อนเปิดภาคเรียน
--   · `staff_record` / `staff_child` เขียนที่ `POST /hr/staff/:id/records`
--     และ `/children` ซึ่ง `HrController` ตั้ง `@Roles('registrar',
--     'director', 'admin')` ไว้อยู่แล้ว — ครูเรียกไม่ได้ผ่าน API มาตั้งแต่ต้น
--     ช่องที่เปิดอยู่คือช่องที่ **ข้าม API** เท่านั้น ซึ่งเป็นรูปแบบเดียวกับ
--     ข้อ 10 และ 11 ในรายการ "เคยพังแบบเงียบ ๆ"
--
-- เจ้าของยังอ่านของตัวเองได้ครบเหมือนเดิม — restrictive คุมเฉพาะการเขียน
-- ───────────────────────────────────────────────────────────────────
do $$
declare
  t text;
  tables constant text[] := array['class_section', 'staff_record', 'staff_child'];
begin
  foreach t in array tables loop
    execute format($f$
      create policy %1$I_staff_insert on %1$I
        as restrictive for insert
        with check (is_institution_wide_role())
    $f$, t);

    execute format($f$
      create policy %1$I_staff_update on %1$I
        as restrictive for update
        using (is_institution_wide_role())
        with check (is_institution_wide_role())
    $f$, t);

    execute format($f$
      create policy %1$I_staff_delete on %1$I
        as restrictive for delete
        using (is_institution_wide_role())
    $f$, t);
  end loop;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0050_request_rate_shared.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0050_request_rate_shared.sql
--
-- ตัวนับคำขอที่ใช้ร่วมกันทุก instance
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- 0021 ย้ายการนับของ `/auth/login` ลงฐานข้อมูลไปแล้ว เพราะโควตาที่คูณตาม
-- จำนวน instance แปลว่าผู้โจมตีเดารหัสผ่านได้มากกว่าที่ตั้งใจ
--
-- แต่ตัวจำกัดคำขอ **ทั่วไป** ยังนับในหน่วยความจำของโปรเซสอยู่ ซึ่งเป็น
-- ปัญหาเดียวกันทุกประการ เพียงแต่เห็นช้ากว่า — รัน 3 instance แล้วเพดาน
-- จริงกลายเป็นสามเท่าโดยไม่มีอะไรฟ้อง และรีสตาร์ททีเดียวโควตาคืนใหม่หมด
--
-- เรื่องนี้สำคัญกว่าที่ตัวเลขบอก เพราะเส้นทางที่ตั้งเพดานแน่นไว้โดยตั้งใจ
-- คือเส้นทางที่อ่อนไหวที่สุด — `POST /provisioning/institutions` ตั้งไว้
-- 3 ครั้งต่อนาที (ทุกคำขอที่ผ่านสร้างวิทยาลัยใหม่หนึ่งแห่ง) ·
-- `/auth/forgot-password` · การเข้าสู่ระบบของผู้ให้บริการ
-- เพดานพวกนี้ถูกเลือกมาจากผลที่ตามมา ไม่ใช่จากความสะดวก การคูณสามจึงไม่ใช่
-- "หลวมนิดหน่อย" แต่คือเพดานคนละตัวกับที่ตัดสินใจไว้
--
-- ─── ทำไมไม่เก็บทุกคำขอเป็นหนึ่งแถวเหมือน login_attempt ───
-- `login_attempt` เก็บรายครั้งได้เพราะการเข้าสู่ระบบมีไม่กี่ครั้งต่อคน และ
-- ต้องเก็บอยู่แล้วตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26 แต่ตัวนี้นับ**ทุกคำขอ
-- ของทุกเส้นทาง** การเขียนหนึ่งแถวต่อคำขอคือการเพิ่มภาระเขียนเท่าตัวของ
-- ทั้งระบบเพื่อทำสิ่งที่เป็นแค่ตัวเลข — ตัวจำกัดที่ทำให้ระบบล้มเสียเอง
-- คือตัวจำกัดที่ใช้ไม่ได้
--
-- จึงเก็บเป็น **ตัวนับต่อหน้าต่างเวลา** หนึ่งแถวต่อ (ถัง, หน้าต่าง)
-- แล้วประมาณค่าแบบหน้าต่างเลื่อนจากสองหน้าต่างที่ติดกัน (วิธีเดียวกับที่
-- CDN ใช้) — แม่นพอสำหรับการจำกัดคำขอ และเขียนแค่ครั้งเดียวต่อคำขอ
--
-- ─── ทำไมคีย์เป็นค่าแฮช ไม่ใช่ไอพีตรง ๆ ───
-- ไอพีเป็นข้อมูลส่วนบุคคลตาม PDPA หลักเดียวกับ `login_attempt.ip_hash`
-- ที่ใช้ IP_HASH_SECRET อยู่แล้ว — ยังนับได้เหมือนเดิมแต่ย้อนกลับไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;

create table request_rate (
  bucket_key   bytea       not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket_key, window_start)
);

comment on table request_rate is
  'ตัวนับคำขอต่อหน้าต่างเวลา ใช้ร่วมกันทุก instance — คีย์เป็นค่าแฮชของไอพีกับเส้นทาง';
comment on column request_rate.bucket_key is
  'sha256(IP_HASH_SECRET : ไอพี | เมท็อด | เส้นทาง) — ย้อนกลับเป็นไอพีจริงไม่ได้';

-- ล้างของเก่าด้วยดัชนีนี้ ไม่ใช่สแกนทั้งตาราง
create index request_rate_window_idx on request_rate (window_start);

-- ตารางนี้ไม่มี institution_id โดยตั้งใจ — ตัวจำกัดคำขอทำงาน**ก่อน**รู้ว่า
-- ผู้เรียกเป็นใครและอยู่วิทยาลัยไหน (นั่นคือหน้าที่ของมัน) การผูกกับวิทยาลัย
-- จะทำให้กันคำขอที่ยังไม่ผ่านการยืนยันตัวตนไม่ได้เลย ซึ่งคือคำขอที่ต้องกัน
alter table request_rate enable row level security;
alter table request_rate force row level security;

-- ─── ทำไมมีนโยบายอ่านอย่างเดียว ไม่มีนโยบายเขียนเลย ───
-- ไม่มีนโยบาย insert/update/delete แปลว่าไม่มีใครเขียนตารางนี้ได้ผ่าน SQL
-- ตรง ๆ เลยสักบทบาท เหลือทางเดียวคือ `request_rate_hit()` ซึ่งเป็น
-- security definer
--
-- **ห้ามพึ่ง GRANT เพียงอย่างเดียวในเรื่องนี้** — `db/deploy/roles.sql`
-- ให้สิทธิ์ `insert, update, delete on all tables` กับ app_runtime แบบเหมารวม
-- ตารางใหม่ทุกตารางจึงได้สิทธิ์เขียนมาโดยอัตโนมัติ การ "ไม่ GRANT"
-- ในไฟล์นี้จึงไม่มีผลอะไรเลย RLS คือชั้นที่กันจริง (TEST 225 ยิงทั้ง
-- insert · update · delete เพื่อยืนยันข้อนี้ ไม่ใช่เชื่อตามที่เขียนไว้)
--
-- ส่วนสิทธิ์อ่านเปิดให้ผู้ดูแลไว้ดูว่าใครถูกจำกัดอยู่ตอนระบบมีปัญหา
create policy request_rate_admin_read on request_rate
  for select using (current_app_role() in ('admin', 'director'));

-- ───────────────────────────────────────────────────────────────────
-- นับหนึ่งครั้งแล้วบอกว่าผ่านหรือไม่
--
-- ─── ทำไมไม่ raise เมื่อเกินเพดาน ───
-- ฟังก์ชันที่นับจำนวนครั้งห้าม raise เด็ดขาด เพราะ rollback จะล้างตัวนับ
-- ที่เพิ่งเขียนทิ้งไปด้วย แล้วผู้โจมตีจะยิงได้ไม่จำกัดโดยที่ระบบยังตอบ
-- ปฏิเสธถูกต้องทุกครั้ง (เคยเจอกับ MFA มาแล้ว) ชั้น API เป็นคนโยน
-- และต้องโยน **นอก** ทรานแซกชันด้วย
--
-- ─── ทำไม security definer ───
-- ตัวจำกัดคำขอทำงานก่อน AuthGuard จึงไม่มี app.role และ app.institution_id
-- ให้ RLS ใช้เลยสักตัว การเรียกแบบไม่มีบริบทจึงต้องข้ามผ่านนโยบาย
-- นี่ไม่ใช่การใช้ security definer เพื่อเลี่ยงนโยบายของตาราง (ซึ่งห้ามไว้)
-- แต่เป็นตารางที่อยู่นอกขอบเขตวิทยาลัยตั้งแต่ต้น เหมือน login_role_for()
-- ที่ต้อง definer เพราะบริบทตอนล็อกอินยังไม่มีผู้ใช้
-- ───────────────────────────────────────────────────────────────────
create or replace function request_rate_hit(
  p_bucket_key  bytea,
  p_limit       integer,
  p_window_secs integer
) returns table (
  allowed          boolean,
  remaining        integer,
  retry_after_secs integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now     timestamptz := clock_timestamp();
  v_win     interval;
  v_start   timestamptz;
  v_prev    integer;
  v_cur     integer;
  v_elapsed numeric;
  v_est     numeric;
begin
  if p_window_secs is null or p_window_secs < 1 then
    p_window_secs := 60;
  end if;
  v_win := make_interval(secs => p_window_secs);

  -- ตัดเวลาให้ลงหน้าต่างเดียวกันทุก instance — ถ้าแต่ละเครื่องเริ่มนับ
  -- หน้าต่างของตัวเองตามเวลาที่คำขอแรกมาถึง ตัวนับจะไม่มีวันตรงกัน
  v_start := to_timestamp(
    floor(extract(epoch from v_now) / p_window_secs) * p_window_secs);

  select r.hits into v_prev
    from request_rate r
   where r.bucket_key = p_bucket_key
     and r.window_start = v_start - v_win;

  insert into request_rate as r (bucket_key, window_start, hits)
  values (p_bucket_key, v_start, 1)
  on conflict (bucket_key, window_start)
    do update set hits = r.hits + 1
  returning r.hits into v_cur;

  -- ประมาณแบบหน้าต่างเลื่อน — ยิ่งเข้าใกล้ปลายหน้าต่าง น้ำหนักของหน้าต่าง
  -- ก่อนหน้ายิ่งน้อยลง ถ้าใช้หน้าต่างตายตัวเฉย ๆ ผู้เรียกจะยิงได้สองเท่า
  -- ของเพดานตรงรอยต่อ (เต็มโควตาท้ายหน้าต่างหนึ่ง แล้วเต็มอีกรอบทันที
  -- ที่ข้ามไปหน้าต่างถัดไป)
  v_elapsed := extract(epoch from v_now - v_start) / p_window_secs;
  v_est     := coalesce(v_prev, 0) * (1 - v_elapsed) + v_cur;

  allowed          := v_est <= p_limit;
  remaining        := greatest(p_limit - ceil(v_est)::integer, 0);
  retry_after_secs := case
                        when v_est <= p_limit then 0
                        else greatest(
                               ceil(extract(epoch from
                                 (v_start + v_win) - v_now))::integer, 1)
                      end;

  -- เก็บกวาดแบบสุ่ม ~1 ใน 1000 คำขอ
  --
  -- ทำในฟังก์ชันแทนที่จะเป็นงานประจำวัน เพราะตารางนี้โตเร็วกว่าตารางอื่น
  -- หลายเท่า (หนึ่งแถวต่อไอพีต่อเส้นทางต่อหน้าต่าง) การรอถึงเที่ยงคืน
  -- แปลว่ามีช่วงที่ตารางใหญ่เกินจำเป็นทั้งวัน ส่วนการล้างทุกคำขอก็เปลือง
  -- เปล่า ๆ เพราะแถวเดียวกันถูกล้างซ้ำไม่ได้อยู่แล้ว
  if random() < 0.001 then
    delete from request_rate r2
     where r2.window_start < v_now - (v_win * 3);
  end if;

  return next;
end $$;

comment on function request_rate_hit(bytea, integer, integer) is
  'นับคำขอหนึ่งครั้งแล้วคืนสถานะ — ไม่ raise เพราะ rollback จะล้างตัวนับทิ้ง ชั้น API เป็นคนโยนเอง';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select on request_rate to app_runtime;
    grant execute on function request_rate_hit(bytea, integer, integer) to app_runtime;
  end if;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0051_graduation_scan_once.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0051_graduation_scan_once.sql
--
-- ตรวจจบอ่านหน่วยกิตของนักศึกษาครั้งเดียว แทนที่จะอ่านซ้ำทุกกฎ
--
-- ─── ตัวเลขที่พาให้มาแก้ตรงนี้ ───
-- ทดสอบโหลดแล้ว `GET /students/:id/graduation` เป็นเส้นทางที่ช้าที่สุด
-- ของนักศึกษาอย่างชัดเจน — 62.8 ms ต่อคำขอ และตันที่ 85 คำขอต่อวินาที
-- ขณะที่การอ่านข้อมูลนักศึกษาธรรมดาทำได้ 1,891 คำขอต่อวินาที
-- ช่วงประกาศผลคือช่วงที่ทุกคนกดหน้านี้พร้อมกัน จึงเป็นภาระสูงสุดของทั้งปี
--
-- ─── ทำไมช้า ───
-- `evaluate_graduation()` วนทุกกฎใน `graduation_rule` แล้วประเมิน
-- `cross join lateral` ทีละกฎ กฎสามชนิดอ่าน `v_student_course_credit`
-- คนละครั้ง และกฎหมวดหน่วยกิตอ่าน `v_student_credits_by_category`
-- ซ้ำทุกหมวด — วัดแยกแล้ว view ตัวแรกใช้ execution 5 ms ต่อครั้ง
-- คูณกับกฎ 10 ข้อได้ ~50 ms ซึ่งตรงกับ 63 ms ที่วัดผ่าน HTTP
--
-- ─── ทำไมยังไม่ใส่แคช ───
-- การใส่แคชทับงานที่ซ้ำสิบรอบคือการจ่ายค่าความซับซ้อน (ล้างแคชเมื่อไร
-- ใครล้าง ข้อมูลค้างนานแค่ไหน) เพื่อซ่อนปัญหาที่แก้ได้ตรง ๆ และแคชผลตรวจจบ
-- อันตรายเป็นพิเศษ เพราะผลที่ค้างหนึ่งวันแปลว่านักศึกษาเห็นว่าตัวเอง
-- "ยังไม่ครบ" หลังจากที่ครูเพิ่งบันทึกให้แล้ว หรือแย่กว่านั้นคือเห็นว่าครบ
-- ทั้งที่ยังไม่ครบ
--
-- ─── ทำไมไม่รวบทุกกฎเป็นตัวเลขชุดเดียวไปเลย ───
-- ที่ดูเหมือนสะอาดกว่าคือคำนวณทุกค่าล่วงหน้าใน CTE เดียวแล้วให้แต่ละกฎ
-- หยิบไปใช้ แต่ `case` ประเมินเฉพาะแขนงที่ตรง หลักสูตรที่มีแค่สองกฎจึงจ่าย
-- แค่สองครั้ง การรวบไว้ก่อนจะบังคับให้จ่ายครบทุกชนิดเสมอ — เร็วขึ้นสำหรับ
-- หลักสูตรที่กฎครบ แต่ช้าลงสำหรับหลักสูตรที่กฎน้อย
--
-- จึงเก็บโครงเดิมไว้ทั้งหมด เปลี่ยนแค่**ที่มาของข้อมูล** ให้ชี้ไปที่ CTE
-- ที่อ่านมาแล้วครั้งเดียว ผลลัพธ์เท่าเดิมทุกแถวทุกค่า (TEST 226 เทียบกับ
-- ตัวเดิมทีละแถวเพื่อยืนยันข้อนี้ ไม่ใช่เชื่อตามที่เขียนไว้)
-- ═══════════════════════════════════════════════════════════════════
begin;

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
language plpgsql stable
/*
 * ─── ทำไมต้องตรึงแผนไว้ ───
 * คำสั่งใหญ่ก้อนเดียวนี้ใช้เวลา **วางแผน 85 ms ต่อ execution 19 ms**
 * (นโยบาย RLS ของทุกตารางถูกกางออกเป็น SubPlan เกินสามสิบชุด) ตราบใดที่
 * PostgreSQL ยังเลือก custom plan มันจะวางแผนใหม่ทุกครั้งที่เรียก แล้ว
 * ค่าวางแผนอย่างเดียวก็กินเวลามากกว่างานจริงสี่เท่า
 *
 * และการตัดสินใจว่าจะใช้ custom หรือ generic plan ขึ้นกับสถิติของข้อมูล
 * จึงต่างกันได้ระหว่างฐานข้อมูลสองชุดที่มีสคีมาเดียวกัน — วัดจริงแล้ว
 * ฐานหนึ่งเลือก generic เอง (เร็วขึ้น 7 เท่าทันที) อีกฐานเลือก custom
 * แล้วการแก้ทั้งหมดนี้กลายเป็น **ช้าลง 20%** ทั้งที่โค้ดชุดเดียวกัน
 * นี่คือความต่างที่มองไม่เห็นเลยถ้าวัดฐานเดียว
 *
 * `force_generic_plan` ปลอดภัยตรงนี้เพราะพารามิเตอร์เดียวคือรหัสนักศึกษา
 * ซึ่งไม่มีนักศึกษาคนไหนที่แผนควรต่างออกไป — วัดแล้ว execution เท่ากัน
 * ทุกฐาน (19 ms) ต่างกันแค่ว่าจ่ายค่าวางแผนซ้ำหรือไม่
 */
set plan_cache_mode = force_generic_plan
as $$
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
  -- `materialized` ทั้งสามตัวโดยตั้งใจ — ถ้าปล่อยให้ PostgreSQL inline
  -- เข้าไปในแขนงของ case มันจะกลับไปอ่าน view ใหม่ทุกกฎ ซึ่งคือปัญหาเดิม
  -- ทั้งหมด CTE ที่ไม่ถูกอ้างถึงเลยจะไม่ถูกประเมิน หลักสูตรที่ไม่มีกฎ
  -- หมวดหน่วยกิตจึงไม่จ่ายค่า cat_credit
  with credit as materialized (
    select v.course_id, v.credits_earned, v.earns_credit, v.is_provisional
      from v_student_course_credit v
     where v.student_id = p_student_id
  ),
  -- ต้องจำกัดเฉพาะหมวดที่มีกฎอ้างถึงจริง ไม่ใช่ทุกหมวดของหลักสูตร
  --
  -- ครั้งแรกเขียนเป็น "ทุกหมวด" ด้วยเหตุผลว่าอ่านทีเดียวจบ ผลคือเร็วขึ้น
  -- 8 เท่าบนฐานข้อมูลหนึ่ง แต่ **ช้าลง** บนอีกฐานหนึ่งที่มี 18 หมวด
  -- (เทียบกับ 9 หมวด) เพราะของเดิมดึงเฉพาะหมวดที่กฎถามถึงสามหมวด
  -- ส่วนตัวใหม่ดึงมาทั้งสิบแปด — ประหยัดจำนวนครั้งแต่จ่ายเนื้องานมากขึ้น
  -- จนกลบกันหมด
  --
  -- ที่ถูกคือดึง **ครั้งเดียว** และ **เท่าที่ต้องใช้** ทั้งสองอย่างพร้อมกัน
  cat_credit as materialized (
    select cat.code, c.credits_earned
      from v_student_credits_by_category c
      join curriculum_category cat on cat.id = c.category_id
     where c.student_id = p_student_id
       and cat.curriculum_version_id = v_cv
       and cat.code in (select g2.params ->> 'category_code'
                          from graduation_rule g2
                         where g2.curriculum_version_id = v_cv
                           and g2.kind = 'credits_by_category')
  ),
  transferred as materialized (
    select pr.mapped_course_id
      from prior_academic_record pr
     where pr.student_id = p_student_id
       and pr.earns_credit
       and pr.approved_at is not null
  )
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
        coalesce((select sum(c.credits_earned) from credit c where c.earns_credit), 0)
        -- หน่วยกิตที่เทียบโอนมาและอนุมัติแล้ว
        + transfer_credits_total(p_student_id)

      when 'credits_by_category' then
        coalesce((select cc.credits_earned from cat_credit cc
                   where cc.code = g.params ->> 'category_code'), 0)
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
        (select count(*) from credit c where c.is_provisional)

      when 'required_courses' then
        -- จำนวนรายวิชาบังคับที่ยังไม่ผ่าน เกณฑ์คือ 0
        (select count(*)
         from curriculum_course cc
         where cc.curriculum_version_id = v_cv
           and cc.requirement = 'required'
           and not exists (
             select 1 from credit c
             where c.course_id = cc.course_id and c.earns_credit
           )
           -- รายวิชาบังคับที่เทียบโอนมาแล้วต้องไม่นับว่ายังขาด
           and not exists (
             select 1 from transferred t where t.mapped_course_id = cc.course_id
           ))

      else 0
    end)::numeric as achieved) a
  where g.curriculum_version_id = v_cv
  order by g.sort_order;
end $$;

comment on function evaluate_graduation is
  'ตรวจจบแบบเรียกได้ทุกเมื่อ — อ่านหน่วยกิตของนักศึกษาครั้งเดียวแล้วให้ทุกกฎใช้ร่วมกัน';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0052_teacher_submit_grades.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0052 — ครูส่งเกรดของกลุ่มเรียนตัวเองได้
--
-- ─── ปัญหา ───
-- `submit_section_grades()` ไม่ใช่ security definer โดยตั้งใจ (ดู 0049)
-- ครูจึงต้องมีสิทธิ์เขียนตารางที่ฟังก์ชันแตะจริง ๆ ทุกตาราง
-- 0049 เปิด `grade_submission` ให้แล้ว แต่ `enrollment_result` ยังปิดอยู่
-- เพราะ 0041 ตั้ง `enrollment_result_staff_insert` ไว้ที่
-- `is_institution_wide_role()` ล้วน
--
-- ผลคือ **ครูส่งเกรดของตัวเองไม่ได้เลยสักครั้ง** — ได้ 403 ทุกครั้งที่กด
-- ทั้งที่ขั้นแรกของสายอนุมัติชื่อ `teacher_submitted` และ `STAGE_APPROVERS`
-- ในชั้น API ก็ระบุว่าขั้นนั้นเป็นของครู งานทะเบียนต้องเป็นคนกดส่งแทน
-- ทุกกลุ่มเรียนของทั้งวิทยาลัย ซึ่งไม่ใช่สิ่งที่ระบบออกแบบไว้
--
-- ─── ทำไมไม่มีใครเห็น ───
-- เทสต์ทุกชุด `insert into grade_submission` ตรงด้วยสิทธิ์เจ้าของฐานข้อมูล
-- ในขั้นเตรียมข้อมูล แล้วทดสอบขั้นถัด ๆ ไป — ไม่มีเทสต์ไหนเดินเส้นทาง
-- "ครูกดส่งเกรดของตัวเอง" เลยสักข้อ รูปแบบเดียวกับ AUTH-26 ที่ผ่านมาตลอด
-- เพราะหยิบ token จากทางที่ระบบจริงไม่มี
--
-- ─── ทำไมเปิดแค่นี้ถึงปลอดภัย ───
-- เงื่อนไขผูกกับสิ่งที่ฟังก์ชันยอมทำอยู่แล้วสามชั้น
--   1. ต้องเป็นครูผู้สอนของกลุ่มเรียนนั้นเอง ไม่ใช่ครูคนไหนก็ได้
--   2. รอบส่งเกรดต้องอยู่ขั้น draft หรือ returned เท่านั้น —
--      `submit_section_grades()` ปฏิเสธขั้นอื่นอยู่แล้ว (0016 บรรทัด 211)
--      นโยบายนี้จึงไม่ได้เปิดอะไรที่ฟังก์ชันไม่ยอมทำ
--   3. รอบที่ล็อกแล้วยังแก้ไม่ได้เหมือนเดิม การเปลี่ยนเกรดหลังล็อกยังต้อง
--      ผ่าน `grade_change_request` ที่ต้องมีผู้อนุมัติสองคน (หลักข้อ 3ก)
--
-- สิทธิ์ update และ delete ยังปิดสำหรับครูเหมือนเดิม — `enrollment_result`
-- แก้ทับไม่ได้อยู่แล้ว ต้องออก revision ใหม่ที่ชี้กลับแถวเดิม (หลักข้อ 4)
--
-- ─── ทำไมต้องแก้ตัวนโยบายเดิม ไม่ใช่เพิ่มนโยบายใหม่ ───
-- `enrollment_result_staff_insert` เป็น **restrictive** ซึ่ง PostgreSQL รวม
-- ด้วย AND การเพิ่มนโยบาย permissive อีกข้อจึงไม่มีผลเลย — ต้องแก้เงื่อนไข
-- ในตัวมันเอง (หลักข้อ 2 ของโปรเจกต์: permissive รวมด้วย OR · restrictive
-- รวมด้วย AND)
-- ═══════════════════════════════════════════════════════════════════

begin;

-- เผื่อกรณีที่เคยลองเพิ่มแบบ permissive ไว้ ซึ่งไม่มีผลกับ restrictive
drop policy if exists enrollment_result_teacher_insert on enrollment_result;

drop policy if exists enrollment_result_staff_insert on enrollment_result;

create policy enrollment_result_staff_insert on enrollment_result
  as restrictive for insert
  with check (
    is_institution_wide_role()
    or exists (
      select 1
        from enrollment e
        join class_section cs on cs.id = e.class_section_id
        join staff st         on st.id = cs.teacher_id
        left join grade_submission gs on gs.class_section_id = cs.id
       where e.id = enrollment_result.enrollment_id
         and st.person_id = current_actor_id()
         -- ยังไม่มีแถว = ยังไม่เคยส่ง ซึ่งเทียบเท่า draft
         and coalesce(gs.stage::text, 'draft') in ('draft', 'returned')
    )
  );

comment on policy enrollment_result_staff_insert on enrollment_result is
  'บทบาทระดับวิทยาลัยบันทึกผลได้เสมอ · ครูผู้สอนบันทึกได้เฉพาะกลุ่มเรียนของตัวเองและเฉพาะตอนที่รอบส่งเกรดยังไม่ล็อก — หลังล็อกต้องผ่าน grade_change_request';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0053_student_profile.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0053 — ระเบียนนักศึกษาให้ครบตามที่งานทะเบียนใช้จริง
--
-- เทียบกับระบบที่วิทยาลัยใช้อยู่ (ดู docs/sisa-gap.md) ระบบนั้นเก็บข้อมูล
-- ผู้สมัคร/นักศึกษาเป็นแปดกลุ่ม ของเรามีครบแค่กลุ่มเดียว ผลคืองานจริง
-- สามอย่างทำไม่ได้เลย — พิจารณาทุนและ กยศ. (ต้องรู้รายได้ผู้ปกครอง) ·
-- ส่งจดหมายเชิญผู้ปกครอง (ต้องมีที่อยู่) · รับมือเหตุในสถานศึกษา
-- (ต้องรู้ประวัติแพ้ยาและโรคประจำตัว)
--
-- ═══ ทำไมข้อมูลอ่อนไหวแยกตาราง ไม่ใช่เพิ่มคอลัมน์ใน person ═══
-- หมู่โลหิต ประวัติแพ้ยา โรคประจำตัว เชื้อชาติ ศาสนา เป็นข้อมูลอ่อนไหว
-- ตาม PDPA มาตรา 26 ซึ่งเข้มกว่าข้อมูลทั่วไป และ **RLS แยกรายคอลัมน์ไม่ได้**
-- ถ้าเพิ่มลง `person` ใครที่อ่าน person ได้ก็อ่านประวัติแพ้ยาได้ด้วย
-- แปลว่าครูผู้สอนทุกคนเห็นศาสนาและโรคประจำตัวของนักศึกษาทุกคนที่ตัวเองสอน
-- (ข้อจำกัดเดียวกับที่ทำให้ `user_credential` ต้องใช้ trigger ใน 0042)
--
-- ═══ ใครเห็นข้อมูลอ่อนไหวได้ ═══
--   งานทะเบียน · กิจการนักศึกษา · ผู้อำนวยการ · ผู้ดูแล → ทั้งวิทยาลัย
--   ครูที่ปรึกษา                                        → เฉพาะเด็กในที่ปรึกษาตัวเอง
--   ครูผู้สอน                                           → ไม่เห็นเลย แม้จะสอนอยู่
--   ฝ่ายวิชาการ · การเงิน                               → ไม่เห็น
--   นักศึกษาเจ้าของ และผู้ปกครองที่ยืนยันตัวตนแล้ว        → เห็นของตัวเอง/บุตรหลาน
--
-- **ฝ่ายวิชาการกับการเงินไม่เห็น ทั้งที่เป็น is_institution_wide_role()**
-- เพราะสุขภาพไม่เกี่ยวกับการจัดหลักสูตรหรือการเก็บเงิน การให้สิทธิ์ตาม
-- ความสะดวกคือสิ่งที่ทำให้ข้อมูลอ่อนไหวรั่วโดยไม่มีใครตั้งใจ
--
-- รายได้ผู้ปกครองไม่ใช่ข้อมูลอ่อนไหวตาม ม.26 แต่ใช้พิจารณาทุน จึงอยู่คนละ
-- ตารางกับสุขภาพ และให้การเงินเห็นได้
--
-- ═══ ทำไมตารางอาจารย์ที่ปรึกษาต้องมาในไฟล์เดียวกัน ═══
-- นโยบายข้างบนอ้าง "ครูที่ปรึกษาของนักศึกษาคนนั้น" ซึ่งยังไม่มีในระบบเลย
-- ถ้าเขียนนโยบายไว้ก่อนโดยยังไม่มีตาราง จะต้องใส่เงื่อนไขที่เป็นเท็จเสมอ
-- แล้วรอแก้ทีหลัง — รูปแบบเดียวกับที่ทำให้ `provisioning_log` อ่านไม่ได้
-- จากฝั่งที่เป็นเจ้าของข้อมูล (ข้อ 9) คอมเมนต์บอกเจตนา นโยบายบอกความจริง
--
-- ═══ ทำไมที่อยู่และประวัติการศึกษาเดิมแยกตาราง ═══
-- ที่อยู่มีอย่างน้อยสองชุด (ทะเบียนบ้าน · ปัจจุบัน) และของบิดามารดาอีกชุด
-- การทำเป็นคอลัมน์แปลว่าต้องซ้ำสี่ชุด · ส่วนประวัติการศึกษาเดิมเคยอยู่ใน
-- `application` เท่านั้น ซึ่งตายอยู่ในใบสมัคร — คนที่ย้ายสถานศึกษาเข้ามา
-- หรือถูกนำเข้าจากระบบเดิมจะไม่มีข้อมูลนี้เลย
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ชนิดข้อมูลใหม่
-- ───────────────────────────────────────────────────────────────────
do $$ begin
  create type address_kind as enum ('registered', 'current', 'work');
exception when duplicate_object then null; end $$;

do $$ begin
  create type parent_role as enum ('father', 'mother');
exception when duplicate_object then null; end $$;

do $$ begin
  create type parent_status as enum ('alive', 'deceased', 'unknown');
exception when duplicate_object then null; end $$;

do $$ begin
  create type marital_status_kind as enum
    ('together', 'separated', 'divorced', 'father_deceased', 'mother_deceased', 'both_deceased', 'unknown');
exception when duplicate_object then null; end $$;

/*
 * ประเภทความพิการตามที่หน่วยงานต้นสังกัดใช้จำแนก
 *
 * เก็บเป็นชนิดข้อมูลไม่ใช่ข้อความอิสระ เพราะตัวเลขนี้ใช้ยันการขอรับเงิน
 * อุดหนุนสำหรับผู้เรียนพิการ ถ้าปล่อยให้พิมพ์เอง จะนับไม่ได้ว่ามีกี่คน
 * ในแต่ละประเภท และคำสะกดต่างกันจะกลายเป็นคนละกลุ่ม
 */
do $$ begin
  create type disability_kind as enum (
    'none', 'vision', 'hearing', 'intellectual', 'physical',
    'learning', 'speech', 'behavioral', 'autistic', 'multiple');
exception when duplicate_object then null; end $$;

/* วิธีเดินทางมาสถานศึกษา — ใช้วางแผนรถรับส่งและประเมินความเสี่ยงการมาสาย */
do $$ begin
  create type travel_mode_kind as enum (
    'walk', 'motorcycle', 'car', 'paid_transit', 'free_transit',
    'loaned_bicycle', 'school_van', 'guardian', 'other');
exception when duplicate_object then null; end $$;

-- ───────────────────────────────────────────────────────────────────
-- ข้อมูลทั่วไปที่ยังขาด — ไม่ใช่ข้อมูลอ่อนไหว จึงอยู่ใน person ได้
-- ───────────────────────────────────────────────────────────────────
alter table person
  add column if not exists prefix_en    text,
  add column if not exists nickname_th  text,
  add column if not exists nickname_en  text,
  add column if not exists nationality  text,
  add column if not exists line_id      text,
  add column if not exists facebook     text,
  add column if not exists birth_place_th text;

comment on column person.nationality is
  'สัญชาติ — ต่างจากเชื้อชาติซึ่งเป็นข้อมูลอ่อนไหวและอยู่ใน person_sensitive';

-- ข้อมูลครอบครัวระดับนักศึกษา ใช้ประกอบการพิจารณาทุน
alter table student
  add column if not exists siblings_count      smallint check (siblings_count between 1 and 30),
  add column if not exists birth_order         smallint check (birth_order between 1 and 30),
  add column if not exists siblings_studying   smallint check (siblings_studying between 0 and 30),
  add column if not exists parents_marital     marital_status_kind,
  add column if not exists class_number        smallint check (class_number between 1 and 99),
  add column if not exists travel_mode         travel_mode_kind,
  add column if not exists talent_th           text;

comment on column student.siblings_count is 'จำนวนพี่น้องรวมตัวนักศึกษาเอง';
comment on column student.class_number is
  'เลขที่ในห้อง — ต่างจากรหัสนักศึกษา ใช้เรียกชื่อและเรียงลำดับในเอกสารของห้อง';

-- ───────────────────────────────────────────────────────────────────
-- อาจารย์ที่ปรึกษา
--
-- ผูกรายคนไม่ใช่รายห้อง เพราะนักศึกษาที่ย้ายห้องกลางปีต้องไม่หลุดจาก
-- ที่ปรึกษาเดิมโดยอัตโนมัติ — ชั้น API มอบหมายทั้งห้องพร้อมกันได้อยู่แล้ว
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_advisor (
  id               uuid primary key default gen_random_uuid(),
  institution_id   uuid not null references institution(id) on delete restrict,
  student_id       uuid not null references student(id)     on delete cascade,
  staff_id         uuid not null references staff(id)       on delete restrict,
  academic_year_id uuid          references academic_year(id) on delete restrict,
  is_primary       boolean not null default true,
  assigned_on      date not null default current_date,
  ended_on         date,
  note             text,
  created_at       timestamptz not null default now(),
  check (ended_on is null or ended_on >= assigned_on)
);

-- ที่ปรึกษาหลักของปีการศึกษาหนึ่งมีได้คนเดียว
create unique index if not exists student_advisor_primary
  on student_advisor (student_id, academic_year_id)
  where is_primary and ended_on is null;

create index if not exists student_advisor_staff on student_advisor (staff_id) where ended_on is null;

comment on table student_advisor is
  'อาจารย์ที่ปรึกษา — เป็นฐานของนโยบายที่ให้ครูที่ปรึกษาเห็นข้อมูลอ่อนไหวของเด็กในที่ปรึกษาตัวเอง';

-- ───────────────────────────────────────────────────────────────────
-- ข้อมูลอ่อนไหวตาม PDPA มาตรา 26
-- ───────────────────────────────────────────────────────────────────
create table if not exists person_sensitive (
  person_id        uuid primary key references person(id) on delete cascade,
  institution_id   uuid not null references institution(id) on delete restrict,
  ethnicity        text,
  religion         text,
  blood_type       text check (blood_type is null or blood_type in ('A','B','AB','O')),
  drug_allergy     text,
  chronic_disease  text,
  weight_kg        numeric(5,2) check (weight_kg is null or weight_kg between 10 and 300),
  height_cm        numeric(5,2) check (height_cm is null or height_cm between 50 and 250),
  distinguishing   text,
  /*
   * ความพิการอยู่ในตารางนี้เพราะเป็นข้อมูลสุขภาพตาม ม.26 — แต่ต่างจาก
   * ฟิลด์อื่นตรงที่ **ต้องนับได้** เพื่อยันการขอรับเงินอุดหนุนผู้เรียนพิการ
   * ซึ่งแปลว่าจะมีคนต้องนับยอดโดยไม่ต้องเห็นว่าเป็นใคร — ทำได้ด้วย
   * view ที่นับอย่างเดียวในภายหลัง ไม่ใช่ด้วยการเปิดตารางนี้ให้กว้างขึ้น
   */
  disability       disability_kind,
  disability_note  text,
  note             text,
  updated_at       timestamptz not null default now()
);

comment on table person_sensitive is
  'ข้อมูลอ่อนไหวตาม PDPA ม.26 — แยกตารางเพราะ RLS แยกรายคอลัมน์ไม่ได้ ผู้เข้าถึงแคบกว่า person';

-- ───────────────────────────────────────────────────────────────────
-- ที่อยู่
-- ───────────────────────────────────────────────────────────────────
create table if not exists person_address (
  id             uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institution(id) on delete restrict,
  person_id      uuid not null references person(id) on delete cascade,
  kind           address_kind not null,
  address_line   text not null,
  subdistrict_th text,
  district_th    text,
  province_th    text,
  postal_code    text check (postal_code is null or postal_code ~ '^[0-9]{5}$'),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (person_id, kind)
);

-- ───────────────────────────────────────────────────────────────────
-- บิดามารดา
--
-- ไม่ผูกกับ `person` เพราะบิดามารดาส่วนใหญ่ไม่ใช่ผู้ใช้ระบบ การบังคับให้
-- สร้าง person ทุกคนแปลว่าตาราง person เต็มไปด้วยแถวที่ไม่มีใครล็อกอิน
-- ส่วนผู้ปกครองที่เข้าระบบได้จริงยังใช้ `student_guardian` ตามเดิม
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_parent (
  id               uuid primary key default gen_random_uuid(),
  institution_id   uuid not null references institution(id) on delete restrict,
  student_id       uuid not null references student(id) on delete cascade,
  role             parent_role not null,
  prefix_th        text,
  first_name_th    text not null,
  last_name_th     text,
  national_id_hash bytea,
  birth_date       date,
  occupation_th    text,
  income_monthly   numeric(12,2) check (income_monthly is null or income_monthly >= 0),
  status           parent_status not null default 'alive',
  phone            text,
  work_phone       text,
  email            text,
  address_line     text,
  subdistrict_th   text,
  district_th      text,
  province_th      text,
  postal_code      text check (postal_code is null or postal_code ~ '^[0-9]{5}$'),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (student_id, role)
);

comment on column student_parent.income_monthly is
  'รายได้ต่อเดือน — ใช้พิจารณาทุนและ กยศ. ไม่ใช่ข้อมูลอ่อนไหวตาม ม.26 แต่เป็นความลับ';

comment on column student_parent.national_id_hash is
  'เก็บเป็นค่าแฮชเท่านั้น หลักเดียวกับ person.national_id_hash — ใช้ตรวจซ้ำได้โดยไม่เก็บเลขจริง';

-- ───────────────────────────────────────────────────────────────────
-- ประวัติการศึกษาเดิม
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_prior_education (
  id                  uuid primary key default gen_random_uuid(),
  institution_id      uuid not null references institution(id) on delete restrict,
  student_id          uuid not null references student(id) on delete cascade,
  level_th            text not null,
  completed_year_be   smallint check (completed_year_be between 2400 and 2700),
  gpax                numeric(4,2) check (gpax is null or gpax between 0 and 4),
  program_th          text,
  program_type_th     text,
  school_th           text,
  province_th         text,
  verified_at         timestamptz,
  verified_by         uuid references person(id) on delete set null,
  note                text,
  created_at          timestamptz not null default now(),
  unique (student_id, level_th)
);

comment on column student_prior_education.verified_at is
  'วันที่ตรวจวุฒิกับสถานศึกษาเดิม — ว่างแปลว่ายังไม่ได้ตรวจ ไม่ใช่ตรวจแล้วไม่ผ่าน';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Row-Level Security
--
-- แยกเป็นทรานแซกชันที่สองเพื่อให้ตารางมีอยู่จริงก่อนสร้างนโยบาย
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- นักศึกษาที่ผู้ใช้ปัจจุบันเป็นที่ปรึกษาอยู่
--
-- security definer เพื่อตัดวงจร — นโยบายของ student_advisor เองก็อ้าง
-- ตารางนี้ ถ้าเรียกตรง ๆ จะเกิด infinite recursion เหมือนที่เคยเจอกับ
-- student ↔ student_guardian
-- ───────────────────────────────────────────────────────────────────
create or replace function actor_advisee_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select sa.student_id
    from student_advisor sa
    join staff st on st.id = sa.staff_id
   where st.person_id = current_actor_id()
     and sa.ended_on is null
$$;

comment on function actor_advisee_ids() is
  'นักศึกษาในที่ปรึกษาของผู้ใช้ปัจจุบัน — security definer เพื่อตัดวงจรของนโยบาย';

/*
 * บุคคลที่ผู้ใช้ปัจจุบันดูข้อมูลส่วนตัวได้ — ตัวเอง บุตรหลาน และเด็กในที่ปรึกษา
 *
 * ต้องเป็น security definer เพราะการแปลง student → person ต้องอ่านตาราง
 * `student` ซึ่งมี RLS ของตัวเอง ครูที่ปรึกษาที่**ไม่ได้สอน**เด็กคนนั้น
 * มองไม่เห็นแถวใน student เลย การตรวจจึงล้มทั้งที่สิทธิ์ถูกต้อง —
 * เป็นกับดักเดียวกับที่ทำให้ต้องมี student_institution() ใน 0012
 */
create or replace function actor_visible_person_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select current_actor_id()
  union
  select s.person_id from student s
   where s.id in (select actor_student_ids())
      or s.id in (select actor_advisee_ids())
$$;

/*
 * ─── ใครเห็นข้อมูลอ่อนไหวได้ ───
 * แคบกว่า is_institution_wide_role() โดยตั้งใจ — ฝ่ายวิชาการและการเงิน
 * ไม่ต้องใช้ข้อมูลสุขภาพในการทำงาน จึงไม่ควรเห็น
 */
create or replace function may_see_sensitive(p_person_id uuid)
returns boolean language sql stable as $$
  select
    current_app_role() in ('registrar', 'student_affairs', 'director', 'admin')
    or p_person_id in (select actor_visible_person_ids())
$$;

comment on function may_see_sensitive(uuid) is
  'สิทธิ์อ่านข้อมูลอ่อนไหว — งานทะเบียน/กิจการนักศึกษา/ผู้บริหาร · ครูที่ปรึกษาเฉพาะเด็กของตัวเอง · เจ้าตัวและผู้ปกครองที่ยืนยันแล้ว';

-- ─── student_advisor ───────────────────────────────────────────────
alter table student_advisor enable row level security;
alter table student_advisor force row level security;

create policy tenant_isolation on student_advisor
  using (institution_id = current_institution_id());

-- ครูเห็นรายการที่ปรึกษาของตัวเอง · นักศึกษาเห็นว่าใครเป็นที่ปรึกษาตน
create policy advisor_scope on student_advisor
  as restrictive using (
    is_institution_wide_role()
    or exists (select 1 from staff st
                where st.id = student_advisor.staff_id
                  and st.person_id = current_actor_id())
    or student_id in (select actor_student_ids())
  );

/*
 * ─── ทำไมต้องแยกเป็นสามนโยบาย ไม่ใช่ `for all` ───
 * นโยบาย **restrictive แบบ `for all` มีผลกับ SELECT ด้วย** ซึ่งแปลว่า
 * เงื่อนไข "ต้องเป็นงานทะเบียนถึงจะเขียนได้" จะกลายเป็น "ต้องเป็นงานทะเบียน
 * ถึงจะอ่านได้" ไปด้วยโดยไม่มีอะไรฟ้อง — ครูที่ปรึกษาจะอ่านไม่ได้เลย
 * ทั้งที่นโยบายอ่านอนุญาตแล้ว
 */
create policy advisor_insert on student_advisor
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

create policy advisor_update on student_advisor
  as restrictive for update
  using (current_app_role() in ('registrar', 'academic', 'director', 'admin'))
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

create policy advisor_delete on student_advisor
  as restrictive for delete
  using (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

-- ─── person_sensitive ──────────────────────────────────────────────
alter table person_sensitive enable row level security;
alter table person_sensitive force row level security;

create policy tenant_isolation on person_sensitive
  using (institution_id = current_institution_id());

create policy sensitive_read on person_sensitive
  as restrictive for select using (may_see_sensitive(person_id));

/*
 * เขียนได้เฉพาะงานทะเบียนและกิจการนักศึกษา — ครูที่ปรึกษา "เห็น" ได้
 * แต่แก้ไม่ได้ เพราะข้อมูลสุขภาพต้องมาจากเอกสารที่ผู้ปกครองกรอก
 * ไม่ใช่จากความจำของครู
 */
create policy sensitive_insert on person_sensitive
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'student_affairs', 'admin'));

create policy sensitive_update on person_sensitive
  as restrictive for update
  using (current_app_role() in ('registrar', 'student_affairs', 'admin'))
  with check (current_app_role() in ('registrar', 'student_affairs', 'admin'));

create policy sensitive_delete on person_sensitive
  as restrictive for delete
  using (current_app_role() in ('registrar', 'student_affairs', 'admin'));

-- ─── person_address ────────────────────────────────────────────────
alter table person_address enable row level security;
alter table person_address force row level security;

create policy tenant_isolation on person_address
  using (institution_id = current_institution_id());

create policy address_scope on person_address
  as restrictive using (
    is_institution_wide_role()
    or person_id in (select actor_visible_person_ids())
  );

create policy address_insert on person_address
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'student_affairs', 'admin'));

create policy address_update on person_address
  as restrictive for update
  using (current_app_role() in ('registrar', 'student_affairs', 'admin'))
  with check (current_app_role() in ('registrar', 'student_affairs', 'admin'));

create policy address_delete on person_address
  as restrictive for delete
  using (current_app_role() in ('registrar', 'student_affairs', 'admin'));

-- ─── student_parent ────────────────────────────────────────────────
alter table student_parent enable row level security;
alter table student_parent force row level security;

create policy tenant_isolation on student_parent
  using (institution_id = current_institution_id());

-- การเงินเห็นด้วย เพราะรายได้ใช้พิจารณาทุนและ กยศ.
create policy parent_scope on student_parent
  as restrictive using (
    current_app_role() in ('registrar', 'student_affairs', 'finance', 'director', 'admin')
    or student_id in (select actor_student_ids())
    or student_id in (select actor_advisee_ids())
  );

create policy parent_insert on student_parent
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'student_affairs', 'admin'));

create policy parent_update on student_parent
  as restrictive for update
  using (current_app_role() in ('registrar', 'student_affairs', 'admin'))
  with check (current_app_role() in ('registrar', 'student_affairs', 'admin'));

create policy parent_delete on student_parent
  as restrictive for delete
  using (current_app_role() in ('registrar', 'student_affairs', 'admin'));

-- ─── student_prior_education ───────────────────────────────────────
alter table student_prior_education enable row level security;
alter table student_prior_education force row level security;

create policy tenant_isolation on student_prior_education
  using (institution_id = current_institution_id());

-- ประวัติการศึกษาเดิมไม่ใช่ข้อมูลอ่อนไหว — บทบาทระดับวิทยาลัยเห็นได้ตามปกติ
create policy prior_education_scope on student_prior_education
  as restrictive using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_advisee_ids())
  );

create policy prior_education_insert on student_prior_education
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'academic', 'admin'));

create policy prior_education_update on student_prior_education
  as restrictive for update
  using (current_app_role() in ('registrar', 'academic', 'admin'))
  with check (current_app_role() in ('registrar', 'academic', 'admin'));

create policy prior_education_delete on student_prior_education
  as restrictive for delete
  using (current_app_role() in ('registrar', 'academic', 'admin'));

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0054_student_leave.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0054 — การลาของนักศึกษา
--
-- ก่อนไฟล์นี้ ระบบมี `attendance_status` ที่มี 'leave_sick'/'leave_personal'
-- และ `attendance_source` ที่มี 'guardian_leave' มาตั้งแต่ 0005 — แต่
-- **ไม่มีที่ให้ยื่นใบลา** ทางเดียวที่การลาจะเข้าระบบได้คือครูกดเลือกสถานะนั้น
-- ตอนเช็คชื่อ ซึ่งแปลว่า
--   · ใบลาที่ยื่นล่วงหน้าไม่มีที่เก็บ ครูต้องจำเอง
--   · ใบรับรองแพทย์ที่มาทีหลังแก้ย้อนหลังไม่ได้เป็นระบบ ต้องไล่บอกครูทีละคน
--   · ไม่มีใครตอบได้ว่านักศึกษาคนหนึ่งลาไปกี่วันในภาคเรียน
--
-- ═══ `can_approve_leave` มีมาตั้งแต่ 0002 และไม่เคยมีใครอ่าน ═══
-- คอลัมน์นี้อยู่ใน `student_guardian` ตั้งแต่ไฟล์ที่สองของโปรเจกต์ แต่ค้นทั้ง
-- repo แล้วไม่มีโค้ดไหนอ่านเลยสักบรรทัด — รูปเดียวกับ `take_usage_snapshot()`
-- (ข้อ 8) และ `generate_class_meetings()` คือคอลัมน์ประกาศเจตนาไว้ แล้วไม่มี
-- อะไรทำให้เจตนานั้นเกิดขึ้นจริง ไฟล์นี้ทำให้มันมีความหมาย — ผู้ปกครองที่ถูก
-- ติ๊กช่องนี้ยื่นใบลาแทนบุตรหลานได้ และรับรองใบลาที่นักศึกษายื่นเองได้
--
-- ═══ ทำไมการรับรองของผู้ปกครองไม่ใช่**เงื่อนไข**ของการอนุมัติ ═══
-- ถ้าบังคับว่าต้องมีผู้ปกครองรับรองก่อน เจ้าหน้าที่ถึงจะอนุมัติได้ นักศึกษา
-- ที่ยังไม่มีผู้ปกครองผูกบัญชี (ซึ่งเป็นสภาพเริ่มต้นของทุกคน) จะลาไม่ได้เลย
-- ตลอดไป — วงจรปิดแบบเดียวกับข้อ 6 ที่ผู้ดูแลเข้าระบบไม่ได้เพราะต้องตั้ง MFA
-- ก่อน แต่เส้นทางตั้ง MFA ก็ต้องล็อกอินก่อน จึงเก็บเป็น**ข้อเท็จจริงที่บันทึกไว้**
-- ให้เจ้าหน้าที่เห็นแล้วตัดสินใจเอง ไม่ใช่ประตูที่ล็อกได้
--
-- ═══ ทำไมการอนุมัติต้องแก้ `attendance_record` จริง ═══
-- ถ้าใบลาเป็นแค่กระดาษในระบบที่ไม่แตะเวลาเรียน กฎ 80% จะยังตัดสิทธิ์คนที่
-- ลาป่วยโดยมีใบรับรองแพทย์อยู่ดี — ใบลาที่ไม่มีผลคือใบลาที่ไม่มีประโยชน์
-- แต่การแก้ต้องมีขอบเขตชัดสามข้อ
--   1. แตะได้เฉพาะแถวที่ยัง**ไม่มีการเช็คชื่อ** หรือที่เช็คไว้ว่า `absent`
--      — `present`/`late` คือครูเห็นตัวจริง ใบลาไม่มีสิทธิ์ลบล้างสิ่งที่เกิดขึ้น
--   2. ทุกแถวที่ถูกแก้ถูกบันทึกไว้ใน `student_leave_applied` พร้อมค่าเดิม
--      การยกเลิกใบลาจึงคืนค่าเดิมได้ตรงแถว ไม่ใช่เดาว่าน่าจะเป็น absent
--   3. `source` เป็น 'guardian_leave' และ `recorded_by` เป็นผู้อนุมัติ
--      — หลักฐานต้องชี้คนที่ทำจริง ไม่ใช่ชี้ครูที่ไม่ได้กด (บทเรียนข้อ 5)
--
-- ═══ ใครอนุมัติได้ ═══
-- งานทะเบียน · งานปกครองและแนะแนว · ผู้อำนวยการ · ผู้ดูแล
-- **ไม่รวมฝ่ายวิชาการและการเงิน** ทั้งที่เป็น is_institution_wide_role()
-- เพราะการลาไม่ใช่งานของสองฝ่ายนั้น — หลักเดียวกับ 0053
-- ครูที่ปรึกษา **เห็นใบลาของเด็กในที่ปรึกษาตัวเองแต่ยังอนุมัติไม่ได้**
-- เพราะการอนุมัติเขียน `attendance_record` ของกลุ่มเรียนที่ตัวเองไม่ได้สอน
-- ซึ่ง RLS ของ 0039 ปฏิเสธ ผลจะเป็นการอนุมัติที่มีผลแค่บางวิชา — แย่กว่า
-- อนุมัติไม่ได้เลย เพราะไม่มีอะไรฟ้องว่ามันไม่ครบ
-- (การให้ครูที่ปรึกษา "เสนอความเห็น" แล้วงานปกครองอนุมัติ เป็นขั้นที่เพิ่ม
--  ทีหลังได้โดยไม่ต้องแก้ของเดิม — ยังไม่ทำเพราะยังไม่มีใครขอ)
--
-- ═══ ห้ามอนุมัติใบลาของตัวเองหรือของบุตรหลาน ═══
-- เงื่อนไขคือ **ผู้อนุมัติต้องไม่ใช่เจ้าของใบ** ไม่ใช่ "ต้องไม่ใช่คนที่กรอก"
-- ความต่างนี้สำคัญมาก — งานทะเบียนรับใบลาที่เป็นกระดาษมาแล้วพิมพ์เข้าระบบ
-- คือเส้นทางปกติที่สุด ถ้าห้าม "คนกรอกอนุมัติ" เจ้าหน้าที่จะบันทึกใบลาแล้ว
-- อนุมัติไม่ได้เลยสักใบ ต้องรอคนที่สองมากดทุกครั้ง ซึ่งวิทยาลัยเล็กที่มี
-- เจ้าหน้าที่ทะเบียนคนเดียวจะใช้ไม่ได้ทั้งฟีเจอร์ (วงจรปิดแบบเดียวกับข้อ 6
-- ที่ผู้ดูแลตั้ง MFA ไม่ได้เพราะต้องล็อกอินก่อน — เจอตอนกดปุ่มจริงบนหน้าจอ
-- ไม่ใช่ตอนเขียนเทสต์ เพราะเทสต์ยื่นด้วยบัญชีนักศึกษาซึ่งเป็นทางที่ต่างกัน)
--
-- สิ่งที่ต้องกันจริงคือคนที่**ได้ประโยชน์**จากใบนั้น — ตัวนักศึกษาเอง และ
-- ผู้ปกครองที่ยืนยันตัวตนแล้ว (เจ้าหน้าที่ที่เป็นผู้ปกครองของนักศึกษาใน
-- วิทยาลัยตัวเองจึงอนุมัติให้ลูกไม่ได้) ซึ่งตรงกับชุดที่ `actor_student_ids()`
-- คืนอยู่แล้วพอดี
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ชนิดข้อมูล
-- ───────────────────────────────────────────────────────────────────
do $$ begin
  create type student_leave_kind as enum ('sick', 'personal', 'activity');
exception when duplicate_object then null; end $$;

comment on type student_leave_kind is
  'activity = ไปราชการหรือทำกิจกรรมของวิทยาลัย ซึ่งไม่ใช่การลาของตัวนักศึกษาเอง แต่เข้าทางเดียวกันเพราะผลต่อเวลาเรียนเหมือนกัน';

do $$ begin
  create type student_leave_status as enum ('submitted', 'approved', 'rejected', 'cancelled');
exception when duplicate_object then null; end $$;

-- ───────────────────────────────────────────────────────────────────
-- ใบลา
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_leave (
  id               uuid primary key default gen_random_uuid(),
  institution_id   uuid not null references institution(id) on delete restrict,
  student_id       uuid not null references student(id) on delete cascade,
  kind             student_leave_kind not null,
  from_date        date not null,
  to_date          date not null,
  reason           text not null,
  /*
   * ระบบไฟล์แนบยังไม่มี (ต้องออกแบบที่เก็บและการจำกัดขนาด/ชนิดไฟล์แยก)
   * ช่องนี้จึงเก็บ**ข้อความ**ว่าเอกสารประกอบคืออะไรและอยู่ที่ใคร เช่น
   * "ใบรับรองแพทย์ รพ.สวนดอก เลขที่ 2569/1188 ส่งตัวจริงที่งานปกครอง"
   * ดีกว่าไม่มีที่ให้บันทึกเลยจนไปอยู่ในกระดาษที่หายได้
   */
  evidence_note    text,
  status           student_leave_status not null default 'submitted',

  requested_by     uuid references person(id) on delete restrict,
  requested_at     timestamptz not null default now(),

  -- การรับรองของผู้ปกครอง — เป็นข้อเท็จจริงที่บันทึกไว้ ไม่ใช่เงื่อนไข
  guardian_ack_by  uuid references person(id) on delete restrict,
  guardian_ack_at  timestamptz,

  decided_by       uuid references person(id) on delete restrict,
  decided_at       timestamptz,
  decision_note    text,

  -- จำนวนคาบที่ถูกปรับจริงตอนอนุมัติ — ศูนย์แปลว่าไม่มีคาบเรียนในช่วงนั้น
  -- หรือครูเช็คไปแล้วว่ามาเรียน ซึ่งเจ้าหน้าที่ต้องเห็นความต่าง
  applied_periods  integer not null default 0 check (applied_periods >= 0),

  created_at       timestamptz not null default now(),

  check (to_date >= from_date),
  check (from_date >= date '1900-01-01'),
  -- ตัดสินแล้วต้องรู้ว่าใครและเมื่อไร — ครบทั้งคู่หรือไม่มีเลย
  check ((decided_by is null) = (decided_at is null)),
  check ((guardian_ack_by is null) = (guardian_ack_at is null)),
  check (status in ('submitted', 'cancelled') or decided_at is not null)
);

create index if not exists student_leave_student on student_leave (student_id, from_date desc);
create index if not exists student_leave_pending on student_leave (institution_id, status)
  where status = 'submitted';

comment on table student_leave is
  'ใบลาของนักศึกษา — อนุมัติแล้วมีผลกับ attendance_record จริง มิฉะนั้นกฎเวลาเรียน 80% จะยังตัดสิทธิ์คนที่ลาถูกต้อง';
comment on column student_leave.applied_periods is
  'จำนวนคาบที่ถูกปรับตอนอนุมัติ — 0 แปลว่าไม่มีคาบในช่วงนั้นหรือครูเช็คว่ามาเรียนแล้ว ไม่ใช่ว่าอนุมัติไม่สำเร็จ';

-- ───────────────────────────────────────────────────────────────────
-- แถวเวลาเรียนที่ใบลาไปแก้ พร้อมค่าเดิม
--
-- มีตารางนี้เพราะการยกเลิกใบลาต้องคืนค่าเดิม**ตรงแถว** ถ้าเดาว่า "น่าจะเป็น
-- absent" จะไปทับกรณีที่เดิมไม่มีแถวเลย (ครูยังไม่ได้เช็ค) แล้วนักศึกษา
-- จะกลายเป็นขาดเรียนจากการยกเลิกใบลา ทั้งที่ไม่เคยมีใครบอกว่าขาด
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_leave_applied (
  leave_id             uuid not null references student_leave(id) on delete cascade,
  attendance_record_id uuid not null references attendance_record(id) on delete cascade,
  previous_status      attendance_status,   -- null = เดิมไม่มีแถว
  periods              smallint not null default 1,
  primary key (leave_id, attendance_record_id)
);

comment on column student_leave_applied.previous_status is
  'null แปลว่าเดิมไม่มีแถวเช็คชื่อเลย การยกเลิกจึงต้องลบแถวทิ้ง ไม่ใช่ตั้งเป็น absent';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ตรรกะ
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * นักศึกษาที่ผู้ใช้ปัจจุบันยื่นและรับรองใบลาแทนได้
 *
 * security definer เพราะอ่าน `student_guardian` ซึ่งมีนโยบายของตัวเอง
 * และนโยบายของ student_leave เองก็จะอ้างฟังก์ชันนี้ — เรียกตรงจะวนกลับ
 */
create or replace function actor_leave_guardian_students()
returns setof uuid language sql stable security definer set search_path = public as $$
  select sg.student_id
    from student_guardian sg
   where sg.person_id = current_actor_id()
     and sg.verified_at is not null
     and sg.can_approve_leave
$$;

comment on function actor_leave_guardian_students() is
  'บุตรหลานที่ผู้ใช้ปัจจุบันรับรองการลาแทนได้ — ใช้ can_approve_leave ที่มีมาตั้งแต่ 0002 และไม่เคยมีใครอ่าน';

/* บทบาทที่อนุมัติใบลาได้ — แคบกว่า is_institution_wide_role() โดยตั้งใจ */
create or replace function may_decide_student_leave()
returns boolean language sql stable as $$
  select current_app_role() in ('registrar', 'student_affairs', 'director', 'admin')
$$;

-- ───────────────────────────────────────────────────────────────────
-- แปลงชนิดการลาเป็นสถานะการเช็คชื่อ
-- ───────────────────────────────────────────────────────────────────
create or replace function leave_kind_to_attendance(p_kind student_leave_kind)
returns attendance_status language sql immutable as $$
  select case p_kind
           when 'sick'     then 'leave_sick'
           when 'personal' then 'leave_personal'
           when 'activity' then 'activity'
         end::attendance_status
$$;

-- ───────────────────────────────────────────────────────────────────
-- กฎของใบลา
--
-- อยู่ใน trigger ไม่ใช่ในนโยบาย RLS เพราะเงื่อนไขเป็นเรื่อง**ค่าในแถว**
-- (ใครยื่น ใครตัดสิน สถานะเดิมคืออะไร) ไม่ใช่เรื่องว่าแถวไหนมองเห็นได้
-- — บทเรียนเดียวกับ `grade_submission` ใน 0049
-- ───────────────────────────────────────────────────────────────────
create or replace function student_leave_guard() returns trigger
language plpgsql as $$
begin
  -- ปล่อยผ่านเมื่อไม่มีบริบทผู้ใช้ (superuser ตอนย้ายข้อมูลหรือ seed)
  -- บริบทที่ไม่มี app.role ก็ไม่มี app.institution_id นโยบาย RLS จึงปฏิเสธ
  -- ทุกแถวอยู่แล้ว การปล่อยผ่านตรงนี้จึงไม่เปิดช่องให้ใคร (หลักเดียวกับ 0042)
  if current_app_role() = 'none' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'submitted' then
      raise exception 'ใบลาที่สร้างใหม่ต้องมีสถานะ "ยื่นแล้ว" เท่านั้น';
    end if;
    if new.decided_by is not null or new.decided_at is not null then
      raise exception 'ใบลาที่สร้างใหม่ต้องยังไม่มีผู้อนุมัติ';
    end if;
    return new;
  end if;

  -- ── ต่อจากนี้เป็น UPDATE ──
  if old.status <> 'submitted' and new.status <> old.status
     and not (old.status = 'approved' and new.status = 'cancelled') then
    raise exception 'ใบลาที่ % แล้วเปลี่ยนสถานะไม่ได้อีก', old.status;
  end if;

  -- รายละเอียดของใบลาแก้ได้เฉพาะตอนที่ยังไม่ถูกตัดสิน มิฉะนั้นสิ่งที่
  -- เจ้าหน้าที่อนุมัติกับสิ่งที่อยู่ในระบบจะเป็นคนละใบกัน
  if old.status <> 'submitted'
     and (new.student_id <> old.student_id
          or new.kind      <> old.kind
          or new.from_date <> old.from_date
          or new.to_date   <> old.to_date) then
    raise exception 'ใบลาที่ตัดสินไปแล้วแก้รายละเอียดไม่ได้ — ต้องยกเลิกแล้วยื่นใหม่';
  end if;

  if new.status in ('approved', 'rejected') and old.status = 'submitted' then
    if not may_decide_student_leave() then
      raise exception 'อนุมัติใบลาได้เฉพาะงานทะเบียน งานปกครอง ผู้อำนวยการ และผู้ดูแลระบบ';
    end if;
    if new.decided_by is null then
      raise exception 'ต้องระบุผู้ตัดสินใบลา';
    end if;
    -- กันที่ "เจ้าของใบ" ไม่ใช่ที่ "คนกรอก" — งานทะเบียนพิมพ์ใบลาที่เป็น
    -- กระดาษเข้าระบบแล้วอนุมัติเองได้ตามปกติ เพราะไม่ได้เป็นผู้ได้ประโยชน์
    if new.student_id in (select actor_student_ids()) then
      raise exception 'อนุมัติใบลาของตัวเองหรือของบุตรหลานไม่ได้';
    end if;
  end if;

  -- ยกเลิกได้สองทาง — เจ้าของยกเลิกใบที่ยังไม่ถูกตัดสิน
  -- หรือเจ้าหน้าที่ยกเลิกใบที่อนุมัติไปแล้ว (ซึ่งคืนค่าเวลาเรียนให้ด้วย)
  if new.status = 'cancelled' and old.status = 'approved'
     and not may_decide_student_leave() then
    raise exception 'ยกเลิกใบลาที่อนุมัติแล้วได้เฉพาะเจ้าหน้าที่';
  end if;

  return new;
end $$;

drop trigger if exists student_leave_guard on student_leave;
create trigger student_leave_guard
  before insert or update on student_leave
  for each row execute function student_leave_guard();

-- ───────────────────────────────────────────────────────────────────
-- อนุมัติแล้วมีผลกับเวลาเรียนจริง
--
-- **ไม่ใช่ security definer โดยตั้งใจ** — ผู้เรียกต้องมีสิทธิ์เขียน
-- `attendance_record` อยู่แล้วตามนโยบายของ 0039 ซึ่งเป็นจริงกับสี่บทบาท
-- ที่อนุมัติใบลาได้พอดี ถ้าวันหนึ่งเปิดให้ครูที่ปรึกษาอนุมัติ คำสั่งนี้จะล้ม
-- ทันทีที่คาบแรกที่ตัวเองไม่ได้สอน — ซึ่งดีกว่าเงียบแล้วอนุมัติได้ครึ่งเดียว
-- ───────────────────────────────────────────────────────────────────
create or replace function decide_student_leave(
  p_leave_id uuid,
  p_approve  boolean,
  p_note     text default null
) returns table (
  leave_id        uuid,
  status          student_leave_status,
  applied_periods integer,
  skipped_present integer
) language plpgsql as $$
#variable_conflict use_column
declare
  v_leave   student_leave;
  v_status  attendance_status;
  v_applied integer := 0;
  v_skipped integer := 0;
  r         record;
  v_rec_id  uuid;
begin
  /*
   * ตรวจสิทธิ์**ก่อน**แตะอะไรทั้งสิ้น
   *
   * trigger `student_leave_guard` ตรวจซ้ำอยู่แล้ว แต่มันยิงตอน update
   * ซึ่งเป็นคำสั่ง**สุดท้าย**ของฟังก์ชันนี้ ถ้าพึ่งอย่างเดียว คนที่ไม่มีสิทธิ์
   * จะเดินผ่านการเขียน attendance_record ไปก่อนแล้วค่อยโดนปฏิเสธ —
   * ได้ผลถูกเพราะ rollback แต่ข้อความผิดพลาดจะเป็นเรื่อง RLS ของตารางอื่น
   * ที่อ่านแล้วไม่รู้ว่าปัญหาคืออะไร (เจอตอนเขียน TEST 236 ซึ่งผ่านด้วย
   * เหตุผลที่ผิด) และถ้าวันหนึ่งช่วงวันลาไม่มีคาบเรียนเลย จะไม่มีคำสั่งไหน
   * แตะ RLS เลยจนกว่าจะถึง update — ลำดับการตรวจจึงต้องไม่ขึ้นกับข้อมูล
   */
  if not may_decide_student_leave() then
    raise exception 'อนุมัติใบลาได้เฉพาะงานทะเบียน งานปกครอง ผู้อำนวยการ และผู้ดูแลระบบ';
  end if;

  select * into v_leave from student_leave where id = p_leave_id;
  if not found then
    raise exception 'ไม่พบใบลา หรือไม่มีสิทธิ์เข้าถึง';
  end if;
  if v_leave.status <> 'submitted' then
    raise exception 'ใบลานี้ถูกตัดสินไปแล้ว (สถานะ %)', v_leave.status;
  end if;
  -- เจ้าของใบอนุมัติเองไม่ได้ — actor_student_ids() คือตัวเองและบุตรหลาน
  -- ที่ยืนยันตัวตนแล้ว ซึ่งเป็นชุดคนที่ได้ประโยชน์จากใบนี้พอดี
  if v_leave.student_id in (select actor_student_ids()) then
    raise exception 'อนุมัติใบลาของตัวเองหรือของบุตรหลานไม่ได้';
  end if;

  if not p_approve then
    update student_leave
       set status = 'rejected', decided_by = current_actor_id(),
           decided_at = now(), decision_note = p_note
     where id = p_leave_id;
    return query select p_leave_id, 'rejected'::student_leave_status, 0, 0;
    return;
  end if;

  v_status := leave_kind_to_attendance(v_leave.kind);

  /*
   * อ่านคาบทั้งช่วงทีเดียวแล้ววนเขียน ไม่ใช่เรียกฟังก์ชันรายคาบ
   * ต้นทุนของคำสั่งในสคีมานี้อยู่ที่การวางแผน ซึ่งกางนโยบาย RLS ใหม่ทุกครั้ง
   */
  for r in
    select cm.id as meeting_id, e.id as enrollment_id, cm.period_count,
           ar.id as record_id, ar.status as current_status
      from enrollment e
      join class_meeting cm on cm.class_section_id = e.class_section_id
      left join attendance_record ar
             on ar.class_meeting_id = cm.id and ar.enrollment_id = e.id
     where e.student_id = v_leave.student_id
       and e.status = 'enrolled'
       and cm.meets_on between v_leave.from_date and v_leave.to_date
       and cm.status <> 'cancelled'
  loop
    -- ครูเห็นตัวจริงแล้ว ใบลาไม่มีสิทธิ์ลบล้างสิ่งที่เกิดขึ้น
    if r.current_status is not null and r.current_status <> 'absent' then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if r.record_id is null then
      insert into attendance_record
        (class_meeting_id, enrollment_id, status, source, recorded_by, note)
      values (r.meeting_id, r.enrollment_id, v_status, 'guardian_leave',
              current_actor_id(), 'ใบลาเลขที่ ' || p_leave_id)
      returning id into v_rec_id;
    else
      update attendance_record
         set status = v_status, source = 'guardian_leave',
             recorded_by = current_actor_id(), recorded_at = now(),
             note = 'ใบลาเลขที่ ' || p_leave_id
       where id = r.record_id
      returning id into v_rec_id;
    end if;

    insert into student_leave_applied
      (leave_id, attendance_record_id, previous_status, periods)
    values (p_leave_id, v_rec_id, r.current_status, r.period_count)
    on conflict do nothing;

    v_applied := v_applied + r.period_count;
  end loop;

  update student_leave
     set status = 'approved', decided_by = current_actor_id(),
         decided_at = now(), decision_note = p_note,
         applied_periods = v_applied
   where id = p_leave_id;

  return query select p_leave_id, 'approved'::student_leave_status, v_applied, v_skipped;
end $$;

comment on function decide_student_leave(uuid, boolean, text) is
  'อนุมัติหรือไม่อนุมัติใบลา — อนุมัติแล้วปรับ attendance_record เฉพาะแถวที่ยังไม่มีหรือที่เป็น absent และเก็บค่าเดิมไว้ให้ยกเลิกคืนได้';

-- ───────────────────────────────────────────────────────────────────
-- ยกเลิกใบลาที่อนุมัติไปแล้ว — คืนค่าเวลาเรียนตรงแถว
-- ───────────────────────────────────────────────────────────────────
create or replace function cancel_student_leave(p_leave_id uuid, p_reason text)
returns table (leave_id uuid, reverted integer)
language plpgsql as $$
#variable_conflict use_column
declare
  v_leave    student_leave;
  v_reverted integer := 0;
  r          record;
begin
  select * into v_leave from student_leave where id = p_leave_id;
  if not found then
    raise exception 'ไม่พบใบลา หรือไม่มีสิทธิ์เข้าถึง';
  end if;
  if v_leave.status not in ('submitted', 'approved') then
    raise exception 'ใบลาสถานะ % ยกเลิกไม่ได้', v_leave.status;
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'ต้องระบุเหตุผลที่ยกเลิก';
  end if;

  for r in
    select attendance_record_id, previous_status
      from student_leave_applied where leave_id = p_leave_id
  loop
    if r.previous_status is null then
      -- เดิมไม่มีแถวเลย — ตั้งเป็น absent จะกลายเป็นการทำให้ขาดเรียน
      -- จากการยกเลิกใบลา ทั้งที่ไม่เคยมีใครบอกว่าขาด
      delete from attendance_record where id = r.attendance_record_id;
    else
      update attendance_record
         set status = r.previous_status, source = 'system',
             recorded_by = current_actor_id(), recorded_at = now(),
             note = 'คืนค่าเดิมจากการยกเลิกใบลา ' || p_leave_id
       where id = r.attendance_record_id;
    end if;
    v_reverted := v_reverted + 1;
  end loop;

  delete from student_leave_applied where leave_id = p_leave_id;

  update student_leave
     set status = 'cancelled',
         decision_note = coalesce(decision_note || ' · ', '') || 'ยกเลิก: ' || p_reason,
         applied_periods = 0
   where id = p_leave_id;

  return query select p_leave_id, v_reverted;
end $$;

comment on function cancel_student_leave(uuid, text) is
  'ยกเลิกใบลา — คืนค่าเวลาเรียนจากค่าที่เก็บไว้ตอนอนุมัติ แถวที่เดิมไม่มีจะถูกลบ ไม่ใช่ตั้งเป็นขาดเรียน';

-- ───────────────────────────────────────────────────────────────────
-- สรุปวันลาต่อภาคเรียน — คำถามที่ไม่มีใครตอบได้ก่อนมีไฟล์นี้
-- ───────────────────────────────────────────────────────────────────
-- security_invoker บังคับให้ view ใช้สิทธิ์ของคนเรียก ไม่ใช่ของเจ้าของ view
-- ถ้าไม่ตั้ง view จะกลายเป็นทางลัดข้าม RLS ทั้งหมด (TEST 41 บังคับทั้งสคีมา)
create or replace view v_student_leave_summary with (security_invoker = true) as
  select sl.institution_id,
         sl.student_id,
         sl.kind,
         count(*)                                      as requests,
         sum(sl.to_date - sl.from_date + 1)            as days,
         sum(sl.applied_periods)                       as periods
    from student_leave sl
   where sl.status = 'approved'
   group by sl.institution_id, sl.student_id, sl.kind;

comment on view v_student_leave_summary is
  'สรุปการลาที่อนุมัติแล้วรายคน — นับวันจากช่วงวันที่ ส่วนคาบนับจากที่ปรับเวลาเรียนได้จริง สองตัวเลขนี้ต่างกันได้เมื่อวันลาไม่มีคาบเรียน';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Row-Level Security
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table student_leave enable row level security;
alter table student_leave force row level security;

create policy tenant_isolation on student_leave
  using (institution_id = current_institution_id());

/*
 * ─── ต้องแยกเป็น for select / insert / update / delete ───
 * นโยบาย restrictive แบบ `for all` กิน select ด้วย ซึ่งจะทำให้เงื่อนไข
 * "ต้องเป็นเจ้าหน้าที่ถึงจะอนุมัติได้" กลายเป็น "ถึงจะอ่านได้" โดยไม่มีอะไรฟ้อง
 * (บทเรียนจาก 0053 ที่ครูที่ปรึกษาอ่านไม่ได้ทั้งที่ฟังก์ชันตรวจสิทธิ์คืน true)
 */
create policy leave_read on student_leave
  as restrictive for select using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_advisee_ids())
  );

-- นักศึกษายื่นของตัวเองได้ · ผู้ปกครองที่ถูกติ๊ก can_approve_leave ยื่นแทนได้
-- · เจ้าหน้าที่ยื่นแทนได้ (ใบลาที่ส่งมาเป็นกระดาษ)
create policy leave_insert on student_leave
  as restrictive for insert with check (
    may_decide_student_leave()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_leave_guardian_students())
  );

/*
 * เจ้าของแก้ได้เฉพาะใบของตัวเอง และ trigger กันไม่ให้ตั้งสถานะเป็น approved
 * — นโยบายบอกว่า "แถวไหนแตะได้" ส่วน trigger บอกว่า "แตะแล้วกลายเป็นอะไรได้"
 * แยกกันเพราะ RLS เทียบค่าในแถวเดียวไม่ได้ว่าเปลี่ยนจากอะไรเป็นอะไร
 */
create policy leave_update on student_leave
  as restrictive for update
  using (
    may_decide_student_leave()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_leave_guardian_students())
  )
  with check (
    may_decide_student_leave()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_leave_guardian_students())
  );

-- ใบลาที่ยื่นแล้วต้องไม่หายไปจากระบบ — ยกเลิกได้ ลบไม่ได้
-- (นโยบายนี้มีไว้ให้งานล้างข้อมูลของผู้ดูแลทำได้ ถ้าไม่มีเลยจะลบไม่ได้สักแถว
--  เพราะ force row level security มีผลกับเจ้าของตารางด้วย)
create policy leave_delete on student_leave
  as restrictive for delete using (current_app_role() = 'admin');

-- ─── student_leave_applied ─────────────────────────────────────────
alter table student_leave_applied enable row level security;
alter table student_leave_applied force row level security;

/*
 * ตารางนี้ไม่มี institution_id ของตัวเอง จึงเทียบผ่านใบลาแม่
 * **RLS ไม่ถ่ายทอดผ่านคีย์นอก** — ถ้าไม่เขียนนโยบายนี้ ตารางจะเปิดโล่ง
 */
create policy tenant_isolation on student_leave_applied
  using (exists (select 1 from student_leave sl
                  where sl.id = student_leave_applied.leave_id
                    and sl.institution_id = current_institution_id()));

create policy applied_write on student_leave_applied
  as restrictive for insert with check (may_decide_student_leave());

create policy applied_delete on student_leave_applied
  as restrictive for delete using (may_decide_student_leave());

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0055_student_letters.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0055 — หนังสือถึงผู้ปกครองและใบรับรองความประพฤติ
--
-- สามใบที่งานปกครองต้องออกจริงทุกภาคเรียนและระบบยังไม่มีเลย
--   · จดหมายแจ้งขาดเรียน       — เตือนก่อนหมดสิทธิ์สอบตามกฎ 80%
--   · หนังสือเชิญผู้ปกครอง      — นัดพบพร้อมวันเวลาและสถานที่
--   · ใบรับรองความประพฤติ      — นักศึกษาขอไปใช้สมัครงาน/เรียนต่อ
--
-- ═══ ทำไมสามใบนี้ต้องเป็น `issued_document` ไม่ใช่พิมพ์สด ═══
-- จดหมายแจ้งขาดเรียนอ้าง**ตัวเลขเวลาเรียน ณ วันที่ออก** ถ้าพิมพ์ซ้ำเดือนหน้า
-- แล้วอ่านค่าใหม่ ตัวเลขบนกระดาษที่ผู้ปกครองถืออยู่กับที่ระบบพิมพ์ใหม่จะไม่ตรงกัน
-- แล้วเถียงกันไม่จบว่าใครถูก — หลักข้อ 5 เรื่องค่าที่ตรึงไว้ห้ามคำนวณใหม่
-- ส่วนใบรับรองความประพฤติเป็นเอกสารที่นักศึกษาเอาไปยื่นให้คนอื่น ต้องตรวจ
-- ย้อนหลังได้ว่าวิทยาลัยออกให้จริงเมื่อไรและเลขที่เท่าไร
--
-- ═══ ทำไมไม่ใช้ `issue_document()` ตัวเดิม ═══
-- payload ของสามใบนี้ **ไม่ควรมี** สิ่งที่ใบเดิมมีทุกใบ คือ `graduation`
-- กับ `summary` (หน่วยกิตสะสมและ GPAX) เพราะจดหมายแจ้งขาดเรียนไม่ได้แสดง
-- เกรดเฉลี่ยของนักศึกษาสักตัว การคัดลอกลงไปคือการเก็บข้อมูลเกินจำเป็น
-- ในที่ที่ลบไม่ได้ (หลักข้อ 5ก · PDPA ม.22) — และในทางกลับกัน สามใบนี้
-- **ต้องมี**ชื่อและที่อยู่ผู้ปกครอง ซึ่งใบ รบ. ไม่มีสิทธิ์มี เพราะไม่ได้แสดง
-- จึงเป็นคนละชุดข้อมูลกันจริง ๆ ไม่ใช่ชุดเดียวกันที่ตัดบางส่วนออก
--
-- ═══ ทำไมนัดพบต้องส่งเข้ามา ไม่ใช่ให้ระบบเดา ═══
-- วันเวลาและสถานที่นัดพบเป็นข้อมูลที่มีอยู่ในหัวของคนออกหนังสือเท่านั้น
-- ถ้าปล่อยให้ว่างแล้วเติมด้วยปากกาทีหลัง จะไม่มีหลักฐานว่าเคยนัดวันไหน
-- เมื่อผู้ปกครองบอกว่าไม่เคยได้รับแจ้ง
--
-- ═══ ทำไมใบรับรองความประพฤติอ่านจาก `v_behavior_balance` ═══
-- `behavior_record.points` เป็นบวกเสมอ ทิศทางหัก/เพิ่มอยู่ที่
-- `behavior_rule.direction` การรวมยอดโดยดูเครื่องหมายของตัวเลขจะได้ผลผิด
-- แบบดูไม่ออก — หนีเรียนกลายเป็นได้คะแนนเพิ่ม แล้ววิทยาลัยจะออกใบรับรอง
-- ความประพฤติให้คนที่ไม่ควรได้ โดยมีลายเซ็นผู้อำนวยการอยู่บนนั้น
-- ═══════════════════════════════════════════════════════════════════

begin;

alter type document_kind add value if not exists 'absence_notice';
alter type document_kind add value if not exists 'guardian_invitation';
alter type document_kind add value if not exists 'conduct_certificate';

comment on type document_kind is
  'ประเภทเอกสารที่วิทยาลัยออกให้ — transcript รบ. · certificate ใบประกาศนียบัตร · certification ใบรับรอง · grade_report สมุดพก · cumulative_record ระเบียนสะสม (ปพ.8) · absence_notice จดหมายแจ้งขาดเรียน · guardian_invitation หนังสือเชิญผู้ปกครอง · conduct_certificate ใบรับรองความประพฤติ';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- PostgreSQL ห้ามใช้ค่า enum ใหม่ในทรานแซกชันเดียวกับที่เพิ่มมัน
-- จึงต้องแยกทรานแซกชัน (กับดักเดียวกับที่ 0026 เจอกับ 'bridging'
-- และ 0029 เจอกับ 'cumulative_record')
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ส่วนหัวที่หนังสือถึงผู้ปกครองทุกใบต้องมี
 *
 * ต่างจากส่วนหัวของ `issue_document()` สองอย่างที่สำคัญ
 *   · ไม่มี graduation/summary — จดหมายแจ้งขาดเรียนไม่ได้แสดง GPAX
 *   · **มี**ผู้ปกครองและที่อยู่ — เพราะหัวจดหมายต้องขึ้นว่า "เรียน ..."
 *     และซองต้องมีที่อยู่ ซึ่งใบ รบ. ไม่มีสิทธิ์เก็บเพราะไม่ได้แสดง
 */
create or replace function letter_header(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code', s.student_code,
                     'full_name_th', trim(coalesce(p.prefix_th, '')
                                       || coalesce(p.first_name_th, '')
                                       || ' ' || coalesce(p.last_name_th, '')),
                     'class_number', s.class_number,
                     'status',       s.status),
    'class',       (select jsonb_build_object(
                             'study_year', scp.study_year,
                             'group_code', coalesce(scp.group_code, ''),
                             'year_be',    ay.year_be)
                      from student_class_placement scp
                      join academic_year ay on ay.id = scp.academic_year_id
                     where scp.student_id = p_student_id
                     order by ay.year_be desc limit 1),
    'program',     (select jsonb_build_object(
                             'name_th', pr.name_th,
                             'level',   pr.level,
                             'abbr_th', case pr.level
                                          when 'PVC' then 'ปวช.'
                                          when 'PVS' then 'ปวส.'
                                          when 'TVB' then 'ทล.บ.'
                                        end)
                      from student_curriculum sc
                      join curriculum_version cv on cv.id = sc.curriculum_version_id
                      join curriculum cur        on cur.id = cv.curriculum_id
                      join program_track ptr     on ptr.id = cur.program_track_id
                      join program pr            on pr.id  = ptr.program_id
                     where sc.student_id = p_student_id
                       and (sc.effective_to is null or sc.effective_to >= current_date)
                     order by sc.effective_from desc nulls last limit 1),
    -- ครูที่ปรึกษาเป็นผู้ลงนามของจดหมายสองใบแรกตามธรรมเนียม
    'advisor',     (select jsonb_build_object(
                             'name_th', trim(coalesce(ap.prefix_th, '')
                                          || coalesce(ap.first_name_th, '')
                                          || ' ' || coalesce(ap.last_name_th, '')))
                      from student_advisor sa
                      join staff ast  on ast.id = sa.staff_id
                      join person ap  on ap.id  = ast.person_id
                     where sa.student_id = p_student_id and sa.ended_on is null
                     order by sa.is_primary desc limit 1),
    /*
     * ผู้ปกครองมาจากสองที่ที่ต่างกันโดยสิ้นเชิง
     *   · `student_parent` (0053) คือบิดามารดาตามระเบียน ซึ่งส่วนใหญ่
     *     ไม่ได้เป็นผู้ใช้ระบบ — เป็นชื่อที่จ่าหน้าซองจริง
     *   · `student_guardian` คือผู้ปกครองที่มีบัญชีเข้าระบบ ซึ่งอาจไม่ใช่
     *     คนเดียวกันและอาจไม่มีเลย
     * หนังสือต้องส่งถึงคนที่อยู่ในระเบียน จึงเอาจาก student_parent ก่อน
     */
    'recipients',  coalesce((
                     select jsonb_agg(jsonb_build_object(
                              'role',      sp.role,
                              'name_th',   trim(coalesce(sp.prefix_th, '')
                                             || sp.first_name_th
                                             || ' ' || coalesce(sp.last_name_th, '')),
                              'phone',     coalesce(sp.phone, ''),
                              'address_th', trim(coalesce(sp.address_line, '')
                                             || case when sp.subdistrict_th is not null
                                                     then ' ต.' || sp.subdistrict_th else '' end
                                             || case when sp.district_th is not null
                                                     then ' อ.' || sp.district_th else '' end
                                             || case when sp.province_th is not null
                                                     then ' จ.' || sp.province_th else '' end
                                             || ' ' || coalesce(sp.postal_code, '')))
                              order by sp.role)
                       from student_parent sp
                      where sp.student_id = p_student_id
                        and sp.status <> 'deceased'), '[]'::jsonb))
    from student s
    join person p      on p.id = s.person_id
    join institution i on i.id = s.institution_id
   where s.id = p_student_id
$$;

comment on function letter_header(uuid) is
  'ส่วนหัวของหนังสือถึงผู้ปกครอง — มีผู้รับและที่อยู่ ซึ่งใบ รบ. ไม่มีสิทธิ์เก็บ และไม่มี GPAX ซึ่งจดหมายไม่ได้แสดง';

-- ───────────────────────────────────────────────────────────────────
-- ออกหนังสือ
--
-- ไม่ใช่ security definer — ผู้เรียกต้องอ่านข้อมูลนักศึกษาและเวลาเรียน
-- ได้เองตามนโยบายของตัวเองอยู่แล้ว ถ้าอ่านไม่ได้ก็ไม่ควรออกหนังสือถึง
-- ผู้ปกครองของคนนั้น
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_student_letter(
  p_student_id uuid,
  p_kind       document_kind,
  p_term_id    uuid  default null,
  p_context    jsonb default '{}'::jsonb
) returns issued_document
language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
begin
  if v_kind not in ('absence_notice', 'guardian_invitation', 'conduct_certificate') then
    raise exception 'ฟังก์ชันนี้ออกได้เฉพาะหนังสือถึงผู้ปกครองและใบรับรองความประพฤติ — ใบอื่นใช้ issue_document()'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ หรือไม่มีสิทธิ์เข้าถึง';
  end if;

  -- จดหมายแจ้งขาดเรียนไม่มีความหมายถ้าไม่รู้ว่าภาคไหน เพราะตัวเลขเวลาเรียน
  -- เป็นของภาคเรียนหนึ่ง ๆ เสมอ
  if v_kind = 'absence_notice' and p_term_id is null then
    raise exception 'ออกจดหมายแจ้งขาดเรียนต้องระบุภาคเรียน มิฉะนั้นตัวเลขเวลาเรียนจะเป็นของภาคที่ผู้ออกไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;

  if v_kind = 'guardian_invitation'
     and coalesce(btrim(p_context ->> 'meet_on'), '') = '' then
    raise exception 'หนังสือเชิญผู้ปกครองต้องระบุวันนัดพบ — ถ้าเว้นไว้เติมด้วยปากกาทีหลัง จะไม่มีหลักฐานว่าเคยนัดวันไหน'
      using errcode = 'check_violation';
  end if;

  v_year := coalesce(
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint);

  v_doc_no := next_document_no(p_kind, v_year);

  v_payload := letter_header(p_student_id) || jsonb_build_object(
    'kind',      v_kind,
    'issued_at', now(),
    'year_be',   v_year,
    'issued_by', (select trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                            || ' ' || coalesce(p.last_name_th, ''))
                    from person p where p.id = current_actor_id()),
    'note',      coalesce(p_context ->> 'note', ''));

  -- ── จดหมายแจ้งขาดเรียน ───────────────────────────────────────────
  if v_kind = 'absence_notice' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be)
           from term t join academic_year ay on ay.id = t.academic_year_id
          where t.id = p_term_id),
      /*
       * ตัวเลขทั้งหมดตรึง ณ วันที่ออก — พิมพ์ซ้ำต้องได้ใบเดิมเป๊ะ
       * `pct_projected` สำคัญกว่า `pct_to_date` เพราะเป็นตัวที่บอกว่า
       * "ถ้าขาดต่อแบบนี้จะจบภาคที่เท่าไร" ซึ่งคือเหตุผลที่ต้องส่งจดหมาย
       */
      'courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'code',            c.code,
                           'name_th',         c.name_th,
                           'section_no',      cs.section_no,
                           'pct_to_date',     v.pct_to_date,
                           'pct_projected',   v.pct_projected,
                           'absences_left',   v.absences_left,
                           'min_pct',         v.min_pct,
                           'state',           v.attendance_state,
                           'teacher_th',      trim(coalesce(tp.prefix_th, '')
                                                || coalesce(tp.first_name_th, '')
                                                || ' ' || coalesce(tp.last_name_th, '')))
                           order by v.pct_projected)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join staff tst on tst.id = cs.teacher_id
                    left join person tp on tp.id  = tst.person_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'
                     -- ใส่เฉพาะวิชาที่มีปัญหาจริง — จดหมายที่ลอกทุกวิชา
                     -- ลงไปทำให้ผู้ปกครองหาไม่เจอว่าต้องดูตรงไหน
                     and v.attendance_state <> 'ok'), '[]'::jsonb));

    if v_payload -> 'courses' = '[]'::jsonb then
      raise exception 'ออกจดหมายแจ้งขาดเรียนไม่ได้ — นักศึกษารายนี้ไม่มีวิชาที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคเรียนนี้'
        using errcode = 'check_violation';
    end if;
  end if;

  -- ── หนังสือเชิญผู้ปกครอง ─────────────────────────────────────────
  if v_kind = 'guardian_invitation' then
    v_payload := v_payload || jsonb_build_object(
      'meeting', jsonb_build_object(
                   'meet_on',   p_context ->> 'meet_on',
                   'meet_time', coalesce(p_context ->> 'meet_time', ''),
                   'place_th',  coalesce(p_context ->> 'place_th', ''),
                   'with_th',   coalesce(p_context ->> 'with_th', '')),
      'reason_th', coalesce(p_context ->> 'reason_th', ''));
  end if;

  -- ── ใบรับรองความประพฤติ ──────────────────────────────────────────
  if v_kind = 'conduct_certificate' then
    v_payload := v_payload || jsonb_build_object(
      /*
       * อ่านยอดคงเหลือจาก view ไม่รวมเอง เพราะ `behavior_record.points`
       * เป็นบวกทั้งสองทิศทาง — ทิศทางอยู่ที่ `behavior_rule.direction`
       * การ sum เครื่องหมายเองจะได้ผลผิดแบบดูไม่ออก (หนีเรียนกลายเป็น
       * ได้คะแนนเพิ่ม) แล้ววิทยาลัยจะออกใบรับรองความประพฤติให้คนที่
       * ไม่ควรได้ โดยมีลายเซ็นผู้อำนวยการอยู่บนนั้น
       *
       * จำนวนครั้งที่ถูกหักนับแยกไว้ด้วย เพราะ "คะแนนเต็มแต่เคยถูกหัก
       * แล้วทำกิจกรรมชดเชยจนกลับมาเต็ม" กับ "ไม่เคยมีประวัติเลย" คนละเรื่องกัน
       * และเป็นสิ่งที่คนอ่านใบรับรองอยากรู้
       */
      'behavior',
        jsonb_build_object(
          'balance',
            (select b.balance from v_behavior_balance b where b.student_id = p_student_id),
          'deduct_count',
            (select count(*) from behavior_record br
               join behavior_rule r on r.id = br.rule_id
              where br.student_id = p_student_id and r.direction = 'deduct'),
          'award_count',
            (select count(*) from behavior_record br
               join behavior_rule r on r.id = br.rule_id
              where br.student_id = p_student_id and r.direction = 'award')),
      'purpose_th',  coalesce(p_context ->> 'purpose_th', ''),
      'admitted_on', (select s.admitted_year_be from student s where s.id = p_student_id));
  end if;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_student_letter(uuid, document_kind, uuid, jsonb) is
  'ออกหนังสือถึงผู้ปกครองและใบรับรองความประพฤติ — ตัวเลขเวลาเรียนและคะแนนความประพฤติตรึง ณ วันที่ออก พิมพ์ซ้ำต้องได้ใบเดิม';

/*
 * รายชื่อผู้ที่ควรได้รับจดหมายแจ้งขาดเรียน
 *
 * มีไว้ให้หน้าจอไม่ต้องเดาว่าจะออกให้ใคร — งานปกครองเปิดมาแล้วเห็นเลยว่า
 * ภาคเรียนนี้มีใครตกเกณฑ์บ้าง และใครได้รับจดหมายไปแล้ว
 * `last_notice_on` เป็น null แปลว่ายังไม่เคยส่ง ไม่ใช่ส่งแล้วไม่ได้ผล
 */
create or replace function absence_notice_candidates(p_term_id uuid)
returns table (
  student_id      uuid,
  student_code    text,
  full_name       text,
  courses_at_risk integer,
  worst_pct       numeric,
  last_notice_on  date
) language sql stable as $$
  select s.id, s.student_code,
         trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
              || ' ' || coalesce(p.last_name_th, '')),
         count(*)::integer,
         min(v.pct_projected),
         (select max(d.issued_on) from issued_document d
           where d.student_id = s.id
             and d.kind = 'absence_notice'
             and d.voided_at is null)
    from enrollment e
    join student s on s.id = e.student_id
    join person  p on p.id = s.person_id
    join v_enrollment_attendance v on v.enrollment_id = e.id
   where e.term_id = p_term_id
     and e.status = 'enrolled'
     and v.attendance_state <> 'ok'
   group by s.id, s.student_code, p.prefix_th, p.first_name_th, p.last_name_th
   order by min(v.pct_projected)
$$;

comment on function absence_notice_candidates(uuid) is
  'ผู้ที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคเรียนที่ระบุ พร้อมวันที่เคยออกจดหมายล่าสุด — null แปลว่ายังไม่เคยส่ง';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0056_behavior_write_scope.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0056 — ปิดช่องเขียนคะแนนความประพฤติ
--
-- ═══ ยิงจริงแล้วนักศึกษาทำได้ทั้งสามอย่างนี้ที่ชั้นฐานข้อมูล ═══
--   · `insert into behavior_record` ให้คะแนนความดีตัวเอง 50 คะแนน
--     (ยอดจาก 100 เป็น 150 ทันที)
--   · `update behavior_record set points = 0` ล้างคะแนนที่ถูกหักทิ้ง
--   · `delete from behavior_record` ลบประวัติการถูกหักของตัวเองทั้งหมด
--     (ทดสอบจริง — ลบได้ 3 แถว ยอดจาก 90 กลับเป็น 100)
--   · และ `insert into behavior_rule` สร้างกฎ "ให้คะแนน 999" ของตัวเองได้ด้วย
--
-- ต้นเหตุคือสองตารางนี้มีแต่นโยบาย `tenant_isolation` ล้วน ไม่มีนโยบาย
-- restrictive ที่จำกัดว่าใครเขียนได้ — เป็นรูปเดียวกับข้อ 10, 11 และ 13
-- ทุกประการ คือช่องที่**ข้าม API ไปเลย** ซึ่งอ่านโค้ดฝั่ง API ไม่มีวันเห็น
-- (ยิ่งกว่านั้นคือ ณ วันที่เขียนไฟล์นี้ **ไม่มี endpoint ไหนแตะตารางนี้เลย
--  สักตัว** การอ่านโค้ดจึงให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้ามกับ
--  ความจริงโดยสิ้นเชิง)
--
-- ═══ ทำไมเรื่องนี้หนักกว่าที่เห็น ═══
-- 0055 เพิ่ง**ออกใบรับรองความประพฤติ**ที่อ่านยอดจาก `v_behavior_balance`
-- ซึ่งรวมมาจากตารางนี้ นักศึกษาที่ลบประวัติตัวเองแล้วไปขอใบรับรอง จะได้
-- กระดาษที่เขียนว่า "ไม่ปรากฏประวัติการถูกตัดคะแนนความประพฤติ" พร้อม
-- ช่องลงนามผู้อำนวยการ — วิทยาลัยรับรองสิ่งที่ไม่จริงโดยไม่มีใครรู้
--
-- ═══ ทำไมครูต้องเขียนได้ แต่แก้ไม่ได้ ═══
-- การบันทึกพฤติกรรมเป็นงานของครูผู้สอนและครูที่ปรึกษาที่เห็นเหตุการณ์
-- ถ้าเปิดให้เฉพาะงานปกครอง ทุกเรื่องต้องเดินไปบอกด้วยปากแล้วให้คนอื่นพิมพ์
-- ซึ่งแปลว่าจะไม่มีใครบันทึก แต่การ**แก้หรือลบ**สิ่งที่บันทึกไปแล้วเป็น
-- คนละเรื่อง — เป็นการเปลี่ยนหลักฐาน จึงเหลือเฉพาะงานปกครองและผู้บริหาร
--
-- ═══ ทำไม student_id กับ rule_id แก้ไม่ได้ ═══
-- การย้ายบันทึกไปให้นักศึกษาอีกคน หรือเปลี่ยนกฎที่อ้างถึง ไม่ใช่การแก้คำผิด
-- แต่เป็นการเขียนประวัติใหม่โดยที่เลขที่และวันที่ยังเป็นของเดิม ถ้าบันทึกผิดคน
-- ต้องลบแล้วบันทึกใหม่ ซึ่งเห็นได้จากภายนอกว่ามีการลบเกิดขึ้น
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ครูผู้สอนของนักศึกษาคนนั้นในภาคเรียนที่ยังเปิดอยู่
--
-- security definer เพราะอ่าน `enrollment` และ `class_section` ซึ่งมี RLS
-- ของตัวเอง — ครูที่ยังไม่เห็นแถวจะตรวจไม่ผ่านทั้งที่สิทธิ์ถูกต้อง
-- (กับดักเดียวกับ `student_institution()` ใน 0012 และ `may_see_sensitive()`
--  ใน 0053)
-- ───────────────────────────────────────────────────────────────────
create or replace function actor_taught_student_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select distinct e.student_id
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join staff st on st.id = cs.teacher_id
   where st.person_id = current_actor_id()
     and e.status = 'enrolled'
$$;

comment on function actor_taught_student_ids() is
  'นักศึกษาที่ผู้ใช้ปัจจุบันเป็นครูผู้สอนอยู่ — ใช้จำกัดขอบเขตการบันทึกพฤติกรรม';

/* บทบาทที่บันทึกพฤติกรรมได้ — ครูรวมอยู่ด้วยโดยตั้งใจ */
create or replace function may_record_behavior()
returns boolean language sql stable as $$
  select current_app_role() in
    ('teacher', 'student_affairs', 'registrar', 'academic', 'director', 'admin')
$$;

/* บทบาทที่**แก้หรือลบ**บันทึกได้ — แคบกว่ามาก เพราะเป็นการเปลี่ยนหลักฐาน */
create or replace function may_amend_behavior()
returns boolean language sql stable as $$
  select current_app_role() in ('student_affairs', 'director', 'admin')
$$;

-- ═══ behavior_rule ═════════════════════════════════════════════════
alter table behavior_rule enable row level security;
alter table behavior_rule force row level security;

/*
 * อ่านได้ทั้งวิทยาลัย — ครูต้องเลือกกฎตอนบันทึก และนักศึกษาควรรู้ว่า
 * ทำอะไรแล้วถูกหักกี่คะแนน (กฎที่ไม่มีใครรู้ล่วงหน้าไม่ใช่กฎ)
 * ไม่ต้องมีนโยบาย select แยก เพราะ tenant_isolation เปิดอ่านให้แล้ว
 */
create policy behavior_rule_insert on behavior_rule
  as restrictive for insert with check (may_amend_behavior());

create policy behavior_rule_update on behavior_rule
  as restrictive for update
  using (may_amend_behavior()) with check (may_amend_behavior());

create policy behavior_rule_delete on behavior_rule
  as restrictive for delete using (may_amend_behavior());

comment on policy behavior_rule_insert on behavior_rule is
  'ยิงจริงแล้วนักศึกษาสร้างกฎ "ให้คะแนนตัวเอง 999" ได้ ก่อนมีนโยบายนี้';

-- ═══ behavior_record ═══════════════════════════════════════════════
alter table behavior_record enable row level security;
alter table behavior_record force row level security;

/*
 * ─── ต้องแยกเป็น for select / insert / update / delete ───
 * นโยบาย restrictive แบบ `for all` กิน select ด้วย ซึ่งจะทำให้เงื่อนไข
 * "ต้องเป็นเจ้าหน้าที่ถึงจะเขียนได้" กลายเป็น "ถึงจะอ่านได้" แล้วนักศึกษา
 * จะดูคะแนนของตัวเองไม่ได้เลย (บทเรียนจาก 0053)
 */
create policy behavior_read on behavior_record
  as restrictive for select using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())     -- เจ้าตัวและผู้ปกครอง
    or student_id in (select actor_advisee_ids())     -- ครูที่ปรึกษา
    or student_id in (select actor_taught_student_ids())  -- ครูผู้สอน
  );

/*
 * ครูบันทึกได้เฉพาะนักศึกษาที่ตัวเองสอนหรือเป็นที่ปรึกษาอยู่
 * — ครูคนหนึ่งไม่ควรหักคะแนนนักศึกษาที่ไม่เคยเจอ
 * ส่วนบทบาทระดับวิทยาลัยบันทึกได้ทั้งหมด เพราะงานปกครองรับเรื่องจากทุกทาง
 */
create policy behavior_insert on behavior_record
  as restrictive for insert with check (
    is_institution_wide_role()
    or (may_record_behavior()
        and (student_id in (select actor_taught_student_ids())
             or student_id in (select actor_advisee_ids())))
  );

create policy behavior_update on behavior_record
  as restrictive for update
  using (may_amend_behavior()) with check (may_amend_behavior());

create policy behavior_delete on behavior_record
  as restrictive for delete using (may_amend_behavior());

comment on policy behavior_read on behavior_record is
  'เจ้าตัว ผู้ปกครอง ครูที่ปรึกษา ครูผู้สอน และบทบาทระดับวิทยาลัยอ่านได้ — เขียนคนละเรื่อง ดูนโยบาย insert/update/delete';

/*
 * ─── ทำไมต้องมี trigger ทั้งที่มีนโยบายแล้ว ───
 * นโยบาย RLS เทียบได้แค่ "แถวนี้แตะได้ไหม" แต่เทียบไม่ได้ว่า "เปลี่ยนจาก
 * อะไรเป็นอะไร" การห้ามย้ายบันทึกไปให้นักศึกษาอีกคนจึงต้องใช้ trigger
 * — เรื่องเดียวกับที่ `grade_submission` ใน 0049 ต้องใช้ trigger ไม่ใช่นโยบาย
 */
create or replace function behavior_record_guard() returns trigger
language plpgsql as $$
begin
  -- ปล่อยผ่านเมื่อไม่มีบริบทผู้ใช้ (superuser ตอนย้ายข้อมูลหรือ seed)
  -- บริบทที่ไม่มี app.role ก็ไม่มี app.institution_id นโยบายจึงปฏิเสธ
  -- ทุกแถวอยู่แล้ว การปล่อยผ่านตรงนี้ไม่เปิดช่องให้ใคร (หลักเดียวกับ 0042)
  if current_app_role() = 'none' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- ผู้บันทึกต้องเป็นคนที่กดจริง ไม่ใช่ชื่อที่ส่งมากับข้อมูล
    -- มิฉะนั้นครูจะบันทึกในนามคนอื่นได้ แล้วหลักฐานจะชี้ผิดคน (บทเรียนข้อ 5)
    if new.recorded_by is distinct from current_actor_id() then
      raise exception 'ผู้บันทึกพฤติกรรมต้องเป็นผู้ใช้ที่กำลังทำรายการ';
    end if;
    return new;
  end if;

  if new.student_id <> old.student_id then
    raise exception 'ย้ายบันทึกพฤติกรรมไปให้นักศึกษาคนอื่นไม่ได้ — ถ้าบันทึกผิดคนต้องลบแล้วบันทึกใหม่';
  end if;
  if new.rule_id is distinct from old.rule_id then
    raise exception 'เปลี่ยนกฎที่บันทึกอ้างถึงไม่ได้ — ถ้าเลือกผิดข้อต้องลบแล้วบันทึกใหม่';
  end if;
  if new.recorded_by is distinct from old.recorded_by then
    raise exception 'เปลี่ยนผู้บันทึกไม่ได้';
  end if;

  return new;
end $$;

drop trigger if exists behavior_record_guard on behavior_record;
create trigger behavior_record_guard
  before insert or update on behavior_record
  for each row execute function behavior_record_guard();

commit;

-- ═══════════════════════════════════════════════════════════════════
-- มุมมองที่หน้าจอต้องใช้
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ยอดคะแนนพร้อมระดับเตือน — `v_behavior_balance` บอกแค่ตัวเลข
 * แต่ตัวเลขเปล่า ๆ ตอบไม่ได้ว่า "แล้วยังไง" เกณฑ์อยู่ใน `behavior_policy`
 * ซึ่งถ้าให้หน้าจออ่านเองแล้วเทียบเอง จะกลายเป็นกฎชุดที่สองที่ค่อย ๆ
 * เพี้ยนไปจากของจริง
 */
create or replace view v_behavior_status with (security_invoker = true) as
  select b.student_id,
         b.institution_id,
         b.balance,
         coalesce(bp.starting_points, 100)  as starting_points,
         coalesce(bp.warn_below, 70)        as warn_below,
         coalesce(bp.critical_below, 50)    as critical_below,
         case
           when b.balance < coalesce(bp.critical_below, 50) then 'critical'
           when b.balance < coalesce(bp.warn_below, 70)     then 'warn'
           else 'ok'
         end as band,
         (select count(*) from behavior_record br
            join behavior_rule r on r.id = br.rule_id
           where br.student_id = b.student_id and r.direction = 'deduct') as deduct_count,
         (select count(*) from behavior_record br
            join behavior_rule r on r.id = br.rule_id
           where br.student_id = b.student_id and r.direction = 'award')  as award_count,
         (select max(br.occurred_on) from behavior_record br
           where br.student_id = b.student_id) as last_record_on
    from v_behavior_balance b
    left join behavior_policy bp on bp.institution_id = b.institution_id;

comment on view v_behavior_status is
  'ยอดคะแนนความประพฤติพร้อมระดับเตือนตาม behavior_policy — หน้าจอห้ามเทียบเกณฑ์เอง มิฉะนั้นจะกลายเป็นกฎชุดที่สอง';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0057_bilingual_documents.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0057 — ที่เก็บของข้อมูลที่ใบ รบ. ภาษาอังกฤษต้องใช้
--
-- ═══ ทำไมต้องทำตอนนี้ ทั้งที่ยังไม่ได้ทำแม่แบบทั้ง 16 รูปแบบ ═══
-- `issued_document.payload` **แก้ไม่ได้** ใบที่ออกไปแล้วจะไม่มีวันมีข้อความ
-- ภาษาอังกฤษ ต่อให้เพิ่มแม่แบบทีหลังก็ต้องออกใบใหม่ทั้งหมด
-- ข้อมูลที่ไม่ได้เก็บวันนี้ จึงเท่ากับใบที่ต้องออกใหม่ในวันที่รู้รูปแบบ
--
-- แม่แบบเป็นโค้ด แก้เมื่อไรก็ได้ · ที่เก็บข้อมูลเป็นสคีมา ยิ่งช้ายิ่งแพง
-- ไฟล์นี้จึงทำเฉพาะฝั่งที่แพงถ้าช้า และไม่แตะรูปแบบการวางหน้าเลยสักบรรทัด
--
-- ═══ ตรวจแล้วว่าอะไรมีอยู่แล้ว อะไรยังไม่มี ═══
-- มีแล้ว — `person.first_name_en/last_name_en/prefix_en` ·
--   `institution.name_en` · `course.name_en` · `program.name_en`
--   และ `student_status` ครบทุกสาเหตุที่ SISA มี (withdrawn = ลาออก ·
--   dismissed = จำหน่าย · transferred_out = ศึกษาต่อที่อื่น) พร้อมวันที่
--   ใน `student_status_history.effective_on`
-- ยังไม่มี — สามอย่างที่ใบ รบ. พิมพ์จริงทุกใบ (ประเภทวิชา · สาขางาน ·
--   ชื่อหลักสูตร) ไม่มีช่องภาษาอังกฤษเลย · เลขที่ฉบับอังกฤษเป็นคนละสาย ·
--   ผลมาตรฐานวิชาชีพ (มีแต่เลขที่ ไม่มีว่าผ่านหรือไม่) · หมายเหตุภาษาอังกฤษ ·
--   เกณฑ์การสำเร็จการศึกษาห้าบรรทัดที่พิมพ์ท้ายใบ ซึ่งไม่มีที่เก็บทั้งสองภาษา
--
-- ═══ ทำไมฉบับอังกฤษต้องเป็นเอกสารคนละใบ ไม่ใช่แม่แบบอีกแบบของใบเดิม ═══
-- SISA เก็บเลขที่ไว้คนละช่อง (`eng_mass_transcript_no`) ซึ่งแปลว่ามันเป็น
-- เอกสารคนละฉบับในสายตาของงานทะเบียน ไม่ใช่การพิมพ์ใบเดิมด้วยฟอนต์อื่น
-- และเมื่อเป็นคนละฉบับ payload ก็ต้องแยก — ใบภาษาอังกฤษแสดงภาษาอังกฤษ
-- ไม่ใช่แสดงทั้งสองภาษาซ้อนกันในใบเดียว (หลักข้อ 5ก)
--
-- ═══ ทำไมออกใบอังกฤษไม่ได้ถ้าข้อมูลอังกฤษไม่ครบ ═══
-- ถ้าปล่อยให้ออกโดยเติมภาษาไทยแทนช่องที่ว่าง จะได้ใบที่หัวเป็นอังกฤษแต่
-- ชื่อสาขาเป็นไทย ซึ่งเป็นเอกสารทางการที่ดูเหมือนระบบพัง และ**แก้ไม่ได้
-- อีกเลยเพราะ payload ตรึงแล้ว** — ล้มตั้งแต่ตอนกดดีกว่าออกใบที่ใช้ไม่ได้
-- (หลักข้อ 6) ข้อความผิดพลาดบอกชื่อสิ่งที่ยังไม่ได้กรอกเป็นรายการ
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ชื่อภาษาอังกฤษของสิ่งที่ใบ รบ. พิมพ์ทุกใบ
-- ───────────────────────────────────────────────────────────────────
alter table program_type add column if not exists name_en text;
alter table program_track add column if not exists name_en text;
alter table curriculum  add column if not exists name_en text;

comment on column program_type.name_en is
  'ประเภทวิชาภาษาอังกฤษ — ใบ รบ. ฉบับอังกฤษพิมพ์ช่องนี้ ว่างแล้วออกใบไม่ได้';
comment on column program_track.name_en is
  'สาขางานภาษาอังกฤษ — ใบ รบ. ฉบับอังกฤษพิมพ์ช่องนี้ ว่างแล้วออกใบไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- ข้อมูลผู้สำเร็จการศึกษาที่ใบ รบ. ใช้แต่ยังไม่มีที่เก็บ
-- ───────────────────────────────────────────────────────────────────
alter table student_graduation
  add column if not exists transcript_no_en text,
  add column if not exists note_en          text,
  /*
   * แยก "ผ่านหรือไม่" ออกจาก "เลขที่" เพราะเดิมมีแต่ `professional_standard_no`
   * ซึ่งตอบไม่ได้ว่าคนที่ยังไม่มีเลขคือ **ยังไม่ได้สอบ** หรือ **สอบแล้วไม่ผ่าน**
   * — สองอย่างนี้ต้องพิมพ์บนใบต่างกัน และมีผลต่อการสมัครงานคนละแบบ
   */
  add column if not exists professional_standard_passed boolean,
  add column if not exists professional_standard_on     date;

create unique index if not exists student_graduation_transcript_no_en_uniq
  on student_graduation (institution_id, transcript_no_en)
  where transcript_no_en is not null;

comment on column student_graduation.professional_standard_passed is
  'null = ยังไม่ได้เข้ารับการประเมิน · false = ประเมินแล้วไม่ผ่าน — คนละความหมายกัน ห้ามยุบเป็นค่าเดียว';

-- ───────────────────────────────────────────────────────────────────
-- สายเลขที่แยกตามภาษา
--
-- เดิม primary key เป็น (institution, kind, year) ซึ่งแปลว่าใบไทยกับใบอังกฤษ
-- ใช้เลขสายเดียวกัน — ผิดจากที่งานทะเบียนใช้จริง และแก้ทีหลังไม่ได้เพราะ
-- เลขที่ออกไปแล้วอยู่บนกระดาษของคนอื่น
-- ───────────────────────────────────────────────────────────────────
alter table document_series
  add column if not exists lang text not null default 'th'
    check (lang in ('th', 'en'));

do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'document_series_pkey'
                and conrelid = 'document_series'::regclass)
     and (select count(*) from pg_index i
           where i.indrelid = 'document_series'::regclass
             and i.indisprimary
             and i.indnatts = 3) = 1
  then
    alter table document_series drop constraint document_series_pkey;
    alter table document_series
      add constraint document_series_pkey
      primary key (institution_id, kind, year_be, lang);
  end if;
end $$;

comment on column document_series.lang is
  'ภาษาของสายเลขที่ — ฉบับภาษาอังกฤษเป็นเอกสารคนละฉบับในสายตางานทะเบียน จึงเดินเลขคนละสาย (ตรงกับ eng_mass_transcript_no ของ SISA)';

-- ───────────────────────────────────────────────────────────────────
-- ข้อความประจำสถานศึกษาที่พิมพ์ท้ายใบ
--
-- เกณฑ์การสำเร็จการศึกษาห้าบรรทัดเป็นข้อความที่แต่ละวิทยาลัยเขียนเอง
-- และต้องมีทั้งสองภาษา — ไม่มีที่เก็บมาก่อนเลย ถ้าปล่อยให้ไปอยู่ในแม่แบบ
-- จะกลายเป็นข้อความของวิทยาลัยเดียวที่ติดไปกับทุกวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
create table if not exists institution_document_text (
  institution_id uuid not null references institution(id) on delete cascade,
  /* ตัวอย่าง 'transcript_criteria_1' … '_5' · 'transcript_footer' */
  key            text not null,
  text_th        text,
  text_en        text,
  updated_at     timestamptz not null default now(),
  primary key (institution_id, key)
);

comment on table institution_document_text is
  'ข้อความประจำสถานศึกษาที่พิมพ์บนเอกสาร เช่น เกณฑ์การสำเร็จการศึกษาห้าบรรทัด — เก็บสองภาษาเพราะใบ รบ. มีทั้งฉบับไทยและอังกฤษ';

alter table institution_document_text enable row level security;
alter table institution_document_text force row level security;

create policy tenant_isolation on institution_document_text
  using (institution_id = current_institution_id());

/*
 * แยกเป็น for insert/update/delete ไม่ใช่ for all — นโยบาย restrictive
 * แบบ for all กิน select ด้วย ซึ่งจะทำให้แม่แบบพิมพ์อ่านข้อความไม่ได้
 * (บทเรียนจาก 0053)
 */
create policy doc_text_insert on institution_document_text
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'director', 'admin'));

create policy doc_text_update on institution_document_text
  as restrictive for update
  using (current_app_role() in ('registrar', 'director', 'admin'))
  with check (current_app_role() in ('registrar', 'director', 'admin'));

create policy doc_text_delete on institution_document_text
  as restrictive for delete
  using (current_app_role() in ('registrar', 'director', 'admin'));

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ตัวจ่ายเลขที่และการออกเอกสาร
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * เพิ่มพารามิเตอร์ภาษาโดยให้ค่าเริ่มต้นเป็น 'th' — การเรียกแบบสองอาร์กิวเมนต์
 * ที่มีอยู่เดิมทั้งหมดจึงทำงานเหมือนเดิมทุกประการ ไม่ต้องไล่แก้
 *
 * **ต้อง drop ตัวเดิมก่อน** เพราะการเพิ่มพารามิเตอร์ที่มีค่าเริ่มต้นสร้าง
 * ฟังก์ชัน**ตัวใหม่**คู่กับตัวเดิม ไม่ใช่แทนที่ แล้วการเรียกแบบสองอาร์กิวเมนต์
 * จะกำกวมทันที (`function next_document_no(unknown, smallint) is not unique`)
 * — กับดักเดียวกับที่ 0029 เขียนเตือนไว้ตอนแก้ issue_document()
 */
drop function if exists next_document_no(document_kind, smallint);

create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text default 'th'
) returns text language plpgsql as $$
declare
  v_inst   uuid := current_institution_id();
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  /*
   * ─── ทำไม prefix ตั้งต้นเป็นปีการศึกษา ไม่ใช่ค่าว่าง ───
   * `issued_document` มี unique (institution, kind, doc_no, copy_no) ซึ่ง
   * **ไม่มีปีการศึกษาอยู่ในนั้น** ส่วนตัวนับเริ่มที่ 1 ใหม่ทุกปี — ถ้า prefix
   * เป็นค่าว่าง ปี 2569 กับ 2570 จะออกเลข "00001" เหมือนกันทั้งคู่ แล้ว
   * **ใบแรกของปีการศึกษาใหม่จะล้มด้วย duplicate key** พร้อมข้อความที่
   * อธิบายอะไรไม่ได้เลย
   *
   * อาการนี้โผล่หนึ่งปีหลังเปิดใช้งานพอดี และโผล่กับทุกวิทยาลัยที่ไม่เคย
   * ตั้ง prefix เอง ซึ่งคือทุกวิทยาลัย เพราะแถวถูกสร้างอัตโนมัติตอนออกใบแรก
   * (เจอตอนเขียนเทสต์ของ 0057 ไม่ใช่ตอนออกแบบ)
   *
   * ใช้ปีล้วนเป็นตัวเลขเพราะ `certificate_prefix_digits_only` บังคับว่า
   * สายของใบประกาศนียบัตรมีได้แต่ตัวเลข — วิทยาลัยแก้เป็นรูปแบบของตัวเองได้
   * ที่ `document_series.prefix` ภายหลัง
   */
  insert into document_series (institution_id, kind, year_be, lang, prefix)
  values (v_inst, p_kind, p_year_be, p_lang, p_year_be::text)
  on conflict (institution_id, kind, year_be, lang) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = v_inst and kind = p_kind
     and year_be = p_year_be and lang = p_lang
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint, text) is
  'จ่ายเลขที่เอกสารจากสายที่แยกตามสถานศึกษา ประเภท ปีการศึกษา และภาษา — ฉบับอังกฤษเดินเลขคนละสายตามที่งานทะเบียนใช้จริง';

/*
 * ตรวจว่าข้อมูลภาษาอังกฤษครบพอจะออกใบหรือยัง
 *
 * คืนรายการ**ชื่อช่องที่ยังว่าง** ไม่ใช่แค่ true/false เพราะคนที่กดแล้วถูก
 * ปฏิเสธต้องรู้ว่าต้องไปกรอกอะไรบ้าง มิฉะนั้นจะกดซ้ำแล้วเดาไปเรื่อย
 */
create or replace function missing_english_fields(p_student_id uuid)
returns text[] language sql stable as $$
  select coalesce(array_agg(x.label order by x.ord), '{}')
    from (
      select 1 as ord, 'ชื่อ-นามสกุลภาษาอังกฤษของนักศึกษา' as label
       where exists (select 1 from student s join person p on p.id = s.person_id
                      where s.id = p_student_id
                        and (coalesce(p.first_name_en, '') = ''
                          or coalesce(p.last_name_en, '') = ''))
      union all
      select 2, 'ชื่อสถานศึกษาภาษาอังกฤษ'
       where exists (select 1 from student s join institution i on i.id = s.institution_id
                      where s.id = p_student_id and coalesce(i.name_en, '') = '')
      union all
      select 3, 'ประเภทวิชาภาษาอังกฤษ'
       where exists (select 1 from student_curriculum sc
                       join curriculum_version cv on cv.id = sc.curriculum_version_id
                       join curriculum cur on cur.id = cv.curriculum_id
                       join program_track ptr on ptr.id = cur.program_track_id
                       join program pr on pr.id = ptr.program_id
                       join program_type pt on pt.id = pr.program_type_id
                      where sc.student_id = p_student_id
                        and (sc.effective_to is null or sc.effective_to >= current_date)
                        and coalesce(pt.name_en, '') = '')
      union all
      select 4, 'สาขาวิชาภาษาอังกฤษ'
       where exists (select 1 from student_curriculum sc
                       join curriculum_version cv on cv.id = sc.curriculum_version_id
                       join curriculum cur on cur.id = cv.curriculum_id
                       join program_track ptr on ptr.id = cur.program_track_id
                       join program pr on pr.id = ptr.program_id
                      where sc.student_id = p_student_id
                        and (sc.effective_to is null or sc.effective_to >= current_date)
                        and coalesce(pr.name_en, '') = '')
      union all
      select 5, 'สาขางานภาษาอังกฤษ'
       where exists (select 1 from student_curriculum sc
                       join curriculum_version cv on cv.id = sc.curriculum_version_id
                       join curriculum cur on cur.id = cv.curriculum_id
                       join program_track ptr on ptr.id = cur.program_track_id
                      where sc.student_id = p_student_id
                        and (sc.effective_to is null or sc.effective_to >= current_date)
                        and coalesce(ptr.name_en, '') = '')
    ) x
$$;

comment on function missing_english_fields(uuid) is
  'รายชื่อช่องภาษาอังกฤษที่ยังว่างสำหรับนักศึกษารายนั้น — ว่างเปล่าแปลว่าออกใบฉบับอังกฤษได้';

/*
 * รายวิชาที่ยังไม่มีชื่อภาษาอังกฤษในใบของนักศึกษาคนหนึ่ง
 *
 * แยกจากฟังก์ชันข้างบนเพราะจำนวนอาจเป็นสิบ ๆ วิชา การยัดรวมเป็นรายการเดียว
 * จะได้ข้อความผิดพลาดที่ยาวจนอ่านไม่ไหว — ชั้น API เลือกได้ว่าจะแสดงกี่ชื่อ
 */
create or replace function courses_missing_english(p_student_id uuid)
returns table (code text, name_th text) language sql stable as $$
  select distinct c.code, c.name_th
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join course c on c.id = cs.course_id
   where e.student_id = p_student_id
     and e.status <> 'dropped'
     and coalesce(c.name_en, '') = ''
   order by c.code
$$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- issue_document() รับภาษา
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ─── ทำไมแยกเป็นสองฟังก์ชัน ───
 * `issue_document_core()` คือตัวประกอบ payload และเขียนแถว ซึ่งเป็นเนื้อ
 * เดียวกับของ 0029 ทุกประการ ต่างแค่รู้จักภาษา · ส่วน `issue_document()`
 * เป็นด่านตรวจว่าข้อมูลภาษาอังกฤษครบพอจะออกใบไหม
 *
 * แยกเพราะการตรวจกับการประกอบเป็นคนละเรื่อง และการยัดรวมกันจะทำให้
 * เงื่อนไข "ออกไม่ได้" ไปปนอยู่กลางโค้ดที่ยาว 200 บรรทัด จนหาไม่เจอ
 */
create or replace function issue_document_core(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint,
  p_term_id    uuid,
  p_lang       text
)
 RETURNS issued_document
 LANGUAGE plpgsql
AS $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;

  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  if v_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;

  if v_kind = 'grade_report' and p_term_id is null then
    raise exception 'ออกสมุดพกต้องระบุภาคเรียน มิฉะนั้นจะได้ผลการเรียนของภาคที่ไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;

  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;

  v_year := coalesce(
    p_year_be,
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year, p_lang);

  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
    'lang',        p_lang,
    'issued_at',   now(),
    'year_be',     v_year,
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status,
                     -- ฉบับอังกฤษต้องมีชื่ออังกฤษ ซึ่ง issue_document()
                     -- ตรวจแล้วว่าไม่ว่างก่อนเรียกมาถึงตรงนี้
                     'prefix_en',     coalesce(p.prefix_en, ''),
                     'first_name_en', coalesce(p.first_name_en, ''),
                     'last_name_en',  coalesce(p.last_name_en, ''),
                     'full_name_en',  trim(coalesce(p.prefix_en, '')
                                        || ' ' || coalesce(p.first_name_en, '')
                                        || ' ' || coalesce(p.last_name_en, ''))),
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end,
                             'type_en',       coalesce(pt.name_en, ''),
                             'name_en',       coalesce(pr.name_en, ''),
                             'track_en',      coalesce(ptr.name_en, ''),
                             'curriculum_en', coalesce(cur.name_en, ''),
                             'qualification_en',
                               case pr.level
                                 when 'PVC' then 'Vocational Certificate'
                                 when 'PVS' then 'High Vocational Certificate'
                                 when 'TVB' then 'Bachelor of Technology'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t           on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none'))
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  -- ── ข้อความประจำสถานศึกษาและผลมาตรฐานวิชาชีพ ──────────────────────
  -- อยู่บนใบ รบ. และใบประกาศนียบัตรเท่านั้น ใบอื่นไม่ได้พิมพ์เกณฑ์การจบ
  if v_kind in ('transcript', 'certificate') then
    v_payload := v_payload || jsonb_build_object(
      'institution_text',
        coalesce((select jsonb_object_agg(
                           t.key,
                           jsonb_build_object('th', coalesce(t.text_th, ''),
                                              'en', coalesce(t.text_en, '')))
                    from institution_document_text t
                   where t.institution_id = v_inst), '{}'::jsonb),
      'professional_standard',
        (select jsonb_build_object(
                  'no',      coalesce(sg.professional_standard_no, ''),
                  -- null = ยังไม่ได้เข้ารับการประเมิน ซึ่งต่างจาก false
                  -- คือประเมินแล้วไม่ผ่าน สองอย่างนี้พิมพ์บนใบไม่เหมือนกัน
                  'passed',  sg.professional_standard_passed,
                  'on_date', sg.professional_standard_on)
           from student_graduation sg
          where sg.student_id = p_student_id
          order by sg.completed_on desc limit 1));
  end if;

  -- ── ระเบียนแสดงผลการเรียน — ต้องมีรายวิชาทั้งหมดและผลรายภาค ───────
  if v_kind in ('transcript', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'term_summaries',
        coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                    from (select ay.year_be, t.ordinal,
                                 'ภาคเรียนที่ ' || t.ordinal
                                   || ' ปีการศึกษา ' || ay.year_be as label,
                                 ts.gpa, ts.gpax, ts.credits_earned
                            from term_summary ts
                            join term t           on t.id  = ts.term_id
                            join academic_year ay on ay.id = t.academic_year_id
                           where ts.student_id = p_student_id) x), '[]'::jsonb),
      'courses',
        coalesce((select jsonb_agg(to_jsonb(td))
                    from transcript_data(p_student_id) td), '[]'::jsonb));
  end if;

  -- ── สมุดพก — ผลการเรียนประจำภาคพร้อมเวลาเรียนและความประพฤติ ───────
  if v_kind = 'grade_report' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
                  'gpa',     ts.gpa,
                  'gpax',    ts.gpax,
                  'credits_earned', ts.credits_earned)
           from term t
           join academic_year ay on ay.id = t.academic_year_id
           left join term_summary ts
                  on ts.term_id = t.id and ts.student_id = p_student_id
          where t.id = p_term_id),

      -- เวลาเรียนมาจาก v_enrollment_attendance ซึ่งเป็นค่าสด ณ เวลาออกใบ
      -- ต่างจากระเบียนแสดงผลการเรียนที่ใช้ attendance_pct ที่ตรึงตอนตัดเกรด
      -- เพราะสมุดพกมักออกกลางภาคตอนที่ยังไม่มีการตัดเกรด
      'term_courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'course_code',   c.code,
                           'course_name_th', c.name_th,
                           'credits',       c.credits,
                           'grade_symbol',  gsym.symbol,
                           'attendance_pct', v.pct_to_date,
                           'attendance_state', v.attendance_state,
                           'absences_left', v.absences_left)
                           order by c.code)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    left join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join enrollment_result er
                           on er.enrollment_id = e.id and er.superseded_by is null
                    left join grade_symbol gsym on gsym.id = er.grade_symbol_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'), '[]'::jsonb),

      'activities',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'sessions_required', cr.sessions_required,
                           'sessions_attended', cr.sessions_attended,
                           'result', cr.result))
                    from cocurricular_result cr
                   where cr.student_id = p_student_id
                     and cr.term_id = p_term_id), '[]'::jsonb));
  end if;

  -- ── ความประพฤติ — สมุดพกและระเบียนสะสมต้องมี ─────────────────────
  --
  -- behavior_record.points เป็นจำนวนบวกเสมอ (check points > 0 ใน 0011)
  -- ทิศทางหักหรือเพิ่มอยู่ที่ behavior_rule.direction ไม่ใช่ที่เครื่องหมาย
  -- ของตัวเลข การรวมยอดโดยดูเครื่องหมายจึงได้คำตอบผิดแบบดูไม่ออก —
  -- "หนีเรียน" จะกลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์อยู่บนกระดาษ
  --
  -- ยอดคงเหลือจึงอ่านจาก v_behavior_balance ซึ่งเป็นสูตรเดียวกับที่ระบบ
  -- เตือนก่อนออกกลางคันใช้ ไม่เขียนสูตรซ้ำที่นี่ให้มีโอกาสไม่ตรงกัน
  if v_kind in ('grade_report', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'behavior',
        (select jsonb_build_object(
                  'starting_points', bp.starting_points,
                  'deducted', coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'deduct'), 0),
                  'awarded',  coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'award'), 0),
                  'current',  (select vb.balance from v_behavior_balance vb
                                where vb.student_id = p_student_id),
                  'warn_below', bp.warn_below,
                  'critical_below', bp.critical_below)
           from behavior_policy bp
          where bp.institution_id = v_inst));
  end if;

  -- ── ระเบียนสะสม (ปพ.8) ────────────────────────────────────────────
  if v_kind = 'cumulative_record' then
    v_payload := v_payload || jsonb_build_object(
      'guardians',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'relation',  sg.relation,
                           'full_name', trim(coalesce(gp.prefix_th, '')
                                          || coalesce(gp.first_name_th, '')
                                          || ' ' || coalesce(gp.last_name_th, '')),
                           'phone',     coalesce(gp.phone, ''),
                           'is_primary', sg.is_primary)
                           order by sg.is_primary desc)
                    from student_guardian sg
                    join person gp on gp.id = sg.person_id
                   where sg.student_id = p_student_id
                     and sg.verified_at is not null), '[]'::jsonb),

      -- เก็บแค่ระดับผลกับวันที่ ไม่เก็บคำตอบรายข้อ (detail) โดยตั้งใจ
      -- ดูเหตุผลที่หัวไฟล์ — เอกสารนี้ลบไม่ได้และถูกส่งต่อกันไปเรื่อย ๆ
      'screenings',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'instrument',  sr.instrument,
                           'assessed_on', sr.assessed_on,
                           'band',        sr.band)
                           order by sr.assessed_on)
                    from screening_result sr
                   where sr.student_id = p_student_id), '[]'::jsonb),

      -- ส่ง direction ไปด้วยเสมอ เพราะ points เป็นบวกทั้งคู่
      -- ถ้าให้แม่แบบเดาเครื่องหมายเอง ใบจะพิมพ์ว่าหนีเรียนแล้วได้คะแนนเพิ่ม
      'behavior_history',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'occurred_on', br.occurred_on,
                           'points',      br.points,
                           'direction',   brl.direction,
                           'rule_th',     coalesce(brl.name_th, ''),
                           'document_no', coalesce(br.document_no, ''))
                           order by br.occurred_on)
                    from behavior_record br
                    left join behavior_rule brl on brl.id = br.rule_id
                   where br.student_id = p_student_id), '[]'::jsonb),

      'activities_all',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'result',        cr.result,
                           'term_label',    'ภาคเรียนที่ ' || t.ordinal
                                              || '/' || ay.year_be))
                    from cocurricular_result cr
                    join term t           on t.id  = cr.term_id
                    join academic_year ay on ay.id = t.academic_year_id
                   where cr.student_id = p_student_id), '[]'::jsonb),

      -- บันทึกเยี่ยมบ้านมีข้อค้นพบเป็นข้อความอิสระที่อ่อนไหวมาก
      -- ระเบียนสะสมจึงบันทึกแค่ว่า "เคยเยี่ยมกี่ครั้ง ครั้งล่าสุดเมื่อไร"
      'home_visits',
        (select jsonb_build_object(
                  'count', count(*),
                  'last_visited_on', max(hv.visited_on))
           from home_visit hv where hv.student_id = p_student_id));
  end if;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document_core(uuid, document_kind, smallint, uuid, text) is
  'ประกอบ payload และเขียนแถว — ไม่ตรวจความครบของข้อมูลภาษาอังกฤษ ให้ issue_document() ตรวจก่อนเรียก';

/*
 * เปลี่ยนลายเซ็นจึงต้อง drop ก่อน — `create or replace` เปลี่ยนรายการ
 * พารามิเตอร์ไม่ได้ จะกลายเป็นฟังก์ชันคนละตัวแล้วการเรียกแบบสี่อาร์กิวเมนต์
 * จะกำกวมทันที (กับดักเดียวกับที่ 0029 เจอ)
 */
drop function if exists issue_document(uuid, document_kind, smallint, uuid);

create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null,
  p_term_id    uuid     default null,
  p_lang       text     default 'th'
) returns issued_document language plpgsql as $$
declare
  v_row     issued_document;
  v_missing text[];
  v_courses text[];
begin
  if p_lang not in ('th', 'en') then
    raise exception 'ภาษาของเอกสารต้องเป็น th หรือ en เท่านั้น'
      using errcode = 'check_violation';
  end if;

  /*
   * ─── สองเส้นทางต้องปฏิเสธประเภทของกันและกัน**อย่างชัดเจน** ───
   * `issue_student_letter()` ของ 0055 ปฏิเสธใบทั้งห้าของทางนี้ด้วยเงื่อนไข
   * ที่เขียนไว้ตรง ๆ แต่ทางนี้เคยปฏิเสธหนังสือถึงผู้ปกครองโดย**บังเอิญ**
   * (payload ไม่มีสาขาที่รองรับ แล้วไปล้มด้วยเหตุผลอื่นทีหลัง) ซึ่งแปลว่า
   * การเขียนฟังก์ชันใหม่ทำให้การปฏิเสธนั้นหายไปเงียบ ๆ — TEST 247 จับได้
   * ตอนไฟล์นี้เขียนทับ issue_document() พอดี
   *
   * ปฏิเสธโดยบังเอิญกับปฏิเสธโดยตั้งใจให้ผลเหมือนกันวันนี้ แต่ต่างกันมาก
   * ในวันที่มีคนแก้โค้ด
   */
  if p_kind::text in ('absence_notice', 'guardian_invitation', 'conduct_certificate') then
    raise exception 'หนังสือถึงผู้ปกครองและใบรับรองความประพฤติออกด้วย issue_student_letter() '
                    '— payload เป็นคนละชุดกัน (มีผู้รับและที่อยู่ · ไม่มี GPAX)'
      using errcode = 'check_violation';
  end if;

  /*
   * ล้มตั้งแต่ตอนกด ดีกว่าออกใบที่หัวเป็นอังกฤษแต่ชื่อสาขาเป็นไทย
   * ซึ่งเป็นเอกสารทางการที่ดูเหมือนระบบพัง และแก้ไม่ได้อีกเลยเพราะ
   * payload ตรึงแล้ว (หลักข้อ 6)
   */
  if p_lang = 'en' then
    v_missing := missing_english_fields(p_student_id);

    if p_kind::text in ('transcript', 'cumulative_record', 'grade_report') then
      select array_agg(x.code || ' ' || x.name_th)
        into v_courses
        from (select code, name_th from courses_missing_english(p_student_id) limit 5) x;
      if v_courses is not null then
        v_missing := v_missing || ('รายวิชาที่ยังไม่มีชื่อภาษาอังกฤษ: '
                                   || array_to_string(v_courses, ' · '));
      end if;
    end if;

    if array_length(v_missing, 1) > 0 then
      raise exception 'ออกเอกสารฉบับภาษาอังกฤษไม่ได้ ยังไม่ได้กรอก — %',
        array_to_string(v_missing, ' · ')
        using errcode = 'check_violation';
    end if;
  end if;

  v_row := issue_document_core(p_student_id, p_kind, p_year_be, p_term_id, p_lang);
  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint, uuid, text) is
  'ออกเอกสาร — ฉบับภาษาอังกฤษเดินเลขคนละสายและปฏิเสธถ้าข้อมูลภาษาอังกฤษยังไม่ครบ ล้มตั้งแต่กดดีกว่าออกใบที่ใช้ไม่ได้';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0058_transcript_category_tree.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0058 — โครงหมวด/กลุ่มวิชาสำหรับใบ รบ. ตระกูล 67
--
-- ═══ ทำไมต้องมี ═══
-- ใบ รบ. ตระกูล ปวช./ปวส. 67 (วัดจากไฟล์จริง — ดู docs/transcript-formats.md)
-- **จัดกลุ่มรายวิชาตามหมวด → กลุ่มวิชา** แล้วสรุปสามบรรทัดใต้ทุกกลุ่ม
--   · จำนวนหน่วยกิตตามหลักสูตร N หน่วยกิต
--   · จำนวนหน่วยกิตที่ได้ N หน่วยกิต
--   · คะแนนเฉลี่ยสะสมกลุ่ม… N.NN
-- และสรุปคะแนนเฉลี่ยสะสมรายหมวดอีกชั้นหนึ่ง
--
-- `transcript_data()` เดิมคืน `category_th` แบน ๆ ชั้นเดียว ซึ่งพอสำหรับ
-- ใบตระกูล 62 ที่จัดตามภาคเรียน แต่ตอบไม่ได้ว่ากลุ่มไหนอยู่ใต้หมวดไหน
-- และไม่มีหน่วยกิตตามหลักสูตรให้เทียบ
--
-- ═══ ทำไมคำนวณที่ฐานข้อมูล ไม่ใช่ที่แม่แบบ ═══
-- คะแนนเฉลี่ยรายกลุ่มเป็น**ตัวเลขบนเอกสารทางการ** ถ้าให้แม่แบบรวมเอง
-- จะกลายเป็นสูตรชุดที่สองที่ค่อย ๆ เพี้ยนไปจาก `term_summary` และ
-- `student_graduation.gpax` ซึ่งเป็นตัวเลขที่ระบบใช้ตัดสินการจบจริง
-- (หลักข้อ 1 — ฐานข้อมูลเป็นเจ้าของกฎ)
--
-- ═══ ทำไมวิชาที่ไม่มีหมวดต้องไม่หายไป ═══
-- `curriculum_course` เป็น left join ใน transcript_data() อยู่แล้ว แปลว่า
-- วิชาที่ยังไม่ได้ผูกเข้าโครงหลักสูตรจะได้ category เป็น null — ถ้าปล่อยให้
-- หลุดออกจากโครงต้นไม้ ใบ รบ. จะขาดรายวิชาไปเงียบ ๆ โดยยอดหน่วยกิตรวม
-- ยังถูกต้อง ซึ่งเป็นความผิดที่มองไม่ออกจนกว่าจะมีคนนับวิชาบนกระดาษ
-- จึงรวมไว้ในกลุ่มพิเศษที่**ชื่อบอกว่ายังไม่ได้จัดหมวด**
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * รายวิชาพร้อมหมวดและกลุ่ม
 *
 * คืนทั้งรหัสและลำดับของทั้งสองชั้น เพื่อให้ชั้นบนเรียงได้ตรงกับที่หลักสูตร
 * กำหนด ไม่ใช่เรียงตามตัวอักษรของชื่อ (ซึ่งจะสลับที่ทุกครั้งที่วิทยาลัย
 * แก้ชื่อกลุ่ม)
 */
create or replace function transcript_courses_grouped(p_student_id uuid)
returns table (
  head_code   text,
  head_name   text,
  head_sort   smallint,
  head_min    numeric,
  group_code  text,
  group_name  text,
  group_sort  smallint,
  group_min   numeric,
  year_be     smallint,
  term_ordinal smallint,
  term_label  text,
  course_code text,
  course_name_th text,
  course_name_en text,
  credits     numeric,
  grade_symbol text,
  grade_point numeric,
  credits_earned numeric,
  counts_in_gpa boolean
) language sql stable as $$
  select
    coalesce(head.code, 'UNSORTED')            as head_code,
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as head_name,
    coalesce(head.sort_order, 99)::smallint    as head_sort,
    head.min_credits                           as head_min,
    /*
     * วิชาที่ผูกกับหมวดโดยตรง (ไม่มีกลุ่มย่อย) ให้ group เป็นตัวมันเอง
     * เพื่อให้แม่แบบวนสองชั้นได้เสมอโดยไม่ต้องมีสาขาพิเศษ
     */
    coalesce(grp.code, head.code, 'UNSORTED')  as group_code,
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as group_name,
    coalesce(grp.sort_order, 0)::smallint      as group_sort,
    coalesce(grp.min_credits, head.min_credits) as group_min,
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    gsym.counts_in_gpa
  from enrollment e
  join class_section cs     on cs.id = e.class_section_id
  join course c             on c.id  = cs.course_id
  join term t               on t.id  = e.term_id
  join academic_year ay     on ay.id = t.academic_year_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym    on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  -- cat อาจเป็นหมวดเอง (parent_id null) หรือเป็นกลุ่มย่อย
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by coalesce(head.sort_order, 99), coalesce(grp.sort_order, 0),
           ay.year_be, t.ordinal, c.code
$$;

comment on function transcript_courses_grouped(uuid) is
  'รายวิชาบนใบ รบ. พร้อมหมวดและกลุ่มวิชา — วิชาที่ยังไม่ได้ผูกโครงหลักสูตรไปอยู่กลุ่ม UNSORTED ไม่ใช่หายไปเงียบ ๆ';

/*
 * ยอดสรุปรายกลุ่มและรายหมวด
 *
 * คะแนนเฉลี่ยคิดจากรายวิชาที่ `counts_in_gpa` เท่านั้น — วิชาที่ได้ ผ./ม.ผ.
 * มีหน่วยกิตแต่ไม่มีแต้ม ถ้ารวมเข้าไปจะกดค่าเฉลี่ยลงโดยไม่มีใครสังเกต
 */
create or replace function transcript_category_summary(p_student_id uuid)
returns table (
  level       text,      -- 'head' หรือ 'group'
  head_code   text,
  group_code  text,
  name_th     text,
  sort_key    text,
  min_credits numeric,
  credits_earned numeric,
  gpa         numeric
) language sql stable as $$
  with rows as (select * from transcript_courses_grouped(p_student_id))
  select 'group', r.head_code, r.group_code, max(r.group_name),
         lpad(max(r.head_sort)::text, 3, '0') || '-' || lpad(max(r.group_sort)::text, 3, '0'),
         max(r.group_min),
         coalesce(sum(r.credits_earned), 0),
         case when sum(r.credits) filter (where r.counts_in_gpa) > 0
              then round(sum(r.grade_point * r.credits) filter (where r.counts_in_gpa)
                         / sum(r.credits) filter (where r.counts_in_gpa), 2)
         end
    from rows r
   group by r.head_code, r.group_code
  union all
  select 'head', r.head_code, null, max(r.head_name),
         lpad(max(r.head_sort)::text, 3, '0') || '-999',
         max(r.head_min),
         coalesce(sum(r.credits_earned), 0),
         case when sum(r.credits) filter (where r.counts_in_gpa) > 0
              then round(sum(r.grade_point * r.credits) filter (where r.counts_in_gpa)
                         / sum(r.credits) filter (where r.counts_in_gpa), 2)
         end
    from rows r
   group by r.head_code
   order by 5
$$;

comment on function transcript_category_summary(uuid) is
  'หน่วยกิตและคะแนนเฉลี่ยรายกลุ่มวิชาและรายหมวด — คิดเฉพาะวิชาที่ counts_in_gpa มิฉะนั้นวิชา ผ./ม.ผ. จะกดค่าเฉลี่ยลง';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ใส่โครงต้นไม้ลง payload ของใบ รบ.
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * เพิ่มเฉพาะสาขา transcript — ใบอื่นไม่ได้พิมพ์โครงหมวด/กลุ่ม
 * การใส่ทุกใบคือการเก็บเกินจำเป็นในที่ที่ลบไม่ได้ (หลักข้อ 5ก)
 */
create or replace function transcript_category_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(head order by head ->> 'sort'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'code',        h.head_code,
               'name_th',     h.name_th,
               'sort',        h.sort_key,
               'min_credits', h.min_credits,
               'credits_earned', h.credits_earned,
               'gpa',         h.gpa,
               'groups',
                 coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'code',        g.group_code,
                            'name_th',     g.name_th,
                            'sort',        g.sort_key,
                            'min_credits', g.min_credits,
                            'credits_earned', g.credits_earned,
                            'gpa',         g.gpa,
                            'courses',
                              coalesce((
                                select jsonb_agg(jsonb_build_object(
                                         'term_label',  c.term_label,
                                         'year_be',     c.year_be,
                                         'term_ordinal', c.term_ordinal,
                                         'code',        c.course_code,
                                         'name_th',     c.course_name_th,
                                         'name_en',     c.course_name_en,
                                         'credits',     c.credits,
                                         'grade',       c.grade_symbol,
                                         'grade_point', c.grade_point,
                                         'credits_earned', c.credits_earned)
                                         order by c.year_be, c.term_ordinal, c.course_code)
                                  from transcript_courses_grouped(p_student_id) c
                                 where c.head_code = h.head_code
                                   and c.group_code = g.group_code), '[]'::jsonb))
                          order by g.sort_key)
                     from transcript_category_summary(p_student_id) g
                    where g.level = 'group' and g.head_code = h.head_code), '[]'::jsonb)) as head
        from transcript_category_summary(p_student_id) h
       where h.level = 'head'
    ) x
$$;

comment on function transcript_category_tree(uuid) is
  'โครงหมวด → กลุ่มวิชา → รายวิชา พร้อมยอดสรุปทุกชั้น สำหรับใบ รบ. ตระกูล 67';

/*
 * เขียน issue_document_core() ทับทั้งตัวเพื่อเพิ่มบรรทัดเดียว
 *
 * plpgsql แก้เฉพาะบางบรรทัดไม่ได้ และการแยกเนื้อ payload ออกเป็นฟังก์ชันย่อย
 * จะทำให้ payload ของใบเดียวถูกประกอบจากหลายที่ ซึ่งขัดกับหลักข้อ 5ก
 * ที่ต้องดูจุดเดียวได้ว่าใบไหนเก็บอะไรบ้าง — migration เป็นภาพนิ่ง
 * นิยามที่ใช้จริงมีชุดเดียวเสมอ
 */
create or replace function issue_document_core(p_student_id uuid, p_kind document_kind, p_year_be smallint, p_term_id uuid, p_lang text)
 RETURNS issued_document
 LANGUAGE plpgsql
AS $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;
  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  if v_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;
  if v_kind = 'grade_report' and p_term_id is null then
    raise exception 'ออกสมุดพกต้องระบุภาคเรียน มิฉะนั้นจะได้ผลการเรียนของภาคที่ไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;
  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;
  v_year := coalesce(
    p_year_be,
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );
  v_doc_no := next_document_no(p_kind, v_year, p_lang);
  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
    'lang',        p_lang,
    'issued_at',   now(),
    'year_be',     v_year,
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status,
                     -- ฉบับอังกฤษต้องมีชื่ออังกฤษ ซึ่ง issue_document()
                     -- ตรวจแล้วว่าไม่ว่างก่อนเรียกมาถึงตรงนี้
                     'prefix_en',     coalesce(p.prefix_en, ''),
                     'first_name_en', coalesce(p.first_name_en, ''),
                     'last_name_en',  coalesce(p.last_name_en, ''),
                     'full_name_en',  trim(coalesce(p.prefix_en, '')
                                        || ' ' || coalesce(p.first_name_en, '')
                                        || ' ' || coalesce(p.last_name_en, ''))),
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end,
                             'type_en',       coalesce(pt.name_en, ''),
                             'name_en',       coalesce(pr.name_en, ''),
                             'track_en',      coalesce(ptr.name_en, ''),
                             'curriculum_en', coalesce(cur.name_en, ''),
                             'qualification_en',
                               case pr.level
                                 when 'PVC' then 'Vocational Certificate'
                                 when 'PVS' then 'High Vocational Certificate'
                                 when 'TVB' then 'Bachelor of Technology'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t           on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none'))
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;
  -- ── ข้อความประจำสถานศึกษาและผลมาตรฐานวิชาชีพ ──────────────────────
  -- อยู่บนใบ รบ. และใบประกาศนียบัตรเท่านั้น ใบอื่นไม่ได้พิมพ์เกณฑ์การจบ
  if v_kind in ('transcript', 'certificate') then
    v_payload := v_payload || jsonb_build_object(
      'institution_text',
        coalesce((select jsonb_object_agg(
                           t.key,
                           jsonb_build_object('th', coalesce(t.text_th, ''),
                                              'en', coalesce(t.text_en, '')))
                    from institution_document_text t
                   where t.institution_id = v_inst), '{}'::jsonb),
      'professional_standard',
        (select jsonb_build_object(
                  'no',      coalesce(sg.professional_standard_no, ''),
                  -- null = ยังไม่ได้เข้ารับการประเมิน ซึ่งต่างจาก false
                  -- คือประเมินแล้วไม่ผ่าน สองอย่างนี้พิมพ์บนใบไม่เหมือนกัน
                  'passed',  sg.professional_standard_passed,
                  'on_date', sg.professional_standard_on)
           from student_graduation sg
          where sg.student_id = p_student_id
          order by sg.completed_on desc limit 1));
  end if;
  -- ── ระเบียนแสดงผลการเรียน — ต้องมีรายวิชาทั้งหมดและผลรายภาค ───────
  if v_kind in ('transcript', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'term_summaries',
        coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                    from (select ay.year_be, t.ordinal,
                                 'ภาคเรียนที่ ' || t.ordinal
                                   || ' ปีการศึกษา ' || ay.year_be as label,
                                 ts.gpa, ts.gpax, ts.credits_earned
                            from term_summary ts
                            join term t           on t.id  = ts.term_id
                            join academic_year ay on ay.id = t.academic_year_id
                           where ts.student_id = p_student_id) x), '[]'::jsonb),
      'courses',
        coalesce((select jsonb_agg(to_jsonb(td))
                    from transcript_data(p_student_id) td), '[]'::jsonb),
      -- โครงหมวด → กลุ่มวิชา → รายวิชา พร้อมยอดสรุปทุกชั้น (0058)
      -- ใบตระกูล 67 จัดกลุ่มแบบนี้ ส่วนตระกูล 62 ใช้ 'courses' ที่จัดตามภาคเรียน
      -- เก็บทั้งสองชุดเพราะเป็นตัวเลขคนละชุดที่คำนวณคนละแบบ ไม่ใช่ข้อมูลซ้ำ
      'category_tree', transcript_category_tree(p_student_id));
  end if;
  -- ── สมุดพก — ผลการเรียนประจำภาคพร้อมเวลาเรียนและความประพฤติ ───────
  if v_kind = 'grade_report' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
                  'gpa',     ts.gpa,
                  'gpax',    ts.gpax,
                  'credits_earned', ts.credits_earned)
           from term t
           join academic_year ay on ay.id = t.academic_year_id
           left join term_summary ts
                  on ts.term_id = t.id and ts.student_id = p_student_id
          where t.id = p_term_id),
      -- เวลาเรียนมาจาก v_enrollment_attendance ซึ่งเป็นค่าสด ณ เวลาออกใบ
      -- ต่างจากระเบียนแสดงผลการเรียนที่ใช้ attendance_pct ที่ตรึงตอนตัดเกรด
      -- เพราะสมุดพกมักออกกลางภาคตอนที่ยังไม่มีการตัดเกรด
      'term_courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'course_code',   c.code,
                           'course_name_th', c.name_th,
                           'credits',       c.credits,
                           'grade_symbol',  gsym.symbol,
                           'attendance_pct', v.pct_to_date,
                           'attendance_state', v.attendance_state,
                           'absences_left', v.absences_left)
                           order by c.code)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    left join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join enrollment_result er
                           on er.enrollment_id = e.id and er.superseded_by is null
                    left join grade_symbol gsym on gsym.id = er.grade_symbol_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'), '[]'::jsonb),
      'activities',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'sessions_required', cr.sessions_required,
                           'sessions_attended', cr.sessions_attended,
                           'result', cr.result))
                    from cocurricular_result cr
                   where cr.student_id = p_student_id
                     and cr.term_id = p_term_id), '[]'::jsonb));
  end if;
  -- ── ความประพฤติ — สมุดพกและระเบียนสะสมต้องมี ─────────────────────
  --
  -- behavior_record.points เป็นจำนวนบวกเสมอ (check points > 0 ใน 0011)
  -- ทิศทางหักหรือเพิ่มอยู่ที่ behavior_rule.direction ไม่ใช่ที่เครื่องหมาย
  -- ของตัวเลข การรวมยอดโดยดูเครื่องหมายจึงได้คำตอบผิดแบบดูไม่ออก —
  -- "หนีเรียน" จะกลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์อยู่บนกระดาษ
  --
  -- ยอดคงเหลือจึงอ่านจาก v_behavior_balance ซึ่งเป็นสูตรเดียวกับที่ระบบ
  -- เตือนก่อนออกกลางคันใช้ ไม่เขียนสูตรซ้ำที่นี่ให้มีโอกาสไม่ตรงกัน
  if v_kind in ('grade_report', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'behavior',
        (select jsonb_build_object(
                  'starting_points', bp.starting_points,
                  'deducted', coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'deduct'), 0),
                  'awarded',  coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'award'), 0),
                  'current',  (select vb.balance from v_behavior_balance vb
                                where vb.student_id = p_student_id),
                  'warn_below', bp.warn_below,
                  'critical_below', bp.critical_below)
           from behavior_policy bp
          where bp.institution_id = v_inst));
  end if;
  -- ── ระเบียนสะสม (ปพ.8) ────────────────────────────────────────────
  if v_kind = 'cumulative_record' then
    v_payload := v_payload || jsonb_build_object(
      'guardians',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'relation',  sg.relation,
                           'full_name', trim(coalesce(gp.prefix_th, '')
                                          || coalesce(gp.first_name_th, '')
                                          || ' ' || coalesce(gp.last_name_th, '')),
                           'phone',     coalesce(gp.phone, ''),
                           'is_primary', sg.is_primary)
                           order by sg.is_primary desc)
                    from student_guardian sg
                    join person gp on gp.id = sg.person_id
                   where sg.student_id = p_student_id
                     and sg.verified_at is not null), '[]'::jsonb),
      -- เก็บแค่ระดับผลกับวันที่ ไม่เก็บคำตอบรายข้อ (detail) โดยตั้งใจ
      -- ดูเหตุผลที่หัวไฟล์ — เอกสารนี้ลบไม่ได้และถูกส่งต่อกันไปเรื่อย ๆ
      'screenings',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'instrument',  sr.instrument,
                           'assessed_on', sr.assessed_on,
                           'band',        sr.band)
                           order by sr.assessed_on)
                    from screening_result sr
                   where sr.student_id = p_student_id), '[]'::jsonb),
      -- ส่ง direction ไปด้วยเสมอ เพราะ points เป็นบวกทั้งคู่
      -- ถ้าให้แม่แบบเดาเครื่องหมายเอง ใบจะพิมพ์ว่าหนีเรียนแล้วได้คะแนนเพิ่ม
      'behavior_history',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'occurred_on', br.occurred_on,
                           'points',      br.points,
                           'direction',   brl.direction,
                           'rule_th',     coalesce(brl.name_th, ''),
                           'document_no', coalesce(br.document_no, ''))
                           order by br.occurred_on)
                    from behavior_record br
                    left join behavior_rule brl on brl.id = br.rule_id
                   where br.student_id = p_student_id), '[]'::jsonb),
      'activities_all',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'result',        cr.result,
                           'term_label',    'ภาคเรียนที่ ' || t.ordinal
                                              || '/' || ay.year_be))
                    from cocurricular_result cr
                    join term t           on t.id  = cr.term_id
                    join academic_year ay on ay.id = t.academic_year_id
                   where cr.student_id = p_student_id), '[]'::jsonb),
      -- บันทึกเยี่ยมบ้านมีข้อค้นพบเป็นข้อความอิสระที่อ่อนไหวมาก
      -- ระเบียนสะสมจึงบันทึกแค่ว่า "เคยเยี่ยมกี่ครั้ง ครั้งล่าสุดเมื่อไร"
      'home_visits',
        (select jsonb_build_object(
                  'count', count(*),
                  'last_visited_on', max(hv.visited_on))
           from home_visit hv where hv.student_id = p_student_id));
  end if;
  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;
  return v_row;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0059_transcript_extra.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0059 — ส่วนที่ ปวส. ต่างจาก ปวช. และการแยก payload เฉพาะใบ รบ. ออกมา
--
-- ═══ สามอย่างที่ ปวส. ต่างจาก ปวช. (วัดจากไฟล์จริง) ═══
-- 1. ชื่อเรื่องต่างกันตามระดับและตามว่าเป็นหลักสูตรต่อเนื่องหรือไม่
--    · ปวช.  — ระเบียนแสดงผลการเรียนตามหลักสูตรประกาศนียบัตรวิชาชีพ พุทธศักราช 2567
--    · ปวส.  — …ประกาศนียบัตรวิชาชีพชั้นสูง พุทธศักราช 2567
--    · ปวส. ต่อเนื่อง — …ประกาศนียบัตรวิชาชีพชั้นสูง (ต่อเนื่อง) พุทธศักราช 2567
-- 2. **ปวส. มีช่อง "สาขาวิชาเดิม" เพิ่มมาหนึ่งช่อง** ที่ ปวช. ไม่มี
--    เพราะผู้เข้า ปวส. จบ ปวช. มา สาขาเดิมจึงมีความหมายกับการเทียบโอน
-- 3. ชื่อเรื่องภาษาอังกฤษใช้ **ปีคริสต์ศักราช** ไม่ใช่ พ.ศ.
--    "2024 CURRICULUM OF THE CERTIFICATE / DIPLOMA IN VOCATIONAL EDUCATION"
--    — ข้อนี้เดาไม่ถูกถ้าไม่ได้เปิดไฟล์จริงดู
--
-- ═══ ทำไมย้าย payload เฉพาะใบ รบ. ออกมาเป็นฟังก์ชันของตัวเอง ═══
-- 0057 กับ 0058 ต่างก็ต้องเขียน `issue_document_core()` ทับทั้ง 300 บรรทัด
-- เพื่อเพิ่มบรรทัดเดียว ซึ่งเป็นวิธีที่ทั้งเสี่ยงและอ่านไม่ออกว่าเปลี่ยนอะไร
--
-- ตอนแรกเลี่ยงการแยกเพราะกลัวว่า payload ของใบเดียวจะกระจายอยู่หลายที่
-- จนดูไม่ออกว่าใบไหนเก็บอะไร (หลักข้อ 5ก) — แต่การแยก **ตามประเภทใบ**
-- ให้ผลตรงกันข้าม คือเปิดไฟล์เดียวแล้วเห็นครบว่าใบ รบ. เก็บอะไรบ้าง
-- ต่างจากการแยกตามชนิดข้อมูลซึ่งจะกระจายจริง
--
-- นับจากนี้การเพิ่มช่องให้ใบ รบ. แก้ที่ `transcript_extra()` ที่เดียว
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * หลักสูตรต่อเนื่อง — ปวส. ที่รับผู้จบ ปวช. สาขาเดียวกันเข้าเรียนต่อ
 * มีชื่อเรียกบนใบ รบ. ต่างจาก ปวส. ปกติ จึงต้องรู้ที่ระดับหลักสูตร
 * ไม่ใช่เดาจากระดับ (`program.level`) ซึ่งเป็น PVS เหมือนกันทั้งคู่
 */
alter table curriculum add column if not exists is_continuing boolean not null default false;

comment on column curriculum.is_continuing is
  'หลักสูตรต่อเนื่อง — ใบ รบ. พิมพ์ "(ต่อเนื่อง)" ต่อท้ายชื่อคุณวุฒิ · program.level เป็น PVS เหมือน ปวส. ปกติ จึงแยกจากตรงนั้นไม่ได้';

/*
 * ส่วนของ payload ที่มีเฉพาะใบ รบ.
 *
 * `prior_education` อยู่ที่นี่เพราะใบ รบ. **พิมพ์ลงกระดาษจริง** ทั้งชื่อ
 * สถานศึกษาเดิม จังหวัด ระดับที่จบ ปีที่จบ และ (เฉพาะ ปวส.) สาขาวิชาเดิม
 * — ใบอื่นไม่ได้แสดง จึงไม่ควรติดไปด้วย (หลักข้อ 5ก)
 *
 * เลือกแถวเดียวคือรายการล่าสุด เพราะช่องบนใบมีชุดเดียว ถ้าส่งหลายแถวไป
 * แม่แบบจะต้องเลือกเอง ซึ่งเป็นการตัดสินใจที่ควรอยู่ที่นี่ที่เดียว
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'prior_education',
      (select jsonb_build_object(
                'level_th',   pe.level_th,
                'school_th',  coalesce(pe.school_th, ''),
                'province_th', coalesce(pe.province_th, ''),
                'program_th', coalesce(pe.program_th, ''),
                'year_be',    pe.completed_year_be,
                'gpax',       pe.gpax)
         from student_prior_education pe
        where pe.student_id = p_student_id
        order by pe.completed_year_be desc nulls last, pe.level_th desc
        limit 1))
$$;

comment on function transcript_extra(uuid) is
  'payload ส่วนที่มีเฉพาะใบ รบ. — เพิ่มช่องให้ใบ รบ. แก้ที่นี่ที่เดียว ไม่ต้องเขียน issue_document_core ทับทั้งตัว';


/*
 * เขียน issue_document_core() ทับเป็น**ครั้งสุดท้าย** — หลังจากนี้ส่วนของ
 * ใบ รบ. อยู่ใน transcript_extra() ซึ่งแก้ได้โดยไม่ต้องแตะตัวนี้อีก
 */
create or replace function issue_document_core(p_student_id uuid, p_kind document_kind, p_year_be smallint, p_term_id uuid, p_lang text)
 RETURNS issued_document
 LANGUAGE plpgsql
AS $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;
  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  if v_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;
  if v_kind = 'grade_report' and p_term_id is null then
    raise exception 'ออกสมุดพกต้องระบุภาคเรียน มิฉะนั้นจะได้ผลการเรียนของภาคที่ไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;
  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;
  v_year := coalesce(
    p_year_be,
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );
  v_doc_no := next_document_no(p_kind, v_year, p_lang);
  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
    'lang',        p_lang,
    'issued_at',   now(),
    'year_be',     v_year,
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status,
                     -- ฉบับอังกฤษต้องมีชื่ออังกฤษ ซึ่ง issue_document()
                     -- ตรวจแล้วว่าไม่ว่างก่อนเรียกมาถึงตรงนี้
                     'prefix_en',     coalesce(p.prefix_en, ''),
                     'first_name_en', coalesce(p.first_name_en, ''),
                     'last_name_en',  coalesce(p.last_name_en, ''),
                     'full_name_en',  trim(coalesce(p.prefix_en, '')
                                        || ' ' || coalesce(p.first_name_en, '')
                                        || ' ' || coalesce(p.last_name_en, ''))),
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end,
                             'type_en',       coalesce(pt.name_en, ''),
                             'name_en',       coalesce(pr.name_en, ''),
                             'track_en',      coalesce(ptr.name_en, ''),
                             'curriculum_en', coalesce(cur.name_en, ''),
                             'is_continuing', cur.is_continuing,
                             'qualification_en',
                               case pr.level
                                 when 'PVC' then 'Vocational Certificate'
                                 when 'PVS' then 'High Vocational Certificate'
                                 when 'TVB' then 'Bachelor of Technology'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t           on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none'))
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;
  -- ── ข้อความประจำสถานศึกษาและผลมาตรฐานวิชาชีพ ──────────────────────
  -- อยู่บนใบ รบ. และใบประกาศนียบัตรเท่านั้น ใบอื่นไม่ได้พิมพ์เกณฑ์การจบ
  if v_kind in ('transcript', 'certificate') then
    v_payload := v_payload || jsonb_build_object(
      'institution_text',
        coalesce((select jsonb_object_agg(
                           t.key,
                           jsonb_build_object('th', coalesce(t.text_th, ''),
                                              'en', coalesce(t.text_en, '')))
                    from institution_document_text t
                   where t.institution_id = v_inst), '{}'::jsonb),
      'professional_standard',
        (select jsonb_build_object(
                  'no',      coalesce(sg.professional_standard_no, ''),
                  -- null = ยังไม่ได้เข้ารับการประเมิน ซึ่งต่างจาก false
                  -- คือประเมินแล้วไม่ผ่าน สองอย่างนี้พิมพ์บนใบไม่เหมือนกัน
                  'passed',  sg.professional_standard_passed,
                  'on_date', sg.professional_standard_on)
           from student_graduation sg
          where sg.student_id = p_student_id
          order by sg.completed_on desc limit 1));
  end if;
  -- ── ระเบียนแสดงผลการเรียน — ต้องมีรายวิชาทั้งหมดและผลรายภาค ───────
  if v_kind in ('transcript', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'term_summaries',
        coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                    from (select ay.year_be, t.ordinal,
                                 'ภาคเรียนที่ ' || t.ordinal
                                   || ' ปีการศึกษา ' || ay.year_be as label,
                                 ts.gpa, ts.gpax, ts.credits_earned
                            from term_summary ts
                            join term t           on t.id  = ts.term_id
                            join academic_year ay on ay.id = t.academic_year_id
                           where ts.student_id = p_student_id) x), '[]'::jsonb),
      'courses',
        coalesce((select jsonb_agg(to_jsonb(td))
                    from transcript_data(p_student_id) td), '[]'::jsonb))
      -- ส่วนที่มีเฉพาะใบ รบ. อยู่ใน transcript_extra() (0059)
      -- เพิ่มช่องให้ใบ รบ. แก้ที่ฟังก์ชันนั้นที่เดียว ไม่ต้องเขียนตัวนี้ทับ
      || transcript_extra(p_student_id);
  end if;
  -- ── สมุดพก — ผลการเรียนประจำภาคพร้อมเวลาเรียนและความประพฤติ ───────
  if v_kind = 'grade_report' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
                  'gpa',     ts.gpa,
                  'gpax',    ts.gpax,
                  'credits_earned', ts.credits_earned)
           from term t
           join academic_year ay on ay.id = t.academic_year_id
           left join term_summary ts
                  on ts.term_id = t.id and ts.student_id = p_student_id
          where t.id = p_term_id),
      -- เวลาเรียนมาจาก v_enrollment_attendance ซึ่งเป็นค่าสด ณ เวลาออกใบ
      -- ต่างจากระเบียนแสดงผลการเรียนที่ใช้ attendance_pct ที่ตรึงตอนตัดเกรด
      -- เพราะสมุดพกมักออกกลางภาคตอนที่ยังไม่มีการตัดเกรด
      'term_courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'course_code',   c.code,
                           'course_name_th', c.name_th,
                           'credits',       c.credits,
                           'grade_symbol',  gsym.symbol,
                           'attendance_pct', v.pct_to_date,
                           'attendance_state', v.attendance_state,
                           'absences_left', v.absences_left)
                           order by c.code)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    left join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join enrollment_result er
                           on er.enrollment_id = e.id and er.superseded_by is null
                    left join grade_symbol gsym on gsym.id = er.grade_symbol_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'), '[]'::jsonb),
      'activities',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'sessions_required', cr.sessions_required,
                           'sessions_attended', cr.sessions_attended,
                           'result', cr.result))
                    from cocurricular_result cr
                   where cr.student_id = p_student_id
                     and cr.term_id = p_term_id), '[]'::jsonb));
  end if;
  -- ── ความประพฤติ — สมุดพกและระเบียนสะสมต้องมี ─────────────────────
  --
  -- behavior_record.points เป็นจำนวนบวกเสมอ (check points > 0 ใน 0011)
  -- ทิศทางหักหรือเพิ่มอยู่ที่ behavior_rule.direction ไม่ใช่ที่เครื่องหมาย
  -- ของตัวเลข การรวมยอดโดยดูเครื่องหมายจึงได้คำตอบผิดแบบดูไม่ออก —
  -- "หนีเรียน" จะกลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์อยู่บนกระดาษ
  --
  -- ยอดคงเหลือจึงอ่านจาก v_behavior_balance ซึ่งเป็นสูตรเดียวกับที่ระบบ
  -- เตือนก่อนออกกลางคันใช้ ไม่เขียนสูตรซ้ำที่นี่ให้มีโอกาสไม่ตรงกัน
  if v_kind in ('grade_report', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'behavior',
        (select jsonb_build_object(
                  'starting_points', bp.starting_points,
                  'deducted', coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'deduct'), 0),
                  'awarded',  coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'award'), 0),
                  'current',  (select vb.balance from v_behavior_balance vb
                                where vb.student_id = p_student_id),
                  'warn_below', bp.warn_below,
                  'critical_below', bp.critical_below)
           from behavior_policy bp
          where bp.institution_id = v_inst));
  end if;
  -- ── ระเบียนสะสม (ปพ.8) ────────────────────────────────────────────
  if v_kind = 'cumulative_record' then
    v_payload := v_payload || jsonb_build_object(
      'guardians',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'relation',  sg.relation,
                           'full_name', trim(coalesce(gp.prefix_th, '')
                                          || coalesce(gp.first_name_th, '')
                                          || ' ' || coalesce(gp.last_name_th, '')),
                           'phone',     coalesce(gp.phone, ''),
                           'is_primary', sg.is_primary)
                           order by sg.is_primary desc)
                    from student_guardian sg
                    join person gp on gp.id = sg.person_id
                   where sg.student_id = p_student_id
                     and sg.verified_at is not null), '[]'::jsonb),
      -- เก็บแค่ระดับผลกับวันที่ ไม่เก็บคำตอบรายข้อ (detail) โดยตั้งใจ
      -- ดูเหตุผลที่หัวไฟล์ — เอกสารนี้ลบไม่ได้และถูกส่งต่อกันไปเรื่อย ๆ
      'screenings',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'instrument',  sr.instrument,
                           'assessed_on', sr.assessed_on,
                           'band',        sr.band)
                           order by sr.assessed_on)
                    from screening_result sr
                   where sr.student_id = p_student_id), '[]'::jsonb),
      -- ส่ง direction ไปด้วยเสมอ เพราะ points เป็นบวกทั้งคู่
      -- ถ้าให้แม่แบบเดาเครื่องหมายเอง ใบจะพิมพ์ว่าหนีเรียนแล้วได้คะแนนเพิ่ม
      'behavior_history',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'occurred_on', br.occurred_on,
                           'points',      br.points,
                           'direction',   brl.direction,
                           'rule_th',     coalesce(brl.name_th, ''),
                           'document_no', coalesce(br.document_no, ''))
                           order by br.occurred_on)
                    from behavior_record br
                    left join behavior_rule brl on brl.id = br.rule_id
                   where br.student_id = p_student_id), '[]'::jsonb),
      'activities_all',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'result',        cr.result,
                           'term_label',    'ภาคเรียนที่ ' || t.ordinal
                                              || '/' || ay.year_be))
                    from cocurricular_result cr
                    join term t           on t.id  = cr.term_id
                    join academic_year ay on ay.id = t.academic_year_id
                   where cr.student_id = p_student_id), '[]'::jsonb),
      -- บันทึกเยี่ยมบ้านมีข้อค้นพบเป็นข้อความอิสระที่อ่อนไหวมาก
      -- ระเบียนสะสมจึงบันทึกแค่ว่า "เคยเยี่ยมกี่ครั้ง ครั้งล่าสุดเมื่อไร"
      'home_visits',
        (select jsonb_build_object(
                  'count', count(*),
                  'last_visited_on', max(hv.visited_on))
           from home_visit hv where hv.student_id = p_student_id));
  end if;
  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;
  return v_row;
end $$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0060_transcript_term_tree.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0060 — ใบ รบ. ตระกูล 62 จัดกลุ่มตามภาคเรียน ไม่ใช่ตามหมวดวิชา
--
-- ═══ ทำไมต้องมีโครงชุดที่สอง ไม่ใช่จัดเรียง category_tree ใหม่ ═══
-- ตระกูล 67 สรุป **หน่วยกิตและคะแนนเฉลี่ยรายกลุ่มวิชา/รายหมวด**
-- ตระกูล 62 สรุป **รายภาคเรียน** และมีคอลัมน์ที่ตระกูล 67 ไม่มีเลยคือ
-- ผลคูณ (1)×(2) = หน่วยกิต × ระดับผลการเรียน
-- สองอย่างนี้เป็นตัวเลขคนละชุดที่คำนวณคนละแบบ ไม่ใช่ข้อมูลเดียวกันที่
-- เรียงต่างกัน — จัดเรียงใหม่จาก category_tree ให้ตัวเลขสรุปไม่ได้เลย
--
-- ═══ ทำไมผลคูณต้องมาจากฐานข้อมูล ไม่ใช่ให้แม่แบบคูณเอง ═══
-- ตัวเลขในคอลัมน์นั้นคือ **ตัวตั้งของสูตร GPA** พอดี —
-- `compute_term_summary()` ใช้ `sum(grade_point * course.credits)
-- filter (where counts_in_gpa)` เป็นเศษ แล้วหารด้วยหน่วยกิตที่นับ
-- ถ้าแม่แบบคูณเอง มันจะไม่รู้เรื่อง `counts_in_gpa` แล้ววิชา ผ./ม.ผ.
-- จะได้ผลคูณเป็น 0 ทั้งที่ใบจริงพิมพ์ "-" — ผลคือคอลัมน์ที่พิมพ์อยู่
-- ข้าง ๆ GPA บวกแล้วไม่ตรงกับ GPA ที่พิมพ์อยู่บรรทัดล่าง **บนกระดาษ
-- ใบเดียวกัน** ซึ่งเป็นความขัดแย้งที่คนถือใบเห็นเองได้
--
-- ═══ และแก้ข้อสรุปผิดของ 0059 ═══
-- 0059 เขียนไว้ว่าฉบับอังกฤษของ ปวส. **ต่อเนื่อง** ใช้ชื่อเรื่องเดียวกับ
-- ปวส. ปกติ ซึ่งผิด — บรรทัดชื่อเรื่องเหมือนกันจริง แต่มีอีกบรรทัดอยู่ใต้
-- ลงมาว่า "(CONTINUING PROGRAM)" ถ้าไม่มี ใบจะไม่ได้บอกเลยว่าเป็นหลักสูตร
-- ต่อเนื่อง ทั้งที่ฉบับไทยบอกด้วยคำว่า "(ต่อเนื่อง)" ในชื่อเรื่อง
-- (แก้ที่แม่แบบ ไม่ใช่ที่สคีมา — `curriculum.is_continuing` ของ 0059 ถูกแล้ว)
--
-- ═══ ที่ตรวจเจอระหว่างทาง — หน่วยกิตสะสมของตระกูล 67 พิมพ์ผิดมาตลอด ═══
-- แม่แบบ 67 พิมพ์ "หน่วยกิตที่ได้ในภาค" กับ "หน่วยกิตสะสม" จากค่าเดียวกัน
-- คือ `credits_earned` ของภาคนั้น ภาคที่สองจึงพิมพ์ 11/11 แทนที่จะเป็น
-- 11/28 — เป็นตัวเลขผิดบนเอกสารที่แก้ไม่ได้ ไม่มีเทสต์ไหนจับได้เพราะ
-- ไม่มีใครเทียบตัวเลขสองตัวนั้นกับใบจริง เจอตอนวัดไฟล์ตระกูล 62
-- ซึ่งพิมพ์คู่นี้ไว้ท้ายทุกภาคเรียน (17/17 · 11/28 · 3/31)
-- ═══════════════════════════════════════════════════════════════════

begin;

/* ═══════════════════════════════════════════════════════════════════
 * ฉบับอังกฤษออกไม่ได้เลยเมื่อสายไทยเดินนำไปแล้ว
 *
 * 0057 แยกตัวนับของสองภาษาออกจากกันสำเร็จ แต่ให้ทั้งสองสายใช้ **คำนำหน้า
 * เดียวกันคือปีการศึกษา** และตัวนับของทั้งคู่เริ่มที่ 1 ผลคือเลขที่ที่
 * *พิมพ์ลงกระดาษ* ชนกัน — ฉบับอังกฤษใบแรกได้ "256900001" ซึ่งฉบับไทย
 * ใช้ไปแล้ว แล้ว unique (institution_id, kind, doc_no, copy_no) ปฏิเสธ
 *
 * ─── ทำไมเทสต์ของ 0057 ไม่จับ ───
 * TEST 258/259 ออกฉบับไทยไปหลายใบก่อนแล้วจึงออกฉบับอังกฤษใบแรก เลข
 * ที่ได้จึงเป็น 256900005 กับ 256900001 ซึ่ง "ต่างกัน" ตามที่เทสต์ตรวจ
 * — เทสต์ตรวจว่าเลข**ไม่เท่ากัน** ซึ่งเป็นจริงเสมอในช่วงที่สายหนึ่งนำอยู่
 * ทั้งที่สิ่งที่ต้องพิสูจน์คือสองสาย**ไม่มีวันชนกัน** ต่างกันคนละเรื่อง
 * ความผิดพลาดโผล่ตอนสายอังกฤษไล่ทันเลขที่สายไทยเคยใช้ ซึ่งเกิดแน่นอน
 * เพราะทั้งคู่เริ่มที่ 1
 *
 * ─── ทำไมแก้ที่คำนำหน้า ไม่ใช่เพิ่ม lang เข้าไปใน unique ───
 * เพิ่ม lang เข้า unique จะได้เอกสารสองใบที่**พิมพ์เลขเดียวกัน** คนที่
 * ถือใบมาตรวจสอบด้วยเลขที่จะเจอสองรายการโดยไม่รู้ว่าต้องดูใบไหน
 * เลขที่บนกระดาษต้องชี้ไปที่ใบเดียวเสมอ (SISA เองก็เดินคนละสายจริง —
 * ฟิลด์ `eng_mass_transcript_no` แยกจากสายไทย)
 *
 * ─── และทำไมยอมให้สายอังกฤษมีตัวอักษรได้ ───
 * `certificate_prefix_digits_only` มาจากระเบียบกระทรวงซึ่งบังคับ
 * **ใบประกาศนียบัตรฉบับที่ยื่นต่อ สอศ.** ซึ่งเป็นฉบับไทย ส่วนฉบับอังกฤษ
 * เป็นเอกสารที่ออกให้ผู้ถือไปใช้ต่อ ไม่ใช่ตัวที่ยื่นตามระเบียบ
 * จึงจำกัดข้อบังคับให้เหลือเฉพาะสายไทย
 * ═══════════════════════════════════════════════════════════════════ */
alter table document_series drop constraint if exists certificate_prefix_digits_only;
alter table document_series add constraint certificate_prefix_digits_only
  check (kind <> 'certificate' or lang <> 'th' or prefix ~ '^[0-9]*$');

-- สายอังกฤษที่สร้างไปแล้วด้วยคำนำหน้าเดิม ต้องย้ายก่อนที่จะไปชนของไทย
update document_series
   set prefix = 'E' || year_be::text
 where lang <> 'th' and prefix = year_be::text;

create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text default 'th'
) returns text language plpgsql as $$
declare
  v_inst   uuid := current_institution_id();
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  /*
   * คำนำหน้าตั้งต้นเป็นปีการศึกษา เพราะ `issued_document` มี
   * unique (institution, kind, doc_no, copy_no) ซึ่ง **ไม่มีปีการศึกษา
   * อยู่ในนั้น** ส่วนตัวนับเริ่มที่ 1 ใหม่ทุกปี — ถ้าไม่มีคำนำหน้า
   * ใบแรกของปีการศึกษาใหม่จะล้มด้วย duplicate key (0057)
   *
   * และสายที่ไม่ใช่ภาษาไทยเติม "E" นำหน้าด้วยเหตุผลเดียวกันพอดี คือ
   * ตัวนับของแต่ละสายเริ่มที่ 1 เหมือนกัน จึงชนกันแน่นอนเมื่อไล่ทัน
   */
  insert into document_series (institution_id, kind, year_be, lang, prefix)
  values (v_inst, p_kind, p_year_be, p_lang,
          case when p_lang = 'th' then p_year_be::text
               else 'E' || p_year_be::text end)
  on conflict (institution_id, kind, year_be, lang) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = v_inst and kind = p_kind
     and year_be = p_year_be and lang = p_lang
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint, text) is
  'จ่ายเลขที่เอกสารจากสายที่แยกตามสถานศึกษา ประเภท ปีการศึกษา และภาษา — สายที่ไม่ใช่ไทยมีคำนำหน้า E เพราะตัวนับทุกสายเริ่มที่ 1 จึงชนกันแน่นอนถ้าใช้คำนำหน้าเดียวกัน';


/*
 * transcript_data() เพิ่มสามคอลัมน์
 *
 * `term_id`        — เพื่อจับคู่กับ term_summary ได้ตรง ๆ โดยไม่ต้องเดา
 *                    จากปี+ลำดับ ซึ่งซ้ำกันได้ข้ามภาคฤดูร้อน
 * `counts_in_gpa`  — ใบตระกูล 62 พิมพ์ "-" ทั้งช่องหน่วยกิตและช่องผลคูณ
 *                    ให้วิชาที่ไม่นับ GPA (วัดจากไฟล์จริง: กิจกรรมลูกเสือ
 *                    ได้ ผ. พิมพ์ "-" ไม่ใช่ "0")
 * `grade_points`   — ผลคูณที่เป็นตัวตั้งของ GPA (ดูเหตุผลที่หัวไฟล์)
 *
 * ─── counts_in_gpa เป็น "และ" ของสองเงื่อนไข ไม่ใช่คอลัมน์เดียว ───
 * `compute_term_summary()` กรองด้วย **ทั้ง** `grade_symbol.counts_in_gpa`
 * และ `enrollment.counts_toward_gpa` — ตัวหลังเป็น false สำหรับรายวิชา
 * ปรับพื้นฐานและรายวิชาเทียบโอน ซึ่งเป็นกรณีปกติของนักศึกษา ปวส.
 * ที่จบ ปวช. มา ถ้าส่งมาแค่ตัวแรก คอลัมน์ผลคูณจะรวมวิชาเทียบโอนเข้าไป
 * แล้วบวกไม่ตรงกับ GPA ที่พิมพ์อยู่บรรทัดถัดไป — และจะเกิดกับใบของ
 * นักศึกษา ปวส. **เกือบทุกใบ** ส่งมาค่าเดียวที่ตอบคำถามที่กระดาษถามจริง
 * คือ "แถวนี้ถูกนับใน GPA ที่พิมพ์อยู่ข้างล่างหรือไม่"
 *
 * ต้อง drop ก่อนเพราะ `create or replace` เปลี่ยนรายการคอลัมน์ของ
 * `returns table` ไม่ได้ — เพิ่มไว้ท้ายสุดเพื่อไม่ให้ตำแหน่งเดิมขยับ
 */
drop function if exists transcript_data(uuid);

create function transcript_data(p_student_id uuid)
returns table (
  year_be        smallint,
  term_ordinal   smallint,
  term_label     text,
  course_code    text,
  course_name_th text,
  credits        numeric(3,1),
  grade_symbol   text,
  grade_point    numeric(2,1),
  credits_earned numeric(3,1),
  category_th    text,
  term_id        uuid,
  course_name_en text,
  counts_in_gpa  boolean,
  grade_points   numeric
) language sql stable as $$
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    c.code,
    c.name_th,
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    cat.name_th,
    t.id,
    coalesce(c.name_en, ''),
    (gsym.counts_in_gpa and e.counts_toward_gpa),
    -- สูตรเดียวกับเศษของ GPA ใน compute_term_summary() ตัวต่อตัว
    case when gsym.counts_in_gpa and e.counts_toward_gpa
         then er.grade_point * c.credits end
  from enrollment e
  join class_section cs      on cs.id = e.class_section_id
  join course c              on c.id  = cs.course_id
  join term t                on t.id  = e.term_id
  join academic_year ay      on ay.id = t.academic_year_id
  join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym     on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by ay.year_be, t.ordinal, c.code;
$$;

comment on function transcript_data(uuid) is
  'รายวิชาทั้งหมดที่ขึ้นระเบียนแสดงผลการเรียน — ใช้ผลฉบับปัจจุบันและค่าที่ตรึงไว้แล้วเท่านั้น · grade_points คือตัวตั้งของ GPA จึงต้องคิดที่นี่ที่เดียว';


/*
 * โครงภาคเรียน → รายวิชา พร้อมสรุปสี่ตัวเลขท้ายภาค
 *
 * ─── ทำไม credits_cum เป็น null ได้ ───
 * ค่าสะสมคือผลรวมของ `term_summary.credits_earned` ย้อนหลังทุกภาค
 * ถ้ามีภาคไหนยังไม่ได้ตัดยอด (ไม่มีแถวใน term_summary) ผลรวมจะขาดไป
 * เท่ากับหน่วยกิตของภาคนั้นโดยไม่มีอะไรฟ้อง — ใบจะพิมพ์ตัวเลขที่ต่ำกว่า
 * ความจริงและดูสมเหตุสมผลทุกประการ จึงคืน null ให้แม่แบบพิมพ์ "-"
 * ซึ่งอ่านออกว่า "ยังไม่รู้" ต่างจากตัวเลขผิดที่อ่านไม่ออกว่าผิด
 */
create or replace function transcript_term_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  with c as (select * from transcript_data(p_student_id)),
  t as (
    select c.term_id,
           min(c.year_be)      as year_be,
           min(c.term_ordinal) as ordinal
      from c
     group by c.term_id
  ),
  s as (
    select t.term_id, t.year_be, t.ordinal,
           ts.credits_earned, ts.gpa, ts.gpax,
           (ts.student_id is not null) as has_summary,
           case when bool_and(ts.student_id is not null)
                     over (order by t.year_be, t.ordinal)
                then sum(ts.credits_earned)
                     over (order by t.year_be, t.ordinal)
           end as credits_cum
      from t
      left join term_summary ts
             on ts.term_id = t.term_id
            and ts.student_id = p_student_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        -- ไม่ส่งข้อความหัวภาคมาด้วย เพราะฉบับอังกฤษเขียน
        -- "Academic year 2025  1st Semester" คือใช้ **ปีคริสต์ศักราช**
        -- การประกอบข้อความจึงเป็นเรื่องของแม่แบบแต่ละภาษา
        'year_be',        s.year_be,
        'ordinal',        s.ordinal,
        'credits_earned', s.credits_earned,
        'credits_cum',    s.credits_cum,
        'has_summary',    s.has_summary,
        'gpa',            s.gpa,
        'gpax',           s.gpax,
        'courses',
          coalesce((select jsonb_agg(jsonb_build_object(
                             'code',        c.course_code,
                             'name_th',     c.course_name_th,
                             'name_en',     c.course_name_en,
                             'credits',     c.credits,
                             'grade',       c.grade_symbol,
                             'grade_point', c.grade_point,
                             'grade_points', c.grade_points,
                             'counts_in_gpa', c.counts_in_gpa,
                             'credits_earned', c.credits_earned)
                             order by c.course_code)
                     from c where c.term_id = s.term_id), '[]'::jsonb))
      order by s.year_be, s.ordinal),
    '[]'::jsonb)
  from s
$$;

comment on function transcript_term_tree(uuid) is
  'โครงปีการศึกษา → ภาคเรียน → รายวิชา พร้อมสรุปสี่ตัวเลขท้ายภาค สำหรับใบ รบ. ตระกูล 62 — credits_cum เป็น null เมื่อมีภาคที่ยังไม่ได้ตัดยอด';


/*
 * คะแนนเฉลี่ยรายกลุ่มของตระกูล 67 เคยรวมวิชาเทียบโอนเข้าไปด้วย
 *
 * 0058 กรองด้วย `grade_symbol.counts_in_gpa` อย่างเดียว ขาด
 * `enrollment.counts_toward_gpa` ไป ผลคือคะแนนเฉลี่ยรายกลุ่มบนใบไม่ตรงกับ
 * GPAX ที่พิมพ์อยู่หัวใบเดียวกัน สำหรับนักศึกษาที่มีวิชาเทียบโอนหรือ
 * วิชาปรับพื้นฐาน ซึ่งคือ **นักศึกษา ปวส. เกือบทุกคน**
 *
 * เขียนทับทั้งฟังก์ชันเพราะ `returns table` แก้เฉพาะเงื่อนไขไม่ได้
 */
create or replace function transcript_courses_grouped(p_student_id uuid)
returns table (
  head_code   text,
  head_name   text,
  head_sort   smallint,
  head_min    numeric,
  group_code  text,
  group_name  text,
  group_sort  smallint,
  group_min   numeric,
  year_be     smallint,
  term_ordinal smallint,
  term_label  text,
  course_code text,
  course_name_th text,
  course_name_en text,
  credits     numeric,
  grade_symbol text,
  grade_point numeric,
  credits_earned numeric,
  counts_in_gpa boolean
) language sql stable as $$
  select
    coalesce(head.code, 'UNSORTED')            as head_code,
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as head_name,
    coalesce(head.sort_order, 99)::smallint    as head_sort,
    head.min_credits                           as head_min,
    coalesce(grp.code, head.code, 'UNSORTED')  as group_code,
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as group_name,
    coalesce(grp.sort_order, 0)::smallint      as group_sort,
    coalesce(grp.min_credits, head.min_credits) as group_min,
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    (gsym.counts_in_gpa and e.counts_toward_gpa)
  from enrollment e
  join class_section cs     on cs.id = e.class_section_id
  join course c             on c.id  = cs.course_id
  join term t               on t.id  = e.term_id
  join academic_year ay     on ay.id = t.academic_year_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym    on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by coalesce(head.sort_order, 99), coalesce(grp.sort_order, 0),
           ay.year_be, t.ordinal, c.code
$$;


/*
 * ตระกูล 67 ต้องรู้ counts_in_gpa ด้วย
 *
 * ใบจริงของตระกูล 67 พิมพ์ "-" ในช่องหน่วยกิตของวิชากิจกรรมเหมือนกัน
 * (วัดจาก `ระเบียนแสดงผลการเรียน…(ปวช. 67).pdf` หน้า 2 — กิจกรรมลูกเสือ
 * วิสามัญพิมพ์ "-" กับ "ผ.") แต่ payload เดิมไม่ได้ส่งสิ่งที่ใช้ตัดสิน
 * มาเลย แม่แบบจึงพิมพ์หน่วยกิตจริงของรายวิชาแทน
 */
create or replace function transcript_category_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(head order by head ->> 'sort'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'code',        h.head_code,
               'name_th',     h.name_th,
               'sort',        h.sort_key,
               'min_credits', h.min_credits,
               'credits_earned', h.credits_earned,
               'gpa',         h.gpa,
               'groups',
                 coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'code',        g.group_code,
                            'name_th',     g.name_th,
                            'sort',        g.sort_key,
                            'min_credits', g.min_credits,
                            'credits_earned', g.credits_earned,
                            'gpa',         g.gpa,
                            'courses',
                              coalesce((
                                select jsonb_agg(jsonb_build_object(
                                         'term_label',  c.term_label,
                                         'year_be',     c.year_be,
                                         'term_ordinal', c.term_ordinal,
                                         'code',        c.course_code,
                                         'name_th',     c.course_name_th,
                                         'name_en',     c.course_name_en,
                                         'credits',     c.credits,
                                         'grade',       c.grade_symbol,
                                         'grade_point', c.grade_point,
                                         'grade_points',
                                           case when c.counts_in_gpa
                                                then c.grade_point * c.credits end,
                                         'counts_in_gpa', c.counts_in_gpa,
                                         'credits_earned', c.credits_earned)
                                         order by c.year_be, c.term_ordinal, c.course_code)
                                  from transcript_courses_grouped(p_student_id) c
                                 where c.head_code = h.head_code
                                   and c.group_code = g.group_code), '[]'::jsonb))
                          order by g.sort_key)
                     from transcript_category_summary(p_student_id) g
                    where g.level = 'group' and g.head_code = h.head_code), '[]'::jsonb)) as head
        from transcript_category_summary(p_student_id) h
       where h.level = 'head'
    ) x
$$;


/*
 * เพิ่ม term_tree ลง payload ของใบ รบ.
 *
 * นี่คือรอบแรกที่ได้ใช้สิ่งที่ 0059 แยกไว้ — เพิ่มช่องให้ใบ รบ. โดย
 * **ไม่ต้องเขียน issue_document_core() ทับทั้ง 300 บรรทัด** ซึ่งเป็นสิ่งที่
 * 0057 และ 0058 ต้องทำทั้งคู่เพื่อเพิ่มบรรทัดเดียว
 *
 * ทั้งสองโครงอยู่ในใบเดียวกันโดยตั้งใจ ไม่ได้เลือกอย่างใดอย่างหนึ่งตาม
 * รุ่นหลักสูตร เพราะ payload ตรึงแล้วแก้ไม่ได้ — วันที่วิทยาลัยขอพิมพ์ซ้ำ
 * เป็นอีกแบบ (ซึ่งเกิดจริง เช่นส่งให้ที่ทำงานขอฉบับที่จัดตามภาคเรียน)
 * ใบที่เก็บโครงเดียวจะพิมพ์แบบนั้นไม่ได้เลยตลอดไป ต้นทุนของการเก็บทั้งสอง
 * โครงคือ jsonb ที่ใหญ่ขึ้นราวเท่าตัวของส่วนรายวิชา ซึ่งถูกกว่ามาก
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'term_tree',     transcript_term_tree(p_student_id),
    /*
     * ─── "หน่วยกิตที่เรียน" กับ "หน่วยกิตที่ได้" เป็นคนละตัวเลข ───
     * ใบจริงพิมพ์ทั้งคู่ติดกัน (ฉบับอังกฤษคือ Credits Enrolled 34 กับ
     * Total Credits 31) แต่ payload มีแค่ตัวหลัง แม่แบบทั้งสองตระกูลจึง
     * พิมพ์ค่าเดียวกันสองครั้ง — ใบบอกว่าลงเรียนเท่ากับที่ได้ทุกใบ
     * แปลว่าไม่เคยตกและไม่เคยถอนรายวิชาสักตัว ซึ่งอ่านแล้วดูสมเหตุสมผล
     * และตรวจไม่ได้ถ้าไม่มีอย่างอื่นให้เทียบ (รูปเดียวกับหน่วยกิตสะสม)
     *
     * เป็น null เมื่อยังไม่มีภาคไหนตัดยอด — พิมพ์ "-" ดีกว่าพิมพ์ 0
     */
    'credits_attempted',
      (select sum(ts.credits_attempted) from term_summary ts
        where ts.student_id = p_student_id),
    'prior_education',
      (select jsonb_build_object(
                'level_th',   pe.level_th,
                'school_th',  coalesce(pe.school_th, ''),
                'province_th', coalesce(pe.province_th, ''),
                'program_th', coalesce(pe.program_th, ''),
                'year_be',    pe.completed_year_be,
                'gpax',       pe.gpax)
         from student_prior_education pe
        where pe.student_id = p_student_id
        order by pe.completed_year_be desc nulls last, pe.level_th desc
        limit 1))
$$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0061_national_id_on_transcript.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0061 — เลขประจำตัวประชาชนบนใบ รบ.
--
-- ═══ ทำไมนี่คือตัวบล็อกที่หนักที่สุดของงานเอกสารทั้งหมด ═══
-- ใบ รบ. ทุกรูปแบบที่วัดจากไฟล์จริง **พิมพ์เลขบัตรประชาชนเต็ม** บนหน้าแรก
-- ระบบเราเก็บแค่ค่าแฮชมาตั้งแต่ 0002 ผลคือแม่แบบทั้งสี่แบบที่ทำเสร็จแล้ว
-- พิมพ์ช่องนั้นว่างทุกใบ — ใบที่สวยงามครบถ้วนแต่**ใช้ยื่นจริงไม่ได้เลย**
-- ซึ่งเป็นเหตุผลเดียวที่ใบ รบ. มีอยู่
--
-- ═══ สิ่งที่ไฟล์นี้ทำและไม่ทำ ═══
-- ทำ    — พา `person.national_id_enc` (มีมาตั้งแต่ 0002 แต่ไม่เคยมีใคร
--         เขียนลงไปเลย) เข้าไปอยู่ใน payload ของใบ รบ. ในรูปแบบที่ยัง
--         **เข้ารหัสอยู่** และบันทึกรุ่นของค่าแฮชไว้ให้รู้ว่าแถวไหนใช้
--         ค่าแฮชแบบเก่าที่ไม่มีกุญแจ
-- ไม่ทำ — การเข้ารหัส/ถอดรหัส ซึ่งอยู่ที่ชั้น API เพราะกุญแจต้องอยู่
--         **นอกฐานข้อมูล** มิฉะนั้นจะรั่วไปพร้อมกับ dump แล้วการเข้ารหัส
--         กลายเป็นของประดับ (ข้อยกเว้นของหลักข้อ 1 ที่ตั้งใจ — หลักเดียว
--         กับ MFA_SECRET_KEY ที่ทำแบบนี้อยู่แล้ว)
--
-- ═══ ทำไม payload เก็บค่าที่เข้ารหัส ไม่ใช่เลขเปล่า ═══
-- `issued_document.payload` **ลบไม่ได้และแก้ไม่ได้** การเก็บเลขบัตรเป็น
-- ข้อความเปล่าแปลว่าทุกใบที่เคยออกกลายเป็นคลังเลขบัตรที่เอาออกไม่ได้อีกเลย
-- ซึ่งขัดกับหลักข้อ 5ก ตรง ๆ
--
-- เก็บค่าที่เข้ารหัสแทน ให้ผลครบทั้งสองด้าน — กระดาษได้เลขจริงเพราะชั้น
-- API ถอดตอนพิมพ์ · ฐานข้อมูลไม่เคยมีเลขเปล่าอยู่เลย · และการพิมพ์ซ้ำ
-- ยังได้เลขเดิมเป๊ะเพราะเป็นไบต์ชุดเดิม (หลักข้อ 5)
--
-- ═══ และค่าแฮชเดิมป้องกันอะไรไม่ได้เลย ═══
-- 0023 กับ 0053 เขียน `digest(national_id, 'sha256')` คือแฮชเปล่าไม่มีกุญแจ
-- ทั้งที่คอมเมนต์ของ 0002 เขียนว่า "HMAC-SHA256" — เลขบัตรประชาชนไทยมี
-- ความเป็นไปได้ราว 10¹² ค่า ไล่ครบด้วยการ์ดจอใบเดียวในเวลาไม่กี่นาที
-- "เก็บแค่ค่าแฮช" จึงไม่ใช่การป้องกัน เป็นแค่การเปลี่ยนรูปแบบ
--
-- **คอมเมนต์บอกเจตนา โค้ดบอกความจริง** — รูปเดียวกับข้อ 9 ในรายการที่
-- เคยพังแบบเงียบ ๆ ตอนนี้แฮชด้วยกุญแจที่ชั้น API และคอลัมน์ใหม่บอกว่า
-- แถวไหนยังเป็นของเก่า เพราะแฮชแบบเก่าย้อนกลับไม่ได้แล้ว
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * รุ่นของค่าแฮช — 1 คือ sha256 เปล่า (เดิม) · 2 คือ HMAC ที่มีกุญแจ
 *
 * ต้องรู้เป็นรายแถวเพราะแถวเก่าแปลงเป็นรุ่น 2 ไม่ได้ถ้าไม่มีเลขต้นฉบับ
 * ซึ่งอยู่นอกระบบไปแล้ว การเดาเอาว่า "ทุกแถวเป็นรุ่นใหม่" จะทำให้การ
 * ตรวจซ้ำเงียบ ๆ ไม่เจอคนเดิม แล้วออกรหัสนักศึกษาซ้ำให้คนคนเดียวกัน
 */
alter table person
  add column if not exists national_id_hash_v smallint not null default 1
    check (national_id_hash_v in (1, 2));

comment on column person.national_id_hash_v is
  'รุ่นของค่าแฮชเลขบัตร — 1 = sha256 เปล่า (ย้อนกลับได้ ห้ามถือว่าปลอดภัย) · 2 = HMAC ที่มีกุญแจนอกฐานข้อมูล';

comment on column person.national_id_enc is
  'เลขบัตรประชาชนที่เข้ารหัสด้วย AES-256-GCM ที่ชั้น API — กุญแจอยู่นอกฐานข้อมูลโดยตั้งใจ ห้ามทำดัชนีบนคอลัมน์นี้';

alter table student_parent
  add column if not exists national_id_hash_v smallint not null default 1
    check (national_id_hash_v in (1, 2));

/*
 * ─── ทำไมไม่เก็บของบิดามารดาเป็นค่าที่เข้ารหัสด้วย ───
 * ใบ รบ. พิมพ์แค่**ชื่อ**บิดามารดา ไม่ได้พิมพ์เลขบัตรของท่าน
 * การเก็บค่าที่ถอดกลับได้ของคนที่เอกสารไม่ได้แสดง คือการเก็บเกินจำเป็น
 * (หลักข้อ 5ก) — เก็บค่าแฮชไว้กันซ้ำอย่างเดียวพอ แต่ต้องเป็นแฮชที่มีกุญแจ
 */
comment on column student_parent.national_id_hash_v is
  'รุ่นของค่าแฮช — ฝั่งบิดามารดาไม่มีค่าที่ถอดกลับได้โดยตั้งใจ เพราะใบ รบ. พิมพ์แค่ชื่อ ไม่ได้พิมพ์เลขบัตร';

commit;


-- ═══════════════════════════════════════════════════════════════════
-- ใส่ค่าที่เข้ารหัสลง payload ของใบ รบ.
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * รอบที่สองที่ได้ใช้สิ่งที่ 0059 แยกไว้ — เพิ่มช่องให้ใบ รบ. โดยไม่ต้อง
 * เขียน issue_document_core() ทับทั้ง 300 บรรทัด
 *
 * ส่งเป็นข้อความฐานสิบหกเพราะ jsonb ไม่มีชนิดไบต์ และ `encode(..., 'hex')`
 * ให้ค่าที่กลับไปเป็นไบต์ชุดเดิมได้เป๊ะ ต่างจาก base64 ที่มีอักขระซึ่ง
 * ต้อง escape ใน JSON บางตัว
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'term_tree',     transcript_term_tree(p_student_id),
    'credits_attempted',
      (select sum(ts.credits_attempted) from term_summary ts
        where ts.student_id = p_student_id),
    /*
     * ─── เก็บค่าที่เข้ารหัส ไม่ใช่เลขเปล่า ───
     * payload ลบไม่ได้ ถ้าเก็บเลขเปล่า ทุกใบที่เคยออกจะกลายเป็นคลัง
     * เลขบัตรที่เอาออกไม่ได้อีกเลย (หลักข้อ 5ก) — ชั้น API ถอดตอนพิมพ์
     * แล้วเลขไปอยู่บนกระดาษอย่างเดียว ไม่เคยถูกเขียนกลับลงฐานข้อมูล
     *
     * null เมื่อยังไม่ได้กรอก — แม่แบบพิมพ์ช่องว่างไว้เหมือนเดิม
     * ซึ่งอ่านออกว่า "ยังกรอกไม่ครบ" ต่างจากการซ่อนหัวข้อทิ้ง
     */
    'national_id_enc',
      (select encode(p.national_id_enc, 'hex')
         from student s join person p on p.id = s.person_id
        where s.id = p_student_id),
    'prior_education',
      (select jsonb_build_object(
                'level_th',   pe.level_th,
                'school_th',  coalesce(pe.school_th, ''),
                'province_th', coalesce(pe.province_th, ''),
                'program_th', coalesce(pe.program_th, ''),
                'year_be',    pe.completed_year_be,
                'gpax',       pe.gpax)
         from student_prior_education pe
        where pe.student_id = p_student_id
        order by pe.completed_year_be desc nulls last, pe.level_th desc
        limit 1))
$$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0062_transcript_header_fields.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0062 — ช่องบนหัวใบ รบ. ที่พิมพ์อยู่บนกระดาษแต่ payload ไม่เคยมี
--
-- ═══ อาการ ═══
-- แม่แบบใบ รบ. พิมพ์หัวข้อ "จังหวัด" · "เชื้อชาติ สัญชาติ ศาสนา" ·
-- "ชื่อบิดา" · "ชื่อมารดา" · "กลุ่มอาชีพ" · "ออกจากสถานศึกษาเมื่อ" ·
-- "เหตุที่ออก" ไว้ครบ แล้วเว้นค่าว่างไว้ทุกใบ — เพราะแม่แบบ**ฮาร์ดโค้ด
-- ค่าว่าง**ลงไปตรง ๆ ไม่ใช่เพราะฐานข้อมูลไม่มีข้อมูล
--
-- ข้อมูลส่วนใหญ่มีอยู่แล้วตั้งแต่ 0053 (`person_sensitive` · `student_parent` ·
-- `person.nationality`) และ 0002 (`student_status_history`) แต่ไม่เคยมีใคร
-- ต่อสายจากตารางพวกนั้นมาถึง payload ของใบ รบ. เลย
--
-- **เป็นรูปเดียวกับข้อ 8 และข้อ 15 ในรายการ "พังแบบเงียบ ๆ"** — ของที่
-- ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น ต่างกันแค่ที่นี่
-- เจตนาถูกประกาศไว้บน**กระดาษที่ส่งให้คนอื่น** ไม่ใช่ในคอมเมนต์
--
-- ═══ สองช่องที่ไม่มีที่เก็บจริง ═══
-- `จังหวัด` ของสถานศึกษา กับ `กลุ่มอาชีพ` ของสาขาวิชา — ค้นทั้งสคีมาแล้ว
-- ไม่มีคอลัมน์ไหนเก็บ (docs/transcript-formats.md ระบุไว้ว่า "ไม่มี")
-- จึงเพิ่มคอลัมน์ให้ที่ตารางที่เป็นเจ้าของเรื่องนั้นจริง ๆ
--
-- ═══ PDPA — ทำไมข้อมูลอ่อนไหวลง payload ได้ ═══
-- หลักข้อ 5ก บอกว่า payload ต้องมี**เฉพาะสิ่งที่กระดาษใบนั้นแสดง**
-- เชื้อชาติ ศาสนา และชื่อบิดามารดา **พิมพ์อยู่บนใบ รบ. จริง** (วัดจากไฟล์
-- ต้นฉบับใน pdf/) จึงเข้าเงื่อนไข — ต่างจากผลคัดกรอง SDQ หรือบันทึก
-- เยี่ยมบ้านที่ใบไม่ได้แสดงและห้ามคัดลอกลงมาเด็ดขาด
-- และเพราะ payload ลบไม่ได้ จึงเก็บเฉพาะสามช่องนี้ ไม่ใช่ทั้ง
-- `person_sensitive` ซึ่งมีหมู่เลือด โรคประจำตัว และความพิการอยู่ด้วย
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ── จังหวัดของสถานศึกษา ────────────────────────────────────────────
-- อยู่บน `institution` เพราะเป็นข้อเท็จจริงของสถานศึกษา ไม่ใช่ข้อความ
-- ที่วิทยาลัยเขียนเอง (ซึ่งจะไปอยู่ `institution_document_text`)
alter table institution add column if not exists province_th text;

comment on column institution.province_th is
  'จังหวัดที่ตั้งสถานศึกษา — พิมพ์บนหัวใบ รบ. ใต้ชื่อสถานศึกษา';

-- ── กลุ่มอาชีพ ─────────────────────────────────────────────────────
-- ใบ ปวช.67 มีช่องนี้อยู่ระหว่าง "ประเภทวิชา" กับ "สาขาวิชา"
-- จึงเป็นคุณสมบัติของ program (สาขาวิชา) ไม่ใช่ของนักศึกษา
alter table program add column if not exists career_group_th text;

comment on column program.career_group_th is
  'กลุ่มอาชีพตามการจัดกลุ่มของ สอศ. — พิมพ์บนหัวใบ รบ. ระหว่างประเภทวิชากับสาขาวิชา';

-- ── ต่อสายจากตารางที่มีข้อมูลอยู่แล้วมาถึง payload ของใบ รบ. ────────
/*
 * เพิ่มช่องให้ใบ รบ. แก้ที่ `transcript_extra()` ที่เดียวตามที่ 0059 วางไว้
 * — ไม่ต้องเขียน `issue_document_core()` ทับทั้ง 300 บรรทัดอีก
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'term_tree',     transcript_term_tree(p_student_id),
    'credits_attempted',
      (select sum(ts.credits_attempted) from term_summary ts
        where ts.student_id = p_student_id),
    /*
     * เก็บค่าที่เข้ารหัส ไม่ใช่เลขเปล่า — payload ลบไม่ได้ (0061)
     * ชั้น API ถอดตอนพิมพ์แล้วเลขไปอยู่บนกระดาษอย่างเดียว
     */
    'national_id_enc',
      (select encode(p.national_id_enc, 'hex')
         from student s join person p on p.id = s.person_id
        where s.id = p_student_id),
    'prior_education',
      (select jsonb_build_object(
                'level_th',   pe.level_th,
                'school_th',  coalesce(pe.school_th, ''),
                'province_th', coalesce(pe.province_th, ''),
                'program_th', coalesce(pe.program_th, ''),
                'year_be',    pe.completed_year_be,
                'gpax',       pe.gpax)
         from student_prior_education pe
        where pe.student_id = p_student_id
        order by pe.completed_year_be desc nulls last, pe.level_th desc
        limit 1),
    -- จังหวัดของสถานศึกษา — ช่องใต้ชื่อสถานศึกษาบนหัวใบ
    'institution_province',
      (select coalesce(i.province_th, '')
         from student s join institution i on i.id = s.institution_id
        where s.id = p_student_id),
    -- กลุ่มอาชีพของสาขาวิชาที่นักศึกษาสังกัด
    'career_group_th',
      (select coalesce(pr.career_group_th, '')
         from student_curriculum sc
         join curriculum_version cv on cv.id = sc.curriculum_version_id
         join curriculum cur    on cur.id = cv.curriculum_id
         join program_track ptr on ptr.id = cur.program_track_id
         join program pr        on pr.id  = ptr.program_id
        where sc.student_id = p_student_id
          and (sc.effective_to is null or sc.effective_to >= current_date)
        order by sc.effective_from desc nulls last
        limit 1),
    /*
     * เชื้อชาติ · สัญชาติ · ศาสนา — สามช่องนี้อยู่บนบรรทัดเดียวของใบจริง
     * เก็บเฉพาะสามช่อง ไม่ใช่ทั้ง person_sensitive เพราะ payload ลบไม่ได้
     */
    'person_extra',
      (select jsonb_build_object(
                'ethnicity',   coalesce(ps.ethnicity, ''),
                'nationality', coalesce(p.nationality, ''),
                'religion',    coalesce(ps.religion, ''))
         from student s
         join person p on p.id = s.person_id
         left join person_sensitive ps on ps.person_id = p.id
        where s.id = p_student_id),
    /*
     * ชื่อบิดา · ชื่อมารดา — ใบพิมพ์แค่ชื่อ ไม่พิมพ์อาชีพ รายได้ เบอร์โทร
     * หรือที่อยู่ ซึ่ง `student_parent` เก็บไว้ด้วย จึงหยิบมาเฉพาะชื่อ
     */
    'parents',
      (select jsonb_object_agg(
                sp.role::text,
                trim(coalesce(sp.prefix_th, '') || coalesce(sp.first_name_th, '')
                     || ' ' || coalesce(sp.last_name_th, '')))
         from student_parent sp
        where sp.student_id = p_student_id),
    /*
     * ออกจากสถานศึกษาเมื่อ · เหตุที่ออก
     *
     * เอาเฉพาะสถานะที่**แปลว่าออกจากสถานศึกษาจริง** ไม่ใช่ทุกการเปลี่ยน
     * สถานะ — `on_leave` กับ `suspended` คือยังอยู่ในสถานศึกษา คนที่เคย
     * พักการเรียนแล้วกลับมาเรียนต่อจึงต้องไม่ถูกนับ ถ้าหยิบแถวล่าสุดมา
     * ดื้อ ๆ ใบจะเขียนว่าออกไปแล้วทั้งที่กำลังเรียนอยู่
     *
     * และต้องตรงกับสถานะ**ปัจจุบัน**ของนักศึกษาด้วย มิฉะนั้นคนที่เคยพ้นสภาพ
     * แล้วได้กลับเข้าเรียนใหม่จะยังมีวันที่ออกค้างอยู่บนใบ
     */
    'leaving',
      (select jsonb_build_object(
                'on_date', h.effective_on,
                'reason',  coalesce(h.reason, ''),
                'status',  h.to_status::text)
         from student_status_history h
         join student s on s.id = h.student_id
        where h.student_id = p_student_id
          and h.to_status = s.status
          and h.to_status in ('graduated', 'withdrawn', 'transferred_out',
                              'dismissed')
        order by h.effective_on desc, h.recorded_at desc
        limit 1))
$$;

comment on function transcript_extra(uuid) is
  'payload ส่วนที่มีเฉพาะใบ รบ. — เพิ่มช่องให้ใบ รบ. แก้ที่นี่ที่เดียว ไม่ต้องเขียน issue_document_core ทับทั้งตัว';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0063_transcript_plan_term.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0063 — ใบ รบ. แสดงภาคเรียนตาม**โครงสร้างหลักสูตร** ไม่ใช่ภาคที่ลงทะเบียนจริง
--
-- ═══ สิ่งที่เปลี่ยน ═══
-- นักศึกษาลงวิชาหนึ่งไว้ที่ปี 1 ภาคเรียนที่ 1 แต่โครงสร้างหลักสูตรวางวิชานั้น
-- ไว้ที่ปี 2 ภาคเรียนที่ 1 — ใบ รบ. ต้องพิมพ์ว่า **1/ปีที่สอง**
--
-- เพราะใบ รบ. เป็นเอกสารที่แสดงว่านักศึกษาเรียนครบตาม**หลักสูตร** ไม่ใช่
-- ปูมว่าไปนั่งเรียนห้องไหนเมื่อไร คนที่รับใบไปเทียบกับโครงสร้างหลักสูตร
-- ของ สอศ. ต้องเห็นรายวิชาอยู่ตำแหน่งเดียวกับที่หลักสูตรกำหนด มิฉะนั้น
-- จะดูเหมือนเรียนผิดแผนทั้งที่จบครบตามเกณฑ์
--
-- ═══ ของที่มีอยู่แล้วแต่ไม่เคยมีใครอ่าน ═══
-- `curriculum_course.suggested_year` กับ `suggested_term` มีมาตั้งแต่ 0004
-- พร้อมคอมเมนต์ว่า "แผนการเรียนแนะนำ … ใช้เตือนเมื่อนักศึกษาเรียนไม่ตามแผน"
-- ค้นทั้ง repo แล้ว**ไม่มีโค้ดไหนอ้างถึงเลยสักบรรทัด** ตลอดหกสิบ migration
-- รูปเดียวกับ `student_guardian.can_approve_leave` (ข้อ 15) และ
-- `take_usage_snapshot()` (ข้อ 8) — ของที่ประกาศเจตนาไว้แล้วไม่มีอะไร
-- ทำให้เจตนานั้นเกิดขึ้น
--
-- ═══ ชั้นปีไม่ใช่ปีการศึกษา ═══
-- `suggested_year` เป็น **ชั้นปี 1-4** ส่วนช่องบนใบพิมพ์ **ปีการศึกษา พ.ศ.**
-- แปลงด้วยปีที่เข้าศึกษา — ชั้นปี 1 = ปีที่เข้า · ชั้นปี 2 = ปีที่เข้า + 1
-- นักศึกษาที่ซ้ำชั้นหรือเทียบโอนเข้ากลางคันจะได้ปีที่ต่างจากที่ลงจริง
-- ซึ่งเป็นผลที่ตั้งใจ เพราะใบแสดงตำแหน่งตามหลักสูตร
--
-- ═══ เก็บทั้งสองค่า ไม่ใช่เขียนทับ ═══
-- `year_be` / `term_ordinal` ยังเป็น**ภาคที่ลงทะเบียนจริง**เหมือนเดิม
-- และเพิ่ม `plan_year_be` / `plan_term_ordinal` มาข้าง ๆ เพราะ
-- 1. ใบที่ออกไปแล้วไม่มีช่องใหม่ → แม่แบบตกไปใช้ค่าเดิม พิมพ์ซ้ำได้เหมือนเดิม
--    (payload ตรึงแล้วแก้ไม่ได้ การเปลี่ยนความหมายของช่องเดิมจะทำให้ใบเก่า
--     พิมพ์ออกมาไม่เหมือนวันที่ออก ซึ่งเป็นสิ่งที่หลักข้อ 5 ห้ามไว้)
-- 2. ตรวจย้อนหลังได้ว่านักศึกษาลงจริงเมื่อไร ต่างจากที่หลักสูตรวางไว้ตรงไหน
--
-- ═══ ทำไมตระกูล 62 ยังจัดกลุ่มตามภาคที่ลงจริง ═══
-- ใบตระกูล 62 จัดกลุ่มรายวิชา**ใต้หัวภาคเรียน** แล้วพิมพ์สรุปสี่ตัวเลข
-- (หน่วยกิตในภาค · สะสม · GPA · GPAX) ต่อท้ายทุกภาค ซึ่งมาจาก `term_summary`
-- คือผลการเรียนรายภาคที่ระบบใช้ตัดสินการจบและสถานะรอพินิจ
--
-- ถ้าย้ายรายวิชาไปอยู่ใต้หัวภาคตามแผน ตัวเลขสรุปจะไม่ตรงกับรายวิชาที่อยู่
-- ข้างบนมันเอง และการคำนวณสรุปใหม่จากรายวิชาที่แสดงจะได้ **GPA รายภาคชุดที่สอง**
-- ที่ต่างจากชุดที่ระบบใช้จริง — สองอย่างนี้แย่ทั้งคู่และแย่กว่าการแสดงภาคจริง
-- ตระกูล 62 จึงยังจัดตามภาคที่ลงทะเบียน ส่วน payload เก็บภาคตามแผนไว้ให้แล้ว
-- เผื่อวันที่ตัดสินใจเป็นอย่างอื่น (หลักเดียวกับ 0057 — ฝั่งที่แพงถ้าช้าทำก่อน)
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * ต้อง drop ก่อน เพราะ `create or replace` เปลี่ยนชนิดที่คืนของ table
 * function ไม่ได้ — และตัวนี้ต้องเพิ่มสามคอลัมน์
 */
drop function if exists transcript_courses_grouped(uuid);

create or replace function transcript_courses_grouped(p_student_id uuid)
returns table (
  head_code   text,
  head_name   text,
  head_sort   smallint,
  head_min    numeric,
  group_code  text,
  group_name  text,
  group_sort  smallint,
  group_min   numeric,
  year_be     smallint,
  term_ordinal smallint,
  term_label  text,
  plan_year_be smallint,
  plan_term_ordinal smallint,
  plan_sort   smallint,
  course_code text,
  course_name_th text,
  course_name_en text,
  credits     numeric,
  grade_symbol text,
  grade_point numeric,
  credits_earned numeric,
  counts_in_gpa boolean
) language sql stable as $$
  select
    coalesce(head.code, 'UNSORTED')            as head_code,
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as head_name,
    coalesce(head.sort_order, 99)::smallint    as head_sort,
    head.min_credits                           as head_min,
    coalesce(grp.code, head.code, 'UNSORTED')  as group_code,
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as group_name,
    coalesce(grp.sort_order, 0)::smallint      as group_sort,
    coalesce(grp.min_credits, head.min_credits) as group_min,
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    /*
     * ชั้นปีตามแผน → ปีการศึกษา พ.ศ.
     * null เมื่อรายวิชาไม่ได้อยู่ในโครงสร้างหลักสูตร (วิชาเลือกเสรีนอกแผน ·
     * วิชาที่เทียบโอนมา) หรือหลักสูตรยังไม่ได้ระบุแผนไว้ หรือไม่รู้ปีที่เข้า
     * — แม่แบบจะตกไปใช้ภาคที่ลงจริง ซึ่งดีกว่าพิมพ์ช่องว่าง
     */
    (s.admitted_year_be + cc.suggested_year - 1)::smallint as plan_year_be,
    cc.suggested_term                          as plan_term_ordinal,
    cc.sort_order                              as plan_sort,
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    (gsym.counts_in_gpa and e.counts_toward_gpa)
  from enrollment e
  join student s            on s.id  = e.student_id
  join class_section cs     on cs.id = e.class_section_id
  join course c             on c.id  = cs.course_id
  join term t               on t.id  = e.term_id
  join academic_year ay     on ay.id = t.academic_year_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym    on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where e.student_id = p_student_id
$$;

comment on function transcript_courses_grouped(uuid) is
  'รายวิชาของนักศึกษาพร้อมหมวด/กลุ่มตามหลักสูตร · year_be คือภาคที่ลงจริง ส่วน plan_year_be คือภาคตามโครงสร้างหลักสูตร (null เมื่อไม่อยู่ในแผน)';


/*
 * ส่งภาคตามแผนเข้า payload และ**เรียงตามค่าที่จะพิมพ์จริง**
 *
 * ถ้าเรียงตามภาคที่ลงแต่พิมพ์ภาคตามแผน คอลัมน์ภาคเรียนบนใบจะกระโดดไปมา
 * (1/2566 · 1/2567 · 1/2566) ซึ่งอ่านแล้วเหมือนพิมพ์ผิด — เรียงลำดับต้อง
 * ตรงกับสิ่งที่ตาเห็นเสมอ
 *
 * `plan_sort` คือ `curriculum_course.sort_order` ซึ่งเป็นลำดับที่วิทยาลัย
 * จัดไว้เองในหลักสูตร ใช้ก่อนรหัสวิชา เพราะหลักสูตรเรียงวิชาตามเนื้อหา
 * ไม่ได้เรียงตามเลขรหัส
 */
create or replace function transcript_category_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(head order by head ->> 'sort'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'code',        h.head_code,
               'name_th',     h.name_th,
               'sort',        h.sort_key,
               'min_credits', h.min_credits,
               'credits_earned', h.credits_earned,
               'gpa',         h.gpa,
               'groups',
                 coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'code',        g.group_code,
                            'name_th',     g.name_th,
                            'sort',        g.sort_key,
                            'min_credits', g.min_credits,
                            'credits_earned', g.credits_earned,
                            'gpa',         g.gpa,
                            'courses',
                              coalesce((
                                select jsonb_agg(jsonb_build_object(
                                         'term_label',  c.term_label,
                                         'year_be',     c.year_be,
                                         'term_ordinal', c.term_ordinal,
                                         'plan_year_be', c.plan_year_be,
                                         'plan_term_ordinal', c.plan_term_ordinal,
                                         'code',        c.course_code,
                                         'name_th',     c.course_name_th,
                                         'name_en',     c.course_name_en,
                                         'credits',     c.credits,
                                         'grade',       c.grade_symbol,
                                         'grade_point', c.grade_point,
                                         'grade_points',
                                           case when c.counts_in_gpa
                                                then c.grade_point * c.credits end,
                                         'counts_in_gpa', c.counts_in_gpa,
                                         'credits_earned', c.credits_earned)
                                         order by coalesce(c.plan_year_be, c.year_be),
                                                  coalesce(c.plan_term_ordinal, c.term_ordinal),
                                                  coalesce(c.plan_sort, 0),
                                                  c.course_code)
                                  from transcript_courses_grouped(p_student_id) c
                                 where c.head_code = h.head_code
                                   and c.group_code = g.group_code), '[]'::jsonb))
                          order by g.sort_key)
                     from transcript_category_summary(p_student_id) g
                    where g.level = 'group' and g.head_code = h.head_code), '[]'::jsonb)) as head
        from transcript_category_summary(p_student_id) h
       where h.level = 'head'
    ) x
$$;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0064_student_status_reason.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0064 — เหตุที่ออกจากสถานศึกษา ต้องมีคนกรอกได้จริง
--
-- ═══ อาการ ═══
-- `student_status_history.reason` มีคอลัมน์มาตั้งแต่ 0002 พร้อม
-- `document_no` (เลขที่คำสั่ง/หนังสือที่อ้างอิง) — และ **ไม่มีอะไรเขียนลงไป
-- เลยสักแถว** เพราะ trigger ที่บันทึกประวัติเขียนแค่สี่ช่อง
--
--     insert into student_status_history
--       (student_id, from_status, to_status, effective_on, actor_id)
--
-- ทั้งสองคอลัมน์จึงเป็น null ทุกแถวมาตลอด ผลคือใบ รบ. พิมพ์หัวข้อ
-- "เหตุที่ออก" ไว้แล้วเว้นว่างเสมอ ไม่ว่าเจ้าหน้าที่จะรู้เหตุผลหรือไม่
-- และไม่มีที่ให้กรอกด้วยซ้ำ
--
-- ═══ ทำไมเป็นคอลัมน์บน student ไม่ใช่พารามิเตอร์ของฟังก์ชัน ═══
-- `status_since` ทำแบบนี้อยู่แล้วตั้งแต่ 0002 — ชั้น API ตั้งค่าลง student
-- แล้ว trigger หยิบไปเขียนประวัติ การเพิ่มอีกสองช่องด้วยรูปแบบเดียวกัน
-- แปลว่าการเปลี่ยนสถานะยังเป็น `update student` คำสั่งเดียวเหมือนเดิม
--
-- ทางเลือกอีกทางคือทำฟังก์ชัน `change_student_status()` แล้วบังคับให้ทุกคน
-- เรียกผ่านมัน — แต่ trigger ยังต้องอยู่ดี (หลักข้อ 1 · กฎต้องบังคับกับ
-- **ทุกทาง**ที่เข้าถึงข้อมูล ไม่ใช่เฉพาะทางที่ผ่านฟังก์ชัน) แล้วจะได้สองที่
-- ที่เขียนประวัติได้ ซึ่งเป็นจุดที่ประวัติจะเริ่มไม่ตรงกัน
--
-- ═══ สองคอลัมน์นี้เป็น "ช่องพัก" ไม่ใช่ที่เก็บถาวร ═══
-- trigger ย้ายค่าลงประวัติแล้ว**ล้างทิ้ง** — ค่าถาวรอยู่ที่ประวัติที่ลบไม่ได้
--
-- ทางแรกที่ลองคือเก็บค่าไว้บน `student` เป็น "เหตุผลของสถานะปัจจุบัน" แล้วให้
-- trigger เขียนลงประวัติเฉพาะเมื่อค่านั้นเปลี่ยน เพื่อกันไม่ให้เหตุผลของครั้ง
-- ก่อนติดไปกับแถวใหม่ — **ซึ่งผิดในกรณีที่เหตุผลซ้ำของเดิม**
--
--   นักศึกษาสองคนพ้นสภาพด้วยเหตุผลเดียวกัน · คนที่กลับเข้าเรียนแล้วจบด้วย
--   ถ้อยคำเดิม · หรือแค่กดบันทึกซ้ำ — ทุกกรณีได้ประวัติที่ `reason` เป็น null
--   ทั้งที่เจ้าหน้าที่กรอกมาแล้ว แล้วช่อง "เหตุที่ออก" บนใบ รบ. ว่างเปล่า
--   โดยที่หน้าจอบอกว่าบันทึกสำเร็จ
--
-- การล้างทิ้งทำให้ปัญหานั้นเป็นไปไม่ได้ตั้งแต่ต้น — ค่าที่ยังอยู่บนแถวคือ
-- ค่าที่ตั้งมาในคำสั่งนี้เสมอ ไม่มีค่าค้างให้สับสน ส่วนการอ่านเหตุผลปัจจุบัน
-- อ่านจากประวัติแถวล่าสุด ซึ่งเป็นที่ที่ตรวจย้อนหลังได้อยู่แล้ว
-- ═══════════════════════════════════════════════════════════════════

begin;

alter table student
  add column if not exists status_reason      text,
  add column if not exists status_document_no text;

comment on column student.status_reason is
  'ช่องพัก — ตั้งพร้อมกับ status ในคำสั่งเดียว แล้ว trigger ย้ายลง student_status_history และล้างทิ้ง · ค่าถาวรอยู่ที่ประวัติ · พิมพ์บนใบ รบ. ช่อง "เหตุที่ออก"';
comment on column student.status_document_no is
  'ช่องพักเลขที่คำสั่ง/หนังสือที่อ้างอิง — ย้ายลงประวัติแล้วล้างทิ้งเช่นเดียวกับ status_reason';

/*
 * ─── ย้ายค่าลงประวัติแล้วล้างช่องพักทิ้งในคำสั่งเดียวกัน ───
 * เป็น before trigger เพราะต้องแก้ NEW ได้ — after trigger แก้ไม่ได้ ต้องยิง
 * update ซ้อนอีกคำสั่ง ซึ่งเป็นทางที่พลาดเป็นวงวนได้ง่ายกว่ามาก
 *
 * insert จาก before trigger อยู่ในทรานแซกชันเดียวกับ update ที่เรียกมัน
 * ถ้า update ล้มทีหลัง แถวประวัติก็ย้อนไปด้วย จึงไม่มีทางเหลือประวัติค้าง
 * ของการเปลี่ยนสถานะที่ไม่เคยเกิด
 */
create or replace function student_status_guard() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status then
    insert into student_status_history
      (student_id, from_status, to_status, effective_on, reason, document_no, actor_id)
    values (
      new.id, old.status, new.status,
      coalesce(new.status_since, current_date),
      new.status_reason, new.status_document_no, current_actor_id());
  end if;
  -- ล้างช่องพักเสมอ แม้สถานะไม่ได้เปลี่ยน — ค่าที่ค้างอยู่จะไปติดกับ
  -- การเปลี่ยนสถานะครั้งถัดไปที่ไม่ได้ตั้งค่ามา
  new.status_reason      := null;
  new.status_document_no := null;
  return new;
end $$;

/*
 * trigger เดิมเป็น `after update of status` ซึ่งแก้ NEW ไม่ได้ — ต้องสร้างใหม่
 * และต้องฟัง update ทุกคอลัมน์ ไม่ใช่เฉพาะ status เพราะการล้างช่องพักต้อง
 * เกิดแม้ในคำสั่งที่ตั้งเหตุผลมาแต่ไม่ได้เปลี่ยนสถานะ
 */
drop trigger if exists student_status_audit on student;
create trigger student_status_audit before update on student
  for each row execute function student_status_guard();

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0065_course_catalog_write_scope.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0065 — ขอบเขตการเขียนของคลังรายวิชา และช่องลบที่เปิดค้างมาตั้งแต่ 0017
--
-- ─── เรื่องนี้โผล่ตอนจะทำหน้าจอลงข้อมูลรายวิชา ───
-- ยิงจริงในบริบท `app.role = 'student'` แล้วนักศึกษาทำได้ทั้งสามอย่าง:
--   update course set credits = 99  → รายวิชาภาษาไทยพื้นฐานกลายเป็น 99 หน่วยกิต
--   insert into course ...          → สร้างรายวิชาของตัวเองในหลักสูตร
--   delete from course ...          → ลบรายวิชาทิ้ง
-- ทั้งสามข้อสำเร็จจริง ทดสอบแล้วทั้งก่อนและหลังไฟล์นี้
--
-- ─── ทำไมถึงไม่มีใครเห็น ───
-- 0017 ปิด `curriculum_version` · `curriculum_category` · `curriculum_course`
-- ไว้ครบด้วย `academic_write_only` แล้ว — **ตารางลูกถูกล็อก แต่ตารางแม่เปิดอยู่**
-- คนอ่านนโยบายจะเห็นว่าโครงสร้างหลักสูตรถูกคุ้มครอง โดยที่ `course` ซึ่งเป็น
-- ตัวถือ **จำนวนหน่วยกิต** ที่ใช้ตัดสินการจบ ไม่มีนโยบายบทบาทเลยสักข้อ
-- (`program` · `curriculum` · `grade_scheme` อยู่ในสภาพเดียวกัน — `grade_scheme`
-- คือตัวกำหนดว่าเกรดไหนได้กี่แต้ม)
-- รูปเดียวกับข้อ 10, 11, 13 และ 16 คือช่องที่ **ข้าม API ไปเลย**
--
-- ─── และช่องที่สอง: `with check` ไม่มีผลกับ delete ───
-- `academic_write_only` ของ 0017 เขียนเป็น
--     as restrictive for all using (true) with check (บทบาทวิชาการ)
-- `using (true)` ทำให้การ**อ่าน**ไม่ถูกกระทบ ซึ่งถูกต้อง แต่ `delete` ตรวจด้วย
-- `using` ไม่ใช่ `with check` — นักศึกษาจึง `delete from curriculum_course`
-- ได้ทั้งตาราง (ยิงจริงแล้วลบได้ 12 จาก 12 แถว) กฎข้อนี้เขียนไว้ใน CLAUDE.md
-- ตรง ๆ อยู่แล้ว แต่ตัวนโยบายที่ตั้งใจบังคับมันกลับติดกับดักนั้นเอง
--
-- ไฟล์นี้ปิดเฉพาะตระกูลหลักสูตรที่หน้าจอใหม่แตะ — ยังเหลืออีก 14 ตารางที่
-- ติดกับดัก delete แบบเดียวกัน (`staff_role` · `ledger_transaction` ·
-- `grade_symbol` · `grade_cutoff` · `workplace` …) TEST 274 นับไว้ให้เห็นทุกครั้ง
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. คลังรายวิชาและโครงหลักสูตรระดับบน ─────────────────────────
--
-- แยกเป็น insert / update / delete แทน `for all` โดยตั้งใจ — `for all`
-- แบบ restrictive กิน `select` ไปด้วยถ้าเผลอเขียน `using` เป็นเงื่อนไขบทบาท
-- และถึงเขียน `using (true)` ก็ยังลืม delete อยู่ดี (คือสิ่งที่เกิดขึ้นจริง)
do $$
declare t text;
begin
  foreach t in array array['course', 'program', 'curriculum', 'grade_scheme'] loop
    execute format($f$
      create policy academic_insert on %I
        as restrictive for insert
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
    execute format($f$
      create policy academic_update on %I
        as restrictive for update
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
    execute format($f$
      create policy academic_delete on %I
        as restrictive for delete
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- ── 2. ปิดช่อง delete ของตระกูลหลักสูตรที่ 0017 เปิดค้างไว้ ────────
--
-- ไม่แตะ `academic_write_only` เดิม เพราะมันคุม insert/update ถูกต้องอยู่แล้ว
-- การเพิ่มนโยบาย restrictive อีกข้อรวมกันด้วย AND จึงเป็นการ **เพิ่ม** ข้อจำกัด
-- ไม่ใช่การเขียนทับ — ปลอดภัยกว่าการคัดลอกประโยคเดิมมาแก้ (วิธีที่ 2 ของ 0045)
do $$
declare t text;
begin
  foreach t in array array[
    'curriculum_version', 'curriculum_category', 'curriculum_course',
    'competency', 'course_competency', 'course_prerequisite',
    'entry_pathway', 'graduation_rule', 'pathway_bridging_course', 'program_track'
  ] loop
    execute format($f$
      create policy academic_delete on %I
        as restrictive for delete
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- ── 3. รายวิชาที่มีคนลงทะเบียนแล้วลบไม่ได้ ────────────────────────
--
-- ─── ทำไมเป็น trigger ไม่ใช่นโยบาย ───
-- เงื่อนไขคือ "มีแถวในตารางอื่นอ้างถึงไหม" ซึ่งนโยบาย RLS ตอบไม่ได้โดยไม่
-- ทำให้ทุกคำสั่งลบต้องกางแผนไปอ่านอีกสองตาราง และ foreign key ก็กันไม่ได้
-- เพราะ `enrollment` ชี้ที่ `class_section` ไม่ได้ชี้ที่ `course` ตรง ๆ
--
-- ─── ทำไมต้องกัน ───
-- รายวิชาที่ถูกลบทิ้งแต่มีผลการเรียนอ้างอยู่ ทำให้ใบ รบ. พิมพ์ชื่อวิชาไม่ออก
-- และ `enrollment_result` แก้ไม่ได้ตามหลักข้อ 4 — ข้อมูลจะค้างในสภาพที่
-- ซ่อมไม่ได้อีกเลย ปิดรายวิชาด้วย `active = false` แทน ซึ่งเลือกลงหลักสูตร
-- ใหม่ไม่ได้แต่ของเก่ายังพิมพ์ได้
create or replace function course_delete_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  select count(*) into v_n
    from class_section cs
   where cs.course_id = old.id;

  if v_n > 0 then
    raise exception 'ลบรายวิชา % ไม่ได้ เพราะมีกลุ่มเรียนอ้างอยู่ % กลุ่ม — ปิดการใช้งานแทนด้วยการตั้ง active = false',
      old.code, v_n;
  end if;

  if exists (select 1 from curriculum_course cc where cc.course_id = old.id) then
    raise exception 'ลบรายวิชา % ไม่ได้ เพราะยังอยู่ในโครงสร้างหลักสูตร — เอาออกจากหลักสูตรก่อน',
      old.code;
  end if;

  return old;
end $$;

drop trigger if exists course_delete_guard on course;
create trigger course_delete_guard
  before delete on course
  for each row execute function course_delete_guard();

comment on function course_delete_guard() is
  'กันการลบรายวิชาที่มีกลุ่มเรียนหรือหลักสูตรอ้างอยู่ — ปิดด้วย active = false แทน';


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0066_transcript_credit_source.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0066 — เครื่องหมาย (*1)–(*5) บนใบ รบ. และรายวิชาเทียบโอนที่ไม่เคยขึ้นใบ
--
-- ═══ สองเรื่องที่ไฟล์นี้ปิด ═══
--
-- **1. คำอธิบายเครื่องหมายมีมาตั้งแต่ต้น แต่ไม่มีเครื่องหมาย**
-- `reference-data.sql` ใส่ `transcript_note_1` ถึง `transcript_note_5` ให้ครบ
-- และแม่แบบทั้ง 67 กับ 62 พิมพ์ออกมาจริงท้ายหน้า 2 แต่ค้นทั้ง repo แล้ว
-- **ไม่มีคอลัมน์ ไม่มีช่องใน payload ไม่มีโค้ดที่ใส่ (*n) ข้างรายวิชาเลย**
-- ใบจึงพิมพ์คำอธิบายของเครื่องหมายที่ไม่มีวันปรากฏ — รูปเดียวกับ
-- `can_approve_leave` (ข้อ 15) และ `take_usage_snapshot` (ข้อ 8)
--
-- **2. รายวิชาเทียบโอนถูกนับตอนตรวจจบ แต่ไม่ขึ้นใบ รบ.**
-- `evaluate_graduation()` บวก `transfer_credits_total()` เข้าหน่วยกิตสะสม
-- (0051) ส่วน `transcript_data()` กับ `transcript_courses_grouped()` อ่านจาก
-- `enrollment` อย่างเดียว — `prior_academic_record` ไม่เคยถูก join เข้ามา
-- ผลคือ **ระบบรับรองว่าจบด้วยหน่วยกิตชุดหนึ่ง แต่กระดาษแสดงอีกชุดหนึ่ง**
-- คนที่ถือใบไปยื่นจะบวกรายวิชาบนใบแล้วไม่ตรงกับหน่วยกิตรวมที่พิมพ์อยู่หัวใบ
-- และกระทบนักศึกษา ปวส. เกือบทุกคนตามที่ 0060 เขียนกำกับไว้เอง
--
-- ─── ทำไม `credit_transfer` ใน enrollment_status ใช้แทนไม่ได้ ───
-- ค่านั้นมีอยู่ในชนิดข้อมูลจริงและฟังก์ชันใบ รบ. ก็รับไว้แล้ว แต่
-- `approveTransfer()` แค่ประทับ `approved_at` ลง `prior_academic_record`
-- ไม่เคยสร้างแถว `enrollment` เลย และสร้างไม่ได้ด้วย เพราะ
-- `class_section_id` กับ `term_id` เป็น not null ส่วนวิชาที่เทียบโอนมา
-- ไม่มีกลุ่มเรียนของวิทยาลัยนี้ — จึงต้อง union เข้ามาตอนอ่าน
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. หน่วยกิตนี้ได้มาอย่างไร ──────────────────────────────────────
--
-- ─── ทำไมเป็นคอลัมน์ของ enrollment ไม่ใช่ของ course ───
-- วิชาเดียวกันคนหนึ่งเทียบโอนมา อีกคนเรียนปกติ และคนที่สามเรียนซ้ำเพื่อ
-- ปรับระดับคะแนน — เครื่องหมายจึงเป็นของ **การลงทะเบียนครั้งนั้น** เสมอ
--
-- ─── ทำไมแยกเป็น enum หนึ่งตัวกับ boolean สองตัว ───
-- (*1)(*2)(*3) ตอบคำถาม "ได้หน่วยกิตมาอย่างไร" ซึ่งเป็นได้อย่างเดียว
-- ส่วน (*4)(*5) ตอบ "เรียนที่ไหน/ภาษาอะไร" ซึ่งซ้อนกับข้อบนและกันเองได้
-- วิชาที่ฝึกในสถานประกอบการและสอนเป็นภาษาอังกฤษต้องได้ทั้ง (*4) และ (*5)
-- ถ้ายัดเป็น enum ตัวเดียวจะบังคับให้เลือกอย่างใดอย่างหนึ่งโดยไม่มีเหตุผล
create type credit_source_kind as enum (
  'studied',                 -- เรียนตามปกติ — ไม่มีเครื่องหมาย
  'transferred_grade',       -- (*1) โอนผลการเรียน
  'transferred_experience',  -- (*2) เทียบโอนความรู้และประสบการณ์
  'regraded'                 -- (*3) เรียนปรับระดับคะแนน
);

alter table enrollment
  add column credit_source       credit_source_kind not null default 'studied',
  add column taught_at_workplace boolean not null default false,  -- (*4)
  add column taught_in_english   boolean not null default false;  -- (*5)

comment on column enrollment.credit_source is
  'ที่มาของหน่วยกิต — ตัวกำหนดเครื่องหมาย (*1)(*2)(*3) บนใบ รบ.';
comment on column enrollment.taught_at_workplace is
  '(*4) เรียนหรือฝึกอาชีพในสถานประกอบการ — ซ้อนกับ credit_source ได้';
comment on column enrollment.taught_in_english is
  '(*5) จัดการเรียนการสอนเป็นภาษาอังกฤษ — ซ้อนกับทุกค่าได้';

/*
 * ─── ค่าเริ่มต้นย้อนหลังของ (*4) ───
 * แถวที่มีอยู่แล้วซึ่งกลุ่มเรียนผูกกับสถานประกอบการ ควรได้ (*4) ตั้งแต่แรก
 * ไม่ใช่รอให้คนไล่กดทีละแถว — ข้อมูลบอกอยู่แล้วว่าเรียนที่ไหน
 */
-- `dvt` คือทวิภาคี ส่วน `internship` คือฝึกงาน — ทั้งคู่คือ "เรียนหรือ
-- ฝึกอาชีพในสถานประกอบการ" ตามถ้อยคำของ (*4) ส่วน `block` เป็นวิธีจัดตาราง
-- ไม่ใช่สถานที่ จึงไม่นับ
update enrollment e
   set taught_at_workplace = true
  from class_section cs
 where cs.id = e.class_section_id
   and cs.delivery_mode in ('dvt', 'internship')
   and e.taught_at_workplace = false;

-- ── 2. วิชาเทียบโอนบอกได้ว่าเป็นแบบไหน ─────────────────────────────
--
-- ─── ทำไมต้องมีคอลัมน์ ไม่ใช่เดาจาก counts_in_gpa ───
-- ระเบียบ สอศ. ให้ "โอนผลการเรียน" ยกเกรดเดิมมาด้วย ส่วน "เทียบโอนความรู้
-- และประสบการณ์" ให้หน่วยกิตโดยไม่มีแต้ม — เดาจาก `counts_in_gpa` จึงถูก
-- เกือบทุกครั้ง แต่ "เกือบ" ไม่พอสำหรับสิ่งที่พิมพ์ลงกระดาษแล้วแก้ไม่ได้
-- และวิทยาลัยที่บันทึกเกรดเทียบโอนแบบไม่คิด GPA จะได้เครื่องหมายผิดเงียบ ๆ
-- ค่าเริ่มต้นเดาให้จากข้อมูลที่มี แล้วให้คนแก้ทีหลังได้
alter table prior_academic_record
  add column transfer_kind credit_source_kind not null default 'transferred_experience'
    check (transfer_kind in ('transferred_grade', 'transferred_experience'));

update prior_academic_record
   set transfer_kind = 'transferred_grade'
 where counts_in_gpa;

comment on column prior_academic_record.transfer_kind is
  'โอนผลการเรียน (*1) หรือเทียบโอนความรู้และประสบการณ์ (*2) — ค่าเริ่มต้นเดาจาก counts_in_gpa ตอน migrate';

-- ── 3. แปลงเป็นเลขเครื่องหมาย ───────────────────────────────────────
--
-- เขียนที่เดียวเพราะทั้งสองตระกูลใบ รบ. และทั้งสองภาษาต้องได้เลขชุดเดียวกัน
-- ถ้าปล่อยให้แต่ละฟังก์ชันแปลงเอง วันหนึ่งจะมีใบที่ (*2) แปลว่าคนละอย่าง
create or replace function transcript_note_marks(
  p_source      credit_source_kind,
  p_workplace   boolean,
  p_english     boolean
) returns smallint[] language sql immutable as $$
  select array_remove(array[
    case p_source
      when 'transferred_grade'      then 1
      when 'transferred_experience' then 2
      when 'regraded'               then 3
    end::smallint,
    case when p_workplace then 4 end::smallint,
    case when p_english   then 5 end::smallint
  ], null)
$$;

comment on function transcript_note_marks(credit_source_kind, boolean, boolean) is
  'เลขเครื่องหมาย (*1)–(*5) ที่ต้องพิมพ์ท้ายชื่อวิชาบนใบ รบ. — เรียงจากน้อยไปมากเสมอ';

/*
 * ─── ภาคที่รับรองการเทียบโอน ───
 * วิชาเทียบโอนไม่มีภาคเรียนของวิทยาลัยนี้ แต่ใบ รบ. ตระกูล 62 จัดกลุ่มตาม
 * ภาคเรียน จึงต้องรู้ว่าจะวางไว้ภาคไหน
 *
 * ใช้ **ภาคที่มีวันอนุมัติอยู่ในช่วง** ไม่ใช่ภาคของสถาบันเดิม เพราะสิ่งที่
 * ใบ รบ. ของเราแสดงคือ "วิทยาลัยนี้รับรองหน่วยกิตนี้เมื่อไร" ส่วนภาคของ
 * สถาบันเดิมเป็นข้อมูลของอีกใบหนึ่ง การเอามาปนจะทำให้ใบมีภาคเรียนที่
 * นักศึกษาไม่เคยลงทะเบียนกับเรา
 *
 * ถ้าวันอนุมัติไม่ตกในภาคไหนเลย (อนุมัติช่วงปิดภาค) ใช้ภาคแรกที่ลงทะเบียน
 * — ดีกว่าทิ้งรายวิชาหายไปจากใบ ซึ่งเป็นสภาพก่อนไฟล์นี้
 */
create or replace function transfer_recognition_term(p_student_id uuid, p_approved_at timestamptz)
returns uuid language sql stable as $$
  select coalesce(
    (select t.id
       from term t
       join academic_year ay on ay.id = t.academic_year_id
       join student s on s.id = p_student_id
      where ay.institution_id = s.institution_id
        and p_approved_at::date between t.starts_on and t.ends_on
      order by t.starts_on
      limit 1),
    (select e.term_id
       from enrollment e
       join term t on t.id = e.term_id
      where e.student_id = p_student_id
      order by t.starts_on
      limit 1)
  )
$$;

comment on function transfer_recognition_term(uuid, timestamptz) is
  'ภาคเรียนที่ใบ รบ. จะวางรายวิชาเทียบโอนไว้ — ภาคที่รับรอง ไม่ใช่ภาคของสถาบันเดิม';

-- ── 4. ตัวอ่านรายวิชาของใบ รบ. ตระกูล 62 ────────────────────────────
--
-- เขียนทับทั้งตัวเพราะ `returns table` เปลี่ยน — เพิ่ม `note_marks` และ
-- union แถวเทียบโอนเข้ามา ส่วนที่เหลือคงเดิมทุกบรรทัด
drop function if exists transcript_data(uuid);
create function transcript_data(p_student_id uuid)
returns table (
  year_be        smallint,
  term_ordinal   smallint,
  term_label     text,
  course_code    text,
  course_name_th text,
  credits        numeric(3,1),
  grade_symbol   text,
  grade_point    numeric(2,1),
  credits_earned numeric(3,1),
  category_th    text,
  term_id        uuid,
  course_name_en text,
  counts_in_gpa  boolean,
  grade_points   numeric,
  note_marks     smallint[]
) language sql stable as $$
  -- ── รายวิชาที่เรียนกับวิทยาลัยนี้ ──
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    c.code,
    c.name_th,
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    cat.name_th,
    t.id,
    coalesce(c.name_en, ''),
    (gsym.counts_in_gpa and e.counts_toward_gpa),
    case when gsym.counts_in_gpa and e.counts_toward_gpa
         then er.grade_point * c.credits end,
    transcript_note_marks(e.credit_source, e.taught_at_workplace, e.taught_in_english)
  from enrollment e
  join class_section cs      on cs.id = e.class_section_id
  join course c              on c.id  = cs.course_id
  join term t                on t.id  = e.term_id
  join academic_year ay      on ay.id = t.academic_year_id
  join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym     on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript

  union all

  /*
   * ── รายวิชาที่เทียบโอนมา ──
   *
   * เอาเฉพาะที่อนุมัติแล้ว — แถวที่ยังไม่อนุมัติคือคำขอ ไม่ใช่หน่วยกิต
   * และ `evaluate_graduation()` ก็นับเฉพาะที่อนุมัติแล้วเหมือนกัน
   * สองที่ต้องใช้เงื่อนไขเดียวกันเสมอ มิฉะนั้นใบกับการตัดสินจะไม่ตรงกันอีก
   *
   * ชื่อวิชาใช้ของรายวิชาที่แมปไว้ถ้ามี — ใบ รบ. ของเราต้องพิมพ์ชื่อวิชา
   * ตามหลักสูตรของเรา ไม่ใช่ชื่อที่สถาบันเดิมใช้เรียก
   */
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    coalesce(mc.code, pr.course_code),
    coalesce(mc.name_th, pr.course_name_th),
    pr.credits::numeric(3,1),
    pr.grade_symbol,
    pr.grade_point::numeric(2,1),
    (case when pr.earns_credit then pr.credits else 0 end)::numeric(3,1),
    cat.name_th,
    t.id,
    coalesce(mc.name_en, ''),
    pr.counts_in_gpa,
    case when pr.counts_in_gpa then pr.grade_point * pr.credits end,
    transcript_note_marks(pr.transfer_kind, false, false)
  from prior_academic_record pr
  join term t           on t.id  = transfer_recognition_term(pr.student_id, pr.approved_at)
  join academic_year ay on ay.id = t.academic_year_id
  left join course mc   on mc.id = pr.mapped_course_id
  left join curriculum_course cc
         on cc.course_id = mc.id
        -- ฉบับหลักสูตรของนักศึกษาอยู่ที่ `student_curriculum` ไม่ใช่ที่ `student`
        -- เอาฉบับที่ยังมีผลอยู่ ถ้ามีหลายแถวเลือกอันที่เริ่มล่าสุด
        and cc.curriculum_version_id = (
              select sc.curriculum_version_id
                from student_curriculum sc
               where sc.student_id = pr.student_id
               order by sc.effective_to nulls first, sc.effective_from desc
               limit 1)
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where pr.student_id = p_student_id
    and pr.approved_at is not null

  order by 1, 2, 4;
$$;

comment on function transcript_data(uuid) is
  'รายวิชาทั้งหมดที่ขึ้นระเบียนแสดงผลการเรียน รวมวิชาเทียบโอนที่อนุมัติแล้ว — grade_points คือตัวตั้งของ GPA จึงต้องคิดที่นี่ที่เดียว · note_marks คือเลข (*n) ท้ายชื่อวิชา';

-- ── 5. ตัวอ่านรายวิชาของใบ รบ. ตระกูล 67 ────────────────────────────
--
-- ─── ต่อยอดจาก 0063 ไม่ใช่จาก 0058 ───
-- รอบแรกผมคัดลอกตัวจาก 0058 มาแก้ แล้ว `plan_year_be` กับ `plan_term_ordinal`
-- ที่ 0063 เพิ่มไว้หายไปทั้งคู่ — ช่องภาคเรียนบนใบจะกลับไปพิมพ์ภาคที่ลงจริง
-- แทนภาคตามแผนโดยไม่มีอะไรฟ้อง นี่คือกับดักที่ 0059 บันทึกไว้ตรง ๆ ว่า
-- "การเขียนฟังก์ชันทับทั้งตัวเพื่อเพิ่มบรรทัดเดียวเสี่ยงและอ่านไม่ออก
-- ว่าเปลี่ยนอะไร" — เจอกับตัวเองในไฟล์ถัดมาสามไฟล์
drop function if exists transcript_courses_grouped(uuid);
create function transcript_courses_grouped(p_student_id uuid)
returns table (
  head_code   text,
  head_name   text,
  head_sort   smallint,
  head_min    numeric,
  group_code  text,
  group_name  text,
  group_sort  smallint,
  group_min   numeric,
  year_be     smallint,
  term_ordinal smallint,
  term_label  text,
  plan_year_be smallint,
  plan_term_ordinal smallint,
  plan_sort   smallint,
  course_code text,
  course_name_th text,
  course_name_en text,
  credits     numeric,
  grade_symbol text,
  grade_point numeric,
  credits_earned numeric,
  counts_in_gpa boolean,
  note_marks  smallint[]
) language sql stable as $$
  select
    coalesce(head.code, 'UNSORTED')            as head_code,
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as head_name,
    coalesce(head.sort_order, 99)::smallint    as head_sort,
    head.min_credits                           as head_min,
    coalesce(grp.code, head.code, 'UNSORTED')  as group_code,
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as group_name,
    coalesce(grp.sort_order, 0)::smallint      as group_sort,
    coalesce(grp.min_credits, head.min_credits) as group_min,
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    (s.admitted_year_be + cc.suggested_year - 1)::smallint as plan_year_be,
    cc.suggested_term                          as plan_term_ordinal,
    cc.sort_order                              as plan_sort,
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    (gsym.counts_in_gpa and e.counts_toward_gpa),
    transcript_note_marks(e.credit_source, e.taught_at_workplace, e.taught_in_english)
  from enrollment e
  join student s            on s.id  = e.student_id
  join class_section cs     on cs.id = e.class_section_id
  join course c             on c.id  = cs.course_id
  join term t               on t.id  = e.term_id
  join academic_year ay     on ay.id = t.academic_year_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym    on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where e.student_id = p_student_id

  union all

  /*
   * ── รายวิชาที่เทียบโอนมา ──
   *
   * เอาเฉพาะที่อนุมัติแล้ว — แถวที่ยังไม่อนุมัติคือคำขอ ไม่ใช่หน่วยกิต
   * และ `evaluate_graduation()` ก็นับเฉพาะที่อนุมัติแล้วเหมือนกัน
   * สองที่ต้องใช้เงื่อนไขเดียวกันเสมอ มิฉะนั้นใบกับการตัดสินจะไม่ตรงกันอีก
   *
   * ชื่อวิชาใช้ของรายวิชาที่แมปไว้ถ้ามี — ใบ รบ. ของเราต้องพิมพ์ชื่อตาม
   * หลักสูตรของเรา ไม่ใช่ชื่อที่สถาบันเดิมใช้เรียก
   *
   * ภาคตามแผนเป็น null เสมอ ตามที่ 0063 เขียนกำกับไว้แล้วว่าวิชาเทียบโอน
   * ไม่อยู่ในแผน — แม่แบบจะตกไปใช้ภาคที่รับรอง
   */
  select
    coalesce(head.code, 'UNSORTED'),
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด'),
    coalesce(head.sort_order, 99)::smallint,
    head.min_credits,
    coalesce(grp.code, head.code, 'UNSORTED'),
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด'),
    coalesce(grp.sort_order, 0)::smallint,
    coalesce(grp.min_credits, head.min_credits),
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    null::smallint,
    null::smallint,
    null::smallint,
    coalesce(mc.code, pr.course_code),
    coalesce(mc.name_th, pr.course_name_th),
    coalesce(mc.name_en, ''),
    pr.credits,
    pr.grade_symbol,
    pr.grade_point,
    case when pr.earns_credit then pr.credits else 0 end,
    pr.counts_in_gpa,
    transcript_note_marks(pr.transfer_kind, false, false)
  from prior_academic_record pr
  join term t           on t.id  = transfer_recognition_term(pr.student_id, pr.approved_at)
  join academic_year ay on ay.id = t.academic_year_id
  left join course mc   on mc.id = pr.mapped_course_id
  left join curriculum_course cc
         on cc.course_id = mc.id
        and cc.curriculum_version_id = (
              select sc.curriculum_version_id
                from student_curriculum sc
               where sc.student_id = pr.student_id
               order by sc.effective_to nulls first, sc.effective_from desc
               limit 1)
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where pr.student_id = p_student_id
    and pr.approved_at is not null
$$;

comment on function transcript_courses_grouped(uuid) is
  'รายวิชาของนักศึกษาพร้อมหมวด/กลุ่มตามหลักสูตร รวมวิชาเทียบโอนที่อนุมัติแล้ว · year_be คือภาคที่ลงจริง ส่วน plan_year_be คือภาคตามโครงสร้างหลักสูตร (null เมื่อไม่อยู่ในแผน) · note_marks คือเลข (*n)';

-- ── 6. ส่งเลขเครื่องหมายเข้า payload ────────────────────────────────
--
-- ─── ทำไมต้องอยู่ใน payload ไม่ใช่ให้แม่แบบไปอ่านเอง ───
-- แม่แบบห้ามแตะฐานข้อมูล (หลักข้อ 5ก) และ payload ตรึงตั้งแต่วันที่ออก —
-- ใบที่ออกวันนี้ต้องพิมพ์เครื่องหมายชุดเดิมได้อีกสิบปีแม้ระเบียนจะเปลี่ยน
-- ถ้าแม่แบบคำนวณสดตอนพิมพ์ ใบเก่าจะเปลี่ยนความหมายเมื่อมีคนแก้ข้อมูล
create or replace function transcript_category_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(head order by head ->> 'sort'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'code',        h.head_code,
               'name_th',     h.name_th,
               'sort',        h.sort_key,
               'min_credits', h.min_credits,
               'credits_earned', h.credits_earned,
               'gpa',         h.gpa,
               'groups',
                 coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'code',        g.group_code,
                            'name_th',     g.name_th,
                            'sort',        g.sort_key,
                            'min_credits', g.min_credits,
                            'credits_earned', g.credits_earned,
                            'gpa',         g.gpa,
                            'courses',
                              coalesce((
                                select jsonb_agg(jsonb_build_object(
                                         'term_label',  c.term_label,
                                         'year_be',     c.year_be,
                                         'term_ordinal', c.term_ordinal,
                                         'plan_year_be', c.plan_year_be,
                                         'plan_term_ordinal', c.plan_term_ordinal,
                                         'code',        c.course_code,
                                         'name_th',     c.course_name_th,
                                         'name_en',     c.course_name_en,
                                         'credits',     c.credits,
                                         'grade',       c.grade_symbol,
                                         'grade_point', c.grade_point,
                                         'grade_points',
                                           case when c.counts_in_gpa
                                                then c.grade_point * c.credits end,
                                         'counts_in_gpa', c.counts_in_gpa,
                                         'credits_earned', c.credits_earned,
                                         'notes',       c.note_marks)
                                         order by coalesce(c.plan_year_be, c.year_be),
                                                  coalesce(c.plan_term_ordinal, c.term_ordinal),
                                                  coalesce(c.plan_sort, 0),
                                                  c.course_code)
                                  from transcript_courses_grouped(p_student_id) c
                                 where c.head_code = h.head_code
                                   and c.group_code = g.group_code), '[]'::jsonb))
                          order by g.sort_key)
                     from transcript_category_summary(p_student_id) g
                    where g.level = 'group' and g.head_code = h.head_code), '[]'::jsonb)) as head
        from transcript_category_summary(p_student_id) h
       where h.level = 'head'
    ) x
$$;

comment on function transcript_category_tree(uuid) is
  'โครงหมวด → กลุ่มวิชา → รายวิชา พร้อมยอดสรุปทุกชั้น สำหรับใบ รบ. ตระกูล 67 · notes คือเลข (*n) ท้ายชื่อวิชา';

create or replace function transcript_term_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  with c as (select * from transcript_data(p_student_id)),
  t as (
    select c.term_id,
           min(c.year_be)      as year_be,
           min(c.term_ordinal) as ordinal
      from c
     group by c.term_id
  ),
  s as (
    select t.term_id, t.year_be, t.ordinal,
           ts.credits_earned, ts.gpa, ts.gpax,
           (ts.student_id is not null) as has_summary,
           case when bool_and(ts.student_id is not null)
                     over (order by t.year_be, t.ordinal)
                then sum(ts.credits_earned)
                     over (order by t.year_be, t.ordinal)
           end as credits_cum
      from t
      left join term_summary ts
             on ts.term_id = t.term_id
            and ts.student_id = p_student_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'year_be',        s.year_be,
        'ordinal',        s.ordinal,
        'credits_earned', s.credits_earned,
        'credits_cum',    s.credits_cum,
        'has_summary',    s.has_summary,
        'gpa',            s.gpa,
        'gpax',           s.gpax,
        'courses',
          coalesce((select jsonb_agg(jsonb_build_object(
                             'code',        c.course_code,
                             'name_th',     c.course_name_th,
                             'name_en',     c.course_name_en,
                             'credits',     c.credits,
                             'grade',       c.grade_symbol,
                             'grade_point', c.grade_point,
                             'grade_points', c.grade_points,
                             'counts_in_gpa', c.counts_in_gpa,
                             'credits_earned', c.credits_earned,
                             'notes',       c.note_marks)
                             order by c.course_code)
                     from c where c.term_id = s.term_id), '[]'::jsonb))
      order by s.year_be, s.ordinal),
    '[]'::jsonb)
  from s
$$;

comment on function transcript_term_tree(uuid) is
  'โครงปีการศึกษา → ภาคเรียน → รายวิชา พร้อมสรุปสี่ตัวเลขท้ายภาค สำหรับใบ รบ. ตระกูล 62 — credits_cum เป็น null เมื่อมีภาคที่ยังไม่ได้ตัดยอด · notes คือเลข (*n)';

-- ── 7. (*4) ต้องติดให้เองทุกครั้งที่ลงทะเบียน ไม่ใช่แค่ตอน migrate ───
--
-- ─── ทำไมการ backfill อย่างเดียวไม่พอ ───
-- ข้อ 1 อัปเดตแถวที่มีอยู่แล้วให้ถูกต้อง แต่แถวที่ลงทะเบียนพรุ่งนี้จะได้
-- ค่าเริ่มต้น false ทั้งที่กลุ่มเรียนเป็นทวิภาคี — ใบ รบ. ของรุ่นถัดไปจะ
-- ขาด (*4) โดยไม่มีอะไรฟ้อง และคนที่ตรวจจะเห็นว่า "เคยมีแล้วหายไป"
-- ซึ่งหาสาเหตุยากกว่า "ไม่เคยมี" มาก
--
-- ─── ทำไมยังเก็บเป็นคอลัมน์ ไม่อ่านสดจาก class_section ───
-- เพราะ **นักศึกษาคนเดียวในกลุ่มปกติอาจไปฝึกที่สถานประกอบการ** ตามข้อตกลง
-- รายบุคคล การอ่านสดจากกลุ่มเรียนจะเขียนทับกรณีนั้นทิ้งทุกครั้ง
-- trigger ตั้งค่า**ตั้งต้น**ให้ตรงกับกลุ่มเรียน แล้วปล่อยให้แก้รายคนได้
create or replace function enrollment_workplace_default() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' and new.taught_at_workplace = false then
    select (cs.delivery_mode in ('dvt', 'internship'))
      into new.taught_at_workplace
      from class_section cs
     where cs.id = new.class_section_id;
  end if;
  return new;
end $$;

drop trigger if exists enrollment_workplace_default on enrollment;
create trigger enrollment_workplace_default
  before insert on enrollment
  for each row execute function enrollment_workplace_default();

comment on function enrollment_workplace_default() is
  'ตั้ง (*4) ให้ตรงกับรูปแบบการเรียนของกลุ่มตอนลงทะเบียน — แก้รายคนทีหลังได้';


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0067_regrade_marks_credit_source.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0067 — (*3) เรียนปรับระดับคะแนน ติดให้เองเมื่อคำร้องจากรอบสอบซ่อมมีผล
--
-- ─── ทำไมต้องมีไฟล์นี้ ───
-- 0066 สร้าง `credit_source = 'regraded'` ไว้พร้อมตัวแปลงและแม่แบบที่พิมพ์
-- (*3) ได้จริง แต่ **ไม่มีเส้นทางไหนตั้งค่านั้นเลยสักที่** ถ้าปล่อยไว้มันจะ
-- กลายเป็นของอีกชิ้นในรายการ "ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เกิด"
-- ต่อจาก `can_approve_leave` (ข้อ 15) และ `take_usage_snapshot` (ข้อ 8)
--
-- ─── ทำไมเป็น trigger ไม่ใช่เขียน apply_grade_change() ทับ ───
-- ฟังก์ชันนั้นยาว 1,683 อักขระและมีนิยามเดียวมาตั้งแต่ 0018 การเขียนทับ
-- ทั้งตัวเพื่อเพิ่มบล็อกเดียวคือกับดักที่ 0059 บันทึกไว้ — และผมเพิ่งเดินเข้า
-- ไปเองใน 0066 ตอนคัดลอก `transcript_courses_grouped()` มาจากรุ่นเก่าแล้ว
-- ทำ `plan_year_be` หายไปสองช่อง
--
-- เงื่อนไขที่ต้องดักคือ "คำร้องนี้มีผลแล้ว" ซึ่งเป็นการเปลี่ยนค่าในแถว
-- จึงเป็นรูปที่ trigger ตอบได้ตรงกว่า และดักได้ทุกเส้นทางที่ทำให้คำร้องมีผล
-- ไม่ใช่เฉพาะเส้นที่ผ่าน `apply_grade_change()` (หลักเดียวกับ 0049)
--
-- ─── ทำไมเฉพาะ restudy ไม่รวม retest ───
-- `regrade_kind` มีสองค่า — `retest` คือสอบซ่อม ส่วน `restudy` คือเรียน
-- ปรับระดับคะแนน ถ้อยคำของ (*3) คือ "เรียนปรับระดับคะแนน" ตรงตัว
-- สอบซ่อมคือการสอบใหม่หลังไม่ผ่าน ไม่ใช่การเรียนซ้ำเพื่อยกเกรดที่ผ่านแล้ว
-- ติดเครื่องหมายให้สอบซ่อมด้วยจะทำให้ใบบอกสิ่งที่ไม่ได้เกิดขึ้น
-- ═══════════════════════════════════════════════════════════════════

create or replace function regrade_marks_credit_source() returns trigger
language plpgsql as $$
begin
  if new.status = 'applied' and old.status is distinct from 'applied' then
    /*
     * ─── ทำไมแตะเฉพาะแถวที่ยังเป็น 'studied' ───
     * วิชาที่เทียบโอนมาแล้วมาขอปรับเกรดทีหลังยังต้องคง (*1)/(*2) ไว้
     * เพราะที่มาของหน่วยกิตไม่ได้เปลี่ยน — เปลี่ยนแค่ระดับคะแนน
     * ถ้าเขียนทับ ใบจะบอกว่าเรียนเองทั้งที่โอนมา ซึ่งผิดข้อเท็จจริง
     */
    update enrollment e
       set credit_source = 'regraded'
      from regrade_candidate rc
      join regrade_session_course rsc on rsc.id = rc.session_course_id
      join regrade_session rs         on rs.id  = rsc.session_id
     where rc.change_request_id = new.id
       and rs.kind = 'restudy'
       and e.id = rc.source_enrollment_id
       and e.credit_source = 'studied';
  end if;
  return new;
end $$;

drop trigger if exists regrade_marks_credit_source on grade_change_request;
create trigger regrade_marks_credit_source
  after update on grade_change_request
  for each row execute function regrade_marks_credit_source();

comment on function regrade_marks_credit_source() is
  'ติด (*3) ให้การลงทะเบียนเดิมเมื่อคำร้องจากรอบเรียนปรับระดับคะแนนมีผล — สอบซ่อมไม่ติด';


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0068_receipt.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0068_receipt.sql
--
-- ใบเสร็จรับเงิน — เอกสารที่มีเลขที่ ตรึงเนื้อหา และแก้ไม่ได้
--
-- ─── ช่องที่พบตอนเทียบเมนูการเงินกับระบบที่วิทยาลัยใช้อยู่ ───
-- ระบบนั้นมีสามเมนูที่พูดถึงใบเสร็จ (ตรวจสอบสถานะใบเสร็จ · พิมพ์ใบเสร็จ
-- ย้อนหลัง · แบบฟอร์มชำระเงินผ่านธนาคารที่อ้างเลขที่) ส่วนของเรามีแค่
-- `payment.receipt_no` ซึ่งเป็น**ช่องข้อความที่เจ้าหน้าที่พิมพ์เอง** ตั้งแต่
-- 0010 — ไม่มีตัวเดินเลข ไม่มีแม่แบบพิมพ์ ไม่มีการตรึงเนื้อหา
--
-- ─── ทำไมเรื่องนี้หนักกว่าที่เห็น ───
-- เอกสารอีกแปดใบของระบบนี้ถูกคุมไว้แน่นมาก (เลขเรียงจาก document_series ·
-- payload ตรึง · แก้/ลบไม่ได้ · ยกเลิกต้องมีเหตุผล) แต่ใบเสร็จซึ่งเป็น
-- **เอกสารทางการเงิน**กลับหลุดออกไปทั้งชุด — เลขซ้ำกันสองใบก็ได้ เว้นว่าง
-- ก็ได้ และพิมพ์ใหม่ได้เนื้อหาที่คำนวณสดทุกครั้ง ทั้งที่ผู้ปกครองถือใบหนึ่ง
-- และฝ่ายบัญชีถือสำเนาอีกใบ ซึ่งต้องตรงกันไปตลอด
--
-- สิ่งที่ทำให้มองไม่เห็นคือ `payment` บันทึกครบทุกช่องและยอดคงเหลือคำนวณ
-- ถูกต้องเสมอ ระบบจึงดู "ครบ" จากทุกมุมที่มีเครื่องมือวัด (รูปเดียวกับ
-- ข้อ 8 และข้อ 15 ในรายการที่เคยพังแบบเงียบ ๆ)
--
-- ─── ทำไมใบเสร็จอยู่ใน issued_document ไม่ใช่ตารางของตัวเอง ───
-- คุณสมบัติที่ใบเสร็จต้องมีคือชุดเดียวกับที่ตารางนั้นบังคับอยู่แล้วทุกข้อ
-- เลขที่ไม่ซ้ำต่อประเภทต่อปี · เนื้อหาตรึง ณ วันที่ออก · แก้ไม่ได้ ·
-- ลบไม่ได้ · ยกเลิกต้องมีเหตุผล · พิมพ์ซ้ำอ่านจาก payload
-- การสร้างตารางที่สองที่มีกฎชุดเดียวกันแปลว่าต้องบังคับกฎเหล่านั้นซ้ำอีกรอบ
-- แล้ววันหนึ่งสองที่จะไม่ตรงกัน
--
-- ─── ทำไมออกใบเสร็จจาก post_payment() ไม่ใช่จากชั้น API ───
-- กฎคือ "รับเงินแล้วต้องมีใบเสร็จ" ไม่ใช่ "หน้าจอควรกดออกใบเสร็จด้วย"
-- ถ้ายกขึ้นไปไว้ที่ชั้น API ทางอื่นที่เขียน payment ได้ (สคริปต์นำเข้า ·
-- การกระทบยอดอัตโนมัติ · pgAdmin) จะรับเงินโดยไม่มีใบเสร็จได้เงียบ ๆ
--
-- ─── ทำไม `adjustment` ไม่ได้ใบเสร็จ ───
-- เป็นการปรับปรุงทางบัญชี ไม่ใช่การรับเงินจากใคร ออกใบเสร็จให้แปลว่ามี
-- หลักฐานว่ารับเงินทั้งที่ไม่มีเงินเข้ามา ซึ่งเป็นเอกสารเท็จ
--
-- ─── ทำไมจำนวนเงินตัวอักษรคำนวณที่ฐานข้อมูลแล้วตรึงลง payload ───
-- ถ้าแม่แบบแปลงเลขเป็นตัวอักษรตอนพิมพ์ มันจะเป็นสูตรชุดที่สองที่ค่อย ๆ
-- เพี้ยนไปจากตัวเลขบนใบเดียวกัน และใบที่พิมพ์ปีหน้าจะได้คำอ่านคนละแบบกับ
-- ใบที่ส่งไปแล้ว (หลักข้อ 5 — ค่าที่ตรึงไว้ห้ามคำนวณใหม่)
-- ═══════════════════════════════════════════════════════════════════

-- PostgreSQL ปฏิเสธการใช้ค่า enum ใหม่ใน transaction เดียวกับที่เพิ่มมัน
-- ("unsafe use of new value of enum type") ทั้งไฟล์จึงต้องแยกเป็นสอง
-- transaction — ค่าใหม่ต้อง commit ก่อนจึงเขียนกฎที่อ้างถึงมันได้ (0026)
begin;
alter type document_kind add value if not exists 'receipt';
commit;

begin;

-- ───────────────────────────────────────────────────────────────────
-- จำนวนเงินเป็นตัวอักษร
--
-- เขียนเองเพราะ PostgreSQL ไม่มี bahttext() และเป็นข้อความที่ต้องอยู่บน
-- กระดาษราชการให้ตรงกับตัวเลขเสมอ
-- ───────────────────────────────────────────────────────────────────
create or replace function thai_number_text(p_n bigint)
returns text language plpgsql immutable as $$
declare
  digits constant text[] := array['ศูนย์','หนึ่ง','สอง','สาม','สี่','ห้า','หก','เจ็ด','แปด','เก้า'];
  units  constant text[] := array['','สิบ','ร้อย','พัน','หมื่น','แสน'];
  v_out  text := '';
  v_rest bigint;
  v_s    text;
  v_len  int;
  v_pos  int;
  i      int;
  d      int;
begin
  if p_n = 0 then return digits[1]; end if;

  -- หลักล้านขึ้นไปอ่านเป็นกลุ่มแล้วต่อด้วย "ล้าน" ซ้อนกันได้ไม่จำกัด
  if p_n >= 1000000 then
    v_out  := thai_number_text(p_n / 1000000) || 'ล้าน';
    v_rest := p_n % 1000000;
    if v_rest > 0 then
      v_out := v_out || thai_number_text(v_rest);
    end if;
    return v_out;
  end if;

  v_s   := p_n::text;
  v_len := length(v_s);

  for i in 1 .. v_len loop
    d := substr(v_s, i, 1)::int;
    continue when d = 0;

    v_pos := v_len - i;   -- 0 = หลักหน่วย · 1 = หลักสิบ

    if v_pos = 1 and d = 1 then
      v_out := v_out || 'สิบ';        -- ไม่ใช่ "หนึ่งสิบ"
    elsif v_pos = 1 and d = 2 then
      v_out := v_out || 'ยี่สิบ';      -- ไม่ใช่ "สองสิบ"
    elsif v_pos = 0 and d = 1 and v_len > 1 then
      v_out := v_out || 'เอ็ด';        -- ไม่ใช่ "หนึ่ง" เมื่อมีหลักสูงกว่า
    else
      v_out := v_out || digits[d + 1] || units[v_pos + 1];
    end if;
  end loop;

  return v_out;
end $$;

comment on function thai_number_text(bigint) is
  'อ่านจำนวนเต็มเป็นตัวอักษรไทย — สิบ/ยี่สิบ/เอ็ด เป็นข้อยกเว้นที่ต้องเขียนแยก';

create or replace function thai_baht_text(p_amount numeric)
returns text language plpgsql immutable as $$
declare
  v_abs  numeric := abs(p_amount);
  v_int  bigint;
  v_sat  int;
  v_out  text := '';
begin
  -- ปัดที่สองตำแหน่งก่อนแยกส่วน มิฉะนั้น 0.999 จะได้ 100 สตางค์
  v_abs := round(v_abs, 2);
  v_int := floor(v_abs)::bigint;
  v_sat := round((v_abs - floor(v_abs)) * 100)::int;

  if v_int = 0 and v_sat = 0 then
    return 'ศูนย์บาทถ้วน';
  end if;

  if p_amount < 0 then
    v_out := 'ลบ';
  end if;

  if v_int > 0 then
    v_out := v_out || thai_number_text(v_int) || 'บาท';
  end if;

  if v_sat = 0 then
    v_out := v_out || 'ถ้วน';
  else
    v_out := v_out || thai_number_text(v_sat) || 'สตางค์';
  end if;

  return v_out;
end $$;

comment on function thai_baht_text(numeric) is
  'จำนวนเงินเป็นตัวอักษรสำหรับใบเสร็จ — ตรึงลง payload ตอนออกใบ ไม่คำนวณใหม่ตอนพิมพ์';

-- ───────────────────────────────────────────────────────────────────
-- หนึ่งการรับเงิน หนึ่งใบเสร็จ
--
-- บังคับที่ดัชนี ไม่ใช่ที่ตรรกะในฟังก์ชัน เพราะการเรียก post_payment()
-- ซ้ำ (กระทบยอดใหม่ · เรียกจากสคริปต์) ต้องไม่ทำให้เกิดใบที่สองของเงิน
-- ก้อนเดิม ซึ่งจะกลายเป็นหลักฐานว่ารับเงินสองรอบ
--
-- นับเฉพาะใบที่ยังไม่ถูกยกเลิก — ใบที่ออกผิดต้องยกเลิกแล้วออกใหม่ได้
-- ───────────────────────────────────────────────────────────────────
create unique index issued_document_receipt_payment_uq
  on issued_document ((payload ->> 'payment_id'))
  where kind = 'receipt' and voided_at is null;

-- ───────────────────────────────────────────────────────────────────
-- ใบเสร็จต้องมาจาก issue_receipt() เท่านั้น
--
-- ─── ทำไมเป็น trigger ไม่ใช่การเขียน issue_document() ทับ ───
-- `issue_document()` ยาวสามร้อยบรรทัดและถูกเขียนทับมาแล้วสองรอบเพื่อเพิ่ม
-- เงื่อนไขบรรทัดเดียว (0057/0058 — เหตุผลที่ 0059 ต้องแยก transcript_extra
-- ออกมา) ส่วนกฎนี้เป็นเงื่อนไขระดับ**ค่าในแถว** คือ "ใบเสร็จต้องผูกกับ
-- การรับเงินเสมอ" ซึ่งเป็นรูปเดียวกับที่ 0049 เลือก trigger แทนนโยบาย
--
-- และครอบทุกทาง ไม่ใช่แค่ทางที่ผ่าน issue_document()
-- ───────────────────────────────────────────────────────────────────
create or replace function receipt_needs_payment() returns trigger
language plpgsql as $$
begin
  if new.kind = 'receipt'
     and coalesce(new.payload ->> 'payment_id', '') = '' then
    raise exception 'ใบเสร็จรับเงินต้องออกด้วย issue_receipt() — payload ต้องผูกกับการรับเงินที่เกิดขึ้นจริง'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger issued_document_receipt_guard before insert on issued_document
  for each row execute function receipt_needs_payment();

-- ───────────────────────────────────────────────────────────────────
-- จ่ายเลขที่โดยระบุสถานศึกษาเอง
--
-- ─── ทำไมต้องมีทางที่ไม่พึ่งบริบทของ session ───
-- ใบเสร็จออกจาก `post_payment()` ซึ่งถูกเรียกจาก
-- `reconcile_bank_transactions(p_institution_id)` ที่**รับสถานศึกษามาเป็น
-- พารามิเตอร์อยู่แล้ว** การให้ตัวจ่ายเลขไปอ่าน `current_institution_id()`
-- อีกทางหนึ่งคือมีแหล่งความจริงสองแหล่งของข้อเท็จจริงเดียวกัน ซึ่งถ้าวันหนึ่ง
-- ไม่ตรงกัน ใบเสร็จจะไปกินเลขของสายเลขวิทยาลัยอื่น
--
-- และ**สถานศึกษาของใบเสร็จคือของแถว payment** ไม่ใช่ของคนที่กดปุ่ม —
-- อ่านจากข้อมูลจึงถูกกว่าอ่านจากบริบทเสมอ
--
-- ตัวเดิมสามอาร์กิวเมนต์ยังอยู่ครบและเปลี่ยนพฤติกรรมไม่ได้เลย เพราะมันมา
-- เรียกตัวนี้ต่อ — ไม่ใช่คัดลอกตรรกะไปไว้สองที่แล้วรอให้เพี้ยนกันทีหลัง
-- ───────────────────────────────────────────────────────────────────
create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text,
  p_inst    uuid
) returns text language plpgsql as $$
declare
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if p_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  insert into document_series (institution_id, kind, year_be, lang, prefix)
  values (p_inst, p_kind, p_year_be, p_lang,
          case when p_lang = 'th' then p_year_be::text
               else 'E' || p_year_be::text end)
  on conflict (institution_id, kind, year_be, lang) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = p_inst and kind = p_kind
     and year_be = p_year_be and lang = p_lang
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint, text, uuid) is
  'จ่ายเลขที่เอกสารของสถานศึกษาที่ระบุ — ใช้เมื่อผู้เรียกรู้สถานศึกษาจากข้อมูล ไม่ใช่จากบริบทของ session';

create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text default 'th'
) returns text language sql as $$
  select next_document_no(p_kind, p_year_be, p_lang, current_institution_id())
$$;

-- ───────────────────────────────────────────────────────────────────
-- ออกใบเสร็จ
--
-- คืนใบเดิมถ้าเงินก้อนนี้เคยออกไปแล้ว ไม่ใช่ raise — เพราะผู้เรียกที่
-- ต้องการ "ใบเสร็จของเงินก้อนนี้" ควรได้ใบนั้น ไม่ใช่ล้มทั้งรายการ
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_receipt(p_payment_id uuid)
returns issued_document language plpgsql as $$
declare
  v_pay     payment;
  v_inst    uuid;
  v_year    smallint;
  v_doc_no  text;
  v_lines   jsonb;
  v_alloc   numeric(12,2);
  v_payload jsonb;
  v_row     issued_document;
begin
  select * into v_pay from payment where id = p_payment_id;
  if v_pay.id is null then
    raise exception 'ไม่พบรายการรับเงินรหัสที่ระบุ หรือไม่มีสิทธิ์เข้าถึง';
  end if;

  -- สถานศึกษาของใบเสร็จมาจากแถวเงินรับ ไม่ใช่จากบริบทของ session
  v_inst := v_pay.institution_id;

  -- ออกใบไปแล้วก็คืนใบเดิม (พิมพ์ซ้ำต้องได้ใบเดียวกันเสมอ)
  select * into v_row from issued_document d
   where d.kind = 'receipt'
     and d.payload ->> 'payment_id' = p_payment_id::text
     and d.voided_at is null
   limit 1;
  if v_row.id is not null then
    return v_row;
  end if;

  if v_pay.student_id is null then
    raise exception 'เงินก้อนนี้ยังไม่รู้ว่าเป็นของนักศึกษาคนไหน จึงออกใบเสร็จให้ใครไม่ได้ (payment=%)', p_payment_id
      using errcode = 'check_violation';
  end if;

  if v_pay.method = 'adjustment' then
    raise exception 'รายการปรับปรุงทางบัญชีไม่ใช่การรับเงิน จึงออกใบเสร็จไม่ได้'
      using errcode = 'check_violation';
  end if;

  -- ปีการศึกษาที่ครอบวันที่รับเงิน — ไม่ใช่ปีปัจจุบันของนาฬิกา เพราะเงินที่
  -- บันทึกย้อนหลังต้องอยู่ในสายเลขของปีที่รับจริง
  v_year := coalesce(
    (select ay.year_be from academic_year ay
      where ay.institution_id = v_inst
        and v_pay.received_on between ay.starts_on and ay.ends_on
      order by ay.year_be desc limit 1),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from v_pay.received_on) + 543)::smallint);

  v_doc_no := next_document_no('receipt'::document_kind, v_year, 'th', v_inst);

  /*
   * รายการบนใบคือ "เงินก้อนนี้ไปตัดงวดไหนบ้าง" ไม่ใช่รายการค่าธรรมเนียม
   * ทั้งใบแจ้งหนี้ — ใบเสร็จต้องแสดงสิ่งที่**จ่ายจริงในครั้งนี้** ถ้าพิมพ์
   * รายการทั้งใบแจ้งหนี้จะได้กระดาษที่ยอดรวมไม่ตรงกับเงินที่รับ
   */
  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_no', inv.invoice_no,
           'term',       jsonb_build_object('year_be', ay.year_be, 'ordinal', t.ordinal),
           'seq',        i.seq,
           'due_on',     i.due_on,
           'amount',     a.amount
         ) order by inv.invoice_no, i.seq), '[]'::jsonb),
       coalesce(sum(a.amount), 0)
    into v_lines, v_alloc
    from payment_allocation a
    join installment i   on i.id = a.installment_id
    join invoice inv     on inv.id = i.invoice_id
    join term t          on t.id = inv.term_id
    join academic_year ay on ay.id = t.academic_year_id
   where a.payment_id = p_payment_id;

  v_payload := jsonb_build_object(
    'kind',       'receipt',
    'payment_id', p_payment_id,
    'issued_at',  now(),
    'year_be',    v_year,
    'institution',
      (select jsonb_build_object('name_th', ins.name_th, 'code', ins.code)
         from institution ins where ins.id = v_inst),
    'student',
      (select jsonb_build_object(
                'student_code', s.student_code,
                'full_name', trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                                  || ' ' || coalesce(p.last_name_th, '')))
         from student s join person p on p.id = s.person_id
        where s.id = v_pay.student_id),
    'payment', jsonb_build_object(
        'received_on', v_pay.received_on,
        'amount',      v_pay.amount,
        'method',      v_pay.method,
        'bank_ref',    v_pay.bank_ref,
        'note',        v_pay.note),
    'lines',       v_lines,
    -- เงินที่ยังไม่ได้ตัดงวด (ชำระเกิน) ต้องอยู่บนใบด้วย มิฉะนั้นยอดรวมของ
    -- รายการจะไม่เท่ากับเงินที่รับ แล้วคนอ่านจะคิดว่าใบพิมพ์ผิด
    'unallocated', v_pay.amount - v_alloc,
    'amount_text', thai_baht_text(v_pay.amount),
    'received_by',
      (select trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                   || ' ' || coalesce(p.last_name_th, ''))
         from person p where p.id = coalesce(v_pay.received_by, current_actor_id())));

  insert into issued_document (institution_id, student_id, kind, doc_no, issued_by, payload)
  values (v_inst, v_pay.student_id, 'receipt', v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  /*
   * เขียนเลขกลับลง payment.receipt_no
   *
   * ช่องนี้มีมาตั้งแต่ 0010 พร้อม unique (institution, receipt_no) และเคย
   * เป็นช่องที่คนกรอกเอง — การให้ระบบเป็นคนเขียนทำให้ข้อจำกัดเดิมกลายเป็น
   * ตัวกันเลขซ้ำจริง ๆ และหน้าจอ/รายงานที่อ่านช่องนี้อยู่แล้วใช้ได้ทันที
   */
  update payment set receipt_no = v_doc_no where id = p_payment_id;

  return v_row;
end $$;

comment on function issue_receipt(uuid) is
  'ออกใบเสร็จของการรับเงินหนึ่งครั้ง — เนื้อหาตรึง ณ วันที่ออก และคืนใบเดิมถ้าเคยออกไปแล้ว';

-- ───────────────────────────────────────────────────────────────────
-- ผูกเข้ากับการรับเงิน
--
-- เขียนทับ post_payment() ทั้งตัวเพราะต้องเติมขั้นสุดท้าย ส่วนที่เหลือ
-- เหมือน 0010 ทุกบรรทัด
-- ───────────────────────────────────────────────────────────────────
create or replace function post_payment(p_payment_id uuid)
returns numeric language plpgsql as $$
declare
  v_remaining numeric(12,2);
  v_student   uuid;
  v_method    payment_method;
  r           record;
  v_take      numeric(12,2);
begin
  select amount, student_id, method into v_remaining, v_student, v_method
  from payment where id = p_payment_id;

  if v_student is null then
    raise exception 'เงินรับก้อนนี้ยังไม่ได้ระบุว่าเป็นของนักศึกษาคนไหน (payment=%)', p_payment_id;
  end if;

  for r in
    select i.id, i.amount + i.penalty - i.paid_amount as outstanding
    from installment i
    join invoice inv on inv.id = i.invoice_id
    where inv.student_id = v_student
      and inv.status not in ('void', 'written_off')
      and i.status <> 'paid'
      and i.amount + i.penalty - i.paid_amount > 0
    order by i.due_on, i.seq
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, r.outstanding);

    insert into payment_allocation (payment_id, installment_id, amount)
    values (p_payment_id, r.id, v_take)
    on conflict (payment_id, installment_id)
      do update set amount = payment_allocation.amount + excluded.amount;

    update installment
    set paid_amount = paid_amount + v_take,
        status = case when paid_amount + v_take >= amount + penalty
                      then 'paid'::installment_status
                      else 'partially_paid'::installment_status end
    where id = r.id;

    v_remaining := v_remaining - v_take;
  end loop;

  -- ปรับยอดบนใบแจ้งหนี้
  update invoice inv
  set paid_total = sub.paid,
      status = case when sub.paid >= inv.total then 'paid'::invoice_status
                    when sub.paid > 0          then 'partially_paid'::invoice_status
                    else inv.status end
  from (
    select i.invoice_id, sum(i.paid_amount) as paid
    from installment i
    join invoice v on v.id = i.invoice_id
    where v.student_id = v_student
    group by i.invoice_id
  ) sub
  where inv.id = sub.invoice_id;

  update payment
  set status = 'reconciled', reconciled_at = now()
  where id = p_payment_id;

  -- ออกใบเสร็จเป็นขั้นสุดท้าย หลังตัดงวดเสร็จแล้ว เพราะรายการบนใบคือ
  -- ผลของการตัด ถ้าออกก่อนจะได้ใบที่ไม่มีรายการสักบรรทัด
  if v_method <> 'adjustment' then
    perform issue_receipt(p_payment_id);
  end if;

  return v_remaining;   -- เงินเหลือที่ยังไม่ได้ตัด (ชำระเกิน)
end $$;

comment on function post_payment is
  'ตัดงวดตามลำดับกำหนดชำระ แล้วออกใบเสร็จให้อัตโนมัติ (ยกเว้นรายการปรับปรุง) — คืนเงินที่เหลือหลังตัดครบ ถ้ามากกว่าศูนย์แปลว่าชำระเกิน';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0069_academic_history_import.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0069_academic_history_import.sql
--
-- นำเข้าประวัติการเรียนเดิมเป็นชุด — ปิดช่องที่ import_kind เปิดไว้ตั้งแต่
-- 0023 แต่ไม่มีฟังก์ชันตรวจ/นำเข้าจริงรองรับ
--
-- ─── ทำไมช่องนี้ค้างมาตั้งแต่ 0023 ───
-- `import_kind` มีค่า 'academic_history' และ `prior_academic_record.batch_id`
-- มี FK ไปยัง `import_batch` มาตั้งแต่ต้น แต่ `ImportService.apply()` มีแค่
-- `student` กับ `staff` — ยิง kind นี้ผ่าน `/import` ได้ถึงขั้นสร้างรอบ แต่
-- validate ไม่ตรวจอะไรเลย (ไม่มี validator ให้เลือก จึงข้ามการ update
-- errors/ok ทั้งก้อน) แล้ว apply ปฏิเสธด้วย "ยังไม่รองรับชนิดนี้" เสมอ
-- เป็นรูปเดียวกับ `take_usage_snapshot()` และ `generate_class_meetings()`
-- ที่ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น
--
-- ทางเข้าที่ใช้งานได้จริงตอนนี้มีแต่ `POST /prior-records` (เพิ่มทีละคน/
-- ทีละไม่กี่รายการ ต้องรู้ student UUID) ซึ่งใช้ตอนรับนักศึกษาย้ายเข้าคนเดียว
-- แต่วิทยาลัยที่ย้ายมาใช้ระบบนี้มีนักศึกษาเทียบโอนหลักร้อยพร้อมกัน — วางเป็น
-- ตารางจากตารางคะแนนเดิมทีเดียวเหมือนนำเข้านักศึกษา/บุคลากร ต้องมีฟังก์ชัน
-- คู่นี้เพื่อให้ `/import` กับ kind='academic_history' ใช้งานได้จริง
--
-- ─── ทำไมต้องตรวจว่านักศึกษามีอยู่แล้ว (สลับขั้วกับ validate_student_row) ───
-- การนำเข้านักศึกษาใหม่ต้องไม่ให้รหัสซ้ำของเดิม แต่ประวัติการเรียนเดิม
-- ต้องผูกกับนักศึกษาที่**มีอยู่แล้ว**ในระบบเท่านั้น — แถวที่ชี้รหัสไม่มีจริง
-- จะสร้างประวัติลอย ๆ ที่ไม่มีใครเป็นเจ้าของ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจข้อมูลประวัติการเรียนเดิมหนึ่งแถว — คืนปัญหาทั้งหมด ไม่หยุดที่ข้อแรก
-- เหตุผลเดียวกับ validate_student_row
-- ───────────────────────────────────────────────────────────────────
create or replace function validate_academic_history_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors  text[] := '{}';
  v_code    text := nullif(btrim(p_payload->>'student_code'), '');
  v_student uuid;
  v_source  text := nullif(btrim(p_payload->>'source_th'), '');
  v_term    text := nullif(btrim(p_payload->>'term_label'), '');
  v_course  text := nullif(btrim(p_payload->>'course_code'), '');
  v_name    text := nullif(btrim(p_payload->>'course_name_th'), '');
  v_credits text := p_payload->>'credits';
  v_symbol  text := nullif(btrim(p_payload->>'grade_symbol'), '');
  v_point   text := nullif(p_payload->>'grade_point', '');
  v_kind    text := nullif(btrim(p_payload->>'transfer_kind'), '');
  v_mapped  text := nullif(btrim(p_payload->>'mapped_course_code'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวนักศึกษา');
  else
    select id into v_student from student
     where institution_id = p_institution_id and student_code = v_code;
    if v_student is null then
      v_errors := array_append(v_errors, format('ไม่พบนักศึกษารหัส %s ในวิทยาลัยนี้', v_code));
    end if;
  end if;

  if v_source is null then v_errors := array_append(v_errors, 'ไม่มีชื่อสถานศึกษาเดิม'); end if;
  if v_course is null then v_errors := array_append(v_errors, 'ไม่มีรหัสวิชา'); end if;
  if v_name   is null then v_errors := array_append(v_errors, 'ไม่มีชื่อวิชา'); end if;
  if v_symbol is null then v_errors := array_append(v_errors, 'ไม่มีสัญลักษณ์ผลการเรียน'); end if;

  if v_credits is null or v_credits !~ '^\d+(\.\d)?$' or v_credits::numeric <= 0 then
    v_errors := array_append(v_errors, 'หน่วยกิตต้องเป็นตัวเลขมากกว่าศูนย์');
  end if;

  if v_point is not null
     and (v_point !~ '^\d+(\.\d)?$' or v_point::numeric < 0 or v_point::numeric > 4) then
    v_errors := array_append(v_errors, 'แต้มระดับคะแนนต้องเป็นตัวเลขระหว่าง 0.0-4.0');
  end if;

  if v_kind is not null and v_kind not in ('transferred_grade', 'transferred_experience') then
    v_errors := array_append(v_errors,
      format('ชนิดการโอน "%s" ไม่ถูกต้อง — ต้องเป็น transferred_grade หรือ transferred_experience', v_kind));
  end if;

  if v_mapped is not null and not exists (
       select 1 from course where institution_id = p_institution_id and code = v_mapped) then
    v_errors := array_append(v_errors, format('ไม่พบรายวิชารหัส %s ในหลักสูตรของวิทยาลัยนี้', v_mapped));
  end if;

  -- ซ้ำกับประวัติที่มีอยู่แล้ว — ตรวจเฉพาะเมื่อมีภาคเรียนระบุ เพราะ unique
  -- constraint ของตารางไม่ถือว่า term_label เป็น NULL สองแถวซ้ำกัน
  if v_student is not null and v_course is not null and v_term is not null
     and exists (select 1 from prior_academic_record
                  where student_id = v_student and course_code = v_course and term_label = v_term) then
    v_errors := array_append(v_errors,
      format('มีประวัติวิชา %s ภาค %s ของนักศึกษาคนนี้อยู่แล้ว', v_course, v_term));
  end if;

  return v_errors;
end $$;

comment on function validate_academic_history_row(uuid, jsonb) is
  'ตรวจแถวประวัติการเรียนเดิมก่อนนำเข้า — นักศึกษาต้องมีอยู่แล้วในระบบ (สลับขั้วกับ validate_student_row ที่ห้ามรหัสซ้ำ)';

-- ───────────────────────────────────────────────────────────────────
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย เหตุผลเดียวกับ apply_student_import
--
-- ผูก batch_id กับทุกแถวที่สร้าง เพื่อให้ตอบได้ว่าแถวไหนมาจากไฟล์ไหนเมื่อไร
-- เหมือน import_batch ทุกชนิด — ต่างจาก POST /prior-records ที่เพิ่มทีละคน
-- ซึ่งไม่ผูก batch เพราะไม่มีไฟล์ต้นทางให้ตามรอย
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_academic_history_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch   import_batch%rowtype;
  r         record;
  v_student uuid;
  v_mapped  uuid;
  v_kind    text;
  v_prior   uuid;
  v_bad     integer := 0;
  v_ok      integer := 0;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'academic_history' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ประวัติการเรียนเดิม', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_academic_history_row(v_batch.institution_id, r.payload);
      update import_row
         set errors = v_errs, ok = (cardinality(v_errs) = 0)
       where id = r.id;
      if cardinality(v_errs) > 0 then v_bad := v_bad + 1; end if;
    end;
  end loop;

  if v_bad > 0 then
    update import_batch
       set status = 'failed', error_rows = v_bad,
           ok_rows = (select count(*) from import_row where batch_id = p_batch_id and ok)
     where id = p_batch_id;
    -- ข้อความไม่ชี้ไปที่ import_row เพราะ raise rollback การเขียน errors ข้างบนไปด้วย
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    select id into v_student from student
     where institution_id = v_batch.institution_id
       and student_code = btrim(r.payload->>'student_code');

    v_mapped := null;
    if nullif(btrim(r.payload->>'mapped_course_code'), '') is not null then
      select id into v_mapped from course
       where institution_id = v_batch.institution_id
         and code = btrim(r.payload->>'mapped_course_code')
       order by edition_be desc limit 1;
    end if;

    v_kind := coalesce(nullif(btrim(r.payload->>'transfer_kind'), ''), 'transferred_experience');

    insert into prior_academic_record
      (student_id, batch_id, source_th, term_label, course_code, course_name_th,
       credits, grade_symbol, grade_point, mapped_course_id, transfer_kind, counts_in_gpa, note)
    values (
      v_student, p_batch_id,
      btrim(r.payload->>'source_th'),
      nullif(btrim(r.payload->>'term_label'), ''),
      btrim(r.payload->>'course_code'),
      btrim(r.payload->>'course_name_th'),
      (r.payload->>'credits')::numeric,
      btrim(r.payload->>'grade_symbol'),
      nullif(r.payload->>'grade_point', '')::numeric,
      v_mapped,
      v_kind::credit_source_kind,
      -- โอนผลการเรียนยกเกรดเดิมมาด้วย จึงนับ GPA · เทียบโอนความรู้และ
      -- ประสบการณ์ให้หน่วยกิตอย่างเดียว หลักเดียวกับ ImportService.addPriorRecords
      v_kind = 'transferred_grade',
      nullif(btrim(r.payload->>'note'), '')
    )
    returning id into v_prior;

    update import_row set created_ref = v_prior, ok = true where id = r.id;
    v_ok := v_ok + 1;
  end loop;

  update import_batch
     set status = 'applied', applied_at = now(),
         ok_rows = v_ok, error_rows = 0, total_rows = v_ok
   where id = p_batch_id;

  imported := v_ok;
  failed   := 0;
  return next;
end $$;

comment on function apply_academic_history_import(uuid) is
  'นำเข้าประวัติการเรียนเดิมทั้งชุด — มีแถวใดผิดจะไม่เขียนอะไรเลย และผูก batch_id กับทุกแถวที่สร้างเพื่อตามรอยได้';

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0070_clubs.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0070_clubs.sql
--
-- วิชาชุมนุม/ชมรม — บันทึกพื้นฐาน (ชื่อชมรม ผู้ดูแล สมาชิก)
--
-- ─── ทำไมยังไม่ผูกกับเกณฑ์จบ ───
-- `graduation_rule.kind = 'cocurricular_all_terms'` ("กิจกรรมเสริมหลักสูตร
-- ผ่านทุกภาคเรียน") มีอยู่แล้วในหลักสูตรทุกฉบับ แต่การผูกชมรมเข้ากับเกณฑ์นั้น
-- ต้องตัดสินใจเพิ่มว่า "เข้าร่วม" กับ "ผ่าน" ต่างกันยังไง (มาไม่ครบทุกครั้ง
-- นับว่าผ่านไหม) ซึ่งเป็นคนละงานกับการมีที่บันทึกชื่อชมรมกับสมาชิกก่อน —
-- ผูกคะแนน/หน่วยกิตทีหลังเมื่อรู้กติกาจริงของวิทยาลัย ไม่งั้นเดาเกณฑ์เอง
-- แล้วเกณฑ์จบใช้ตัวเลขที่เดามาโดยไม่มีใครสั่ง
-- ═══════════════════════════════════════════════════════════════════
begin;

create table club (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  code           text        not null,
  name_th        text        not null,
  category_th    text,                        -- เช่น "กีฬา" "วิชาการ" "ศิลปะ" — ข้อความอิสระ ไม่ตรึงเป็น enum
  advisor_staff_id uuid      references staff on delete set null,
  description_th text,
  active         boolean     not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (institution_id, code)
);
create index on club (institution_id) where active;

comment on table club is
  'ชมรม/วิชาชุมนุม — บันทึกพื้นฐาน ยังไม่ผูกกับเกณฑ์จบหรือหน่วยกิตกิจกรรม (ดูคอมเมนต์บนไฟล์)';

create table club_member (
  id          uuid        primary key default gen_random_uuid(),
  club_id     uuid        not null references club on delete cascade,
  student_id  uuid        not null references student on delete cascade,
  academic_year_id uuid   not null references academic_year on delete restrict,
  role        text        not null default 'member',   -- 'member' | 'leader'
  joined_on   date        not null default current_date,
  left_on     date,
  created_at  timestamptz not null default now(),
  unique (club_id, student_id, academic_year_id)
);
create index on club_member (student_id);

comment on column club_member.academic_year_id is
  'ชมรมสมัครใหม่ทุกปีการศึกษา — คนเดิมที่สมัครซ้ำปีถัดไปนับเป็นสมาชิกใหม่ของปีนั้น ไม่ใช่แถวเดิมที่ยังค้าง';

-- set_updated_at() มีมาตั้งแต่ 0001 — ใช้ตัวเดิม ไม่ประกาศซ้ำ
create trigger club_touch before update on club
  for each row execute function set_updated_at();

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table club enable row level security;
alter table club force  row level security;

create policy tenant_isolation on club
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy club_write on club
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_update on club
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_delete on club
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

alter table club_member enable row level security;
alter table club_member force  row level security;

create policy tenant_isolation on club_member
  using (student_institution(club_member.student_id) = current_institution_id())
  with check (student_institution(club_member.student_id) = current_institution_id());

-- อ่านได้: บทบาทระดับวิทยาลัย, ครู (ดูของนักศึกษาที่ตัวเองดูแล/สอนไม่ได้แยกในนี้
-- เพราะสมาชิกชมรมไม่ใช่ข้อมูลอ่อนไหว), เจ้าตัวเอง, ผู้ปกครองที่ยืนยันแล้ว
create policy club_member_scope on club_member
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or club_member.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = club_member.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null)
  );

create policy club_member_write on club_member
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_member_update on club_member
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_member_delete on club_member
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

grant select, insert, update, delete on club, club_member to app_runtime;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0071_national_exam_results.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0071_national_exam_results.sql
--
-- ผลสอบ O-NET/V-NET — ตารางแบบทั่วไปก่อน ยังไม่ได้เทียบกับรูปแบบไฟล์จริง
-- ที่ สอศ./สทศ. ส่งมา (หลักการเดียวกับ PVRS ก่อนยืนยันรูปแบบ — ดู
-- pvrs_rows() และคอมเมนต์ formatConfirmed ใน CLAUDE.md) รหัสวิชาและชื่อวิชา
-- จึงเป็นข้อความอิสระ ไม่ตรึงเป็น enum หรือตารางอ้างอิง เพราะยังไม่รู้ชุด
-- วิชาที่แน่นอนของไฟล์จริง (O-NET กับ V-NET มีจำนวนและชื่อวิชาต่างกัน)
--
-- ─── ทำไม on conflict do update ไม่ใช่ all-or-nothing แบบ apply_student_import ───
-- คะแนนแต่ละแถวเป็นของนักศึกษาคนละคน ไม่ใช่ชุดข้อมูลเดียวที่ต้องครบถ้วน
-- ด้วยกัน (ต่างจากประวัติการเรียนเดิมที่ทุกแถวเป็นของ "รอบนำเข้า" เดียว
-- ที่ต้องตามรอยได้) แถวหนึ่งพิมพ์รหัสนักศึกษาผิดไม่ควรทำให้อีกสามสิบเก้าคน
-- ที่ถูกต้องบันทึกไม่ได้ไปด้วย — หลักเดียวกับ register_courses_bulk()
-- ═══════════════════════════════════════════════════════════════════
begin;

create table national_exam_result (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  student_id     uuid          not null references student on delete cascade,
  exam_kind      text          not null default 'onet',   -- 'onet' | 'vnet' — ข้อความอิสระ เผื่อมีชนิดอื่นภายหลัง
  exam_year_be   smallint      not null check (exam_year_be between 2500 and 2700),
  subject_code   text          not null,
  subject_th     text          not null,
  score          numeric(5,2)  not null check (score >= 0 and score <= 100),
  created_at     timestamptz   not null default now(),
  updated_at     timestamptz   not null default now(),
  unique (student_id, exam_kind, exam_year_be, subject_code)
);
create index on national_exam_result (institution_id, exam_kind, exam_year_be);

comment on table national_exam_result is
  'ผลสอบระดับชาติ (O-NET/V-NET) — โครงตารางทั่วไป ยังไม่เทียบกับรูปแบบไฟล์จริงที่หน่วยงานส่งมา';

create trigger national_exam_result_touch before update on national_exam_result
  for each row execute function set_updated_at();

-- ───────────────────────────────────────────────────────────────────
-- บันทึกผลเป็นกลุ่ม — รายวิชา/รายคนที่ผิดไม่ทำให้ทั้งชุดล้ม
--
-- คืนผลรายแถว (status/detail) แทนการ raise เหตุผลเดียวกับ
-- register_courses_bulk() — ไฟล์ผลสอบมีเป็นร้อยแถว แถวเดียวพิมพ์รหัส
-- นักศึกษาผิดต้องไม่ทำให้อีกร้อยแถวที่ถูกบันทึกไม่ได้
-- ───────────────────────────────────────────────────────────────────
create or replace function record_onet_results_bulk(p_rows jsonb)
returns table (row_no integer, student_code text, subject_code text, status text, detail text)
language plpgsql as $$
-- คอลัมน์ที่คืนออกไป (student_code, subject_code) ซ้ำชื่อกับคอลัมน์จริงใน
-- student/national_exam_result — สั่งให้ WHERE ตีความเป็นคอลัมน์เสมอ
-- (รูปแบบเดียวกับ register_courses_bulk ใน 0026)
#variable_conflict use_column
declare
  r         jsonb;
  v_idx     integer := 0;
  v_inst    uuid := current_institution_id();
  v_student uuid;
  v_code    text;
  v_kind    text;
  v_year    text;
  v_subject_code text;
  v_subject_th   text;
  v_score   text;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    v_idx := v_idx + 1;
    v_code := nullif(btrim(r->>'studentCode'), '');
    v_kind := coalesce(nullif(btrim(r->>'examKind'), ''), 'onet');
    v_year := r->>'examYearBe';
    v_subject_code := nullif(btrim(r->>'subjectCode'), '');
    v_subject_th   := nullif(btrim(r->>'subjectTh'), '');
    v_score := r->>'score';

    begin
      if v_code is null then
        raise exception 'ไม่มีรหัสนักศึกษา';
      end if;
      select id into v_student from student
       where institution_id = v_inst and student_code = v_code;
      if v_student is null then
        raise exception 'ไม่พบนักศึกษารหัส %', v_code;
      end if;
      if v_subject_code is null or v_subject_th is null then
        raise exception 'ไม่มีรหัสหรือชื่อวิชา';
      end if;
      if v_year !~ '^\d{4}$' then
        raise exception 'ปีที่สอบต้องเป็นพุทธศักราชสี่หลัก';
      end if;
      if v_score !~ '^\d+(\.\d+)?$' or v_score::numeric < 0 or v_score::numeric > 100 then
        raise exception 'คะแนนต้องเป็นตัวเลข 0-100';
      end if;

      insert into national_exam_result
        (institution_id, student_id, exam_kind, exam_year_be, subject_code, subject_th, score)
      values (v_inst, v_student, v_kind, v_year::smallint, v_subject_code, v_subject_th, v_score::numeric)
      on conflict (student_id, exam_kind, exam_year_be, subject_code)
      do update set subject_th = excluded.subject_th, score = excluded.score, updated_at = now();

      row_no := v_idx; student_code := v_code; subject_code := v_subject_code;
      status := 'saved'; detail := null;
      return next;
    exception
      when others then
        row_no := v_idx; student_code := v_code; subject_code := v_subject_code;
        status := 'error'; detail := sqlerrm;
        return next;
    end;
  end loop;
end $$;

comment on function record_onet_results_bulk(jsonb) is
  'บันทึกผลสอบ O-NET/V-NET เป็นกลุ่ม คืนผลรายแถว — แถวที่ผิดไม่ทำให้แถวอื่นบันทึกไม่ได้ (หลักเดียวกับ register_courses_bulk)';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security — รูปแบบเดียวกับ prior_academic_record (0023/0044)
-- ───────────────────────────────────────────────────────────────────
alter table national_exam_result enable row level security;
alter table national_exam_result force  row level security;

create policy tenant_isolation on national_exam_result
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy national_exam_result_scope on national_exam_result
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or national_exam_result.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = national_exam_result.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_grades)
  );

create policy national_exam_result_write on national_exam_result
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','director','admin']));
create policy national_exam_result_update on national_exam_result
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','academic','director','admin']));
create policy national_exam_result_delete on national_exam_result
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','director','admin']));

grant select, insert, update, delete on national_exam_result to app_runtime;

commit;


-- ───────────────────────────────────────────────────────────────────
-- แหล่งที่มา: migrations/0072_graduation_survey.sql
-- ───────────────────────────────────────────────────────────────────

-- ═══════════════════════════════════════════════════════════════════
-- 0072_graduation_survey.sql
--
-- แบบสำรวจภาวะการมีงานทำของผู้สำเร็จการศึกษา — ชุดคำถามมาตรฐานทั่วไป
-- ยังไม่ได้เทียบกับแบบฟอร์มที่ สอศ. กำหนดจริง (เหมือน O-NET ใน 0071)
--
-- ─── ทำไมไม่ผูก unique (student_id) ───
-- วิทยาลัยบางแห่งสำรวจซ้ำหลังจบ (เช่น ทันทีที่จบ + ตามผลอีกครั้งหลังจบ 1 ปี)
-- ผูก unique ไว้ตั้งแต่ต้นจะปิดทางสำรวจซ้ำโดยไม่มีเหตุผลรองรับ — ปล่อยให้มี
-- ได้หลายแถวต่อคน แล้วหน้าจอแสดงแถวล่าสุดเป็นค่าเริ่มต้น
-- ═══════════════════════════════════════════════════════════════════
begin;

create type employment_status_kind as enum (
  'employed', 'employed_and_studying', 'further_study', 'seeking', 'other'
);

create table graduation_survey_response (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  student_id     uuid          not null references student on delete cascade,
  graduation_id  uuid          references student_graduation on delete set null,
  status         employment_status_kind not null,

  employer_name_th  text,
  job_title_th      text,
  monthly_income    numeric(10,2),
  field_matches_study boolean,

  further_study_institution_th text,
  further_study_field_th       text,

  contact_phone  text,
  note           text,

  responded_on   date          not null default current_date,
  recorded_by    uuid,                       -- staff ที่โทรสำรวจ — ว่างได้ถ้าบัณฑิตตอบเอง
  created_at     timestamptz   not null default now(),

  constraint graduation_survey_employed_needs_employer
    check (status not in ('employed', 'employed_and_studying') or employer_name_th is not null),
  constraint graduation_survey_study_needs_institution
    check (status not in ('further_study', 'employed_and_studying') or further_study_institution_th is not null)
);
create index on graduation_survey_response (student_id);
create index on graduation_survey_response (institution_id, responded_on desc);

comment on table graduation_survey_response is
  'แบบสำรวจภาวะการมีงานทำของผู้สำเร็จการศึกษา — ชุดคำถามทั่วไป ยังไม่เทียบกับแบบฟอร์มที่ สอศ. กำหนดจริง ปล่อยให้สำรวจซ้ำได้หลายรอบต่อคนโดยตั้งใจ';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security — รูปแบบเดียวกับ prior_academic_record / national_exam_result
-- ───────────────────────────────────────────────────────────────────
alter table graduation_survey_response enable row level security;
alter table graduation_survey_response force  row level security;

create policy tenant_isolation on graduation_survey_response
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy graduation_survey_scope on graduation_survey_response
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or graduation_survey_response.student_id in (select actor_student_ids())
  );

create policy graduation_survey_write on graduation_survey_response
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','student_affairs','academic','director','admin']));
create policy graduation_survey_update on graduation_survey_response
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','student_affairs','academic','director','admin']));
create policy graduation_survey_delete on graduation_survey_response
  as restrictive for delete
  using (current_app_role() = any (array['registrar','student_affairs','academic','director','admin']));

grant select, insert, update, delete on graduation_survey_response to app_runtime;

commit;

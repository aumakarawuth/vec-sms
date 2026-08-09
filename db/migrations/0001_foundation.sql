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

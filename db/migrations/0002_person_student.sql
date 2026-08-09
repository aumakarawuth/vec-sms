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

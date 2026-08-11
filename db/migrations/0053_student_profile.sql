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

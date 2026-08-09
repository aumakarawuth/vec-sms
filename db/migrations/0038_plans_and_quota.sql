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

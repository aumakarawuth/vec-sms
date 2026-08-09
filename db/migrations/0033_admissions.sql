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

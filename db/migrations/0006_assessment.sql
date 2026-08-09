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

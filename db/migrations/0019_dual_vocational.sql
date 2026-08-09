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

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

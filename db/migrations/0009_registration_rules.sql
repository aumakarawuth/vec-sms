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

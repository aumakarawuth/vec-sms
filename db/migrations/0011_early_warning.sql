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

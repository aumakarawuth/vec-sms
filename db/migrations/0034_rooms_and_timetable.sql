-- ═══════════════════════════════════════════════════════════════════
-- 0034_rooms_and_timetable.sql
--
-- ห้องเรียนเป็นข้อมูลจริง และการจัดตารางสอน
--
-- ─── ทำไมต้องทำห้องให้เป็นตารางก่อน ───
-- ก่อนไฟล์นี้ ห้องเป็นข้อความอิสระใน class_section.room และ
-- section_timeslot.room ซึ่งใช้ตรวจการชนของห้องไม่ได้เลย — "ห้อง 301"
-- กับ "ห้อง301" กับ "301" เป็นคนละห้องในสายตาฐานข้อมูล ผลคือจัดสองวิชา
-- ลงห้องเดียวกันเวลาเดียวกันได้โดยไม่มีอะไรฟ้อง แล้วไปรู้ตอนครูสองคน
-- พานักศึกษามายืนหน้าห้องเดียวกัน
--
-- และห้องปฏิบัติการต้องแยกจากห้องบรรยาย เพราะวิชาที่ต้องใช้โรงฝึกงาน
-- จัดลงห้องบรรยายไม่ได้ ซึ่งข้อความอิสระบอกไม่ได้
--
-- ─── ทำไมกล้าลบคอลัมน์ข้อความทิ้ง ───
-- ทั้งระบบมีที่เขียนค่าห้องสามแห่งและอ่านหนึ่งแห่ง ทั้งหมดอยู่ในมือเรา
-- การเก็บทั้งข้อความและคีย์ไว้คู่กันจะกลายเป็นความจริงสองชุดที่ค่อย ๆ
-- ไม่ตรงกัน แล้ววันหนึ่งจะไม่มีใครรู้ว่าอันไหนคือห้องจริง
--
-- ─── การชนกันสี่แบบที่ตัวตรวจจับ ───
-- 1. ครูคนเดียวสอนสองที่พร้อมกัน
-- 2. ห้องเดียวถูกใช้สองวิชาพร้อมกัน
-- 3. นักศึกษากลุ่มเดียวกันมีสองวิชาพร้อมกัน (หลักสูตรฉบับเดียวกัน + ห้องเดียวกัน)
-- 4. นักศึกษาที่ลงทะเบียนแล้วมีสองวิชาชนกันจริง
--
-- ข้อ 3 กับข้อ 4 ต่างกันตรงเวลาที่ใช้ได้ — ตอนจัดตารางยังไม่มีใครลงทะเบียน
-- จึงต้องใช้ "กลุ่มตามแผน" (ข้อ 3) ส่วนข้อ 4 ใช้ตรวจย้อนหลังหลังเปิดเทอม
-- ว่ามีใครติดตารางชนจริงไหม ถ้ามีแต่ข้อ 4 อย่างเดียวจะตรวจอะไรไม่ได้เลย
-- ตอนที่ยังจัดตารางอยู่ ซึ่งเป็นตอนที่ต้องการมันที่สุด
--
-- ─── ทำไมตัวจัดอัตโนมัติเป็นแบบโลภ ไม่ใช่หาคำตอบที่ดีที่สุด ───
-- การจัดตารางที่ดีที่สุดเป็นปัญหา NP-hard การหาคำตอบที่ดีที่สุดจริง ๆ
-- กับวิชาสองพันกว่าตัวใช้เวลานานเกินกว่าจะรอในหน้าจอ และคำตอบที่ "ดีที่สุด"
-- ตามสูตรมักขัดกับข้อจำกัดจริงที่ไม่ได้อยู่ในฐานข้อมูล (ครูคนนี้ไม่สอนเช้า
-- เพราะต้องส่งลูก) ตัวจัดนี้จึงวางให้ได้มากที่สุดเท่าที่ไม่ชน แล้ว
-- **รายงานว่าวิชาไหนวางไม่ได้และเพราะอะไร** ให้คนไปตัดสินใจต่อ
-- ไม่ใช่ยัดลงไปให้ครบแล้วปล่อยให้ไปเจอปัญหาหน้างาน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ห้องเรียน
-- ───────────────────────────────────────────────────────────────────
create type room_kind as enum
  ('classroom', 'workshop', 'lab', 'computer', 'auditorium', 'outdoor');

comment on type room_kind is
  'ประเภทห้อง — workshop คือโรงฝึกงาน ใช้กับวิชาที่ course.needs_workshop';

create table room (
  id             uuid      primary key default gen_random_uuid(),
  institution_id uuid      not null references institution on delete restrict,
  code           text      not null,
  name_th        text      not null,
  kind           room_kind not null default 'classroom',
  capacity       smallint  check (capacity is null or capacity > 0),
  building       text,
  active         boolean   not null default true,
  created_at     timestamptz not null default now(),
  unique (institution_id, code)
);

comment on table room is
  'ห้องเรียนจริง — ก่อนหน้านี้เป็นข้อความอิสระ ซึ่งทำให้ตรวจการชนของห้องไม่ได้';

create index room_institution_idx on room (institution_id, kind) where active;

-- ── ย้ายข้อมูลเดิมจากคอลัมน์ข้อความ ────────────────────────────────
insert into room (institution_id, code, name_th, kind)
select distinct cs.institution_id, btrim(cs.room), btrim(cs.room),
       case when cs.room ilike '%โรงฝึก%' or cs.room ilike '%ปฏิบัติการ%'
            then 'workshop'::room_kind else 'classroom'::room_kind end
  from class_section cs
 where nullif(btrim(cs.room), '') is not null
on conflict (institution_id, code) do nothing;

insert into room (institution_id, code, name_th, kind)
select distinct cs.institution_id, btrim(st.room), btrim(st.room),
       case when st.room ilike '%โรงฝึก%' or st.room ilike '%ปฏิบัติการ%'
            then 'workshop'::room_kind else 'classroom'::room_kind end
  from section_timeslot st
  join class_section cs on cs.id = st.class_section_id
 where nullif(btrim(st.room), '') is not null
on conflict (institution_id, code) do nothing;

alter table class_section    add column room_id uuid references room on delete restrict;
alter table section_timeslot add column room_id uuid references room on delete restrict;

update class_section cs
   set room_id = r.id
  from room r
 where r.institution_id = cs.institution_id
   and r.code = btrim(cs.room);

update section_timeslot st
   set room_id = r.id
  from class_section cs, room r
 where cs.id = st.class_section_id
   and r.institution_id = cs.institution_id
   and r.code = btrim(st.room);

-- v_room_conflict จาก 0009 เทียบห้องด้วยข้อความ ซึ่งเป็นเหตุผลที่ไฟล์นี้มีอยู่ —
-- "ห้อง 301" กับ "301" ไม่เท่ากัน วิวจึงมองไม่เห็นการชนที่เกิดขึ้นจริง
-- สร้างใหม่ให้เทียบด้วยคีย์ของห้องแทน
drop view if exists v_room_conflict;

-- ความจริงสองชุดที่ค่อย ๆ ไม่ตรงกันแก้ยากกว่าการย้ายให้จบตั้งแต่ตอนนี้
alter table class_section    drop column room;
alter table section_timeslot drop column room;

create view v_room_conflict as
select cs1.term_id,
       t1.room_id,
       r.code as room_code,
       t1.day_of_week,
       cs1.id as section_a,
       cs2.id as section_b,
       int4range(t1.period_from, t1.period_to, '[]')
         * int4range(t2.period_from, t2.period_to, '[]') as overlapping_periods
  from section_timeslot t1
  join class_section cs1 on cs1.id = t1.class_section_id
  join room r            on r.id   = t1.room_id
  join section_timeslot t2
    on t2.day_of_week = t1.day_of_week
   and t2.room_id = t1.room_id
   and int4range(t2.period_from, t2.period_to, '[]')
       && int4range(t1.period_from, t1.period_to, '[]')
  join class_section cs2 on cs2.id = t2.class_section_id
 where cs1.term_id = cs2.term_id and cs1.id < cs2.id;

alter view v_room_conflict set (security_invoker = true);

create index section_timeslot_room_idx on section_timeslot (room_id, day_of_week);

-- ───────────────────────────────────────────────────────────────────
-- นโยบายตารางสอน
-- ───────────────────────────────────────────────────────────────────
create table timetable_policy (
  institution_id  uuid     primary key references institution on delete cascade,
  periods_per_day smallint not null default 10 check (periods_per_day between 1 and 20),
  days_per_week   smallint not null default 5  check (days_per_week between 1 and 7),
  lunch_period    smallint check (lunch_period is null or lunch_period > 0),
  max_consecutive smallint not null default 4  check (max_consecutive between 1 and 10)
);

comment on column timetable_policy.lunch_period is
  'คาบพักกลางวัน — ตัวจัดอัตโนมัติจะไม่วางคาบเรียนทับ และตัวตรวจจะเตือนถ้ามีคนวางเอง';
comment on column timetable_policy.max_consecutive is
  'จำนวนคาบติดกันสูงสุดที่ยอมให้จัดในวันเดียว — กันวิชาเดียวยาวทั้งวัน';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจการชนของคาบที่เสนอ
--
-- คืน "รายการปัญหา" ไม่ใช่ true/false — หน้าจอจึงบอกได้ว่าชนกับอะไรบ้าง
-- หลักเดียวกับ check_registration() ใน 0009
-- ───────────────────────────────────────────────────────────────────
create or replace function timeslot_conflicts(
  p_class_section_id uuid,
  p_day_of_week      smallint,
  p_period_from      smallint,
  p_period_to        smallint,
  p_room_id          uuid default null,
  p_ignore_slot_id   uuid default null
) returns table (
  kind             text,
  message_th       text,
  other_section_id uuid
) language sql stable as $$
  with me as (
    select cs.id, cs.term_id, cs.teacher_id, cs.curriculum_version_id,
           cs.section_no, cs.institution_id, c.needs_workshop
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.id = p_class_section_id
  ),
  policy as (
    select tp.* from timetable_policy tp
     join me on me.institution_id = tp.institution_id
  ),
  overlapping as (
    select st.id as slot_id, st.class_section_id, st.room_id,
           cs2.teacher_id, cs2.curriculum_version_id, cs2.section_no,
           c2.code as course_code, c2.name_th as course_name
      from section_timeslot st
      join class_section cs2 on cs2.id = st.class_section_id
      join course c2         on c2.id  = cs2.course_id
      cross join me
     where cs2.term_id = me.term_id
       and st.class_section_id <> p_class_section_id
       and (p_ignore_slot_id is null or st.id <> p_ignore_slot_id)
       and st.day_of_week = p_day_of_week
       and int4range(st.period_from, st.period_to, '[]')
           && int4range(p_period_from, p_period_to, '[]')
  )
  -- 1. ครูคนเดียวสอนสองที่พร้อมกัน
  select 'teacher',
         'ครูผู้สอนติดสอน ' || o.course_code || ' ' || o.course_name || ' ในคาบเดียวกัน',
         o.class_section_id
    from overlapping o cross join me
   where me.teacher_id is not null and o.teacher_id = me.teacher_id

  union all
  -- 2. ห้องเดียวถูกใช้สองวิชาพร้อมกัน
  select 'room',
         'ห้องนี้ถูกใช้โดย ' || o.course_code || ' ' || o.course_name || ' ในคาบเดียวกัน',
         o.class_section_id
    from overlapping o
   where p_room_id is not null and o.room_id = p_room_id

  union all
  -- 3. นักศึกษากลุ่มเดียวกันตามแผน — ใช้ได้ตั้งแต่ตอนจัดตาราง
  --    ก่อนที่จะมีใครลงทะเบียน ซึ่งเป็นตอนที่ต้องการมันที่สุด
  select 'cohort',
         'ห้องเรียน ' || coalesce(me.section_no, '-') || ' ติดเรียน '
           || o.course_code || ' ' || o.course_name || ' ในคาบเดียวกัน',
         o.class_section_id
    from overlapping o cross join me
   where me.curriculum_version_id is not null
     and o.curriculum_version_id = me.curriculum_version_id
     and o.section_no is not distinct from me.section_no

  union all
  -- 4. นักศึกษาที่ลงทะเบียนแล้วชนจริง — ใช้ตรวจย้อนหลังหลังเปิดเทอม
  select distinct 'enrolled',
         'มีนักศึกษาที่ลงทะเบียนทั้งวิชานี้และ ' || o.course_code || ' อยู่แล้ว',
         o.class_section_id
    from overlapping o
   where exists (
     select 1 from enrollment e1
       join enrollment e2 on e2.student_id = e1.student_id
      where e1.class_section_id = p_class_section_id
        and e2.class_section_id = o.class_section_id
        and e1.status = 'enrolled' and e2.status = 'enrolled')

  union all
  -- 5. ห้องเรียนรายวิชานี้มีคาบอยู่แล้วในช่วงเวลานั้น
  --
  --    ข้อนี้ดูเหมือนซ้ำซ้อนกับ exclusion constraint ที่กันไว้อยู่แล้ว
  --    แต่จำเป็น เพราะตัวเสนอคาบว่างต้องรู้ล่วงหน้าว่าวางไม่ได้
  --    ไม่ใช่ไปรู้ตอนที่ insert แล้วล้ม — ตัวจัดอัตโนมัติที่วางหลายบล็อก
  --    ให้วิชาเดียวกันจะเสนอคาบเดิมซ้ำไปเรื่อย ๆ ถ้าไม่มีข้อนี้
  select 'self',
         'ห้องเรียนรายวิชานี้มีคาบเรียนอยู่แล้วในช่วงเวลานี้',
         null::uuid
    from section_timeslot st
   where st.class_section_id = p_class_section_id
     and (p_ignore_slot_id is null or st.id <> p_ignore_slot_id)
     and st.day_of_week = p_day_of_week
     and int4range(st.period_from, st.period_to, '[]')
         && int4range(p_period_from, p_period_to, '[]')

  union all
  -- 6. วิชาที่ต้องใช้โรงฝึกงานจัดลงห้องบรรยายไม่ได้
  select 'room_kind',
         'วิชานี้ต้องใช้โรงฝึกงาน แต่ห้องที่เลือกเป็น ' || r.name_th,
         null::uuid
    from me join room r on r.id = p_room_id
   where me.needs_workshop and r.kind not in ('workshop', 'lab', 'computer')

  union all
  -- 7. ทับคาบพักกลางวันหรือเกินจำนวนคาบต่อวัน
  select 'policy',
         case when p.lunch_period is not null
                   and p.lunch_period between p_period_from and p_period_to
              then 'คาบนี้ทับคาบพักกลางวัน (คาบ ' || p.lunch_period || ')'
              when p_period_to > p.periods_per_day
              then 'เกินจำนวนคาบต่อวันที่กำหนดไว้ (' || p.periods_per_day || ' คาบ)'
              else 'เกินจำนวนวันเรียนต่อสัปดาห์ที่กำหนดไว้ (' || p.days_per_week || ' วัน)'
         end,
         null::uuid
    from policy p
   where (p.lunch_period is not null
          and p.lunch_period between p_period_from and p_period_to)
      or p_period_to > p.periods_per_day
      or p_day_of_week > p.days_per_week;
$$;

comment on function timeslot_conflicts(uuid, smallint, smallint, smallint, uuid, uuid) is
  'ตรวจว่าคาบที่เสนอชนกับอะไรบ้าง — คืนรายการปัญหาทั้งหมด ไม่ใช่หยุดที่ข้อแรก';

-- ───────────────────────────────────────────────────────────────────
-- คาบว่างที่วางได้
--
-- ไล่ทุกวันทุกคาบแล้วคัดเฉพาะที่ไม่ชนอะไรเลย เรียงตามวันและคาบ
-- เพื่อให้ตารางกระจุกอยู่ต้นสัปดาห์และต้นวัน ซึ่งเป็นรูปแบบที่วิทยาลัยใช้จริง
-- ───────────────────────────────────────────────────────────────────
create or replace function suggest_timeslots(
  p_class_section_id uuid,
  p_periods          smallint default 2,
  p_room_id          uuid default null,
  p_limit            integer default 10
) returns table (
  day_of_week smallint,
  period_from smallint,
  period_to   smallint
) language sql stable as $$
  with me as (
    select cs.institution_id from class_section cs where cs.id = p_class_section_id
  ),
  policy as (
    select coalesce(tp.periods_per_day, 10) as periods_per_day,
           coalesce(tp.days_per_week, 5)    as days_per_week
      from me left join timetable_policy tp on tp.institution_id = me.institution_id
  ),
  candidates as (
    select d::smallint as day_of_week,
           s::smallint as period_from,
           (s + p_periods - 1)::smallint as period_to
      from policy p,
           generate_series(1, p.days_per_week) d,
           generate_series(1, p.periods_per_day) s
     where s + p_periods - 1 <= p.periods_per_day
  )
  select c.day_of_week, c.period_from, c.period_to
    from candidates c
   where not exists (
     select 1 from timeslot_conflicts(
       p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_room_id))
   order by c.day_of_week, c.period_from
   limit p_limit;
$$;

comment on function suggest_timeslots(uuid, smallint, uuid, integer) is
  'คาบว่างที่วางห้องเรียนรายวิชานี้ได้โดยไม่ชนอะไรเลย';

-- ───────────────────────────────────────────────────────────────────
-- จัดตารางอัตโนมัติทั้งภาคเรียน
--
-- คืนผลรายห้องเรียนเสมอ รวมถึงห้องที่วางไม่ได้และเหตุผล
-- ไม่ raise เพราะห้องหนึ่งวางไม่ได้ต้องไม่ทำให้ทั้งภาคเรียนล้ม
-- ───────────────────────────────────────────────────────────────────
create or replace function auto_schedule_term(p_term_id uuid)
returns table (
  class_section_id uuid,
  label            text,
  action           text,
  periods_placed   smallint,
  note             text
) language plpgsql as $$
#variable_conflict use_column
declare
  r         record;
  v_need    smallint;
  v_have    smallint;
  v_block   smallint;
  v_max     smallint;
  v_placed  smallint;
  v_slot    record;
begin
  select coalesce(max(tp.max_consecutive), 4) into v_max
    from class_section cs
    join timetable_policy tp on tp.institution_id = cs.institution_id
   where cs.term_id = p_term_id;

  for r in
    select cs.id, cs.room_id, c.code, c.name_th, c.weekly_periods,
           coalesce(cs.section_no, '-') as section_no
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.term_id = p_term_id
       and not cs.is_locked
     order by c.code, cs.section_no
  loop
    select coalesce(sum(st.period_to - st.period_from + 1), 0)::smallint
      into v_have
      from section_timeslot st where st.class_section_id = r.id;

    v_need := coalesce(r.weekly_periods, 0)::smallint - v_have;

    if coalesce(r.weekly_periods, 0) = 0 then
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'skipped'::text, v_have,
        'หลักสูตรไม่ได้กำหนดจำนวนคาบต่อสัปดาห์ของรายวิชานี้'::text;
      continue;
    end if;

    if v_need <= 0 then
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'already_full'::text, v_have, null::text;
      continue;
    end if;

    v_placed := 0;

    while v_need > 0 loop
      v_block := least(v_need, v_max)::smallint;

      select * into v_slot
        from suggest_timeslots(r.id, v_block, r.room_id, 1);

      -- ลองบล็อกที่สั้นลงก่อนยอมแพ้ — ตารางที่แตกเป็นคาบเดี่ยวยังดีกว่าไม่มี
      while v_slot is null and v_block > 1 loop
        v_block := (v_block - 1)::smallint;
        select * into v_slot
          from suggest_timeslots(r.id, v_block, r.room_id, 1);
      end loop;

      exit when v_slot is null;

      insert into section_timeslot
        (class_section_id, day_of_week, period_from, period_to, room_id)
      values (r.id, v_slot.day_of_week, v_slot.period_from, v_slot.period_to, r.room_id);

      v_placed := (v_placed + v_block)::smallint;
      v_need   := (v_need - v_block)::smallint;
      v_slot   := null;
    end loop;

    if v_need > 0 then
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'partial'::text, v_placed,
        format('วางได้ %s คาบ ยังขาดอีก %s คาบ ไม่มีคาบว่างที่ไม่ชน', v_placed, v_need)::text;
    else
      return query select r.id, (r.code || ' ' || r.section_no)::text,
        'scheduled'::text, v_placed, null::text;
    end if;
  end loop;
end $$;

comment on function auto_schedule_term(uuid) is
  'จัดตารางสอนทั้งภาคเรียนแบบโลภ — วางให้ได้มากที่สุดเท่าที่ไม่ชน แล้วรายงานวิชาที่วางไม่ครบ';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจการชนของตารางทั้งภาคเรียน
--
-- ใช้ตรวจหลังจัดเสร็จหรือหลังมีคนแก้ตารางเอง
-- ───────────────────────────────────────────────────────────────────
create or replace function timetable_conflicts(p_term_id uuid)
returns table (
  class_section_id uuid,
  label            text,
  day_of_week      smallint,
  period_from      smallint,
  period_to        smallint,
  kind             text,
  message_th       text
) language sql stable as $$
  select st.class_section_id,
         (c.code || ' ' || coalesce(cs.section_no, '-'))::text,
         st.day_of_week, st.period_from, st.period_to,
         cf.kind, cf.message_th
    from section_timeslot st
    join class_section cs on cs.id = st.class_section_id
    join course c         on c.id  = cs.course_id
    cross join lateral timeslot_conflicts(
      st.class_section_id, st.day_of_week, st.period_from, st.period_to,
      st.room_id, st.id) cf
   where cs.term_id = p_term_id
   order by st.day_of_week, st.period_from, c.code;
$$;

comment on function timetable_conflicts(uuid) is
  'การชนทั้งหมดในตารางของภาคเรียน — เปิดดูหลังจัดเสร็จหรือหลังมีคนแก้ตารางเอง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table room enable row level security;
alter table room force  row level security;
create policy tenant_isolation on room
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

alter table timetable_policy enable row level security;
alter table timetable_policy force  row level security;
create policy tenant_isolation on timetable_policy
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

commit;

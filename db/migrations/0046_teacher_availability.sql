-- ═══════════════════════════════════════════════════════════════════
-- 0046_teacher_availability.sql
--
-- ข้อจำกัดเวลาสอนรายบุคคล — "ครูคนนี้ไม่สอนเช้าวันจันทร์"
--
-- ─── ทำไมตัวจัดตารางที่ไม่รู้ข้อจำกัดนี้ใช้งานจริงไม่ได้ ───
-- ทุกวิทยาลัยมีข้อจำกัดแบบนี้เสมอ — ครูที่สอนสองวิทยาเขต ครูที่ลาศึกษาต่อ
-- ครึ่งวัน ครูที่เป็นวิทยากรภายนอกซึ่งมาได้แค่บ่ายวันพุธ
--
-- ตัวจัดอัตโนมัติที่ไม่รู้เรื่องนี้จะวางคาบทับเวลาที่ครูไม่อยู่ แล้วคนจัด
-- ต้องมานั่งแก้ทีละคาบ ซึ่งใช้เวลามากกว่าจัดเองตั้งแต่แรก — ผลคือไม่มีใคร
-- ใช้ตัวจัดอัตโนมัติเลย
--
-- ─── ทำไมเก็บเป็น "ช่วงที่ไม่ว่าง" ไม่ใช่ "ช่วงที่ว่าง" ───
-- ครูส่วนใหญ่ว่างเกือบทั้งสัปดาห์ ถ้าเก็บช่วงที่ว่าง ทุกคนต้องกรอกทุกคาบ
-- ของทุกวันตั้งแต่ต้น และครูที่ยังไม่ได้กรอกจะกลายเป็น "ไม่ว่างเลย"
-- ซึ่งทำให้ตัวจัดตารางวางอะไรไม่ได้เลยทั้งวิทยาลัยในวันแรกที่เปิดใช้
--
-- เก็บเป็นช่วงที่ไม่ว่างแทน — ครูที่ไม่ได้กรอกอะไรคือครูที่ว่างตลอด
-- ซึ่งตรงกับความจริงและทำให้ deploy แล้วไม่มีอะไรพัง
--
-- ─── ทำไมมีทั้งแบบ "ห้าม" และ "เลี่ยงถ้าได้" ───
-- ครูที่ติดสอนอีกวิทยาเขตคือ **ห้าม** วางจริง ๆ ส่วนครูที่ขอไม่สอนคาบแรก
-- เพราะบ้านไกลคือ **เลี่ยงถ้าได้** ถ้าปนกันเป็นข้อห้ามทั้งหมด ตารางจะจัด
-- ไม่ลงเมื่อมีคำขอมาก และคนจัดจะเริ่มลบคำขอทิ้งเพื่อให้จัดได้ —
-- ซึ่งทำให้ข้อมูลนี้เชื่อถือไม่ได้ทั้งตาราง
-- ═══════════════════════════════════════════════════════════════════
begin;

create type availability_kind as enum ('unavailable', 'prefer_not');

comment on type availability_kind is
  'unavailable = ห้ามวาง (ติดภารกิจจริง) · prefer_not = เลี่ยงถ้าได้ (ความสะดวกส่วนตัว)';

create table teacher_availability (
  id             uuid              primary key default gen_random_uuid(),
  institution_id uuid              not null references institution on delete restrict,
  staff_id       uuid              not null references staff on delete cascade,
  term_id        uuid              references term on delete cascade,
  day_of_week    smallint          not null check (day_of_week between 1 and 7),
  period_from    smallint          not null check (period_from >= 1),
  period_to      smallint          not null check (period_to >= period_from),
  kind           availability_kind not null default 'unavailable',
  reason         text,
  created_by     uuid,
  created_at     timestamptz       not null default now()
);

comment on table teacher_availability is
  'ช่วงเวลาที่ครูสอนไม่ได้หรือขอเลี่ยง — ไม่กรอกอะไรเลยคือว่างตลอด';
comment on column teacher_availability.term_id is
  'จำกัดเฉพาะภาคเรียนนี้ — null คือใช้ทุกภาคเรียน (เช่นครูที่สอนสองวิทยาเขตประจำ)';

create index teacher_availability_lookup_idx
  on teacher_availability (staff_id, day_of_week);

-- ───────────────────────────────────────────────────────────────────
-- ครูของกลุ่มเรียนนี้ติดอะไรในช่วงเวลาที่จะวางหรือไม่
--
-- คืนเป็นแถว ไม่ใช่ boolean เพราะตัวเสนอคาบต้องบอกได้ว่า **ทำไม** วางไม่ได้
-- (หลักเดียวกับ timeslot_conflicts ที่คืนชนิดของการชน)
-- ───────────────────────────────────────────────────────────────────
create or replace function teacher_unavailable(
  p_class_section_id uuid,
  p_day_of_week      smallint,
  p_period_from      smallint,
  p_period_to        smallint,
  p_term_id          uuid default null
) returns table (
  kind   availability_kind,
  reason text
) language sql stable as $$
  select ta.kind, ta.reason
    from class_section cs
    join teacher_availability ta on ta.staff_id = cs.teacher_id
   where cs.id = p_class_section_id
     and ta.day_of_week = p_day_of_week
     -- ช่วงคาบซ้อนกัน (ไม่ใช่แค่เริ่มตรงกัน)
     and ta.period_from <= p_period_to
     and ta.period_to   >= p_period_from
     -- ข้อจำกัดที่ไม่ผูกภาคเรียนใช้ได้ทุกภาค
     and (ta.term_id is null or ta.term_id = coalesce(p_term_id, ta.term_id))
$$;

comment on function teacher_unavailable(uuid, smallint, smallint, smallint, uuid) is
  'ครูของกลุ่มเรียนติดอะไรในช่วงนี้ — คืนชนิดและเหตุผล เพื่อให้ตัวเสนอคาบบอกได้ว่าทำไมวางไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- ตัวเสนอคาบว่าง — เคารพข้อจำกัดของครู
--
-- คืน `avoids` มาด้วยว่าคาบนี้ตรงกับคำขอ "เลี่ยงถ้าได้" หรือไม่ และเรียง
-- คาบที่ไม่ตรงกับคำขอไว้ก่อน — คนจัดจะได้เลือกคาบที่ทุกฝ่ายพอใจก่อนเสมอ
-- โดยยังเห็นตัวเลือกที่เหลือถ้าจำเป็น
-- ───────────────────────────────────────────────────────────────────
-- ต้อง drop ตัวเดิมก่อน ไม่ใช่ create or replace — ชนิดที่คืนเปลี่ยนไป
-- (เพิ่ม avoids กับ note) และถ้าปล่อยตัวเก่าไว้จะกลายเป็นสองตัวซ้อนกัน
-- แล้วผู้เรียกเดิมที่ส่งสี่อาร์กิวเมนต์จะได้ตัวเก่าที่ไม่รู้จักข้อจำกัดของครู
-- ซึ่งเป็นความล้มเหลวแบบเงียบที่สุด — ระบบทำงานได้แต่ไม่เคารพข้อจำกัดเลย
--
-- อาร์กิวเมนต์ที่ห้าเป็น default จึงเรียกด้วยสี่ตัวได้เหมือนเดิม
-- (auto_schedule_term เรียกแบบนั้นและได้ตัวใหม่ไปโดยไม่ต้องแก้)
drop function if exists suggest_timeslots(uuid, smallint, uuid, integer);

create or replace function suggest_timeslots(
  p_class_section_id uuid,
  p_periods          smallint default 2,
  p_room_id          uuid default null,
  p_limit            integer default 10,
  p_term_id          uuid default null
) returns table (
  day_of_week smallint,
  period_from smallint,
  period_to   smallint,
  avoids      boolean,
  note        text
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
  ),
  usable as (
    select c.*,
           (select ta.kind from teacher_unavailable(
              p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_term_id) ta
             order by ta.kind limit 1) as block_kind,
           (select ta.reason from teacher_unavailable(
              p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_term_id) ta
             order by ta.kind limit 1) as block_reason
      from candidates c
     where not exists (
       select 1 from timeslot_conflicts(
         p_class_section_id, c.day_of_week, c.period_from, c.period_to, p_room_id))
  )
  -- ต้อง coalesce เป็น false ทั้งในคอลัมน์และใน order by
  --
  -- คาบที่ไม่มีข้อจำกัดจะได้ block_kind เป็น null ทำให้ (null = 'prefer_not')
  -- เป็น null ไม่ใช่ false และ PostgreSQL เรียง null ไว้ **ท้ายสุด** ในลำดับ
  -- ขึ้น — ผลคือคาบที่ครูขอเลี่ยง (true) จะถูกเสนอมาก่อนคาบที่ไม่ติดอะไรเลย
  -- ซึ่งกลับด้านกับสิ่งที่ตั้งใจทั้งหมด
  select u.day_of_week, u.period_from, u.period_to,
         coalesce(u.block_kind = 'prefer_not', false) as avoids,
         case when u.block_kind = 'prefer_not'
              then coalesce(u.block_reason, 'ครูขอเลี่ยงคาบนี้') end as note
    from usable u
   -- ห้ามวางถูกตัดออกทั้งหมด ส่วนที่ขอเลี่ยงยังเสนอได้แต่ไปอยู่ท้ายรายการ
   where u.block_kind is distinct from 'unavailable'
   order by coalesce(u.block_kind = 'prefer_not', false),
            u.day_of_week, u.period_from
   limit p_limit;
$$;

comment on function suggest_timeslots(uuid, smallint, uuid, integer, uuid) is
  'คาบว่างที่วางได้จริง — ตัดช่วงที่ครูสอนไม่ได้ออก และเรียงคาบที่ครูขอเลี่ยงไว้ท้ายสุด';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on teacher_availability to app_runtime;
    grant execute on function teacher_unavailable(uuid, smallint, smallint, smallint, uuid)
      to app_runtime;
    grant execute on function suggest_timeslots(uuid, smallint, uuid, integer, uuid)
      to app_runtime;
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ครูอ่านของตัวเองได้ (ต้องเห็นว่าที่แจ้งไปถูกบันทึกแล้ว) แต่เขียนไม่ได้ —
-- ถ้าครูกรอกเองได้ ตารางสอนจะกลายเป็นเรื่องที่ต่อรองกันเองโดยไม่มีใคร
-- ตัดสิน และคนที่กรอกก่อนจะได้คาบที่ดีที่สุดเสมอ
-- ───────────────────────────────────────────────────────────────────
alter table teacher_availability enable row level security;
alter table teacher_availability force  row level security;

create policy tenant_isolation on teacher_availability
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy availability_scope on teacher_availability
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
                where st.id = teacher_availability.staff_id
                  and st.person_id = current_actor_id())
  )
  with check (is_institution_wide_role());

create policy availability_no_teacher_delete on teacher_availability
  as restrictive for delete
  using (is_institution_wide_role());

commit;

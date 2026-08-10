-- ═══════════════════════════════════════════════════════════════════
-- 0048_timetable_scan_once.sql
--
-- ตัวจัดตารางอ่านคาบที่ถูกจองไว้ "ครั้งเดียว" แทนที่จะถามทีละคาบ
--
-- ─── อาการที่พาให้มาแก้ตรงนี้ ───
-- `POST /timetable/terms/:id/auto-schedule` ตอบ 408 (statement_timeout
-- 15 วินาที รหัส 57014) บนเครื่อง CI ส่วน `GET /timetable/suggest`
-- ซึ่งเรียก suggest_timeslots **ครั้งเดียว** ใช้เวลา 7 วินาที
--
-- ─── ทำไมช้าขนาดนั้นทั้งที่ข้อมูลมีไม่กี่สิบแถว ───
-- ต้นทุนไม่ได้อยู่ที่การอ่านข้อมูล แต่อยู่ที่ **การวางแผนคำสั่ง**
-- timeslot_conflicts เป็นคำสั่งเจ็ดท่อน union กัน แตะ section_timeslot ·
-- class_section · course · enrollment · room · timetable_policy ซึ่ง
-- ทุกตารางมีนโยบาย RLS ที่ถูกกางออกเป็นเงื่อนไขซ้อนกันตอนวางแผน
-- แผนที่ได้ยาว ~400 บรรทัด มี SubPlan เกินร้อยชุด — วัดจริงบนเครื่องพัฒนา
-- ได้ planning 12 ms ต่อ execution 1.7 ms คือเวลาหมดไปกับการวางแผนล้วน ๆ
--
-- suggest_timeslots เดิมเรียก timeslot_conflicts **หนึ่งครั้งต่อคาบผู้สมัคร**
-- (8 คาบ × 5 วัน = 40 ครั้ง) และ auto_schedule_term เรียก suggest_timeslots
-- ซ้ำอีกทุกกลุ่มเรียนคูณทุกขนาดบล็อกที่ลองย่อลง — รวมแล้วหลักพันครั้ง
-- ต่อคำขอเดียว
--
-- **สังเกตว่านี่ไม่ใช่ของใหม่** รอบ CI ที่ผ่านครั้งล่าสุดก่อนหน้านี้
-- API-72 ใช้เวลา 14.6 วินาทีจากเพดาน 15 วินาที — ผ่านมาตลอดด้วยเสี้ยววินาที
-- 0046 เพิ่มการตรวจข้อจำกัดของครูเข้าไปอีกชั้นจึงเป็นฟางเส้นสุดท้าย
-- ถ้าแก้แค่ให้ 0046 เบาลง เทสต์จะกลับไปนั่งอยู่ที่ขอบเพดานเหมือนเดิม
-- แล้วแดงอีกเมื่อใดก็ได้ที่ runner ช้ากว่าปกติ จึงแก้ที่รูปแบบการเรียกแทน
--
-- ─── วิธีแก้ ───
-- แยก "คาบไหนถูกจองไปแล้วบ้าง" ออกมาเป็น blocked_periods() ที่คืนผล
-- **ทั้งสัปดาห์ในครั้งเดียว** เป็นรายคาบ แล้วให้ทั้งสองตัวใช้ร่วมกัน
--   · suggest_timeslots เรียกครั้งเดียวแล้ว anti-join กับคาบผู้สมัคร
--   · timeslot_conflicts กรองผลของมันด้วยวันและช่วงคาบที่ถาม
-- กฎการชนจึงยังมีที่อยู่ที่เดียว ไม่ได้คัดลอกไปเขียนซ้ำในตัวเสนอคาบ
-- ซึ่งเป็นสิ่งที่ต้องระวังที่สุดของการแก้แบบนี้ — ตัวเสนอที่รู้กฎไม่ครบ
-- จะเสนอคาบที่วางไม่ได้จริง แล้วตัวจัดอัตโนมัติจะวนเสนอคาบเดิมไม่รู้จบ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- คาบที่ถูกจองไว้แล้วทั้งสัปดาห์ สำหรับกลุ่มเรียนหนึ่ง
--
-- คืนเป็น **รายคาบ** (period ทีละคาบ) ไม่ใช่ช่วง เพราะผู้เรียกทั้งสองฝั่ง
-- ต้องการถามว่า "คาบนี้ว่างไหม" การเทียบช่วงกับช่วงในทุกจุดที่ใช้
-- เปิดโอกาสให้เขียนเงื่อนไขซ้อนทับผิดได้ง่าย (เคยพลาดมาแล้วกับ
-- ta.period_from <= p_period_to and ta.period_to >= p_period_from)
-- ส่วนจำนวนแถวที่เพิ่มขึ้นนั้นไม่มีนัยสำคัญ — คาบต่อวันมีสิบคาบเป็นอย่างมาก
--
-- ครอบคลุมการชนห้าข้อแรกของ timeslot_conflicts ที่เป็น "คาบถูกใช้ไปแล้ว"
-- ส่วนอีกสองข้อ (ห้องผิดประเภท · ผิดนโยบายคาบ) ไม่ขึ้นกับการจองของคนอื่น
-- และคิดได้จากตัวคาบเอง จึงอยู่ที่ผู้เรียกทั้งคู่
-- ───────────────────────────────────────────────────────────────────
create or replace function blocked_periods(
  p_class_section_id uuid,
  p_room_id          uuid default null,
  p_ignore_slot_id   uuid default null
) returns table (
  day_of_week      smallint,
  period           smallint,
  kind             text,
  other_section_id uuid,
  course_code      text,
  course_name      text
) language sql stable as $$
  -- `materialized` ทั้งสองตัวโดยตั้งใจ — ถ้าปล่อยให้ PostgreSQL inline
  -- เข้าไปในแต่ละท่อนของ union ข้างล่าง คำสั่งจะกลับไปกางนโยบาย RLS
  -- ของ class_section กับ course ซ้ำห้ารอบ ซึ่งคือต้นทุนที่มาแก้ตรงนี้
  with me as materialized (
    select cs.id, cs.term_id, cs.teacher_id, cs.curriculum_version_id,
           cs.section_no
      from class_section cs
     where cs.id = p_class_section_id
  ),
  slots as materialized (
    select st.id as slot_id, st.class_section_id, st.room_id,
           st.day_of_week, st.period_from, st.period_to,
           cs2.teacher_id, cs2.curriculum_version_id, cs2.section_no,
           c2.code as course_code, c2.name_th as course_name
      from section_timeslot st
      join class_section cs2 on cs2.id = st.class_section_id
      join course c2         on c2.id  = cs2.course_id
      cross join me
     where cs2.term_id = me.term_id
       and (p_ignore_slot_id is null or st.id <> p_ignore_slot_id)
  ),
  others as (
    select s.* from slots s where s.class_section_id <> p_class_section_id
  ),
  hits as (
    -- 1. ครูคนเดียวสอนสองที่พร้อมกัน
    select o.day_of_week, o.period_from, o.period_to, 'teacher'::text as kind,
           o.class_section_id as other_section_id, o.course_code, o.course_name
      from others o cross join me
     where me.teacher_id is not null and o.teacher_id = me.teacher_id

    union all
    -- 2. ห้องเดียวถูกใช้สองวิชาพร้อมกัน
    select o.day_of_week, o.period_from, o.period_to, 'room',
           o.class_section_id, o.course_code, o.course_name
      from others o
     where p_room_id is not null and o.room_id = p_room_id

    union all
    -- 3. นักศึกษากลุ่มเดียวกันตามแผน — ใช้ได้ตั้งแต่ก่อนมีใครลงทะเบียน
    select o.day_of_week, o.period_from, o.period_to, 'cohort',
           o.class_section_id, o.course_code, o.course_name
      from others o cross join me
     where me.curriculum_version_id is not null
       and o.curriculum_version_id = me.curriculum_version_id
       and o.section_no is not distinct from me.section_no

    union all
    -- 4. นักศึกษาที่ลงทะเบียนแล้วชนจริง — ใช้ตรวจย้อนหลังหลังเปิดเทอม
    select o.day_of_week, o.period_from, o.period_to, 'enrolled',
           o.class_section_id, o.course_code, o.course_name
      from others o
     where exists (
       select 1 from enrollment e1
         join enrollment e2 on e2.student_id = e1.student_id
        where e1.class_section_id = p_class_section_id
          and e2.class_section_id = o.class_section_id
          and e1.status = 'enrolled' and e2.status = 'enrolled')

    union all
    -- 5. กลุ่มเรียนนี้เองมีคาบอยู่แล้ว
    --
    --    ข้อนี้ดูซ้ำซ้อนกับ exclusion constraint ที่กันไว้อยู่แล้ว แต่จำเป็น
    --    เพราะตัวเสนอคาบต้องรู้ล่วงหน้าว่าวางไม่ได้ ไม่ใช่ไปรู้ตอน insert
    --    แล้วล้ม — ตัวจัดอัตโนมัติที่วางหลายบล็อกให้วิชาเดียวกันจะเสนอ
    --    คาบเดิมซ้ำไม่รู้จบถ้าไม่มีข้อนี้
    select s.day_of_week, s.period_from, s.period_to, 'self',
           null::uuid, null::text, null::text
      from slots s
     where s.class_section_id = p_class_section_id
  )
  select h.day_of_week, p::smallint, h.kind, h.other_section_id,
         h.course_code, h.course_name
    -- ต้อง cast เป็น integer เอง — generate_series(smallint, smallint) กำกวม
    -- (PostgreSQL เลือกไม่ได้ระหว่างตัวที่รับ int, bigint และ numeric)
    from hits h, generate_series(h.period_from::integer, h.period_to::integer) p;
$$;

comment on function blocked_periods(uuid, uuid, uuid) is
  'คาบที่ถูกจองไว้แล้วทั้งสัปดาห์ของกลุ่มเรียนนี้ — อ่านครั้งเดียวแล้วใช้ทั้งตัวตรวจและตัวเสนอคาบ';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจการชนของคาบที่เสนอ (เหมือนเดิมทุกอย่างจากมุมผู้เรียก)
--
-- ยังคืน "รายการปัญหา" ไม่ใช่ true/false และข้อความยังเป็นภาษาไทยชุดเดิม
-- เปลี่ยนแค่ที่มาของข้อ 1–5 ให้มาจาก blocked_periods()
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
  with me as materialized (
    select cs.section_no, cs.institution_id, c.needs_workshop
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.id = p_class_section_id
  ),
  policy as (
    select tp.* from timetable_policy tp
     join me on me.institution_id = tp.institution_id
  ),
  -- คาบเดียวกันอาจถูกจองทับหลายคาบติดกัน ต้องยุบเป็นหนึ่งข้อความต่อหนึ่ง
  -- ปัญหา มิฉะนั้นหน้าจอจะขึ้น "ครูติดสอน..." ซ้ำเท่าจำนวนคาบที่ทับกัน
  hit as (
    select distinct b.kind, b.other_section_id, b.course_code, b.course_name
      from blocked_periods(p_class_section_id, p_room_id, p_ignore_slot_id) b
     where b.day_of_week = p_day_of_week
       and b.period between p_period_from and p_period_to
  )
  select h.kind,
         case h.kind
           when 'teacher' then
             'ครูผู้สอนติดสอน ' || h.course_code || ' ' || h.course_name
               || ' ในคาบเดียวกัน'
           when 'room' then
             'ห้องนี้ถูกใช้โดย ' || h.course_code || ' ' || h.course_name
               || ' ในคาบเดียวกัน'
           when 'cohort' then
             'ห้องเรียน ' || coalesce(me.section_no, '-') || ' ติดเรียน '
               || h.course_code || ' ' || h.course_name || ' ในคาบเดียวกัน'
           when 'enrolled' then
             'มีนักศึกษาที่ลงทะเบียนทั้งวิชานี้และ ' || h.course_code || ' อยู่แล้ว'
           else 'ห้องเรียนรายวิชานี้มีคาบเรียนอยู่แล้วในช่วงเวลานี้'
         end,
         h.other_section_id
    from hit h cross join me

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
-- คาบว่างที่วางได้ — อ่านของที่จองไว้ครั้งเดียว
--
-- ผลลัพธ์ต้องเหมือน 0046 ทุกประการ เปลี่ยนแค่จำนวนครั้งที่ถามฐานข้อมูล
-- ───────────────────────────────────────────────────────────────────
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
  with me as materialized (
    select cs.institution_id, cs.teacher_id, c.needs_workshop
      from class_section cs
      join course c on c.id = cs.course_id
     where cs.id = p_class_section_id
  ),
  policy as materialized (
    select coalesce(tp.periods_per_day, 10) as periods_per_day,
           coalesce(tp.days_per_week, 5)    as days_per_week,
           tp.lunch_period
      from me left join timetable_policy tp on tp.institution_id = me.institution_id
  ),
  -- ห้องผิดประเภทแปลว่าวางไม่ได้ทุกคาบเท่ากันหมด ตรวจครั้งเดียวจบ
  -- ไม่ต้องถามซ้ำทุกคาบเหมือนตอนที่ยังเรียก timeslot_conflicts รายคาบ
  room_bad as materialized (
    select 1 from me join room r on r.id = p_room_id
     where me.needs_workshop and r.kind not in ('workshop', 'lab', 'computer')
  ),
  taken as materialized (
    select b.day_of_week, b.period
      from blocked_periods(p_class_section_id, p_room_id) b
  ),
  avoidance as materialized (
    select ta.day_of_week, ta.period_from, ta.period_to, ta.kind, ta.reason
      from me
      join teacher_availability ta on ta.staff_id = me.teacher_id
     where ta.term_id is null or ta.term_id = coalesce(p_term_id, ta.term_id)
  ),
  candidates as (
    select d::smallint as day_of_week,
           s::smallint as period_from,
           (s + p_periods - 1)::smallint as period_to
      from policy p,
           generate_series(1, p.days_per_week) d,
           generate_series(1, p.periods_per_day) s
     where s + p_periods - 1 <= p.periods_per_day
       -- ข้อ 7 ของ timeslot_conflicts: ห้ามคร่อมคาบพักกลางวัน
       -- (เพดานคาบต่อวันและวันต่อสัปดาห์ถูกบังคับด้วยตัว generate_series แล้ว)
       and (p.lunch_period is null
            or p.lunch_period not between s and s + p_periods - 1)
       and not exists (select 1 from room_bad)
  ),
  usable as (
    select c.day_of_week, c.period_from, c.period_to,
           b.kind as block_kind, b.reason as block_reason
      from candidates c
      left join lateral (
        select k.kind, k.reason
          from avoidance k
         where k.day_of_week = c.day_of_week
           -- ช่วงคาบซ้อนกัน (ไม่ใช่แค่เริ่มตรงกัน)
           and k.period_from <= c.period_to
           and k.period_to   >= c.period_from
         -- 'unavailable' มาก่อน 'prefer_not' ตามลำดับที่ประกาศไว้ใน enum
         order by k.kind
         limit 1
      ) b on true
     where not exists (
       select 1 from taken t
        where t.day_of_week = c.day_of_week
          and t.period between c.period_from and c.period_to)
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
    grant execute on function blocked_periods(uuid, uuid, uuid) to app_runtime;
  end if;
end $$;

commit;

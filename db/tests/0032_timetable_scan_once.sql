-- ═══════════════════════════════════════════════════════════════════
-- 0032_timetable_scan_once.sql
-- ทดสอบว่าตัวเสนอคาบกับตัวตรวจการชนยังพูดตรงกัน และยังเร็วพอ
--
-- ─── ทำไมต้องมีไฟล์นี้ ───
-- 0048 แยก "คาบไหนถูกจองแล้ว" ออกมาเป็น blocked_periods() เพื่อให้อ่าน
-- ครั้งเดียวแทนการถาม timeslot_conflicts ทีละคาบ ความเสี่ยงของการแก้แบบนี้
-- มีสองทางและทั้งสองทางพังแบบเงียบ
--
-- 1. **ตัวเสนอรู้กฎไม่ครบ** แล้วเสนอคาบที่วางจริงไม่ได้ ผลคือ insert ล้ม
--    ที่ exclusion constraint หรือ (แย่กว่า) auto_schedule_term วนเสนอ
--    คาบเดิมไม่รู้จบ ระบบไม่ได้ error อะไรเลย แค่ช้าลงเรื่อย ๆ
-- 2. **ตัวเสนอระวังเกิน** แล้วไม่เสนอคาบที่ว่างจริง คนจัดจะเห็นว่า
--    "ไม่มีคาบว่าง" ทั้งที่ตารางยังโล่ง แล้วเลิกใช้ตัวช่วยไปจัดมือเอง
--
-- TEST 216 จึงเทียบคำตอบของสองฟังก์ชันทุกคาบของทั้งสัปดาห์ ไม่ใช่สุ่มดู
--
-- หมายเหตุ psql: ห้ามเขียน :'ตัวแปร' ไว้ใน do $$ ... $$ เพราะ psql ไม่แทนค่า
-- ให้ในสตริงที่ยกด้วยดอลลาร์ ต้องส่งผ่าน set_config แล้วอ่านด้วย
-- current_setting เหมือนไฟล์เทสต์อื่น ๆ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ห้องเป็นตัวเลือก ไม่ใช่เงื่อนไข — ข้อมูลตั้งต้นยังไม่ผูกห้องให้กลุ่มเรียนไหน
-- (การผูกห้องเกิดตอนจัดตาราง) ถ้าบังคับว่าต้องมีห้อง เทสต์จะข้ามทั้งไฟล์
-- แบบเงียบ ๆ ซึ่งแย่กว่าการตรวจโดยไม่มีห้อง — การชนชนิด room กับ room_kind
-- ถูกตรวจไว้แล้วที่ API-69/API-70 ซึ่งสร้างห้องจริงขึ้นมาทดสอบ
--
-- และต้องเลือกกลุ่มที่ **ยังมีคาบว่างยาวสามคาบ** ไม่ใช่กลุ่มแรกที่เจอ
-- กลุ่มที่จัดตารางเต็มแล้วจะทำให้ TEST 218 ข้ามตัวเองไปเงียบ ๆ ซึ่ง
-- แปลว่าเรื่องการยุบข้อความซ้ำไม่เคยถูกตรวจเลยสักรอบ
select cs.id as sec_id, cs.institution_id as inst_id,
       coalesce(cs.room_id::text, '') as room_id
  from class_section cs
 where cs.teacher_id is not null
 order by (select count(*) from suggest_timeslots(cs.id, 3::smallint, cs.room_id, 1)) desc,
          cs.id
 limit 1 \gset

select p.id as academic_person
  from person p
  join staff st      on st.person_id = p.id
  join staff_role sr on sr.staff_id  = st.id
 where sr.role in ('academic', 'registrar')
   and st.institution_id = :'inst_id'
 order by p.id
 limit 1 \gset

-- term ไม่มีคอลัมน์ institution_id เอง (ผูกผ่านปีการศึกษา) จึงกรองจาก
-- กลุ่มเรียนแทน แล้วเลือกภาคที่มีกลุ่มเรียนมากที่สุด — ภาคที่ว่างเปล่า
-- จะทำให้ TEST 217 ผ่านโดยไม่ได้จัดอะไรเลย
select cs.term_id as term_id
  from class_section cs
 where cs.institution_id = :'inst_id'
 group by cs.term_id
 order by count(*) desc, cs.term_id
 limit 1 \gset

select set_config('test.sec',  :'sec_id',  false) as a,
       set_config('test.room', :'room_id', false) as b,
       set_config('test.term', :'term_id', false) as c \gset ctx_

-- ── TEST 216 ───────────────────────────────────────────────────────
-- ทุกคาบของทั้งสัปดาห์ ตัวเสนอกับตัวตรวจต้องตอบตรงกัน
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec       uuid := current_setting('test.sec')::uuid;
  v_room      uuid := nullif(current_setting('test.room'), '')::uuid;
  v_periods   smallint;
  v_days      smallint;
  v_c         record;
  v_conflict  boolean;
  v_blocked   boolean;
  v_suggested boolean;
  v_checked   integer := 0;
  v_disagree  text[] := '{}';
begin
  select coalesce(tp.periods_per_day, 10), coalesce(tp.days_per_week, 5)
    into v_periods, v_days
    from class_section cs
    left join timetable_policy tp on tp.institution_id = cs.institution_id
   where cs.id = v_sec;

  -- วางคาบไว้ก่อนหนึ่งบล็อก เพื่อให้มีการชนจริงให้ทั้งสองฟังก์ชันเจอ
  -- (ถ้าตารางว่างสนิท เทสต์จะผ่านโดยไม่ได้พิสูจน์อะไรเลย)
  insert into section_timeslot (class_section_id, day_of_week, period_from, period_to, room_id)
  select v_sec, s.day_of_week, s.period_from, s.period_to, v_room
    from suggest_timeslots(v_sec, 2::smallint, v_room, 1) s
  on conflict do nothing;

  for v_c in
    select d::smallint as day_of_week, p::smallint as period_from,
           (p + 1)::smallint as period_to
      from generate_series(1, v_days) d, generate_series(1, v_periods - 1) p
  loop
    v_conflict := exists (
      select 1 from timeslot_conflicts(
        v_sec, v_c.day_of_week, v_c.period_from, v_c.period_to, v_room));

    -- ตัวเสนอตัดช่วงที่ครู "ห้ามวาง" ออกด้วย ซึ่งตัวตรวจไม่รู้เรื่อง
    -- จึงต้องหักออกจากการเปรียบเทียบ ไม่ใช่นับเป็นความไม่ตรงกัน
    v_blocked := exists (
      select 1 from teacher_unavailable(
        v_sec, v_c.day_of_week, v_c.period_from, v_c.period_to) tu
       where tu.kind = 'unavailable');

    v_suggested := exists (
      select 1 from suggest_timeslots(v_sec, 2::smallint, v_room, 1000) s
       where s.day_of_week = v_c.day_of_week
         and s.period_from = v_c.period_from);

    v_checked := v_checked + 1;

    if v_suggested <> (not v_conflict and not v_blocked) then
      v_disagree := array_append(v_disagree, format(
        'วัน %s คาบ %s-%s: เสนอ=%s ชน=%s ครูห้าม=%s',
        v_c.day_of_week, v_c.period_from, v_c.period_to,
        v_suggested, v_conflict, v_blocked));
    end if;
  end loop;

  if array_length(v_disagree, 1) > 0 then
    raise exception 'TEST 216 ล้มเหลว: ตัวเสนอกับตัวตรวจตอบไม่ตรงกัน % จุด — %',
      array_length(v_disagree, 1), array_to_string(v_disagree[1:5], ' · ');
  end if;

  if v_checked = 0 then
    raise exception 'TEST 216 ล้มเหลว: ไม่ได้ตรวจคาบไหนเลย';
  end if;

  raise notice 'TEST 216 ผ่าน — ตัวเสนอกับตัวตรวจตอบตรงกันครบ % คาบ', v_checked;
end $$;
rollback;

-- ── TEST 217 ───────────────────────────────────────────────────────
-- จัดตารางทั้งภาคเรียนต้องเสร็จภายในเพดานเวลา — โดยมี RLS ทำงานเต็มรูปแบบ
--
-- ─── ทำไมเทสต์นี้ต้องรันเป็น app_runtime ไม่ใช่ postgres ───
-- superuser ข้าม RLS ทั้งหมด แผนคำสั่งจึงสั้นและเร็วเสมอ ต้นทุนจริงของ
-- ตัวจัดตารางเกือบทั้งหมดคือ **การวางแผนคำสั่งที่กางนโยบาย RLS ออกมา**
-- เทสต์ที่รันเป็น superuser จึงวัดไม่เจออะไรเลย ตอนที่ CI แดงด้วย 408
-- คำสั่งเดียวกันบนเครื่องพัฒนาเป็น superuser ใช้เวลา 9 มิลลิวินาที
--
-- ─── ทำไมตั้งเพดานไว้ 10 วินาที ทั้งที่ควรเสร็จในหลักมิลลิวินาที ───
-- ไม่ได้ต้องการวัดความเร็วของเครื่อง แต่ต้องการจับ **การกลับไปเรียก
-- ทีละคาบ** ซึ่งเคยใช้เวลา 14.6 วินาทีบน CI เพดานนี้จึงกว้างพอที่จะไม่
-- แกว่งตามเครื่อง แต่แคบพอที่รูปแบบเดิมจะไม่รอด
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',         true) as a,
       set_config('app.actor_id',       :'academic_person', true) as b,
       set_config('app.role',           'academic',         true) as c \gset ctx_

set local statement_timeout = '10s';

do $$
declare
  v_term    uuid := current_setting('test.term')::uuid;
  v_rows    integer;
  v_started timestamptz := clock_timestamp();
  v_ms      numeric;
begin
  select count(*) into v_rows from auto_schedule_term(v_term);
  v_ms := extract(epoch from (clock_timestamp() - v_started)) * 1000;

  if v_rows = 0 then
    raise exception 'TEST 217 ล้มเหลว: ไม่มีกลุ่มเรียนให้จัดเลย เทสต์ไม่ได้พิสูจน์อะไร';
  end if;

  raise notice 'TEST 217 ผ่าน — จัดตาราง % กลุ่มเรียนใน % ms (เพดาน 10 วินาที)',
    v_rows, round(v_ms);
end $$;
rollback;

-- ── TEST 218 ───────────────────────────────────────────────────────
-- ข้อความการชนยังเป็นชุดเดิม และไม่ซ้ำเมื่อคาบทับกันหลายคาบ
--
-- blocked_periods() คืนผลเป็นรายคาบ คาบที่ทับกันสามคาบจะได้สามแถว
-- ถ้า timeslot_conflicts ไม่ยุบให้เหลือหนึ่งข้อความ หน้าจอจะขึ้น
-- "ครูผู้สอนติดสอน..." ซ้ำสามครั้งติดกัน ซึ่งดูเหมือนระบบเสีย
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec   uuid := current_setting('test.sec')::uuid;
  v_room  uuid := nullif(current_setting('test.room'), '')::uuid;
  v_slot  record;
  v_kinds text[];
  v_msgs  integer;
begin
  select * into v_slot from suggest_timeslots(v_sec, 3::smallint, v_room, 1);
  if v_slot is null then
    raise notice 'TEST 218 ข้าม — ไม่มีคาบว่างยาวสามคาบให้ทดสอบ';
    return;
  end if;

  insert into section_timeslot (class_section_id, day_of_week, period_from, period_to, room_id)
  values (v_sec, v_slot.day_of_week, v_slot.period_from, v_slot.period_to, v_room);

  -- ถามช่วงที่ทับกันทั้งสามคาบ
  select array_agg(distinct kind) into v_kinds
    from timeslot_conflicts(v_sec, v_slot.day_of_week,
                            v_slot.period_from, v_slot.period_to, v_room);

  if not ('self' = any(v_kinds)) then
    raise exception 'TEST 218 ล้มเหลว: วางทับคาบของตัวเองแล้วไม่ได้ชนิด self — ได้ %',
      array_to_string(v_kinds, ',');
  end if;

  select count(*) into v_msgs
    from timeslot_conflicts(v_sec, v_slot.day_of_week,
                            v_slot.period_from, v_slot.period_to, v_room) tc
   where tc.kind = 'self';

  if v_msgs <> 1 then
    raise exception 'TEST 218 ล้มเหลว: การชนหนึ่งเรื่องคืนข้อความ % ครั้ง '
      '(คาบที่ทับกันหลายคาบต้องยุบเป็นข้อความเดียว)', v_msgs;
  end if;

  if exists (select 1 from timeslot_conflicts(v_sec, v_slot.day_of_week,
                       v_slot.period_from, v_slot.period_to, v_room) tc
              where tc.message_th !~ '[ก-๙]') then
    raise exception 'TEST 218 ล้มเหลว: มีข้อความการชนที่ไม่ใช่ภาษาไทย';
  end if;

  raise notice 'TEST 218 ผ่าน — ชนิดการชน (%) · ไม่มีข้อความซ้ำ · ภาษาไทยครบ',
    array_to_string(v_kinds, ',');
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบตัวจัดตารางแบบอ่านครั้งเดียวครบทุกข้อ ════'; end $$;

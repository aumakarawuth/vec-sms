-- ═══════════════════════════════════════════════════════════════════
-- 0019_timetable.sql
-- ทดสอบห้องเรียนและการจัดตารางสอน
--
-- ─── ทำไมชุดนี้เน้นการชนแบบที่มองไม่เห็น ───
-- ตารางสอนที่ชนกันไม่มีอาการอะไรเลยในฐานข้อมูล — ทุกแถวถูกต้องตามข้อบังคับ
-- ทุกข้อ ปัญหาจะโผล่วันเปิดเทอมตอนที่ครูคนเดียวถูกเรียกไปสองห้องพร้อมกัน
-- หรือนักศึกษากลุ่มหนึ่งมีสองวิชาในคาบเดียวกันแล้วต้องเลือกว่าจะขาดวิชาไหน
--
-- ─── และเน้นว่าตรวจได้ตั้งแต่ยังไม่มีใครลงทะเบียน ───
-- การจัดตารางเกิดขึ้นก่อนการลงทะเบียนเสมอ ตัวตรวจที่ดูจาก enrollment
-- อย่างเดียวจะเงียบสนิทตอนที่ต้องการมันที่สุด — TEST 159 จึงตรวจว่า
-- การชนของ "กลุ่มตามแผน" ถูกจับได้โดยไม่ต้องมีใครลงทะเบียนเลย
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

insert into timetable_policy
  (institution_id, periods_per_day, days_per_week, lunch_period, max_consecutive)
values ('11111111-1111-1111-1111-111111111111', 8, 5, 5, 4)
on conflict (institution_id) do nothing;

-- ── TEST 159 ───────────────────────────────────────────────────────
-- การชนของครู ห้อง และกลุ่มตามแผน ต้องถูกจับได้ทั้งหมด
do $$
declare
  v_teacher integer;
  v_cohort  integer;
  v_room    integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  -- bbbb...0001 อยู่จันทร์ คาบ 3–4 ห้อง W-02 ครูคนเดียวกัน กลุ่ม 1/2
  -- เสนอวางอีกวิชาทับที่จันทร์ คาบ 4 ในห้อง W-02 → ต้องชนทั้งสามแบบ
  select count(*) filter (where kind = 'teacher'),
         count(*) filter (where kind = 'cohort'),
         count(*) filter (where kind = 'room')
    into v_teacher, v_cohort, v_room
    from timeslot_conflicts('bbbb0000-0000-0000-0000-000000000003',
           1::smallint, 4::smallint, 4::smallint,
           'bbbb0000-0000-0000-0000-00000000cc01');

  if v_teacher = 0 then
    raise exception 'TEST 159 ล้มเหลว: ครูคนเดียวถูกจัดสอนสองที่พร้อมกันได้';
  end if;
  if v_cohort = 0 then
    raise exception 'TEST 159 ล้มเหลว: นักศึกษากลุ่มเดียวกันถูกจัดเรียนสองวิชาพร้อมกันได้';
  end if;
  if v_room = 0 then
    raise exception 'TEST 159 ล้มเหลว: ห้องเดียวถูกใช้สองวิชาพร้อมกันได้';
  end if;

  raise notice 'TEST 159 ผ่าน — จับการชนได้ครบ ครู % · กลุ่ม % · ห้อง %',
    v_teacher, v_cohort, v_room;
end $$;

-- ── TEST 160 ───────────────────────────────────────────────────────
-- ประเภทห้องและนโยบายตารางสอน
do $$
declare
  v_kind   integer;
  v_policy integer;
  v_free   integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  -- 20101-2003 ต้องใช้โรงฝึกงาน จัดลงห้องบรรยาย 322 ไม่ได้
  select count(*) into v_kind
    from timeslot_conflicts('bbbb0000-0000-0000-0000-000000000001',
           3::smallint, 1::smallint, 2::smallint,
           'bbbb0000-0000-0000-0000-00000000cc03')
   where kind = 'room_kind';

  if v_kind = 0 then
    raise exception 'TEST 160 ล้มเหลว: วิชาที่ต้องใช้โรงฝึกงานถูกจัดลงห้องบรรยายได้';
  end if;

  -- คาบ 5 คือคาบพักกลางวันตามนโยบาย
  select count(*) into v_policy
    from timeslot_conflicts('bbbb0000-0000-0000-0000-000000000001',
           4::smallint, 4::smallint, 6::smallint, null)
   where kind = 'policy';

  if v_policy = 0 then
    raise exception 'TEST 160 ล้มเหลว: จัดคาบเรียนทับคาบพักกลางวันได้';
  end if;

  -- คาบที่ไม่ชนอะไรเลยต้องไม่มีปัญหาสักข้อ
  select count(*) into v_free
    from timeslot_conflicts('bbbb0000-0000-0000-0000-000000000001',
           4::smallint, 1::smallint, 2::smallint, null);

  if v_free <> 0 then
    raise exception 'TEST 160 ล้มเหลว: คาบว่างจริงกลับมีปัญหา % ข้อ', v_free;
  end if;

  raise notice 'TEST 160 ผ่าน — โรงฝึกงาน คาบพักกลางวัน และคาบว่างจริง ตรวจได้ถูกต้อง';
end $$;

-- ── TEST 161 ───────────────────────────────────────────────────────
-- คาบที่เสนอต้องไม่ชนอะไรเลย และต้องไม่แตะคาบพักกลางวัน
do $$
declare
  v_n    integer;
  v_bad  integer;
  v_late integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  select count(*) into v_n
    from suggest_timeslots('bbbb0000-0000-0000-0000-000000000001', 2::smallint, null, 20);

  if v_n = 0 then
    raise exception 'TEST 161 ล้มเหลว: ไม่มีคาบว่างให้เสนอเลย';
  end if;

  select count(*) into v_bad
    from suggest_timeslots('bbbb0000-0000-0000-0000-000000000001', 2::smallint, null, 20) s
   where exists (select 1 from timeslot_conflicts(
           'bbbb0000-0000-0000-0000-000000000001',
           s.day_of_week, s.period_from, s.period_to, null));

  if v_bad > 0 then
    raise exception 'TEST 161 ล้มเหลว: เสนอคาบที่ชน % รายการ', v_bad;
  end if;

  select count(*) into v_late
    from suggest_timeslots('bbbb0000-0000-0000-0000-000000000001', 2::smallint, null, 20)
   where period_to > 8 or day_of_week > 5;

  if v_late > 0 then
    raise exception 'TEST 161 ล้มเหลว: เสนอคาบที่เกินนโยบาย % รายการ', v_late;
  end if;

  raise notice 'TEST 161 ผ่าน — เสนอ % คาบ ไม่มีคาบไหนชนและไม่เกินนโยบาย', v_n;
end $$;

-- ── TEST 162 ───────────────────────────────────────────────────────
-- จัดอัตโนมัติ — วางได้จริง และรายงานวิชาที่วางไม่ครบแทนที่จะยัดลงไป
do $$
declare
  v_rows      integer;
  v_scheduled integer;
  v_partial   integer;
  v_conflicts integer;
  v_before    integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select count(*) into v_before from section_timeslot;

  select count(*),
         count(*) filter (where action = 'scheduled'),
         count(*) filter (where action = 'partial')
    into v_rows, v_scheduled, v_partial
    from auto_schedule_term('33333333-3333-3333-3333-333333333331');

  if v_rows = 0 then
    raise exception 'TEST 162 ล้มเหลว: ไม่รายงานห้องเรียนใดเลย';
  end if;
  if (select count(*) from section_timeslot) <= v_before then
    raise exception 'TEST 162 ล้มเหลว: ไม่ได้วางคาบเพิ่มเลย';
  end if;

  -- สิ่งที่จัดเองต้องไม่สร้างการชนใหม่ นี่คือข้อที่สำคัญที่สุดของตัวจัด
  select count(*) into v_conflicts
    from timetable_conflicts('33333333-3333-3333-3333-333333333331')
   where kind in ('teacher', 'room', 'cohort');

  raise notice 'TEST 162 ผ่าน — รายงาน % ห้องเรียน (จัดครบ % · จัดได้บางส่วน %) · การชนคงเหลือ %',
    v_rows, v_scheduled, v_partial, v_conflicts;
end $$;

-- ── TEST 163 ───────────────────────────────────────────────────────
-- ตัวจัดอัตโนมัติต้องไม่สร้างการชนใหม่
--
-- การชนที่เหลืออยู่ต้องเป็นของเดิมที่มีคนวางเองไว้ก่อน (จันทร์ คาบ 4)
-- ไม่ใช่ของที่ตัวจัดเพิ่งวางลงไป
do $$
declare
  v_pre  integer;
  v_all  integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  select count(*) into v_all
    from timetable_conflicts('33333333-3333-3333-3333-333333333331')
   where kind in ('teacher', 'room', 'cohort');

  -- การชนของเดิม: bbbb...0001 (จันทร์ 3–4) กับ bbbb...0002 (จันทร์ 4–5)
  select count(*) into v_pre
    from timetable_conflicts('33333333-3333-3333-3333-333333333331')
   where kind in ('teacher', 'room', 'cohort')
     and day_of_week = 1 and period_from between 3 and 4;

  if v_pre = 0 then
    raise exception 'TEST 163 ล้มเหลว: ตรวจไม่เจอการชนของเดิมที่รู้ว่ามีอยู่';
  end if;
  if v_all <> v_pre then
    raise exception 'TEST 163 ล้มเหลว: ตัวจัดอัตโนมัติสร้างการชนใหม่ % รายการ', v_all - v_pre;
  end if;

  raise notice 'TEST 163 ผ่าน — เจอการชนของเดิม % รายการ และตัวจัดไม่สร้างการชนใหม่เลย', v_pre;
end $$;

-- ── TEST 164 ───────────────────────────────────────────────────────
-- วิทยาลัยอื่นต้องไม่เห็นห้องเรียนและนโยบายตารางสอนของเรา
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_r integer; v_p integer;
begin
  select count(*) into v_r from room;
  select count(*) into v_p from timetable_policy;
  if v_r + v_p <> 0 then
    raise exception 'TEST 164 ล้มเหลว: วิทยาลัยอื่นเห็นห้อง % แถว นโยบาย % แถว', v_r, v_p;
  end if;
  raise notice 'TEST 164 ผ่าน — วิทยาลัยอื่นไม่เห็นห้องเรียนหรือนโยบายตารางสอนเลย';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบห้องเรียนและตารางสอนครบทุกข้อ ════'; end $$;

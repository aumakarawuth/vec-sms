-- ═══════════════════════════════════════════════════════════════════
-- 0030_teacher_availability.sql
-- ทดสอบข้อจำกัดเวลาสอนรายบุคคล
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. ช่วงที่ครู "สอนไม่ได้" หายไปจากรายการคาบที่เสนอทั้งหมด
-- 2. ช่วงที่ครู "ขอเลี่ยง" ยังเสนอได้ แต่ไปอยู่ท้ายรายการ พร้อมเหตุผล
-- 3. ครูไม่ได้กรอกอะไร = ว่างตลอด (ไม่ใช่ไม่ว่างเลย ซึ่งจะทำให้จัดตาราง
--    ไม่ได้ทั้งวิทยาลัยในวันแรกที่เปิดใช้)
-- 4. ครูแก้ข้อจำกัดของตัวเองไม่ได้ — ถ้าทำได้ ตารางสอนจะกลายเป็นเรื่อง
--    ที่ต่อรองกันเองและคนกรอกก่อนได้คาบดีที่สุดเสมอ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ต้องเลือกกลุ่มเรียนที่ **ยังมีคาบว่าง** ไม่ใช่กลุ่มแรกที่เจอ
--
-- กลุ่มที่จัดตารางเต็มแล้วจะไม่มีคาบให้เสนอเลยตั้งแต่ต้น (timeslot_conflicts
-- คืนชนิด self ให้ทุกช่วง) แล้วเทสต์จะล้มด้วยเหตุผลที่ไม่เกี่ยวกับข้อจำกัด
-- ของครูสักนิด — ซึ่งเป็นสิ่งที่เสียเวลาหาสาเหตุนานที่สุด
select cs.id as sec_id, cs.institution_id as inst_id,
       st.id as staff_id, st.person_id as teacher_person
  from class_section cs
  join staff st on st.id = cs.teacher_id
 where (select count(*) from suggest_timeslots(cs.id, 2::smallint, null, 20)) > 4
 order by cs.id
 limit 1 \gset

select set_config('test.sec',   :'sec_id',   false) as a,
       set_config('test.staff', :'staff_id', false) as b \gset ctx_

-- ── TEST 210 ───────────────────────────────────────────────────────
-- ไม่กรอกอะไร = ว่างตลอด · กรอกว่าไม่ว่าง = คาบนั้นหายไปจากข้อเสนอ
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec    uuid := current_setting('test.sec')::uuid;
  v_staff  uuid := current_setting('test.staff')::uuid;
  v_inst   uuid;
  v_before integer;
  v_after  integer;
  v_mon    integer;
begin
  select institution_id into v_inst from class_section where id = v_sec;

  select count(*) into v_before from suggest_timeslots(v_sec, 2::smallint, null, 100);
  if v_before = 0 then
    raise exception 'TEST 210 ล้มเหลว: ครูที่ไม่ได้กรอกข้อจำกัดควรว่างตลอด แต่เสนอคาบไม่ได้เลย';
  end if;

  -- ปิดเช้าวันจันทร์ (คาบ 1-4)
  insert into teacher_availability
    (institution_id, staff_id, day_of_week, period_from, period_to, kind, reason)
  values (v_inst, v_staff, 1, 1, 4, 'unavailable', 'สอนอีกวิทยาเขต');

  select count(*) into v_after from suggest_timeslots(v_sec, 2::smallint, null, 100);
  select count(*) into v_mon   from suggest_timeslots(v_sec, 2::smallint, null, 100)
   where day_of_week = 1 and period_from <= 4;

  if v_mon <> 0 then
    raise exception 'TEST 210 ล้มเหลว: ยังเสนอคาบเช้าวันจันทร์ % คาบ ทั้งที่ครูสอนไม่ได้', v_mon;
  end if;
  if v_after >= v_before then
    raise exception 'TEST 210 ล้มเหลว: จำนวนคาบที่เสนอไม่ลดลง (% → %)', v_before, v_after;
  end if;

  raise notice 'TEST 210 ผ่าน — ปิดเช้าวันจันทร์แล้วคาบที่เสนอลดจาก % เหลือ % และไม่มีคาบต้องห้ามเลย',
    v_before, v_after;
end $$;
rollback;

-- ── TEST 211 ───────────────────────────────────────────────────────
-- "ขอเลี่ยง" ต่างจาก "ห้าม" — ยังเสนอได้แต่ไปท้ายรายการพร้อมเหตุผล
--
-- ถ้าปนกันเป็นข้อห้ามทั้งหมด ตารางจะจัดไม่ลงเมื่อมีคำขอมาก แล้วคนจัด
-- จะเริ่มลบคำขอทิ้งเพื่อให้จัดได้ — ข้อมูลนี้จะเชื่อถือไม่ได้ทั้งตาราง
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_sec   uuid := current_setting('test.sec')::uuid;
  v_staff uuid := current_setting('test.staff')::uuid;
  v_inst  uuid;
  v_first record;
  v_avoid integer;
  v_note  text;
begin
  select institution_id into v_inst from class_section where id = v_sec;

  insert into teacher_availability
    (institution_id, staff_id, day_of_week, period_from, period_to, kind, reason)
  values (v_inst, v_staff, 1, 1, 4, 'prefer_not', 'บ้านไกล ขอไม่สอนคาบแรก');

  -- ต้องยังเสนอคาบเช้าวันจันทร์อยู่ ไม่ใช่ตัดทิ้ง
  select count(*) into v_avoid from suggest_timeslots(v_sec, 2::smallint, null, 100)
   where day_of_week = 1 and period_from <= 4;
  if v_avoid = 0 then
    raise exception 'TEST 211 ล้มเหลว: คำขอเลี่ยงถูกตัดทิ้งเหมือนข้อห้าม '
      '(ตารางจะจัดไม่ลงเมื่อมีคำขอมาก)';
  end if;

  -- และต้องติดธง avoids พร้อมเหตุผลให้คนจัดเห็น
  select note into v_note from suggest_timeslots(v_sec, 2::smallint, null, 100)
   where day_of_week = 1 and period_from <= 4 and avoids limit 1;
  if v_note is null then
    raise exception 'TEST 211 ล้มเหลว: ไม่ได้บอกเหตุผลที่ครูขอเลี่ยง '
      '(คนจัดจะเลือกคาบนั้นโดยไม่รู้ว่ากำลังฝืนคำขอของใคร)';
  end if;

  -- คาบแรกในรายการต้องไม่ใช่คาบที่ครูขอเลี่ยง
  select * into v_first from suggest_timeslots(v_sec, 2::smallint, null, 100) limit 1;
  if v_first.avoids then
    raise exception 'TEST 211 ล้มเหลว: คาบที่ครูขอเลี่ยงถูกเสนอเป็นตัวเลือกแรก';
  end if;

  raise notice 'TEST 211 ผ่าน — คำขอเลี่ยงยังเสนอได้ (%) แต่ไปท้ายรายการ', v_note;
end $$;
rollback;

-- ── TEST 212 ───────────────────────────────────────────────────────
-- ครูอ่านข้อจำกัดของตัวเองได้ แต่แก้และลบไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_staff uuid := current_setting('test.staff')::uuid;
  v_inst  uuid;
begin
  select institution_id into v_inst from staff where id = v_staff;
  insert into teacher_availability
    (institution_id, staff_id, day_of_week, period_from, period_to, kind, reason)
  values (v_inst, v_staff, 3, 1, 2, 'unavailable', 'ประชุมประจำสัปดาห์');
end $$;

-- ใช้ค่าที่หยิบไว้ตั้งแต่ต้นไฟล์ ห้ามค้นใหม่หลัง set local role app_runtime
-- เพราะตอนนั้น RLS ยังไม่มีบริบทให้กรอง จะได้ NULL แล้ว set_config เงียบ ๆ
-- จนบริบทไม่ถูกตั้ง — อาการที่ออกมาคือ "ครูอ่านของตัวเองไม่ได้"
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'teacher_person', true) as b,
       set_config('app.role',           'teacher',         true) as c \gset ctx_

do $$
declare
  v_staff  uuid := current_setting('test.staff')::uuid;
  v_seen   integer;
  v_n      integer;
  v_wrote  text[] := '{}';
begin
  -- ต้องอ่านของตัวเองได้ — ครูต้องเห็นว่าที่แจ้งไปถูกบันทึกแล้ว
  select count(*) into v_seen from teacher_availability where staff_id = v_staff;
  if v_seen = 0 then
    raise exception 'TEST 212 ล้มเหลว: ครูดูข้อจำกัดของตัวเองไม่ได้';
  end if;

  begin
    update teacher_availability set kind = 'prefer_not' where staff_id = v_staff;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'แก้'); end if;
  exception when insufficient_privilege then null; end;

  begin
    delete from teacher_availability where staff_id = v_staff;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'ลบ'); end if;
  exception when insufficient_privilege then null; end;

  begin
    insert into teacher_availability
      (institution_id, staff_id, day_of_week, period_from, period_to, kind)
    values (current_setting('app.institution_id')::uuid, v_staff, 5, 1, 10, 'unavailable');
    v_wrote := array_append(v_wrote, 'เพิ่ม');
  exception when others then null; end;

  if array_length(v_wrote, 1) > 0 then
    raise exception 'TEST 212 ล้มเหลว: ครูจัดการข้อจำกัดของตัวเองได้ (%) '
      '(ตารางสอนจะกลายเป็นเรื่องที่ต่อรองกันเอง คนกรอกก่อนได้คาบดีที่สุด)',
      array_to_string(v_wrote, ' · ');
  end if;

  raise notice 'TEST 212 ผ่าน — ครูอ่านข้อจำกัดของตัวเองได้ (% รายการ) แต่แก้ ลบ และเพิ่มเองไม่ได้', v_seen;
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบข้อจำกัดเวลาสอนครบทุกข้อ ════'; end $$;

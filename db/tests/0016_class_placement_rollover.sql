-- ═══════════════════════════════════════════════════════════════════
-- 0016_class_placement_rollover.sql
-- ทดสอบชั้นปี/ห้องเรียน และการเลื่อนชั้นปีการศึกษา
--
-- ─── ทำไมชุดนี้เน้นคนที่ "ไม่ควรถูกเลื่อน" ───
-- การเลื่อนชั้นที่ทำงานถูกต้องกับคนปกติเป็นเรื่องง่าย ความเสียหายจริงมาจาก
-- คนที่ไม่ควรถูกเลื่อนแต่ถูกเลื่อนไปด้วย — คนที่จบไปแล้ว คนที่ลาออกไปแล้ว
-- และคนที่เรียนเกินเวลาปกติของหลักสูตร
--
-- ทั้งสามกลุ่มนี้ถ้าถูกเลื่อนชั้นเงียบ ๆ จะไปโผล่ในรายชื่อนักศึกษาปีถัดไป
-- ในรายงานส่งหน่วยงานรัฐ และในการคิดค่าเทอม โดยไม่มีอาการอะไรให้เห็นเลย
-- จนกว่าจะมีคนทักว่า "คนนี้จบไปตั้งแต่ปีที่แล้วไม่ใช่เหรอ"
--
-- ─── และเน้นว่ากดซ้ำแล้วต้องไม่พัง ───
-- งานเลื่อนชั้นทำปีละครั้ง คนที่กดมักไม่แน่ใจว่ากดไปแล้วหรือยัง การกดซ้ำ
-- จึงต้องไม่สร้างข้อมูลซ้ำหรือเขียนทับของเดิม
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมข้อมูล ───────────────────────────────────────────────────
-- ปีการศึกษาถัดไป (การเลื่อนชั้นไม่สร้างให้เอง โดยตั้งใจ)
insert into academic_year (id, institution_id, year_be, starts_on, ends_on)
values ('22222222-2222-2222-2222-222222222223',
        '11111111-1111-1111-1111-111111111111', 2570, '2027-05-10', '2028-03-31')
on conflict (id) do nothing;

-- ชั้นปีของปีปัจจุบัน — ให้ทุกคนที่ยัง active อยู่ชั้นปี 1
insert into student_class_placement
  (institution_id, student_id, academic_year_id, study_year, group_code)
select s.institution_id, s.id, '22222222-2222-2222-2222-222222222222', 1, 'ปวช.1/1'
  from student s
 where s.institution_id = '11111111-1111-1111-1111-111111111111'
on conflict (student_id, academic_year_id) do nothing;

-- คนที่เรียนเกินเวลาปกติ — ดันไปอยู่ชั้นปีสุดท้ายของหลักสูตรไว้ก่อน
update student_class_placement
   set study_year = 3
 where student_id = 'aaaa0000-0000-0000-0000-000000000014'
   and academic_year_id = '22222222-2222-2222-2222-222222222222';

-- คนที่ลาออกไปแล้ว
update student set status = 'withdrawn'
 where id = 'aaaa0000-0000-0000-0000-000000000013';

-- ── TEST 143 ───────────────────────────────────────────────────────
-- ชั้นปีต้องผูกกับปีการศึกษา ไม่ใช่เขียนทับค่าเดิม
do $$
declare v_dup integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  begin
    insert into student_class_placement
      (institution_id, student_id, academic_year_id, study_year)
    values ('11111111-1111-1111-1111-111111111111',
            'aaaa0000-0000-0000-0000-000000000011',
            '22222222-2222-2222-2222-222222222222', 2);
    raise exception 'TEST 143 ล้มเหลว: ใส่ชั้นปีซ้ำในปีการศึกษาเดียวกันได้';
  exception when unique_violation then null;
  end;

  select count(*) into v_dup
    from student_class_placement
   where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  if v_dup <> 1 then
    raise exception 'TEST 143 ล้มเหลว: ควรมีชั้นปีเดียวต่อปีการศึกษา มี % แถว', v_dup;
  end if;

  raise notice 'TEST 143 ผ่าน — ชั้นปีผูกกับปีการศึกษา หนึ่งคนหนึ่งปีหนึ่งชั้น';
end $$;

-- ── TEST 144 ───────────────────────────────────────────────────────
-- ยังไม่ได้สร้างปีการศึกษาปลายทางต้องเลื่อนไม่ได้ พร้อมบอกให้ไปสร้างก่อน
do $$
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  begin
    perform rollover_students(2569::smallint, 2599::smallint);
    raise exception 'TEST 144 ล้มเหลว: เลื่อนไปยังปีที่ยังไม่มีได้';
  exception when others then
    if sqlerrm not like '%ยังไม่ได้สร้างปีการศึกษา%' then
      raise exception 'TEST 144 ล้มเหลว: ข้อความไม่ได้บอกว่าต้องสร้างปีการศึกษาก่อน (%)', sqlerrm;
    end if;
  end;
  raise notice 'TEST 144 ผ่าน — ไม่สร้างปฏิทินให้เองและบอกชัดว่าต้องไปสร้างก่อน';
end $$;

-- ── TEST 145 ───────────────────────────────────────────────────────
-- เลื่อนชั้นจริง — คนที่ไม่ควรถูกเลื่อนต้องไม่ถูกเลื่อน
do $$
declare
  v_promoted  integer;
  v_graduated integer;
  v_inactive  integer;
  v_exceeded  integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select count(*) filter (where action = 'promoted'),
         count(*) filter (where action = 'graduated'),
         count(*) filter (where action = 'inactive'),
         count(*) filter (where action = 'exceeded')
    into v_promoted, v_graduated, v_inactive, v_exceeded
    from rollover_students(2569::smallint, 2570::smallint);

  if v_promoted = 0 then
    raise exception 'TEST 145 ล้มเหลว: ไม่มีใครถูกเลื่อนชั้นเลย';
  end if;
  if v_graduated = 0 then
    raise exception 'TEST 145 ล้มเหลว: คนที่จบแล้วควรถูกข้าม แต่ไม่มีใครถูกข้ามด้วยเหตุนี้';
  end if;
  if v_inactive = 0 then
    raise exception 'TEST 145 ล้มเหลว: คนที่ลาออกแล้วควรถูกข้าม แต่ไม่มีใครถูกข้ามด้วยเหตุนี้';
  end if;

  -- คนที่จบแล้วต้องไม่มีชั้นปีในปีถัดไป
  if exists (select 1 from student_class_placement
              where student_id = 'aaaa0000-0000-0000-0000-000000000011'
                and academic_year_id = '22222222-2222-2222-2222-222222222223') then
    raise exception 'TEST 145 ล้มเหลว: คนที่สำเร็จการศึกษาแล้วถูกเลื่อนชั้นไปปีถัดไป';
  end if;

  raise notice 'TEST 145 ผ่าน — เลื่อน % คน · จบแล้วข้าม % · ไม่ active ข้าม % · เกินเวลาหลักสูตร %',
    v_promoted, v_graduated, v_inactive, v_exceeded;
end $$;

-- ── TEST 146 ───────────────────────────────────────────────────────
-- กดซ้ำต้องไม่สร้างข้อมูลซ้ำและไม่เขียนทับของเดิม
do $$
declare
  v_before  integer;
  v_after   integer;
  v_skipped integer;
  v_year    smallint;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select count(*) into v_before from student_class_placement
   where academic_year_id = '22222222-2222-2222-2222-222222222223';

  select count(*) filter (where action = 'skipped') into v_skipped
    from rollover_students(2569::smallint, 2570::smallint);

  select count(*) into v_after from student_class_placement
   where academic_year_id = '22222222-2222-2222-2222-222222222223';

  if v_after <> v_before then
    raise exception 'TEST 146 ล้มเหลว: กดซ้ำแล้วเกิดแถวเพิ่ม % → %', v_before, v_after;
  end if;
  if v_skipped = 0 then
    raise exception 'TEST 146 ล้มเหลว: กดซ้ำแล้วไม่มีใครถูกรายงานว่าข้าม';
  end if;

  -- ชั้นปีเดิมของปีก่อนต้องยังอยู่ครบ ไม่ถูกเขียนทับ
  select study_year into v_year from student_class_placement
   where student_id = 'aaaa0000-0000-0000-0000-000000000012'
     and academic_year_id = '22222222-2222-2222-2222-222222222222';
  if v_year <> 1 then
    raise exception 'TEST 146 ล้มเหลว: ชั้นปีของปีการศึกษาเดิมถูกเขียนทับเป็น %', v_year;
  end if;

  raise notice 'TEST 146 ผ่าน — กดซ้ำข้าม % คน ไม่เกิดแถวเพิ่ม และประวัติปีเก่ายังอยู่', v_skipped;
end $$;

-- ── TEST 147 ───────────────────────────────────────────────────────
-- คัดลอกรายการชำระเงินตามชั้นปี และต้องยังไม่เปิดใช้
do $$
declare
  v_lines  integer;
  v_active integer;
  v_again  integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  v_lines := rollover_fee_schedules(2569::smallint, 2570::smallint);

  select count(*) into v_active
    from fee_schedule
   where academic_year_id = '22222222-2222-2222-2222-222222222223' and active;

  if v_active > 0 then
    raise exception 'TEST 147 ล้มเหลว: ค่าเทอมปีใหม่เปิดใช้ทันทีโดยที่งานการเงินยังไม่ได้ตรวจตัวเลข';
  end if;

  -- กดซ้ำต้องไม่คัดลอกซ้อน มิฉะนั้นค่าเทอมจะกลายเป็นสองเท่า
  v_again := rollover_fee_schedules(2569::smallint, 2570::smallint);
  if v_again <> 0 then
    raise exception 'TEST 147 ล้มเหลว: กดซ้ำแล้วคัดลอกเพิ่มอีก % บรรทัด ค่าเทอมจะซ้อนกัน', v_again;
  end if;

  raise notice 'TEST 147 ผ่าน — คัดลอก % บรรทัด ยังไม่เปิดใช้ และกดซ้ำไม่ซ้อน', v_lines;
end $$;

-- ── TEST 148 ───────────────────────────────────────────────────────
-- วิทยาลัยอื่นต้องไม่เห็นชั้นปีของเรา
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_p integer; v_l integer;
begin
  select count(*) into v_p from student_class_placement;
  select count(*) into v_l from rollover_log;
  if v_p + v_l <> 0 then
    raise exception 'TEST 148 ล้มเหลว: วิทยาลัยอื่นเห็นชั้นปี % แถว บันทึกการเลื่อนชั้น % แถว', v_p, v_l;
  end if;
  raise notice 'TEST 148 ผ่าน — วิทยาลัยอื่นไม่เห็นชั้นปีหรือประวัติการเลื่อนชั้นเลย';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบชั้นปีและการเลื่อนชั้นปีการศึกษาครบทุกข้อ ════'; end $$;

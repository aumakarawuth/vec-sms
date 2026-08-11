-- ═══════════════════════════════════════════════════════════════════
-- 0036_teacher_submit_grades.sql
-- ทดสอบว่าครูส่งเกรดของกลุ่มเรียนตัวเองได้จริง (0052)
--
-- ─── ทำไมต้องมีเทสต์นี้ ───
-- 0049 เปิด `grade_submission` ให้ครูเขียนได้ เพราะ `submit_section_grades()`
-- ไม่ใช่ security definer แต่ `enrollment_result_staff_insert` จาก 0041
-- ยังเป็น restrictive ที่ยอมเฉพาะบทบาทระดับวิทยาลัย ผลคือ **ครูส่งเกรด
-- ของตัวเองไม่ได้เลยสักครั้ง** ทั้งที่ขั้นแรกของสายอนุมัติชื่อ teacher_submitted
--
-- ไม่มีใครเห็นเพราะเทสต์ทุกชุด `insert into grade_submission` ตรงด้วยสิทธิ์
-- เจ้าของฐานข้อมูลในขั้นเตรียมข้อมูล แล้วทดสอบขั้นถัด ๆ ไป — ไม่เคยมีเทสต์
-- ไหนกดปุ่มแรกของเส้นทางเลย
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. ครูผู้สอนส่งเกรดของกลุ่มเรียนตัวเองได้
-- 2. ครูคนอื่นส่งเกรดแทนไม่ได้
-- 3. เมื่อรอบล็อกแล้ว ครูส่งทับไม่ได้ — ต้องผ่าน grade_change_request เท่านั้น
-- 4. บทบาทระดับวิทยาลัยยังทำได้เหมือนเดิม (การเปิดต้องไม่ปิดของเดิม)
--
-- หมายเหตุ: ข้อที่ต้อง "ถูกปฏิเสธ" ใช้ธงบูลีนกับ sqlerrm ที่จับไว้
-- ไม่ raise ในบล็อกที่ตัวเองดักอยู่ (กับดักที่เขียนไว้ในหัวไฟล์ 0024)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- กลุ่มเรียนที่มีครูผู้สอน มีผู้ลงทะเบียน และ**ยังไม่ได้ส่งเกรด**
-- seed มีกลุ่มที่ล็อกไว้แล้วสองกลุ่มสำหรับทดสอบขั้นอื่น ถ้าหยิบกลุ่มนั้นมา
-- เทสต์นี้จะล้มด้วยเหตุผลที่ไม่เกี่ยวกับสิ่งที่ตั้งใจพิสูจน์
select cs.id as sec_id, cs.institution_id as inst_id,
       st.person_id as teacher_person
  from class_section cs
  join staff st     on st.id = cs.teacher_id
  join enrollment e on e.class_section_id = cs.id and e.status = 'enrolled'
  left join grade_submission gs on gs.class_section_id = cs.id
 where coalesce(gs.stage::text, 'draft') in ('draft', 'returned')
 group by cs.id, st.person_id
 order by cs.id
 limit 1 \gset

select p.id as registrar_person
  from person p
  join staff s       on s.person_id = p.id
  join staff_role sr on sr.staff_id = s.id
 where sr.role in ('registrar', 'academic', 'director', 'admin')
   and s.institution_id = :'inst_id'
 order by p.id
 limit 1 \gset

select set_config('test.sec',       :'sec_id',          false) as a,
       set_config('test.inst',      :'inst_id',         false) as b,
       set_config('test.teacher',   :'teacher_person',  false) as c,
       set_config('test.registrar', :'registrar_person', false) as d \gset

/*
 * ปิดคาบที่ยังค้างให้หมดก่อน — `submit_section_grades()` ปฏิเสธถ้ายังมีคาบ
 * ที่ยังไม่ได้สอน เพราะเวลาเรียนยังไม่ใช่ตัวเลขสุดท้าย ซึ่งเป็นกฎที่ถูกต้อง
 * แต่ไม่ใช่สิ่งที่ไฟล์นี้ตั้งใจพิสูจน์ จึงจัดสถานะให้พร้อมด้วยสิทธิ์เจ้าของ
 * ฐานข้อมูลก่อนเริ่ม
 */
update class_meeting
   set status = 'held'
 where class_section_id = current_setting('test.sec')::uuid
   and status <> 'held';

-- ── TEST 228 ───────────────────────────────────────────────────────
-- ครูผู้สอนส่งเกรดของกลุ่มเรียนตัวเองได้
do $$
declare
  v_written integer;
  v_stage   text;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.teacher'), true);
  perform set_config('app.role',           'teacher', true);

  select results_written into v_written
    from submit_section_grades(current_setting('test.sec')::uuid);

  if coalesce(v_written, 0) = 0 then
    raise exception 'TEST 228 ล้มเหลว: ครูส่งเกรดแล้วไม่มีผลถูกบันทึกเลยสักแถว';
  end if;

  select stage::text into v_stage
    from grade_submission
   where class_section_id = current_setting('test.sec')::uuid;

  if v_stage <> 'teacher_submitted' then
    raise exception 'TEST 228 ล้มเหลว: ขั้นควรเป็น teacher_submitted ได้ %', v_stage;
  end if;

  raise notice 'TEST 228 ผ่าน — ครูส่งเกรดของตัวเองได้ % แถว ขั้นเป็น %', v_written, v_stage;
end $$;

reset role;

-- ── TEST 229 ───────────────────────────────────────────────────────
-- คนที่ไม่ใช่ครูของกลุ่มนี้ส่งเกรดแทนไม่ได้ และรอบที่ล็อกแล้วส่งทับไม่ได้
do $$
declare
  v_blocked_other boolean := false;
  v_blocked_lock  boolean := false;
  v_msg_other     text;
  v_msg_lock      text;
begin
  /*
   * ใช้คนของงานทะเบียนสวมบทบาท teacher แทนการหาครูคนที่สอง — พิสูจน์ได้
   * ตรงกว่าด้วยซ้ำว่านโยบายดูที่ **ตัวบุคคล** (`st.person_id = current_actor_id()`)
   * ไม่ใช่ดูแค่ว่าบทบาทเป็นครูหรือเปล่า
   */
  begin
    set local role app_runtime;
    perform set_config('app.institution_id', current_setting('test.inst'), true);
    perform set_config('app.actor_id',       current_setting('test.registrar'), true);
    perform set_config('app.role',           'teacher', true);

    perform submit_section_grades(current_setting('test.sec')::uuid);
  exception when others then
    v_blocked_other := true;
    v_msg_other := sqlerrm;
  end;

  reset role;

  if not v_blocked_other then
    raise exception 'TEST 229 ล้มเหลว: คนที่ไม่ได้สอนกลุ่มนี้ส่งเกรดแทนได้ '
                    'ทั้งที่สวมบทบาท teacher — นโยบายดูแค่บทบาท ไม่ได้ดูตัวบุคคล';
  end if;

  -- ล็อกรอบด้วยสิทธิ์เจ้าของฐานข้อมูล แล้วให้ครูเจ้าของกลุ่มลองส่งทับ
  update grade_submission
     set stage = 'locked', locked_at = now()
   where class_section_id = current_setting('test.sec')::uuid;

  begin
    set local role app_runtime;
    perform set_config('app.institution_id', current_setting('test.inst'), true);
    perform set_config('app.actor_id',       current_setting('test.teacher'), true);
    perform set_config('app.role',           'teacher', true);

    perform submit_section_grades(current_setting('test.sec')::uuid);
  exception when others then
    v_blocked_lock := true;
    v_msg_lock := sqlerrm;
  end;

  reset role;

  if not v_blocked_lock then
    raise exception 'TEST 229 ล้มเหลว: รอบที่ล็อกแล้วครูยังส่งทับได้ '
                    '— การแก้เกรดหลังล็อกต้องผ่าน grade_change_request เท่านั้น';
  end if;

  raise notice 'TEST 229 ผ่าน — คนที่ไม่ได้สอนถูกปฏิเสธ (%) · รอบที่ล็อกแล้วถูกปฏิเสธ (%)',
    left(v_msg_other, 55), left(v_msg_lock, 55);
end $$;

reset role;

-- ── TEST 230 ───────────────────────────────────────────────────────
-- การเปิดให้ครูต้องไม่ปิดของเดิม — บทบาทระดับวิทยาลัยยังบันทึกผลได้
--
-- ทั้งบล็อกอยู่ในทรานแซกชันที่ rollback ทิ้ง เพราะ `enrollment_result`
-- ลบไม่ได้ตามหลักข้อ 4 — เก็บกวาดด้วย delete จึงทำไม่ได้ และการปล่อยแถว
-- ทดสอบค้างไว้จะไปโผล่ในผลการเรียนของนักศึกษาจริงในฐานตัวอย่าง
begin;

do $$
declare
  v_enr uuid;
  v_sym uuid;
  v_ok  boolean := true;
begin
  -- ปลดล็อกกลับเพื่อไม่ให้เทสต์นี้ไปติดกฎของ TEST 229
  update grade_submission
     set stage = 'draft', locked_at = null
   where class_section_id = current_setting('test.sec')::uuid;

  /*
   * ต้องเป็นการลงทะเบียนที่**ยังไม่มีผลปัจจุบัน** — `enrollment_result_current`
   * เป็น unique ที่ยอมให้มีผลที่ยังไม่ถูกแทนที่ได้แถวเดียวต่อการลงทะเบียนหนึ่งรายการ
   * (หลักข้อ 4: เขียนอย่างเดียว ต้องออก revision ใหม่ที่ชี้กลับแถวเดิม)
   * TEST 228 เพิ่งสร้างผลให้ทั้งกลุ่มไปแล้ว จึงต้องหาจากกลุ่มอื่น
   */
  select e.id into v_enr
    from enrollment e
    join student s on s.id = e.student_id
    left join enrollment_result er
      on er.enrollment_id = e.id and er.superseded_by is null
   where s.institution_id = current_setting('test.inst')::uuid
     and e.status = 'enrolled'
     and er.id is null
   order by e.id limit 1;

  if v_enr is null then
    raise exception 'TEST 230 ล้มเหลว: หาการลงทะเบียนที่ยังไม่มีผลไม่เจอ เทสต์นี้จึงพิสูจน์อะไรไม่ได้';
  end if;

  select gs.id into v_sym
    from grade_symbol gs
    join grade_scheme sc on sc.id = gs.grade_scheme_id
   where sc.institution_id = current_setting('test.inst')::uuid
     and gs.symbol = '4.0'
   limit 1;

  begin
    set local role app_runtime;
    perform set_config('app.institution_id', current_setting('test.inst'), true);
    perform set_config('app.actor_id',       current_setting('test.registrar'), true);
    perform set_config('app.role',           'registrar', true);

    insert into enrollment_result
      (enrollment_id, revision, raw_score, attendance_pct, grade_symbol_id,
       grade_point, credits_earned, computed_by)
    values (v_enr, 900, 88.0, 95.0, v_sym, 4.0, 2.0, current_setting('test.registrar')::uuid);
  exception when others then
    v_ok := false;
    raise notice 'TEST 230 — งานทะเบียนถูกปฏิเสธ: %', sqlerrm;
  end;

  reset role;

  if not v_ok then
    raise exception 'TEST 230 ล้มเหลว: 0052 ปิดทางของบทบาทระดับวิทยาลัยไปด้วย';
  end if;

  raise notice 'TEST 230 ผ่าน — บทบาทระดับวิทยาลัยยังบันทึกผลได้ตามเดิม';
end $$;

rollback;

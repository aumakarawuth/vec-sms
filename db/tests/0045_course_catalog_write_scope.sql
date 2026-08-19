-- ═══════════════════════════════════════════════════════════════════
-- 0045_course_catalog_write_scope.sql
-- ทดสอบว่าคลังรายวิชาเขียนได้เฉพาะฝ่ายวิชาการ (0065)
--
-- ─── ทำไมต้องยิง SQL ตรง ไม่ใช่ยิงผ่าน API ───
-- ก่อน 0065 ไม่มีเส้นทาง API ไหนแตะตาราง `course` เลยสักตัว การอ่านโค้ด
-- ฝั่ง API จึงให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้ามกับความจริง —
-- ตารางที่ไม่มี API ไม่ได้แปลว่าปิด แปลว่ายังไม่มีใครดู (บทเรียนข้อ 16)
--
-- ─── ต้อง set local role app_runtime เสมอ ───
-- run.sh ต่อด้วย postgres ซึ่งข้าม RLS ทุกกรณีแม้ตารางตั้ง force ไว้
-- เทสต์รอบแรกของไฟล์นี้ลืมสลับบทบาทแล้วรายงานว่า "นักศึกษาแก้หน่วยกิตได้"
-- ทั้งที่นโยบายทำงานถูกต้อง — ตัวเทสต์เองเดินผิดทางเสียก่อน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── หาเป้าหมายก่อนสลับบทบาท (ยังเป็น superuser จึงเห็นทุกแถว) ────────
select c.id             as course_id,
       c.code           as course_code,
       c.institution_id as inst_id,
       p.id             as owner_person
  from course c
  join student s on s.institution_id = c.institution_id
  join person p  on p.id = s.person_id
 order by c.code
 limit 1 \gset

-- ═══ นักศึกษาแตะคลังรายวิชาไม่ได้เลยสักทาง ═══
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',      true) as a,
       set_config('app.actor_id',       :'owner_person', true) as b,
       set_config('app.role',           'student',       true) as c,
       set_config('test.course_id',     :'course_id',    true) as d,
       set_config('test.course_code',   :'course_code',  true) as e \gset ctx_

do $$
declare n integer; v_code text := current_setting('test.course_code');
begin
  -- ── TEST 274 แก้หน่วยกิตไม่ได้ ─────────────────────────────────
  --
  -- หน่วยกิตคือตัวตั้งของทั้งการตรวจจบและ GPA ถ้าแก้ได้ คนที่รู้วิธีจะ
  -- เปลี่ยนเกณฑ์จบของตัวเองโดยไม่ต้องแตะผลการเรียนสักแถว
  update course set credits = 99 where id = current_setting('test.course_id')::uuid;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'TEST 274 ล้มเหลว: นักศึกษาแก้หน่วยกิตของรายวิชา % ได้ % แถว', v_code, n;
  end if;

  -- ── TEST 275 สร้างรายวิชาใหม่ไม่ได้ ────────────────────────────
  begin
    insert into course (institution_id, edition_be, code, name_th, credits)
    values (current_setting('app.institution_id')::uuid, 2567,
            'TEST-275', 'รายวิชาที่ไม่ควรถูกสร้าง', 9);
    raise exception 'TEST 275 ล้มเหลว: นักศึกษาสร้างรายวิชาเองได้';
  exception
    when insufficient_privilege then null;   -- ถูกปฏิเสธตามที่ควรเป็น
  end;

  -- ── TEST 276 ลบรายวิชาออกจากหลักสูตรไม่ได้ ─────────────────────
  --
  -- ข้อนี้คือช่องที่ `academic_write_only` ของ 0017 เปิดค้างไว้ — มันเขียน
  -- `for all using (true) with check (...)` ซึ่ง `delete` ตรวจด้วย `using`
  -- ไม่ใช่ `with check` ก่อน 0065 นักศึกษาลบได้ทั้งตาราง (ยิงจริงแล้ว 12/12)
  delete from curriculum_course;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'TEST 276 ล้มเหลว: นักศึกษาลบรายวิชาออกจากหลักสูตรได้ % แถว', n;
  end if;

  -- ── TEST 277 แต่ยัง **อ่าน** โครงสร้างหลักสูตรได้ตามปกติ ────────
  --
  -- ข้อนี้สำคัญพอ ๆ กับสามข้อบน — นโยบาย restrictive แบบ `for all` ที่
  -- เขียนเงื่อนไขบทบาทลงใน `using` จะกิน select ไปด้วยโดยไม่มีอะไรฟ้อง
  -- แล้วนักศึกษาจะเปิดหน้า "หลักสูตรของฉัน" มาเห็นหน้าว่าง
  select count(*) into n from course;
  if n = 0 then
    raise exception 'TEST 277 ล้มเหลว: นักศึกษาอ่านรายวิชาไม่ได้เลย — ปิดเกินไป';
  end if;

  raise notice 'TEST 274 ผ่าน — นักศึกษาแก้หน่วยกิตของรายวิชาไม่ได้';
  raise notice 'TEST 275 ผ่าน — นักศึกษาสร้างรายวิชาเองไม่ได้';
  raise notice 'TEST 276 ผ่าน — นักศึกษาลบรายวิชาออกจากหลักสูตรไม่ได้';
  raise notice 'TEST 277 ผ่าน — แต่ยังอ่านคลังรายวิชาได้ % รายวิชา', n;
end $$;
rollback;

-- ═══ ฝ่ายวิชาการยังทำงานได้ตามปกติ ═══
--
-- ข้อนี้สำคัญพอ ๆ กับข้อบน — นโยบายที่ปิดจนคนทำงานทำงานไม่ได้คือสิ่งที่
-- จะถูกถอดออกในอีกสามเดือน และไม่มีใครจำได้ว่าทำไมถึงเคยมี (บทเรียนข้อ 14)
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'owner_person', true) as b,
       set_config('app.role',           'academic',   true) as c,
       set_config('test.course_id',     :'course_id', true) as d \gset ctx2_

do $$
declare n integer; v_credits numeric; v_inst uuid := current_setting('app.institution_id')::uuid;
begin
  insert into course (institution_id, edition_be, code, name_th, credits,
                      theory_hours, practice_hours)
  values (v_inst, 2567, 'TEST-278', 'รายวิชาทดสอบขอบเขตการเขียน', 2, 1, 2);
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'TEST 278 ล้มเหลว: ฝ่ายวิชาการสร้างรายวิชาไม่ได้';
  end if;

  update course set credits = 3 where institution_id = v_inst and code = 'TEST-278';
  select credits into v_credits from course
   where institution_id = v_inst and code = 'TEST-278';
  if v_credits <> 3 then
    raise exception 'TEST 278 ล้มเหลว: ฝ่ายวิชาการแก้หน่วยกิตไม่ได้ — ได้ %', v_credits;
  end if;

  -- ── TEST 279 รายวิชาที่ไม่มีใครอ้างถึงลบได้ ────────────────────
  delete from course where institution_id = v_inst and code = 'TEST-278';
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'TEST 279 ล้มเหลว: ลบรายวิชาที่ไม่มีใครอ้างถึงไม่ได้';
  end if;

  -- ── TEST 280 แต่รายวิชาที่มีกลุ่มเรียนอ้างอยู่ลบไม่ได้ ──────────
  --
  -- ผลการเรียนที่ยังไม่ได้ออกเอกสารจะพิมพ์ชื่อวิชาไม่ออก และ
  -- `enrollment_result` แก้ไม่ได้ตามหลักข้อ 4 — ข้อมูลจะค้างในสภาพที่
  -- ซ่อมไม่ได้อีกเลย ปิดด้วย active = false แทน
  select count(*) into n from class_section
   where course_id = current_setting('test.course_id')::uuid;
  if n > 0 then
    begin
      delete from course where id = current_setting('test.course_id')::uuid;
      raise exception 'TEST 280 ล้มเหลว: ลบรายวิชาที่มีกลุ่มเรียนอ้างอยู่ได้';
    exception
      when raise_exception then
        if position('TEST 280 ล้มเหลว' in sqlerrm) > 0 then raise; end if;
    end;
  end if;

  raise notice 'TEST 278 ผ่าน — ฝ่ายวิชาการสร้างและแก้รายวิชาได้ตามปกติ';
  raise notice 'TEST 279 ผ่าน — รายวิชาที่ไม่มีใครอ้างถึงลบได้';
  raise notice 'TEST 280 ผ่าน — รายวิชาที่มีกลุ่มเรียนอ้างอยู่ลบไม่ได้ (% กลุ่ม)', n;
end $$;
rollback;

-- ═══════════════════════════════════════════════════════════════════
-- TEST 281 — ตัวนับตารางที่ยังลบได้โดยไม่มีอะไรกัน
--
-- ─── ทำไมต้องนับ ไม่ใช่บังคับให้เป็นศูนย์ ───
-- 0065 ปิดเฉพาะตระกูลหลักสูตร ที่เหลืออยู่ในโมดูลอื่นซึ่งต้องแก้พร้อมกับ
-- คนที่ดูแลโมดูลนั้น ตัวเลขนี้ต้อง **ลดลงเท่านั้น** เหมือน TEST 185
--
-- ─── ทำไม TEST 185 นับไม่เจอ ───
-- TEST 185 นับนโยบาย restrictive ที่ `with_check is null` ส่วนกลุ่มนี้
-- **มี** with_check ครบ แต่ลืม delete — เป็นช่องคนละบานที่ตัวนับเดิมมองไม่เห็น
-- ═══════════════════════════════════════════════════════════════════
do $$
declare v_rest integer; v_names text;
begin
  select count(*), string_agg(p.tablename, ', ' order by p.tablename)
    into v_rest, v_names
    from pg_policies p
   where p.schemaname = 'public'
     and p.permissive = 'RESTRICTIVE'
     and p.cmd = 'ALL'
     and p.with_check is not null
     and p.qual = 'true'
     and not exists (
       select 1 from pg_policies d
        where d.schemaname = 'public'
          and d.tablename  = p.tablename
          and d.permissive = 'RESTRICTIVE'
          and d.cmd in ('DELETE', 'ALL')
          and d.policyname <> p.policyname
     );

  raise notice 'TEST 281 ผ่าน — ยังเหลืออีก % ตารางที่ลบได้โดยไม่มีนโยบายกัน: %',
    v_rest, coalesce(v_names, 'ไม่มี');
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนของคลังรายวิชาครบทุกข้อ ════'; end $$;

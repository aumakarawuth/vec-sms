-- ═══════════════════════════════════════════════════════════════════
-- 0065 — ขอบเขตการเขียนของคลังรายวิชา และช่องลบที่เปิดค้างมาตั้งแต่ 0017
--
-- ─── เรื่องนี้โผล่ตอนจะทำหน้าจอลงข้อมูลรายวิชา ───
-- ยิงจริงในบริบท `app.role = 'student'` แล้วนักศึกษาทำได้ทั้งสามอย่าง:
--   update course set credits = 99  → รายวิชาภาษาไทยพื้นฐานกลายเป็น 99 หน่วยกิต
--   insert into course ...          → สร้างรายวิชาของตัวเองในหลักสูตร
--   delete from course ...          → ลบรายวิชาทิ้ง
-- ทั้งสามข้อสำเร็จจริง ทดสอบแล้วทั้งก่อนและหลังไฟล์นี้
--
-- ─── ทำไมถึงไม่มีใครเห็น ───
-- 0017 ปิด `curriculum_version` · `curriculum_category` · `curriculum_course`
-- ไว้ครบด้วย `academic_write_only` แล้ว — **ตารางลูกถูกล็อก แต่ตารางแม่เปิดอยู่**
-- คนอ่านนโยบายจะเห็นว่าโครงสร้างหลักสูตรถูกคุ้มครอง โดยที่ `course` ซึ่งเป็น
-- ตัวถือ **จำนวนหน่วยกิต** ที่ใช้ตัดสินการจบ ไม่มีนโยบายบทบาทเลยสักข้อ
-- (`program` · `curriculum` · `grade_scheme` อยู่ในสภาพเดียวกัน — `grade_scheme`
-- คือตัวกำหนดว่าเกรดไหนได้กี่แต้ม)
-- รูปเดียวกับข้อ 10, 11, 13 และ 16 คือช่องที่ **ข้าม API ไปเลย**
--
-- ─── และช่องที่สอง: `with check` ไม่มีผลกับ delete ───
-- `academic_write_only` ของ 0017 เขียนเป็น
--     as restrictive for all using (true) with check (บทบาทวิชาการ)
-- `using (true)` ทำให้การ**อ่าน**ไม่ถูกกระทบ ซึ่งถูกต้อง แต่ `delete` ตรวจด้วย
-- `using` ไม่ใช่ `with check` — นักศึกษาจึง `delete from curriculum_course`
-- ได้ทั้งตาราง (ยิงจริงแล้วลบได้ 12 จาก 12 แถว) กฎข้อนี้เขียนไว้ใน CLAUDE.md
-- ตรง ๆ อยู่แล้ว แต่ตัวนโยบายที่ตั้งใจบังคับมันกลับติดกับดักนั้นเอง
--
-- ไฟล์นี้ปิดเฉพาะตระกูลหลักสูตรที่หน้าจอใหม่แตะ — ยังเหลืออีก 14 ตารางที่
-- ติดกับดัก delete แบบเดียวกัน (`staff_role` · `ledger_transaction` ·
-- `grade_symbol` · `grade_cutoff` · `workplace` …) TEST 274 นับไว้ให้เห็นทุกครั้ง
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. คลังรายวิชาและโครงหลักสูตรระดับบน ─────────────────────────
--
-- แยกเป็น insert / update / delete แทน `for all` โดยตั้งใจ — `for all`
-- แบบ restrictive กิน `select` ไปด้วยถ้าเผลอเขียน `using` เป็นเงื่อนไขบทบาท
-- และถึงเขียน `using (true)` ก็ยังลืม delete อยู่ดี (คือสิ่งที่เกิดขึ้นจริง)
do $$
declare t text;
begin
  foreach t in array array['course', 'program', 'curriculum', 'grade_scheme'] loop
    execute format($f$
      create policy academic_insert on %I
        as restrictive for insert
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
    execute format($f$
      create policy academic_update on %I
        as restrictive for update
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
    execute format($f$
      create policy academic_delete on %I
        as restrictive for delete
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- ── 2. ปิดช่อง delete ของตระกูลหลักสูตรที่ 0017 เปิดค้างไว้ ────────
--
-- ไม่แตะ `academic_write_only` เดิม เพราะมันคุม insert/update ถูกต้องอยู่แล้ว
-- การเพิ่มนโยบาย restrictive อีกข้อรวมกันด้วย AND จึงเป็นการ **เพิ่ม** ข้อจำกัด
-- ไม่ใช่การเขียนทับ — ปลอดภัยกว่าการคัดลอกประโยคเดิมมาแก้ (วิธีที่ 2 ของ 0045)
do $$
declare t text;
begin
  foreach t in array array[
    'curriculum_version', 'curriculum_category', 'curriculum_course',
    'competency', 'course_competency', 'course_prerequisite',
    'entry_pathway', 'graduation_rule', 'pathway_bridging_course', 'program_track'
  ] loop
    execute format($f$
      create policy academic_delete on %I
        as restrictive for delete
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- ── 3. รายวิชาที่มีคนลงทะเบียนแล้วลบไม่ได้ ────────────────────────
--
-- ─── ทำไมเป็น trigger ไม่ใช่นโยบาย ───
-- เงื่อนไขคือ "มีแถวในตารางอื่นอ้างถึงไหม" ซึ่งนโยบาย RLS ตอบไม่ได้โดยไม่
-- ทำให้ทุกคำสั่งลบต้องกางแผนไปอ่านอีกสองตาราง และ foreign key ก็กันไม่ได้
-- เพราะ `enrollment` ชี้ที่ `class_section` ไม่ได้ชี้ที่ `course` ตรง ๆ
--
-- ─── ทำไมต้องกัน ───
-- รายวิชาที่ถูกลบทิ้งแต่มีผลการเรียนอ้างอยู่ ทำให้ใบ รบ. พิมพ์ชื่อวิชาไม่ออก
-- และ `enrollment_result` แก้ไม่ได้ตามหลักข้อ 4 — ข้อมูลจะค้างในสภาพที่
-- ซ่อมไม่ได้อีกเลย ปิดรายวิชาด้วย `active = false` แทน ซึ่งเลือกลงหลักสูตร
-- ใหม่ไม่ได้แต่ของเก่ายังพิมพ์ได้
create or replace function course_delete_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  select count(*) into v_n
    from class_section cs
   where cs.course_id = old.id;

  if v_n > 0 then
    raise exception 'ลบรายวิชา % ไม่ได้ เพราะมีกลุ่มเรียนอ้างอยู่ % กลุ่ม — ปิดการใช้งานแทนด้วยการตั้ง active = false',
      old.code, v_n;
  end if;

  if exists (select 1 from curriculum_course cc where cc.course_id = old.id) then
    raise exception 'ลบรายวิชา % ไม่ได้ เพราะยังอยู่ในโครงสร้างหลักสูตร — เอาออกจากหลักสูตรก่อน',
      old.code;
  end if;

  return old;
end $$;

drop trigger if exists course_delete_guard on course;
create trigger course_delete_guard
  before delete on course
  for each row execute function course_delete_guard();

comment on function course_delete_guard() is
  'กันการลบรายวิชาที่มีกลุ่มเรียนหรือหลักสูตรอ้างอยู่ — ปิดด้วย active = false แทน';

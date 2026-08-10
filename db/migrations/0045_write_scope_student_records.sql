-- ═══════════════════════════════════════════════════════════════════
-- 0045_write_scope_student_records.sql
--
-- ปิดช่องเขียนของเจ้าของในระเบียนนักศึกษาที่เหลือ
--
-- ─── อาการที่ทดสอบแล้วเกิดขึ้นจริง ───
-- ในบริบทนักศึกษา สามตารางนี้เขียนได้จริง (ยิง update แล้วมีแถวถูกแก้)
--
--   student_curriculum  เปลี่ยนฉบับหลักสูตรของตัวเอง = เปลี่ยนกฎการจบ
--                       ที่ใช้กับตัวเองไปเป็นฉบับที่ผ่านง่ายกว่า
--   student_guardian    แก้สิทธิ์ของผู้ปกครองตัวเอง เช่นปิดไม่ให้เห็นเกรด
--   enrollment_result   แถวผลการเรียนของตัวเอง (มี trigger กันการแก้ทับอยู่
--                       อีกชั้น แต่ไม่ควรผ่านมาถึง trigger ตั้งแต่แรก)
--
-- ตารางที่เหลือในไฟล์นี้ทดสอบแล้วไม่พบแถวให้เขียน — ซึ่ง**ไม่ได้แปลว่าปิดอยู่**
-- แค่แปลว่าข้อมูลตัวอย่างไม่มีแถวของนักศึกษาคนที่ทดสอบ นโยบายของทุกตาราง
-- ในรายการนี้มีประโยคเจ้าของอยู่ใน `using` เหมือนกันหมด จึงเปิดช่องเดียวกัน
-- เมื่อมีข้อมูลจริง
--
-- ─── ทำไมเพิ่มนโยบายใหม่แทนการเขียนของเดิมทับ ───
-- ไฟล์ก่อนหน้า (0039 · 0041 · 0042) เขียนนโยบายเดิมทับทั้งก้อน ซึ่งต้อง
-- คัดลอกประโยค `using` ที่ยาวและซับซ้อนมาใหม่ให้ตรงทุกตัวอักษร — สิบห้า
-- ตารางแบบนั้นคือสิบห้าโอกาสที่จะพิมพ์ตกแล้ว**เปิดสิทธิ์อ่านกว้างขึ้น**
-- โดยไม่มีใครเห็น
--
-- restrictive policy รวมกันด้วย AND การเพิ่มนโยบายที่คุมเฉพาะ
-- insert/update/delete จึงบีบสิทธิ์เขียนให้แคบลงโดย**ไม่แตะสิทธิ์อ่านเลย**
-- เจ้าของยังเห็นข้อมูลของตัวเองครบเหมือนเดิมทุกตาราง
--
-- ─── ใครยังเขียนได้ ───
-- บทบาทระดับวิทยาลัยเท่านั้น (registrar · academic · finance ·
-- student_affairs · director · admin) ตรงกับ @Roles ของทุกเส้นทางที่เขียน
-- ตารางเหล่านี้อยู่แล้ว — ตรวจทีละเส้นทางแล้ว ไม่มีเส้นทางไหนให้ครูหรือ
-- นักศึกษาเขียน
-- ═══════════════════════════════════════════════════════════════════
begin;

do $$
declare
  t text;
  tables constant text[] := array[
    -- ระเบียนการเรียนและการจบ
    'enrollment_result', 'student_curriculum', 'student_graduation',
    'student_graduation_status', 'cocurricular_result',
    'professional_standard_assessment', 'prior_academic_record',
    'regrade_candidate',
    -- การจัดชั้นเรียน
    'student_placement', 'student_class_placement',
    -- ผู้ปกครอง
    'student_guardian',
    -- เอกสารที่ออกให้
    'issued_document',
    -- ข้อมูลอ่อนไหวของผู้เยาว์ตาม PDPA — ผลคัดกรองและบันทึกเยี่ยมบ้าน
    'screening_result', 'home_visit'
  ];
begin
  foreach t in array tables loop
    -- นโยบายเดิมยังอยู่ครบ ไม่ถูกแตะ — สามข้อนี้ AND ทับลงไปเฉพาะการเขียน
    execute format($f$
      create policy %1$I_staff_insert on %1$I
        as restrictive for insert
        with check (is_institution_wide_role())
    $f$, t);

    execute format($f$
      create policy %1$I_staff_update on %1$I
        as restrictive for update
        using (is_institution_wide_role())
        with check (is_institution_wide_role())
    $f$, t);

    execute format($f$
      create policy %1$I_staff_delete on %1$I
        as restrictive for delete
        using (is_institution_wide_role())
    $f$, t);
  end loop;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกฝึกอาชีพ — ต้องรวมครูด้วย
--
-- ─── ทำไมแยกจากรายการข้างบน ───
-- ครูนิเทศเป็นคนรับรองชั่วโมงฝึกอาชีพ ไม่ใช่งานทะเบียน (verify_practicum_hours
-- ถูกเรียกในบริบท teacher และ POST ของ dual module กั้นด้วย @Roles ที่มี
-- teacher อยู่) ถ้าใช้ is_institution_wide_role() ล้วนเหมือนตารางอื่น
-- ครูจะรับรองชั่วโมงไม่ได้เลย แล้วกฎการจบข้อ practicum_hours จะไม่มีวันผ่าน
--
-- เจอเพราะ TEST 86 ล้มทันทีที่ใส่ practicum_log ลงในรายการข้างบน
-- ───────────────────────────────────────────────────────────────────
create policy practicum_log_staff_insert on practicum_log
  as restrictive for insert
  with check (is_institution_wide_role() or current_app_role() = 'teacher');

create policy practicum_log_staff_update on practicum_log
  as restrictive for update
  using (is_institution_wide_role() or current_app_role() = 'teacher')
  with check (is_institution_wide_role() or current_app_role() = 'teacher');

create policy practicum_log_staff_delete on practicum_log
  as restrictive for delete
  using (is_institution_wide_role() or current_app_role() = 'teacher');

comment on policy practicum_log_staff_update on practicum_log is
  'นักศึกษาดูชั่วโมงฝึกอาชีพของตัวเองได้ แต่บันทึกและรับรองเองไม่ได้ — ครูนิเทศเป็นผู้รับรอง';

comment on policy student_curriculum_staff_update on student_curriculum is
  'เจ้าของเปลี่ยนฉบับหลักสูตรของตัวเองไม่ได้ — เดิมทำได้ ซึ่งเท่ากับเลือกกฎการจบที่ผ่านง่ายกว่าให้ตัวเอง';
comment on policy student_guardian_staff_update on student_guardian is
  'เจ้าของแก้สิทธิ์ของผู้ปกครองตัวเองไม่ได้ — เดิมปิดไม่ให้ผู้ปกครองเห็นเกรดของตัวเองได้';
comment on policy home_visit_staff_update on home_visit is
  'บันทึกเยี่ยมบ้านเป็นข้อมูลอ่อนไหวของผู้เยาว์ตาม PDPA — เจ้าของอ่านได้แต่แก้และลบไม่ได้';

commit;

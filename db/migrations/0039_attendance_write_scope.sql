-- ═══════════════════════════════════════════════════════════════════
-- 0039_attendance_write_scope.sql
--
-- ปิดช่องที่นักศึกษาแก้เวลาเรียนของตัวเองได้
--
-- ─── อาการที่เกิดขึ้นจริง ───
-- นักศึกษาเรียก POST /attendance/meetings/:id ด้วย enrollment ของตัวเอง
-- แล้วเปลี่ยน "ขาดเรียน" เป็น "มาเรียน" ได้สำเร็จ ทดสอบแล้วได้ผลดังนี้
--
--   ก่อน  pct_to_date 50.00 · absences_left 6 · attendance_state 'warning'
--   หลัง  pct_to_date 100.00 · absences_left 8 · attendance_state 'ok'
--
-- หา meeting_id ครบทุกคาบได้จาก GET /students/:id/schedule ของตัวเอง
-- แล้ววนยิงทีละคาบ กฎเวลาเรียน 80% จึงไม่มีผลกับใครที่รู้วิธีนี้เลย
-- และลบแถวการเช็คชื่อของตัวเองทิ้งได้ด้วย
--
-- ─── ต้นเหตุ — กฎของ PostgreSQL ที่มองข้ามได้ง่ายที่สุด ───
-- policy ที่เขียน `using` ไว้แต่ไม่เขียน `with check` PostgreSQL จะเอา
-- `using` **มาใช้เป็น `with check` ให้เอง** สิทธิ์ที่ตั้งใจให้ "อ่านของตัวเอง"
-- จึงกลายเป็นสิทธิ์ "เขียนของตัวเอง" โดยไม่มีใครเขียนบรรทัดไหนอนุญาต
--
--   attendance_scope (0012) ... or enrollment_id in (actor_enrollment_ids())
--   meeting_scope    (0017) ... or class_section_id in (actor_section_ids())
--
-- ทั้งสองประโยคเขียนไว้ให้นักศึกษา**ดู**เวลาเรียนและตารางของตัวเองได้
--
-- ─── ทำไมคาบเรียนต้องแก้ด้วย ───
-- ตัวบันทึกการเช็คชื่อปิดคาบให้อัตโนมัติ (status = 'held') ซึ่งเพิ่ม
-- ตัวหารของกฎ 80% ให้ **ทุกคน** ในกลุ่มเรียน นักศึกษาคนเดียวจึงยิงคาบที่
-- ยังไม่ถึงกำหนดเพื่อกดเปอร์เซ็นต์ของเพื่อนทั้งห้องให้ต่ำกว่าเกณฑ์ได้
-- (ทดสอบแล้ว — B ยิงหนึ่งคาบ periods_held ของ A ขยับจาก 2 เป็น 4)
--
-- ─── ทำไม with check อย่างเดียวไม่พอ ───
-- `with check` มีผลกับ insert และ update เท่านั้น **delete ไม่มี with check**
-- PostgreSQL ใช้ `using` ตัดสิน delete ล้วน ๆ ถ้าไม่เพิ่มนโยบายเฉพาะ
-- นักศึกษาจะยังลบแถวของตัวเองทิ้งได้ ซึ่งได้ผลเหมือนแก้เป็นมาเรียน
-- (แถวที่ไม่มี = ไม่ถูกนับเป็นขาด) จึงต้องมีนโยบาย for delete แยกอีกตัว
--
-- ─── ขอบเขตของไฟล์นี้ ───
-- ปิดเฉพาะเส้นทางเขียนเวลาเรียน ซึ่งเป็นจุดเดียวที่มี endpoint ให้นักศึกษา
-- เรียกถึงได้จริง รูปแบบ using-ไม่มี-with-check ยังมีอยู่อีกหลายสิบตาราง
-- (ดู TEST 183 ที่นับไว้ให้) ตารางเหล่านั้นยังกันด้วย @Roles ที่ชั้น API
-- ชั้นเดียว ซึ่งขัดกับหลักข้อ 1 ที่ว่าฐานข้อมูลเป็นเจ้าของกฎ — ต้องตามปิดต่อ
--
-- ─── ถ้าวันหน้าทำ A-05 ให้นักศึกษาเช็คอินเอง ───
-- ห้ามแก้ด้วยการเอาประโยค actor_enrollment_ids() กลับเข้า with check
-- เพราะนั่นคือการเปิดช่องนี้คืน ให้ทำเป็นตารางคำขอเช็คอินแยกที่ครูยืนยัน
-- แล้วค่อยกลายเป็น attendance_record — คนถูกเช็คต้องไม่ใช่คนเขียนผลเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- การเช็คชื่อ — อ่านของตัวเองได้ แต่เขียนได้เฉพาะครูผู้สอนและงานส่วนกลาง
-- ───────────────────────────────────────────────────────────────────
drop policy if exists attendance_scope on attendance_record;

create policy attendance_scope on attendance_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
    -- นักศึกษาและผู้ปกครองที่ยืนยันแล้ว — **อ่านอย่างเดียว**
    -- ประโยคนี้ต้องไม่ปรากฏใน with check ด้านล่างเด็ดขาด
    or attendance_record.enrollment_id in (select actor_enrollment_ids())
  )
  with check (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
  );

-- delete ไม่ผ่าน with check จึงต้องมีนโยบายของตัวเอง
create policy attendance_no_subject_delete on attendance_record
  as restrictive for delete
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
  );

comment on policy attendance_scope on attendance_record is
  'เจ้าของอ่านได้ แต่เขียนได้เฉพาะครูผู้สอนและงานส่วนกลาง — with check ต้องไม่มีประโยคของเจ้าของ';

-- ───────────────────────────────────────────────────────────────────
-- คาบเรียน — นักศึกษาเห็นตารางของตัวเอง แต่ปิดคาบเองไม่ได้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists meeting_scope on class_meeting;

create policy meeting_scope on class_meeting
  as restrictive
  using (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
    -- นักศึกษาที่ลงทะเบียนในกลุ่มนี้ — **อ่านอย่างเดียว**
    or class_meeting.class_section_id in (select actor_section_ids())
  )
  with check (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
  );

create policy meeting_no_student_delete on class_meeting
  as restrictive for delete
  using (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
  );

comment on policy meeting_scope on class_meeting is
  'นักศึกษาเห็นตารางของตัวเอง แต่ปิดคาบไม่ได้ — การปิดคาบเพิ่มตัวหารกฎ 80% ให้ทั้งห้อง';

commit;

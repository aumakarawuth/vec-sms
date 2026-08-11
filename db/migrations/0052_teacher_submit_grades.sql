-- ═══════════════════════════════════════════════════════════════════
-- 0052 — ครูส่งเกรดของกลุ่มเรียนตัวเองได้
--
-- ─── ปัญหา ───
-- `submit_section_grades()` ไม่ใช่ security definer โดยตั้งใจ (ดู 0049)
-- ครูจึงต้องมีสิทธิ์เขียนตารางที่ฟังก์ชันแตะจริง ๆ ทุกตาราง
-- 0049 เปิด `grade_submission` ให้แล้ว แต่ `enrollment_result` ยังปิดอยู่
-- เพราะ 0041 ตั้ง `enrollment_result_staff_insert` ไว้ที่
-- `is_institution_wide_role()` ล้วน
--
-- ผลคือ **ครูส่งเกรดของตัวเองไม่ได้เลยสักครั้ง** — ได้ 403 ทุกครั้งที่กด
-- ทั้งที่ขั้นแรกของสายอนุมัติชื่อ `teacher_submitted` และ `STAGE_APPROVERS`
-- ในชั้น API ก็ระบุว่าขั้นนั้นเป็นของครู งานทะเบียนต้องเป็นคนกดส่งแทน
-- ทุกกลุ่มเรียนของทั้งวิทยาลัย ซึ่งไม่ใช่สิ่งที่ระบบออกแบบไว้
--
-- ─── ทำไมไม่มีใครเห็น ───
-- เทสต์ทุกชุด `insert into grade_submission` ตรงด้วยสิทธิ์เจ้าของฐานข้อมูล
-- ในขั้นเตรียมข้อมูล แล้วทดสอบขั้นถัด ๆ ไป — ไม่มีเทสต์ไหนเดินเส้นทาง
-- "ครูกดส่งเกรดของตัวเอง" เลยสักข้อ รูปแบบเดียวกับ AUTH-26 ที่ผ่านมาตลอด
-- เพราะหยิบ token จากทางที่ระบบจริงไม่มี
--
-- ─── ทำไมเปิดแค่นี้ถึงปลอดภัย ───
-- เงื่อนไขผูกกับสิ่งที่ฟังก์ชันยอมทำอยู่แล้วสามชั้น
--   1. ต้องเป็นครูผู้สอนของกลุ่มเรียนนั้นเอง ไม่ใช่ครูคนไหนก็ได้
--   2. รอบส่งเกรดต้องอยู่ขั้น draft หรือ returned เท่านั้น —
--      `submit_section_grades()` ปฏิเสธขั้นอื่นอยู่แล้ว (0016 บรรทัด 211)
--      นโยบายนี้จึงไม่ได้เปิดอะไรที่ฟังก์ชันไม่ยอมทำ
--   3. รอบที่ล็อกแล้วยังแก้ไม่ได้เหมือนเดิม การเปลี่ยนเกรดหลังล็อกยังต้อง
--      ผ่าน `grade_change_request` ที่ต้องมีผู้อนุมัติสองคน (หลักข้อ 3ก)
--
-- สิทธิ์ update และ delete ยังปิดสำหรับครูเหมือนเดิม — `enrollment_result`
-- แก้ทับไม่ได้อยู่แล้ว ต้องออก revision ใหม่ที่ชี้กลับแถวเดิม (หลักข้อ 4)
--
-- ─── ทำไมต้องแก้ตัวนโยบายเดิม ไม่ใช่เพิ่มนโยบายใหม่ ───
-- `enrollment_result_staff_insert` เป็น **restrictive** ซึ่ง PostgreSQL รวม
-- ด้วย AND การเพิ่มนโยบาย permissive อีกข้อจึงไม่มีผลเลย — ต้องแก้เงื่อนไข
-- ในตัวมันเอง (หลักข้อ 2 ของโปรเจกต์: permissive รวมด้วย OR · restrictive
-- รวมด้วย AND)
-- ═══════════════════════════════════════════════════════════════════

begin;

-- เผื่อกรณีที่เคยลองเพิ่มแบบ permissive ไว้ ซึ่งไม่มีผลกับ restrictive
drop policy if exists enrollment_result_teacher_insert on enrollment_result;

drop policy if exists enrollment_result_staff_insert on enrollment_result;

create policy enrollment_result_staff_insert on enrollment_result
  as restrictive for insert
  with check (
    is_institution_wide_role()
    or exists (
      select 1
        from enrollment e
        join class_section cs on cs.id = e.class_section_id
        join staff st         on st.id = cs.teacher_id
        left join grade_submission gs on gs.class_section_id = cs.id
       where e.id = enrollment_result.enrollment_id
         and st.person_id = current_actor_id()
         -- ยังไม่มีแถว = ยังไม่เคยส่ง ซึ่งเทียบเท่า draft
         and coalesce(gs.stage::text, 'draft') in ('draft', 'returned')
    )
  );

comment on policy enrollment_result_staff_insert on enrollment_result is
  'บทบาทระดับวิทยาลัยบันทึกผลได้เสมอ · ครูผู้สอนบันทึกได้เฉพาะกลุ่มเรียนของตัวเองและเฉพาะตอนที่รอบส่งเกรดยังไม่ล็อก — หลังล็อกต้องผ่าน grade_change_request';

commit;

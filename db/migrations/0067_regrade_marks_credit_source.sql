-- ═══════════════════════════════════════════════════════════════════
-- 0067 — (*3) เรียนปรับระดับคะแนน ติดให้เองเมื่อคำร้องจากรอบสอบซ่อมมีผล
--
-- ─── ทำไมต้องมีไฟล์นี้ ───
-- 0066 สร้าง `credit_source = 'regraded'` ไว้พร้อมตัวแปลงและแม่แบบที่พิมพ์
-- (*3) ได้จริง แต่ **ไม่มีเส้นทางไหนตั้งค่านั้นเลยสักที่** ถ้าปล่อยไว้มันจะ
-- กลายเป็นของอีกชิ้นในรายการ "ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เกิด"
-- ต่อจาก `can_approve_leave` (ข้อ 15) และ `take_usage_snapshot` (ข้อ 8)
--
-- ─── ทำไมเป็น trigger ไม่ใช่เขียน apply_grade_change() ทับ ───
-- ฟังก์ชันนั้นยาว 1,683 อักขระและมีนิยามเดียวมาตั้งแต่ 0018 การเขียนทับ
-- ทั้งตัวเพื่อเพิ่มบล็อกเดียวคือกับดักที่ 0059 บันทึกไว้ — และผมเพิ่งเดินเข้า
-- ไปเองใน 0066 ตอนคัดลอก `transcript_courses_grouped()` มาจากรุ่นเก่าแล้ว
-- ทำ `plan_year_be` หายไปสองช่อง
--
-- เงื่อนไขที่ต้องดักคือ "คำร้องนี้มีผลแล้ว" ซึ่งเป็นการเปลี่ยนค่าในแถว
-- จึงเป็นรูปที่ trigger ตอบได้ตรงกว่า และดักได้ทุกเส้นทางที่ทำให้คำร้องมีผล
-- ไม่ใช่เฉพาะเส้นที่ผ่าน `apply_grade_change()` (หลักเดียวกับ 0049)
--
-- ─── ทำไมเฉพาะ restudy ไม่รวม retest ───
-- `regrade_kind` มีสองค่า — `retest` คือสอบซ่อม ส่วน `restudy` คือเรียน
-- ปรับระดับคะแนน ถ้อยคำของ (*3) คือ "เรียนปรับระดับคะแนน" ตรงตัว
-- สอบซ่อมคือการสอบใหม่หลังไม่ผ่าน ไม่ใช่การเรียนซ้ำเพื่อยกเกรดที่ผ่านแล้ว
-- ติดเครื่องหมายให้สอบซ่อมด้วยจะทำให้ใบบอกสิ่งที่ไม่ได้เกิดขึ้น
-- ═══════════════════════════════════════════════════════════════════

create or replace function regrade_marks_credit_source() returns trigger
language plpgsql as $$
begin
  if new.status = 'applied' and old.status is distinct from 'applied' then
    /*
     * ─── ทำไมแตะเฉพาะแถวที่ยังเป็น 'studied' ───
     * วิชาที่เทียบโอนมาแล้วมาขอปรับเกรดทีหลังยังต้องคง (*1)/(*2) ไว้
     * เพราะที่มาของหน่วยกิตไม่ได้เปลี่ยน — เปลี่ยนแค่ระดับคะแนน
     * ถ้าเขียนทับ ใบจะบอกว่าเรียนเองทั้งที่โอนมา ซึ่งผิดข้อเท็จจริง
     */
    update enrollment e
       set credit_source = 'regraded'
      from regrade_candidate rc
      join regrade_session_course rsc on rsc.id = rc.session_course_id
      join regrade_session rs         on rs.id  = rsc.session_id
     where rc.change_request_id = new.id
       and rs.kind = 'restudy'
       and e.id = rc.source_enrollment_id
       and e.credit_source = 'studied';
  end if;
  return new;
end $$;

drop trigger if exists regrade_marks_credit_source on grade_change_request;
create trigger regrade_marks_credit_source
  after update on grade_change_request
  for each row execute function regrade_marks_credit_source();

comment on function regrade_marks_credit_source() is
  'ติด (*3) ให้การลงทะเบียนเดิมเมื่อคำร้องจากรอบเรียนปรับระดับคะแนนมีผล — สอบซ่อมไม่ติด';

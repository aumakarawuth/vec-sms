-- ═══════════════════════════════════════════════════════════════════
-- 0049_write_scope_teacher_and_hr.sql
--
-- ปิดช่องเขียนของ **ครู** และของ **เจ้าของระเบียนบุคลากร**
--
-- ─── ยิงจริงในบริบทครูแล้วทำได้ทั้งห้าข้อนี้ ───
--   1. `update grade_submission set locked_at = null, stage = 'draft'`
--      ปลดล็อกรอบส่งเกรดของตัวเอง แล้วกลับไปแก้เกรดตรง ๆ ได้เลย
--      **ข้อนี้ล้มหลัก 3ก ทั้งข้อ** — เหตุผลเดียวที่คำร้องแก้เกรดต้องมี
--      ผู้อนุมัติสองคน คือเพราะรอบที่ล็อกแล้วแก้ไม่ได้ ถ้าปลดล็อกเองได้
--      ไม่มีใครต้องยื่นคำร้องอีกเลย
--   2. `delete from grade_submission_event` ลบประวัติว่าใครเลื่อนขั้นเมื่อไร
--      (ยืนยันแล้วว่าลบได้จริง 1 แถว) — หลักฐานของข้อ 1 อยู่ตรงนี้
--   3. `update class_section` แก้รายละเอียดกลุ่มเรียนของตัวเอง
--   4. `insert/update staff_record` เพิ่มวุฒิและชั่วโมงอบรมปลอมให้ตัวเอง
--      (ระเบียน ทช.1 ใช้ประกอบการต่อใบอนุญาตและการเลื่อนวิทยฐานะ)
--   5. `insert staff_child` ผูกตัวเองเป็นผู้ปกครองของนักศึกษาคนใดก็ได้
--      ที่ยังไม่ถูกผูก (มีผลต่อสิทธิ์ลดหย่อนค่าเล่าเรียน)
--
-- ─── สิ่งที่ตรวจแล้วพบว่า "กันไว้แล้ว" ไม่ต้องแตะ ───
-- ทดสอบสามข้อนี้แล้วถูกปฏิเสธด้วย trigger ที่มีอยู่เดิม ไม่ใช่ด้วยความบังเอิญ
--   · ครูอนุมัติคำร้องแก้เกรดของตัวเองไม่ได้ ('ผู้ยื่นคำร้องเป็นผู้อนุมัติ
--     คำร้องของตัวเองไม่ได้') และตั้งสถานะเป็นอนุมัติโดยไม่มีผู้อนุมัติครบ
--     สองคนไม่ได้ — ลองทั้งแบบคำสั่งเดียวและแบบแยกทีละคำสั่งแล้ว
--   · ครูอนุมัติใบลาของตัวเองไม่ได้ ('ผู้ยื่นใบลาอนุมัติใบลาของตัวเองไม่ได้')
--   · ครูถอดตัวเองออกจากกลุ่มเรียนไม่ได้ (`teacher_id = null` ทำให้แถวใหม่
--     ตกนโยบายเดิม เพราะ `using` ถูกใช้เป็น `with check` — บังเอิญกันไว้ให้
--     แต่กันได้แค่คอลัมน์เดียว คอลัมน์อื่นยังแก้ได้ตามข้อ 3)
--
-- ─── ทำไมสองตารางเกรดใช้ trigger ไม่ใช่นโยบายอย่างเดียว ───
-- `submit_section_grades()` กับ `advance_grade_submission()` **ไม่ใช่**
-- security definer จึงทำงานในบทบาทของผู้เรียก — ครูที่ส่งเกรดต้องเขียน
-- `grade_submission` ได้จริง การปิดด้วย restrictive policy ทั้งตารางจะทำให้
-- ครูส่งเกรดไม่ได้เลย ซึ่งเป็นความผิดพลาดแบบเดียวกับที่ 0045 เคยทำกับ
-- `practicum_log` (ปิดจนนักศึกษาบันทึกชั่วโมงของตัวเองไม่ได้ = A-06 พังทั้งจอ)
--
-- สิ่งที่ต้องห้ามจึงไม่ใช่ "ครูเขียนตารางนี้" แต่คือ "การย้อนสิ่งที่ล็อกแล้ว"
-- ซึ่งเป็นเงื่อนไขระดับค่าในแถว ไม่ใช่ระดับตาราง — RLS ทำไม่ได้ trigger ทำได้
-- และ trigger บังคับกับ**ทุกทาง**ที่เข้าถึงข้อมูล ไม่ใช่แค่ทางที่ผ่านฟังก์ชัน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- 1. ล็อกแล้วคือล็อก — บังคับที่แถว ไม่ใช่ที่ฟังก์ชัน
--
-- `advance_grade_submission()` ปฏิเสธการเลื่อนขั้นของรอบที่ล็อกแล้วอยู่ก่อน
-- แต่การ `update` ตรง ๆ ไม่ผ่านฟังก์ชันจึงไม่เจอเงื่อนไขนั้นเลย
-- trigger ย้ายกฎเดียวกันมาไว้ที่แถว ทางไหนก็หนีไม่พ้น
-- ───────────────────────────────────────────────────────────────────
create or replace function grade_submission_lock_guard()
returns trigger language plpgsql as $$
begin
  -- ต้องปล่อยผ่านให้ superuser และให้บริบทที่ไม่มีผู้ใช้
  --
  -- trigger ยิงกับ superuser ด้วย ต่างจาก RLS ที่ superuser ข้ามอยู่แล้ว
  -- งานย้ายข้อมูล การกู้คืน และการเตรียมข้อมูลของเทสต์จึงติดกับดักของ
  -- ตัวเองทันทีถ้าไม่ปล่อย (บทเรียนเดียวกับ user_credential_owner_guard()
  -- ใน 0042 — ครั้งนั้นดูแค่ `current_app_role() = 'none'` ซึ่ง**ไม่พอ**
  -- เพราะสคริปต์ที่รันเป็น postgres มักตั้ง `app.role` ไว้ด้วยเพื่อทดสอบ
  -- มุมมองของบทบาทหนึ่ง แล้วค่อยกลับมาเตรียมข้อมูลต่อ)
  --
  -- ปล่อยให้ superuser ไม่ได้ลดความปลอดภัยลงเลย เพราะคนที่เป็น superuser
  -- ถอด trigger ทิ้งได้อยู่แล้ว และแอปไม่ยอมบูตถ้าต่อ DB ด้วย superuser
  -- (หลัก 6) ส่วนบริบทที่ไม่มี `app.role` ก็ไม่มี `app.institution_id`
  -- นโยบาย RLS ชั้นแรกจึงปฏิเสธทุกแถวอยู่แล้ว
  if current_setting('is_superuser', true) = 'on' or current_app_role() = 'none' then
    return new;
  end if;

  if old.locked_at is not null and new.locked_at is distinct from old.locked_at then
    raise exception 'รอบส่งเกรดที่ล็อกแล้วปลดล็อกไม่ได้ '
      'การแก้เกรดหลังล็อกต้องยื่นคำร้องแก้เกรดที่มีผู้อนุมัติสองคน';
  end if;

  if old.stage = 'locked' and new.stage is distinct from old.stage then
    raise exception 'รอบส่งเกรดที่ล็อกแล้วย้อนขั้นไม่ได้ (ขอย้อนไป %) '
      'การแก้เกรดหลังล็อกต้องยื่นคำร้องแก้เกรดที่มีผู้อนุมัติสองคน', new.stage;
  end if;

  return new;
end $$;

comment on function grade_submission_lock_guard() is
  'ล็อกแล้วคือล็อก — ห้ามล้าง locked_at และห้ามย้อนขั้นจาก locked ไม่ว่าจะเข้าทางไหน';

create trigger grade_submission_lock_guard
  before update on grade_submission
  for each row execute function grade_submission_lock_guard();

-- ลบทั้งแถวได้ผลเท่ากับปลดล็อก จึงต้องปิดด้วยกัน
-- (งานทะเบียนยังลบรอบที่ยังไม่ล็อกทิ้งได้ เช่นเปิดผิดกลุ่มเรียน)
create policy grade_submission_staff_delete on grade_submission
  as restrictive for delete
  using (is_institution_wide_role() and locked_at is null);

-- ───────────────────────────────────────────────────────────────────
-- 2. ประวัติการเลื่อนขั้นเป็นบันทึกที่เพิ่มได้อย่างเดียว
--
-- หลักการเดียวกับ access_log และ grade_ledger — ถ้าคนที่เลื่อนขั้นลบหรือ
-- แก้ประวัติของตัวเองได้ ประวัตินั้นไม่ใช่หลักฐาน มันเป็นแค่ความเห็นของ
-- คนล่าสุดที่แตะมัน
--
-- ห้ามทุกบทบาทรวมถึงผู้ดูแล ไม่ใช่ห้ามเฉพาะครู — ผู้ดูแลที่ลบประวัติได้
-- คือจุดเดียวที่ทำให้บันทึกทั้งชุดใช้เป็นหลักฐานไม่ได้
-- ───────────────────────────────────────────────────────────────────
create policy grade_submission_event_no_update on grade_submission_event
  as restrictive for update using (false);

create policy grade_submission_event_no_delete on grade_submission_event
  as restrictive for delete using (false);

-- ───────────────────────────────────────────────────────────────────
-- 3. กลุ่มเรียน · ระเบียนบุคลากร · บุตรบุคลากร — เขียนได้เฉพาะระดับวิทยาลัย
--
-- ตรวจทุกเส้นทางที่เขียนสามตารางนี้แล้ว
--   · `class_section` ไม่มีเส้นทาง API ไหนเขียนเลยสักเส้น ตัวที่เขียนคือ
--     `generate_class_meetings()` ซึ่งเรียกจากงานทะเบียนก่อนเปิดภาคเรียน
--   · `staff_record` / `staff_child` เขียนที่ `POST /hr/staff/:id/records`
--     และ `/children` ซึ่ง `HrController` ตั้ง `@Roles('registrar',
--     'director', 'admin')` ไว้อยู่แล้ว — ครูเรียกไม่ได้ผ่าน API มาตั้งแต่ต้น
--     ช่องที่เปิดอยู่คือช่องที่ **ข้าม API** เท่านั้น ซึ่งเป็นรูปแบบเดียวกับ
--     ข้อ 10 และ 11 ในรายการ "เคยพังแบบเงียบ ๆ"
--
-- เจ้าของยังอ่านของตัวเองได้ครบเหมือนเดิม — restrictive คุมเฉพาะการเขียน
-- ───────────────────────────────────────────────────────────────────
do $$
declare
  t text;
  tables constant text[] := array['class_section', 'staff_record', 'staff_child'];
begin
  foreach t in array tables loop
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

commit;

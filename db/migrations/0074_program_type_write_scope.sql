-- ═══════════════════════════════════════════════════════════════════
-- 0074 — program_type ไม่มีนโยบายบทบาทเลยสักข้อ ตั้งแต่ตารางถูกสร้าง
--
-- ─── เรื่องนี้โผล่ตอนจะเปิดเส้นทางสร้างสาขาวิชาใหม่จากหน้าจอ ───
-- 0065 ปิด `program` · `curriculum` · `course` · `grade_scheme` ไว้ครบแล้ว
-- (insert/update/delete ต้องเป็นบทบาทวิชาการ) และ 0065 ส่วนที่สองเพิ่ม
-- `academic_delete` ให้ `program_track` อีกตัว — แต่ `program_type` ซึ่งเป็น
-- ตารางแม่สุดของทั้งสายไม่เคยอยู่ในรายการทั้งสองชุดนั้นเลย
--
-- ยิงจริงในบริบท `app.role = 'student'` แล้ว
--   insert into program_type (institution_id, code, name_th)
--     values (current_institution_id(), '99', 'ทดสอบ')
-- สำเร็จจริง — นักศึกษาสร้างหมวดสาขาของทั้งวิทยาลัยเองได้ ทั้งที่ไม่เคย
-- มีเส้นทาง API ไหนแตะตารางนี้เลยสักเส้นจนถึงไฟล์นี้ — รูปเดียวกับ
-- ข้อ 16 ใน CLAUDE.md ("ตารางที่ไม่มี API ไม่ได้แปลว่าปิด แปลว่ายังไม่มี
-- ใครดู") เพราะการอ่านโค้ด API ให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้าม
-- กับความจริง — ต้องยิง SQL ตรงถึงจะเจอ
--
-- ปิดด้วยรูปแบบเดียวกับ 0065 ข้อ 1 เป๊ะ (แยก insert/update/delete แทน
-- `for all` เพราะ `for all` แบบ restrictive กิน select ไปด้วยถ้าเผลอเขียน
-- `using` เป็นเงื่อนไขบทบาท)
-- ═══════════════════════════════════════════════════════════════════

create policy academic_insert on program_type
  as restrictive for insert
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_update on program_type
  as restrictive for update
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_delete on program_type
  as restrictive for delete
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

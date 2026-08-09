-- ═══════════════════════════════════════════════════════════════════
-- 0024_scale_indexes.sql
--
-- ดัชนีสำหรับเส้นทางที่ถูกเรียกบ่อยที่สุดเมื่อข้อมูลโตขึ้น
--
-- ─── ทำไมเรื่องนี้สำคัญกว่าที่เห็นในระบบหลายผู้เช่า ───
-- ทุกวิทยาลัยใช้ตารางชุดเดียวกัน แยกกันด้วย Row-Level Security
-- แปลว่าการค้นหานักศึกษาของวิทยาลัยหนึ่ง **สแกนแถวของทุกวิทยาลัย**
-- แล้วค่อยให้ RLS กรองทิ้ง
--
-- วิทยาลัยเดียว 5,000 คนสแกน 5,000 แถว — ยอมรับได้
-- ยี่สิบวิทยาลัยรวม 100,000 คน การค้นหาของวิทยาลัยที่มีนักศึกษา 200 คน
-- ก็ยังสแกน 100,000 แถวอยู่ดี ซึ่งเป็นภาระที่ลูกค้ารายเล็กไม่ได้ก่อ
-- แต่ต้องแบกด้วย และแย่ลงเรื่อย ๆ ทุกครั้งที่ขายลูกค้าเพิ่ม
--
-- ─── ทำไม ilike '%คำ%' ใช้ดัชนีปกติไม่ได้ ───
-- ดัชนี btree เรียงตามลำดับตัวอักษรจากซ้าย จึงหา "ขึ้นต้นด้วย" ได้เร็ว
-- แต่ "มีคำนี้อยู่ตรงไหนก็ได้" ต้องดูทุกแถว ช่องค้นหาที่พิมพ์แล้วค้นทันที
-- จึงกลายเป็นการสแกนเต็มตารางทุกตัวอักษรที่พิมพ์
--
-- pg_trgm ตัดข้อความเป็นชุดสามตัวอักษรแล้วทำดัชนีจากชุดเหล่านั้น
-- ทำให้ค้นแบบมีคำอยู่ตรงกลางได้เร็ว และใช้ได้กับภาษาไทยด้วย
-- ═══════════════════════════════════════════════════════════════════
begin;

create extension if not exists pg_trgm;

-- ───────────────────────────────────────────────────────────────────
-- ค้นหานักศึกษาและบุคลากร — เส้นทางที่เจ้าหน้าที่ใช้บ่อยที่สุด
-- ───────────────────────────────────────────────────────────────────
create index if not exists student_code_trgm_idx
  on student using gin (student_code gin_trgm_ops);

create index if not exists person_first_name_trgm_idx
  on person using gin (first_name_th gin_trgm_ops);

create index if not exists person_last_name_trgm_idx
  on person using gin (last_name_th gin_trgm_ops);

create index if not exists staff_code_trgm_idx
  on staff using gin (staff_code gin_trgm_ops);

-- ───────────────────────────────────────────────────────────────────
-- ดัชนีที่ขึ้นต้นด้วย institution_id
--
-- RLS เติมเงื่อนไข institution_id = current_institution_id() ให้ทุก query
-- อยู่แล้ว ดัชนีที่ขึ้นต้นด้วยคอลัมน์นั้นจึงตัดข้อมูลของวิทยาลัยอื่นทิ้ง
-- ตั้งแต่ระดับดัชนี ไม่ต้องอ่านแถวขึ้นมาก่อนแล้วค่อยกรอง
-- ───────────────────────────────────────────────────────────────────
create index if not exists student_institution_status_idx
  on student (institution_id, status, student_code);

create index if not exists person_institution_idx
  on person (institution_id);

-- ───────────────────────────────────────────────────────────────────
-- เส้นทางของแอปนักศึกษา — ถูกเรียกพร้อมกันมากที่สุดตอนประกาศผล
--
-- ช่วงประกาศผลคือช่วงที่ทุกคนเปิดแอปพร้อมกันภายในไม่กี่นาที
-- ซึ่งเป็นภาระสูงสุดของทั้งปี และเป็นช่วงที่ระบบล่มแล้วเสียหายที่สุด
-- ───────────────────────────────────────────────────────────────────
create index if not exists enrollment_student_term_idx
  on enrollment (student_id, term_id) where status = 'enrolled';

create index if not exists attendance_record_enrollment_idx
  on attendance_record (enrollment_id);

create index if not exists enrollment_result_current_lookup_idx
  on enrollment_result (enrollment_id) where superseded_by is null;

create index if not exists invoice_student_term_idx
  on invoice (student_id, term_id);

create index if not exists installment_due_idx
  on installment (invoice_id, due_on) where status <> 'paid';

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการเข้าถึง — เขียนทุกคำขอที่เปลี่ยนแปลงข้อมูล
--
-- ตารางนี้โตเร็วที่สุดในระบบ การล้างตามระยะเก็บต้องหาแถวเก่าได้เร็ว
-- มิฉะนั้นงานประจำวันจะสแกนทั้งตารางทุกคืนและช้าลงเรื่อย ๆ
-- ───────────────────────────────────────────────────────────────────
create index if not exists access_log_occurred_idx on access_log (occurred_at);

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 0082 — หมวดภาคเรียน (term_category) และช่องวันที่ย่อยของภาคเรียน
--
-- ─── ทำไมต้องมีตารางใหม่ ───
-- วิทยาลัยอาชีวศึกษาบางแห่งเปิดหลายรอบในภาคเรียนเดียวกัน (รอบเช้า/รอบบ่าย/
-- ทวิภาคี) ซึ่งแต่ละรอบมีปฏิทินของตัวเอง (วันลงทะเบียน วันชำระเงิน ฯลฯ
-- อาจไม่ตรงกัน) `term` เดิมผูกกับ `academic_year` ตรง ๆ ไม่มีชั้นจัดกลุ่มนี้
--
-- `term_category` เป็นตารางเลือกได้ (institution_id ผูกกับวิทยาลัย ไม่ผูก
-- กับปีการศึกษาใดปีหนึ่ง) เพราะรอบเรียนเป็นรูปแบบการจัดองค์กรของวิทยาลัย
-- ไม่ใช่ของภาคเรียนใดภาคเรียนหนึ่ง — สร้างครั้งเดียวใช้ได้ทุกปี
--
-- ─── ทำไมช่องวันที่ใหม่ไม่ซ้ำกับที่มีอยู่ ───
-- `add_drop_ends_on` (สิ้นสุดเพิ่ม-ถอน) และ `grade_due_on` (กำหนดส่งเกรด)
-- มีอยู่แล้วตั้งแต่ 0001 — คือ "วันสิ้นสุด" ของงานลงทะเบียนรายวิชาและงาน
-- สมุดบันทึกคะแนนตามลำดับ จึงไม่เพิ่มคอลัมน์ใหม่ซ้ำ เพิ่มเฉพาะ "วันเริ่มต้น"
-- ที่ยังไม่มี (`registration_starts_on`, `gradebook_starts_on`) บวกช่วงที่
-- ไม่เคยมีเลยทั้งคู่ (การชำระเงิน, การตรวจสอบข้อมูลจบโดยนักศึกษา)
-- ═══════════════════════════════════════════════════════════════════

create table term_category (
  id              uuid      primary key default gen_random_uuid(),
  institution_id  uuid      not null references institution on delete restrict,
  title           text      not null,
  sort_order      smallint  not null default 0,
  created_at      timestamptz not null default now(),
  unique (institution_id, title)
);

alter table term_category enable row level security;
alter table term_category force  row level security;

create policy tenant_isolation on term_category
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- เหตุผลของการแยก insert/update/delete แทน `for all` — ดู 0074/0065
create policy academic_insert on term_category
  as restrictive for insert
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_update on term_category
  as restrictive for update
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_delete on term_category
  as restrictive for delete
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

alter table term add column category_id       uuid references term_category on delete set null;
alter table term add column short_name        text;
alter table term add column sort_order        smallint    not null default 0;
alter table term add column is_normal         boolean     not null default true;
alter table term add column registration_starts_on date;
alter table term add column gradebook_starts_on    date;
alter table term add column payment_starts_on      date;
alter table term add column payment_ends_on        date;
alter table term add column audit_starts_on        date;
alter table term add column audit_ends_on          date;

comment on column term.category_id is
  'หมวด/รอบเรียนที่ภาคเรียนนี้สังกัด (รอบเช้า/รอบบ่าย/ทวิภาคี ฯลฯ) — ว่างได้ วิทยาลัยที่ไม่แยกรอบไม่ต้องตั้งค่านี้';
comment on column term.is_normal is
  'ภาคเรียนปกติ (true) หรือภาคพิเศษ/ปรับพื้นฐาน (false) — ใช้กรองแสดงผลไม่ให้ปนกับภาคที่ ordinal=0';

alter table term add constraint term_registration_range
  check (registration_starts_on is null or add_drop_ends_on is null or registration_starts_on <= add_drop_ends_on);
alter table term add constraint term_gradebook_range
  check (gradebook_starts_on is null or grade_due_on is null or gradebook_starts_on <= grade_due_on);
alter table term add constraint term_payment_range
  check (payment_starts_on is null or payment_ends_on is null or payment_starts_on <= payment_ends_on);
alter table term add constraint term_audit_range
  check (audit_starts_on is null or audit_ends_on is null or audit_starts_on <= audit_ends_on);

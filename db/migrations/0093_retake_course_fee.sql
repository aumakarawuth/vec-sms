-- ═══════════════════════════════════════════════════════════════════
-- 0093 — ค่าซ่อมรายวิชา: ลงทะเบียนซ่อม → ออกยอดให้การเงิน → รอชำระเงิน →
-- ซ่อนจากสมุดคะแนนจนกว่าจะชำระ → ไม่ปนกับใบแจ้งหนี้ค่าเทอม
--
-- ═══ อาการเดิม ═══
-- ระบบสอบซ่อม/เรียนปรับเกรด (0030 — regrade_session) เป็นแค่ "ที่บันทึกว่า
-- ใครมีสิทธิ์สอบซ่อมวิชาไหน" กับ "บันทึกผลสอบซ่อม" เท่านั้น ไม่แตะเรื่อง
-- เงินเลยสักจุด แม้จะมีคอลัมน์ `regrade_session_course.fee_amount` เตรียม
-- ไว้ตั้งแต่ต้นก็ตาม — ไม่เคยมีอะไรอ่านค่านั้นไปทำอะไรต่อ (รูปเดียวกับ
-- `take_usage_snapshot()` ในบทเรียนของโปรเจกต์นี้ คือของที่ประกาศเจตนา
-- ไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้นจริง)
--
-- ส่วน "ลงทะเบียนเรียนซ้ำ" ตัวจริง (สร้าง enrollment ใหม่ที่ attempt_no > 1
-- ผ่าน register_courses()) ก็ไม่มี fee logic เช่นกัน — เรียนซ้ำได้ฟรี
-- เหมือนลงทะเบียนปกติทุกประการ
--
-- ═══ ทำไมไม่ต่อกับตาราง invoice/invoice_line ที่มีอยู่แล้ว ═══
-- `invoice` มี `unique (student_id, term_id)` บังคับไว้ว่านักศึกษาหนึ่งคน
-- มีใบแจ้งหนี้ได้ใบเดียวต่อภาคเรียน — ผู้ใช้ต้องการให้ยอดซ่อม "ไม่รวมกับ
-- ค่าเทอม" อย่างชัดเจน ถ้าฝืนใส่เป็น invoice_line อีกบรรทัดในใบเดิมจะเป็น
-- การรวมกันอยู่ดี (แค่แยกบรรทัด) ส่วนถ้าจะแก้ constraint ให้ออกใบที่สองได้
-- จะกระทบฟังก์ชัน/รายงานที่สมมติว่านักศึกษาหนึ่งคนมีใบแจ้งหนี้เดียวต่อภาค
-- อยู่หลายจุด (ยอดค้างชำระ, aging, holds) โดยไม่จำเป็น — ทำบัญชีแยกต่างหาก
-- (course_retake_charge) จึง "ไม่ปนกับค่าเทอม" ได้จริงตามตัวอักษร และไม่มี
-- ทางกระทบระบบใบแจ้งหนี้เดิมที่ผ่านการทดสอบมาแล้วเลยแม้แต่น้อย
--
-- ═══ ทำไมไม่เพิ่มค่าในตาราง enrollment_status ═══
-- enum นั้นใช้กว้างมากทั้งระบบ (เช็คชื่อ, กฎ 80%, การตัดเกรด, รายงาน) —
-- เพิ่มค่า "รอชำระเงิน" เข้าไปแปลว่าทุกจุดที่ยังไม่รู้จักค่าใหม่ต้องถูกไล่
-- ตรวจใหม่ทั้งหมดว่าจะเผลอนับรวมหรือเผลอตกหล่นไหม ทั้งที่สิ่งที่ต้องการ
-- จริง ๆ แคบกว่านั้นมาก คือ "ซ่อนจากสมุดคะแนนจนกว่าจะจ่าย" อย่างเดียว —
-- เก็บสถานะไว้ในตาราง course_retake_charge ของตัวเอง แล้วให้สมุดคะแนน
-- (จุดเดียวที่ต้องกรอง) join มาเช็คแทน ปลอดภัยกว่าและง่ายต่อการอ่านย้อนหลัง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- อัตราค่าซ่อมต่อหน่วยกิต — ตั้งค่าระดับสถานศึกษา (แบบเดียวกับ
-- behavior_policy/risk_policy ใน 0011) ไม่ใช่ระดับหลักสูตร/ระดับชั้น
-- เพราะค่าซ่อมทางปฏิบัติของวิทยาลัยอาชีวศึกษาเอกชนส่วนใหญ่เป็นอัตราเดียว
-- ทั้งวิทยาลัย ไม่ได้แยกตามสาขา — เพิ่มความซับซ้อนตอนยังไม่มีใครขอ
-- ผิดหลัก YAGNI ของโปรเจกต์นี้
-- ───────────────────────────────────────────────────────────────────
create table retake_fee_policy (
  institution_id  uuid primary key references institution on delete cascade,
  fee_per_credit  numeric(8,2) not null check (fee_per_credit >= 0),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references person on delete set null
);

comment on table retake_fee_policy is
  'อัตราค่าซ่อมต่อหน่วยกิต — ไม่มีแถวแปลว่ายังไม่ได้ตั้งค่า charge_retake_fee() จะปฏิเสธจนกว่าจะตั้ง';

alter table retake_fee_policy enable row level security;
alter table retake_fee_policy force row level security;

create policy tenant_isolation on retake_fee_policy
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy retake_fee_policy_write on retake_fee_policy
  as restrictive for insert
  with check (current_app_role() = any (array['finance','registrar','director','admin']));
create policy retake_fee_policy_update on retake_fee_policy
  as restrictive for update
  using (current_app_role() = any (array['finance','registrar','director','admin']))
  with check (current_app_role() = any (array['finance','registrar','director','admin']));
create policy retake_fee_policy_delete on retake_fee_policy
  as restrictive for delete
  using (current_app_role() = any (array['finance','registrar','director','admin']));

-- ───────────────────────────────────────────────────────────────────
-- ยอดค่าซ่อมของการลงทะเบียนซ่อมแต่ละรายการ
-- ───────────────────────────────────────────────────────────────────
create type retake_charge_status as enum ('pending', 'paid', 'waived');

create table course_retake_charge (
  id              uuid primary key default gen_random_uuid(),
  institution_id  uuid not null references institution on delete restrict,
  enrollment_id   uuid not null unique references enrollment on delete cascade,
  student_id      uuid not null references student on delete restrict,
  credits         numeric(3,1) not null check (credits > 0),
  rate_per_credit numeric(8,2) not null check (rate_per_credit >= 0),
  amount          numeric(10,2) not null check (amount >= 0),
  status          retake_charge_status not null default 'pending',
  paid_at         timestamptz,
  paid_by         uuid references person on delete set null,
  method          text,
  note            text,
  created_by      uuid not null references person on delete restrict,
  created_at      timestamptz not null default now()
);
create index on course_retake_charge (student_id);
create index on course_retake_charge (status) where status = 'pending';

comment on table course_retake_charge is
  'ยอดค่าซ่อมรายวิชา แยกจาก invoice/invoice_line ของค่าเทอมโดยตั้งใจ (ดูคอมเมนต์บนสุดของไฟล์นี้) — ตัดสินใจว่าเป็นการลงทะเบียนซ่อมที่ต้องเก็บเงินหรือไม่อยู่ที่ผู้เรียก charge_retake_fee() ไม่ใช่การเดาจากข้อมูล';
comment on column course_retake_charge.enrollment_id is
  'หนึ่งรายการลงทะเบียน (attempt) มีค่าซ่อมได้รายการเดียว — ถอนแล้วลงใหม่ได้ enrollment ใหม่ จึงคิดค่าซ่อมใหม่ได้ตามจริง';

alter table course_retake_charge enable row level security;
alter table course_retake_charge force row level security;

create policy tenant_isolation on course_retake_charge
  using (student_institution(course_retake_charge.student_id) = current_institution_id())
  with check (student_institution(course_retake_charge.student_id) = current_institution_id());

/*
 * อ่านได้กว้าง (รวมเจ้าตัวและผู้ปกครองที่ยืนยันแล้ว — ต้องรู้ว่าตัวเองค้าง
 * ค่าซ่อมอยู่เท่าไร) เขียน/แก้ไขแคบกว่ามาก
 */
create policy retake_charge_read on course_retake_charge
  as restrictive
  using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = course_retake_charge.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  );

create policy retake_charge_insert on course_retake_charge
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','director','admin']));

create policy retake_charge_update on course_retake_charge
  as restrictive for update
  using (current_app_role() = any (array['finance','registrar','director','admin']))
  with check (current_app_role() = any (array['finance','registrar','director','admin']));

create policy retake_charge_delete on course_retake_charge
  as restrictive for delete
  using (current_app_role() = any (array['finance','director','admin']));

-- ───────────────────────────────────────────────────────────────────
-- ออกยอดค่าซ่อม — เรียกทีหลังจาก register_courses()/register_courses_bulk()
-- สร้าง enrollment ไปแล้ว ไม่ยุ่งกับการสร้าง enrollment เอง เพื่อไม่ต้อง
-- คัดลอกตรรกะการลงทะเบียนที่ทดสอบไว้แล้วมาเขียนซ้ำ
-- ───────────────────────────────────────────────────────────────────
create or replace function charge_retake_fee(p_enrollment_id uuid)
returns course_retake_charge language plpgsql as $$
declare
  v_inst    uuid;
  v_student uuid;
  v_credits numeric(3,1);
  v_rate    numeric(8,2);
  v_row     course_retake_charge;
begin
  select e.student_id, c.credits, student_institution(e.student_id)
    into v_student, v_credits, v_inst
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join course c on c.id = cs.course_id
   where e.id = p_enrollment_id;

  if v_student is null then
    raise exception 'ไม่พบการลงทะเบียนที่ระบุ';
  end if;

  select fee_per_credit into v_rate
    from retake_fee_policy where institution_id = v_inst;
  if v_rate is null then
    raise exception 'ยังไม่ได้ตั้งอัตราค่าซ่อมต่อหน่วยกิต — ตั้งค่าที่งานการเงินก่อน'
      using errcode = 'check_violation';
  end if;

  insert into course_retake_charge
    (institution_id, enrollment_id, student_id, credits, rate_per_credit, amount, created_by)
  values
    (v_inst, p_enrollment_id, v_student, v_credits, v_rate, v_credits * v_rate, current_actor_id())
  returning * into v_row;

  return v_row;
end $$;

comment on function charge_retake_fee(uuid) is
  'ออกยอดค่าซ่อมของการลงทะเบียนหนึ่งรายการ — จำนวนเงิน = หน่วยกิตของวิชา × อัตราที่ตั้งไว้ใน retake_fee_policy';

-- ───────────────────────────────────────────────────────────────────
-- ยืนยันการชำระ / ยกเว้นค่าซ่อม
-- ───────────────────────────────────────────────────────────────────
create or replace function confirm_retake_payment(p_charge_id uuid, p_method text, p_note text default null)
returns course_retake_charge language plpgsql as $$
declare v_row course_retake_charge;
begin
  update course_retake_charge
     set status = 'paid', paid_at = now(), paid_by = current_actor_id(),
         method = p_method, note = coalesce(p_note, note)
   where id = p_charge_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ไม่พบรายการค่าซ่อมที่รอชำระ หรือรายการนี้ถูกจัดการไปแล้ว'
      using errcode = 'check_violation';
  end if;
  return v_row;
end $$;

create or replace function waive_retake_fee(p_charge_id uuid, p_note text)
returns course_retake_charge language plpgsql as $$
declare v_row course_retake_charge;
begin
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'ต้องระบุเหตุผลที่ยกเว้นค่าซ่อม';
  end if;
  update course_retake_charge
     set status = 'waived', paid_at = now(), paid_by = current_actor_id(), note = p_note
   where id = p_charge_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ไม่พบรายการค่าซ่อมที่รอชำระ หรือรายการนี้ถูกจัดการไปแล้ว'
      using errcode = 'check_violation';
  end if;
  return v_row;
end $$;

/*
 * ─── ทำไมต้อง security definer ───
 * ครูไม่อยู่ใน is_institution_wide_role() จึงมองไม่เห็นแถวใน
 * course_retake_charge เลยตามนโยบาย retake_charge_read (ถูกต้องแล้ว —
 * ครูไม่ควรเห็นยอดเงิน/สถานะการชำระของใคร) แต่สมุดคะแนนต้องอาศัย "มีค่าซ่อม
 * ค้างชำระอยู่ไหม" มาตัดสินว่าจะซ่อนชื่อหรือไม่ ถ้า query จากบริบทครูตรง ๆ
 * แบบ `not exists (select ... from course_retake_charge ...)` นโยบาย RLS
 * จะกรองแถวทิ้งไปก่อนเช็คเงื่อนไขเสมอ ผลคือ not exists เป็นจริงเสมอไม่ว่า
 * จะค้างชำระจริงหรือไม่ — สมุดคะแนนจะไม่ซ่อนใครเลยสักคน (กับดักเดียวกับ
 * ที่ทำให้ต้องมี student_institution()/actor_taught_student_ids() ใน 0012
 * และ 0056 คือฟังก์ชันที่ policy อ้างถึงต้องข้าม RLS ของตารางที่มันอ่าน)
 * ฟังก์ชันนี้คืนแค่ boolean ไม่คืนยอดเงินหรือรายละเอียดอื่นใด จึงไม่เปิด
 * ช่องให้ครูเห็นข้อมูลการเงินที่ไม่ควรเห็น
 */
create or replace function enrollment_has_pending_retake_charge(p_enrollment_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from course_retake_charge
     where enrollment_id = p_enrollment_id and status = 'pending'
  )
$$;

revoke all on function enrollment_has_pending_retake_charge(uuid) from public;
grant execute on function enrollment_has_pending_retake_charge(uuid) to app_runtime;

comment on function enrollment_has_pending_retake_charge(uuid) is
  'true = มีค่าซ่อมค้างชำระ — security definer เพราะครูมองไม่เห็นแถว course_retake_charge เอง (ดูคอมเมนต์บนฟังก์ชันนี้)';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ซ่อนจากสมุดคะแนนจนกว่าจะชำระ (หรือยกเว้น)
--
-- แก้เฉพาะจุดเดียวที่ดึงรายชื่อขึ้นสมุดคะแนน — แถวที่มีค่าซ่อมค้างสถานะ
-- 'pending' จะไม่โผล่ในรายชื่อ แต่ enrollment ยังอยู่ครบ (สถานะยังเป็น
-- 'enrolled' ตามเดิม) จุดอื่นที่อ่าน enrollment (เช็คชื่อ ใบรายชื่อ ฯลฯ)
-- จึงไม่ถูกกระทบ — ตั้งใจให้กระทบแค่ "มองเห็นในสมุดคะแนน" ตามที่ขอเท่านั้น
-- ═══════════════════════════════════════════════════════════════════

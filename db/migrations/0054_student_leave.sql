-- ═══════════════════════════════════════════════════════════════════
-- 0054 — การลาของนักศึกษา
--
-- ก่อนไฟล์นี้ ระบบมี `attendance_status` ที่มี 'leave_sick'/'leave_personal'
-- และ `attendance_source` ที่มี 'guardian_leave' มาตั้งแต่ 0005 — แต่
-- **ไม่มีที่ให้ยื่นใบลา** ทางเดียวที่การลาจะเข้าระบบได้คือครูกดเลือกสถานะนั้น
-- ตอนเช็คชื่อ ซึ่งแปลว่า
--   · ใบลาที่ยื่นล่วงหน้าไม่มีที่เก็บ ครูต้องจำเอง
--   · ใบรับรองแพทย์ที่มาทีหลังแก้ย้อนหลังไม่ได้เป็นระบบ ต้องไล่บอกครูทีละคน
--   · ไม่มีใครตอบได้ว่านักศึกษาคนหนึ่งลาไปกี่วันในภาคเรียน
--
-- ═══ `can_approve_leave` มีมาตั้งแต่ 0002 และไม่เคยมีใครอ่าน ═══
-- คอลัมน์นี้อยู่ใน `student_guardian` ตั้งแต่ไฟล์ที่สองของโปรเจกต์ แต่ค้นทั้ง
-- repo แล้วไม่มีโค้ดไหนอ่านเลยสักบรรทัด — รูปเดียวกับ `take_usage_snapshot()`
-- (ข้อ 8) และ `generate_class_meetings()` คือคอลัมน์ประกาศเจตนาไว้ แล้วไม่มี
-- อะไรทำให้เจตนานั้นเกิดขึ้นจริง ไฟล์นี้ทำให้มันมีความหมาย — ผู้ปกครองที่ถูก
-- ติ๊กช่องนี้ยื่นใบลาแทนบุตรหลานได้ และรับรองใบลาที่นักศึกษายื่นเองได้
--
-- ═══ ทำไมการรับรองของผู้ปกครองไม่ใช่**เงื่อนไข**ของการอนุมัติ ═══
-- ถ้าบังคับว่าต้องมีผู้ปกครองรับรองก่อน เจ้าหน้าที่ถึงจะอนุมัติได้ นักศึกษา
-- ที่ยังไม่มีผู้ปกครองผูกบัญชี (ซึ่งเป็นสภาพเริ่มต้นของทุกคน) จะลาไม่ได้เลย
-- ตลอดไป — วงจรปิดแบบเดียวกับข้อ 6 ที่ผู้ดูแลเข้าระบบไม่ได้เพราะต้องตั้ง MFA
-- ก่อน แต่เส้นทางตั้ง MFA ก็ต้องล็อกอินก่อน จึงเก็บเป็น**ข้อเท็จจริงที่บันทึกไว้**
-- ให้เจ้าหน้าที่เห็นแล้วตัดสินใจเอง ไม่ใช่ประตูที่ล็อกได้
--
-- ═══ ทำไมการอนุมัติต้องแก้ `attendance_record` จริง ═══
-- ถ้าใบลาเป็นแค่กระดาษในระบบที่ไม่แตะเวลาเรียน กฎ 80% จะยังตัดสิทธิ์คนที่
-- ลาป่วยโดยมีใบรับรองแพทย์อยู่ดี — ใบลาที่ไม่มีผลคือใบลาที่ไม่มีประโยชน์
-- แต่การแก้ต้องมีขอบเขตชัดสามข้อ
--   1. แตะได้เฉพาะแถวที่ยัง**ไม่มีการเช็คชื่อ** หรือที่เช็คไว้ว่า `absent`
--      — `present`/`late` คือครูเห็นตัวจริง ใบลาไม่มีสิทธิ์ลบล้างสิ่งที่เกิดขึ้น
--   2. ทุกแถวที่ถูกแก้ถูกบันทึกไว้ใน `student_leave_applied` พร้อมค่าเดิม
--      การยกเลิกใบลาจึงคืนค่าเดิมได้ตรงแถว ไม่ใช่เดาว่าน่าจะเป็น absent
--   3. `source` เป็น 'guardian_leave' และ `recorded_by` เป็นผู้อนุมัติ
--      — หลักฐานต้องชี้คนที่ทำจริง ไม่ใช่ชี้ครูที่ไม่ได้กด (บทเรียนข้อ 5)
--
-- ═══ ใครอนุมัติได้ ═══
-- งานทะเบียน · งานปกครองและแนะแนว · ผู้อำนวยการ · ผู้ดูแล
-- **ไม่รวมฝ่ายวิชาการและการเงิน** ทั้งที่เป็น is_institution_wide_role()
-- เพราะการลาไม่ใช่งานของสองฝ่ายนั้น — หลักเดียวกับ 0053
-- ครูที่ปรึกษา **เห็นใบลาของเด็กในที่ปรึกษาตัวเองแต่ยังอนุมัติไม่ได้**
-- เพราะการอนุมัติเขียน `attendance_record` ของกลุ่มเรียนที่ตัวเองไม่ได้สอน
-- ซึ่ง RLS ของ 0039 ปฏิเสธ ผลจะเป็นการอนุมัติที่มีผลแค่บางวิชา — แย่กว่า
-- อนุมัติไม่ได้เลย เพราะไม่มีอะไรฟ้องว่ามันไม่ครบ
-- (การให้ครูที่ปรึกษา "เสนอความเห็น" แล้วงานปกครองอนุมัติ เป็นขั้นที่เพิ่ม
--  ทีหลังได้โดยไม่ต้องแก้ของเดิม — ยังไม่ทำเพราะยังไม่มีใครขอ)
--
-- ═══ ห้ามอนุมัติใบลาของตัวเองหรือของบุตรหลาน ═══
-- เงื่อนไขคือ **ผู้อนุมัติต้องไม่ใช่เจ้าของใบ** ไม่ใช่ "ต้องไม่ใช่คนที่กรอก"
-- ความต่างนี้สำคัญมาก — งานทะเบียนรับใบลาที่เป็นกระดาษมาแล้วพิมพ์เข้าระบบ
-- คือเส้นทางปกติที่สุด ถ้าห้าม "คนกรอกอนุมัติ" เจ้าหน้าที่จะบันทึกใบลาแล้ว
-- อนุมัติไม่ได้เลยสักใบ ต้องรอคนที่สองมากดทุกครั้ง ซึ่งวิทยาลัยเล็กที่มี
-- เจ้าหน้าที่ทะเบียนคนเดียวจะใช้ไม่ได้ทั้งฟีเจอร์ (วงจรปิดแบบเดียวกับข้อ 6
-- ที่ผู้ดูแลตั้ง MFA ไม่ได้เพราะต้องล็อกอินก่อน — เจอตอนกดปุ่มจริงบนหน้าจอ
-- ไม่ใช่ตอนเขียนเทสต์ เพราะเทสต์ยื่นด้วยบัญชีนักศึกษาซึ่งเป็นทางที่ต่างกัน)
--
-- สิ่งที่ต้องกันจริงคือคนที่**ได้ประโยชน์**จากใบนั้น — ตัวนักศึกษาเอง และ
-- ผู้ปกครองที่ยืนยันตัวตนแล้ว (เจ้าหน้าที่ที่เป็นผู้ปกครองของนักศึกษาใน
-- วิทยาลัยตัวเองจึงอนุมัติให้ลูกไม่ได้) ซึ่งตรงกับชุดที่ `actor_student_ids()`
-- คืนอยู่แล้วพอดี
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ชนิดข้อมูล
-- ───────────────────────────────────────────────────────────────────
do $$ begin
  create type student_leave_kind as enum ('sick', 'personal', 'activity');
exception when duplicate_object then null; end $$;

comment on type student_leave_kind is
  'activity = ไปราชการหรือทำกิจกรรมของวิทยาลัย ซึ่งไม่ใช่การลาของตัวนักศึกษาเอง แต่เข้าทางเดียวกันเพราะผลต่อเวลาเรียนเหมือนกัน';

do $$ begin
  create type student_leave_status as enum ('submitted', 'approved', 'rejected', 'cancelled');
exception when duplicate_object then null; end $$;

-- ───────────────────────────────────────────────────────────────────
-- ใบลา
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_leave (
  id               uuid primary key default gen_random_uuid(),
  institution_id   uuid not null references institution(id) on delete restrict,
  student_id       uuid not null references student(id) on delete cascade,
  kind             student_leave_kind not null,
  from_date        date not null,
  to_date          date not null,
  reason           text not null,
  /*
   * ระบบไฟล์แนบยังไม่มี (ต้องออกแบบที่เก็บและการจำกัดขนาด/ชนิดไฟล์แยก)
   * ช่องนี้จึงเก็บ**ข้อความ**ว่าเอกสารประกอบคืออะไรและอยู่ที่ใคร เช่น
   * "ใบรับรองแพทย์ รพ.สวนดอก เลขที่ 2569/1188 ส่งตัวจริงที่งานปกครอง"
   * ดีกว่าไม่มีที่ให้บันทึกเลยจนไปอยู่ในกระดาษที่หายได้
   */
  evidence_note    text,
  status           student_leave_status not null default 'submitted',

  requested_by     uuid references person(id) on delete restrict,
  requested_at     timestamptz not null default now(),

  -- การรับรองของผู้ปกครอง — เป็นข้อเท็จจริงที่บันทึกไว้ ไม่ใช่เงื่อนไข
  guardian_ack_by  uuid references person(id) on delete restrict,
  guardian_ack_at  timestamptz,

  decided_by       uuid references person(id) on delete restrict,
  decided_at       timestamptz,
  decision_note    text,

  -- จำนวนคาบที่ถูกปรับจริงตอนอนุมัติ — ศูนย์แปลว่าไม่มีคาบเรียนในช่วงนั้น
  -- หรือครูเช็คไปแล้วว่ามาเรียน ซึ่งเจ้าหน้าที่ต้องเห็นความต่าง
  applied_periods  integer not null default 0 check (applied_periods >= 0),

  created_at       timestamptz not null default now(),

  check (to_date >= from_date),
  check (from_date >= date '1900-01-01'),
  -- ตัดสินแล้วต้องรู้ว่าใครและเมื่อไร — ครบทั้งคู่หรือไม่มีเลย
  check ((decided_by is null) = (decided_at is null)),
  check ((guardian_ack_by is null) = (guardian_ack_at is null)),
  check (status in ('submitted', 'cancelled') or decided_at is not null)
);

create index if not exists student_leave_student on student_leave (student_id, from_date desc);
create index if not exists student_leave_pending on student_leave (institution_id, status)
  where status = 'submitted';

comment on table student_leave is
  'ใบลาของนักศึกษา — อนุมัติแล้วมีผลกับ attendance_record จริง มิฉะนั้นกฎเวลาเรียน 80% จะยังตัดสิทธิ์คนที่ลาถูกต้อง';
comment on column student_leave.applied_periods is
  'จำนวนคาบที่ถูกปรับตอนอนุมัติ — 0 แปลว่าไม่มีคาบในช่วงนั้นหรือครูเช็คว่ามาเรียนแล้ว ไม่ใช่ว่าอนุมัติไม่สำเร็จ';

-- ───────────────────────────────────────────────────────────────────
-- แถวเวลาเรียนที่ใบลาไปแก้ พร้อมค่าเดิม
--
-- มีตารางนี้เพราะการยกเลิกใบลาต้องคืนค่าเดิม**ตรงแถว** ถ้าเดาว่า "น่าจะเป็น
-- absent" จะไปทับกรณีที่เดิมไม่มีแถวเลย (ครูยังไม่ได้เช็ค) แล้วนักศึกษา
-- จะกลายเป็นขาดเรียนจากการยกเลิกใบลา ทั้งที่ไม่เคยมีใครบอกว่าขาด
-- ───────────────────────────────────────────────────────────────────
create table if not exists student_leave_applied (
  leave_id             uuid not null references student_leave(id) on delete cascade,
  attendance_record_id uuid not null references attendance_record(id) on delete cascade,
  previous_status      attendance_status,   -- null = เดิมไม่มีแถว
  periods              smallint not null default 1,
  primary key (leave_id, attendance_record_id)
);

comment on column student_leave_applied.previous_status is
  'null แปลว่าเดิมไม่มีแถวเช็คชื่อเลย การยกเลิกจึงต้องลบแถวทิ้ง ไม่ใช่ตั้งเป็น absent';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ตรรกะ
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * นักศึกษาที่ผู้ใช้ปัจจุบันยื่นและรับรองใบลาแทนได้
 *
 * security definer เพราะอ่าน `student_guardian` ซึ่งมีนโยบายของตัวเอง
 * และนโยบายของ student_leave เองก็จะอ้างฟังก์ชันนี้ — เรียกตรงจะวนกลับ
 */
create or replace function actor_leave_guardian_students()
returns setof uuid language sql stable security definer set search_path = public as $$
  select sg.student_id
    from student_guardian sg
   where sg.person_id = current_actor_id()
     and sg.verified_at is not null
     and sg.can_approve_leave
$$;

comment on function actor_leave_guardian_students() is
  'บุตรหลานที่ผู้ใช้ปัจจุบันรับรองการลาแทนได้ — ใช้ can_approve_leave ที่มีมาตั้งแต่ 0002 และไม่เคยมีใครอ่าน';

/* บทบาทที่อนุมัติใบลาได้ — แคบกว่า is_institution_wide_role() โดยตั้งใจ */
create or replace function may_decide_student_leave()
returns boolean language sql stable as $$
  select current_app_role() in ('registrar', 'student_affairs', 'director', 'admin')
$$;

-- ───────────────────────────────────────────────────────────────────
-- แปลงชนิดการลาเป็นสถานะการเช็คชื่อ
-- ───────────────────────────────────────────────────────────────────
create or replace function leave_kind_to_attendance(p_kind student_leave_kind)
returns attendance_status language sql immutable as $$
  select case p_kind
           when 'sick'     then 'leave_sick'
           when 'personal' then 'leave_personal'
           when 'activity' then 'activity'
         end::attendance_status
$$;

-- ───────────────────────────────────────────────────────────────────
-- กฎของใบลา
--
-- อยู่ใน trigger ไม่ใช่ในนโยบาย RLS เพราะเงื่อนไขเป็นเรื่อง**ค่าในแถว**
-- (ใครยื่น ใครตัดสิน สถานะเดิมคืออะไร) ไม่ใช่เรื่องว่าแถวไหนมองเห็นได้
-- — บทเรียนเดียวกับ `grade_submission` ใน 0049
-- ───────────────────────────────────────────────────────────────────
create or replace function student_leave_guard() returns trigger
language plpgsql as $$
begin
  -- ปล่อยผ่านเมื่อไม่มีบริบทผู้ใช้ (superuser ตอนย้ายข้อมูลหรือ seed)
  -- บริบทที่ไม่มี app.role ก็ไม่มี app.institution_id นโยบาย RLS จึงปฏิเสธ
  -- ทุกแถวอยู่แล้ว การปล่อยผ่านตรงนี้จึงไม่เปิดช่องให้ใคร (หลักเดียวกับ 0042)
  if current_app_role() = 'none' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'submitted' then
      raise exception 'ใบลาที่สร้างใหม่ต้องมีสถานะ "ยื่นแล้ว" เท่านั้น';
    end if;
    if new.decided_by is not null or new.decided_at is not null then
      raise exception 'ใบลาที่สร้างใหม่ต้องยังไม่มีผู้อนุมัติ';
    end if;
    return new;
  end if;

  -- ── ต่อจากนี้เป็น UPDATE ──
  if old.status <> 'submitted' and new.status <> old.status
     and not (old.status = 'approved' and new.status = 'cancelled') then
    raise exception 'ใบลาที่ % แล้วเปลี่ยนสถานะไม่ได้อีก', old.status;
  end if;

  -- รายละเอียดของใบลาแก้ได้เฉพาะตอนที่ยังไม่ถูกตัดสิน มิฉะนั้นสิ่งที่
  -- เจ้าหน้าที่อนุมัติกับสิ่งที่อยู่ในระบบจะเป็นคนละใบกัน
  if old.status <> 'submitted'
     and (new.student_id <> old.student_id
          or new.kind      <> old.kind
          or new.from_date <> old.from_date
          or new.to_date   <> old.to_date) then
    raise exception 'ใบลาที่ตัดสินไปแล้วแก้รายละเอียดไม่ได้ — ต้องยกเลิกแล้วยื่นใหม่';
  end if;

  if new.status in ('approved', 'rejected') and old.status = 'submitted' then
    if not may_decide_student_leave() then
      raise exception 'อนุมัติใบลาได้เฉพาะงานทะเบียน งานปกครอง ผู้อำนวยการ และผู้ดูแลระบบ';
    end if;
    if new.decided_by is null then
      raise exception 'ต้องระบุผู้ตัดสินใบลา';
    end if;
    -- กันที่ "เจ้าของใบ" ไม่ใช่ที่ "คนกรอก" — งานทะเบียนพิมพ์ใบลาที่เป็น
    -- กระดาษเข้าระบบแล้วอนุมัติเองได้ตามปกติ เพราะไม่ได้เป็นผู้ได้ประโยชน์
    if new.student_id in (select actor_student_ids()) then
      raise exception 'อนุมัติใบลาของตัวเองหรือของบุตรหลานไม่ได้';
    end if;
  end if;

  -- ยกเลิกได้สองทาง — เจ้าของยกเลิกใบที่ยังไม่ถูกตัดสิน
  -- หรือเจ้าหน้าที่ยกเลิกใบที่อนุมัติไปแล้ว (ซึ่งคืนค่าเวลาเรียนให้ด้วย)
  if new.status = 'cancelled' and old.status = 'approved'
     and not may_decide_student_leave() then
    raise exception 'ยกเลิกใบลาที่อนุมัติแล้วได้เฉพาะเจ้าหน้าที่';
  end if;

  return new;
end $$;

drop trigger if exists student_leave_guard on student_leave;
create trigger student_leave_guard
  before insert or update on student_leave
  for each row execute function student_leave_guard();

-- ───────────────────────────────────────────────────────────────────
-- อนุมัติแล้วมีผลกับเวลาเรียนจริง
--
-- **ไม่ใช่ security definer โดยตั้งใจ** — ผู้เรียกต้องมีสิทธิ์เขียน
-- `attendance_record` อยู่แล้วตามนโยบายของ 0039 ซึ่งเป็นจริงกับสี่บทบาท
-- ที่อนุมัติใบลาได้พอดี ถ้าวันหนึ่งเปิดให้ครูที่ปรึกษาอนุมัติ คำสั่งนี้จะล้ม
-- ทันทีที่คาบแรกที่ตัวเองไม่ได้สอน — ซึ่งดีกว่าเงียบแล้วอนุมัติได้ครึ่งเดียว
-- ───────────────────────────────────────────────────────────────────
create or replace function decide_student_leave(
  p_leave_id uuid,
  p_approve  boolean,
  p_note     text default null
) returns table (
  leave_id        uuid,
  status          student_leave_status,
  applied_periods integer,
  skipped_present integer
) language plpgsql as $$
#variable_conflict use_column
declare
  v_leave   student_leave;
  v_status  attendance_status;
  v_applied integer := 0;
  v_skipped integer := 0;
  r         record;
  v_rec_id  uuid;
begin
  /*
   * ตรวจสิทธิ์**ก่อน**แตะอะไรทั้งสิ้น
   *
   * trigger `student_leave_guard` ตรวจซ้ำอยู่แล้ว แต่มันยิงตอน update
   * ซึ่งเป็นคำสั่ง**สุดท้าย**ของฟังก์ชันนี้ ถ้าพึ่งอย่างเดียว คนที่ไม่มีสิทธิ์
   * จะเดินผ่านการเขียน attendance_record ไปก่อนแล้วค่อยโดนปฏิเสธ —
   * ได้ผลถูกเพราะ rollback แต่ข้อความผิดพลาดจะเป็นเรื่อง RLS ของตารางอื่น
   * ที่อ่านแล้วไม่รู้ว่าปัญหาคืออะไร (เจอตอนเขียน TEST 236 ซึ่งผ่านด้วย
   * เหตุผลที่ผิด) และถ้าวันหนึ่งช่วงวันลาไม่มีคาบเรียนเลย จะไม่มีคำสั่งไหน
   * แตะ RLS เลยจนกว่าจะถึง update — ลำดับการตรวจจึงต้องไม่ขึ้นกับข้อมูล
   */
  if not may_decide_student_leave() then
    raise exception 'อนุมัติใบลาได้เฉพาะงานทะเบียน งานปกครอง ผู้อำนวยการ และผู้ดูแลระบบ';
  end if;

  select * into v_leave from student_leave where id = p_leave_id;
  if not found then
    raise exception 'ไม่พบใบลา หรือไม่มีสิทธิ์เข้าถึง';
  end if;
  if v_leave.status <> 'submitted' then
    raise exception 'ใบลานี้ถูกตัดสินไปแล้ว (สถานะ %)', v_leave.status;
  end if;
  -- เจ้าของใบอนุมัติเองไม่ได้ — actor_student_ids() คือตัวเองและบุตรหลาน
  -- ที่ยืนยันตัวตนแล้ว ซึ่งเป็นชุดคนที่ได้ประโยชน์จากใบนี้พอดี
  if v_leave.student_id in (select actor_student_ids()) then
    raise exception 'อนุมัติใบลาของตัวเองหรือของบุตรหลานไม่ได้';
  end if;

  if not p_approve then
    update student_leave
       set status = 'rejected', decided_by = current_actor_id(),
           decided_at = now(), decision_note = p_note
     where id = p_leave_id;
    return query select p_leave_id, 'rejected'::student_leave_status, 0, 0;
    return;
  end if;

  v_status := leave_kind_to_attendance(v_leave.kind);

  /*
   * อ่านคาบทั้งช่วงทีเดียวแล้ววนเขียน ไม่ใช่เรียกฟังก์ชันรายคาบ
   * ต้นทุนของคำสั่งในสคีมานี้อยู่ที่การวางแผน ซึ่งกางนโยบาย RLS ใหม่ทุกครั้ง
   */
  for r in
    select cm.id as meeting_id, e.id as enrollment_id, cm.period_count,
           ar.id as record_id, ar.status as current_status
      from enrollment e
      join class_meeting cm on cm.class_section_id = e.class_section_id
      left join attendance_record ar
             on ar.class_meeting_id = cm.id and ar.enrollment_id = e.id
     where e.student_id = v_leave.student_id
       and e.status = 'enrolled'
       and cm.meets_on between v_leave.from_date and v_leave.to_date
       and cm.status <> 'cancelled'
  loop
    -- ครูเห็นตัวจริงแล้ว ใบลาไม่มีสิทธิ์ลบล้างสิ่งที่เกิดขึ้น
    if r.current_status is not null and r.current_status <> 'absent' then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    if r.record_id is null then
      insert into attendance_record
        (class_meeting_id, enrollment_id, status, source, recorded_by, note)
      values (r.meeting_id, r.enrollment_id, v_status, 'guardian_leave',
              current_actor_id(), 'ใบลาเลขที่ ' || p_leave_id)
      returning id into v_rec_id;
    else
      update attendance_record
         set status = v_status, source = 'guardian_leave',
             recorded_by = current_actor_id(), recorded_at = now(),
             note = 'ใบลาเลขที่ ' || p_leave_id
       where id = r.record_id
      returning id into v_rec_id;
    end if;

    insert into student_leave_applied
      (leave_id, attendance_record_id, previous_status, periods)
    values (p_leave_id, v_rec_id, r.current_status, r.period_count)
    on conflict do nothing;

    v_applied := v_applied + r.period_count;
  end loop;

  update student_leave
     set status = 'approved', decided_by = current_actor_id(),
         decided_at = now(), decision_note = p_note,
         applied_periods = v_applied
   where id = p_leave_id;

  return query select p_leave_id, 'approved'::student_leave_status, v_applied, v_skipped;
end $$;

comment on function decide_student_leave(uuid, boolean, text) is
  'อนุมัติหรือไม่อนุมัติใบลา — อนุมัติแล้วปรับ attendance_record เฉพาะแถวที่ยังไม่มีหรือที่เป็น absent และเก็บค่าเดิมไว้ให้ยกเลิกคืนได้';

-- ───────────────────────────────────────────────────────────────────
-- ยกเลิกใบลาที่อนุมัติไปแล้ว — คืนค่าเวลาเรียนตรงแถว
-- ───────────────────────────────────────────────────────────────────
create or replace function cancel_student_leave(p_leave_id uuid, p_reason text)
returns table (leave_id uuid, reverted integer)
language plpgsql as $$
#variable_conflict use_column
declare
  v_leave    student_leave;
  v_reverted integer := 0;
  r          record;
begin
  select * into v_leave from student_leave where id = p_leave_id;
  if not found then
    raise exception 'ไม่พบใบลา หรือไม่มีสิทธิ์เข้าถึง';
  end if;
  if v_leave.status not in ('submitted', 'approved') then
    raise exception 'ใบลาสถานะ % ยกเลิกไม่ได้', v_leave.status;
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'ต้องระบุเหตุผลที่ยกเลิก';
  end if;

  for r in
    select attendance_record_id, previous_status
      from student_leave_applied where leave_id = p_leave_id
  loop
    if r.previous_status is null then
      -- เดิมไม่มีแถวเลย — ตั้งเป็น absent จะกลายเป็นการทำให้ขาดเรียน
      -- จากการยกเลิกใบลา ทั้งที่ไม่เคยมีใครบอกว่าขาด
      delete from attendance_record where id = r.attendance_record_id;
    else
      update attendance_record
         set status = r.previous_status, source = 'system',
             recorded_by = current_actor_id(), recorded_at = now(),
             note = 'คืนค่าเดิมจากการยกเลิกใบลา ' || p_leave_id
       where id = r.attendance_record_id;
    end if;
    v_reverted := v_reverted + 1;
  end loop;

  delete from student_leave_applied where leave_id = p_leave_id;

  update student_leave
     set status = 'cancelled',
         decision_note = coalesce(decision_note || ' · ', '') || 'ยกเลิก: ' || p_reason,
         applied_periods = 0
   where id = p_leave_id;

  return query select p_leave_id, v_reverted;
end $$;

comment on function cancel_student_leave(uuid, text) is
  'ยกเลิกใบลา — คืนค่าเวลาเรียนจากค่าที่เก็บไว้ตอนอนุมัติ แถวที่เดิมไม่มีจะถูกลบ ไม่ใช่ตั้งเป็นขาดเรียน';

-- ───────────────────────────────────────────────────────────────────
-- สรุปวันลาต่อภาคเรียน — คำถามที่ไม่มีใครตอบได้ก่อนมีไฟล์นี้
-- ───────────────────────────────────────────────────────────────────
-- security_invoker บังคับให้ view ใช้สิทธิ์ของคนเรียก ไม่ใช่ของเจ้าของ view
-- ถ้าไม่ตั้ง view จะกลายเป็นทางลัดข้าม RLS ทั้งหมด (TEST 41 บังคับทั้งสคีมา)
create or replace view v_student_leave_summary with (security_invoker = true) as
  select sl.institution_id,
         sl.student_id,
         sl.kind,
         count(*)                                      as requests,
         sum(sl.to_date - sl.from_date + 1)            as days,
         sum(sl.applied_periods)                       as periods
    from student_leave sl
   where sl.status = 'approved'
   group by sl.institution_id, sl.student_id, sl.kind;

comment on view v_student_leave_summary is
  'สรุปการลาที่อนุมัติแล้วรายคน — นับวันจากช่วงวันที่ ส่วนคาบนับจากที่ปรับเวลาเรียนได้จริง สองตัวเลขนี้ต่างกันได้เมื่อวันลาไม่มีคาบเรียน';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- Row-Level Security
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table student_leave enable row level security;
alter table student_leave force row level security;

create policy tenant_isolation on student_leave
  using (institution_id = current_institution_id());

/*
 * ─── ต้องแยกเป็น for select / insert / update / delete ───
 * นโยบาย restrictive แบบ `for all` กิน select ด้วย ซึ่งจะทำให้เงื่อนไข
 * "ต้องเป็นเจ้าหน้าที่ถึงจะอนุมัติได้" กลายเป็น "ถึงจะอ่านได้" โดยไม่มีอะไรฟ้อง
 * (บทเรียนจาก 0053 ที่ครูที่ปรึกษาอ่านไม่ได้ทั้งที่ฟังก์ชันตรวจสิทธิ์คืน true)
 */
create policy leave_read on student_leave
  as restrictive for select using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_advisee_ids())
  );

-- นักศึกษายื่นของตัวเองได้ · ผู้ปกครองที่ถูกติ๊ก can_approve_leave ยื่นแทนได้
-- · เจ้าหน้าที่ยื่นแทนได้ (ใบลาที่ส่งมาเป็นกระดาษ)
create policy leave_insert on student_leave
  as restrictive for insert with check (
    may_decide_student_leave()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_leave_guardian_students())
  );

/*
 * เจ้าของแก้ได้เฉพาะใบของตัวเอง และ trigger กันไม่ให้ตั้งสถานะเป็น approved
 * — นโยบายบอกว่า "แถวไหนแตะได้" ส่วน trigger บอกว่า "แตะแล้วกลายเป็นอะไรได้"
 * แยกกันเพราะ RLS เทียบค่าในแถวเดียวไม่ได้ว่าเปลี่ยนจากอะไรเป็นอะไร
 */
create policy leave_update on student_leave
  as restrictive for update
  using (
    may_decide_student_leave()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_leave_guardian_students())
  )
  with check (
    may_decide_student_leave()
    or student_id in (select actor_student_ids())
    or student_id in (select actor_leave_guardian_students())
  );

-- ใบลาที่ยื่นแล้วต้องไม่หายไปจากระบบ — ยกเลิกได้ ลบไม่ได้
-- (นโยบายนี้มีไว้ให้งานล้างข้อมูลของผู้ดูแลทำได้ ถ้าไม่มีเลยจะลบไม่ได้สักแถว
--  เพราะ force row level security มีผลกับเจ้าของตารางด้วย)
create policy leave_delete on student_leave
  as restrictive for delete using (current_app_role() = 'admin');

-- ─── student_leave_applied ─────────────────────────────────────────
alter table student_leave_applied enable row level security;
alter table student_leave_applied force row level security;

/*
 * ตารางนี้ไม่มี institution_id ของตัวเอง จึงเทียบผ่านใบลาแม่
 * **RLS ไม่ถ่ายทอดผ่านคีย์นอก** — ถ้าไม่เขียนนโยบายนี้ ตารางจะเปิดโล่ง
 */
create policy tenant_isolation on student_leave_applied
  using (exists (select 1 from student_leave sl
                  where sl.id = student_leave_applied.leave_id
                    and sl.institution_id = current_institution_id()));

create policy applied_write on student_leave_applied
  as restrictive for insert with check (may_decide_student_leave());

create policy applied_delete on student_leave_applied
  as restrictive for delete using (may_decide_student_leave());

commit;

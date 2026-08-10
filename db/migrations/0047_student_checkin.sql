-- ═══════════════════════════════════════════════════════════════════
-- 0047_student_checkin.sql
--
-- คำขอเช็คอินของนักศึกษา (A-05) — คนถูกเช็คไม่ใช่คนเขียนผล
--
-- ─── ข้อกำหนดที่ 0039 เขียนไว้ล่วงหน้า ───
-- migration 0039 ปิดช่องที่นักศึกษาแก้เวลาเรียนของตัวเองได้ และเขียนไว้ตรง ๆ
-- ว่าถ้าวันหน้าทำ A-05 ให้นักศึกษาเช็คอินเอง **ห้ามแก้ด้วยการเอาประโยค
-- actor_enrollment_ids() กลับเข้า with check** เพราะนั่นคือการเปิดช่องเดิมคืน
--
-- ทางที่ถูกคือตารางคำขอแยก ที่ครูยืนยันแล้วจึงกลายเป็น attendance_record
-- ไฟล์นี้ทำตามนั้น
--
-- ─── ทำไมคำขอไม่ใช่การเช็คชื่อ ───
-- แถวใน attendance_checkin ไม่มีผลกับกฎเวลาเรียน 80% เลยสักนิดจนกว่าครู
-- จะยืนยัน — นักศึกษาจึงกดได้ไม่จำกัดโดยไม่กระทบใคร และครูยังเป็นคนเดียว
-- ที่ตัดสินว่าใครมาเรียนจริง
--
-- ─── ทำไมเก็บพิกัดเป็นระยะห่าง ไม่ใช่พิกัดจริง ───
-- พิกัดของผู้เยาว์เป็นข้อมูลอ่อนไหวตาม PDPA และเก็บไว้ก็ตอบคำถามเดียว
-- ที่ระบบต้องการไม่ได้ดีไปกว่าระยะห่าง — "อยู่ในบริเวณวิทยาลัยไหม"
-- เก็บระยะห่างเป็นเมตรจึงพอ และย้อนกลับเป็นตำแหน่งบ้านใครไม่ได้
--
-- ─── ทำไมไม่บังคับพิกัด ───
-- โรงฝึกงานเป็นอาคารคอนกรีตหนาที่ GPS เข้าไม่ถึง ถ้าบังคับ นักศึกษาที่อยู่
-- ในห้องเรียนจริงจะเช็คอินไม่ได้ ส่วนคนที่อยากโกงก็ปลอมพิกัดได้อยู่ดี —
-- ค่านี้จึงเป็นข้อมูลประกอบให้ครูเห็น ไม่ใช่เงื่อนไขที่ระบบตัดสินเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

create type checkin_status as enum ('pending', 'accepted', 'rejected');

create table attendance_checkin (
  id               uuid           primary key default gen_random_uuid(),
  institution_id   uuid           not null references institution on delete restrict,
  class_meeting_id uuid           not null references class_meeting on delete cascade,
  enrollment_id    uuid           not null references enrollment on delete cascade,
  status           checkin_status not null default 'pending',

  -- ระยะห่างจากจุดที่วิทยาลัยกำหนด (เมตร) — null คือไม่มีสัญญาณหรือปฏิเสธ
  distance_m       integer        check (distance_m is null or distance_m >= 0),
  device_id        text,
  note             text,

  submitted_at     timestamptz    not null default now(),
  decided_at       timestamptz,
  decided_by       uuid           references staff on delete restrict,
  decision_note    text,

  -- กดซ้ำในคาบเดิมไม่สร้างแถวใหม่ — มิฉะนั้นครูจะเห็นคำขอสิบแถวของคนเดียว
  unique (class_meeting_id, enrollment_id)
);

comment on table attendance_checkin is
  'คำขอเช็คอินของนักศึกษา — ไม่มีผลกับกฎเวลาเรียนจนกว่าครูจะยืนยัน คนถูกเช็คต้องไม่ใช่คนเขียนผล';
comment on column attendance_checkin.distance_m is
  'ระยะห่างจากวิทยาลัยเป็นเมตร ไม่ใช่พิกัด — พิกัดของผู้เยาว์เป็นข้อมูลอ่อนไหวและเก็บไว้ก็ไม่ได้ตอบอะไรเพิ่ม';

create index attendance_checkin_pending_idx
  on attendance_checkin (class_meeting_id) where status = 'pending';

-- ───────────────────────────────────────────────────────────────────
-- นักศึกษาส่งคำขอเช็คอิน
--
-- ปฏิเสธคาบที่ปิดไปแล้วเพราะการเช็คอินย้อนหลังคือสิ่งที่มาตรการนี้กันอยู่
-- ───────────────────────────────────────────────────────────────────
create or replace function submit_checkin(
  p_class_meeting_id uuid,
  p_enrollment_id    uuid,
  p_distance_m       integer default null,
  p_device_id        text default null
) returns attendance_checkin
language plpgsql as $$
declare
  v_row    attendance_checkin;
  v_status text;
  v_inst   uuid;
begin
  select cm.status::text, cs.institution_id into v_status, v_inst
    from class_meeting cm
    join class_section cs on cs.id = cm.class_section_id
   where cm.id = p_class_meeting_id;

  if v_status is null then
    raise exception 'ไม่พบคาบเรียนนี้ หรือไม่มีสิทธิ์เข้าถึง';
  end if;
  if v_status <> 'scheduled' then
    raise exception 'คาบนี้ปิดไปแล้ว เช็คอินย้อนหลังไม่ได้ ติดต่อครูผู้สอน';
  end if;

  insert into attendance_checkin
    (institution_id, class_meeting_id, enrollment_id, distance_m, device_id)
  values (v_inst, p_class_meeting_id, p_enrollment_id, p_distance_m, p_device_id)
  on conflict (class_meeting_id, enrollment_id) do update
    set submitted_at = now(),
        distance_m   = excluded.distance_m,
        device_id    = excluded.device_id
    -- กดซ้ำหลังครูตัดสินไปแล้วไม่ล้างผลทิ้ง
    where attendance_checkin.status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'คำขอของคาบนี้ถูกตัดสินไปแล้ว ติดต่อครูผู้สอนถ้าไม่ถูกต้อง';
  end if;

  return v_row;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ครูยืนยันคำขอ — จุดเดียวที่คำขอกลายเป็นการเช็คชื่อจริง
--
-- เขียน attendance_record ให้ในบริบทของครูซึ่งมีสิทธิ์อยู่แล้วตาม 0039
-- ไม่ต้องใช้ security definer และไม่ต้องผ่อนนโยบายของ attendance_record เลย
-- ───────────────────────────────────────────────────────────────────
create or replace function decide_checkin(
  p_checkin_id uuid,
  p_accept     boolean,
  p_status     attendance_status default 'present',
  p_note       text default null
) returns attendance_checkin
language plpgsql as $$
declare
  v_row   attendance_checkin;
  v_staff uuid;
begin
  select st.id into v_staff
    from staff st where st.person_id = current_actor_id();

  update attendance_checkin
     set status        = case when p_accept then 'accepted' else 'rejected' end::checkin_status,
         decided_at    = now(),
         decided_by    = v_staff,
         decision_note = p_note
   where id = p_checkin_id and status = 'pending'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ไม่พบคำขอนี้ หรือถูกตัดสินไปแล้ว';
  end if;

  if p_accept then
    -- เขียนผลจริง ณ จุดนี้เท่านั้น ถ้ามีแถวอยู่แล้วถือว่าครูแก้ผลเดิม
    insert into attendance_record (class_meeting_id, enrollment_id, status, note)
    values (v_row.class_meeting_id, v_row.enrollment_id, p_status,
            coalesce(p_note, 'ยืนยันจากคำขอเช็คอินของนักศึกษา'))
    on conflict (class_meeting_id, enrollment_id) do update
      set status = excluded.status, note = excluded.note;
  end if;

  return v_row;
end $$;

comment on function decide_checkin(uuid, boolean, attendance_status, text) is
  'ครูยืนยันหรือปฏิเสธคำขอเช็คอิน — จุดเดียวที่คำขอกลายเป็นเวลาเรียนจริง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- นักศึกษาสร้างคำขอของตัวเองได้ (นี่คือทั้งหมดที่เขาทำได้) แต่ตัดสินไม่ได้
-- — เงื่อนไขคือแถวที่เขียนต้องมีสถานะ pending เสมอ
-- ───────────────────────────────────────────────────────────────────
alter table attendance_checkin enable row level security;
alter table attendance_checkin force  row level security;

create policy tenant_isolation on attendance_checkin
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy checkin_scope on attendance_checkin
  as restrictive
  using (
    is_institution_wide_role()
    or section_teacher_person_id(
         (select cm.class_section_id from class_meeting cm
           where cm.id = attendance_checkin.class_meeting_id)) = current_actor_id()
    or enrollment_id in (select actor_enrollment_ids())
  )
  with check (
    is_institution_wide_role()
    or section_teacher_person_id(
         (select cm.class_section_id from class_meeting cm
           where cm.id = attendance_checkin.class_meeting_id)) = current_actor_id()
    -- เจ้าของเขียนได้เฉพาะแถวที่ยังเป็นคำขอ — ตัดสินให้ตัวเองไม่ได้
    or (enrollment_id in (select actor_enrollment_ids()) and status = 'pending')
  );

create policy checkin_no_student_delete on attendance_checkin
  as restrictive for delete
  using (
    is_institution_wide_role()
    or section_teacher_person_id(
         (select cm.class_section_id from class_meeting cm
           where cm.id = attendance_checkin.class_meeting_id)) = current_actor_id()
  );

comment on policy checkin_scope on attendance_checkin is
  'นักศึกษาส่งคำขอของตัวเองได้เฉพาะสถานะ pending — ยืนยันเองไม่ได้ และลบคำขอทิ้งไม่ได้';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on attendance_checkin to app_runtime;
    grant execute on function submit_checkin(uuid, uuid, integer, text) to app_runtime;
    grant execute on function decide_checkin(uuid, boolean, attendance_status, text)
      to app_runtime;
  end if;
end $$;

commit;

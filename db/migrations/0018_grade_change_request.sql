-- ═══════════════════════════════════════════════════════════════════
-- 0018_grade_change_request.sql
--
-- คำร้องแก้เกรดหลังล็อก — ทางเดียวที่แก้ผลการเรียนที่อนุมัติแล้วได้
--
-- ─── ทำไมต้องมีทางนี้ ───
-- migration 0016 ทำให้ผลการเรียนที่เดินครบสายอนุมัติแล้วแตะไม่ได้เลย
-- ซึ่งถูกต้อง แต่ความผิดพลาดเกิดขึ้นจริงเสมอ — กรอกคะแนนสลับคน
-- นักศึกษายื่นใบรับรองแพทย์ย้อนหลัง หรือ ม.ส. ที่แก้เสร็จแล้ว
-- ถ้าไม่มีทางแก้ที่ตรวจสอบได้ คนจะไปแก้ที่ฐานข้อมูลตรง ๆ แทน
-- ซึ่งแย่กว่ามาก เพราะไม่เหลือร่องรอยว่าใครแก้และเพราะอะไร
--
-- ─── dual control: ผู้อนุมัติสองคน และห้ามเป็นคนขอ ───
-- ตาราง grade_change_request มี constraint บังคับว่าผู้อนุมัติสองคน
-- ต้องเป็นคนละคนอยู่แล้ว แต่ constraint นั้นไม่ได้ห้าม **คนขอ**
-- มาอนุมัติคำร้องของตัวเอง ซึ่งทำให้ dual control ไม่มีความหมาย
-- เพราะครูคนเดียวขอเองแล้วกดอนุมัติหนึ่งในสองช่องเองได้
-- ฟังก์ชันในไฟล์นี้จึงปิดช่องนั้นอีกชั้น
--
-- ─── ทำไมลงมือแก้อัตโนมัติเมื่อครบสองคน ───
-- ถ้าแยกขั้น "อนุมัติแล้ว" กับ "ลงมือแก้" ออกจากกัน จะเกิดสถานะค้าง
-- ที่อนุมัติครบแล้วแต่ไม่มีใครกดใช้ แล้วเกรดในระบบยังเป็นค่าเดิม
-- ทั้งที่ทุกคนเข้าใจว่าแก้ไปแล้ว — เป็นความไม่ตรงกันที่ตรวจไม่เจอจนออกเอกสาร
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ยื่นคำร้อง
-- ───────────────────────────────────────────────────────────────────
create or replace function request_grade_change(
  p_enrollment_id      uuid,
  p_to_grade_symbol_id uuid,
  p_reason             text,
  p_to_raw_score       numeric default null,
  p_document_no        text    default null
) returns uuid
language plpgsql as $$
declare
  v_current  enrollment_result%rowtype;
  v_stage    submission_stage;
  v_scheme   uuid;
  v_id       uuid;
begin
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'ต้องระบุเหตุผลของการแก้เกรด';
  end if;

  -- คำร้องที่ไม่รู้ว่าใครยื่นตรวจสอบย้อนหลังไม่ได้ และทำให้ dual control
  -- พังทันที เพราะกฎ "ผู้ยื่นอนุมัติเองไม่ได้" ต้องรู้ว่าผู้ยื่นคือใคร
  if current_actor_id() is null then
    raise exception 'การยื่นคำร้องแก้เกรดต้องระบุตัวผู้ยื่น';
  end if;

  select * into v_current
    from enrollment_result er
   where er.enrollment_id = p_enrollment_id and er.superseded_by is null;

  if not found then
    raise exception 'การลงทะเบียนนี้ยังไม่มีผลการเรียน จึงยังไม่มีอะไรให้แก้';
  end if;

  -- ยังไม่ล็อกก็ไม่ต้องใช้คำร้อง ให้ผู้อนุมัติตีกลับแล้วครูส่งใหม่ ซึ่งเบากว่ามาก
  select gs.stage into v_stage
    from grade_submission gs
    join enrollment e on e.class_section_id = gs.class_section_id
   where e.id = p_enrollment_id;

  if v_stage is distinct from 'locked' then
    raise exception
      'รอบส่งเกรดของกลุ่มนี้ยังไม่ล็อก (ขั้น %) ให้ผู้อนุมัติตีกลับแล้วครูส่งใหม่แทนการยื่นคำร้อง',
      coalesce(v_stage::text, 'ยังไม่ได้ส่ง');
  end if;

  if exists (select 1 from grade_change_request
              where enrollment_id = p_enrollment_id and status = 'pending') then
    raise exception 'มีคำร้องแก้เกรดของการลงทะเบียนนี้ค้างอยู่แล้ว ต้องดำเนินการให้เสร็จก่อน';
  end if;

  -- ไม่ส่งคะแนนมาแปลว่าไม่ขอแก้คะแนน ถ้าสัญลักษณ์ก็เท่าเดิมด้วยก็ไม่มีอะไรต้องแก้
  if p_to_grade_symbol_id = v_current.grade_symbol_id
     and (p_to_raw_score is null or p_to_raw_score = v_current.raw_score) then
    raise exception 'ผลการเรียนที่ขอแก้เหมือนเดิมทุกอย่าง ไม่มีอะไรต้องแก้';
  end if;

  -- สัญลักษณ์ที่ขอต้องอยู่ในระเบียบวัดผลของหลักสูตรเดียวกัน
  -- ไม่งั้นจะได้เกรดของ ปวส. ไปโผล่ในผลการเรียน ปวช.
  select cv.grade_scheme_id into v_scheme
    from enrollment e
    join class_section cs      on cs.id = e.class_section_id
    join curriculum_version cv on cv.id = cs.curriculum_version_id
   where e.id = p_enrollment_id;

  if not exists (select 1 from grade_symbol
                  where id = p_to_grade_symbol_id and grade_scheme_id = v_scheme) then
    raise exception 'สัญลักษณ์ผลการเรียนที่ขอไม่ได้อยู่ในระเบียบวัดผลของหลักสูตรนี้';
  end if;

  insert into grade_change_request
    (enrollment_id, from_result_id, to_grade_symbol_id, to_raw_score,
     reason, document_no, requested_by)
  values
    (p_enrollment_id, v_current.id, p_to_grade_symbol_id, p_to_raw_score,
     btrim(p_reason), p_document_no, current_actor_id())
  returning id into v_id;

  return v_id;
end $$;

comment on function request_grade_change(uuid, uuid, text, numeric, text) is
  'ยื่นคำร้องแก้เกรดที่ล็อกแล้ว — ต้องมีเหตุผลเสมอ และใช้ได้เฉพาะเมื่อรอบส่งเกรดล็อกไปแล้ว';

-- ───────────────────────────────────────────────────────────────────
-- ลงมือแก้ — เรียกจาก approve_grade_change() เมื่อครบสองคนเท่านั้น
--
-- ออก revision ใหม่แล้วชี้แถวเดิมมาหา ไม่ใช่แก้ทับ เหมือนตอนส่งเกรดใหม่
-- attendance_pct ยกมาจากแถวเดิมโดยไม่คำนวณใหม่ เพราะเป็นค่าที่ตรึงไว้
-- ณ เวลาตัดเกรด ถ้าคำนวณใหม่ เอกสารที่ออกย้อนหลังจะไม่ตรงกับที่เคยออกไป
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_grade_change(p_request_id uuid)
returns uuid
language plpgsql as $$
declare
  v_req     grade_change_request%rowtype;
  v_current enrollment_result%rowtype;
  v_symbol  record;
  v_credits numeric;
  v_new_id  uuid;
begin
  select * into v_req from grade_change_request where id = p_request_id;
  if not found then
    raise exception 'ไม่พบคำร้อง % (หรือไม่มีสิทธิ์เข้าถึง)', p_request_id;
  end if;

  select * into v_current
    from enrollment_result where enrollment_id = v_req.enrollment_id and superseded_by is null;

  select gs.grade_point, gs.earns_credit, gs.symbol
    into v_symbol
    from grade_symbol gs where gs.id = v_req.to_grade_symbol_id;

  select co.credits into v_credits
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join course        co on co.id = cs.course_id
   where e.id = v_req.enrollment_id;

  v_new_id := gen_random_uuid();

  update enrollment_result
     set superseded_by = v_new_id
   where id = v_current.id;

  insert into enrollment_result (
    id, enrollment_id, submission_id, revision,
    raw_score, attendance_pct, grade_symbol_id, grade_point, credits_earned,
    computed_by, reason
  )
  values (
    v_new_id, v_req.enrollment_id, v_current.submission_id, v_current.revision + 1,
    coalesce(v_req.to_raw_score, v_current.raw_score),
    v_current.attendance_pct,
    v_req.to_grade_symbol_id, v_symbol.grade_point,
    case when v_symbol.earns_credit then v_credits else 0 end,
    current_actor_id(),
    format('แก้เกรดตามคำร้อง %s: %s',
           coalesce(v_req.document_no, p_request_id::text), v_req.reason)
  );

  update grade_change_request
     set status = 'applied', applied_result_id = v_new_id
   where id = p_request_id;

  return v_new_id;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- อนุมัติ — คนที่สองที่กดคือคนที่ทำให้การแก้มีผลจริง
-- ───────────────────────────────────────────────────────────────────
create or replace function approve_grade_change(p_request_id uuid)
returns change_request_status
language plpgsql as $$
declare
  v_req   grade_change_request%rowtype;
  v_actor uuid := current_actor_id();
begin
  if v_actor is null then
    raise exception 'การอนุมัติต้องระบุตัวผู้อนุมัติ';
  end if;

  select * into v_req from grade_change_request where id = p_request_id;
  if not found then
    raise exception 'ไม่พบคำร้อง % (หรือไม่มีสิทธิ์เข้าถึง)', p_request_id;
  end if;

  if v_req.status <> 'pending' then
    raise exception 'คำร้องนี้อยู่สถานะ % แล้ว อนุมัติซ้ำไม่ได้', v_req.status;
  end if;

  -- หัวใจของ dual control — constraint ในตารางกันได้แค่ผู้อนุมัติซ้ำคน
  -- แต่ไม่ได้กันคนขอมาอนุมัติเอง ถ้าไม่ปิดตรงนี้ ครูคนเดียวก็ขอเอง
  -- แล้วกดอนุมัติหนึ่งในสองช่องเองได้ เหลือให้หาคนกดอีกคนเดียว
  if v_actor = v_req.requested_by then
    raise exception 'ผู้ยื่นคำร้องอนุมัติคำร้องของตัวเองไม่ได้';
  end if;

  if v_req.approver_1_id is null then
    update grade_change_request
       set approver_1_id = v_actor, approver_1_at = now()
     where id = p_request_id;
    return 'pending';
  end if;

  if v_req.approver_1_id = v_actor then
    raise exception 'คุณอนุมัติคำร้องนี้ไปแล้ว ต้องให้ผู้อนุมัติอีกคนเป็นคนละคน';
  end if;

  -- คนที่สอง — อนุมัติครบแล้วลงมือแก้ทันทีในธุรกรรมเดียว
  update grade_change_request
     set approver_2_id = v_actor, approver_2_at = now(), status = 'approved'
   where id = p_request_id;

  perform apply_grade_change(p_request_id);
  return 'applied';
end $$;

comment on function approve_grade_change(uuid) is
  'อนุมัติคำร้องแก้เกรด ต้องสองคนคนละคน และห้ามเป็นผู้ยื่นคำร้อง คนที่สองกดแล้วระบบแก้ให้ทันที';

-- ───────────────────────────────────────────────────────────────────
-- ปฏิเสธคำร้อง
-- ───────────────────────────────────────────────────────────────────
create or replace function reject_grade_change(p_request_id uuid, p_reason text)
returns change_request_status
language plpgsql as $$
declare v_req grade_change_request%rowtype; v_actor uuid := current_actor_id();
begin
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'ต้องระบุเหตุผลที่ปฏิเสธ เพื่อให้ผู้ยื่นรู้ว่าต้องแก้อะไร';
  end if;

  select * into v_req from grade_change_request where id = p_request_id;
  if not found then
    raise exception 'ไม่พบคำร้อง % (หรือไม่มีสิทธิ์เข้าถึง)', p_request_id;
  end if;

  if v_req.status <> 'pending' then
    raise exception 'คำร้องนี้อยู่สถานะ % แล้ว ปฏิเสธไม่ได้', v_req.status;
  end if;

  if v_actor = v_req.requested_by then
    raise exception 'ผู้ยื่นคำร้องปฏิเสธคำร้องของตัวเองไม่ได้ ถ้าต้องการยกเลิกให้แจ้งงานทะเบียน';
  end if;

  update grade_change_request
     set status = 'rejected',
         reason = reason || E'\n[ปฏิเสธ] ' || btrim(p_reason)
   where id = p_request_id;

  return 'rejected';
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ด่านสุดท้าย: บังคับ dual control ที่ตัวตาราง ไม่ใช่แค่ในฟังก์ชัน
--
-- ─── ทำไมไม่ใช้ security definer แล้วปิดการเขียนตรงด้วย RLS ───
-- security definer ทำให้ฟังก์ชันรันด้วยสิทธิ์เจ้าของ ซึ่งข้าม RLS ทั้งหมด
-- แปลว่าครูของวิทยาลัยหนึ่งส่ง id ของอีกวิทยาลัยเข้ามาก็ทำงานได้
-- เป็นการแลกช่องโหว่ใหญ่กับการปิดช่องโหว่เล็ก
--
-- trigger บังคับได้ทุกเส้นทางโดยไม่ต้องยกสิทธิ์ให้ใคร — ผ่านฟังก์ชัน
-- ผ่าน pgAdmin หรือผ่านสคริปต์ย้ายข้อมูล ก็ติดกฎเดียวกันหมด
-- และ RLS ยังทำงานตามปกติเพราะฟังก์ชันรันด้วยสิทธิ์ผู้เรียก
-- ───────────────────────────────────────────────────────────────────
create or replace function grade_change_request_guard() returns trigger
language plpgsql as $$
begin
  -- ตั้งผู้อนุมัติทั้งสองคนพร้อมกันในคำสั่งเดียวไม่ได้
  -- นี่คือช่องที่ทำให้ dual control ไร้ความหมายที่สุด เพราะคนเดียวกดจบได้เลย
  if old.approver_1_id is null and old.approver_2_id is null
     and new.approver_1_id is not null and new.approver_2_id is not null then
    raise exception 'ตั้งผู้อนุมัติสองคนพร้อมกันในคำสั่งเดียวไม่ได้ ต้องอนุมัติทีละคน';
  end if;

  -- ผู้ยื่นคำร้องเป็นผู้อนุมัติเองไม่ได้
  if new.approver_1_id = new.requested_by or new.approver_2_id = new.requested_by then
    raise exception 'ผู้ยื่นคำร้องเป็นผู้อนุมัติคำร้องของตัวเองไม่ได้';
  end if;

  -- ลบผู้อนุมัติที่ลงไปแล้วเพื่อกดใหม่ไม่ได้
  if (old.approver_1_id is not null and new.approver_1_id is distinct from old.approver_1_id)
     or (old.approver_2_id is not null and new.approver_2_id is distinct from old.approver_2_id) then
    raise exception 'ผู้อนุมัติที่ลงไปแล้วเปลี่ยนไม่ได้';
  end if;

  -- สาระของคำร้องต้องไม่ถูกสลับหลังมีคนอนุมัติไปแล้ว
  -- ไม่งั้นจะขออย่างหนึ่งให้คนอนุมัติ แล้วเปลี่ยนเป็นอีกอย่างก่อนคนที่สองกด
  if old.approver_1_id is not null
     and (new.enrollment_id      is distinct from old.enrollment_id
       or new.from_result_id     is distinct from old.from_result_id
       or new.to_grade_symbol_id is distinct from old.to_grade_symbol_id
       or new.to_raw_score       is distinct from old.to_raw_score
       or new.requested_by       is distinct from old.requested_by) then
    raise exception 'แก้สาระของคำร้องหลังมีผู้อนุมัติแล้วไม่ได้ ให้ยื่นคำร้องใหม่';
  end if;

  -- สถานะเดินได้ทางเดียว: pending → approved → applied หรือ pending → rejected
  if new.status is distinct from old.status then
    if not ((old.status = 'pending'  and new.status in ('approved', 'rejected'))
         or (old.status = 'approved' and new.status = 'applied')) then
      raise exception 'เปลี่ยนสถานะคำร้องจาก % ไป % ไม่ได้', old.status, new.status;
    end if;
  end if;

  -- ขึ้นเป็นอนุมัติได้ต่อเมื่อมีผู้อนุมัติครบสองคนจริง
  if new.status = 'approved'
     and (new.approver_1_id is null or new.approver_2_id is null) then
    raise exception 'คำร้องจะเป็นอนุมัติได้ต่อเมื่อมีผู้อนุมัติครบสองคน';
  end if;

  return new;
end $$;

create trigger grade_change_request_dual_control
  before update on grade_change_request
  for each row execute function grade_change_request_guard();

-- คำร้องที่ปิดไปแล้วลบทิ้งไม่ได้ ต้องเหลือไว้ให้ตรวจสอบย้อนหลัง
create or replace function grade_change_request_no_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'คำร้องแก้เกรดลบไม่ได้ ต้องเก็บไว้เป็นหลักฐานการตรวจสอบ';
end $$;

create trigger grade_change_request_block_delete
  before delete on grade_change_request
  for each row execute function grade_change_request_no_delete();

commit;

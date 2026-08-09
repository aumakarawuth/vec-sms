-- ═══════════════════════════════════════════════════════════════════
-- 0037_provisioning.sql
--
-- เปิดวิทยาลัยใหม่โดยไม่ต้องรัน SQL เอง
--
-- ─── ทำไมข้อนี้บล็อกการขาย ───
-- ก่อนไฟล์นี้ การรับวิทยาลัยใหม่หนึ่งแห่งต้องมีคนเปิด psql แล้ว insert
-- ทีละตาราง — สถานศึกษา นโยบายยืนยันตัวตน นโยบายตารางสอน นโยบายพฤติกรรม
-- ปีการศึกษา และบัญชีผู้ดูแลคนแรก ถ้าลืมสักตาราง ระบบจะทำงานผิดแบบ
-- ที่หาสาเหตุยากมาก (เช่น auth_policy หายไป แล้วบัญชีไม่มีวันถูกล็อก)
--
-- และไม่มีทางขายแบบให้ลูกค้าสมัครเองได้เลยตราบใดที่ต้องมีคนรันคำสั่ง
--
-- ─── ทำไมไม่ตั้งรหัสผ่านให้ผู้ดูแลคนแรก ───
-- หลักเดียวกับ 0025 — คนที่เปิดระบบให้จะรู้รหัสผ่านของผู้ดูแลวิทยาลัย
-- ตั้งแต่วินาทีแรก ซึ่งแปลว่าผู้ให้บริการเข้าถึงข้อมูลของลูกค้าได้
-- โดยที่บันทึกการเข้าถึงจะระบุว่าเป็นฝีมือของผู้ดูแลวิทยาลัย
--
-- ฟังก์ชันนี้จึงสร้าง **บัญชีที่ยังไม่มีรหัสผ่าน** แล้วคืน person_id
-- ให้ชั้นแอปออกรหัสรีเซ็ตผ่านทางเดิม (issueResetCode) ผู้ดูแลตัวจริง
-- เป็นคนตั้งรหัสผ่านเอง และผู้ให้บริการไม่มีวันรู้
--
-- ─── ทำไมเป็นฟังก์ชันเดียวที่ทำทุกอย่าง ───
-- ถ้าแยกเป็นหลายขั้นแล้วขาดกลางทาง จะเหลือวิทยาลัยครึ่ง ๆ กลาง ๆ ที่
-- ล็อกอินได้แต่ทำงานไม่ได้ และไม่มีใครรู้ว่าต้องเติมอะไรบ้าง
-- ทั้งหมดอยู่ในทรานแซกชันเดียว — สำเร็จทั้งหมดหรือไม่เกิดอะไรเลย
--
-- ─── ทำไมฟังก์ชันนี้เป็น security definer ───
-- ทุกตารางในระบบถูก RLS กรองด้วย current_institution_id() ซึ่งตอน
-- เปิดวิทยาลัยใหม่ยังไม่มีค่าให้ตั้ง — วิทยาลัยที่กำลังจะสร้างยังไม่มีอยู่
--
-- นี่เป็นข้อยกเว้นเดียวของหลัก "อย่าใช้ security definer เพื่อเลี่ยงนโยบาย"
-- เพราะไม่ได้เลี่ยงการกรอง แต่เป็นการสร้างขอบเขตใหม่ขึ้นมา ฟังก์ชันจึง
-- **สร้างได้อย่างเดียว** ไม่มีคำสั่ง select/update/delete ที่แตะข้อมูลของ
-- วิทยาลัยที่มีอยู่แล้วเลย และตรวจว่ารหัสสถานศึกษาไม่ซ้ำก่อนเสมอ
-- ═══════════════════════════════════════════════════════════════════
begin;

create table provisioning_log (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  code           text        not null,
  name_th        text        not null,
  admin_person_id uuid       not null references person on delete restrict,
  requested_by   text,
  created_at     timestamptz not null default now()
);

comment on table provisioning_log is
  'ประวัติการเปิดวิทยาลัยใหม่ — ตอบได้ว่าใครเปิดให้ใครเมื่อไร';

-- ไม่เปิด RLS เหมือน institution เพราะเป็นข้อมูลระดับผู้ให้บริการ
-- ไม่ใช่ของวิทยาลัยใด และผู้ใช้ทั่วไปไม่มีทางเข้าถึง (ไม่มี endpoint ให้อ่าน)
alter table provisioning_log enable row level security;
alter table provisioning_log force  row level security;
create policy tenant_isolation on provisioning_log
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- ───────────────────────────────────────────────────────────────────
-- เปิดวิทยาลัยใหม่
-- ───────────────────────────────────────────────────────────────────
create or replace function provision_institution(
  p_code            text,
  p_name_th         text,
  p_admin_prefix_th text,
  p_admin_first_th  text,
  p_admin_last_th   text,
  p_admin_username  text,
  p_year_be         smallint,
  p_year_starts_on  date,
  p_year_ends_on    date,
  p_name_en         text default null,
  p_admin_email     text default null,
  p_admin_phone     text default null,
  p_requested_by    text default null
) returns table (
  institution_id  uuid,
  admin_person_id uuid,
  admin_staff_id  uuid,
  academic_year_id uuid
) language plpgsql security definer set search_path = public as $$
declare
  v_inst   uuid;
  v_person uuid;
  v_staff  uuid;
  v_year   uuid;
begin
  if coalesce(btrim(p_code), '') = '' or coalesce(btrim(p_name_th), '') = '' then
    raise exception 'ต้องระบุรหัสสถานศึกษาและชื่อสถานศึกษา';
  end if;
  if coalesce(btrim(p_admin_username), '') = '' then
    raise exception 'ต้องระบุชื่อผู้ใช้ของผู้ดูแลคนแรก';
  end if;
  if p_year_ends_on <= p_year_starts_on then
    raise exception 'วันสิ้นปีการศึกษาต้องอยู่หลังวันเริ่ม';
  end if;

  if exists (select 1 from institution i where i.code = btrim(p_code)) then
    raise exception 'รหัสสถานศึกษา % ถูกใช้ไปแล้ว', btrim(p_code)
      using errcode = 'unique_violation';
  end if;

  insert into institution (code, name_th, name_en)
  values (btrim(p_code), btrim(p_name_th), nullif(btrim(p_name_en), ''))
  returning id into v_inst;

  -- ── นโยบายพื้นฐาน ──────────────────────────────────────────────
  -- ใช้ค่าเริ่มต้นของแต่ละตาราง การไม่มีแถวเหล่านี้คือสาเหตุของอาการ
  -- ที่หายากที่สุด — บัญชีไม่มีวันถูกล็อก ตารางสอนไม่มีเพดานคาบ
  -- และคะแนนความประพฤติไม่มีค่าตั้งต้น
  insert into auth_policy (institution_id) values (v_inst);
  insert into timetable_policy (institution_id) values (v_inst);
  insert into behavior_policy (institution_id) values (v_inst);

  insert into academic_year (institution_id, year_be, starts_on, ends_on)
  values (v_inst, p_year_be, p_year_starts_on, p_year_ends_on)
  returning id into v_year;

  -- ── ผู้ดูแลคนแรก ───────────────────────────────────────────────
  insert into person
    (institution_id, prefix_th, first_name_th, last_name_th, email, phone)
  values (v_inst, nullif(btrim(p_admin_prefix_th), ''),
          btrim(p_admin_first_th), btrim(p_admin_last_th),
          nullif(btrim(p_admin_email), ''), nullif(btrim(p_admin_phone), ''))
  returning id into v_person;

  insert into staff (institution_id, person_id, staff_code, is_teacher)
  values (v_inst, v_person, 'ADMIN-001', false)
  returning id into v_staff;

  insert into staff_role (staff_id, role, effective_from, granted_by, reason)
  values (v_staff, 'admin', current_date, v_staff,
          'ผู้ดูแลคนแรกที่สร้างพร้อมการเปิดวิทยาลัย');

  -- บัญชีที่ยังไม่มีรหัสผ่าน — ผู้ดูแลตัวจริงตั้งเองผ่านรหัสรีเซ็ต
  --
  -- must_change = true และค่าแฮชเป็นค่าที่เทียบกับอะไรไม่ได้เลย จึงเข้าระบบ
  -- ด้วยรหัสผ่านไม่ได้จนกว่าจะรีเซ็ต ต่างจากการตั้งรหัสชั่วคราวให้ตรงที่
  -- ไม่มีใครนอกจากเจ้าตัวรู้รหัสผ่านได้เลยแม้แต่วินาทีเดียว
  insert into user_credential
    (institution_id, person_id, username, password_hash, must_change)
  values (v_inst, v_person, btrim(p_admin_username),
          'locked$' || encode(gen_random_bytes(32), 'hex'), true);

  insert into provisioning_log
    (institution_id, code, name_th, admin_person_id, requested_by)
  values (v_inst, btrim(p_code), btrim(p_name_th), v_person, p_requested_by);

  return query select v_inst, v_person, v_staff, v_year;
end $$;

comment on function provision_institution is
  'เปิดวิทยาลัยใหม่ทั้งชุดในทรานแซกชันเดียว — สร้างบัญชีผู้ดูแลที่ยังไม่มีรหัสผ่าน ผู้ให้บริการจึงไม่มีวันรู้รหัสของลูกค้า';

-- ให้เฉพาะเจ้าของฐานข้อมูลเรียกได้ ผู้ใช้ของแอปเรียกไม่ได้โดยตรง
-- ชั้นแอปเข้าถึงผ่าน ADMIN_DATABASE_URL ซึ่งใช้เฉพาะเส้นทางเปิดวิทยาลัย
revoke execute on function provision_institution from public;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 0056_multi_role_secretary_hr.sql
-- ทดสอบบทบาทซ้อนและบทบาทเลขา/งานบุคคล (0095)
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. คนที่มีทั้งบทบาทระดับวิทยาลัยและเป็นครูผู้สอน ได้บทบาทครบทั้งชุด
--    ไม่ถูกยุบเหลือตัวเดียว — เหตุผลทั้งหมดที่ 0095 มีอยู่
-- 2. current_app_roles() ถอยไปใช้ app.role เมื่อไม่มี app.roles —
--    งานเบื้องหลังตั้งแค่ app.role ถ้าคืนอาร์เรย์ว่าง นโยบายที่อ่านชุดบทบาท
--    จะปิดทุกอย่างของบริบทเหล่านั้นโดยไม่มีอะไรฟ้อง
-- 3. เลขาปลอมเอกสารหลักฐานไม่ได้ — ใบ รบ. ที่ใส่ payload เองคือเอกสาร
--    ทางการปลอมที่แก้/ลบไม่ได้อีกเลย (หลักข้อ 4)
-- 4. งานบุคคลอ่านระเบียนของบุคลากรคนอื่นได้ · เลขาเขียนไม่ได้ (งานบุคคลเขียนได้ตั้งแต่ 0097 — TEST 343)
--
-- ─── สิ่งที่เทสต์นี้ตั้งใจ *ไม่* ยืนยัน ───
-- เลขาออกหนังสือถึงผู้ปกครอง/ประกาศ และงานบุคคลแก้ระเบียน ยังทำไม่ได้จริง
-- (นโยบาย restrictive ของ 0049 กับ @Roles ของ API ยังไม่เปิดให้) ข้อ 3–4
-- จึงเฝ้า "ไม่เกินสิทธิ์" อย่างเดียว ถ้าวันหนึ่งเปิดให้ทำงานได้จริง ต้องเพิ่ม
-- เทสต์ "ยังทำได้" คู่กัน ไม่ใช่ลบข้อเหล่านี้ทิ้ง
--
-- ข้อที่ต้อง "ถูกปฏิเสธ" ใช้ธงบูลีน ไม่ raise ในบล็อกที่ตัวเองดักอยู่
-- (กับดักในหัวไฟล์ 0024)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select s.person_id as reg_person, s.id as reg_staff, s.institution_id as inst_id
  from staff s
  join staff_role sr on sr.staff_id = s.id
 where sr.role = 'registrar' and sr.revoked_at is null and s.active
 order by s.id
 limit 1 \gset

select set_config('test.reg_person', :'reg_person', false) as a,
       set_config('test.reg_staff',  :'reg_staff',  false) as b,
       set_config('test.inst',       :'inst_id',    false) as c \gset ctx_

-- ── TEST 338 ───────────────────────────────────────────────────────
-- บทบาทซ้อนไม่ถูกยุบ และบทบาทเดียวยังได้ผลเดิม
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_person uuid := current_setting('test.reg_person')::uuid;
  v_inst   uuid := current_setting('test.inst')::uuid;
  v_roles  text[];
begin
  v_roles := login_roles_for(v_person, v_inst);
  if not ('registrar' = any (v_roles)) or 'teacher' = any (v_roles) then
    raise exception 'TEST 338 ล้มเหลว: งานทะเบียนที่ไม่ได้สอนควรได้ {registrar} ได้ %', v_roles;
  end if;

  update staff set is_teacher = true where id = current_setting('test.reg_staff')::uuid;
  v_roles := login_roles_for(v_person, v_inst);
  if not (v_roles @> array['registrar', 'teacher']) then
    raise exception 'TEST 338 ล้มเหลว: งานทะเบียนที่เป็นครูผู้สอนด้วยต้องได้ทั้งสองบทบาท ได้ %', v_roles;
  end if;

  -- บทบาทหลักยังเป็นตัวที่แรงที่สุด — access_log และการลงชื่ออนุมัติอ้างค่านี้
  if login_role_for(v_person, v_inst) <> 'registrar' then
    raise exception 'TEST 338 ล้มเหลว: บทบาทหลักควรเป็น registrar ได้ %', login_role_for(v_person, v_inst);
  end if;
  raise notice 'TEST 338 ผ่าน — บทบาทซ้อนได้ครบชุด % และบทบาทหลักยังเป็นตัวที่แรงที่สุด', v_roles;
end $$;
rollback;

-- ── TEST 339 ───────────────────────────────────────────────────────
-- current_app_roles() ถอยไปใช้ app.role เมื่อไม่มี app.roles
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id', true) as a,
       set_config('app.role',           'finance',  true) as b \gset ctx_
do $$
begin
  if current_app_roles() <> array['finance'] then
    raise exception 'TEST 339 ล้มเหลว: ไม่มี app.roles ต้องได้ {finance} ได้ %', current_app_roles();
  end if;
  perform set_config('app.roles', 'academic,teacher', true);
  if current_app_roles() <> array['academic', 'teacher'] then
    raise exception 'TEST 339 ล้มเหลว: app.roles=academic,teacher ต้องได้สองตัว ได้ %', current_app_roles();
  end if;
  raise notice 'TEST 339 ผ่าน — งานเบื้องหลังที่ตั้งแค่ app.role ยังได้บทบาทของตัวเอง';
end $$;
rollback;

-- ── TEST 340 ───────────────────────────────────────────────────────
-- เลขาปลอมใบ รบ. ไม่ได้ และแตะเอกสารหลักฐานที่มีอยู่ไม่ได้
-- ═══════════════════════════════════════════════════════════════════
select st.id as stu_id from student st where st.institution_id = :'inst_id' order by st.id limit 1 \gset
select set_config('test.stu', :'stu_id', false) as a \gset ctx_

begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',    true) as a,
       set_config('app.actor_id',       :'reg_person', true) as b,
       set_config('app.role',           'secretary',   true) as c,
       set_config('app.roles',          'secretary',   true) as d \gset ctx_
do $$
declare
  v_forged  boolean := false;
  v_n       integer;
begin
  begin
    insert into issued_document (institution_id, student_id, kind, doc_no, payload)
    values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
            'transcript', 'TEST-340-FORGED', '{"gpax": "4.00"}');
    v_forged := true;
  exception when others then
    null;
  end;
  if v_forged then
    raise exception 'TEST 340 ล้มเหลว: เลขาสร้างใบ รบ. ด้วย payload ที่เขียนเองได้';
  end if;

  update issued_document set void_reason = 'TEST 340', voided_at = now();
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise exception 'TEST 340 ล้มเหลว: เลขายกเลิกเอกสารหลักฐานได้ % ใบ', v_n;
  end if;
  raise notice 'TEST 340 ผ่าน — เลขาปลอมหรือยกเลิกเอกสารหลักฐานไม่ได้';
end $$;
rollback;

-- ── TEST 341 ───────────────────────────────────────────────────────
-- งานบุคคลอ่านระเบียนของคนอื่นได้ แต่เขียนทับไม่ได้
-- ═══════════════════════════════════════════════════════════════════
select sr.staff_id as rec_staff from staff_record sr order by sr.id limit 1 \gset
select set_config('test.rec_staff', :'rec_staff', false) as a \gset ctx_

-- คนที่สวมบทบาท hr ต้องไม่ใช่เจ้าของระเบียน มิฉะนั้นจะอ่านได้เพราะเป็นของตัวเอง
select p.id as outsider
  from person p
  join staff s on s.person_id = p.id
 where s.institution_id = :'inst_id' and s.id <> :'rec_staff'
 order by p.id
 limit 1 \gset

begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',  true) as a,
       set_config('app.actor_id',       :'outsider', true) as b,
       set_config('app.role',           'hr',        true) as c,
       set_config('app.roles',          'hr',        true) as d \gset ctx_
do $$
declare
  v_seen    integer;
  v_n       integer;
  v_insert  boolean := false;
begin
  select count(*) into v_seen from staff_record
   where staff_id = current_setting('test.rec_staff')::uuid;
  if v_seen = 0 then
    raise exception 'TEST 341 ล้มเหลว: งานบุคคลต้องอ่านระเบียน ทช.1 ของบุคลากรคนอื่นได้';
  end if;

  -- 0097 เปิดให้งานบุคคลเขียนได้แล้ว (TEST 343) — ครึ่งหลังนี้จึงเฝ้า
  -- "ไม่เกินสิทธิ์" ด้วยบทบาทเลขาแทน ซึ่งไม่ควรแตะระเบียนบุคลากรเลย
  perform set_config('app.role', 'secretary', true);
  perform set_config('app.roles', 'secretary', true);

  update staff_record set title_th = 'TEST 341'
   where staff_id = current_setting('test.rec_staff')::uuid;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise exception 'TEST 341 ล้มเหลว: เลขาแก้ระเบียนบุคลากรได้ % แถว', v_n;
  end if;

  begin
    insert into staff_record (staff_id, kind, title_th)
    values (current_setting('test.rec_staff')::uuid, 'award', 'TEST 341');
    v_insert := true;
  exception when others then
    null;
  end;
  if v_insert then
    raise exception 'TEST 341 ล้มเหลว: เลขาเพิ่มระเบียนบุคลากรได้';
  end if;
  raise notice 'TEST 341 ผ่าน — งานบุคคลอ่านระเบียนได้ % แถว · เลขาเขียนไม่ได้', v_seen;
end $$;
rollback;

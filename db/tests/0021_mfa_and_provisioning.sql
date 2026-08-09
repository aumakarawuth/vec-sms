-- ═══════════════════════════════════════════════════════════════════
-- 0021_mfa_and_provisioning.sql
-- ทดสอบการยืนยันสองชั้นและการเปิดวิทยาลัยใหม่
--
-- ─── ทำไมชุดนี้เน้นตัวนับ ───
-- ระบบยืนยันสองชั้นที่ตัวนับไม่ทำงานดูเหมือนทำงานปกติทุกประการ —
-- รหัสผิดถูกปฏิเสธถูกต้องทุกครั้ง ผู้ใช้จริงเข้าได้ ไม่มี error ที่ไหน
-- สิ่งเดียวที่ต่างคือไม่มีวันล็อก ซึ่งแปลว่ารหัสหกหลักถูกเดาได้ไม่จำกัด
-- และเดาถูกภายในไม่กี่ชั่วโมง
--
-- ─── และเน้นว่าเปิดวิทยาลัยแล้วต้องครบ ───
-- วิทยาลัยที่ขาด auth_policy จะไม่มีวันล็อกบัญชีใครเลย ขาด behavior_policy
-- จะไม่มีคะแนนความประพฤติตั้งต้น ขาด timetable_policy จะจัดตารางไม่ได้
-- ทั้งสามอย่างไม่มี error ตอนเปิด แต่ไปโผล่เป็นพฤติกรรมประหลาดทีหลัง
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 171 ───────────────────────────────────────────────────────
-- ตัวนับต้องขยับทุกครั้งที่ผิด และล็อกเมื่อครบเพดาน
do $$
declare
  v_person uuid := 'aaaa0000-0000-0000-0000-000000000001';
  r        record;
  v_locked boolean := false;
  i        integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', v_person::text, true);
  perform set_config('app.role', 'admin', true);

  insert into mfa_credential (institution_id, person_id, secret_enc, confirmed_at)
  values ('11111111-1111-1111-1111-111111111111', v_person,
          decode('00112233445566778899', 'hex'), now())
  on conflict (person_id) do update set confirmed_at = now(),
    failed_attempts = 0, locked_until = null, last_step = null;

  -- เพดานค่าเริ่มต้นคือ 5 ครั้ง
  for i in 1..5 loop
    select * into r from mfa_verify_step(v_person, 100000::bigint, false);
    if r.ok then
      raise exception 'TEST 171 ล้มเหลว: รหัสผิดกลับผ่าน';
    end if;
  end loop;

  select * into r from mfa_verify_step(v_person, 100000::bigint, true);
  if r.ok then
    raise exception 'TEST 171 ล้มเหลว: ใส่ผิดครบเพดานแล้วยังเข้าได้';
  end if;
  if r.retry_after_secs <= 0 then
    raise exception 'TEST 171 ล้มเหลว: ถูกล็อกแต่ไม่บอกว่าต้องรอนานเท่าไร';
  end if;
  v_locked := true;

  raise notice 'TEST 171 ผ่าน — ผิดครบ 5 ครั้งแล้วถูกล็อก ต้องรออีก % วินาที (%)',
    r.retry_after_secs, r.reason;
end $$;

-- ── TEST 172 ───────────────────────────────────────────────────────
-- รหัสของช่วงเวลาที่ใช้ไปแล้วต้องใช้ซ้ำไม่ได้
do $$
declare
  v_person uuid := 'aaaa0000-0000-0000-0000-000000000001';
  r        record;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', v_person::text, true);
  perform set_config('app.role', 'admin', true);

  update mfa_credential set failed_attempts = 0, locked_until = null, last_step = null
   where person_id = v_person;

  select * into r from mfa_verify_step(v_person, 200000::bigint, true);
  if not r.ok then
    raise exception 'TEST 172 ล้มเหลว: รหัสที่ถูกต้องกลับไม่ผ่าน (%)', r.reason;
  end if;

  -- ช่วงเดิม
  select * into r from mfa_verify_step(v_person, 200000::bigint, true);
  if r.ok then
    raise exception 'TEST 172 ล้มเหลว: รหัสของช่วงเดิมใช้ซ้ำได้ — คนที่แอบเห็นรหัสจะเข้าระบบได้';
  end if;

  -- ช่วงที่ผ่านไปแล้ว
  select * into r from mfa_verify_step(v_person, 199999::bigint, true);
  if r.ok then
    raise exception 'TEST 172 ล้มเหลว: รหัสของช่วงที่ผ่านไปแล้วยังใช้ได้';
  end if;

  -- ช่วงใหม่กว่าใช้ได้
  update mfa_credential set failed_attempts = 0, locked_until = null where person_id = v_person;
  select * into r from mfa_verify_step(v_person, 200001::bigint, true);
  if not r.ok then
    raise exception 'TEST 172 ล้มเหลว: ช่วงเวลาถัดไปกลับใช้ไม่ได้ (%)', r.reason;
  end if;

  raise notice 'TEST 172 ผ่าน — ช่วงเดิมและช่วงเก่าใช้ซ้ำไม่ได้ ช่วงใหม่ใช้ได้';
end $$;

-- ── TEST 173 ───────────────────────────────────────────────────────
-- รหัสกู้คืนใช้ได้ครั้งเดียว และเดาผิดถูกนับเข้าตัวนับเดียวกัน
do $$
declare
  v_person uuid := 'aaaa0000-0000-0000-0000-000000000001';
  v_cred   uuid;
  r        record;
  v_before smallint;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', v_person::text, true);
  perform set_config('app.role', 'admin', true);

  select id into v_cred from mfa_credential where person_id = v_person;
  update mfa_credential set failed_attempts = 0, locked_until = null where id = v_cred;

  insert into mfa_recovery_code (credential_id, code_hash)
  values (v_cred, digest('RECOVERY-1', 'sha256'))
  on conflict do nothing;

  select * into r from mfa_consume_recovery(v_person, digest('RECOVERY-1', 'sha256'), null);
  if not r.ok then
    raise exception 'TEST 173 ล้มเหลว: รหัสกู้คืนที่ถูกต้องใช้ไม่ได้ (%)', r.reason;
  end if;

  select * into r from mfa_consume_recovery(v_person, digest('RECOVERY-1', 'sha256'), null);
  if r.ok then
    raise exception 'TEST 173 ล้มเหลว: รหัสกู้คืนใช้ซ้ำได้';
  end if;

  select failed_attempts into v_before from mfa_credential where id = v_cred;
  perform mfa_consume_recovery(v_person, digest('ไม่มีรหัสนี้', 'sha256'), null);
  if (select failed_attempts from mfa_credential where id = v_cred) <= v_before then
    raise exception 'TEST 173 ล้มเหลว: เดารหัสกู้คืนผิดแล้วตัวนับไม่ขยับ';
  end if;

  raise notice 'TEST 173 ผ่าน — รหัสกู้คืนใช้ได้ครั้งเดียว และการเดาผิดถูกนับ';
end $$;

-- ── TEST 174 ───────────────────────────────────────────────────────
-- เปิดวิทยาลัยใหม่แล้วต้องได้ครบทุกชั้น
do $$
declare
  r        record;
  v_pol    integer;
  v_tt     integer;
  v_bh     integer;
  v_role   integer;
  v_cred   record;
begin
  select * into r from provision_institution(
    '1399990001', 'วิทยาลัยเทคโนโลยีเปิดใหม่ทดสอบ',
    'นาย', 'ทดสอบ', 'ผู้ดูแลระบบ', 'admin001',
    2569::smallint, '2026-05-11'::date, '2027-03-31'::date,
    'New Test Technology College', 'admin@newcollege.ac.th', '021234567',
    'ทดสอบอัตโนมัติ');

  if r.institution_id is null then
    raise exception 'TEST 174 ล้มเหลว: ไม่ได้สถานศึกษาใหม่';
  end if;

  select count(*) into v_pol from auth_policy      where institution_id = r.institution_id;
  select count(*) into v_tt  from timetable_policy where institution_id = r.institution_id;
  select count(*) into v_bh  from behavior_policy  where institution_id = r.institution_id;
  select count(*) into v_role from staff_role sr
    join staff s on s.id = sr.staff_id
   where s.institution_id = r.institution_id and sr.role = 'admin';

  if v_pol = 0 then
    raise exception 'TEST 174 ล้มเหลว: ไม่มี auth_policy — บัญชีจะไม่มีวันถูกล็อก';
  end if;
  if v_tt = 0 then
    raise exception 'TEST 174 ล้มเหลว: ไม่มี timetable_policy — จัดตารางไม่ได้';
  end if;
  if v_bh = 0 then
    raise exception 'TEST 174 ล้มเหลว: ไม่มี behavior_policy — ไม่มีคะแนนความประพฤติตั้งต้น';
  end if;
  if v_role = 0 then
    raise exception 'TEST 174 ล้มเหลว: ผู้ดูแลคนแรกไม่ได้สิทธิ์ admin';
  end if;

  -- บัญชีผู้ดูแลต้องมีอยู่แต่ **เข้าด้วยรหัสผ่านไม่ได้**
  select * into v_cred from user_credential
   where institution_id = r.institution_id and person_id = r.admin_person_id;

  if v_cred.id is null then
    raise exception 'TEST 174 ล้มเหลว: ไม่ได้สร้างบัญชีผู้ดูแล';
  end if;
  if v_cred.password_hash not like 'locked$%' then
    raise exception 'TEST 174 ล้มเหลว: ตั้งรหัสผ่านให้ผู้ดูแล ผู้ให้บริการจะรู้รหัสของลูกค้า';
  end if;
  if not v_cred.must_change then
    raise exception 'TEST 174 ล้มเหลว: ไม่ได้บังคับตั้งรหัสผ่านใหม่';
  end if;

  raise notice 'TEST 174 ผ่าน — ได้นโยบายครบสามชุด · ผู้ดูแลมีสิทธิ์ admin · บัญชีเข้าด้วยรหัสผ่านไม่ได้';
end $$;

-- ── TEST 175 ───────────────────────────────────────────────────────
-- รหัสสถานศึกษาซ้ำเปิดไม่ได้ และวิทยาลัยใหม่ไม่เห็นข้อมูลของวิทยาลัยเดิม
do $$
declare v_blocked integer := 0;
begin
  begin
    perform provision_institution(
      '1399990001', 'ซ้ำรหัสเดิม', 'นาย', 'ก', 'ข', 'admin002',
      2569::smallint, '2026-05-11'::date, '2027-03-31'::date);
  exception when unique_violation then v_blocked := v_blocked + 1;
  end;

  begin
    perform provision_institution(
      '1399990002', 'วันที่กลับด้าน', 'นาย', 'ก', 'ข', 'admin003',
      2569::smallint, '2027-03-31'::date, '2026-05-11'::date);
  exception when others then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 2 then
    raise exception 'TEST 175 ล้มเหลว: ควรถูกบล็อกสองทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;
  raise notice 'TEST 175 ผ่าน — รหัสซ้ำและวันที่กลับด้านเปิดไม่ได้';
end $$;

-- ── TEST 176 ───────────────────────────────────────────────────────
-- วิทยาลัยที่เพิ่งเปิดต้องไม่เห็นข้อมูลของวิทยาลัยเดิมเลย
begin;
set local role app_runtime;
set local app.role = 'admin';

do $$
declare
  v_new  uuid;
  v_stu  integer;
  v_doc  integer;
  v_app  integer;
begin
  select id into v_new from institution where code = '1399990001';
  perform set_config('app.institution_id', v_new::text, true);

  select count(*) into v_stu from student;
  select count(*) into v_doc from issued_document;
  select count(*) into v_app from application;

  if v_stu + v_doc + v_app <> 0 then
    raise exception 'TEST 176 ล้มเหลว: วิทยาลัยใหม่เห็นนักศึกษา % เอกสาร % ใบสมัคร %',
      v_stu, v_doc, v_app;
  end if;
  raise notice 'TEST 176 ผ่าน — วิทยาลัยที่เพิ่งเปิดเริ่มจากศูนย์จริง ๆ';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบการยืนยันสองชั้นและการเปิดวิทยาลัยครบทุกข้อ ════'; end $$;

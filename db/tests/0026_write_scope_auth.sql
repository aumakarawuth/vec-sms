-- ═══════════════════════════════════════════════════════════════════
-- 0026_write_scope_auth.sql
-- ทดสอบว่าเจ้าของบัญชียกระดับสิทธิ์ตัวเองผ่านตารางยืนยันตัวตนไม่ได้
--
-- ─── ทำไมชุดนี้สำคัญ ───
-- ทุกข้อในนี้คือการ **ถอดมาตรการที่ระบบสร้างไว้กันตัวเอง** ไม่ใช่การรั่ว
-- ของข้อมูล — ปลดล็อกบัญชีที่ถูกล็อกเพราะเดารหัสผิด ปิดการยืนยันสองชั้น
-- ของตัวเอง และอนุมัติอุปกรณ์ใหม่ให้ตัวเอง ทั้งสามข้อทำให้มาตรการที่
-- เหลืออยู่ทั้งหมดกลายเป็นเครื่องประดับ
--
-- ─── สิ่งที่ต้องไม่พังไปด้วย ───
-- เจ้าของ **ต้อง** เปลี่ยนรหัสผ่านของตัวเองได้ และ **ต้อง** ออกจากระบบได้
-- ถ้าเทสต์ข้อ 198 ตก แปลว่าปิดเกินจนผู้ใช้เปลี่ยนรหัสผ่านเองไม่ได้
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมข้อมูลในบทบาท superuser ก่อนสลับบทบาท ────────────────────
select uc.person_id      as person_id,
       uc.institution_id as inst_id,
       uc.id             as cred_id
  from user_credential uc
 limit 1 \gset

insert into mfa_credential (institution_id, person_id, secret_enc, confirmed_at)
values (:'inst_id', :'person_id', '\x00'::bytea, now())
on conflict (person_id) do update set confirmed_at = now(), disabled_at = null;

insert into device_binding (institution_id, person_id, device_id, device_label)
values (:'inst_id', :'person_id', 'test-device-0026', 'เครื่องทดสอบ')
on conflict do nothing;

-- ล็อกและระงับบัญชีไว้ก่อน เพื่อดูว่าเจ้าตัวปลดเองได้ไหม
--
-- ต้องตั้งค่าให้ต่างจากค่าที่จะทดสอบเขียนจริง ๆ — ถ้า disabled_at เป็น null
-- อยู่แล้ว การเขียน null ทับ null ไม่ใช่การเปลี่ยนแปลง trigger จะปล่อยผ่าน
-- อย่างถูกต้อง แล้วเทสต์จะรายงานว่า "ยังถอดได้" ทั้งที่ไม่ได้ถอดอะไรเลย
update user_credential
   set failed_attempts = 4,
       locked_until    = now() + interval '15 minutes',
       disabled_at     = now()
 where id = :'cred_id';

-- ── TEST 196 ───────────────────────────────────────────────────────
-- เจ้าของถอดมาตรการของตัวเองไม่ได้สักข้อ
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'student',    true) as c,
       set_config('test.cred',          :'cred_id',   true) as d,
       set_config('test.person',        :'person_id', true) as e \gset ctx_

do $$
declare
  v_cred   uuid := current_setting('test.cred')::uuid;
  v_person uuid := current_setting('test.person')::uuid;
  v_n      integer;
  v_ok     text[] := '{}';
begin
  -- ปลดล็อกบัญชีตัวเอง
  begin
    update user_credential set failed_attempts = 0, locked_until = null where id = v_cred;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ปลดล็อกบัญชี'); end if;
  exception when others then null; end;

  -- ยกเลิกการระงับบัญชีตัวเอง
  begin
    update user_credential set disabled_at = null where id = v_cred;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ยกเลิกการระงับ'); end if;
  exception when others then null; end;

  -- เปลี่ยนชื่อผู้ใช้
  begin
    update user_credential set username = username || '.x' where id = v_cred;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'เปลี่ยนชื่อผู้ใช้'); end if;
  exception when others then null; end;

  -- ปิด MFA ของตัวเอง
  begin
    update mfa_credential set disabled_at = now() where person_id = v_person;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ปิด MFA'); end if;
  exception when others then null; end;

  -- ล้างตัวนับ MFA
  begin
    update mfa_credential set failed_attempts = 0, locked_until = null where person_id = v_person;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ล้างตัวนับ MFA'); end if;
  exception when others then null; end;

  -- ลบ MFA ทิ้ง
  begin
    delete from mfa_credential where person_id = v_person;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ลบ MFA'); end if;
  exception when others then null; end;

  -- อนุมัติอุปกรณ์ของตัวเอง
  begin
    update device_binding set approved_at = now() where person_id = v_person;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'อนุมัติอุปกรณ์'); end if;
  exception when others then null; end;

  -- ลบประวัติคำขอรหัสรีเซ็ต
  begin
    delete from password_reset where person_id = v_person;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_ok := array_append(v_ok, 'ลบประวัติรหัสรีเซ็ต'); end if;
  exception when others then null; end;

  if array_length(v_ok, 1) > 0 then
    raise exception 'TEST 196 ล้มเหลว: เจ้าของยังถอดมาตรการของตัวเองได้ — %',
      array_to_string(v_ok, ' · ');
  end if;

  raise notice 'TEST 196 ผ่าน — เจ้าของปลดล็อก ปิด MFA และอนุมัติอุปกรณ์ของตัวเองไม่ได้';
end $$;
rollback;

-- ── TEST 197 ───────────────────────────────────────────────────────
-- แต่ยังต้องอ่านสถานะของตัวเองได้ มิฉะนั้นหน้าจอความปลอดภัยว่างเปล่า
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'student',    true) as c,
       set_config('test.person',        :'person_id', true) as d \gset ctx_

do $$
declare v_person uuid := current_setting('test.person')::uuid; v_mfa integer; v_dev integer;
begin
  select count(*) into v_mfa from mfa_credential  where person_id = v_person;
  select count(*) into v_dev from device_binding  where person_id = v_person;

  if v_mfa = 0 then
    raise exception 'TEST 197 ล้มเหลว: เจ้าของดูสถานะ MFA ของตัวเองไม่ได้ '
      '(หน้าจอความปลอดภัยจะบอกไม่ได้ว่าตั้งไว้แล้วหรือยัง)';
  end if;
  if v_dev = 0 then
    raise exception 'TEST 197 ล้มเหลว: เจ้าของดูรายการอุปกรณ์ของตัวเองไม่ได้';
  end if;

  raise notice 'TEST 197 ผ่าน — เจ้าของยังดูสถานะ MFA และอุปกรณ์ของตัวเองได้';
end $$;
rollback;

-- ── TEST 198 ───────────────────────────────────────────────────────
-- เจ้าของยังเปลี่ยนรหัสผ่านและออกจากระบบของตัวเองได้
--
-- ข้อนี้คือด้านกลับของ TEST 196 — ถ้าปิดเกินไปหนึ่งก้าว ผู้ใช้ทุกคน
-- จะเปลี่ยนรหัสผ่านเองไม่ได้ ซึ่งแย่กว่าช่องที่กำลังปิดเสียอีก
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'student',    true) as c,
       set_config('test.cred',          :'cred_id',   true) as d,
       set_config('test.person',        :'person_id', true) as e \gset ctx_

do $$
declare
  v_cred   uuid := current_setting('test.cred')::uuid;
  v_person uuid := current_setting('test.person')::uuid;
  v_n      integer;
  v_sid    uuid;
begin
  -- เปลี่ยนรหัสผ่านของตัวเอง — ตรงกับสามคอลัมน์ที่ changePassword เขียนจริง
  update user_credential
     set password_hash = 'scrypt$ใหม่', must_change = false, password_changed_at = now()
   where id = v_cred;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 198 ล้มเหลว: เจ้าของเปลี่ยนรหัสผ่านของตัวเองไม่ได้ '
      '(ปิดเกินไปจนทุกคนต้องพึ่งงานทะเบียนเพื่อเปลี่ยนรหัสผ่าน)';
  end if;

  -- ออกจากระบบของตัวเอง = เพิกถอน session ของตัวเอง
  insert into auth_session (institution_id, person_id, token_hash, app_role, expires_at)
  values (current_setting('app.institution_id')::uuid, v_person,
          sha256('sess-0026'::bytea), 'student', now() + interval '1 day')
  returning id into v_sid;
  raise exception 'TEST 198 ล้มเหลว: เจ้าของสร้าง session ให้ตัวเองได้ (ปลอมการเข้าสู่ระบบได้)';
exception
  when insufficient_privilege then
    -- สร้าง session เองไม่ได้ ถูกต้องแล้ว
    raise notice 'TEST 198 ผ่าน — เปลี่ยนรหัสผ่านเองได้ แต่สร้าง session ให้ตัวเองไม่ได้';
end $$;
rollback;

-- ── TEST 198ก ──────────────────────────────────────────────────────
-- เพิกถอน session ของตัวเองได้ แต่ต่ออายุไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;

-- สร้าง session ในบทบาท auth (เหมือนตอนล็อกอินจริง) ก่อนสลับเป็นเจ้าของ
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'auth',       true) as c,
       set_config('test.person',        :'person_id', true) as d \gset ctx_

do $$
declare
  v_person uuid := current_setting('test.person')::uuid;
  v_sid    uuid;
  v_n      integer;
  v_extended boolean := false;
begin
  insert into auth_session (institution_id, person_id, token_hash, app_role, expires_at)
  values (current_setting('app.institution_id')::uuid, v_person,
          sha256('sess-0026b'::bytea), 'student', now() + interval '1 day')
  returning id into v_sid;

  -- สลับเป็นเจ้าของบัญชี
  perform set_config('app.role', 'student', true);

  -- ต่ออายุต้องไม่ได้
  begin
    update auth_session set expires_at = now() + interval '365 days' where id = v_sid;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_extended := true; end if;
  exception when insufficient_privilege then null; end;

  if v_extended then
    raise exception 'TEST 198ก ล้มเหลว: เจ้าของต่ออายุ session ของตัวเองได้';
  end if;

  -- แต่เพิกถอนต้องได้ (คือการออกจากระบบ)
  update auth_session set revoked_at = now(), revoke_reason = 'ผู้ใช้ออกจากระบบ'
   where id = v_sid;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'TEST 198ก ล้มเหลว: เจ้าของออกจากระบบของตัวเองไม่ได้';
  end if;

  raise notice 'TEST 198ก ผ่าน — เจ้าของเพิกถอน session ของตัวเองได้ แต่ต่ออายุไม่ได้';
end $$;
rollback;

-- ── เก็บกวาด ────────────────────────────────────────────────────────
--
-- ต้องคืนสถานะบัญชีให้เหมือนเดิมด้วย ไม่ใช่แค่ลบแถวที่สร้างขึ้น —
-- ไฟล์เทสต์ถัดไปใช้บัญชีเดียวกันนี้ ถ้าปล่อยให้ค้างเป็น "ถูกระงับและถูกล็อก"
-- ชุดถัดไปจะล้มด้วยเหตุผลที่ไม่เกี่ยวกับสิ่งที่มันทดสอบเลย
delete from device_binding where device_id = 'test-device-0026';

update user_credential
   set failed_attempts = 0, locked_until = null, disabled_at = null
 where id = :'cred_id';

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนกลุ่มยืนยันตัวตนครบทุกข้อ ════'; end $$;

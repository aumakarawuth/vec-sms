-- ═══════════════════════════════════════════════════════════════════
-- 0042_write_scope_auth.sql
--
-- ปิดช่องที่เจ้าของบัญชียกระดับสิทธิ์ตัวเองผ่านตารางกลุ่มยืนยันตัวตน
--
-- ─── อาการที่ทดสอบแล้วเกิดขึ้นจริง ───
-- ตั้งบริบทเป็นเจ้าของบัญชี (app.role = 'student') แล้วยิง update ตรง ๆ
-- เจ็ดข้อนี้สำเร็จหมด ทุกข้อคือการถอดมาตรการที่ระบบสร้างไว้กันตัวเอง
--
--   ปลดล็อกบัญชีตัวเอง        การล็อกหลังใส่รหัสผิด 5 ครั้งไม่มีความหมาย
--   ยกเลิกการระงับบัญชีตัวเอง  งานทะเบียนระงับบัญชีแล้วเจ้าตัวเปิดคืนได้
--   เปลี่ยนชื่อผู้ใช้ตัวเอง     สวมชื่อผู้ใช้ที่ยังว่างอยู่ได้
--   ปิด MFA ของตัวเอง          ถอดชั้นที่สองทิ้งโดยไม่ต้องใส่รหัสสักครั้ง
--   ล้างตัวนับ MFA             เดารหัสหกหลักได้ไม่จำกัดจำนวนครั้ง
--   ลบ MFA ทิ้งทั้งแถว         เหมือนไม่เคยตั้งชั้นที่สองเลย
--   อนุมัติอุปกรณ์ของตัวเอง    การผูกบัญชีกับเครื่องเดียวไม่มีความหมาย
--
-- ─── ทำไมกลุ่มนี้แก้ยากกว่า 0039 กับ 0041 ───
-- สองไฟล์นั้นตัดสิทธิ์เขียนของเจ้าของทิ้งได้เลย เพราะเจ้าของไม่เคยต้อง
-- เขียนคะแนนหรือใบแจ้งหนี้ของตัวเอง แต่กลุ่มนี้ **เจ้าของต้องเขียนได้จริง**
-- — เปลี่ยนรหัสผ่านเอง และเพิกถอน session ของตัวเองตอนเปลี่ยนรหัสผ่าน
--
-- จึงแยกเป็นสองแบบตามที่เส้นทางจริงเขียนจริง (ตรวจกับโค้ดทุกเส้นทางแล้ว)
--
--   ก. ตารางที่ **บทบาท auth เขียนล้วน ๆ** — mfa_credential ·
--      mfa_recovery_code · device_binding · password_reset · auth_identity
--      ทั้งหมดเขียนผ่าน AuthService ที่ใช้ db.runAs(authCtx) เสมอ
--      เจ้าของจึงไม่ต้องมีสิทธิ์เขียนเลยแม้แต่คอลัมน์เดียว → ปิดด้วย RLS ล้วน
--
--   ข. ตารางที่ **เจ้าของเขียนบางคอลัมน์** — user_credential กับ auth_session
--      RLS เป็นกฎระดับแถว แยกรายคอลัมน์ไม่ได้ จึงต้องใช้ trigger
--      (ตรงกับหลักที่ว่า "อย่าใช้ security definer เลี่ยงนโยบาย ใช้ trigger แทน")
--
-- ─── auth_session ใช้ RLS อย่างเดียวได้โดยไม่ต้องมี trigger ───
-- เจ้าของต้องทำได้อย่างเดียวคือ **เพิกถอน** session ของตัวเอง เงื่อนไข
-- "แถวหลังเขียนต้องมี revoked_at" เขียนใน with check ได้ตรง ๆ — การต่ออายุ
-- session ที่ยังใช้งานอยู่จึงเป็นไปไม่ได้ เพราะผลลัพธ์จะยังไม่ถูกเพิกถอน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ก. ตารางที่บทบาท auth เขียนล้วน ๆ — เจ้าของอ่านได้อย่างเดียว
-- ───────────────────────────────────────────────────────────────────

-- ความลับ TOTP — ออก ยืนยัน นับครั้งที่ผิด และปิด ล้วนทำผ่าน AuthService
-- ที่รันในบทบาท auth ทั้งหมด (mfaEnroll · mfaConfirm · mfaDisable ·
-- verifyStepCommitted) เจ้าตัวจึงไม่ต้องเขียนแถวนี้เองเลย
drop policy if exists mfa_credential_scope on mfa_credential;

create policy mfa_credential_scope on mfa_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'admin'));

create policy mfa_credential_no_owner_delete on mfa_credential
  as restrictive for delete
  using (current_app_role() in ('auth', 'admin'));

comment on policy mfa_credential_scope on mfa_credential is
  'เจ้าของดูสถานะ MFA ของตัวเองได้ แต่ปิดหรือลบเองไม่ได้ — เดิมสั่ง disabled_at = now() ถอดชั้นที่สองทิ้งได้';

drop policy if exists mfa_recovery_code_scope on mfa_recovery_code;

create policy mfa_recovery_code_scope on mfa_recovery_code
  as restrictive
  using (
    current_app_role() = 'auth'
    or exists (select 1 from mfa_credential mc
                where mc.id = mfa_recovery_code.credential_id
                  and mc.person_id = current_actor_id())
  )
  with check (current_app_role() = 'auth');

create policy mfa_recovery_code_no_owner_delete on mfa_recovery_code
  as restrictive for delete
  using (current_app_role() = 'auth');

-- การผูกบัญชีกับอุปกรณ์ — กันการยืมบัญชีกันเช็คอินแทน
-- ถ้าเจ้าตัวอนุมัติเครื่องใหม่ให้ตัวเองได้ มาตรการนี้เท่ากับไม่มี
drop policy if exists device_scope on device_binding;

create policy device_scope on device_binding
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin'));

create policy device_binding_no_owner_delete on device_binding
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin'));

comment on policy device_scope on device_binding is
  'เจ้าของเห็นรายการอุปกรณ์ของตัวเองได้ แต่อนุมัติเองไม่ได้ — เดิมตั้ง approved_at ให้เครื่องใหม่ของตัวเองได้';

-- คำขอรหัสรีเซ็ตรหัสผ่าน — ออกและใช้ผ่านบทบาท auth เท่านั้น
-- (งานทะเบียนออกให้ที่เคาน์เตอร์ผ่านบทบาทของตัวเอง)
drop policy if exists reset_scope on password_reset;

create policy reset_scope on password_reset
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'registrar', 'admin'));

create policy password_reset_no_owner_delete on password_reset
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'admin'));

drop policy if exists identity_scope on auth_identity;

create policy identity_scope on auth_identity
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  )
  with check (current_app_role() in ('auth', 'registrar', 'admin'));

create policy auth_identity_no_owner_delete on auth_identity
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'admin'));

-- ───────────────────────────────────────────────────────────────────
-- ข.1 session — เจ้าของเพิกถอนของตัวเองได้ แต่ต่ออายุไม่ได้
--
-- เงื่อนไขคือ "แถวหลังเขียนต้องถูกเพิกถอนแล้ว" ซึ่งครอบทั้งการออกจากระบบ
-- และการเตะทุกอุปกรณ์ตอนเปลี่ยนรหัสผ่าน (changePassword เพิกถอน session
-- ในบริบทของเจ้าตัวเอง ไม่ใช่บทบาท auth)
--
-- ส่วนการต่ออายุเป็นไปไม่ได้ เพราะผลลัพธ์จะยังมี revoked_at เป็น null
-- และการสร้าง session ใหม่ก็ไม่ได้ด้วยเหตุผลเดียวกัน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists session_scope on auth_session;

create policy session_scope on auth_session
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  )
  with check (
    current_app_role() in ('auth', 'admin')
    or (person_id = current_actor_id() and revoked_at is not null)
  );

create policy auth_session_no_owner_delete on auth_session
  as restrictive for delete
  using (current_app_role() in ('auth', 'admin'));

comment on policy session_scope on auth_session is
  'เจ้าของออกจากระบบของตัวเองได้ (เขียนได้เฉพาะผลลัพธ์ที่ถูกเพิกถอนแล้ว) แต่ต่ออายุ session ไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- ข.2 บัญชีผู้ใช้ — เจ้าของเปลี่ยนได้เฉพาะรหัสผ่านของตัวเอง
--
-- ─── ทำไมต้องเป็น trigger ไม่ใช่ RLS ───
-- RLS ตัดสินเป็นราย **แถว** ไม่ใช่ราย **คอลัมน์** แต่สิ่งที่ต้องแยกตรงนี้
-- คือคอลัมน์ — password_hash เจ้าตัวเปลี่ยนได้ ส่วน locked_until,
-- disabled_at, username, person_id เปลี่ยนไม่ได้ ถ้าใช้ RLS อย่างเดียว
-- ต้องเลือกระหว่าง "เจ้าตัวเปลี่ยนรหัสผ่านเองไม่ได้" กับ "เจ้าตัวปลดล็อก
-- บัญชีตัวเองได้" ซึ่งทั้งสองทางยอมรับไม่ได้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists credential_scope on user_credential;

create policy credential_scope on user_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  )
  -- เจ้าของยังผ่านชั้นนี้ได้เพื่อเปลี่ยนรหัสผ่าน คอลัมน์ที่แตะได้จริง
  -- ถูกจำกัดด้วย trigger ข้างล่าง
  with check (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

create policy user_credential_no_owner_delete on user_credential
  as restrictive for delete
  using (current_app_role() in ('auth', 'registrar', 'admin'));

create or replace function user_credential_owner_guard() returns trigger
language plpgsql as $$
begin
  -- บทบาทที่ดูแลบัญชีคนอื่นได้อยู่แล้ว ไม่ต้องผ่านด่านนี้
  if current_app_role() in ('auth', 'registrar', 'admin') then
    return new;
  end if;

  /*
   * ─── ทำไมต้องปล่อยผ่านเมื่อไม่มีบริบทแอปเลย ───
   * trigger ยิงกับ **ทุกคน** รวมถึง superuser และฟังก์ชันที่ถูกเรียกตรง
   * จากฐานข้อมูล ต่างจาก RLS ที่ superuser ข้ามได้
   *
   * consume_password_reset() (0025) ล้าง failed_attempts และ locked_until
   * โดยตั้งใจ — คนที่ลืมรหัสผ่านจนบัญชีถูกล็อกต้องกลับเข้าระบบได้ ถ้าไม่
   * ปล่อยผ่าน การรีเซ็ตรหัสผ่านจะพังทั้งเส้นทางสำหรับคนที่ถูกล็อกอยู่
   * ซึ่งคือคนส่วนใหญ่ที่ใช้ทางนี้
   *
   * ปล่อยผ่านตรงนี้ไม่ได้เปิดช่องให้ใครเพิ่ม เพราะบริบทที่ไม่มี app.role
   * ก็ไม่มี app.institution_id กับ app.actor_id ด้วย นโยบาย RLS ของตาราง
   * นี้จึงปฏิเสธทุกแถวอยู่แล้วสำหรับผู้ใช้ที่ไม่ใช่ superuser
   */
  if current_app_role() = 'none' then
    return new;
  end if;

  -- ถึงตรงนี้แปลว่าเจ้าของบัญชีเป็นคนเขียนเอง — เปลี่ยนได้เฉพาะรหัสผ่าน
  -- (ตรงกับที่ AuthService.changePassword เขียนจริงสามคอลัมน์)
  if new.username        is distinct from old.username
     or new.person_id       is distinct from old.person_id
     or new.institution_id  is distinct from old.institution_id then
    raise exception 'เปลี่ยนชื่อผู้ใช้หรือเจ้าของบัญชีเองไม่ได้ ต้องให้งานทะเบียนเป็นผู้ดำเนินการ';
  end if;

  if new.disabled_at is distinct from old.disabled_at then
    raise exception 'ยกเลิกการระงับบัญชีของตัวเองไม่ได้ ต้องให้งานทะเบียนเป็นผู้ดำเนินการ';
  end if;

  -- ข้อนี้สำคัญที่สุด — ถ้าปลดล็อกเองได้ การล็อกบัญชีหลังเดารหัสผิด
  -- ห้าครั้งจะไม่มีความหมายเลย เพราะผู้ที่ยึด session ไปแล้วปลดเองได้ทันที
  if new.locked_until    is distinct from old.locked_until
     or new.failed_attempts is distinct from old.failed_attempts then
    raise exception 'ปลดล็อกบัญชีของตัวเองไม่ได้ กรุณารอจนครบกำหนดหรือติดต่องานทะเบียน';
  end if;

  return new;
end $$;

create trigger user_credential_owner_columns
  before update on user_credential
  for each row execute function user_credential_owner_guard();

comment on function user_credential_owner_guard() is
  'เจ้าของบัญชีเปลี่ยนได้เฉพาะรหัสผ่าน — RLS แยกรายคอลัมน์ไม่ได้จึงต้องใช้ trigger';

commit;

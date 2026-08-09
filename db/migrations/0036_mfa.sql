-- ═══════════════════════════════════════════════════════════════════
-- 0036_mfa.sql
--
-- การยืนยันตัวตนสองชั้นสำหรับบทบาทที่เห็นข้อมูลทั้งวิทยาลัย
--
-- ─── ทำไมบทบาทเหล่านี้ต้องมีชั้นที่สอง ───
-- บัญชี admin และ director เห็นข้อมูลนักศึกษาทั้งวิทยาลัย รวมถึงเลขบัตร
-- ประชาชน ผลคัดกรอง SDQ และบันทึกเยี่ยมบ้าน บัญชีเดียวที่หลุดจึงเท่ากับ
-- ข้อมูลทั้งวิทยาลัยหลุด ซึ่งเข้าเงื่อนไขการแจ้งเหตุละเมิดตาม PDPA
--
-- ─── หน้าที่แบ่งกันอย่างไร ───
-- การคำนวณรหัส TOTP อยู่ที่ชั้นแอป เพราะต้องถอดรหัสความลับด้วยกุญแจที่
-- อยู่นอกฐานข้อมูล (หลักเดียวกับ IP_HASH_SECRET) ถ้าฐานข้อมูลรั่ว
-- ผู้โจมตีต้องไม่ได้ความลับ TOTP ไปด้วย
--
-- ส่วนไฟล์นี้ถือ **สถานะที่ต้องอะตอมมิก** — กันการใช้รหัสซ้ำ นับครั้งที่ผิด
-- และการล็อก สามอย่างนี้อยู่ที่ชั้นแอปไม่ได้ เพราะรันหลาย instance แล้ว
-- ต่างคนต่างนับ
--
-- ─── กับดักที่ระบบ MFA ส่วนใหญ่พลาด — รหัสเดิมใช้ซ้ำได้ ───
-- รหัส TOTP หนึ่งตัวใช้ได้ 30 วินาที ถ้าไม่จำว่าใช้ไปแล้ว ผู้ที่แอบเห็น
-- รหัสบนหน้าจอหรือดักจับได้จะใช้ซ้ำได้ภายในหน้าต่างนั้น ซึ่งเพียงพอ
-- สำหรับการเข้าระบบหนึ่งครั้ง — และไม่มีอาการอะไรให้เห็นเลย
-- last_step จึงบันทึกช่วงเวลาล่าสุดที่ใช้ไปแล้ว และรับเฉพาะช่วงที่ใหม่กว่า
--
-- ─── ทำไมฟังก์ชันตรวจไม่ raise ───
-- หลักเดียวกับ login_rate_status และ consume_password_reset (0021, 0025) —
-- ถ้า raise ฐานข้อมูลจะ rollback ตัวนับครั้งที่ผิดทิ้งทุกครั้ง แล้วเดารหัส
-- หกหลักได้ไม่จำกัดจำนวนครั้ง ซึ่งเดาถูกภายในไม่กี่ชั่วโมง
--
-- ─── ทำไมต้องมีรหัสกู้คืน ───
-- โทรศัพท์หายคือเรื่องปกติ ถ้าไม่มีทางกลับเข้าระบบเลย ทางแก้เดียวคือให้
-- คนอื่นปิด MFA ให้ ซึ่งกลายเป็นช่องที่ใหญ่กว่าตัว MFA เอง
-- รหัสกู้คืนเก็บเป็นค่าแฮชและใช้ได้ครั้งเดียว หลักเดียวกับรหัสรีเซ็ตรหัสผ่าน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- บทบาทที่ต้องยืนยันสองชั้น ตั้งได้รายวิทยาลัย
alter table auth_policy
  add column if not exists require_mfa_roles text[] not null default '{admin,director}';

comment on column auth_policy.require_mfa_roles is
  'บทบาทที่ต้องยืนยันตัวตนสองชั้น — ค่าเริ่มต้นคือบทบาทที่เห็นข้อมูลทั้งวิทยาลัย';

alter table auth_policy
  add column if not exists mfa_max_attempts smallint not null default 5
    check (mfa_max_attempts between 1 and 20);
alter table auth_policy
  add column if not exists mfa_lockout_minutes smallint not null default 15
    check (mfa_lockout_minutes between 1 and 1440);

-- ───────────────────────────────────────────────────────────────────
-- ความลับ TOTP
-- ───────────────────────────────────────────────────────────────────
create table mfa_credential (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  person_id      uuid        not null references person on delete restrict,

  -- เข้ารหัสที่ชั้นแอปด้วยกุญแจนอกฐานข้อมูล ฐานข้อมูลไม่เคยเห็นค่าจริง
  secret_enc     bytea       not null,

  confirmed_at   timestamptz,
  -- ช่วงเวลา TOTP ล่าสุดที่ใช้ไปแล้ว — กันการใช้รหัสเดิมซ้ำ
  last_step      bigint,
  failed_attempts smallint   not null default 0,
  locked_until   timestamptz,
  created_at     timestamptz not null default now(),
  disabled_at    timestamptz,
  disabled_by    uuid        references person on delete restrict,

  unique (person_id)
);

comment on table mfa_credential is
  'ความลับ TOTP ของผู้ใช้หนึ่งคน — ค่าจริงเข้ารหัสด้วยกุญแจนอกฐานข้อมูล';
comment on column mfa_credential.last_step is
  'ช่วงเวลา TOTP ล่าสุดที่ใช้ไปแล้ว รับเฉพาะช่วงที่ใหม่กว่า มิฉะนั้นรหัสที่ถูกแอบเห็นใช้ซ้ำได้';

create index mfa_credential_person_idx on mfa_credential (institution_id, person_id)
  where disabled_at is null;

-- ───────────────────────────────────────────────────────────────────
-- รหัสกู้คืน
-- ───────────────────────────────────────────────────────────────────
create table mfa_recovery_code (
  id            uuid        primary key default gen_random_uuid(),
  credential_id uuid        not null references mfa_credential on delete cascade,
  code_hash     bytea       not null,
  used_at       timestamptz,
  used_ip_hash  bytea,
  created_at    timestamptz not null default now(),
  unique (credential_id, code_hash)
);

comment on table mfa_recovery_code is
  'รหัสกู้คืนใช้ครั้งเดียว เก็บเฉพาะค่าแฮช — หลักเดียวกับรหัสรีเซ็ตรหัสผ่าน (0025)';

-- ───────────────────────────────────────────────────────────────────
-- บทบาทนี้ต้องยืนยันสองชั้นหรือไม่
-- ───────────────────────────────────────────────────────────────────
create or replace function mfa_required_for(p_institution_id uuid, p_role text)
returns boolean language sql stable as $$
  select coalesce(
    (select p_role = any(ap.require_mfa_roles)
       from auth_policy ap where ap.institution_id = p_institution_id),
    p_role in ('admin', 'director'));
$$;

comment on function mfa_required_for(uuid, text) is
  'บทบาทนี้ต้องยืนยันสองชั้นไหม — ค่าเริ่มต้นครอบ admin/director แม้วิทยาลัยยังไม่ได้ตั้งนโยบาย';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจรหัส TOTP
--
-- ชั้นแอปคำนวณว่ารหัสตรงหรือไม่ (p_matched) แล้วส่งช่วงเวลามาให้
-- ฟังก์ชันนี้ตัดสินขั้นสุดท้าย เพราะสามเรื่องนี้ต้องอะตอมมิก —
-- การล็อก การกันใช้ซ้ำ และการนับครั้งที่ผิด
--
-- **ห้าม raise** มิฉะนั้นตัวนับจะถูก rollback แล้วเดารหัสได้ไม่จำกัด
-- ───────────────────────────────────────────────────────────────────
create or replace function mfa_verify_step(
  p_person_id uuid,
  p_step      bigint,
  p_matched   boolean
) returns table (
  ok               boolean,
  reason           text,
  retry_after_secs integer
) language plpgsql as $$
declare
  v_cred    mfa_credential;
  v_max     smallint;
  v_lock    smallint;
begin
  select * into v_cred from mfa_credential
   where person_id = p_person_id and disabled_at is null;

  if v_cred.id is null then
    return query select false, 'ยังไม่ได้ตั้งค่าการยืนยันตัวตนสองชั้น'::text, 0;
    return;
  end if;

  select coalesce(ap.mfa_max_attempts, 5), coalesce(ap.mfa_lockout_minutes, 15)
    into v_max, v_lock
    from auth_policy ap where ap.institution_id = v_cred.institution_id;
  v_max  := coalesce(v_max, 5);
  v_lock := coalesce(v_lock, 15);

  if v_cred.locked_until is not null and v_cred.locked_until > now() then
    return query select false, 'ใส่รหัสผิดหลายครั้ง ถูกระงับชั่วคราว'::text,
      ceil(extract(epoch from (v_cred.locked_until - now())))::integer;
    return;
  end if;

  if not p_matched then
    update mfa_credential
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= v_max then now() + (v_lock || ' minutes')::interval
             else locked_until end
     where id = v_cred.id;

    return query select false, 'รหัสยืนยันไม่ถูกต้อง'::text, 0;
    return;
  end if;

  -- รหัสถูก แต่เป็นช่วงเวลาที่ใช้ไปแล้ว = มีคนดักรหัสมาใช้ซ้ำ
  --
  -- นับเป็นความพยายามที่ผิดด้วย เพราะเจ้าของตัวจริงไม่มีทางส่งรหัสของ
  -- ช่วงเวลาที่ผ่านไปแล้ว — แอปของเขาแสดงรหัสปัจจุบันเสมอ
  if v_cred.last_step is not null and p_step <= v_cred.last_step then
    update mfa_credential
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= v_max then now() + (v_lock || ' minutes')::interval
             else locked_until end
     where id = v_cred.id;

    return query select false, 'รหัสนี้ถูกใช้ไปแล้ว รอรหัสถัดไป'::text, 0;
    return;
  end if;

  update mfa_credential
     set last_step = p_step, failed_attempts = 0, locked_until = null
   where id = v_cred.id;

  return query select true, null::text, 0;
end $$;

comment on function mfa_verify_step(uuid, bigint, boolean) is
  'ตัดสินผลการยืนยันสองชั้น — คุมการล็อก การกันใช้รหัสซ้ำ และตัวนับ ห้าม raise เพราะตัวนับจะถูก rollback';

-- ───────────────────────────────────────────────────────────────────
-- ใช้รหัสกู้คืน
--
-- ค้นจากเจ้าของก่อนแล้วค่อยเทียบค่าแฮช เหตุผลเดียวกับ consume_password_reset —
-- ถ้าค้นจากค่าแฮชตรง ๆ การเดาผิดจะไม่เจอแถวใดเลย แล้วตัวนับไม่ขยับ
-- ───────────────────────────────────────────────────────────────────
create or replace function mfa_consume_recovery(
  p_person_id uuid,
  p_code_hash bytea,
  p_ip_hash   bytea default null
) returns table (
  ok     boolean,
  reason text,
  remaining integer
) language plpgsql as $$
declare
  v_cred mfa_credential;
  v_id   uuid;
  v_max  smallint;
  v_lock smallint;
begin
  select * into v_cred from mfa_credential
   where person_id = p_person_id and disabled_at is null;

  if v_cred.id is null then
    return query select false, 'ยังไม่ได้ตั้งค่าการยืนยันตัวตนสองชั้น'::text, 0;
    return;
  end if;

  select coalesce(ap.mfa_max_attempts, 5), coalesce(ap.mfa_lockout_minutes, 15)
    into v_max, v_lock
    from auth_policy ap where ap.institution_id = v_cred.institution_id;
  v_max  := coalesce(v_max, 5);
  v_lock := coalesce(v_lock, 15);

  if v_cred.locked_until is not null and v_cred.locked_until > now() then
    return query select false, 'ใส่รหัสผิดหลายครั้ง ถูกระงับชั่วคราว'::text, 0;
    return;
  end if;

  select rc.id into v_id
    from mfa_recovery_code rc
   where rc.credential_id = v_cred.id
     and rc.code_hash = p_code_hash
     and rc.used_at is null;

  if v_id is null then
    update mfa_credential
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= v_max then now() + (v_lock || ' minutes')::interval
             else locked_until end
     where id = v_cred.id;

    return query select false, 'รหัสกู้คืนไม่ถูกต้องหรือถูกใช้ไปแล้ว'::text, 0;
    return;
  end if;

  update mfa_recovery_code
     set used_at = now(), used_ip_hash = p_ip_hash
   where id = v_id;

  update mfa_credential
     set failed_attempts = 0, locked_until = null
   where id = v_cred.id;

  return query select true, null::text,
    (select count(*)::integer from mfa_recovery_code rc
      where rc.credential_id = v_cred.id and rc.used_at is null);
end $$;

comment on function mfa_consume_recovery(uuid, bytea, bytea) is
  'ใช้รหัสกู้คืนหนึ่งครั้ง — ใช้ซ้ำไม่ได้ และเดาผิดถูกนับเข้าตัวนับเดียวกับรหัส TOTP';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ตารางนี้ถูกอ่านตอนล็อกอิน ซึ่งบริบทเป็นบทบาท auth เหมือน user_credential
-- ───────────────────────────────────────────────────────────────────
alter table mfa_credential enable row level security;
alter table mfa_credential force  row level security;
create policy tenant_isolation on mfa_credential
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- เจ้าของเห็นและจัดการของตัวเองได้ · admin ปิดให้คนอื่นได้เมื่อโทรศัพท์หาย
-- · บทบาท auth อ่านได้ตอนล็อกอิน
create policy mfa_credential_scope on mfa_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  );

alter table mfa_recovery_code enable row level security;
alter table mfa_recovery_code force  row level security;
create policy tenant_isolation on mfa_recovery_code
  using (exists (select 1 from mfa_credential mc
                  where mc.id = mfa_recovery_code.credential_id
                    and mc.institution_id = current_institution_id()));

create policy mfa_recovery_code_scope on mfa_recovery_code
  as restrictive
  using (
    current_app_role() = 'auth'
    or exists (select 1 from mfa_credential mc
                where mc.id = mfa_recovery_code.credential_id
                  and mc.person_id = current_actor_id())
  );

commit;

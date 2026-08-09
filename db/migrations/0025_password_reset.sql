-- ═══════════════════════════════════════════════════════════════════
-- 0025_password_reset.sql
--
-- การรีเซ็ตรหัสผ่านด้วยรหัสใช้ครั้งเดียว
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- ก่อนหน้านี้ทางเดียวที่คนลืมรหัสผ่านจะกลับเข้าระบบได้คือให้งานทะเบียนเรียก
-- POST /auth/credentials ออกรหัสผ่านชั่วคราวให้ใหม่ ซึ่งมีปัญหาสองอย่าง
--
--   1. เจ้าหน้าที่ **รู้รหัสผ่านของนักศึกษา** ตั้งแต่วินาทีที่ออกให้
--      จนถึงตอนที่นักศึกษาเข้ามาเปลี่ยน ช่วงนั้นเข้าระบบแทนกันได้จริง
--      และบันทึกการเข้าถึงจะระบุว่าเป็นฝีมือของนักศึกษา ไม่ใช่เจ้าหน้าที่
--   2. ต้องเดินไปที่งานทะเบียนเท่านั้น เพราะบอกรหัสผ่านทางโทรศัพท์
--      แล้วปล่อยให้ใช้ได้ตลอดไปนั้นยอมรับไม่ได้
--
-- ไฟล์นี้เปลี่ยนของที่ส่งมอบจาก "รหัสผ่าน" เป็น "รหัสรีเซ็ต" ที่
-- ใช้ได้ครั้งเดียว หมดอายุใน 30 นาที และ **ตั้งรหัสผ่านใหม่โดยเจ้าตัวเอง**
-- เจ้าหน้าที่จึงไม่มีวันรู้รหัสผ่านของใคร และบอกรหัสรีเซ็ตทางโทรศัพท์ได้
--
-- ─── ทำไมรหัสสั้นแทนลิงก์ยาว ───
-- นักศึกษาอาชีวะจำนวนมากไม่มีอีเมลของตัวเองตอนเข้าเรียน (เหตุผลเดียวกับที่
-- ชื่อผู้ใช้เป็นรหัสประจำตัวไม่ใช่อีเมล ดู 0014) ลิงก์รีเซ็ตทางอีเมลจึง
-- ครอบคลุมคนไม่ถึงครึ่ง รหัสสั้นที่อ่านให้ฟังทางโทรศัพท์หรือส่ง SMS ได้
-- ครอบคลุมทุกคน และยังใช้กับช่องทางอีเมลได้ด้วยเมื่อมีอีเมลบันทึกไว้
--
-- ─── ทำไมเก็บเฉพาะค่าแฮชของรหัส ───
-- หลักเดียวกับ refresh token — ถ้าฐานข้อมูลรั่ว ผู้โจมตีต้องไม่ได้อะไรไป
-- ชั้น API แฮชด้วยกุญแจที่อยู่นอกฐานข้อมูลก่อนส่งมาเก็บ (แบบเดียวกับ ip_hash)
-- เพราะรหัสแปดตัวอักษรที่แฮชด้วย sha256 เปล่า ๆ ถอดกลับได้ในไม่กี่วินาที
-- ด้วยการไล่เดาทุกความเป็นไปได้ ซึ่งจะทำให้ตารางนี้กลายเป็นจุดที่อ่อนที่สุด
-- ของทั้งระบบแทนที่จะเป็นจุดที่แข็งที่สุด
--
-- ─── ทำไมฟังก์ชันคืนค่าแทนที่จะ raise ───
-- ผลข้างเคียงด้านความปลอดภัยต้องคงอยู่แม้คำขอจะล้มเหลว — ตัวนับจำนวนครั้ง
-- ที่เดารหัสผิด และการเพิกถอนรหัสที่ถูกเดาจนครบโควตา ถ้าฟังก์ชัน raise
-- ฐานข้อมูลจะ rollback ทั้ง transaction ผลคือ **เดารหัสได้ไม่จำกัดครั้ง**
-- โดยที่ตัวนับไม่เคยขยับเลย ซึ่งเป็นกับดักเดียวกับที่ 0021 และ auth.service
-- อธิบายไว้ ชั้น API จึงต้องอ่านค่าที่คืนมาแล้วค่อยโยนข้อผิดพลาดเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ช่องทางส่งรหัสรีเซ็ต
--
-- staff_counter คือเจ้าหน้าที่ยืนยันตัวตนแล้วส่งมอบรหัสให้เอง ต่อหน้าหรือ
-- ทางโทรศัพท์ เก็บแยกจากช่องทางอัตโนมัติเพราะต้องตอบผู้ตรวจสอบได้ว่า
-- ครั้งไหนมีมนุษย์เป็นผู้ยืนยันตัวตน และเป็นใคร
-- ───────────────────────────────────────────────────────────────────
create type password_reset_channel as enum ('staff_counter', 'email', 'sms');

-- ───────────────────────────────────────────────────────────────────
-- นโยบายเพิ่มเติม — ต่อจาก 0014 และ 0021
-- ───────────────────────────────────────────────────────────────────
alter table auth_policy
  add column if not exists reset_code_minutes    smallint not null default 30,
  add column if not exists reset_code_attempts   smallint not null default 5,
  add column if not exists max_reset_per_day     smallint not null default 3,
  add column if not exists max_reset_per_ip_day  smallint not null default 15;

comment on column auth_policy.reset_code_minutes is
  'อายุของรหัสรีเซ็ต — สั้นพอที่รหัสซึ่งบอกทางโทรศัพท์แล้วมีคนได้ยินจะหมดอายุก่อนถูกใช้';
comment on column auth_policy.reset_code_attempts is
  'จำนวนครั้งที่กรอกรหัสผิดได้ก่อนรหัสนั้นถูกเพิกถอน — รหัสสั้นไม่มีตัวนับนี้เท่ากับเดาได้ไม่จำกัด';
comment on column auth_policy.max_reset_per_ip_day is
  'เพดานรายไอพี — กันการยิงขอรีเซ็ตให้คนทั้งวิทยาลัยจนค่า SMS บานปลายและกล่องข้อความของผู้ใช้เต็ม';

-- ───────────────────────────────────────────────────────────────────
-- คำขอรีเซ็ตรหัสผ่าน
--
-- ทุกแถวอยู่ต่อไปแม้ใช้ไปแล้วหรือหมดอายุแล้ว เพราะเป็นหลักฐานว่าใคร
-- ขอรีเซ็ตบัญชีของใครเมื่อไร ซึ่งเป็นคำถามแรกเวลาสงสัยว่าบัญชีถูกยึด
-- การล้างทำโดย purge_password_reset() ตามระยะเก็บเท่านั้น
-- ───────────────────────────────────────────────────────────────────
create table password_reset (
  id                uuid  primary key default gen_random_uuid(),
  institution_id    uuid  not null references institution    on delete cascade,
  person_id         uuid  not null references person         on delete cascade,
  credential_id     uuid  not null references user_credential on delete cascade,

  -- HMAC-SHA256 ของรหัสที่ normalize แล้ว กุญแจอยู่ในชั้น API ไม่ใช่ในนี้
  token_hash        bytea not null,

  channel           password_reset_channel not null,

  -- 'so***@example.com' หรือ '08******78' — ไว้ให้เจ้าหน้าที่ยืนยันปลายทาง
  -- โดยไม่ต้องเปิดดูข้อมูลติดต่อจริงของนักศึกษา
  destination_hint  text,

  issued_by         uuid  references staff,   -- เฉพาะช่องทางเคาน์เตอร์
  requested_ip_hash bytea,                    -- แฮชเหมือน login_attempt ตาม PDPA

  attempts          smallint    not null default 0,
  expires_at        timestamptz not null,
  consumed_at       timestamptz,
  revoked_at        timestamptz,
  revoke_reason     text,
  created_at        timestamptz not null default now(),

  check (expires_at > created_at),
  check (revoked_at is null or revoke_reason is not null),

  -- ช่องทางเคาน์เตอร์ต้องรู้ว่าเจ้าหน้าที่คนไหนเป็นผู้ยืนยันตัวตน
  -- ถ้าไม่บังคับ บันทึกจะตอบไม่ได้ว่าใครปล่อยรหัสออกไป ซึ่งเป็นข้อมูล
  -- ชิ้นเดียวที่มีค่าจริงเวลาสอบสวนกรณีบัญชีถูกยึด
  check (channel <> 'staff_counter' or issued_by is not null),

  unique (token_hash)
);

-- ค้นรหัสที่ยังใช้ได้ของคนหนึ่ง — ทุกครั้งที่มีคนกรอกรหัสจะยิง query นี้
create index password_reset_active_idx
  on password_reset (person_id, created_at desc)
  where consumed_at is null and revoked_at is null;

-- นับโควตารายวันของคนหนึ่งและของไอพีหนึ่ง
create index password_reset_person_day_idx on password_reset (person_id, created_at desc);
create index password_reset_ip_day_idx
  on password_reset (institution_id, requested_ip_hash, created_at desc)
  where requested_ip_hash is not null;

-- ล้างของเก่าตามระยะเก็บ
create index password_reset_created_idx on password_reset (created_at);

comment on table password_reset is
  'คำขอรีเซ็ตรหัสผ่าน เก็บเฉพาะค่าแฮชของรหัส — ใครขอรีเซ็ตบัญชีของใครเมื่อไร เป็นคำถามแรกเวลาสงสัยว่าบัญชีถูกยึด';
comment on column password_reset.token_hash is
  'HMAC-SHA256 ของรหัสรีเซ็ต กุญแจอยู่นอกฐานข้อมูล — sha256 เปล่า ๆ ของรหัสแปดตัวถอดกลับได้ในไม่กี่วินาที';

-- ───────────────────────────────────────────────────────────────────
-- ห้ามเขียนทับประวัติ
--
-- แถวที่ใช้ไปแล้วต้องแตะไม่ได้อีก และสาระสำคัญของคำขอต้องแก้ย้อนหลังไม่ได้
-- มิฉะนั้นคนที่เขียนตารางนี้ได้จะ "ต่ออายุ" รหัสของตัวเอง หรือย้ายรหัสที่
-- ตัวเองรู้ไปผูกกับบัญชีคนอื่นได้ ซึ่งทำให้ทั้งกลไกไม่มีความหมาย
-- ───────────────────────────────────────────────────────────────────
create or replace function password_reset_guard() returns trigger
language plpgsql as $$
begin
  if old.consumed_at is not null then
    raise exception 'รหัสรีเซ็ตที่ใช้ไปแล้วแก้ไขไม่ได้';
  end if;

  if new.institution_id is distinct from old.institution_id
     or new.person_id     is distinct from old.person_id
     or new.credential_id is distinct from old.credential_id
     or new.token_hash    is distinct from old.token_hash
     or new.channel       is distinct from old.channel
     or new.expires_at    is distinct from old.expires_at
     or new.created_at    is distinct from old.created_at then
    raise exception 'แก้สาระสำคัญของคำขอรีเซ็ตรหัสผ่านย้อนหลังไม่ได้ ให้ออกคำขอใหม่แทน';
  end if;

  return new;
end $$;

create trigger password_reset_no_rewrite before update on password_reset
  for each row execute function password_reset_guard();

-- ───────────────────────────────────────────────────────────────────
-- ปิดบังปลายทางก่อนแสดงให้เจ้าหน้าที่เห็น
--
-- งานทะเบียนต้องยืนยันได้ว่า "รหัสถูกส่งไปที่เบอร์ที่ลงท้าย 78 ใช่ไหม"
-- โดยไม่ต้องเปิดดูเบอร์เต็มของนักศึกษา ซึ่งเป็นหลักการเก็บข้อมูลเท่าที่
-- จำเป็นตาม PDPA มาตรา 22
-- ───────────────────────────────────────────────────────────────────
create or replace function mask_destination(
  p_value   text,
  p_channel password_reset_channel
) returns text
language sql immutable as $$
  select case
    when p_value is null then null
    when p_channel = 'email' and position('@' in p_value) > 0 then
      -- เก็บสองตัวแรกของชื่อกล่องไว้ให้จำได้ ที่เหลือปิดหมด โดเมนไม่ปิด
      -- เพราะโดเมนไม่ได้ระบุตัวบุคคล และช่วยให้ผู้ใช้รู้ว่าต้องไปเปิดกล่องไหน
      left(split_part(p_value, '@', 1), 2)
        || repeat('*', greatest(length(split_part(p_value, '@', 1)) - 2, 1))
        || '@' || split_part(p_value, '@', 2)
    when p_channel = 'sms' then
      left(p_value, 2)
        || repeat('*', greatest(length(p_value) - 4, 1))
        || right(p_value, 2)
    else null
  end
$$;

-- ───────────────────────────────────────────────────────────────────
-- ขอรหัสรีเซ็ต
--
-- p_channel เป็น null แปลว่า "ให้ระบบเลือกจากช่องทางที่บันทึกไว้"
-- ซึ่งเป็นกรณีที่ผู้ใช้กดขอเอง ส่วนช่องทางเคาน์เตอร์ต้องระบุมาชัดเจน
-- พร้อม person_id ของเจ้าหน้าที่ผู้ยืนยันตัวตน
--
-- คืน issued = false พร้อมเหตุผลเสมอ ไม่ raise เพราะชั้น API ต้องตอบ
-- ข้อความเดียวกันทุกกรณีเพื่อไม่ให้บอกได้ว่ารหัสประจำตัวไหนมีอยู่จริง
-- แต่ยังต้องเขียนบันทึกและนับโควตาให้ติดถาวรก่อนตอบกลับ
-- ───────────────────────────────────────────────────────────────────
create or replace function request_password_reset(
  p_institution_id uuid,
  p_username       text,
  p_channel        password_reset_channel,
  p_token_hash     bytea,
  p_ip_hash        bytea default null,
  p_issued_by      uuid  default null
) returns table (
  issued           boolean,
  reason           text,
  person_id        uuid,
  channel          password_reset_channel,
  destination_hint text,
  expires_at       timestamptz
)
language plpgsql as $$
declare
  v_cred        record;
  v_person      record;
  v_minutes     smallint;
  v_per_day     smallint;
  v_per_ip_day  smallint;
  v_channel     password_reset_channel;
  v_destination text;
  v_hint        text;
  v_staff_id    uuid;
  v_expires     timestamptz;
  v_count       integer;
begin
  issued := false;
  reason := null;
  person_id := null;
  channel := null;
  destination_hint := null;
  expires_at := null;

  select coalesce(ap.reset_code_minutes, 30),
         coalesce(ap.max_reset_per_day, 3),
         coalesce(ap.max_reset_per_ip_day, 15)
    into v_minutes, v_per_day, v_per_ip_day
    from auth_policy ap where ap.institution_id = p_institution_id;

  -- สถานศึกษาที่ยังไม่ได้ตั้งนโยบายใช้ค่าเริ่มต้นที่ปลอดภัย ไม่ใช่ปล่อยผ่าน
  v_minutes    := coalesce(v_minutes, 30);
  v_per_day    := coalesce(v_per_day, 3);
  v_per_ip_day := coalesce(v_per_ip_day, 15);

  -- ── เพดานรายไอพี ต้องตรวจก่อนแตะบัญชีใด ๆ ────────────────────
  --
  -- ตรวจก่อนค้นหาบัญชีโดยเจตนา เพราะการยิงขอรีเซ็ตรัว ๆ ให้คนทั้งวิทยาลัย
  -- ทำให้ค่า SMS บานปลายและกล่องข้อความของผู้ใช้เต็ม โดยที่โควตารายคน
  -- กันไม่ได้เลย — แต่ละบัญชีถูกขอแค่ครั้งเดียว หลักเดียวกับ 0021
  --
  -- ─── ทำไมยกเว้นช่องทางเคาน์เตอร์ ───
  -- คำขอของงานทะเบียนออกจากเครื่องเดียวกันทั้งวัน ช่วงเปิดเทอมวันเดียว
  -- อาจเป็นร้อยราย ถ้านับรวมด้วย เคาน์เตอร์จะตันตั้งแต่สายและเจ้าหน้าที่
  -- จะกลับไปใช้วิธีตั้งรหัสผ่านให้เองซึ่งเป็นสิ่งที่ไฟล์นี้ต้องการเลิก
  -- ที่สำคัญคือช่องทางนี้มีมนุษย์ยืนยันตัวตนทุกครั้งและมีชื่อกำกับอยู่แล้ว
  if p_ip_hash is not null and coalesce(p_channel, 'email') <> 'staff_counter' then
    select count(*) into v_count
      from password_reset pr
     where pr.institution_id    = p_institution_id
       and pr.requested_ip_hash = p_ip_hash
       and pr.created_at > now() - interval '1 day';

    if v_count >= v_per_ip_day then
      reason := 'ขอรีเซ็ตจากที่อยู่นี้บ่อยเกินกำหนด';
      return next;
      return;
    end if;
  end if;

  select uc.id, uc.person_id, uc.disabled_at
    into v_cred
    from user_credential uc
   where uc.institution_id = p_institution_id
     and uc.username       = p_username;

  if v_cred is null then
    reason := 'ไม่พบรหัสประจำตัว';
    return next;
    return;
  end if;

  if v_cred.disabled_at is not null then
    -- บัญชีที่ถูกระงับต้องกู้คืนโดยเจ้าหน้าที่เท่านั้น การรีเซ็ตรหัสผ่าน
    -- ไม่ควรเป็นทางลัดที่ทำให้บัญชีซึ่งถูกสั่งระงับกลับมาใช้ได้เอง
    person_id := v_cred.person_id;
    reason := 'บัญชีถูกระงับ';
    return next;
    return;
  end if;

  -- ── เพดานรายบัญชี ────────────────────────────────────────────
  --
  -- ยกเว้นช่องทางเคาน์เตอร์ด้วยเหตุผลเดียวกับเพดานรายไอพี บวกอีกข้อ —
  -- คนที่มาถึงเคาน์เตอร์แล้วกรอกรหัสผิดจนถูกยกเลิก ทำกระดาษหาย แล้วมาใหม่
  -- จะติดเพดานตั้งแต่ครั้งที่สี่และไม่มีทางออกเลยจนกว่าจะพ้นยี่สิบสี่ชั่วโมง
  -- ซึ่งแย่กว่าความเสี่ยงที่เพดานนี้กันได้ เพราะทุกใบมีชื่อเจ้าหน้าที่กำกับอยู่แล้ว
  if p_channel is distinct from 'staff_counter' then
    select count(*) into v_count
      from password_reset pr
     where pr.person_id = v_cred.person_id
       and pr.created_at > now() - interval '1 day';

    if v_count >= v_per_day then
      person_id := v_cred.person_id;
      reason := 'ขอรีเซ็ตบัญชีนี้บ่อยเกินกำหนด';
      return next;
      return;
    end if;
  end if;

  -- ── เลือกช่องทางส่ง ──────────────────────────────────────────
  select p.email, p.phone into v_person
    from person p where p.id = v_cred.person_id;

  if p_channel = 'staff_counter' then
    select st.id into v_staff_id
      from staff st
     where st.person_id     = p_issued_by
       and st.institution_id = p_institution_id
       and st.active;

    if v_staff_id is null then
      person_id := v_cred.person_id;
      reason := 'ผู้ออกรหัสไม่ใช่บุคลากรที่ยังปฏิบัติงานอยู่';
      return next;
      return;
    end if;
    v_channel := 'staff_counter';
    v_hint := null;
  else
    -- ผู้ใช้กดขอเอง — ใช้ช่องทางที่ระบุ ถ้าไม่ระบุให้เลือกอีเมลก่อน
    -- เพราะส่งฟรีและมีร่องรอยให้ผู้ใช้ตรวจย้อนหลังได้ ต่างจาก SMS
    v_channel := coalesce(
      p_channel,
      case when nullif(trim(coalesce(v_person.email, '')), '') is not null then 'email'::password_reset_channel
           when nullif(trim(coalesce(v_person.phone, '')), '') is not null then 'sms'::password_reset_channel
      end
    );

    v_destination := case v_channel
                       when 'email' then nullif(trim(coalesce(v_person.email, '')), '')
                       when 'sms'   then nullif(trim(coalesce(v_person.phone, '')), '')
                     end;

    if v_destination is null then
      -- ไม่มีช่องทางติดต่อที่บันทึกไว้ — ต้องไปที่งานทะเบียน
      -- ตอบตามความจริงตรงนี้ แต่ชั้น API จะกลบเป็นข้อความกลางก่อนส่งออก
      person_id := v_cred.person_id;
      reason := 'ไม่มีช่องทางติดต่อที่บันทึกไว้';
      return next;
      return;
    end if;

    v_hint := mask_destination(v_destination, v_channel);
  end if;

  -- ── เพิกถอนรหัสเดิมที่ยังค้างอยู่ ─────────────────────────────
  --
  -- ต้องเหลือรหัสที่ใช้ได้ครั้งละหนึ่งใบเท่านั้น ถ้าปล่อยให้ค้างหลายใบ
  -- ผู้โจมตีที่กดขอซ้ำ ๆ จะได้พื้นที่เดาเพิ่มเป็นเท่าตัวตามจำนวนใบ
  -- ทั้งที่ตัวนับจำนวนครั้งของแต่ละใบยังไม่ถูกแตะเลย
  update password_reset pr
     set revoked_at = now(),
         revoke_reason = 'ออกรหัสใหม่ทับ'
   where pr.person_id   = v_cred.person_id
     and pr.consumed_at is null
     and pr.revoked_at  is null;

  v_expires := now() + make_interval(mins => v_minutes);

  insert into password_reset
    (institution_id, person_id, credential_id, token_hash, channel,
     destination_hint, issued_by, requested_ip_hash, expires_at)
  values
    (p_institution_id, v_cred.person_id, v_cred.id, p_token_hash, v_channel,
     v_hint, v_staff_id, p_ip_hash, v_expires);

  issued := true;
  person_id := v_cred.person_id;
  channel := v_channel;
  destination_hint := v_hint;
  expires_at := v_expires;
  return next;
end $$;

comment on function request_password_reset(uuid, text, password_reset_channel, bytea, bytea, uuid) is
  'ออกรหัสรีเซ็ตหนึ่งใบ เพิกถอนใบเดิมที่ค้างอยู่ — คืนเหตุผลแทนการ raise เพราะโควตาและบันทึกต้องติดถาวรแม้คำขอจะถูกปฏิเสธ';

-- ───────────────────────────────────────────────────────────────────
-- ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่
--
-- ค้นแถวจาก "รหัสประจำตัว" ก่อน แล้วค่อยเทียบค่าแฮช ไม่ใช่ค้นจากค่าแฮช
-- ตรง ๆ เพราะการค้นจากค่าแฮชทำให้รหัสที่กรอกผิดไม่ตรงกับแถวใด จึงไม่มี
-- แถวไหนให้เพิ่มตัวนับ ผลคือเดารหัสแปดตัวได้ไม่จำกัดครั้งจนกว่าจะหมดอายุ
--
-- must_change ตั้งเป็น false เพราะรหัสผ่านที่ได้มาเจ้าตัวเป็นคนพิมพ์เอง
-- ไม่มีใครอื่นรู้ ต่างจากรหัสชั่วคราวที่เจ้าหน้าที่ออกให้ซึ่งต้องบังคับเปลี่ยน
-- ───────────────────────────────────────────────────────────────────
create or replace function consume_password_reset(
  p_institution_id uuid,
  p_username       text,
  p_token_hash     bytea,
  p_new_hash       text
) returns table (
  ok            boolean,
  reason        text,
  person_id     uuid,
  attempts_left integer
)
language plpgsql as $$
declare
  v_cred     record;
  v_reset    record;
  v_max      smallint;
  v_attempts smallint;
begin
  ok := false;
  reason := null;
  person_id := null;
  attempts_left := 0;

  select coalesce(ap.reset_code_attempts, 5) into v_max
    from auth_policy ap where ap.institution_id = p_institution_id;
  v_max := coalesce(v_max, 5);

  select uc.id, uc.person_id, uc.disabled_at
    into v_cred
    from user_credential uc
   where uc.institution_id = p_institution_id
     and uc.username       = p_username;

  if v_cred is null or v_cred.disabled_at is not null then
    reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    return next;
    return;
  end if;

  select pr.id, pr.token_hash, pr.attempts, pr.expires_at
    into v_reset
    from password_reset pr
   where pr.person_id   = v_cred.person_id
     and pr.consumed_at is null
     and pr.revoked_at  is null
   order by pr.created_at desc
   limit 1;

  if v_reset is null then
    reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    return next;
    return;
  end if;

  if v_reset.expires_at <= now() then
    -- เพิกถอนทิ้งเลย เพื่อไม่ให้แถวที่หมดอายุค้างเป็นเป้าให้เดาต่อ
    -- และเพื่อให้การขอใบใหม่ไม่ต้องรอให้ใบเก่าถูกเก็บกวาด
    update password_reset pr
       set revoked_at = now(), revoke_reason = 'หมดอายุ'
     where pr.id = v_reset.id;
    reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    return next;
    return;
  end if;

  -- ── เพิ่มตัวนับก่อนเทียบเสมอ ─────────────────────────────────
  --
  -- ถ้าเพิ่มหลังเทียบแล้วรีบ return ตัวนับจะขยับเฉพาะตอนเดาถูก
  -- ซึ่งเท่ากับไม่มีตัวนับ
  v_attempts := v_reset.attempts + 1;
  update password_reset pr set attempts = v_attempts where pr.id = v_reset.id;

  if v_reset.token_hash is distinct from p_token_hash then
    if v_attempts >= v_max then
      update password_reset pr
         set revoked_at = now(),
             revoke_reason = 'กรอกรหัสผิดครบจำนวนที่กำหนด'
       where pr.id = v_reset.id;
      reason := 'กรอกรหัสรีเซ็ตผิดหลายครั้ง รหัสนี้ถูกยกเลิกแล้ว ต้องขอใหม่';
    else
      reason := 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว';
    end if;
    attempts_left := greatest(v_max - v_attempts, 0);
    return next;
    return;
  end if;

  -- ── ถูกต้อง ──────────────────────────────────────────────────
  update password_reset pr set consumed_at = now() where pr.id = v_reset.id;

  update user_credential uc
     set password_hash       = p_new_hash,
         must_change         = false,
         failed_attempts     = 0,
         locked_until        = null,   -- คนที่ถูกล็อกเพราะจำรหัสไม่ได้ต้องกลับเข้าได้
         password_changed_at = now()
   where uc.id = v_cred.id;

  -- ตั้งรหัสผ่านใหม่แล้วต้องเตะทุกอุปกรณ์ออก หลักเดียวกับการเปลี่ยนรหัสผ่าน
  -- และสำคัญกว่าด้วย เพราะเหตุผลที่ต้องรีเซ็ตมักคือสงสัยว่าบัญชีถูกยึดไปแล้ว
  update auth_session s
     set revoked_at = now(), revoke_reason = 'รีเซ็ตรหัสผ่าน'
   where s.person_id = v_cred.person_id
     and s.revoked_at is null;

  ok := true;
  person_id := v_cred.person_id;
  attempts_left := v_max;
  return next;
end $$;

comment on function consume_password_reset(uuid, text, bytea, text) is
  'ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่ — ปลดล็อกบัญชี ล้างตัวนับรหัสผิด และเพิกถอนทุก session';

-- ───────────────────────────────────────────────────────────────────
-- ล้างคำขอที่เกินระยะเก็บ — ตั้งเป็นงานประจำวันเหมือน purge_login_attempts
-- ───────────────────────────────────────────────────────────────────
create or replace function purge_password_reset(p_keep_days integer default 90)
returns integer language plpgsql as $$
declare v_n integer;
begin
  if p_keep_days < 90 then
    raise exception 'ระยะเก็บบันทึกคำขอรีเซ็ตรหัสผ่านต่ำกว่า 90 วันไม่ได้ตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26';
  end if;
  delete from password_reset where created_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ตารางนี้อ่อนไหวเท่า user_credential — คนที่อ่านได้จะรู้ว่าบัญชีไหน
-- กำลังมีรหัสรีเซ็ตค้างอยู่ ซึ่งเป็นข้อมูลที่ใช้เลือกเป้าหมายได้โดยตรง
-- ───────────────────────────────────────────────────────────────────
alter table password_reset enable row level security;
alter table password_reset force  row level security;

create policy tenant_isolation on password_reset
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- บทบาท auth ใช้ได้เฉพาะช่วงขอและใช้รหัสรีเซ็ต · งานทะเบียนดูได้เพื่อช่วย
-- ผู้ใช้ที่โทรมาถาม · เจ้าตัวเห็นของตัวเองได้ ตรงกับ credential_scope ของ 0014
create policy reset_scope on password_reset
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

-- ลบได้เฉพาะแถวที่เกินระยะเก็บแล้ว — แม้แต่ admin ก็ลบคำขอของเมื่อวานไม่ได้
--
-- ต้องเขียนเป็นนโยบายไม่ใช่ปล่อยว่าง เพราะ force row level security
-- มีผลกับเจ้าของตารางด้วย ถ้าไม่มีนโยบาย delete เลย purge_password_reset()
-- จะลบไม่ได้สักแถวและตารางจะโตไปเรื่อย ๆ (กับดักเดียวกับ access_log ใน 0022)
create policy reset_purge_aged on password_reset
  as restrictive for delete
  using (created_at < now() - interval '90 days');

-- ───────────────────────────────────────────────────────────────────
-- สิทธิ์ — ต้องให้หลังสร้างตารางใหม่ เพราะ roles.sql รันไปก่อนหน้านี้แล้ว
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on password_reset to app_runtime;
    grant execute on function request_password_reset(uuid, text, password_reset_channel, bytea, bytea, uuid) to app_runtime;
    grant execute on function consume_password_reset(uuid, text, bytea, text) to app_runtime;
    grant execute on function purge_password_reset(integer)                   to app_runtime;
    grant execute on function mask_destination(text, password_reset_channel)  to app_runtime;
  end if;
end $$;

commit;

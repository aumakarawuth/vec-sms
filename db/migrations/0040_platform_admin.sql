-- ═══════════════════════════════════════════════════════════════════
-- 0040_platform_admin.sql
--
-- ผู้ดูแลระดับผู้ให้บริการ — ผู้ใช้ที่ไม่ได้อยู่ในวิทยาลัยไหนเลย
--
-- ─── ทำไมข้อนี้บล็อกการขาย ───
-- ทุกบทบาทในระบบนี้อยู่ **ภายใน** วิทยาลัยหนึ่ง ๆ — admin ของวิทยาลัย ก
-- ไม่มีความหมายในวิทยาลัย ข งานของผู้ให้บริการ (เปิดวิทยาลัยใหม่ ผูกแพ็กเกจ
-- ดูปริมาณใช้งานเพื่อออกใบเรียกเก็บ ระงับลูกค้าที่ไม่ชำระ) จึงไม่มีบทบาทไหน
-- ที่ถูกต้องจะใช้ได้เลย
--
-- ทางที่ใช้อยู่ก่อนไฟล์นี้คือความลับระดับการติดตั้ง (PROVISION_KEY ใน 0037)
-- ซึ่งพอสำหรับคนเดียวที่ถือกุญแจ แต่ขายจริงไม่ได้ เพราะ
--   · กุญแจเดียวใช้ร่วมกันทั้งทีม ตอบไม่ได้ว่าใครเปิดวิทยาลัยให้ใคร
--   · เพิกถอนสิทธิ์คนที่ลาออกไม่ได้ ต้องเปลี่ยนกุญแจแล้วแจ้งใหม่ทั้งทีม
--   · แบ่งหน้าที่ไม่ได้ คนดูแลใบเรียกเก็บกับคนตอบปัญหาลูกค้าได้สิทธิ์เท่ากัน
--
-- ─── หลักที่ห้ามละเมิดของไฟล์นี้ — ผู้ให้บริการต้องไม่เห็นข้อมูลนักศึกษา ───
-- ข้อมูลชุดนี้มีเลขบัตรประชาชน ข้อมูลผู้เยาว์ ผลคัดกรอง SDQ และบันทึก
-- เยี่ยมบ้าน ผู้ให้บริการเป็นผู้ประมวลผลข้อมูลตาม PDPA ไม่ใช่เจ้าของข้อมูล
-- การเปิดหน้าจอข้ามวิทยาลัยแบบเห็นทุกอย่างคือการสร้างบัญชีที่ดูดข้อมูล
-- ของทุกวิทยาลัยได้จากที่เดียว ซึ่งเป็นสิ่งที่ระบบทั้งระบบพยายามกันมาตลอด
--
-- กำแพงจึงไม่ได้อยู่ที่ "ไม่มี endpoint ให้เรียก" แต่อยู่ที่ **บริบทของ
-- ผู้ให้บริการไม่มีวิทยาลัย** — RLS ชั้นที่ 1 ของทุกตารางเทียบ
-- `institution_id = current_institution_id()` เมื่อค่านั้นเป็น null
-- ทุกตารางคืนศูนย์แถวโดยอัตโนมัติ ไม่ต้องเขียนกฎเพิ่มสักข้อ
--
-- ตารางที่ผู้ให้บริการเห็นจึงมีเท่าที่เปิดไว้อย่างจงใจใน 0038 เท่านั้น
-- (plan · institution_subscription · usage_snapshot) บวก institution
-- ซึ่งมีแค่รหัสกับชื่อสถานศึกษา — ไม่มีข้อมูลส่วนบุคคลเลยสักช่อง
-- เทสต์ TEST 186 ยิงจริงทุกตารางที่มีข้อมูลส่วนบุคคลเพื่อยืนยันข้อนี้
--
-- ─── ทำไมผู้ให้บริการออกรหัสรีเซ็ตให้ผู้ใช้ของวิทยาลัยไม่ได้ ───
-- ถ้าออกได้ ประตูหลังจะเปิดทันที — ออกรหัสรีเซ็ตให้ admin ของวิทยาลัย
-- ตั้งรหัสผ่านใหม่ แล้วเข้าไปในบริบทของวิทยาลัยนั้นเต็มสิทธิ์ กำแพง
-- ข้างบนทั้งหมดจะไม่มีความหมายอะไรเลย
--
-- ข้อยกเว้นเดียวคือ **ผู้ดูแลคนแรกตอนเปิดวิทยาลัย** (0037) ซึ่งเลี่ยงไม่ได้
-- เพราะยังไม่มีใครในวิทยาลัยนั้นให้ออกรหัสให้ และรหัสนั้นใช้ได้ครั้งเดียว
-- มีอายุสั้น และการเปิดวิทยาลัยทุกครั้งถูกบันทึกไว้ว่าใครเป็นคนทำ
--
-- ─── ทำไมการระงับเป็นการปิดทางเข้า ไม่ใช่การลบหรือซ่อนข้อมูล ───
-- ลูกค้าที่ค้างชำระยังเป็นเจ้าของข้อมูลของตัวเองอยู่ การลบหรือทำให้อ่าน
-- ไม่ได้คือการยึดข้อมูลของเจ้าของไปเป็นตัวประกัน ซึ่งผิดทั้งทางกฎหมาย
-- และทางธุรกิจ การระงับจึงห้ามแค่ **การสร้าง session ใหม่** ข้อมูลทุกแถว
-- ยังอยู่ครบ ส่งออกได้ และกลับมาใช้ได้ทันทีที่ปลดระงับ
--
-- และการระงับต้องเป็นการกระทำที่มีคนกดเท่านั้น ห้ามผูกกับสถานะสัญญา
-- ให้เกิดเองอัตโนมัติ — บั๊กในการคิดเงินหนึ่งตัวจะกลายเป็นวิทยาลัย
-- ทั้งประเทศเข้าระบบไม่ได้พร้อมกันตอนเช้าวันจันทร์ (หลักเดียวกับ 5ข)
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บทบาทของฝั่งผู้ให้บริการ
--
-- แยกสามระดับเพราะงานสามอย่างนี้ความเสี่ยงต่างกันมาก — คนตอบปัญหาลูกค้า
-- ต้องเปิดดูได้ว่าวิทยาลัยไหนใช้แพ็กเกจอะไร แต่ไม่ควรระงับใครได้
-- ───────────────────────────────────────────────────────────────────
create type platform_role as enum ('owner', 'billing', 'support');

comment on type platform_role is
  'owner = ดูแลบัญชีผู้ให้บริการด้วยกันเองได้ · billing = แพ็กเกจ สัญญา ระงับ/ปลดระงับ · support = อ่านอย่างเดียว';

-- ───────────────────────────────────────────────────────────────────
-- บัญชีของผู้ให้บริการ
--
-- ─── ทำไมไม่ใช้ตาราง person/user_credential เดิม ───
-- ทั้งสองตารางมี institution_id แบบ not null และถูก RLS กรองด้วย
-- current_institution_id() การยัดผู้ให้บริการลงไปแปลว่าต้องสร้าง
-- "วิทยาลัยปลอม" ขึ้นมาหนึ่งแห่งให้เขาสังกัด ซึ่งจะกลายเป็นวิทยาลัยที่
-- โผล่ในรายงาน ในโควตา และในการนับยอดขายตลอดไป
--
-- และที่สำคัญกว่านั้น — บัญชีที่อยู่ในตารางเดียวกับผู้ใช้ของลูกค้า
-- มีโอกาสหลุดเข้าไปใน query ของฝั่งวิทยาลัยได้เสมอ การแยกตารางทำให้
-- นโยบายเดียว (`is_platform_context()`) ปิดได้ทั้งก้อน
-- ───────────────────────────────────────────────────────────────────
create table platform_user (
  id              uuid          primary key default gen_random_uuid(),
  username        text          not null unique,
  display_name    text          not null,
  email           text,
  role            platform_role not null default 'support',

  -- ─── ทำไมค่าเริ่มต้นคือแฮชที่เทียบกับอะไรไม่ได้ ───
  -- หลักเดียวกับ 0037 — คนที่สร้างบัญชีให้ต้องไม่รู้รหัสผ่านของเจ้าตัว
  -- แม้แต่วินาทีเดียว บัญชีใหม่จึงเข้าด้วยรหัสผ่านไม่ได้จนกว่าเจ้าตัว
  -- จะตั้งเองผ่านรหัสตั้งค่าที่ออกให้ครั้งเดียว
  password_hash   text          not null,
  must_change     boolean       not null default false,

  -- ─── รหัสตั้งค่าครั้งแรก ───
  -- เก็บเป็นค่าแฮชเหมือนรหัสรีเซ็ตของฝั่งวิทยาลัย (0025) ฐานข้อมูลที่รั่ว
  -- จึงไม่ได้แถมรหัสที่ยังใช้ได้ไปด้วย
  setup_code_hash bytea,
  setup_expires_at timestamptz,
  setup_attempts  smallint      not null default 0,

  -- ─── การยืนยันสองชั้นบังคับเสมอ ไม่มีนโยบายให้ปิด ───
  -- บัญชีเดียวในตารางนี้เปิดวิทยาลัยใหม่ได้ ระงับลูกค้าได้ และเห็นตัวเลข
  -- ธุรกิจของทุกวิทยาลัย ต่างจากฝั่งวิทยาลัยที่ตั้งได้รายแห่ง (0036)
  -- ตรงที่ตรงนี้ไม่มีลูกค้าคนไหนเป็นผู้รับความเสี่ยงแทนได้
  totp_secret_enc bytea,
  totp_confirmed_at timestamptz,
  totp_last_step  bigint,
  mfa_failed_attempts smallint  not null default 0,
  mfa_locked_until timestamptz,

  failed_attempts smallint      not null default 0,
  locked_until    timestamptz,
  disabled_at     timestamptz,
  last_login_at   timestamptz,
  created_at      timestamptz   not null default now(),
  created_by      uuid          references platform_user on delete set null,

  check (setup_expires_at is null or setup_code_hash is not null)
);

comment on table platform_user is
  'บัญชีของผู้ให้บริการ — อยู่นอกวิทยาลัยทุกแห่ง จึงไม่มี institution_id และมองไม่เห็นข้อมูลของวิทยาลัยใดเลย';
comment on column platform_user.totp_secret_enc is
  'ความลับ TOTP ที่เข้ารหัสด้วยกุญแจนอกฐานข้อมูล — ฐานข้อมูลไม่เคยเห็นค่าจริง (หลักเดียวกับ 0036)';
comment on column platform_user.totp_last_step is
  'ช่วงเวลา TOTP ล่าสุดที่ใช้ไปแล้ว รับเฉพาะช่วงที่ใหม่กว่า มิฉะนั้นรหัสที่ถูกแอบเห็นใช้ซ้ำได้';

create index platform_user_active_idx on platform_user (role)
  where disabled_at is null;

-- ───────────────────────────────────────────────────────────────────
-- session ของผู้ให้บริการ
-- แยกจาก auth_session เพราะตารางนั้นมี institution_id แบบ not null
-- และทุกนโยบายของมันอ้างวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
create table platform_session (
  id               uuid        primary key default gen_random_uuid(),
  platform_user_id uuid        not null references platform_user on delete cascade,
  token_hash       bytea       not null unique,
  expires_at       timestamptz not null,
  revoked_at       timestamptz,
  revoke_reason    text,
  user_agent       text,
  created_at       timestamptz not null default now()
);

create index platform_session_user_idx on platform_session (platform_user_id)
  where revoked_at is null;

-- ───────────────────────────────────────────────────────────────────
-- ความพยายามเข้าสู่ระบบฝั่งผู้ให้บริการ
--
-- มีไว้สองอย่าง — เป็นตัวนับรายไอพี (หลักเดียวกับ 0021 คือนับในฐานข้อมูล
-- ไม่ใช่ในหน่วยความจำของโปรเซส เพราะหลาย instance จะต่างคนต่างนับ)
-- และเป็นหลักฐานว่ามีใครพยายามเข้าบัญชีผู้ให้บริการหรือไม่
-- ───────────────────────────────────────────────────────────────────
create table platform_login_attempt (
  id               bigserial   primary key,
  username         text        not null,
  platform_user_id uuid        references platform_user on delete set null,
  succeeded        boolean     not null,
  reason           text,
  ip_hash          bytea,
  user_agent       text,
  attempted_at     timestamptz not null default now()
);

create index platform_login_attempt_ip_idx
  on platform_login_attempt (ip_hash, attempted_at desc)
  where not succeeded;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการกระทำของผู้ให้บริการ
--
-- ─── ทำไมต้องมีแยกจาก access_log ───
-- access_log มี institution_id แบบ not null และอ่านได้เฉพาะคนในวิทยาลัยนั้น
-- การกระทำของผู้ให้บริการหลายอย่างไม่ได้อยู่ในวิทยาลัยไหน (แก้ราคาแพ็กเกจ
-- สร้างบัญชีผู้ให้บริการ) และที่สำคัญกว่าคือ **ลูกค้าต้องตรวจสอบได้ว่า
-- ผู้ให้บริการทำอะไรกับวิทยาลัยของตนบ้าง** จึงต้องเป็นบันทึกที่ผู้ให้บริการ
-- เองแก้ไม่ได้ ไม่ใช่บันทึกที่อยู่ในมือฝ่ายเดียว
--
-- username ตรึงเป็นข้อความไว้ด้วยโดยตั้งใจ — ลบบัญชีทิ้งแล้วยังต้อง
-- ตอบได้ว่าใครเป็นคนทำ ถ้าเก็บแค่คีย์นอก การลบบัญชีจะลบร่องรอยไปด้วย
-- ───────────────────────────────────────────────────────────────────
create table platform_action_log (
  id               bigserial   primary key,
  platform_user_id uuid        references platform_user on delete set null,
  username         text        not null,
  action           text        not null,
  institution_id   uuid        references institution on delete restrict,
  detail           jsonb       not null default '{}'::jsonb,
  ip_hash          bytea,
  occurred_at      timestamptz not null default now()
);

comment on table platform_action_log is
  'ผู้ให้บริการทำอะไรกับวิทยาลัยไหนเมื่อไร — เขียนได้อย่างเดียว แก้ไม่ได้ ลบได้เฉพาะที่เกินระยะเก็บ';

create index platform_action_log_time_idx on platform_action_log (occurred_at desc);
create index platform_action_log_inst_idx on platform_action_log (institution_id, occurred_at desc)
  where institution_id is not null;

-- ───────────────────────────────────────────────────────────────────
-- การระงับการใช้งานของวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
alter table institution
  add column if not exists suspended_at     timestamptz,
  add column if not exists suspended_reason text,
  add column if not exists suspended_by     uuid references platform_user on delete set null;

comment on column institution.suspended_at is
  'ระงับการเข้าสู่ระบบชั่วคราว — ข้อมูลทุกแถวยังอยู่ครบ ปลดระงับแล้วใช้ได้ทันที';
comment on column institution.suspended_reason is
  'เหตุผลที่ระงับ — แสดงให้ผู้ใช้ของวิทยาลัยเห็นตอนพยายามเข้าระบบ จึงต้องเขียนแบบที่ลูกค้าอ่านแล้วรู้ว่าต้องทำอะไรต่อ';

-- ───────────────────────────────────────────────────────────────────
-- ตัวช่วยของนโยบาย
--
-- ─── ทำไมต้องเช็คทั้งสองอย่าง ───
-- `current_institution_id() is null` อย่างเดียวไม่พอ เพราะงานเบื้องหลัง
-- บางตัวก็ไม่มีวิทยาลัย และ `app.role` อย่างเดียวก็ไม่พอ เพราะค่านั้นมาจาก
-- token ที่ชั้นแอปตั้งให้ การบังคับทั้งคู่แปลว่า token ของฝั่งวิทยาลัย
-- (ซึ่ง AuthGuard บังคับว่าต้องมี inst เสมอ) ไปถึงตรงนี้ไม่ได้เลย
-- ───────────────────────────────────────────────────────────────────
create or replace function is_platform_context() returns boolean
language sql stable as $$
  select current_institution_id() is null
     and current_app_role() in ('platform', 'platform_auth')
$$;

comment on function is_platform_context() is
  'บริบทนี้เป็นของผู้ให้บริการหรือไม่ — ต้องไม่มีวิทยาลัย และบทบาทต้องเป็นของฝั่งผู้ให้บริการเท่านั้น';

-- บทบาทของผู้ให้บริการที่กำลังทำคำขอนี้
--
-- ─── ทำไมต้องเป็น security definer ───
-- ฟังก์ชันนี้ถูกเรียกจาก **ในนโยบายของ platform_user เอง** ถ้าไม่ตัดวงจร
-- การอ่าน platform_user จะไปเรียกนโยบายที่เรียกฟังก์ชันที่อ่าน platform_user
-- อีกรอบ PostgreSQL จะล้มด้วย infinite recursion detected in policy
-- (กับดักเดียวกับ student ↔ student_guardian ใน 0008)
--
-- ปลอดภัยเพราะคืนได้แค่บทบาท **ของผู้เรียกเอง** ไม่รับพารามิเตอร์ใด ๆ
-- และไม่คืนแถวหรือคอลัมน์อื่นออกไปเลย
create or replace function current_platform_role() returns platform_role
language sql stable security definer set search_path = public as $$
  select pu.role from platform_user pu
   where pu.id = current_actor_id() and pu.disabled_at is null
$$;

-- ───────────────────────────────────────────────────────────────────
-- สร้างบัญชีผู้ให้บริการคนแรก
--
-- ─── ทำไมต้องมีฟังก์ชันแยกและเป็น security definer ───
-- ไก่กับไข่ — นโยบาย insert ของ platform_user ต้องการ owner ที่ล็อกอินแล้ว
-- แต่ตอนติดตั้งระบบครั้งแรกยังไม่มี owner สักคนให้ล็อกอิน ถ้าไม่มีทางนี้
-- การติดตั้งครั้งแรกต้องเปิด psql เขียนแถวเอง ซึ่งคือปัญหาเดิมที่ 0037
-- ตั้งใจแก้
--
-- นี่เป็นข้อยกเว้นแบบเดียวกับ provision_institution — **สร้างได้อย่างเดียว
-- และสร้างได้ครั้งเดียวจริง ๆ** มีแถวอยู่แล้วแม้แถวเดียวก็ล้มทันที
-- จึงไม่ใช่ประตูหลังที่เรียกซ้ำเพื่อแต่งตั้งตัวเองเป็น owner ได้
--
-- ชั้นแอปยังกั้นด้วย PROVISION_KEY อีกชั้นก่อนถึงตรงนี้
-- ───────────────────────────────────────────────────────────────────
create or replace function bootstrap_platform_owner(
  p_username        text,
  p_display_name    text,
  p_email           text,
  p_setup_code_hash bytea,
  p_setup_minutes   integer default 60
) returns platform_user language plpgsql security definer set search_path = public as $$
declare v platform_user;
begin
  if exists (select 1 from platform_user) then
    raise exception 'มีบัญชีผู้ให้บริการอยู่แล้ว — การสร้างบัญชีเพิ่มต้องทำโดยผู้ดูแลระดับ owner ที่เข้าสู่ระบบแล้ว';
  end if;
  if coalesce(btrim(p_username), '') = '' or coalesce(btrim(p_display_name), '') = '' then
    raise exception 'ต้องระบุชื่อผู้ใช้และชื่อที่แสดง';
  end if;
  if p_setup_code_hash is null then
    raise exception 'ต้องมีรหัสตั้งค่า — บัญชีที่ไม่มีทางตั้งรหัสผ่านคือบัญชีที่เข้าไม่ได้ตลอดไป';
  end if;

  insert into platform_user
    (username, display_name, email, role, password_hash, must_change,
     setup_code_hash, setup_expires_at)
  values (btrim(p_username), btrim(p_display_name), nullif(btrim(p_email), ''), 'owner',
          -- เข้าด้วยรหัสผ่านไม่ได้จนกว่าเจ้าตัวจะตั้งเองผ่านรหัสตั้งค่า
          'locked$' || encode(gen_random_bytes(32), 'hex'), true,
          p_setup_code_hash, now() + make_interval(mins => p_setup_minutes))
  returning * into v;

  -- บันทึกการติดตั้งไว้ด้วย มิฉะนั้นบัญชีแรกของระบบจะเป็นบัญชีเดียวที่
  -- ไม่มีร่องรอยว่าเกิดขึ้นเมื่อไรและกลายเป็นช่องว่างในบันทึกตั้งแต่แถวแรก
  -- (log_platform_action() ใช้ไม่ได้ตรงนี้เพราะยังไม่มี current_actor_id())
  insert into platform_action_log (platform_user_id, username, action, detail)
  values (v.id, v.username, 'bootstrap_platform_owner',
          jsonb_build_object('note', 'สร้างด้วยกุญแจติดตั้ง PROVISION_KEY'));

  return v;
end $$;

revoke execute on function bootstrap_platform_owner(text, text, text, bytea, integer) from public;

-- ───────────────────────────────────────────────────────────────────
-- จำกัดจำนวนครั้งการเข้าสู่ระบบรายไอพี
--
-- **ห้าม raise** ด้วยเหตุผลเดียวกับ login_rate_status (0021) — ถ้า raise
-- ฐานข้อมูลจะ rollback ตัวนับทิ้งทุกครั้ง แล้วเดารหัสผ่านได้ไม่จำกัด
--
-- เข้มกว่าฝั่งวิทยาลัยเพราะบัญชีฝั่งนี้มีไม่กี่บัญชีและไม่มีนักศึกษา
-- เป็นพันคนที่พิมพ์รหัสผิดตอนเปิดเทอม โควตาต่ำจึงไม่รบกวนใคร
-- ───────────────────────────────────────────────────────────────────
create or replace function platform_login_rate_status(p_ip_hash bytea)
returns table (
  recent_failures  integer,
  max_attempts     integer,
  remaining        integer,
  blocked          boolean,
  retry_after_secs integer
) language plpgsql stable as $$
declare
  v_max    constant integer := 10;
  v_window constant integer := 15;   -- นาที
  v_block  constant integer := 30;   -- นาที
  v_count  integer;
  v_oldest timestamptz;
begin
  if p_ip_hash is null then
    -- ไม่รู้ไอพี (เรียกจากในเครื่อง) ไม่นับ แต่ก็ไม่ปลดล็อกให้ใคร
    return query select 0, v_max, v_max, false, 0;
    return;
  end if;

  select count(*)::integer, min(la.attempted_at)
    into v_count, v_oldest
    from platform_login_attempt la
   where la.ip_hash = p_ip_hash
     and not la.succeeded
     and la.attempted_at > now() - make_interval(mins => v_window);

  return query select
    v_count,
    v_max,
    greatest(0, v_max - v_count),
    v_count >= v_max,
    case when v_count >= v_max
         then greatest(0, ceil(extract(epoch from
                (coalesce(v_oldest, now()) + make_interval(mins => v_block) - now())))::integer)
         else 0 end;
end $$;

comment on function platform_login_rate_status(bytea) is
  'สถานะการจำกัดจำนวนครั้งรายไอพีของฝั่งผู้ให้บริการ — คืนค่า ไม่ raise เพราะตัวนับต้องไม่ถูก rollback';

-- ───────────────────────────────────────────────────────────────────
-- ใช้รหัสตั้งค่าครั้งแรก
--
-- ─── ทำไมค้นจากชื่อผู้ใช้ก่อน แล้วค่อยเทียบค่าแฮช ───
-- ถ้าค้นด้วย `where setup_code_hash = $1` ตรง ๆ การเดาผิดจะไม่เจอแถวใดเลย
-- แล้วไม่มีแถวให้เพิ่มตัวนับ ผลคือเดารหัสได้ไม่จำกัดครั้งโดยที่ระบบยัง
-- ปฏิเสธรหัสผิดถูกต้องทุกครั้ง (กับดักเดียวกับ consume_password_reset ใน 0025)
--
-- **ห้าม raise** ด้วยเหตุผลเดิม — rollback จะล้างตัวนับทิ้ง
-- ───────────────────────────────────────────────────────────────────
create or replace function consume_platform_setup(
  p_username  text,
  p_code_hash bytea
) returns table (
  ok        boolean,
  user_id   uuid,
  reason    text
) language plpgsql as $$
declare
  v     platform_user;
  v_max constant smallint := 5;
begin
  select * into v from platform_user where username = p_username;

  -- ข้อความเดียวกันทุกกรณีที่เดาไม่ถูก เพื่อไม่บอกว่าชื่อผู้ใช้ไหนมีอยู่จริง
  if v.id is null then
    return query select false, null::uuid, 'ชื่อผู้ใช้หรือรหัสตั้งค่าไม่ถูกต้อง'::text;
    return;
  end if;
  if v.setup_code_hash is null then
    return query select false, null::uuid, 'บัญชีนี้ตั้งรหัสผ่านไปแล้ว'::text;
    return;
  end if;
  if v.setup_expires_at is null or v.setup_expires_at < now() then
    return query select false, null::uuid, 'รหัสตั้งค่าหมดอายุแล้ว ขอรหัสใหม่จากผู้ดูแลระดับ owner'::text;
    return;
  end if;
  if v.setup_attempts >= v_max then
    return query select false, null::uuid, 'ใส่รหัสตั้งค่าผิดหลายครั้งเกินไป ขอรหัสใหม่'::text;
    return;
  end if;

  if v.setup_code_hash <> p_code_hash then
    update platform_user set setup_attempts = setup_attempts + 1 where id = v.id;
    return query select false, null::uuid, 'ชื่อผู้ใช้หรือรหัสตั้งค่าไม่ถูกต้อง'::text;
    return;
  end if;

  update platform_user
     set setup_code_hash = null, setup_expires_at = null, setup_attempts = 0
   where id = v.id;

  return query select true, v.id, null::text;
end $$;

comment on function consume_platform_setup(text, bytea) is
  'ตรวจรหัสตั้งค่าครั้งแรก — ค้นจากชื่อผู้ใช้ก่อนเพื่อให้มีแถวให้เพิ่มตัวนับเมื่อเดาผิด และห้าม raise';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจรหัส TOTP ของผู้ให้บริการ
--
-- โครงเดียวกับ mfa_verify_step (0036) — ชั้นแอปเป็นคนบอกว่ารหัสตรงไหม
-- เพราะต้องถอดรหัสความลับด้วยกุญแจที่อยู่นอกฐานข้อมูล ส่วนฟังก์ชันนี้
-- ถือสถานะที่ต้องอะตอมมิก คือการล็อก การกันใช้รหัสซ้ำ และตัวนับ
--
-- **ห้าม raise** เหตุผลเดียวกับข้างบน
-- ───────────────────────────────────────────────────────────────────
create or replace function platform_totp_verify(
  p_user_id uuid,
  p_step    bigint,
  p_matched boolean
) returns table (
  ok               boolean,
  reason           text,
  retry_after_secs integer
) language plpgsql as $$
declare
  v_user    platform_user;
  v_max     constant smallint := 5;
  v_lock    constant smallint := 15;  -- นาที
begin
  select * into v_user from platform_user
   where id = p_user_id and disabled_at is null;

  if v_user.id is null then
    return query select false, 'ไม่พบบัญชีผู้ให้บริการ'::text, 0;
    return;
  end if;

  if v_user.totp_secret_enc is null then
    return query select false, 'ยังไม่ได้ตั้งค่าการยืนยันตัวตนสองชั้น'::text, 0;
    return;
  end if;

  if v_user.mfa_locked_until is not null and v_user.mfa_locked_until > now() then
    return query select false, 'ใส่รหัสผิดหลายครั้ง ถูกระงับชั่วคราว'::text,
      ceil(extract(epoch from (v_user.mfa_locked_until - now())))::integer;
    return;
  end if;

  if not p_matched then
    update platform_user
       set mfa_failed_attempts = mfa_failed_attempts + 1,
           mfa_locked_until = case
             when mfa_failed_attempts + 1 >= v_max then now() + make_interval(mins => v_lock)
             else mfa_locked_until end
     where id = v_user.id;

    return query select false, 'รหัสยืนยันไม่ถูกต้อง'::text, 0;
    return;
  end if;

  -- รหัสถูกแต่เป็นช่วงเวลาที่ใช้ไปแล้ว = มีคนดักรหัสมาใช้ซ้ำ
  -- นับเป็นความพยายามที่ผิดด้วย เพราะแอปของเจ้าตัวแสดงรหัสปัจจุบันเสมอ
  if v_user.totp_last_step is not null and p_step <= v_user.totp_last_step then
    update platform_user
       set mfa_failed_attempts = mfa_failed_attempts + 1,
           mfa_locked_until = case
             when mfa_failed_attempts + 1 >= v_max then now() + make_interval(mins => v_lock)
             else mfa_locked_until end
     where id = v_user.id;

    return query select false, 'รหัสนี้ถูกใช้ไปแล้ว รอรหัสถัดไป'::text, 0;
    return;
  end if;

  update platform_user
     set totp_last_step = p_step, mfa_failed_attempts = 0, mfa_locked_until = null
   where id = v_user.id;

  return query select true, null::text, 0;
end $$;

comment on function platform_totp_verify(uuid, bigint, boolean) is
  'ตัดสินผลการยืนยันสองชั้นของผู้ให้บริการ — ห้าม raise เพราะตัวนับจะถูก rollback แล้วเดารหัสหกหลักได้ไม่จำกัด';

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการกระทำ
--
-- ตรึง username ลงไปด้วยเพื่อให้บันทึกยังตอบได้แม้บัญชีถูกลบ
-- ───────────────────────────────────────────────────────────────────
create or replace function log_platform_action(
  p_action         text,
  p_institution_id uuid    default null,
  p_detail         jsonb   default '{}'::jsonb,
  p_ip_hash        bytea   default null
) returns bigint language plpgsql as $$
declare
  v_id   bigint;
  v_name text;
begin
  select pu.username into v_name from platform_user pu where pu.id = current_actor_id();

  insert into platform_action_log
    (platform_user_id, username, action, institution_id, detail, ip_hash)
  values (current_actor_id(), coalesce(v_name, 'ไม่ทราบ'), p_action,
          p_institution_id, coalesce(p_detail, '{}'::jsonb), p_ip_hash)
  returning id into v_id;

  return v_id;
end $$;

-- ล้างบันทึกที่เกินระยะเก็บ — เก็บนานกว่า access_log เพราะเป็นหลักฐาน
-- ของสัญญาระหว่างนิติบุคคลสองราย ไม่ใช่บันทึกการเข้าถึงรายวัน
create or replace function purge_platform_action_log(p_keep_days integer default 730)
returns integer language plpgsql as $$
declare v_deleted integer;
begin
  delete from platform_action_log where occurred_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ตัด session ทั้งหมดของวิทยาลัยหนึ่ง
--
-- security definer เพราะบริบทผู้ให้บริการไม่มีวิทยาลัย จึงมองไม่เห็น
-- auth_session ของใครเลย (ซึ่งเป็นสิ่งที่ตั้งใจ) ฟังก์ชันนี้ **เขียน
-- อย่างเดียว** ไม่คืนข้อมูลอะไรออกมานอกจากจำนวนแถว จึงไม่ได้เปิดช่อง
-- ให้อ่านข้ามวิทยาลัยแม้แต่ช่องเดียว
-- ───────────────────────────────────────────────────────────────────
create or replace function revoke_institution_sessions(
  p_institution_id uuid,
  p_reason         text
) returns integer language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  update auth_session
     set revoked_at = now(), revoke_reason = p_reason
   where institution_id = p_institution_id and revoked_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

comment on function revoke_institution_sessions(uuid, text) is
  'ตัด session ที่ค้างอยู่ของวิทยาลัยหนึ่ง — เขียนอย่างเดียว ไม่คืนข้อมูลของวิทยาลัยออกมา';

revoke execute on function revoke_institution_sessions(uuid, text) from public;

-- ───────────────────────────────────────────────────────────────────
-- ระงับ / ปลดระงับวิทยาลัย
--
-- ต้องมีเหตุผลเสมอ เพราะข้อความนี้คือสิ่งเดียวที่ผู้ใช้ของวิทยาลัยจะเห็น
-- ตอนเข้าระบบไม่ได้ — "ถูกระงับ" เฉย ๆ ทำให้ทั้งวิทยาลัยโทรหาผู้ให้บริการ
-- พร้อมกันโดยไม่มีใครรู้ว่าต้องทำอะไร
--
-- ไม่ใช่ security definer — ต้องผ่านนโยบายของ institution ตามปกติ
-- แปลว่าเรียกได้เฉพาะบริบทผู้ให้บริการเท่านั้น วิทยาลัยปลดระงับตัวเองไม่ได้
-- ───────────────────────────────────────────────────────────────────
create or replace function suspend_institution(
  p_institution_id uuid,
  p_reason         text
) returns institution language plpgsql as $$
declare v institution;
begin
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'ต้องระบุเหตุผลที่ระงับ — ผู้ใช้ของวิทยาลัยจะเห็นข้อความนี้ตอนเข้าระบบไม่ได้';
  end if;

  update institution
     set suspended_at = coalesce(suspended_at, now()),
         suspended_reason = btrim(p_reason),
         suspended_by = current_actor_id()
   where id = p_institution_id
  returning * into v;

  if v.id is null then
    raise exception 'ไม่พบสถานศึกษาที่ระบุ หรือไม่มีสิทธิ์ระงับ';
  end if;

  -- session ที่ค้างอยู่ต้องถูกตัดด้วย มิฉะนั้นคนที่ล็อกอินค้างไว้ยังใช้งาน
  -- ต่อได้อีกหลายชั่วโมงจนกว่า access token จะหมดอายุ ซึ่งทำให้การระงับ
  -- ดูเหมือนไม่ทำงานในสายตาของคนที่กดปุ่ม
  --
  -- ทำผ่าน security definer เพราะ auth_session ถูก RLS กรองด้วยวิทยาลัย
  -- ซึ่งบริบทผู้ให้บริการไม่มี — เป็นการ "ปิดทางเข้า" ไม่ใช่การอ่านข้อมูล
  perform revoke_institution_sessions(p_institution_id, 'สถานศึกษาถูกระงับการใช้งาน');

  return v;
end $$;

create or replace function resume_institution(p_institution_id uuid)
returns institution language plpgsql as $$
declare v institution;
begin
  update institution
     set suspended_at = null, suspended_reason = null, suspended_by = null
   where id = p_institution_id
  returning * into v;

  if v.id is null then
    raise exception 'ไม่พบสถานศึกษาที่ระบุ หรือไม่มีสิทธิ์ปลดระงับ';
  end if;

  return v;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ประตูที่บังคับการระงับจริง ๆ
--
-- ─── ทำไมเป็น trigger ไม่ใช่ if ในชั้น API ───
-- ชั้น API ตรวจอยู่แล้วเพื่อให้ได้ข้อความที่อ่านรู้เรื่อง แต่การตรวจที่นั่น
-- อย่างเดียวแปลว่าเส้นทางไหนก็ตามที่สร้าง session ได้โดยไม่ผ่านโค้ดนั้น
-- (สคริปต์ย้ายข้อมูล เส้นทางใหม่ที่เขียนทีหลัง การหมุน token) จะข้ามการ
-- ระงับได้ทั้งหมด — กฎอยู่ที่ฐานข้อมูลจึงบังคับกับทุกทาง (หลักข้อ 1)
--
-- ─── ทำไมดักที่ insert เท่านั้น ───
-- การ update ใช้เพิกถอน session (ออกจากระบบ · หมุน token · ตัดตอนระงับ)
-- ถ้าดักด้วยจะทำให้ "ออกจากระบบ" ล้มเหลวหลังวิทยาลัยถูกระงับ ซึ่งกลาย
-- เป็นการบังคับให้ token ค้างอยู่กับเครื่องลูกค้าแทนที่จะถูกเพิกถอน
-- และการหมุน token ก็ออก session แถวใหม่เสมอ (issueTokens) จึงถูกดักอยู่ดี
-- ───────────────────────────────────────────────────────────────────
create or replace function block_session_when_suspended() returns trigger
language plpgsql as $$
declare v_reason text; v_at timestamptz;
begin
  select i.suspended_reason, i.suspended_at into v_reason, v_at
    from institution i where i.id = new.institution_id;

  if v_at is not null then
    raise exception 'สถานศึกษานี้ถูกระงับการใช้งานชั่วคราว (%) กรุณาติดต่อผู้ให้บริการ',
      coalesce(nullif(btrim(v_reason), ''), 'ไม่ได้ระบุเหตุผล');
  end if;

  return new;
end $$;

create trigger auth_session_suspension_check
  before insert on auth_session
  for each row execute function block_session_when_suspended();

-- ───────────────────────────────────────────────────────────────────
-- กันการยกระดับสิทธิ์ของตัวเอง
--
-- ─── ทำไม RLS อย่างเดียวไม่พอ ───
-- นโยบายข้างล่างต้องยอมให้ผู้ใช้แก้แถวของตัวเองได้ (เปลี่ยนรหัสผ่าน
-- ตั้ง TOTP) ซึ่งแปลว่า support คนหนึ่งเขียนแถวของตัวเองได้ และถ้าไม่มี
-- อะไรกั้น เขาก็ตั้ง role ของตัวเองเป็น owner ได้ในคำสั่งเดียวกัน
--
-- นโยบายแยกตามคอลัมน์ทำไม่ได้ใน PostgreSQL (RLS เป็นระดับแถว) จึงต้อง
-- ใช้ trigger — ซึ่งเป็นทางที่หลักข้อ "อย่าใช้ security definer เลี่ยง
-- นโยบาย" แนะนำไว้อยู่แล้ว
-- ───────────────────────────────────────────────────────────────────
create or replace function platform_user_guard() returns trigger
language plpgsql as $$
declare v_owners integer;
begin
  -- ขั้นตอนล็อกอินแตะได้เฉพาะตัวนับกับเวลา ไม่ใช่สิทธิ์
  if current_app_role() = 'platform_auth' then
    if new.role <> old.role or new.disabled_at is distinct from old.disabled_at then
      raise exception 'ขั้นตอนเข้าสู่ระบบเปลี่ยนสิทธิ์ของบัญชีไม่ได้';
    end if;
    return new;
  end if;

  if new.role <> old.role then
    if old.id = current_actor_id() then
      raise exception 'เปลี่ยนบทบาทของตัวเองไม่ได้ — ต้องให้ผู้ดูแลระบบคนอื่นเป็นคนเปลี่ยน';
    end if;
    if current_platform_role() <> 'owner' then
      raise exception 'ต้องเป็นผู้ดูแลระดับ owner จึงจะเปลี่ยนบทบาทของบัญชีอื่นได้';
    end if;
  end if;

  if new.disabled_at is distinct from old.disabled_at then
    if old.id = current_actor_id() then
      raise exception 'ระงับหรือเปิดบัญชีของตัวเองไม่ได้';
    end if;
    if current_platform_role() <> 'owner' then
      raise exception 'ต้องเป็นผู้ดูแลระดับ owner จึงจะระงับบัญชีอื่นได้';
    end if;
  end if;

  -- ต้องเหลือ owner ที่ใช้งานได้อย่างน้อยหนึ่งคนเสมอ
  --
  -- ถ้าเหลือศูนย์ จะไม่มีใครแต่งตั้ง owner คนใหม่ได้อีกเลย ทางแก้เดียวคือ
  -- เข้าไปแก้ในฐานข้อมูลตรง ๆ ซึ่งเป็นสถานการณ์ที่ระบบไม่ควรพาไปถึง
  if (old.role = 'owner' and new.role <> 'owner')
     or (old.role = 'owner' and new.disabled_at is not null and old.disabled_at is null) then
    select count(*) into v_owners from platform_user
     where role = 'owner' and disabled_at is null and id <> old.id;
    if v_owners = 0 then
      raise exception 'ต้องเหลือผู้ดูแลระดับ owner ที่ใช้งานได้อย่างน้อยหนึ่งบัญชี';
    end if;
  end if;

  return new;
end $$;

create trigger platform_user_role_guard
  before update on platform_user
  for each row execute function platform_user_guard();

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ─── ข้อที่สำคัญที่สุดในส่วนนี้ ───
-- ตารางทั้งสี่ต้องมองไม่เห็นจากบริบทของวิทยาลัย **โดยสิ้นเชิง**
-- ไม่ใช่แค่ "ไม่มี endpoint ให้เรียก" — app_runtime มีสิทธิ์ select ทุกตาราง
-- อยู่แล้ว ถ้าไม่ปิดที่ RLS โค้ดฝั่งวิทยาลัยบรรทัดเดียวที่เขียนผิดจะอ่าน
-- ค่าแฮชรหัสผ่านของผู้ให้บริการได้
-- ───────────────────────────────────────────────────────────────────
alter table platform_user enable row level security;
alter table platform_user force  row level security;

-- อ่านได้เฉพาะฝั่งผู้ให้บริการ (รวมขั้นตอนล็อกอินที่ต้องอ่านค่าแฮชมาเทียบ)
create policy platform_user_scope on platform_user
  for select using (is_platform_context());

-- สร้างบัญชีใหม่ได้เฉพาะ owner และเฉพาะบริบทที่ล็อกอินเสร็จแล้ว
--
-- ห้ามเขียนเงื่อนไข "หรือยังไม่มีบัญชีสักคน" ไว้ตรงนี้เพื่อรองรับการติดตั้ง
-- ครั้งแรก — subquery ที่อ่าน platform_user จากในนโยบายของ platform_user เอง
-- ทำให้เกิด infinite recursion บัญชีแรกจึงใช้ bootstrap_platform_owner()
create policy platform_user_insert on platform_user
  for insert with check (
    current_institution_id() is null
    and current_app_role() = 'platform'
    and current_platform_role() = 'owner'
  );

-- ─── ทำไมยอมให้แก้แถวของตัวเองและของคนอื่น ───
-- ขั้นล็อกอินต้องแก้ตัวนับของบัญชีที่กำลังถูกลอง (ยังไม่รู้ว่าเป็นใคร)
-- เจ้าตัวต้องแก้รหัสผ่านและ TOTP ของตัวเอง และ owner ต้องจัดการบัญชีอื่น
-- ส่วนการยกระดับสิทธิ์ถูกกันด้วย trigger ข้างบน ไม่ใช่ด้วยนโยบายนี้
create policy platform_user_update on platform_user
  for update using (is_platform_context())
  with check (is_platform_context());

-- ไม่มีนโยบาย delete โดยเจตนา — บัญชีที่ทำอะไรไปแล้วต้องระงับ ไม่ใช่ลบ
-- มิฉะนั้น platform_action_log จะเหลือแต่ชื่อที่ตามตัวไม่ได้

alter table platform_session enable row level security;
alter table platform_session force  row level security;
create policy platform_session_scope on platform_session
  using (is_platform_context())
  with check (is_platform_context());

alter table platform_login_attempt enable row level security;
alter table platform_login_attempt force  row level security;
create policy platform_login_attempt_scope on platform_login_attempt
  using (is_platform_context())
  with check (is_platform_context());

alter table platform_action_log enable row level security;
alter table platform_action_log force  row level security;

-- ─── ทำไมอ่านได้อย่างเดียวและแก้ไม่ได้เลย ───
-- บันทึกที่ผู้ให้บริการลบเองได้ ใช้ตอบลูกค้าไม่ได้ว่า "ไม่มีใครเข้าไปยุ่ง
-- กับข้อมูลของท่าน" เพราะคำตอบนั้นพิสูจน์ไม่ได้ (หลักเดียวกับ access_log)
create policy platform_action_log_read on platform_action_log
  for select using (is_platform_context());
create policy platform_action_log_append on platform_action_log
  for insert with check (is_platform_context());
create policy platform_action_log_purge_aged on platform_action_log
  for delete using (occurred_at < now() - interval '730 days');

-- ───────────────────────────────────────────────────────────────────
-- provisioning_log — ประวัติการเปิดวิทยาลัย
--
-- 0037 เขียนไว้ว่าตารางนี้เป็น "ข้อมูลระดับผู้ให้บริการ" แต่นโยบายที่ใส่ไว้
-- กรองด้วย current_institution_id() ล้วน ๆ ผลคือฝั่งที่เป็นเจ้าของข้อมูล
-- จริง ๆ กลับเป็นฝ่ายเดียวที่อ่านไม่ได้ — หน้าจอ "ใครเปิดวิทยาลัยนี้ให้เมื่อไร"
-- จึงว่างเปล่าเสมอ เพิ่มนโยบายสำหรับบริบทผู้ให้บริการให้ตรงกับที่ตั้งใจไว้
--
-- อ่านอย่างเดียว — แถวถูกเขียนโดย provision_institution() เท่านั้น
create policy provisioning_log_platform_read on provisioning_log
  for select using (is_platform_context());

-- ───────────────────────────────────────────────────────────────────
-- institution — เปิดให้อ่านเหมือนเดิม แต่เขียนได้เฉพาะผู้ให้บริการ
--
-- ─── ทำไมต้องเพิ่ม RLS ตอนนี้ ───
-- ตารางนี้ไม่เคยมี RLS เพราะเป็นตัวกำหนดขอบเขตเอง (กรองด้วยตัวเองไม่ได้)
-- ซึ่งเดิมไม่เป็นปัญหาเพราะมีแค่รหัสกับชื่อ แต่ไฟล์นี้เพิ่ม suspended_at
-- ลงไป — ถ้าไม่ปิดการเขียน วิทยาลัยที่ถูกระงับจะ `update institution
-- set suspended_at = null` ปลดระงับตัวเองได้ที่ชั้นฐานข้อมูล แล้วการระงับ
-- จะไม่มีความหมายอะไรเลย
--
-- ─── ทำไมการอ่านยังเปิดกว้าง ───
-- งานเบื้องหลังวนทุกวิทยาลัยโดยไม่มีบริบทผู้ใช้ (DbService.listInstitutions)
-- และนโยบายของตารางอื่นหลายข้ออ้าง institution ระหว่างตรวจสิทธิ์
-- การปิดการอ่านตรงนี้จะทำให้ทั้งสองอย่างพังเงียบ ๆ และแถวในตารางนี้
-- ไม่มีข้อมูลส่วนบุคคลเลยสักช่อง — การจำกัดการอ่านเป็นงานแยกที่ต้องมี
-- เทสต์ของตัวเอง ไม่ใช่ของแถมในไฟล์นี้
-- ───────────────────────────────────────────────────────────────────
alter table institution enable row level security;
alter table institution force  row level security;

create policy institution_read on institution
  for select using (true);

create policy institution_manage on institution
  for update using (is_platform_context())
  with check (is_platform_context());

-- provision_institution() เป็น security definer จึงข้าม RLS อยู่แล้วเมื่อ
-- เจ้าของฟังก์ชันเป็น superuser แต่การพึ่งข้อนั้นอย่างเดียวแปลว่าการเปิด
-- วิทยาลัยจะพังทันทีที่ deploy ด้วยเจ้าของที่ไม่ใช่ superuser — เขียนนโยบาย
-- ไว้ให้ตรงกับสิ่งที่ตั้งใจดีกว่าปล่อยให้ขึ้นกับสิทธิ์ของคนที่รัน migration
create policy institution_create on institution
  for insert with check (is_platform_context());

-- ไม่มีนโยบาย delete — การลบวิทยาลัยไม่ควรทำได้จากที่ไหนเลย
-- (คีย์นอกแบบ restrict ทั้งระบบชี้มาที่ตารางนี้อยู่แล้ว)

-- ───────────────────────────────────────────────────────────────────
-- สิทธิ์ระดับตาราง — roles.sql รันไปก่อนหน้านี้แล้ว
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete
      on platform_user, platform_session, platform_login_attempt, platform_action_log
      to app_runtime;
    grant usage, select on sequence platform_login_attempt_id_seq to app_runtime;
    grant usage, select on sequence platform_action_log_id_seq    to app_runtime;
    grant execute on function is_platform_context()                       to app_runtime;
    grant execute on function bootstrap_platform_owner(text, text, text, bytea, integer)
      to app_runtime;
    grant execute on function current_platform_role()                     to app_runtime;
    grant execute on function platform_login_rate_status(bytea)           to app_runtime;
    grant execute on function consume_platform_setup(text, bytea)         to app_runtime;
    grant execute on function platform_totp_verify(uuid, bigint, boolean) to app_runtime;
    grant execute on function log_platform_action(text, uuid, jsonb, bytea) to app_runtime;
    grant execute on function purge_platform_action_log(integer)          to app_runtime;
    grant execute on function suspend_institution(uuid, text)             to app_runtime;
    grant execute on function resume_institution(uuid)                    to app_runtime;
    grant execute on function revoke_institution_sessions(uuid, text)     to app_runtime;
  end if;
end $$;

commit;

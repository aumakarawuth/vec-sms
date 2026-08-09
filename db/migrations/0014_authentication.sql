-- ═══════════════════════════════════════════════════════════════════
-- 0014_authentication.sql
-- การยืนยันตัวตนจริง — แทนช่องทางสำหรับพัฒนาที่ไม่ตรวจรหัสผ่าน
--
-- ─── หลักที่ยึด ───
-- 1. ไม่เก็บรหัสผ่าน เก็บเฉพาะค่าที่ผ่านฟังก์ชันหน่วงแล้ว และเก็บพารามิเตอร์
--    ไว้ในสตริงเดียวกัน เพื่อให้เปลี่ยนความแรงในอนาคตได้โดยไม่ต้องรีเซ็ตทุกคน
-- 2. ไม่เก็บ refresh token เก็บเฉพาะค่าแฮช ถ้าฐานข้อมูลรั่วผู้โจมตีก็ยัง
--    สวมสิทธิ์ไม่ได้
-- 3. ผูกอุปกรณ์กับบัญชีนักศึกษา เครื่องแรกอนุมัติเอง เครื่องถัดไปต้องให้
--    เจ้าหน้าที่อนุมัติ — กันการยืมบัญชีกันเช็คอินแทน
-- 4. เผื่อทางไว้ให้ผู้ให้บริการภายนอก (ThaID สำหรับผู้ปกครอง Google
--    Workspace สำหรับนักศึกษาและครู) โดยไม่ต้องรื้อโครงสร้างทีหลัง
--
-- ─── บทบาทพิเศษ 'auth' ───
-- ตอนล็อกอินยังไม่รู้ว่าผู้ใช้เป็นใคร จึงยังตั้ง app.actor_id ไม่ได้
-- ระบบจึงมีบทบาท 'auth' ที่อ่านได้เฉพาะข้อมูลที่จำเป็นต่อการตรวจรหัสผ่าน
-- ภายในสถานศึกษาที่ระบุเท่านั้น ไม่ใช่การให้สิทธิ์ admin ชั่วคราว
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- รหัสผ่านภายในระบบ
-- ───────────────────────────────────────────────────────────────────
create table user_credential (
  id                 uuid        primary key default gen_random_uuid(),
  institution_id     uuid        not null references institution on delete cascade,
  person_id          uuid        not null references person      on delete cascade,

  -- ชื่อผู้ใช้คือรหัสนักศึกษาหรือรหัสบุคลากร ไม่ใช่อีเมล
  -- เพราะนักศึกษาอาชีวะจำนวนมากไม่มีอีเมลของตัวเองตอนเข้าเรียน
  username           text        not null,

  -- รูปแบบ: scrypt$N$r$p$saltBase64$hashBase64
  -- เก็บพารามิเตอร์ไว้ในสตริงเดียวกัน เพื่อให้เพิ่มความแรงในอนาคตได้
  -- โดยผู้ใช้เดิมยังล็อกอินได้และค่อยอัปเกรดตอนเข้าสู่ระบบครั้งถัดไป
  password_hash      text        not null,

  must_change        boolean     not null default true,
  failed_attempts    smallint    not null default 0,
  locked_until       timestamptz,
  last_login_at      timestamptz,
  password_changed_at timestamptz not null default now(),
  disabled_at        timestamptz,
  created_at         timestamptz not null default now(),

  unique (institution_id, username)
);
create index on user_credential (person_id);

comment on column user_credential.must_change is
  'รหัสผ่านชุดแรกออกโดยงานทะเบียน ต้องบังคับเปลี่ยนตอนเข้าใช้ครั้งแรก';

-- ───────────────────────────────────────────────────────────────────
-- ตัวตนจากผู้ให้บริการภายนอก
-- เตรียมไว้ให้ ThaID และ Google Workspace เชื่อมเข้ามาโดยไม่ต้องรื้อของเดิม
-- ───────────────────────────────────────────────────────────────────
create type identity_provider as enum ('local', 'thaid', 'google', 'line');

create table auth_identity (
  id             uuid              primary key default gen_random_uuid(),
  institution_id uuid              not null references institution on delete cascade,
  person_id      uuid              not null references person      on delete cascade,
  provider       identity_provider not null,
  subject        text              not null,     -- รหัสผู้ใช้ฝั่งผู้ให้บริการ
  email          text,
  linked_at      timestamptz       not null default now(),
  last_used_at   timestamptz,
  unique (provider, subject)
);
create index on auth_identity (person_id);

-- ───────────────────────────────────────────────────────────────────
-- อุปกรณ์ที่ผูกกับบัญชี
--
-- นักศึกษาหนึ่งคนใช้ได้หนึ่งเครื่อง เครื่องแรกอนุมัติอัตโนมัติ
-- เครื่องถัดไปต้องให้เจ้าหน้าที่อนุมัติ พร้อมบันทึกว่าใครอนุมัติเมื่อไร
-- เพราะการยืมบัญชีกันเช็คอินแทนเป็นปัญหาที่เกิดจริงและตรวจย้อนหลังยาก
-- ───────────────────────────────────────────────────────────────────
create table device_binding (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  person_id      uuid        not null references person      on delete cascade,
  device_id      text        not null,          -- ตัวระบุที่แอปสร้างและเก็บใน secure storage
  device_label   text,                          -- 'Samsung A15' ให้เจ้าหน้าที่อ่านเข้าใจ
  platform       text,
  approved_at    timestamptz,
  approved_by    uuid references staff,
  revoked_at     timestamptz,
  revoke_reason  text,
  first_seen_at  timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  unique (institution_id, device_id)
);
create index on device_binding (person_id) where revoked_at is null;

-- ───────────────────────────────────────────────────────────────────
-- Refresh token
-- เก็บเฉพาะแฮช ถ้าฐานข้อมูลรั่วผู้โจมตีก็สวมสิทธิ์ไม่ได้
-- ───────────────────────────────────────────────────────────────────
create table auth_session (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  person_id      uuid        not null references person      on delete cascade,
  token_hash     bytea       not null,
  device_id      text,
  app_role       text        not null,
  issued_at      timestamptz not null default now(),
  expires_at     timestamptz not null,
  last_used_at   timestamptz,
  revoked_at     timestamptz,
  revoke_reason  text,
  user_agent     text,
  unique (token_hash)
);
create index on auth_session (person_id) where revoked_at is null;
create index on auth_session (expires_at) where revoked_at is null;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกความพยายามเข้าสู่ระบบ
--
-- เก็บที่อยู่ไอพีเป็นค่าแฮช ไม่ใช่ค่าจริง เพราะไอพีเป็นข้อมูลส่วนบุคคล
-- ตาม PDPA แต่ยังต้องใช้จำกัดจำนวนครั้งและตรวจสอบย้อนหลังได้
-- ───────────────────────────────────────────────────────────────────
create table login_attempt (
  id             bigserial   primary key,
  institution_id uuid        references institution on delete cascade,
  username       text,
  person_id      uuid        references person on delete set null,
  succeeded      boolean     not null,
  reason         text,
  ip_hash        bytea,
  user_agent     text,
  attempted_at   timestamptz not null default now()
);
create index on login_attempt (institution_id, username, attempted_at desc);
create index on login_attempt (attempted_at);

comment on table login_attempt is
  'เก็บไว้ไม่น้อยกว่า 90 วันตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26 แล้วลบอัตโนมัติ';

-- ลบบันทึกที่เกินระยะเก็บ — ตั้งเป็นงานประจำวัน
create or replace function purge_login_attempts(p_keep_days integer default 90)
returns integer language plpgsql as $$
declare v_n integer;
begin
  delete from login_attempt where attempted_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- นโยบายการเข้าสู่ระบบ
-- ───────────────────────────────────────────────────────────────────
create table auth_policy (
  institution_id        uuid     primary key references institution on delete cascade,
  max_failed_attempts   smallint not null default 5,
  lockout_minutes       smallint not null default 15,
  access_token_minutes  smallint not null default 30,
  refresh_token_days    smallint not null default 30,
  min_password_length   smallint not null default 8,
  bind_student_device   boolean  not null default true,
  max_devices_student   smallint not null default 1
);

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
--
-- ตารางกลุ่มนี้อ่อนไหวที่สุดในระบบ ผู้ใช้ทั่วไปต้องเห็นได้เฉพาะของตัวเอง
-- ส่วนบทบาท 'auth' ใช้ได้เฉพาะตอนล็อกอินและอ่านได้เท่าที่จำเป็น
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'user_credential', 'auth_identity', 'device_binding',
    'auth_session', 'login_attempt', 'auth_policy'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- ตัวเองเห็นของตัวเอง · เจ้าหน้าที่ที่ดูแลบัญชีเห็นได้ทั้งหมด
-- บทบาท auth ใช้ได้เฉพาะช่วงตรวจรหัสผ่าน
create policy credential_scope on user_credential
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

create policy identity_scope on auth_identity
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'admin')
    or person_id = current_actor_id()
  );

create policy session_scope on auth_session
  as restrictive
  using (
    current_app_role() in ('auth', 'admin')
    or person_id = current_actor_id()
  );

-- การอนุมัติอุปกรณ์เป็นงานของทะเบียนและปกครอง
create policy device_scope on device_binding
  as restrictive
  using (
    current_app_role() in ('auth', 'registrar', 'student_affairs', 'admin')
    or person_id = current_actor_id()
  );

-- บันทึกความพยายามเข้าสู่ระบบ เขียนได้ อ่านได้เฉพาะผู้ดูแล ห้ามแก้และลบ
create policy attempt_scope on login_attempt
  as restrictive
  using (current_app_role() in ('auth', 'admin', 'director'));

commit;

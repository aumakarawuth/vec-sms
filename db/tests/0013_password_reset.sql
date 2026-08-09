-- ═══════════════════════════════════════════════════════════════════
-- 0013_password_reset.sql
-- ทดสอบการรีเซ็ตรหัสผ่านด้วยรหัสใช้ครั้งเดียว
--
-- ─── ทำไมชุดนี้เน้นกรณีที่พังเงียบ ───
-- กลไกรีเซ็ตรหัสผ่านเป็นทางเข้าบัญชีที่ **ไม่ต้องรู้รหัสผ่านเดิม** จึงเป็น
-- เป้าหมายที่คุ้มค่าที่สุดสำหรับผู้โจมตี และความผิดพลาดของมันไม่มีอาการ
-- ให้เห็นเลยจนกว่าจะมีคนเสียบัญชีไป — ตัวนับที่ไม่เคยขยับ รหัสเก่าที่ยัง
-- ใช้ได้หลังออกใบใหม่ และรหัสที่ใช้แล้วยังใช้ซ้ำได้ ล้วนดูเหมือนระบบทำงาน
-- ปกติทุกประการจากภายนอก
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมข้อมูล ───────────────────────────────────────────────────
-- นักศึกษาที่มีอีเมลกับเบอร์โทรบันทึกไว้ (ขอรีเซ็ตเองได้)
update person
   set email = 'somchai.k@example.ac.th', phone = '0812345678'
 where id = 'aaaa0000-0000-0000-0000-000000000001';

-- นักศึกษาที่ไม่มีช่องทางติดต่อเลย — กรณีที่พบบ่อยที่สุดในอาชีวะ
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
values ('bbbb0000-0000-0000-0000-0000000000d1',
        '11111111-1111-1111-1111-111111111111', 'นาย', 'ธนากร', 'ไร้อีเมล', 'male')
on conflict (id) do nothing;

insert into student (id, institution_id, person_id, student_code, admitted_year_be)
values ('bbbb0000-0000-0000-0000-0000000000d2',
        '11111111-1111-1111-1111-111111111111',
        'bbbb0000-0000-0000-0000-0000000000d1', '69PWR00002', 2569)
on conflict (id) do nothing;

-- บัญชีของทั้งสองคน — ค่าแฮชรหัสผ่านเป็นของสมมติ ฐานข้อมูลไม่เคยตรวจเอง
insert into user_credential
  (id, institution_id, person_id, username, password_hash, must_change, failed_attempts)
values
  ('bbbb0000-0000-0000-0000-0000000000e1', '11111111-1111-1111-1111-111111111111',
   'aaaa0000-0000-0000-0000-000000000001', '67201010005', 'scrypt$16384$8$1$AAAA$OLD1', true, 4),
  ('bbbb0000-0000-0000-0000-0000000000e2', '11111111-1111-1111-1111-111111111111',
   'bbbb0000-0000-0000-0000-0000000000d1', '69PWR00002', 'scrypt$16384$8$1$AAAA$OLD2', true, 0)
on conflict (id) do nothing;

-- บัญชีที่ถูกล็อกไว้ เพื่อดูว่าการรีเซ็ตปลดล็อกให้จริง
update user_credential
   set locked_until = now() + interval '15 minutes'
 where id = 'bbbb0000-0000-0000-0000-0000000000e1';

-- อีกสามบัญชีที่มีอีเมล — ใช้ทดสอบเพดานรายไอพี ซึ่งต้องยิงไปยังบัญชี
-- ที่มีอยู่จริงเท่านั้นจึงจะสมจริง (บัญชีที่ไม่มีอยู่ไม่ทำให้เกิดการส่งอะไรเลย)
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender, email)
values
  ('bbbb0000-0000-0000-0000-0000000000a1', '11111111-1111-1111-1111-111111111111',
   'นางสาว', 'ปิยะดา', 'ทดสอบไอพี', 'female', 'piyada@example.ac.th'),
  ('bbbb0000-0000-0000-0000-0000000000a2', '11111111-1111-1111-1111-111111111111',
   'นาย', 'ณัฐวุฒิ', 'ทดสอบไอพี', 'male', 'nattawut@example.ac.th'),
  ('bbbb0000-0000-0000-0000-0000000000a3', '11111111-1111-1111-1111-111111111111',
   'นางสาว', 'กมลชนก', 'ทดสอบไอพี', 'female', 'kamonchanok@example.ac.th')
on conflict (id) do nothing;

insert into user_credential
  (id, institution_id, person_id, username, password_hash)
values
  ('bbbb0000-0000-0000-0000-0000000000b1', '11111111-1111-1111-1111-111111111111',
   'bbbb0000-0000-0000-0000-0000000000a1', '69IP00001', 'scrypt$16384$8$1$AAAA$IP1'),
  ('bbbb0000-0000-0000-0000-0000000000b2', '11111111-1111-1111-1111-111111111111',
   'bbbb0000-0000-0000-0000-0000000000a2', '69IP00002', 'scrypt$16384$8$1$AAAA$IP2'),
  ('bbbb0000-0000-0000-0000-0000000000b3', '11111111-1111-1111-1111-111111111111',
   'bbbb0000-0000-0000-0000-0000000000a3', '69IP00003', 'scrypt$16384$8$1$AAAA$IP3')
on conflict (id) do nothing;

-- session ที่ยังใช้ได้ เพื่อดูว่าการรีเซ็ตเตะทุกอุปกรณ์ออกจริง
insert into auth_session
  (id, institution_id, person_id, token_hash, app_role, expires_at)
values ('bbbb0000-0000-0000-0000-0000000000f1', '11111111-1111-1111-1111-111111111111',
        'aaaa0000-0000-0000-0000-000000000001', sha256('session-a'::bytea),
        'student', now() + interval '30 days')
on conflict (id) do nothing;

-- ── TEST 113 ───────────────────────────────────────────────────────
-- รหัสประจำตัวที่ไม่มีอยู่จริงต้องไม่สร้างแถวใด ๆ
--
-- ถ้าสร้างแถวทิ้งไว้ จำนวนแถวจะกลายเป็นตัวบอกว่ารหัสประจำตัวไหนมีจริง
-- และผู้โจมตีที่อ่านตารางได้จะไล่รายชื่อทั้งวิทยาลัยได้จากตรงนี้
do $$
declare v_r record; v_before int; v_after int;
begin
  select count(*) into v_before from password_reset;

  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', 'ไม่มีรหัสนี้', null,
    sha256('x'::bytea), null, null);

  select count(*) into v_after from password_reset;

  if v_r.issued then
    raise exception 'TEST 113 ล้มเหลว: ออกรหัสให้บัญชีที่ไม่มีอยู่จริง';
  end if;
  if v_after <> v_before then
    raise exception 'TEST 113 ล้มเหลว: สร้างแถวทิ้งไว้ % แถว กลายเป็นตัวบอกว่าบัญชีไหนมีจริง',
      v_after - v_before;
  end if;
  raise notice 'TEST 113 ผ่าน — บัญชีที่ไม่มีอยู่จริงไม่สร้างแถว (เหตุผล: %)', v_r.reason;
end $$;

-- ── TEST 114 ───────────────────────────────────────────────────────
-- ระบบเลือกช่องทางจากข้อมูลติดต่อที่บันทึกไว้ และปิดบังปลายทางก่อนแสดง
--
-- งานทะเบียนต้องยืนยันได้ว่ารหัสถูกส่งไปที่ไหน โดยไม่ต้องเปิดดูอีเมล
-- หรือเบอร์เต็มของนักศึกษา ซึ่งเป็นการเก็บเท่าที่จำเป็นตาม PDPA มาตรา 22
do $$
declare v_r record;
begin
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005', null,
    sha256('code-1'::bytea), sha256('ip-a'::bytea), null);

  if not v_r.issued then
    raise exception 'TEST 114 ล้มเหลว: ออกรหัสไม่สำเร็จ — %', v_r.reason;
  end if;
  if v_r.channel <> 'email' then
    raise exception 'TEST 114 ล้มเหลว: ควรเลือกอีเมลเป็นช่องทางแรก ได้ %', v_r.channel;
  end if;
  if v_r.destination_hint like '%somchai.k%' then
    raise exception 'TEST 114 ล้มเหลว: ปลายทางไม่ถูกปิดบัง — %', v_r.destination_hint;
  end if;
  if v_r.destination_hint <> 'so*******@example.ac.th' then
    raise exception 'TEST 114 ล้มเหลว: รูปแบบการปิดบังผิด — %', v_r.destination_hint;
  end if;
  raise notice 'TEST 114 ผ่าน — เลือกช่องทาง % ปลายทาง % หมดอายุ %',
    v_r.channel, v_r.destination_hint, v_r.expires_at;
end $$;

-- ── TEST 115 ───────────────────────────────────────────────────────
-- ออกใบใหม่ต้องเพิกถอนใบเก่าทันที เหลือใบที่ใช้ได้ครั้งละหนึ่งใบ
--
-- ถ้าปล่อยให้ค้างหลายใบ ผู้โจมตีที่กดขอซ้ำสิบครั้งจะได้พื้นที่เดาเป็นสิบเท่า
-- ทั้งที่ตัวนับจำนวนครั้งของแต่ละใบยังไม่ถูกแตะเลยสักใบ
do $$
declare v_r record; v_active int; v_old_revoked boolean;
begin
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005', null,
    sha256('code-2'::bytea), sha256('ip-a'::bytea), null);

  if not v_r.issued then
    raise exception 'TEST 115 ล้มเหลว: ออกใบที่สองไม่ได้ — %', v_r.reason;
  end if;

  select count(*) into v_active
    from password_reset
   where person_id = 'aaaa0000-0000-0000-0000-000000000001'
     and consumed_at is null and revoked_at is null;

  select revoked_at is not null into v_old_revoked
    from password_reset where token_hash = sha256('code-1'::bytea);

  if v_active <> 1 then
    raise exception 'TEST 115 ล้มเหลว: มีรหัสที่ใช้ได้ค้างอยู่ % ใบ ควรเหลือใบเดียว', v_active;
  end if;
  if not v_old_revoked then
    raise exception 'TEST 115 ล้มเหลว: ใบเก่ายังใช้ได้อยู่หลังออกใบใหม่';
  end if;
  raise notice 'TEST 115 ผ่าน — ออกใบใหม่แล้วใบเก่าถูกเพิกถอน เหลือใบที่ใช้ได้ 1 ใบ';
end $$;

-- ── TEST 116 ───────────────────────────────────────────────────────
-- รหัสเก่าที่ถูกเพิกถอนแล้วใช้ไม่ได้ แม้จะยังไม่หมดอายุ
do $$
declare v_r record; v_attempts smallint;
begin
  select * into v_r from consume_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005',
    sha256('code-1'::bytea), 'scrypt$16384$8$1$AAAA$NEW');

  if v_r.ok then
    raise exception 'TEST 116 ล้มเหลว: รหัสที่ถูกเพิกถอนแล้วยังใช้ได้';
  end if;

  -- และต้องนับเป็นการเดาผิดของใบปัจจุบันด้วย มิฉะนั้นผู้โจมตีจะไล่ยิง
  -- รหัสเก่าที่เคยรู้ได้ไม่จำกัดครั้งโดยตัวนับไม่ขยับ
  select attempts into v_attempts
    from password_reset where token_hash = sha256('code-2'::bytea);
  if v_attempts <> 1 then
    raise exception 'TEST 116 ล้มเหลว: รหัสที่ผิดไม่ถูกนับเป็นการเดา (ตัวนับ = %)', v_attempts;
  end if;
  raise notice 'TEST 116 ผ่าน — รหัสที่ถูกเพิกถอนใช้ไม่ได้และถูกนับเป็นการเดาผิด (%)', v_r.reason;
end $$;

-- ── TEST 117 ───────────────────────────────────────────────────────
-- กรอกผิดต้องเพิ่มตัวนับทุกครั้ง และครบโควตาแล้วใบนั้นถูกยกเลิก
--
-- นี่คือข้อที่ป้องกันการเดารหัสแปดตัวอักษรจนได้ ถ้าตัวนับไม่ขยับ
-- รหัสสั้นขนาดนี้เดาครบทุกความเป็นไปได้ภายในเวลาที่ยังไม่หมดอายุ
do $$
declare
  v_r record; i int; v_max smallint := 5;
  v_start smallint; v_attempts smallint; v_revoked text;
begin
  -- ใบนี้ถูกเดาผิดไปแล้วหนึ่งครั้งจาก TEST 116 จึงนับต่อจากของเดิม
  -- ไม่ใช่ตั้งต้นที่ศูนย์ เพราะตัวนับต้องสะสมข้ามคำขอ ไม่ใช่รีเซ็ตทุกครั้ง
  select attempts into v_start
    from password_reset where token_hash = sha256('code-2'::bytea);

  for i in 1..(v_max - v_start - 1) loop
    select * into v_r from consume_password_reset(
      '11111111-1111-1111-1111-111111111111', '67201010005',
      sha256(('เดาผิด-' || i)::bytea), 'scrypt$16384$8$1$AAAA$NEW');

    if v_r.ok then
      raise exception 'TEST 117 ล้มเหลว: รหัสที่เดาผิดกลับใช้ได้ (รอบที่ %)', i;
    end if;
  end loop;

  select attempts, revoke_reason into v_attempts, v_revoked
    from password_reset where token_hash = sha256('code-2'::bytea);

  if v_attempts <> v_max - 1 then
    raise exception 'TEST 117 ล้มเหลว: ตัวนับควรเป็น % ได้ % — เดารหัสได้ไม่จำกัดครั้ง',
      v_max - 1, v_attempts;
  end if;
  if v_revoked is not null then
    raise exception 'TEST 117 ล้มเหลว: ยกเลิกก่อนครบโควตา (%)', v_revoked;
  end if;

  -- ครั้งสุดท้ายครบโควตา ใบนี้ต้องถูกยกเลิกทันที
  select * into v_r from consume_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005',
    sha256('เดาผิดครั้งสุดท้าย'::bytea), 'scrypt$16384$8$1$AAAA$NEW');

  select revoke_reason into v_revoked
    from password_reset where token_hash = sha256('code-2'::bytea);

  if v_revoked is null then
    raise exception 'TEST 117 ล้มเหลว: เดาผิดครบ % ครั้งแล้วรหัสยังใช้ได้อยู่', v_max;
  end if;
  raise notice 'TEST 117 ผ่าน — ตัวนับขยับทุกครั้ง ครบ % ครั้งแล้วยกเลิกอัตโนมัติ (%)',
    v_max, v_revoked;
end $$;

-- ── TEST 118 ───────────────────────────────────────────────────────
-- ใช้รหัสที่ถูกต้องแล้วต้องได้ครบทุกผล — ตั้งรหัสใหม่ ปลดล็อก
-- ล้างตัวนับรหัสผิด เลิกบังคับเปลี่ยน และเตะทุกอุปกรณ์ออก
--
-- ข้อที่พลาดง่ายที่สุดคือการปลดล็อก คนที่ลืมรหัสผ่านมักใส่ผิดจนบัญชีถูกล็อก
-- ก่อนจะยอมกดรีเซ็ต ถ้าการรีเซ็ตไม่ล้าง locked_until เขาจะตั้งรหัสใหม่สำเร็จ
-- แล้วยังเข้าระบบไม่ได้อยู่ดี โดยที่ไม่มีข้อความไหนอธิบายว่าทำไม
do $$
declare v_r record; v_cred record; v_sessions int;
begin
  -- ต้องออกใบใหม่ก่อน เพราะใบก่อนหน้าถูกยกเลิกจากการเดาผิดครบโควตา
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005', null,
    sha256('code-3'::bytea), sha256('ip-a'::bytea), null);

  if not v_r.issued then
    raise exception 'TEST 118 ล้มเหลว: ขอใบใหม่ไม่ได้ — %', v_r.reason;
  end if;

  select * into v_r from consume_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005',
    sha256('code-3'::bytea), 'scrypt$16384$8$1$AAAA$RESET1');

  if not v_r.ok then
    raise exception 'TEST 118 ล้มเหลว: ใช้รหัสที่ถูกต้องไม่ได้ — %', v_r.reason;
  end if;

  select password_hash, must_change, failed_attempts, locked_until
    into v_cred
    from user_credential where id = 'bbbb0000-0000-0000-0000-0000000000e1';

  select count(*) into v_sessions
    from auth_session
   where person_id = 'aaaa0000-0000-0000-0000-000000000001' and revoked_at is null;

  if v_cred.password_hash <> 'scrypt$16384$8$1$AAAA$RESET1' then
    raise exception 'TEST 118 ล้มเหลว: รหัสผ่านไม่ถูกเปลี่ยน';
  end if;
  if v_cred.locked_until is not null then
    raise exception 'TEST 118 ล้มเหลว: ยังถูกล็อกอยู่หลังรีเซ็ต ตั้งรหัสใหม่ได้แต่เข้าระบบไม่ได้';
  end if;
  if v_cred.failed_attempts <> 0 then
    raise exception 'TEST 118 ล้มเหลว: ตัวนับรหัสผิดไม่ถูกล้าง เหลือ %', v_cred.failed_attempts;
  end if;
  if v_cred.must_change then
    raise exception 'TEST 118 ล้มเหลว: บังคับเปลี่ยนซ้ำทั้งที่เจ้าตัวเป็นคนพิมพ์รหัสเอง';
  end if;
  if v_sessions <> 0 then
    raise exception 'TEST 118 ล้มเหลว: ยังมี session เหลือ % รายการ อุปกรณ์ที่ยึดบัญชีไปยังใช้ได้ต่อ',
      v_sessions;
  end if;
  raise notice 'TEST 118 ผ่าน — ตั้งรหัสใหม่ · ปลดล็อก · ล้างตัวนับ · ไม่บังคับเปลี่ยนซ้ำ · เตะทุกอุปกรณ์ออก';
end $$;

-- ── TEST 119 ───────────────────────────────────────────────────────
-- รหัสที่ใช้ไปแล้วใช้ซ้ำไม่ได้ และแถวนั้นแก้ไขไม่ได้อีกเลย
do $$
declare v_r record; v_blocked boolean := false;
begin
  select * into v_r from consume_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005',
    sha256('code-3'::bytea), 'scrypt$16384$8$1$AAAA$RESET2');

  if v_r.ok then
    raise exception 'TEST 119 ล้มเหลว: รหัสที่ใช้ไปแล้วใช้ซ้ำได้';
  end if;

  begin
    update password_reset set revoked_at = null, revoke_reason = null
     where token_hash = sha256('code-3'::bytea);
  exception when others then
    v_blocked := true;
  end;

  if not v_blocked then
    raise exception 'TEST 119 ล้มเหลว: แก้แถวที่ใช้ไปแล้วได้';
  end if;
  raise notice 'TEST 119 ผ่าน — ใช้ซ้ำไม่ได้ และแถวที่ใช้แล้วแก้ไม่ได้';
end $$;

-- ── TEST 120 ───────────────────────────────────────────────────────
-- ต่ออายุหรือย้ายรหัสไปผูกกับบัญชีอื่นย้อนหลังไม่ได้
--
-- คนที่เขียนตารางนี้ได้ต้องไม่สามารถ "ต่ออายุ" รหัสของตัวเอง หรือย้าย
-- รหัสที่ตัวเองรู้ไปผูกกับบัญชีผู้อำนวยการได้ มิฉะนั้นทั้งกลไกไม่มีความหมาย
do $$
declare v_r record; v_id uuid; v_extend boolean := false; v_move boolean := false;
begin
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69PWR00002', 'staff_counter',
    sha256('code-counter'::bytea), null, 'aaaa0000-0000-0000-0000-0000000000c1');

  if not v_r.issued then
    raise exception 'TEST 120 ล้มเหลว: งานทะเบียนออกรหัสหน้าเคาน์เตอร์ไม่ได้ — %', v_r.reason;
  end if;

  select id into v_id from password_reset where token_hash = sha256('code-counter'::bytea);

  begin
    update password_reset set expires_at = now() + interval '30 days' where id = v_id;
  exception when others then
    v_extend := true;
  end;

  begin
    update password_reset set person_id = 'aaaa0000-0000-0000-0000-000000000002' where id = v_id;
  exception when others then
    v_move := true;
  end;

  if not v_extend then
    raise exception 'TEST 120 ล้มเหลว: ต่ออายุรหัสรีเซ็ตย้อนหลังได้';
  end if;
  if not v_move then
    raise exception 'TEST 120 ล้มเหลว: ย้ายรหัสไปผูกกับบัญชีคนอื่นได้';
  end if;
  raise notice 'TEST 120 ผ่าน — ต่ออายุและย้ายเจ้าของรหัสย้อนหลังไม่ได้';
end $$;

-- ── TEST 121 ───────────────────────────────────────────────────────
-- ช่องทางเคาน์เตอร์ต้องระบุเจ้าหน้าที่ผู้ยืนยันตัวตนเสมอ
--
-- ถ้าไม่บังคับ บันทึกจะตอบไม่ได้ว่าใครปล่อยรหัสออกไป ซึ่งเป็นข้อมูล
-- ชิ้นเดียวที่มีค่าจริงตอนสอบสวนกรณีบัญชีถูกยึด
do $$
declare v_r record; v_direct boolean := false;
begin
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69PWR00002', 'staff_counter',
    sha256('code-nostaff'::bytea), null, null);

  if v_r.issued then
    raise exception 'TEST 121 ล้มเหลว: ออกรหัสหน้าเคาน์เตอร์ได้โดยไม่ระบุเจ้าหน้าที่';
  end if;

  -- เขียนตรงเข้าตารางเพื่อข้ามฟังก์ชันก็ต้องไม่ได้
  begin
    insert into password_reset
      (institution_id, person_id, credential_id, token_hash, channel, expires_at)
    values ('11111111-1111-1111-1111-111111111111',
            'bbbb0000-0000-0000-0000-0000000000d1',
            'bbbb0000-0000-0000-0000-0000000000e2',
            sha256('code-bypass'::bytea), 'staff_counter', now() + interval '30 minutes');
  exception when others then
    v_direct := true;
  end;

  if not v_direct then
    raise exception 'TEST 121 ล้มเหลว: เขียนตรงเข้าตารางข้ามการระบุเจ้าหน้าที่ได้';
  end if;
  raise notice 'TEST 121 ผ่าน — ช่องทางเคาน์เตอร์ต้องมีเจ้าหน้าที่กำกับ ทั้งผ่านฟังก์ชันและเขียนตรง (%)',
    v_r.reason;
end $$;

-- ── TEST 122 ───────────────────────────────────────────────────────
-- รหัสที่หมดอายุใช้ไม่ได้ และถูกเพิกถอนทิ้งไม่ให้ค้างเป็นเป้าให้เดาต่อ
do $$
declare v_r record; v_reason text;
begin
  -- ใส่แถวที่หมดอายุแล้วโดยตรง เพราะฟังก์ชันออกให้ได้เร็วที่สุด 1 นาที
  insert into password_reset
    (institution_id, person_id, credential_id, token_hash, channel,
     created_at, expires_at)
  values ('11111111-1111-1111-1111-111111111111',
          'aaaa0000-0000-0000-0000-000000000001',
          'bbbb0000-0000-0000-0000-0000000000e1',
          sha256('code-expired'::bytea), 'sms',
          now() - interval '2 hours', now() - interval '90 minutes');

  select * into v_r from consume_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005',
    sha256('code-expired'::bytea), 'scrypt$16384$8$1$AAAA$NOPE');

  select revoke_reason into v_reason
    from password_reset where token_hash = sha256('code-expired'::bytea);

  if v_r.ok then
    raise exception 'TEST 122 ล้มเหลว: รหัสที่หมดอายุแล้วยังใช้ได้';
  end if;
  if v_reason is null then
    raise exception 'TEST 122 ล้มเหลว: รหัสที่หมดอายุไม่ถูกเพิกถอน ยังค้างเป็นเป้าให้เดาต่อ';
  end if;
  raise notice 'TEST 122 ผ่าน — รหัสหมดอายุใช้ไม่ได้และถูกเพิกถอน (%)', v_reason;
end $$;

-- ── TEST 123 ───────────────────────────────────────────────────────
-- บัญชีที่ถูกระงับรีเซ็ตรหัสผ่านไม่ได้
--
-- การรีเซ็ตต้องไม่กลายเป็นทางลัดที่ทำให้บัญชีซึ่งถูกสั่งระงับกลับมาใช้ได้เอง
do $$
declare v_r record;
begin
  update user_credential set disabled_at = now()
   where id = 'bbbb0000-0000-0000-0000-0000000000e2';

  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69PWR00002', 'staff_counter',
    sha256('code-disabled'::bytea), null, 'aaaa0000-0000-0000-0000-0000000000c1');

  if v_r.issued then
    raise exception 'TEST 123 ล้มเหลว: ออกรหัสรีเซ็ตให้บัญชีที่ถูกระงับ';
  end if;

  -- แม้มีรหัสค้างอยู่จากตอนที่ยังไม่ถูกระงับ ก็ต้องใช้ไม่ได้
  select * into v_r from consume_password_reset(
    '11111111-1111-1111-1111-111111111111', '69PWR00002',
    sha256('code-counter'::bytea), 'scrypt$16384$8$1$AAAA$NOPE');

  if v_r.ok then
    raise exception 'TEST 123 ล้มเหลว: บัญชีที่ถูกระงับใช้รหัสที่ค้างอยู่รีเซ็ตได้';
  end if;

  update user_credential set disabled_at = null
   where id = 'bbbb0000-0000-0000-0000-0000000000e2';
  raise notice 'TEST 123 ผ่าน — บัญชีที่ถูกระงับทั้งขอใหม่และใช้รหัสที่ค้างอยู่ไม่ได้';
end $$;

-- ── TEST 124 ───────────────────────────────────────────────────────
-- คนที่ไม่มีช่องทางติดต่อบันทึกไว้ ขอรีเซ็ตเองไม่ได้ ต้องผ่านเจ้าหน้าที่
--
-- เป็นกรณีที่พบบ่อยที่สุด ไม่ใช่ข้อยกเว้น — นักศึกษาอาชีวะจำนวนมาก
-- ไม่มีอีเมลของตัวเองตอนเข้าเรียน ระบบต้องไม่ทำเป็นว่าส่งไปแล้ว
do $$
declare v_r record;
begin
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69PWR00002', null,
    sha256('code-nochannel'::bytea), null, null);

  if v_r.issued then
    raise exception 'TEST 124 ล้มเหลว: ออกรหัสทั้งที่ไม่มีช่องทางส่ง — รหัสหายไปเฉย ๆ';
  end if;
  if v_r.reason <> 'ไม่มีช่องทางติดต่อที่บันทึกไว้' then
    raise exception 'TEST 124 ล้มเหลว: เหตุผลไม่ตรง — %', v_r.reason;
  end if;
  raise notice 'TEST 124 ผ่าน — ไม่มีช่องทางติดต่อแล้วไม่ออกรหัสให้ (%)', v_r.reason;
end $$;

-- ── TEST 125 ───────────────────────────────────────────────────────
-- เพดานรายวัน — ทั้งรายบัญชีและรายไอพี
--
-- โควตารายบัญชีกันคนกดรัว ๆ ได้ แต่กันการยิงขอรีเซ็ตให้คนทั้งวิทยาลัย
-- ไม่ได้เลย เพราะแต่ละบัญชีถูกขอแค่ครั้งเดียว ต้องมีทั้งคู่ (หลักเดียวกับ 0021)
do $$
declare v_r record; v_ip bytea := sha256('ip-flood'::bytea);
begin
  -- รายบัญชี: นโยบายตั้งไว้ 3 ครั้งต่อวัน และวันนี้ใช้ไปแล้ว 3 ใบ
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005', null,
    sha256('code-over'::bytea), null, null);

  if v_r.issued then
    raise exception 'TEST 125 ล้มเหลว: ขอรีเซ็ตเกินโควตารายบัญชีได้';
  end if;
  if v_r.reason <> 'ขอรีเซ็ตบัญชีนี้บ่อยเกินกำหนด' then
    raise exception 'TEST 125 ล้มเหลว: เหตุผลรายบัญชีไม่ตรง — %', v_r.reason;
  end if;

  -- แต่คนเดิมต้องเดินไปที่เคาน์เตอร์แล้วขอได้อยู่ มิฉะนั้นคนที่กรอกรหัสผิด
  -- จนถูกยกเลิกสามรอบจะไม่มีทางออกเลยจนกว่าจะพ้นยี่สิบสี่ชั่วโมง
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '67201010005', 'staff_counter',
    sha256('code-counter-over'::bytea), null, 'aaaa0000-0000-0000-0000-0000000000c1');
  if not v_r.issued then
    raise exception 'TEST 125 ล้มเหลว: เคาน์เตอร์ติดเพดานรายบัญชีด้วย — %', v_r.reason;
  end if;

  -- รายไอพี: ลดเพดานลงเหลือ 2 เพื่อไม่ต้องสร้างบัญชีสิบห้าบัญชีในเทสต์
  update auth_policy set max_reset_per_ip_day = 2
   where institution_id = '11111111-1111-1111-1111-111111111111';

  -- ยิงไปยังบัญชีที่มีอยู่จริงคนละคน — โควตารายบัญชีกันกรณีนี้ไม่ได้เลย
  -- เพราะแต่ละบัญชีถูกขอแค่ครั้งเดียว แต่ผู้ใช้ทั้งวิทยาลัยได้รับอีเมลกันหมด
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69IP00001', null,
    sha256('flood-1'::bytea), v_ip, null);
  if not v_r.issued then
    raise exception 'TEST 125 ล้มเหลว: คำขอแรกจากไอพีนี้ถูกปฏิเสธ — %', v_r.reason;
  end if;

  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69IP00002', null,
    sha256('flood-2'::bytea), v_ip, null);
  if not v_r.issued then
    raise exception 'TEST 125 ล้มเหลว: คำขอที่สองจากไอพีนี้ถูกปฏิเสธ — %', v_r.reason;
  end if;

  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69IP00003', null,
    sha256('flood-3'::bytea), v_ip, null);
  if v_r.reason is distinct from 'ขอรีเซ็ตจากที่อยู่นี้บ่อยเกินกำหนด' then
    raise exception 'TEST 125 ล้มเหลว: เพดานรายไอพีไม่ทำงาน — %',
      coalesce(v_r.reason, 'ออกรหัสให้ทั้งที่เกินเพดาน');
  end if;

  -- แต่เคาน์เตอร์งานทะเบียนต้องไม่ติดเพดานนี้ มิฉะนั้นวันเปิดเทอมจะตันตั้งแต่สาย
  -- แล้วเจ้าหน้าที่จะกลับไปตั้งรหัสผ่านให้เอง ซึ่งเป็นสิ่งที่ 0025 ต้องการเลิก
  select * into v_r from request_password_reset(
    '11111111-1111-1111-1111-111111111111', '69IP00003', 'staff_counter',
    sha256('flood-counter'::bytea), v_ip, 'aaaa0000-0000-0000-0000-0000000000c1');
  if not v_r.issued then
    raise exception 'TEST 125 ล้มเหลว: เคาน์เตอร์งานทะเบียนติดเพดานรายไอพี — %', v_r.reason;
  end if;

  update auth_policy set max_reset_per_ip_day = 15
   where institution_id = '11111111-1111-1111-1111-111111111111';
  raise notice 'TEST 125 ผ่าน — เพดานรายบัญชีและรายไอพีทำงานทั้งคู่ · เคาน์เตอร์ไม่ติดเพดานรายไอพี';
end $$;

-- ── TEST 126 ───────────────────────────────────────────────────────
-- Row-Level Security — วิทยาลัยอื่นและนักศึกษาคนอื่นต้องไม่เห็นคำขอ
--
-- คนที่อ่านตารางนี้ได้จะรู้ว่าบัญชีไหนกำลังมีรหัสรีเซ็ตค้างอยู่
-- ซึ่งเป็นข้อมูลที่ใช้เลือกเป้าหมายได้ทันที
begin;
set local role app_runtime;

set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'registrar';
set local app.actor_id = 'aaaa0000-0000-0000-0000-0000000000c1';
do $$
declare v int;
begin
  select count(*) into v from password_reset;
  if v <> 0 then
    raise exception 'TEST 126 ล้มเหลว: วิทยาลัยอื่นเห็นคำขอรีเซ็ต % รายการ', v;
  end if;
  raise notice 'TEST 126 ผ่าน — วิทยาลัยอื่นไม่เห็นคำขอรีเซ็ตเลย';
end $$;

set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'bbbb0000-0000-0000-0000-0000000000d1';
do $$
declare v_own int; v_other int;
begin
  select count(*) into v_own from password_reset
   where person_id = 'bbbb0000-0000-0000-0000-0000000000d1';
  select count(*) into v_other from password_reset
   where person_id = 'aaaa0000-0000-0000-0000-000000000001';

  if v_other <> 0 then
    raise exception 'TEST 126b ล้มเหลว: นักศึกษาเห็นคำขอรีเซ็ตของเพื่อน % รายการ', v_other;
  end if;
  if v_own = 0 then
    raise exception 'TEST 126b ล้มเหลว: นักศึกษาไม่เห็นคำขอของตัวเองเลย';
  end if;
  raise notice 'TEST 126b ผ่าน — นักศึกษาเห็นเฉพาะคำขอของตัวเอง % รายการ ไม่เห็นของเพื่อน', v_own;
end $$;
commit;

-- ── TEST 127 ───────────────────────────────────────────────────────
-- ลบคำขอของวันนี้ไม่ได้แม้แต่ admin · ล้างของเก่าได้ · ตั้งต่ำกว่า 90 วันไม่ได้
--
-- บันทึกว่าใครขอรีเซ็ตบัญชีของใครเป็นหลักฐานชิ้นแรกเวลาสงสัยว่าบัญชีถูกยึด
-- ถ้าลบได้ หลักฐานจะหายไปพร้อมกับคนที่ก่อเหตุ
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'admin';
set local app.actor_id = 'aaaa0000-0000-0000-0000-0000000000c1';
do $$
declare v_before int; v_after int;
begin
  select count(*) into v_before from password_reset;
  delete from password_reset where created_at > now() - interval '1 day';
  select count(*) into v_after from password_reset;

  if v_after <> v_before then
    raise exception 'TEST 127 ล้มเหลว: admin ลบคำขอรีเซ็ตของวันนี้ได้ (% → %)', v_before, v_after;
  end if;
  raise notice 'TEST 127 ผ่าน — admin ลบคำขอของวันนี้ไม่ได้ (เหลือ % รายการเท่าเดิม)', v_after;
end $$;
commit;

do $$
declare v_n int;
begin
  begin
    perform purge_password_reset(30);
    raise exception 'TEST 127b ล้มเหลว: ตั้งระยะเก็บต่ำกว่า 90 วันได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 127b%' then raise; end if;
      null;
  end;

  insert into password_reset
    (institution_id, person_id, credential_id, token_hash, channel,
     created_at, expires_at)
  values ('11111111-1111-1111-1111-111111111111',
          'aaaa0000-0000-0000-0000-000000000001',
          'bbbb0000-0000-0000-0000-0000000000e1',
          sha256('code-ancient'::bytea), 'sms',
          now() - interval '200 days', now() - interval '200 days' + interval '30 minutes');

  select purge_password_reset(90) into v_n;
  if v_n < 1 then
    raise exception 'TEST 127b ล้มเหลว: ล้างคำขอเก่าไม่ได้เลย ตารางจะโตไปเรื่อย ๆ';
  end if;
  raise notice 'TEST 127b ผ่าน — ตั้งต่ำกว่า 90 วันไม่ได้ · ล้างของเก่าได้ % รายการ', v_n;
end $$;

\echo ''
\echo '════ ทดสอบการรีเซ็ตรหัสผ่านครบทุกข้อ ════'

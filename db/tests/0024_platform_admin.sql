-- ═══════════════════════════════════════════════════════════════════
-- 0024_platform_admin.sql
-- ทดสอบขอบเขตของผู้ดูแลระดับผู้ให้บริการ
--
-- ─── ทำไมชุดนี้สำคัญกว่าชุดอื่น ───
-- หน้าจอผู้ดูแลข้ามวิทยาลัยคือสิ่งเดียวในระบบที่ **ตั้งใจ** ให้มองเห็น
-- ทุกวิทยาลัยพร้อมกัน ถ้าขอบเขตของมันผิดแม้ข้อเดียว บัญชีเดียวจะดูดข้อมูล
-- ส่วนบุคคลของทุกวิทยาลัยได้จากที่เดียว — ซึ่งเป็นสิ่งที่ RLS ทั้งระบบ
-- ถูกสร้างมาเพื่อกัน
--
-- ─── ต้อง set local role app_runtime เสมอ ───
-- run.sh ต่อด้วย postgres ซึ่งเป็น superuser และ superuser ข้าม RLS
-- ทุกกรณีแม้ตารางจะตั้ง force ไว้ เทสต์ที่ลืมสลับบทบาทจะผ่านโดยไม่ได้
-- ทดสอบนโยบายเลยสักข้อ (หลักเดียวกับ TEST 10 และ TEST 183)
--
-- ─── รูปแบบการเขียนข้อที่ต้อง "ถูกปฏิเสธ" ───
-- ห้าม raise ข้อความ "ล้มเหลว" ไว้ข้างใน begin...exception ของตัวเอง
-- เพราะ handler จะจับข้อความของตัวเองแล้วนับว่าถูกปฏิเสธสำเร็จ
-- (เคยเขียนพลาดมาแล้วตอนร่างไฟล์นี้ — ข้อความล้มเหลวมีคำว่า "ตัวเอง"
--  ซึ่งตรงกับคำที่ใช้ตรวจ sqlerrm พอดี เทสต์จึงผ่านทั้งที่ช่องเปิดอยู่)
-- ใช้ธงกับตัวแปรเก็บ sqlerrm แล้วตัดสินข้างนอกแทน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมบัญชีผู้ให้บริการสองคนไว้ใช้ทั้งไฟล์ ──────────────────────
-- สร้างในบทบาท superuser เพราะเส้นทางติดตั้งจริงใช้ bootstrap_platform_owner()
-- ซึ่งทดสอบแยกใน TEST 191
insert into platform_user (username, display_name, role, password_hash)
values ('owner1', 'เจ้าของระบบ',   'owner',   'locked$test'),
       ('help1',  'ฝ่ายสนับสนุน', 'support', 'locked$test')
on conflict (username) do nothing;

select (select id from platform_user where username = 'owner1') as owner_id,
       (select id from platform_user where username = 'help1')  as support_id,
       (select p.id             from person p limit 1)          as person_id,
       (select p.institution_id from person p limit 1)          as inst_id \gset

-- ── TEST 186 ───────────────────────────────────────────────────────
-- บริบทผู้ให้บริการต้องอ่านข้อมูลของวิทยาลัยไม่ได้เลยสักตาราง
--
-- ─── ทำไมไล่ทุกตารางแทนที่จะเลือกมาสิบตาราง ───
-- รูปแบบความผิดพลาดที่เกิดจริงคือ "เพิ่มตารางใหม่แล้วเผลอเขียนนโยบายให้
-- ผ่านเมื่อไม่มีวิทยาลัย" (เช่น `or current_institution_id() is null` ที่
-- 0038 ใช้อย่างจงใจกับสามตาราง) การไล่ทีละตารางที่นึกออกจะไม่มีวันจับ
-- ตารางที่ยังไม่มีตอนเขียนเทสต์ ซึ่งเป็นตารางที่เสี่ยงที่สุด
--
-- ตารางที่ยกเว้นได้มีเท่านี้ และทั้งหมดไม่มีข้อมูลส่วนบุคคลสักช่อง —
-- สัญญา ปริมาณใช้งาน ประวัติการเปิดวิทยาลัย และบันทึกการกระทำของ
-- ผู้ให้บริการเอง ซึ่งเป็นข้อมูลตามสัญญาระหว่างผู้ให้บริการกับวิทยาลัย
-- ไม่ใช่ข้อมูลของนักศึกษาหรือบุคลากร
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '',          true) as a,
       set_config('app.actor_id',       :'owner_id',  true) as b,
       set_config('app.role',           'platform',   true) as c \gset ctx_

do $$
declare
  t        record;
  v_count  bigint;
  v_leaked text[] := '{}';
  v_seen   integer := 0;
begin
  for t in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attname = 'institution_id'
     where n.nspname = 'public' and c.relkind = 'r' and not a.attisdropped
       and c.relname not in ('institution_subscription', 'usage_snapshot',
                             'provisioning_log', 'platform_action_log')
     order by c.relname
  loop
    execute format('select count(*) from %I', t.relname) into v_count;
    v_seen := v_seen + 1;
    if v_count > 0 then
      v_leaked := array_append(v_leaked, t.relname || '=' || v_count);
    end if;
  end loop;

  if array_length(v_leaked, 1) > 0 then
    raise exception 'TEST 186 ล้มเหลว: บริบทผู้ให้บริการเห็นข้อมูลของวิทยาลัย — % '
      '(บัญชีเดียวอ่านข้อมูลส่วนบุคคลของทุกวิทยาลัยได้)',
      array_to_string(v_leaked, ', ');
  end if;

  -- ถ้าจำนวนตารางที่ตรวจน้อยผิดปกติ แปลว่า query ข้างบนพัง ไม่ใช่ว่าปลอดภัย
  if v_seen < 20 then
    raise exception 'TEST 186 ล้มเหลว: ตรวจได้แค่ % ตาราง — เทสต์ไม่ได้ทดสอบอะไรจริง', v_seen;
  end if;

  raise notice 'TEST 186 ผ่าน — ผู้ให้บริการอ่านข้อมูลของวิทยาลัยไม่ได้เลยทั้ง % ตาราง', v_seen;
end $$;

-- และต้องยังอ่านสิ่งที่ต้องใช้ทำงานได้จริง มิฉะนั้นหน้าจอจะว่างเปล่าทั้งหน้า
do $$
declare v_inst integer; v_plans integer;
begin
  select count(*) into v_inst  from institution;
  select count(*) into v_plans from plan;

  if v_inst = 0 then
    raise exception 'TEST 186ก ล้มเหลว: ผู้ให้บริการมองไม่เห็นทะเบียนสถานศึกษา '
      '(ปิดเกินไปจนหน้าจอข้ามวิทยาลัยใช้ไม่ได้)';
  end if;

  raise notice 'TEST 186ก ผ่าน — เห็นสถานศึกษา % แห่ง และแพ็กเกจ % รายการ ตามที่ต้องใช้',
    v_inst, v_plans;
end $$;
rollback;

-- ── TEST 187 ───────────────────────────────────────────────────────
-- ฝั่งวิทยาลัยต้องมองไม่เห็นบัญชีของผู้ให้บริการเลย
--
-- app_runtime มีสิทธิ์ select ทุกตารางอยู่แล้ว ถ้าไม่ปิดที่ RLS โค้ดฝั่ง
-- วิทยาลัยบรรทัดเดียวที่เขียนผิดจะอ่านค่าแฮชรหัสผ่านของผู้ให้บริการได้
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',   true) as a,
       set_config('app.actor_id',       :'person_id', true) as b,
       set_config('app.role',           'admin',      true) as c \gset ctx_

do $$
declare
  v_users    integer;
  v_sessions integer;
  v_log      integer;
  v_inserted boolean := false;
  v_err      text;
begin
  select count(*) into v_users    from platform_user;
  select count(*) into v_sessions from platform_session;
  select count(*) into v_log      from platform_action_log;

  if v_users <> 0 or v_sessions <> 0 or v_log <> 0 then
    raise exception 'TEST 187 ล้มเหลว: ผู้ดูแลของวิทยาลัยเห็นข้อมูลฝั่งผู้ให้บริการ '
      '(บัญชี % · session % · บันทึก %)', v_users, v_sessions, v_log;
  end if;

  -- และเขียนไม่ได้ด้วย — สร้างบัญชีผู้ให้บริการเองได้เท่ากับยึดระบบทั้งระบบ
  begin
    insert into platform_user (username, display_name, role, password_hash)
    values ('intruder', 'ผู้บุกรุก', 'owner', 'locked$x');
    v_inserted := true;
  exception
    when insufficient_privilege then v_err := sqlerrm;
  end;

  if v_inserted then
    raise exception 'TEST 187 ล้มเหลว: ผู้ดูแลของวิทยาลัยสร้างบัญชีผู้ให้บริการได้';
  end if;

  raise notice 'TEST 187 ผ่าน — ฝั่งวิทยาลัยมองไม่เห็นและสร้างบัญชีผู้ให้บริการไม่ได้';
end $$;
rollback;

-- ── TEST 188 ───────────────────────────────────────────────────────
-- การระงับต้องปิดทางเข้าจริง และวิทยาลัยต้องปลดระงับตัวเองไม่ได้
--
-- ถ้าปลดเองได้ การระงับจะเป็นแค่ธงที่ลูกค้าลบทิ้งเองได้ ซึ่งแปลว่า
-- ผู้ให้บริการไม่มีทางหยุดการใช้งานของคนที่ไม่ชำระเงินได้เลย
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '',          true) as a,
       set_config('app.actor_id',       :'owner_id',  true) as b,
       set_config('app.role',           'platform',   true) as c,
       set_config('test.inst_id',       :'inst_id',   true) as d,
       set_config('test.person_id',     :'person_id', true) as e \gset ctx_

do $$
declare
  v_inst      uuid := current_setting('test.inst_id')::uuid;
  v_suspended boolean := false;
  v_err       text;
begin
  perform suspend_institution(v_inst, 'ค้างชำระค่าบริการเกิน 60 วัน');

  if (select suspended_at from institution where id = v_inst) is null then
    raise exception 'TEST 188 ล้มเหลว: ระงับแล้วแต่ค่าไม่ถูกบันทึก';
  end if;

  -- เหตุผลว่างต้องไม่ผ่าน — ข้อความนี้คือสิ่งเดียวที่ผู้ใช้ของวิทยาลัยจะเห็น
  begin
    perform suspend_institution(v_inst, '   ');
    v_suspended := true;
  exception
    when raise_exception then v_err := sqlerrm;
  end;

  if v_suspended then
    raise exception 'TEST 188 ล้มเหลว: ระงับได้โดยไม่ต้องมีเหตุผล';
  end if;
  if position('เหตุผล' in coalesce(v_err, '')) = 0 then
    raise exception 'TEST 188 ล้มเหลว: ถูกปฏิเสธด้วยเหตุอื่น — %', v_err;
  end if;

  raise notice 'TEST 188 ผ่าน — ระงับได้และบังคับให้มีเหตุผลที่ลูกค้าอ่านเข้าใจ';
end $$;

-- ── สร้าง session ใหม่ต้องถูกปฏิเสธขณะถูกระงับ ──────────────────────
do $$
declare
  v_inst    uuid := current_setting('test.inst_id')::uuid;
  v_person  uuid := current_setting('test.person_id')::uuid;
  v_created boolean := false;
  v_err     text;
  v_still   timestamptz;
begin
  -- ต้องย้ายเข้าบริบทของวิทยาลัยก่อน เพราะ auth_session ถูก RLS กรอง
  perform set_config('app.institution_id', v_inst::text,   true);
  perform set_config('app.actor_id',       v_person::text, true);
  perform set_config('app.role',           'auth',         true);

  begin
    insert into auth_session
      (institution_id, person_id, token_hash, app_role, expires_at)
    values (v_inst, v_person, sha256('t1'::bytea), 'admin', now() + interval '1 day');
    v_created := true;
  exception
    when raise_exception then v_err := sqlerrm;
  end;

  if v_created then
    raise exception 'TEST 188ก ล้มเหลว: เข้าสู่ระบบได้ทั้งที่วิทยาลัยถูกระงับ';
  end if;
  if position('ระงับ' in coalesce(v_err, '')) = 0 then
    raise exception 'TEST 188ก ล้มเหลว: ถูกปฏิเสธด้วยเหตุอื่น — %', v_err;
  end if;

  -- และวิทยาลัยต้องปลดระงับตัวเองไม่ได้
  perform set_config('app.role', 'admin', true);
  update institution set suspended_at = null, suspended_reason = null where id = v_inst;

  select suspended_at into v_still from institution where id = v_inst;
  if v_still is null then
    raise exception 'TEST 188ก ล้มเหลว: วิทยาลัยปลดระงับตัวเองได้ '
      '(การระงับกลายเป็นแค่ธงที่ลูกค้าลบเองได้)';
  end if;

  raise notice 'TEST 188ก ผ่าน — ถูกระงับแล้วสร้าง session ไม่ได้ และปลดระงับเองไม่ได้';
end $$;

-- ── ปลดระงับแล้วต้องกลับมาใช้ได้ทันที ───────────────────────────────
do $$
declare
  v_inst   uuid := current_setting('test.inst_id')::uuid;
  v_person uuid := current_setting('test.person_id')::uuid;
  v_id     uuid;
begin
  perform set_config('app.institution_id', '',         true);
  perform set_config('app.role',           'platform', true);
  perform resume_institution(v_inst);

  perform set_config('app.institution_id', v_inst::text,   true);
  perform set_config('app.actor_id',       v_person::text, true);
  perform set_config('app.role',           'auth',         true);

  insert into auth_session
    (institution_id, person_id, token_hash, app_role, expires_at)
  values (v_inst, v_person, sha256('t2'::bytea), 'admin', now() + interval '1 day')
  returning id into v_id;

  if v_id is null then
    raise exception 'TEST 188ข ล้มเหลว: ปลดระงับแล้วยังเข้าระบบไม่ได้';
  end if;

  raise notice 'TEST 188ข ผ่าน — ปลดระงับแล้วเข้าระบบได้ทันที ข้อมูลไม่ถูกแตะต้องเลย';
end $$;
rollback;

-- ── TEST 189 ───────────────────────────────────────────────────────
-- บันทึกการกระทำของผู้ให้บริการต้องแก้ไม่ได้และลบไม่ได้
--
-- บันทึกที่ผู้ให้บริการลบเองได้ ใช้ตอบลูกค้าว่า "ไม่มีใครเข้าไปยุ่งกับ
-- ข้อมูลของท่าน" ไม่ได้ เพราะคำตอบนั้นพิสูจน์ไม่ได้ (หลักเดียวกับ access_log)
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '',         true) as a,
       set_config('app.actor_id',       :'owner_id', true) as b,
       set_config('app.role',           'platform',  true) as c,
       set_config('test.inst_id',       :'inst_id',  true) as d \gset ctx_

do $$
declare
  v_inst    uuid := current_setting('test.inst_id')::uuid;
  v_id      bigint;
  v_who     text;
  v_updated boolean := false;
  v_deleted integer;
  v_err     text;
begin
  v_id := log_platform_action('suspend_institution', v_inst,
                              jsonb_build_object('reason', 'ค้างชำระ'), null);

  select username into v_who from platform_action_log where id = v_id;
  if v_who <> 'owner1' then
    raise exception 'TEST 189 ล้มเหลว: บันทึกไม่ได้ตรึงชื่อผู้กระทำไว้ (%)', v_who;
  end if;

  begin
    update platform_action_log set action = 'อย่างอื่น' where id = v_id;
    v_updated := found;
  exception
    when insufficient_privilege then v_err := sqlerrm;
  end;

  if v_updated then
    raise exception 'TEST 189 ล้มเหลว: ผู้ให้บริการแก้บันทึกของตัวเองได้';
  end if;

  delete from platform_action_log where id = v_id;
  get diagnostics v_deleted = row_count;
  if v_deleted <> 0 then
    raise exception 'TEST 189 ล้มเหลว: ลบบันทึกของตัวเองได้ % แถว', v_deleted;
  end if;

  raise notice 'TEST 189 ผ่าน — บันทึกการกระทำเขียนได้อย่างเดียว แก้และลบไม่ได้';
end $$;
rollback;

-- ── TEST 190 ───────────────────────────────────────────────────────
-- ยกระดับสิทธิ์ของตัวเองไม่ได้ แต่ยังตั้งรหัสผ่านของตัวเองได้
--
-- นโยบายต้องยอมให้แก้แถวของตัวเอง (เปลี่ยนรหัสผ่าน ตั้ง TOTP) ซึ่งแปลว่า
-- ถ้าไม่มี trigger กั้น support จะตั้ง role ของตัวเองเป็น owner ได้ในคำสั่งเดียว
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '',            true) as a,
       set_config('app.actor_id',       :'support_id', true) as b,
       set_config('app.role',           'platform',    true) as c,
       set_config('test.owner_id',      :'owner_id',   true) as d,
       set_config('test.support_id',    :'support_id', true) as e \gset ctx_

do $$
declare
  v_support uuid := current_setting('test.support_id')::uuid;
  v_owner   uuid := current_setting('test.owner_id')::uuid;
  v_self    boolean := false;
  v_other   boolean := false;
  v_err1    text;
  v_err2    text;
begin
  -- 1. ยกระดับตัวเอง
  begin
    update platform_user set role = 'owner' where id = v_support;
    v_self := true;
  exception
    when raise_exception then v_err1 := sqlerrm;
  end;

  -- 2. เปลี่ยนบทบาทของคนอื่นทั้งที่ตัวเองไม่ใช่ owner
  begin
    update platform_user set role = 'billing' where id = v_owner;
    v_other := true;
  exception
    when raise_exception then v_err2 := sqlerrm;
  end;

  if v_self then
    raise exception 'TEST 190 ล้มเหลว: support ยกระดับบัญชีของตนเป็น owner ได้';
  end if;
  if v_other then
    raise exception 'TEST 190 ล้มเหลว: support เปลี่ยนบทบาทของบัญชีอื่นได้';
  end if;
  if position('owner' in coalesce(v_err2, '')) = 0 then
    raise exception 'TEST 190 ล้มเหลว: ถูกปฏิเสธด้วยเหตุอื่น — %', v_err2;
  end if;

  -- 3. แต่ยังต้องแก้ของตัวเองได้ตามปกติ มิฉะนั้นตั้งรหัสผ่านครั้งแรกไม่ได้
  update platform_user set password_hash = 'scrypt$new', must_change = false
   where id = v_support;
  if not found then
    raise exception 'TEST 190 ล้มเหลว: เจ้าตัวเปลี่ยนรหัสผ่านของตัวเองไม่ได้ '
      '(ปิดเกินไปจนบัญชีใหม่ตั้งรหัสผ่านครั้งแรกไม่ได้)';
  end if;

  raise notice 'TEST 190 ผ่าน — ยกระดับสิทธิ์ไม่ได้ แต่ยังตั้งรหัสผ่านของตัวเองได้';
end $$;
rollback;

-- ── TEST 190ก ──────────────────────────────────────────────────────
-- owner คนสุดท้ายต้องถูกถอดไม่ได้ มิฉะนั้นจะไม่มีใครแต่งตั้งใครได้อีกเลย
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '',            true) as a,
       set_config('app.actor_id',       :'owner_id',   true) as b,
       set_config('app.role',           'platform',    true) as c,
       set_config('test.owner_id',      :'owner_id',   true) as d,
       set_config('test.support_id',    :'support_id', true) as e \gset ctx_

do $$
declare
  v_owner   uuid := current_setting('test.owner_id')::uuid;
  v_support uuid := current_setting('test.support_id')::uuid;
  v_demoted boolean := false;
  v_err     text;
begin
  begin
    update platform_user set role = 'support' where id = v_owner;
    v_demoted := true;
  exception
    when raise_exception then v_err := sqlerrm;
  end;

  if v_demoted then
    raise exception 'TEST 190ก ล้มเหลว: ถอด owner คนสุดท้ายได้ ระบบจะไม่เหลือผู้ดูแลเลย';
  end if;

  -- owner แต่งตั้งคนที่สองได้ ซึ่งเป็นทางออกที่ถูกต้องของข้อจำกัดข้างบน
  update platform_user set role = 'owner' where id = v_support;
  if not found then
    raise exception 'TEST 190ก ล้มเหลว: owner แต่งตั้งบัญชีอื่นเป็น owner ไม่ได้';
  end if;

  raise notice 'TEST 190ก ผ่าน — owner คนสุดท้ายถูกถอดไม่ได้ แต่แต่งตั้งเพิ่มได้';
end $$;
rollback;

-- ── TEST 191 ───────────────────────────────────────────────────────
-- bootstrap_platform_owner() ใช้ได้ครั้งเดียวจริง ๆ
--
-- ถ้าเรียกซ้ำได้ มันจะกลายเป็นประตูหลังที่ใครก็ตามที่มี PROVISION_KEY
-- แต่งตั้งตัวเองเป็น owner ได้ตลอดเวลา
-- ═══════════════════════════════════════════════════════════════════
do $$
declare v_made boolean := false; v_err text;
begin
  begin
    perform bootstrap_platform_owner('owner2', 'เจ้าของอีกคน', null,
                                     sha256('code'::bytea), 60);
    v_made := true;
  exception
    when raise_exception then v_err := sqlerrm;
  end;

  if v_made then
    raise exception 'TEST 191 ล้มเหลว: สร้างบัญชีแรกซ้ำได้ทั้งที่มีบัญชีอยู่แล้ว';
  end if;
  if position('มีบัญชีผู้ให้บริการอยู่แล้ว' in coalesce(v_err, '')) = 0 then
    raise exception 'TEST 191 ล้มเหลว: ถูกปฏิเสธด้วยเหตุอื่น — %', v_err;
  end if;

  raise notice 'TEST 191 ผ่าน — สร้างบัญชีผู้ให้บริการคนแรกซ้ำไม่ได้';
end $$;

-- ── TEST 192 ───────────────────────────────────────────────────────
-- ตัวนับของ MFA และของการล็อกอินต้องไม่ถูก rollback
--
-- กับดักที่เคยกัดมาแล้วสองครั้ง (0021 · 0036) — ฟังก์ชันที่นับจำนวนครั้ง
-- ห้าม raise เพราะ rollback จะล้างตัวนับทิ้ง แล้วเดารหัสได้ไม่จำกัด
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '',         true) as a,
       set_config('app.actor_id',       :'owner_id', true) as b,
       set_config('app.role',           'platform',  true) as c,
       set_config('test.owner_id',      :'owner_id', true) as d \gset ctx_

do $$
declare
  v_owner uuid := current_setting('test.owner_id')::uuid;
  r       record;
  v_fail  integer;
begin
  update platform_user set totp_secret_enc = '\x00'::bytea where id = v_owner;

  -- รหัสผิดต้องคืนค่า ไม่ใช่ raise และตัวนับต้องขยับ
  select * into r from platform_totp_verify(v_owner, 100, false);
  if r.ok then raise exception 'TEST 192 ล้มเหลว: รหัสผิดแต่ผ่าน'; end if;

  select mfa_failed_attempts into v_fail from platform_user where id = v_owner;
  if v_fail <> 1 then
    raise exception 'TEST 192 ล้มเหลว: ตัวนับไม่ขยับ (%) — เดารหัสหกหลักได้ไม่จำกัด', v_fail;
  end if;

  select * into r from platform_totp_verify(v_owner, 100, true);
  if not r.ok then
    raise exception 'TEST 192 ล้มเหลว: รหัสถูกแต่ไม่ผ่าน (%)', r.reason;
  end if;

  -- ช่วงเวลาเดิมต้องใช้ซ้ำไม่ได้ — คนที่แอบเห็นรหัสบนหน้าจอใช้ตามไม่ได้
  select * into r from platform_totp_verify(v_owner, 100, true);
  if r.ok then
    raise exception 'TEST 192 ล้มเหลว: ใช้รหัสของช่วงเวลาเดิมซ้ำได้';
  end if;

  raise notice 'TEST 192 ผ่าน — ตัวนับ MFA ขยับจริงและใช้รหัสซ้ำไม่ได้';
end $$;

do $$
declare r record; v_ip bytea := sha256('1.2.3.4'::bytea);
begin
  for i in 1..10 loop
    insert into platform_login_attempt (username, succeeded, reason, ip_hash)
    values ('owner1', false, 'รหัสผ่านไม่ถูกต้อง', v_ip);
  end loop;

  select * into r from platform_login_rate_status(v_ip);
  if not r.blocked then
    raise exception 'TEST 192ก ล้มเหลว: ยิงผิด % ครั้งแล้วยังไม่ถูกบล็อก', r.recent_failures;
  end if;
  if r.retry_after_secs <= 0 then
    raise exception 'TEST 192ก ล้มเหลว: ไม่ได้บอกว่าต้องรออีกนานเท่าไร';
  end if;

  select * into r from platform_login_rate_status(sha256('9.9.9.9'::bytea));
  if r.blocked then
    raise exception 'TEST 192ก ล้มเหลว: ไอพีอื่นถูกบล็อกไปด้วย';
  end if;

  raise notice 'TEST 192ก ผ่าน — จำกัดจำนวนครั้งรายไอพีได้และไม่กระทบไอพีอื่น';
end $$;
rollback;

-- ── เก็บกวาด ────────────────────────────────────────────────────────
delete from platform_user where username in ('owner1', 'help1');

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตผู้ให้บริการครบทุกข้อ ════'; end $$;

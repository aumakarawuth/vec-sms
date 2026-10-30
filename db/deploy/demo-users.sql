-- ═══════════════════════════════════════════════════════════════════
-- demo-users.sql
-- บัญชีตัวอย่างครบทุกบทบาท — ฉบับที่ใช้ psql อย่างเดียว ไม่ต้องมี API รันอยู่
--
--   psql -v ON_ERROR_STOP=1 -f db/deploy/demo-users.sql vecsms_api_test
--
-- ═══ ห้ามรันกับฐานข้อมูลของวิทยาลัยจริงเด็ดขาด ═══
-- ไฟล์นี้เขียนรหัสผ่านไว้ในตัวมันเอง และหนึ่งในบัญชีที่สร้างคือ admin
-- ซึ่งเห็นข้อมูลทั้งวิทยาลัย ใครที่อ่าน repo ได้จึงเข้าระบบนั้นได้ทันที
-- — จึงมีรายชื่อฐานที่อนุญาตอยู่ข้างล่าง และล้มทันทีถ้าชื่อไม่อยู่ในนั้น
--
-- ═══ ทำไมอยู่ใน db/deploy/ ไม่ใช่ db/seed/ ═══
-- `db/run.sh` รันทุกไฟล์ใน `db/seed/` ทุกครั้งที่สร้างฐานใหม่ — บัญชี admin
-- ที่รหัสผ่านอยู่ใน repo จะติดไปกับการซ้อม deploy ด้วย ส่วน `db/deploy/`
-- ไม่มีอะไรรันให้อัตโนมัติ ต้องพิมพ์คำสั่งเอง ซึ่งเป็นสิ่งที่ต้องการ
--
-- ═══ ความสัมพันธ์กับ api/tools/seed-demo-users.cjs ═══
-- **สองไฟล์นี้สร้างคนชุดเดียวกัน ด้วย UUID · ชื่อผู้ใช้ · รหัสผ่านเดียวกัน**
-- จึง upsert ทับกันได้ทั้งสองทาง รันตัวไหนก่อนก็ได้ ผลลัพธ์ลงที่เดิม
--
--   ไฟล์นี้ (.sql)  ต้องมีแค่ psql — ใช้ได้ทันทีหลัง prepare-db.sh
--                   ยังไม่ต้อง build api และยังไม่ต้องสตาร์ต API
--   .cjs            ต้อง build + API รันอยู่ แต่ทำสิ่งที่ SQL ทำไม่ได้สองอย่าง
--                   คือ **ผูก MFA ให้ admin/director** และ **ตรวจด้วยการ
--                   ล็อกอินจริง** ซึ่งเป็นการพิสูจน์ที่แถวในตารางให้ไม่ได้
--
-- แก้รายชื่อบัญชีที่ไฟล์ไหน ต้องแก้อีกไฟล์ให้ตรงกันเสมอ
--
-- ═══ ทำไมค่าแฮชรหัสผ่านเป็นค่าคงที่ในไฟล์ ═══
-- ระบบแฮชด้วย scrypt ที่มากับ Node (`api/src/common/auth/password.ts`)
-- ซึ่ง PostgreSQL คำนวณเองไม่ได้ (pgcrypto ไม่มี scrypt) การลอกสูตรมาไว้
-- ในไฟล์นี้ทำไม่ได้ ทางที่เหลือคือฝังค่าที่แฮชไว้แล้วลงไปตรง ๆ
--
-- ค่านี้ยังใช้ได้แม้ค่าพารามิเตอร์เริ่มต้นของ scrypt จะเปลี่ยนในอนาคต
-- เพราะ `verifyPassword()` อ่านพารามิเตอร์จากตัวสตริงที่เก็บไว้ ไม่ใช่จาก
-- ค่าปัจจุบันของระบบ — แต่ถ้าวันหนึ่ง **รูปแบบ** ของสตริงเปลี่ยน
-- (เช่นเปลี่ยนไปใช้อัลกอริทึมอื่น) บัญชีชุดนี้จะล็อกอินไม่ได้เงียบ ๆ
-- ตัวที่จับได้คือ .cjs ซึ่งตรวจด้วยการล็อกอินจริง — จึงควรรันตัวนั้นตามหลัง
-- อย่างน้อยครั้งหนึ่งหลังแตะเรื่องรหัสผ่าน
--
-- ═══ ต้องรันด้วยผู้ใช้ที่เป็นเจ้าของฐานข้อมูล ═══
-- ไม่ใช่ `vecsms_app` เพราะบริบท `app.*` ยังไม่มีตอนรันจากบรรทัดคำสั่ง
-- ทุกนโยบาย RLS จึงปฏิเสธทุกแถว (ตั้งใจให้เป็นแบบนั้น)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

begin;

/*
 * ─── รายชื่อฐานที่ยอมให้เขียน ───
 * เป็นรายชื่อ ไม่ใช่สวิตช์ `-v force=1` โดยตั้งใจ — สวิตช์กดผ่านได้ด้วย
 * ความเคยชิน ส่วนการต้องพิมพ์ชื่อฐานให้ตรงบังคับให้อ่านว่ากำลังเขียนใส่ฐานไหน
 *
 * ตรวจ `current_database()` ไม่ใช่พารามิเตอร์ที่ผู้เรียกส่งมา เพราะสิ่งที่
 * ต้องกันคือ "ต่อผิดฐาน" ซึ่งพารามิเตอร์ที่พิมพ์เองไม่ได้บอกความจริง
 */
do $$
begin
  if current_database() not in ('vecsms_api_test', 'vecsms_dev', 'vecsms_demo') then
    raise exception
      'ปฏิเสธการเขียนบัญชีตัวอย่างลงฐาน "%" — ไฟล์นี้มีรหัสผ่านของบัญชี admin '
      'อยู่ใน repo จึงรันได้เฉพาะฐานสำหรับพัฒนา (vecsms_api_test · vecsms_dev · vecsms_demo)',
      current_database();
  end if;
end $$;

/*
 * ─── วิทยาลัยและรหัสผ่าน ───
 * รหัสผ่านเดียวกันทุกบัญชีเพราะเป็นชุดสาธิต ไม่ใช่ของใครจริง ๆ
 * ค่าแฮชด้านล่างคือ 'Demo!vec2569' — ต้องตรงกับ PASSWORD ใน .cjs
 */
create temporary table _demo on commit drop as
select
  '11111111-1111-1111-1111-111111111111'::uuid as institution_id,
  'Demo!vec2569'::text as password_plain,
  'scrypt$16384$8$1$lfzp0yVTlX9p+caVd8USmw==$L7DB0k/9yj6r3b7o4jtjFWdzUtk8YHv2EDACti+/DzB9tfZxvmGpfTYe2MBcTyTGOEv/e7nMESpQXugnK9QxtA=='::text
    as password_hash;

do $$
declare v_inst uuid;
begin
  select institution_id into v_inst from _demo;
  if not exists (select 1 from institution where id = v_inst) then
    raise exception 'ไม่พบวิทยาลัยตัวอย่าง % ในฐานนี้ — ฐานนี้ยังไม่ได้รัน db/seed หรือใช้รหัสวิทยาลัยอื่น', v_inst;
  end if;
end $$;

/*
 * ─── บุคลากรหนึ่งคนต่อหนึ่งค่าใน staff_role_kind ───
 * ตั้งแต่ 0095 คนคนเดียวถือหลายบทบาทซ้อนกันได้จริง (login_roles_for()
 * คืนทั้งชุด ไม่ยุบเหลือตัวเดียวแบบ login_role_for() อีกต่อไป) แต่บัญชี
 * สาธิตชุดนี้ยังคงหนึ่งคนต่อหนึ่งบทบาทโดยตั้งใจ — เพื่อให้กดทดสอบแต่ละฝ่าย
 * แยกจากกันได้ชัดเจน ไม่ปนกัน ต้องการทดสอบหลายบทบาทซ้อนกันให้มอบบทบาท
 * เพิ่มเองผ่านหน้า /hr หลังจากมีบัญชีเหล่านี้แล้ว
 */
create temporary table _staff on commit drop as
select * from (values
  ('20000000-0000-0000-0000-000000000001'::uuid, '21000000-0000-0000-0000-000000000001'::uuid,
   'S-ADM01', 'admin.demo',     'admin'::staff_role_kind,           'นาย',    'อดิศร',      'มั่นคงระบบ',   'male'::gender_kind),
  ('20000000-0000-0000-0000-000000000002'::uuid, '21000000-0000-0000-0000-000000000002'::uuid,
   'S-DIR01', 'director.demo',  'director'::staff_role_kind,        'นาย',    'ดำรงศักดิ์', 'วิสัยทัศน์',   'male'::gender_kind),
  ('20000000-0000-0000-0000-000000000003'::uuid, '21000000-0000-0000-0000-000000000003'::uuid,
   'S-REG01', 'registrar.demo', 'registrar'::staff_role_kind,       'นางสาว', 'ทิพวรรณ',    'ทะเบียนดี',    'female'::gender_kind),
  ('20000000-0000-0000-0000-000000000004'::uuid, '21000000-0000-0000-0000-000000000004'::uuid,
   'S-ACA01', 'academic.demo',  'academic'::staff_role_kind,        'นาง',    'วิชญา',      'หลักสูตรงาม',  'female'::gender_kind),
  ('20000000-0000-0000-0000-000000000005'::uuid, '21000000-0000-0000-0000-000000000005'::uuid,
   'S-FIN01', 'finance.demo',   'finance'::staff_role_kind,         'นางสาว', 'พรทิพย์',    'บัญชีแม่น',    'female'::gender_kind),
  ('20000000-0000-0000-0000-000000000006'::uuid, '21000000-0000-0000-0000-000000000006'::uuid,
   'S-AFF01', 'affairs.demo',   'student_affairs'::staff_role_kind, 'นาย',    'สุรชัย',     'ปกครองดี',     'male'::gender_kind),
  ('20000000-0000-0000-0000-000000000007'::uuid, '21000000-0000-0000-0000-000000000007'::uuid,
   'S-SEC01', 'secretary.demo', 'secretary'::staff_role_kind,       'นางสาว', 'อัญชลี',     'จดหมายเหตุ',   'female'::gender_kind),
  ('20000000-0000-0000-0000-000000000008'::uuid, '21000000-0000-0000-0000-000000000008'::uuid,
   'S-HR01',  'hr.demo',        'hr'::staff_role_kind,              'นาย',    'ประเสริฐ',   'คนสำคัญ',      'male'::gender_kind)
) as v(person_id, staff_id, staff_code, username, role, prefix_th, first_name_th, last_name_th, gender);

insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
select s.person_id, d.institution_id, s.prefix_th, s.first_name_th, s.last_name_th, s.gender
  from _staff s, _demo d
on conflict (id) do update
  set prefix_th     = excluded.prefix_th,
      first_name_th = excluded.first_name_th,
      last_name_th  = excluded.last_name_th;

insert into staff (id, institution_id, person_id, staff_code, is_teacher, active)
select s.staff_id, d.institution_id, s.person_id, s.staff_code, false, true
  from _staff s, _demo d
on conflict (id) do update
  set staff_code = excluded.staff_code, is_teacher = false, active = true;

/*
 * `staff_role` มี exclusion constraint กันช่วงเวลาซ้อน จึงใช้ `on conflict`
 * ไม่ได้ — ต้องลบของเดิมก่อน (เหมือนที่ .cjs ทำ)
 */
delete from staff_role sr using _staff s where sr.staff_id = s.staff_id;

insert into staff_role (staff_id, role, effective_from, reason)
select s.staff_id, s.role, current_date, 'บัญชีตัวอย่างสำหรับทดสอบหน้าจอ'
  from _staff s;

/*
 * ─── ครู · นักศึกษา · ผู้ปกครอง ผูกกับคนที่ demo-data.sql สร้าง ───
 * สามคนนี้ต้องมีข้อมูลจริงห้อยอยู่ (กลุ่มเรียน · เกรด · ค่าเทอม) มิฉะนั้น
 * จะได้บัญชีที่เข้าไปแล้วหน้าจอว่างเปล่า ซึ่งใช้ดูอะไรไม่ได้
 *
 * ─── ข้ามไปเงียบ ๆ ถ้ายังไม่ได้รัน demo-data.sql ───
 * `db/seed/` มีแต่ข้อมูลอ้างอิง (ภาคเรียน · รายวิชา · นโยบาย · ค่าธรรมเนียม)
 * **ไม่มีคนเลยสักคน** — ตอนแรกไฟล์นี้ชี้ไปที่ person ของ fixture เทสต์
 * ซึ่งบังเอิญมีอยู่ในฐานที่กำลังใช้ แต่ไม่มีในฐานที่สร้างใหม่ พอ
 * `prepare-db.sh` ล้างฐานจึงล้มด้วย foreign key ทันที
 *
 * ตอนนี้ได้หกบัญชีที่เป็นบุคลากรไปก่อน แล้วอีกสามบัญชีจะมาเมื่อรัน
 * demo-data.sql — ดีกว่าล้มทั้งไฟล์
 */
create temporary table _existing on commit drop as
select v.person_id, v.username from (values
  ('e0000000-0000-0000-0000-000000000001'::uuid, 'teacher.demo'),
  ('f0000000-0000-0000-0000-000000000001'::uuid, 'student.demo')
) as v(person_id, username)
 where exists (select 1 from person p where p.id = v.person_id);

/*
 * ─── ผู้ปกครอง ───
 * ต้องมีแถวใน `student_guardian` ที่ `verified_at` ไม่เป็น null มิฉะนั้น
 * `login_role_for()` ไม่คืน guardian แล้วล็อกอินถูกปฏิเสธด้วยข้อความ
 * "บัญชีนี้ยังไม่ได้รับมอบหมายบทบาท" ซึ่งอ่านแล้วนึกไม่ถึงว่าสาเหตุอยู่ตรงนี้
 */
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender)
select '20000000-0000-0000-0000-000000000009', d.institution_id, 'นาง', 'มาลี', 'ศรีสุข', 'female'
  from _demo d
on conflict (id) do update
  set prefix_th = excluded.prefix_th,
      first_name_th = excluded.first_name_th,
      last_name_th = excluded.last_name_th;

insert into student_guardian
  (student_id, person_id, relation, is_primary, can_approve_leave, verified_at)
select 'f1000000-0000-0000-0000-000000000001'::uuid,
       '20000000-0000-0000-0000-000000000009'::uuid, 'mother', true, true, now()
 where exists (select 1 from student s
                where s.id = 'f1000000-0000-0000-0000-000000000001'::uuid)
on conflict (student_id, person_id) do update
  set verified_at = now(), is_primary = true, can_approve_leave = true;

/*
 * ─── บัญชีผู้ใช้ ───
 * `must_change = false` เพราะเป็นบัญชีสาธิต — ถ้าเป็น true หน้าจอจะบังคับ
 * เปลี่ยนรหัสก่อนเข้าทุกครั้ง แล้วรหัสในไฟล์นี้จะใช้ไม่ได้ตั้งแต่ครั้งที่สอง
 *
 * และล้าง `failed_attempts` / `locked_until` / `disabled_at` ด้วย เพราะ
 * บัญชีที่ถูกล็อกจากการทดสอบเดารหัสจะเข้าไม่ได้ทั้งที่รหัสถูก ซึ่งเป็น
 * สภาพที่เกิดบ่อยมากบนฐานทดสอบ
 */
insert into user_credential
  (institution_id, person_id, username, password_hash, must_change)
select d.institution_id, x.person_id, x.username, d.password_hash, false
  from _demo d,
       (select person_id, username from _staff
        union all
        select person_id, username from _existing
        union all
        select '20000000-0000-0000-0000-000000000009'::uuid, 'guardian.demo'
         where exists (select 1 from student_guardian sg
                        where sg.person_id = '20000000-0000-0000-0000-000000000009'::uuid)) as x
on conflict (institution_id, username) do update
  set person_id           = excluded.person_id,
      password_hash       = excluded.password_hash,
      must_change         = false,
      failed_attempts     = 0,
      locked_until        = null,
      disabled_at         = null,
      password_changed_at = now();

/*
 * ─── สรุปสิ่งที่ได้ พร้อมบอกว่าใครยัง "ล็อกอินไม่ผ่าน" ───
 *
 * ใช้ฟังก์ชันเดียวกับที่การล็อกอินจริงใช้ทั้งสองตัว — `login_role_for()`
 * และ `mfa_required_for()` เพราะแถวที่ครบทุกคอลัมน์ยังเข้าระบบไม่ได้
 * ถ้าบทบาทผูกไม่ครบ หรือนโยบายบังคับ MFA ที่ยังไม่ได้ผูก authenticator
 *
 * ─── ทำไมต้องบอกเป็นรายบัญชี ไม่ใช่เตือนรวม ───
 * ตอนทดสอบไฟล์นี้ ผมยิงล็อกอินจริงแล้วเห็น `admin.demo` ตอบ 201 พร้อม
 * `role: 'admin'` เลยสรุปว่าผ่าน — ที่จริงเป็น **challenge token** ของ
 * ขั้นยืนยันสองชั้น ซึ่งมี `role` อยู่ในคำตอบเหมือนกัน และ AuthGuard
 * ปฏิเสธกับทุกเส้นทาง (ยิง /jobs ได้ 401)
 *
 * "ดูเหมือนผ่าน" กับ "ผ่าน" จึงต่างกันตรงนี้พอดี — ตารางข้างล่างบอกตรง ๆ
 */
select uc.username,
       coalesce(login_role_for(uc.person_id, uc.institution_id), '(ไม่มีบทบาท)') as role,
       trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
            || ' ' || coalesce(p.last_name_th, '')) as name,
       case
         when login_role_for(uc.person_id, uc.institution_id) is null
           then 'เข้าระบบไม่ได้ — ยังไม่ได้ผูกบทบาท'
         when mfa_required_for(uc.institution_id,
                               login_role_for(uc.person_id, uc.institution_id))
              and not exists (select 1 from mfa_credential mc
                               where mc.person_id = uc.person_id
                                 and mc.confirmed_at is not null)
           then 'ยังเข้าไม่ได้ — ต้องผูก authenticator ก่อน'
         else 'พร้อมใช้'
       end as status
  from user_credential uc
  join person p on p.id = uc.person_id
 where uc.username like '%.demo'
 order by uc.username;

/*
 * ─── บทบาทที่ถูกบังคับยืนยันสองชั้น ───
 * SQL ผูก authenticator ให้ไม่ได้ เพราะความลับ TOTP เข้ารหัสด้วย
 * `MFA_SECRET_KEY` ซึ่งอยู่ใน env ของโปรเซส API ไม่ใช่ในฐานข้อมูล
 * การเขียนไบต์ลงตารางเองจะได้ค่าที่ API ถอดไม่ออก แล้วบัญชีนั้นเข้าระบบ
 * ไม่ได้ตลอดไป — เตือนไว้ตรงนี้ ดีกว่าให้ไปเจอตอนกดล็อกอินแล้วงง
 */
do $$
declare v_blocked text[];
begin
  select array_agg(uc.username order by uc.username) into v_blocked
    from user_credential uc
   where uc.username like '%.demo'
     and login_role_for(uc.person_id, uc.institution_id) is not null
     and mfa_required_for(uc.institution_id,
                          login_role_for(uc.person_id, uc.institution_id))
     and not exists (select 1 from mfa_credential mc
                      where mc.person_id = uc.person_id
                        and mc.confirmed_at is not null);

  if v_blocked is not null then
    raise notice '';
    raise notice '% ยังเข้าระบบไม่ได้ — นโยบายบังคับยืนยันสองชั้นแต่ยังไม่ได้ผูก authenticator', v_blocked;
    raise notice 'การล็อกอินจะตอบ 201 พร้อม role อยู่ในคำตอบ แต่เป็น challenge token ที่ใช้กับเส้นทางอื่นไม่ได้';
    raise notice 'ผูกให้ด้วย  node api/tools/seed-demo-users.cjs  (ต้องมี API รันอยู่)';
    raise notice 'หรือปิดนโยบายชั่วคราวด้วย  psql -f api/tools/demo-mfa-off.sql';
  end if;
end $$;

commit;

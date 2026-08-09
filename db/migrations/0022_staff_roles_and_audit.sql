-- ═══════════════════════════════════════════════════════════════════
-- 0022_staff_roles_and_audit.sql
--
-- สิทธิของบุคลากร และบันทึกการเข้าถึงหรือเปลี่ยนแปลงข้อมูล
--
-- ─── ช่องโหว่ที่ปิดในไฟล์นี้ ───
-- ระบบมีบทบาทเก้าตัวที่ RLS ทั้งหมดพึ่งพา แต่ roleOf() ในชั้น API
-- คืนได้แค่ teacher กับ student เท่านั้น — ใครที่เป็นบุคลากรจะได้ teacher
-- ทุกคนไม่ว่าจะทำงานอะไร
--
-- ผลคือในระบบจริงที่ปิด DEV_AUTH **ไม่มีใครเป็น registrar, finance,
-- academic, director หรือ admin ได้เลย** งานทะเบียนออกใบแจ้งหนี้ไม่ได้
-- ฝ่ายวิชาการอนุมัติเกรดไม่ได้ ผู้อำนวยการดูรายงานไม่ได้
-- นโยบาย RLS ที่เขียนไว้อย่างละเอียดสำหรับบทบาทเหล่านั้นไม่เคยถูกใช้จริง
--
-- ─── ทำไมบทบาทต้องมีช่วงเวลา ───
-- หัวหน้าแผนกและรักษาการมีวาระ การเก็บเป็นคอลัมน์เดียวบน staff
-- ทำให้ตอบไม่ได้ว่า "ตอนอนุมัติเกรดใบนั้นเมื่อปีที่แล้ว คนนี้มีสิทธิ์ไหม"
-- ซึ่งเป็นคำถามแรกที่ผู้ตรวจสอบถาม
--
-- ─── ทำไมต้องมีบันทึกการเข้าถึง ไม่ใช่แค่การเปลี่ยนแปลง ───
-- grade_ledger บันทึกการ "เขียน" ผลการเรียนไว้แล้ว แต่ PDPA มาตรา 37
-- กำหนดให้ผู้ควบคุมข้อมูลต้องมีมาตรการตรวจสอบย้อนหลังได้ว่าใคร **เข้าถึง**
-- ข้อมูลส่วนบุคคลบ้าง การรั่วไหลส่วนใหญ่คือการอ่านแล้วคัดลอกออกไป
-- ซึ่งไม่ทิ้งร่องรอยใด ๆ ในระบบที่บันทึกเฉพาะการเขียน
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บทบาทของบุคลากร
-- ───────────────────────────────────────────────────────────────────
create type staff_role_kind as enum (
  'registrar',        -- งานทะเบียน
  'academic',         -- ฝ่ายวิชาการ
  'finance',          -- การเงิน
  'student_affairs',  -- งานปกครองและแนะแนว
  'director',         -- ผู้อำนวยการ
  'admin'             -- ผู้ดูแลระบบ
);

comment on type staff_role_kind is
  'บทบาทที่มอบหมายให้บุคลากรได้ — ไม่มี teacher เพราะการเป็นครูผู้สอนมาจาก staff.is_teacher และการถูกกำหนดเป็นครูประจำกลุ่มเรียน ไม่ใช่การมอบหมายสิทธิ';

create table staff_role (
  id             uuid            primary key default gen_random_uuid(),
  staff_id       uuid            not null references staff on delete cascade,
  role           staff_role_kind not null,
  effective_from date            not null default current_date,
  effective_to   date,
  granted_by     uuid            references staff,
  reason         text,

  -- ─── ทำไมมีทั้ง effective_to และ revoked_at ───
  -- effective_to คือวันสุดท้ายของวาระที่วางแผนไว้ล่วงหน้า เช่นรักษาการ
  -- ถึงสิ้นเดือน ส่วน revoked_at คือการตัดสิทธิ์ทันทีเมื่อมีเหตุ เช่นถูกให้
  -- ออกจากงานหรือพบการใช้สิทธิ์ในทางมิชอบ
  --
  -- ถ้ามีแต่ effective_to จะตัดสิทธิ์คนที่เพิ่งได้รับมอบหมายวันนี้ไม่ได้เลย
  -- เพราะ effective_to ต้องไม่น้อยกว่า effective_from — ต้องรอถึงพรุ่งนี้
  -- ซึ่งใช้ไม่ได้กับสถานการณ์ที่ต้องตัดสิทธิ์เดี๋ยวนั้น
  revoked_at     timestamptz,
  revoked_by     uuid            references staff,
  revoke_reason  text,

  created_at     timestamptz     not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (revoked_at is null or revoke_reason is not null),

  -- คนเดียวถือบทบาทเดิมซ้อนช่วงเวลากันไม่ได้
  -- ถ้าซ้อนได้ การตอบว่า "วันนั้นมีสิทธิ์ไหม" จะได้หลายคำตอบพร้อมกัน
  -- btree_gist รองรับ enum ได้โดยตรง ไม่ต้อง cast เป็น text
  -- (การ cast enum เป็น text เป็น STABLE ไม่ใช่ IMMUTABLE จึงใช้ในดัชนีไม่ได้)
  exclude using gist (
    staff_id with =,
    role with =,
    daterange(effective_from, coalesce(effective_to, date '9999-12-31'), '[]') with &&
  ) where (revoked_at is null)
);
create index on staff_role (staff_id) where effective_to is null;
create index on staff_role (role, effective_from desc);

comment on table staff_role is
  'บทบาทที่บุคลากรถืออยู่ พร้อมช่วงเวลา — ตอบได้ว่า ณ วันใดวันหนึ่งใครมีสิทธิ์อะไร';

-- ───────────────────────────────────────────────────────────────────
-- บทบาทที่ใช้ได้จริง ณ วันนี้
--
-- คืนบทบาทเดียวที่ "แรงที่สุด" เพราะ token มีช่องบทบาทช่องเดียว
-- และ RLS อ่านค่าเดียว การให้เลือกเองตอนล็อกอินจะทำให้ผู้ใช้สับสน
-- และเปิดช่องให้เลือกบทบาทที่ตัวเองไม่ควรใช้ในงานนั้น
--
-- ลำดับความแรงตามขอบเขตที่มองเห็นข้อมูล ไม่ใช่ตามตำแหน่งในองค์กร
-- ───────────────────────────────────────────────────────────────────
create or replace function effective_staff_role(p_person_id uuid, p_on date default current_date)
returns text
language sql stable as $$
  select sr.role::text
    from staff_role sr
    join staff st on st.id = sr.staff_id
   where st.person_id = p_person_id
     and st.active
     and sr.revoked_at is null
     and sr.effective_from <= p_on
     and (sr.effective_to is null or sr.effective_to >= p_on)
   order by case sr.role
              when 'admin'           then 1
              when 'director'        then 2
              when 'registrar'       then 3
              when 'academic'        then 4
              when 'finance'         then 5
              when 'student_affairs' then 6
            end
   limit 1
$$;

comment on function effective_staff_role(uuid, date) is
  'บทบาทที่แรงที่สุดที่บุคลากรคนนี้ถืออยู่ ณ วันที่ระบุ — ชั้น API ใช้ตอนล็อกอินแทนการเดาว่าทุกคนเป็น teacher';

-- ───────────────────────────────────────────────────────────────────
-- บทบาทที่ผู้ใช้ได้ตอนล็อกอิน
--
-- ─── ทำไมต้องเป็น security definer ───
-- ตอนล็อกอินยังไม่รู้ว่าผู้ใช้เป็นใคร บริบทจึงเป็นบทบาท 'auth' ที่
-- ไม่ใช่บทบาทระดับสถานศึกษา นโยบาย subject_scope ของ student จึงบล็อก
-- การอ่าน ทำให้หาไม่เจอว่าคนนี้เป็นนักศึกษา
--
-- โค้ดเดิมในชั้น API ไม่เจอปัญหานี้เพราะมันตกไปเป็น 'student' เสมอ
-- เมื่ออ่านไม่เห็นอะไร ซึ่งบังเอิญให้ผลถูกกับนักศึกษา แต่ซ่อนความจริงว่า
-- การอ่านถูกบล็อกอยู่ และทำให้บุคลากรทุกคนได้ teacher ไปด้วย
--
-- ปลอดภัยเพราะรับ person_id ที่ผู้เรียกรู้อยู่แล้ว (ผ่านการตรวจรหัสผ่านมาแล้ว)
-- และคืนออกไปแค่ชื่อบทบาท ไม่ใช่ข้อมูลส่วนบุคคลใด ๆ
-- ───────────────────────────────────────────────────────────────────
create or replace function login_role_for(p_person_id uuid, p_institution_id uuid)
returns text
language sql stable security definer
set search_path = public as $$
  select coalesce(
    -- บุคลากรที่ได้รับมอบหมายบทบาท
    (select effective_staff_role(p_person_id)
       from staff st
      where st.person_id = p_person_id
        and st.institution_id = p_institution_id
        and st.active
      limit 1),
    -- บุคลากรที่เป็นครูผู้สอน
    (select 'teacher' from staff st
      where st.person_id = p_person_id
        and st.institution_id = p_institution_id
        and st.active and st.is_teacher limit 1),
    -- นักศึกษา
    (select 'student' from student s
      where s.person_id = p_person_id
        and s.institution_id = p_institution_id limit 1),
    -- ผู้ปกครองที่ยืนยันตัวตนแล้ว
    (select 'guardian' from student_guardian sg
       join student s on s.id = sg.student_id
      where sg.person_id = p_person_id
        and sg.verified_at is not null
        and s.institution_id = p_institution_id limit 1)
  )
$$;

comment on function login_role_for(uuid, uuid) is
  'บทบาทที่ผู้ใช้ได้ตอนล็อกอิน — คืน null ถ้าไม่ผูกกับบทบาทใดเลย ซึ่งแปลว่าเข้าระบบไม่ได้';

revoke all on function login_role_for(uuid, uuid) from public;

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการเข้าถึงและเปลี่ยนแปลงข้อมูล
--
-- ─── ทำไมแยกจาก grade_ledger ───
-- grade_ledger เป็นโซ่แฮชที่ออกแบบมาเพื่อ "พิสูจน์ว่าไม่ถูกแก้ย้อนหลัง"
-- ซึ่งจำเป็นกับผลการเรียนที่ใช้ยันเงินอุดหนุนและออกเอกสารราชการ
-- ส่วนตารางนี้เป็นบันทึกปริมาณมากที่เขียนทุกคำขอ การใส่โซ่แฮชกับมัน
-- จะทำให้ทุกคำขอต้องล็อกแถวสุดท้ายของตารางเรียงกัน กลายเป็นคอขวด
-- ───────────────────────────────────────────────────────────────────
create type audit_action as enum ('read', 'create', 'update', 'delete', 'export', 'login');

create table access_log (
  id             bigserial    primary key,
  institution_id uuid         not null references institution,
  actor_id       uuid,                       -- person_id ของผู้กระทำ
  actor_role     text,
  action         audit_action not null,
  entity         text         not null,      -- 'student' | 'invoice' | ...
  entity_id      uuid,
  subject_id     uuid,                       -- เจ้าของข้อมูล ถ้าข้อมูลนั้นเป็นของใครคนหนึ่ง
  route          text,
  detail         jsonb        not null default '{}'::jsonb,
  ip_hash        bytea,                      -- ไอพีเป็นข้อมูลส่วนบุคคล เก็บเป็นค่าแฮชเหมือน login_attempt
  occurred_at    timestamptz  not null default now()
);
create index on access_log (institution_id, occurred_at desc);
create index on access_log (subject_id, occurred_at desc) where subject_id is not null;
create index on access_log (actor_id, occurred_at desc);
create index on access_log (entity, entity_id);

comment on table access_log is
  'ใครเข้าถึงหรือเปลี่ยนแปลงข้อมูลของใครเมื่อไร — ตาม PDPA มาตรา 37 ที่ต้องตรวจสอบย้อนหลังได้ เก็บไม่น้อยกว่า 90 วันตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26';
comment on column access_log.subject_id is
  'person_id ของเจ้าของข้อมูล ใช้ตอบคำถาม "ใครดูข้อมูลของลูกฉันบ้าง" ซึ่งเจ้าของข้อมูลมีสิทธิ์ถามตาม PDPA มาตรา 30';

-- ล้างบันทึกที่เกินระยะเก็บ — ตั้งเป็นงานประจำวันเหมือน purge_login_attempts
create or replace function purge_access_log(p_keep_days integer default 90)
returns integer language plpgsql as $$
declare v_n integer;
begin
  if p_keep_days < 90 then
    raise exception 'ระยะเก็บบันทึกการเข้าถึงต่ำกว่า 90 วันไม่ได้ตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26';
  end if;
  delete from access_log where occurred_at < now() - make_interval(days => p_keep_days);
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table staff_role enable row level security;
alter table staff_role force  row level security;
create policy tenant_isolation on staff_role
  using (exists (select 1 from staff st
                 where st.id = staff_role.staff_id
                   and st.institution_id = current_institution_id()))
  with check (exists (select 1 from staff st
                      where st.id = staff_role.staff_id
                        and st.institution_id = current_institution_id()));

/*
 * การมอบหมายสิทธิเป็นงานของผู้ดูแลระบบและผู้อำนวยการเท่านั้น
 *
 * ถ้าปล่อยให้บทบาทอื่นเขียนได้ ใครก็ตามที่มีสิทธิ์เขียนตารางนี้จะยกระดับ
 * ตัวเองเป็น admin ได้ในคำสั่งเดียว แล้วสิทธิทั้งระบบก็ไม่มีความหมาย
 * ส่วนการอ่านเปิดให้ทุกคนในวิทยาลัย เพราะต้องรู้ว่าใครรับผิดชอบอะไร
 */
create policy staff_role_write on staff_role
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('admin', 'director'));

alter table access_log enable row level security;
alter table access_log force  row level security;

-- อ่านได้เฉพาะผู้ดูแล ผู้อำนวยการ และเจ้าของข้อมูลเอง
create policy access_log_read on access_log
  for select using (
    institution_id = current_institution_id()
    and (
      current_app_role() in ('admin', 'director')
      or subject_id = current_actor_id()
    )
  );

-- เขียนได้ทุกบทบาท เพราะทุกคำขอต้องบันทึกได้
create policy access_log_append on access_log
  for insert with check (institution_id = current_institution_id());

-- ไม่มีนโยบาย update โดยเจตนา — บันทึกการตรวจสอบที่แก้ได้ไม่มีค่าในการตรวจสอบ
--
-- ส่วน delete อนุญาตเฉพาะแถวที่เกินระยะเก็บขั้นต่ำแล้ว
-- ตั้งใจให้เป็นนโยบายไม่ใช่ปล่อยว่าง เพราะ force row level security
-- มีผลกับเจ้าของตารางด้วย ถ้าไม่มีนโยบาย delete เลย purge_access_log()
-- จะลบไม่ได้สักแถวและบันทึกจะโตไปเรื่อย ๆ จนเต็มดิสก์
--
-- เงื่อนไขในนโยบายทำให้ **ไม่มีใครลบบันทึกของเมื่อวานได้** แม้แต่ admin
-- ซึ่งเป็นคุณสมบัติที่ทำให้บันทึกนี้ใช้เป็นหลักฐานได้จริง
create policy access_log_purge_aged on access_log
  for delete using (occurred_at < now() - interval '90 days');

-- ต้องให้สิทธิ์หลังสร้างตารางใหม่ เพราะ roles.sql รันไปก่อนหน้านี้แล้ว
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete on staff_role, access_log to app_runtime;
    grant usage, select on sequence access_log_id_seq to app_runtime;
    grant execute on function login_role_for(uuid, uuid)          to app_runtime;
    grant execute on function effective_staff_role(uuid, date)    to app_runtime;
    grant execute on function purge_access_log(integer)           to app_runtime;
  end if;
end $$;

commit;

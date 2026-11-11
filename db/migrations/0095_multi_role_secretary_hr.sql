-- ═══════════════════════════════════════════════════════════════════
-- 0095_multi_role_secretary_hr.sql
--
-- ศูนย์บุคลากรแบบหลายฝ่ายซ้อนกัน — เพิ่มบทบาท "เลขา" กับ "บุคคล" และปิด
-- ช่องว่างที่ session ยุบเหลือบทบาทเดียว
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- login_role_for() (0022) ใช้ coalesce(staff_role → is_teacher → student →
-- guardian) คนที่มีทั้งบทบาทระดับวิทยาลัย (เช่น academic) และเป็นครูผู้สอน
-- ด้วย (staff.is_teacher) จะได้ role เดียวคือ academic — ความสามารถฝั่งครู
-- (ส่งเกรดกลุ่มตัวเอง ฯลฯ) หายไปทั้งที่ RLS หลายจุดยอมให้ครูทำอยู่แล้ว
-- รูปเดียวกับข้อ 14 ใน CLAUDE.md (grade_submission) แต่คราวนี้เกิดจาก
-- การยุบบทบาทตอนล็อกอิน ไม่ใช่นโยบาย restrictive ที่เขียนไม่ครบ
--
-- ─── ทำไมไม่แก้ login_role_for() ตรง ๆ ───
-- ที่อื่นในระบบ (JWT field `role`, access_log, audit) ยังอ้างค่าเดียวอยู่
-- และค่านั้นต้องเป็น "บทบาทที่แรงที่สุด" เพื่อความหมายเดิม (เช่นใครลงชื่อ
-- อนุมัติ) จึงเพิ่มฟังก์ชันคู่ขนาน login_roles_for() ที่คืน**ชุด**บทบาท
-- ทั้งหมดแทน ให้ชั้น API ส่งเป็น `roles` เพิ่มเติมจาก `role` เดิม
--
-- ─── ทำไม current_app_roles() ต้อง fallback เป็น current_app_role() ───
-- งานเบื้องหลัง (jobs, platform, provisioning) ยังตั้งแค่ app.role เดี่ยว
-- ถ้า current_app_roles() คืนอาร์เรย์ว่างเมื่อไม่มี app.roles นโยบายที่พึ่ง
-- current_app_roles() จะปิดกั้นทุกอย่างสำหรับบริบทเหล่านั้นทันที
--
-- ─── ทำไมเลขา/บุคคลไม่เข้ากลุ่ม is_institution_wide_role() ───
-- กลุ่มนั้นเห็นข้อมูลทั้งวิทยาลัยรวมถึงเกรดและการเงิน ถ้าเลขา/บุคคลเข้ากลุ่ม
-- จะเห็นข้อมูลที่ไม่เกี่ยวกับงานตัวเองทันที ขัดกับ "ห้ามมีช่องว่างข้ามสิทธิ์"
-- จึงเสียบเข้าเฉพาะนโยบายของตารางที่เกี่ยวกับงานของฝ่ายตัวเองเท่านั้น
-- (งานบุคคล → staff_leave/staff_record/staff_child ของ 0035, เลขา →
-- issued_document สามใบที่ issue_student_letter() ออกได้ (0055) กับ
-- announcement ของ 0091)
-- ═══════════════════════════════════════════════════════════════════

-- enum ใหม่ต้อง commit ก่อนถูกใช้งานในทรานแซกชันอื่น จึงแยกเป็นทรานแซกชัน
-- ของตัวเอง ไม่รวมกับส่วนที่เหลือของไฟล์นี้
alter type staff_role_kind add value if not exists 'secretary';
alter type staff_role_kind add value if not exists 'hr';

comment on type staff_role_kind is
  'บทบาทที่มอบหมายให้บุคลากรได้ — ไม่มี teacher เพราะการเป็นครูผู้สอนมาจาก staff.is_teacher และการถูกกำหนดเป็นครูประจำกลุ่มเรียน ไม่ใช่การมอบหมายสิทธิ';

begin;

-- ───────────────────────────────────────────────────────────────────
-- effective_staff_role() ต้องรู้จักค่า enum ใหม่ มิฉะนั้น case ที่ไม่ครบ
-- จะทำให้ query ล้มตอน runtime ทันทีที่มีใครถือบทบาทนี้
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
              when 'hr'              then 7
              when 'secretary'       then 8
            end
   limit 1
$$;

-- ───────────────────────────────────────────────────────────────────
-- ชุดบทบาททั้งหมดที่มีผลจริง — คู่ขนานกับ login_role_for() ที่ยังคืน
-- ค่าเดียว (บทบาทที่แรงที่สุด) ไว้ให้จุดที่ยังอ้างค่าเดียวใช้ต่อได้
--
-- ต่างจาก login_role_for() ตรงที่ "ครูผู้สอน" ไม่ใช่ทางเลือกสำรองเมื่อไม่มี
-- staff_role อีกต่อไป — เป็นบทบาทที่**บวกเพิ่ม**เสมอถ้า is_teacher เป็นจริง
-- ไม่ว่าจะมี staff_role อื่นอยู่ด้วยหรือไม่ นี่คือจุดที่ปิดช่องว่างของ
-- "ฝ่ายวิชาการที่สอนด้วย" ที่อธิบายไว้ด้านบน
-- ───────────────────────────────────────────────────────────────────
create or replace function login_roles_for(p_person_id uuid, p_institution_id uuid)
returns text[]
language sql stable security definer
set search_path = public as $$
  with staff_ctx as (
    select st.id, st.is_teacher
      from staff st
     where st.person_id = p_person_id
       and st.institution_id = p_institution_id
       and st.active
     limit 1
  ),
  granted as (
    select sr.role::text as r
      from staff_role sr
      join staff_ctx sc on sc.id = sr.staff_id
     where sr.revoked_at is null
       and sr.effective_from <= current_date
       and (sr.effective_to is null or sr.effective_to >= current_date)
    union
    select 'teacher'
      from staff_ctx sc
     where sc.is_teacher
  ),
  agg as (
    select array_agg(distinct r) as roles from granted
  )
  select case
           when (select roles from agg) is not null then (select roles from agg)
           else array[login_role_for(p_person_id, p_institution_id)]
         end
$$;

comment on function login_roles_for(uuid, uuid) is
  'ชุดบทบาททั้งหมดที่มีผลจริง ไม่ยุบเหลือตัวเดียวแบบ login_role_for() — ใช้ตอนออก token เพื่อไม่ให้ความสามารถของบทบาทรองหายไปเมื่อมีบทบาทหลักซ้อนอยู่';

revoke all on function login_roles_for(uuid, uuid) from public;

-- ───────────────────────────────────────────────────────────────────
-- current_app_roles() — คู่กับ current_app_role() เดิมใน 0008
-- fallback เป็น [current_app_role()] เมื่อไม่มีใครตั้ง app.roles
-- (งานเบื้องหลัง/บริบทเก่าที่ยังตั้งแค่ app.role เดี่ยว) — ไม่ทำให้
-- นโยบายที่พึ่งฟังก์ชันนี้ปิดกั้นบริบทเหล่านั้นไปทั้งหมด
-- ───────────────────────────────────────────────────────────────────
create or replace function current_app_roles() returns text[]
language sql stable as $$
  select case
           when nullif(current_setting('app.roles', true), '') is null
             then array[current_app_role()]
           else string_to_array(current_setting('app.roles', true), ',')
         end
$$;

-- ───────────────────────────────────────────────────────────────────
-- งานบุคคล (hr) เห็นระเบียนบุคลากรทั้งวิทยาลัยได้โดยไม่ต้องเข้ากลุ่ม
-- institution-wide เดิม — จำกัดเฉพาะสามตารางของ 0035 ที่เป็นงานของฝ่ายนี้
-- โดยตรง (ประวัติ · การลา · บุตรบุคลากร) ไม่แตะตารางอื่น
-- ───────────────────────────────────────────────────────────────────
alter policy staff_leave_scope on staff_leave
  using (
    is_institution_wide_role()
    or 'hr' = any (current_app_roles())
    or exists (select 1 from staff s
                where s.id = staff_leave.staff_id
                  and s.person_id = current_actor_id())
  );

alter policy staff_record_scope on staff_record
  using (
    is_institution_wide_role()
    or 'hr' = any (current_app_roles())
    or exists (select 1 from staff s
                where s.id = staff_record.staff_id
                  and s.person_id = current_actor_id())
  );

alter policy staff_child_scope on staff_child
  using (
    is_institution_wide_role()
    or 'hr' = any (current_app_roles())
    or exists (select 1 from staff s
                where s.id = staff_child.staff_id
                  and s.person_id = current_actor_id())
  );

-- ───────────────────────────────────────────────────────────────────
-- เลขา (secretary) ออกหนังสือถึงผู้ปกครองได้ (issue_student_letter() ไม่ใช่
-- security definer จึงยึด RLS ของ issued_document ตรง ๆ — 0045 บังคับไว้
-- ว่าเขียนได้เฉพาะ is_institution_wide_role() เท่านั้น เพิ่ม secretary
-- เป็นเงื่อนไข OR เสริมเฉพาะสามนโยบายของตารางนี้ ไม่แตะตารางอื่นในลูป 0045)
-- ───────────────────────────────────────────────────────────────────
alter policy issued_document_staff_insert on issued_document
  with check (is_institution_wide_role() or 'secretary' = any (current_app_roles()));

alter policy issued_document_staff_update on issued_document
  using (is_institution_wide_role() or 'secretary' = any (current_app_roles()))
  with check (is_institution_wide_role() or 'secretary' = any (current_app_roles()));

alter policy issued_document_staff_delete on issued_document
  using (is_institution_wide_role() or 'secretary' = any (current_app_roles()));

-- ───────────────────────────────────────────────────────────────────
-- เลขาประกาศข่าวได้ (0091) — เพิ่มเข้ารายชื่อเดิมที่ policy เช็คตรง ๆ
-- ───────────────────────────────────────────────────────────────────
alter policy announcement_insert on announcement
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin','secretary']));

alter policy announcement_update on announcement
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin','secretary']))
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin','secretary']));

alter policy announcement_delete on announcement
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin','secretary']));

commit;

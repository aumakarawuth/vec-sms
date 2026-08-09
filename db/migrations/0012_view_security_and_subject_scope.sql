-- ═══════════════════════════════════════════════════════════════════
-- 0012_view_security_and_subject_scope.sql
--
-- แก้ช่องโหว่ความปลอดภัยสองจุดที่พบตอนทดสอบ API
--
-- ─── จุดที่ 1: view ข้าม Row-Level Security ทั้งหมด ───
-- ใน PostgreSQL view จะรันด้วยสิทธิ์ของ "เจ้าของ view" ไม่ใช่ผู้เรียก
-- เมื่อเจ้าของเป็นผู้ใช้ที่สร้างฐานข้อมูล (ซึ่งมักเป็น superuser) RLS ของ
-- ตารางที่อยู่ข้างใต้จะถูกข้ามทั้งหมด
--
-- ผลคือ ตารางกันข้ามวิทยาลัยได้ถูกต้อง แต่ทุก view รั่ว
-- ยืนยันแล้วด้วยการทดลอง: ตั้งบริบทเป็นวิทยาลัยที่ 2 ซึ่งมีใบแจ้งหนี้ 0 ใบ
--   select count(*) from invoice            → 0   ถูกต้อง
--   select count(*) from v_student_balance  → 1   รั่ว
--
-- แก้ด้วย security_invoker = true ซึ่งทำให้ view ใช้สิทธิ์ของผู้เรียกแทน
-- และ RLS ของตารางข้างใต้กลับมาทำงาน
--
-- security_invoker ต้องใช้ PostgreSQL 15 ขึ้นไป ความต้องการขั้นต่ำของระบบ
-- จึงเปลี่ยนจาก 14 เป็น 15 ตั้งแต่ migration นี้เป็นต้นไป
--
-- ─── จุดที่ 2: นักศึกษาดูข้อมูลของตัวเองไม่ได้ ───
-- นโยบาย teacher_scope บน class_section และ attendance_record เป็นแบบ
-- restrictive ที่อนุญาตเฉพาะบทบาทระดับสถานศึกษากับครูผู้สอน
-- นักศึกษาจึงมองไม่เห็นกลุ่มเรียนของตัวเอง ทำให้หน้าจอเวลาเรียนในแอปว่างเปล่า
-- ═══════════════════════════════════════════════════════════════════
begin;

do $$
declare
  v_major int;
begin
  select current_setting('server_version_num')::int / 10000 into v_major;
  if v_major < 15 then
    raise exception
      'migration นี้ต้องใช้ PostgreSQL 15 ขึ้นไป เพราะใช้ security_invoker บน view (พบเวอร์ชัน %)',
      v_major;
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ให้ทุก view ใช้สิทธิ์ของผู้เรียก ไม่ใช่ของเจ้าของ
-- ───────────────────────────────────────────────────────────────────
do $$
declare v record;
begin
  for v in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'v' and n.nspname = 'public'
  loop
    execute format('alter view public.%I set (security_invoker = true)', v.relname);
  end loop;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ฟังก์ชันช่วยหาว่าผู้ใช้ปัจจุบันเกี่ยวข้องกับนักศึกษาคนไหนบ้าง
--
-- ต้องเป็น security definer เพื่อตัดวงจรของนโยบาย RLS
-- ถ้าเขียนเงื่อนไข "นักศึกษาเห็นกลุ่มเรียนของตัวเอง" ตรง ๆ นโยบายของ
-- class_section จะไปอ่าน enrollment ซึ่งนโยบายของมันก็อ่าน class_section กลับมา
-- PostgreSQL จะฟ้อง infinite recursion detected in policy
--
-- ฟังก์ชันเหล่านี้เปิดเผยเฉพาะความสัมพันธ์ของผู้เรียกเองเท่านั้น
-- ไม่ได้เปิดข้อมูลของคนอื่น จึงปลอดภัยที่จะให้รันด้วยสิทธิ์ของเจ้าของ
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if not (select rolsuper or rolbypassrls from pg_roles where rolname = current_user) then
    raise exception
      'migration นี้ต้องรันด้วยผู้ใช้ที่ข้าม RLS ได้ (superuser หรือ BYPASSRLS) '
      'เพราะสร้างฟังก์ชัน security definer ที่ต้องอ่านข้ามนโยบาย — ผู้ใช้ปัจจุบันคือ %',
      current_user;
  end if;
end $$;

create or replace function actor_student_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  -- ตัวเองถ้าเป็นนักศึกษา
  select s.id from student s where s.person_id = current_actor_id()
  union
  -- บุตรหลานถ้าเป็นผู้ปกครองที่ยืนยันตัวตนแล้ว
  select sg.student_id from student_guardian sg
   where sg.person_id = current_actor_id()
     and sg.verified_at is not null
$$;

create or replace function actor_enrollment_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select e.id from enrollment e where e.student_id in (select actor_student_ids())
$$;

create or replace function actor_section_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select distinct e.class_section_id from enrollment e
   where e.student_id in (select actor_student_ids())
$$;

-- ───────────────────────────────────────────────────────────────────
-- ขอบเขตของกลุ่มเรียน — เพิ่มนักศึกษาและผู้ปกครองที่ยืนยันตัวตนแล้ว
-- ───────────────────────────────────────────────────────────────────
drop policy if exists teacher_scope on class_section;
drop policy if exists section_scope on class_section;

create policy section_scope on class_section
  as restrictive
  using (
    is_institution_wide_role()
    -- ครูผู้สอนประจำกลุ่ม
    or exists (select 1 from staff st
               where st.id = class_section.teacher_id
                 and st.person_id = current_actor_id())
    -- ครูสอนแทนในคาบใดคาบหนึ่งของกลุ่มนี้
    or exists (select 1 from class_meeting cm
               join staff st2 on st2.id = cm.taught_by
               where cm.class_section_id = class_section.id
                 and st2.person_id = current_actor_id())
    -- นักศึกษาที่ลงทะเบียน และผู้ปกครองที่ยืนยันตัวตนแล้ว
    or class_section.id in (select actor_section_ids())
  );

-- ───────────────────────────────────────────────────────────────────
-- ขอบเขตของการเช็คชื่อ — เดิมนักศึกษาดูของตัวเองไม่ได้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists teacher_scope on attendance_record;
drop policy if exists attendance_scope on attendance_record;

create policy attendance_scope on attendance_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
    or attendance_record.enrollment_id in (select actor_enrollment_ids())
  );

-- ───────────────────────────────────────────────────────────────────
-- ขอบเขตของการลงทะเบียน — เดิมนักศึกษาเห็นการลงทะเบียนของทุกคนในวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
drop policy if exists enrollment_scope on enrollment;

create policy enrollment_scope on enrollment
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_section cs
               join staff st on st.id = cs.teacher_id
               where cs.id = enrollment.class_section_id
                 and st.person_id = current_actor_id())
    or enrollment.student_id in (select actor_student_ids())
  );

-- ───────────────────────────────────────────────────────────────────
-- คะแนนเก็บ — นักศึกษาเห็นเฉพาะชิ้นงานที่ครูเปิดเผยแล้วเท่านั้น
-- ตรงกับการตั้งค่า gradebook_item.publish_to_student ที่ออกแบบไว้
-- ───────────────────────────────────────────────────────────────────
drop policy if exists teacher_scope on gradebook_score;
drop policy if exists gradebook_scope on gradebook_score;

create policy gradebook_scope on gradebook_score
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from gradebook_item gi
               join class_section cs on cs.id = gi.class_section_id
               join staff st on st.id = cs.teacher_id
               where gi.id = gradebook_score.gradebook_item_id
                 and st.person_id = current_actor_id())
    or (gradebook_score.enrollment_id in (select actor_enrollment_ids())
        and exists (select 1 from gradebook_item gi
                    where gi.id = gradebook_score.gradebook_item_id
                      and gi.publish_to_student))
  );

commit;

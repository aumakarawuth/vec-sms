-- ═══════════════════════════════════════════════════════════════════
-- 0008_rls.sql
-- Row-Level Security
--
-- สิทธิ์ต้องบังคับที่ฐานข้อมูล ไม่ใช่ที่ชั้นแอปพลิเคชันเพียงอย่างเดียว
-- ถ้าโค้ดชั้นแอปลืมใส่เงื่อนไข where สักที่เดียว ข้อมูลนักศึกษาทั้งวิทยาลัย
-- จะรั่ว การวางกำแพงไว้ที่ชั้นล่างสุดทำให้บั๊กแบบนั้นกลายเป็นแถวว่าง
-- แทนที่จะกลายเป็นเหตุละเมิดข้อมูลส่วนบุคคล
--
-- ─── กติกาที่ต้องเข้าใจก่อนแก้ไฟล์นี้ ───
-- PostgreSQL รวม policy สองแบบไม่เหมือนกัน
--   PERMISSIVE  (ค่าเริ่มต้น) → รวมกันด้วย OR   = "ทางใดทางหนึ่งอนุญาตก็พอ"
--   RESTRICTIVE               → รวมกันด้วย AND  = "ต้องผ่านทุกข้อ"
-- ถ้าเขียนนโยบายขอบเขตบทบาทเป็น permissive มันจะไป OR กับนโยบายแยกสถานศึกษา
-- แล้วเปิดข้อมูลข้ามวิทยาลัยทันที (บั๊กนี้ถูกจับได้ด้วย tests/0001_smoke.sql TEST 10)
--
-- โครงสร้างที่ใช้จึงเป็นสองชั้น
--   ชั้นที่ 1  permissive  — เข้าถึงได้เมื่ออยู่ในสถานศึกษาเดียวกัน
--   ชั้นที่ 2  restrictive — แล้วยังต้องผ่านขอบเขตของบทบาทอีกชั้น
--
-- ชั้นแอปต้องตั้งค่าทุก transaction:
--   SET LOCAL app.institution_id = '...';
--   SET LOCAL app.actor_id       = '...';   -- person_id ของผู้ใช้
--   SET LOCAL app.role           = 'teacher' | 'registrar' | 'finance' | ...
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function current_app_role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('app.role', true), ''), 'none')
$$;

-- บทบาทที่มีหน้าที่ดูข้อมูลได้ทั้งสถานศึกษา
create or replace function is_institution_wide_role() returns boolean
language sql stable as $$
  select current_app_role() in ('registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin')
$$;

-- ═══ ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา (permissive) ═══════════

-- 1ก. ตารางที่มี institution_id อยู่บนตัวเอง
do $$
declare t text;
begin
  foreach t in array array[
    'person', 'student', 'staff',
    'academic_year', 'program_type', 'program', 'curriculum',
    'course', 'class_section', 'grade_scheme', 'attendance_policy'
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

-- 1ข. ตารางที่สืบทอดสถานศึกษาผ่านคีย์นอก
alter table term enable row level security;
alter table term force  row level security;
create policy tenant_isolation on term
  using (exists (select 1 from academic_year ay
                 where ay.id = term.academic_year_id
                   and ay.institution_id = current_institution_id()));

alter table enrollment enable row level security;
alter table enrollment force  row level security;
create policy tenant_isolation on enrollment
  using (exists (select 1 from student s
                 where s.id = enrollment.student_id
                   and s.institution_id = current_institution_id()));

alter table enrollment_result enable row level security;
alter table enrollment_result force  row level security;
create policy tenant_isolation on enrollment_result
  using (exists (select 1 from enrollment e
                 join student s on s.id = e.student_id
                 where e.id = enrollment_result.enrollment_id
                   and s.institution_id = current_institution_id()));

alter table gradebook_score enable row level security;
alter table gradebook_score force  row level security;
create policy tenant_isolation on gradebook_score
  using (exists (select 1 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 where gi.id = gradebook_score.gradebook_item_id
                   and cs.institution_id = current_institution_id()));

alter table attendance_record enable row level security;
alter table attendance_record force  row level security;
create policy tenant_isolation on attendance_record
  using (exists (select 1 from class_meeting cm
                 join class_section cs on cs.id = cm.class_section_id
                 where cm.id = attendance_record.class_meeting_id
                   and cs.institution_id = current_institution_id()));

-- ═══ ชั้นที่ 2 — ขอบเขตของบทบาท (restrictive, AND ทับชั้นที่ 1) ═══

-- ครูเห็นเฉพาะกลุ่มเรียนที่ตนสอน บทบาทระดับสถานศึกษาเห็นทั้งหมด
create policy teacher_scope on class_section
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
               where st.id = class_section.teacher_id
                 and st.person_id = current_actor_id())
  );

create policy teacher_scope on gradebook_score
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from gradebook_item gi
               join class_section cs on cs.id = gi.class_section_id
               join staff st         on st.id = cs.teacher_id
               where gi.id = gradebook_score.gradebook_item_id
                 and st.person_id = current_actor_id())
  );

-- ครูสอนแทนต้องเช็คชื่อได้ด้วย จึงเทียบกับ coalesce(taught_by, teacher_id)
create policy teacher_scope on attendance_record
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
               from class_meeting cm
               join class_section cs on cs.id = cm.class_section_id
               join staff st         on st.id = coalesce(cm.taught_by, cs.teacher_id)
               where cm.id = attendance_record.class_meeting_id
                 and st.person_id = current_actor_id())
  );

-- นักศึกษาเห็นข้อมูลตนเอง ผู้ปกครองเห็นได้เมื่อยืนยันตัวตนแล้วเท่านั้น
create policy subject_scope on student
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from person p
               where p.id = student.person_id
                 and p.id = current_actor_id())
    or exists (select 1 from student_guardian sg
               where sg.student_id = student.id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null)
  );

create policy subject_scope on enrollment_result
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1
               from enrollment e
               join student s on s.id = e.student_id
               where e.id = enrollment_result.enrollment_id
                 and s.person_id = current_actor_id())
    or exists (select 1
               from enrollment e
               join student_guardian sg on sg.student_id = e.student_id
               where e.id = enrollment_result.enrollment_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_grades)
  );

-- ═══ บัญชีตรวจสอบ: อ่านได้ เพิ่มได้ แก้และลบไม่ได้ ═══════════════
alter table grade_ledger enable row level security;
alter table grade_ledger force  row level security;
create policy ledger_read on grade_ledger
  for select using (institution_id = current_institution_id());
create policy ledger_append on grade_ledger
  for insert with check (institution_id = current_institution_id());
-- ไม่มีนโยบาย update และ delete โดยเจตนา — RLS จึงปฏิเสธทั้งสองอย่างเสมอ
-- แม้แต่บทบาท admin ก็แก้บัญชีย้อนหลังไม่ได้ผ่านการเชื่อมต่อปกติ

commit;

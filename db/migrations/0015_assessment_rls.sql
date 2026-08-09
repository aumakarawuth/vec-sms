-- ═══════════════════════════════════════════════════════════════════
-- 0015_assessment_rls.sql
--
-- ปิดช่องโหว่ — ตารางฝั่งวัดผลหกตารางไม่มี Row-Level Security เลย
--
-- ─── อาการ ───
-- select relname, relrowsecurity from pg_class
--  where relname in ('gradebook_item', 'grade_submission', ...)
-- คืนค่า false ทั้งหมด แปลว่าใครก็ตามที่เชื่อมต่อด้วย vecsms_app
-- อ่านและเขียนตารางเหล่านี้ของ **ทุกวิทยาลัย** ได้
--
-- ─── ทำไมยังไม่มีใครเจอ ───
-- เพราะยังไม่มี endpoint ไหนแตะตารางกลุ่มนี้เลย ช่องโหว่จึงยังไม่ถูกใช้
-- แต่วินาทีที่โมดูลสมุดคะแนนขึ้น มันจะกลายเป็นการรั่วข้ามวิทยาลัยทันที
-- migration นี้จึงต้องมาก่อน endpoint ไม่ใช่ตามหลัง
--
-- ─── ตารางที่ได้รับผลกระทบและความรุนแรง ───
-- gradebook_item          คะแนนเก็บของทุกกลุ่มเรียนทุกวิทยาลัย
-- grade_submission        สถานะการอนุมัติเกรด แก้ให้ข้ามขั้นได้
-- grade_submission_event  ประวัติการอนุมัติ ปลอมได้
-- grade_change_request    คำร้องแก้เกรด — อันตรายที่สุด เพราะ dual control
--                         ที่ตั้งใจไว้จะถูกข้ามได้ถ้าเขียนตารางนี้ตรง ๆ
-- term_summary            GPA และ GPAX รายคน
-- grade_symbol/cutoff     ช่วงคะแนนตัดเกรดของวิทยาลัยอื่น
--
-- ─── โครงสร้างเดิมที่ยังใช้ต่อ ───
-- ชั้นที่ 1 permissive  — อยู่วิทยาลัยเดียวกันไหม
-- ชั้นที่ 2 restrictive — แล้วยังต้องผ่านขอบเขตของบทบาทอีกชั้น
-- PostgreSQL รวม permissive ด้วย OR และ restrictive ด้วย AND
-- ถ้าเขียนขอบเขตบทบาทเป็น permissive มันจะไป OR กับการแยกวิทยาลัย
-- แล้วเปิดข้อมูลข้ามวิทยาลัยทันที
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ═══ ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา (permissive) ═══════════

-- สมุดคะแนนและรอบส่งเกรด สืบทอดวิทยาลัยผ่านกลุ่มเรียน
do $$
declare t text;
begin
  foreach t in array array['gradebook_item', 'grade_submission'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from class_section cs
                     where cs.id = %I.class_section_id
                       and cs.institution_id = current_institution_id()))
      with check (exists (select 1 from class_section cs
                          where cs.id = %I.class_section_id
                            and cs.institution_id = current_institution_id()))
    $f$, t, t, t);
  end loop;
end $$;

-- ประวัติขั้นอนุมัติ สืบทอดผ่านรอบส่งเกรดอีกทอด
alter table grade_submission_event enable row level security;
alter table grade_submission_event force  row level security;
create policy tenant_isolation on grade_submission_event
  using (exists (select 1 from grade_submission gs
                 join class_section cs on cs.id = gs.class_section_id
                 where gs.id = grade_submission_event.submission_id
                   and cs.institution_id = current_institution_id()))
  with check (exists (select 1 from grade_submission gs
                      join class_section cs on cs.id = gs.class_section_id
                      where gs.id = grade_submission_event.submission_id
                        and cs.institution_id = current_institution_id()));

-- คำร้องแก้เกรด สืบทอดผ่านการลงทะเบียน
alter table grade_change_request enable row level security;
alter table grade_change_request force  row level security;
create policy tenant_isolation on grade_change_request
  using (exists (select 1 from enrollment e
                 join class_section cs on cs.id = e.class_section_id
                 where e.id = grade_change_request.enrollment_id
                   and cs.institution_id = current_institution_id()))
  with check (exists (select 1 from enrollment e
                      join class_section cs on cs.id = e.class_section_id
                      where e.id = grade_change_request.enrollment_id
                        and cs.institution_id = current_institution_id()));

-- สรุปผลรายภาคเรียน สืบทอดผ่านนักศึกษา
alter table term_summary enable row level security;
alter table term_summary force  row level security;
create policy tenant_isolation on term_summary
  using (exists (select 1 from student s
                 where s.id = term_summary.student_id
                   and s.institution_id = current_institution_id()))
  with check (exists (select 1 from student s
                      where s.id = term_summary.student_id
                        and s.institution_id = current_institution_id()));

-- สัญลักษณ์ผลการเรียนและช่วงคะแนน สืบทอดผ่านระเบียบวัดผล
do $$
declare t text;
begin
  foreach t in array array['grade_symbol', 'grade_cutoff'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from grade_scheme g
                     where g.id = %I.grade_scheme_id
                       and g.institution_id = current_institution_id()))
      with check (exists (select 1 from grade_scheme g
                          where g.id = %I.grade_scheme_id
                            and g.institution_id = current_institution_id()))
    $f$, t, t, t);
  end loop;
end $$;

-- ═══ ชั้นที่ 2 — ขอบเขตของบทบาท (restrictive) ═══════════════════

-- ชิ้นงานในสมุดคะแนน
-- นักศึกษาเห็นเฉพาะชิ้นงานที่ครูเปิดเผยแล้ว ให้ตรงกับนโยบายที่มีอยู่แล้ว
-- บน gradebook_score — ถ้าปล่อยให้เห็นชิ้นงานทั้งหมด นักศึกษาจะรู้ว่ามี
-- ชิ้นงานที่ยังไม่เปิดเผยกี่ชิ้นและคะแนนเต็มเท่าไร ซึ่งเป็นการรั่วทางอ้อม
create policy gradebook_item_scope on gradebook_item
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from class_section cs
               join staff st on st.id = cs.teacher_id
               where cs.id = gradebook_item.class_section_id
                 and st.person_id = current_actor_id())
    or (gradebook_item.publish_to_student
        and gradebook_item.class_section_id in (select actor_section_ids()))
  );

-- รอบส่งเกรดและประวัติขั้นอนุมัติ เป็นงานของครูกับฝ่ายบริหาร
-- นักศึกษาไม่ต้องเห็นว่าเกรดของตัวเองค้างอยู่ขั้นไหน
create policy submission_scope on grade_submission
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from class_section cs
               join staff st on st.id = cs.teacher_id
               where cs.id = grade_submission.class_section_id
                 and st.person_id = current_actor_id())
  );

create policy submission_event_scope on grade_submission_event
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from grade_submission gs
               join class_section cs on cs.id = gs.class_section_id
               join staff st on st.id = cs.teacher_id
               where gs.id = grade_submission_event.submission_id
                 and st.person_id = current_actor_id())
  );

-- คำร้องแก้เกรด — เจ้าตัวควรตามสถานะคำร้องของตัวเองได้
create policy change_request_scope on grade_change_request
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from enrollment e
               join class_section cs on cs.id = e.class_section_id
               join staff st on st.id = cs.teacher_id
               where e.id = grade_change_request.enrollment_id
                 and st.person_id = current_actor_id())
    or grade_change_request.enrollment_id in (select actor_enrollment_ids())
  );

-- GPA และ GPAX — ตรงกับขอบเขตของ enrollment_result ที่ใช้อยู่แล้ว
-- ผู้ปกครองต้องยืนยันตัวตนแล้วและมีสิทธิ์ดูผลการเรียนเท่านั้น
create policy term_summary_scope on term_summary
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or term_summary.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = term_summary.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_grades)
  );

-- grade_symbol และ grade_cutoff เป็นข้อมูลอ้างอิงระดับวิทยาลัย
-- ทุกบทบาทในวิทยาลัยเดียวกันอ่านได้ จึงมีแค่ชั้นที่ 1 พอ
-- แต่แก้ไขต้องเป็นฝ่ายวัดผล — ระเบียบวัดผลเปลี่ยนแล้วกระทบทุกคนย้อนหลัง
create policy grade_symbol_write on grade_symbol
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy grade_cutoff_write on grade_cutoff
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

commit;

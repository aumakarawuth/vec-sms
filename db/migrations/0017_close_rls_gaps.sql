-- ═══════════════════════════════════════════════════════════════════
-- 0017_close_rls_gaps.sql
--
-- ปิด Row-Level Security ให้ตารางที่เหลืออีก 28 ตาราง
--
-- ─── ทำไมตารางกลุ่มนี้ถึงหลุด ───
-- ทั้งหมดเป็น "ตารางลูก" ที่ตอนออกแบบคิดว่าเข้าถึงผ่านตารางแม่เท่านั้น
-- ซึ่งตารางแม่มี RLS ครบอยู่แล้ว แต่ **RLS ใน PostgreSQL ไม่ถ่ายทอด
-- ผ่านคีย์นอก** — ถ้าใครเขียน
--
--   select * from installment where due_on < current_date
--
-- จะได้งวดผ่อนชำระของทุกวิทยาลัย ไม่ใช่แค่ของตัวเอง การป้องกันที่มีอยู่
-- ทำงานก็ต่อเมื่อ query นั้นบังเอิญ join ผ่านตารางแม่เท่านั้น ซึ่งเป็น
-- การพึ่งวินัยของคนเขียน query ไม่ใช่การบังคับของระบบ
--
-- ─── กับดักที่ต้องเลี่ยง: policy ที่อ้างกันเองจนวนไม่รู้จบ ───
-- นโยบาย subject_scope ของ student อ้าง student_guardian อยู่แล้ว
-- ถ้า student_guardian อ้างกลับไปที่ student เพื่อหาว่าอยู่วิทยาลัยไหน
-- PostgreSQL จะฟ้อง "infinite recursion detected in policy"
-- นโยบาย section_scope ของ class_section อ้าง class_meeting ก็เข้าคู่เดียวกัน
--
-- ทางแก้คือฟังก์ชัน security definer ที่หาสังกัดโดยไม่ผ่าน RLS
-- วิธีเดียวกับที่ migration 0012 ใช้กับ actor_student_ids()
-- ได้ผลพลอยได้คือเร็วขึ้นด้วย เพราะไม่ต้องประเมินนโยบายของตารางแม่
-- ซ้ำทุกแถวของตารางลูก
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตัวช่วยหาสังกัด — ข้าม RLS โดยเจตนา
--
-- ปลอดภัยเพราะรับ id เข้ามาแล้วคืน "รหัสวิทยาลัย" ออกไปอย่างเดียว
-- ไม่ได้คืนข้อมูลส่วนบุคคลใด ๆ ผู้เรียกต้องรู้ id อยู่แล้วจึงจะเรียกได้
-- และค่าที่ได้ถูกเอาไปเทียบกับ current_institution_id() ทันที
-- ───────────────────────────────────────────────────────────────────
create or replace function student_institution(p_student_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select institution_id from student where id = p_student_id
$$;

create or replace function class_section_institution(p_section_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select institution_id from class_section where id = p_section_id
$$;

create or replace function curriculum_version_institution(p_version_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select cu.institution_id
    from curriculum_version cv join curriculum cu on cu.id = cv.curriculum_id
   where cv.id = p_version_id
$$;

-- ครูผู้สอนประจำกลุ่ม — ใช้ในนโยบายของ class_meeting โดยไม่แตะ class_section
create or replace function section_teacher_person_id(p_section_id uuid)
returns uuid language sql stable security definer
set search_path = public as $$
  select st.person_id
    from class_section cs join staff st on st.id = cs.teacher_id
   where cs.id = p_section_id
$$;

revoke all on function student_institution(uuid)            from public;
revoke all on function class_section_institution(uuid)      from public;
revoke all on function curriculum_version_institution(uuid) from public;
revoke all on function section_teacher_person_id(uuid)      from public;
grant execute on function student_institution(uuid)            to app_runtime;
grant execute on function class_section_institution(uuid)      to app_runtime;
grant execute on function curriculum_version_institution(uuid) to app_runtime;
grant execute on function section_teacher_person_id(uuid)      to app_runtime;

-- ═══ ชั้นที่ 1 — แยกข้อมูลระหว่างสถานศึกษา (permissive) ═══════════

-- 1ก. มี institution_id อยู่บนตัวเอง
do $$
declare t text;
begin
  foreach t in array array['behavior_policy', 'risk_policy'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- 1ข. สืบทอดผ่านตารางแม่ที่มี institution_id อยู่บนตัวเอง
do $$
declare r record;
begin
  for r in
    select * from (values
      ('attendance_status_weight', 'attendance_policy',  'attendance_policy_id'),
      ('program_track',            'program',            'program_id'),
      ('curriculum_version',       'curriculum',         'curriculum_id'),
      ('fee_schedule_line',        'fee_schedule',       'fee_schedule_id'),
      ('installment',              'invoice',            'invoice_id'),
      ('invoice_line',             'invoice',            'invoice_id'),
      ('payment_allocation',       'payment',            'payment_id'),
      ('ledger_entry',             'ledger_transaction', 'transaction_id')
    ) as t(child, parent, fk)
  loop
    execute format('alter table %I enable row level security', r.child);
    execute format('alter table %I force  row level security', r.child);
    execute format($f$
      create policy tenant_isolation on %I
      using (exists (select 1 from %I p
                     where p.id = %I.%I and p.institution_id = current_institution_id()))
      with check (exists (select 1 from %I p
                          where p.id = %I.%I and p.institution_id = current_institution_id()))
    $f$, r.child, r.parent, r.child, r.fk, r.parent, r.child, r.fk);
  end loop;
end $$;

-- 1ค. สืบทอดผ่านนักศึกษา — ใช้ตัวช่วย definer กันวนไม่รู้จบกับ student_guardian
do $$
declare t text;
begin
  foreach t in array array[
    'cocurricular_result', 'practicum_log', 'student_curriculum',
    'student_graduation_status', 'student_guardian', 'student_status_history',
    'professional_standard_assessment'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (student_institution(%I.student_id) = current_institution_id())
      with check (student_institution(%I.student_id) = current_institution_id())
    $f$, t, t, t);
  end loop;
end $$;

-- 1ง. สืบทอดผ่านฉบับหลักสูตร
do $$
declare t text;
begin
  foreach t in array array[
    'competency', 'course_competency', 'course_prerequisite',
    'curriculum_category', 'curriculum_course', 'entry_pathway', 'graduation_rule'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (curriculum_version_institution(%I.curriculum_version_id) = current_institution_id())
      with check (curriculum_version_institution(%I.curriculum_version_id) = current_institution_id())
    $f$, t, t, t);
  end loop;
end $$;

-- 1จ. คาบเรียน — ใช้ตัวช่วย definer กันวนไม่รู้จบกับ section_scope ของ class_section
alter table class_meeting enable row level security;
alter table class_meeting force  row level security;
create policy tenant_isolation on class_meeting
  using (class_section_institution(class_meeting.class_section_id) = current_institution_id())
  with check (class_section_institution(class_meeting.class_section_id) = current_institution_id());

-- 1ฉ. โซ่ที่ลึกกว่าหนึ่งชั้น
alter table pathway_bridging_course enable row level security;
alter table pathway_bridging_course force  row level security;
create policy tenant_isolation on pathway_bridging_course
  using (exists (select 1 from entry_pathway ep
                 where ep.id = pathway_bridging_course.entry_pathway_id
                   and curriculum_version_institution(ep.curriculum_version_id) = current_institution_id()))
  with check (exists (select 1 from entry_pathway ep
                      where ep.id = pathway_bridging_course.entry_pathway_id
                        and curriculum_version_institution(ep.curriculum_version_id) = current_institution_id()));

alter table professional_standard_competency_result enable row level security;
alter table professional_standard_competency_result force  row level security;
create policy tenant_isolation on professional_standard_competency_result
  using (exists (select 1 from professional_standard_assessment a
                 where a.id = professional_standard_competency_result.assessment_id
                   and student_institution(a.student_id) = current_institution_id()))
  with check (exists (select 1 from professional_standard_assessment a
                      where a.id = professional_standard_competency_result.assessment_id
                        and student_institution(a.student_id) = current_institution_id()));

alter table intervention_action enable row level security;
alter table intervention_action force  row level security;
create policy tenant_isolation on intervention_action
  using (exists (select 1 from intervention_case ic
                 where ic.id = intervention_action.case_id
                   and student_institution(ic.student_id) = current_institution_id()))
  with check (exists (select 1 from intervention_case ic
                      where ic.id = intervention_action.case_id
                        and student_institution(ic.student_id) = current_institution_id()));

-- ═══ ชั้นที่ 2 — ขอบเขตของบทบาท (restrictive) ═══════════════════

-- ── คาบเรียน — ตรงกับ section_scope ของกลุ่มเรียน ─────────────────
-- ครูสอนแทนต้องเห็นคาบที่ตนสอน แม้ไม่ใช่ครูประจำกลุ่ม
create policy meeting_scope on class_meeting
  as restrictive
  using (
    is_institution_wide_role()
    or section_teacher_person_id(class_meeting.class_section_id) = current_actor_id()
    or exists (select 1 from staff st
               where st.id = class_meeting.taught_by
                 and st.person_id = current_actor_id())
    or class_meeting.class_section_id in (select actor_section_ids())
  );

-- ── การเงิน — ตรงกับ subject_scope ของใบแจ้งหนี้ ─────────────────
-- ผู้ปกครองต้องยืนยันตัวตนแล้วและมีสิทธิ์ดูการเงิน จึงจะเห็นงวดผ่อนชำระ
do $$
declare t text;
begin
  foreach t in array array['installment', 'invoice_line'] loop
    execute format($f$
      create policy finance_subject_scope on %I
        as restrictive
        using (
          current_app_role() in ('finance', 'registrar', 'director', 'admin')
          or exists (select 1 from invoice i
                     join student s on s.id = i.student_id
                     where i.id = %I.invoice_id
                       and s.person_id = current_actor_id())
          or exists (select 1 from invoice i
                     join student_guardian sg on sg.student_id = i.student_id
                     where i.id = %I.invoice_id
                       and sg.person_id  = current_actor_id()
                       and sg.verified_at is not null
                       and sg.can_view_finance)
        )
    $f$, t, t, t);
  end loop;
end $$;

-- การตัดยอดและบัญชีแยกประเภทเป็นงานหลังบ้านล้วน นักศึกษาไม่ต้องเห็น
create policy allocation_scope on payment_allocation
  as restrictive
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy ledger_entry_scope on ledger_entry
  as restrictive
  using (current_app_role() in ('finance', 'director', 'admin'));

-- แก้บัญชีย้อนหลังไม่ได้ ให้ตรงกับ ledger_no_rewrite ของรายการแม่
-- ถ้ากันแต่ที่ตารางแม่ การเพิ่มบรรทัดเข้ารายการเก่ายังทำได้อยู่
create policy ledger_entry_no_rewrite on ledger_entry
  as restrictive
  for all
  using (true)
  with check (exists (select 1 from ledger_transaction lt
                      where lt.id = ledger_entry.transaction_id
                        and lt.posted_at >= now() - interval '1 day'));

-- ── ข้อมูลรายบุคคลของนักศึกษา ────────────────────────────────────
-- ตรงกับ subject_scope ของ enrollment_result ที่ใช้อยู่แล้ว
do $$
declare t text;
begin
  foreach t in array array[
    'cocurricular_result', 'student_graduation_status',
    'professional_standard_assessment', 'student_curriculum'
  ] loop
    execute format($f$
      create policy subject_scope on %I
        as restrictive
        using (
          is_institution_wide_role()
          or current_app_role() = 'teacher'
          or %I.student_id in (select actor_student_ids())
          or exists (select 1 from student_guardian sg
                     where sg.student_id = %I.student_id
                       and sg.person_id  = current_actor_id()
                       and sg.verified_at is not null
                       and sg.can_view_grades)
        )
    $f$, t, t, t);
  end loop;
end $$;

-- ประวัติการเปลี่ยนสถานะเป็นเอกสารทางทะเบียน ครูผู้สอนทั่วไปไม่ต้องเห็น
create policy status_history_scope on student_status_history
  as restrictive
  using (
    is_institution_wide_role()
    or student_status_history.student_id in (select actor_student_ids())
  );

/*
 * บันทึกฝึกประสบการณ์มีพิกัดเช็คอินและรูปถ่าย จึงอ่อนไหวกว่าข้อมูลเรียนทั่วไป
 * ครูผู้สอนทั่วไปไม่ควรเห็นว่านักศึกษาอยู่พิกัดไหนตอนไหน
 * เห็นได้เฉพาะครูนิเทศที่รับรองชั่วโมง และเจ้าตัวกับผู้ปกครองที่ยืนยันแล้ว
 */
create policy practicum_scope on practicum_log
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from staff st
               where st.id = practicum_log.verified_by
                 and st.person_id = current_actor_id())
    or practicum_log.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = practicum_log.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null)
  );

/*
 * ความสัมพันธ์ผู้ปกครอง — ห้ามอ้าง student ในนโยบายนี้
 *
 * subject_scope ของ student อ้าง student_guardian อยู่แล้ว ถ้าอ้างกลับ
 * PostgreSQL จะฟ้อง infinite recursion จึงใช้ actor_student_ids()
 * ซึ่งเป็น security definer และไม่ปลุกนโยบายของ student ขึ้นมาอีกรอบ
 *
 * ผู้ปกครองต้องเห็นแถวของตัวเองได้ มิฉะนั้นนโยบายของ invoice และ student
 * ที่ตรวจ "มีผู้ปกครองที่ยืนยันแล้วไหม" จะหาไม่เจอ แล้วผู้ปกครองจะเข้าไม่ได้ทั้งระบบ
 */
create policy guardian_scope on student_guardian
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or student_guardian.person_id = current_actor_id()
    or student_guardian.student_id in (select actor_student_ids())
  );

-- ── ข้อมูลอ้างอิงระดับวิทยาลัย ───────────────────────────────────
-- อ่านได้ทุกบทบาทในวิทยาลัยเดียวกัน เพราะเป็นโครงสร้างหลักสูตรที่ทุกคนต้องใช้
-- แต่แก้ไขต้องเป็นฝ่ายวิชาการ — เปลี่ยนโครงสร้างหลักสูตรกระทบการตรวจจบย้อนหลัง
do $$
declare t text;
begin
  foreach t in array array[
    'curriculum_version', 'competency', 'course_competency', 'course_prerequisite',
    'curriculum_category', 'curriculum_course', 'entry_pathway', 'graduation_rule',
    'pathway_bridging_course', 'program_track'
  ] loop
    execute format($f$
      create policy academic_write_only on %I
        as restrictive
        for all
        using (true)
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- นโยบายค่าธรรมเนียมและเกณฑ์ความเสี่ยงเป็นค่าตั้งที่กระทบทุกคนทันทีที่แก้
create policy finance_write_only on fee_schedule_line
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

do $$
declare t text;
begin
  foreach t in array array['risk_policy', 'behavior_policy'] loop
    execute format($f$
      create policy affairs_write_only on %I
        as restrictive
        for all
        using (true)
        with check (current_app_role() in ('student_affairs', 'academic', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

create policy attendance_policy_write_only on attendance_status_weight
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

commit;

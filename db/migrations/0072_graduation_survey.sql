-- ═══════════════════════════════════════════════════════════════════
-- 0072_graduation_survey.sql
--
-- แบบสำรวจภาวะการมีงานทำของผู้สำเร็จการศึกษา — ชุดคำถามมาตรฐานทั่วไป
-- ยังไม่ได้เทียบกับแบบฟอร์มที่ สอศ. กำหนดจริง (เหมือน O-NET ใน 0071)
--
-- ─── ทำไมไม่ผูก unique (student_id) ───
-- วิทยาลัยบางแห่งสำรวจซ้ำหลังจบ (เช่น ทันทีที่จบ + ตามผลอีกครั้งหลังจบ 1 ปี)
-- ผูก unique ไว้ตั้งแต่ต้นจะปิดทางสำรวจซ้ำโดยไม่มีเหตุผลรองรับ — ปล่อยให้มี
-- ได้หลายแถวต่อคน แล้วหน้าจอแสดงแถวล่าสุดเป็นค่าเริ่มต้น
-- ═══════════════════════════════════════════════════════════════════
begin;

create type employment_status_kind as enum (
  'employed', 'employed_and_studying', 'further_study', 'seeking', 'other'
);

create table graduation_survey_response (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  student_id     uuid          not null references student on delete cascade,
  graduation_id  uuid          references student_graduation on delete set null,
  status         employment_status_kind not null,

  employer_name_th  text,
  job_title_th      text,
  monthly_income    numeric(10,2),
  field_matches_study boolean,

  further_study_institution_th text,
  further_study_field_th       text,

  contact_phone  text,
  note           text,

  responded_on   date          not null default current_date,
  recorded_by    uuid,                       -- staff ที่โทรสำรวจ — ว่างได้ถ้าบัณฑิตตอบเอง
  created_at     timestamptz   not null default now(),

  constraint graduation_survey_employed_needs_employer
    check (status not in ('employed', 'employed_and_studying') or employer_name_th is not null),
  constraint graduation_survey_study_needs_institution
    check (status not in ('further_study', 'employed_and_studying') or further_study_institution_th is not null)
);
create index on graduation_survey_response (student_id);
create index on graduation_survey_response (institution_id, responded_on desc);

comment on table graduation_survey_response is
  'แบบสำรวจภาวะการมีงานทำของผู้สำเร็จการศึกษา — ชุดคำถามทั่วไป ยังไม่เทียบกับแบบฟอร์มที่ สอศ. กำหนดจริง ปล่อยให้สำรวจซ้ำได้หลายรอบต่อคนโดยตั้งใจ';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security — รูปแบบเดียวกับ prior_academic_record / national_exam_result
-- ───────────────────────────────────────────────────────────────────
alter table graduation_survey_response enable row level security;
alter table graduation_survey_response force  row level security;

create policy tenant_isolation on graduation_survey_response
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy graduation_survey_scope on graduation_survey_response
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or graduation_survey_response.student_id in (select actor_student_ids())
  );

create policy graduation_survey_write on graduation_survey_response
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','student_affairs','academic','director','admin']));
create policy graduation_survey_update on graduation_survey_response
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','student_affairs','academic','director','admin']));
create policy graduation_survey_delete on graduation_survey_response
  as restrictive for delete
  using (current_app_role() = any (array['registrar','student_affairs','academic','director','admin']));

grant select, insert, update, delete on graduation_survey_response to app_runtime;

commit;

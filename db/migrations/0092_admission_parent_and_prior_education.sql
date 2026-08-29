-- ═══════════════════════════════════════════════════════════════════
-- 0092 — งานรับสมัครกรอกข้อมูลบิดามารดาได้ และรับเข้าแล้วข้อมูลจริงไปถึง
-- แฟ้มนักศึกษาโดยอัตโนมัติ
--
-- ═══ อาการที่แก้ ═══
-- 1. `application` (0033) ไม่มีช่องบิดามารดาเลยสักคอลัมน์ ทั้งที่ใบสมัคร
--    กระดาษของทุกวิทยาลัยมีช่องนี้อยู่แล้ว — เจ้าหน้าที่รับสมัครกรอกได้แค่
--    ตัวผู้สมัครคนเดียว แล้วต้องมาเปิดแฟ้มนักศึกษาอีกรอบเพื่อกรอกบิดามารดา
--    ทั้งที่กระดาษใบเดียวกันมีข้อมูลอยู่แล้วตั้งแต่วันสมัคร
-- 2. `admit_applicant()` (0033) ไม่เคยเขียน `student_prior_education` เลย
--    ทั้งที่คอมเมนต์ของ `application.prior_school_th` เขียนไว้เองว่า
--    "ใช้ทั้งตรวจคุณสมบัติและกรอก prior_academic_record ตอนรับเข้า" —
--    ของที่ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น (รูปเดียวกับ
--    ข้อ 8/9/15/20/21 ในบทเรียนที่ CLAUDE.md บันทึกไว้) ผลคือนักศึกษาทุกคน
--    ที่รับเข้าทางนี้มีแท็บ "การศึกษา" ว่างเปล่า ทั้งที่กรอกวุฒิเดิมไว้ตั้งแต่
--    ใบสมัครแล้ว
--
-- ═══ ทำไมกรอกที่ใบสมัคร ไม่ใช่บังคับให้ไปกรอกที่แฟ้มนักศึกษาทีหลัง ═══
-- ใบสมัครกระดาษมีข้อมูลนี้อยู่แล้ววันเดียว เจ้าหน้าที่รับสมัครเห็นหน้าผู้ปกครอง
-- อยู่ตรงหน้า ให้กรอกซ้ำอีกรอบหลังรับเข้าเป็นการเสียเวลาสองเท่าโดยไม่มี
-- เหตุผล และเสี่ยงกรอกไม่ตรงกับที่เขียนในใบสมัครเพราะจำผิด
--
-- ═══ ทำไมยังไม่มีช่องผู้ปกครอง (guardian) ═══
-- บิดา/มารดาอยู่ใน parent_role ที่มีแค่ 'father'/'mother' (0053) ส่วน
-- ผู้ปกครองที่ไม่ใช่บิดามารดาอยู่ในตาราง `student_guardian` คนละตัว ซึ่งผูก
-- กับ `person` เพราะผู้ปกครองกลุ่มนี้เข้าระบบได้จริง (ดูแอปผู้ปกครอง) —
-- การเพิ่มช่องผู้ปกครองที่ใบสมัครแปลว่าต้องตัดสินใจเพิ่มว่าจะสร้างบัญชี
-- ผู้ปกครองให้เลยไหม ซึ่งเป็นคนละงานกับการกรอกข้อมูลบิดามารดา — เพิ่มทีหลัง
-- เมื่อมีคนขอจริง (หลักเดียวกับที่ 0070 ยังไม่ผูกชมรมกับเกณฑ์จบ)
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table application
  add column if not exists father_prefix_th      text,
  add column if not exists father_first_name_th  text,
  add column if not exists father_last_name_th   text,
  add column if not exists father_national_id_hash bytea,
  add column if not exists father_occupation_th  text,
  add column if not exists father_income_monthly numeric(12,2)
    check (father_income_monthly is null or father_income_monthly >= 0),
  add column if not exists father_phone          text,

  add column if not exists mother_prefix_th      text,
  add column if not exists mother_first_name_th  text,
  add column if not exists mother_last_name_th   text,
  add column if not exists mother_national_id_hash bytea,
  add column if not exists mother_occupation_th  text,
  add column if not exists mother_income_monthly numeric(12,2)
    check (mother_income_monthly is null or mother_income_monthly >= 0),
  add column if not exists mother_phone          text;

comment on column application.father_national_id_hash is
  'เก็บเป็นค่าแฮชเท่านั้น หลักเดียวกับ application.national_id_hash — ไม่เก็บเลขจริง';
comment on column application.father_income_monthly is
  'ใช้พิจารณาทุนตอนรับเข้า หลักเดียวกับ student_parent.income_monthly';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ผู้อำนวยการรับเข้าไม่ได้ถ้าใบสมัครมีข้อมูลบิดามารดา/วุฒิเดิม —
-- นโยบายเขียนของ student_parent (0053) และ student_prior_education (0053)
-- ไม่มี 'director' อยู่เลย ทั้งที่ AdmissionsController อนุญาตให้ director
-- เรียก /admit ได้ (@Roles('registrar', 'director', 'admin')) — ถ้าไม่แก้
-- ตรงนี้ก่อน admit_applicant() ด้านล่างจะ insert ชน RLS กลางทางทันทีที่
-- director เป็นคนกดรับเข้าแล้วใบสมัครมีชื่อบิดาหรือมารดามา (บทเรียนเดียว
-- กับข้อ 6/14 — เส้นทางที่ @Roles ชั้น API เปิดไว้แล้ว แต่ RLS ยังไม่รู้เรื่อง)
-- ───────────────────────────────────────────────────────────────────
begin;

drop policy if exists parent_insert on student_parent;
create policy parent_insert on student_parent
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'student_affairs', 'director', 'admin'));

drop policy if exists prior_education_insert on student_prior_education;
create policy prior_education_insert on student_prior_education
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

commit;

-- ═══════════════════════════════════════════════════════════════════
-- แก้ admit_applicant() ให้คัดลอกวุฒิเดิม + บิดามารดาไปที่แฟ้มนักศึกษา
--
-- แทนที่ทั้งฟังก์ชันเพราะโค้ดเดิมสั้นและการแก้แบบแยกส่วนจะทำให้แถวใหม่ที่
-- แทรกอยู่กลางฟังก์ชันอ่านยากกว่าดูทั้งก้อน — สิ่งที่เปลี่ยนจริงมีแค่ท้าย
-- ฟังก์ชัน (ส่วน insert ที่เพิ่มเข้ามา) โครงเดิมทั้งหมดยังเหมือนเดิมทุก
-- ประการ (ตรวจสถานะ · ใช้ person เดิมถ้ามี · สร้าง student · ผูกหลักสูตร
-- และห้อง)
-- ═══════════════════════════════════════════════════════════════════
create or replace function admit_applicant(
  p_application_id   uuid,
  p_student_code     text,
  p_academic_year_id uuid,
  p_study_year       smallint default 1,
  p_group_code       text     default null
) returns uuid language plpgsql as $$
declare
  v_app     application;
  v_inst    uuid := current_institution_id();
  v_person  uuid;
  v_student uuid;
begin
  select * into v_app from application where id = p_application_id;
  if v_app.id is null then
    raise exception 'ไม่พบใบสมัครที่ระบุ';
  end if;
  if v_app.status <> 'passed' then
    raise exception 'รับเข้าได้เฉพาะผู้ที่ผ่านการคัดเลือก (สถานะ %)', v_app.status
      using errcode = 'check_violation';
  end if;
  if v_app.student_id is not null then
    raise exception 'ใบสมัครนี้รับเข้าไปแล้ว'
      using errcode = 'check_violation';
  end if;
  if coalesce(btrim(p_student_code), '') = '' then
    raise exception 'ต้องระบุรหัสนักศึกษา';
  end if;

  -- คนที่เคยเรียนแล้วลาออกไปสมัครใหม่มีอยู่จริง ใช้ person เดิมต่อ
  -- มิฉะนั้นจะชน unique (institution_id, national_id_hash) แล้วรับเข้าไม่ได้
  if v_app.national_id_hash is not null then
    select p.id into v_person from person p
     where p.institution_id = v_inst
       and p.national_id_hash = v_app.national_id_hash;
  end if;

  if v_person is null then
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email)
    values (v_inst, v_app.prefix_th, v_app.first_name_th, v_app.last_name_th,
            v_app.national_id_hash, v_app.birth_date, v_app.gender,
            v_app.phone, v_app.email)
    returning id into v_person;
  end if;

  insert into student
    (institution_id, person_id, student_code, admitted_year_be, status)
  values (v_inst, v_person, btrim(p_student_code),
          (select ay.year_be from academic_year ay where ay.id = p_academic_year_id),
          'active')
  returning id into v_student;

  insert into student_curriculum (student_id, curriculum_version_id, effective_from)
  values (v_student, v_app.admitted_curriculum_version_id, current_date);

  insert into student_class_placement
    (institution_id, student_id, academic_year_id, study_year, group_code)
  values (v_inst, v_student, p_academic_year_id, p_study_year, p_group_code);

  -- ─── วุฒิเดิม ───
  -- level_th เป็น not null และเป็นส่วนหนึ่งของ unique (student_id, level_th)
  -- ใบสมัครไม่มีคอลัมน์ "ระดับ" แยกต่างหาก จึงใช้ prior_qualification_th
  -- เป็น level_th โดยตรง — ถ้าเจ้าหน้าที่ไม่ได้กรอกอะไรมาเลยก็ไม่ต้อง insert
  -- แถวเปล่า (ต่างจาก student/person ที่ต้องมีเสมอ)
  if v_app.prior_school_th is not null or v_app.prior_qualification_th is not null
     or v_app.prior_gpax is not null then
    insert into student_prior_education
      (institution_id, student_id, level_th, gpax, school_th)
    values (v_inst, v_student,
            coalesce(nullif(btrim(v_app.prior_qualification_th), ''), 'ไม่ระบุระดับ'),
            v_app.prior_gpax, v_app.prior_school_th)
    on conflict (student_id, level_th) do nothing;
  end if;

  -- ─── บิดามารดา ───
  -- มีชื่ออย่างน้อยหนึ่งคนถึงจะ insert — unique (student_id, role) กันซ้ำ
  -- อยู่แล้ว แต่ไม่ต้องการแถวเปล่าที่ไม่มีชื่อเลยสักตัว
  if v_app.father_first_name_th is not null then
    insert into student_parent
      (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
       national_id_hash, occupation_th, income_monthly, phone)
    values (v_inst, v_student, 'father', v_app.father_prefix_th,
            v_app.father_first_name_th, v_app.father_last_name_th,
            v_app.father_national_id_hash, v_app.father_occupation_th,
            v_app.father_income_monthly, v_app.father_phone)
    on conflict (student_id, role) do nothing;
  end if;

  if v_app.mother_first_name_th is not null then
    insert into student_parent
      (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
       national_id_hash, occupation_th, income_monthly, phone)
    values (v_inst, v_student, 'mother', v_app.mother_prefix_th,
            v_app.mother_first_name_th, v_app.mother_last_name_th,
            v_app.mother_national_id_hash, v_app.mother_occupation_th,
            v_app.mother_income_monthly, v_app.mother_phone)
    on conflict (student_id, role) do nothing;
  end if;

  -- ─── ทำไมไม่คัดลอกวุฒิเดิมลง prior_academic_record (คนละตารางกับ
  -- student_prior_education ด้านบน) ───
  -- prior_academic_record เก็บ**ผลรายวิชา**เพื่อเทียบโอนหน่วยกิต (มี
  -- credits > 0 เป็นข้อบังคับ) ไม่ใช่ "วุฒิที่จบมา" การยัดแถวปลอมที่มีรหัส
  -- วิชาเป็น '-' และหน่วยกิตเป็นศูนย์ลงไป จะทำให้ทุกรายงานที่นับรายวิชา
  -- เทียบโอนมีขยะปน — ถ้าวันหนึ่งต้องเทียบโอนรายวิชาจริง ให้กรอกผ่าน
  -- เส้นทางเทียบโอนโดยตรง (ย่อหน้านี้คัดลอกมาจากต้นฉบับ 0033 เพราะยังเป็น
  -- เหตุผลที่ใช้ได้อยู่ ต่างจาก student_prior_education ที่แก้ไว้ด้านบน)
  update application
     set student_id = v_student,
         status     = 'enrolled',
         reported_on = coalesce(reported_on, current_date)
   where id = p_application_id;

  return v_student;
end $$;

comment on function admit_applicant(uuid, text, uuid, smallint, text) is
  'เปลี่ยนผู้สมัครเป็นนักศึกษา — จุดเดียวในระบบที่ทำเรื่องนี้ ทำได้ครั้งเดียวต่อใบสมัคร '
  'พร้อมคัดลอกวุฒิเดิมและบิดามารดาไปที่แฟ้มนักศึกษาถ้ามีข้อมูลในใบสมัคร (0092)';

-- ═══════════════════════════════════════════════════════════════════
-- 0100_application_keyed_hash.sql
-- เลขบัตรประชาชนในใบสมัครแฮชด้วยกุญแจ — เหมือนที่ 0061 ทำกับนักศึกษา
--
-- ─── ที่มา ───
-- 0033/0092 เก็บเลขบัตรของผู้สมัครและบิดามารดาเป็น digest(sha256) เปล่า
-- เลขบัตรไทยมีราว 10¹² ค่า ไล่ครบด้วยการ์ดจอใบเดียวในไม่กี่นาที "เก็บแค่แฮช"
-- จึงไม่ได้ป้องกันอะไร (CLAUDE.md หัวข้อ national_id_enc) และ admit_applicant()
-- คัดลอกค่านั้นต่อไปที่ person/student_parent ซึ่ง 0061 ตั้งใจให้เป็นรุ่น 2
--
-- ─── วิธีแก้ ───
-- ชั้น API คำนวณ HMAC ด้วย hashNationalId() ตัวเดียวกับระเบียนนักศึกษาแล้วส่ง
-- ไบต์มา ฐานข้อมูลไม่เห็นเลขจริงอีกเลย · ใบสมัครมีป้ายรุ่น (national_id_hash_v)
-- แบบเดียวกับ person และ admit_applicant() ส่งป้ายต่อไปให้ person/student_parent
--
-- ─── ใบเก่า ───
-- ค่าแฮชเก่าแปลงเป็นรุ่น 2 ไม่ได้เพราะไม่มีเลขต้นฉบับ จึงคงไว้พร้อมป้ายรุ่น 1
-- และการหาคนเดิมตอนรับเข้าเทียบเฉพาะแฮชรุ่นเดียวกัน — เทียบข้ามรุ่นได้ผลว่า
-- "ไม่ใช่คนเดิม" เสมอ ซึ่งคือสิ่งที่เกิดจริงอยู่แล้ว แต่ตอนนี้รู้ตัว
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table application
  add column if not exists national_id_hash_v smallint not null default 1
    check (national_id_hash_v in (1, 2));

comment on column application.national_id_hash_v is
  'รุ่นของค่าแฮชเลขบัตรของผู้สมัครและบิดามารดาในใบนี้ — 1 = sha256 เปล่า (ย้อนกลับได้) · 2 = HMAC ที่ชั้น API (0100)';

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
       and p.national_id_hash = v_app.national_id_hash
       and p.national_id_hash_v = v_app.national_id_hash_v;
  end if;

  if v_person is null then
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, national_id_hash_v, birth_date, gender, phone, email)
    values (v_inst, v_app.prefix_th, v_app.first_name_th, v_app.last_name_th,
            v_app.national_id_hash, v_app.national_id_hash_v, v_app.birth_date, v_app.gender,
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
       national_id_hash, national_id_hash_v, occupation_th, income_monthly, phone)
    values (v_inst, v_student, 'father', v_app.father_prefix_th,
            v_app.father_first_name_th, v_app.father_last_name_th,
            v_app.father_national_id_hash, v_app.national_id_hash_v, v_app.father_occupation_th,
            v_app.father_income_monthly, v_app.father_phone)
    on conflict (student_id, role) do nothing;
  end if;

  if v_app.mother_first_name_th is not null then
    insert into student_parent
      (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
       national_id_hash, national_id_hash_v, occupation_th, income_monthly, phone)
    values (v_inst, v_student, 'mother', v_app.mother_prefix_th,
            v_app.mother_first_name_th, v_app.mother_last_name_th,
            v_app.mother_national_id_hash, v_app.national_id_hash_v, v_app.mother_occupation_th,
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

commit;

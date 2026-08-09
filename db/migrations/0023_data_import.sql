-- ═══════════════════════════════════════════════════════════════════
-- 0023_data_import.sql
--
-- นำเข้าข้อมูลนักศึกษาและประวัติการเรียนจากระบบเดิม
--
-- ─── ปัญหาที่แก้ ───
-- วิทยาลัยที่ย้ายมาใช้ระบบนี้มีนักศึกษาอยู่แล้วหลักพันคน พร้อมผลการเรียน
-- ย้อนหลังหลายภาคเรียน จะเริ่มจากฐานข้อมูลเปล่าไม่ได้ และการให้เจ้าหน้าที่
-- กรอกทีละคนใช้เวลาเป็นเดือนและผิดพลาดมากกว่าการนำเข้า
--
-- ─── ทำไมต้องมีรอบทดลอง (dry run) ───
-- การนำเข้าที่ล้มเหลวกลางคันแล้วเหลือข้อมูลครึ่ง ๆ กลาง ๆ แก้ยากกว่าไม่นำเข้าเลย
-- เพราะเจ้าหน้าที่ไม่รู้ว่าแถวไหนเข้าไปแล้วบ้าง รอบทดลองตรวจทุกแถวแล้วรายงาน
-- ปัญหาทั้งหมดกลับไปโดยไม่เขียนอะไรเลย ให้แก้ไฟล์ให้ถูกก่อนค่อยนำเข้าจริง
--
-- ─── ทำไมประวัติการเรียนที่นำเข้าต้องแยกออกจากผลที่ระบบตัดเอง ───
-- enrollment_result เป็นตารางเขียนอย่างเดียวที่มีโซ่แฮชกำกับ ใช้ยันจำนวน
-- นักศึกษาที่ขอรับเงินอุดหนุนและออกเอกสารราชการ ผลที่นำเข้ามาจากระบบเดิม
-- ไม่ได้ผ่านการตัดเกรดของระบบนี้ จึงต้องแยกให้เห็นชัดว่าแถวไหนมาจากไหน
-- มิฉะนั้นตอนตรวจสอบจะแยกไม่ออกระหว่าง "ระบบคำนวณให้" กับ "คนกรอกเข้ามา"
-- ═══════════════════════════════════════════════════════════════════
begin;

create type import_kind   as enum ('student', 'academic_history', 'staff');
create type import_status as enum ('draft', 'validated', 'applied', 'failed');

create table import_batch (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  kind           import_kind   not null,
  source_name    text,                       -- ชื่อไฟล์ต้นทาง ใช้ตามรอยว่ามาจากไหน
  status         import_status not null default 'draft',
  total_rows     integer       not null default 0,
  ok_rows        integer       not null default 0,
  error_rows     integer       not null default 0,
  created_by     uuid,
  created_at     timestamptz   not null default now(),
  applied_at     timestamptz,
  note           text
);
create index on import_batch (institution_id, created_at desc);

comment on table import_batch is
  'หนึ่งรอบการนำเข้า — เก็บไว้เพื่อตอบว่าข้อมูลแถวไหนมาจากไฟล์ไหนเมื่อไร ซึ่งจำเป็นตอนพบข้อมูลผิดแล้วต้องตามหาต้นตอ';

create table import_row (
  id           uuid        primary key default gen_random_uuid(),
  batch_id     uuid        not null references import_batch on delete cascade,
  row_no       integer     not null,
  payload      jsonb       not null,
  ok           boolean     not null default false,
  errors       text[]      not null default '{}',
  created_ref  uuid,                        -- id ของแถวที่สร้างขึ้นจริง
  unique (batch_id, row_no)
);
create index on import_row (batch_id) where not ok;

comment on column import_row.errors is
  'ปัญหาทั้งหมดของแถวนี้ ไม่ใช่ข้อแรกที่เจอ — เจ้าหน้าที่ต้องเห็นทุกอย่างที่ต้องแก้ในรอบเดียว เหมือน check_registration()';

-- ───────────────────────────────────────────────────────────────────
-- ตรวจข้อมูลนักศึกษาหนึ่งแถว
--
-- คืนรายการปัญหาทั้งหมด ไม่หยุดที่ข้อแรก ด้วยเหตุผลเดียวกับ
-- check_registration() — ถ้าหยุดที่ข้อแรก เจ้าหน้าที่จะต้องแก้แล้วนำเข้าใหม่
-- หลายรอบกว่าจะครบ ซึ่งกับไฟล์พันแถวคือการทำงานหลายวัน
-- ───────────────────────────────────────────────────────────────────
create or replace function validate_student_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors text[] := '{}';
  v_code   text := nullif(btrim(p_payload->>'student_code'), '');
  v_first  text := nullif(btrim(p_payload->>'first_name_th'), '');
  v_last   text := nullif(btrim(p_payload->>'last_name_th'), '');
  v_year   text := p_payload->>'admitted_year_be';
  v_nat    text := nullif(btrim(p_payload->>'national_id'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวนักศึกษา');
  elsif exists (select 1 from student s
                 where s.institution_id = p_institution_id and s.student_code = v_code) then
    v_errors := array_append(v_errors, format('รหัสประจำตัว %s มีอยู่ในระบบแล้ว', v_code));
  end if;

  if v_first is null then v_errors := array_append(v_errors, 'ไม่มีชื่อ'); end if;
  if v_last  is null then v_errors := array_append(v_errors, 'ไม่มีนามสกุล'); end if;

  if v_year is null or v_year !~ '^\d{4}$' then
    v_errors := array_append(v_errors, 'ปีที่เข้าศึกษาต้องเป็นพุทธศักราชสี่หลัก');
  elsif v_year::int < 2500 or v_year::int > 2700 then
    v_errors := array_append(v_errors, format('ปีที่เข้าศึกษา %s ไม่อยู่ในช่วงที่รับได้ (2500-2700)', v_year));
  end if;

  -- เลขประจำตัวประชาชนตรวจ checksum ได้ จึงควรตรวจตั้งแต่ตอนนำเข้า
  -- ไม่ใช่ปล่อยให้ผิดแล้วไปเจอตอนออกเอกสารราชการ
  if v_nat is not null then
    if v_nat !~ '^\d{13}$' then
      v_errors := array_append(v_errors, 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก');
    elsif not thai_national_id_valid(v_nat) then
      v_errors := array_append(v_errors, format('เลขประจำตัวประชาชน %s ไม่ผ่านการตรวจหลักที่ 13', v_nat));
    end if;
  end if;

  if p_payload ? 'status'
     and p_payload->>'status' not in
         ('active','on_leave','suspended','withdrawn','transferred_out','dismissed','graduated') then
    v_errors := array_append(v_errors, format('สถานะ "%s" ไม่ถูกต้อง', p_payload->>'status'));
  end if;

  return v_errors;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจหลักที่ 13 ของเลขประจำตัวประชาชน
--
-- ตรวจได้ตั้งแต่ตอนนำเข้าโดยไม่ต้องต่อระบบภายนอก จับการพิมพ์ผิดได้เกือบทั้งหมด
-- ซึ่งสำคัญเพราะเลขนี้ใช้ยันตัวตนตอนขอรับเงินอุดหนุนและออกเอกสารราชการ
-- ───────────────────────────────────────────────────────────────────
create or replace function thai_national_id_valid(p_id text)
returns boolean
language plpgsql immutable as $$
declare v_sum integer := 0; i integer;
begin
  if p_id is null or p_id !~ '^\d{13}$' then return false; end if;
  for i in 1..12 loop
    v_sum := v_sum + substr(p_id, i, 1)::int * (14 - i);
  end loop;
  return ((11 - (v_sum % 11)) % 10) = substr(p_id, 13, 1)::int;
end $$;

comment on function thai_national_id_valid(text) is
  'ตรวจหลักที่ 13 ของเลขประจำตัวประชาชน — จับการพิมพ์ผิดได้ตั้งแต่ตอนนำเข้า ไม่ต้องรอไปเจอตอนออกเอกสาร';

-- ───────────────────────────────────────────────────────────────────
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย
--
-- ถ้ามีแถวใดผิด จะไม่เขียนอะไรเลยและคืนรายการปัญหาทั้งหมด
-- เหตุผลเดียวกับ register_courses() — ข้อมูลที่เข้าไปครึ่งเดียว
-- แก้ยากกว่าไม่เข้าเลย เพราะไม่มีใครรู้ว่าแถวไหนเข้าไปแล้ว
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_student_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch  import_batch%rowtype;
  r        record;
  v_person uuid;
  v_student uuid;
  v_bad    integer := 0;
  v_ok     integer := 0;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'student' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ข้อมูลนักศึกษา', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_student_row(v_batch.institution_id, r.payload);
      update import_row
         set errors = v_errs, ok = (cardinality(v_errs) = 0)
       where id = r.id;
      if cardinality(v_errs) > 0 then v_bad := v_bad + 1; end if;
    end;
  end loop;

  if v_bad > 0 then
    update import_batch
       set status = 'failed', error_rows = v_bad,
           ok_rows = (select count(*) from import_row where batch_id = p_batch_id and ok)
     where id = p_batch_id;
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — ดูรายละเอียดรายแถวที่ import_row', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email)
    values (
      v_batch.institution_id,
      nullif(btrim(r.payload->>'prefix_th'), ''),
      btrim(r.payload->>'first_name_th'),
      btrim(r.payload->>'last_name_th'),
      -- เก็บเป็นค่าแฮชเพื่อตรวจซ้ำได้โดยไม่ต้องเก็บเลขจริงไว้แบบอ่านออก
      -- คอลัมน์ national_id_enc รอเชื่อม KMS จึงยังไม่เขียนเลขจริงลงไป
      case when nullif(btrim(r.payload->>'national_id'), '') is not null
           then digest(btrim(r.payload->>'national_id'), 'sha256') end,
      (nullif(btrim(r.payload->>'birth_date'), ''))::date,
      coalesce(nullif(btrim(r.payload->>'gender'), ''), 'undisclosed')::gender_kind,
      nullif(btrim(r.payload->>'phone'), ''),
      nullif(btrim(r.payload->>'email'), '')
    )
    returning id into v_person;

    insert into student
      (institution_id, person_id, student_code, admitted_year_be, status)
    values (
      v_batch.institution_id, v_person,
      btrim(r.payload->>'student_code'),
      (r.payload->>'admitted_year_be')::smallint,
      coalesce(nullif(btrim(r.payload->>'status'), ''), 'active')::student_status
    )
    returning id into v_student;

    update import_row set created_ref = v_student, ok = true where id = r.id;
    v_ok := v_ok + 1;
  end loop;

  update import_batch
     set status = 'applied', applied_at = now(),
         ok_rows = v_ok, error_rows = 0, total_rows = v_ok
   where id = p_batch_id;

  imported := v_ok;
  failed   := 0;
  return next;
end $$;

comment on function apply_student_import(uuid) is
  'นำเข้าข้อมูลนักศึกษาทั้งชุด — มีแถวใดผิดจะไม่เขียนอะไรเลย เพราะข้อมูลที่เข้าไปครึ่งเดียวแก้ยากกว่าไม่เข้าเลย';

-- ───────────────────────────────────────────────────────────────────
-- ประวัติการเรียนที่นำเข้าจากระบบเดิม
--
-- ─── ทำไมไม่เขียนลง enrollment_result ตรง ๆ ───
-- enrollment_result ต้องผูกกับ enrollment ซึ่งต้องผูกกับ class_section
-- ของภาคเรียนที่มีอยู่จริงในระบบนี้ ประวัติจากระบบเดิมไม่มีสิ่งเหล่านั้น
-- การสร้างกลุ่มเรียนปลอมย้อนหลังให้ครบเพื่อรองรับประวัติ จะทำให้รายงาน
-- จำนวนกลุ่มเรียนและภาระงานครูผิดไปทั้งหมด
--
-- ตารางนี้จึงเก็บประวัติเป็นข้อมูลของตัวเอง แล้วให้การตรวจจบนับรวม
-- ซึ่งตรงกับความจริงว่า "หน่วยกิตนี้ได้มาจากที่อื่น ไม่ใช่จากระบบนี้"
-- ───────────────────────────────────────────────────────────────────
create table prior_academic_record (
  id              uuid         primary key default gen_random_uuid(),
  student_id      uuid         not null references student on delete cascade,
  batch_id        uuid         references import_batch,
  source_th       text         not null,          -- ชื่อสถานศึกษาเดิม
  term_label      text,                           -- เช่น '2566/1' ตามที่ระบบเดิมใช้
  course_code     text         not null,
  course_name_th  text         not null,
  credits         numeric(3,1) not null check (credits > 0),
  grade_symbol    text         not null,
  grade_point     numeric(2,1),
  counts_in_gpa   boolean      not null default true,
  earns_credit    boolean      not null default true,
  -- เทียบโอนเข้ารายวิชาใดในหลักสูตรปัจจุบัน ถ้าเทียบได้
  mapped_course_id uuid        references course,
  approved_by     uuid         references staff,
  approved_at     timestamptz,
  note            text,
  created_at      timestamptz  not null default now(),
  unique (student_id, term_label, course_code)
);
create index on prior_academic_record (student_id);
create index on prior_academic_record (batch_id);

comment on table prior_academic_record is
  'ผลการเรียนจากสถานศึกษาเดิม แยกจาก enrollment_result โดยเจตนา เพราะไม่ได้ผ่านการตัดเกรดของระบบนี้ และไม่มีกลุ่มเรียนจริงรองรับ';
comment on column prior_academic_record.approved_at is
  'หน่วยกิตที่ยังไม่อนุมัติเทียบโอนจะไม่ถูกนับในการตรวจจบ เหมือนชั่วโมงฝึกที่ยังไม่รับรอง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table import_batch enable row level security;
alter table import_batch force  row level security;
create policy tenant_isolation on import_batch
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- การนำเข้าข้อมูลเป็นงานของทะเบียนและผู้ดูแลระบบ
-- ถ้าบทบาทอื่นนำเข้าได้ จะสร้างนักศึกษาปลอมเข้าระบบได้ในไฟล์เดียว
create policy import_write on import_batch
  as restrictive
  for all
  using (current_app_role() in ('registrar', 'academic', 'director', 'admin'))
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

alter table import_row enable row level security;
alter table import_row force  row level security;
create policy tenant_isolation on import_row
  using (exists (select 1 from import_batch b
                 where b.id = import_row.batch_id
                   and b.institution_id = current_institution_id()))
  with check (exists (select 1 from import_batch b
                      where b.id = import_row.batch_id
                        and b.institution_id = current_institution_id()));

alter table prior_academic_record enable row level security;
alter table prior_academic_record force  row level security;
create policy tenant_isolation on prior_academic_record
  using (student_institution(prior_academic_record.student_id) = current_institution_id())
  with check (student_institution(prior_academic_record.student_id) = current_institution_id());

-- นักศึกษาเห็นประวัติของตัวเอง ครูและงานทะเบียนเห็นตามหน้าที่
create policy prior_record_scope on prior_academic_record
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or prior_academic_record.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
               where sg.student_id = prior_academic_record.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_grades)
  );

-- อนุมัติเทียบโอนเป็นงานของฝ่ายวิชาการ ไม่ใช่ของคนที่นำเข้าไฟล์
create policy prior_record_write on prior_academic_record
  as restrictive
  for all
  using (true)
  with check (current_app_role() in ('registrar', 'academic', 'director', 'admin'));

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select, insert, update, delete
      on import_batch, import_row, prior_academic_record to app_runtime;
  end if;
end $$;

commit;

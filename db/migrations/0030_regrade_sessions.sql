-- ═══════════════════════════════════════════════════════════════════
-- 0030_regrade_sessions.sql
--
-- รอบสอบซ่อมและเรียนปรับเกรด
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- ระบบมี enrollment.attempt_no (เรียนซ้ำได้) และ grade_change_request
-- (แก้เกรดได้) อยู่แล้ว แต่ **ไม่มีตัวคุมรอบ** — ไม่มีที่บอกว่ารอบนี้เปิด
-- วิชาไหน ใครมีสิทธิ์เข้า และปิดรับเมื่อไร
--
-- ผลคือทุกอย่างขึ้นกับความจำของเจ้าหน้าที่ ซึ่งพังในสองทางที่เจ็บทั้งคู่ —
-- นักศึกษาที่ไม่มีสิทธิ์เข้าสอบซ่อมได้เพราะไม่มีใครตรวจ และนักศึกษาที่มีสิทธิ์
-- ตกหล่นเพราะไม่มีรายชื่อกลาง กว่าจะรู้ก็จบภาคเรียนไปแล้ว
--
-- ─── ทำไมสิทธิ์เข้าสอบซ่อมต้องคำนวณ ไม่ใช่ให้เจ้าหน้าที่พิมพ์รายชื่อเอง ───
-- คำถามว่า "ใครมีสิทธิ์" มีคำตอบที่ตายตัวอยู่แล้วในข้อมูล — คนที่ลงวิชานี้
-- และผลปัจจุบันยังไม่ได้หน่วยกิต ถ้าให้พิมพ์รายชื่อเอง รายชื่อจะคลาดเคลื่อน
-- ทุกครั้งที่มีการแก้เกรดหลังจากพิมพ์ และไม่มีใครรู้ว่าคลาดเคลื่อน
--
-- regrade_eligible() จึงคำนวณให้ และการลงทะเบียนตรวจซ้ำอีกชั้นตอนเขียนจริง
--
-- ─── ทำไมผลสอบซ่อมไม่เขียนเกรดตรง ๆ ───
-- เกรดในระบบนี้เปลี่ยนได้ทางเดียวคือผ่าน grade_change_request ซึ่งมี
-- dual control (ผู้ยื่นอนุมัติเองไม่ได้) และทิ้ง revision ไว้ให้ตรวจสอบ
-- ถ้าเปิดทางที่สองให้รอบสอบซ่อมเขียนเกรดได้เอง กฎนั้นจะหายไปทันที
-- และจะกลายเป็นช่องที่ใช้แก้เกรดโดยไม่ต้องผ่านใครเลย เพียงแค่สร้าง
-- "รอบสอบซ่อม" ขึ้นมาหนึ่งรอบ
--
-- record_regrade_result() จึงเรียก request_grade_change() ซึ่งเป็นทางเดิม
-- ไม่ได้เขียน enrollment_result เอง
--
-- ─── ทำไมการลงทะเบียนเป็นกลุ่มไม่ raise ───
-- หลักเดียวกับ register_courses_bulk (0026) — คนหนึ่งไม่มีสิทธิ์ต้องไม่ทำให้
-- อีกยี่สิบเก้าคนที่มีสิทธิ์ลงทะเบียนไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;

create type regrade_kind as enum ('retest', 'restudy');
comment on type regrade_kind is
  'retest = สอบซ่อม (สอบใหม่ในวิชาเดิม) · restudy = เรียนปรับเกรด (เรียนซ้ำทั้งวิชา)';

create type regrade_status as enum ('draft', 'open', 'closed');

create type regrade_candidate_status as enum ('registered', 'withdrawn', 'passed', 'failed');

-- ───────────────────────────────────────────────────────────────────
-- รอบสอบซ่อม/เรียนปรับเกรด
-- ───────────────────────────────────────────────────────────────────
create table regrade_session (
  id             uuid           primary key default gen_random_uuid(),
  institution_id uuid           not null references institution on delete restrict,
  term_id        uuid           not null references term on delete restrict,
  code           text           not null,
  name_th        text           not null,
  kind           regrade_kind   not null,
  -- null = เปิดให้ทุกระดับ ส่วนใหญ่วิทยาลัยแยกรอบ ปวช. กับ ปวส.
  level          qualification_level,
  opens_on       date           not null,
  closes_on      date           not null,
  status         regrade_status not null default 'draft',
  note           text,
  created_at     timestamptz    not null default now(),

  unique (institution_id, term_id, code),
  check (closes_on >= opens_on)
);

comment on table regrade_session is
  'รอบสอบซ่อมหรือเรียนปรับเกรดหนึ่งรอบ — คุมว่าเปิดวิชาไหน ใครมีสิทธิ์ และปิดรับเมื่อไร';

create index regrade_session_term_idx on regrade_session (institution_id, term_id, status);

-- ───────────────────────────────────────────────────────────────────
-- รายวิชาที่เปิดในรอบ
-- ───────────────────────────────────────────────────────────────────
create table regrade_session_course (
  id         uuid    primary key default gen_random_uuid(),
  session_id uuid    not null references regrade_session on delete cascade,
  course_id  uuid    not null references course on delete restrict,
  fee_amount numeric(9,2) not null default 0 check (fee_amount >= 0),
  capacity   smallint check (capacity is null or capacity > 0),
  created_at timestamptz not null default now(),
  unique (session_id, course_id)
);

create index regrade_session_course_session_idx on regrade_session_course (session_id);

-- ───────────────────────────────────────────────────────────────────
-- ผู้เข้ารอบ
--
-- source_enrollment_id ชี้กลับไปที่การลงทะเบียนเดิมที่ยังไม่ได้หน่วยกิต
-- เก็บไว้เพราะเวลาบันทึกผลต้องรู้ว่าจะแก้เกรดของการลงทะเบียนครั้งไหน
-- ───────────────────────────────────────────────────────────────────
create table regrade_candidate (
  id                  uuid    primary key default gen_random_uuid(),
  session_course_id   uuid    not null references regrade_session_course on delete cascade,
  student_id          uuid    not null references student on delete restrict,
  source_enrollment_id uuid   not null references enrollment on delete restrict,
  status              regrade_candidate_status not null default 'registered',
  change_request_id   uuid    references grade_change_request on delete restrict,
  registered_at       timestamptz not null default now(),
  registered_by       uuid    references person on delete restrict,
  unique (session_course_id, student_id)
);

create index regrade_candidate_student_idx on regrade_candidate (student_id);

comment on column regrade_candidate.change_request_id is
  'คำร้องแก้เกรดที่เกิดจากผลของรอบนี้ — เกรดจริงเปลี่ยนเมื่อคำร้องผ่านการอนุมัติสองชั้น ไม่ใช่ตอนบันทึกผล';

-- ───────────────────────────────────────────────────────────────────
-- ใครมีสิทธิ์เข้ารอบนี้ในวิชานี้
--
-- เงื่อนไข: เคยลงวิชานี้ และผลฉบับปัจจุบันยังไม่ได้หน่วยกิต และยังไม่เคย
-- ผ่านวิชานี้ในความพยายามครั้งไหนเลย (คนที่เรียนซ้ำแล้วผ่านไม่ต้องซ่อมอีก)
-- ───────────────────────────────────────────────────────────────────
create or replace function regrade_eligible(p_session_course_id uuid)
returns table (
  student_id     uuid,
  student_code   text,
  full_name      text,
  enrollment_id  uuid,
  grade_symbol   text,
  term_label     text
) language sql stable as $$
  with target as (
    select rsc.course_id, rs.level
      from regrade_session_course rsc
      join regrade_session rs on rs.id = rsc.session_id
     where rsc.id = p_session_course_id
  ),
  attempts as (
    select e.id as enrollment_id, e.student_id, cs.course_id,
           gsym.symbol, gsym.earns_credit,
           ay.year_be, t.ordinal
      from enrollment e
      join class_section cs      on cs.id = e.class_section_id
      join term t                on t.id  = e.term_id
      join academic_year ay      on ay.id = t.academic_year_id
      join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
      join grade_symbol gsym     on gsym.id = er.grade_symbol_id
      join target tg             on tg.course_id = cs.course_id
     where e.status = 'enrolled'
  )
  select a.student_id, s.student_code,
         trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
              || ' ' || coalesce(p.last_name_th, '')),
         a.enrollment_id, a.symbol,
         'ภาคเรียนที่ ' || a.ordinal || '/' || a.year_be
    from attempts a
    join student s on s.id = a.student_id
    join person  p on p.id = s.person_id
    join curriculum_version cv
      on cv.id = (select sc.curriculum_version_id from student_curriculum sc
                   where sc.student_id = a.student_id
                   order by sc.effective_from desc nulls last limit 1)
    join curriculum cur    on cur.id = cv.curriculum_id
    join program_track ptr on ptr.id = cur.program_track_id
    join program pr        on pr.id  = ptr.program_id
    cross join target tg
   where not a.earns_credit
     and s.status = 'active'
     and (tg.level is null or pr.level = tg.level)
     -- เคยผ่านวิชานี้แล้วในครั้งไหนก็ตาม = ไม่ต้องซ่อม
     and not exists (select 1 from attempts a2
                      where a2.student_id = a.student_id
                        and a2.course_id  = a.course_id
                        and a2.earns_credit)
   order by s.student_code;
$$;

comment on function regrade_eligible(uuid) is
  'รายชื่อผู้มีสิทธิ์เข้ารอบสอบซ่อมในวิชาหนึ่ง — คำนวณจากผลการเรียนจริง ไม่ใช่รายชื่อที่พิมพ์ไว้';

-- ───────────────────────────────────────────────────────────────────
-- ลงทะเบียนเข้ารอบเป็นกลุ่ม
--
-- คืนผลรายคนเสมอ ไม่ raise — คนที่ไม่มีสิทธิ์ต้องไม่ทำให้ทั้งกลุ่มล้ม
-- ───────────────────────────────────────────────────────────────────
create or replace function register_regrade(
  p_session_course_id uuid,
  p_student_ids       uuid[]
) returns table (
  student_id  uuid,
  registered  boolean,
  reason      text
) language plpgsql as $$
#variable_conflict use_column
declare
  v_student  uuid;
  v_status   regrade_status;
  v_opens    date;
  v_closes   date;
  v_cap      smallint;
  v_taken    integer;
  v_enroll   uuid;
begin
  select rs.status, rs.opens_on, rs.closes_on, rsc.capacity
    into v_status, v_opens, v_closes, v_cap
    from regrade_session_course rsc
    join regrade_session rs on rs.id = rsc.session_id
   where rsc.id = p_session_course_id;

  if v_status is null then
    raise exception 'ไม่พบรายวิชาที่เปิดในรอบนี้';
  end if;

  -- รอบที่ยังไม่เปิดหรือปิดไปแล้วรับคนไม่ได้ — ข้อนี้ raise ได้เพราะเป็น
  -- ปัญหาของทั้งคำขอ ไม่ใช่ของนักศึกษาคนใดคนหนึ่ง
  if v_status <> 'open' then
    raise exception 'รอบนี้ยังไม่เปิดรับหรือปิดรับไปแล้ว (สถานะ %)', v_status
      using errcode = 'check_violation';
  end if;
  if current_date < v_opens or current_date > v_closes then
    raise exception 'อยู่นอกช่วงวันที่รับสมัคร (% ถึง %)', v_opens, v_closes
      using errcode = 'check_violation';
  end if;

  foreach v_student in array coalesce(p_student_ids, '{}'::uuid[]) loop
    -- ตรวจสิทธิ์ซ้ำตอนเขียนจริง ไม่เชื่อรายชื่อที่ส่งมาจากหน้าจอ
    -- เพราะระหว่างที่หน้าจอเปิดค้างไว้ เกรดอาจถูกแก้ไปแล้ว
    select el.enrollment_id into v_enroll
      from regrade_eligible(p_session_course_id) el
     where el.student_id = v_student
     limit 1;

    if v_enroll is null then
      return query select v_student, false,
        'ไม่มีสิทธิ์เข้ารอบนี้ — ไม่พบผลการเรียนที่ยังไม่ได้หน่วยกิตในวิชานี้'::text;
      continue;
    end if;

    if exists (select 1 from regrade_candidate rc
                where rc.session_course_id = p_session_course_id
                  and rc.student_id = v_student) then
      return query select v_student, false, 'ลงทะเบียนในรอบนี้ไปแล้ว'::text;
      continue;
    end if;

    if v_cap is not null then
      select count(*) into v_taken from regrade_candidate rc
       where rc.session_course_id = p_session_course_id
         and rc.status <> 'withdrawn';
      if v_taken >= v_cap then
        return query select v_student, false,
          format('ที่นั่งเต็มแล้ว (รับได้ %s คน)', v_cap)::text;
        continue;
      end if;
    end if;

    insert into regrade_candidate
      (session_course_id, student_id, source_enrollment_id, registered_by)
    values (p_session_course_id, v_student, v_enroll, current_actor_id());

    return query select v_student, true, null::text;
  end loop;
end $$;

comment on function register_regrade(uuid, uuid[]) is
  'ลงทะเบียนเข้ารอบสอบซ่อมเป็นกลุ่ม คืนผลรายคน — คนที่ไม่มีสิทธิ์ไม่ทำให้คนอื่นล้ม';

-- ───────────────────────────────────────────────────────────────────
-- บันทึกผลของรอบ
--
-- ไม่เขียนเกรดเอง แต่ยื่นคำร้องแก้เกรดผ่านทางเดิม ซึ่งมี dual control
-- และทิ้ง revision ไว้ให้ตรวจสอบย้อนหลังได้
-- ───────────────────────────────────────────────────────────────────
create or replace function record_regrade_result(
  p_candidate_id       uuid,
  p_to_grade_symbol_id uuid,
  p_reason             text,
  p_document_no        text default null
) returns uuid language plpgsql as $$
declare
  v_enroll  uuid;
  v_earns   boolean;
  v_req     uuid;
  v_status  regrade_candidate_status;
begin
  select rc.source_enrollment_id, rc.status
    into v_enroll, v_status
    from regrade_candidate rc
   where rc.id = p_candidate_id;

  if v_enroll is null then
    raise exception 'ไม่พบผู้เข้ารอบตามรหัสที่ระบุ';
  end if;
  if v_status <> 'registered' then
    raise exception 'บันทึกผลซ้ำไม่ได้ ผู้เข้ารอบรายนี้มีผลแล้ว (%)', v_status
      using errcode = 'check_violation';
  end if;

  select gsym.earns_credit into v_earns
    from grade_symbol gsym where gsym.id = p_to_grade_symbol_id;

  if v_earns is null then
    raise exception 'ไม่พบสัญลักษณ์ผลการเรียนที่ระบุ';
  end if;

  v_req := request_grade_change(v_enroll, p_to_grade_symbol_id, p_reason, null, p_document_no);

  -- cast เอง เพราะ case ... end คืน text ไม่ใช่ enum
  update regrade_candidate
     set status = (case when v_earns then 'passed' else 'failed' end)::regrade_candidate_status,
         change_request_id = v_req
   where id = p_candidate_id;

  return v_req;
end $$;

comment on function record_regrade_result(uuid, uuid, text, text) is
  'บันทึกผลสอบซ่อมโดยยื่นคำร้องแก้เกรด — เกรดจริงเปลี่ยนเมื่อผ่านการอนุมัติสองชั้น ไม่ใช่ตอนบันทึก';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table regrade_session enable row level security;
alter table regrade_session force  row level security;
create policy tenant_isolation on regrade_session
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- ตารางลูกไม่ได้สืบทอด RLS ผ่านคีย์นอก ต้องมีนโยบายของตัวเอง
alter table regrade_session_course enable row level security;
alter table regrade_session_course force  row level security;
create policy tenant_isolation on regrade_session_course
  using (exists (select 1 from regrade_session rs
                  where rs.id = regrade_session_course.session_id
                    and rs.institution_id = current_institution_id()));

alter table regrade_candidate enable row level security;
alter table regrade_candidate force  row level security;
create policy tenant_isolation on regrade_candidate
  using (exists (select 1 from student s
                  where s.id = regrade_candidate.student_id
                    and s.institution_id = current_institution_id()));

-- ชั้นที่ 2 — นักศึกษาเห็นเฉพาะรายการของตัวเอง (restrictive จึงถูก AND)
create policy regrade_candidate_scope on regrade_candidate
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from student s
                where s.id = regrade_candidate.student_id
                  and s.person_id = current_actor_id())
  );

commit;

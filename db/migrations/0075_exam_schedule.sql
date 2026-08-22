-- ═══════════════════════════════════════════════════════════════════
-- 0075 — ตารางสอบ: จัดวัน เวลา ห้อง และกรรมการคุมสอบ
--
-- ─── ทำไมแยกตารางจาก section_timeslot ทั้งที่หน้าตาคล้ายกัน ───
-- section_timeslot คือคาบที่ **วนซ้ำทุกสัปดาห์** ตาม day_of_week ส่วนสอบ
-- เป็นเหตุการณ์**ครั้งเดียวในวันที่กำหนด** — ผสมสองแนวคิดนี้ในตารางเดียว
-- จะทำให้ครึ่งหนึ่งของคอลัมน์ไม่มีความหมายเสมอ (day_of_week ไม่มีความหมาย
-- กับสอบ ส่วน exam_date ไม่มีความหมายกับคาบเรียนปกติ)
--
-- ─── ทำไมตรวจการชนแยกจาก timeslot_conflicts()/blocked_periods() ───
-- ระบบนี้ยังไม่มีแนวคิด "สัปดาห์สอบพักการเรียนปกติ" — exam_conflicts()
-- จึงตรวจชนกับสอบวิชาอื่นเท่านั้น ไม่ตรวจกับ section_timeslot ของตาราง
-- เรียนปกติ ถ้าวันหนึ่งวิทยาลัยต้องจัดสอบทับคาบเรียนปกติจริง ต้องเพิ่ม
-- การตรวจข้ามสองตารางตอนนั้น — ไม่เดาความต้องการนี้ล่วงหน้า
--
-- ─── ทำไมแก้กำหนดการเดิมด้วย update ได้ ไม่ใช่ออกฉบับใหม่แบบ enrollment_result ───
-- ตารางสอบเป็นข้อมูลโลจิสติกส์ของการจัดงาน ไม่ใช่หลักฐานผลการเรียน — เลื่อน
-- ห้องสอบตอนเช้าของวันสอบเป็นเรื่องปกติ ไม่มีใครต้องอนุมัติหรือสอบย้อนกลับ
-- ว่าใครเคยเห็นกำหนดการเดิม (ต่างจาก enrollment_result ตามหลักข้อ 4)
-- ═══════════════════════════════════════════════════════════════════

create type exam_kind as enum ('midterm', 'final');

create table exam_session (
  id                uuid primary key default gen_random_uuid(),
  institution_id    uuid not null references institution(id) on delete restrict,
  class_section_id  uuid not null references class_section(id) on delete restrict,
  kind              exam_kind not null default 'final',
  exam_date         date not null,
  period_from       smallint not null,
  period_to         smallint not null,
  room_id           uuid references room(id) on delete restrict,
  note              text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (class_section_id, kind),
  check (period_from between 1 and 20),
  check (period_to >= period_from and period_to <= 20)
);

comment on table exam_session is
  'ตารางสอบ — หนึ่งกลุ่มเรียนสอบกลางภาคได้หนึ่งครั้งและปลายภาคได้หนึ่งครั้ง แก้กำหนดการเดิมด้วย update ได้เพราะเป็นโลจิสติกส์ ไม่ใช่หลักฐานผลการเรียน';

-- ห้องสอบชนกันเป็นข้อจำกัดที่แน่นอน (ห้องเดียวอยู่สองที่พร้อมกันไม่ได้จริง ๆ)
-- จึงบังคับด้วย exclusion constraint ไม่ใช่แค่ตรวจตอน insert เหมือน section_timeslot
alter table exam_session add constraint exam_session_room_no_overlap
  exclude using gist (
    room_id with =,
    exam_date with =,
    int4range(period_from::integer, period_to::integer, '[]') with &&
  ) where (room_id is not null);

create table exam_proctor (
  id               uuid primary key default gen_random_uuid(),
  exam_session_id  uuid not null references exam_session(id) on delete cascade,
  staff_id         uuid not null references staff(id) on delete restrict,
  created_at       timestamptz not null default now(),
  unique (exam_session_id, staff_id)
);

comment on table exam_proctor is
  'กรรมการคุมสอบของการสอบหนึ่งครั้ง — ไม่แยกบทบาทหัวหน้าห้องสอบ/กรรมการ เพิ่มทีหลังได้เมื่อมีวิทยาลัยต้องการจริง';

create index exam_session_date_idx on exam_session (institution_id, exam_date);
create index exam_proctor_staff_idx on exam_proctor (staff_id);

-- ── ฟังก์ชันตัดวงจร RLS ระหว่าง exam_session ↔ exam_proctor ────────
--
-- exam_session ต้องรู้ว่า "ผู้ใช้คนนี้เป็นกรรมการคุมสอบของการสอบนี้ไหม" เพื่อ
-- ให้กรรมการอ่านตารางสอบที่ตัวเองต้องคุมได้ ซึ่งต้องอ่าน exam_proctor —
-- แต่ exam_proctor เองก็ต้องอ่าน exam_session (ผ่าน class_section) เพื่อรู้ว่า
-- ผู้ใช้เป็นครูของวิชานั้นไหม ถ้าให้นโยบายของทั้งสองตารางอ้างกันตรง ๆ จะเกิด
-- infinite recursion แบบเดียวกับ student ↔ student_guardian ก่อน 0012 — ตัดวงจร
-- ด้วย security definer ที่นี่ (อ่าน exam_proctor แบบข้าม RLS) แล้วให้ฝั่ง
-- exam_proctor เป็นฝ่ายเดียวที่ join เข้า exam_session ตรง ๆ ได้ (ทางเดียว)
create function current_actor_is_exam_proctor(p_exam_session_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from exam_proctor ep
      join staff st on st.id = ep.staff_id
     where ep.exam_session_id = p_exam_session_id
       and st.person_id = current_actor_id()
  )
$$;

comment on function current_actor_is_exam_proctor(uuid) is
  'ตัดวงจร RLS ระหว่าง exam_session กับ exam_proctor — อ่าน exam_proctor แบบข้าม RLS เจตนา';

alter table exam_session enable row level security;
alter table exam_session force row level security;
alter table exam_proctor enable row level security;
alter table exam_proctor force row level security;

create policy tenant_isolation on exam_session
  as permissive for all
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- อ่านได้กว้างกว่าเขียน — บทบาทงานวิชาการเห็นทั้งวิทยาลัย ครูเห็นวิชาที่ตัวเอง
-- สอน นักศึกษา/ผู้ปกครองที่ยืนยันแล้วเห็นวิชาที่ลงทะเบียนอยู่ กรรมการคุมสอบ
-- เห็นห้องสอบที่ตัวเองต้องไปคุม
create policy exam_session_read_scope on exam_session
  as restrictive for select
  using (
    is_institution_wide_role()
    or exists (
      select 1 from class_section cs
        join staff st on st.id = cs.teacher_id
       where cs.id = exam_session.class_section_id
         and st.person_id = current_actor_id()
    )
    or exists (
      select 1 from enrollment e
       where e.class_section_id = exam_session.class_section_id
         and e.student_id in (select actor_student_ids())
    )
    or current_actor_is_exam_proctor(exam_session.id)
  );

create policy academic_insert on exam_session
  as restrictive for insert
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_update on exam_session
  as restrictive for update
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_delete on exam_session
  as restrictive for delete
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy tenant_isolation on exam_proctor
  as permissive for all
  using (exists (
    select 1 from exam_session es
     where es.id = exam_proctor.exam_session_id
       and es.institution_id = current_institution_id()
  ))
  with check (exists (
    select 1 from exam_session es
     where es.id = exam_proctor.exam_session_id
       and es.institution_id = current_institution_id()
  ));

-- exam_proctor เป็นฝ่ายเดียวที่ join เข้า exam_session ตรง ๆ ได้ — exam_session
-- เรียก current_actor_is_exam_proctor() แทน (ดูคอมเมนต์ของฟังก์ชันด้านบน)
create policy exam_proctor_read_scope on exam_proctor
  as restrictive for select
  using (
    is_institution_wide_role()
    or exists (
      select 1 from staff st
       where st.id = exam_proctor.staff_id
         and st.person_id = current_actor_id()
    )
    or exists (
      select 1 from exam_session es
        join class_section cs on cs.id = es.class_section_id
        join staff st2 on st2.id = cs.teacher_id
       where es.id = exam_proctor.exam_session_id
         and st2.person_id = current_actor_id()
    )
  );

create policy academic_insert on exam_proctor
  as restrictive for insert
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_update on exam_proctor
  as restrictive for update
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
  with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

create policy academic_delete on exam_proctor
  as restrictive for delete
  using (current_app_role() in ('academic', 'registrar', 'director', 'admin'));

-- ── ตรวจการชนก่อนบันทึก — เรียกจากชั้น API ก่อน insert/update เสมอ ─────
--
-- รูปแบบเดียวกับ timeslot_conflicts(): คืนแถวละหนึ่งปัญหาพร้อมข้อความไทย
-- ให้ผู้ใช้ตัดสินใจต่อ ไม่ raise exception เอง เพราะบางกรณี (เช่นกรรมการ
-- คุมสอบชนแค่บางคนในหลายคน) ผู้ใช้อาจต้องการเห็นทั้งหมดแล้วแก้ทีเดียว
create function exam_conflicts(
  p_class_section_id  uuid,
  p_exam_date         date,
  p_period_from       smallint,
  p_period_to         smallint,
  p_room_id           uuid default null,
  p_proctor_ids       uuid[] default null,
  p_ignore_session_id uuid default null
) returns table(kind text, message_th text)
language sql stable as $$
  with me as materialized (
    select cs.institution_id
      from class_section cs
     where cs.id = p_class_section_id
  ),
  others as materialized (
    select es.id, es.room_id, es.class_section_id,
           c.code as course_code, c.name_th as course_name
      from exam_session es
      join class_section cs2 on cs2.id = es.class_section_id
      join course c on c.id = cs2.course_id
      cross join me
     where cs2.institution_id = me.institution_id
       and es.exam_date = p_exam_date
       and int4range(es.period_from::integer, es.period_to::integer, '[]')
           && int4range(p_period_from::integer, p_period_to::integer, '[]')
       and (p_ignore_session_id is null or es.id <> p_ignore_session_id)
  )
  select 'room'::text,
         'ห้องนี้ถูกใช้สอบ ' || o.course_code || ' ' || o.course_name || ' ในวันและช่วงเวลาเดียวกัน'
    from others o
   where p_room_id is not null and o.room_id = p_room_id

  union all
  select 'proctor',
         'กรรมการคุมสอบติดคุมสอบ ' || o.course_code || ' ' || o.course_name || ' ในวันและช่วงเวลาเดียวกัน'
    from others o
   where p_proctor_ids is not null and cardinality(p_proctor_ids) > 0
     and exists (
       select 1 from exam_proctor ep
        where ep.exam_session_id = o.id and ep.staff_id = any (p_proctor_ids)
     )

  union all
  select 'enrolled',
         'มีนักศึกษาที่ลงทะเบียนทั้งวิชานี้และ ' || o.course_code || ' สอบชนกันอยู่แล้ว'
    from others o
   where exists (
     select 1
       from enrollment e1
      where e1.class_section_id = p_class_section_id
        and exists (
          select 1 from enrollment e2
           where e2.class_section_id = o.class_section_id
             and e2.student_id = e1.student_id
        )
   )
$$;

comment on function exam_conflicts(uuid, date, smallint, smallint, uuid, uuid[], uuid) is
  'ตรวจห้องสอบ/กรรมการคุมสอบ/นักศึกษาชนกันก่อนบันทึกตารางสอบ — ไม่ตรวจกับ section_timeslot ของตารางเรียนปกติ (ดูคอมเมนต์หัวไฟล์)';

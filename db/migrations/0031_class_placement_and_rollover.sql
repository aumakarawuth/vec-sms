-- ═══════════════════════════════════════════════════════════════════
-- 0031_class_placement_and_rollover.sql
--
-- ชั้นปี/ห้องเรียนของนักศึกษา และการเลื่อนชั้นปีการศึกษา
--
-- ─── ช่องว่างที่พบตอนเทียบกับระบบที่วิทยาลัยใช้อยู่ ───
-- ระบบนั้นมี "ประเภทวิชา / สาขา / ชั้นเรียน / ห้องเรียน" เป็นข้อมูลหลัก
-- และมีเมนู "จัดห้องเรียน" กับ "เลื่อนชั้นปีการศึกษา" ที่ใช้ทุกปี
--
-- ของเราไม่มี **ชั้นปี** อยู่ที่ไหนเลย — ตาราง student มีแค่ปีที่เข้าศึกษา
-- ส่วนห้องเป็นข้อความอิสระใน class_section.section_no ซึ่งเป็นห้องของ
-- รายวิชา ไม่ใช่ห้องประจำของนักศึกษา
--
-- ที่เจ็บกว่านั้นคือ fee_schedule.study_year มีอยู่แล้วตั้งแต่ 0010 —
-- ระบบการเงินตั้งค่าเทอมตามชั้นปีได้ แต่ **ไม่มีทางรู้ว่านักศึกษาคนไหน
-- อยู่ชั้นปีอะไร** จึงจับคู่ไม่ได้จริง เป็นข้อมูลที่ออกแบบไว้แล้วใช้ไม่ได้
-- แบบเดียวกับ entry_pathway ก่อน 0026
--
-- ─── ทำไมชั้นปีอยู่ในตารางแยกที่ผูกกับปีการศึกษา ───
-- ทางที่ง่ายกว่าคือใส่คอลัมน์ study_year ลงในตาราง student ตรง ๆ แต่ทำ
-- แบบนั้นแล้วจะตอบไม่ได้ว่า "ปีการศึกษา 2568 คนนี้อยู่ชั้นปีอะไร ห้องไหน"
-- ซึ่งเป็นคำถามที่ต้องตอบทุกครั้งที่ออกเอกสารย้อนหลังหรือตรวจสอบข้อมูลเก่า
-- และการเลื่อนชั้นจะกลายเป็นการเขียนทับค่าเดิม ทำให้ประวัติหายไปทุกปี
--
-- ─── ทำไมไม่เก็บหลักสูตรซ้ำในตารางนี้ ───
-- student_curriculum ตอบอยู่แล้วว่านักศึกษาสังกัดหลักสูตรฉบับไหนช่วงไหน
-- ถ้าเก็บซ้ำที่นี่ด้วย วันหนึ่งสองที่จะไม่ตรงกันแล้วไม่มีใครรู้ว่าอันไหนจริง
--
-- ─── ทำไมการเลื่อนชั้นคืนผลรายคน ไม่ raise ───
-- หลักเดียวกับ register_courses_bulk (0026) และ register_regrade (0030) —
-- การเลื่อนชั้นทำกับนักศึกษาทั้งวิทยาลัยพร้อมกัน ถ้ามีคนหนึ่งเรียนเกิน
-- เวลาที่หลักสูตรกำหนดแล้ว raise ทั้งงานจะ rollback แล้วอีกสองพันคน
-- ไม่ได้เลื่อนชั้นไปด้วย งานทะเบียนจะติดตายทั้งวิทยาลัยเพราะคนคนเดียว
--
-- ─── ทำไมไม่สร้างปีการศึกษาปลายทางให้เอง ───
-- ปีการศึกษามีวันเปิด-ปิดและภาคเรียนที่ต้องตัดสินใจ ไม่ใช่ข้อมูลที่คัดลอก
-- มาได้ ถ้าสร้างให้เองด้วยการเดาวันที่ จะได้ปฏิทินที่ผิดโดยไม่มีใครทักท้วง
-- แล้วกำหนดส่งเกรดกับวันสุดท้ายของการถอนรายวิชาจะผิดตามไปทั้งปี
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ชั้นปีและห้องประจำของนักศึกษาในแต่ละปีการศึกษา
-- ───────────────────────────────────────────────────────────────────
create table student_class_placement (
  id               uuid        primary key default gen_random_uuid(),
  institution_id   uuid        not null references institution on delete restrict,
  student_id       uuid        not null references student on delete restrict,
  academic_year_id uuid        not null references academic_year on delete restrict,
  study_year       smallint    not null check (study_year between 1 and 6),
  group_code       text,
  note             text,
  created_at       timestamptz not null default now(),

  -- ปีการศึกษาหนึ่งนักศึกษาคนหนึ่งอยู่ชั้นปีเดียว
  unique (student_id, academic_year_id)
);

comment on table student_class_placement is
  'ชั้นปีและห้องประจำของนักศึกษาในปีการศึกษาหนึ่ง — เก็บแยกรายปีเพื่อให้ตอบย้อนหลังได้ว่าปีนั้นอยู่ชั้นไหน';
comment on column student_class_placement.study_year is
  'ชั้นปี 1-6 · ใช้จับคู่กับ fee_schedule.study_year เพื่อคิดค่าเทอมตามชั้นปี';
comment on column student_class_placement.group_code is
  'ห้องประจำ เช่น 1/1 — ต่างจาก class_section.section_no ซึ่งเป็นห้องของรายวิชา';

create index student_class_placement_year_idx
  on student_class_placement (institution_id, academic_year_id, study_year);
create index student_class_placement_student_idx
  on student_class_placement (student_id);

-- ───────────────────────────────────────────────────────────────────
-- บันทึกการเลื่อนชั้นปีการศึกษา
--
-- ต้องรู้ย้อนหลังได้ว่าใครกดเลื่อนเมื่อไร และผลเป็นอย่างไร เพราะเป็น
-- งานที่ทำปีละครั้งและกระทบทุกคน คนที่มาถามทีหลังว่า "ทำไมคนนี้ไม่ถูก
-- เลื่อนชั้น" ต้องหาคำตอบได้โดยไม่ต้องเดา
-- ───────────────────────────────────────────────────────────────────
create table rollover_log (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  from_year_be   smallint    not null,
  to_year_be     smallint    not null,
  summary        jsonb       not null,
  ran_at         timestamptz not null default now(),
  ran_by         uuid        references person on delete restrict
);

comment on table rollover_log is
  'ประวัติการเลื่อนชั้นปีการศึกษา — ตอบได้ว่าใครกดเมื่อไร เลื่อนไปกี่คน และใครตกหล่นเพราะอะไร';

-- ───────────────────────────────────────────────────────────────────
-- เลื่อนชั้นปีการศึกษา
--
-- คืนหนึ่งแถวต่อนักศึกษาหนึ่งคนเสมอ รวมถึงคนที่ไม่ถูกเลื่อนและเหตุผล
-- ───────────────────────────────────────────────────────────────────
create or replace function rollover_students(
  p_from_year_be smallint,
  p_to_year_be   smallint
) returns table (
  student_id  uuid,
  action      text,
  study_year  smallint,
  note        text
) language plpgsql as $$
#variable_conflict use_column
declare
  v_inst    uuid := current_institution_id();
  v_from_ay uuid;
  v_to_ay   uuid;
  r         record;
  v_next    smallint;
  v_max     smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;
  if p_to_year_be <= p_from_year_be then
    raise exception 'ปีปลายทาง (%) ต้องมากกว่าปีต้นทาง (%)', p_to_year_be, p_from_year_be;
  end if;

  select id into v_from_ay from academic_year
   where institution_id = v_inst and year_be = p_from_year_be;
  select id into v_to_ay   from academic_year
   where institution_id = v_inst and year_be = p_to_year_be;

  if v_from_ay is null then
    raise exception 'ไม่พบปีการศึกษา % ในสถานศึกษานี้', p_from_year_be;
  end if;
  if v_to_ay is null then
    raise exception 'ยังไม่ได้สร้างปีการศึกษา % — ต้องสร้างพร้อมกำหนดวันเปิด-ปิดก่อนจึงจะเลื่อนชั้นได้',
      p_to_year_be;
  end if;

  for r in
    select s.id,
           scp.study_year as current_year,
           -- จำนวนภาคเรียนปกติของหลักสูตร แปลงเป็นจำนวนชั้นปี
           -- (ภาคฤดูร้อนไม่นับเป็นชั้นปี จึงหารสอง)
           coalesce(ceil(cv.normal_duration_terms / 2.0), 3)::smallint as max_year
      from student s
      join student_class_placement scp
        on scp.student_id = s.id and scp.academic_year_id = v_from_ay
      left join lateral (
        select sc.curriculum_version_id
          from student_curriculum sc
         where sc.student_id = s.id
         order by sc.effective_from desc nulls last
         limit 1
      ) cur on true
      left join curriculum_version cv on cv.id = cur.curriculum_version_id
     where s.institution_id = v_inst
     order by s.student_code
  loop
    -- มีที่อยู่ในปีปลายทางแล้ว — ไม่เขียนทับ เพื่อให้กดซ้ำได้โดยไม่เสียหาย
    if exists (select 1 from student_class_placement scp2
                where scp2.student_id = r.id and scp2.academic_year_id = v_to_ay) then
      return query select r.id, 'skipped'::text, r.current_year,
        'มีชั้นปีในปีการศึกษาปลายทางอยู่แล้ว'::text;
      continue;
    end if;

    if exists (select 1 from student_graduation sg where sg.student_id = r.id) then
      return query select r.id, 'graduated'::text, r.current_year,
        'สำเร็จการศึกษาแล้ว ไม่ต้องเลื่อนชั้น'::text;
      continue;
    end if;

    if (select status from student where id = r.id) <> 'active' then
      return query select r.id, 'inactive'::text, r.current_year,
        'สถานะไม่ใช่กำลังศึกษา'::text;
      continue;
    end if;

    v_next := r.current_year + 1;
    v_max  := r.max_year;

    -- เกินเวลาเรียนปกติของหลักสูตร ต้องให้คนตัดสินใจ ไม่ใช่เลื่อนต่อเงียบ ๆ
    if v_next > v_max then
      return query select r.id, 'exceeded'::text, r.current_year,
        format('เกินจำนวนชั้นปีปกติของหลักสูตร (%s ปี) ต้องพิจารณาเป็นรายกรณี', v_max)::text;
      continue;
    end if;

    insert into student_class_placement
      (institution_id, student_id, academic_year_id, study_year)
    values (v_inst, r.id, v_to_ay, v_next);

    return query select r.id, 'promoted'::text, v_next, null::text;
  end loop;
end $$;

comment on function rollover_students(smallint, smallint) is
  'เลื่อนชั้นปีนักศึกษาไปยังปีการศึกษาถัดไป คืนผลรายคน — คนที่เลื่อนไม่ได้ไม่ทำให้ทั้งวิทยาลัยล้ม';

-- ───────────────────────────────────────────────────────────────────
-- คัดลอกรายการชำระเงินตามระดับชั้นไปยังปีการศึกษาถัดไป
--
-- คัดลอกโครงสร้างและจำนวนเงินเดิม ให้งานการเงินไปปรับตัวเลขเอง
-- ดีกว่าให้ตั้งใหม่ทั้งหมดทุกปี ซึ่งเป็นจุดที่พิมพ์ตัวเลขผิดได้ง่ายที่สุด
-- ───────────────────────────────────────────────────────────────────
create or replace function rollover_fee_schedules(
  p_from_year_be smallint,
  p_to_year_be   smallint
) returns integer language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_from_ay uuid;
  v_to_ay   uuid;
  v_count   integer := 0;
begin
  select id into v_from_ay from academic_year
   where institution_id = v_inst and year_be = p_from_year_be;
  select id into v_to_ay   from academic_year
   where institution_id = v_inst and year_be = p_to_year_be;

  if v_from_ay is null or v_to_ay is null then
    raise exception 'ไม่พบปีการศึกษาต้นทางหรือปลายทางในสถานศึกษานี้';
  end if;

  with copied as (
    insert into fee_schedule
      (institution_id, academic_year_id, level, study_year, program_id, active)
    select fs.institution_id, v_to_ay, fs.level, fs.study_year, fs.program_id, false
      from fee_schedule fs
     where fs.institution_id = v_inst
       and fs.academic_year_id = v_from_ay
       -- ไม่คัดลอกทับของที่มีอยู่แล้ว กดซ้ำจึงไม่ทำให้ค่าเทอมซ้อนกัน
       and not exists (
         select 1 from fee_schedule t
          where t.institution_id = v_inst
            and t.academic_year_id = v_to_ay
            and t.level = fs.level
            and t.study_year is not distinct from fs.study_year
            and t.program_id is not distinct from fs.program_id)
    returning id, level, study_year, program_id
  )
  insert into fee_schedule_line (fee_schedule_id, fee_item_id, term_ordinal, amount)
  select c.id, l.fee_item_id, l.term_ordinal, l.amount
    from copied c
    join fee_schedule src
      on src.institution_id = v_inst
     and src.academic_year_id = v_from_ay
     and src.level = c.level
     and src.study_year is not distinct from c.study_year
     and src.program_id is not distinct from c.program_id
    join fee_schedule_line l on l.fee_schedule_id = src.id;

  get diagnostics v_count = row_count;
  return v_count;
end $$;

comment on function rollover_fee_schedules(smallint, smallint) is
  'คัดลอกรายการชำระเงินตามระดับชั้นไปปีถัดไป โดยยังไม่เปิดใช้ (active = false) ให้งานการเงินตรวจตัวเลขก่อน';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table student_class_placement enable row level security;
alter table student_class_placement force  row level security;
create policy tenant_isolation on student_class_placement
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

-- นักศึกษาเห็นชั้นปีของตัวเองได้ แต่ไม่เห็นรายชื่อทั้งห้องทั้งวิทยาลัย
create policy student_class_placement_scope on student_class_placement
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from student s
                where s.id = student_class_placement.student_id
                  and s.person_id = current_actor_id())
  );

alter table rollover_log enable row level security;
alter table rollover_log force  row level security;
create policy tenant_isolation on rollover_log
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy rollover_log_scope on rollover_log
  as restrictive using (is_institution_wide_role());

commit;

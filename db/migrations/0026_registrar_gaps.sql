-- ═══════════════════════════════════════════════════════════════════
-- 0026_registrar_gaps.sql
--
-- ปิดช่องว่างของงานทะเบียนและงานวิชาการที่พบตอนเทียบกับระบบที่วิทยาลัย
-- ใช้งานจริงอยู่ (SISA) สี่เรื่อง ทุกเรื่องเป็นงานที่งานทะเบียนทำทุกภาคเรียน
--
-- ─── 1. ภาคเรียนปรับพื้นฐาน ───
-- term_kind เดิมมีแค่ regular กับ summer ทั้งที่วิทยาลัยอาชีวศึกษารับ
-- นักศึกษาที่จบมาจากคนละสายและคนละสถานศึกษาเข้ามาปนกันในห้องเดียวกัน
-- จึงต้องเปิด "ภาคเรียนปรับพื้นฐาน" ก่อนภาคเรียนที่ 1 เพื่อปรับพื้นให้เท่ากัน
--
-- ระบบนี้มี entry_pathway และ pathway_bridging_course อยู่แล้ว คือรู้ว่า
-- ใครมาจากทางไหนและต้องเรียนปรับพื้นวิชาอะไรบ้าง แต่ **ไม่มีภาคเรียนให้ลง**
-- ผลคือข้อมูลที่ออกแบบไว้ดีแล้วใช้จริงไม่ได้เลย
--
-- ordinal ของภาคเรียนปรับพื้นฐานใช้ 0 เพราะเรียงตาม ordinal แล้วต้องมา
-- ก่อนภาคเรียนที่ 1 ตามลำดับเวลาจริง ไม่ใช่ต่อท้ายเป็นภาคเรียนที่ 4
--
-- ─── 2. รอบเช้า/รอบบ่าย ───
-- วิทยาลัยอาชีวศึกษาเอกชนเปิดหลายรอบในหลักสูตรเดียวกันเป็นเรื่องปกติ
-- คนทำงานกลางวันเรียนรอบบ่ายหรือรอบค่ำ ระบบที่ใช้อยู่แยกเป็นหลักสูตร
-- คนละตัวไปเลย ("การบัญชี (ปวช.) - รอบเช้า" กับ "- รอบบ่าย")
--
-- ของเราพอจะใส่คำว่ารอบไว้ในชื่อ curriculum ได้เหมือนกัน แต่ชื่อที่เป็น
-- ข้อความเปล่า ๆ ทำให้ **นับแยกรอบไม่ได้ กรองตารางสอนตามรอบไม่ได้ และ
-- ตั้งค่าเทอมแยกรอบไม่ได้** ทั้งที่สามอย่างนี้คืองานประจำของงานทะเบียน
-- จึงยกขึ้นมาเป็นคอลัมน์ที่ query ได้
--
-- วางไว้ที่ curriculum ไม่ใช่ class_section เพราะรอบเป็นคุณสมบัติของ
-- หลักสูตรที่นักศึกษาสังกัด ไม่ใช่ของห้องเรียนรายวิชา — class_section
-- ชี้ไป curriculum_version อยู่แล้ว จึงหารอบได้ด้วยการ join ไม่ต้องเก็บซ้ำ
-- (เก็บซ้ำสองที่แล้วไม่ตรงกันคือปัญหาที่แก้ยากกว่าการ join)
--
-- ─── 3. ลงทะเบียนทั้งห้อง ───
-- register_courses() รับนักศึกษาทีละคน ซึ่งใช้ไม่ได้จริงกับวิทยาลัยที่มี
-- นักศึกษาสองพันคน งานทะเบียนลงทะเบียนเป็น "ทั้งห้อง" ไม่ใช่ทีละคน
--
-- ข้อสำคัญคือฟังก์ชันนี้ **ห้าม raise เมื่อมีคนติดเงื่อนไข** เพราะการ raise
-- จะ rollback ทั้ง transaction ผลคือคนที่ผ่านเงื่อนไขอีกสามสิบเก้าคนไม่ได้
-- ลงทะเบียนไปด้วย เพียงเพราะมีคนหนึ่งค้างค่าเทอม — งานทะเบียนจะติดตาย
-- ทั้งห้องโดยแก้อะไรไม่ได้จนกว่าคนนั้นจะไปจ่ายเงิน
--
-- จึงคืน "ผลรายคน" ออกมาแทน ใครผ่านลงให้เลย ใครติดบอกว่าติดอะไร
-- หลักเดียวกับ check_registration() ที่คืนรายการปัญหาแทน true/false
-- และหลักเดียวกับ login_rate_status() ที่คืนสถานะให้ชั้น API ตัดสินใจเอง
--
-- ─── 4. รายงานคุมงานของงานทะเบียน ───
-- ข้อมูลสองชุดนี้มีอยู่ในฐานข้อมูลครบแล้ว แต่ไม่มีใครรวมให้ดู
--
--   grade_cutoff_progress()  ครูคนไหนยังไม่ส่งเกรดกี่วิชา — เปิดดูก่อนถึง
--                            กำหนดส่งเกรดทุกครั้ง ไม่มีตัวนี้ก็ต้องไล่ถาม
--                            ทีละคนซึ่งไม่มีใครทำจริง แล้วไปรู้ตอนเลยกำหนด
--   registration_progress()  หลักสูตรไหนลงทะเบียนไปแล้วกี่เปอร์เซ็นต์ —
--                            ใช้จับห้องที่ตกหล่นก่อนหมดเวลาเพิ่ม-ถอน
--
-- ทั้งคู่ **ไม่ใช่ security definer** โดยตั้งใจ ต้องถูก RLS กรองตามสิทธิ์
-- ของคนเรียกเหมือนการอ่านตารางตรง ๆ มิฉะนั้นรายงานจะกลายเป็นทางลัด
-- ที่เห็นข้อมูลข้ามวิทยาลัยได้
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- 1. ภาคเรียนปรับพื้นฐาน
-- ───────────────────────────────────────────────────────────────────

-- หมายเหตุ: ห้ามอ้างถึงค่า 'bridging' ที่เพิ่งเพิ่มในไฟล์นี้อีก
-- PostgreSQL ปฏิเสธการใช้ค่า enum ใหม่ใน transaction เดียวกับที่เพิ่มมัน
-- ("unsafe use of new value of enum type") จึงเขียนกฎที่อ้างค่านี้ไม่ได้
-- จนกว่าจะ commit — เงื่อนไข ordinal ข้างล่างจึงคุมด้วยช่วงตัวเลขล้วน
alter type term_kind add value if not exists 'bridging';

alter table term drop constraint if exists term_ordinal_check;
alter table term add constraint term_ordinal_check check (ordinal between 0 and 3);

comment on column term.ordinal is
  '0 = ภาคเรียนปรับพื้นฐาน (มาก่อนภาคเรียนที่ 1) · 1-2 = ภาคเรียนปกติ · 3 = ภาคฤดูร้อน';

-- ───────────────────────────────────────────────────────────────────
-- 2. รอบเรียน
-- ───────────────────────────────────────────────────────────────────
create type class_shift as enum ('morning', 'afternoon', 'evening', 'weekend');

comment on type class_shift is
  'รอบเรียนของหลักสูตร — เช้า บ่าย ค่ำ และรอบวันหยุด (เรียนเสาร์-อาทิตย์)';

-- ค่าเริ่มต้นเป็นรอบเช้าเพราะหลักสูตรที่มีอยู่ก่อน migration นี้เป็นรอบเช้า
-- ทั้งหมด และเพราะการปล่อยให้เป็น null จะทำให้หลักสูตรหายไปจากรายงาน
-- ที่นับแยกรอบโดยไม่มีใครสังเกต — ค่าที่ผิดแต่มองเห็นแก้ได้ ค่าที่หายเงียบแก้ไม่ได้
alter table curriculum add column if not exists shift class_shift not null default 'morning';

comment on column curriculum.shift is
  'รอบเรียน — นักศึกษาสังกัดรอบผ่านหลักสูตร ส่วน class_section หารอบได้โดย join ผ่าน curriculum_version';

create index if not exists curriculum_shift_idx on curriculum (institution_id, shift);

-- ───────────────────────────────────────────────────────────────────
-- 3. ลงทะเบียนเป็นกลุ่ม
--
-- คืนหนึ่งแถวต่อนักศึกษาหนึ่งคนเสมอ แม้คนนั้นจะลงไม่ได้ เพื่อให้หน้าจอ
-- แสดงได้ว่าใครผ่านใครไม่ผ่านโดยไม่ต้องเรียกซ้ำอีกรอบ
-- ───────────────────────────────────────────────────────────────────
create or replace function register_courses_bulk(
  p_student_ids uuid[],
  p_term_id     uuid,
  p_section_ids uuid[]
) returns table (
  student_id uuid,
  registered integer,
  blockers   text
) language plpgsql as $$
-- ชื่อคอลัมน์ที่คืนออกไป (student_id) ซ้ำกับชื่อคอลัมน์ใน enrollment
-- plpgsql จึงไม่รู้ว่า on conflict (student_id, ...) หมายถึงตัวแปรหรือคอลัมน์
-- แล้วล้มด้วย "column reference is ambiguous" — สั่งให้ตีความเป็นคอลัมน์เสมอ
-- และคืนค่าด้วย return query แทนการกำหนดค่าให้ตัวแปร OUT ทีละตัว
#variable_conflict use_column
declare
  v_student  uuid;
  v_blockers text;
  v_count    integer;
begin
  foreach v_student in array coalesce(p_student_ids, '{}'::uuid[]) loop
    select string_agg(format('[%s] %s', code, message_th), E'\n')
      into v_blockers
    from check_registration(v_student, p_term_id, p_section_ids)
    where severity = 'block' and not waived;

    if v_blockers is not null then
      -- ไม่ raise โดยตั้งใจ — คนที่เหลือในห้องต้องลงทะเบียนได้ต่อ
      return query select v_student, 0, v_blockers;
      continue;
    end if;

    insert into enrollment (student_id, class_section_id, term_id, attempt_no, registered_by)
    select v_student, cs.id, p_term_id,
           1 + (select count(*)
                from enrollment e
                join class_section cs2 on cs2.id = e.class_section_id
                where e.student_id = v_student
                  and cs2.course_id = cs.course_id
                  and e.status in ('enrolled', 'withdrawn')),
           current_actor_id()
    from unnest(coalesce(p_section_ids, '{}'::uuid[])) sid
    join class_section cs on cs.id = sid
    on conflict (student_id, class_section_id) do nothing;

    get diagnostics v_count = row_count;

    return query select v_student, v_count, null::text;
  end loop;
end $$;

comment on function register_courses_bulk(uuid[], uuid, uuid[]) is
  'ลงทะเบียนหลายคนพร้อมกัน คืนผลรายคน — คนที่ติดเงื่อนไขไม่ทำให้คนอื่นในกลุ่มล้มไปด้วย';

-- ───────────────────────────────────────────────────────────────────
-- 4ก. ความคืบหน้าการตัดเกรดรายครู
--
-- นับจากห้องเรียนรายวิชาที่ครูคนนั้นเป็นผู้สอนในภาคเรียนที่ระบุ
-- "ส่งแล้ว" หมายถึงผ่านมือครูไปแล้ว — draft และ returned ยังไม่นับ
-- เพราะ returned คือถูกตีกลับมาให้แก้ ซึ่งงานยังอยู่ที่ครูคนเดิม
-- ───────────────────────────────────────────────────────────────────
create or replace function grade_cutoff_progress(p_term_id uuid)
returns table (
  teacher_id     uuid,
  teacher_name   text,
  sections_total integer,
  submitted      integer,
  remaining      integer,
  grade_due_on   date,
  is_overdue     boolean
) language sql stable as $$
  select
    cs.teacher_id,
    -- coalesce ทุกชิ้น เพราะต่อสตริงกับ null ได้ null ทั้งก้อน
    trim(coalesce(p.first_name_th, '') || ' ' || coalesce(p.last_name_th, '')) as teacher_name,
    count(*)::integer,
    count(*) filter (
      where gs.stage is not null and gs.stage not in ('draft', 'returned')
    )::integer,
    count(*) filter (
      where gs.stage is null or gs.stage in ('draft', 'returned')
    )::integer,
    t.grade_due_on,
    (t.grade_due_on is not null
     and current_date > t.grade_due_on
     and count(*) filter (
           where gs.stage is null or gs.stage in ('draft', 'returned')
         ) > 0)
  from class_section cs
  join term t on t.id = cs.term_id
  left join grade_submission gs on gs.class_section_id = cs.id
  left join staff  st on st.id = cs.teacher_id
  left join person p  on p.id  = st.person_id
  where cs.term_id = p_term_id
    and cs.teacher_id is not null
  group by cs.teacher_id, p.first_name_th, p.last_name_th, t.grade_due_on
  order by 5 desc, 2;
$$;

comment on function grade_cutoff_progress(uuid) is
  'ครูแต่ละคนสอนกี่ห้อง ส่งเกรดแล้วกี่ห้อง เหลือกี่ห้อง — งานทะเบียนใช้ไล่ตามก่อนถึงกำหนดส่ง';

-- ───────────────────────────────────────────────────────────────────
-- 4ข. ความคืบหน้าการลงทะเบียนรายหลักสูตร
--
-- ตัวหารคือนักศึกษาที่ยัง active และสังกัดหลักสูตรนั้นอยู่ ณ วันที่เรียก
-- ไม่ใช่ทุกคนที่เคยสังกัด — มิฉะนั้นคนที่ลาออกไปแล้วจะทำให้ทุกหลักสูตร
-- ค้างอยู่ที่เก้าสิบกว่าเปอร์เซ็นต์ตลอดกาลและรายงานจะไร้ประโยชน์
-- ───────────────────────────────────────────────────────────────────
create or replace function registration_progress(p_term_id uuid)
returns table (
  curriculum_id      uuid,
  curriculum_name    text,
  shift              class_shift,
  students_total     integer,
  students_registered integer,
  pct                numeric(5,2)
) language sql stable as $$
  with roster as (
    select c.id as curriculum_id, c.name_th, c.shift, s.id as student_id
    from student_curriculum sc
    join curriculum_version cv on cv.id = sc.curriculum_version_id
    join curriculum c          on c.id  = cv.curriculum_id
    join student s             on s.id  = sc.student_id
    where s.status = 'active'
      and (sc.effective_to is null or sc.effective_to >= current_date)
  ),
  registered as (
    select distinct e.student_id
    from enrollment e
    where e.term_id = p_term_id
      and e.status = 'enrolled'
  )
  select
    r.curriculum_id,
    r.name_th,
    r.shift,
    count(*)::integer,
    count(*) filter (where reg.student_id is not null)::integer,
    round(100.0 * count(*) filter (where reg.student_id is not null)
          / nullif(count(*), 0), 2)
  from roster r
  left join registered reg on reg.student_id = r.student_id
  group by r.curriculum_id, r.name_th, r.shift
  order by 6 nulls first, 2;
$$;

comment on function registration_progress(uuid) is
  'แต่ละหลักสูตร (แยกรอบ) ลงทะเบียนไปแล้วกี่เปอร์เซ็นต์ — ใช้จับห้องที่ตกหล่นก่อนหมดเวลาเพิ่ม-ถอน';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 0066 — เครื่องหมาย (*1)–(*5) บนใบ รบ. และรายวิชาเทียบโอนที่ไม่เคยขึ้นใบ
--
-- ═══ สองเรื่องที่ไฟล์นี้ปิด ═══
--
-- **1. คำอธิบายเครื่องหมายมีมาตั้งแต่ต้น แต่ไม่มีเครื่องหมาย**
-- `reference-data.sql` ใส่ `transcript_note_1` ถึง `transcript_note_5` ให้ครบ
-- และแม่แบบทั้ง 67 กับ 62 พิมพ์ออกมาจริงท้ายหน้า 2 แต่ค้นทั้ง repo แล้ว
-- **ไม่มีคอลัมน์ ไม่มีช่องใน payload ไม่มีโค้ดที่ใส่ (*n) ข้างรายวิชาเลย**
-- ใบจึงพิมพ์คำอธิบายของเครื่องหมายที่ไม่มีวันปรากฏ — รูปเดียวกับ
-- `can_approve_leave` (ข้อ 15) และ `take_usage_snapshot` (ข้อ 8)
--
-- **2. รายวิชาเทียบโอนถูกนับตอนตรวจจบ แต่ไม่ขึ้นใบ รบ.**
-- `evaluate_graduation()` บวก `transfer_credits_total()` เข้าหน่วยกิตสะสม
-- (0051) ส่วน `transcript_data()` กับ `transcript_courses_grouped()` อ่านจาก
-- `enrollment` อย่างเดียว — `prior_academic_record` ไม่เคยถูก join เข้ามา
-- ผลคือ **ระบบรับรองว่าจบด้วยหน่วยกิตชุดหนึ่ง แต่กระดาษแสดงอีกชุดหนึ่ง**
-- คนที่ถือใบไปยื่นจะบวกรายวิชาบนใบแล้วไม่ตรงกับหน่วยกิตรวมที่พิมพ์อยู่หัวใบ
-- และกระทบนักศึกษา ปวส. เกือบทุกคนตามที่ 0060 เขียนกำกับไว้เอง
--
-- ─── ทำไม `credit_transfer` ใน enrollment_status ใช้แทนไม่ได้ ───
-- ค่านั้นมีอยู่ในชนิดข้อมูลจริงและฟังก์ชันใบ รบ. ก็รับไว้แล้ว แต่
-- `approveTransfer()` แค่ประทับ `approved_at` ลง `prior_academic_record`
-- ไม่เคยสร้างแถว `enrollment` เลย และสร้างไม่ได้ด้วย เพราะ
-- `class_section_id` กับ `term_id` เป็น not null ส่วนวิชาที่เทียบโอนมา
-- ไม่มีกลุ่มเรียนของวิทยาลัยนี้ — จึงต้อง union เข้ามาตอนอ่าน
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. หน่วยกิตนี้ได้มาอย่างไร ──────────────────────────────────────
--
-- ─── ทำไมเป็นคอลัมน์ของ enrollment ไม่ใช่ของ course ───
-- วิชาเดียวกันคนหนึ่งเทียบโอนมา อีกคนเรียนปกติ และคนที่สามเรียนซ้ำเพื่อ
-- ปรับระดับคะแนน — เครื่องหมายจึงเป็นของ **การลงทะเบียนครั้งนั้น** เสมอ
--
-- ─── ทำไมแยกเป็น enum หนึ่งตัวกับ boolean สองตัว ───
-- (*1)(*2)(*3) ตอบคำถาม "ได้หน่วยกิตมาอย่างไร" ซึ่งเป็นได้อย่างเดียว
-- ส่วน (*4)(*5) ตอบ "เรียนที่ไหน/ภาษาอะไร" ซึ่งซ้อนกับข้อบนและกันเองได้
-- วิชาที่ฝึกในสถานประกอบการและสอนเป็นภาษาอังกฤษต้องได้ทั้ง (*4) และ (*5)
-- ถ้ายัดเป็น enum ตัวเดียวจะบังคับให้เลือกอย่างใดอย่างหนึ่งโดยไม่มีเหตุผล
create type credit_source_kind as enum (
  'studied',                 -- เรียนตามปกติ — ไม่มีเครื่องหมาย
  'transferred_grade',       -- (*1) โอนผลการเรียน
  'transferred_experience',  -- (*2) เทียบโอนความรู้และประสบการณ์
  'regraded'                 -- (*3) เรียนปรับระดับคะแนน
);

alter table enrollment
  add column credit_source       credit_source_kind not null default 'studied',
  add column taught_at_workplace boolean not null default false,  -- (*4)
  add column taught_in_english   boolean not null default false;  -- (*5)

comment on column enrollment.credit_source is
  'ที่มาของหน่วยกิต — ตัวกำหนดเครื่องหมาย (*1)(*2)(*3) บนใบ รบ.';
comment on column enrollment.taught_at_workplace is
  '(*4) เรียนหรือฝึกอาชีพในสถานประกอบการ — ซ้อนกับ credit_source ได้';
comment on column enrollment.taught_in_english is
  '(*5) จัดการเรียนการสอนเป็นภาษาอังกฤษ — ซ้อนกับทุกค่าได้';

/*
 * ─── ค่าเริ่มต้นย้อนหลังของ (*4) ───
 * แถวที่มีอยู่แล้วซึ่งกลุ่มเรียนผูกกับสถานประกอบการ ควรได้ (*4) ตั้งแต่แรก
 * ไม่ใช่รอให้คนไล่กดทีละแถว — ข้อมูลบอกอยู่แล้วว่าเรียนที่ไหน
 */
-- `dvt` คือทวิภาคี ส่วน `internship` คือฝึกงาน — ทั้งคู่คือ "เรียนหรือ
-- ฝึกอาชีพในสถานประกอบการ" ตามถ้อยคำของ (*4) ส่วน `block` เป็นวิธีจัดตาราง
-- ไม่ใช่สถานที่ จึงไม่นับ
update enrollment e
   set taught_at_workplace = true
  from class_section cs
 where cs.id = e.class_section_id
   and cs.delivery_mode in ('dvt', 'internship')
   and e.taught_at_workplace = false;

-- ── 2. วิชาเทียบโอนบอกได้ว่าเป็นแบบไหน ─────────────────────────────
--
-- ─── ทำไมต้องมีคอลัมน์ ไม่ใช่เดาจาก counts_in_gpa ───
-- ระเบียบ สอศ. ให้ "โอนผลการเรียน" ยกเกรดเดิมมาด้วย ส่วน "เทียบโอนความรู้
-- และประสบการณ์" ให้หน่วยกิตโดยไม่มีแต้ม — เดาจาก `counts_in_gpa` จึงถูก
-- เกือบทุกครั้ง แต่ "เกือบ" ไม่พอสำหรับสิ่งที่พิมพ์ลงกระดาษแล้วแก้ไม่ได้
-- และวิทยาลัยที่บันทึกเกรดเทียบโอนแบบไม่คิด GPA จะได้เครื่องหมายผิดเงียบ ๆ
-- ค่าเริ่มต้นเดาให้จากข้อมูลที่มี แล้วให้คนแก้ทีหลังได้
alter table prior_academic_record
  add column transfer_kind credit_source_kind not null default 'transferred_experience'
    check (transfer_kind in ('transferred_grade', 'transferred_experience'));

update prior_academic_record
   set transfer_kind = 'transferred_grade'
 where counts_in_gpa;

comment on column prior_academic_record.transfer_kind is
  'โอนผลการเรียน (*1) หรือเทียบโอนความรู้และประสบการณ์ (*2) — ค่าเริ่มต้นเดาจาก counts_in_gpa ตอน migrate';

-- ── 3. แปลงเป็นเลขเครื่องหมาย ───────────────────────────────────────
--
-- เขียนที่เดียวเพราะทั้งสองตระกูลใบ รบ. และทั้งสองภาษาต้องได้เลขชุดเดียวกัน
-- ถ้าปล่อยให้แต่ละฟังก์ชันแปลงเอง วันหนึ่งจะมีใบที่ (*2) แปลว่าคนละอย่าง
create or replace function transcript_note_marks(
  p_source      credit_source_kind,
  p_workplace   boolean,
  p_english     boolean
) returns smallint[] language sql immutable as $$
  select array_remove(array[
    case p_source
      when 'transferred_grade'      then 1
      when 'transferred_experience' then 2
      when 'regraded'               then 3
    end::smallint,
    case when p_workplace then 4 end::smallint,
    case when p_english   then 5 end::smallint
  ], null)
$$;

comment on function transcript_note_marks(credit_source_kind, boolean, boolean) is
  'เลขเครื่องหมาย (*1)–(*5) ที่ต้องพิมพ์ท้ายชื่อวิชาบนใบ รบ. — เรียงจากน้อยไปมากเสมอ';

/*
 * ─── ภาคที่รับรองการเทียบโอน ───
 * วิชาเทียบโอนไม่มีภาคเรียนของวิทยาลัยนี้ แต่ใบ รบ. ตระกูล 62 จัดกลุ่มตาม
 * ภาคเรียน จึงต้องรู้ว่าจะวางไว้ภาคไหน
 *
 * ใช้ **ภาคที่มีวันอนุมัติอยู่ในช่วง** ไม่ใช่ภาคของสถาบันเดิม เพราะสิ่งที่
 * ใบ รบ. ของเราแสดงคือ "วิทยาลัยนี้รับรองหน่วยกิตนี้เมื่อไร" ส่วนภาคของ
 * สถาบันเดิมเป็นข้อมูลของอีกใบหนึ่ง การเอามาปนจะทำให้ใบมีภาคเรียนที่
 * นักศึกษาไม่เคยลงทะเบียนกับเรา
 *
 * ถ้าวันอนุมัติไม่ตกในภาคไหนเลย (อนุมัติช่วงปิดภาค) ใช้ภาคแรกที่ลงทะเบียน
 * — ดีกว่าทิ้งรายวิชาหายไปจากใบ ซึ่งเป็นสภาพก่อนไฟล์นี้
 */
create or replace function transfer_recognition_term(p_student_id uuid, p_approved_at timestamptz)
returns uuid language sql stable as $$
  select coalesce(
    (select t.id
       from term t
       join academic_year ay on ay.id = t.academic_year_id
       join student s on s.id = p_student_id
      where ay.institution_id = s.institution_id
        and p_approved_at::date between t.starts_on and t.ends_on
      order by t.starts_on
      limit 1),
    (select e.term_id
       from enrollment e
       join term t on t.id = e.term_id
      where e.student_id = p_student_id
      order by t.starts_on
      limit 1)
  )
$$;

comment on function transfer_recognition_term(uuid, timestamptz) is
  'ภาคเรียนที่ใบ รบ. จะวางรายวิชาเทียบโอนไว้ — ภาคที่รับรอง ไม่ใช่ภาคของสถาบันเดิม';

-- ── 4. ตัวอ่านรายวิชาของใบ รบ. ตระกูล 62 ────────────────────────────
--
-- เขียนทับทั้งตัวเพราะ `returns table` เปลี่ยน — เพิ่ม `note_marks` และ
-- union แถวเทียบโอนเข้ามา ส่วนที่เหลือคงเดิมทุกบรรทัด
drop function if exists transcript_data(uuid);
create function transcript_data(p_student_id uuid)
returns table (
  year_be        smallint,
  term_ordinal   smallint,
  term_label     text,
  course_code    text,
  course_name_th text,
  credits        numeric(3,1),
  grade_symbol   text,
  grade_point    numeric(2,1),
  credits_earned numeric(3,1),
  category_th    text,
  term_id        uuid,
  course_name_en text,
  counts_in_gpa  boolean,
  grade_points   numeric,
  note_marks     smallint[]
) language sql stable as $$
  -- ── รายวิชาที่เรียนกับวิทยาลัยนี้ ──
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    c.code,
    c.name_th,
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    cat.name_th,
    t.id,
    coalesce(c.name_en, ''),
    (gsym.counts_in_gpa and e.counts_toward_gpa),
    case when gsym.counts_in_gpa and e.counts_toward_gpa
         then er.grade_point * c.credits end,
    transcript_note_marks(e.credit_source, e.taught_at_workplace, e.taught_in_english)
  from enrollment e
  join class_section cs      on cs.id = e.class_section_id
  join course c              on c.id  = cs.course_id
  join term t                on t.id  = e.term_id
  join academic_year ay      on ay.id = t.academic_year_id
  join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym     on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript

  union all

  /*
   * ── รายวิชาที่เทียบโอนมา ──
   *
   * เอาเฉพาะที่อนุมัติแล้ว — แถวที่ยังไม่อนุมัติคือคำขอ ไม่ใช่หน่วยกิต
   * และ `evaluate_graduation()` ก็นับเฉพาะที่อนุมัติแล้วเหมือนกัน
   * สองที่ต้องใช้เงื่อนไขเดียวกันเสมอ มิฉะนั้นใบกับการตัดสินจะไม่ตรงกันอีก
   *
   * ชื่อวิชาใช้ของรายวิชาที่แมปไว้ถ้ามี — ใบ รบ. ของเราต้องพิมพ์ชื่อวิชา
   * ตามหลักสูตรของเรา ไม่ใช่ชื่อที่สถาบันเดิมใช้เรียก
   */
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    coalesce(mc.code, pr.course_code),
    coalesce(mc.name_th, pr.course_name_th),
    pr.credits::numeric(3,1),
    pr.grade_symbol,
    pr.grade_point::numeric(2,1),
    (case when pr.earns_credit then pr.credits else 0 end)::numeric(3,1),
    cat.name_th,
    t.id,
    coalesce(mc.name_en, ''),
    pr.counts_in_gpa,
    case when pr.counts_in_gpa then pr.grade_point * pr.credits end,
    transcript_note_marks(pr.transfer_kind, false, false)
  from prior_academic_record pr
  join term t           on t.id  = transfer_recognition_term(pr.student_id, pr.approved_at)
  join academic_year ay on ay.id = t.academic_year_id
  left join course mc   on mc.id = pr.mapped_course_id
  left join curriculum_course cc
         on cc.course_id = mc.id
        -- ฉบับหลักสูตรของนักศึกษาอยู่ที่ `student_curriculum` ไม่ใช่ที่ `student`
        -- เอาฉบับที่ยังมีผลอยู่ ถ้ามีหลายแถวเลือกอันที่เริ่มล่าสุด
        and cc.curriculum_version_id = (
              select sc.curriculum_version_id
                from student_curriculum sc
               where sc.student_id = pr.student_id
               order by sc.effective_to nulls first, sc.effective_from desc
               limit 1)
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where pr.student_id = p_student_id
    and pr.approved_at is not null

  order by 1, 2, 4;
$$;

comment on function transcript_data(uuid) is
  'รายวิชาทั้งหมดที่ขึ้นระเบียนแสดงผลการเรียน รวมวิชาเทียบโอนที่อนุมัติแล้ว — grade_points คือตัวตั้งของ GPA จึงต้องคิดที่นี่ที่เดียว · note_marks คือเลข (*n) ท้ายชื่อวิชา';

-- ── 5. ตัวอ่านรายวิชาของใบ รบ. ตระกูล 67 ────────────────────────────
--
-- ─── ต่อยอดจาก 0063 ไม่ใช่จาก 0058 ───
-- รอบแรกผมคัดลอกตัวจาก 0058 มาแก้ แล้ว `plan_year_be` กับ `plan_term_ordinal`
-- ที่ 0063 เพิ่มไว้หายไปทั้งคู่ — ช่องภาคเรียนบนใบจะกลับไปพิมพ์ภาคที่ลงจริง
-- แทนภาคตามแผนโดยไม่มีอะไรฟ้อง นี่คือกับดักที่ 0059 บันทึกไว้ตรง ๆ ว่า
-- "การเขียนฟังก์ชันทับทั้งตัวเพื่อเพิ่มบรรทัดเดียวเสี่ยงและอ่านไม่ออก
-- ว่าเปลี่ยนอะไร" — เจอกับตัวเองในไฟล์ถัดมาสามไฟล์
drop function if exists transcript_courses_grouped(uuid);
create function transcript_courses_grouped(p_student_id uuid)
returns table (
  head_code   text,
  head_name   text,
  head_sort   smallint,
  head_min    numeric,
  group_code  text,
  group_name  text,
  group_sort  smallint,
  group_min   numeric,
  year_be     smallint,
  term_ordinal smallint,
  term_label  text,
  plan_year_be smallint,
  plan_term_ordinal smallint,
  plan_sort   smallint,
  course_code text,
  course_name_th text,
  course_name_en text,
  credits     numeric,
  grade_symbol text,
  grade_point numeric,
  credits_earned numeric,
  counts_in_gpa boolean,
  note_marks  smallint[]
) language sql stable as $$
  select
    coalesce(head.code, 'UNSORTED')            as head_code,
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as head_name,
    coalesce(head.sort_order, 99)::smallint    as head_sort,
    head.min_credits                           as head_min,
    coalesce(grp.code, head.code, 'UNSORTED')  as group_code,
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as group_name,
    coalesce(grp.sort_order, 0)::smallint      as group_sort,
    coalesce(grp.min_credits, head.min_credits) as group_min,
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    (s.admitted_year_be + cc.suggested_year - 1)::smallint as plan_year_be,
    cc.suggested_term                          as plan_term_ordinal,
    cc.sort_order                              as plan_sort,
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    (gsym.counts_in_gpa and e.counts_toward_gpa),
    transcript_note_marks(e.credit_source, e.taught_at_workplace, e.taught_in_english)
  from enrollment e
  join student s            on s.id  = e.student_id
  join class_section cs     on cs.id = e.class_section_id
  join course c             on c.id  = cs.course_id
  join term t               on t.id  = e.term_id
  join academic_year ay     on ay.id = t.academic_year_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym    on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where e.student_id = p_student_id

  union all

  /*
   * ── รายวิชาที่เทียบโอนมา ──
   *
   * เอาเฉพาะที่อนุมัติแล้ว — แถวที่ยังไม่อนุมัติคือคำขอ ไม่ใช่หน่วยกิต
   * และ `evaluate_graduation()` ก็นับเฉพาะที่อนุมัติแล้วเหมือนกัน
   * สองที่ต้องใช้เงื่อนไขเดียวกันเสมอ มิฉะนั้นใบกับการตัดสินจะไม่ตรงกันอีก
   *
   * ชื่อวิชาใช้ของรายวิชาที่แมปไว้ถ้ามี — ใบ รบ. ของเราต้องพิมพ์ชื่อตาม
   * หลักสูตรของเรา ไม่ใช่ชื่อที่สถาบันเดิมใช้เรียก
   *
   * ภาคตามแผนเป็น null เสมอ ตามที่ 0063 เขียนกำกับไว้แล้วว่าวิชาเทียบโอน
   * ไม่อยู่ในแผน — แม่แบบจะตกไปใช้ภาคที่รับรอง
   */
  select
    coalesce(head.code, 'UNSORTED'),
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด'),
    coalesce(head.sort_order, 99)::smallint,
    head.min_credits,
    coalesce(grp.code, head.code, 'UNSORTED'),
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด'),
    coalesce(grp.sort_order, 0)::smallint,
    coalesce(grp.min_credits, head.min_credits),
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    null::smallint,
    null::smallint,
    null::smallint,
    coalesce(mc.code, pr.course_code),
    coalesce(mc.name_th, pr.course_name_th),
    coalesce(mc.name_en, ''),
    pr.credits,
    pr.grade_symbol,
    pr.grade_point,
    case when pr.earns_credit then pr.credits else 0 end,
    pr.counts_in_gpa,
    transcript_note_marks(pr.transfer_kind, false, false)
  from prior_academic_record pr
  join term t           on t.id  = transfer_recognition_term(pr.student_id, pr.approved_at)
  join academic_year ay on ay.id = t.academic_year_id
  left join course mc   on mc.id = pr.mapped_course_id
  left join curriculum_course cc
         on cc.course_id = mc.id
        and cc.curriculum_version_id = (
              select sc.curriculum_version_id
                from student_curriculum sc
               where sc.student_id = pr.student_id
               order by sc.effective_to nulls first, sc.effective_from desc
               limit 1)
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where pr.student_id = p_student_id
    and pr.approved_at is not null
$$;

comment on function transcript_courses_grouped(uuid) is
  'รายวิชาของนักศึกษาพร้อมหมวด/กลุ่มตามหลักสูตร รวมวิชาเทียบโอนที่อนุมัติแล้ว · year_be คือภาคที่ลงจริง ส่วน plan_year_be คือภาคตามโครงสร้างหลักสูตร (null เมื่อไม่อยู่ในแผน) · note_marks คือเลข (*n)';

-- ── 6. ส่งเลขเครื่องหมายเข้า payload ────────────────────────────────
--
-- ─── ทำไมต้องอยู่ใน payload ไม่ใช่ให้แม่แบบไปอ่านเอง ───
-- แม่แบบห้ามแตะฐานข้อมูล (หลักข้อ 5ก) และ payload ตรึงตั้งแต่วันที่ออก —
-- ใบที่ออกวันนี้ต้องพิมพ์เครื่องหมายชุดเดิมได้อีกสิบปีแม้ระเบียนจะเปลี่ยน
-- ถ้าแม่แบบคำนวณสดตอนพิมพ์ ใบเก่าจะเปลี่ยนความหมายเมื่อมีคนแก้ข้อมูล
create or replace function transcript_category_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(head order by head ->> 'sort'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'code',        h.head_code,
               'name_th',     h.name_th,
               'sort',        h.sort_key,
               'min_credits', h.min_credits,
               'credits_earned', h.credits_earned,
               'gpa',         h.gpa,
               'groups',
                 coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'code',        g.group_code,
                            'name_th',     g.name_th,
                            'sort',        g.sort_key,
                            'min_credits', g.min_credits,
                            'credits_earned', g.credits_earned,
                            'gpa',         g.gpa,
                            'courses',
                              coalesce((
                                select jsonb_agg(jsonb_build_object(
                                         'term_label',  c.term_label,
                                         'year_be',     c.year_be,
                                         'term_ordinal', c.term_ordinal,
                                         'plan_year_be', c.plan_year_be,
                                         'plan_term_ordinal', c.plan_term_ordinal,
                                         'code',        c.course_code,
                                         'name_th',     c.course_name_th,
                                         'name_en',     c.course_name_en,
                                         'credits',     c.credits,
                                         'grade',       c.grade_symbol,
                                         'grade_point', c.grade_point,
                                         'grade_points',
                                           case when c.counts_in_gpa
                                                then c.grade_point * c.credits end,
                                         'counts_in_gpa', c.counts_in_gpa,
                                         'credits_earned', c.credits_earned,
                                         'notes',       c.note_marks)
                                         order by coalesce(c.plan_year_be, c.year_be),
                                                  coalesce(c.plan_term_ordinal, c.term_ordinal),
                                                  coalesce(c.plan_sort, 0),
                                                  c.course_code)
                                  from transcript_courses_grouped(p_student_id) c
                                 where c.head_code = h.head_code
                                   and c.group_code = g.group_code), '[]'::jsonb))
                          order by g.sort_key)
                     from transcript_category_summary(p_student_id) g
                    where g.level = 'group' and g.head_code = h.head_code), '[]'::jsonb)) as head
        from transcript_category_summary(p_student_id) h
       where h.level = 'head'
    ) x
$$;

comment on function transcript_category_tree(uuid) is
  'โครงหมวด → กลุ่มวิชา → รายวิชา พร้อมยอดสรุปทุกชั้น สำหรับใบ รบ. ตระกูล 67 · notes คือเลข (*n) ท้ายชื่อวิชา';

create or replace function transcript_term_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  with c as (select * from transcript_data(p_student_id)),
  t as (
    select c.term_id,
           min(c.year_be)      as year_be,
           min(c.term_ordinal) as ordinal
      from c
     group by c.term_id
  ),
  s as (
    select t.term_id, t.year_be, t.ordinal,
           ts.credits_earned, ts.gpa, ts.gpax,
           (ts.student_id is not null) as has_summary,
           case when bool_and(ts.student_id is not null)
                     over (order by t.year_be, t.ordinal)
                then sum(ts.credits_earned)
                     over (order by t.year_be, t.ordinal)
           end as credits_cum
      from t
      left join term_summary ts
             on ts.term_id = t.term_id
            and ts.student_id = p_student_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'year_be',        s.year_be,
        'ordinal',        s.ordinal,
        'credits_earned', s.credits_earned,
        'credits_cum',    s.credits_cum,
        'has_summary',    s.has_summary,
        'gpa',            s.gpa,
        'gpax',           s.gpax,
        'courses',
          coalesce((select jsonb_agg(jsonb_build_object(
                             'code',        c.course_code,
                             'name_th',     c.course_name_th,
                             'name_en',     c.course_name_en,
                             'credits',     c.credits,
                             'grade',       c.grade_symbol,
                             'grade_point', c.grade_point,
                             'grade_points', c.grade_points,
                             'counts_in_gpa', c.counts_in_gpa,
                             'credits_earned', c.credits_earned,
                             'notes',       c.note_marks)
                             order by c.course_code)
                     from c where c.term_id = s.term_id), '[]'::jsonb))
      order by s.year_be, s.ordinal),
    '[]'::jsonb)
  from s
$$;

comment on function transcript_term_tree(uuid) is
  'โครงปีการศึกษา → ภาคเรียน → รายวิชา พร้อมสรุปสี่ตัวเลขท้ายภาค สำหรับใบ รบ. ตระกูล 62 — credits_cum เป็น null เมื่อมีภาคที่ยังไม่ได้ตัดยอด · notes คือเลข (*n)';

-- ── 7. (*4) ต้องติดให้เองทุกครั้งที่ลงทะเบียน ไม่ใช่แค่ตอน migrate ───
--
-- ─── ทำไมการ backfill อย่างเดียวไม่พอ ───
-- ข้อ 1 อัปเดตแถวที่มีอยู่แล้วให้ถูกต้อง แต่แถวที่ลงทะเบียนพรุ่งนี้จะได้
-- ค่าเริ่มต้น false ทั้งที่กลุ่มเรียนเป็นทวิภาคี — ใบ รบ. ของรุ่นถัดไปจะ
-- ขาด (*4) โดยไม่มีอะไรฟ้อง และคนที่ตรวจจะเห็นว่า "เคยมีแล้วหายไป"
-- ซึ่งหาสาเหตุยากกว่า "ไม่เคยมี" มาก
--
-- ─── ทำไมยังเก็บเป็นคอลัมน์ ไม่อ่านสดจาก class_section ───
-- เพราะ **นักศึกษาคนเดียวในกลุ่มปกติอาจไปฝึกที่สถานประกอบการ** ตามข้อตกลง
-- รายบุคคล การอ่านสดจากกลุ่มเรียนจะเขียนทับกรณีนั้นทิ้งทุกครั้ง
-- trigger ตั้งค่า**ตั้งต้น**ให้ตรงกับกลุ่มเรียน แล้วปล่อยให้แก้รายคนได้
create or replace function enrollment_workplace_default() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' and new.taught_at_workplace = false then
    select (cs.delivery_mode in ('dvt', 'internship'))
      into new.taught_at_workplace
      from class_section cs
     where cs.id = new.class_section_id;
  end if;
  return new;
end $$;

drop trigger if exists enrollment_workplace_default on enrollment;
create trigger enrollment_workplace_default
  before insert on enrollment
  for each row execute function enrollment_workplace_default();

comment on function enrollment_workplace_default() is
  'ตั้ง (*4) ให้ตรงกับรูปแบบการเรียนของกลุ่มตอนลงทะเบียน — แก้รายคนทีหลังได้';

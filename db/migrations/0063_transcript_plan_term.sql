-- ═══════════════════════════════════════════════════════════════════
-- 0063 — ใบ รบ. แสดงภาคเรียนตาม**โครงสร้างหลักสูตร** ไม่ใช่ภาคที่ลงทะเบียนจริง
--
-- ═══ สิ่งที่เปลี่ยน ═══
-- นักศึกษาลงวิชาหนึ่งไว้ที่ปี 1 ภาคเรียนที่ 1 แต่โครงสร้างหลักสูตรวางวิชานั้น
-- ไว้ที่ปี 2 ภาคเรียนที่ 1 — ใบ รบ. ต้องพิมพ์ว่า **1/ปีที่สอง**
--
-- เพราะใบ รบ. เป็นเอกสารที่แสดงว่านักศึกษาเรียนครบตาม**หลักสูตร** ไม่ใช่
-- ปูมว่าไปนั่งเรียนห้องไหนเมื่อไร คนที่รับใบไปเทียบกับโครงสร้างหลักสูตร
-- ของ สอศ. ต้องเห็นรายวิชาอยู่ตำแหน่งเดียวกับที่หลักสูตรกำหนด มิฉะนั้น
-- จะดูเหมือนเรียนผิดแผนทั้งที่จบครบตามเกณฑ์
--
-- ═══ ของที่มีอยู่แล้วแต่ไม่เคยมีใครอ่าน ═══
-- `curriculum_course.suggested_year` กับ `suggested_term` มีมาตั้งแต่ 0004
-- พร้อมคอมเมนต์ว่า "แผนการเรียนแนะนำ … ใช้เตือนเมื่อนักศึกษาเรียนไม่ตามแผน"
-- ค้นทั้ง repo แล้ว**ไม่มีโค้ดไหนอ้างถึงเลยสักบรรทัด** ตลอดหกสิบ migration
-- รูปเดียวกับ `student_guardian.can_approve_leave` (ข้อ 15) และ
-- `take_usage_snapshot()` (ข้อ 8) — ของที่ประกาศเจตนาไว้แล้วไม่มีอะไร
-- ทำให้เจตนานั้นเกิดขึ้น
--
-- ═══ ชั้นปีไม่ใช่ปีการศึกษา ═══
-- `suggested_year` เป็น **ชั้นปี 1-4** ส่วนช่องบนใบพิมพ์ **ปีการศึกษา พ.ศ.**
-- แปลงด้วยปีที่เข้าศึกษา — ชั้นปี 1 = ปีที่เข้า · ชั้นปี 2 = ปีที่เข้า + 1
-- นักศึกษาที่ซ้ำชั้นหรือเทียบโอนเข้ากลางคันจะได้ปีที่ต่างจากที่ลงจริง
-- ซึ่งเป็นผลที่ตั้งใจ เพราะใบแสดงตำแหน่งตามหลักสูตร
--
-- ═══ เก็บทั้งสองค่า ไม่ใช่เขียนทับ ═══
-- `year_be` / `term_ordinal` ยังเป็น**ภาคที่ลงทะเบียนจริง**เหมือนเดิม
-- และเพิ่ม `plan_year_be` / `plan_term_ordinal` มาข้าง ๆ เพราะ
-- 1. ใบที่ออกไปแล้วไม่มีช่องใหม่ → แม่แบบตกไปใช้ค่าเดิม พิมพ์ซ้ำได้เหมือนเดิม
--    (payload ตรึงแล้วแก้ไม่ได้ การเปลี่ยนความหมายของช่องเดิมจะทำให้ใบเก่า
--     พิมพ์ออกมาไม่เหมือนวันที่ออก ซึ่งเป็นสิ่งที่หลักข้อ 5 ห้ามไว้)
-- 2. ตรวจย้อนหลังได้ว่านักศึกษาลงจริงเมื่อไร ต่างจากที่หลักสูตรวางไว้ตรงไหน
--
-- ═══ ทำไมตระกูล 62 ยังจัดกลุ่มตามภาคที่ลงจริง ═══
-- ใบตระกูล 62 จัดกลุ่มรายวิชา**ใต้หัวภาคเรียน** แล้วพิมพ์สรุปสี่ตัวเลข
-- (หน่วยกิตในภาค · สะสม · GPA · GPAX) ต่อท้ายทุกภาค ซึ่งมาจาก `term_summary`
-- คือผลการเรียนรายภาคที่ระบบใช้ตัดสินการจบและสถานะรอพินิจ
--
-- ถ้าย้ายรายวิชาไปอยู่ใต้หัวภาคตามแผน ตัวเลขสรุปจะไม่ตรงกับรายวิชาที่อยู่
-- ข้างบนมันเอง และการคำนวณสรุปใหม่จากรายวิชาที่แสดงจะได้ **GPA รายภาคชุดที่สอง**
-- ที่ต่างจากชุดที่ระบบใช้จริง — สองอย่างนี้แย่ทั้งคู่และแย่กว่าการแสดงภาคจริง
-- ตระกูล 62 จึงยังจัดตามภาคที่ลงทะเบียน ส่วน payload เก็บภาคตามแผนไว้ให้แล้ว
-- เผื่อวันที่ตัดสินใจเป็นอย่างอื่น (หลักเดียวกับ 0057 — ฝั่งที่แพงถ้าช้าทำก่อน)
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * ต้อง drop ก่อน เพราะ `create or replace` เปลี่ยนชนิดที่คืนของ table
 * function ไม่ได้ — และตัวนี้ต้องเพิ่มสามคอลัมน์
 */
drop function if exists transcript_courses_grouped(uuid);

create or replace function transcript_courses_grouped(p_student_id uuid)
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
  counts_in_gpa boolean
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
    /*
     * ชั้นปีตามแผน → ปีการศึกษา พ.ศ.
     * null เมื่อรายวิชาไม่ได้อยู่ในโครงสร้างหลักสูตร (วิชาเลือกเสรีนอกแผน ·
     * วิชาที่เทียบโอนมา) หรือหลักสูตรยังไม่ได้ระบุแผนไว้ หรือไม่รู้ปีที่เข้า
     * — แม่แบบจะตกไปใช้ภาคที่ลงจริง ซึ่งดีกว่าพิมพ์ช่องว่าง
     */
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
    (gsym.counts_in_gpa and e.counts_toward_gpa)
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
$$;

comment on function transcript_courses_grouped(uuid) is
  'รายวิชาของนักศึกษาพร้อมหมวด/กลุ่มตามหลักสูตร · year_be คือภาคที่ลงจริง ส่วน plan_year_be คือภาคตามโครงสร้างหลักสูตร (null เมื่อไม่อยู่ในแผน)';


/*
 * ส่งภาคตามแผนเข้า payload และ**เรียงตามค่าที่จะพิมพ์จริง**
 *
 * ถ้าเรียงตามภาคที่ลงแต่พิมพ์ภาคตามแผน คอลัมน์ภาคเรียนบนใบจะกระโดดไปมา
 * (1/2566 · 1/2567 · 1/2566) ซึ่งอ่านแล้วเหมือนพิมพ์ผิด — เรียงลำดับต้อง
 * ตรงกับสิ่งที่ตาเห็นเสมอ
 *
 * `plan_sort` คือ `curriculum_course.sort_order` ซึ่งเป็นลำดับที่วิทยาลัย
 * จัดไว้เองในหลักสูตร ใช้ก่อนรหัสวิชา เพราะหลักสูตรเรียงวิชาตามเนื้อหา
 * ไม่ได้เรียงตามเลขรหัส
 */
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
                                         'credits_earned', c.credits_earned)
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

commit;

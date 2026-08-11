-- ═══════════════════════════════════════════════════════════════════
-- 0060 — ใบ รบ. ตระกูล 62 จัดกลุ่มตามภาคเรียน ไม่ใช่ตามหมวดวิชา
--
-- ═══ ทำไมต้องมีโครงชุดที่สอง ไม่ใช่จัดเรียง category_tree ใหม่ ═══
-- ตระกูล 67 สรุป **หน่วยกิตและคะแนนเฉลี่ยรายกลุ่มวิชา/รายหมวด**
-- ตระกูล 62 สรุป **รายภาคเรียน** และมีคอลัมน์ที่ตระกูล 67 ไม่มีเลยคือ
-- ผลคูณ (1)×(2) = หน่วยกิต × ระดับผลการเรียน
-- สองอย่างนี้เป็นตัวเลขคนละชุดที่คำนวณคนละแบบ ไม่ใช่ข้อมูลเดียวกันที่
-- เรียงต่างกัน — จัดเรียงใหม่จาก category_tree ให้ตัวเลขสรุปไม่ได้เลย
--
-- ═══ ทำไมผลคูณต้องมาจากฐานข้อมูล ไม่ใช่ให้แม่แบบคูณเอง ═══
-- ตัวเลขในคอลัมน์นั้นคือ **ตัวตั้งของสูตร GPA** พอดี —
-- `compute_term_summary()` ใช้ `sum(grade_point * course.credits)
-- filter (where counts_in_gpa)` เป็นเศษ แล้วหารด้วยหน่วยกิตที่นับ
-- ถ้าแม่แบบคูณเอง มันจะไม่รู้เรื่อง `counts_in_gpa` แล้ววิชา ผ./ม.ผ.
-- จะได้ผลคูณเป็น 0 ทั้งที่ใบจริงพิมพ์ "-" — ผลคือคอลัมน์ที่พิมพ์อยู่
-- ข้าง ๆ GPA บวกแล้วไม่ตรงกับ GPA ที่พิมพ์อยู่บรรทัดล่าง **บนกระดาษ
-- ใบเดียวกัน** ซึ่งเป็นความขัดแย้งที่คนถือใบเห็นเองได้
--
-- ═══ และแก้ข้อสรุปผิดของ 0059 ═══
-- 0059 เขียนไว้ว่าฉบับอังกฤษของ ปวส. **ต่อเนื่อง** ใช้ชื่อเรื่องเดียวกับ
-- ปวส. ปกติ ซึ่งผิด — บรรทัดชื่อเรื่องเหมือนกันจริง แต่มีอีกบรรทัดอยู่ใต้
-- ลงมาว่า "(CONTINUING PROGRAM)" ถ้าไม่มี ใบจะไม่ได้บอกเลยว่าเป็นหลักสูตร
-- ต่อเนื่อง ทั้งที่ฉบับไทยบอกด้วยคำว่า "(ต่อเนื่อง)" ในชื่อเรื่อง
-- (แก้ที่แม่แบบ ไม่ใช่ที่สคีมา — `curriculum.is_continuing` ของ 0059 ถูกแล้ว)
--
-- ═══ ที่ตรวจเจอระหว่างทาง — หน่วยกิตสะสมของตระกูล 67 พิมพ์ผิดมาตลอด ═══
-- แม่แบบ 67 พิมพ์ "หน่วยกิตที่ได้ในภาค" กับ "หน่วยกิตสะสม" จากค่าเดียวกัน
-- คือ `credits_earned` ของภาคนั้น ภาคที่สองจึงพิมพ์ 11/11 แทนที่จะเป็น
-- 11/28 — เป็นตัวเลขผิดบนเอกสารที่แก้ไม่ได้ ไม่มีเทสต์ไหนจับได้เพราะ
-- ไม่มีใครเทียบตัวเลขสองตัวนั้นกับใบจริง เจอตอนวัดไฟล์ตระกูล 62
-- ซึ่งพิมพ์คู่นี้ไว้ท้ายทุกภาคเรียน (17/17 · 11/28 · 3/31)
-- ═══════════════════════════════════════════════════════════════════

begin;

/* ═══════════════════════════════════════════════════════════════════
 * ฉบับอังกฤษออกไม่ได้เลยเมื่อสายไทยเดินนำไปแล้ว
 *
 * 0057 แยกตัวนับของสองภาษาออกจากกันสำเร็จ แต่ให้ทั้งสองสายใช้ **คำนำหน้า
 * เดียวกันคือปีการศึกษา** และตัวนับของทั้งคู่เริ่มที่ 1 ผลคือเลขที่ที่
 * *พิมพ์ลงกระดาษ* ชนกัน — ฉบับอังกฤษใบแรกได้ "256900001" ซึ่งฉบับไทย
 * ใช้ไปแล้ว แล้ว unique (institution_id, kind, doc_no, copy_no) ปฏิเสธ
 *
 * ─── ทำไมเทสต์ของ 0057 ไม่จับ ───
 * TEST 258/259 ออกฉบับไทยไปหลายใบก่อนแล้วจึงออกฉบับอังกฤษใบแรก เลข
 * ที่ได้จึงเป็น 256900005 กับ 256900001 ซึ่ง "ต่างกัน" ตามที่เทสต์ตรวจ
 * — เทสต์ตรวจว่าเลข**ไม่เท่ากัน** ซึ่งเป็นจริงเสมอในช่วงที่สายหนึ่งนำอยู่
 * ทั้งที่สิ่งที่ต้องพิสูจน์คือสองสาย**ไม่มีวันชนกัน** ต่างกันคนละเรื่อง
 * ความผิดพลาดโผล่ตอนสายอังกฤษไล่ทันเลขที่สายไทยเคยใช้ ซึ่งเกิดแน่นอน
 * เพราะทั้งคู่เริ่มที่ 1
 *
 * ─── ทำไมแก้ที่คำนำหน้า ไม่ใช่เพิ่ม lang เข้าไปใน unique ───
 * เพิ่ม lang เข้า unique จะได้เอกสารสองใบที่**พิมพ์เลขเดียวกัน** คนที่
 * ถือใบมาตรวจสอบด้วยเลขที่จะเจอสองรายการโดยไม่รู้ว่าต้องดูใบไหน
 * เลขที่บนกระดาษต้องชี้ไปที่ใบเดียวเสมอ (SISA เองก็เดินคนละสายจริง —
 * ฟิลด์ `eng_mass_transcript_no` แยกจากสายไทย)
 *
 * ─── และทำไมยอมให้สายอังกฤษมีตัวอักษรได้ ───
 * `certificate_prefix_digits_only` มาจากระเบียบกระทรวงซึ่งบังคับ
 * **ใบประกาศนียบัตรฉบับที่ยื่นต่อ สอศ.** ซึ่งเป็นฉบับไทย ส่วนฉบับอังกฤษ
 * เป็นเอกสารที่ออกให้ผู้ถือไปใช้ต่อ ไม่ใช่ตัวที่ยื่นตามระเบียบ
 * จึงจำกัดข้อบังคับให้เหลือเฉพาะสายไทย
 * ═══════════════════════════════════════════════════════════════════ */
alter table document_series drop constraint if exists certificate_prefix_digits_only;
alter table document_series add constraint certificate_prefix_digits_only
  check (kind <> 'certificate' or lang <> 'th' or prefix ~ '^[0-9]*$');

-- สายอังกฤษที่สร้างไปแล้วด้วยคำนำหน้าเดิม ต้องย้ายก่อนที่จะไปชนของไทย
update document_series
   set prefix = 'E' || year_be::text
 where lang <> 'th' and prefix = year_be::text;

create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text default 'th'
) returns text language plpgsql as $$
declare
  v_inst   uuid := current_institution_id();
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  /*
   * คำนำหน้าตั้งต้นเป็นปีการศึกษา เพราะ `issued_document` มี
   * unique (institution, kind, doc_no, copy_no) ซึ่ง **ไม่มีปีการศึกษา
   * อยู่ในนั้น** ส่วนตัวนับเริ่มที่ 1 ใหม่ทุกปี — ถ้าไม่มีคำนำหน้า
   * ใบแรกของปีการศึกษาใหม่จะล้มด้วย duplicate key (0057)
   *
   * และสายที่ไม่ใช่ภาษาไทยเติม "E" นำหน้าด้วยเหตุผลเดียวกันพอดี คือ
   * ตัวนับของแต่ละสายเริ่มที่ 1 เหมือนกัน จึงชนกันแน่นอนเมื่อไล่ทัน
   */
  insert into document_series (institution_id, kind, year_be, lang, prefix)
  values (v_inst, p_kind, p_year_be, p_lang,
          case when p_lang = 'th' then p_year_be::text
               else 'E' || p_year_be::text end)
  on conflict (institution_id, kind, year_be, lang) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = v_inst and kind = p_kind
     and year_be = p_year_be and lang = p_lang
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint, text) is
  'จ่ายเลขที่เอกสารจากสายที่แยกตามสถานศึกษา ประเภท ปีการศึกษา และภาษา — สายที่ไม่ใช่ไทยมีคำนำหน้า E เพราะตัวนับทุกสายเริ่มที่ 1 จึงชนกันแน่นอนถ้าใช้คำนำหน้าเดียวกัน';


/*
 * transcript_data() เพิ่มสามคอลัมน์
 *
 * `term_id`        — เพื่อจับคู่กับ term_summary ได้ตรง ๆ โดยไม่ต้องเดา
 *                    จากปี+ลำดับ ซึ่งซ้ำกันได้ข้ามภาคฤดูร้อน
 * `counts_in_gpa`  — ใบตระกูล 62 พิมพ์ "-" ทั้งช่องหน่วยกิตและช่องผลคูณ
 *                    ให้วิชาที่ไม่นับ GPA (วัดจากไฟล์จริง: กิจกรรมลูกเสือ
 *                    ได้ ผ. พิมพ์ "-" ไม่ใช่ "0")
 * `grade_points`   — ผลคูณที่เป็นตัวตั้งของ GPA (ดูเหตุผลที่หัวไฟล์)
 *
 * ─── counts_in_gpa เป็น "และ" ของสองเงื่อนไข ไม่ใช่คอลัมน์เดียว ───
 * `compute_term_summary()` กรองด้วย **ทั้ง** `grade_symbol.counts_in_gpa`
 * และ `enrollment.counts_toward_gpa` — ตัวหลังเป็น false สำหรับรายวิชา
 * ปรับพื้นฐานและรายวิชาเทียบโอน ซึ่งเป็นกรณีปกติของนักศึกษา ปวส.
 * ที่จบ ปวช. มา ถ้าส่งมาแค่ตัวแรก คอลัมน์ผลคูณจะรวมวิชาเทียบโอนเข้าไป
 * แล้วบวกไม่ตรงกับ GPA ที่พิมพ์อยู่บรรทัดถัดไป — และจะเกิดกับใบของ
 * นักศึกษา ปวส. **เกือบทุกใบ** ส่งมาค่าเดียวที่ตอบคำถามที่กระดาษถามจริง
 * คือ "แถวนี้ถูกนับใน GPA ที่พิมพ์อยู่ข้างล่างหรือไม่"
 *
 * ต้อง drop ก่อนเพราะ `create or replace` เปลี่ยนรายการคอลัมน์ของ
 * `returns table` ไม่ได้ — เพิ่มไว้ท้ายสุดเพื่อไม่ให้ตำแหน่งเดิมขยับ
 */
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
  grade_points   numeric
) language sql stable as $$
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
    -- สูตรเดียวกับเศษของ GPA ใน compute_term_summary() ตัวต่อตัว
    case when gsym.counts_in_gpa and e.counts_toward_gpa
         then er.grade_point * c.credits end
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
  order by ay.year_be, t.ordinal, c.code;
$$;

comment on function transcript_data(uuid) is
  'รายวิชาทั้งหมดที่ขึ้นระเบียนแสดงผลการเรียน — ใช้ผลฉบับปัจจุบันและค่าที่ตรึงไว้แล้วเท่านั้น · grade_points คือตัวตั้งของ GPA จึงต้องคิดที่นี่ที่เดียว';


/*
 * โครงภาคเรียน → รายวิชา พร้อมสรุปสี่ตัวเลขท้ายภาค
 *
 * ─── ทำไม credits_cum เป็น null ได้ ───
 * ค่าสะสมคือผลรวมของ `term_summary.credits_earned` ย้อนหลังทุกภาค
 * ถ้ามีภาคไหนยังไม่ได้ตัดยอด (ไม่มีแถวใน term_summary) ผลรวมจะขาดไป
 * เท่ากับหน่วยกิตของภาคนั้นโดยไม่มีอะไรฟ้อง — ใบจะพิมพ์ตัวเลขที่ต่ำกว่า
 * ความจริงและดูสมเหตุสมผลทุกประการ จึงคืน null ให้แม่แบบพิมพ์ "-"
 * ซึ่งอ่านออกว่า "ยังไม่รู้" ต่างจากตัวเลขผิดที่อ่านไม่ออกว่าผิด
 */
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
        -- ไม่ส่งข้อความหัวภาคมาด้วย เพราะฉบับอังกฤษเขียน
        -- "Academic year 2025  1st Semester" คือใช้ **ปีคริสต์ศักราช**
        -- การประกอบข้อความจึงเป็นเรื่องของแม่แบบแต่ละภาษา
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
                             'credits_earned', c.credits_earned)
                             order by c.course_code)
                     from c where c.term_id = s.term_id), '[]'::jsonb))
      order by s.year_be, s.ordinal),
    '[]'::jsonb)
  from s
$$;

comment on function transcript_term_tree(uuid) is
  'โครงปีการศึกษา → ภาคเรียน → รายวิชา พร้อมสรุปสี่ตัวเลขท้ายภาค สำหรับใบ รบ. ตระกูล 62 — credits_cum เป็น null เมื่อมีภาคที่ยังไม่ได้ตัดยอด';


/*
 * คะแนนเฉลี่ยรายกลุ่มของตระกูล 67 เคยรวมวิชาเทียบโอนเข้าไปด้วย
 *
 * 0058 กรองด้วย `grade_symbol.counts_in_gpa` อย่างเดียว ขาด
 * `enrollment.counts_toward_gpa` ไป ผลคือคะแนนเฉลี่ยรายกลุ่มบนใบไม่ตรงกับ
 * GPAX ที่พิมพ์อยู่หัวใบเดียวกัน สำหรับนักศึกษาที่มีวิชาเทียบโอนหรือ
 * วิชาปรับพื้นฐาน ซึ่งคือ **นักศึกษา ปวส. เกือบทุกคน**
 *
 * เขียนทับทั้งฟังก์ชันเพราะ `returns table` แก้เฉพาะเงื่อนไขไม่ได้
 */
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
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    (gsym.counts_in_gpa and e.counts_toward_gpa)
  from enrollment e
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
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by coalesce(head.sort_order, 99), coalesce(grp.sort_order, 0),
           ay.year_be, t.ordinal, c.code
$$;


/*
 * ตระกูล 67 ต้องรู้ counts_in_gpa ด้วย
 *
 * ใบจริงของตระกูล 67 พิมพ์ "-" ในช่องหน่วยกิตของวิชากิจกรรมเหมือนกัน
 * (วัดจาก `ระเบียนแสดงผลการเรียน…(ปวช. 67).pdf` หน้า 2 — กิจกรรมลูกเสือ
 * วิสามัญพิมพ์ "-" กับ "ผ.") แต่ payload เดิมไม่ได้ส่งสิ่งที่ใช้ตัดสิน
 * มาเลย แม่แบบจึงพิมพ์หน่วยกิตจริงของรายวิชาแทน
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
                                         order by c.year_be, c.term_ordinal, c.course_code)
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


/*
 * เพิ่ม term_tree ลง payload ของใบ รบ.
 *
 * นี่คือรอบแรกที่ได้ใช้สิ่งที่ 0059 แยกไว้ — เพิ่มช่องให้ใบ รบ. โดย
 * **ไม่ต้องเขียน issue_document_core() ทับทั้ง 300 บรรทัด** ซึ่งเป็นสิ่งที่
 * 0057 และ 0058 ต้องทำทั้งคู่เพื่อเพิ่มบรรทัดเดียว
 *
 * ทั้งสองโครงอยู่ในใบเดียวกันโดยตั้งใจ ไม่ได้เลือกอย่างใดอย่างหนึ่งตาม
 * รุ่นหลักสูตร เพราะ payload ตรึงแล้วแก้ไม่ได้ — วันที่วิทยาลัยขอพิมพ์ซ้ำ
 * เป็นอีกแบบ (ซึ่งเกิดจริง เช่นส่งให้ที่ทำงานขอฉบับที่จัดตามภาคเรียน)
 * ใบที่เก็บโครงเดียวจะพิมพ์แบบนั้นไม่ได้เลยตลอดไป ต้นทุนของการเก็บทั้งสอง
 * โครงคือ jsonb ที่ใหญ่ขึ้นราวเท่าตัวของส่วนรายวิชา ซึ่งถูกกว่ามาก
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'term_tree',     transcript_term_tree(p_student_id),
    /*
     * ─── "หน่วยกิตที่เรียน" กับ "หน่วยกิตที่ได้" เป็นคนละตัวเลข ───
     * ใบจริงพิมพ์ทั้งคู่ติดกัน (ฉบับอังกฤษคือ Credits Enrolled 34 กับ
     * Total Credits 31) แต่ payload มีแค่ตัวหลัง แม่แบบทั้งสองตระกูลจึง
     * พิมพ์ค่าเดียวกันสองครั้ง — ใบบอกว่าลงเรียนเท่ากับที่ได้ทุกใบ
     * แปลว่าไม่เคยตกและไม่เคยถอนรายวิชาสักตัว ซึ่งอ่านแล้วดูสมเหตุสมผล
     * และตรวจไม่ได้ถ้าไม่มีอย่างอื่นให้เทียบ (รูปเดียวกับหน่วยกิตสะสม)
     *
     * เป็น null เมื่อยังไม่มีภาคไหนตัดยอด — พิมพ์ "-" ดีกว่าพิมพ์ 0
     */
    'credits_attempted',
      (select sum(ts.credits_attempted) from term_summary ts
        where ts.student_id = p_student_id),
    'prior_education',
      (select jsonb_build_object(
                'level_th',   pe.level_th,
                'school_th',  coalesce(pe.school_th, ''),
                'province_th', coalesce(pe.province_th, ''),
                'program_th', coalesce(pe.program_th, ''),
                'year_be',    pe.completed_year_be,
                'gpax',       pe.gpax)
         from student_prior_education pe
        where pe.student_id = p_student_id
        order by pe.completed_year_be desc nulls last, pe.level_th desc
        limit 1))
$$;

commit;

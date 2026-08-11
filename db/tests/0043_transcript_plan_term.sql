-- ═══════════════════════════════════════════════════════════════════
-- 0043_transcript_plan_term.sql
-- ทดสอบว่าใบ รบ. แสดงภาคเรียนตามโครงสร้างหลักสูตร ไม่ใช่ภาคที่ลงทะเบียน (0063)
--
-- ─── ทำไมข้อนี้ต้องทำให้สองค่า "ต่างกันจริง" ก่อนตรวจ ───
-- ในข้อมูลตัวอย่าง นักศึกษาลงทะเบียนตรงตามแผนอยู่แล้ว ค่าที่ลงจริงกับค่า
-- ตามแผนจึงเท่ากัน — เทสต์ที่รันบนข้อมูลแบบนั้นจะเขียวเหมือนกันทั้งตอนที่
-- โค้ดถูกและตอนที่โค้ดยังอ่านค่าเดิมอยู่ คือไม่ได้พิสูจน์อะไรเลย
-- ต้องดันแผนให้ไปคนละปีกับที่ลงจริงก่อน ถึงจะแยกสองกรณีออกจากกันได้
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare
  v_student   uuid;
  v_course    text;
  v_inst      uuid;
  v_admitted  smallint;
  v_real_year smallint;
  v_real_term smallint;
  v_plan_year smallint;
  v_plan_term smallint;
  v_seen_year smallint;
  v_seen_term smallint;
  v_fallback  integer;
begin
  perform set_config('app.role', 'registrar', true);
  select s.id, s.institution_id, s.admitted_year_be
    into v_student, v_inst, v_admitted
    from student s
    join enrollment e on e.student_id = s.id
   group by s.id, s.institution_id, s.admitted_year_be
   having count(*) > 0
   order by s.student_code
   limit 1;
  perform set_config('app.institution_id', v_inst::text, true);

  -- หยิบรายวิชาหนึ่งตัวที่อยู่ในโครงสร้างหลักสูตรจริง
  select c.course_code, c.year_be, c.term_ordinal
    into v_course, v_real_year, v_real_term
    from transcript_courses_grouped(v_student) c
   where c.plan_year_be is not null
   limit 1;

  if v_course is null then
    -- ไม่มีรายวิชาไหนผูกกับแผนเลย — ตั้งแผนให้หนึ่งตัวเพื่อให้ตรวจได้
    update curriculum_course cc
       set suggested_year = 2, suggested_term = 1
      from transcript_courses_grouped(v_student) g
      join course co on co.code = g.course_code
     where cc.course_id = co.id
       and cc.suggested_year is null;
  end if;

  /*
   * ดันแผนของทุกรายวิชาไปที่ **ชั้นปี 2 ภาคเรียนที่ 2** ซึ่งข้อมูลตัวอย่าง
   * ไม่ได้ลงไว้ที่นั่น — ถ้าฟังก์ชันยังอ่านภาคที่ลงจริงอยู่ ค่าที่ได้จะไม่ใช่ค่านี้
   */
  update curriculum_course cc
     set suggested_year = 2, suggested_term = 2
   where exists (select 1 from transcript_courses_grouped(v_student) g
                  join course co on co.code = g.course_code
                 where co.id = cc.course_id);

  v_plan_year := v_admitted + 1;      -- ชั้นปี 2 = ปีที่เข้า + 1
  v_plan_term := 2;

  select c.plan_year_be, c.plan_term_ordinal
    into v_seen_year, v_seen_term
    from transcript_courses_grouped(v_student) c
   where c.plan_year_be is not null
   limit 1;

  if v_seen_year is distinct from v_plan_year or v_seen_term is distinct from v_plan_term then
    raise exception 'TEST 270 ล้มเหลว: แปลงชั้นปีเป็นปีการศึกษาผิด — คาด %/% ได้ %/%',
                    v_plan_term, v_plan_year, v_seen_term, v_seen_year;
  end if;

  -- และต้องต่างจากภาคที่ลงจริง มิฉะนั้นข้อนี้ไม่ได้พิสูจน์อะไร
  if v_seen_year = v_real_year and v_seen_term = v_real_term then
    raise exception 'TEST 270 ล้มเหลว: ภาคตามแผนเท่ากับภาคที่ลงจริง เทสต์นี้แยกสองกรณีไม่ได้';
  end if;

  /*
   * รายวิชาที่ไม่ได้อยู่ในโครงสร้างหลักสูตรต้องได้ null ไม่ใช่ค่าที่เดาขึ้นมา
   * — แม่แบบจะตกไปใช้ภาคที่ลงจริง ซึ่งดีกว่าพิมพ์ช่องว่างบนเอกสารทางการ
   */
  select count(*) into v_fallback
    from transcript_courses_grouped(v_student) c
   where c.plan_year_be is null and c.year_be is null;
  if v_fallback > 0 then
    raise exception 'TEST 270 ล้มเหลว: มี % รายวิชาที่ไม่มีทั้งภาคตามแผนและภาคที่ลงจริง',
                    v_fallback;
  end if;

  raise notice 'TEST 270 ผ่าน — ภาคตามแผน %/% ต่างจากภาคที่ลงจริง %/% และวิชานอกแผนมีภาคสำรองครบ',
               v_seen_term, v_seen_year, v_real_term, v_real_year;
end $$;

/*
 * และ payload ต้องพา plan_* ไปถึงใบจริง มิฉะนั้นแม่แบบจะไม่มีอะไรให้ใช้
 * — ตรวจที่ผลลัพธ์ของ transcript_category_tree() ซึ่งเป็นสิ่งที่ถูกตรึงลง
 * payload ตอนออกใบ ไม่ใช่ตรวจที่ฟังก์ชันชั้นใน
 */
do $$
declare
  v_student uuid;
  v_inst    uuid;
  v_tree    jsonb;
  v_course  jsonb;
begin
  perform set_config('app.role', 'registrar', true);
  select s.id, s.institution_id into v_student, v_inst
    from student s join enrollment e on e.student_id = s.id
   group by s.id, s.institution_id order by s.student_code limit 1;
  perform set_config('app.institution_id', v_inst::text, true);

  v_tree := transcript_category_tree(v_student);
  select c into v_course
    from jsonb_array_elements(v_tree) h,
         jsonb_array_elements(h -> 'groups') g,
         jsonb_array_elements(g -> 'courses') c
   limit 1;

  if v_course is null then
    raise exception 'TEST 271 ล้มเหลว: โครงหมวดไม่มีรายวิชาเลย ตรวจต่อไม่ได้';
  end if;
  if not (v_course ? 'plan_year_be' and v_course ? 'plan_term_ordinal') then
    raise exception 'TEST 271 ล้มเหลว: payload ของรายวิชาไม่มีภาคตามแผน — %', v_course;
  end if;
  -- ภาคที่ลงจริงต้องยังอยู่ด้วย เพื่อให้ตรวจย้อนหลังได้ว่าลงจริงเมื่อไร
  if not (v_course ? 'year_be' and v_course ? 'term_ordinal') then
    raise exception 'TEST 271 ล้มเหลว: payload ต้องเก็บภาคที่ลงจริงไว้ด้วย — %', v_course;
  end if;

  raise notice 'TEST 271 ผ่าน — payload มีทั้งภาคตามแผน %/% และภาคที่ลงจริง %/%',
               v_course ->> 'plan_term_ordinal', v_course ->> 'plan_year_be',
               v_course ->> 'term_ordinal', v_course ->> 'year_be';
end $$;

reset role;

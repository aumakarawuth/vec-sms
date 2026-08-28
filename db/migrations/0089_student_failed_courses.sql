-- ═══════════════════════════════════════════════════════════════════
-- 0089 — วิชาที่นักศึกษายังไม่ผ่าน มองจากฝั่งนักศึกษาแทนฝั่งวิชา
--
-- 0030 มี regrade_eligible(session_course_id) ที่ตอบว่า "วิชานี้ ใครมีสิทธิ์
-- เข้าซ่อมบ้าง" อยู่แล้ว แต่ไม่มีทิศทางกลับ — "นักศึกษาคนนี้ ยังไม่ผ่าน
-- วิชาอะไรบ้าง" ซึ่งเป็นสิ่งที่หน้าลงทะเบียนเรียนเสริม/เรียนปรับเกรดรายคน
-- ต้องใช้ตอนเลือกนักศึกษาแล้วอยากเห็นเฉพาะวิชาที่ต้องลงจริง ๆ ไม่ใช่ทุกวิชา
-- ที่เปิดในภาคเรียนนั้น (เดิมหน้าจอโชว์ทุกกลุ่มเรียนในภาค ไม่กรองอะไรเลย)
--
-- เงื่อนไข "ยังไม่ผ่าน" ใช้หลักเดียวกับ regrade_eligible() เป๊ะ — ผลฉบับ
-- ปัจจุบัน (superseded_by is null) ของความพยายามล่าสุดไม่ได้หน่วยกิต
-- (earns_credit = false เช่น '0' 'ข.ร.' 'ถ.น.' 'ม.ผ.') และไม่เคยผ่านวิชานี้
-- ในความพยายามครั้งไหนเลย (เรียนซ้ำแล้วผ่านไม่ต้องซ่อมอีก)
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function student_failed_courses(p_student_id uuid)
returns table (
  course_id    uuid,
  course_code  text,
  course_name  text,
  grade_symbol text,
  term_label   text
) language sql stable as $$
  with attempts as (
    select cs.course_id, c.code, c.name_th,
           gsym.symbol, gsym.earns_credit,
           ay.year_be, t.ordinal, er.computed_at
      from enrollment e
      join class_section cs      on cs.id = e.class_section_id
      join course c               on c.id  = cs.course_id
      join term t                 on t.id  = e.term_id
      join academic_year ay       on ay.id = t.academic_year_id
      join enrollment_result er   on er.enrollment_id = e.id and er.superseded_by is null
      join grade_symbol gsym      on gsym.id = er.grade_symbol_id
     where e.student_id = p_student_id
       and e.status = 'enrolled'
  ),
  -- ความพยายามล่าสุดต่อวิชา — ใช้บอกสัญลักษณ์/ภาคที่แสดงบนหน้าจอเท่านั้น
  latest_attempt as (
    select distinct on (course_id) course_id, code, name_th, symbol, year_be, ordinal
      from attempts
     where not earns_credit
     order by course_id, computed_at desc
  )
  select la.course_id, la.code, la.name_th, la.symbol,
         'ภาคเรียนที่ ' || la.ordinal || '/' || la.year_be
    from latest_attempt la
   where not exists (
     select 1 from attempts a2
      where a2.course_id = la.course_id and a2.earns_credit
   )
   order by la.code;
$$;

comment on function student_failed_courses(uuid) is
  'วิชาที่นักศึกษาคนหนึ่งยังไม่ผ่าน (ผลปัจจุบันไม่ได้หน่วยกิต และไม่เคยผ่านวิชานี้ในความพยายามครั้งไหนเลย) — หลักการเดียวกับ regrade_eligible() แต่มองจากฝั่งนักศึกษา ใช้กรองรายวิชาในหน้าลงทะเบียนเรียนเสริม/เรียนปรับเกรดรายคน';

commit;

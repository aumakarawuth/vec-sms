-- ═══════════════════════════════════════════════════════════════════
-- 0042_transcript_term_tree.sql
-- ทดสอบโครงภาคเรียนของใบ รบ. ตระกูล 62 (0060)
--
-- ─── ทำไมเทสต์ชุดนี้เทียบตัวเลขกับ term_summary แทนที่จะเทียบกับค่าคงที่ ───
-- ใบ รบ. พิมพ์ตัวเลขสองชุดที่คนถือใบเอามาบวกเทียบกันเองได้ —
-- คอลัมน์ (1)×(2) รายวิชา กับ GPA ท้ายภาค ถ้าสองชุดนี้คิดกันคนละสูตร
-- ใบจะขัดแย้งกันเองบนกระดาษแผ่นเดียว ซึ่งเป็นข้อผิดพลาดที่ **ผู้รับใบ
-- เป็นคนเจอ** ไม่ใช่ระบบ เทสต์จึงต้องบวกจริงแล้วหารจริง ไม่ใช่ตรวจว่า
-- ฟังก์ชันคืนค่าไม่เป็น null
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ═══ ข้อมูลตั้งต้นที่ seed ไม่มี ═══════════════════════════════════
-- seed มีผลการเรียนอยู่ภาคเดียว ซึ่งพิสูจน์เรื่อง "สะสม" ไม่ได้เลย
-- และไม่มีรายวิชาเทียบโอนสักตัว ซึ่งเป็นกรณีที่ข้อผิดพลาดของคอลัมน์
-- ผลคูณจะโผล่ (นักศึกษา ปวส. เกือบทุกคนมีวิชาเทียบโอน)
--
-- สร้างทั้งสองอย่างที่นี่แทนที่จะแก้ seed เพราะ seed เป็นข้อมูลตัวอย่าง
-- ที่เทสต์อีกหลายสิบข้อนับจำนวนแถวของมันอยู่
insert into grade_submission (id, class_section_id, term_id, stage)
values ('dddd0000-0000-0000-0000-0000000000f1', 'cccc0000-0000-0000-0000-00000000f001',
        '33333333-3333-3333-3333-333333333332', 'locked'),
       ('dddd0000-0000-0000-0000-0000000000f2', 'bbbb0000-0000-0000-0000-000000000003',
        '33333333-3333-3333-3333-333333333331', 'locked')
on conflict do nothing;

insert into enrollment (id, student_id, class_section_id, term_id, status, counts_toward_gpa)
values
  -- ภาคที่สองของนักศึกษาคนเดิม — เพื่อให้มี "สะสม" ให้ตรวจ
  ('cccc0000-0000-0000-0000-0000000000f1', 'aaaa0000-0000-0000-0000-000000000011',
   'cccc0000-0000-0000-0000-00000000f001', '33333333-3333-3333-3333-333333333332',
   'enrolled', true),
  -- รายวิชาเทียบโอน — ขึ้นใบ รบ. แต่ไม่นับ GPA
  ('cccc0000-0000-0000-0000-0000000000f2', 'aaaa0000-0000-0000-0000-000000000011',
   'bbbb0000-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333331',
   'credit_transfer', false)
on conflict do nothing;

insert into enrollment_result
  (id, enrollment_id, submission_id, revision, raw_score, attendance_pct,
   grade_symbol_id, grade_point, credits_earned)
select 'eeee0000-0000-0000-0000-0000000000f1', 'cccc0000-0000-0000-0000-0000000000f1',
       'dddd0000-0000-0000-0000-0000000000f1', 1, 75.0, 90.00, gs.id, gs.grade_point, 2.0
  from grade_symbol gs
 where gs.grade_scheme_id = '44444444-4444-4444-4444-444444444444' and gs.symbol = '3.0'
on conflict do nothing;

insert into enrollment_result
  (id, enrollment_id, submission_id, revision, raw_score, attendance_pct,
   grade_symbol_id, grade_point, credits_earned)
select 'eeee0000-0000-0000-0000-0000000000f2', 'cccc0000-0000-0000-0000-0000000000f2',
       'dddd0000-0000-0000-0000-0000000000f2', 1, 95.0, 100.00, gs.id, gs.grade_point, 2.0
  from grade_symbol gs
 where gs.grade_scheme_id = '44444444-4444-4444-4444-444444444444' and gs.symbol = '4.0'
 order by gs.id limit 1
on conflict do nothing;

-- ─── ตัวเลขใน seed ไม่เคยตรงกับผลการเรียนของ seed เอง ───
-- `term_summary` ใน seed เขียนด้วยมือ (ภาค 1 เป็น gpa 3.00 · หน่วยกิต 4.0)
-- แต่ผลการเรียนที่ seed ใส่ไว้ให้นักศึกษาคนเดียวกันคือ 2.5 กับ ข.ร.
-- ซึ่ง `compute_term_summary()` คิดได้ 1.25 · หน่วยกิต 2.0 — ต่างกันมาก
-- ไม่มีอะไรฟ้องเพราะไม่เคยมีเทสต์ไหนเอาสองฝั่งมาเทียบกัน (TEST 266 เป็นตัวแรก)
-- การเรียกที่นี่จึงทำให้ข้อมูลตรงกับตัวเองก่อนเริ่มตรวจ
select compute_term_summary('33333333-3333-3333-3333-333333333331') as term1_rows,
       compute_term_summary('33333333-3333-3333-3333-333333333332') as term2_rows \gset

-- ── TEST 264 ───────────────────────────────────────────────────────
-- โครงภาคเรียนต้องมีรายวิชาครบเท่ากับที่แบบแบนมี
--
-- ถ้าจัดกลุ่มแล้ววิชาหาย ใบจะพิมพ์ตารางที่ดูสมบูรณ์ทุกประการแต่ขาดวิชา
-- ที่นักศึกษาเรียนจริง — และหน่วยกิตรวมหัวใบยังถูกอยู่ จึงมองไม่ออก
do $$
declare
  v_stu uuid; v_tree jsonb; v_terms integer;
  v_in_tree integer; v_flat integer;
begin
  select e.student_id into v_stu
    from enrollment e
    join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
   group by e.student_id order by count(*) desc, e.student_id limit 1;

  if v_stu is null then
    raise exception 'TEST 264 ล้มเหลว: ไม่มีนักศึกษาที่มีผลการเรียนให้ทดสอบ';
  end if;

  v_tree  := transcript_term_tree(v_stu);
  v_terms := jsonb_array_length(v_tree);

  select count(*) into v_flat from transcript_data(v_stu);

  select coalesce(sum(jsonb_array_length(t -> 'courses')), 0) into v_in_tree
    from jsonb_array_elements(v_tree) t;

  if v_terms = 0 then
    raise exception 'TEST 264 ล้มเหลว: โครงภาคเรียนว่างเปล่าทั้งที่มีผลการเรียน % รายวิชา', v_flat;
  end if;

  if v_in_tree <> v_flat then
    raise exception 'TEST 264 ล้มเหลว: ในโครงมี % รายวิชา แต่แบบแบนมี % '
                    '— มีวิชาหายไประหว่างจัดตามภาคเรียน', v_in_tree, v_flat;
  end if;

  raise notice 'TEST 264 ผ่าน — % ภาคเรียน · % รายวิชา ครบทั้งสองทาง', v_terms, v_in_tree;
end $$;

-- ── TEST 265 ───────────────────────────────────────────────────────
-- หน่วยกิตสะสมต้องเป็นผลรวมย้อนหลัง ไม่ใช่หน่วยกิตของภาคนั้นซ้ำสองครั้ง
--
-- นี่คือข้อผิดพลาดที่แม่แบบตระกูล 67 มีอยู่จริงจนถึง 0060 — พิมพ์
-- "หน่วยกิตที่ได้ในภาค 11 หน่วยกิตสะสม 11" ทั้งที่ควรเป็น 11 กับ 28
-- ตัวเลขผิดบนเอกสารที่แก้ไม่ได้ และไม่มีอะไรฟ้องเพราะทั้งคู่เป็นตัวเลข
-- ที่ดูสมเหตุสมผล
do $$
declare
  v_stu uuid; v_tree jsonb; v_prev numeric := null;
  v_running numeric := 0; r record; v_checked integer := 0;
begin
  select ts.student_id into v_stu
    from term_summary ts
   group by ts.student_id
  having count(*) >= 2
   order by count(*) desc, ts.student_id limit 1;

  if v_stu is null then
    raise exception 'TEST 265 ล้มเหลว: ไม่มีนักศึกษาที่มียอดสรุปตั้งแต่สองภาคขึ้นไป '
                    '— เทสต์นี้พิสูจน์อะไรไม่ได้เลยถ้ามีภาคเดียว';
  end if;

  v_tree := transcript_term_tree(v_stu);

  for r in
    select (t ->> 'year_be')::int         as year_be,
           (t ->> 'ordinal')::int         as ordinal,
           (t ->> 'credits_earned')::numeric as earned,
           (t ->> 'credits_cum')::numeric    as cum
      from jsonb_array_elements(v_tree) with ordinality as a(t, i)
     order by a.i
  loop
    v_running := v_running + coalesce(r.earned, 0);
    if r.cum is distinct from v_running then
      raise exception 'TEST 265 ล้มเหลว: ภาค %/% หน่วยกิตสะสมเป็น % '
                      'แต่ผลรวมย้อนหลังคือ %', r.ordinal, r.year_be, r.cum, v_running;
    end if;
    -- ค่าสะสมต้องไม่ลดลง มิฉะนั้นเรียงภาคผิด
    if v_prev is not null and r.cum < v_prev then
      raise exception 'TEST 265 ล้มเหลว: หน่วยกิตสะสมลดลงจาก % เป็น % ที่ภาค %/%',
                      v_prev, r.cum, r.ordinal, r.year_be;
    end if;
    v_prev := r.cum;
    v_checked := v_checked + 1;
  end loop;

  raise notice 'TEST 265 ผ่าน — ตรวจ % ภาค หน่วยกิตสะสมสุดท้าย %', v_checked, v_prev;
end $$;

-- ── TEST 266 ───────────────────────────────────────────────────────
-- คอลัมน์ (1)×(2) ต้องบวกแล้วหารได้ GPA ที่พิมพ์อยู่บรรทัดถัดไป
--
-- ─── ทำไมข้อนี้สำคัญกว่าที่เห็น ───
-- `compute_term_summary()` กรองด้วยทั้ง grade_symbol.counts_in_gpa และ
-- enrollment.counts_toward_gpa ถ้าคอลัมน์ผลคูณกรองไม่ครบ ใบของนักศึกษาที่มี
-- วิชาเทียบโอน (ปวส. เกือบทุกคน) จะบวกได้ค่าที่ไม่ตรงกับ GPA บนใบเดียวกัน
do $$
declare
  v_stu uuid; v_tree jsonb; r record;
  v_num numeric; v_den numeric; v_calc numeric; v_checked integer := 0;
begin
  select ts.student_id into v_stu
    from term_summary ts
   where ts.gpa is not null
   group by ts.student_id
   order by count(*) desc, ts.student_id limit 1;

  if v_stu is null then
    raise exception 'TEST 266 ล้มเหลว: ไม่มีนักศึกษาที่มี GPA รายภาคให้เทียบ';
  end if;

  v_tree := transcript_term_tree(v_stu);

  for r in
    select (t ->> 'year_be')::int  as year_be,
           (t ->> 'ordinal')::int  as ordinal,
           (t ->> 'gpa')::numeric  as gpa,
           t -> 'courses'          as courses
      from jsonb_array_elements(v_tree) as a(t)
     where t ->> 'gpa' is not null
  loop
    select sum((c ->> 'grade_points')::numeric),
           sum((c ->> 'credits')::numeric) filter (where (c ->> 'counts_in_gpa')::boolean)
      into v_num, v_den
      from jsonb_array_elements(r.courses) as b(c);

    if coalesce(v_den, 0) = 0 then
      raise exception 'TEST 266 ล้มเหลว: ภาค %/% มี GPA % แต่ไม่มีหน่วยกิตที่นับ GPA เลย',
                      r.ordinal, r.year_be, r.gpa;
    end if;

    v_calc := round(v_num / v_den, 2);
    if v_calc is distinct from r.gpa then
      raise exception 'TEST 266 ล้มเหลว: ภาค %/% คอลัมน์ผลคูณบวกแล้วหารได้ % '
                      'แต่ GPA ที่เก็บไว้คือ % — ใบจะขัดแย้งกันเองบนกระดาษแผ่นเดียว',
                      r.ordinal, r.year_be, v_calc, r.gpa;
    end if;
    v_checked := v_checked + 1;
  end loop;

  if v_checked = 0 then
    raise exception 'TEST 266 ล้มเหลว: ไม่ได้เทียบสักภาค — เทสต์ที่ไม่ได้ตรวจอะไรคือเทสต์ที่เขียวเปล่า ๆ';
  end if;

  raise notice 'TEST 266 ผ่าน — คอลัมน์ผลคูณตรงกับ GPA ทั้ง % ภาค', v_checked;
end $$;

-- ── TEST 267 ───────────────────────────────────────────────────────
-- วิชาที่ไม่นับ GPA ต้องไม่มีผลคูณ (แม่แบบพิมพ์ "-")
--
-- ถ้าคืน 0 มาแทน null ใบจะพิมพ์ "0.0" ในช่องผลคูณของวิชากิจกรรม
-- ซึ่งอ่านได้ว่า "ได้ศูนย์" คนละเรื่องกับ "ผ่านแบบไม่คิดแต้ม"
do $$
declare v_bad integer; v_n integer;
begin
  select count(*) into v_bad
    from student s, lateral transcript_data(s.id) td
   where td.counts_in_gpa is false
     and td.grade_points is not null;

  if v_bad > 0 then
    raise exception 'TEST 267 ล้มเหลว: มี % รายวิชาที่ไม่นับ GPA แต่ยังมีผลคูณติดมา', v_bad;
  end if;

  select count(*) into v_bad
    from student s, lateral transcript_data(s.id) td
   where td.counts_in_gpa
     and td.grade_point is not null
     and td.grade_points is distinct from td.grade_point * td.credits;

  if v_bad > 0 then
    raise exception 'TEST 267 ล้มเหลว: มี % รายวิชาที่ผลคูณไม่เท่ากับหน่วยกิต × ระดับผลการเรียน', v_bad;
  end if;

  -- ต้องมีวิชาที่ไม่นับ GPA อยู่จริงอย่างน้อยหนึ่ง มิฉะนั้นสองข้อข้างบน
  -- ผ่านเพราะไม่มีอะไรให้ตรวจ ไม่ใช่เพราะถูก
  select count(*) into v_n
    from student s, lateral transcript_data(s.id) td
   where td.counts_in_gpa is false;
  if v_n = 0 then
    raise exception 'TEST 267 ล้มเหลว: ไม่มีรายวิชาที่ไม่นับ GPA เลยสักตัว '
                    '— ข้อที่แล้วจึงผ่านโดยไม่ได้ตรวจอะไร';
  end if;

  select count(*) into v_n
    from student s, lateral transcript_data(s.id) td;
  if v_n = 0 then
    raise exception 'TEST 267 ล้มเหลว: ไม่มีรายวิชาให้ตรวจเลย';
  end if;

  raise notice 'TEST 267 ผ่าน — ตรวจ % รายวิชา ผลคูณตรงกับสูตรและวิชาที่ไม่นับ GPA ไม่มีผลคูณ', v_n;
end $$;

-- ── TEST 268 ───────────────────────────────────────────────────────
-- ใบที่ออกจริงต้องมีโครงทั้งสองแบบใน payload
--
-- ─── ทำไมต้องมีทั้งสองแบบ ไม่ใช่เลือกตามรุ่นหลักสูตร ───
-- payload ตรึงแล้วแก้ไม่ได้ วันที่วิทยาลัยขอพิมพ์ซ้ำเป็นอีกแบบ
-- (เกิดจริง เช่นที่ทำงานขอฉบับที่จัดตามภาคเรียน) ใบที่เก็บโครงเดียว
-- จะพิมพ์อีกแบบไม่ได้เลยตลอดไป
do $$
declare
  v_stu uuid; v_inst uuid; v_doc issued_document; v_terms integer; v_heads integer;
begin
  select s.id, s.institution_id into v_stu, v_inst
    from student s
    join enrollment e on e.student_id = s.id
    join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
   group by s.id, s.institution_id
   order by count(*) desc, s.id limit 1;

  perform set_config('app.institution_id', v_inst::text, true);
  perform set_config('app.role', 'registrar', true);
  perform set_config('app.person_id',
    (select p.id::text from person p
      join staff st on st.person_id = p.id
      join staff_role sr on sr.staff_id = st.id
     where st.institution_id = v_inst and sr.role in ('registrar','director','admin')
     order by p.id limit 1), true);

  v_doc := issue_document(v_stu, 'transcript', null, null, 'th');

  v_terms := jsonb_array_length(coalesce(v_doc.payload -> 'term_tree', '[]'::jsonb));
  v_heads := jsonb_array_length(coalesce(v_doc.payload -> 'category_tree', '[]'::jsonb));

  if v_terms = 0 then
    raise exception 'TEST 268 ล้มเหลว: payload ของใบที่ออกจริงไม่มี term_tree '
                    '— แม่แบบตระกูล 62 จะพิมพ์ตารางเปล่า';
  end if;
  if v_heads = 0 then
    raise exception 'TEST 268 ล้มเหลว: payload ไม่มี category_tree — การเพิ่มโครงใหม่ทับของเดิม';
  end if;

  raise notice 'TEST 268 ผ่าน — ใบ % มีทั้ง term_tree (% ภาค) และ category_tree (% หมวด)',
               v_doc.doc_no, v_terms, v_heads;
end $$;

-- ── TEST 269 ───────────────────────────────────────────────────────
-- สายเลขไทยกับอังกฤษต้อง **ไม่มีวันชนกัน** ไม่ใช่แค่ "ตอนนี้ไม่เท่ากัน"
--
-- 0057 แยกตัวนับสำเร็จแต่ให้ทั้งสองสายใช้คำนำหน้าเดียวกัน และตัวนับทั้งคู่
-- เริ่มที่ 1 — ฉบับอังกฤษใบแรกจึงได้เลขที่ฉบับไทยใช้ไปแล้ว แล้วล้มด้วย
-- duplicate key TEST 258/259 ไม่จับเพราะออกฉบับไทยไปหลายใบก่อน เลขจึง
-- "ต่างกัน" ตามที่ตรวจ ทั้งที่สิ่งที่ต้องพิสูจน์คือไม่มีวันชนกัน
--
-- ข้อนี้จึงไล่ออกทั้งสองสายจำนวนเท่ากันตั้งแต่ใบแรก แล้วดูว่ามีเลขซ้ำไหม
do $$
declare
  v_inst uuid; v_no text; v_all text[] := '{}'; i integer;
begin
  select id into v_inst from institution order by code limit 1;
  perform set_config('app.institution_id', v_inst::text, true);
  perform set_config('app.role', 'registrar', true);

  for i in 1..5 loop
    v_no := next_document_no('certification', 2599::smallint, 'th');
    v_all := array_append(v_all, v_no);
    v_no := next_document_no('certification', 2599::smallint, 'en');
    v_all := array_append(v_all, v_no);
  end loop;

  if array_length(v_all, 1) <> cardinality(array(select distinct unnest(v_all))) then
    raise exception 'TEST 269 ล้มเหลว: สองสายจ่ายเลขซ้ำกัน — %', v_all;
  end if;

  -- และใบประกาศนียบัตรฉบับไทยต้องยังเป็นตัวเลขล้วนตามระเบียบกระทรวง
  v_no := next_document_no('certificate', 2599::smallint, 'th');
  if v_no !~ '^[0-9]+$' then
    raise exception 'TEST 269 ล้มเหลว: เลขที่ใบประกาศนียบัตรฉบับไทยต้องเป็นตัวเลขล้วน ได้ %', v_no;
  end if;

  raise notice 'TEST 269 ผ่าน — ไล่สองสายพร้อมกัน 5 รอบไม่ซ้ำสักเลข (% … %) · ใบประกาศนียบัตรไทยยังเป็นตัวเลขล้วน %',
               v_all[1], v_all[10], v_no;
end $$;

reset role;

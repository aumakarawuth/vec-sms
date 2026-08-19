-- ═══════════════════════════════════════════════════════════════════
-- 0046_transcript_credit_source.sql
-- ทดสอบเครื่องหมาย (*1)–(*5) และรายวิชาเทียบโอนบนใบ รบ. (0066)
--
-- ─── ทำไมต้องตรวจว่า "ขึ้นใบ" ไม่ใช่แค่ "เก็บได้" ───
-- ก่อน 0066 ตาราง `prior_academic_record` เก็บวิชาเทียบโอนได้ครบทุกช่อง
-- และ `transfer_credits_total()` ก็นับหน่วยกิตให้การตรวจจบถูกต้อง —
-- สิ่งที่ขาดคือใบ รบ. ไม่เคย join ตารางนั้นเข้ามาเลย เทสต์ที่ตรวจว่า
-- "บันทึกได้" จึงเขียวสนิทมาตลอดโดยที่กระดาษยังขาดรายวิชาไปทั้งชุด
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 282 ตารางแปลงเลขเครื่องหมาย ────────────────────────────────
do $$
declare v smallint[];
begin
  v := transcript_note_marks('studied', false, false);
  if array_length(v, 1) is not null then
    raise exception 'TEST 282 ล้มเหลว: เรียนปกติต้องไม่มีเครื่องหมาย ได้ %', v;
  end if;

  v := transcript_note_marks('transferred_grade', false, false);
  if v <> array[1]::smallint[] then
    raise exception 'TEST 282 ล้มเหลว: โอนผลการเรียนต้องได้ (*1) ได้ %', v;
  end if;

  v := transcript_note_marks('transferred_experience', false, false);
  if v <> array[2]::smallint[] then
    raise exception 'TEST 282 ล้มเหลว: เทียบโอนประสบการณ์ต้องได้ (*2) ได้ %', v;
  end if;

  v := transcript_note_marks('regraded', false, false);
  if v <> array[3]::smallint[] then
    raise exception 'TEST 282 ล้มเหลว: เรียนปรับระดับคะแนนต้องได้ (*3) ได้ %', v;
  end if;

  /*
   * ─── ข้อที่ทำให้ต้องแยก enum กับ boolean ───
   * วิชาที่ฝึกในสถานประกอบการและสอนเป็นภาษาอังกฤษต้องได้ทั้ง (*4) และ (*5)
   * ถ้ายัดสามเรื่องเป็น enum ตัวเดียวจะบังคับให้เลือกอย่างใดอย่างหนึ่ง
   * แล้วใบจะบอกความจริงได้ไม่ครบโดยไม่มีใครเห็นว่าขาดอะไรไป
   */
  v := transcript_note_marks('transferred_grade', true, true);
  if v <> array[1, 4, 5]::smallint[] then
    raise exception 'TEST 282 ล้มเหลว: สามเครื่องหมายพร้อมกันต้องได้ 1,4,5 ได้ %', v;
  end if;

  raise notice 'TEST 282 ผ่าน — แปลงครบทั้งห้าเครื่องหมายและซ้อนกันได้';
end $$;

-- ── TEST 283–285 วิชาเทียบโอนขึ้นใบจริง ─────────────────────────────
do $$
declare
  v_student uuid; v_inst uuid; v_course uuid; v_term uuid;
  n integer; v_marks smallint[]; v_payload jsonb; v_notes jsonb;
begin
  perform set_config('app.role', 'registrar', true);

  select e.student_id, s.institution_id
    into v_student, v_inst
    from enrollment e
    join student s on s.id = e.student_id
   group by e.student_id, s.institution_id
   order by count(*) desc
   limit 1;
  perform set_config('app.institution_id', v_inst::text, true);

  select c.id into v_course from course c
   where c.institution_id = v_inst order by c.code limit 1;

  -- ── เตรียมวิชาเทียบโอนหนึ่งตัวที่อนุมัติแล้ว ──
  delete from prior_academic_record where student_id = v_student;
  insert into prior_academic_record
    (student_id, source_th, term_label, course_code, course_name_th,
     credits, grade_symbol, grade_point, counts_in_gpa, earns_credit,
     mapped_course_id, transfer_kind, approved_at)
  values
    (v_student, 'วิทยาลัยเดิม', '1/2566', 'OLD-101', 'วิชาที่โอนผลการเรียนมา',
     3, 'B', 3.0, true, true, v_course, 'transferred_grade', now()),
    (v_student, 'ประสบการณ์ทำงาน', '-', 'EXP-101', 'วิชาที่เทียบโอนประสบการณ์',
     2, 'ผ', null, false, true, null, 'transferred_experience', now());

  /*
   * ── TEST 283 ตระกูล 67 เห็นทั้งสองแถว ──
   *
   * นับด้วย `note_marks` ไม่ใช่ด้วยรหัสวิชา — แถวที่แมปกับรายวิชาของเรา
   * ใช้ **รหัสและชื่อของเรา** ตามที่ตั้งใจ (ใบ รบ. ของเราต้องพิมพ์ชื่อตาม
   * หลักสูตรของเรา ไม่ใช่ชื่อที่สถาบันเดิมใช้เรียก) การค้นด้วย 'OLD-101'
   * จึงหาไม่เจอทั้งที่ทำงานถูกต้อง — รอบแรกของเทสต์นี้พลาดตรงนี้พอดี
   */
  select count(*) into n
    from transcript_courses_grouped(v_student)
   where note_marks && array[1, 2]::smallint[];
  if n <> 2 then
    raise exception 'TEST 283 ล้มเหลว: ตระกูล 67 เห็นวิชาเทียบโอน % แถว ควรได้ 2', n;
  end if;

  select note_marks into v_marks
    from transcript_courses_grouped(v_student)
   where note_marks = array[1]::smallint[]
   limit 1;
  if v_marks is null then
    raise exception 'TEST 283 ล้มเหลว: วิชาที่โอนผลการเรียนไม่ได้เครื่องหมาย (*1)';
  end if;

  -- และวิชาที่แมปแล้วต้องไม่ใช้ชื่อของสถาบันเดิม
  select count(*) into n
    from transcript_courses_grouped(v_student)
   where note_marks = array[1]::smallint[]
     and course_name_th = 'วิชาที่โอนผลการเรียนมา';
  if n > 0 then
    raise exception 'TEST 283 ล้มเหลว: วิชาที่แมปแล้วยังใช้ชื่อของสถาบันเดิม';
  end if;

  -- ── TEST 284 ตระกูล 62 เห็นเหมือนกัน ──
  select count(*) into n
    from transcript_data(v_student)
   where note_marks && array[1, 2]::smallint[];
  if n < 2 then
    raise exception 'TEST 284 ล้มเหลว: ตระกูล 62 เห็นวิชาเทียบโอน % แถว ควรได้ 2', n;
  end if;

  -- วิชาเทียบโอนต้องมีภาคเรียนของ **วิทยาลัยนี้** ไม่ใช่ภาคของสถาบันเดิม
  select count(*) into n from transcript_data(v_student)
   where note_marks && array[1, 2]::smallint[] and term_id is null;
  if n > 0 then
    raise exception 'TEST 284 ล้มเหลว: วิชาเทียบโอน % แถวไม่มีภาคเรียนรองรับ', n;
  end if;

  -- ── TEST 285 เลขเครื่องหมายเข้าถึง payload ──
  --
  -- ข้อนี้คือข้อที่สำคัญที่สุดของไฟล์ เพราะ payload แก้ไม่ได้หลังออกใบ
  -- ถ้าช่องนี้ตกหล่น ใบทุกใบที่ออกไปแล้วจะไม่มีเครื่องหมายตลอดไป
  v_payload := transcript_category_tree(v_student);
  select jsonb_agg(course -> 'notes')
    into v_notes
    from jsonb_array_elements(v_payload) head,
         jsonb_array_elements(head -> 'groups') grp,
         jsonb_array_elements(grp -> 'courses') course
   where course -> 'notes' <> 'null'::jsonb
     and jsonb_array_length(course -> 'notes') > 0;

  if v_notes is null or jsonb_array_length(v_notes) = 0 then
    raise exception 'TEST 285 ล้มเหลว: payload ตระกูล 67 ไม่มีเครื่องหมายสักตัว';
  end if;

  v_payload := transcript_term_tree(v_student);
  select jsonb_agg(course -> 'notes')
    into v_notes
    from jsonb_array_elements(v_payload) term,
         jsonb_array_elements(term -> 'courses') course
   where course -> 'notes' <> 'null'::jsonb
     and jsonb_array_length(course -> 'notes') > 0;

  if v_notes is null or jsonb_array_length(v_notes) = 0 then
    raise exception 'TEST 285 ล้มเหลว: payload ตระกูล 62 ไม่มีเครื่องหมายสักตัว';
  end if;

  raise notice 'TEST 283 ผ่าน — ใบ รบ. ตระกูล 67 แสดงวิชาเทียบโอนพร้อม (*1)';
  raise notice 'TEST 284 ผ่าน — ตระกูล 62 แสดงเหมือนกันและมีภาคเรียนรองรับทุกแถว';
  raise notice 'TEST 285 ผ่าน — เลขเครื่องหมายเข้าถึง payload ทั้งสองตระกูล';

  delete from prior_academic_record where student_id = v_student;
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบเครื่องหมายและวิชาเทียบโอนบนใบ รบ. ครบทุกข้อ ════'; end $$;

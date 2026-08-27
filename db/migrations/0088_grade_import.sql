-- ═══════════════════════════════════════════════════════════════════
-- 0088 — นำเข้าผลการเรียนจากไฟล์ระบบเดิม (finalgrades.csv)
--
-- ─── ทำไมนำเข้าเป็นคะแนนในสมุดคะแนน ไม่ใช่เขียน enrollment_result ตรง ───
-- หลักข้อ 3ก: เกรดเปลี่ยนได้ทางเดียวคือผ่าน `grade_change_request` และ
-- ทางเดียวที่ enrollment_result ถูกเขียนคือ `compute_section_grades()`
-- ที่เรียกจาก `submit_section_grades()` หลังครูกดส่งและผ่านสายอนุมัติ
-- (ครูที่ปรึกษาสาขา → ฝ่ายวิชาการ → ผู้อำนวยการ → ล็อก) ถ้าตัวนำเข้าเขียน
-- enrollment_result ตรง ๆ จะเป็นการเปิดทางที่สองที่ข้ามการอนุมัติทั้งหมด —
-- ใครก็ตามที่นำเข้าไฟล์ได้จะแก้เกรดใครก็ได้โดยไม่ต้องมีใครอนุมัติ (ช่องโหว่
-- แบบเดียวกับข้อ 3ก ที่ CLAUDE.md เตือนไว้สำหรับรอบสอบซ่อม)
--
-- ตัวนำเข้าจึงเขียนแค่ `gradebook_item`/`gradebook_score` — เหมือนครูกรอก
-- คะแนนเอง แล้วยังต้องกด "ส่งเกรด" ที่หน้าสมุดคะแนนและผ่านสายอนุมัติตามปกติ
-- ต่อ ไม่มีอะไรถูกล็อกเป็นผลจริงจากขั้นตอนนำเข้านี้เพียงอย่างเดียว
--
-- ─── ทำไมข้ามแถวที่ไม่มีคะแนนตัวเลข ───
-- ไฟล์จริงมีทั้งแถวที่ยังไม่ตัดเกรด ("-") และแถวที่มีแต่สัญลักษณ์ผลการเรียน
-- โดยไม่มีคะแนน (เช่น ข.ร./ผ./ข.ส. — ขาดสอบ/ผ่านแบบไม่มีคะแนน/ขาดส่งงาน)
-- `gradebook_score.score` เป็นตัวเลขเท่านั้น ไม่มีที่เก็บสัญลักษณ์พวกนี้ตรง ๆ
-- การเดาตัวเลขแทนสัญลักษณ์คือการปั้นข้อมูลที่ไม่มีอยู่จริง (หลักข้อ 5)
-- ชั้น API จึงกรองแถวที่ไม่มีคะแนนตัวเลขทิ้งตั้งแต่ก่อนส่งเข้ามา เจ้าหน้าที่
-- ต้องกรอกแถวเหล่านั้นเองที่หน้าสมุดคะแนนตามปกติ
--
-- ─── ทำไม 1 รายการต่อกลุ่มเรียน น้ำหนักเต็ม 100 ───
-- ไฟล์มีแค่ "คะแนนรวม" ต่อวิชาต่อคน ไม่มีคะแนนย่อยแยกชิ้นงาน จึงสร้าง
-- `gradebook_item` ชื่อ "คะแนนนำเข้าจากไฟล์เดิม" ตัวเดียวต่อกลุ่มเรียน
-- (max_score=100, weight=100) แล้วใส่คะแนนที่ได้ตรง ๆ — ถ้ากลุ่มเรียนนั้น
-- มีชิ้นงานอื่นอยู่ก่อนแล้ว น้ำหนักรวมจะเกิน 100 ซึ่งเป็นสิ่งที่ผู้ใช้ต้อง
-- ไปจัดการเอง (ปกติควรนำเข้าเฉพาะกลุ่มเรียนที่ยังไม่มีใครกรอกคะแนน)
-- ═══════════════════════════════════════════════════════════════════

alter type import_kind add value if not exists 'grade';

begin;

-- ═══════════════════════════════════════════════════════════════════
-- ตรวจแถว
-- ═══════════════════════════════════════════════════════════════════
create or replace function validate_grade_import_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors      text[] := '{}';
  v_code        text := nullif(btrim(p_payload->>'student_code'), '');
  v_course      text := nullif(btrim(p_payload->>'course_code'), '');
  v_ordinal     text := nullif(btrim(p_payload->>'term_ordinal'), '');
  v_year        text := nullif(btrim(p_payload->>'academic_year_be'), '');
  v_score       text := nullif(btrim(p_payload->>'score'), '');
  v_student_id  uuid;
  v_match_count integer;
  v_locked      boolean;
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสนักศึกษา');
  end if;
  if v_course is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสวิชา');
  end if;
  if v_ordinal is null or v_ordinal !~ '^[1-3]$' then
    v_errors := array_append(v_errors, 'ภาคเรียนต้องเป็น 1, 2 หรือ 3');
  end if;
  if v_year is null or v_year !~ '^\d{4}$' or v_year::int < 2500 or v_year::int > 2700 then
    v_errors := array_append(v_errors, 'ปีการศึกษาต้องเป็นพุทธศักราชสี่หลัก (2500-2700)');
  end if;
  if v_score is null then
    v_errors := array_append(v_errors, 'ไม่มีคะแนน');
  elsif v_score !~ '^\d+(\.\d+)?$' or v_score::numeric < 0 or v_score::numeric > 100 then
    v_errors := array_append(v_errors, format('คะแนน "%s" ต้องเป็นตัวเลข 0-100', v_score));
  end if;

  -- ตรวจต่อไม่ได้ถ้าค่าพื้นฐานยังไม่ครบ
  if cardinality(v_errors) > 0 then
    return v_errors;
  end if;

  select id into v_student_id
    from student where institution_id = p_institution_id and student_code = v_code;
  if v_student_id is null then
    v_errors := array_append(v_errors, format('ไม่พบนักศึกษารหัส %s ในวิทยาลัยนี้', v_code));
    return v_errors;
  end if;

  select count(*), bool_or(cs.is_locked) into v_match_count, v_locked
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join course co        on co.id = cs.course_id
    join term t            on t.id = cs.term_id
    join academic_year ay  on ay.id = t.academic_year_id
   where e.student_id = v_student_id
     and cs.institution_id = p_institution_id
     and co.code = v_course
     and t.ordinal = v_ordinal::smallint
     and ay.year_be = v_year::smallint
     and e.status = 'enrolled';

  if v_match_count = 0 then
    v_errors := array_append(v_errors,
      format('ไม่พบการลงทะเบียนวิชา %s ของนักศึกษา %s ในภาคเรียนที่ %s/%s',
             v_course, v_code, v_ordinal, v_year));
  elsif v_match_count > 1 then
    v_errors := array_append(v_errors,
      format('พบมากกว่าหนึ่งกลุ่มเรียนที่ตรงกันสำหรับวิชา %s ของนักศึกษา %s — ต้องแก้ด้วยมือ',
             v_course, v_code));
  elsif v_locked then
    v_errors := array_append(v_errors,
      'กลุ่มเรียนนี้ล็อกผลการเรียนแล้ว — แก้ไขได้เฉพาะผ่านคำร้องขอแก้เกรดเท่านั้น');
  end if;

  return v_errors;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- นำเข้าจริง — เขียน gradebook_item/gradebook_score ทั้งชุดหรือไม่เขียนเลย
-- ═══════════════════════════════════════════════════════════════════
create or replace function apply_grade_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch    import_batch%rowtype;
  r          record;
  v_bad      integer := 0;
  v_ok       integer := 0;
  v_student_id  uuid;
  v_section_id  uuid;
  v_enrollment_id uuid;
  v_item_id     uuid;
  v_score       record;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'grade' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ผลการเรียน', v_batch.kind;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_grade_import_row(v_batch.institution_id, r.payload);
      update import_row
         set errors = v_errs, ok = (cardinality(v_errs) = 0)
       where id = r.id;
      if cardinality(v_errs) > 0 then v_bad := v_bad + 1; end if;
    end;
  end loop;

  if v_bad > 0 then
    update import_batch
       set status = 'failed', error_rows = v_bad,
           ok_rows = (select count(*) from import_row where batch_id = p_batch_id and ok)
     where id = p_batch_id;
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    select s.id into v_student_id
      from student s
     where s.institution_id = v_batch.institution_id
       and s.student_code = r.payload->>'student_code';

    select cs.id, e.id into v_section_id, v_enrollment_id
      from enrollment e
      join class_section cs on cs.id = e.class_section_id
      join course co        on co.id = cs.course_id
      join term t            on t.id = cs.term_id
      join academic_year ay  on ay.id = t.academic_year_id
     where e.student_id = v_student_id
       and cs.institution_id = v_batch.institution_id
       and co.code = r.payload->>'course_code'
       and t.ordinal = (r.payload->>'term_ordinal')::smallint
       and ay.year_be = (r.payload->>'academic_year_be')::smallint
       and e.status = 'enrolled';

    -- หารายการ "คะแนนนำเข้าจากไฟล์เดิม" ของกลุ่มเรียนนี้ ถ้ายังไม่มีให้สร้าง
    -- ใหม่ — ค้นด้วยชื่อคงที่เพื่อให้รันซ้ำได้โดยไม่สร้างรายการซ้อนทุกครั้ง
    select id into v_item_id
      from gradebook_item
     where class_section_id = v_section_id and name_th = 'คะแนนนำเข้าจากไฟล์เดิม';

    if v_item_id is null then
      insert into gradebook_item
        (class_section_id, name_th, category, max_score, weight, publish_to_student)
      values (v_section_id, 'คะแนนนำเข้าจากไฟล์เดิม', 'final', 100, 100, false)
      returning id into v_item_id;
    end if;

    insert into gradebook_score (gradebook_item_id, enrollment_id, score, recorded_by)
    values (v_item_id, v_enrollment_id, (r.payload->>'score')::numeric, current_actor_id())
    on conflict (gradebook_item_id, enrollment_id) do update set
      score = excluded.score, recorded_by = excluded.recorded_by, recorded_at = now()
    returning id into v_score;

    update import_row set created_ref = v_score.id, ok = true where id = r.id;
    v_ok := v_ok + 1;
  end loop;

  update import_batch
     set status = 'applied', applied_at = now(),
         ok_rows = v_ok, error_rows = 0, total_rows = v_ok
   where id = p_batch_id;

  imported := v_ok;
  failed   := 0;
  return next;
end $$;

comment on function apply_grade_import(uuid) is
  'นำเข้าคะแนนเป็นรายการในสมุดคะแนน (gradebook_item/gradebook_score) — ไม่แตะ enrollment_result '
  'เลย ครูยังต้องกด "ส่งเกรด" และผ่านสายอนุมัติตามปกติเหมือนกรอกเอง (0088)';

commit;

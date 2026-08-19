-- ═══════════════════════════════════════════════════════════════════
-- 0069_academic_history_import.sql
--
-- นำเข้าประวัติการเรียนเดิมเป็นชุด — ปิดช่องที่ import_kind เปิดไว้ตั้งแต่
-- 0023 แต่ไม่มีฟังก์ชันตรวจ/นำเข้าจริงรองรับ
--
-- ─── ทำไมช่องนี้ค้างมาตั้งแต่ 0023 ───
-- `import_kind` มีค่า 'academic_history' และ `prior_academic_record.batch_id`
-- มี FK ไปยัง `import_batch` มาตั้งแต่ต้น แต่ `ImportService.apply()` มีแค่
-- `student` กับ `staff` — ยิง kind นี้ผ่าน `/import` ได้ถึงขั้นสร้างรอบ แต่
-- validate ไม่ตรวจอะไรเลย (ไม่มี validator ให้เลือก จึงข้ามการ update
-- errors/ok ทั้งก้อน) แล้ว apply ปฏิเสธด้วย "ยังไม่รองรับชนิดนี้" เสมอ
-- เป็นรูปเดียวกับ `take_usage_snapshot()` และ `generate_class_meetings()`
-- ที่ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น
--
-- ทางเข้าที่ใช้งานได้จริงตอนนี้มีแต่ `POST /prior-records` (เพิ่มทีละคน/
-- ทีละไม่กี่รายการ ต้องรู้ student UUID) ซึ่งใช้ตอนรับนักศึกษาย้ายเข้าคนเดียว
-- แต่วิทยาลัยที่ย้ายมาใช้ระบบนี้มีนักศึกษาเทียบโอนหลักร้อยพร้อมกัน — วางเป็น
-- ตารางจากตารางคะแนนเดิมทีเดียวเหมือนนำเข้านักศึกษา/บุคลากร ต้องมีฟังก์ชัน
-- คู่นี้เพื่อให้ `/import` กับ kind='academic_history' ใช้งานได้จริง
--
-- ─── ทำไมต้องตรวจว่านักศึกษามีอยู่แล้ว (สลับขั้วกับ validate_student_row) ───
-- การนำเข้านักศึกษาใหม่ต้องไม่ให้รหัสซ้ำของเดิม แต่ประวัติการเรียนเดิม
-- ต้องผูกกับนักศึกษาที่**มีอยู่แล้ว**ในระบบเท่านั้น — แถวที่ชี้รหัสไม่มีจริง
-- จะสร้างประวัติลอย ๆ ที่ไม่มีใครเป็นเจ้าของ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจข้อมูลประวัติการเรียนเดิมหนึ่งแถว — คืนปัญหาทั้งหมด ไม่หยุดที่ข้อแรก
-- เหตุผลเดียวกับ validate_student_row
-- ───────────────────────────────────────────────────────────────────
create or replace function validate_academic_history_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors  text[] := '{}';
  v_code    text := nullif(btrim(p_payload->>'student_code'), '');
  v_student uuid;
  v_source  text := nullif(btrim(p_payload->>'source_th'), '');
  v_term    text := nullif(btrim(p_payload->>'term_label'), '');
  v_course  text := nullif(btrim(p_payload->>'course_code'), '');
  v_name    text := nullif(btrim(p_payload->>'course_name_th'), '');
  v_credits text := p_payload->>'credits';
  v_symbol  text := nullif(btrim(p_payload->>'grade_symbol'), '');
  v_point   text := nullif(p_payload->>'grade_point', '');
  v_kind    text := nullif(btrim(p_payload->>'transfer_kind'), '');
  v_mapped  text := nullif(btrim(p_payload->>'mapped_course_code'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวนักศึกษา');
  else
    select id into v_student from student
     where institution_id = p_institution_id and student_code = v_code;
    if v_student is null then
      v_errors := array_append(v_errors, format('ไม่พบนักศึกษารหัส %s ในวิทยาลัยนี้', v_code));
    end if;
  end if;

  if v_source is null then v_errors := array_append(v_errors, 'ไม่มีชื่อสถานศึกษาเดิม'); end if;
  if v_course is null then v_errors := array_append(v_errors, 'ไม่มีรหัสวิชา'); end if;
  if v_name   is null then v_errors := array_append(v_errors, 'ไม่มีชื่อวิชา'); end if;
  if v_symbol is null then v_errors := array_append(v_errors, 'ไม่มีสัญลักษณ์ผลการเรียน'); end if;

  if v_credits is null or v_credits !~ '^\d+(\.\d)?$' or v_credits::numeric <= 0 then
    v_errors := array_append(v_errors, 'หน่วยกิตต้องเป็นตัวเลขมากกว่าศูนย์');
  end if;

  if v_point is not null
     and (v_point !~ '^\d+(\.\d)?$' or v_point::numeric < 0 or v_point::numeric > 4) then
    v_errors := array_append(v_errors, 'แต้มระดับคะแนนต้องเป็นตัวเลขระหว่าง 0.0-4.0');
  end if;

  if v_kind is not null and v_kind not in ('transferred_grade', 'transferred_experience') then
    v_errors := array_append(v_errors,
      format('ชนิดการโอน "%s" ไม่ถูกต้อง — ต้องเป็น transferred_grade หรือ transferred_experience', v_kind));
  end if;

  if v_mapped is not null and not exists (
       select 1 from course where institution_id = p_institution_id and code = v_mapped) then
    v_errors := array_append(v_errors, format('ไม่พบรายวิชารหัส %s ในหลักสูตรของวิทยาลัยนี้', v_mapped));
  end if;

  -- ซ้ำกับประวัติที่มีอยู่แล้ว — ตรวจเฉพาะเมื่อมีภาคเรียนระบุ เพราะ unique
  -- constraint ของตารางไม่ถือว่า term_label เป็น NULL สองแถวซ้ำกัน
  if v_student is not null and v_course is not null and v_term is not null
     and exists (select 1 from prior_academic_record
                  where student_id = v_student and course_code = v_course and term_label = v_term) then
    v_errors := array_append(v_errors,
      format('มีประวัติวิชา %s ภาค %s ของนักศึกษาคนนี้อยู่แล้ว', v_course, v_term));
  end if;

  return v_errors;
end $$;

comment on function validate_academic_history_row(uuid, jsonb) is
  'ตรวจแถวประวัติการเรียนเดิมก่อนนำเข้า — นักศึกษาต้องมีอยู่แล้วในระบบ (สลับขั้วกับ validate_student_row ที่ห้ามรหัสซ้ำ)';

-- ───────────────────────────────────────────────────────────────────
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย เหตุผลเดียวกับ apply_student_import
--
-- ผูก batch_id กับทุกแถวที่สร้าง เพื่อให้ตอบได้ว่าแถวไหนมาจากไฟล์ไหนเมื่อไร
-- เหมือน import_batch ทุกชนิด — ต่างจาก POST /prior-records ที่เพิ่มทีละคน
-- ซึ่งไม่ผูก batch เพราะไม่มีไฟล์ต้นทางให้ตามรอย
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_academic_history_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch   import_batch%rowtype;
  r         record;
  v_student uuid;
  v_mapped  uuid;
  v_kind    text;
  v_prior   uuid;
  v_bad     integer := 0;
  v_ok      integer := 0;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'academic_history' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ประวัติการเรียนเดิม', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_academic_history_row(v_batch.institution_id, r.payload);
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
    -- ข้อความไม่ชี้ไปที่ import_row เพราะ raise rollback การเขียน errors ข้างบนไปด้วย
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    select id into v_student from student
     where institution_id = v_batch.institution_id
       and student_code = btrim(r.payload->>'student_code');

    v_mapped := null;
    if nullif(btrim(r.payload->>'mapped_course_code'), '') is not null then
      select id into v_mapped from course
       where institution_id = v_batch.institution_id
         and code = btrim(r.payload->>'mapped_course_code')
       order by edition_be desc limit 1;
    end if;

    v_kind := coalesce(nullif(btrim(r.payload->>'transfer_kind'), ''), 'transferred_experience');

    insert into prior_academic_record
      (student_id, batch_id, source_th, term_label, course_code, course_name_th,
       credits, grade_symbol, grade_point, mapped_course_id, transfer_kind, counts_in_gpa, note)
    values (
      v_student, p_batch_id,
      btrim(r.payload->>'source_th'),
      nullif(btrim(r.payload->>'term_label'), ''),
      btrim(r.payload->>'course_code'),
      btrim(r.payload->>'course_name_th'),
      (r.payload->>'credits')::numeric,
      btrim(r.payload->>'grade_symbol'),
      nullif(r.payload->>'grade_point', '')::numeric,
      v_mapped,
      v_kind::credit_source_kind,
      -- โอนผลการเรียนยกเกรดเดิมมาด้วย จึงนับ GPA · เทียบโอนความรู้และ
      -- ประสบการณ์ให้หน่วยกิตอย่างเดียว หลักเดียวกับ ImportService.addPriorRecords
      v_kind = 'transferred_grade',
      nullif(btrim(r.payload->>'note'), '')
    )
    returning id into v_prior;

    update import_row set created_ref = v_prior, ok = true where id = r.id;
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

comment on function apply_academic_history_import(uuid) is
  'นำเข้าประวัติการเรียนเดิมทั้งชุด — มีแถวใดผิดจะไม่เขียนอะไรเลย และผูก batch_id กับทุกแถวที่สร้างเพื่อตามรอยได้';

commit;

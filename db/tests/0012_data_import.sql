-- ═══════════════════════════════════════════════════════════════════
-- 0012_data_import.sql
-- ทดสอบการนำเข้าข้อมูลนักศึกษาและประวัติการเรียน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 102 ───────────────────────────────────────────────────────
-- ตรวจหลักที่ 13 ของเลขประจำตัวประชาชน
do $$
begin
  -- 3845663218456 คำนวณหลักที่ 13 มาแล้วว่าถูกต้อง
  if not thai_national_id_valid('3845663218456') then
    raise exception 'TEST 102 ล้มเหลว: เลขที่ถูกต้องถูกปฏิเสธ';
  end if;
  if thai_national_id_valid('3845663218457') then
    raise exception 'TEST 102 ล้มเหลว: เลขที่หลักตรวจผิดถูกยอมรับ';
  end if;
  if thai_national_id_valid('384566321845') then
    raise exception 'TEST 102 ล้มเหลว: เลข 12 หลักถูกยอมรับ';
  end if;
  raise notice 'TEST 102 ผ่าน — ตรวจหลักที่ 13 ของเลขประจำตัวประชาชนได้';
end $$;

-- ── TEST 103 ───────────────────────────────────────────────────────
-- ตรวจแล้วคืนปัญหาทั้งหมดของแถว ไม่ใช่ข้อแรกที่เจอ
--
-- เหตุผลเดียวกับ check_registration() — ถ้าหยุดที่ข้อแรก เจ้าหน้าที่จะต้อง
-- แก้แล้วนำเข้าใหม่หลายรอบ ซึ่งกับไฟล์พันแถวคือการทำงานหลายวัน
do $$
declare v_errs text[];
begin
  v_errs := validate_student_row(
    '11111111-1111-1111-1111-111111111111',
    '{"student_code":"","admitted_year_be":"99","national_id":"1234567890123"}'::jsonb);

  if cardinality(v_errs) < 4 then
    raise exception 'TEST 103 ล้มเหลว: ควรคืนปัญหาอย่างน้อย 4 ข้อ คืน % ข้อ (%)',
      cardinality(v_errs), array_to_string(v_errs, ' · ');
  end if;
  raise notice 'TEST 103 ผ่าน — คืนปัญหาครบ % ข้อในรอบเดียว: %',
    cardinality(v_errs), array_to_string(v_errs, ' · ');
end $$;

-- ── TEST 104 ───────────────────────────────────────────────────────
-- รหัสประจำตัวที่มีอยู่แล้วถูกจับได้
do $$
declare v_errs text[];
begin
  v_errs := validate_student_row(
    '11111111-1111-1111-1111-111111111111',
    '{"student_code":"67201010005","first_name_th":"ทดสอบ","last_name_th":"ซ้ำ",
      "admitted_year_be":"2569"}'::jsonb);

  if not exists (select 1 from unnest(v_errs) e where e like '%มีอยู่ในระบบแล้ว%') then
    raise exception 'TEST 104 ล้มเหลว: รหัสประจำตัวซ้ำไม่ถูกจับ (%)', array_to_string(v_errs, ' · ');
  end if;
  raise notice 'TEST 104 ผ่าน — รหัสประจำตัวที่มีอยู่แล้วถูกจับได้';
end $$;

-- ── TEST 105 ───────────────────────────────────────────────────────
-- มีแถวผิดแม้แถวเดียว ต้องไม่เขียนอะไรลงฐานข้อมูลเลย
--
-- ข้อนี้สำคัญที่สุดในชุด — การนำเข้าที่ล้มเหลวกลางคันแล้วเหลือข้อมูล
-- ครึ่ง ๆ กลาง ๆ แก้ยากกว่าไม่นำเข้าเลย เพราะไม่มีใครรู้ว่าแถวไหนเข้าไปแล้ว
do $$
declare
  v_batch uuid; v_before int; v_after int;
begin
  select count(*) into v_before from student;

  insert into import_batch (institution_id, kind, source_name, total_rows)
  values ('11111111-1111-1111-1111-111111111111', 'student', 'test.xlsx', 3)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, '{"student_code":"69IMP0001","first_name_th":"สมหญิง",
                   "last_name_th":"ตั้งใจเรียน","admitted_year_be":"2569"}'::jsonb),
    (v_batch, 2, '{"student_code":"69IMP0002","first_name_th":"สมศรี",
                   "last_name_th":"ขยันเรียน","admitted_year_be":"2569"}'::jsonb),
    -- แถวนี้ผิด: ไม่มีนามสกุล
    (v_batch, 3, '{"student_code":"69IMP0003","first_name_th":"สมปอง",
                   "admitted_year_be":"2569"}'::jsonb);

  begin
    perform apply_student_import(v_batch);
    raise exception 'TEST 105 ล้มเหลว: นำเข้าได้ทั้งที่มีแถวผิด';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 105%' then raise; end if;
      null;
  end;

  select count(*) into v_after from student;
  if v_after <> v_before then
    raise exception 'TEST 105 ล้มเหลว: เขียนนักศึกษาไป % คนทั้งที่ควรยกเลิกทั้งชุด',
      v_after - v_before;
  end if;

  raise notice 'TEST 105 ผ่าน — มีแถวผิด 1 แถว ไม่เขียนอะไรเลย (นักศึกษายังเท่าเดิม % คน)', v_after;
end $$;

-- ── TEST 106 ───────────────────────────────────────────────────────
-- แก้แถวที่ผิดแล้วนำเข้าได้ครบ
do $$
declare v_batch uuid; v_before int; v_after int; v_imported int;
begin
  select count(*) into v_before from student;

  select id into v_batch from import_batch
   where source_name = 'test.xlsx' order by created_at desc limit 1;

  update import_row
     set payload = payload || '{"last_name_th":"ใจดีมาก"}'::jsonb
   where batch_id = v_batch and row_no = 3;

  select imported into v_imported from apply_student_import(v_batch);

  select count(*) into v_after from student;

  if v_imported <> 3 or v_after - v_before <> 3 then
    raise exception 'TEST 106 ล้มเหลว: ควรนำเข้า 3 คน นำเข้า % และเพิ่มจริง %',
      v_imported, v_after - v_before;
  end if;
  raise notice 'TEST 106 ผ่าน — แก้แถวที่ผิดแล้วนำเข้าครบ % คน', v_imported;
end $$;

-- ── TEST 107 ───────────────────────────────────────────────────────
-- นำเข้าซ้ำรอบเดิมไม่ได้
do $$
declare v_batch uuid;
begin
  select id into v_batch from import_batch
   where source_name = 'test.xlsx' order by created_at desc limit 1;
  begin
    perform apply_student_import(v_batch);
    raise exception 'TEST 107 ล้มเหลว: นำเข้ารอบเดิมซ้ำได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 107%' then raise; end if;
      raise notice 'TEST 107 ผ่าน — %', sqlerrm;
  end;
end $$;

-- ── TEST 108 ───────────────────────────────────────────────────────
-- ไม่เก็บเลขประจำตัวประชาชนแบบอ่านออก เก็บเป็นค่าแฮชที่มีกุญแจ
--
-- ─── ทำไมเทสต์นี้ส่ง national_id_hash_hex มาเอง ไม่ใช่ national_id ตรง ๆ ───
-- 0087 เปลี่ยนสัญญาของ apply_student_import() ให้รับเฉพาะค่าที่เข้ารหัส/
-- แฮชมาแล้วจากชั้น API (ดูคอมเมนต์บนสุดของ 0087) เพราะกุญแจ HMAC
-- (NATIONAL_ID_KEY) อยู่นอกฐานข้อมูลโดยตั้งใจตั้งแต่ 0061 — ถ้าฟังก์ชันนี้
-- แฮชเลขบัตรตรงในฐานข้อมูลเอง (แบบ 0023 เดิม) จะไม่มีกุญแจให้ใช้เลย
-- และย้อนกลับไปเป็นแฮชเปล่าที่ไล่ครบได้ในไม่กี่นาที ซึ่งเป็นช่องโหว่ที่
-- 0061 ปิดไปแล้ว — เทสต์รุ่นเดิมยัง raw `national_id` ตรง ๆ จึงพังตั้งแต่
-- 0087 โดยไม่มีอะไรฟ้องจนกว่าจะรันทั้งชุด (v_hash เป็น null เพราะฟังก์ชัน
-- ไม่เห็น national_id_hash_hex ในเพย์โหลดเลย)
--
-- ค่าเลขฐานสิบหกด้านล่างเป็นค่าจำลอง (ไม่ใช่ HMAC จริงของเลข 13 หลักใด ๆ)
-- เพราะเทสต์ระดับฐานข้อมูลไม่มีกุญแจของชั้น API ให้คำนวณค่าจริง — สิ่งที่
-- ต้องพิสูจน์ตรงนี้คือฟังก์ชัน**ส่งผ่าน**ค่าที่ได้รับมาอย่างถูกต้อง ไม่ใช่
-- ตรวจอัลกอริทึมแฮช (นั่นคือหน้าที่ของเทสต์ฝั่ง API — ดู national-id.ts)
--
-- คอลัมน์ national_id_enc รอเชื่อม KMS จึงยังไม่เขียนเลขจริงลงไปแม้จะส่ง
-- hash มาแล้วก็ตาม (ไม่ส่ง national_id_enc_hex มาในเทสต์นี้)
do $$
declare v_batch uuid; v_hash bytea; v_enc bytea; v_ver smallint;
  v_hash_hex text := 'a1b2c3d4e5f60718293a4b5c6d7e8f90112233445566778899aabbccddeeff';
begin
  insert into import_batch (institution_id, kind, total_rows)
  values ('11111111-1111-1111-1111-111111111111', 'student', 1)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, jsonb_build_object(
      'student_code', '69IMP0009', 'first_name_th', 'มานี', 'last_name_th', 'มีนา',
      'admitted_year_be', '2569', 'national_id', '3845663218456',
      'national_id_hash_hex', v_hash_hex));

  perform apply_student_import(v_batch);

  select p.national_id_hash, p.national_id_enc, p.national_id_hash_v
    into v_hash, v_enc, v_ver
    from person p join student s on s.person_id = p.id
   where s.student_code = '69IMP0009';

  if v_hash is null then
    raise exception 'TEST 108 ล้มเหลว: ไม่ได้เก็บค่าแฮชของเลขประจำตัวประชาชนที่ส่งมาจากชั้น API';
  end if;
  if v_hash <> decode(v_hash_hex, 'hex') then
    raise exception 'TEST 108 ล้มเหลว: ค่าแฮชที่เก็บไม่ตรงกับที่ชั้น API ส่งมา — ฟังก์ชันต้องส่งผ่าน ไม่ใช่คำนวณเอง';
  end if;
  if v_ver <> 2 then
    raise exception 'TEST 108 ล้มเหลว: national_id_hash_v ต้องเป็น 2 เมื่อมี national_id_hash_hex มาให้';
  end if;
  if v_enc is not null then
    raise exception 'TEST 108 ล้มเหลว: เขียนเลขประจำตัวประชาชนลงคอลัมน์ที่ยังไม่ได้เข้ารหัสจริง';
  end if;
  raise notice 'TEST 108 ผ่าน — ส่งผ่านค่าแฮชที่มีกุญแจจากชั้น API ได้ถูกต้อง ไม่คำนวณแฮชเองในฐานข้อมูล';
end $$;

-- ── TEST 109 ───────────────────────────────────────────────────────
-- ประวัติการเรียนที่นำเข้าไม่ปนกับผลที่ระบบตัดเอง
--
-- enrollment_result ใช้ยันเงินอุดหนุนและออกเอกสารราชการ ถ้าผลที่คนกรอก
-- เข้ามาปนอยู่ในนั้น ตอนตรวจสอบจะแยกไม่ออกว่าแถวไหนระบบคำนวณให้
do $$
declare v_student uuid; v_er_before int; v_er_after int; v_prior int;
begin
  select id into v_student from student where student_code = '69IMP0001';
  select count(*) into v_er_before from enrollment_result;

  insert into prior_academic_record
    (student_id, source_th, term_label, course_code, course_name_th,
     credits, grade_symbol, grade_point)
  values
    (v_student, 'วิทยาลัยเทคนิคเดิม', '2566/1', '20000-1001', 'ภาษาไทยพื้นฐาน', 2, '3.5', 3.5),
    (v_student, 'วิทยาลัยเทคนิคเดิม', '2566/1', '20000-1201', 'ภาษาอังกฤษในชีวิตจริง', 2, '3.0', 3.0);

  select count(*) into v_er_after from enrollment_result;
  select count(*) into v_prior from prior_academic_record where student_id = v_student;

  if v_er_after <> v_er_before then
    raise exception 'TEST 109 ล้มเหลว: ประวัติที่นำเข้าไปเขียนลง enrollment_result ด้วย';
  end if;
  if v_prior <> 2 then
    raise exception 'TEST 109 ล้มเหลว: ควรมีประวัติ 2 รายการ มี %', v_prior;
  end if;
  raise notice 'TEST 109 ผ่าน — ประวัติ % รายการเก็บแยก ไม่ปนกับผลที่ระบบตัดเอง', v_prior;
end $$;

-- ── TEST 110 ───────────────────────────────────────────────────────
-- หน่วยกิตที่ยังไม่อนุมัติเทียบโอนไม่ถูกนับ
--
-- เหมือนชั่วโมงฝึกที่ยังไม่รับรอง — การเทียบโอนเป็นดุลยพินิจของฝ่ายวิชาการ
-- ไม่ใช่ผลอัตโนมัติของการนำเข้าไฟล์
do $$
declare v_student uuid; v_approved numeric; v_pending numeric;
begin
  select id into v_student from student where student_code = '69IMP0001';

  select coalesce(sum(credits) filter (where approved_at is not null), 0),
         coalesce(sum(credits) filter (where approved_at is null), 0)
    into v_approved, v_pending
    from prior_academic_record where student_id = v_student;

  if v_approved <> 0 then
    raise exception 'TEST 110 ล้มเหลว: ยังไม่อนุมัติแต่นับเป็นอนุมัติแล้ว % หน่วยกิต', v_approved;
  end if;
  if v_pending <> 4 then
    raise exception 'TEST 110 ล้มเหลว: ควรรออนุมัติ 4 หน่วยกิต มี %', v_pending;
  end if;

  update prior_academic_record
     set approved_at = now(), approved_by = 'aaaa0000-0000-0000-0000-000000000022'
   where student_id = v_student;

  select coalesce(sum(credits) filter (where approved_at is not null), 0)
    into v_approved from prior_academic_record where student_id = v_student;

  if v_approved <> 4 then
    raise exception 'TEST 110 ล้มเหลว: อนุมัติแล้วควรนับ 4 หน่วยกิต นับ %', v_approved;
  end if;
  raise notice 'TEST 110 ผ่าน — รออนุมัติ 4 นก. ไม่ถูกนับ · อนุมัติแล้วนับ % นก.', v_approved;
end $$;

-- ── TEST 111 ───────────────────────────────────────────────────────
-- บทบาทที่ไม่มีอำนาจนำเข้าข้อมูลไม่ได้
--
-- ถ้าบทบาทอื่นนำเข้าได้ จะสร้างนักศึกษาปลอมเข้าระบบได้ในไฟล์เดียว
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
begin
  begin
    insert into import_batch (institution_id, kind, total_rows)
    values ('11111111-1111-1111-1111-111111111111', 'student', 1);
    raise exception 'TEST 111 ล้มเหลว: ครูสร้างรอบนำเข้าได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 111 ผ่าน — ครูนำเข้าข้อมูลนักศึกษาไม่ได้ ต้องเป็นงานทะเบียนขึ้นไป';
  end;
end $$;
commit;

-- ── TEST 112 ───────────────────────────────────────────────────────
-- วิทยาลัยอื่นไม่เห็นรอบนำเข้าและประวัติการเรียนที่นำเข้า
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_batch int; v_row int; v_prior int;
begin
  select count(*) into v_batch from import_batch;
  select count(*) into v_row   from import_row;
  select count(*) into v_prior from prior_academic_record;

  if v_batch <> 0 or v_row <> 0 or v_prior <> 0 then
    raise exception 'TEST 112 ล้มเหลว: วิทยาลัยอื่นเห็น รอบนำเข้า % · แถว % · ประวัติ %',
      v_batch, v_row, v_prior;
  end if;
  raise notice 'TEST 112 ผ่าน — วิทยาลัยอื่นไม่เห็นข้อมูลการนำเข้าเลย';
end $$;
commit;

\echo ''
\echo '════ ทดสอบการนำเข้าข้อมูลครบทุกข้อ ════'

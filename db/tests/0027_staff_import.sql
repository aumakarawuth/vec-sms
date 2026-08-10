-- ═══════════════════════════════════════════════════════════════════
-- 0027_staff_import.sql
-- ทดสอบการนำเข้าข้อมูลบุคลากร
--
-- ─── สิ่งที่ต่างจากการนำเข้านักศึกษาและต้องคุมให้แน่น ───
-- แถวบุคลากรหนึ่งแถวสร้าง **สิทธิ์** ในระบบ ไม่ใช่แค่ข้อมูล ถ้าไฟล์ตั้ง
-- บทบาทได้อย่างอิสระ ใครที่แก้ไฟล์ระหว่างทางจะแต่งตั้งตัวเองเป็น admin ได้
-- TEST 201 จึงยิงไฟล์ที่ขอบทบาท admin เข้าไปตรง ๆ เพื่อดูว่าถูกปฏิเสธจริง
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select id as inst_id from institution where code = '1300000001' \gset
select code as dept_code from department where institution_id = :'inst_id' limit 1 \gset

-- ── TEST 199 ───────────────────────────────────────────────────────
-- นำเข้าบุคลากรที่ข้อมูลถูกต้อง — ได้ person + staff + สังกัดหน่วยงาน
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_inst  uuid := (select id from institution where code = '1300000001');
  v_dept  text := (select code from department where institution_id = v_inst limit 1);
  v_batch uuid;
  v_res   record;
  v_staff uuid;
  v_pos   text;
begin
  insert into import_batch (institution_id, kind, source_name, total_rows)
  values (v_inst, 'staff', 'บุคลากร-2569.csv', 2)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, jsonb_build_object(
      'staff_code', 'IMP-STAFF-01', 'prefix_th', 'นาย',
      'first_name_th', 'ประสิทธิ์', 'last_name_th', 'ชำนาญกิจ',
      'employment_kind', 'permanent', 'is_teacher', true,
      'department_code', v_dept, 'position_th', 'ครูชำนาญการ')),
    (v_batch, 2, jsonb_build_object(
      'staff_code', 'IMP-STAFF-02', 'prefix_th', 'นางสาว',
      'first_name_th', 'อรวรรณ', 'last_name_th', 'ธุรการดี',
      'employment_kind', 'contract'));

  select * into v_res from apply_staff_import(v_batch);

  if v_res.imported <> 2 then
    raise exception 'TEST 199 ล้มเหลว: นำเข้าได้ % แถว ควรได้ 2', v_res.imported;
  end if;

  select st.id into v_staff from staff st where st.staff_code = 'IMP-STAFF-01';
  if v_staff is null then
    raise exception 'TEST 199 ล้มเหลว: ไม่พบบุคลากรที่นำเข้า';
  end if;

  -- สังกัดหน่วยงานต้องถูกสร้างด้วย ไม่ใช่แค่แถว staff
  select sa.position_th into v_pos from staff_assignment sa where sa.staff_id = v_staff;
  if v_pos is distinct from 'ครูชำนาญการ' then
    raise exception 'TEST 199 ล้มเหลว: ไม่ได้สร้างสังกัดหน่วยงาน (ได้ %)', v_pos;
  end if;

  -- การเป็นครูมาจาก is_teacher ไม่ใช่ staff_role
  if not exists (select 1 from staff st where st.id = v_staff and st.is_teacher) then
    raise exception 'TEST 199 ล้มเหลว: ไม่ได้ตั้ง is_teacher ตามที่ระบุในไฟล์';
  end if;

  -- และการนำเข้าต้องไม่สร้างบทบาทให้ใครเลย ไม่ว่าไฟล์จะเขียนอะไรมา
  if exists (select 1 from staff_role sr where sr.staff_id = v_staff) then
    raise exception 'TEST 199 ล้มเหลว: การนำเข้าสร้างบทบาทให้บุคลากร '
      '(ทุกบทบาทเห็นข้อมูลทั้งวิทยาลัย ต้องแต่งตั้งทีละคนเท่านั้น)';
  end if;

  -- แถวที่ไม่ระบุหน่วยงานต้องไม่มีสังกัด และ is_teacher ต้องเป็น false
  select st.id into v_staff from staff st where st.staff_code = 'IMP-STAFF-02';
  if exists (select 1 from staff_assignment sa where sa.staff_id = v_staff) then
    raise exception 'TEST 199 ล้มเหลว: สร้างสังกัดให้แถวที่ไม่ได้ระบุหน่วยงาน';
  end if;
  if exists (select 1 from staff st where st.id = v_staff and st.is_teacher) then
    raise exception 'TEST 199 ล้มเหลว: ตั้ง is_teacher ให้แถวที่ไม่ได้ระบุ '
      '(คนที่ไม่ได้สอนจะเห็นข้อมูลนักศึกษาไปด้วย)';
  end if;

  raise notice 'TEST 199 ผ่าน — นำเข้าบุคลากร 2 คน พร้อมสังกัด โดยไม่สร้างบทบาทให้ใคร';
end $$;
rollback;

-- ── TEST 200 ───────────────────────────────────────────────────────
-- แถวที่ผิดทำให้ไม่เขียนอะไรเลยทั้งชุด และรายงานปัญหาครบทุกข้อของแถว
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_inst   uuid := (select id from institution where code = '1300000001');
  v_batch  uuid;
  v_errs   text[];
  v_wrote  boolean := false;
  v_before integer;
  v_after  integer;
begin
  select count(*) into v_before from staff where institution_id = v_inst;

  insert into import_batch (institution_id, kind, source_name, total_rows)
  values (v_inst, 'staff', 'ไฟล์ที่ผิด.csv', 2)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    -- แถวนี้ถูกต้อง
    (v_batch, 1, jsonb_build_object(
      'staff_code', 'IMP-OK-01', 'first_name_th', 'สมชาย', 'last_name_th', 'ดีงาม')),
    -- แถวนี้ผิดหลายข้อพร้อมกัน — ต้องรายงานครบ ไม่ใช่หยุดที่ข้อแรก
    (v_batch, 2, jsonb_build_object(
      'first_name_th', '', 'last_name_th', '',
      'national_id', '1234567890123',
      'employment_kind', 'ลูกจ้างชั่วคราว',
      'department_code', 'ไม่มีหน่วยงานนี้', 'position_th', ''));

  /*
   * ตรวจก่อนแล้วค่อยนำเข้า — เป็นลำดับเดียวกับที่ชั้น API ทำจริง
   *
   * ต้องอ่านผลการตรวจจากขั้นนี้ ไม่ใช่จากขั้นนำเข้า เพราะ `raise` ในขั้น
   * นำเข้า rollback การเขียน errors ของตัวเองไปด้วย (ดูคอมเมนต์ใน 0043)
   */
  v_errs := validate_staff_row(v_inst, (select payload from import_row
                                         where batch_id = v_batch and row_no = 2));
  if cardinality(v_errs) < 4 then
    raise exception 'TEST 200 ล้มเหลว: รายงานปัญหาแค่ % ข้อ ควรได้อย่างน้อย 4 — %',
      cardinality(v_errs), array_to_string(v_errs, ' | ');
  end if;

  begin
    perform apply_staff_import(v_batch);
    v_wrote := true;
  exception when raise_exception then null; end;

  if v_wrote then
    raise exception 'TEST 200 ล้มเหลว: นำเข้าสำเร็จทั้งที่มีแถวผิด';
  end if;

  -- ต้องไม่เขียนอะไรเลย แม้แถวที่ 1 จะถูกต้อง
  select count(*) into v_after from staff where institution_id = v_inst;
  if v_after <> v_before then
    raise exception 'TEST 200 ล้มเหลว: เขียนบางแถวไปแล้ว % → % '
      '(ข้อมูลที่เข้าไปครึ่งเดียวแก้ยากกว่าไม่เข้าเลย)', v_before, v_after;
  end if;

  raise notice 'TEST 200 ผ่าน — แถวผิดรายงานครบ % ข้อ และไม่เขียนอะไรเลยสักแถว',
    cardinality(v_errs);
end $$;
rollback;

-- ── TEST 201 ───────────────────────────────────────────────────────
-- ไฟล์นำเข้าตั้งบทบาทที่เห็นข้อมูลทั้งวิทยาลัยไม่ได้
--
-- ข้อนี้คือกำแพงที่สำคัญที่สุดของการนำเข้าบุคลากร — ไฟล์ CSV ผ่านมือ
-- หลายคนและไม่มีใครตรวจทุกแถวด้วยตาก่อนกดนำเข้า ถ้าตั้ง admin ได้จากไฟล์
-- การแต่งตั้งสิทธิ์สูงสุดของระบบจะไม่มีร่องรอยว่าใครเป็นคนอนุมัติ
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_inst  uuid := (select id from institution where code = '1300000001');
  v_batch uuid;
  v_errs  text[];
  v_wrote boolean := false;
begin
  insert into import_batch (institution_id, kind, source_name, total_rows)
  values (v_inst, 'staff', 'แอบตั้ง-admin.csv', 1)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, jsonb_build_object(
      'staff_code', 'IMP-EVIL-01', 'first_name_th', 'ผู้บุกรุก', 'last_name_th', 'ผ่านไฟล์',
      'role', 'admin'));

  -- อ่านผลจากตัวตรวจโดยตรง ไม่ใช่จาก import_row หลังการนำเข้าล้ม
  -- เพราะ raise rollback การเขียน errors ไปด้วย (ดู TEST 200)
  v_errs := validate_staff_row(v_inst, (select payload from import_row
                                         where batch_id = v_batch and row_no = 1));

  begin
    perform apply_staff_import(v_batch);
    v_wrote := true;
  exception when raise_exception then null; end;

  if v_wrote then
    raise exception 'TEST 201 ล้มเหลว: ไฟล์นำเข้าตั้งบทบาท admin ได้ '
      '(ใครแก้ไฟล์ระหว่างทางก็แต่งตั้งตัวเองเป็นผู้ดูแลระบบได้)';
  end if;

  if not exists (select 1 from unnest(v_errs) e where e like '%บทบาท%') then
    raise exception 'TEST 201 ล้มเหลว: ถูกปฏิเสธด้วยเหตุอื่น — %', array_to_string(v_errs, ' | ');
  end if;

  raise notice 'TEST 201 ผ่าน — ไฟล์นำเข้าตั้งบทบาทไม่ได้เลยสักค่า';
end $$;
rollback;

-- ── TEST 202 ───────────────────────────────────────────────────────
-- นำเข้าซ้ำรอบเดิมไม่ได้ และรอบของนักศึกษายิงเข้าตัวนำเข้าบุคลากรไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_inst   uuid := (select id from institution where code = '1300000001');
  v_batch  uuid;
  v_again  boolean := false;
  v_cross  boolean := false;
begin
  insert into import_batch (institution_id, kind, source_name, total_rows)
  values (v_inst, 'staff', 'ซ้ำ.csv', 1)
  returning id into v_batch;

  insert into import_row (batch_id, row_no, payload) values
    (v_batch, 1, jsonb_build_object(
      'staff_code', 'IMP-DUP-01', 'first_name_th', 'ทดสอบ', 'last_name_th', 'ซ้ำ'));

  perform apply_staff_import(v_batch);

  begin
    perform apply_staff_import(v_batch);
    v_again := true;
  exception when raise_exception then null; end;

  if v_again then
    raise exception 'TEST 202 ล้มเหลว: นำเข้ารอบเดิมซ้ำได้ (บุคลากรจะถูกสร้างซ้ำทั้งไฟล์)';
  end if;

  -- รอบของนักศึกษาต้องเข้าตัวนำเข้าบุคลากรไม่ได้
  insert into import_batch (institution_id, kind, source_name, total_rows)
  values (v_inst, 'student', 'นักศึกษา.csv', 0)
  returning id into v_batch;

  begin
    perform apply_staff_import(v_batch);
    v_cross := true;
  exception when raise_exception then null; end;

  if v_cross then
    raise exception 'TEST 202 ล้มเหลว: เอารอบนักศึกษาเข้าตัวนำเข้าบุคลากรได้';
  end if;

  raise notice 'TEST 202 ผ่าน — นำเข้าซ้ำไม่ได้ และชนิดของรอบนำเข้าข้ามกันไม่ได้';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบการนำเข้าบุคลากรครบทุกข้อ ════'; end $$;

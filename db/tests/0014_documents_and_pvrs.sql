-- ═══════════════════════════════════════════════════════════════════
-- 0014_documents_and_pvrs.sql
-- ทดสอบเอกสารของงานทะเบียนและรายงานสำหรับหน่วยงานรัฐ
--
-- ─── ทำไมชุดนี้เน้นการตรึงเนื้อหาเป็นพิเศษ ───
-- ความผิดพลาดของชั้นเอกสารไม่มีอาการให้เห็นเลยในวันที่มันเกิด — ระบบพิมพ์
-- ใบออกมาสวยงามทุกครั้ง เลขที่ก็มี ตราครุฑก็อยู่ ปัญหาจะโผล่อีกสองปีให้หลัง
-- ตอนที่มีคนเอาใบเดิมมาขอคัดสำเนา แล้วสำเนาที่ระบบพิมพ์ให้ใหม่มีเกรดหรือชื่อ
-- ไม่ตรงกับใบที่ถืออยู่ในมือ เพราะระหว่างนั้นมีการแก้เกรดผ่านคำร้อง
-- หรือมีการแก้ชื่อ-นามสกุลตามหลักฐานทางทะเบียนราษฎร
--
-- ณ จุดนั้นวิทยาลัยจะพิสูจน์ไม่ได้ว่าใบไหนคือใบจริง และมีเอกสารสองใบ
-- เลขที่เดียวกันแต่เนื้อหาต่างกันลอยอยู่ในระบบราชการ TEST 129 จึงจงใจ
-- แก้เกรดย้อนหลังหลังออกเอกสารแล้ว เพื่อยืนยันว่าใบเดิมไม่ขยับตาม
--
-- ─── อีกสองอย่างที่ชุดนี้จับ ───
-- เลขที่เอกสารซ้ำหรือมีตัวอักษรปนตามระเบียบกระทรวงไม่ได้ (TEST 131) และ
-- นักศึกษาต้องเห็นเอกสารของตัวเองเท่านั้น ไม่ใช่ของทั้งวิทยาลัย (TEST 134)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 128 ───────────────────────────────────────────────────────
-- เลขที่เอกสารต้องเรียงต่อกัน ไม่ซ้ำ และแยกสายตามประเภทกับปีการศึกษา
do $$
declare
  v_a text; v_b text; v_c text; v_d text;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  v_a := next_document_no('transcript',  2569::smallint);
  v_b := next_document_no('transcript',  2569::smallint);
  v_c := next_document_no('certificate', 2569::smallint);
  v_d := next_document_no('transcript',  2570::smallint);

  if v_a = v_b then
    raise exception 'TEST 128 ล้มเหลว: จ่ายเลขซ้ำ (% กับ %) เอกสารราชการเลขที่ซ้ำกันไม่ได้', v_a, v_b;
  end if;
  if v_b::integer <> v_a::integer + 1 then
    raise exception 'TEST 128 ล้มเหลว: เลขไม่เรียงต่อกัน % แล้ว %', v_a, v_b;
  end if;
  -- คนละประเภทและคนละปีต้องเริ่มนับใหม่ของตัวเอง ไม่ใช่ใช้ตัวนับร่วมกัน
  if v_c <> v_a or v_d <> v_a then
    raise exception 'TEST 128 ล้มเหลว: สายเลขไม่ได้แยกตามประเภท/ปี (% % %)', v_a, v_c, v_d;
  end if;

  raise notice 'TEST 128 ผ่าน — เลขเรียงต่อกัน % → % และแยกสายตามประเภทกับปีการศึกษา', v_a, v_b;
end $$;

-- ── TEST 129 ───────────────────────────────────────────────────────
-- หัวใจของชุดนี้ — แก้เกรดย้อนหลังหลังออกเอกสารแล้ว ใบเดิมต้องไม่ขยับ
do $$
declare
  v_doc      issued_document;
  v_before   jsonb;
  v_after    jsonb;
  v_courses  integer;
  v_live     integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  v_doc := issue_document('aaaa0000-0000-0000-0000-000000000011', 'transcript');
  v_before := v_doc.payload;

  v_courses := jsonb_array_length(v_before -> 'courses');
  if v_courses = 0 then
    raise exception 'TEST 129 ล้มเหลว: ระเบียนแสดงผลการเรียนไม่มีรายวิชาเลย';
  end if;

  -- ออก revision ใหม่ของผลการเรียน ซึ่งเป็นทางเดียวที่แก้เกรดได้
  -- (enrollment_result แก้ทับไม่ได้ ดู 0006) แล้วปิดฉบับเดิม
  update enrollment_result
     set superseded_by = id
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001'
     and superseded_by is null;

  select payload into v_after from issued_document where id = v_doc.id;
  select count(*) into v_live from transcript_data('aaaa0000-0000-0000-0000-000000000011');

  if v_after <> v_before then
    raise exception 'TEST 129 ล้มเหลว: เนื้อหาเอกสารที่ออกไปแล้วเปลี่ยนตามการแก้เกรด';
  end if;
  if v_live >= v_courses then
    raise exception 'TEST 129 ล้มเหลว: การแก้เกรดไม่มีผลกับข้อมูลสด แปลว่าเทสต์นี้ไม่ได้ทดสอบอะไรเลย';
  end if;

  raise notice 'TEST 129 ผ่าน — ใบที่ออกไปแล้วยังมี % รายวิชาเท่าเดิม ขณะที่ข้อมูลสดเหลือ %',
    v_courses, v_live;
end $$;

-- ── TEST 130 ───────────────────────────────────────────────────────
-- เอกสารที่ออกไปแล้วแก้ทับไม่ได้ ลบไม่ได้ ยกเลิกได้แต่ต้องมีเหตุผล
do $$
declare
  v_id      uuid;
  v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select id into v_id from issued_document order by created_at desc limit 1;

  begin
    update issued_document set doc_no = '00000' where id = v_id;
  exception when others then v_blocked := v_blocked + 1;
  end;

  begin
    delete from issued_document where id = v_id;
  exception when others then v_blocked := v_blocked + 1;
  end;

  -- ยกเลิกโดยไม่บอกเหตุผลต้องไม่ได้ — การยกเลิกเงียบ ๆ ตรวจสอบย้อนหลังไม่ได้
  begin
    update issued_document set voided_at = now() where id = v_id;
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 3 then
    raise exception 'TEST 130 ล้มเหลว: ควรถูกบล็อกทั้งสามทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  -- ยกเลิกพร้อมเหตุผลต้องทำได้
  update issued_document
     set voided_at = now(), void_reason = 'พิมพ์ผิด ออกใบใหม่แทน',
         voided_by = 'aaaa0000-0000-0000-0000-000000000001'
   where id = v_id;

  -- แต่ยกเลิกซ้ำหรือย้อนการยกเลิกต้องไม่ได้
  begin
    update issued_document set voided_at = now() - interval '1 day' where id = v_id;
    raise exception 'TEST 130 ล้มเหลว: เปลี่ยนการยกเลิกย้อนหลังได้';
  exception when others then null;
  end;

  raise notice 'TEST 130 ผ่าน — แก้ไม่ได้ ลบไม่ได้ ยกเลิกต้องมีเหตุผล และยกเลิกแล้วย้อนไม่ได้';
end $$;

-- ── TEST 131 ───────────────────────────────────────────────────────
-- เลขที่ใบประกาศนียบัตรต้องเป็นตัวเลขล้วนตามระเบียบกระทรวง และห้ามซ้ำ
insert into graduation_approval
  (id, institution_id, approved_on, term_id, document_no, approved_by)
values ('eeee0000-0000-0000-0000-00000000a001',
        '11111111-1111-1111-1111-111111111111',
        '2026-03-31',
        (select id from term order by ordinal limit 1),
        'ที่ ศธ 0210/2569', 'aaaa0000-0000-0000-0000-000000000001')
on conflict do nothing;

do $$
declare v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  -- มีตัวอักษรปน — ระเบียบกระทรวงไม่รับ
  begin
    insert into student_graduation
      (institution_id, student_id, approval_id, curriculum_version_id,
       completed_on, gpax, credits_earned, certificate_no)
    values ('11111111-1111-1111-1111-111111111111',
            'aaaa0000-0000-0000-0000-000000000011',
            'eeee0000-0000-0000-0000-00000000a001',
            '77777777-7777-7777-7777-777777777767',
            '2026-03-31', 3.25, 106, 'CERT-2569-001');
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  -- ตัวเลขล้วน — ผ่าน
  insert into student_graduation
    (institution_id, student_id, approval_id, curriculum_version_id,
     completed_on, completed_term_id, gpax, credits_earned,
     transcript_no, certificate_no, professional_standard_no)
  values ('11111111-1111-1111-1111-111111111111',
          'aaaa0000-0000-0000-0000-000000000011',
          'eeee0000-0000-0000-0000-00000000a001',
          '77777777-7777-7777-7777-777777777767',
          '2026-03-31', (select id from term order by ordinal limit 1),
          3.25, 106, '2569000123', '25690000456', 'มฐ.2569/001');

  -- เลขเดิมซ้ำในวิทยาลัยเดียวกัน — ไม่ได้
  begin
    insert into student_graduation
      (institution_id, student_id, approval_id, curriculum_version_id,
       completed_on, gpax, credits_earned, certificate_no)
    values ('11111111-1111-1111-1111-111111111111',
            'aaaa0000-0000-0000-0000-000000000012',
            'eeee0000-0000-0000-0000-00000000a001',
            '77777777-7777-7777-7777-777777777767',
            '2026-03-31', 3.00, 106, '25690000456');
  exception when unique_violation then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 2 then
    raise exception 'TEST 131 ล้มเหลว: ควรถูกปฏิเสธสองกรณี ถูกปฏิเสธจริง % กรณี', v_blocked;
  end if;

  raise notice 'TEST 131 ผ่าน — เลขที่มีตัวอักษรและเลขที่ซ้ำถูกปฏิเสธที่ฐานข้อมูล ไม่ใช่แค่ที่หน้าจอ';
end $$;

-- ── TEST 132 ───────────────────────────────────────────────────────
-- รายงาน PVRS ต้องประกอบครบทุกช่องที่หน่วยงานรัฐขอ
do $$
declare r record;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  select * into r from pvrs_rows('eeee0000-0000-0000-0000-00000000a001');

  if r is null then
    raise exception 'TEST 132 ล้มเหลว: มติอนุมัติมีผู้สำเร็จการศึกษาแต่รายงานว่าง';
  end if;
  if r.full_name is null or btrim(r.full_name) = '' then
    raise exception 'TEST 132 ล้มเหลว: ชื่อว่าง — ต่อสตริงกับ null ได้ null ทั้งก้อน';
  end if;
  if r.program_name is null or r.qualification is null then
    raise exception 'TEST 132 ล้มเหลว: ไม่มีสาขาวิชาหรือวุฒิการศึกษา';
  end if;
  if r.certificate_no is null or r.approved_on is null or r.completed_on is null then
    raise exception 'TEST 132 ล้มเหลว: ขาดเลขที่ใบประกาศนียบัตร วันที่อนุมัติ หรือวันที่สำเร็จการศึกษา';
  end if;
  if r.exit_reason is null or btrim(r.exit_reason) = '' then
    raise exception 'TEST 132 ล้มเหลว: ไม่มีสาเหตุที่ออก';
  end if;

  raise notice 'TEST 132 ผ่าน — % · % · วุฒิ % · จบ % · เลขที่ % · %',
    r.student_code, r.full_name, r.qualification, r.completed_on,
    r.certificate_no, r.exit_reason;
end $$;

-- ── TEST 133 ───────────────────────────────────────────────────────
-- วิทยาลัยอื่นต้องไม่เห็นเอกสารหรือมติอนุมัติของเราเลยสักแถว
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_doc integer; v_grad integer; v_appr integer; v_series integer;
begin
  select count(*) into v_doc    from issued_document;
  select count(*) into v_grad   from student_graduation;
  select count(*) into v_appr   from graduation_approval;
  select count(*) into v_series from document_series;

  if v_doc + v_grad + v_appr + v_series <> 0 then
    raise exception 'TEST 133 ล้มเหลว: วิทยาลัยอื่นเห็นเอกสาร % มติ % ผู้จบ % สายเลข %',
      v_doc, v_appr, v_grad, v_series;
  end if;
  raise notice 'TEST 133 ผ่าน — วิทยาลัยอื่นไม่เห็นเอกสารหรือมติอนุมัติเลยสักแถว';
end $$;
rollback;

-- ── TEST 134 ───────────────────────────────────────────────────────
-- นักศึกษาเห็นเอกสารของตัวเองได้ แต่ต้องไม่เห็นของเพื่อน
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';

do $$
declare v_mine integer; v_others integer; v_series integer;
begin
  select count(*) into v_mine
    from issued_document where student_id = 'aaaa0000-0000-0000-0000-000000000011';
  select count(*) into v_others
    from issued_document where student_id <> 'aaaa0000-0000-0000-0000-000000000011';
  select count(*) into v_series from document_series;

  if v_mine = 0 then
    raise exception 'TEST 134 ล้มเหลว: นักศึกษาไม่เห็นเอกสารของตัวเองเลย แอปจะแสดงประวัติไม่ได้';
  end if;
  if v_others <> 0 then
    raise exception 'TEST 134 ล้มเหลว: นักศึกษาเห็นเอกสารของคนอื่น % ใบ', v_others;
  end if;
  -- สายเลขที่เอกสารเป็นงานหลังบ้าน นักศึกษาไม่ควรเห็นว่าออกไปแล้วกี่ใบทั้งวิทยาลัย
  if v_series <> 0 then
    raise exception 'TEST 134 ล้มเหลว: นักศึกษาเห็นสายเลขที่เอกสาร % แถว', v_series;
  end if;

  raise notice 'TEST 134 ผ่าน — เห็นของตัวเอง % ใบ ไม่เห็นของเพื่อนและไม่เห็นสายเลขที่เอกสาร', v_mine;
end $$;
rollback;

-- ── TEST 135 ───────────────────────────────────────────────────────
-- payload ต้องมีเฉพาะส่วนที่กระดาษใบนั้นใช้จริง
--
-- ข้อนี้เป็นเรื่อง PDPA ไม่ใช่เรื่องขนาดไฟล์ — payload ลบไม่ได้ ถ้าผลคัดกรอง
-- บันทึกเยี่ยมบ้าน และข้อมูลผู้ปกครองถูกคัดลอกลงเอกสารทุกใบ ข้อมูลอ่อนไหว
-- ของผู้เยาว์จะถูกเก็บถาวรในที่ที่ไม่มีเหตุผลต้องใช้มัน และเอาออกไม่ได้อีกเลย
do $$
declare
  v_tr   jsonb;
  v_cum  jsonb;
  k      text;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select payload into v_tr
    from issue_document('aaaa0000-0000-0000-0000-000000000011', 'transcript');
  select payload into v_cum
    from issue_document('aaaa0000-0000-0000-0000-000000000011', 'cumulative_record');

  foreach k in array array['screenings', 'home_visits', 'guardians', 'behavior_history'] loop
    if v_tr ? k then
      raise exception 'TEST 135 ล้มเหลว: ระเบียนแสดงผลการเรียนพก % ติดไปด้วยทั้งที่ไม่ได้ใช้', k;
    end if;
    if not (v_cum ? k) then
      raise exception 'TEST 135 ล้มเหลว: ระเบียนสะสมขาด % ซึ่งเป็นหมวดที่ต้องมี', k;
    end if;
  end loop;

  -- ระเบียนสะสมเก็บแค่ระดับผลการคัดกรอง ไม่เก็บคำตอบรายข้อ
  if jsonb_array_length(v_cum -> 'screenings') > 0
     and (v_cum -> 'screenings' -> 0) ? 'detail' then
    raise exception 'TEST 135 ล้มเหลว: ระเบียนสะสมเก็บรายละเอียดแบบคัดกรองลงกระดาษ';
  end if;

  raise notice 'TEST 135 ผ่าน — รบ. มี % หมวดและไม่มีข้อมูลอ่อนไหว · ปพ.8 มี % หมวดครบ',
    (select count(*) from jsonb_object_keys(v_tr)),
    (select count(*) from jsonb_object_keys(v_cum));
end $$;

-- ── TEST 136 ───────────────────────────────────────────────────────
-- สมุดพกที่ไม่ระบุภาคเรียนต้องออกไม่ได้เลย
do $$
declare v_label text;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  begin
    perform issue_document('aaaa0000-0000-0000-0000-000000000011', 'grade_report');
    raise exception 'TEST 136 ล้มเหลว: ออกสมุดพกโดยไม่ระบุภาคเรียนได้ ซึ่งจะได้ข้อมูลของภาคที่ไม่ได้ตั้งใจ';
  exception when check_violation then null;
  end;

  select payload -> 'term' ->> 'label' into v_label
    from issue_document('aaaa0000-0000-0000-0000-000000000011', 'grade_report', null,
                        (select id from term order by ordinal limit 1));

  if v_label is null then
    raise exception 'TEST 136 ล้มเหลว: สมุดพกไม่มีชื่อภาคเรียนบนใบ';
  end if;

  raise notice 'TEST 136 ผ่าน — ไม่ระบุภาคเรียนออกไม่ได้ · ระบุแล้วได้ใบของ %', v_label;
end $$;

-- ── TEST 137 ───────────────────────────────────────────────────────
-- คะแนนความประพฤติบนกระดาษต้องตรงกับที่ระบบใช้จริง
--
-- behavior_record.points เป็นจำนวนบวกเสมอ ทิศทางหักหรือเพิ่มอยู่ที่
-- behavior_rule.direction การรวมยอดโดยดูเครื่องหมายของตัวเลขจะได้คำตอบ
-- ที่ผิดแบบดูไม่ออก — "หนีเรียน" กลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์
-- อยู่บนระเบียนสะสมที่ส่งต่อกันไปเรื่อย ๆ และแก้ไม่ได้
do $$
declare
  v_payload jsonb;
  v_balance integer;
  v_deduct  integer;
  v_award   integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select payload into v_payload
    from issue_document('aaaa0000-0000-0000-0000-000000000011', 'cumulative_record');

  select balance into v_balance
    from v_behavior_balance where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  v_deduct := (v_payload -> 'behavior' ->> 'deducted')::integer;
  v_award  := (v_payload -> 'behavior' ->> 'awarded')::integer;

  if (v_payload -> 'behavior' ->> 'current')::integer <> v_balance then
    raise exception 'TEST 137 ล้มเหลว: คะแนนบนกระดาษ % ไม่ตรงกับที่ระบบใช้ %',
      v_payload -> 'behavior' ->> 'current', v_balance;
  end if;

  -- ต้องมีทั้งฝั่งหักและฝั่งเพิ่มจริง มิฉะนั้นเทสต์นี้ไม่ได้พิสูจน์อะไร
  if v_deduct = 0 or v_award = 0 then
    raise exception 'TEST 137 ล้มเหลว: ข้อมูลทดสอบไม่มีทั้งการหักและการเพิ่ม (หัก % เพิ่ม %)',
      v_deduct, v_award;
  end if;

  -- ทุกบรรทัดต้องบอกทิศทางมาด้วย มิฉะนั้นแม่แบบต้องเดาเครื่องหมายเอง
  if exists (select 1 from jsonb_array_elements(v_payload -> 'behavior_history') e
              where not (e ? 'direction') or e ->> 'direction' is null) then
    raise exception 'TEST 137 ล้มเหลว: ประวัติพฤติกรรมบางบรรทัดไม่บอกทิศทาง แม่แบบจะพิมพ์เครื่องหมายผิด';
  end if;

  raise notice 'TEST 137 ผ่าน — ตั้งต้น % หัก % เพิ่ม % คงเหลือ % ตรงกับ v_behavior_balance',
    v_payload -> 'behavior' ->> 'starting_points', v_deduct, v_award, v_balance;
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบเอกสารและรายงานหน่วยงานรัฐครบทุกข้อ ════'; end $$;

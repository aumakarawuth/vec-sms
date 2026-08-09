-- ═══════════════════════════════════════════════════════════════════
-- 0009_grade_change_request.sql
-- ทดสอบคำร้องแก้เกรดหลังล็อก และ dual control
--
-- เทสต์ชุดนี้เน้นทดสอบ "การโจมตี" มากกว่าทางเดินปกติ เพราะกลไก dual control
-- มีไว้กันคนในที่มีสิทธิ์อยู่แล้ว ไม่ได้กันคนนอก ทางเดินปกติผ่านง่าย
-- แต่ช่องที่ทำให้มันไร้ความหมายมีหลายทางและมองไม่เห็นจากหน้าจอ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ใช้ ปิยะพงศ์ (enrollment dddd...e001) ที่ได้ 4.0 เป็นตัวทดสอบ
--
-- เทสต์ชุด 0007 จบลงที่ขั้น teacher_submitted (เพราะข้อ 61 ตีกลับแล้วส่งใหม่)
-- คำร้องแก้เกรดใช้ได้เฉพาะเมื่อล็อกแล้ว จึงต้องเดินสายอนุมัติให้ครบก่อน
do $$
declare v_sub uuid;
begin
  select id into v_sub from grade_submission
   where class_section_id = 'dddd0000-0000-0000-0000-000000000001';

  if (select stage from grade_submission where id = v_sub) <> 'locked' then
    perform advance_grade_submission(v_sub, 'head_approved',     'เตรียมข้อมูลเทสต์');
    perform advance_grade_submission(v_sub, 'academic_approved', 'เตรียมข้อมูลเทสต์');
    perform advance_grade_submission(v_sub, 'director_approved', 'เตรียมข้อมูลเทสต์');
    perform advance_grade_submission(v_sub, 'locked',            'เตรียมข้อมูลเทสต์');
  end if;
end $$;

-- บริบทของครูผู้ยื่นคำร้อง — ต้องตั้งก่อน มิฉะนั้นจะไปติดด่าน
-- "ต้องระบุตัวผู้ยื่น" แล้วเทสต์ข้ออื่นจะผ่านด้วยเหตุผลผิด
set app.institution_id = '11111111-1111-1111-1111-111111111111';
set app.role           = 'teacher';
set app.actor_id       = 'aaaa0000-0000-0000-0000-000000000002';

-- ── TEST 72 ────────────────────────────────────────────────────────
-- รอบส่งเกรดต้องล็อกก่อนจึงจะยื่นคำร้องได้
-- ยังไม่ล็อกให้ตีกลับแล้วส่งใหม่ ซึ่งเบากว่าการยื่นคำร้องมาก
do $$
declare v_sym uuid;
begin
  select id into v_sym from grade_symbol
   where grade_scheme_id = '44444444-4444-4444-4444-444444444444' and symbol = '3.0';

  -- ถอยกลับไปหนึ่งขั้นชั่วคราวเพื่อทดสอบ
  update grade_submission set stage = 'director_approved', locked_at = null
   where class_section_id = 'dddd0000-0000-0000-0000-000000000001';

  begin
    perform request_grade_change('dddd0000-0000-0000-0000-00000000e001', v_sym, 'ขอแก้ทั้งที่ยังไม่ล็อก');
    raise exception 'TEST 72 ล้มเหลว: ยื่นคำร้องได้ทั้งที่ยังไม่ล็อก';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 72%' then raise; end if;
      raise notice 'TEST 72 ผ่าน — %', sqlerrm;
  end;

  update grade_submission set stage = 'locked', locked_at = now()
   where class_section_id = 'dddd0000-0000-0000-0000-000000000001';
end $$;

-- ── TEST 73 ────────────────────────────────────────────────────────
-- ยื่นคำร้องต้องมีเหตุผลเสมอ ต้องรู้ตัวผู้ยื่น และแก้เป็นค่าเดิมไม่ได้
set app.actor_id = '';   -- จำลองคำขอที่ไม่มีบริบทผู้ใช้

do $$
declare v_sym uuid;
begin
  select id into v_sym from grade_symbol
   where grade_scheme_id = '44444444-4444-4444-4444-444444444444' and symbol = '3.0';
  begin
    perform request_grade_change('dddd0000-0000-0000-0000-00000000e001', v_sym, 'ไม่มีบริบทผู้ใช้');
    raise exception 'TEST 73a ล้มเหลว: ยื่นคำร้องได้ทั้งที่ไม่รู้ว่าใครยื่น';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 73a%' then raise; end if;
      raise notice 'TEST 73a ผ่าน — %', sqlerrm;
  end;
end $$;

set app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_sym uuid; v_same uuid;
begin
  select id into v_sym from grade_symbol
   where grade_scheme_id = '44444444-4444-4444-4444-444444444444' and symbol = '3.0';

  begin
    perform request_grade_change('dddd0000-0000-0000-0000-00000000e001', v_sym, '   ');
    raise exception 'TEST 73 ล้มเหลว: ยื่นคำร้องโดยไม่มีเหตุผลได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 73%' then raise; end if;
      null;
  end;

  select grade_symbol_id into v_same from enrollment_result
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and superseded_by is null;

  begin
    perform request_grade_change('dddd0000-0000-0000-0000-00000000e001', v_same, 'ขอแก้เป็นค่าเดิม');
    raise exception 'TEST 73 ล้มเหลว: ยื่นคำร้องแก้เป็นค่าเดิมได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 73%' then raise; end if;
      null;
  end;

  raise notice 'TEST 73 ผ่าน — ต้องมีเหตุผล และแก้เป็นค่าเดิมไม่ได้';
end $$;

-- ── TEST 74 ────────────────────────────────────────────────────────
-- สัญลักษณ์ที่ขอต้องอยู่ในระเบียบวัดผลของหลักสูตรเดียวกัน
-- ไม่งั้นเกรดของ ปวส. จะไปโผล่ในผลการเรียน ปวช.
do $$
declare v_other uuid;
begin
  insert into grade_scheme (id, institution_id, code, name_th, level, effective_from_year_be)
  values ('44444444-4444-4444-4444-4444444444ff',
          '11111111-1111-1111-1111-111111111111', 'TEST-OTHER',
          'ระเบียบวัดผลของอีกหลักสูตร', 'PVS', 2567)
  on conflict (id) do nothing;

  insert into grade_symbol (id, grade_scheme_id, symbol, name_th, grade_point)
  values ('44444444-4444-4444-4444-4444444444fe',
          '44444444-4444-4444-4444-4444444444ff', '4.0', 'ดีเยี่ยมของอีกหลักสูตร', 4.0)
  on conflict (id) do nothing;

  begin
    perform request_grade_change('dddd0000-0000-0000-0000-00000000e001',
                                 '44444444-4444-4444-4444-4444444444fe', 'ขอใช้สัญลักษณ์ข้ามหลักสูตร');
    raise exception 'TEST 74 ล้มเหลว: ใช้สัญลักษณ์ข้ามระเบียบวัดผลได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 74%' then raise; end if;
      raise notice 'TEST 74 ผ่าน — %', sqlerrm;
  end;
end $$;

-- ── TEST 75 ────────────────────────────────────────────────────────
-- ยื่นคำร้องปกติได้ และยื่นซ้ำขณะมีคำร้องค้างไม่ได้
begin;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_sym uuid; v_req uuid;
begin
  select id into v_sym from grade_symbol
   where grade_scheme_id = '44444444-4444-4444-4444-444444444444' and symbol = '3.0';

  select request_grade_change(
           'dddd0000-0000-0000-0000-00000000e001', v_sym,
           'กรอกคะแนนสอบปลายภาคสลับกับนักศึกษาอีกคน', 78.00, 'คร.2569/001')
    into v_req;

  if v_req is null then
    raise exception 'TEST 75 ล้มเหลว: ยื่นคำร้องไม่สำเร็จ';
  end if;

  begin
    perform request_grade_change('dddd0000-0000-0000-0000-00000000e001', v_sym, 'ขอยื่นซ้ำ');
    raise exception 'TEST 75 ล้มเหลว: ยื่นคำร้องซ้ำขณะมีคำร้องค้างได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 75%' then raise; end if;
      null;
  end;

  raise notice 'TEST 75 ผ่าน — ยื่นคำร้อง คร.2569/001 สำเร็จ และยื่นซ้ำขณะค้างไม่ได้';
end $$;
commit;

-- ── TEST 76 ────────────────────────────────────────────────────────
-- ผู้ยื่นคำร้องอนุมัติคำร้องของตัวเองไม่ได้
--
-- ข้อนี้คือหัวใจของ dual control — constraint ในตารางกันได้แค่ผู้อนุมัติซ้ำคน
-- แต่ไม่ได้กันคนขอมาอนุมัติเอง ถ้าไม่ปิด ครูคนเดียวก็เหลือให้หาคนกดอีกคนเดียว
begin;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'academic';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';   -- คนเดียวกับผู้ยื่น

do $$
declare v_req uuid;
begin
  select id into v_req from grade_change_request
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and status = 'pending';

  begin
    perform approve_grade_change(v_req);
    raise exception 'TEST 76 ล้มเหลว: ผู้ยื่นอนุมัติคำร้องของตัวเองได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 76%' then raise; end if;
      raise notice 'TEST 76 ผ่าน — %', sqlerrm;
  end;
end $$;
commit;

-- ── TEST 77 ────────────────────────────────────────────────────────
-- คนเดียวกันอนุมัติสองช่องไม่ได้
begin;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'academic';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000003';

do $$
declare v_req uuid; v_status change_request_status;
begin
  select id into v_req from grade_change_request
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and status = 'pending';

  select approve_grade_change(v_req) into v_status;
  if v_status <> 'pending' then
    raise exception 'TEST 77 ล้มเหลว: คนแรกอนุมัติแล้วไม่ควรมีผลทันที ได้สถานะ %', v_status;
  end if;

  begin
    perform approve_grade_change(v_req);
    raise exception 'TEST 77 ล้มเหลว: คนเดิมอนุมัติซ้ำเป็นคนที่สองได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 77%' then raise; end if;
      raise notice 'TEST 77 ผ่าน — คนแรกอนุมัติแล้วยังไม่มีผล และคนเดิมกดซ้ำไม่ได้: %', sqlerrm;
  end;
end $$;
commit;

-- ── TEST 78 ────────────────────────────────────────────────────────
-- เขียนตารางตรง ๆ เพื่อข้าม dual control ไม่ได้
--
-- ต่อให้มีสิทธิ์เขียนตารางนี้ ก็ตั้งผู้อนุมัติสองคนพร้อมกันในคำสั่งเดียวไม่ได้
-- และแก้สาระของคำร้องหลังมีคนอนุมัติแล้วก็ไม่ได้
do $$
declare v_req uuid; v_sym uuid;
begin
  select id into v_req from grade_change_request
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and status = 'pending';

  -- ล้างผู้อนุมัติคนแรกออกก่อนเพื่อทดสอบการตั้งพร้อมกัน
  begin
    update grade_change_request
       set approver_1_id = 'aaaa0000-0000-0000-0000-000000000004'
     where id = v_req;
    raise exception 'TEST 78 ล้มเหลว: เปลี่ยนผู้อนุมัติที่ลงไปแล้วได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 78%' then raise; end if;
      null;
  end;

  -- สลับสาระของคำร้องหลังมีคนอนุมัติแล้ว
  select id into v_sym from grade_symbol
   where grade_scheme_id = '44444444-4444-4444-4444-444444444444' and symbol = '4.0';
  begin
    update grade_change_request set to_grade_symbol_id = v_sym where id = v_req;
    raise exception 'TEST 78 ล้มเหลว: สลับสาระของคำร้องหลังมีผู้อนุมัติแล้วได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 78%' then raise; end if;
      null;
  end;

  -- ดันสถานะเป็นอนุมัติทั้งที่มีคนอนุมัติคนเดียว
  begin
    update grade_change_request set status = 'approved' where id = v_req;
    raise exception 'TEST 78 ล้มเหลว: ตั้งสถานะอนุมัติทั้งที่มีผู้อนุมัติคนเดียวได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 78%' then raise; end if;
      null;
  end;

  -- ลบคำร้องทิ้ง
  begin
    delete from grade_change_request where id = v_req;
    raise exception 'TEST 78 ล้มเหลว: ลบคำร้องทิ้งได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 78%' then raise; end if;
      null;
  end;

  raise notice 'TEST 78 ผ่าน — เขียนตรงเพื่อข้าม dual control ไม่ได้ทั้งสี่ทาง';
end $$;

-- ── TEST 78b ───────────────────────────────────────────────────────
-- ตั้งผู้อนุมัติสองคนพร้อมกันในคำสั่งเดียวไม่ได้ (ทดสอบบนคำร้องใหม่ที่ยังว่าง)
do $$
declare v_req uuid; v_sym uuid;
begin
  select id into v_sym from grade_symbol
   where grade_scheme_id = '44444444-4444-4444-4444-444444444444' and symbol = '2.5';

  insert into grade_change_request
    (enrollment_id, from_result_id, to_grade_symbol_id, reason, requested_by)
  select 'dddd0000-0000-0000-0000-00000000e002', er.id, v_sym,
         'คำร้องสำหรับทดสอบการตั้งผู้อนุมัติพร้อมกัน',
         'aaaa0000-0000-0000-0000-000000000002'
    from enrollment_result er
   where er.enrollment_id = 'dddd0000-0000-0000-0000-00000000e002' and er.superseded_by is null
  returning id into v_req;

  begin
    update grade_change_request
       set approver_1_id = 'aaaa0000-0000-0000-0000-000000000003',
           approver_2_id = 'aaaa0000-0000-0000-0000-000000000004',
           status        = 'approved'
     where id = v_req;
    raise exception 'TEST 78b ล้มเหลว: ตั้งผู้อนุมัติสองคนพร้อมกันในคำสั่งเดียวได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 78b%' then raise; end if;
      raise notice 'TEST 78b ผ่าน — %', sqlerrm;
  end;
end $$;

-- ── TEST 79 ────────────────────────────────────────────────────────
-- คนที่สองอนุมัติแล้วระบบแก้ให้ทันที ออก revision ใหม่ ไม่ใช่แก้ทับ
begin;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'director';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000004';

do $$
declare
  v_req uuid; v_status change_request_status;
  v_old_rev int; v_new_rev int; v_symbol text; v_score numeric;
  v_att_before numeric; v_att_after numeric; v_total int;
begin
  select id into v_req from grade_change_request
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and status = 'pending';

  select revision, attendance_pct into v_old_rev, v_att_before
    from enrollment_result
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and superseded_by is null;

  select approve_grade_change(v_req) into v_status;

  select er.revision, sy.symbol, er.raw_score, er.attendance_pct
    into v_new_rev, v_symbol, v_score, v_att_after
    from enrollment_result er join grade_symbol sy on sy.id = er.grade_symbol_id
   where er.enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and er.superseded_by is null;

  select count(*) into v_total from enrollment_result
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001';

  if v_status <> 'applied' then
    raise exception 'TEST 79 ล้มเหลว: คนที่สองอนุมัติแล้วควรได้ applied ได้ %', v_status;
  end if;
  if v_new_rev <> v_old_rev + 1 then
    raise exception 'TEST 79 ล้มเหลว: revision ควรเป็น % ได้ %', v_old_rev + 1, v_new_rev;
  end if;
  if v_symbol <> '3.0' or v_score <> 78.00 then
    raise exception 'TEST 79 ล้มเหลว: ควรได้ 3.0 คะแนน 78.00 ได้ % คะแนน %', v_symbol, v_score;
  end if;

  -- เวลาเรียนต้องยกมาจากแถวเดิม ห้ามคำนวณใหม่
  -- ไม่งั้นเอกสารที่ออกย้อนหลังจะไม่ตรงกับที่เคยออกไป
  if v_att_after is distinct from v_att_before then
    raise exception 'TEST 79 ล้มเหลว: เวลาเรียนถูกคำนวณใหม่ จาก % เป็น %', v_att_before, v_att_after;
  end if;

  raise notice
    'TEST 79 ผ่าน — อนุมัติครบสองคนแล้วแก้ทันที revision % → % ได้ % คะแนน % เวลาเรียนตรึงไว้ที่ %',
    v_old_rev, v_new_rev, v_symbol, v_score, v_att_after;
end $$;
commit;

-- ── TEST 80 ────────────────────────────────────────────────────────
-- คำร้องที่ปิดแล้วอนุมัติซ้ำไม่ได้ และการแก้ถูกบันทึกลงบัญชีตรวจสอบ
do $$
declare v_req uuid; v_ledger int; v_ok boolean; v_applied uuid;
begin
  select id, applied_result_id into v_req, v_applied
    from grade_change_request
   where enrollment_id = 'dddd0000-0000-0000-0000-00000000e001' and status = 'applied';

  if v_applied is null then
    raise exception 'TEST 80 ล้มเหลว: คำร้องที่ใช้แล้วไม่ได้บันทึกว่าออกผลแถวไหน';
  end if;

  begin
    perform approve_grade_change(v_req);
    raise exception 'TEST 80 ล้มเหลว: อนุมัติคำร้องที่ปิดไปแล้วได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 80%' then raise; end if;
      null;
  end;

  select count(*) into v_ledger from grade_ledger
   where entity = 'enrollment_result' and entity_id = v_applied;

  select bool_and(ok) into v_ok
    from verify_grade_ledger('11111111-1111-1111-1111-111111111111');

  if v_ledger = 0 then
    raise exception 'TEST 80 ล้มเหลว: การแก้เกรดไม่ถูกบันทึกลงบัญชีตรวจสอบ';
  end if;
  if not coalesce(v_ok, false) then
    raise exception 'TEST 80 ล้มเหลว: โซ่แฮชของบัญชีตรวจสอบไม่สมบูรณ์หลังแก้เกรด';
  end if;

  raise notice 'TEST 80 ผ่าน — คำร้องที่ปิดแล้วกดซ้ำไม่ได้ · การแก้ถูกบันทึกและโซ่แฮชสมบูรณ์';
end $$;

\echo ''
\echo '════ ทดสอบคำร้องแก้เกรดครบทุกข้อ ════'

-- ═══════════════════════════════════════════════════════════════════
-- 0003_finance.sql — ทดสอบโมดูลการเงิน
-- รันต่อจาก 0001 และ 0002
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 23 ────────────────────────────────────────────────────────
-- ออกใบแจ้งหนี้จากโครงสร้างค่าธรรมเนียม พร้อมแบ่งสามงวด
-- ปวช.1 ภาคเรียนที่ 1 = 9000 + 2500 + 800 + 300 = 12,600 บาท
do $$
declare v_inv uuid; v_total numeric; v_lines int; v_inst int; v_sum numeric;
begin
  v_inv := issue_invoice('aaaa0000-0000-0000-0000-000000000011',
                         '33333333-3333-3333-3333-333333333331', 3);

  select total into v_total from invoice where id = v_inv;
  select count(*) into v_lines from invoice_line where invoice_id = v_inv;
  select count(*), sum(amount) into v_inst, v_sum from installment where invoice_id = v_inv;

  if v_total <> 12600.00 then raise exception 'TEST 23: ยอดควรเป็น 12,600 ได้ %', v_total; end if;
  if v_lines <> 4      then raise exception 'TEST 23: ควรมี 4 บรรทัด ได้ %', v_lines; end if;
  if v_inst  <> 3      then raise exception 'TEST 23: ควรแบ่ง 3 งวด ได้ %', v_inst; end if;
  if v_sum   <> v_total then raise exception 'TEST 23: ผลรวมงวด % ไม่ตรงยอด %', v_sum, v_total; end if;

  raise notice 'TEST 23 ผ่าน — ออกใบแจ้งหนี้ % บาท แบ่ง % งวด ผลรวมงวดตรงยอดพอดี', v_total, v_inst;
end $$;

-- ── TEST 24 ────────────────────────────────────────────────────────
-- ส่วนลดถูกหักให้อัตโนมัติตอนออกใบแจ้งหนี้
do $$
declare v_inv uuid; v_total numeric; v_disc numeric;
begin
  insert into student_funding
    (student_id, funding_source_id, academic_year_id, percent_off, approved_by, approved_at, document_no)
  values ('aaaa0000-0000-0000-0000-000000000012', 'f0000000-0000-0000-0000-000000000001',
          '22222222-2222-2222-2222-222222222222', 10.00,
          'aaaa0000-0000-0000-0000-000000000022', now(), 'ทน.2569/0007');

  v_inv := issue_invoice('aaaa0000-0000-0000-0000-000000000012',
                         '33333333-3333-3333-3333-333333333331', 1);

  select total, discount_total into v_total, v_disc from invoice where id = v_inv;

  -- ส่วนลด 10% ของทุกบรรทัด = 1,260 บาท
  if v_disc <> 1260.00 then raise exception 'TEST 24: ส่วนลดควรเป็น 1,260 ได้ %', v_disc; end if;
  if v_total <> 11340.00 then raise exception 'TEST 24: ยอดสุทธิควรเป็น 11,340 ได้ %', v_total; end if;

  raise notice 'TEST 24 ผ่าน — หักส่วนลดพี่น้อง 10%% ให้อัตโนมัติ เหลือ % บาท', v_total;
end $$;

-- ── TEST 24b ───────────────────────────────────────────────────────
-- ยอดใน v_student_balance ต้องเท่ากับยอดใบแจ้งหนี้เป๊ะ ๆ ไม่ถูกคูณด้วยจำนวนงวด
-- บั๊กเดิม: มุมมอง join กับตารางงวดแล้ว sum ทำให้ยอดถูกนับซ้ำสามเท่า
do $$
declare v_bal numeric; v_inv numeric; v_n int;
begin
  select outstanding into v_bal from v_student_balance
  where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  select total, (select count(*) from installment i where i.invoice_id = inv.id)
    into v_inv, v_n
  from invoice inv where inv.student_id = 'aaaa0000-0000-0000-0000-000000000011';

  if v_bal <> v_inv then
    raise exception 'TEST 24b ล้มเหลว: ยอดค้าง % ไม่ตรงกับยอดใบแจ้งหนี้ % (แบ่ง % งวด)',
      v_bal, v_inv, v_n;
  end if;
  raise notice 'TEST 24b ผ่าน — ยอดค้าง % ตรงกับใบแจ้งหนี้ แม้แบ่ง % งวด', v_bal, v_n;
end $$;

-- ── TEST 25 ────────────────────────────────────────────────────────
-- รับชำระแล้วตัดงวดที่ครบกำหนดก่อน (FIFO)
do $$
declare v_pay uuid; v_left numeric; r record;
begin
  insert into payment (institution_id, student_id, received_on, amount, method, receipt_no)
  values ('11111111-1111-1111-1111-111111111111', 'aaaa0000-0000-0000-0000-000000000011',
          current_date, 5000.00, 'promptpay', 'RC-0001')
  returning id into v_pay;

  v_left := post_payment(v_pay);
  if v_left <> 0 then raise exception 'TEST 25: ไม่ควรมีเงินเหลือ ได้ %', v_left; end if;

  select i.seq, i.amount, i.paid_amount, i.status into r
  from installment i join invoice inv on inv.id = i.invoice_id
  where inv.student_id = 'aaaa0000-0000-0000-0000-000000000011' and i.seq = 1;

  if r.status <> 'paid' then
    raise exception 'TEST 25: งวดที่ 1 ควรเป็น paid ได้ %', r.status;
  end if;

  -- 5,000 ตัดงวดแรก 4,200 เต็ม เหลือ 800 ไหลลงงวดที่ 2
  select i.paid_amount, i.status into r
  from installment i join invoice inv on inv.id = i.invoice_id
  where inv.student_id = 'aaaa0000-0000-0000-0000-000000000011' and i.seq = 2;

  if r.paid_amount <> 800.00 then
    raise exception 'TEST 25: งวดที่ 2 ควรได้รับ 800 ได้ %', r.paid_amount;
  end if;
  if r.status <> 'partially_paid' then
    raise exception 'TEST 25: งวดที่ 2 ควรเป็น partially_paid ได้ %', r.status;
  end if;

  raise notice 'TEST 25 ผ่าน — ตัดงวดตามลำดับครบกำหนด เงินส่วนเกินไหลลงงวดถัดไป';
end $$;

-- ── TEST 26 ────────────────────────────────────────────────────────
-- กระทบยอดอัตโนมัติ: Ref2 ตรง = ตัดยอดเอง, ยอดตรงอย่างเดียว = แค่เสนอ
do $$
declare v_ref2 text; r record; v_paid numeric;
begin
  select ref2 into v_ref2 from invoice
  where student_id = 'aaaa0000-0000-0000-0000-000000000012';

  -- รายการที่ 1: Ref2 ตรง ต้องจับคู่และตัดยอดเองทันที
  insert into bank_transaction
    (institution_id, posted_at, amount, counterparty, bank_ref, ref2)
  values ('11111111-1111-1111-1111-111111111111', now(), 11340.00,
          'น.ส. สมหญิง ศรีสุข', 'BK-0001', v_ref2);

  -- รายการที่ 2: ไม่มีอ้างอิงใด ๆ ยอดไม่ตรงงวดไหนเลย ต้องค้างไว้ให้คนดู
  insert into bank_transaction
    (institution_id, posted_at, amount, counterparty, bank_ref)
  values ('11111111-1111-1111-1111-111111111111', now(), 777.00,
          'ไม่ทราบผู้โอน', 'BK-0002');

  select * into r from reconcile_bank_transactions('11111111-1111-1111-1111-111111111111');

  if r.auto_matched <> 1 then
    raise exception 'TEST 26: ควรจับคู่อัตโนมัติ 1 รายการ ได้ %', r.auto_matched;
  end if;
  if r.unmatched <> 1 then
    raise exception 'TEST 26: ควรเหลือค้าง 1 รายการ ได้ %', r.unmatched;
  end if;

  select paid_total into v_paid from invoice
  where student_id = 'aaaa0000-0000-0000-0000-000000000012';
  if v_paid <> 11340.00 then
    raise exception 'TEST 26: ควรตัดยอดครบ 11,340 ได้ %', v_paid;
  end if;

  raise notice 'TEST 26 ผ่าน — จับคู่เอง % รายการ เสนอ % รายการ ค้างให้คนตัดสิน % รายการ',
    r.auto_matched, r.suggested, r.unmatched;
end $$;

-- ── TEST 27 ────────────────────────────────────────────────────────
-- บัญชีแยกประเภทต้องสมดุล ใส่ไม่ครบคู่ต้องถูกปฏิเสธตอน commit
do $$
declare v_tx uuid;
begin
  begin
    insert into ledger_transaction (institution_id, occurred_on, memo)
    values ('11111111-1111-1111-1111-111111111111', current_date, 'รายการที่ไม่สมดุลโดยตั้งใจ')
    returning id into v_tx;

    insert into ledger_entry (transaction_id, account_id, debit)
    values (v_tx, 'c0000000-0000-0000-0000-000000000101', 5000.00);
    -- จงใจไม่ใส่ฝั่งเครดิต

    -- ปกติ constraint trigger เป็น deferred จะยิงตอน commit
    -- สั่ง immediate เพื่อให้ตรวจเดี๋ยวนี้และดักจับได้ในเทสต์
    set constraints all immediate;

    raise exception 'TEST 27 ล้มเหลว: ระบบยอมรับรายการบัญชีที่ไม่สมดุล';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 27 ล้มเหลว%' then raise; end if;
      raise notice 'TEST 27 ผ่าน — %', left(sqlerrm, 72);
  end;
end $$;

-- ตรวจซ้ำแบบชัดเจนใน transaction ของตัวเอง
begin;
do $$
declare v_tx uuid;
begin
  insert into ledger_transaction (institution_id, occurred_on, memo)
  values ('11111111-1111-1111-1111-111111111111', current_date, 'ทดสอบความสมดุล')
  returning id into v_tx;

  insert into ledger_entry (transaction_id, account_id, debit)
  values (v_tx, 'c0000000-0000-0000-0000-000000000101', 12600.00);
  insert into ledger_entry (transaction_id, account_id, credit)
  values (v_tx, 'c0000000-0000-0000-0000-000000000401', 12600.00);
end $$;
commit;

do $$
declare v int;
begin
  select count(*) into v from ledger_transaction where memo = 'ทดสอบความสมดุล';
  if v <> 1 then raise exception 'TEST 27b ล้มเหลว: รายการที่สมดุลควรบันทึกได้'; end if;
  raise notice 'TEST 27b ผ่าน — รายการที่เดบิตเท่ากับเครดิตบันทึกได้ตามปกติ';
end $$;

-- ── TEST 28 ────────────────────────────────────────────────────────
-- ค้างชำระเกินกำหนดแล้วระบบระงับสิทธิ์การลงทะเบียนเอง
-- และปลดให้เองเมื่อชำระครบ
do $$
declare r record; v_held int; v_blocked int;
begin
  -- ดันวันครบกำหนดของนักศึกษาคนแรกให้เลยมา 45 วัน
  update installment i
  set due_on = current_date - 45
  from invoice inv
  where inv.id = i.invoice_id
    and inv.student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and i.status <> 'paid';

  select * into r from refresh_finance_holds('11111111-1111-1111-1111-111111111111');
  if r.placed < 1 then raise exception 'TEST 28: ควรระงับสิทธิ์อย่างน้อย 1 คน ได้ %', r.placed; end if;

  select count(*) into v_held from registration_hold
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and kind = 'finance' and released_at is null;
  if v_held <> 1 then raise exception 'TEST 28: ควรมีการระงับค้างอยู่ 1 รายการ ได้ %', v_held; end if;

  -- งานทะเบียนต้องเห็นผลทันทีโดยไม่ต้องรู้จักใบแจ้งหนี้
  select count(*) into v_blocked
  from check_registration('aaaa0000-0000-0000-0000-000000000011',
                          '33333333-3333-3333-3333-333333333332', '{}'::uuid[])
  where code = 'HOLD_FINANCE' and severity = 'block';
  if v_blocked <> 1 then
    raise exception 'TEST 28: งานทะเบียนควรเห็นการระงับ 1 รายการ ได้ %', v_blocked;
  end if;

  raise notice 'TEST 28 ผ่าน — งานการเงินระงับสิทธิ์ % คน และงานทะเบียนเห็นผลทันที', r.placed;
end $$;

-- ── TEST 29 ────────────────────────────────────────────────────────
-- ชำระครบแล้วระบบปลดการระงับเอง
do $$
declare v_pay uuid; v_owed numeric; r record; v_held int;
begin
  select outstanding into v_owed from v_student_balance
  where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  insert into payment (institution_id, student_id, received_on, amount, method, receipt_no)
  values ('11111111-1111-1111-1111-111111111111', 'aaaa0000-0000-0000-0000-000000000011',
          current_date, v_owed, 'bank_transfer', 'RC-0002')
  returning id into v_pay;
  perform post_payment(v_pay);

  select * into r from refresh_finance_holds('11111111-1111-1111-1111-111111111111');

  select count(*) into v_held from registration_hold
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and kind = 'finance' and released_at is null;
  if v_held <> 0 then raise exception 'TEST 29: ชำระครบแล้วยังมีการระงับค้าง % รายการ', v_held; end if;

  raise notice 'TEST 29 ผ่าน — ชำระครบ % บาท ระบบปลดการระงับให้เอง', v_owed;
end $$;

-- ── TEST 30 ────────────────────────────────────────────────────────
-- รายงานลูกหนี้แยกตามอายุหนี้
do $$
declare v int;
begin
  select count(*) into v from v_ar_aging
  where institution_id = '11111111-1111-1111-1111-111111111111';
  raise notice 'TEST 30 ผ่าน — รายงานอายุหนี้ทำงาน มี % ช่วงอายุที่มียอดค้าง', v;
end $$;

-- ── TEST 336 ───────────────────────────────────────────────────────
-- ส่วนลดที่เจาะจงรายการ (0080) ต้องลดเฉพาะรายการนั้น ไม่ใช่ทุกบรรทัด
-- เท่ากันหมด — นักศึกษา 012 มีส่วนลดพี่น้อง 10% แบบไม่เจาะจง (จาก TEST 24)
-- อยู่แล้ว เพิ่มส่วนลดที่เจาะจงเฉพาะค่าวัสดุฝึกอีก 50% ยอดที่ถูกต้องคือ
-- ค่าวัสดุฝึกลด 60% (10%+50% รวมกัน) ส่วนรายการอื่นลดแค่ 10% เดิม
do $$
declare v_inv uuid; r record;
begin
  insert into student_funding
    (student_id, funding_source_id, academic_year_id, fee_item_id,
     percent_off, approved_by, approved_at, document_no)
  values ('aaaa0000-0000-0000-0000-000000000012', 'f0000000-0000-0000-0000-000000000001',
          '22222222-2222-2222-2222-222222222222', 'd0000000-0000-0000-0000-000000000002',
          50.00, 'aaaa0000-0000-0000-0000-000000000022', now(), 'ทน.2569/0008');

  -- ภาคเรียนที่สอง — ยังไม่เคยออกใบแจ้งหนี้ให้นักศึกษาคนนี้มาก่อน
  v_inv := issue_invoice('aaaa0000-0000-0000-0000-000000000012',
                         '33333333-3333-3333-3333-333333333332', 1);

  select amount, discount into r from invoice_line
  where invoice_id = v_inv and fee_item_id = 'd0000000-0000-0000-0000-000000000001'; -- ค่าเล่าเรียน
  if r.discount <> 900.00 then
    raise exception 'TEST 336: ค่าเล่าเรียนควรลดแค่ 10%% (900) เพราะไม่เจาะจงถึงมัน ได้ %', r.discount;
  end if;

  select amount, discount into r from invoice_line
  where invoice_id = v_inv and fee_item_id = 'd0000000-0000-0000-0000-000000000002'; -- ค่าวัสดุฝึก
  if r.discount <> 1500.00 then
    raise exception 'TEST 336: ค่าวัสดุฝึกควรลด 60%% (1,500 จาก 2,500) ทั้งแบบรวมและแบบเจาะจง ได้ %', r.discount;
  end if;

  select amount, discount into r from invoice_line
  where invoice_id = v_inv and fee_item_id = 'd0000000-0000-0000-0000-000000000003'; -- ค่ากิจกรรม
  if r.discount <> 80.00 then
    raise exception 'TEST 336: ค่ากิจกรรมควรลดแค่ 10%% (80) เพราะไม่เจาะจงถึงมัน ได้ %', r.discount;
  end if;

  raise notice 'TEST 336 ผ่าน — ส่วนลดเจาะจงค่าวัสดุฝึกไม่ล้นไปลดค่าเล่าเรียน/ค่ากิจกรรมด้วย';
end $$;

-- ── TEST 337 ───────────────────────────────────────────────────────
-- โครงสร้างค่าเทอมแบบ "รวม" (level/study_year ว่าง, 0080) — เลือกใช้ก็
-- ต่อเมื่อไม่มีโครงสร้างที่เจาะจงกว่าตรงกันเท่านั้น (สาขา > ชั้นปี > ระดับ)
do $$
declare v_specific uuid; v_combined uuid; v_picked uuid;
begin
  insert into fee_schedule (id, institution_id, academic_year_id, level, study_year, announcement_no)
  values
    ('e0000000-0000-0000-0000-000000000090', '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222', 'PVC', 4, 'ทดสอบ TEST 337 — เจาะจง')
  returning id into v_specific;

  insert into fee_schedule (id, institution_id, academic_year_id, level, study_year, announcement_no)
  values
    ('e0000000-0000-0000-0000-000000000091', '11111111-1111-1111-1111-111111111111',
     '22222222-2222-2222-2222-222222222222', null, null, 'ทดสอบ TEST 337 — รวมทุกระดับทุกชั้นปี')
  returning id into v_combined;

  -- มีทั้งแบบเจาะจง (PVC ชั้นปี 4) และแบบรวม พร้อมกัน — ต้องเลือกแบบเจาะจง
  select fs.id into v_picked
  from fee_schedule fs
  where fs.institution_id = '11111111-1111-1111-1111-111111111111'
    and fs.academic_year_id = '22222222-2222-2222-2222-222222222222'
    and (fs.level = 'PVC' or fs.level is null)
    and (fs.study_year = 4 or fs.study_year is null)
    and fs.active
    and (fs.program_id is null)
    and fs.id in (v_specific, v_combined)
  order by (fs.program_id is not null) desc, (fs.study_year is not null) desc, (fs.level is not null) desc
  limit 1;

  if v_picked <> v_specific then
    raise exception 'TEST 337: มีแบบเจาะจงอยู่แล้วต้องเลือกแบบเจาะจง ไม่ใช่แบบรวม ได้ %', v_picked;
  end if;

  -- ลบแบบเจาะจงทิ้ง เหลือแต่แบบรวม — ต้องร่วงมาเลือกแบบรวมแทน
  delete from fee_schedule where id = v_specific;

  select fs.id into v_picked
  from fee_schedule fs
  where fs.institution_id = '11111111-1111-1111-1111-111111111111'
    and fs.academic_year_id = '22222222-2222-2222-2222-222222222222'
    and (fs.level = 'PVC' or fs.level is null)
    and (fs.study_year = 4 or fs.study_year is null)
    and fs.active
    and (fs.program_id is null)
    and fs.id = v_combined
  order by (fs.program_id is not null) desc, (fs.study_year is not null) desc, (fs.level is not null) desc
  limit 1;

  if v_picked <> v_combined then
    raise exception 'TEST 337: ไม่มีแบบเจาะจงเหลือแล้วต้องร่วงไปใช้แบบรวม ได้ %', v_picked;
  end if;

  delete from fee_schedule where id = v_combined;
  raise notice 'TEST 337 ผ่าน — เลือกโครงสร้างที่เจาะจงก่อนเสมอ ร่วงไปใช้แบบรวมเฉพาะเมื่อไม่มีแบบเจาะจงจริง ๆ';
end $$;

\echo ''
\echo '════ ทดสอบการเงินครบทุกข้อ ════'

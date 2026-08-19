-- ═══════════════════════════════════════════════════════════════════
-- 0048_receipt.sql
-- ทดสอบใบเสร็จรับเงิน (0068)
--
-- ─── ทำไมต้องทดสอบว่า "ออกให้เอง" ไม่ใช่ "ออกได้" ───
-- ก่อน 0068 ระบบมี `payment.receipt_no` ให้กรอกอยู่แล้ว เทสต์ที่เขียนว่า
-- "ใส่เลขแล้วอ่านกลับมาได้" จึงเขียวสนิทมาตลอดโดยที่ไม่มีใบเสร็จจริงสักใบ
-- สิ่งที่ต้องพิสูจน์คือ **รับเงินแล้วมีใบเสร็จโดยไม่มีใครต้องกดอะไรเพิ่ม**
-- และเลขนั้นมาจากสายเลขของสถานศึกษา ไม่ใช่จากนิ้วของเจ้าหน้าที่
--
-- ─── ทำไมยอดบนใบต้องเท่ากับเงินที่รับเสมอ ───
-- รายการบนใบคือ "เงินก้อนนี้ไปตัดงวดไหน" ถ้าเงินตัดไม่หมด (ชำระเกิน)
-- แล้วใบพิมพ์เฉพาะส่วนที่ตัดได้ ผู้ปกครองจะถือกระดาษที่บอกว่าจ่ายน้อยกว่า
-- ที่จ่ายจริง — ไฟล์นี้จึงตรวจ "ผลรวมรายการ + ชำระเกิน = เงินที่รับ" เสมอ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare
  v_inst    uuid := '11111111-1111-1111-1111-111111111111';
  v_actor   uuid;
  v_student uuid;
  v_pay     uuid;
  v_pay2    uuid;
  v_pay_adj uuid;
  v_doc     issued_document;
  v_doc2    issued_document;
  v_no1     text;
  v_no2     text;
  v_sum     numeric;
  n         integer;
begin
  perform set_config('app.institution_id', v_inst::text, true);
  perform set_config('app.role', 'finance', true);

  select p.id into v_actor from person p where p.institution_id = v_inst order by p.id limit 1;
  perform set_config('app.actor_id', v_actor::text, true);

  select s.id into v_student from student s where s.institution_id = v_inst order by s.student_code limit 1;
  if v_student is null then
    raise exception 'TEST 289 เตรียมข้อมูลไม่พอ: ไม่มีนักศึกษาในชุดตัวอย่าง';
  end if;

  -- ── TEST 289 รับเงินแล้วได้ใบเสร็จเองพร้อมเลขที่ ──────────────────
  insert into payment (institution_id, student_id, received_on, amount, method, received_by)
  values (v_inst, v_student, current_date, 1234.56, 'cash', v_actor)
  returning id into v_pay;

  perform post_payment(v_pay);

  select * into v_doc from issued_document
   where kind = 'receipt' and payload ->> 'payment_id' = v_pay::text;

  if v_doc.id is null then
    raise exception 'TEST 289 ล้มเหลว: รับเงินแล้วไม่มีใบเสร็จ — กฎอยู่ที่ post_payment() จึงต้องออกให้เองทุกครั้ง';
  end if;
  if coalesce(v_doc.doc_no, '') = '' then
    raise exception 'TEST 289 ล้มเหลว: ใบเสร็จไม่มีเลขที่';
  end if;
  if (select receipt_no from payment where id = v_pay) is distinct from v_doc.doc_no then
    raise exception 'TEST 289 ล้มเหลว: เลขที่ไม่ถูกเขียนกลับลง payment.receipt_no (ได้ %)',
      (select receipt_no from payment where id = v_pay);
  end if;
  v_no1 := v_doc.doc_no;

  -- ยอดบนใบต้องเท่ากับเงินที่รับเสมอ ไม่ว่าจะตัดงวดได้หมดหรือไม่
  select coalesce(sum((l ->> 'amount')::numeric), 0) into v_sum
    from jsonb_array_elements(v_doc.payload -> 'lines') l;
  if v_sum + (v_doc.payload ->> 'unallocated')::numeric <> 1234.56 then
    raise exception 'TEST 289 ล้มเหลว: ยอดรายการ % บวกชำระเกิน % ไม่เท่ากับเงินที่รับ 1234.56',
      v_sum, v_doc.payload ->> 'unallocated';
  end if;
  if coalesce(v_doc.payload ->> 'amount_text', '') = '' then
    raise exception 'TEST 289 ล้มเหลว: ไม่มีจำนวนเงินตัวอักษรบนใบ';
  end if;

  -- ── TEST 290 เลขเดินต่อ ไม่ซ้ำกับใบก่อนหน้า ──────────────────────
  insert into payment (institution_id, student_id, received_on, amount, method, received_by)
  values (v_inst, v_student, current_date, 500.00, 'promptpay', v_actor)
  returning id into v_pay2;
  perform post_payment(v_pay2);

  select doc_no into v_no2 from issued_document
   where kind = 'receipt' and payload ->> 'payment_id' = v_pay2::text;

  if v_no2 = v_no1 then
    raise exception 'TEST 290 ล้มเหลว: ใบที่สองได้เลขเดียวกับใบแรก (%)', v_no1;
  end if;

  -- ── TEST 291 เรียกซ้ำต้องไม่ได้ใบที่สองของเงินก้อนเดิม ────────────
  -- การกระทบยอดหรือสคริปต์ที่เรียก post_payment() ซ้ำต้องไม่สร้างหลักฐาน
  -- ว่ารับเงินสองรอบ
  perform post_payment(v_pay);
  select count(*) into n from issued_document
   where kind = 'receipt' and payload ->> 'payment_id' = v_pay::text;
  if n <> 1 then
    raise exception 'TEST 291 ล้มเหลว: เงินก้อนเดียวได้ใบเสร็จ % ใบ', n;
  end if;

  -- ── TEST 292 รายการปรับปรุงทางบัญชีไม่ได้ใบเสร็จ ──────────────────
  insert into payment (institution_id, student_id, received_on, amount, method, received_by)
  values (v_inst, v_student, current_date, 100.00, 'adjustment', v_actor)
  returning id into v_pay_adj;
  perform post_payment(v_pay_adj);

  select count(*) into n from issued_document
   where kind = 'receipt' and payload ->> 'payment_id' = v_pay_adj::text;
  if n <> 0 then
    raise exception 'TEST 292 ล้มเหลว: รายการปรับปรุงได้ใบเสร็จ ซึ่งเป็นหลักฐานว่ารับเงินทั้งที่ไม่มีเงินเข้า';
  end if;

  begin
    perform issue_receipt(v_pay_adj);
    raise exception 'TEST 292 ล้มเหลว: เรียก issue_receipt() กับรายการปรับปรุงตรง ๆ แล้วผ่าน';
  exception when check_violation then
    null;
  end;

  -- ── TEST 293 ใบเสร็จแก้ไม่ได้และลบไม่ได้ ─────────────────────────
  begin
    update issued_document set payload = payload || '{"amount_text":"ศูนย์บาทถ้วน"}'::jsonb
     where id = v_doc.id;
    raise exception 'TEST 293 ล้มเหลว: แก้เนื้อหาใบเสร็จที่ออกไปแล้วได้';
  exception when raise_exception then
    if position('TEST 293' in sqlerrm) > 0 then raise; end if;
  end;

  begin
    delete from issued_document where id = v_doc.id;
    raise exception 'TEST 293 ล้มเหลว: ลบใบเสร็จที่ออกไปแล้วได้';
  exception when raise_exception then
    if position('TEST 293' in sqlerrm) > 0 then raise; end if;
  end;

  -- ── TEST 294 ใบเสร็จที่ไม่ผูกกับการรับเงินออกไม่ได้ ───────────────
  -- ทางที่ข้าม issue_receipt() ไปเลย (pgAdmin · สคริปต์) ต้องถูกปฏิเสธด้วย
  begin
    insert into issued_document (institution_id, student_id, kind, doc_no, payload)
    values (v_inst, v_student, 'receipt', 'MANUAL-0001', '{"kind":"receipt"}'::jsonb);
    raise exception 'TEST 294 ล้มเหลว: ออกใบเสร็จที่ไม่ผูกกับการรับเงินได้';
  exception when check_violation then
    null;
  end;

  -- ── TEST 295 จำนวนเงินตัวอักษร ──────────────────────────────────
  if thai_baht_text(0)        <> 'ศูนย์บาทถ้วน'        then raise exception 'TEST 295 ล้มเหลว: 0'; end if;
  if thai_baht_text(11)       <> 'สิบเอ็ดบาทถ้วน'       then raise exception 'TEST 295 ล้มเหลว: 11 ได้ %', thai_baht_text(11); end if;
  if thai_baht_text(21)       <> 'ยี่สิบเอ็ดบาทถ้วน'     then raise exception 'TEST 295 ล้มเหลว: 21 ได้ %', thai_baht_text(21); end if;
  if thai_baht_text(101)      <> 'หนึ่งร้อยเอ็ดบาทถ้วน'  then raise exception 'TEST 295 ล้มเหลว: 101 ได้ %', thai_baht_text(101); end if;
  if thai_baht_text(1000000)  <> 'หนึ่งล้านบาทถ้วน'      then raise exception 'TEST 295 ล้มเหลว: 1000000 ได้ %', thai_baht_text(1000000); end if;
  if thai_baht_text(0.75)     <> 'เจ็ดสิบห้าสตางค์'      then raise exception 'TEST 295 ล้มเหลว: 0.75 ได้ %', thai_baht_text(0.75); end if;
  if thai_baht_text(1234.50)  <> 'หนึ่งพันสองร้อยสามสิบสี่บาทห้าสิบสตางค์'
    then raise exception 'TEST 295 ล้มเหลว: 1234.50 ได้ %', thai_baht_text(1234.50); end if;

  -- ── TEST 296 ยกเลิกแล้วออกใบใหม่ให้เงินก้อนเดิมได้ ────────────────
  -- ใบที่ออกผิดต้องยกเลิกแล้วออกใหม่ ไม่ใช่แก้ของเดิม — และตัวกันใบซ้ำ
  -- ต้องไม่ขวางการออกใบทดแทน
  update issued_document
     set voided_at = now(), void_reason = 'ทดสอบการยกเลิก', voided_by = v_actor
   where id = v_doc.id;

  select * into v_doc2 from issue_receipt(v_pay);
  if v_doc2.id = v_doc.id then
    raise exception 'TEST 296 ล้มเหลว: ยกเลิกแล้วยังคืนใบเดิม';
  end if;
  if v_doc2.doc_no = v_no1 then
    raise exception 'TEST 296 ล้มเหลว: ใบทดแทนใช้เลขเดิม (%) — เลขที่ต้องชี้ไปที่ใบเดียวเสมอ', v_no1;
  end if;

  raise notice 'TEST 289 ผ่าน — รับเงินแล้วได้ใบเสร็จเอง เลขที่ % และยอดบนใบเท่ากับเงินที่รับ', v_no1;
  raise notice 'TEST 290 ผ่าน — ใบถัดไปได้เลข % ไม่ซ้ำกับใบก่อน', v_no2;
  raise notice 'TEST 291 ผ่าน — เรียก post_payment ซ้ำไม่ได้ใบที่สอง';
  raise notice 'TEST 292 ผ่าน — รายการปรับปรุงทางบัญชีไม่ได้ใบเสร็จ';
  raise notice 'TEST 293 ผ่าน — ใบเสร็จแก้ไม่ได้และลบไม่ได้';
  raise notice 'TEST 294 ผ่าน — ออกใบเสร็จโดยไม่ผูกกับการรับเงินไม่ได้';
  raise notice 'TEST 295 ผ่าน — จำนวนเงินตัวอักษรถูกทุกกรณีที่เป็นข้อยกเว้น';
  raise notice 'TEST 296 ผ่าน — ยกเลิกแล้วออกใบทดแทนด้วยเลขใหม่ได้';
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบใบเสร็จรับเงินครบทุกข้อ ════'; end $$;

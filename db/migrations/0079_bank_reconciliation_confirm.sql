-- ═══════════════════════════════════════════════════════════════════
-- 0079 — กระทบยอดธนาคารมีทางเดินแค่ครึ่งเดียวมาตั้งแต่ 0010
--
-- ─── ต้นเหตุ ───
-- bank_transaction.state เป็น enum สี่ค่า (unmatched · suggested · confirmed
-- · ignored) reconcile_bank_transactions() (0010) เขียน confirmed ได้เอง
-- เฉพาะตอนมั่นใจ ≥90 (ref2 ตรงเป๊ะ หรือรหัสนักศึกษา+ยอดตรงกับงวด) ที่เหลือ
-- ค้างที่ suggested "ให้เจ้าหน้าที่กดยืนยัน" ตามคอมเมนต์ของฟังก์ชันเอง —
-- แต่ไม่เคยมีฟังก์ชันหรือ endpoint ไหนทำหน้าที่ "กดยืนยัน" นั้นเลยสักจุด
-- ตรวจแล้วไม่มีทางเขียน state = 'confirmed'/'ignored' จากที่อื่นเลยในทั้งระบบ
--
-- รายการที่คะแนน 60-80 (ยอดตรงกับงวดเดียว หรือเคยยืนยันชื่อผู้โอนนี้มาก่อน)
-- ซึ่งในทางปฏิบัติเป็นเสียงส่วนใหญ่ของการโอนผ่านมือถือที่ไม่มีเลขอ้างอิง
-- จึงค้างอยู่ที่ suggested ตลอดไป ไม่มีทางไปต่อได้แม้แต่ทาง API ตรง
--
-- ที่กระทบต่อคือ reconciliation_hint (จำชื่อผู้โอนคู่กับนักศึกษา ให้ครั้งถัดไป
-- จับคู่เองได้ที่ระดับ 80 คะแนน) ไม่เคยมีอะไร insert เข้าไปเลยทั้งระบบ เพราะ
-- จุดเดียวที่ควรเขียนมันคือ "ตอนเจ้าหน้าที่กดยืนยัน" ซึ่งไม่มีอยู่จริง —
-- ระดับคะแนน 80 จึงใช้งานไม่ได้ตลอดมาเช่นกัน แม้จะดูเหมือนใช้ได้จากคอมเมนต์
--
-- ─── ทำไม confirm_bank_match() รับ p_student_id ไม่ใช่ p_invoice_id ───
-- post_payment() ไม่สนใจว่าเงินจะไปตัดใบแจ้งหนี้ใบไหน มันตัดกับ**ทุกงวดที่
-- ค้างของนักศึกษาคนนั้น**ตามลำดับวันครบกำหนดเสมออยู่แล้ว (ดู recordPayment())
-- — ตัวแปรที่ต้องรู้จริง ๆ คือ "ใครโอนมา" ไม่ใช่ "ใบไหน" ถ้ารับเป็นใบแจ้งหนี้
-- หน้าจอต้องมีตัวค้นหาใบแจ้งหนี้แยกอีกชุด ทั้งที่มีตัวเลือกนักศึกษาอยู่แล้ว
-- ในหน้าเดิม — ข้อเสนอที่ระบบให้มา (matched_invoice_id) ผิดได้เช่นกัน จึง
-- ให้เจ้าหน้าที่ระบุนักศึกษาเองแทนได้เสมอ ไม่ใช่ต้องยอมรับข้อเสนอเท่านั้น
--
-- ─── ทำไมยืนยันแล้วเดินผ่าน post_payment() เหมือนรับชำระปกติ ───
-- รายการเดินบัญชีที่ยืนยันแล้วก็คือเงินที่รับจริง กฎ "รับเงินแล้วต้องมี
-- ใบเสร็จ" (0068) ต้องใช้ทางเดียวกับการรับชำระตามปกติ ไม่ใช่ทางลัดที่ข้าม
-- การออกใบเสร็จไป — เงินที่ยืนยันจากธนาคารแล้วไม่มีใบเสร็จจะตรวจสอบย้อนหลัง
-- ไม่ได้เหมือนที่ recordPayment() ป้องกันไว้อยู่แล้ว
-- ═══════════════════════════════════════════════════════════════════

create or replace function confirm_bank_match(
  p_bank_transaction_id uuid,
  p_student_id          uuid default null
) returns uuid
language plpgsql as $$
declare
  bt        record;
  v_student uuid;
  v_invoice uuid;
  v_pay     uuid;
begin
  select * into bt from bank_transaction
   where id = p_bank_transaction_id
     and institution_id = current_institution_id()
     and state in ('unmatched', 'suggested');
  if bt.id is null then
    raise exception 'ไม่พบรายการนี้ หรือถูกยืนยัน/ข้ามไปแล้ว';
  end if;

  if p_student_id is not null then
    select id into v_student from student
     where id = p_student_id and institution_id = current_institution_id();
    if v_student is null then
      raise exception 'ไม่พบนักศึกษาคนนี้ หรือไม่มีสิทธิ์เข้าถึง';
    end if;
  elsif bt.matched_invoice_id is not null then
    select student_id into v_student from invoice
     where id = bt.matched_invoice_id and institution_id = current_institution_id();
  end if;

  if v_student is null then
    raise exception 'ต้องระบุนักศึกษาที่จะจับคู่ — รายการนี้ยังไม่มีข้อเสนอ';
  end if;

  insert into payment
    (institution_id, student_id, received_on, amount, method, bank_ref, note, received_by, status)
  values (current_institution_id(), v_student, bt.posted_at::date, bt.amount, 'promptpay',
          bt.bank_ref,
          'ยืนยันจากรายการเดินบัญชี — ' || coalesce(bt.match_reason, 'เจ้าหน้าที่จับคู่เอง'),
          current_actor_id(), 'pending')
  returning id into v_pay;

  -- post_payment() ออกใบเสร็จให้ในตัวเหมือน recordPayment() ปกติ (0068) และ
  -- ตัดกับทุกงวดที่ค้างของนักศึกษาคนนี้ตามลำดับวันครบกำหนดเอง ไม่ใช่ใบใดใบหนึ่ง
  perform post_payment(v_pay);

  -- matched_invoice_id เป็นค่าที่ใช้แสดงผลเท่านั้น ไม่ใช่ตัวตัดสินว่าเงินไป
  -- ตัดยอดใบไหน (ดูคอมเมนต์หัวไฟล์) — คงค่าเดิมถ้ามีอยู่แล้ว ไม่มีก็เดาให้
  -- จากใบที่ยังค้างอยู่ใบล่าสุดของนักศึกษาคนนี้เพื่อให้พอดูรู้เรื่อง
  update bank_transaction
     set state = 'confirmed',
         matched_invoice_id = coalesce(
           bt.matched_invoice_id,
           (select i.id from invoice i
             where i.student_id = v_student and i.status in ('issued', 'partially_paid')
             order by i.due_on limit 1)
         ),
         confidence = 100, payment_id = v_pay
   where id = p_bank_transaction_id;

  -- จำชื่อผู้โอนคู่กับนักศึกษาไว้ ให้ครั้งถัดไปจับคู่เองได้ที่ระดับ 80 คะแนน
  -- (ระดับนี้ไม่เคยทำงานเลยเพราะไม่เคยมีอะไรมา insert ตารางนี้มาก่อน)
  if bt.counterparty is not null then
    insert into reconciliation_hint (institution_id, counterparty, student_id)
    values (current_institution_id(), bt.counterparty, v_student)
    on conflict (institution_id, counterparty)
      do update set student_id   = excluded.student_id,
                     hit_count    = reconciliation_hint.hit_count + 1,
                     last_used_at = now();
  end if;

  return v_pay;
end $$;

comment on function confirm_bank_match(uuid, uuid) is
  'เจ้าหน้าที่ยืนยันรายการเดินบัญชีที่ยังไม่มั่นใจพอให้จับคู่เอง (suggested) '
  'หรือจับคู่เองจากรายการที่ยังไม่มีข้อเสนอ (unmatched) — รับเงินจริงและออก'
  'ใบเสร็จผ่าน post_payment() เหมือนรับชำระปกติ และจำชื่อผู้โอนไว้ใช้จับคู่'
  'อัตโนมัติครั้งถัดไป (0079)';

create or replace function ignore_bank_match(p_bank_transaction_id uuid)
returns void
language plpgsql as $$
begin
  update bank_transaction
     set state = 'ignored'
   where id = p_bank_transaction_id
     and institution_id = current_institution_id()
     and state in ('unmatched', 'suggested');
  if not found then
    raise exception 'ไม่พบรายการนี้ หรือถูกยืนยัน/ข้ามไปแล้ว';
  end if;
end $$;

comment on function ignore_bank_match(uuid) is
  'ทำเครื่องหมายว่ารายการเดินบัญชีนี้ไม่ใช่ค่าเทอม (เช่น เงินคืน รายการภายใน'
  'ธนาคาร) — ไม่ลบทิ้ง เพื่อให้ตรวจสอบย้อนหลังได้ว่าทำไมถึงไม่นับ (0079)';

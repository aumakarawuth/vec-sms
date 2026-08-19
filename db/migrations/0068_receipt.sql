-- ═══════════════════════════════════════════════════════════════════
-- 0068_receipt.sql
--
-- ใบเสร็จรับเงิน — เอกสารที่มีเลขที่ ตรึงเนื้อหา และแก้ไม่ได้
--
-- ─── ช่องที่พบตอนเทียบเมนูการเงินกับระบบที่วิทยาลัยใช้อยู่ ───
-- ระบบนั้นมีสามเมนูที่พูดถึงใบเสร็จ (ตรวจสอบสถานะใบเสร็จ · พิมพ์ใบเสร็จ
-- ย้อนหลัง · แบบฟอร์มชำระเงินผ่านธนาคารที่อ้างเลขที่) ส่วนของเรามีแค่
-- `payment.receipt_no` ซึ่งเป็น**ช่องข้อความที่เจ้าหน้าที่พิมพ์เอง** ตั้งแต่
-- 0010 — ไม่มีตัวเดินเลข ไม่มีแม่แบบพิมพ์ ไม่มีการตรึงเนื้อหา
--
-- ─── ทำไมเรื่องนี้หนักกว่าที่เห็น ───
-- เอกสารอีกแปดใบของระบบนี้ถูกคุมไว้แน่นมาก (เลขเรียงจาก document_series ·
-- payload ตรึง · แก้/ลบไม่ได้ · ยกเลิกต้องมีเหตุผล) แต่ใบเสร็จซึ่งเป็น
-- **เอกสารทางการเงิน**กลับหลุดออกไปทั้งชุด — เลขซ้ำกันสองใบก็ได้ เว้นว่าง
-- ก็ได้ และพิมพ์ใหม่ได้เนื้อหาที่คำนวณสดทุกครั้ง ทั้งที่ผู้ปกครองถือใบหนึ่ง
-- และฝ่ายบัญชีถือสำเนาอีกใบ ซึ่งต้องตรงกันไปตลอด
--
-- สิ่งที่ทำให้มองไม่เห็นคือ `payment` บันทึกครบทุกช่องและยอดคงเหลือคำนวณ
-- ถูกต้องเสมอ ระบบจึงดู "ครบ" จากทุกมุมที่มีเครื่องมือวัด (รูปเดียวกับ
-- ข้อ 8 และข้อ 15 ในรายการที่เคยพังแบบเงียบ ๆ)
--
-- ─── ทำไมใบเสร็จอยู่ใน issued_document ไม่ใช่ตารางของตัวเอง ───
-- คุณสมบัติที่ใบเสร็จต้องมีคือชุดเดียวกับที่ตารางนั้นบังคับอยู่แล้วทุกข้อ
-- เลขที่ไม่ซ้ำต่อประเภทต่อปี · เนื้อหาตรึง ณ วันที่ออก · แก้ไม่ได้ ·
-- ลบไม่ได้ · ยกเลิกต้องมีเหตุผล · พิมพ์ซ้ำอ่านจาก payload
-- การสร้างตารางที่สองที่มีกฎชุดเดียวกันแปลว่าต้องบังคับกฎเหล่านั้นซ้ำอีกรอบ
-- แล้ววันหนึ่งสองที่จะไม่ตรงกัน
--
-- ─── ทำไมออกใบเสร็จจาก post_payment() ไม่ใช่จากชั้น API ───
-- กฎคือ "รับเงินแล้วต้องมีใบเสร็จ" ไม่ใช่ "หน้าจอควรกดออกใบเสร็จด้วย"
-- ถ้ายกขึ้นไปไว้ที่ชั้น API ทางอื่นที่เขียน payment ได้ (สคริปต์นำเข้า ·
-- การกระทบยอดอัตโนมัติ · pgAdmin) จะรับเงินโดยไม่มีใบเสร็จได้เงียบ ๆ
--
-- ─── ทำไม `adjustment` ไม่ได้ใบเสร็จ ───
-- เป็นการปรับปรุงทางบัญชี ไม่ใช่การรับเงินจากใคร ออกใบเสร็จให้แปลว่ามี
-- หลักฐานว่ารับเงินทั้งที่ไม่มีเงินเข้ามา ซึ่งเป็นเอกสารเท็จ
--
-- ─── ทำไมจำนวนเงินตัวอักษรคำนวณที่ฐานข้อมูลแล้วตรึงลง payload ───
-- ถ้าแม่แบบแปลงเลขเป็นตัวอักษรตอนพิมพ์ มันจะเป็นสูตรชุดที่สองที่ค่อย ๆ
-- เพี้ยนไปจากตัวเลขบนใบเดียวกัน และใบที่พิมพ์ปีหน้าจะได้คำอ่านคนละแบบกับ
-- ใบที่ส่งไปแล้ว (หลักข้อ 5 — ค่าที่ตรึงไว้ห้ามคำนวณใหม่)
-- ═══════════════════════════════════════════════════════════════════

-- PostgreSQL ปฏิเสธการใช้ค่า enum ใหม่ใน transaction เดียวกับที่เพิ่มมัน
-- ("unsafe use of new value of enum type") ทั้งไฟล์จึงต้องแยกเป็นสอง
-- transaction — ค่าใหม่ต้อง commit ก่อนจึงเขียนกฎที่อ้างถึงมันได้ (0026)
begin;
alter type document_kind add value if not exists 'receipt';
commit;

begin;

-- ───────────────────────────────────────────────────────────────────
-- จำนวนเงินเป็นตัวอักษร
--
-- เขียนเองเพราะ PostgreSQL ไม่มี bahttext() และเป็นข้อความที่ต้องอยู่บน
-- กระดาษราชการให้ตรงกับตัวเลขเสมอ
-- ───────────────────────────────────────────────────────────────────
create or replace function thai_number_text(p_n bigint)
returns text language plpgsql immutable as $$
declare
  digits constant text[] := array['ศูนย์','หนึ่ง','สอง','สาม','สี่','ห้า','หก','เจ็ด','แปด','เก้า'];
  units  constant text[] := array['','สิบ','ร้อย','พัน','หมื่น','แสน'];
  v_out  text := '';
  v_rest bigint;
  v_s    text;
  v_len  int;
  v_pos  int;
  i      int;
  d      int;
begin
  if p_n = 0 then return digits[1]; end if;

  -- หลักล้านขึ้นไปอ่านเป็นกลุ่มแล้วต่อด้วย "ล้าน" ซ้อนกันได้ไม่จำกัด
  if p_n >= 1000000 then
    v_out  := thai_number_text(p_n / 1000000) || 'ล้าน';
    v_rest := p_n % 1000000;
    if v_rest > 0 then
      v_out := v_out || thai_number_text(v_rest);
    end if;
    return v_out;
  end if;

  v_s   := p_n::text;
  v_len := length(v_s);

  for i in 1 .. v_len loop
    d := substr(v_s, i, 1)::int;
    continue when d = 0;

    v_pos := v_len - i;   -- 0 = หลักหน่วย · 1 = หลักสิบ

    if v_pos = 1 and d = 1 then
      v_out := v_out || 'สิบ';        -- ไม่ใช่ "หนึ่งสิบ"
    elsif v_pos = 1 and d = 2 then
      v_out := v_out || 'ยี่สิบ';      -- ไม่ใช่ "สองสิบ"
    elsif v_pos = 0 and d = 1 and v_len > 1 then
      v_out := v_out || 'เอ็ด';        -- ไม่ใช่ "หนึ่ง" เมื่อมีหลักสูงกว่า
    else
      v_out := v_out || digits[d + 1] || units[v_pos + 1];
    end if;
  end loop;

  return v_out;
end $$;

comment on function thai_number_text(bigint) is
  'อ่านจำนวนเต็มเป็นตัวอักษรไทย — สิบ/ยี่สิบ/เอ็ด เป็นข้อยกเว้นที่ต้องเขียนแยก';

create or replace function thai_baht_text(p_amount numeric)
returns text language plpgsql immutable as $$
declare
  v_abs  numeric := abs(p_amount);
  v_int  bigint;
  v_sat  int;
  v_out  text := '';
begin
  -- ปัดที่สองตำแหน่งก่อนแยกส่วน มิฉะนั้น 0.999 จะได้ 100 สตางค์
  v_abs := round(v_abs, 2);
  v_int := floor(v_abs)::bigint;
  v_sat := round((v_abs - floor(v_abs)) * 100)::int;

  if v_int = 0 and v_sat = 0 then
    return 'ศูนย์บาทถ้วน';
  end if;

  if p_amount < 0 then
    v_out := 'ลบ';
  end if;

  if v_int > 0 then
    v_out := v_out || thai_number_text(v_int) || 'บาท';
  end if;

  if v_sat = 0 then
    v_out := v_out || 'ถ้วน';
  else
    v_out := v_out || thai_number_text(v_sat) || 'สตางค์';
  end if;

  return v_out;
end $$;

comment on function thai_baht_text(numeric) is
  'จำนวนเงินเป็นตัวอักษรสำหรับใบเสร็จ — ตรึงลง payload ตอนออกใบ ไม่คำนวณใหม่ตอนพิมพ์';

-- ───────────────────────────────────────────────────────────────────
-- หนึ่งการรับเงิน หนึ่งใบเสร็จ
--
-- บังคับที่ดัชนี ไม่ใช่ที่ตรรกะในฟังก์ชัน เพราะการเรียก post_payment()
-- ซ้ำ (กระทบยอดใหม่ · เรียกจากสคริปต์) ต้องไม่ทำให้เกิดใบที่สองของเงิน
-- ก้อนเดิม ซึ่งจะกลายเป็นหลักฐานว่ารับเงินสองรอบ
--
-- นับเฉพาะใบที่ยังไม่ถูกยกเลิก — ใบที่ออกผิดต้องยกเลิกแล้วออกใหม่ได้
-- ───────────────────────────────────────────────────────────────────
create unique index issued_document_receipt_payment_uq
  on issued_document ((payload ->> 'payment_id'))
  where kind = 'receipt' and voided_at is null;

-- ───────────────────────────────────────────────────────────────────
-- ใบเสร็จต้องมาจาก issue_receipt() เท่านั้น
--
-- ─── ทำไมเป็น trigger ไม่ใช่การเขียน issue_document() ทับ ───
-- `issue_document()` ยาวสามร้อยบรรทัดและถูกเขียนทับมาแล้วสองรอบเพื่อเพิ่ม
-- เงื่อนไขบรรทัดเดียว (0057/0058 — เหตุผลที่ 0059 ต้องแยก transcript_extra
-- ออกมา) ส่วนกฎนี้เป็นเงื่อนไขระดับ**ค่าในแถว** คือ "ใบเสร็จต้องผูกกับ
-- การรับเงินเสมอ" ซึ่งเป็นรูปเดียวกับที่ 0049 เลือก trigger แทนนโยบาย
--
-- และครอบทุกทาง ไม่ใช่แค่ทางที่ผ่าน issue_document()
-- ───────────────────────────────────────────────────────────────────
create or replace function receipt_needs_payment() returns trigger
language plpgsql as $$
begin
  if new.kind = 'receipt'
     and coalesce(new.payload ->> 'payment_id', '') = '' then
    raise exception 'ใบเสร็จรับเงินต้องออกด้วย issue_receipt() — payload ต้องผูกกับการรับเงินที่เกิดขึ้นจริง'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger issued_document_receipt_guard before insert on issued_document
  for each row execute function receipt_needs_payment();

-- ───────────────────────────────────────────────────────────────────
-- จ่ายเลขที่โดยระบุสถานศึกษาเอง
--
-- ─── ทำไมต้องมีทางที่ไม่พึ่งบริบทของ session ───
-- ใบเสร็จออกจาก `post_payment()` ซึ่งถูกเรียกจาก
-- `reconcile_bank_transactions(p_institution_id)` ที่**รับสถานศึกษามาเป็น
-- พารามิเตอร์อยู่แล้ว** การให้ตัวจ่ายเลขไปอ่าน `current_institution_id()`
-- อีกทางหนึ่งคือมีแหล่งความจริงสองแหล่งของข้อเท็จจริงเดียวกัน ซึ่งถ้าวันหนึ่ง
-- ไม่ตรงกัน ใบเสร็จจะไปกินเลขของสายเลขวิทยาลัยอื่น
--
-- และ**สถานศึกษาของใบเสร็จคือของแถว payment** ไม่ใช่ของคนที่กดปุ่ม —
-- อ่านจากข้อมูลจึงถูกกว่าอ่านจากบริบทเสมอ
--
-- ตัวเดิมสามอาร์กิวเมนต์ยังอยู่ครบและเปลี่ยนพฤติกรรมไม่ได้เลย เพราะมันมา
-- เรียกตัวนี้ต่อ — ไม่ใช่คัดลอกตรรกะไปไว้สองที่แล้วรอให้เพี้ยนกันทีหลัง
-- ───────────────────────────────────────────────────────────────────
create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text,
  p_inst    uuid
) returns text language plpgsql as $$
declare
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if p_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  insert into document_series (institution_id, kind, year_be, lang, prefix)
  values (p_inst, p_kind, p_year_be, p_lang,
          case when p_lang = 'th' then p_year_be::text
               else 'E' || p_year_be::text end)
  on conflict (institution_id, kind, year_be, lang) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = p_inst and kind = p_kind
     and year_be = p_year_be and lang = p_lang
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint, text, uuid) is
  'จ่ายเลขที่เอกสารของสถานศึกษาที่ระบุ — ใช้เมื่อผู้เรียกรู้สถานศึกษาจากข้อมูล ไม่ใช่จากบริบทของ session';

create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text default 'th'
) returns text language sql as $$
  select next_document_no(p_kind, p_year_be, p_lang, current_institution_id())
$$;

-- ───────────────────────────────────────────────────────────────────
-- ออกใบเสร็จ
--
-- คืนใบเดิมถ้าเงินก้อนนี้เคยออกไปแล้ว ไม่ใช่ raise — เพราะผู้เรียกที่
-- ต้องการ "ใบเสร็จของเงินก้อนนี้" ควรได้ใบนั้น ไม่ใช่ล้มทั้งรายการ
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_receipt(p_payment_id uuid)
returns issued_document language plpgsql as $$
declare
  v_pay     payment;
  v_inst    uuid;
  v_year    smallint;
  v_doc_no  text;
  v_lines   jsonb;
  v_alloc   numeric(12,2);
  v_payload jsonb;
  v_row     issued_document;
begin
  select * into v_pay from payment where id = p_payment_id;
  if v_pay.id is null then
    raise exception 'ไม่พบรายการรับเงินรหัสที่ระบุ หรือไม่มีสิทธิ์เข้าถึง';
  end if;

  -- สถานศึกษาของใบเสร็จมาจากแถวเงินรับ ไม่ใช่จากบริบทของ session
  v_inst := v_pay.institution_id;

  -- ออกใบไปแล้วก็คืนใบเดิม (พิมพ์ซ้ำต้องได้ใบเดียวกันเสมอ)
  select * into v_row from issued_document d
   where d.kind = 'receipt'
     and d.payload ->> 'payment_id' = p_payment_id::text
     and d.voided_at is null
   limit 1;
  if v_row.id is not null then
    return v_row;
  end if;

  if v_pay.student_id is null then
    raise exception 'เงินก้อนนี้ยังไม่รู้ว่าเป็นของนักศึกษาคนไหน จึงออกใบเสร็จให้ใครไม่ได้ (payment=%)', p_payment_id
      using errcode = 'check_violation';
  end if;

  if v_pay.method = 'adjustment' then
    raise exception 'รายการปรับปรุงทางบัญชีไม่ใช่การรับเงิน จึงออกใบเสร็จไม่ได้'
      using errcode = 'check_violation';
  end if;

  -- ปีการศึกษาที่ครอบวันที่รับเงิน — ไม่ใช่ปีปัจจุบันของนาฬิกา เพราะเงินที่
  -- บันทึกย้อนหลังต้องอยู่ในสายเลขของปีที่รับจริง
  v_year := coalesce(
    (select ay.year_be from academic_year ay
      where ay.institution_id = v_inst
        and v_pay.received_on between ay.starts_on and ay.ends_on
      order by ay.year_be desc limit 1),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from v_pay.received_on) + 543)::smallint);

  v_doc_no := next_document_no('receipt'::document_kind, v_year, 'th', v_inst);

  /*
   * รายการบนใบคือ "เงินก้อนนี้ไปตัดงวดไหนบ้าง" ไม่ใช่รายการค่าธรรมเนียม
   * ทั้งใบแจ้งหนี้ — ใบเสร็จต้องแสดงสิ่งที่**จ่ายจริงในครั้งนี้** ถ้าพิมพ์
   * รายการทั้งใบแจ้งหนี้จะได้กระดาษที่ยอดรวมไม่ตรงกับเงินที่รับ
   */
  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_no', inv.invoice_no,
           'term',       jsonb_build_object('year_be', ay.year_be, 'ordinal', t.ordinal),
           'seq',        i.seq,
           'due_on',     i.due_on,
           'amount',     a.amount
         ) order by inv.invoice_no, i.seq), '[]'::jsonb),
       coalesce(sum(a.amount), 0)
    into v_lines, v_alloc
    from payment_allocation a
    join installment i   on i.id = a.installment_id
    join invoice inv     on inv.id = i.invoice_id
    join term t          on t.id = inv.term_id
    join academic_year ay on ay.id = t.academic_year_id
   where a.payment_id = p_payment_id;

  v_payload := jsonb_build_object(
    'kind',       'receipt',
    'payment_id', p_payment_id,
    'issued_at',  now(),
    'year_be',    v_year,
    'institution',
      (select jsonb_build_object('name_th', ins.name_th, 'code', ins.code)
         from institution ins where ins.id = v_inst),
    'student',
      (select jsonb_build_object(
                'student_code', s.student_code,
                'full_name', trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                                  || ' ' || coalesce(p.last_name_th, '')))
         from student s join person p on p.id = s.person_id
        where s.id = v_pay.student_id),
    'payment', jsonb_build_object(
        'received_on', v_pay.received_on,
        'amount',      v_pay.amount,
        'method',      v_pay.method,
        'bank_ref',    v_pay.bank_ref,
        'note',        v_pay.note),
    'lines',       v_lines,
    -- เงินที่ยังไม่ได้ตัดงวด (ชำระเกิน) ต้องอยู่บนใบด้วย มิฉะนั้นยอดรวมของ
    -- รายการจะไม่เท่ากับเงินที่รับ แล้วคนอ่านจะคิดว่าใบพิมพ์ผิด
    'unallocated', v_pay.amount - v_alloc,
    'amount_text', thai_baht_text(v_pay.amount),
    'received_by',
      (select trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                   || ' ' || coalesce(p.last_name_th, ''))
         from person p where p.id = coalesce(v_pay.received_by, current_actor_id())));

  insert into issued_document (institution_id, student_id, kind, doc_no, issued_by, payload)
  values (v_inst, v_pay.student_id, 'receipt', v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  /*
   * เขียนเลขกลับลง payment.receipt_no
   *
   * ช่องนี้มีมาตั้งแต่ 0010 พร้อม unique (institution, receipt_no) และเคย
   * เป็นช่องที่คนกรอกเอง — การให้ระบบเป็นคนเขียนทำให้ข้อจำกัดเดิมกลายเป็น
   * ตัวกันเลขซ้ำจริง ๆ และหน้าจอ/รายงานที่อ่านช่องนี้อยู่แล้วใช้ได้ทันที
   */
  update payment set receipt_no = v_doc_no where id = p_payment_id;

  return v_row;
end $$;

comment on function issue_receipt(uuid) is
  'ออกใบเสร็จของการรับเงินหนึ่งครั้ง — เนื้อหาตรึง ณ วันที่ออก และคืนใบเดิมถ้าเคยออกไปแล้ว';

-- ───────────────────────────────────────────────────────────────────
-- ผูกเข้ากับการรับเงิน
--
-- เขียนทับ post_payment() ทั้งตัวเพราะต้องเติมขั้นสุดท้าย ส่วนที่เหลือ
-- เหมือน 0010 ทุกบรรทัด
-- ───────────────────────────────────────────────────────────────────
create or replace function post_payment(p_payment_id uuid)
returns numeric language plpgsql as $$
declare
  v_remaining numeric(12,2);
  v_student   uuid;
  v_method    payment_method;
  r           record;
  v_take      numeric(12,2);
begin
  select amount, student_id, method into v_remaining, v_student, v_method
  from payment where id = p_payment_id;

  if v_student is null then
    raise exception 'เงินรับก้อนนี้ยังไม่ได้ระบุว่าเป็นของนักศึกษาคนไหน (payment=%)', p_payment_id;
  end if;

  for r in
    select i.id, i.amount + i.penalty - i.paid_amount as outstanding
    from installment i
    join invoice inv on inv.id = i.invoice_id
    where inv.student_id = v_student
      and inv.status not in ('void', 'written_off')
      and i.status <> 'paid'
      and i.amount + i.penalty - i.paid_amount > 0
    order by i.due_on, i.seq
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, r.outstanding);

    insert into payment_allocation (payment_id, installment_id, amount)
    values (p_payment_id, r.id, v_take)
    on conflict (payment_id, installment_id)
      do update set amount = payment_allocation.amount + excluded.amount;

    update installment
    set paid_amount = paid_amount + v_take,
        status = case when paid_amount + v_take >= amount + penalty
                      then 'paid'::installment_status
                      else 'partially_paid'::installment_status end
    where id = r.id;

    v_remaining := v_remaining - v_take;
  end loop;

  -- ปรับยอดบนใบแจ้งหนี้
  update invoice inv
  set paid_total = sub.paid,
      status = case when sub.paid >= inv.total then 'paid'::invoice_status
                    when sub.paid > 0          then 'partially_paid'::invoice_status
                    else inv.status end
  from (
    select i.invoice_id, sum(i.paid_amount) as paid
    from installment i
    join invoice v on v.id = i.invoice_id
    where v.student_id = v_student
    group by i.invoice_id
  ) sub
  where inv.id = sub.invoice_id;

  update payment
  set status = 'reconciled', reconciled_at = now()
  where id = p_payment_id;

  -- ออกใบเสร็จเป็นขั้นสุดท้าย หลังตัดงวดเสร็จแล้ว เพราะรายการบนใบคือ
  -- ผลของการตัด ถ้าออกก่อนจะได้ใบที่ไม่มีรายการสักบรรทัด
  if v_method <> 'adjustment' then
    perform issue_receipt(p_payment_id);
  end if;

  return v_remaining;   -- เงินเหลือที่ยังไม่ได้ตัด (ชำระเกิน)
end $$;

comment on function post_payment is
  'ตัดงวดตามลำดับกำหนดชำระ แล้วออกใบเสร็จให้อัตโนมัติ (ยกเว้นรายการปรับปรุง) — คืนเงินที่เหลือหลังตัดครบ ถ้ามากกว่าศูนย์แปลว่าชำระเกิน';

commit;

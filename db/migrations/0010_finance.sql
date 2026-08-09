-- ═══════════════════════════════════════════════════════════════════
-- 0010_finance.sql
-- การเงิน — ค่าธรรมเนียม ใบแจ้งหนี้ ผ่อนชำระ รับชำระ กระทบยอด บัญชีแยกประเภท
--
-- ทำไมโมดูลนี้สำคัญที่สุดสำหรับวิทยาลัยเอกชน
-- รายได้มาจากสองทางเท่านั้น คือค่าเทอมกับเงินอุดหนุนรายบุคคล ทั้งสองทางผูก
-- กับ "จำนวนนักศึกษาที่มีตัวตนจริงและยังอยู่" ระบบนี้จึงไม่ใช่งานธุรการ
-- แต่เป็นระบบรักษารายได้
--
-- หลักสี่ข้อ
-- 1. บัญชีเป็น double-entry ตั้งแต่วันแรก — ย้ายทีหลังแทบเป็นไปไม่ได้
--    ทุกรายการต้องเดบิตเท่ากับเครดิต บังคับด้วย constraint trigger แบบ deferred
-- 2. เงินที่รับมาไม่ผูกกับใบแจ้งหนี้โดยตรง แต่ผ่าน payment_allocation
--    เพราะเงินก้อนเดียวอาจตัดหลายงวด และงวดเดียวอาจมาจากหลายก้อน
-- 3. กระทบยอดอัตโนมัติเป็นหัวใจ — เจ้าหน้าที่ควรทำงานกับรายการที่จับคู่ไม่ได้
--    ไม่ใช่ทั้งหมด ระบบให้คะแนนความมั่นใจและจำรูปแบบที่ยืนยันแล้วไว้ใช้ครั้งต่อไป
-- 4. การระงับสิทธิ์ไปที่ registration_hold ไม่ใช่ให้งานทะเบียนมาอ่านใบแจ้งหนี้เอง
--
-- นอกขอบเขตไฟล์นี้ — จัดซื้อจัดจ้าง งบประมาณ เจ้าหนี้ และ e-Tax Invoice
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- บัญชีแยกประเภท
-- ───────────────────────────────────────────────────────────────────
create type ledger_account_type as enum ('asset', 'liability', 'equity', 'revenue', 'expense');

create table ledger_account (
  id             uuid                primary key default gen_random_uuid(),
  institution_id uuid                not null references institution on delete restrict,
  code           text                not null,     -- '1102' ลูกหนี้ค่าเล่าเรียน
  name_th        text                not null,
  type           ledger_account_type not null,
  active         boolean             not null default true,
  unique (institution_id, code)
);

create table ledger_transaction (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  occurred_on    date        not null,
  memo           text        not null,
  ref_type       text,                             -- 'invoice' | 'payment' | 'writeoff'
  ref_id         uuid,
  posted_at      timestamptz not null default now(),
  posted_by      uuid
);
create index on ledger_transaction (institution_id, occurred_on);
create index on ledger_transaction (ref_type, ref_id);

create table ledger_entry (
  id             uuid         primary key default gen_random_uuid(),
  transaction_id uuid         not null references ledger_transaction on delete cascade,
  account_id     uuid         not null references ledger_account on delete restrict,
  debit          numeric(14,2) not null default 0,
  credit         numeric(14,2) not null default 0,
  memo           text,
  check (debit >= 0 and credit >= 0),
  check ((debit = 0) <> (credit = 0))              -- ต้องเป็นด้านใดด้านหนึ่งเท่านั้น
);
create index on ledger_entry (transaction_id);
create index on ledger_entry (account_id);

-- ทุกรายการต้องสมดุล ตรวจตอน commit เพื่อให้ใส่บรรทัดทีละบรรทัดได้
create or replace function ledger_balanced() returns trigger
language plpgsql as $$
declare v_diff numeric(14,2);
begin
  select coalesce(sum(debit) - sum(credit), 0) into v_diff
  from ledger_entry where transaction_id = coalesce(new.transaction_id, old.transaction_id);

  if v_diff <> 0 then
    raise exception 'รายการบัญชีไม่สมดุล เดบิตต่างจากเครดิต % บาท (transaction=%)',
      v_diff, coalesce(new.transaction_id, old.transaction_id);
  end if;
  return null;
end $$;

create constraint trigger ledger_entry_balanced
  after insert or update or delete on ledger_entry
  deferrable initially deferred
  for each row execute function ledger_balanced();

comment on trigger ledger_entry_balanced on ledger_entry is
  'ตรวจตอน commit ไม่ใช่ตอน insert เพื่อให้ใส่บรรทัดเดบิตกับเครดิตทีละบรรทัดได้';

-- ───────────────────────────────────────────────────────────────────
-- โครงสร้างค่าธรรมเนียม
-- ต้องเก็บเลขที่ประกาศอัตราค่าธรรมเนียมไว้ด้วย เพราะโรงเรียนเอกชนต้อง
-- ได้รับอนุมัติก่อนเก็บ และถูกตรวจสอบย้อนหลังได้
-- ───────────────────────────────────────────────────────────────────
create type fee_item_kind as enum (
  'tuition',       -- ค่าเล่าเรียน
  'lab_material',  -- ค่าวัสดุฝึก
  'activity',      -- ค่ากิจกรรม
  'insurance',     -- ค่าประกันอุบัติเหตุ
  'uniform',       -- ค่าเครื่องแบบและชุดปฏิบัติการ
  'book',          -- ค่าหนังสือและอุปกรณ์การเรียน
  'exam',          -- ค่าธรรมเนียมการสอบ
  'dormitory',     -- ค่าหอพัก
  'other'
);

create table fee_item (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  code           text          not null,
  name_th        text          not null,
  kind           fee_item_kind not null,
  subsidised     boolean       not null default false,  -- อยู่ในเงินอุดหนุนเรียนฟรี 15 ปีหรือไม่
  refundable     boolean       not null default false,
  revenue_account_id uuid      references ledger_account,
  unique (institution_id, code)
);
comment on column fee_item.subsidised is
  'รายการที่รัฐอุดหนุนสำหรับ ปวช. แต่ ปวส. ต้องจ่ายเอง ระบบจึงคิดคนละสูตรตามระดับ';

create table fee_schedule (
  id                 uuid                primary key default gen_random_uuid(),
  institution_id     uuid                not null references institution   on delete restrict,
  academic_year_id   uuid                not null references academic_year on delete restrict,
  level              qualification_level not null,
  study_year         smallint            not null check (study_year between 1 and 4),
  program_id         uuid                references program,   -- null = ใช้กับทุกสาขา
  announcement_no    text,                                     -- เลขที่ประกาศอัตราค่าธรรมเนียม
  announced_on       date,
  active             boolean             not null default true,
  unique (institution_id, academic_year_id, level, study_year, program_id)
);

create table fee_schedule_line (
  id               uuid          primary key default gen_random_uuid(),
  fee_schedule_id  uuid          not null references fee_schedule on delete cascade,
  fee_item_id      uuid          not null references fee_item     on delete restrict,
  term_ordinal     smallint      not null check (term_ordinal between 1 and 3),
  amount           numeric(12,2) not null check (amount >= 0),
  unique (fee_schedule_id, fee_item_id, term_ordinal)
);

-- ───────────────────────────────────────────────────────────────────
-- ส่วนลด ทุน และแหล่งเงินภายนอก
-- ───────────────────────────────────────────────────────────────────
create type funding_kind as enum (
  'scholarship',    -- ทุนการศึกษาของวิทยาลัย
  'sibling',        -- ส่วนลดพี่น้อง
  'staff_child',    -- ส่วนลดบุตรบุคลากร
  'gov_subsidy',    -- เงินอุดหนุนรายบุคคล
  'student_loan',   -- กยศ.
  'employer',       -- ทุนสถานประกอบการ
  'other'
);

create table funding_source (
  id             uuid         primary key default gen_random_uuid(),
  institution_id uuid         not null references institution on delete restrict,
  kind           funding_kind not null,
  name_th        text         not null,
  external_ref   text,                                -- เลขที่โครงการหรือรหัสผู้ให้ทุน
  active         boolean      not null default true
);

create table student_funding (
  id                uuid          primary key default gen_random_uuid(),
  student_id        uuid          not null references student        on delete cascade,
  funding_source_id uuid          not null references funding_source on delete restrict,
  academic_year_id  uuid          not null references academic_year  on delete restrict,
  term_id           uuid          references term,          -- null = ใช้ทั้งปี
  percent_off       numeric(5,2)  check (percent_off between 0 and 100),
  amount            numeric(12,2) check (amount >= 0),
  approved_by       uuid,
  approved_at       timestamptz,
  document_no       text,
  note              text,
  check (percent_off is not null or amount is not null)
);
create index on student_funding (student_id, academic_year_id);

-- กยศ. — ต้องติดตามเป็นขั้น เพราะเงินเข้าช้ากว่ากำหนดชำระเสมอ
create type loan_status as enum (
  'draft', 'submitted', 'college_certified', 'approved', 'disbursed', 'rejected', 'cancelled'
);

create table student_loan (
  id                 uuid          primary key default gen_random_uuid(),
  student_id         uuid          not null references student       on delete cascade,
  academic_year_id   uuid          not null references academic_year on delete restrict,
  term_id            uuid          references term,
  loan_type          text          not null default 'ลักษณะที่ 1',
  requested_amount   numeric(12,2) not null,
  approved_amount    numeric(12,2),
  disbursed_amount   numeric(12,2) not null default 0,
  status             loan_status   not null default 'draft',
  submitted_on       date,
  certified_on       date,
  approved_on        date,
  disbursed_on       date,
  external_ref       text,
  note               text,
  unique (student_id, academic_year_id, term_id)
);
create index on student_loan (status) where status <> 'disbursed';

-- ───────────────────────────────────────────────────────────────────
-- ใบแจ้งหนี้และงวดผ่อนชำระ
-- ───────────────────────────────────────────────────────────────────
create type invoice_status as enum ('draft', 'issued', 'partially_paid', 'paid', 'void', 'written_off');

create table invoice (
  id             uuid           primary key default gen_random_uuid(),
  institution_id uuid           not null references institution on delete restrict,
  student_id     uuid           not null references student     on delete restrict,
  term_id        uuid           not null references term        on delete restrict,
  invoice_no     text           not null,
  issued_on      date           not null default current_date,
  due_on         date           not null,
  subtotal       numeric(12,2)  not null default 0,
  discount_total numeric(12,2)  not null default 0,
  total          numeric(12,2)  not null default 0,
  paid_total     numeric(12,2)  not null default 0,
  status         invoice_status not null default 'draft',
  -- อ้างอิงสำหรับ PromptPay Bill Payment
  ref1           text,          -- รหัสนักศึกษา
  ref2           text,          -- เลขที่ใบแจ้งหนี้แบบตัวเลขล้วน
  void_reason    text,
  created_at     timestamptz    not null default now(),
  unique (institution_id, invoice_no),
  unique (student_id, term_id),
  check (total >= 0 and paid_total >= 0)
);
create index on invoice (student_id);
create index on invoice (status, due_on) where status in ('issued', 'partially_paid');
create index on invoice (ref2);

comment on column invoice.ref2 is
  'ตัวเลขล้วน ใช้เป็น Reference 2 ของ PromptPay Bill Payment ซึ่งเป็นกุญแจของการกระทบยอดอัตโนมัติ';

create table invoice_line (
  id           uuid          primary key default gen_random_uuid(),
  invoice_id   uuid          not null references invoice  on delete cascade,
  fee_item_id  uuid          not null references fee_item on delete restrict,
  description  text          not null,
  amount       numeric(12,2) not null,
  discount     numeric(12,2) not null default 0,
  funding_id   uuid          references student_funding,   -- ที่มาของส่วนลด
  check (amount >= 0 and discount >= 0 and discount <= amount)
);
create index on invoice_line (invoice_id);

create type installment_status as enum ('pending', 'partially_paid', 'paid', 'overdue', 'waived');

create table installment (
  id          uuid               primary key default gen_random_uuid(),
  invoice_id  uuid               not null references invoice on delete cascade,
  seq         smallint           not null check (seq > 0),
  due_on      date               not null,
  amount      numeric(12,2)      not null check (amount > 0),
  paid_amount numeric(12,2)      not null default 0,
  penalty     numeric(12,2)      not null default 0,
  status      installment_status not null default 'pending',
  unique (invoice_id, seq)
);
create index on installment (due_on) where status in ('pending', 'partially_paid', 'overdue');

-- ───────────────────────────────────────────────────────────────────
-- การรับชำระ
-- ───────────────────────────────────────────────────────────────────
create type payment_method as enum (
  'cash', 'bank_transfer', 'promptpay', 'credit_card',
  'counter_service', 'direct_debit', 'gov_subsidy', 'student_loan', 'scholarship', 'adjustment'
);
create type payment_status as enum ('pending', 'reconciled', 'rejected', 'refunded');

create table payment (
  id             uuid           primary key default gen_random_uuid(),
  institution_id uuid           not null references institution on delete restrict,
  student_id     uuid           references student,        -- null ได้ตอนยังจับคู่ไม่ได้
  received_on    date           not null,
  amount         numeric(12,2)  not null check (amount > 0),
  method         payment_method not null,
  bank_ref       text,                                     -- เลขอ้างอิงจากธนาคาร
  receipt_no     text,
  status         payment_status not null default 'pending',
  reconciled_at  timestamptz,
  received_by    uuid,
  note           text,
  created_at     timestamptz    not null default now(),
  unique (institution_id, receipt_no)
);
create index on payment (student_id);
create index on payment (status, received_on);

-- เงินก้อนเดียวตัดได้หลายงวด และงวดเดียวรับเงินได้หลายก้อน
create table payment_allocation (
  id             uuid          primary key default gen_random_uuid(),
  payment_id     uuid          not null references payment     on delete cascade,
  installment_id uuid          not null references installment on delete restrict,
  amount         numeric(12,2) not null check (amount > 0),
  allocated_at   timestamptz   not null default now(),
  unique (payment_id, installment_id)
);
create index on payment_allocation (installment_id);

-- ───────────────────────────────────────────────────────────────────
-- รายการเดินบัญชีจากธนาคารและการจับคู่
-- ───────────────────────────────────────────────────────────────────
create type match_state as enum ('unmatched', 'suggested', 'confirmed', 'ignored');

create table bank_transaction (
  id                uuid          primary key default gen_random_uuid(),
  institution_id    uuid          not null references institution on delete restrict,
  posted_at         timestamptz   not null,
  amount            numeric(12,2) not null,
  counterparty      text,                                   -- ชื่อผู้โอน
  bank_ref          text,
  ref1              text,
  ref2              text,
  raw               jsonb         not null default '{}'::jsonb,
  state             match_state   not null default 'unmatched',
  matched_invoice_id uuid         references invoice,
  confidence        smallint      check (confidence between 0 and 100),
  match_reason      text,
  payment_id        uuid          references payment,
  imported_at       timestamptz   not null default now(),
  unique (institution_id, bank_ref, posted_at, amount)
);
create index on bank_transaction (state) where state <> 'confirmed';
create index on bank_transaction (institution_id, posted_at);

-- จำรูปแบบที่เจ้าหน้าที่ยืนยันด้วยมือ เพื่อให้ครั้งต่อไปจับคู่เองได้
create table reconciliation_hint (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  counterparty   text        not null,
  student_id     uuid        not null references student on delete cascade,
  hit_count      integer     not null default 1,
  last_used_at   timestamptz not null default now(),
  unique (institution_id, counterparty)
);
comment on table reconciliation_hint is
  'ผู้ปกครองมักโอนจากบัญชีเดิมทุกงวด การจำชื่อผู้โอนคู่กับนักศึกษาทำให้ครั้งต่อไปจับคู่อัตโนมัติได้';

-- ───────────────────────────────────────────────────────────────────
-- ออกใบแจ้งหนี้จากโครงสร้างค่าธรรมเนียม
-- ───────────────────────────────────────────────────────────────────
create sequence if not exists invoice_no_seq;

-- p_installments เป็น integer ไม่ใช่ smallint เพราะ PostgreSQL ไม่แปลงเลขจำนวนเต็ม
-- ธรรมดาให้เป็น smallint ตอนเลือกฟังก์ชัน ทำให้ผู้เรียกต้อง cast เองทุกครั้ง
create or replace function issue_invoice(
  p_student_id  uuid,
  p_term_id     uuid,
  p_installments integer default 1
) returns uuid language plpgsql as $$
declare
  v_inst      uuid;
  v_year_id   uuid;
  v_level     qualification_level;
  v_study_yr  smallint;
  v_program   uuid;
  v_ordinal   smallint;
  v_sched     uuid;
  v_invoice   uuid;
  v_no        text;
  v_code      text;
  v_subtotal  numeric(12,2) := 0;
  v_discount  numeric(12,2) := 0;
  v_due       date;
  v_year_be   smallint;   -- ปีการศึกษาที่กำลังออกใบแจ้งหนี้
  v_admitted  smallint;   -- ปีที่นักศึกษาเข้าศึกษา ใช้คำนวณชั้นปี
  i           smallint;
begin
  select s.institution_id, s.student_code, s.admitted_year_be
    into v_inst, v_code, v_admitted
  from student s where s.id = p_student_id;

  if v_inst is null then
    raise exception 'ไม่พบนักศึกษา %', p_student_id;
  end if;

  select t.academic_year_id, t.ordinal, ay.year_be
    into v_year_id, v_ordinal, v_year_be
  from term t join academic_year ay on ay.id = t.academic_year_id
  where t.id = p_term_id;

  select p.level, p.id into v_level, v_program
  from student_curriculum sc
  join curriculum_version cv on cv.id = sc.curriculum_version_id
  join curriculum c          on c.id  = cv.curriculum_id
  join program_track pt      on pt.id = c.program_track_id
  join program p             on p.id  = pt.program_id
  where sc.student_id = p_student_id and sc.effective_to is null;

  if v_level is null then
    raise exception 'นักศึกษา % ยังไม่ได้กำหนดหลักสูตร ออกใบแจ้งหนี้ไม่ได้', p_student_id;
  end if;

  -- ชั้นปีคำนวณจากปีการศึกษาที่ออกใบแจ้งหนี้ เทียบกับปีที่เข้าศึกษา
  v_study_yr := least(greatest(v_year_be - v_admitted + 1, 1), 4);

  -- เลือกโครงสร้างค่าธรรมเนียม เจาะจงสาขาก่อน ถ้าไม่มีจึงใช้แบบทั่วไป
  select fs.id into v_sched
  from fee_schedule fs
  where fs.institution_id   = v_inst
    and fs.academic_year_id = v_year_id
    and fs.level            = v_level
    and fs.study_year       = v_study_yr
    and fs.active
    and (fs.program_id = v_program or fs.program_id is null)
  order by fs.program_id nulls last
  limit 1;

  if v_sched is null then
    raise exception 'ไม่พบโครงสร้างค่าธรรมเนียมสำหรับ % ชั้นปี % ปีการศึกษา %', v_level, v_study_yr, v_year_be;
  end if;

  v_no := to_char(v_year_be, 'FM0000') || '-' || lpad(nextval('invoice_no_seq')::text, 6, '0');
  select t.starts_on + 30 into v_due from term t where t.id = p_term_id;

  insert into invoice (institution_id, student_id, term_id, invoice_no, due_on, ref1, ref2, status)
  values (v_inst, p_student_id, p_term_id, 'INV-' || v_no, v_due,
          v_code, regexp_replace(v_no, '\D', '', 'g'), 'draft')
  returning id into v_invoice;

  -- บรรทัดค่าธรรมเนียม พร้อมหักส่วนลดและทุนที่นักศึกษาได้รับ
  insert into invoice_line (invoice_id, fee_item_id, description, amount, discount, funding_id)
  select
    v_invoice,
    fi.id,
    fi.name_th,
    fsl.amount,
    least(
      coalesce(sum(coalesce(sf.amount, fsl.amount * sf.percent_off / 100)), 0),
      fsl.amount
    ),
    (array_agg(sf.id order by sf.id) filter (where sf.id is not null))[1]
  from fee_schedule_line fsl
  join fee_item fi on fi.id = fsl.fee_item_id
  left join student_funding sf
         on sf.student_id       = p_student_id
        and sf.academic_year_id = v_year_id
        and (sf.term_id is null or sf.term_id = p_term_id)
        and sf.approved_at is not null
  where fsl.fee_schedule_id = v_sched
    and fsl.term_ordinal    = v_ordinal
  group by fi.id, fi.name_th, fsl.amount;

  select coalesce(sum(amount), 0), coalesce(sum(discount), 0)
    into v_subtotal, v_discount
  from invoice_line where invoice_id = v_invoice;

  update invoice
  set subtotal = v_subtotal, discount_total = v_discount, total = v_subtotal - v_discount,
      status = 'issued'
  where id = v_invoice;

  -- แบ่งงวด งวดสุดท้ายรับเศษ เพื่อให้ผลรวมตรงกับยอดใบแจ้งหนี้เสมอ
  for i in 1..greatest(p_installments, 1) loop
    insert into installment (invoice_id, seq, due_on, amount)
    values (
      v_invoice, i,
      v_due + ((i - 1) * 60),
      case when i < greatest(p_installments, 1)
           then round((v_subtotal - v_discount) / greatest(p_installments, 1), 2)
           else (v_subtotal - v_discount)
                - round((v_subtotal - v_discount) / greatest(p_installments, 1), 2)
                  * (greatest(p_installments, 1) - 1)
      end
    );
  end loop;

  return v_invoice;
end $$;

comment on function issue_invoice is
  'ออกใบแจ้งหนี้หนึ่งใบต่อนักศึกษาต่อภาคเรียน หักทุนและส่วนลดที่อนุมัติแล้วให้อัตโนมัติ';

-- ───────────────────────────────────────────────────────────────────
-- รับชำระและตัดยอด
-- ตัดงวดที่ครบกำหนดก่อนเสมอ (FIFO) เพื่อให้ค่าปรับล่าช้าคำนวณถูก
-- ───────────────────────────────────────────────────────────────────
create or replace function post_payment(p_payment_id uuid)
returns numeric language plpgsql as $$
declare
  v_remaining numeric(12,2);
  v_student   uuid;
  r           record;
  v_take      numeric(12,2);
begin
  select amount, student_id into v_remaining, v_student
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

  return v_remaining;   -- เงินเหลือที่ยังไม่ได้ตัด (ชำระเกิน)
end $$;

comment on function post_payment is
  'คืนค่าเงินที่เหลือหลังตัดครบทุกงวด ถ้ามากกว่าศูนย์แปลว่าชำระเกิน ต้องให้เจ้าหน้าที่ตัดสินใจว่าจะยกไปงวดหน้าหรือคืนเงิน';

-- ───────────────────────────────────────────────────────────────────
-- กระทบยอดอัตโนมัติ
-- ให้คะแนนความมั่นใจแล้วจับคู่เองเฉพาะที่มั่นใจสูง ที่เหลือส่งให้คนตัดสิน
-- ───────────────────────────────────────────────────────────────────
create or replace function reconcile_bank_transactions(p_institution_id uuid)
returns table (auto_matched integer, suggested integer, unmatched integer)
language plpgsql as $$
declare
  bt        record;
  v_inv     uuid;
  v_conf    smallint;
  v_reason  text;
  v_student uuid;
  v_pay     uuid;
  v_auto    integer := 0;
  v_sug     integer := 0;
begin
  for bt in
    select * from bank_transaction
    where institution_id = p_institution_id and state = 'unmatched' and amount > 0
    order by posted_at
  loop
    v_inv := null; v_conf := 0; v_reason := null;

    -- ระดับ 1: Reference 2 ตรงกับใบแจ้งหนี้ตรง ๆ
    select i.id into v_inv from invoice i
    where i.institution_id = p_institution_id and i.ref2 = bt.ref2
      and i.status in ('issued', 'partially_paid')
    limit 1;
    if v_inv is not null then
      v_conf := 100; v_reason := 'เลขอ้างอิงที่สองตรงกับใบแจ้งหนี้';
    end if;

    -- ระดับ 2: Reference 1 คือรหัสนักศึกษา และยอดตรงกับงวดที่ค้าง
    if v_inv is null and bt.ref1 is not null then
      select i.id into v_inv
      from invoice i
      join student s     on s.id = i.student_id and s.student_code = bt.ref1
      join installment n on n.invoice_id = i.id
      where i.institution_id = p_institution_id
        and i.status in ('issued', 'partially_paid')
        and n.amount + n.penalty - n.paid_amount = bt.amount
      limit 1;
      if v_inv is not null then
        v_conf := 90; v_reason := 'รหัสนักศึกษาและยอดเงินตรงกับงวดที่ค้าง';
      end if;
    end if;

    -- ระดับ 3: เคยยืนยันชื่อผู้โอนคนนี้ไว้แล้ว
    if v_inv is null and bt.counterparty is not null then
      select h.student_id into v_student
      from reconciliation_hint h
      where h.institution_id = p_institution_id and h.counterparty = bt.counterparty;

      if v_student is not null then
        select i.id into v_inv
        from invoice i
        where i.student_id = v_student and i.status in ('issued', 'partially_paid')
        order by i.due_on
        limit 1;
        if v_inv is not null then
          v_conf := 80; v_reason := 'ผู้โอนคนนี้เคยชำระให้นักศึกษาคนนี้มาก่อน';
        end if;
      end if;
    end if;

    -- ระดับ 4: ยอดตรงกับงวดที่ค้างเพียงงวดเดียวในระบบ
    if v_inv is null then
      select i.id into v_inv
      from invoice i
      join installment n on n.invoice_id = i.id
      where i.institution_id = p_institution_id
        and i.status in ('issued', 'partially_paid')
        and n.amount + n.penalty - n.paid_amount = bt.amount
        and n.due_on between bt.posted_at::date - 45 and bt.posted_at::date + 15
      group by i.id
      having count(*) = 1
      limit 1;
      if v_inv is not null then
        v_conf := 60; v_reason := 'ยอดเงินตรงกับงวดที่ค้างเพียงงวดเดียวในช่วงเวลาใกล้เคียง';
      end if;
    end if;

    if v_inv is null then
      continue;
    end if;

    if v_conf >= 90 then
      -- มั่นใจพอที่จะตัดยอดเอง
      select student_id into v_student from invoice where id = v_inv;

      insert into payment (institution_id, student_id, received_on, amount, method,
                           bank_ref, status, note)
      values (p_institution_id, v_student, bt.posted_at::date, bt.amount, 'promptpay',
              bt.bank_ref, 'pending', v_reason)
      returning id into v_pay;

      perform post_payment(v_pay);

      update bank_transaction
      set state = 'confirmed', matched_invoice_id = v_inv, confidence = v_conf,
          match_reason = v_reason, payment_id = v_pay
      where id = bt.id;

      v_auto := v_auto + 1;
    else
      update bank_transaction
      set state = 'suggested', matched_invoice_id = v_inv,
          confidence = v_conf, match_reason = v_reason
      where id = bt.id;

      v_sug := v_sug + 1;
    end if;
  end loop;

  return query
  select v_auto, v_sug,
         (select count(*)::integer from bank_transaction
          where institution_id = p_institution_id and state = 'unmatched');
end $$;

comment on function reconcile_bank_transactions is
  'ตัดยอดเองเฉพาะที่มั่นใจตั้งแต่ 90 ขึ้นไป ที่เหลือขึ้นเป็นข้อเสนอให้เจ้าหน้าที่กดยืนยัน';

-- ───────────────────────────────────────────────────────────────────
-- ค่าปรับล่าช้าและการระงับสิทธิ์
-- งานการเงินเขียน registration_hold งานทะเบียนไม่ต้องรู้จักใบแจ้งหนี้
-- ───────────────────────────────────────────────────────────────────
create table late_fee_policy (
  id                    uuid          primary key default gen_random_uuid(),
  institution_id        uuid          not null references institution on delete cascade,
  effective_from_year_be smallint     not null,
  grace_days            smallint      not null default 7,
  flat_amount           numeric(10,2) not null default 0,
  daily_amount          numeric(10,2) not null default 0,
  max_amount            numeric(10,2),
  hold_after_days       smallint      not null default 30,   -- ค้างกี่วันจึงระงับการลงทะเบียน
  unique (institution_id, effective_from_year_be)
);

create or replace function refresh_finance_holds(p_institution_id uuid)
returns table (placed integer, released integer)
language plpgsql as $$
declare
  v_policy late_fee_policy%rowtype;
  v_placed   integer := 0;
  v_released integer := 0;
  r          record;
begin
  select * into v_policy from late_fee_policy
  where institution_id = p_institution_id
  order by effective_from_year_be desc limit 1;

  if v_policy.id is null then
    raise exception 'ยังไม่ได้ตั้งนโยบายค่าปรับและการระงับสิทธิ์ของสถานศึกษานี้';
  end if;

  -- ตั้งสถานะเกินกำหนดให้งวดที่พ้นกำหนดแล้ว
  update installment i
  set status = 'overdue'
  from invoice inv
  where inv.id = i.invoice_id
    and inv.institution_id = p_institution_id
    and inv.status in ('issued', 'partially_paid')
    and i.status in ('pending', 'partially_paid')
    and i.due_on < current_date - v_policy.grace_days;

  -- ระงับสิทธิ์คนที่ค้างเกินกำหนดและยังไม่ถูกระงับ
  for r in
    select inv.student_id,
           sum(i.amount + i.penalty - i.paid_amount) as owed,
           min(i.due_on)                             as oldest_due,
           min(inv.invoice_no)                       as ref
    from installment i
    join invoice inv on inv.id = i.invoice_id
    where inv.institution_id = p_institution_id
      and inv.status in ('issued', 'partially_paid')
      and i.status <> 'paid'
      and i.due_on < current_date - v_policy.hold_after_days
      and i.amount + i.penalty - i.paid_amount > 0
    group by inv.student_id
  loop
    if not exists (
      select 1 from registration_hold h
      where h.student_id = r.student_id and h.kind = 'finance' and h.released_at is null
    ) then
      insert into registration_hold
        (student_id, kind, reason, amount, source_module, source_ref, blocks_registration)
      values (r.student_id, 'finance',
              format('ค้างชำระเกิน %s วัน ครบกำหนดตั้งแต่ %s',
                     v_policy.hold_after_days, to_char(r.oldest_due, 'DD/MM/YYYY')),
              r.owed, 'finance', r.ref, true);
      v_placed := v_placed + 1;
    end if;
  end loop;

  -- ปลดคนที่ชำระครบแล้ว
  with cleared as (
    select h.id
    from registration_hold h
    join student s on s.id = h.student_id
    where s.institution_id = p_institution_id
      and h.kind = 'finance'
      and h.released_at is null
      and not exists (
        select 1
        from installment i
        join invoice inv on inv.id = i.invoice_id
        where inv.student_id = h.student_id
          and inv.status in ('issued', 'partially_paid')
          and i.status <> 'paid'
          and i.amount + i.penalty - i.paid_amount > 0
      )
  )
  update registration_hold h
  set released_at = now(), release_reason = 'ชำระครบแล้ว ระบบปลดอัตโนมัติ'
  from cleared c where c.id = h.id;

  get diagnostics v_released = row_count;
  return query select v_placed, v_released;
end $$;

comment on function refresh_finance_holds is
  'ให้ตั้งเป็นงานประจำวัน งานทะเบียนไม่ต้องรู้จักใบแจ้งหนี้ เห็นแค่ registration_hold';

-- ───────────────────────────────────────────────────────────────────
-- มุมมองที่หน้าจอใช้
-- ───────────────────────────────────────────────────────────────────
create view v_student_balance as
select
  inv.student_id,
  inv.institution_id,
  sum(inv.total)                                  as billed,
  sum(inv.paid_total)                             as paid,
  sum(inv.total - inv.paid_total)                 as outstanding,
  min(i.due_on) filter (where i.status <> 'paid') as next_due_on,
  max(current_date - i.due_on) filter (where i.status <> 'paid' and i.due_on < current_date)
                                                  as days_overdue
from invoice inv
left join installment i on i.invoice_id = inv.id
where inv.status in ('issued', 'partially_paid')
group by inv.student_id, inv.institution_id;

create view v_ar_aging as
select
  inv.institution_id,
  case
    when i.due_on >= current_date            then 'ยังไม่ครบกำหนด'
    when current_date - i.due_on <= 30       then 'เกิน 1–30 วัน'
    when current_date - i.due_on <= 60       then 'เกิน 31–60 วัน'
    else                                          'เกิน 60 วันขึ้นไป'
  end                                              as bucket,
  count(distinct inv.student_id)                   as students,
  sum(i.amount + i.penalty - i.paid_amount)        as amount
from installment i
join invoice inv on inv.id = i.invoice_id
where inv.status in ('issued', 'partially_paid')
  and i.status <> 'paid'
  and i.amount + i.penalty - i.paid_amount > 0
group by inv.institution_id, 2;

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array[
    'ledger_account', 'ledger_transaction', 'fee_item', 'fee_schedule',
    'funding_source', 'invoice', 'payment', 'bank_transaction',
    'reconciliation_hint', 'late_fee_policy'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

alter table student_funding enable row level security;
alter table student_funding force  row level security;
create policy tenant_isolation on student_funding
  using (exists (select 1 from student s
                 where s.id = student_funding.student_id
                   and s.institution_id = current_institution_id()));

alter table student_loan enable row level security;
alter table student_loan force  row level security;
create policy tenant_isolation on student_loan
  using (exists (select 1 from student s
                 where s.id = student_loan.student_id
                   and s.institution_id = current_institution_id()));

-- นักศึกษาและผู้ปกครองที่ยืนยันตัวตนแล้วเห็นใบแจ้งหนี้ของตน
create policy subject_scope on invoice
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from student s
               where s.id = invoice.student_id and s.person_id = current_actor_id())
    or exists (select 1 from student_guardian sg
               where sg.student_id = invoice.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_finance)
  );

-- บัญชีแยกประเภทแก้ย้อนหลังไม่ได้
create policy ledger_no_rewrite on ledger_transaction
  as restrictive
  using (true)
  with check (posted_at >= now() - interval '1 day');

commit;

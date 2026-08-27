-- ═══════════════════════════════════════════════════════════════════
-- 0080_fee_setup_and_scoped_discounts.sql
-- โครงสร้างค่าเทอมกำหนดเป็นแบบรวมได้ + ส่วนลดรายคนต้องเจาะจงรายการได้
--
-- ─── เจอตอนตรวจว่างานการเงินกำหนดค่าเทอมแยกสาขา/ชั้นปี/ระดับได้ไหม ───
-- พบว่า fee_item · fee_schedule · funding_source ไม่เคยมีเส้นทาง API ให้
-- สร้างเลยสักตัวตั้งแต่ 0010 (มีแต่ rollover_fee_schedules() ที่คัดลอกของ
-- ที่มีอยู่แล้วไปปีถัดไป ไม่ได้สร้างจากศูนย์) วิทยาลัยที่เปิดใหม่จึงตั้ง
-- ค่าเทอมของตัวเองไม่ได้เลยนอกจากมือแตะฐานข้อมูลตรง ๆ — reference-data.sql
-- ตั้งใจไม่ seed ให้ (ราคาเป็นเรื่องของแต่ละวิทยาลัย ถูกแล้ว) แต่ก็ไม่เคยมี
-- ใครสร้างเส้นทางให้วิทยาลัยตั้งเอง รูปเดียวกับข้อ 20 ที่ program_type เจอ
--
-- ─── และร้ายแรงกว่านั้น — สี่ตารางนี้ไม่มีนโยบายบทบาทเลยสักข้อ ───
-- ทดสอบยิงจริงในบริบท app.role = 'student' แล้วทำได้ทั้งสามอย่าง:
--   insert เข้า funding_source (สร้างประเภททุนของทั้งวิทยาลัยเอง)
--   insert เข้า student_funding ให้ตัวเองลด 100% โดยไม่ต้องมีใครอนุมัติ
--     (approved_by/approved_at ว่างได้ — using ไม่มี with check จึงเท่ากับ
--     with check เดียวกัน แต่ using เองก็ไม่เช็คเจ้าของ เช็คแค่ว่านักศึกษา
--     คนนั้นอยู่วิทยาลัยเดียวกัน ไม่ใช่ว่าเป็นนักศึกษาคนนั้นเอง)
--   insert เข้า fee_item (ตั้งรายการค่าธรรมเนียมของทั้งวิทยาลัยเอง)
-- บทเรียนเดียวกับข้อ 16/20 — ตารางที่ไม่มี API ไม่ได้แปลว่าปิด แปลว่ายัง
-- ไม่มีใครดู อ่านโค้ด API ให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้ามกับ
-- ความจริง ปิดด้วย finance_write_only แบบเดียวกับที่ fee_schedule_line
-- มีอยู่แล้วตั้งแต่ 0017 (ไม่รู้ทำไมตัวแม่ทั้งสามไม่เคยได้ตัวเดียวกัน)
--
-- ─── ปัญหาที่สาม — ส่วนลดทุกชนิดของนักศึกษาคนหนึ่งลดทุกรายการเท่ากันหมด ───
-- issue_invoice() รวมส่วนลดทั้งหมดของนักศึกษาแล้วหักจาก "ทุกบรรทัด" ของ
-- ใบแจ้งหนี้เท่ากัน เพราะ join กับ student_funding โดยไม่กรองว่าส่วนลดนั้น
-- ตั้งใจลดรายการไหน — ส่วนลดค่าแรกเข้าอย่างเดียวจะไปลดค่าเทอม ค่ากิจกรรม
-- ค่าประกัน ด้วยเท่ากันหมด และถ้ามีทั้งทุนการศึกษา+กยศ.+ลดค่าแรกเข้าพร้อมกัน
-- ยอดทั้งสามจะถูกบวกรวมแล้วหักซ้ำทุกบรรทัดเหมือนกันหมด ไม่ใช่คนละรายการ
-- ตามที่ควรจะเป็น เพิ่ม fee_item_id ให้ student_funding (ว่าง = ลดทุกรายการ
-- เหมือนเดิม สำหรับทุนที่ตั้งใจลดทั้งใบจริง ๆ เช่น ทุนเรียนดี)
--
-- ─── และ level/study_year ยังไม่รองรับ "รวม" เหมือนที่ program_id รองรับอยู่แล้ว ───
-- program_id ว่างได้มาตั้งแต่ 0010 แปลว่า "ใช้กับทุกสาขา" แต่ level กับ
-- study_year เป็น not null บังคับเจาะจงเสมอ วิทยาลัยที่ค่าเทอมเท่ากันทุก
-- ชั้นปีหรือทุกระดับ (พบได้บ่อยกับค่ากิจกรรม/ค่าประกัน) ต้องสร้างแถวซ้ำ
-- แยกทุกชั้นปีทุกระดับทั้งที่ตัวเลขเหมือนกันทุกใบ ทำให้แก้ทีก็ต้องแก้หลายแถว
-- และพลาดแถวใดแถวหนึ่งได้ง่าย เปิดให้ว่างได้แบบเดียวกับ program_id แล้วให้
-- issue_invoice() เลือกโครงสร้างที่เจาะจงที่สุดก่อนเสมอ (สาขา > ชั้นปี >
-- ระดับ) ถ้าไม่มีเจาะจงพอจึงร่วงไปใช้แบบรวม
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- 1) ปิดช่องโหว่ RLS ก่อน — สี่ตารางนี้ไม่เคยมีนโยบายบทบาทเลย
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['fee_item', 'fee_schedule', 'funding_source'] loop
    execute format($f$
      create policy finance_write_only on %I
        as restrictive
        for all
        using (true)
        with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

-- student_funding ต้องแยกเป็นสองนโยบาย — subject_scope (for all) ให้เจ้าตัว
-- และผู้ปกครองที่ยืนยันแล้วอ่านส่วนลดของตัวเองได้ (โปร่งใสว่าลดเพราะอะไร
-- เท่าไร) ส่วน finance_write_only (เฉพาะ insert/update/delete) จำกัดว่าเขียน
-- ได้เฉพาะบทบาทระดับวิทยาลัย — รวมกันด้วย AND ตามธรรมชาติของ restrictive
-- จึงได้ผลลัพธ์คือ "อ่านได้ถ้าเป็นเจ้าของ/ผู้ปกครอง/เจ้าหน้าที่ เขียนได้
-- เฉพาะเจ้าหน้าที่" ระวังอย่าใช้ for all กับ subject_scope เพราะจะกิน select
-- ของเจ้าของทิ้งไปด้วย (กับดักเดียวกับที่ TEST 231 เจอกับ may_see_sensitive)
create policy subject_scope on student_funding
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from student s
               where s.id = student_funding.student_id and s.person_id = current_actor_id())
    or exists (select 1 from student_guardian sg
               where sg.student_id = student_funding.student_id
                 and sg.person_id  = current_actor_id()
                 and sg.verified_at is not null
                 and sg.can_view_finance)
  );

create policy finance_write_only on student_funding
  as restrictive
  for insert
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy finance_write_only_update on student_funding
  as restrictive
  for update
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'))
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy finance_write_only_delete on student_funding
  as restrictive
  for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

-- ───────────────────────────────────────────────────────────────────
-- 2) ส่วนลดเจาะจงรายการได้ — ว่าง = ลดทุกรายการเหมือนเดิม
-- ───────────────────────────────────────────────────────────────────
alter table student_funding
  add column fee_item_id uuid references fee_item on delete restrict;

comment on column student_funding.fee_item_id is
  'ว่าง = ลดทุกรายการในใบแจ้งหนี้ (เช่น ทุนเรียนดีที่ตั้งใจลดทั้งใบ) ·
   ระบุ = ลดเฉพาะรายการนั้น (เช่น ลดค่าแรกเข้าอย่างเดียว ไม่แตะค่าเทอม)';

-- ───────────────────────────────────────────────────────────────────
-- 3) level/study_year ว่างได้แบบเดียวกับ program_id — ว่าง = ทุกค่า
-- ───────────────────────────────────────────────────────────────────
alter table fee_schedule alter column level drop not null;
alter table fee_schedule alter column study_year drop not null;

alter table fee_schedule drop constraint fee_schedule_study_year_check;
alter table fee_schedule add constraint fee_schedule_study_year_check
  check (study_year is null or study_year between 1 and 4);

comment on column fee_schedule.level is
  'ว่าง = ใช้กับทุกระดับ (ปวช./ปวส.) — เหมือนกับที่ program_id ว่างมาตั้งแต่ 0010';
comment on column fee_schedule.study_year is
  'ว่าง = ใช้กับทุกชั้นปี — พบบ่อยกับค่ากิจกรรม/ค่าประกันที่เท่ากันทุกปี';

-- ───────────────────────────────────────────────────────────────────
-- 4) issue_invoice() — เลือกโครงสร้างที่เจาะจงที่สุดก่อน + ส่วนลดเจาะจงรายการ
-- ───────────────────────────────────────────────────────────────────
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
  v_year_be   smallint;
  v_admitted  smallint;
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
  join program p              on p.id  = pt.program_id
  where sc.student_id = p_student_id and sc.effective_to is null;

  if v_level is null then
    raise exception 'นักศึกษา % ยังไม่ได้กำหนดหลักสูตร ออกใบแจ้งหนี้ไม่ได้', p_student_id;
  end if;

  v_study_yr := least(greatest(v_year_be - v_admitted + 1, 1), 4);

  -- เลือกโครงสร้างค่าธรรมเนียม เจาะจงก่อนเสมอ — สาขา > ชั้นปี > ระดับ
  -- ว่างในมิติไหนแปลว่า "ใช้กับทุกค่าของมิตินั้น" (รูปเดียวกับ program_id
  -- ที่ว่างมาตั้งแต่ 0010 แต่ตอนนี้ครบทั้งสามมิติ)
  select fs.id into v_sched
  from fee_schedule fs
  where fs.institution_id   = v_inst
    and fs.academic_year_id = v_year_id
    and (fs.level = v_level or fs.level is null)
    and (fs.study_year = v_study_yr or fs.study_year is null)
    and fs.active
    and (fs.program_id = v_program or fs.program_id is null)
  order by
    (fs.program_id is not null) desc,
    (fs.study_year is not null) desc,
    (fs.level is not null) desc
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

  -- บรรทัดค่าธรรมเนียม พร้อมหักส่วนลดและทุนที่นักศึกษาได้รับ — เฉพาะส่วนลด
  -- ที่เจาะจงรายการนี้ (fee_item_id ตรงกัน) หรือเจาะจงทุกรายการ (ว่าง)
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
        and (sf.fee_item_id is null or sf.fee_item_id = fi.id)
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
  'ออกใบแจ้งหนี้หนึ่งใบต่อนักศึกษาต่อภาคเรียน หักทุนและส่วนลดที่อนุมัติแล้วให้อัตโนมัติ
   ตามรายการที่ทุน/ส่วนลดนั้นเจาะจงไว้ (ว่าง = ทุกรายการ) เลือกโครงสร้างค่าธรรมเนียม
   ที่เจาะจงสาขา/ชั้นปี/ระดับที่สุดก่อนเสมอ ถ้าไม่มีเจาะจงพอจึงใช้แบบที่ตั้งเป็น "รวม"';

commit;

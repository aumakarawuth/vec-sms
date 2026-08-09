-- ═══════════════════════════════════════════════════════════════════
-- 0027_documents_and_pvrs.sql
--
-- เอกสารของงานทะเบียนและรายงานสำหรับหน่วยงานรัฐ
--
-- ─── ทำไมข้อนี้สำคัญกว่าทุกข้อที่เหลือ ───
-- ระบบนี้จะดีกว่าระบบเดิมของวิทยาลัยแค่ไหนก็ไม่มีความหมาย ถ้าออกระเบียน
-- แสดงผลการเรียนกับใบประกาศนียบัตรไม่ได้ และส่งรายงานให้หน่วยงานรัฐไม่ได้
-- เพราะสองอย่างนี้ไม่ใช่ความสะดวก แต่เป็นระเบียบที่ไม่ทำแล้วผิด
--
-- ─── หลักที่คุมทั้งไฟล์ — เอกสารที่ออกไปแล้วเปลี่ยนไม่ได้ ───
-- เอกสารที่พิมพ์ออกไปแล้วอยู่ในมือคนอื่น ฐานข้อมูลจึงต้องจำ **เนื้อหา ณ
-- เวลาที่ออก** ไม่ใช่วิธีคำนวณเนื้อหา ถ้าเก็บแค่วิธีคำนวณ แล้ววันหนึ่งมีการ
-- แก้เกรดย้อนหลังผ่านคำร้อง หรือแก้ชื่อ-นามสกุล หรือแก้เกณฑ์การจบ
-- การพิมพ์ใบเดิมซ้ำจะได้เอกสารที่ **ไม่ตรงกับใบที่เคยออกไป** โดยไม่มีใคร
-- รู้ตัว ซึ่งกับเอกสารทางราชการแปลว่ามีเอกสารสองใบที่เลขที่เดียวกันแต่
-- เนื้อหาต่างกันลอยอยู่ในโลก
--
-- issued_document.payload จึงเก็บเนื้อหาทั้งใบเป็น jsonb และแถวแก้ไม่ได้
-- หลักเดียวกับ enrollment_result (0006) และ grade_ledger — ยกเลิกได้
-- แต่แก้ทับไม่ได้ เพราะการยกเลิกทิ้งร่องรอยไว้ ส่วนการแก้ทับลบร่องรอย
--
-- ─── ทำไมเลขที่เอกสารต้องมาจากตารางแยก ───
-- เลขที่ใบประกาศนียบัตรและเลขที่ระเบียนแสดงผลการเรียนเป็นเลขทางราชการ
-- ซ้ำกันสองใบไม่ได้ และข้ามเลขโดยไม่มีคำอธิบายก็ไม่ได้ การให้ชั้นแอป
-- คิดเลขถัดไปเองด้วยการ select max()+1 จะชนกันทันทีที่มีเจ้าหน้าที่สองคน
-- กดพร้อมกัน — document_series จึงจ่ายเลขด้วยการ update ที่ล็อกแถวไว้
--
-- ─── ทำไมบังคับว่าเลขที่ใบประกาศนียบัตรเป็นตัวเลขล้วน ───
-- เป็นข้อบังคับตามระเบียบกระทรวง ระบบที่วิทยาลัยใช้อยู่เขียนเตือนไว้ข้างช่อง
-- กรอกว่า "ตามระเบียบกระทรวงต้องเป็นตัวเลขเท่านั้น" ซึ่งเป็นการเตือนที่
-- ข้ามได้ทุกทางที่ไม่ผ่านหน้าจอนั้น กฎแบบนี้จึงต้องอยู่ในฐานข้อมูล
--
-- ─── ทำไมการอนุมัติจบเป็น "ชุด" ไม่ใช่รายคน ───
-- คณะกรรมการวิทยาลัยอนุมัติผู้สำเร็จการศึกษาเป็นมติในวันหนึ่ง ครอบคลุม
-- คนจำนวนหนึ่งพร้อมกัน วันที่อนุมัติจึงเป็นคุณสมบัติของมติ ไม่ใช่ของนักศึกษา
-- ถ้าเก็บวันที่อนุมัติไว้บนตัวนักศึกษาแต่ละคน จะไม่มีทางตอบได้ว่ามติวันนั้น
-- ครอบคลุมใครบ้าง ซึ่งเป็นคำถามแรกที่ถูกถามเวลามีคนมาขอตรวจสอบ
--
-- ─── ขอบเขตที่ยังไม่ครอบคลุม (อ่านก่อนใช้กับข้อมูลจริง) ───
-- ฟังก์ชัน pvrs_rows() ในไฟล์นี้ประกอบ **ข้อมูล** ครบตามช่องที่ระบบเดิม
-- ของวิทยาลัยเก็บไว้ แต่ **รูปแบบไฟล์จริงที่ สอศ. รับ** (ลำดับคอลัมน์
-- ตัวคั่น รหัสอักขระ ชื่อไฟล์) ยังไม่ได้ยืนยันกับสเปกฉบับจริง ต้องเทียบ
-- กับไฟล์ที่วิทยาลัยเคยส่งสำเร็จก่อนใช้งานจริงเสมอ
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ประเภทเอกสาร
-- ───────────────────────────────────────────────────────────────────
create type document_kind as enum (
  'transcript',    -- ระเบียนแสดงผลการเรียน (รบ.)
  'certificate',   -- ใบประกาศนียบัตร
  'certification', -- ใบรับรอง (กำลังศึกษา / สำเร็จการศึกษา)
  'grade_report'   -- ใบแจ้งผลการเรียนรายภาค (สมุดพก)
);

comment on type document_kind is
  'ประเภทเอกสารที่งานทะเบียนออกให้ — แต่ละประเภทมีสายเลขที่ของตัวเองแยกกัน';

-- ───────────────────────────────────────────────────────────────────
-- สายเลขที่เอกสาร
-- ───────────────────────────────────────────────────────────────────
create table document_series (
  institution_id uuid          not null references institution on delete restrict,
  kind           document_kind not null,
  year_be        smallint      not null check (year_be between 2500 and 2700),
  prefix         text          not null default '',
  next_no        integer       not null default 1 check (next_no > 0),
  width          smallint      not null default 5 check (width between 1 and 12),
  primary key (institution_id, kind, year_be),

  -- ระเบียบกระทรวงบังคับว่าเลขที่ใบประกาศนียบัตรเป็นตัวเลขเท่านั้น
  -- คำนำหน้าที่มีตัวอักษรจึงใช้กับสายนี้ไม่ได้ตั้งแต่ต้นทาง
  constraint certificate_prefix_digits_only
    check (kind <> 'certificate' or prefix ~ '^[0-9]*$')
);

comment on table document_series is
  'ตัวจ่ายเลขที่เอกสารแยกตามสถานศึกษา ประเภท และปีการศึกษา — จ่ายด้วยการล็อกแถว ไม่ใช่ max()+1';
comment on column document_series.next_no is
  'เลขถัดไปที่จะจ่าย ค่าปัจจุบันคือเลขที่ยังไม่ถูกใช้';

-- ───────────────────────────────────────────────────────────────────
-- มติอนุมัติผู้สำเร็จการศึกษา
-- ───────────────────────────────────────────────────────────────────
create table graduation_approval (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  approved_on    date        not null,
  term_id        uuid        references term on delete restrict,
  document_no    text,       -- เลขที่หนังสือหรือมติที่ประชุม
  note           text,
  approved_by    uuid        references person on delete restrict,
  created_at     timestamptz not null default now(),
  unique (institution_id, approved_on, document_no)
);

comment on table graduation_approval is
  'มติอนุมัติผู้สำเร็จการศึกษาหนึ่งครั้ง ครอบคลุมนักศึกษาหลายคน — วันที่อนุมัติเป็นของมติ ไม่ใช่ของรายคน';

-- ───────────────────────────────────────────────────────────────────
-- ผู้สำเร็จการศึกษารายคน — หนึ่งแถวคือหนึ่งบรรทัดในรายงานส่ง สอศ.
--
-- gpax และหน่วยกิตถูก "ตรึง" ไว้ที่นี่ ไม่อ่านจาก term_summary ตอนพิมพ์
-- เหตุผลเดียวกับ enrollment_result.attendance_pct — ถ้ามีการแก้เกรด
-- ย้อนหลังหลังอนุมัติจบไปแล้ว ตัวเลขบนใบที่ออกไปแล้วต้องไม่ขยับตาม
-- ───────────────────────────────────────────────────────────────────
create table student_graduation (
  id                       uuid    primary key default gen_random_uuid(),
  institution_id           uuid    not null references institution on delete restrict,
  student_id               uuid    not null references student on delete restrict,
  approval_id              uuid    not null references graduation_approval on delete restrict,
  curriculum_version_id    uuid    not null references curriculum_version on delete restrict,
  completed_on             date    not null,
  completed_term_id        uuid    references term on delete restrict,
  gpax                     numeric(3,2) not null check (gpax >= 0 and gpax <= 4),
  credits_earned           numeric(5,1) not null check (credits_earned >= 0),
  transcript_no            text,
  certificate_no           text,
  professional_standard_no text,
  note                     text,
  created_at               timestamptz not null default now(),

  unique (student_id, approval_id),

  -- ระเบียบกระทรวง — เลขที่ใบประกาศนียบัตรต้องเป็นตัวเลขล้วน
  constraint certificate_no_digits_only
    check (certificate_no is null or certificate_no ~ '^[0-9]+$')
);

-- เลขทางราชการซ้ำกันสองใบไม่ได้ ใช้ดัชนีบางส่วนเพราะช่องนี้ว่างได้
-- ระหว่างที่ยังไม่ได้ออกเลขให้
create unique index student_graduation_certificate_no_uniq
  on student_graduation (institution_id, certificate_no)
  where certificate_no is not null;

create unique index student_graduation_transcript_no_uniq
  on student_graduation (institution_id, transcript_no)
  where transcript_no is not null;

create index student_graduation_approval_idx on student_graduation (approval_id);
create index student_graduation_student_idx   on student_graduation (student_id);

comment on column student_graduation.gpax is
  'ตรึง ณ เวลาอนุมัติจบ ห้ามอ่านใหม่จาก term_summary ตอนพิมพ์ มิฉะนั้นใบที่ออกซ้ำจะไม่ตรงกับใบเดิม';

-- ───────────────────────────────────────────────────────────────────
-- เอกสารที่ออกไปแล้ว
-- ───────────────────────────────────────────────────────────────────
create table issued_document (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  student_id     uuid          not null references student on delete restrict,
  kind           document_kind not null,
  doc_no         text          not null,
  copy_no        smallint      not null default 1 check (copy_no > 0),
  issued_on      date          not null default current_date,
  issued_by      uuid          references person on delete restrict,
  payload        jsonb         not null,
  void_reason    text,
  voided_at      timestamptz,
  voided_by      uuid          references person on delete restrict,
  created_at     timestamptz   not null default now(),

  unique (institution_id, kind, doc_no, copy_no),

  -- ยกเลิกแล้วต้องมีเหตุผลเสมอ การยกเลิกเงียบ ๆ ตรวจสอบย้อนหลังไม่ได้
  constraint void_needs_reason
    check ((voided_at is null and void_reason is null)
        or (voided_at is not null and void_reason is not null))
);

create index issued_document_student_idx on issued_document (student_id, kind, issued_on desc);

comment on table issued_document is
  'เอกสารที่พิมพ์ออกไปแล้ว เก็บเนื้อหาทั้งใบไว้ใน payload — ออกซ้ำต้องได้ใบเดิมเป๊ะ';
comment on column issued_document.copy_no is
  'ฉบับที่ — การออกซ้ำใช้เลขที่เดิมแต่เพิ่มฉบับที่ เพื่อให้รู้ว่ามีกี่ใบลอยอยู่';
comment on column issued_document.payload is
  'เนื้อหาเอกสาร ณ เวลาที่ออก ไม่คำนวณใหม่ตอนพิมพ์ซ้ำ (หลักเดียวกับ enrollment_result.attendance_pct)';

-- แก้ทับไม่ได้ ยกเว้นการยกเลิก
create or replace function issued_document_immutable() returns trigger
language plpgsql as $$
begin
  if (to_jsonb(new) - 'void_reason' - 'voided_at' - 'voided_by')
     is distinct from
     (to_jsonb(old) - 'void_reason' - 'voided_at' - 'voided_by') then
    raise exception 'เอกสารที่ออกไปแล้วแก้ไม่ได้ ให้ยกเลิกแล้วออกใบใหม่ (เลขที่ %)', old.doc_no;
  end if;

  if old.voided_at is not null and new.voided_at is distinct from old.voided_at then
    raise exception 'เอกสารที่ยกเลิกไปแล้วเปลี่ยนการยกเลิกไม่ได้ (เลขที่ %)', old.doc_no;
  end if;

  return new;
end $$;

create trigger issued_document_no_update before update on issued_document
  for each row execute function issued_document_immutable();

create or replace function issued_document_no_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'เอกสารที่ออกไปแล้วลบไม่ได้ ให้ยกเลิกแทน (เลขที่ %)', old.doc_no;
end $$;

create trigger issued_document_block_delete before delete on issued_document
  for each row execute function issued_document_no_delete();

-- ───────────────────────────────────────────────────────────────────
-- จ่ายเลขที่เอกสาร
--
-- update ... returning ล็อกแถวไว้จนจบ transaction เจ้าหน้าที่สองคนที่กด
-- พร้อมกันจึงได้คนละเลขเสมอ ไม่ใช่เลขเดียวกันแบบที่ select max()+1 จะให้
-- ───────────────────────────────────────────────────────────────────
create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint
) returns text language plpgsql as $$
declare
  v_inst   uuid := current_institution_id();
  v_no     integer;
  v_prefix text;
  v_width  smallint;
begin
  if v_inst is null then
    raise exception 'ไม่ทราบสถานศึกษาปัจจุบัน — ชั้นแอปต้องตั้ง app.institution_id ก่อน';
  end if;

  insert into document_series (institution_id, kind, year_be)
  values (v_inst, p_kind, p_year_be)
  on conflict (institution_id, kind, year_be) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = v_inst and kind = p_kind and year_be = p_year_be
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint) is
  'จ่ายเลขที่เอกสารถัดไปแบบกันชนกัน — ล็อกแถวใน document_series ไม่ใช่ select max()+1';

-- ───────────────────────────────────────────────────────────────────
-- เนื้อหาระเบียนแสดงผลการเรียน
--
-- อ่านเฉพาะผลที่เป็นฉบับปัจจุบัน (superseded_by is null) และเฉพาะสัญลักษณ์
-- ที่ระเบียบให้แสดงบนเอกสาร — สัญลักษณ์ชั่วคราวอย่าง ร. หรือ ม.ส. ที่ยัง
-- ไม่ได้แก้ไม่ควรไปโผล่บนใบจริง
-- ───────────────────────────────────────────────────────────────────
create or replace function transcript_data(p_student_id uuid)
returns table (
  year_be        smallint,
  term_ordinal   smallint,
  term_label     text,
  course_code    text,
  course_name_th text,
  credits        numeric(3,1),
  grade_symbol   text,
  grade_point    numeric(2,1),
  credits_earned numeric(3,1),
  category_th    text
) language sql stable as $$
  select
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
    c.code,
    c.name_th,
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    cat.name_th
  from enrollment e
  join class_section cs      on cs.id = e.class_section_id
  join course c              on c.id  = cs.course_id
  join term t                on t.id  = e.term_id
  join academic_year ay      on ay.id = t.academic_year_id
  join enrollment_result er  on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym     on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat on cat.id = cc.curriculum_category_id
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by ay.year_be, t.ordinal, c.code;
$$;

comment on function transcript_data(uuid) is
  'รายวิชาทั้งหมดที่ขึ้นระเบียนแสดงผลการเรียน — ใช้ผลฉบับปัจจุบันและค่าที่ตรึงไว้แล้วเท่านั้น';

-- ───────────────────────────────────────────────────────────────────
-- ออกเอกสารและตรึงเนื้อหา
--
-- คืนแถวใน issued_document ที่เพิ่งสร้าง ชั้น API เอา payload ไปวางลง
-- แม่แบบเพื่อพิมพ์ — การพิมพ์ซ้ำต้องอ่านจาก payload ใบเดิม ไม่ใช่เรียก
-- ฟังก์ชันนี้ใหม่ (เรียกใหม่ = เอกสารคนละใบ คนละเลขที่)
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null
) returns issued_document language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
begin
  -- RLS กันนักศึกษาของวิทยาลัยอื่นไว้แล้ว ตรงนี้กันกรณีรหัสไม่มีอยู่จริง
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;

  v_year := coalesce(
    p_year_be,
    (select max(ay.year_be)
       from student_curriculum sc
       join curriculum_version cv on cv.id = sc.curriculum_version_id
       join academic_year ay on ay.institution_id = v_inst
      where sc.student_id = p_student_id),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year);

  select jsonb_build_object(
    'kind',        p_kind,
    'issued_at',   now(),
    'institution', jsonb_build_object('code', i.code, 'name_th', i.name_th),
    'student',     jsonb_build_object(
                     'student_code', s.student_code,
                     'prefix_th',    coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'birth_date',    p.birth_date,
                     'status',        s.status),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'courses',     coalesce((select jsonb_agg(to_jsonb(td))
                               from transcript_data(p_student_id) td), '[]'::jsonb)
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint) is
  'ออกเอกสารใหม่พร้อมตรึงเนื้อหา — การพิมพ์ซ้ำต้องอ่าน payload ของใบเดิม ไม่ใช่เรียกฟังก์ชันนี้อีกครั้ง';

-- ───────────────────────────────────────────────────────────────────
-- รายงานผู้สำเร็จการศึกษาสำหรับหน่วยงานรัฐ (PVRS)
--
-- ช่องทั้งหมดตรงกับที่ระบบเดิมของวิทยาลัยเก็บ — ดูหมายเหตุเรื่องขอบเขต
-- ที่หัวไฟล์ก่อนนำไปส่งจริง
-- ───────────────────────────────────────────────────────────────────
create or replace function pvrs_rows(p_approval_id uuid)
returns table (
  seq                      bigint,
  student_code             text,
  full_name                text,
  program_name             text,
  qualification            qualification_level,
  completed_on             date,
  completed_term           text,
  exit_reason              text,
  approved_on              date,
  transcript_no            text,
  certificate_no           text,
  professional_standard_no text,
  gpax                     numeric(3,2),
  credits_earned           numeric(5,1),
  note                     text
) language sql stable as $$
  select
    row_number() over (order by s.student_code),
    s.student_code,
    -- coalesce ทุกชิ้น มิฉะนั้นคนที่ไม่มีคำนำหน้าจะได้ชื่อเป็น null ทั้งช่อง
    trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
         || ' ' || coalesce(p.last_name_th, '')),
    pt.name_th || ' - ' || pr.name_th,
    pr.level,
    sg.completed_on,
    case when t.id is null then null
         else 'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be end,
    -- สาเหตุที่ออก อ่านจากประวัติสถานะที่บันทึกไว้ ไม่ใช่เดาจากสถานะปัจจุบัน
    coalesce(
      (select ssh.reason from student_status_history ssh
        where ssh.student_id = s.id and ssh.to_status = 'graduated'
        order by ssh.effective_on desc limit 1),
      'สำเร็จการศึกษาตามหลักสูตร'),
    ga.approved_on,
    sg.transcript_no,
    sg.certificate_no,
    sg.professional_standard_no,
    sg.gpax,
    sg.credits_earned,
    sg.note
  from student_graduation sg
  join graduation_approval ga on ga.id = sg.approval_id
  join student s              on s.id  = sg.student_id
  join person p               on p.id  = s.person_id
  join curriculum_version cv  on cv.id = sg.curriculum_version_id
  join curriculum cur         on cur.id = cv.curriculum_id
  join program_track ptr      on ptr.id = cur.program_track_id
  join program pr             on pr.id  = ptr.program_id
  join program_type pt        on pt.id  = pr.program_type_id
  left join term t            on t.id   = sg.completed_term_id
  left join academic_year ay  on ay.id  = t.academic_year_id
  where sg.approval_id = p_approval_id
  order by s.student_code;
$$;

comment on function pvrs_rows(uuid) is
  'บรรทัดรายงานผู้สำเร็จการศึกษาตามมติหนึ่งครั้ง — ต้องเทียบรูปแบบไฟล์กับสเปก สอศ. ฉบับจริงก่อนส่ง';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security ของตารางใหม่ทั้งสี่
--
-- ทุกตารางต้อง force เสมอ ไม่มีข้อยกเว้น (TEST 45b ตรวจทั้งสคีมา)
-- และ RLS ไม่ถ่ายทอดผ่านคีย์นอก ตารางลูกจึงต้องมีนโยบายของตัวเอง
-- ───────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['document_series', 'graduation_approval',
                           'student_graduation', 'issued_document'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
  end loop;
end $$;

-- ชั้นที่ 2 — ขอบเขตตามบทบาท (restrictive จึงถูก AND กับการแยกวิทยาลัย
-- ถ้าเขียนเป็น permissive มันจะไป OR แล้วเปิดข้อมูลข้ามวิทยาลัยทันที)
--
-- นักศึกษาเห็นเอกสารของตัวเองได้ เพื่อให้แอปแสดงว่าเคยออกใบอะไรไปแล้วบ้าง
-- แต่คนอื่นที่ไม่ใช่เจ้าหน้าที่ต้องไม่เห็นของใครเลย
create policy issued_document_scope on issued_document
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from student s
                where s.id = issued_document.student_id
                  and s.person_id = current_actor_id())
  );

-- เลขที่เอกสารและมติอนุมัติเป็นงานของเจ้าหน้าที่เท่านั้น
create policy document_series_scope on document_series
  as restrictive using (is_institution_wide_role());

create policy graduation_approval_scope on graduation_approval
  as restrictive using (is_institution_wide_role());

create policy student_graduation_scope on student_graduation
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from student s
                where s.id = student_graduation.student_id
                  and s.person_id = current_actor_id())
  );

commit;

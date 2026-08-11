-- ═══════════════════════════════════════════════════════════════════
-- 0057 — ที่เก็บของข้อมูลที่ใบ รบ. ภาษาอังกฤษต้องใช้
--
-- ═══ ทำไมต้องทำตอนนี้ ทั้งที่ยังไม่ได้ทำแม่แบบทั้ง 16 รูปแบบ ═══
-- `issued_document.payload` **แก้ไม่ได้** ใบที่ออกไปแล้วจะไม่มีวันมีข้อความ
-- ภาษาอังกฤษ ต่อให้เพิ่มแม่แบบทีหลังก็ต้องออกใบใหม่ทั้งหมด
-- ข้อมูลที่ไม่ได้เก็บวันนี้ จึงเท่ากับใบที่ต้องออกใหม่ในวันที่รู้รูปแบบ
--
-- แม่แบบเป็นโค้ด แก้เมื่อไรก็ได้ · ที่เก็บข้อมูลเป็นสคีมา ยิ่งช้ายิ่งแพง
-- ไฟล์นี้จึงทำเฉพาะฝั่งที่แพงถ้าช้า และไม่แตะรูปแบบการวางหน้าเลยสักบรรทัด
--
-- ═══ ตรวจแล้วว่าอะไรมีอยู่แล้ว อะไรยังไม่มี ═══
-- มีแล้ว — `person.first_name_en/last_name_en/prefix_en` ·
--   `institution.name_en` · `course.name_en` · `program.name_en`
--   และ `student_status` ครบทุกสาเหตุที่ SISA มี (withdrawn = ลาออก ·
--   dismissed = จำหน่าย · transferred_out = ศึกษาต่อที่อื่น) พร้อมวันที่
--   ใน `student_status_history.effective_on`
-- ยังไม่มี — สามอย่างที่ใบ รบ. พิมพ์จริงทุกใบ (ประเภทวิชา · สาขางาน ·
--   ชื่อหลักสูตร) ไม่มีช่องภาษาอังกฤษเลย · เลขที่ฉบับอังกฤษเป็นคนละสาย ·
--   ผลมาตรฐานวิชาชีพ (มีแต่เลขที่ ไม่มีว่าผ่านหรือไม่) · หมายเหตุภาษาอังกฤษ ·
--   เกณฑ์การสำเร็จการศึกษาห้าบรรทัดที่พิมพ์ท้ายใบ ซึ่งไม่มีที่เก็บทั้งสองภาษา
--
-- ═══ ทำไมฉบับอังกฤษต้องเป็นเอกสารคนละใบ ไม่ใช่แม่แบบอีกแบบของใบเดิม ═══
-- SISA เก็บเลขที่ไว้คนละช่อง (`eng_mass_transcript_no`) ซึ่งแปลว่ามันเป็น
-- เอกสารคนละฉบับในสายตาของงานทะเบียน ไม่ใช่การพิมพ์ใบเดิมด้วยฟอนต์อื่น
-- และเมื่อเป็นคนละฉบับ payload ก็ต้องแยก — ใบภาษาอังกฤษแสดงภาษาอังกฤษ
-- ไม่ใช่แสดงทั้งสองภาษาซ้อนกันในใบเดียว (หลักข้อ 5ก)
--
-- ═══ ทำไมออกใบอังกฤษไม่ได้ถ้าข้อมูลอังกฤษไม่ครบ ═══
-- ถ้าปล่อยให้ออกโดยเติมภาษาไทยแทนช่องที่ว่าง จะได้ใบที่หัวเป็นอังกฤษแต่
-- ชื่อสาขาเป็นไทย ซึ่งเป็นเอกสารทางการที่ดูเหมือนระบบพัง และ**แก้ไม่ได้
-- อีกเลยเพราะ payload ตรึงแล้ว** — ล้มตั้งแต่ตอนกดดีกว่าออกใบที่ใช้ไม่ได้
-- (หลักข้อ 6) ข้อความผิดพลาดบอกชื่อสิ่งที่ยังไม่ได้กรอกเป็นรายการ
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ชื่อภาษาอังกฤษของสิ่งที่ใบ รบ. พิมพ์ทุกใบ
-- ───────────────────────────────────────────────────────────────────
alter table program_type add column if not exists name_en text;
alter table program_track add column if not exists name_en text;
alter table curriculum  add column if not exists name_en text;

comment on column program_type.name_en is
  'ประเภทวิชาภาษาอังกฤษ — ใบ รบ. ฉบับอังกฤษพิมพ์ช่องนี้ ว่างแล้วออกใบไม่ได้';
comment on column program_track.name_en is
  'สาขางานภาษาอังกฤษ — ใบ รบ. ฉบับอังกฤษพิมพ์ช่องนี้ ว่างแล้วออกใบไม่ได้';

-- ───────────────────────────────────────────────────────────────────
-- ข้อมูลผู้สำเร็จการศึกษาที่ใบ รบ. ใช้แต่ยังไม่มีที่เก็บ
-- ───────────────────────────────────────────────────────────────────
alter table student_graduation
  add column if not exists transcript_no_en text,
  add column if not exists note_en          text,
  /*
   * แยก "ผ่านหรือไม่" ออกจาก "เลขที่" เพราะเดิมมีแต่ `professional_standard_no`
   * ซึ่งตอบไม่ได้ว่าคนที่ยังไม่มีเลขคือ **ยังไม่ได้สอบ** หรือ **สอบแล้วไม่ผ่าน**
   * — สองอย่างนี้ต้องพิมพ์บนใบต่างกัน และมีผลต่อการสมัครงานคนละแบบ
   */
  add column if not exists professional_standard_passed boolean,
  add column if not exists professional_standard_on     date;

create unique index if not exists student_graduation_transcript_no_en_uniq
  on student_graduation (institution_id, transcript_no_en)
  where transcript_no_en is not null;

comment on column student_graduation.professional_standard_passed is
  'null = ยังไม่ได้เข้ารับการประเมิน · false = ประเมินแล้วไม่ผ่าน — คนละความหมายกัน ห้ามยุบเป็นค่าเดียว';

-- ───────────────────────────────────────────────────────────────────
-- สายเลขที่แยกตามภาษา
--
-- เดิม primary key เป็น (institution, kind, year) ซึ่งแปลว่าใบไทยกับใบอังกฤษ
-- ใช้เลขสายเดียวกัน — ผิดจากที่งานทะเบียนใช้จริง และแก้ทีหลังไม่ได้เพราะ
-- เลขที่ออกไปแล้วอยู่บนกระดาษของคนอื่น
-- ───────────────────────────────────────────────────────────────────
alter table document_series
  add column if not exists lang text not null default 'th'
    check (lang in ('th', 'en'));

do $$
begin
  if exists (select 1 from pg_constraint
              where conname = 'document_series_pkey'
                and conrelid = 'document_series'::regclass)
     and (select count(*) from pg_index i
           where i.indrelid = 'document_series'::regclass
             and i.indisprimary
             and i.indnatts = 3) = 1
  then
    alter table document_series drop constraint document_series_pkey;
    alter table document_series
      add constraint document_series_pkey
      primary key (institution_id, kind, year_be, lang);
  end if;
end $$;

comment on column document_series.lang is
  'ภาษาของสายเลขที่ — ฉบับภาษาอังกฤษเป็นเอกสารคนละฉบับในสายตางานทะเบียน จึงเดินเลขคนละสาย (ตรงกับ eng_mass_transcript_no ของ SISA)';

-- ───────────────────────────────────────────────────────────────────
-- ข้อความประจำสถานศึกษาที่พิมพ์ท้ายใบ
--
-- เกณฑ์การสำเร็จการศึกษาห้าบรรทัดเป็นข้อความที่แต่ละวิทยาลัยเขียนเอง
-- และต้องมีทั้งสองภาษา — ไม่มีที่เก็บมาก่อนเลย ถ้าปล่อยให้ไปอยู่ในแม่แบบ
-- จะกลายเป็นข้อความของวิทยาลัยเดียวที่ติดไปกับทุกวิทยาลัย
-- ───────────────────────────────────────────────────────────────────
create table if not exists institution_document_text (
  institution_id uuid not null references institution(id) on delete cascade,
  /* ตัวอย่าง 'transcript_criteria_1' … '_5' · 'transcript_footer' */
  key            text not null,
  text_th        text,
  text_en        text,
  updated_at     timestamptz not null default now(),
  primary key (institution_id, key)
);

comment on table institution_document_text is
  'ข้อความประจำสถานศึกษาที่พิมพ์บนเอกสาร เช่น เกณฑ์การสำเร็จการศึกษาห้าบรรทัด — เก็บสองภาษาเพราะใบ รบ. มีทั้งฉบับไทยและอังกฤษ';

alter table institution_document_text enable row level security;
alter table institution_document_text force row level security;

create policy tenant_isolation on institution_document_text
  using (institution_id = current_institution_id());

/*
 * แยกเป็น for insert/update/delete ไม่ใช่ for all — นโยบาย restrictive
 * แบบ for all กิน select ด้วย ซึ่งจะทำให้แม่แบบพิมพ์อ่านข้อความไม่ได้
 * (บทเรียนจาก 0053)
 */
create policy doc_text_insert on institution_document_text
  as restrictive for insert
  with check (current_app_role() in ('registrar', 'director', 'admin'));

create policy doc_text_update on institution_document_text
  as restrictive for update
  using (current_app_role() in ('registrar', 'director', 'admin'))
  with check (current_app_role() in ('registrar', 'director', 'admin'));

create policy doc_text_delete on institution_document_text
  as restrictive for delete
  using (current_app_role() in ('registrar', 'director', 'admin'));

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ตัวจ่ายเลขที่และการออกเอกสาร
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * เพิ่มพารามิเตอร์ภาษาโดยให้ค่าเริ่มต้นเป็น 'th' — การเรียกแบบสองอาร์กิวเมนต์
 * ที่มีอยู่เดิมทั้งหมดจึงทำงานเหมือนเดิมทุกประการ ไม่ต้องไล่แก้
 *
 * **ต้อง drop ตัวเดิมก่อน** เพราะการเพิ่มพารามิเตอร์ที่มีค่าเริ่มต้นสร้าง
 * ฟังก์ชัน**ตัวใหม่**คู่กับตัวเดิม ไม่ใช่แทนที่ แล้วการเรียกแบบสองอาร์กิวเมนต์
 * จะกำกวมทันที (`function next_document_no(unknown, smallint) is not unique`)
 * — กับดักเดียวกับที่ 0029 เขียนเตือนไว้ตอนแก้ issue_document()
 */
drop function if exists next_document_no(document_kind, smallint);

create or replace function next_document_no(
  p_kind    document_kind,
  p_year_be smallint,
  p_lang    text default 'th'
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

  /*
   * ─── ทำไม prefix ตั้งต้นเป็นปีการศึกษา ไม่ใช่ค่าว่าง ───
   * `issued_document` มี unique (institution, kind, doc_no, copy_no) ซึ่ง
   * **ไม่มีปีการศึกษาอยู่ในนั้น** ส่วนตัวนับเริ่มที่ 1 ใหม่ทุกปี — ถ้า prefix
   * เป็นค่าว่าง ปี 2569 กับ 2570 จะออกเลข "00001" เหมือนกันทั้งคู่ แล้ว
   * **ใบแรกของปีการศึกษาใหม่จะล้มด้วย duplicate key** พร้อมข้อความที่
   * อธิบายอะไรไม่ได้เลย
   *
   * อาการนี้โผล่หนึ่งปีหลังเปิดใช้งานพอดี และโผล่กับทุกวิทยาลัยที่ไม่เคย
   * ตั้ง prefix เอง ซึ่งคือทุกวิทยาลัย เพราะแถวถูกสร้างอัตโนมัติตอนออกใบแรก
   * (เจอตอนเขียนเทสต์ของ 0057 ไม่ใช่ตอนออกแบบ)
   *
   * ใช้ปีล้วนเป็นตัวเลขเพราะ `certificate_prefix_digits_only` บังคับว่า
   * สายของใบประกาศนียบัตรมีได้แต่ตัวเลข — วิทยาลัยแก้เป็นรูปแบบของตัวเองได้
   * ที่ `document_series.prefix` ภายหลัง
   */
  insert into document_series (institution_id, kind, year_be, lang, prefix)
  values (v_inst, p_kind, p_year_be, p_lang, p_year_be::text)
  on conflict (institution_id, kind, year_be, lang) do nothing;

  update document_series
     set next_no = next_no + 1
   where institution_id = v_inst and kind = p_kind
     and year_be = p_year_be and lang = p_lang
  returning next_no - 1, prefix, width into v_no, v_prefix, v_width;

  if v_no is null then
    raise exception 'ออกเลขที่เอกสารไม่ได้ ไม่พบสายเลขของสถานศึกษานี้';
  end if;

  return v_prefix || lpad(v_no::text, v_width, '0');
end $$;

comment on function next_document_no(document_kind, smallint, text) is
  'จ่ายเลขที่เอกสารจากสายที่แยกตามสถานศึกษา ประเภท ปีการศึกษา และภาษา — ฉบับอังกฤษเดินเลขคนละสายตามที่งานทะเบียนใช้จริง';

/*
 * ตรวจว่าข้อมูลภาษาอังกฤษครบพอจะออกใบหรือยัง
 *
 * คืนรายการ**ชื่อช่องที่ยังว่าง** ไม่ใช่แค่ true/false เพราะคนที่กดแล้วถูก
 * ปฏิเสธต้องรู้ว่าต้องไปกรอกอะไรบ้าง มิฉะนั้นจะกดซ้ำแล้วเดาไปเรื่อย
 */
create or replace function missing_english_fields(p_student_id uuid)
returns text[] language sql stable as $$
  select coalesce(array_agg(x.label order by x.ord), '{}')
    from (
      select 1 as ord, 'ชื่อ-นามสกุลภาษาอังกฤษของนักศึกษา' as label
       where exists (select 1 from student s join person p on p.id = s.person_id
                      where s.id = p_student_id
                        and (coalesce(p.first_name_en, '') = ''
                          or coalesce(p.last_name_en, '') = ''))
      union all
      select 2, 'ชื่อสถานศึกษาภาษาอังกฤษ'
       where exists (select 1 from student s join institution i on i.id = s.institution_id
                      where s.id = p_student_id and coalesce(i.name_en, '') = '')
      union all
      select 3, 'ประเภทวิชาภาษาอังกฤษ'
       where exists (select 1 from student_curriculum sc
                       join curriculum_version cv on cv.id = sc.curriculum_version_id
                       join curriculum cur on cur.id = cv.curriculum_id
                       join program_track ptr on ptr.id = cur.program_track_id
                       join program pr on pr.id = ptr.program_id
                       join program_type pt on pt.id = pr.program_type_id
                      where sc.student_id = p_student_id
                        and (sc.effective_to is null or sc.effective_to >= current_date)
                        and coalesce(pt.name_en, '') = '')
      union all
      select 4, 'สาขาวิชาภาษาอังกฤษ'
       where exists (select 1 from student_curriculum sc
                       join curriculum_version cv on cv.id = sc.curriculum_version_id
                       join curriculum cur on cur.id = cv.curriculum_id
                       join program_track ptr on ptr.id = cur.program_track_id
                       join program pr on pr.id = ptr.program_id
                      where sc.student_id = p_student_id
                        and (sc.effective_to is null or sc.effective_to >= current_date)
                        and coalesce(pr.name_en, '') = '')
      union all
      select 5, 'สาขางานภาษาอังกฤษ'
       where exists (select 1 from student_curriculum sc
                       join curriculum_version cv on cv.id = sc.curriculum_version_id
                       join curriculum cur on cur.id = cv.curriculum_id
                       join program_track ptr on ptr.id = cur.program_track_id
                      where sc.student_id = p_student_id
                        and (sc.effective_to is null or sc.effective_to >= current_date)
                        and coalesce(ptr.name_en, '') = '')
    ) x
$$;

comment on function missing_english_fields(uuid) is
  'รายชื่อช่องภาษาอังกฤษที่ยังว่างสำหรับนักศึกษารายนั้น — ว่างเปล่าแปลว่าออกใบฉบับอังกฤษได้';

/*
 * รายวิชาที่ยังไม่มีชื่อภาษาอังกฤษในใบของนักศึกษาคนหนึ่ง
 *
 * แยกจากฟังก์ชันข้างบนเพราะจำนวนอาจเป็นสิบ ๆ วิชา การยัดรวมเป็นรายการเดียว
 * จะได้ข้อความผิดพลาดที่ยาวจนอ่านไม่ไหว — ชั้น API เลือกได้ว่าจะแสดงกี่ชื่อ
 */
create or replace function courses_missing_english(p_student_id uuid)
returns table (code text, name_th text) language sql stable as $$
  select distinct c.code, c.name_th
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join course c on c.id = cs.course_id
   where e.student_id = p_student_id
     and e.status <> 'dropped'
     and coalesce(c.name_en, '') = ''
   order by c.code
$$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- issue_document() รับภาษา
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ─── ทำไมแยกเป็นสองฟังก์ชัน ───
 * `issue_document_core()` คือตัวประกอบ payload และเขียนแถว ซึ่งเป็นเนื้อ
 * เดียวกับของ 0029 ทุกประการ ต่างแค่รู้จักภาษา · ส่วน `issue_document()`
 * เป็นด่านตรวจว่าข้อมูลภาษาอังกฤษครบพอจะออกใบไหม
 *
 * แยกเพราะการตรวจกับการประกอบเป็นคนละเรื่อง และการยัดรวมกันจะทำให้
 * เงื่อนไข "ออกไม่ได้" ไปปนอยู่กลางโค้ดที่ยาว 200 บรรทัด จนหาไม่เจอ
 */
create or replace function issue_document_core(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint,
  p_term_id    uuid,
  p_lang       text
)
 RETURNS issued_document
 LANGUAGE plpgsql
AS $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;

  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  if v_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;

  if v_kind = 'grade_report' and p_term_id is null then
    raise exception 'ออกสมุดพกต้องระบุภาคเรียน มิฉะนั้นจะได้ผลการเรียนของภาคที่ไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;

  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;

  v_year := coalesce(
    p_year_be,
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year, p_lang);

  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
    'lang',        p_lang,
    'issued_at',   now(),
    'year_be',     v_year,
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status,
                     -- ฉบับอังกฤษต้องมีชื่ออังกฤษ ซึ่ง issue_document()
                     -- ตรวจแล้วว่าไม่ว่างก่อนเรียกมาถึงตรงนี้
                     'prefix_en',     coalesce(p.prefix_en, ''),
                     'first_name_en', coalesce(p.first_name_en, ''),
                     'last_name_en',  coalesce(p.last_name_en, ''),
                     'full_name_en',  trim(coalesce(p.prefix_en, '')
                                        || ' ' || coalesce(p.first_name_en, '')
                                        || ' ' || coalesce(p.last_name_en, ''))),
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end,
                             'type_en',       coalesce(pt.name_en, ''),
                             'name_en',       coalesce(pr.name_en, ''),
                             'track_en',      coalesce(ptr.name_en, ''),
                             'curriculum_en', coalesce(cur.name_en, ''),
                             'qualification_en',
                               case pr.level
                                 when 'PVC' then 'Vocational Certificate'
                                 when 'PVS' then 'High Vocational Certificate'
                                 when 'TVB' then 'Bachelor of Technology'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t           on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none'))
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  -- ── ข้อความประจำสถานศึกษาและผลมาตรฐานวิชาชีพ ──────────────────────
  -- อยู่บนใบ รบ. และใบประกาศนียบัตรเท่านั้น ใบอื่นไม่ได้พิมพ์เกณฑ์การจบ
  if v_kind in ('transcript', 'certificate') then
    v_payload := v_payload || jsonb_build_object(
      'institution_text',
        coalesce((select jsonb_object_agg(
                           t.key,
                           jsonb_build_object('th', coalesce(t.text_th, ''),
                                              'en', coalesce(t.text_en, '')))
                    from institution_document_text t
                   where t.institution_id = v_inst), '{}'::jsonb),
      'professional_standard',
        (select jsonb_build_object(
                  'no',      coalesce(sg.professional_standard_no, ''),
                  -- null = ยังไม่ได้เข้ารับการประเมิน ซึ่งต่างจาก false
                  -- คือประเมินแล้วไม่ผ่าน สองอย่างนี้พิมพ์บนใบไม่เหมือนกัน
                  'passed',  sg.professional_standard_passed,
                  'on_date', sg.professional_standard_on)
           from student_graduation sg
          where sg.student_id = p_student_id
          order by sg.completed_on desc limit 1));
  end if;

  -- ── ระเบียนแสดงผลการเรียน — ต้องมีรายวิชาทั้งหมดและผลรายภาค ───────
  if v_kind in ('transcript', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'term_summaries',
        coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                    from (select ay.year_be, t.ordinal,
                                 'ภาคเรียนที่ ' || t.ordinal
                                   || ' ปีการศึกษา ' || ay.year_be as label,
                                 ts.gpa, ts.gpax, ts.credits_earned
                            from term_summary ts
                            join term t           on t.id  = ts.term_id
                            join academic_year ay on ay.id = t.academic_year_id
                           where ts.student_id = p_student_id) x), '[]'::jsonb),
      'courses',
        coalesce((select jsonb_agg(to_jsonb(td))
                    from transcript_data(p_student_id) td), '[]'::jsonb));
  end if;

  -- ── สมุดพก — ผลการเรียนประจำภาคพร้อมเวลาเรียนและความประพฤติ ───────
  if v_kind = 'grade_report' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
                  'gpa',     ts.gpa,
                  'gpax',    ts.gpax,
                  'credits_earned', ts.credits_earned)
           from term t
           join academic_year ay on ay.id = t.academic_year_id
           left join term_summary ts
                  on ts.term_id = t.id and ts.student_id = p_student_id
          where t.id = p_term_id),

      -- เวลาเรียนมาจาก v_enrollment_attendance ซึ่งเป็นค่าสด ณ เวลาออกใบ
      -- ต่างจากระเบียนแสดงผลการเรียนที่ใช้ attendance_pct ที่ตรึงตอนตัดเกรด
      -- เพราะสมุดพกมักออกกลางภาคตอนที่ยังไม่มีการตัดเกรด
      'term_courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'course_code',   c.code,
                           'course_name_th', c.name_th,
                           'credits',       c.credits,
                           'grade_symbol',  gsym.symbol,
                           'attendance_pct', v.pct_to_date,
                           'attendance_state', v.attendance_state,
                           'absences_left', v.absences_left)
                           order by c.code)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    left join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join enrollment_result er
                           on er.enrollment_id = e.id and er.superseded_by is null
                    left join grade_symbol gsym on gsym.id = er.grade_symbol_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'), '[]'::jsonb),

      'activities',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'sessions_required', cr.sessions_required,
                           'sessions_attended', cr.sessions_attended,
                           'result', cr.result))
                    from cocurricular_result cr
                   where cr.student_id = p_student_id
                     and cr.term_id = p_term_id), '[]'::jsonb));
  end if;

  -- ── ความประพฤติ — สมุดพกและระเบียนสะสมต้องมี ─────────────────────
  --
  -- behavior_record.points เป็นจำนวนบวกเสมอ (check points > 0 ใน 0011)
  -- ทิศทางหักหรือเพิ่มอยู่ที่ behavior_rule.direction ไม่ใช่ที่เครื่องหมาย
  -- ของตัวเลข การรวมยอดโดยดูเครื่องหมายจึงได้คำตอบผิดแบบดูไม่ออก —
  -- "หนีเรียน" จะกลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์อยู่บนกระดาษ
  --
  -- ยอดคงเหลือจึงอ่านจาก v_behavior_balance ซึ่งเป็นสูตรเดียวกับที่ระบบ
  -- เตือนก่อนออกกลางคันใช้ ไม่เขียนสูตรซ้ำที่นี่ให้มีโอกาสไม่ตรงกัน
  if v_kind in ('grade_report', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'behavior',
        (select jsonb_build_object(
                  'starting_points', bp.starting_points,
                  'deducted', coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'deduct'), 0),
                  'awarded',  coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'award'), 0),
                  'current',  (select vb.balance from v_behavior_balance vb
                                where vb.student_id = p_student_id),
                  'warn_below', bp.warn_below,
                  'critical_below', bp.critical_below)
           from behavior_policy bp
          where bp.institution_id = v_inst));
  end if;

  -- ── ระเบียนสะสม (ปพ.8) ────────────────────────────────────────────
  if v_kind = 'cumulative_record' then
    v_payload := v_payload || jsonb_build_object(
      'guardians',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'relation',  sg.relation,
                           'full_name', trim(coalesce(gp.prefix_th, '')
                                          || coalesce(gp.first_name_th, '')
                                          || ' ' || coalesce(gp.last_name_th, '')),
                           'phone',     coalesce(gp.phone, ''),
                           'is_primary', sg.is_primary)
                           order by sg.is_primary desc)
                    from student_guardian sg
                    join person gp on gp.id = sg.person_id
                   where sg.student_id = p_student_id
                     and sg.verified_at is not null), '[]'::jsonb),

      -- เก็บแค่ระดับผลกับวันที่ ไม่เก็บคำตอบรายข้อ (detail) โดยตั้งใจ
      -- ดูเหตุผลที่หัวไฟล์ — เอกสารนี้ลบไม่ได้และถูกส่งต่อกันไปเรื่อย ๆ
      'screenings',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'instrument',  sr.instrument,
                           'assessed_on', sr.assessed_on,
                           'band',        sr.band)
                           order by sr.assessed_on)
                    from screening_result sr
                   where sr.student_id = p_student_id), '[]'::jsonb),

      -- ส่ง direction ไปด้วยเสมอ เพราะ points เป็นบวกทั้งคู่
      -- ถ้าให้แม่แบบเดาเครื่องหมายเอง ใบจะพิมพ์ว่าหนีเรียนแล้วได้คะแนนเพิ่ม
      'behavior_history',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'occurred_on', br.occurred_on,
                           'points',      br.points,
                           'direction',   brl.direction,
                           'rule_th',     coalesce(brl.name_th, ''),
                           'document_no', coalesce(br.document_no, ''))
                           order by br.occurred_on)
                    from behavior_record br
                    left join behavior_rule brl on brl.id = br.rule_id
                   where br.student_id = p_student_id), '[]'::jsonb),

      'activities_all',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'result',        cr.result,
                           'term_label',    'ภาคเรียนที่ ' || t.ordinal
                                              || '/' || ay.year_be))
                    from cocurricular_result cr
                    join term t           on t.id  = cr.term_id
                    join academic_year ay on ay.id = t.academic_year_id
                   where cr.student_id = p_student_id), '[]'::jsonb),

      -- บันทึกเยี่ยมบ้านมีข้อค้นพบเป็นข้อความอิสระที่อ่อนไหวมาก
      -- ระเบียนสะสมจึงบันทึกแค่ว่า "เคยเยี่ยมกี่ครั้ง ครั้งล่าสุดเมื่อไร"
      'home_visits',
        (select jsonb_build_object(
                  'count', count(*),
                  'last_visited_on', max(hv.visited_on))
           from home_visit hv where hv.student_id = p_student_id));
  end if;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document_core(uuid, document_kind, smallint, uuid, text) is
  'ประกอบ payload และเขียนแถว — ไม่ตรวจความครบของข้อมูลภาษาอังกฤษ ให้ issue_document() ตรวจก่อนเรียก';

/*
 * เปลี่ยนลายเซ็นจึงต้อง drop ก่อน — `create or replace` เปลี่ยนรายการ
 * พารามิเตอร์ไม่ได้ จะกลายเป็นฟังก์ชันคนละตัวแล้วการเรียกแบบสี่อาร์กิวเมนต์
 * จะกำกวมทันที (กับดักเดียวกับที่ 0029 เจอ)
 */
drop function if exists issue_document(uuid, document_kind, smallint, uuid);

create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null,
  p_term_id    uuid     default null,
  p_lang       text     default 'th'
) returns issued_document language plpgsql as $$
declare
  v_row     issued_document;
  v_missing text[];
  v_courses text[];
begin
  if p_lang not in ('th', 'en') then
    raise exception 'ภาษาของเอกสารต้องเป็น th หรือ en เท่านั้น'
      using errcode = 'check_violation';
  end if;

  /*
   * ─── สองเส้นทางต้องปฏิเสธประเภทของกันและกัน**อย่างชัดเจน** ───
   * `issue_student_letter()` ของ 0055 ปฏิเสธใบทั้งห้าของทางนี้ด้วยเงื่อนไข
   * ที่เขียนไว้ตรง ๆ แต่ทางนี้เคยปฏิเสธหนังสือถึงผู้ปกครองโดย**บังเอิญ**
   * (payload ไม่มีสาขาที่รองรับ แล้วไปล้มด้วยเหตุผลอื่นทีหลัง) ซึ่งแปลว่า
   * การเขียนฟังก์ชันใหม่ทำให้การปฏิเสธนั้นหายไปเงียบ ๆ — TEST 247 จับได้
   * ตอนไฟล์นี้เขียนทับ issue_document() พอดี
   *
   * ปฏิเสธโดยบังเอิญกับปฏิเสธโดยตั้งใจให้ผลเหมือนกันวันนี้ แต่ต่างกันมาก
   * ในวันที่มีคนแก้โค้ด
   */
  if p_kind::text in ('absence_notice', 'guardian_invitation', 'conduct_certificate') then
    raise exception 'หนังสือถึงผู้ปกครองและใบรับรองความประพฤติออกด้วย issue_student_letter() '
                    '— payload เป็นคนละชุดกัน (มีผู้รับและที่อยู่ · ไม่มี GPAX)'
      using errcode = 'check_violation';
  end if;

  /*
   * ล้มตั้งแต่ตอนกด ดีกว่าออกใบที่หัวเป็นอังกฤษแต่ชื่อสาขาเป็นไทย
   * ซึ่งเป็นเอกสารทางการที่ดูเหมือนระบบพัง และแก้ไม่ได้อีกเลยเพราะ
   * payload ตรึงแล้ว (หลักข้อ 6)
   */
  if p_lang = 'en' then
    v_missing := missing_english_fields(p_student_id);

    if p_kind::text in ('transcript', 'cumulative_record', 'grade_report') then
      select array_agg(x.code || ' ' || x.name_th)
        into v_courses
        from (select code, name_th from courses_missing_english(p_student_id) limit 5) x;
      if v_courses is not null then
        v_missing := v_missing || ('รายวิชาที่ยังไม่มีชื่อภาษาอังกฤษ: '
                                   || array_to_string(v_courses, ' · '));
      end if;
    end if;

    if array_length(v_missing, 1) > 0 then
      raise exception 'ออกเอกสารฉบับภาษาอังกฤษไม่ได้ ยังไม่ได้กรอก — %',
        array_to_string(v_missing, ' · ')
        using errcode = 'check_violation';
    end if;
  end if;

  v_row := issue_document_core(p_student_id, p_kind, p_year_be, p_term_id, p_lang);
  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint, uuid, text) is
  'ออกเอกสาร — ฉบับภาษาอังกฤษเดินเลขคนละสายและปฏิเสธถ้าข้อมูลภาษาอังกฤษยังไม่ครบ ล้มตั้งแต่กดดีกว่าออกใบที่ใช้ไม่ได้';

commit;

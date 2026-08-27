-- ═══════════════════════════════════════════════════════════════════
-- 0087 — นำเข้าข้อมูลนักศึกษาแบบเต็ม ให้ตรงกับไฟล์แม่แบบของวิทยาลัย
--
-- ─── ปัญหาที่แก้ ───
-- `apply_student_import()` (0023) เขียนแค่ชื่อ/นามสกุล/เพศ/วันเกิด/เบอร์/
-- อีเมลกับ `person`+`student` สองตารางเท่านั้น ทั้งที่ตาราง `person_sensitive`
-- (สุขภาพ) · `person_address` (ที่อยู่) · `student_parent` (บิดามารดา) ·
-- `student_prior_education` (การศึกษาเดิม) มีอยู่แล้วตั้งแต่ 0053 และมี
-- หน้าจอ "ระเบียนนักศึกษา" อ่าน/แก้ได้ครบทุกแท็บ — แต่ไฟล์นำเข้าไม่เคยเขียน
-- ตารางเหล่านี้เลย วิทยาลัยที่นำเข้านักศึกษาเป็นพันคนจะได้แต่ข้อมูลพื้นฐาน
-- แล้วต้องกรอกที่เหลือทีละคนทีละแท็บ ซึ่งเสียเวลาพอ ๆ กับไม่มีระบบนำเข้าเลย
--
-- ไฟล์แม่แบบ ImportFull_VocationalEducation.xlsx (รูปแบบเดียวกับ SISA)
-- มี 80 คอลัมน์ ครอบคลุมนักศึกษา+ผู้ปกครอง+บิดา+มารดา+ที่อยู่สองชุด+สุขภาพ+
-- การศึกษาเดิม — คอลัมน์ส่วนใหญ่มีตารางรองรับอยู่แล้ว งานหลักคือเปิดทางเขียน
-- ให้ครบ ไม่ใช่ออกแบบตารางใหม่
--
-- ─── สิ่งที่ตั้งใจ "ไม่" เชื่อมอัตโนมัติ ───
-- รหัสประเภทวิชา/สาขาวิชา/หลักสูตร/ระดับชั้นในไฟล์เป็นโครงสามชั้น
-- (ประเภท→สาขา→หลักสูตร) แต่ต้นไม้ของระบบนี้ลึกสี่ชั้น (ประเภท→สาขา→
-- สาขางาน→หลักสูตร→ฉบับ) — ไฟล์ไม่มีรหัสสาขางานและไม่มีเลขฉบับหลักสูตร
-- ให้เดา การเดาโครงสร้างที่ไม่มีในไฟล์จะจับคู่ผิดแบบเงียบ ๆ (ระดับความเสียหาย
-- เดียวกับ "ห้อง 301" กับ "301" ก่อน 0034) ปลอดภัยกว่าที่จะเก็บ ห้อง/เลขที่
-- ไว้แล้วให้เจ้าหน้าที่จัดนักศึกษาเข้าห้องจริงที่หน้า "ลงทะเบียนเรียน"
-- (ซึ่งออกแบบมาให้เริ่มจากห้องอยู่แล้ว — ดู CLAUDE.md ข้อ 19)
--
-- ─── ทำไมเลขบัตรประชาชนไม่แฮช/เข้ารหัสในฟังก์ชันนี้ ───
-- กุญแจเข้ารหัส (NATIONAL_ID_KEY) กับกุญแจแฮช (IP_HASH_SECRET) อยู่นอก
-- ฐานข้อมูลโดยตั้งใจ (ดู national-id.ts) ฟังก์ชันนี้จึงรับเฉพาะค่าที่
-- เข้ารหัส/แฮชมาแล้วจากชั้น API เป็นเลขฐานสิบหก (`*_hash_hex`/`*_enc_hex`)
-- ไม่รับเลขบัตรตรงแล้วมาแฮชเองแบบ 0023 เดิม (`digest(..,'sha256')` ไม่มี
-- กุญแจ — ช่องโหว่เดียวกับที่ 0061 ปิดไปแล้วฝั่งหน้าจอแก้ระเบียน)
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table person add column if not exists phone2 text;
comment on column person.phone2 is 'เบอร์โทรศัพท์สำรอง — ไฟล์นำเข้าบางชุดมีสองเบอร์ต่อคน';

alter table person_address
  add column if not exists village_no text,   -- หมู่
  add column if not exists road       text,   -- ถนน
  add column if not exists alley      text,   -- ตรอก
  add column if not exists soi        text,   -- ซอย
  add column if not exists country    text not null default 'ไทย';

alter table student
  add column if not exists room_code text;
comment on column student.room_code is
  'ห้องตามไฟล์นำเข้า — เป็นข้อความอ้างอิงเท่านั้น ยังไม่ผูกกับ class_group จริง '
  'เพราะไฟล์นำเข้าไม่มีข้อมูลพอจะเดาห้องประจำชั้นที่ถูกต้อง (ดูคอมเมนต์บนสุดของไฟล์นี้) '
  'ต้องจัดนักศึกษาเข้าห้องจริงที่หน้า "ลงทะเบียนเรียน" อีกที';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ตรวจแถว — เพิ่มการตรวจฟิลด์ใหม่ ของเดิมยังอยู่ครบ
-- ═══════════════════════════════════════════════════════════════════
create or replace function validate_student_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors text[] := '{}';
  v_code   text := nullif(btrim(p_payload->>'student_code'), '');
  v_first  text := nullif(btrim(p_payload->>'first_name_th'), '');
  v_last   text := nullif(btrim(p_payload->>'last_name_th'), '');
  v_year   text := p_payload->>'admitted_year_be';
  v_nat    text := nullif(btrim(p_payload->>'national_id'), '');
  v_father_nat   text := nullif(btrim(p_payload->>'father_national_id'), '');
  v_mother_nat   text := nullif(btrim(p_payload->>'mother_national_id'), '');
  v_guardian_nat text := nullif(btrim(p_payload->>'guardian_national_id'), '');
  v_gpax   text := nullif(btrim(p_payload->>'prior_gpax'), '');
  v_weight text := nullif(btrim(p_payload->>'weight_kg'), '');
  v_height text := nullif(btrim(p_payload->>'height_cm'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวนักศึกษา');
  elsif exists (select 1 from student s
                 where s.institution_id = p_institution_id and s.student_code = v_code) then
    v_errors := array_append(v_errors, format('รหัสประจำตัว %s มีอยู่ในระบบแล้ว', v_code));
  end if;

  if v_first is null then v_errors := array_append(v_errors, 'ไม่มีชื่อ'); end if;
  if v_last  is null then v_errors := array_append(v_errors, 'ไม่มีนามสกุล'); end if;

  if v_year is null or v_year !~ '^\d{4}$' then
    v_errors := array_append(v_errors, 'ปีที่เข้าศึกษาต้องเป็นพุทธศักราชสี่หลัก');
  elsif v_year::int < 2500 or v_year::int > 2700 then
    v_errors := array_append(v_errors, format('ปีที่เข้าศึกษา %s ไม่อยู่ในช่วงที่รับได้ (2500-2700)', v_year));
  end if;

  -- เลขประจำตัวประชาชนตรวจ checksum ได้ จึงควรตรวจตั้งแต่ตอนนำเข้า
  -- ไม่ใช่ปล่อยให้ผิดแล้วไปเจอตอนออกเอกสารราชการ
  --
  -- ตรวจครบทั้งสี่ช่อง (นักศึกษา/บิดา/มารดา/ผู้ปกครอง) เพราะ ImportService
  -- ที่ชั้น API เข้ารหัส/แฮชเฉพาะเลขที่ผ่าน checksum เท่านั้น — เลขที่ไม่ผ่าน
  -- จะไม่มี *_hash_hex/*_enc_hex ติดมาด้วยเลย ถ้าไม่ตรวจซ้ำที่นี่ แถวนั้นจะผ่าน
  -- การตรวจแบบเงียบ ๆ แล้วช่องเลขบัตรของบิดา/มารดา/ผู้ปกครองว่างเปล่าไปโดย
  -- ไม่มีใครรู้ (ต่างจากเดิมที่ API โยน exception ทั้งคำขอเมื่อเจอเลขบัตรพัง
  -- แม้แค่แถวเดียว ซึ่งบล็อกทั้งไฟล์ — ดูคอมเมนต์ใน encryptNationalIdFields())
  if v_nat is not null then
    if v_nat !~ '^\d{13}$' then
      v_errors := array_append(v_errors, 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก');
    elsif not thai_national_id_valid(v_nat) then
      v_errors := array_append(v_errors, format('เลขประจำตัวประชาชน %s ไม่ผ่านการตรวจหลักที่ 13', v_nat));
    -- ตรวจซ้ำกับนักศึกษาที่มีอยู่แล้ว — ไม่งั้น apply_student_import() จะไป
    -- ชน unique constraint ของ person.national_id_hash เอาตอน insert จริง
    -- ซึ่ง PostgreSQL คืนแค่ชื่อ constraint กลับมา ("person_institution_id_
    -- national_id_hash_key") ไม่ใช่ข้อความที่อ่านรู้เรื่อง แล้วล้มทั้งรอบ
    -- นำเข้าเพราะแถวเดียว (ทั้งที่ผ่านขั้นตรวจไปแล้วโดยไม่มีอะไรฟ้อง)
    elsif p_payload ? 'national_id_hash_hex'
      and exists (select 1 from person p
                   where p.institution_id = p_institution_id
                     and p.national_id_hash = decode(p_payload->>'national_id_hash_hex', 'hex')) then
      v_errors := array_append(v_errors, format('เลขประจำตัวประชาชน %s ซ้ำกับคนที่มีอยู่แล้วในระบบ', v_nat));
    end if;
  end if;

  if v_father_nat is not null and not (v_father_nat ~ '^\d{13}$' and thai_national_id_valid(v_father_nat)) then
    v_errors := array_append(v_errors, format('เลขประจำตัวประชาชนของบิดา %s ไม่ผ่านการตรวจหลักที่ 13', v_father_nat));
  end if;

  if v_mother_nat is not null and not (v_mother_nat ~ '^\d{13}$' and thai_national_id_valid(v_mother_nat)) then
    v_errors := array_append(v_errors, format('เลขประจำตัวประชาชนของมารดา %s ไม่ผ่านการตรวจหลักที่ 13', v_mother_nat));
  end if;

  if v_guardian_nat is not null and not (v_guardian_nat ~ '^\d{13}$' and thai_national_id_valid(v_guardian_nat)) then
    v_errors := array_append(v_errors, format('เลขประจำตัวประชาชนของผู้ปกครอง %s ไม่ผ่านการตรวจหลักที่ 13', v_guardian_nat));
  end if;

  -- ผู้ปกครองลงเป็นแถวใน `person` (คนละตารางกับบิดา/มารดาที่ลงใน
  -- `student_parent` ซึ่ง last_name_th เว้นว่างได้) และ `person.last_name_th`
  -- เป็น NOT NULL — เจอจริงว่าไฟล์บางแถวมีแค่ชื่อผู้ปกครองไม่มีนามสกุล
  -- ถ้าไม่ตรวจตรงนี้ apply_student_import() จะไป insert ชน constraint นั้น
  -- แล้วล้มทั้งรอบนำเข้าเพราะแถวเดียว (ตระกูลเดียวกับเลขบัตรซ้ำด้านบน)
  if nullif(btrim(p_payload->>'guardian_first_name_th'), '') is not null
     and nullif(btrim(p_payload->>'guardian_last_name_th'), '') is null then
    v_errors := array_append(v_errors, 'มีชื่อผู้ปกครองแต่ไม่มีนามสกุลผู้ปกครอง');
  end if;

  if p_payload ? 'status'
     and p_payload->>'status' not in
         ('active','on_leave','suspended','withdrawn','transferred_out','dismissed','graduated') then
    v_errors := array_append(v_errors, format('สถานะ "%s" ไม่ถูกต้อง', p_payload->>'status'));
  end if;

  if p_payload ? 'gender' and nullif(btrim(p_payload->>'gender'), '') is not null
     and p_payload->>'gender' not in ('male', 'female', 'other', 'undisclosed') then
    v_errors := array_append(v_errors, format('เพศ "%s" ไม่ถูกต้อง', p_payload->>'gender'));
  end if;

  if p_payload ? 'blood_type' and nullif(btrim(p_payload->>'blood_type'), '') is not null
     and p_payload->>'blood_type' not in ('A', 'B', 'AB', 'O') then
    v_errors := array_append(v_errors, format('หมู่โลหิต "%s" ไม่ถูกต้อง — ต้องเป็น A, B, AB หรือ O', p_payload->>'blood_type'));
  end if;

  if v_gpax is not null and (v_gpax !~ '^\d(\.\d+)?$' or v_gpax::numeric > 4) then
    v_errors := array_append(v_errors, format('ผลการเรียนเดิม "%s" ต้องเป็นตัวเลข 0-4', v_gpax));
  end if;

  if v_weight is not null and (v_weight !~ '^\d+(\.\d+)?$' or v_weight::numeric not between 10 and 300) then
    v_errors := array_append(v_errors, format('น้ำหนัก "%s" ต้องเป็นตัวเลขระหว่าง 10-300 กก.', v_weight));
  end if;

  if v_height is not null and (v_height !~ '^\d+(\.\d+)?$' or v_height::numeric not between 50 and 250) then
    v_errors := array_append(v_errors, format('ส่วนสูง "%s" ต้องเป็นตัวเลขระหว่าง 50-250 ซม.', v_height));
  end if;

  return v_errors;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย (ของเดิม) ครบทุกตารางที่มี
-- ข้อมูลในไฟล์ (ของใหม่)
-- ═══════════════════════════════════════════════════════════════════
create or replace function apply_student_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch   import_batch%rowtype;
  r         record;
  v_person  uuid;
  v_student uuid;
  v_bad     integer := 0;
  v_ok      integer := 0;
  v_same_addr boolean;
  v_guardian_person uuid;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'student' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ข้อมูลนักศึกษา', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_student_row(v_batch.institution_id, r.payload);
      update import_row
         set errors = v_errs, ok = (cardinality(v_errs) = 0)
       where id = r.id;
      if cardinality(v_errs) > 0 then v_bad := v_bad + 1; end if;
    end;
  end loop;

  if v_bad > 0 then
    update import_batch
       set status = 'failed', error_rows = v_bad,
           ok_rows = (select count(*) from import_row where batch_id = p_batch_id and ok)
     where id = p_batch_id;
    -- ข้อความไม่ชี้ไปที่ import_row เพราะ `raise` rollback การเขียน errors
    -- ข้างบนไปด้วย รายละเอียดรายแถวจึงหายไปพร้อมข้อผิดพลาด (ดู 0043)
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       prefix_en, first_name_en, last_name_en, nickname_th,
       national_id_enc, national_id_hash, national_id_hash_v,
       birth_date, gender, phone, phone2, email, nationality)
    values (
      v_batch.institution_id,
      nullif(btrim(r.payload->>'prefix_th'), ''),
      btrim(r.payload->>'first_name_th'),
      btrim(r.payload->>'last_name_th'),
      nullif(btrim(r.payload->>'prefix_en'), ''),
      nullif(btrim(r.payload->>'first_name_en'), ''),
      nullif(btrim(r.payload->>'last_name_en'), ''),
      nullif(btrim(r.payload->>'nickname_th'), ''),
      -- เข้ารหัส/แฮชมาแล้วจากชั้น API เสมอ — ดูคอมเมนต์บนสุดของไฟล์นี้
      case when r.payload ? 'national_id_enc_hex'
           then decode(r.payload->>'national_id_enc_hex', 'hex') end,
      case when r.payload ? 'national_id_hash_hex'
           then decode(r.payload->>'national_id_hash_hex', 'hex') end,
      case when r.payload ? 'national_id_hash_hex' then 2 else 1 end,
      (nullif(btrim(r.payload->>'birth_date'), ''))::date,
      coalesce(nullif(btrim(r.payload->>'gender'), ''), 'undisclosed')::gender_kind,
      nullif(btrim(r.payload->>'phone'), ''),
      nullif(btrim(r.payload->>'phone2'), ''),
      nullif(btrim(r.payload->>'email'), ''),
      nullif(btrim(r.payload->>'nationality'), '')
    )
    returning id into v_person;

    insert into student
      (institution_id, person_id, student_code, admitted_year_be, status,
       siblings_count, birth_order, siblings_studying, class_number, room_code)
    values (
      v_batch.institution_id, v_person,
      btrim(r.payload->>'student_code'),
      (r.payload->>'admitted_year_be')::smallint,
      coalesce(nullif(btrim(r.payload->>'status'), ''), 'active')::student_status,
      nullif(r.payload->>'siblings_count', '')::smallint,
      nullif(r.payload->>'birth_order', '')::smallint,
      nullif(r.payload->>'siblings_studying', '')::smallint,
      nullif(r.payload->>'class_number', '')::smallint,
      nullif(btrim(r.payload->>'room_code'), '')
    )
    returning id into v_student;

    -- ─── สุขภาพและข้อมูลอ่อนไหว (PDPA ม.26) ─────────────────────────
    if (r.payload ? 'ethnicity') or (r.payload ? 'religion') or (r.payload ? 'blood_type')
       or (r.payload ? 'drug_allergy') or (r.payload ? 'chronic_disease')
       or (r.payload ? 'weight_kg') or (r.payload ? 'height_cm') then
      insert into person_sensitive
        (person_id, institution_id, ethnicity, religion, blood_type,
         drug_allergy, chronic_disease, weight_kg, height_cm)
      values (
        v_person, v_batch.institution_id,
        nullif(btrim(r.payload->>'ethnicity'), ''),
        nullif(btrim(r.payload->>'religion'), ''),
        nullif(btrim(r.payload->>'blood_type'), ''),
        nullif(btrim(r.payload->>'drug_allergy'), ''),
        nullif(btrim(r.payload->>'chronic_disease'), ''),
        nullif(r.payload->>'weight_kg', '')::numeric,
        nullif(r.payload->>'height_cm', '')::numeric
      );
    end if;

    -- ─── ที่อยู่ปัจจุบัน + ทะเบียนบ้าน ───────────────────────────────
    -- "ที่อยู่ปัจจุบันเดียวกับทะเบียนบ้านหรือไม่" (Y/N) — ถ้าใช่ คัดลอกชุด
    -- เดียวกันลงทั้งสอง kind แทนการเว้นแถว 'registered' ว่างไว้ เพราะหน้าจอ
    -- ระเบียนนักศึกษาคาดว่าทั้งสอง kind มีข้อมูลเสมอเมื่อมีคนกรอกที่อยู่มาแล้ว
    v_same_addr := upper(coalesce(nullif(btrim(r.payload->>'address_same_as_registered'), ''), 'Y')) = 'Y';

    if nullif(btrim(r.payload->>'current_address_line'), '') is not null then
      insert into person_address
        (institution_id, person_id, kind, address_line, village_no, road, alley, soi,
         country, subdistrict_th, district_th, province_th, postal_code)
      values (
        v_batch.institution_id, v_person, 'current',
        btrim(r.payload->>'current_address_line'),
        nullif(btrim(r.payload->>'current_village_no'), ''),
        nullif(btrim(r.payload->>'current_road'), ''),
        nullif(btrim(r.payload->>'current_alley'), ''),
        nullif(btrim(r.payload->>'current_soi'), ''),
        coalesce(nullif(btrim(r.payload->>'current_country'), ''), 'ไทย'),
        nullif(btrim(r.payload->>'current_subdistrict_th'), ''),
        nullif(btrim(r.payload->>'current_district_th'), ''),
        nullif(btrim(r.payload->>'current_province_th'), ''),
        nullif(btrim(r.payload->>'current_postal_code'), '')
      )
      on conflict (person_id, kind) do update set
        address_line = excluded.address_line, village_no = excluded.village_no,
        road = excluded.road, alley = excluded.alley, soi = excluded.soi,
        country = excluded.country, subdistrict_th = excluded.subdistrict_th,
        district_th = excluded.district_th, province_th = excluded.province_th,
        postal_code = excluded.postal_code, updated_at = now();
    end if;

    if v_same_addr and nullif(btrim(r.payload->>'current_address_line'), '') is not null then
      insert into person_address
        (institution_id, person_id, kind, address_line, village_no, road, alley, soi,
         country, subdistrict_th, district_th, province_th, postal_code)
      values (
        v_batch.institution_id, v_person, 'registered',
        btrim(r.payload->>'current_address_line'),
        nullif(btrim(r.payload->>'current_village_no'), ''),
        nullif(btrim(r.payload->>'current_road'), ''),
        nullif(btrim(r.payload->>'current_alley'), ''),
        nullif(btrim(r.payload->>'current_soi'), ''),
        coalesce(nullif(btrim(r.payload->>'current_country'), ''), 'ไทย'),
        nullif(btrim(r.payload->>'current_subdistrict_th'), ''),
        nullif(btrim(r.payload->>'current_district_th'), ''),
        nullif(btrim(r.payload->>'current_province_th'), ''),
        nullif(btrim(r.payload->>'current_postal_code'), '')
      )
      on conflict (person_id, kind) do update set
        address_line = excluded.address_line, village_no = excluded.village_no,
        road = excluded.road, alley = excluded.alley, soi = excluded.soi,
        country = excluded.country, subdistrict_th = excluded.subdistrict_th,
        district_th = excluded.district_th, province_th = excluded.province_th,
        postal_code = excluded.postal_code, updated_at = now();
    elsif not v_same_addr and nullif(btrim(r.payload->>'registered_address_line'), '') is not null then
      insert into person_address
        (institution_id, person_id, kind, address_line, village_no, road, alley, soi,
         country, subdistrict_th, district_th, province_th, postal_code)
      values (
        v_batch.institution_id, v_person, 'registered',
        btrim(r.payload->>'registered_address_line'),
        nullif(btrim(r.payload->>'registered_village_no'), ''),
        nullif(btrim(r.payload->>'registered_road'), ''),
        nullif(btrim(r.payload->>'registered_alley'), ''),
        nullif(btrim(r.payload->>'registered_soi'), ''),
        coalesce(nullif(btrim(r.payload->>'registered_country'), ''), 'ไทย'),
        nullif(btrim(r.payload->>'registered_subdistrict_th'), ''),
        nullif(btrim(r.payload->>'registered_district_th'), ''),
        nullif(btrim(r.payload->>'registered_province_th'), ''),
        nullif(btrim(r.payload->>'registered_postal_code'), '')
      )
      on conflict (person_id, kind) do update set
        address_line = excluded.address_line, village_no = excluded.village_no,
        road = excluded.road, alley = excluded.alley, soi = excluded.soi,
        country = excluded.country, subdistrict_th = excluded.subdistrict_th,
        district_th = excluded.district_th, province_th = excluded.province_th,
        postal_code = excluded.postal_code, updated_at = now();
    end if;

    -- ─── บิดา / มารดา — คนละแถว ไม่ผูกกับ person (ดูคอมเมนต์ใน 0053) ──
    if nullif(btrim(r.payload->>'father_first_name_th'), '') is not null then
      insert into student_parent
        (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
         national_id_hash, national_id_hash_v, phone, work_phone, email)
      values (
        v_batch.institution_id, v_student, 'father',
        nullif(btrim(r.payload->>'father_prefix_th'), ''),
        btrim(r.payload->>'father_first_name_th'),
        nullif(btrim(r.payload->>'father_last_name_th'), ''),
        case when r.payload ? 'father_national_id_hash_hex'
             then decode(r.payload->>'father_national_id_hash_hex', 'hex') end,
        case when r.payload ? 'father_national_id_hash_hex' then 2 else 1 end,
        nullif(btrim(r.payload->>'father_phone'), ''),
        nullif(btrim(r.payload->>'father_phone2'), ''),
        nullif(btrim(r.payload->>'father_email'), '')
      )
      on conflict (student_id, role) do update set
        prefix_th = excluded.prefix_th, first_name_th = excluded.first_name_th,
        last_name_th = excluded.last_name_th, national_id_hash = excluded.national_id_hash,
        national_id_hash_v = excluded.national_id_hash_v,
        phone = excluded.phone, work_phone = excluded.work_phone, email = excluded.email,
        updated_at = now();
    end if;

    if nullif(btrim(r.payload->>'mother_first_name_th'), '') is not null then
      insert into student_parent
        (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
         national_id_hash, national_id_hash_v, phone, work_phone, email)
      values (
        v_batch.institution_id, v_student, 'mother',
        nullif(btrim(r.payload->>'mother_prefix_th'), ''),
        btrim(r.payload->>'mother_first_name_th'),
        nullif(btrim(r.payload->>'mother_last_name_th'), ''),
        case when r.payload ? 'mother_national_id_hash_hex'
             then decode(r.payload->>'mother_national_id_hash_hex', 'hex') end,
        case when r.payload ? 'mother_national_id_hash_hex' then 2 else 1 end,
        nullif(btrim(r.payload->>'mother_phone'), ''),
        nullif(btrim(r.payload->>'mother_phone2'), ''),
        nullif(btrim(r.payload->>'mother_email'), '')
      )
      on conflict (student_id, role) do update set
        prefix_th = excluded.prefix_th, first_name_th = excluded.first_name_th,
        last_name_th = excluded.last_name_th, national_id_hash = excluded.national_id_hash,
        national_id_hash_v = excluded.national_id_hash_v,
        phone = excluded.phone, work_phone = excluded.work_phone, email = excluded.email,
        updated_at = now();
    end if;

    -- ─── ผู้ปกครอง (คนละคนจากบิดา/มารดาได้ เช่น ปู่ย่า/ลุงป้า) ────────
    -- สร้าง person ใหม่ให้เสมอ ไม่ค้นหาคนซ้ำข้ามนักศึกษา เพราะเลขบัตรเก็บ
    -- เป็นแฮชเท่านั้น ค้นหาแบบ "คนเดียวกันดูแลหลายคน" ไม่ได้โดยไม่ถอดรหัส
    -- (ผู้ปกครองที่ดูแลพี่น้องหลายคนจะมีแถว person ซ้ำกันคนละแถว — ยอมรับได้
    -- เพราะเป้าหมายของฟิลด์นี้คือช่องทางติดต่อ ไม่ใช่บัญชีผู้ใช้เดียวที่ล็อกอิน)
    if nullif(btrim(r.payload->>'guardian_first_name_th'), '') is not null then
      v_guardian_person := null;

      -- พี่น้องมักมีผู้ปกครองคนเดียวกัน — `person.national_id_hash` ไม่ซ้ำ
      -- ได้ในสถานศึกษาเดียวกัน (unique (institution_id, national_id_hash)
      -- ตั้งแต่ 0002) ถ้าสร้าง person ใหม่ทุกครั้งโดยไม่เช็คก่อน แถวที่สอง
      -- จะชนแล้วทำให้ทั้งรอบนำเข้าล้ม จึงค้นหาคนเดิมก่อนเสมอเมื่อมีเลขบัตร
      if r.payload ? 'guardian_national_id_hash_hex' then
        select id into v_guardian_person
          from person
         where institution_id = v_batch.institution_id
           and national_id_hash = decode(r.payload->>'guardian_national_id_hash_hex', 'hex');
      end if;

      if v_guardian_person is null then
        insert into person
          (institution_id, prefix_th, first_name_th, last_name_th, phone, phone2, email,
           national_id_hash, national_id_hash_v)
        values (
          v_batch.institution_id,
          nullif(btrim(r.payload->>'guardian_prefix_th'), ''),
          btrim(r.payload->>'guardian_first_name_th'),
          nullif(btrim(r.payload->>'guardian_last_name_th'), ''),
          nullif(btrim(r.payload->>'guardian_phone'), ''),
          nullif(btrim(r.payload->>'guardian_phone2'), ''),
          nullif(btrim(r.payload->>'guardian_email'), ''),
          case when r.payload ? 'guardian_national_id_hash_hex'
               then decode(r.payload->>'guardian_national_id_hash_hex', 'hex') end,
          case when r.payload ? 'guardian_national_id_hash_hex' then 2 else 1 end
        )
        returning id into v_guardian_person;
      end if;

      -- ยังไม่ยืนยันตัวตน (verified_at ว่าง) โดยตั้งใจ — การนำเข้าไฟล์ไม่ใช่
      -- การยืนยันตัวตนจริง (ดูคอมเมนต์ verified_at ใน 0053)
      insert into student_guardian
        (student_id, person_id, relation, is_primary)
      values (v_student, v_guardian_person, 'guardian', true)
      on conflict (student_id, person_id) do nothing;
    end if;

    -- ─── การศึกษาเดิม ────────────────────────────────────────────────
    if nullif(btrim(r.payload->>'prior_level_th'), '') is not null then
      insert into student_prior_education
        (institution_id, student_id, level_th, completed_year_be, gpax,
         school_th, province_th, note)
      values (
        v_batch.institution_id, v_student,
        btrim(r.payload->>'prior_level_th'),
        nullif(r.payload->>'prior_completed_year_be', '')::smallint,
        nullif(r.payload->>'prior_gpax', '')::numeric,
        nullif(btrim(r.payload->>'prior_school_th'), ''),
        nullif(btrim(r.payload->>'prior_province_th'), ''),
        case when nullif(btrim(r.payload->>'prior_credit_units'), '') is not null
             then 'หน่วยกิตสะสมจากสถานศึกษาเดิม: ' || btrim(r.payload->>'prior_credit_units') end
      )
      on conflict (student_id, level_th) do nothing;
    end if;

    update import_row set created_ref = v_student, ok = true where id = r.id;
    v_ok := v_ok + 1;
  end loop;

  update import_batch
     set status = 'applied', applied_at = now(),
         ok_rows = v_ok, error_rows = 0, total_rows = v_ok
   where id = p_batch_id;

  imported := v_ok;
  failed   := 0;
  return next;
end $$;

comment on function apply_student_import(uuid) is
  'นำเข้าข้อมูลนักศึกษาทั้งชุด — มีแถวใดผิดจะไม่เขียนอะไรเลย ครอบคลุมข้อมูลพื้นฐาน '
  'สุขภาพ ที่อยู่ บิดามารดา ผู้ปกครอง และการศึกษาเดิม (0087) ไม่ครอบคลุมการจัดห้อง/หลักสูตร '
  'เพราะไฟล์ไม่มีข้อมูลพอจะเดาได้ถูกต้อง (ดูคอมเมนต์บนสุดของ 0087)';

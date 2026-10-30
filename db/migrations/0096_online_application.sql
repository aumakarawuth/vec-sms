-- ═══════════════════════════════════════════════════════════════════
-- 0096_online_application.sql
--
-- สมัครเรียนออนไลน์ — ผู้สมัครกรอกใบสมัครเองจากหน้าสาธารณะ
--
-- ─── ทำไมไฟล์นี้ต้องระวังกว่าไฟล์อื่น ───
-- ทุกเส้นทางก่อนหน้านี้มีคนที่ล็อกอินแล้วเป็นผู้เขียน ส่วนไฟล์นี้เปิด
-- **ทางเดียวที่คนนอกเขียนข้อมูลเข้าระบบได้** โดยไม่มีบัญชี จึงไม่เปิด
-- ตารางใดให้บริบทนั้นเขียนตรงเลยสักตาราง — ทุกอย่างผ่านฟังก์ชัน
-- `security definer` สี่ตัวที่ตรวจกฎเองทุกข้อ (หลักข้อ 1) บริบทที่ชั้น API
-- ตั้งให้เป็นบทบาท `auth` ซึ่ง RLS ชั้นที่ 2 ของ `application` ปฏิเสธอยู่แล้ว
-- (`is_institution_wide_role()` เป็น false) ถ้าวันหนึ่งมีใครเผลอเขียน
-- insert ตรงจากเส้นทางสาธารณะ มันจะล้ม ไม่ใช่สำเร็จเงียบ ๆ
--
-- ─── ยืนยันตัวตนด้วยเลขใบสมัคร + รหัสลับ ไม่ใช่เลขบัตร + วันเกิด ───
-- เลขบัตรและวันเกิดของเด็กคือสิ่งที่ครอบครัว เพื่อน และครูที่โรงเรียนเดิม
-- รู้กันหมด ใครก็เปิดดูและแก้ใบของคนอื่นได้ ส่วน OTP ทางอีเมล/SMS ยังไม่มี
-- ผู้ให้บริการ (ดู "ยังไม่ได้ผูกผู้ให้บริการอีเมล/SMS" ใน CLAUDE.md)
-- รหัสลับสุ่มที่ชั้น API ตอนยื่น แสดงครั้งเดียว และฐานข้อมูลเก็บแค่ค่า
-- HMAC ด้วยกุญแจที่อยู่นอกฐานข้อมูล หลักเดียวกับรหัสรีเซ็ต (0025/0061)
--
-- ─── ตัวนับเดาผิดอยู่ที่ฐานข้อมูล และฟังก์ชันห้าม raise เมื่อเดาผิด ───
-- ถ้า raise การ rollback จะล้างตัวนับทิ้งทุกครั้ง แล้วเดารหัสได้ไม่จำกัด
-- (กับดักเดียวกับ consume_password_reset / verifyStepCommitted) จึงคืน
-- outcome ให้ชั้น API โยนเองข้างนอกทรานแซกชัน และค้นใบจากเลขใบสมัครก่อน
-- แล้วค่อยเทียบค่าแฮช — ค้นจากค่าแฮชตรง ๆ จะไม่มีแถวให้เพิ่มตัวนับ
--
-- ─── ผลการคัดเลือกห้ามรั่วก่อนวันประกาศ ───
-- เจ้าหน้าที่บันทึกผลทีละคนได้ก่อนประกาศหลายวัน ถ้าหน้าสถานะอ่าน
-- `application.status` ตรง ๆ ผู้สมัครจะรู้ผลก่อน (และรู้ก่อนกันไม่พร้อมกัน)
-- จึงแสดง "ยื่นแล้ว" จนกว่ารอบจะเป็น announced
--
-- ─── ไม่รับไฟล์แนบ ───
-- สำเนาบัตร รูปถ่าย และวุฒิของผู้เยาว์คือข้อมูลที่เอาออกยากที่สุด ทั้งที่
-- วิทยาลัยต้องเห็นตัวจริงวันมอบตัวอยู่ดี (PDPA เก็บเท่าที่จำเป็น)
-- และไฟล์จากคนนอกที่ไม่ได้ล็อกอินเป็นช่องโจมตีที่ไม่คุ้มเปิด เจ้าหน้าที่
-- ยังบันทึกการรับหลักฐานใน `application_document` ได้ตามเดิม
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table application
  add column if not exists submitted_via text not null default 'staff'
    check (submitted_via in ('staff', 'online'));

comment on column application.submitted_via is
  'ใครเป็นคนกรอก — online แปลว่าผู้สมัครกรอกเอง ข้อมูลยังไม่ผ่านตาเจ้าหน้าที่';

-- ───────────────────────────────────────────────────────────────────
-- สิทธิ์เข้าดู/แก้ใบสมัครของผู้สมัคร
--
-- แยกตารางจาก application เพราะเจ้าหน้าที่ที่ทำงานกับใบสมัครทั้งวันต้องไม่มี
-- ทางเขียนค่าแฮชหรือล้างตัวนับได้ — ตารางนี้ไม่มีนโยบายเขียนเลยสักข้อ
-- RLS จึงปฏิเสธการเขียนทุกบทบาท เขียนได้เฉพาะผ่านฟังก์ชันในไฟล์นี้
-- ───────────────────────────────────────────────────────────────────
create table application_access (
  application_id uuid        primary key references application on delete cascade,
  institution_id uuid        not null references institution on delete restrict,
  secret_hash    bytea       not null check (octet_length(secret_hash) = 32),
  failed_count   smallint    not null default 0,
  locked_until   timestamptz,
  last_seen_at   timestamptz,
  created_at     timestamptz not null default now()
);

comment on table application_access is
  'รหัสลับของผู้สมัครออนไลน์ (เก็บแค่ HMAC) และตัวนับเดาผิด — เขียนได้เฉพาะผ่านฟังก์ชัน apply_*';

alter table application_access enable row level security;
alter table application_access force  row level security;

create policy tenant_isolation on application_access
  for select using (institution_id = current_institution_id());
create policy application_access_scope on application_access
  as restrictive for select using (is_institution_wide_role());

-- ───────────────────────────────────────────────────────────────────
-- ตัวช่วยภายใน
-- ───────────────────────────────────────────────────────────────────

-- ข้อความจากฟอร์ม — ตัดช่องว่าง ค่าว่างเป็น null และจำกัดความยาว
-- ความยาวต้องจำกัดที่นี่ เพราะเส้นทางนี้ใครก็ยิงได้ ข้อความยาวหนึ่งเมกะไบต์
-- ต่อช่องจะเข้าไปนั่งในตารางที่เจ้าหน้าที่เปิดดูทุกวัน
create or replace function apply_text(p jsonb, p_key text, p_max integer, p_label text)
returns text language plpgsql immutable as $$
declare v text := nullif(btrim(p ->> p_key), '');
begin
  if v is not null and char_length(v) > p_max then
    raise exception '% ยาวเกิน % ตัวอักษร', p_label, p_max using errcode = 'check_violation';
  end if;
  return v;
end $$;

-- อันดับที่เลือกต้องเป็นหลักสูตรที่รอบนี้เปิดโควตาไว้ — มิฉะนั้นผู้สมัคร
-- จะเลือกหลักสูตรใดก็ได้ของวิทยาลัย รวมถึงฉบับที่เลิกใช้แล้ว
create or replace function apply_check_choices(p_round_id uuid, p_choices uuid[])
returns void language plpgsql stable security definer set search_path = public as $$
declare v_n integer := coalesce(array_length(p_choices, 1), 0);
begin
  if v_n = 0 then
    raise exception 'ต้องเลือกสาขาที่ต้องการเรียนอย่างน้อยหนึ่งอันดับ' using errcode = 'check_violation';
  end if;
  if v_n > 3 then
    raise exception 'เลือกได้ไม่เกินสามอันดับ' using errcode = 'check_violation';
  end if;
  if (select count(distinct c) from unnest(p_choices) c) <> v_n then
    raise exception 'เลือกสาขาเดิมซ้ำสองอันดับไม่ได้' using errcode = 'check_violation';
  end if;
  if exists (select 1 from unnest(p_choices) c
              where not exists (select 1 from admission_quota q
                                 where q.round_id = p_round_id
                                   and q.curriculum_version_id = c)) then
    raise exception 'สาขาที่เลือกไม่ได้เปิดรับในรอบนี้' using errcode = 'check_violation';
  end if;
end $$;

-- ตรวจข้อมูลที่ผู้สมัครกรอกให้ครบในที่เดียว ทั้งตอนยื่นและตอนแก้
create or replace function apply_check_form(p jsonb)
returns void language plpgsql stable as $$
declare
  v_birth date;
  v_gpax  numeric;
begin
  if apply_text(p, 'first_name_th', 100, 'ชื่อ') is null
     or apply_text(p, 'last_name_th', 100, 'นามสกุล') is null then
    raise exception 'กรอกชื่อและนามสกุล' using errcode = 'check_violation';
  end if;

  begin
    v_birth := (p ->> 'birth_date')::date;
  exception when others then
    raise exception 'วันเกิดไม่ถูกต้อง' using errcode = 'check_violation';
  end;
  -- ปี พ.ศ. ที่หลุดมาเป็น ค.ศ. (2554 → ค.ศ. 2554) จะอยู่ในอนาคต — ดักไว้
  -- ตรงนี้ ไม่ใช่ปล่อยให้เจ้าหน้าที่เจอตอนรับเข้า (บทเรียนข้อ 23)
  if v_birth is null or v_birth >= current_date - interval '10 years'
     or v_birth < current_date - interval '80 years' then
    raise exception 'วันเกิดไม่ถูกต้อง (กรอกเป็นปฏิทินของเบราว์เซอร์ ไม่ต้องแปลงเป็น พ.ศ. เอง)'
      using errcode = 'check_violation';
  end if;

  if coalesce(p ->> 'gender', 'undisclosed') not in ('male', 'female', 'other', 'undisclosed') then
    raise exception 'เพศไม่ถูกต้อง' using errcode = 'check_violation';
  end if;

  -- เบอร์โทรเป็นช่องทางเดียวที่วิทยาลัยติดต่อผู้สมัครได้ (ไม่มีอีเมลบังคับ)
  if coalesce(regexp_replace(p ->> 'phone', '[^0-9]', '', 'g'), '') !~ '^0[0-9]{8,9}$' then
    raise exception 'เบอร์โทรศัพท์ต้องเป็นตัวเลข 9–10 หลักขึ้นต้นด้วย 0' using errcode = 'check_violation';
  end if;

  if nullif(p ->> 'prior_gpax', '') is not null then
    begin
      v_gpax := (p ->> 'prior_gpax')::numeric;
    exception when others then
      raise exception 'เกรดเฉลี่ยไม่ถูกต้อง' using errcode = 'check_violation';
    end;
    if v_gpax < 0 or v_gpax > 4 then
      raise exception 'เกรดเฉลี่ยต้องอยู่ระหว่าง 0.00 ถึง 4.00' using errcode = 'check_violation';
    end if;
  end if;

  perform apply_text(p, 'prefix_th', 30, 'คำนำหน้า'),
          apply_text(p, 'email', 200, 'อีเมล'),
          apply_text(p, 'address_th', 500, 'ที่อยู่'),
          apply_text(p, 'prior_school_th', 200, 'โรงเรียนเดิม'),
          apply_text(p, 'prior_qualification_th', 100, 'วุฒิเดิม'),
          apply_text(p, 'referral_source', 100, 'ช่องทางที่รู้จักวิทยาลัย'),
          apply_text(p, 'father_first_name_th', 100, 'ชื่อบิดา'),
          apply_text(p, 'father_last_name_th', 100, 'นามสกุลบิดา'),
          apply_text(p, 'father_occupation_th', 100, 'อาชีพบิดา'),
          apply_text(p, 'father_phone', 20, 'เบอร์โทรบิดา'),
          apply_text(p, 'mother_first_name_th', 100, 'ชื่อมารดา'),
          apply_text(p, 'mother_last_name_th', 100, 'นามสกุลมารดา'),
          apply_text(p, 'mother_occupation_th', 100, 'อาชีพมารดา'),
          apply_text(p, 'mother_phone', 20, 'เบอร์โทรมารดา');
end $$;

-- แก้ได้ตราบที่ยังไม่มีเจ้าหน้าที่แตะใบนี้ — พอเริ่มตรวจหลักฐานหรือ
-- ตัดสินผลแล้ว ข้อมูลที่เจ้าหน้าที่เห็นต้องไม่เปลี่ยนใต้มือเขา
create or replace function apply_editable(p_app application)
returns boolean language sql stable security definer set search_path = public as $$
  select p_app.status = 'submitted'
     and p_app.submitted_via = 'online'
     and p_app.decided_at is null
     and not exists (select 1 from application_document d where d.application_id = p_app.id)
     and exists (select 1 from admission_round ar
                  where ar.id = p_app.round_id and ar.status = 'open'
                    and current_date between ar.applies_from and ar.applies_to)
$$;

-- สิ่งที่ผู้สมัครเห็น — ไม่มีค่าแฮช ไม่มีคะแนน/อันดับ/บันทึกของกรรมการ
create or replace function apply_public_view(p_app application)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_round   admission_round;
  v_status  text := p_app.status::text;
  v_edit    boolean := apply_editable(p_app);
begin
  select * into v_round from admission_round where id = p_app.round_id;

  if v_status in ('passed', 'failed', 'waitlisted')
     and v_round.status not in ('announced', 'completed') then
    v_status := 'submitted';
  end if;

  return jsonb_build_object(
    'application_no', p_app.application_no,
    'full_name', btrim(coalesce(p_app.prefix_th, '') || p_app.first_name_th || ' ' || p_app.last_name_th),
    'round_name', v_round.name_th,
    'status', v_status,
    'submitted_at', p_app.submitted_at,
    'exam_on', v_round.exam_on,
    'announce_on', v_round.announce_on,
    'report_from', v_round.report_from,
    'report_to', v_round.report_to,
    'admitted_curriculum', case when v_status in ('passed', 'enrolled') then
        (select cur.name_th from curriculum_version cv join curriculum cur on cur.id = cv.curriculum_id
          where cv.id = p_app.admitted_curriculum_version_id) end,
    'choices', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'preference', ac.preference,
                 'curriculum_version_id', ac.curriculum_version_id,
                 'curriculum_th', cur.name_th,
                 'shift', cur.shift) order by ac.preference)
          from application_choice ac
          join curriculum_version cv on cv.id = ac.curriculum_version_id
          join curriculum cur        on cur.id = cv.curriculum_id
         where ac.application_id = p_app.id), '[]'::jsonb),
    'editable', v_edit,
    -- ข้อมูลในฟอร์มส่งกลับเฉพาะตอนที่ยังแก้ได้ — หลังจากนั้นไม่มีเหตุให้
    -- หน้าสาธารณะถือที่อยู่และข้อมูลผู้ปกครองของผู้เยาว์ไว้อีก
    'form', case when v_edit then jsonb_build_object(
        'prefix_th', p_app.prefix_th, 'first_name_th', p_app.first_name_th,
        'last_name_th', p_app.last_name_th, 'birth_date', p_app.birth_date,
        'gender', p_app.gender, 'phone', p_app.phone, 'email', p_app.email,
        'address_th', p_app.address_th, 'prior_school_th', p_app.prior_school_th,
        'prior_qualification_th', p_app.prior_qualification_th, 'prior_gpax', p_app.prior_gpax,
        'referral_source', p_app.referral_source,
        'father_first_name_th', p_app.father_first_name_th, 'father_last_name_th', p_app.father_last_name_th,
        'father_occupation_th', p_app.father_occupation_th, 'father_phone', p_app.father_phone,
        'mother_first_name_th', p_app.mother_first_name_th, 'mother_last_name_th', p_app.mother_last_name_th,
        'mother_occupation_th', p_app.mother_occupation_th, 'mother_phone', p_app.mother_phone) end
  );
end $$;

-- ยืนยันตัวผู้สมัคร — คืน id ของใบเมื่อรหัสถูก ไม่ raise เมื่อผิด
--
-- เลขใบสมัครไม่ unique ระดับวิทยาลัย (unique ต่อรอบ และรหัสรอบซ้ำได้
-- ข้ามปีการศึกษา) จึงเทียบกับทุกใบที่เลขตรง ถ้าผิดเพิ่มตัวนับทุกใบ
-- เดาผิดห้าครั้งล็อกสิบห้านาที — ร่วมกับตัวจำกัดคำขอรายไอพี รหัสสุ่ม
-- 8 ตัวจากอักษร 31 ตัว (~2^39) ไม่มีทางเดาครบ
create or replace function apply_authenticate(p_application_no text, p_secret_hash bytea)
returns table (application_id uuid, outcome text, retry_after_secs integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_inst   uuid := current_institution_id();
  v_hit    uuid;
  v_locked timestamptz;
begin
  if v_inst is null then
    raise exception 'ไม่ได้ระบุสถานศึกษา';
  end if;

  select max(x.locked_until) into v_locked
    from application_access x join application a on a.id = x.application_id
   where a.institution_id = v_inst and a.application_no = btrim(p_application_no)
     and x.locked_until > now();
  if v_locked is not null then
    return query select null::uuid, 'locked'::text,
                        ceil(extract(epoch from v_locked - now()))::integer;
    return;
  end if;

  select x.application_id into v_hit
    from application_access x join application a on a.id = x.application_id
   where a.institution_id = v_inst and a.application_no = btrim(p_application_no)
     and x.secret_hash = p_secret_hash
   limit 1;

  if v_hit is null then
    update application_access x
       set failed_count = case when x.failed_count + 1 >= 5 then 0 else x.failed_count + 1 end,
           locked_until = case when x.failed_count + 1 >= 5 then now() + interval '15 minutes'
                               else x.locked_until end
      from application a
     where a.id = x.application_id and a.institution_id = v_inst
       and a.application_no = btrim(p_application_no);
    return query select null::uuid, 'invalid'::text, 0;
    return;
  end if;

  update application_access set failed_count = 0, last_seen_at = now()
   where application_access.application_id = v_hit;
  return query select v_hit, 'ok'::text, 0;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- ฟังก์ชันที่ชั้น API เรียก
-- ───────────────────────────────────────────────────────────────────

-- รอบที่เปิดรับอยู่ตอนนี้ของวิทยาลัยในบริบท พร้อมสาขาที่เลือกได้
-- คืนเฉพาะวิทยาลัยเดียวเสมอ — หน้าสาธารณะไม่มีทางได้รายชื่อลูกค้า
create or replace function apply_open_rounds()
returns table (round_id uuid, round_name text, applies_from date, applies_to date,
               exam_on date, announce_on date,
               curriculum_version_id uuid, curriculum_th text, shift text)
language sql stable security definer set search_path = public as $$
  select ar.id, ar.name_th, ar.applies_from, ar.applies_to, ar.exam_on, ar.announce_on,
         q.curriculum_version_id, cur.name_th, cur.shift::text
    from admission_round ar
    join admission_quota q     on q.round_id = ar.id
    join curriculum_version cv on cv.id = q.curriculum_version_id
    join curriculum cur        on cur.id = cv.curriculum_id
   where ar.institution_id = current_institution_id()
     and ar.status = 'open'
     and current_date between ar.applies_from and ar.applies_to
   order by ar.applies_to, cur.name_th
$$;

create or replace function apply_submit(
  p_round_id          uuid,
  p                   jsonb,
  p_national_id_hash  bytea,
  p_choices           uuid[],
  p_secret_hash       bytea
) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_inst  uuid := current_institution_id();
  v_round admission_round;
  v_no    text;
  v_id    uuid;
  i       integer;
begin
  if v_inst is null then
    raise exception 'ไม่ได้ระบุสถานศึกษา';
  end if;

  select * into v_round from admission_round
   where id = p_round_id and institution_id = v_inst;
  if v_round.id is null or v_round.status <> 'open'
     or current_date not between v_round.applies_from and v_round.applies_to then
    raise exception 'รอบรับสมัครนี้ไม่ได้เปิดรับอยู่' using errcode = 'check_violation';
  end if;

  -- ออนไลน์ต้องมีเลขบัตรเสมอ เพราะเป็นตัวเดียวที่กันคนเดียวยื่นหลายใบ
  -- (ฝั่งเจ้าหน้าที่ปล่อยว่างได้ เพราะคนกรอกเห็นตัวผู้สมัครอยู่ตรงหน้า)
  if p_national_id_hash is null or octet_length(p_national_id_hash) <> 32 then
    raise exception 'ต้องกรอกเลขประจำตัวประชาชน' using errcode = 'check_violation';
  end if;
  if p_secret_hash is null or octet_length(p_secret_hash) <> 32 then
    raise exception 'รหัสลับไม่ถูกต้อง';
  end if;

  perform apply_check_form(p);
  perform apply_check_choices(p_round_id, p_choices);

  v_no := next_application_no(p_round_id);

  begin
    insert into application
      (institution_id, round_id, application_no, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email, address_th,
       prior_school_th, prior_qualification_th, prior_gpax, referral_source,
       father_first_name_th, father_last_name_th, father_occupation_th, father_phone,
       mother_first_name_th, mother_last_name_th, mother_occupation_th, mother_phone,
       status, submitted_at, submitted_via)
    values
      (v_inst, p_round_id, v_no,
       apply_text(p, 'prefix_th', 30, ''), apply_text(p, 'first_name_th', 100, ''),
       apply_text(p, 'last_name_th', 100, ''),
       p_national_id_hash, (p ->> 'birth_date')::date,
       coalesce(nullif(p ->> 'gender', ''), 'undisclosed')::gender_kind,
       regexp_replace(p ->> 'phone', '[^0-9]', '', 'g'),
       apply_text(p, 'email', 200, ''), apply_text(p, 'address_th', 500, ''),
       apply_text(p, 'prior_school_th', 200, ''), apply_text(p, 'prior_qualification_th', 100, ''),
       nullif(p ->> 'prior_gpax', '')::numeric, apply_text(p, 'referral_source', 100, ''),
       apply_text(p, 'father_first_name_th', 100, ''), apply_text(p, 'father_last_name_th', 100, ''),
       apply_text(p, 'father_occupation_th', 100, ''), apply_text(p, 'father_phone', 20, ''),
       apply_text(p, 'mother_first_name_th', 100, ''), apply_text(p, 'mother_last_name_th', 100, ''),
       apply_text(p, 'mother_occupation_th', 100, ''), apply_text(p, 'mother_phone', 20, ''),
       'submitted', now(), 'online')
    returning id into v_id;
  exception when unique_violation then
    -- ไม่บอกเลขใบเดิม — คนที่รู้แค่เลขบัตรของคนอื่นต้องไม่ได้อะไรกลับไป
    raise exception 'เลขประจำตัวประชาชนนี้ยื่นใบสมัครในรอบนี้แล้ว — ถ้าลืมเลขใบสมัครหรือรหัสลับ ติดต่องานทะเบียนพร้อมบัตรประชาชน'
      using errcode = 'check_violation';
  end;

  for i in 1 .. array_length(p_choices, 1) loop
    insert into application_choice (application_id, preference, curriculum_version_id)
    values (v_id, i, p_choices[i]);
  end loop;

  insert into application_access (application_id, institution_id, secret_hash)
  values (v_id, v_inst, p_secret_hash);

  return v_no;
end $$;

-- ดูสถานะ — data เป็น null เมื่อ outcome ไม่ใช่ ok
create or replace function apply_lookup(p_application_no text, p_secret_hash bytea)
returns table (outcome text, retry_after_secs integer, data jsonb)
language plpgsql security definer set search_path = public as $$
declare
  v_auth record;
  v_app  application;
begin
  select * into v_auth from apply_authenticate(p_application_no, p_secret_hash);
  if v_auth.outcome <> 'ok' then
    return query select v_auth.outcome, v_auth.retry_after_secs, null::jsonb;
    return;
  end if;
  select * into v_app from application where id = v_auth.application_id;
  return query select 'ok'::text, 0, apply_public_view(v_app);
end $$;

-- แก้ใบ — แทนที่ทุกช่องที่ผู้สมัครกรอกได้และอันดับที่เลือกทั้งชุด
-- เลขบัตรแก้ไม่ได้: มันคือตัวกันยื่นซ้ำ ถ้าแก้ได้ก็หลบตัวกันได้
create or replace function apply_update(
  p_application_no text,
  p_secret_hash    bytea,
  p                jsonb,
  p_choices        uuid[]
) returns table (outcome text, retry_after_secs integer, data jsonb)
language plpgsql security definer set search_path = public as $$
declare
  v_auth record;
  v_app  application;
  i      integer;
begin
  select * into v_auth from apply_authenticate(p_application_no, p_secret_hash);
  if v_auth.outcome <> 'ok' then
    return query select v_auth.outcome, v_auth.retry_after_secs, null::jsonb;
    return;
  end if;

  select * into v_app from application where id = v_auth.application_id for update;
  -- raise ตรงนี้ได้ เพราะยืนยันตัวผ่านแล้ว สิ่งที่ rollback มีแค่การล้างตัวนับ
  if not apply_editable(v_app) then
    raise exception 'ใบสมัครนี้แก้ไขไม่ได้แล้ว (เจ้าหน้าที่เริ่มตรวจแล้วหรือปิดรับสมัครแล้ว) — ติดต่องานทะเบียน'
      using errcode = 'check_violation';
  end if;

  perform apply_check_form(p);
  perform apply_check_choices(v_app.round_id, p_choices);

  update application set
    prefix_th = apply_text(p, 'prefix_th', 30, ''),
    first_name_th = apply_text(p, 'first_name_th', 100, ''),
    last_name_th = apply_text(p, 'last_name_th', 100, ''),
    birth_date = (p ->> 'birth_date')::date,
    gender = coalesce(nullif(p ->> 'gender', ''), 'undisclosed')::gender_kind,
    phone = regexp_replace(p ->> 'phone', '[^0-9]', '', 'g'),
    email = apply_text(p, 'email', 200, ''),
    address_th = apply_text(p, 'address_th', 500, ''),
    prior_school_th = apply_text(p, 'prior_school_th', 200, ''),
    prior_qualification_th = apply_text(p, 'prior_qualification_th', 100, ''),
    prior_gpax = nullif(p ->> 'prior_gpax', '')::numeric,
    referral_source = apply_text(p, 'referral_source', 100, ''),
    father_first_name_th = apply_text(p, 'father_first_name_th', 100, ''),
    father_last_name_th = apply_text(p, 'father_last_name_th', 100, ''),
    father_occupation_th = apply_text(p, 'father_occupation_th', 100, ''),
    father_phone = apply_text(p, 'father_phone', 20, ''),
    mother_first_name_th = apply_text(p, 'mother_first_name_th', 100, ''),
    mother_last_name_th = apply_text(p, 'mother_last_name_th', 100, ''),
    mother_occupation_th = apply_text(p, 'mother_occupation_th', 100, ''),
    mother_phone = apply_text(p, 'mother_phone', 20, '')
  where id = v_app.id;

  delete from application_choice where application_id = v_app.id;
  for i in 1 .. array_length(p_choices, 1) loop
    insert into application_choice (application_id, preference, curriculum_version_id)
    values (v_app.id, i, p_choices[i]);
  end loop;

  select * into v_app from application where id = v_app.id;
  return query select 'ok'::text, 0, apply_public_view(v_app);
end $$;

-- ตัวช่วยภายในไม่ต้องให้ใครเรียกตรง (ฟังก์ชัน definer ข้างบนเรียกมันด้วย
-- สิทธิ์เจ้าของอยู่แล้ว) ถ้า roles.sql ให้สิทธิ์คืนแบบเหมาทุกฟังก์ชันก็ไม่เปิด
-- อะไรเพิ่ม — apply_authenticate ตรวจรหัสและนับเดาผิดเหมือน apply_lookup ทุกอย่าง
revoke all on function apply_check_choices(uuid, uuid[]) from public;
revoke all on function apply_editable(application)        from public;
revoke all on function apply_public_view(application)     from public;
revoke all on function apply_authenticate(text, bytea)    from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select on application_access to app_runtime;
  end if;
end $$;

commit;

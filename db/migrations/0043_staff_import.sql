-- ═══════════════════════════════════════════════════════════════════
-- 0043_staff_import.sql
--
-- นำเข้าข้อมูลบุคลากรจากไฟล์ — ปิดข้อสุดท้ายของการย้ายระบบ
--
-- ─── ทำไมข้อนี้ขวางการย้ายระบบจริง ───
-- `import_kind` มี `'staff'` เตรียมไว้ตั้งแต่ 0023 แต่ไม่เคยมีตัวนำเข้าจริง
-- วิทยาลัยที่ย้ายจากระบบเดิมจึงนำเข้านักศึกษาได้เป็นพันคนในนาทีเดียว
-- แต่ต้องกรอกบุคลากรทีละคนเป็นร้อยคน ซึ่งเป็นงานที่ทำให้การย้ายระบบ
-- ค้างอยู่ตรงนั้นทั้งสัปดาห์ และเป็นจุดที่คนตัดสินใจเลิกย้าย
--
-- ─── ทำไมนำเข้าบุคลากรเสี่ยงกว่านำเข้านักศึกษา ───
-- แถวบุคลากรหนึ่งแถวสร้าง **สิทธิ์** ในระบบ ไม่ใช่แค่ข้อมูล — ถ้าไฟล์
-- กำหนดบทบาทได้อย่างอิสระ ใครที่แก้ไฟล์ CSV ระหว่างทางจะแต่งตั้งตัวเอง
-- เป็น admin ได้ทันที
--
-- ไฟล์นี้จึง **ตั้งบทบาทไม่ได้เลยสักค่า** เพราะทุกค่าใน staff_role_kind
-- (registrar · academic · finance · student_affairs · director · admin)
-- เห็นข้อมูลทั้งวิทยาลัย ต้องแต่งตั้งทีละคนผ่าน staff_role ซึ่งบันทึกว่า
-- ใครแต่งตั้งใครเมื่อไรและด้วยเหตุผลอะไร
--
-- ส่วน "เป็นครูหรือไม่" ไม่ใช่บทบาท แต่เป็น `staff.is_teacher` ซึ่งไฟล์ตั้งได้
-- เพราะให้สิทธิ์เห็นเฉพาะห้องที่ตัวเองสอน — ค่าเริ่มต้นเป็น false เสมอ
--
-- ─── โครงเดียวกับการนำเข้านักศึกษาทุกอย่าง ───
-- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด · คืนปัญหาทั้งหมดของแถว
-- ไม่ใช่ข้อแรกที่เจอ · นำเข้าซ้ำรอบเดิมไม่ได้ (หลักเดียวกับ 0023)
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตรวจข้อมูลบุคลากรหนึ่งแถว
--
-- คืนรายการปัญหาทั้งหมด ไม่หยุดที่ข้อแรก — ไฟล์ร้อยแถวที่ต้องแก้ทีละข้อ
-- แล้วนำเข้าใหม่ทุกครั้งคือการทำงานหลายวัน
-- ───────────────────────────────────────────────────────────────────
create or replace function validate_staff_row(
  p_institution_id uuid,
  p_payload        jsonb
) returns text[]
language plpgsql stable as $$
declare
  v_errors text[] := '{}';
  v_code   text := nullif(btrim(p_payload->>'staff_code'), '');
  v_first  text := nullif(btrim(p_payload->>'first_name_th'), '');
  v_last   text := nullif(btrim(p_payload->>'last_name_th'), '');
  v_nat    text := nullif(btrim(p_payload->>'national_id'), '');
  v_emp    text := nullif(btrim(p_payload->>'employment_kind'), '');
  v_dept   text := nullif(btrim(p_payload->>'department_code'), '');
  v_role   text := nullif(btrim(p_payload->>'role'), '');
begin
  if v_code is null then
    v_errors := array_append(v_errors, 'ไม่มีรหัสประจำตัวบุคลากร');
  elsif exists (select 1 from staff st
                 where st.institution_id = p_institution_id and st.staff_code = v_code) then
    v_errors := array_append(v_errors, format('รหัสประจำตัวบุคลากร %s มีอยู่ในระบบแล้ว', v_code));
  end if;

  if v_first is null then v_errors := array_append(v_errors, 'ไม่มีชื่อ'); end if;
  if v_last  is null then v_errors := array_append(v_errors, 'ไม่มีนามสกุล'); end if;

  -- ตรวจ checksum ตั้งแต่ตอนนำเข้า เหตุผลเดียวกับฝั่งนักศึกษา —
  -- เลขนี้ใช้ยันตัวตนตอนออกเอกสารและตอนเบิกจ่าย
  if v_nat is not null then
    if v_nat !~ '^\d{13}$' then
      v_errors := array_append(v_errors, 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก');
    elsif not thai_national_id_valid(v_nat) then
      v_errors := array_append(v_errors, format('เลขประจำตัวประชาชน %s ไม่ผ่านการตรวจหลักที่ 13', v_nat));
    end if;
  end if;

  if v_emp is not null
     and v_emp not in ('civil_servant','permanent','contract','part_time','industry_expert') then
    v_errors := array_append(v_errors,
      format('ประเภทการจ้าง "%s" ไม่ถูกต้อง (civil_servant · permanent · contract · part_time · industry_expert)', v_emp));
  end if;

  -- หน่วยงานต้องมีอยู่จริงก่อน ไม่สร้างให้อัตโนมัติ — แผนกที่เกิดจาก
  -- การพิมพ์ผิดในไฟล์จะกลายเป็นแผนกผีที่มีคนสังกัดอยู่จริงหนึ่งคน
  if v_dept is not null
     and not exists (select 1 from department d
                      where d.institution_id = p_institution_id and d.code = v_dept) then
    v_errors := array_append(v_errors,
      format('ไม่พบหน่วยงานรหัส %s — ต้องสร้างหน่วยงานก่อนนำเข้าบุคลากร', v_dept));
  end if;

  if v_dept is not null and nullif(btrim(p_payload->>'position_th'), '') is null then
    v_errors := array_append(v_errors, 'ระบุหน่วยงานแล้วต้องระบุตำแหน่งด้วย');
  end if;

  /*
   * ─── ข้อนี้คือความต่างสำคัญที่สุดจากการนำเข้านักศึกษา ───
   * แถวบุคลากรสร้าง **สิทธิ์** ในระบบ ไม่ใช่แค่ข้อมูล ไฟล์จึงตั้งบทบาท
   * ไม่ได้เลยสักค่า ต่อให้คนที่กดนำเข้าจะเป็น admin เองก็ตาม — เพราะไฟล์
   * ผ่านมือหลายคนและไม่มีใครตรวจทุกแถวด้วยตาก่อนกดนำเข้า
   *
   * ทุกค่าใน staff_role_kind (registrar · academic · finance ·
   * student_affairs · director · admin) เห็นข้อมูลทั้งวิทยาลัย จึงต้อง
   * แต่งตั้งทีละคนผ่าน staff_role ซึ่งบันทึกว่าใครแต่งตั้ง เมื่อไร
   * และด้วยเหตุผลอะไร
   *
   * ส่วน "เป็นครูหรือไม่" ไม่ใช่บทบาท แต่เป็น staff.is_teacher ซึ่งไฟล์
   * ตั้งได้ตามปกติ เพราะมันให้สิทธิ์เห็นเฉพาะห้องที่ตัวเองสอนเท่านั้น
   */
  if v_role is not null then
    v_errors := array_append(v_errors,
      format('ไฟล์นำเข้าตั้งบทบาท "%s" ไม่ได้ — ทุกบทบาทในระบบเห็นข้อมูลทั้งวิทยาลัย ' ||
             'ต้องแต่งตั้งทีละคนผ่านงานบุคลากร (ระบุการเป็นครูด้วยช่อง is_teacher แทน)', v_role));
  end if;

  return v_errors;
end $$;

comment on function validate_staff_row(uuid, jsonb) is
  'ตรวจข้อมูลบุคลากรหนึ่งแถว — คืนปัญหาทั้งหมด และปฏิเสธการตั้งบทบาทจากไฟล์ทุกกรณี';

-- ───────────────────────────────────────────────────────────────────
-- นำเข้าจริง — เขียนทั้งชุดหรือไม่เขียนเลย
-- ───────────────────────────────────────────────────────────────────
create or replace function apply_staff_import(p_batch_id uuid)
returns table (imported integer, failed integer)
language plpgsql as $$
declare
  v_batch  import_batch%rowtype;
  r        record;
  v_person uuid;
  v_staff  uuid;
  v_dept   uuid;
  v_bad    integer := 0;
  v_ok     integer := 0;
begin
  select * into v_batch from import_batch where id = p_batch_id;
  if not found then
    raise exception 'ไม่พบรอบนำเข้า % (หรือไม่มีสิทธิ์เข้าถึง)', p_batch_id;
  end if;
  if v_batch.status = 'applied' then
    raise exception 'รอบนำเข้านี้ถูกนำเข้าไปแล้วเมื่อ % นำเข้าซ้ำไม่ได้', v_batch.applied_at;
  end if;
  if v_batch.kind <> 'staff' then
    raise exception 'รอบนำเข้านี้เป็นชนิด % ไม่ใช่ข้อมูลบุคลากร', v_batch.kind;
  end if;

  -- ตรวจทุกแถวก่อน ไม่เขียนอะไรจนกว่าจะผ่านหมด
  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    declare v_errs text[];
    begin
      v_errs := validate_staff_row(v_batch.institution_id, r.payload);
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
    /*
     * ─── ทำไมข้อความไม่ชี้ไปที่ import_row ───
     * `raise` ทำให้ rollback กลับไปก่อนหน้าฟังก์ชันนี้ทั้งหมด รวมถึงบรรทัด
     * update import_row set errors = ... ที่เพิ่งเขียนไปข้างบน รายละเอียด
     * รายแถวจึงหายไปพร้อมกับข้อผิดพลาด — บอกให้ไปดูที่นั่นคือส่งคนไปดู
     * ตารางว่าง (กับดักเดียวกับตัวนับใน login_rate_status · 0021)
     *
     * เส้นทางที่ถูกต้องคือเรียกตรวจ (validate) ก่อน ซึ่ง commit ผลไว้จริง
     * แล้วค่อยนำเข้า — ชั้น API ทำแบบนั้นอยู่แล้ว
     */
    raise exception
      'มี % แถวที่ยังมีปัญหา ไม่ได้นำเข้าอะไรเลย — สั่งตรวจ (validate) รอบนี้อีกครั้ง '
      'เพื่อดูรายละเอียดรายแถว', v_bad;
  end if;

  for r in select * from import_row where batch_id = p_batch_id order by row_no loop
    insert into person
      (institution_id, prefix_th, first_name_th, last_name_th,
       national_id_hash, birth_date, gender, phone, email)
    values (
      v_batch.institution_id,
      nullif(btrim(r.payload->>'prefix_th'), ''),
      btrim(r.payload->>'first_name_th'),
      btrim(r.payload->>'last_name_th'),
      -- ค่าแฮชเท่านั้น เหตุผลเดียวกับ 0023 — national_id_enc รอเชื่อม KMS
      case when nullif(btrim(r.payload->>'national_id'), '') is not null
           then digest(btrim(r.payload->>'national_id'), 'sha256') end,
      (nullif(btrim(r.payload->>'birth_date'), ''))::date,
      coalesce(nullif(btrim(r.payload->>'gender'), ''), 'undisclosed')::gender_kind,
      nullif(btrim(r.payload->>'phone'), ''),
      nullif(btrim(r.payload->>'email'), '')
    )
    returning id into v_person;

    insert into staff
      (institution_id, person_id, staff_code, employment_kind, is_teacher,
       license_no, license_expires)
    values (
      v_batch.institution_id, v_person,
      btrim(r.payload->>'staff_code'),
      coalesce(nullif(btrim(r.payload->>'employment_kind'), ''), 'permanent')::employment_kind,
      -- ค่าเริ่มต้นเป็น "ไม่ใช่ครู" โดยตั้งใจ — is_teacher เปิดสิทธิ์เห็น
      -- ข้อมูลนักศึกษาในห้องที่สอน ถ้าเดาให้เป็น true คนที่ไม่ได้สอน
      -- จะได้สิทธิ์นั้นไปด้วยทั้งไฟล์
      coalesce((r.payload->>'is_teacher')::boolean, false),
      nullif(btrim(r.payload->>'license_no'), ''),
      (nullif(btrim(r.payload->>'license_expires'), ''))::date
    )
    returning id into v_staff;

    -- สังกัดหน่วยงาน (ถ้าระบุมา — validate_staff_row ตรวจแล้วว่ามีอยู่จริง)
    if nullif(btrim(r.payload->>'department_code'), '') is not null then
      select d.id into v_dept
        from department d
       where d.institution_id = v_batch.institution_id
         and d.code = btrim(r.payload->>'department_code');

      insert into staff_assignment (staff_id, department_id, position_th, is_primary)
      values (v_staff, v_dept, btrim(r.payload->>'position_th'), true);
    end if;

    -- ไม่มีการเขียน staff_role ที่นี่โดยเจตนา — ดูเหตุผลใน validate_staff_row
    update import_row set created_ref = v_staff, ok = true where id = r.id;
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

comment on function apply_staff_import(uuid) is
  'นำเข้าบุคลากรทั้งชุดหรือไม่เขียนเลย — สร้าง person + staff + สังกัดหน่วยงาน และให้บทบาทได้แค่ teacher';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant execute on function validate_staff_row(uuid, jsonb) to app_runtime;
    grant execute on function apply_staff_import(uuid)        to app_runtime;
  end if;
end $$;

commit;

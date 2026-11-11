-- ═══════════════════════════════════════════════════════════════════
-- 0098_reference_option.sql
-- ข้อมูลพื้นฐานที่วิทยาลัยแก้เองได้ — SISA "การตั้งค่า › ข้อมูลพื้นฐาน"
-- (คำนำหน้าชื่อ · ศาสนา · สัญชาติ · เชื้อชาติ · อาชีพ · ธนาคาร · สถานศึกษา ·
-- วุฒิการศึกษา)
--
-- ─── ทำไมเป็นรายการตัวเลือก ไม่ใช่คีย์นอก ───
-- ช่องเหล่านี้เป็นข้อความอิสระมาตั้งแต่ 0002/0053 และมีข้อมูลนำเข้าจากไฟล์อยู่แล้ว
-- การเปลี่ยนเป็นคีย์นอกแปลว่าข้อมูลเดิมทุกแถวต้องจับคู่ใหม่ และไฟล์นำเข้าที่สะกด
-- ต่างไปนิดเดียวจะล้มทั้งแถว ตารางนี้จึงเป็น "คำที่ควรใช้" ที่หน้าจอเสนอให้เลือก
-- ผลที่ได้คือคำสะกดเดียวกันทั้งวิทยาลัย — สถิติแยกตามศาสนา/อาชีพ
-- (/reports/students/breakdown) จึงไม่แตกเป็น "พุทธ" กับ "ศาสนาพุทธ" สองแถว
--
-- ─── ทำไมไม่มีแถวกลางที่ institution_id ว่าง ───
-- แถวที่ไม่มีวิทยาลัยต้องเปิดให้บริบทที่ไม่มีวิทยาลัยอ่านได้ ซึ่งคือบริบทของ
-- ผู้ให้บริการ — TEST 186 ห้ามสิ่งนั้นทุกตาราง จึงคัดลอกค่าตั้งต้นลงให้แต่ละ
-- วิทยาลัยแทน ทั้งวิทยาลัยที่มีอยู่แล้ว (ด้านล่าง) และที่เปิดใหม่ (trigger)
-- ═══════════════════════════════════════════════════════════════════
begin;

create table reference_option (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete cascade,
  category       text        not null check (category in
                   ('prefix', 'religion', 'nationality', 'ethnicity', 'occupation', 'bank', 'school', 'qualification')),
  code           text,
  label_th       text        not null check (btrim(label_th) <> ''),
  label_en       text,
  sort_order     smallint    not null default 0,
  active         boolean     not null default true,
  created_at     timestamptz not null default now(),
  unique (institution_id, category, label_th)
);
create index on reference_option (institution_id, category, sort_order);

comment on table reference_option is
  'คำที่ควรใช้ในช่องข้อความอิสระ (คำนำหน้า ศาสนา อาชีพ ฯลฯ) — หน้าจอเสนอให้เลือก ไม่ใช่คีย์นอก (0098)';

alter table reference_option enable row level security;
alter table reference_option force row level security;

create policy tenant_isolation on reference_option
  using (institution_id = current_institution_id());

-- อ่านได้ทุกบทบาท (ครูต้องเห็นตัวเลือกตอนกรอก) · เขียนได้เฉพาะคนตั้งค่าระบบ
-- แยก for insert/update/delete — restrictive for all กิน select ด้วย (บทเรียนจาก 0053)
create policy reference_option_insert on reference_option
  as restrictive for insert with check (current_app_roles() && array['registrar', 'director', 'admin']);
create policy reference_option_update on reference_option
  as restrictive for update
  using (current_app_roles() && array['registrar', 'director', 'admin'])
  with check (current_app_roles() && array['registrar', 'director', 'admin']);
create policy reference_option_delete on reference_option
  as restrictive for delete using (current_app_roles() && array['registrar', 'director', 'admin']);

/*
 * ค่าตั้งต้น — ชุดเล็กที่ใช้จริงในสถานศึกษาไทย ไม่ใช่ทุกค่าที่เป็นไปได้
 * (SISA มีสัญชาติ 273 ค่า ซึ่งเกือบทั้งหมดไม่มีใครเลือก และทำให้หาค่าที่ต้องการยาก)
 * วิทยาลัยเพิ่มเองได้ที่หน้าตั้งค่า
 */
create or replace function seed_reference_options(p_institution_id uuid) returns void
language sql security definer set search_path = public as $$
  insert into reference_option (institution_id, category, code, label_th, label_en, sort_order)
  select p_institution_id, v.category, v.code, v.th, v.en, v.ord
    from (values
      ('prefix', '001', 'นาย', 'Mr.', 1), ('prefix', '002', 'นางสาว', 'Miss', 2), ('prefix', '003', 'นาง', 'Mrs.', 3),
      ('prefix', '004', 'เด็กชาย', 'Master', 4), ('prefix', '005', 'เด็กหญิง', 'Miss', 5),
      ('religion', '101', 'พุทธ', 'Buddhism', 1), ('religion', '102', 'คริสต์', 'Christianity', 2),
      ('religion', '103', 'อิสลาม', 'Islam', 3), ('religion', '104', 'ฮินดู', 'Hinduism', 4),
      ('religion', '105', 'ซิกข์', 'Sikhism', 5), ('religion', '199', 'ไม่นับถือศาสนา', 'None', 9),
      ('nationality', '099', 'ไทย', 'Thai', 1), ('nationality', '048', 'เมียนมา', 'Myanmar', 2),
      ('nationality', '056', 'ลาว', 'Lao', 3), ('nationality', '057', 'กัมพูชา', 'Cambodian', 4),
      ('nationality', '044', 'จีน', 'Chinese', 5), ('nationality', '046', 'เวียดนาม', 'Vietnamese', 6),
      ('ethnicity', '099', 'ไทย', 'Thai', 1), ('ethnicity', '044', 'จีน', 'Chinese', 2),
      ('ethnicity', '048', 'เมียนมา', 'Myanmar', 3), ('ethnicity', '056', 'ลาว', 'Lao', 4),
      ('ethnicity', '057', 'กัมพูชา', 'Cambodian', 5), ('ethnicity', '070', 'มลายู', 'Malay', 6),
      ('occupation', '01', 'รับราชการ', 'Government official', 1), ('occupation', '02', 'พนักงานรัฐวิสาหกิจ', 'State enterprise employee', 2),
      ('occupation', '03', 'พนักงานบริษัท', 'Company employee', 3), ('occupation', '04', 'ค้าขาย/ธุรกิจส่วนตัว', 'Business owner', 4),
      ('occupation', '05', 'เกษตรกร', 'Farmer', 5), ('occupation', '06', 'รับจ้างทั่วไป', 'General labourer', 6),
      ('occupation', '07', 'แม่บ้าน/พ่อบ้าน', 'Homemaker', 7), ('occupation', '08', 'ไม่ได้ประกอบอาชีพ', 'Unemployed', 8),
      ('bank', '002', 'ธนาคารกรุงเทพ', 'Bangkok Bank', 1), ('bank', '004', 'ธนาคารกสิกรไทย', 'Kasikornbank', 2),
      ('bank', '006', 'ธนาคารกรุงไทย', 'Krungthai Bank', 3), ('bank', '014', 'ธนาคารไทยพาณิชย์', 'Siam Commercial Bank', 4),
      ('bank', '025', 'ธนาคารกรุงศรีอยุธยา', 'Bank of Ayudhya', 5), ('bank', '011', 'ธนาคารทหารไทยธนชาต', 'TMBThanachart Bank', 6),
      ('bank', '030', 'ธนาคารออมสิน', 'Government Savings Bank', 7), ('bank', '034', 'ธ.ก.ส.', 'BAAC', 8),
      ('qualification', '01', 'มัธยมศึกษาตอนต้น (ม.3)', 'Lower secondary', 1),
      ('qualification', '02', 'มัธยมศึกษาตอนปลาย (ม.6)', 'Upper secondary', 2),
      ('qualification', '03', 'ประกาศนียบัตรวิชาชีพ (ปวช.)', 'Certificate of Vocational Education', 3),
      ('qualification', '04', 'ประกาศนียบัตรวิชาชีพชั้นสูง (ปวส.)', 'Diploma of Vocational Education', 4),
      ('qualification', '05', 'ปริญญาตรี', 'Bachelor''s degree', 5),
      ('qualification', '06', 'ปริญญาโท', 'Master''s degree', 6), ('qualification', '07', 'ปริญญาเอก', 'Doctoral degree', 7)
    ) as v(category, code, th, en, ord)
  on conflict (institution_id, category, label_th) do nothing
$$;
revoke all on function seed_reference_options(uuid) from public;

create or replace function institution_seed_reference_options() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform seed_reference_options(new.id);
  return new;
end $$;

create trigger institution_reference_options
  after insert on institution
  for each row execute function institution_seed_reference_options();

select seed_reference_options(id) from institution;

commit;

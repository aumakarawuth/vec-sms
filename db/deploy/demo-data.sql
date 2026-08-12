-- ═══════════════════════════════════════════════════════════════════
-- demo-data.sql
-- ข้อมูลตัวอย่างที่ "ครบพอจะกดดูได้ทุกหน้าจอ" — หนึ่งห้องเรียนที่มีชีวิต
--
--   psql -v ON_ERROR_STOP=1 -f db/deploy/demo-data.sql vecsms_api_test
--
-- ═══ ห้ามรันกับฐานข้อมูลของวิทยาลัยจริงเด็ดขาด ═══
-- ไฟล์นี้สร้างคนสมมติพร้อมข้อมูลอ่อนไหว (ศาสนา · โรคประจำตัว · รายได้
-- ผู้ปกครอง) ปนกับข้อมูลจริงแล้วแยกออกยากมาก — จึงมีรายชื่อฐานที่อนุญาต
-- เหมือน demo-users.sql และล้มทันทีถ้าชื่อไม่ตรง
--
-- ═══ ทำไมต้องมีไฟล์นี้ ═══
-- `db/seed/` มีข้อมูลพอให้เทสต์ผ่าน — นักศึกษาหกคน รายวิชาห้าตัว ผลการเรียน
-- หนึ่งแถว ซึ่งพิสูจน์กฎได้ครบแต่ **กดดูหน้าจอแล้วว่างเปล่าเกือบทุกหน้า**
-- สมุดคะแนนไม่มีคะแนนสักช่อง เฝ้าระวังไม่มีใครเข้าเกณฑ์ การเงินมีใบเดียว
--
-- หน้าจอที่ว่างเปล่าดูเหมือน "ยังทำไม่เสร็จ" ทั้งที่เสร็จแล้ว — ซึ่งเป็น
-- ปัญหาคนละอย่างกับที่เทสต์จับได้ และเป็นสิ่งที่คนดูระบบครั้งแรกเห็นก่อน
--
-- ═══ ข้อมูลถูกออกแบบให้มีทั้งเคสปกติและเคสที่ระบบต้องจัดการ ═══
-- ห้องเรียนที่มีแต่คนเรียนดีจ่ายครบไม่ได้ทดสอบอะไรเลย ชุดนี้จึงมี
--   · คนเวลาเรียนไม่ถึงเกณฑ์ 80%   → เฝ้าระวัง · ประกาศผู้มีสิทธิ์สอบ · จดหมายแจ้ง
--   · คนค้างค่าเทอม                → การเงิน · ระงับการลงทะเบียน
--   · คนถูกตัดคะแนนความประพฤติ      → พฤติกรรม · หนังสือเชิญผู้ปกครอง
--   · คนที่ได้ ข.ร. และคนที่ตก      → สมุดคะแนน · รอบสอบซ่อม
--   · คนพักการเรียน                → ระเบียนนักศึกษา · สถานะ
--   · คนฝึกงานทวิภาคี              → ชั่วโมงที่รอรับรอง
--
-- ═══ รันซ้ำได้ ═══
-- ทุกขั้นเป็น upsert ด้วย UUID คงที่ — รันซ้ำแล้วได้ผลเดิม ไม่เพิ่มแถวซ้ำ
-- (ยกเว้นตารางที่ไม่มีคีย์ธรรมชาติ ซึ่งลบของชุดนี้ทิ้งก่อนแล้วใส่ใหม่)
--
-- ═══ ต้องรันด้วยผู้ใช้ที่เป็นเจ้าของฐานข้อมูล ═══
-- ไม่ใช่ `vecsms_app` เพราะบริบท `app.*` ยังไม่มีตอนรันจากบรรทัดคำสั่ง
-- ทุกนโยบาย RLS จึงปฏิเสธทุกแถว (ตั้งใจให้เป็นแบบนั้น)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

begin;

do $$
begin
  if current_database() not in ('vecsms_api_test', 'vecsms_dev', 'vecsms_demo') then
    raise exception
      'ปฏิเสธการเขียนข้อมูลตัวอย่างลงฐาน "%" — ชุดนี้เป็นคนสมมติพร้อมข้อมูลอ่อนไหว '
      'ปนกับข้อมูลจริงแล้วแยกออกยากมาก (รันได้เฉพาะ vecsms_api_test · vecsms_dev · vecsms_demo)',
      current_database();
  end if;
end $$;

/*
 * ─── สิ่งที่ไฟล์นี้อ้างว่ามีอยู่แล้ว ───
 * ทั้งหมดมาจาก `db/seed/` — ถ้าฐานนี้ไม่ได้รัน seed จะล้มตรงนี้พร้อมบอกว่า
 * ขาดอะไร ดีกว่าไปล้มกลางทางด้วย foreign key ที่อ่านไม่รู้เรื่อง
 */
create temporary table _ref on commit drop as
select
  '11111111-1111-1111-1111-111111111111'::uuid as inst,
  '22222222-2222-2222-2222-222222222222'::uuid as year_2569,
  '33333333-3333-3333-3333-333333333331'::uuid as term1,
  '33333333-3333-3333-3333-333333333332'::uuid as term2,
  '77777777-7777-7777-7777-777777777767'::uuid as cv67,
  '55555555-5555-5555-5555-555555555555'::uuid as att_policy,
  '44444444-4444-4444-4444-444444444444'::uuid as grade_scheme,
  'd2000000-0000-0000-0000-000000000001'::uuid as dept_auto,
  'd2000000-0000-0000-0000-000000000002'::uuid as dept_academic,
  'd3000000-0000-0000-0000-000000000001'::uuid as room_shop,
  'd3000000-0000-0000-0000-000000000002'::uuid as room_lecture;

do $$
declare r record; v_missing text[] := '{}';
begin
  select * into r from _ref;
  if not exists (select 1 from institution where id = r.inst) then
    v_missing := array_append(v_missing, 'วิทยาลัยตัวอย่าง'); end if;
  if not exists (select 1 from term where id = r.term1) then
    v_missing := array_append(v_missing, 'ภาคเรียน 2569/1'); end if;
  if not exists (select 1 from curriculum_version where id = r.cv67) then
    v_missing := array_append(v_missing, 'ฉบับหลักสูตร 2567'); end if;
  if not exists (select 1 from attendance_policy where id = r.att_policy) then
    v_missing := array_append(v_missing, 'นโยบายเวลาเรียน'); end if;
  if cardinality(v_missing) > 0 then
    raise exception 'ฐานนี้ยังไม่มีข้อมูลตั้งต้นที่ต้องใช้: % — รัน db/seed ก่อน', v_missing;
  end if;
end $$;


-- ═══════════════════════════════════════════════════════════════════
-- 0. หน่วยงานและห้องเรียน
--
-- ─── `db/seed/` ไม่ได้สร้างสองอย่างนี้ให้ ───
-- seed มีแต่ข้อมูลอ้างอิงที่เป็นกฎ (ภาคเรียน · รายวิชา · สัญลักษณ์เกรด ·
-- นโยบาย · ค่าธรรมเนียม) ส่วนคน หน่วยงาน และห้อง เป็นของแต่ละวิทยาลัย
-- ที่ต้องกรอกเอง — ไฟล์นี้จึงต้องสร้างเองทั้งหมด ไม่ใช่อ้างของที่ไม่มี
--
-- (ตอนแรกผมอ้าง UUID ของหน่วยงานที่เห็นในฐานที่กำลังใช้อยู่ ซึ่งมาจาก
--  fixture ของเทสต์ ไม่ใช่จาก seed — พอสร้างฐานใหม่จึงล้มด้วย foreign key)
-- ═══════════════════════════════════════════════════════════════════
insert into department (id, institution_id, code, name_th, kind)
select v.id::uuid, r.inst, v.code, v.name_th, v.kind::department_kind
  from _ref r, (values
    ('d2000000-0000-0000-0000-000000000001', 'AUTO', 'แผนกวิชาช่างยนต์', 'department'),
    ('d2000000-0000-0000-0000-000000000002', 'ACAD', 'ฝ่ายวิชาการ',      'division')
  ) as v(id, code, name_th, kind)
on conflict (id) do update set name_th = excluded.name_th;

insert into room (id, institution_id, code, name_th, capacity, kind)
select v.id::uuid, r.inst, v.code, v.name_th, v.capacity, v.kind::room_kind
  from _ref r, (values
    ('d3000000-0000-0000-0000-000000000001', 'SHOP-3', 'โรงฝึกงานช่างยนต์ 3', 30, 'workshop'),
    ('d3000000-0000-0000-0000-000000000002', 'LEC-401', 'ห้องบรรยาย 401',     40, 'classroom')
  ) as v(id, code, name_th, capacity, kind)
on conflict (id) do update set name_th = excluded.name_th, capacity = excluded.capacity;


-- ═══════════════════════════════════════════════════════════════════
-- 1. รายวิชา — ให้ภาคเรียนหนึ่งมีวิชาครบเหมือนของจริง
--
-- seed มีห้าวิชาซึ่งพอสำหรับเทสต์ แต่ใบลงทะเบียนที่มีห้าบรรทัดดูไม่เหมือน
-- ใบจริง และตารางสอนที่มีห้าคาบทั้งสัปดาห์ก็ไม่ได้ทดสอบการชนกันของคาบเลย
-- ═══════════════════════════════════════════════════════════════════
-- `weekly_periods` กับ `total_hours` เป็นคอลัมน์ที่ฐานคำนวณเอง — ใส่ค่าไม่ได้
insert into course
  (id, institution_id, edition_be, code, name_th, name_en, credits,
   theory_hours, practice_hours)
select v.id::uuid, r.inst, 2567, v.code, v.name_th, v.name_en,
       v.credits, v.theory, v.practice
  from _ref r, (values
    ('99999999-0000-0000-0000-0000000000a1', '20000-1101', 'ภาษาไทยพื้นฐาน',            'Fundamental Thai',            2, 2, 0, 2),
    ('99999999-0000-0000-0000-0000000000a2', '20000-1201', 'ภาษาอังกฤษในชีวิตจริง',      'English in Real Life',        2, 2, 0, 2),
    ('99999999-0000-0000-0000-0000000000a3', '20000-1501', 'หน้าที่พลเมืองและศีลธรรม',   'Civic Duty and Morality',     2, 2, 0, 2),
    ('99999999-0000-0000-0000-0000000000a4', '20000-1601', 'ทักษะชีวิตและสุขภาพ',        'Life Skills and Health',      1, 1, 0, 1),
    ('99999999-0000-0000-0000-0000000000a5', '20001-1001', 'อาชีวอนามัยและความปลอดภัย',  'Occupational Health and Safety', 2, 2, 0, 2),
    ('99999999-0000-0000-0000-0000000000a6', '20100-1001', 'งานเชื่อมและโลหะแผ่นเบื้องต้น', 'Basic Welding and Sheet Metal', 2, 1, 3, 4),
    ('99999999-0000-0000-0000-0000000000a7', '20101-2001', 'งานเครื่องยนต์แก๊สโซลีน',     'Gasoline Engine Work',        3, 1, 6, 7),
    ('99999999-0000-0000-0000-0000000000a8', '20000-2001', 'กิจกรรมลูกเสือวิสามัญ 1',     'Rover Scout Activity 1',      0, 0, 2, 2)
  ) as v(id, code, name_th, name_en, credits, theory, practice, weekly)
on conflict (institution_id, code, edition_be) do update
  set name_th = excluded.name_th, name_en = excluded.name_en,
      credits = excluded.credits, active = true;

/*
 * ผูกรายวิชาเข้าโครงหลักสูตร มิฉะนั้นใบ รบ. จะจัดวิชาเหล่านี้ไว้ในกลุ่ม
 * UNSORTED (0058 ตั้งใจให้เห็น ไม่ใช่ให้หายเงียบ) ซึ่งไม่ใช่สภาพที่ควร
 * เอาไปโชว์ — และคะแนนเฉลี่ยรายหมวดจะไม่มีความหมาย
 */
insert into curriculum_course
  (curriculum_version_id, curriculum_category_id, course_id, requirement, suggested_year, suggested_term)
select r.cv67, cat.id, c.id, 'required', 1, 1
  from (values
      ('20000-1101', '%แกนกลาง%'),
      ('20000-1201', '%แกนกลาง%'),
      ('20000-1501', '%แกนกลาง%'),
      ('20000-1601', '%แกนกลาง%'),
      ('20001-1001', '%วิชาชีพ%'),
      ('20100-1001', '%วิชาชีพ%'),
      ('20101-2001', '%วิชาชีพ%')
    ) as v(code, cat_like)
  cross join _ref r
  join course c on c.institution_id = r.inst and c.code = v.code and c.edition_be = 2567
  join lateral (
    -- เลือกหมวดที่ชื่อใกล้เคียงที่สุด ถ้าไม่มีเลยก็ใช้หมวดแรกของฉบับนั้น
    -- ดีกว่าไม่ผูก เพราะวิชาที่ไม่ผูกจะไปกอง UNSORTED บนใบ รบ.
    select cc.id from curriculum_category cc
     where cc.curriculum_version_id = r.cv67
     order by case when cc.name_th like v.cat_like then 0 else 1 end, cc.sort_order
     limit 1) cat on true
on conflict (curriculum_version_id, course_id) do nothing;


-- ═══════════════════════════════════════════════════════════════════
-- 2. ครูผู้สอน — หนึ่งคนต่อกลุ่มวิชา
--
-- ตารางสอนที่ครูคนเดียวสอนทุกวิชาจะไม่มีวันชนกัน ซึ่งทำให้ตัวตรวจการชน
-- (`timeslot_conflicts`) ไม่เคยถูกเรียกใช้จริงเลยตอนกดดู
-- ═══════════════════════════════════════════════════════════════════
insert into person (id, institution_id, prefix_th, first_name_th, last_name_th, gender, phone)
select v.id::uuid, r.inst, v.prefix, v.first, v.last, v.gender::gender_kind, v.phone
  from _ref r, (values
    ('e0000000-0000-0000-0000-000000000001', 'นาย',    'ประสิทธิ์', 'เครื่องยนต์ดี', 'male',   '081-100-0001'),
    ('e0000000-0000-0000-0000-000000000002', 'นางสาว', 'อรวรรณ',   'ภาษางาม',     'female', '081-100-0002'),
    ('e0000000-0000-0000-0000-000000000003', 'นาย',    'วีระชัย',   'เชื่อมชำนาญ',  'male',   '081-100-0003'),
    ('e0000000-0000-0000-0000-000000000004', 'นาง',    'สุนิสา',    'พลศึกษา',     'female', '081-100-0004'),
    ('e0000000-0000-0000-0000-000000000005', 'นาย',    'ธนากร',    'ปลอดภัยไว้',   'male',   '081-100-0005')
  ) as v(id, prefix, first, last, gender, phone)
on conflict (id) do update
  set prefix_th = excluded.prefix_th, first_name_th = excluded.first_name_th,
      last_name_th = excluded.last_name_th, phone = excluded.phone;

insert into staff (id, institution_id, person_id, staff_code, is_teacher, active, employment_kind)
select v.staff::uuid, r.inst, v.person::uuid, v.code, true, true, v.kind::employment_kind
  from _ref r, (values
    ('e1000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'T-2001', 'permanent'),
    ('e1000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000002', 'T-2002', 'permanent'),
    ('e1000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000003', 'T-2003', 'contract'),
    ('e1000000-0000-0000-0000-000000000004', 'e0000000-0000-0000-0000-000000000004', 'T-2004', 'part_time'),
    ('e1000000-0000-0000-0000-000000000005', 'e0000000-0000-0000-0000-000000000005', 'T-2005', 'contract')
  ) as v(staff, person, code, kind)
on conflict (id) do update
  set staff_code = excluded.staff_code, is_teacher = true, active = true;

/*
 * สังกัดหน่วยงานอยู่คนละตารางกับตัวบุคลากร (0035) — หน้าจอบุคลากรจัดกลุ่ม
 * ตามหน่วยงาน ครูที่ไม่มีแถวนี้จะไปกองอยู่ท้ายรายการโดยไม่มีสังกัด
 */
insert into staff_assignment (staff_id, department_id, position_th, is_primary, effective_from)
select v.staff::uuid, r.dept_auto, v.position, true, date '2026-05-01'
  from _ref r, (values
    ('e1000000-0000-0000-0000-000000000001', 'หัวหน้าแผนกวิชาช่างยนต์'),
    ('e1000000-0000-0000-0000-000000000002', 'ครูผู้สอน'),
    ('e1000000-0000-0000-0000-000000000003', 'ครูผู้สอน'),
    ('e1000000-0000-0000-0000-000000000004', 'ครูผู้สอน'),
    ('e1000000-0000-0000-0000-000000000005', 'ครูผู้สอน')
  ) as v(staff, position)
on conflict do nothing;


-- ═══════════════════════════════════════════════════════════════════
-- 3. นักศึกษา ปวช.1 ช่างยนต์ หนึ่งห้อง สิบสองคน
--
-- ─── ทำไมต้องสิบสองคน ไม่ใช่สามคน ───
-- หน้าจอที่มีสามแถวดูไม่ออกว่าการเรียงลำดับ การแบ่งหน้า และการกรอง
-- ทำงานถูกไหม และ "รายชื่อผู้ที่คะแนนต่ำกว่าเกณฑ์" ที่มีคนเดียวก็ดูไม่ออก
-- ว่าเป็นรายการหรือเป็นข้อความ
-- ═══════════════════════════════════════════════════════════════════
create temporary table _stu on commit drop as
select * from (values
  -- person id, student id, รหัส, เลขที่, prefix, ชื่อ, สกุล, เพศ, วันเกิด, สถานะ, บันทึกย่อ
  ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000001','69201010101', 1,'นาย','กิตติศักดิ์','ตั้งใจเรียน','male',  '2552-03-14','active','เรียนดี'),
  ('f0000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000002','69201010102', 2,'นาย','ชนาธิป','ขยันหมั่นเพียร','male',  '2552-05-02','active','เรียนดี'),
  ('f0000000-0000-0000-0000-000000000003','f1000000-0000-0000-0000-000000000003','69201010103', 3,'นาย','ณัฐพงศ์','ช่างสังเกต','male',    '2552-07-21','active','ปกติ'),
  ('f0000000-0000-0000-0000-000000000004','f1000000-0000-0000-0000-000000000004','69201010104', 4,'นาย','ธีรภัทร','มุ่งมั่น','male',      '2552-01-09','active','ปกติ'),
  ('f0000000-0000-0000-0000-000000000005','f1000000-0000-0000-0000-000000000005','69201010105', 5,'นาย','ปวริศ','ใจกล้า','male',        '2552-11-30','active','ขาดเรียนบ่อย'),
  ('f0000000-0000-0000-0000-000000000006','f1000000-0000-0000-0000-000000000006','69201010106', 6,'นาย','ภาณุพงศ์','รักเครื่องยนต์','male','2552-09-18','active','ปกติ'),
  ('f0000000-0000-0000-0000-000000000007','f1000000-0000-0000-0000-000000000007','69201010107', 7,'นาย','ยศกร','สู้ชีวิต','male',        '2552-04-25','active','ค้างค่าเทอม'),
  ('f0000000-0000-0000-0000-000000000008','f1000000-0000-0000-0000-000000000008','69201010108', 8,'นาย','วรเมธ','คิดต่าง','male',        '2552-08-07','active','ถูกตัดคะแนน'),
  ('f0000000-0000-0000-0000-000000000009','f1000000-0000-0000-0000-000000000009','69201010109', 9,'นาย','ศุภกร','อดทน','male',          '2552-02-16','active','ฝึกงานทวิภาคี'),
  ('f0000000-0000-0000-0000-00000000000a','f1000000-0000-0000-0000-00000000000a','69201010110',10,'นางสาว','กชกร','ละเอียดรอบคอบ','female','2552-06-11','active','เรียนดี'),
  ('f0000000-0000-0000-0000-00000000000b','f1000000-0000-0000-0000-00000000000b','69201010111',11,'นางสาว','ธัญชนก','ตั้งคำถาม','female', '2552-10-03','active','ปกติ'),
  ('f0000000-0000-0000-0000-00000000000c','f1000000-0000-0000-0000-00000000000c','69201010112',12,'นาย','อนุชิต','กลับใจ','male',        '2551-12-22','on_leave','พักการเรียน')
) as v(person_id, student_id, student_code, class_number, prefix_th, first_name_th, last_name_th, gender, birth_date, status, note);

insert into person (id, institution_id, prefix_th, first_name_th, last_name_th,
                    gender, birth_date, phone, nationality, birth_place_th)
select s.person_id::uuid, r.inst, s.prefix_th, s.first_name_th, s.last_name_th,
       s.gender::gender_kind, s.birth_date::date,
       '08' || lpad((90000000 + s.class_number)::text, 8, '0'),
       'ไทย', 'กรุงเทพมหานคร'
  from _stu s, _ref r
on conflict (id) do update
  set prefix_th = excluded.prefix_th, first_name_th = excluded.first_name_th,
      last_name_th = excluded.last_name_th, birth_date = excluded.birth_date,
      gender = excluded.gender;

insert into student (id, institution_id, person_id, student_code, admitted_year_be,
                     admitted_term_id, status, class_number, travel_mode,
                     siblings_count, birth_order, parents_marital, talent_th)
select s.student_id::uuid, r.inst, s.person_id::uuid, s.student_code, 2569,
       r.term1, s.status::student_status, s.class_number,
       (array['walk','motorcycle','school_van','paid_transit','guardian'])
         [1 + (s.class_number % 5)]::travel_mode_kind,
       1 + (s.class_number % 4), 1 + (s.class_number % 2),
       (array['together','together','together','separated','father_deceased'])
         [1 + (s.class_number % 5)]::marital_status_kind,
       (array['ซ่อมมอเตอร์ไซค์', 'ฟุตบอล', 'ดนตรีไทย', 'วาดรูป', 'คอมพิวเตอร์'])
         [1 + (s.class_number % 5)]
  from _stu s, _ref r
on conflict (id) do update
  set student_code = excluded.student_code, status = excluded.status,
      class_number = excluded.class_number, travel_mode = excluded.travel_mode;

insert into student_curriculum (student_id, curriculum_version_id)
select s.student_id::uuid, r.cv67 from _stu s, _ref r
on conflict do nothing;

/*
 * ── ชั้นปีและห้องประจำ ──
 *
 * ไฟล์นี้พูดถึง "ปวช.1 ช่างยนต์ หนึ่งห้อง" มาตั้งแต่หัวข้อ แต่ห้องนั้นเคยมี
 * อยู่ในคอมเมนต์เท่านั้น — `student_class_placement` ไม่มีแถวเดียวเลยทั้งใน
 * seed และไฟล์นี้ ผลคือหน้าลงทะเบียนที่เริ่มจากรายการห้องเปิดมาว่างเปล่า
 * ทั้งที่ข้อมูลอื่นครบหมด ซึ่งดูเหมือน "ยังทำไม่เสร็จ" ทั้งที่เสร็จแล้ว
 *
 * รหัสห้องตรงกับ `class_section.section_no` ('1/1') โดยตั้งใจ เพื่อให้เห็น
 * การจับคู่กลุ่มเรียนให้อัตโนมัติทำงานจริงตอนกดดู — สองค่านี้เป็นห้องประจำ
 * กับห้องของรายวิชาซึ่งคนละเรื่องกัน การจับคู่จึงเทียบตรงตัวอักษรเท่านั้น
 */
insert into student_class_placement
  (institution_id, student_id, academic_year_id, study_year, group_code)
select r.inst, s.student_id::uuid, r.year_2569, 1, '1/1'
  from _stu s, _ref r
on conflict (student_id, academic_year_id) do update
  set study_year = excluded.study_year, group_code = excluded.group_code;

-- ── ที่อยู่ ────────────────────────────────────────────────────────
insert into person_address
  (institution_id, person_id, kind, address_line, subdistrict_th, district_th, province_th, postal_code)
select r.inst, s.person_id::uuid, 'registered',
       (100 + s.class_number)::text || ' หมู่ ' || (1 + s.class_number % 9)::text || ' ถนนพัฒนาการ',
       'สวนหลวง', 'สวนหลวง', 'กรุงเทพมหานคร', '10250'
  from _stu s, _ref r
on conflict do nothing;

-- ── บิดามารดา ──────────────────────────────────────────────────────
insert into student_parent
  (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
   occupation_th, income_monthly, status, phone)
select r.inst, s.student_id::uuid, 'father', 'นาย',
       (array['สมบัติ','ประเสริฐ','วิชัย','บุญมี','สุทธิพงษ์'])[1 + (s.class_number % 5)],
       s.last_name_th,
       (array['รับจ้างทั่วไป','ค้าขาย','พนักงานบริษัท','เกษตรกร','ขับรถรับจ้าง'])[1 + (s.class_number % 5)],
       (9000 + s.class_number * 850)::numeric,
       case when s.note = 'พักการเรียน' then 'deceased' else 'alive' end::parent_status,
       '08' || lpad((81000000 + s.class_number)::text, 8, '0')
  from _stu s, _ref r
on conflict (student_id, role) do update
  set first_name_th = excluded.first_name_th, occupation_th = excluded.occupation_th,
      income_monthly = excluded.income_monthly, status = excluded.status;

insert into student_parent
  (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
   occupation_th, income_monthly, status, phone)
select r.inst, s.student_id::uuid, 'mother', 'นาง',
       (array['สมศรี','บุญเรือน','วันเพ็ญ','จันทร์เพ็ญ','มาลัย'])[1 + (s.class_number % 5)],
       s.last_name_th,
       (array['แม่บ้าน','ค้าขาย','รับจ้างทั่วไป','พนักงานโรงงาน','เกษตรกร'])[1 + (s.class_number % 5)],
       (7000 + s.class_number * 600)::numeric, 'alive',
       '08' || lpad((82000000 + s.class_number)::text, 8, '0')
  from _stu s, _ref r
on conflict (student_id, role) do update
  set first_name_th = excluded.first_name_th, occupation_th = excluded.occupation_th,
      income_monthly = excluded.income_monthly;

-- ── ข้อมูลอ่อนไหว (ม.26) ───────────────────────────────────────────
insert into person_sensitive
  (person_id, institution_id, ethnicity, religion, blood_type, weight_kg, height_cm,
   drug_allergy, chronic_disease)
select s.person_id::uuid, r.inst, 'ไทย',
       (array['พุทธ','พุทธ','พุทธ','อิสลาม','คริสต์'])[1 + (s.class_number % 5)],
       (array['A','B','O','AB','O'])[1 + (s.class_number % 5)],
       48 + (s.class_number * 1.7), 158 + (s.class_number % 20),
       case when s.class_number = 3 then 'เพนิซิลลิน' end,
       case when s.class_number = 5 then 'หอบหืด' when s.class_number = 11 then 'ภูมิแพ้' end
  from _stu s, _ref r
on conflict (person_id) do update
  set religion = excluded.religion, blood_type = excluded.blood_type,
      weight_kg = excluded.weight_kg, height_cm = excluded.height_cm,
      drug_allergy = excluded.drug_allergy, chronic_disease = excluded.chronic_disease;

-- ── การศึกษาเดิม ───────────────────────────────────────────────────
insert into student_prior_education
  (institution_id, student_id, level_th, completed_year_be, gpax, school_th, province_th)
select r.inst, s.student_id::uuid, 'มัธยมศึกษาตอนต้น', 2568,
       round((2.10 + (s.class_number % 9) * 0.19)::numeric, 2),
       (array['โรงเรียนวัดใหม่','โรงเรียนบ้านหนองบัว','โรงเรียนเทศบาล 2',
              'โรงเรียนสวนหลวง','โรงเรียนพระโขนง'])[1 + (s.class_number % 5)],
       'กรุงเทพมหานคร'
  from _stu s, _ref r
on conflict do nothing;

-- ── ครูที่ปรึกษา ───────────────────────────────────────────────────
insert into student_advisor
  (institution_id, student_id, staff_id, academic_year_id, is_primary, assigned_on)
select r.inst, s.student_id::uuid, 'e1000000-0000-0000-0000-000000000001'::uuid,
       r.year_2569, true, date '2026-05-11'
  from _stu s, _ref r
on conflict do nothing;

commit;

\echo ''
\echo '── ส่วนที่ 1 เสร็จ: รายวิชา · ครู · นักศึกษาพร้อมระเบียนครบทุกแท็บ ──'


-- ═══════════════════════════════════════════════════════════════════
-- 4. กลุ่มเรียนและตารางสอน — ภาคเรียน 2569/1
--
-- ─── ทำไมต้องวางคาบให้ครบทุกกลุ่ม ───
-- `generate_class_meetings()` สร้างคาบเรียนจาก `section_timeslot` ถ้าไม่วาง
-- ตารางไว้ จะไม่มีคาบให้เช็คชื่อเลยสักคาบ แล้วหน้าเช็คชื่อจะว่างทั้งหน้า
-- ทั้งที่กลุ่มเรียนมีอยู่จริง (รูปเดียวกับที่ `generate_class_meetings()`
-- มีมาตั้งแต่ 0009 แต่ไม่มีใครเรียกเลย — ดูข้อ 8 ใน CLAUDE.md)
-- ═══════════════════════════════════════════════════════════════════
begin;

create temporary table _ref on commit drop as
select '11111111-1111-1111-1111-111111111111'::uuid as inst,
       '22222222-2222-2222-2222-222222222222'::uuid as year_2569,
       '33333333-3333-3333-3333-333333333331'::uuid as term1,
       '77777777-7777-7777-7777-777777777767'::uuid as cv67,
       '55555555-5555-5555-5555-555555555555'::uuid as att_policy,
       'd3000000-0000-0000-0000-000000000001'::uuid as room_shop,
       'd3000000-0000-0000-0000-000000000002'::uuid as room_lecture;

/*
 * หนึ่งกลุ่มเรียนต่อหนึ่งรายวิชา — ห้องเดียวทั้งชั้นปี (ปวช.1/1)
 * วันและคาบไม่ซ้ำกันเลย เพราะนักศึกษากลุ่มนี้ลงทุกวิชา ถ้าซ้อนกันแม้คาบเดียว
 * exclusion constraint ของ `section_timeslot` จะปฏิเสธตั้งแต่ตอนวาง
 */
create temporary table _sec on commit drop as
select * from (values
  ('f2000000-0000-0000-0000-000000000001','20000-1101','e1000000-0000-0000-0000-000000000002', 1, 1, 2, 'lecture'),
  ('f2000000-0000-0000-0000-000000000002','20000-1201','e1000000-0000-0000-0000-000000000002', 1, 3, 4, 'lecture'),
  ('f2000000-0000-0000-0000-000000000003','20000-1501','e1000000-0000-0000-0000-000000000004', 2, 1, 2, 'lecture'),
  ('f2000000-0000-0000-0000-000000000004','20000-1601','e1000000-0000-0000-0000-000000000004', 2, 3, 3, 'lecture'),
  ('f2000000-0000-0000-0000-000000000005','20001-1001','e1000000-0000-0000-0000-000000000005', 3, 1, 2, 'lecture'),
  ('f2000000-0000-0000-0000-000000000006','20100-1001','e1000000-0000-0000-0000-000000000003', 3, 3, 6, 'shop'),
  ('f2000000-0000-0000-0000-000000000007','20101-2001','e1000000-0000-0000-0000-000000000001', 4, 1, 7, 'shop'),
  ('f2000000-0000-0000-0000-000000000008','20000-2001','e1000000-0000-0000-0000-000000000001', 5, 7, 8, 'shop')
) as v(section_id, course_code, teacher_id, dow, p_from, p_to, place);

insert into class_section
  (id, institution_id, term_id, course_id, curriculum_version_id, section_no,
   teacher_id, capacity, attendance_policy_id, planned_periods, room_id)
select s.section_id::uuid, r.inst, r.term1, c.id, r.cv67, '1/1',
       s.teacher_id::uuid, 30, r.att_policy,
       /* คาบต่อสัปดาห์ × 18 สัปดาห์ — ตัวหารของกฎ 80% */
       (s.p_to - s.p_from + 1) * 18,
       case when s.place = 'shop' then r.room_shop else r.room_lecture end
  from _sec s
  cross join _ref r
  join course c on c.institution_id = r.inst and c.code = s.course_code and c.edition_be = 2567
on conflict (id) do update
  set teacher_id = excluded.teacher_id, room_id = excluded.room_id,
      planned_periods = excluded.planned_periods, capacity = excluded.capacity;

delete from section_timeslot ts using _sec s where ts.class_section_id = s.section_id::uuid;

insert into section_timeslot (class_section_id, day_of_week, period_from, period_to, room_id)
select s.section_id::uuid, s.dow, s.p_from, s.p_to,
       case when s.place = 'shop' then r.room_shop else r.room_lecture end
  from _sec s cross join _ref r;

commit;

\echo '── ส่วนที่ 2 เสร็จ: กลุ่มเรียนแปดวิชาพร้อมตารางสอนที่ไม่ชนกัน ──'


-- ═══════════════════════════════════════════════════════════════════
-- 5. ลงทะเบียน · คาบเรียน · เวลาเรียน
--
-- ─── เวลาเรียนถูกออกแบบให้มีคนตกเกณฑ์จริง ───
-- กฎ 80% จะไม่มีความหมายเลยถ้าทุกคนมาครบ — ชุดนี้จึงมีคนที่ขาดจนตกเกณฑ์
-- หนึ่งคน คนที่เฉียดเกณฑ์หนึ่งคน และที่เหลือปกติ เพื่อให้หน้าเฝ้าระวัง
-- ประกาศผู้มีสิทธิ์สอบ และจดหมายแจ้งขาดเรียนมีข้อมูลให้ดูจริง
-- ═══════════════════════════════════════════════════════════════════
begin;

create temporary table _ref on commit drop as
select '11111111-1111-1111-1111-111111111111'::uuid as inst,
       '33333333-3333-3333-3333-333333333331'::uuid as term1;

create temporary table _sec on commit drop as
select cs.id as section_id, c.code as course_code, cs.teacher_id
  from class_section cs join course c on c.id = cs.course_id
 where cs.id::text like 'f2000000-%';

create temporary table _stu on commit drop as
select s.id as student_id, s.class_number, s.status
  from student s where s.id::text like 'f1000000-%';

/*
 * ลงทะเบียนทุกคนในทุกวิชา — ยกเว้นคนที่พักการเรียน ซึ่งไม่ควรมีรายวิชา
 * ค้างอยู่ (ถ้าลงไว้ ระบบจะนับเขาเป็นคนขาดเรียนทุกคาบตลอดภาค)
 */
insert into enrollment (student_id, class_section_id, term_id, status)
select st.student_id, sc.section_id, r.term1, 'enrolled'
  from _stu st cross join _sec sc cross join _ref r
 where st.status = 'active'
on conflict (student_id, class_section_id) do nothing;

/*
 * สร้างคาบเรียนจากตารางสอน — ฟังก์ชันเดียวกับที่หน้าจอเรียก
 *
 * ─── ข้ามกลุ่มที่มีคาบอยู่แล้ว ───
 * `generate_class_meetings()` **ปฏิเสธ**ถ้ากลุ่มนั้นมีคาบที่สอนไปแล้ว
 * (API-92) เพราะการสร้างทับจะลบเวลาเรียนที่บันทึกไว้ทิ้ง — เป็นกฎที่ถูก
 * ไฟล์นี้จึงต้องเรียกเฉพาะกลุ่มที่ยังไม่มีคาบ มิฉะนั้นรันซ้ำครั้งที่สองจะล้ม
 */
do $$
declare s record; v_n integer; v_total integer := 0; v_skipped integer := 0;
begin
  for s in select section_id from _sec loop
    if exists (select 1 from class_meeting where class_section_id = s.section_id) then
      v_skipped := v_skipped + 1;
    else
      select generate_class_meetings(s.section_id) into v_n;
      v_total := v_total + coalesce(v_n, 0);
    end if;
  end loop;
  raise notice 'สร้างคาบเรียน % คาบ (ข้าม % กลุ่มที่มีคาบอยู่แล้ว)', v_total, v_skipped;
end $$;

/*
 * ─── ปิดทุกคาบของภาคเรียนนี้ ───
 * ชุดข้อมูลนี้จำลอง **ภาคเรียนที่สอนจบแล้ว** ทั้งที่ปฏิทินจริงยังไม่ถึง
 * วันปิดภาค — เพราะถ้าปิดเฉพาะคาบที่ผ่านมาแล้ว จะส่งเกรดไม่ได้เลยสักกลุ่ม
 * (`submit_section_grades()` ปฏิเสธเมื่อยังมีคาบที่ยังไม่ได้สอน ด้วยเหตุผล
 * ที่ถูกต้องคือเวลาเรียนยังไม่ใช่ตัวเลขสุดท้าย) แล้วใบ รบ. · GPA ·
 * เอกสารทุกใบจะไม่มีข้อมูลให้ดูเลย
 *
 * ตัวหารของกฎ 80% ถูกตั้งให้เท่ากับคาบที่ปิดจริงในขั้นตัดเกรด ตัวเลข
 * เวลาเรียนบนหน้าจอกับที่ใช้ตัดเกรดจึงเป็นค่าเดียวกัน
 */
update class_meeting cm
   set status = 'held', closed_at = cm.meets_on + time '16:30',
       taught_by = cs.teacher_id
  from class_section cs
 where cs.id = cm.class_section_id
   and cm.class_section_id in (select section_id from _sec)
   and cm.status <> 'held';

delete from attendance_record ar
 using enrollment e
 where ar.enrollment_id = e.id
   and e.class_section_id in (select section_id from _sec);

/*
 * รูปแบบการขาด — ใช้เลขที่ในห้องเป็นตัวกำหนดให้ผลออกมาเหมือนเดิมทุกครั้งที่รัน
 *   เลขที่ 5  ขาดหนัก   → ตกเกณฑ์ 80%
 *   เลขที่ 8  ขาดปานกลาง → เฉียดเกณฑ์
 *   เลขที่ 12 พักการเรียน (ไม่มีรายวิชา)
 *   ที่เหลือ  ขาดบ้างประปราย ตามจังหวะที่คำนวณจากลำดับคาบ
 */
/*
 * ─── ลำดับคาบต้องนับจากคาบทั้งหมดของกลุ่ม ไม่ใช่จากคาบเดียว ───
 * รอบแรกเขียน `row_number()` ไว้ใน lateral ที่กรองเหลือคาบเดียว
 * (`cm2.id = cm.id`) ลำดับจึงเป็น 1 ทุกแถว แล้วเงื่อนไขทุกข้อที่อาศัย
 * ลำดับก็ตัดสินเหมือนกันหมด — ผลคือ **เลขที่ 5 ขาดทุกคาบ ส่วนคนอื่น
 * มาครบทุกคาบ** ซึ่งดูเหมือนข้อมูลที่ตั้งใจ จนกว่าจะนับแยกตามสถานะ
 */
with numbered as (
  select cm.id, cm.class_section_id, cm.meets_on,
         row_number() over (partition by cm.class_section_id order by cm.meets_on) as seq
    from class_meeting cm
   where cm.class_section_id in (select section_id from _sec)
     and cm.status = 'held'
)
insert into attendance_record (class_meeting_id, enrollment_id, status, source, recorded_at)
select n.id, e.id,
       case
         when st.class_number = 5  and (n.seq % 3) <> 0 then 'absent'
         when st.class_number = 8  and (n.seq % 4)  = 0 then 'absent'
         when st.class_number = 8  and (n.seq % 7)  = 0 then 'late'
         when st.class_number = 3  and (n.seq % 11) = 0 then 'leave_sick'
         -- ตัวหารต้องเล็กกว่าจำนวนคาบต่อกลุ่ม (~13) มิฉะนั้นเงื่อนไขจะไม่เคย
         -- เป็นจริงเลย แล้วทุกคนที่เหลือจะมาครบ 100% ซึ่งไม่เหมือนห้องจริง
         when (n.seq + st.class_number) % 11 = 0 then 'absent'
         when (n.seq + st.class_number) % 7  = 0 then 'late'
         else 'present'
       end::attendance_status,
       'teacher_web', n.meets_on + time '09:00'
  from numbered n
  join enrollment e on e.class_section_id = n.class_section_id
  join _stu st on st.student_id = e.student_id;

commit;

\echo '── ส่วนที่ 3 เสร็จ: ลงทะเบียน · คาบเรียน · เวลาเรียนที่มีคนตกเกณฑ์จริง ──'


-- ═══════════════════════════════════════════════════════════════════
-- 6. สมุดคะแนน — ชิ้นงานและคะแนนรายคน
--
-- ─── ทำไมต้องมีคะแนนจริง ไม่ใช่แค่หัวข้อชิ้นงาน ───
-- หน้าสมุดคะแนนที่มีหัวข้อแต่ไม่มีคะแนนดูเหมือนหน้าที่ยังทำไม่เสร็จ
-- และไม่ได้ทดสอบการรวมคะแนนตามน้ำหนักเลยสักครั้ง
-- ═══════════════════════════════════════════════════════════════════
begin;

create temporary table _sec on commit drop as
select cs.id as section_id, c.code as course_code, c.credits
  from class_section cs join course c on c.id = cs.course_id
 where cs.id::text like 'f2000000-%';

delete from gradebook_score gs
 using gradebook_item gi
 where gs.gradebook_item_id = gi.id
   and gi.class_section_id in (select section_id from _sec);
delete from gradebook_item gi where gi.class_section_id in (select section_id from _sec);

insert into gradebook_item (class_section_id, name_th, category, max_score, weight, sort_order, publish_to_student)
select s.section_id, v.name, v.cat::gradebook_category, v.max_score, v.weight, v.sort_order, true
  from _sec s, (values
    ('คะแนนเก็บระหว่างภาค', 'formative', 30, 30, 1),
    ('ใบงาน/ปฏิบัติ',        'practical', 20, 20, 2),
    ('จิตพิสัย',             'affective', 10, 10, 3),
    ('สอบกลางภาค',          'midterm',   20, 20, 4),
    ('สอบปลายภาค',          'final',     20, 20, 5)
  ) as v(name, cat, max_score, weight, sort_order);

/*
 * คะแนนคำนวณจากเลขที่ในห้อง เพื่อให้รันซ้ำแล้วได้ค่าเดิม และให้ผลกระจาย
 * ตั้งแต่เกือบเต็มจนถึงตก — คนที่เวลาเรียนไม่ถึงเกณฑ์ (เลขที่ 5) ให้คะแนน
 * ต่ำด้วย เพราะคนที่ไม่ได้มาเรียนแล้วได้คะแนนเต็มคือข้อมูลที่ขัดกันเอง
 */
/*
 * ─── คะแนนต้องต่างกันรายวิชาด้วย ไม่ใช่ต่างแค่รายคน ───
 * รอบแรกคิดจากเลขที่กับลำดับชิ้นงานอย่างเดียว ผลคือ **ทุกคนได้เกรดเดียวกัน
 * ทั้งแปดวิชา** แล้ว GPA ออกมาเป็น 4.00 พอดีหรือ 3.50 พอดีทั้งห้อง
 * ซึ่งมองผ่าน ๆ เหมือนข้อมูลปกติ จนกว่าจะเปิดใบ รบ. แล้วเห็นเกรดเรียงเท่ากันหมด
 *
 * เพิ่มลำดับของกลุ่มเรียนเข้าไปในสูตร คะแนนจึงกระจายทั้งสองแกน
 */
insert into gradebook_score (gradebook_item_id, enrollment_id, score, recorded_at)
select gi.id, e.id,
       greatest(0, least(gi.max_score,
         round(gi.max_score
               * case
                   when st.class_number = 5 then 0.30 + (sn.seq % 3) / 20.0
                   when st.class_number = 8 then 0.42 + (sn.seq % 4) / 12.0
                   else 0.52
                        + ((st.class_number * 5 + sn.seq * 11) % 45) / 100.0
                        + ((gi.sort_order * 3) % 7) / 100.0
                 end, 1)))::numeric,
       now()
  from gradebook_item gi
  join enrollment e on e.class_section_id = gi.class_section_id
  join student st on st.id = e.student_id
  join (select section_id, row_number() over (order by section_id) as seq from _sec) sn
    on sn.section_id = gi.class_section_id
 where gi.class_section_id in (select section_id from _sec)
   and st.id::text like 'f1000000-%';

commit;

\echo '── ส่วนที่ 4 เสร็จ: สมุดคะแนนห้าชิ้นงานต่อวิชา พร้อมคะแนนรายคน ──'


-- ═══════════════════════════════════════════════════════════════════
-- 7. ผลการเรียน — ตัดเกรดด้วยฟังก์ชันของระบบ ไม่ใช่เขียนเกรดลงไปเอง
--
-- `compute_section_grades()` เป็นตัวเดียวกับที่ครูกดใช้จริง การเขียน
-- `enrollment_result` เองจะได้ข้อมูลที่ไม่ผ่านเส้นทางเดียวกับของจริง
-- แล้วเราจะไม่มีวันรู้ว่าเส้นทางนั้นพัง (บทเรียนข้อ 14 ใน CLAUDE.md)
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ─── ปรับคาบที่วางแผนให้เท่ากับคาบที่สอนจริง ก่อนตัดเกรด ───
 * `planned_periods` เป็น **ตัวหารของกฎ 80%** ตอนวางไว้ที่ 18 สัปดาห์
 * แต่ภาคเรียนนี้เพิ่งผ่านไป 13 สัปดาห์ ทุกคนจึงได้เวลาเรียน 66% แล้วถูก
 * ตัดเป็น ข.ร. ทั้งห้อง ซึ่งไม่ใช่ภาพที่ต้องการโชว์ และไม่ใช่ความผิดของกฎ —
 * เป็นเพราะข้อมูลชุดนี้จำลอง "ภาคเรียนที่จบแล้ว" บนปฏิทินที่ยังไม่จบ
 *
 * ตั้งให้เท่ากับคาบที่ปิดจริงจึงเป็นการบอกว่า "ภาคนี้สอนไปเท่านี้"
 * ซึ่งทำให้เปอร์เซ็นต์บนหน้าจอกับที่ใช้ตัดเกรดเป็นตัวเลขเดียวกัน
 */
update class_section cs
   set planned_periods = greatest(1, x.periods)
  from (select cm.class_section_id,
               sum(coalesce(cm.period_count, cm.period_to - cm.period_from + 1))::int as periods
          from class_meeting cm
         where cm.status = 'held'
         group by cm.class_section_id) x
 where x.class_section_id = cs.id
   and cs.id::text like 'f2000000-%';

/*
 * `compute_section_grades()` คืน **ตาราง** ไม่ใช่จำนวน — เป็นตัวเดียวกับที่
 * ครูกดใช้จริง การเขียน enrollment_result เองจะได้ข้อมูลที่ไม่เคยผ่าน
 * เส้นทางของจริง แล้วเราจะไม่มีวันรู้ว่าเส้นทางนั้นพัง (บทเรียนข้อ 14)
 */
/*
 * ─── เดินสายอนุมัติจริงทั้งสาย ไม่ใช่เขียน enrollment_result ลงไปเอง ───
 * `compute_section_grades()` **คำนวณอย่างเดียว ไม่ได้บันทึกอะไร** — ตัวที่
 * เขียนผลคือ `submit_section_grades()` แล้วต้องเดินขั้นอนุมัติต่อจนถึง
 * `locked` ซึ่งเป็นเส้นทางเดียวกับที่ครูและงานทะเบียนกดจริง
 *
 * เขียน enrollment_result ตรง ๆ ได้เร็วกว่า แต่จะได้ข้อมูลที่ไม่เคยผ่าน
 * เส้นทางของจริง — ซึ่งเป็นรูปเดียวกับข้อ 14 ใน CLAUDE.md ที่ครูส่งเกรด
 * ไม่ได้เลยสักครั้งอยู่นาน เพราะทุกเทสต์ insert ข้ามขั้นแรกไป
 *
 * ต้องมีบริบทผู้ใช้เพราะฟังก์ชันเหล่านี้บันทึกว่าใครเป็นคนกด
 */
do $$
declare
  s record; v_sub uuid; v_n integer; v_total integer := 0;
  v_actor uuid;
begin
  select p.id into v_actor
    from person p join staff st on st.person_id = p.id
    join staff_role sr on sr.staff_id = st.id
   where sr.role = 'registrar' limit 1;

  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.person_id', v_actor::text, true);
  perform set_config('app.role', 'registrar', true);

  for s in select id from class_section where id::text like 'f2000000-%' loop
    /*
     * ─── ข้ามกลุ่มที่ส่งเกรดไปแล้ว ───
     * `enrollment_result` ลบไม่ได้ (หลักข้อ 4) และรอบที่ `locked` แล้ว
     * ส่งซ้ำไม่ได้ — ทั้งสองอย่างถูกต้อง ไฟล์นี้จึงต้องข้าม ไม่ใช่พยายามทับ
     * ถ้าอยากได้ผลการเรียนชุดใหม่ ต้องสร้างฐานใหม่แล้วรันไฟล์นี้ตั้งแต่ต้น
     */
    continue when exists (
      select 1 from grade_submission gsub where gsub.class_section_id = s.id);
    begin
      -- คืนเป็นตาราง (submission_id, results_written) ไม่ใช่ uuid เดี่ยว
      select submission_id into v_sub from submit_section_grades(s.id);
      perform advance_grade_submission(v_sub, 'head_approved', 'ข้อมูลตัวอย่าง');
      perform advance_grade_submission(v_sub, 'academic_approved', 'ข้อมูลตัวอย่าง');
      perform advance_grade_submission(v_sub, 'director_approved', 'ข้อมูลตัวอย่าง');
      perform advance_grade_submission(v_sub, 'locked', 'ข้อมูลตัวอย่าง');
      select count(*) into v_n
        from enrollment_result er join enrollment e on e.id = er.enrollment_id
       where e.class_section_id = s.id and er.superseded_by is null;
      v_total := v_total + coalesce(v_n, 0);
    exception when others then
      raise notice 'ส่งเกรดกลุ่ม % ไม่ได้: %', s.id, left(sqlerrm, 100);
    end;
  end loop;
  raise notice 'บันทึกผลการเรียน % รายวิชา-คน', v_total;
end $$;

select compute_term_summary('33333333-3333-3333-3333-333333333331'::uuid) as term1_rows \gset

commit;

\echo '── ส่วนที่ 5 เสร็จ: ผลการเรียนและยอดสรุปรายภาค ──'


-- ═══════════════════════════════════════════════════════════════════
-- 8. การเงิน — ใบแจ้งหนี้ · งวดผ่อนชำระ · การรับชำระ
--
-- ─── ทำไมต้องมีคนค้างชำระ ───
-- หน้าการเงินที่ทุกคนจ่ายครบไม่ได้แสดงอะไรเลย และ `registration_hold`
-- ที่ไม่เคยมีใครติดก็ไม่ได้พิสูจน์ว่าการระงับลงทะเบียนทำงาน
-- ═══════════════════════════════════════════════════════════════════
begin;

create temporary table _stu on commit drop as
select s.id as student_id, s.class_number
  from student s where s.id::text like 'f1000000-%' and s.status = 'active';

/*
 * `issue_invoice()` เป็นตัวเดียวกับที่หน้าจอเรียก — ประกอบบรรทัดค่าใช้จ่าย
 * จาก `fee_schedule` ของภาคนั้นให้เอง การเขียน invoice_line เองจะได้ใบที่
 * ยอดไม่ตรงกับตารางค่าธรรมเนียมที่ประกาศไว้
 */
do $$
declare st record; v_actor uuid; v_n integer := 0;
begin
  select p.id into v_actor
    from person p join staff st2 on st2.person_id = p.id
    join staff_role sr on sr.staff_id = st2.id
   where sr.role = 'finance' limit 1;
  if v_actor is null then
    select p.id into v_actor from person p join staff st2 on st2.person_id = p.id
      join staff_role sr on sr.staff_id = st2.id where sr.role = 'registrar' limit 1;
  end if;

  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.person_id', v_actor::text, true);
  perform set_config('app.role', 'finance', true);

  for st in select * from _stu loop
    continue when exists (
      select 1 from invoice i
       where i.student_id = st.student_id
         and i.term_id = '33333333-3333-3333-3333-333333333331'::uuid
         and i.status <> 'void');
    begin
      -- ผ่อนสองงวดสำหรับคนที่เลขที่เป็นคู่ เพื่อให้มีทั้งสองแบบบนหน้าจอ
      perform issue_invoice(st.student_id, '33333333-3333-3333-3333-333333333331'::uuid,
                            case when st.class_number % 2 = 0 then 2 else 1 end);
      v_n := v_n + 1;
    exception when others then
      raise notice 'ออกใบแจ้งหนี้ให้เลขที่ % ไม่ได้: %', st.class_number, left(sqlerrm, 90);
    end;
  end loop;
  raise notice 'ออกใบแจ้งหนี้ % ใบ', v_n;
end $$;

/*
 * รับชำระ — ทุกคนจ่ายครบ ยกเว้นเลขที่ 7 (ยศกร) ที่ตั้งใจให้ค้างไว้
 * และเลขที่ 11 ที่จ่ายมาบางส่วน เพื่อให้เห็นสถานะ partially_paid ด้วย
 */
insert into payment (institution_id, student_id, received_on, amount, method, receipt_no, status, note)
select i.institution_id, i.student_id, current_date - 20,
       case when st.class_number = 11 then round(i.total * 0.4, 2) else i.total end,
       'cash', 'RC-' || lpad(st.class_number::text, 4, '0'), 'reconciled',
       'ข้อมูลตัวอย่าง'
  from invoice i
  join _stu st on st.student_id = i.student_id
 where i.term_id = '33333333-3333-3333-3333-333333333331'::uuid
   and i.status <> 'void'
   and st.class_number <> 7
   and not exists (select 1 from payment pm
                    where pm.student_id = i.student_id
                      and pm.receipt_no = 'RC-' || lpad(st.class_number::text, 4, '0'));

commit;

\echo '── ส่วนที่ 6 เสร็จ: ใบแจ้งหนี้ · การรับชำระ · คนค้างชำระหนึ่งคน ──'


-- ═══════════════════════════════════════════════════════════════════
-- 9. ความประพฤติ · การคัดกรอง · เยี่ยมบ้าน
-- ═══════════════════════════════════════════════════════════════════
begin;

create temporary table _stu on commit drop as
select s.id as student_id, s.class_number
  from student s where s.id::text like 'f1000000-%';

delete from behavior_record br where br.detail = 'ข้อมูลตัวอย่าง';

insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_at)
select st.student_id, r.id, current_date - (10 + st.class_number), r.points,
       'ข้อมูลตัวอย่าง', now()
  from _stu st
  join lateral (
    select br2.id, br2.points from behavior_rule br2
     where br2.direction = 'deduct' and br2.active
     order by br2.id offset (st.class_number % 3) limit 1) r on true
 where st.class_number in (5, 8, 11);

insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_at)
select st.student_id, r.id, current_date - 5, r.points, 'ข้อมูลตัวอย่าง', now()
  from _stu st
  join lateral (
    select br2.id, br2.points from behavior_rule br2
     where br2.direction = 'award' and br2.active order by br2.id limit 1) r on true
 where st.class_number in (1, 2, 10);

insert into screening_result (student_id, instrument, assessed_on, band, detail)
select st.student_id, 'SDQ', current_date - 45,
       case when st.class_number = 5 then 'at_risk'
            when st.class_number = 8 then 'has_problem'
            else 'normal' end::screening_band,
       '{"note":"ข้อมูลตัวอย่าง"}'::jsonb
  from _stu st
 where not exists (select 1 from screening_result sr
                    where sr.student_id = st.student_id and sr.instrument = 'SDQ');

insert into home_visit (student_id, visited_on, findings, follow_up)
select st.student_id, current_date - 30,
       'ข้อมูลตัวอย่าง — เยี่ยมบ้านตามระบบดูแลช่วยเหลือผู้เรียน',
       'ติดตามอีกครั้งในภาคเรียนหน้า'
  from _stu st
 where st.class_number in (5, 8)
   and not exists (select 1 from home_visit hv where hv.student_id = st.student_id);

commit;

\echo '── ส่วนที่ 7 เสร็จ: ความประพฤติ · ผลคัดกรอง · บันทึกเยี่ยมบ้าน ──'

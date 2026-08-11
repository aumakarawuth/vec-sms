-- ═══════════════════════════════════════════════════════════════════
-- reference-data.sql
-- ข้อมูลอ้างอิงตั้งต้นของวิทยาลัยหนึ่งแห่ง — รันครั้งเดียวต่อวิทยาลัยที่เปิดใหม่
--
--   psql "$ADMIN_DATABASE_URL" -v ON_ERROR_STOP=1 -f db/deploy/reference-data.sql
--
-- ─── ทำไมต้องมีไฟล์นี้ ───
-- คู่มือ deploy สั่งให้นำเข้า `vec-sms-schema.sql` และย้ำว่าห้ามใช้
-- `vec-sms-full.sql` เพราะตัวหลังมีวิทยาลัยสมมติปนอยู่ — ซึ่งถูก
-- แต่ข้อมูลอ้างอิงทั้งหมดอยู่ในไฟล์ที่ห้ามใช้นั้น ทั้งสองทางจึงไม่มีทางถูก
-- เอา seed มาก็ได้วิทยาลัยปลอมติดมาด้วย ไม่เอาก็ได้ระบบที่
--
--   ตัดเกรดไม่ได้        (ไม่มี grade_scheme · grade_symbol · grade_cutoff)
--   สร้างกลุ่มเรียนไม่ได้ (class_section.attendance_policy_id เป็น not null)
--   ลงทะเบียนไม่ได้      (ไม่มี registration_policy)
--   งานประจำวันล้มสองตัว (ไม่มี risk_factor · late_fee_policy)
--
-- ทั้งหมดนี้มองไม่เห็นจากภายนอกเลย — แอปบูตปกติ health เขียว หน้าจอเปิดได้ครบ
-- จนถึงวันที่ครูคนแรกกดส่งเกรด
--
-- `open_institution()` สร้างให้แค่สามอย่างคือ auth_policy · behavior_policy ·
-- timetable_policy ที่เหลือในไฟล์นี้ไม่มีใครสร้างให้
--
-- ─── ที่ไฟล์นี้ตั้งใจไม่สร้าง ───
--   ค่าธรรมเนียม (fee_item · fee_schedule)  ราคาและเลขที่ประกาศเป็นเรื่องของ
--                                            แต่ละวิทยาลัย ระบบไม่ควรเดาแทน
--                                            และโรงเรียนเอกชนถูกตรวจย้อนหลังได้
--   หลักสูตรและรายวิชา                       เป็นเนื้องานวิชาการ ไม่ใช่ข้อมูลอ้างอิง
--   graduation_rule                          ผูกกับ curriculum_version จึงต้องมี
--                                            หลักสูตรก่อน
--   academic_holiday                         เปลี่ยนทุกปี ตั้งพร้อมปฏิทินการศึกษา
--
-- ─── ตัวเลขทุกตัวเป็นค่าตั้งต้น ต้องยืนยันก่อนใช้กับข้อมูลจริง ───
--   ช่วงคะแนนตัดเกรด            ฝ่ายวัดผล
--   น้ำหนักลาป่วย/ลากิจ         ฝ่ายวัดผล (ค่าตั้งต้น ลาป่วยเต็ม ลากิจครึ่ง)
--   เพดานหน่วยกิต               ฝ่ายวิชาการ
--   ค่าปรับและวันผ่อนผัน        ฝ่ายการเงิน
--   น้ำหนักปัจจัยเสี่ยง          ควรปรับจากข้อมูลย้อนหลังของวิทยาลัยเองหลังใช้ไปหนึ่งปี
--
-- ─── ต้องรันด้วยผู้ใช้ที่เป็นเจ้าของฐานข้อมูล ───
-- ไม่ใช่ vecsms_app เพราะบริบท app.* ยังไม่มีตอนรันจากบรรทัดคำสั่ง
-- ทุกนโยบาย RLS จึงปฏิเสธทุกแถว (ตั้งใจให้เป็นแบบนั้น)
--
-- รันซ้ำได้ปลอดภัย — ทุกบล็อกข้ามแถวที่มีอยู่แล้ว จึงไม่ทับค่าที่วิทยาลัยแก้เอง
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- แก้สองค่านี้ให้ตรงกับวิทยาลัยที่เพิ่งเปิด แล้วรันทั้งไฟล์
-- ───────────────────────────────────────────────────────────────────
create temporary table _params on commit drop as
select '1234567890'::text as institution_code,  -- รหัสสถานศึกษา 10 หลัก
       2569::smallint     as year_be;           -- ปีการศึกษาที่เริ่มใช้ค่าเหล่านี้

do $$
declare n integer;
begin
  select count(*) into n
    from _params p join institution i on i.code = p.institution_code;
  if n <> 1 then
    raise exception 'หาสถานศึกษารหัสนี้ไม่เจอ (พบ % รายการ) — ตรวจ institution_code ในไฟล์', n;
  end if;
end $$;

-- ───────────────────────────────────────────────────────────────────
-- 1. ระเบียบการวัดและประเมินผล ปวช.
-- ไม่มีชุดนี้ = ตัดเกรดไม่ได้เลยแม้แต่คนเดียว
-- ───────────────────────────────────────────────────────────────────
insert into grade_scheme (institution_id, code, name_th, level, effective_from_year_be)
select i.id, 'PVC-2567', 'ระเบียบการวัดและประเมินผล ปวช.', 'PVC', 2567
  from _params p join institution i on i.code = p.institution_code
on conflict (institution_id, code) do nothing;

insert into grade_symbol
  (grade_scheme_id, symbol, name_th, grade_point, counts_in_gpa, earns_credit,
   is_provisional, resolve_within_days, appears_on_transcript, sort_order)
select gs.id, v.symbol, v.name_th, v.grade_point::numeric,
       v.counts_in_gpa, v.earns_credit, v.is_provisional,
       v.resolve_within_days::smallint, v.appears_on_transcript, v.sort_order::smallint
  from _params p
  join institution i  on i.code = p.institution_code
  join grade_scheme gs on gs.institution_id = i.id and gs.code = 'PVC-2567'
  cross join (values
    ('4.0',  'ผลการเรียนดีเยี่ยม',      4.0,  true,  true,  false, null, true,  1),
    ('3.5',  'ผลการเรียนดีมาก',         3.5,  true,  true,  false, null, true,  2),
    ('3.0',  'ผลการเรียนดี',            3.0,  true,  true,  false, null, true,  3),
    ('2.5',  'ผลการเรียนดีพอใช้',       2.5,  true,  true,  false, null, true,  4),
    ('2.0',  'ผลการเรียนพอใช้',         2.0,  true,  true,  false, null, true,  5),
    ('1.5',  'ผลการเรียนอ่อน',          1.5,  true,  true,  false, null, true,  6),
    ('1.0',  'ผลการเรียนอ่อนมาก',       1.0,  true,  true,  false, null, true,  7),
    ('0',    'ผลการเรียนต่ำกว่าเกณฑ์',  0.0,  true,  false, false, null, true,  8),
    -- สัญลักษณ์พิเศษ — ข.ส. และ ม.ส. มีกำหนดแก้ 30 วัน ถ้าไม่แก้จะกลายเป็น 0
    ('ข.ร.', 'ขาดเรียน ไม่มีสิทธิ์เข้ารับการประเมินสรุปผล', 0.0, true, false, false, null, true, 9),
    ('ข.ส.', 'ขาดการประเมินสรุปผล',     null, false, false, true,  30,   true, 10),
    ('ม.ส.', 'ไม่สมบูรณ์',              null, false, false, true,  30,   true, 11),
    ('ถ.น.', 'ถอนรายวิชา',              null, false, false, false, null, true, 12),
    ('ผ.',   'ผ่าน',                    null, false, true,  false, null, true, 13),
    ('ม.ผ.', 'ไม่ผ่าน',                 null, false, false, false, null, true, 14)
  ) as v(symbol, name_th, grade_point, counts_in_gpa, earns_credit,
         is_provisional, resolve_within_days, appears_on_transcript, sort_order)
on conflict (grade_scheme_id, symbol) do nothing;

-- ช่วงคะแนนตัดเกรดอัตโนมัติ — **ต้องยืนยันกับฝ่ายวัดผลก่อนใช้จริง**
insert into grade_cutoff (grade_scheme_id, grade_symbol_id, min_score)
select gs.id, sym.id, v.min_score::numeric
  from _params p
  join institution i   on i.code = p.institution_code
  join grade_scheme gs on gs.institution_id = i.id and gs.code = 'PVC-2567'
  cross join (values ('4.0', 80.0), ('3.5', 75.0), ('3.0', 70.0), ('2.5', 65.0),
                     ('2.0', 60.0), ('1.5', 55.0), ('1.0', 50.0), ('0', 0.0))
             as v(symbol, min_score)
  join grade_symbol sym on sym.grade_scheme_id = gs.id and sym.symbol = v.symbol
on conflict (grade_scheme_id, grade_symbol_id) do nothing;

-- ───────────────────────────────────────────────────────────────────
-- 2. นโยบายเวลาเรียน
-- ไม่มีชุดนี้ = สร้างกลุ่มเรียนไม่ได้ เพราะ class_section.attendance_policy_id
-- เป็น not null และไม่มีค่าเริ่มต้น
--
-- น้ำหนักสามค่าที่แต่ละวิทยาลัยตีความไม่เหมือนกัน — ลาป่วยนับเต็ม
-- ลากิจนับครึ่ง มาสายนับเต็ม **ยืนยันกับฝ่ายวัดผลก่อน** เพราะเมื่อมีข้อมูลจริง
-- แล้วแก้ย้อนหลังไม่ได้
-- ───────────────────────────────────────────────────────────────────
insert into attendance_policy
  (institution_id, name_th, effective_from_year_be, min_pct, discretion_floor_pct, warn_pct)
select i.id, 'นโยบายเวลาเรียน ปีการศึกษา ' || p.year_be, p.year_be, 80.00, 60.00, 85.00
  from _params p join institution i on i.code = p.institution_code
on conflict (institution_id, effective_from_year_be) do nothing;

insert into attendance_status_weight (attendance_policy_id, status, weight)
select ap.id, v.status::attendance_status, v.weight::numeric
  from _params p
  join institution i on i.code = p.institution_code
  join attendance_policy ap
    on ap.institution_id = i.id and ap.effective_from_year_be = p.year_be
  cross join (values ('present', 1.00), ('late', 1.00), ('activity', 1.00),
                     ('leave_sick', 1.00), ('leave_personal', 0.50), ('absent', 0.00))
             as v(status, weight)
on conflict (attendance_policy_id, status) do nothing;

-- ───────────────────────────────────────────────────────────────────
-- 3. นโยบายการลงทะเบียน
-- ไม่มีชุดนี้ = ลงทะเบียนไม่ผ่านเพราะไม่มีเพดานหน่วยกิตให้เทียบ
-- ───────────────────────────────────────────────────────────────────
insert into registration_policy
  (institution_id, level, term_kind, effective_from_year_be,
   min_credits, max_credits, max_credits_with_approval, allow_time_conflict, block_when_on_hold)
select i.id, v.level::qualification_level, v.term_kind::term_kind, 2567,
       v.min_credits::numeric, v.max_credits::numeric, v.max_approval::numeric, false, true
  from _params p
  join institution i on i.code = p.institution_code
  cross join (values ('PVC', 'regular', 12.0, 22.0, 25.0),
                     ('PVC', 'summer',   0.0,  9.0, 12.0),
                     ('PVS', 'regular',  9.0, 22.0, 25.0),
                     ('PVS', 'summer',   0.0,  9.0, 12.0))
             as v(level, term_kind, min_credits, max_credits, max_approval)
on conflict (institution_id, level, term_kind, effective_from_year_be) do nothing;

-- ───────────────────────────────────────────────────────────────────
-- 4. ปัจจัยเสี่ยงและเกณฑ์สี
-- ไม่มีชุดนี้ = งานประจำวัน `risk` ล้มทุกคืนด้วยข้อความ
-- "ยังไม่ได้ตั้งเกณฑ์ระดับความเสี่ยงของสถานศึกษานี้"
--
-- น้ำหนักรวมเกิน 100 โดยตั้งใจ เพราะคนที่ติดหลายข้อพร้อมกันต้องขึ้นแดงทันที
-- คะแนนถูกตัดที่ 100
-- ───────────────────────────────────────────────────────────────────
insert into risk_policy (institution_id, yellow_at, orange_at, red_at, respond_within_days)
select i.id, 25, 50, 75, 3
  from _params p join institution i on i.code = p.institution_code
on conflict (institution_id) do nothing;

insert into risk_factor (institution_id, code, name_th, weight, params, sort_order)
select i.id, v.code, v.name_th, v.weight::smallint, v.params::jsonb, v.sort_order::smallint
  from _params p
  join institution i on i.code = p.institution_code
  cross join (values
    ('ABSENT_STREAK',   'ขาดเรียนติดต่อกัน',                  30, '{"days": 3}',   1),
    ('ATTENDANCE_LOW',  'เวลาเรียนใกล้ตกเกณฑ์ 80%',           25, '{}',            2),
    ('OVERDUE_PAYMENT', 'ค้างชำระเกินกำหนด',                  25, '{"days": 30}',  3),
    ('NOT_REGISTERED',  'ยังไม่ลงทะเบียนในภาคเรียนปัจจุบัน',  30, '{}',            4),
    ('LOW_GPA',         'ผลการเรียนเฉลี่ยสะสมต่ำกว่าเกณฑ์จบ', 15, '{"gpax": 2.00}', 5),
    ('PENDING_GRADE',   'มีผลการเรียนค้างแก้',                10, '{"count": 1}',  6),
    ('LATE_FREQUENT',   'มาสายบ่อย',                          10, '{"count": 5}',  7),
    ('BEHAVIOR_LOW',    'คะแนนความประพฤติเหลือน้อย',          10, '{"below": 80}', 8),
    ('SCREENING_RISK',  'ผลคัดกรองอยู่กลุ่มเสี่ยง',           10, '{}',            9)
  ) as v(code, name_th, weight, params, sort_order)
on conflict (institution_id, code) do nothing;

-- ───────────────────────────────────────────────────────────────────
-- 5. กฎความประพฤติ
-- `points` เป็นบวกเสมอ ทิศทางหัก/เพิ่มอยู่ที่ `direction` — การรวมยอด
-- โดยดูเครื่องหมายของตัวเลขจะได้ผลผิดแบบดูไม่ออก (หนีเรียนกลายเป็นได้คะแนนเพิ่ม)
-- ───────────────────────────────────────────────────────────────────
insert into behavior_policy (institution_id, starting_points, warn_below, critical_below)
select i.id, 100, 80, 60
  from _params p join institution i on i.code = p.institution_code
on conflict (institution_id) do nothing;

insert into behavior_rule (institution_id, code, name_th, direction, points, triggers_action)
select i.id, v.code, v.name_th, v.direction::behavior_direction, v.points::smallint, v.action
  from _params p
  join institution i on i.code = p.institution_code
  cross join (values
    ('LATE',      'มาสาย',                            'deduct',  2, null),
    ('UNIFORM',   'แต่งกายผิดระเบียบ',                'deduct',  5, null),
    ('SKIP',      'หนีเรียน',                         'deduct', 10, 'เชิญผู้ปกครอง'),
    ('SMOKE',     'สูบบุหรี่ในสถานศึกษา',             'deduct', 20, 'ทำทัณฑ์บน'),
    ('FIGHT',     'ทะเลาะวิวาท',                      'deduct', 30, 'เชิญผู้ปกครองและทำทัณฑ์บน'),
    ('SAFETY',    'ไม่สวมอุปกรณ์ป้องกันในโรงฝึกงาน',  'deduct', 15, 'ห้ามเข้าโรงฝึกจนกว่าจะอบรมซ้ำ'),
    ('VOLUNTEER', 'จิตอาสาช่วยงานวิทยาลัย',           'award',   5, null),
    ('CONTEST',   'ได้รางวัลแข่งขันทักษะวิชาชีพ',     'award',  20, null),
    ('HELP',      'ช่วยเหลือเพื่อนหรือครู',           'award',   5, null)
  ) as v(code, name_th, direction, points, action)
on conflict (institution_id, code) do nothing;

-- ───────────────────────────────────────────────────────────────────
-- 6. ผังบัญชีขั้นต่ำ แหล่งทุน และนโยบายค่าปรับ
-- ไม่มีนโยบายค่าปรับ = งานประจำวัน `finance-holds` ล้มทุกคืน
--
-- ผังบัญชีนี้เป็นขั้นต่ำที่ระบบต้องใช้อ้างอิงเท่านั้น ไม่ใช่ผังบัญชีจริง
-- ของวิทยาลัย — ฝ่ายการเงินเพิ่มของตัวเองต่อได้
-- ───────────────────────────────────────────────────────────────────
insert into ledger_account (institution_id, code, name_th, type)
select i.id, v.code, v.name_th, v.type::ledger_account_type
  from _params p
  join institution i on i.code = p.institution_code
  cross join (values
    ('1101', 'เงินสดและเงินฝากธนาคาร',        'asset'),
    ('1102', 'ลูกหนี้ค่าเล่าเรียน',            'asset'),
    ('2101', 'รายได้รับล่วงหน้า',              'liability'),
    ('4101', 'รายได้ค่าเล่าเรียน',             'revenue'),
    ('4102', 'รายได้ค่าวัสดุฝึกและกิจกรรม',    'revenue'),
    ('4103', 'รายได้เงินอุดหนุนรายบุคคล',      'revenue')
  ) as v(code, name_th, type)
on conflict (institution_id, code) do nothing;

insert into funding_source (institution_id, kind, name_th)
select i.id, v.kind::funding_kind, v.name_th
  from _params p
  join institution i on i.code = p.institution_code
  cross join (values
    ('sibling',      'ส่วนลดพี่น้องเรียนพร้อมกัน'),
    ('gov_subsidy',  'เงินอุดหนุนรายบุคคล เรียนฟรี 15 ปี'),
    ('student_loan', 'กองทุนเงินให้กู้ยืมเพื่อการศึกษา')
  ) as v(kind, name_th)
 where not exists (
   select 1 from funding_source f
    where f.institution_id = i.id and f.kind = v.kind::funding_kind);

-- ค่าปรับและวันผ่อนผัน — **ยืนยันกับฝ่ายการเงินก่อนใช้จริง**
insert into late_fee_policy
  (institution_id, effective_from_year_be, grace_days, flat_amount, daily_amount,
   max_amount, hold_after_days)
select i.id, p.year_be, 7, 100.00, 20.00, 1000.00, 30
  from _params p join institution i on i.code = p.institution_code
on conflict (institution_id, effective_from_year_be) do nothing;

-- ข้อความบนใบ รบ. — เกณฑ์การสำเร็จหลักสูตรและคำอธิบายเครื่องหมายดอกจัน
--
-- ─── ทำไมถึงเป็นข้อมูลอ้างอิง ทั้งที่ตารางบอกว่า "แต่ละวิทยาลัยเขียนเอง" ───
-- ข้อความห้าบรรทัดนี้มาจากระเบียบของ สอศ. ไม่ใช่นโยบายของวิทยาลัย —
-- ทุกใบที่วัดจากไฟล์จริงเขียนเหมือนกันหมด ตารางแยกเก็บรายวิทยาลัยเพราะ
-- **แก้ได้** เมื่อระเบียบเปลี่ยนหรือหลักสูตรต่างระดับใช้ถ้อยคำต่างกัน
-- ไม่ใช่เพราะต้องพิมพ์เอง
--
-- ถ้าไม่ใส่ให้ ใบ รบ. ของวิทยาลัยเปิดใหม่จะพิมพ์หัวข้อ "เกณฑ์การสำเร็จ
-- หลักสูตร" พร้อมพื้นที่ว่างใต้หัวข้อ ซึ่งดูเหมือนกระดาษเสียมากกว่าดูเหมือน
-- ระบบที่ยังตั้งค่าไม่ครบ — และไม่มีอะไรฟ้องจนกว่าจะมีคนถือใบไปยื่นที่อื่น
insert into institution_document_text (institution_id, key, text_th, text_en)
select i.id, v.key, v.th, v.en
  from _params p join institution i on i.code = p.institution_code,
  (values
    ('transcript_criteria_1', 'ประเมินผ่านรายวิชาครบตามโครงสร้างหลักสูตร',
      'Pass the required courses according to program structure'),
    ('transcript_criteria_2', 'ประเมินผ่านกิจกรรมตามที่หลักสูตรกำหนด',
      'Pass the activities required in the curriculum'),
    ('transcript_criteria_3', 'ระดับคะแนนเฉลี่ยสะสมไม่ต่ำกว่า 2.00',
      'Obtain cumulative G.P.A. not less than 2.00'),
    ('transcript_criteria_4', 'ประเมินผ่านเกณฑ์มาตรฐานวิชาชีพ',
      'Achieve the criteria of vocational education standard'),
    ('transcript_note_1', 'โอนผลการเรียน',
      'Refers to credit transferred'),
    ('transcript_note_2', 'เทียบโอนความรู้และประสบการณ์',
      'Refers to the recognition of prior learning'),
    ('transcript_note_3', 'เรียนปรับระดับคะแนน',
      'Refers to study to improve grades'),
    ('transcript_note_4', 'เรียนหรือฝึกอาชีพในสถานประกอบการ',
      'Refers to study or work experience in workplace'),
    ('transcript_note_5', 'จัดการเรียนการสอนเป็นภาษาอังกฤษ',
      'Refers to learning and teaching conducted in English')
  ) as v(key, th, en)
on conflict (institution_id, key) do nothing;

-- ═══════════════════════════════════════════════════════════════════
-- สรุปสิ่งที่วิทยาลัยนี้มีแล้ว — ทุกบรรทัดต้องไม่เป็นศูนย์
-- อยู่ก่อน commit เพราะ _params เป็นตารางชั่วคราวที่ถูกทิ้งตอนจบทรานแซกชัน
-- ═══════════════════════════════════════════════════════════════════
with inst as (
  select i.id from _params p join institution i on i.code = p.institution_code
)
select 'grade_symbol' as what, count(*) as rows
  from grade_symbol x join grade_scheme s on s.id = x.grade_scheme_id
  join inst on inst.id = s.institution_id
union all select 'grade_cutoff', count(*)
  from grade_cutoff x join grade_scheme s on s.id = x.grade_scheme_id
  join inst on inst.id = s.institution_id
union all select 'attendance_status_weight', count(*)
  from attendance_status_weight x join attendance_policy ap on ap.id = x.attendance_policy_id
  join inst on inst.id = ap.institution_id
union all select 'registration_policy', count(*)
  from registration_policy x join inst on inst.id = x.institution_id
union all select 'risk_factor', count(*)
  from risk_factor x join inst on inst.id = x.institution_id
union all select 'behavior_rule', count(*)
  from behavior_rule x join inst on inst.id = x.institution_id
union all select 'ledger_account', count(*)
  from ledger_account x join inst on inst.id = x.institution_id
union all select 'funding_source', count(*)
  from funding_source x join inst on inst.id = x.institution_id
union all select 'late_fee_policy', count(*)
  from late_fee_policy x join inst on inst.id = x.institution_id
union all select 'institution_document_text', count(*)
  from institution_document_text x join inst on inst.id = x.institution_id;

commit;

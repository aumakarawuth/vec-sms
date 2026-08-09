-- ═══════════════════════════════════════════════════════════════════
-- 0004_early_warning.sql — ทดสอบระบบเตือนก่อนออกกลางคัน
-- รันต่อจาก 0001 ถึง 0003
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ───────────────────────────────────────────────────────────────────
-- สร้างสถานการณ์จริง: นักศึกษาที่กำลังจะหลุด
--   ขาดเรียนติดกัน 4 คาบเรียนติดต่อกัน + เวลาเรียนตก + ค้างชำระ
-- ───────────────────────────────────────────────────────────────────
insert into behavior_record (student_id, rule_id, points, occurred_on, detail)
select 'aaaa0000-0000-0000-0000-000000000011', r.id, r.points, current_date - 10, 'หนีเรียนคาบบ่าย'
from behavior_rule r
where r.institution_id = '11111111-1111-1111-1111-111111111111' and r.code = 'SKIP';

insert into behavior_record (student_id, rule_id, points, occurred_on, detail)
select 'aaaa0000-0000-0000-0000-000000000011', r.id, r.points, current_date - 5, 'สูบบุหรี่หลังโรงฝึกงาน'
from behavior_rule r
where r.institution_id = '11111111-1111-1111-1111-111111111111' and r.code = 'SMOKE';

insert into screening_result (student_id, instrument, assessed_on, band, score)
values ('aaaa0000-0000-0000-0000-000000000011', 'SDQ', current_date - 60, 'at_risk', 18.0);

-- ── TEST 31 ────────────────────────────────────────────────────────
-- คะแนนความประพฤติหักตามกฎ 100 - 10 - 20 = 70
do $$
declare v int;
begin
  select balance into v from v_behavior_balance
  where student_id = 'aaaa0000-0000-0000-0000-000000000011';
  if v <> 70 then raise exception 'TEST 31: คะแนนควรเหลือ 70 ได้ %', v; end if;
  raise notice 'TEST 31 ผ่าน — คะแนนความประพฤติหักตามกฎ เหลือ %', v;
end $$;

-- ── TEST 32 ────────────────────────────────────────────────────────
-- บันทึกเชิงบวกต้องบวกคะแนนกลับ
do $$
declare v int;
begin
  insert into behavior_record (student_id, rule_id, points, occurred_on, detail)
  select 'aaaa0000-0000-0000-0000-000000000011', r.id, r.points, current_date - 2,
         'ได้รางวัลรองชนะเลิศทักษะงานเครื่องยนต์เล็ก ระดับจังหวัด'
  from behavior_rule r
  where r.institution_id = '11111111-1111-1111-1111-111111111111' and r.code = 'CONTEST';

  select balance into v from v_behavior_balance
  where student_id = 'aaaa0000-0000-0000-0000-000000000011';
  if v <> 90 then raise exception 'TEST 32: ควรเป็น 90 ได้ %', v; end if;
  raise notice 'TEST 32 ผ่าน — บันทึกเชิงบวกบวกคะแนนกลับ เหลือ % (ระบบส่วนใหญ่บันทึกแต่ความผิด)', v;
end $$;

-- ── TEST 33 ────────────────────────────────────────────────────────
-- คำนวณคะแนนความเสี่ยง — ต้องจับสัญญาณได้หลายตัวและอธิบายเป็นข้อความไทย
do $$
declare v_n int; r record; v_sig text;
begin
  -- สร้างการขาดเรียนติดต่อกัน
  update attendance_record ar
  set status = 'absent'
  from class_meeting cm
  where cm.id = ar.class_meeting_id
    and ar.enrollment_id = 'cccc0000-0000-0000-0000-000000000001'
    and cm.meets_on >= (select max(meets_on) - 28 from class_meeting
                        where class_section_id = 'bbbb0000-0000-0000-0000-000000000001');

  -- ทำให้ค้างชำระอีกครั้ง
  update installment i
  set due_on = current_date - 45, paid_amount = 0, status = 'overdue'
  from invoice inv
  where inv.id = i.invoice_id
    and inv.student_id = 'aaaa0000-0000-0000-0000-000000000011';
  update invoice set paid_total = 0, status = 'issued'
  where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  v_n := compute_risk_scores('11111111-1111-1111-1111-111111111111',
                             '33333333-3333-3333-3333-333333333331');
  if v_n < 1 then raise exception 'TEST 33: ควรคำนวณให้นักศึกษาอย่างน้อย 1 คน ได้ %', v_n; end if;

  select * into r from student_risk_score
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and term_id = '33333333-3333-3333-3333-333333333331';

  if r.score is null then raise exception 'TEST 33: ไม่มีคะแนนความเสี่ยง'; end if;
  if r.band not in ('orange', 'red') then
    raise exception 'TEST 33: นักศึกษาคนนี้ควรอยู่ระดับส้มหรือแดง ได้ %  (คะแนน %)', r.band, r.score;
  end if;

  select string_agg(message_th, ' · ' order by points desc) into v_sig
  from student_risk_signal
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and term_id = '33333333-3333-3333-3333-333333333331';

  raise notice 'TEST 33 ผ่าน — คะแนน % ระดับ %', r.score, r.band;
  raise notice '            สัญญาณ: %', v_sig;
end $$;

-- ── TEST 34 ────────────────────────────────────────────────────────
-- สัญญาณต้องเป็นข้อความที่ครูอ่านให้ผู้ปกครองฟังได้ ไม่ใช่แค่รหัส
do $$
declare v_msg text;
begin
  select message_th into v_msg from student_risk_signal
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and factor_code = 'OVERDUE_PAYMENT';
  if v_msg is null or v_msg !~ 'บาท' then
    raise exception 'TEST 34: ข้อความค้างชำระควรระบุจำนวนเงิน ได้ %', v_msg;
  end if;
  raise notice 'TEST 34 ผ่าน — "%"', v_msg;
end $$;

-- ── TEST 35 ────────────────────────────────────────────────────────
-- เปิดเคสอัตโนมัติ พร้อมเสนอขั้นตอนที่ตรงกับสัญญาณที่พบจริง
do $$
declare v_opened int; v_case uuid; v_actions text; v_due date;
begin
  v_opened := open_intervention_cases('11111111-1111-1111-1111-111111111111',
                                      '33333333-3333-3333-3333-333333333331');
  if v_opened < 1 then raise exception 'TEST 35: ควรเปิดเคสอย่างน้อย 1 เคส ได้ %', v_opened; end if;

  select id, respond_by into v_case, v_due from intervention_case
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and term_id = '33333333-3333-3333-3333-333333333331';

  select string_agg(kind::text, ', ' order by kind) into v_actions
  from intervention_action where case_id = v_case and suggested_by_system;

  if v_actions not like '%call_guardian%' then
    raise exception 'TEST 35: ต้องเสนอให้โทรหาผู้ปกครองเสมอ ได้ %', v_actions;
  end if;
  if v_actions not like '%refer_finance%' then
    raise exception 'TEST 35: ติดค้างชำระต้องเสนอส่งต่องานการเงิน ได้ %', v_actions;
  end if;

  raise notice 'TEST 35 ผ่าน — เปิด % เคส ครบกำหนดตอบสนอง % ขั้นตอนที่เสนอ: %',
    v_opened, v_due, v_actions;
end $$;

-- ── TEST 36 ────────────────────────────────────────────────────────
-- เปิดซ้ำต้องไม่สร้างเคสซ้อน
do $$
declare v_again int; v_total int;
begin
  v_again := open_intervention_cases('11111111-1111-1111-1111-111111111111',
                                     '33333333-3333-3333-3333-333333333331');
  select count(*) into v_total from intervention_case
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and term_id = '33333333-3333-3333-3333-333333333331';
  if v_total <> 1 then raise exception 'TEST 36: ควรมีเคสเดียว ได้ %', v_total; end if;
  raise notice 'TEST 36 ผ่าน — รันซ้ำแล้วไม่เปิดเคสซ้อน (เปิดเพิ่ม % เคส)', v_again;
end $$;

-- ── TEST 37 ────────────────────────────────────────────────────────
-- มุมมองสำหรับหน้าจอครูที่ปรึกษา
do $$
declare r record;
begin
  select * into r from v_students_at_risk
  where student_id = 'aaaa0000-0000-0000-0000-000000000011';
  if r.student_id is null then raise exception 'TEST 37: ไม่พบในมุมมองนักศึกษากลุ่มเสี่ยง'; end if;
  if r.signal_count < 2 then
    raise exception 'TEST 37: ควรมีสัญญาณอย่างน้อย 2 ตัว ได้ %', r.signal_count;
  end if;
  if r.case_id is null then raise exception 'TEST 37: ควรผูกกับเคสที่เปิดอยู่'; end if;
  raise notice 'TEST 37 ผ่าน — % (%) คะแนน % ระดับ % สัญญาณ % ตัว',
    r.full_name, r.student_code, r.score, r.band, r.signal_count;
end $$;

-- ── TEST 38 ────────────────────────────────────────────────────────
-- มูลค่ารายได้ที่เสี่ยงจะสูญ — ตัวเลขที่ผู้บริหารใช้ตัดสินใจ
do $$
declare r record;
begin
  select * into r from v_revenue_at_risk
  where institution_id = '11111111-1111-1111-1111-111111111111'
    and term_id = '33333333-3333-3333-3333-333333333331'
  order by band desc limit 1;

  if r.students is null or r.students < 1 then
    raise exception 'TEST 38: ควรมีนักศึกษากลุ่มเสี่ยงอย่างน้อย 1 คน';
  end if;
  if r.revenue_at_risk is null or r.revenue_at_risk <= 0 then
    raise exception 'TEST 38: มูลค่าที่เสี่ยงควรมากกว่าศูนย์ ได้ %', r.revenue_at_risk;
  end if;

  raise notice 'TEST 38 ผ่าน — ระดับ % : % คน มูลค่าที่เสี่ยงจะสูญ % บาท',
    r.band, r.students, to_char(r.revenue_at_risk, 'FM999,999,990.00');
end $$;

-- ── TEST 39 ────────────────────────────────────────────────────────
-- ปรับน้ำหนักปัจจัยแล้วคะแนนต้องเปลี่ยนตาม — พิสูจน์ว่าไม่ใช่กล่องดำ
do $$
declare v_before smallint; v_after smallint;
begin
  select score into v_before from student_risk_score
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and term_id = '33333333-3333-3333-3333-333333333331';

  update risk_factor set weight = 5
  where institution_id = '11111111-1111-1111-1111-111111111111' and code = 'ABSENT_STREAK';

  perform compute_risk_scores('11111111-1111-1111-1111-111111111111',
                              '33333333-3333-3333-3333-333333333331');

  select score into v_after from student_risk_score
  where student_id = 'aaaa0000-0000-0000-0000-000000000011'
    and term_id = '33333333-3333-3333-3333-333333333331';

  if v_after >= v_before then
    raise exception 'TEST 39: ลดน้ำหนักแล้วคะแนนควรลดลง จาก % เป็น %', v_before, v_after;
  end if;

  update risk_factor set weight = 30
  where institution_id = '11111111-1111-1111-1111-111111111111' and code = 'ABSENT_STREAK';
  perform compute_risk_scores('11111111-1111-1111-1111-111111111111',
                              '33333333-3333-3333-3333-333333333331');

  raise notice 'TEST 39 ผ่าน — ผู้ดูแลปรับน้ำหนักเองได้ คะแนน % ลดเหลือ % แล้วคืนค่าเดิม',
    v_before, v_after;
end $$;

-- ── TEST 40 ────────────────────────────────────────────────────────
-- ข้อมูลชั้นความลับ: ครูผู้สอนทั่วไปต้องไม่เห็นผลคัดกรองและบันทึกเยี่ยมบ้าน
insert into home_visit (student_id, visited_on, visited_by, findings)
values ('aaaa0000-0000-0000-0000-000000000011', current_date - 3,
        'aaaa0000-0000-0000-0000-000000000022',
        'ผู้ปกครองแยกทางกัน นักศึกษาอยู่กับยาย ต้องช่วยงานร้านหลังเลิกเรียน');

begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = '00000000-0000-0000-0000-0000000000ff';

do $$
declare v_screen int; v_visit int;
begin
  select count(*) into v_screen from screening_result;
  select count(*) into v_visit  from home_visit;
  if v_screen <> 0 then raise exception 'TEST 40 ล้มเหลว: ครูทั่วไปเห็นผลคัดกรอง % รายการ', v_screen; end if;
  if v_visit  <> 0 then raise exception 'TEST 40 ล้มเหลว: ครูทั่วไปเห็นบันทึกเยี่ยมบ้าน % รายการ', v_visit; end if;
  raise notice 'TEST 40 ผ่าน — ครูผู้สอนทั่วไปไม่เห็นผลคัดกรองและบันทึกเยี่ยมบ้าน';
end $$;

set local app.role = 'student_affairs';
do $$
declare v_visit int;
begin
  select count(*) into v_visit from home_visit;
  if v_visit <> 1 then raise exception 'TEST 40b ล้มเหลว: งานปกครองควรเห็น 1 รายการ เห็น %', v_visit; end if;
  raise notice 'TEST 40b ผ่าน — งานปกครองเห็นข้อมูลชั้นความลับได้ตามหน้าที่';
end $$;
commit;

\echo ''
\echo '════ ทดสอบระบบเตือนก่อนออกกลางคันครบทุกข้อ ════'

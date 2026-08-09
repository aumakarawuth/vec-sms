-- ═══════════════════════════════════════════════════════════════════
-- 0020_hr.sql
-- ทดสอบงานบุคลากร
--
-- ─── สามอย่างที่ชุดนี้จับ ───
-- 1. **โครงสร้างหน่วยงานที่วนกลับมาที่ตัวเอง** ทุก query ที่ไล่สายบังคับบัญชา
--    จะวนไม่รู้จบและทำให้ทั้งระบบค้าง — เป็นความผิดพลาดที่กดผิดครั้งเดียวก็เกิด
-- 2. **ผู้ยื่นอนุมัติใบลาของตัวเอง** สิทธิ์อนุมัติที่ใช้กับตัวเองได้ไม่ใช่
--    การอนุมัติ แต่เป็นการประทับตรา
-- 3. **วันลาที่นับซ้ำ** ใบลาที่อนุมัติแล้วซ้อนกันทำให้วันลาสะสมเกินจริง
--    แล้วไปโผล่ตอนสิ้นปีโดยไม่มีใครสังเกต
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมหน่วยงาน ─────────────────────────────────────────────────
insert into department (id, institution_id, parent_id, code, name_th, kind, head_staff_id)
values ('dd000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', null,
        'ACAD', 'ฝ่ายวิชาการ', 'division', 'aaaa0000-0000-0000-0000-000000000022'),
       ('dd000000-0000-0000-0000-000000000002',
        '11111111-1111-1111-1111-111111111111',
        'dd000000-0000-0000-0000-000000000001',
        'MECH', 'แผนกวิชาช่างยนต์', 'department', 'aaaa0000-0000-0000-0000-000000000022')
on conflict do nothing;

insert into staff_assignment
  (staff_id, department_id, position_th, is_primary, effective_from)
values ('aaaa0000-0000-0000-0000-000000000022',
        'dd000000-0000-0000-0000-000000000002',
        'หัวหน้าแผนกวิชาช่างยนต์', true, current_date - 365)
on conflict do nothing;

-- ── TEST 165 ───────────────────────────────────────────────────────
-- โครงสร้างหน่วยงานต้องเป็นต้นไม้จริง วนกลับมาที่ตัวเองไม่ได้
do $$
declare
  v_blocked integer := 0;
  v_rows    integer;
  v_depth   integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  -- เป็นแม่ของตัวเอง
  begin
    update department set parent_id = id where id = 'dd000000-0000-0000-0000-000000000001';
  exception when others then v_blocked := v_blocked + 1;
  end;

  -- วนผ่านลูก: ฝ่ายวิชาการ → แผนกช่างยนต์ → ฝ่ายวิชาการ
  begin
    update department set parent_id = 'dd000000-0000-0000-0000-000000000002'
     where id = 'dd000000-0000-0000-0000-000000000001';
  exception when others then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 2 then
    raise exception 'TEST 165 ล้มเหลว: ควรถูกบล็อกสองทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  select count(*), max(depth) into v_rows, v_depth from department_tree();
  if v_rows < 2 or v_depth < 1 then
    raise exception 'TEST 165 ล้มเหลว: ต้นไม้หน่วยงานไม่ถูกต้อง (% แถว ลึกสุด %)', v_rows, v_depth;
  end if;

  raise notice 'TEST 165 ผ่าน — วงจรถูกกันทั้งสองแบบ · ต้นไม้มี % หน่วยงาน ลึกสุด % ชั้น',
    v_rows, v_depth;
end $$;

-- ── TEST 166 ───────────────────────────────────────────────────────
-- สังกัดหลักซ้อนกันสองที่ในเวลาเดียวกันไม่ได้
do $$
declare v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  begin
    insert into staff_assignment
      (staff_id, department_id, position_th, is_primary, effective_from)
    values ('aaaa0000-0000-0000-0000-000000000022',
            'dd000000-0000-0000-0000-000000000001',
            'หัวหน้าฝ่ายวิชาการ', true, current_date);
  exception when exclusion_violation then v_blocked := v_blocked + 1;
  end;

  -- สังกัดรองซ้อนได้ เพราะครูสอนข้ามแผนกเป็นเรื่องปกติ
  insert into staff_assignment
    (staff_id, department_id, position_th, is_primary, effective_from)
  values ('aaaa0000-0000-0000-0000-000000000022',
          'dd000000-0000-0000-0000-000000000001',
          'กรรมการฝ่ายวิชาการ', false, current_date);

  if v_blocked <> 1 then
    raise exception 'TEST 166 ล้มเหลว: สังกัดหลักซ้อนกันได้';
  end if;

  raise notice 'TEST 166 ผ่าน — สังกัดหลักซ้อนไม่ได้ แต่สังกัดรองซ้อนได้';
end $$;

-- ── TEST 167 ───────────────────────────────────────────────────────
-- ใบลา — ผู้ยื่นอนุมัติเองไม่ได้ และที่อนุมัติแล้วซ้อนกันไม่ได้
do $$
declare
  v_leave   uuid;
  v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000002', true);

  insert into staff_leave
    (institution_id, staff_id, kind, from_date, to_date, days, reason, requested_by)
  values ('11111111-1111-1111-1111-111111111111',
          'aaaa0000-0000-0000-0000-000000000022', 'sick',
          current_date + 10, current_date + 11, 2, 'ป่วยเป็นไข้หวัดใหญ่',
          'aaaa0000-0000-0000-0000-000000000002')
  returning id into v_leave;

  -- ผู้ยื่นคือเจ้าของใบลา อนุมัติเองไม่ได้
  begin
    update staff_leave
       set status = 'approved', decided_by = 'aaaa0000-0000-0000-0000-000000000002'
     where id = v_leave;
  exception when others then v_blocked := v_blocked + 1;
  end;

  -- คนอื่นอนุมัติได้
  update staff_leave
     set status = 'approved', decided_by = 'aaaa0000-0000-0000-0000-000000000001'
   where id = v_leave;

  if (select status from staff_leave where id = v_leave) <> 'approved' then
    raise exception 'TEST 167 ล้มเหลว: ผู้บังคับบัญชาอนุมัติแล้วสถานะไม่เปลี่ยน';
  end if;

  -- ใบลาที่อนุมัติแล้วซ้อนวันกันไม่ได้
  begin
    insert into staff_leave
      (institution_id, staff_id, kind, from_date, to_date, days, reason,
       status, requested_by, decided_by)
    values ('11111111-1111-1111-1111-111111111111',
            'aaaa0000-0000-0000-0000-000000000022', 'personal',
            current_date + 11, current_date + 12, 2, 'ธุระส่วนตัว',
            'approved', 'aaaa0000-0000-0000-0000-000000000002',
            'aaaa0000-0000-0000-0000-000000000001');
  exception when exclusion_violation then v_blocked := v_blocked + 1;
  end;

  -- ตัดสินไปแล้วย้อนกลับเป็นรออนุมัติไม่ได้
  begin
    update staff_leave set status = 'pending' where id = v_leave;
  exception when others then v_blocked := v_blocked + 1;
  end;

  if v_blocked <> 3 then
    raise exception 'TEST 167 ล้มเหลว: ควรถูกบล็อกสามทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  raise notice 'TEST 167 ผ่าน — อนุมัติเองไม่ได้ · ลาซ้อนวันไม่ได้ · ย้อนสถานะไม่ได้';
end $$;

-- ── TEST 168 ───────────────────────────────────────────────────────
-- สรุปเวลาทำการต้องนับวันลาที่อนุมัติแล้วด้วย
--
-- ถ้านับจากการสแกนบัตรอย่างเดียว คนที่ลาถูกต้องจะกลายเป็นขาดงานในรายงาน
-- ซึ่งเป็นข้อมูลที่ใช้ประเมินผลงานประจำปี
do $$
declare r record;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  insert into staff_attendance
    (institution_id, staff_id, on_date, status, check_in)
  values ('11111111-1111-1111-1111-111111111111',
          'aaaa0000-0000-0000-0000-000000000022', current_date - 2, 'present', '07:55'),
         ('11111111-1111-1111-1111-111111111111',
          'aaaa0000-0000-0000-0000-000000000022', current_date - 1, 'late', '08:40')
  on conflict (staff_id, on_date) do nothing;

  select * into r
    from staff_worktime_summary(current_date - 30, current_date + 30)
   where staff_id = 'aaaa0000-0000-0000-0000-000000000022';

  if r.staff_id is null then
    raise exception 'TEST 168 ล้มเหลว: ไม่มีบุคลากรในสรุปเวลาทำการ';
  end if;
  if r.present <> 1 or r.late <> 1 then
    raise exception 'TEST 168 ล้มเหลว: นับผิด มาปกติ % สาย %', r.present, r.late;
  end if;
  if r.leave_days <= 0 then
    raise exception 'TEST 168 ล้มเหลว: ไม่ได้นับวันลาที่อนุมัติแล้ว คนที่ลาถูกต้องจะกลายเป็นขาดงาน';
  end if;
  if r.department is null then
    raise exception 'TEST 168 ล้มเหลว: ไม่รู้ว่าสังกัดหน่วยงานไหน';
  end if;

  raise notice 'TEST 168 ผ่าน — % (%) มาปกติ % · สาย % · วันลาสะสม %',
    r.full_name, r.department, r.present, r.late, r.leave_days;
end $$;

-- ── TEST 169 ───────────────────────────────────────────────────────
-- ระเบียนบุคลากร (ทช.1) และบุตรบุคลากร
do $$
declare
  v_edu integer;
  v_hrs numeric;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);

  insert into staff_record
    (staff_id, kind, title_th, organization_th, field_th, started_on, ended_on)
  values ('aaaa0000-0000-0000-0000-000000000022', 'education',
          'ครุศาสตร์อุตสาหกรรมบัณฑิต', 'มหาวิทยาลัยเทคโนโลยีทดสอบ',
          'วิศวกรรมเครื่องกล', '2555-06-01', '2559-03-31');

  insert into staff_record
    (staff_id, kind, title_th, organization_th, started_on, ended_on, hours)
  values ('aaaa0000-0000-0000-0000-000000000022', 'training',
          'อบรมการจัดการเรียนรู้ฐานสมรรถนะ', 'สำนักงานคณะกรรมการการอาชีวศึกษา',
          current_date - 60, current_date - 58, 18);

  -- บุตรบุคลากรที่เรียนที่นี่ — ทำให้ส่วนลด staff_child ตรวจสอบได้
  insert into staff_child (staff_id, full_name_th, birth_date, student_id)
  values ('aaaa0000-0000-0000-0000-000000000022', 'ด.ญ. ทดสอบ ใจงาม', '2555-01-15',
          'aaaa0000-0000-0000-0000-000000000012');

  select count(*) into v_edu
    from staff_record where staff_id = 'aaaa0000-0000-0000-0000-000000000022'
     and kind = 'education';
  select coalesce(sum(hours), 0) into v_hrs
    from staff_record where staff_id = 'aaaa0000-0000-0000-0000-000000000022'
     and kind = 'training';

  if v_edu = 0 or v_hrs = 0 then
    raise exception 'TEST 169 ล้มเหลว: ระเบียนบุคลากรไม่ครบ (การศึกษา % · ชั่วโมงอบรม %)',
      v_edu, v_hrs;
  end if;

  -- บุตรคนเดิมผูกกับนักศึกษาสองคนไม่ได้
  begin
    insert into staff_child (staff_id, full_name_th, student_id)
    values ('aaaa0000-0000-0000-0000-000000000022', 'ชื่ออื่น',
            'aaaa0000-0000-0000-0000-000000000012');
    raise exception 'TEST 169 ล้มเหลว: นักศึกษาคนเดียวเป็นบุตรของสองรายการได้';
  exception when unique_violation then null;
  end;

  raise notice 'TEST 169 ผ่าน — ระเบียน ทช.1 มีวุฒิ % รายการ · ชั่วโมงอบรม % ชั่วโมง · ผูกบุตรบุคลากรกับนักศึกษาได้',
    v_edu, v_hrs;
end $$;

-- ── TEST 170 ───────────────────────────────────────────────────────
-- ประวัติบุคลากรและใบลาเป็นข้อมูลส่วนบุคคล — บุคลากรเห็นของตัวเองเท่านั้น
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_mine integer; v_dept integer;
begin
  select count(*) into v_mine from staff_record;
  select count(*) into v_dept from department;

  -- ครูคนนี้คือเจ้าของระเบียน จึงต้องเห็นของตัวเอง
  if v_mine = 0 then
    raise exception 'TEST 170 ล้มเหลว: บุคลากรไม่เห็นระเบียนของตัวเองเลย';
  end if;
  -- โครงสร้างหน่วยงานเป็นข้อมูลภายในองค์กร ครูต้องรู้ว่าตัวเองสังกัดที่ไหน
  if v_dept = 0 then
    raise exception 'TEST 170 ล้มเหลว: ครูมองไม่เห็นโครงสร้างหน่วยงานเลย';
  end if;
end $$;
rollback;

begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_d integer; v_l integer; v_r integer; v_a integer;
begin
  select count(*) into v_d from department;
  select count(*) into v_l from staff_leave;
  select count(*) into v_r from staff_record;
  select count(*) into v_a from staff_attendance;
  if v_d + v_l + v_r + v_a <> 0 then
    raise exception 'TEST 170 ล้มเหลว: วิทยาลัยอื่นเห็นหน่วยงาน % ใบลา % ระเบียน % เวลาทำการ %',
      v_d, v_l, v_r, v_a;
  end if;
  raise notice 'TEST 170 ผ่าน — บุคลากรเห็นระเบียนของตัวเอง · วิทยาลัยอื่นไม่เห็นอะไรเลย';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบงานบุคลากรครบทุกข้อ ════'; end $$;

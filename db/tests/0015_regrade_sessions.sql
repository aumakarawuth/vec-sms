-- ═══════════════════════════════════════════════════════════════════
-- 0015_regrade_sessions.sql
-- ทดสอบรอบสอบซ่อมและเรียนปรับเกรด
--
-- ─── สองอย่างที่ชุดนี้จับเป็นพิเศษ ───
-- 1. **สิทธิ์เข้ารอบต้องคำนวณจากข้อมูลจริง** ไม่ใช่เชื่อรายชื่อที่ส่งมา
--    ถ้าตรวจไม่ครบ นักศึกษาที่สอบผ่านไปแล้วจะเข้าสอบซ่อมได้ ซึ่งเปิดทาง
--    ให้แก้เกรดของคนที่ผ่านแล้วโดยไม่มีใครสังเกต
--
-- 2. **ผลสอบซ่อมต้องไม่เขียนเกรดตรง ๆ** เกรดในระบบนี้เปลี่ยนได้ทางเดียว
--    คือผ่าน grade_change_request ซึ่งมี dual control ถ้ารอบสอบซ่อมเขียน
--    เกรดได้เอง ใครก็ตามที่สร้างรอบขึ้นมาได้จะแก้เกรดใครก็ได้โดยไม่ต้อง
--    ผ่านการอนุมัติของใครเลย — เป็นช่องที่ใหญ่กว่าตัวฟีเจอร์เองมาก
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── เตรียมรอบและวิชา ───────────────────────────────────────────────
insert into regrade_session
  (id, institution_id, term_id, code, name_th, kind, opens_on, closes_on, status)
values ('f0000000-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111',
        (select id from term order by ordinal limit 1),
        'RG-1-2569', 'เรียนปรับเกรด 1/2569 (ปวช.)', 'restudy',
        current_date - 1, current_date + 30, 'open')
on conflict do nothing;

insert into regrade_session_course (id, session_id, course_id, fee_amount, capacity)
select 'f0000000-0000-0000-0000-000000000002',
       'f0000000-0000-0000-0000-000000000001', cs.course_id, 600, 5
  from enrollment e
  join class_section cs on cs.id = e.class_section_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gs on gs.id = er.grade_symbol_id
 where not gs.earns_credit
 limit 1
on conflict do nothing;

-- ── TEST 138 ───────────────────────────────────────────────────────
-- สิทธิ์เข้ารอบคำนวณจากผลการเรียนจริง — คนที่ผ่านแล้วต้องไม่อยู่ในรายชื่อ
do $$
declare
  v_eligible integer;
  v_passed   integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select count(*) into v_eligible
    from regrade_eligible('f0000000-0000-0000-0000-000000000002');

  if v_eligible = 0 then
    raise exception 'TEST 138 ล้มเหลว: ไม่มีใครมีสิทธิ์เลย ทั้งที่มีนักศึกษาที่ยังไม่ได้หน่วยกิต';
  end if;

  -- ปิยะพงศ์ได้ 2.5 ซึ่งได้หน่วยกิตแล้ว ต้องไม่อยู่ในรายชื่อ
  select count(*) into v_passed
    from regrade_eligible('f0000000-0000-0000-0000-000000000002')
   where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  if v_passed > 0 then
    raise exception 'TEST 138 ล้มเหลว: คนที่ได้หน่วยกิตแล้วยังอยู่ในรายชื่อผู้มีสิทธิ์สอบซ่อม';
  end if;

  raise notice 'TEST 138 ผ่าน — มีสิทธิ์ % คน และคนที่ผ่านแล้วไม่อยู่ในรายชื่อ', v_eligible;
end $$;

-- ── TEST 139 ───────────────────────────────────────────────────────
-- ลงทะเบียนกลุ่ม — คนไม่มีสิทธิ์ต้องไม่ทำให้คนที่มีสิทธิ์ล้มไปด้วย
do $$
declare
  v_ok      integer;
  v_no      integer;
  v_again   integer;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select count(*) filter (where registered),
         count(*) filter (where not registered)
    into v_ok, v_no
    from register_regrade('f0000000-0000-0000-0000-000000000002',
           (select array_agg(id) from student
             where institution_id = '11111111-1111-1111-1111-111111111111'));

  if v_ok = 0 then
    raise exception 'TEST 139 ล้มเหลว: ไม่มีใครลงทะเบียนได้เลย';
  end if;
  if v_no = 0 then
    raise exception 'TEST 139 ล้มเหลว: ทุกคนลงได้หมด แปลว่าไม่ได้ตรวจสิทธิ์เลย';
  end if;

  -- ลงซ้ำต้องถูกปฏิเสธรายคน ไม่ใช่ล้มทั้งคำขอ
  select count(*) filter (where not registered) into v_again
    from register_regrade('f0000000-0000-0000-0000-000000000002',
           (select array_agg(rc.student_id) from regrade_candidate rc
             where rc.session_course_id = 'f0000000-0000-0000-0000-000000000002'));

  if v_again <> v_ok then
    raise exception 'TEST 139 ล้มเหลว: ลงซ้ำควรถูกปฏิเสธ % ราย ถูกปฏิเสธจริง %', v_ok, v_again;
  end if;

  raise notice 'TEST 139 ผ่าน — ลงได้ % คน ไม่มีสิทธิ์ % คน และลงซ้ำถูกปฏิเสธครบ', v_ok, v_no;
end $$;

-- ── TEST 140 ───────────────────────────────────────────────────────
-- บันทึกผลต้องได้คำร้องแก้เกรด และเกรดต้องยังไม่เปลี่ยนจนกว่าจะอนุมัติ
do $$
declare
  v_cand   uuid;
  v_sym    uuid;
  v_req    uuid;
  v_before text;
  v_after  text;
  v_status regrade_candidate_status;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  -- เลี่ยงคนที่มีคำร้องค้างอยู่แล้วจากชุดทดสอบ 0009
  select rc.id into v_cand
    from regrade_candidate rc
   where rc.session_course_id = 'f0000000-0000-0000-0000-000000000002'
     and rc.status = 'registered'
     and not exists (select 1 from grade_change_request g
                      where g.enrollment_id = rc.source_enrollment_id
                        and g.status = 'pending')
   limit 1;

  if v_cand is null then
    raise exception 'TEST 140 ล้มเหลว: ไม่มีผู้เข้ารอบที่พร้อมบันทึกผล';
  end if;

  select gs.id into v_sym
    from grade_symbol gs where gs.earns_credit and gs.grade_point = 1.0 limit 1;

  select gs.symbol into v_before
    from regrade_candidate rc
    join enrollment_result er on er.enrollment_id = rc.source_enrollment_id
                             and er.superseded_by is null
    join grade_symbol gs on gs.id = er.grade_symbol_id
   where rc.id = v_cand;

  v_req := record_regrade_result(v_cand, v_sym, 'สอบซ่อมผ่านตามรอบ RG-1-2569', 'ที่ ศธ 999/2569');

  select gs.symbol into v_after
    from regrade_candidate rc
    join enrollment_result er on er.enrollment_id = rc.source_enrollment_id
                             and er.superseded_by is null
    join grade_symbol gs on gs.id = er.grade_symbol_id
   where rc.id = v_cand;

  select status into v_status from regrade_candidate where id = v_cand;

  if v_req is null then
    raise exception 'TEST 140 ล้มเหลว: ไม่ได้สร้างคำร้องแก้เกรด';
  end if;
  if v_after is distinct from v_before then
    raise exception 'TEST 140 ล้มเหลว: เกรดเปลี่ยนทันทีที่บันทึกผล (% → %) ข้าม dual control ไปแล้ว',
      v_before, v_after;
  end if;
  if v_status <> 'passed' then
    raise exception 'TEST 140 ล้มเหลว: สถานะผู้เข้ารอบควรเป็น passed ได้ %', v_status;
  end if;
  if not exists (select 1 from grade_change_request where id = v_req and status = 'pending') then
    raise exception 'TEST 140 ล้มเหลว: คำร้องที่สร้างไม่ได้อยู่ในสถานะรออนุมัติ';
  end if;

  raise notice 'TEST 140 ผ่าน — ยื่นคำร้องแล้ว เกรดยังเป็น % เหมือนเดิมจนกว่าจะอนุมัติสองชั้น', v_before;
end $$;

-- ── TEST 141 ───────────────────────────────────────────────────────
-- บันทึกผลซ้ำไม่ได้ · รอบที่ปิดแล้วรับคนไม่ได้
do $$
declare
  v_cand    uuid;
  v_sym     uuid;
  v_blocked integer := 0;
begin
  perform set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('app.actor_id', 'aaaa0000-0000-0000-0000-000000000001', true);

  select id into v_cand from regrade_candidate
   where session_course_id = 'f0000000-0000-0000-0000-000000000002'
     and status <> 'registered' limit 1;
  select gs.id into v_sym from grade_symbol gs where gs.earns_credit limit 1;

  begin
    perform record_regrade_result(v_cand, v_sym, 'ลองบันทึกซ้ำ');
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  update regrade_session set status = 'closed'
   where id = 'f0000000-0000-0000-0000-000000000001';

  begin
    perform register_regrade('f0000000-0000-0000-0000-000000000002',
      array['aaaa0000-0000-0000-0000-000000000014']::uuid[]);
  exception when check_violation then v_blocked := v_blocked + 1;
  end;

  update regrade_session set status = 'open'
   where id = 'f0000000-0000-0000-0000-000000000001';

  if v_blocked <> 2 then
    raise exception 'TEST 141 ล้มเหลว: ควรถูกบล็อกสองทาง ถูกบล็อกจริง % ทาง', v_blocked;
  end if;

  raise notice 'TEST 141 ผ่าน — บันทึกผลซ้ำไม่ได้ และรอบที่ปิดแล้วรับคนไม่ได้';
end $$;

-- ── TEST 142 ───────────────────────────────────────────────────────
-- วิทยาลัยอื่นต้องไม่เห็นรอบสอบซ่อมของเราเลย
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_s integer; v_c integer; v_k integer;
begin
  select count(*) into v_s from regrade_session;
  select count(*) into v_c from regrade_session_course;
  select count(*) into v_k from regrade_candidate;

  if v_s + v_c + v_k <> 0 then
    raise exception 'TEST 142 ล้มเหลว: วิทยาลัยอื่นเห็นรอบ % วิชา % ผู้เข้ารอบ %', v_s, v_c, v_k;
  end if;
  raise notice 'TEST 142 ผ่าน — วิทยาลัยอื่นไม่เห็นรอบสอบซ่อมของเราเลยสักแถว';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบรอบสอบซ่อมและเรียนปรับเกรดครบทุกข้อ ════'; end $$;

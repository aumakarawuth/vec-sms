-- ═══════════════════════════════════════════════════════════════════
-- 0010_dual_and_curriculum.sql
-- ทดสอบทวิภาคี การฝึกประสบการณ์ และการออกฉบับหลักสูตรใหม่
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_runtime') then
    create role app_runtime nologin;
  end if;
end $$;
grant usage on schema public to app_runtime;
grant select, insert, update, delete on all tables    in schema public to app_runtime;
grant usage, select                  on all sequences in schema public to app_runtime;
grant execute                        on all functions in schema public to app_runtime;

-- ── เตรียมข้อมูล ───────────────────────────────────────────────────
insert into workplace
  (id, institution_id, code, name_th, industry, province,
   lat, lng, checkin_radius_m, contact_name, contact_phone, capacity)
values
  ('bbbb1111-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111', 'WP-001',
   'อู่ช่างสมศักดิ์ยานยนต์', 'ซ่อมบำรุงยานยนต์', 'ชลบุรี',
   13.361143, 100.984673, 200, 'สมศักดิ์ ช่างดี', '0891234567', 5),
  ('bbbb1111-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111', 'WP-002',
   'บริษัท ยานยนต์ไทย จำกัด', 'ผลิตชิ้นส่วนยานยนต์', 'ระยอง',
   12.681000, 101.257000, 500, 'ฝ่ายบุคคล', '0384567890', 20)
on conflict (id) do nothing;

-- ── TEST 81 ────────────────────────────────────────────────────────
-- สถานประกอบการที่ยังไม่ผ่านประเมินต้องส่งนักศึกษาไปฝึกไม่ได้
--
-- ระเบียบทวิภาคีกำหนดว่าต้องประเมินความพร้อมก่อน ถ้าไม่บังคับที่ระบบ
-- จะมีการส่งตัวไปที่ที่ยังไม่ผ่านโดยไม่มีใครสังเกต เพราะใบส่งตัว
-- ก็ดูเหมือนกันหมด
do $$
declare v_status workplace_status;
begin
  select status into v_status from workplace where id = 'bbbb1111-0000-0000-0000-000000000001';
  if v_status <> 'draft' then
    raise exception 'TEST 81 ล้มเหลว: สถานประกอบการใหม่ควรเป็น draft ได้ %', v_status;
  end if;
  raise notice 'TEST 81 ผ่าน — สถานประกอบการที่สร้างใหม่เป็น % ยังรับนักศึกษาไม่ได้', v_status;
end $$;

-- อนุมัติให้ที่แรก
update workplace
   set status = 'approved', assessed_on = current_date, approved_at = now(),
       approved_by = 'aaaa0000-0000-0000-0000-000000000022'
 where id = 'bbbb1111-0000-0000-0000-000000000001';

insert into workplace_supervisor
  (id, workplace_id, full_name_th, position_th, phone, is_primary)
values ('bbbb1111-0000-0000-0000-0000000000a1',
        'bbbb1111-0000-0000-0000-000000000001',
        'สมศักดิ์ ช่างดี', 'เจ้าของกิจการ', '0891234567', true)
on conflict (id) do nothing;

-- ── TEST 82 ────────────────────────────────────────────────────────
-- ส่งนักศึกษาคนเดียวไปฝึกสองที่ในช่วงเวลาเดียวกันไม่ได้
--
-- เคยเกิดจริงเมื่อครูสองคนส่งตัวคนเดียวกันไปคนละที่ แล้วชั่วโมงถูกนับซ้ำ
-- จนนักศึกษาผ่านเกณฑ์ 320 ชั่วโมงทั้งที่ฝึกจริงครึ่งเดียว
do $$
begin
  insert into student_placement
    (id, student_id, workplace_id, starts_on, ends_on, target_hours,
     supervisor_id, advisor_staff_id, status)
  values ('bbbb1111-0000-0000-0000-0000000000b1',
          'aaaa0000-0000-0000-0000-000000000011',
          'bbbb1111-0000-0000-0000-000000000001',
          date '2026-06-01', date '2026-09-30', 320,
          'bbbb1111-0000-0000-0000-0000000000a1',
          'aaaa0000-0000-0000-0000-000000000022', 'active')
  on conflict (id) do nothing;

  begin
    insert into student_placement
      (student_id, workplace_id, starts_on, ends_on, status)
    values ('aaaa0000-0000-0000-0000-000000000011',
            'bbbb1111-0000-0000-0000-000000000002',
            date '2026-08-01', date '2026-10-31', 'planned');
    raise exception 'TEST 82 ล้มเหลว: ส่งนักศึกษาคนเดียวไปฝึกสองที่พร้อมกันได้';
  exception
    when exclusion_violation then
      raise notice 'TEST 82 ผ่าน — กันส่งนักศึกษาคนเดียวไปฝึกสองที่พร้อมกัน (ชั่วโมงจะถูกนับซ้ำ)';
  end;
end $$;

-- ── TEST 83 ────────────────────────────────────────────────────────
-- practicum_log ผูกกับสถานประกอบการจริงแล้ว — ใส่ที่ฝึกมั่วไม่ได้
--
-- ก่อน migration 0019 คอลัมน์นี้ไม่มีคีย์นอก ใส่ uuid อะไรก็ได้
do $$
begin
  begin
    insert into practicum_log (student_id, workplace_id, worked_on, hours)
    values ('aaaa0000-0000-0000-0000-000000000011',
            '00000000-0000-0000-0000-0000000000ff', current_date, 8);
    raise exception 'TEST 83 ล้มเหลว: บันทึกชั่วโมงฝึกที่สถานประกอบการที่ไม่มีอยู่จริงได้';
  exception
    when foreign_key_violation then
      raise notice 'TEST 83 ผ่าน — ชั่วโมงฝึกต้องผูกกับสถานประกอบการที่มีอยู่จริง';
  end;
end $$;

-- ── TEST 84 ────────────────────────────────────────────────────────
-- ชั่วโมงที่ยังไม่รับรองต้องไม่ถูกนับในการตรวจจบ แต่ต้องแสดงเป็นยอดรอรับรอง
insert into practicum_log
  (student_id, placement_id, workplace_id, worked_on, hours, source)
select 'aaaa0000-0000-0000-0000-000000000011',
       'bbbb1111-0000-0000-0000-0000000000b1',
       'bbbb1111-0000-0000-0000-000000000001',
       date '2026-06-01' + g, 8, 'student_app'
  from generate_series(0, 39) g
on conflict do nothing;

do $$
declare v_verified numeric; v_pending numeric; v_required numeric; v_grad numeric;
begin
  select verified_hours, pending_hours, required_hours
    into v_verified, v_pending, v_required
    from v_student_practicum where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  select achieved into v_grad
    from evaluate_graduation('aaaa0000-0000-0000-0000-000000000011')
   where kind = 'practicum_hours';

  if v_pending <> 320 then
    raise exception 'TEST 84 ล้มเหลว: ยอดรอรับรองควรเป็น 320 ได้ %', v_pending;
  end if;
  if v_verified <> 0 then
    raise exception 'TEST 84 ล้มเหลว: ยังไม่รับรองแต่นับเป็นรับรองแล้ว %', v_verified;
  end if;
  if v_grad <> 0 then
    raise exception 'TEST 84 ล้มเหลว: ตรวจจบนับชั่วโมงที่ยังไม่รับรอง (%)', v_grad;
  end if;

  raise notice 'TEST 84 ผ่าน — รอรับรอง % ชม. · รับรองแล้ว % ชม. · ตรวจจบนับ % จากเกณฑ์ %',
    v_pending, v_verified, v_grad, v_required;
end $$;

-- ── TEST 85 ────────────────────────────────────────────────────────
-- ผู้รับรองต้องเป็นบุคลากรของวิทยาลัย ไม่ใช่ตัวนักศึกษาเอง
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';

do $$
declare v_ids uuid[];
begin
  select array_agg(id) into v_ids from practicum_log
   where student_id = 'aaaa0000-0000-0000-0000-000000000011' limit 5;

  begin
    perform verify_practicum_hours(v_ids);
    raise exception 'TEST 85 ล้มเหลว: นักศึกษารับรองชั่วโมงของตัวเองได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 85%' then raise; end if;
      raise notice 'TEST 85 ผ่าน — %', sqlerrm;
  end;
end $$;
commit;

-- ── TEST 86 ────────────────────────────────────────────────────────
-- ครูนิเทศรับรองแล้วชั่วโมงถึงจะนับในการตรวจจบ
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v_ids uuid[]; v_n int; v_verified numeric; v_grad numeric;
begin
  select array_agg(id) into v_ids from practicum_log
   where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  select verify_practicum_hours(v_ids) into v_n;

  select verified_hours into v_verified
    from v_student_practicum where student_id = 'aaaa0000-0000-0000-0000-000000000011';

  select achieved into v_grad
    from evaluate_graduation('aaaa0000-0000-0000-0000-000000000011')
   where kind = 'practicum_hours';

  if v_verified <> 320 or v_grad <> 320 then
    raise exception 'TEST 86 ล้มเหลว: รับรอง % รายการแล้ว แต่ได้ % ชม. ตรวจจบนับ %',
      v_n, v_verified, v_grad;
  end if;
  raise notice 'TEST 86 ผ่าน — ครูนิเทศรับรอง % รายการ ชั่วโมงเข้าเกณฑ์ตรวจจบ % ชม.', v_n, v_grad;
end $$;
commit;

-- ── TEST 87 ────────────────────────────────────────────────────────
-- นักศึกษาเห็นใบส่งตัวของตัวเอง แต่ไม่เห็นของคนอื่น
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';

do $$
declare v_own int; v_all int;
begin
  select count(*) into v_own from student_placement
   where student_id = 'aaaa0000-0000-0000-0000-000000000011';
  select count(*) into v_all from student_placement;

  if v_own = 0 then
    raise exception 'TEST 87 ล้มเหลว: นักศึกษาดูใบส่งตัวของตัวเองไม่ได้';
  end if;
  if v_all <> v_own then
    raise exception 'TEST 87 ล้มเหลว: นักศึกษาเห็นใบส่งตัวของคนอื่นด้วย (% จาก %)', v_own, v_all;
  end if;
  raise notice 'TEST 87 ผ่าน — นักศึกษาเห็นเฉพาะใบส่งตัวของตัวเอง % ใบ', v_own;
end $$;
commit;

-- ── TEST 88 ────────────────────────────────────────────────────────
-- วิทยาลัยอื่นไม่เห็นทะเบียนสถานประกอบการและใบส่งตัว
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'admin';

do $$
declare v_wp int; v_sp int; v_sup int; v_ag int;
begin
  select count(*) into v_wp  from workplace;
  select count(*) into v_sp  from student_placement;
  select count(*) into v_sup from workplace_supervisor;
  select count(*) into v_ag  from dual_training_agreement;

  if v_wp <> 0 or v_sp <> 0 or v_sup <> 0 or v_ag <> 0 then
    raise exception
      'TEST 88 ล้มเหลว: วิทยาลัยอื่นเห็น สถานประกอบการ % · ใบส่งตัว % · ครูฝึก % · ข้อตกลง %',
      v_wp, v_sp, v_sup, v_ag;
  end if;
  raise notice 'TEST 88 ผ่าน — วิทยาลัยอื่นไม่เห็นข้อมูลทวิภาคีเลย';
end $$;
commit;

-- ── TEST 89 ────────────────────────────────────────────────────────
-- ออกฉบับหลักสูตรใหม่แล้วโครงสร้างต้องครบ และ parent_id ต้องไม่ชี้ข้ามฉบับ
--
-- ข้อนี้คือจุดที่การคัดลอกด้วยมือพลาดเสมอ — หมวดวิชาของฉบับใหม่
-- ยังแขวนอยู่ใต้ต้นไม้ของฉบับเดิม แล้ว v_student_credits_by_category
-- จะไต่ขึ้นไปนับหน่วยกิตข้ามฉบับ ตรวจจบผ่านทั้งที่เรียนไม่ครบ
do $$
declare
  v_new uuid;
  v_src_cats int; v_src_courses int; v_src_rules int; v_src_comp int; v_src_path int;
  v_new_cats int; v_new_courses int; v_new_rules int; v_new_comp int; v_new_path int;
  v_leaked int; v_status curriculum_status; v_nested int;
begin
  select count(*) into v_src_cats    from curriculum_category where curriculum_version_id = '77777777-7777-7777-7777-777777777767';
  select count(*) into v_src_courses from curriculum_course   where curriculum_version_id = '77777777-7777-7777-7777-777777777767';
  select count(*) into v_src_rules   from graduation_rule     where curriculum_version_id = '77777777-7777-7777-7777-777777777767';
  select count(*) into v_src_comp    from competency          where curriculum_version_id = '77777777-7777-7777-7777-777777777767';
  select count(*) into v_src_path    from entry_pathway       where curriculum_version_id = '77777777-7777-7777-7777-777777777767';

  select clone_curriculum_version('77777777-7777-7777-7777-777777777767',
                                  2571::smallint, 2571::smallint) into v_new;

  select count(*) into v_new_cats    from curriculum_category where curriculum_version_id = v_new;
  select count(*) into v_new_courses from curriculum_course   where curriculum_version_id = v_new;
  select count(*) into v_new_rules   from graduation_rule     where curriculum_version_id = v_new;
  select count(*) into v_new_comp    from competency          where curriculum_version_id = v_new;
  select count(*) into v_new_path    from entry_pathway       where curriculum_version_id = v_new;
  select status into v_status from curriculum_version where id = v_new;
  select count(*) into v_nested from curriculum_category
   where curriculum_version_id = v_new and parent_id is not null;

  select count(*) into v_leaked
    from curriculum_category child
    join curriculum_category parent on parent.id = child.parent_id
   where child.curriculum_version_id = v_new
     and parent.curriculum_version_id <> v_new;

  if v_new_cats <> v_src_cats or v_new_courses <> v_src_courses
     or v_new_rules <> v_src_rules or v_new_comp <> v_src_comp
     or v_new_path <> v_src_path then
    raise exception
      'TEST 89 ล้มเหลว: คัดลอกไม่ครบ — หมวด %/% · รายวิชา %/% · กฎ %/% · สมรรถนะ %/% · เส้นทาง %/%',
      v_new_cats, v_src_cats, v_new_courses, v_src_courses, v_new_rules, v_src_rules,
      v_new_comp, v_src_comp, v_new_path, v_src_path;
  end if;

  if v_leaked > 0 then
    raise exception 'TEST 89 ล้มเหลว: หมวดวิชา % หมวดของฉบับใหม่ยังชี้ไปหมวดแม่ของฉบับเดิม', v_leaked;
  end if;

  if v_status <> 'draft' then
    raise exception 'TEST 89 ล้มเหลว: ฉบับใหม่ต้องเกิดเป็น draft ได้ %', v_status;
  end if;

  raise notice
    'TEST 89 ผ่าน — โคลนครบ (หมวด % ซ้อนชั้น % · รายวิชา % · กฎ % · สมรรถนะ % · เส้นทาง %) สถานะ % · ไม่มีหมวดชี้ข้ามฉบับ',
    v_new_cats, v_nested, v_new_courses, v_new_rules, v_new_comp, v_new_path, v_status;
end $$;

-- ── TEST 90 ────────────────────────────────────────────────────────
-- ออกฉบับซ้ำปีเดิมไม่ได้
do $$
begin
  begin
    perform clone_curriculum_version('77777777-7777-7777-7777-777777777767',
                                     2571::smallint, 2572::smallint);
    raise exception 'TEST 90 ล้มเหลว: ออกฉบับปีเดิมซ้ำได้';
  exception
    when raise_exception then
      if sqlerrm like 'TEST 90%' then raise; end if;
      raise notice 'TEST 90 ผ่าน — %', sqlerrm;
  end;
end $$;

\echo ''
\echo '════ ทดสอบทวิภาคีและหลักสูตรครบทุกข้อ ════'

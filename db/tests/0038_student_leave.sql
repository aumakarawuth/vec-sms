-- ═══════════════════════════════════════════════════════════════════
-- 0038_student_leave.sql
-- ทดสอบการลาของนักศึกษา (0054)
--
-- ─── ทำไมต้องยิง SQL จริง ───
-- ใบลาที่อนุมัติแล้ว**แก้ `attendance_record` จริง** ซึ่งเป็นตารางที่ 0039
-- ปิดไว้ไม่ให้นักศึกษาเขียน (ข้อ 11 — นักศึกษาเคยแก้เวลาเรียนของตัวเองได้)
-- ถ้าเส้นทางใบลาเปิดช่องกลับมา จะมองไม่เห็นจากชั้น API เลย เพราะช่องอยู่ที่
-- "ใครเป็นคนสั่งให้ฟังก์ชันเขียน" ไม่ใช่ที่ endpoint
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. นักศึกษายื่นใบลาของตัวเองได้ แต่อนุมัติเองไม่ได้
-- 2. อนุมัติแล้วเวลาเรียนเปลี่ยนจริง — ขาดเรียนกลายเป็นลาป่วย
-- 3. ใบลาไม่ทับสถานะที่ครูเช็คว่ามาเรียน
-- 4. ยกเลิกแล้วคืนค่าเดิม**ตรงแถว** — แถวที่เดิมไม่มีต้องถูกลบ ไม่ใช่กลายเป็นขาด
-- 5. ครูผู้สอนอนุมัติใบลาไม่ได้ (เขียน attendance ของกลุ่มตัวเองได้ก็จริง
--    แต่ต้องไม่ได้แปลว่าอนุมัติใบลาได้)
-- 6. ครูที่ปรึกษาเห็นใบลาของเด็กในที่ปรึกษาตัวเอง แต่ของคนอื่นไม่เห็น
--
-- หมายเหตุ: ข้อที่ต้อง "ถูกปฏิเสธ" ใช้ธงบูลีนกับ sqlerrm ที่จับไว้
-- ไม่ raise ในบล็อกที่ตัวเองดักอยู่ (กับดักที่เขียนไว้ในหัวไฟล์ 0024)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- นักศึกษาที่มีคาบเรียนจริงในตาราง — ต้องมีคาบ มิฉะนั้นเทสต์ข้อ 2 จะผ่าน
-- ด้วยเหตุผลที่ผิด (อนุมัติได้แต่ไม่มีอะไรให้ปรับ)
select e.student_id as stu_id,
       s.institution_id as inst_id,
       s.person_id as stu_person,
       min(cm.meets_on) as day1,
       max(cm.meets_on) as day2
  from enrollment e
  join student s        on s.id = e.student_id
  join class_meeting cm on cm.class_section_id = e.class_section_id
 where e.status = 'enrolled' and cm.status <> 'cancelled'
 group by e.student_id, s.institution_id, s.person_id
having count(*) >= 3
 order by e.student_id
 limit 1 \gset

select s.id as other_stu
  from student s
 where s.institution_id = :'inst_id' and s.id <> :'stu_id'
 order by s.id limit 1 \gset

select p.id as registrar_person
  from person p
  join staff st      on st.person_id = p.id
  join staff_role sr on sr.staff_id = st.id
 where sr.role in ('registrar', 'director', 'admin')
   and st.institution_id = :'inst_id'
 order by p.id limit 1 \gset

select st.id as teacher_staff, st.person_id as teacher_person
  from staff st
 where st.is_teacher and st.institution_id = :'inst_id'
 order by st.id limit 1 \gset

select set_config('test.stu',       :'stu_id',          false) as a,
       set_config('test.inst',      :'inst_id',         false) as b,
       set_config('test.stuperson', :'stu_person',      false) as c,
       set_config('test.other',     :'other_stu',       false) as d,
       set_config('test.registrar', :'registrar_person', false) as e,
       set_config('test.teacher',   :'teacher_person',  false) as f,
       set_config('test.tstaff',    :'teacher_staff',   false) as g,
       set_config('test.day1',      :'day1',            false) as h,
       set_config('test.day2',      :'day2',            false) as i \gset

-- ── TEST 236 ───────────────────────────────────────────────────────
-- นักศึกษายื่นใบลาของตัวเองได้ แต่อนุมัติเองไม่ได้
do $$
declare v_leave uuid; v_blocked boolean := false; v_msg text;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.stuperson'), true);
  perform set_config('app.role',           'student', true);

  insert into student_leave
    (institution_id, student_id, kind, from_date, to_date, reason, requested_by)
  values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
          'sick', current_setting('test.day1')::date, current_setting('test.day1')::date,
          'เป็นไข้', current_setting('test.stuperson')::uuid)
  returning id into v_leave;

  begin
    perform decide_student_leave(v_leave, true, 'อนุมัติเอง');
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  reset role;
  perform set_config('test.leave', v_leave::text, false);

  if not v_blocked then
    raise exception 'TEST 236 ล้มเหลว: นักศึกษาอนุมัติใบลาของตัวเองได้ '
                    '— เท่ากับลบเวลาขาดเรียนของตัวเองทิ้งได้ทุกวัน';
  end if;

  raise notice 'TEST 236 ผ่าน — ยื่นได้ แต่อนุมัติเองไม่ได้ (%)', left(v_msg, 60);
end $$;

reset role;

-- ── TEST 237 ───────────────────────────────────────────────────────
-- อนุมัติแล้วเวลาเรียนเปลี่ยนจริง — ขาดเรียนกลายเป็นลาป่วย
do $$
declare
  v_leave uuid := current_setting('test.leave')::uuid;
  v_absent_before integer; v_leave_after integer; v_applied integer;
begin
  -- ตั้งให้เป็นขาดเรียนไว้ก่อนด้วยสิทธิ์เจ้าของฐานข้อมูล เพื่อให้มีอะไรให้แก้จริง
  insert into attendance_record (class_meeting_id, enrollment_id, status, source)
  select cm.id, e.id, 'absent', 'teacher_web'
    from enrollment e
    join class_meeting cm on cm.class_section_id = e.class_section_id
   where e.student_id = current_setting('test.stu')::uuid
     and e.status = 'enrolled'
     and cm.meets_on = current_setting('test.day1')::date
     and cm.status <> 'cancelled'
  on conflict (class_meeting_id, enrollment_id)
    do update set status = 'absent', source = 'teacher_web';

  select count(*) into v_absent_before
    from attendance_record ar
    join enrollment e on e.id = ar.enrollment_id
    join class_meeting cm on cm.id = ar.class_meeting_id
   where e.student_id = current_setting('test.stu')::uuid
     and cm.meets_on = current_setting('test.day1')::date
     and ar.status = 'absent';

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  select applied_periods into v_applied
    from decide_student_leave(v_leave, true, 'มีใบรับรองแพทย์');

  reset role;

  select count(*) into v_leave_after
    from attendance_record ar
    join enrollment e on e.id = ar.enrollment_id
    join class_meeting cm on cm.id = ar.class_meeting_id
   where e.student_id = current_setting('test.stu')::uuid
     and cm.meets_on = current_setting('test.day1')::date
     and ar.status = 'leave_sick'
     and ar.source = 'guardian_leave';

  if v_absent_before = 0 then
    raise exception 'TEST 237 ล้มเหลว: เตรียมข้อมูลไม่สำเร็จ ไม่มีแถวขาดเรียนให้แก้';
  end if;
  if v_leave_after <> v_absent_before then
    raise exception 'TEST 237 ล้มเหลว: ขาดเรียน % แถว แต่กลายเป็นลาป่วยแค่ % แถว '
                    '— ใบลาที่ไม่มีผลกับเวลาเรียนคือใบลาที่ไม่มีประโยชน์',
                    v_absent_before, v_leave_after;
  end if;
  if v_applied = 0 then
    raise exception 'TEST 237 ล้มเหลว: applied_periods เป็น 0 ทั้งที่แก้ไป % แถว', v_leave_after;
  end if;

  raise notice 'TEST 237 ผ่าน — ขาดเรียน % แถวกลายเป็นลาป่วย รวม % คาบ', v_leave_after, v_applied;
end $$;

reset role;

-- ── TEST 238 ───────────────────────────────────────────────────────
-- ใบลาไม่ทับสถานะที่ครูเช็คว่ามาเรียน
do $$
declare
  v_leave uuid; v_still_present integer; v_skipped integer;
begin
  -- วันที่สองให้ครูเช็คว่ามาเรียนไว้ก่อน แล้วค่อยยื่นใบลาคลุมวันนั้น
  insert into attendance_record (class_meeting_id, enrollment_id, status, source)
  select cm.id, e.id, 'present', 'teacher_web'
    from enrollment e
    join class_meeting cm on cm.class_section_id = e.class_section_id
   where e.student_id = current_setting('test.stu')::uuid
     and e.status = 'enrolled'
     and cm.meets_on = current_setting('test.day2')::date
     and cm.status <> 'cancelled'
  on conflict (class_meeting_id, enrollment_id)
    do update set status = 'present', source = 'teacher_web';

  insert into student_leave
    (institution_id, student_id, kind, from_date, to_date, reason, requested_by)
  values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
          'personal', current_setting('test.day2')::date, current_setting('test.day2')::date,
          'ธุระที่บ้าน', current_setting('test.stuperson')::uuid)
  returning id into v_leave;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  select skipped_present into v_skipped
    from decide_student_leave(v_leave, true, null);

  reset role;

  select count(*) into v_still_present
    from attendance_record ar
    join enrollment e on e.id = ar.enrollment_id
    join class_meeting cm on cm.id = ar.class_meeting_id
   where e.student_id = current_setting('test.stu')::uuid
     and cm.meets_on = current_setting('test.day2')::date
     and ar.status = 'present';

  if v_still_present = 0 then
    raise exception 'TEST 238 ล้มเหลว: ใบลาลบล้างสถานะ "มาเรียน" ที่ครูเช็คไว้ '
                    '— ครูเห็นตัวจริง ใบลาไม่มีสิทธิ์เขียนทับสิ่งที่เกิดขึ้น';
  end if;
  if v_skipped = 0 then
    raise exception 'TEST 238 ล้มเหลว: ไม่ได้รายงานว่ามีคาบที่ข้ามไป '
                    '— เจ้าหน้าที่ต้องรู้ว่าอนุมัติแล้วไม่ครบทุกคาบ';
  end if;

  raise notice 'TEST 238 ผ่าน — คงสถานะมาเรียน % แถว และรายงานว่าข้าม % คาบ',
               v_still_present, v_skipped;
end $$;

reset role;

-- ── TEST 239 ───────────────────────────────────────────────────────
-- ยกเลิกแล้วคืนค่าเดิมตรงแถว — แถวที่เดิมไม่มีต้องถูกลบ ไม่ใช่กลายเป็นขาดเรียน
do $$
declare
  v_leave uuid; v_mtg uuid; v_enr uuid;
  v_exists integer; v_reverted integer;
begin
  -- หาคาบที่ยัง**ไม่มี**แถวเช็คชื่อเลย
  select cm.id, e.id into v_mtg, v_enr
    from enrollment e
    join class_meeting cm on cm.class_section_id = e.class_section_id
    left join attendance_record ar
           on ar.class_meeting_id = cm.id and ar.enrollment_id = e.id
   where e.student_id = current_setting('test.stu')::uuid
     and e.status = 'enrolled'
     and cm.status <> 'cancelled'
     and ar.id is null
   order by cm.meets_on
   limit 1;

  if v_mtg is null then
    raise notice 'TEST 239 ข้าม — ไม่มีคาบที่ยังไม่ได้เช็คชื่อให้ทดสอบ';
    return;
  end if;

  insert into student_leave
    (institution_id, student_id, kind, from_date, to_date, reason, requested_by)
  select current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
         'sick', cm.meets_on, cm.meets_on, 'ทดสอบการยกเลิก',
         current_setting('test.stuperson')::uuid
    from class_meeting cm where cm.id = v_mtg
  returning id into v_leave;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  perform decide_student_leave(v_leave, true, null);

  select count(*) into v_exists from attendance_record
   where class_meeting_id = v_mtg and enrollment_id = v_enr;
  if v_exists <> 1 then
    reset role;
    raise exception 'TEST 239 ล้มเหลว: อนุมัติแล้วไม่ได้สร้างแถวเช็คชื่อให้คาบที่ยังไม่มี';
  end if;

  select reverted into v_reverted from cancel_student_leave(v_leave, 'ยื่นผิดวัน');

  reset role;

  select count(*) into v_exists from attendance_record
   where class_meeting_id = v_mtg and enrollment_id = v_enr;

  if v_exists <> 0 then
    raise exception 'TEST 239 ล้มเหลว: ยกเลิกใบลาแล้วยังเหลือแถวเช็คชื่ออยู่ '
                    '— ถ้าตั้งเป็นขาดเรียนแทน นักศึกษาจะกลายเป็นขาดเรียน'
                    'จากการยกเลิกใบลา ทั้งที่ไม่เคยมีใครบอกว่าขาด';
  end if;

  raise notice 'TEST 239 ผ่าน — คืนค่า % แถว และแถวที่เดิมไม่มีถูกลบทิ้ง', v_reverted;
end $$;

reset role;

-- ── TEST 240 ───────────────────────────────────────────────────────
-- ครูผู้สอนอนุมัติใบลาไม่ได้
--
-- ครูเขียน attendance_record ของกลุ่มตัวเองได้อยู่แล้วตาม 0039 ข้อนี้จึง
-- พิสูจน์ว่า "เขียนเวลาเรียนได้" ไม่เท่ากับ "อนุมัติใบลาได้" — มิฉะนั้น
-- ครูคนหนึ่งจะอนุมัติใบลาที่มีผลกับวิชาของครูคนอื่นทั้งวิทยาลัย
do $$
declare v_leave uuid; v_blocked boolean := false; v_msg text;
begin
  insert into student_leave
    (institution_id, student_id, kind, from_date, to_date, reason, requested_by)
  values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
          'personal', current_setting('test.day1')::date, current_setting('test.day1')::date,
          'ทดสอบสิทธิ์ครู', current_setting('test.stuperson')::uuid)
  returning id into v_leave;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.teacher'), true);
  perform set_config('app.role',           'teacher', true);

  begin
    perform decide_student_leave(v_leave, true, null);
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  reset role;

  if not v_blocked then
    raise exception 'TEST 240 ล้มเหลว: ครูผู้สอนอนุมัติใบลาได้ '
                    '— จะมีผลกับวิชาของครูคนอื่นทั้งวิทยาลัย';
  end if;

  raise notice 'TEST 240 ผ่าน — ครูผู้สอนอนุมัติไม่ได้ (%)', left(v_msg, 60);
end $$;

reset role;

-- ── TEST 241 ───────────────────────────────────────────────────────
-- ครูที่ปรึกษาเห็นใบลาของเด็กในที่ปรึกษาตัวเอง แต่ของคนอื่นไม่เห็น
do $$
declare v_mine integer; v_other integer;
begin
  insert into student_advisor (institution_id, student_id, staff_id)
  values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
          current_setting('test.tstaff')::uuid)
  on conflict do nothing;

  -- 0037 ผูกครูคนแรกเป็นที่ปรึกษาของนักศึกษาคนแรกไว้แล้ว ซึ่งอาจเป็นคนเดียวกับ
  -- `other` ของไฟล์นี้ ถ้าไม่ถอนออกก่อน เทสต์จะล้มด้วยเหตุผลที่ไม่เกี่ยวกับ
  -- สิ่งที่ตั้งใจพิสูจน์ (สถานะที่ค้างจากไฟล์ก่อนหน้า ไม่ใช่นโยบายผิด)
  update student_advisor set ended_on = current_date
   where student_id = current_setting('test.other')::uuid
     and staff_id   = current_setting('test.tstaff')::uuid
     and ended_on is null;

  insert into student_leave
    (institution_id, student_id, kind, from_date, to_date, reason)
  values (current_setting('test.inst')::uuid, current_setting('test.other')::uuid,
          'sick', current_setting('test.day1')::date, current_setting('test.day1')::date,
          'ใบลาของนักศึกษาคนอื่น');

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.teacher'), true);
  perform set_config('app.role',           'teacher', true);

  select count(*) into v_mine  from student_leave
   where student_id = current_setting('test.stu')::uuid;
  select count(*) into v_other from student_leave
   where student_id = current_setting('test.other')::uuid;

  reset role;

  if v_mine = 0 then
    raise exception 'TEST 241 ล้มเหลว: ครูที่ปรึกษาอ่านใบลาของเด็กในที่ปรึกษาตัวเองไม่ได้ '
                    '— นโยบายแคบเกินไปจนใช้งานจริงไม่ได้';
  end if;
  if v_other <> 0 then
    raise exception 'TEST 241 ล้มเหลว: ครูที่ปรึกษาเห็นใบลาของนักศึกษาที่ไม่ได้อยู่ในที่ปรึกษา % ใบ',
                    v_other;
  end if;

  raise notice 'TEST 241 ผ่าน — เห็นของเด็กตัวเอง % ใบ ของคนอื่น % ใบ', v_mine, v_other;
end $$;

reset role;

-- ── TEST 243 ───────────────────────────────────────────────────────
-- งานทะเบียนบันทึกใบลาที่ส่งมาเป็นกระดาษแล้วอนุมัติเองได้
--
-- เส้นทางนี้คือเส้นทางที่ใช้บ่อยที่สุดจริง ๆ และเป็นเส้นทางที่พังตอนแรก
-- เพราะกฎเดิมเขียนว่า "ผู้ยื่นอนุมัติเองไม่ได้" ซึ่งไปกันเจ้าหน้าที่ที่พิมพ์
-- ใบเข้าระบบ ผลคือวิทยาลัยที่มีเจ้าหน้าที่ทะเบียนคนเดียวใช้ฟีเจอร์นี้ไม่ได้เลย
-- **เทสต์ชุดแรกไม่เจอเพราะยื่นด้วยบัญชีนักศึกษาทุกข้อ** — ทางที่เจ้าหน้าที่
-- เดินจริงไม่เคยถูกเดินเลยสักครั้ง (รูปเดียวกับข้อ 6 และข้อ 14)
do $$
declare v_leave uuid; v_status student_leave_status;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  insert into student_leave
    (institution_id, student_id, kind, from_date, to_date, reason, requested_by)
  values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
          'sick', current_setting('test.day1')::date, current_setting('test.day1')::date,
          'ใบลากระดาษที่งานทะเบียนพิมพ์เข้าระบบ', current_setting('test.registrar')::uuid)
  returning id into v_leave;

  select status into v_status from decide_student_leave(v_leave, true, 'ตรวจใบรับรองแพทย์แล้ว');

  reset role;

  if v_status <> 'approved' then
    raise exception 'TEST 243 ล้มเหลว: เจ้าหน้าที่บันทึกใบลาแล้วอนุมัติเองไม่ได้ '
                    '— วิทยาลัยที่มีเจ้าหน้าที่ทะเบียนคนเดียวจะใช้ฟีเจอร์นี้ไม่ได้เลย';
  end if;

  raise notice 'TEST 243 ผ่าน — งานทะเบียนบันทึกใบลากระดาษแล้วอนุมัติเองได้';
end $$;

reset role;

-- ── TEST 242 ───────────────────────────────────────────────────────
-- ใบลาที่ตัดสินไปแล้วแก้รายละเอียดไม่ได้
--
-- ถ้าแก้ได้ ใบที่เจ้าหน้าที่อนุมัติกับใบที่อยู่ในระบบจะเป็นคนละใบกัน
-- แล้วเวลาเรียนที่ถูกปรับไปแล้วจะไม่ตรงกับช่วงวันที่ที่เขียนอยู่บนใบ
do $$
declare v_leave uuid; v_blocked boolean := false; v_msg text;
begin
  select id into v_leave from student_leave
   where student_id = current_setting('test.stu')::uuid and status = 'approved'
   order by created_at limit 1;

  if v_leave is null then
    raise exception 'TEST 242 ล้มเหลว: ไม่พบใบลาที่อนุมัติแล้วจากเทสต์ก่อนหน้า';
  end if;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  begin
    update student_leave set to_date = to_date + 30 where id = v_leave;
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  reset role;

  if not v_blocked then
    raise exception 'TEST 242 ล้มเหลว: แก้ช่วงวันที่ของใบลาที่อนุมัติแล้วได้ '
                    '— เวลาเรียนที่ปรับไปแล้วจะไม่ตรงกับใบ';
  end if;

  raise notice 'TEST 242 ผ่าน — ใบที่ตัดสินแล้วแก้ไม่ได้ (%)', left(v_msg, 60);
end $$;

reset role;

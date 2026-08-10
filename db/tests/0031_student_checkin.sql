-- ═══════════════════════════════════════════════════════════════════
-- 0031_student_checkin.sql
-- ทดสอบว่าการเช็คอินของนักศึกษาไม่ได้เปิดช่องที่ 0039 ปิดไปคืน
--
-- ─── ข้อที่สำคัญที่สุด ───
-- ช่องที่ 0039 ปิดคือ "นักศึกษาเขียนเวลาเรียนของตัวเอง" การเพิ่มปุ่มเช็คอิน
-- ให้นักศึกษาต้องไม่ทำให้ช่องนั้นกลับมาทางอ้อม — คำขอต้องไม่มีผลกับกฎ 80%
-- จนกว่าครูจะยืนยัน และนักศึกษาต้องยืนยันคำขอของตัวเองไม่ได้
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select cm.id            as meeting_id,
       e.id             as enroll_id,
       s.person_id      as student_person,
       st.person_id     as teacher_person,
       cs.institution_id as inst_id
  from class_meeting cm
  join class_section cs on cs.id = cm.class_section_id
  join staff st         on st.id = cs.teacher_id
  join enrollment e     on e.class_section_id = cs.id
  join student s        on s.id = e.student_id
 where cm.status = 'scheduled'
 limit 1 \gset

-- ── TEST 213 ───────────────────────────────────────────────────────
-- นักศึกษาส่งคำขอได้ แต่ยืนยันให้ตัวเองไม่ได้ และไม่มีเวลาเรียนเกิดขึ้น
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'student_person', true) as b,
       set_config('app.role',           'student',         true) as c,
       set_config('test.meeting',       :'meeting_id',     true) as d,
       set_config('test.enroll',        :'enroll_id',      true) as e \gset ctx_

do $$
declare
  v_meeting uuid := current_setting('test.meeting')::uuid;
  v_enroll  uuid := current_setting('test.enroll')::uuid;
  v_row     attendance_checkin;
  v_att     integer;
  v_n       integer;
  v_forced  boolean := false;
begin
  v_row := submit_checkin(v_meeting, v_enroll, 25, 'อุปกรณ์ทดสอบ');

  if v_row.status <> 'pending' then
    raise exception 'TEST 213 ล้มเหลว: คำขอเกิดมาพร้อมสถานะ % ไม่ใช่ pending', v_row.status;
  end if;

  -- ต้องยังไม่มีเวลาเรียนเกิดขึ้นเลย
  select count(*) into v_att from attendance_record
   where class_meeting_id = v_meeting and enrollment_id = v_enroll;
  if v_att > 0 then
    raise exception 'TEST 213 ล้มเหลว: คำขอสร้างเวลาเรียนทันที '
      '(ช่องที่ 0039 ปิดไว้กลับมาทางอ้อม)';
  end if;

  -- ยืนยันให้ตัวเองไม่ได้
  begin
    update attendance_checkin set status = 'accepted' where id = v_row.id;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_forced := true; end if;
  exception when insufficient_privilege then null; end;

  if v_forced then
    raise exception 'TEST 213 ล้มเหลว: นักศึกษายืนยันคำขอของตัวเองได้';
  end if;

  -- ลบคำขอทิ้งก็ไม่ได้ — มิฉะนั้นลบแล้วส่งใหม่จนกว่าครูจะเผลอกด
  delete from attendance_checkin where id = v_row.id;
  get diagnostics v_n = row_count;
  if v_n > 0 then
    raise exception 'TEST 213 ล้มเหลว: นักศึกษาลบคำขอของตัวเองได้';
  end if;

  raise notice 'TEST 213 ผ่าน — ส่งคำขอได้ แต่ยืนยันเองไม่ได้ ลบไม่ได้ และยังไม่มีเวลาเรียนเกิดขึ้น';
end $$;
rollback;

-- ── TEST 214 ───────────────────────────────────────────────────────
-- ครูยืนยันแล้วจึงกลายเป็นเวลาเรียนจริง
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'student_person', true) as b,
       set_config('app.role',           'student',         true) as c,
       set_config('test.meeting',       :'meeting_id',     true) as d,
       set_config('test.enroll',        :'enroll_id',      true) as e,
       set_config('test.teacher',       :'teacher_person', true) as f \gset ctx_

do $$
declare
  v_meeting uuid := current_setting('test.meeting')::uuid;
  v_enroll  uuid := current_setting('test.enroll')::uuid;
  v_row     attendance_checkin;
  v_att     attendance_status;
begin
  v_row := submit_checkin(v_meeting, v_enroll, 12, null);

  -- สลับเป็นครูผู้สอน
  perform set_config('app.actor_id', current_setting('test.teacher'), true);
  perform set_config('app.role', 'teacher', true);

  v_row := decide_checkin(v_row.id, true, 'present', 'เห็นตัวในห้อง');

  if v_row.status <> 'accepted' then
    raise exception 'TEST 214 ล้มเหลว: ยืนยันแล้วสถานะเป็น %', v_row.status;
  end if;

  select ar.status into v_att from attendance_record ar
   where ar.class_meeting_id = v_meeting and ar.enrollment_id = v_enroll;

  if v_att is null then
    raise exception 'TEST 214 ล้มเหลว: ครูยืนยันแล้วแต่ไม่มีเวลาเรียนเกิดขึ้น';
  end if;

  raise notice 'TEST 214 ผ่าน — ครูยืนยันแล้วกลายเป็นเวลาเรียนจริง (%)', v_att;
end $$;
rollback;

-- ── TEST 215 ───────────────────────────────────────────────────────
-- เช็คอินย้อนหลังในคาบที่ปิดไปแล้วไม่ได้
--
-- ถ้าทำได้ นักศึกษาจะไล่ส่งคำขอย้อนหลังทุกคาบที่ขาด แล้วรอให้ครูเผลอกด
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst_id',        true) as a,
       set_config('app.actor_id',       :'student_person', true) as b,
       set_config('app.role',           'student',         true) as c,
       set_config('test.enroll',        :'enroll_id',      true) as d \gset ctx_

do $$
declare
  v_enroll  uuid := current_setting('test.enroll')::uuid;
  v_closed  uuid;
  v_made    boolean := false;
  v_err     text;
begin
  select cm.id into v_closed
    from class_meeting cm
    join enrollment e on e.class_section_id = cm.class_section_id
   where e.id = v_enroll and cm.status <> 'scheduled'
   limit 1;

  if v_closed is null then
    raise notice 'TEST 215 ข้าม — ไม่มีคาบที่ปิดแล้วให้ทดสอบ';
    return;
  end if;

  begin
    perform submit_checkin(v_closed, v_enroll, 10, null);
    v_made := true;
  exception when raise_exception then v_err := sqlerrm; end;

  if v_made then
    raise exception 'TEST 215 ล้มเหลว: ส่งคำขอย้อนหลังในคาบที่ปิดแล้วได้';
  end if;
  if position('ย้อนหลัง' in coalesce(v_err, '')) = 0 then
    raise exception 'TEST 215 ล้มเหลว: ถูกปฏิเสธด้วยเหตุอื่น — %', v_err;
  end if;

  raise notice 'TEST 215 ผ่าน — เช็คอินย้อนหลังไม่ได้';
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบคำขอเช็คอินครบทุกข้อ ════'; end $$;

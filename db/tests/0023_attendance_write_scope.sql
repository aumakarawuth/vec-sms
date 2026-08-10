-- ═══════════════════════════════════════════════════════════════════
-- 0023_attendance_write_scope.sql
-- ทดสอบว่านักศึกษาแก้เวลาเรียนของตัวเองไม่ได้
--
-- ─── ทำไมต้องมีชุดนี้ ───
-- ช่องนี้เคยเปิดอยู่จริงและไม่มีอะไรฟ้องเลย — นักศึกษาเรียก
-- POST /attendance/meetings/:id ด้วย enrollment ของตัวเองแล้วเปลี่ยน
-- "ขาดเรียน" เป็น "มาเรียน" ได้ ทำให้กฎเวลาเรียน 80% ไม่มีผลกับใครที่รู้วิธี
--
-- ต้นเหตุคือ policy ที่มี `using` แต่ไม่มี `with check` ซึ่ง PostgreSQL
-- จะเอา `using` มาใช้เป็น `with check` ให้เอง สิทธิ์อ่านจึงกลายเป็นสิทธิ์เขียน
-- อาการแบบนี้มองไม่เห็นจากการอ่านโค้ด ต้องมีเทสต์ยิงจริงเท่านั้น
--
-- ─── ต้อง set local role app_runtime เสมอ ───
-- run.sh ต่อฐานข้อมูลด้วย postgres ซึ่งเป็น superuser และ superuser
-- **ข้าม RLS ทุกกรณีแม้ตารางจะตั้ง force ไว้** เทสต์ที่ลืมสลับบทบาทจึง
-- ผ่านหรือไม่ผ่านโดยไม่เกี่ยวกับนโยบายเลย (หลักเดียวกับ TEST 10 ใน 0001)
--
-- ─── สามอย่างที่ชุดนี้จับ ───
-- 1. เจ้าของยัง **อ่าน** ของตัวเองได้ (ถ้าปิดหมดคือแก้เกินจนแอปพัง)
-- 2. เจ้าของ **เขียนและลบ** ของตัวเองไม่ได้ ทั้ง update และ delete
--    (delete ต้องทดสอบแยก เพราะ with check ไม่มีผลกับ delete)
-- 3. ครูผู้สอนยังทำงานของตัวเองได้ตามปกติ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── หาเป้าหมายก่อนสลับบทบาท (ยังเป็น superuser จึงเห็นทุกแถว) ────────
select ar.id            as ar_id,
       ar.status::text  as ar_status,
       p.id             as owner_person,
       s.institution_id as inst_id
  from attendance_record ar
  join enrollment e on e.id = ar.enrollment_id
  join student s    on s.id = e.student_id
  join person p     on p.id = s.person_id
 limit 1 \gset

-- ── TEST 183 ───────────────────────────────────────────────────────
-- นักศึกษาอ่านการเช็คชื่อของตัวเองได้ แต่แก้ไม่ได้และลบไม่ได้
begin;
set local role app_runtime;
-- psql ไม่แทนค่าตัวแปรใน dollar-quoted string ของ do block จึงต้องฝากค่า
-- ไว้ใน GUC ชื่อ test.* ที่ระดับบนสุดก่อน แล้วให้ do block อ่านด้วย current_setting
select set_config('app.institution_id', :'inst_id',      true) as a,
       set_config('app.actor_id',       :'owner_person', true) as b,
       set_config('app.role',           'student',       true) as c,
       set_config('test.ar_id',         :'ar_id',        true) as d \gset ctx_

do $$
declare
  v_ar      uuid := current_setting('test.ar_id')::uuid;
  v_seen    attendance_status;
  v_deleted integer;
  v_blocked boolean := false;
begin
  -- 1. ต้องยังอ่านของตัวเองได้ — หน้าจอ "เหลือขาดได้อีกกี่คาบ" พึ่งข้อนี้
  select ar.status into v_seen from attendance_record ar where ar.id = v_ar;
  if v_seen is null then
    raise exception 'TEST 183 ล้มเหลว: นักศึกษาอ่านการเช็คชื่อของตัวเองไม่ได้ '
      '(ปิดเกินไปจนหน้าจอของนักศึกษาใช้ไม่ได้)';
  end if;

  -- 2. แก้เป็น "มาเรียน" ต้องถูกปฏิเสธด้วย RLS ไม่ใช่ถูกกรองเงียบ ๆ
  begin
    update attendance_record set status = 'present' where id = v_ar;
    if found then
      raise exception 'TEST 183 ล้มเหลว: นักศึกษาแก้การเช็คชื่อของตัวเองได้ '
        '(กฎเวลาเรียน 80%% ไม่มีผลกับใครที่รู้วิธีนี้)';
    end if;
  exception
    when insufficient_privilege then
      v_blocked := true;
  end;

  if not v_blocked then
    raise exception 'TEST 183 ล้มเหลว: การแก้ไม่ถูกปฏิเสธด้วย RLS';
  end if;

  -- 3. ลบทิ้งต้องไม่ได้ผลเช่นกัน — แถวที่หายไปเท่ากับไม่เคยขาดเรียน
  --    delete ไม่ผ่าน with check จึงต้องมีนโยบาย for delete แยกอีกตัว
  delete from attendance_record where id = v_ar;
  get diagnostics v_deleted = row_count;
  if v_deleted <> 0 then
    raise exception 'TEST 183 ล้มเหลว: นักศึกษาลบการเช็คชื่อของตัวเองได้ % แถว', v_deleted;
  end if;

  raise notice 'TEST 183 ผ่าน — เจ้าของอ่านได้ (%) แต่แก้ไม่ได้และลบไม่ได้', v_seen;
end $$;
rollback;

-- ── TEST 184 ───────────────────────────────────────────────────────
-- นักศึกษาปิดคาบเรียนเองไม่ได้ แต่ครูผู้สอนยังทำได้
--
-- การปิดคาบเพิ่มตัวหารของกฎ 80% ให้ทุกคนในกลุ่มเรียน นักศึกษาคนเดียวจึง
-- กดเปอร์เซ็นต์ของเพื่อนทั้งห้องให้ต่ำกว่าเกณฑ์ได้ถ้าปล่อยให้ทำ
select cm.id                     as meeting_id,
       p.id                      as stu_person,
       s.institution_id          as m_inst,
       coalesce(st.person_id::text, '') as teacher_person
  from class_meeting cm
  join enrollment e  on e.class_section_id = cm.class_section_id
  join student s     on s.id = e.student_id
  join person p      on p.id = s.person_id
  join class_section cs on cs.id = cm.class_section_id
  left join staff st on st.id = cs.teacher_id
 where cm.status <> 'held'
 limit 1 \gset

begin;
set local role app_runtime;
select set_config('app.institution_id', :'m_inst',         true) as a,
       set_config('app.actor_id',       :'stu_person',     true) as b,
       set_config('app.role',           'student',         true) as c,
       set_config('test.meeting_id',    :'meeting_id',     true) as d,
       set_config('test.teacher_person', :'teacher_person', true) as e \gset ctx2_

do $$
declare
  v_meeting uuid := current_setting('test.meeting_id')::uuid;
  v_teacher text := current_setting('test.teacher_person');
  v_seen    uuid;
  v_blocked boolean := false;
begin
  -- ต้องยังเห็นตารางเรียนของกลุ่มตัวเอง
  select cm.id into v_seen from class_meeting cm where cm.id = v_meeting;
  if v_seen is null then
    raise exception 'TEST 184 ล้มเหลว: นักศึกษาไม่เห็นคาบเรียนของกลุ่มตัวเอง';
  end if;

  begin
    update class_meeting set status = 'held', closed_at = now() where id = v_meeting;
    if found then
      raise exception 'TEST 184 ล้มเหลว: นักศึกษาปิดคาบเรียนเองได้ '
        '(ตัวหารกฎ 80%% ของทั้งห้องขยับตามได้)';
    end if;
  exception
    when insufficient_privilege then
      v_blocked := true;
  end;

  if not v_blocked then
    raise exception 'TEST 184 ล้มเหลว: การปิดคาบไม่ถูกปฏิเสธด้วย RLS';
  end if;

  -- ครูผู้สอนต้องยังทำงานของตัวเองได้ — ถ้าปิดเกินไปคือแอปครูใช้ไม่ได้
  if v_teacher <> '' then
    perform set_config('app.actor_id', v_teacher, true);
    perform set_config('app.role', 'teacher', true);

    update class_meeting set status = 'held', closed_at = now() where id = v_meeting;
    if not found then
      raise exception 'TEST 184 ล้มเหลว: ครูผู้สอนปิดคาบของตัวเองไม่ได้';
    end if;
  end if;

  raise notice 'TEST 184 ผ่าน — นักศึกษาเห็นตารางแต่ปิดคาบไม่ได้ · ครูผู้สอนยังปิดได้';
end $$;
rollback;

-- ── TEST 185 ───────────────────────────────────────────────────────
-- นโยบายทั้งสองตัวต้องมี with check เสมอ และรายงานว่ายังเหลืออีกกี่ตาราง
--
-- ─── ทำไมไม่บังคับทั้งสคีมาเลย ───
-- รูปแบบ using-ไม่มี-with-check มีอยู่อีกหลายสิบตาราง การบังคับทั้งหมด
-- วันนี้แปลว่าเทสต์แดงค้างจนกว่าจะแก้ครบ ซึ่งจบลงด้วยการที่คนปิดเทสต์ทิ้ง
-- จึงบังคับเฉพาะสองตัวที่ปิดไปแล้ว แล้ว raise notice จำนวนที่เหลือไว้ให้เห็น
-- ทุกครั้งที่รัน — ตัวเลขนี้ต้องลดลงเรื่อย ๆ ไม่ใช่เพิ่มขึ้น
do $$
declare
  v_missing text;
  v_rest    integer;
begin
  -- รายชื่อนี้ต้องยาวขึ้นเรื่อย ๆ ทุกครั้งที่ปิดเพิ่ม ห้ามสั้นลง
  -- เวลาเรียน (0039) · คะแนน เกรด ทะเบียน และการเงิน (0041)
  select string_agg(tablename || '.' || policyname, ', ')
    into v_missing
    from pg_policies
   where schemaname = 'public'
     and tablename in ('attendance_record', 'class_meeting',
                       'gradebook_score', 'term_summary', 'student',
                       'student_status_history', 'enrollment',
                       'invoice', 'invoice_line', 'installment')
     and permissive = 'RESTRICTIVE'
     and cmd = 'ALL'
     and with_check is null;

  if v_missing is not null then
    raise exception 'TEST 185 ล้มเหลว: นโยบายที่ปิดไปแล้วกลับมาไม่มี with check — % '
      '(สิทธิ์อ่านจะกลายเป็นสิทธิ์เขียนทันที)', v_missing;
  end if;

  select count(*) into v_rest
    from pg_policies
   where schemaname = 'public'
     and permissive = 'RESTRICTIVE'
     and cmd = 'ALL'
     and with_check is null;

  raise notice 'TEST 185 ผ่าน — สิบตารางที่ปิดแล้วยังปิดอยู่ · ยังเหลืออีก % ตารางที่ยังไม่ปิด', v_rest;
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบขอบเขตการเขียนเวลาเรียนครบทุกข้อ ════'; end $$;

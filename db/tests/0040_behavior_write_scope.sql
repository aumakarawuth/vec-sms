-- ═══════════════════════════════════════════════════════════════════
-- 0040_behavior_write_scope.sql
-- ทดสอบขอบเขตการเขียนคะแนนความประพฤติ (0056)
--
-- ─── ทำไมต้องยิง SQL จริง ───
-- ก่อน 0056 **ไม่มี endpoint ไหนแตะ `behavior_record` เลยสักตัว** การอ่าน
-- โค้ดฝั่ง API จึงให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้ามกับความจริง
-- โดยสิ้นเชิง — ยิงจริงแล้วนักศึกษาให้คะแนนตัวเอง แก้คะแนนที่ถูกหัก และ
-- ลบประวัติทั้งหมดของตัวเองได้ (ทดสอบจริง ลบได้ 3 แถว ยอด 90 → 100)
--
-- และเรื่องนี้หนักกว่าที่เห็น เพราะ 0055 ออก**ใบรับรองความประพฤติ**ที่อ่าน
-- ยอดจากตารางนี้ — คนที่ลบประวัติตัวเองแล้วไปขอใบรับรอง จะได้กระดาษที่เขียนว่า
-- "ไม่ปรากฏประวัติการถูกตัดคะแนน" พร้อมช่องลงนามผู้อำนวยการ
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. นักศึกษาให้คะแนนตัวเองไม่ได้
-- 2. นักศึกษาแก้และลบประวัติของตัวเองไม่ได้
-- 3. นักศึกษาสร้างกฎ "ให้คะแนน 999" ไม่ได้
-- 4. **นักศึกษายังอ่านคะแนนของตัวเองได้** (การปิดต้องไม่ปิดเกิน)
-- 5. ครูผู้สอนบันทึกได้เฉพาะนักศึกษาที่ตัวเองสอน แต่แก้ของที่บันทึกไปแล้วไม่ได้
-- 6. ย้ายบันทึกไปให้นักศึกษาคนอื่นไม่ได้
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select s.id as stu_id, s.institution_id as inst_id, s.person_id as stu_person
  from student s
  join enrollment e on e.student_id = s.id and e.status = 'enrolled'
 group by s.id
 order by s.id limit 1 \gset

select cs.teacher_id as tstaff, st.person_id as teacher_person
  from enrollment e
  join class_section cs on cs.id = e.class_section_id
  join staff st on st.id = cs.teacher_id
 where e.student_id = :'stu_id' and e.status = 'enrolled'
 limit 1 \gset

select s.id as other_stu from student s
 where s.institution_id = :'inst_id' and s.id <> :'stu_id'
   and not exists (select 1 from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                   where e.student_id = s.id and cs.teacher_id = :'tstaff')
 order by s.id limit 1 \gset

select p.id as affairs_person
  from person p join staff st on st.person_id = p.id
  join staff_role sr on sr.staff_id = st.id
 where sr.role in ('student_affairs', 'director', 'admin')
   and st.institution_id = :'inst_id'
 order by p.id limit 1 \gset

select r.id as deduct_rule from behavior_rule r
 where r.direction = 'deduct' and r.institution_id = :'inst_id' limit 1 \gset
select r.id as award_rule from behavior_rule r
 where r.direction = 'award' and r.institution_id = :'inst_id' limit 1 \gset

select set_config('t.stu',     :'stu_id',         false) a,
       set_config('t.inst',    :'inst_id',        false) b,
       set_config('t.person',  :'stu_person',     false) c,
       set_config('t.teacher', :'teacher_person', false) d,
       set_config('t.other',   :'other_stu',      false) e,
       set_config('t.affairs', :'affairs_person', false) f,
       set_config('t.deduct',  :'deduct_rule',    false) g,
       set_config('t.award',   :'award_rule',     false) h \gset

-- มีประวัติถูกหักไว้ให้ลองลบ
insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_by)
values (current_setting('t.stu')::uuid, current_setting('t.deduct')::uuid,
        current_date, 10, 'ข้อมูลสำหรับทดสอบ', current_setting('t.affairs')::uuid);

-- ── TEST 251 ───────────────────────────────────────────────────────
-- นักศึกษาให้คะแนนตัวเอง แก้ และลบประวัติไม่ได้ — แต่ยังอ่านได้
do $$
declare
  v_ins boolean := false; v_upd integer := 0; v_del integer := 0;
  v_before numeric; v_after numeric; v_seen integer;
begin
  select balance into v_before from v_behavior_balance
   where student_id = current_setting('t.stu')::uuid;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.person'), true);
  perform set_config('app.role',           'student', true);

  select count(*) into v_seen from behavior_record
   where student_id = current_setting('t.stu')::uuid;

  begin
    insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_by)
    values (current_setting('t.stu')::uuid, current_setting('t.award')::uuid,
            current_date, 50, 'ให้คะแนนตัวเอง', current_setting('t.person')::uuid);
    v_ins := true;
  exception when others then v_ins := false;
  end;

  begin
    update behavior_record set points = 0
     where student_id = current_setting('t.stu')::uuid;
    get diagnostics v_upd = row_count;
  exception when others then v_upd := 0;
  end;

  begin
    delete from behavior_record where student_id = current_setting('t.stu')::uuid;
    get diagnostics v_del = row_count;
  exception when others then v_del := 0;
  end;

  reset role;

  select balance into v_after from v_behavior_balance
   where student_id = current_setting('t.stu')::uuid;

  if v_ins then
    raise exception 'TEST 251 ล้มเหลว: นักศึกษาให้คะแนนความดีตัวเองได้';
  end if;
  if v_upd > 0 then
    raise exception 'TEST 251 ล้มเหลว: นักศึกษาแก้คะแนนที่ถูกหักได้ % แถว', v_upd;
  end if;
  if v_del > 0 then
    raise exception 'TEST 251 ล้มเหลว: นักศึกษาลบประวัติการถูกหักคะแนนของตัวเองได้ % แถว '
                    '— แล้วไปขอใบรับรองความประพฤติที่เขียนว่าไม่มีประวัติ', v_del;
  end if;
  if v_before is distinct from v_after then
    raise exception 'TEST 251 ล้มเหลว: ยอดคะแนนเปลี่ยนจาก % เป็น %', v_before, v_after;
  end if;
  if v_seen = 0 then
    raise exception 'TEST 251 ล้มเหลว: นักศึกษาอ่านคะแนนของตัวเองไม่ได้ '
                    '— การปิดช่องเขียนต้องไม่ปิดการอ่านไปด้วย '
                    '(นโยบาย restrictive แบบ for all กิน select)';
  end if;

  raise notice 'TEST 251 ผ่าน — เขียนไม่ได้ทั้งสามทาง · ยอดคงที่ที่ % · แต่ยังอ่านของตัวเองได้ % แถว',
               v_after, v_seen;
end $$;

reset role;

-- ── TEST 252 ───────────────────────────────────────────────────────
-- นักศึกษาสร้างกฎให้คะแนนตัวเองไม่ได้
do $$
declare v_ok boolean := false; v_msg text;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.person'), true);
  perform set_config('app.role',           'student', true);

  begin
    insert into behavior_rule (institution_id, code, name_th, direction, points)
    values (current_setting('t.inst')::uuid, 'TESTHACK', 'กฎที่นักศึกษาสร้างเอง', 'award', 999);
    v_ok := true;
  exception when others then v_msg := sqlerrm;
  end;

  reset role;

  if v_ok then
    raise exception 'TEST 252 ล้มเหลว: นักศึกษาสร้างกฎ "ให้คะแนน 999" ได้ '
                    '— ปิดทางเขียนบันทึกอย่างเดียวไม่พอ ถ้ายังสร้างกฎเองได้';
  end if;

  raise notice 'TEST 252 ผ่าน — สร้างกฎเองไม่ได้ (%)', left(v_msg, 55);
end $$;

reset role;

-- ── TEST 253 ───────────────────────────────────────────────────────
-- ครูผู้สอนบันทึกได้เฉพาะนักศึกษาที่ตัวเองสอน และแก้ของเดิมไม่ได้
do $$
declare
  v_mine boolean := false; v_other boolean := false;
  v_upd integer := 0; v_id uuid;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.teacher'), true);
  perform set_config('app.role',           'teacher', true);

  begin
    insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_by)
    values (current_setting('t.stu')::uuid, current_setting('t.deduct')::uuid,
            current_date, 5, 'ครูผู้สอนบันทึก', current_setting('t.teacher')::uuid)
    returning id into v_id;
    v_mine := true;
  exception when others then
    raise notice '  บันทึกนักศึกษาที่สอนอยู่ล้มเหลว: %', sqlerrm;
  end;

  begin
    insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_by)
    values (current_setting('t.other')::uuid, current_setting('t.deduct')::uuid,
            current_date, 5, 'ครูบันทึกคนที่ไม่ได้สอน', current_setting('t.teacher')::uuid);
    v_other := true;
  exception when others then v_other := false;
  end;

  -- แก้สิ่งที่ตัวเองเพิ่งบันทึกไม่ได้ — การแก้เป็นการเปลี่ยนหลักฐาน
  if v_id is not null then
    begin
      update behavior_record set points = 1 where id = v_id;
      get diagnostics v_upd = row_count;
    exception when others then v_upd := 0;
    end;
  end if;

  reset role;

  if not v_mine then
    raise exception 'TEST 253 ล้มเหลว: ครูผู้สอนบันทึกพฤติกรรมของนักศึกษาที่ตัวเองสอนไม่ได้ '
                    '— ถ้าเปิดให้เฉพาะงานปกครอง จะไม่มีใครบันทึกเลย';
  end if;
  if v_other then
    raise exception 'TEST 253 ล้มเหลว: ครูหักคะแนนนักศึกษาที่ตัวเองไม่เคยสอนได้';
  end if;
  if v_upd > 0 then
    raise exception 'TEST 253 ล้มเหลว: ครูแก้บันทึกที่ตัวเองเขียนไปแล้วได้ '
                    '— การแก้หลักฐานเป็นคนละเรื่องกับการบันทึก';
  end if;

  raise notice 'TEST 253 ผ่าน — บันทึกคนที่สอนได้ · คนที่ไม่ได้สอนไม่ได้ · แก้ของเดิมไม่ได้';
end $$;

reset role;

-- ── TEST 254 ───────────────────────────────────────────────────────
-- ย้ายบันทึกไปให้นักศึกษาคนอื่นไม่ได้ แม้เป็นงานปกครอง
--
-- นโยบาย RLS เทียบได้แค่ "แถวนี้แตะได้ไหม" ไม่ได้เทียบว่าเปลี่ยนจากอะไร
-- เป็นอะไร ข้อนี้จึงพิสูจน์ trigger ไม่ใช่นโยบาย
do $$
declare v_id uuid; v_moved boolean := false; v_msg text;
begin
  select id into v_id from behavior_record
   where student_id = current_setting('t.stu')::uuid limit 1;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.affairs'), true);
  perform set_config('app.role',           'student_affairs', true);

  begin
    update behavior_record set student_id = current_setting('t.other')::uuid
     where id = v_id;
    v_moved := true;
  exception when others then v_msg := sqlerrm;
  end;

  reset role;

  if v_moved then
    raise exception 'TEST 254 ล้มเหลว: ย้ายบันทึกพฤติกรรมไปให้นักศึกษาคนอื่นได้ '
                    '— เป็นการเขียนประวัติใหม่โดยที่วันที่ยังเป็นของเดิม';
  end if;

  raise notice 'TEST 254 ผ่าน — ย้ายบันทึกข้ามคนไม่ได้ (%)', left(v_msg, 55);
end $$;

reset role;

-- ── TEST 255 ───────────────────────────────────────────────────────
-- ผู้บันทึกต้องเป็นคนที่กดจริง
do $$
declare v_ok boolean := false; v_msg text;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.affairs'), true);
  perform set_config('app.role',           'student_affairs', true);

  begin
    -- บันทึกในนามครูคนอื่น
    insert into behavior_record (student_id, rule_id, occurred_on, points, detail, recorded_by)
    values (current_setting('t.stu')::uuid, current_setting('t.deduct')::uuid,
            current_date, 5, 'บันทึกในนามคนอื่น', current_setting('t.teacher')::uuid);
    v_ok := true;
  exception when others then v_msg := sqlerrm;
  end;

  reset role;

  if v_ok then
    raise exception 'TEST 255 ล้มเหลว: บันทึกในนามคนอื่นได้ — หลักฐานจะชี้ผิดคน';
  end if;

  raise notice 'TEST 255 ผ่าน — ผู้บันทึกต้องเป็นคนที่กดจริง (%)', left(v_msg, 55);
end $$;

reset role;

-- ── TEST 256 ───────────────────────────────────────────────────────
-- v_behavior_status บอกระดับเตือนตาม behavior_policy ไม่ใช่ตัวเลขเปล่า
do $$
declare v_band text; v_balance numeric; v_warn smallint;
begin
  select band, balance, warn_below into v_band, v_balance, v_warn
    from v_behavior_status where student_id = current_setting('t.stu')::uuid;

  if v_band is null then
    raise exception 'TEST 256 ล้มเหลว: v_behavior_status ไม่คืนระดับเตือน';
  end if;
  if v_balance < v_warn and v_band = 'ok' then
    raise exception 'TEST 256 ล้มเหลว: คะแนน % ต่ำกว่าเกณฑ์เตือน % แต่ยังบอกว่าปกติ',
                    v_balance, v_warn;
  end if;

  raise notice 'TEST 256 ผ่าน — คะแนน % เกณฑ์เตือน % ระดับ %', v_balance, v_warn, v_band;
end $$;

reset role;

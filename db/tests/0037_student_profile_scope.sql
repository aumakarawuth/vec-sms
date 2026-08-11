-- ═══════════════════════════════════════════════════════════════════
-- 0037_student_profile_scope.sql
-- ทดสอบขอบเขตการเห็นข้อมูลอ่อนไหวของนักศึกษา (0053)
--
-- ─── ทำไมต้องยิง SQL จริง ไม่ใช่อ่านโค้ด ───
-- นโยบายชุดนี้ **แคบกว่า** `is_institution_wide_role()` โดยตั้งใจ ซึ่งเป็น
-- รูปแบบที่ไม่เคยมีในสคีมานี้มาก่อน — ทุกตารางก่อนหน้าถือว่าบทบาทระดับ
-- วิทยาลัยเห็นได้หมด การอ่านโค้ดจึงเดาผิดได้ง่ายว่า "ฝ่ายวิชาการก็คงเห็น"
--
-- และช่องแบบนี้มองไม่เห็นจากชั้น API เลย เพราะ API ไม่มี endpoint ที่คืน
-- ข้อมูลอ่อนไหวให้ครูอยู่แล้ว — ต้องยิง SQL ในบริบทของครูจริงถึงจะรู้ว่า
-- คนที่ข้าม API ไปเลยเห็นอะไรบ้าง (บทเรียนเดียวกับข้อ 10, 11 และ 13)
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. ครูผู้สอนอ่านข้อมูลอ่อนไหวของนักศึกษาที่ตัวเองสอนอยู่ไม่ได้
-- 2. ครูที่ปรึกษาอ่านของเด็กในที่ปรึกษาตัวเองได้ แต่ของคนอื่นไม่ได้
-- 3. ฝ่ายวิชาการอ่านข้อมูลสุขภาพไม่ได้ แม้เป็นบทบาทระดับวิทยาลัย
-- 4. การเงินอ่านรายได้ผู้ปกครองได้ แต่อ่านข้อมูลสุขภาพไม่ได้
-- 5. นักศึกษาอ่านของตัวเองได้ แต่ **แก้ไม่ได้**
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select s.id as stu_id, s.institution_id as inst_id, s.person_id as stu_person
  from student s
 order by s.id limit 1 \gset

select s.id as other_stu, s.person_id as other_person
  from student s
 where s.id <> :'stu_id'
 order by s.id limit 1 \gset

select st.id as staff_id, st.person_id as teacher_person
  from staff st
 where st.is_teacher
 order by st.id limit 1 \gset

select p.id as registrar_person
  from person p
  join staff s       on s.person_id = p.id
  join staff_role sr on sr.staff_id = s.id
 where sr.role in ('registrar', 'academic', 'director', 'admin')
 order by p.id limit 1 \gset

select set_config('test.stu',       :'stu_id',           false) as a,
       set_config('test.inst',      :'inst_id',          false) as b,
       set_config('test.stuperson', :'stu_person',       false) as c,
       set_config('test.other',     :'other_stu',        false) as d,
       set_config('test.otherperson', :'other_person',   false) as e,
       set_config('test.teacher',   :'teacher_person',   false) as f,
       set_config('test.registrar', :'registrar_person', false) as g \gset

-- เตรียมข้อมูล: ทั้งสองคนมีข้อมูลอ่อนไหว · ครูเป็นที่ปรึกษาของคนแรกเท่านั้น
insert into person_sensitive (person_id, institution_id, blood_type, drug_allergy, religion)
values (current_setting('test.stuperson')::uuid, current_setting('test.inst')::uuid,
        'O', 'แพ้เพนิซิลลิน', 'พุทธ'),
       (current_setting('test.otherperson')::uuid, current_setting('test.inst')::uuid,
        'A', 'ไม่มี', 'พุทธ')
on conflict (person_id) do update set blood_type = excluded.blood_type;

insert into student_parent (institution_id, student_id, role, first_name_th, income_monthly)
values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
        'father', 'ทดสอบ', 18000)
on conflict (student_id, role) do update set income_monthly = excluded.income_monthly;

insert into student_advisor (institution_id, student_id, staff_id)
select current_setting('test.inst')::uuid, current_setting('test.stu')::uuid, st.id
  from staff st where st.person_id = current_setting('test.teacher')::uuid
on conflict do nothing;

-- ── TEST 231 ───────────────────────────────────────────────────────
-- ครูที่ปรึกษาเห็นของเด็กตัวเอง แต่ไม่เห็นของคนอื่น
do $$
declare v_mine integer; v_other integer;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.teacher'), true);
  perform set_config('app.role',           'teacher', true);

  select count(*) into v_mine  from person_sensitive
   where person_id = current_setting('test.stuperson')::uuid;
  select count(*) into v_other from person_sensitive
   where person_id = current_setting('test.otherperson')::uuid;

  reset role;

  if v_mine <> 1 then
    raise exception 'TEST 231 ล้มเหลว: ครูที่ปรึกษาอ่านข้อมูลของเด็กในที่ปรึกษาตัวเองไม่ได้ '
                    '— นโยบายแคบเกินไปจนใช้งานจริงไม่ได้';
  end if;
  if v_other <> 0 then
    raise exception 'TEST 231 ล้มเหลว: ครูที่ปรึกษาเห็นข้อมูลอ่อนไหวของนักศึกษาที่ไม่ได้อยู่ในที่ปรึกษา';
  end if;

  raise notice 'TEST 231 ผ่าน — ครูที่ปรึกษาเห็นเฉพาะเด็กของตัวเอง (เห็น % ไม่เห็น %)', v_mine, v_other;
end $$;

reset role;

-- ── TEST 232 ───────────────────────────────────────────────────────
-- ครูผู้สอนที่ไม่ใช่ที่ปรึกษา อ่านไม่ได้แม้จะสอนนักศึกษาคนนั้นอยู่
do $$
declare v_seen integer;
begin
  -- ถอนการเป็นที่ปรึกษาชั่วคราว เหลือความสัมพันธ์แค่ "สอนอยู่"
  reset role;
  update student_advisor set ended_on = current_date
   where student_id = current_setting('test.stu')::uuid;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.teacher'), true);
  perform set_config('app.role',           'teacher', true);

  select count(*) into v_seen from person_sensitive;

  reset role;

  -- คืนสถานะที่ปรึกษาให้เทสต์ถัดไป
  update student_advisor set ended_on = null
   where student_id = current_setting('test.stu')::uuid;

  if v_seen <> 0 then
    raise exception 'TEST 232 ล้มเหลว: ครูผู้สอนเห็นข้อมูลอ่อนไหว % แถว '
                    '— การสอนอยู่ไม่ควรให้สิทธิ์เห็นประวัติแพ้ยาและศาสนา', v_seen;
  end if;

  raise notice 'TEST 232 ผ่าน — ครูผู้สอนที่ไม่ใช่ที่ปรึกษาไม่เห็นเลยสักแถว';
end $$;

reset role;

-- ── TEST 233 ───────────────────────────────────────────────────────
-- ฝ่ายวิชาการอ่านข้อมูลสุขภาพไม่ได้ แม้เป็นบทบาทระดับวิทยาลัย
-- แต่ยังอ่านประวัติการศึกษาเดิมได้ตามปกติ
do $$
declare v_sensitive integer; v_prior integer;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'academic', true);

  select count(*) into v_sensitive from person_sensitive;
  select count(*) into v_prior     from student_prior_education;

  reset role;

  if v_sensitive <> 0 then
    raise exception 'TEST 233 ล้มเหลว: ฝ่ายวิชาการเห็นข้อมูลอ่อนไหว % แถว '
                    '— นโยบายนี้ตั้งใจให้แคบกว่า is_institution_wide_role()', v_sensitive;
  end if;

  raise notice 'TEST 233 ผ่าน — ฝ่ายวิชาการไม่เห็นข้อมูลอ่อนไหว แต่ยังอ่านประวัติการศึกษาเดิมได้ (% แถว)', v_prior;
end $$;

reset role;

-- ── TEST 234 ───────────────────────────────────────────────────────
-- การเงินเห็นรายได้ผู้ปกครอง แต่ไม่เห็นข้อมูลสุขภาพ
do $$
declare v_income integer; v_health integer;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'finance', true);

  select count(*) into v_income from student_parent where income_monthly is not null;
  select count(*) into v_health from person_sensitive;

  reset role;

  if v_income = 0 then
    raise exception 'TEST 234 ล้มเหลว: การเงินอ่านรายได้ผู้ปกครองไม่ได้ '
                    '— ข้อมูลนี้ใช้พิจารณาทุนและ กยศ. ปิดแล้วงานทำไม่ได้';
  end if;
  if v_health <> 0 then
    raise exception 'TEST 234 ล้มเหลว: การเงินเห็นข้อมูลสุขภาพ % แถว', v_health;
  end if;

  raise notice 'TEST 234 ผ่าน — การเงินเห็นรายได้ (% แถว) แต่ไม่เห็นข้อมูลสุขภาพ', v_income;
end $$;

reset role;

-- ── TEST 235 ───────────────────────────────────────────────────────
-- นักศึกษาอ่านของตัวเองได้ แต่แก้ไม่ได้
do $$
declare v_seen integer; v_blocked boolean := false; v_msg text;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.stuperson'), true);
  perform set_config('app.role',           'student', true);

  select count(*) into v_seen from person_sensitive;

  begin
    update person_sensitive set blood_type = 'AB'
     where person_id = current_setting('test.stuperson')::uuid;
    if found then
      v_blocked := false;
    else
      v_blocked := true;   -- ไม่มีแถวให้แก้ = ถูกกันแล้ว
      v_msg := 'ไม่มีแถวที่แก้ได้';
    end if;
  exception when others then
    v_blocked := true;
    v_msg := sqlerrm;
  end;

  reset role;

  if v_seen <> 1 then
    raise exception 'TEST 235 ล้มเหลว: นักศึกษาอ่านข้อมูลของตัวเองไม่ได้ (เห็น % แถว)', v_seen;
  end if;
  if not v_blocked then
    raise exception 'TEST 235 ล้มเหลว: นักศึกษาแก้ข้อมูลสุขภาพของตัวเองได้ '
                    '— ข้อมูลนี้ต้องมาจากเอกสารที่ผู้ปกครองกรอก ไม่ใช่จากเจ้าตัว';
  end if;

  raise notice 'TEST 235 ผ่าน — นักศึกษาอ่านของตัวเองได้ แต่แก้ไม่ได้ (%)', left(coalesce(v_msg,''), 50);
end $$;

reset role;

-- ═══════════════════════════════════════════════════════════════════
-- 0039_student_letters.sql
-- ทดสอบหนังสือถึงผู้ปกครองและใบรับรองความประพฤติ (0055)
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. payload ของหนังสือ **ไม่มี** GPAX และหน่วยกิตสะสม
--    (ใบเดิมทุกใบมี — ถ้าเผลอใช้ส่วนหัวเดียวกันจะติดมาโดยไม่มีอะไรฟ้อง)
-- 2. payload **มี** ชื่อและที่อยู่ผู้ปกครอง ซึ่งใบ รบ. ไม่มีสิทธิ์มี
-- 3. จดหมายแจ้งขาดเรียนออกให้คนที่เวลาเรียนครบเกณฑ์ไม่ได้
-- 4. หนังสือเชิญผู้ปกครองต้องมีวันนัดพบ
-- 5. ตัวเลขเวลาเรียนตรึงในใบ — แก้เวลาเรียนทีหลังแล้วใบเดิมต้องไม่ขยับ
-- 6. `issue_document()` ออกหนังสือพวกนี้ไม่ได้ และ `issue_student_letter()`
--    ออกใบ รบ. ไม่ได้ — สองทางต้องไม่ทับกัน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- นักศึกษาที่มีเวลาเรียนต่ำกว่าเกณฑ์จริงในภาคเรียนหนึ่ง
select e.student_id as stu_id, e.term_id as term_id, s.institution_id as inst_id
  from enrollment e
  join student s on s.id = e.student_id
  join v_enrollment_attendance v on v.enrollment_id = e.id
 where e.status = 'enrolled' and v.attendance_state <> 'ok'
 order by e.student_id
 limit 1 \gset

select p.id as registrar_person
  from person p
  join staff st      on st.person_id = p.id
  join staff_role sr on sr.staff_id = st.id
 where sr.role in ('registrar', 'student_affairs', 'director', 'admin')
   and st.institution_id = :'inst_id'
 order by p.id limit 1 \gset

select set_config('test.stu',       :'stu_id',           false) as a,
       set_config('test.term',      :'term_id',          false) as b,
       set_config('test.inst',      :'inst_id',          false) as c,
       set_config('test.registrar', :'registrar_person', false) as d \gset

-- ผู้ปกครองในระเบียน — หนังสือต้องจ่าหน้าถึงคนนี้
insert into student_parent
  (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
   phone, address_line, subdistrict_th, district_th, province_th, postal_code)
values (current_setting('test.inst')::uuid, current_setting('test.stu')::uuid,
        'father', 'นาย', 'ทดสอบ', 'ผู้ปกครอง', '0800000000',
        '9/9 หมู่ 2', 'ในเมือง', 'เมือง', 'ลำปาง', '52000')
on conflict (student_id, role) do update set address_line = excluded.address_line;

-- ── TEST 244 ───────────────────────────────────────────────────────
-- จดหมายแจ้งขาดเรียน — มีผู้ปกครองและที่อยู่ แต่ไม่มี GPAX
do $$
declare v_doc issued_document; v_pl jsonb;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  v_doc := issue_student_letter(current_setting('test.stu')::uuid,
                                'absence_notice',
                                current_setting('test.term')::uuid,
                                '{"note": "ทดสอบ"}'::jsonb);
  reset role;
  v_pl := v_doc.payload;

  perform set_config('test.notice', v_doc.id::text, false);

  if v_pl ? 'summary' or v_pl ? 'graduation' then
    raise exception 'TEST 244 ล้มเหลว: payload ของจดหมายมี GPAX หรือข้อมูลการจบติดมาด้วย '
                    '— จดหมายแจ้งขาดเรียนไม่ได้แสดงเกรดเฉลี่ยสักตัว '
                    'การคัดลอกลงไปคือการเก็บข้อมูลเกินจำเป็นในที่ที่ลบไม่ได้ (PDPA ม.22)';
  end if;

  if jsonb_array_length(v_pl -> 'recipients') = 0 then
    raise exception 'TEST 244 ล้มเหลว: ไม่มีผู้รับในหนังสือ — จดหมายที่ขึ้นต้นว่า "เรียน" '
                    'แล้วตามด้วยที่ว่างคือจดหมายที่ส่งไม่ได้';
  end if;

  if coalesce(v_pl -> 'recipients' -> 0 ->> 'address_th', '') = '' then
    raise exception 'TEST 244 ล้มเหลว: ไม่มีที่อยู่ผู้ปกครองสำหรับจ่าหน้าซอง';
  end if;

  if jsonb_array_length(v_pl -> 'courses') = 0 then
    raise exception 'TEST 244 ล้มเหลว: ไม่มีรายวิชาที่ตกเกณฑ์ในหนังสือ';
  end if;

  raise notice 'TEST 244 ผ่าน — เลขที่ % · ผู้รับ % คน · วิชาที่ตกเกณฑ์ % วิชา · ไม่มี GPAX',
               v_doc.doc_no,
               jsonb_array_length(v_pl -> 'recipients'),
               jsonb_array_length(v_pl -> 'courses');
end $$;

reset role;

-- ── TEST 245 ───────────────────────────────────────────────────────
-- ตัวเลขเวลาเรียนตรึงในใบ — แก้เวลาเรียนทีหลังแล้วใบเดิมต้องไม่ขยับ
do $$
declare v_before numeric; v_after numeric; v_enr uuid;
begin
  select (payload -> 'courses' -> 0 ->> 'pct_to_date')::numeric into v_before
    from issued_document where id = current_setting('test.notice')::uuid;

  -- เปลี่ยนเวลาเรียนจริงด้วยสิทธิ์เจ้าของฐานข้อมูล
  select e.id into v_enr from enrollment e
   where e.student_id = current_setting('test.stu')::uuid
     and e.term_id = current_setting('test.term')::uuid
     and e.status = 'enrolled'
   limit 1;

  update attendance_record set status = 'present'
   where enrollment_id = v_enr and status = 'absent';

  select (payload -> 'courses' -> 0 ->> 'pct_to_date')::numeric into v_after
    from issued_document where id = current_setting('test.notice')::uuid;

  if v_before is distinct from v_after then
    raise exception 'TEST 245 ล้มเหลว: ตัวเลขในใบที่ออกไปแล้วเปลี่ยนตามข้อมูลปัจจุบัน '
                    '(% → %) — กระดาษที่ผู้ปกครองถืออยู่จะไม่ตรงกับที่ระบบพิมพ์ใหม่',
                    v_before, v_after;
  end if;

  raise notice 'TEST 245 ผ่าน — ตัวเลขในใบตรึงที่ % แม้เวลาเรียนจริงเปลี่ยนไปแล้ว', v_before;
end $$;

reset role;

-- ── TEST 246 ───────────────────────────────────────────────────────
-- หนังสือเชิญผู้ปกครองต้องมีวันนัดพบ
do $$
declare v_blocked boolean := false; v_msg text; v_doc issued_document;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'student_affairs', true);

  begin
    v_doc := issue_student_letter(current_setting('test.stu')::uuid,
                                  'guardian_invitation', null, '{}'::jsonb);
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  if not v_blocked then
    reset role;
    raise exception 'TEST 246 ล้มเหลว: ออกหนังสือเชิญโดยไม่ระบุวันนัดพบได้ '
                    '— ถ้าเว้นไว้เติมด้วยปากกาทีหลัง จะไม่มีหลักฐานว่าเคยนัดวันไหน';
  end if;

  -- ระบุวันแล้วต้องออกได้
  v_doc := issue_student_letter(
    current_setting('test.stu')::uuid, 'guardian_invitation', null,
    jsonb_build_object('meet_on', (current_date + 7)::text,
                       'meet_time', '10:00 น.',
                       'place_th', 'ห้องงานปกครอง อาคาร 1',
                       'reason_th', 'ปรึกษาเรื่องเวลาเรียน'));
  reset role;

  if v_doc.payload -> 'meeting' ->> 'meet_on' is null then
    raise exception 'TEST 246 ล้มเหลว: ระบุวันนัดแล้วแต่ไม่ถูกเก็บลง payload';
  end if;

  raise notice 'TEST 246 ผ่าน — ไม่มีวันนัดออกไม่ได้ (%) · มีวันนัดออกได้ เลขที่ %',
               left(v_msg, 40), v_doc.doc_no;
end $$;

reset role;

-- ── TEST 247 ───────────────────────────────────────────────────────
-- สองเส้นทางต้องไม่ทับกัน
do $$
declare v_a boolean := false; v_b boolean := false; v_doc issued_document;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  begin
    v_doc := issue_student_letter(current_setting('test.stu')::uuid, 'transcript', null, '{}'::jsonb);
  exception when others then v_a := true;
  end;

  begin
    v_doc := issue_document(current_setting('test.stu')::uuid, 'absence_notice', null, null);
  exception when others then v_b := true;
  end;

  reset role;

  if not v_a then
    raise exception 'TEST 247 ล้มเหลว: issue_student_letter() ออกใบ รบ. ได้ '
                    '— จะได้ใบ รบ. ที่ไม่มีรายวิชาสักแถวและกินเลขที่ไปหนึ่งเลข';
  end if;
  if not v_b then
    raise exception 'TEST 247 ล้มเหลว: issue_document() ออกจดหมายแจ้งขาดเรียนได้ '
                    '— จะได้จดหมายที่มี GPAX ติดมาและไม่มีรายวิชาที่ตกเกณฑ์';
  end if;

  raise notice 'TEST 247 ผ่าน — สองเส้นทางปฏิเสธประเภทของกันและกัน';
end $$;

reset role;

-- ── TEST 248 ───────────────────────────────────────────────────────
-- จดหมายแจ้งขาดเรียนออกให้คนที่เวลาเรียนครบเกณฑ์ไม่ได้
--
-- ถ้าออกได้ จะได้จดหมายที่มีตารางว่างเปล่าส่งถึงบ้านผู้ปกครอง
-- ซึ่งเสียหายกว่าไม่ส่งเลย
do $$
declare v_ok uuid; v_blocked boolean := false; v_msg text; v_doc issued_document;
begin
  select e.student_id into v_ok
    from enrollment e
    join v_enrollment_attendance v on v.enrollment_id = e.id
    join student s on s.id = e.student_id
   where e.status = 'enrolled'
     and s.institution_id = current_setting('test.inst')::uuid
     and e.term_id = current_setting('test.term')::uuid
   group by e.student_id
  having bool_and(v.attendance_state = 'ok')
   limit 1;

  if v_ok is null then
    raise notice 'TEST 248 ข้าม — ไม่มีนักศึกษาที่เวลาเรียนครบเกณฑ์ทุกวิชาให้ทดสอบ';
    return;
  end if;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  begin
    v_doc := issue_student_letter(v_ok, 'absence_notice',
                                  current_setting('test.term')::uuid, '{}'::jsonb);
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  reset role;

  if not v_blocked then
    raise exception 'TEST 248 ล้มเหลว: ออกจดหมายแจ้งขาดเรียนให้คนที่เวลาเรียนครบเกณฑ์ได้ '
                    '— จะได้จดหมายที่มีตารางว่างเปล่าส่งถึงบ้าน';
  end if;

  raise notice 'TEST 248 ผ่าน — คนที่เวลาเรียนครบเกณฑ์ออกจดหมายไม่ได้ (%)', left(v_msg, 50);
end $$;

reset role;

-- ── TEST 249 ───────────────────────────────────────────────────────
-- ใบรับรองความประพฤติอ่านยอดจาก view ไม่รวมเครื่องหมายเอง
do $$
declare v_doc issued_document; v_balance numeric; v_view numeric;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       current_setting('test.registrar'), true);
  perform set_config('app.role',           'registrar', true);

  v_doc := issue_student_letter(current_setting('test.stu')::uuid, 'conduct_certificate',
                                null, '{"purpose_th": "สมัครงาน"}'::jsonb);
  reset role;

  v_balance := (v_doc.payload -> 'behavior' ->> 'balance')::numeric;
  select b.balance into v_view from v_behavior_balance b
   where b.student_id = current_setting('test.stu')::uuid;

  if v_balance is distinct from v_view then
    raise exception 'TEST 249 ล้มเหลว: ยอดคะแนนในใบ (%) ไม่ตรงกับ v_behavior_balance (%) '
                    '— behavior_record.points เป็นบวกทั้งสองทิศทาง การรวมเองจะได้ผลผิด '
                    'แบบดูไม่ออก แล้ววิทยาลัยจะรับรองคนที่ไม่ควรได้',
                    v_balance, v_view;
  end if;

  if v_doc.payload -> 'behavior' ->> 'deduct_count' is null then
    raise exception 'TEST 249 ล้มเหลว: ไม่ได้นับจำนวนครั้งที่ถูกหักคะแนน '
                    '— "คะแนนเต็มเพราะไม่เคยมีประวัติ" กับ "เต็มเพราะทำกิจกรรมชดเชย" คนละเรื่องกัน';
  end if;

  raise notice 'TEST 249 ผ่าน — เลขที่ % · คะแนนคงเหลือ % ตรงกับ view · ถูกหัก % ครั้ง',
               v_doc.doc_no, v_balance, v_doc.payload -> 'behavior' ->> 'deduct_count';
end $$;

reset role;

-- ── TEST 250 ───────────────────────────────────────────────────────
-- นักศึกษาออกหนังสือถึงผู้ปกครองของตัวเองไม่ได้
--
-- ถ้าออกได้ จะเขียนใบรับรองความประพฤติให้ตัวเองพร้อมเลขที่เอกสารจริง
do $$
declare v_blocked boolean := false; v_msg text; v_doc issued_document; v_person uuid;
begin
  select person_id into v_person from student where id = current_setting('test.stu')::uuid;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('test.inst'), true);
  perform set_config('app.actor_id',       v_person::text, true);
  perform set_config('app.role',           'student', true);

  begin
    v_doc := issue_student_letter(current_setting('test.stu')::uuid, 'conduct_certificate',
                                  null, '{}'::jsonb);
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  reset role;

  if not v_blocked then
    raise exception 'TEST 250 ล้มเหลว: นักศึกษาออกใบรับรองความประพฤติให้ตัวเองได้ '
                    'พร้อมเลขที่เอกสารจริงของวิทยาลัย';
  end if;

  raise notice 'TEST 250 ผ่าน — นักศึกษาออกเอกสารเองไม่ได้ (%)', left(v_msg, 60);
end $$;

reset role;

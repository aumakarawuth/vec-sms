-- ═══════════════════════════════════════════════════════════════════
-- 0056_online_application.sql — ทดสอบสมัครเรียนออนไลน์ (0096)
--
-- ทุกข้อรันในบริบทเดียวกับที่ชั้น API ตั้งให้เส้นทางสาธารณะจริง
-- (`set local role app_runtime` + app.role = 'auth') — ถ้ารันเป็น superuser
-- RLS ถูกข้ามหมดแล้วข้อที่ว่า "เขียนตรงไม่ได้" จะเขียวโดยไม่ได้พิสูจน์อะไร
-- (บทเรียนของ TEST 147 ข้อ 21)
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- รอบที่เปิดรับอยู่ (ทำด้วยสิทธิ์เจ้าของ — เป็นงานของเจ้าหน้าที่ ไม่ใช่สิ่งที่ทดสอบ)
insert into admission_round (id, institution_id, academic_year_id, code, name_th,
                             applies_from, applies_to, status)
values ('99999999-0000-0000-0000-00000000a001', '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222223', 'ON-T', 'รอบทดสอบออนไลน์',
        current_date - 3, current_date + 3, 'open'),
       ('99999999-0000-0000-0000-00000000a002', '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222223', 'ON-D', 'รอบที่ยังไม่เปิด',
        current_date - 3, current_date + 3, 'draft');
insert into admission_quota (round_id, curriculum_version_id, seats)
values ('99999999-0000-0000-0000-00000000a001', '77777777-7777-7777-7777-777777777767', 30),
       ('99999999-0000-0000-0000-00000000a002', '77777777-7777-7777-7777-777777777767', 30);

begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.actor_id',       '00000000-0000-0000-0000-000000000000', true) as b,
       set_config('app.role',           'auth', true) as c \gset ctx_

do $$
declare
  v_form jsonb := jsonb_build_object(
    'first_name_th', 'สมัคร', 'last_name_th', 'ออนไลน์', 'birth_date', (current_date - interval '15 years')::date,
    'phone', '081-234-5678', 'prior_school_th', 'โรงเรียนทดสอบ');
  v_cv   uuid[] := array['77777777-7777-7777-7777-777777777767'::uuid];
  v_nid  bytea  := decode(repeat('ab', 32), 'hex');
  v_sec  bytea  := decode(repeat('cd', 32), 'hex');
  v_bad  bytea  := decode(repeat('ee', 32), 'hex');
  v_no   text;
  v_n    integer;
  r      record;
begin
  -- TEST 338 รอบที่เปิดอยู่ปรากฏ รอบ draft ไม่ปรากฏ
  select count(*) into v_n from apply_open_rounds()
   where round_id = '99999999-0000-0000-0000-00000000a002';
  if v_n <> 0 then raise exception 'TEST 338 ล้ม — รอบ draft ไม่ควรปรากฏในหน้าสาธารณะ'; end if;
  select count(*) into v_n from apply_open_rounds()
   where round_id = '99999999-0000-0000-0000-00000000a001';
  if v_n <> 1 then raise exception 'TEST 338 ล้ม — รอบที่เปิดอยู่ต้องปรากฏพร้อมสาขา ได้ %', v_n; end if;
  raise notice 'TEST 338 ผ่าน — เห็นเฉพาะรอบที่เปิดรับอยู่';

  -- TEST 339 บริบทสาธารณะเขียน application ตรงไม่ได้ อ่านก็ไม่ได้
  begin
    insert into application (institution_id, round_id, application_no, first_name_th, last_name_th)
    values ('11111111-1111-1111-1111-111111111111', '99999999-0000-0000-0000-00000000a001', 'X', 'ก', 'ข');
    raise exception 'TEST 339 ล้ม — insert ตรงสำเร็จ';
  exception when insufficient_privilege then null;
  end;
  select count(*) into v_n from application;
  if v_n <> 0 then raise exception 'TEST 339 ล้ม — บริบทสาธารณะอ่านใบสมัครได้ % ใบ', v_n; end if;
  raise notice 'TEST 339 ผ่าน — เส้นทางสาธารณะเขียน/อ่านตารางตรงไม่ได้';

  -- TEST 340 ยื่นได้จริง สถานะ submitted
  v_no := apply_submit('99999999-0000-0000-0000-00000000a001', v_form, v_nid, v_cv, v_sec);
  select * into r from apply_lookup(v_no, v_sec);
  if r.outcome <> 'ok' or r.data ->> 'status' <> 'submitted' or not (r.data ->> 'editable')::boolean then
    raise exception 'TEST 340 ล้ม — %', row_to_json(r);
  end if;
  raise notice 'TEST 340 ผ่าน — ยื่นได้ เลขที่ % ดูสถานะด้วยรหัสลับได้', v_no;

  -- TEST 341 เลขบัตรเดิมยื่นซ้ำในรอบเดียวกันไม่ได้ และไม่บอกเลขใบเดิม
  begin
    perform apply_submit('99999999-0000-0000-0000-00000000a001', v_form, v_nid, v_cv, v_bad);
    raise exception 'TEST 341 ล้ม — ยื่นซ้ำได้';
  exception when check_violation then
    if sqlerrm like '%' || v_no || '%' then
      raise exception 'TEST 341 ล้ม — ข้อความเปิดเผยเลขใบเดิม';
    end if;
  end;
  raise notice 'TEST 341 ผ่าน — กันยื่นซ้ำด้วยเลขบัตร';

  -- TEST 342 ยื่นเข้ารอบที่ไม่เปิด และเลือกสาขาที่รอบไม่ได้เปิดไม่ได้
  begin
    perform apply_submit('99999999-0000-0000-0000-00000000a002', v_form,
                         decode(repeat('a1', 32), 'hex'), v_cv, v_sec);
    raise exception 'TEST 342 ล้ม — ยื่นเข้ารอบ draft ได้';
  exception when check_violation then null;
  end;
  begin
    perform apply_submit('99999999-0000-0000-0000-00000000a001', v_form,
                         decode(repeat('a2', 32), 'hex'),
                         array['77777777-7777-7777-7777-777777777762'::uuid], v_sec);
    raise exception 'TEST 342 ล้ม — เลือกสาขาที่ไม่มีโควตาได้';
  exception when check_violation then null;
  end;
  raise notice 'TEST 342 ผ่าน — รอบ/สาขาที่ไม่เปิดยื่นไม่ได้';

  -- TEST 343 วันเกิดปี พ.ศ. ที่หลุดมาเป็น ค.ศ. ถูกปฏิเสธ
  begin
    perform apply_submit('99999999-0000-0000-0000-00000000a001',
                         v_form || jsonb_build_object('birth_date', '2554-05-01'),
                         decode(repeat('a3', 32), 'hex'), v_cv, v_sec);
    raise exception 'TEST 343 ล้ม — วันเกิดในอนาคตผ่าน';
  exception when check_violation then null;
  end;
  raise notice 'TEST 343 ผ่าน — ปี พ.ศ. ที่กรอกเป็น ค.ศ. ถูกดักที่ฐานข้อมูล';

  -- TEST 344 รหัสผิดไม่ได้ข้อมูล และตัวนับล็อกหลังห้าครั้ง แม้รหัสถูกก็ยังเข้าไม่ได้
  for i in 1..5 loop
    select * into r from apply_lookup(v_no, v_bad);
    if r.data is not null then raise exception 'TEST 344 ล้ม — รหัสผิดได้ข้อมูล'; end if;
  end loop;
  select * into r from apply_lookup(v_no, v_sec);
  if r.outcome <> 'locked' or r.retry_after_secs <= 0 then
    raise exception 'TEST 344 ล้ม — เดาผิดห้าครั้งต้องล็อก ได้ %', row_to_json(r);
  end if;
  raise notice 'TEST 344 ผ่าน — เดาผิดห้าครั้งล็อก % วินาที', r.retry_after_secs;
end $$;
rollback;

-- TEST 344ก ตัวนับต้องอยู่รอด — ถ้าฟังก์ชัน raise ตอนเดาผิด rollback จะล้างทิ้ง
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.role', 'auth', true) as b \gset ctx_
create temp table t_no on commit drop as
  select apply_submit('99999999-0000-0000-0000-00000000a001',
    jsonb_build_object('first_name_th', 'นับ', 'last_name_th', 'ผิด',
                       'birth_date', (current_date - interval '15 years')::date, 'phone', '0812345678'),
    decode(repeat('b1', 32), 'hex'), array['77777777-7777-7777-7777-777777777767'::uuid],
    decode(repeat('b2', 32), 'hex')) as no;
do $$ begin
  perform apply_lookup((select no from t_no), decode(repeat('00', 32), 'hex'));
  perform apply_lookup((select no from t_no), decode(repeat('00', 32), 'hex'));
end $$;
reset role;
do $$
declare v_n integer;
begin
  select failed_count into v_n from application_access x join application a on a.id = x.application_id
   where a.first_name_th = 'นับ' and a.last_name_th = 'ผิด';
  if v_n <> 2 then raise exception 'TEST 344ก ล้ม — ตัวนับควรเป็น 2 ได้ %', v_n; end if;
  raise notice 'TEST 344ก ผ่าน — ตัวนับเดาผิดถูกเขียนจริง ไม่ถูก rollback';
end $$;
rollback;

-- TEST 345–347 ผลก่อนประกาศ · แก้หลังเจ้าหน้าที่ตรวจ · วิทยาลัยอื่น
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.role', 'auth', true) as b \gset ctx_
create temp table t_app on commit drop as
  select apply_submit('99999999-0000-0000-0000-00000000a001',
    jsonb_build_object('first_name_th', 'ผล', 'last_name_th', 'ล่วงหน้า',
                       'birth_date', (current_date - interval '15 years')::date, 'phone', '0812345678'),
    decode(repeat('c1', 32), 'hex'), array['77777777-7777-7777-7777-777777777767'::uuid],
    decode(repeat('c2', 32), 'hex')) as no;
reset role;
-- เจ้าหน้าที่ตัดสินผล "ไม่ผ่าน" ไว้ก่อนวันประกาศ
update application set status = 'failed', decided_at = now()
 where application_no = (select no from t_app) and round_id = '99999999-0000-0000-0000-00000000a001';
set local role app_runtime;
do $$
declare r record;
begin
  select * into r from apply_lookup((select no from t_app), decode(repeat('c2', 32), 'hex'));
  if r.data ->> 'status' <> 'submitted' then
    raise exception 'TEST 345 ล้ม — ผลรั่วก่อนประกาศ: %', r.data ->> 'status';
  end if;
  raise notice 'TEST 345 ผ่าน — ผลที่บันทึกไว้แล้วยังไม่ปรากฏก่อนรอบประกาศ';

  begin
    perform apply_update((select no from t_app), decode(repeat('c2', 32), 'hex'),
      jsonb_build_object('first_name_th', 'แก้', 'last_name_th', 'หลังตัดสิน',
                         'birth_date', (current_date - interval '15 years')::date, 'phone', '0812345678'),
      array['77777777-7777-7777-7777-777777777767'::uuid]);
    raise exception 'TEST 346 ล้ม — แก้ใบหลังเจ้าหน้าที่ตัดสินผลได้';
  exception when check_violation then null;
  end;
  raise notice 'TEST 346 ผ่าน — ใบที่เจ้าหน้าที่แตะแล้วแก้ไม่ได้';
end $$;

select set_config('app.institution_id', '11111111-2222-2222-2222-111111111111', true) \gset other_
do $$
declare r record; v_n integer;
begin
  select * into r from apply_lookup((select no from t_app), decode(repeat('c2', 32), 'hex'));
  if r.outcome = 'ok' then raise exception 'TEST 347 ล้ม — วิทยาลัยอื่นเปิดใบได้'; end if;
  select count(*) into v_n from apply_open_rounds();
  if v_n <> 0 then raise exception 'TEST 347 ล้ม — เห็นรอบของวิทยาลัยอื่น'; end if;
  raise notice 'TEST 347 ผ่าน — รหัสถูกแต่คนละวิทยาลัยก็เปิดไม่ได้';
end $$;
rollback;

-- TEST 348 ผู้สมัครแก้ใบตัวเองได้ระหว่างยังไม่มีใครแตะ · เจ้าหน้าที่แก้ตารางรหัสไม่ได้
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.role', 'auth', true) as b \gset ctx_
do $$
declare v_no text; r record;
begin
  v_no := apply_submit('99999999-0000-0000-0000-00000000a001',
    jsonb_build_object('first_name_th', 'แก้', 'last_name_th', 'ได้',
                       'birth_date', (current_date - interval '15 years')::date, 'phone', '0812345678'),
    decode(repeat('d1', 32), 'hex'), array['77777777-7777-7777-7777-777777777767'::uuid],
    decode(repeat('d2', 32), 'hex'));
  select * into r from apply_update(v_no, decode(repeat('d2', 32), 'hex'),
    jsonb_build_object('first_name_th', 'แก้แล้ว', 'last_name_th', 'ได้',
                       'birth_date', (current_date - interval '16 years')::date, 'phone', '0899999999'),
    array['77777777-7777-7777-7777-777777777767'::uuid]);
  if r.outcome <> 'ok' or r.data -> 'form' ->> 'first_name_th' <> 'แก้แล้ว' then
    raise exception 'TEST 348 ล้ม — %', row_to_json(r);
  end if;
  raise notice 'TEST 348 ผ่าน — ผู้สมัครแก้ใบของตัวเองได้';
end $$;
select set_config('app.role', 'registrar', true) \gset reg_
do $$
declare v_n integer;
begin
  begin
    update application_access set failed_count = 0, locked_until = null;
    get diagnostics v_n = row_count;
    if v_n <> 0 then raise exception 'TEST 348ก ล้ม — เจ้าหน้าที่แก้ตารางรหัสได้ % แถว', v_n; end if;
  exception when insufficient_privilege then null;
  end;
  select count(*) into v_n from application where submitted_via = 'online';
  if v_n = 0 then raise exception 'TEST 348ก ล้ม — เจ้าหน้าที่ต้องเห็นใบที่ยื่นออนไลน์'; end if;
  raise notice 'TEST 348ก ผ่าน — งานทะเบียนเห็นใบออนไลน์แต่แตะรหัสลับไม่ได้';
end $$;
rollback;

delete from admission_quota where round_id in ('99999999-0000-0000-0000-00000000a001',
                                               '99999999-0000-0000-0000-00000000a002');
delete from admission_round where id in ('99999999-0000-0000-0000-00000000a001',
                                        '99999999-0000-0000-0000-00000000a002');

do $$ begin raise notice ''; raise notice '════ ทดสอบสมัครเรียนออนไลน์ครบทุกข้อ ════'; end $$;

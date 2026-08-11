-- ═══════════════════════════════════════════════════════════════════
-- 0044_student_status_reason.sql
-- ทดสอบว่าเหตุที่ออกลงประวัติจริงทุกครั้ง (0064)
--
-- ─── ทำไมข้อนี้ต้องกรอก "เหตุผลเดิมซ้ำ" ───
-- ตัวแรกที่เขียนใช้เงื่อนไข "เขียนเฉพาะเมื่อเหตุผลเปลี่ยน" เพื่อกันค่าค้าง
-- ซึ่งผ่านทุกกรณีที่นึกออกตอนเขียน — จนกระทั่งเจอกรณีที่เหตุผล**ซ้ำของเดิม**
-- (นักศึกษาสองคนพ้นสภาพด้วยเหตุผลเดียวกัน · คนที่กลับเข้าเรียนแล้วจบด้วย
--  ถ้อยคำเดิม · กดบันทึกซ้ำ) แล้วประวัติได้ reason เป็น null ทั้งที่กรอกมาแล้ว
-- ช่อง "เหตุที่ออก" บนใบ รบ. จึงว่างเปล่าโดยที่หน้าจอบอกว่าบันทึกสำเร็จ
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare
  v_student uuid; v_inst uuid; v_reason text; v_doc text; v_left text; n integer;
begin
  perform set_config('app.role', 'registrar', true);
  select s.id, s.institution_id into v_student, v_inst
    from student s order by s.student_code limit 1;
  perform set_config('app.institution_id', v_inst::text, true);

  update student set status = 'active' where id = v_student;
  delete from student_status_history where student_id = v_student;

  -- รอบแรก
  update student
     set status = 'dismissed', status_since = date '2026-03-31',
         status_reason = 'ขาดเรียนเกินเกณฑ์', status_document_no = 'คำสั่งที่ 1/2569'
   where id = v_student;

  /*
   * เลือกด้วย effective_on ไม่ใช่ "แถวล่าสุด" — `recorded_at` เป็น now()
   * ซึ่งเป็นเวลาของ**ทรานแซกชัน** ทุกแถวที่เขียนในบล็อกเดียวกันจึงเท่ากันหมด
   * แล้ว `order by recorded_at desc limit 1` จะคืนแถวไหนก็ได้
   */
  select reason, document_no into v_reason, v_doc
    from student_status_history
   where student_id = v_student and effective_on = date '2026-03-31';
  if v_reason is distinct from 'ขาดเรียนเกินเกณฑ์' or v_doc is distinct from 'คำสั่งที่ 1/2569' then
    raise exception 'TEST 272 ล้มเหลว: รอบแรกไม่ได้เขียนเหตุผลลงประวัติ — ได้ % / %', v_reason, v_doc;
  end if;

  -- ช่องพักต้องถูกล้างทิ้ง มิฉะนั้นค่าจะไปติดกับการเปลี่ยนสถานะครั้งถัดไป
  select status_reason into v_left from student where id = v_student;
  if v_left is not null then
    raise exception 'TEST 272 ล้มเหลว: ช่องพักไม่ถูกล้าง เหลือค่า %', v_left;
  end if;

  -- ─── รอบสอง: เหตุผล**เดิมเป๊ะ** — เป็นกรณีที่ตัวแรกพลาด ───
  update student set status = 'active' where id = v_student;
  update student
     set status = 'dismissed', status_since = date '2027-03-31',
         status_reason = 'ขาดเรียนเกินเกณฑ์'
   where id = v_student;

  select reason into v_reason
    from student_status_history
   where student_id = v_student and effective_on = date '2027-03-31'
     and to_status = 'dismissed';
  if v_reason is distinct from 'ขาดเรียนเกินเกณฑ์' then
    raise exception 'TEST 272 ล้มเหลว: เหตุผลที่ซ้ำของเดิมไม่ถูกเขียนลงประวัติ — ได้ %', v_reason;
  end if;

  -- ─── เปลี่ยนสถานะโดยไม่ตั้งเหตุผล ต้องได้ null ไม่ใช่เหตุผลของครั้งก่อน ───
  update student set status = 'active', status_since = date '2027-05-01' where id = v_student;
  select reason into v_reason
    from student_status_history
   where student_id = v_student and effective_on = date '2027-05-01';
  if v_reason is not null then
    raise exception 'TEST 272 ล้มเหลว: เหตุผลของครั้งก่อนติดมากับแถวใหม่ — %', v_reason;
  end if;

  select count(*) into n from student_status_history where student_id = v_student;
  raise notice 'TEST 272 ผ่าน — เขียนเหตุผลครบทุกครั้งรวมกรณีเหตุผลซ้ำเดิม · ประวัติ % แถว · ช่องพักถูกล้างทุกครั้ง', n;
end $$;

/*
 * และ transcript_extra() ต้องหยิบเฉพาะสถานะที่แปลว่าออกจากสถานศึกษาจริง
 * และต้องตรงกับสถานะปัจจุบัน — คนที่เคยพ้นสภาพแล้วกลับเข้าเรียนใหม่ต้องไม่มี
 * วันที่ออกค้างอยู่บนใบ
 */
do $$
declare
  v_student uuid; v_inst uuid; v_leaving jsonb;
begin
  perform set_config('app.role', 'registrar', true);
  select s.id, s.institution_id into v_student, v_inst
    from student s order by s.student_code limit 1;
  perform set_config('app.institution_id', v_inst::text, true);

  -- ตอนนี้สถานะเป็น active (จากบล็อกบน) ทั้งที่ประวัติมี dismissed อยู่
  v_leaving := transcript_extra(v_student) -> 'leaving';
  if v_leaving is not null and v_leaving <> 'null'::jsonb then
    raise exception 'TEST 273 ล้มเหลว: นักศึกษาที่กลับมาเรียนแล้วยังมีวันที่ออกบนใบ — %', v_leaving;
  end if;

  update student
     set status = 'graduated', status_since = date '2027-03-31',
         status_reason = 'สำเร็จการศึกษาตามหลักสูตร'
   where id = v_student;

  v_leaving := transcript_extra(v_student) -> 'leaving';
  if v_leaving ->> 'reason' is distinct from 'สำเร็จการศึกษาตามหลักสูตร' then
    raise exception 'TEST 273 ล้มเหลว: payload ของใบ รบ. ไม่มีเหตุที่ออก — %', v_leaving;
  end if;

  raise notice 'TEST 273 ผ่าน — คนที่กลับมาเรียนไม่มีวันที่ออกบนใบ · คนที่ออกจริงมีเหตุผลครบ (%)',
               v_leaving ->> 'on_date';
end $$;

reset role;

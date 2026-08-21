-- ═══════════════════════════════════════════════════════════════════
-- 0053_term_lifecycle.sql — ทดสอบลำดับสถานะภาคเรียน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare v_inst uuid := '11111111-1111-1111-1111-111111111111'; v_ay uuid;
begin
  insert into academic_year (institution_id, year_be, starts_on, ends_on)
  values (v_inst, 2599, '2599-05-01', '2600-03-31')
  returning id into v_ay;
  insert into term (id, academic_year_id, ordinal, starts_on, ends_on)
  values ('99999999-0000-0000-0000-000000000001', v_ay, 1, '2599-05-11', '2599-09-30');
  raise notice 'เตรียมฐาน — ปีการศึกษา 2599 ภาคเรียนที่ 1 (id ลงท้าย ...0001) สถานะเริ่มต้น planning';
end $$;

-- ── TEST 314 ───────────────────────────────────────────────────────
-- ข้ามขั้นตอนไม่ได้ — planning ไป open ตรง ๆ ต้องถูกปฏิเสธ
do $$
begin
  begin
    perform advance_term_status('99999999-0000-0000-0000-000000000001', 'open');
    raise exception 'TEST 314 ล้มเหลว: ข้ามจาก planning ไป open ตรง ๆ ได้';
  exception
    when raise_exception then
      raise notice 'TEST 314 ผ่าน — ข้ามขั้นตอนจาก planning ไป open ถูกปฏิเสธ';
  end;
end $$;

-- ── TEST 315 ───────────────────────────────────────────────────────
-- เดินหน้าทีละขั้นได้ครบ planning → registration → open → grading → closed
do $$
declare v_status term_status;
begin
  perform advance_term_status('99999999-0000-0000-0000-000000000001', 'registration');
  perform advance_term_status('99999999-0000-0000-0000-000000000001', 'open');
  perform advance_term_status('99999999-0000-0000-0000-000000000001', 'grading');
  select status into v_status from advance_term_status('99999999-0000-0000-0000-000000000001', 'closed');
  if v_status <> 'closed' then
    raise exception 'TEST 315 ล้มเหลว: สถานะสุดท้ายควรเป็น closed ได้ %', v_status;
  end if;
  raise notice 'TEST 315 ผ่าน — เดินครบ planning → registration → open → grading → closed';
end $$;

-- ── TEST 316 ───────────────────────────────────────────────────────
-- closed แล้วเดินต่อไม่ได้อีกเลย แม้แต่ถอยกลับ
do $$
begin
  begin
    perform advance_term_status('99999999-0000-0000-0000-000000000001', 'grading');
    raise exception 'TEST 316 ล้มเหลว: ภาคเรียนที่ closed แล้วยังเปลี่ยนสถานะได้';
  exception
    when raise_exception then
      raise notice 'TEST 316 ผ่าน — closed แล้วเปลี่ยนสถานะอะไรต่อไม่ได้อีกเลย';
  end;
end $$;

-- ── TEST 317 ───────────────────────────────────────────────────────
-- ถอยจาก registration กลับ planning ได้ทางเดียวที่ยอมให้ถอย
do $$
declare v_ay uuid; v_term uuid; v_status term_status;
begin
  select id into v_ay from academic_year where year_be = 2599;
  insert into term (academic_year_id, ordinal, starts_on, ends_on)
  values (v_ay, 2, '2599-11-01', '2600-03-15')
  returning id into v_term;

  perform advance_term_status(v_term, 'registration');
  select status into v_status from advance_term_status(v_term, 'planning');
  if v_status <> 'planning' then
    raise exception 'TEST 317 ล้มเหลว: ควรถอยกลับ planning ได้ ได้ %', v_status;
  end if;

  begin
    perform advance_term_status(v_term, 'grading');
    raise exception 'TEST 317 ล้มเหลว: จาก planning กระโดดไป grading ได้';
  exception
    when raise_exception then
      raise notice 'TEST 317 ผ่าน — ถอยจาก registration กลับ planning ได้ครั้งเดียว แล้วยังข้ามขั้นต่อไม่ได้';
  end;
end $$;

\echo ''
\echo '════ ทดสอบลำดับสถานะภาคเรียนครบทุกข้อ ════'

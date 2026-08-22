-- ═══════════════════════════════════════════════════════════════════
-- 0078 — GPA/GPAX ไม่เคยถูกคำนวณในระบบจริงเลยตั้งแต่ 0016
--
-- ─── ต้นเหตุ ───
-- compute_term_summary() (0016) เขียน term_summary ถูกต้องทุกอย่าง แต่ไม่มี
-- อะไรในทั้งระบบเรียกมันอัตโนมัติเลย — ไม่มี trigger ไม่มี job ไม่มีฟังก์ชัน
-- อื่นเรียก จุดเดียวที่เรียกได้คือ POST /gradebook/terms/:termId/summary
-- ซึ่งไม่เคยมีปุ่มในหน้าจอและไม่เคยมีเทสต์ระดับ API เรียกมันเลยสักข้อ —
-- เทสต์ที่มีอยู่ (db/tests/0007, 0042) เรียก compute_term_summary() ตรงด้วย
-- SQL ในขั้นเตรียมข้อมูล ไม่ได้เดินทางที่ระบบจริงเดิน (รูปแบบเดียวกับข้อ 14
-- ใน CLAUDE.md — เทสต์ insert ตรง ไม่มีใครกดปุ่มจริงเลย)
--
-- ผลคือ term_summary ว่างเปล่าตลอดในวิทยาลัยที่ deploy จริง (ยืนยันแล้ว —
-- ฐานทดสอบที่รันเทสต์ผ่านครบ 610 ข้อ ก็มี term_summary 0 แถวเหมือนกัน) และ
-- evaluate_graduation() (0051) อ่าน gpax จากตารางนี้ตรง ๆ ด้วย
-- `order by computed_at desc limit 1` — ถ้าไม่มีแถว v_gpax เป็น null ซึ่ง
-- เทียบกับเกณฑ์ GPA ไม่ผ่านเสมอ ไม่ว่านักศึกษาจะเรียนดีแค่ไหน และใบ รบ.
-- ตระกูล 62 ที่อ่านจากตารางนี้ตรงจะว่างเปล่าเช่นกัน (0060)
--
-- ─── ทำไมผูกไว้ใน advance_term_status() แทนที่จะเพิ่มปุ่มอย่างเดียว ───
-- หลักข้อ 1: กฎธุรกิจต้องอยู่ในฐานข้อมูล ไม่ใช่ชั้น API เพราะถ้าใครปิดภาคเรียน
-- ผ่านทางอื่น (pgAdmin เพื่อแก้ไขข้อมูล สคริปต์ย้ายข้อมูล ฟังก์ชันอื่นในอนาคต)
-- โดยไม่ผ่านปุ่มในหน้าจอ การคำนวณจะถูกข้ามไปเงียบ ๆ เหมือนเดิม — ผูกไว้ที่
-- ฟังก์ชันเดียวกับที่เปลี่ยนสถานะแทน ทำให้ปิดภาคเรียนได้จริงก็ต้องคำนวณ
-- GPA/GPAX เสร็จจริงเสมอ อยู่ในธุรกรรมเดียวกัน ถ้าคำนวณพลาดสถานะก็ไม่เปลี่ยน
-- ตามด้วย (หลักข้อ 6 — ล้มดีกว่าทำงานผิดเงียบ ๆ)
--
-- endpoint เดิม (POST /gradebook/terms/:termId/summary) ยังเปิดไว้เหมือนเดิม
-- ไม่ใช่ของซ้ำซ้อน — ใช้คำนวณใหม่ได้หลังแก้เกรดผ่านคำร้องเมื่อภาคเรียนปิดไปแล้ว
-- (compute_term_summary() upsert ทับตาม (student_id, term_id) อยู่แล้ว ไม่ซ้อน)
-- และใช้ backfill ให้ภาคเรียนที่เคยปิดไปแล้วก่อน migration นี้ด้วย
-- ═══════════════════════════════════════════════════════════════════

create or replace function advance_term_status(p_term_id uuid, p_status term_status)
returns term
language plpgsql as $$
declare
  v_term    term;
  v_allowed term_status[];
begin
  select * into v_term from term where id = p_term_id;
  if v_term.id is null then
    raise exception 'ไม่พบภาคเรียนนี้ หรือไม่มีสิทธิ์เข้าถึง';
  end if;

  v_allowed := case v_term.status
    when 'planning'     then array['registration']::term_status[]
    when 'registration' then array['open', 'planning']::term_status[]
    when 'open'         then array['grading']::term_status[]
    when 'grading'      then array['closed']::term_status[]
    when 'closed'       then array[]::term_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'เปลี่ยนสถานะจาก % เป็น % ไม่ได้ — ต้องเป็น %',
      v_term.status, p_status,
      case when array_length(v_allowed, 1) is null then 'ไม่มีสถานะถัดไปแล้ว (ปิดภาคเรียนแล้ว)'
           else array_to_string(v_allowed, ' หรือ ') end;
  end if;

  -- ปิดภาคเรียนต้องคำนวณ GPA/GPAX ลง term_summary เสมอ ห้ามพลาดแม้ครั้งเดียว
  -- (ดูคอมเมนต์หัวไฟล์) — อยู่ในธุรกรรมเดียวกับการเปลี่ยนสถานะ ถ้าคำนวณ
  -- ล้มเหลว สถานะจะไม่ถูกเปลี่ยนตามไปด้วย
  if p_status = 'closed' then
    perform compute_term_summary(p_term_id);
  end if;

  update term set status = p_status where id = p_term_id returning * into v_term;
  return v_term;
end $$;

comment on function advance_term_status(uuid, term_status) is
  'เปลี่ยนสถานะภาคเรียนทีละขั้นตามลำดับ planning→registration→open→grading→closed '
  'ถอยจาก registration กลับ planning ได้ทางเดียว ที่เหลือเดินหน้าทางเดียว — '
  'ปิดภาคเรียน (closed) เรียก compute_term_summary() ให้เองเสมอ (0078)';

-- ── backfill ภาคเรียนที่ปิดไปแล้วก่อน migration นี้ ────────────────────
-- วิทยาลัยไหนที่เคยปิดภาคเรียนไปแล้วก่อนแก้ครั้งนี้ term_summary ของภาคนั้น
-- จะว่างเปล่าตลอดไปถ้าไม่ backfill ให้ — เดินทุกภาคเรียนที่สถานะเป็น closed
-- อยู่แล้วในตอนนี้ ข้ามได้อย่างปลอดภัยถ้าไม่มีภาคที่ปิดแล้วเลย (deploy ใหม่)
do $$
declare v_term record; v_count integer := 0;
begin
  for v_term in select id from term where status = 'closed' loop
    perform compute_term_summary(v_term.id);
    v_count := v_count + 1;
  end loop;
  raise notice 'backfill term_summary ให้ % ภาคเรียนที่ปิดไปแล้วก่อนหน้านี้', v_count;
end $$;

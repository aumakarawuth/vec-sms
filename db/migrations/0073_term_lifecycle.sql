-- ═══════════════════════════════════════════════════════════════════
-- 0073_term_lifecycle.sql
--
-- ไม่มีทางเปลี่ยนสถานะภาคเรียนเลยตั้งแต่ 0001 — `term.status` มีคอลัมน์
-- และ `check_registration_rules()` (0009) อ่านค่านี้เพื่อตัดสินว่าเปิด
-- ลงทะเบียนหรือยัง แต่ไม่มีฟังก์ชันหรือเส้นทาง API ไหนเขียนมันเลยสักที่
-- ตลอด 72 migration ที่ผ่านมา ภาคเรียนของวิทยาลัยที่เพิ่ง seed จึงค้างอยู่ที่
-- สถานะเริ่มต้น 'planning' ตลอดไป เว้นแต่จะพิมพ์ SQL ตรงเข้าฐานข้อมูลเอง
-- (ซึ่งคือสิ่งที่ demo-data.sql/first-terms.sql ทำอยู่ตอนนี้ — ใช้ได้แค่
-- ตอน seed ครั้งแรก ไม่ใช่ทางที่งานวิชาการใช้ต่อไปทุกภาคเรียน)
--
-- ─── ทำไมต้องเป็นฟังก์ชัน ไม่ใช่ update ตรง ๆ จากชั้น API ───
-- ลำดับ planning → registration → open → grading → closed มีความหมาย
-- ทางธุรกิจจริง (เช่น closed แล้วห้ามแก้ผลการเรียนโดยตรงตามคอมเมนต์เดิม
-- ใน 0001) ถ้าปล่อยให้ชั้น API เขียนสถานะอะไรก็ได้ตามใจ การข้ามขั้นตอน
-- (เช่น planning ไป closed ตรง ๆ) จะทำให้ระเบียนเดินไปอยู่ในสถานะที่
-- ไม่มีใครตั้งใจให้เกิดขึ้นได้ — ตามหลักข้อ 1 กฎการเปลี่ยนสถานะจึงต้องอยู่
-- ในฐานข้อมูล ไม่ใช่กระจายอยู่ตามชั้น API ที่อาจเขียนซ้ำผิดกันคนละที่
--
-- ─── ทำไมยอมถอยจาก registration กลับ planning ได้ ───
-- งานทะเบียนอาจกดเปิดเร็วไปแล้วต้องถอยกลับไปแก้ช่วงเพิ่ม-ถอนก่อน — ทางอื่น
-- ทั้งหมดเดินไปข้างหน้าทางเดียว เพราะย้อนกลับหลังจากมีคนลงทะเบียนหรือ
-- มีการเช็คชื่อไปแล้วจะทำให้ข้อมูลที่เขียนไปแล้วขัดกับสถานะใหม่
-- ═══════════════════════════════════════════════════════════════════
begin;

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

  update term set status = p_status where id = p_term_id returning * into v_term;
  return v_term;
end $$;

comment on function advance_term_status(uuid, term_status) is
  'เปลี่ยนสถานะภาคเรียนทีละขั้นตามลำดับ planning→registration→open→grading→closed '
  'ถอยจาก registration กลับ planning ได้ทางเดียว ที่เหลือเดินหน้าทางเดียว';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 0077 — rollover_fee_schedules() ใช้งานจริงไม่ได้เลยสักครั้งตั้งแต่ 0031
--
-- ─── เจอตอนต่อหน้าจอเข้ากับปุ่มที่ไม่เคยมีปุ่มมาก่อน ไม่ใช่ตอนอ่านโค้ด ───
-- ฟังก์ชันนี้มีมาตั้งแต่ 0031 พร้อมเทสต์ที่ด่านฐานข้อมูลไม่เคยเรียกมันเลย
-- (ไม่มีอยู่ใน db/tests/) และชั้น API ก็ไม่เคยมีหน้าจอเรียกมันเลยสักปุ่ม —
-- พอเปิดปุ่มแรกจากหน้าจอจริงแล้วยิงจริง กลับได้
-- "new row violates row-level security policy for table fee_schedule_line"
-- ทุกครั้ง ไม่ว่าจะเป็นบทบาทไหนก็ตาม (ลองแล้วทั้ง registrar และ admin)
--
-- ─── ต้นเหตุไม่ใช่เรื่องสิทธิ์ ทั้งที่ข้อความอ่านดูเหมือนเรื่องสิทธิ์ ───
-- ฟังก์ชันเดิม insert เข้า fee_schedule กับ fee_schedule_line ในคำสั่งเดียว
-- ด้วย `with copied as (insert into fee_schedule ... returning ...) insert
-- into fee_schedule_line select ... from copied join fee_schedule src on ...`
-- นโยบาย tenant_isolation ของ fee_schedule_line ตรวจว่า "มีแถวพ่อแม่ใน
-- fee_schedule ที่ institution_id ตรงกันไหม" ด้วย exists(select ... from
-- fee_schedule ...) ซึ่งเป็นการ scan ตารางจริงแยกต่างหาก — และ PostgreSQL
-- ไม่ให้ส่วนอื่นของคำสั่งเดียวกันเห็นแถวที่ CTE เพิ่ง insert ไป (เห็นได้ทาง
-- เดียวคือผ่าน RETURNING ของ CTE นั้นเอง) แถวแม่ที่เพิ่งสร้างจึง "ไม่มีอยู่"
-- ในสายตาของนโยบายนี้ชั่วขณะ ทั้งที่อยู่ในธุรกรรมเดียวกันและจะ commit จริง
--
-- ─── ทำไมแก้ด้วยการแยกเป็นสองคำสั่ง ไม่ใช่เปลี่ยนนโยบาย RLS ───
-- นโยบายของ fee_schedule_line ถูกต้องอยู่แล้ว (กันไม่ให้ผูกกับ fee_schedule
-- ของวิทยาลัยอื่น) ปัญหาอยู่ที่การ chain สองคำสั่งเข้าด้วยกันเฉย ๆ — แยกเป็น
-- insert ทีละคำสั่งแล้วเก็บ id ที่เพิ่งสร้างไว้ในตัวแปร (ผ่าน RETURNING ของ
-- CTE ตัวมันเอง ซึ่งเห็นแถวตัวเองได้ปกติ) คำสั่งที่สองจึง scan fee_schedule
-- แบบ select ธรรมดาซึ่งเห็นแถวที่เพิ่ง insert ไปแล้วในธุรกรรมเดียวกันจริง ๆ
-- ผลลัพธ์และเงื่อนไข "กดซ้ำไม่คัดลอกซ้อน" เหมือนเดิมทุกประการ (ทดสอบแล้ว)
-- ═══════════════════════════════════════════════════════════════════

create or replace function rollover_fee_schedules(
  p_from_year_be smallint,
  p_to_year_be   smallint
) returns integer language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_from_ay uuid;
  v_to_ay   uuid;
  v_new_ids uuid[];
  v_count   integer := 0;
begin
  select id into v_from_ay from academic_year
   where institution_id = v_inst and year_be = p_from_year_be;
  select id into v_to_ay   from academic_year
   where institution_id = v_inst and year_be = p_to_year_be;

  if v_from_ay is null or v_to_ay is null then
    raise exception 'ไม่พบปีการศึกษาต้นทางหรือปลายทางในสถานศึกษานี้';
  end if;

  with ins as (
    insert into fee_schedule
      (institution_id, academic_year_id, level, study_year, program_id, active)
    select fs.institution_id, v_to_ay, fs.level, fs.study_year, fs.program_id, false
      from fee_schedule fs
     where fs.institution_id = v_inst
       and fs.academic_year_id = v_from_ay
       -- ไม่คัดลอกทับของที่มีอยู่แล้ว กดซ้ำจึงไม่ทำให้ค่าเทอมซ้อนกัน
       and not exists (
         select 1 from fee_schedule t
          where t.institution_id = v_inst
            and t.academic_year_id = v_to_ay
            and t.level = fs.level
            and t.study_year is not distinct from fs.study_year
            and t.program_id is not distinct from fs.program_id)
    returning id
  )
  select array_agg(id) into v_new_ids from ins;

  -- คำสั่งแยกจากด้านบนโดยตั้งใจ (ดูคอมเมนต์หัวไฟล์) — scan fee_schedule
  -- ตรงนี้เห็นแถวที่เพิ่ง insert ไปแล้วจริง เพราะเป็นคนละคำสั่งกัน
  insert into fee_schedule_line (fee_schedule_id, fee_item_id, term_ordinal, amount)
  select dst.id, l.fee_item_id, l.term_ordinal, l.amount
    from fee_schedule dst
    join fee_schedule src
      on src.institution_id = v_inst
     and src.academic_year_id = v_from_ay
     and src.level = dst.level
     and src.study_year is not distinct from dst.study_year
     and src.program_id is not distinct from dst.program_id
    join fee_schedule_line l on l.fee_schedule_id = src.id
   where dst.id = any (v_new_ids);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function rollover_fee_schedules(smallint, smallint) is
  'คัดลอกรายการชำระเงินตามระดับชั้นไปปีถัดไป โดยยังไม่เปิดใช้ (active = false) ให้งานการเงินตรวจตัวเลขก่อน — insert สองคำสั่งแยกกันโดยตั้งใจ (ดู 0077) ห้ามรวมกลับเป็น WITH...INSERT เดียว';

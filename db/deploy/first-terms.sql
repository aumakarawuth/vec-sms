-- ═══════════════════════════════════════════════════════════════════
-- first-terms.sql
-- สร้างภาคเรียนแรกให้วิทยาลัยที่เพิ่งเปิด — รันครั้งเดียวต่อหนึ่งวิทยาลัย
--
--   psql "$ADMIN_DATABASE_URL" -v ON_ERROR_STOP=1 -f db/deploy/first-terms.sql
--
-- ─── ทำไมต้องมีไฟล์นี้ ───
-- `POST /platform/institutions` สร้างวิทยาลัย ผู้ดูแล และ**ปีการศึกษา**ให้
-- แต่ไม่ได้สร้างภาคเรียน และไม่มีเส้นทาง API ให้สร้างเลยสักเส้น
-- (`/rollover` คัดลอกของระหว่างภาคเรียนที่มีอยู่แล้วเท่านั้น ส่วน
--  `insert into term` มีอยู่ที่เดียวคือไฟล์ seed ซึ่งเป็นข้อมูลตัวอย่าง)
--
-- ผลคือวิทยาลัยที่เพิ่งเปิดยังใช้งานอะไรไม่ได้เลย และแอปเว็บ build ไม่ได้
-- เพราะไม่มี TERM_ID จนกว่าจะเติมภาคเรียนเข้าไป
--
-- ไฟล์นี้เป็นทางชั่วคราวจนกว่าจะมีหน้าจอปฏิทินการศึกษา — ไม่ใช่การออกแบบ
-- ที่ตั้งใจให้เป็นแบบนี้ถาวร
--
-- ─── ต้องรันด้วยผู้ใช้ที่เป็นเจ้าของฐานข้อมูล ───
-- ไม่ใช่ vecsms_app เพราะบริบท app.* ยังไม่มีตอนรันจากบรรทัดคำสั่ง
-- ทุกนโยบาย RLS จึงปฏิเสธทุกแถว (ตั้งใจให้เป็นแบบนั้น)
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- แก้เฉพาะบล็อกนี้ให้ตรงกับวิทยาลัยและปฏิทินจริง แล้วรันทั้งไฟล์
--
-- วันสำคัญสามค่าหลังของแต่ละภาคมีผลกับกฎที่บังคับใช้จริง —
--   add_drop_ends_on  หลังวันนี้ เพิ่ม/ถอนรายวิชาไม่ได้
--   withdraw_ends_on  หลังวันนี้ ถอนแบบติด W ไม่ได้
--   grade_due_on      กำหนดส่งเกรด ใช้เตือนและใช้ในรายงานคุมงาน
-- ตั้งผิดแล้วแก้ทีหลังได้ แต่รายการที่เกิดไปแล้วไม่ย้อนกลับ
-- ───────────────────────────────────────────────────────────────────
create temporary table _params on commit drop as
select
  '1234567890'::text as institution_code,   -- รหัสสถานศึกษา 10 หลัก
  2569::smallint     as year_be,            -- ปีการศึกษา พ.ศ.

  -- ภาคเรียนที่ 1 — เปิดใช้งานทันที
  date '2026-05-16'  as t1_starts_on,
  date '2026-10-10'  as t1_ends_on,
  date '2026-05-30'  as t1_add_drop_ends_on,
  date '2026-08-29'  as t1_withdraw_ends_on,
  date '2026-10-24'  as t1_grade_due_on,

  -- ภาคเรียนที่ 2 — ยังไม่เปิด (planning) เปลี่ยนสถานะเมื่อถึงเวลา
  date '2026-11-01'  as t2_starts_on,
  date '2027-03-31'  as t2_ends_on,
  date '2026-11-15'  as t2_add_drop_ends_on,
  date '2027-02-13'  as t2_withdraw_ends_on,
  date '2027-04-14'  as t2_grade_due_on;

-- ล้มทันทีถ้าหาปีการศึกษาไม่เจอ ดีกว่าเงียบแล้วไม่ได้อะไรเลย
do $$
declare n integer;
begin
  select count(*) into n
    from _params p
    join institution i   on i.code = p.institution_code
    join academic_year a on a.institution_id = i.id and a.year_be = p.year_be;
  if n <> 1 then
    raise exception 'หาปีการศึกษาของวิทยาลัยนี้ไม่เจอ (พบ % รายการ) — ตรวจ institution_code กับ year_be ในไฟล์', n;
  end if;
end $$;

insert into term (academic_year_id, ordinal, kind, starts_on, ends_on,
                  add_drop_ends_on, withdraw_ends_on, grade_due_on, status)
select a.id, 1, 'regular',
       p.t1_starts_on, p.t1_ends_on,
       p.t1_add_drop_ends_on, p.t1_withdraw_ends_on, p.t1_grade_due_on,
       'open'
  from _params p
  join institution i   on i.code = p.institution_code
  join academic_year a on a.institution_id = i.id and a.year_be = p.year_be
on conflict (academic_year_id, ordinal) do nothing;

insert into term (academic_year_id, ordinal, kind, starts_on, ends_on,
                  add_drop_ends_on, withdraw_ends_on, grade_due_on, status)
select a.id, 2, 'regular',
       p.t2_starts_on, p.t2_ends_on,
       p.t2_add_drop_ends_on, p.t2_withdraw_ends_on, p.t2_grade_due_on,
       'planning'
  from _params p
  join institution i   on i.code = p.institution_code
  join academic_year a on a.institution_id = i.id and a.year_be = p.year_be
on conflict (academic_year_id, ordinal) do nothing;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- เอา id ของภาคเรียนที่ status = 'open' ไปใส่เป็น TERM_ID ตอน build แอปเว็บ
-- ═══════════════════════════════════════════════════════════════════
select t.id as term_id, t.ordinal, t.status, t.starts_on, t.ends_on,
       i.code as institution_code, i.id as institution_id
  from term t
  join academic_year a on a.id = t.academic_year_id
  join institution i   on i.id = a.institution_id
 order by i.code, a.year_be, t.ordinal;

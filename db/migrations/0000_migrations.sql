-- ═══════════════════════════════════════════════════════════════════
-- 0000_migrations.sql
-- ตารางติดตามว่า migration ไหนถูกใช้ไปแล้ว
--
-- ต้องมีตัวนี้ก่อนทุกอย่าง เพราะการ deploy จริงคือการ "เติมส่วนที่ยังไม่มี"
-- ลงฐานข้อมูลที่มีข้อมูลอยู่แล้ว ไม่ใช่การสร้างใหม่ทั้งก้อน
--
-- เก็บ checksum ไว้ด้วย เพื่อจับกรณีที่มีคนแก้ไฟล์ migration ที่ deploy
-- ไปแล้ว ซึ่งจะทำให้ฐานข้อมูลแต่ละเครื่องไม่ตรงกันโดยไม่มีใครรู้
-- ═══════════════════════════════════════════════════════════════════

create table if not exists schema_migrations (
  version     text        primary key,
  checksum    text        not null,
  applied_at  timestamptz not null default now(),
  applied_by  text        not null default current_user,
  duration_ms integer
);

comment on table schema_migrations is
  'บันทึกว่า migration ไหนถูกใช้ไปแล้ว deploy.sh อ่านตารางนี้เพื่อข้ามไฟล์ที่ทำไปแล้ว';
comment on column schema_migrations.checksum is
  'SHA-256 ของไฟล์ ณ เวลาที่ใช้ ถ้าไฟล์ถูกแก้ทีหลัง deploy.sh จะหยุดและแจ้งเตือน';

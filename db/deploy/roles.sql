-- ═══════════════════════════════════════════════════════════════════
-- roles.sql
-- สร้างกลุ่มสิทธิ์สำหรับใช้งานจริง — รันครั้งเดียวหลัง deploy โครงสร้างเสร็จ
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/deploy/roles.sql
--
-- ─── เรื่องสำคัญที่สุดของไฟล์นี้ ───
-- แอปพลิเคชันต้องห้ามเชื่อมต่อด้วย superuser เด็ดขาด
-- เพราะ superuser ข้าม Row-Level Security ทุกกรณี แปลว่ากำแพงกันข้อมูล
-- ข้ามสถานศึกษาและกำแพงกันครูดูข้อมูลนักศึกษาที่ไม่ได้สอน จะไม่ทำงานเลย
-- และไม่มีอะไรฟ้อง ระบบจะดูเหมือนทำงานปกติจนกว่าจะมีคนร้องเรียน
--
-- ไฟล์นี้สร้าง "กลุ่มสิทธิ์" ที่ล็อกอินไม่ได้ แล้วให้สร้างผู้ใช้จริงแยก
-- เพื่อไม่ต้องเก็บรหัสผ่านไว้ในไฟล์ที่อยู่ในรีโป
-- ═══════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────
-- กลุ่มที่ 1: แอปพลิเคชัน — อ่านเขียนได้ แต่อยู่ใต้ RLS
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_runtime') then
    create role app_runtime nologin;
  end if;
end $$;

grant usage on schema public to app_runtime;
grant select, insert, update, delete on all tables    in schema public to app_runtime;
grant usage, select                  on all sequences in schema public to app_runtime;
grant execute                        on all functions in schema public to app_runtime;

-- ตารางที่สร้างในอนาคตให้ได้สิทธิ์เดียวกันอัตโนมัติ
alter default privileges in schema public
  grant select, insert, update, delete on tables    to app_runtime;
alter default privileges in schema public
  grant usage, select                  on sequences to app_runtime;
alter default privileges in schema public
  grant execute                        on functions to app_runtime;

-- ───────────────────────────────────────────────────────────────────
-- กลุ่มที่ 2: รายงานและ BI — อ่านอย่างเดียว
-- Metabase หรือเครื่องมือทำรายงานควรใช้กลุ่มนี้ ไม่ใช่กลุ่มแอป
-- ───────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_readonly') then
    create role app_readonly nologin;
  end if;
end $$;

grant usage  on schema public to app_readonly;
grant select on all tables in schema public to app_readonly;
alter default privileges in schema public grant select on tables to app_readonly;

-- ───────────────────────────────────────────────────────────────────
-- ปิดสิทธิ์ที่เปิดไว้กว้างเกินไปโดยค่าเริ่มต้น
-- PostgreSQL 14 และเก่ากว่า เปิดให้ทุกคนสร้างตารางใน schema public ได้
-- ───────────────────────────────────────────────────────────────────
revoke create on schema public from public;

-- ═══════════════════════════════════════════════════════════════════
-- ขั้นตอนต่อไป — ทำเองด้วยมือ ไม่เก็บรหัสผ่านไว้ในไฟล์
--
--   create user vecsms_app      with password '<รหัสผ่านที่สุ่มมา>' in role app_runtime;
--   create user vecsms_report   with password '<รหัสผ่านที่สุ่มมา>' in role app_readonly;
--
-- แล้วให้แอปเชื่อมต่อด้วย vecsms_app และให้ Metabase ใช้ vecsms_report
--
-- ตรวจว่าตั้งถูกแล้วด้วยคำสั่งนี้ — ต้องได้ f ทั้งสองคอลัมน์
--   select rolsuper, rolbypassrls from pg_roles where rolname = 'vecsms_app';
-- ═══════════════════════════════════════════════════════════════════

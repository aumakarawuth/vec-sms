-- ═══════════════════════════════════════════════════════════════════
-- คืนมาตรการเข้าสู่ระบบเป็นค่าเริ่มต้น — ย้อน demo-auth-relax.sql
--
--   psql -v ON_ERROR_STOP=1 -f api/tools/demo-auth-strict.sql vecsms_api_test
--
-- ─── ทำไมใช้ `= default` ไม่ใช่เขียนตัวเลขกลับไป ───
-- ค่าเริ่มต้นจริงอยู่ที่ `create table auth_policy` ใน 0014 และคอลัมน์ที่
-- เพิ่มทีหลัง ถ้าไฟล์นี้เขียนตัวเลขไว้เอง วันที่ migration เปลี่ยนค่าเริ่มต้น
-- ไฟล์นี้จะคืนค่าเป็นของเก่าเงียบ ๆ แล้วไม่มีอะไรฟ้อง — `default` อ่านจาก
-- นิยามของคอลัมน์เสมอ จึงไม่มีวันเพี้ยน
--
-- ─── ต้องรันก่อนเสมอ ถ้าจะเอาฐานนี้ไปวัดอะไรที่เกี่ยวกับการยืนยันตัวตน ───
-- ฐานที่ถูกผ่อนไว้จะทำให้เทสต์เรื่องล็อกบัญชี · การผูกอุปกรณ์ · และการ
-- บังคับสองชั้น ผ่านโดยไม่ได้พิสูจน์อะไรเลย
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

begin;

update auth_policy set
  require_mfa_roles    = default,
  bind_student_device  = default,
  max_devices_student  = default,
  max_failed_attempts  = default,
  lockout_minutes      = default,
  max_ip_attempts      = default,
  ip_window_minutes    = default,
  ip_block_minutes     = default,
  access_token_minutes = default,
  max_reset_per_day    = default,
  max_reset_per_ip_day = default,
  reset_code_attempts  = default,
  mfa_max_attempts     = default;

commit;

\echo ''
\echo 'คืนมาตรการเข้าสู่ระบบเป็นค่าเริ่มต้นแล้ว'
\echo 'admin/director ต้องผูก authenticator ใหม่ถ้ายังไม่เคยผูก —'
\echo '  node api/tools/seed-demo-users.cjs'
\echo ''

select bind_student_device as "ผูกอุปกรณ์",
       require_mfa_roles   as "บทบาทที่ต้องยืนยันสองชั้น",
       max_failed_attempts as "ผิดได้กี่ครั้ง",
       access_token_minutes as "อายุ token (นาที)"
  from auth_policy;

-- ═══════════════════════════════════════════════════════════════════
-- คืนการบังคับยืนยันสองชั้นให้วิทยาลัยตัวอย่าง (ค่าเดิมของระบบ)
--
--   psql -f api/tools/demo-mfa-on.sql vecsms_api_test
--
-- รันหลังจากตั้ง MFA_SECRET_KEY ให้โปรเซส API แล้ว มิฉะนั้น admin กับ
-- director จะกลับไปเข้าระบบไม่ได้ — ดูเหตุผลเต็มในหัวของ demo-mfa-off.sql
--
-- ไฟล์นี้ไม่มีด่านตรวจฐาน เพราะการ "เปิด" ชั้นที่สองไม่ใช่การถอดมาตรการ
-- ต่างจาก demo-mfa-off.sql ที่ต้องกันไว้
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

update auth_policy
   set require_mfa_roles = '{admin,director}'
 where institution_id = '11111111-1111-1111-1111-111111111111';

select institution_id, require_mfa_roles from auth_policy;

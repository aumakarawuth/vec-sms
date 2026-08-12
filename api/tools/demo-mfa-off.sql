-- ═══════════════════════════════════════════════════════════════════
-- ปิดการบังคับยืนยันสองชั้นของวิทยาลัยตัวอย่าง — เฉพาะตอนพัฒนา
--
--   psql -f api/tools/demo-mfa-off.sql vecsms_api_test
--
-- ─── ทำไมถึงต้องมีไฟล์นี้ ───
-- นโยบายค่าเริ่มต้นคือ require_mfa_roles = {admin,director} ถ้าโปรเซส API
-- บูตมาโดยไม่มี MFA_SECRET_KEY การผูก authenticator จะล้มทุกครั้ง แล้ว
-- สองบทบาทนั้นได้แต่ challenge token ซึ่ง AuthGuard ปฏิเสธกับทุกเส้นทาง
-- — เข้าระบบไม่ได้เลยสักทาง วงจรปิดแบบเดียวกับข้อ 6 ใน CLAUDE.md
--
-- ─── นี่คือการแก้ที่ปลายเหตุโดยรู้ตัว ───
-- ทางที่ถูกคือตั้ง MFA_SECRET_KEY ให้โปรเซส API แล้วบูตใหม่
--   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
-- ไฟล์นี้มีไว้เพื่อให้กดดูหน้าจอของสองบทบาทนั้นได้ระหว่างที่ยังไม่ได้ตั้ง
--
-- ย้อนกลับด้วย demo-mfa-on.sql ข้าง ๆ ไฟล์นี้ — และต้องย้อนก่อนเสมอ
-- ถ้าจะเอาฐานนี้ไปวัดอะไรที่เกี่ยวกับการยืนยันตัวตน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ─── ด่านตรวจ ───
-- รายชื่อฐานตรงกับ SAFE_DATABASES ใน seed-demo-users.cjs
-- ปิด MFA ของ admin ในฐานจริงคือการถอดชั้นที่สองของคนที่เห็นข้อมูลทั้งวิทยาลัย
do $$
begin
  if current_database() not in ('vecsms_api_test', 'vecsms_dev', 'vecsms_demo') then
    raise exception
      'ฐาน "%" ไม่ใช่ฐานสำหรับพัฒนา — ไฟล์นี้ถอดการยืนยันสองชั้นของ admin/director',
      current_database();
  end if;
end $$;

update auth_policy
   set require_mfa_roles = '{}'
 where institution_id = '11111111-1111-1111-1111-111111111111';

select institution_id, require_mfa_roles from auth_policy;

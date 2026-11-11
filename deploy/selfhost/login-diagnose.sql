-- ตรวจว่าทำไมเข้าระบบไม่ได้ — อ่านอย่างเดียว ไม่แก้ข้อมูล ไม่แสดงค่าแฮชรหัสผ่าน
-- sudo -u postgres psql -p 5434 -f /opt/vecsms/app/deploy/selfhost/login-diagnose.sql vecsms
-- (เขียนเป็น ASCII ล้วนในส่วนคำสั่ง เพราะ psql บน Windows แปลง argv ภาษาไทยพัง — ดู CLAUDE.md)

\echo '== 1. accounts (locked / disabled / must_change / roles) =='
select i.code as institution, uc.username,
       uc.disabled_at is not null as disabled,
       uc.locked_until > now()    as locked_now,
       uc.locked_until, uc.failed_attempts, uc.must_change, uc.last_login_at,
       (select string_agg(sr.role::text, ',') from staff s join staff_role sr on sr.staff_id = s.id
         where s.person_id = uc.person_id and sr.revoked_at is null) as staff_roles
  from user_credential uc join institution i on i.id = uc.institution_id
 order by uc.last_login_at desc nulls last
 limit 20;

\echo '== 2. last 20 login attempts (reason = why it failed) =='
select attempted_at, username, succeeded, reason
  from login_attempt order by attempted_at desc limit 20;

\echo '== 3. MFA policy and enrolment =='
select i.code, ap.require_mfa_roles from auth_policy ap join institution i on i.id = ap.institution_id;
select uc.username, m.confirmed_at is not null as mfa_confirmed
  from mfa_credential m join user_credential uc on uc.person_id = m.person_id;

\echo '== 4. devices waiting for approval =='
select uc.username, d.device_label, d.approved_at is not null as approved,
       d.revoked_at is not null as revoked, d.first_seen_at
  from device_binding d join user_credential uc on uc.person_id = d.person_id
 order by d.first_seen_at desc limit 10;

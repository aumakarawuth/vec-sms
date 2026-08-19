#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# demo-reset.sh — คืนฐานทดสอบให้อยู่ในสภาพที่กดดูหน้าจอได้ทันที
#
#   bash api/tools/demo-reset.sh
#
# ─── ทำไมต้องมีไฟล์นี้ ───
# `api/test/prepare-db.sh` ล้างฐานทุกครั้งที่รัน ซึ่งจำเป็นเพราะเทสต์เขียน
# ข้อมูลจริง แต่ผลข้างเคียงคือ **บัญชีสาธิต ข้อมูลตัวอย่าง และค่าที่ผ่อน
# มาตรการเข้าสู่ระบบหายไปพร้อมกันทุกครั้ง** — ระหว่างพัฒนาจึงต้องไล่รัน
# สามคำสั่งเรียงกันเองทุกรอบ แล้วก็ลืมไปหนึ่งตัวเป็นประจำ
# อาการที่เจอบ่อยที่สุดคือ "นักศึกษาเข้าระบบไม่ได้ ขึ้นว่ารออนุมัติอุปกรณ์"
# ซึ่งไม่ใช่บั๊ก แต่เป็นค่าเริ่มต้นของ `auth_policy.bind_student_device`
# ที่กลับมาเป็น true หลังล้างฐาน
#
# ─── ไม่รัน prepare-db.sh ให้ ───
# เพราะการล้างฐานเป็นการตัดสินใจที่ควรพิมพ์เอง ไม่ใช่ผลข้างเคียงของสคริปต์
# ที่ชื่อว่า "reset demo" — รันตัวนี้หลัง prepare-db.sh หรือรันเดี่ยว ๆ
# เมื่ออยากคืนบัญชีสาธิตก็ได้ ทุกขั้นเป็น upsert จึงรันซ้ำได้เสมอ
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

DB="${1:-vecsms_api_test}"
export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5433}"
export PGUSER="${PGUSER:-postgres}"
export PGCLIENTENCODING=UTF8

# ─── ด่านตรวจ ───
# รายชื่อเดียวกับ SAFE_DATABASES ใน seed-demo-users.cjs — ไฟล์ที่เรียกต่อ
# จากนี้ใส่รหัสผ่านที่อยู่ใน repo และถอดการยืนยันสองชั้นของ admin
case "$DB" in
  vecsms_api_test|vecsms_dev|vecsms_demo) ;;
  *)
    echo "ปฏิเสธ: \"$DB\" ไม่ใช่ฐานสำหรับพัฒนา" >&2
    exit 1
    ;;
esac

run() {
  echo "▸ $2"
  psql -q -v ON_ERROR_STOP=1 -f "$ROOT/$1" "$DB" > /dev/null
}

run db/deploy/demo-data.sql   "ข้อมูลตัวอย่าง — หนึ่งห้องเรียนที่มีชีวิต"
run db/deploy/demo-users.sql  "บัญชีสาธิตเก้าบัญชี (รหัสผ่าน Demo!vec2569)"
run api/tools/demo-auth-relax.sql "ผ่อนมาตรการเข้าสู่ระบบ — ปิดการอนุมัติอุปกรณ์และ MFA"

echo ""
psql -At -c "select 'bind_student_device=' || bind_student_device
                 || '  require_mfa_roles=' || require_mfa_roles::text
               from auth_policy" "$DB"
psql -At -c "select count(*) || ' demo accounts ready'
               from user_credential where username like '%.demo'" "$DB"
echo ""
echo "เปิดหน้าจอได้เลย — student.demo / Demo!vec2569"
echo "ย้อนมาตรการกลับด้วย  psql -f api/tools/demo-auth-strict.sql $DB"

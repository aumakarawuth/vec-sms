#!/usr/bin/env bash
# สร้างฐานข้อมูลใหม่สำหรับทดสอบ API แล้วตั้งผู้ใช้ที่ไม่ใช่ superuser ให้แอปใช้
#
#   PGHOST=localhost PGPORT=5432 PGUSER=postgres bash api/test/prepare-db.sh
#
# เทสต์ต้องเริ่มจากฐานข้อมูลใหม่ทุกครั้ง เพราะ e2e เขียนข้อมูลจริง
# เช่นลงทะเบียนและออกใบแจ้งหนี้ ซึ่งรันซ้ำบนข้อมูลเดิมจะชนกับ unique constraint
set -euo pipefail

export PGCLIENTENCODING=UTF8

DB="${TEST_DB:-vecsms_api_test}"
APP_USER="${TEST_APP_USER:-apiuser}"
APP_PASS="${TEST_APP_PASS:-apipass}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_DIR="$HERE/../../db"

echo "▸ สร้างฐานข้อมูล $DB ใหม่"
psql -d postgres -q -c "drop database if exists ${DB};"
psql -d postgres -q -c "create database ${DB};"

echo "▸ รัน migrations และ seed"
for f in "$DB_DIR"/migrations/*.sql "$DB_DIR"/seed/*.sql; do
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f"
done

echo "▸ ตั้งกลุ่มสิทธิ์และผู้ใช้ของแอป"
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$DB_DIR/deploy/roles.sql" 2>/dev/null
psql -d "$DB" -q -c "drop role if exists ${APP_USER};" 2>/dev/null || true
psql -d "$DB" -q -c "create user ${APP_USER} with password '${APP_PASS}' in role app_runtime;"

# ยืนยันว่าผู้ใช้ของแอปข้าม RLS ไม่ได้ — ถ้าข้ามได้ กำแพงกันข้อมูลจะไม่ทำงานเลย
#
# หมายเหตุ: อาร์กิวเมนต์ของ psql ต้องเป็น ASCII ล้วน
# Git Bash บน Windows แปลง argv เป็น ANSI codepage (TIS-620) ก่อนส่งให้ psql.exe
# ข้อความไทยใน -c จึงเพี้ยนและ PostgreSQL ปฏิเสธว่าเป็น UTF-8 ที่ไม่ถูกต้อง
# ส่วนไฟล์ที่ส่งด้วย -f ไม่มีปัญหานี้เพราะอ่านเป็นไบต์ตรง ๆ
if [ "$(psql -d "$DB" -At -c       "select case when rolsuper or rolbypassrls then 'BYPASS' else 'ok' end          from pg_roles where rolname = '${APP_USER}'" | tr -d '\r')" != "ok" ]; then
  echo "ผู้ใช้ของแอปข้าม RLS ได้ ซึ่งทำให้กำแพงกันข้อมูลไม่ทำงาน ใช้ทดสอบไม่ได้" >&2
  exit 1
fi

echo "▸ พร้อมแล้ว — ฐานข้อมูล $DB ผู้ใช้ $APP_USER"

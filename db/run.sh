#!/usr/bin/env bash
# สร้างฐานข้อมูลใหม่ รัน migrations + seed แล้วรัน smoke test
#
#   bash db/run.sh                 ใช้ฐานข้อมูลชื่อ vecsms บนเซิร์ฟเวอร์ปัจจุบัน
#   DB=mydb bash db/run.sh         กำหนดชื่อฐานข้อมูลเอง
#   PGHOST=... PGPORT=... PGUSER=... bash db/run.sh
#
# ตัวแปร PG* มาตรฐานของ libpq ใช้ได้ทั้งหมด
set -euo pipefail

# ไฟล์ SQL เป็น UTF-8 และมีข้อความไทย — บน Windows psql จะเดา encoding
# จาก code page ของคอนโซลแล้วอ่านเพี้ยน จึงต้องประกาศให้ชัด
export PGCLIENTENCODING=UTF8

DB="${DB:-vecsms}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "▸ สร้างฐานข้อมูล $DB ใหม่"
psql -d postgres -q -c "drop database if exists ${DB};" -c "create database ${DB};"

echo "▸ รัน migrations"
for f in "$HERE"/migrations/*.sql; do
  printf '  %s\n' "$(basename "$f")"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f"
done

echo "▸ รัน seed"
for f in "$HERE"/seed/*.sql; do
  printf '  %s\n' "$(basename "$f")"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f"
done

# ─── ทำไมต้องรัน roles.sql ตรงนี้ ───
# เทสต์เกือบทุกไฟล์ `set local role app_runtime` เพื่อออกจากสิทธิ์ superuser
# (superuser ข้าม RLS ทุกกรณี เทสต์ที่ลืมสลับบทบาทจึงไม่ได้ทดสอบอะไรเลย)
# แต่ละไฟล์จึงมีท่อน `create role app_runtime if not exists` ของตัวเองไว้กัน
# ไม่ให้ล้มบนเครื่องที่ยังไม่มีบทบาท
#
# ปัญหาคือบทบาทที่สร้างแบบนั้นได้แค่ usage on schema — ไม่มีสิทธิ์ execute
# ฟังก์ชันที่ migrations ถอนจาก public ไว้ (0017) บน cluster ที่เคยรัน
# roles.sql มาก่อนจะไม่มีใครเห็นปัญหา เพราะบทบาทมีสิทธิ์ครบอยู่แล้ว
# ส่วน cluster ใหม่จะล้มที่ TEST 10 ด้วย "permission denied for function"
#
# รัน roles.sql ตรงนี้จึงตรงกับลำดับการติดตั้งจริงตาม DEPLOY-ONLINE.md
# (นำเข้าโครงสร้าง → สร้างผู้ใช้ของแอป) และทำให้เครื่องใหม่ได้ผลเหมือนเครื่องเก่า
echo "▸ สร้างกลุ่มสิทธิ์ (db/deploy/roles.sql)"
psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$HERE/deploy/roles.sql"

echo "▸ รันเทสต์"
for f in "$HERE"/tests/*.sql; do
  printf '  %s\n' "$(basename "$f")"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f" 2>&1 | sed 's/^psql:.*sql:[0-9]*: /  /'
done

echo "▸ เสร็จ"

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

echo "▸ รันเทสต์"
for f in "$HERE"/tests/*.sql; do
  printf '  %s\n' "$(basename "$f")"
  psql -d "$DB" -v ON_ERROR_STOP=1 -q -f "$f" 2>&1 | sed 's/^psql:.*sql:[0-9]*: /  /'
done

echo "▸ เสร็จ"

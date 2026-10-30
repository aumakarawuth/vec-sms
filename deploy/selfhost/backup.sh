#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# สำรองฐานข้อมูล vec-sms ทุกคืน (เรียกจาก vecsms-backup.timer)
#
# ไม่สำรองกุญแจในไฟล์เดียวกัน — dump ที่มีกุญแจติดไปด้วยคือการถอดรหัส
# เลขบัตรประชาชนให้ใครก็ตามที่ได้ไฟล์นี้ไป กุญแจต้องเก็บแยกนอกเครื่อง
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

DIR=/opt/vecsms/backups
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$DIR/vecsms_$STAMP.dump"

mkdir -p "$DIR"
# รูปแบบ custom บีบอัดในตัวและกู้คืนทีละตารางได้ · nice/ionice ให้ระบบสอบได้ก่อน
nice -n 10 ionice -c3 pg_dump -p 5434 -U postgres -Fc -f "$OUT.part" vecsms
mv "$OUT.part" "$OUT"
chmod 600 "$OUT"

# ไฟล์ที่ pg_restore อ่านไม่ได้ ไม่ใช่ข้อมูลสำรอง
pg_restore -l "$OUT" > /dev/null

find "$DIR" -name 'vecsms_*.dump' -mtime +"$KEEP_DAYS" -delete
echo "สำรองแล้ว $OUT ($(du -h "$OUT" | cut -f1))"

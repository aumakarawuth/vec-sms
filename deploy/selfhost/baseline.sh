#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# บันทึกว่าฐานข้อมูลอยู่ที่ migration ไหนแล้ว — ใช้ครั้งเดียวกับฐานที่นำเข้า
# จาก db/dist/vec-sms-schema.sql (ไฟล์นั้นไม่บันทึก schema_migrations)
#
#   sudo bash /opt/vecsms/app/deploy/selfhost/baseline.sh 0095
#
# ─── ทำไมต้องมี ───
# install.sh รุ่นแรกนำเข้าโครงสร้างจากไฟล์ dist ซึ่งสร้างทุกตารางครบ แต่
# schema_migrations ว่างเปล่า ถ้ารัน db/deploy.sh ทั้งสภาพนี้ มันจะเห็นว่า
# ยังไม่เคยใช้ migration ไหนเลย แล้วไล่รันตั้งแต่ 0001 ทับฐานที่มีข้อมูล
#
# ─── ทำไมต้องพิมพ์เลขเอง ไม่เดาให้ ───
# การบันทึกผิดเลขพังได้สองทาง ระบุต่ำไปจะรัน migration ซ้ำ ระบุสูงไปจะข้าม
# migration ที่ยังไม่เคยรันแล้วสคีมาขาดไปเงียบ ๆ — เลขต้องมาจากหัวไฟล์ dist
# ที่ใช้ติดตั้งจริง (บรรทัด "migration ล่าสุด") ไม่ใช่จากไฟล์ที่ดึงมาทีหลัง
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

APP=/opt/vecsms/app
URL='postgresql:///vecsms?host=/var/run/postgresql&port=5434'
UPTO="${1:-}"

[ "$(id -u)" -eq 0 ] || { echo "ต้องรันด้วย sudo" >&2; exit 1; }
[[ "$UPTO" =~ ^[0-9]{4}$ ]] || { echo "ใช้: baseline.sh <เลข migration 4 หลัก เช่น 0095>" >&2; exit 1; }
ls "$APP"/db/migrations/"$UPTO"_*.sql >/dev/null 2>&1 || { echo "ไม่มีไฟล์ migration $UPTO" >&2; exit 1; }

q() { sudo -u postgres psql "$URL" -v ON_ERROR_STOP=1 -qAt "$@"; }

sudo -u postgres psql "$URL" -v ON_ERROR_STOP=1 -q -f "$APP/db/migrations/0000_migrations.sql" >/dev/null
n="$(q -c 'select count(*) from schema_migrations')"
[ "$n" = "0" ] || { echo "schema_migrations มี $n แถวแล้ว — ไม่ต้อง baseline (ใช้ upgrade.sh)" >&2; exit 1; }
[ "$(q -c "select to_regclass('public.institution') is not null")" = "t" ] \
  || { echo "ฐานยังว่าง — ใช้ install.sh ไม่ใช่ baseline" >&2; exit 1; }

echo "จะบันทึกว่า migration ตั้งแต่ 0001 ถึง $UPTO ถูกใช้แล้ว (ไม่รันอะไรจริง)"
read -r -p "พิมพ์ $UPTO อีกครั้งเพื่อยืนยัน: " again
[ "$again" = "$UPTO" ] || { echo "ยกเลิก"; exit 1; }

count=0
for f in "$APP"/db/migrations/*.sql; do
  v="$(basename "$f" .sql)"
  [ "$v" = "0000_migrations" ] && continue
  [ "${v%%_*}" \> "$UPTO" ] && break
  sum="$(sha256sum "$f" | cut -d' ' -f1)"
  q -c "insert into schema_migrations (version, checksum, applied_by) values ('$v', '$sum', 'baseline')" >/dev/null
  count=$((count + 1))
done
echo "บันทึกแล้ว $count ไฟล์ — จากนี้ใช้ upgrade.sh ได้"

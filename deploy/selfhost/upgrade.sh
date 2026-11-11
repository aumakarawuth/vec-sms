#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# อัปเดต vec-sms ที่ติดตั้งแล้ว — ดึงโค้ด · สำรอง · ไล่ migration · build · restart
#
#   sudo bash /opt/vecsms/app/deploy/selfhost/upgrade.sh
#
# ─── ลำดับที่ตั้งใจ ───
# สำรองฐานข้อมูลก่อนแตะสคีมาเสมอ — migration ย้อนกลับไม่ได้ ทางถอยทางเดียว
# คือไฟล์สำรองที่ทำก่อนหน้านั้นไม่กี่วินาที ถ้าสำรองไม่ผ่านจะไม่ทำต่อ
#
# migration ล้มกลางทาง → deploy.sh หยุดทันทีและไม่บันทึกไฟล์นั้นว่าใช้แล้ว
# API ยังรันโค้ดเดิมต่อ ไม่ restart จนกว่าทุกไฟล์จะผ่าน · ไฟล์ส่วนใหญ่ครอบ
# begin/commit ของตัวเองจึงไม่ค้างครึ่งไฟล์ แต่บางไฟล์ (เช่น 0095 ที่เพิ่มค่า
# enum) ทำนอกทรานแซกชันโดยจำเป็น — ถ้าล้มที่ไฟล์แบบนั้น ให้กู้จากไฟล์สำรอง
#
# ไม่แตะ examkub · cloudflared · cluster 18/main เลย
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

APP=/opt/vecsms/app
URL='postgresql:///vecsms?host=/var/run/postgresql&port=5434'
WEB_ID_FILE=/etc/vecsms/web-institution-id

say() { printf '\n▸ %s\n' "$*"; }
die() { printf '\n✕ %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "ต้องรันด้วย sudo"

q() { sudo -u postgres psql "$URL" -v ON_ERROR_STOP=1 -qAt "$@"; }

# ─── กันฐานที่ยังไม่ได้ baseline ───
tracked="$(q -c "select case when to_regclass('public.schema_migrations') is null then 0 else (select count(*) from schema_migrations) end")"
[ "$tracked" != "0" ] || die "schema_migrations ว่าง — ฐานนี้นำเข้าจากไฟล์ dist รัน baseline.sh ก่อน (ดู README.md)"

say "ดึงโค้ด"
before="$(sudo -u vecsms git -C "$APP" rev-parse --short HEAD)"
sudo -u vecsms git -C "$APP" pull --ff-only
after="$(sudo -u vecsms git -C "$APP" rev-parse --short HEAD)"
echo "  $before → $after"

say "migration ที่จะใช้"
sudo -u postgres env DATABASE_URL="$URL" DRY_RUN=1 bash "$APP/db/deploy.sh" | sed 's/^/  /'

say "สำรองฐานข้อมูลก่อนแตะสคีมา"
sudo -u postgres bash "$APP/deploy/selfhost/backup.sh"

say "ไล่ migration"
sudo -u postgres env DATABASE_URL="$URL" bash "$APP/db/deploy.sh" | sed 's/^/  /'

say "สิทธิ์ของแอปกับตาราง/ฟังก์ชันใหม่ (roles.sql รันซ้ำได้)"
sudo -u postgres psql "$URL" -v ON_ERROR_STOP=1 -q -f "$APP/db/deploy/roles.sql"

say "build API"
sudo -u vecsms bash -c "cd '$APP/api' && npm ci --no-audit --no-fund && npm run build"

# unit ของ systemd อาจเปลี่ยนมากับโค้ด — คัดลอกทับทุกครั้ง
install -m 644 "$APP/deploy/selfhost/vecsms-api.service"    /etc/systemd/system/
install -m 644 "$APP/deploy/selfhost/vecsms-backup.service" /etc/systemd/system/
install -m 644 "$APP/deploy/selfhost/vecsms-backup.timer"   /etc/systemd/system/
systemctl daemon-reload

say "restart API"
systemctl restart vecsms-api
for _ in $(seq 1 30); do curl -fs http://127.0.0.1:3100/api/v1/health >/dev/null && break; sleep 1; done
curl -fs http://127.0.0.1:3100/api/v1/health || die "API ไม่ขึ้นหลังอัปเดต — ดู journalctl -u vecsms-api -n 60 (ฐานสำรองอยู่ที่ /opt/vecsms/backups)"
echo

if [ -f "$WEB_ID_FILE" ]; then
  say "build หน้าจอเจ้าหน้าที่"
  bash "$APP/deploy/selfhost/build-web.sh" "$(cat "$WEB_ID_FILE")"
else
  say "ข้าม build หน้าจอ — ยังไม่เคยรัน build-web.sh"
fi

say "เสร็จ — $before → $after"

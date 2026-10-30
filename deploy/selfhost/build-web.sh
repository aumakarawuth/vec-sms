#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# build หน้าจอเจ้าหน้าที่แล้ววางที่ /opt/vecsms/www
#
#   sudo bash /opt/vecsms/app/deploy/selfhost/build-web.sh <institution-id>
#
# แยกจาก install.sh เพราะ VITE_INSTITUTION_ID ฝังตอน build และรู้ได้
# หลังเปิดวิทยาลัยแล้วเท่านั้น (ไม่มีหน้าเลือกวิทยาลัยตอนล็อกอินโดยตั้งใจ
# มิฉะนั้นหน้าล็อกอินจะกลายเป็นรายชื่อลูกค้าทั้งหมด — ดู CLAUDE.md)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

ID="${1:-}"
[[ "$ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
  || { echo "ใช้: build-web.sh <institution-id แบบ UUID>" >&2; exit 1; }

APP=/opt/vecsms/app
sudo -u vecsms bash -c "cd '$APP/web' && npm ci --no-audit --no-fund && \
  VITE_API_BASE_URL=https://vec.examkub.com/api/v1 VITE_INSTITUTION_ID='$ID' npm run build"

# สลับทั้งโฟลเดอร์ทีเดียว — คนที่เปิดหน้าอยู่ไม่เจอไฟล์ครึ่งเก่าครึ่งใหม่
rm -rf /opt/vecsms/www.new
cp -r "$APP/web/dist" /opt/vecsms/www.new
chown -R vecsms:vecsms /opt/vecsms/www.new
rm -rf /opt/vecsms/www.old
[ -d /opt/vecsms/www ] && mv /opt/vecsms/www /opt/vecsms/www.old
mv /opt/vecsms/www.new /opt/vecsms/www
# จำไว้ให้ upgrade.sh build ใหม่ได้เองโดยไม่ต้องถามรหัสวิทยาลัยซ้ำ
install -d -m 755 /etc/vecsms
printf '%s\n' "$ID" > /etc/vecsms/web-institution-id
echo "วางหน้าจอแล้วที่ /opt/vecsms/www"

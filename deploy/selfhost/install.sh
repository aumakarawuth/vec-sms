#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# ติดตั้ง vec-sms บนเครื่องเดียวกับ examkub (Ubuntu 24.04)
#
#   sudo bash /opt/vecsms/app/deploy/selfhost/install.sh
#
# รันซ้ำได้ — ทุกขั้นข้ามตัวเองถ้าทำไปแล้ว
#
# ─── สิ่งที่สคริปต์นี้ตั้งใจไม่ทำ ───
# · ไม่แตะ /opt/examkub · cluster PostgreSQL ของ examkub · service ของ examkub
# · ไม่ติดตั้งหรืออัปเกรด Node — examkub ใช้ Node ตัวเดียวกันบนเครื่อง
#   อัปเกรดให้ vec-sms คือการเปลี่ยนรันไทม์ของระบบสอบไปด้วยโดยไม่มีใครทดสอบ
# · ไม่เปิดใช้ไฟล์ Nginx และไม่ reload — Nginx เป็นของที่ระบบสอบวิ่งผ่าน
#   ทุกคำขอ จึงแยกเป็นขั้นที่คนสั่งเองหลังอ่านไฟล์แล้ว (ดู README.md)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

APP=/opt/vecsms/app
ENV_FILE=/etc/vecsms/vecsms.env
PG_VER=18
PG_CLUSTER=vecsms
PG_PORT=5434
DB=vecsms
APP_DB_USER=vecsms_app

say() { printf '\n▸ %s\n' "$*"; }
die() { printf '\n✕ %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "ต้องรันด้วย sudo"
[ -f "$APP/api/package.json" ] || die "ไม่พบโค้ดที่ $APP — clone repo ไว้ที่นั่นก่อน (ดู README.md)"

# ─── Node ──────────────────────────────────────────────────────────
say "ตรวจ Node (ใช้ตัวที่มีอยู่แล้ว ไม่ติดตั้งเพิ่ม)"
command -v node >/dev/null || die "ไม่พบ node"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 22 ] || die "ต้องใช้ Node 22 ขึ้นไป พบ $(node -v) — ไม่อัปเกรดให้เพราะ examkub ใช้ตัวเดียวกัน"
echo "  $(node -v)"

# ─── PostgreSQL 18 แยก cluster ───────────────────────────────────────
say "ตรวจ PostgreSQL $PG_VER"
if [ ! -x "/usr/lib/postgresql/$PG_VER/bin/postgres" ]; then
  # ติดตั้งแพ็กเกจรุ่น 18 ข้างรุ่นเดิม — ไม่ลบหรืออัปเกรด cluster ที่มีอยู่
  # postgresql-common จัดการหลายรุ่นพร้อมกันได้อยู่แล้ว
  die "ยังไม่มี PostgreSQL $PG_VER — ติดตั้งตามขั้นที่ 2 ใน README.md ก่อน แล้วรันสคริปต์นี้ใหม่"
fi

if ! pg_lsclusters -h | awk '{print $1"/"$2}' | grep -qx "$PG_VER/$PG_CLUSTER"; then
  say "สร้าง cluster $PG_VER/$PG_CLUSTER ที่พอร์ต $PG_PORT"
  pg_lsclusters -h | awk '{print $3}' | grep -qx "$PG_PORT" && die "พอร์ต $PG_PORT ถูกใช้แล้ว"
  pg_createcluster "$PG_VER" "$PG_CLUSTER" --port "$PG_PORT" --encoding UTF8 --locale C.UTF-8
  install -m 644 "$APP/deploy/selfhost/postgresql-vecsms.conf" "/etc/postgresql/$PG_VER/$PG_CLUSTER/conf.d/vecsms.conf"
fi
systemctl enable --now "postgresql@$PG_VER-$PG_CLUSTER"

psql_su() { sudo -u postgres psql -p "$PG_PORT" -v ON_ERROR_STOP=1 -q "$@"; }

# ─── ฐานข้อมูลและโครงสร้าง ─────────────────────────────────────────
if ! psql_su -tAc "select 1 from pg_database where datname = '$DB'" postgres | grep -q 1; then
  say "สร้างฐานข้อมูล $DB"
  psql_su -c "create database $DB" postgres
fi

if ! psql_su -tAc "select to_regclass('public.institution') is not null" "$DB" | grep -q t; then
  say "นำเข้าโครงสร้าง (vec-sms-schema.sql — ไม่ใช่ full ที่มีวิทยาลัยสมมติ)"
  psql_su -f "$APP/db/dist/vec-sms-schema.sql" "$DB"
fi

say "ตั้งกลุ่มสิทธิ์ (roles.sql)"
psql_su -f "$APP/db/deploy/roles.sql" "$DB"

# ─── ไฟล์ความลับ ─────────────────────────────────────────────────────
# สุ่มบนเครื่องนี้เอง ไม่ผ่านแชต ไม่ผ่านรีโป และไม่พิมพ์ออกหน้าจอ
if [ ! -f "$ENV_FILE" ]; then
  say "สร้าง $ENV_FILE พร้อมสุ่มความลับ"
  install -d -m 700 /etc/vecsms
  rnd() { openssl rand -base64 32 | tr -d '\n'; }
  DB_PASS="$(openssl rand -hex 24)"
  sed -e "s#vecsms_app:CHANGE_ME@#$APP_DB_USER:$DB_PASS@#" "$APP/deploy/selfhost/vecsms.env.example" > "$ENV_FILE.tmp"
  for k in JWT_SECRET IP_HASH_SECRET PROVISION_KEY MFA_SECRET_KEY NATIONAL_ID_KEY; do
    v="$(rnd)"; sed -i "s#^$k=CHANGE_ME\$#$k=$v#" "$ENV_FILE.tmp"
  done
  grep -q CHANGE_ME "$ENV_FILE.tmp" && die "ยังมีค่า CHANGE_ME เหลือใน $ENV_FILE.tmp"
  chmod 600 "$ENV_FILE.tmp"; mv "$ENV_FILE.tmp" "$ENV_FILE"
  psql_su -c "create user $APP_DB_USER with password '$DB_PASS' in role app_runtime" "$DB"
  echo "  ✱ สำรอง MFA_SECRET_KEY และ NATIONAL_ID_KEY จาก $ENV_FILE ไว้นอกเครื่องตอนนี้เลย"
fi

# ─── ผู้ใช้ระบบและการ build ───────────────────────────────────────────
id vecsms >/dev/null 2>&1 || useradd --system --home /opt/vecsms --shell /usr/sbin/nologin vecsms
install -d -o vecsms -g vecsms /opt/vecsms/run /opt/vecsms/www
install -d -o postgres -g postgres -m 700 /opt/vecsms/backups
chown -R vecsms:vecsms "$APP"

say "build API (tsc เท่านั้น — esbuild ไม่ปล่อย metadata ที่ NestJS ใช้)"
sudo -u vecsms bash -c "cd '$APP/api' && npm ci --no-audit --no-fund && npm run build"

# ─── systemd ───────────────────────────────────────────────────────
say "ติดตั้ง service"
install -m 644 "$APP/deploy/selfhost/vecsms-api.service"    /etc/systemd/system/
install -m 644 "$APP/deploy/selfhost/vecsms-backup.service" /etc/systemd/system/
install -m 644 "$APP/deploy/selfhost/vecsms-backup.timer"   /etc/systemd/system/
chmod 755 "$APP/deploy/selfhost/backup.sh"
systemctl daemon-reload
systemctl enable --now vecsms-backup.timer
systemctl enable vecsms-api
systemctl restart vecsms-api

say "รอ API ขึ้น"
for _ in $(seq 1 30); do
  curl -fs http://127.0.0.1:3100/api/v1/health >/dev/null && break
  sleep 1
done
curl -fs http://127.0.0.1:3100/api/v1/health || die "API ไม่ขึ้น — ดู journalctl -u vecsms-api -n 50"
echo

# ─── Nginx: วางไฟล์ไว้เฉย ๆ ไม่เปิดใช้ ─────────────────────────────────
install -m 644 "$APP/deploy/selfhost/nginx-vec.examkub.com.conf" /etc/nginx/sites-available/vec.examkub.com
say "เสร็จ — API ฟังอยู่ที่ 127.0.0.1:3100 เท่านั้น ยังไม่เปิดสู่ภายนอก"
echo "  ขั้นต่อไปคือขั้นที่ 5 ใน README.md (เปิด Nginx) ซึ่งต้องสั่งเอง"

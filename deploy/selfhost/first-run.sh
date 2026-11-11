#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# ตั้งค่าครั้งแรกหลังติดตั้ง — ถามทีละช่องแทนการพิมพ์ curl ยาว ๆ
#
#   sudo bash /opt/vecsms/app/deploy/selfhost/first-run.sh
#
# ทำไมต้องมี — คำสั่ง curl ที่มี JSON ภาษาไทยเพี้ยนง่ายตอนคัดลอกวาง
# (อักขระหาย · เครื่องหมายคำพูดไม่ครบแล้ว shell ค้าง) และการ export
# PROVISION_KEY ไว้ใน shell ทำให้กุญแจค้างใน history กับ environment
# สคริปต์นี้อ่านกุญแจจากไฟล์เอง และอ่านรหัสผ่านแบบไม่แสดงบนจอ
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

ENV_FILE=/etc/vecsms/vecsms.env
BASE="${VECSMS_BASE:-http://127.0.0.1:3100/api/v1}"

[ "$(id -u)" -eq 0 ] || { echo "ต้องรันด้วย sudo" >&2; exit 1; }
KEY="$(grep '^PROVISION_KEY=' "$ENV_FILE" | cut -d= -f2-)"
[ -n "$KEY" ] || { echo "ไม่พบ PROVISION_KEY ใน $ENV_FILE" >&2; exit 1; }

ask()    { local v; read -r -p "  $1: " v; printf '%s' "$v"; }
secret() {
  local a b
  while true; do
    # || exit — set -e ไม่มีผลใน $(...) ถ้า input หมดกลางทางจะวนถามไม่รู้จบ
    read -r -s -p "  $1 (ไม่แสดงบนจอ): " a || exit 1; echo >&2
    read -r -s -p "  พิมพ์ซ้ำ: " b || exit 1; echo >&2
    [ "$a" = "$b" ] && [ "${#a}" -ge "$2" ] && { printf '%s' "$a"; return; }
    echo "  ✕ ไม่ตรงกัน หรือสั้นกว่า $2 ตัวอักษร ลองใหม่" >&2
  done
}

# ส่ง JSON ด้วย node — ประกอบ JSON ใน bash แล้วชื่อที่มีเครื่องหมายคำพูดจะพัง
# ค่าที่ขึ้นต้นด้วย # คือตัวเลข · คืนค่าเป็น JSON ของผลลัพธ์ หรือออกด้วย error
post() {
  local path="$1"; shift
  # --input-type=module เพราะสคริปต์จาก stdin เป็น CommonJS โดยค่าเริ่มต้น ซึ่งใช้ await ระดับบนสุดไม่ได้
  node --input-type=module - "$BASE$path" "$KEY" "$@" <<'JS'
const [url, key, ...pairs] = process.argv.slice(2);
const body = {};
for (const p of pairs) {
  const i = p.indexOf('=');
  const k = p.slice(0, i), v = p.slice(i + 1);
  if (v !== '') body[k] = v.startsWith('#') ? Number(v.slice(1)) : v;
}
const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', 'x-provision-key': key }, body: JSON.stringify(body) });
const text = await r.text();
if (!r.ok) { console.error(`  ✕ ${r.status}: ${text}`); process.exit(1); }
process.stdout.write(text);
JS
}
field() { node -e 'const o=JSON.parse(process.argv[1]);console.log(o[process.argv[2]] ?? "")' "$1" "$2"; }

echo
echo "══ 1/3 บัญชีผู้ให้บริการ (ทำได้ครั้งเดียวตลอดอายุระบบ) ══"
read -r -p "  ทำขั้นนี้ไหม (y = ทำ · n = ข้าม เพราะเคยทำแล้ว): " yn
if [ "$yn" = "y" ]; then
  U="$(ask 'ชื่อผู้ใช้ เช่น vendor.owner')"
  N="$(ask 'ชื่อที่แสดง')"
  R="$(post /platform/bootstrap "username=$U" "displayName=$N")"
  CODE="$(node -e 'const o=JSON.parse(process.argv[1]);console.log(o.setupCode ?? o.code ?? "")' "$R")"
  [ -n "$CODE" ] || { echo "  ✕ ไม่พบรหัสตั้งค่าในผลลัพธ์: $R" >&2; exit 1; }
  # วนถามจนผ่าน — รหัสตั้งค่าออกได้ครั้งเดียว ถ้าจบสคริปต์ตรงนี้จะรันซ้ำไม่ได้
  until P="$(secret 'รหัสผ่านใหม่ อย่างน้อย 12 ตัว' 12)" && post /platform/setup "username=$U" "code=$CODE" "newPassword=$P" >/dev/null; do
    echo "  ลองรหัสผ่านอื่น" >&2
  done
  echo "  ✓ ตั้งรหัสผ่าน $U แล้ว — ล็อกอินครั้งแรกจะบังคับผูกแอป authenticator"
fi

echo
echo "══ 2/3 เปิดวิทยาลัย ══"
CODE10="$(ask 'รหัสสถานศึกษา 10 หลัก')"
NAME="$(ask 'ชื่อวิทยาลัย')"
FN="$(ask 'ชื่อผู้ดูแลระบบของวิทยาลัย')"
LN="$(ask 'นามสกุลผู้ดูแล')"
AU="$(ask 'ชื่อผู้ใช้ของผู้ดูแล เช่น admin')"
YB="$(ask 'ปีการศึกษา พ.ศ. เช่น 2569')"
YS="$(ask 'วันเริ่มปีการศึกษา ค.ศ. เช่น 2026-05-16')"
YE="$(ask 'วันสิ้นสุดปีการศึกษา ค.ศ. เช่น 2027-03-31')"
R="$(post /provisioning/institutions "code=$CODE10" "nameTh=$NAME" "adminFirstNameTh=$FN" "adminLastNameTh=$LN" \
      "adminUsername=$AU" "yearBe=#$YB" "yearStartsOn=$YS" "yearEndsOn=$YE")"
IID="$(field "$R" institutionId)"
RC="$(field "$R" resetCode)"
echo "  ✓ เปิดวิทยาลัยแล้ว  institutionId = $IID"

echo
echo "══ 3/3 ตั้งรหัสผ่านผู้ดูแลวิทยาลัย ══"
echo "  ห้ามมีชื่อผู้ใช้อยู่ในรหัสผ่าน · รหัสรีเซ็ตหมดอายุใน 30 นาที"
# วนถามจนผ่าน — วิทยาลัยเปิดไปแล้ว รันสคริปต์ซ้ำจะชนรหัสสถานศึกษาเดิม
until P="$(secret "รหัสผ่านใหม่ของ $AU อย่างน้อย 8 ตัว" 8)" && post /auth/reset-password "institutionId=$IID" "username=$AU" "code=$RC" "newPassword=$P" >/dev/null; do
  echo "  ลองรหัสผ่านอื่น" >&2
done
echo "  ✓ ตั้งรหัสผ่าน $AU แล้ว"

echo
echo "เสร็จ — จดค่านี้ไว้ใช้ขั้นที่ 7–8:"
echo "  institutionId    = $IID"
echo "  รหัสสถานศึกษา    = $CODE10"
echo "  ปีการศึกษา       = $YB"

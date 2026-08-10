#!/usr/bin/env bash
# ใช้ migration ที่ยังไม่เคยใช้ กับฐานข้อมูลปลายทาง — รันซ้ำได้ปลอดภัย
#
#   DATABASE_URL="postgres://user:pass@host:5432/dbname" bash db/deploy.sh
#   DATABASE_URL="..." WITH_DEMO=1 bash db/deploy.sh     รวมข้อมูลตัวอย่างด้วย
#   DATABASE_URL="..." DRY_RUN=1  bash db/deploy.sh      ดูว่าจะทำอะไรบ้าง ไม่เขียนจริง
#
# ต่างจาก run.sh ตรงที่ไฟล์นี้ไม่ลบฐานข้อมูล แต่เติมเฉพาะส่วนที่ยังไม่มี
# จึงใช้กับระบบที่มีข้อมูลจริงอยู่แล้วได้
set -euo pipefail

# ไฟล์ SQL ทั้งหมดเป็น UTF-8 และมีข้อความไทย
# บน Windows psql จะเดา client encoding จาก code page ของคอนโซล (มักเป็น WIN874)
# แล้วอ่านภาษาไทยเพี้ยน จึงต้องประกาศให้ชัด
export PGCLIENTENCODING=UTF8

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-0}"
WITH_DEMO="${WITH_DEMO:-0}"

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ต้องกำหนด DATABASE_URL ก่อน เช่น" >&2
  echo '  DATABASE_URL="postgres://user:pass@host:5432/vecsms" bash db/deploy.sh' >&2
  exit 2
fi

PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q)

# ── ตรวจการเชื่อมต่อและเวอร์ชัน ────────────────────────────────────
server_version="$("${PSQL[@]}" -At -c "show server_version_num" 2>/dev/null)" || {
  echo "เชื่อมต่อฐานข้อมูลไม่ได้ ตรวจสอบ DATABASE_URL" >&2
  exit 1
}
# ─── ทำไมเป็น 18 ไม่ใช่ 15 ───
# สคีมาเองใช้งานได้ตั้งแต่ 15 (pgcrypto · btree_gist · security_invoker บน view)
# แต่เกณฑ์นี้ไม่ได้ถามว่า "SQL รันผ่านไหม" — ถามว่า "รุ่นนี้ถูกวัดแล้วหรือยัง"
#
# บน 16 ตัวจัดตารางอัตโนมัติใช้เวลา 14.6 วินาทีจนชน statement_timeout
# ส่วนบน 18 ใช้ 90 มิลลิวินาที ด้วยข้อมูลชุดเดียวกันและสถิติของตัววางแผน
# ที่ว่างเปล่าเหมือนกัน — ต่างกันแค่รุ่น เพราะสคีมานี้กางนโยบาย RLS ออกเป็น
# เงื่อนไขซ้อนกันทุกคำสั่ง ซึ่งเป็นรูปแบบที่ 16 วางแผนได้แย่กว่ามาก
# (ดูข้อ 12 ในรายการที่เคยพังแบบเงียบ ๆ ใน CLAUDE.md)
#
# 17 ไม่เคยวัด จึงไม่ผ่านเช่นกัน — ปล่อยผ่านสิ่งที่ไม่เคยวัดคือการทำซ้ำ
# ความผิดพลาดเดิมที่ทำให้ CI ตรวจรุ่นที่ไม่มีใครรันอยู่หลายเดือน
# ถ้าจะลดเกณฑ์นี้ ต้องวัด API-71/API-72 บนรุ่นนั้นก่อน ไม่ใช่แก้ตัวเลขที่นี่
if [ "$server_version" -lt 180000 ]; then
  echo "ต้องใช้ PostgreSQL 18 ขึ้นไป (พบ $server_version)" >&2
  echo "รุ่นเก่ากว่านี้รัน SQL ผ่านได้ แต่วางแผนคำสั่งที่กาง RLS ได้แย่กว่ามาก" >&2
  echo "จนเส้นทางที่หนักที่สุดชน statement_timeout — ดู CLAUDE.md ข้อ 12" >&2
  exit 1
fi
printf '▸ เชื่อมต่อสำเร็จ — PostgreSQL %s\n' \
  "$("${PSQL[@]}" -At -c "show server_version")"

# ── สร้างตารางติดตาม migration ─────────────────────────────────────
if [ "$DRY_RUN" = "0" ]; then
  "${PSQL[@]}" -f "$HERE/migrations/0000_migrations.sql" >/dev/null
fi

applied_checksum() {
  "${PSQL[@]}" -At -c "select checksum from schema_migrations where version = '$1'" 2>/dev/null || true
}

checksum_of() {
  sha256sum "$1" | cut -d' ' -f1
}

# ── ใช้ migration ที่ยังไม่เคยใช้ ───────────────────────────────────
pending=0
skipped=0

for f in "$HERE"/migrations/*.sql; do
  version="$(basename "$f" .sql)"
  [ "$version" = "0000_migrations" ] && continue

  sum="$(checksum_of "$f")"
  prev="$(applied_checksum "$version")"

  if [ -n "$prev" ]; then
    if [ "$prev" != "$sum" ]; then
      echo "" >&2
      echo "หยุด: $version ถูกใช้ไปแล้วแต่ไฟล์ถูกแก้ภายหลัง" >&2
      echo "  checksum ที่บันทึกไว้ $prev" >&2
      echo "  checksum ของไฟล์ตอนนี้ $sum" >&2
      echo "" >&2
      echo "การแก้ migration ที่ deploy ไปแล้วทำให้ฐานข้อมูลแต่ละเครื่องไม่ตรงกัน" >&2
      echo "ให้เขียน migration ใหม่เป็นไฟล์ถัดไปแทนการแก้ไฟล์เดิม" >&2
      exit 1
    fi
    skipped=$((skipped + 1))
    continue
  fi

  pending=$((pending + 1))
  if [ "$DRY_RUN" = "1" ]; then
    printf '  จะใช้  %s\n' "$version"
    continue
  fi

  printf '  ใช้    %s' "$version"
  start=$(date +%s%3N 2>/dev/null || echo 0)
  "${PSQL[@]}" -f "$f"
  end=$(date +%s%3N 2>/dev/null || echo 0)
  ms=$(( end > start ? end - start : 0 ))

  "${PSQL[@]}" -c "insert into schema_migrations (version, checksum, duration_ms)
                   values ('$version', '$sum', $ms)" >/dev/null
  printf '  (%s ms)\n' "$ms"
done

if [ "$DRY_RUN" = "1" ]; then
  printf '▸ ทดลองรัน — จะใช้ %s ไฟล์ ข้าม %s ไฟล์ที่ทำไปแล้ว\n' "$pending" "$skipped"
  exit 0
fi

if [ "$pending" -eq 0 ]; then
  printf '▸ ฐานข้อมูลเป็นเวอร์ชันล่าสุดอยู่แล้ว (ข้าม %s ไฟล์)\n' "$skipped"
else
  printf '▸ ใช้ migration ใหม่ %s ไฟล์ (ข้าม %s ไฟล์)\n' "$pending" "$skipped"
fi

# ── ข้อมูลตัวอย่าง (ต้องสั่งเอง) ────────────────────────────────────
if [ "$WITH_DEMO" = "1" ]; then
  existing="$("${PSQL[@]}" -At -c "select count(*) from institution")"
  if [ "$existing" != "0" ]; then
    printf '▸ ข้ามข้อมูลตัวอย่าง — มีสถานศึกษาในระบบแล้ว %s แห่ง\n' "$existing"
  else
    echo "▸ นำเข้าข้อมูลตัวอย่าง"
    for f in "$HERE"/seed/*.sql; do
      printf '  %s\n' "$(basename "$f")"
      "${PSQL[@]}" -f "$f"
    done
  fi
fi

# ── สรุปสถานะ ───────────────────────────────────────────────────────
"${PSQL[@]}" -c "
select
  (select count(*) from schema_migrations)                            as migrations,
  (select count(*) from pg_tables  where schemaname = 'public')       as tables,
  (select count(*) from pg_views   where schemaname = 'public')       as views,
  (select count(*) from pg_policies where schemaname = 'public')      as rls_policies,
  (select count(*) from institution)                                  as institutions"

echo "▸ เสร็จ"

# คู่มือติดตั้งและ deploy

ฐานข้อมูลระบบบริหารวิทยาลัยอาชีวศึกษาเอกชน — แกนหลักสูตร การวัดผล และการลงทะเบียน

**ต้องการ** PostgreSQL 15 ขึ้นไป (ใช้ `pgcrypto`, `btree_gist` และ `security_invoker` บน view)
ทดสอบแล้วบน PostgreSQL 18.4

---

## เลือกวิธีที่ตรงกับสถานการณ์

| สถานการณ์ | ใช้วิธี | เวลาที่ใช้ |
|---|---|---|
| อยากลองดูก่อนว่าระบบเป็นยังไง | Docker Compose | 2 นาที |
| มีฐานข้อมูลอยู่แล้ว อยากนำเข้าผ่านหน้าจอ | นำเข้าไฟล์เดียว | 5 นาที |
| ขึ้นระบบจริง และต้องอัปเกรดได้ในอนาคต | `deploy.sh` | 10 นาที |
| ใช้ Supabase / Neon / Railway | นำเข้าไฟล์เดียว หรือ `deploy.sh` | 10 นาที |

---

## วิธีที่ 1 — Docker Compose

เหมาะกับการทดลองใช้ การสาธิตให้ผู้บริหารดู และเครื่องของนักพัฒนา

```bash
cd db
cp .env.example .env
```

แก้ `.env` ใส่รหัสผ่าน (สุ่มด้วย `openssl rand -base64 32`) แล้ว

```bash
bash build.sh
docker compose up -d
```

ครั้งแรกที่ container ขึ้น ระบบจะนำเข้าโครงสร้างและข้อมูลตัวอย่างให้อัตโนมัติ
เชื่อมต่อได้ที่ `postgres://vecsms:<รหัสผ่าน>@localhost:5432/vecsms`

**สำหรับระบบจริง** ตั้ง `INIT_SQL=vec-sms-schema.sql` ใน `.env` ก่อนสั่ง `up`
เพื่อไม่ให้มีวิทยาลัยสมมติปนอยู่ในฐานข้อมูล

ตัวเลือกเสริม

```bash
docker compose --profile tools up -d     # เปิด pgAdmin ที่ http://localhost:5050
docker compose --profile backup up -d    # สำรองข้อมูลรายวัน เก็บย้อนหลัง 14 วัน
```

---

## วิธีที่ 2 — นำเข้าไฟล์เดียว

ไฟล์ใน `dist/` เป็น SQL ล้วน ไม่มีคำสั่งเฉพาะ psql จึงวางลง pgAdmin, DBeaver,
Supabase SQL Editor หรือ query editor อะไรก็ได้

| ไฟล์ | ใช้เมื่อ |
|---|---|
| `vec-sms-schema.sql` | **ระบบจริง** — โครงสร้างอย่างเดียว ไม่มีข้อมูลใด ๆ |
| `vec-sms-demo-data.sql` | เติมข้อมูลตัวอย่างทีหลัง (ต้องนำเข้า schema ก่อน) |
| `vec-sms-full.sql` | ทดลองใช้ — โครงสร้าง + ข้อมูลตัวอย่าง จบในไฟล์เดียว |

ผ่านบรรทัดคำสั่ง

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f dist/vec-sms-schema.sql
```

ตรวจว่าไฟล์ไม่เสียหายระหว่างส่ง

```bash
cd dist && sha256sum -c SHA256SUMS.txt
```

> **บน Windows** psql จะเดา client encoding จาก code page ของคอนโซล ทำให้ข้อความ
> ภาษาไทยเพี้ยน ให้สั่ง `set PGCLIENTENCODING=UTF8` (cmd) หรือ
> `$env:PGCLIENTENCODING="UTF8"` (PowerShell) ก่อนรัน — สคริปต์ในโฟลเดอร์นี้ตั้งให้แล้ว

---

## วิธีที่ 3 — deploy.sh สำหรับระบบจริง

ต่างจากวิธีอื่นตรงที่ **ไม่ลบข้อมูลเดิม** แต่เติมเฉพาะ migration ที่ยังไม่เคยใช้
จึงรันซ้ำได้ปลอดภัยและใช้อัปเกรดระบบที่มีข้อมูลจริงอยู่แล้วได้

```bash
export DATABASE_URL="postgres://user:pass@host:5432/vecsms"

DRY_RUN=1 bash deploy.sh     # ดูก่อนว่าจะทำอะไรบ้าง ไม่เขียนจริง
bash deploy.sh               # ใช้จริง
```

บริการที่บังคับ SSL เช่น Supabase หรือ Neon ให้เติม `?sslmode=require` ท้าย URL

สคริปต์จะ

1. ตรวจว่าเชื่อมต่อได้และเป็น PostgreSQL 15 ขึ้นไป
2. สร้างตาราง `schema_migrations` ถ้ายังไม่มี
3. ใช้เฉพาะไฟล์ที่ยังไม่เคยใช้ พร้อมบันทึก checksum
4. **หยุดทันทีถ้าไฟล์ที่ deploy ไปแล้วถูกแก้ภายหลัง** เพราะจะทำให้ฐานข้อมูล
   แต่ละเครื่องไม่ตรงกันโดยไม่มีใครรู้ — ให้เขียน migration ใหม่เป็นไฟล์ถัดไปแทน
5. สรุปสถานะให้ดู

เติมข้อมูลตัวอย่าง (ข้ามให้อัตโนมัติถ้ามีสถานศึกษาในระบบแล้ว)

```bash
WITH_DEMO=1 bash deploy.sh
```

---

## ตั้งค่าสิทธิ์ — ขั้นตอนที่ห้ามข้าม

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f deploy/roles.sql
```

แล้วสร้างผู้ใช้จริงด้วยมือ (ไม่เก็บรหัสผ่านไว้ในไฟล์)

```sql
create user vecsms_app    with password '<สุ่มมา>' in role app_runtime;
create user vecsms_report with password '<สุ่มมา>' in role app_readonly;
```

> **แอปพลิเคชันต้องห้ามเชื่อมต่อด้วย superuser เด็ดขาด**
> superuser ข้าม Row-Level Security ทุกกรณี แปลว่ากำแพงกันข้อมูลข้ามสถานศึกษา
> และกำแพงกันครูดูข้อมูลนักศึกษาที่ไม่ได้สอน **จะไม่ทำงานเลย** และไม่มีอะไรฟ้อง
> ระบบจะดูเหมือนทำงานปกติจนกว่าจะมีคนร้องเรียน

ตรวจว่าตั้งถูก — ต้องได้ `f` ทั้งสองคอลัมน์

```sql
select rolsuper, rolbypassrls from pg_roles where rolname = 'vecsms_app';
```

---

## สิ่งที่แอปต้องส่งทุก transaction

Row-Level Security ทั้งหมดอ่านค่าจากสามตัวแปรนี้ ถ้าไม่ตั้ง **ทุก query จะคืนศูนย์แถว**
ซึ่งเป็นพฤติกรรมที่ตั้งใจ — ล้มเหลวแบบปิดไว้ก่อน ดีกว่าเผลอเปิดข้อมูลออกไป

```sql
BEGIN;
SET LOCAL app.institution_id = '11111111-1111-1111-1111-111111111111';
SET LOCAL app.actor_id       = '<person_id ของผู้ใช้ที่ล็อกอิน>';
SET LOCAL app.role           = 'teacher';
--   registrar | academic | finance | student_affairs | director | admin
--   teacher | student | guardian
-- ...คำสั่งของ request นี้...
COMMIT;
```

ต้องใช้ `SET LOCAL` ไม่ใช่ `SET` เพราะ `SET LOCAL` มีผลแค่ใน transaction
ถ้าใช้ connection pool แบบ transaction mode (pgBouncer) ค่าจะไม่รั่วข้าม request
แต่ถ้าใช้ `SET` เฉย ๆ ค่าจะติดอยู่กับ connection แล้วผู้ใช้คนถัดไปที่หยิบ
connection เดิมจะได้สิทธิ์ของคนก่อนหน้า

ตัวอย่างใน NestJS / TypeORM

```ts
await dataSource.transaction(async (tx) => {
  await tx.query(
    `select set_config('app.institution_id', $1, true),
            set_config('app.actor_id',       $2, true),
            set_config('app.role',           $3, true)`,
    [ctx.institutionId, ctx.personId, ctx.role],
  );
  return handler(tx);
});
```

`set_config(..., true)` เทียบเท่า `SET LOCAL` และรับพารามิเตอร์ได้ จึงปลอดภัยกว่าการต่อสตริง

---

## อัปเกรดในอนาคต

1. เขียน migration ใหม่เป็นไฟล์ถัดไป เช่น `migrations/0010_finance.sql` — **ห้ามแก้ไฟล์เดิม**
2. เพิ่มเทสต์ใน `tests/`
3. ทดสอบบนฐานข้อมูลเปล่า `bash run.sh`
4. `bash build.sh` เพื่อสร้างไฟล์ dist ใหม่
5. `DRY_RUN=1 bash deploy.sh` ดูก่อน แล้วค่อยรันจริง

ดูว่าตอนนี้ระบบอยู่เวอร์ชันไหน

```sql
select version, applied_at, applied_by, duration_ms
from schema_migrations order by version;
```

---

## สำรองและกู้คืน

```bash
# สำรอง
pg_dump "$DATABASE_URL" -Fc -f vecsms-$(date +%Y%m%d).dump

# กู้คืนลงฐานข้อมูลเปล่า
pg_restore -d "$DATABASE_URL" --clean --if-exists vecsms-20690808.dump
```

ข้อควรระวังสำหรับสถานศึกษาเอกชน — ข้อมูลการมาเรียนและผลการเรียนใช้ยันการขอรับ
เงินอุดหนุน สำเนาสำรองจึงควรเก็บแบบที่ลบไม่ได้ (immutable / WORM) อย่างน้อยหนึ่งชุด
และต้องทดสอบกู้คืนจริงอย่างน้อยไตรมาสละครั้ง สำเนาที่กู้ไม่ได้ไม่ใช่สำเนา

---

## ตรวจก่อนขึ้นระบบจริง

- [ ] แอปเชื่อมต่อด้วย `vecsms_app` ไม่ใช่ superuser และยืนยันด้วย `select rolsuper, rolbypassrls`
- [ ] ทุก transaction ตั้ง `app.institution_id`, `app.actor_id`, `app.role` แล้ว
- [ ] ใช้ `vec-sms-schema.sql` ไม่ใช่ `vec-sms-full.sql` — ไม่มีวิทยาลัยสมมติปนอยู่
- [ ] **ยืนยันช่วงคะแนนตัดเกรดกับฝ่ายวัดผล** — ค่าใน seed เป็นค่าตั้งต้นเท่านั้น
- [ ] **ยืนยันน้ำหนักของลาป่วยและลากิจในการคิดเวลาเรียน** — ค่าตั้งต้นคือลาป่วยนับเต็ม
      ลากิจนับครึ่ง ซึ่งเป็นการตีความแบบหนึ่ง แต่ละวิทยาลัยไม่เหมือนกัน
      และเมื่อมีข้อมูลจริงแล้วจะแก้ย้อนหลังไม่ได้
- [ ] ยืนยันเพดานหน่วยกิตใน `registration_policy` กับฝ่ายวิชาการ
- [ ] เชื่อม KMS สำหรับคอลัมน์ `national_id_enc` — ตอนนี้ยังไม่มีการเข้ารหัสจริง
- [ ] ตั้งการสำรองข้อมูลอัตโนมัติ และทดสอบกู้คืนแล้วอย่างน้อยหนึ่งครั้ง
- [ ] ตั้ง log retention ไม่น้อยกว่า 90 วัน ตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26
- [ ] จัดทำ DPIA และนโยบายความเป็นส่วนตัวสำหรับข้อมูลผู้เยาว์

---

## แก้ปัญหาที่พบบ่อย

| อาการ | สาเหตุและวิธีแก้ |
|---|---|
| ทุก query คืน 0 แถวทั้งที่มีข้อมูล | ยังไม่ได้ตั้ง `app.institution_id` — เป็นพฤติกรรมที่ตั้งใจ ไม่ใช่บั๊ก |
| RLS ไม่ทำงาน เห็นข้อมูลข้ามวิทยาลัย | เชื่อมต่อด้วย superuser อยู่ ให้เปลี่ยนไปใช้ `vecsms_app` |
| ข้อความไทยเพี้ยนตอนนำเข้า | ตั้ง `PGCLIENTENCODING=UTF8` ก่อนรัน psql |
| `extension "btree_gist" is not available` | ติดตั้ง `postgresql-contrib` บนเซิร์ฟเวอร์ |
| deploy.sh หยุดเพราะ checksum ไม่ตรง | มีคนแก้ไฟล์ที่ deploy ไปแล้ว — ให้เขียน migration ใหม่แทนการแก้ไฟล์เดิม |
| ครูเห็นนักศึกษาทุกคน ทั้งที่ควรเห็นเฉพาะที่ตนสอน | ส่ง `app.role` เป็น `registrar` หรือบทบาทระดับสถานศึกษาอยู่ |
| ข้อความไทยใน `psql -c` เพี้ยนบน Git Bash | Git Bash แปลง argv เป็น TIS-620 ให้ใช้ `psql -f ไฟล์` แทน |
| อ่านผ่าน view แล้วเห็นข้อมูลข้ามวิทยาลัย | view ยังไม่ได้ตั้ง `security_invoker` — ต้องรัน migration 0012 |

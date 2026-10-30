# ติดตั้ง vec-sms บนเครื่องเดียวกับ examkub

Ubuntu 24.04 · Nginx · `vec.examkub.com`

**หลักข้อเดียวของการติดตั้งนี้: ระบบสอบต้องไม่รู้สึกถึง vec-sms**
ระบบสอบใช้งานเป็นช่วง แต่ช่วงนั้นคือทั้งห้องสอบพร้อมกันในนาทีเดียว ทุกการ
ตัดสินใจด้านล่างจึงเลือกทางที่ vec-sms ถอยให้

| เรื่อง | examkub | vec-sms |
|---|---|---|
| โฟลเดอร์ | `/opt/examkub` | `/opt/vecsms` (service มองไม่เห็น `/opt/examkub` เลย) |
| ผู้ใช้ระบบ | `examkub` | `vecsms` |
| PostgreSQL | cluster เดิม | **cluster แยก** รุ่น 18 พอร์ต 5434 ฟังแค่ 127.0.0.1 |
| แอป | เดิม | `127.0.0.1:3100` เข้าจากนอกเครื่องไม่ได้ |
| ส่วนแบ่ง CPU/IO ตอนแย่งกัน | 100 (ค่าเริ่มต้น) | 20 · หน่วยความจำไม่เกิน 1.5 GB |
| Nginx | server block เดิม | ไฟล์ใหม่ของตัวเอง ไม่แก้ของเดิมสักบรรทัด |
| สำรองข้อมูล | เดิม | ตีสามทุกคืน เก็บ 14 วัน ที่ `/opt/vecsms/backups` |

## ขั้นที่ไม่แตะ examkub (1–4)

**1. ชี้ DNS** — เพิ่ม A record `vec` ไปที่ IP เดียวกับ `examkub.com`

**2. ติดตั้ง PostgreSQL 18 ข้างรุ่นเดิม** (ข้ามถ้ามีแล้ว — `ls /usr/lib/postgresql`)

```bash
sudo apt install -y postgresql-common && sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
```

```bash
sudo apt install -y postgresql-18
```

แพ็กเกจรุ่น 18 อยู่คู่กับรุ่นเดิมได้ แต่ **การติดตั้งจะสร้าง cluster `18/main`
ให้อัตโนมัติ** ถ้า examkub ใช้พอร์ต 5432 อยู่ ตัวใหม่จะไปได้ 5433 — ไม่ชนกัน
แต่ไม่มีใครใช้ ลบทิ้งได้ด้วย `sudo pg_dropcluster 18 main --stop`
(**ตรวจด้วย `pg_lsclusters` ก่อนว่าไม่ใช่ cluster ของ examkub**)

**3. วางโค้ด**

```bash
sudo git clone -b phase0/deploy-readiness https://github.com/aumakarawuth/vec-sms.git /opt/vecsms/app
```

**4. ติดตั้ง** — สร้าง cluster · ฐานข้อมูล · ผู้ใช้ · สุ่มความลับ · build · service

```bash
sudo bash /opt/vecsms/app/deploy/selfhost/install.sh
```

ความลับทั้งหมดถูกสุ่มบนเครื่องและเขียนลง `/etc/vecsms/vecsms.env` (อ่านได้แค่ root)
**สำรอง `MFA_SECRET_KEY` และ `NATIONAL_ID_KEY` ไว้นอกเครื่องทันที** —
กุญแจเลขบัตรหายแปลว่าใบ รบ. ที่ออกไปแล้วพิมพ์ซ้ำได้ช่องเลขบัตรว่างตลอดไป
และอย่าเก็บไว้ที่เดียวกับไฟล์สำรองฐานข้อมูล

จบขั้นนี้ API ทำงานอยู่แต่ยังเข้าจากภายนอกไม่ได้ ตรวจได้ด้วย

```bash
curl -s http://127.0.0.1:3100/api/v1/health
```

## ขั้นที่แตะของที่ระบบสอบใช้ร่วม (5)

**5. เปิด Nginx** — ไฟล์ถูกวางไว้ที่ `/etc/nginx/sites-available/vec.examkub.com`
แล้ว อ่านก่อน แล้วสั่งทีละบรรทัด `nginx -t` ต้องผ่านก่อน reload เสมอ —
ถ้าล้ม Nginx ยังใช้ค่าเดิมต่อและ examkub ไม่สะดุด

```bash
sudo ln -s /etc/nginx/sites-available/vec.examkub.com /etc/nginx/sites-enabled/
```

```bash
sudo nginx -t
```

```bash
sudo systemctl reload nginx
```

```bash
sudo certbot --nginx -d vec.examkub.com
```

ทำนอกช่วงสอบ — `reload` ไม่ตัดการเชื่อมต่อที่ค้างอยู่ แต่ไม่มีเหตุผลให้เสี่ยง

## เปิดวิทยาลัยแรก (6–8)

**6. สร้างบัญชีผู้ให้บริการ / เปิดวิทยาลัย** — ใช้ `PROVISION_KEY` จาก
`/etc/vecsms/vecsms.env` ตามหัวข้อเดียวกันใน [`DEPLOY-ONLINE.md`](../../DEPLOY-ONLINE.md)
เก็บ `institutionId` ที่ได้ไว้ใช้ขั้นที่ 8

**7. ข้อมูลอ้างอิงและภาคเรียนแรก** — แก้ `institution_code`/`year_be` ในสองไฟล์
แล้วรัน (รันซ้ำได้ ไม่ทับค่าที่วิทยาลัยแก้เอง)

```bash
sudo -u postgres psql -p 5434 -v ON_ERROR_STOP=1 -f /opt/vecsms/app/db/deploy/reference-data.sql vecsms
```

```bash
sudo -u postgres psql -p 5434 -v ON_ERROR_STOP=1 -f /opt/vecsms/app/db/deploy/first-terms.sql vecsms
```

**8. build หน้าจอเจ้าหน้าที่**

```bash
sudo bash /opt/vecsms/app/deploy/selfhost/build-web.sh <institutionId>
```

## อัปเดตรอบถัดไป

```bash
cd /opt/vecsms/app && sudo -u vecsms git pull && sudo bash deploy/selfhost/install.sh
```

**migration ใหม่ไม่ถูกรันโดย `install.sh`** — มันนำเข้าโครงสร้างเฉพาะฐานที่ยังว่าง
การไล่ migration บนฐานที่มีข้อมูลจริงต้องสำรองก่อนและทำทีละไฟล์ (ยังไม่มีสคริปต์)

## ข้อห้าม

- **ห้ามรัน vec-sms เกินหนึ่ง instance** งานประจำคืนรันในโปรเซสของแอป
- **ห้ามตั้ง `DATABASE_URL` เป็น `postgres`** แอปจะไม่บูต (RLS ถูกข้ามทั้งหมด)
- **ห้ามใช้ `vec-sms-full.sql`** มีวิทยาลัยสมมติปนอยู่
- **ห้ามเพิ่ม `MemoryMax` จนเกินที่เครื่องเหลือ** ถ้าเครื่องหน่วยความจำหมด
  OOM killer อาจเลือกฆ่าโปรเซสของระบบสอบแทน

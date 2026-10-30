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

**1. DNS** — เครื่องนี้เข้าทาง **Cloudflare Tunnel** จึงไม่ต้องเพิ่ม A record
และไม่ต้องรู้ IP — Cloudflare สร้าง CNAME ชี้ไปที่ทันเนลให้เองในขั้นที่ 5

**2. PostgreSQL 18 และ Nginx**

ตรวจก่อนว่ามี PostgreSQL 18 แล้วหรือยัง (`ls /usr/lib/postgresql`) — บนเครื่อง
examkub มีอยู่แล้ว เพราะ examkub ใช้ cluster `18/main` พอร์ต 5432 **จึงข้าม
การติดตั้งได้ และ `18/main` คือฐานข้อมูลของระบบสอบ — ห้าม drop · stop ·
แก้ค่าของ cluster นี้เด็ดขาด** vec-sms สร้าง cluster `18/vecsms` แยกของตัวเอง

ถ้ายังไม่มีรุ่น 18 จริง ๆ:

```bash
sudo apt install -y postgresql-common && sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && sudo apt install -y postgresql-18
```

**Nginx** — หน้าเครื่อง examkub คือ **Caddy ที่พอร์ต 80** (cloudflared → Caddy
→ examkub) vec-sms ใช้ Nginx แยกของตัวเองที่ฟังแค่ `127.0.0.1:8081`
**ไม่แตะ Caddyfile เลย** — Caddy เป็นทางที่คำขอของระบบสอบวิ่งผ่านทุกคำขอ

ปัญหาคือแพ็กเกจ nginx ติดตั้งแล้วพยายามสตาร์ตไซต์ตั้งต้นที่พอร์ต 80 ทันที
ซึ่ง Caddy ถืออยู่ — Nginx จะสตาร์ตไม่ขึ้น (**Caddy ไม่ได้รับผลกระทบ** การ bind
พอร์ตที่มีคนถืออยู่แค่ล้มฝั่งที่มาทีหลัง) แล้ว apt จะรายงานว่าตั้งค่าไม่ครบ
จึงทำสามขั้นนี้ตามลำดับ

```bash
sudo apt install -y nginx || true
```

```bash
sudo rm -f /etc/nginx/sites-enabled/default && sudo dpkg --configure -a
```

```bash
sudo systemctl restart nginx && sudo ss -ltnp | grep -E ':80\b'
```

บรรทัดสุดท้ายต้องเห็น **`caddy` คนเดียว** ที่พอร์ต 80 ไม่มี nginx

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

ทำนอกช่วงสอบ — `reload` ไม่ตัดการเชื่อมต่อที่ค้างอยู่ แต่ไม่มีเหตุผลให้เสี่ยง

ไฟล์นี้ฟังแค่ `127.0.0.1:8081` จึงยังไม่มีใครจากภายนอกเข้าถึงได้ ตรวจด้วย

```bash
curl -s -H 'Host: vec.examkub.com' http://127.0.0.1:8081/api/v1/health
```

**เพิ่ม Public Hostname ในทันเนลเดิม** — Cloudflare Zero Trust → Networks →
Tunnels → ทันเนลของ examkub → Public Hostname → Add

| ช่อง | ค่า |
|---|---|
| Subdomain | `vec` |
| Domain | `examkub.com` |
| Type | `HTTP` |
| URL | `localhost:8081` |

ทันเนลที่จัดการผ่านหน้าเว็บเพิ่ม hostname ได้โดยไม่ restart cloudflared —
ระบบสอบไม่สะดุด **ถ้าทันเนลจัดการด้วยไฟล์ `config.yml` บนเครื่องแทน**
ต้องเพิ่ม ingress rule เหนือบรรทัด `http_status:404` แล้ว restart cloudflared
ซึ่งตัดการเชื่อมต่อของ examkub ชั่วครู่ — ทำนอกช่วงสอบเท่านั้น

**ไม่ใช้ certbot** — Cloudflare ปิดปลาย HTTPS ให้แล้ว
และไอพีจริงของผู้ใช้มาจาก `CF-Connecting-IP` (ไฟล์ Nginx จัดการให้แล้ว)

## เปิดวิทยาลัยแรก (6–8)

**6. สร้างบัญชีผู้ให้บริการ · เปิดวิทยาลัย · ตั้งรหัสผ่านผู้ดูแล** — สคริปต์ถาม
ทีละช่อง อ่าน `PROVISION_KEY` จากไฟล์เอง และไม่แสดงรหัสผ่านบนจอ (คำสั่ง curl
ที่มี JSON ภาษาไทยเพี้ยนง่ายตอนคัดลอกวางลงเทอร์มินัล)

```bash
sudo bash /opt/vecsms/app/deploy/selfhost/first-run.sh
```

รหัสผ่านที่ถูกปฏิเสธจะถามใหม่แทนการจบ เพราะรหัสตั้งค่ากับรหัสรีเซ็ตใช้ได้ครั้งเดียว
จด `institutionId` ที่ได้ไว้ใช้ขั้นที่ 8

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

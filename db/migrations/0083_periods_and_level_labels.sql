-- ═══════════════════════════════════════════════════════════════════
-- 0083 — คาบเรียนจริง (period) และป้ายชื่อระดับ/ชั้นปีที่แก้ไขได้
--
-- ─── คาบเรียน ───
-- `section_timeslot.period_from/period_to` (0034) เก็บแค่เลขลำดับคาบมาตลอด
-- ไม่มีเวลานาฬิกาผูกอยู่เลย หน้าจอ "จัดตารางสอน" และ "ตารางสอบ" จึงพิมพ์
-- แค่ "คาบ 1–2" โดยไม่มีใครรู้ว่าคือกี่โมงถึงกี่โมง — `period` เป็นตาราง
-- ใหม่ที่ผูกเลขลำดับกับเวลาจริง ใช้เลขลำดับเดียวกับที่ `section_timeslot`
-- ใช้อยู่แล้ว (ไม่ใช่คนละชุด) จึงไม่ต้องแก้ตารางเดิม แค่ให้ชั้น API/หน้าจอ
-- แปลเลขเป็นเวลาให้เพิ่ม
--
-- ─── ป้ายชื่อระดับและชั้นปี ───
-- `qualification_level` (0002) เป็น enum ตายตัวสามค่า และหน้าจอเว็บ
-- (`academic-year.tsx`, `finance.tsx`) ฮาร์ดโค้ด "ปวช./ปวส." ไว้ในโค้ด
-- ทั้งสองไฟล์แยกกัน — วิทยาลัยที่อยากเรียกชื่ออื่น (เช่น "ปวช." เป็น
-- "ระดับกลาง") แก้ไม่ได้เลยนอกจากแก้โค้ด ตารางใหม่สองตัวเก็บป้ายชื่อ
-- ที่แก้ได้แยกจาก enum ซึ่งยังคงเป็นตัวกำหนดกฎธุรกิจเหมือนเดิม
--   - `qualification_level_label` — ป้ายชื่อระดับ (ปวช./ปวส./ทล.บ.)
--   - `grade_level` — ป้ายชื่อชั้นปีในแต่ละระดับ (ปวช.1, ปวช.2, ...)
-- ทั้งสองเป็นข้อมูลตกแต่งการแสดงผลล้วน ๆ ไม่กระทบการคำนวณเลื่อนชั้นปี
-- (`rollover_students()` ยังบวก study_year ด้วยตัวเลขเหมือนเดิม)
-- ═══════════════════════════════════════════════════════════════════

create table period (
  id              uuid      primary key default gen_random_uuid(),
  institution_id  uuid      not null references institution on delete restrict,
  ordinal         smallint  not null check (ordinal between 1 and 20),
  title           text      not null,
  short_name      text,
  starts_at       time,
  ends_at         time,
  unique (institution_id, ordinal),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table grade_level (
  id              uuid                 primary key default gen_random_uuid(),
  institution_id  uuid                 not null references institution on delete restrict,
  level           qualification_level  not null,
  study_year      smallint             not null check (study_year between 1 and 6),
  title           text                 not null,
  short_name      text,
  unique (institution_id, level, study_year)
);

create table qualification_level_label (
  id              uuid                 primary key default gen_random_uuid(),
  institution_id  uuid                 not null references institution on delete restrict,
  level           qualification_level  not null,
  title           text                 not null,
  sort_order      smallint             not null default 0,
  unique (institution_id, level)
);

do $$
declare t text;
begin
  foreach t in array array['period', 'grade_level', 'qualification_level_label'] loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force  row level security', t);
    execute format($f$
      create policy tenant_isolation on %I
      using (institution_id = current_institution_id())
      with check (institution_id = current_institution_id())
    $f$, t);
    -- เหตุผลของการแยก insert/update/delete แทน `for all` — ดู 0074/0065
    execute format($f$
      create policy academic_insert on %I
        as restrictive for insert
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
    execute format($f$
      create policy academic_update on %I
        as restrictive for update
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
        with check (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
    execute format($f$
      create policy academic_delete on %I
        as restrictive for delete
        using (current_app_role() in ('academic', 'registrar', 'director', 'admin'))
    $f$, t);
  end loop;
end $$;

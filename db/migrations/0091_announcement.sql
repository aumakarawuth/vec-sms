-- ═══════════════════════════════════════════════════════════════════
-- 0091_announcement.sql
--
-- ประกาศ/ข่าวสารถึงนักศึกษา — รวมสองเมนูเดิมของศูนย์นักศึกษาเป็นระบบเดียว
-- "การประชาสัมพันธ์" (จัดทำประกาศ) และ "ไปรษณีย์" (จัดการข้อมูลไปรษณีย์และ
-- เอกสารติดต่อ) เป็นงานเดียวกันจริง ๆ ในทางปฏิบัติ — ทั้งสองคือ "ข้อความ
-- ที่วิทยาลัยต้องการสื่อสารถึงนักศึกษาเป็นกลุ่ม" ต่างกันแค่ช่องทาง (ปิดประกาศ
-- vs. เอกสารที่ส่งทางไปรษณีย์) ซึ่งไม่ใช่ความต่างของโครงสร้างข้อมูล
-- แยกเป็นสองตารางจะได้ระบบที่ทำงานเหมือนกันทุกอย่างสองชุดโดยไม่มีเหตุผล
--
-- ─── ทำไมยังไม่มี audience targeting (ต่อกลุ่ม/ห้อง) ───
-- ตารางที่ผูกกับ program/class_section เพิ่มความซับซ้อนของ RLS และการ
-- คำนวณ "ใครเห็นประกาศนี้" ทันที โดยยังไม่มีใครขอ — วิทยาลัยที่ใช้งานจริง
-- อาจต้องการ "ทั้งวิทยาลัย" เป็นส่วนใหญ่อยู่แล้ว เพิ่มการเจาะกลุ่มทีหลังได้
-- เมื่อรู้ว่าวิทยาลัยต้องการแบบไหนจริง ไม่ใช่เดาไว้ก่อน (หลักการเดียวกับ
-- ที่ 0070 ยังไม่ผูกชมรมกับเกณฑ์จบ)
--
-- ─── ทำไม published_at เป็น timestamptz ที่ตั้งค่าได้ ไม่ใช่แค่ boolean ───
-- งานประชาสัมพันธ์เขียนล่วงหน้าแล้วตั้งเวลาปล่อยเป็นเรื่องปกติ (เช่น เขียน
-- ประกาศผลสอบไว้ก่อน แล้วให้ขึ้นพร้อมกันตอนเช้าวันถัดไป) — null คือฉบับร่าง
-- ที่ยังไม่เผยแพร่ ค่าที่ตั้งไว้ในอนาคตคือ "ตั้งเวลาไว้แล้ว" หน้าจอเป็นผู้
-- ตัดสินว่าจะแสดงอะไรจากสองคอลัมน์นี้ ไม่ต้องมี status แยกอีกคอลัมน์ที่
-- อาจไม่ตรงกับเวลาจริง
-- ═══════════════════════════════════════════════════════════════════
begin;

create table announcement (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  title_th       text        not null,
  body_th        text        not null,
  category_th    text,                          -- เช่น "ทั่วไป" "การเงิน" "ตารางสอบ" "กิจกรรม" — ข้อความอิสระ
  published_at   timestamptz,                    -- null = ฉบับร่าง · อนาคต = ตั้งเวลาไว้แล้ว
  expires_on     date,                           -- null = ไม่มีกำหนดหมดอายุ
  created_by     uuid        not null references person on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on announcement (institution_id, published_at desc);

comment on table announcement is
  'ประกาศ/ข่าวสารถึงนักศึกษา — รวมงาน "การประชาสัมพันธ์" และ "ไปรษณีย์" เดิมของศูนย์นักศึกษาเป็นระบบเดียว (ดูคอมเมนต์บนไฟล์นี้)';
comment on column announcement.created_by is
  'ผู้เขียนจริง ไม่ใช่ผู้ที่ระบบอนุญาตให้เลือก — ตั้งจาก current_actor_id() เท่านั้น (ดู trigger guard)';

create trigger announcement_touch before update on announcement
  for each row execute function set_updated_at();

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table announcement enable row level security;
alter table announcement force row level security;

create policy tenant_isolation on announcement
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

/*
 * เขียนได้เฉพาะบทบาทที่ทำหน้าที่สื่อสารกับนักศึกษาโดยตรง — ครูไม่รวม
 * เพราะประกาศระดับนี้เป็นเสียงของวิทยาลัย ไม่ใช่ของครูรายคน (ต่างจาก
 * behavior_record ที่ครูต้องบันทึกเองได้ตามเหตุการณ์ที่เห็น)
 */
create policy announcement_insert on announcement
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

create policy announcement_update on announcement
  as restrictive for update
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']))
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

create policy announcement_delete on announcement
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

/* ผู้เขียนต้องเป็นคนที่กดจริง — เหตุผลเดียวกับ student_achievement_guard ใน 0090 */
create or replace function announcement_guard() returns trigger
language plpgsql as $$
begin
  if current_app_role() = 'none' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.created_by is distinct from current_actor_id() then
      raise exception 'ผู้เขียนประกาศต้องเป็นผู้ใช้ที่กำลังทำรายการ';
    end if;
    return new;
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'เปลี่ยนผู้เขียนประกาศไม่ได้';
  end if;
  return new;
end $$;

drop trigger if exists announcement_guard on announcement;
create trigger announcement_guard
  before insert or update on announcement
  for each row execute function announcement_guard();

commit;

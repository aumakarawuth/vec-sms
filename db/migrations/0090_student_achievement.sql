-- ═══════════════════════════════════════════════════════════════════
-- 0090_student_achievement.sql
--
-- ผลงานและเกียรติประวัติของนักศึกษา — เมนู "ข้อมูลผลงานและเกียรติประวัติ"
-- ในศูนย์นักศึกษาไม่เคยมีตารางรองรับเลยตั้งแต่ต้น (ต่างจาก `talent_th`
-- ซึ่งเป็นแค่ข้อความอิสระบนโปรไฟล์ — รางวัล/ผลงานต้องมีวันที่ ระดับ และ
-- ผู้มอบ เพื่อขึ้นใบประกาศเกียรติคุณหรือพิจารณาทุนได้จริง)
--
-- ─── ทำไมไม่ใช้ตาราง behavior_record (ทิศทาง 'award') แทน ───
-- behavior_record เป็นเรื่อง**คะแนนความประพฤติสะสม**ที่บวก/ลบยอดรายวินาที
-- (ดู v_behavior_balance) ส่วนผลงาน/เกียรติประวัติเป็น**บันทึกเหตุการณ์**ที่
-- ไม่มียอดสะสมและไม่ผูกกับ behavior_rule เลย — ผสมสองเรื่องนี้เข้าตารางเดียว
-- จะทำให้ยอดคะแนนความประพฤติปนกับ "ได้รับรางวัลกีฬาสี" ซึ่งไม่ควรบวกลบอะไร
--
-- ─── ทำไมแก้ไข/ลบได้ตรง ไม่ใช่ write-once แบบ issued_document ───
-- รางวัลที่บันทึกผิดปี ผิดระดับ หรือพิมพ์ชื่อผิด เป็นเรื่องที่ต้องแก้ตรงได้
-- ต่างจากเอกสารที่ออกไปแล้วมีคนถือกระดาษอยู่ (หลักข้อ 4) — บันทึกนี้ยังไม่ใช่
-- หลักฐานที่พิมพ์ออกไปให้ใครถือ จึงแก้/ลบตรงได้เหมือน club (0070)
-- ═══════════════════════════════════════════════════════════════════
begin;

create table student_achievement (
  id             uuid        primary key default gen_random_uuid(),
  student_id     uuid        not null references student on delete cascade,
  title_th       text        not null,
  category_th    text,                          -- เช่น "วิชาการ" "กีฬา" "ศิลปะ" "จิตอาสา" — ข้อความอิสระ ไม่ตรึงเป็น enum
  level_th       text,                           -- เช่น "ระดับสถานศึกษา" "ระดับจังหวัด" "ระดับชาติ" — ข้อความอิสระเช่นกัน
  issuer_th      text,                           -- หน่วยงานที่มอบ/จัด
  awarded_on     date        not null default current_date,
  note_th        text,
  recorded_by    uuid        not null references person on delete restrict,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on student_achievement (student_id, awarded_on desc);

comment on table student_achievement is
  'ผลงานและเกียรติประวัติของนักศึกษา — บันทึกเหตุการณ์ ไม่ใช่ยอดสะสมแบบ behavior_record (ดูคอมเมนต์บนไฟล์นี้)';
comment on column student_achievement.recorded_by is
  'ผู้บันทึกจริง ไม่ใช่ผู้ที่ระบบอนุญาตให้เลือก — ตั้งจาก current_actor_id() เท่านั้น (ดู trigger guard)';

create trigger student_achievement_touch before update on student_achievement
  for each row execute function set_updated_at();

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security — สืบทอดสถานศึกษาผ่าน student_id เหมือน club_member
-- ───────────────────────────────────────────────────────────────────
alter table student_achievement enable row level security;
alter table student_achievement force row level security;

create policy tenant_isolation on student_achievement
  using (student_institution(student_achievement.student_id) = current_institution_id())
  with check (student_institution(student_achievement.student_id) = current_institution_id());

/*
 * อ่านได้กว้างกว่าเขียน — ครูควรเห็นผลงานของนักศึกษาที่ตัวเองดูแล/สอนเวลา
 * เขียนจดหมายแนะนำหรือคัดเลือกตัวแทน ต่างจากการบันทึก/แก้ไขที่ควรอยู่กับ
 * งานที่รับผิดชอบเรื่องนี้จริง (รูปแบบเดียวกับ club_member_scope ใน 0070)
 */
create policy student_achievement_read on student_achievement
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = student_achievement.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null)
  );

create policy student_achievement_insert on student_achievement
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

create policy student_achievement_update on student_achievement
  as restrictive for update
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']))
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

create policy student_achievement_delete on student_achievement
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

/*
 * ─── ทำไมต้องมี trigger ทั้งที่มีนโยบาย insert แล้ว ───
 * นโยบายเทียบได้แค่ "บทบาทนี้เขียนได้ไหม" แต่เทียบไม่ได้ว่าค่า recorded_by
 * ที่ส่งมาเป็นคนที่กดจริงหรือไม่ — ถ้าไม่บังคับ เจ้าหน้าที่คนหนึ่งจะบันทึก
 * ในนามคนอื่นได้ แล้วหลักฐานว่าใครบันทึกจะชี้ผิดคน (บทเรียนเดียวกับ
 * behavior_record_guard ใน 0056)
 */
create or replace function student_achievement_guard() returns trigger
language plpgsql as $$
begin
  if current_app_role() = 'none' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.recorded_by is distinct from current_actor_id() then
      raise exception 'ผู้บันทึกผลงาน/เกียรติประวัติต้องเป็นผู้ใช้ที่กำลังทำรายการ';
    end if;
    return new;
  end if;
  if new.student_id <> old.student_id then
    raise exception 'ย้ายบันทึกไปให้นักศึกษาคนอื่นไม่ได้ — ถ้าบันทึกผิดคนต้องลบแล้วบันทึกใหม่';
  end if;
  if new.recorded_by is distinct from old.recorded_by then
    raise exception 'เปลี่ยนผู้บันทึกไม่ได้';
  end if;
  return new;
end $$;

drop trigger if exists student_achievement_guard on student_achievement;
create trigger student_achievement_guard
  before insert or update on student_achievement
  for each row execute function student_achievement_guard();

commit;

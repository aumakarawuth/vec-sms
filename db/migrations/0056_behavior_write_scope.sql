-- ═══════════════════════════════════════════════════════════════════
-- 0056 — ปิดช่องเขียนคะแนนความประพฤติ
--
-- ═══ ยิงจริงแล้วนักศึกษาทำได้ทั้งสามอย่างนี้ที่ชั้นฐานข้อมูล ═══
--   · `insert into behavior_record` ให้คะแนนความดีตัวเอง 50 คะแนน
--     (ยอดจาก 100 เป็น 150 ทันที)
--   · `update behavior_record set points = 0` ล้างคะแนนที่ถูกหักทิ้ง
--   · `delete from behavior_record` ลบประวัติการถูกหักของตัวเองทั้งหมด
--     (ทดสอบจริง — ลบได้ 3 แถว ยอดจาก 90 กลับเป็น 100)
--   · และ `insert into behavior_rule` สร้างกฎ "ให้คะแนน 999" ของตัวเองได้ด้วย
--
-- ต้นเหตุคือสองตารางนี้มีแต่นโยบาย `tenant_isolation` ล้วน ไม่มีนโยบาย
-- restrictive ที่จำกัดว่าใครเขียนได้ — เป็นรูปเดียวกับข้อ 10, 11 และ 13
-- ทุกประการ คือช่องที่**ข้าม API ไปเลย** ซึ่งอ่านโค้ดฝั่ง API ไม่มีวันเห็น
-- (ยิ่งกว่านั้นคือ ณ วันที่เขียนไฟล์นี้ **ไม่มี endpoint ไหนแตะตารางนี้เลย
--  สักตัว** การอ่านโค้ดจึงให้ข้อสรุปว่า "ไม่มีใครเขียนได้" ซึ่งตรงข้ามกับ
--  ความจริงโดยสิ้นเชิง)
--
-- ═══ ทำไมเรื่องนี้หนักกว่าที่เห็น ═══
-- 0055 เพิ่ง**ออกใบรับรองความประพฤติ**ที่อ่านยอดจาก `v_behavior_balance`
-- ซึ่งรวมมาจากตารางนี้ นักศึกษาที่ลบประวัติตัวเองแล้วไปขอใบรับรอง จะได้
-- กระดาษที่เขียนว่า "ไม่ปรากฏประวัติการถูกตัดคะแนนความประพฤติ" พร้อม
-- ช่องลงนามผู้อำนวยการ — วิทยาลัยรับรองสิ่งที่ไม่จริงโดยไม่มีใครรู้
--
-- ═══ ทำไมครูต้องเขียนได้ แต่แก้ไม่ได้ ═══
-- การบันทึกพฤติกรรมเป็นงานของครูผู้สอนและครูที่ปรึกษาที่เห็นเหตุการณ์
-- ถ้าเปิดให้เฉพาะงานปกครอง ทุกเรื่องต้องเดินไปบอกด้วยปากแล้วให้คนอื่นพิมพ์
-- ซึ่งแปลว่าจะไม่มีใครบันทึก แต่การ**แก้หรือลบ**สิ่งที่บันทึกไปแล้วเป็น
-- คนละเรื่อง — เป็นการเปลี่ยนหลักฐาน จึงเหลือเฉพาะงานปกครองและผู้บริหาร
--
-- ═══ ทำไม student_id กับ rule_id แก้ไม่ได้ ═══
-- การย้ายบันทึกไปให้นักศึกษาอีกคน หรือเปลี่ยนกฎที่อ้างถึง ไม่ใช่การแก้คำผิด
-- แต่เป็นการเขียนประวัติใหม่โดยที่เลขที่และวันที่ยังเป็นของเดิม ถ้าบันทึกผิดคน
-- ต้องลบแล้วบันทึกใหม่ ซึ่งเห็นได้จากภายนอกว่ามีการลบเกิดขึ้น
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ───────────────────────────────────────────────────────────────────
-- ครูผู้สอนของนักศึกษาคนนั้นในภาคเรียนที่ยังเปิดอยู่
--
-- security definer เพราะอ่าน `enrollment` และ `class_section` ซึ่งมี RLS
-- ของตัวเอง — ครูที่ยังไม่เห็นแถวจะตรวจไม่ผ่านทั้งที่สิทธิ์ถูกต้อง
-- (กับดักเดียวกับ `student_institution()` ใน 0012 และ `may_see_sensitive()`
--  ใน 0053)
-- ───────────────────────────────────────────────────────────────────
create or replace function actor_taught_student_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select distinct e.student_id
    from enrollment e
    join class_section cs on cs.id = e.class_section_id
    join staff st on st.id = cs.teacher_id
   where st.person_id = current_actor_id()
     and e.status = 'enrolled'
$$;

comment on function actor_taught_student_ids() is
  'นักศึกษาที่ผู้ใช้ปัจจุบันเป็นครูผู้สอนอยู่ — ใช้จำกัดขอบเขตการบันทึกพฤติกรรม';

/* บทบาทที่บันทึกพฤติกรรมได้ — ครูรวมอยู่ด้วยโดยตั้งใจ */
create or replace function may_record_behavior()
returns boolean language sql stable as $$
  select current_app_role() in
    ('teacher', 'student_affairs', 'registrar', 'academic', 'director', 'admin')
$$;

/* บทบาทที่**แก้หรือลบ**บันทึกได้ — แคบกว่ามาก เพราะเป็นการเปลี่ยนหลักฐาน */
create or replace function may_amend_behavior()
returns boolean language sql stable as $$
  select current_app_role() in ('student_affairs', 'director', 'admin')
$$;

-- ═══ behavior_rule ═════════════════════════════════════════════════
alter table behavior_rule enable row level security;
alter table behavior_rule force row level security;

/*
 * อ่านได้ทั้งวิทยาลัย — ครูต้องเลือกกฎตอนบันทึก และนักศึกษาควรรู้ว่า
 * ทำอะไรแล้วถูกหักกี่คะแนน (กฎที่ไม่มีใครรู้ล่วงหน้าไม่ใช่กฎ)
 * ไม่ต้องมีนโยบาย select แยก เพราะ tenant_isolation เปิดอ่านให้แล้ว
 */
create policy behavior_rule_insert on behavior_rule
  as restrictive for insert with check (may_amend_behavior());

create policy behavior_rule_update on behavior_rule
  as restrictive for update
  using (may_amend_behavior()) with check (may_amend_behavior());

create policy behavior_rule_delete on behavior_rule
  as restrictive for delete using (may_amend_behavior());

comment on policy behavior_rule_insert on behavior_rule is
  'ยิงจริงแล้วนักศึกษาสร้างกฎ "ให้คะแนนตัวเอง 999" ได้ ก่อนมีนโยบายนี้';

-- ═══ behavior_record ═══════════════════════════════════════════════
alter table behavior_record enable row level security;
alter table behavior_record force row level security;

/*
 * ─── ต้องแยกเป็น for select / insert / update / delete ───
 * นโยบาย restrictive แบบ `for all` กิน select ด้วย ซึ่งจะทำให้เงื่อนไข
 * "ต้องเป็นเจ้าหน้าที่ถึงจะเขียนได้" กลายเป็น "ถึงจะอ่านได้" แล้วนักศึกษา
 * จะดูคะแนนของตัวเองไม่ได้เลย (บทเรียนจาก 0053)
 */
create policy behavior_read on behavior_record
  as restrictive for select using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())     -- เจ้าตัวและผู้ปกครอง
    or student_id in (select actor_advisee_ids())     -- ครูที่ปรึกษา
    or student_id in (select actor_taught_student_ids())  -- ครูผู้สอน
  );

/*
 * ครูบันทึกได้เฉพาะนักศึกษาที่ตัวเองสอนหรือเป็นที่ปรึกษาอยู่
 * — ครูคนหนึ่งไม่ควรหักคะแนนนักศึกษาที่ไม่เคยเจอ
 * ส่วนบทบาทระดับวิทยาลัยบันทึกได้ทั้งหมด เพราะงานปกครองรับเรื่องจากทุกทาง
 */
create policy behavior_insert on behavior_record
  as restrictive for insert with check (
    is_institution_wide_role()
    or (may_record_behavior()
        and (student_id in (select actor_taught_student_ids())
             or student_id in (select actor_advisee_ids())))
  );

create policy behavior_update on behavior_record
  as restrictive for update
  using (may_amend_behavior()) with check (may_amend_behavior());

create policy behavior_delete on behavior_record
  as restrictive for delete using (may_amend_behavior());

comment on policy behavior_read on behavior_record is
  'เจ้าตัว ผู้ปกครอง ครูที่ปรึกษา ครูผู้สอน และบทบาทระดับวิทยาลัยอ่านได้ — เขียนคนละเรื่อง ดูนโยบาย insert/update/delete';

/*
 * ─── ทำไมต้องมี trigger ทั้งที่มีนโยบายแล้ว ───
 * นโยบาย RLS เทียบได้แค่ "แถวนี้แตะได้ไหม" แต่เทียบไม่ได้ว่า "เปลี่ยนจาก
 * อะไรเป็นอะไร" การห้ามย้ายบันทึกไปให้นักศึกษาอีกคนจึงต้องใช้ trigger
 * — เรื่องเดียวกับที่ `grade_submission` ใน 0049 ต้องใช้ trigger ไม่ใช่นโยบาย
 */
create or replace function behavior_record_guard() returns trigger
language plpgsql as $$
begin
  -- ปล่อยผ่านเมื่อไม่มีบริบทผู้ใช้ (superuser ตอนย้ายข้อมูลหรือ seed)
  -- บริบทที่ไม่มี app.role ก็ไม่มี app.institution_id นโยบายจึงปฏิเสธ
  -- ทุกแถวอยู่แล้ว การปล่อยผ่านตรงนี้ไม่เปิดช่องให้ใคร (หลักเดียวกับ 0042)
  if current_app_role() = 'none' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- ผู้บันทึกต้องเป็นคนที่กดจริง ไม่ใช่ชื่อที่ส่งมากับข้อมูล
    -- มิฉะนั้นครูจะบันทึกในนามคนอื่นได้ แล้วหลักฐานจะชี้ผิดคน (บทเรียนข้อ 5)
    if new.recorded_by is distinct from current_actor_id() then
      raise exception 'ผู้บันทึกพฤติกรรมต้องเป็นผู้ใช้ที่กำลังทำรายการ';
    end if;
    return new;
  end if;

  if new.student_id <> old.student_id then
    raise exception 'ย้ายบันทึกพฤติกรรมไปให้นักศึกษาคนอื่นไม่ได้ — ถ้าบันทึกผิดคนต้องลบแล้วบันทึกใหม่';
  end if;
  if new.rule_id is distinct from old.rule_id then
    raise exception 'เปลี่ยนกฎที่บันทึกอ้างถึงไม่ได้ — ถ้าเลือกผิดข้อต้องลบแล้วบันทึกใหม่';
  end if;
  if new.recorded_by is distinct from old.recorded_by then
    raise exception 'เปลี่ยนผู้บันทึกไม่ได้';
  end if;

  return new;
end $$;

drop trigger if exists behavior_record_guard on behavior_record;
create trigger behavior_record_guard
  before insert or update on behavior_record
  for each row execute function behavior_record_guard();

commit;

-- ═══════════════════════════════════════════════════════════════════
-- มุมมองที่หน้าจอต้องใช้
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ยอดคะแนนพร้อมระดับเตือน — `v_behavior_balance` บอกแค่ตัวเลข
 * แต่ตัวเลขเปล่า ๆ ตอบไม่ได้ว่า "แล้วยังไง" เกณฑ์อยู่ใน `behavior_policy`
 * ซึ่งถ้าให้หน้าจออ่านเองแล้วเทียบเอง จะกลายเป็นกฎชุดที่สองที่ค่อย ๆ
 * เพี้ยนไปจากของจริง
 */
create or replace view v_behavior_status with (security_invoker = true) as
  select b.student_id,
         b.institution_id,
         b.balance,
         coalesce(bp.starting_points, 100)  as starting_points,
         coalesce(bp.warn_below, 70)        as warn_below,
         coalesce(bp.critical_below, 50)    as critical_below,
         case
           when b.balance < coalesce(bp.critical_below, 50) then 'critical'
           when b.balance < coalesce(bp.warn_below, 70)     then 'warn'
           else 'ok'
         end as band,
         (select count(*) from behavior_record br
            join behavior_rule r on r.id = br.rule_id
           where br.student_id = b.student_id and r.direction = 'deduct') as deduct_count,
         (select count(*) from behavior_record br
            join behavior_rule r on r.id = br.rule_id
           where br.student_id = b.student_id and r.direction = 'award')  as award_count,
         (select max(br.occurred_on) from behavior_record br
           where br.student_id = b.student_id) as last_record_on
    from v_behavior_balance b
    left join behavior_policy bp on bp.institution_id = b.institution_id;

comment on view v_behavior_status is
  'ยอดคะแนนความประพฤติพร้อมระดับเตือนตาม behavior_policy — หน้าจอห้ามเทียบเกณฑ์เอง มิฉะนั้นจะกลายเป็นกฎชุดที่สอง';

commit;

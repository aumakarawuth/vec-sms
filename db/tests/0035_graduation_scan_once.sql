-- ═══════════════════════════════════════════════════════════════════
-- 0035_graduation_scan_once.sql
-- ทดสอบว่าตรวจจบที่เขียนใหม่ (0051) ให้ผลเท่าเดิมทุกแถว และเร็วขึ้นจริง
--
-- ─── ทำไมต้องเทียบกับตัวเดิมทีละแถว ───
-- 0051 แก้เรื่องความเร็วล้วน ๆ ผลลัพธ์ต้องไม่ขยับแม้แต่ทศนิยมเดียว
-- การตรวจจบผิดไม่ได้ทำให้ใครเห็น error — มันทำให้นักศึกษาคนหนึ่งเห็นว่า
-- ตัวเอง "ครบแล้ว" ทั้งที่ยังไม่ครบ แล้วไปรู้ตอนที่สายเกินแก้
--
-- เทสต์นี้จึงประกาศ **ตัวเดิมก่อน 0051** ไว้เป็น `evaluate_graduation_ref()`
-- แล้วเทียบผลของทั้งสองตัวกับนักศึกษา**ทุกคน**ในฐานข้อมูล ไม่ใช่สุ่มดูคนเดียว
-- ถ้าวันหนึ่งมีคนแก้กฎการจบจริง ๆ เทสต์นี้จะแดง และนั่นถูกแล้ว — ต้องแก้
-- ตัวอ้างอิงในไฟล์นี้ให้ตรงกันอย่างจงใจ ไม่ใช่แก้ผ่าน ๆ ให้เขียว
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── ตัวอ้างอิง: ตรวจจบฉบับก่อน 0051 (อ่าน view ซ้ำทุกกฎ) ──────────
create or replace function evaluate_graduation_ref(p_student_id uuid)
returns table (
  rule_id     uuid,
  kind        graduation_rule_kind,
  name_th     text,
  required    numeric,
  achieved    numeric,
  satisfied   boolean,
  is_blocking boolean
)
language plpgsql stable as $$
declare
  v_cv    uuid;
  v_gpax  numeric;
begin
  select sc.curriculum_version_id into v_cv
  from student_curriculum sc
  where sc.student_id = p_student_id and sc.effective_to is null;

  if v_cv is null then
    return;
  end if;

  select ts.gpax into v_gpax
  from term_summary ts
  where ts.student_id = p_student_id
  order by ts.computed_at desc
  limit 1;

  return query
  select
    g.id, g.kind, g.name_th, g.threshold, a.achieved,
    case when g.kind in ('cocurricular_all_terms', 'no_pending_grade', 'required_courses')
         then a.achieved <= coalesce(g.threshold, 0)
         else a.achieved >= coalesce(g.threshold, 0)
    end as satisfied,
    g.is_blocking
  from graduation_rule g
  cross join lateral (select (case g.kind
      when 'credits_total' then
        coalesce((select sum(v.credits_earned)
                  from v_student_course_credit v
                  where v.student_id = p_student_id and v.earns_credit), 0)
        + transfer_credits_total(p_student_id)
      when 'credits_by_category' then
        coalesce((select c.credits_earned
                  from v_student_credits_by_category c
                  join curriculum_category cat on cat.id = c.category_id
                  where c.student_id = p_student_id
                    and cat.curriculum_version_id = v_cv
                    and cat.code = g.params ->> 'category_code'), 0)
        + coalesce((select transfer_credits_by_category(p_student_id, cat.id)
                    from curriculum_category cat
                    where cat.curriculum_version_id = v_cv
                      and cat.code = g.params ->> 'category_code'), 0)
      when 'gpax_min' then coalesce(v_gpax, 0)
      when 'professional_standard' then
        (select count(*) from professional_standard_assessment a
         where a.student_id = p_student_id and a.result = 'pass')
      when 'cocurricular_all_terms' then
        (select count(*) from cocurricular_result cr
         where cr.student_id = p_student_id and cr.result <> 'pass')
      when 'practicum_hours' then
        coalesce((select sum(p.hours) from practicum_log p
                  where p.student_id = p_student_id and p.verified_at is not null), 0)
      when 'no_pending_grade' then
        (select count(*) from v_student_course_credit v
         where v.student_id = p_student_id and v.is_provisional)
      when 'required_courses' then
        (select count(*)
         from curriculum_course cc
         where cc.curriculum_version_id = v_cv
           and cc.requirement = 'required'
           and not exists (
             select 1 from v_student_course_credit v
             where v.student_id = p_student_id
               and v.course_id  = cc.course_id
               and v.earns_credit)
           and not exists (
             select 1 from prior_academic_record pr
             where pr.student_id = p_student_id
               and pr.mapped_course_id = cc.course_id
               and pr.earns_credit
               and pr.approved_at is not null))
      else 0
    end)::numeric as achieved) a
  where g.curriculum_version_id = v_cv
  order by g.sort_order;
end $$;

-- ── TEST 226 ───────────────────────────────────────────────────────
-- ผลของนักศึกษาทุกคนต้องเท่าเดิมทุกแถวทุกค่า
-- ═══════════════════════════════════════════════════════════════════
do $$
declare
  v_s        record;
  v_diff     integer;
  v_checked  integer := 0;
  v_rows     integer := 0;
  v_bad      text[] := '{}';
begin
  for v_s in select id from student order by id loop
    select count(*) into v_diff from (
      (select * from evaluate_graduation(v_s.id)
       except all
       select * from evaluate_graduation_ref(v_s.id))
      union all
      (select * from evaluate_graduation_ref(v_s.id)
       except all
       select * from evaluate_graduation(v_s.id))
    ) d;

    if v_diff > 0 then
      v_bad := array_append(v_bad, format('นักศึกษา %s ต่างกัน %s แถว', v_s.id, v_diff));
    end if;

    v_checked := v_checked + 1;
    v_rows := v_rows + (select count(*) from evaluate_graduation(v_s.id));
  end loop;

  if array_length(v_bad, 1) > 0 then
    raise exception 'TEST 226 ล้มเหลว: ผลตรวจจบเปลี่ยนไป — %',
      array_to_string(v_bad[1:5], ' · ');
  end if;

  if v_rows = 0 then
    raise exception 'TEST 226 ล้มเหลว: ตรวจ % คนแล้วไม่ได้กฎกลับมาเลยสักข้อ '
      '(ไม่มีใครผูกหลักสูตร เทสต์จึงไม่ได้เทียบอะไร)', v_checked;
  end if;

  raise notice 'TEST 226 ผ่าน — ผลเท่าเดิมทุกแถว (นักศึกษา % คน · กฎรวม % แถว)',
    v_checked, v_rows;
end $$;

-- ── TEST 227 ───────────────────────────────────────────────────────
-- ต้องเร็วกว่าตัวเดิมจริง ไม่ใช่แค่เขียนให้ดูดีขึ้น
--
-- ─── ทำไมเทียบกันเองแทนที่จะตั้งเพดานเป็นมิลลิวินาที ───
-- เพดานตายตัวจะแกว่งตามเครื่องที่รัน แต่การเทียบสองตัวในรอบเดียวกัน
-- บนเครื่องเดียวกันตัดตัวแปรนั้นออกทั้งหมด — ถ้าวันหนึ่งมีคนเผลอทำให้
-- CTE ถูก inline กลับไปอ่าน view ซ้ำทุกกฎ อัตราส่วนจะกลับมาเท่ากันเอง
--
-- รันเป็น app_runtime เพราะ superuser ข้าม RLS ทั้งหมด แล้วต้นทุนจริง
-- ของสคีมานี้จะหายไปจากการวัด
-- ═══════════════════════════════════════════════════════════════════
select s.id as sid, s.institution_id as inst, s.person_id as person
  from student s
  join student_curriculum sc on sc.student_id = s.id and sc.effective_to is null
 order by s.id
 limit 1 \gset

begin;
set local role app_runtime;
select set_config('app.institution_id', :'inst',   true) as a,
       set_config('app.actor_id',       :'person', true) as b,
       set_config('app.role',           'student', true) as c,
       set_config('test.sid',           :'sid',    false) as d \gset ctx_

do $$
declare
  v_sid  uuid := current_setting('test.sid')::uuid;
  v_i    integer;
  v_t    timestamptz;
  v_new  numeric;
  v_old  numeric;
  v_n    integer;
begin
  /*
   * ─── ต้องอุ่นให้ครบสิบรอบ ไม่ใช่รอบเดียว ───
   * plpgsql วางแผนคำสั่งแบบ custom plan ห้าครั้งแรกของทุกคำสั่งก่อนจะ
   * พิจารณาเปลี่ยนไปใช้ generic plan และการวางแผนของสคีมานี้แพงมาก
   * (นโยบาย RLS ถูกกางออกทุกครั้ง) การอุ่นรอบเดียวจึงทำให้เวลาที่วัดได้
   * เป็นค่าวางแผนของทั้งสองตัวเกือบทั้งหมด แล้วอัตราส่วนออกมาเป็น 1.1 เท่า
   * ทั้งที่ของจริงคือ 8-9 เท่า — เคยเขียนพลาดแบบนี้จริงและเกือบสรุปว่า
   * การแก้ไม่ได้ผล ตัวเลขที่วัดผ่าน HTTP ต่างหากที่บอกความจริง
   */
  for v_i in 1..10 loop
    select count(*) into v_n from evaluate_graduation(v_sid);
    select count(*) into v_n from evaluate_graduation_ref(v_sid);
  end loop;

  v_t := clock_timestamp();
  for v_i in 1..50 loop
    select count(*) into v_n from evaluate_graduation_ref(v_sid);
  end loop;
  v_old := extract(epoch from (clock_timestamp() - v_t)) * 1000;

  v_t := clock_timestamp();
  for v_i in 1..50 loop
    select count(*) into v_n from evaluate_graduation(v_sid);
  end loop;
  v_new := extract(epoch from (clock_timestamp() - v_t)) * 1000;

  -- เกณฑ์ตั้งไว้หลวมกว่าที่วัดได้จริงมาก (วัดได้ ~8.7 เท่า) เพื่อไม่ให้
  -- แกว่งตามเครื่อง แต่ยังจับได้ทันทีถ้ามีคนทำให้ CTE ถูก inline กลับไป
  -- อ่าน view ซ้ำทุกกฎ ซึ่งจะทำให้อัตราส่วนกลับไปเท่ากันเอง
  if v_new * 2 >= v_old then
    raise exception 'TEST 227 ล้มเหลว: ตัวใหม่เร็วกว่าไม่ถึงสองเท่า '
      '(ใหม่ % ms · เดิม % ms) — น่าจะมี CTE ถูก inline กลับไปอ่าน view ซ้ำทุกกฎ',
      round(v_new), round(v_old);
  end if;

  raise notice 'TEST 227 ผ่าน — 50 รอบ: ใหม่ % ms · เดิม % ms (เร็วขึ้น % เท่า)',
    round(v_new), round(v_old), round(v_old / greatest(v_new, 0.01), 1);
end $$;
rollback;

drop function if exists evaluate_graduation_ref(uuid);

do $$ begin raise notice ''; raise notice '════ ทดสอบตรวจจบแบบอ่านครั้งเดียวครบทุกข้อ ════'; end $$;

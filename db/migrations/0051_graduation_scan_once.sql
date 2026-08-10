-- ═══════════════════════════════════════════════════════════════════
-- 0051_graduation_scan_once.sql
--
-- ตรวจจบอ่านหน่วยกิตของนักศึกษาครั้งเดียว แทนที่จะอ่านซ้ำทุกกฎ
--
-- ─── ตัวเลขที่พาให้มาแก้ตรงนี้ ───
-- ทดสอบโหลดแล้ว `GET /students/:id/graduation` เป็นเส้นทางที่ช้าที่สุด
-- ของนักศึกษาอย่างชัดเจน — 62.8 ms ต่อคำขอ และตันที่ 85 คำขอต่อวินาที
-- ขณะที่การอ่านข้อมูลนักศึกษาธรรมดาทำได้ 1,891 คำขอต่อวินาที
-- ช่วงประกาศผลคือช่วงที่ทุกคนกดหน้านี้พร้อมกัน จึงเป็นภาระสูงสุดของทั้งปี
--
-- ─── ทำไมช้า ───
-- `evaluate_graduation()` วนทุกกฎใน `graduation_rule` แล้วประเมิน
-- `cross join lateral` ทีละกฎ กฎสามชนิดอ่าน `v_student_course_credit`
-- คนละครั้ง และกฎหมวดหน่วยกิตอ่าน `v_student_credits_by_category`
-- ซ้ำทุกหมวด — วัดแยกแล้ว view ตัวแรกใช้ execution 5 ms ต่อครั้ง
-- คูณกับกฎ 10 ข้อได้ ~50 ms ซึ่งตรงกับ 63 ms ที่วัดผ่าน HTTP
--
-- ─── ทำไมยังไม่ใส่แคช ───
-- การใส่แคชทับงานที่ซ้ำสิบรอบคือการจ่ายค่าความซับซ้อน (ล้างแคชเมื่อไร
-- ใครล้าง ข้อมูลค้างนานแค่ไหน) เพื่อซ่อนปัญหาที่แก้ได้ตรง ๆ และแคชผลตรวจจบ
-- อันตรายเป็นพิเศษ เพราะผลที่ค้างหนึ่งวันแปลว่านักศึกษาเห็นว่าตัวเอง
-- "ยังไม่ครบ" หลังจากที่ครูเพิ่งบันทึกให้แล้ว หรือแย่กว่านั้นคือเห็นว่าครบ
-- ทั้งที่ยังไม่ครบ
--
-- ─── ทำไมไม่รวบทุกกฎเป็นตัวเลขชุดเดียวไปเลย ───
-- ที่ดูเหมือนสะอาดกว่าคือคำนวณทุกค่าล่วงหน้าใน CTE เดียวแล้วให้แต่ละกฎ
-- หยิบไปใช้ แต่ `case` ประเมินเฉพาะแขนงที่ตรง หลักสูตรที่มีแค่สองกฎจึงจ่าย
-- แค่สองครั้ง การรวบไว้ก่อนจะบังคับให้จ่ายครบทุกชนิดเสมอ — เร็วขึ้นสำหรับ
-- หลักสูตรที่กฎครบ แต่ช้าลงสำหรับหลักสูตรที่กฎน้อย
--
-- จึงเก็บโครงเดิมไว้ทั้งหมด เปลี่ยนแค่**ที่มาของข้อมูล** ให้ชี้ไปที่ CTE
-- ที่อ่านมาแล้วครั้งเดียว ผลลัพธ์เท่าเดิมทุกแถวทุกค่า (TEST 226 เทียบกับ
-- ตัวเดิมทีละแถวเพื่อยืนยันข้อนี้ ไม่ใช่เชื่อตามที่เขียนไว้)
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function evaluate_graduation(p_student_id uuid)
returns table (
  rule_id     uuid,
  kind        graduation_rule_kind,
  name_th     text,
  required    numeric,
  achieved    numeric,
  satisfied   boolean,
  is_blocking boolean
)
language plpgsql stable
/*
 * ─── ทำไมต้องตรึงแผนไว้ ───
 * คำสั่งใหญ่ก้อนเดียวนี้ใช้เวลา **วางแผน 85 ms ต่อ execution 19 ms**
 * (นโยบาย RLS ของทุกตารางถูกกางออกเป็น SubPlan เกินสามสิบชุด) ตราบใดที่
 * PostgreSQL ยังเลือก custom plan มันจะวางแผนใหม่ทุกครั้งที่เรียก แล้ว
 * ค่าวางแผนอย่างเดียวก็กินเวลามากกว่างานจริงสี่เท่า
 *
 * และการตัดสินใจว่าจะใช้ custom หรือ generic plan ขึ้นกับสถิติของข้อมูล
 * จึงต่างกันได้ระหว่างฐานข้อมูลสองชุดที่มีสคีมาเดียวกัน — วัดจริงแล้ว
 * ฐานหนึ่งเลือก generic เอง (เร็วขึ้น 7 เท่าทันที) อีกฐานเลือก custom
 * แล้วการแก้ทั้งหมดนี้กลายเป็น **ช้าลง 20%** ทั้งที่โค้ดชุดเดียวกัน
 * นี่คือความต่างที่มองไม่เห็นเลยถ้าวัดฐานเดียว
 *
 * `force_generic_plan` ปลอดภัยตรงนี้เพราะพารามิเตอร์เดียวคือรหัสนักศึกษา
 * ซึ่งไม่มีนักศึกษาคนไหนที่แผนควรต่างออกไป — วัดแล้ว execution เท่ากัน
 * ทุกฐาน (19 ms) ต่างกันแค่ว่าจ่ายค่าวางแผนซ้ำหรือไม่
 */
set plan_cache_mode = force_generic_plan
as $$
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
  -- `materialized` ทั้งสามตัวโดยตั้งใจ — ถ้าปล่อยให้ PostgreSQL inline
  -- เข้าไปในแขนงของ case มันจะกลับไปอ่าน view ใหม่ทุกกฎ ซึ่งคือปัญหาเดิม
  -- ทั้งหมด CTE ที่ไม่ถูกอ้างถึงเลยจะไม่ถูกประเมิน หลักสูตรที่ไม่มีกฎ
  -- หมวดหน่วยกิตจึงไม่จ่ายค่า cat_credit
  with credit as materialized (
    select v.course_id, v.credits_earned, v.earns_credit, v.is_provisional
      from v_student_course_credit v
     where v.student_id = p_student_id
  ),
  -- ต้องจำกัดเฉพาะหมวดที่มีกฎอ้างถึงจริง ไม่ใช่ทุกหมวดของหลักสูตร
  --
  -- ครั้งแรกเขียนเป็น "ทุกหมวด" ด้วยเหตุผลว่าอ่านทีเดียวจบ ผลคือเร็วขึ้น
  -- 8 เท่าบนฐานข้อมูลหนึ่ง แต่ **ช้าลง** บนอีกฐานหนึ่งที่มี 18 หมวด
  -- (เทียบกับ 9 หมวด) เพราะของเดิมดึงเฉพาะหมวดที่กฎถามถึงสามหมวด
  -- ส่วนตัวใหม่ดึงมาทั้งสิบแปด — ประหยัดจำนวนครั้งแต่จ่ายเนื้องานมากขึ้น
  -- จนกลบกันหมด
  --
  -- ที่ถูกคือดึง **ครั้งเดียว** และ **เท่าที่ต้องใช้** ทั้งสองอย่างพร้อมกัน
  cat_credit as materialized (
    select cat.code, c.credits_earned
      from v_student_credits_by_category c
      join curriculum_category cat on cat.id = c.category_id
     where c.student_id = p_student_id
       and cat.curriculum_version_id = v_cv
       and cat.code in (select g2.params ->> 'category_code'
                          from graduation_rule g2
                         where g2.curriculum_version_id = v_cv
                           and g2.kind = 'credits_by_category')
  ),
  transferred as materialized (
    select pr.mapped_course_id
      from prior_academic_record pr
     where pr.student_id = p_student_id
       and pr.earns_credit
       and pr.approved_at is not null
  )
  select
    g.id,
    g.kind,
    g.name_th,
    g.threshold,
    a.achieved,
    -- กฎสามข้อล่างเป็น "จำนวนที่ยังค้าง" ยิ่งน้อยยิ่งดี เกณฑ์คือไม่เกิน threshold (ปกติ 0)
    -- ที่เหลือเป็น "สะสมได้เท่าไร" ต้องไม่น้อยกว่า threshold
    case when g.kind in ('cocurricular_all_terms', 'no_pending_grade', 'required_courses')
         then a.achieved <= coalesce(g.threshold, 0)
         else a.achieved >= coalesce(g.threshold, 0)
    end as satisfied,
    g.is_blocking
  from graduation_rule g
  cross join lateral (select (case g.kind

      when 'credits_total' then
        coalesce((select sum(c.credits_earned) from credit c where c.earns_credit), 0)
        -- หน่วยกิตที่เทียบโอนมาและอนุมัติแล้ว
        + transfer_credits_total(p_student_id)

      when 'credits_by_category' then
        coalesce((select cc.credits_earned from cat_credit cc
                   where cc.code = g.params ->> 'category_code'), 0)
        + coalesce((select transfer_credits_by_category(p_student_id, cat.id)
                    from curriculum_category cat
                    where cat.curriculum_version_id = v_cv
                      and cat.code = g.params ->> 'category_code'), 0)

      when 'gpax_min' then
        -- ไม่รวมเกรดเทียบโอนโดยตั้งใจ — หน่วยกิตโอนได้แต่เกรดไม่โอน
        coalesce(v_gpax, 0)

      when 'professional_standard' then
        (select count(*) from professional_standard_assessment a
         where a.student_id = p_student_id and a.result = 'pass')

      when 'cocurricular_all_terms' then
        -- จำนวนภาคเรียนที่ยังไม่ผ่าน ยิ่งน้อยยิ่งดี เกณฑ์คือ 0
        (select count(*) from cocurricular_result cr
         where cr.student_id = p_student_id and cr.result <> 'pass')

      when 'practicum_hours' then
        coalesce((select sum(p.hours) from practicum_log p
                  where p.student_id = p_student_id and p.verified_at is not null), 0)

      when 'no_pending_grade' then
        (select count(*) from credit c where c.is_provisional)

      when 'required_courses' then
        -- จำนวนรายวิชาบังคับที่ยังไม่ผ่าน เกณฑ์คือ 0
        (select count(*)
         from curriculum_course cc
         where cc.curriculum_version_id = v_cv
           and cc.requirement = 'required'
           and not exists (
             select 1 from credit c
             where c.course_id = cc.course_id and c.earns_credit
           )
           -- รายวิชาบังคับที่เทียบโอนมาแล้วต้องไม่นับว่ายังขาด
           and not exists (
             select 1 from transferred t where t.mapped_course_id = cc.course_id
           ))

      else 0
    end)::numeric as achieved) a
  where g.curriculum_version_id = v_cv
  order by g.sort_order;
end $$;

comment on function evaluate_graduation is
  'ตรวจจบแบบเรียกได้ทุกเมื่อ — อ่านหน่วยกิตของนักศึกษาครั้งเดียวแล้วให้ทุกกฎใช้ร่วมกัน';

commit;

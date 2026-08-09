-- ═══════════════════════════════════════════════════════════════════
-- 0016_grade_computation.sql
--
-- ตัดเกรดจากสมุดคะแนน และขั้นตอนอนุมัติเกรด
--
-- ─── ทำไมกฎอยู่ในฐานข้อมูล ไม่ใช่ในโค้ดแอป ───
-- เหตุผลเดียวกับ check_registration() และ issue_invoice() — กฎที่อยู่ใน
-- ฐานข้อมูลบังคับใช้กับทุกทางที่เข้าถึงข้อมูล ไม่ว่าจะผ่าน API ผ่าน pgAdmin
-- หรือผ่านสคริปต์นำเข้าข้อมูลจากระบบเดิม การตัดเกรดเป็นจุดที่ผิดแล้ว
-- แก้ยากที่สุด เพราะเอกสาร รบ.1 ที่ออกไปแล้วต้องเรียกคืน
--
-- ─── ลำดับการตัดสิน ───
-- 1. เวลาเรียนไม่ถึงเกณฑ์  → ข.ร. ไม่ต้องดูคะแนนเลย
-- 2. ยังกรอกคะแนนไม่ครบ    → ม.ส. ผลชั่วคราวที่ต้องแก้ภายในกำหนด
-- 3. นอกนั้น               → เทียบคะแนนถ่วงน้ำหนักกับช่วงคะแนนตัดเกรด
--
-- ข้อ 1 มาก่อนข้อ 3 เสมอ เพราะระเบียบกำหนดว่านักศึกษาที่เวลาเรียนไม่ถึง
-- ไม่มีสิทธิ์เข้ารับการประเมินสรุปผล ต่อให้คะแนนเก็บสูงแค่ไหนก็ตาม
--
-- ─── ทำไม attendance_pct ถูกตรึงไว้ในแถวผลการเรียน ───
-- ห้ามคำนวณใหม่ตอนพิมพ์เอกสาร มิฉะนั้นเอกสารที่ออกย้อนหลังจะไม่ตรงกับ
-- ที่เคยออกไป เพราะคาบเรียนอาจถูกเพิ่มหรือแก้ทีหลัง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- ตัดเกรดแบบดูอย่างเดียว — ไม่เขียนอะไรลงฐานข้อมูล
--
-- ครูเปิดหน้าจอนี้ดูก่อนกดส่งได้เสมอ และดูได้กี่ครั้งก็ได้
-- ระบบเก่าที่คำนวณตอนกดส่งอย่างเดียวทำให้ครูไม่กล้ากด เพราะไม่รู้ว่าจะได้อะไร
-- ───────────────────────────────────────────────────────────────────
create or replace function compute_section_grades(p_class_section_id uuid)
returns table (
  enrollment_id    uuid,
  student_code     text,
  full_name        text,
  weighted_score   numeric,
  weight_recorded  numeric,
  weight_total     numeric,
  attendance_pct   numeric,
  attendance_state text,
  grade_symbol_id  uuid,
  symbol           text,
  grade_point      numeric,
  credits_earned   numeric,
  note_th          text
)
language plpgsql stable as $$
declare
  v_scheme_id  uuid;
  v_credits    numeric;
  v_mode       text;
  v_weight_all numeric;
  r            record;
  v_symbol     record;
  v_note       text;
begin
  select cv.grade_scheme_id, c.credits, c.grading_mode::text
    into v_scheme_id, v_credits, v_mode
    from class_section cs
    join course c on c.id = cs.course_id
    left join curriculum_version cv on cv.id = cs.curriculum_version_id
   where cs.id = p_class_section_id;

  if not found then
    raise exception 'ไม่พบกลุ่มเรียน % (หรือไม่มีสิทธิ์เข้าถึง)', p_class_section_id;
  end if;

  if v_scheme_id is null then
    raise exception 'กลุ่มเรียนนี้ยังไม่ได้ผูกกับฉบับหลักสูตร จึงไม่รู้ว่าใช้ระเบียบวัดผลชุดไหน';
  end if;

  select coalesce(sum(weight), 0) into v_weight_all
    from gradebook_item where class_section_id = p_class_section_id;

  for r in
    select e.id                                             as enr_id,
           s.student_code                                   as code,
           p.first_name_th || ' ' || p.last_name_th         as name,
           -- คะแนนถ่วงน้ำหนัก: แต่ละชิ้นเทียบสัดส่วนของคะแนนเต็มแล้วคูณน้ำหนัก
           coalesce(sum(gsc.score / gi.max_score * gi.weight), 0)                  as weighted,
           coalesce(sum(gi.weight) filter (where gsc.score is not null), 0)        as w_recorded,
           va.pct_final                                     as att_pct,
           va.attendance_state                              as att_state,
           va.min_pct                                       as att_min
      from enrollment e
      join student s on s.id = e.student_id
      join person  p on p.id = s.person_id
      left join v_enrollment_attendance va on va.enrollment_id = e.id
      left join gradebook_item  gi  on gi.class_section_id = p_class_section_id
      left join gradebook_score gsc on gsc.gradebook_item_id = gi.id
                                   and gsc.enrollment_id     = e.id
     where e.class_section_id = p_class_section_id
       and e.status = 'enrolled'
     group by e.id, s.student_code, p.first_name_th, p.last_name_th,
              va.pct_final, va.attendance_state, va.min_pct
     order by s.student_code
  loop
    v_note := null;

    -- ── 1. เวลาเรียนไม่ถึงเกณฑ์ → ข.ร. ไม่ต้องดูคะแนน ───────────
    if r.att_pct is not null and r.att_min is not null and r.att_pct < r.att_min then
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_symbol gs
       where gs.grade_scheme_id = v_scheme_id and gs.symbol = 'ข.ร.';
      v_note := format('เวลาเรียน %s%% ต่ำกว่าเกณฑ์ %s%%', r.att_pct, r.att_min);

    -- ── 2. กรอกคะแนนไม่ครบ → ม.ส. ผลชั่วคราว ────────────────────
    elsif v_weight_all = 0 or r.w_recorded < v_weight_all then
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_symbol gs
       where gs.grade_scheme_id = v_scheme_id and gs.symbol = 'ม.ส.';
      v_note := case
                  when v_weight_all = 0 then 'ยังไม่ได้กำหนดชิ้นงานในสมุดคะแนน'
                  else format('กรอกคะแนนแล้ว %s จากน้ำหนักรวม %s', r.w_recorded, v_weight_all)
                end;

    -- ── 3. รายวิชาแบบผ่าน/ไม่ผ่าน ────────────────────────────────
    elsif v_mode = 'pass_fail' then
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_symbol gs
       where gs.grade_scheme_id = v_scheme_id
         and gs.symbol = case when r.weighted >= 50 then 'ผ.' else 'ม.ผ.' end;

    -- ── 4. เทียบช่วงคะแนนตัดเกรด ─────────────────────────────────
    else
      select gs.id, gs.symbol, gs.grade_point, gs.earns_credit
        into v_symbol
        from grade_cutoff gc
        join grade_symbol gs on gs.id = gc.grade_symbol_id
       where gc.grade_scheme_id = v_scheme_id
         and gc.min_score <= r.weighted
       order by gc.min_score desc
       limit 1;
    end if;

    if v_symbol.id is null then
      raise exception
        'ระเบียบวัดผลของหลักสูตรนี้ไม่มีสัญลักษณ์ที่ต้องใช้ (นักศึกษา %) — ตรวจ grade_symbol และ grade_cutoff',
        r.code;
    end if;

    enrollment_id    := r.enr_id;
    student_code     := r.code;
    full_name        := r.name;
    weighted_score   := round(r.weighted, 2);
    weight_recorded  := r.w_recorded;
    weight_total     := v_weight_all;
    attendance_pct   := r.att_pct;
    attendance_state := r.att_state;
    grade_symbol_id  := v_symbol.id;
    symbol           := v_symbol.symbol;
    grade_point      := v_symbol.grade_point;
    credits_earned   := case when v_symbol.earns_credit then v_credits else 0 end;
    note_th          := v_note;
    return next;
  end loop;
end $$;

comment on function compute_section_grades(uuid) is
  'ตัดเกรดจากสมุดคะแนนแบบดูอย่างเดียว ไม่เขียนอะไรลงฐานข้อมูล ครูเปิดดูก่อนกดส่งได้เสมอ';

-- ───────────────────────────────────────────────────────────────────
-- ครูส่งเกรด — เขียน enrollment_result แล้วเลื่อนขั้นเป็น teacher_submitted
--
-- ทั้งหมดอยู่ในธุรกรรมเดียว ถ้านักศึกษาคนใดคนหนึ่งตัดเกรดไม่ได้
-- จะไม่มีใครถูกบันทึกเลย เพราะเกรดที่ลงครึ่งห้องแย่กว่าไม่ลงเลย
-- ───────────────────────────────────────────────────────────────────

-- การส่งใหม่หลังถูกตีกลับต้องแทนที่แถวเดิม ไม่ใช่แก้ทับ
-- ลำดับที่จำเป็นคือ ชี้แถวเดิมไปหาแถวใหม่ก่อน แล้วค่อยเพิ่มแถวใหม่
-- เพราะดัชนี enrollment_result_current ยอมให้มีแถวที่ superseded_by is null
-- ได้แค่แถวเดียวต่อการลงทะเบียนหนึ่งรายการ
--
-- ตอนชี้ แถวใหม่ยังไม่มีอยู่จริง คีย์นอกจึงต้องเลื่อนไปตรวจตอน commit
alter table enrollment_result
  drop constraint enrollment_result_superseded_by_fkey;
alter table enrollment_result
  add constraint enrollment_result_superseded_by_fkey
  foreign key (superseded_by) references enrollment_result(id)
  deferrable initially deferred;

create or replace function submit_section_grades(p_class_section_id uuid)
returns table (submission_id uuid, results_written integer)
language plpgsql as $$
declare
  v_sub     grade_submission%rowtype;
  v_term    uuid;
  v_n       integer := 0;
  v_new_id  uuid;
  v_current enrollment_result%rowtype;
  r         record;
begin
  select cs.term_id into v_term from class_section cs where cs.id = p_class_section_id;
  if not found then
    raise exception 'ไม่พบกลุ่มเรียน % (หรือไม่มีสิทธิ์เข้าถึง)', p_class_section_id;
  end if;

  select * into v_sub from grade_submission where class_section_id = p_class_section_id;

  if not found then
    insert into grade_submission (class_section_id, term_id, stage)
    values (p_class_section_id, v_term, 'draft')
    returning * into v_sub;
  end if;

  -- ส่งซ้ำได้เฉพาะตอนยังไม่ส่ง หรือถูกตีกลับมาแก้
  if v_sub.stage not in ('draft', 'returned') then
    raise exception
      'รอบส่งเกรดของกลุ่มนี้อยู่ขั้น % แล้ว ส่งซ้ำไม่ได้ ถ้าต้องแก้ให้ผู้อนุมัติตีกลับก่อน',
      v_sub.stage;
  end if;

  -- ยังมีคาบที่ยังไม่ได้สอน = เวลาเรียนยังไม่ใช่ตัวเลขสุดท้าย
  --
  -- ถ้าปล่อยให้ส่งตอนนี้ pct_final จะต่ำโดยธรรมชาติเพราะตัวหารคือคาบทั้งภาค
  -- ผลคือทั้งห้องได้ ข.ร. ทั้งที่ยังเรียนไม่จบ ซึ่งเป็นความผิดพลาดที่
  -- มองไม่ออกจากหน้าจอ — ครูเห็นแค่ว่า "ระบบตัดเกรดให้แล้ว"
  declare v_pending integer;
  begin
    select count(*) into v_pending
      from class_meeting
     where class_section_id = p_class_section_id and status = 'scheduled';

    if v_pending > 0 then
      raise exception
        'กลุ่มนี้ยังมีคาบที่ยังไม่ได้สอนอีก % คาบ เวลาเรียนจึงยังไม่ใช่ตัวเลขสุดท้าย ส่งเกรดไม่ได้',
        v_pending;
    end if;
  end;

  for r in select * from compute_section_grades(p_class_section_id) loop
    select * into v_current
      from enrollment_result er
     where er.enrollment_id = r.enrollment_id
       and er.superseded_by is null;

    -- ผลเดิมเหมือนเดิมทุกอย่างก็ไม่ต้องออก revision ใหม่
    -- ไม่งั้นการกดส่งซ้ำจะสร้างประวัติปลอมเต็มบัญชีตรวจสอบ
    if found
       and v_current.grade_symbol_id = r.grade_symbol_id
       and v_current.raw_score      is not distinct from r.weighted_score
       and v_current.attendance_pct is not distinct from r.attendance_pct then
      continue;
    end if;

    v_new_id := gen_random_uuid();

    if found then
      update enrollment_result
         set superseded_by = v_new_id
       where id = v_current.id;
    end if;

    insert into enrollment_result (
      id, enrollment_id, submission_id, revision,
      raw_score, attendance_pct, grade_symbol_id, grade_point, credits_earned,
      computed_by, reason
    )
    values (
      v_new_id, r.enrollment_id, v_sub.id,
      coalesce(v_current.revision, 0) + 1,
      r.weighted_score, r.attendance_pct, r.grade_symbol_id,
      r.grade_point, r.credits_earned,
      current_actor_id(),
      case when v_current.id is not null then 'ส่งเกรดใหม่หลังถูกตีกลับ' end
    );

    v_n := v_n + 1;
  end loop;

  update grade_submission
     set stage = 'teacher_submitted',
         submitted_by = current_actor_id(),
         submitted_at = now()
   where id = v_sub.id;

  insert into grade_submission_event (submission_id, from_stage, to_stage, actor_id, note)
  values (v_sub.id, v_sub.stage, 'teacher_submitted', current_actor_id(),
          format('ส่งผลการเรียน %s คน', v_n));

  submission_id   := v_sub.id;
  results_written := v_n;
  return next;
end $$;

comment on function submit_section_grades(uuid) is
  'ครูส่งเกรดทั้งกลุ่มในธุรกรรมเดียว ถ้าคนใดคนหนึ่งตัดไม่ได้จะไม่มีใครถูกบันทึกเลย';

-- ───────────────────────────────────────────────────────────────────
-- เลื่อนขั้นอนุมัติ
--
-- ครูผู้สอน → หัวหน้าแผนกวิชา → ฝ่ายวิชาการ → ผู้อำนวยการ → ล็อก
--
-- บังคับลำดับไว้ในฐานข้อมูล ไม่ใช่ในโค้ดแอป เพราะการข้ามขั้นคือช่องทาง
-- ที่ใช้แก้เกรดโดยไม่ผ่านการตรวจสอบ ซึ่งเป็นเหตุผลที่ขั้นตอนนี้มีอยู่ตั้งแต่แรก
-- ───────────────────────────────────────────────────────────────────
create or replace function advance_grade_submission(
  p_submission_id uuid,
  p_to_stage      submission_stage,
  p_note          text default null
) returns submission_stage
language plpgsql as $$
declare
  v_sub      grade_submission%rowtype;
  v_expected submission_stage;
begin
  select * into v_sub from grade_submission where id = p_submission_id;
  if not found then
    raise exception 'ไม่พบรอบส่งเกรด % (หรือไม่มีสิทธิ์เข้าถึง)', p_submission_id;
  end if;

  if v_sub.stage = 'locked' then
    raise exception 'รอบส่งเกรดนี้ล็อกแล้ว การแก้ต้องยื่นคำร้องแก้เกรดที่ต้องมีผู้อนุมัติสองคน';
  end if;

  -- ตีกลับให้ครูแก้ ทำได้จากทุกขั้นก่อนล็อก
  if p_to_stage = 'returned' then
    if v_sub.stage = 'draft' then
      raise exception 'รอบส่งเกรดนี้ยังไม่ถูกส่ง จึงตีกลับไม่ได้';
    end if;
  else
    v_expected := case v_sub.stage
                    when 'teacher_submitted' then 'head_approved'
                    when 'head_approved'     then 'academic_approved'
                    when 'academic_approved' then 'director_approved'
                    when 'director_approved' then 'locked'
                    when 'returned'          then 'teacher_submitted'
                  end::submission_stage;

    if v_expected is null then
      raise exception 'ขั้น % เลื่อนต่อไม่ได้ ต้องให้ครูส่งเกรดก่อน', v_sub.stage;
    end if;

    if p_to_stage <> v_expected then
      raise exception 'ข้ามขั้นไม่ได้ — จากขั้น % ไปได้เฉพาะ % (ขอไป %)',
        v_sub.stage, v_expected, p_to_stage;
    end if;
  end if;

  update grade_submission
     set stage = p_to_stage,
         locked_at = case when p_to_stage = 'locked' then now() else locked_at end
   where id = p_submission_id;

  insert into grade_submission_event (submission_id, from_stage, to_stage, actor_id, note)
  values (p_submission_id, v_sub.stage, p_to_stage, current_actor_id(), p_note);

  return p_to_stage;
end $$;

comment on function advance_grade_submission(uuid, submission_stage, text) is
  'เลื่อนขั้นอนุมัติเกรดทีละขั้น ห้ามข้ามขั้น เพราะการข้ามขั้นคือช่องทางแก้เกรดโดยไม่ผ่านการตรวจสอบ';

-- ───────────────────────────────────────────────────────────────────
-- คำนวณ GPA และ GPAX ลง term_summary
--
-- ─── ทำไม GPAX ต้องคิดสะสมจากทุกภาคเรียน ไม่ใช่เฉลี่ยของ GPA ───
-- ค่าเฉลี่ยของค่าเฉลี่ยไม่เท่ากับค่าเฉลี่ยรวม ถ้าภาคหนึ่งลง 21 หน่วยกิต
-- อีกภาคลง 9 หน่วยกิต การเฉลี่ย GPA สองตัวจะให้น้ำหนักภาคเล็กเกินจริง
-- GPAX ที่ผิดกระทบการจบและการสมัครเรียนต่อโดยตรง
-- ───────────────────────────────────────────────────────────────────
create or replace function compute_term_summary(p_term_id uuid)
returns integer
language plpgsql as $$
declare v_n integer := 0;
begin
  insert into term_summary (student_id, term_id, credits_attempted, credits_earned, gpa, gpax, computed_at)
  select t.student_id,
         p_term_id,
         t.credits_attempted,
         t.credits_earned,
         t.gpa,
         x.gpax,
         now()
    from (
      -- ภาคเรียนนี้
      select e.student_id,
             sum(co.credits)                                              as credits_attempted,
             sum(er.credits_earned)                                       as credits_earned,
             case when sum(co.credits) filter (where sy.counts_in_gpa) > 0
                  then round(sum(er.grade_point * co.credits) filter (where sy.counts_in_gpa)
                             / sum(co.credits) filter (where sy.counts_in_gpa), 2)
             end                                                          as gpa
        from enrollment_result er
        join enrollment    e  on e.id  = er.enrollment_id
        join class_section cs on cs.id = e.class_section_id
        join course        co on co.id = cs.course_id
        join grade_symbol  sy on sy.id = er.grade_symbol_id
       where er.superseded_by is null
         and e.term_id = p_term_id
         and e.counts_toward_gpa
       group by e.student_id
    ) t
    join lateral (
      -- สะสมทุกภาคเรียนจนถึงภาคนี้ — คิดจากหน่วยกิตรวม ไม่ใช่เฉลี่ยของ GPA
      select case when sum(co.credits) filter (where sy.counts_in_gpa) > 0
                  then round(sum(er.grade_point * co.credits) filter (where sy.counts_in_gpa)
                             / sum(co.credits) filter (where sy.counts_in_gpa), 2)
             end as gpax
        from enrollment_result er
        join enrollment    e2 on e2.id = er.enrollment_id
        join class_section cs on cs.id = e2.class_section_id
        join course        co on co.id = cs.course_id
        join grade_symbol  sy on sy.id = er.grade_symbol_id
        join term          tm on tm.id = e2.term_id
       where er.superseded_by is null
         and e2.student_id = t.student_id
         and e2.counts_toward_gpa
         and tm.starts_on <= (select starts_on from term where id = p_term_id)
    ) x on true
      on conflict (student_id, term_id) do update
      set credits_attempted = excluded.credits_attempted,
          credits_earned    = excluded.credits_earned,
          gpa               = excluded.gpa,
          gpax              = excluded.gpax,
          computed_at       = excluded.computed_at;

  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function compute_term_summary(uuid) is
  'คำนวณ GPA รายภาคและ GPAX สะสมลง term_summary — GPAX คิดจากหน่วยกิตรวม ไม่ใช่เฉลี่ยของ GPA';

commit;

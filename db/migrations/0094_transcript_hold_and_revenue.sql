-- ═══════════════════════════════════════════════════════════════════
-- บล็อกพิมพ์ใบ รบ. เมื่อมียอดค้างชำระเกินกำหนด + มุมมองรายงานรายรับ
--
-- ทั้งสองเรื่องนี้อยู่ในรายการ "ที่ยังไม่ได้ทำ" ของศูนย์การเงิน —
-- `registration_hold.blocks_transcript` มีคอลัมน์มาตั้งแต่ 0009 แต่
-- `refresh_finance_holds()` (0010) ไม่เคยตั้งเป็น true เลยสักครั้ง
-- เป็นแบบเดียวกับ `take_usage_snapshot()` และ `program_type` ที่ CLAUDE.md
-- บันทึกไว้ — คอลัมน์ที่ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น
--
-- ตามหลัก 5ข (โควตาเริ่มต้นเป็นแบบเตือน ไม่ใช่บล็อก) การบล็อกพิมพ์ใบ รบ.
-- ต้องเป็นทางเลือกที่วิทยาลัยเปิดเอง ไม่ใช่ค่าเริ่มต้นที่ทำให้ลูกค้าเดิม
-- ถูกบล็อกทันทีหลัง deploy — จึงเพิ่มคอลัมน์ตั้งค่าแยกที่ default เป็น false
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table late_fee_policy
  add column blocks_transcript_after_hold boolean not null default false;

comment on column late_fee_policy.blocks_transcript_after_hold is
  'เปิดแล้วเท่านั้นที่การระงับสิทธิ์จะบล็อกการพิมพ์ใบ รบ. ด้วย — ค่าเริ่มต้นปิด ตามหลัก 5ข';

-- ───────────────────────────────────────────────────────────────────
-- refresh_finance_holds() — ตั้ง blocks_transcript ตามนโยบายจริง
-- (ทับจาก 0010 เฉพาะประโยค insert หนึ่งจุด ที่เหลือเหมือนเดิมทุกประการ)
-- ───────────────────────────────────────────────────────────────────
create or replace function refresh_finance_holds(p_institution_id uuid)
returns table (placed integer, released integer)
language plpgsql as $$
declare
  v_policy late_fee_policy%rowtype;
  v_placed   integer := 0;
  v_released integer := 0;
  r          record;
begin
  select * into v_policy from late_fee_policy
  where institution_id = p_institution_id
  order by effective_from_year_be desc limit 1;

  if v_policy.id is null then
    raise exception 'ยังไม่ได้ตั้งนโยบายค่าปรับและการระงับสิทธิ์ของสถานศึกษานี้';
  end if;

  -- ตั้งสถานะเกินกำหนดให้งวดที่พ้นกำหนดแล้ว
  update installment i
  set status = 'overdue'
  from invoice inv
  where inv.id = i.invoice_id
    and inv.institution_id = p_institution_id
    and inv.status in ('issued', 'partially_paid')
    and i.status in ('pending', 'partially_paid')
    and i.due_on < current_date - v_policy.grace_days;

  -- ระงับสิทธิ์คนที่ค้างเกินกำหนดและยังไม่ถูกระงับ
  for r in
    select inv.student_id,
           sum(i.amount + i.penalty - i.paid_amount) as owed,
           min(i.due_on)                             as oldest_due,
           min(inv.invoice_no)                       as ref
    from installment i
    join invoice inv on inv.id = i.invoice_id
    where inv.institution_id = p_institution_id
      and inv.status in ('issued', 'partially_paid')
      and i.status <> 'paid'
      and i.due_on < current_date - v_policy.hold_after_days
      and i.amount + i.penalty - i.paid_amount > 0
    group by inv.student_id
  loop
    if not exists (
      select 1 from registration_hold h
      where h.student_id = r.student_id and h.kind = 'finance' and h.released_at is null
    ) then
      insert into registration_hold
        (student_id, kind, reason, amount, source_module, source_ref,
         blocks_registration, blocks_transcript)
      values (r.student_id, 'finance',
              format('ค้างชำระเกิน %s วัน ครบกำหนดตั้งแต่ %s',
                     v_policy.hold_after_days, to_char(r.oldest_due, 'DD/MM/YYYY')),
              r.owed, 'finance', r.ref, true, v_policy.blocks_transcript_after_hold);
      v_placed := v_placed + 1;
    end if;
  end loop;

  -- ปลดคนที่ชำระครบแล้ว
  with cleared as (
    select h.id
    from registration_hold h
    join student s on s.id = h.student_id
    where s.institution_id = p_institution_id
      and h.kind = 'finance'
      and h.released_at is null
      and not exists (
        select 1
        from installment i
        join invoice inv on inv.id = i.invoice_id
        where inv.student_id = h.student_id
          and inv.status in ('issued', 'partially_paid')
          and i.status <> 'paid'
          and i.amount + i.penalty - i.paid_amount > 0
      )
  )
  update registration_hold h
  set released_at = now(), release_reason = 'ชำระครบแล้ว ระบบปลดอัตโนมัติ'
  from cleared c where c.id = h.id;

  get diagnostics v_released = row_count;
  return query select v_placed, v_released;
end $$;

comment on function refresh_finance_holds is
  'ให้ตั้งเป็นงานประจำวัน งานทะเบียนไม่ต้องรู้จักใบแจ้งหนี้ เห็นแค่ registration_hold';

-- ───────────────────────────────────────────────────────────────────
-- issue_document_core() — ปฏิเสธการออกใบ รบ. เมื่อมีการระงับที่บล็อกอยู่
-- (ทับจาก 0059 เฉพาะการเพิ่มเงื่อนไขนี้หนึ่งจุด ที่เหลือเหมือนเดิมทุกประการ)
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_document_core(p_student_id uuid, p_kind document_kind, p_year_be smallint, p_term_id uuid, p_lang text)
 RETURNS issued_document
 LANGUAGE plpgsql
AS $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
  v_cv      uuid;
begin
  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ';
  end if;
  -- ใบ รบ. พิมพ์ไม่ได้ถ้ามีการระงับสิทธิ์ที่ตั้งใจให้บล็อกใบนี้อยู่
  -- (registration_hold.blocks_transcript — ค่าเริ่มต้นเป็น false เสมอ
  -- จนกว่าวิทยาลัยจะเปิดเองที่ late_fee_policy.blocks_transcript_after_hold)
  if v_kind = 'transcript'
     and exists (select 1 from registration_hold h
                  where h.student_id = p_student_id
                    and h.released_at is null
                    and h.blocks_transcript) then
    raise exception 'พิมพ์ใบ รบ. ไม่ได้ ระบุว่ามีการระงับสิทธิ์เนื่องจากค้างชำระอยู่ — ให้ชำระหรือปลดการระงับที่ศูนย์การเงินก่อน'
      using errcode = 'check_violation';
  end if;
  -- ใบประกาศนียบัตรออกให้คนที่ยังไม่ได้รับอนุมัติจบไม่ได้
  if v_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;
  if v_kind = 'grade_report' and p_term_id is null then
    raise exception 'ออกสมุดพกต้องระบุภาคเรียน มิฉะนั้นจะได้ผลการเรียนของภาคที่ไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;
  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;
  v_year := coalesce(
    p_year_be,
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );
  v_doc_no := next_document_no(p_kind, v_year, p_lang);
  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
    'lang',        p_lang,
    'issued_at',   now(),
    'year_be',     v_year,
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code',  s.student_code,
                     'prefix_th',     coalesce(p.prefix_th, ''),
                     'first_name_th', coalesce(p.first_name_th, ''),
                     'last_name_th',  coalesce(p.last_name_th, ''),
                     'full_name_th',  trim(coalesce(p.prefix_th, '')
                                        || coalesce(p.first_name_th, '')
                                        || ' ' || coalesce(p.last_name_th, '')),
                     'birth_date',    p.birth_date,
                     'admitted_year_be', s.admitted_year_be,
                     'status',        s.status,
                     -- ฉบับอังกฤษต้องมีชื่ออังกฤษ ซึ่ง issue_document()
                     -- ตรวจแล้วว่าไม่ว่างก่อนเรียกมาถึงตรงนี้
                     'prefix_en',     coalesce(p.prefix_en, ''),
                     'first_name_en', coalesce(p.first_name_en, ''),
                     'last_name_en',  coalesce(p.last_name_en, ''),
                     'full_name_en',  trim(coalesce(p.prefix_en, '')
                                        || ' ' || coalesce(p.first_name_en, '')
                                        || ' ' || coalesce(p.last_name_en, ''))),
    'program',     (select jsonb_build_object(
                             'type_th',       pt.name_th,
                             'name_th',       pr.name_th,
                             'track_th',      ptr.name_th,
                             'curriculum_th', cur.name_th,
                             'shift',         cur.shift,
                             'level',         pr.level,
                             'edition_be',    cv.edition_be,
                             'qualification_th',
                               case pr.level
                                 when 'PVC' then 'ประกาศนียบัตรวิชาชีพ'
                                 when 'PVS' then 'ประกาศนียบัตรวิชาชีพชั้นสูง'
                                 when 'TVB' then 'ปริญญาตรีสายเทคโนโลยีหรือสายปฏิบัติการ'
                               end,
                             'qualification_abbr_th',
                               case pr.level
                                 when 'PVC' then 'ปวช.'
                                 when 'PVS' then 'ปวส.'
                                 when 'TVB' then 'ทล.บ.'
                               end,
                             'type_en',       coalesce(pt.name_en, ''),
                             'name_en',       coalesce(pr.name_en, ''),
                             'track_en',      coalesce(ptr.name_en, ''),
                             'curriculum_en', coalesce(cur.name_en, ''),
                             'is_continuing', cur.is_continuing,
                             'qualification_en',
                               case pr.level
                                 when 'PVC' then 'Vocational Certificate'
                                 when 'PVS' then 'High Vocational Certificate'
                                 when 'TVB' then 'Bachelor of Technology'
                               end)
                      from curriculum_version cv
                      join curriculum cur    on cur.id = cv.curriculum_id
                      join program_track ptr on ptr.id = cur.program_track_id
                      join program pr        on pr.id  = ptr.program_id
                      join program_type pt   on pt.id  = pr.program_type_id
                     where cv.id = v_cv),
    'graduation',  (select to_jsonb(sg) from student_graduation sg
                     where sg.student_id = p_student_id
                     order by sg.completed_on desc limit 1),
    'summary',     coalesce(
                     (select jsonb_build_object(
                               'credits_earned', sg.credits_earned,
                               'gpax',           sg.gpax,
                               'source',         'graduation')
                        from student_graduation sg
                       where sg.student_id = p_student_id
                       order by sg.completed_on desc limit 1),
                     (select jsonb_build_object(
                               'credits_earned', ts.credits_earned,
                               'gpax',           ts.gpax,
                               'source',         'term_summary')
                        from term_summary ts
                        join term t           on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc
                       limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none'))
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;
  -- ── ข้อความประจำสถานศึกษาและผลมาตรฐานวิชาชีพ ──────────────────────
  -- อยู่บนใบ รบ. และใบประกาศนียบัตรเท่านั้น ใบอื่นไม่ได้พิมพ์เกณฑ์การจบ
  if v_kind in ('transcript', 'certificate') then
    v_payload := v_payload || jsonb_build_object(
      'institution_text',
        coalesce((select jsonb_object_agg(
                           t.key,
                           jsonb_build_object('th', coalesce(t.text_th, ''),
                                              'en', coalesce(t.text_en, '')))
                    from institution_document_text t
                   where t.institution_id = v_inst), '{}'::jsonb),
      'professional_standard',
        (select jsonb_build_object(
                  'no',      coalesce(sg.professional_standard_no, ''),
                  -- null = ยังไม่ได้เข้ารับการประเมิน ซึ่งต่างจาก false
                  -- คือประเมินแล้วไม่ผ่าน สองอย่างนี้พิมพ์บนใบไม่เหมือนกัน
                  'passed',  sg.professional_standard_passed,
                  'on_date', sg.professional_standard_on)
           from student_graduation sg
          where sg.student_id = p_student_id
          order by sg.completed_on desc limit 1));
  end if;
  -- ── ระเบียนแสดงผลการเรียน — ต้องมีรายวิชาทั้งหมดและผลรายภาค ───────
  if v_kind in ('transcript', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'term_summaries',
        coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                    from (select ay.year_be, t.ordinal,
                                 'ภาคเรียนที่ ' || t.ordinal
                                   || ' ปีการศึกษา ' || ay.year_be as label,
                                 ts.gpa, ts.gpax, ts.credits_earned
                            from term_summary ts
                            join term t           on t.id  = ts.term_id
                            join academic_year ay on ay.id = t.academic_year_id
                           where ts.student_id = p_student_id) x), '[]'::jsonb),
      'courses',
        coalesce((select jsonb_agg(to_jsonb(td))
                    from transcript_data(p_student_id) td), '[]'::jsonb))
      -- ส่วนที่มีเฉพาะใบ รบ. อยู่ใน transcript_extra() (0059)
      -- เพิ่มช่องให้ใบ รบ. แก้ที่ฟังก์ชันนั้นที่เดียว ไม่ต้องเขียนตัวนี้ทับ
      || transcript_extra(p_student_id);
  end if;
  -- ── สมุดพก — ผลการเรียนประจำภาคพร้อมเวลาเรียนและความประพฤติ ───────
  if v_kind = 'grade_report' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be,
                  'gpa',     ts.gpa,
                  'gpax',    ts.gpax,
                  'credits_earned', ts.credits_earned)
           from term t
           join academic_year ay on ay.id = t.academic_year_id
           left join term_summary ts
                  on ts.term_id = t.id and ts.student_id = p_student_id
          where t.id = p_term_id),
      -- เวลาเรียนมาจาก v_enrollment_attendance ซึ่งเป็นค่าสด ณ เวลาออกใบ
      -- ต่างจากระเบียนแสดงผลการเรียนที่ใช้ attendance_pct ที่ตรึงตอนตัดเกรด
      -- เพราะสมุดพกมักออกกลางภาคตอนที่ยังไม่มีการตัดเกรด
      'term_courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'course_code',   c.code,
                           'course_name_th', c.name_th,
                           'credits',       c.credits,
                           'grade_symbol',  gsym.symbol,
                           'attendance_pct', v.pct_to_date,
                           'attendance_state', v.attendance_state,
                           'absences_left', v.absences_left)
                           order by c.code)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    left join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join enrollment_result er
                           on er.enrollment_id = e.id and er.superseded_by is null
                    left join grade_symbol gsym on gsym.id = er.grade_symbol_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'), '[]'::jsonb),
      'activities',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'sessions_required', cr.sessions_required,
                           'sessions_attended', cr.sessions_attended,
                           'result', cr.result))
                    from cocurricular_result cr
                   where cr.student_id = p_student_id
                     and cr.term_id = p_term_id), '[]'::jsonb));
  end if;
  -- ── ความประพฤติ — สมุดพกและระเบียนสะสมต้องมี ─────────────────────
  --
  -- behavior_record.points เป็นจำนวนบวกเสมอ (check points > 0 ใน 0011)
  -- ทิศทางหักหรือเพิ่มอยู่ที่ behavior_rule.direction ไม่ใช่ที่เครื่องหมาย
  -- ของตัวเลข การรวมยอดโดยดูเครื่องหมายจึงได้คำตอบผิดแบบดูไม่ออก —
  -- "หนีเรียน" จะกลายเป็นการเพิ่มคะแนนให้ แล้วไปพิมพ์อยู่บนกระดาษ
  --
  -- ยอดคงเหลือจึงอ่านจาก v_behavior_balance ซึ่งเป็นสูตรเดียวกับที่ระบบ
  -- เตือนก่อนออกกลางคันใช้ ไม่เขียนสูตรซ้ำที่นี่ให้มีโอกาสไม่ตรงกัน
  if v_kind in ('grade_report', 'cumulative_record') then
    v_payload := v_payload || jsonb_build_object(
      'behavior',
        (select jsonb_build_object(
                  'starting_points', bp.starting_points,
                  'deducted', coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'deduct'), 0),
                  'awarded',  coalesce((select sum(br.points)
                                          from behavior_record br
                                          join behavior_rule r on r.id = br.rule_id
                                         where br.student_id = p_student_id
                                           and r.direction = 'award'), 0),
                  'current',  (select vb.balance from v_behavior_balance vb
                                where vb.student_id = p_student_id),
                  'warn_below', bp.warn_below,
                  'critical_below', bp.critical_below)
           from behavior_policy bp
          where bp.institution_id = v_inst));
  end if;
  -- ── ระเบียนสะสม (ปพ.8) ────────────────────────────────────────────
  if v_kind = 'cumulative_record' then
    v_payload := v_payload || jsonb_build_object(
      'guardians',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'relation',  sg.relation,
                           'full_name', trim(coalesce(gp.prefix_th, '')
                                          || coalesce(gp.first_name_th, '')
                                          || ' ' || coalesce(gp.last_name_th, '')),
                           'phone',     coalesce(gp.phone, ''),
                           'is_primary', sg.is_primary)
                           order by sg.is_primary desc)
                    from student_guardian sg
                    join person gp on gp.id = sg.person_id
                   where sg.student_id = p_student_id
                     and sg.verified_at is not null), '[]'::jsonb),
      -- เก็บแค่ระดับผลกับวันที่ ไม่เก็บคำตอบรายข้อ (detail) โดยตั้งใจ
      -- ดูเหตุผลที่หัวไฟล์ — เอกสารนี้ลบไม่ได้และถูกส่งต่อกันไปเรื่อย ๆ
      'screenings',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'instrument',  sr.instrument,
                           'assessed_on', sr.assessed_on,
                           'band',        sr.band)
                           order by sr.assessed_on)
                    from screening_result sr
                   where sr.student_id = p_student_id), '[]'::jsonb),
      -- ส่ง direction ไปด้วยเสมอ เพราะ points เป็นบวกทั้งคู่
      -- ถ้าให้แม่แบบเดาเครื่องหมายเอง ใบจะพิมพ์ว่าหนีเรียนแล้วได้คะแนนเพิ่ม
      'behavior_history',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'occurred_on', br.occurred_on,
                           'points',      br.points,
                           'direction',   brl.direction,
                           'rule_th',     coalesce(brl.name_th, ''),
                           'document_no', coalesce(br.document_no, ''))
                           order by br.occurred_on)
                    from behavior_record br
                    left join behavior_rule brl on brl.id = br.rule_id
                   where br.student_id = p_student_id), '[]'::jsonb),
      'activities_all',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'activity_name', cr.activity_name,
                           'result',        cr.result,
                           'term_label',    'ภาคเรียนที่ ' || t.ordinal
                                              || '/' || ay.year_be))
                    from cocurricular_result cr
                    join term t           on t.id  = cr.term_id
                    join academic_year ay on ay.id = t.academic_year_id
                   where cr.student_id = p_student_id), '[]'::jsonb),
      -- บันทึกเยี่ยมบ้านมีข้อค้นพบเป็นข้อความอิสระที่อ่อนไหวมาก
      -- ระเบียนสะสมจึงบันทึกแค่ว่า "เคยเยี่ยมกี่ครั้ง ครั้งล่าสุดเมื่อไร"
      'home_visits',
        (select jsonb_build_object(
                  'count', count(*),
                  'last_visited_on', max(hv.visited_on))
           from home_visit hv where hv.student_id = p_student_id));
  end if;
  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;
  return v_row;
end $$;

comment on function issue_document_core is
  'สร้างเนื้อหาที่ทุกใบต้องมี (ตัวนักศึกษา หลักสูตร) แล้วต่อด้วยส่วนเฉพาะใบ รบ. จาก transcript_extra() — เพิ่มช่องใหม่ให้ใบ รบ. แก้ที่นั่น ไม่ต้องแตะฟังก์ชันนี้อีก · ปฏิเสธการพิมพ์ถ้ามีการระงับสิทธิ์ที่บล็อกใบนี้ (0094)';

-- ───────────────────────────────────────────────────────────────────
-- มุมมองรายงานรายรับ — ตัวเลขที่ศูนย์การเงินไม่เคยตอบได้มาก่อน
-- นับเฉพาะเงินที่กระทบยอดแล้ว (reconciled) ไม่รวม pending/rejected/refunded
-- มิฉะนั้นตัวเลขจะรวมเงินที่ยังจับคู่ไม่ได้หรือถูกยกเลิกไปแล้ว
-- ───────────────────────────────────────────────────────────────────
create view v_revenue_daily
  with (security_invoker = true) as
select institution_id, received_on, method,
       count(*)   as payment_count,
       sum(amount) as amount
  from payment
 where status = 'reconciled'
 group by institution_id, received_on, method;

comment on view v_revenue_daily is
  'รายรับรายวันแยกตามช่องทางชำระ — ต้นทางของรายงานรายรับที่ /finance/revenue อ่านแล้วรวมตามช่วงที่ขอ';

commit;

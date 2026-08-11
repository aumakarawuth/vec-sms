-- ═══════════════════════════════════════════════════════════════════
-- 0059 — ส่วนที่ ปวส. ต่างจาก ปวช. และการแยก payload เฉพาะใบ รบ. ออกมา
--
-- ═══ สามอย่างที่ ปวส. ต่างจาก ปวช. (วัดจากไฟล์จริง) ═══
-- 1. ชื่อเรื่องต่างกันตามระดับและตามว่าเป็นหลักสูตรต่อเนื่องหรือไม่
--    · ปวช.  — ระเบียนแสดงผลการเรียนตามหลักสูตรประกาศนียบัตรวิชาชีพ พุทธศักราช 2567
--    · ปวส.  — …ประกาศนียบัตรวิชาชีพชั้นสูง พุทธศักราช 2567
--    · ปวส. ต่อเนื่อง — …ประกาศนียบัตรวิชาชีพชั้นสูง (ต่อเนื่อง) พุทธศักราช 2567
-- 2. **ปวส. มีช่อง "สาขาวิชาเดิม" เพิ่มมาหนึ่งช่อง** ที่ ปวช. ไม่มี
--    เพราะผู้เข้า ปวส. จบ ปวช. มา สาขาเดิมจึงมีความหมายกับการเทียบโอน
-- 3. ชื่อเรื่องภาษาอังกฤษใช้ **ปีคริสต์ศักราช** ไม่ใช่ พ.ศ.
--    "2024 CURRICULUM OF THE CERTIFICATE / DIPLOMA IN VOCATIONAL EDUCATION"
--    — ข้อนี้เดาไม่ถูกถ้าไม่ได้เปิดไฟล์จริงดู
--
-- ═══ ทำไมย้าย payload เฉพาะใบ รบ. ออกมาเป็นฟังก์ชันของตัวเอง ═══
-- 0057 กับ 0058 ต่างก็ต้องเขียน `issue_document_core()` ทับทั้ง 300 บรรทัด
-- เพื่อเพิ่มบรรทัดเดียว ซึ่งเป็นวิธีที่ทั้งเสี่ยงและอ่านไม่ออกว่าเปลี่ยนอะไร
--
-- ตอนแรกเลี่ยงการแยกเพราะกลัวว่า payload ของใบเดียวจะกระจายอยู่หลายที่
-- จนดูไม่ออกว่าใบไหนเก็บอะไร (หลักข้อ 5ก) — แต่การแยก **ตามประเภทใบ**
-- ให้ผลตรงกันข้าม คือเปิดไฟล์เดียวแล้วเห็นครบว่าใบ รบ. เก็บอะไรบ้าง
-- ต่างจากการแยกตามชนิดข้อมูลซึ่งจะกระจายจริง
--
-- นับจากนี้การเพิ่มช่องให้ใบ รบ. แก้ที่ `transcript_extra()` ที่เดียว
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * หลักสูตรต่อเนื่อง — ปวส. ที่รับผู้จบ ปวช. สาขาเดียวกันเข้าเรียนต่อ
 * มีชื่อเรียกบนใบ รบ. ต่างจาก ปวส. ปกติ จึงต้องรู้ที่ระดับหลักสูตร
 * ไม่ใช่เดาจากระดับ (`program.level`) ซึ่งเป็น PVS เหมือนกันทั้งคู่
 */
alter table curriculum add column if not exists is_continuing boolean not null default false;

comment on column curriculum.is_continuing is
  'หลักสูตรต่อเนื่อง — ใบ รบ. พิมพ์ "(ต่อเนื่อง)" ต่อท้ายชื่อคุณวุฒิ · program.level เป็น PVS เหมือน ปวส. ปกติ จึงแยกจากตรงนั้นไม่ได้';

/*
 * ส่วนของ payload ที่มีเฉพาะใบ รบ.
 *
 * `prior_education` อยู่ที่นี่เพราะใบ รบ. **พิมพ์ลงกระดาษจริง** ทั้งชื่อ
 * สถานศึกษาเดิม จังหวัด ระดับที่จบ ปีที่จบ และ (เฉพาะ ปวส.) สาขาวิชาเดิม
 * — ใบอื่นไม่ได้แสดง จึงไม่ควรติดไปด้วย (หลักข้อ 5ก)
 *
 * เลือกแถวเดียวคือรายการล่าสุด เพราะช่องบนใบมีชุดเดียว ถ้าส่งหลายแถวไป
 * แม่แบบจะต้องเลือกเอง ซึ่งเป็นการตัดสินใจที่ควรอยู่ที่นี่ที่เดียว
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'prior_education',
      (select jsonb_build_object(
                'level_th',   pe.level_th,
                'school_th',  coalesce(pe.school_th, ''),
                'province_th', coalesce(pe.province_th, ''),
                'program_th', coalesce(pe.program_th, ''),
                'year_be',    pe.completed_year_be,
                'gpax',       pe.gpax)
         from student_prior_education pe
        where pe.student_id = p_student_id
        order by pe.completed_year_be desc nulls last, pe.level_th desc
        limit 1))
$$;

comment on function transcript_extra(uuid) is
  'payload ส่วนที่มีเฉพาะใบ รบ. — เพิ่มช่องให้ใบ รบ. แก้ที่นี่ที่เดียว ไม่ต้องเขียน issue_document_core ทับทั้งตัว';


/*
 * เขียน issue_document_core() ทับเป็น**ครั้งสุดท้าย** — หลังจากนี้ส่วนของ
 * ใบ รบ. อยู่ใน transcript_extra() ซึ่งแก้ได้โดยไม่ต้องแตะตัวนี้อีก
 */
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
                       order by ay.year_be desc, t.ordinal desc limit 1),
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

commit;

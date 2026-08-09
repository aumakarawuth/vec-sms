-- ═══════════════════════════════════════════════════════════════════
-- 0029_more_document_kinds.sql
--
-- เอกสารที่เหลือของงานทะเบียน — ใบรับรอง สมุดพก และระเบียนสะสม (ปพ.8)
--
-- ─── ทำไม payload ต้องแยกตามประเภทเอกสาร ไม่ใช่ใส่ทุกอย่างทุกใบ ───
-- ทางที่ง่ายกว่าคือประกอบข้อมูลทุกส่วนใส่ไว้ในทุกใบ แล้วให้แม่แบบหยิบเฉพาะ
-- ส่วนที่ต้องใช้ ซึ่งใช้งานได้และโค้ดสั้นกว่า — แต่ทำไม่ได้ที่นี่
--
-- เพราะ payload คือ **สำเนาถาวรที่ลบไม่ได้** ถ้าใส่ผลคัดกรอง SDQ บันทึก
-- เยี่ยมบ้าน และข้อมูลผู้ปกครองลงไปในระเบียนแสดงผลการเรียนทุกใบ ข้อมูล
-- อ่อนไหวของผู้เยาว์จะถูกคัดลอกไปเก็บถาวรในเอกสารที่ไม่มีเหตุผลต้องใช้มันเลย
-- และลบทิ้งไม่ได้ด้วย (issued_document แก้/ลบไม่ได้ตั้งแต่ 0027)
--
-- นี่คือการเก็บข้อมูลเกินความจำเป็นตาม PDPA มาตรา 22 ซึ่งเป็นความผิดที่
-- ตรวจพบยากมาก เพราะระบบทำงานถูกต้องทุกประการจากภายนอก แต่ละใบจึงได้
-- เฉพาะส่วนที่หน้ากระดาษของมันต้องแสดงจริง
--
-- ─── ทำไมระเบียนสะสมเก็บแค่ระดับผล ไม่เก็บรายละเอียด ───
-- ปพ.8 ต้องแสดงว่านักศึกษาเคยถูกคัดกรองและอยู่ในกลุ่มไหน ซึ่งพอสำหรับ
-- ครูที่ปรึกษาคนถัดไปใช้ทำงาน ส่วนคำตอบรายข้อของแบบคัดกรองและข้อค้นพบ
-- จากการเยี่ยมบ้านเป็นคนละเรื่อง — อยู่ในระบบให้คนที่มีสิทธิ์เปิดดูได้
-- แต่ไม่ควรถูกพิมพ์ลงกระดาษที่ส่งต่อกันไปเรื่อย ๆ
--
-- ─── ทำไมสมุดพกบังคับว่าต้องระบุภาคเรียน ───
-- สมุดพกคือผลการเรียน "ประจำภาค" การออกโดยไม่ระบุภาคเรียนแล้วให้ระบบเดา
-- ให้เองจะได้ใบที่ดูถูกต้องทุกอย่างแต่เป็นข้อมูลของภาคเรียนที่ผู้ออกไม่ได้ตั้งใจ
-- ซึ่งไปโผล่ในมือผู้ปกครองแล้วแก้ไม่ได้
--
-- ─── หมายเหตุเรื่องค่า enum ใหม่ ───
-- ไฟล์นี้เพิ่ม 'cumulative_record' เข้า document_kind แล้วต้องใช้ค่านั้น
-- ในตัวฟังก์ชันด้วย PostgreSQL ห้ามใช้ค่า enum ใหม่ใน transaction เดียวกับ
-- ที่เพิ่มมัน การเปรียบเทียบจึงทำผ่าน p_kind::text เทียบกับข้อความธรรมดา
-- ซึ่งไม่นับเป็นการอ้างถึงค่า enum (กับดักเดียวกับที่ 0026 เจอกับ 'bridging')
-- ═══════════════════════════════════════════════════════════════════
begin;

alter type document_kind add value if not exists 'cumulative_record';

comment on type document_kind is
  'ประเภทเอกสารที่งานทะเบียนออกให้ — transcript รบ. · certificate ใบประกาศนียบัตร · certification ใบรับรอง · grade_report สมุดพก · cumulative_record ระเบียนสะสม (ปพ.8)';

-- เปลี่ยนลายเซ็นฟังก์ชันเพื่อรับภาคเรียน จึงต้อง drop ก่อน
-- (create or replace เปลี่ยนรายการพารามิเตอร์ไม่ได้ จะกลายเป็นฟังก์ชันคนละตัว
--  แล้วการเรียกแบบสามอาร์กิวเมนต์จะกำกวมทันที)
drop function if exists issue_document(uuid, document_kind, smallint);

create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null,
  p_term_id    uuid     default null
) returns issued_document language plpgsql as $$
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

  v_doc_no := next_document_no(p_kind, v_year);

  -- ── ส่วนที่ทุกใบต้องมี ────────────────────────────────────────────
  select jsonb_build_object(
    'kind',        v_kind,
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
                     'status',        s.status),
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
                    from transcript_data(p_student_id) td), '[]'::jsonb));
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

comment on function issue_document(uuid, document_kind, smallint, uuid) is
  'ออกเอกสารพร้อมตรึงเนื้อหาทั้งใบ — payload มีเฉพาะส่วนที่กระดาษใบนั้นต้องแสดง ไม่ใส่ข้อมูลอ่อนไหวที่ใบนั้นไม่ได้ใช้';

commit;

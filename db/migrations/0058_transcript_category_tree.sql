-- ═══════════════════════════════════════════════════════════════════
-- 0058 — โครงหมวด/กลุ่มวิชาสำหรับใบ รบ. ตระกูล 67
--
-- ═══ ทำไมต้องมี ═══
-- ใบ รบ. ตระกูล ปวช./ปวส. 67 (วัดจากไฟล์จริง — ดู docs/transcript-formats.md)
-- **จัดกลุ่มรายวิชาตามหมวด → กลุ่มวิชา** แล้วสรุปสามบรรทัดใต้ทุกกลุ่ม
--   · จำนวนหน่วยกิตตามหลักสูตร N หน่วยกิต
--   · จำนวนหน่วยกิตที่ได้ N หน่วยกิต
--   · คะแนนเฉลี่ยสะสมกลุ่ม… N.NN
-- และสรุปคะแนนเฉลี่ยสะสมรายหมวดอีกชั้นหนึ่ง
--
-- `transcript_data()` เดิมคืน `category_th` แบน ๆ ชั้นเดียว ซึ่งพอสำหรับ
-- ใบตระกูล 62 ที่จัดตามภาคเรียน แต่ตอบไม่ได้ว่ากลุ่มไหนอยู่ใต้หมวดไหน
-- และไม่มีหน่วยกิตตามหลักสูตรให้เทียบ
--
-- ═══ ทำไมคำนวณที่ฐานข้อมูล ไม่ใช่ที่แม่แบบ ═══
-- คะแนนเฉลี่ยรายกลุ่มเป็น**ตัวเลขบนเอกสารทางการ** ถ้าให้แม่แบบรวมเอง
-- จะกลายเป็นสูตรชุดที่สองที่ค่อย ๆ เพี้ยนไปจาก `term_summary` และ
-- `student_graduation.gpax` ซึ่งเป็นตัวเลขที่ระบบใช้ตัดสินการจบจริง
-- (หลักข้อ 1 — ฐานข้อมูลเป็นเจ้าของกฎ)
--
-- ═══ ทำไมวิชาที่ไม่มีหมวดต้องไม่หายไป ═══
-- `curriculum_course` เป็น left join ใน transcript_data() อยู่แล้ว แปลว่า
-- วิชาที่ยังไม่ได้ผูกเข้าโครงหลักสูตรจะได้ category เป็น null — ถ้าปล่อยให้
-- หลุดออกจากโครงต้นไม้ ใบ รบ. จะขาดรายวิชาไปเงียบ ๆ โดยยอดหน่วยกิตรวม
-- ยังถูกต้อง ซึ่งเป็นความผิดที่มองไม่ออกจนกว่าจะมีคนนับวิชาบนกระดาษ
-- จึงรวมไว้ในกลุ่มพิเศษที่**ชื่อบอกว่ายังไม่ได้จัดหมวด**
-- ═══════════════════════════════════════════════════════════════════

begin;

/*
 * รายวิชาพร้อมหมวดและกลุ่ม
 *
 * คืนทั้งรหัสและลำดับของทั้งสองชั้น เพื่อให้ชั้นบนเรียงได้ตรงกับที่หลักสูตร
 * กำหนด ไม่ใช่เรียงตามตัวอักษรของชื่อ (ซึ่งจะสลับที่ทุกครั้งที่วิทยาลัย
 * แก้ชื่อกลุ่ม)
 */
create or replace function transcript_courses_grouped(p_student_id uuid)
returns table (
  head_code   text,
  head_name   text,
  head_sort   smallint,
  head_min    numeric,
  group_code  text,
  group_name  text,
  group_sort  smallint,
  group_min   numeric,
  year_be     smallint,
  term_ordinal smallint,
  term_label  text,
  course_code text,
  course_name_th text,
  course_name_en text,
  credits     numeric,
  grade_symbol text,
  grade_point numeric,
  credits_earned numeric,
  counts_in_gpa boolean
) language sql stable as $$
  select
    coalesce(head.code, 'UNSORTED')            as head_code,
    coalesce(head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as head_name,
    coalesce(head.sort_order, 99)::smallint    as head_sort,
    head.min_credits                           as head_min,
    /*
     * วิชาที่ผูกกับหมวดโดยตรง (ไม่มีกลุ่มย่อย) ให้ group เป็นตัวมันเอง
     * เพื่อให้แม่แบบวนสองชั้นได้เสมอโดยไม่ต้องมีสาขาพิเศษ
     */
    coalesce(grp.code, head.code, 'UNSORTED')  as group_code,
    coalesce(grp.name_th, head.name_th, 'รายวิชาที่ยังไม่ได้จัดหมวด') as group_name,
    coalesce(grp.sort_order, 0)::smallint      as group_sort,
    coalesce(grp.min_credits, head.min_credits) as group_min,
    ay.year_be,
    t.ordinal,
    'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be,
    c.code,
    c.name_th,
    coalesce(c.name_en, ''),
    c.credits,
    gsym.symbol,
    er.grade_point,
    er.credits_earned,
    gsym.counts_in_gpa
  from enrollment e
  join class_section cs     on cs.id = e.class_section_id
  join course c             on c.id  = cs.course_id
  join term t               on t.id  = e.term_id
  join academic_year ay     on ay.id = t.academic_year_id
  join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
  join grade_symbol gsym    on gsym.id = er.grade_symbol_id
  left join curriculum_course cc
         on cc.curriculum_version_id = cs.curriculum_version_id
        and cc.course_id = c.id
  left join curriculum_category cat  on cat.id = cc.curriculum_category_id
  -- cat อาจเป็นหมวดเอง (parent_id null) หรือเป็นกลุ่มย่อย
  left join curriculum_category grp  on grp.id = cat.id and cat.parent_id is not null
  left join curriculum_category head on head.id = coalesce(cat.parent_id, cat.id)
  where e.student_id = p_student_id
    and e.status in ('enrolled', 'credit_transfer')
    and gsym.appears_on_transcript
  order by coalesce(head.sort_order, 99), coalesce(grp.sort_order, 0),
           ay.year_be, t.ordinal, c.code
$$;

comment on function transcript_courses_grouped(uuid) is
  'รายวิชาบนใบ รบ. พร้อมหมวดและกลุ่มวิชา — วิชาที่ยังไม่ได้ผูกโครงหลักสูตรไปอยู่กลุ่ม UNSORTED ไม่ใช่หายไปเงียบ ๆ';

/*
 * ยอดสรุปรายกลุ่มและรายหมวด
 *
 * คะแนนเฉลี่ยคิดจากรายวิชาที่ `counts_in_gpa` เท่านั้น — วิชาที่ได้ ผ./ม.ผ.
 * มีหน่วยกิตแต่ไม่มีแต้ม ถ้ารวมเข้าไปจะกดค่าเฉลี่ยลงโดยไม่มีใครสังเกต
 */
create or replace function transcript_category_summary(p_student_id uuid)
returns table (
  level       text,      -- 'head' หรือ 'group'
  head_code   text,
  group_code  text,
  name_th     text,
  sort_key    text,
  min_credits numeric,
  credits_earned numeric,
  gpa         numeric
) language sql stable as $$
  with rows as (select * from transcript_courses_grouped(p_student_id))
  select 'group', r.head_code, r.group_code, max(r.group_name),
         lpad(max(r.head_sort)::text, 3, '0') || '-' || lpad(max(r.group_sort)::text, 3, '0'),
         max(r.group_min),
         coalesce(sum(r.credits_earned), 0),
         case when sum(r.credits) filter (where r.counts_in_gpa) > 0
              then round(sum(r.grade_point * r.credits) filter (where r.counts_in_gpa)
                         / sum(r.credits) filter (where r.counts_in_gpa), 2)
         end
    from rows r
   group by r.head_code, r.group_code
  union all
  select 'head', r.head_code, null, max(r.head_name),
         lpad(max(r.head_sort)::text, 3, '0') || '-999',
         max(r.head_min),
         coalesce(sum(r.credits_earned), 0),
         case when sum(r.credits) filter (where r.counts_in_gpa) > 0
              then round(sum(r.grade_point * r.credits) filter (where r.counts_in_gpa)
                         / sum(r.credits) filter (where r.counts_in_gpa), 2)
         end
    from rows r
   group by r.head_code
   order by 5
$$;

comment on function transcript_category_summary(uuid) is
  'หน่วยกิตและคะแนนเฉลี่ยรายกลุ่มวิชาและรายหมวด — คิดเฉพาะวิชาที่ counts_in_gpa มิฉะนั้นวิชา ผ./ม.ผ. จะกดค่าเฉลี่ยลง';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- ใส่โครงต้นไม้ลง payload ของใบ รบ.
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * เพิ่มเฉพาะสาขา transcript — ใบอื่นไม่ได้พิมพ์โครงหมวด/กลุ่ม
 * การใส่ทุกใบคือการเก็บเกินจำเป็นในที่ที่ลบไม่ได้ (หลักข้อ 5ก)
 */
create or replace function transcript_category_tree(p_student_id uuid)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(head order by head ->> 'sort'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'code',        h.head_code,
               'name_th',     h.name_th,
               'sort',        h.sort_key,
               'min_credits', h.min_credits,
               'credits_earned', h.credits_earned,
               'gpa',         h.gpa,
               'groups',
                 coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'code',        g.group_code,
                            'name_th',     g.name_th,
                            'sort',        g.sort_key,
                            'min_credits', g.min_credits,
                            'credits_earned', g.credits_earned,
                            'gpa',         g.gpa,
                            'courses',
                              coalesce((
                                select jsonb_agg(jsonb_build_object(
                                         'term_label',  c.term_label,
                                         'year_be',     c.year_be,
                                         'term_ordinal', c.term_ordinal,
                                         'code',        c.course_code,
                                         'name_th',     c.course_name_th,
                                         'name_en',     c.course_name_en,
                                         'credits',     c.credits,
                                         'grade',       c.grade_symbol,
                                         'grade_point', c.grade_point,
                                         'credits_earned', c.credits_earned)
                                         order by c.year_be, c.term_ordinal, c.course_code)
                                  from transcript_courses_grouped(p_student_id) c
                                 where c.head_code = h.head_code
                                   and c.group_code = g.group_code), '[]'::jsonb))
                          order by g.sort_key)
                     from transcript_category_summary(p_student_id) g
                    where g.level = 'group' and g.head_code = h.head_code), '[]'::jsonb)) as head
        from transcript_category_summary(p_student_id) h
       where h.level = 'head'
    ) x
$$;

comment on function transcript_category_tree(uuid) is
  'โครงหมวด → กลุ่มวิชา → รายวิชา พร้อมยอดสรุปทุกชั้น สำหรับใบ รบ. ตระกูล 67';

/*
 * เขียน issue_document_core() ทับทั้งตัวเพื่อเพิ่มบรรทัดเดียว
 *
 * plpgsql แก้เฉพาะบางบรรทัดไม่ได้ และการแยกเนื้อ payload ออกเป็นฟังก์ชันย่อย
 * จะทำให้ payload ของใบเดียวถูกประกอบจากหลายที่ ซึ่งขัดกับหลักข้อ 5ก
 * ที่ต้องดูจุดเดียวได้ว่าใบไหนเก็บอะไรบ้าง — migration เป็นภาพนิ่ง
 * นิยามที่ใช้จริงมีชุดเดียวเสมอ
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
                    from transcript_data(p_student_id) td), '[]'::jsonb),
      -- โครงหมวด → กลุ่มวิชา → รายวิชา พร้อมยอดสรุปทุกชั้น (0058)
      -- ใบตระกูล 67 จัดกลุ่มแบบนี้ ส่วนตระกูล 62 ใช้ 'courses' ที่จัดตามภาคเรียน
      -- เก็บทั้งสองชุดเพราะเป็นตัวเลขคนละชุดที่คำนวณคนละแบบ ไม่ใช่ข้อมูลซ้ำ
      'category_tree', transcript_category_tree(p_student_id));
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

-- ═══════════════════════════════════════════════════════════════════
-- 0028_document_payload_detail.sql
--
-- เติมข้อมูลใน payload ของเอกสารให้ครบเท่าที่หน้ากระดาษต้องแสดง
--
-- ─── ทำไมต้องเติมก่อนทำแม่แบบพิมพ์ ───
-- 0027 เก็บ payload ไว้แค่ข้อมูลนักศึกษากับรายวิชา ซึ่งไม่พอสำหรับระเบียน
-- แสดงผลการเรียนจริง — ยังขาดสาขาวิชา หน่วยกิตสะสม ผลการเรียนเฉลี่ยสะสม
-- และผลการเรียนเฉลี่ยรายภาค
--
-- ถ้าปล่อยให้ตัวเรนเดอร์ไป join เอาเองตอนพิมพ์ หลักการตรึงเนื้อหาทั้งหมด
-- จะพังทันที เพราะครึ่งหนึ่งของกระดาษจะมาจากข้อมูลสด ผลคือใบที่พิมพ์ซ้ำ
-- ปีหน้าจะมีชื่อสาขาวิชาหรือ GPAX ไม่ตรงกับใบเดิม ถ้าระหว่างนั้นมีการ
-- เปลี่ยนชื่อสาขา แก้เกรด หรือคำนวณ term_summary ใหม่ — และจะไม่มีใครรู้
-- เพราะกระดาษสองใบไม่เคยถูกเอามาวางเทียบกัน
--
-- หลักที่ใช้ตัดสินคือ **ทุกตัวอักษรที่ปรากฏบนกระดาษต้องอยู่ใน payload**
--
-- ─── ทำไม gpax มีสองแหล่ง ───
-- คนที่อนุมัติจบแล้วใช้ค่าที่ตรึงไว้ใน student_graduation เสมอ เพราะเป็น
-- ตัวเลขที่คณะกรรมการอนุมัติ ส่วนคนที่ยังเรียนอยู่ (ขอใบรับรองหรือใบแสดงผล
-- ระหว่างเรียน) ยังไม่มีมติอนุมัติ จึงต้องใช้ค่าล่าสุดจาก term_summary
-- payload บอก source ไว้ด้วยเพื่อให้ตรวจสอบย้อนหลังได้ว่าเลขนั้นมาจากไหน
--
-- ─── ทำไมข้อความวุฒิการศึกษาคำนวณในฐานข้อมูล ───
-- "ประกาศนียบัตรวิชาชีพ" กับ "ประกาศนียบัตรวิชาชีพชั้นสูง" เป็นถ้อยคำตาม
-- หลักสูตร ไม่ใช่การจัดรูปแบบ ถ้าให้ตัวเรนเดอร์แปล PVC/PVS เอง วันที่มี
-- ช่องทางพิมพ์ที่สอง (แอป หรือสคริปต์ออกใบย้อนหลัง) จะแปลไม่เหมือนกัน
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function issue_document(
  p_student_id uuid,
  p_kind       document_kind,
  p_year_be    smallint default null
) returns issued_document language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
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
  --
  -- กฎนี้อยู่ที่ฐานข้อมูลไม่ใช่ที่ตัวเรนเดอร์ เพราะใบที่ออกไปแล้วมีเลขที่
  -- ทางราชการติดตัวไป การไปพบทีหลังว่าออกให้คนที่ยังไม่จบแก้ไม่ได้แล้ว
  -- ต้องยกเลิกและเสียเลขนั้นทิ้ง — ต้องกันไม่ให้เกิดตั้งแต่แรก
  if p_kind = 'certificate'
     and not exists (select 1 from student_graduation sg
                      where sg.student_id = p_student_id) then
    raise exception 'ออกใบประกาศนียบัตรไม่ได้ ยังไม่มีมติอนุมัติสำเร็จการศึกษาของนักศึกษารายนี้'
      using errcode = 'check_violation';
  end if;

  -- หลักสูตรที่นักศึกษาสังกัดอยู่ ณ วันนี้ ถ้าเคยย้ายหลักสูตรให้ใช้ฉบับล่าสุด
  select sc.curriculum_version_id into v_cv
    from student_curriculum sc
   where sc.student_id = p_student_id
     and (sc.effective_to is null or sc.effective_to >= current_date)
   order by sc.effective_from desc nulls last
   limit 1;

  v_year := coalesce(
    p_year_be,
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint
  );

  v_doc_no := next_document_no(p_kind, v_year);

  select jsonb_build_object(
    'kind',        p_kind,
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

    -- ─── สาขาวิชาและวุฒิ ───
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

    -- ─── สรุปผลการเรียน ───
    -- คนที่อนุมัติจบแล้วใช้ค่าที่คณะกรรมการอนุมัติเสมอ ไม่คำนวณใหม่
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
                        join term t       on t.id  = ts.term_id
                        join academic_year ay on ay.id = t.academic_year_id
                       where ts.student_id = p_student_id
                       order by ay.year_be desc, t.ordinal desc limit 1),
                     jsonb_build_object('credits_earned', 0, 'gpax', null,
                                        'source', 'none')),

    'term_summaries',
                   coalesce((select jsonb_agg(x order by x.year_be, x.ordinal)
                               from (select ay.year_be, t.ordinal,
                                            'ภาคเรียนที่ ' || t.ordinal
                                              || ' ปีการศึกษา ' || ay.year_be as label,
                                            ts.gpa, ts.gpax, ts.credits_earned
                                       from term_summary ts
                                       join term t           on t.id  = ts.term_id
                                       join academic_year ay on ay.id = t.academic_year_id
                                      where ts.student_id = p_student_id) x),
                            '[]'::jsonb),

    'courses',     coalesce((select jsonb_agg(to_jsonb(td))
                               from transcript_data(p_student_id) td), '[]'::jsonb)
  )
    into v_payload
  from student s
  join person p      on p.id = s.person_id
  join institution i on i.id = s.institution_id
  where s.id = p_student_id;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values
    (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_document(uuid, document_kind, smallint) is
  'ออกเอกสารใหม่พร้อมตรึงเนื้อหาทั้งใบ — ทุกตัวอักษรที่ปรากฏบนกระดาษต้องอยู่ใน payload ไม่ใช่ดึงสดตอนพิมพ์';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 0055 — หนังสือถึงผู้ปกครองและใบรับรองความประพฤติ
--
-- สามใบที่งานปกครองต้องออกจริงทุกภาคเรียนและระบบยังไม่มีเลย
--   · จดหมายแจ้งขาดเรียน       — เตือนก่อนหมดสิทธิ์สอบตามกฎ 80%
--   · หนังสือเชิญผู้ปกครอง      — นัดพบพร้อมวันเวลาและสถานที่
--   · ใบรับรองความประพฤติ      — นักศึกษาขอไปใช้สมัครงาน/เรียนต่อ
--
-- ═══ ทำไมสามใบนี้ต้องเป็น `issued_document` ไม่ใช่พิมพ์สด ═══
-- จดหมายแจ้งขาดเรียนอ้าง**ตัวเลขเวลาเรียน ณ วันที่ออก** ถ้าพิมพ์ซ้ำเดือนหน้า
-- แล้วอ่านค่าใหม่ ตัวเลขบนกระดาษที่ผู้ปกครองถืออยู่กับที่ระบบพิมพ์ใหม่จะไม่ตรงกัน
-- แล้วเถียงกันไม่จบว่าใครถูก — หลักข้อ 5 เรื่องค่าที่ตรึงไว้ห้ามคำนวณใหม่
-- ส่วนใบรับรองความประพฤติเป็นเอกสารที่นักศึกษาเอาไปยื่นให้คนอื่น ต้องตรวจ
-- ย้อนหลังได้ว่าวิทยาลัยออกให้จริงเมื่อไรและเลขที่เท่าไร
--
-- ═══ ทำไมไม่ใช้ `issue_document()` ตัวเดิม ═══
-- payload ของสามใบนี้ **ไม่ควรมี** สิ่งที่ใบเดิมมีทุกใบ คือ `graduation`
-- กับ `summary` (หน่วยกิตสะสมและ GPAX) เพราะจดหมายแจ้งขาดเรียนไม่ได้แสดง
-- เกรดเฉลี่ยของนักศึกษาสักตัว การคัดลอกลงไปคือการเก็บข้อมูลเกินจำเป็น
-- ในที่ที่ลบไม่ได้ (หลักข้อ 5ก · PDPA ม.22) — และในทางกลับกัน สามใบนี้
-- **ต้องมี**ชื่อและที่อยู่ผู้ปกครอง ซึ่งใบ รบ. ไม่มีสิทธิ์มี เพราะไม่ได้แสดง
-- จึงเป็นคนละชุดข้อมูลกันจริง ๆ ไม่ใช่ชุดเดียวกันที่ตัดบางส่วนออก
--
-- ═══ ทำไมนัดพบต้องส่งเข้ามา ไม่ใช่ให้ระบบเดา ═══
-- วันเวลาและสถานที่นัดพบเป็นข้อมูลที่มีอยู่ในหัวของคนออกหนังสือเท่านั้น
-- ถ้าปล่อยให้ว่างแล้วเติมด้วยปากกาทีหลัง จะไม่มีหลักฐานว่าเคยนัดวันไหน
-- เมื่อผู้ปกครองบอกว่าไม่เคยได้รับแจ้ง
--
-- ═══ ทำไมใบรับรองความประพฤติอ่านจาก `v_behavior_balance` ═══
-- `behavior_record.points` เป็นบวกเสมอ ทิศทางหัก/เพิ่มอยู่ที่
-- `behavior_rule.direction` การรวมยอดโดยดูเครื่องหมายของตัวเลขจะได้ผลผิด
-- แบบดูไม่ออก — หนีเรียนกลายเป็นได้คะแนนเพิ่ม แล้ววิทยาลัยจะออกใบรับรอง
-- ความประพฤติให้คนที่ไม่ควรได้ โดยมีลายเซ็นผู้อำนวยการอยู่บนนั้น
-- ═══════════════════════════════════════════════════════════════════

begin;

alter type document_kind add value if not exists 'absence_notice';
alter type document_kind add value if not exists 'guardian_invitation';
alter type document_kind add value if not exists 'conduct_certificate';

comment on type document_kind is
  'ประเภทเอกสารที่วิทยาลัยออกให้ — transcript รบ. · certificate ใบประกาศนียบัตร · certification ใบรับรอง · grade_report สมุดพก · cumulative_record ระเบียนสะสม (ปพ.8) · absence_notice จดหมายแจ้งขาดเรียน · guardian_invitation หนังสือเชิญผู้ปกครอง · conduct_certificate ใบรับรองความประพฤติ';

commit;

-- ═══════════════════════════════════════════════════════════════════
-- PostgreSQL ห้ามใช้ค่า enum ใหม่ในทรานแซกชันเดียวกับที่เพิ่มมัน
-- จึงต้องแยกทรานแซกชัน (กับดักเดียวกับที่ 0026 เจอกับ 'bridging'
-- และ 0029 เจอกับ 'cumulative_record')
-- ═══════════════════════════════════════════════════════════════════
begin;

/*
 * ส่วนหัวที่หนังสือถึงผู้ปกครองทุกใบต้องมี
 *
 * ต่างจากส่วนหัวของ `issue_document()` สองอย่างที่สำคัญ
 *   · ไม่มี graduation/summary — จดหมายแจ้งขาดเรียนไม่ได้แสดง GPAX
 *   · **มี**ผู้ปกครองและที่อยู่ — เพราะหัวจดหมายต้องขึ้นว่า "เรียน ..."
 *     และซองต้องมีที่อยู่ ซึ่งใบ รบ. ไม่มีสิทธิ์เก็บเพราะไม่ได้แสดง
 */
create or replace function letter_header(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'institution', jsonb_build_object(
                     'code',    i.code,
                     'name_th', i.name_th,
                     'name_en', coalesce(i.name_en, '')),
    'student',     jsonb_build_object(
                     'student_code', s.student_code,
                     'full_name_th', trim(coalesce(p.prefix_th, '')
                                       || coalesce(p.first_name_th, '')
                                       || ' ' || coalesce(p.last_name_th, '')),
                     'class_number', s.class_number,
                     'status',       s.status),
    'class',       (select jsonb_build_object(
                             'study_year', scp.study_year,
                             'group_code', coalesce(scp.group_code, ''),
                             'year_be',    ay.year_be)
                      from student_class_placement scp
                      join academic_year ay on ay.id = scp.academic_year_id
                     where scp.student_id = p_student_id
                     order by ay.year_be desc limit 1),
    'program',     (select jsonb_build_object(
                             'name_th', pr.name_th,
                             'level',   pr.level,
                             'abbr_th', case pr.level
                                          when 'PVC' then 'ปวช.'
                                          when 'PVS' then 'ปวส.'
                                          when 'TVB' then 'ทล.บ.'
                                        end)
                      from student_curriculum sc
                      join curriculum_version cv on cv.id = sc.curriculum_version_id
                      join curriculum cur        on cur.id = cv.curriculum_id
                      join program_track ptr     on ptr.id = cur.program_track_id
                      join program pr            on pr.id  = ptr.program_id
                     where sc.student_id = p_student_id
                       and (sc.effective_to is null or sc.effective_to >= current_date)
                     order by sc.effective_from desc nulls last limit 1),
    -- ครูที่ปรึกษาเป็นผู้ลงนามของจดหมายสองใบแรกตามธรรมเนียม
    'advisor',     (select jsonb_build_object(
                             'name_th', trim(coalesce(ap.prefix_th, '')
                                          || coalesce(ap.first_name_th, '')
                                          || ' ' || coalesce(ap.last_name_th, '')))
                      from student_advisor sa
                      join staff ast  on ast.id = sa.staff_id
                      join person ap  on ap.id  = ast.person_id
                     where sa.student_id = p_student_id and sa.ended_on is null
                     order by sa.is_primary desc limit 1),
    /*
     * ผู้ปกครองมาจากสองที่ที่ต่างกันโดยสิ้นเชิง
     *   · `student_parent` (0053) คือบิดามารดาตามระเบียน ซึ่งส่วนใหญ่
     *     ไม่ได้เป็นผู้ใช้ระบบ — เป็นชื่อที่จ่าหน้าซองจริง
     *   · `student_guardian` คือผู้ปกครองที่มีบัญชีเข้าระบบ ซึ่งอาจไม่ใช่
     *     คนเดียวกันและอาจไม่มีเลย
     * หนังสือต้องส่งถึงคนที่อยู่ในระเบียน จึงเอาจาก student_parent ก่อน
     */
    'recipients',  coalesce((
                     select jsonb_agg(jsonb_build_object(
                              'role',      sp.role,
                              'name_th',   trim(coalesce(sp.prefix_th, '')
                                             || sp.first_name_th
                                             || ' ' || coalesce(sp.last_name_th, '')),
                              'phone',     coalesce(sp.phone, ''),
                              'address_th', trim(coalesce(sp.address_line, '')
                                             || case when sp.subdistrict_th is not null
                                                     then ' ต.' || sp.subdistrict_th else '' end
                                             || case when sp.district_th is not null
                                                     then ' อ.' || sp.district_th else '' end
                                             || case when sp.province_th is not null
                                                     then ' จ.' || sp.province_th else '' end
                                             || ' ' || coalesce(sp.postal_code, '')))
                              order by sp.role)
                       from student_parent sp
                      where sp.student_id = p_student_id
                        and sp.status <> 'deceased'), '[]'::jsonb))
    from student s
    join person p      on p.id = s.person_id
    join institution i on i.id = s.institution_id
   where s.id = p_student_id
$$;

comment on function letter_header(uuid) is
  'ส่วนหัวของหนังสือถึงผู้ปกครอง — มีผู้รับและที่อยู่ ซึ่งใบ รบ. ไม่มีสิทธิ์เก็บ และไม่มี GPAX ซึ่งจดหมายไม่ได้แสดง';

-- ───────────────────────────────────────────────────────────────────
-- ออกหนังสือ
--
-- ไม่ใช่ security definer — ผู้เรียกต้องอ่านข้อมูลนักศึกษาและเวลาเรียน
-- ได้เองตามนโยบายของตัวเองอยู่แล้ว ถ้าอ่านไม่ได้ก็ไม่ควรออกหนังสือถึง
-- ผู้ปกครองของคนนั้น
-- ───────────────────────────────────────────────────────────────────
create or replace function issue_student_letter(
  p_student_id uuid,
  p_kind       document_kind,
  p_term_id    uuid  default null,
  p_context    jsonb default '{}'::jsonb
) returns issued_document
language plpgsql as $$
declare
  v_inst    uuid := current_institution_id();
  v_kind    text := p_kind::text;
  v_year    smallint;
  v_doc_no  text;
  v_payload jsonb;
  v_row     issued_document;
begin
  if v_kind not in ('absence_notice', 'guardian_invitation', 'conduct_certificate') then
    raise exception 'ฟังก์ชันนี้ออกได้เฉพาะหนังสือถึงผู้ปกครองและใบรับรองความประพฤติ — ใบอื่นใช้ issue_document()'
      using errcode = 'check_violation';
  end if;

  if not exists (select 1 from student s where s.id = p_student_id) then
    raise exception 'ไม่พบนักศึกษารหัสที่ระบุ หรือไม่มีสิทธิ์เข้าถึง';
  end if;

  -- จดหมายแจ้งขาดเรียนไม่มีความหมายถ้าไม่รู้ว่าภาคไหน เพราะตัวเลขเวลาเรียน
  -- เป็นของภาคเรียนหนึ่ง ๆ เสมอ
  if v_kind = 'absence_notice' and p_term_id is null then
    raise exception 'ออกจดหมายแจ้งขาดเรียนต้องระบุภาคเรียน มิฉะนั้นตัวเลขเวลาเรียนจะเป็นของภาคที่ผู้ออกไม่ได้ตั้งใจ'
      using errcode = 'check_violation';
  end if;

  if v_kind = 'guardian_invitation'
     and coalesce(btrim(p_context ->> 'meet_on'), '') = '' then
    raise exception 'หนังสือเชิญผู้ปกครองต้องระบุวันนัดพบ — ถ้าเว้นไว้เติมด้วยปากกาทีหลัง จะไม่มีหลักฐานว่าเคยนัดวันไหน'
      using errcode = 'check_violation';
  end if;

  v_year := coalesce(
    (select ay.year_be from term t
       join academic_year ay on ay.id = t.academic_year_id
      where t.id = p_term_id),
    (select max(ay.year_be) from academic_year ay where ay.institution_id = v_inst),
    (extract(year from current_date) + 543)::smallint);

  v_doc_no := next_document_no(p_kind, v_year);

  v_payload := letter_header(p_student_id) || jsonb_build_object(
    'kind',      v_kind,
    'issued_at', now(),
    'year_be',   v_year,
    'issued_by', (select trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                            || ' ' || coalesce(p.last_name_th, ''))
                    from person p where p.id = current_actor_id()),
    'note',      coalesce(p_context ->> 'note', ''));

  -- ── จดหมายแจ้งขาดเรียน ───────────────────────────────────────────
  if v_kind = 'absence_notice' then
    v_payload := v_payload || jsonb_build_object(
      'term',
        (select jsonb_build_object(
                  'year_be', ay.year_be,
                  'ordinal', t.ordinal,
                  'label',   'ภาคเรียนที่ ' || t.ordinal || ' ปีการศึกษา ' || ay.year_be)
           from term t join academic_year ay on ay.id = t.academic_year_id
          where t.id = p_term_id),
      /*
       * ตัวเลขทั้งหมดตรึง ณ วันที่ออก — พิมพ์ซ้ำต้องได้ใบเดิมเป๊ะ
       * `pct_projected` สำคัญกว่า `pct_to_date` เพราะเป็นตัวที่บอกว่า
       * "ถ้าขาดต่อแบบนี้จะจบภาคที่เท่าไร" ซึ่งคือเหตุผลที่ต้องส่งจดหมาย
       */
      'courses',
        coalesce((select jsonb_agg(jsonb_build_object(
                           'code',            c.code,
                           'name_th',         c.name_th,
                           'section_no',      cs.section_no,
                           'pct_to_date',     v.pct_to_date,
                           'pct_projected',   v.pct_projected,
                           'absences_left',   v.absences_left,
                           'min_pct',         v.min_pct,
                           'state',           v.attendance_state,
                           'teacher_th',      trim(coalesce(tp.prefix_th, '')
                                                || coalesce(tp.first_name_th, '')
                                                || ' ' || coalesce(tp.last_name_th, '')))
                           order by v.pct_projected)
                    from enrollment e
                    join class_section cs on cs.id = e.class_section_id
                    join course c         on c.id  = cs.course_id
                    join v_enrollment_attendance v on v.enrollment_id = e.id
                    left join staff tst on tst.id = cs.teacher_id
                    left join person tp on tp.id  = tst.person_id
                   where e.student_id = p_student_id
                     and e.term_id = p_term_id
                     and e.status = 'enrolled'
                     -- ใส่เฉพาะวิชาที่มีปัญหาจริง — จดหมายที่ลอกทุกวิชา
                     -- ลงไปทำให้ผู้ปกครองหาไม่เจอว่าต้องดูตรงไหน
                     and v.attendance_state <> 'ok'), '[]'::jsonb));

    if v_payload -> 'courses' = '[]'::jsonb then
      raise exception 'ออกจดหมายแจ้งขาดเรียนไม่ได้ — นักศึกษารายนี้ไม่มีวิชาที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคเรียนนี้'
        using errcode = 'check_violation';
    end if;
  end if;

  -- ── หนังสือเชิญผู้ปกครอง ─────────────────────────────────────────
  if v_kind = 'guardian_invitation' then
    v_payload := v_payload || jsonb_build_object(
      'meeting', jsonb_build_object(
                   'meet_on',   p_context ->> 'meet_on',
                   'meet_time', coalesce(p_context ->> 'meet_time', ''),
                   'place_th',  coalesce(p_context ->> 'place_th', ''),
                   'with_th',   coalesce(p_context ->> 'with_th', '')),
      'reason_th', coalesce(p_context ->> 'reason_th', ''));
  end if;

  -- ── ใบรับรองความประพฤติ ──────────────────────────────────────────
  if v_kind = 'conduct_certificate' then
    v_payload := v_payload || jsonb_build_object(
      /*
       * อ่านยอดคงเหลือจาก view ไม่รวมเอง เพราะ `behavior_record.points`
       * เป็นบวกทั้งสองทิศทาง — ทิศทางอยู่ที่ `behavior_rule.direction`
       * การ sum เครื่องหมายเองจะได้ผลผิดแบบดูไม่ออก (หนีเรียนกลายเป็น
       * ได้คะแนนเพิ่ม) แล้ววิทยาลัยจะออกใบรับรองความประพฤติให้คนที่
       * ไม่ควรได้ โดยมีลายเซ็นผู้อำนวยการอยู่บนนั้น
       *
       * จำนวนครั้งที่ถูกหักนับแยกไว้ด้วย เพราะ "คะแนนเต็มแต่เคยถูกหัก
       * แล้วทำกิจกรรมชดเชยจนกลับมาเต็ม" กับ "ไม่เคยมีประวัติเลย" คนละเรื่องกัน
       * และเป็นสิ่งที่คนอ่านใบรับรองอยากรู้
       */
      'behavior',
        jsonb_build_object(
          'balance',
            (select b.balance from v_behavior_balance b where b.student_id = p_student_id),
          'deduct_count',
            (select count(*) from behavior_record br
               join behavior_rule r on r.id = br.rule_id
              where br.student_id = p_student_id and r.direction = 'deduct'),
          'award_count',
            (select count(*) from behavior_record br
               join behavior_rule r on r.id = br.rule_id
              where br.student_id = p_student_id and r.direction = 'award')),
      'purpose_th',  coalesce(p_context ->> 'purpose_th', ''),
      'admitted_on', (select s.admitted_year_be from student s where s.id = p_student_id));
  end if;

  insert into issued_document
    (institution_id, student_id, kind, doc_no, issued_by, payload)
  values (v_inst, p_student_id, p_kind, v_doc_no, current_actor_id(), v_payload)
  returning * into v_row;

  return v_row;
end $$;

comment on function issue_student_letter(uuid, document_kind, uuid, jsonb) is
  'ออกหนังสือถึงผู้ปกครองและใบรับรองความประพฤติ — ตัวเลขเวลาเรียนและคะแนนความประพฤติตรึง ณ วันที่ออก พิมพ์ซ้ำต้องได้ใบเดิม';

/*
 * รายชื่อผู้ที่ควรได้รับจดหมายแจ้งขาดเรียน
 *
 * มีไว้ให้หน้าจอไม่ต้องเดาว่าจะออกให้ใคร — งานปกครองเปิดมาแล้วเห็นเลยว่า
 * ภาคเรียนนี้มีใครตกเกณฑ์บ้าง และใครได้รับจดหมายไปแล้ว
 * `last_notice_on` เป็น null แปลว่ายังไม่เคยส่ง ไม่ใช่ส่งแล้วไม่ได้ผล
 */
create or replace function absence_notice_candidates(p_term_id uuid)
returns table (
  student_id      uuid,
  student_code    text,
  full_name       text,
  courses_at_risk integer,
  worst_pct       numeric,
  last_notice_on  date
) language sql stable as $$
  select s.id, s.student_code,
         trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
              || ' ' || coalesce(p.last_name_th, '')),
         count(*)::integer,
         min(v.pct_projected),
         (select max(d.issued_on) from issued_document d
           where d.student_id = s.id
             and d.kind = 'absence_notice'
             and d.voided_at is null)
    from enrollment e
    join student s on s.id = e.student_id
    join person  p on p.id = s.person_id
    join v_enrollment_attendance v on v.enrollment_id = e.id
   where e.term_id = p_term_id
     and e.status = 'enrolled'
     and v.attendance_state <> 'ok'
   group by s.id, s.student_code, p.prefix_th, p.first_name_th, p.last_name_th
   order by min(v.pct_projected)
$$;

comment on function absence_notice_candidates(uuid) is
  'ผู้ที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคเรียนที่ระบุ พร้อมวันที่เคยออกจดหมายล่าสุด — null แปลว่ายังไม่เคยส่ง';

commit;

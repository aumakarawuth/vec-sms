-- ═══════════════════════════════════════════════════════════════════
-- 0062 — ช่องบนหัวใบ รบ. ที่พิมพ์อยู่บนกระดาษแต่ payload ไม่เคยมี
--
-- ═══ อาการ ═══
-- แม่แบบใบ รบ. พิมพ์หัวข้อ "จังหวัด" · "เชื้อชาติ สัญชาติ ศาสนา" ·
-- "ชื่อบิดา" · "ชื่อมารดา" · "กลุ่มอาชีพ" · "ออกจากสถานศึกษาเมื่อ" ·
-- "เหตุที่ออก" ไว้ครบ แล้วเว้นค่าว่างไว้ทุกใบ — เพราะแม่แบบ**ฮาร์ดโค้ด
-- ค่าว่าง**ลงไปตรง ๆ ไม่ใช่เพราะฐานข้อมูลไม่มีข้อมูล
--
-- ข้อมูลส่วนใหญ่มีอยู่แล้วตั้งแต่ 0053 (`person_sensitive` · `student_parent` ·
-- `person.nationality`) และ 0002 (`student_status_history`) แต่ไม่เคยมีใคร
-- ต่อสายจากตารางพวกนั้นมาถึง payload ของใบ รบ. เลย
--
-- **เป็นรูปเดียวกับข้อ 8 และข้อ 15 ในรายการ "พังแบบเงียบ ๆ"** — ของที่
-- ประกาศเจตนาไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น ต่างกันแค่ที่นี่
-- เจตนาถูกประกาศไว้บน**กระดาษที่ส่งให้คนอื่น** ไม่ใช่ในคอมเมนต์
--
-- ═══ สองช่องที่ไม่มีที่เก็บจริง ═══
-- `จังหวัด` ของสถานศึกษา กับ `กลุ่มอาชีพ` ของสาขาวิชา — ค้นทั้งสคีมาแล้ว
-- ไม่มีคอลัมน์ไหนเก็บ (docs/transcript-formats.md ระบุไว้ว่า "ไม่มี")
-- จึงเพิ่มคอลัมน์ให้ที่ตารางที่เป็นเจ้าของเรื่องนั้นจริง ๆ
--
-- ═══ PDPA — ทำไมข้อมูลอ่อนไหวลง payload ได้ ═══
-- หลักข้อ 5ก บอกว่า payload ต้องมี**เฉพาะสิ่งที่กระดาษใบนั้นแสดง**
-- เชื้อชาติ ศาสนา และชื่อบิดามารดา **พิมพ์อยู่บนใบ รบ. จริง** (วัดจากไฟล์
-- ต้นฉบับใน pdf/) จึงเข้าเงื่อนไข — ต่างจากผลคัดกรอง SDQ หรือบันทึก
-- เยี่ยมบ้านที่ใบไม่ได้แสดงและห้ามคัดลอกลงมาเด็ดขาด
-- และเพราะ payload ลบไม่ได้ จึงเก็บเฉพาะสามช่องนี้ ไม่ใช่ทั้ง
-- `person_sensitive` ซึ่งมีหมู่เลือด โรคประจำตัว และความพิการอยู่ด้วย
-- ═══════════════════════════════════════════════════════════════════

begin;

-- ── จังหวัดของสถานศึกษา ────────────────────────────────────────────
-- อยู่บน `institution` เพราะเป็นข้อเท็จจริงของสถานศึกษา ไม่ใช่ข้อความ
-- ที่วิทยาลัยเขียนเอง (ซึ่งจะไปอยู่ `institution_document_text`)
alter table institution add column if not exists province_th text;

comment on column institution.province_th is
  'จังหวัดที่ตั้งสถานศึกษา — พิมพ์บนหัวใบ รบ. ใต้ชื่อสถานศึกษา';

-- ── กลุ่มอาชีพ ─────────────────────────────────────────────────────
-- ใบ ปวช.67 มีช่องนี้อยู่ระหว่าง "ประเภทวิชา" กับ "สาขาวิชา"
-- จึงเป็นคุณสมบัติของ program (สาขาวิชา) ไม่ใช่ของนักศึกษา
alter table program add column if not exists career_group_th text;

comment on column program.career_group_th is
  'กลุ่มอาชีพตามการจัดกลุ่มของ สอศ. — พิมพ์บนหัวใบ รบ. ระหว่างประเภทวิชากับสาขาวิชา';

-- ── ต่อสายจากตารางที่มีข้อมูลอยู่แล้วมาถึง payload ของใบ รบ. ────────
/*
 * เพิ่มช่องให้ใบ รบ. แก้ที่ `transcript_extra()` ที่เดียวตามที่ 0059 วางไว้
 * — ไม่ต้องเขียน `issue_document_core()` ทับทั้ง 300 บรรทัดอีก
 */
create or replace function transcript_extra(p_student_id uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'category_tree', transcript_category_tree(p_student_id),
    'term_tree',     transcript_term_tree(p_student_id),
    'credits_attempted',
      (select sum(ts.credits_attempted) from term_summary ts
        where ts.student_id = p_student_id),
    /*
     * เก็บค่าที่เข้ารหัส ไม่ใช่เลขเปล่า — payload ลบไม่ได้ (0061)
     * ชั้น API ถอดตอนพิมพ์แล้วเลขไปอยู่บนกระดาษอย่างเดียว
     */
    'national_id_enc',
      (select encode(p.national_id_enc, 'hex')
         from student s join person p on p.id = s.person_id
        where s.id = p_student_id),
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
        limit 1),
    -- จังหวัดของสถานศึกษา — ช่องใต้ชื่อสถานศึกษาบนหัวใบ
    'institution_province',
      (select coalesce(i.province_th, '')
         from student s join institution i on i.id = s.institution_id
        where s.id = p_student_id),
    -- กลุ่มอาชีพของสาขาวิชาที่นักศึกษาสังกัด
    'career_group_th',
      (select coalesce(pr.career_group_th, '')
         from student_curriculum sc
         join curriculum_version cv on cv.id = sc.curriculum_version_id
         join curriculum cur    on cur.id = cv.curriculum_id
         join program_track ptr on ptr.id = cur.program_track_id
         join program pr        on pr.id  = ptr.program_id
        where sc.student_id = p_student_id
          and (sc.effective_to is null or sc.effective_to >= current_date)
        order by sc.effective_from desc nulls last
        limit 1),
    /*
     * เชื้อชาติ · สัญชาติ · ศาสนา — สามช่องนี้อยู่บนบรรทัดเดียวของใบจริง
     * เก็บเฉพาะสามช่อง ไม่ใช่ทั้ง person_sensitive เพราะ payload ลบไม่ได้
     */
    'person_extra',
      (select jsonb_build_object(
                'ethnicity',   coalesce(ps.ethnicity, ''),
                'nationality', coalesce(p.nationality, ''),
                'religion',    coalesce(ps.religion, ''))
         from student s
         join person p on p.id = s.person_id
         left join person_sensitive ps on ps.person_id = p.id
        where s.id = p_student_id),
    /*
     * ชื่อบิดา · ชื่อมารดา — ใบพิมพ์แค่ชื่อ ไม่พิมพ์อาชีพ รายได้ เบอร์โทร
     * หรือที่อยู่ ซึ่ง `student_parent` เก็บไว้ด้วย จึงหยิบมาเฉพาะชื่อ
     */
    'parents',
      (select jsonb_object_agg(
                sp.role::text,
                trim(coalesce(sp.prefix_th, '') || coalesce(sp.first_name_th, '')
                     || ' ' || coalesce(sp.last_name_th, '')))
         from student_parent sp
        where sp.student_id = p_student_id),
    /*
     * ออกจากสถานศึกษาเมื่อ · เหตุที่ออก
     *
     * เอาเฉพาะสถานะที่**แปลว่าออกจากสถานศึกษาจริง** ไม่ใช่ทุกการเปลี่ยน
     * สถานะ — `on_leave` กับ `suspended` คือยังอยู่ในสถานศึกษา คนที่เคย
     * พักการเรียนแล้วกลับมาเรียนต่อจึงต้องไม่ถูกนับ ถ้าหยิบแถวล่าสุดมา
     * ดื้อ ๆ ใบจะเขียนว่าออกไปแล้วทั้งที่กำลังเรียนอยู่
     *
     * และต้องตรงกับสถานะ**ปัจจุบัน**ของนักศึกษาด้วย มิฉะนั้นคนที่เคยพ้นสภาพ
     * แล้วได้กลับเข้าเรียนใหม่จะยังมีวันที่ออกค้างอยู่บนใบ
     */
    'leaving',
      (select jsonb_build_object(
                'on_date', h.effective_on,
                'reason',  coalesce(h.reason, ''),
                'status',  h.to_status::text)
         from student_status_history h
         join student s on s.id = h.student_id
        where h.student_id = p_student_id
          and h.to_status = s.status
          and h.to_status in ('graduated', 'withdrawn', 'transferred_out',
                              'dismissed')
        order by h.effective_on desc, h.recorded_at desc
        limit 1))
$$;

comment on function transcript_extra(uuid) is
  'payload ส่วนที่มีเฉพาะใบ รบ. — เพิ่มช่องให้ใบ รบ. แก้ที่นี่ที่เดียว ไม่ต้องเขียน issue_document_core ทับทั้งตัว';

commit;

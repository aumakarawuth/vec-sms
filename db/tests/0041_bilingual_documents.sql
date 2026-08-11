-- ═══════════════════════════════════════════════════════════════════
-- 0041_bilingual_documents.sql
-- ทดสอบเอกสารฉบับภาษาอังกฤษ (0057)
--
-- ─── ทำไมต้องมีเทสต์ก่อนที่แม่แบบจะมี ───
-- `issued_document.payload` แก้ไม่ได้ ใบที่ออกวันนี้ด้วย payload ที่ขาดช่อง
-- จะขาดตลอดไป เทสต์ชุดนี้จึงคุม**ฝั่งข้อมูล** ไม่ใช่ฝั่งการวางหน้า —
-- แม่แบบเป็นโค้ดที่แก้เมื่อไรก็ได้ ส่วน payload ที่ออกไปแล้วแก้ไม่ได้เลย
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. ออกใบภาษาอังกฤษไม่ได้ถ้าข้อมูลอังกฤษยังไม่ครบ และข้อความบอกว่าขาดอะไร
-- 2. กรอกครบแล้วออกได้ และ payload มีชื่ออังกฤษจริง
-- 3. เลขที่ฉบับอังกฤษเดินคนละสายกับฉบับไทย
-- 4. ฉบับไทยยังทำงานเหมือนเดิมทุกประการ (การเพิ่มต้องไม่แก้ของเดิม)
-- 5. เกณฑ์การสำเร็จการศึกษาของแต่ละวิทยาลัยไม่ปนกัน
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

select sg.student_id as stu_id, s.institution_id as inst_id
  from student_graduation sg
  join student s on s.id = sg.student_id
 order by sg.student_id limit 1 \gset

select p.id as registrar_person
  from person p join staff st on st.person_id = p.id
  join staff_role sr on sr.staff_id = st.id
 where sr.role in ('registrar', 'director', 'admin')
   and st.institution_id = :'inst_id'
 order by p.id limit 1 \gset

select set_config('t.stu', :'stu_id', false) a,
       set_config('t.inst', :'inst_id', false) b,
       set_config('t.reg', :'registrar_person', false) c \gset

-- ── TEST 257 ───────────────────────────────────────────────────────
-- ข้อมูลอังกฤษไม่ครบ → ออกไม่ได้ และบอกว่าขาดอะไร
do $$
declare v_blocked boolean := false; v_msg text; v_doc issued_document;
begin
  -- ล้างชื่ออังกฤษให้แน่ใจว่าไม่ครบจริง
  update person p set first_name_en = null, last_name_en = null
    from student s where s.id = current_setting('t.stu')::uuid and p.id = s.person_id;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.reg'), true);
  perform set_config('app.role',           'registrar', true);

  begin
    v_doc := issue_document(current_setting('t.stu')::uuid, 'transcript', null, null, 'en');
  exception when others then
    v_blocked := true; v_msg := sqlerrm;
  end;

  reset role;

  if not v_blocked then
    raise exception 'TEST 257 ล้มเหลว: ออกใบภาษาอังกฤษได้ทั้งที่ยังไม่มีชื่ออังกฤษ '
                    '— จะได้ใบที่หัวเป็นอังกฤษแต่ชื่อเป็นไทย และแก้ไม่ได้เพราะ payload ตรึงแล้ว';
  end if;
  if v_msg not like '%ภาษาอังกฤษ%' then
    raise exception 'TEST 257 ล้มเหลว: ข้อความผิดพลาดไม่ได้บอกว่าขาดอะไร — ได้ %', v_msg;
  end if;

  raise notice 'TEST 257 ผ่าน — ปฏิเสธพร้อมบอกสิ่งที่ขาด (%)', left(v_msg, 90);
end $$;

reset role;

-- ── TEST 258 ───────────────────────────────────────────────────────
-- กรอกครบแล้วออกได้ · payload มีชื่ออังกฤษ · เลขที่คนละสาย
do $$
declare
  v_th issued_document; v_en issued_document;
  v_name_en text; v_lang text;
begin
  -- กรอกภาษาอังกฤษให้ครบด้วยสิทธิ์เจ้าของฐานข้อมูล
  update person p set first_name_en = 'Somchai', last_name_en = 'Jaidee',
                      prefix_en = 'Mr.'
    from student s where s.id = current_setting('t.stu')::uuid and p.id = s.person_id;
  update institution set name_en = 'Example Vocational College'
   where id = current_setting('t.inst')::uuid and coalesce(name_en, '') = '';
  update program_type   set name_en = 'Industry'          where coalesce(name_en, '') = '';
  update program        set name_en = 'Automotive'        where coalesce(name_en, '') = '';
  update program_track  set name_en = 'Automotive Works'  where coalesce(name_en, '') = '';
  update course         set name_en = code                where coalesce(name_en, '') = '';

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.reg'), true);
  perform set_config('app.role',           'registrar', true);

  v_th := issue_document(current_setting('t.stu')::uuid, 'transcript', 2569::smallint, null, 'th');
  v_en := issue_document(current_setting('t.stu')::uuid, 'transcript', 2569::smallint, null, 'en');

  reset role;

  v_name_en := v_en.payload -> 'student' ->> 'full_name_en';
  v_lang    := v_en.payload ->> 'lang';

  if coalesce(v_name_en, '') = '' then
    raise exception 'TEST 258 ล้มเหลว: payload ของฉบับอังกฤษไม่มีชื่ออังกฤษ';
  end if;
  if v_lang <> 'en' then
    raise exception 'TEST 258 ล้มเหลว: payload ไม่ได้บันทึกว่าเป็นฉบับภาษาอะไร (ได้ %) '
                    '— แม่แบบจะไม่รู้ว่ากำลังพิมพ์ฉบับไหน', v_lang;
  end if;
  if coalesce(v_en.payload -> 'program' ->> 'track_en', '') = '' then
    raise exception 'TEST 258 ล้มเหลว: payload ไม่มีชื่อสาขางานภาษาอังกฤษ';
  end if;
  if v_th.doc_no <> v_en.doc_no then
    -- ต่างกันคือถูกต้อง แต่ต้องต่างเพราะ**คนละสาย** ไม่ใช่เพราะเดินต่อกัน
    null;
  else
    raise exception 'TEST 258 ล้มเหลว: ฉบับไทยกับอังกฤษได้เลขที่เดียวกัน (%)', v_th.doc_no;
  end if;

  raise notice 'TEST 258 ผ่าน — ฉบับไทยเลขที่ % · ฉบับอังกฤษเลขที่ % · ชื่อ %',
               v_th.doc_no, v_en.doc_no, v_name_en;
end $$;

reset role;

-- ── TEST 259 ───────────────────────────────────────────────────────
-- เลขที่เดินคนละสายจริง ไม่ใช่แค่บังเอิญต่างกัน
--
-- ออกฉบับไทยอีกใบแล้วเลขต้องเดินต่อจากฉบับไทยเดิม ไม่ใช่ต่อจากฉบับอังกฤษ
do $$
declare v_a text; v_b text; v_en text; v_rows integer;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.reg'), true);
  perform set_config('app.role',           'registrar', true);

  v_a  := (issue_document(current_setting('t.stu')::uuid, 'transcript', 2569::smallint, null, 'th')).doc_no;
  v_en := (issue_document(current_setting('t.stu')::uuid, 'transcript', 2569::smallint, null, 'en')).doc_no;
  v_b  := (issue_document(current_setting('t.stu')::uuid, 'transcript', 2569::smallint, null, 'th')).doc_no;

  reset role;

  select count(*) into v_rows from document_series
   where institution_id = current_setting('t.inst')::uuid
     and kind = 'transcript' and year_be = 2569;

  if v_rows <> 2 then
    raise exception 'TEST 259 ล้มเหลว: สายเลขที่ควรมีสองแถว (ไทยและอังกฤษ) ได้ % แถว', v_rows;
  end if;
  if right(v_b, 5)::integer <> right(v_a, 5)::integer + 1 then
    raise exception 'TEST 259 ล้มเหลว: ฉบับไทยเดินเลข % → % ซึ่งไม่ต่อกัน '
                    '— แปลว่าฉบับอังกฤษไปกินเลขของสายไทย', v_a, v_b;
  end if;

  raise notice 'TEST 259 ผ่าน — ไทยเดิน % → % ส่วนอังกฤษอยู่ที่ % คนละสาย', v_a, v_b, v_en;
end $$;

reset role;

-- ── TEST 260 ───────────────────────────────────────────────────────
-- ฉบับไทยยังทำงานเหมือนเดิม — การเรียกแบบสี่อาร์กิวเมนต์ยังใช้ได้
do $$
declare v_doc issued_document;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.reg'), true);
  perform set_config('app.role',           'registrar', true);

  -- ไม่ส่งพารามิเตอร์ภาษา — ต้องได้ฉบับไทยเหมือนก่อนมี 0057
  v_doc := issue_document(current_setting('t.stu')::uuid, 'transcript');

  reset role;

  if coalesce(v_doc.payload ->> 'lang', 'th') <> 'th' then
    raise exception 'TEST 260 ล้มเหลว: การเรียกแบบเดิมไม่ได้ฉบับไทย';
  end if;
  if coalesce(v_doc.payload -> 'student' ->> 'full_name_th', '') = '' then
    raise exception 'TEST 260 ล้มเหลว: ฉบับไทยขาดชื่อภาษาไทย';
  end if;
  if jsonb_array_length(v_doc.payload -> 'courses') = 0 then
    raise exception 'TEST 260 ล้มเหลว: ฉบับไทยขาดรายวิชา — การเพิ่มภาษาไปทำของเดิมพัง';
  end if;

  raise notice 'TEST 260 ผ่าน — เรียกแบบเดิมยังได้ฉบับไทยครบ (% รายวิชา)',
               jsonb_array_length(v_doc.payload -> 'courses');
end $$;

reset role;

-- ── TEST 261 ───────────────────────────────────────────────────────
-- เกณฑ์การสำเร็จการศึกษาของแต่ละวิทยาลัยไม่ปนกัน
--
-- ถ้าข้อความนี้ไปอยู่ในแม่แบบแทนที่จะอยู่ในฐานข้อมูล ข้อความของวิทยาลัยเดียว
-- จะติดไปกับทุกวิทยาลัยที่ใช้ระบบ
do $$
declare v_text jsonb; v_other integer;
begin
  insert into institution_document_text (institution_id, key, text_th, text_en)
  values (current_setting('t.inst')::uuid, 'transcript_criteria_1',
          'เรียนครบตามโครงสร้างหลักสูตร', 'Completed all required credits')
  on conflict (institution_id, key) do update set text_th = excluded.text_th;

  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.reg'), true);
  perform set_config('app.role',           'registrar', true);

  v_text := (issue_document(current_setting('t.stu')::uuid, 'transcript')).payload
              -> 'institution_text';

  -- วิทยาลัยอื่นต้องมองไม่เห็นข้อความของเรา
  perform set_config('app.institution_id', '11111111-2222-2222-2222-111111111111', true);
  select count(*) into v_other from institution_document_text;

  reset role;

  if coalesce(v_text -> 'transcript_criteria_1' ->> 'th', '') = '' then
    raise exception 'TEST 261 ล้มเหลว: payload ไม่มีเกณฑ์การสำเร็จการศึกษาของวิทยาลัย';
  end if;
  if coalesce(v_text -> 'transcript_criteria_1' ->> 'en', '') = '' then
    raise exception 'TEST 261 ล้มเหลว: เกณฑ์ไม่มีฉบับภาษาอังกฤษ '
                    '— ซึ่งเป็นเหตุผลทั้งหมดที่ต้องมีตารางนี้';
  end if;
  if v_other <> 0 then
    raise exception 'TEST 261 ล้มเหลว: วิทยาลัยอื่นเห็นข้อความของเรา % แถว', v_other;
  end if;

  raise notice 'TEST 261 ผ่าน — เกณฑ์อยู่ใน payload ทั้งสองภาษา และไม่รั่วข้ามวิทยาลัย';
end $$;

reset role;

-- ── TEST 262 ───────────────────────────────────────────────────────
-- ปีการศึกษาใหม่ต้องไม่ออกเลขที่ซ้ำกับปีก่อน
--
-- `issued_document` มี unique (institution, kind, doc_no, copy_no) ซึ่ง
-- **ไม่มีปีการศึกษาอยู่ในนั้น** ส่วนตัวนับเริ่มที่ 1 ใหม่ทุกปี ถ้า prefix
-- เป็นค่าว่าง ใบแรกของปีการศึกษาใหม่จะล้มด้วย duplicate key พร้อมข้อความ
-- ที่อธิบายอะไรไม่ได้ — อาการโผล่หนึ่งปีหลังเปิดใช้งานพอดี และโผล่กับ
-- ทุกวิทยาลัยที่ไม่เคยตั้ง prefix เอง ซึ่งคือทุกวิทยาลัย
do $$
declare v_a text; v_b text;
begin
  set local role app_runtime;
  perform set_config('app.institution_id', current_setting('t.inst'), true);
  perform set_config('app.actor_id',       current_setting('t.reg'), true);
  perform set_config('app.role',           'registrar', true);

  v_a := next_document_no('certification', 2600::smallint);
  v_b := next_document_no('certification', 2601::smallint);

  reset role;

  if v_a = v_b then
    raise exception 'TEST 262 ล้มเหลว: ปีการศึกษาสองปีออกเลขที่เดียวกัน (%) '
                    '— ใบแรกของปีใหม่จะล้มด้วย duplicate key', v_a;
  end if;

  raise notice 'TEST 262 ผ่าน — ปี 2600 ได้ % · ปี 2601 ได้ % ไม่ซ้ำกัน', v_a, v_b;
end $$;

reset role;

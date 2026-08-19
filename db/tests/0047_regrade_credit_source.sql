-- ═══════════════════════════════════════════════════════════════════
-- 0047_regrade_credit_source.sql
-- ทดสอบว่า (*3) ติดให้เองเมื่อคำร้องจากรอบเรียนปรับระดับคะแนนมีผล (0067)
--
-- ─── ทำไมต้องตรวจว่า "ติดเอง" ไม่ใช่ "ตั้งค่าได้" ───
-- 0066 สร้างค่า `regraded` พร้อมตัวแปลงและแม่แบบที่พิมพ์ (*3) ได้จริง
-- แต่ไม่มีเส้นทางไหนตั้งค่านั้นเลย — เทสต์ที่ `update enrollment set
-- credit_source = 'regraded'` ตรง ๆ แล้วดูว่าใบพิมพ์ถูก จะเขียวสนิท
-- โดยที่ในระบบจริงไม่มีวันมีแถวไหนได้ค่านั้น
--
-- ─── ทำไมสร้างเคสเองทั้งสองแบบ ไม่ยืมของ 0015 ───
-- คำร้องที่ 0015 ทิ้งไว้มีผู้ยื่นที่ไฟล์นี้ควบคุมไม่ได้ และ dual control
-- ต้องการคนสามคนที่ต่างกัน (ผู้ยื่น + ผู้อนุมัติสองคน) ส่วนชุดตัวอย่างมี
-- บุคลากรแค่สองคน — การยืมของเดิมจึงล้มหรือผ่านขึ้นกับว่า 0015 รันเป็นใคร
-- ซึ่งเป็นเทสต์ที่ผลไม่ได้มาจากสิ่งที่กำลังทดสอบ
--
-- ตัวตนที่ใช้ที่นี่เป็นแค่ "คนสามคนที่ต่างกัน" — กฎว่าใครมีสิทธิ์อนุมัติ
-- บ้างถูกทดสอบไว้แล้วที่ 0009 ไฟล์นี้ทดสอบ trigger ของ 0067 อย่างเดียว
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
declare
  v_inst uuid := '11111111-1111-1111-1111-111111111111';
  v_p1 uuid; v_p2 uuid; v_p3 uuid;          -- ผู้ยื่น · ผู้อนุมัติคนที่ 1 · คนที่ 2
  v_sym_pass uuid;
  v_enroll uuid; v_cand uuid; v_req uuid; v_src text; n integer;
  v_enroll2 uuid; v_cand2 uuid; v_req2 uuid;
  v_enroll3 uuid; v_cand3 uuid; v_req3 uuid;
  v_sc3   uuid := 'f0000000-0000-0000-0000-000000000025';
  v_sess  uuid := 'f0000000-0000-0000-0000-000000000021';
  v_sc    uuid := 'f0000000-0000-0000-0000-000000000022';
  v_sess2 uuid := 'f0000000-0000-0000-0000-000000000023';
  v_sc2   uuid := 'f0000000-0000-0000-0000-000000000024';
begin
  perform set_config('app.institution_id', v_inst::text, true);
  perform set_config('app.role', 'academic', true);

  select p.id into v_p1 from person p where p.institution_id = v_inst order by p.id limit 1;
  select p.id into v_p2 from person p where p.institution_id = v_inst and p.id <> v_p1
   order by p.id limit 1;
  select p.id into v_p3 from person p where p.institution_id = v_inst
     and p.id not in (v_p1, v_p2) order by p.id limit 1;
  if v_p3 is null then
    raise exception 'TEST 286 เตรียมข้อมูลไม่พอ: ต้องมีคนอย่างน้อยสามคนสำหรับ dual control';
  end if;

  select gs.id into v_sym_pass from grade_symbol gs
   where gs.earns_credit and gs.grade_point = 1.0 limit 1;

  -- ── หาสองการลงทะเบียนที่ยังไม่มีคำร้องค้าง ────────────────────────
  --
  -- `request_grade_change()` ปฏิเสธการยื่นซ้ำบนการลงทะเบียนเดียวกัน ซึ่ง
  -- ถูกต้อง แต่เทสต์ชุดก่อนหน้า (0009 · 0015) ทิ้งคำร้องไว้บนหลายแถว
  select e.id into v_enroll
    from enrollment e
    join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
   where e.credit_source = 'studied'
     and not exists (select 1 from grade_change_request g where g.enrollment_id = e.id)
   order by e.id limit 1;

  select e.id into v_enroll2
    from enrollment e
    join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
   where e.credit_source = 'studied' and e.id <> v_enroll
     and not exists (select 1 from grade_change_request g where g.enrollment_id = e.id)
   order by e.id limit 1;

  if v_enroll is null or v_enroll2 is null then
    raise exception 'TEST 286 เตรียมข้อมูลไม่พอ: ต้องมีการลงทะเบียนที่ไม่มีคำร้องค้างสองรายการ';
  end if;

  -- ── รอบเรียนปรับระดับคะแนน (restudy) ─────────────────────────────
  insert into regrade_session
    (id, institution_id, term_id, code, name_th, kind, opens_on, closes_on, status)
  select v_sess, v_inst, e.term_id, 'RS-0047', 'เรียนปรับระดับคะแนน (เทสต์ 0047)',
         'restudy', current_date - 1, current_date + 30, 'open'
    from enrollment e where e.id = v_enroll
  on conflict (id) do nothing;

  insert into regrade_session_course (id, session_id, course_id, fee_amount, capacity)
  select v_sc, v_sess, cs.course_id, 0, 5
    from enrollment e join class_section cs on cs.id = e.class_section_id
   where e.id = v_enroll
  on conflict (id) do nothing;

  insert into regrade_candidate (session_course_id, student_id, source_enrollment_id, status)
  select v_sc, e.student_id, e.id, 'registered' from enrollment e where e.id = v_enroll
  returning id into v_cand;

  -- ── รอบสอบซ่อม (retest) ──────────────────────────────────────────
  insert into regrade_session
    (id, institution_id, term_id, code, name_th, kind, opens_on, closes_on, status)
  select v_sess2, v_inst, e.term_id, 'RT-0047', 'สอบซ่อม (เทสต์ 0047)',
         'retest', current_date - 1, current_date + 30, 'open'
    from enrollment e where e.id = v_enroll2
  on conflict (id) do nothing;

  insert into regrade_session_course (id, session_id, course_id, fee_amount, capacity)
  select v_sc2, v_sess2, cs.course_id, 0, 5
    from enrollment e join class_section cs on cs.id = e.class_section_id
   where e.id = v_enroll2
  on conflict (id) do nothing;

  insert into regrade_candidate (session_course_id, student_id, source_enrollment_id, status)
  select v_sc2, e.student_id, e.id, 'registered' from enrollment e where e.id = v_enroll2
  returning id into v_cand2;

  -- ── TEST 286 restudy ที่ผ่านการอนุมัติแล้ว ต้องได้ (*3) ──────────
  perform set_config('app.actor_id', v_p1::text, true);
  v_req := record_regrade_result(v_cand, v_sym_pass, 'เรียนปรับระดับคะแนนผ่าน', 'ที่ ศธ 47/2569');

  -- ยื่นแล้วแต่ยังไม่อนุมัติ — ต้องยังไม่ติดเครื่องหมาย
  select credit_source::text into v_src from enrollment where id = v_enroll;
  if v_src <> 'studied' then
    raise exception 'TEST 286 ล้มเหลว: ติด (*3) ตั้งแต่ยังไม่อนุมัติ — ได้ %', v_src;
  end if;

  perform set_config('app.actor_id', v_p2::text, true);
  perform approve_grade_change(v_req);
  perform set_config('app.actor_id', v_p3::text, true);
  perform approve_grade_change(v_req);

  select credit_source::text into v_src from enrollment where id = v_enroll;
  if v_src <> 'regraded' then
    raise exception 'TEST 286 ล้มเหลว: คำร้องจากรอบเรียนปรับเกรดมีผลแล้วแต่ไม่ติด (*3) — ได้ %', v_src;
  end if;

  select count(*) into n
    from transcript_courses_grouped((select student_id from enrollment where id = v_enroll))
   where note_marks && array[3]::smallint[];
  if n = 0 then
    raise exception 'TEST 286 ล้มเหลว: (*3) ไม่ขึ้นในตัวอ่านของใบ รบ.';
  end if;

  -- ── TEST 287 retest ต้องไม่ติดเครื่องหมาย ────────────────────────
  --
  -- สอบซ่อมคือการสอบใหม่หลังไม่ผ่าน ไม่ใช่การเรียนซ้ำเพื่อยกเกรดที่ผ่านแล้ว
  -- ถ้าติดให้ด้วย ใบจะบอกสิ่งที่ไม่ได้เกิดขึ้นกับนักศึกษาเกือบทุกคนที่เคยตก
  perform set_config('app.actor_id', v_p1::text, true);
  v_req2 := record_regrade_result(v_cand2, v_sym_pass, 'สอบซ่อมผ่าน', 'ที่ ศธ 48/2569');
  perform set_config('app.actor_id', v_p2::text, true);
  perform approve_grade_change(v_req2);
  perform set_config('app.actor_id', v_p3::text, true);
  perform approve_grade_change(v_req2);

  select credit_source::text into v_src from enrollment where id = v_enroll2;
  if v_src <> 'studied' then
    raise exception 'TEST 287 ล้มเหลว: สอบซ่อมไม่ควรติดเครื่องหมาย — ได้ %', v_src;
  end if;

  /*
   * ── TEST 288 ที่มาของหน่วยกิตเดิมไม่ถูกเขียนทับ ──────────────────
   *
   * วิชาที่เทียบโอนมาแล้วมาขอปรับเกรดทีหลังยังต้องคง (*1)/(*2) ไว้ เพราะ
   * ที่มาของหน่วยกิตไม่ได้เปลี่ยน เปลี่ยนแค่ระดับคะแนน — ถ้าเขียนทับ ใบจะ
   * บอกว่าเรียนเองทั้งที่โอนมา ซึ่งผิดข้อเท็จจริงบนเอกสารที่แก้ไม่ได้
   *
   * ─── ทำไมต้องใช้คำร้องใบใหม่ ───
   * รอบแรกผมพาสถานะของใบเดิมกลับไป `approved` แล้วกลับมา `applied` เพื่อ
   * ยิง trigger ซ้ำ ซึ่ง `grade_change_request_guard()` ปฏิเสธถูกแล้ว —
   * `applied` เป็นสถานะปลายทาง คำร้องที่มีผลไปแล้วต้องย้อนไม่ได้ มิฉะนั้น
   * เกรดที่ออกเอกสารไปแล้วจะถูกแก้ซ้ำได้โดยไม่ต้องยื่นใหม่
   */
  select e.id into v_enroll3
    from enrollment e
    join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
   where e.id not in (v_enroll, v_enroll2)
     and not exists (select 1 from grade_change_request g where g.enrollment_id = e.id)
   order by e.id limit 1;

  if v_enroll3 is null then
    raise notice 'TEST 288 ข้าม — ไม่มีการลงทะเบียนที่สามที่ยังไม่มีคำร้องค้าง';
  else
    update enrollment set credit_source = 'transferred_grade' where id = v_enroll3;

    insert into regrade_session_course (id, session_id, course_id, fee_amount, capacity)
    select v_sc3, v_sess, cs.course_id, 0, 5
      from enrollment e join class_section cs on cs.id = e.class_section_id
     where e.id = v_enroll3
    on conflict (id) do nothing;

    insert into regrade_candidate (session_course_id, student_id, source_enrollment_id, status)
    select v_sc3, e.student_id, e.id, 'registered' from enrollment e where e.id = v_enroll3
    returning id into v_cand3;

    perform set_config('app.actor_id', v_p1::text, true);
    v_req3 := record_regrade_result(v_cand3, v_sym_pass, 'ปรับเกรดวิชาที่เทียบโอนมา', 'ที่ ศธ 49/2569');
    perform set_config('app.actor_id', v_p2::text, true);
    perform approve_grade_change(v_req3);
    perform set_config('app.actor_id', v_p3::text, true);
    perform approve_grade_change(v_req3);

    select credit_source::text into v_src from enrollment where id = v_enroll3;
    if v_src <> 'transferred_grade' then
      raise exception 'TEST 288 ล้มเหลว: (*3) เขียนทับที่มาของหน่วยกิตเดิม — ได้ %', v_src;
    end if;
    raise notice 'TEST 288 ผ่าน — วิชาที่เทียบโอนมายังคง (*1) ไว้แม้จะปรับเกรดทีหลัง';
  end if;

  raise notice 'TEST 286 ผ่าน — คำร้องจากรอบเรียนปรับระดับคะแนนมีผลแล้วติด (*3) ให้เอง';
  raise notice 'TEST 287 ผ่าน — สอบซ่อมไม่ติดเครื่องหมาย ยังเป็น studied';
end $$;

do $$ begin raise notice ''; raise notice '════ ทดสอบ (*3) จากรอบเรียนปรับระดับคะแนนครบทุกข้อ ════'; end $$;

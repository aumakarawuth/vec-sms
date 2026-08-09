-- ═══════════════════════════════════════════════════════════════════
-- 0006_assessment_rls.sql
-- ทดสอบว่าตารางฝั่งวัดผลกันข้ามวิทยาลัยได้จริงหลัง migration 0015
--
-- เทสต์ชุดนี้เกิดจากการตรวจพบว่าตารางหกตัวในกลุ่มวัดผลไม่มี RLS เลย
-- ตอนจะเริ่มเขียน endpoint สมุดคะแนน ถ้าไม่มีเทสต์คุมไว้ ตารางที่เพิ่ม
-- ในอนาคตก็จะหลุดแบบเดียวกันอีก TEST 45 จึงเป็นเทสต์แบบครอบคลุม
-- ไม่ใช่เทสต์รายตาราง
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_runtime') then
    create role app_runtime nologin;
  end if;
end $$;

grant usage on schema public to app_runtime;
grant select, insert, update, delete on all tables in schema public to app_runtime;
grant usage, select on all sequences in schema public to app_runtime;

-- ── TEST 45 ────────────────────────────────────────────────────────
-- ตารางกลุ่มวัดผลทุกตารางต้องเปิด RLS และต้องเป็น force ด้วย
--
-- force สำคัญเพราะถ้าไม่ตั้ง เจ้าของตารางจะข้าม RLS ได้เสมอ
-- และในระบบจริงเจ้าของตารางคือผู้ใช้ที่รัน migration ซึ่งมักถูกเผลอเอาไป
-- ใช้เชื่อมต่อจากสคริปต์อื่น
do $$
declare v_missing text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_missing
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and c.relname in ('grade_scheme', 'grade_symbol', 'grade_cutoff',
                       'gradebook_item', 'gradebook_score',
                       'grade_submission', 'grade_submission_event',
                       'enrollment_result', 'grade_change_request',
                       'term_summary', 'grade_ledger')
     and not (c.relrowsecurity and c.relforcerowsecurity);

  if v_missing is not null then
    raise exception 'TEST 45 ล้มเหลว: ตารางกลุ่มวัดผลที่ยังไม่ได้เปิด RLS แบบ force — %', v_missing;
  end if;
  raise notice 'TEST 45 ผ่าน — ตารางกลุ่มวัดผลทั้ง 11 ตารางเปิด RLS แบบ force แล้ว';
end $$;

-- ── TEST 45b ───────────────────────────────────────────────────────
-- ทุกตารางที่เก็บข้อมูลของวิทยาลัยต้องเปิด RLS แบบ force — ไม่มีข้อยกเว้น
--
-- เทสต์ข้อนี้เป็นแบบครอบคลุมโดยเจตนา ไม่ใช่ไล่ทีละตาราง เพราะรูปแบบ
-- ความผิดพลาดที่เกิดจริงคือ "เพิ่มตารางใหม่แล้วลืมเขียนนโยบาย"
-- การไล่ทีละตารางจะไม่มีวันจับกรณีนั้นได้เลย
do $$
declare v_missing text; v_count int;
begin
  select count(*), string_agg(c.relname, ', ' order by c.relname)
    into v_count, v_missing
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and not (c.relrowsecurity and c.relforcerowsecurity)
     -- institution คือตัวกำหนดขอบเขตเอง จะกรองด้วยตัวเองไม่ได้
     -- schema_migrations เป็นข้อมูลของระบบ ไม่ใช่ของวิทยาลัยใด
     and c.relname not in ('institution', 'schema_migrations');

  if v_missing is not null then
    raise exception 'TEST 45b ล้มเหลว: ยังมี % ตารางที่ไม่มี RLS แบบ force — %',
      v_count, v_missing;
  end if;
  raise notice 'TEST 45b ผ่าน — ทุกตารางในสคีมาเปิด RLS แบบ force แล้ว ไม่เหลือช่องว่าง';
end $$;

-- ── TEST 45c ───────────────────────────────────────────────────────
-- ทุกตารางที่เปิด RLS ต้องมีนโยบายอย่างน้อยหนึ่งข้อ
--
-- ตารางที่เปิด RLS แต่ไม่มีนโยบายเลยจะปฏิเสธทุกอย่างเงียบ ๆ
-- ซึ่งดูเผิน ๆ เหมือนปลอดภัย แต่จริง ๆ คือฟีเจอร์ที่พังโดยไม่มีใครรู้
do $$
declare v_empty text;
begin
  select string_agg(c.relname, ', ' order by c.relname) into v_empty
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
     and not exists (select 1 from pg_policy p where p.polrelid = c.oid);

  if v_empty is not null then
    raise exception 'TEST 45c ล้มเหลว: เปิด RLS แต่ไม่มีนโยบายเลย — %', v_empty;
  end if;
  raise notice 'TEST 45c ผ่าน — ทุกตารางที่เปิด RLS มีนโยบายครบ';
end $$;

-- เตรียมข้อมูล: ชิ้นงานสองชิ้น ชิ้นหนึ่งเปิดเผยให้นักศึกษา อีกชิ้นไม่เปิด
insert into gradebook_item (id, class_section_id, name_th, category, max_score, weight, publish_to_student)
values
  ('eeee0000-0000-0000-0000-000000000001',
   'bbbb0000-0000-0000-0000-000000000001', 'สอบกลางภาค', 'midterm', 30, 30, true),
  ('eeee0000-0000-0000-0000-000000000002',
   'bbbb0000-0000-0000-0000-000000000001', 'คะแนนจิตพิสัย', 'affective', 10, 10, false)
on conflict (id) do nothing;

insert into grade_submission (id, class_section_id, term_id, stage)
values ('eeee0000-0000-0000-0000-000000000011',
        'bbbb0000-0000-0000-0000-000000000001',
        '33333333-3333-3333-3333-333333333331', 'draft')
on conflict (class_section_id) do nothing;

insert into term_summary (student_id, term_id, credits_attempted, credits_earned, gpa, gpax)
values ('aaaa0000-0000-0000-0000-000000000011',
        '33333333-3333-3333-3333-333333333331', 6, 6, 3.25, 3.25)
on conflict (student_id, term_id) do update set gpa = excluded.gpa;

-- ── TEST 46 ────────────────────────────────────────────────────────
-- วิทยาลัยอื่นต้องไม่เห็นอะไรเลยในกลุ่มตารางนี้
begin;
set local role app_runtime;
set local app.institution_id = '11111111-2222-2222-2222-111111111111';
set local app.role = 'registrar';

do $$
declare v_item int; v_sub int; v_sum int; v_sym int;
begin
  select count(*) into v_item from gradebook_item;
  select count(*) into v_sub  from grade_submission;
  select count(*) into v_sum  from term_summary;
  select count(*) into v_sym  from grade_symbol;

  if v_item <> 0 or v_sub <> 0 or v_sum <> 0 or v_sym <> 0 then
    raise exception
      'TEST 46 ล้มเหลว: วิทยาลัยอื่นเห็น ชิ้นงาน % · รอบส่งเกรด % · สรุปผล % · สัญลักษณ์ %',
      v_item, v_sub, v_sum, v_sym;
  end if;
  raise notice 'TEST 46 ผ่าน — วิทยาลัยอื่นไม่เห็นข้อมูลวัดผลเลยสักแถว';
end $$;

-- เขียนข้ามวิทยาลัยก็ต้องไม่ได้ ไม่ใช่แค่อ่านไม่เห็น
do $$
begin
  begin
    insert into gradebook_item (class_section_id, name_th, max_score, weight)
    values ('bbbb0000-0000-0000-0000-000000000001', 'ชิ้นงานที่แทรกจากวิทยาลัยอื่น', 10, 10);
    raise exception 'TEST 46b ล้มเหลว: วิทยาลัยอื่นเขียนชิ้นงานเข้ากลุ่มเรียนที่ไม่ใช่ของตนได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 46b ผ่าน — วิทยาลัยอื่นเขียนข้ามไม่ได้ (with check ปฏิเสธ)';
  end;
end $$;
commit;

-- ── TEST 47 ────────────────────────────────────────────────────────
-- วิทยาลัยตัวเองยังทำงานได้ตามปกติ
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'academic';

do $$
declare v_item int; v_sub int; v_sum int;
begin
  select count(*) into v_item from gradebook_item;
  select count(*) into v_sub  from grade_submission;
  select count(*) into v_sum  from term_summary;

  if v_item < 2 or v_sub < 1 or v_sum < 1 then
    raise exception
      'TEST 47 ล้มเหลว: วิทยาลัยตัวเองควรเห็นครบ แต่เห็น ชิ้นงาน % · รอบส่งเกรด % · สรุปผล %',
      v_item, v_sub, v_sum;
  end if;
  raise notice 'TEST 47 ผ่าน — ฝ่ายวิชาการของวิทยาลัยตัวเองเห็นข้อมูลครบ (ชิ้นงาน % · รอบส่งเกรด % · สรุปผล %)',
    v_item, v_sub, v_sum;
end $$;
commit;

-- ── TEST 48 ────────────────────────────────────────────────────────
-- นักศึกษาเห็นเฉพาะชิ้นงานที่ครูเปิดเผยแล้ว
--
-- ถ้าเห็นทั้งหมด นักศึกษาจะรู้ว่ามีชิ้นงานที่ยังไม่เปิดเผยกี่ชิ้นและคะแนนเต็มเท่าไร
-- ซึ่งเป็นการรั่วทางอ้อมที่ตรงกับนโยบายบน gradebook_score ที่มีอยู่แล้ว
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'student';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000001';

do $$
declare v_total int; v_names text;
begin
  select count(*), string_agg(name_th, ', ') into v_total, v_names from gradebook_item;
  if v_total <> 1 then
    raise exception 'TEST 48 ล้มเหลว: นักศึกษาควรเห็นชิ้นงานที่เปิดเผยแล้ว 1 ชิ้น เห็น % (%)',
      v_total, coalesce(v_names, 'ไม่มี');
  end if;
  raise notice 'TEST 48 ผ่าน — นักศึกษาเห็นเฉพาะชิ้นงานที่เปิดเผยแล้ว: %', v_names;
end $$;

-- และต้องไม่เห็นรอบส่งเกรดของตัวเอง เพราะเป็นงานภายในของครูกับฝ่ายบริหาร
do $$
declare v int;
begin
  select count(*) into v from grade_submission;
  if v <> 0 then
    raise exception 'TEST 48b ล้มเหลว: นักศึกษาเห็นรอบส่งเกรด % รายการ', v;
  end if;
  raise notice 'TEST 48b ผ่าน — นักศึกษาไม่เห็นขั้นตอนอนุมัติเกรดภายใน';
end $$;

-- แต่ต้องเห็น GPA ของตัวเอง
do $$
declare v numeric;
begin
  select gpa into v from term_summary
   where student_id = 'aaaa0000-0000-0000-0000-000000000011';
  if v is null then
    raise exception 'TEST 48c ล้มเหลว: นักศึกษาดู GPA ของตัวเองไม่ได้';
  end if;
  raise notice 'TEST 48c ผ่าน — นักศึกษาเห็น GPA ของตัวเอง (%)', v;
end $$;
commit;

-- ── TEST 49 ────────────────────────────────────────────────────────
-- ครูเห็นเฉพาะกลุ่มเรียนที่ตนสอน ไม่ใช่ทุกกลุ่มในวิทยาลัย
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
-- ครูคนนี้ไม่ได้สอนกลุ่มไหนเลย (ใช้ person ของนักศึกษาเป็นตัวแทนครูที่ไม่มีกลุ่มสอน)
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000003';

do $$
declare v int;
begin
  select count(*) into v from gradebook_item;
  if v <> 0 then
    raise exception 'TEST 49 ล้มเหลว: ครูที่ไม่ได้สอนกลุ่มนี้เห็นชิ้นงาน % ชิ้น', v;
  end if;
  raise notice 'TEST 49 ผ่าน — ครูที่ไม่ได้สอนกลุ่มนั้นไม่เห็นสมุดคะแนนของกลุ่ม';
end $$;
commit;

-- ── TEST 50 ────────────────────────────────────────────────────────
-- ครูผู้สอนของกลุ่มนั้นเห็นและแก้สมุดคะแนนของตนได้
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
declare v int;
begin
  select count(*) into v from gradebook_item;
  if v <> 2 then
    raise exception 'TEST 50 ล้มเหลว: ครูผู้สอนควรเห็นชิ้นงานครบ 2 ชิ้น เห็น %', v;
  end if;

  insert into gradebook_score (gradebook_item_id, enrollment_id, score, recorded_by)
  values ('eeee0000-0000-0000-0000-000000000001',
          'cccc0000-0000-0000-0000-000000000001', 27.5,
          'aaaa0000-0000-0000-0000-000000000002')
  on conflict (gradebook_item_id, enrollment_id) do update set score = excluded.score;

  raise notice 'TEST 50 ผ่าน — ครูผู้สอนเห็นชิ้นงานครบ 2 ชิ้นและบันทึกคะแนนได้';
end $$;
commit;

-- ── TEST 51 ────────────────────────────────────────────────────────
-- ระเบียบวัดผลแก้ได้เฉพาะฝ่ายวัดผล — เปลี่ยนช่วงคะแนนกระทบทุกคนย้อนหลัง
begin;
set local role app_runtime;
set local app.institution_id = '11111111-1111-1111-1111-111111111111';
set local app.role = 'teacher';
set local app.actor_id = 'aaaa0000-0000-0000-0000-000000000002';

do $$
begin
  begin
    insert into grade_symbol (grade_scheme_id, symbol, name_th, grade_point)
    values ('44444444-4444-4444-4444-444444444444', '4.5', 'ดีเลิศพิเศษ', 4.5);
    raise exception 'TEST 51 ล้มเหลว: ครูเพิ่มสัญลักษณ์ผลการเรียนเองได้';
  exception
    when insufficient_privilege then
      raise notice 'TEST 51 ผ่าน — ครูแก้ระเบียบวัดผลไม่ได้ ต้องเป็นฝ่ายวัดผล';
  end;
end $$;
commit;

\echo ''
\echo '════ ทดสอบ RLS ฝั่งวัดผลครบทุกข้อ ════'

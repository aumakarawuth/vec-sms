-- ═══════════════════════════════════════════════════════════════════
-- 0034_request_rate_shared.sql
-- ทดสอบตัวนับคำขอที่ใช้ร่วมกันทุก instance (0050)
--
-- ─── สิ่งที่ต้องพิสูจน์ ───
-- 1. ตัวนับอยู่รอดข้ามทรานแซกชัน — นี่คือทั้งหมดที่ทำให้มันนับรวมทุก
--    instance ได้ (แต่ละคำขอของ API คือคนละทรานแซกชันจาก pool เดียวกัน)
-- 2. เกินเพดานแล้ว **ไม่ raise** แต่คืนสถานะ และ**ตัวนับต้องไม่หายไป**
--    ข้อหลังคือหัวใจ — ฟังก์ชันที่ raise จะถูก rollback พาตัวนับหายไปด้วย
--    แล้วผู้โจมตีจะยิงได้ไม่จำกัดโดยที่ระบบยังตอบปฏิเสธถูกต้องทุกครั้ง
--    (เคยเจอกับ MFA มาแล้ว — ดูรายการกับดักใน CLAUDE.md)
-- 3. app_runtime เขียนตารางตรง ๆ ไม่ได้ ต้องผ่านฟังก์ชันเท่านั้น
-- ═══════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on

-- ── TEST 223 ───────────────────────────────────────────────────────
-- ตัวนับอยู่รอดข้ามทรานแซกชัน และเกินเพดานแล้วบอกว่าให้รออีกนานเท่าไร
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_key bytea := sha256('ทดสอบ-223'::bytea);
  v_r   record;
begin
  delete from request_rate where bucket_key = v_key;

  select * into v_r from request_rate_hit(v_key, 3, 60);
  if not v_r.allowed then
    raise exception 'TEST 223 ล้มเหลว: คำขอแรกถูกปฏิเสธทั้งที่เพดานคือ 3';
  end if;
  if v_r.remaining <> 2 then
    raise exception 'TEST 223 ล้มเหลว: ยิงไปครั้งเดียวควรเหลือ 2 ได้ %', v_r.remaining;
  end if;
end $$;
commit;

-- ทรานแซกชันใหม่ — ถ้าตัวนับอยู่ในหน่วยความจำของ session จะเริ่มนับใหม่ตรงนี้
begin;
do $$
declare
  v_key   bytea := sha256('ทดสอบ-223'::bytea);
  v_r     record;
  v_hits  integer;
begin
  select * into v_r from request_rate_hit(v_key, 3, 60);
  select * into v_r from request_rate_hit(v_key, 3, 60);

  select sum(hits)::integer into v_hits from request_rate where bucket_key = v_key;
  if v_hits <> 3 then
    raise exception 'TEST 223 ล้มเหลว: นับได้ % ครั้งจากที่ยิงไป 3 ครั้ง '
      '(ตัวนับไม่อยู่รอดข้ามทรานแซกชัน = นับรวมหลาย instance ไม่ได้)', v_hits;
  end if;

  -- ครั้งที่สี่ต้องเกินเพดาน
  select * into v_r from request_rate_hit(v_key, 3, 60);
  if v_r.allowed then
    raise exception 'TEST 223 ล้มเหลว: ยิงครั้งที่ 4 ยังผ่านทั้งที่เพดานคือ 3';
  end if;
  if v_r.retry_after_secs <= 0 then
    raise exception 'TEST 223 ล้มเหลว: ถูกปฏิเสธแต่ไม่บอกว่าต้องรออีกนานเท่าไร '
      '(ผู้ใช้จริงที่ติดร่างแหจะไม่รู้ว่าต้องรอแค่ไหน)';
  end if;

  raise notice 'TEST 223 ผ่าน — ตัวนับอยู่รอดข้ามทรานแซกชัน · ครั้งที่ 4 ถูกปฏิเสธ รออีก % วินาที',
    v_r.retry_after_secs;
end $$;
rollback;

-- ── TEST 224 ───────────────────────────────────────────────────────
-- เกินเพดานแล้วต้องไม่ raise และตัวนับต้องไม่หายไป
-- ═══════════════════════════════════════════════════════════════════
begin;
do $$
declare
  v_key bytea := sha256('ทดสอบ-224'::bytea);
begin
  delete from request_rate where bucket_key = v_key;
end $$;
commit;

do $$
declare
  v_key    bytea := sha256('ทดสอบ-224'::bytea);
  v_r      record;
  v_raised boolean := false;
  v_i      integer;
begin
  begin
    for v_i in 1..5 loop
      select * into v_r from request_rate_hit(v_key, 2, 60);
    end loop;
  exception when others then v_raised := true; end;

  if v_raised then
    raise exception 'TEST 224 ล้มเหลว: ฟังก์ชันนับจำนวนครั้ง raise ออกมา '
      '— rollback จะล้างตัวนับทิ้งทุกครั้ง แล้วเดาได้ไม่จำกัด';
  end if;
end $$;

-- อ่านจากทรานแซกชันใหม่ ถ้าฟังก์ชัน raise แถวจะไม่เหลือให้เห็น
do $$
declare
  v_key  bytea := sha256('ทดสอบ-224'::bytea);
  v_hits integer;
begin
  select coalesce(sum(hits), 0)::integer into v_hits
    from request_rate where bucket_key = v_key;

  if v_hits <> 5 then
    raise exception 'TEST 224 ล้มเหลว: ยิงไป 5 ครั้งแต่ตัวนับเหลือ % '
      '(ครั้งที่ถูกปฏิเสธต้องถูกนับด้วย มิฉะนั้นยิงรัวได้ไม่จำกัด)', v_hits;
  end if;

  delete from request_rate where bucket_key = v_key;
  raise notice 'TEST 224 ผ่าน — ไม่ raise และครั้งที่ถูกปฏิเสธถูกนับครบทั้ง 5 ครั้ง';
end $$;

-- ── TEST 225 ───────────────────────────────────────────────────────
-- app_runtime เขียนตารางตรง ๆ ไม่ได้ ต้องผ่านฟังก์ชันเท่านั้น
--
-- ถ้าเขียนตรงได้ ใครที่ยิง SQL ได้จะตั้งตัวนับของตัวเองเป็นศูนย์ได้ตลอด
-- ซึ่งทำให้ตัวจำกัดคำขอไม่มีผลกับคนที่ต้องกันที่สุด
-- ═══════════════════════════════════════════════════════════════════
begin;
set local role app_runtime;
select set_config('app.institution_id', '11111111-1111-1111-1111-111111111111', true) as a,
       set_config('app.role', 'teacher', true) as b \gset ctx_

do $$
declare
  v_key   bytea := sha256('ทดสอบ-225'::bytea);
  v_r     record;
  v_wrote text[] := '{}';
  v_seen  integer;
  v_n     integer;
begin
  -- เรียกผ่านฟังก์ชันต้องได้
  select * into v_r from request_rate_hit(v_key, 5, 60);
  if not v_r.allowed then
    raise exception 'TEST 225 ล้มเหลว: เรียกฟังก์ชันในบริบทผู้ใช้จริงไม่ได้';
  end if;

  begin
    insert into request_rate (bucket_key, window_start, hits) values (v_key, now(), 0);
    v_wrote := array_append(v_wrote, 'เพิ่มแถวเอง');
  exception when others then null; end;

  begin
    update request_rate set hits = 0;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'ตั้งตัวนับเป็นศูนย์'); end if;
  exception when others then null; end;

  begin
    delete from request_rate;
    get diagnostics v_n = row_count;
    if v_n > 0 then v_wrote := array_append(v_wrote, 'ลบตัวนับทิ้ง'); end if;
  exception when others then null; end;

  if array_length(v_wrote, 1) > 0 then
    raise exception 'TEST 225 ล้มเหลว: บทบาทของแอปแก้ตัวนับเองได้ (%)',
      array_to_string(v_wrote, ' · ');
  end if;

  -- ครูอ่านไม่เห็น (นโยบายเปิดให้เฉพาะผู้ดูแล) แต่ผู้ดูแลต้องเห็น
  select count(*) into v_seen from request_rate;
  if v_seen <> 0 then
    raise exception 'TEST 225 ล้มเหลว: ครูอ่านตัวนับของทุกคนได้ % แถว', v_seen;
  end if;

  perform set_config('app.role', 'admin', true);
  select count(*) into v_seen from request_rate;
  if v_seen = 0 then
    raise exception 'TEST 225 ล้มเหลว: ผู้ดูแลอ่านตัวนับไม่ได้เลย '
      '(ต้องดูได้ว่าใครถูกจำกัดอยู่ตอนระบบมีปัญหา)';
  end if;

  raise notice 'TEST 225 ผ่าน — เขียนตรงไม่ได้สักทาง · ครูอ่านไม่เห็น · ผู้ดูแลเห็น % แถว', v_seen;
end $$;
rollback;

do $$ begin raise notice ''; raise notice '════ ทดสอบตัวนับคำขอที่ใช้ร่วมกันครบทุกข้อ ════'; end $$;

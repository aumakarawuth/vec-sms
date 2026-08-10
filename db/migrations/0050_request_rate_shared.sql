-- ═══════════════════════════════════════════════════════════════════
-- 0050_request_rate_shared.sql
--
-- ตัวนับคำขอที่ใช้ร่วมกันทุก instance
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- 0021 ย้ายการนับของ `/auth/login` ลงฐานข้อมูลไปแล้ว เพราะโควตาที่คูณตาม
-- จำนวน instance แปลว่าผู้โจมตีเดารหัสผ่านได้มากกว่าที่ตั้งใจ
--
-- แต่ตัวจำกัดคำขอ **ทั่วไป** ยังนับในหน่วยความจำของโปรเซสอยู่ ซึ่งเป็น
-- ปัญหาเดียวกันทุกประการ เพียงแต่เห็นช้ากว่า — รัน 3 instance แล้วเพดาน
-- จริงกลายเป็นสามเท่าโดยไม่มีอะไรฟ้อง และรีสตาร์ททีเดียวโควตาคืนใหม่หมด
--
-- เรื่องนี้สำคัญกว่าที่ตัวเลขบอก เพราะเส้นทางที่ตั้งเพดานแน่นไว้โดยตั้งใจ
-- คือเส้นทางที่อ่อนไหวที่สุด — `POST /provisioning/institutions` ตั้งไว้
-- 3 ครั้งต่อนาที (ทุกคำขอที่ผ่านสร้างวิทยาลัยใหม่หนึ่งแห่ง) ·
-- `/auth/forgot-password` · การเข้าสู่ระบบของผู้ให้บริการ
-- เพดานพวกนี้ถูกเลือกมาจากผลที่ตามมา ไม่ใช่จากความสะดวก การคูณสามจึงไม่ใช่
-- "หลวมนิดหน่อย" แต่คือเพดานคนละตัวกับที่ตัดสินใจไว้
--
-- ─── ทำไมไม่เก็บทุกคำขอเป็นหนึ่งแถวเหมือน login_attempt ───
-- `login_attempt` เก็บรายครั้งได้เพราะการเข้าสู่ระบบมีไม่กี่ครั้งต่อคน และ
-- ต้องเก็บอยู่แล้วตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26 แต่ตัวนี้นับ**ทุกคำขอ
-- ของทุกเส้นทาง** การเขียนหนึ่งแถวต่อคำขอคือการเพิ่มภาระเขียนเท่าตัวของ
-- ทั้งระบบเพื่อทำสิ่งที่เป็นแค่ตัวเลข — ตัวจำกัดที่ทำให้ระบบล้มเสียเอง
-- คือตัวจำกัดที่ใช้ไม่ได้
--
-- จึงเก็บเป็น **ตัวนับต่อหน้าต่างเวลา** หนึ่งแถวต่อ (ถัง, หน้าต่าง)
-- แล้วประมาณค่าแบบหน้าต่างเลื่อนจากสองหน้าต่างที่ติดกัน (วิธีเดียวกับที่
-- CDN ใช้) — แม่นพอสำหรับการจำกัดคำขอ และเขียนแค่ครั้งเดียวต่อคำขอ
--
-- ─── ทำไมคีย์เป็นค่าแฮช ไม่ใช่ไอพีตรง ๆ ───
-- ไอพีเป็นข้อมูลส่วนบุคคลตาม PDPA หลักเดียวกับ `login_attempt.ip_hash`
-- ที่ใช้ IP_HASH_SECRET อยู่แล้ว — ยังนับได้เหมือนเดิมแต่ย้อนกลับไม่ได้
-- ═══════════════════════════════════════════════════════════════════
begin;

create table request_rate (
  bucket_key   bytea       not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket_key, window_start)
);

comment on table request_rate is
  'ตัวนับคำขอต่อหน้าต่างเวลา ใช้ร่วมกันทุก instance — คีย์เป็นค่าแฮชของไอพีกับเส้นทาง';
comment on column request_rate.bucket_key is
  'sha256(IP_HASH_SECRET : ไอพี | เมท็อด | เส้นทาง) — ย้อนกลับเป็นไอพีจริงไม่ได้';

-- ล้างของเก่าด้วยดัชนีนี้ ไม่ใช่สแกนทั้งตาราง
create index request_rate_window_idx on request_rate (window_start);

-- ตารางนี้ไม่มี institution_id โดยตั้งใจ — ตัวจำกัดคำขอทำงาน**ก่อน**รู้ว่า
-- ผู้เรียกเป็นใครและอยู่วิทยาลัยไหน (นั่นคือหน้าที่ของมัน) การผูกกับวิทยาลัย
-- จะทำให้กันคำขอที่ยังไม่ผ่านการยืนยันตัวตนไม่ได้เลย ซึ่งคือคำขอที่ต้องกัน
alter table request_rate enable row level security;
alter table request_rate force row level security;

-- ─── ทำไมมีนโยบายอ่านอย่างเดียว ไม่มีนโยบายเขียนเลย ───
-- ไม่มีนโยบาย insert/update/delete แปลว่าไม่มีใครเขียนตารางนี้ได้ผ่าน SQL
-- ตรง ๆ เลยสักบทบาท เหลือทางเดียวคือ `request_rate_hit()` ซึ่งเป็น
-- security definer
--
-- **ห้ามพึ่ง GRANT เพียงอย่างเดียวในเรื่องนี้** — `db/deploy/roles.sql`
-- ให้สิทธิ์ `insert, update, delete on all tables` กับ app_runtime แบบเหมารวม
-- ตารางใหม่ทุกตารางจึงได้สิทธิ์เขียนมาโดยอัตโนมัติ การ "ไม่ GRANT"
-- ในไฟล์นี้จึงไม่มีผลอะไรเลย RLS คือชั้นที่กันจริง (TEST 225 ยิงทั้ง
-- insert · update · delete เพื่อยืนยันข้อนี้ ไม่ใช่เชื่อตามที่เขียนไว้)
--
-- ส่วนสิทธิ์อ่านเปิดให้ผู้ดูแลไว้ดูว่าใครถูกจำกัดอยู่ตอนระบบมีปัญหา
create policy request_rate_admin_read on request_rate
  for select using (current_app_role() in ('admin', 'director'));

-- ───────────────────────────────────────────────────────────────────
-- นับหนึ่งครั้งแล้วบอกว่าผ่านหรือไม่
--
-- ─── ทำไมไม่ raise เมื่อเกินเพดาน ───
-- ฟังก์ชันที่นับจำนวนครั้งห้าม raise เด็ดขาด เพราะ rollback จะล้างตัวนับ
-- ที่เพิ่งเขียนทิ้งไปด้วย แล้วผู้โจมตีจะยิงได้ไม่จำกัดโดยที่ระบบยังตอบ
-- ปฏิเสธถูกต้องทุกครั้ง (เคยเจอกับ MFA มาแล้ว) ชั้น API เป็นคนโยน
-- และต้องโยน **นอก** ทรานแซกชันด้วย
--
-- ─── ทำไม security definer ───
-- ตัวจำกัดคำขอทำงานก่อน AuthGuard จึงไม่มี app.role และ app.institution_id
-- ให้ RLS ใช้เลยสักตัว การเรียกแบบไม่มีบริบทจึงต้องข้ามผ่านนโยบาย
-- นี่ไม่ใช่การใช้ security definer เพื่อเลี่ยงนโยบายของตาราง (ซึ่งห้ามไว้)
-- แต่เป็นตารางที่อยู่นอกขอบเขตวิทยาลัยตั้งแต่ต้น เหมือน login_role_for()
-- ที่ต้อง definer เพราะบริบทตอนล็อกอินยังไม่มีผู้ใช้
-- ───────────────────────────────────────────────────────────────────
create or replace function request_rate_hit(
  p_bucket_key  bytea,
  p_limit       integer,
  p_window_secs integer
) returns table (
  allowed          boolean,
  remaining        integer,
  retry_after_secs integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now     timestamptz := clock_timestamp();
  v_win     interval;
  v_start   timestamptz;
  v_prev    integer;
  v_cur     integer;
  v_elapsed numeric;
  v_est     numeric;
begin
  if p_window_secs is null or p_window_secs < 1 then
    p_window_secs := 60;
  end if;
  v_win := make_interval(secs => p_window_secs);

  -- ตัดเวลาให้ลงหน้าต่างเดียวกันทุก instance — ถ้าแต่ละเครื่องเริ่มนับ
  -- หน้าต่างของตัวเองตามเวลาที่คำขอแรกมาถึง ตัวนับจะไม่มีวันตรงกัน
  v_start := to_timestamp(
    floor(extract(epoch from v_now) / p_window_secs) * p_window_secs);

  select r.hits into v_prev
    from request_rate r
   where r.bucket_key = p_bucket_key
     and r.window_start = v_start - v_win;

  insert into request_rate as r (bucket_key, window_start, hits)
  values (p_bucket_key, v_start, 1)
  on conflict (bucket_key, window_start)
    do update set hits = r.hits + 1
  returning r.hits into v_cur;

  -- ประมาณแบบหน้าต่างเลื่อน — ยิ่งเข้าใกล้ปลายหน้าต่าง น้ำหนักของหน้าต่าง
  -- ก่อนหน้ายิ่งน้อยลง ถ้าใช้หน้าต่างตายตัวเฉย ๆ ผู้เรียกจะยิงได้สองเท่า
  -- ของเพดานตรงรอยต่อ (เต็มโควตาท้ายหน้าต่างหนึ่ง แล้วเต็มอีกรอบทันที
  -- ที่ข้ามไปหน้าต่างถัดไป)
  v_elapsed := extract(epoch from v_now - v_start) / p_window_secs;
  v_est     := coalesce(v_prev, 0) * (1 - v_elapsed) + v_cur;

  allowed          := v_est <= p_limit;
  remaining        := greatest(p_limit - ceil(v_est)::integer, 0);
  retry_after_secs := case
                        when v_est <= p_limit then 0
                        else greatest(
                               ceil(extract(epoch from
                                 (v_start + v_win) - v_now))::integer, 1)
                      end;

  -- เก็บกวาดแบบสุ่ม ~1 ใน 1000 คำขอ
  --
  -- ทำในฟังก์ชันแทนที่จะเป็นงานประจำวัน เพราะตารางนี้โตเร็วกว่าตารางอื่น
  -- หลายเท่า (หนึ่งแถวต่อไอพีต่อเส้นทางต่อหน้าต่าง) การรอถึงเที่ยงคืน
  -- แปลว่ามีช่วงที่ตารางใหญ่เกินจำเป็นทั้งวัน ส่วนการล้างทุกคำขอก็เปลือง
  -- เปล่า ๆ เพราะแถวเดียวกันถูกล้างซ้ำไม่ได้อยู่แล้ว
  if random() < 0.001 then
    delete from request_rate r2
     where r2.window_start < v_now - (v_win * 3);
  end if;

  return next;
end $$;

comment on function request_rate_hit(bytea, integer, integer) is
  'นับคำขอหนึ่งครั้งแล้วคืนสถานะ — ไม่ raise เพราะ rollback จะล้างตัวนับทิ้ง ชั้น API เป็นคนโยนเอง';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'app_runtime') then
    grant select on request_rate to app_runtime;
    grant execute on function request_rate_hit(bytea, integer, integer) to app_runtime;
  end if;
end $$;

commit;

-- ═══════════════════════════════════════════════════════════════════
-- 0021_login_rate_limit.sql
--
-- จำกัดจำนวนครั้งการเข้าสู่ระบบ **รายไอพี**
--
-- ─── ช่องว่างที่ปิดในไฟล์นี้ ───
-- ระบบมีการล็อกบัญชีอยู่แล้ว — ใส่รหัสผิด 5 ครั้ง บัญชีถูกล็อก 15 นาที
-- ซึ่งกันการเดารหัสผ่านของ "บัญชีหนึ่ง" ได้ดี
--
-- แต่กัน credential stuffing ไม่ได้เลย — ผู้โจมตีที่มีรายชื่อรหัสประจำตัว
-- นักศึกษาทั้งวิทยาลัย (ซึ่งเดาได้จากรูปแบบ 67201010xxx) ลองรหัสผ่านยอดนิยม
-- **หนึ่งตัว** กับ **ทุกบัญชี** จะไม่ทำให้บัญชีไหนถูกล็อกเลยสักบัญชี
-- เพราะแต่ละบัญชีถูกลองแค่ครั้งเดียว แต่ผู้โจมตีได้ลองไปแล้วเป็นพันครั้ง
-- และมักได้บัญชีที่ตั้งรหัสง่าย ๆ ไปอย่างน้อยหนึ่งบัญชีเสมอ
--
-- การนับรายไอพีจึงเป็นคนละมิติกับการล็อกบัญชี ต้องมีทั้งคู่
--
-- ─── ทำไมนับในฐานข้อมูล ไม่ใช่ในหน่วยความจำของโปรเซส ───
-- ตัวนับในหน่วยความจำจะถูกแบ่งตามจำนวน instance — รัน 3 instance
-- แปลว่าผู้โจมตีได้โควตาสามเท่าโดยอัตโนมัติ และรีสตาร์ททีเดียวโควตาก็คืนมาใหม่
-- ตาราง login_attempt เก็บ ip_hash กับ attempted_at ไว้อยู่แล้วตาม
-- พ.ร.บ.คอมพิวเตอร์ มาตรา 26 จึงใช้เป็นตัวนับได้เลยโดยไม่ต้องเพิ่มอะไร
-- ═══════════════════════════════════════════════════════════════════
begin;

alter table auth_policy
  add column if not exists max_ip_attempts    smallint not null default 30,
  add column if not exists ip_window_minutes  smallint not null default 15,
  add column if not exists ip_block_minutes   smallint not null default 30;

comment on column auth_policy.max_ip_attempts is
  'จำนวนครั้งที่ล้มเหลวสูงสุดต่อไอพีในหนึ่งช่วงเวลา — กัน credential stuffing ที่การล็อกบัญชีกันไม่ได้';

-- ดัชนีสำหรับนับรายไอพีในช่วงเวลาย้อนหลัง
-- ต้องมีเพราะทุกคำขอเข้าสู่ระบบจะยิง query นี้ ถ้าสแกนทั้งตารางจะช้าลง
-- เรื่อย ๆ ตามอายุระบบ จนกลายเป็นช่องทาง DoS เสียเอง
create index if not exists login_attempt_ip_window_idx
  on login_attempt (institution_id, ip_hash, attempted_at desc)
  where not succeeded;

-- ───────────────────────────────────────────────────────────────────
-- สถานะของไอพีหนึ่ง ณ ขณะนี้
--
-- คืนค่าแทนที่จะ raise เพราะชั้น API ต้องเอาตัวเลขไปใส่เฮดเดอร์
-- RateLimit-Remaining และ Retry-After ให้ผู้เรียกรู้ว่าเหลือกี่ครั้ง
-- และรออีกนานเท่าไร การ raise อย่างเดียวทำให้บอกไม่ได้
-- ───────────────────────────────────────────────────────────────────
create or replace function login_rate_status(
  p_institution_id uuid,
  p_ip_hash        bytea
) returns table (
  recent_failures  integer,
  max_attempts     integer,
  remaining        integer,
  blocked          boolean,
  retry_after_secs integer
)
language plpgsql stable as $$
declare
  v_max     smallint;
  v_window  smallint;
  v_block   smallint;
  v_oldest  timestamptz;
begin
  select coalesce(ap.max_ip_attempts, 30),
         coalesce(ap.ip_window_minutes, 15),
         coalesce(ap.ip_block_minutes, 30)
    into v_max, v_window, v_block
    from auth_policy ap where ap.institution_id = p_institution_id;

  -- สถานศึกษาที่ยังไม่ได้ตั้งนโยบายใช้ค่าเริ่มต้น ไม่ใช่ปล่อยผ่าน
  -- ค่าเริ่มต้นที่ปลอดภัยสำคัญกว่าความสะดวกตอนตั้งระบบใหม่
  v_max    := coalesce(v_max, 30);
  v_window := coalesce(v_window, 15);
  v_block  := coalesce(v_block, 30);

  if p_ip_hash is null then
    -- ไม่รู้ไอพี (เช่นเรียกจากภายในเครื่อง) ไม่นับ แต่ก็ไม่ปลดล็อกให้ใคร
    return query select 0, v_max::integer, v_max::integer, false, 0;
    return;
  end if;

  select count(*)::integer, min(la.attempted_at)
    into recent_failures, v_oldest
    from login_attempt la
   where la.institution_id = p_institution_id
     and la.ip_hash        = p_ip_hash
     and not la.succeeded
     and la.attempted_at > now() - make_interval(mins => v_window);

  max_attempts     := v_max;
  remaining        := greatest(v_max - recent_failures, 0);
  blocked          := recent_failures >= v_max;
  retry_after_secs := case
                        when recent_failures >= v_max
                        then greatest(
                               extract(epoch from
                                 (v_oldest + make_interval(mins => v_block)) - now())::integer,
                               1)
                        else 0
                      end;
  return next;
end $$;

comment on function login_rate_status(uuid, bytea) is
  'สถานะการจำกัดจำนวนครั้งรายไอพี — คืนค่าให้ชั้น API เอาไปใส่เฮดเดอร์ RateLimit ไม่ใช่ raise ทิ้ง';

commit;

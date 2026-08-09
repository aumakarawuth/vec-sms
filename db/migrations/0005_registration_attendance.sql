-- ═══════════════════════════════════════════════════════════════════
-- 0005_registration_attendance.sql
-- กลุ่มเรียน · การลงทะเบียน · การเช็คชื่อ · กฎเวลาเรียน 80%
--
-- หัวใจของไฟล์นี้คือกฎเวลาเรียน
-- ตามระเบียบ ปวช./ปวส. นักศึกษาต้องมีเวลาเรียนไม่ต่ำกว่า 80% ของรายวิชา
-- จึงมีสิทธิ์เข้ารับการประเมินสรุปผล ต่ำกว่านั้นจะได้ ข.ร. ซึ่งเท่ากับ 0
-- ระบบต้องคำนวณตัวเลขนี้ตลอดเวลา ไม่ใช่ตอนปลายภาค เพราะการเตือนล่วงหน้า
-- คือกลไกป้องกันการออกกลางคันที่ได้ผลที่สุด
--
-- นโยบายเวลาเรียนถูกตรึงไว้ที่กลุ่มเรียนตั้งแต่วันเปิดภาค การแก้นโยบาย
-- กลางภาคจึงไม่ย้อนไปเปลี่ยนผลของกลุ่มที่เปิดไปแล้ว
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- นโยบายเวลาเรียน — ตั้งค่าได้เอง เพราะแต่ละสถานศึกษาตีความไม่เหมือนกัน
-- โดยเฉพาะเรื่อง "ลาป่วยที่มีใบรับรองแพทย์นับเป็นเวลาเรียนหรือไม่"
-- ───────────────────────────────────────────────────────────────────
create table attendance_policy (
  id                     uuid          primary key default gen_random_uuid(),
  institution_id         uuid          not null references institution on delete restrict,
  name_th                text          not null,
  effective_from_year_be smallint      not null,
  min_pct                numeric(5,2)  not null default 80.00,  -- เกณฑ์ผ่าน
  discretion_floor_pct   numeric(5,2)  not null default 60.00,  -- ต่ำกว่านี้ยื่นคำร้องไม่ได้
  warn_pct               numeric(5,2)  not null default 85.00,  -- เริ่มเตือนที่กี่เปอร์เซ็นต์
  created_at             timestamptz   not null default now(),
  unique (institution_id, effective_from_year_be),
  check (discretion_floor_pct <= min_pct and min_pct <= warn_pct)
);
comment on column attendance_policy.discretion_floor_pct is
  'ระหว่าง discretion_floor_pct ถึง min_pct ให้ยื่นคำร้องเข้าดุลยพินิจสถานศึกษาได้ ต่ำกว่านั้นติด ข.ร. ทันที';

create type attendance_status as enum (
  'present',         -- มาเรียน
  'late',            -- มาสาย
  'leave_sick',      -- ลาป่วย
  'leave_personal',  -- ลากิจ
  'activity',        -- ไปราชการ/ทำกิจกรรมของวิทยาลัย
  'absent'           -- ขาดเรียน
);

-- น้ำหนักของแต่ละสถานะในการคิดเวลาเรียน 1.00 = นับเต็ม, 0 = ไม่นับ
create table attendance_status_weight (
  attendance_policy_id uuid              not null references attendance_policy on delete cascade,
  status               attendance_status not null,
  weight               numeric(3,2)      not null check (weight between 0 and 1),
  primary key (attendance_policy_id, status)
);

-- ───────────────────────────────────────────────────────────────────
-- กลุ่มเรียน
-- ───────────────────────────────────────────────────────────────────
create type delivery_mode as enum ('onsite', 'dvt', 'internship', 'online', 'block');
comment on type delivery_mode is
  'dvt = ทวิภาคี · internship = ฝึกประสบการณ์ · block = เรียนแบบบล็อกคอร์ส ซึ่งอาชีวะบางแห่งใช้';

create table class_section (
  id                    uuid          primary key default gen_random_uuid(),
  institution_id        uuid          not null references institution on delete restrict,
  term_id               uuid          not null references term        on delete restrict,
  course_id             uuid          not null references course      on delete restrict,
  curriculum_version_id uuid          references curriculum_version,
  section_no            text          not null,        -- '1/2'
  teacher_id            uuid          references staff,
  room                  text,
  capacity              smallint      not null default 40,
  delivery_mode         delivery_mode not null default 'onsite',

  -- ตรึงนโยบายเวลาเรียนไว้ตั้งแต่เปิดกลุ่ม
  attendance_policy_id  uuid          not null references attendance_policy on delete restrict,
  planned_periods       smallint      not null,        -- จำนวนคาบทั้งภาคตามแผน ใช้เป็นตัวหาร

  is_locked             boolean       not null default false,
  created_at            timestamptz   not null default now(),
  unique (term_id, course_id, section_no),
  check (planned_periods > 0)
);
create index on class_section (term_id, teacher_id);

comment on column class_section.planned_periods is
  'ตัวหารของเวลาเรียน กำหนดตอนเปิดกลุ่มและห้ามแก้หลังเริ่มภาคเรียน เพราะจะเปลี่ยนผลย้อนหลังของทุกคน';

-- ───────────────────────────────────────────────────────────────────
-- การลงทะเบียน
-- ───────────────────────────────────────────────────────────────────
create type enrollment_status as enum (
  'enrolled',       -- ลงทะเบียนปกติ
  'withdrawn',      -- ถอนรายวิชา (ติด ถ.น.)
  'dropped',        -- ถอนภายในกำหนดเพิ่ม-ถอน ไม่ปรากฏในระเบียน
  'credit_transfer' -- เทียบโอน
);

create table enrollment (
  id                uuid              primary key default gen_random_uuid(),
  student_id        uuid              not null references student      on delete restrict,
  class_section_id  uuid              not null references class_section on delete restrict,
  term_id           uuid              not null references term          on delete restrict,
  status            enrollment_status not null default 'enrolled',
  attempt_no        smallint          not null default 1,   -- เรียนซ้ำครั้งที่เท่าไร
  counts_toward_gpa boolean           not null default true,
  registered_at     timestamptz       not null default now(),
  registered_by     uuid,
  withdrawn_at      timestamptz,
  created_at        timestamptz       not null default now(),
  unique (student_id, class_section_id)
);
create index on enrollment (class_section_id) where status = 'enrolled';
create index on enrollment (student_id, term_id);

comment on column enrollment.counts_toward_gpa is
  'รายวิชาปรับพื้นฐานและรายวิชาเทียบโอนตั้งเป็น false เพราะต้องผ่านแต่ไม่นำมาคิด GPA';

-- ───────────────────────────────────────────────────────────────────
-- คาบเรียนและการเช็คชื่อ
-- ───────────────────────────────────────────────────────────────────
create type meeting_status as enum ('scheduled', 'held', 'cancelled', 'substituted');

create table class_meeting (
  id                uuid           primary key default gen_random_uuid(),
  class_section_id  uuid           not null references class_section on delete cascade,
  meets_on          date           not null,
  period_from       smallint       not null,
  period_to         smallint       not null,
  period_count      smallint generated always as (period_to - period_from + 1) stored,
  status            meeting_status not null default 'scheduled',
  taught_by         uuid           references staff,   -- ครูสอนแทนจะต่างจาก teacher_id ของกลุ่ม
  closed_at         timestamptz,                       -- ปิดคาบแล้ว = ห้ามแก้การเช็คชื่อโดยตรง
  note              text,
  unique (class_section_id, meets_on, period_from),
  check (period_to >= period_from)
);
create index on class_meeting (class_section_id, meets_on);

create type attendance_source as enum ('teacher_web', 'teacher_mobile', 'gate_import', 'guardian_leave', 'system');

create table attendance_record (
  id                 uuid              primary key default gen_random_uuid(),
  class_meeting_id   uuid              not null references class_meeting on delete cascade,
  enrollment_id      uuid              not null references enrollment    on delete cascade,
  status             attendance_status not null,
  source             attendance_source not null default 'teacher_mobile',
  recorded_by        uuid,
  recorded_at        timestamptz       not null default now(),
  captured_at        timestamptz,      -- เวลาที่กดจริงบนเครื่อง กรณีเช็คชื่อออฟไลน์แล้วส่งทีหลัง
  note               text,
  unique (class_meeting_id, enrollment_id)
);
create index on attendance_record (enrollment_id);

comment on column attendance_record.captured_at is
  'เวลาที่ครูกดบนเครื่องขณะออฟไลน์ ต่างจาก recorded_at ที่เป็นเวลาที่ข้อมูลถึงเซิร์ฟเวอร์ ใช้ตรวจสอบย้อนหลังได้';

-- ───────────────────────────────────────────────────────────────────
-- คำนวณเวลาเรียน
-- pct_to_date  = เทียบกับคาบที่สอนไปแล้ว ใช้แสดงผลระหว่างภาค
-- pct_final    = เทียบกับคาบตามแผนทั้งภาค ใช้ตัดสิน ข.ร. ตอนปลายภาค
-- absences_left = ขาดได้อีกกี่คาบก่อนตกเกณฑ์ — ตัวเลขที่แสดงในแอปนักศึกษา
-- ───────────────────────────────────────────────────────────────────
create view v_enrollment_attendance as
with agg as (
  select
    e.id                                   as enrollment_id,
    e.class_section_id,
    cs.planned_periods,
    ap.min_pct,
    ap.warn_pct,
    ap.discretion_floor_pct,
    coalesce(sum(cm.period_count), 0)      as periods_held,
    coalesce(sum(cm.period_count * coalesce(w.weight, 0)), 0) as periods_credited
  from enrollment e
  join class_section     cs on cs.id = e.class_section_id
  join attendance_policy ap on ap.id = cs.attendance_policy_id
  left join class_meeting cm
         on cm.class_section_id = e.class_section_id
        and cm.status = 'held'
  left join attendance_record ar
         on ar.class_meeting_id = cm.id
        and ar.enrollment_id    = e.id
  left join attendance_status_weight w
         on w.attendance_policy_id = cs.attendance_policy_id
        and w.status               = ar.status
  where e.status = 'enrolled'
  group by e.id, e.class_section_id, cs.planned_periods,
           ap.min_pct, ap.warn_pct, ap.discretion_floor_pct
)
select
  enrollment_id,
  class_section_id,
  planned_periods,
  periods_held,
  periods_credited,

  -- เทียบกับคาบที่สอนไปแล้ว — ตัวเลขที่แสดงให้นักศึกษาเห็นระหว่างภาค
  case when periods_held = 0 then null
       else round(periods_credited * 100.0 / periods_held, 2) end   as pct_to_date,

  -- เทียบกับคาบตามแผนทั้งภาค — ตัวเลขทางการที่ใช้ตัดสิน ข.ร. ตอนปลายภาค
  round(periods_credited * 100.0 / planned_periods, 2)              as pct_final,

  -- ถ้าเข้าเรียนครบทุกคาบที่เหลือจะจบภาคที่กี่เปอร์เซ็นต์
  -- ใช้ตัดสินสถานะระหว่างภาค เพราะ pct_final กลางเทอมจะต่ำเสมอโดยธรรมชาติ
  round((periods_credited + (planned_periods - periods_held)) * 100.0 / planned_periods, 2)
                                                                    as pct_projected,

  -- ขาดได้อีกกี่คาบก่อนตกเกณฑ์ (ปัดลง ไม่เคยแสดงค่าติดลบ)
  greatest(
    floor(periods_credited + (planned_periods - periods_held)
          - (planned_periods * min_pct / 100.0)),
    0
  )::int                                                            as absences_left,

  min_pct,
  warn_pct,
  discretion_floor_pct,

  case
    -- เข้าเรียนครบทุกคาบที่เหลือก็ยังต่ำกว่าเกณฑ์ดุลยพินิจ = หมดสิทธิ์แน่นอนแล้ว
    when round((periods_credited + (planned_periods - periods_held)) * 100.0 / planned_periods, 2)
         < discretion_floor_pct then 'failed'
    -- เข้าครบที่เหลือก็ยังไม่ถึง 80% = ต้องยื่นคำร้องเข้าดุลยพินิจ
    when round((periods_credited + (planned_periods - periods_held)) * 100.0 / planned_periods, 2)
         < min_pct then 'discretion'
    -- ยังกู้คืนได้แต่เริ่มน่าเป็นห่วง = จุดที่ระบบเริ่มเตือน
    when periods_held > 0
     and round(periods_credited * 100.0 / periods_held, 2) < warn_pct then 'warning'
    else 'ok'
  end                                                               as attendance_state
from agg;

comment on view v_enrollment_attendance is
  'แหล่งความจริงเดียวของเวลาเรียน ทั้งแอปนักศึกษา หน้าบันทึกคะแนน และการตัดเกรด ต้องอ่านจากมุมมองนี้เท่านั้น';

commit;

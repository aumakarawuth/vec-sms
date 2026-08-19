-- ═══════════════════════════════════════════════════════════════════
-- 0070_clubs.sql
--
-- วิชาชุมนุม/ชมรม — บันทึกพื้นฐาน (ชื่อชมรม ผู้ดูแล สมาชิก)
--
-- ─── ทำไมยังไม่ผูกกับเกณฑ์จบ ───
-- `graduation_rule.kind = 'cocurricular_all_terms'` ("กิจกรรมเสริมหลักสูตร
-- ผ่านทุกภาคเรียน") มีอยู่แล้วในหลักสูตรทุกฉบับ แต่การผูกชมรมเข้ากับเกณฑ์นั้น
-- ต้องตัดสินใจเพิ่มว่า "เข้าร่วม" กับ "ผ่าน" ต่างกันยังไง (มาไม่ครบทุกครั้ง
-- นับว่าผ่านไหม) ซึ่งเป็นคนละงานกับการมีที่บันทึกชื่อชมรมกับสมาชิกก่อน —
-- ผูกคะแนน/หน่วยกิตทีหลังเมื่อรู้กติกาจริงของวิทยาลัย ไม่งั้นเดาเกณฑ์เอง
-- แล้วเกณฑ์จบใช้ตัวเลขที่เดามาโดยไม่มีใครสั่ง
-- ═══════════════════════════════════════════════════════════════════
begin;

create table club (
  id             uuid        primary key default gen_random_uuid(),
  institution_id uuid        not null references institution on delete restrict,
  code           text        not null,
  name_th        text        not null,
  category_th    text,                        -- เช่น "กีฬา" "วิชาการ" "ศิลปะ" — ข้อความอิสระ ไม่ตรึงเป็น enum
  advisor_staff_id uuid      references staff on delete set null,
  description_th text,
  active         boolean     not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (institution_id, code)
);
create index on club (institution_id) where active;

comment on table club is
  'ชมรม/วิชาชุมนุม — บันทึกพื้นฐาน ยังไม่ผูกกับเกณฑ์จบหรือหน่วยกิตกิจกรรม (ดูคอมเมนต์บนไฟล์)';

create table club_member (
  id          uuid        primary key default gen_random_uuid(),
  club_id     uuid        not null references club on delete cascade,
  student_id  uuid        not null references student on delete cascade,
  academic_year_id uuid   not null references academic_year on delete restrict,
  role        text        not null default 'member',   -- 'member' | 'leader'
  joined_on   date        not null default current_date,
  left_on     date,
  created_at  timestamptz not null default now(),
  unique (club_id, student_id, academic_year_id)
);
create index on club_member (student_id);

comment on column club_member.academic_year_id is
  'ชมรมสมัครใหม่ทุกปีการศึกษา — คนเดิมที่สมัครซ้ำปีถัดไปนับเป็นสมาชิกใหม่ของปีนั้น ไม่ใช่แถวเดิมที่ยังค้าง';

-- set_updated_at() มีมาตั้งแต่ 0001 — ใช้ตัวเดิม ไม่ประกาศซ้ำ
create trigger club_touch before update on club
  for each row execute function set_updated_at();

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security
-- ───────────────────────────────────────────────────────────────────
alter table club enable row level security;
alter table club force  row level security;

create policy tenant_isolation on club
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy club_write on club
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_update on club
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_delete on club
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

alter table club_member enable row level security;
alter table club_member force  row level security;

create policy tenant_isolation on club_member
  using (student_institution(club_member.student_id) = current_institution_id())
  with check (student_institution(club_member.student_id) = current_institution_id());

-- อ่านได้: บทบาทระดับวิทยาลัย, ครู (ดูของนักศึกษาที่ตัวเองดูแล/สอนไม่ได้แยกในนี้
-- เพราะสมาชิกชมรมไม่ใช่ข้อมูลอ่อนไหว), เจ้าตัวเอง, ผู้ปกครองที่ยืนยันแล้ว
create policy club_member_scope on club_member
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or club_member.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = club_member.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null)
  );

create policy club_member_write on club_member
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_member_update on club_member
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));
create policy club_member_delete on club_member
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','student_affairs','director','admin']));

grant select, insert, update, delete on club, club_member to app_runtime;

commit;

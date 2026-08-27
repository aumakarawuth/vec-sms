begin;

-- ห้องประจำชั้นเป็นคนละสิ่งกับ room (ห้องกายภาพในตารางสอน):
-- ห้องประจำชั้นต้องสร้างได้ก่อนมีนักศึกษา แล้วจึงค่อยจัดรายชื่อเข้าห้องภายหลัง
create table class_group (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institution on delete restrict,
  academic_year_id uuid not null references academic_year on delete restrict,
  level qualification_level not null,
  study_year smallint not null check (study_year between 1 and 6),
  code text not null,
  cohort text,
  finance_group_th text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, academic_year_id, level, study_year, code)
);
create index on class_group (academic_year_id) where active;
create trigger class_group_touch before update on class_group for each row execute function set_updated_at();

create table class_group_advisor (
  class_group_id uuid not null references class_group on delete cascade,
  staff_id uuid not null references staff on delete restrict,
  primary key (class_group_id, staff_id)
);

alter table class_group enable row level security;
alter table class_group force row level security;
create policy tenant_isolation on class_group using (institution_id = current_institution_id()) with check (institution_id = current_institution_id());
create policy class_group_write on class_group as restrictive for all using (current_app_role() = any (array['registrar','academic','director','admin'])) with check (current_app_role() = any (array['registrar','academic','director','admin']));

alter table class_group_advisor enable row level security;
alter table class_group_advisor force row level security;
create policy tenant_isolation on class_group_advisor using (exists (select 1 from class_group cg where cg.id = class_group_advisor.class_group_id and cg.institution_id = current_institution_id())) with check (exists (select 1 from class_group cg where cg.id = class_group_advisor.class_group_id and cg.institution_id = current_institution_id()));
create policy class_group_advisor_write on class_group_advisor as restrictive for all using (current_app_role() = any (array['registrar','academic','director','admin'])) with check (current_app_role() = any (array['registrar','academic','director','admin']));

commit;

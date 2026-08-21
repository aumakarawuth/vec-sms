-- ═══════════════════════════════════════════════════════════════════
-- 0071_national_exam_results.sql
--
-- ผลสอบ O-NET/V-NET — ตารางแบบทั่วไปก่อน ยังไม่ได้เทียบกับรูปแบบไฟล์จริง
-- ที่ สอศ./สทศ. ส่งมา (หลักการเดียวกับ PVRS ก่อนยืนยันรูปแบบ — ดู
-- pvrs_rows() และคอมเมนต์ formatConfirmed ใน CLAUDE.md) รหัสวิชาและชื่อวิชา
-- จึงเป็นข้อความอิสระ ไม่ตรึงเป็น enum หรือตารางอ้างอิง เพราะยังไม่รู้ชุด
-- วิชาที่แน่นอนของไฟล์จริง (O-NET กับ V-NET มีจำนวนและชื่อวิชาต่างกัน)
--
-- ─── ทำไม on conflict do update ไม่ใช่ all-or-nothing แบบ apply_student_import ───
-- คะแนนแต่ละแถวเป็นของนักศึกษาคนละคน ไม่ใช่ชุดข้อมูลเดียวที่ต้องครบถ้วน
-- ด้วยกัน (ต่างจากประวัติการเรียนเดิมที่ทุกแถวเป็นของ "รอบนำเข้า" เดียว
-- ที่ต้องตามรอยได้) แถวหนึ่งพิมพ์รหัสนักศึกษาผิดไม่ควรทำให้อีกสามสิบเก้าคน
-- ที่ถูกต้องบันทึกไม่ได้ไปด้วย — หลักเดียวกับ register_courses_bulk()
-- ═══════════════════════════════════════════════════════════════════
begin;

create table national_exam_result (
  id             uuid          primary key default gen_random_uuid(),
  institution_id uuid          not null references institution on delete restrict,
  student_id     uuid          not null references student on delete cascade,
  exam_kind      text          not null default 'onet',   -- 'onet' | 'vnet' — ข้อความอิสระ เผื่อมีชนิดอื่นภายหลัง
  exam_year_be   smallint      not null check (exam_year_be between 2500 and 2700),
  subject_code   text          not null,
  subject_th     text          not null,
  score          numeric(5,2)  not null check (score >= 0 and score <= 100),
  created_at     timestamptz   not null default now(),
  updated_at     timestamptz   not null default now(),
  unique (student_id, exam_kind, exam_year_be, subject_code)
);
create index on national_exam_result (institution_id, exam_kind, exam_year_be);

comment on table national_exam_result is
  'ผลสอบระดับชาติ (O-NET/V-NET) — โครงตารางทั่วไป ยังไม่เทียบกับรูปแบบไฟล์จริงที่หน่วยงานส่งมา';

create trigger national_exam_result_touch before update on national_exam_result
  for each row execute function set_updated_at();

-- ───────────────────────────────────────────────────────────────────
-- บันทึกผลเป็นกลุ่ม — รายวิชา/รายคนที่ผิดไม่ทำให้ทั้งชุดล้ม
--
-- คืนผลรายแถว (status/detail) แทนการ raise เหตุผลเดียวกับ
-- register_courses_bulk() — ไฟล์ผลสอบมีเป็นร้อยแถว แถวเดียวพิมพ์รหัส
-- นักศึกษาผิดต้องไม่ทำให้อีกร้อยแถวที่ถูกบันทึกไม่ได้
-- ───────────────────────────────────────────────────────────────────
create or replace function record_onet_results_bulk(p_rows jsonb)
returns table (row_no integer, student_code text, subject_code text, status text, detail text)
language plpgsql as $$
-- คอลัมน์ที่คืนออกไป (student_code, subject_code) ซ้ำชื่อกับคอลัมน์จริงใน
-- student/national_exam_result — สั่งให้ WHERE ตีความเป็นคอลัมน์เสมอ
-- (รูปแบบเดียวกับ register_courses_bulk ใน 0026)
#variable_conflict use_column
declare
  r         jsonb;
  v_idx     integer := 0;
  v_inst    uuid := current_institution_id();
  v_student uuid;
  v_code    text;
  v_kind    text;
  v_year    text;
  v_subject_code text;
  v_subject_th   text;
  v_score   text;
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    v_idx := v_idx + 1;
    v_code := nullif(btrim(r->>'studentCode'), '');
    v_kind := coalesce(nullif(btrim(r->>'examKind'), ''), 'onet');
    v_year := r->>'examYearBe';
    v_subject_code := nullif(btrim(r->>'subjectCode'), '');
    v_subject_th   := nullif(btrim(r->>'subjectTh'), '');
    v_score := r->>'score';

    begin
      if v_code is null then
        raise exception 'ไม่มีรหัสนักศึกษา';
      end if;
      select id into v_student from student
       where institution_id = v_inst and student_code = v_code;
      if v_student is null then
        raise exception 'ไม่พบนักศึกษารหัส %', v_code;
      end if;
      if v_subject_code is null or v_subject_th is null then
        raise exception 'ไม่มีรหัสหรือชื่อวิชา';
      end if;
      if v_year !~ '^\d{4}$' then
        raise exception 'ปีที่สอบต้องเป็นพุทธศักราชสี่หลัก';
      end if;
      if v_score !~ '^\d+(\.\d+)?$' or v_score::numeric < 0 or v_score::numeric > 100 then
        raise exception 'คะแนนต้องเป็นตัวเลข 0-100';
      end if;

      insert into national_exam_result
        (institution_id, student_id, exam_kind, exam_year_be, subject_code, subject_th, score)
      values (v_inst, v_student, v_kind, v_year::smallint, v_subject_code, v_subject_th, v_score::numeric)
      on conflict (student_id, exam_kind, exam_year_be, subject_code)
      do update set subject_th = excluded.subject_th, score = excluded.score, updated_at = now();

      row_no := v_idx; student_code := v_code; subject_code := v_subject_code;
      status := 'saved'; detail := null;
      return next;
    exception
      when others then
        row_no := v_idx; student_code := v_code; subject_code := v_subject_code;
        status := 'error'; detail := sqlerrm;
        return next;
    end;
  end loop;
end $$;

comment on function record_onet_results_bulk(jsonb) is
  'บันทึกผลสอบ O-NET/V-NET เป็นกลุ่ม คืนผลรายแถว — แถวที่ผิดไม่ทำให้แถวอื่นบันทึกไม่ได้ (หลักเดียวกับ register_courses_bulk)';

-- ───────────────────────────────────────────────────────────────────
-- Row-Level Security — รูปแบบเดียวกับ prior_academic_record (0023/0044)
-- ───────────────────────────────────────────────────────────────────
alter table national_exam_result enable row level security;
alter table national_exam_result force  row level security;

create policy tenant_isolation on national_exam_result
  using (institution_id = current_institution_id())
  with check (institution_id = current_institution_id());

create policy national_exam_result_scope on national_exam_result
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or national_exam_result.student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = national_exam_result.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_grades)
  );

create policy national_exam_result_write on national_exam_result
  as restrictive for insert
  with check (current_app_role() = any (array['registrar','academic','director','admin']));
create policy national_exam_result_update on national_exam_result
  as restrictive for update
  using (true)
  with check (current_app_role() = any (array['registrar','academic','director','admin']));
create policy national_exam_result_delete on national_exam_result
  as restrictive for delete
  using (current_app_role() = any (array['registrar','academic','director','admin']));

commit;

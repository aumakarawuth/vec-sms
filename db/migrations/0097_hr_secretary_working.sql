-- ═══════════════════════════════════════════════════════════════════
-- 0097_hr_secretary_working.sql
-- ทำให้บทบาทงานบุคคล (hr) และเลขา (secretary) ใช้งานได้จริง — และปิดช่องที่
-- เจอระหว่างทาง
--
-- ─── ที่มา ───
-- 0095 เพิ่มสองบทบาทแต่เปิดได้แค่ "อ่าน" (TEST 340/341 เฝ้าเฉพาะ "ไม่เกินสิทธิ์")
-- งานบุคคลจึงแก้ระเบียน ทช.1 · โครงสร้างหน่วยงาน · ตัดสินใบลาไม่ได้ ส่วนเลขา
-- ถูกนโยบายประกาศที่ยังอ่าน current_app_role() ตัวเดียวกันไว้ทุกครั้งที่มี
-- บทบาทหลักอื่นซ้อน และเปิดหนังสือที่ออกแล้วไม่ได้เลยเพราะ issued_document_scope
--
-- ─── ช่องที่เจอระหว่างทาง (ร้ายแรงกว่าเรื่องที่มาแก้) ───
-- `department` · `staff_assignment` · `staff_attendance` มีแต่ tenant_isolation
-- ตั้งแต่ 0035 — ยิงจริงในบริบท app.role = 'student' แล้ว **สร้างแผนกใหม่ได้ ·
-- แก้ชื่อแผนกทั้งวิทยาลัยได้ · ลงเวลามาทำงานแทนบุคลากรได้** บทเรียนเดียวกับ
-- ข้อ 16/20/25 — ตารางที่ไม่มีหน้าจอให้คนทั่วไปเขียนไม่ได้แปลว่าปิด
--
-- และ `staff_leave` เจ้าของใบแก้แถวของตัวเองได้ (ตั้งใจ — ยื่นและยกเลิกเอง)
-- แต่ trigger กันแค่ "ผู้ตัดสินต้องไม่ใช่เจ้าของ" ครูจึงตั้ง status = 'approved'
-- พร้อมใส่ decided_by เป็นรหัสของใครก็ได้ แล้วผ่าน — การอนุมัติปลอมที่ระบุชื่อ
-- ผู้อนุมัติเป็นคนอื่น ตอนนี้การตัดสินใบลาต้องเป็นบทบาทผู้บริหาร/งานบุคคล
--
-- ─── ทำไมเลขายังออกหนังสือใหม่เองไม่ได้ ───
-- issue_student_letter() ไม่ใช่ security definer มันอ่านนักศึกษา ผู้ปกครอง
-- เวลาเรียน และคะแนนความประพฤติด้วยสิทธิ์ของคนกด ถ้าจะให้เลขาออกได้ต้องเปิด
-- ข้อมูลเหล่านั้นทั้งวิทยาลัยให้เลขา ซึ่งเกินหน้าที่ — งานปกครองเป็นคนออก
-- เลขาเปิด/พิมพ์ซ้ำหนังสือที่ออกแล้วได้ (อ่านจาก payload ที่ตรึงไว้ ไม่แตะตารางอื่น)
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace function hr_writer() returns boolean
language sql stable as $$
  select is_institution_wide_role() or 'hr' = any (current_app_roles())
$$;
comment on function hr_writer() is
  'ผู้เขียนข้อมูลงานบุคคลได้ — บทบาทระดับวิทยาลัย หรือมีบทบาท hr อยู่ในชุดบทบาท (0097)';

-- ─── 1. ปิดสามตารางที่ใครก็เขียนได้ ───────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['department', 'staff_assignment', 'staff_attendance'] loop
    execute format('create policy %1$I_write_insert on %1$I as restrictive for insert with check (hr_writer())', t);
    execute format('create policy %1$I_write_update on %1$I as restrictive for update using (hr_writer()) with check (hr_writer())', t);
    execute format('create policy %1$I_write_delete on %1$I as restrictive for delete using (hr_writer())', t);
  end loop;
end $$;

-- ─── 2. งานบุคคลเขียนระเบียน ทช.1 และบุตรบุคลากรได้ ──────────────────
-- แก้ตัว restrictive ของ 0049 เอง ไม่ใช่เพิ่ม permissive ทับ (ทับไม่มีผล — ข้อ 14)
do $$
declare
  t text;
begin
  foreach t in array array['staff_record', 'staff_child'] loop
    execute format('alter policy %1$I_staff_insert on %1$I with check (hr_writer())', t);
    execute format('alter policy %1$I_staff_update on %1$I using (hr_writer()) with check (hr_writer())', t);
    execute format('alter policy %1$I_staff_delete on %1$I using (hr_writer())', t);
  end loop;
end $$;

-- ─── 3. การตัดสินใบลาเป็นของผู้บริหาร/งานบุคคลเท่านั้น ─────────────
-- เจ้าของใบยังยื่นและยกเลิกของตัวเองได้ — แต่แถวผลลัพธ์ต้องไม่มีผู้ตัดสิน
create policy staff_leave_decide on staff_leave
  as restrictive for update
  using (true)
  with check (hr_writer() or (status in ('pending', 'cancelled') and decided_by is null));

create policy staff_leave_submit on staff_leave
  as restrictive for insert
  with check (hr_writer() or (status = 'pending' and decided_by is null));

-- ─── 4. เลขา: ประกาศอ่านชุดบทบาท · เปิดหนังสือถึงผู้ปกครองที่ออกแล้ว ──
alter policy announcement_insert on announcement
  with check (current_app_roles() && array['registrar','academic','student_affairs','director','admin','secretary']);
alter policy announcement_update on announcement
  using (current_app_roles() && array['registrar','academic','student_affairs','director','admin','secretary'])
  with check (current_app_roles() && array['registrar','academic','student_affairs','director','admin','secretary']);
alter policy announcement_delete on announcement
  using (current_app_roles() && array['registrar','academic','student_affairs','director','admin','secretary']);

-- 0095 เปิด insert/update/delete ให้เลขาไว้ ซึ่งรอดมาได้เพราะ scope ด้านล่าง
-- ปิดอยู่ทั้งตาราง พอ scope เปิดให้เห็นหนังสือถึงผู้ปกครอง เลขาจะ insert ใบรับรอง
-- ความประพฤติที่เขียน payload เองได้ตรง ๆ โดยไม่ผ่าน issue_student_letter() —
-- เอกสารทางการปลอมที่แก้/ลบไม่ได้อีกเลย (หลักข้อ 4) จึงคืนเป็นของเดิมก่อนเปิดอ่าน
alter policy issued_document_staff_insert on issued_document
  with check (is_institution_wide_role());
alter policy issued_document_staff_update on issued_document
  using (is_institution_wide_role()) with check (is_institution_wide_role());
alter policy issued_document_staff_delete on issued_document
  using (is_institution_wide_role());

alter policy issued_document_scope on issued_document
  using (
    is_institution_wide_role()
    or ('secretary' = any (current_app_roles())
        and kind in ('absence_notice', 'guardian_invitation', 'conduct_certificate'))
    or exists (select 1 from student s
                where s.id = issued_document.student_id
                  and s.person_id = current_actor_id())
  );

commit;

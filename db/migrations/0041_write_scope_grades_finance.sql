-- ═══════════════════════════════════════════════════════════════════
-- 0041_write_scope_grades_finance.sql
--
-- ปิดช่องที่นักศึกษาเขียนคะแนน เกรดเฉลี่ย สถานะ และหนี้ของตัวเองได้
--
-- ─── อาการที่ทดสอบแล้วเกิดขึ้นจริง ───
-- ตั้งบริบทเป็นนักศึกษาคนหนึ่ง (app.role = 'student') แล้วยิง update ตรง ๆ
-- ที่ชั้นฐานข้อมูล ทุกคำสั่งข้างล่างนี้สำเร็จ ไม่ใช่ถูกกรองเป็นศูนย์แถว
--
--   update gradebook_score   set score  = 100          → ให้คะแนนตัวเอง
--   update term_summary      set gpa    = 4.00         → แก้เกรดเฉลี่ยตัวเอง
--   update student           set status = 'graduated'  → ทำให้ตัวเองจบ
--   update invoice           set status = 'paid'       → ล้างหนี้ตัวเอง
--   update installment       set due_on = +365 วัน     → เลื่อนกำหนดชำระ
--   update enrollment        set status = ...          → แก้สถานะลงทะเบียน
--   delete from student_status_history                 → ลบร่องรอยของตัวเอง
--
-- ─── ต้นเหตุเดิมกับ 0039 ───
-- policy ที่เขียน `using` ไว้แต่ไม่เขียน `with check` PostgreSQL จะเอา
-- `using` **มาใช้เป็น `with check` ให้เอง** ประโยคที่เขียนไว้ให้เจ้าของ
-- **ดู**ของตัวเองได้ จึงกลายเป็นสิทธิ์ **เขียน** ของตัวเองไปด้วยทุกข้อ
--
--   subject_scope        ... or s.person_id = current_actor_id()
--   term_summary_scope   ... or student_id in (select actor_student_ids())
--   gradebook_scope      ... or enrollment_id in (select actor_enrollment_ids())
--
-- ทั้งสามประโยคเขียนไว้ให้นักศึกษาเปิดดูคะแนนและใบแจ้งหนี้ของตัวเอง
-- ซึ่งเป็นสิ่งที่ต้องมี — สิ่งที่ผิดคือมันเปิดทางเขียนไปด้วย
--
-- ─── ทำไมต้องมีนโยบาย for delete แยกทุกตาราง ───
-- `with check` มีผลกับ insert และ update เท่านั้น **delete ไม่มี with check**
-- PostgreSQL ใช้ `using` ตัดสิน delete ล้วน ๆ ถ้าไม่เพิ่มนโยบายเฉพาะ
-- เจ้าของจะยังลบแถวของตัวเองทิ้งได้ ซึ่งมักได้ผลเท่ากับแก้ค่า —
-- ใบแจ้งหนี้ที่หายไปคือหนี้ที่หายไป และคะแนนที่หายไปคือคะแนนที่ไม่เคยมี
--
-- ─── ใครยังต้องเขียนได้บ้าง (ตรวจกับเส้นทางจริงแล้วทุกข้อ) ───
-- · gradebook_score  ครูผู้สอนของรายการคะแนนนั้น — เป็นคนกรอกคะแนนตัวจริง
-- · term_summary     เฉพาะบทบาทระดับวิทยาลัย เพราะ compute_term_summary()
--                    ถูกเรียกจาก POST /gradebook/terms/:id/summary ซึ่งกั้น
--                    ด้วย @Roles('registrar','academic','director','admin')
-- · invoice · invoice_line · installment  งานการเงินและงานทะเบียน
-- · student · enrollment · student_status_history  บทบาทระดับวิทยาลัย
--   (ครูอ่านได้เหมือนเดิมแต่เขียนไม่ได้ — การแก้ทะเบียนนักศึกษาไม่ใช่งานครู)
--
-- ─── ที่เหลืออีก 38 ตาราง ───
-- รูปแบบเดียวกันนี้ยังมีอยู่ในตารางกลุ่มยืนยันตัวตน (user_credential ·
-- mfa_credential · password_reset) ซึ่ง **ต้องให้เจ้าของเขียนได้** เพราะ
-- เจ้าตัวเป็นคนเปลี่ยนรหัสผ่านและตั้ง MFA เอง การปิดตรงนั้นต้องกันรายคอลัมน์
-- ด้วย trigger ไม่ใช่ปิดทั้งแถว จึงเป็นงานคนละก้อนที่ต้องมีเทสต์ของตัวเอง
-- ═══════════════════════════════════════════════════════════════════
begin;

-- ───────────────────────────────────────────────────────────────────
-- คะแนนในสมุดคะแนน — ครูผู้สอนกรอก นักศึกษาดูได้เมื่อครูเผยแพร่แล้ว
--
-- ข้อนี้ร้ายแรงที่สุดในไฟล์ เพราะคะแนนคือที่มาของเกรด และเกรดคือที่มา
-- ของการจบการศึกษา การแก้ที่ต้นทางจึงไหลไปทุกอย่างที่คำนวณต่อจากมัน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists gradebook_scope on gradebook_score;

create policy gradebook_scope on gradebook_score
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1
                 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 join staff st         on st.id = cs.teacher_id
                where gi.id = gradebook_score.gradebook_item_id
                  and st.person_id = current_actor_id())
    -- เจ้าของดูได้เฉพาะรายการที่ครูเผยแพร่แล้ว — อ่านอย่างเดียว
    or (enrollment_id in (select actor_enrollment_ids())
        and exists (select 1 from gradebook_item gi
                     where gi.id = gradebook_score.gradebook_item_id
                       and gi.publish_to_student))
  )
  with check (
    is_institution_wide_role()
    or exists (select 1
                 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 join staff st         on st.id = cs.teacher_id
                where gi.id = gradebook_score.gradebook_item_id
                  and st.person_id = current_actor_id())
  );

create policy gradebook_score_no_owner_delete on gradebook_score
  as restrictive for delete
  using (
    is_institution_wide_role()
    or exists (select 1
                 from gradebook_item gi
                 join class_section cs on cs.id = gi.class_section_id
                 join staff st         on st.id = cs.teacher_id
                where gi.id = gradebook_score.gradebook_item_id
                  and st.person_id = current_actor_id())
  );

comment on policy gradebook_scope on gradebook_score is
  'นักศึกษาดูคะแนนที่ครูเผยแพร่แล้วได้ แต่กรอกและแก้ไม่ได้ — ทดสอบแล้วว่าเดิมตั้ง score = 100 ให้ตัวเองได้';

-- ───────────────────────────────────────────────────────────────────
-- เกรดเฉลี่ยรายภาคและสะสม — คำนวณจากผลการเรียน ไม่ใช่ค่าที่ใครกรอกเอง
-- ───────────────────────────────────────────────────────────────────
drop policy if exists term_summary_scope on term_summary;

create policy term_summary_scope on term_summary
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or student_id in (select actor_student_ids())
    or exists (select 1 from student_guardian sg
                where sg.student_id = term_summary.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_grades)
  )
  -- compute_term_summary() ถูกเรียกจากเส้นทางที่กั้นด้วยบทบาทระดับวิทยาลัย
  -- เท่านั้น ครูจึงไม่ต้องเขียนตารางนี้แม้จะเป็นคนส่งเกรดต้นทาง
  with check (is_institution_wide_role());

create policy term_summary_no_owner_delete on term_summary
  as restrictive for delete
  using (is_institution_wide_role());

comment on policy term_summary_scope on term_summary is
  'เจ้าของและผู้ปกครองที่ได้รับสิทธิ์ดูเกรดเฉลี่ยได้ แต่แก้ไม่ได้ — เดิมนักศึกษาตั้ง gpa = 4.00 ให้ตัวเองได้';

-- ───────────────────────────────────────────────────────────────────
-- ทะเบียนนักศึกษา — สถานะเป็นตัวตัดสินว่ายังเรียนอยู่หรือจบแล้ว
--
-- สถานะยังเป็นตัวคูณของโควตาแพ็กเกจ (0038) ด้วย การแก้สถานะตัวเองจึง
-- กระทบทั้งการจบการศึกษาและยอดที่วิทยาลัยต้องจ่ายผู้ให้บริการ
-- ───────────────────────────────────────────────────────────────────
drop policy if exists subject_scope on student;

create policy subject_scope on student
  as restrictive
  using (
    is_institution_wide_role()
    or current_app_role() = 'teacher'
    or exists (select 1 from person p
                where p.id = student.person_id and p.id = current_actor_id())
    or exists (select 1 from student_guardian sg
                where sg.student_id = student.id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null)
  )
  with check (is_institution_wide_role());

create policy student_no_owner_delete on student
  as restrictive for delete
  using (is_institution_wide_role());

comment on policy subject_scope on student is
  'ครู เจ้าตัว และผู้ปกครองที่ยืนยันแล้วอ่านได้ แต่เขียนได้เฉพาะบทบาทระดับวิทยาลัย — เดิมนักศึกษาตั้งสถานะตัวเองเป็น graduated ได้';

-- ───────────────────────────────────────────────────────────────────
-- ประวัติการเปลี่ยนสถานะ — เขียนโดย trigger บน student
--
-- ลบได้เท่ากับลบหลักฐานว่าเคยพ้นสภาพหรือเคยถูกพักการเรียน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists status_history_scope on student_status_history;

create policy status_history_scope on student_status_history
  as restrictive
  using (
    is_institution_wide_role()
    or student_id in (select actor_student_ids())
  )
  with check (is_institution_wide_role());

create policy status_history_no_owner_delete on student_status_history
  as restrictive for delete
  using (is_institution_wide_role());

-- ───────────────────────────────────────────────────────────────────
-- การลงทะเบียนเรียน
--
-- ครูผู้สอนอ่านได้เพราะต้องเห็นรายชื่อคนในห้อง แต่การเพิ่ม-ถอนรายวิชา
-- เป็นงานทะเบียน ไม่ใช่งานครู
-- ───────────────────────────────────────────────────────────────────
drop policy if exists enrollment_scope on enrollment;

create policy enrollment_scope on enrollment
  as restrictive
  using (
    is_institution_wide_role()
    or exists (select 1 from class_section cs
                 join staff st on st.id = cs.teacher_id
                where cs.id = enrollment.class_section_id
                  and st.person_id = current_actor_id())
    or student_id in (select actor_student_ids())
  )
  with check (is_institution_wide_role());

create policy enrollment_no_owner_delete on enrollment
  as restrictive for delete
  using (is_institution_wide_role());

-- ───────────────────────────────────────────────────────────────────
-- การเงิน — ใบแจ้งหนี้ รายการในใบ และงวดผ่อนชำระ
--
-- ทั้งสามตารางใช้ประโยคเดียวกันคือ "เจ้าของหรือผู้ปกครองที่ได้รับสิทธิ์
-- ดูการเงิน" ซึ่งต้องอ่านได้จริง เพราะหน้าจอยอดค้างชำระของนักศึกษา
-- และผู้ปกครองพึ่งข้อนี้ทั้งหมด — ปิดเฉพาะการเขียน
-- ───────────────────────────────────────────────────────────────────
drop policy if exists subject_scope on invoice;

create policy subject_scope on invoice
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from student s
                where s.id = invoice.student_id and s.person_id = current_actor_id())
    or exists (select 1 from student_guardian sg
                where sg.student_id = invoice.student_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  )
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy invoice_no_owner_delete on invoice
  as restrictive for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

drop policy if exists finance_subject_scope on invoice_line;

create policy finance_subject_scope on invoice_line
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from invoice i
                 join student s on s.id = i.student_id
                where i.id = invoice_line.invoice_id
                  and s.person_id = current_actor_id())
    or exists (select 1 from invoice i
                 join student_guardian sg on sg.student_id = i.student_id
                where i.id = invoice_line.invoice_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  )
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy invoice_line_no_owner_delete on invoice_line
  as restrictive for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

drop policy if exists finance_subject_scope on installment;

create policy finance_subject_scope on installment
  as restrictive
  using (
    current_app_role() in ('finance', 'registrar', 'director', 'admin')
    or exists (select 1 from invoice i
                 join student s on s.id = i.student_id
                where i.id = installment.invoice_id
                  and s.person_id = current_actor_id())
    or exists (select 1 from invoice i
                 join student_guardian sg on sg.student_id = i.student_id
                where i.id = installment.invoice_id
                  and sg.person_id = current_actor_id()
                  and sg.verified_at is not null
                  and sg.can_view_finance)
  )
  with check (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

create policy installment_no_owner_delete on installment
  as restrictive for delete
  using (current_app_role() in ('finance', 'registrar', 'director', 'admin'));

comment on policy subject_scope on invoice is
  'เจ้าของและผู้ปกครองที่ได้รับสิทธิ์ดูยอดค้างชำระได้ แต่แก้ไม่ได้ — เดิมนักศึกษาตั้ง status = paid ให้ตัวเองได้';

commit;

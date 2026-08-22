-- ═══════════════════════════════════════════════════════════════════
-- 0076 — กรรมการคุมสอบที่ไม่ได้สอนวิชานั้นมองไม่เห็นว่าตัวเองคุมสอบอะไร
--
-- ─── เจอตอนทดสอบ API-204 จริง ไม่ใช่ตอนอ่านโค้ด ───
-- exam_session_read_scope (0075) เปิดทางให้กรรมการคุมสอบเห็นแถว exam_session
-- ที่ตัวเองต้องไปคุมอยู่แล้ว ผ่าน current_actor_is_exam_proctor() — ยิงตรง
-- แล้วเห็นแถวจริง แต่ GET /exam-schedule ยังคืนอาร์เรย์ว่างให้กรรมการคนนั้น
-- เพราะ ExamScheduleService.list() ต้อง join class_section เพื่อดึงชื่อวิชา
-- และเลขกลุ่มเรียนมาแสดง — class_section มีนโยบาย section_scope ของตัวเอง
-- (0034) ที่เปิดให้เฉพาะครูผู้สอน/ผู้สอนคาบ/บทบาทวิชาการเห็น ซึ่ง**ไม่รู้จัก**
-- แนวคิดกรรมการคุมสอบเลย — inner join จึงตัดแถว exam_session ที่ผ่านนโยบาย
-- ของตัวเองมาแล้วทิ้งไปเงียบ ๆ ที่ชั้น join
--
-- ─── ทำไมไม่แก้ที่ section_scope โดยตรง ───
-- section_scope เปิดกว้างขึ้นเพื่อกรรมการคุมสอบ จะแปลว่ากรรมการเห็นข้อมูล
-- อื่นทั้งหมดของกลุ่มเรียนนั้นไปด้วย (สมุดคะแนน รายชื่อนักศึกษา ฯลฯ) ทั้งที่
-- ควรเห็นแค่ชื่อวิชา/เลขกลุ่มเรียนสำหรับแสดงบนตารางสอบของตัวเองเท่านั้น
--
-- รูปแบบเดียวกับ class_section_institution() (0012) ที่ตัดวงจรให้ตารางอื่น
-- อ่าน institution_id ของ class_section ได้โดยไม่ต้องเห็นทั้งแถว — ต่างกันที่
-- ครั้งนี้ต้องการชื่อวิชากับเลขกลุ่มเรียนสำหรับแสดงผล ไม่ใช่แค่ id เดียว
-- ═══════════════════════════════════════════════════════════════════

create function class_section_display(p_section_id uuid)
returns table(section_no text, term_id uuid, course_code text, course_name text)
language sql stable security definer set search_path = public as $$
  select cs.section_no, cs.term_id, c.code, c.name_th
    from class_section cs
    join course c on c.id = cs.course_id
   where cs.id = p_section_id
$$;

comment on function class_section_display(uuid) is
  'ชื่อวิชา/เลขกลุ่มเรียนของ class_section หนึ่งรายการ ข้าม RLS ของ class_section เจตนา — ใช้เมื่อผู้เรียกได้รับอนุญาตให้เห็นสิ่งที่เกี่ยวกับกลุ่มเรียนนี้ผ่านตารางอื่นไปแล้ว (เช่น exam_session) แต่ไม่มีสิทธิ์เห็น class_section ทั้งแถว';

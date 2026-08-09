-- ═══════════════════════════════════════════════════════════════════
-- 0013_fix_student_balance_fanout.sql
--
-- แก้บั๊กยอดค้างชำระถูกคูณด้วยจำนวนงวดผ่อนชำระ
--
-- ─── อาการ ───
-- นักศึกษามีใบแจ้งหนี้ใบเดียว 12,600 บาท แบ่งสามงวด
-- v_student_balance รายงานว่าค้าง 37,800 บาท คือ 12,600 คูณสาม
--
-- ─── สาเหตุ ───
-- มุมมองเดิม join invoice กับ installment แล้ว sum(invoice.total)
-- การ join แบบหนึ่งต่อหลายทำให้แถวของใบแจ้งหนี้ถูกทำซ้ำตามจำนวนงวด
-- ผลรวมจึงถูกนับเกิน เป็นความผิดพลาดคลาสสิกของการรวมข้อมูลข้ามระดับ
--
-- ─── ผลกระทบที่เกิดขึ้นจริงก่อนแก้ ───
-- ยอดค้างในแอปนักศึกษาสูงเกินจริง · ข้อความเตือนความเสี่ยงบอกตัวเลขผิด
-- และถ้าเจ้าหน้าที่ใช้ยอดนี้เรียกเก็บเงิน จะเรียกเกินสามเท่า
--
-- ─── วิธีแก้ ───
-- รวมยอดที่ระดับใบแจ้งหนี้กับที่ระดับงวด แยกกันคนละชั้น แล้วค่อยเชื่อมกัน
-- ═══════════════════════════════════════════════════════════════════
begin;

create or replace view v_student_balance as
with by_invoice as (
  -- รวมที่ระดับใบแจ้งหนี้ ไม่แตะตารางงวด จึงไม่มีการทำซ้ำแถว
  select
    inv.student_id,
    inv.institution_id,
    sum(inv.total)                    as billed,
    sum(inv.paid_total)               as paid,
    sum(inv.total - inv.paid_total)   as outstanding
  from invoice inv
  where inv.status in ('issued', 'partially_paid')
  group by inv.student_id, inv.institution_id
),
by_installment as (
  -- รวมที่ระดับงวดแยกต่างหาก เพื่อหาวันครบกำหนดถัดไปและจำนวนวันที่เลยกำหนด
  select
    inv.student_id,
    min(n.due_on) filter (where n.status <> 'paid')                     as next_due_on,
    max((current_date - n.due_on)) filter (
      where n.status <> 'paid' and n.due_on < current_date
    )                                                                    as days_overdue
  from installment n
  join invoice inv on inv.id = n.invoice_id
  where inv.status in ('issued', 'partially_paid')
  group by inv.student_id
)
select
  b.student_id,
  b.institution_id,
  b.billed,
  b.paid,
  b.outstanding,
  d.next_due_on,
  d.days_overdue
from by_invoice b
left join by_installment d on d.student_id = b.student_id;

-- create or replace view ไม่รับประกันว่าตัวเลือกเดิมจะติดมาด้วย จึงตั้งซ้ำให้ชัดเจน
alter view v_student_balance set (security_invoker = true);

commit;

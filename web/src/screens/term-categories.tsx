/**
 * หมวดภาคเรียน — จัดกลุ่มภาคเรียนตามรอบเรียน (รอบเช้า/รอบบ่าย/ทวิภาคี ฯลฯ)
 * และแก้ไขช่องวันที่ย่อยของแต่ละภาคเรียน (0082)
 *
 * ─── ทำไมแยกจากฟอร์มเปิดภาคเรียนใหม่ในหน้า "งานวิชาการรายปี" ───
 * ช่องพวกนี้ (วันเริ่มลงทะเบียน/สมุดคะแนน/ชำระเงิน/ตรวจสอบข้อมูลจบ) มัก
 * ตั้งทีหลังตอนวางแผนงานทะเบียนของภาคเรียนนั้นละเอียดขึ้น ไม่ใช่ตอนเปิด
 * ภาคเรียนครั้งแรก การรวมไว้หน้าเดียวกันจะทำให้ฟอร์มเปิดภาคเรียนยาวเกินไป
 */
import { useState } from 'react';
import { api } from '../core/api';
import { fetchTerms, termLabel, type Term, type TermCategory } from '../core/catalog';
import { href } from '../core/router';
import { ActionButton, AsyncView, Badge, Card, Field, PageHead, TableCard, useAsync } from '../ui/kit';

function fetchCategories() {
  return api.get<TermCategory[]>('/academic/term-categories');
}

export function TermCategoriesScreen() {
  const categories = useAsync(fetchCategories, []);
  const terms = useAsync(fetchTerms, []);
  const [editingId, setEditingId] = useState<string | null>(null);

  const editing = terms.data?.find((t) => t.id === editingId) ?? null;

  return (
    <>
      <PageHead
        title="หมวดภาคเรียน"
        sub="จัดกลุ่มภาคเรียนตามรอบเรียน และกำหนดช่วงวันที่ย่อยของแต่ละภาคเรียน"
        actions={<a href={href('/settings-center')}>← ศูนย์การตั้งค่า</a>}
      />
      <div className="row" style={{ alignItems: 'flex-start' }}>
        <div style={{ flex: 1, minWidth: 280 }}>
          <CategoryList categories={categories} />
        </div>
        <div style={{ flex: 2, minWidth: 360 }}>
          <TableCard title="ภาคเรียนทั้งหมด">
            <AsyncView state={terms} empty="ยังไม่มีภาคเรียนในระบบ">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th>ภาคเรียน</th>
                      <th style={{ width: 140 }}>ช่วงเวลา</th>
                      <th style={{ width: 100 }}>หมวด</th>
                      <th style={{ width: 90 }} />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((t) => {
                      const cat = categories.data?.find((c) => c.id === t.category_id);
                      return (
                        <tr key={t.id} className={editingId === t.id ? 'selected' : ''}>
                          <td>{t.short_name || termLabel(t)}</td>
                          <td>{t.starts_on} – {t.ends_on}</td>
                          <td>{cat ? cat.title : <Badge kind="default">ไม่ระบุ</Badge>}</td>
                          <td>
                            <button className="ghost" onClick={() => setEditingId(t.id)}>แก้ไข</button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

          {editing && (
            <TermEditForm
              term={editing}
              categories={categories.data ?? []}
              onClose={() => setEditingId(null)}
              onDone={() => { terms.reload(); setEditingId(null); }}
            />
          )}
        </div>
      </div>
    </>
  );
}

function CategoryList({ categories }: { categories: ReturnType<typeof useAsync<TermCategory[]>> }) {
  const [title, setTitle] = useState('');
  const [editId, setEditId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState('');

  return (
    <TableCard title="หมวดภาคเรียน">
      <AsyncView state={categories} empty="ยังไม่มีหมวดภาคเรียน — วิทยาลัยที่ไม่แยกรอบเรียนไม่ต้องสร้าง">
        {(rows) => (
          <table>
            <thead><tr><th>หมวด</th><th style={{ width: 130 }} /></tr></thead>
            <tbody>
              {rows.map((c) => (
                <tr key={c.id}>
                  <td>
                    {editId === c.id
                      ? <input value={editTitle} onChange={(e) => setEditTitle(e.target.value)} />
                      : c.title}
                  </td>
                  <td>
                    {editId === c.id ? (
                      <>
                        <ActionButton
                          className="ghost"
                          onRun={() => {
                            if (!editTitle.trim()) throw new Error('กรอกชื่อหมวด');
                            return api.patch(`/academic/term-categories/${c.id}`, { title: editTitle.trim() });
                          }}
                          onDone={() => { setEditId(null); categories.reload(); }}
                        >
                          บันทึก
                        </ActionButton>
                        <button className="ghost" onClick={() => setEditId(null)}>ยกเลิก</button>
                      </>
                    ) : (
                      <>
                        <button className="ghost" onClick={() => { setEditId(c.id); setEditTitle(c.title); }}>แก้ไข</button>
                        <ActionButton
                          className="ghost danger"
                          confirm={`ลบหมวด "${c.title}" ใช่หรือไม่ — ภาคเรียนที่ผูกหมวดนี้จะกลายเป็นไม่ระบุหมวด`}
                          onRun={() => api.del(`/academic/term-categories/${c.id}`)}
                          onDone={() => categories.reload()}
                        >
                          ลบออก
                        </ActionButton>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
      <div className="row">
        <Field label="เพิ่มหมวดภาคเรียนใหม่">
          <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="เช่น รอบเช้า" />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!title.trim()) throw new Error('กรอกชื่อหมวด');
              return api.post('/academic/term-categories', { title: title.trim() });
            }}
            onDone={() => { setTitle(''); categories.reload(); }}
          >
            เพิ่มหมวด
          </ActionButton>
        </div>
      </div>
    </TableCard>
  );
}

function TermEditForm({
  term, categories, onClose, onDone,
}: {
  term: Term;
  categories: TermCategory[];
  onClose: () => void;
  onDone: () => void;
}) {
  const [categoryId, setCategoryId] = useState(term.category_id ?? '');
  const [shortName, setShortName] = useState(term.short_name ?? '');
  const [isNormal, setIsNormal] = useState(term.is_normal);
  const [registrationStartsOn, setRegistrationStartsOn] = useState(term.registration_starts_on ?? '');
  const [gradebookStartsOn, setGradebookStartsOn] = useState(term.gradebook_starts_on ?? '');
  const [paymentStartsOn, setPaymentStartsOn] = useState(term.payment_starts_on ?? '');
  const [paymentEndsOn, setPaymentEndsOn] = useState(term.payment_ends_on ?? '');
  const [auditStartsOn, setAuditStartsOn] = useState(term.audit_starts_on ?? '');
  const [auditEndsOn, setAuditEndsOn] = useState(term.audit_ends_on ?? '');

  return (
    <Card title={`แก้ไข — ${termLabel(term)}`} actions={<button className="ghost" onClick={onClose}>✕ ปิด</button>}>
      <div className="row">
        <label className="field">
          <span>หมวดภาคเรียน</span>
          <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">— ไม่ระบุหมวด —</option>
            {categories.map((c) => <option key={c.id} value={c.id}>{c.title}</option>)}
          </select>
        </label>
        <Field label="ชื่อย่อ">
          <input value={shortName} onChange={(e) => setShortName(e.target.value)} placeholder={termLabel(term)} />
        </Field>
        <label className="field">
          <span>ภาคเรียนปกติ</span>
          <input type="checkbox" checked={isNormal} onChange={(e) => setIsNormal(e.target.checked)} />
        </label>
      </div>
      <div className="row">
        <Field label="วันที่เริ่มลงทะเบียนรายวิชา">
          <input type="date" value={registrationStartsOn} onChange={(e) => setRegistrationStartsOn(e.target.value)} />
        </Field>
        <Field label="วันที่สิ้นสุดลงทะเบียนรายวิชา">
          <input type="date" value={term.add_drop_ends_on ?? ''} disabled title="แก้ที่หน้างานวิชาการรายปี — เพิ่ม/ถอนถึงวันที่" />
        </Field>
      </div>
      <div className="row">
        <Field label="กำหนดวันเริ่มต้นสมุดบันทึกคะแนน">
          <input type="date" value={gradebookStartsOn} onChange={(e) => setGradebookStartsOn(e.target.value)} />
        </Field>
        <Field label="กำหนดวันสิ้นสุดสมุดบันทึกคะแนน">
          <input type="date" value={term.grade_due_on ?? ''} disabled title="แก้ที่หน้างานวิชาการรายปี — กำหนดส่งเกรด" />
        </Field>
      </div>
      <div className="row">
        <Field label="วันที่เริ่มต้นการชำระเงิน">
          <input type="date" value={paymentStartsOn} onChange={(e) => setPaymentStartsOn(e.target.value)} />
        </Field>
        <Field label="วันครบกำหนดชำระเงิน">
          <input type="date" value={paymentEndsOn} onChange={(e) => setPaymentEndsOn(e.target.value)} />
        </Field>
      </div>
      <div className="row">
        <Field label="กำหนดวันเริ่มต้นตรวจสอบข้อมูลจบโดยนักศึกษา">
          <input type="date" value={auditStartsOn} onChange={(e) => setAuditStartsOn(e.target.value)} />
        </Field>
        <Field label="กำหนดวันสิ้นสุดตรวจสอบข้อมูลจบโดยนักศึกษา">
          <input type="date" value={auditEndsOn} onChange={(e) => setAuditEndsOn(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => api.patch(`/academic/terms/${term.id}`, {
              categoryId: categoryId || null,
              shortName: shortName || undefined,
              isNormal,
              registrationStartsOn: registrationStartsOn || undefined,
              gradebookStartsOn: gradebookStartsOn || undefined,
              paymentStartsOn: paymentStartsOn || undefined,
              paymentEndsOn: paymentEndsOn || undefined,
              auditStartsOn: auditStartsOn || undefined,
              auditEndsOn: auditEndsOn || undefined,
            })}
            onDone={onDone}
          >
            บันทึก
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

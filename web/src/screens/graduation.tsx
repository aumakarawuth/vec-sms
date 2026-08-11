/**
 * ตรวจเกณฑ์จบและอนุมัติสำเร็จการศึกษา
 *
 * ─── ทำไมไม่มีปุ่ม "อนุมัติทั้งรุ่น" ───
 * `evaluate_graduation()` คืนกฎรายข้อว่าใครยังขาดอะไร การอนุมัติเป็นรายคน
 * เพราะแต่ละคนขาดคนละอย่างและต้องมีคนตัดสินใจจริง ๆ ว่ายกเว้นข้อไหนได้
 * ปุ่มที่กดทีเดียวจบทั้งรุ่นแปลว่าไม่มีใครอ่านผลตรวจของใครเลย
 *
 * ─── ทำไม gpax ตรึงตอนอนุมัติ ───
 * `student_graduation.gpax` ถูกตรึง ณ เวลาอนุมัติ ไม่ได้อ่านใหม่จาก
 * `term_summary` ทุกครั้ง เพราะเอกสารที่ออกไปแล้วต้องตรงกับที่นักศึกษาถืออยู่
 * แม้ผลการเรียนจะถูกแก้ภายหลังด้วยคำร้อง (หลักข้อ 5)
 */
import { useState } from 'react';
import { api } from '../core/api';
import { num, thaiDate } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface Approval {
  id: string;
  approved_on: string;
  document_no: string | null;
  note: string | null;
  graduates: number;
}

interface Rule {
  kind: string;
  name_th: string;
  required: string | null;
  achieved: string | null;
  satisfied: boolean;
  is_blocking: boolean;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
  status: string;
}

interface StaffRow {
  id: string;
  person_id: string;
  staff_code: string;
  full_name: string;
}

interface PvrsResult {
  total: number;
  missingNumbers: number;
  formatConfirmed: boolean;
  note: string;
  rows: Record<string, unknown>[];
}

/**
 * แก้วันสำเร็จการศึกษาของนักศึกษาที่อนุมัติจบไปแล้ว
 *
 * ─── ทำไมช่องนี้อยู่ที่ระเบียนจบ ไม่ใช่ที่หน้าออกเอกสาร ───
 * `issued_document.payload` ตรึงตั้งแต่วันที่ออกและแก้ไม่ได้ ถ้าให้กรอก
 * วันที่ตอนกดพิมพ์ คนที่พิมพ์ผิดต้องยกเลิกใบแล้วออกใหม่ ซึ่งกินเลขที่เพิ่ม
 * ทุกครั้งและทิ้งใบที่ยกเลิกไว้ในระบบถาวร
 *
 * และวันสำเร็จการศึกษาเป็นข้อเท็จจริงของนักศึกษา ไม่ใช่ของกระดาษใบนั้น —
 * ใบทุกใบที่ออกให้คนคนเดียวกันต้องเขียนวันเดียวกันเสมอ
 *
 * ─── ใบที่ออกไปแล้วไม่เปลี่ยนตาม ───
 * ซึ่งถูกแล้ว เพราะมีคนถือใบนั้นอยู่ ถ้าต้องการใบที่มีวันใหม่ ต้องยกเลิก
 * ใบเก่าแล้วออกใหม่อย่างเปิดเผย
 */
function CompletedOnEditor({ studentId }: { studentId: string }) {
  const [date, setDate] = useState('');
  const [saved, setSaved] = useState<string | null>(null);

  return (
    <div style={{ marginTop: 12 }}>
      <div className="row">
        <Field label="แก้วันสำเร็จการศึกษา (จบช้า หรือกรอกผิด)">
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </Field>
        <div className="field">
          <span>&nbsp;</span>
          <ActionButton
            onRun={() =>
              api.patch<{ completed_on: string }>(
                `/graduation/students/${studentId}/completed-on`,
                { completedOn: date },
              )
            }
            onDone={(r) => setSaved((r as { completed_on: string }).completed_on)}
          >
            บันทึกวันจบ
          </ActionButton>
        </div>
      </div>
      {saved && (
        <Notice kind="ok">
          บันทึกแล้ว — ใบที่ออกไปก่อนหน้านี้ยังเขียนวันเดิม เพราะเนื้อหาของ
          เอกสารที่ออกแล้วแก้ไม่ได้ ถ้าต้องการใบที่มีวันใหม่ ต้องยกเลิกใบเก่า
          แล้วออกใหม่
        </Notice>
      )}
    </div>
  );
}

export function GraduationScreen() {
  const approvals = useAsync(() => api.get<Approval[]>('/graduation/approvals'), []);
  const students = useAsync(() => api.get<StudentRow[]>('/students?limit=200'), []);
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=100'), []);

  const [studentId, setStudentId] = useState('');
  const [approvedOn, setApprovedOn] = useState(new Date().toISOString().slice(0, 10));
  const [approvedBy, setApprovedBy] = useState('');
  const [documentNo, setDocumentNo] = useState('');
  const [pvrs, setPvrs] = useState<PvrsResult | null>(null);

  const rules = useAsync(
    () => (studentId ? api.get<Rule[]>(`/students/${studentId}/graduation`) : Promise.resolve([])),
    [studentId],
  );

  const blocking = (rules.data ?? []).filter((r) => r.is_blocking && !r.satisfied);

  return (
    <>
      <PageHead title="สำเร็จการศึกษา" />

      <Card title="ตรวจเกณฑ์การจบรายคน">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>นักศึกษา</span>
            <AsyncView state={students}>
              {(rows) => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {rows.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.student_code} {s.full_name}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>

        {studentId && (
          <AsyncView state={rules} empty="ยังไม่มีเกณฑ์ให้ตรวจ — ตรวจว่าผูกหลักสูตรให้นักศึกษาแล้วหรือยัง">
            {(list) => (
              <>
                <Notice kind={blocking.length === 0 ? 'ok' : 'warn'}>
                  {blocking.length === 0
                    ? 'ครบทุกเกณฑ์ที่บังคับแล้ว'
                    : `ยังขาดเกณฑ์ที่บังคับอยู่ ${blocking.length} ข้อ`}
                </Notice>
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 260 }}>เกณฑ์</th>
                      <th className="num" style={{ width: 100 }}>ต้องได้</th>
                      <th className="num" style={{ width: 100 }}>ได้จริง</th>
                      <th style={{ width: 110 }}>ผล</th>
                      <th style={{ width: 110 }}>บังคับไหม</th>
                    </tr>
                  </thead>
                  <tbody>
                    {list.map((r, i) => (
                      <tr key={`${r.kind}-${i}`}>
                        <td style={{ whiteSpace: 'normal' }}>{r.name_th}</td>
                        <td className="num">{r.required === null ? '—' : num(r.required, 2)}</td>
                        <td className="num">{r.achieved === null ? '—' : num(r.achieved, 2)}</td>
                        <td>
                          <Badge kind={r.satisfied ? 'ok' : r.is_blocking ? 'danger' : 'warn'}>
                            {r.satisfied ? 'ผ่าน' : 'ยังไม่ผ่าน'}
                          </Badge>
                        </td>
                        <td>{r.is_blocking ? 'บังคับ' : 'ไม่บังคับ'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </>
            )}
          </AsyncView>
        )}

        {studentId && <CompletedOnEditor studentId={studentId} />}
      </Card>

      <Card title="เปิดรอบอนุมัติสำเร็จการศึกษา">
        <div className="row">
          <Field label="วันที่อนุมัติ">
            <input type="date" value={approvedOn} onChange={(e) => setApprovedOn(e.target.value)} />
          </Field>
          <label className="field">
            <span>ผู้อนุมัติ</span>
            <AsyncView state={staff}>
              {(page) => (
                <select value={approvedBy} onChange={(e) => setApprovedBy(e.target.value)}>
                  <option value="">— เลือกผู้อนุมัติ —</option>
                  {page.items.map((s) => (
                    <option key={s.person_id} value={s.person_id}>
                      {s.full_name} ({s.staff_code})
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
          <Field label="เลขที่หนังสืออนุมัติ (ถ้ามี)">
            <input value={documentNo} onChange={(e) => setDocumentNo(e.target.value)} placeholder="เช่น วก.2569/021" />
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() =>
                api.post('/graduation/approvals', {
                  approvedOn,
                  approvedBy,
                  ...(documentNo.trim() ? { documentNo: documentNo.trim() } : {}),
                })
              }
              onDone={() => {
                setDocumentNo('');
                approvals.reload();
              }}
            >
              เปิดรอบอนุมัติ
            </ActionButton>
          </div>
        </div>
        <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
          ผู้อนุมัติคือคนที่ลงนามจริงในหนังสือ ซึ่งอาจไม่ใช่คนที่กำลังบันทึกอยู่ตอนนี้
        </div>
      </Card>

      <TableCard title="รอบอนุมัติที่เคยเปิด">
        <AsyncView state={approvals} empty="ยังไม่เคยเปิดรอบอนุมัติ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>วันที่อนุมัติ</th>
                  <th style={{ width: 160 }}>เลขที่หนังสือ</th>
                  <th className="num" style={{ width: 110 }}>ผู้สำเร็จ</th>
                  <th>หมายเหตุ</th>
                  <th style={{ width: 150 }}>ไฟล์ส่ง สอศ.</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((a) => (
                  <tr key={a.id}>
                    <td>{thaiDate(a.approved_on)}</td>
                    <td className="mono">{a.document_no ?? '—'}</td>
                    <td className="num">{a.graduates}</td>
                    <td style={{ whiteSpace: 'normal' }}>{a.note ?? '—'}</td>
                    <td>
                      <ActionButton
                        onRun={() => api.get<PvrsResult>(`/graduation/approvals/${a.id}/pvrs`)}
                        onDone={(r) => setPvrs(r as PvrsResult)}
                      >
                        ดูข้อมูล PVRS
                      </ActionButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {pvrs && (
        <Card title={`ข้อมูลสำหรับส่ง สอศ. — ${pvrs.total} รายการ`}>
          <Notice kind="warn">
            {pvrs.note}
            {pvrs.missingNumbers > 0 && (
              <>
                <br />
                <strong>ยังขาดเลขที่เอกสาร {pvrs.missingNumbers} รายการ</strong> —
                ออกเอกสารให้ครบก่อนส่ง มิฉะนั้นหน่วยงานอาจตีกลับทั้งชุด
              </>
            )}
          </Notice>
          {pvrs.rows.length > 0 && (
            <div style={{ overflowX: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    {Object.keys(pvrs.rows[0] ?? {}).map((k) => (
                      <th key={k}>{k}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {pvrs.rows.map((r, i) => (
                    <tr key={i}>
                      {Object.keys(pvrs.rows[0] ?? {}).map((k) => (
                        <td key={k}>{String(r[k] ?? '—')}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </>
  );
}

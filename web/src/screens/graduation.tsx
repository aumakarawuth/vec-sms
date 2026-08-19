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

interface SurveyCandidate {
  student_id: string;
  student_code: string;
  full_name: string;
  completed_on: string;
  latest_status: string | null;
  latest_responded_on: string | null;
}

interface SurveySummaryRow {
  status: string;
  students: number;
}

interface VersionOption {
  id: string;
  edition_be: number;
  curriculum_name: string;
  shift: string | null;
}

/**
 * เพิ่มผู้สำเร็จการศึกษาเข้ารอบอนุมัติ — จุดที่ขาดไปเดิม
 *
 * `POST /graduation/approvals/:id/students` มีมาตั้งแต่ 0027/0028 แต่ไม่เคย
 * มีปุ่มเรียกเลยสักที่ — เปิดรอบอนุมัติได้ แต่ไม่มีทางเติมคนเข้ารอบนั้น
 * `student_graduation` จึงว่างเปล่าเสมอไม่ว่าจะเปิดรอบกี่ครั้ง (รูปเดียวกับ
 * `take_usage_snapshot()` และ `generate_class_meetings()` ที่ประกาศเจตนา
 * ไว้แล้วไม่มีอะไรทำให้เจตนานั้นเกิดขึ้น) เจอตอนตามหาว่าทำไมแบบสำรวจภาวะ
 * การมีงานทำไม่มีผู้สำเร็จการศึกษาให้เลือกเลยสักคน
 */
function AddGraduateForm({
  approvalId, students, versions, onDone,
}: { approvalId: string; students: StudentRow[]; versions: VersionOption[]; onDone: () => void }) {
  const [studentId, setStudentId] = useState('');
  const [versionId, setVersionId] = useState('');
  const [completedOn, setCompletedOn] = useState(new Date().toISOString().slice(0, 10));
  const [gpax, setGpax] = useState('');
  const [creditsEarned, setCreditsEarned] = useState('');
  const [certificateNo, setCertificateNo] = useState('');

  return (
    <Card title="เพิ่มผู้สำเร็จการศึกษาเข้ารอบนี้">
      <div className="row">
        <label className="field" style={{ flex: 2 }}>
          <span>นักศึกษา</span>
          <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
            <option value="">— เลือกนักศึกษา —</option>
            {students.map((s) => (
              <option key={s.id} value={s.id}>{s.student_code} {s.full_name}</option>
            ))}
          </select>
        </label>
        <label className="field" style={{ flex: 2 }}>
          <span>ฉบับหลักสูตรที่จบ</span>
          <select value={versionId} onChange={(e) => setVersionId(e.target.value)}>
            <option value="">— เลือกฉบับ —</option>
            {versions.map((v) => (
              <option key={v.id} value={v.id}>{v.curriculum_name} — ฉบับ {v.edition_be}</option>
            ))}
          </select>
        </label>
        <Field label="วันสำเร็จการศึกษา">
          <input type="date" value={completedOn} onChange={(e) => setCompletedOn(e.target.value)} />
        </Field>
      </div>
      <div className="row">
        <Field label="GPAX">
          <input type="number" min={0} max={4} step={0.01} value={gpax} onChange={(e) => setGpax(e.target.value)} style={{ maxWidth: 90 }} />
        </Field>
        <Field label="หน่วยกิตที่ได้">
          <input type="number" min={0} step={0.5} value={creditsEarned} onChange={(e) => setCreditsEarned(e.target.value)} style={{ maxWidth: 100 }} />
        </Field>
        <Field label="เลขที่ใบประกาศนียบัตร (ถ้ามี)">
          <input value={certificateNo} onChange={(e) => setCertificateNo(e.target.value.replace(/\D/g, ''))} placeholder="ตัวเลขล้วน" />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!studentId || !versionId) throw new Error('ต้องเลือกนักศึกษาและฉบับหลักสูตร');
              if (!gpax || !creditsEarned) throw new Error('ต้องกรอก GPAX และหน่วยกิตที่ได้');
              return api.post(`/graduation/approvals/${approvalId}/students`, {
                studentId, curriculumVersionId: versionId, completedOn,
                gpax: Number(gpax), creditsEarned: Number(creditsEarned),
                ...(certificateNo.trim() ? { certificateNo: certificateNo.trim() } : {}),
              });
            }}
            onDone={() => {
              setStudentId(''); setVersionId(''); setGpax(''); setCreditsEarned(''); setCertificateNo('');
              onDone();
            }}
          >
            เพิ่มเข้ารอบอนุมัติ
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

const EMPLOYMENT_STATUS: Record<string, string> = {
  employed: 'ทำงานแล้ว',
  employed_and_studying: 'ทำงานและศึกษาต่อ',
  further_study: 'ศึกษาต่อ',
  seeking: 'ยังไม่มีงานทำ',
  other: 'อื่น ๆ',
};

/**
 * บันทึกแบบสำรวจภาวะการมีงานทำของบัณฑิตหนึ่งคน
 *
 * ช่องที่ต้องกรอกเปลี่ยนตามสถานะที่เลือก — ฐานข้อมูลบังคับด้วย check
 * constraint อยู่แล้ว (ทำงานแล้วต้องมีสถานประกอบการ) ฟอร์มนี้แค่ซ่อนช่อง
 * ที่ไม่เกี่ยวเพื่อไม่ให้กรอกผิดจุด
 */
function SurveyForm({ candidate, onDone }: { candidate: SurveyCandidate; onDone: () => void }) {
  const [status, setStatus] = useState('employed');
  const [employerNameTh, setEmployerNameTh] = useState('');
  const [jobTitleTh, setJobTitleTh] = useState('');
  const [fieldMatches, setFieldMatches] = useState(true);
  const [studyInstitution, setStudyInstitution] = useState('');
  const [studyField, setStudyField] = useState('');
  const [contactPhone, setContactPhone] = useState('');

  const needsEmployer = status === 'employed' || status === 'employed_and_studying';
  const needsStudy = status === 'further_study' || status === 'employed_and_studying';

  return (
    <Card title={`บันทึกแบบสำรวจ — ${candidate.full_name}`}>
      <div className="row">
        <Field label="สถานภาพปัจจุบัน">
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            {Object.entries(EMPLOYMENT_STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
        <Field label="เบอร์ติดต่อ (ถ้ามี)">
          <input value={contactPhone} onChange={(e) => setContactPhone(e.target.value)} />
        </Field>
      </div>
      {needsEmployer && (
        <div className="row">
          <Field label="สถานประกอบการ">
            <input value={employerNameTh} onChange={(e) => setEmployerNameTh(e.target.value)} />
          </Field>
          <Field label="ตำแหน่งงาน">
            <input value={jobTitleTh} onChange={(e) => setJobTitleTh(e.target.value)} />
          </Field>
          <label className="field">
            <span>ตรงกับสาขาที่เรียนไหม</span>
            <select value={fieldMatches ? '1' : '0'} onChange={(e) => setFieldMatches(e.target.value === '1')}>
              <option value="1">ตรงสาขา</option>
              <option value="0">ไม่ตรงสาขา</option>
            </select>
          </label>
        </div>
      )}
      {needsStudy && (
        <div className="row">
          <Field label="สถานศึกษาที่เรียนต่อ">
            <input value={studyInstitution} onChange={(e) => setStudyInstitution(e.target.value)} />
          </Field>
          <Field label="สาขาที่เรียนต่อ">
            <input value={studyField} onChange={(e) => setStudyField(e.target.value)} />
          </Field>
        </div>
      )}
      <div className="row">
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (needsEmployer && !employerNameTh.trim()) throw new Error('ต้องระบุสถานประกอบการ');
              if (needsStudy && !studyInstitution.trim()) throw new Error('ต้องระบุสถานศึกษาที่เรียนต่อ');
              return api.post('/graduation/survey', {
                studentId: candidate.student_id,
                status,
                ...(needsEmployer ? { employerNameTh: employerNameTh.trim(), jobTitleTh: jobTitleTh.trim() || undefined, fieldMatchesStudy: fieldMatches } : {}),
                ...(needsStudy ? { furtherStudyInstitutionTh: studyInstitution.trim(), furtherStudyFieldTh: studyField.trim() || undefined } : {}),
                ...(contactPhone.trim() ? { contactPhone: contactPhone.trim() } : {}),
              });
            }}
            onDone={onDone}
          >
            บันทึกแบบสำรวจ
          </ActionButton>
        </div>
      </div>
    </Card>
  );
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
  const versions = useAsync(() => api.get<VersionOption[]>('/curriculum/versions'), []);

  const [studentId, setStudentId] = useState('');
  const [approvedOn, setApprovedOn] = useState(new Date().toISOString().slice(0, 10));
  const [approvedBy, setApprovedBy] = useState('');
  const [documentNo, setDocumentNo] = useState('');
  const [pvrs, setPvrs] = useState<PvrsResult | null>(null);
  const [surveyFor, setSurveyFor] = useState('');
  const [approvalId, setApprovalId] = useState('');

  const surveyCandidates = useAsync(() => api.get<SurveyCandidate[]>('/graduation/survey/candidates'), []);
  const surveySummary = useAsync(() => api.get<SurveySummaryRow[]>('/graduation/survey/summary'), []);

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
                  <th style={{ width: 40 }} />
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
                    <td>
                      <input
                        type="radio"
                        name="approval"
                        checked={approvalId === a.id}
                        onChange={() => setApprovalId(approvalId === a.id ? '' : a.id)}
                      />
                    </td>
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

      {approvalId && (
        <AsyncView state={students} empty="ไม่มีนักศึกษา">
          {(rows) => (
            <AsyncView state={versions} empty="ยังไม่มีฉบับหลักสูตร">
              {(vrows) => (
                <AddGraduateForm
                  approvalId={approvalId}
                  students={rows}
                  versions={vrows}
                  onDone={() => {
                    approvals.reload();
                    surveyCandidates.reload();
                  }}
                />
              )}
            </AsyncView>
          )}
        </AsyncView>
      )}

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

      <TableCard title="สรุปแบบสำรวจภาวะการมีงานทำ">
        <AsyncView state={surveySummary} empty="ยังไม่มีใครตอบแบบสำรวจ">
          {(rows) => (
            <div className="registry-summary">
              {rows.map((r) => (
                <div className="registry-stat primary" key={r.status}>
                  <span>{EMPLOYMENT_STATUS[r.status] ?? r.status}</span>
                  <strong>{r.students}</strong>
                </div>
              ))}
            </div>
          )}
        </AsyncView>
      </TableCard>

      <TableCard title="ผู้สำเร็จการศึกษา — สถานะแบบสำรวจ">
        <AsyncView state={surveyCandidates} empty="ยังไม่มีผู้สำเร็จการศึกษา">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                  <th>ชื่อ — นามสกุล</th>
                  <th style={{ width: 130 }}>วันสำเร็จการศึกษา</th>
                  <th style={{ width: 180 }}>สถานะล่าสุด</th>
                  <th style={{ width: 140 }}>ตอบเมื่อ</th>
                  <th style={{ width: 120 }} />
                </tr>
              </thead>
              <tbody>
                {rows.map((c) => (
                  <tr key={c.student_id}>
                    <td className="mono">{c.student_code}</td>
                    <td>{c.full_name}</td>
                    <td>{thaiDate(c.completed_on)}</td>
                    <td>
                      {c.latest_status ? (
                        <Badge kind="ok">{EMPLOYMENT_STATUS[c.latest_status] ?? c.latest_status}</Badge>
                      ) : (
                        <Badge kind="warn">ยังไม่ตอบ</Badge>
                      )}
                    </td>
                    <td>{c.latest_responded_on ? thaiDate(c.latest_responded_on) : '—'}</td>
                    <td>
                      <button className="ghost" onClick={() => setSurveyFor(surveyFor === c.student_id ? '' : c.student_id)}>
                        {surveyFor === c.student_id ? 'ปิด' : c.latest_status ? 'สำรวจซ้ำ' : 'บันทึก'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {surveyFor && surveyCandidates.data && (
        <SurveyForm
          candidate={surveyCandidates.data.find((c) => c.student_id === surveyFor)!}
          onDone={() => { setSurveyFor(''); surveyCandidates.reload(); surveySummary.reload(); }}
        />
      )}
    </>
  );
}

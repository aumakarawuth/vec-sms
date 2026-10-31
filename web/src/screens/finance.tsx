/**
 * งานการเงิน — ออกใบแจ้งหนี้ รับชำระ และดูยอดค้าง
 *
 * ─── ทำไมไม่มีปุ่มแก้ยอดในใบแจ้งหนี้ ───
 * ใบแจ้งหนี้ออกจาก `fee_schedule` ของชั้นปีและปีการศึกษานั้น ไม่ใช่ตัวเลข
 * ที่เจ้าหน้าที่พิมพ์เอง — โรงเรียนเอกชนถูกตรวจย้อนหลังได้ว่าเก็บตรงกับ
 * ประกาศที่แจ้งไว้หรือไม่ ถ้าให้แก้ยอดรายคนจากหน้าจอ ความสอดคล้องนั้นหายทันที
 * ส่วนลดและทุนไปที่ `funding_source` ซึ่งบันทึกว่าลดเพราะอะไร
 *
 * ─── ทำไมปุ่มปรับสถานะระงับสิทธิ์อยู่ตรงนี้ ───
 * งานประจำวันปรับให้คืนละครั้ง แต่เจ้าหน้าที่ที่เพิ่งรับชำระเงินต้องปลดให้
 * นักศึกษาลงทะเบียนได้เดี๋ยวนี้ ไม่ใช่พรุ่งนี้
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { money, thaiDate } from '../core/fmt';
import { useRoute } from '../core/router';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, PrintButton, TableCard, useAsync,
} from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const METHOD: Record<string, string> = {
  cash: 'เงินสด',
  bank_transfer: 'โอนเงิน',
  promptpay: 'พร้อมเพย์',
  credit_card: 'บัตรเครดิต',
  counter_service: 'เคาน์เตอร์เซอร์วิส',
  direct_debit: 'หักบัญชีอัตโนมัติ',
  gov_subsidy: 'เงินอุดหนุนรัฐ',
  student_loan: 'กองทุนกู้ยืม',
  scholarship: 'ทุนการศึกษา',
  adjustment: 'ปรับปรุงรายการ',
};

/*
 * `v_ar_aging.bucket` คืนข้อความไทยมาแล้ว ไม่ใช่รหัส — หน้าจอจึงไม่แปลซ้ำ
 * เหลือแค่เลือกสีตามความหนักของหนี้ ถ้าแปลซ้ำที่นี่แล้ววันหนึ่งฐานข้อมูล
 * เปลี่ยนช่วงวัน หน้าจอจะแสดงช่วงเก่าทับค่าจริงโดยไม่มีอะไรฟ้อง
 */
function bucketKind(bucket: string): 'default' | 'warn' | 'danger' {
  if (bucket.includes('ยังไม่')) return 'default';
  if (bucket.includes('60 วันขึ้นไป')) return 'danger';
  return 'warn';
}

interface AgingRow {
  bucket: string;
  students: string | number;
  amount: string | number;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

interface Receipt {
  id: string;
  doc_no: string;
  issued_on: string;
  voided_at: string | null;
  void_reason: string | null;
  amount: string | number;
  method: string;
  amount_text: string;
}

interface PaymentResult {
  paymentId: string;
  receipt: { id: string; doc_no: string } | null;
  overpaid: number;
}

interface Balance {
  billed: number | string;
  paid: number | string;
  outstanding: number | string;
  next_due_on: string | null;
  days_overdue: number | null;
}

interface PendingMatch {
  id: string;
  posted_at: string;
  amount: string | number;
  counterparty: string | null;
  ref1: string | null;
  ref2: string | null;
  state: string;
  confidence: number | null;
  match_reason: string | null;
  invoice_id: string | null;
  invoice_no: string | null;
  student_code: string | null;
  student_name: string | null;
}

interface ReconcileResult {
  autoMatched: number;
  suggested: number;
  unmatched: number;
}

interface AcademicYear {
  id: string;
  year_be: number;
}

interface ProgramRow {
  program_id: string;
  program_name: string;
}

interface FeeItem {
  id: string;
  code: string;
  name_th: string;
  kind: string;
  subsidised: boolean;
  refundable: boolean;
}

interface FeeSchedule {
  id: string;
  level: string | null;
  study_year: number | null;
  program_id: string | null;
  program_name: string | null;
  announcement_no: string | null;
  announced_on: string | null;
  active: boolean;
  line_count: number;
}

interface FeeScheduleLine {
  id: string;
  fee_item_id: string;
  fee_item_name: string;
  term_ordinal: number;
  amount: string | number;
}

interface FundingSource {
  id: string;
  kind: string;
  name_th: string;
  external_ref: string | null;
  active: boolean;
}

interface StudentFundingRow {
  id: string;
  funding_source_id: string;
  funding_name: string;
  kind: string;
  academic_year_id: string;
  term_id: string | null;
  fee_item_id: string | null;
  fee_item_name: string | null;
  percent_off: string | number | null;
  amount: string | number | null;
  document_no: string | null;
  note: string | null;
  approved_at: string | null;
}

const LEVEL_LABEL: Record<string, string> = { PVC: 'ปวช.', PVS: 'ปวส.', TVB: 'ทวิภาคีบัณฑิต' };

const FEE_ITEM_KIND: Record<string, string> = {
  tuition: 'ค่าเล่าเรียน', lab_material: 'ค่าวัสดุฝึก', activity: 'ค่ากิจกรรม',
  insurance: 'ค่าประกันอุบัติเหตุ', uniform: 'ค่าเครื่องแบบ', book: 'ค่าหนังสือ',
  exam: 'ค่าธรรมเนียมสอบ', dormitory: 'ค่าหอพัก', other: 'อื่น ๆ',
};

const FUNDING_KIND: Record<string, string> = {
  scholarship: 'ทุนการศึกษา', sibling: 'ส่วนลดพี่น้อง', staff_child: 'ส่วนลดบุตรบุคลากร',
  gov_subsidy: 'เงินอุดหนุนรายบุคคล', student_loan: 'กยศ.', employer: 'ทุนสถานประกอบการ', other: 'อื่น ๆ',
};

/**
 * โครงสร้างค่าเทอม — ระบุแยกสาขา/ชั้นปี/ระดับได้ หรือเว้นว่างให้เป็น "รวม"
 * (ใช้กับทุกค่าของมิตินั้น) ตามที่ program_id รองรับมาตั้งแต่ 0010 และ 0080
 * เปิดให้ level/study_year ว่างได้แบบเดียวกัน — ไม่มีปุ่มนี้มาก่อนเลยตั้งแต่
 * 0010 วิทยาลัยที่เปิดใหม่จึงตั้งค่าเทอมเองไม่ได้นอกจากมือแตะฐานข้อมูล
 */
function FeeScheduleSetupCard() {
  const years = useAsync(() => api.get<AcademicYear[]>('/academic/years'), []);
  const programs = useAsync(() => api.get<ProgramRow[]>('/curriculum/programs'), []);
  const feeItems = useAsync(() => api.get<FeeItem[]>('/finance/fee-items'), []);

  const [yearId, setYearId] = useState('');
  const schedules = useAsync(
    () => (yearId ? api.get<FeeSchedule[]>(`/finance/fee-schedules${qs({ academicYearId: yearId })}`) : Promise.resolve([])),
    [yearId],
  );

  const [level, setLevel] = useState('');
  const [studyYear, setStudyYear] = useState('');
  const [programId, setProgramId] = useState('');
  const [announcementNo, setAnnouncementNo] = useState('');
  const [announcedOn, setAnnouncedOn] = useState('');

  const [itemCode, setItemCode] = useState('');
  const [itemName, setItemName] = useState('');
  const [itemKind, setItemKind] = useState('tuition');

  const [scheduleId, setScheduleId] = useState('');
  const lines = useAsync(
    () => (scheduleId ? api.get<FeeScheduleLine[]>(`/finance/fee-schedules/${scheduleId}/lines`) : Promise.resolve([])),
    [scheduleId],
  );
  const [lineItemId, setLineItemId] = useState('');
  const [lineTerm, setLineTerm] = useState('1');
  const [lineAmount, setLineAmount] = useState('');

  const uniquePrograms = new Map<string, string>();
  for (const p of programs.data ?? []) uniquePrograms.set(p.program_id, p.program_name);

  return (
    <>
      <Card title="รายการค่าธรรมเนียม">
        <div className="row">
          <Field label="รหัส">
            <input value={itemCode} onChange={(e) => setItemCode(e.target.value)} placeholder="TUITION" />
          </Field>
          <Field label="ชื่อรายการ">
            <input value={itemName} onChange={(e) => setItemName(e.target.value)} placeholder="ค่าเล่าเรียน" />
          </Field>
          <Field label="ประเภท">
            <select value={itemKind} onChange={(e) => setItemKind(e.target.value)}>
              {Object.entries(FEE_ITEM_KIND).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() => api.post('/finance/fee-items', { code: itemCode.trim(), nameTh: itemName.trim(), kind: itemKind })}
              onDone={() => { setItemCode(''); setItemName(''); feeItems.reload(); }}
            >
              เพิ่มรายการ
            </ActionButton>
          </div>
        </div>
        <AsyncView state={feeItems}>
          {(rows) => rows.length === 0 ? (
            <div className="empty">ยังไม่มีรายการค่าธรรมเนียม</div>
          ) : (
            <div className="hint">{rows.map((r) => `${r.name_th} (${r.code})`).join(' · ')}</div>
          )}
        </AsyncView>
      </Card>

      <TableCard
        title="โครงสร้างค่าเทอม"
        actions={
          <div style={{ width: 200 }}>
            <AsyncView state={years}>
              {(rows) => (
                <select value={yearId} onChange={(e) => { setYearId(e.target.value); setScheduleId(''); }}>
                  <option value="">— เลือกปีการศึกษา —</option>
                  {rows.map((y) => <option key={y.id} value={y.id}>ปีการศึกษา {y.year_be}</option>)}
                </select>
              )}
            </AsyncView>
          </div>
        }
      >
        {yearId && (
          <>
            <div className="row">
              <Field label="ระดับ">
                <select value={level} onChange={(e) => setLevel(e.target.value)}>
                  <option value="">ทุกระดับ (รวม)</option>
                  {Object.entries(LEVEL_LABEL).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                </select>
              </Field>
              <Field label="ชั้นปี">
                <select value={studyYear} onChange={(e) => setStudyYear(e.target.value)}>
                  <option value="">ทุกชั้นปี (รวม)</option>
                  {[1, 2, 3, 4].map((n) => <option key={n} value={n}>ชั้นปีที่ {n}</option>)}
                </select>
              </Field>
              <Field label="สาขา">
                <select value={programId} onChange={(e) => setProgramId(e.target.value)}>
                  <option value="">ทุกสาขา (รวม)</option>
                  {[...uniquePrograms].map(([id, name]) => <option key={id} value={id}>{name}</option>)}
                </select>
              </Field>
              <Field label="เลขที่ประกาศ">
                <input value={announcementNo} onChange={(e) => setAnnouncementNo(e.target.value)} placeholder="ปก.2569/001" />
              </Field>
              <Field label="วันประกาศ (พ.ศ. หรือ ค.ศ.)">
                <input value={announcedOn} onChange={(e) => setAnnouncedOn(e.target.value)} placeholder="2569-03-15" />
              </Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post('/finance/fee-schedules', {
                      academicYearId: yearId,
                      ...(level ? { level } : {}),
                      ...(studyYear ? { studyYear: Number(studyYear) } : {}),
                      ...(programId ? { programId } : {}),
                      ...(announcementNo.trim() ? { announcementNo: announcementNo.trim() } : {}),
                      ...(announcedOn.trim() ? { announcedOn: toGregorianIso(announcedOn.trim()) } : {}),
                    })
                  }
                  onDone={() => { setAnnouncementNo(''); setAnnouncedOn(''); schedules.reload(); }}
                >
                  สร้างโครงสร้าง
                </ActionButton>
              </div>
            </div>

            <AsyncView state={schedules} empty="ปีการศึกษานี้ยังไม่มีโครงสร้างค่าเทอม">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 34 }} />
                      <th style={{ width: 110 }}>ระดับ</th>
                      <th style={{ width: 90 }}>ชั้นปี</th>
                      <th>สาขา</th>
                      <th style={{ width: 140 }}>เลขที่ประกาศ</th>
                      <th className="num" style={{ width: 90 }}>รายการ</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((s) => (
                      <tr key={s.id}>
                        <td>
                          <input
                            type="radio" name="fee-schedule" style={{ width: 'auto' }}
                            checked={scheduleId === s.id} onChange={() => setScheduleId(s.id)}
                          />
                        </td>
                        <td>{s.level ? LEVEL_LABEL[s.level] ?? s.level : <em>ทุกระดับ</em>}</td>
                        <td>{s.study_year ?? <em>ทุกชั้นปี</em>}</td>
                        <td>{s.program_name ?? <em>ทุกสาขา</em>}</td>
                        <td>{s.announcement_no ?? '—'}</td>
                        <td className="num">{s.line_count}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </>
        )}
      </TableCard>

      {scheduleId && (
        <TableCard title="รายการในโครงสร้างที่เลือก">
          <div className="row">
            <Field label="รายการค่าธรรมเนียม">
              <AsyncView state={feeItems}>
                {(rows) => (
                  <select value={lineItemId} onChange={(e) => setLineItemId(e.target.value)}>
                    <option value="">— เลือกรายการ —</option>
                    {rows.map((r) => <option key={r.id} value={r.id}>{r.name_th}</option>)}
                  </select>
                )}
              </AsyncView>
            </Field>
            <Field label="งวด/ภาคเรียนที่">
              <select value={lineTerm} onChange={(e) => setLineTerm(e.target.value)}>
                {[1, 2, 3].map((n) => <option key={n} value={n}>{n}</option>)}
              </select>
            </Field>
            <Field label="จำนวนเงิน">
              <input value={lineAmount} onChange={(e) => setLineAmount(e.target.value)} inputMode="decimal" />
            </Field>
            <div className="shrink">
              <ActionButton
                className="primary"
                onRun={() => {
                  if (!lineItemId) throw new Error('เลือกรายการค่าธรรมเนียมก่อน');
                  return api.post(`/finance/fee-schedules/${scheduleId}/lines`, {
                    lines: [{ feeItemId: lineItemId, termOrdinal: Number(lineTerm), amount: Number(lineAmount) }],
                  });
                }}
                onDone={() => { setLineAmount(''); lines.reload(); schedules.reload(); }}
              >
                บันทึกราคา
              </ActionButton>
            </div>
          </div>
          <AsyncView state={lines} empty="โครงสร้างนี้ยังไม่มีรายการราคา">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th>รายการ</th>
                    <th style={{ width: 110 }}>งวด/ภาคเรียนที่</th>
                    <th className="num" style={{ width: 130 }}>จำนวนเงิน</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((l) => (
                    <tr key={l.id}>
                      <td>{l.fee_item_name}</td>
                      <td>{l.term_ordinal}</td>
                      <td className="num">{money(l.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>
      )}
    </>
  );
}

interface RetakeFeePolicy {
  fee_per_credit: string | null;
}

interface PendingRetakeCharge {
  id: string;
  amount: string;
  created_at: string;
  student_code: string;
  student_name: string;
  course_code: string;
  course_name: string;
}

/**
 * ค่าซ่อมรายวิชา (0093) — คนละบัญชีกับค่าเทอมโดยตั้งใจ (ดูคอมเมนต์ที่
 * migration) งานทะเบียนเป็นคนลงทะเบียนซ่อมและออกยอดที่หน้า "ลงทะเบียนเรียน"
 * ส่วนที่นี่เป็นที่เดียวที่ยืนยันว่าชำระแล้วหรือยกเว้น — ยืนยันแล้วชื่อ
 * นักศึกษาจึงจะขึ้นสมุดคะแนนของครูทันที
 */
function RetakeFeeCard() {
  const policy = useAsync(() => api.get<RetakeFeePolicy>('/retake-fee/policy'), []);
  const pending = useAsync(() => api.get<PendingRetakeCharge[]>('/retake-fee/pending'), []);
  const [rate, setRate] = useState('');

  return (
    <Card
      title="ค่าซ่อมรายวิชา"
      actions={
        <div className="row" style={{ gap: 8, alignItems: 'center' }}>
          <Field label="อัตรา/หน่วยกิต (บาท)">
            <input
              type="number" min={0}
              placeholder={policy.data?.fee_per_credit ?? 'ยังไม่ได้ตั้งค่า'}
              value={rate}
              onChange={(e) => setRate(e.target.value)}
              style={{ width: 120 }}
            />
          </Field>
          <div className="shrink">
            <ActionButton
              toast
              onRun={() => {
                if (!rate) throw new Error('กรอกอัตราก่อน');
                return api.post('/retake-fee/policy', { feePerCredit: Number(rate) });
              }}
              onDone={() => { setRate(''); policy.reload(); }}
            >
              บันทึกอัตรา
            </ActionButton>
          </div>
        </div>
      }
    >
      {!policy.loading && policy.data?.fee_per_credit == null && (
        <Notice kind="warn">
          ยังไม่ได้ตั้งอัตราค่าซ่อมต่อหน่วยกิต — งานทะเบียนจะลงทะเบียนซ่อมพร้อมออกยอดไม่ได้จนกว่าจะตั้งค่าที่นี่
        </Notice>
      )}
      <AsyncView state={pending} empty="ไม่มีรายการค่าซ่อมที่รอชำระ">
        {(rows) => (
          <table>
            <thead>
              <tr>
                <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                <th>ชื่อ — นามสกุล</th>
                <th>รายวิชา</th>
                <th className="num" style={{ width: 100 }}>ยอด</th>
                <th style={{ width: 190 }} />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <PendingRetakeRow key={r.id} row={r} onDone={() => pending.reload()} />
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </Card>
  );
}

function PendingRetakeRow({ row, onDone }: { row: PendingRetakeCharge; onDone: () => void }) {
  return (
    <tr>
      <td className="mono">{row.student_code}</td>
      <td>{row.student_name}</td>
      <td>{row.course_code} {row.course_name}</td>
      <td className="num">{money(row.amount)}</td>
      <td className="row" style={{ gap: 6 }}>
        <ActionButton
          className="primary"
          toast
          confirm={`ยืนยันว่านักศึกษาชำระค่าซ่อม ${money(row.amount)} บาทแล้ว — ชื่อจะขึ้นสมุดคะแนนของครูทันที`}
          onRun={() => api.post(`/retake-fee/${row.id}/confirm-payment`, { method: 'cash' })}
          onDone={onDone}
        >
          ยืนยันชำระแล้ว
        </ActionButton>
        <ActionButton
          toast
          onRun={() => {
            const note = window.prompt('ยกเว้นค่าซ่อมนี้ — ระบุเหตุผล');
            if (!note?.trim()) throw new Error('ต้องระบุเหตุผลที่ยกเว้น');
            return api.post(`/retake-fee/${row.id}/waive`, { note: note.trim() });
          }}
          onDone={onDone}
        >
          ยกเว้น
        </ActionButton>
      </td>
    </tr>
  );
}

interface LateFeePolicy {
  effective_from_year_be: number;
  grace_days: number;
  flat_amount: string;
  daily_amount: string;
  max_amount: string | null;
  hold_after_days: number;
  blocks_transcript_after_hold: boolean;
}

/**
 * นโยบายค้างชำระและการระงับสิทธิ์ (0094) — บล็อกพิมพ์ใบ รบ. เป็นทางเลือก
 * ที่ปิดโดยค่าเริ่มต้นเสมอ (หลัก 5ข) ต้องมากดเปิดเองที่นี่ วิทยาลัยที่ไม่ได้
 * ตั้งค่าอะไรเลยจะไม่มีใครถูกบล็อกพิมพ์ใบ รบ. แม้ค้างชำระเกินกำหนดจริง
 */
function LatePolicyCard() {
  const policy = useAsync(() => api.get<LateFeePolicy | null>('/finance/late-policy'), []);
  const [graceDays, setGraceDays] = useState('');
  const [holdAfterDays, setHoldAfterDays] = useState('');
  const [blocksTranscript, setBlocksTranscript] = useState(false);
  const [touched, setTouched] = useState(false);

  const p = policy.data;
  if (!touched && p && graceDays === '' && holdAfterDays === '') {
    // เติมค่าปัจจุบันให้ครั้งแรกที่โหลดเสร็จ เพื่อไม่ให้ฟิลด์ที่ไม่ได้แตะ
    // ถูกรีเซ็ตกลับไปเป็นค่าเริ่มต้นตอนบันทึก (ส่งครบทุกช่องเสมอ)
    setGraceDays(String(p.grace_days));
    setHoldAfterDays(String(p.hold_after_days));
    setBlocksTranscript(p.blocks_transcript_after_hold);
  }

  return (
    <Card title="นโยบายค้างชำระและการระงับสิทธิ์">
      {!policy.loading && !p && (
        <Notice kind="warn">ยังไม่ได้ตั้งนโยบายค้างชำระของสถานศึกษานี้ — ตั้งค่าด้านล่างเพื่อเริ่มใช้งาน</Notice>
      )}
      <div className="row" style={{ gap: 16, alignItems: 'flex-end', flexWrap: 'wrap' }}>
        <Field label="ผ่อนผัน (วัน)">
          <input type="number" min={0} value={graceDays} onChange={(e) => { setTouched(true); setGraceDays(e.target.value); }} style={{ width: 100 }} />
        </Field>
        <Field label="ระงับสิทธิ์เมื่อค้างเกิน (วัน)">
          <input type="number" min={0} value={holdAfterDays} onChange={(e) => { setTouched(true); setHoldAfterDays(e.target.value); }} style={{ width: 100 }} />
        </Field>
        <Field label="เมื่อระงับสิทธิ์แล้ว">
          <label className="row" style={{ gap: 6, alignItems: 'center' }}>
            <input
              type="checkbox"
              checked={blocksTranscript}
              onChange={(e) => { setTouched(true); setBlocksTranscript(e.target.checked); }}
            />
            บล็อกการพิมพ์ใบ รบ. ด้วย
          </label>
        </Field>
        <div className="shrink">
          <ActionButton
            toast
            onRun={() => {
              if (!graceDays || !holdAfterDays) throw new Error('กรอกจำนวนวันให้ครบก่อน');
              return api.post('/finance/late-policy', {
                effectiveFromYearBe: p?.effective_from_year_be ?? new Date().getFullYear() + 543,
                graceDays: Number(graceDays),
                holdAfterDays: Number(holdAfterDays),
                flatAmount: p ? Number(p.flat_amount) : undefined,
                dailyAmount: p ? Number(p.daily_amount) : undefined,
                maxAmount: p?.max_amount != null ? Number(p.max_amount) : undefined,
                blocksTranscriptAfterHold: blocksTranscript,
              });
            }}
            onDone={() => { setTouched(false); policy.reload(); }}
          >
            บันทึกนโยบาย
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

interface RevenueRow { method: string; count: number; amount: number }
interface Revenue { from: string | null; to: string | null; total: number; byMethod: RevenueRow[] }

/** รายงานรายรับ (0094) — นับเฉพาะเงินที่กระทบยอดแล้ว ไม่รวมรายการที่ยังค้างจับคู่ */
function RevenueReportCard() {
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const revenue = useAsync(() => api.get<Revenue>(`/finance/revenue${qs({ from: from || undefined, to: to || undefined })}`), [from, to]);

  return (
    <Card
      title="รายงานรายรับ"
      actions={
        <div className="row" style={{ gap: 8, alignItems: 'center' }}>
          <Field label="ตั้งแต่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label="ถึง"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
        </div>
      }
    >
      <AsyncView state={revenue}>
        {(r) => (
          <>
            <p style={{ fontSize: 20, fontWeight: 600, margin: '0 0 12px' }}>{money(r.total)} บาท</p>
            {r.byMethod.length === 0 ? (
              <p className="muted">ยังไม่มีรายรับที่กระทบยอดแล้วในช่วงนี้</p>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>ช่องทางชำระ</th>
                    <th className="num" style={{ width: 100 }}>จำนวนรายการ</th>
                    <th className="num" style={{ width: 160 }}>ยอดเงิน</th>
                  </tr>
                </thead>
                <tbody>
                  {r.byMethod.map((x) => (
                    <tr key={x.method}>
                      <td>{METHOD[x.method] ?? x.method}</td>
                      <td className="num">{x.count}</td>
                      <td className="num">{money(x.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </AsyncView>
    </Card>
  );
}

/**
 * ส่วนลด/ทุนรายคน — เจาะจงรายการได้ (0080) เช่น ลดเฉพาะค่าแรกเข้า ไม่แตะ
 * ค่าเทอม ต่างจากทุนที่ตั้งใจลดทั้งใบซึ่งเว้นช่องรายการว่างไว้ กดมอบแล้ว
 * ถือเป็นการอนุมัติทันที เพราะมีแค่ finance/registrar/director/admin
 * เท่านั้นที่กดถึงหน้านี้ได้ (บังคับซ้ำที่ฐานข้อมูลอีกชั้น)
 */
function StudentDiscountCard({ studentId, academicYearId }: { studentId: string; academicYearId: string }) {
  const funding = useAsync(() => api.get<StudentFundingRow[]>(`/finance/students/${studentId}/funding`), [studentId]);
  const sources = useAsync(() => api.get<FundingSource[]>('/finance/funding-sources'), []);
  const feeItems = useAsync(() => api.get<FeeItem[]>('/finance/fee-items'), []);

  const [sourceId, setSourceId] = useState('');
  const [feeItemId, setFeeItemId] = useState('');
  const [amountKind, setAmountKind] = useState<'percent' | 'amount'>('percent');
  const [value, setValue] = useState('');
  const [note, setNote] = useState('');

  const [newKind, setNewKind] = useState('scholarship');
  const [newName, setNewName] = useState('');

  return (
    <TableCard title="ส่วนลดและทุนของนักศึกษาคนนี้">
      <div className="row">
        <Field label="สร้างแหล่งทุน/ส่วนลดใหม่">
          <select value={newKind} onChange={(e) => setNewKind(e.target.value)}>
            {Object.entries(FUNDING_KIND).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
          </select>
        </Field>
        <Field label="ชื่อ">
          <input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="เช่น ทุนเรียนดี, ลดค่าแรกเข้า" />
        </Field>
        <div className="shrink">
          <ActionButton
            onRun={() => api.post('/finance/funding-sources', { kind: newKind, nameTh: newName.trim() })}
            onDone={() => { setNewName(''); sources.reload(); }}
          >
            เพิ่มแหล่งทุน
          </ActionButton>
        </div>
      </div>

      <div className="row">
        <Field label="แหล่งทุน/ส่วนลด">
          <AsyncView state={sources}>
            {(rows) => (
              <select value={sourceId} onChange={(e) => setSourceId(e.target.value)}>
                <option value="">— เลือก —</option>
                {rows.map((s) => <option key={s.id} value={s.id}>{s.name_th} ({FUNDING_KIND[s.kind] ?? s.kind})</option>)}
              </select>
            )}
          </AsyncView>
        </Field>
        <Field label="ลดเฉพาะรายการ (ว่าง = ลดทุกรายการในใบแจ้งหนี้)">
          <AsyncView state={feeItems}>
            {(rows) => (
              <select value={feeItemId} onChange={(e) => setFeeItemId(e.target.value)}>
                <option value="">— ลดทุกรายการ —</option>
                {rows.map((r) => <option key={r.id} value={r.id}>{r.name_th}</option>)}
              </select>
            )}
          </AsyncView>
        </Field>
        <Field label="รูปแบบ">
          <select value={amountKind} onChange={(e) => setAmountKind(e.target.value as 'percent' | 'amount')}>
            <option value="percent">เปอร์เซ็นต์</option>
            <option value="amount">จำนวนเงิน</option>
          </select>
        </Field>
        <Field label={amountKind === 'percent' ? 'ลดกี่ %' : 'ลดกี่บาท'}>
          <input value={value} onChange={(e) => setValue(e.target.value)} inputMode="decimal" />
        </Field>
        <Field label="หมายเหตุ (ถ้ามี)">
          <input value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!sourceId) throw new Error('เลือกแหล่งทุน/ส่วนลดก่อน');
              if (!value) throw new Error('ระบุจำนวนที่จะลดก่อน');
              return api.post(`/finance/students/${studentId}/funding`, {
                fundingSourceId: sourceId,
                academicYearId,
                ...(feeItemId ? { feeItemId } : {}),
                ...(amountKind === 'percent' ? { percentOff: Number(value) } : { amount: Number(value) }),
                ...(note.trim() ? { note: note.trim() } : {}),
              });
            }}
            onDone={() => { setValue(''); setNote(''); funding.reload(); }}
          >
            มอบส่วนลด
          </ActionButton>
        </div>
      </div>

      <AsyncView state={funding} empty="นักศึกษาคนนี้ยังไม่มีส่วนลดหรือทุนใด ๆ">
        {(rows) => (
          <table>
            <thead>
              <tr>
                <th>แหล่งทุน/ส่วนลด</th>
                <th>ลดเฉพาะรายการ</th>
                <th className="num" style={{ width: 110 }}>จำนวน</th>
                <th>หมายเหตุ</th>
                <th style={{ width: 90 }} />
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id}>
                  <td>{r.funding_name} <span className="hint">({FUNDING_KIND[r.kind] ?? r.kind})</span></td>
                  <td>{r.fee_item_name ?? <em>ทุกรายการ</em>}</td>
                  <td className="num">{r.percent_off != null ? `${r.percent_off}%` : money(r.amount ?? 0)}</td>
                  <td>{r.note ?? '—'}</td>
                  <td>
                    <ActionButton
                      className="ghost"
                      confirm="ถอนส่วนลดนี้มีผลกับใบแจ้งหนี้ที่จะออกครั้งต่อไป ยืนยันหรือไม่"
                      onRun={() => api.del(`/finance/students/${studentId}/funding/${r.id}`)}
                      onDone={() => funding.reload()}
                    >
                      ถอน
                    </ActionButton>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

/**
 * แปลงปี พ.ศ. ที่พิมพ์มาให้เป็น ค.ศ. ก่อนส่งเข้า API เสมอ
 *
 * ─── ทำไมต้องแปลงเอง ไม่ปล่อยให้พิมพ์ตามที่เห็น ───
 * `@IsISO8601()` ฝั่ง API ตรวจแค่รูปแบบตัวเลข ไม่ตรวจว่าปีสมเหตุสมผล —
 * "2569-08-20" ผ่านการตรวจและถูกบันทึกเป็นวันที่จริงในปี ค.ศ. 2569 (อีกกว่า
 * 500 ปีข้างหน้า) โดยไม่มี error ใด ๆ เลย ทั้งที่ทุกที่อื่นในระบบพิมพ์ปี พ.ศ.
 * เป็นเรื่องปกติ (หลักสไตล์ท้าย CLAUDE.md) — เจอเองตอนกดทดสอบปุ่มนี้จริง
 * ไม่ใช่ตอนอ่านโค้ด ปีที่พิมพ์เกิน 2400 แปลว่าเป็น พ.ศ. แน่นอน (ระบบนี้ยังไม่มี
 * วันไหนต้องเดินถึงปี ค.ศ. 2400)
 */
function toGregorianIso(raw: string): string {
  const m = raw.match(/^(\d{4})(-\d{2}-\d{2}.*)$/);
  if (!m) return raw;
  const year = Number(m[1]);
  return year > 2400 ? `${year - 543}${m[2]}` : raw;
}

/**
 * แปลงข้อความที่วางจากสเปรดชีตเป็นรายการเดินบัญชี — หนึ่งบรรทัดต่อหนึ่งรายการ
 * คั่นด้วยจุลภาค: วันที่ (พ.ศ. หรือ ค.ศ. ก็ได้ YYYY-MM-DD), จำนวนเงิน,
 * ชื่อผู้โอน, เลขอ้างอิงธนาคาร, ref1 (รหัสนักศึกษาถ้ามี), ref2
 */
function parseBankRows(text: string) {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [postedAt, amount, counterparty, bankRef, ref1, ref2] = line.split(',').map((s) => s.trim());
      if (!postedAt || !amount) throw new Error(`บรรทัดข้อมูลไม่ครบ: ${line}`);
      return {
        postedAt: toGregorianIso(postedAt),
        amount: Number(amount),
        ...(counterparty ? { counterparty } : {}),
        ...(bankRef ? { bankRef } : {}),
        ...(ref1 ? { ref1 } : {}),
        ...(ref2 ? { ref2 } : {}),
      };
    });
}

function BankImportCard({ onDone }: { onDone: () => void }) {
  const [text, setText] = useState('');
  const [result, setResult] = useState<ReconcileResult | null>(null);

  return (
    <Card title="นำเข้ารายการเดินบัญชีธนาคาร">
      <label className="field">
        <span>วางข้อมูลจากสเปรดชีต — บรรทัดละหนึ่งรายการ (วันที่พิมพ์ปี พ.ศ. หรือ ค.ศ. ก็ได้)</span>
        <textarea
          rows={4}
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder={'2569-08-20,4200,น.ส. สมหญิง ศรีสุข,BK-00123,69201010101\n2569-08-20,13.50,ไม่ทราบผู้โอน,BK-00124'}
          style={{ fontFamily: 'monospace', fontSize: 12.5 }}
        />
      </label>
      <div className="row" style={{ marginTop: 8 }}>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              const transactions = parseBankRows(text);
              if (transactions.length === 0) throw new Error('ยังไม่มีข้อมูลให้นำเข้า');
              return api.post<{ imported: number; skipped: number }>('/finance/bank-transactions', { transactions });
            }}
            onDone={() => setText('')}
          >
            นำเข้ารายการ
          </ActionButton>
        </div>
        <div className="shrink">
          <ActionButton
            onRun={() => api.post<ReconcileResult>('/finance/reconcile')}
            onDone={(r) => {
              setResult(r as ReconcileResult);
              onDone();
            }}
          >
            กระทบยอดอัตโนมัติ
          </ActionButton>
        </div>
        <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
          จับคู่เองเฉพาะที่มั่นใจสูง (เลขอ้างอิงตรง หรือรหัสนักศึกษา+ยอดตรงกับงวดที่ค้าง)
          ที่เหลือขึ้นเป็นรายการรอด้านล่างให้ยืนยันเอง
        </div>
      </div>
      {result && (
        <Notice kind="info">
          จับคู่เอง {result.autoMatched} รายการ · รอเจ้าหน้าที่ยืนยัน {result.suggested} รายการ ·
          ยังไม่พบข้อมูลพอ {result.unmatched} รายการ
        </Notice>
      )}
    </Card>
  );
}

function PendingMatchRow({
  row, students, onDone,
}: { row: PendingMatch; students: StudentRow[]; onDone: () => void }) {
  const [studentId, setStudentId] = useState('');
  const hasSuggestion = !!row.student_name;

  return (
    <tr>
      <td>{thaiDate(row.posted_at)}</td>
      <td className="num">{money(row.amount)}</td>
      <td>{row.counterparty ?? '—'}</td>
      <td>
        {hasSuggestion ? (
          <>
            {row.student_code} {row.student_name}
            <div className="hint">
              {row.confidence != null ? `${row.confidence} คะแนน — ` : ''}{row.match_reason ?? 'ยอดตรงกับใบแจ้งหนี้'}
            </div>
          </>
        ) : (
          <select value={studentId} onChange={(e) => setStudentId(e.target.value)} style={{ maxWidth: 220 }}>
            <option value="">— ไม่พบข้อมูลพอ เลือกนักศึกษาเอง —</option>
            {students.map((s) => (
              <option key={s.id} value={s.id}>{s.student_code} {s.full_name}</option>
            ))}
          </select>
        )}
      </td>
      <td style={{ width: 200 }}>
        <ActionButton
          className="primary"
          onRun={() => {
            if (!hasSuggestion && !studentId) throw new Error('เลือกนักศึกษาก่อน — ไม่มีข้อเสนอให้ยอมรับ');
            return api.post(`/finance/reconcile/${row.id}/confirm`, studentId ? { studentId } : {});
          }}
          onDone={onDone}
        >
          ยืนยัน
        </ActionButton>{' '}
        <ActionButton
          className="ghost"
          confirm="รายการนี้ไม่ใช่ค่าเทอม ยืนยันหรือไม่ — เก็บไว้ในประวัติแต่จะไม่ขึ้นให้ตัดสินใจอีก"
          onRun={() => api.post(`/finance/reconcile/${row.id}/ignore`)}
          onDone={onDone}
        >
          ไม่ใช่ค่าเทอม
        </ActionButton>
      </td>
    </tr>
  );
}

/**
 * หน้าการเงินแยกเป็นหน้าละงาน แบบเดียวกับ SISA ที่หนึ่งเมนูตอบหนึ่งคำถาม —
 * เดิมเก้าการ์ดอยู่หน้าเดียว ทุกเมนูในศูนย์การเงินจึงพามาเจอหน้าเดิม
 * แล้วผู้ใช้ต้องเลื่อนหาเอง ส่วนตัวการ์ดแต่ละใบไม่ได้เปลี่ยนเลย
 */
export const FINANCE_SECTIONS = {
  payments: { title: 'รับชำระเงิน', sub: 'เลือกนักศึกษา ดูยอดค้าง ออกใบแจ้งหนี้ และรับชำระ' },
  receipts: { title: 'ใบเสร็จรับเงิน', sub: 'ดูและพิมพ์ใบเสร็จย้อนหลังของนักศึกษา' },
  revenue: { title: 'รายงานรายรับ', sub: 'ยอดรับตามช่วงวันที่ แยกตามช่องทางการชำระ' },
  arrears: { title: 'ค้างชำระและระงับสิทธิ์', sub: 'ยอดลูกหนี้ตามอายุหนี้ และเงื่อนไขการระงับสิทธิ์' },
  fees: { title: 'ตั้งค่าค่าธรรมเนียม', sub: 'รายการค่าธรรมเนียม โครงสร้างค่าเทอม และค่าเรียนซ่อม' },
  discounts: { title: 'ทุนและส่วนลด', sub: 'แหล่งทุน และส่วนลดของนักศึกษารายคน' },
  bank: { title: 'นำเข้าและกระทบยอดธนาคาร', sub: 'นำเข้ารายการเดินบัญชี และจับคู่กับนักศึกษา' },
} as const;
export type FinanceSection = keyof typeof FINANCE_SECTIONS;

export function FinanceScreen({ section = 'payments' }: { section?: FinanceSection }) {
  const route = useRoute();
  const { terms, termId, term, setTerm } = useTermPicker();
  const aging = useAsync(() => api.get<AgingRow[]>('/finance/ar-aging'), []);
  const students = useAsync(() => api.get<StudentRow[]>('/students?limit=200'), []);
  const pending = useAsync(() => api.get<PendingMatch[]>('/finance/reconcile/pending'), []);

  /** เปิดตรงมาจากงานรับสมัคร (?studentId=) หลังขึ้นทะเบียนนักศึกษาใหม่แล้ว */
  const [studentId, setStudentId] = useState(route.query.get('studentId') ?? '');
  const [installments, setInstallments] = useState('2');
  const [amount, setAmount] = useState('');
  const [method, setMethod] = useState('cash');
  const [note, setNote] = useState('');
  /** ใบเสร็จของการรับเงินครั้งล่าสุด — สิ่งที่ต้องพิมพ์ให้คนที่ยืนรออยู่ */
  const [justIssued, setJustIssued] = useState<{ id: string; doc_no: string } | null>(null);

  const balance = useAsync(
    () =>
      studentId
        ? api.get<Balance>(`/students/${studentId}/balance`)
        : Promise.resolve(null as unknown as Balance),
    [studentId],
  );

  const receipts = useAsync(
    () =>
      studentId
        ? api.get<Receipt[]>(`/finance/receipts${qs({ studentId })}`)
        : Promise.resolve([]),
    [studentId],
  );

  /*
   * `/students?limit=200` ไม่รับประกันว่าจะมีนักศึกษาที่เพิ่งขึ้นทะเบียน
   * ใหม่อยู่ในสองร้อยแถวแรก (โดยเฉพาะวิทยาลัยที่มีนักศึกษาเกินสองร้อยคน
   * อยู่แล้ว) — ถ้าเปิดหน้านี้มาจากลิงก์ `?studentId=` ของงานรับสมัครแล้ว
   * ไม่เจอในรายการ ให้ดึงคนนั้นมาเพิ่มเป็นตัวเลือกเองแยกต่างหาก มิฉะนั้น
   * ช่องเลือกนักศึกษาจะโชว์ว่างเปล่าทั้งที่ข้อมูลด้านล่างโหลดถูกคนแล้วจริง
   */
  const alreadyInList = (students.data ?? []).some((s) => s.id === studentId);
  const deepLinkedStudent = useAsync(
    () =>
      studentId && !alreadyInList
        ? api.get<{ student_code: string; first_name_th: string; last_name_th: string }>(`/students/${studentId}`)
        : Promise.resolve(null),
    [studentId, alreadyInList],
  );
  /*
   * กรองซ้ำที่ตอนรวมรายการเสมอ ไม่ใช่พึ่ง alreadyInList ตัวเดียว — ตอน
   * `students.data` ยังไม่โหลดเสร็จตอนแรก alreadyInList เป็น false ทำให้
   * ไปดึงคนนี้มาซ้ำ แล้วพอ students.data โหลดเสร็จ (มีคนนี้อยู่แล้วจริง)
   * จะได้ตัวเลือกซ้ำ id เดียวกันในเฟรมเดียวกันชั่วขณะ (React เตือน key ซ้ำ)
   */
  const studentOptions: StudentRow[] = [
    ...(students.data ?? []),
    ...(deepLinkedStudent.data && !alreadyInList
      ? [{
          id: studentId,
          student_code: deepLinkedStudent.data.student_code,
          full_name: `${deepLinkedStudent.data.first_name_th} ${deepLinkedStudent.data.last_name_th}`,
        }]
      : []),
  ];

  const meta = FINANCE_SECTIONS[section];
  const needsTerm = section === 'payments' || section === 'discounts';

  return (
    <>
      <PageHead
        title={meta.title}
        sub={meta.sub}
        actions={
          needsTerm ? (
            <div style={{ width: 240 }}>
              <AsyncView state={terms}>
                {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
              </AsyncView>
            </div>
          ) : undefined
        }
      />

      {section === 'payments' && (
        <>
      <Card title="เลือกนักศึกษา">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>นักศึกษา</span>
            <AsyncView state={students}>
              {() => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {studentOptions.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.student_code} {s.full_name}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
      </Card>

          {studentId && (
            <>
          <Card title="ยอดของนักศึกษาคนนี้">
            <AsyncView state={balance}>
              {(b) => (
                <div className="row">
                  <Field label="ยอดเรียกเก็บ">
                    <input value={money(b.billed)} readOnly />
                  </Field>
                  <Field label="ชำระแล้ว">
                    <input value={money(b.paid)} readOnly />
                  </Field>
                  <Field label="คงค้าง">
                    <input value={money(b.outstanding)} readOnly />
                  </Field>
                  <Field label="กำหนดชำระถัดไป">
                    <input value={thaiDate(b.next_due_on)} readOnly />
                  </Field>
                  <Field label="เกินกำหนด">
                    <input value={b.days_overdue ? `${b.days_overdue} วัน` : '—'} readOnly />
                  </Field>
                </div>
              )}
            </AsyncView>
          </Card>

          <Card title="ออกใบแจ้งหนี้ของภาคเรียนที่เลือก">
            <div className="row">
              <Field label="จำนวนงวด">
                <select value={installments} onChange={(e) => setInstallments(e.target.value)}>
                  {[1, 2, 3, 4, 5, 6].map((n) => (
                    <option key={n} value={n}>{n} งวด</option>
                  ))}
                </select>
              </Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post('/finance/invoices', {
                      studentId,
                      termId,
                      installments: Number(installments),
                    })
                  }
                  onDone={() => balance.reload()}
                >
                  ออกใบแจ้งหนี้
                </ActionButton>
              </div>
              <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                ยอดมาจากโครงสร้างค่าธรรมเนียมของชั้นปีและปีการศึกษานั้น
                ไม่ใช่ตัวเลขที่กรอกเอง — เพื่อให้ตรงกับประกาศที่แจ้งไว้เสมอ
              </div>
            </div>
          </Card>

          <Card title="รับชำระเงิน">
            <div className="row">
              <Field label="จำนวนเงิน">
                <input value={amount} onChange={(e) => setAmount(e.target.value)} inputMode="decimal" />
              </Field>
              <Field label="ช่องทาง">
                <select value={method} onChange={(e) => setMethod(e.target.value)}>
                  {Object.entries(METHOD).map(([v, l]) => (
                    <option key={v} value={v}>{l}</option>
                  ))}
                </select>
              </Field>
              <Field label="หมายเหตุ (ถ้ามี)">
                <input value={note} onChange={(e) => setNote(e.target.value)} />
              </Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post<PaymentResult>('/finance/payments', {
                      studentId,
                      amount: Number(amount),
                      method,
                      ...(note.trim() ? { note: note.trim() } : {}),
                    })
                  }
                  onDone={(r) => {
                    setAmount('');
                    setNote('');
                    setJustIssued((r as PaymentResult).receipt);
                    balance.reload();
                    aging.reload();
                    receipts.reload();
                  }}
                >
                  บันทึกการรับชำระ
                </ActionButton>
              </div>
            </div>
            {/*
              ─── ไม่มีช่องให้กรอกเลขที่ใบเสร็จอีกแล้ว ───
              เลขออกจากสายเลขของสถานศึกษาตอนบันทึกการรับชำระ (0068) ของเดิม
              ให้พิมพ์เอง ซึ่งแปลว่าเลขซ้ำกันสองใบก็ได้ เว้นว่างก็ได้ และไม่มี
              อะไรผูกเลขนั้นกับกระดาษที่พิมพ์ออกไปเลย
            */}
            {justIssued && (
              <Notice kind="ok">
                <div className="row" style={{ alignItems: 'center' }}>
                  <span>
                    รับชำระแล้ว — ใบเสร็จเลขที่ <strong>{justIssued.doc_no}</strong>
                  </span>
                  <div className="shrink">
                    <PrintButton path={`/finance/receipts/${justIssued.id}/print`}>
                      พิมพ์ใบเสร็จ
                    </PrintButton>
                  </div>
                </div>
              </Notice>
            )}
          </Card>

          <Notice kind="info">
            เงินที่รับเข้ามาจะถูกตัดกับงวดที่ครบกำหนดก่อนเสมอตามลำดับที่
            ฐานข้อมูลกำหนด ไม่ใช่ให้เจ้าหน้าที่เลือกว่าจะตัดงวดไหน
          </Notice>
            </>
          )}
        </>
      )}

      {section === 'receipts' && (
        <>
      <Card title="เลือกนักศึกษา">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>นักศึกษา</span>
            <AsyncView state={students}>
              {() => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {studentOptions.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.student_code} {s.full_name}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
      </Card>

          {studentId && (
            <>
          <TableCard title="ใบเสร็จที่ออกให้นักศึกษาคนนี้">
            <AsyncView state={receipts} empty="ยังไม่เคยออกใบเสร็จให้นักศึกษาคนนี้">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 130 }}>เลขที่</th>
                      <th style={{ width: 130 }}>วันที่</th>
                      <th className="num" style={{ width: 120 }}>จำนวนเงิน</th>
                      <th>ตัวอักษร</th>
                      <th style={{ width: 130 }} />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.id} style={{ opacity: r.voided_at ? 0.55 : 1 }}>
                        <td className="mono">{r.doc_no}</td>
                        <td>{thaiDate(r.issued_on)}</td>
                        <td className="num">{money(r.amount)}</td>
                        <td>
                          {r.amount_text}
                          {r.voided_at && (
                            <>
                              {' '}
                              <Badge kind="danger">ยกเลิกแล้ว</Badge>
                              {r.void_reason ? ` — ${r.void_reason}` : ''}
                            </>
                          )}
                        </td>
                        <td>
                          {/*
                            พิมพ์ซ้ำอ่านจาก payload ที่ตรึงไว้ ไม่ได้ออกใบใหม่ —
                            เลขที่จึงไม่เดินและกระดาษที่ได้เหมือนใบแรกทุกตัวอักษร
                          */}
                          <PrintButton path={`/finance/receipts/${r.id}/print`}>
                            พิมพ์ซ้ำ
                          </PrintButton>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

            </>
          )}
        </>
      )}

      {section === 'discounts' && (
        <>
      <Card title="เลือกนักศึกษา">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>นักศึกษา</span>
            <AsyncView state={students}>
              {() => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {studentOptions.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.student_code} {s.full_name}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
      </Card>

          {studentId && (
            <>
          {term && <StudentDiscountCard studentId={studentId} academicYearId={term.academic_year_id} />}

            </>
          )}
        </>
      )}

      {section === 'revenue' && <RevenueReportCard />}

      {section === 'arrears' && (
        <>
      <TableCard
        title="ยอดลูกหนี้แยกตามอายุหนี้"
        actions={
          <ActionButton onRun={() => api.post('/finance/holds/refresh')} onDone={() => aging.reload()}>
            ปรับสถานะระงับสิทธิ์
          </ActionButton>
        }
      >
        <AsyncView state={aging} empty="ยังไม่มียอดค้างชำระ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th>ช่วงอายุหนี้</th>
                  <th className="num" style={{ width: 120 }}>จำนวนนักศึกษา</th>
                  <th className="num" style={{ width: 160 }}>ยอดเงิน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.bucket}>
                    <td>
                      <Badge kind={bucketKind(r.bucket)}>{r.bucket}</Badge>
                    </td>
                    <td className="num">{r.students}</td>
                    <td className="num">{money(r.amount)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <LatePolicyCard />
        </>
      )}

      {section === 'fees' && (
        <>
      <FeeScheduleSetupCard />
      <RetakeFeeCard />
        </>
      )}

      {section === 'bank' && (
        <>
      <BankImportCard onDone={() => pending.reload()} />

      <TableCard title="รายการรอกระทบยอด">
        <AsyncView state={pending} empty="ไม่มีรายการค้างให้ตัดสินใจ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 110 }}>วันที่</th>
                  <th className="num" style={{ width: 110 }}>จำนวนเงิน</th>
                  <th style={{ width: 160 }}>ผู้โอน</th>
                  <th>ข้อเสนอ</th>
                  <th style={{ width: 200 }} />
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <PendingMatchRow
                    key={r.id}
                    row={r}
                    students={students.data ?? []}
                    onDone={() => pending.reload()}
                  />
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

        </>
      )}
    </>
  );
}

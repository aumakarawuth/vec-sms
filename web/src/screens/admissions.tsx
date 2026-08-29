/**
 * งานรับสมัคร
 *
 * ─── ทำไมทุกอย่างที่นี่เป็นงานของเจ้าหน้าที่ ───
 * ยังไม่เปิดให้ผู้สมัครกรอกเอง เพราะการให้คนนอกสร้างใบสมัครได้ต้องมี
 * การยืนยันตัวตน การกันบอท และการจำกัดจำนวนคำขอที่ออกแบบแยกต่างหาก
 * เปิดก่อนแล้วค่อยคิดทีหลัง = เปิดช่องให้ยิงใบสมัครปลอม
 *
 * ─── ทำไมเลขบัตรประชาชนไม่โผล่กลับมา ───
 * ฐานข้อมูลเก็บเฉพาะค่าแฮช หน้าจอจึงกรอกได้แต่อ่านกลับไม่ได้ — ตั้งใจให้
 * เป็นแบบนั้นตาม PDPA ไม่ใช่ข้อมูลหาย
 *
 * ─── ทำไม "ขึ้นทะเบียน" อยู่ที่นี่ ไม่ใช่หน้าระเบียนนักศึกษา ───
 * `admit_applicant()` ต้องรู้จักใบสมัคร (เพื่อผูกกลับไปหาได้ว่านักศึกษาคนนี้
 * มาจากใบสมัครใบไหน) บริบทของใบสมัครมีครบอยู่แล้วตรงนี้ ไม่ต้องพิมพ์ค้นหาซ้ำ
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { fetchTerms } from '../core/catalog';
import { num, thaiDate } from '../core/fmt';
import { href } from '../core/router';
import type { Role } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useAsync, useCan,
} from '../ui/kit';

const ADMISSIONS_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];

interface Round {
  id: string;
  code: string;
  name_th: string;
  applies_from: string;
  applies_to: string;
  status: string;
  applications: number;
  enrolled: number;
}

interface Application {
  id: string;
  application_no: string;
  full_name: string;
  status: string;
  admitted_curriculum: string | null;
}

interface VersionOption {
  id: string;
  edition_be: number;
  curriculum_name: string;
  shift: string | null;
}

interface ApplicationDetail {
  id: string;
  application_no: string;
  first_name_th: string;
  last_name_th: string;
  phone: string | null;
  email: string | null;
  prior_school_th: string | null;
  prior_qualification_th: string | null;
  prior_gpax: string | null;
  student_id: string | null;
  father_first_name_th: string | null;
  father_last_name_th: string | null;
  father_occupation_th: string | null;
  father_phone: string | null;
  mother_first_name_th: string | null;
  mother_last_name_th: string | null;
  mother_occupation_th: string | null;
  mother_phone: string | null;
  choices: { preference: number; name_th: string; shift: string | null }[];
  documents: { kind: string; status: string; note: string | null }[];
}

const ROUND_STATUS: Record<string, { label: string; kind: 'default' | 'ok' | 'warn' | 'info' }> = {
  draft: { label: 'ร่าง', kind: 'default' },
  open: { label: 'เปิดรับสมัคร', kind: 'ok' },
  closed: { label: 'ปิดรับแล้ว', kind: 'warn' },
  announced: { label: 'ประกาศผลแล้ว', kind: 'info' },
  completed: { label: 'จบรอบ', kind: 'default' },
};

const APP_STATUS: Record<string, { label: string; kind: 'default' | 'ok' | 'warn' | 'danger' | 'info' }> = {
  draft: { label: 'ร่าง', kind: 'default' },
  submitted: { label: 'ยื่นแล้ว', kind: 'info' },
  passed: { label: 'ผ่านการคัดเลือก', kind: 'ok' },
  failed: { label: 'ไม่ผ่าน', kind: 'danger' },
  waitlisted: { label: 'สำรอง', kind: 'warn' },
  enrolled: { label: 'ขึ้นทะเบียนแล้ว', kind: 'ok' },
};

const DOC_STATUS: Record<string, string> = {
  pending: 'รอส่ง', received: 'ได้รับแล้ว', verified: 'ตรวจแล้ว', rejected: 'ไม่ผ่าน',
};

/** เปิดรอบรับสมัครใหม่ — ต้องมีปีการศึกษาก่อน ใช้รายการเดียวกับตัวเลือกภาคเรียนทั่วระบบ */
function CreateRoundCard({
  years, onDone,
}: { years: { id: string; year_be: number }[]; onDone: () => void }) {
  const [academicYearId, setAcademicYearId] = useState('');
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');
  const [appliesFrom, setAppliesFrom] = useState('');
  const [appliesTo, setAppliesTo] = useState('');
  const [examOn, setExamOn] = useState('');
  const [announceOn, setAnnounceOn] = useState('');

  return (
    <Card title="เปิดรอบรับสมัครใหม่">
      <div className="row">
        <Field label="ปีการศึกษา">
          <select value={academicYearId} onChange={(e) => setAcademicYearId(e.target.value)}>
            <option value="">— เลือกปีการศึกษา —</option>
            {years.map((y) => (
              <option key={y.id} value={y.id}>ปีการศึกษา {y.year_be}</option>
            ))}
          </select>
        </Field>
        <Field label="รหัสรอบ">
          <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น 2569-1" style={{ maxWidth: 120 }} />
        </Field>
        <Field label="ชื่อรอบ">
          <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น รอบโควตา 1/2569" />
        </Field>
      </div>
      <div className="row">
        <Field label="เปิดรับตั้งแต่">
          <input type="date" value={appliesFrom} onChange={(e) => setAppliesFrom(e.target.value)} />
        </Field>
        <Field label="ถึงวันที่">
          <input type="date" value={appliesTo} onChange={(e) => setAppliesTo(e.target.value)} />
        </Field>
        <Field label="วันสอบ/สัมภาษณ์ (ถ้ามี)">
          <input type="date" value={examOn} onChange={(e) => setExamOn(e.target.value)} />
        </Field>
        <Field label="วันประกาศผล (ถ้ามี)">
          <input type="date" value={announceOn} onChange={(e) => setAnnounceOn(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() =>
              api.post('/admissions/rounds', {
                academicYearId, code: code.trim(), nameTh: nameTh.trim(),
                appliesFrom, appliesTo,
                ...(examOn ? { examOn } : {}),
                ...(announceOn ? { announceOn } : {}),
              })
            }
            onDone={() => {
              setCode(''); setNameTh(''); setAppliesFrom(''); setAppliesTo('');
              setExamOn(''); setAnnounceOn('');
              onDone();
            }}
          >
            เปิดรอบ
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function QuotaCard({
  roundId, versions, onDone,
}: { roundId: string; versions: VersionOption[]; onDone: () => void }) {
  const [versionId, setVersionId] = useState('');
  const [seats, setSeats] = useState('40');
  const [note, setNote] = useState('');

  return (
    <Card title="ตั้งโควตาที่นั่ง">
      <div className="row">
        <label className="field" style={{ flex: 2 }}>
          <span>สาขา/หลักสูตร</span>
          <select value={versionId} onChange={(e) => setVersionId(e.target.value)}>
            <option value="">— เลือกสาขา —</option>
            {versions.map((v) => (
              <option key={v.id} value={v.id}>
                {v.curriculum_name} {v.shift ? `(${v.shift})` : ''} — ฉบับ {v.edition_be}
              </option>
            ))}
          </select>
        </label>
        <Field label="จำนวนที่นั่ง">
          <input type="number" min={1} value={seats} onChange={(e) => setSeats(e.target.value)} style={{ maxWidth: 100 }} />
        </Field>
        <Field label="หมายเหตุ (ถ้ามี)">
          <input value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() =>
              api.post(`/admissions/rounds/${roundId}/quotas`, {
                curriculumVersionId: versionId,
                seats: Number(seats),
                ...(note.trim() ? { note: note.trim() } : {}),
              })
            }
            onDone={() => { setNote(''); onDone(); }}
          >
            ตั้งโควตา
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

const GENDER: Record<string, string> = { male: 'ชาย', female: 'หญิง', other: 'อื่น ๆ', undisclosed: 'ไม่ระบุ' };

function CreateApplicationCard({
  roundId, versions, onDone,
}: { roundId: string; versions: VersionOption[]; onDone: () => void }) {
  const [prefixTh, setPrefixTh] = useState('');
  const [firstNameTh, setFirstNameTh] = useState('');
  const [lastNameTh, setLastNameTh] = useState('');
  const [nationalId, setNationalId] = useState('');
  const [phone, setPhone] = useState('');
  const [gender, setGender] = useState('');
  const [priorSchoolTh, setPriorSchoolTh] = useState('');
  const [priorGpax, setPriorGpax] = useState('');
  const [choice1, setChoice1] = useState('');
  const [choice2, setChoice2] = useState('');

  const [fatherFirstNameTh, setFatherFirstNameTh] = useState('');
  const [fatherLastNameTh, setFatherLastNameTh] = useState('');
  const [fatherOccupationTh, setFatherOccupationTh] = useState('');
  const [fatherIncomeMonthly, setFatherIncomeMonthly] = useState('');
  const [fatherPhone, setFatherPhone] = useState('');

  const [motherFirstNameTh, setMotherFirstNameTh] = useState('');
  const [motherLastNameTh, setMotherLastNameTh] = useState('');
  const [motherOccupationTh, setMotherOccupationTh] = useState('');
  const [motherIncomeMonthly, setMotherIncomeMonthly] = useState('');
  const [motherPhone, setMotherPhone] = useState('');

  const bad = nationalId !== '' && !/^\d{13}$/.test(nationalId);

  return (
    <Card title="รับใบสมัครใหม่ (กรอกจากใบสมัครกระดาษ)">
      <div className="row">
        <Field label="คำนำหน้า">
          <input value={prefixTh} onChange={(e) => setPrefixTh(e.target.value)} placeholder="นาย/นางสาว" style={{ maxWidth: 100 }} />
        </Field>
        <Field label="ชื่อ">
          <input value={firstNameTh} onChange={(e) => setFirstNameTh(e.target.value)} />
        </Field>
        <Field label="นามสกุล">
          <input value={lastNameTh} onChange={(e) => setLastNameTh(e.target.value)} />
        </Field>
        <Field label="เพศ">
          <select value={gender} onChange={(e) => setGender(e.target.value)}>
            <option value="">— ไม่ระบุ —</option>
            {Object.entries(GENDER).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field>
      </div>
      <div className="row">
        <Field label="เลขประจำตัวประชาชน (ถ้ามี)">
          <input
            value={nationalId}
            onChange={(e) => setNationalId(e.target.value.replace(/\D/g, '').slice(0, 13))}
            placeholder="13 หลัก"
          />
        </Field>
        <Field label="เบอร์โทร">
          <input value={phone} onChange={(e) => setPhone(e.target.value)} />
        </Field>
        <Field label="โรงเรียนเดิม">
          <input value={priorSchoolTh} onChange={(e) => setPriorSchoolTh(e.target.value)} />
        </Field>
        <Field label="GPAX เดิม">
          <input
            type="number" min={0} max={4} step={0.01}
            value={priorGpax} onChange={(e) => setPriorGpax(e.target.value)}
            style={{ maxWidth: 90 }}
          />
        </Field>
      </div>
      <div className="row">
        <label className="field" style={{ flex: 2 }}>
          <span>สาขาที่เลือกอันดับ 1</span>
          <select value={choice1} onChange={(e) => setChoice1(e.target.value)}>
            <option value="">— เลือกสาขา —</option>
            {versions.map((v) => (
              <option key={v.id} value={v.id}>
                {v.curriculum_name} {v.shift ? `(${v.shift})` : ''} — ฉบับ {v.edition_be}
              </option>
            ))}
          </select>
        </label>
        <label className="field" style={{ flex: 2 }}>
          <span>อันดับ 2 (ถ้ามี)</span>
          <select value={choice2} onChange={(e) => setChoice2(e.target.value)}>
            <option value="">— ไม่มี —</option>
            {versions.filter((v) => v.id !== choice1).map((v) => (
              <option key={v.id} value={v.id}>
                {v.curriculum_name} {v.shift ? `(${v.shift})` : ''} — ฉบับ {v.edition_be}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="row">
        <Field label="ชื่อบิดา"><input value={fatherFirstNameTh} onChange={(e) => setFatherFirstNameTh(e.target.value)} /></Field>
        <Field label="นามสกุลบิดา"><input value={fatherLastNameTh} onChange={(e) => setFatherLastNameTh(e.target.value)} /></Field>
        <Field label="อาชีพบิดา"><input value={fatherOccupationTh} onChange={(e) => setFatherOccupationTh(e.target.value)} /></Field>
        <Field label="รายได้บิดา/เดือน"><input type="number" min={0} value={fatherIncomeMonthly} onChange={(e) => setFatherIncomeMonthly(e.target.value)} style={{ maxWidth: 120 }} /></Field>
        <Field label="โทรบิดา"><input value={fatherPhone} onChange={(e) => setFatherPhone(e.target.value)} style={{ maxWidth: 130 }} /></Field>
      </div>
      <div className="row">
        <Field label="ชื่อมารดา"><input value={motherFirstNameTh} onChange={(e) => setMotherFirstNameTh(e.target.value)} /></Field>
        <Field label="นามสกุลมารดา"><input value={motherLastNameTh} onChange={(e) => setMotherLastNameTh(e.target.value)} /></Field>
        <Field label="อาชีพมารดา"><input value={motherOccupationTh} onChange={(e) => setMotherOccupationTh(e.target.value)} /></Field>
        <Field label="รายได้มารดา/เดือน"><input type="number" min={0} value={motherIncomeMonthly} onChange={(e) => setMotherIncomeMonthly(e.target.value)} style={{ maxWidth: 120 }} /></Field>
        <Field label="โทรมารดา"><input value={motherPhone} onChange={(e) => setMotherPhone(e.target.value)} style={{ maxWidth: 130 }} /></Field>
      </div>
      {bad && <Notice kind="error">เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก — เว้นว่างได้ถ้ายังไม่ทราบ</Notice>}
      <div className="row">
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!firstNameTh.trim() || !lastNameTh.trim()) throw new Error('ยังไม่ได้กรอกชื่อ-นามสกุล');
              if (!choice1) throw new Error('ยังไม่ได้เลือกสาขาอันดับ 1');
              const choices = [{ preference: 1, curriculumVersionId: choice1 }];
              if (choice2) choices.push({ preference: 2, curriculumVersionId: choice2 });
              return api.post<{ applicationNo: string }>('/admissions/applications', {
                roundId,
                ...(prefixTh.trim() ? { prefixTh: prefixTh.trim() } : {}),
                firstNameTh: firstNameTh.trim(),
                lastNameTh: lastNameTh.trim(),
                ...(nationalId ? { nationalId } : {}),
                ...(phone.trim() ? { phone: phone.trim() } : {}),
                ...(gender ? { gender } : {}),
                ...(priorSchoolTh.trim() ? { priorSchoolTh: priorSchoolTh.trim() } : {}),
                ...(priorGpax ? { priorGpax: Number(priorGpax) } : {}),
                ...(fatherFirstNameTh.trim() ? { fatherFirstNameTh: fatherFirstNameTh.trim() } : {}),
                ...(fatherLastNameTh.trim() ? { fatherLastNameTh: fatherLastNameTh.trim() } : {}),
                ...(fatherOccupationTh.trim() ? { fatherOccupationTh: fatherOccupationTh.trim() } : {}),
                ...(fatherIncomeMonthly ? { fatherIncomeMonthly: Number(fatherIncomeMonthly) } : {}),
                ...(fatherPhone.trim() ? { fatherPhone: fatherPhone.trim() } : {}),
                ...(motherFirstNameTh.trim() ? { motherFirstNameTh: motherFirstNameTh.trim() } : {}),
                ...(motherLastNameTh.trim() ? { motherLastNameTh: motherLastNameTh.trim() } : {}),
                ...(motherOccupationTh.trim() ? { motherOccupationTh: motherOccupationTh.trim() } : {}),
                ...(motherIncomeMonthly ? { motherIncomeMonthly: Number(motherIncomeMonthly) } : {}),
                ...(motherPhone.trim() ? { motherPhone: motherPhone.trim() } : {}),
                choices,
              });
            }}
            onDone={() => {
              setPrefixTh(''); setFirstNameTh(''); setLastNameTh(''); setNationalId('');
              setPhone(''); setGender(''); setPriorSchoolTh(''); setPriorGpax('');
              setChoice1(''); setChoice2('');
              setFatherFirstNameTh(''); setFatherLastNameTh(''); setFatherOccupationTh('');
              setFatherIncomeMonthly(''); setFatherPhone('');
              setMotherFirstNameTh(''); setMotherLastNameTh(''); setMotherOccupationTh('');
              setMotherIncomeMonthly(''); setMotherPhone('');
              onDone();
            }}
          >
            บันทึกใบสมัคร
          </ActionButton>
        </div>
        <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
          บันทึกแล้วยังเป็น "ร่าง" — ต้องกด "ยื่นใบสมัคร" ในตารางด้านล่างก่อนจึงจะพิจารณาผลได้
        </div>
      </div>
    </Card>
  );
}

/**
 * ตัดสิน "ผ่าน" — ต้องระบุสาขาที่ได้ด้วยเสมอ
 *
 * `decide_application()` ปฏิเสธ outcome='passed' ที่ไม่มี curriculumVersionId
 * เพราะต้องตรวจที่นั่งว่างของสาขานั้นในรอบนี้ก่อนเสมอ (กันรับเกินโควตา)
 * ปุ่ม "ผ่าน" เดิมส่งแค่ outcome จึงถูกฐานข้อมูลปฏิเสธทุกครั้งที่กด
 */
function DecidePassForm({
  applicationId, versions, onDone,
}: { applicationId: string; versions: VersionOption[]; onDone: () => void }) {
  const [versionId, setVersionId] = useState('');

  return (
    <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
      <select value={versionId} onChange={(e) => setVersionId(e.target.value)} style={{ width: 170 }}>
        <option value="">สาขาที่ได้ —</option>
        {versions.map((v) => (
          <option key={v.id} value={v.id}>{v.curriculum_name} — ฉบับ {v.edition_be}</option>
        ))}
      </select>
      <ActionButton
        className="primary"
        onRun={() => {
          if (!versionId) throw new Error('ต้องเลือกสาขาที่ได้ก่อน — โควตาผูกกับสาขา');
          return api.post(`/admissions/applications/${applicationId}/decision`, {
            outcome: 'passed', curriculumVersionId: versionId,
          });
        }}
        onDone={onDone}
      >
        ผ่าน
      </ActionButton>
    </span>
  );
}

/** ขึ้นทะเบียนเป็นนักศึกษา — ย้อนกลับไม่ได้ ต้องมีรหัสนักศึกษาและปีการศึกษาที่เข้า */
function AdmitForm({
  applicationId, years, onDone,
}: { applicationId: string; years: { id: string; year_be: number }[]; onDone: () => void }) {
  const [studentCode, setStudentCode] = useState('');
  const [academicYearId, setAcademicYearId] = useState('');
  const [groupCode, setGroupCode] = useState('');

  return (
    <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center', flexWrap: 'wrap' }}>
      <input
        value={studentCode} onChange={(e) => setStudentCode(e.target.value)}
        placeholder="รหัสนักศึกษาใหม่" style={{ width: 130 }}
      />
      <select value={academicYearId} onChange={(e) => setAcademicYearId(e.target.value)} style={{ width: 130 }}>
        <option value="">ปีที่เข้า —</option>
        {years.map((y) => <option key={y.id} value={y.id}>{y.year_be}</option>)}
      </select>
      <input
        value={groupCode} onChange={(e) => setGroupCode(e.target.value)}
        placeholder="ห้อง (ถ้ารู้)" style={{ width: 90 }}
      />
      <ActionButton
        className="primary"
        confirm="ขึ้นทะเบียนเป็นนักศึกษา — เป็นจุดที่ย้อนกลับไม่ได้ ยืนยันหรือไม่"
        onRun={() => {
          if (!studentCode.trim() || !academicYearId) throw new Error('ต้องมีรหัสนักศึกษาและปีการศึกษา');
          return api.post(`/admissions/applications/${applicationId}/admit`, {
            studentCode: studentCode.trim(),
            academicYearId,
            ...(groupCode.trim() ? { groupCode: groupCode.trim() } : {}),
          });
        }}
        onDone={onDone}
      >
        ขึ้นทะเบียน
      </ActionButton>
    </span>
  );
}

function ApplicationDetailCard({ id }: { id: string }) {
  const detail = useAsync(() => api.get<ApplicationDetail>(`/admissions/applications/${id}`), [id]);
  const [kind, setKind] = useState('');
  const [status, setStatus] = useState('received');

  return (
    <Card title="รายละเอียดใบสมัคร">
      <AsyncView state={detail}>
        {(d) => (
          <>
            <p className="hint">
              {d.first_name_th} {d.last_name_th} · {d.phone ?? 'ไม่มีเบอร์โทร'} ·
              {' '}โรงเรียนเดิม {d.prior_school_th ?? '—'} · GPAX เดิม {d.prior_gpax ?? '—'}
            </p>
            <p className="hint">
              อันดับที่เลือก: {d.choices.map((c) => `${c.preference}. ${c.name_th}`).join(' · ') || 'ยังไม่มี'}
            </p>
            <p className="hint">
              บิดา {[d.father_first_name_th, d.father_last_name_th].filter(Boolean).join(' ') || '—'}
              {d.father_occupation_th ? ` (${d.father_occupation_th})` : ''}
              {' · '}มารดา {[d.mother_first_name_th, d.mother_last_name_th].filter(Boolean).join(' ') || '—'}
              {d.mother_occupation_th ? ` (${d.mother_occupation_th})` : ''}
            </p>

            {d.student_id && (
              <Notice kind="ok">
                ขึ้นทะเบียนเป็นนักศึกษาแล้ว — บิดามารดาและวุฒิเดิมที่กรอกไว้ข้างต้นถูกคัดลอกเข้าแฟ้มนักศึกษาให้แล้วอัตโนมัติ{' '}
                <a href={href(`/finance?studentId=${d.student_id}`)}>ไปออกใบแจ้งหนี้ค่าเทอม ส่วนลด หรือทุน →</a>
              </Notice>
            )}

            <table>
              <thead>
                <tr><th>เอกสาร</th><th style={{ width: 120 }}>สถานะ</th><th>หมายเหตุ</th></tr>
              </thead>
              <tbody>
                {d.documents.length === 0 && (
                  <tr><td colSpan={3} className="empty">ยังไม่มีบันทึกเอกสาร</td></tr>
                )}
                {d.documents.map((doc) => (
                  <tr key={doc.kind}>
                    <td>{doc.kind}</td>
                    <td><Badge kind={doc.status === 'verified' ? 'ok' : doc.status === 'rejected' ? 'danger' : 'default'}>
                      {DOC_STATUS[doc.status] ?? doc.status}
                    </Badge></td>
                    <td>{doc.note ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            <div className="row" style={{ marginTop: 8 }}>
              <Field label="ชื่อเอกสาร">
                <input value={kind} onChange={(e) => setKind(e.target.value)} placeholder="เช่น สำเนาบัตรประชาชน" />
              </Field>
              <Field label="สถานะ">
                <select value={status} onChange={(e) => setStatus(e.target.value)}>
                  {Object.entries(DOC_STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </Field>
              <div className="shrink">
                <ActionButton
                  onRun={() => {
                    if (!kind.trim()) throw new Error('ยังไม่ได้กรอกชื่อเอกสาร');
                    return api.post(`/admissions/applications/${id}/documents`, { kind: kind.trim(), status });
                  }}
                  onDone={() => { setKind(''); detail.reload(); }}
                >
                  บันทึกเอกสาร
                </ActionButton>
              </div>
            </div>
          </>
        )}
      </AsyncView>
    </Card>
  );
}

export function AdmissionsScreen() {
  const canUse = useCan(...ADMISSIONS_ROLES);
  const rounds = useAsync(() => (canUse ? api.get<Round[]>('/admissions/rounds') : Promise.resolve([])), [canUse]);
  const terms = useAsync(() => (canUse ? fetchTerms() : Promise.resolve([])), [canUse]);
  const versions = useAsync(
    () => (canUse ? api.get<VersionOption[]>('/curriculum/versions') : Promise.resolve([])),
    [canUse],
  );
  const [roundId, setRoundId] = useState('');
  const [status, setStatus] = useState('');
  const [detailId, setDetailId] = useState('');

  const applications = useAsync(
    () =>
      canUse && roundId
        ? api.get<Application[]>(`/admissions/applications${qs({ roundId, status })}`)
        : Promise.resolve([]),
    [canUse, roundId, status],
  );
  const summary = useAsync(
    () =>
      canUse && roundId
        ? api.get<Record<string, unknown>[]>(`/admissions/rounds/${roundId}/summary`)
        : Promise.resolve([]),
    [canUse, roundId],
  );

  const round = rounds.data?.find((r) => r.id === roundId);
  const years = [...new Map(
    (terms.data ?? []).map((t) => [t.academic_year_id, { id: t.academic_year_id, year_be: t.year_be }]),
  ).values()].sort((a, b) => b.year_be - a.year_be);

  return (
    <>
      <PageHead title="งานรับสมัคร" sub={<a href={href('/registry')}>← ศูนย์งานทะเบียน</a>} />

      {!canUse ? (
        <RestrictedNotice roles={ADMISSIONS_ROLES} />
      ) : (
      <>
      <Notice kind="info">
        ทุกขั้นตอนที่นี่เป็นงานของเจ้าหน้าที่ — ยังไม่เปิดให้ผู้สมัครกรอกใบสมัครเอง
        เพราะต้องออกแบบการยืนยันตัวตนและการกันบอทก่อน
      </Notice>

      <CreateRoundCard years={years} onDone={() => rounds.reload()} />

      <TableCard title="รอบรับสมัคร">
        <AsyncView state={rounds} empty="ยังไม่เคยเปิดรอบรับสมัคร">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 34 }} />
                  <th style={{ width: 120 }}>รหัสรอบ</th>
                  <th>ชื่อรอบ</th>
                  <th style={{ width: 210 }}>ช่วงรับสมัคร</th>
                  <th className="num" style={{ width: 90 }}>ใบสมัคร</th>
                  <th className="num" style={{ width: 110 }}>ขึ้นทะเบียน</th>
                  <th style={{ width: 130 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => {
                  const st = ROUND_STATUS[r.status];
                  return (
                    <tr key={r.id}>
                      <td>
                        <input
                          type="radio"
                          name="round"
                          style={{ width: 'auto' }}
                          checked={roundId === r.id}
                          onChange={() => { setRoundId(r.id); setDetailId(''); }}
                        />
                      </td>
                      <td className="mono">{r.code}</td>
                      <td>{r.name_th}</td>
                      <td>
                        {thaiDate(r.applies_from)} – {thaiDate(r.applies_to)}
                      </td>
                      <td className="num">{r.applications}</td>
                      <td className="num">{r.enrolled}</td>
                      <td>
                        <Badge kind={st?.kind ?? 'default'}>{st?.label ?? r.status}</Badge>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {round && (
        <>
          <Card title={`เปลี่ยนสถานะรอบ — ${round.name_th}`}>
            <div className="row">
              {Object.entries(ROUND_STATUS)
                .filter(([k]) => k !== round.status)
                .map(([k, v]) => (
                  <div className="shrink" key={k}>
                    <ActionButton
                      confirm={`เปลี่ยนสถานะรอบเป็น "${v.label}" ยืนยันหรือไม่`}
                      onRun={() => api.post(`/admissions/rounds/${round.id}/status`, { status: k })}
                      onDone={() => rounds.reload()}
                    >
                      {v.label}
                    </ActionButton>
                  </div>
                ))}
            </div>
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              ลำดับสถานะบังคับที่ฐานข้อมูล — ข้ามขั้นไม่ได้แม้จะกดจากที่นี่
            </div>
          </Card>

          <TableCard title="สรุปโควตาที่นั่งของรอบนี้">
            <AsyncView state={summary} empty="ยังไม่ได้ตั้งโควตาที่นั่ง">
              {(rows) =>
                rows.length === 0 ? (
                  <div className="empty">ยังไม่ได้ตั้งโควตาที่นั่ง</div>
                ) : (
                  <table>
                    <thead>
                      <tr>
                        {Object.keys(rows[0] ?? {}).map((k) => (
                          <th key={k}>{k}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((r, i) => (
                        <tr key={i}>
                          {Object.keys(rows[0] ?? {}).map((k) => (
                            <td key={k}>
                              {typeof r[k] === 'number' ? num(r[k] as number, 0) : String(r[k] ?? '—')}
                            </td>
                          ))}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )
              }
            </AsyncView>
          </TableCard>

          <AsyncView state={versions}>
            {(vs) => <QuotaCard roundId={round.id} versions={vs} onDone={() => summary.reload()} />}
          </AsyncView>

          <AsyncView state={versions}>
            {(vs) => (
              <CreateApplicationCard
                roundId={round.id}
                versions={vs}
                onDone={() => applications.reload()}
              />
            )}
          </AsyncView>

          <Card>
            <div className="row">
              <Field label="กรองตามสถานะใบสมัคร">
                <select value={status} onChange={(e) => setStatus(e.target.value)}>
                  <option value="">ทุกสถานะ</option>
                  {Object.entries(APP_STATUS).map(([k, v]) => (
                    <option key={k} value={k}>{v.label}</option>
                  ))}
                </select>
              </Field>
            </div>
          </Card>

          <TableCard title="ใบสมัครในรอบนี้">
            <AsyncView state={applications} empty="ยังไม่มีใบสมัครในรอบนี้">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 150 }}>เลขที่ใบสมัคร</th>
                      <th style={{ width: 200 }}>ชื่อ — นามสกุล</th>
                      <th>สาขาที่รับเข้า</th>
                      <th style={{ width: 150 }}>สถานะ</th>
                      <th style={{ width: 330 }}>การทำงาน</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((a) => {
                      const st = APP_STATUS[a.status];
                      return (
                        <tr key={a.id}>
                          <td className="mono">{a.application_no}</td>
                          <td>{a.full_name}</td>
                          <td>{a.admitted_curriculum ?? '—'}</td>
                          <td>
                            <Badge kind={st?.kind ?? 'default'}>{st?.label ?? a.status}</Badge>
                          </td>
                          <td>
                            <span style={{ display: 'inline-flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
                              {a.status === 'draft' && (
                                <ActionButton
                                  className="primary"
                                  onRun={() => api.post(`/admissions/applications/${a.id}/submit`)}
                                  onDone={() => applications.reload()}
                                >
                                  ยื่นใบสมัคร
                                </ActionButton>
                              )}
                              {a.status === 'submitted' && (
                                <>
                                  <AsyncView state={versions}>
                                    {(vs) => (
                                      <DecidePassForm
                                        applicationId={a.id}
                                        versions={vs}
                                        onDone={() => applications.reload()}
                                      />
                                    )}
                                  </AsyncView>
                                  <ActionButton
                                    onRun={() =>
                                      api.post(`/admissions/applications/${a.id}/decision`, { outcome: 'waitlisted' })
                                    }
                                    onDone={() => applications.reload()}
                                  >
                                    สำรอง
                                  </ActionButton>
                                  <ActionButton
                                    className="danger"
                                    onRun={() =>
                                      api.post(`/admissions/applications/${a.id}/decision`, { outcome: 'failed' })
                                    }
                                    onDone={() => applications.reload()}
                                  >
                                    ไม่ผ่าน
                                  </ActionButton>
                                </>
                              )}
                              {a.status === 'passed' && (
                                <AdmitForm
                                  applicationId={a.id}
                                  years={years}
                                  onDone={() => applications.reload()}
                                />
                              )}
                              {!['draft', 'submitted', 'passed'].includes(a.status) && a.status !== 'enrolled' && '—'}
                              <button className="ghost" onClick={() => setDetailId(detailId === a.id ? '' : a.id)}>
                                {detailId === a.id ? 'ซ่อนรายละเอียด' : 'รายละเอียด'}
                              </button>
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

          {detailId && <ApplicationDetailCard id={detailId} />}

          <Notice kind="warn">
            <strong>ขึ้นทะเบียนเป็นนักศึกษาเป็นจุดที่ย้อนกลับไม่ได้</strong> —
            `admit_applicant()` เป็นจุดเดียวที่ผู้สมัครกลายเป็นนักศึกษา
            และสร้างระเบียนถาวรทันที
          </Notice>
        </>
      )}
      </>
      )}
    </>
  );
}

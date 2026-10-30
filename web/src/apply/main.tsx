import { StrictMode, useEffect, useRef, useState, type FormEvent } from 'react';
import { createRoot } from 'react-dom/client';
import { API_BASE, INSTITUTION_ID } from '../core/api';
import './apply.css';

/**
 * หน้าสมัครเรียนออนไลน์ — หน้าเดียวที่คนนอกใช้ได้โดยไม่ต้องล็อกอิน
 *
 * ─── ทำไมไม่ใช้ core/api.ts ตัวเต็ม ───
 * ตัวนั้นผูกกับ token และการต่ออายุของเจ้าหน้าที่ หน้านี้ไม่มีทั้งสองอย่าง
 * และต้องไม่มี — ใช้แค่ค่าคงที่ที่ตั้งตอน build (วิทยาลัยเดียวต่อหนึ่งชุด
 * จึงไม่มีทางเห็นรายชื่อวิทยาลัยอื่น)
 *
 * ─── รหัสลับไม่เก็บลงเครื่อง ───
 * เครื่องที่ผู้สมัครใช้มักเป็นเครื่องในห้องคอมของโรงเรียนเดิม การจำรหัสไว้
 * ให้แปลว่าคนถัดไปเปิดดูและแก้ใบของคนก่อนได้ ผู้สมัครต้องจด/แคปจอเอง
 */

type Program = { curriculumVersionId: string; name: string; shift: string };
type Round = {
  id: string; name: string; appliesFrom: string; appliesTo: string;
  examOn: string | null; announceOn: string | null; programs: Program[];
};
type Form = Record<string, string>;
type View = {
  application_no: string; full_name: string; round_name: string; status: string;
  submitted_at: string; exam_on: string | null; announce_on: string | null;
  report_from: string | null; report_to: string | null; admitted_curriculum: string | null;
  choices: { preference: number; curriculum_version_id: string; curriculum_th: string; shift: string }[];
  editable: boolean; form: Record<string, string | number | null> | null;
};

const STATUS: Record<string, string> = {
  submitted: 'ยื่นใบสมัครแล้ว — รอประกาศผล',
  passed: 'ผ่านการคัดเลือก',
  failed: 'ไม่ผ่านการคัดเลือก',
  waitlisted: 'อยู่ในลำดับสำรอง',
  withdrawn: 'สละสิทธิ์',
  enrolled: 'มอบตัวเป็นนักศึกษาแล้ว',
};
const SHIFT: Record<string, string> = { morning: 'ภาคเช้า', afternoon: 'ภาคบ่าย', evening: 'ภาคค่ำ', weekend: 'เสาร์-อาทิตย์' };
const PREFIXES = ['นาย', 'นางสาว', 'เด็กชาย', 'เด็กหญิง', 'นาง'];
const QUALIFICATIONS = ['มัธยมศึกษาปีที่ 3', 'มัธยมศึกษาปีที่ 6', 'ปวช.', 'อื่น ๆ'];
const CHANNELS = ['เพื่อน/รุ่นพี่', 'ครูแนะแนว', 'Facebook/โซเชียล', 'เว็บไซต์วิทยาลัย', 'ป้าย/ใบปลิว', 'ผู้ปกครอง', 'อื่น ๆ'];

const thaiDate = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString('th-TH', { day: 'numeric', month: 'long', year: 'numeric' }) : '—';

async function call<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, body === undefined ? {} : {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    if (res.status === 429 && !data?.message?.includes('รอ')) {
      throw new Error('มีคำขอจากเครือข่ายนี้มากเกินไป กรุณารอสักครู่แล้วลองใหม่');
    }
    const m = data?.message;
    throw new Error(Array.isArray(m) ? m.join(' · ') : m ?? `เกิดข้อผิดพลาด (${res.status})`);
  }
  return data as T;
}

/** ช่องกรอกของฟอร์มเป็น camelCase ตาม DTO ส่วนข้อมูลที่คืนมาเป็น snake_case ตามฐานข้อมูล */
const camel = (s: string) => s.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());

function body(form: Form, choices: string[]) {
  const out: Record<string, unknown> = { choices: choices.filter(Boolean) };
  for (const [k, v] of Object.entries(form)) {
    if (v.trim() === '') continue;
    out[k] = k === 'priorGpax' ? Number(v) : v.trim();
  }
  return out;
}

function ApplicantFields({ form, set, programs, choices, setChoices }: {
  form: Form; set: (k: string, v: string) => void;
  programs: Program[]; choices: string[]; setChoices: (c: string[]) => void;
}) {
  const field = (k: string, label: string, opts: { type?: string; required?: boolean; list?: string[]; wide?: boolean; inputMode?: 'numeric' | 'tel' | 'email' | 'decimal' } = {}) => (
    <label className={opts.wide ? 'wide' : ''}>
      <span>{label}{opts.required && <b> *</b>}</span>
      {opts.list ? (
        <select value={form[k] ?? ''} required={opts.required} onChange={(e) => set(k, e.target.value)}>
          <option value="">— เลือก —</option>
          {opts.list.map((x) => <option key={x}>{x}</option>)}
        </select>
      ) : (
        <input type={opts.type ?? 'text'} inputMode={opts.inputMode} value={form[k] ?? ''}
               required={opts.required} onChange={(e) => set(k, e.target.value)} />
      )}
    </label>
  );
  const pick = (i: number, v: string) => {
    const next = [...choices];
    next[i] = v;
    setChoices(next);
  };
  return (
    <>
      <fieldset>
        <legend>สาขาที่ต้องการเรียน</legend>
        {[0, 1, 2].map((i) => (
          <label key={i} className="wide">
            <span>อันดับ {i + 1}{i === 0 && <b> *</b>}</span>
            <select value={choices[i] ?? ''} required={i === 0} onChange={(e) => pick(i, e.target.value)}>
              <option value="">{i === 0 ? '— เลือกสาขา —' : '— ไม่เลือก —'}</option>
              {programs
                .filter((p) => p.curriculumVersionId === choices[i] || !choices.includes(p.curriculumVersionId))
                .map((p) => (
                  <option key={p.curriculumVersionId} value={p.curriculumVersionId}>
                    {p.name} ({SHIFT[p.shift] ?? p.shift})
                  </option>
                ))}
            </select>
          </label>
        ))}
      </fieldset>

      <fieldset>
        <legend>ข้อมูลผู้สมัคร</legend>
        {field('prefixTh', 'คำนำหน้า', { list: PREFIXES })}
        {field('firstNameTh', 'ชื่อ', { required: true })}
        {field('lastNameTh', 'นามสกุล', { required: true })}
        {field('birthDate', 'วันเกิด', { type: 'date', required: true })}
        {field('phone', 'เบอร์โทรศัพท์', { required: true, inputMode: 'tel' })}
        {field('email', 'อีเมล', { type: 'email', inputMode: 'email' })}
        {field('addressTh', 'ที่อยู่ที่ติดต่อได้', { wide: true })}
      </fieldset>

      <fieldset>
        <legend>การศึกษาเดิม</legend>
        {field('priorSchoolTh', 'โรงเรียนเดิม', { wide: true })}
        {field('priorQualificationTh', 'วุฒิการศึกษา', { list: QUALIFICATIONS })}
        {field('priorGpax', 'เกรดเฉลี่ยสะสม', { inputMode: 'decimal' })}
      </fieldset>

      <fieldset>
        <legend>ผู้ปกครอง</legend>
        {field('fatherFirstNameTh', 'ชื่อบิดา')}
        {field('fatherLastNameTh', 'นามสกุลบิดา')}
        {field('fatherOccupationTh', 'อาชีพบิดา')}
        {field('fatherPhone', 'เบอร์โทรบิดา', { inputMode: 'tel' })}
        {field('motherFirstNameTh', 'ชื่อมารดา')}
        {field('motherLastNameTh', 'นามสกุลมารดา')}
        {field('motherOccupationTh', 'อาชีพมารดา')}
        {field('motherPhone', 'เบอร์โทรมารดา', { inputMode: 'tel' })}
      </fieldset>

      <fieldset>
        <legend>อื่น ๆ</legend>
        {field('referralSource', 'รู้จักวิทยาลัยจากช่องทางใด', { list: CHANNELS })}
      </fieldset>
    </>
  );
}

function ApplyForm({ onDone }: { onDone: (r: { applicationNo: string; secret: string }) => void }) {
  const [rounds, setRounds] = useState<Round[] | null>(null);
  const [roundId, setRoundId] = useState('');
  const [form, setForm] = useState<Form>({});
  const [choices, setChoices] = useState<string[]>([]);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const startedAt = useRef(Date.now());
  const honeypot = useRef<HTMLInputElement>(null);

  useEffect(() => {
    call<Round[]>(`/apply/rounds?institutionId=${INSTITUTION_ID}`)
      .then((r) => { setRounds(r); if (r.length === 1 && r[0]) setRoundId(r[0].id); })
      .catch((e: Error) => setError(e.message));
  }, []);

  const round = rounds?.find((r) => r.id === roundId);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      const res = await call<{ applicationNo: string; secret: string }>('/apply/applications', {
        ...body(form, choices), institutionId: INSTITUTION_ID, roundId,
        homepageUrl: honeypot.current?.value ?? '', startedAt: startedAt.current,
      });
      onDone(res);
    } catch (err) {
      setError((err as Error).message);
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } finally {
      setBusy(false);
    }
  }

  if (!rounds) return <p className="muted">{error || 'กำลังโหลด…'}</p>;
  if (rounds.length === 0) {
    return <div className="card"><h2>ยังไม่เปิดรับสมัครในขณะนี้</h2><p className="muted">โปรดติดตามประกาศของวิทยาลัย</p></div>;
  }

  return (
    <form onSubmit={submit} className="card">
      {error && <div className="error" role="alert">{error}</div>}
      <label className="wide">
        <span>รอบรับสมัคร<b> *</b></span>
        <select value={roundId} required onChange={(e) => { setRoundId(e.target.value); setChoices([]); }}>
          <option value="">— เลือกรอบ —</option>
          {rounds.map((r) => (
            <option key={r.id} value={r.id}>{r.name} (ถึง {thaiDate(r.appliesTo)})</option>
          ))}
        </select>
      </label>
      {round && (
        <>
          <p className="muted">
            {round.examOn && <>สอบ/สัมภาษณ์ {thaiDate(round.examOn)} · </>}
            {round.announceOn && <>ประกาศผล {thaiDate(round.announceOn)}</>}
          </p>
          <fieldset>
            <legend>เลขประจำตัวประชาชน</legend>
            <label className="wide">
              <span>เลข 13 หลัก<b> *</b></span>
              <input inputMode="numeric" autoComplete="off" required value={form.nationalId ?? ''}
                     onChange={(e) => setForm({ ...form, nationalId: e.target.value })} />
            </label>
            <p className="muted small">ใช้กันการสมัครซ้ำเท่านั้น — วิทยาลัยเก็บเป็นค่าที่ย้อนกลับเป็นเลขไม่ได้ และแก้ภายหลังไม่ได้</p>
          </fieldset>
          <ApplicantFields form={form} set={(k, v) => setForm({ ...form, [k]: v })}
                           programs={round.programs} choices={choices} setChoices={setChoices} />
          {/* ช่องดักบอท — ซ่อนจากคนทั้งสายตาและโปรแกรมอ่านหน้าจอ */}
          <div className="hp" aria-hidden="true">
            <label>เว็บไซต์ <input ref={honeypot} name="homepage_url" tabIndex={-1} autoComplete="off" /></label>
          </div>
          <p className="muted small">
            ไม่ต้องแนบเอกสาร — นำหลักฐานตัวจริง (บัตรประชาชน · ใบแสดงผลการเรียน · รูปถ่าย) มาแสดงในวันมอบตัว
          </p>
          <button type="submit" disabled={busy}>{busy ? 'กำลังส่ง…' : 'ส่งใบสมัคร'}</button>
        </>
      )}
    </form>
  );
}

function Done({ applicationNo, secret }: { applicationNo: string; secret: string }) {
  return (
    <div className="card">
      <h2>ส่งใบสมัครเรียบร้อยแล้ว</h2>
      <p>จดหรือถ่ายภาพหน้าจอนี้ไว้ — ใช้ดูสถานะและแก้ไขใบสมัคร <b>รหัสลับจะแสดงครั้งเดียวเท่านั้น</b></p>
      <dl className="secret">
        <dt>เลขที่ใบสมัคร</dt><dd>{applicationNo}</dd>
        <dt>รหัสลับ</dt><dd>{secret}</dd>
      </dl>
      <p className="muted small">ถ้าทำรหัสหาย ติดต่องานทะเบียนพร้อมบัตรประชาชน</p>
      <a href="#status" className="button">ไปหน้าดูสถานะ</a>
    </div>
  );
}

function Status() {
  const [cred, setCred] = useState({ applicationNo: '', secret: '' });
  const [view, setView] = useState<View | null>(null);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<Form>({});
  const [choices, setChoices] = useState<string[]>([]);
  const [programs, setPrograms] = useState<Program[]>([]);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  async function lookup(e: FormEvent) {
    e.preventDefault();
    setError(''); setNote(''); setBusy(true);
    try {
      setView(await call<View>('/apply/status', { institutionId: INSTITUTION_ID, ...cred }));
    } catch (err) {
      setView(null);
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function startEdit() {
    if (!view?.form) return;
    const f: Form = {};
    for (const [k, v] of Object.entries(view.form)) {
      if (v !== null) f[camel(k)] = k === 'birth_date' ? String(v).slice(0, 10) : String(v);
    }
    setForm(f);
    setChoices(view.choices.map((c) => c.curriculum_version_id));
    // สาขาที่เลือกได้มาจากรอบที่ยังเปิดอยู่ — ใบที่แก้ได้แปลว่ารอบยังเปิด
    const rounds = await call<Round[]>(`/apply/rounds?institutionId=${INSTITUTION_ID}`).catch(() => []);
    const r = rounds.find((x) => x.name === view.round_name);
    setPrograms(r?.programs ?? view.choices.map((c) => ({
      curriculumVersionId: c.curriculum_version_id, name: c.curriculum_th, shift: c.shift,
    })));
    setEditing(true);
  }

  async function save(e: FormEvent) {
    e.preventDefault();
    setError(''); setBusy(true);
    try {
      const v = await call<View>('/apply/applications/update', {
        ...body(form, choices), institutionId: INSTITUTION_ID, ...cred,
      });
      setView(v);
      setEditing(false);
      setNote('บันทึกการแก้ไขแล้ว');
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <form onSubmit={lookup} className="card">
        <h2>ดูสถานะใบสมัคร</h2>
        <label className="wide"><span>เลขที่ใบสมัคร</span>
          <input required value={cred.applicationNo} autoComplete="off"
                 onChange={(e) => setCred({ ...cred, applicationNo: e.target.value })} /></label>
        <label className="wide"><span>รหัสลับ</span>
          <input required value={cred.secret} autoComplete="off" autoCapitalize="characters"
                 onChange={(e) => setCred({ ...cred, secret: e.target.value })} /></label>
        <button type="submit" disabled={busy}>ดูสถานะ</button>
      </form>
      {error && <div className="error" role="alert">{error}</div>}
      {note && <div className="ok">{note}</div>}
      {view && !editing && (
        <div className="card">
          <h2>{view.full_name}</h2>
          <p className={`status s-${view.status}`}>{STATUS[view.status] ?? view.status}</p>
          {view.admitted_curriculum && <p>สาขาที่ได้: <b>{view.admitted_curriculum}</b></p>}
          <dl>
            <dt>เลขที่ใบสมัคร</dt><dd>{view.application_no}</dd>
            <dt>รอบ</dt><dd>{view.round_name}</dd>
            <dt>ยื่นเมื่อ</dt><dd>{thaiDate(view.submitted_at)}</dd>
            <dt>สาขาที่เลือก</dt>
            <dd>{view.choices.map((c) => <div key={c.preference}>{c.preference}. {c.curriculum_th}</div>)}</dd>
            {view.exam_on && <><dt>สอบ/สัมภาษณ์</dt><dd>{thaiDate(view.exam_on)}</dd></>}
            {view.announce_on && <><dt>ประกาศผล</dt><dd>{thaiDate(view.announce_on)}</dd></>}
            {view.report_from && <><dt>มอบตัว</dt><dd>{thaiDate(view.report_from)} – {thaiDate(view.report_to)}</dd></>}
          </dl>
          {view.editable
            ? <button type="button" onClick={startEdit}>แก้ไขใบสมัคร</button>
            : <p className="muted small">ใบสมัครนี้แก้ไขทางออนไลน์ไม่ได้แล้ว — ถ้าต้องแก้ ติดต่องานทะเบียน</p>}
        </div>
      )}
      {view && editing && (
        <form onSubmit={save} className="card">
          <h2>แก้ไขใบสมัคร {view.application_no}</h2>
          <p className="muted small">เลขประจำตัวประชาชนแก้ทางออนไลน์ไม่ได้</p>
          <ApplicantFields form={form} set={(k, v) => setForm({ ...form, [k]: v })}
                           programs={programs} choices={choices} setChoices={setChoices} />
          <div className="row">
            <button type="submit" disabled={busy}>บันทึก</button>
            <button type="button" className="secondary" onClick={() => setEditing(false)}>ยกเลิก</button>
          </div>
        </form>
      )}
    </>
  );
}

function App() {
  const [hash, setHash] = useState(location.hash);
  const [done, setDone] = useState<{ applicationNo: string; secret: string } | null>(null);
  useEffect(() => {
    const on = () => setHash(location.hash);
    addEventListener('hashchange', on);
    return () => removeEventListener('hashchange', on);
  }, []);
  const status = hash === '#status';
  return (
    <main>
      <header>
        <h1>สมัครเรียนออนไลน์</h1>
        <nav>
          <a href="#" className={status ? '' : 'active'}>สมัครเรียน</a>
          <a href="#status" className={status ? 'active' : ''}>ดูสถานะ / แก้ไขใบสมัคร</a>
        </nav>
      </header>
      {status ? <Status /> : done ? <Done {...done} /> : <ApplyForm onDone={setDone} />}
    </main>
  );
}

const root = document.getElementById('root');
if (!root) throw new Error('ไม่พบ #root ใน apply.html');
createRoot(root).render(<StrictMode><App /></StrictMode>);

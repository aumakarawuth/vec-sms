/**
 * เข้าสู่ระบบสำหรับเจ้าหน้าที่ — รวมทุกขั้นไว้ในหน้าจอเดียว
 *
 * ล็อกอิน → (ยืนยันสองชั้น) → (ตั้งค่า MFA ครั้งแรก) → (เปลี่ยนรหัสผ่าน)
 *
 * ─── ทำไมขั้นตั้งค่า MFA ต้องอยู่ในหน้านี้ ───
 * บทบาท admin/director ถูกบังคับยืนยันสองชั้นตั้งแต่ครั้งแรกที่เข้าระบบ
 * ถ้าไม่มีทางผูกแอป authenticator จากหน้าล็อกอิน คนกลุ่มนั้นจะได้แต่
 * challenge token ซึ่งเรียกเส้นทางอื่นไม่ได้เลย — วงจรปิดสนิท
 */
import { useState, type FormEvent } from 'react';
import { useSession } from '../core/session';
import { ApiError } from '../core/api';
import { Field, Notice } from '../ui/kit';

function errorText(e: unknown): string {
  return e instanceof ApiError ? e.message : 'ทำรายการไม่สำเร็จ';
}

export function LoginScreen() {
  const s = useSession();

  return (
    <div className="login-wrap">
      <div className="login-box">
        <h1>ระบบบริหารวิทยาลัย</h1>
        <div className="sub">
          {s.stage === 'anonymous' && 'สำหรับเจ้าหน้าที่ของวิทยาลัย'}
          {s.stage === 'mfa' && 'ยืนยันตัวตนขั้นที่สอง'}
          {s.stage === 'mfa-enroll' && 'ตั้งค่าการยืนยันสองชั้นครั้งแรก'}
          {s.stage === 'must-change' && 'ตั้งรหัสผ่านใหม่ก่อนเริ่มใช้งาน'}
        </div>

        {s.stage === 'anonymous' && <PasswordStep />}
        {s.stage === 'mfa' && <CodeStep />}
        {s.stage === 'mfa-enroll' && <EnrollStep />}
        {s.stage === 'must-change' && <ChangeStep />}
      </div>
    </div>
  );
}

function PasswordStep() {
  const { signIn } = useSession();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!username.trim() || !password) {
      setError('กรอกชื่อผู้ใช้และรหัสผ่าน');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await signIn(username.trim(), password);
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit}>
      {error && <Notice kind="error">{error}</Notice>}
      <Field label="ชื่อผู้ใช้">
        <input
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          autoFocus
          autoComplete="username"
        />
      </Field>
      <Field label="รหัสผ่าน">
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          autoComplete="current-password"
        />
      </Field>
      <button className="primary" disabled={busy}>
        {busy ? 'กำลังเข้าสู่ระบบ…' : 'เข้าสู่ระบบ'}
      </button>
    </form>
  );
}

function CodeStep() {
  const { verifyMfa } = useSession();
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await verifyMfa(code.trim());
    } catch (err) {
      setError(errorText(err));
      setCode('');
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit}>
      {error && <Notice kind="error">{error}</Notice>}
      <Field label="รหัสหกหลักจากแอป authenticator">
        <input
          className="otp"
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\s/g, ''))}
          inputMode="numeric"
          maxLength={12}
          autoFocus
        />
      </Field>
      <button className="primary" disabled={busy || code.length < 6}>
        {busy ? 'กำลังตรวจ…' : 'ยืนยัน'}
      </button>
      <p style={{ fontSize: 11.5, color: 'var(--ink-soft)', marginBottom: 0 }}>
        ใช้รหัสกู้คืนแทนได้ถ้าเครื่องที่ผูกไว้หาย
      </p>
    </form>
  );
}

function EnrollStep() {
  const { startEnroll, confirmEnroll, enrollUri } = useSession();
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const secret = enrollUri ? new URL(enrollUri).searchParams.get('secret') : null;

  if (!enrollUri) {
    return (
      <>
        {error && <Notice kind="error">{error}</Notice>}
        <Notice kind="info">
          บทบาทของคุณต้องยืนยันตัวตนสองชั้นทุกครั้งที่เข้าระบบ
          ผูกแอป authenticator ก่อนใช้งานครั้งแรก
        </Notice>
        <button
          className="primary"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            setError(null);
            try {
              await startEnroll();
            } catch (err) {
              setError(errorText(err));
            } finally {
              setBusy(false);
            }
          }}
        >
          {busy ? 'กำลังสร้าง…' : 'เริ่มตั้งค่า'}
        </button>
      </>
    );
  }

  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        setError(null);
        try {
          await confirmEnroll(code.trim());
        } catch (err) {
          setError(errorText(err));
          setCode('');
        } finally {
          setBusy(false);
        }
      }}
    >
      {error && <Notice kind="error">{error}</Notice>}
      <p style={{ fontSize: 12, marginTop: 0 }}>
        เพิ่มบัญชีในแอป authenticator ด้วยความลับนี้ แล้วกรอกรหัสที่แอปแสดง
      </p>
      <div className="secret">{secret}</div>
      <div style={{ height: 10 }} />
      <Field label="รหัสหกหลักจากแอป">
        <input
          className="otp"
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\s/g, ''))}
          inputMode="numeric"
          maxLength={6}
          autoFocus
        />
      </Field>
      <button className="primary" disabled={busy || code.length < 6}>
        {busy ? 'กำลังยืนยัน…' : 'ยืนยันและเข้าใช้งาน'}
      </button>
    </form>
  );
}

function ChangeStep() {
  const { changePassword } = useSession();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        if (next.length < 8) {
          setError('รหัสผ่านใหม่ต้องยาวอย่างน้อย 8 ตัวอักษร');
          return;
        }
        if (next !== again) {
          setError('รหัสผ่านใหม่สองช่องไม่ตรงกัน');
          return;
        }
        setBusy(true);
        setError(null);
        try {
          await changePassword(current, next);
        } catch (err) {
          setError(errorText(err));
        } finally {
          setBusy(false);
        }
      }}
    >
      {error && <Notice kind="error">{error}</Notice>}
      <Notice kind="warn">
        บัญชีนี้ใช้รหัสผ่านที่งานทะเบียนออกให้ ต้องตั้งรหัสของตัวเองก่อนใช้งาน
      </Notice>
      <Field label="รหัสผ่านปัจจุบัน">
        <input type="password" value={current} onChange={(e) => setCurrent(e.target.value)} autoFocus />
      </Field>
      <Field label="รหัสผ่านใหม่">
        <input type="password" value={next} onChange={(e) => setNext(e.target.value)} />
      </Field>
      <Field label="ยืนยันรหัสผ่านใหม่">
        <input type="password" value={again} onChange={(e) => setAgain(e.target.value)} />
      </Field>
      <button className="primary" disabled={busy}>
        {busy ? 'กำลังบันทึก…' : 'บันทึกและเข้าใช้งาน'}
      </button>
    </form>
  );
}

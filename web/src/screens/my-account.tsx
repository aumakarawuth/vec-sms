/**
 * ข้อมูลส่วนตัวของผู้ใช้ — SISA "ข้อมูลส่วนตัว › การตั้งค่าส่วนตัว"
 *
 * เปลี่ยนรหัสผ่านเอง · ดูสถานะยืนยันตัวตนสองชั้น · ดูว่าใครเข้าถึงข้อมูลของตน
 * ทั้งสามเส้นทางมีใน API อยู่แล้ว (/auth/change-password · /auth/mfa/status ·
 * /audit/me) แต่ไม่เคยมีหน้าจอ — เปลี่ยนรหัสผ่านได้เฉพาะตอนถูกบังคับเปลี่ยน
 * ครั้งแรก ผู้ใช้ที่สงสัยว่ารหัสรั่วจึงต้องไปขอให้งานทะเบียนออกรหัสรีเซ็ตให้
 */
import { useState } from 'react';
import { api } from '../core/api';
import { ROLE_LABEL, useSession } from '../core/session';
import { AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface MfaStatus { enrolled: boolean; confirmed: boolean; recoveryCodesRemaining: number }
interface AccessRow { action: string; entity: string; route: string | null; actor_role: string | null; occurred_at: string; actor_name: string | null }

const ACTION: Record<string, string> = { read: 'เปิดดู', create: 'สร้าง', update: 'แก้ไข', delete: 'ลบ', export: 'ส่งออก', login: 'เข้าระบบ' };

export function MyAccountScreen() {
  const s = useSession();
  const mfa = useAsync(() => api.get<MfaStatus>('/auth/mfa/status'), []);
  const access = useAsync(() => api.get<AccessRow[]>('/audit/me'), []);
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [again, setAgain] = useState('');
  const [msg, setMsg] = useState<{ kind: 'ok' | 'error'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);

  async function change() {
    setMsg(null);
    if (next.length < 8) return setMsg({ kind: 'error', text: 'รหัสผ่านใหม่ต้องยาวอย่างน้อย 8 ตัวอักษร' });
    if (next !== again) return setMsg({ kind: 'error', text: 'รหัสผ่านใหม่ทั้งสองช่องไม่ตรงกัน' });
    setBusy(true);
    try {
      await s.changePassword(current, next);
      setCurrent(''); setNext(''); setAgain('');
      setMsg({ kind: 'ok', text: 'เปลี่ยนรหัสผ่านแล้ว — ใช้รหัสใหม่ตั้งแต่การเข้าระบบครั้งถัดไป' });
    } catch (e) {
      setMsg({ kind: 'error', text: e instanceof Error ? e.message : 'เปลี่ยนรหัสผ่านไม่สำเร็จ' });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHead title="ข้อมูลส่วนตัว" sub="บัญชีผู้ใช้ รหัสผ่าน การยืนยันตัวตนสองชั้น และประวัติการเข้าถึงข้อมูลของคุณ" />

      <Card title="บัญชีผู้ใช้">
        <div className="row">
          <Field label="ชื่อผู้ใช้"><input value={s.username ?? ''} readOnly /></Field>
          <Field label="บทบาท">
            <input value={(s.roles.length ? s.roles : s.role ? [s.role] : []).map((r) => ROLE_LABEL[r] ?? r).join(' · ')} readOnly />
          </Field>
        </div>
      </Card>

      <Card title="เปลี่ยนรหัสผ่าน">
        {msg && <Notice kind={msg.kind}>{msg.text}</Notice>}
        <div className="row">
          <Field label="รหัสผ่านปัจจุบัน"><input type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} /></Field>
          <Field label="รหัสผ่านใหม่ (อย่างน้อย 8 ตัว)"><input type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} /></Field>
          <Field label="ยืนยันรหัสผ่านใหม่"><input type="password" autoComplete="new-password" value={again} onChange={(e) => setAgain(e.target.value)} /></Field>
          <div className="shrink">
            <button className="primary" disabled={busy || !current || !next} onClick={() => void change()}>
              {busy ? 'กำลังบันทึก…' : 'เปลี่ยนรหัสผ่าน'}
            </button>
          </div>
        </div>
      </Card>

      <Card title="การยืนยันตัวตนสองชั้น (MFA)">
        <AsyncView state={mfa}>
          {(m) => (
            m.confirmed ? (
              <p>
                <Badge kind="ok">เปิดใช้อยู่</Badge> รหัสสำรองที่ยังไม่ได้ใช้เหลือ {m.recoveryCodesRemaining} รหัส
                {m.recoveryCodesRemaining <= 2 && <> — <strong>ใกล้หมดแล้ว</strong> ถ้าทำอุปกรณ์หายจะเข้าระบบไม่ได้</>}
              </p>
            ) : (
              <p><Badge>ยังไม่ได้เปิด</Badge> บทบาทผู้อำนวยการและผู้ดูแลระบบถูกบังคับเปิดตอนเข้าระบบครั้งแรก</p>
            )
          )}
        </AsyncView>
      </Card>

      <TableCard title="ใครเข้าถึงข้อมูลของคุณบ้าง (ล่าสุด 200 รายการ)">
        <AsyncView state={access} empty="ยังไม่มีใครเข้าถึงข้อมูลส่วนบุคคลของคุณ">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 150 }}>เวลา</th>
                  <th>ผู้เข้าถึง</th>
                  <th style={{ width: 90 }}>การกระทำ</th>
                  <th>ข้อมูล</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r, i) => (
                  <tr key={i}>
                    <td>{new Date(r.occurred_at).toLocaleString('th-TH', { dateStyle: 'short', timeStyle: 'short' })}</td>
                    <td>{r.actor_name ?? '—'}{r.actor_role ? <small className="muted"> · {r.actor_role}</small> : null}</td>
                    <td>{ACTION[r.action] ?? r.action}</td>
                    <td className="mono" style={{ fontSize: 12 }}>{r.entity}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}

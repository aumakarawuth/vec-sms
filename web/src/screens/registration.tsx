/**
 * ลงทะเบียนเรียน — งานที่ทำกับคนทั้งห้องพร้อมกัน
 *
 * ─── ทำไมต้องแสดงผลรายคน ไม่ใช่ "สำเร็จ/ไม่สำเร็จ" ───
 * `register_courses_bulk()` ตั้งใจไม่ raise เมื่อมีคนติดเงื่อนไข เพราะ
 * rollback จะล้างงานของคนที่ผ่านไปด้วย — คนหนึ่งค้างค่าเทอมต้องไม่ทำให้
 * ทั้งห้องลงทะเบียนไม่ได้ หน้าจอจึงต้องแสดงว่าใครติดอะไรเป็นรายคน
 * มิฉะนั้นเจ้าหน้าที่จะไม่รู้ว่าต้องตามใคร
 */
import { useState } from 'react';
import { api } from '../core/api';
import { fetchSections, type Section } from '../core/catalog';
import { num } from '../core/fmt';
import { AsyncView, Badge, Card, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermDates, TermSelect, useTermPicker } from '../ui/term-picker';

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
  status: string;
}

interface BulkResult {
  requested: number;
  succeeded: number;
  blocked: number;
  results: { studentId: string; registered: number; blockers: string[] }[];
}

interface CheckResult {
  canRegister: boolean;
  blockingCount: number;
  warningCount: number;
  problems: {
    code: string;
    severity: 'block' | 'warn' | 'info';
    message_th: string;
    waived: boolean;
  }[];
}

export function RegistrationScreen() {
  const { terms, termId, term, setTerm } = useTermPicker();

  const sections = useAsync(
    () => (termId ? fetchSections(termId) : Promise.resolve([])),
    [termId],
  );
  const students = useAsync(() => api.get<StudentRow[]>('/students?limit=200'), []);

  const [pickedSections, setPickedSections] = useState<Set<string>>(new Set());
  const [pickedStudents, setPickedStudents] = useState<Set<string>>(new Set());
  const [result, setResult] = useState<BulkResult | null>(null);
  const [check, setCheck] = useState<CheckResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const toggle = (set: Set<string>, id: string) => {
    const next = new Set(set);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    return next;
  };

  const chosen = (sections.data ?? []).filter((s) => pickedSections.has(s.id));
  const credits = chosen.reduce((sum, s) => sum + Number(s.credits), 0);

  async function runCheck() {
    const first = [...pickedStudents][0];
    if (!first || !termId) return;
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      setCheck(
        await api.post<CheckResult>('/registration/check', {
          studentId: first,
          termId,
          sectionIds: [...pickedSections],
        }),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ตรวจไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  async function register() {
    if (!termId) return;
    setBusy(true);
    setError(null);
    setCheck(null);
    try {
      const r = await api.post<BulkResult>('/registration/register-bulk', {
        studentIds: [...pickedStudents],
        termId,
        sectionIds: [...pickedSections],
      });
      setResult(r);
      sections.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ลงทะเบียนไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  const byId = new Map((students.data ?? []).map((s) => [s.id, s]));

  return (
    <>
      <PageHead
        title="ลงทะเบียนเรียน"
        sub={term && <TermDates term={term} />}
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(list) => <TermSelect terms={list} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      {error && <Notice kind="error">{error}</Notice>}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, alignItems: 'start' }}>
        {/* ─── กลุ่มเรียน ─────────────────────────────────────── */}
        <TableCard
          title={`กลุ่มเรียน — เลือกแล้ว ${chosen.length} วิชา ${num(credits)} หน่วยกิต`}
        >
          <AsyncView state={sections} empty="ภาคเรียนนี้ยังไม่มีกลุ่มเรียน">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 34 }} />
                    <th style={{ width: 110 }}>รหัสวิชา</th>
                    <th>ชื่อวิชา</th>
                    <th className="num" style={{ width: 60 }}>นก.</th>
                    <th style={{ width: 130 }}>ครูผู้สอน</th>
                    <th className="num" style={{ width: 80 }}>ลงแล้ว</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((s: Section) => {
                    const full = Number(s.enrolled) >= s.capacity;
                    return (
                      <tr key={s.id}>
                        <td>
                          <input
                            type="checkbox"
                            style={{ width: 'auto' }}
                            checked={pickedSections.has(s.id)}
                            disabled={s.is_locked}
                            onChange={() => setPickedSections((p) => toggle(p, s.id))}
                          />
                        </td>
                        <td className="mono">{s.code}</td>
                        <td>
                          {s.name_th}
                          {s.is_locked && ' (ล็อกแล้ว)'}
                        </td>
                        <td className="num">{num(s.credits)}</td>
                        <td>{s.teacher_name || '—'}</td>
                        <td className="num">
                          <Badge kind={full ? 'danger' : 'default'}>
                            {s.enrolled}/{s.capacity}
                          </Badge>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>

        {/* ─── นักศึกษา ───────────────────────────────────────── */}
        <TableCard
          title={`นักศึกษา — เลือกแล้ว ${pickedStudents.size} คน`}
          actions={
            <button
              className="link"
              onClick={() =>
                setPickedStudents((p) =>
                  p.size === (students.data?.length ?? 0)
                    ? new Set()
                    : new Set((students.data ?? []).map((s) => s.id)),
                )
              }
            >
              {pickedStudents.size === (students.data?.length ?? 0) ? 'ล้างทั้งหมด' : 'เลือกทั้งหมด'}
            </button>
          }
        >
          <AsyncView state={students}>
            {(rows) => (
              <div style={{ maxHeight: 420, overflowY: 'auto' }}>
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 34 }} />
                      <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                      <th>ชื่อ — นามสกุล</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((s) => (
                      <tr key={s.id}>
                        <td>
                          <input
                            type="checkbox"
                            style={{ width: 'auto' }}
                            checked={pickedStudents.has(s.id)}
                            onChange={() => setPickedStudents((p) => toggle(p, s.id))}
                          />
                        </td>
                        <td className="mono">{s.student_code}</td>
                        <td>{s.full_name}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </AsyncView>
        </TableCard>
      </div>

      <Card>
        <div className="row">
          <div className="shrink">
            <button
              disabled={busy || pickedStudents.size !== 1 || pickedSections.size === 0}
              onClick={() => void runCheck()}
              title="ตรวจได้ทีละคน — เลือกนักศึกษาหนึ่งคนเพื่อดูรายละเอียดก่อนลง"
            >
              ตรวจเงื่อนไขก่อน
            </button>
          </div>
          <div className="shrink">
            <button
              className="primary"
              disabled={busy || pickedStudents.size === 0 || pickedSections.size === 0}
              onClick={() => void register()}
            >
              {busy
                ? 'กำลังลงทะเบียน…'
                : `ลงทะเบียน ${pickedStudents.size} คน × ${chosen.length} วิชา`}
            </button>
          </div>
          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            เพดานหน่วยกิตและวิชาบังคับก่อนถูกตรวจที่ฐานข้อมูลเสมอ
            ต่อให้กดจากหน้าจอนี้ก็ข้ามไม่ได้
          </div>
        </div>
      </Card>

      {check && (
        <Card title={`ผลตรวจ — ${check.canRegister ? 'ลงทะเบียนได้' : 'ยังลงไม่ได้'}`}>
          {check.problems.length === 0 ? (
            <Notice kind="ok">ไม่มีเงื่อนไขติดขัด</Notice>
          ) : (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>ระดับ</th>
                  <th>รายละเอียด</th>
                </tr>
              </thead>
              <tbody>
                {check.problems.map((p, i) => (
                  <tr key={`${p.code}-${i}`}>
                    <td>
                      <Badge kind={p.severity === 'block' ? 'danger' : p.severity === 'warn' ? 'warn' : 'info'}>
                        {p.severity === 'block' ? 'ติดขัด' : p.severity === 'warn' ? 'เตือน' : 'ข้อมูล'}
                        {p.waived && ' (ยกเว้นแล้ว)'}
                      </Badge>
                    </td>
                    <td style={{ whiteSpace: 'normal' }}>{p.message_th}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      )}

      {result && (
        <TableCard
          title={`ผลลงทะเบียน — สำเร็จ ${result.succeeded} คน · ติดเงื่อนไข ${result.blocked} คน`}
        >
          <table>
            <thead>
              <tr>
                <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                <th style={{ width: 180 }}>ชื่อ — นามสกุล</th>
                <th className="num" style={{ width: 90 }}>ลงได้</th>
                <th>ติดอะไร</th>
              </tr>
            </thead>
            <tbody>
              {result.results.map((r) => {
                const s = byId.get(r.studentId);
                return (
                  <tr key={r.studentId}>
                    <td className="mono">{s?.student_code ?? '—'}</td>
                    <td>{s?.full_name ?? '—'}</td>
                    <td className="num">
                      <Badge kind={r.registered > 0 ? 'ok' : 'danger'}>{r.registered} วิชา</Badge>
                    </td>
                    <td style={{ whiteSpace: 'normal' }}>
                      {r.blockers.length === 0 ? '—' : r.blockers.join(' · ')}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </TableCard>
      )}
    </>
  );
}

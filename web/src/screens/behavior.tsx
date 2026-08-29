/**
 * พฤติกรรม คัดกรอง และเยี่ยมบ้าน
 *
 * ─── ทำไมหน้านี้ต้องมี ───
 * ตาราง `behavior_record`/`screening_result`/`home_visit` มีมาตั้งแต่ต้น
 * แต่ไม่เคยมีทางเขียนเลย ตารางจึงว่างตลอด และระเบียนสะสม (ปพ.8) กับ
 * ใบรับรองความประพฤติที่อ่านจากตารางเหล่านี้ก็ว่างตามโดยไม่มีอะไรฟ้อง
 *
 * ─── ทำไมแสดงยอดใหม่ทันทีหลังบันทึก ───
 * คนบันทึกต้องรู้ตรงนั้นเลยว่าหักครั้งนี้แล้วนักศึกษาตกเกณฑ์หรือยัง
 * ถ้าต้องกดเข้าไปดูอีกหน้า คนที่รีบจะไม่กด แล้วเคสที่ควรส่งต่องานปกครอง
 * จะค้างอยู่ในหัวคนบันทึกคนเดียว
 *
 * ─── ทำไมไม่มีปุ่มแก้บันทึก ───
 * การแก้สิ่งที่บันทึกไปแล้วเป็นการเปลี่ยนหลักฐาน ฐานข้อมูลเปิดให้เฉพาะ
 * งานปกครองและผู้บริหาร**ลบ**ได้ ซึ่งเห็นจากภายนอกว่ามีการลบเกิดขึ้น
 * ต่างจากการแก้ตัวเลขเงียบ ๆ ที่ไม่มีใครรู้
 */
import { useEffect, useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDate, thaiDateTime } from '../core/fmt';
import { href } from '../core/router';
import { useSession } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync,
} from '../ui/kit';

interface Rule {
  id: string;
  code: string;
  name_th: string;
  direction: string;
  points: number;
  triggers_action: string | null;
  active: boolean;
}

interface Status {
  balance: number;
  starting_points: number;
  warn_below: number;
  critical_below: number;
  band: string;
  deduct_count: number;
  award_count: number;
  last_record_on: string | null;
}

interface Record_ {
  id: string;
  occurred_on: string;
  points: number;
  detail: string | null;
  document_no: string | null;
  recorded_at: string;
  code: string | null;
  rule_th: string | null;
  direction: string | null;
  recorded_by_name: string | null;
}

interface WatchRow {
  student_id: string;
  student_code: string;
  full_name: string;
  balance: number;
  band: string;
  deduct_count: number;
  last_record_on: string | null;
}

interface Screening {
  id: string;
  instrument: string;
  assessed_on: string;
  band: string;
  score: number | null;
  assessed_by_name: string | null;
}

interface HomeVisit {
  id: string;
  visited_on: string;
  findings: string | null;
  follow_up: string | null;
  visited_by_name: string | null;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

const BAND: Record<string, { label: string; kind: 'ok' | 'warn' | 'danger' }> = {
  ok: { label: 'ปกติ', kind: 'ok' },
  warn: { label: 'ต้องเฝ้าระวัง', kind: 'warn' },
  critical: { label: 'วิกฤต', kind: 'danger' },
};

const SCREEN_BAND: Record<string, { label: string; kind: 'ok' | 'warn' | 'danger' | 'info' }> = {
  normal: { label: 'ปกติ', kind: 'ok' },
  at_risk: { label: 'กลุ่มเสี่ยง', kind: 'warn' },
  has_problem: { label: 'มีปัญหา', kind: 'danger' },
  special_needs: { label: 'ต้องการความช่วยเหลือพิเศษ', kind: 'info' },
};

export function BehaviorScreen() {
  const { role } = useSession();
  const canAmend = role != null && ['student_affairs', 'director', 'admin'].includes(role);
  const canSeeSensitive =
    role != null && ['student_affairs', 'academic', 'director', 'admin'].includes(role);

  const [result, setResult] = useState<string | null>(null);
  const [band, setBand] = useState('');

  const rules = useAsync(() => api.get<Rule[]>('/behavior/rules'), []);
  const watchlist = useAsync(
    () => api.get<WatchRow[]>(`/behavior/watchlist${qs({ band })}`),
    [band],
  );

  /* ─── นักศึกษาที่กำลังทำงานด้วย ─── */
  const [typed, setTyped] = useState('');
  const [q, setQ] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setQ(typed.trim()), 300);
    return () => clearTimeout(t);
  }, [typed]);

  const found = useAsync(
    () => (q.length >= 2 ? api.get<StudentRow[]>(`/students${qs({ q, limit: 20 })}`) : Promise.resolve([])),
    [q],
  );

  const [studentId, setStudentId] = useState('');
  const [studentLabel, setStudentLabel] = useState('');

  const history = useAsync(
    () =>
      studentId
        ? api.get<{ status: Status | null; records: Record_[] }>(`/behavior/students/${studentId}`)
        : Promise.resolve({ status: null, records: [] }),
    [studentId],
  );
  const screenings = useAsync(
    () =>
      studentId && canSeeSensitive
        ? api.get<Screening[]>(`/behavior/screenings/${studentId}`)
        : Promise.resolve([]),
    [studentId, canSeeSensitive],
  );
  const visits = useAsync(
    () =>
      studentId && canSeeSensitive
        ? api.get<HomeVisit[]>(`/behavior/home-visits/${studentId}`)
        : Promise.resolve([]),
    [studentId, canSeeSensitive],
  );

  /* ─── ฟอร์มบันทึก ─── */
  const [ruleId, setRuleId] = useState('');
  const [occurredOn, setOccurredOn] = useState('');
  const [detail, setDetail] = useState('');

  const [instrument, setInstrument] = useState('SDQ');
  const [assessedOn, setAssessedOn] = useState('');
  const [screenBand, setScreenBand] = useState('normal');
  const [score, setScore] = useState('');

  const [visitedOn, setVisitedOn] = useState('');
  const [findings, setFindings] = useState('');
  const [followUp, setFollowUp] = useState('');

  function pick(id: string, label: string) {
    setStudentId(id);
    setStudentLabel(label);
  }

  const st = history.data?.status;

  return (
    <>
      <PageHead title="พฤติกรรมและการดูแล" sub={<a href={href('/behavior-center')}>← ศูนย์งานพฤติกรรม</a>} />

      <TableCard
        title="ผู้ที่คะแนนความประพฤติต่ำกว่าเกณฑ์"
        actions={
          <select value={band} onChange={(e) => setBand(e.target.value)} style={{ width: 180 }}>
            <option value="">ทุกระดับที่ผิดปกติ</option>
            <option value="warn">ต้องเฝ้าระวัง</option>
            <option value="critical">วิกฤต</option>
          </select>
        }
      >
        <AsyncView state={watchlist} empty="ไม่มีนักศึกษาที่คะแนนต่ำกว่าเกณฑ์">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                  <th>ชื่อ — นามสกุล</th>
                  <th className="num" style={{ width: 100 }}>คะแนน</th>
                  <th className="num" style={{ width: 100 }}>ถูกหัก</th>
                  <th style={{ width: 140 }}>ล่าสุดเมื่อ</th>
                  <th style={{ width: 130 }}>ระดับ</th>
                  <th style={{ width: 110 }} />
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.student_id}>
                    <td className="mono">{r.student_code}</td>
                    <td>{r.full_name}</td>
                    <td className="num">{r.balance}</td>
                    <td className="num">{r.deduct_count}</td>
                    <td>{r.last_record_on ? thaiDate(r.last_record_on) : '—'}</td>
                    <td>
                      <Badge kind={BAND[r.band]?.kind ?? 'default'}>
                        {BAND[r.band]?.label ?? r.band}
                      </Badge>
                    </td>
                    <td>
                      <button onClick={() => pick(r.student_id, `${r.student_code} ${r.full_name}`)}>
                        เปิดประวัติ
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <Card title="ค้นหานักศึกษา">
        <div className="row">
          <Field label="รหัสนักศึกษา ชื่อ หรือนามสกุล">
            <input value={typed} onChange={(e) => setTyped(e.target.value)} />
          </Field>
          <Field label="ผลค้นหา">
            <select
              value={studentId}
              onChange={(e) => {
                const s = (found.data ?? []).find((x) => x.id === e.target.value);
                if (s) pick(s.id, `${s.student_code} ${s.full_name}`);
              }}
            >
              <option value="">— เลือกนักศึกษา —</option>
              {(found.data ?? []).map((s) => (
                <option key={s.id} value={s.id}>{s.student_code} {s.full_name}</option>
              ))}
            </select>
          </Field>
        </div>
      </Card>

      {result && <Notice kind="ok">{result}</Notice>}

      {studentId && (
        <>
          <Card title={`คะแนนความประพฤติ — ${studentLabel}`}>
            <AsyncView state={history}>
              {() =>
                st ? (
                  <div className="row">
                    <Field label="คะแนนคงเหลือ">
                      <input value={`${st.balance} / ${st.starting_points}`} readOnly />
                    </Field>
                    <Field label="ระดับ">
                      <input value={BAND[st.band]?.label ?? st.band} readOnly />
                    </Field>
                    <Field label="เกณฑ์เฝ้าระวัง">
                      <input value={`ต่ำกว่า ${st.warn_below}`} readOnly />
                    </Field>
                    <Field label="เกณฑ์วิกฤต">
                      <input value={`ต่ำกว่า ${st.critical_below}`} readOnly />
                    </Field>
                    <Field label="ถูกหัก / ได้เพิ่ม">
                      <input value={`${st.deduct_count} / ${st.award_count} ครั้ง`} readOnly />
                    </Field>
                  </div>
                ) : (
                  <div className="empty">ยังไม่มีข้อมูลคะแนนความประพฤติ</div>
                )
              }
            </AsyncView>
          </Card>

          <Card title="บันทึกพฤติกรรม">
            <div className="row">
              <Field label="กฎที่ใช้">
                <select value={ruleId} onChange={(e) => setRuleId(e.target.value)}>
                  <option value="">— เลือกกฎ —</option>
                  {(rules.data ?? []).map((r) => (
                    <option key={r.id} value={r.id}>
                      [{r.direction === 'deduct' ? `−${r.points}` : `+${r.points}`}] {r.code} {r.name_th}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="วันที่เกิดเหตุ">
                <input type="date" value={occurredOn} onChange={(e) => setOccurredOn(e.target.value)} />
              </Field>
              <Field label="รายละเอียด">
                <input value={detail} onChange={(e) => setDetail(e.target.value)} />
              </Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() =>
                    api.post<{ status: { balance: number; band: string }; rule: string }>(
                      '/behavior/records',
                      { studentId, ruleId, occurredOn: occurredOn || undefined, detail: detail || undefined },
                    )
                  }
                  onDone={(r) => {
                    const d = r as { status: { balance: number; band: string }; rule: string };
                    setResult(
                      `บันทึก “${d.rule}” แล้ว — คะแนนคงเหลือ ${d.status.balance} ` +
                      `(${BAND[d.status.band]?.label ?? d.status.band})`,
                    );
                    setDetail('');
                    history.reload();
                    watchlist.reload();
                  }}
                >
                  บันทึก
                </ActionButton>
              </div>
            </div>
            <Notice kind="info">
              คะแนนที่บันทึกเป็น<strong>สำเนาของคะแนนตามกฎ ณ วันนั้น</strong> —
              การแก้คะแนนของกฎในภายหลังจะไม่เปลี่ยนประวัติที่บันทึกไปแล้ว
            </Notice>
          </Card>

          <TableCard title="ประวัติพฤติกรรม">
            <AsyncView state={history} empty="ยังไม่มีประวัติ">
              {(h) =>
                h.records.length === 0 ? (
                  <div className="empty">ยังไม่มีประวัติ</div>
                ) : (
                  <table>
                    <thead>
                      <tr>
                        <th style={{ width: 130 }}>วันที่เกิดเหตุ</th>
                        <th style={{ width: 110 }}>รหัสกฎ</th>
                        <th>เรื่อง</th>
                        <th className="num" style={{ width: 90 }}>คะแนน</th>
                        <th style={{ width: 170 }}>ผู้บันทึก</th>
                        {canAmend && <th style={{ width: 90 }} />}
                      </tr>
                    </thead>
                    <tbody>
                      {h.records.map((r) => (
                        <tr key={r.id}>
                          <td>{thaiDate(r.occurred_on)}</td>
                          <td className="mono">{r.code ?? '—'}</td>
                          <td style={{ whiteSpace: 'normal' }}>
                            {r.rule_th ?? '—'}
                            {r.detail && (
                              <div style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>{r.detail}</div>
                            )}
                          </td>
                          <td className="num">
                            <span style={{ color: r.direction === 'deduct' ? 'var(--danger)' : 'var(--ok)' }}>
                              {r.direction === 'deduct' ? `−${r.points}` : `+${r.points}`}
                            </span>
                          </td>
                          <td style={{ fontSize: 11.5 }}>
                            {r.recorded_by_name ?? '—'}
                            <div style={{ color: 'var(--ink-faint)' }}>{thaiDateTime(r.recorded_at)}</div>
                          </td>
                          {canAmend && (
                            <td>
                              <ActionButton
                                className="danger"
                                confirm="ลบบันทึกนี้ — ประวัติจะหายไปถาวร ยืนยันหรือไม่"
                                onRun={() => api.del(`/behavior/records/${r.id}`)}
                                onDone={() => {
                                  setResult('ลบบันทึกแล้ว');
                                  history.reload();
                                  watchlist.reload();
                                }}
                              >
                                ลบ
                              </ActionButton>
                            </td>
                          )}
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )
              }
            </AsyncView>
            <Notice kind="warn">
              <strong>ไม่มีปุ่มแก้บันทึกโดยตั้งใจ</strong> — การแก้สิ่งที่บันทึกไปแล้ว
              คือการเปลี่ยนหลักฐาน ถ้าบันทึกผิดต้องลบแล้วบันทึกใหม่ ซึ่งเห็นได้จาก
              ภายนอกว่ามีการลบเกิดขึ้น
            </Notice>
          </TableCard>

          {canSeeSensitive ? (
            <>
              <TableCard title="ผลคัดกรอง">
                <AsyncView state={screenings} empty="ยังไม่เคยคัดกรอง">
                  {(rows) => (
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 140 }}>เครื่องมือ</th>
                          <th style={{ width: 140 }}>วันที่ประเมิน</th>
                          <th className="num" style={{ width: 90 }}>คะแนน</th>
                          <th style={{ width: 220 }}>ผลการคัดกรอง</th>
                          <th>ผู้ประเมิน</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((s) => (
                          <tr key={s.id}>
                            <td>{s.instrument}</td>
                            <td>{thaiDate(s.assessed_on)}</td>
                            <td className="num">{s.score ?? '—'}</td>
                            <td>
                              <Badge kind={SCREEN_BAND[s.band]?.kind ?? 'default'}>
                                {SCREEN_BAND[s.band]?.label ?? s.band}
                              </Badge>
                            </td>
                            <td>{s.assessed_by_name ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </AsyncView>
              </TableCard>

              <Card title="บันทึกผลคัดกรอง">
                <div className="row">
                  <Field label="เครื่องมือ">
                    <input value={instrument} onChange={(e) => setInstrument(e.target.value)} />
                  </Field>
                  <Field label="วันที่ประเมิน">
                    <input type="date" value={assessedOn} onChange={(e) => setAssessedOn(e.target.value)} />
                  </Field>
                  <Field label="คะแนน">
                    <input value={score} onChange={(e) => setScore(e.target.value)} />
                  </Field>
                  <Field label="ผลการคัดกรอง">
                    <select value={screenBand} onChange={(e) => setScreenBand(e.target.value)}>
                      {Object.entries(SCREEN_BAND).map(([k, v]) => (
                        <option key={k} value={k}>{v.label}</option>
                      ))}
                    </select>
                  </Field>
                  <div className="shrink">
                    <ActionButton
                      className="primary"
                      onRun={() =>
                        api.post('/behavior/screenings', {
                          studentId, instrument, assessedOn,
                          band: screenBand,
                          score: score ? Number(score) : undefined,
                        })
                      }
                      onDone={() => {
                        setResult('บันทึกผลคัดกรองแล้ว');
                        setScore('');
                        screenings.reload();
                      }}
                    >
                      บันทึก
                    </ActionButton>
                  </div>
                </div>
                <Notice kind="info">
                  บันทึกเฉพาะ<strong>ระดับผล</strong> ไม่เก็บคำตอบรายข้อ — คำตอบรายข้อ
                  เป็นข้อมูลอ่อนไหวที่ต้องออกแบบว่าใครเห็นได้ก่อน และระเบียนสะสม (ปพ.8)
                  ก็แสดงแค่ระดับผลเช่นกัน
                </Notice>
              </Card>

              <TableCard title="บันทึกการเยี่ยมบ้าน">
                <AsyncView state={visits} empty="ยังไม่เคยเยี่ยมบ้าน">
                  {(rows) => (
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 140 }}>วันที่เยี่ยม</th>
                          <th>ข้อค้นพบ</th>
                          <th>การติดตาม</th>
                          <th style={{ width: 170 }}>ผู้เยี่ยม</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rows.map((v) => (
                          <tr key={v.id}>
                            <td>{thaiDate(v.visited_on)}</td>
                            <td style={{ whiteSpace: 'normal' }}>{v.findings ?? '—'}</td>
                            <td style={{ whiteSpace: 'normal' }}>{v.follow_up ?? '—'}</td>
                            <td>{v.visited_by_name ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </AsyncView>
              </TableCard>

              <Card title="บันทึกการเยี่ยมบ้านครั้งใหม่">
                <div className="row">
                  <Field label="วันที่เยี่ยม">
                    <input type="date" value={visitedOn} onChange={(e) => setVisitedOn(e.target.value)} />
                  </Field>
                  <Field label="ข้อค้นพบ">
                    <input value={findings} onChange={(e) => setFindings(e.target.value)} />
                  </Field>
                  <Field label="การติดตาม">
                    <input value={followUp} onChange={(e) => setFollowUp(e.target.value)} />
                  </Field>
                  <div className="shrink">
                    <ActionButton
                      className="primary"
                      onRun={() =>
                        api.post('/behavior/home-visits', {
                          studentId, visitedOn,
                          findings: findings || undefined,
                          followUp: followUp || undefined,
                        })
                      }
                      onDone={() => {
                        setResult('บันทึกการเยี่ยมบ้านแล้ว');
                        setFindings(''); setFollowUp('');
                        visits.reload();
                      }}
                    >
                      บันทึก
                    </ActionButton>
                  </div>
                </div>
              </Card>
            </>
          ) : (
            <Notice kind="warn">
              <strong>ผลคัดกรองและบันทึกเยี่ยมบ้านต้องมีสิทธิ์เฉพาะ</strong> —
              ผู้ที่ดูได้คืองานปกครองและแนะแนว · ฝ่ายวิชาการ · ผู้อำนวยการ
              ถ้าต้องใช้ข้อมูลนี้ในการดูแลนักศึกษา ให้ขอผ่านงานปกครอง
              <strong>อย่าไปถามเจ้าตัวหรือผู้ปกครองแล้วจดไว้เอง</strong>
            </Notice>
          )}
        </>
      )}

      <TableCard title="กฎคะแนนความประพฤติที่ประกาศใช้">
        <AsyncView state={rules} empty="ยังไม่ได้ตั้งกฎ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัส</th>
                  <th>ชื่อกฎ</th>
                  <th style={{ width: 110 }}>ทิศทาง</th>
                  <th className="num" style={{ width: 90 }}>คะแนน</th>
                  <th>การดำเนินการที่ตามมา</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id}>
                    <td className="mono">{r.code}</td>
                    <td>{r.name_th}</td>
                    <td>
                      <Badge kind={r.direction === 'deduct' ? 'danger' : 'ok'}>
                        {r.direction === 'deduct' ? 'หักคะแนน' : 'เพิ่มคะแนน'}
                      </Badge>
                    </td>
                    <td className="num">{r.points}</td>
                    <td>{r.triggers_action ?? '—'}</td>
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

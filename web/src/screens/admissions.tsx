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
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num, thaiDate } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

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

export function AdmissionsScreen() {
  const rounds = useAsync(() => api.get<Round[]>('/admissions/rounds'), []);
  const [roundId, setRoundId] = useState('');
  const [status, setStatus] = useState('');

  const applications = useAsync(
    () =>
      roundId
        ? api.get<Application[]>(`/admissions/applications${qs({ roundId, status })}`)
        : Promise.resolve([]),
    [roundId, status],
  );
  const summary = useAsync(
    () =>
      roundId
        ? api.get<Record<string, unknown>[]>(`/admissions/rounds/${roundId}/summary`)
        : Promise.resolve([]),
    [roundId],
  );

  const round = rounds.data?.find((r) => r.id === roundId);

  return (
    <>
      <PageHead title="งานรับสมัคร" />

      <Notice kind="info">
        ทุกขั้นตอนที่นี่เป็นงานของเจ้าหน้าที่ — ยังไม่เปิดให้ผู้สมัครกรอกใบสมัครเอง
        เพราะต้องออกแบบการยืนยันตัวตนและการกันบอทก่อน
      </Notice>

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
                          onChange={() => setRoundId(r.id)}
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
                      <th style={{ width: 220 }}>ชื่อ — นามสกุล</th>
                      <th>สาขาที่รับเข้า</th>
                      <th style={{ width: 150 }}>สถานะ</th>
                      <th style={{ width: 260 }}>การทำงาน</th>
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
                            {a.status === 'submitted' && (
                              <span style={{ display: 'inline-flex', gap: 8 }}>
                                <ActionButton
                                  className="primary"
                                  onRun={() =>
                                    api.post(`/admissions/applications/${a.id}/decision`, {
                                      outcome: 'passed',
                                    })
                                  }
                                  onDone={() => applications.reload()}
                                >
                                  ผ่าน
                                </ActionButton>
                                <ActionButton
                                  onRun={() =>
                                    api.post(`/admissions/applications/${a.id}/decision`, {
                                      outcome: 'waitlisted',
                                    })
                                  }
                                  onDone={() => applications.reload()}
                                >
                                  สำรอง
                                </ActionButton>
                                <ActionButton
                                  className="danger"
                                  onRun={() =>
                                    api.post(`/admissions/applications/${a.id}/decision`, {
                                      outcome: 'failed',
                                    })
                                  }
                                  onDone={() => applications.reload()}
                                >
                                  ไม่ผ่าน
                                </ActionButton>
                              </span>
                            )}
                            {a.status === 'passed' && (
                              <span style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
                                ขึ้นทะเบียนที่หน้าระเบียนนักศึกษา (ต้องมีรหัสนักศึกษาและปีการศึกษา)
                              </span>
                            )}
                            {a.status !== 'submitted' && a.status !== 'passed' && '—'}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

          <Notice kind="warn">
            <strong>ขึ้นทะเบียนเป็นนักศึกษาเป็นจุดที่ย้อนกลับไม่ได้</strong> —
            `admit_applicant()` เป็นจุดเดียวที่ผู้สมัครกลายเป็นนักศึกษา
            และสร้างระเบียนถาวรทันที
          </Notice>
        </>
      )}
    </>
  );
}

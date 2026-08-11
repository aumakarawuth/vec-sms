/**
 * งานตามกำหนดเวลา
 *
 * ─── ทำไมหน้านี้ต้องแสดง lastRun ไม่ใช่แค่ enabled ───
 * `enabled` เป็น true ตั้งแต่วินาทีที่แอปบูต ทั้งที่ยังไม่เคยรันอะไรเลย
 * คนที่ดูแค่ค่านั้นจะเข้าใจว่างานทำงานอยู่ ทั้งที่อาจไม่เคยทำงานสักครั้ง
 * — ซึ่งเป็นสิ่งที่เกิดขึ้นจริงมาแล้วกับ usage-snapshot ที่ตารางว่างเปล่า
 * อยู่นานโดยไม่มีอะไรฟ้อง
 *
 * ─── ทำไมต้องดูจำนวนที่ล้มด้วย ───
 * ตัวรันดักข้อผิดพลาดแยกรายวิทยาลัย วิทยาลัยที่ยังตั้งค่าไม่ครบจะล้ม
 * เฉพาะตัวเองโดยไม่ลากคนอื่น ผลคือ `failed` ค้างอยู่ที่ 1 ได้เป็นเดือน
 * โดยระบบยังดูปกติ
 */
import { api } from '../core/api';
import { thaiDateTime } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface JobRun {
  job: string;
  startedAt: string;
  durationMs: number;
  ok: number;
  failed: number;
  results: { institution: string; code: string; ok: boolean; error?: string }[];
}

interface JobsStatus {
  enabled: boolean;
  dailyAt: string;
  timezone: string;
  nextRunAt: string | null;
  jobs: { name: string; lastRun: JobRun | null }[];
}

const JOB_LABEL: Record<string, string> = {
  risk: 'คำนวณคะแนนความเสี่ยงและเปิดเคสติดตาม',
  'finance-holds': 'ระงับสิทธิ์คนค้างชำระ และปลดให้เมื่อชำระครบ',
  'usage-snapshot': 'เก็บภาพนิ่งปริมาณใช้งานสำหรับออกใบเรียกเก็บ',
  'purge-login-attempts': 'ล้างบันทึกการเข้าสู่ระบบที่เกิน 90 วัน',
  'purge-password-reset': 'ล้างคำขอรีเซ็ตรหัสผ่านที่เกิน 90 วัน',
};

export function JobsScreen() {
  const status = useAsync(() => api.get<JobsStatus>('/jobs'), []);

  return (
    <>
      <PageHead title="งานตามกำหนดเวลา" />

      <AsyncView state={status}>
        {(s) => {
          const neverRun = s.jobs.filter((j) => j.lastRun === null).length;
          const failing = s.jobs.filter((j) => (j.lastRun?.failed ?? 0) > 0).length;

          return (
            <>
              <Card title="สถานะตัวตั้งเวลา">
                <div className="row">
                  <div>
                    ตัวตั้งเวลาในโปรเซส{' '}
                    <Badge kind={s.enabled ? 'ok' : 'warn'}>
                      {s.enabled ? 'เปิดอยู่' : 'ปิดอยู่'}
                    </Badge>
                  </div>
                  <div>รันทุกวันเวลา {s.dailyAt} น.</div>
                  <div>เขตเวลา {s.timezone}</div>
                  <div>ครั้งถัดไป {thaiDateTime(s.nextRunAt)}</div>
                  <div className="shrink">
                    <ActionButton
                      className="primary"
                      confirm="สั่งรันงานประจำวันทั้งหมดเดี๋ยวนี้ ยืนยันหรือไม่"
                      onRun={() => api.post('/jobs/run')}
                      onDone={() => status.reload()}
                    >
                      รันทั้งหมดเดี๋ยวนี้
                    </ActionButton>
                  </div>
                </div>

                {s.enabled && (
                  <Notice kind="warn">
                    ตัวตั้งเวลาในโปรเซสใช้ได้เฉพาะเมื่อรัน <strong>instance เดียว</strong> —
                    ถ้า scale เกินหนึ่ง งานจะถูกรันซ้ำพร้อมกันทุก instance
                    ที่เจ็บที่สุดคือภาพนิ่งปริมาณใช้งาน ซึ่งเป็นหลักฐานการเรียกเก็บเงิน
                  </Notice>
                )}

                {neverRun > 0 && (
                  <Notice kind="warn">
                    มีงานที่ <strong>ยังไม่เคยรันเลย {neverRun} งาน</strong> —
                    ถ้าแอปเพิ่งรีสตาร์ทถือว่าปกติ แต่ถ้าค้างแบบนี้ข้ามคืน แปลว่าตัวตั้งเวลาไม่ทำงาน
                  </Notice>
                )}
                {failing > 0 && (
                  <Notice kind="error">
                    มีงานที่ล้มบางวิทยาลัย {failing} งาน — ดูรายละเอียดด้านล่าง
                    มักเกิดจากยังไม่ได้ตั้งเกณฑ์ความเสี่ยงหรือนโยบายค่าปรับ
                  </Notice>
                )}
              </Card>

              <TableCard title="ผลการรันครั้งล่าสุดของแต่ละงาน">
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 200 }}>งาน</th>
                      <th>ทำอะไร</th>
                      <th style={{ width: 170 }}>รันล่าสุด</th>
                      <th className="num" style={{ width: 90 }}>ใช้เวลา</th>
                      <th className="num" style={{ width: 120 }}>สำเร็จ/ล้ม</th>
                      <th style={{ width: 110 }}>สั่งรันเดี่ยว</th>
                    </tr>
                  </thead>
                  <tbody>
                    {s.jobs.map((j) => (
                      <tr key={j.name}>
                        <td className="mono">{j.name}</td>
                        <td style={{ whiteSpace: 'normal' }}>{JOB_LABEL[j.name] ?? '—'}</td>
                        <td>
                          {j.lastRun ? (
                            thaiDateTime(j.lastRun.startedAt)
                          ) : (
                            <Badge kind="warn">ยังไม่เคยรัน</Badge>
                          )}
                        </td>
                        <td className="num">{j.lastRun ? `${j.lastRun.durationMs} ms` : '—'}</td>
                        <td className="num">
                          {j.lastRun ? (
                            <Badge kind={j.lastRun.failed > 0 ? 'danger' : 'ok'}>
                              {j.lastRun.ok}/{j.lastRun.ok + j.lastRun.failed}
                            </Badge>
                          ) : (
                            '—'
                          )}
                        </td>
                        <td>
                          <ActionButton
                            onRun={() => api.post(`/jobs/run/${j.name}`)}
                            onDone={() => status.reload()}
                          >
                            รัน
                          </ActionButton>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TableCard>

              {s.jobs
                .filter((j) => (j.lastRun?.failed ?? 0) > 0)
                .map((j) => (
                  <Card key={j.name} title={`รายละเอียดที่ล้ม — ${j.name}`}>
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 150 }}>รหัสสถานศึกษา</th>
                          <th>สาเหตุ</th>
                        </tr>
                      </thead>
                      <tbody>
                        {j.lastRun!.results
                          .filter((r) => !r.ok)
                          .map((r) => (
                            <tr key={r.institution}>
                              <td className="mono">{r.code}</td>
                              <td style={{ whiteSpace: 'normal' }}>{r.error}</td>
                            </tr>
                          ))}
                      </tbody>
                    </table>
                  </Card>
                ))}
            </>
          );
        }}
      </AsyncView>
    </>
  );
}

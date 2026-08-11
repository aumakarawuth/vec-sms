/**
 * เฝ้าระวังและติดตามนักศึกษา — หน้าจอของครูที่ปรึกษาและฝ่ายกิจการนักศึกษา
 *
 * ─── ทำไมต้องเห็นสัญญาณเป็นข้อความ ไม่ใช่แค่คะแนน ───
 * คะแนนความเสี่ยงเป็นตัวเลขรวมที่ไม่บอกว่าต้องไปทำอะไร ครูที่ปรึกษาที่เห็น
 * "72 คะแนน" ทำอะไรไม่ได้ แต่ที่เห็น "ขาดเรียนติดต่อกัน 3 วัน · ค้างชำระ
 * เกิน 30 วัน" รู้ทันทีว่าต้องโทรหาใครเรื่องอะไร — `v_students_at_risk`
 * จึงคืนสัญญาณเป็นข้อความไทยมาให้แล้ว หน้าจอแค่แสดงตามนั้น
 *
 * ─── ทำไมปุ่มคำนวณใหม่อยู่ตรงนี้ ───
 * งานประจำวันคำนวณให้คืนละครั้ง แต่ครูที่ปรึกษาที่เพิ่งบันทึกเวลาเรียน
 * หรือเพิ่งรับชำระเงินต้องเห็นผลทันที ไม่ใช่พรุ่งนี้
 */
import { useState } from 'react';
import { api, emptyPage, qs } from '../core/api';
import { thaiDate } from '../core/fmt';
import { href } from '../core/router';
import { ActionButton, AsyncView, Badge, Card, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

interface AtRiskRow {
  student_id: string;
  student_code: string;
  full_name: string;
  score: number;
  band: string;
  signals_th: string | null;
  signal_count: number;
  case_id: string | null;
  case_status: string | null;
  respond_by: string | null;
}

const BAND: Record<string, { label: string; kind: 'danger' | 'warn' | 'info' | 'default' }> = {
  red: { label: 'แดง', kind: 'danger' },
  orange: { label: 'ส้ม', kind: 'warn' },
  yellow: { label: 'เหลือง', kind: 'warn' },
  green: { label: 'เขียว', kind: 'default' },
};

const CASE_STATUS: Record<string, string> = {
  open: 'เปิดอยู่',
  in_progress: 'กำลังติดตาม',
  resolved: 'ปิดแล้ว',
  escalated: 'ส่งต่อ',
};

export function RiskScreen() {
  const { terms, termId, setTerm } = useTermPicker();
  const [band, setBand] = useState('');

  const list = useAsync(
    () =>
      termId
        ? api.getPage<AtRiskRow>(`/risk/students${qs({ termId, band, limit: 200 })}`)
        : Promise.resolve(emptyPage<AtRiskRow>()),
    [termId, band],
  );

  const counts = (list.data?.items ?? []).reduce<Record<string, number>>((acc, r) => {
    acc[r.band] = (acc[r.band] ?? 0) + 1;
    return acc;
  }, {});

  return (
    <>
      <PageHead
        title="เฝ้าระวังและติดตาม"
        sub={
          list.data
            ? Object.entries(counts)
                .map(([b, n]) => `${BAND[b]?.label ?? b} ${n}`)
                .join(' · ')
            : undefined
        }
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <Card>
        <div className="row">
          <label className="field" style={{ maxWidth: 200 }}>
            <span>ระดับความเสี่ยง</span>
            <select value={band} onChange={(e) => setBand(e.target.value)}>
              <option value="">ทุกระดับ</option>
              <option value="red">แดง</option>
              <option value="orange">ส้ม</option>
              <option value="yellow">เหลือง</option>
            </select>
          </label>

          <div className="shrink">
            <ActionButton
              onRun={() => api.post('/risk/compute', { termId })}
              onDone={() => list.reload()}
            >
              คำนวณคะแนนใหม่
            </ActionButton>
          </div>

          <div className="shrink">
            <ActionButton
              onRun={() => api.post('/risk/cases/open', { termId })}
              onDone={() => list.reload()}
              confirm="เปิดเคสติดตามให้ทุกคนที่ถึงเกณฑ์และยังไม่มีเคส ยืนยันหรือไม่"
            >
              เปิดเคสติดตามที่ยังขาด
            </ActionButton>
          </div>

          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            งานประจำวันคำนวณให้คืนละครั้ง กดที่นี่เมื่อต้องการผลทันที
          </div>
        </div>
      </Card>

      <TableCard title="รายชื่อที่ต้องติดตาม">
        <AsyncView state={list} empty="ไม่มีนักศึกษาที่เข้าเกณฑ์เฝ้าระวังในภาคเรียนนี้">
          {(page) =>
            page.items.length === 0 ? (
              <div className="empty">ไม่มีนักศึกษาที่เข้าเกณฑ์เฝ้าระวังในภาคเรียนนี้</div>
            ) : (
              <>
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 70 }}>ระดับ</th>
                      <th className="num" style={{ width: 70 }}>คะแนน</th>
                      <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                      <th style={{ width: 170 }}>ชื่อ — นามสกุล</th>
                      <th>สัญญาณที่พบ</th>
                      <th style={{ width: 120 }}>เคสติดตาม</th>
                      <th style={{ width: 120 }}>ต้องตอบภายใน</th>
                    </tr>
                  </thead>
                  <tbody>
                    {page.items.map((r) => {
                      const b = BAND[r.band];
                      const overdue =
                        r.respond_by !== null && new Date(r.respond_by) < new Date();
                      return (
                        <tr key={r.student_id}>
                          <td>
                            <Badge kind={b?.kind ?? 'default'}>{b?.label ?? r.band}</Badge>
                          </td>
                          <td className="num">{r.score}</td>
                          <td className="mono">
                            <a href={href(`/students/${r.student_id}`)}>{r.student_code}</a>
                          </td>
                          <td>{r.full_name}</td>
                          <td style={{ whiteSpace: 'normal' }}>
                            {r.signals_th ?? `${r.signal_count} สัญญาณ`}
                          </td>
                          <td>
                            {r.case_id ? (
                              <Badge kind={r.case_status === 'resolved' ? 'ok' : 'info'}>
                                {CASE_STATUS[r.case_status ?? ''] ?? r.case_status}
                              </Badge>
                            ) : (
                              <span style={{ color: 'var(--ink-faint)' }}>ยังไม่เปิด</span>
                            )}
                          </td>
                          <td>
                            {r.respond_by ? (
                              <span style={{ color: overdue ? 'var(--danger)' : undefined }}>
                                {thaiDate(r.respond_by)}
                                {overdue && ' (เกินแล้ว)'}
                              </span>
                            ) : (
                              '—'
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>

                {page.hasMore && (
                  <div style={{ padding: 12 }}>
                    <Notice kind="info">
                      แสดง {page.items.length} รายการแรก — กรองด้วยระดับความเสี่ยงเพื่อดูให้ครบ
                    </Notice>
                  </div>
                )}
              </>
            )
          }
        </AsyncView>
      </TableCard>
    </>
  );
}

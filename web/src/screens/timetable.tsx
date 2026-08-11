/**
 * ตารางสอน
 *
 * ─── ทำไมตัวจัดอัตโนมัติไม่ใช่ปุ่มเดียวจบ ───
 * ตัวจัดเป็นแบบโลภ ไม่ใช่หาคำตอบที่ดีที่สุด — วางให้ได้มากที่สุดเท่าที่
 * ไม่ชน แล้วรายงานวิชาที่วางไม่ครบให้คนไปตัดสินใจต่อ หน้าจอจึงต้องแสดง
 * ผลที่วางไม่ได้ให้เห็น ไม่ใช่บอกแค่ว่า "สำเร็จ"
 *
 * ─── ทำไมต้องดูคาบที่ชนหลังวางเสร็จ ───
 * exclusion constraint กันการชนของห้องและครูไว้แล้วตอนเขียน แต่การชนที่
 * เกิดกับ**ผู้เรียน** (นักศึกษาคนเดียวลงสองวิชาที่คาบเดียวกัน) เป็นเรื่อง
 * ของการลงทะเบียนซึ่งเกิดทีหลัง — จึงต้องตรวจซ้ำหลังตารางนิ่งแล้ว
 */
import { useEffect, useState } from 'react';
import { api } from '../core/api';
import { fetchSections, type Section } from '../core/catalog';
import { ActionButton, AsyncView, Badge, Card, Notice, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const DAY = ['', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

interface Room {
  id: string;
  code: string;
  name_th: string;
  kind: string;
  capacity: number | null;
  building: string | null;
}

interface Conflict {
  class_section_id: string;
  label: string;
  day_of_week: number;
  period_from: number;
  period_to: number;
  message_th?: string;
  kind?: string;
}

interface Suggestion {
  day_of_week: number;
  period_from: number;
  period_to: number;
  avoids: boolean;
  note: string | null;
}

export function TimetableScreen() {
  const { terms, termId, setTerm } = useTermPicker();
  const rooms = useAsync(() => api.get<Room[]>('/timetable/rooms'), []);
  const sections = useAsync(
    () => (termId ? fetchSections(termId) : Promise.resolve([])),
    [termId],
  );
  // เส้นทางนี้คืน { total, conflicts } ไม่ใช่อาร์เรย์เปล่า
  const conflicts = useAsync(
    () =>
      termId
        ? api.get<{ total: number; conflicts: Conflict[] }>(
            `/timetable/terms/${termId}/conflicts`,
          )
        : Promise.resolve({ total: 0, conflicts: [] }),
    [termId],
  );

  const [sectionId, setSectionId] = useState('');
  const [periods, setPeriods] = useState('2');
  const [roomId, setRoomId] = useState('');
  const [suggestions, setSuggestions] = useState<Suggestion[] | null>(null);
  const [autoResult, setAutoResult] = useState<unknown>(null);

  useEffect(() => {
    setSectionId('');
    setSuggestions(null);
    setAutoResult(null);
  }, [termId]);

  return (
    <>
      <PageHead
        title="ตารางสอน"
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <Card title="จัดตารางอัตโนมัติทั้งภาคเรียน">
        <div className="row">
          <div className="shrink">
            <ActionButton
              className="primary"
              confirm="ตัวจัดจะวางคาบให้กลุ่มเรียนที่ยังไม่มีตาราง ยืนยันหรือไม่"
              onRun={() => api.post(`/timetable/terms/${termId}/auto-schedule`)}
              onDone={(r) => {
                setAutoResult(r);
                conflicts.reload();
              }}
            >
              จัดตารางอัตโนมัติ
            </ActionButton>
          </div>
          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            ตัวจัดเป็นแบบโลภ — วางให้ได้มากที่สุดเท่าที่ไม่ชน แล้วรายงานวิชาที่วางไม่ครบ
            ให้คนไปตัดสินใจต่อ ไม่ใช่การหาคำตอบที่ดีที่สุด
          </div>
        </div>
        {autoResult !== null && (
          <Notice kind="info">
            <pre style={{ margin: 0, whiteSpace: 'pre-wrap', fontSize: 12 }}>
              {JSON.stringify(autoResult, null, 2)}
            </pre>
          </Notice>
        )}
      </Card>

      <Card title="วางคาบให้กลุ่มเรียนทีละกลุ่ม">
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>กลุ่มเรียน</span>
            <AsyncView state={sections} empty="ภาคเรียนนี้ยังไม่มีกลุ่มเรียน">
              {(rows) => (
                <select value={sectionId} onChange={(e) => setSectionId(e.target.value)}>
                  <option value="">— เลือกกลุ่มเรียน —</option>
                  {rows.map((s: Section) => (
                    <option key={s.id} value={s.id}>
                      {s.code} {s.name_th} · กลุ่ม {s.section_no} · {s.teacher_name || 'ยังไม่มีครู'}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
          <label className="field" style={{ maxWidth: 140 }}>
            <span>จำนวนคาบติดกัน</span>
            <select value={periods} onChange={(e) => setPeriods(e.target.value)}>
              {[1, 2, 3, 4].map((n) => (
                <option key={n} value={n}>{n} คาบ</option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>ห้อง (ถ้าระบุ)</span>
            <AsyncView state={rooms}>
              {(list) => (
                <select value={roomId} onChange={(e) => setRoomId(e.target.value)}>
                  <option value="">— ไม่ระบุห้อง —</option>
                  {list.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.code} {r.name_th}
                      {r.capacity ? ` (${r.capacity} ที่)` : ''}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
          <div className="shrink">
            <ActionButton
              onRun={() =>
                api.get<Suggestion[]>(
                  `/timetable/suggest?classSectionId=${sectionId}&periods=${periods}` +
                    (roomId ? `&roomId=${roomId}` : '') +
                    (termId ? `&termId=${termId}` : ''),
                )
              }
              onDone={(r) => setSuggestions(r as Suggestion[])}
            >
              หาคาบว่าง
            </ActionButton>
          </div>
        </div>

        {suggestions && (
          suggestions.length === 0 ? (
            <Notice kind="warn">
              ไม่มีคาบว่างที่วางได้เลย — ลองลดจำนวนคาบติดกัน หรือไม่ระบุห้อง
            </Notice>
          ) : (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>วัน</th>
                  <th style={{ width: 120 }}>คาบ</th>
                  <th style={{ width: 150 }}>เลี่ยงคำขอครู</th>
                  <th>หมายเหตุ</th>
                  <th style={{ width: 110 }}>วางคาบนี้</th>
                </tr>
              </thead>
              <tbody>
                {suggestions.map((s, i) => (
                  <tr key={i}>
                    <td>{DAY[s.day_of_week]}</td>
                    <td>
                      {s.period_from}–{s.period_to}
                    </td>
                    <td>
                      {s.avoids ? (
                        <Badge kind="warn">ครูขอเลี่ยง</Badge>
                      ) : (
                        <Badge kind="ok">ไม่ติดคำขอ</Badge>
                      )}
                    </td>
                    <td style={{ whiteSpace: 'normal' }}>{s.note ?? '—'}</td>
                    <td>
                      <ActionButton
                        onRun={() =>
                          api.post('/timetable/slots', {
                            classSectionId: sectionId,
                            dayOfWeek: s.day_of_week,
                            periodFrom: s.period_from,
                            periodTo: s.period_to,
                            ...(roomId ? { roomId } : {}),
                          })
                        }
                        onDone={() => {
                          setSuggestions(null);
                          conflicts.reload();
                        }}
                      >
                        วาง
                      </ActionButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )
        )}
      </Card>

      <TableCard
        title="คาบที่ชนกันในภาคเรียนนี้"
        actions={<button onClick={() => conflicts.reload()}>ตรวจใหม่</button>}
      >
        <AsyncView state={conflicts} empty="ไม่มีคาบที่ชนกัน">
          {({ conflicts: rows }) =>
            rows.length === 0 ? (
              <div className="empty">ไม่มีคาบที่ชนกัน</div>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>กลุ่มเรียน</th>
                    <th style={{ width: 120 }}>วัน</th>
                    <th style={{ width: 100 }}>คาบ</th>
                    <th>ชนกับอะไร</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((c, i) => (
                    <tr key={`${c.class_section_id}-${i}`}>
                      <td>{c.label}</td>
                      <td>{DAY[c.day_of_week]}</td>
                      <td>
                        {c.period_from}–{c.period_to}
                      </td>
                      <td style={{ whiteSpace: 'normal' }}>{c.message_th ?? c.kind ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )
          }
        </AsyncView>
      </TableCard>

      <TableCard title="ห้องเรียนของวิทยาลัย">
        <AsyncView state={rooms} empty="ยังไม่ได้บันทึกห้องเรียน">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>รหัสห้อง</th>
                  <th>ชื่อห้อง</th>
                  <th style={{ width: 150 }}>ประเภท</th>
                  <th style={{ width: 130 }}>อาคาร</th>
                  <th className="num" style={{ width: 90 }}>ความจุ</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.id}>
                    <td className="mono">{r.code}</td>
                    <td>{r.name_th}</td>
                    <td>{r.kind}</td>
                    <td>{r.building ?? '—'}</td>
                    <td className="num">{r.capacity ?? '—'}</td>
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

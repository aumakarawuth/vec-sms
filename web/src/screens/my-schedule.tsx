/**
 * ตารางสอนของฉัน
 *
 * ต่างจาก /timetable (ศูนย์งานตารางเรียน — งานทะเบียน/วิชาการ) ตรงที่หน้านี้
 * ตอบได้แค่คำถามเดียวคือ "ฉันสอนอะไรบ้าง" ไม่มีทางเลือกดูของครูคนอื่น และ
 * ไม่มีปุ่มแก้ตาราง — `/academic/my-schedule` กรองด้วย current_actor_id()
 * ที่ฐานข้อมูลเสมอ ไม่รับ staffId จากฝั่งนี้เลย
 */
import { api } from '../core/api';
import { usePeriodLabel } from '../core/catalog';
import { href } from '../core/router';
import { AsyncView, Card, PageHead, TableCard, useAsync } from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const DAY = ['', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

interface MySlot {
  timeslot_id: string;
  day_of_week: number;
  period_from: number;
  period_to: number;
  class_section_id: string;
  section_no: string;
  code: string;
  name_th: string;
  credits: string;
  room_code: string | null;
  room_name: string | null;
}

export function MyScheduleScreen() {
  const { terms, termId, setTerm } = useTermPicker();
  const periodLabel = usePeriodLabel();
  const slots = useAsync(
    () => (termId ? api.get<MySlot[]>(`/academic/my-schedule?termId=${termId}`) : Promise.resolve([])),
    [termId],
  );

  return (
    <>
      <PageHead
        title="ตารางสอนของฉัน"
        sub="คาบสอนทั้งหมดที่ผูกกับบัญชีของคุณในภาคเรียนที่เลือก"
        actions={
          <div className="row" style={{ gap: 8, alignItems: 'center' }}>
            <a href={href('/timetable-center')}>← ศูนย์งานตารางเรียน</a>
            <div style={{ width: 240 }}>
              <AsyncView state={terms}>
                {(l) => <TermSelect terms={l} termId={termId} onChange={setTerm} />}
              </AsyncView>
            </div>
          </div>
        }
      />

      <TableCard title="คาบสอนรายสัปดาห์">
        <AsyncView
          state={slots}
          empty="ยังไม่มีคาบสอนที่วางไว้ให้คุณในภาคเรียนนี้ — ถ้าคิดว่าควรมี ให้แจ้งงานทะเบียน/วิชาการ"
        >
          {(rows) => {
            const byDay = new Map<number, MySlot[]>();
            for (const r of rows) {
              const list = byDay.get(r.day_of_week) ?? [];
              list.push(r);
              byDay.set(r.day_of_week, list);
            }
            for (const list of byDay.values()) list.sort((a, b) => a.period_from - b.period_from);

            return (
              <>
                {[1, 2, 3, 4, 5, 6, 7]
                  .filter((d) => byDay.has(d))
                  .map((d) => (
                    <Card key={d} title={DAY[d]}>
                      <table>
                        <thead>
                          <tr>
                            <th style={{ width: 140 }}>คาบ</th>
                            <th style={{ width: 100 }}>รหัสวิชา</th>
                            <th>ชื่อวิชา</th>
                            <th style={{ width: 90 }}>กลุ่ม</th>
                            <th className="num" style={{ width: 70 }}>หน่วยกิต</th>
                            <th style={{ width: 160 }}>ห้อง</th>
                          </tr>
                        </thead>
                        <tbody>
                          {byDay.get(d)!.map((s) => (
                            <tr key={s.timeslot_id}>
                              <td>{periodLabel(s.period_from, s.period_to)}</td>
                              <td className="mono">{s.code}</td>
                              <td>{s.name_th}</td>
                              <td>{s.section_no}</td>
                              <td className="num">{s.credits}</td>
                              <td>{s.room_code ? `${s.room_code} ${s.room_name ?? ''}` : '— ไม่ระบุห้อง —'}</td>
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
      </TableCard>
    </>
  );
}

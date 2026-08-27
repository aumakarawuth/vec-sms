/**
 * คาบเรียน — ผูกเลขลำดับคาบ (ตัวเดียวกับที่ section_timeslot.period_from/
 * period_to ใช้อยู่แล้วในหน้าจัดตารางสอน/ตารางสอบ) เข้ากับเวลานาฬิกาจริง
 * เดิมหน้านี้เก็บใน React state ล้วน ปุ่ม "บันทึก" ไม่มีโค้ดทำงานเลย
 */
import { useState } from 'react';
import { api } from '../core/api';
import { ActionButton, AsyncView, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

export interface PeriodRow {
  id: string;
  ordinal: number;
  title: string;
  short_name: string | null;
  starts_at: string | null;
  ends_at: string | null;
}

const fetchPeriods = () => api.get<PeriodRow[]>('/academic/periods');

export function PeriodsScreen() {
  const periods = useAsync(fetchPeriods, []);
  return (
    <>
      <PageHead title="คาบเรียน" sub="กำหนดเลขลำดับคาบ ชื่อคาบ และเวลาที่ใช้จัดตารางสอน" />
      <TableCard title="คาบเรียนทั้งหมด">
        <AsyncView state={periods} empty="ยังไม่มีคาบเรียน">
          {(rows) => (
            <table>
              <thead>
                <tr><th style={{ width: 70 }}>ลำดับ</th><th>ชื่อ</th><th style={{ width: 100 }}>ชื่อย่อ</th><th style={{ width: 110 }}>เริ่ม</th><th style={{ width: 110 }}>สิ้นสุด</th><th style={{ width: 140 }} /></tr>
              </thead>
              <tbody>
                {rows.map((p) => <PeriodRowItem key={p.id} period={p} onDone={() => periods.reload()} />)}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
      <NewPeriodForm onDone={() => periods.reload()} />
    </>
  );
}

function PeriodRowItem({ period, onDone }: { period: PeriodRow; onDone: () => void }) {
  const [editing, setEditing] = useState(false);
  const [ordinal, setOrdinal] = useState(String(period.ordinal));
  const [title, setTitle] = useState(period.title);
  const [shortName, setShortName] = useState(period.short_name ?? '');
  const [startsAt, setStartsAt] = useState(period.starts_at?.slice(0, 5) ?? '');
  const [endsAt, setEndsAt] = useState(period.ends_at?.slice(0, 5) ?? '');

  if (!editing) {
    return (
      <tr>
        <td>{period.ordinal}</td>
        <td>{period.title}</td>
        <td>{period.short_name ?? '—'}</td>
        <td>{period.starts_at?.slice(0, 5) ?? '—'}</td>
        <td>{period.ends_at?.slice(0, 5) ?? '—'}</td>
        <td>
          <button className="ghost" onClick={() => setEditing(true)}>แก้ไข</button>
          <ActionButton
            className="ghost danger"
            confirm={`ลบคาบ "${period.title}" ใช่หรือไม่`}
            onRun={() => api.del(`/academic/periods/${period.id}`)}
            onDone={onDone}
          >
            ลบออก
          </ActionButton>
        </td>
      </tr>
    );
  }
  return (
    <tr>
      <td><input type="number" min={1} max={20} value={ordinal} onChange={(e) => setOrdinal(e.target.value)} style={{ maxWidth: 60 }} /></td>
      <td><input value={title} onChange={(e) => setTitle(e.target.value)} /></td>
      <td><input value={shortName} onChange={(e) => setShortName(e.target.value)} style={{ maxWidth: 80 }} /></td>
      <td><input type="time" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} /></td>
      <td><input type="time" value={endsAt} onChange={(e) => setEndsAt(e.target.value)} /></td>
      <td>
        <ActionButton
          className="ghost"
          onRun={() => {
            if (!title.trim() || !ordinal) throw new Error('กรอกไม่ครบ');
            return api.patch(`/academic/periods/${period.id}`, {
              ordinal: Number(ordinal), title: title.trim(),
              shortName: shortName.trim() || undefined,
              startsAt: startsAt || undefined, endsAt: endsAt || undefined,
            });
          }}
          onDone={() => { setEditing(false); onDone(); }}
        >
          บันทึก
        </ActionButton>
        <button className="ghost" onClick={() => setEditing(false)}>ยกเลิก</button>
      </td>
    </tr>
  );
}

function NewPeriodForm({ onDone }: { onDone: () => void }) {
  const [ordinal, setOrdinal] = useState('');
  const [title, setTitle] = useState('');
  const [shortName, setShortName] = useState('');
  const [startsAt, setStartsAt] = useState('');
  const [endsAt, setEndsAt] = useState('');
  return (
    <TableCard title="เพิ่มคาบเรียนใหม่">
      <div className="row">
        <label className="field"><span>ลำดับ</span><input type="number" min={1} max={20} value={ordinal} onChange={(e) => setOrdinal(e.target.value)} style={{ maxWidth: 80 }} /></label>
        <label className="field"><span>ชื่อ</span><input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="คาบ 1" /></label>
        <label className="field"><span>ชื่อย่อ</span><input value={shortName} onChange={(e) => setShortName(e.target.value)} style={{ maxWidth: 100 }} /></label>
        <label className="field"><span>เริ่ม</span><input type="time" value={startsAt} onChange={(e) => setStartsAt(e.target.value)} /></label>
        <label className="field"><span>สิ้นสุด</span><input type="time" value={endsAt} onChange={(e) => setEndsAt(e.target.value)} /></label>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!title.trim() || !ordinal) throw new Error('กรอกลำดับและชื่อคาบ');
              return api.post('/academic/periods', {
                ordinal: Number(ordinal), title: title.trim(),
                shortName: shortName.trim() || undefined,
                startsAt: startsAt || undefined, endsAt: endsAt || undefined,
              });
            }}
            onDone={() => { setOrdinal(''); setTitle(''); setShortName(''); setStartsAt(''); setEndsAt(''); onDone(); }}
          >
            เพิ่มคาบเรียน
          </ActionButton>
        </div>
      </div>
      <Notice kind="info">เลขลำดับต้องตรงกับเลขคาบที่ใช้ในหน้าจัดตารางสอนและตารางสอบ</Notice>
    </TableCard>
  );
}

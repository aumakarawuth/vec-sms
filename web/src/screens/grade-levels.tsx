/**
 * ระดับชั้น — ป้ายชื่อชั้นปีในแต่ละระดับ (ปวช.1, ปวช.2, ...) ผูกกับ
 * qualification_level (enum ตายตัว) และ study_year (เลขชั้นปีที่ระบบใช้
 * คำนวณเลื่อนชั้นจริง) เดิมหน้านี้เก็บใน React state ล้วน ปุ่ม "บันทึก"
 * ไม่มีโค้ดทำงานเลย — เป็นป้ายตกแต่งการแสดงผล ไม่กระทบตัวเลขเลื่อนชั้นปี
 */
import { useState } from 'react';
import { api } from '../core/api';
import { href } from '../core/router';
import { ActionButton, AsyncView, Notice, PageHead, useAsync } from '../ui/kit';

export interface GradeLevelRow {
  id: string;
  level: 'PVC' | 'PVS' | 'TVB';
  study_year: number;
  title: string;
  short_name: string | null;
}

const LEVELS = ['PVC', 'PVS', 'TVB'] as const;
const LEVEL_TITLE: Record<string, string> = { PVC: 'ปวช.', PVS: 'ปวส.', TVB: 'ทล.บ.' };

const fetchGradeLevels = () => api.get<GradeLevelRow[]>('/academic/grade-levels');

export function GradeLevelsScreen() {
  const levels = useAsync(fetchGradeLevels, []);
  const [active, setActive] = useState<typeof LEVELS[number]>('PVC');
  const rows = (levels.data ?? []).filter((r) => r.level === active);

  return (
    <>
      <PageHead
        title="ระดับชั้น"
        sub="กำหนดชื่อและชื่อย่อของแต่ละชั้นปีในแต่ละระดับ"
        actions={<a href={href('/settings-center')}>← ศูนย์การตั้งค่า</a>}
      />
      <Notice kind="info">เลขชั้นปี (1–6) เป็นตัวเลขที่ระบบใช้คำนวณเลื่อนชั้นจริงอยู่แล้ว หน้านี้แค่ตั้งชื่อที่แสดงผล</Notice>
      <div className="period-layout">
        <aside className="period-groups">
          <header><strong>{LEVELS.length} ระดับ</strong></header>
          {LEVELS.map((lv) => (
            <button key={lv} className={lv === active ? 'active' : ''} onClick={() => setActive(lv)}>
              {LEVEL_TITLE[lv]}<small>{(levels.data ?? []).filter((r) => r.level === lv).length} ชั้นปี</small>
            </button>
          ))}
        </aside>
        <section className="period-table">
          <AsyncView state={levels} empty="ยังไม่มีระดับชั้น">
            {() => (
              <table>
                <thead><tr><th style={{ width: 70 }}>ชั้นปี</th><th>ชื่อ</th><th style={{ width: 100 }}>ชื่อย่อ</th><th style={{ width: 140 }} /></tr></thead>
                <tbody>
                  {rows.map((r) => <GradeLevelRowItem key={r.id} row={r} onDone={() => levels.reload()} />)}
                </tbody>
              </table>
            )}
          </AsyncView>
          <NewGradeLevelForm level={active} onDone={() => levels.reload()} />
        </section>
      </div>
    </>
  );
}

function GradeLevelRowItem({ row, onDone }: { row: GradeLevelRow; onDone: () => void }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(row.title);
  const [shortName, setShortName] = useState(row.short_name ?? '');

  if (!editing) {
    return (
      <tr>
        <td>{row.study_year}</td>
        <td>{row.title}</td>
        <td>{row.short_name ?? '—'}</td>
        <td>
          <button className="ghost" onClick={() => setEditing(true)}>แก้ไข</button>
          <ActionButton
            className="ghost danger"
            confirm={`ลบระดับชั้น "${row.title}" ใช่หรือไม่`}
            onRun={() => api.del(`/academic/grade-levels/${row.id}`)}
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
      <td>{row.study_year}</td>
      <td><input value={title} onChange={(e) => setTitle(e.target.value)} /></td>
      <td><input value={shortName} onChange={(e) => setShortName(e.target.value)} style={{ maxWidth: 90 }} /></td>
      <td>
        <ActionButton
          className="ghost"
          onRun={() => {
            if (!title.trim()) throw new Error('กรอกชื่อชั้นปี');
            return api.patch(`/academic/grade-levels/${row.id}`, {
              level: row.level, studyYear: row.study_year,
              title: title.trim(), shortName: shortName.trim() || undefined,
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

function NewGradeLevelForm({ level, onDone }: { level: string; onDone: () => void }) {
  const [studyYear, setStudyYear] = useState('1');
  const [title, setTitle] = useState('');
  const [shortName, setShortName] = useState('');
  return (
    <div className="row">
      <label className="field"><span>ชั้นปี</span><input type="number" min={1} max={6} value={studyYear} onChange={(e) => setStudyYear(e.target.value)} style={{ maxWidth: 80 }} /></label>
      <label className="field"><span>ชื่อ</span><input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${LEVEL_TITLE[level]}${studyYear}`} /></label>
      <label className="field"><span>ชื่อย่อ</span><input value={shortName} onChange={(e) => setShortName(e.target.value)} style={{ maxWidth: 90 }} /></label>
      <div className="shrink">
        <ActionButton
          className="primary"
          onRun={() => {
            if (!studyYear) throw new Error('กรอกชั้นปี');
            return api.post('/academic/grade-levels', {
              level, studyYear: Number(studyYear),
              title: title.trim() || `${LEVEL_TITLE[level]}${studyYear}`,
              shortName: shortName.trim() || undefined,
            });
          }}
          onDone={() => { setTitle(''); setShortName(''); onDone(); }}
        >
          เพิ่มระดับชั้น
        </ActionButton>
      </div>
    </div>
  );
}

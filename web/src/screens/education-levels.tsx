/**
 * ระดับการศึกษา — ป้ายชื่อของ qualification_level (enum ตายตัว: PVC/PVS/TVB)
 * ที่เคยฮาร์ดโค้ดไว้คนละชุดใน academic-year.tsx กับ finance.tsx
 * (ทั้งสองไฟล์มี LEVEL_LABEL ของตัวเอง) — หน้านี้ทำให้แก้ป้ายชื่อได้จริง
 * โดยไม่ต้องแก้โค้ด
 *
 * ตัดช่อง folder/SQL_TYPE/MUA_ID ของหน้ามอคอัพเดิมทิ้ง — เป็นคอลัมน์ที่
 * คัดลอกมาจากระบบเดิม ไม่ตรงกับสคีมาของเราเลย (ชื่อฉบับหลักสูตรอยู่ที่
 * ตาราง curriculum/curriculum_version อยู่แล้ว ไม่ควรมีชุดข้อมูลที่สอง
 * มาซ้ำซ้อนกัน)
 */
import { useState } from 'react';
import { api } from '../core/api';
import { ActionButton, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

export interface QualificationLevelLabelRow {
  id: string;
  level: 'PVC' | 'PVS' | 'TVB';
  title: string;
  sort_order: number;
}

const LEVELS = ['PVC', 'PVS', 'TVB'] as const;
const DEFAULT_TITLE: Record<string, string> = { PVC: 'ประกาศนียบัตรวิชาชีพ (ปวช.)', PVS: 'ประกาศนียบัตรวิชาชีพชั้นสูง (ปวส.)', TVB: 'ทล.บ.' };

const fetchLabels = () => api.get<QualificationLevelLabelRow[]>('/academic/qualification-levels');

export function EducationLevelsScreen() {
  const labels = useAsync(fetchLabels, []);
  const rows = LEVELS.map((level) => labels.data?.find((r) => r.level === level) ?? { id: '', level, title: DEFAULT_TITLE[level] ?? level, sort_order: 0 });

  return (
    <>
      <PageHead title="ระดับการศึกษา" sub="ตั้งชื่อที่ใช้เรียกแต่ละระดับการศึกษาในระบบ" />
      <Notice kind="info">ระดับการศึกษา (ปวช./ปวส./ทล.บ.) เป็นค่าคงที่ของระบบ หน้านี้แก้ได้เฉพาะชื่อที่แสดงผล — ฉบับหลักสูตรของแต่ละระดับดูที่เมนู "หลักสูตร"</Notice>
      <TableCard title="ชื่อระดับการศึกษา">
        {/*
          ห้ามใช้ AsyncView ตรงนี้ — มันซ่อนตารางทั้งก้อนทันทีที่ labels.data
          เป็นอาร์เรย์ว่าง (วิทยาลัยเปิดใหม่ยังไม่เคยตั้งชื่อเอง) ทั้งที่ `rows`
          ด้านบนคำนวณไว้ให้มีครบสามแถวเสมอโดยใช้ชื่อเริ่มต้นแทนแถวที่ยังไม่มี
          ผลคือปุ่ม "แก้ไข" ไม่เคยโผล่เลยสักครั้งสำหรับวิทยาลัยที่ยังไม่เคยตั้งชื่อ
          — เช็คสถานะโหลด/ผิดพลาดเองแทน ไม่เช็คว่าอาร์เรย์ว่างหรือไม่
        */}
        {labels.loading && labels.data === null ? <div className="loading">กำลังโหลด…</div>
          : labels.error ? <Notice kind="error">{labels.error}</Notice>
          : <table>
              <thead><tr><th style={{ width: 80 }}>รหัส</th><th>ชื่อ</th><th style={{ width: 90 }}>ลำดับ</th><th style={{ width: 180 }} /></tr></thead>
              <tbody>{rows.map((r) => <LevelLabelRow key={r.level} row={r} onDone={() => labels.reload()} />)}</tbody>
            </table>}
      </TableCard>
    </>
  );
}

function LevelLabelRow({ row, onDone }: { row: QualificationLevelLabelRow; onDone: () => void }) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(row.title);
  const [sortOrder, setSortOrder] = useState(String(row.sort_order));

  if (!editing) {
    return (
      <tr>
        <td>{row.level}</td>
        <td>{row.title}</td>
        <td>{row.sort_order}</td>
        <td>
          <button className="ghost" onClick={() => setEditing(true)}>แก้ไข</button>{' '}
          {row.id && (
            <ActionButton
              className="ghost danger"
              toast
              confirm={`ลบชื่อที่ตั้งไว้สำหรับ ${row.level} ใช่หรือไม่ — จะกลับไปใช้ชื่อเริ่มต้น "${DEFAULT_TITLE[row.level] ?? row.level}" แทน`}
              onRun={() => api.del(`/academic/qualification-levels/${row.id}`)}
              onDone={onDone}
            >
              ลบ
            </ActionButton>
          )}
        </td>
      </tr>
    );
  }
  return (
    <tr>
      <td>{row.level}</td>
      <td><input value={title} onChange={(e) => setTitle(e.target.value)} /></td>
      <td><input type="number" value={sortOrder} onChange={(e) => setSortOrder(e.target.value)} style={{ maxWidth: 70 }} /></td>
      <td>
        <ActionButton
          className="ghost"
          onRun={() => {
            if (!title.trim()) throw new Error('กรอกชื่อ');
            return api.post('/academic/qualification-levels', {
              level: row.level, title: title.trim(), sortOrder: Number(sortOrder) || 0,
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

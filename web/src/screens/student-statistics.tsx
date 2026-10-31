/**
 * สถิตินักศึกษาแบบ SISA — ทุกเมนู "ข้อมูลสถิติ" ของ SISA คือตารางรูปเดียวกัน
 * (แถว = ค่าของมิติ · คอลัมน์ = ชั้นปี) ต่างกันแค่มิติ หน้านี้จึงเป็นหน้าเดียว
 * ที่เลือกมิติจากรายการด้านซ้าย แทนที่จะเป็นสิบเก้าหน้าที่หน้าตาเหมือนกันทุกหน้า
 *
 * มิติที่อยู่ในข้อมูลอ่อนไหว (ศาสนา · เชื้อชาติ · ความพิการ · BMI) แสดงเฉพาะ
 * บทบาทที่ RLS ให้เห็นทั้งวิทยาลัย — บทบาทอื่นจะได้ตัวเลขที่นับไม่ครบโดยไม่รู้ตัว
 * (เหตุผลเต็มอยู่ที่ STUDENT_DIMENSIONS ฝั่ง API)
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num } from '../core/fmt';
import { useScope } from '../core/scope';
import type { Role } from '../core/session';
import { AsyncView, Card, Field, PageHead, RestrictedNotice, TableCard, useAsync, useCan } from '../ui/kit';

const REPORTS_ROLES: Role[] = ['registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin'];
const SENSITIVE_ROLES: Role[] = ['registrar', 'student_affairs', 'director', 'admin'];

interface Dimension { key: string; label: string; sensitive: boolean }
interface Breakdown { dimension: string; label: string; rows: { value: string; studyYear: number | null; students: number }[] }

const STATUS: Record<string, string> = {
  active: 'กำลังศึกษา',
  current: 'ยังมีสถานะ (รวมลาพัก/พักการเรียน)',
  graduated: 'สำเร็จการศึกษา',
  left: 'ออก (ลาออก · ย้าย · พ้นสภาพ)',
  all: 'ทั้งหมด',
};

export function StudentStatisticsScreen() {
  const canUse = useCan(...REPORTS_ROLES);
  const canSensitive = useCan(...SENSITIVE_ROLES);
  const yearId = useScope().yearId;
  const [dim, setDim] = useState('room');
  const [status, setStatus] = useState('active');

  const dims = useAsync(
    () => (canUse ? api.get<Dimension[]>('/reports/students/dimensions') : Promise.resolve([])),
    [canUse],
  );
  const current = (dims.data ?? []).find((d) => d.key === dim);
  const data = useAsync(
    () =>
      canUse && yearId && current
        ? api.get<Breakdown>(
            `/reports/students/${current.sensitive ? 'breakdown-sensitive' : 'breakdown'}${qs({ dimension: dim, academicYearId: yearId, status })}`,
          )
        : Promise.resolve(null as unknown as Breakdown),
    [canUse, yearId, dim, status, current?.sensitive],
  );

  if (!canUse) return <><PageHead title="สถิตินักศึกษา" /><RestrictedNotice roles={REPORTS_ROLES} /></>;

  return (
    <>
      <PageHead
        title="สถิตินักศึกษา"
        sub="จำนวนนักศึกษาแยกตามหัวข้อ × ชั้นปี ของปีการศึกษาที่เลือกด้านบน"
      />
      <div className="stats-layout">
        <Card title="หัวข้อ">
          <AsyncView state={dims}>
            {(list) => (
              <div className="stats-dims">
                {list.filter((d) => !d.sensitive || canSensitive).map((d) => (
                  <button
                    key={d.key}
                    className={d.key === dim ? 'active' : ''}
                    onClick={() => setDim(d.key)}
                  >
                    {d.label}
                    {d.sensitive && <small> · อ่อนไหว</small>}
                  </button>
                ))}
              </div>
            )}
          </AsyncView>
        </Card>
        <div>
          <Card title="สถานะนักศึกษา">
            <Field label="นับเฉพาะ">
              <select value={status} onChange={(e) => setStatus(e.target.value)}>
                {Object.entries(STATUS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            </Field>
          </Card>
          <TableCard title={current ? `จำนวนนักศึกษาแยกตาม${current.label}` : 'จำนวนนักศึกษา'}>
            <AsyncView state={data}>
              {(b) => (b ? <CrossTab b={b} /> : <p className="muted">เลือกปีการศึกษาด้านบนก่อน</p>)}
            </AsyncView>
          </TableCard>
        </div>
      </div>
    </>
  );
}

/** แถว = ค่าของมิติ · คอลัมน์ = ชั้นปี · "ยังไม่จัดห้อง" เป็นคอลัมน์ของตัวเองเสมอ */
function CrossTab({ b }: { b: Breakdown }) {
  if (b.rows.length === 0) return <p className="muted">ไม่มีนักศึกษาตามเงื่อนไขนี้</p>;
  const years = [...new Set(b.rows.map((r) => r.studyYear))].sort((x, y) => (x ?? 0) - (y ?? 0));
  const values = [...new Set(b.rows.map((r) => r.value))];
  const cell = (v: string, y: number | null) => b.rows.find((r) => r.value === v && r.studyYear === y)?.students ?? 0;
  const rowTotal = (v: string) => b.rows.filter((r) => r.value === v).reduce((t, r) => t + r.students, 0);
  const colTotal = (y: number | null) => b.rows.filter((r) => r.studyYear === y).reduce((t, r) => t + r.students, 0);
  const total = b.rows.reduce((t, r) => t + r.students, 0);

  return (
    <table>
      <thead>
        <tr>
          <th>{b.label}</th>
          {years.map((y) => <th key={String(y)} className="num">{y === null ? 'ยังไม่จัดชั้นปี' : `ชั้นปี ${y}`}</th>)}
          <th className="num">รวม</th>
          <th className="num">ร้อยละ</th>
        </tr>
      </thead>
      <tbody>
        {values.map((v) => (
          <tr key={v}>
            <td>{v}</td>
            {years.map((y) => <td key={String(y)} className="num">{cell(v, y) || ''}</td>)}
            <td className="num"><strong>{num(rowTotal(v), 0)}</strong></td>
            <td className="num">{((rowTotal(v) / total) * 100).toFixed(1)}</td>
          </tr>
        ))}
        <tr style={{ fontWeight: 600 }}>
          <td>รวม</td>
          {years.map((y) => <td key={String(y)} className="num">{num(colTotal(y), 0)}</td>)}
          <td className="num">{num(total, 0)}</td>
          <td className="num">100.0</td>
        </tr>
      </tbody>
    </table>
  );
}

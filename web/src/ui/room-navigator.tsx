/**
 * ตัวนำทางกลางของงานทะเบียน — หลักสูตร → ชั้นปี → ห้อง แบบคอลัมน์ไล่ลงของ SISA
 *
 * SISA ใช้วิธีเลือกขอบเขตแบบเดียวกันเกือบทุกหน้าของทะเบียนวัดผล ผู้ใช้เรียนครั้งเดียว
 * แล้วใช้ได้ทุกหน้า หน้าเราเลือกขอบเขตคนละแบบ — คอมโพเนนต์นี้คือแบบเดียวที่ทุกหน้า
 * ใช้ร่วมกัน ส่วนตัวเลข % ของแต่ละห้องให้หน้าที่เรียกส่งมาเอง เพราะ "ครบ" ของหน้า
 * ลงทะเบียนกับของหน้าส่งเกรดเป็นคนละเรื่อง
 *
 * ข้อมูลมาจาก `/registry/tree` (แถวแบนระดับห้อง) แล้วรวมขึ้นที่นี่ ไม่นับซ้ำที่ฐานข้อมูล
 * กอง "ยังไม่ผูกหลักสูตร" กับ "ยังไม่จัดห้อง" แสดงเสมอ — ซ่อนแล้วไม่มีใครเห็นงานที่ค้าง
 */
import type { ReactElement } from 'react';
import { api, qs } from '../core/api';
import { AsyncView, Badge, useAsync } from './kit';

export interface TreeRow {
  programTypeId: string | null; programTypeName: string | null;
  programId: string | null; programName: string | null; level: string | null;
  curriculumId: string | null; curriculumName: string | null; shift: string | null;
  studyYear: number | null; levelLabel: string | null; groupCode: string | null;
  students: number;
}

/** ความคืบหน้าของห้อง คีย์ `${studyYear}/${groupCode ?? ''}` */
export type RoomMetric = Map<string, { done: number; total: number }>;

export interface NavSelection { cur: string | null; studyYear: string | null; groupCode: string | null }

const NONE = '-';
const SHIFT: Record<string, string> = { morning: 'รอบเช้า', afternoon: 'รอบบ่าย', evening: 'รอบค่ำ', weekend: 'เสาร์-อาทิตย์' };
export const roomKeyOf = (studyYear: number | string | null, groupCode: string | null) => `${studyYear ?? ''}/${groupCode ?? ''}`;

function Pct({ m }: { m?: { done: number; total: number } }) {
  if (!m || m.total === 0) return <span className="muted">—</span>;
  const p = (m.done / m.total) * 100;
  return <Badge kind={p >= 100 ? 'ok' : p === 0 ? 'warn' : 'info'}>{p.toFixed(0)}%</Badge>;
}

function sum(rows: TreeRow[], metric?: RoomMetric) {
  if (!metric) return undefined;
  const seen = new Set<string>();
  let done = 0, total = 0;
  for (const r of rows) {
    const k = roomKeyOf(r.studyYear, r.groupCode);
    if (seen.has(k)) continue;
    seen.add(k);
    const m = metric.get(k);
    if (m) { done += m.done; total += m.total; }
  }
  return { done, total };
}

export function RoomNavigator({
  academicYearId, metric, metricLabel = 'ความคืบหน้า', value, onChange,
}: {
  academicYearId: string | null;
  metric?: RoomMetric;
  metricLabel?: string;
  value: NavSelection;
  onChange: (v: NavSelection) => void;
}) {
  const tree = useAsync(
    () => (academicYearId ? api.get<TreeRow[]>(`/registry/tree${qs({ academicYearId })}`) : Promise.resolve([])),
    [academicYearId],
  );
  return (
    <AsyncView state={tree} empty="ยังไม่มีการจัดชั้นปี/ห้องประจำในปีการศึกษานี้ — จัดห้องได้ที่หน้างานวิชาการรายปี">
      {(rows) => <Panels rows={rows} metric={metric} metricLabel={metricLabel} value={value} onChange={onChange} />}
    </AsyncView>
  );
}

function Panels({ rows, metric, metricLabel, value, onChange }: {
  rows: TreeRow[]; metric?: RoomMetric; metricLabel: string; value: NavSelection; onChange: (v: NavSelection) => void;
}) {
  const curKey = (r: TreeRow) => r.curriculumId ?? NONE;
  const curricula = [...new Map(rows.map((r) => [curKey(r), r])).values()];
  const inCur = value.cur ? rows.filter((r) => curKey(r) === value.cur) : [];
  const years = [...new Map(inCur.map((r) => [String(r.studyYear ?? ''), r])).values()];
  const inYear = value.studyYear !== null ? inCur.filter((r) => String(r.studyYear ?? '') === value.studyYear) : [];
  const total = (rs: TreeRow[]) => rs.reduce((t, r) => t + r.students, 0);

  const sel = rows.find((r) => curKey(r) === value.cur);
  const crumbs = [
    sel ? (sel.curriculumId ? `${sel.programTypeName} › ${sel.programName} › ${sel.curriculumName}` : 'ยังไม่ผูกหลักสูตร') : null,
    value.studyYear ? (inYear[0]?.levelLabel ?? `ชั้นปี ${value.studyYear}`) : null,
    value.groupCode ? (value.groupCode === NONE ? 'ยังไม่จัดห้อง' : `ห้อง ${value.groupCode}`) : null,
  ].filter(Boolean);

  let lastType: string | null | undefined;
  let lastProgram: string | null | undefined;
  return (
    <div className="card navigator">
      <div className="nav-bar">
        <strong>ขอบเขต:</strong> {crumbs.length ? crumbs.join(' › ') : <span className="muted">เลือกหลักสูตรทางซ้าย แล้วไล่ลงไปถึงห้อง</span>}
        <span className="muted" style={{ marginLeft: 'auto' }}>ทั้งปีการศึกษา {total(rows)} คน</span>
      </div>
      <div className="nav-cols">
        <div className="nav-col">
          <table>
            <thead><tr><th>ประเภทวิชา · สาขาวิชา · หลักสูตร</th><th className="num">คน</th><th className="num">{metricLabel}</th></tr></thead>
            <tbody>
              {curricula.map((c) => {
                const rs = rows.filter((r) => curKey(r) === curKey(c));
                const head: ReactElement[] = [];
                if (c.programTypeName !== lastType) {
                  lastType = c.programTypeName; lastProgram = undefined;
                  head.push(<tr key={`t${c.programTypeId}`} className="nav-group"><td colSpan={3}>{c.programTypeName ?? 'ยังไม่ผูกหลักสูตร'}</td></tr>);
                }
                if (c.curriculumId && c.programName !== lastProgram) {
                  lastProgram = c.programName;
                  head.push(<tr key={`p${c.programId}`} className="nav-sub"><td colSpan={3}>{c.programName}</td></tr>);
                }
                return [
                  ...head,
                  <tr key={curKey(c)} className={value.cur === curKey(c) ? 'sel' : ''}
                      onClick={() => onChange({ cur: curKey(c), studyYear: null, groupCode: null })}>
                    <td style={{ paddingLeft: 24 }}>{c.curriculumId ? `${c.curriculumName}${c.shift ? ` (${SHIFT[c.shift] ?? c.shift})` : ''}` : <em>นักศึกษาที่ยังไม่ผูกหลักสูตร</em>}</td>
                    <td className="num">{total(rs)}</td>
                    <td className="num"><Pct m={sum(rs, metric)} /></td>
                  </tr>,
                ];
              })}
            </tbody>
          </table>
        </div>
        <div className="nav-col">
          <table>
            <thead><tr><th>ระดับชั้น</th><th className="num">คน</th><th className="num">{metricLabel}</th></tr></thead>
            <tbody>
              {!value.cur ? <tr><td colSpan={3} className="muted">เลือกหลักสูตรก่อน</td></tr> : years.map((y) => {
                const rs = inCur.filter((r) => r.studyYear === y.studyYear);
                const k = String(y.studyYear ?? '');
                return (
                  <tr key={k} className={value.studyYear === k ? 'sel' : ''} onClick={() => onChange({ ...value, studyYear: k, groupCode: null })}>
                    <td>{y.levelLabel ?? `ชั้นปี ${y.studyYear}`}</td>
                    <td className="num">{total(rs)}</td>
                    <td className="num"><Pct m={sum(rs, metric)} /></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <div className="nav-col">
          <table>
            <thead><tr><th>ห้อง</th><th className="num">คน</th><th className="num">{metricLabel}</th></tr></thead>
            <tbody>
              {value.studyYear === null ? <tr><td colSpan={3} className="muted">เลือกระดับชั้นก่อน</td></tr> : inYear.map((r) => {
                const g = r.groupCode ?? NONE;
                return (
                  <tr key={g} className={value.groupCode === g ? 'sel' : ''} onClick={() => onChange({ ...value, groupCode: g })}>
                    <td>{r.groupCode ?? <em>ยังไม่จัดห้อง</em>}</td>
                    <td className="num">{r.students}</td>
                    <td className="num"><Pct m={metric?.get(roomKeyOf(r.studyYear, r.groupCode))} /></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

/** ค่าใน URL `groupCode=-` = กองยังไม่จัดห้อง (null ใน API) */
export const groupFromNav = (g: string | null) => (g === NONE ? null : g);

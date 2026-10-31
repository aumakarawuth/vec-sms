/**
 * รายงานบุคลากรแบบ SISA — หน้าละคำถาม (หมวดบุคลากร › ข้อมูลบุคลากร ·
 * ข้อมูลสถิติ · ฝึกอบรม) อ่านอย่างเดียวทั้งหมด
 *
 * สถิติ 10 กว่าเมนูของ SISA (ประเภทบุคลากร · อายุและเพศ · อายุราชการ · วุฒิ ·
 * ฝ่าย ฯลฯ) คือตารางรูปเดียวกัน จึงเป็นหน้าเดียวที่เลือกหัวข้อทางซ้าย
 * เหมือนสถิตินักศึกษา ไม่ใช่สิบหน้าที่หน้าตาเหมือนกัน
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num, thaiDate } from '../core/fmt';
import type { Role } from '../core/session';
import { AsyncView, Badge, Card, Field, PageHead, RestrictedNotice, TableCard, useAsync, useCan } from '../ui/kit';

const ROLES: Role[] = ['registrar', 'hr', 'director', 'admin'];

export const HR_REPORT_SECTIONS = {
  stats: { title: 'สถิติบุคลากร', sub: 'จำนวนบุคลากรแยกตามหัวข้อ × เพศ' },
  roster: { title: 'ทะเบียนบุคลากร', sub: 'ตำแหน่ง ฝ่าย อายุ อายุงาน วุฒิการศึกษา และใบอนุญาตประกอบวิชาชีพ' },
  training: { title: 'ชั่วโมงการฝึกอบรม', sub: 'ชั่วโมงอบรมสะสมรายคนตามช่วงวันที่' },
  leaves: { title: 'สถิติการลาของบุคลากร', sub: 'วันลาที่อนุมัติแล้ว แยกรายคนและประเภทการลา' },
  awards: { title: 'ผลงานและเกียรติประวัติบุคลากร', sub: 'รางวัลและผลงานที่บันทึกในระเบียนบุคลากร' },
} as const;
export type HrReportSection = keyof typeof HR_REPORT_SECTIONS;

const EMPLOYMENT: Record<string, string> = {
  civil_servant: 'ข้าราชการ', permanent: 'พนักงานประจำ', contract: 'สัญญาจ้าง',
  part_time: 'ไม่เต็มเวลา', industry_expert: 'ผู้เชี่ยวชาญจากสถานประกอบการ',
};
const LEAVE: Record<string, string> = {
  personal: 'ลากิจ', sick: 'ลาป่วย', maternity: 'ลาคลอด', ordination: 'ลาอุปสมบท',
  military: 'ลาตรวจเลือกทหาร', training: 'ลาศึกษา/อบรม', unpaid: 'ลาไม่รับค่าจ้าง', other: 'อื่น ๆ',
};

export function HrReportsScreen({ section }: { section: HrReportSection }) {
  const can = useCan(...ROLES);
  const meta = HR_REPORT_SECTIONS[section];
  return (
    <>
      <PageHead title={meta.title} sub={meta.sub} />
      {!can ? <RestrictedNotice roles={ROLES} /> : (
        <>
          {section === 'stats' && <Stats />}
          {section === 'roster' && <Roster />}
          {section === 'training' && <Training />}
          {section === 'leaves' && <Leaves />}
          {section === 'awards' && <Awards />}
        </>
      )}
    </>
  );
}

interface Breakdown { label: string; rows: { value: string; gender: string; staff: number }[] }

function Stats() {
  const [dim, setDim] = useState('employment');
  const [active, setActive] = useState(true);
  const dims = useAsync(() => api.get<{ key: string; label: string }[]>('/hr-reports/dimensions'), []);
  const data = useAsync(
    () => api.get<Breakdown>(`/hr-reports/breakdown${qs({ dimension: dim, active: String(active) })}`),
    [dim, active],
  );
  return (
    <div className="stats-layout">
      <Card title="หัวข้อ">
        <AsyncView state={dims}>
          {(list) => (
            <div className="stats-dims">
              {list.map((d) => (
                <button key={d.key} className={d.key === dim ? 'active' : ''} onClick={() => setDim(d.key)}>{d.label}</button>
              ))}
            </div>
          )}
        </AsyncView>
      </Card>
      <div>
        <Card title="ขอบเขต">
          <label className="row" style={{ gap: 8, alignItems: 'center' }}>
            <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} style={{ width: 'auto' }} />
            นับเฉพาะบุคลากรที่ยังปฏิบัติงานอยู่
          </label>
        </Card>
        <TableCard title={data.data ? `จำนวนบุคลากรแยกตาม${data.data.label}` : 'จำนวนบุคลากร'}>
          <AsyncView state={data}>
            {(b) => {
              if (b.rows.length === 0) return <p className="muted">ยังไม่มีบุคลากร</p>;
              const genders = ['ชาย', 'หญิง', 'ไม่ระบุ'].filter((g) => b.rows.some((r) => r.gender === g));
              const values = [...new Set(b.rows.map((r) => r.value))];
              const cell = (v: string, g: string) => b.rows.find((r) => r.value === v && r.gender === g)?.staff ?? 0;
              const total = b.rows.reduce((t, r) => t + r.staff, 0);
              const rowTotal = (v: string) => genders.reduce((t, g) => t + cell(v, g), 0);
              return (
                <table>
                  <thead>
                    <tr>
                      <th>{b.label}</th>
                      {genders.map((g) => <th key={g} className="num">{g}</th>)}
                      <th className="num">รวม</th>
                      <th className="num">ร้อยละ</th>
                    </tr>
                  </thead>
                  <tbody>
                    {values.map((v) => (
                      <tr key={v}>
                        <td>{v}</td>
                        {genders.map((g) => <td key={g} className="num">{cell(v, g) || ''}</td>)}
                        <td className="num"><strong>{rowTotal(v)}</strong></td>
                        <td className="num">{((rowTotal(v) / total) * 100).toFixed(1)}</td>
                      </tr>
                    ))}
                    <tr style={{ fontWeight: 600 }}>
                      <td>รวม</td>
                      {genders.map((g) => <td key={g} className="num">{b.rows.filter((r) => r.gender === g).reduce((t, r) => t + r.staff, 0)}</td>)}
                      <td className="num">{total}</td>
                      <td className="num">100.0</td>
                    </tr>
                  </tbody>
                </table>
              );
            }}
          </AsyncView>
        </TableCard>
      </div>
    </div>
  );
}

interface RosterRow {
  id: string; staff_code: string; full_name: string; employment_kind: string; is_teacher: boolean;
  position_th: string | null; department_th: string | null; age_years: number | null;
  started_on: string | null; education_th: string | null; license_no: string | null; license_expires: string | null;
}

function Roster() {
  const [active, setActive] = useState(true);
  const rows = useAsync(() => api.get<RosterRow[]>(`/hr-reports/roster${qs({ active: String(active) })}`), [active]);
  const today = new Date().toISOString().slice(0, 10);
  const soon = new Date(Date.now() + 90 * 864e5).toISOString().slice(0, 10);
  return (
    <TableCard
      title="ทะเบียนบุคลากร"
      actions={
        <label className="row" style={{ gap: 8, alignItems: 'center' }}>
          <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} style={{ width: 'auto' }} />
          เฉพาะที่ยังปฏิบัติงาน
        </label>
      }
    >
      <AsyncView state={rows} empty="ยังไม่มีบุคลากร">
        {(list) => (
          <table>
            <thead>
              <tr>
                <th style={{ width: 90 }}>รหัส</th>
                <th>ชื่อ</th>
                <th>ตำแหน่ง / ฝ่าย</th>
                <th style={{ width: 120 }}>ประเภท</th>
                <th className="num" style={{ width: 60 }}>อายุ</th>
                <th style={{ width: 110 }}>เริ่มงาน</th>
                <th>วุฒิล่าสุด</th>
                <th style={{ width: 150 }}>ใบอนุญาต</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td className="mono">{r.staff_code}</td>
                  <td><a href={`#/personnel-search/${r.id}`}>{r.full_name}</a></td>
                  <td>{r.position_th ?? '—'}{r.department_th ? <small className="muted"> · {r.department_th}</small> : null}</td>
                  <td>{EMPLOYMENT[r.employment_kind] ?? r.employment_kind}{r.is_teacher ? '' : <small className="muted"> · สนับสนุน</small>}</td>
                  <td className="num">{r.age_years ?? '—'}</td>
                  <td>{r.started_on ? thaiDate(r.started_on) : '—'}</td>
                  <td>{r.education_th ?? '—'}</td>
                  <td>
                    {r.license_no ?? '—'}
                    {r.license_expires && r.license_expires < today && <> <Badge kind="danger">หมดอายุ</Badge></>}
                    {r.license_expires && r.license_expires >= today && r.license_expires <= soon && <> <Badge kind="warn">ใกล้หมด</Badge></>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

function DateRange({ from, to, setFrom, setTo }: { from: string; to: string; setFrom: (v: string) => void; setTo: (v: string) => void }) {
  return (
    <div className="row" style={{ gap: 8 }}>
      <Field label="ตั้งแต่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
      <Field label="ถึง"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
    </div>
  );
}

function Training() {
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const rows = useAsync(
    () => api.get<{ id: string; staff_code: string; full_name: string; courses: string; hours: string }[]>(
      `/hr-reports/training${qs({ from: from || undefined, to: to || undefined })}`),
    [from, to],
  );
  return (
    <TableCard title="ชั่วโมงอบรมรายคน" actions={<DateRange {...{ from, to, setFrom, setTo }} />}>
      <AsyncView state={rows} empty="ยังไม่มีบุคลากร">
        {(list) => (
          <table>
            <thead>
              <tr>
                <th style={{ width: 90 }}>รหัส</th>
                <th>ชื่อ</th>
                <th className="num" style={{ width: 110 }}>จำนวนหลักสูตร</th>
                <th className="num" style={{ width: 110 }}>ชั่วโมง</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td className="mono">{r.staff_code}</td>
                  <td>{r.full_name}</td>
                  <td className="num">{r.courses}</td>
                  <td className="num">{Number(r.hours) ? num(Number(r.hours), 1) : <span className="muted">ยังไม่มี</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

function Leaves() {
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const rows = useAsync(
    () => api.get<{ id: string; staff_code: string; full_name: string; kind: string; days: string; times: string }[]>(
      `/hr-reports/leaves${qs({ from: from || undefined, to: to || undefined })}`),
    [from, to],
  );
  return (
    <TableCard title="วันลาที่อนุมัติแล้ว" actions={<DateRange {...{ from, to, setFrom, setTo }} />}>
      <AsyncView state={rows} empty="ยังไม่มีการลาที่อนุมัติในช่วงนี้">
        {(list) => {
          const kinds = [...new Set(list.map((r) => r.kind))];
          const people = [...new Map(list.map((r) => [r.id, r])).values()];
          const days = (id: string, k: string) => Number(list.find((r) => r.id === id && r.kind === k)?.days ?? 0);
          return (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 90 }}>รหัส</th>
                  <th>ชื่อ</th>
                  {kinds.map((k) => <th key={k} className="num">{LEAVE[k] ?? k} (วัน)</th>)}
                  <th className="num">รวม (วัน)</th>
                </tr>
              </thead>
              <tbody>
                {people.map((p) => (
                  <tr key={p.id}>
                    <td className="mono">{p.staff_code}</td>
                    <td>{p.full_name}</td>
                    {kinds.map((k) => <td key={k} className="num">{days(p.id, k) || ''}</td>)}
                    <td className="num"><strong>{kinds.reduce((t, k) => t + days(p.id, k), 0)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          );
        }}
      </AsyncView>
    </TableCard>
  );
}

function Awards() {
  const rows = useAsync(
    () => api.get<{ id: string; title_th: string; organization_th: string | null; started_on: string | null; staff_code: string; full_name: string }[]>('/hr-reports/awards'),
    [],
  );
  return (
    <TableCard title="ผลงานและเกียรติประวัติ">
      <AsyncView state={rows} empty="ยังไม่มีผลงานที่บันทึก — เพิ่มได้ที่ระเบียนบุคลากรรายคน">
        {(list) => (
          <table>
            <thead>
              <tr>
                <th style={{ width: 110 }}>วันที่</th>
                <th>ผลงาน</th>
                <th>หน่วยงานที่มอบ</th>
                <th>บุคลากร</th>
              </tr>
            </thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td>{r.started_on ? thaiDate(r.started_on) : '—'}</td>
                  <td>{r.title_th}</td>
                  <td>{r.organization_th ?? '—'}</td>
                  <td>{r.staff_code} {r.full_name}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </AsyncView>
    </TableCard>
  );
}

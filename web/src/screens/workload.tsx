import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { href } from '../core/router';
import type { Role } from '../core/session';
import { AsyncView, Badge, Card, PageHead, RestrictedNotice, TableCard, useAsync, useCan } from '../ui/kit';
import { TermDates, TermSelect, useTermPicker } from '../ui/term-picker';

interface WorkloadRow {
  staff_id: string;
  staff_code: string;
  teacher_name: string;
  department_name: string | null;
  position_th: string | null;
  section_count: string | number;
  course_count: string | number;
  weekly_periods: string | number;
  planned_periods: string | number;
  students: string | number;
  unscheduled_sections: string | number;
}

const n = (value: string | number) => Number(value) || 0;

/** /timetable/terms/:id/workload อยู่ใต้คอนโทรลเลอร์เดียวกับ /timetable — registrar/academic/director/admin เท่านั้น */
const WORKLOAD_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];

export function WorkloadScreen() {
  const canUse = useCan(...WORKLOAD_ROLES);
  const { terms, termId, term, setTerm } = useTermPicker();
  const workload = useAsync(
    () => canUse && termId
      ? api.get<WorkloadRow[]>(`/timetable/terms/${termId}/workload`)
      : Promise.resolve([]),
    [canUse, termId],
  );
  const [query, setQuery] = useState('');
  const [onlyNeedsAttention, setOnlyNeedsAttention] = useState(false);

  const rows = useMemo(() => {
    const q = query.trim().toLocaleLowerCase('th');
    return (workload.data ?? []).filter((row) => {
      if (onlyNeedsAttention && n(row.unscheduled_sections) === 0) return false;
      if (!q) return true;
      return [row.staff_code, row.teacher_name, row.department_name, row.position_th]
        .some((value) => value?.toLocaleLowerCase('th').includes(q));
    });
  }, [workload.data, query, onlyNeedsAttention]);

  const all = workload.data ?? [];
  const totalWeekly = all.reduce((sum, row) => sum + n(row.weekly_periods), 0);
  const missing = all.reduce((sum, row) => sum + n(row.unscheduled_sections), 0);
  const activeTeachers = all.filter((row) => n(row.section_count) > 0).length;

  return (
    <>
      <PageHead
        title="ภาระงานสอน"
        sub={term ? <TermDates term={term} /> : 'สรุปจากกลุ่มเรียนและคาบที่จัดไว้จริง'}
        actions={<a href={href('/timetable-center')}>← ศูนย์งานตารางเรียน</a>}
      />

      {!canUse ? (
        <RestrictedNotice roles={WORKLOAD_ROLES} />
      ) : (
      <>
      <Card>
        <div className="row">
          <label className="field" style={{ minWidth: 260 }}>
            <span>ภาคเรียน</span>
            <AsyncView state={terms} empty="ยังไม่มีภาคเรียน">
              {(list) => <TermSelect terms={list} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </label>
          <label className="field" style={{ minWidth: 280 }}>
            <span>ค้นหาครู/รหัส/หน่วยงาน</span>
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="พิมพ์เพื่อกรองรายการ" />
          </label>
          <label className="field" style={{ alignSelf: 'end' }}>
            <span>ตัวกรอง</span>
            <span className="row" style={{ minHeight: 36 }}>
              <input
                type="checkbox"
                checked={onlyNeedsAttention}
                onChange={(e) => setOnlyNeedsAttention(e.target.checked)}
              />
              เฉพาะกลุ่มที่ยังไม่ลงตาราง
            </span>
          </label>
        </div>
      </Card>

      <div className="registry-summary">
        <Stat label="ครูที่มีภาระสอน" value={activeTeachers} note={`จากครูทั้งหมด ${all.length} คน`} color="primary" />
        <Stat label="คาบสอนต่อสัปดาห์" value={totalWeekly} note="นับจากตารางที่วางจริง" color="success" />
        <Stat label="กลุ่มที่ต้องจัดต่อ" value={missing} note="ยังไม่มีคาบในตาราง" color={missing ? 'warning' : 'success'} />
      </div>

      <TableCard
        title="ภาระงานรายบุคคล"
        actions={<button onClick={() => workload.reload()}>โหลดใหม่</button>}
      >
        <AsyncView state={workload} empty="ยังไม่มีรายชื่อครู">
          {() => rows.length === 0 ? (
            <div className="empty">ไม่พบรายการตามตัวกรอง</div>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>ผู้สอน</th>
                  <th>หน่วยงาน/ตำแหน่ง</th>
                  <th className="num">รายวิชา</th>
                  <th className="num">กลุ่ม</th>
                  <th className="num">คาบ/สัปดาห์</th>
                  <th className="num">คาบทั้งภาค</th>
                  <th className="num">นักศึกษา</th>
                  <th>สถานะตาราง</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => {
                  const unscheduled = n(row.unscheduled_sections);
                  return (
                    <tr key={row.staff_id}>
                      <td><strong>{row.teacher_name}</strong><br /><small className="mono">{row.staff_code}</small></td>
                      <td>{row.department_name ?? '—'}<br /><small>{row.position_th ?? 'ยังไม่ระบุตำแหน่ง'}</small></td>
                      <td className="num">{n(row.course_count)}</td>
                      <td className="num">{n(row.section_count)}</td>
                      <td className="num"><strong>{n(row.weekly_periods)}</strong></td>
                      <td className="num">{n(row.planned_periods)}</td>
                      <td className="num">{n(row.students)}</td>
                      <td>{unscheduled > 0
                        ? <Badge kind="warn">ยังไม่ลงตาราง {unscheduled} กลุ่ม</Badge>
                        : n(row.section_count) > 0
                          ? <Badge kind="ok">ลงตารางแล้ว</Badge>
                          : <Badge>ยังไม่มีภาระสอน</Badge>}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <p className="hint">
        “คาบ/สัปดาห์” นับจากคาบประจำสัปดาห์ที่จัดไว้จริง ส่วน “คาบทั้งภาค” เป็นแผนที่ใช้คำนวณเวลาเรียน
        จึงเป็นคนละหน่วยและไม่ควรนำมาเปรียบเทียบกันโดยตรง
      </p>
      </>
      )}
    </>
  );
}

function Stat({ label, value, note, color }: { label: string; value: number; note: string; color: string }) {
  return <div className={`registry-stat ${color}`}><span>{label}</span><strong>{value}</strong><small>{note}</small></div>;
}

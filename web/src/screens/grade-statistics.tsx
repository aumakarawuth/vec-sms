/**
 * สถิติทะเบียนวัดผลแบบ SISA — สรุปผลการประเมินรายวิชา (จำนวนลงทะเบียน ·
 * การกระจายเกรด · คะแนนเฉลี่ย) และ ขาด ลา มาสาย แยกห้อง ของภาคเรียนที่เลือก
 * ด้านบน · อ่านอย่างเดียว
 */
import { api } from '../core/api';
import { num } from '../core/fmt';
import { useScope } from '../core/scope';
import type { Role } from '../core/session';
import { AsyncView, Badge, PageHead, RestrictedNotice, TableCard, useAsync, useCan } from '../ui/kit';

const ROLES: Role[] = ['registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin'];

interface CourseRow {
  sectionId: string; courseCode: string; courseName: string; sectionNo: string; teacherName: string | null;
  enrolled: number; graded: number; passed: number; avgScore: number | null; distribution: Record<string, number>;
}
interface RoomRow {
  studyYear: number | null; groupCode: string | null; students: number;
  present: number; late: number; leaveSick: number; leavePersonal: number; activity: number; absent: number;
}

export function GradeStatisticsScreen() {
  const can = useCan(...ROLES);
  const termId = useScope().termId;
  const courses = useAsync(
    () => (can && termId ? api.get<CourseRow[]>(`/reports/terms/${termId}/course-results`) : Promise.resolve([])),
    [can, termId],
  );
  const rooms = useAsync(
    () => (can && termId ? api.get<RoomRow[]>(`/reports/terms/${termId}/attendance-by-room`) : Promise.resolve([])),
    [can, termId],
  );
  if (!can) return <><PageHead title="สถิติผลการเรียนและเวลาเรียน" /><RestrictedNotice roles={ROLES} /></>;

  return (
    <>
      <PageHead
        title="สถิติผลการเรียนและเวลาเรียน"
        sub="ผลการประเมินรายวิชา และ ขาด ลา มาสาย แยกห้อง ของภาคเรียนที่เลือกด้านบน"
      />
      <TableCard title="สรุปผลการประเมินรายวิชา">
        <AsyncView state={courses} empty="ภาคเรียนนี้ยังไม่มีกลุ่มเรียน">
          {(list) => {
            const symbols = [...new Set(list.flatMap((r) => Object.keys(r.distribution)))].sort((a, b) => Number(b) - Number(a) || a.localeCompare(b));
            return (
              <table>
                <thead>
                  <tr>
                    <th>รายวิชา</th>
                    <th style={{ width: 70 }}>กลุ่ม</th>
                    <th>ผู้สอน</th>
                    <th className="num" style={{ width: 80 }}>ลงทะเบียน</th>
                    {symbols.map((s) => <th key={s} className="num" style={{ width: 50 }}>{s}</th>)}
                    <th className="num" style={{ width: 70 }}>ผ่าน</th>
                    <th className="num" style={{ width: 80 }}>คะแนนเฉลี่ย</th>
                  </tr>
                </thead>
                <tbody>
                  {list.map((r) => (
                    <tr key={r.sectionId}>
                      <td><span className="mono">{r.courseCode}</span> {r.courseName}</td>
                      <td>{r.sectionNo}</td>
                      <td>{r.teacherName ?? '—'}</td>
                      <td className="num">{r.enrolled}</td>
                      {r.graded === 0
                        ? <td colSpan={symbols.length || 1}><Badge kind="warn">ยังไม่มีผล</Badge></td>
                        : symbols.map((s) => <td key={s} className="num">{r.distribution[s] || ''}</td>)}
                      <td className="num">{r.graded ? r.passed : ''}</td>
                      <td className="num">{r.avgScore === null ? '—' : num(r.avgScore, 2)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            );
          }}
        </AsyncView>
      </TableCard>

      <TableCard title="ขาด ลา มาสาย แยกห้อง (นับเป็นคาบ)">
        <AsyncView state={rooms} empty="ยังไม่มีการเช็คชื่อในภาคเรียนนี้">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th>ห้อง</th>
                  <th className="num">นักศึกษา</th>
                  <th className="num">มาเรียน</th>
                  <th className="num">สาย</th>
                  <th className="num">ลาป่วย</th>
                  <th className="num">ลากิจ</th>
                  <th className="num">กิจกรรม</th>
                  <th className="num">ขาด</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={`${r.studyYear}|${r.groupCode}`}>
                    <td>{r.groupCode ? `ชั้นปี ${r.studyYear} · ห้อง ${r.groupCode}` : 'ยังไม่จัดห้อง'}</td>
                    <td className="num">{r.students}</td>
                    <td className="num">{r.present}</td>
                    <td className="num">{r.late || ''}</td>
                    <td className="num">{r.leaveSick || ''}</td>
                    <td className="num">{r.leavePersonal || ''}</td>
                    <td className="num">{r.activity || ''}</td>
                    <td className="num">{r.absent ? <strong>{r.absent}</strong> : ''}</td>
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

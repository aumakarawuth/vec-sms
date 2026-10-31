/**
 * สถิติทะเบียนวัดผลแบบ SISA — สรุปผลการประเมินรายวิชา (จำนวนลงทะเบียน ·
 * การกระจายเกรด · คะแนนเฉลี่ย) และ ขาด ลา มาสาย แยกห้อง ของภาคเรียนที่เลือก
 * ด้านบน · อ่านอย่างเดียว
 */
import { api, qs } from '../core/api';
import { num } from '../core/fmt';
import { navigate, useRoute } from '../core/router';
import { useScope } from '../core/scope';
import { groupFromNav, RoomNavigator } from '../ui/room-navigator';
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
  const scope = useScope();
  const termId = scope.termId;
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

      {termId && <RoomScoresCard termId={termId} academicYearId={scope.term?.academic_year_id ?? null} />}

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

interface ScoreRow {
  student_id: string; student_code: string; class_number: number | null; full_name: string;
  section_id: string; course_code: string; course_name: string;
  weighted: string; weight_filled: string; weight_total: string;
}

/**
 * ผลรวมคะแนนเก็บของห้อง — SISA "ผลรวมคะแนนเก็บ" ตาราง นักศึกษา × รายวิชา
 * คะแนนสูตรเดียวกับตอนตัดเกรด ช่องที่ครูยังกรอกไม่ครบแสดงสัดส่วนที่กรอกแล้วด้วย
 */
function RoomScoresCard({ termId, academicYearId }: { termId: string; academicYearId: string | null }) {
  /* เลือกห้องผ่านตัวนำทางกลางแบบเดียวกับหน้าลงทะเบียน และเก็บไว้ใน URL ให้ส่งลิงก์ต่อได้ */
  const route = useRoute();
  const nav = { cur: route.query.get('cur'), studyYear: route.query.get('studyYear'), groupCode: route.query.get('groupCode') };
  const room = nav.groupCode ?? '';
  const data = useAsync(
    () => (room ? api.get<ScoreRow[]>(`/reports/terms/${termId}/room-scores${qs({ groupCode: groupFromNav(room) ?? undefined })}`) : Promise.resolve([])),
    [termId, room],
  );
  const setNav = (v: typeof nav) => {
    const q = new URLSearchParams(route.query);
    for (const [k, x] of Object.entries(v)) { if (x) q.set(k, x); else q.delete(k); }
    navigate(`${route.path}?${q.toString()}`);
  };
  return (
    <TableCard title="ผลรวมคะแนนเก็บของห้อง">
      <RoomNavigator academicYearId={academicYearId} value={nav} onChange={setNav} />
      {!room ? <p className="muted">เลือกห้องเพื่อดูคะแนนเก็บของทุกคนในทุกวิชา</p> : (
        <AsyncView state={data} empty="ห้องนี้ยังไม่มีการลงทะเบียนในภาคเรียนนี้">
          {(list) => {
            const courses = [...new Map(list.map((r) => [r.section_id, r])).values()];
            const people = [...new Map(list.map((r) => [r.student_id, r])).values()];
            const cell = (sid: string, sec: string) => list.find((r) => r.student_id === sid && r.section_id === sec);
            return (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 50 }}>เลขที่</th>
                    <th>ชื่อ</th>
                    {courses.map((c) => (
                      <th key={c.section_id} className="num" title={c.course_name}>
                        {c.course_code}<br /><small className="muted">เต็ม {Number(c.weight_total)}</small>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {people.map((p) => (
                    <tr key={p.student_id}>
                      <td>{p.class_number ?? ''}</td>
                      <td>{p.student_code} {p.full_name}</td>
                      {courses.map((c) => {
                        const x = cell(p.student_id, c.section_id);
                        if (!x) return <td key={c.section_id} className="num muted">—</td>;
                        const partial = Number(x.weight_filled) < Number(x.weight_total);
                        return (
                          <td key={c.section_id} className="num" title={partial ? `กรอกแล้ว ${Number(x.weight_filled)} จาก ${Number(x.weight_total)}` : ''}>
                            {num(Number(x.weighted), 2)}{partial && <small className="muted"> *</small>}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            );
          }}
        </AsyncView>
      )}
      <p className="hint">* ครูยังกรอกคะแนนไม่ครบทุกรายการ — ชี้ที่ตัวเลขเพื่อดูว่ากรอกแล้วเท่าไรจากเต็ม</p>
    </TableCard>
  );
}

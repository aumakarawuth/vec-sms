/**
 * ข้อมูลสถิติภาพรวม
 *
 * รวมตัวเลขที่มีอยู่แล้วในแต่ละโมดูล (นักศึกษา บุคลากร การเงิน เฝ้าระวัง
 * หลักสูตร) มาไว้จุดเดียว — ไม่มีข้อมูลใหม่ ไม่มีการคำนวณใหม่ อ่านจาก
 * `GET /reports/summary` ที่นับที่ฐานข้อมูลโดยตรง ไม่โหลดรายการมานับเอง
 */
import { api } from '../core/api';
import { num } from '../core/fmt';
import { href } from '../core/router';
import type { Role } from '../core/session';
import { AsyncView, Card, PageHead, RestrictedNotice, TableCard, useAsync, useCan } from '../ui/kit';

/** /reports/* ผูก @Roles ไว้ทั้งคอนโทรลเลอร์ — เช็คเดียวกับ /grade-reports */
const REPORTS_ROLES: Role[] = ['registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin'];

interface Summary {
  students: { total: number; active: number; onLeave: number; suspended: number; graduated: number; withdrawn: number };
  staff: { total: number; teachers: number };
  finance: { arOutstanding: number; invoicesUnpaid: number };
  risk: { openCases: number };
  curriculum: { activeVersions: number };
}

interface CurriculumRow {
  curriculum_name: string;
  edition_be: number;
  shift: string | null;
  active_students: string;
}

function Stat({ title, value, note, tone }: { title: string; value: string; note?: string; tone?: string }) {
  return (
    <div className={`registry-stat ${tone ?? 'primary'}`}>
      <span>{title}</span>
      <strong>{value}</strong>
      {note && <small>{note}</small>}
    </div>
  );
}

export function StatisticsScreen() {
  const canUse = useCan(...REPORTS_ROLES);
  // ไม่ยิงถ้าไม่มีสิทธิ์ — คืนค่าหลอกเมื่อ !canUse เพราะไม่มีวันถูก AsyncView อ่านจริง (อยู่นอกกิ่งที่เรนเดอร์)
  const summary = useAsync(
    () => (canUse ? api.get<Summary>('/reports/summary') : Promise.resolve(null as unknown as Summary)),
    [canUse],
  );
  const byCurriculum = useAsync(
    () => (canUse ? api.get<CurriculumRow[]>('/reports/by-curriculum') : Promise.resolve([])),
    [canUse],
  );

  return (
    <>
      <PageHead
        title="ข้อมูลสถิติ"
        sub="ภาพรวมของทั้งวิทยาลัย ณ ขณะนี้ — ตัวเลขจากฐานข้อมูลจริง ไม่ใช่ตัวอย่าง"
        actions={<a href={href('/registry')}>← ศูนย์งานทะเบียน</a>}
      />

      {!canUse ? (
        <RestrictedNotice roles={REPORTS_ROLES} />
      ) : (
      <>
      <AsyncView state={summary}>
        {(s) => (
          <>
            <Card title="นักศึกษา">
              <div className="registry-summary">
                <Stat title="ทั้งหมด" value={num(s.students.total, 0)} tone="primary" />
                <Stat title="กำลังเรียน" value={num(s.students.active, 0)} tone="success" />
                <Stat title="ลาพัก" value={num(s.students.onLeave, 0)} tone="warning" />
                <Stat title="ถูกระงับสิทธิ์" value={num(s.students.suspended, 0)} tone="warning" />
                <Stat title="สำเร็จการศึกษา" value={num(s.students.graduated, 0)} tone="success" />
                <Stat title="พ้นสภาพ" value={num(s.students.withdrawn, 0)} tone="warning" />
              </div>
            </Card>

            <Card title="บุคลากร">
              <div className="registry-summary">
                <Stat title="ทั้งหมด" value={num(s.staff.total, 0)} tone="primary" />
                <Stat title="เป็นครูผู้สอน" value={num(s.staff.teachers, 0)} tone="success" />
              </div>
            </Card>

            <Card title="การเงิน">
              <div className="registry-summary">
                <Stat
                  title="ค้างชำระรวม"
                  value={`${num(s.finance.arOutstanding, 2)} บาท`}
                  tone={s.finance.arOutstanding > 0 ? 'warning' : 'success'}
                />
                <Stat title="ใบแจ้งหนี้ยังไม่ปิด" value={num(s.finance.invoicesUnpaid, 0)} tone="warning" />
              </div>
            </Card>

            <Card title="เฝ้าระวังและติดตาม">
              <div className="registry-summary">
                <Stat
                  title="เคสที่ยังเปิดอยู่"
                  value={num(s.risk.openCases, 0)}
                  tone={s.risk.openCases > 0 ? 'warning' : 'success'}
                />
              </div>
            </Card>

            <Card title="หลักสูตร">
              <div className="registry-summary">
                <Stat title="ฉบับที่ใช้งานอยู่" value={num(s.curriculum.activeVersions, 0)} tone="primary" />
              </div>
            </Card>
          </>
        )}
      </AsyncView>

      <TableCard title="นักศึกษากำลังเรียนแยกตามสาขา">
        <AsyncView state={byCurriculum} empty="ยังไม่มีนักศึกษาผูกหลักสูตร">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th>สาขา/หลักสูตร</th>
                  <th style={{ width: 90 }}>ฉบับ</th>
                  <th style={{ width: 110 }}>ภาค</th>
                  <th className="num" style={{ width: 120 }}>กำลังเรียน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i}>
                    <td>{r.curriculum_name}</td>
                    <td>{r.edition_be}</td>
                    <td>{r.shift ?? '—'}</td>
                    <td className="num">{num(r.active_students, 0)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
      </>
      )}
    </>
  );
}

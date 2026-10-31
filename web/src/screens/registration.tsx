/**
 * ลงทะเบียนเรียน — เริ่มจากห้อง ไม่ใช่จากรายชื่อคน
 *
 * ─── ทำไมหน้านี้ไม่เปิดมาเป็นรายชื่อนักศึกษา ───
 * ของเดิมโหลด `/students?limit=200` มาทั้งก้อนแล้วให้ติ๊กเอาเอง ซึ่งทำงานได้
 * กับข้อมูลตัวอย่างสิบสองคน และ **ใช้ไม่ได้เลย**กับวิทยาลัยจริงที่มีพันคน —
 * แปดร้อยคนที่เหลือไม่มีช่องติ๊กอยู่บนหน้าจอตั้งแต่แรก และปุ่ม "เลือกทั้งหมด"
 * เลือกสองร้อยคนแรกตามรหัส ซึ่งไม่ตรงกับห้องไหน ชั้นปีไหน หรือหลักสูตรไหนเลย
 *
 * งานทะเบียนลงทะเบียน**เป็นห้อง** — คอมเมนต์ของ `register_courses_bulk` ที่
 * ชั้น API เขียนไว้เองว่าห้องหนึ่งใหญ่สุดราวสี่สิบคน หน้าจอเป็นชิ้นเดียวที่
 * ไม่ได้ทำตามสมมติฐานนั้น วิทยาลัยพันคนมีห้องราวสามสิบห้อง ซึ่งอ่านครบได้
 * ในหน้าจอเดียว
 *
 * ─── ทำไมยังต้องมีทางรายคน ───
 * เด็กตกค้าง เรียนซ้ำ เทียบโอน และคนที่เรียนไม่ตามแผน ลงเป็นห้องไม่ได้จริง ๆ
 * — แต่เป็น**ทางที่สอง** ไม่ใช่ทางหลัก จึงอยู่คนละแท็บ
 *
 * ─── ทำไมต้องแสดงผลรายคน ไม่ใช่ "สำเร็จ/ไม่สำเร็จ" ───
 * `register_courses_bulk()` ตั้งใจไม่ raise เมื่อมีคนติดเงื่อนไข เพราะ
 * rollback จะล้างงานของคนที่ผ่านไปด้วย — คนหนึ่งค้างค่าเทอมต้องไม่ทำให้
 * ทั้งห้องลงทะเบียนไม่ได้ หน้าจอจึงต้องแสดงว่าใครติดอะไรเป็นรายคน
 * มิฉะนั้นเจ้าหน้าที่จะไม่รู้ว่าต้องตามใคร
 */
import { useEffect, useState } from 'react';
import { groupFromNav, RoomNavigator, roomKeyOf } from '../ui/room-navigator';
import { api, qs } from '../core/api';
import { fetchSections, type Section } from '../core/catalog';
import { num } from '../core/fmt';
import { navigate, useRoute } from '../core/router';
import {
  AsyncView, Badge, Card, Field, Notice, PageHead, PrintButton, TableCard, Tabs, useAsync,
} from '../ui/kit';
import { TermDates, TermSelect, useTermPicker } from '../ui/term-picker';

/** เพดานของ `/registration/register-bulk` — เกินกว่านี้ต้องแบ่งเป็นหลายคำขอ */
const BULK_MAX = 200;

interface Room {
  academic_year_id: string;
  study_year: number;
  group_code: string | null;
  students_total: number;
  students_registered: number;
  students_pending: number;
  pct: string | null;
}

interface PlanSection {
  id: string;
  sectionNo: string;
  capacity: number;
  enrolled: number;
  teacherName: string;
  isLocked: boolean;
}

interface PlanCourse {
  courseId: string;
  code: string;
  nameTh: string;
  credits: string;
  required: boolean;
  studentsInPlan: number;
  wholeRoom: boolean;
  sections: PlanSection[];
  suggestedSectionId: string | null;
  suggestedReason: string | null;
}

interface PlanStudent {
  id: string;
  studentCode: string;
  fullName: string;
  status: string;
  registered: number;
  hasCurriculum: boolean;
}

interface RoomPlan {
  term: { id: string; ordinal: number; yearBe: number };
  room: { academicYearId: string; studyYear: number; groupCode: string | null };
  students: PlanStudent[];
  studentsTotal: number;
  studentsTruncated: boolean;
  registerable: number;
  plannable: number;
  withoutCurriculum: number;
  courses: PlanCourse[];
  planEmptyReason: string | null;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
  status: string;
  study_year: number | null;
  group_code: string | null;
}

interface FailedCourse {
  course_id: string;
  course_code: string;
  course_name: string;
  grade_symbol: string;
  term_label: string;
}

interface RetakeCharge {
  id: string;
  credits: string;
  rate_per_credit: string;
  amount: string;
  status: 'pending' | 'paid' | 'waived';
}

interface BulkResult {
  requested: number;
  succeeded: number;
  blocked: number;
  results: { studentId: string; registered: number; blockers: string[] }[];
}

interface CheckResult {
  canRegister: boolean;
  blockingCount: number;
  warningCount: number;
  problems: { code: string; severity: 'block' | 'warn' | 'info'; message_th: string; waived: boolean }[];
}

const roomLabel = (r: { study_year: number; group_code: string | null }) =>
  r.group_code ? `ปี ${r.study_year} ห้อง ${r.group_code}` : `ปี ${r.study_year} — ยังไม่จัดห้อง`;

function toggle<T>(set: Set<T>, id: T): Set<T> {
  const next = new Set(set);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return next;
}

/**
 * ยิงเป็นก้อนละไม่เกิน 200 คน แล้วรวมผล
 *
 * เพดานฝั่ง API มีเหตุผลของมัน (ทรานแซกชันที่ล็อกตาราง enrollment ค้างไว้
 * นานจนคนอื่นลงทะเบียนไม่ได้ทั้งวิทยาลัย) การแบ่งก้อนจึงเป็นการทำตามเพดาน
 * ไม่ใช่การหลบ — แต่ละก้อนยังเป็นทรานแซกชันสั้นเหมือนเดิม
 *
 * ที่ต้องมีเพราะกอง "ยังไม่จัดห้อง" ของวิทยาลัยที่เพิ่งเริ่มใช้ระบบคือ
 * นักศึกษาทั้งวิทยาลัย ถ้าไม่แบ่งให้ ปุ่มจะกดไม่ได้เลยโดยไม่มีทางออก
 */
async function registerInChunks(
  studentIds: string[],
  termId: string,
  sectionIds: string[],
  onProgress: (done: number) => void,
): Promise<BulkResult> {
  const merged: BulkResult = { requested: 0, succeeded: 0, blocked: 0, results: [] };
  for (let i = 0; i < studentIds.length; i += BULK_MAX) {
    const chunk = studentIds.slice(i, i + BULK_MAX);
    const r = await api.post<BulkResult>('/registration/register-bulk', {
      studentIds: chunk, termId, sectionIds,
    });
    merged.requested += r.requested;
    merged.succeeded += r.succeeded;
    merged.blocked += r.blocked;
    merged.results.push(...r.results);
    onProgress(Math.min(i + BULK_MAX, studentIds.length));
  }
  return merged;
}

/**
 * ป้ายผลรายคน
 *
 * ─── ทำไม "0 วิชา" ไม่ใช่ความล้มเหลวเสมอไป ───
 * `register_courses_bulk` ใช้ `on conflict do nothing` คนที่ลงครบไปแล้วจึง
 * ได้ 0 กลับมาโดยไม่ติดอะไรสักข้อ ของเดิมทาสีแดงให้ทุกแถวที่ได้ 0 — กดลง
 * ห้องเดิมซ้ำเพื่อเก็บคนที่เพิ่งย้ายเข้ามา แล้วอีกสี่สิบคนกลายเป็นสีแดง
 * ทั้งที่ไม่มีอะไรผิดสักอย่าง
 */
function ResultBadge({ registered, blocked }: { registered: number; blocked: boolean }) {
  if (blocked) return <Badge kind="danger">ติดเงื่อนไข</Badge>;
  if (registered > 0) return <Badge kind="ok">ลงเพิ่ม {registered} วิชา</Badge>;
  return <Badge kind="info">ลงครบอยู่แล้ว</Badge>;
}

export function RegistrationScreen() {
  const route = useRoute();
  const { terms, termId, term, setTerm } = useTermPicker();

  const tab = route.query.get('tab') === 'student' ? 'student' : 'room';

  /*
   * ห้องที่เลือกอยู่ใน URL เหมือนภาคเรียนและแท็บของหน้าระเบียนนักศึกษา —
   * เจ้าหน้าที่ส่งลิงก์หากันทางแชทเป็นเรื่องปกติ ("ห้องนี้ยังไม่ครบนะ")
   * ถ้าเก็บใน state ล้วน คนรับจะเปิดมาที่รายการห้องเปล่า ๆ แล้วต้องเดาต่อ
   */
  const studyYear = route.query.get('studyYear');
  const navGroup = route.query.get('groupCode');
  const groupCode = groupFromNav(navGroup);
  const cur = route.query.get('cur');
  const roomKey = studyYear && navGroup ? `${studyYear}/${groupCode ?? ''}` : '';

  const setQuery = (patch: Record<string, string | null>) => {
    const q = new URLSearchParams(route.query);
    for (const [k, v] of Object.entries(patch)) {
      if (v === null || v === '') q.delete(k);
      else q.set(k, v);
    }
    navigate(`${route.path}?${q.toString()}`);
  };

  const rooms = useAsync(
    () => (termId ? api.get<Room[]>(`/registration/rooms${qs({ termId })}`) : Promise.resolve([])),
    [termId],
  );

  const plan = useAsync(
    () =>
      termId && roomKey
        ? api.get<RoomPlan>(
            `/registration/rooms/plan${qs({ termId, studyYear, groupCode })}`,
          )
        : Promise.resolve(null),
    [termId, roomKey],
  );

  /* วิชาที่จะลง — คีย์เป็นรหัสวิชา ค่าเป็นกลุ่มเรียนที่เลือก */
  const [picked, setPicked] = useState<Record<string, string>>({});
  const [pickedStudents, setPickedStudents] = useState<Set<string>>(new Set());
  const [result, setResult] = useState<BulkResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  /*
   * ตั้งค่าเริ่มต้นจากแผนการเรียนทุกครั้งที่เปลี่ยนห้อง
   *
   * เลือกให้ล่วงหน้าเฉพาะวิชาที่ระบบจับคู่กลุ่มเรียนได้และเป็นวิชาของทั้งห้อง
   * — วิชาที่มาจากแผนของคนไม่กี่คนต้องให้คนกดเลือกเอง เพราะการกดลงทั้งห้อง
   * ให้วิชาที่อีกสามสิบแปดคนไม่ได้เรียน คือความผิดพลาดที่ต้องไล่ถอนทีละคน
   */
  useEffect(() => {
    const p = plan.data;
    if (!p) {
      setPicked({});
      setPickedStudents(new Set());
      return;
    }
    const next: Record<string, string> = {};
    for (const c of p.courses) {
      if (c.suggestedSectionId && c.wholeRoom) next[c.courseId] = c.suggestedSectionId;
    }
    setPicked(next);
    /*
     * ไม่ติ๊กคนที่ยังไม่ผูกหลักสูตรให้ล่วงหน้า — `check_registration` ปฏิเสธ
     * ด้วย NO_CURRICULUM ทุกครั้ง การติ๊กไว้จึงได้แถวสีแดงที่รู้ผลล่วงหน้าแล้ว
     * มากลบคนที่ติดเงื่อนไขจริง ๆ ที่ต้องตามต่อ (ยังติ๊กเองได้ถ้าอยากเห็นเหตุผล)
     */
    setPickedStudents(
      new Set(p.students.filter((s) => s.status === 'active' && s.hasCurriculum).map((s) => s.id)),
    );
  }, [plan.data]);

  /*
   * ล้างผลเมื่อ**เปลี่ยนห้อง** ไม่ใช่เมื่อแผนถูกโหลดใหม่
   *
   * ─── เจอตอนกดปุ่มจริง ไม่ใช่ตอนอ่านโค้ด ───
   * เดิมล้างผลไว้ในตัวเดียวกับการตั้งค่าเริ่มต้น ซึ่งผูกกับ `plan.data`
   * พอกดลงทะเบียนเสร็จแล้วโหลดตัวเลขใหม่ (เพื่อให้ % ขยับ) แผนก็เปลี่ยนตาม
   * แล้ว**ตารางผลรายคนหายไปทันทีที่กดสำเร็จ** — เจ้าหน้าที่เห็นเปอร์เซ็นต์
   * ขยับแต่ไม่เห็นเลยว่าใครติดเงื่อนไข ทั้งที่นั่นคือเหตุผลทั้งหมดที่
   * `register_courses_bulk` ไม่ raise แล้วคืนผลรายคนออกมา
   * เทสต์ผ่านหมดเพราะทุกข้อดูคำตอบจาก HTTP ไม่ใช่ดูสิ่งที่ค้างอยู่บนจอ
   */
  useEffect(() => {
    setResult(null);
    setError(null);
  }, [termId, roomKey]);

  const chosenSectionIds = Object.values(picked).filter(Boolean);
  const chosenCredits = (plan.data?.courses ?? [])
    .filter((c) => picked[c.courseId])
    .reduce((sum, c) => sum + Number(c.credits), 0);

  async function registerRoom() {
    if (!termId || chosenSectionIds.length === 0) return;
    setBusy('กำลังลงทะเบียน…');
    setError(null);
    setResult(null);
    try {
      const ids = [...pickedStudents];
      setResult(
        await registerInChunks(ids, termId, chosenSectionIds, (done) =>
          setBusy(ids.length > BULK_MAX ? `กำลังลงทะเบียน ${done}/${ids.length} คน…` : 'กำลังลงทะเบียน…'),
        ),
      );
      rooms.reload();
      plan.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ลงทะเบียนไม่สำเร็จ');
    } finally {
      setBusy(null);
    }
  }

  const nameOf = new Map(
    (plan.data?.students ?? []).map((s) => [s.id, `${s.studentCode} ${s.fullName}`]),
  );

  return (
    <>
      <PageHead
        title="ลงทะเบียนเรียน"
        sub={term && <TermDates term={term} />}
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(list) => <TermSelect terms={list} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      <Tabs
        tabs={[
          { key: 'room', label: 'ลงทั้งห้อง' },
          { key: 'student', label: 'รายคน (ตกค้าง · เรียนซ้ำ · เทียบโอน)' },
        ]}
        active={tab}
        onChange={(k) => setQuery({ tab: k === 'room' ? null : k })}
      />

      {error && <Notice kind="error">{error}</Notice>}

      {tab === 'room' ? (
        <>
          <RoomNavigator
            academicYearId={term?.academic_year_id ?? null}
            metricLabel="ลงแล้ว"
            metric={new Map((rooms.data ?? []).map((r) => [roomKeyOf(r.study_year, r.group_code), { done: Number(r.students_registered), total: Number(r.students_total) }]))}
            value={{ cur, studyYear, groupCode: navGroup }}
            onChange={(v) => setQuery({ cur: v.cur, studyYear: v.studyYear, groupCode: v.groupCode })}
          />

          {termId && roomKey && studyYear && (
            <div className="row" style={{ justifyContent: 'flex-end', margin: '8px 0' }}>
              <PrintButton
                path={`/reports/terms/${termId}/room-registrations/print${qs({
                  studyYear, groupCode: navGroup ?? undefined,
                  scopeLabel: `${term ? `ภาคเรียนที่ ${term.ordinal}/${term.year_be}` : ''} · ชั้นปี ${studyYear} ห้อง ${groupCode ?? 'ยังไม่จัดห้อง'}`,
                })}`}
              >
                ออกรายงานรายชื่อผู้ลงทะเบียน
              </PrintButton>
            </div>
          )}

          {studyYear && (
            <AsyncView state={plan} empty="เลือกห้องจากรายการด้านบน">
              {(p) =>
                p && (
                  <>
                    {p.studentsTruncated && (
                      <Notice kind="warn">
                        ห้องนี้มี {p.studentsTotal} คน แสดงได้ {p.students.length} คนแรก —
                        กองที่ใหญ่ขนาดนี้มักแปลว่ายังไม่ได้จัดห้อง
                        ให้ไปจัดห้องที่หน้างานวิชาการรายปีก่อน แล้วค่อยกลับมาลงทะเบียนเป็นห้อง
                      </Notice>
                    )}
                    {p.planEmptyReason && <Notice kind="warn">{p.planEmptyReason}</Notice>}
                    {p.withoutCurriculum > 0 && (
                      <Notice kind="warn">
                        {p.withoutCurriculum} คนในห้องนี้ยังไม่ได้ผูกหลักสูตร —
                        ฐานข้อมูลจะปฏิเสธการลงทะเบียนของคนกลุ่มนี้ทุกครั้ง (NO_CURRICULUM)
                        ให้ผูกหลักสูตรที่ระเบียนนักศึกษาก่อน ระบบจึงไม่ติ๊กชื่อไว้ให้
                      </Notice>
                    )}
                    {p.courses.some((c) => !c.wholeRoom) && (
                      <Notice kind="warn">
                        บางวิชาไม่ได้อยู่ในแผนของทุกคนที่ผูกหลักสูตรไว้ — ระบบจึงไม่ติ๊กให้ล่วงหน้า
                        ต้องเลือกเองพร้อมตรวจว่าใครควรลง มักเกิดจากคนที่ย้ายหลักสูตรหรือตกซ้ำชั้น
                        ซึ่งลงทั้งห้องแล้วจะได้วิชาที่ไม่อยู่ในแผนตัวเอง
                      </Notice>
                    )}

                    <PlanTable
                      plan={p}
                      picked={picked}
                      onToggle={(c) =>
                        setPicked((cur) => {
                          const next = { ...cur };
                          // ติ๊กเองโดยไม่มีตัวที่ระบบเดาให้ → กลุ่มแรกที่ยังไม่ล็อก
                          const open = c.sections.find((s) => !s.isLocked);
                          if (next[c.courseId]) delete next[c.courseId];
                          else if (c.suggestedSectionId) next[c.courseId] = c.suggestedSectionId;
                          else if (open) next[c.courseId] = open.id;
                          return next;
                        })
                      }
                      onSection={(courseId, sectionId) =>
                        setPicked((cur) =>
                          sectionId
                            ? { ...cur, [courseId]: sectionId }
                            : Object.fromEntries(Object.entries(cur).filter(([k]) => k !== courseId))
                        )
                      }
                    />

                    <RosterTable
                      plan={p}
                      picked={pickedStudents}
                      onToggle={(id) => setPickedStudents((s) => toggle(s, id))}
                      onAll={() =>
                        setPickedStudents((s) =>
                          s.size > 0
                            ? new Set()
                            : new Set(
                                p.students
                                  .filter((x) => x.status === 'active' && x.hasCurriculum)
                                  .map((x) => x.id),
                              ),
                        )
                      }
                    />

                    <Card>
                      <div className="row">
                        <div className="shrink">
                          <button
                            className="primary"
                            disabled={
                              busy !== null || pickedStudents.size === 0 || chosenSectionIds.length === 0
                            }
                            onClick={() => void registerRoom()}
                          >
                            {busy ??
                              `ลงทะเบียน ${pickedStudents.size} คน × ${chosenSectionIds.length} วิชา` +
                                ` (${num(chosenCredits)} หน่วยกิต)`}
                          </button>
                        </div>
                        {pickedStudents.size > BULK_MAX && (
                          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                            จะแบ่งส่งเป็นก้อนละ {BULK_MAX} คน — คนที่ลงไปแล้วในก้อนก่อนหน้าไม่ถูกย้อนคืน
                            ถ้าก้อนหลังล้ม
                          </div>
                        )}
                        <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                          เพดานหน่วยกิตและวิชาบังคับก่อนถูกตรวจที่ฐานข้อมูลเสมอ
                          ต่อให้กดจากหน้าจอนี้ก็ข้ามไม่ได้
                        </div>
                      </div>
                    </Card>

                    {result && <ResultTable result={result} nameOf={nameOf} />}
                  </>
                )
              }
            </AsyncView>
          )}
        </>
      ) : (
        <PerStudentTab termId={termId} />
      )}
    </>
  );
}

/* ─── รายวิชาตามแผนการเรียน ───────────────────────────────────────── */

function PlanTable({
  plan,
  picked,
  onToggle,
  onSection,
}: {
  plan: RoomPlan;
  picked: Record<string, string>;
  onToggle: (c: PlanCourse) => void;
  onSection: (courseId: string, sectionId: string) => void;
}) {
  return (
    <TableCard
      title={`รายวิชาตามแผนการเรียน — ${roomLabel({
        study_year: plan.room.studyYear,
        group_code: plan.room.groupCode,
      })} ภาคเรียนที่ ${plan.term.ordinal}`}
    >
      {plan.courses.length === 0 ? (
        <div className="empty">ไม่มีรายวิชาในแผนของภาคเรียนนี้</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th style={{ width: 34 }} />
              <th style={{ width: 110 }}>รหัสวิชา</th>
              <th>ชื่อวิชา</th>
              <th className="num" style={{ width: 60 }}>นก.</th>
              <th style={{ width: 230 }}>กลุ่มเรียน</th>
              <th style={{ width: 190 }}>อยู่ในแผนของ</th>
            </tr>
          </thead>
          <tbody>
            {plan.courses.map((c) => {
              const sel = picked[c.courseId] ?? '';
              const open = c.sections.filter((s) => !s.isLocked);
              return (
                <tr key={c.courseId}>
                  <td>
                    <input
                      type="checkbox"
                      style={{ width: 'auto' }}
                      disabled={open.length === 0}
                      checked={Boolean(sel)}
                      onChange={() => onToggle(c)}
                    />
                  </td>
                  <td className="mono">{c.code}</td>
                  <td>
                    {c.nameTh}
                    {!c.required && ' (วิชาเลือก)'}
                  </td>
                  <td className="num">{num(c.credits)}</td>
                  <td>
                    {c.sections.length === 0 ? (
                      <Badge kind="warn">ยังไม่เปิดกลุ่มเรียน</Badge>
                    ) : (
                      <>
                        <select
                          value={sel}
                          onChange={(e) => onSection(c.courseId, e.target.value)}
                        >
                          <option value="">— ไม่ลงวิชานี้ —</option>
                          {c.sections.map((s) => (
                            <option key={s.id} value={s.id} disabled={s.isLocked}>
                              กลุ่ม {s.sectionNo} · {s.enrolled}/{s.capacity}
                              {s.teacherName ? ` · ${s.teacherName}` : ''}
                              {s.isLocked ? ' (ล็อกแล้ว)' : ''}
                            </option>
                          ))}
                        </select>
                        {/*
                          บอกที่มาของการเลือกให้เสมอ — `section_no` เป็นห้องของ
                          รายวิชา ส่วนรหัสห้องเป็นห้องประจำ สองค่านี้หน้าตา
                          เหมือนกันแต่ไม่มีอะไรผูกกันจริง การเดาที่ไม่บอกที่มา
                          คือการเดาที่ตรวจไม่ได้
                        */}
                        {c.suggestedReason && sel === c.suggestedSectionId && (
                          <div style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
                            เลือกให้เพราะ{c.suggestedReason}
                          </div>
                        )}
                      </>
                    )}
                  </td>
                  <td>
                    {c.wholeRoom ? (
                      <Badge kind="ok">ทั้งห้อง ({c.studentsInPlan})</Badge>
                    ) : (
                      <Badge kind="warn">
                        {c.studentsInPlan} จาก {plan.plannable} คน
                      </Badge>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </TableCard>
  );
}

/* ─── รายชื่อในห้อง ───────────────────────────────────────────────── */

function RosterTable({
  plan,
  picked,
  onToggle,
  onAll,
}: {
  plan: RoomPlan;
  picked: Set<string>;
  onToggle: (id: string) => void;
  onAll: () => void;
}) {
  const inactive = plan.studentsTotal - plan.registerable;
  return (
    <TableCard
      title={
        `นักศึกษาในห้อง ${plan.studentsTotal} คน · ลงทะเบียนได้ ${plan.registerable} คน` +
        (inactive > 0 ? ` · ไม่อยู่ในสถานะกำลังศึกษา ${inactive} คน` : '') +
        ` — เลือกแล้ว ${picked.size} คน`
      }
      actions={
        <button className="link" onClick={onAll}>
          {picked.size > 0 ? 'ล้างทั้งหมด' : 'เลือกทุกคนที่ลงได้'}
        </button>
      }
    >
      <div style={{ maxHeight: 420, overflowY: 'auto' }}>
        <table>
          <thead>
            <tr>
              <th style={{ width: 34 }} />
              <th style={{ width: 130 }}>รหัสนักศึกษา</th>
              <th>ชื่อ — นามสกุล</th>
              <th className="num" style={{ width: 120 }}>ลงแล้วในภาคนี้</th>
            </tr>
          </thead>
          <tbody>
            {plan.students.map((s) => {
              const canRegister = s.status === 'active';
              return (
                <tr key={s.id} style={{ opacity: canRegister ? 1 : 0.55 }}>
                  <td>
                    <input
                      type="checkbox"
                      style={{ width: 'auto' }}
                      /*
                        คนที่ไม่ได้อยู่ในสถานะกำลังศึกษาลงทะเบียนไม่ได้อยู่แล้ว
                        (0009 ปฏิเสธที่ `check_registration`) — ปิดช่องติ๊กไว้
                        ดีกว่าปล่อยให้กดแล้วไปโผล่เป็นแถวสีแดงในตารางผล
                        ซึ่งจะกลบคนที่ติดเงื่อนไขจริง ๆ ที่ต้องตามต่อ
                      */
                      disabled={!canRegister}
                      checked={picked.has(s.id)}
                      onChange={() => onToggle(s.id)}
                    />
                  </td>
                  <td className="mono">{s.studentCode}</td>
                  <td>
                    {s.fullName}
                    {!canRegister && <span className="sub"> — {s.status}</span>}
                    {canRegister && !s.hasCurriculum && (
                      <> <Badge kind="warn">ยังไม่ผูกหลักสูตร</Badge></>
                    )}
                  </td>
                  <td className="num">
                    {s.registered > 0 ? `${s.registered} วิชา` : <Badge kind="warn">ยังไม่ลง</Badge>}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </TableCard>
  );
}

/* ─── ผลลงทะเบียน ─────────────────────────────────────────────────── */

function ResultTable({
  result,
  nameOf,
}: {
  result: BulkResult;
  nameOf: Map<string, string>;
}) {
  /* คนที่ติดเงื่อนไขอยู่บนสุด เพราะนั่นคือรายการที่ยังต้องทำงานต่อ */
  const rows = [...result.results].sort(
    (a, b) => Number(b.blockers.length > 0) - Number(a.blockers.length > 0),
  );
  return (
    <TableCard
      title={`ผลลงทะเบียน — สำเร็จ ${result.succeeded} คน · ติดเงื่อนไข ${result.blocked} คน`}
    >
      <table>
        <thead>
          <tr>
            <th style={{ width: 260 }}>นักศึกษา</th>
            <th style={{ width: 130 }}>ผล</th>
            <th>ติดอะไร</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.studentId}>
              <td>{nameOf.get(r.studentId) ?? r.studentId}</td>
              <td>
                <ResultBadge registered={r.registered} blocked={r.blockers.length > 0} />
              </td>
              <td style={{ whiteSpace: 'normal' }}>
                {r.blockers.length === 0 ? '—' : r.blockers.join(' · ')}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableCard>
  );
}

/* ─── ทางรายคน ────────────────────────────────────────────────────── */

/**
 * ─── ทำไมแท็บนี้ต้องมีช่องค้นหา ไม่ใช่รายชื่อทั้งวิทยาลัย ───
 * ของเดิมโหลดสองร้อยคนแรกตามรหัสมาเสมอ ซึ่งกับวิทยาลัยพันคนแปลว่าคนที่
 * ต้องการจริง ๆ มักไม่อยู่ในรายการ และไม่มีอะไรบนหน้าจอบอกว่ายังมีอีก
 */
function PerStudentTab({ termId }: { termId: string }) {
  const [typed, setTyped] = useState('');
  const [q, setQ] = useState('');
  const [courseQ, setCourseQ] = useState('');
  /*
   * เริ่มต้นแสดงเฉพาะวิชาที่นักศึกษายังไม่ผ่าน เพราะแท็บนี้ใช้ลงทะเบียน
   * เรียนเสริม/เรียนซ้ำเป็นหลัก — ปิดตัวกรองได้เมื่อเป็นกรณีตกค้าง/เทียบโอน
   * ที่ยังไม่เคยลงทะเบียนวิชานั้นมาก่อนเลย ซึ่ง student_failed_courses()
   * หาไม่เจอ (ไม่มีผลการเรียนให้ดู)
   */
  const [failedOnly, setFailedOnly] = useState(true);

  // ไม่โหลดรายชื่อจนกว่าจะพิมพ์ค้นหา — เดิมโหลด 50 คนแรกมาให้เลือกทันที
  // ซึ่งใช้ไม่ได้กับวิทยาลัยที่มีนักศึกษาเป็นพันคน (รูปเดียวกับ RoomList)
  const students = useAsync(
    () => (q ? api.get<StudentRow[]>(`/students${qs({ q, limit: 50 })}`) : Promise.resolve([])),
    [q],
  );
  const sections = useAsync(
    () => (termId ? fetchSections(termId, courseQ || undefined) : Promise.resolve([])),
    [termId, courseQ],
  );

  const [studentId, setStudentId] = useState('');
  const [pickedSections, setPickedSections] = useState<Set<string>>(new Set());
  const [check, setCheck] = useState<CheckResult | null>(null);
  const [result, setResult] = useState<BulkResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [retakeCharge, setRetakeCharge] = useState<RetakeCharge | null>(null);
  const [retakeBusy, setRetakeBusy] = useState(false);

  const student = (students.data ?? []).find((s) => s.id === studentId);

  const failed = useAsync(
    () => (studentId ? api.get<FailedCourse[]>(`/registration/students/${studentId}/failed-courses`) : Promise.resolve([])),
    [studentId],
  );
  const failedByCourse = new Map((failed.data ?? []).map((f) => [f.course_id, f]));
  const visibleSections = (sections.data ?? []).filter(
    (s) => !failedOnly || !studentId || failedByCourse.has(s.course_id),
  );

  async function run(kind: 'check' | 'register') {
    if (!termId || !studentId) return;
    setBusy(true);
    setError(null);
    setCheck(null);
    setResult(null);
    try {
      if (kind === 'check') {
        setCheck(
          await api.post<CheckResult>('/registration/check', {
            studentId, termId, sectionIds: [...pickedSections],
          }),
        );
      } else {
        setResult(
          await api.post<BulkResult>('/registration/register-bulk', {
            studentIds: [studentId], termId, sectionIds: [...pickedSections],
          }),
        );
        sections.reload();
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ทำรายการไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  /**
   * ลงทะเบียนซ่อมพร้อมเก็บค่าธรรมเนียม — ใช้ได้เฉพาะเลือกวิชาเดียวที่เป็น
   * วิชาที่ยังไม่ผ่านของนักศึกษาคนนี้ (เพื่อไม่ให้เผลอเก็บค่าซ่อมวิชาที่ยัง
   * ไม่เคยลงหรือไม่เคยตก) ยอดคำนวณจากหน่วยกิต × อัตราที่ตั้งไว้ที่งานการเงิน
   * — ถ้ายังไม่ได้ตั้งอัตราจะถูกปฏิเสธพร้อมบอกให้ไปตั้งก่อน
   */
  async function runRetake() {
    if (!termId || !studentId || pickedSections.size !== 1) return;
    const [sectionId] = [...pickedSections];
    setRetakeBusy(true);
    setError(null);
    setRetakeCharge(null);
    try {
      const r = await api.post<{ charge: RetakeCharge }>('/retake-fee/register', {
        studentId, termId, sectionId,
      });
      setRetakeCharge(r.charge);
      sections.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'ลงทะเบียนซ่อมไม่สำเร็จ');
    } finally {
      setRetakeBusy(false);
    }
  }

  const singlePickedSection = pickedSections.size === 1 ? [...pickedSections][0] : null;
  const isRetakeEligible = !!singlePickedSection
    && !!visibleSections.find((s) => s.id === singlePickedSection && failedByCourse.has(s.course_id));

  return (
    <>
      {error && <Notice kind="error">{error}</Notice>}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, alignItems: 'start' }}>
        <TableCard
          title={student ? `นักศึกษา — ${student.student_code} ${student.full_name}` : 'เลือกนักศึกษาหนึ่งคน'}
          actions={
            <form
              onSubmit={(e) => {
                e.preventDefault();
                setQ(typed.trim());
              }}
            >
              <Field label="">
                <input
                  placeholder="รหัส ชื่อ หรือนามสกุล"
                  value={typed}
                  onChange={(e) => setTyped(e.target.value)}
                  style={{ width: 200 }}
                />
              </Field>
            </form>
          }
        >
          {!q ? (
            <div className="empty">พิมพ์รหัส ชื่อ หรือนามสกุลแล้วกด Enter เพื่อค้นหา</div>
          ) : (
            <AsyncView state={students} empty="ไม่พบนักศึกษาที่ตรงกับคำค้น">
              {(rows) => (
                <div style={{ maxHeight: 380, overflowY: 'auto' }}>
                  <table>
                    <thead>
                      <tr>
                        <th style={{ width: 34 }} />
                        <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                        <th>ชื่อ — นามสกุล</th>
                        <th style={{ width: 90 }}>ห้อง</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((s) => (
                        <tr key={s.id}>
                          <td>
                            <input
                              type="radio"
                              name="student"
                              style={{ width: 'auto' }}
                              checked={studentId === s.id}
                              onChange={() => setStudentId(s.id)}
                            />
                          </td>
                          <td className="mono">{s.student_code}</td>
                          <td>{s.full_name}</td>
                          <td>{s.group_code ?? '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </AsyncView>
          )}
        </TableCard>

        <TableCard
          title={`กลุ่มเรียน — เลือกแล้ว ${pickedSections.size} วิชา`}
          actions={
            <div className="row" style={{ gap: 10, alignItems: 'center' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 4, whiteSpace: 'nowrap', fontSize: 13 }}>
                <input
                  type="checkbox"
                  checked={failedOnly}
                  onChange={(e) => setFailedOnly(e.target.checked)}
                />
                เฉพาะวิชาที่ยังไม่ผ่าน
              </label>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                }}
              >
                <Field label="">
                  <input
                    placeholder="ค้นรหัส/ชื่อวิชา"
                    value={courseQ}
                    onChange={(e) => setCourseQ(e.target.value)}
                    style={{ width: 180 }}
                  />
                </Field>
              </form>
            </div>
          }
        >
          {!studentId ? (
            <div className="empty">เลือกนักศึกษาก่อน — วิชาที่ยังไม่ผ่านของคนนั้นจะปรากฏที่นี่</div>
          ) : failedOnly && failed.loading && failed.data === null ? (
            <div className="loading">กำลังโหลดวิชาที่ยังไม่ผ่าน…</div>
          ) : failedOnly && failed.data?.length === 0 ? (
            <div className="empty">
              นักศึกษาคนนี้ไม่มีวิชาที่ยังไม่ผ่านในระบบ — ถ้าจะลงทะเบียนกรณีตกค้างหรือเทียบโอน (ที่ยังไม่เคยมีผลการเรียน) ให้ปิดตัวกรอง “เฉพาะวิชาที่ยังไม่ผ่าน” ด้านบน
            </div>
          ) : (
            <AsyncView state={sections} empty="ภาคเรียนนี้ยังไม่มีกลุ่มเรียน">
              {() =>
                visibleSections.length === 0 ? (
                  <div className="empty">ไม่พบวิชาตามตัวกรอง</div>
                ) : (
                  <div style={{ maxHeight: 380, overflowY: 'auto' }}>
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 34 }} />
                          <th style={{ width: 110 }}>รหัสวิชา</th>
                          <th>ชื่อวิชา</th>
                          <th style={{ width: 70 }}>กลุ่ม</th>
                          <th className="num" style={{ width: 80 }}>ลงแล้ว</th>
                          {failedOnly && <th style={{ width: 150 }}>ผลเดิม</th>}
                        </tr>
                      </thead>
                      <tbody>
                        {visibleSections.map((s: Section) => {
                          const fail = failedByCourse.get(s.course_id);
                          return (
                            <tr key={s.id}>
                              <td>
                                <input
                                  type="checkbox"
                                  style={{ width: 'auto' }}
                                  checked={pickedSections.has(s.id)}
                                  disabled={s.is_locked}
                                  onChange={() => setPickedSections((p) => toggle(p, s.id))}
                                />
                              </td>
                              <td className="mono">{s.code}</td>
                              <td>
                                {s.name_th}
                                {s.is_locked && ' (ล็อกแล้ว)'}
                              </td>
                              <td>{s.section_no}</td>
                              <td className="num">
                                <Badge kind={Number(s.enrolled) >= s.capacity ? 'danger' : 'default'}>
                                  {s.enrolled}/{s.capacity}
                                </Badge>
                              </td>
                              {failedOnly && (
                                <td>
                                  {fail && (
                                    <Badge kind="warn">{fail.grade_symbol} · {fail.term_label}</Badge>
                                  )}
                                </td>
                              )}
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )
              }
            </AsyncView>
          )}
        </TableCard>
      </div>

      <Card>
        <div className="row">
          <div className="shrink">
            <button
              disabled={busy || !studentId || pickedSections.size === 0}
              onClick={() => void run('check')}
            >
              ตรวจเงื่อนไขก่อน
            </button>
          </div>
          <div className="shrink">
            <button
              className="primary"
              disabled={busy || !studentId || pickedSections.size === 0}
              onClick={() => void run('register')}
            >
              {busy ? 'กำลังลงทะเบียน…' : `ลงทะเบียน ${pickedSections.size} วิชา`}
            </button>
          </div>
          <div className="shrink">
            {/*
              ใบลงทะเบียน**พิมพ์สด** ไม่ใช่ issued_document — ระหว่างช่วง
              เพิ่ม-ถอนมันถูกพิมพ์ซ้ำหลายรอบ ถ้าตรึงไว้จะได้ใบที่ไม่ตรงกับ
              รายวิชาจริง และถ้าให้เลขที่เอกสารก็จะกินเลขเพิ่มทุกครั้งที่กด
            */}
            {studentId && termId ? (
              <PrintButton path={`/reports/registration/${studentId}?termId=${termId}`}>
                พิมพ์ใบลงทะเบียน
              </PrintButton>
            ) : (
              <button disabled title="เลือกนักศึกษาหนึ่งคนก่อน">พิมพ์ใบลงทะเบียน</button>
            )}
          </div>
          {isRetakeEligible && (
            <div className="shrink">
              <button
                disabled={retakeBusy}
                onClick={() => void runRetake()}
                title="เลือกวิชาที่ยังไม่ผ่านของนักศึกษาคนนี้ไว้แล้ว — ลงทะเบียนซ่อมพร้อมออกยอดค่าซ่อมให้งานการเงิน"
              >
                {retakeBusy ? 'กำลังลงทะเบียนซ่อม…' : 'ลงทะเบียนซ่อม (เก็บค่าธรรมเนียม)'}
              </button>
            </div>
          )}
        </div>
        {retakeCharge && (
          <Notice kind={retakeCharge.status === 'pending' ? 'warn' : 'ok'}>
            ลงทะเบียนซ่อมสำเร็จ — {retakeCharge.credits} หน่วยกิต × {retakeCharge.rate_per_credit} บาท
            = <strong>{retakeCharge.amount} บาท</strong>{' '}
            {retakeCharge.status === 'pending'
              ? '— สถานะ "รอชำระเงิน" ชื่อนักศึกษาจะยังไม่ขึ้นสมุดคะแนนของครูจนกว่างานการเงินจะยืนยันว่าชำระแล้ว'
              : '— ชำระแล้ว'}
          </Notice>
        )}
      </Card>

      {check && (
        <Card title={`ผลตรวจ — ${check.canRegister ? 'ลงทะเบียนได้' : 'ยังลงไม่ได้'}`}>
          {check.problems.length === 0 ? (
            <Notice kind="ok">ไม่มีเงื่อนไขติดขัด</Notice>
          ) : (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 120 }}>ระดับ</th>
                  <th>รายละเอียด</th>
                </tr>
              </thead>
              <tbody>
                {check.problems.map((p, i) => (
                  <tr key={`${p.code}-${i}`}>
                    <td>
                      <Badge
                        kind={p.severity === 'block' ? 'danger' : p.severity === 'warn' ? 'warn' : 'info'}
                      >
                        {p.severity === 'block' ? 'ติดขัด' : p.severity === 'warn' ? 'เตือน' : 'ข้อมูล'}
                        {p.waived && ' (ยกเว้นแล้ว)'}
                      </Badge>
                    </td>
                    <td style={{ whiteSpace: 'normal' }}>{p.message_th}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </Card>
      )}

      {result && (
        <ResultTable
          result={result}
          nameOf={new Map(student ? [[student.id, `${student.student_code} ${student.full_name}`]] : [])}
        />
      )}
    </>
  );
}

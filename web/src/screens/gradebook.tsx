/**
 * สมุดคะแนนและการส่งเกรด
 *
 * ─── ทำไมหน้าจอนี้ไม่คำนวณเกรดเอง ───
 * การตัดเกรดทั้งหมดอยู่ใน `compute_section_grades()` ซึ่งอ่านช่วงคะแนนจาก
 * `grade_cutoff` และตรวจกฎเวลาเรียน 80% ให้ในคำสั่งเดียว ถ้าหน้าจอคิดเอง
 * จะได้ตัวเลขที่ต่างจากที่บันทึกลงระเบียนจริง — และคนที่เห็นสองตัวเลขนี้
 * ไม่ตรงกันคือนักศึกษา ตอนที่แก้อะไรไม่ได้แล้ว
 *
 * ─── ทำไมช่องคะแนนว่างไม่เท่ากับศูนย์ ───
 * ว่าง = ยังไม่ได้ประเมิน ซึ่งทำให้ได้ ม.ส. ส่วน 0 = ประเมินแล้วได้ศูนย์
 * ซึ่งทำให้คะแนนตก สองอย่างนี้ต่างกันมากและแก้ย้อนหลังยากทั้งคู่
 */
import { useEffect, useState } from 'react';
import { api, qs } from '../core/api';
import { type Section } from '../core/catalog';
import { num, pct } from '../core/fmt';
import { href } from '../core/router';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, PrintButton, TableCard, useAsync, useCan } from '../ui/kit';
import { RoomNavigator, type NavSelection } from '../ui/room-navigator';
import { TermSelect, useTermPicker } from '../ui/term-picker';

const CATEGORY: Record<string, string> = {
  formative: 'ระหว่างภาค',
  midterm: 'กลางภาค',
  final: 'ปลายภาค',
  affective: 'จิตพิสัย',
  practical: 'ปฏิบัติ',
};

interface Item {
  id: string;
  name_th: string;
  category: string | null;
  max_score: string;
  weight: string;
  publish_to_student: boolean;
}

interface SheetStudent {
  enrollment_id: string;
  student_code: string;
  full_name: string;
  pct_final: string | null;
  attendance_state: string | null;
  scores: Record<string, number | null>;
}

interface Sheet {
  items: Item[];
  students: SheetStudent[];
  weightTotal: number;
}

interface PreviewRow {
  enrollment_id: string;
  student_code: string;
  full_name: string;
  weighted_score: string | null;
  weight_recorded: string | null;
  weight_total: string | null;
  attendance_pct: string | null;
  attendance_state: string | null;
  symbol: string | null;
  grade_point: string | null;
  credits_earned: string | null;
  note_th: string | null;
}

interface Submission {
  stage: string;
  history: { from_stage: string | null; to_stage: string; note: string | null; occurred_at: string }[];
  results?: unknown[];
}

const STAGE_LABEL: Record<string, string> = {
  draft: 'ยังไม่ส่ง',
  teacher_submitted: 'ครูส่งแล้ว',
  head_approved: 'หัวหน้าแผนกอนุมัติ',
  academic_approved: 'ฝ่ายวิชาการอนุมัติ',
  director_approved: 'ผู้อำนวยการอนุมัติ',
  locked: 'ล็อกแล้ว',
  returned: 'ตีกลับให้แก้',
};

const NEXT_STAGE: Record<string, string> = {
  teacher_submitted: 'head_approved',
  head_approved: 'academic_approved',
  academic_approved: 'director_approved',
  director_approved: 'locked',
};

export function GradebookScreen() {
  const { terms, termId, term, setTerm } = useTermPicker();
  const [sectionId, setSectionId] = useState('');
  /*
   * อนุมัติเกรดของ SISA ไล่ถึงห้องก่อนแล้วจึงเลือกรายวิชา — งานทะเบียนตรวจทีละห้อง
   * ไม่ใช่ทีละวิชาของทั้งวิทยาลัย ครูไม่เห็นตัวนำทาง (เหตุผลเดียวกับหน้าเช็คชื่อ)
   */
  const isStaff = useCan('registrar', 'academic', 'director', 'admin');
  const [nav, setNav] = useState<NavSelection>({ cur: null, studyYear: null, groupCode: null });

  const sections = useAsync(
    () => (termId
      ? api.get<Section[]>(`/academic/sections${qs({ termId, ...(nav.groupCode ? { studyYear: nav.studyYear ?? undefined, groupCode: nav.groupCode } : {}) })}`)
      : Promise.resolve([])),
    [termId, nav.studyYear, nav.groupCode],
  );

  useEffect(() => setSectionId(''), [termId]);

  return (
    <>
      <PageHead
        title="สมุดคะแนน"
        actions={
          <div className="row" style={{ gap: 8, alignItems: 'center' }}>
            <a href={href('/registry')}>← ศูนย์งานทะเบียน</a>
            <div style={{ width: 240 }}>
              <AsyncView state={terms}>
                {(list) => <TermSelect terms={list} termId={termId} onChange={setTerm} />}
              </AsyncView>
            </div>
          </div>
        }
      />

      {isStaff && (
        <RoomNavigator academicYearId={term?.academic_year_id ?? null} value={nav} onChange={(v) => { setNav(v); setSectionId(''); }} />
      )}

      <Card>
        <div className="row">
          <label className="field" style={{ flex: 2 }}>
            <span>กลุ่มเรียน{nav.groupCode ? ' ที่คนในห้องนี้ลงอยู่' : ''}</span>
            <AsyncView state={sections} empty="ภาคเรียนนี้ยังไม่มีกลุ่มเรียน">
              {(rows) => (
                <select value={sectionId} onChange={(e) => setSectionId(e.target.value)}>
                  <option value="">— เลือกกลุ่มเรียน —</option>
                  {rows.map((s: Section) => (
                    <option key={s.id} value={s.id}>
                      {s.code} {s.name_th} · กลุ่ม {s.section_no}
                      {s.is_locked ? ' (ล็อกแล้ว)' : ''}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
      </Card>

      {sectionId && <SectionGradebook key={sectionId} sectionId={sectionId} />}
    </>
  );
}

function SectionGradebook({ sectionId }: { sectionId: string }) {
  const sheet = useAsync(() => api.get<Sheet>(`/gradebook/sections/${sectionId}/scores`), [sectionId]);
  const submission = useAsync(
    () => api.get<Submission>(`/gradebook/sections/${sectionId}/submission`),
    [sectionId],
  );
  const [preview, setPreview] = useState<PreviewRow[] | null>(null);

  return (
    <>
      <ItemsPanel sectionId={sectionId} sheet={sheet} />
      <ScoreSheet sheet={sheet} />
      <GradePanel
        sectionId={sectionId}
        preview={preview}
        setPreview={setPreview}
        submission={submission}
      />
    </>
  );
}

/* ─── ชิ้นงานที่ให้คะแนน ─────────────────────────────────────────── */

function ItemsPanel({ sectionId, sheet }: { sectionId: string; sheet: ReturnType<typeof useAsync<Sheet>> }) {
  const [nameTh, setName] = useState('');
  const [category, setCategory] = useState('formative');
  const [maxScore, setMax] = useState('20');
  const [weight, setWeight] = useState('20');

  const total = sheet.data?.weightTotal ?? 0;

  return (
    <TableCard
      title={`ชิ้นงานที่ให้คะแนน — น้ำหนักรวม ${num(total)}`}
      actions={
        total !== 100 && total > 0 ? (
          <Badge kind="warn">น้ำหนักรวมยังไม่ครบ 100</Badge>
        ) : null
      }
    >
      <AsyncView state={sheet}>
        {(s) => (
          <>
            {s.items.length > 0 && (
              <table>
                <thead>
                  <tr>
                    <th>ชื่อชิ้นงาน</th>
                    <th style={{ width: 120 }}>หมวด</th>
                    <th className="num" style={{ width: 90 }}>คะแนนเต็ม</th>
                    <th className="num" style={{ width: 90 }}>น้ำหนัก</th>
                    <th style={{ width: 110 }}>ให้นักศึกษาเห็น</th>
                  </tr>
                </thead>
                <tbody>
                  {s.items.map((i) => (
                    <tr key={i.id}>
                      <td>{i.name_th}</td>
                      <td>{i.category ? CATEGORY[i.category] ?? i.category : '—'}</td>
                      <td className="num">{num(i.max_score, 0)}</td>
                      <td className="num">{num(i.weight, 0)}</td>
                      <td>{i.publish_to_student ? 'เห็น' : 'ไม่เห็น'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}

            <div style={{ padding: 12, borderTop: '1px solid var(--line-soft)' }}>
              <div className="row">
                <Field label="ชื่อชิ้นงานใหม่">
                  <input value={nameTh} onChange={(e) => setName(e.target.value)} placeholder="เช่น ใบงานที่ 1" />
                </Field>
                <Field label="หมวด">
                  <select value={category} onChange={(e) => setCategory(e.target.value)}>
                    {Object.entries(CATEGORY).map(([v, l]) => (
                      <option key={v} value={v}>{l}</option>
                    ))}
                  </select>
                </Field>
                <Field label="คะแนนเต็ม">
                  <input value={maxScore} onChange={(e) => setMax(e.target.value)} inputMode="decimal" />
                </Field>
                <Field label="น้ำหนัก">
                  <input value={weight} onChange={(e) => setWeight(e.target.value)} inputMode="decimal" />
                </Field>
                <div className="shrink">
                  <ActionButton
                    onRun={() =>
                      api.post(`/gradebook/sections/${sectionId}/items`, {
                        nameTh: nameTh.trim(),
                        category,
                        maxScore: Number(maxScore),
                        weight: Number(weight),
                      })
                    }
                    onDone={() => {
                      setName('');
                      sheet.reload();
                    }}
                  >
                    เพิ่มชิ้นงาน
                  </ActionButton>
                </div>
              </div>
            </div>
          </>
        )}
      </AsyncView>
    </TableCard>
  );
}

/* ─── ตารางกรอกคะแนน ────────────────────────────────────────────── */

function ScoreSheet({ sheet }: { sheet: ReturnType<typeof useAsync<Sheet>> }) {
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const key = (itemId: string, enrollmentId: string) => `${itemId}:${enrollmentId}`;

  async function save() {
    if (!sheet.data) return;
    setBusy(true);
    setError(null);
    setMsg(null);
    try {
      // ส่งทีละชิ้นงาน เพราะ API รับคะแนนของชิ้นงานเดียวต่อหนึ่งคำขอ
      let written = 0;
      for (const item of sheet.data.items) {
        const scores = sheet.data.students
          .map((st) => {
            const k = key(item.id, st.enrollment_id);
            if (!(k in edits)) return null;
            const raw = edits[k]!.trim();
            return { enrollmentId: st.enrollment_id, score: raw === '' ? null : Number(raw) };
          })
          .filter((x): x is { enrollmentId: string; score: number | null } => x !== null);

        if (scores.length === 0) continue;
        const r = await api.post<{ written: number }>(`/gradebook/items/${item.id}/scores`, { scores });
        written += r.written;
      }
      setMsg(`บันทึกคะแนนแล้ว ${written} ช่อง`);
      setEdits({});
      sheet.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'บันทึกคะแนนไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  return (
    <TableCard
      title="กรอกคะแนน"
      actions={
        <button
          className="primary"
          disabled={busy || Object.keys(edits).length === 0}
          onClick={() => void save()}
        >
          {busy ? 'กำลังบันทึก…' : `บันทึก ${Object.keys(edits).length} ช่องที่แก้`}
        </button>
      }
    >
      {error && <div style={{ padding: 12 }}><Notice kind="error">{error}</Notice></div>}
      {msg && <div style={{ padding: 12 }}><Notice kind="ok">{msg}</Notice></div>}

      <AsyncView state={sheet}>
        {(s) =>
          s.items.length === 0 ? (
            <div className="empty">ยังไม่มีชิ้นงาน — เพิ่มชิ้นงานก่อนจึงจะกรอกคะแนนได้</div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                    <th style={{ width: 170 }}>ชื่อ — นามสกุล</th>
                    {s.items.map((i) => (
                      <th key={i.id} className="num" style={{ width: 90 }}>
                        {i.name_th}
                        <br />
                        <span style={{ fontWeight: 400 }}>เต็ม {num(i.max_score, 0)}</span>
                      </th>
                    ))}
                    <th className="num" style={{ width: 90 }}>เวลาเรียน</th>
                  </tr>
                </thead>
                <tbody>
                  {s.students.map((st) => (
                    <tr key={st.enrollment_id}>
                      <td className="mono">{st.student_code}</td>
                      <td>{st.full_name}</td>
                      {s.items.map((i) => {
                        const k = key(i.id, st.enrollment_id);
                        const stored = st.scores?.[i.id];
                        const value = k in edits ? edits[k]! : stored === null || stored === undefined ? '' : String(stored);
                        return (
                          <td key={i.id} className="num">
                            <input
                              value={value}
                              inputMode="decimal"
                              style={{ textAlign: 'right', padding: '2px 6px' }}
                              onChange={(e) => setEdits((p) => ({ ...p, [k]: e.target.value }))}
                            />
                          </td>
                        );
                      })}
                      <td className="num">{pct(st.pct_final)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        }
      </AsyncView>
    </TableCard>
  );
}

/* ─── ตัดเกรดและส่ง ─────────────────────────────────────────────── */

function GradePanel({
  sectionId,
  preview,
  setPreview,
  submission,
}: {
  sectionId: string;
  preview: PreviewRow[] | null;
  setPreview: (r: PreviewRow[] | null) => void;
  submission: ReturnType<typeof useAsync<Submission>>;
}) {
  const stage = submission.data?.stage ?? 'draft';
  const next = NEXT_STAGE[stage];

  return (
    <TableCard
      title={
        <>
          ตัดเกรด · สถานะ <Badge kind={stage === 'locked' ? 'ok' : stage === 'draft' ? 'default' : 'info'}>
            {STAGE_LABEL[stage] ?? stage}
          </Badge>
        </>
      }
      actions={
        <>
          <ActionButton
            onRun={() => api.get<PreviewRow[]>(`/gradebook/sections/${sectionId}/preview`)}
            onDone={(r) => setPreview(r as PreviewRow[])}
          >
            ดูผลตัดเกรด
          </ActionButton>

          {stage === 'draft' && (
            <ActionButton
              className="primary"
              confirm="ส่งเกรดแล้วจะเข้าสู่สายอนุมัติ ยืนยันหรือไม่"
              onRun={() => api.post(`/gradebook/sections/${sectionId}/submit`)}
              onDone={() => submission.reload()}
            >
              ส่งเกรด
            </ActionButton>
          )}

          {next && (
            <ActionButton
              className="primary"
              confirm={`เลื่อนไปขั้น "${STAGE_LABEL[next]}" ยืนยันหรือไม่`}
              onRun={() =>
                api.post(`/gradebook/submissions/${(submission.data as { id?: string })?.id}/advance`, {
                  toStage: next,
                })
              }
              onDone={() => submission.reload()}
            >
              เลื่อนเป็น {STAGE_LABEL[next]}
            </ActionButton>
          )}
        </>
      }
    >
      {stage === 'locked' && (
        <div style={{ padding: 12 }}>
          <Notice kind="ok">
            รอบนี้ล็อกแล้ว — การแก้เกรดหลังจากนี้ต้องยื่นคำร้องที่ต้องมีผู้อนุมัติสองคน
            ไม่มีทางแก้ตรงจากหน้าจอนี้
          </Notice>
          <div style={{ marginTop: 8 }}>
            <PrintButton path={`/reports/grade-announcement/${sectionId}`}>
              พิมพ์ประกาศผลสอบ
            </PrintButton>
          </div>
        </div>
      )}

      {preview === null ? (
        <div className="empty">กด “ดูผลตัดเกรด” เพื่อคำนวณจากคะแนนที่กรอกไว้ (ไม่เขียนลงระเบียน)</div>
      ) : (
        <table>
          <thead>
            <tr>
              <th style={{ width: 120 }}>รหัสนักศึกษา</th>
              <th style={{ width: 170 }}>ชื่อ — นามสกุล</th>
              <th className="num" style={{ width: 100 }}>คะแนนรวม</th>
              <th className="num" style={{ width: 110 }}>น้ำหนักที่กรอก</th>
              <th className="num" style={{ width: 90 }}>เวลาเรียน</th>
              <th style={{ width: 70 }}>เกรด</th>
              <th>หมายเหตุ</th>
            </tr>
          </thead>
          <tbody>
            {preview.map((r) => (
              <tr key={r.enrollment_id}>
                <td className="mono">{r.student_code}</td>
                <td>{r.full_name}</td>
                <td className="num">{num(r.weighted_score)}</td>
                <td className="num">
                  {num(r.weight_recorded, 0)}/{num(r.weight_total, 0)}
                </td>
                <td className="num">{pct(r.attendance_pct)}</td>
                <td>
                  <Badge
                    kind={
                      r.symbol === 'ข.ร.' || r.symbol === '0' ? 'danger'
                        : r.symbol === 'ม.ส.' || r.symbol === 'ข.ส.' ? 'warn'
                        : 'ok'
                    }
                  >
                    {r.symbol ?? '—'}
                  </Badge>
                </td>
                <td style={{ whiteSpace: 'normal' }}>{r.note_th ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </TableCard>
  );
}

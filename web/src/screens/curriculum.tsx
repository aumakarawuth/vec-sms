/**
 * โครงสร้างหลักสูตร
 *
 * ─── ทำไมหน้านี้อ่านเป็นหลัก ───
 * หลักสูตรที่มีนักศึกษาเรียนอยู่แล้วแก้ไม่ได้ตามใจ — `curriculum_version`
 * เป็นฉบับที่ผูกกับปีที่เข้าศึกษา คนที่เข้าปี 2566 ยังอยู่ใต้ฉบับ 2562
 * แม้ปัจจุบันจะใช้ฉบับ 2567 แล้ว การแก้ฉบับเดิมจึงเท่ากับเปลี่ยนเกณฑ์จบ
 * ของคนที่เรียนไปแล้วครึ่งทาง วิธีที่ถูกคือ **โคลนเป็นฉบับใหม่**
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, PageHead, TableCard, useAsync } from '../ui/kit';
import { CourseEntry } from './course-entry';

interface Version {
  id: string;
  edition_be: number;
  effective_from_year_be: number;
  effective_to_year_be: number | null;
  status: string;
  min_total_credits: string;
  min_gpax: string;
  grade_scheme_code: string | null;
  courses: string | number;
  rules: string | number;
  students: string | number;
}

interface CourseInVersion {
  id: string;
  requirement: string;
  code: string;
  name_th: string;
  credits?: string;
  suggested_year?: number | null;
  suggested_term?: number | null;
}

/**
 * เลื่อนรายวิชาขึ้น/ลงหนึ่งขั้นแล้วส่งลำดับทั้งชุดไปให้ API
 *
 * ─── ทำไมส่งทั้งชุด ทั้งที่ผู้ใช้เลื่อนแค่แถวเดียว ───
 * เพราะ "เลื่อนขึ้นหนึ่งขั้น" ต้องอ่านลำดับปัจจุบันมาก่อนแล้วเขียนกลับสองแถว
 * ถ้ามีคนสองคนเปิดหน้าจอเดียวกันอยู่ จะสลับกันจนลำดับเพี้ยนโดยไม่มีใครเห็น
 * — ส่งทั้งชุดแปลว่าคนที่กดทีหลังชนะทั้งชุด ซึ่งอธิบายให้ผู้ใช้ฟังได้
 */
function moveCourse(
  versionId: string, courses: CourseInVersion[], index: number, delta: number,
) {
  const to = index + delta;
  if (to < 0 || to >= courses.length) return Promise.resolve();
  const ids = courses.map((c) => c.id);
  const moved = ids[index]!;
  ids[index] = ids[to]!;
  ids[to] = moved;
  return api.post(`/curriculum/versions/${versionId}/courses/reorder`, { courseIds: ids });
}

/**
 * แก้ภาคเรียนตามหลักสูตรของรายวิชา
 *
 * ค่านี้เป็นตัวบอกว่ารายวิชาไปโผล่ภาคไหนบน**ใบ ระเบียนแสดงผลการเรียน**
 * ไม่ใช่แค่คำแนะนำ — นักศึกษาที่ลงเรียนคนละภาคกับแผนจะยังถูกพิมพ์ตามแผน
 */
function PlanTermEditor(
  { course, onSaved }: { course: CourseInVersion; onSaved: () => void },
) {
  const [year, setYear] = useState(String(course.suggested_year ?? ''));
  const [term, setTerm] = useState(String(course.suggested_term ?? ''));
  const dirty = year !== String(course.suggested_year ?? '')
    || term !== String(course.suggested_term ?? '');

  return (
    <span className="plan-term">
      <select value={year} onChange={(e) => setYear(e.target.value)}>
        <option value="">ชั้นปี —</option>
        {[1, 2, 3, 4].map((y) => <option key={y} value={y}>ชั้นปีที่ {y}</option>)}
      </select>{' '}
      <select value={term} onChange={(e) => setTerm(e.target.value)}>
        <option value="">ภาค —</option>
        {[1, 2, 3].map((t) => <option key={t} value={t}>ภาค {t}</option>)}
      </select>
      {dirty && year !== '' && term !== '' && (
        <>
          {' '}
          <ActionButton
            onRun={() => api.patch(`/curriculum/courses/${course.id}`, {
              suggestedYear: Number(year), suggestedTerm: Number(term),
            })}
            onDone={onSaved}
          >
            บันทึก
          </ActionButton>
        </>
      )}
    </span>
  );
}

/**
 * โคลนฉบับหลักสูตรเป็นฉบับใหม่ — ทางเดียวที่สร้างฉบับใหม่ได้
 *
 * ฉบับเดิมแก้ไม่ได้ตามใจเพราะมีนักศึกษาผูกอยู่แล้ว (ดูคอมเมนต์บนสุดของไฟล์)
 * แต่ก่อนหน้านี้ไม่มีปุ่มเรียก `clone_curriculum_version()` เลยสักที่ — วิทยาลัย
 * ที่หลักสูตรเดิมหมดอายุจึงไม่มีทางออกฉบับใหม่ได้จากหน้าจอ
 */
function CloneVersionCard({ version, onDone }: { version: Version; onDone: () => void }) {
  const [editionBe, setEditionBe] = useState(String(version.edition_be + 1));
  const [fromYear, setFromYear] = useState(String(version.edition_be + 1));
  const [toYear, setToYear] = useState('');
  const [note, setNote] = useState('');

  return (
    <Card title={`โคลนฉบับ ${version.edition_be} เป็นฉบับใหม่`}>
      <p className="hint">
        คัดลอกหมวดวิชา รายวิชา และกฎการจบทั้งหมดจากฉบับ {version.edition_be} ไปเป็นฉบับใหม่
        แล้วแก้ต่อจากตรงนั้นได้ — ฉบับเดิมไม่ถูกแตะเลยเพราะยังมีนักศึกษาผูกอยู่
      </p>
      <div className="row">
        <Field label="ฉบับ (พ.ศ.)">
          <input
            type="number" value={editionBe}
            onChange={(e) => setEditionBe(e.target.value)}
            style={{ maxWidth: 100 }}
          />
        </Field>
        <Field label="เริ่มใช้ปีการศึกษา">
          <input
            type="number" value={fromYear}
            onChange={(e) => setFromYear(e.target.value)}
            style={{ maxWidth: 100 }}
          />
        </Field>
        <Field label="ถึงปีการศึกษา (ถ้ามี)">
          <input
            type="number" value={toYear}
            onChange={(e) => setToYear(e.target.value)}
            style={{ maxWidth: 100 }}
          />
        </Field>
        <Field label="หมายเหตุ (ถ้ามี)">
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="เช่น ปรับตามเกณฑ์ สอศ. ใหม่" />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            confirm={`โคลนฉบับ ${version.edition_be} เป็นฉบับ ${editionBe} ยืนยันหรือไม่`}
            onRun={() =>
              api.post<{ id: string }>(`/curriculum/versions/${version.id}/clone`, {
                editionBe: Number(editionBe),
                effectiveFromYearBe: Number(fromYear),
                ...(toYear ? { effectiveToYearBe: Number(toYear) } : {}),
                ...(note.trim() ? { note: note.trim() } : {}),
              })
            }
            onDone={onDone}
          >
            โคลนเป็นฉบับใหม่
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

interface Category {
  id: string;
  parent_id: string | null;
  kind: string;
  code: string;
  name_th: string;
  min_credits?: string | null;
  max_credits?: string | null;
  courses: CourseInVersion[];
}

interface GraduationRule {
  id: string;
  kind: string;
  name_th: string;
  threshold: string | null;
  is_blocking: boolean;
}

/** เส้นทางนี้คืนข้อมูลของฉบับหลักสูตรแบบแบน แล้วซ้อนรายวิชาไว้ในแต่ละหมวด */
interface Structure {
  edition_be: number;
  min_total_credits: string;
  min_gpax: string;
  min_practicum_hours: number | null;
  grade_scheme_name: string | null;
  categories: Category[];
  uncategorized: CourseInVersion[];
  graduationRules: GraduationRule[];
}

const REQUIREMENT: Record<string, string> = {
  required: 'บังคับ',
  elective: 'เลือก',
  free_elective: 'เลือกเสรี',
};

/**
 * ต้นไม้สาขาวิชา — หมวดสาขา → สาขาวิชา → สาขางาน → หลักสูตร
 *
 * ─── ทำไมต้องมีชั้นนี้ ───
 * `GET /curriculum/programs` มีมาตั้งแต่แรกแต่ไม่เคยมีหน้าจอไหนเรียกเลย
 * และไม่มีเส้นทางสร้างสักชั้น วิทยาลัยที่ deploy ใหม่ตาม reference-data.sql
 * (ซึ่งตั้งใจไม่ใส่สาขาวิชาให้ เพราะเป็นเรื่องเฉพาะของแต่ละวิทยาลัย) จึงเปิด
 * "โครงสร้างหลักสูตร" มาแล้วสร้างฉบับหลักสูตรไม่ได้เลยสักฉบับ — ไม่มีสาขา
 * ให้เลือกตั้งแต่ขั้นแรก
 */
interface ProgramRow {
  program_type_id: string;
  type_code: string;
  type_name: string;
  program_id: string;
  program_code: string;
  program_name: string;
  program_level: string;
  track_id: string | null;
  track_code: string | null;
  track_name: string | null;
  curriculum_id: string | null;
  curriculum_name: string | null;
  curriculum_shift: string | null;
  versions: string | number;
}

interface GradeScheme {
  id: string;
  code: string;
  name_th: string;
  level: string;
  effective_from_year_be: number;
}

const QUALIFICATION_LEVEL: Record<string, string> = { PVC: 'ปวช.', PVS: 'ปวส.', TVB: 'ทวิภาคีบัณฑิต' };
const CLASS_SHIFT: Record<string, string> = { morning: 'เช้า', afternoon: 'บ่าย', evening: 'ค่ำ', weekend: 'เสาร์-อาทิตย์' };

/** เอาแถวที่ id ไม่ซ้ำกันจากอาร์เรย์ที่แบนอยู่ — ต้นไม้ทั้งก้อนมาเป็นแถวเดียวต่อหนึ่งใบไม้ */
function uniqueBy<T, K>(rows: T[], key: (row: T) => K | null | undefined): T[] {
  const seen = new Set<K>();
  const out: T[] = [];
  for (const row of rows) {
    const k = key(row);
    if (k == null || seen.has(k)) continue;
    seen.add(k);
    out.push(row);
  }
  return out;
}

function AddProgramTypeForm({ onDone }: { onDone: () => void }) {
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');

  return (
    <Card title="เพิ่มหมวดสาขา">
      <p className="hint">ระดับบนสุด เช่น อุตสาหกรรม พาณิชยกรรม คหกรรม — ส่วนใหญ่วิทยาลัยหนึ่งมีไม่กี่หมวด</p>
      <div className="row">
        <Field label="รหัสหมวด">
          <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น 01" style={{ maxWidth: 100 }} />
        </Field>
        <Field label="ชื่อหมวด">
          <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น อุตสาหกรรม" />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!code.trim() || !nameTh.trim()) throw new Error('กรอกรหัสและชื่อหมวดสาขา');
              return api.post('/curriculum/program-types', { code: code.trim(), nameTh: nameTh.trim() });
            }}
            onDone={() => { setCode(''); setNameTh(''); onDone(); }}
          >
            เพิ่มหมวดสาขา
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function AddProgramForm({ programTypes, onDone }: { programTypes: ProgramRow[]; onDone: () => void }) {
  const [programTypeId, setProgramTypeId] = useState('');
  const [level, setLevel] = useState('PVC');
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');

  return (
    <Card title="เพิ่มสาขาวิชา">
      <p className="hint">ผูกระดับการศึกษาไว้ที่ชั้นนี้ — สาขาเดียวกันที่เปิดทั้ง ปวช. และ ปวส. ต้องสร้างสองแถว</p>
      <div className="row">
        <Field label="หมวดสาขา">
          <select value={programTypeId} onChange={(e) => setProgramTypeId(e.target.value)}>
            <option value="">— เลือกหมวดสาขา —</option>
            {programTypes.map((t) => (
              <option key={t.program_type_id} value={t.program_type_id}>{t.type_code} {t.type_name}</option>
            ))}
          </select>
        </Field>
        <Field label="ระดับ">
          <select value={level} onChange={(e) => setLevel(e.target.value)} style={{ maxWidth: 140 }}>
            {Object.entries(QUALIFICATION_LEVEL).map(([v, label]) => (
              <option key={v} value={v}>{label}</option>
            ))}
          </select>
        </Field>
        <Field label="รหัสสาขา">
          <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น 20101" style={{ maxWidth: 120 }} />
        </Field>
        <Field label="ชื่อสาขาวิชา">
          <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น ช่างยนต์" />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!programTypeId) throw new Error('เลือกหมวดสาขาก่อน');
              if (!code.trim() || !nameTh.trim()) throw new Error('กรอกรหัสและชื่อสาขาวิชา');
              return api.post('/curriculum/programs', {
                programTypeId, level, code: code.trim(), nameTh: nameTh.trim(),
              });
            }}
            onDone={() => { setCode(''); setNameTh(''); onDone(); }}
          >
            เพิ่มสาขาวิชา
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function AddProgramTrackForm({ programs, onDone }: { programs: ProgramRow[]; onDone: () => void }) {
  const [programId, setProgramId] = useState('');
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');

  return (
    <Card title="เพิ่มสาขางาน">
      <p className="hint">แขนงย่อยภายในสาขาวิชาหนึ่ง เช่น ช่างยนต์ → ยานยนต์ / ตัวถังและสี</p>
      <div className="row">
        <Field label="สาขาวิชา">
          <select value={programId} onChange={(e) => setProgramId(e.target.value)}>
            <option value="">— เลือกสาขาวิชา —</option>
            {programs.map((p) => (
              <option key={p.program_id} value={p.program_id}>
                {p.program_code} {p.program_name} ({QUALIFICATION_LEVEL[p.program_level] ?? p.program_level})
              </option>
            ))}
          </select>
        </Field>
        <Field label="รหัสสาขางาน">
          <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น 20101010" style={{ maxWidth: 140 }} />
        </Field>
        <Field label="ชื่อสาขางาน">
          <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น ยานยนต์" />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!programId) throw new Error('เลือกสาขาวิชาก่อน');
              if (!code.trim() || !nameTh.trim()) throw new Error('กรอกรหัสและชื่อสาขางาน');
              return api.post('/curriculum/program-tracks', { programId, code: code.trim(), nameTh: nameTh.trim() });
            }}
            onDone={() => { setCode(''); setNameTh(''); onDone(); }}
          >
            เพิ่มสาขางาน
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function AddCurriculumForm({ tracks, onDone }: { tracks: ProgramRow[]; onDone: () => void }) {
  const [trackId, setTrackId] = useState('');
  const [nameTh, setNameTh] = useState('');
  const [shift, setShift] = useState('morning');
  const [isContinuing, setIsContinuing] = useState(false);

  return (
    <Card title="เพิ่มหลักสูตรใหม่">
      <p className="hint">
        สาขางานเดียวกันเปิดได้หลายกะ (เช้า/บ่าย/เสาร์-อาทิตย์) แต่ละกะนับเป็นคนละหลักสูตร —
        หลักสูตรที่สร้างตรงนี้ยังไม่มีฉบับ ต้องออกฉบับแรกในหัวข้อถัดไป
      </p>
      <div className="row">
        <Field label="สาขางาน">
          <select value={trackId} onChange={(e) => setTrackId(e.target.value)}>
            <option value="">— เลือกสาขางาน —</option>
            {tracks.map((t) => (
              <option key={t.track_id!} value={t.track_id!}>
                {t.program_name} · {t.track_code} {t.track_name}
              </option>
            ))}
          </select>
        </Field>
        <Field label="ชื่อหลักสูตร">
          <input
            value={nameTh} onChange={(e) => setNameTh(e.target.value)}
            placeholder="เช่น ปวช. ช่างยนต์ สาขางานยานยนต์"
          />
        </Field>
        <Field label="กะเรียน">
          <select value={shift} onChange={(e) => setShift(e.target.value)} style={{ maxWidth: 150 }}>
            {Object.entries(CLASS_SHIFT).map(([v, label]) => (
              <option key={v} value={v}>{label}</option>
            ))}
          </select>
        </Field>
        <label style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 22 }}>
          <input type="checkbox" checked={isContinuing} onChange={(e) => setIsContinuing(e.target.checked)} />
          หลักสูตรต่อเนื่อง
        </label>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!trackId) throw new Error('เลือกสาขางานก่อน');
              if (!nameTh.trim()) throw new Error('กรอกชื่อหลักสูตร');
              return api.post('/curriculum/curricula', {
                programTrackId: trackId, nameTh: nameTh.trim(), shift, isContinuing,
              });
            }}
            onDone={() => { setNameTh(''); setIsContinuing(false); onDone(); }}
          >
            เพิ่มหลักสูตร
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function AddVersionForm({
  curricula, gradeSchemes, onDone,
}: { curricula: ProgramRow[]; gradeSchemes: GradeScheme[]; onDone: () => void }) {
  const [curriculumId, setCurriculumId] = useState('');
  const [editionBe, setEditionBe] = useState('');
  const [fromYear, setFromYear] = useState('');
  const [gradeSchemeId, setGradeSchemeId] = useState('');
  const [minTotalCredits, setMinTotalCredits] = useState('');
  const [minGpax, setMinGpax] = useState('2.00');
  const [normalDurationTerms, setNormalDurationTerms] = useState('6');

  return (
    <Card title="ออกฉบับแรกของหลักสูตร">
      <p className="hint">
        หลักสูตรที่เพิ่งสร้างยังไม่มีฉบับ — เส้นทางนี้สร้างฉบับเปล่าให้ ต่างจาก "โคลนฉบับ" ที่ต้องมีฉบับต้นทางอยู่ก่อน
        ใส่หมวดวิชาและรายวิชาต่อได้ที่ตาราง "ฉบับหลักสูตร" ด้านล่างหลังสร้างเสร็จ
      </p>
      <div className="row">
        <Field label="หลักสูตร">
          <select value={curriculumId} onChange={(e) => setCurriculumId(e.target.value)} style={{ minWidth: 260 }}>
            <option value="">— เลือกหลักสูตร —</option>
            {curricula.map((c) => (
              <option key={c.curriculum_id!} value={c.curriculum_id!}>
                {c.curriculum_name} ({CLASS_SHIFT[c.curriculum_shift ?? ''] ?? c.curriculum_shift})
              </option>
            ))}
          </select>
        </Field>
        <Field label="ฉบับ (พ.ศ.)">
          <input type="number" value={editionBe} onChange={(e) => setEditionBe(e.target.value)} style={{ maxWidth: 100 }} />
        </Field>
        <Field label="เริ่มใช้ปีการศึกษา">
          <input type="number" value={fromYear} onChange={(e) => setFromYear(e.target.value)} style={{ maxWidth: 100 }} />
        </Field>
        <Field label="ระเบียบการวัดและประเมินผล">
          <select value={gradeSchemeId} onChange={(e) => setGradeSchemeId(e.target.value)} style={{ minWidth: 220 }}>
            <option value="">— ยังไม่เลือก —</option>
            {gradeSchemes.map((g) => (
              <option key={g.id} value={g.id}>{g.code} {g.name_th}</option>
            ))}
          </select>
        </Field>
        <Field label="หน่วยกิตขั้นต่ำ">
          <input type="number" value={minTotalCredits} onChange={(e) => setMinTotalCredits(e.target.value)} style={{ maxWidth: 100 }} />
        </Field>
        <Field label="GPAX ขั้นต่ำ">
          <input type="number" step="0.01" value={minGpax} onChange={(e) => setMinGpax(e.target.value)} style={{ maxWidth: 90 }} />
        </Field>
        <Field label="จำนวนภาคเรียนปกติ">
          <input type="number" value={normalDurationTerms} onChange={(e) => setNormalDurationTerms(e.target.value)} style={{ maxWidth: 90 }} />
        </Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!curriculumId) throw new Error('เลือกหลักสูตรก่อน');
              if (!editionBe || !fromYear || !minTotalCredits) {
                throw new Error('กรอกฉบับ ปีที่เริ่มใช้ และหน่วยกิตขั้นต่ำ');
              }
              return api.post('/curriculum/versions', {
                curriculumId,
                editionBe: Number(editionBe),
                effectiveFromYearBe: Number(fromYear),
                ...(gradeSchemeId ? { gradeSchemeId } : {}),
                minTotalCredits: Number(minTotalCredits),
                ...(minGpax ? { minGpax: Number(minGpax) } : {}),
                normalDurationTerms: Number(normalDurationTerms),
              });
            }}
            onDone={() => { setEditionBe(''); setFromYear(''); setMinTotalCredits(''); onDone(); }}
          >
            ออกฉบับแรก
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function ProgramTree({ rows }: { rows: ProgramRow[] }) {
  return (
    <TableCard title="โครงสร้างสาขาวิชา">
      <table>
        <thead>
          <tr>
            <th>หมวดสาขา</th>
            <th>สาขาวิชา</th>
            <th style={{ width: 90 }}>ระดับ</th>
            <th>สาขางาน</th>
            <th>หลักสูตร</th>
            <th className="num" style={{ width: 90 }}>ฉบับ</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={`${r.program_id}-${r.track_id ?? 'none'}-${r.curriculum_id ?? i}`}>
              <td>{r.type_code} {r.type_name}</td>
              <td>{r.program_code} {r.program_name}</td>
              <td><Badge kind="default">{QUALIFICATION_LEVEL[r.program_level] ?? r.program_level}</Badge></td>
              <td>{r.track_name ? `${r.track_code} ${r.track_name}` : <span className="hint">— ยังไม่มีสาขางาน —</span>}</td>
              <td>{r.curriculum_name ?? (r.track_id && <span className="hint">— ยังไม่มีหลักสูตร —</span>)}</td>
              <td className="num">
                {r.curriculum_id ? (
                  Number(r.versions) === 0
                    ? <Badge kind="warn">ยังไม่มีฉบับ</Badge>
                    : r.versions
                ) : ''}
              </td>
            </tr>
          ))}
          {rows.length === 0 && (
            <tr><td colSpan={6} style={{ textAlign: 'center', color: 'var(--ink-soft)' }}>ยังไม่มีสาขาวิชาในระบบ — เริ่มจากเพิ่มหมวดสาขาด้านล่าง</td></tr>
          )}
        </tbody>
      </table>
    </TableCard>
  );
}

export function CurriculumScreen() {
  const programs = useAsync(() => api.get<ProgramRow[]>('/curriculum/programs'), []);
  const gradeSchemes = useAsync(() => api.get<GradeScheme[]>('/curriculum/grade-schemes'), []);
  const versions = useAsync(() => api.get<Version[]>('/curriculum/versions'), []);
  const [versionId, setVersionId] = useState('');
  const [q, setQ] = useState('');

  const rows = programs.data ?? [];
  const programTypes = uniqueBy(rows, (r) => r.program_type_id);
  const allPrograms = uniqueBy(rows, (r) => r.program_id);
  const tracksOnly = uniqueBy(rows.filter((r) => r.track_id), (r) => r.track_id);
  const curriculaOnly = uniqueBy(rows.filter((r) => r.curriculum_id), (r) => r.curriculum_id);

  const reloadTree = () => programs.reload();

  const structure = useAsync(
    () =>
      versionId
        ? api.get<Structure>(`/curriculum/versions/${versionId}`)
        : Promise.resolve(null as unknown as Structure),
    [versionId],
  );
  const courses = useAsync(
    () => api.get<{ id: string; code: string; name_th: string; credits: string }[]>(
      `/curriculum/courses${qs({ q })}`,
    ),
    [q],
  );

  return (
    <>
      <PageHead title="โครงสร้างหลักสูตร" />

      <ProgramTree rows={rows} />
      <AddProgramTypeForm onDone={reloadTree} />
      <AddProgramForm programTypes={programTypes} onDone={reloadTree} />
      <AddProgramTrackForm programs={allPrograms} onDone={reloadTree} />
      <AddCurriculumForm tracks={tracksOnly} onDone={reloadTree} />
      <AddVersionForm
        curricula={curriculaOnly}
        gradeSchemes={gradeSchemes.data ?? []}
        onDone={() => { reloadTree(); versions.reload(); }}
      />

      <TableCard title="ฉบับหลักสูตร">
        <AsyncView state={versions} empty="ยังไม่มีหลักสูตรในระบบ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 34 }} />
                  <th style={{ width: 90 }}>ฉบับ</th>
                  <th style={{ width: 150 }}>ปีที่ใช้</th>
                  <th className="num" style={{ width: 110 }}>หน่วยกิตขั้นต่ำ</th>
                  <th className="num" style={{ width: 90 }}>GPAX</th>
                  <th className="num" style={{ width: 90 }}>รายวิชา</th>
                  <th className="num" style={{ width: 80 }}>กฎจบ</th>
                  <th className="num" style={{ width: 100 }}>นักศึกษา</th>
                  <th style={{ width: 100 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((v) => (
                  <tr key={v.id}>
                    <td>
                      <input
                        type="radio"
                        name="cv"
                        style={{ width: 'auto' }}
                        checked={versionId === v.id}
                        onChange={() => setVersionId(v.id)}
                      />
                    </td>
                    <td>{v.edition_be}</td>
                    <td>
                      {v.effective_from_year_be}
                      {v.effective_to_year_be ? `–${v.effective_to_year_be}` : ' เป็นต้นไป'}
                    </td>
                    <td className="num">{num(v.min_total_credits)}</td>
                    <td className="num">{num(v.min_gpax, 2)}</td>
                    <td className="num">{v.courses}</td>
                    <td className="num">{v.rules}</td>
                    <td className="num">{v.students}</td>
                    <td>
                      <Badge kind={v.status === 'active' ? 'ok' : 'default'}>
                        {v.status === 'active' ? 'ใช้งานอยู่' : v.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {versionId && versions.data && (
        <CloneVersionCard
          version={versions.data.find((v) => v.id === versionId)!}
          onDone={() => versions.reload()}
        />
      )}

      {versionId && (
        <AsyncView state={structure}>
          {(s) => (
            <>
              <TableCard title="เกณฑ์การจบของฉบับนี้">
                <table>
                  <thead>
                    <tr>
                      <th>เกณฑ์</th>
                      <th className="num" style={{ width: 120 }}>ค่าที่ต้องถึง</th>
                      <th style={{ width: 110 }}>บังคับไหม</th>
                    </tr>
                  </thead>
                  <tbody>
                    {s.graduationRules.map((r) => (
                      <tr key={r.id}>
                        <td style={{ whiteSpace: 'normal' }}>{r.name_th}</td>
                        <td className="num">{r.threshold === null ? '—' : num(r.threshold, 2)}</td>
                        <td>
                          <Badge kind={r.is_blocking ? 'danger' : 'default'}>
                            {r.is_blocking ? 'บังคับ' : 'ไม่บังคับ'}
                          </Badge>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TableCard>

              {/*
                วางไว้ **เหนือ** รายการหมวดวิชาโดยตั้งใจ — คนที่เปิดหน้านี้ตอน
                เปิดวิทยาลัยใหม่มาเพื่อ "ลงข้อมูล" ไม่ใช่เพื่ออ่านของที่ยังไม่มี
                ถ้าอยู่ท้ายสุด หลักสูตรที่ยังว่างจะแสดงหมวดเปล่า ๆ สิบกว่าใบ
                คั่นก่อนถึงกล่องที่ใช้ทำงานจริง
              */}
              <CourseEntry
                versionId={versionId}
                editionBe={s.edition_be}
                categories={s.categories}
                onDone={structure.reload}
              />

              {s.categories.map((c) => (
                <TableCard
                  key={c.id}
                  title={
                    <>
                      <span className="mono">{c.code}</span> {c.name_th}
                      {c.min_credits && ` — อย่างน้อย ${num(c.min_credits)} หน่วยกิต`}
                      {` · ${c.courses.length} วิชา`}
                    </>
                  }
                >
                  {c.courses.length === 0 ? (
                    <div className="empty">ยังไม่มีรายวิชาในหมวดนี้</div>
                  ) : (
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 120 }}>รหัสวิชา</th>
                          <th>ชื่อวิชา</th>
                          <th className="num" style={{ width: 70 }}>นก.</th>
                          <th style={{ width: 110 }}>ประเภท</th>
                          <th style={{ width: 190 }}>ภาคเรียนตามหลักสูตร</th>
                          <th style={{ width: 90 }}>ลำดับ</th>
                        </tr>
                      </thead>
                      <tbody>
                        {c.courses.map((co, i) => (
                          <tr key={co.id}>
                            <td className="mono">{co.code}</td>
                            <td>{co.name_th}</td>
                            <td className="num">{co.credits ? num(co.credits) : '—'}</td>
                            <td>
                              <Badge kind={co.requirement === 'required' ? 'info' : 'default'}>
                                {REQUIREMENT[co.requirement] ?? co.requirement}
                              </Badge>
                            </td>
                            <td>
                              <PlanTermEditor course={co} onSaved={() => structure.reload()} />
                            </td>
                            <td>
                              {/*
                                เลื่อนทีละขั้นแต่ส่งลำดับ**ทั้งชุด**ไปให้ API
                                — ถ้าส่งแค่สองแถวที่สลับกัน คนสองคนที่เปิด
                                หน้าจอเดียวกันอยู่จะเขียนทับกันจนลำดับเพี้ยน
                                โดยไม่มีใครเห็น
                              */}
                              <ActionButton
                                className="ghost"
                                onRun={() => moveCourse(versionId, c.courses, i, -1)}
                                onDone={() => structure.reload()}
                              >
                                ↑
                              </ActionButton>{' '}
                              <ActionButton
                                className="ghost"
                                onRun={() => moveCourse(versionId, c.courses, i, 1)}
                                onDone={() => structure.reload()}
                              >
                                ↓
                              </ActionButton>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </TableCard>
              ))}

              {s.uncategorized.length > 0 && (
                <Card title={`รายวิชาที่ยังไม่ได้จัดหมวด — ${s.uncategorized.length} วิชา`}>
                  {s.uncategorized.map((co) => (
                    <div key={co.id}>
                      <span className="mono">{co.code}</span> {co.name_th}
                    </div>
                  ))}
                </Card>
              )}
            </>
          )}
        </AsyncView>
      )}

      <TableCard title="คลังรายวิชาของวิทยาลัย">
        <div style={{ padding: 12, borderBottom: '1px solid var(--line-soft)' }}>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="ค้นหาด้วยรหัสหรือชื่อวิชา"
            style={{ maxWidth: 320 }}
          />
        </div>
        <AsyncView state={courses} empty="ไม่พบรายวิชา">
          {(rows) => (
            <div style={{ maxHeight: 320, overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 120 }}>รหัสวิชา</th>
                    <th>ชื่อวิชา</th>
                    <th className="num" style={{ width: 80 }}>หน่วยกิต</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((c) => (
                    <tr key={c.id}>
                      <td className="mono">{c.code}</td>
                      <td>{c.name_th}</td>
                      <td className="num">{num(c.credits)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}

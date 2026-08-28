/**
 * สมรรถนะ
 *
 * ─── ทำไมแยกหน้าจากกลุ่มวิชา ───
 * กลุ่มวิชาจัดรายวิชาเป็นหมวดสำหรับนับหน่วยกิต ส่วนสมรรถนะบอกว่ารายวิชา
 * แต่ละตัว "ฝึกอะไร" ให้นักศึกษา — คนละมิติกัน วิชาเดียวฝึกได้หลายสมรรถนะ
 * และสมรรถนะเดียวถูกฝึกได้จากหลายวิชา (many-to-many ผ่าน course_competency)
 */
import { useState } from 'react';
import { api } from '../core/api';
import { href } from '../core/router';
import { ActionButton, AsyncView, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface Version { id: string; edition_be: number; effective_from_year_be: number; effective_to_year_be: number | null }
interface CourseRef { mappingId: string; courseId: string; code: string; nameTh: string; isPrimary: boolean }
interface Competency { id: string; code: string; statement_th: string; sort_order: number; courses: CourseRef[] }
interface CatalogCourse { id: string; code: string; name_th: string }

export function CompetenciesScreen() {
  const versions = useAsync(() => api.get<Version[]>('/curriculum/versions'), []);
  const [versionId, setVersionId] = useState('');
  const competencies = useAsync(
    () => versionId ? api.get<Competency[]>(`/curriculum/versions/${versionId}/competencies`) : Promise.resolve([]),
    [versionId],
  );
  const courses = useAsync(() => api.get<CatalogCourse[]>('/curriculum/courses'), []);

  return <>
    <PageHead
      title="สมรรถนะ"
      sub="กำหนดสมรรถนะของฉบับหลักสูตร แล้วผูกกับรายวิชาที่ฝึกสมรรถนะนั้น"
      actions={<a href={href('/subject-data')}>← ข้อมูลวิชา</a>}
    />
    <Card title="เลือกฉบับหลักสูตร">
      <Field label="ฉบับหลักสูตร">
        <select value={versionId} onChange={(e) => setVersionId(e.target.value)}>
          <option value="">— เลือกฉบับหลักสูตร —</option>
          {(versions.data ?? []).map((v) => (
            <option key={v.id} value={v.id}>
              ฉบับ {v.edition_be} · ใช้ตั้งแต่ปี {v.effective_from_year_be}{v.effective_to_year_be ? `–${v.effective_to_year_be}` : ''}
            </option>
          ))}
        </select>
      </Field>
    </Card>

    {!versionId ? <Notice kind="info">เลือกฉบับหลักสูตรก่อน เพื่อให้สมรรถนะไม่ปะปนกันระหว่างหลักสูตรคนละฉบับ</Notice> : <>
      <NewCompetencyCard versionId={versionId} onDone={competencies.reload} />
      <TableCard title="สมรรถนะของฉบับหลักสูตรนี้">
        <AsyncView state={competencies} empty="ยังไม่มีสมรรถนะ — เพิ่มจากแบบฟอร์มด้านบน">
          {(rows) => rows.length === 0 ? <div className="empty">ยังไม่มีสมรรถนะ — เพิ่มจากแบบฟอร์มด้านบน</div> : (
            <table>
              <thead><tr><th style={{ width: 90 }}>รหัส</th><th>ข้อความสมรรถนะ</th><th>รายวิชาที่ฝึกสมรรถนะนี้</th><th style={{ width: 140 }}></th></tr></thead>
              <tbody>
                {rows.map((c) => (
                  <CompetencyRow key={c.id} competency={c} courses={courses.data ?? []} onDone={competencies.reload} />
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>}
  </>;
}

function NewCompetencyCard({ versionId, onDone }: { versionId: string; onDone: () => void }) {
  const [code, setCode] = useState('');
  const [statementTh, setStatementTh] = useState('');

  return (
    <Card title="เพิ่มสมรรถนะใหม่">
      <div className="row">
        <Field label="รหัสสมรรถนะ"><input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น C1" style={{ width: 100 }} /></Field>
        <Field label="ข้อความสมรรถนะ"><input value={statementTh} onChange={(e) => setStatementTh(e.target.value)} placeholder="เช่น ซ่อมบำรุงเครื่องยนต์แก๊สโซลีนได้ถูกต้องตามคู่มือ" style={{ minWidth: 360 }} /></Field>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!code.trim() || !statementTh.trim()) throw new Error('กรอกรหัสและข้อความสมรรถนะให้ครบ');
              return api.post(`/curriculum/versions/${versionId}/competencies`, { code: code.trim(), statementTh: statementTh.trim() });
            }}
            onDone={() => { setCode(''); setStatementTh(''); onDone(); }}
          >
            เพิ่มสมรรถนะ
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function CompetencyRow({ competency, courses, onDone }: { competency: Competency; courses: CatalogCourse[]; onDone: () => void }) {
  const [editing, setEditing] = useState(false);
  const [code, setCode] = useState(competency.code);
  const [statementTh, setStatementTh] = useState(competency.statement_th);
  const [courseToAdd, setCourseToAdd] = useState('');

  const unmapped = courses.filter((c) => !competency.courses.some((mc) => mc.courseId === c.id));

  if (editing) {
    return (
      <tr>
        <td><input value={code} onChange={(e) => setCode(e.target.value)} style={{ width: 80 }} /></td>
        <td><input value={statementTh} onChange={(e) => setStatementTh(e.target.value)} style={{ width: '100%' }} /></td>
        <td>{competency.courses.length} วิชา</td>
        <td className="row" style={{ gap: 6 }}>
          <ActionButton
            className="primary"
            onRun={() => {
              if (!code.trim() || !statementTh.trim()) throw new Error('กรอกรหัสและข้อความสมรรถนะให้ครบ');
              return api.patch(`/curriculum/competencies/${competency.id}`, { code: code.trim(), statementTh: statementTh.trim() });
            }}
            onDone={() => { setEditing(false); onDone(); }}
          >
            บันทึก
          </ActionButton>
          <button onClick={() => setEditing(false)}>ยกเลิก</button>
        </td>
      </tr>
    );
  }

  return (
    <tr>
      <td className="mono">{competency.code}</td>
      <td>{competency.statement_th}</td>
      <td>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4, marginBottom: 6 }}>
          {competency.courses.length === 0 && <span className="hint">ยังไม่มีวิชาผูกไว้</span>}
          {competency.courses.map((c) => (
            <span key={c.courseId} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '2px 8px', borderRadius: 999, background: 'var(--bg-soft, #f0f0f0)', border: '1px solid var(--line-soft, #ddd)' }}>
              <span className="mono">{c.code}</span> {c.nameTh}
              <ActionButton
                toast
                confirm={`เอาวิชา ${c.code} ออกจากสมรรถนะนี้หรือไม่`}
                onRun={() => api.del(`/curriculum/course-competencies/${c.mappingId}`)}
                onDone={onDone}
              >
                ×
              </ActionButton>
            </span>
          ))}
        </div>
        <div className="row" style={{ gap: 6 }}>
          <select value={courseToAdd} onChange={(e) => setCourseToAdd(e.target.value)} style={{ maxWidth: 260 }}>
            <option value="">— เลือกวิชาเพื่อผูก —</option>
            {unmapped.map((c) => <option key={c.id} value={c.id}>{c.code} {c.name_th}</option>)}
          </select>
          {courseToAdd && (
            <ActionButton
              toast
              onRun={() => api.post('/curriculum/course-competencies', { courseId: courseToAdd, competencyId: competency.id })}
              onDone={() => { setCourseToAdd(''); onDone(); }}
            >
              ผูกวิชานี้
            </ActionButton>
          )}
        </div>
      </td>
      <td className="row" style={{ gap: 6 }}>
        <button onClick={() => setEditing(true)}>แก้ไข</button>
        <ActionButton
          toast
          confirm={`ลบสมรรถนะ "${competency.statement_th}" — ลบได้เฉพาะที่ไม่มีรายวิชาผูกอยู่ ยืนยันหรือไม่`}
          onRun={() => api.del(`/curriculum/competencies/${competency.id}`)}
          onDone={onDone}
        >
          ลบ
        </ActionButton>
      </td>
    </tr>
  );
}

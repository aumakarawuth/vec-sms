import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { href } from '../core/router';
import { ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

type Version = { id: string; edition_be: number; effective_from_year_be: number; effective_to_year_be: number | null; status: string; courses: string | number };
type Category = { id: string; parent_id: string | null; code: string; name_th: string; kind: string; min_credits: string | null; max_credits: string | null; courses: unknown[] };
type Structure = { edition_be: number; categories: Category[] };

const KIND: Record<string, string> = {
  core_competency: 'สมรรถนะแกนกลาง', vocational: 'วิชาชีพ', voc_basic: 'วิชาชีพพื้นฐาน',
  voc_specific: 'วิชาชีพเฉพาะ', voc_elective: 'วิชาชีพเลือก', practicum: 'ฝึกประสบการณ์',
  project: 'โครงการ', free_elective: 'เลือกเสรี', activity: 'กิจกรรม',
};

function flatten(categories: Category[]) {
  const byParent = new Map<string | null, Category[]>();
  for (const category of categories) {
    const list = byParent.get(category.parent_id) ?? [];
    list.push(category);
    byParent.set(category.parent_id, list);
  }
  const rows: Array<{ category: Category; depth: number }> = [];
  const walk = (parent: string | null, depth: number) => {
    for (const category of (byParent.get(parent) ?? []).sort((a, b) => a.code.localeCompare(b.code, 'th'))) {
      rows.push({ category, depth });
      walk(category.id, depth + 1);
    }
  };
  walk(null, 0);
  return rows;
}

export function SubjectGroupsScreen() {
  const versions = useAsync(() => api.get<Version[]>('/curriculum/versions'), []);
  const [versionId, setVersionId] = useState('');
  const structure = useAsync(() => versionId ? api.get<Structure>(`/curriculum/versions/${versionId}`) : Promise.resolve(null), [versionId]);
  const rows = useMemo(() => flatten(structure.data?.categories ?? []), [structure.data]);

  return <>
    <PageHead title="กลุ่มวิชา" sub="กำหนดกลุ่มวิชาในแต่ละฉบับหลักสูตร แล้วนำไปผูกรายวิชาและแผนการเรียน" actions={<a href={href('/subject-data')}>← ข้อมูลวิชา</a>} />
    <Card title="เลือกฉบับหลักสูตร">
      <Field label="ฉบับหลักสูตร"><select value={versionId} onChange={(e) => setVersionId(e.target.value)}>
        <option value="">— เลือกฉบับหลักสูตร —</option>
        {(versions.data ?? []).map((version) => <option key={version.id} value={version.id}>ฉบับ {version.edition_be} · ใช้ตั้งแต่ปี {version.effective_from_year_be}{version.effective_to_year_be ? `–${version.effective_to_year_be}` : ''}</option>)}
      </select></Field>
      {versions.loading && <span className="hint">กำลังโหลดฉบับหลักสูตร…</span>}
    </Card>

    {!versionId ? <Notice kind="info">เลือกฉบับหลักสูตรก่อน เพื่อให้กลุ่มวิชาไม่ปะปนกันระหว่างหลักสูตรคนละฉบับ</Notice> : <AsyncView state={structure} empty="ไม่พบโครงสร้างหลักสูตร">
      {(data) => data && <>
        <SubjectGroupForm versionId={versionId} categories={data.categories} onDone={structure.reload} />
        <TableCard title={`กลุ่มวิชาในหลักสูตรฉบับ ${data.edition_be}`}>
          {rows.length === 0 ? <div className="empty">ยังไม่มีกลุ่มวิชา — เพิ่มกลุ่มแรกจากแบบฟอร์มด้านบน</div> : <table>
            <thead><tr><th style={{ width: 105 }}>รหัส</th><th>หัวข้อ</th><th style={{ width: 170 }}>ประเภท</th><th className="num" style={{ width: 100 }}>รายวิชา</th><th className="num" style={{ width: 130 }}>หน่วยกิต</th></tr></thead>
            <tbody>{rows.map(({ category, depth }) => <tr key={category.id}>
              <td className="mono">{category.code}</td>
              <td style={{ paddingLeft: 16 + depth * 26 }}><span aria-hidden="true">{depth ? '↳ ' : ''}</span>{category.name_th}</td>
              <td><Badge kind="info">{KIND[category.kind] ?? category.kind}</Badge></td>
              <td className="num">{category.courses.length}</td>
              <td className="num">{category.min_credits ?? '—'}{category.max_credits ? `–${category.max_credits}` : ''}</td>
            </tr>)}</tbody>
          </table>}
        </TableCard>
      </>}
    </AsyncView>}
  </>;
}

function SubjectGroupForm({ versionId, categories, onDone }: { versionId: string; categories: Category[]; onDone: () => void }) {
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');
  const [kind, setKind] = useState('vocational');
  const [parentId, setParentId] = useState('');
  const [minCredits, setMinCredits] = useState('');
  const [maxCredits, setMaxCredits] = useState('');
  const parents = useMemo(() => flatten(categories), [categories]);
  const ready = code.trim() !== '' && nameTh.trim() !== '';

  return <Card title="เพิ่มกลุ่มวิชา">
    <p className="hint">ใช้กลุ่มหลักเพื่อจัดโครงสร้าง เช่น “หมวดวิชาทักษะวิชาชีพ” แล้วเลือกกลุ่มแม่เมื่อเพิ่มกลุ่มย่อย</p>
    <div className="row">
      <Field label="รหัสกลุ่ม"><input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น 1 หรือ VOC" style={{ maxWidth: 130 }} /></Field>
      <Field label="ชื่อกลุ่มวิชา"><input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น หมวดวิชาทักษะวิชาชีพ" /></Field>
      <Field label="ประเภท"><select value={kind} onChange={(e) => setKind(e.target.value)}>{Object.entries(KIND).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></Field>
      <Field label="อยู่ภายใต้กลุ่ม"><select value={parentId} onChange={(e) => setParentId(e.target.value)}><option value="">— กลุ่มหลัก —</option>{parents.map(({ category, depth }) => <option key={category.id} value={category.id}>{'— '.repeat(depth)}{category.code} {category.name_th}</option>)}</select></Field>
      <Field label="หน่วยกิตขั้นต่ำ"><input type="number" min="0" value={minCredits} onChange={(e) => setMinCredits(e.target.value)} style={{ maxWidth: 100 }} /></Field>
      <Field label="หน่วยกิตสูงสุด"><input type="number" min="0" value={maxCredits} onChange={(e) => setMaxCredits(e.target.value)} style={{ maxWidth: 100 }} /></Field>
      <div className="shrink">{ready ? <ActionButton className="primary" toast onRun={() => api.post(`/curriculum/versions/${versionId}/categories`, {
        code: code.trim(), nameTh: nameTh.trim(), kind, ...(parentId ? { parentId } : {}),
        ...(minCredits !== '' ? { minCredits: Number(minCredits) } : {}), ...(maxCredits !== '' ? { maxCredits: Number(maxCredits) } : {}),
        sortOrder: categories.length,
      })} onDone={() => { setCode(''); setNameTh(''); setParentId(''); setMinCredits(''); setMaxCredits(''); onDone(); }}>เพิ่มกลุ่มวิชา</ActionButton> : <button className="primary" disabled>เพิ่มกลุ่มวิชา</button>}</div>
    </div>
  </Card>;
}

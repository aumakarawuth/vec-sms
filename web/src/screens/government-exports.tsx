import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { href } from '../core/router';
import type { Role } from '../core/session';
import { AsyncView, Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useAsync, useCan } from '../ui/kit';

const EXPORTS_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];

interface ExportFormat {
  id: string;
  label: string;
  agency: string;
  dataset: string;
  approvalDates: boolean;
  studentStatuses: boolean;
}

interface Catalog {
  formats: ExportFormat[];
  terms: Array<{ id: string; year_be: number; ordinal: number; kind: string; status: string }>;
  curricula: Array<{
    id: string; edition_be: number; status: string; code: string; name_th: string;
    program_code: string; program_name: string; program_type_code: string; program_type_name: string;
  }>;
}

interface Preview {
  rows: number;
  dataset: string;
  issues: Array<{ level: 'error' | 'warning'; code: string; message: string }>;
  sample: Array<Record<string, unknown>>;
}

interface GeneratedFile { filename: string; mimeType: string; bytes: number; contentBase64: string }

const DATASETS = [
  { id: 'students', label: 'ข้อมูลนักศึกษา' },
  { id: 'timetable', label: 'ตารางเรียน/ตารางสอน' },
  { id: 'grades', label: 'ผลการเรียน' },
];

export function GovernmentExportsScreen() {
  const canUse = useCan(...EXPORTS_ROLES);
  const catalog = useAsync(
    () => (canUse ? api.get<Catalog>('/government-exports/catalog') : Promise.resolve(null as unknown as Catalog)),
    [canUse],
  );
  return (
    <>
      <PageHead title="ส่งออกข้อมูลให้หน่วยงานรัฐ" sub={<a href={href('/settings-center')}>← ศูนย์การตั้งค่า</a>} />
      {!canUse ? (
        <RestrictedNotice roles={EXPORTS_ROLES} />
      ) : (
        <AsyncView state={catalog}>{(data) => <ExportForm catalog={data} />}</AsyncView>
      )}
    </>
  );
}

function ExportForm({ catalog }: { catalog: Catalog }) {
  const [formatId, setFormatId] = useState(catalog.formats[0]?.id ?? 'standard');
  const [termId, setTermId] = useState(catalog.terms[0]?.id ?? '');
  const [dataset, setDataset] = useState('students');
  const [curricula, setCurricula] = useState<string[]>([]);
  const [statuses, setStatuses] = useState<string[]>(['active']);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const format = catalog.formats.find((x) => x.id === formatId) ?? catalog.formats[0];
  const grouped = useMemo(() => Object.entries(catalog.curricula.reduce<Record<string, Catalog['curricula']>>((all, item) => {
    (all[item.program_type_name] ??= []).push(item);
    return all;
  }, {})), [catalog.curricula]);

  function toggle(list: string[], value: string, set: (value: string[]) => void) {
    set(list.includes(value) ? list.filter((x) => x !== value) : [...list, value]);
    setPreview(null);
  }

  function payload() {
    return {
      format: formatId,
      termId,
      ...(formatId === 'standard' ? { dataset } : {}),
      curriculumVersionIds: curricula,
      studentStatuses: statuses,
    };
  }

  async function inspect() {
    setBusy(true); setError(null);
    try { setPreview(await api.post<Preview>('/government-exports/preview', payload())); }
    catch (e) { setError(e instanceof Error ? e.message : 'ตรวจสอบข้อมูลไม่สำเร็จ'); }
    finally { setBusy(false); }
  }

  async function generate() {
    setBusy(true); setError(null);
    try {
      const result = await api.post<GeneratedFile>('/government-exports/generate', payload());
      const binary = atob(result.contentBase64);
      const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([bytes], { type: result.mimeType }));
      const link = document.createElement('a');
      link.href = url; link.download = result.filename; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 0);
    } catch (e) { setError(e instanceof Error ? e.message : 'สร้างไฟล์ไม่สำเร็จ'); }
    finally { setBusy(false); }
  }

  const hasErrors = preview?.issues.some((x) => x.level === 'error') ?? false;
  return (
    <>
      <Notice kind="info">
        ขั้นตอนเลือกข้อมูลจัดวางตาม SISA: เลือกรูปแบบ ปี/ภาคเรียน หลักสูตร และสถานะ แล้วตรวจความพร้อมก่อนสร้างไฟล์
      </Notice>
      <Card title="กำหนดข้อมูลส่งออก">
        <div className="row">
          <Field label="รูปแบบ / หน่วยงานปลายทาง">
            <select value={formatId} onChange={(e) => { setFormatId(e.target.value); setPreview(null); }}>
              {catalog.formats.map((x) => <option key={x.id} value={x.id}>{x.label} — {x.agency}</option>)}
            </select>
          </Field>
          <Field label="ปีการศึกษา / ภาคเรียน">
            <select value={termId} onChange={(e) => { setTermId(e.target.value); setPreview(null); }}>
              {catalog.terms.map((x) => <option key={x.id} value={x.id}>{x.year_be} / {x.ordinal} ({x.status})</option>)}
            </select>
          </Field>
          {formatId === 'standard' && <Field label="ชุดข้อมูล">
            <select value={dataset} onChange={(e) => { setDataset(e.target.value); setPreview(null); }}>
              {DATASETS.map((x) => <option key={x.id} value={x.id}>{x.label}</option>)}
            </select>
          </Field>}
        </div>

        <h3>หลักสูตร/สาขาที่ต้องการ</h3>
        <label><input type="checkbox" checked={curricula.length === 0} onChange={() => { setCurricula([]); setPreview(null); }} /> ทุกหลักสูตร</label>
        {grouped.map(([group, items]) => <div key={group} style={{ marginTop: 10 }}>
          <strong>{group}</strong>
          <div className="row">
            {items.map((x) => <label key={x.id} style={{ minWidth: 260 }}>
              <input type="checkbox" checked={curricula.includes(x.id)} onChange={() => toggle(curricula, x.id, setCurricula)} />{' '}
              {x.program_code} {x.program_name} — {x.name_th} ({x.edition_be})
            </label>)}
          </div>
        </div>)}

        {format?.studentStatuses && <>
          <h3>สถานะนักศึกษา</h3>
          <div className="row">
            {[{ id: 'active', label: 'กำลังศึกษา/ลาพัก' }, { id: 'graduated', label: 'สำเร็จการศึกษา' }, { id: 'inactive', label: 'พ้นสภาพ/ย้าย' }].map((item) =>
              <label key={item.id}><input type="checkbox" checked={statuses.includes(item.id)} onChange={() => toggle(statuses, item.id, setStatuses)} /> {item.label}</label>)}
          </div>
        </>}

        <div className="row" style={{ marginTop: 18 }}>
          <div className="shrink"><button disabled={busy || !termId} onClick={() => void inspect()}>{busy ? 'กำลังตรวจ…' : 'ตรวจความพร้อม'}</button></div>
          <div className="shrink"><button className="primary" disabled={busy || !preview || hasErrors || preview.rows === 0} onClick={() => void generate()}>สร้างและดาวน์โหลด CSV</button></div>
        </div>
        {error && <Notice kind="error">{error}</Notice>}
      </Card>

      {preview && <TableCard title={`ผลตรวจสอบ — ${preview.rows.toLocaleString('th-TH')} รายการ`}>
        {preview.issues.map((x) => <Notice key={x.code} kind={x.level === 'error' ? 'error' : 'warn'}>{x.message}</Notice>)}
        {!preview.issues.length && <Notice kind="ok">ข้อมูลผ่านการตรวจเบื้องต้น พร้อมสร้างไฟล์</Notice>}
        {preview.sample.length > 0 && <div style={{ overflowX: 'auto' }}><table>
          <thead><tr>{Object.keys(preview.sample[0]!).map((h) => <th key={h}>{h}</th>)}</tr></thead>
          <tbody>{preview.sample.map((row, i) => <tr key={i}>{Object.values(row).map((v, j) => <td key={j}>{v == null ? '' : String(v)}</td>)}</tr>)}</tbody>
        </table></div>}
      </TableCard>}

      <Notice kind="warn">
        ไฟล์นี้เป็น CSV สำหรับตรวจสอบและนำไปแปลงตามช่องข้อมูลของหน่วยงานปลายทาง ต้องทดสอบรับรองกับคู่มือหรือไฟล์ตัวอย่างรุ่นปัจจุบันก่อนนำส่งจริง
      </Notice>
    </>
  );
}

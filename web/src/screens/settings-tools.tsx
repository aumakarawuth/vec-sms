/**
 * การตั้งค่าแบบ SISA ที่ยังขาด — ข้อมูลพื้นฐาน · ข้อความบนเอกสาร · บันทึกเหตุการณ์
 * หน้าละงาน (หลักเดียวกับหน้าการเงิน)
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDate } from '../core/fmt';
import type { Role } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useAsync, useCan,
} from '../ui/kit';

export const SETTINGS_TOOL_SECTIONS = {
  options: { title: 'ข้อมูลพื้นฐาน', sub: 'คำที่ระบบเสนอให้เลือกตอนกรอก — คำนำหน้า ศาสนา สัญชาติ อาชีพ ธนาคาร ฯลฯ' },
  'document-texts': { title: 'ข้อความบนเอกสาร', sub: 'เกณฑ์การสำเร็จการศึกษา หมายเหตุ และชื่อผู้ลงนามที่พิมพ์บนใบ รบ.' },
  audit: { title: 'บันทึกเหตุการณ์', sub: 'ใครเข้าถึงหรือเปลี่ยนข้อมูลของใคร เมื่อไร — หลักฐานตาม PDPA มาตรา 37' },
} as const;
export type SettingsToolSection = keyof typeof SETTINGS_TOOL_SECTIONS;

const CATEGORY: Record<string, string> = {
  prefix: 'คำนำหน้าชื่อ', religion: 'ศาสนา', nationality: 'สัญชาติ', ethnicity: 'เชื้อชาติ',
  occupation: 'อาชีพ', bank: 'ธนาคาร', school: 'สถานศึกษา', qualification: 'วุฒิการศึกษา',
};

export function SettingsToolsScreen({ section }: { section: SettingsToolSection }) {
  const meta = SETTINGS_TOOL_SECTIONS[section];
  return (
    <>
      <PageHead title={meta.title} sub={meta.sub} />
      {section === 'options' && <Options />}
      {section === 'document-texts' && <DocumentTexts />}
      {section === 'audit' && <Audit />}
    </>
  );
}

interface Option { id: string; category: string; code: string | null; label_th: string; label_en: string | null; sort_order: number; active: boolean }

function Options() {
  const canEdit = useCan('registrar', 'director', 'admin');
  const [cat, setCat] = useState('prefix');
  const [label, setLabel] = useState('');
  const [labelEn, setLabelEn] = useState('');
  const [code, setCode] = useState('');
  const rows = useAsync(() => api.get<Option[]>(`/settings/options${qs({ category: cat })}`), [cat]);
  return (
    <div className="stats-layout">
      <Card title="หมวด">
        <div className="stats-dims">
          {Object.entries(CATEGORY).map(([k, l]) => (
            <button key={k} className={k === cat ? 'active' : ''} onClick={() => setCat(k)}>{l}</button>
          ))}
        </div>
      </Card>
      <div>
        {canEdit && (
          <Card title={`เพิ่ม${CATEGORY[cat]}`}>
            <div className="row">
              <Field label="รหัส (ถ้ามี)"><input value={code} onChange={(e) => setCode(e.target.value)} /></Field>
              <Field label="ชื่อภาษาไทย"><input value={label} onChange={(e) => setLabel(e.target.value)} /></Field>
              <Field label="ชื่อภาษาอังกฤษ"><input value={labelEn} onChange={(e) => setLabelEn(e.target.value)} /></Field>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  onRun={() => api.post('/settings/options', {
                    category: cat, labelTh: label.trim(),
                    ...(labelEn.trim() ? { labelEn: labelEn.trim() } : {}), ...(code.trim() ? { code: code.trim() } : {}),
                  })}
                  onDone={() => { setLabel(''); setLabelEn(''); setCode(''); rows.reload(); }}
                >
                  เพิ่ม
                </ActionButton>
              </div>
            </div>
          </Card>
        )}
        <TableCard title={CATEGORY[cat]}>
          <AsyncView state={rows} empty="ยังไม่มีรายการ">
            {(list) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 80 }}>รหัส</th>
                    <th>ภาษาไทย</th>
                    <th>ภาษาอังกฤษ</th>
                    <th style={{ width: 110 }}>สถานะ</th>
                    {canEdit && <th style={{ width: 110 }} />}
                  </tr>
                </thead>
                <tbody>
                  {list.map((o) => (
                    <tr key={o.id} style={{ opacity: o.active ? 1 : 0.55 }}>
                      <td className="mono">{o.code ?? '—'}</td>
                      <td>{o.label_th}</td>
                      <td>{o.label_en ?? '—'}</td>
                      <td>{o.active ? <Badge kind="ok">ใช้งาน</Badge> : <Badge>ปิดแล้ว</Badge>}</td>
                      {canEdit && (
                        <td>
                          <ActionButton
                            onRun={() => api.patch(`/settings/options/${o.id}`, { active: !o.active })}
                            onDone={() => rows.reload()}
                          >
                            {o.active ? 'ปิด' : 'เปิดใช้'}
                          </ActionButton>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
        </TableCard>
        <Notice kind="info">
          ปิดแทนการลบ เพราะข้อมูลเดิมที่ใช้คำนั้นอยู่ยังต้องอ่านออก รายการที่ปิดจะไม่ถูกเสนอให้เลือกอีก
        </Notice>
      </div>
    </div>
  );
}

interface DocText { key: string; label: string; textTh: string | null; textEn: string | null; updatedAt: string | null }

function DocumentTexts() {
  const can = useCan('registrar', 'director', 'admin');
  const rows = useAsync(() => (can ? api.get<DocText[]>('/settings/document-texts') : Promise.resolve([])), [can]);
  if (!can) return <RestrictedNotice roles={['registrar', 'director', 'admin'] as Role[]} />;
  return (
    <>
      <Notice kind="info">
        ใบที่ออกไปแล้วไม่เปลี่ยนตาม — ข้อความถูกตรึงลงเอกสารตั้งแต่วันที่ออก การแก้ที่นี่มีผลกับใบที่ออกหลังจากนี้เท่านั้น
      </Notice>
      <AsyncView state={rows}>
        {(list) => (
          <>
            {list.map((r) => <DocTextRow key={r.key} row={r} onDone={() => rows.reload()} />)}
          </>
        )}
      </AsyncView>
    </>
  );
}

function DocTextRow({ row, onDone }: { row: DocText; onDone: () => void }) {
  const [th, setTh] = useState(row.textTh ?? '');
  const [en, setEn] = useState(row.textEn ?? '');
  const dirty = th !== (row.textTh ?? '') || en !== (row.textEn ?? '');
  return (
    <Card title={row.label}>
      <div className="row">
        <Field label="ภาษาไทย"><input value={th} onChange={(e) => setTh(e.target.value)} /></Field>
        <Field label="ภาษาอังกฤษ"><input value={en} onChange={(e) => setEn(e.target.value)} /></Field>
        <div className="shrink">
          <ActionButton
            className={dirty ? 'primary' : ''}
            onRun={() => api.post('/settings/document-texts', { key: row.key, textTh: th, textEn: en })}
            onDone={onDone}
          >
            บันทึก
          </ActionButton>
        </div>
      </div>
      {row.updatedAt && <small className="muted">แก้ล่าสุด {thaiDate(row.updatedAt)}</small>}
    </Card>
  );
}

interface AuditRow {
  id: string; action: string; entity: string; route: string | null; actor_role: string | null;
  occurred_at: string; actor_name: string | null; subject_name: string | null;
}

const ACTION: Record<string, string> = { read: 'เปิดดู', create: 'สร้าง', update: 'แก้ไข', delete: 'ลบ', export: 'ส่งออก', login: 'เข้าระบบ' };

function Audit() {
  const can = useCan('director', 'admin');
  const today = new Date().toISOString().slice(0, 10);
  const [from, setFrom] = useState(today);
  const [to, setTo] = useState(today);
  const [entity, setEntity] = useState('');
  const rows = useAsync(
    () => (can ? api.get<AuditRow[]>(`/audit${qs({ from: from || undefined, to: to || undefined, entity: entity.trim() || undefined })}`) : Promise.resolve([])),
    [can, from, to, entity],
  );
  if (!can) return <RestrictedNotice roles={['director', 'admin'] as Role[]} />;
  return (
    <>
      <Card title="เงื่อนไข">
        <div className="row">
          <Field label="ตั้งแต่"><input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field label="ถึง"><input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
          <Field label="ชนิดข้อมูล (เช่น student, issued_document)"><input value={entity} onChange={(e) => setEntity(e.target.value)} /></Field>
        </div>
      </Card>
      <TableCard title="รายการ (ล่าสุด 500 รายการ)">
        <AsyncView state={rows} empty="ไม่มีเหตุการณ์ในช่วงนี้">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 150 }}>เวลา</th>
                  <th>ผู้กระทำ</th>
                  <th style={{ width: 90 }}>การกระทำ</th>
                  <th>ข้อมูล</th>
                  <th>เจ้าของข้อมูล</th>
                </tr>
              </thead>
              <tbody>
                {list.map((r) => (
                  <tr key={r.id}>
                    <td>{new Date(r.occurred_at).toLocaleString('th-TH', { dateStyle: 'short', timeStyle: 'short' })}</td>
                    <td>{r.actor_name ?? '—'}{r.actor_role ? <small className="muted"> · {r.actor_role}</small> : null}</td>
                    <td>{ACTION[r.action] ?? r.action}</td>
                    <td className="mono" style={{ fontSize: 12 }}>{r.entity}{r.route ? ` · ${r.route}` : ''}</td>
                    <td>{r.subject_name ?? '—'}</td>
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

import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { thaiDate } from '../core/fmt';
import { href } from '../core/router';
import { ActionButton, AsyncView, Badge, PageHead, useAsync } from '../ui/kit';

type StaffRow = { id:string; staff_code:string; full_name:string; active:boolean; is_teacher:boolean };
type RecordRow = { id:string; kind:string; title_th:string; organization_th:string|null; field_th:string|null; started_on:string|null; ended_on:string|null; hours:string|null };
type RecordGroups = { education:RecordRow[]; experience:RecordRow[]; training:RecordRow[]; award:RecordRow[]; trainingHours:number };
type StaffDetail = { id:string; staff_code:string; full_name:string; active:boolean; is_teacher:boolean; employment_kind:string; license_no:string|null; license_expires:string|null; phone:string|null; email:string|null; roles:{id:string; role:string; active_now:boolean}[]; person_id:string };

const TABS = [
  ['general','ข้อมูลผู้ใช้ระบบ'], ['address','ที่อยู่'], ['education','การศึกษา'], ['experience','ประสบการณ์การทำงาน'],
  ['license','ใบประกอบวิชาชีพ'], ['attachments','ไฟล์แนบ'], ['leave','การลา'], ['worktime','เวลาทำงาน'], ['health','สุขภาพ'],
  ['honors','เครื่องราชอิสริยาภรณ์'], ['welfare','สวัสดิการ'], ['awards','รางวัลและผลงาน'], ['training','ฝึกอบรม / สัมมนา / ประชุม'],
  ['talent','ความสามารถพิเศษ'], ['salary','เงินเดือน'], ['standing','วิทยฐานะ'],
] as const;
type Tab = (typeof TABS)[number][0];

const employment:Record<string,string> = { civil_servant:'ข้าราชการ', permanent:'พนักงานประจำ', contract:'พนักงานสัญญาจ้าง', part_time:'พนักงานพาร์ตไทม์', industry_expert:'ผู้เชี่ยวชาญจากสถานประกอบการ' };
const roleLabel:Record<string,string> = { registrar:'งานทะเบียน', academic:'วิชาการ', finance:'การเงิน', student_affairs:'กิจการนักศึกษา', director:'ผู้อำนวยการ', admin:'ผู้ดูแลระบบ' };
const TAB_HINT: Record<Tab, string> = { general:'ข้อมูลติดต่อ การจ้าง และสิทธิ์ผู้ใช้งาน', address:'ข้อมูลที่อยู่และการติดต่อของบุคลากร', education:'คุณวุฒิและประวัติการศึกษา', experience:'ประสบการณ์ทำงานและตำแหน่งที่ผ่านมา', license:'ข้อมูลใบอนุญาตประกอบวิชาชีพ', attachments:'เอกสารและไฟล์แนบ', leave:'ประวัติและรายการลา', worktime:'ข้อมูลเวลาปฏิบัติงาน', health:'ข้อมูลสุขภาพที่มีการควบคุมสิทธิ์', honors:'เครื่องราชอิสริยาภรณ์', welfare:'สิทธิและสวัสดิการ', awards:'รางวัลและผลงาน', training:'ประวัติอบรม สัมมนา และประชุม', talent:'ความสามารถพิเศษ', salary:'ข้อมูลเงินเดือน', standing:'ข้อมูลวิทยฐานะ' };
const TAB_GROUPS:{ title:string; keys:Tab[] }[] = [
  { title:'ข้อมูลหลัก', keys:['general', 'address', 'education', 'experience', 'license'] },
  { title:'งานบุคคล', keys:['leave', 'worktime', 'welfare', 'salary', 'standing'] },
  { title:'ประวัติและเอกสาร', keys:['training', 'awards', 'honors', 'talent', 'attachments', 'health'] },
];

export function PersonnelSearchScreen({ staffId }: { staffId?:string }) {
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=200'), []);
  const [keyword, setKeyword] = useState('');
  const visible = useMemo(() => (staff.data?.items ?? []).filter((s) => `${s.full_name} ${s.staff_code}`.toLocaleLowerCase().includes(keyword.trim().toLocaleLowerCase())), [staff.data, keyword]);

  return <><PageHead title="ค้นหาบุคลากร" sub="เลือกบุคลากรเพื่อเปิดแฟ้มประวัติและข้อมูลประกอบ" actions={<a href={href('/personnel-center')}>← ศูนย์งานบุคลากร</a>} />
    {staffId ? <section className="personnel-file"><div className="personnel-file-tools"><a href={href('/personnel-search')}>⌕ ค้นหาบุคลากรคนอื่น</a></div><PersonnelFile staffId={staffId} /></section> : <section className="personnel-search-dialog"><header><span className="personnel-search-icon">⌕</span><div><h3>ค้นหาบุคลากร</h3><p>พิมพ์ชื่อ–นามสกุล หรือรหัสบุคลากร แล้วเลือกรายการที่ต้องการ</p></div></header><div className="search-box"><input autoFocus value={keyword} onChange={(e) => setKeyword(e.target.value)} placeholder="เช่น สมชาย หรือ 6401001" aria-label="ค้นหาบุคลากร" /></div>{keyword.trim() && <AsyncView state={staff} empty="ยังไม่มีข้อมูลบุคลากร">{() => <div className="personnel-search-results">{visible.length === 0 ? <div className="empty">ไม่พบรายการที่ค้นหา</div> : visible.map((s) => <a key={s.id} href={href(`/personnel-search/${s.id}`)}><strong>{s.full_name}</strong><small>{s.staff_code} · {s.is_teacher ? 'ครูผู้สอน' : 'บุคลากร'} · {s.active ? 'ปฏิบัติงาน' : 'พ้นสภาพ'}</small><span>›</span></a>)}</div>}</AsyncView>}</section>}</>;
}

function PersonnelFile({ staffId }: { staffId:string }) {
  const detail = useAsync(() => api.get<StaffDetail>(`/staff/${staffId}`), [staffId]);
  const records = useAsync(() => api.get<RecordGroups>(`/hr/staff/${staffId}/records`), [staffId]);
  const [tab, setTab] = useState<Tab>('general');
  return <AsyncView state={detail}>{(d) => <><div className="personnel-file-head"><div className="personnel-photo" aria-label="รูปบุคลากร">{initials(d.full_name)}</div><div><p>แฟ้มประวัติบุคลากร</p><h3>{d.full_name}</h3><p>รหัสบุคลากร {d.staff_code} · {d.is_teacher ? 'ครูผู้สอน' : 'บุคลากรสนับสนุน'}</p></div><Badge kind={d.active ? 'ok' : 'default'}>{d.active ? 'ปฏิบัติงาน' : 'พ้นสภาพ'}</Badge></div><div className="personnel-workspace"><aside className="personnel-record-nav"><div className="personnel-record-nav-title"><b>หมวดข้อมูล</b><span>เลือกหัวข้อเพื่อดูหรือแก้ไข</span></div>{TAB_GROUPS.map((group) => <div className="personnel-record-nav-group" key={group.title}><span>{group.title}</span>{group.keys.map((key) => { const label = TABS.find(([tabKey]) => tabKey === key)?.[1] ?? key; const badge = key === 'training' ? records.data?.training.length : key === 'awards' ? records.data?.award.length : key === 'education' ? records.data?.education.length : undefined; return <button key={key} className={tab === key ? 'active' : ''} onClick={() => setTab(key)}><i>{tab === key ? '●' : '○'}</i><b>{label}</b>{badge ? <em>{badge}</em> : null}</button>; })}</div>)}</aside><section className="personnel-content"><div className="personnel-content-head"><span>แฟ้มประวัติบุคลากร</span><h3>{TABS.find(([key]) => key === tab)?.[1]}</h3><p>{TAB_HINT[tab]}</p></div><TabContent tab={tab} detail={d} records={records.data ?? undefined} onSaved={() => detail.reload()} /></section></div></>}</AsyncView>;
}

function TabContent({ tab, detail, records, onSaved }: { tab:Tab; detail:StaffDetail; records:RecordGroups|undefined; onSaved:()=>void }) {
  if (tab === 'general') return <ProfileEditor detail={detail} onSaved={onSaved} />;
  if (tab === 'license') return <ProfileEditor detail={detail} onSaved={onSaved} licenseOnly />;
  const recordKind:Partial<Record<Tab, keyof Omit<RecordGroups,'trainingHours'>>> = { education:'education', experience:'experience', training:'training', awards:'award' };
  const kind = recordKind[tab];
  if (kind) { const rows = records?.[kind] ?? []; return <><h4>{TABS.find(([key]) => key === tab)?.[1]}</h4>{rows.length ? <div className="scroll-x"><table><thead><tr><th>รายการ</th><th>หน่วยงาน</th><th>สาขา/รายละเอียด</th><th>ช่วงเวลา</th><th className="num">ชั่วโมง</th></tr></thead><tbody>{rows.map((r) => <tr key={r.id}><td>{r.title_th}</td><td>{r.organization_th ?? '—'}</td><td>{r.field_th ?? '—'}</td><td>{r.started_on ? thaiDate(r.started_on) : '—'}{r.ended_on ? ` – ${thaiDate(r.ended_on)}` : ''}</td><td className="num">{r.hours ?? '—'}</td></tr>)}</tbody></table></div> : <Empty label={TABS.find(([key]) => key === tab)?.[1] ?? ''} />}</>; }
  const sensitive = tab === 'health';
  return <><h4>{TABS.find(([key]) => key === tab)?.[1]}</h4><div className="personnel-empty">{sensitive ? 'ข้อมูลสุขภาพเป็นข้อมูลอ่อนไหวตาม PDPA และยังไม่ได้เปิดใช้งานในแฟ้มบุคลากรหน้านี้' : `ยังไม่มีข้อมูล${TABS.find(([key]) => key === tab)?.[1] ?? ''}ของบุคลากรรายนี้`}</div></>;
}

function ProfileEditor({ detail, onSaved, licenseOnly = false }: { detail:StaffDetail; onSaved:()=>void; licenseOnly?:boolean }) {
  const [editing, setEditing] = useState(false);
  const [phone, setPhone] = useState(detail.phone ?? ''); const [email, setEmail] = useState(detail.email ?? '');
  const [employmentKind, setEmploymentKind] = useState(detail.employment_kind); const [isTeacher, setIsTeacher] = useState(detail.is_teacher); const [active, setActive] = useState(detail.active);
  const [licenseNo, setLicenseNo] = useState(detail.license_no ?? ''); const [licenseExpires, setLicenseExpires] = useState(detail.license_expires ?? '');
  const save = () => api.patch(`/staff/${detail.id}/profile`, { phone, email, employmentKind, isTeacher, active, licenseNo, licenseExpires: licenseExpires || null });
  if (!editing) return <><div className="personnel-section-heading"><h4>{licenseOnly ? 'ใบประกอบวิชาชีพ' : 'ข้อมูลผู้ใช้ระบบ'}</h4><button onClick={() => setEditing(true)}>แก้ไขข้อมูล</button></div>{licenseOnly ? <Fields rows={[["เลขที่ใบอนุญาต",detail.license_no],["วันหมดอายุ",detail.license_expires ? thaiDate(detail.license_expires) : null]]} empty="ยังไม่ได้ระบุข้อมูลใบประกอบวิชาชีพ" /> : <Fields rows={[["ชื่อ–นามสกุล",detail.full_name],["รหัสบุคลากร",detail.staff_code],["ประเภทการจ้าง",employment[detail.employment_kind] ?? detail.employment_kind],["สถานะ",detail.active ? 'ปฏิบัติงาน' : 'พ้นสภาพ'],["โทรศัพท์",detail.phone],["อีเมล",detail.email],["บทบาทในระบบ",detail.roles.filter((r) => r.active_now).map((r) => roleLabel[r.role] ?? r.role).join(', ') || 'ยังไม่ได้กำหนด'],["สถานะผู้สอน",detail.is_teacher ? 'เป็นครูผู้สอน' : 'ไม่ใช่ครูผู้สอน']]} />}</>;
  return <><div className="personnel-section-heading"><h4>{licenseOnly ? 'แก้ไขใบประกอบวิชาชีพ' : 'แก้ไขข้อมูลผู้ใช้ระบบ'}</h4><button onClick={() => setEditing(false)}>ยกเลิก</button></div><div className="personnel-edit-fields">{!licenseOnly && <><label>โทรศัพท์<input value={phone} onChange={(e) => setPhone(e.target.value)} /></label><label>อีเมล<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></label><label>ประเภทการจ้าง<select value={employmentKind} onChange={(e) => setEmploymentKind(e.target.value)}>{Object.entries(employment).map(([value,label]) => <option key={value} value={value}>{label}</option>)}</select></label><label>สถานะผู้สอน<select value={String(isTeacher)} onChange={(e) => setIsTeacher(e.target.value === 'true')}><option value="true">เป็นครูผู้สอน</option><option value="false">ไม่ใช่ครูผู้สอน</option></select></label><label>สถานะการทำงาน<select value={String(active)} onChange={(e) => setActive(e.target.value === 'true')}><option value="true">ปฏิบัติงาน</option><option value="false">พ้นสภาพ</option></select></label></>}<label>เลขที่ใบประกอบวิชาชีพ<input value={licenseNo} onChange={(e) => setLicenseNo(e.target.value)} /></label><label>วันหมดอายุ<input type="date" value={licenseExpires} onChange={(e) => setLicenseExpires(e.target.value)} /></label></div><div className="personnel-edit-actions"><ActionButton className="primary" onRun={save} onDone={() => { setEditing(false); onSaved(); }}>บันทึกข้อมูล</ActionButton></div></>;
}

function Fields({ rows, empty }: { rows:[string,string|null|undefined][]; empty?:string }) { const has = rows.some(([,v]) => Boolean(v)); return has ? <div className="personnel-fields">{rows.map(([label,value]) => <div key={label}><span>{label}</span><b>{value || '—'}</b></div>)}</div> : <div className="personnel-empty">{empty ?? 'ยังไม่มีข้อมูล'}</div>; }
function Empty({ label }: { label:string }) { return <div className="personnel-empty">ยังไม่มีข้อมูล{label}ของบุคลากรรายนี้</div>; }
function initials(name:string) { return name.trim().split(/\s+/).slice(0,2).map((x) => x[0] ?? '').join(''); }

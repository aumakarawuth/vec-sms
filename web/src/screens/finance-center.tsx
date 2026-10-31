import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key:string; title:string; desc:string; path?:string; state:State };
const i = (key:string, title:string, desc:string, path?:string, state:State = 'planned'):Item => ({ key, title, desc, path, state });

/** หนึ่งหน้าจอจริงมีการ์ดเดียว — เดิมมียี่สิบการ์ดตามเมนู SISA แต่สิบหกใบชี้ไป /finance
 * หน้าเดียวกัน (ดูเหมือนเมนูซ้ำ) และอีกสี่ใบเปิดได้แค่หน้าว่าง หลักเดียวกับ behavior-center
 * งานที่ยังไม่มีหน้าจอจริง (ปิดเงินรายวัน · แบบฟอร์มชำระผ่านธนาคาร · บัญชีรายจ่าย)
 * ไม่ทำเป็นการ์ด เพราะการ์ดที่กดแล้วว่างทำให้ผู้ใช้สรุปว่าระบบเสีย */
const GROUPS = [
  { title:'งานการเงิน', subtitle:'รับเงิน ตั้งค่าค่าเทอม กระทบยอด และรายงานในหน้าเดียว', items:[
    i('finance','การเงินนักศึกษา','เลือกนักศึกษา ดูยอดค้าง ออกใบแจ้งหนี้ รับชำระ พิมพ์ใบเสร็จ มอบส่วนลด · ตั้งรายการค่าธรรมเนียมและโครงสร้างค่าเทอม · นโยบายค้างชำระ · นำเข้าและกระทบยอดธนาคาร · รายงานรายรับ','/finance','ready'),
  ] },
  { title:'งานที่เกี่ยวข้อง', subtitle:'หน้าจออื่นที่ใช้ข้อมูลการเงิน', items:[
    i('graduation','ตรวจสอบก่อนจบการศึกษา','ดูยอดค้างชำระประกอบการอนุมัติจบ','/graduation','ready'),
  ] },
];
const STATUS = { ready:{ label:'พร้อมใช้งาน', kind:'ok' }, partial:{ label:'ใช้งานได้บางส่วน', kind:'warn' }, planned:{ label:'หน้าต้นแบบ', kind:'info' } } as const;

export function FinanceCenterScreen() {
  const selected = useRoute().query.get('module'); const all = GROUPS.flatMap((g) => g.items); const chosen = all.find((x) => x.key === selected);
  if (chosen && !chosen.path) return <Preview item={chosen} />;
  return <><PageHead title="ศูนย์การเงิน" sub="รับชำระเงิน รายงาน และการตั้งค่าในจุดเดียว" /><div className="registry-summary"><Stat title="ฟังก์ชันทั้งหมด" value={all.length} note="งานรับเงิน รายงาน และการตั้งค่า" tone="primary" /><Stat title="พร้อมใช้งาน" value={all.filter((x) => x.state === 'ready').length} note="เปิดใช้งานได้ทันที" tone="success" /><Stat title="กำลังเติมเต็ม" value={all.filter((x) => x.state !== 'ready').length} note="บางส่วนและหน้าต้นแบบ" tone="warning" /></div>{GROUPS.map((group) => <section className="registry-section" key={group.title}><div className="registry-section-head"><div><span>{group.subtitle}</span><h3>{group.title}</h3></div><b>{group.items.length} เมนู</b></div><div className="operation-grid">{group.items.map((x) => { const status = STATUS[x.state]; return <a className="operation-card" href={href(x.path ?? `/finance-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path ? '↗' : '◇'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={status.kind}>{status.label}</Badge></div><span className="operation-arrow">›</span></a>; })}</div></section>)}</>;
}
function Stat({ title, value, note, tone }: { title:string; value:number; note:string; tone:string }) { return <div className={`registry-stat ${tone}`}><span>{title}</span><strong>{value}</strong><small>{note}</small></div>; }
function Preview({ item }: { item:Item }) { return <><PageHead title={item.title} sub="โครงหน้าจอการเงิน" actions={<a href={href('/finance-center')}>← ศูนย์การเงิน</a>} /><Notice kind="info">เมนูนี้เตรียมโครงหน้าจอไว้แล้ว และจะเชื่อมข้อมูลจริงในขั้นถัดไป</Notice><Card title={item.title}><p className="hint">{item.desc}</p></Card></>; }

/** รายการเมนูย่อยให้แถบซ้ายแสดงใต้ศูนย์นี้ — อ่านจากการ์ดชุดเดียวกันจึงไม่เพี้ยนจากกัน */
export const SUBNAV = GROUPS.flatMap((g) => g.items.map((x) => ({ ...x, group: g.title }))).filter((x) => x.path).map((x) => ({ path: x.path!, label: x.title, group: x.group }));

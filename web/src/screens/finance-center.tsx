import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key:string; title:string; desc:string; path?:string; state:State };
const i = (key:string, title:string, desc:string, path?:string, state:State = 'planned'):Item => ({ key, title, desc, path, state });

/** หนึ่งการ์ดต่อหนึ่งหน้า — /finance แยกเป็นหน้าละงานแล้ว (FINANCE_SECTIONS)
 * แบบเดียวกับ SISA ที่หนึ่งเมนูตอบหนึ่งคำถาม งานที่ยังไม่มีหน้าจอจริง
 * (ปิดเงินรายวัน · ใบนำฝากธนาคาร · รับชำระทั้งห้อง) ไม่ทำเป็นการ์ด เพราะการ์ด
 * ที่กดแล้วว่างทำให้ผู้ใช้สรุปว่าระบบเสีย — ดู docs/sisa-function-audit */
const GROUPS = [
  { title:'รับชำระเงิน', subtitle:'งานหน้าเคาน์เตอร์', items:[
    i('payments','รับชำระเงิน','เลือกนักศึกษา ดูยอดค้าง ออกใบแจ้งหนี้ และรับชำระ','/finance/payments','ready'),
    i('receipts','ใบเสร็จรับเงิน','ค้นใบเสร็จทั้งวิทยาลัยตามวันที่ เลขที่ หรือนักศึกษา แล้วพิมพ์ซ้ำ','/finance/receipts','ready'),
    i('bank','นำเข้าและกระทบยอดธนาคาร','นำเข้ารายการเดินบัญชี และจับคู่กับนักศึกษา','/finance/bank','ready'),
  ] },
  { title:'รายงาน', subtitle:'สรุปรายรับและติดตามหนี้', items:[
    i('revenue','รายงานรายรับ','ปิดยอดตามผู้รับเงิน และยอดที่กระทบยอดแล้วแยกช่องทาง','/finance/revenue','ready'),
    i('arrears','ค้างชำระและระงับสิทธิ์','การชำระแยกห้อง รายชื่อค้างชำระ อายุหนี้ และการระงับสิทธิ์','/finance/arrears','ready'),
  ] },
  { title:'การตั้งค่า', subtitle:'โครงสร้างค่าธรรมเนียมและส่วนลด', items:[
    i('fees','ตั้งค่าค่าธรรมเนียม','รายการค่าธรรมเนียม โครงสร้างค่าเทอม และค่าเรียนซ่อม','/finance/fees','ready'),
    i('discounts','ทุนและส่วนลด','รายงานผู้ได้รับทุน แหล่งทุน และส่วนลดรายคน','/finance/discounts','ready'),
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

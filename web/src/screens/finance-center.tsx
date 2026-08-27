import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key:string; title:string; desc:string; path?:string; state:State };
const i = (key:string, title:string, desc:string, path?:string, state:State = 'planned'):Item => ({ key, title, desc, path, state });

const GROUPS = [
  { title:'รับชำระเงิน', subtitle:'ใบแจ้งหนี้ รับเงิน และกระทบยอด', items:[
    i('payments','รับชำระเงินนักศึกษา','เลือกนักศึกษา ตรวจยอดค้าง และบันทึกการรับชำระ','/finance','ready'),
    i('payment-items','จัดการระบบรับชำระเงิน','ออกใบแจ้งหนี้ จัดงวด และดูใบเสร็จของนักศึกษา','/finance','ready'),
    i('additional','รับชำระเงิน (เพิ่มเติม)','รับรายการค่าใช้จ่ายหรือการชำระเพิ่มเติม','/finance','partial'),
    i('pending','กองทุนที่ค้างชำระ','ติดตามยอดกองทุนและรายการที่ยังไม่ตัดชำระ','/finance','partial'),
    i('check','ตรวจสอบการชำระเงินของนักศึกษา','ตรวจยอดเรียกเก็บ ชำระแล้ว และยอดค้าง','/finance','ready'),
    i('bank-import','นำเข้าข้อมูลจากธนาคาร','นำเข้ารายการเดินบัญชีและกระทบยอดอัตโนมัติ','/finance','ready'),
  ] },
  { title:'รายงาน', subtitle:'สรุปรายรับ การชำระ และรายการติดตาม', items:[
    i('income','รายงานรายรับ','สรุปรายรับตามช่วงเวลาและช่องทางการชำระ','/finance','partial'),
    i('payment-summary','สรุปการชำระเงิน','ภาพรวมการชำระเงินและยอดคงค้าง','/finance','partial'),
    i('fee-list','การคิดบัญชีรายจ่าย','ข้อมูลรายการค่าใช้จ่ายและการตั้งยอด'),
    i('unpaid-check','ตรวจสอบสถานะใบเสร็จรับเงิน','ตรวจใบเสร็จ การยกเลิก และการพิมพ์ซ้ำ','/finance','ready'),
    i('overdue','รายงานนักศึกษาค้างชำระ','ติดตามลูกหนี้ตามอายุหนี้และสถานะระงับสิทธิ์','/finance','ready'),
    i('cash-report','รายงานปิดเงินรายได้รายวัน','สรุปการรับเงินและการปิดยอดประจำวัน'),
    i('receipt-print','การพิมพ์ใบเสร็จย้อนหลัง','ค้นหาและพิมพ์ใบเสร็จที่ออกแล้ว','/finance','ready'),
    i('bank-form','แบบฟอร์มชำระเงินผ่านธนาคาร','สร้างเอกสารหรือแบบฟอร์มสำหรับชำระผ่านธนาคาร'),
  ] },
  { title:'การตั้งค่า', subtitle:'โครงสร้างค่าธรรมเนียมและเงื่อนไขการเรียกเก็บ', items:[
    i('initial','ตั้งค่าการชำระเงินเริ่มต้น','กำหนดค่าตั้งต้นและรอบการเรียกเก็บ','/finance','partial'),
    i('extra-fee','กำหนดรายการชำระเงินค่าเรียนเสริม','ตั้งรายการค่าธรรมเนียมเพิ่มเติม','/finance','ready'),
    i('fee-schedule','กำหนดรายการชำระเงินค่าเรียน','จัดโครงสร้างค่าเทอมตามระดับ ชั้นปี และสาขา','/finance','ready'),
    i('level-fee','กำหนดรายการชำระเงินตามระดับชั้น','ตั้งราคาตามระดับและชั้นปี','/finance','partial'),
    i('template','กำหนดรายการชำระเงินโดยสร้างต้นแบบ','สร้างแบบต้นแบบเพื่อใช้กับหลายหลักสูตร','/finance','partial'),
    i('discount','ตั้งบัญชีลดหนี้','ตั้งทุน ส่วนลด และแหล่งสนับสนุนการศึกษา','/finance','ready'),
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

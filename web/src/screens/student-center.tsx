import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key:string; title:string; desc:string; path?:string; state:State };
const item = (key:string, title:string, desc:string, path?:string, state:State = 'planned'):Item => ({ key, title, desc, path, state });

const GROUPS = [
  { title:'ข้อมูลนักศึกษา', subtitle:'ประวัติ การจัดชั้นเรียน และการดูแลผู้เรียน', items:[
    item('student-search','ค้นหานักศึกษา','ค้นหาจากชื่อ รหัสนักศึกษา หรือสถานะ แล้วเปิดแฟ้มประวัติ','/students','ready'),
    item('classroom','จัดห้องเรียน','ค้นหา เลือก และจัดนักศึกษาเข้าชั้นปีและห้องเรียน','/academic-year/placements','ready'),
    item('fee','การเงินนักศึกษา','ติดตามใบแจ้งหนี้ การชำระเงิน และส่วนลด','/finance/payments','ready'),
    item('import','นำเข้าข้อมูล','นำเข้าข้อมูลนักศึกษาจากไฟล์พร้อมตรวจสอบก่อนบันทึก','/import','ready'),
    item('leave','การลา','รับคำขอและพิจารณาการลาของนักศึกษา','/leaves','ready'),
    item('assessment','การประเมิน','บันทึกผลการประเมินและพฤติกรรมนักศึกษา','/behavior','partial'),
  ] },
  { title:'รายงาน', subtitle:'เวลาเรียน ผลการศึกษา และข้อมูลเพื่อการติดตาม', items:[
    item('study-check','ตรวจสอบข้อมูลจบการศึกษา','ตรวจความครบถ้วนของผลการเรียนก่อนจบการศึกษา','/graduation','ready'),
    item('pr','การประชาสัมพันธ์','จัดทำประกาศและข่าวสารสำหรับนักศึกษา — ตั้งเวลาเผยแพร่ได้','/announcements','ready'),
    item('attendance-report','รายงานการเข้าเรียน','ตรวจและสรุปการเข้าเรียนรายคาบ','/attendance','ready'),
    item('student-breakdown','สถิตินักศึกษาแยกตามหัวข้อ','ห้อง สาขา เพศ อายุ สัญชาติ จังหวัด พาหนะ อาชีพและรายได้ผู้ปกครอง สถานศึกษาเดิม แยกตามชั้นปี','/statistics/students','ready'),
    item('student-report','รายงานข้อมูลนักศึกษา','รายงานรายชื่อ สถานะ และข้อมูลพื้นฐานของนักศึกษา','/statistics','partial'),
    item('exam','ตรวจสอบข้อสอบ','ตรวจตารางสอบและการจัดสอบของนักศึกษา','/exam-schedule','partial'),
  ] },
  { title:'การตั้งค่า', subtitle:'ข้อมูลประกอบและค่าเริ่มต้นสำหรับงานนักศึกษา', items:[
    item('old-grade','คีย์เก่า','บันทึกหรือทบทวนผลการเรียนเดิม','/gradebook','partial'),
  ] },
];

const STATUS = { ready:{ label:'พร้อมใช้งาน', kind:'ok' }, partial:{ label:'ใช้งานได้บางส่วน', kind:'warn' }, planned:{ label:'หน้าต้นแบบ', kind:'info' } } as const;

export function StudentCenterScreen() {
  const selected = useRoute().query.get('module');
  const all = GROUPS.flatMap((g) => g.items);
  const chosen = all.find((x) => x.key === selected);
  if (chosen && !chosen.path) return <Preview item={chosen} />;
  return <><PageHead title="ศูนย์นักศึกษา" sub="ข้อมูลนักศึกษา รายงาน และการตั้งค่าในจุดเดียว" />
    <div className="registry-summary"><Stat title="ฟังก์ชันทั้งหมด" value={all.length} note="จัดกลุ่มตามงานในศูนย์นักศึกษา" tone="primary" /><Stat title="พร้อมใช้งาน" value={all.filter((x) => x.state === 'ready').length} note="เปิดใช้งานจากเมนูได้ทันที" tone="success" /><Stat title="กำลังเติมเต็ม" value={all.filter((x) => x.state !== 'ready').length} note="บางส่วนและหน้าต้นแบบ" tone="warning" /></div>
    {GROUPS.map((g) => <section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map((x) => { const status = STATUS[x.state]; return <a className="operation-card" href={href(x.path ?? `/student-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path ? '↗' : '◇'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={status.kind}>{status.label}</Badge></div><span className="operation-arrow">›</span></a>; })}</div></section>)}</>;
}

function Stat({ title, value, note, tone }: { title:string; value:number; note:string; tone:string }) { return <div className={`registry-stat ${tone}`}><span>{title}</span><strong>{value}</strong><small>{note}</small></div>; }
function Preview({ item }: { item:Item }) { return <><PageHead title={item.title} sub="โครงหน้าจอสำหรับเชื่อมข้อมูลนักศึกษา" actions={<a href={href('/student-center')}>← กลับ</a>} /><Notice kind="info">เมนูนี้เตรียมโครงหน้าจอไว้แล้ว และจะเชื่อมข้อมูลจริงในขั้นถัดไป</Notice><Card title={item.title}><p className="hint">{item.desc}</p></Card></>; }

/** รายการเมนูย่อยให้แถบซ้ายแสดงใต้ศูนย์นี้ — อ่านจากการ์ดชุดเดียวกันจึงไม่เพี้ยนจากกัน */
export const SUBNAV = GROUPS.flatMap((g) => g.items.map((x) => ({ ...x, group: g.title }))).filter((x) => x.path).map((x) => ({ path: x.path!, label: x.title, group: x.group }));

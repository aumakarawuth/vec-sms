import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key:string; title:string; desc:string; path?:string; state:State };
const item = (key:string, title:string, desc:string, path?:string, state:State = 'planned'):Item => ({ key, title, desc, path, state });

const GROUPS = [
  { title:'ข้อมูลนักศึกษา', subtitle:'ประวัติ การจัดชั้นเรียน และการดูแลผู้เรียน', items:[
    item('student-search','ค้นหานักศึกษา','ค้นหาจากชื่อ รหัสนักศึกษา หรือสถานะ แล้วเปิดแฟ้มประวัติ','/students','ready'),
    item('classroom','จัดห้องเรียน','ค้นหา เลือก และจัดนักศึกษาเข้าชั้นปีและห้องเรียน','/academic-year/placements','ready'),
    item('placement','เปลี่ยนตำแหน่งห้อง','ย้ายห้องหรือจัดนักศึกษาเข้าห้องเรียน','/academic-year/placements','ready'),
    item('fee','การเงินนักศึกษา','ติดตามใบแจ้งหนี้ การชำระเงิน และส่วนลด','/finance','ready'),
    item('import','นำเข้าข้อมูล','นำเข้าข้อมูลนักศึกษาจากไฟล์พร้อมตรวจสอบก่อนบันทึก','/import','ready'),
    item('photo','แสดงรูปภาพนักเรียน','รวมรูปภาพและข้อมูลติดต่อของนักศึกษา'),
    item('graduation-photo','แสดงรูปภาพนักเรียนชุดครุยรับปริญญา','จัดเก็บและแสดงรูปสำหรับพิธีสำเร็จการศึกษา'),
    item('health','สุขภาพ','ข้อมูลสุขภาพและข้อควรระวังในการดูแลนักศึกษา — อยู่ในแฟ้มนักศึกษารายคน แท็บ "สุขภาพ"','/students','ready'),
    item('leave','การลา','รับคำขอและพิจารณาการลาของนักศึกษา','/leaves','ready'),
    item('assessment','การประเมิน','บันทึกผลการประเมินและพฤติกรรมนักศึกษา','/behavior','partial'),
    item('guardian','ข้อมูลผู้ปกครอง','ข้อมูลผู้ปกครองและช่องทางติดต่อ — อยู่ในแฟ้มนักศึกษารายคน แท็บ "ผู้ปกครอง"','/students','ready'),
    item('status-reason','กำหนดรหัสการรับเข้าออก','เหตุที่พ้นสภาพ/กลับเข้าเรียน พร้อมเลขที่คำสั่ง — อยู่ในแฟ้มนักศึกษารายคน แท็บ "สถานะ"','/students','ready'),
  ] },
  { title:'รายงาน', subtitle:'เวลาเรียน ผลการศึกษา และข้อมูลเพื่อการติดตาม', items:[
    item('study-check','ตรวจสอบข้อมูลจบการศึกษา','ตรวจความครบถ้วนของผลการเรียนก่อนจบการศึกษา','/graduation','ready'),
    item('pr','การประชาสัมพันธ์','จัดทำประกาศและข่าวสารสำหรับนักศึกษา — ตั้งเวลาเผยแพร่ได้','/announcements','ready'),
    item('scholarship','ทุนการศึกษา','ติดตามทุน ส่วนลด และสวัสดิการนักศึกษา','/finance','partial'),
    item('attendance-report','รายงานการเข้าเรียน','ตรวจและสรุปการเข้าเรียนรายคาบ','/attendance','ready'),
    item('student-report','รายงานข้อมูลนักศึกษา','รายงานรายชื่อ สถานะ และข้อมูลพื้นฐานของนักศึกษา','/statistics','partial'),
    item('exam','ตรวจสอบข้อสอบ','ตรวจตารางสอบและการจัดสอบของนักศึกษา','/exam-schedule','partial'),
    item('directory','ไปรษณีย์','จัดการข้อมูลไปรษณีย์และเอกสารติดต่อ — เป็นระบบเดียวกับ "การประชาสัมพันธ์"','/announcements','ready'),
    item('address','ที่อยู่','ที่อยู่และข้อมูลการติดต่อของนักศึกษา — อยู่ในแฟ้มนักศึกษารายคน แท็บ "ที่อยู่"','/students','ready'),
    item('achievement','ข้อมูลผลงานและเกียรติประวัติ','รางวัลและผลงานของนักศึกษา — อยู่ในแฟ้มนักศึกษารายคน แท็บ "ผลงาน/เกียรติประวัติ"','/students','ready'),
    item('student-statistics','ข้อมูลสถิติ','ภาพรวมนักศึกษาและตัวชี้วัดสำคัญ','/statistics','ready'),
  ] },
  { title:'การตั้งค่า', subtitle:'ข้อมูลประกอบและค่าเริ่มต้นสำหรับงานนักศึกษา', items:[
    item('student-photo','รับรูปนักศึกษา','จับคู่ไฟล์รูปด้วยรหัสนักศึกษา'),
    item('health-setup','สุขภาพ','ตั้งค่าข้อมูลสุขภาพที่ใช้ในการดูแลนักศึกษา'),
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

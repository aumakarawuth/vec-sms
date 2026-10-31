import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key: string; title: string; description: string; path?: string; state: State };
type Group = { title: string; subtitle: string; items: Item[] };

const GROUPS: Group[] = [
  { title: 'ข้อมูลและการลงทะเบียน', subtitle: 'เริ่มจากข้อมูลนักศึกษา แล้วจัดห้องและลงทะเบียนรายวิชา', items: [
    ['students','ระเบียนนักศึกษา','ค้นหา ดู และแก้ไขแฟ้มข้อมูลนักศึกษาในหน้าเดียว','/students','ready'],
    ['registration','ข้อมูลลงทะเบียนและลงทะเบียนเรียน','ลงทะเบียนทั้งห้องหรือรายคน พร้อมตรวจรายชื่อและรายวิชา','/registration','ready'],
    ['academic-year','จัดการปีการศึกษาและระดับชั้น','เปิดปีการศึกษา ตั้งภาคเรียน เลื่อนชั้น และติดตามผู้มีสิทธิ์','/academic-year','ready'],
    ['classroom','จัดห้องเรียนและรีเลขที่','จัดห้องประจำชั้น กำหนดห้อง และจัดเลขที่ในห้องใหม่','/academic-year/classes','ready'],
    ['admissions','รับสมัครและโควตา','เปิดรอบรับสมัคร กำหนดโควตา ตัดสินผล และขึ้นทะเบียนนักศึกษา','/admissions','ready'],
    ['dual','ทวิภาคีและสถานประกอบการ','ดูแลสถานประกอบการ การฝึกงาน และชั่วโมงทวิภาคี','/dual','ready'],
  ].map(([key,title,description,path,state]) => ({ key,title,description,path,state } as Item)) },
  { title: 'ผลการเรียนและกิจกรรม', subtitle: 'บันทึกคะแนน เวลาเรียน กิจกรรม และติดตามความก้าวหน้าทางการเรียน', items: [
    ['gradebook','ผลการเรียน · สมุดคะแนน · อนุมัติเกรด','บันทึกคะแนน ตรวจผล ส่งผล และอนุมัติเกรดตามลำดับงานเดียวกัน','/gradebook','ready'],
    ['change-requests','คำร้องขอแก้เกรด','ยื่น ตรวจสอบ และอนุมัติการแก้ไขผลการเรียนที่ล็อกแล้ว','/change-requests','ready'],
    ['attendance','เวลาเรียนและเช็คชื่อรายคาบ','เปิดคาบเรียน บันทึกการเข้าเรียน และติดตามเวลาเรียน','/attendance','ready'],
    ['timetable','ตารางเรียนและตารางสอบ','จัดตารางเรียน จัดห้องสอบ และตรวจความขัดแย้งของตาราง','/timetable-center','ready'],
    ['clubs','จัดการวิชาชุมนุม/ชมรม','ตั้งชมรม ผู้ดูแล และสมาชิกแยกตามปีการศึกษา','/clubs','ready'],
    ['onet','ผลสอบ O-NET','บันทึกผลสอบและดูสรุปคะแนนเฉลี่ยรายวิชา','/onet','ready'],
    ['graduation','ตรวจสอบข้อมูลจบการศึกษา','ตรวจเกณฑ์จบ อนุมัติจบ และติดตามการมีงานทำหรือศึกษาต่อ','/graduation','ready'],
  ].map(([key,title,description,path,state]) => ({ key,title,description,path,state } as Item)) },
  { title: 'รายงานและเอกสาร', subtitle: 'พิมพ์เอกสารทะเบียน ดูรายงาน และส่งข้อมูลให้หน่วยงานภายนอก', items: [
    ['documents','เอกสารนักศึกษาและใบรับรอง','พิมพ์ใบลงทะเบียน ใบ รบ./Transcript สมุดพก และใบรับรอง','/documents','ready'],
    ['grade-reports','รายงานผลการเรียน','ดูผลการเรียนตามภาคเรียน/ปีการศึกษา/ทุกภาคเรียน และรายชื่อผู้ไม่ผ่านเกณฑ์','/grade-reports','ready'],
    ['letters','หนังสือและแบบฟอร์ม','จัดทำหนังสือถึงผู้ปกครองและเอกสารงานทะเบียน','/letters','ready'],
    ['government-exports','รายงานและข้อมูลส่งออกภาครัฐ','ส่งออกข้อมูลนักเรียน ผลการเรียน และข้อมูลตามรูปแบบหน่วยงานรัฐ','/government-exports','ready'],
    ['statistics','รายงานสถิติ','ดูภาพรวมผู้เรียน ผลการเรียน และตัวชี้วัดของวิทยาลัย','/statistics','ready'],
    ['import','นำเข้าข้อมูลผลการเรียน','ตรวจไฟล์ก่อนนำเข้า และบันทึกผลการเรียนอย่างเป็นขั้นตอน','/import','ready'],
  ].map(([key,title,description,path,state]) => ({ key,title,description,path,state } as Item)) },
  { title: 'ตั้งค่างานทะเบียน', subtitle: 'กำหนดโครงสร้างก่อนเริ่มใช้งานในแต่ละปีการศึกษา', items: [
    ['education-levels','ระดับชั้นและวุฒิการศึกษา','กำหนดระดับการศึกษา ชั้นปี และคำเรียกที่ใช้ในระบบ','/education-levels','ready'],
    ['curriculum','หลักสูตร · สาขา · วิชาเรียน','จัดโครงสร้างหลักสูตร สาขา วิชา และแผนการเรียน','/curriculum/programs','ready'],
    ['courses','ข้อมูลวิชา','จัดกลุ่มสาระ กลุ่มวิชา รายวิชา ระดับผลการเรียน และการประเมิน','/subject-data','ready'],
    ['curriculum-versions','รูปแบบโครงสร้างหลักสูตร','จัดการฉบับหลักสูตรและโครงสร้างรายวิชาแต่ละฉบับ','/curriculum/versions','ready'],
    ['term-categories','ช่วงเวลาและเงื่อนไขการเรียน','กำหนดช่วงลงทะเบียน สมุดคะแนน และวันสำคัญในภาคเรียน','/term-categories','ready'],
    ['grade-levels','รูปแบบเกรดและการประเมิน','ตั้งช่วงคะแนน ตัวอักษรเกรด และเงื่อนไขผลการเรียน','/grade-levels','ready'],
  ].map(([key,title,description,path,state]) => ({ key,title,description,path,state } as Item)) },
];

const STATUS = { ready: { label: 'พร้อมใช้งาน', kind: 'ok' }, partial: { label: 'ใช้งานได้บางส่วน', kind: 'warn' }, planned: { label: 'หน้าต้นแบบ', kind: 'info' } } as const;

export function RegistryCenterScreen() {
  const selected = useRoute().query.get('module');
  const item = GROUPS.flatMap((g) => g.items).find((x) => x.key === selected);
  if (item && !item.path) return <Preview item={item} />;
  const all = GROUPS.flatMap((g) => g.items);
  return <>
    <PageHead title="ศูนย์งานทะเบียน" sub="เมนูงานทะเบียน รายงาน และเอกสารครบในจุดเดียว" />
    <div className="registry-summary"><Stat title="ฟังก์ชันทั้งหมด" value={all.length} note="หนึ่งการ์ดต่อหนึ่งหน้าจอ" tone="primary"/><Stat title="พร้อมใช้งาน" value={all.filter(x=>x.state==='ready').length} note="เชื่อมหน้าจอแล้ว" tone="success"/><Stat title="กำลังเติมเต็ม" value={all.filter(x=>x.state!=='ready').length} note="บางส่วนและ Mockup" tone="warning"/></div>
    {GROUPS.map((group) => <section className="registry-section" key={group.title}><div className="registry-section-head"><div><span>{group.subtitle}</span><h3>{group.title}</h3></div><b>{group.items.length} เมนู</b></div><div className="operation-grid">{group.items.map((x) => { const s=STATUS[x.state]; return <a className="operation-card" href={href(x.path ?? `/registry?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.description}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>; })}</div></section>)}
  </>;
}

function Stat({title,value,note,tone}:{title:string;value:number;note:string;tone:string}) { return <div className={`registry-stat ${tone}`}><span>{title}</span><strong>{value}</strong><small>{note}</small></div>; }
function Preview({item}:{item:Item}) { return <><PageHead title={item.title} sub="โครงหน้าจอสำหรับเชื่อมข้อมูลภายหลัง" actions={<a href={href('/registry')}>← กลับ</a>}/><Notice kind="info">ยังไม่มี API เฉพาะ ข้อมูลในหน้านี้เป็น Mockup และไม่บันทึกลงฐานข้อมูล</Notice><div className="registry-summary"><Stat title="รายการทั้งหมด" value={24} note="ข้อมูลตัวอย่าง" tone="primary"/><Stat title="กำลังดำเนินการ" value={18} note="ภาคเรียนปัจจุบัน" tone="success"/><Stat title="รอตรวจสอบ" value={6} note="ต้องดำเนินการ" tone="warning"/></div><Card title={`ภาพรวม ${item.title}`}><div className="mock-chart">{[48,72,58,88,66,94].map((h)=><i key={h} style={{height:`${h}%`}}/>)}</div><p className="hint">{item.description} ตัวเลขและกราฟเป็นตัวอย่างเพื่อยืนยันรูปแบบก่อนพัฒนา API จริง</p></Card></>; }

/** รายการเมนูย่อยให้แถบซ้ายแสดงใต้ศูนย์นี้ — อ่านจากการ์ดชุดเดียวกันจึงไม่เพี้ยนจากกัน */
export const SUBNAV = GROUPS.flatMap((g) => g.items.map((x) => ({ ...x, group: g.title }))).filter((x) => x.path).map((x) => ({ path: x.path!, label: x.title, group: x.group }));

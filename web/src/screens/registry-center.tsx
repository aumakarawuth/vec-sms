import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key: string; title: string; description: string; path?: string; state: State };
type Group = { title: string; subtitle: string; items: Item[] };

const GROUPS: Group[] = [
  { title: 'งานทะเบียน', subtitle: 'ข้อมูลนักศึกษา การลงทะเบียน และงานวัดผล', items: [
    ['student-registration','ข้อมูลลงทะเบียนของนักศึกษา','ค้นหาและตรวจสอบระเบียน การเรียน และสถานะลงทะเบียน','/students','ready'],
    ['student-results','ผลการเรียนของนักศึกษา','ดูคะแนน ผลการเรียน และสรุปตามภาคเรียน','/students','ready'],
    ['grade-approval','อนุมัติเกรด','ตรวจผล ส่งผล และอนุมัติตามลำดับงาน','/gradebook','ready'],
    ['attendance-book','สมุดบันทึกเวลาเรียนสำหรับเจ้าหน้าที่','รายชื่อผู้เรียนและประวัติการเข้าเรียนรายคาบ','/attendance','ready'],
    ['courses','จัดการรายวิชา','รายวิชา โครงสร้างหลักสูตร และหน่วยกิต','/curriculum','ready'],
    ['clubs','จัดการวิชาชุมนุม/ชมรม','บันทึกชื่อชมรม ผู้ดูแล และสมาชิกรายปีการศึกษา','/clubs','ready'],
    ['onet','ผลสอบ O-NET','วางผลสอบจากตารางและดูสรุปคะแนนเฉลี่ยรายวิชา','/onet','ready'],
    ['teacher','ระบบสำหรับอาจารย์','สมุดคะแนน เช็กชื่อ และคำร้องแก้ผลการเรียน','/gradebook','ready'],
    ['quota','ระบบจัดการนักศึกษาโควตา','เปิดรอบ ตั้งโควตา รับใบสมัคร ตัดสินผล และขึ้นทะเบียนเป็นนักศึกษา','/admissions','ready'],
    ['checkin','ลงเวลาเข้าเรียน','เปิดรายคาบและบันทึกสถานะการเข้าเรียน','/attendance','ready'],
  ].map(([key,title,description,path,state]) => ({key,title,description,path,state} as Item)) },
  { title: 'รายงานและเอกสาร', subtitle: 'เอกสารทะเบียน รายงานผล และข้อมูลส่งออก', items: [
    ['registration-form','ใบลงทะเบียน','พิมพ์ใบลงทะเบียนจากข้อมูลนักศึกษา','/documents','ready'],
    ['roster','รายชื่อนักศึกษาที่ลงทะเบียนเรียน','รายชื่อแยกตามรายวิชาและกลุ่มเรียน','/registration','ready'],
    ['result-report','รายงานผลการเรียน','สรุปคะแนนและผลการเรียนรายวิชา','/gradebook','ready'],
    ['transcript','ระเบียนผลการเรียน','ออกใบ รบ. และ Transcript ไทย/อังกฤษ','/documents','ready'],
    ['graduation-survey','แบบสำรวจจบการศึกษา','สำรวจภาวะการมีงานทำ/ศึกษาต่อของผู้สำเร็จการศึกษา','/graduation','ready'],
    ['grade-report','สมุดพกนักเรียน','ออกใบแจ้งผลการเรียนรายภาค','/documents','ready'],
    ['certification','ใบรับรอง','ออกใบรับรองสถานภาพและการสำเร็จการศึกษา','/documents','ready'],
    ['government','ใบประกาศนียบัตรและรายงานหน่วยงานรัฐ','ออกเอกสารและส่งออกชุดข้อมูลภาครัฐ','/government-exports','ready'],
    ['gradebook-layout','โครงสร้างสมุดบันทึกคะแนน','หัวข้อคะแนน น้ำหนัก และคะแนนเต็ม','/gradebook','ready'],
    ['academic-data','ข้อมูลวิชาการ','ปีการศึกษา ภาคเรียน ห้อง และตารางสอน','/academic-year','ready'],
    ['grade-cutoff','รายงานตัดเกรด','ตัวอย่างผลและความคืบหน้าการตัดเกรด','/gradebook','ready'],
    ['statistics','ข้อมูลสถิติ','ภาพรวมนักศึกษา บุคลากร การเงิน และการเฝ้าระวังทั้งวิทยาลัย','/statistics','ready'],
  ].map(([key,title,description,path,state]) => ({key,title,description,path,state} as Item)) },
  { title: 'การตั้งค่า', subtitle: 'ข้อมูลพื้นฐาน โครงสร้างการเรียน และการนำเข้า', items: [
    ['master-data','ข้อมูลพื้นฐาน','โคลนฉบับหลักสูตรใหม่ ปรับโครงสร้าง และตั้งค่าที่กระจายตามโมดูล','/curriculum','ready'],
    ['classroom','ประเภท/สาขา/ชั้นเรียน/ห้องเรียน','เพิ่มห้องเรียน และจัดชั้นเรียนที่หน้างานวิชาการรายปี','/timetable','ready'],
    ['curriculum-layout','รูปแบบโครงสร้างหลักสูตร','รุ่นหลักสูตร หมวดวิชา และแผนการเรียน','/curriculum','ready'],
    ['term-courses','จัดวิชาเรียนแต่ละภาคเรียน','เปิดรายวิชาและจัดกลุ่มเรียนประจำภาค','/academic-year','ready'],
    ['class-enrollment','ลงวิชาเรียนแต่ละชั้นเรียน','ลงทะเบียนทั้งห้องหรือเลือกรายคน','/registration','ready'],
    ['grade-settings','สมุดคะแนนเก็บและระดับผลการเรียน','กำหนดหัวข้อคะแนนและตรวจผลก่อนส่ง','/gradebook','ready'],
    ['club-settings','วิชาชุมนุม/ชมรม','จัดการรายชื่อชมรมและผู้ดูแล','/clubs','ready'],
    ['result-import','นำเข้าข้อมูลผลการเรียน','นำเข้าประวัติการเรียนเดิมเป็นชุดจากไฟล์ CSV — ผูกกับนักศึกษาที่มีอยู่แล้วเท่านั้น','/import','ready'],
  ].map(([key,title,description,path,state]) => ({key,title,description,path,state} as Item)) },
];

const STATUS = { ready: { label: 'พร้อมใช้งาน', kind: 'ok' }, partial: { label: 'ใช้งานได้บางส่วน', kind: 'warn' }, planned: { label: 'หน้าต้นแบบ', kind: 'info' } } as const;

export function RegistryCenterScreen() {
  const selected = useRoute().query.get('module');
  const item = GROUPS.flatMap((g) => g.items).find((x) => x.key === selected);
  if (item && !item.path) return <Preview item={item} />;
  const all = GROUPS.flatMap((g) => g.items);
  return <>
    <PageHead title="ศูนย์งานทะเบียน" sub="เมนูงานทะเบียน รายงาน และการตั้งค่าครบในจุดเดียว" />
    <div className="registry-summary"><Stat title="ฟังก์ชันทั้งหมด" value={all.length} note="ตามระบบต้นแบบ" tone="primary"/><Stat title="พร้อมใช้งาน" value={all.filter(x=>x.state==='ready').length} note="เชื่อมหน้าจอแล้ว" tone="success"/><Stat title="กำลังเติมเต็ม" value={all.filter(x=>x.state!=='ready').length} note="บางส่วนและ Mockup" tone="warning"/></div>
    {GROUPS.map((group) => <section className="registry-section" key={group.title}><div className="registry-section-head"><div><span>{group.subtitle}</span><h3>{group.title}</h3></div><b>{group.items.length} เมนู</b></div><div className="operation-grid">{group.items.map((x) => { const s=STATUS[x.state]; return <a className="operation-card" href={href(x.path ?? `/registry?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.description}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>; })}</div></section>)}
  </>;
}

function Stat({title,value,note,tone}:{title:string;value:number;note:string;tone:string}) { return <div className={`registry-stat ${tone}`}><span>{title}</span><strong>{value}</strong><small>{note}</small></div>; }
function Preview({item}:{item:Item}) { return <><PageHead title={item.title} sub="โครงหน้าจอสำหรับเชื่อมข้อมูลภายหลัง" actions={<a href={href('/registry')}>← กลับ</a>}/><Notice kind="info">ยังไม่มี API เฉพาะ ข้อมูลในหน้านี้เป็น Mockup และไม่บันทึกลงฐานข้อมูล</Notice><div className="registry-summary"><Stat title="รายการทั้งหมด" value={24} note="ข้อมูลตัวอย่าง" tone="primary"/><Stat title="กำลังดำเนินการ" value={18} note="ภาคเรียนปัจจุบัน" tone="success"/><Stat title="รอตรวจสอบ" value={6} note="ต้องดำเนินการ" tone="warning"/></div><Card title={`ภาพรวม ${item.title}`}><div className="mock-chart">{[48,72,58,88,66,94].map((h)=><i key={h} style={{height:`${h}%`}}/>)}</div><p className="hint">{item.description} ตัวเลขและกราฟเป็นตัวอย่างเพื่อยืนยันรูปแบบก่อนพัฒนา API จริง</p></Card></>; }

import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key: string; title: string; description: string; path?: string; state: State };
type Group = { title: string; subtitle: string; items: Item[] };

/**
 * แต่ละหน้าจอจริงมีการ์ดเดียวในทั้งศูนย์นี้ — เดิมเคยมีการ์ดซ้ำชี้ปลายทาง
 * เดียวกันคนละชื่อ (เช่น /gradebook มีการ์ดชื่อต่างกันหกใบ) ทำให้หาไม่เจอว่า
 * ควรกดใบไหน คำอธิบายของการ์ดที่เหลือจึงรวมงานย่อยที่เคยแยกใบไว้ทั้งหมด
 */
const GROUPS: Group[] = [
  { title: 'งานทะเบียน', subtitle: 'ข้อมูลนักศึกษา การลงทะเบียน และงานวัดผล', items: [
    ['students','ระเบียนนักศึกษา','ค้นหาและตรวจสอบระเบียน สถานะลงทะเบียน และผลการเรียนของนักศึกษา','/students','ready'],
    ['registration','ลงทะเบียนเรียน','ลงทะเบียนทั้งห้องหรือรายคน และดูรายชื่อที่ลงทะเบียนแล้วแยกตามวิชา','/registration','ready'],
    ['gradebook','สมุดคะแนนและอนุมัติเกรด','บันทึกคะแนน ตรวจผล ส่งผล และอนุมัติเกรดตามลำดับงาน','/gradebook','ready'],
    ['attendance','เช็คชื่อรายคาบ','เปิดคาบเรียนและบันทึกสถานะการเข้าเรียนรายคาบ','/attendance','ready'],
    ['change-requests','คำร้องขอแก้เกรด','ยื่นและอนุมัติคำร้องขอแก้ไขผลการเรียนที่ล็อกแล้ว','/change-requests','ready'],
    ['admissions','งานรับสมัคร','เปิดรอบรับสมัคร ตั้งโควตา รับใบสมัคร ตัดสินผล และขึ้นทะเบียนเป็นนักศึกษา','/admissions','ready'],
    ['dual','ทวิภาคีและสถานประกอบการ','บันทึกสถานประกอบการ ชั่วโมงฝึกงาน และการรับรองชั่วโมง','/dual','ready'],
    ['clubs','จัดการวิชาชุมนุม/ชมรม','บันทึกชื่อชมรม ผู้ดูแล และสมาชิกรายปีการศึกษา','/clubs','ready'],
    ['onet','ผลสอบ O-NET','วางผลสอบจากตารางและดูสรุปคะแนนเฉลี่ยรายวิชา','/onet','ready'],
  ].map(([key,title,description,path,state]) => ({key,title,description,path,state} as Item)) },
  { title: 'รายงานและเอกสาร', subtitle: 'เอกสารทะเบียน รายงานผล และข้อมูลส่งออก', items: [
    ['documents','ออกเอกสาร','พิมพ์ใบลงทะเบียน ใบ รบ./Transcript สมุดพก และใบรับรองสถานภาพ','/documents','ready'],
    ['graduation','สำเร็จการศึกษา','ตรวจเกณฑ์จบ อนุมัติจบ และแบบสำรวจภาวะการมีงานทำ/ศึกษาต่อ','/graduation','ready'],
    ['government-exports','ส่งออกข้อมูลหน่วยงานรัฐ','ออกเอกสารและส่งออกชุดข้อมูลให้หน่วยงานภาครัฐ','/government-exports','ready'],
    ['statistics','ข้อมูลสถิติ','ภาพรวมนักศึกษา บุคลากร การเงิน และการเฝ้าระวังทั้งวิทยาลัย','/statistics','ready'],
  ].map(([key,title,description,path,state]) => ({key,title,description,path,state} as Item)) },
  { title: 'การตั้งค่า', subtitle: 'หลักสูตร ปีการศึกษา และการนำเข้าข้อมูล', items: [
    ['curriculum','โครงสร้างหลักสูตร','สาขาวิชา รุ่นหลักสูตร หมวดวิชา รายวิชา และแผนการเรียน','/curriculum','ready'],
    ['academic-year','งานวิชาการรายปี','เปิดปีการศึกษา/ภาคเรียน จัดนักศึกษาเข้าห้อง และเดินสถานะภาคเรียน','/academic-year','ready'],
    ['import','นำเข้าข้อมูล','นำเข้าประวัติการเรียนเดิมและข้อมูลนักศึกษาเป็นชุดจากไฟล์ CSV','/import','ready'],
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
    <div className="registry-summary"><Stat title="ฟังก์ชันทั้งหมด" value={all.length} note="หนึ่งการ์ดต่อหนึ่งหน้าจอ" tone="primary"/><Stat title="พร้อมใช้งาน" value={all.filter(x=>x.state==='ready').length} note="เชื่อมหน้าจอแล้ว" tone="success"/><Stat title="กำลังเติมเต็ม" value={all.filter(x=>x.state!=='ready').length} note="บางส่วนและ Mockup" tone="warning"/></div>
    {GROUPS.map((group) => <section className="registry-section" key={group.title}><div className="registry-section-head"><div><span>{group.subtitle}</span><h3>{group.title}</h3></div><b>{group.items.length} เมนู</b></div><div className="operation-grid">{group.items.map((x) => { const s=STATUS[x.state]; return <a className="operation-card" href={href(x.path ?? `/registry?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.description}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>; })}</div></section>)}
  </>;
}

function Stat({title,value,note,tone}:{title:string;value:number;note:string;tone:string}) { return <div className={`registry-stat ${tone}`}><span>{title}</span><strong>{value}</strong><small>{note}</small></div>; }
function Preview({item}:{item:Item}) { return <><PageHead title={item.title} sub="โครงหน้าจอสำหรับเชื่อมข้อมูลภายหลัง" actions={<a href={href('/registry')}>← กลับ</a>}/><Notice kind="info">ยังไม่มี API เฉพาะ ข้อมูลในหน้านี้เป็น Mockup และไม่บันทึกลงฐานข้อมูล</Notice><div className="registry-summary"><Stat title="รายการทั้งหมด" value={24} note="ข้อมูลตัวอย่าง" tone="primary"/><Stat title="กำลังดำเนินการ" value={18} note="ภาคเรียนปัจจุบัน" tone="success"/><Stat title="รอตรวจสอบ" value={6} note="ต้องดำเนินการ" tone="warning"/></div><Card title={`ภาพรวม ${item.title}`}><div className="mock-chart">{[48,72,58,88,66,94].map((h)=><i key={h} style={{height:`${h}%`}}/>)}</div><p className="hint">{item.description} ตัวเลขและกราฟเป็นตัวอย่างเพื่อยืนยันรูปแบบก่อนพัฒนา API จริง</p></Card></>; }

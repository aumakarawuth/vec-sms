import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State='ready'|'partial'|'planned'; type Item={key:string;title:string;desc:string;path?:string;state:State};
const item=(key:string,title:string,desc:string,path:string|undefined,state:State):Item=>({key,title,desc,path,state});
/** หนึ่งหน้าจอจริงมีการ์ดเดียว — เดิม /timetable มีการ์ดชี้ปลายทางเดียวกันเจ็ดใบ */
const GROUPS=[
 {title:'งานตารางเรียน',subtitle:'ลงทะเบียนเสริม จัดตาราง และตารางสอบ',items:[
  item('extra-registration','จัดการลงทะเบียนเรียนเสริม/เรียนปรับเกรด','ลงทะเบียนรายคนสำหรับเรียนซ้ำ ตกค้าง หรือปรับผลการเรียน','/registration?tab=student','ready'),
  item('timetable','จัดตารางสอน','สร้าง แนะนำ และตรวจตารางสอนอัตโนมัติ พร้อมดูคาบว่าง ภาระงาน และการใช้ห้องของผู้สอน โอนย้ายคาบ ห้อง หรือผู้สอนได้จากหน้าเดียวกัน','/timetable','ready'),
  item('exam-schedule','ตารางสอบ','จัดวัน เวลา ห้อง และกรรมการคุมสอบ พร้อมตรวจการชนก่อนบันทึก','/exam-schedule','ready'),
 ]},
 {title:'การตั้งค่าและรอบพิเศษ',subtitle:'ผู้สอน ที่ปรึกษา และรอบเรียนปรับเกรด',items:[
  item('teachers','กำหนดอาจารย์ผู้สอนและเปิดกลุ่มเรียน','เปิดกลุ่มเรียนพร้อมเลือกผู้สอนประจำรายวิชา','/academic-year','ready'),
  item('advisors','กำหนดอาจารย์ที่ปรึกษา','แต่งตั้งอาจารย์ที่ปรึกษารายคนหรือแบบกลุ่ม','/students','ready'),
  item('remedial','เรียนเสริม/สอบซ่อม/ปรับเกรด','เปิดรอบแก้ผล บันทึกผลสอบซ่อม และลงทะเบียนผู้มีสิทธิ์','/academic-year','ready'),
  item('workload','ภาระงาน','สรุปภาระการสอนและงานที่ได้รับมอบหมาย',undefined,'partial'),
 ]},
];
const STATUS={ready:{label:'พร้อมใช้งาน',kind:'ok'},partial:{label:'ใช้งานได้บางส่วน',kind:'warn'},planned:{label:'หน้าต้นแบบ',kind:'info'}} as const;
export function TimetableCenterScreen(){const all=GROUPS.flatMap(g=>g.items), selected=useRoute().query.get('module'), chosen=all.find(x=>x.key===selected);if(chosen&&!chosen.path)return <Preview x={chosen}/>;return <><PageHead title="ศูนย์งานตารางเรียน" sub="จัดตาราง รายงาน และการตั้งค่าในจุดเดียว"/><div className="registry-summary"><Stat t="ฟังก์ชันทั้งหมด" v={all.length} n="หนึ่งการ์ดต่อหนึ่งหน้าจอ" c="primary"/><Stat t="พร้อมใช้งาน" v={all.filter(x=>x.state==='ready').length} n="เชื่อมหน้าจอแล้ว" c="success"/><Stat t="กำลังเติมเต็ม" v={all.filter(x=>x.state!=='ready').length} n="บางส่วนและ Mockup" c="warning"/></div>{GROUPS.map(g=><section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map(x=>{const s=STATUS[x.state];return <a className="operation-card" href={href(x.path??`/timetable-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>})}</div></section>)}</>}
function Stat({t,v,n,c}:{t:string;v:number;n:string;c:string}){return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>}
function Preview({x}:{x:Item}){return <><PageHead title={x.title} sub="โครงหน้าจอสำหรับเชื่อมระบบตารางเรียน" actions={<a href={href('/timetable-center')}>← กลับ</a>}/><Notice kind="info">หน้านี้เป็น Mockup และยังไม่บันทึกข้อมูลลงฐานข้อมูล</Notice><div className="registry-summary"><Stat t="คาบทั้งหมด" v={128} n="ข้อมูลตัวอย่าง" c="primary"/><Stat t="จัดตารางแล้ว" v={112} n="87.5%" c="success"/><Stat t="รอดำเนินการ" v={16} n="ต้องจัดตาราง" c="warning"/></div><Card title={`ภาพรวม ${x.title}`}><div className="mock-chart">{[76,58,92,68,84,64].map((h,i)=><i key={i} style={{height:`${h}%`}}/>)}</div><p className="hint">{x.desc} กราฟเป็นข้อมูลตัวอย่างเพื่อรอเชื่อม API เฉพาะ</p></Card></>}

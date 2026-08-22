import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State='ready'|'partial'|'planned'; type Item={key:string;title:string;desc:string;path?:string;state:State};
const item=(key:string,title:string,desc:string,path:string|undefined,state:State):Item=>({key,title,desc,path,state});
const GROUPS=[
 {title:'งานตารางเรียน',subtitle:'ลงทะเบียน เรียนเสริม และการโอนย้าย',items:[
  item('extra-registration','จัดการลงทะเบียนเรียนเสริม/เรียนปรับเกรด','ลงทะเบียนรายคนสำหรับเรียนซ้ำ ตกค้าง หรือปรับผลการเรียน','/registration?tab=student','ready'),
  item('transfer','โอนย้ายตารางสอน','ย้ายคาบ ห้อง หรือครูผู้สอนระหว่างตาราง','/timetable','ready'),
 ]},
 {title:'รายงาน',subtitle:'ตารางเรียน ภาระงาน และการใช้ห้อง',items:[
  item('class-timetable','ตารางเรียน/ตารางสอน','ดูและจัดตารางตามภาคเรียน ห้อง และกลุ่มเรียน','/timetable','ready'),
  item('teacher-availability','รายงานคาบว่างของอาจารย์','ตรวจช่วงเวลาว่างและข้อจำกัดของผู้สอน','/timetable','ready'),
  item('teacher-load','รายงานคาบสอนของอาจารย์','สรุปวิชา กลุ่มเรียน และจำนวนคาบของผู้สอน','/timetable','ready'),
  item('workload','ภาระงาน','สรุปภาระการสอนและงานที่ได้รับมอบหมาย',undefined,'partial'),
  item('classroom-use','การใช้ห้อง','ตรวจห้องว่างและตารางการใช้ห้องเรียน','/timetable','ready'),
 ]},
 {title:'การตั้งค่า',subtitle:'ผู้สอน ที่ปรึกษา ห้องเรียน และรอบสอบ',items:[
  item('teachers','กำหนดอาจารย์ผู้สอน','เปิดกลุ่มเรียนพร้อมเลือกผู้สอนประจำรายวิชา','/academic-year','ready'),
  item('advisors','กำหนดอาจารย์ที่ปรึกษา','แต่งตั้งอาจารย์ที่ปรึกษารายคนหรือแบบกลุ่ม','/students','ready'),
  item('weekly-spread','จัดตารางสอน (แบบกระจายสัปดาห์)','จัดคาบอัตโนมัติพร้อมตรวจข้อขัดแย้ง','/timetable','ready'),
  item('schedule','จัดตารางสอน','สร้าง แนะนำ และตรวจตารางสอน','/timetable','ready'),
  item('class-schedule','ลงตารางสอนแต่ละชั้นเรียน','จัดรายวิชา ห้อง และเวลาให้แต่ละกลุ่ม','/timetable','ready'),
  item('remedial','เรียนเสริม/เรียนปรับเกรด','เปิดรอบแก้ผลและลงทะเบียนผู้มีสิทธิ์','/academic-year','ready'),
  item('retest','สอบซ่อม/ปรับเกรด','บันทึกผลการสอบซ่อมและปรับผลการเรียน','/academic-year','ready'),
  item('exam-schedule','ตารางสอบ','จัดวัน เวลา ห้อง และกรรมการคุมสอบ พร้อมตรวจการชนก่อนบันทึก','/exam-schedule','ready'),
 ]},
];
const STATUS={ready:{label:'พร้อมใช้งาน',kind:'ok'},partial:{label:'ใช้งานได้บางส่วน',kind:'warn'},planned:{label:'หน้าต้นแบบ',kind:'info'}} as const;
export function TimetableCenterScreen(){const all=GROUPS.flatMap(g=>g.items), selected=useRoute().query.get('module'), chosen=all.find(x=>x.key===selected);if(chosen&&!chosen.path)return <Preview x={chosen}/>;return <><PageHead title="ศูนย์งานตารางเรียน" sub="จัดตาราง รายงาน และการตั้งค่าในจุดเดียว"/><div className="registry-summary"><Stat t="ฟังก์ชันทั้งหมด" v={all.length} n="ตามเมนูต้นแบบ" c="primary"/><Stat t="พร้อมใช้งาน" v={all.filter(x=>x.state==='ready').length} n="เชื่อมหน้าจอแล้ว" c="success"/><Stat t="กำลังเติมเต็ม" v={all.filter(x=>x.state!=='ready').length} n="บางส่วนและ Mockup" c="warning"/></div>{GROUPS.map(g=><section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map(x=>{const s=STATUS[x.state];return <a className="operation-card" href={href(x.path??`/timetable-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>})}</div></section>)}</>}
function Stat({t,v,n,c}:{t:string;v:number;n:string;c:string}){return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>}
function Preview({x}:{x:Item}){return <><PageHead title={x.title} sub="โครงหน้าจอสำหรับเชื่อมระบบตารางเรียน" actions={<a href={href('/timetable-center')}>← กลับ</a>}/><Notice kind="info">หน้านี้เป็น Mockup และยังไม่บันทึกข้อมูลลงฐานข้อมูล</Notice><div className="registry-summary"><Stat t="คาบทั้งหมด" v={128} n="ข้อมูลตัวอย่าง" c="primary"/><Stat t="จัดตารางแล้ว" v={112} n="87.5%" c="success"/><Stat t="รอดำเนินการ" v={16} n="ต้องจัดตาราง" c="warning"/></div><Card title={`ภาพรวม ${x.title}`}><div className="mock-chart">{[76,58,92,68,84,64].map((h,i)=><i key={i} style={{height:`${h}%`}}/>)}</div><p className="hint">{x.desc} กราฟเป็นข้อมูลตัวอย่างเพื่อรอเชื่อม API เฉพาะ</p></Card></>}

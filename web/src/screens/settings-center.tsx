import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';
type State='ready'|'partial'|'planned'; type Item={key:string;title:string;desc:string;path?:string;state:State};
/** หนึ่งหน้าจอจริงมีการ์ดเดียว — เดิม /curriculum มีการ์ดชี้ปลายทางเดียวกันสี่ใบ */
const GROUPS:{title:string;subtitle:string;items:Item[]}[]=[
 {title:'โครงสร้างหลักสูตร',subtitle:'หมวดภาคเรียน คาบเรียน ระดับชั้น สาขา หลักสูตร และระดับการศึกษา',items:[
  {key:'term-categories',title:'หมวดภาคเรียน',desc:'จัดกลุ่มภาคเรียนตามรอบเรียน (รอบเช้า รอบบ่าย ทวิภาคี) และแก้ไขช่วงวันที่ย่อยของแต่ละภาคเรียน',path:'/term-categories',state:'ready'},
  {key:'periods',title:'คาบเรียน',desc:'กำหนดกลุ่มคาบและช่วงเวลาที่ใช้จัดตารางสอน',path:'/periods',state:'ready'},
  {key:'grade-levels',title:'ชื่อระดับชั้น',desc:'ตั้งชื่อและชื่อย่อของแต่ละชั้นปีในแต่ละระดับ (ปวช.1 ฯลฯ) — ป้ายแสดงผลเท่านั้น ไม่กระทบการเลื่อนชั้นจริง',path:'/grade-levels',state:'ready'},
  {key:'branches',title:'ประเภท/สาขา/ชั้นเรียน/ห้องเรียน',desc:'เลือกหลักสูตรก่อน แล้วดูประเภท สาขา และเพิ่มห้องประจำชั้น',path:'/curriculum/programs',state:'ready'},
  {key:'curriculum',title:'หลักสูตร',desc:'เลือกหลักสูตร สอศ. แก้ชื่อ และนำเข้าเป็นฉบับร่าง',path:'/curriculum-library',state:'ready'},
  {key:'education-level',title:'ระดับการศึกษา',desc:'กำหนดระดับและฉบับหลักสูตร (ปวช./ปวส.) ที่ใช้ในระบบ',path:'/education-levels',state:'ready'},
 ]},
 {title:'เครื่องมือ',subtitle:'งานตามกำหนดเวลา นำเข้า/ส่งออกข้อมูล และสื่อ',items:[
  {key:'jobs',title:'งานตามกำหนดเวลา',desc:'ดูสถานะและสั่งรันงานประจำวันของระบบ (คำนวณสถิติ ส่งแจ้งเตือน ฯลฯ)',path:'/jobs',state:'ready'},
  {key:'import',title:'นำเข้าข้อมูล',desc:'นำเข้าข้อมูลนักศึกษาและบุคลากรจากไฟล์ พร้อมขั้นตรวจสอบก่อนบันทึกจริง',path:'/import',state:'ready'},
  {key:'government-exports',title:'ส่งออกข้อมูล',desc:'ออกไฟล์ข้อมูลตามรูปแบบที่หน่วยงานรัฐกำหนด (PVRS ฯลฯ)',path:'/government-exports',state:'ready'},
 ]},
];
const STATUS={ready:{label:'พร้อมใช้งาน',kind:'ok'},partial:{label:'ใช้งานได้บางส่วน',kind:'warn'},planned:{label:'หน้าต้นแบบ',kind:'info'}} as const;
export function SettingsCenterScreen(){const all=GROUPS.flatMap(g=>g.items),selected=useRoute().query.get('module'),chosen=all.find(x=>x.key===selected);if(chosen&&!chosen.path)return <Preview x={chosen}/>;return <><PageHead title="ศูนย์การตั้งค่า" sub="หลักสูตร ข้อมูลพื้นฐาน และเครื่องมือระบบ"/><div className="registry-summary"><Stat t="รายการตั้งค่า" v={all.length} n="หนึ่งการ์ดต่อหนึ่งหน้าจอ" c="primary"/><Stat t="พร้อมใช้งาน" v={all.filter(x=>x.state==='ready').length} n="เชื่อมหน้าจอแล้ว" c="success"/><Stat t="กำลังเติมเต็ม" v={all.filter(x=>x.state!=='ready').length} n="บางส่วนและ Mockup" c="warning"/></div>{GROUPS.map(g=><section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map(x=>{const s=STATUS[x.state];return <a className="operation-card" href={href(x.path??`/settings-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'⚙'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>})}</div></section>)}</>}
function Stat({t,v,n,c}:{t:string;v:number;n:string;c:string}){return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>}
function Preview({x}:{x:Item}){return <><PageHead title={x.title} sub="เครื่องมือระบบฉบับต้นแบบ" actions={<a href={href('/settings-center')}>← กลับ</a>}/><Notice kind="info">หน้านี้เป็น Mockup การกดใช้งานจะยังไม่เปลี่ยนข้อมูลจริง</Notice><div className="registry-summary"><Stat t="สถานะระบบ" v={100} n="พร้อมให้บริการ (%)" c="success"/><Stat t="รายการทั้งหมด" v={12} n="ข้อมูลตัวอย่าง" c="primary"/><Stat t="รอตั้งค่า" v={3} n="ต้องดำเนินการ" c="warning"/></div><Card title={x.title}><div className="mock-chart">{[86,70,94,62,78,90].map((h,i)=><i key={i} style={{height:`${h}%`}}/>)}</div><p className="hint">{x.desc} หน้านี้เตรียมรูปแบบไว้เพื่อเชื่อม API และพื้นที่จัดเก็บในขั้นถัดไป</p></Card></>}

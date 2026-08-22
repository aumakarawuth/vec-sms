import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';
type State='ready'|'partial'|'planned'; type Item={key:string;title:string;desc:string;path?:string;state:State};
/** หนึ่งหน้าจอจริงมีการ์ดเดียว — เดิม /curriculum มีการ์ดชี้ปลายทางเดียวกันสี่ใบ */
const GROUPS:{title:string;subtitle:string;items:Item[]}[]=[
 {title:'การตั้งค่า',subtitle:'หลักสูตร ปีการศึกษา และค่าเรียน',items:[
  {key:'curriculum',title:'โครงสร้างหลักสูตร',desc:'สาขาวิชา หลักสูตร รุ่น ระดับการศึกษา ห้องเรียน และหน่วยกิตสะสม',path:'/curriculum',state:'ready'},
  {key:'academic-year',title:'ปีการศึกษาและระดับชั้น',desc:'เปิดปีการศึกษา/ภาคเรียนใหม่ เดินสถานะภาคเรียน และจัดชั้นปี',path:'/academic-year',state:'ready'},
  {key:'tuition',title:'ค่าเรียน',desc:'ค่าธรรมเนียม ใบแจ้งหนี้ และตารางการชำระ',path:'/finance',state:'ready'},
 ]},
 {title:'เครื่องมือ',subtitle:'งานตามกำหนดเวลา ข้อมูลระบบ และสื่อ',items:[
  {key:'jobs',title:'งานตามกำหนดเวลา',desc:'ดูสถานะและสั่งรันงานประจำวันของระบบ (คำนวณสถิติ ส่งแจ้งเตือน ฯลฯ)',path:'/jobs',state:'ready'},
  {key:'system-info',title:'System Informations',desc:'ข้อมูลเวอร์ชัน สถานะบริการ และสภาพแวดล้อมระบบ',state:'planned'},
  {key:'images',title:'จัดการไฟล์รูปภาพ',desc:'รูปนักศึกษา บุคลากร ตราสถานศึกษา และไฟล์ประกอบ',state:'planned'},
  {key:'qr',title:'QR Code',desc:'สร้างรหัสสำหรับเช็กอิน เอกสาร และการตรวจสอบ',state:'planned'},
 ]},
];
const STATUS={ready:{label:'พร้อมใช้งาน',kind:'ok'},partial:{label:'ใช้งานได้บางส่วน',kind:'warn'},planned:{label:'หน้าต้นแบบ',kind:'info'}} as const;
export function SettingsCenterScreen(){const all=GROUPS.flatMap(g=>g.items),selected=useRoute().query.get('module'),chosen=all.find(x=>x.key===selected);if(chosen&&!chosen.path)return <Preview x={chosen}/>;return <><PageHead title="ศูนย์การตั้งค่า" sub="หลักสูตร ข้อมูลพื้นฐาน และเครื่องมือระบบ"/><div className="registry-summary"><Stat t="รายการตั้งค่า" v={all.length} n="หนึ่งการ์ดต่อหนึ่งหน้าจอ" c="primary"/><Stat t="พร้อมใช้งาน" v={all.filter(x=>x.state==='ready').length} n="เชื่อมหน้าจอแล้ว" c="success"/><Stat t="กำลังเติมเต็ม" v={all.filter(x=>x.state!=='ready').length} n="บางส่วนและ Mockup" c="warning"/></div>{GROUPS.map(g=><section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map(x=>{const s=STATUS[x.state];return <a className="operation-card" href={href(x.path??`/settings-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'⚙'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>})}</div></section>)}</>}
function Stat({t,v,n,c}:{t:string;v:number;n:string;c:string}){return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>}
function Preview({x}:{x:Item}){return <><PageHead title={x.title} sub="เครื่องมือระบบฉบับต้นแบบ" actions={<a href={href('/settings-center')}>← กลับ</a>}/><Notice kind="info">หน้านี้เป็น Mockup การกดใช้งานจะยังไม่เปลี่ยนข้อมูลจริง</Notice><div className="registry-summary"><Stat t="สถานะระบบ" v={100} n="พร้อมให้บริการ (%)" c="success"/><Stat t="รายการทั้งหมด" v={12} n="ข้อมูลตัวอย่าง" c="primary"/><Stat t="รอตั้งค่า" v={3} n="ต้องดำเนินการ" c="warning"/></div><Card title={x.title}><div className="mock-chart">{[86,70,94,62,78,90].map((h,i)=><i key={i} style={{height:`${h}%`}}/>)}</div><p className="hint">{x.desc} หน้านี้เตรียมรูปแบบไว้เพื่อเชื่อม API และพื้นที่จัดเก็บในขั้นถัดไป</p></Card></>}

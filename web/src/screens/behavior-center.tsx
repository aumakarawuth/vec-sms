import { href, useRoute } from '../core/router'; import { Badge,Card,Notice,PageHead } from '../ui/kit';
type S='ready'|'partial'|'planned'; type I={key:string;title:string;desc:string;path?:string;state:S}; const i=(key:string,title:string,desc:string,path:string|undefined,state:S):I=>({key,title,desc,path,state});
/** หนึ่งหน้าจอจริงมีการ์ดเดียว — เดิม /behavior มีการ์ดชี้ปลายทางเดียวกันเจ็ดใบ และ /attendance ห้าใบ */
const GROUPS=[
 {title:'งานพฤติกรรมและกิจการนักศึกษา',subtitle:'การลา พฤติกรรม เวลาเรียน และการติดตาม',items:[
  i('leave','จัดการการลา','รับคำขอ ตรวจสอบ อนุมัติ และดูรายงานการลาของนักศึกษา','/leaves','ready'),
  i('behavior','พฤติกรรมและการดูแล','บันทึกคะแนนพฤติกรรม กำหนดประเภท คัดกรองกลุ่มเสี่ยง และติดตามเคส','/behavior','ready'),
  i('risk','เฝ้าระวังและติดตาม','รายชื่อนักศึกษากลุ่มเสี่ยงและการติดตามดูแลรายบุคคล','/risk','ready'),
  i('attendance','เวลาเรียน','ตรวจสมุดบันทึกเวลาเรียน รายงาน และรายการที่ต้องพิจารณาเพื่อการดูแล','/attendance','ready'),
  i('letters','หนังสือถึงผู้ปกครอง','จดหมายแจ้งขาดเรียน หนังสือเชิญผู้ปกครอง และใบรับรองความประพฤติ','/letters','ready'),
  i('cumulative','จัดการข้อมูลระเบียนสะสม (ปพ.8)','ข้อมูลสะสม การดูแล และการส่งต่อรายบุคคล',undefined,'partial'),
 ]},
 {title:'การตั้งค่าและสแกนบัตร',subtitle:'สแกนบัตร เวลา และ RFID',items:[
  i('scan-settings','จัดการข้อมูลการสแกนบัตร','ตรวจรายการสแกนและสถานะการตัดสินใจ',undefined,'partial'),
  i('card-period','กำหนดเวลาแต่ละหลักสูตร','กำหนดช่วงเวลาตามหลักสูตรและระดับชั้น',undefined,'partial'),
 ]},
];
const ST={ready:{label:'พร้อมใช้งาน',kind:'ok'},partial:{label:'ใช้งานได้บางส่วน',kind:'warn'},planned:{label:'หน้าต้นแบบ',kind:'info'}} as const;
export function BehaviorCenterScreen(){const all=GROUPS.flatMap(g=>g.items),q=useRoute().query.get('module'),x=all.find(v=>v.key===q);if(x&&!x.path)return <Preview x={x}/>;return <><PageHead title="ศูนย์งานพฤติกรรม" sub="ดูแลนักศึกษา การลา เวลาเรียน และการติดตาม"/><div className="registry-summary"><Stat t="ฟังก์ชันทั้งหมด" v={all.length} n="หนึ่งการ์ดต่อหนึ่งหน้าจอ" c="primary"/><Stat t="พร้อมใช้งาน" v={all.filter(x=>x.state==='ready').length} n="เชื่อมหน้าจอแล้ว" c="success"/><Stat t="กำลังเติมเต็ม" v={all.filter(x=>x.state!=='ready').length} n="บางส่วนและ Mockup" c="warning"/></div>{GROUPS.map(g=><section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map(x=>{const s=ST[x.state];return <a className="operation-card" href={href(x.path??`/behavior-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>})}</div></section>)}</>}
function Stat({t,v,n,c}:{t:string;v:number;n:string;c:string}){return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>}
function Preview({x}:{x:I}){return <><PageHead title={x.title} sub="โครงหน้าจอสำหรับงานพฤติกรรม" actions={<a href={href('/behavior-center')}>← กลับ</a>}/><Notice kind="info">หน้านี้เป็น Mockup และไม่เปลี่ยนข้อมูลจริง</Notice><div className="registry-summary"><Stat t="นักศึกษาที่ติดตาม" v={42} n="ข้อมูลตัวอย่าง" c="primary"/><Stat t="สถานะปกติ" v={34} n="ดำเนินการแล้ว" c="success"/><Stat t="ต้องติดตาม" v={8} n="รอดำเนินการ" c="warning"/></div><Card title={x.title}><div className="mock-chart">{[82,64,91,58,74,88].map((h,n)=><i key={n} style={{height:`${h}%`}}/>)}</div><p className="hint">{x.desc} ข้อมูลนี้ใช้แสดงรูปแบบก่อนเชื่อม API เฉพาะ</p></Card></>}

/** รายการเมนูย่อยให้แถบซ้ายแสดงใต้ศูนย์นี้ — อ่านจากการ์ดชุดเดียวกันจึงไม่เพี้ยนจากกัน */
export const SUBNAV = GROUPS.flatMap((g) => g.items.map((x) => ({ ...x, group: g.title }))).filter((x) => x.path).map((x) => ({ path: x.path!, label: x.title, group: x.group }));

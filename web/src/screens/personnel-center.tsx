import { href, useRoute } from '../core/router';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State='ready'|'partial'|'planned';
type Item={key:string;title:string;desc:string;path?:string;state:State};
const make=(rows:(string|undefined)[][]):Item[]=>rows.map(([key,title,desc,path,state])=>({key:key!,title:title!,desc:desc!,path,state:state as State}));
const GROUPS=[
  {title:'งานบุคลากร',subtitle:'ผู้ใช้งาน สิทธิ์ ระเบียน และเวลาปฏิบัติงาน',items:make([
    ['staff-search','ค้นหาผู้ใช้','ค้นหารหัส ชื่อ และสถานะบุคลากร','/hr','ready'],
    ['login-info','ข้อมูลผู้ใช้ระบบ','บัญชีเข้าสู่ระบบและสถานะการใช้งาน','/hr','partial'],
    ['teacher-system','ระบบสำหรับอาจารย์','สมุดคะแนน เช็กชื่อ และงานสอน','/gradebook','ready'],
    ['permissions','การตั้งค่าและการกำหนดสิทธิ์','บทบาทผู้ใช้และช่วงเวลาที่ได้รับสิทธิ์','/hr','partial'],
    ['time-import','นำเข้าข้อมูลเวลา','รับข้อมูลเวลาปฏิบัติงานจากเครื่องบันทึกเวลา',undefined,'partial'],
    ['staff-settings','ตั้งค่าข้อมูลบุคลากร','ข้อมูลหน่วยงาน ตำแหน่ง และระเบียน ทช.1','/hr','ready'],
    ['staff-view','แสดงรูปภาพบุคลากร','หน้ารวมรูปและข้อมูลติดต่อบุคลากร',undefined,'planned'],
    ['contact','ติดต่อบุคลากร','สมุดรายชื่อ โทรศัพท์ และอีเมล',undefined,'partial'],
    ['staff-select','คัดลอกบุคลากร','คัดลอกข้อมูลบุคลากรสำหรับปีการศึกษาใหม่',undefined,'planned'],
  ])},
  {title:'รายงาน',subtitle:'เวลาเรียน ภาระงาน ระเบียน และสวัสดิการ',items:make([
    ['attendance-book','ตรวจสอบสมุดบันทึกเวลาเรียน','ตรวจรายชื่อและเวลาเรียนรายคาบ','/attendance','ready'],
    ['teaching-load','วิชาที่สอน (ภาคเรียน)','รายวิชา กลุ่มเรียน และภาระงานสอน','/timetable','partial'],
    ['personal-info','ข้อมูลบุคลากร','ข้อมูลประจำตัว ตำแหน่ง และหน่วยงาน','/hr','ready'],
    ['staff-register','ระเบียนบุคลากร','ระเบียนประวัติการทำงานและคุณวุฒิ','/hr','ready'],
    ['staff-register-1','ระเบียนบุคลากร (ทช.1)','คุณวุฒิ ประสบการณ์ อบรม และรางวัล','/hr','ready'],
    ['staff-card','บัตรบุคลากร','ต้นแบบบัตรประจำตัวพร้อมรูปถ่าย',undefined,'planned'],
    ['staff-summary','สรุปเวลาทำการ','รายงานเวลาปฏิบัติงานรายวันและรายเดือน',undefined,'partial'],
    ['staff-book','บุคลากร','บัญชีรายชื่อบุคลากรสำหรับพิมพ์',undefined,'partial'],
    ['welfare','สวัสดิการ','ข้อมูลบุตรและสิทธิประโยชน์บุคลากร','/hr','partial'],
    ['training','ฝึกอบรม','ชั่วโมงอบรมและการพัฒนาวิชาชีพ','/hr','ready'],
    ['staff-reports','ข้อมูลบุคลากร','ชุดรายงานบุคลากรสำหรับหน่วยงานภายนอก','/government-exports','ready'],
    ['statistics','ข้อมูลสถิติ','จำนวนบุคลากร แยกหน่วยงาน ตำแหน่ง และสถานะ',undefined,'partial'],
  ])},
  {title:'การตั้งค่า',subtitle:'โครงสร้างองค์กร เวลา สแกนบัตร และการนำเข้า',items:make([
    ['master','ข้อมูลพื้นฐาน','ข้อมูลตั้งต้นสำหรับงานบุคลากร','/hr','partial'],
    ['departments','คณะและหน่วยงาน','โครงสร้างหน่วยงานแบบลำดับชั้น','/hr','ready'],
    ['administration','โครงสร้างการบริหาร','หัวหน้าหน่วยงานและสายการบังคับบัญชา','/hr','partial'],
    ['scan-format','กำหนดรูปแบบการสแกนบัตร','รูปแบบรหัสและเครื่องบันทึกเวลา',undefined,'planned'],
    ['worktime','กำหนดเวลาบุคลากร','เวลาเข้าออกและเงื่อนไขการมาสาย',undefined,'partial'],
    ['group-worktime','กำหนดเวลาทำการบุคลากรแบบกลุ่ม','ใช้ตารางเวลาร่วมกับหลายหน่วยงาน',undefined,'partial'],
    ['work-pattern','กำหนดรหัสการรับเข้าออก','รูปแบบรหัสจากเครื่องบันทึกเวลา',undefined,'planned'],
    ['staff-import','นำเข้าข้อมูลบุคลากร','ตรวจสอบและนำเข้าบุคลากรแบบกลุ่ม','/import','ready'],
    ['photo-import','รับรูปบุคลากร','จับคู่ไฟล์รูปด้วยรหัสบุคลากร',undefined,'planned'],
  ])},
];
const STATUS={ready:{label:'พร้อมใช้งาน',kind:'ok'},partial:{label:'ใช้งานได้บางส่วน',kind:'warn'},planned:{label:'หน้าต้นแบบ',kind:'info'}} as const;

export function PersonnelCenterScreen(){
  const selected=useRoute().query.get('module'); const all=GROUPS.flatMap(g=>g.items); const chosen=all.find(x=>x.key===selected);
  if(chosen&&!chosen.path)return <Preview item={chosen}/>;
  return <><PageHead title="ศูนย์งานบุคลากร" sub="บริหารบุคลากร รายงาน และการตั้งค่าในจุดเดียว"/><div className="registry-summary"><Stat t="ฟังก์ชันทั้งหมด" v={all.length} n="ตามเมนูต้นแบบ" c="primary"/><Stat t="พร้อมใช้งาน" v={all.filter(x=>x.state==='ready').length} n="เชื่อมหน้าจอแล้ว" c="success"/><Stat t="กำลังเติมเต็ม" v={all.filter(x=>x.state!=='ready').length} n="บางส่วนและ Mockup" c="warning"/></div>{GROUPS.map(g=><section className="registry-section" key={g.title}><div className="registry-section-head"><div><span>{g.subtitle}</span><h3>{g.title}</h3></div><b>{g.items.length} เมนู</b></div><div className="operation-grid">{g.items.map(x=>{const s=STATUS[x.state];return <a className="operation-card" href={href(x.path??`/personnel-center?module=${x.key}`)} key={x.key}><div className={`operation-icon ${x.state}`}>{x.path?'↗':'◇'}</div><div><strong>{x.title}</strong><p>{x.desc}</p><Badge kind={s.kind}>{s.label}</Badge></div><span className="operation-arrow">›</span></a>})}</div></section>)}</>;
}
function Stat({t,v,n,c}:{t:string;v:number;n:string;c:string}){return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>}
function Preview({item}:{item:Item}){return <><PageHead title={item.title} sub="โครงหน้าจอสำหรับเชื่อมข้อมูลบุคลากร" actions={<a href={href('/personnel-center')}>← กลับ</a>}/><Notice kind="info">หน้าจอนี้เป็น Mockup ข้อมูลตัวอย่างจะไม่ถูกบันทึกลงฐานข้อมูล</Notice><div className="registry-summary"><Stat t="บุคลากรทั้งหมด" v={86} n="ข้อมูลตัวอย่าง" c="primary"/><Stat t="ปฏิบัติงาน" v={78} n="สถานะปัจจุบัน" c="success"/><Stat t="รอตรวจสอบ" v={8} n="รายการที่ต้องดำเนินการ" c="warning"/></div><Card title={`ภาพรวม ${item.title}`}><div className="mock-chart">{[62,84,54,92,70,78].map((h,i)=><i key={i} style={{height:`${h}%`}}/>)}</div><p className="hint">{item.desc} ตัวเลขและกราฟเป็น Mockup เพื่อรอเชื่อม API เฉพาะในขั้นถัดไป</p></Card></>}

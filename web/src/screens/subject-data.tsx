import { href } from '../core/router';
import { Badge, PageHead } from '../ui/kit';

type SubjectItem = {
  title: string;
  description: string;
  path?: string;
  state: 'ready' | 'partial' | 'planned';
};

const GROUPS: { title: string; subtitle: string; items: SubjectItem[] }[] = [
  {
    title: 'โครงสร้างรายวิชา',
    subtitle: 'ข้อมูลที่ใช้ประกอบหลักสูตรและแผนการเรียน',
    items: [
      { title: 'กลุ่มสาระการเรียนรู้', description: 'จัดหมวดรายวิชาในฉบับหลักสูตร เช่น สมรรถนะวิชาชีพและพื้นฐาน', path: '/curriculum/versions', state: 'ready' },
      { title: 'กลุ่มวิชา', description: 'กำหนดกลุ่มวิชา ลำดับ และเงื่อนไขหน่วยกิตของแต่ละหลักสูตร', path: '/subject-groups', state: 'ready' },
      { title: 'วิชา', description: 'เพิ่ม แก้ไข ค้นหา รหัส ชื่อ หน่วยกิต และรายละเอียดรายวิชา', path: '/curriculum/courses', state: 'ready' },
      { title: 'แผนการเรียน', description: 'นำรายวิชาไปวางตามชั้นปีและภาคเรียนของหลักสูตร', path: '/curriculum/plan', state: 'ready' },
    ],
  },
  {
    title: 'ผลการเรียน',
    subtitle: 'เกณฑ์คะแนนและการแปลงผลการเรียน',
    items: [
      { title: 'ระดับผลการเรียน', description: 'กำหนดช่วงคะแนน อักษรเกรด และค่าคะแนนเฉลี่ย', path: '/grade-levels', state: 'ready' },
      { title: 'คะแนนจากสมุดคะแนน', description: 'บันทึก ตรวจสอบ และสรุปคะแนนรายวิชาจากสมุดคะแนน', path: '/gradebook', state: 'ready' },
      { title: 'กลุ่มคะแนนเก็บ', description: 'จัดสัดส่วนคะแนนเก็บ งาน แบบทดสอบ และสอบปลายภาคในรายวิชา', path: '/gradebook', state: 'partial' },
    ],
  },
  {
    title: 'การประเมินเพิ่มเติม',
    subtitle: 'เตรียมข้อมูลประเมินที่ไม่ได้เป็นเกรดรายวิชา',
    items: [
      { title: 'เกณฑ์คุณลักษณะอันพึงประสงค์', description: 'กำหนดหัวข้อและระดับการประเมินคุณลักษณะของผู้เรียน', state: 'planned' },
      { title: 'คะแนนจากแบบประเมิน', description: 'รวบรวมคะแนนจากแบบประเมินเพื่อประกอบผลการเรียน', state: 'planned' },
    ],
  },
];

const STATUS = {
  ready: { label: 'พร้อมใช้งาน', kind: 'ok' },
  partial: { label: 'ใช้งานได้บางส่วน', kind: 'warn' },
  planned: { label: 'รอพัฒนา', kind: 'info' },
} as const;

export function SubjectDataScreen() {
  const all = GROUPS.flatMap((group) => group.items);
  return <>
    <PageHead title="ข้อมูลวิชา" sub="ตั้งค่าข้อมูลรายวิชา กลุ่มวิชา และเกณฑ์ผลการเรียน" actions={<a href={href('/registry')}>← ศูนย์งานทะเบียน</a>} />
    <div className="registry-summary">
      <Stat title="ข้อมูลทั้งหมด" value={all.length} note="แยกตามหน้าที่ใช้งาน" tone="primary" />
      <Stat title="พร้อมใช้งาน" value={all.filter((item) => item.state === 'ready').length} note="เชื่อมหน้าจอแล้ว" tone="success" />
      <Stat title="รอเติมเต็ม" value={all.filter((item) => item.state !== 'ready').length} note="ไม่ซ่อนข้อจำกัด" tone="warning" />
    </div>
    {GROUPS.map((group) => <section className="registry-section" key={group.title}>
      <div className="registry-section-head"><div><span>{group.subtitle}</span><h3>{group.title}</h3></div><b>{group.items.length} รายการ</b></div>
      <div className="operation-grid">{group.items.map((item) => {
        const status = STATUS[item.state];
        const content = <><div className={`operation-icon ${item.state}`}>{item.path ? '↗' : '◇'}</div><div><strong>{item.title}</strong><p>{item.description}</p><Badge kind={status.kind}>{status.label}</Badge></div><span className="operation-arrow">›</span></>;
        return item.path ? <a className="operation-card" href={href(item.path)} key={item.title}>{content}</a> : <div className="operation-card" key={item.title} aria-disabled="true">{content}</div>;
      })}</div>
    </section>)}
  </>;
}

function Stat({ title, value, note, tone }: { title: string; value: number; note: string; tone: string }) {
  return <div className={`registry-stat ${tone}`}><span>{title}</span><strong>{value}</strong><small>{note}</small></div>;
}

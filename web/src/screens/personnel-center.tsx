import { href, useRoute } from '../core/router';
import { hasRole, useSession, type Role } from '../core/session';
import { Badge, Card, Notice, PageHead } from '../ui/kit';

type State = 'ready' | 'partial' | 'planned';
type Item = { key: string; title: string; desc: string; path?: string; state: State };
const make = (rows: (string | undefined)[][]): Item[] =>
  rows.map(([key, title, desc, path, state]) => ({
    key: key!, title: title!, desc: desc!, path, state: state as State,
  }));

/**
 * ศูนย์บุคลากรแบ่งเป็นฝ่ายตามบทบาทของสถานศึกษา — ครูผู้สอน · วิชาการ ·
 * ทะเบียน · การเงิน · บุคคล · เลขา · กิจการนักศึกษา
 *
 * ─── ทำไมแบ่งเป็นฝ่ายในหน้าเดียว ไม่ใช่หน้าละฝ่าย ───
 * คนหนึ่งมีได้หลายฝ่ายพร้อมกัน (เช่นฝ่ายวิชาการที่สอนด้วย) — session.roles
 * เป็นชุด ไม่ใช่ค่าเดียวตั้งแต่ 0095 แล้ว การ์ดของแต่ละฝ่ายจึงแสดงตาม
 * hasRole() ของฝ่ายนั้น union กันเอง คนที่มีสองฝ่ายเห็นการ์ดของทั้งคู่
 * พร้อมกันในหน้าเดียว ไม่ต้องสลับหน้าไปมา
 *
 * **การซ่อนการ์ดที่นี่คือความสะดวก ไม่ใช่การกันสิทธิ์** — สิทธิ์จริงอยู่ที่
 * `@Roles` ของ API และ RLS ในฐานข้อมูลเสมอ (ดู CLAUDE.md หัวข้อ "หน้าจอ
 * เจ้าหน้าที่") คนที่พิมพ์ URL ปลายทางตรง ๆ โดยไม่มีสิทธิ์ยังต้องได้ 403
 * หรือข้อมูลว่างจากฐานข้อมูล ไม่ใช่ถูกกันที่หน้านี้
 */
interface Dept {
  key: string;
  roles: Role[];
  title: string;
  subtitle: string;
  items: Item[];
}

const DEPARTMENTS: Dept[] = [
  {
    key: 'teacher',
    roles: ['teacher'],
    title: 'ครูผู้สอน',
    subtitle: 'สมุดคะแนน ตารางสอนของตัวเอง และเช็คชื่อ',
    items: make([
      ['gradebook', 'สมุดคะแนนและส่งเกรด', 'บันทึกคะแนนและส่งเกรดของกลุ่มเรียนที่สอน', '/gradebook', 'ready'],
      ['my-schedule', 'ตารางสอนของฉัน', 'ตารางสอนรายสัปดาห์และคาบที่ต้องคุมสอบ', '/my-schedule', 'ready'],
      ['attendance', 'เช็คชื่อรายคาบ', 'บันทึกเวลาเรียนของกลุ่มเรียนที่สอน', '/attendance', 'ready'],
    ]),
  },
  {
    key: 'academic',
    roles: ['academic'],
    title: 'ฝ่ายวิชาการ',
    subtitle: 'หลักสูตร ตารางสอน และงานวิชาการรายปี',
    items: make([
      ['curriculum', 'โครงสร้างหลักสูตร', 'สาขาวิชา หลักสูตร ฉบับ และแผนการเรียน', '/curriculum/programs', 'ready'],
      ['academic-year', 'งานวิชาการรายปี', 'เลื่อนชั้น จัดห้อง และรอบสอบซ่อม', '/academic-year', 'ready'],
      ['timetable-center', 'ศูนย์งานตารางเรียน', 'จัดตารางสอนและห้องเรียน', '/timetable-center', 'ready'],
      ['exam-schedule', 'ตารางสอบ', 'จัดห้องสอบและกรรมการคุมสอบ', '/exam-schedule', 'ready'],
    ]),
  },
  {
    key: 'registrar',
    roles: ['registrar'],
    title: 'งานทะเบียน',
    subtitle: 'ระเบียนนักศึกษา ลงทะเบียน และเอกสาร',
    items: make([
      ['registry', 'ศูนย์งานทะเบียน', 'ระเบียนนักศึกษา ลงทะเบียนเรียน และผลการเรียน', '/registry', 'ready'],
      ['registration', 'ลงทะเบียนเรียน', 'ลงทะเบียนเป็นห้องและติดตามความคืบหน้า', '/registration', 'ready'],
      ['documents', 'ออกเอกสาร', 'ใบ รบ. ใบประกาศนียบัตร และหนังสือรับรอง', '/documents', 'ready'],
      ['graduation', 'สำเร็จการศึกษาและ PVRS', 'ตรวจเกณฑ์การจบและส่งออกไฟล์ สอศ.', '/graduation', 'ready'],
    ]),
  },
  {
    key: 'finance',
    roles: ['finance'],
    title: 'ฝ่ายการเงิน',
    subtitle: 'ค่าธรรมเนียม ใบแจ้งหนี้ และการรับชำระ',
    items: make([
      ['finance-center', 'ศูนย์การเงิน', 'โครงสร้างค่าเทอม ใบแจ้งหนี้ และรับชำระ', '/finance-center', 'ready'],
      ['finance', 'ตั้งค่าและกระทบยอด', 'รายการค่าธรรมเนียม ส่วนลด และกระทบยอดธนาคาร', '/finance', 'ready'],
    ]),
  },
  {
    key: 'hr',
    roles: ['hr'],
    title: 'งานบุคคล',
    subtitle: 'บุคลากร สิทธิ์ ระเบียน และการลา',
    items: make([
      ['personnel-search', 'ค้นหาบุคลากร', 'ค้นหารายชื่อและเปิดแฟ้มประวัติบุคลากรแบบแยกหัวข้อ', '/personnel-search', 'ready'],
      ['hr', 'บุคลากรและการลา', 'ค้นหาบุคลากร มอบ/ถอนบทบาท โครงสร้างหน่วยงาน ระเบียนประวัติ (ทช.1) และใบลา', '/hr', 'ready'],
      ['time-import', 'นำเข้าข้อมูลเวลา', 'รับข้อมูลเวลาปฏิบัติงานจากเครื่องบันทึกเวลา', undefined, 'partial'],
      ['contact', 'ติดต่อบุคลากร', 'สมุดรายชื่อ โทรศัพท์ และอีเมล', undefined, 'partial'],
      ['staff-summary', 'สรุปเวลาทำการ', 'รายงานเวลาปฏิบัติงานรายวันและรายเดือน', undefined, 'partial'],
      ['worktime', 'กำหนดเวลาบุคลากร', 'เวลาเข้าออกและเงื่อนไขการมาสาย', undefined, 'partial'],
    ]),
  },
  {
    key: 'secretary',
    roles: ['secretary'],
    title: 'งานเลขานุการ',
    subtitle: 'หนังสือถึงผู้ปกครอง และประกาศข่าวสาร',
    items: make([
      ['letters', 'หนังสือถึงผู้ปกครอง', 'จดหมายแจ้งขาดเรียน หนังสือเชิญผู้ปกครอง และใบรับรองความประพฤติ', '/letters', 'ready'],
      ['announcements', 'ประกาศ/ข่าวสาร', 'ประกาศถึงนักศึกษาและผู้ปกครอง', '/announcements', 'ready'],
    ]),
  },
  {
    key: 'student_affairs',
    roles: ['student_affairs'],
    title: 'ฝ่ายกิจการนักศึกษา',
    subtitle: 'พฤติกรรม การดูแล และเฝ้าระวัง',
    items: make([
      ['behavior-center', 'ศูนย์งานพฤติกรรม', 'บันทึกพฤติกรรม ผลคัดกรอง และเยี่ยมบ้าน', '/behavior-center', 'ready'],
      ['risk', 'เฝ้าระวังและติดตาม', 'รายชื่อนักศึกษาที่มีความเสี่ยง', '/risk', 'ready'],
      ['leaves', 'การลาของนักศึกษา', 'ยื่น รับรอง และอนุมัติใบลา', '/leaves', 'ready'],
      ['clubs', 'ชมรม/กิจกรรม', 'สมาชิกภาพชมรมและวิชาชุมนุม', '/clubs', 'ready'],
    ]),
  },
  {
    // ผู้อำนวยการ/ผู้ดูแลระบบเห็นภาพรวมทุกฝ่ายในหน้าเดียว — ไม่ต้องมอบบทบาท
    // ย่อยให้ตัวเองเพื่อจะดูงานของฝ่ายอื่น เพราะเป็นข้อมูลระดับวิทยาลัยอยู่แล้ว
    key: 'directorship',
    roles: ['director', 'admin'],
    title: 'ผู้บริหาร',
    subtitle: 'ภาพรวมทุกฝ่ายและการตั้งค่าระดับวิทยาลัย',
    items: make([
      ['settings-center', 'ศูนย์การตั้งค่า', 'นโยบาย ปีการศึกษา และการนำเข้าข้อมูล', '/settings-center', 'ready'],
      ['statistics', 'ข้อมูลสถิติ', 'จำนวนบุคลากร แยกหน่วยงาน ตำแหน่ง และสถานะ', undefined, 'partial'],
    ]),
  },
];

const STATUS = {
  ready: { label: 'พร้อมใช้งาน', kind: 'ok' },
  partial: { label: 'ใช้งานได้บางส่วน', kind: 'warn' },
  planned: { label: 'หน้าต้นแบบ', kind: 'info' },
} as const;

export function PersonnelCenterScreen() {
  const session = useSession();
  const selected = useRoute().query.get('module');

  const visible = DEPARTMENTS.filter((d) => hasRole(session, ...d.roles));
  const all = visible.flatMap((d) => d.items);
  const chosen = all.find((x) => x.key === selected);
  if (chosen && !chosen.path) return <Preview item={chosen} />;

  if (visible.length === 0) {
    return (
      <>
        <PageHead title="ศูนย์บุคลากร" sub="บริหารบุคลากรและงานประจำวันแยกตามฝ่าย" />
        <Notice kind="info">บัญชีนี้ยังไม่ได้รับมอบหมายบทบาทที่มีเมนูในหน้านี้</Notice>
      </>
    );
  }

  return (
    <>
      <PageHead title="ศูนย์บุคลากร" sub="บริหารบุคลากรและงานประจำวันแยกตามฝ่าย — เห็นเฉพาะฝ่ายที่ตัวเองมีสิทธิ์" />
      <div className="registry-summary">
        <Stat t="ฝ่ายที่มีสิทธิ์" v={visible.length} n="จากทั้งหมด 8 กลุ่ม" c="primary" />
        <Stat t="เมนูทั้งหมด" v={all.length} n="หนึ่งการ์ดต่อหนึ่งหน้าจอ" c="success" />
        <Stat t="กำลังเติมเต็ม" v={all.filter((x) => x.state !== 'ready').length} n="บางส่วนและ Mockup" c="warning" />
      </div>
      {visible.map((d) => (
        <section className="registry-section" key={d.key}>
          <div className="registry-section-head">
            <div><span>{d.subtitle}</span><h3>{d.title}</h3></div>
            <b>{d.items.length} เมนู</b>
          </div>
          <div className="operation-grid">
            {d.items.map((x) => {
              const s = STATUS[x.state];
              return (
                <a
                  className="operation-card"
                  href={href(x.path ?? `/personnel-center?module=${x.key}`)}
                  key={x.key}
                >
                  <div className={`operation-icon ${x.state}`}>{x.path ? '↗' : '◇'}</div>
                  <div>
                    <strong>{x.title}</strong>
                    <p>{x.desc}</p>
                    <Badge kind={s.kind}>{s.label}</Badge>
                  </div>
                  <span className="operation-arrow">›</span>
                </a>
              );
            })}
          </div>
        </section>
      ))}
    </>
  );
}

function Stat({ t, v, n, c }: { t: string; v: number; n: string; c: string }) {
  return <div className={`registry-stat ${c}`}><span>{t}</span><strong>{v}</strong><small>{n}</small></div>;
}

function Preview({ item }: { item: Item }) {
  return (
    <>
      <PageHead
        title={item.title}
        sub="โครงหน้าจอสำหรับเชื่อมข้อมูลบุคลากร"
        actions={<a href={href('/personnel-center')}>← กลับ</a>}
      />
      <Notice kind="info">หน้าจอนี้เป็น Mockup ข้อมูลตัวอย่างจะไม่ถูกบันทึกลงฐานข้อมูล</Notice>
      <div className="registry-summary">
        <Stat t="บุคลากรทั้งหมด" v={86} n="ข้อมูลตัวอย่าง" c="primary" />
        <Stat t="ปฏิบัติงาน" v={78} n="สถานะปัจจุบัน" c="success" />
        <Stat t="รอตรวจสอบ" v={8} n="รายการที่ต้องดำเนินการ" c="warning" />
      </div>
      <Card title={`ภาพรวม ${item.title}`}>
        <div className="mock-chart">{[62, 84, 54, 92, 70, 78].map((h, i) => <i key={i} style={{ height: `${h}%` }} />)}</div>
        <p className="hint">{item.desc} ตัวเลขและกราฟเป็น Mockup เพื่อรอเชื่อม API เฉพาะในขั้นถัดไป</p>
      </Card>
    </>
  );
}

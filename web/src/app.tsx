/**
 * โครงหน้าจอและเส้นทาง
 *
 * ─── ทำไมเมนูซ่อนตามบทบาท แต่ไม่ใช่การกันสิทธิ์ ───
 * การซ่อนเมนูมีไว้ให้เจ้าหน้าที่ไม่ต้องมองของที่ตัวเองใช้ไม่ได้เท่านั้น
 * สิทธิ์จริงบังคับที่ `@Roles` ของ API และที่ RLS ในฐานข้อมูล — คนที่พิมพ์
 * URL เองจะเห็นหน้าจอ แต่ข้อมูลจะว่างหรือได้ 403 ซึ่งเป็นพฤติกรรมที่ถูกต้อง
 * ห้ามย้ายการตัดสินใจเรื่องสิทธิ์มาไว้ที่นี่เด็ดขาด
 */
import { ROLE_LABEL, useSession, type Role } from './core/session';
import { href, useRoute } from './core/router';
import { AcademicYearScreen } from './screens/academic-year';
import { AdmissionsScreen } from './screens/admissions';
import { AttendanceScreen } from './screens/attendance';
import { ChangeRequestsScreen } from './screens/change-requests';
import { CurriculumScreen } from './screens/curriculum';
import { DocumentsScreen } from './screens/documents';
import { FinanceScreen } from './screens/finance';
import { GradebookScreen } from './screens/gradebook';
import { GraduationScreen } from './screens/graduation';
import { HrScreen } from './screens/hr';
import { ImportScreen } from './screens/import';
import { JobsScreen } from './screens/jobs';
import { LettersScreen } from './screens/letters';
import { LoginScreen } from './screens/login';
import { RegistrationScreen } from './screens/registration';
import { RiskScreen } from './screens/risk';
import { StudentLeaveScreen } from './screens/student-leave';
import { StudentDetailScreen, StudentsScreen } from './screens/students';
import { TimetableScreen } from './screens/timetable';

interface NavItem {
  path: string;
  label: string;
  roles: Role[];
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const ALL: Role[] = ['registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin', 'teacher'];
const OFFICE: Role[] = ['registrar', 'academic', 'director', 'admin'];

const NAV: NavGroup[] = [
  {
    title: 'งานทะเบียน',
    items: [
      { path: '/students', label: 'ระเบียนนักศึกษา', roles: ALL },
      { path: '/registration', label: 'ลงทะเบียนเรียน', roles: OFFICE },
      { path: '/documents', label: 'ออกเอกสาร', roles: OFFICE },
      { path: '/graduation', label: 'สำเร็จการศึกษา', roles: OFFICE },
      { path: '/admissions', label: 'งานรับสมัคร', roles: OFFICE },
      { path: '/import', label: 'นำเข้าข้อมูล', roles: OFFICE },
    ],
  },
  {
    title: 'การเงิน',
    items: [
      { path: '/finance', label: 'ใบแจ้งหนี้และรับชำระ', roles: ['finance', 'director', 'admin'] },
    ],
  },
  {
    title: 'งานวัดผล',
    items: [
      { path: '/curriculum', label: 'โครงสร้างหลักสูตร', roles: OFFICE },
      { path: '/timetable', label: 'ตารางสอน', roles: OFFICE },
      { path: '/academic-year', label: 'งานวิชาการรายปี', roles: OFFICE },
      { path: '/gradebook', label: 'สมุดคะแนน', roles: ['teacher', 'academic', 'director', 'admin'] },
      { path: '/attendance', label: 'เช็คชื่อรายคาบ', roles: ['teacher', 'registrar', 'academic', 'admin'] },
      {
        path: '/change-requests',
        label: 'คำร้องขอแก้เกรด',
        roles: ['teacher', 'academic', 'registrar', 'director', 'admin'],
      },
    ],
  },
  {
    title: 'ดูแลนักศึกษา',
    items: [
      {
        path: '/risk',
        label: 'เฝ้าระวังและติดตาม',
        roles: ['teacher', 'student_affairs', 'academic', 'director', 'admin'],
      },
      {
        path: '/letters',
        label: 'หนังสือถึงผู้ปกครอง',
        roles: ['student_affairs', 'registrar', 'academic', 'director', 'admin'],
      },
      {
        path: '/leaves',
        label: 'การลาของนักศึกษา',
        // ครูที่ปรึกษาเห็นของเด็กในที่ปรึกษาตัวเอง แต่อนุมัติไม่ได้ —
        // หน้าจอซ่อนปุ่มให้ ส่วนสิทธิ์จริงอยู่ที่ @Roles และ RLS
        roles: ['teacher', 'student_affairs', 'registrar', 'director', 'admin'],
      },
    ],
  },
  {
    title: 'งานบุคคล',
    items: [
      { path: '/hr', label: 'บุคลากรและการลา', roles: ['registrar', 'director', 'admin'] },
    ],
  },
  {
    title: 'ระบบ',
    items: [{ path: '/jobs', label: 'งานตามกำหนดเวลา', roles: ['admin', 'director'] }],
  },
];

export function App() {
  const s = useSession();
  const route = useRoute();

  if (s.stage !== 'ready') return <LoginScreen />;

  const role = s.role;
  const visible = NAV.map((g) => ({
    ...g,
    items: g.items.filter((i) => !role || i.roles.includes(role)),
  })).filter((g) => g.items.length > 0);

  return (
    <div className="shell">
      <nav className="sidebar">
        <h1>ระบบบริหารวิทยาลัย</h1>
        <div className="who">
          {s.username}
          <br />
          {role ? ROLE_LABEL[role] : ''}
        </div>

        {visible.map((g) => (
          <div className="nav-group" key={g.title}>
            <span>{g.title}</span>
            {g.items.map((i) => (
              <a
                key={i.path}
                href={href(i.path)}
                className={route.path.startsWith(i.path) ? 'active' : ''}
              >
                {i.label}
              </a>
            ))}
          </div>
        ))}

        <div className="spacer" />
        <button onClick={() => void s.signOut()}>ออกจากระบบ</button>
      </nav>

      <main className="main">
        <Routes />
      </main>
    </div>
  );
}

function Routes() {
  const { segments } = useRoute();
  const [head, second] = segments;

  if (!head || head === 'students') {
    if (head === 'students' && second) return <StudentDetailScreen id={second} />;
    return <StudentsScreen />;
  }

  if (head === 'registration') return <RegistrationScreen />;
  if (head === 'attendance') return <AttendanceScreen />;
  if (head === 'gradebook') return <GradebookScreen />;
  if (head === 'risk') return <RiskScreen />;
  if (head === 'change-requests') return <ChangeRequestsScreen />;
  if (head === 'documents') return <DocumentsScreen />;
  if (head === 'graduation') return <GraduationScreen />;
  if (head === 'curriculum') return <CurriculumScreen />;
  if (head === 'import') return <ImportScreen />;
  if (head === 'jobs') return <JobsScreen />;
  if (head === 'hr') return <HrScreen />;
  if (head === 'timetable') return <TimetableScreen />;
  if (head === 'admissions') return <AdmissionsScreen />;
  if (head === 'academic-year') return <AcademicYearScreen />;
  if (head === 'finance') return <FinanceScreen />;
  if (head === 'leaves') return <StudentLeaveScreen />;
  if (head === 'letters') return <LettersScreen />;

  return (
    <div className="empty">
      หน้าจอนี้ยังไม่ได้ทำ — ดูรายการที่เหลือใน CLAUDE.md หัวข้อ “หน้าจอเจ้าหน้าที่”
    </div>
  );
}

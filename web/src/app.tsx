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
import { ScopeProvider, useScope } from './core/scope';
import {
  AcademicClassroomScreen, AcademicPlacementScreen, AcademicSectionsScreen, AcademicYearScreen, RemedialScreen,
} from './screens/academic-year';
import { AdmissionsScreen } from './screens/admissions';
import { AttendanceScreen } from './screens/attendance';
import { BehaviorScreen } from './screens/behavior';
import { BehaviorCenterScreen, SUBNAV as SUB_BEHAVIOR } from './screens/behavior-center';
import { ChangeRequestsScreen } from './screens/change-requests';
import { ClubsScreen } from './screens/clubs';
import { CurriculumScreen } from './screens/curriculum';
import { CurriculumLibraryScreen } from './screens/curriculum-library';
import { DocumentsScreen } from './screens/documents';
import { EducationLevelsScreen } from './screens/education-levels';
import { DualScreen } from './screens/dual';
import { ExamScheduleScreen } from './screens/exam-schedule';
import { FinanceScreen } from './screens/finance';
import { FinanceCenterScreen, SUBNAV as SUB_FINANCE } from './screens/finance-center';
import { GradebookScreen } from './screens/gradebook';
import { GradeLevelsScreen } from './screens/grade-levels';
import { GraduationScreen } from './screens/graduation';
import { GovernmentExportsScreen } from './screens/government-exports';
import { HrScreen } from './screens/hr';
import { ImportScreen } from './screens/import';
import { JobsScreen } from './screens/jobs';
import { LettersScreen } from './screens/letters';
import { LoginScreen } from './screens/login';
import { MyScheduleScreen } from './screens/my-schedule';
import { OnetScreen } from './screens/onet';
import { PersonnelCenterScreen, SUBNAV as SUB_PERSONNEL } from './screens/personnel-center';
import { PersonnelSearchScreen } from './screens/personnel-search';
import { PeriodsScreen } from './screens/periods';
import { RegistrationScreen } from './screens/registration';
import { RegistryCenterScreen, SUBNAV as SUB_REGISTRY } from './screens/registry-center';
import { RiskScreen } from './screens/risk';
import { StudentLeaveScreen } from './screens/student-leave';
import { SettingsCenterScreen, SUBNAV as SUB_SETTINGS } from './screens/settings-center';
import { StatisticsScreen } from './screens/statistics';
import { GradeReportsScreen } from './screens/grade-reports';
import { StudentDetailScreen, StudentsScreen } from './screens/students';
import { AdvisorsScreen } from './screens/advisors';
import { StudentCenterScreen, SUBNAV as SUB_STUDENT } from './screens/student-center';
import { SubjectDataScreen } from './screens/subject-data';
import { SubjectGroupsScreen } from './screens/subject-groups';
import { CompetenciesScreen } from './screens/competencies';
import { AnnouncementsScreen } from './screens/announcements';
import { TermCategoriesScreen } from './screens/term-categories';
import { TimetableScreen } from './screens/timetable';
import { TimetableCenterScreen, SUBNAV as SUB_TIMETABLE } from './screens/timetable-center';
import { WorkloadScreen } from './screens/workload';

interface NavItem {
  path: string;
  label: string;
  roles: Role[];
}

const NAV_ICON: Record<string, string> = {
  '/registry': '▦',
  '/student-center': '♙',
  '/personnel-center': '♙',
  '/timetable-center': '◷',
  '/settings-center': '⚙',
  '/behavior-center': '♢',
  '/finance': '฿',
  '/finance-center': '฿',
};

/**
 * เมนูย่อยของแต่ละศูนย์ — แสดงใต้ศูนย์ที่กำลังทำงานอยู่ในแถบซ้าย แบบเดียวกับ
 * SISA ที่เมนูของหมวดค้างอยู่ด้านข้างตลอด ทุกฟังก์ชันของหมวดจึงห่างกันแค่คลิกเดียว
 * และไม่ต้องพึ่งปุ่ม "← กลับ" ซึ่งเดิมแต่ละหน้าเขียนเองคนละแบบ และบางหน้า
 * พากลับไปศูนย์ที่ผู้ใช้ไม่ได้มาจาก (เช่นเข้า /finance จากศูนย์นักศึกษา
 * แต่ปุ่มกลับพาไปศูนย์อื่น)
 */
const SUBNAV: Record<string, { path: string; label: string; roles?: Role[] }[]> = {
  '/registry': SUB_REGISTRY,
  '/student-center': SUB_STUDENT,
  '/personnel-center': SUB_PERSONNEL,
  '/timetable-center': SUB_TIMETABLE,
  '/settings-center': SUB_SETTINGS,
  '/behavior-center': SUB_BEHAVIOR,
  '/finance-center': SUB_FINANCE,
};

const LAST_CENTER = 'vecsms.lastCenter';

/** หน้าเดียวกันอยู่ได้หลายศูนย์ (เช่น /finance) — ยึดศูนย์ที่ผู้ใช้เพิ่งเข้ามาก่อน */
function activeCenter(path: string, centers: string[]): string | undefined {
  const own = (c: string) => path === c || path.startsWith(c + '/') ||
    SUBNAV[c]?.some((x) => path === x.path || path.startsWith(x.path + '/'));
  if (centers.includes(path)) {
    try { sessionStorage.setItem(LAST_CENTER, path); } catch { /* เบราว์เซอร์ปิด storage — ใช้ตัวแรกที่เจอแทน */ }
    return path;
  }
  let last: string | null = null;
  try { last = sessionStorage.getItem(LAST_CENTER); } catch { /* ข้าม */ }
  if (last && centers.includes(last) && own(last)) return last;
  return centers.find(own);
}

function subLabel(center: string, path: string): string | undefined {
  const items = SUBNAV[center] ?? [];
  return [...items].sort((a, b) => b.path.length - a.path.length)
    .find((x) => path === x.path || path.startsWith(x.path + '/'))?.label;
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const ALL: Role[] = [
  'registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin',
  'secretary', 'hr', 'teacher',
];

/**
 * เมนูซ้ายเหลือแค่ทางเข้า "ศูนย์งาน" ทั้งห้า + การเงิน — ทุกหน้าจอจริงยังอยู่
 * ที่เดิม (`Routes()` ด้านล่างไม่ได้แตะ) แค่ทางเข้าเปลี่ยนจาก "มีสองทางไปที่
 * เดียวกัน" (ลิงก์ตรงในเมนูซ้าย ซ้ำกับการ์ดในหน้าศูนย์งาน) เหลือทางเดียว
 * ผ่านการ์ดในแต่ละศูนย์งาน — ยกเว้นการเงินที่ไม่มีศูนย์งานของตัวเอง และ
 * ไม่มีศูนย์งานไหนที่บทบาท finance มองเห็นเลย (เช็คสิทธิ์ทีละศูนย์แล้ว)
 * จึงต้องมีทางเข้าตรงไว้ มิฉะนั้นงานการเงินจะเข้าระบบไม่ได้เลย
 */
const NAV: NavGroup[] = [
  {
    title: 'เมนูหลัก',
    items: [
      { path: '/registry', label: 'ศูนย์งานทะเบียน', roles: ALL },
      { path: '/student-center', label: 'ศูนย์นักศึกษา', roles: ['registrar', 'academic', 'student_affairs', 'director', 'admin'] },
      // ALL เพราะหน้านี้แบ่งเป็นการ์ดตามฝ่ายเอง (ครู/วิชาการ/ทะเบียน/การเงิน/
      // บุคคล/เลขา/กิจการนักศึกษา) — ใครมีบทบาทไหนเห็นการ์ดฝ่ายนั้น ไม่ใช่
      // ทั้งหน้าเปิด-ปิดตามบทบาทเดียว (ดูเหตุผลเต็มในตัวหน้าจอเอง)
      { path: '/personnel-center', label: 'ศูนย์บุคลากร', roles: ALL },
      { path: '/timetable-center', label: 'ศูนย์งานตารางเรียน', roles: ['teacher', 'registrar', 'academic', 'director', 'admin'] },
      { path: '/settings-center', label: 'ศูนย์การตั้งค่า', roles: ['registrar', 'academic', 'director', 'admin'] },
      { path: '/behavior-center', label: 'ศูนย์งานพฤติกรรม', roles: ['teacher', 'student_affairs', 'academic', 'director', 'admin'] },
    ],
  },
  {
    title: 'การเงิน',
    items: [
      { path: '/finance-center', label: 'ศูนย์การเงิน', roles: ['finance', 'director', 'admin'] },
    ],
  },
];

export function App() {
  const s = useSession();
  const route = useRoute();

  if (s.stage !== 'ready') return <LoginScreen />;

  const role = s.role;
  const roles = s.roles;
  // .some แทน .includes(role) เดี่ยว — คนที่มีหลายบทบาทซ้อนกัน (เช่น
  // วิชาการที่สอนด้วย) ต้องเห็นเมนูของทุกบทบาทที่ตัวเองมีพร้อมกัน ไม่ใช่
  // แค่บทบาทหลักที่ระบบเลือกให้
  const visible = NAV.map((g) => ({
    ...g,
    items: g.items.filter((i) => roles.length === 0 || i.roles.some((r) => roles.includes(r))),
  })).filter((g) => g.items.length > 0);

  const center = activeCenter(route.path, visible.flatMap((g) => g.items.map((i) => i.path)));
  const centerLabel = visible.flatMap((g) => g.items).find((i) => i.path === center)?.label;
  const pageLabel = center && route.path !== center ? subLabel(center, route.path) : undefined;

  return (
    <ScopeProvider>
      <div className="shell">
        <nav className="sidebar">
          <h1><span className="brand-mark">✦</span><span>VEC SCHOOL</span></h1>
          <div className="who">
            <span className="avatar">{(s.username ?? '?').slice(0, 1).toUpperCase()}</span>
            <span><strong>{s.username}</strong><small>{role ? ROLE_LABEL[role] : ''}</small></span>
          </div>

          {visible.map((g) => (
            <div className="nav-group" key={g.title}>
              <span>{g.title}</span>
              {g.items.map((i) => (
                <div key={i.path}>
                  <a href={href(i.path)} className={center === i.path ? 'active' : ''}>
                    <span className="nav-icon">{NAV_ICON[i.path] ?? '•'}</span>{i.label}
                  </a>
                  {center === i.path && (
                    <div className="subnav">
                      {(SUBNAV[i.path] ?? [])
                        .filter((x) => !Object.prototype.hasOwnProperty.call(SUBNAV, x.path))
                        .filter((x) => !x.roles || roles.length === 0 || x.roles.some((r) => roles.includes(r)))
                        .filter((x, n, all) => all.findIndex((y) => y.path === x.path) === n)
                        .map((x) => (
                          <a key={x.path} href={href(x.path)} className={route.path === x.path || route.path.startsWith(x.path + '/') ? 'active' : ''}>{x.label}</a>
                        ))}
                    </div>
                  )}
                </div>
              ))}
            </div>
          ))}

          <div className="spacer" />
          <button onClick={() => void s.signOut()}>ออกจากระบบ</button>
        </nav>

        <main className="main">
          <header className="topbar">
            <div><strong>แดชบอร์ดวิทยาลัย</strong><small>จัดการข้อมูลและติดตามงานได้ในที่เดียว</small></div>
            <ScopeSelect />
            <label className="global-search"><span>⌕</span><input aria-label="ค้นหาในระบบ" placeholder="ค้นหาในระบบ" /></label>
            <button className="icon-button" aria-label="การแจ้งเตือน">♢</button>
            <span className="top-avatar">{(s.username ?? '?').slice(0, 1).toUpperCase()}</span>
          </header>
          <div className="page-content">
            {center && route.path !== center && (
              <nav className="crumbs" aria-label="ตำแหน่งปัจจุบัน">
                <a href={href(center)}>{centerLabel}</a>
                {pageLabel && <><span>›</span><b>{pageLabel}</b></>}
              </nav>
            )}
            <Routes />
          </div>
        </main>
      </div>
    </ScopeProvider>
  );
}

/**
 * เลือกปีการศึกษาและภาคเรียนที่ด้านบน — เลือกครั้งเดียวมีผลกับทุกหน้าจอ
 * ที่อ่านจาก `useScope()` แทนการมีดรอปดาวน์ของตัวเองแยกแต่ละหน้า
 */
function ScopeSelect() {
  const scope = useScope();
  if (scope.years.length === 0) return null;

  return (
    <div className="scope-select">
      <select
        aria-label="ปีการศึกษา"
        value={scope.yearId}
        onChange={(e) => scope.setYearId(e.target.value)}
      >
        {scope.years.map((y) => <option key={y.id} value={y.id}>ปีการศึกษา {y.year_be}</option>)}
      </select>
      <select
        aria-label="ภาคเรียน"
        value={scope.termId}
        onChange={(e) => scope.setTermId(e.target.value)}
      >
        {scope.termsInYear.length === 0 && <option value="">ไม่มีภาคเรียน</option>}
        {scope.termsInYear.map((t) => <option key={t.id} value={t.id}>ภาคเรียนที่ {t.ordinal}</option>)}
      </select>
    </div>
  );
}

function Routes() {
  const { segments } = useRoute();
  const [head, second] = segments;

  if (!head) return <RegistryCenterScreen />;
  if (head === 'students') {
    if (second) return <StudentDetailScreen id={second} />;
    return <StudentsScreen />;
  }

  if (head === 'registry') return <RegistryCenterScreen />;
  if (head === 'subject-data') return <SubjectDataScreen />;
  if (head === 'subject-groups') return <SubjectGroupsScreen />;
  if (head === 'competencies') return <CompetenciesScreen />;
  if (head === 'announcements') return <AnnouncementsScreen />;
  if (head === 'student-center') return <StudentCenterScreen />;
  if (head === 'personnel-center') return <PersonnelCenterScreen />;
  if (head === 'personnel-search') return <PersonnelSearchScreen staffId={second} />;
  if (head === 'periods') return <PeriodsScreen />;
  if (head === 'timetable-center') return <TimetableCenterScreen />;
  if (head === 'settings-center') return <SettingsCenterScreen />;
  if (head === 'behavior-center') return <BehaviorCenterScreen />;
  if (head === 'registration') return <RegistrationScreen />;
  if (head === 'attendance') return <AttendanceScreen />;
  if (head === 'gradebook') return <GradebookScreen />;
  if (head === 'grade-levels') return <GradeLevelsScreen />;
  if (head === 'term-categories') return <TermCategoriesScreen />;
  if (head === 'risk') return <RiskScreen />;
  if (head === 'change-requests') return <ChangeRequestsScreen />;
  if (head === 'documents') return <DocumentsScreen />;
  if (head === 'education-levels') return <EducationLevelsScreen />;
  if (head === 'graduation') return <GraduationScreen />;
  if (head === 'curriculum') {
    if (second === 'programs') return <CurriculumScreen mode="programs" />;
    if (second === 'versions') return <CurriculumScreen mode="versions" />;
    if (second === 'plan') return <CurriculumScreen mode="plan" />;
    if (second === 'courses') return <CurriculumScreen mode="courses" />;
    // ไม่มีการ์ดเมนูรวมของ /curriculum เปล่า ๆ อีกแล้ว — ศูนย์การตั้งค่า
    // ชี้ตรงมาที่โหมดที่ต้องการอยู่แล้ว (ดู settings-center.tsx)
  }
  if (head === 'curriculum-library') return <CurriculumLibraryScreen />;
  if (head === 'import') return <ImportScreen />;
  if (head === 'government-exports') return <GovernmentExportsScreen />;
  if (head === 'jobs') return <JobsScreen />;
  if (head === 'hr') return <HrScreen />;
  if (head === 'timetable') return <TimetableScreen />;
  if (head === 'my-schedule') return <MyScheduleScreen />;
  if (head === 'admissions') return <AdmissionsScreen />;
  if (head === 'academic-year') {
    if (second === 'classes') return <AcademicClassroomScreen />;
    if (second === 'placements') return <AcademicPlacementScreen />;
    if (second === 'sections') return <AcademicSectionsScreen />;
    if (second === 'remedial') return <RemedialScreen />;
    return <AcademicYearScreen />;
  }
  if (head === 'finance') return <FinanceScreen />;
  if (head === 'finance-center') return <FinanceCenterScreen />;
  if (head === 'leaves') return <StudentLeaveScreen />;
  if (head === 'letters') return <LettersScreen />;
  if (head === 'behavior') return <BehaviorScreen />;
  if (head === 'dual') return <DualScreen />;
  if (head === 'exam-schedule') return <ExamScheduleScreen />;
  if (head === 'workload') return <WorkloadScreen />;
  if (head === 'advisors') return <AdvisorsScreen />;
  if (head === 'statistics') return <StatisticsScreen />;
  if (head === 'grade-reports') return <GradeReportsScreen />;
  if (head === 'clubs') return <ClubsScreen />;
  if (head === 'onet') return <OnetScreen />;

  return (
    <div className="empty">
      หน้าจอนี้ยังไม่ได้ทำ — ดูรายการที่เหลือใน CLAUDE.md หัวข้อ “หน้าจอเจ้าหน้าที่”
    </div>
  );
}

/**
 * เซสชันของเจ้าหน้าที่
 *
 * ─── ทำไมต้องรองรับ MFA ตั้งแต่หน้าจอแรก ───
 * `auth_policy.require_mfa_roles` ค่าเริ่มต้นคือ {admin, director} ซึ่งเป็น
 * บทบาทที่เห็นข้อมูลทั้งวิทยาลัย คนกลุ่มนั้นจะได้ challenge token เสมอ
 * และถ้าหน้าจอไม่มีทางตั้งค่า MFA ให้ **ผู้ดูแลจะเข้าระบบไม่ได้เลยสักทาง**
 * ซึ่งเป็นวงจรปิดที่เคยเกิดมาแล้วฝั่ง API (ดูข้อ 6 ใน CLAUDE.md)
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { api, hasToken, INSTITUTION_ID, setTokens, setUnauthorizedHandler } from './api';

export type Role =
  | 'registrar' | 'academic' | 'finance' | 'student_affairs'
  | 'director' | 'admin' | 'secretary' | 'hr'
  | 'teacher' | 'student' | 'guardian';

/** บทบาทที่หน้าจอชุดนี้รองรับ — นักศึกษาและผู้ปกครองใช้แอป Flutter แยก */
export const STAFF_ROLES: Role[] = [
  'registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin',
  'secretary', 'hr', 'teacher',
];

export const ROLE_LABEL: Record<Role, string> = {
  registrar: 'งานทะเบียน',
  academic: 'ฝ่ายวิชาการ',
  finance: 'ฝ่ายการเงิน',
  student_affairs: 'ฝ่ายกิจการนักศึกษา',
  director: 'ผู้อำนวยการ',
  admin: 'ผู้ดูแลระบบ',
  secretary: 'งานเลขานุการ',
  hr: 'งานบุคคล',
  teacher: 'ครูผู้สอน',
  student: 'นักศึกษา',
  guardian: 'ผู้ปกครอง',
};

interface TokenResponse {
  accessToken: string;
  refreshToken: string;
  expiresInSeconds: number;
  role: Role;
  /** ชุดบทบาททั้งหมดที่มีผลจริง — คนที่มีหลายฝ่ายเห็นเมนูของทุกฝ่ายพร้อมกัน */
  roles: Role[];
  mustChangePassword?: boolean;
}

interface ChallengeResponse {
  mfaRequired: true;
  enrollmentRequired: boolean;
  challengeToken: string;
  mustChangePassword?: boolean;
  role?: Role;
  roles?: Role[];
}

type LoginResponse = TokenResponse | ChallengeResponse;

const isChallenge = (r: LoginResponse): r is ChallengeResponse =>
  (r as ChallengeResponse).mfaRequired === true;

/** ขั้นที่หน้าจอกำลังอยู่ — ตัวนี้เป็นตัวตัดสินว่าจะแสดงอะไร */
export type Stage =
  | 'anonymous'      // ยังไม่ล็อกอิน
  | 'mfa'            // ล็อกอินผ่านแล้ว รอรหัสหกหลัก
  | 'mfa-enroll'     // ต้องผูกแอป authenticator ก่อนครั้งแรก
  | 'must-change'    // ต้องเปลี่ยนรหัสผ่านก่อนใช้งาน
  | 'ready';

export interface SessionState {
  stage: Stage;
  /** บทบาทหลัก (แรงที่สุด) — เหลือไว้ให้จุดที่ยังอ้างค่าเดียว เช่นป้ายแสดงผล */
  role: Role | null;
  /** ชุดบทบาททั้งหมดที่มีผลจริง — ใช้ตรวจสิทธิ์เมนู/การ์ดแทน role เดี่ยวเสมอ */
  roles: Role[];
  username: string | null;
  /** ใช้ตอนขั้น mfa/mfa-enroll เท่านั้น */
  challengeToken: string | null;
  enrollUri: string | null;
}

interface SessionApi extends SessionState {
  signIn: (username: string, password: string) => Promise<void>;
  verifyMfa: (code: string) => Promise<void>;
  startEnroll: () => Promise<void>;
  confirmEnroll: (code: string) => Promise<void>;
  changePassword: (current: string, next: string) => Promise<void>;
  signOut: () => Promise<void>;
}

/** ผู้ใช้ถือบทบาทใดบทบาทหนึ่งในรายการนี้อยู่หรือไม่ — ใช้แทนการเทียบ role === x ตรง ๆ */
export function hasRole(s: Pick<SessionState, 'roles'>, ...roles: Role[]): boolean {
  return s.roles.some((r) => roles.includes(r));
}

const Ctx = createContext<SessionApi | null>(null);

export function useSession(): SessionApi {
  const s = useContext(Ctx);
  if (!s) throw new Error('useSession ต้องอยู่ภายใต้ SessionProvider');
  return s;
}

const ROLE_KEY = 'vecsms.role';
const ROLES_KEY = 'vecsms.roles';
const USER_KEY = 'vecsms.username';

function readStoredRoles(): Role[] {
  try {
    const raw = sessionStorage.getItem(ROLES_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Role[];
      if (Array.isArray(parsed) && parsed.length) return parsed;
    }
  } catch {
    // ค่าที่เก็บไว้เพี้ยน — ตกไปใช้ role เดี่ยวด้านล่าง
  }
  const single = sessionStorage.getItem(ROLE_KEY) as Role | null;
  return single ? [single] : [];
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SessionState>(() => ({
    // มี token ค้างอยู่แปลว่าเพิ่งรีเฟรชหน้า ไม่ใช่เข้าใหม่
    stage: hasToken() ? 'ready' : 'anonymous',
    role: (sessionStorage.getItem(ROLE_KEY) as Role | null) ?? null,
    roles: readStoredRoles(),
    username: sessionStorage.getItem(USER_KEY),
    challengeToken: null,
    enrollUri: null,
  }));

  const reset = useCallback(() => {
    setTokens(null, null);
    sessionStorage.removeItem(ROLE_KEY);
    sessionStorage.removeItem(ROLES_KEY);
    sessionStorage.removeItem(USER_KEY);
    setState({
      stage: 'anonymous', role: null, roles: [], username: null,
      challengeToken: null, enrollUri: null,
    });
  }, []);

  // token หมดอายุกลางคันแล้วต่ออายุไม่สำเร็จ — พากลับหน้าล็อกอินทันที
  useEffect(() => setUnauthorizedHandler(reset), [reset]);

  const land = useCallback((t: TokenResponse, username: string) => {
    setTokens(t.accessToken, t.refreshToken);
    const roles = t.roles?.length ? t.roles : [t.role];
    sessionStorage.setItem(ROLE_KEY, t.role);
    sessionStorage.setItem(ROLES_KEY, JSON.stringify(roles));
    sessionStorage.setItem(USER_KEY, username);
    setState({
      stage: t.mustChangePassword ? 'must-change' : 'ready',
      role: t.role,
      roles,
      username,
      challengeToken: null,
      enrollUri: null,
    });
  }, []);

  const signIn = useCallback(
    async (username: string, password: string) => {
      const res = await api.withToken<LoginResponse>(
        'POST',
        '/auth/login',
        { institutionId: INSTITUTION_ID, username, password },
        null,
      );

      if (isChallenge(res)) {
        sessionStorage.setItem(USER_KEY, username);
        setState({
          stage: res.enrollmentRequired ? 'mfa-enroll' : 'mfa',
          role: res.role ?? null,
          roles: res.roles?.length ? res.roles : res.role ? [res.role] : [],
          username,
          challengeToken: res.challengeToken,
          enrollUri: null,
        });
        return;
      }
      land(res, username);
    },
    [land],
  );

  const verifyMfa = useCallback(
    async (code: string) => {
      const t = await api.withToken<TokenResponse>(
        'POST',
        '/auth/mfa/verify',
        { challengeToken: state.challengeToken, code },
        null,
      );
      land(t, state.username ?? '');
    },
    [land, state.challengeToken, state.username],
  );

  /*
   * เส้นทางตั้งค่า MFA ติด @AllowMfaChallenge ไว้โดยตั้งใจ จึงเรียกด้วย
   * challenge token ได้ — ถ้าไม่ได้ ผู้ดูแลคนแรกของวิทยาลัยจะไม่มีทางเข้าระบบ
   */
  const startEnroll = useCallback(async () => {
    const r = await api.withToken<{ otpauthUri: string }>(
      'POST',
      '/auth/mfa/enroll',
      {},
      state.challengeToken,
    );
    setState((s) => ({ ...s, enrollUri: r.otpauthUri }));
  }, [state.challengeToken]);

  const confirmEnroll = useCallback(
    async (code: string) => {
      // confirm คืน token จริงเลย ไม่ต้องล็อกอินใหม่
      const t = await api.withToken<TokenResponse>(
        'POST',
        '/auth/mfa/confirm',
        { code },
        state.challengeToken,
      );
      land(t, state.username ?? '');
    },
    [land, state.challengeToken, state.username],
  );

  const changePassword = useCallback(async (current: string, next: string) => {
    await api.post('/auth/change-password', { currentPassword: current, newPassword: next });
    setState((s) => ({ ...s, stage: 'ready' }));
  }, []);

  const signOut = useCallback(async () => {
    try {
      await api.post('/auth/logout', {});
    } catch {
      // ออกจากระบบฝั่งเครื่องให้สำเร็จเสมอ แม้เซิร์ฟเวอร์จะตอบไม่ได้
    }
    reset();
  }, [reset]);

  const value = useMemo<SessionApi>(
    () => ({ ...state, signIn, verifyMfa, startEnroll, confirmEnroll, changePassword, signOut }),
    [state, signIn, verifyMfa, startEnroll, confirmEnroll, changePassword, signOut],
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

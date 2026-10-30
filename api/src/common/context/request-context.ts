import { AsyncLocalStorage } from 'node:async_hooks';

/**
 * บริบทของผู้ใช้ที่ทำคำขอนี้
 *
 * ค่าสามตัวนี้คือสิ่งที่ Row-Level Security ทั้งหมดในฐานข้อมูลอ่าน
 * ถ้าไม่ส่งไป ทุก query จะคืนศูนย์แถว ซึ่งเป็นพฤติกรรมที่ตั้งใจ
 * ล้มเหลวแบบปิดไว้ก่อน ดีกว่าเผลอเปิดข้อมูลออกไป
 */
export interface UserContext {
  /** สถานศึกษาที่ผู้ใช้สังกัด — ขอบเขตการแยกข้อมูลชั้นแรก */
  institutionId: string;
  /** person_id ของผู้ใช้ ไม่ใช่ student_id หรือ staff_id */
  actorId: string;
  /** บทบาทหลัก (แรงที่สุด) — registrar | academic | finance | student_affairs | director | admin | teacher | student | guardian */
  role: AppRole;
  /**
   * ชุดบทบาททั้งหมดที่มีผลจริง (มาจาก login_roles_for() ไม่ใช่แค่ role เดียว)
   * ใช้ตั้ง app.roles ให้ RLS ที่รองรับหลายบทบาทซ้อนกัน (current_app_roles())
   * — ไม่ลบ role เดี่ยวด้านบน เพราะจุดอื่นที่ยังอ้างค่าเดียวยังต้องใช้ได้
   *
   * เป็น optional เพราะบริบทเบื้องหลัง (jobs, provisioning, platform, auth
   * ระหว่างล็อกอิน) ยังสร้าง UserContext ด้วยบทบาทเดียวอยู่ — DbService
   * เติมให้เป็น [role] เองถ้าไม่ได้ระบุ ไม่ต้องแก้จุดเหล่านั้นทั้งหมด
   */
  roles?: AppRole[];
  /** ใช้ในบันทึกการตรวจสอบเท่านั้น ไม่ได้ส่งลงฐานข้อมูล */
  requestId?: string;
  /**
   * บริบทนี้มาจาก token ที่ยังไม่ผ่านการยืนยันตัวตนสองชั้น
   *
   * ตั้งได้เฉพาะเส้นทางที่ติด @AllowMfaChallenge() ไว้ ซึ่งมีแค่ขั้นตอน
   * ตั้งค่า MFA เท่านั้น เส้นทางเหล่านั้นอ่านค่านี้เพื่อรู้ว่าต้องออก token
   * จริงให้ตอนตั้งค่าเสร็จ (ผู้ใช้พิสูจน์ทั้งรหัสผ่านและรหัสจากแอปแล้ว)
   */
  mfaPending?: boolean;
}

export type AppRole =
  | 'registrar'
  | 'academic'
  | 'finance'
  | 'student_affairs'
  | 'director'
  | 'admin'
  | 'secretary'
  | 'hr'
  | 'teacher'
  | 'student'
  | 'guardian';

/** บทบาทที่เห็นข้อมูลได้ทั้งสถานศึกษา ตรงกับ is_institution_wide_role() ในฐานข้อมูล */
export const INSTITUTION_WIDE_ROLES: AppRole[] = [
  'registrar',
  'academic',
  'finance',
  'student_affairs',
  'director',
  'admin',
];

const storage = new AsyncLocalStorage<UserContext>();

export const RequestContext = {
  /** เรียกครอบการทำงานทั้งหมดของหนึ่งคำขอ */
  run<T>(ctx: UserContext, fn: () => T): T {
    return storage.run(ctx, fn);
  },

  /** คืน undefined ถ้าอยู่นอกคำขอ เช่นตอน bootstrap หรือ cron */
  get(): UserContext | undefined {
    return storage.getStore();
  },
};

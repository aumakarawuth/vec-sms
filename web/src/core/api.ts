/**
 * ตัวเรียก API — บางที่สุดเท่าที่จะทำได้
 *
 * ─── ทำไมไม่ใช้ไลบรารีดึงข้อมูล ───
 * ทั้งระบบมีรูปแบบเดียวคือ REST + Bearer token และข้อความผิดพลาดภาษาไทย
 * ไหลมาจากฐานข้อมูลตรง ๆ อยู่แล้ว สิ่งที่ไลบรารีให้เพิ่มคือแคชกับ retry
 * ซึ่งทั้งสองอย่างเป็นสิ่งที่**ไม่ควรมี**ในหน้าจองานทะเบียน — ข้อมูลที่ค้าง
 * อยู่หนึ่งรอบแปลว่าเจ้าหน้าที่ตัดสินใจจากตัวเลขเก่า และการ retry อัตโนมัติ
 * กับคำสั่งที่ไม่ idempotent (ออกเอกสาร ลงทะเบียน) ทำให้เกิดรายการซ้ำ
 */

/** โดเมนของ API — ตั้งตอน build เหมือนที่แอป Flutter ใช้ --dart-define */
export const API_BASE: string =
  import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000/api/v1';

/**
 * วิทยาลัยที่หน้าจอชุดนี้ให้บริการ
 *
 * ตั้งตอน build เหมือนแอปนักศึกษา เพราะวิทยาลัยหนึ่งแห่ง deploy หน้าจอ
 * ของตัวเองหนึ่งชุด — ไม่มีหน้าจอเลือกวิทยาลัยตอนล็อกอินโดยตั้งใจ
 * มิฉะนั้นหน้าล็อกอินจะกลายเป็นรายชื่อลูกค้าทั้งหมดของผู้ให้บริการ
 */
export const INSTITUTION_ID: string =
  import.meta.env.VITE_INSTITUTION_ID ?? '11111111-1111-1111-1111-111111111111';

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly body?: unknown,
  ) {
    super(message);
  }
}

/** ข้อความผิดพลาดจาก Nest มาได้ทั้งสตริงเดี่ยวและอาร์เรย์ (ValidationPipe) */
function readMessage(body: unknown, status: number): string {
  if (typeof body === 'object' && body !== null && 'message' in body) {
    const m = (body as { message: unknown }).message;
    if (typeof m === 'string') return m;
    if (Array.isArray(m)) return m.join(' · ');
  }
  if (status === 401) return 'เซสชันหมดอายุหรือไม่มีสิทธิ์ — เข้าสู่ระบบใหม่';
  if (status === 403) return 'บทบาทของคุณไม่มีสิทธิ์ทำรายการนี้';
  if (status === 404) return 'ไม่พบข้อมูลที่ต้องการ';
  if (status >= 500) return 'ระบบขัดข้อง ลองใหม่อีกครั้ง';
  return `คำขอไม่สำเร็จ (${status})`;
}

/*
 * ─── ทำไมเก็บ token ใน sessionStorage ไม่ใช่ localStorage ───
 * เครื่องที่งานทะเบียนใช้เป็นเครื่องกลางที่หลายคนนั่งสลับกัน localStorage
 * อยู่ข้ามการปิดเบราว์เซอร์ แปลว่าคนถัดไปที่เปิดหน้านี้เข้าเป็นคนก่อนหน้าได้เลย
 * sessionStorage หายเมื่อปิดแท็บ ซึ่งใกล้เคียงกับ "ลุกจากโต๊ะแล้วหลุด" มากกว่า
 *
 * ไม่เก็บในหน่วยความจำอย่างเดียวเพราะเจ้าหน้าที่กด F5 ระหว่างวันบ่อยมาก
 * การหลุดทุกครั้งที่รีเฟรชจะทำให้คนเลี่ยงไปใช้วิธีที่แย่กว่า เช่นไม่ล็อกเอาต์เลย
 */
const ACCESS_KEY = 'vecsms.access';
const REFRESH_KEY = 'vecsms.refresh';

let accessToken: string | null = sessionStorage.getItem(ACCESS_KEY);
let refreshToken: string | null = sessionStorage.getItem(REFRESH_KEY);

export function setTokens(access: string | null, refresh?: string | null): void {
  accessToken = access;
  if (access) sessionStorage.setItem(ACCESS_KEY, access);
  else sessionStorage.removeItem(ACCESS_KEY);

  if (refresh !== undefined) {
    refreshToken = refresh;
    if (refresh) sessionStorage.setItem(REFRESH_KEY, refresh);
    else sessionStorage.removeItem(REFRESH_KEY);
  }
}

export function hasToken(): boolean {
  return accessToken !== null;
}

/** เรียกเมื่อ token หมดอายุกลางคัน — ให้ชั้นบนพากลับไปหน้าล็อกอิน */
let onUnauthorized: (() => void) | null = null;
export function setUnauthorizedHandler(fn: () => void): void {
  onUnauthorized = fn;
}

type Method = 'GET' | 'POST' | 'PATCH' | 'DELETE';

async function raw(method: Method, path: string, body?: unknown, token?: string | null) {
  const headers: Record<string, string> = {};
  if (body !== undefined) headers['content-type'] = 'application/json';

  const bearer = token === undefined ? accessToken : token;
  if (bearer) headers.authorization = `Bearer ${bearer}`;

  const res = await fetch(API_BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  const text = await res.text();
  let parsed: unknown = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }
  }
  return { res, parsed };
}

/**
 * ต่ออายุ token เมื่อได้ 401 แล้วยิงซ้ำหนึ่งครั้ง
 *
 * token ของระบบนี้มีอายุ 30 นาทีตาม `auth_policy.access_token_minutes`
 * ซึ่งสั้นกว่าช่วงเวลาที่เจ้าหน้าที่นั่งทำงานต่อเนื่องมาก ถ้าไม่ต่ออายุให้
 * ระบบจะเด้งออกกลางการกรอกข้อมูลเป็นประจำ แล้วงานที่พิมพ์ค้างไว้หายทุกครั้ง
 */
let refreshing: Promise<boolean> | null = null;

async function tryRefresh(): Promise<boolean> {
  if (!refreshToken) return false;
  if (refreshing) return refreshing;

  refreshing = (async () => {
    const { res, parsed } = await raw(
      'POST',
      '/auth/refresh',
      { institutionId: INSTITUTION_ID, refreshToken },
      null,
    );
    if (!res.ok) {
      setTokens(null, null);
      return false;
    }
    const b = parsed as { accessToken?: string; refreshToken?: string };
    if (!b.accessToken) return false;
    setTokens(b.accessToken, b.refreshToken ?? refreshToken);
    return true;
  })().finally(() => {
    refreshing = null;
  });

  return refreshing;
}

async function request<T>(method: Method, path: string, body?: unknown): Promise<T> {
  let { res, parsed } = await raw(method, path, body);

  if (res.status === 401 && accessToken) {
    if (await tryRefresh()) {
      ({ res, parsed } = await raw(method, path, body));
    } else {
      setTokens(null, null);
      onUnauthorized?.();
    }
  }

  if (!res.ok) throw new ApiError(res.status, readMessage(parsed, res.status), parsed);
  return parsed as T;
}

/**
 * รูปแบบผลลัพธ์ของเส้นทางที่แบ่งหน้า (`toPage()` ฝั่ง API)
 *
 * ─── ทำไมต้องมีชนิดนี้อยู่ตรงกลาง ───
 * `/staff` กับ `/risk/students` คืน **ออบเจ็กต์** ไม่ใช่อาร์เรย์ แต่หน้าจอ
 * เขียน `api.get<StaffRow[]>('/staff')` ได้โดย TypeScript ไม่ทักอะไรเลย
 * เพราะ generic ของ `get` เป็นแค่การประกาศ ไม่ได้ตรวจกับของจริง
 * ผลคือ `rows.map is not a function` ตอนรันจริง — พังทั้งหน้า ไม่ใช่แค่ตารางนั้น
 * (เจอจริงที่หน้างานบุคลากรและหน้าจบการศึกษา ตอนยิง API เทียบของจริง)
 *
 * เขียนไว้ที่นี่ที่เดียวเพื่อให้ทุกหน้าจออ้างตัวเดียวกัน และเพิ่ม `getPage`
 * ที่บังคับให้ต้องรู้ว่ากำลังเรียกเส้นทางแบ่งหน้าอยู่
 */
export interface Page<T> {
  items: T[];
  limit: number;
  offset: number;
  hasMore: boolean;
}

export const emptyPage = <T>(): Page<T> => ({ items: [], limit: 0, offset: 0, hasMore: false });

export const api = {
  get: <T>(path: string) => request<T>('GET', path),

  /**
   * เส้นทางที่แบ่งหน้า — คืนทั้งก้อนรวม `hasMore`
   *
   * ไม่คลี่เหลือแต่ `items` โดยตั้งใจ เพราะหน้าจอที่แสดง 200 จาก 800 แถว
   * โดยไม่บอกผู้ใช้คือความผิดพลาดที่มองไม่ออกจากภายนอก
   */
  getPage: <T>(path: string) => request<Page<T>>('GET', path),

  post: <T>(path: string, body?: unknown) => request<T>('POST', path, body),
  patch: <T>(path: string, body?: unknown) => request<T>('PATCH', path, body),
  del: <T>(path: string) => request<T>('DELETE', path),

  /** ใช้ตอนยังไม่มี token (ล็อกอิน) หรือมี token ชนิดพิเศษ (challenge ของ MFA) */
  async withToken<T>(method: Method, path: string, body: unknown, token: string | null): Promise<T> {
    const { res, parsed } = await raw(method, path, body, token);
    if (!res.ok) throw new ApiError(res.status, readMessage(parsed, res.status), parsed);
    return parsed as T;
  },
};

/** ประกอบ query string โดยตัดค่าว่างทิ้ง — ทุกหน้าจอที่มีตัวกรองใช้ตัวนี้ */
export function qs(params: Record<string, string | number | boolean | undefined | null>): string {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null || v === '') continue;
    p.set(k, String(v));
  }
  const s = p.toString();
  return s ? `?${s}` : '';
}

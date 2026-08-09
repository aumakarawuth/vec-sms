import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCb) as (
  password: string | Buffer,
  salt: Buffer,
  keylen: number,
  options: { N: number; r: number; p: number; maxmem: number },
) => Promise<Buffer>;

/**
 * การแฮชรหัสผ่านด้วย scrypt ที่มากับ Node เอง
 *
 * ─── ทำไมไม่ใช้ bcrypt หรือ argon2 ───
 * ทั้งสองตัวเป็น native module ที่ต้องคอมไพล์ตอนติดตั้ง ซึ่งพังบ่อยบน
 * Windows และบน CI ที่ไม่มีเครื่องมือ build ส่วน scrypt อยู่ในไลบรารี
 * มาตรฐานของ Node อยู่แล้ว ไม่ต้องพึ่งอะไรเพิ่ม และเป็นฟังก์ชันหน่วง
 * ที่ OWASP รับรองให้ใช้กับรหัสผ่านได้
 *
 * ─── ทำไมเก็บพารามิเตอร์ไว้ในสตริงเดียวกัน ───
 * ความแรงที่เหมาะสมเปลี่ยนไปตามเวลา เมื่อเพิ่ม N ในอนาคต รหัสผ่านเดิม
 * ยังตรวจได้เพราะพารามิเตอร์เก่าติดมากับค่าที่เก็บไว้ แล้วค่อยแฮชใหม่
 * ตอนผู้ใช้เข้าสู่ระบบสำเร็จ โดยที่ไม่ต้องบังคับทุกคนตั้งรหัสใหม่พร้อมกัน
 */
export const SCRYPT_PARAMS = { N: 16384, r: 8, p: 1 } as const;
const KEY_LEN = 64;
const MAX_MEM = 64 * 1024 * 1024;

export async function hashPassword(plain: string): Promise<string> {
  const salt = randomBytes(16);
  const { N, r, p } = SCRYPT_PARAMS;
  const key = await scrypt(plain.normalize('NFKC'), salt, KEY_LEN, {
    N, r, p, maxmem: MAX_MEM,
  });
  return `scrypt$${N}$${r}$${p}$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(
  plain: string,
  stored: string,
): Promise<boolean> {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;

  const [, nStr, rStr, pStr, saltB64, hashB64] = parts;
  const salt = Buffer.from(saltB64, 'base64');
  const expected = Buffer.from(hashB64, 'base64');

  let actual: Buffer;
  try {
    actual = await scrypt(plain.normalize('NFKC'), salt, expected.length, {
      N: Number(nStr), r: Number(rStr), p: Number(pStr), maxmem: MAX_MEM,
    });
  } catch {
    return false;
  }

  if (actual.length !== expected.length) return false;
  // ต้องเทียบแบบเวลาคงที่ การเทียบด้วย === รั่วข้อมูลผ่านเวลาที่ใช้
  return timingSafeEqual(actual, expected);
}

/** ค่าที่เก็บไว้ใช้พารามิเตอร์เก่ากว่าปัจจุบันหรือไม่ — ถ้าใช่ควรแฮชใหม่ */
export function needsRehash(stored: string): boolean {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return true;
  return Number(parts[1]) < SCRYPT_PARAMS.N;
}

/**
 * ตรวจความแข็งแรงของรหัสผ่านขั้นต่ำ
 *
 * ไม่บังคับให้มีอักขระพิเศษหรือตัวพิมพ์ใหญ่ตามแนวทางใหม่ของ NIST
 * เพราะกฎแบบนั้นทำให้คนตั้งรหัสที่เดาง่ายในรูปแบบเดิม ๆ และจดใส่กระดาษ
 * สิ่งที่ได้ผลกว่าคือความยาว และการปฏิเสธรหัสที่เดาได้ทันที
 */
const OBVIOUS = new Set([
  'password', '12345678', '123456789', 'qwertyui', 'iloveyou',
  'student', 'college', 'admin123', 'abcd1234', 'p@ssw0rd',
]);

export function checkPasswordStrength(
  plain: string,
  opts: { minLength: number; username?: string },
): string | null {
  const value = plain.normalize('NFKC');

  if (value.length < opts.minLength) {
    return `รหัสผ่านต้องยาวอย่างน้อย ${opts.minLength} ตัวอักษร`;
  }
  if (value.length > 256) {
    return 'รหัสผ่านยาวเกินไป';
  }
  if (OBVIOUS.has(value.toLowerCase())) {
    return 'รหัสผ่านนี้เดาง่ายเกินไป กรุณาตั้งใหม่';
  }
  if (opts.username && value.toLowerCase().includes(opts.username.toLowerCase())) {
    return 'รหัสผ่านต้องไม่มีรหัสประจำตัวอยู่ในนั้น';
  }
  if (/^(\d)\1+$/.test(value) || /^0123456789/.test(value)) {
    return 'รหัสผ่านนี้เดาง่ายเกินไป กรุณาตั้งใหม่';
  }
  return null;
}

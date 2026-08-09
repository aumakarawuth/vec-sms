import { createCipheriv, createDecipheriv, createHmac, randomBytes, timingSafeEqual } from 'crypto';

/**
 * TOTP ตาม RFC 6238 และการเก็บความลับแบบเข้ารหัส
 *
 * ─── ทำไมเขียนเอง ───
 * ทั้งไฟล์นี้ใช้แค่ HMAC-SHA1 กับการแปลงฐาน 32 ซึ่ง Node มีให้ครบแล้ว
 * ไลบรารี TOTP ที่นิยมกันมีโค้ดมากกว่านี้หลายเท่าเพราะรองรับตัวเลือกที่
 * ระบบนี้ไม่ใช้ และการเพิ่ม dependency ในเส้นทางยืนยันตัวตนแลกมาด้วย
 * การต้องตามข่าวช่องโหว่ของมันไปตลอดอายุระบบ
 * (หลักเดียวกับที่ใช้ scrypt ที่มากับ Node แทน bcrypt)
 *
 * ─── ทำไมยังเป็น SHA-1 ───
 * ไม่ใช่เพราะปลอดภัยกว่า แต่เพราะแอป authenticator ทุกตัวที่คนไทยใช้จริง
 * (Google Authenticator, Microsoft Authenticator, แอปธนาคาร) รองรับ
 * เฉพาะค่าเริ่มต้นของ RFC 6238 การเลือก SHA-256 จะทำให้สแกน QR แล้วได้
 * รหัสที่ไม่ตรงกัน โดยไม่มีข้อความบอกว่าทำไม
 *
 * HMAC-SHA1 ในบริบทนี้ไม่ได้อ่อนแอ เพราะความลับสุ่มเต็มความยาวและรหัส
 * มีอายุ 30 วินาที การชนของ SHA-1 ไม่ช่วยผู้โจมตีเลย
 */

const DIGITS = 6;
const STEP_SECONDS = 30;

/** ยอมรับรหัสของช่วงก่อนหน้าหนึ่งช่วง เผื่อนาฬิกาเครื่องผู้ใช้เดินช้า */
const WINDOW = 1;

// ── ฐาน 32 ตาม RFC 4648 — แอป authenticator รับเฉพาะรูปแบบนี้ ─────
const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export function base32Encode(buf: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

export function base32Decode(s: string): Buffer {
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of s.replace(/=+$/, '').toUpperCase()) {
    const idx = B32.indexOf(ch);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

export function currentStep(atMs = Date.now()): number {
  return Math.floor(atMs / 1000 / STEP_SECONDS);
}

function codeAt(secret: Buffer, step: number): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));

  const digest = createHmac('sha1', secret).update(counter).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const bin =
    ((digest[offset] & 0x7f) << 24) |
    ((digest[offset + 1] & 0xff) << 16) |
    ((digest[offset + 2] & 0xff) << 8) |
    (digest[offset + 3] & 0xff);

  return String(bin % 10 ** DIGITS).padStart(DIGITS, '0');
}

/**
 * หาช่วงเวลาที่รหัสนี้ตรง หรือ null ถ้าไม่ตรงเลย
 *
 * คืน **ช่วงเวลา** ไม่ใช่แค่ true/false เพราะฐานข้อมูลต้องรู้ว่าเป็นช่วงไหน
 * จึงจะกันการใช้รหัสเดิมซ้ำได้ (ดู mfa_verify_step ใน 0036)
 *
 * เทียบด้วย timingSafeEqual เพราะการเทียบสตริงแบบปกติหยุดที่ตัวแรกที่ต่างกัน
 * ผู้โจมตีที่วัดเวลาตอบกลับได้จึงเดารหัสทีละหลักแทนที่จะเดาทั้งหกหลักพร้อมกัน
 */
export function verifyTotp(
  secret: Buffer,
  code: string,
  atMs = Date.now(),
): number | null {
  const clean = (code ?? '').replace(/\D/g, '');
  if (clean.length !== DIGITS) return null;

  const now = currentStep(atMs);
  const given = Buffer.from(clean, 'utf8');

  for (let d = -WINDOW; d <= 0; d++) {
    const step = now + d;
    const expected = Buffer.from(codeAt(secret, step), 'utf8');
    if (expected.length === given.length && timingSafeEqual(expected, given)) {
      return step;
    }
  }
  return null;
}

export function newSecret(): Buffer {
  // 20 ไบต์คือความยาวที่ RFC 4226 แนะนำและตรงกับความยาวของ HMAC-SHA1
  return randomBytes(20);
}

/** URI สำหรับสร้าง QR ให้แอป authenticator สแกน */
export function otpauthUri(issuer: string, account: string, secret: Buffer): string {
  const label = encodeURIComponent(`${issuer}:${account}`);
  const params = new URLSearchParams({
    secret: base32Encode(secret),
    issuer,
    algorithm: 'SHA1',
    digits: String(DIGITS),
    period: String(STEP_SECONDS),
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

// ── การเก็บความลับ ────────────────────────────────────────────────
//
// ความลับ TOTP ต้องถอดกลับได้เพื่อคำนวณรหัส จึงเก็บเป็นค่าแฮชไม่ได้
// เหมือนรหัสผ่าน ทางเดียวที่เหลือคือเข้ารหัสด้วยกุญแจที่อยู่นอกฐานข้อมูล
// ถ้าฐานข้อมูลรั่วอย่างเดียว ผู้โจมตียังสร้างรหัสไม่ได้
//
// ใช้ AES-256-GCM เพราะให้ทั้งความลับและการตรวจว่าไม่ถูกแก้ — ถ้ามีคนแก้
// ไบต์ในฐานข้อมูล การถอดรหัสจะล้มทันทีแทนที่จะได้ความลับที่เพี้ยน
// แล้วผู้ใช้เข้าระบบไม่ได้โดยไม่มีใครรู้ว่าเพราะอะไร

const IV_BYTES = 12;
const TAG_BYTES = 16;

function keyFrom(secretKey: string): Buffer {
  const key = Buffer.from(secretKey, 'base64');
  if (key.length !== 32) {
    throw new Error(
      'MFA_SECRET_KEY ต้องเป็นคีย์ 32 ไบต์ในรูปแบบ base64 — สร้างด้วย openssl rand -base64 32',
    );
  }
  return key;
}

export function encryptSecret(secret: Buffer, secretKey: string): Buffer {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv('aes-256-gcm', keyFrom(secretKey), iv);
  const enc = Buffer.concat([cipher.update(secret), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), enc]);
}

export function decryptSecret(blob: Buffer, secretKey: string): Buffer {
  if (blob.length < IV_BYTES + TAG_BYTES) {
    throw new Error('ข้อมูลความลับ MFA เสียหาย');
  }
  const iv = blob.subarray(0, IV_BYTES);
  const tag = blob.subarray(IV_BYTES, IV_BYTES + TAG_BYTES);
  const decipher = createDecipheriv('aes-256-gcm', keyFrom(secretKey), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(blob.subarray(IV_BYTES + TAG_BYTES)), decipher.final()]);
}

/**
 * รหัสกู้คืน — อ่านออกเสียงทางโทรศัพท์ได้
 *
 * ตัดตัวอักษรที่สับสนกันออก (0/O, 1/I/L) เพราะรหัสเหล่านี้ถูกจดใส่กระดาษ
 * แล้วพิมพ์ตามทีหลัง การอ่านผิดหนึ่งตัวแปลว่าเสียรหัสไปหนึ่งใบเปล่า ๆ
 */
const RECOVERY_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function newRecoveryCode(): string {
  const bytes = randomBytes(10);
  let out = '';
  for (let i = 0; i < 10; i++) {
    out += RECOVERY_ALPHABET[bytes[i] % RECOVERY_ALPHABET.length];
    if (i === 4) out += '-';
  }
  return out;
}

/** ตัดขีดและตัวพิมพ์เล็กออกก่อนแฮช เพราะผู้ใช้พิมพ์มาได้หลายแบบ */
export function normalizeRecoveryCode(code: string): string {
  return (code ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

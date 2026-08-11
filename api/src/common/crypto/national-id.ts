import { createCipheriv, createDecipheriv, createHmac, randomBytes, createHash } from 'node:crypto';

/**
 * เลขประจำตัวประชาชน — ค่าแฮชสำหรับค้นหา และค่าที่เข้ารหัสสำหรับพิมพ์
 *
 * ═══ ทำไมต้องเก็บค่าที่ถอดกลับได้ ทั้งที่เดิมตั้งใจเก็บแค่ค่าแฮช ═══
 * ใบ รบ. **พิมพ์เลขเต็มบนกระดาษ** ทุกรูปแบบที่วัดมาจากไฟล์จริง
 * (ดู docs/transcript-formats.md) การเก็บแค่ค่าแฮชจึงแปลว่าออกใบ รบ.
 * ที่ใช้ยื่นจริงไม่ได้เลยสักใบ — ซึ่งเป็นเหตุผลเดียวที่ระบบนี้มีอยู่
 *
 * ทางออกคือคอลัมน์ที่เข้ารหัสจริงด้วยกุญแจที่**อยู่นอกฐานข้อมูล**
 * ไม่ใช่การเลิกแฮช — ถ้าฐานข้อมูลรั่วอย่างเดียว เลขยังอ่านไม่ได้
 * (`person.national_id_enc` มีมาตั้งแต่ 0002 แต่ไม่เคยมีใครเขียนลงไปเลย
 *  รูปเดียวกับ `take_usage_snapshot()` — ของที่ประกาศเจตนาไว้แล้วไม่มี
 *  อะไรทำให้เจตนานั้นเกิดขึ้น)
 *
 * ═══ และค่าแฮชเดิมป้องกันอะไรไม่ได้เลย ═══
 * `digest(national_id, 'sha256')` เป็นแฮชเปล่าไม่มีกุญแจ ส่วนเลขบัตร
 * ประชาชนไทยมีความเป็นไปได้ราว 10¹² ค่าหลังหักตัวตรวจสอบ — ไล่ครบด้วย
 * การ์ดจอใบเดียวในเวลาไม่กี่นาที "เก็บแค่ค่าแฮช" จึงไม่ใช่การป้องกัน
 * เป็นแค่การเปลี่ยนรูปแบบ
 *
 * เหตุผลนี้เขียนไว้แล้วใน `reset-code.ts` สำหรับรหัสที่มีเอนโทรปี 39.6 บิต
 * ซึ่ง**มากกว่า**เลขบัตรประชาชน — แต่โค้ดฝั่งเลขบัตรกลับทำตรงข้าม
 *
 * ═══ ทำไมกุญแจอยู่ที่ชั้น API ไม่ใช่ในฐานข้อมูล ═══
 * ขัดกับหลักข้อ 1 ("ฐานข้อมูลเป็นเจ้าของกฎ") โดยตั้งใจ และเป็นข้อยกเว้น
 * ที่จำเป็น — กุญแจที่เก็บในฐานข้อมูลจะรั่วไปพร้อมกับ dump ของฐานข้อมูล
 * แล้วการเข้ารหัสจะกลายเป็นของประดับ
 *
 * สิ่งที่ฐานข้อมูล**ยังเป็นเจ้าของอยู่**คือ *ใครเห็นแถวได้* (RLS ของ
 * `person`) และ *ห้ามทำดัชนีบนคอลัมน์ที่เข้ารหัส* (คอมเมนต์ใน 0002)
 * ส่วนกุญแจอยู่ที่กระบวนการ หลักเดียวกับ MFA_SECRET_KEY ที่ทำแบบนี้อยู่แล้ว
 */

const IV_BYTES = 12;
const TAG_BYTES = 16;
const VERSION = 1;

/**
 * รหัสกุญแจ — แปดตัวอักษรฐานสิบหกจากค่าแฮชของกุญแจเอง
 *
 * ─── ทำไมต้องมี ───
 * ใบ รบ. ที่ออกวันนี้ต้องพิมพ์ซ้ำได้อีกสิบปีข้างหน้า ซึ่งนานกว่าอายุของ
 * กุญแจชุดใดชุดหนึ่งแน่นอน การเก็บรหัสกุญแจไว้กับข้อความที่เข้ารหัสทำให้
 * รู้ได้ว่าแถวนี้ต้องใช้กุญแจใบไหนถอด โดยไม่ต้องลองทุกใบและไม่ต้องเดา
 *
 * ได้จากการแฮชกุญแจ จึงไม่ต้องตั้งค่าเพิ่มและไม่เปิดเผยตัวกุญแจ
 */
export function keyIdOf(keyB64: string): string {
  return createHash('sha256').update(keyB64, 'utf8').digest('hex').slice(0, 8);
}

function keyFrom(keyB64: string): Buffer {
  const key = Buffer.from(keyB64, 'base64');
  if (key.length !== 32) {
    throw new Error(
      'NATIONAL_ID_KEY ต้องเป็นคีย์ 32 ไบต์ในรูปแบบ base64 — สร้างด้วย openssl rand -base64 32',
    );
  }
  return key;
}

/** ตัดทุกอย่างที่ไม่ใช่ตัวเลขออก — คนกรอกทั้งแบบมีขีดและไม่มี */
export function normalizeNationalId(raw: string): string {
  return raw.replace(/\D/g, '');
}

/**
 * ตรวจเลขบัตรประชาชนไทยด้วยหลักตรวจสอบ
 *
 * ฐานข้อมูลมี `thai_national_id_valid()` อยู่แล้วตั้งแต่ 0023 แต่ชั้นนี้
 * ต้องตรวจก่อนเข้ารหัส เพราะเลขที่ผิดเมื่อเข้ารหัสไปแล้วจะตรวจไม่ได้อีก
 * โดยไม่ถอดรหัสออกมาทั้งฐาน
 */
export function isValidThaiNationalId(id: string): boolean {
  const n = normalizeNationalId(id);
  if (!/^\d{13}$/.test(n)) return false;
  let sum = 0;
  for (let i = 0; i < 12; i++) sum += Number(n[i]) * (13 - i);
  return (11 - (sum % 11)) % 10 === Number(n[12]);
}

/**
 * ค่าแฮชสำหรับค้นหาและกันซ้ำ — HMAC ไม่ใช่ sha256 เปล่า
 *
 * แตกสายจากความลับที่มีอยู่แล้วด้วยป้ายกำกับ หลักเดียวกับ `resetCodeKey()`
 * เพื่อไม่ให้เพิ่มกุญแจที่ต้องตั้งเองอีกตัว ซึ่งเป็นกุญแจที่มีโอกาสถูกลืมตั้ง
 * แล้วตกไปใช้ค่าเริ่มต้นที่เดาได้
 */
export function hashNationalId(id: string, secret: string): Buffer {
  const key = createHmac('sha256', secret).update('vec-sms:national-id').digest();
  return createHmac('sha256', key).update(normalizeNationalId(id)).digest();
}

/**
 * เข้ารหัสด้วย AES-256-GCM
 *
 * รูปแบบ: `[รุ่น 1][ความยาวรหัสกุญแจ 1][รหัสกุญแจ][iv 12][tag 16][เนื้อ]`
 * ใช้ GCM เพราะให้ทั้งความลับและการตรวจว่าไม่ถูกแก้ — ถ้ามีคนแก้ไบต์ใน
 * ฐานข้อมูล การถอดรหัสจะล้มทันที แทนที่จะได้เลขที่เพี้ยนไปพิมพ์ลงใบ รบ.
 */
export function encryptNationalId(id: string, keyB64: string): Buffer {
  const keyId = Buffer.from(keyIdOf(keyB64), 'ascii');
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv('aes-256-gcm', keyFrom(keyB64), iv);
  const enc = Buffer.concat([
    cipher.update(normalizeNationalId(id), 'utf8'),
    cipher.final(),
  ]);
  return Buffer.concat([
    Buffer.from([VERSION, keyId.length]),
    keyId,
    iv,
    cipher.getAuthTag(),
    enc,
  ]);
}

export function keyIdInBlob(blob: Buffer): string | null {
  if (blob.length < 2 || blob[0] !== VERSION) return null;
  const len = blob[1];
  if (blob.length < 2 + len) return null;
  return blob.subarray(2, 2 + len).toString('ascii');
}

/**
 * ถอดรหัสด้วยกุญแจที่ตรงกับรหัสกุญแจในตัวข้อความ
 *
 * `keys` เป็นแผนที่ รหัสกุญแจ → กุญแจ ซึ่งรวมกุญแจที่เลิกใช้แล้วด้วย
 * (`NATIONAL_ID_KEYS_OLD`) เพื่อให้ใบเก่ายังพิมพ์ซ้ำได้หลังหมุนกุญแจ
 *
 * คืน null เมื่อไม่มีกุญแจที่ตรง — **ไม่โยน** เพราะเส้นทางที่เรียกคือการ
 * พิมพ์เอกสาร ซึ่งต้องพิมพ์ได้ต่อโดยเว้นช่องเลขบัตรว่างไว้ ดีกว่าพิมพ์
 * ไม่ได้ทั้งใบเพราะกุญแจใบเดียวหาย
 */
export function decryptNationalId(blob: Buffer, keys: Map<string, string>): string | null {
  const id = keyIdInBlob(blob);
  if (id === null) return null;
  const keyB64 = keys.get(id);
  if (!keyB64) return null;

  const at = 2 + id.length;
  if (blob.length < at + IV_BYTES + TAG_BYTES) return null;
  const iv = blob.subarray(at, at + IV_BYTES);
  const tag = blob.subarray(at + IV_BYTES, at + IV_BYTES + TAG_BYTES);
  try {
    const decipher = createDecipheriv('aes-256-gcm', keyFrom(keyB64), iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([
      decipher.update(blob.subarray(at + IV_BYTES + TAG_BYTES)),
      decipher.final(),
    ]).toString('utf8');
  } catch {
    // ไบต์ถูกแก้หรือกุญแจผิด — เว้นว่างดีกว่าพิมพ์เลขที่เพี้ยนลงเอกสารทางการ
    return null;
  }
}

/** เลขบนกระดาษเขียนเป็น `1 1040 00247 44 9` ตามที่ใบจริงพิมพ์ */
export function formatNationalId(id: string): string {
  const n = normalizeNationalId(id);
  if (n.length !== 13) return n;
  return `${n[0]} ${n.slice(1, 5)} ${n.slice(5, 10)} ${n.slice(10, 12)} ${n[12]}`;
}

/**
 * กุญแจทั้งหมดที่ใช้ถอดรหัสได้ — ใบปัจจุบันหนึ่งใบ บวกใบเก่าที่เก็บไว้
 *
 * ถ้าไม่ได้ตั้ง `NATIONAL_ID_KEY` เลย จะได้แผนที่ว่าง ซึ่งแปลว่า
 * **เก็บเลขบัตรไม่ได้** และชั้นบนต้องปฏิเสธไปตรง ๆ ไม่ใช่เก็บแต่ค่าแฮช
 * แล้วรายงานว่าสำเร็จ — เป็นหลักเดียวกับ RESET_DELIVERY ที่ค่าเริ่มต้น
 * คือปิด ไม่ใช่ทำเป็นส่งแล้วเงียบ ๆ
 */
export function decryptionKeys(env: NodeJS.ProcessEnv): Map<string, string> {
  const out = new Map<string, string>();
  const add = (k: string) => {
    const v = k.trim();
    if (v) out.set(keyIdOf(v), v);
  };
  if (env.NATIONAL_ID_KEY) add(env.NATIONAL_ID_KEY);
  for (const k of (env.NATIONAL_ID_KEYS_OLD ?? '').split(',')) add(k);
  return out;
}

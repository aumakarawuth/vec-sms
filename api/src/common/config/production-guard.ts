import { Logger } from '@nestjs/common';

/**
 * ปฏิเสธการเริ่มทำงานถ้าตั้งค่าไม่ปลอดภัยในระบบจริง
 *
 * ─── ทำไมต้องล้มตั้งแต่บูต ───
 * ระบบนี้มีหลักอยู่แล้วว่า "ถ้าเชื่อมต่อฐานข้อมูลด้วย superuser ให้แอปไม่ขึ้น"
 * เหตุผลคือ RLS จะถูกข้ามเงียบ ๆ และ**ไม่มีอะไรฟ้อง** จนกว่าจะมีคนร้องเรียน
 *
 * การตั้งค่าที่ตรวจในไฟล์นี้มีลักษณะเดียวกันทุกข้อ — ถ้าผิด ระบบจะดูเหมือน
 * ทำงานปกติทุกอย่าง แต่ความปลอดภัยหายไปโดยไม่มีสัญญาณใด ๆ
 *
 *   DEV_AUTH=true          ใครก็ขอ token เป็น admin ได้โดยไม่ต้องมีรหัสผ่าน
 *   JWT_SECRET อ่อน        ปลอม token เป็นใครก็ได้
 *   CORS_ORIGINS=*         เว็บไซต์ใดก็ยิงคำขอแทนผู้ใช้ที่ล็อกอินค้างไว้ได้
 *   THROTTLE_ENABLED=false เดารหัสผ่านได้ไม่จำกัด
 *   AUDIT_ENABLED=false    ไม่เหลือหลักฐานว่าใครเข้าถึงข้อมูลใคร (ผิด PDPA ม.37)
 *   RESET_DELIVERY=log     รหัสรีเซ็ตรหัสผ่านโผล่ใน log ยึดบัญชีใครก็ได้
 *
 * ทั้งหมดนี้คือสิ่งที่ถูกเปิดไว้ตอนพัฒนาแล้วลืมปิดตอน deploy ซึ่งเป็น
 * สาเหตุของเหตุการณ์ข้อมูลรั่วจำนวนมากในระบบจริง
 *
 * ─── ทำไมไม่แค่เตือน ───
 * คำเตือนตอนบูตไม่มีใครอ่าน โดยเฉพาะเมื่อ deploy อัตโนมัติ
 * การไม่ขึ้นเลยทำให้ต้องแก้ก่อนใช้งาน ซึ่งเป็นผลลัพธ์ที่ต้องการ
 */

/** ค่าที่พบบ่อยในไฟล์ตัวอย่างและคู่มือ — ถ้าเจอในระบบจริงแปลว่าไม่ได้ตั้งจริง */
const KNOWN_WEAK_SECRETS = new Set([
  'secret', 'changeme', 'change-me', 'test-secret', 'ci-secret',
  'dev', 'development', 'vec-sms', 'jwt-secret', 'mysecret',
  'password', 'admin', '12345678', 'supersecret',
]);

const MIN_SECRET_LENGTH = 32;

export interface GuardResult {
  errors: string[];
  warnings: string[];
}

export function checkProductionConfig(env: NodeJS.ProcessEnv): GuardResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const isProduction = env.NODE_ENV === 'production';

  const weak = (value?: string) =>
    !value ||
    value.trim().length < MIN_SECRET_LENGTH ||
    KNOWN_WEAK_SECRETS.has(value.trim().toLowerCase());

  // ── ที่ต้องผิดพลาดไม่ได้เลยในระบบจริง ─────────────────────────────
  if (isProduction) {
    if (env.DEV_AUTH === 'true') {
      errors.push(
        'DEV_AUTH=true ในระบบจริง — POST /auth/dev-token จะออก token เป็นบทบาทใดก็ได้ ' +
          'ให้ใครก็ตามที่รู้ URL โดยไม่ต้องมีรหัสผ่าน',
      );
    }

    if (env.MFA_DISABLED === 'true') {
      errors.push('MFA_DISABLED=true ในระบบจริง — ห้ามปิดการยืนยันสองชั้นนอกเครื่องพัฒนา');
    }

    if (env.ALLOW_SUPERUSER === 'true') {
      errors.push(
        'ALLOW_SUPERUSER=true ในระบบจริง — Row-Level Security จะถูกข้ามทั้งหมด ' +
          'กำแพงกันข้อมูลข้ามวิทยาลัยจะไม่ทำงานเลย',
      );
    }

    if (weak(env.JWT_SECRET)) {
      errors.push(
        `JWT_SECRET สั้นเกินไปหรือเป็นค่าตัวอย่าง — ต้องยาวอย่างน้อย ${MIN_SECRET_LENGTH} ตัวอักษร ` +
          'สุ่มด้วย openssl rand -base64 48 (ถ้าเดาได้ ผู้โจมตีปลอม token เป็นใครก็ได้)',
      );
    }

    if (weak(env.IP_HASH_SECRET)) {
      errors.push(
        'IP_HASH_SECRET สั้นเกินไปหรือเป็นค่าตัวอย่าง — ค่าแฮชไอพีจะถูกย้อนกลับได้ด้วย ' +
          'rainbow table ซึ่งทำให้การเก็บเป็นค่าแฮชไม่มีความหมายตาม PDPA',
      );
    }

    /*
     * MFA_SECRET_KEY ใช้เข้ารหัสความลับ TOTP ถ้าไม่มี บทบาท admin/director
     * จะตั้งการยืนยันสองชั้นไม่ได้เลย และ auth_policy บังคับให้บทบาทเหล่านั้น
     * ต้องยืนยันสองชั้น — ผลคือผู้ดูแลเข้าระบบไม่ได้ทั้งวิทยาลัย
     *
     * ล้มตั้งแต่บูตดีกว่าปล่อยให้ไปเจอตอนผู้ดูแลคนแรกพยายามเข้าระบบ
     */
    const mfaKey = env.MFA_SECRET_KEY ?? '';
    if (!mfaKey) {
      errors.push(
        'ไม่ได้ตั้ง MFA_SECRET_KEY — บทบาทที่ถูกบังคับยืนยันสองชั้นจะตั้งค่าไม่ได้ ' +
          'และเข้าระบบไม่ได้เลย สร้างด้วย openssl rand -base64 32',
      );
    } else if (Buffer.from(mfaKey, 'base64').length !== 32) {
      errors.push(
        'MFA_SECRET_KEY ต้องเป็นคีย์ 32 ไบต์ในรูปแบบ base64 — สร้างด้วย openssl rand -base64 32',
      );
    } else if (mfaKey === env.JWT_SECRET || mfaKey === env.IP_HASH_SECRET) {
      errors.push(
        'MFA_SECRET_KEY ซ้ำกับความลับอื่น — ถ้าค่าใดค่าหนึ่งรั่ว จะเสียหลายอย่างพร้อมกัน',
      );
    }

    /*
     * NATIONAL_ID_KEY เข้ารหัสเลขประจำตัวประชาชน ซึ่งใบ รบ. พิมพ์เต็ม
     * บนกระดาษทุกรูปแบบ ถ้าไม่มี วิทยาลัยจะกรอกเลขบัตรไม่ได้เลยสักคน
     * แล้วใบ รบ. ทุกใบที่ออกจะมีช่องเลขบัตรว่าง — ใช้ยื่นจริงไม่ได้
     *
     * เป็นข้อผิดพลาดรูปเดียวกับ MFA_SECRET_KEY ที่ทำให้ deploy รอบก่อน
     * ไม่ผ่าน คือค่าที่ทุกอย่างพึ่งอยู่แต่ไม่มีอยู่ในไฟล์ตั้งค่าไหนเลย
     */
    const nidKey = env.NATIONAL_ID_KEY ?? '';
    if (!nidKey) {
      errors.push(
        'ไม่ได้ตั้ง NATIONAL_ID_KEY — กรอกเลขประจำตัวประชาชนไม่ได้เลย และใบ รบ. ' +
          'ทุกใบจะมีช่องเลขบัตรว่าง สร้างด้วย openssl rand -base64 32',
      );
    } else if (Buffer.from(nidKey, 'base64').length !== 32) {
      errors.push(
        'NATIONAL_ID_KEY ต้องเป็นคีย์ 32 ไบต์ในรูปแบบ base64 — สร้างด้วย openssl rand -base64 32',
      );
    } else if (
      nidKey === env.JWT_SECRET ||
      nidKey === env.IP_HASH_SECRET ||
      nidKey === env.MFA_SECRET_KEY
    ) {
      errors.push(
        'NATIONAL_ID_KEY ซ้ำกับความลับอื่น — ถ้าค่าใดค่าหนึ่งรั่ว จะเสียหลายอย่างพร้อมกัน',
      );
    }

    /*
     * ─── กุญแจเก่าที่ถอนออกแล้วต้องเก็บไว้ ───
     * ใบ รบ. ที่ออกวันนี้ต้องพิมพ์ซ้ำได้อีกสิบปี ซึ่งนานกว่าอายุของกุญแจ
     * ชุดใดชุดหนึ่ง การหมุนกุญแจโดยทิ้งใบเก่าแปลว่าใบที่ออกก่อนหน้าพิมพ์
     * ซ้ำแล้วช่องเลขบัตรว่าง โดยไม่มีอะไรฟ้องจนกว่าจะมีคนขอใบซ้ำ
     */
    for (const old of (env.NATIONAL_ID_KEYS_OLD ?? '').split(',')) {
      if (old.trim() && Buffer.from(old.trim(), 'base64').length !== 32) {
        errors.push('NATIONAL_ID_KEYS_OLD มีคีย์ที่ไม่ใช่ 32 ไบต์ในรูปแบบ base64');
        break;
      }
    }

    /*
     * PROVISION_KEY เปิดสองอย่างที่อยู่นอกขอบเขตของทุกบทบาทในระบบ —
     * การเปิดวิทยาลัยใหม่ (0037) และการสร้างบัญชีผู้ให้บริการคนแรก (0040)
     *
     * ไม่ตั้งเลยถือว่าปลอดภัย เพราะทั้งสองเส้นทางจะปิดสนิท (503) แต่ถ้าตั้ง
     * ไว้เป็นค่าที่เดาได้ ใครก็ตามที่รู้ URL จะสร้างวิทยาลัยปลอมได้ไม่จำกัด
     * และถ้าระบบยังไม่มีบัญชีผู้ให้บริการ จะแต่งตั้งตัวเองเป็น owner ได้ด้วย
     */
    if (env.PROVISION_KEY && weak(env.PROVISION_KEY)) {
      errors.push(
        `PROVISION_KEY สั้นเกินไปหรือเป็นค่าตัวอย่าง — ต้องยาวอย่างน้อย ${MIN_SECRET_LENGTH} ตัวอักษร ` +
          'เพราะกุญแจนี้เปิดวิทยาลัยใหม่ได้ และสร้างบัญชีผู้ให้บริการคนแรกได้',
      );
    }

    if (env.JWT_SECRET && env.IP_HASH_SECRET && env.JWT_SECRET === env.IP_HASH_SECRET) {
      errors.push(
        'JWT_SECRET กับ IP_HASH_SECRET เป็นค่าเดียวกัน — ถ้าค่าใดค่าหนึ่งรั่ว จะเสียทั้งสองอย่างพร้อมกัน',
      );
    }

    if ((env.CORS_ORIGINS ?? '').split(',').some((o) => o.trim() === '*')) {
      errors.push(
        'CORS_ORIGINS มี * ในระบบจริง — เว็บไซต์ใดก็ยิงคำขอแทนผู้ใช้ที่ล็อกอินค้างไว้ได้',
      );
    }

    if (env.THROTTLE_ENABLED === 'false') {
      errors.push(
        'THROTTLE_ENABLED=false ในระบบจริง — เดารหัสผ่านและยิงคำขอได้ไม่จำกัด',
      );
    }

    if (env.AUDIT_ENABLED === 'false') {
      errors.push(
        'AUDIT_ENABLED=false ในระบบจริง — ไม่เหลือหลักฐานว่าใครเข้าถึงข้อมูลของใคร ' +
          'ซึ่งขัดกับ PDPA มาตรา 37 ที่ต้องตรวจสอบย้อนหลังได้',
      );
    }

    if (env.RESET_DELIVERY === 'log') {
      errors.push(
        'RESET_DELIVERY=log ในระบบจริง — รหัสรีเซ็ตรหัสผ่านจะถูกเขียนลง log ' +
          'ซึ่งทุกคนที่เปิด log ได้จะยึดบัญชีใครก็ได้โดยไม่ต้องรู้รหัสผ่านเดิม ' +
          'ให้ตั้งเป็นผู้ให้บริการจริง หรือไม่ตั้งเลยเพื่อใช้เฉพาะช่องทางงานทะเบียน',
      );
    }

    if (!env.DATABASE_URL?.includes('sslmode=') && !env.DATABASE_URL?.includes('localhost')) {
      warnings.push(
        'DATABASE_URL ไม่ได้ระบุ sslmode — การเชื่อมต่อฐานข้อมูลข้ามเครือข่ายควรเข้ารหัส ' +
          'เติม ?sslmode=require ท้าย URL',
      );
    }

    if (env.OPENAPI_ENABLED === 'true') {
      warnings.push(
        'OPENAPI_ENABLED=true ในระบบจริง — รายการ endpoint ทั้งหมดพร้อมบทบาทที่เรียกได้ ' +
          'เป็นแผนที่ให้ผู้โจมตี ควรเปิดชั่วคราวแล้วปิดกลับ',
      );
    }

    if (env.TZ !== 'Asia/Bangkok') {
      warnings.push(
        `TZ=${env.TZ ?? 'ไม่ได้ตั้ง'} — งานตามกำหนดเวลาจะรันผิดเวลา ควรตั้งเป็น Asia/Bangkok`,
      );
    }
  } else {
    // นอกระบบจริงแค่เตือน เพื่อให้เห็นตั้งแต่ตอนพัฒนาว่าอะไรจะบล็อกตอน deploy
    if (weak(env.JWT_SECRET)) {
      warnings.push('JWT_SECRET เป็นค่าที่อ่อน — ใช้ได้เฉพาะนอกระบบจริง');
    }
  }

  return { errors, warnings };
}

/** เรียกตอนบูต — โยนข้อผิดพลาดถ้าตั้งค่าไม่ปลอดภัย */
export function assertProductionConfig(env: NodeJS.ProcessEnv = process.env): void {
  const logger = new Logger('ProductionGuard');
  const { errors, warnings } = checkProductionConfig(env);

  warnings.forEach((w) => logger.warn(w));

  if (errors.length > 0) {
    errors.forEach((e) => logger.error(e));
    throw new Error(
      `การตั้งค่าไม่ปลอดภัยสำหรับระบบจริง ${errors.length} ข้อ — ระบบจะไม่เริ่มทำงานจนกว่าจะแก้ครบ`,
    );
  }
}

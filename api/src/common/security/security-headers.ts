import { NextFunction, Request, Response } from 'express';

/**
 * เฮดเดอร์ความปลอดภัย
 *
 * ─── ทำไมเขียนเองแทนใช้ helmet ───
 * helmet ตั้งเฮดเดอร์ราวสิบตัวโดยค่าเริ่มต้น ซึ่งหลายตัวออกแบบมาสำหรับเว็บ
 * ที่ส่ง HTML ไม่ใช่ API ที่ส่ง JSON ล้วน การใช้ค่าเริ่มต้นของมันทำให้มีเฮดเดอร์
 * ที่ไม่มีผลอะไรเลยปนอยู่ และคนอ่านโค้ดแยกไม่ออกว่าตัวไหนกันอะไรจริง
 *
 * ระบบนี้ยึดหลักพึ่งไลบรารีน้อยอยู่แล้ว (ไม่ใช้ bcrypt เพราะเป็น native module,
 * ไม่ใช้ไลบรารีจัดการสถานะในแอป) ไฟล์นี้ยาวสี่สิบบรรทัดและอธิบายได้ทุกบรรทัด
 * ว่าทำไมถึงมี ซึ่งมีค่ากว่าการเพิ่ม dependency ที่ต้องตามอัปเดตไปอีกหลายปี
 */
export function securityHeaders(isProduction: boolean) {
  return (req: Request, res: Response, next: NextFunction): void => {
    // เปิดเผยว่าใช้ Express รุ่นไหนไม่มีประโยชน์กับใครนอกจากผู้โจมตี
    res.removeHeader('X-Powered-By');

    // เบราว์เซอร์ห้ามเดาชนิดไฟล์เอง — กัน JSON ที่มีข้อความของผู้ใช้
    // ถูกตีความเป็น HTML แล้วรันสคริปต์
    res.setHeader('X-Content-Type-Options', 'nosniff');

    // API นี้ไม่มีหน้าเว็บให้ฝัง การถูกฝังใน iframe มีแต่ทางเสีย (clickjacking)
    res.setHeader('X-Frame-Options', 'DENY');

    // ไม่ส่ง URL เดิมไปให้ปลายทาง — URL ของระบบนี้มี uuid ของนักศึกษาอยู่
    res.setHeader('Referrer-Policy', 'no-referrer');

    // API ไม่ต้องใช้กล้อง ไมค์ หรือพิกัด ปิดทิ้งให้หมด
    res.setHeader(
      'Permissions-Policy',
      'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
    );

    // ตอบกลับเป็น JSON ล้วน ไม่มีอะไรให้โหลดเลย
    // ยกเว้นหน้าเอกสาร OpenAPI ที่ต้องโหลดสคริปต์และสไตล์ของตัวเอง
    if (!req.path.startsWith('/api/docs')) {
      res.setHeader(
        'Content-Security-Policy',
        "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
      );
    }

    // บังคับ HTTPS เฉพาะระบบจริง — ตั้งในเครื่องพัฒนาจะทำให้เบราว์เซอร์
    // จำไว้แล้วเปิด http://localhost ไม่ได้อีกเลยจนกว่าจะล้างค่าเอง
    if (isProduction) {
      res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    }

    next();
  };
}

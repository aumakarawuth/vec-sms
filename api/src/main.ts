import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { json, urlencoded } from 'express';
import { AppModule } from './app.module';
import { assertProductionConfig } from './common/config/production-guard';
import { configurePgTypes } from './common/db/pg-types';
import { securityHeaders } from './common/security/security-headers';

// ต้องตั้งก่อนเปิดการเชื่อมต่อฐานข้อมูล มิฉะนั้นวันที่จะเลื่อนไปหนึ่งวัน
configurePgTypes();

export async function createApp() {
  // ตรวจก่อนสร้างแอป — ไม่มีประโยชน์ที่จะเปิดการเชื่อมต่อฐานข้อมูล
  // ถ้ารู้อยู่แล้วว่าการตั้งค่าไม่ปลอดภัยพอจะให้บริการจริง
  assertProductionConfig();

  const app = await NestFactory.create(AppModule, {
    logger: process.env.LOG_LEVEL === 'debug'
      ? ['log', 'error', 'warn', 'debug', 'verbose']
      : ['log', 'error', 'warn'],
    // ปิด body parser ของ Nest เพื่อตั้งเพดานขนาดเอง
    bodyParser: false,
  });

  const isProduction = process.env.NODE_ENV === 'production';
  app.use(securityHeaders(isProduction));

  // ─── เพดานขนาดคำขอ ───────────────────────────────────────────────
  //
  // ค่าเริ่มต้นของ Nest คือ 100KB ซึ่งเล็กเกินไปสำหรับการนำเข้าข้อมูล
  // (ไฟล์นักศึกษา 800 คนเป็น JSON ราว 130KB) แต่ใหญ่เกินไปถ้าปล่อยให้
  // ทุก endpoint รับได้เท่ากัน เพราะการยิงคำขอใหญ่ ๆ รัว ๆ เป็นวิธี
  // ทำให้เซิร์ฟเวอร์หมดหน่วยความจำที่ง่ายที่สุด
  //
  // จึงตั้งเพดานทั่วไปให้เล็ก แล้วเปิดกว้างเฉพาะเส้นทางนำเข้าข้อมูล
  // ซึ่งจำกัดบทบาทไว้ที่งานทะเบียนขึ้นไปอยู่แล้ว
  const importLimit = process.env.IMPORT_BODY_LIMIT ?? '8mb';
  const defaultLimit = process.env.BODY_LIMIT ?? '256kb';

  app.use('/api/v1/import', json({ limit: importLimit }));
  app.use(json({ limit: defaultLimit }));
  app.use(urlencoded({ extended: false, limit: defaultLimit }));

  app.setGlobalPrefix('api/v1');

  // ─── CORS ─────────────────────────────────────────────────────────
  // แอปมือถือไม่ต้องใช้ แต่ Flutter build web ต้องใช้ เพราะเบราว์เซอร์
  // บล็อกคำขอข้ามโดเมนถ้าเซิร์ฟเวอร์ไม่อนุญาตอย่างชัดเจน
  //
  // ระบุโดเมนเป็นรายชื่อเสมอ ไม่ใช้ '*' เพราะ token อยู่ในเฮดเดอร์
  // Authorization การเปิดกว้างทำให้เว็บไซต์ใดก็ได้ยิงคำขอแทนผู้ใช้ที่
  // ล็อกอินค้างไว้ได้ ถ้าไม่ตั้ง CORS_ORIGINS จะไม่เปิดให้โดเมนอื่นเลย
  const origins = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

  if (origins.length > 0) {
    app.enableCors({
      origin: origins,
      methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Authorization', 'Content-Type', 'X-Request-Id'],
      maxAge: 86_400,
    });
  }

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );
  app.enableShutdownHooks();

  // ─── เอกสาร OpenAPI ───────────────────────────────────────────────
  //
  // ปิดไว้เป็นค่าเริ่มต้นในระบบจริง เพราะหน้ารายการ endpoint ทั้งหมด
  // พร้อมบทบาทที่เรียกได้ เป็นแผนที่ให้ผู้โจมตีอย่างดี
  // เปิดเมื่อจำเป็นด้วย OPENAPI_ENABLED=true แล้วปิดกลับ
  if (process.env.OPENAPI_ENABLED === 'true') {
    // เอกสารเป็นของเสริม ถ้าสร้างไม่ได้ต้องไม่ทำให้ API ทั้งตัวไม่ขึ้น
    // ระบบที่ล่มเพราะสร้างเอกสารไม่สำเร็จคือการแลกที่ไม่คุ้มอย่างชัดเจน
    try {
      const { buildOpenApi } = await import('./common/openapi/openapi');
      const { SwaggerModule } = await import('@nestjs/swagger');
      const document = buildOpenApi(app);
      SwaggerModule.setup('api/docs', app, document, {
        jsonDocumentUrl: 'api/docs/openapi.json',
        yamlDocumentUrl: 'api/docs/openapi.yaml',
        swaggerOptions: { persistAuthorization: true },
      });
      new Logger('bootstrap').log('เอกสาร OpenAPI ที่ /api/docs');
    } catch (err) {
      new Logger('bootstrap').error(
        `สร้างเอกสาร OpenAPI ไม่สำเร็จ — API ยังทำงานปกติ: ${(err as Error).stack}`,
      );
    }
  }

  return app;
}

async function bootstrap() {
  const app = await createApp();
  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  new Logger('bootstrap').log(`API พร้อมใช้งานที่ http://localhost:${port}/api/v1`);
}

if (require.main === module) {
  bootstrap().catch((err) => {
    // eslint-disable-next-line no-console
    console.error('เริ่มระบบไม่สำเร็จ:', err.message);
    process.exit(1);
  });
}

import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, OpenAPIObject, SwaggerModule } from '@nestjs/swagger';
import { PUBLIC_KEY, ROLES_KEY } from '../auth/auth.guard';
import { THROTTLE_KEY, ThrottleOptions } from '../throttle/throttle.guard';

/**
 * เอกสาร OpenAPI
 *
 * ─── ทำไมไม่ใส่ decorator ทีละ endpoint ───
 * @Roles() และ @Throttle() ที่ติดอยู่บนทุก endpoint อยู่แล้วคือข้อมูล
 * ที่คนอ่านเอกสารต้องการที่สุด — ใครเรียกได้ และยิงได้ถี่แค่ไหน
 *
 * ถ้าเขียน @ApiOperation ซ้ำอีกชุด ข้อมูลสองชุดจะค่อย ๆ เพี้ยนจากกัน
 * แล้วเอกสารจะโกหกอย่างมั่นใจ ซึ่งแย่กว่าไม่มีเอกสาร
 * ตัวนี้จึงอ่านจาก metadata ที่บังคับใช้จริงแทน — เอกสารจึงผิดไม่ได้
 * เพราะมันคือกฎตัวเดียวกับที่ guard ใช้
 */
export function buildOpenApi(app: INestApplication): OpenAPIObject {
  const config = new DocumentBuilder()
    .setTitle('API ระบบบริหารวิทยาลัยอาชีวศึกษาเอกชน')
    .setDescription(
      [
        'กฎทางธุรกิจทั้งหมดอยู่ในฐานข้อมูล ชั้น API เป็นทางผ่าน',
        '',
        '**ทุกคำขอต้องแนบ Bearer token** ยกเว้น `/health` และ `/auth/*` ที่ระบุว่าสาธารณะ',
        '',
        'การจำกัดบทบาทที่ชั้น API เป็นเพียงชั้นแรก ฐานข้อมูลบังคับซ้ำอีกชั้นด้วย',
        'Row-Level Security ถ้าชั้นใดชั้นหนึ่งพลาด อีกชั้นยังกันอยู่',
        '',
        '**ข้อผิดพลาดที่ควรรู้จัก**',
        '',
        '| รหัส | ความหมาย |',
        '|---|---|',
        '| 401 | ไม่มี token หรือ token หมดอายุ |',
        '| 403 | บทบาทไม่มีสิทธิ์ใช้คำสั่งนี้ |',
        '| 409 | ข้อมูลซ้ำ หรือทับซ้อนกับรายการที่มีอยู่ |',
        '| 422 | กฎทางธุรกิจไม่ผ่าน — ข้อความภาษาไทยจากฐานข้อมูลส่งต่อถึงผู้ใช้ได้เลย |',
        '| 429 | คำขอถี่เกินไป ดูเฮดเดอร์ `Retry-After` |',
      ].join('\n'),
    )
    .setVersion('0.1.0')
    .addBearerAuth(
      { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
      'bearer',
    )
    .build();

  const document = SwaggerModule.createDocument(app, config);
  annotate(app, document);
  return document;
}

/**
 * เติมข้อมูลบทบาทและการจำกัดจำนวนครั้งจาก metadata ที่ guard ใช้จริง
 */
function annotate(app: INestApplication, document: OpenAPIObject): void {
  const server = app.getHttpAdapter().getInstance();
  const router = server?._router ?? server?.router;
  if (!router?.stack) return;

  // จับคู่เส้นทางใน express กับ handler เพื่ออ่าน metadata กลับมา
  const meta = collectMetadata(app);

  for (const [path, item] of Object.entries(document.paths ?? {})) {
    for (const method of ['get', 'post', 'patch', 'put', 'delete'] as const) {
      const op = (item as Record<string, any>)[method];
      if (!op) continue;

      const found = meta.get(`${method.toUpperCase()} ${path}`);
      if (!found) continue;

      const notes: string[] = [];

      if (found.isPublic) {
        notes.push('**สาธารณะ** — ไม่ต้องแนบ token');
        op.security = [];
      } else {
        op.security = [{ bearer: [] }];
        notes.push(
          found.roles?.length
            ? `**บทบาทที่เรียกได้** ${found.roles.join(' · ')}`
            : '**ทุกบทบาท** (RLS จำกัดขอบเขตข้อมูลให้เอง)',
        );
      }

      if (found.throttle === null) {
        notes.push('ไม่จำกัดจำนวนครั้ง');
      } else if (found.throttle) {
        notes.push(
          `จำกัด ${found.throttle.limit} ครั้งต่อ ${found.throttle.windowSecs} วินาที ต่อหนึ่งไอพี`,
        );
      }

      op.description = [op.description, notes.join('  \n')]
        .filter(Boolean)
        .join('\n\n');

      if (!found.isPublic) {
        op.responses = {
          ...op.responses,
          401: { description: 'ไม่มี token หรือ token หมดอายุ' },
          403: { description: 'บทบาทไม่มีสิทธิ์ใช้คำสั่งนี้' },
        };
      }
      op.responses = {
        ...op.responses,
        422: { description: 'กฎทางธุรกิจไม่ผ่าน — ข้อความภาษาไทยจากฐานข้อมูล' },
        429: { description: 'คำขอถี่เกินไป ดูเฮดเดอร์ Retry-After' },
      };
    }
  }
}

interface RouteMeta {
  roles?: string[];
  isPublic?: boolean;
  throttle?: ThrottleOptions | null;
}

/**
 * เดินดู controller ทุกตัวแล้วอ่าน metadata ของ handler
 *
 * ใช้ Reflect โดยตรงแทน Reflector ของ Nest เพราะตอนสร้างเอกสาร
 * เราอยู่นอก request scope จึงไม่มี ExecutionContext ให้ส่งเข้าไป
 */
function collectMetadata(app: INestApplication): Map<string, RouteMeta> {
  const result = new Map<string, RouteMeta>();
  const container = (app as unknown as { container?: any }).container;
  const modules = container?.getModules?.();
  if (!modules) return result;

  const globalPrefix = '/api/v1';

  for (const module of modules.values()) {
    for (const wrapper of module.controllers?.values?.() ?? []) {
      const ctor = wrapper.metatype;
      if (!ctor?.prototype) continue;

      const controllerPath: string = Reflect.getMetadata('path', ctor) ?? '';
      const classRoles: string[] | undefined = Reflect.getMetadata(ROLES_KEY, ctor);
      const classPublic: boolean | undefined = Reflect.getMetadata(PUBLIC_KEY, ctor);
      const classThrottle = Reflect.getMetadata(THROTTLE_KEY, ctor);

      for (const name of Object.getOwnPropertyNames(ctor.prototype)) {
        if (name === 'constructor') continue;

        // ต้องอ่านผ่าน descriptor ห้ามแตะ ctor.prototype[name] ตรง ๆ
        // เพราะ controller อาจมี getter (เช่น devEnabled ใน AuthController)
        // การอ่านค่าจะไป **เรียก** getter นั้นด้วย this ที่เป็น prototype
        // ซึ่งไม่มี dependency ที่ inject ไว้ แล้วพังทั้งการสร้างเอกสาร
        const descriptor = Object.getOwnPropertyDescriptor(ctor.prototype, name);
        const handler = descriptor?.value;
        if (typeof handler !== 'function') continue;

        const methodPath: string | undefined = Reflect.getMetadata('path', handler);
        const httpMethod: number | undefined = Reflect.getMetadata('method', handler);
        if (methodPath === undefined || httpMethod === undefined) continue;

        const verb = HTTP_VERBS[httpMethod] ?? 'GET';
        const full = normalise(
          `${globalPrefix}/${controllerPath}/${methodPath}`.replace(/\/+/g, '/'),
        );

        const roles = Reflect.getMetadata(ROLES_KEY, handler) ?? classRoles;
        const isPublic = Reflect.getMetadata(PUBLIC_KEY, handler) ?? classPublic;
        const throttleRaw = Reflect.getMetadata(THROTTLE_KEY, handler);
        const throttle =
          throttleRaw !== undefined ? throttleRaw : classThrottle;

        result.set(`${verb} ${full}`, { roles, isPublic, throttle });
      }
    }
  }
  return result;
}

/** `:id` ของ express → `{id}` ของ OpenAPI */
function normalise(path: string): string {
  const withBraces = path.replace(/:([A-Za-z0-9_]+)/g, '{$1}');
  return withBraces.length > 1 && withBraces.endsWith('/')
    ? withBraces.slice(0, -1)
    : withBraces;
}

const HTTP_VERBS: Record<number, string> = {
  0: 'GET',
  1: 'POST',
  2: 'PUT',
  3: 'DELETE',
  4: 'PATCH',
  5: 'ALL',
  6: 'OPTIONS',
  7: 'HEAD',
};

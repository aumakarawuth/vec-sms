import {
  Injectable,
  InternalServerErrorException,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryResultRow } from 'pg';
import { RequestContext, UserContext } from '../context/request-context';

/**
 * ทางเดียวที่โค้ดในระบบนี้แตะฐานข้อมูลได้
 *
 * ─── เหตุผลที่ต้องบังคับให้ทุกอย่างผ่าน tx() ───
 * Row-Level Security ในฐานข้อมูลอ่านค่าจาก app.institution_id, app.actor_id
 * และ app.role ถ้าโค้ดที่ไหนสักแห่งเผลอ query ตรงจาก pool โดยไม่ตั้งค่าเหล่านี้
 * มันจะได้ศูนย์แถว ไม่ใช่ข้อมูลของคนอื่น — แต่ที่แย่กว่าคือถ้าเชื่อมต่อด้วย
 * superuser มันจะได้ข้อมูลทั้งหมดของทุกวิทยาลัย คลาสนี้จึงไม่เปิด pool ออกไปเลย
 *
 * ─── ทำไมใช้ set_config(..., true) ไม่ใช่ SET ───
 * พารามิเตอร์ตัวที่สามคือ is_local เทียบเท่า SET LOCAL คือมีผลเฉพาะใน
 * transaction นี้ ถ้าใช้ SET เฉย ๆ ค่าจะติดอยู่กับ connection แล้วผู้ใช้คนถัดไป
 * ที่หยิบ connection เดิมจาก pool จะได้สิทธิ์ของคนก่อนหน้า ซึ่งเป็นช่องโหว่จริง
 * ที่เกิดขึ้นบ่อยในระบบที่ใช้ connection pool ร่วมกับ RLS
 */
@Injectable()
export class DbService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DbService.name);
  private pool: Pool;

  constructor(private readonly config: ConfigService) {}

  async onModuleInit(): Promise<void> {
    const url = this.config.get<string>('DATABASE_URL');
    if (!url) {
      throw new Error('ต้องกำหนด DATABASE_URL');
    }

    this.pool = new Pool({
      connectionString: url,
      max: Number(this.config.get('DB_POOL_MAX') ?? 10),
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 10_000,
      application_name: 'vec-sms-api',

      // ─── เพดานเวลาของคำสั่ง ─────────────────────────────────────
      //
      // ไม่มีเพดานแปลว่า query เดียวที่ช้าผิดปกติจะยึด connection ไว้ไม่ปล่อย
      // pool มีแค่สิบ connection ดังนั้นคำขอช้าสิบรายการพร้อมกัน = ระบบล่มทั้งตัว
      // ทั้งที่ฐานข้อมูลยังทำงานปกติ ซึ่งเป็นวิธีทำให้ระบบล่มที่ถูกที่สุด
      // สำหรับผู้โจมตี และเกิดเองได้จากรายงานที่เขียน query ไม่ดี
      //
      // idle_in_transaction ป้องกันอีกแบบ — transaction ที่เปิดค้างไว้
      // เพราะโค้ดฝั่งแอปค้าง จะบล็อก autovacuum และทำให้ตารางบวมขึ้นเรื่อย ๆ
      statement_timeout: Number(this.config.get('DB_STATEMENT_TIMEOUT_MS') ?? 15_000),
      idle_in_transaction_session_timeout: Number(
        this.config.get('DB_IDLE_TX_TIMEOUT_MS') ?? 30_000,
      ),
    });

    const probe = await this.pool.query<{
      current_user: string;
      rolsuper: boolean;
      rolbypassrls: boolean;
    }>(
      `select current_user, r.rolsuper, r.rolbypassrls
       from pg_roles r where r.rolname = current_user`,
    );

    const who = probe.rows[0];
    this.logger.log(`เชื่อมต่อฐานข้อมูลด้วยผู้ใช้ ${who.current_user}`);

    // กันความผิดพลาดที่ร้ายแรงที่สุด: ถ้าแอปเชื่อมต่อด้วย superuser
    // RLS ทั้งหมดจะถูกข้าม กำแพงกันข้อมูลข้ามวิทยาลัยจะไม่ทำงานเลย
    // และไม่มีอะไรฟ้อง ระบบจะดูปกติจนกว่าจะมีคนร้องเรียน
    if (who.rolsuper || who.rolbypassrls) {
      const message =
        `ผู้ใช้ฐานข้อมูล "${who.current_user}" เป็น superuser หรือมีสิทธิ์ข้าม RLS ` +
        `ซึ่งทำให้กำแพงกันข้อมูลข้ามสถานศึกษาไม่ทำงาน ` +
        `ให้เชื่อมต่อด้วยผู้ใช้ที่อยู่ในกลุ่ม app_runtime แทน (ดู db/deploy/roles.sql)`;

      if (this.config.get('ALLOW_SUPERUSER') === 'true') {
        this.logger.error(`ข้ามการตรวจเพราะตั้ง ALLOW_SUPERUSER=true — ${message}`);
      } else {
        throw new Error(message);
      }
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool?.end();
  }

  /**
   * เปิด transaction พร้อมตั้งบริบทผู้ใช้จาก AsyncLocalStorage
   * ถ้าไม่มีบริบท จะโยนข้อผิดพลาดทันที ไม่ยอมให้ query หลุดออกไปแบบไร้บริบท
   */
  async tx<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
    const ctx = RequestContext.get();
    if (!ctx) {
      throw new InternalServerErrorException(
        'คำขอนี้ไม่มีบริบทผู้ใช้ จึงเข้าถึงฐานข้อมูลไม่ได้ ' +
          '(งานเบื้องหลังต้องใช้ runAs() และระบุสถานศึกษาให้ชัดเจน)',
      );
    }
    return this.runWith(ctx, fn);
  }

  /**
   * สำหรับงานเบื้องหลังที่ไม่มีผู้ใช้จริง เช่น งานประจำคืน
   * ต้องระบุสถานศึกษาและบทบาทอย่างชัดเจน ไม่มีค่าเริ่มต้นให้เผลอใช้
   */
  async runAs<T>(ctx: UserContext, fn: (c: PoolClient) => Promise<T>): Promise<T> {
    return this.runWith(ctx, fn);
  }

  /**
   * เรียกฟังก์ชันที่ต้องทำงาน **ก่อน** รู้ว่าผู้เรียกเป็นใคร
   *
   * ─── ทำไมต้องมีทางนี้ และทำไมมันไม่ใช่ประตูหลัง ───
   * ตัวจำกัดคำขอทำงานก่อน AuthGuard จึงไม่มีบริบทผู้ใช้ให้ตั้ง — นั่นคือ
   * หน้าที่ของมัน `tx()` โยนทิ้งอย่างถูกต้องแล้วเมื่อไม่มีบริบท
   * (เคยพลาดมาแล้วตอนเปิดวิทยาลัยใหม่ ดูข้อ 7 ในรายการที่เคยพังแบบเงียบ ๆ)
   * แต่การยอมให้ตัวจำกัดคำขอ "ผ่านไปก่อน" ทุกครั้งก็เท่ากับไม่มีตัวจำกัด
   *
   * ทางนี้ไม่ตั้ง `app.*` เลยสักตัว ซึ่งแปลว่า `current_institution_id()`
   * เป็น null และ `current_app_role()` เป็น 'none' — นโยบาย RLS ชั้นแรก
   * ของ **ทุกตาราง** จึงปฏิเสธทุกแถวโดยอัตโนมัติ หลักเดียวกับที่ทำให้
   * บัญชีผู้ให้บริการมองไม่เห็นข้อมูลของลูกค้า (หลัก 5ค) สิ่งเดียวที่
   * เรียกผ่านทางนี้ได้ผลจริงคือฟังก์ชัน `security definer` ที่ตั้งใจเปิดไว้
   *
   * ใช้กับ `request_rate_hit()` เท่านั้น อย่าใช้เพื่อเลี่ยงการตั้งบริบท
   */
  async queryWithoutContext<T extends QueryResultRow = QueryResultRow>(
    sql: string,
    params: unknown[] = [],
  ): Promise<T[]> {
    const client = await this.pool.connect();
    try {
      return (await client.query<T>(sql, params)).rows;
    } finally {
      client.release();
    }
  }

  /**
   * เปลี่ยนบริบทกลางทรานแซกชัน
   *
   * ─── มีไว้เพื่อกรณีเดียว: การเปิดวิทยาลัยใหม่ ───
   * ตอนทรานแซกชันเริ่ม วิทยาลัยที่กำลังจะสร้างยังไม่มีอยู่ จึงตั้ง
   * app.institution_id เป็นค่านั้นไม่ได้ แต่ขั้นตอนหลังจากสร้างเสร็จ
   * (ออกรหัสรีเซ็ตให้ผู้ดูแลคนแรก) ต้องอ่านตารางที่มี RLS ของวิทยาลัยนั้น
   *
   * แยกทั้งสองขั้นเป็นคนละทรานแซกชันไม่ได้ เพราะถ้าขั้นหลังล้ม วิทยาลัย
   * ที่ commit ไปแล้วจะเหลือค้างโดยไม่มีใครเข้าได้และเปิดซ้ำก็ไม่ได้
   * เพราะรหัสสถานศึกษาชนตัวเอง
   *
   * ใช้ is_local = true เหมือน runWith() ค่าจึงหายไปพร้อมทรานแซกชัน
   * ไม่ติดค้างไปกับ connection ให้คำขอถัดไปหยิบไปใช้
   */
  async switchContext(c: PoolClient, ctx: UserContext): Promise<void> {
    await c.query(
      `select set_config('app.institution_id', $1, true),
              set_config('app.actor_id',       $2, true),
              set_config('app.role',           $3, true)`,
      [ctx.institutionId, ctx.actorId ?? '', ctx.role],
    );
  }

  private async runWith<T>(
    ctx: UserContext,
    fn: (c: PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      await this.switchContext(client, ctx);
      const result = await fn(client);
      await client.query('commit');
      return result;
    } catch (err) {
      await client.query('rollback').catch(() => undefined);
      throw err;
    } finally {
      client.release();
    }
  }

  /** ตัวช่วยสั้น ๆ สำหรับ query เดียวจบ */
  async query<T extends QueryResultRow = QueryResultRow>(
    sql: string,
    params: unknown[] = [],
  ): Promise<T[]> {
    return this.tx(async (c) => (await c.query<T>(sql, params)).rows);
  }

  async queryOne<T extends QueryResultRow = QueryResultRow>(
    sql: string,
    params: unknown[] = [],
  ): Promise<T | undefined> {
    const rows = await this.query<T>(sql, params);
    return rows[0];
  }

  /** ใช้เฉพาะตอน health check — ไม่ผ่าน RLS เพราะไม่แตะข้อมูลใด ๆ */
  async ping(): Promise<{ ok: boolean; version: string }> {
    const r = await this.pool.query<{ version: string }>('select version()');
    return { ok: true, version: r.rows[0].version };
  }

  /**
   * ทะเบียนสถานศึกษา — ใช้ตอนงานประจำคืนที่ต้องวนทุกสถานศึกษา
   *
   * ตาราง institution ไม่มี RLS โดยเจตนา เพราะมันคือตัวกำหนดขอบเขตเอง
   * จะเอา current_institution_id() มากรองตัวเองไม่ได้ (ไก่กับไข่)
   * แถวในตารางนี้มีแค่รหัสกับชื่อสถานศึกษา ไม่มีข้อมูลส่วนบุคคลเลย
   *
   * ห้ามใช้เมธอดนี้ในเส้นทางที่ผู้ใช้เรียกได้ — งานเบื้องหลังเท่านั้น
   */
  async listInstitutions(): Promise<{ id: string; code: string; name_th: string }[]> {
    const r = await this.pool.query<{ id: string; code: string; name_th: string }>(
      'select id, code, name_th from institution order by code',
    );
    return r.rows;
  }
}

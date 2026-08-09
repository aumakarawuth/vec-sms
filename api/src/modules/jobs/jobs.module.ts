import {
  Controller,
  Get,
  Injectable,
  Logger,
  Module,
  NotFoundException,
  OnApplicationBootstrap,
  OnModuleDestroy,
  Param,
  Post,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';

/**
 * งานตามกำหนดเวลา
 *
 * ─── ทำไมต้องมีตัวนี้ ───
 * ฟังก์ชันในฐานข้อมูลพร้อมมานานแล้ว แต่ถ้าไม่มีใครเรียก ระบบสองอย่างจะเงียบสนิท
 * โดยไม่มีอะไรฟ้อง — การระงับสิทธิ์ของคนค้างชำระจะไม่เกิดขึ้นเลย และคะแนน
 * ความเสี่ยงจะค้างอยู่ที่ค่าเดิมตลอดภาคเรียน ครูที่ปรึกษาจะเปิดหน้าจอเฝ้าระวัง
 * แล้วเห็นข้อมูลของเมื่อสามเดือนก่อนโดยไม่รู้ตัว
 *
 * ─── ทำไมไม่ใช้ @nestjs/schedule ───
 * งานทั้งหมดที่นี่คือ "วันละครั้งตอนตีหนึ่งครึ่ง" ซึ่ง setTimeout เขียนได้ครบ
 * ระบบนี้ต้องอยู่ไปอีกหลายปีและถูกอัปเกรด Node กับ NestJS หลายรอบ
 * การไม่เพิ่ม dependency ที่ต้องรอตามรุ่นจึงคุ้มกว่าความสะดวกของ decorator
 *
 * ─── ทำไมวนทีละสถานศึกษาแล้วดักข้อผิดพลาดแยกกัน ───
 * refresh_finance_holds() และ compute_risk_scores() จะ raise ถ้าสถานศึกษานั้น
 * ยังไม่ได้ตั้งนโยบาย ถ้าปล่อยให้หลุดออกไป สถานศึกษาแรกที่ตั้งค่าไม่ครบจะทำให้
 * ที่เหลือทั้งหมดไม่ถูกประมวลผล ซึ่งเป็นความล้มเหลวแบบเงียบที่แย่ที่สุด
 */

export const JOB_NAMES = [
  'risk',
  'finance-holds',
  'usage-snapshot',
  'purge-login-attempts',
  'purge-password-reset',
] as const;
export type JobName = (typeof JOB_NAMES)[number];

export interface InstitutionOutcome {
  institution: string;
  code: string;
  ok: boolean;
  detail?: unknown;
  error?: string;
}

export interface JobRun {
  job: JobName;
  startedAt: string;
  durationMs: number;
  ok: number;
  failed: number;
  results: InstitutionOutcome[];
}

@Injectable()
export class JobsService implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger(JobsService.name);
  private timer?: NodeJS.Timeout;
  private nextRunAt?: Date;
  private lastRuns = new Map<JobName, JobRun>();

  constructor(
    private readonly db: DbService,
    private readonly config: ConfigService,
  ) {}

  onApplicationBootstrap(): void {
    if (this.config.get('JOBS_ENABLED') === 'false') {
      this.logger.log('งานตามกำหนดเวลาถูกปิดไว้ (JOBS_ENABLED=false)');
      return;
    }
    this.scheduleNext();
  }

  onModuleDestroy(): void {
    if (this.timer) clearTimeout(this.timer);
  }

  // ─── ตัวตั้งเวลา ─────────────────────────────────────────────────

  /**
   * ตั้งเวลาครั้งถัดไปแล้วคำนวณใหม่ทุกครั้งหลังรันเสร็จ
   *
   * ไม่ใช้ setInterval(24 ชม.) เพราะเวลาที่ใช้รันจริงจะสะสมไปเรื่อย ๆ
   * จนงานเลื่อนไปตกกลางวันภายในไม่กี่เดือน การคำนวณจากนาฬิกาใหม่ทุกครั้ง
   * ทำให้เวลาที่รันคงที่เสมอ
   */
  private scheduleNext(): void {
    const at = this.config.get<string>('JOBS_DAILY_AT') ?? '01:30';
    const delay = this.msUntil(at);
    this.nextRunAt = new Date(Date.now() + delay);

    this.timer = setTimeout(() => {
      void this.runAll().finally(() => this.scheduleNext());
    }, delay);

    // ไม่ให้ timer ค้างไม่ให้โปรเซสปิด — สำคัญตอนรันเทสต์และตอน deploy ใหม่
    this.timer.unref?.();

    this.logger.log(
      `งานประจำวันถัดไป ${this.nextRunAt.toLocaleString('th-TH')} ` +
        `(เขตเวลาของโปรเซส: ${Intl.DateTimeFormat().resolvedOptions().timeZone})`,
    );
  }

  private msUntil(hhmm: string): number {
    const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm.trim());
    if (!m) {
      this.logger.warn(`JOBS_DAILY_AT="${hhmm}" อ่านไม่ออก ใช้ 01:30 แทน`);
      return this.msUntil('01:30');
    }
    const now = new Date();
    const next = new Date(now);
    next.setHours(Number(m[1]), Number(m[2]), 0, 0);
    if (next <= now) next.setDate(next.getDate() + 1);
    return next.getTime() - now.getTime();
  }

  // ─── ตัวรัน ─────────────────────────────────────────────────────

  async runAll(): Promise<JobRun[]> {
    const runs: JobRun[] = [];
    for (const job of JOB_NAMES) {
      runs.push(await this.run(job));
    }
    return runs;
  }

  async run(job: JobName): Promise<JobRun> {
    const startedAt = new Date();
    const institutions = await this.db.listInstitutions();
    const results: InstitutionOutcome[] = [];

    for (const inst of institutions) {
      try {
        const detail = await this.db.runAs(
          // actorId ว่างแปลว่า current_actor_id() คืน null — บันทึกที่งานนี้เขียน
          // จะไม่ถูกอ้างว่าเป็นฝีมือของเจ้าหน้าที่คนใดคนหนึ่ง ซึ่งตรงกับความจริง
          { institutionId: inst.id, actorId: '', role: 'admin' },
          (c) => this.execute(job, c),
        );
        results.push({ institution: inst.id, code: inst.code, ok: true, detail });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        this.logger.error(`งาน ${job} ล้มเหลวที่สถานศึกษา ${inst.code} — ${message}`);
        results.push({ institution: inst.id, code: inst.code, ok: false, error: message });
      }
    }

    const run: JobRun = {
      job,
      startedAt: startedAt.toISOString(),
      durationMs: Date.now() - startedAt.getTime(),
      ok: results.filter((r) => r.ok).length,
      failed: results.filter((r) => !r.ok).length,
      results,
    };

    this.lastRuns.set(job, run);
    this.logger.log(
      `งาน ${job} เสร็จใน ${run.durationMs} มิลลิวินาที — สำเร็จ ${run.ok} ล้มเหลว ${run.failed}`,
    );
    return run;
  }

  /** เนื้องานจริงของแต่ละงาน รันอยู่ในบริบทของสถานศึกษาหนึ่งแล้ว */
  private async execute(
    job: JobName,
    c: Parameters<Parameters<DbService['runAs']>[1]>[0],
  ): Promise<unknown> {
    switch (job) {
      case 'risk': {
        // ภาคเรียนที่กำลังเรียนอยู่เท่านั้น ภาคที่ปิดแล้วคะแนนความเสี่ยงไม่มีความหมาย
        // และภาคที่ยังไม่เปิดก็ยังไม่มีข้อมูลการเข้าเรียนให้คิด
        const terms = (
          await c.query<{ id: string }>(
            `select id from term where status = 'open' order by starts_on`,
          )
        ).rows;

        const perTerm = [];
        for (const t of terms) {
          const scored = await c.query<{ n: number }>(
            `select compute_risk_scores(current_institution_id(), $1) as n`,
            [t.id],
          );
          const opened = await c.query<{ n: number }>(
            `select open_intervention_cases(current_institution_id(), $1) as n`,
            [t.id],
          );
          perTerm.push({
            termId: t.id,
            evaluated: Number(scored.rows[0].n),
            casesOpened: Number(opened.rows[0].n),
          });
        }
        return { terms: perTerm };
      }

      case 'finance-holds': {
        const r = await c.query<{ placed: number; released: number }>(
          `select * from refresh_finance_holds(current_institution_id())`,
        );
        return {
          placed: Number(r.rows[0]?.placed ?? 0),
          released: Number(r.rows[0]?.released ?? 0),
        };
      }

      case 'usage-snapshot': {
        /*
         * ─── ทำไมปริมาณใช้งานต้องเก็บเป็นภาพนิ่ง ไม่ใช่นับสดตอนออกใบเรียกเก็บ ───
         * จำนวนนักศึกษาเปลี่ยนทุกวัน การนับย้อนหลังจะได้ตัวเลขคนละอย่างทุกครั้ง
         * ที่นับ แล้วเถียงกับลูกค้าไม่จบว่าเดือนนั้นมีกี่คนกันแน่ (ดู 0038)
         *
         * ─── ทำไมงานนี้ต้องอยู่ตรงนี้ ไม่ใช่ในหน้าจอผู้ให้บริการ ───
         * take_usage_snapshot() นับข้อมูลของวิทยาลัยและต้องถูก RLS กรอง
         * ตามปกติ จึงต้องรันในบริบทของวิทยาลัยนั้นเอง ซึ่งงานเบื้องหลังมี
         * โดยชอบอยู่แล้ว ถ้าให้หน้าจอผู้ให้บริการนับเอง มันจะต้องยืมบริบท
         * ของวิทยาลัยมาใช้ — ซึ่งเปิดทางให้อ่านอะไรก็ได้ในวิทยาลัยนั้น
         * หน้าจอฝั่งผู้ให้บริการจึงอ่านจาก usage_snapshot อย่างเดียว
         */
        const r = await c.query<{ students_active: number; staff_active: number }>(
          `select students_active, staff_active
             from take_usage_snapshot(current_institution_id())`,
        );
        return {
          studentsActive: Number(r.rows[0]?.students_active ?? 0),
          staffActive: Number(r.rows[0]?.staff_active ?? 0),
        };
      }

      case 'purge-login-attempts': {
        // ต่ำกว่า 90 วันไม่ได้ตาม พ.ร.บ.คอมพิวเตอร์ มาตรา 26
        const configured = Number(this.config.get('LOGIN_LOG_KEEP_DAYS') ?? 90);
        const keepDays = Number.isFinite(configured) ? Math.max(90, configured) : 90;
        const r = await c.query<{ n: number }>(
          `select purge_login_attempts($1) as n`,
          [keepDays],
        );
        return { deleted: Number(r.rows[0].n), keepDays };
      }

      case 'purge-password-reset': {
        // ใช้ระยะเก็บเดียวกับบันทึกการเข้าสู่ระบบ เพราะเป็นหลักฐานชุดเดียวกัน
        // เวลาสอบสวนว่าบัญชีถูกยึดได้อย่างไร ฟังก์ชันในฐานข้อมูลปฏิเสธค่า
        // ต่ำกว่า 90 วันอยู่แล้ว การบีบค่าที่นี่ด้วยทำให้ได้ข้อความที่อ่านง่ายกว่า
        const configured = Number(this.config.get('LOGIN_LOG_KEEP_DAYS') ?? 90);
        const keepDays = Number.isFinite(configured) ? Math.max(90, configured) : 90;
        const r = await c.query<{ n: number }>(
          `select purge_password_reset($1) as n`,
          [keepDays],
        );
        return { deleted: Number(r.rows[0].n), keepDays };
      }
    }
  }

  status() {
    return {
      enabled: this.config.get('JOBS_ENABLED') !== 'false',
      dailyAt: this.config.get('JOBS_DAILY_AT') ?? '01:30',
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      nextRunAt: this.nextRunAt?.toISOString() ?? null,
      jobs: JOB_NAMES.map((name) => ({
        name,
        lastRun: this.lastRuns.get(name) ?? null,
      })),
    };
  }
}

/**
 * เรียกด้วยมือได้ เพื่อให้ตัวตั้งเวลาของแพลตฟอร์ม (Render, Fly, Cloud Scheduler)
 * ยิงเข้ามาแทนตัวตั้งเวลาในโปรเซสได้ ซึ่งจำเป็นเมื่อรันหลาย instance
 * เพราะถ้าปล่อยให้ทุก instance ตั้งเวลาเอง งานจะถูกรันซ้ำพร้อมกัน
 */
@Roles('admin', 'director')
@Controller('jobs')
class JobsController {
  constructor(private readonly svc: JobsService) {}

  @Get()
  status() {
    return this.svc.status();
  }

  @Post('run')
  runAll() {
    return this.svc.runAll();
  }

  @Post('run/:name')
  run(@Param('name') name: string) {
    if (!(JOB_NAMES as readonly string[]).includes(name)) {
      throw new NotFoundException(
        `ไม่มีงานชื่อ "${name}" — มีให้เรียกคือ ${JOB_NAMES.join(', ')}`,
      );
    }
    return this.svc.run(name as JobName);
  }
}

@Module({
  controllers: [JobsController],
  providers: [JobsService],
  exports: [JobsService],
})
export class JobsModule {}

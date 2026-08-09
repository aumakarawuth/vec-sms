import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DbService } from '../../common/db/db.service';
import { JobsService } from '../jobs/jobs.module';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformRole, platformCtx } from './platform.guard';

/**
 * งานของหน้าจอผู้ดูแลข้ามวิทยาลัย
 *
 * ─── ขอบเขตที่ยึดไว้ทั้งไฟล์ ───
 * ทุกเมธอดทำงานในบริบทผู้ให้บริการเท่านั้น (ไม่มีวิทยาลัย) จึงอ่านได้แค่
 * ทะเบียนสถานศึกษา แพ็กเกจ สัญญา ปริมาณใช้งานที่เก็บเป็นภาพนิ่ง และ
 * ประวัติการเปิดวิทยาลัย — ที่เหลือ RLS คืนศูนย์แถวให้เองโดยไม่ต้องเขียนกฎ
 *
 * **ห้ามใช้ db.runAs() ด้วย institutionId ของลูกค้าในไฟล์นี้เด็ดขาด**
 * นั่นคือการยืมบริบทของวิทยาลัยมาอ่านข้อมูล ซึ่งทำให้กำแพงทั้งหมดไม่มีผล
 * ตัวเลขปริมาณใช้งานจึงอ่านจาก usage_snapshot ที่งานประจำวันเก็บไว้
 * ไม่ใช่ไปนับสดในบริบทของลูกค้า
 */
@Injectable()
export class PlatformService {
  constructor(
    private readonly db: DbService,
    private readonly auth: PlatformAuthService,
    private readonly jobs: JobsService,
  ) {}

  /** บันทึกทุกการกระทำที่เปลี่ยนแปลงอะไรของลูกค้า */
  private async log(
    actorId: string,
    action: string,
    institutionId: string | null,
    detail: unknown,
  ) {
    await this.db.runAs(platformCtx(actorId), (c) =>
      c.query(`select log_platform_action($1, $2, $3::jsonb, null)`, [
        action,
        institutionId,
        JSON.stringify(detail ?? {}),
      ]),
    );
  }

  // ── ทะเบียนวิทยาลัย ────────────────────────────────────────────────

  /**
   * รายชื่อวิทยาลัยพร้อมสถานะทางธุรกิจ
   *
   * รวมมาจาก query เดียวโดยตั้งใจ — ถ้าวนอ่านทีละแห่ง จำนวนคำสั่งจะโต
   * ตามจำนวนลูกค้า และหน้าจอแรกที่ผู้ให้บริการเปิดทุกเช้าจะช้าลงเรื่อย ๆ
   * ตามความสำเร็จของธุรกิจเอง
   */
  async institutions(actorId: string) {
    const rows = await this.db.runAs(platformCtx(actorId), async (c) =>
      (
        await c.query(
          `select i.id, i.code, i.name_th, i.created_at,
                  i.suspended_at, i.suspended_reason,
                  s.status            as subscription_status,
                  s.starts_on, s.ends_on, s.seats_purchased,
                  p.code              as plan_code,
                  p.name_th           as plan_name_th,
                  p.max_students, p.enforcement, p.grace_percent,
                  u.taken_on          as usage_taken_on,
                  u.students_active, u.staff_active,
                  case
                    when p.max_students is null then null
                    else greatest(0, coalesce(u.students_active, 0)
                           - (p.max_students + coalesce(s.seats_purchased, 0)))
                  end                 as over_students
             from institution i
             left join lateral (
               select * from institution_subscription s2
                where s2.institution_id = i.id
                  and s2.status in ('trial', 'active', 'past_due')
                  and s2.starts_on <= current_date
                  and (s2.ends_on is null or s2.ends_on >= current_date)
                order by s2.starts_on desc limit 1
             ) s on true
             left join plan p on p.id = s.plan_id
             left join lateral (
               select * from usage_snapshot u2
                where u2.institution_id = i.id
                order by u2.taken_on desc limit 1
             ) u on true
            order by i.code`,
        )
      ).rows,
    );

    return {
      institutions: rows.length,
      suspended: rows.filter((r: any) => r.suspended_at).length,
      unassigned: rows.filter((r: any) => !r.plan_code).length,
      overQuota: rows.filter((r: any) => Number(r.over_students ?? 0) > 0).length,
      // บอกตรง ๆ ว่าตัวเลขมาจากภาพนิ่งวันไหน ไม่ใช่ปล่อยให้เข้าใจว่าเป็นสด
      note:
        'จำนวนนักศึกษาและบุคลากรมาจากภาพนิ่งล่าสุดของงานประจำวัน ' +
        'ไม่ใช่ตัวเลขสด — สั่งเก็บใหม่ได้ที่ POST /platform/usage/refresh',
      rows,
    };
  }

  /**
   * บันทึกว่าใครเปิดวิทยาลัยแห่งนี้
   *
   * provisioning_log (0037) เก็บว่าวิทยาลัยถูกเปิดเมื่อไร แต่ช่องผู้ขอเป็น
   * ข้อความอิสระที่ผู้เรียกกรอกเอง — ตอบไม่ได้ว่าบัญชีไหนเป็นคนกด
   * บันทึกตรงนี้ผูกกับบัญชีจริงและแก้ไม่ได้
   */
  async recordProvision(actorId: string, institutionId: string, code: string) {
    await this.log(actorId, 'provision_institution', institutionId, { code });
  }

  async institution(actorId: string, institutionId: string) {
    return this.db.runAs(platformCtx(actorId), async (c) => {
      const inst = (
        await c.query(
          `select id, code, name_th, name_en, sector, created_at,
                  suspended_at, suspended_reason
             from institution where id = $1`,
          [institutionId],
        )
      ).rows[0];
      if (!inst) throw new NotFoundException('ไม่พบสถานศึกษาที่ระบุ');

      const subscriptions = (
        await c.query(
          `select s.id, s.starts_on, s.ends_on, s.status, s.seats_purchased, s.note,
                  p.code as plan_code, p.name_th as plan_name_th, p.price_per_year
             from institution_subscription s
             join plan p on p.id = s.plan_id
            where s.institution_id = $1
            order by s.starts_on desc`,
          [institutionId],
        )
      ).rows;

      const usage = (
        await c.query(
          `select taken_on, students_active, staff_active, documents_issued, applications
             from usage_snapshot where institution_id = $1
            order by taken_on desc limit 90`,
          [institutionId],
        )
      ).rows;

      const provisioning = (
        await c.query(
          `select code, name_th, requested_by, created_at
             from provisioning_log where institution_id = $1
            order by created_at desc`,
          [institutionId],
        )
      ).rows;

      const actions = (
        await c.query(
          `select username, action, detail, occurred_at
             from platform_action_log where institution_id = $1
            order by occurred_at desc limit 50`,
          [institutionId],
        )
      ).rows;

      return { institution: inst, subscriptions, usage, provisioning, actions };
    });
  }

  // ── ระงับ / คืนสิทธิ์ ──────────────────────────────────────────────

  /**
   * ระงับการใช้งานของวิทยาลัย
   *
   * ปิดแค่ทางเข้า — ไม่ลบและไม่ซ่อนข้อมูล ลูกค้าที่ค้างชำระยังเป็นเจ้าของ
   * ข้อมูลของตัวเองอยู่ การยึดข้อมูลไว้เป็นตัวประกันผิดทั้งทางกฎหมาย
   * และทางธุรกิจ
   */
  async suspend(actorId: string, institutionId: string, reason: string) {
    const row = await this.db.runAs(platformCtx(actorId), async (c) =>
      (
        await c.query(
          `select id, code, name_th, suspended_at, suspended_reason
             from suspend_institution($1, $2)`,
          [institutionId, reason],
        )
      ).rows[0],
    );

    await this.log(actorId, 'suspend_institution', institutionId, { reason });
    return {
      ...row,
      note: 'ผู้ใช้ทุกคนของวิทยาลัยนี้เข้าระบบไม่ได้จนกว่าจะคืนสิทธิ์ ข้อมูลทั้งหมดยังอยู่ครบ',
    };
  }

  async resume(actorId: string, institutionId: string, note?: string) {
    const row = await this.db.runAs(platformCtx(actorId), async (c) =>
      (
        await c.query(
          `select id, code, name_th, suspended_at from resume_institution($1)`,
          [institutionId],
        )
      ).rows[0],
    );

    await this.log(actorId, 'resume_institution', institutionId, { note });
    return { ...row, note: 'คืนสิทธิ์แล้ว ผู้ใช้เข้าระบบได้ทันที' };
  }

  // ── แพ็กเกจ ────────────────────────────────────────────────────────

  async plans(actorId: string) {
    return this.db.runAs(platformCtx(actorId), async (c) =>
      (
        await c.query(
          `select p.id, p.code, p.name_th, p.max_students, p.max_staff,
                  p.price_per_year, p.price_per_student, p.enforcement,
                  p.grace_percent, p.features, p.active, p.sort_order,
                  (select count(*) from institution_subscription s
                    where s.plan_id = p.id and s.status in ('trial','active','past_due'))
                    as institutions
             from plan p order by p.sort_order, p.price_per_year`,
        )
      ).rows,
    );
  }

  /**
   * สร้างหรือแก้แพ็กเกจ
   *
   * ─── ทำไมแก้ราคาแพ็กเกจเดิมได้ แต่ต้องบันทึกไว้เสมอ ───
   * ราคาที่เปลี่ยนมีผลกับทุกวิทยาลัยที่ผูกแพ็กเกจนั้นอยู่ในงวดถัดไป
   * ซึ่งเป็นการกระทำที่กระทบสัญญาหลายฉบับพร้อมกันโดยไม่มีใครเห็น
   * บันทึกจึงเก็บทั้งค่าเดิมและค่าใหม่ ไม่ใช่แค่ว่า "มีคนแก้แพ็กเกจ"
   */
  async upsertPlan(
    actorId: string,
    dto: {
      code: string;
      nameTh: string;
      maxStudents?: number | null;
      maxStaff?: number | null;
      pricePerYear?: number;
      pricePerStudent?: number;
      enforcement?: 'soft' | 'hard';
      gracePercent?: number;
      active?: boolean;
      sortOrder?: number;
    },
  ) {
    const { before, after } = await this.db.runAs(platformCtx(actorId), async (c) => {
      const before = (
        await c.query(`select * from plan where code = $1`, [dto.code])
      ).rows[0];

      const after = (
        await c.query(
          `insert into plan (code, name_th, max_students, max_staff,
                             price_per_year, price_per_student, enforcement,
                             grace_percent, active, sort_order)
           values ($1, $2, $3, $4, coalesce($5, 0), coalesce($6, 0),
                   coalesce($7, 'soft')::plan_enforcement,
                   coalesce($8, 10), coalesce($9, true), coalesce($10, 0))
           on conflict (code) do update
              set name_th           = excluded.name_th,
                  max_students      = excluded.max_students,
                  max_staff         = excluded.max_staff,
                  price_per_year    = excluded.price_per_year,
                  price_per_student = excluded.price_per_student,
                  enforcement       = excluded.enforcement,
                  grace_percent     = excluded.grace_percent,
                  active            = excluded.active,
                  sort_order        = excluded.sort_order
           returning *`,
          [
            dto.code, dto.nameTh, dto.maxStudents ?? null, dto.maxStaff ?? null,
            dto.pricePerYear ?? null, dto.pricePerStudent ?? null,
            dto.enforcement ?? null, dto.gracePercent ?? null,
            dto.active ?? null, dto.sortOrder ?? null,
          ],
        )
      ).rows[0];

      return { before, after };
    });

    await this.log(actorId, before ? 'update_plan' : 'create_plan', null, {
      code: dto.code,
      before: before
        ? {
            pricePerYear: before.price_per_year,
            pricePerStudent: before.price_per_student,
            maxStudents: before.max_students,
            enforcement: before.enforcement,
          }
        : null,
      after: {
        pricePerYear: after.price_per_year,
        pricePerStudent: after.price_per_student,
        maxStudents: after.max_students,
        enforcement: after.enforcement,
      },
    });

    return after;
  }

  // ── สัญญา ──────────────────────────────────────────────────────────

  /**
   * ผูกแพ็กเกจให้วิทยาลัย
   *
   * ปิดสัญญาฉบับเดิมให้อัตโนมัติ เพราะ exclusion constraint ห้ามสัญญา
   * ซ้อนช่วงเวลากัน — ถ้าไม่ปิดให้ ผู้ให้บริการจะเจอ 409 แล้วต้องไปไล่ปิดเอง
   * ซึ่งเป็นขั้นตอนที่ลืมได้ง่ายและทำให้เปลี่ยนแพ็กเกจไม่สำเร็จ
   */
  async assignPlan(
    actorId: string,
    dto: {
      institutionId: string;
      planCode: string;
      startsOn: string;
      endsOn?: string;
      status?: string;
      seatsPurchased?: number;
      note?: string;
    },
  ) {
    const row = await this.db.runAs(platformCtx(actorId), async (c) => {
      const inst = (
        await c.query<{ id: string; name_th: string }>(
          `select id, name_th from institution where id = $1`,
          [dto.institutionId],
        )
      ).rows[0];
      if (!inst) throw new NotFoundException('ไม่พบสถานศึกษาที่ระบุ');

      const plan = (
        await c.query<{ id: string; name_th: string }>(
          `select id, name_th from plan where code = $1 and active`,
          [dto.planCode],
        )
      ).rows[0];
      if (!plan) {
        throw new NotFoundException('ไม่พบแพ็กเกจตามรหัสที่ระบุ หรือแพ็กเกจถูกปิดไปแล้ว');
      }

      await c.query(
        `update institution_subscription
            set ends_on = least(coalesce(ends_on, 'infinity'::date), $2::date - 1)
          where institution_id = $1
            and (ends_on is null or ends_on >= $2::date)`,
        [inst.id, dto.startsOn],
      );

      const sub = (
        await c.query(
          `insert into institution_subscription
             (institution_id, plan_id, starts_on, ends_on, status, seats_purchased, note)
           values ($1, $2, $3, $4, coalesce($5, 'active')::subscription_status,
                   coalesce($6, 0), $7)
           returning id, starts_on, ends_on, status, seats_purchased`,
          [
            inst.id, plan.id, dto.startsOn, dto.endsOn ?? null,
            dto.status ?? null, dto.seatsPurchased ?? null, dto.note ?? null,
          ],
        )
      ).rows[0];

      return { institution: inst.name_th, plan: plan.name_th, subscription: sub };
    });

    await this.log(actorId, 'assign_plan', dto.institutionId, {
      planCode: dto.planCode,
      startsOn: dto.startsOn,
      seatsPurchased: dto.seatsPurchased ?? 0,
    });

    return row;
  }

  // ── ปริมาณใช้งาน ───────────────────────────────────────────────────

  /**
   * สั่งเก็บภาพนิ่งใหม่ทันที
   *
   * เรียกงานตัวเดียวกับที่ตัวตั้งเวลาเรียกทุกคืน ไม่ใช่โค้ดชุดที่สอง —
   * งานนั้นรันในบริบทของแต่ละวิทยาลัยเองซึ่งจำเป็นต่อการนับ ส่วนหน้าจอนี้
   * แค่สั่งให้รัน แล้วไปอ่านผลจาก usage_snapshot ตามเดิม
   */
  async refreshUsage(actorId: string) {
    const run = await this.jobs.run('usage-snapshot');
    await this.log(actorId, 'refresh_usage', null, { ok: run.ok, failed: run.failed });
    return {
      ok: run.ok,
      failed: run.failed,
      durationMs: run.durationMs,
      failures: run.results.filter((r) => !r.ok).map((r) => ({ code: r.code, error: r.error })),
    };
  }

  // ── บัญชีผู้ให้บริการด้วยกันเอง ────────────────────────────────────

  async users(actorId: string) {
    return this.db.runAs(platformCtx(actorId), async (c) =>
      (
        await c.query(
          `select id, username, display_name, email, role, disabled_at,
                  last_login_at, created_at,
                  (totp_confirmed_at is not null) as mfa_ready,
                  (setup_code_hash is not null)   as awaiting_setup
             from platform_user order by username`,
        )
      ).rows,
    );
  }

  /**
   * สร้างบัญชีผู้ให้บริการคนใหม่
   *
   * ไม่ตั้งรหัสผ่านให้ — ออกรหัสตั้งค่าที่ใช้ครั้งเดียวแทน หลักเดียวกับ
   * ทั้งระบบ (0025 · 0037) คนที่สร้างบัญชีให้ต้องไม่รู้รหัสผ่านของเจ้าตัว
   * แม้แต่วินาทีเดียว มิฉะนั้นบันทึกการกระทำจะชี้ผิดคนได้
   */
  async createUser(
    actorId: string,
    dto: { username: string; displayName: string; email?: string; role: PlatformRole },
  ) {
    const result = await this.db.runAs(platformCtx(actorId), async (c) => {
      const row = (
        await c.query<{ id: string }>(
          `insert into platform_user
             (username, display_name, email, role, password_hash, must_change, created_by)
           values ($1, $2, $3, $4::platform_role,
                   'locked$' || encode(gen_random_bytes(32), 'hex'), true, $5)
           returning id`,
          [dto.username, dto.displayName, dto.email ?? null, dto.role, actorId],
        )
      ).rows[0];

      const setup = await this.auth.issueSetupCodeOn(c, row.id);
      return { id: row.id, setup };
    });

    await this.log(actorId, 'create_platform_user', null, {
      username: dto.username,
      role: dto.role,
    });

    return {
      platformUserId: result.id,
      username: dto.username,
      role: dto.role,
      setupCode: result.setup.code,
      setupExpiresAt: result.setup.expiresAt,
      note: 'ส่งรหัสตั้งค่าให้เจ้าตัวตั้งรหัสผ่านเอง — ระบบไม่ได้ตั้งรหัสผ่านให้',
    };
  }

  /** ออกรหัสตั้งค่าใหม่ให้คนที่ลืมรหัสผ่าน */
  async resetUser(actorId: string, userId: string) {
    if (userId === actorId) {
      // ออกรหัสให้ตัวเองเท่ากับตั้งรหัสผ่านใหม่โดยไม่ต้องรู้รหัสเดิม
      // ซึ่งทำให้ session ที่ถูกขโมยไปยึดบัญชีถาวรได้
      throw new BadRequestException(
        'ออกรหัสตั้งค่าให้ตัวเองไม่ได้ — ใช้ POST /platform/me/password เปลี่ยนรหัสผ่านแทน',
      );
    }

    const setup = await this.db.runAs(platformCtx(actorId), async (c) => {
      const exists = (
        await c.query(`select username from platform_user where id = $1`, [userId])
      ).rows[0];
      if (!exists) throw new NotFoundException('ไม่พบบัญชีผู้ให้บริการที่ระบุ');

      const s = await this.auth.issueSetupCodeOn(c, userId);
      // session เดิมต้องถูกตัด มิฉะนั้นการออกรหัสใหม่ให้คนที่บัญชีถูกยึด
      // จะไม่ได้ไล่ผู้บุกรุกออกจากระบบเลย
      await c.query(
        `update platform_session
            set revoked_at = now(), revoke_reason = 'ออกรหัสตั้งค่าใหม่'
          where platform_user_id = $1 and revoked_at is null`,
        [userId],
      );
      return s;
    });

    await this.log(actorId, 'reset_platform_user', null, { userId });
    return { setupCode: setup.code, setupExpiresAt: setup.expiresAt };
  }

  async setUserState(
    actorId: string,
    userId: string,
    input: { disabled?: boolean; role?: PlatformRole },
  ) {
    const row = await this.db.runAs(platformCtx(actorId), async (c) => {
      const updated = (
        await c.query(
          `update platform_user
              set disabled_at = case when $2::boolean is null then disabled_at
                                     when $2 then coalesce(disabled_at, now())
                                     else null end,
                  role = coalesce($3::platform_role, role)
            where id = $1
          returning id, username, role, disabled_at`,
          [userId, input.disabled ?? null, input.role ?? null],
        )
      ).rows[0];
      if (!updated) throw new NotFoundException('ไม่พบบัญชีผู้ให้บริการที่ระบุ');

      if (input.disabled) {
        await c.query(
          `update platform_session
              set revoked_at = now(), revoke_reason = 'บัญชีถูกระงับ'
            where platform_user_id = $1 and revoked_at is null`,
          [userId],
        );
      }
      return updated;
    });

    await this.log(actorId, 'update_platform_user', null, {
      userId,
      disabled: input.disabled,
      role: input.role,
    });
    return row;
  }

  // ── บันทึกการกระทำ ─────────────────────────────────────────────────

  async actionLog(actorId: string, limit = 200) {
    return this.db.runAs(platformCtx(actorId), async (c) =>
      (
        await c.query(
          `select l.username, l.action, l.detail, l.occurred_at,
                  i.code as institution_code, i.name_th as institution_name
             from platform_action_log l
             left join institution i on i.id = l.institution_id
            order by l.occurred_at desc
            limit $1`,
          [Math.min(Math.max(limit, 1), 1000)],
        )
      ).rows,
    );
  }
}

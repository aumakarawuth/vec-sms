import {
  BadRequestException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { createHash, randomBytes } from 'node:crypto';
import { PoolClient } from 'pg';
import { AppRole } from '../../common/context/request-context';
import { DbService } from '../../common/db/db.service';
import {
  checkPasswordStrength,
  hashPassword,
  needsRehash,
  verifyPassword,
} from '../../common/auth/password';
import { generateResetCode, hashResetCode } from '../../common/auth/reset-code';
import { ResetDelivery } from './reset-delivery';
import {
  currentStep,
  decryptSecret,
  encryptSecret,
  newRecoveryCode,
  newSecret,
  normalizeRecoveryCode,
  otpauthUri,
  verifyTotp,
} from './totp';

export interface LoginInput {
  institutionId: string;
  username: string;
  password: string;
  deviceId?: string;
  deviceLabel?: string;
  platform?: string;
  ip?: string;
  userAgent?: string;
}

interface Policy {
  max_failed_attempts: number;
  lockout_minutes: number;
  access_token_minutes: number;
  refresh_token_days: number;
  min_password_length: number;
  bind_student_device: boolean;
  max_devices_student: number;
  reset_code_minutes: number;
  reset_code_attempts: number;
}

const DEFAULT_POLICY: Policy = {
  max_failed_attempts: 5,
  lockout_minutes: 15,
  access_token_minutes: 30,
  refresh_token_days: 30,
  min_password_length: 8,
  bind_student_device: true,
  max_devices_student: 1,
  reset_code_minutes: 30,
  reset_code_attempts: 5,
};

/**
 * ค่าแฮชหลอกสำหรับเทียบเวลาเมื่อไม่พบผู้ใช้
 * ค่าจริงไม่สำคัญ สำคัญที่ทำให้ใช้เวลาใกล้เคียงกับการตรวจของจริง
 */
const DUMMY_HASH =
  'scrypt$16384$8$1$AAAAAAAAAAAAAAAAAAAAAA==$' +
  'ZGVsaWJlcmF0ZWx5LWludmFsaWQtaGFzaC11c2VkLW9ubHktdG8tZXF1YWxpc2UtdGltaW5nLXg=';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly db: DbService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly delivery: ResetDelivery,
  ) {}

  /** บริบทที่ใช้เฉพาะช่วงตรวจรหัสผ่าน อ่านได้เท่าที่ RLS ของบทบาท auth อนุญาต */
  private authCtx(institutionId: string) {
    return {
      institutionId,
      actorId: '00000000-0000-0000-0000-000000000000',
      role: 'auth' as AppRole,
    };
  }

  private hashToken(token: string): Buffer {
    return createHash('sha256').update(token).digest();
  }

  /**
   * ปฏิเสธตั้งแต่ต้นถ้าสถานศึกษาถูกระงับ
   *
   * ─── ทำไมตรวจที่นี่ทั้งที่ฐานข้อมูลก็กันอยู่แล้ว ───
   * trigger บน auth_session (0040) เป็นตัวบังคับจริงและครอบทุกเส้นทาง
   * แต่ข้อความที่ออกมาจากมันคือข้อผิดพลาดของฐานข้อมูลซึ่งกลายเป็น 422
   * ผู้ใช้ที่เจอหน้าจอนั้นจะไม่รู้ว่าต้องทำอะไรต่อ
   *
   * การตรวจตรงนี้ให้ 403 พร้อมเหตุผลที่ผู้ให้บริการเขียนไว้ — ไม่ได้แทน
   * กฎในฐานข้อมูล แต่ทำให้คำตอบอ่านรู้เรื่องในเส้นทางปกติ
   */
  private async assertInstitutionActive(institutionId: string): Promise<void> {
    const row = await this.db.runAs(this.authCtx(institutionId), async (c) =>
      (
        await c.query<{ suspended_at: Date | null; suspended_reason: string | null }>(
          `select suspended_at, suspended_reason from institution where id = $1`,
          [institutionId],
        )
      ).rows[0],
    );

    if (row?.suspended_at) {
      throw new ForbiddenException(
        `สถานศึกษานี้ถูกระงับการใช้งานชั่วคราว ` +
          `(${row.suspended_reason?.trim() || 'ไม่ได้ระบุเหตุผล'}) กรุณาติดต่อผู้ให้บริการ`,
      );
    }
  }

  private hashIp(ip?: string): Buffer | null {
    if (!ip) return null;
    // ไอพีเป็นข้อมูลส่วนบุคคลตาม PDPA เก็บเป็นค่าแฮชพร้อมเกลือประจำระบบ
    // ยังใช้จำกัดจำนวนครั้งและตรวจสอบย้อนหลังได้ แต่ย้อนกลับเป็นไอพีจริงไม่ได้
    const pepper = this.config.get<string>('IP_HASH_SECRET') ?? 'vec-sms';
    return createHash('sha256').update(`${pepper}:${ip}`).digest();
  }

  /**
   * เข้าสู่ระบบ
   *
   * ─── เหตุผลที่แยกเป็นหลาย transaction ───
   * ผลข้างเคียงด้านความปลอดภัยต้องคงอยู่แม้คำขอจะล้มเหลว — ตัวนับครั้งที่ใส่ผิด
   * บันทึกความพยายามเข้าระบบ และการลงทะเบียนอุปกรณ์ที่รออนุมัติ
   *
   * ถ้าเขียนสิ่งเหล่านี้ไว้ใน transaction เดียวกับที่โยนข้อผิดพลาด ฐานข้อมูลจะ
   * rollback ทั้งหมด ผลคือใส่รหัสผิดกี่ครั้งบัญชีก็ไม่มีวันถูกล็อก บันทึกจะมี
   * เฉพาะครั้งที่สำเร็จ และเจ้าหน้าที่จะไม่เห็นอุปกรณ์ที่รออนุมัติเลย
   * ทั้งสามอย่างทำให้มาตรการที่ตั้งใจไว้ไม่ทำงานโดยไม่มีใครรู้
   */
  async login(input: LoginInput) {
    const ctx = this.authCtx(input.institutionId);
    const ipHash = this.hashIp(input.ip);

    // ── ขั้นที่ 0 จำกัดจำนวนครั้งรายไอพี ─────────────────────────
    //
    // การล็อกบัญชีด้านล่างกันการเดารหัสผ่านของบัญชีหนึ่งได้ดี แต่กัน
    // credential stuffing ไม่ได้เลย — ลองรหัสยอดนิยมหนึ่งตัวกับทุกบัญชี
    // จะไม่ทำให้บัญชีไหนถูกล็อกสักบัญชี เพราะแต่ละบัญชีถูกลองแค่ครั้งเดียว
    //
    // ตัวนับอยู่ในฐานข้อมูล ไม่ใช่หน่วยความจำของโปรเซส เพราะโควตาที่
    // ถูกแบ่งตามจำนวน instance แปลว่าผู้โจมตีได้ลองมากกว่าที่ตั้งใจ
    const rate = await this.db.runAs(ctx, async (c) =>
      (
        await c.query<{
          recent_failures: number;
          max_attempts: number;
          remaining: number;
          blocked: boolean;
          retry_after_secs: number;
        }>(`select * from login_rate_status($1, $2)`, [input.institutionId, ipHash])
      ).rows[0],
    );

    if (rate?.blocked) {
      // ไม่บันทึกความพยายามครั้งนี้ลง login_attempt โดยเจตนา
      // มิฉะนั้นผู้โจมตีที่ยิงต่อเนื่องจะต่ออายุการบล็อกตัวเองไปเรื่อย ๆ
      // และตารางจะโตจากทราฟฟิกของการโจมตีเอง
      throw new HttpException(
        {
          statusCode: HttpStatus.TOO_MANY_REQUESTS,
          message:
            `พยายามเข้าสู่ระบบผิดพลาดถี่เกินไปจากที่อยู่นี้ ` +
            `ลองใหม่อีกครั้งใน ${Math.ceil(rate.retry_after_secs / 60)} นาที`,
          error: 'Too Many Requests',
          retryAfter: rate.retry_after_secs,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    await this.assertInstitutionActive(input.institutionId);

    // ── ขั้นที่ 1 อ่านอย่างเดียว ──────────────────────────────────
    const { policy, cred } = await this.db.runAs(ctx, async (c) => ({
      policy: await this.policyOf(c, input.institutionId),
      cred: (
        await c.query<{
          id: string;
          person_id: string;
          password_hash: string;
          must_change: boolean;
          failed_attempts: number;
          locked_until: Date | null;
          disabled_at: Date | null;
        }>(
          `select id, person_id, password_hash, must_change, failed_attempts,
                  locked_until, disabled_at
             from user_credential
            where institution_id = $1 and username = $2`,
          [input.institutionId, input.username],
        )
      ).rows[0],
    }));

    /** บันทึกความล้มเหลวให้ติดถาวรก่อน แล้วค่อยโยนข้อผิดพลาด */
    const reject = async (
      reason: string,
      personId: string | null,
      error: Error,
    ): Promise<never> => {
      await this.db.runAs(ctx, (c) =>
        this.record(c, input, false, reason, ipHash, personId),
      );
      throw error;
    };

    // ── ขั้นที่ 2 ตรวจสอบ ─────────────────────────────────────────
    if (!cred) {
      // ตรวจกับค่าหลอกเพื่อให้ใช้เวลาใกล้เคียงกัน มิฉะนั้นผู้โจมตีจะรู้จาก
      // ความเร็วว่ารหัสประจำตัวไหนมีอยู่จริง
      await verifyPassword(input.password, DUMMY_HASH);
      return reject(
        'ไม่พบรหัสประจำตัว',
        null,
        new UnauthorizedException('รหัสประจำตัวหรือรหัสผ่านไม่ถูกต้อง'),
      );
    }

    if (cred.disabled_at) {
      return reject(
        'บัญชีถูกระงับ',
        cred.person_id,
        new ForbiddenException('บัญชีนี้ถูกระงับ ติดต่องานทะเบียน'),
      );
    }

    if (cred.locked_until && cred.locked_until > new Date()) {
      const mins = Math.ceil((cred.locked_until.getTime() - Date.now()) / 60000);
      return reject(
        'อยู่ระหว่างล็อก',
        cred.person_id,
        new ForbiddenException(`ใส่รหัสผ่านผิดหลายครั้ง กรุณารออีก ${mins} นาที`),
      );
    }

    const ok = await verifyPassword(input.password, cred.password_hash);

    if (!ok) {
      const attempts = cred.failed_attempts + 1;
      const shouldLock = attempts >= policy.max_failed_attempts;

      // ต้อง commit ก่อนโยน มิฉะนั้นตัวนับจะถูก rollback และไม่มีวันล็อกได้
      await this.db.runAs(ctx, async (c) => {
        await c.query(
          `update user_credential
              set failed_attempts = $2,
                  locked_until = case when $3
                                      then now() + make_interval(mins => $4)
                                      else locked_until end
            where id = $1`,
          [cred.id, shouldLock ? 0 : attempts, shouldLock, policy.lockout_minutes],
        );
        await this.record(c, input, false, 'รหัสผ่านไม่ถูกต้อง', ipHash, cred.person_id);
      });

      if (shouldLock) {
        throw new ForbiddenException(
          `ใส่รหัสผ่านผิด ${policy.max_failed_attempts} ครั้ง ` +
            `บัญชีถูกล็อก ${policy.lockout_minutes} นาที`,
        );
      }
      throw new UnauthorizedException(
        `รหัสประจำตัวหรือรหัสผ่านไม่ถูกต้อง ` +
          `(เหลืออีก ${policy.max_failed_attempts - attempts} ครั้ง)`,
      );
    }

    // ── ขั้นที่ 3 ตรวจอุปกรณ์ ─────────────────────────────────────
    const role = await this.db.runAs(ctx, (c) =>
      this.roleOf(c, cred.person_id, input.institutionId),
    );

    // บัญชีที่ไม่ผูกกับบทบาทใดเลยเข้าระบบไม่ได้ ไม่ใช่ให้บทบาทเริ่มต้นไป
    // การให้ teacher โดยอัตโนมัติแปลว่าบัญชีที่ตั้งค่าไม่ครบเห็นข้อมูลนักศึกษาได้
    if (!role) {
      return reject(
        'บัญชีนี้ยังไม่ได้รับมอบหมายบทบาท',
        cred.person_id,
        new ForbiddenException(
          'บัญชีนี้ยังไม่ได้รับมอบหมายบทบาทในระบบ ติดต่องานทะเบียนหรือผู้ดูแลระบบ',
        ),
      );
    }
    const device = await this.db.runAs(ctx, (c) =>
      this.registerDevice(c, input, cred.person_id, role, policy),
    );

    if (device.blocked) {
      return reject(device.reason, cred.person_id, new ForbiddenException(device.reason));
    }

    // ── ขั้นที่ 4 สำเร็จ ──────────────────────────────────────────
    return this.db.runAs(ctx, async (c) => {
      // อัปเกรดความแรงของแฮชแบบเงียบ ๆ ตอนล็อกอินสำเร็จ
      if (needsRehash(cred.password_hash)) {
        await c.query(`update user_credential set password_hash = $2 where id = $1`, [
          cred.id,
          await hashPassword(input.password),
        ]);
      }

      await c.query(
        `update user_credential
            set failed_attempts = 0, locked_until = null, last_login_at = now()
          where id = $1`,
        [cred.id],
      );
      await this.record(c, input, true, null, ipHash, cred.person_id);

      /*
       * ─── ชั้นที่สอง ───
       * บทบาทที่เห็นข้อมูลทั้งวิทยาลัยต้องยืนยันอีกชั้นก่อนได้ token จริง
       *
       * คนที่ยังไม่ได้ตั้ง MFA ก็ไม่ได้ token จริงเช่นกัน แต่ได้ token
       * ชั่วคราวไปตั้งค่า — ถ้าปล่อยให้เข้าได้เลยเพราะ "ยังไม่ได้ตั้ง"
       * นโยบายจะไม่มีผลกับใครเลยจนกว่าทุกคนจะตั้งเอง ซึ่งไม่เกิดขึ้น
       */
      const mfa = (
        await c.query<{ required: boolean; enrolled: boolean }>(
          `select mfa_required_for($1, $2) as required,
                  exists (select 1 from mfa_credential mc
                           where mc.person_id = $3
                             and mc.confirmed_at is not null
                             and mc.disabled_at is null) as enrolled`,
          [input.institutionId, role, cred.person_id],
        )
      ).rows[0];

      if (mfa?.required) {
        return {
          mfaRequired: true,
          enrollmentRequired: !mfa.enrolled,
          challengeToken: await this.issueMfaChallenge(
            input.institutionId, cred.person_id, role,
          ),
          mustChangePassword: cred.must_change,
          role,
        };
      }

      const tokens = await this.issueTokens(c, {
        institutionId: input.institutionId,
        personId: cred.person_id,
        role,
        deviceId: input.deviceId,
        userAgent: input.userAgent,
        policy,
      });

      return { ...tokens, mustChangePassword: cred.must_change, role };
    });
  }

  /**
   * token ชั่วคราวระหว่างรอยืนยันสองชั้น
   *
   * อายุสั้นมากโดยตั้งใจ — ถ้ายาว มันจะกลายเป็นของที่มีค่าพอ ๆ กับ
   * access token สำหรับผู้ที่ขโมยได้ ทั้งที่ยังไม่ผ่านชั้นที่สอง
   * และ AuthGuard ปฏิเสธ token ที่มี stage=mfa กับทุก endpoint อื่นอยู่แล้ว
   */
  private issueMfaChallenge(institutionId: string, personId: string, role: string) {
    return this.jwt.signAsync(
      { sub: personId, inst: institutionId, role, stage: 'mfa' },
      { expiresIn: '5m' },
    );
  }

  /** อ่าน challenge token — ใช้เฉพาะเส้นทาง MFA ที่ยังไม่มี token จริง */
  async readMfaChallenge(token: string) {
    let payload: { sub: string; inst: string; role: string; stage?: string };
    try {
      payload = await this.jwt.verifyAsync(token);
    } catch {
      throw new UnauthorizedException('token ยืนยันตัวตนไม่ถูกต้องหรือหมดอายุ');
    }
    if (payload.stage !== 'mfa') {
      throw new UnauthorizedException('ต้องใช้ token ที่ได้จากขั้นตอนเข้าสู่ระบบ');
    }
    return payload;
  }

  async refresh(institutionId: string, refreshToken: string) {
    const ctx = this.authCtx(institutionId);
    const hash = this.hashToken(refreshToken);

    // การหมุน token คือการต่ออายุการเข้าใช้งาน ถ้าไม่ตรวจตรงนี้ด้วย
    // คนที่ล็อกอินค้างไว้ก่อนถูกระงับจะต่ออายุตัวเองไปได้เรื่อย ๆ
    await this.assertInstitutionActive(institutionId);

    const { policy, row } = await this.db.runAs(ctx, async (c) => ({
      policy: await this.policyOf(c, institutionId),
      row: (
        await c.query<{
          id: string;
          person_id: string;
          app_role: string;
          device_id: string | null;
          expires_at: Date;
          revoked_at: Date | null;
        }>(
          `select id, person_id, app_role, device_id, expires_at, revoked_at
             from auth_session
            where institution_id = $1 and token_hash = $2`,
          [institutionId, hash],
        )
      ).rows[0],
    }));

    if (!row) throw new UnauthorizedException('token ไม่ถูกต้อง');

    if (row.revoked_at) {
      // token ที่เพิกถอนแล้วถูกนำมาใช้ซ้ำ แปลว่าอาจถูกขโมยไป
      // เพิกถอนทุก session ของคนนี้ทันที และต้อง commit ก่อนโยนข้อผิดพลาด
      // มิฉะนั้นการเพิกถอนจะถูก rollback และ token ที่ถูกขโมยยังใช้ได้ต่อ
      await this.db.runAs(ctx, (c) =>
        c.query(
          `update auth_session
              set revoked_at = now(),
                  revoke_reason = 'ตรวจพบการใช้ token ที่เพิกถอนแล้วซ้ำ'
            where person_id = $1 and revoked_at is null`,
          [row.person_id],
        ),
      );
      this.logger.warn(`ใช้ refresh token ที่เพิกถอนแล้วซ้ำ person=${row.person_id}`);
      throw new UnauthorizedException('กรุณาเข้าสู่ระบบใหม่');
    }

    if (row.expires_at <= new Date()) {
      throw new UnauthorizedException('หมดอายุแล้ว กรุณาเข้าสู่ระบบใหม่');
    }

    return this.db.runAs(ctx, async (c) => {
      // หมุน refresh token ทุกครั้ง ตัวเดิมใช้ไม่ได้อีก
      await c.query(
        `update auth_session set revoked_at = now(), revoke_reason = 'หมุน token'
          where id = $1`,
        [row.id],
      );

      return this.issueTokens(c, {
        institutionId,
        personId: row.person_id,
        role: row.app_role as AppRole,
        deviceId: row.device_id ?? undefined,
        policy,
      });
    });
  }

  async logout(institutionId: string, refreshToken: string) {
    return this.db.runAs(this.authCtx(institutionId), async (c) => {
      const r = await c.query(
        `update auth_session
            set revoked_at = now(), revoke_reason = 'ผู้ใช้ออกจากระบบ'
          where institution_id = $1 and token_hash = $2 and revoked_at is null`,
        [institutionId, this.hashToken(refreshToken)],
      );
      return { revoked: r.rowCount ?? 0 };
    });
  }

  /** เปลี่ยนรหัสผ่านของตัวเอง ต้องยืนยันรหัสเดิม */
  async changePassword(current: string, next: string) {
    return this.db.tx(async (c) => {
      const cred = (
        await c.query<{
          id: string;
          username: string;
          password_hash: string;
          institution_id: string;
        }>(
          `select id, username, password_hash, institution_id
             from user_credential where person_id = current_actor_id()`,
        )
      ).rows[0];

      if (!cred) throw new BadRequestException('ไม่พบบัญชีของผู้ใช้นี้');
      if (!(await verifyPassword(current, cred.password_hash))) {
        throw new UnauthorizedException('รหัสผ่านเดิมไม่ถูกต้อง');
      }

      const policy = await this.policyOf(c, cred.institution_id);
      const problem = checkPasswordStrength(next, {
        minLength: policy.min_password_length,
        username: cred.username,
      });
      if (problem) throw new BadRequestException(problem);

      if (await verifyPassword(next, cred.password_hash)) {
        throw new BadRequestException('รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสเดิม');
      }

      await c.query(
        `update user_credential
            set password_hash = $2, must_change = false, password_changed_at = now()
          where id = $1`,
        [cred.id, await hashPassword(next)],
      );

      // เปลี่ยนรหัสผ่านแล้วต้องเตะทุกอุปกรณ์ออก
      // เพราะคนมักเปลี่ยนตอนสงสัยว่าบัญชีถูกขโมย
      await c.query(
        `update auth_session set revoked_at = now(), revoke_reason = 'เปลี่ยนรหัสผ่าน'
          where person_id = current_actor_id() and revoked_at is null`,
      );

      return { changed: true };
    });
  }

  /** งานทะเบียนตั้งรหัสผ่านชุดแรกให้นักศึกษาหรือบุคลากร */
  async issueCredential(personId: string, username: string, tempPassword: string) {
    return this.db.tx(async (c) => {
      const hash = await hashPassword(tempPassword);
      const r = await c.query<{ id: string }>(
        `insert into user_credential
           (institution_id, person_id, username, password_hash, must_change)
         select p.institution_id, p.id, $2, $3, true
           from person p where p.id = $1
         on conflict (institution_id, username) do update
           set password_hash = excluded.password_hash,
               must_change = true,
               failed_attempts = 0,
               locked_until = null,
               disabled_at = null,
               password_changed_at = now()
         returning id`,
        [personId, username, hash],
      );
      if (r.rowCount === 0) throw new BadRequestException('ไม่พบบุคคลที่ระบุ');
      return { id: r.rows[0].id, username };
    });
  }

  // ── รีเซ็ตรหัสผ่าน ─────────────────────────────────────────────────

  /**
   * ผู้ใช้ขอรหัสรีเซ็ตด้วยตัวเอง
   *
   * ─── ทำไมตอบข้อความเดียวกันทุกกรณี ───
   * ถ้าตอบต่างกันระหว่าง "ส่งแล้ว" กับ "ไม่พบบัญชี" ใครก็ตามที่ยิงรายการ
   * รหัสประจำตัวเข้ามาจะได้รายชื่อบัญชีที่มีอยู่จริงทั้งวิทยาลัยกลับไป
   * ซึ่งเป็นวัตถุดิบของการโจมตีขั้นถัดไปทุกแบบ รหัสประจำตัวนักศึกษาเดาได้
   * จากรูปแบบ 67201010xxx อยู่แล้ว จึงต้องปิดช่องนี้ให้สนิท
   *
   * เหตุผลจริงบันทึกไว้ที่ log ฝั่งเซิร์ฟเวอร์ และที่ตาราง password_reset
   * ซึ่งเจ้าหน้าที่ที่มีสิทธิ์เปิดดูได้
   */
  async requestPasswordReset(input: {
    institutionId: string;
    username: string;
    ip?: string;
    userAgent?: string;
  }) {
    // ไม่มีช่องทางส่งแล้วต้องบอกตรง ๆ ไม่ใช่ตอบว่าส่งแล้วทั้งที่ไม่มีรหัส
    // ไปถึงใคร — ผู้ใช้จะนั่งรอ SMS ที่ไม่มีวันมาแล้วเลิกใช้ระบบไปเฉย ๆ
    if (!this.delivery.available) {
      throw new ServiceUnavailableException(
        'วิทยาลัยนี้ยังไม่ได้เปิดการรีเซ็ตรหัสผ่านด้วยตนเอง ' +
          'กรุณาติดต่องานทะเบียนเพื่อขอรหัสรีเซ็ต',
      );
    }

    const ctx = this.authCtx(input.institutionId);
    const code = generateResetCode();
    const codeHash = hashResetCode(code, this.resetSecret);

    const { policy, row } = await this.db.runAs(ctx, async (c) => ({
      policy: await this.policyOf(c, input.institutionId),
      row: (
        await c.query<{
          issued: boolean;
          reason: string | null;
          person_id: string | null;
          channel: 'email' | 'sms' | 'staff_counter' | null;
          destination_hint: string | null;
          expires_at: Date | null;
        }>(
          `select * from request_password_reset($1, $2, null, $3, $4, null)`,
          [input.institutionId, input.username, codeHash, this.hashIp(input.ip)],
        )
      ).rows[0],
    }));

    if (row?.issued && row.channel !== 'staff_counter') {
      await this.delivery.send({
        channel: row.channel as 'email' | 'sms',
        destinationHint: row.destination_hint ?? '',
        code,
        expiresAt: row.expires_at as Date,
        institutionId: input.institutionId,
        personId: row.person_id as string,
      });
    } else {
      // ไม่ใส่รหัสประจำตัวลง log เพราะ log ถูกส่งต่อไปยังระบบรวบรวมภายนอก
      // ได้ง่ายกว่าฐานข้อมูลมาก การมีรายชื่อบัญชีอยู่ในนั้นเป็นข้อมูลส่วนบุคคล
      this.logger.log(`ปฏิเสธคำขอรีเซ็ตรหัสผ่าน — ${row?.reason ?? 'ไม่ทราบสาเหตุ'}`);
    }

    return {
      requested: true,
      expiresInMinutes: policy.reset_code_minutes,
      message:
        `ถ้ามีบัญชีนี้อยู่และมีอีเมลหรือเบอร์โทรบันทึกไว้ ระบบได้ส่งรหัสรีเซ็ตไปให้แล้ว ` +
        `รหัสมีอายุ ${policy.reset_code_minutes} นาที ` +
        `ถ้าไม่ได้รับภายใน 10 นาที กรุณาติดต่องานทะเบียน`,
    };
  }

  /**
   * ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่
   *
   * ─── ทำไมตรวจความแข็งแรงก่อนเรียกฐานข้อมูล ───
   * ถ้าตรวจทีหลัง รหัสรีเซ็ตจะถูกใช้ไปแล้วตอนที่พบว่ารหัสผ่านใหม่อ่อนเกินไป
   * ผู้ใช้จะต้องขอรหัสใหม่ทั้งที่กรอกรหัสรีเซ็ตถูก ซึ่งกินโควตารายวันไปฟรี ๆ
   * และเป็นเหตุผลที่คนเลิกใช้ระบบกลางคันมากที่สุด
   */
  async resetPassword(input: {
    institutionId: string;
    username: string;
    code: string;
    newPassword: string;
  }) {
    const ctx = this.authCtx(input.institutionId);
    const policy = await this.db.runAs(ctx, (c) =>
      this.policyOf(c, input.institutionId),
    );

    const problem = checkPasswordStrength(input.newPassword, {
      minLength: policy.min_password_length,
      username: input.username,
    });
    if (problem) throw new BadRequestException(problem);

    const row = await this.db.runAs(
      ctx,
      async (c) =>
        (
          await c.query<{
            ok: boolean;
            reason: string | null;
            person_id: string | null;
            attempts_left: number;
          }>(`select * from consume_password_reset($1, $2, $3, $4)`, [
            input.institutionId,
            input.username,
            hashResetCode(input.code, this.resetSecret),
            await hashPassword(input.newPassword),
          ])
        ).rows[0],
    );

    // ต้องโยนข้อผิดพลาด **นอก** transaction ที่เพิ่งเรียกฟังก์ชันไป
    // เพราะตัวนับการเดาผิดถูกเขียนอยู่ใน transaction นั้น ถ้าโยนจากข้างใน
    // ฐานข้อมูลจะ rollback ตัวนับทิ้ง แล้วรหัสแปดตัวจะเดาได้ไม่จำกัดครั้ง
    // (กับดักเดียวกับการล็อกบัญชีที่อธิบายไว้ใน login())
    if (!row?.ok) {
      throw new UnauthorizedException(
        row?.reason ?? 'รหัสรีเซ็ตไม่ถูกต้องหรือหมดอายุแล้ว',
      );
    }

    return {
      reset: true,
      message: 'ตั้งรหัสผ่านใหม่เรียบร้อย ระบบออกจากระบบทุกอุปกรณ์แล้ว กรุณาเข้าสู่ระบบใหม่',
    };
  }

  /**
   * งานทะเบียนออกรหัสรีเซ็ตให้ที่เคาน์เตอร์หรือทางโทรศัพท์
   *
   * ─── ทำไมไม่ใช้ issueCredential() ที่มีอยู่แล้ว ───
   * issueCredential() ตั้ง **รหัสผ่าน** ให้ ซึ่งแปลว่าเจ้าหน้าที่รู้รหัสผ่าน
   * ของนักศึกษาตั้งแต่วินาทีที่ออกให้จนถึงตอนที่นักศึกษาเข้ามาเปลี่ยน
   * ช่วงนั้นเข้าระบบแทนกันได้จริง และบันทึกการเข้าถึงจะระบุว่าเป็นฝีมือ
   * ของนักศึกษา ไม่ใช่เจ้าหน้าที่ — เท่ากับหลักฐานชี้ผิดคน
   *
   * เมธอดนี้ออก **รหัสรีเซ็ต** แทน ใช้ได้ครั้งเดียว หมดอายุใน 30 นาที
   * และรหัสผ่านจริงเป็นสิ่งที่นักศึกษาพิมพ์เอง เจ้าหน้าที่ไม่มีวันรู้
   * ผลพลอยได้คือบอกทางโทรศัพท์ได้ ไม่ต้องเดินมาที่วิทยาลัย
   */
  async issueResetCode(personId: string) {
    return this.db.tx((c) => this.issueResetCodeOn(c, personId));
  }

  /**
   * เนื้อในของ issueResetCode() ที่ทำงานบน client ที่ผู้เรียกถืออยู่แล้ว
   *
   * แยกออกมาเพื่อให้การเปิดวิทยาลัยใหม่ออกรหัสรีเซ็ตให้ผู้ดูแลคนแรกได้
   * **ในทรานแซกชันเดียวกับที่สร้างวิทยาลัย** ถ้าเรียก issueResetCode()
   * ตรง ๆ มันจะเปิดทรานแซกชันของตัวเอง แล้วความล้มเหลวของขั้นนี้จะทิ้ง
   * วิทยาลัยที่สร้างเสร็จแล้วไว้โดยไม่มีใครเข้าได้
   */
  async issueResetCodeOn(c: PoolClient, personId: string) {
    const code = generateResetCode();

    const cred = (
      await c.query<{ username: string; institution_id: string }>(
        `select username, institution_id from user_credential where person_id = $1`,
        [personId],
      )
    ).rows[0];

    if (!cred) {
      throw new BadRequestException(
        'บุคคลนี้ยังไม่มีบัญชีผู้ใช้ ให้ออกบัญชีด้วย POST /auth/credentials ก่อน',
      );
    }

    const row = (
      await c.query<{
        issued: boolean;
        reason: string | null;
        expires_at: Date | null;
      }>(
        `select * from request_password_reset($1, $2, 'staff_counter', $3, null, current_actor_id())`,
        [cred.institution_id, cred.username, hashResetCode(code, this.resetSecret)],
      )
    ).rows[0];

    // ตรงนี้โยนจากใน transaction ได้ เพราะเมื่อ issued = false ฟังก์ชัน
    // ยังไม่ได้เขียนอะไรลงฐานข้อมูลเลย จึงไม่มีผลข้างเคียงให้เสียจากการ rollback
    if (!row?.issued) {
      throw new BadRequestException(row?.reason ?? 'ออกรหัสรีเซ็ตไม่สำเร็จ');
    }

    return {
      username: cred.username,
      // ค่านี้แสดงครั้งเดียว ระบบเก็บไว้แต่ค่าแฮชจึงเรียกดูซ้ำไม่ได้
      code,
      expiresAt: (row.expires_at as Date).toISOString(),
      note:
        'อ่านรหัสนี้ให้ผู้ขอทราบ แล้วให้เขาตั้งรหัสผ่านใหม่ด้วยตนเอง ' +
        'อย่าตั้งรหัสผ่านแทน เพราะรหัสผ่านที่เจ้าหน้าที่รู้ทำให้บันทึกการเข้าถึงชี้ผิดคน',
    };
  }

  // ── ตัวช่วยภายใน ───────────────────────────────────────────────────

  /**
   * กุญแจสำหรับแฮชรหัสรีเซ็ต
   *
   * ล้มทันทีถ้าไม่ได้ตั้ง แทนที่จะตกไปใช้ค่าเริ่มต้น เพราะค่าเริ่มต้นที่
   * เดาได้ทำให้ค่าแฮชในตารางถูกไล่ย้อนกลับได้ ซึ่งเท่ากับไม่ได้แฮชเลย
   */
  private get resetSecret(): string {
    const secret = this.config.get<string>('JWT_SECRET');
    if (!secret) {
      throw new HttpException(
        'ไม่ได้ตั้ง JWT_SECRET จึงออกรหัสรีเซ็ตอย่างปลอดภัยไม่ได้',
        HttpStatus.INTERNAL_SERVER_ERROR,
      );
    }
    return secret;
  }

  private async policyOf(c: PoolClient, institutionId: string): Promise<Policy> {
    const r = await c.query<Policy>(
      `select max_failed_attempts, lockout_minutes, access_token_minutes,
              refresh_token_days, min_password_length, bind_student_device,
              max_devices_student, reset_code_minutes, reset_code_attempts
         from auth_policy where institution_id = $1`,
      [institutionId],
    );
    return r.rows[0] ?? DEFAULT_POLICY;
  }

  /** เดาบทบาทจากข้อมูลที่มี — บุคลากรเป็นครู ที่เหลือเป็นนักศึกษา */
  /**
   * บทบาทที่ผู้ใช้คนนี้ได้ตอนล็อกอิน
   *
   * ─── เดิมคืนได้แค่ teacher กับ student ───
   * แปลว่าในระบบจริงที่ปิด DEV_AUTH ไม่มีใครเป็น registrar, finance,
   * academic, director หรือ admin ได้เลย นโยบาย RLS ที่เขียนไว้อย่างละเอียด
   * สำหรับบทบาทเหล่านั้นจึงไม่เคยถูกใช้จริง และงานทะเบียนกับงานการเงิน
   * ทำอะไรไม่ได้เลยผ่านทางที่ตั้งใจไว้
   *
   * ตอนนี้อ่านจาก staff_role ซึ่งมีช่วงเวลากำกับ — ตอบได้ว่าวันนั้นใครมีสิทธิ์อะไร
   *
   * ─── ลำดับการตัดสิน ───
   * 1. บุคลากรที่ได้รับมอบหมายบทบาท → บทบาทนั้น
   * 2. บุคลากรที่เป็นครูผู้สอน → teacher
   * 3. นักศึกษา → student
   * 4. ผู้ปกครองที่ยืนยันตัวตนแล้ว → guardian
   *
   * บุคลากรที่ไม่ได้รับมอบหมายบทบาทและไม่ใช่ครูผู้สอน (เช่นนักการภารโรง
   * ที่มีบัญชีไว้ใช้ระบบอื่น) จะไม่ได้บทบาทใด ๆ และเข้าระบบไม่ได้
   * ซึ่งถูกต้องกว่าการให้ teacher ไปโดยอัตโนมัติแล้วเห็นข้อมูลนักศึกษา
   */
  private async roleOf(
    c: PoolClient,
    personId: string,
    institutionId: string,
  ): Promise<AppRole | null> {
    // ตรรกะทั้งหมดอยู่ใน login_role_for() ในฐานข้อมูล
    //
    // ต้องเป็น security definer เพราะตอนล็อกอินบริบทเป็นบทบาท 'auth'
    // ซึ่งนโยบาย subject_scope ของ student บล็อกการอ่าน ถ้าถามจากที่นี่ตรง ๆ
    // จะหาไม่เจอว่าคนนี้เป็นนักศึกษา แล้วทุกคนจะเข้าระบบไม่ได้
    const r = await c.query<{ role: string | null }>(
      `select login_role_for($1, $2) as role`,
      [personId, institutionId],
    );
    return (r.rows[0]?.role as AppRole) ?? null;
  }

  /**
   * ลงทะเบียนอุปกรณ์ และบอกว่าอนุญาตให้เข้าหรือไม่
   *
   * คืนผลแทนการโยนข้อผิดพลาด เพราะแถวของอุปกรณ์ที่รออนุมัติต้องถูกบันทึกไว้
   * ให้เจ้าหน้าที่เห็นและกดอนุมัติได้ ถ้าโยนออกไปตรงนี้ transaction จะ rollback
   * แล้วรายการที่รออนุมัติจะหายไปทุกครั้ง
   */
  private async registerDevice(
    c: PoolClient,
    input: LoginInput,
    personId: string,
    role: AppRole,
    policy: Policy,
  ): Promise<{ blocked: false } | { blocked: true; reason: string }> {
    if (!input.deviceId || role !== 'student' || !policy.bind_student_device) {
      return { blocked: false };
    }

    const existing = (
      await c.query<{ id: string; approved_at: Date | null; revoked_at: Date | null }>(
        `select id, approved_at, revoked_at from device_binding
          where institution_id = $1 and device_id = $2`,
        [input.institutionId, input.deviceId],
      )
    ).rows[0];

    if (existing) {
      if (existing.revoked_at) {
        return { blocked: true, reason: 'อุปกรณ์นี้ถูกยกเลิกการใช้งาน ติดต่องานทะเบียน' };
      }
      if (!existing.approved_at) {
        return {
          blocked: true,
          reason: 'อุปกรณ์นี้รอการอนุมัติจากงานทะเบียน กรุณาติดต่อเจ้าหน้าที่',
        };
      }
      await c.query(`update device_binding set last_seen_at = now() where id = $1`, [
        existing.id,
      ]);
      return { blocked: false };
    }

    const active = (
      await c.query<{ n: string }>(
        `select count(*) as n from device_binding
          where person_id = $1 and revoked_at is null`,
        [personId],
      )
    ).rows[0];

    // เครื่องแรกอนุมัติเอง เครื่องถัดไปต้องให้เจ้าหน้าที่อนุมัติ
    const autoApprove = Number(active.n) < policy.max_devices_student;

    await c.query(
      `insert into device_binding
         (institution_id, person_id, device_id, device_label, platform, approved_at)
       values ($1, $2, $3, $4, $5, case when $6 then now() else null end)`,
      [
        input.institutionId,
        personId,
        input.deviceId,
        input.deviceLabel ?? null,
        input.platform ?? null,
        autoApprove,
      ],
    );

    if (!autoApprove) {
      return {
        blocked: true,
        reason:
          'บัญชีนี้ผูกกับอุปกรณ์อื่นอยู่แล้ว การเปลี่ยนเครื่องต้องให้งานทะเบียนอนุมัติก่อน',
      };
    }
    return { blocked: false };
  }

  private async issueTokens(
    c: PoolClient,
    p: {
      institutionId: string;
      personId: string;
      role: AppRole;
      deviceId?: string;
      userAgent?: string;
      policy: Policy;
    },
  ) {
    const accessToken = await this.jwt.signAsync(
      { sub: p.personId, inst: p.institutionId, role: p.role },
      { expiresIn: `${p.policy.access_token_minutes}m` },
    );

    const refreshToken = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + p.policy.refresh_token_days * 86400_000);

    await c.query(
      `insert into auth_session
         (institution_id, person_id, token_hash, device_id, app_role, expires_at, user_agent)
       values ($1, $2, $3, $4, $5, $6, $7)`,
      [
        p.institutionId,
        p.personId,
        this.hashToken(refreshToken),
        p.deviceId ?? null,
        p.role,
        expiresAt,
        p.userAgent ?? null,
      ],
    );

    return {
      accessToken,
      refreshToken,
      tokenType: 'Bearer',
      expiresInSeconds: p.policy.access_token_minutes * 60,
      refreshExpiresAt: expiresAt.toISOString(),
    };
  }

  private async record(
    c: PoolClient,
    input: LoginInput,
    ok: boolean,
    reason: string | null,
    ipHash: Buffer | null,
    personId: string | null,
  ): Promise<void> {
    await c.query(
      `insert into login_attempt
         (institution_id, username, person_id, succeeded, reason, ip_hash, user_agent)
       values ($1, $2, $3, $4, $5, $6, $7)`,
      [
        input.institutionId,
        input.username,
        personId,
        ok,
        reason,
        ipHash,
        input.userAgent ?? null,
      ],
    );
  }

  // ── การยืนยันตัวตนสองชั้น ─────────────────────────────────────────

  private mfaKey(): string {
    const key = this.config.get<string>('MFA_SECRET_KEY');
    if (!key) {
      throw new ServiceUnavailableException(
        'ยังไม่ได้ตั้ง MFA_SECRET_KEY จึงเปิดใช้การยืนยันสองชั้นไม่ได้',
      );
    }
    return key;
  }

  /**
   * ออกความลับใหม่ — ยังไม่ถือว่าเปิดใช้จนกว่าจะยืนยันด้วยรหัสจริง
   *
   * ถ้าถือว่าเปิดใช้ทันทีที่ออกความลับ คนที่สแกน QR ไม่สำเร็จจะเข้าระบบ
   * ไม่ได้อีกเลย เพราะระบบจะขอรหัสจากแอปที่เขาไม่มี
   */
  async mfaEnroll(institutionId: string, personId: string) {
    const secret = newSecret();
    const enc = encryptSecret(secret, this.mfaKey());

    return this.db.runAs(this.authCtx(institutionId), async (c) => {
      const person = (
        await c.query<{ label: string; inst_name: string }>(
          `select coalesce(uc.username, p.first_name_th) as label,
                  i.name_th as inst_name
             from person p
             join institution i on i.id = p.institution_id
             left join user_credential uc on uc.person_id = p.id
            where p.id = $1`,
          [personId],
        )
      ).rows[0];

      // ออกความลับใหม่ทับของเดิมที่ยังไม่ยืนยัน แต่ห้ามทับของที่ใช้อยู่จริง
      const existing = (
        await c.query<{ confirmed_at: string | null }>(
          `select confirmed_at from mfa_credential
            where person_id = $1 and disabled_at is null`,
          [personId],
        )
      ).rows[0];

      if (existing?.confirmed_at) {
        throw new BadRequestException(
          'ตั้งค่าการยืนยันสองชั้นไว้แล้ว ถ้าต้องการตั้งใหม่ให้ปิดของเดิมก่อน',
        );
      }

      await c.query(
        `insert into mfa_credential (institution_id, person_id, secret_enc)
         values ($1, $2, $3)
         on conflict (person_id) do update
           set secret_enc = excluded.secret_enc,
               failed_attempts = 0, locked_until = null, last_step = null`,
        [institutionId, personId, enc],
      );

      return {
        otpauthUri: otpauthUri(
          person?.inst_name ?? 'VEC SMS',
          person?.label ?? personId,
          secret,
        ),
        note: 'สแกน QR แล้วยืนยันด้วยรหัสหกหลักเพื่อเปิดใช้ — ยังไม่เปิดใช้จนกว่าจะยืนยัน',
      };
    });
  }

  /**
   * ยืนยันการตั้งค่าและออกรหัสกู้คืน
   *
   * รหัสกู้คืนแสดงครั้งเดียวและเก็บเป็นค่าแฮช ถ้าเก็บแบบอ่านออกได้
   * คนที่อ่านฐานข้อมูลได้จะข้ามชั้นที่สองของทุกคนได้ทันที
   */
  async mfaConfirm(
    institutionId: string,
    personId: string,
    code: string,
    /**
     * ระบุเมื่อผู้เรียกมาด้วย token ชั่วคราวจากขั้นล็อกอิน (ยังไม่มี token จริง)
     *
     * ─── ทำไมต้องออก token ให้ตรงนี้เลย ───
     * มาถึงบรรทัดนี้ได้แปลว่าผ่านทั้งรหัสผ่าน (จึงได้ token ชั่วคราวมา)
     * และรหัสจากแอป (เพิ่งตรวจผ่าน) ครบสองชั้นตามที่นโยบายต้องการแล้ว
     *
     * ถ้าไม่ออกให้ ผู้ใช้ต้องไปเรียก /auth/mfa/verify ต่อด้วยรหัสของ**ช่วง
     * ถัดไป** เพราะ mfa_verify_step กันการใช้ช่วงเดิมซ้ำ แปลว่าต้องนั่งรอ
     * ให้แอปเปลี่ยนตัวเลขก่อนถึงจะเข้าได้ ทั้งที่เพิ่งพิสูจน์ตัวตนไปเมื่อครู่
     */
    session?: { role: AppRole; deviceId?: string; userAgent?: string },
  ) {
    const ctx = this.authCtx(institutionId);

    const row = await this.db.runAs(ctx, async (c) =>
      (
        await c.query<{ id: string; secret_enc: Buffer; confirmed_at: string | null }>(
          `select id, secret_enc, confirmed_at from mfa_credential
            where person_id = $1 and disabled_at is null`,
          [personId],
        )
      ).rows[0],
    );

    if (!row) throw new BadRequestException('ยังไม่ได้เริ่มตั้งค่าการยืนยันสองชั้น');
    if (row.confirmed_at) throw new BadRequestException('ยืนยันไปแล้ว');

    const step = verifyTotp(decryptSecret(row.secret_enc, this.mfaKey()), code);
    const res = await this.verifyStepCommitted(institutionId, personId, step);
    if (!res.ok) throw new UnauthorizedException(res.reason);

    const codes = Array.from({ length: 8 }, () => newRecoveryCode());

    const tokens = await this.db.runAs(ctx, async (c) => {
      for (const rc of codes) {
        await c.query(
          `insert into mfa_recovery_code (credential_id, code_hash) values ($1, $2)`,
          [row.id, createHash('sha256').update(normalizeRecoveryCode(rc)).digest()],
        );
      }
      await c.query(`update mfa_credential set confirmed_at = now() where id = $1`, [row.id]);

      return session
        ? this.issueTokens(c, {
            institutionId,
            personId,
            role: session.role,
            deviceId: session.deviceId,
            userAgent: session.userAgent,
            policy: await this.policyOf(c, institutionId),
          })
        : null;
    });

    return {
      confirmed: true,
      recoveryCodes: codes,
      note: 'เก็บรหัสกู้คืนไว้ในที่ปลอดภัย จะไม่แสดงอีก — ใช้ได้ใบละครั้ง',
      ...(tokens ?? {}),
    };
  }

  /**
   * เรียก mfa_verify_step ใน transaction ของตัวเองแล้วคืนผลออกมา
   *
   * **ต้องแยก transaction** เพราะผู้เรียกจะโยนข้อผิดพลาดเมื่อ ok=false
   * ถ้าโยนจากข้างใน transaction เดียวกัน ฐานข้อมูลจะ rollback ตัวนับครั้งที่ผิด
   * ทิ้งทุกครั้ง แล้วรหัสหกหลักจะเดาได้ไม่จำกัดจำนวนครั้ง — เป็นกับดักเดียวกับ
   * ที่ login() และ resetPassword() อธิบายไว้ และมองไม่เห็นจากภายนอกเลย
   * เพราะระบบยังปฏิเสธรหัสผิดถูกต้องทุกครั้ง แค่ไม่เคยล็อก
   */
  private async verifyStepCommitted(
    institutionId: string,
    personId: string,
    step: number | null,
  ) {
    return this.db.runAs(this.authCtx(institutionId), async (c) =>
      (
        await c.query<{ ok: boolean; reason: string | null; retry_after_secs: number }>(
          `select ok, reason, retry_after_secs from mfa_verify_step($1, $2, $3)`,
          [personId, step ?? currentStep(), step !== null],
        )
      ).rows[0],
    );
  }

  /** ยืนยันด้วยรหัสจากแอป แล้วแลกเป็น token จริง */
  async mfaVerify(challengeToken: string, code: string, deviceId?: string, userAgent?: string) {
    const claim = await this.readMfaChallenge(challengeToken);
    const ctx = this.authCtx(claim.inst);

    const row = await this.db.runAs(ctx, async (c) =>
      (
        await c.query<{ secret_enc: Buffer; confirmed_at: string | null }>(
          `select secret_enc, confirmed_at from mfa_credential
            where person_id = $1 and disabled_at is null`,
          [claim.sub],
        )
      ).rows[0],
    );

    if (!row?.confirmed_at) {
      throw new BadRequestException('ยังไม่ได้ตั้งค่าการยืนยันสองชั้น');
    }

    const step = verifyTotp(decryptSecret(row.secret_enc, this.mfaKey()), code);
    const res = await this.verifyStepCommitted(claim.inst, claim.sub, step);

    // โยน **นอก** transaction ที่เพิ่งเขียนตัวนับไป
    if (!res.ok) {
      throw new UnauthorizedException({
        message: res.reason,
        retryAfterSeconds: res.retry_after_secs,
      });
    }

    return this.db.runAs(ctx, async (c) =>
      this.issueTokens(c, {
        institutionId: claim.inst,
        personId: claim.sub,
        role: claim.role as AppRole,
        deviceId,
        userAgent,
        policy: await this.policyOf(c, claim.inst),
      }),
    );
  }

  /** ยืนยันด้วยรหัสกู้คืนเมื่อโทรศัพท์หาย */
  async mfaRecover(challengeToken: string, code: string, ip?: string) {
    const claim = await this.readMfaChallenge(challengeToken);
    const ctx = this.authCtx(claim.inst);

    // ตัวนับการเดาผิดอยู่ใน transaction นี้ จึงต้อง commit ก่อนโยน
    const res = await this.db.runAs(ctx, async (c) =>
      (
        await c.query<{ ok: boolean; reason: string | null; remaining: number }>(
          `select ok, reason, remaining from mfa_consume_recovery($1, $2, $3)`,
          [
            claim.sub,
            createHash('sha256').update(normalizeRecoveryCode(code)).digest(),
            this.hashIp(ip),
          ],
        )
      ).rows[0],
    );

    if (!res.ok) throw new UnauthorizedException(res.reason);

    const tokens = await this.db.runAs(ctx, async (c) =>
      this.issueTokens(c, {
        institutionId: claim.inst,
        personId: claim.sub,
        role: claim.role as AppRole,
        policy: await this.policyOf(c, claim.inst),
      }),
    );

    return {
      ...tokens,
      recoveryCodesRemaining: res.remaining,
      note: res.remaining === 0
        ? 'ใช้รหัสกู้คืนหมดแล้ว ให้ตั้งค่าการยืนยันสองชั้นใหม่ทันที'
        : 'เข้าระบบด้วยรหัสกู้คืน ควรตั้งค่าแอปยืนยันตัวตนใหม่โดยเร็ว',
    };
  }

  /**
   * ปิดการยืนยันสองชั้นของตัวเอง — ต้องใส่รหัสปัจจุบันก่อน
   *
   * ถ้าปิดได้ด้วย access token อย่างเดียว ผู้ที่ขโมย token ไปได้จะปิดชั้นที่สอง
   * แล้วเข้าระบบด้วยรหัสผ่านอย่างเดียวได้ตลอดไป
   */
  async mfaDisable(institutionId: string, personId: string, code: string) {
    const ctx = this.authCtx(institutionId);

    const row = await this.db.runAs(ctx, async (c) =>
      (
        await c.query<{ id: string; secret_enc: Buffer }>(
          `select id, secret_enc from mfa_credential
            where person_id = $1 and disabled_at is null and confirmed_at is not null`,
          [personId],
        )
      ).rows[0],
    );

    if (!row) throw new BadRequestException('ยังไม่ได้เปิดใช้การยืนยันสองชั้น');

    const step = verifyTotp(decryptSecret(row.secret_enc, this.mfaKey()), code);
    const res = await this.verifyStepCommitted(institutionId, personId, step);
    if (!res.ok) throw new UnauthorizedException(res.reason);

    await this.db.runAs(ctx, (c) =>
      c.query(
        `update mfa_credential set disabled_at = now(), disabled_by = $2 where id = $1`,
        [row.id, personId],
      ),
    );
    return { disabled: true };
  }

  async mfaStatus(institutionId: string, personId: string) {
    return this.db.runAs(this.authCtx(institutionId), async (c) => {
      const row = (
        await c.query<{
          enrolled: boolean; confirmed: boolean; recovery_left: number;
        }>(
          `select (mc.id is not null) as enrolled,
                  (mc.confirmed_at is not null) as confirmed,
                  coalesce((select count(*) from mfa_recovery_code rc
                             where rc.credential_id = mc.id and rc.used_at is null), 0)::int
                    as recovery_left
             from mfa_credential mc
            where mc.person_id = $1 and mc.disabled_at is null`,
          [personId],
        )
      ).rows[0];

      return {
        enrolled: row?.enrolled ?? false,
        confirmed: row?.confirmed ?? false,
        recoveryCodesRemaining: row?.recovery_left ?? 0,
      };
    });
  }
}

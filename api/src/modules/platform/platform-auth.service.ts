import {
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
import { PoolClient } from 'pg';
import { createHash, randomBytes } from 'node:crypto';
import {
  checkPasswordStrength,
  hashPassword,
  needsRehash,
  verifyPassword,
} from '../../common/auth/password';
import { DbService } from '../../common/db/db.service';
import {
  currentStep,
  decryptSecret,
  encryptSecret,
  newSecret,
  otpauthUri,
  verifyTotp,
} from '../auth/totp';
import {
  PlatformRole,
  platformAuthCtx,
  platformCtx,
} from './platform.guard';

/**
 * การเข้าสู่ระบบของผู้ให้บริการ
 *
 * ─── ทำไมแยกจาก AuthService ทั้งที่ขั้นตอนคล้ายกันมาก ───
 * AuthService ทุกเมธอดรับ institutionId เป็นตัวแรกและอ่านนโยบายรายวิทยาลัย
 * (auth_policy) ซึ่งฝั่งนี้ไม่มีและไม่ควรมี — นโยบายของผู้ให้บริการต้องไม่
 * ขึ้นกับการตั้งค่าของลูกค้ารายใดรายหนึ่ง มิฉะนั้นวิทยาลัยที่ตั้ง
 * require_mfa_roles เป็นค่าว่างจะปิด MFA ของผู้ให้บริการไปด้วย
 *
 * ─── ทำไม MFA บังคับเสมอ ไม่มีสวิตช์ปิด ───
 * บัญชีเดียวในตารางนี้เปิดวิทยาลัยใหม่ได้ ระงับลูกค้าได้ และเห็นตัวเลข
 * ธุรกิจของทุกวิทยาลัย ต่างจากฝั่งวิทยาลัยตรงที่ไม่มีลูกค้ารายไหน
 * เป็นผู้รับความเสี่ยงแทนได้ — ความเสียหายตกที่ทุกรายพร้อมกัน
 *
 * ผลคือ login ไม่เคยคืน access token ตรง ๆ เลยสักกรณี คืน challenge token
 * เสมอ แล้วต้องผ่านรหัสจากแอปอีกชั้น
 */
@Injectable()
export class PlatformAuthService {
  private readonly logger = new Logger(PlatformAuthService.name);

  constructor(
    private readonly db: DbService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  /** ค่าแฮชหลอกให้เวลาตอบใกล้เคียงกันเมื่อไม่พบบัญชี */
  private static readonly DUMMY_HASH =
    'scrypt$16384$8$1$AAAAAAAAAAAAAAAAAAAAAA==$' +
    'ZGVsaWJlcmF0ZWx5LWludmFsaWQtaGFzaC11c2VkLW9ubHktdG8tZXF1YWxpc2UtdGltaW5nLXg=';

  private hashToken(token: string): Buffer {
    return createHash('sha256').update(token).digest();
  }

  private hashIp(ip?: string): Buffer | null {
    if (!ip) return null;
    const pepper = this.config.get<string>('IP_HASH_SECRET') ?? 'vec-sms';
    return createHash('sha256').update(`${pepper}:${ip}`).digest();
  }

  private mfaKey(): string {
    const key = this.config.get<string>('MFA_SECRET_KEY');
    if (!key) {
      throw new ServiceUnavailableException(
        'ยังไม่ได้ตั้ง MFA_SECRET_KEY จึงเปิดใช้การยืนยันสองชั้นของผู้ให้บริการไม่ได้',
      );
    }
    return key;
  }

  // ── รหัสที่ออกให้ครั้งเดียว ────────────────────────────────────────

  /**
   * รหัสตั้งค่าครั้งแรก
   *
   * รูปแบบเดียวกับรหัสรีเซ็ตของฝั่งวิทยาลัย — อ่านออกเสียงทางโทรศัพท์ได้
   * และตัดอักษรที่สับสนกับตัวเลขออก (0/O · 1/I/L)
   */
  private newSetupCode(): string {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    const bytes = randomBytes(8);
    let out = '';
    for (let i = 0; i < 8; i++) out += alphabet[bytes[i] % alphabet.length];
    return `${out.slice(0, 4)}-${out.slice(4)}`;
  }

  private hashCode(code: string): Buffer {
    return createHash('sha256')
      .update(code.replace(/[^A-Za-z0-9]/g, '').toUpperCase())
      .digest();
  }

  // ── การติดตั้งครั้งแรก ─────────────────────────────────────────────

  /**
   * สร้างบัญชีผู้ให้บริการคนแรก
   *
   * กั้นด้วย PROVISION_KEY ที่ชั้นเส้นทาง และกั้นซ้ำที่ฐานข้อมูลด้วย
   * bootstrap_platform_owner() ซึ่งล้มทันทีถ้ามีบัญชีอยู่แล้วแม้แถวเดียว
   * — กุญแจที่รั่วภายหลังจึงแต่งตั้งใครเป็น owner ไม่ได้
   */
  async bootstrap(input: { username: string; displayName: string; email?: string }) {
    const code = this.newSetupCode();

    const row = await this.db.runAs(platformCtx(), async (c) =>
      (
        await c.query<{ id: string; username: string; setup_expires_at: Date }>(
          `select id, username, setup_expires_at
             from bootstrap_platform_owner($1, $2, $3, $4, $5)`,
          [input.username, input.displayName, input.email ?? null, this.hashCode(code), 60],
        )
      ).rows[0],
    );

    return {
      platformUserId: row.id,
      username: row.username,
      setupCode: code,
      setupExpiresAt: row.setup_expires_at,
      note:
        'ตั้งรหัสผ่านด้วย POST /platform/setup ภายในเวลาที่กำหนด — ' +
        'ระบบไม่ได้ตั้งรหัสผ่านให้ และไม่มีใครนอกจากเจ้าของบัญชีรู้รหัสผ่านได้เลย',
    };
  }

  /** ตั้งรหัสผ่านครั้งแรกด้วยรหัสตั้งค่า */
  async claimSetup(input: { username: string; code: string; newPassword: string }) {
    const weak = checkPasswordStrength(input.newPassword, {
      minLength: 12, // ยาวกว่าฝั่งวิทยาลัยเพราะบัญชีนี้เห็นทุกวิทยาลัย
      username: input.username,
    });
    if (weak) throw new HttpException(weak, HttpStatus.UNPROCESSABLE_ENTITY);

    const result = await this.db.runAs(platformAuthCtx(), async (c) => {
      const r = (
        await c.query<{ ok: boolean; user_id: string | null; reason: string | null }>(
          `select ok, user_id, reason from consume_platform_setup($1, $2)`,
          [input.username, this.hashCode(input.code)],
        )
      ).rows[0];

      if (!r?.ok || !r.user_id) return r;

      await c.query(
        `update platform_user
            set password_hash = $2, must_change = false,
                failed_attempts = 0, locked_until = null
          where id = $1`,
        [r.user_id, await hashPassword(input.newPassword)],
      );
      return r;
    });

    // ต้องโยน **นอก** runAs — ข้างในคือทรานแซกชัน การโยนจากในนั้นจะ rollback
    // ตัวนับที่ consume_platform_setup เพิ่งเพิ่มไป แล้วเดารหัสได้ไม่จำกัด
    // (บทเรียนเดียวกับ verifyStepCommitted ของฝั่งวิทยาลัย)
    if (!result?.ok) {
      throw new UnauthorizedException(result?.reason ?? 'รหัสตั้งค่าไม่ถูกต้อง');
    }

    return {
      ok: true,
      message: 'ตั้งรหัสผ่านแล้ว เข้าสู่ระบบด้วย POST /platform/login แล้วตั้งการยืนยันสองชั้นต่อ',
    };
  }

  // ── เข้าสู่ระบบ ────────────────────────────────────────────────────

  async login(input: {
    username: string;
    password: string;
    ip?: string;
    userAgent?: string;
  }) {
    const ipHash = this.hashIp(input.ip);

    const rate = await this.db.runAs(platformAuthCtx(), async (c) =>
      (
        await c.query<{ blocked: boolean; retry_after_secs: number }>(
          `select blocked, retry_after_secs from platform_login_rate_status($1)`,
          [ipHash],
        )
      ).rows[0],
    );

    if (rate?.blocked) {
      // ไม่บันทึกครั้งนี้ มิฉะนั้นผู้โจมตีที่ยิงต่อเนื่องจะต่ออายุการบล็อก
      // ของตัวเองไปเรื่อย ๆ และตารางจะโตจากทราฟฟิกของการโจมตีเอง
      throw new HttpException(
        {
          statusCode: HttpStatus.TOO_MANY_REQUESTS,
          message:
            'พยายามเข้าสู่ระบบผิดพลาดถี่เกินไปจากที่อยู่นี้ ' +
            `ลองใหม่อีกครั้งใน ${Math.ceil((rate.retry_after_secs ?? 60) / 60)} นาที`,
          error: 'Too Many Requests',
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const user = await this.db.runAs(platformAuthCtx(), async (c) =>
      (
        await c.query<{
          id: string;
          role: PlatformRole;
          password_hash: string;
          must_change: boolean;
          failed_attempts: number;
          locked_until: Date | null;
          disabled_at: Date | null;
          totp_confirmed_at: Date | null;
        }>(
          `select id, role, password_hash, must_change, failed_attempts,
                  locked_until, disabled_at, totp_confirmed_at
             from platform_user where username = $1`,
          [input.username],
        )
      ).rows[0],
    );

    const record = (ok: boolean, reason: string | null, userId: string | null) =>
      this.db.runAs(platformAuthCtx(), (c) =>
        c.query(
          `insert into platform_login_attempt
             (username, platform_user_id, succeeded, reason, ip_hash, user_agent)
           values ($1, $2, $3, $4, $5, $6)`,
          [input.username, userId, ok, reason, ipHash, input.userAgent ?? null],
        ),
      );

    if (!user) {
      await verifyPassword(input.password, PlatformAuthService.DUMMY_HASH);
      await record(false, 'ไม่พบชื่อผู้ใช้', null);
      throw new UnauthorizedException('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
    }

    if (user.disabled_at) {
      await record(false, 'บัญชีถูกระงับ', user.id);
      throw new ForbiddenException('บัญชีนี้ถูกระงับ ติดต่อผู้ดูแลระดับ owner');
    }

    if (user.locked_until && user.locked_until > new Date()) {
      const mins = Math.ceil((user.locked_until.getTime() - Date.now()) / 60000);
      await record(false, 'อยู่ระหว่างล็อก', user.id);
      throw new ForbiddenException(`ใส่รหัสผ่านผิดหลายครั้ง กรุณารออีก ${mins} นาที`);
    }

    const ok = await verifyPassword(input.password, user.password_hash);

    if (!ok) {
      const attempts = user.failed_attempts + 1;
      const shouldLock = attempts >= 5;

      // ต้อง commit ก่อนโยน มิฉะนั้นตัวนับถูก rollback แล้วบัญชีไม่มีวันถูกล็อก
      await this.db.runAs(platformAuthCtx(), async (c) => {
        await c.query(
          `update platform_user
              set failed_attempts = $2,
                  locked_until = case when $3 then now() + interval '15 minutes'
                                      else locked_until end
            where id = $1`,
          [user.id, shouldLock ? 0 : attempts, shouldLock],
        );
      });
      await record(false, 'รหัสผ่านไม่ถูกต้อง', user.id);

      if (shouldLock) {
        throw new ForbiddenException('ใส่รหัสผ่านผิด 5 ครั้ง บัญชีถูกล็อก 15 นาที');
      }
      throw new UnauthorizedException(
        `ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง (เหลืออีก ${5 - attempts} ครั้ง)`,
      );
    }

    await this.db.runAs(platformAuthCtx(), async (c) => {
      if (needsRehash(user.password_hash)) {
        await c.query(`update platform_user set password_hash = $2 where id = $1`, [
          user.id,
          await hashPassword(input.password),
        ]);
      }
      await c.query(
        `update platform_user
            set failed_attempts = 0, locked_until = null, last_login_at = now()
          where id = $1`,
        [user.id],
      );
    });
    await record(true, null, user.id);

    return {
      mfaRequired: true,
      enrollmentRequired: !user.totp_confirmed_at,
      mustChangePassword: user.must_change,
      role: user.role,
      challengeToken: await this.jwt.signAsync(
        { sub: user.id, kind: 'platform', stage: 'mfa' },
        { expiresIn: '5m' },
      ),
    };
  }

  // ── การยืนยันสองชั้น ───────────────────────────────────────────────

  /**
   * ออกความลับใหม่ — ยังไม่ถือว่าเปิดใช้จนกว่าจะยืนยันด้วยรหัสจริง
   *
   * ถ้าถือว่าเปิดใช้ทันทีที่ออกความลับ คนที่สแกน QR ไม่สำเร็จจะเข้าระบบ
   * ไม่ได้อีกเลย เพราะระบบจะขอรหัสจากแอปที่เขาไม่มี
   */
  async mfaEnroll(userId: string) {
    const secret = newSecret();
    const enc = encryptSecret(secret, this.mfaKey());

    const row = await this.db.runAs(platformCtx(userId), async (c) => {
      const existing = (
        await c.query<{ totp_confirmed_at: Date | null; username: string }>(
          `select totp_confirmed_at, username from platform_user where id = $1`,
          [userId],
        )
      ).rows[0];

      if (existing?.totp_confirmed_at) {
        throw new HttpException(
          'ตั้งการยืนยันสองชั้นไว้แล้ว ต้องปิดของเดิมก่อนจึงจะตั้งใหม่ได้',
          HttpStatus.CONFLICT,
        );
      }

      await c.query(
        `update platform_user
            set totp_secret_enc = $2, totp_last_step = null,
                mfa_failed_attempts = 0, mfa_locked_until = null
          where id = $1`,
        [userId, enc],
      );
      return existing;
    });

    return {
      otpauthUri: otpauthUri('VEC SMS (ผู้ให้บริการ)', row?.username ?? 'platform', secret),
      note: 'สแกนด้วยแอป authenticator แล้วยืนยันด้วย POST /platform/mfa/confirm',
    };
  }

  /**
   * ยืนยันรหัสครั้งแรก แล้วออก token จริงให้เลย
   *
   * ─── ทำไมต้องคืน token จริงตรงนี้ ───
   * บทเรียนจาก 0036 ข้อ 6 — ถ้าให้กลับไปล็อกอินใหม่ ผู้ใช้จะต้องพิมพ์
   * รหัสผ่านอีกรอบทั้งที่เพิ่งพิสูจน์ครบสองชั้นไปแล้วในคำขอนี้
   * และถ้าเส้นทางล็อกอินมีปัญหาอะไรก็ตาม เขาจะติดอยู่วงนอกทั้งที่ตั้งค่าเสร็จ
   */
  async mfaConfirm(userId: string, code: string, userAgent?: string) {
    const step = await this.verifyCode(userId, code);
    if (step === null) {
      throw new UnauthorizedException('รหัสยืนยันไม่ถูกต้อง');
    }

    return this.db.runAs(platformCtx(userId), async (c) => {
      await c.query(
        `update platform_user set totp_confirmed_at = coalesce(totp_confirmed_at, now())
          where id = $1`,
        [userId],
      );
      return this.issueTokens(c, userId, userAgent);
    });
  }

  /** แลก challenge token + รหัสจากแอป เป็น token จริง */
  async mfaVerify(challengeToken: string, code: string, userAgent?: string) {
    const userId = await this.readChallenge(challengeToken);
    const step = await this.verifyCode(userId, code);
    if (step === null) {
      throw new UnauthorizedException('รหัสยืนยันไม่ถูกต้อง');
    }

    return this.db.runAs(platformCtx(userId), (c) =>
      this.issueTokens(c, userId, userAgent),
    );
  }

  async readChallenge(token: string): Promise<string> {
    try {
      const claims = await this.jwt.verifyAsync<{
        sub: string;
        kind?: string;
        stage?: string;
      }>(token);
      if (claims.kind !== 'platform' || claims.stage !== 'mfa' || !claims.sub) {
        throw new Error('ไม่ใช่ token ของขั้นยืนยันสองชั้น');
      }
      return claims.sub;
    } catch {
      throw new UnauthorizedException('token ของขั้นยืนยันสองชั้นไม่ถูกต้องหรือหมดอายุ');
    }
  }

  /**
   * ตรวจรหัสหกหลัก
   *
   * ─── ทำไมต้องโยนนอก runAs ───
   * platform_totp_verify() ไม่ raise โดยตั้งใจ เพราะต้องเพิ่มตัวนับให้ติด
   * ถ้าโยนจากข้างในทรานแซกชัน rollback จะล้างตัวนับที่ฟังก์ชันเพิ่งเขียน
   * แล้วเดารหัสหกหลักได้ไม่จำกัดโดยที่ระบบยังปฏิเสธรหัสผิดถูกต้องทุกครั้ง
   * (อาการเดียวกับที่เคยเจอกับ MFA ของฝั่งวิทยาลัย)
   */
  private async verifyCode(userId: string, code: string): Promise<number | null> {
    const result = await this.db.runAs(platformCtx(userId), async (c) => {
      const row = (
        await c.query<{ totp_secret_enc: Buffer | null }>(
          `select totp_secret_enc from platform_user where id = $1`,
          [userId],
        )
      ).rows[0];

      if (!row?.totp_secret_enc) {
        return { step: null as number | null, ok: false, reason: 'ยังไม่ได้ตั้งการยืนยันสองชั้น' };
      }

      const secret = decryptSecret(row.totp_secret_enc, this.mfaKey());
      const step = verifyTotp(secret, code);

      const verdict = (
        await c.query<{ ok: boolean; reason: string | null; retry_after_secs: number }>(
          `select ok, reason, retry_after_secs from platform_totp_verify($1, $2, $3)`,
          [userId, step ?? currentStep(), step !== null],
        )
      ).rows[0];

      return { step, ok: verdict?.ok ?? false, reason: verdict?.reason ?? null };
    });

    if (!result.ok) {
      if (result.reason && result.reason !== 'รหัสยืนยันไม่ถูกต้อง') {
        throw new UnauthorizedException(result.reason);
      }
      return null;
    }
    return result.step;
  }

  private async issueTokens(c: PoolClient, userId: string, userAgent?: string) {
    const user = (
      await c.query<{ role: PlatformRole; username: string; display_name: string }>(
        `select role, username, display_name from platform_user where id = $1`,
        [userId],
      )
    ).rows[0];

    const accessToken = await this.jwt.signAsync(
      { sub: userId, kind: 'platform', prole: user.role },
      { expiresIn: '30m' },
    );

    const refreshToken = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + 7 * 86400_000); // สั้นกว่าฝั่งวิทยาลัยมาก

    await c.query(
      `insert into platform_session (platform_user_id, token_hash, expires_at, user_agent)
       values ($1, $2, $3, $4)`,
      [userId, this.hashToken(refreshToken), expiresAt, userAgent ?? null],
    );

    return {
      accessToken,
      refreshToken,
      tokenType: 'Bearer',
      expiresInSeconds: 30 * 60,
      refreshExpiresAt: expiresAt.toISOString(),
      role: user.role,
      displayName: user.display_name,
      username: user.username,
    };
  }

  // ── หมุน token / ออกจากระบบ ───────────────────────────────────────

  async refresh(refreshToken: string, userAgent?: string) {
    const hash = this.hashToken(refreshToken);

    const row = await this.db.runAs(platformAuthCtx(), async (c) =>
      (
        await c.query<{
          id: string;
          platform_user_id: string;
          expires_at: Date;
          revoked_at: Date | null;
        }>(
          `select id, platform_user_id, expires_at, revoked_at
             from platform_session where token_hash = $1`,
          [hash],
        )
      ).rows[0],
    );

    if (!row) throw new UnauthorizedException('token ไม่ถูกต้อง');

    if (row.revoked_at) {
      // token ที่เพิกถอนแล้วถูกใช้ซ้ำ = อาจถูกขโมย เพิกถอนทุก session ทันที
      // และต้อง commit ก่อนโยน มิฉะนั้นการเพิกถอนจะถูก rollback
      await this.db.runAs(platformAuthCtx(), (c) =>
        c.query(
          `update platform_session
              set revoked_at = now(), revoke_reason = 'ตรวจพบการใช้ token ที่เพิกถอนแล้วซ้ำ'
            where platform_user_id = $1 and revoked_at is null`,
          [row.platform_user_id],
        ),
      );
      this.logger.warn(`ใช้ refresh token ที่เพิกถอนแล้วซ้ำ platform_user=${row.platform_user_id}`);
      throw new UnauthorizedException('กรุณาเข้าสู่ระบบใหม่');
    }

    if (row.expires_at <= new Date()) {
      throw new UnauthorizedException('หมดอายุแล้ว กรุณาเข้าสู่ระบบใหม่');
    }

    return this.db.runAs(platformCtx(row.platform_user_id), async (c) => {
      await c.query(
        `update platform_session set revoked_at = now(), revoke_reason = 'หมุน token'
          where id = $1`,
        [row.id],
      );
      return this.issueTokens(c, row.platform_user_id, userAgent);
    });
  }

  async logout(refreshToken: string) {
    const r = await this.db.runAs(platformAuthCtx(), (c) =>
      c.query(
        `update platform_session
            set revoked_at = now(), revoke_reason = 'ผู้ใช้ออกจากระบบ'
          where token_hash = $1 and revoked_at is null`,
        [this.hashToken(refreshToken)],
      ),
    );
    return { revoked: r.rowCount ?? 0 };
  }

  /** เปลี่ยนรหัสผ่านของตัวเอง */
  async changePassword(userId: string, current: string, next: string) {
    const user = await this.db.runAs(platformCtx(userId), async (c) =>
      (
        await c.query<{ password_hash: string; username: string }>(
          `select password_hash, username from platform_user where id = $1`,
          [userId],
        )
      ).rows[0],
    );

    if (!user || !(await verifyPassword(current, user.password_hash))) {
      throw new UnauthorizedException('รหัสผ่านเดิมไม่ถูกต้อง');
    }

    const weak = checkPasswordStrength(next, { minLength: 12, username: user.username });
    if (weak) throw new HttpException(weak, HttpStatus.UNPROCESSABLE_ENTITY);

    if (await verifyPassword(next, user.password_hash)) {
      throw new HttpException(
        'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }

    await this.db.runAs(platformCtx(userId), async (c) => {
      await c.query(
        `update platform_user set password_hash = $2, must_change = false where id = $1`,
        [userId, await hashPassword(next)],
      );
      // เปลี่ยนรหัสผ่านแล้วต้องตัด session อื่นทิ้ง — ถ้าเปลี่ยนเพราะสงสัยว่า
      // ถูกขโมยบัญชี การปล่อยให้ session เดิมใช้ต่อได้ทำให้การเปลี่ยนไร้ผล
      await c.query(
        `update platform_session
            set revoked_at = now(), revoke_reason = 'เปลี่ยนรหัสผ่าน'
          where platform_user_id = $1 and revoked_at is null`,
        [userId],
      );
    });

    return { ok: true, message: 'เปลี่ยนรหัสผ่านแล้ว session เดิมทั้งหมดถูกตัด' };
  }

  /** ออกรหัสตั้งค่าให้บัญชีที่สร้างใหม่ หรือให้คนที่ลืมรหัสผ่าน */
  async issueSetupCodeOn(c: PoolClient, userId: string) {
    const code = this.newSetupCode();
    const row = (
      await c.query<{ setup_expires_at: Date }>(
        `update platform_user
            set setup_code_hash = $2, setup_expires_at = now() + interval '60 minutes',
                setup_attempts = 0,
                -- ล็อกรหัสผ่านเดิมทิ้งด้วย มิฉะนั้นคนที่รู้รหัสเดิมยังเข้าได้
                password_hash = 'locked$' || encode(gen_random_bytes(32), 'hex'),
                must_change = true
          where id = $1
        returning setup_expires_at`,
        [userId, this.hashCode(code)],
      )
    ).rows[0];

    return { code, expiresAt: row?.setup_expires_at };
  }
}

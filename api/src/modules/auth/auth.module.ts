import {
  Body,
  Controller,
  Get,
  Ip,
  Module,
  NotFoundException,
  Post,
  Headers,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { AllowMfaChallenge, AppRole, Public, Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { Throttle } from '../../common/throttle/throttle.guard';
import { RequestContext } from '../../common/context/request-context';
import { IsUuid } from '../../common/validation/uuid';
import { AuthService } from './auth.service';
import { ResetDelivery } from './reset-delivery';

const ROLES: AppRole[] = [
  'registrar', 'academic', 'finance', 'student_affairs',
  'director', 'admin', 'teacher', 'student', 'guardian',
];

class LoginDto {
  @IsUuid() institutionId: string;
  @IsString() @MinLength(1) @MaxLength(64) username: string;
  @IsString() @MinLength(1) @MaxLength(256) password: string;
  /** ตัวระบุอุปกรณ์ที่แอปสร้างเองและเก็บไว้ในที่เก็บปลอดภัยของเครื่อง */
  @IsOptional() @IsString() @MaxLength(128) deviceId?: string;
  @IsOptional() @IsString() @MaxLength(80) deviceLabel?: string;
  @IsOptional() @IsString() @MaxLength(40) platform?: string;
}

class RefreshDto {
  @IsUuid() institutionId: string;
  @IsString() @MinLength(10) refreshToken: string;
}

class ChangePasswordDto {
  @IsString() currentPassword: string;
  @IsString() @MinLength(8) @MaxLength(256) newPassword: string;
}

class IssueCredentialDto {
  @IsUuid() personId: string;
  @IsString() @MinLength(1) @MaxLength(64) username: string;
  @IsString() @MinLength(8) @MaxLength(256) temporaryPassword: string;
}

class ForgotPasswordDto {
  @IsUuid() institutionId: string;
  @IsString() @MinLength(1) @MaxLength(64) username: string;
}

class ResetPasswordDto {
  @IsUuid() institutionId: string;
  @IsString() @MinLength(1) @MaxLength(64) username: string;
  /** รหัสรีเซ็ตแปดตัวอักษร รับได้ทั้งแบบมีขีดคั่นและไม่มี */
  @IsString() @MinLength(8) @MaxLength(16) code: string;
  @IsString() @MinLength(8) @MaxLength(256) newPassword: string;
}

class IssueResetCodeDto {
  @IsUuid() personId: string;
}

class MfaCodeDto {
  /** รหัสหกหลักจากแอป authenticator */
  @IsString() @MinLength(6) @MaxLength(8) code: string;
  /** ใช้เฉพาะตอนตั้งค่าเสร็จแล้วได้ token จริงกลับไปเลย */
  @IsOptional() @IsString() @MaxLength(128) deviceId?: string;
}

class MfaVerifyDto {
  @IsString() @MinLength(10) challengeToken: string;
  /** รหัสหกหลักจากแอป หรือรหัสกู้คืน (ยาวกว่า และมีขีดคั่นได้) */
  @IsString() @MinLength(6) @MaxLength(24) code: string;
  @IsOptional() @IsString() @MaxLength(128) deviceId?: string;
}

class DevTokenDto {
  @IsUuid() institutionId: string;
  @IsUuid() personId: string;
  @IsIn(ROLES) role: AppRole;
}

@Controller('auth')
class AuthController {
  constructor(
    private readonly svc: AuthService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly db: DbService,
  ) {}

  private get devEnabled(): boolean {
    return this.config.get('DEV_AUTH') === 'true';
  }

  // เข้มกว่าค่าเริ่มต้นมาก เพราะเป็นเส้นทางที่ถูกยิงเดารหัสผ่านจริง
  // ตัวนับรายไอพีข้าม instance อยู่ในฐานข้อมูลอีกชั้น (login_rate_status)
  @Throttle(10, 60)
  @Public()
  @Post('login')
  login(
    @Body() dto: LoginDto,
    @Ip() ip: string,
    @Headers('user-agent') userAgent?: string,
  ) {
    return this.svc.login({ ...dto, ip, userAgent });
  }

  @Throttle(30, 60)
  @Public()
  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.svc.refresh(dto.institutionId, dto.refreshToken);
  }

  @Public()
  @Post('logout')
  logout(@Body() dto: RefreshDto) {
    return this.svc.logout(dto.institutionId, dto.refreshToken);
  }

  @Post('change-password')
  changePassword(@Body() dto: ChangePasswordDto) {
    return this.svc.changePassword(dto.currentPassword, dto.newPassword);
  }

  /** งานทะเบียนออกรหัสผ่านชุดแรกให้ ผู้ใช้ต้องเปลี่ยนตอนเข้าครั้งแรก */
  @Roles('registrar', 'admin')
  @Post('credentials')
  issue(@Body() dto: IssueCredentialDto) {
    return this.svc.issueCredential(dto.personId, dto.username, dto.temporaryPassword);
  }

  /**
   * ขอรหัสรีเซ็ตด้วยตนเอง
   *
   * เข้มกว่า /auth/login เพราะทุกคำขอที่ผ่านอาจกลายเป็น SMS ที่เสียเงินจริง
   * และเป็นข้อความที่ไปโผล่ในมือของคนอื่น ตัวนับรายไอพีที่นับข้าม instance
   * อยู่ในฐานข้อมูลอีกชั้น (ดู request_password_reset ใน migration 0025)
   */
  @Throttle(5, 60)
  @Public()
  @Post('forgot-password')
  forgot(@Body() dto: ForgotPasswordDto, @Ip() ip: string) {
    return this.svc.requestPasswordReset({ ...dto, ip });
  }

  /** ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่ — ไม่ต้องรู้รหัสผ่านเดิม */
  @Throttle(10, 60)
  @Public()
  @Post('reset-password')
  reset(@Body() dto: ResetPasswordDto) {
    return this.svc.resetPassword(dto);
  }

  /**
   * งานทะเบียนออกรหัสรีเซ็ตให้ที่เคาน์เตอร์หรือทางโทรศัพท์
   *
   * ใช้แทน POST /auth/credentials สำหรับคนที่ลืมรหัสผ่าน เพราะเส้นทางนี้
   * เจ้าหน้าที่ไม่ได้รู้รหัสผ่านของผู้ใช้ — ผู้ใช้เป็นคนตั้งเอง
   */
  @Roles('registrar', 'admin')
  @Post('credentials/reset-code')
  issueResetCode(@Body() dto: IssueResetCodeDto) {
    return this.svc.issueResetCode(dto.personId);
  }

  /**
   * ─── การยืนยันตัวตนสองชั้น ───
   *
   * status กับ disable ต้องใช้ token จริงเท่านั้น — การปิดชั้นที่สองด้วย
   * token ที่ได้มาจากรหัสผ่านอย่างเดียวเท่ากับไม่มีชั้นที่สอง
   *
   * ส่วน enroll กับ confirm ติด @AllowMfaChallenge() ไว้ เพราะบทบาทที่ถูก
   * บังคับยืนยันสองชั้นจะมีแต่ token ชั่วคราวจนกว่าจะตั้งค่าเสร็จ ถ้าสองเส้นทาง
   * นี้ไม่รับ คนที่ยังไม่เคยตั้งจะตั้งไม่ได้และเข้าระบบไม่ได้ตลอดไป
   * (ทั้งคู่ยังใช้กับ token จริงได้ตามเดิม สำหรับคนที่เข้าระบบอยู่แล้วและ
   * อยากเปิดใช้เอง)
   *
   * verify กับ recovery รับ challenge token ทาง body จึงเป็น @Public
   */
  @Get('mfa/status')
  mfaStatus() {
    const ctx = RequestContext.get()!;
    return this.svc.mfaStatus(ctx.institutionId, ctx.actorId);
  }

  @AllowMfaChallenge()
  @Post('mfa/enroll')
  mfaEnroll() {
    const ctx = RequestContext.get()!;
    return this.svc.mfaEnroll(ctx.institutionId, ctx.actorId);
  }

  @AllowMfaChallenge()
  @Post('mfa/confirm')
  mfaConfirm(@Body() dto: MfaCodeDto, @Headers('user-agent') userAgent?: string) {
    const ctx = RequestContext.get()!;
    return this.svc.mfaConfirm(
      ctx.institutionId,
      ctx.actorId,
      dto.code,
      // เข้ามาด้วย token ชั่วคราว = ยังไม่มี token จริง ต้องออกให้ตอนตั้งเสร็จ
      ctx.mfaPending ? { role: ctx.role, deviceId: dto.deviceId, userAgent } : undefined,
    );
  }

  @Post('mfa/disable')
  mfaDisable(@Body() dto: MfaCodeDto) {
    const ctx = RequestContext.get()!;
    return this.svc.mfaDisable(ctx.institutionId, ctx.actorId, dto.code);
  }

  /** แลก challenge token + รหัสจากแอป เป็น token จริง */
  @Throttle(10, 60)
  @Public()
  @Post('mfa/verify')
  mfaVerify(@Body() dto: MfaVerifyDto, @Headers('user-agent') userAgent?: string) {
    return this.svc.mfaVerify(dto.challengeToken, dto.code, dto.deviceId, userAgent);
  }

  /** ใช้รหัสกู้คืนเมื่อโทรศัพท์หาย — เข้มกว่าเพราะรหัสกู้คืนไม่หมดอายุเอง */
  @Throttle(5, 60)
  @Public()
  @Post('mfa/recovery')
  mfaRecovery(@Body() dto: MfaVerifyDto, @Ip() ip: string) {
    return this.svc.mfaRecover(dto.challengeToken, dto.code, ip);
  }

  /**
   * ออก token โดยไม่ตรวจรหัสผ่าน — สำหรับการพัฒนาและทดสอบเท่านั้น
   * ปิดโดยค่าเริ่มต้น เปิดด้วย DEV_AUTH=true
   */
  @Throttle(20, 60)
  @Public()
  @Post('dev-token')
  async devToken(@Body() dto: DevTokenDto) {
    if (!this.devEnabled) {
      throw new NotFoundException('ปิดใช้งานอยู่ ตั้ง DEV_AUTH=true เพื่อเปิดในเครื่องพัฒนา');
    }
    const accessToken = await this.jwt.signAsync({
      sub: dto.personId,
      inst: dto.institutionId,
      role: dto.role,
    });
    return { accessToken, tokenType: 'Bearer' };
  }
}

@Module({
  controllers: [AuthController],
  providers: [AuthService, ResetDelivery],
  exports: [AuthService],
})
export class AuthModule {}

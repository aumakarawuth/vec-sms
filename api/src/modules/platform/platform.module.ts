import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  Injectable,
  Ip,
  Module,
  Param,
  Post,
  Query,
  Req,
  ServiceUnavailableException,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { timingSafeEqual } from 'node:crypto';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Public } from '../../common/auth/auth.guard';
import { Throttle } from '../../common/throttle/throttle.guard';
import { IsUuid } from '../../common/validation/uuid';
import { ProvisioningModule, ProvisioningService } from '../provisioning/provisioning.module';
import { JobsModule } from '../jobs/jobs.module';
import { PlatformAuthService } from './platform-auth.service';
import { PlatformService } from './platform.service';
import {
  AllowPlatformMfaChallenge,
  PlatformGuard,
  PlatformPublic,
  PlatformRequest,
  PlatformRole,
  PlatformRoles,
} from './platform.guard';

/**
 * หน้าจอผู้ดูแลข้ามวิทยาลัย
 *
 * ─── ทำไมเส้นทางเหล่านี้ติด @Public() ───
 * @Public() ปิดแค่ AuthGuard ของฝั่งวิทยาลัย ซึ่งบังคับว่า token ต้องมี inst
 * เสมอ — เงื่อนไขที่ผู้ให้บริการไม่มีทางผ่านได้เลย ความปลอดภัยจริงมาจาก
 * PlatformGuard ที่ครอบทั้ง controller ไว้ ไม่ใช่ว่าเส้นทางนี้เปิดสาธารณะ
 *
 * ─── สิ่งที่ไม่มีในหน้าจอนี้โดยตั้งใจ ───
 * · ไม่มีเส้นทางอ่านข้อมูลนักศึกษา บุคลากร เกรด หรือการเงินของวิทยาลัย
 * · ไม่มีเส้นทางออกรหัสรีเซ็ตให้ผู้ใช้ของวิทยาลัย (ยกเว้นผู้ดูแลคนแรก
 *   ตอนเปิดวิทยาลัย ซึ่งเลี่ยงไม่ได้เพราะยังไม่มีใครในวิทยาลัยนั้น)
 * · ไม่มีเส้นทาง "เข้าระบบแทนลูกค้า" ทุกรูปแบบ
 *
 * ทั้งสามข้อไม่ได้กันด้วยการไม่เขียน endpoint อย่างเดียว — บริบทของ
 * ผู้ให้บริการไม่มีวิทยาลัย RLS จึงคืนศูนย์แถวให้เองแม้จะเผลอเขียน query
 * ขึ้นมาก็ตาม (ดู migration 0040 และ TEST 186)
 */

class BootstrapDto {
  @Matches(/^[a-zA-Z0-9._-]{3,64}$/, {
    message: 'ชื่อผู้ใช้ใช้ได้เฉพาะตัวอักษรอังกฤษ ตัวเลข จุด ขีด และขีดล่าง',
  })
  username: string;

  @IsString() @MinLength(1) @MaxLength(200) displayName: string;
  @IsOptional() @IsString() @MaxLength(200) email?: string;
}

class SetupDto {
  @IsString() @MinLength(3) @MaxLength(64) username: string;
  @IsString() @MinLength(8) @MaxLength(16) code: string;
  @IsString() @MinLength(12) @MaxLength(256) newPassword: string;
}

class PlatformLoginDto {
  @IsString() @MinLength(1) @MaxLength(64) username: string;
  @IsString() @MinLength(1) @MaxLength(256) password: string;
}

class RefreshDto {
  @IsString() @MinLength(10) refreshToken: string;
}

class MfaCodeDto {
  @IsString() @MinLength(6) @MaxLength(8) code: string;
}

class MfaVerifyDto {
  @IsString() @MinLength(10) challengeToken: string;
  @IsString() @MinLength(6) @MaxLength(8) code: string;
}

class ChangePasswordDto {
  @IsString() currentPassword: string;
  @IsString() @MinLength(12) @MaxLength(256) newPassword: string;
}

class ProvisionDto {
  @Matches(/^[0-9]{10}$/, { message: 'รหัสสถานศึกษาต้องเป็นตัวเลข 10 หลัก' })
  code: string;

  @IsString() @MinLength(3) @MaxLength(200) nameTh: string;
  @IsOptional() @IsString() @MaxLength(200) nameEn?: string;

  @IsOptional() @IsString() @MaxLength(40) adminPrefixTh?: string;
  @IsString() @MinLength(1) @MaxLength(100) adminFirstNameTh: string;
  @IsString() @MinLength(1) @MaxLength(100) adminLastNameTh: string;
  @IsString() @MinLength(3) @MaxLength(64) adminUsername: string;
  @IsOptional() @IsString() @MaxLength(200) adminEmail?: string;
  @IsOptional() @IsString() @MaxLength(40) adminPhone?: string;

  @IsInt() @Min(2500) @Max(2700) yearBe: number;
  @IsISO8601() yearStartsOn: string;
  @IsISO8601() yearEndsOn: string;
}

class SuspendDto {
  /**
   * เหตุผลบังคับ และต้องยาวพอที่จะสื่อความ — ข้อความนี้คือสิ่งเดียวที่
   * ผู้ใช้ของวิทยาลัยจะเห็นตอนเข้าระบบไม่ได้ ถ้าเขียนว่า "ระงับ" เฉย ๆ
   * ทั้งวิทยาลัยจะโทรมาพร้อมกันโดยไม่มีใครรู้ว่าต้องทำอะไรต่อ
   */
  @IsString() @MinLength(10) @MaxLength(500) reason: string;
}

class ResumeDto {
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}

class PlanDto {
  @IsString() @MinLength(1) @MaxLength(64) code: string;
  @IsString() @MinLength(1) @MaxLength(200) nameTh: string;
  @IsOptional() @IsInt() @Min(1) maxStudents?: number;
  @IsOptional() @IsInt() @Min(1) maxStaff?: number;
  @IsOptional() @IsNumber() @Min(0) pricePerYear?: number;
  @IsOptional() @IsNumber() @Min(0) pricePerStudent?: number;
  @IsOptional() @IsIn(['soft', 'hard']) enforcement?: 'soft' | 'hard';
  @IsOptional() @IsInt() @Min(0) @Max(100) gracePercent?: number;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @IsInt() @Min(0) @Max(999) sortOrder?: number;
}

class AssignPlanDto {
  @IsUuid() institutionId: string;
  @IsString() @MinLength(1) @MaxLength(64) planCode: string;
  @IsISO8601() startsOn: string;
  @IsOptional() @IsISO8601() endsOn?: string;
  @IsOptional() @IsIn(['trial', 'active', 'past_due', 'suspended', 'cancelled'])
  status?: string;
  @IsOptional() @IsInt() @Min(0) seatsPurchased?: number;
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}

class CreateUserDto {
  @Matches(/^[a-zA-Z0-9._-]{3,64}$/, {
    message: 'ชื่อผู้ใช้ใช้ได้เฉพาะตัวอักษรอังกฤษ ตัวเลข จุด ขีด และขีดล่าง',
  })
  username: string;

  @IsString() @MinLength(1) @MaxLength(200) displayName: string;
  @IsOptional() @IsString() @MaxLength(200) email?: string;
  @IsIn(['owner', 'billing', 'support']) role: PlatformRole;
}

class UpdateUserDto {
  @IsOptional() @IsBoolean() disabled?: boolean;
  @IsOptional() @IsIn(['owner', 'billing', 'support']) role?: PlatformRole;
}

/**
 * กุญแจสำหรับการติดตั้งครั้งแรกเท่านั้น
 *
 * ─── ทำไมยังต้องมีอยู่ ทั้งที่มีบัญชีผู้ให้บริการแล้ว ───
 * ไก่กับไข่ — ตอนติดตั้งครั้งแรกยังไม่มีบัญชีไหนให้ล็อกอิน ต้องมีอะไรสักอย่าง
 * ที่พิสูจน์ว่าคนที่เรียกคือคนที่ deploy ระบบนี้ ความลับระดับการติดตั้ง
 * เป็นสิ่งเดียวที่มีอยู่ในตอนนั้น
 *
 * ─── ทำไมมันไม่ใช่ประตูหลังถาวร ───
 * bootstrap_platform_owner() ในฐานข้อมูลล้มทันทีถ้ามีบัญชีอยู่แล้วแม้แถวเดียว
 * กุญแจที่รั่วภายหลังจึงสร้างบัญชีไม่ได้อีกเลย และการสร้างบัญชีเพิ่มต้อง
 * ผ่าน owner ที่ล็อกอินครบสองชั้นแล้วเท่านั้น
 */
@Injectable()
export class PlatformKeyService {
  constructor(private readonly config: ConfigService) {}

  assert(given?: string) {
    const expected = this.config.get<string>('PROVISION_KEY');
    if (!expected) {
      throw new ServiceUnavailableException(
        'ยังไม่ได้ตั้ง PROVISION_KEY — เส้นทางติดตั้งครั้งแรกปิดอยู่',
      );
    }
    // เทียบแบบเวลาคงที่ การเทียบสตริงปกติหยุดที่ตัวแรกที่ต่างกัน
    // ผู้โจมตีที่วัดเวลาตอบกลับได้จึงเดาความลับทีละตัวอักษรได้
    const a = Buffer.from(given ?? '', 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new ForbiddenException('กุญแจสำหรับติดตั้งครั้งแรกไม่ถูกต้อง');
    }
  }
}

@Public()
@UseGuards(PlatformGuard)
@Controller('platform')
class PlatformController {
  constructor(
    private readonly auth: PlatformAuthService,
    private readonly svc: PlatformService,
    private readonly provisioning: ProvisioningService,
    private readonly key: PlatformKeyService,
  ) {}

  private actor(req: PlatformRequest): string {
    return req.platform!.userId;
  }

  // ── ติดตั้งครั้งแรกและการเข้าสู่ระบบ ───────────────────────────────

  @Throttle(3, 60)
  @PlatformPublic()
  @Post('bootstrap')
  bootstrap(@Body() dto: BootstrapDto, @Headers('x-provision-key') key?: string) {
    this.key.assert(key);
    return this.auth.bootstrap(dto);
  }

  @Throttle(5, 60)
  @PlatformPublic()
  @Post('setup')
  setup(@Body() dto: SetupDto) {
    return this.auth.claimSetup(dto);
  }

  /**
   * เข้าสู่ระบบ — ไม่เคยคืน access token ตรง ๆ เลยสักกรณี
   *
   * คืน challenge token เสมอ แล้วต้องผ่านรหัสจากแอปอีกชั้น เพราะบัญชีฝั่งนี้
   * เห็นตัวเลขธุรกิจของทุกวิทยาลัยและเปิด/ระงับวิทยาลัยได้
   */
  @Throttle(10, 60)
  @PlatformPublic()
  @Post('login')
  login(
    @Body() dto: PlatformLoginDto,
    @Ip() ip: string,
    @Headers('user-agent') userAgent?: string,
  ) {
    return this.auth.login({ ...dto, ip, userAgent });
  }

  @Throttle(20, 60)
  @PlatformPublic()
  @Post('refresh')
  refresh(@Body() dto: RefreshDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.refresh(dto.refreshToken, userAgent);
  }

  @PlatformPublic()
  @Post('logout')
  logout(@Body() dto: RefreshDto) {
    return this.auth.logout(dto.refreshToken);
  }

  /**
   * ตั้งค่าการยืนยันสองชั้น
   *
   * รับ token ชั่วคราวได้ เพราะบัญชีที่ยังไม่เคยตั้งจะมีแต่ token ชั่วคราว
   * ถ้าไม่รับ วงจรจะปิดสนิทและไม่มีใครเข้าระบบได้เลย (บทเรียนจาก 0036 ข้อ 6)
   */
  @AllowPlatformMfaChallenge()
  @Post('mfa/enroll')
  mfaEnroll(@Req() req: PlatformRequest) {
    return this.auth.mfaEnroll(this.actor(req));
  }

  @AllowPlatformMfaChallenge()
  @Post('mfa/confirm')
  mfaConfirm(
    @Req() req: PlatformRequest,
    @Body() dto: MfaCodeDto,
    @Headers('user-agent') userAgent?: string,
  ) {
    return this.auth.mfaConfirm(this.actor(req), dto.code, userAgent);
  }

  @Throttle(10, 60)
  @PlatformPublic()
  @Post('mfa/verify')
  mfaVerify(@Body() dto: MfaVerifyDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.mfaVerify(dto.challengeToken, dto.code, userAgent);
  }

  @Post('me/password')
  changePassword(@Req() req: PlatformRequest, @Body() dto: ChangePasswordDto) {
    return this.auth.changePassword(
      this.actor(req),
      dto.currentPassword,
      dto.newPassword,
    );
  }

  // ── ทะเบียนวิทยาลัย ────────────────────────────────────────────────

  @Get('institutions')
  institutions(@Req() req: PlatformRequest) {
    return this.svc.institutions(this.actor(req));
  }

  @Get('institutions/:id')
  institution(@Req() req: PlatformRequest, @Param('id') id: string) {
    return this.svc.institution(this.actor(req), id);
  }

  /**
   * เปิดวิทยาลัยใหม่
   *
   * เข้มกว่าเส้นทางอื่นมาก เพราะทุกคำขอที่ผ่านสร้างวิทยาลัยใหม่หนึ่งแห่ง
   * การยิงรัวจะทำให้ฐานข้อมูลเต็มไปด้วยวิทยาลัยที่ไม่มีอยู่จริง
   *
   * ต่างจาก POST /provisioning/institutions ตรงที่เส้นทางนี้รู้ว่าใครเป็นคนเปิด
   * และบันทึกไว้ ส่วนเส้นทางเดิมกั้นด้วยกุญแจที่ทั้งทีมใช้ร่วมกัน
   */
  @Throttle(3, 60)
  @PlatformRoles('owner', 'billing')
  @Post('institutions')
  async provision(@Req() req: PlatformRequest, @Body() dto: ProvisionDto) {
    const result = await this.provisioning.provision(dto);
    await this.svc.recordProvision(this.actor(req), result.institutionId, dto.code);
    return result;
  }

  @PlatformRoles('owner', 'billing')
  @Post('institutions/:id/suspend')
  suspend(
    @Req() req: PlatformRequest,
    @Param('id') id: string,
    @Body() dto: SuspendDto,
  ) {
    return this.svc.suspend(this.actor(req), id, dto.reason);
  }

  @PlatformRoles('owner', 'billing')
  @Post('institutions/:id/resume')
  resume(
    @Req() req: PlatformRequest,
    @Param('id') id: string,
    @Body() dto: ResumeDto,
  ) {
    return this.svc.resume(this.actor(req), id, dto.note);
  }

  // ── แพ็กเกจและสัญญา ────────────────────────────────────────────────

  @Get('plans')
  plans(@Req() req: PlatformRequest) {
    return this.svc.plans(this.actor(req));
  }

  @PlatformRoles('owner', 'billing')
  @Post('plans')
  upsertPlan(@Req() req: PlatformRequest, @Body() dto: PlanDto) {
    return this.svc.upsertPlan(this.actor(req), dto);
  }

  @PlatformRoles('owner', 'billing')
  @Post('subscriptions')
  assignPlan(@Req() req: PlatformRequest, @Body() dto: AssignPlanDto) {
    return this.svc.assignPlan(this.actor(req), dto);
  }

  @PlatformRoles('owner', 'billing')
  @Post('usage/refresh')
  refreshUsage(@Req() req: PlatformRequest) {
    return this.svc.refreshUsage(this.actor(req));
  }

  // ── บัญชีผู้ให้บริการด้วยกันเอง ────────────────────────────────────

  @PlatformRoles('owner')
  @Get('users')
  users(@Req() req: PlatformRequest) {
    return this.svc.users(this.actor(req));
  }

  @PlatformRoles('owner')
  @Post('users')
  createUser(@Req() req: PlatformRequest, @Body() dto: CreateUserDto) {
    return this.svc.createUser(this.actor(req), dto);
  }

  @PlatformRoles('owner')
  @Post('users/:id/reset')
  resetUser(@Req() req: PlatformRequest, @Param('id') id: string) {
    return this.svc.resetUser(this.actor(req), id);
  }

  @PlatformRoles('owner')
  @Post('users/:id/state')
  setUserState(
    @Req() req: PlatformRequest,
    @Param('id') id: string,
    @Body() dto: UpdateUserDto,
  ) {
    return this.svc.setUserState(this.actor(req), id, dto);
  }

  // ── บันทึกการกระทำ ─────────────────────────────────────────────────

  @Get('audit')
  audit(@Req() req: PlatformRequest, @Query('limit') limit?: string) {
    return this.svc.actionLog(this.actor(req), Number(limit) || 200);
  }
}

@Module({
  imports: [ProvisioningModule, JobsModule],
  controllers: [PlatformController],
  providers: [PlatformAuthService, PlatformService, PlatformKeyService, PlatformGuard],
  exports: [PlatformAuthService, PlatformService],
})
export class PlatformModule {}

import {
  Body,
  Controller,
  ForbiddenException,
  Headers,
  Injectable,
  Module,
  NotFoundException,
  Post,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { timingSafeEqual } from 'node:crypto';
import { IsInt, IsISO8601, IsOptional, IsString, Max, MaxLength, Min, MinLength, Matches } from 'class-validator';
import { AppRole, Public } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { Throttle } from '../../common/throttle/throttle.guard';
import { AuthModule } from '../auth/auth.module';
import { AuthService } from '../auth/auth.service';

/**
 * เปิดวิทยาลัยใหม่
 *
 * ─── ทำไมไม่ใช้บทบาทผู้ใช้ ───
 * ทุกบทบาทในระบบนี้อยู่ **ภายใน** วิทยาลัยหนึ่ง ๆ — admin ของวิทยาลัย ก
 * ไม่มีความหมายในวิทยาลัย ข และการเปิดวิทยาลัยใหม่ไม่ได้อยู่ในวิทยาลัยไหนเลย
 * จึงไม่มีบทบาทไหนที่ถูกต้องจะใช้กับเส้นทางนี้
 *
 * ทางที่ตรงไปตรงมาที่สุดคือความลับระดับการติดตั้ง (PROVISION_KEY) ที่ตั้ง
 * ตอน deploy — ผู้ให้บริการถือ ลูกค้าไม่มี ถ้าไม่ได้ตั้ง เส้นทางนี้ปิดสนิท
 *
 * เมื่อมีหน้าจอผู้ดูแลข้ามวิทยาลัยจริง ๆ ค่อยเปลี่ยนมาใช้บทบาทระดับผู้ให้บริการ
 * แต่การรอสิ่งนั้นแปลว่ายังต้องเปิดวิทยาลัยด้วยการรัน SQL เองต่อไป
 *
 * ─── ทำไมไม่คืนรหัสผ่านของผู้ดูแล ───
 * ฟังก์ชันในฐานข้อมูลสร้างบัญชีที่ **เข้าด้วยรหัสผ่านไม่ได้** แล้วเส้นทางนี้
 * ออกรหัสรีเซ็ตให้ ผู้ดูแลตัวจริงตั้งรหัสผ่านเอง — ผู้ให้บริการจึงไม่มีวัน
 * รู้รหัสผ่านของลูกค้า (หลักเดียวกับ 0025)
 */

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

  @IsOptional() @IsString() @MaxLength(200) requestedBy?: string;
}

class AssignPlanDto {
  @IsString() @MinLength(1) @MaxLength(64) institutionCode: string;
  @IsString() @MinLength(1) @MaxLength(64) planCode: string;
  @IsISO8601() startsOn: string;
  @IsOptional() @IsISO8601() endsOn?: string;
  @IsOptional() @IsString() status?: string;
  @IsOptional() @IsInt() @Min(0) seatsPurchased?: number;
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}

/**
 * บริบทของผู้ให้บริการ — ไม่มีวิทยาลัย
 *
 * ต้องเป็นสตริงว่าง ไม่ใช่ UUID ศูนย์ เพราะ `current_institution_id()` แปลง
 * ค่าว่างเป็น null ซึ่งเป็นเงื่อนไขที่นโยบายใน 0038 ใช้แยก "ผู้ให้บริการเขียน"
 * ออกจาก "วิทยาลัยเขียน" — UUID ศูนย์จะกลายเป็นวิทยาลัยที่ไม่มีอยู่จริง
 * แล้วการเขียนจะถูกปฏิเสธโดยไม่มีใครเข้าใจว่าทำไม
 */
const VENDOR_CTX = {
  institutionId: '',
  actorId: '00000000-0000-0000-0000-000000000000',
  // บทบาท 'platform' คือครึ่งหนึ่งของเงื่อนไข is_platform_context() ใน 0040
  // (อีกครึ่งคือไม่มีวิทยาลัย) — เดิมใช้ 'admin' ซึ่งผ่านได้เพราะนโยบายของ
  // 0038 ดูแค่ว่าไม่มีวิทยาลัย แต่ตั้งแต่ 0040 การเขียนตาราง institution
  // ตรวจบทบาทด้วย เพื่อไม่ให้บริบทที่ไม่มีวิทยาลัยด้วยเหตุอื่นเขียนได้
  role: 'platform' as unknown as AppRole,
};

@Injectable()
export class ProvisioningService {
  constructor(
    private readonly db: DbService,
    private readonly config: ConfigService,
    private readonly auth: AuthService,
  ) {}

  /**
   * เทียบความลับแบบไม่รั่วเวลา
   *
   * การเทียบสตริงปกติหยุดที่ตัวแรกที่ต่างกัน ผู้โจมตีที่วัดเวลาตอบกลับได้
   * จึงเดาความลับทีละตัวอักษรแทนที่จะเดาทั้งเส้น
   */
  assertKey(given?: string) {
    const expected = this.config.get<string>('PROVISION_KEY');
    if (!expected) {
      throw new ServiceUnavailableException(
        'ยังไม่ได้ตั้ง PROVISION_KEY — เส้นทางเปิดวิทยาลัยปิดอยู่',
      );
    }
    const a = Buffer.from(given ?? '', 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      throw new ForbiddenException('กุญแจสำหรับเปิดวิทยาลัยไม่ถูกต้อง');
    }
  }

  /**
   * ─── ทำไมทั้งสองขั้นต้องอยู่ในทรานแซกชันเดียว ───
   * เดิมสร้างวิทยาลัยในทรานแซกชันหนึ่งแล้วออกรหัสรีเซ็ตในอีกทรานแซกชัน
   * ผลคือเมื่อขั้นหลังล้ม วิทยาลัยที่ commit ไปแล้วจะเหลือค้างพร้อมบัญชี
   * ผู้ดูแลที่เข้าด้วยรหัสผ่านไม่ได้ (ตั้งใจให้เป็นแบบนั้น) และไม่มีรหัสรีเซ็ต
   * ส่งกลับมา — ไม่มีใครเข้าวิทยาลัยนั้นได้อีกเลย และเปิดซ้ำก็ไม่ได้เพราะ
   * รหัสสถานศึกษาชนกับของเดิมที่ค้างอยู่
   *
   * รวมเป็นทรานแซกชันเดียวจึงตรงกับที่ provision_institution() ตั้งใจไว้แต่แรก
   * — สำเร็จทั้งหมดหรือไม่เกิดอะไรเลย
   */
  async provision(dto: ProvisionDto) {
    const result = await this.db.runAs(
      // ฟังก์ชันเป็น security definer และสร้างขอบเขตใหม่ จึงยังไม่ต้องมี
      // บริบทวิทยาลัยตอนเริ่ม — วิทยาลัยที่กำลังจะสร้างยังไม่มีอยู่
      //
      // ใช้บริบทผู้ให้บริการ (ไม่มีวิทยาลัย) ไม่ใช่ UUID ศูนย์ เพราะตั้งแต่
      // 0040 ตาราง institution มีนโยบาย insert ที่ตรวจ is_platform_context()
      // UUID ศูนย์จะกลายเป็นวิทยาลัยที่ไม่มีอยู่จริงแล้วถูกปฏิเสธ
      VENDOR_CTX,
      async (c) => {
        const row = (
          await c.query<{
            institution_id: string;
            admin_person_id: string;
            admin_staff_id: string;
            academic_year_id: string;
          }>(
            `select institution_id, admin_person_id, admin_staff_id, academic_year_id
               from provision_institution($1, $2, $3, $4, $5, $6, $7::smallint, $8, $9,
                                          $10, $11, $12, $13)`,
            [
              dto.code, dto.nameTh, dto.adminPrefixTh ?? null,
              dto.adminFirstNameTh, dto.adminLastNameTh, dto.adminUsername,
              dto.yearBe, dto.yearStartsOn, dto.yearEndsOn,
              dto.nameEn ?? null, dto.adminEmail ?? null, dto.adminPhone ?? null,
              dto.requestedBy ?? null,
            ],
          )
        ).rows[0];

        // ขั้นถัดไปอ่านตารางที่มี RLS ของวิทยาลัยที่เพิ่งสร้าง จึงต้องย้าย
        // บริบทมาที่วิทยาลัยนั้นก่อน — แถวที่ยังไม่ commit มองเห็นได้ใน
        // ทรานแซกชันเดียวกันอยู่แล้ว
        await this.db.switchContext(c, {
          institutionId: row.institution_id,
          actorId: row.admin_person_id,
          role: 'registrar',
        });

        // ออกรหัสรีเซ็ตให้ผู้ดูแลตั้งรหัสผ่านเอง — ผู้ให้บริการไม่เห็นรหัสผ่าน
        const reset = await this.auth.issueResetCodeOn(c, row.admin_person_id);

        return { row, reset };
      },
    );

    return {
      institutionId: result.row.institution_id,
      adminPersonId: result.row.admin_person_id,
      academicYearId: result.row.academic_year_id,
      adminUsername: dto.adminUsername,
      resetCode: result.reset.code,
      resetExpiresAt: result.reset.expiresAt,
      note:
        'ส่งรหัสรีเซ็ตให้ผู้ดูแลของวิทยาลัยตั้งรหัสผ่านเอง — ระบบไม่ได้ตั้งรหัสผ่านให้ ' +
        'และผู้ให้บริการไม่มีทางรู้รหัสผ่านของลูกค้า',
    };
  }

  /**
   * @deprecated ย้ายไป POST /platform/subscriptions แล้ว
   *
   * เหลือไว้ให้โค้ดเก่าที่อาจเรียกอยู่ยังคอมไพล์ได้ แต่ไม่มีเส้นทาง HTTP
   * ชี้มาแล้ว — ดูเหตุผลที่ ProvisioningController
   */
  async assignPlan(dto: AssignPlanDto) {
    return this.db.runAs(VENDOR_CTX, async (c) => {
      const inst = (
        await c.query<{ id: string; name_th: string }>(
          `select id, name_th from institution where code = $1`,
          [dto.institutionCode],
        )
      ).rows[0];
      if (!inst) throw new NotFoundException('ไม่พบสถานศึกษาตามรหัสที่ระบุ');

      const plan = (
        await c.query<{ id: string; name_th: string }>(
          `select id, name_th from plan where code = $1 and active`,
          [dto.planCode],
        )
      ).rows[0];
      if (!plan) throw new NotFoundException('ไม่พบแพ็กเกจตามรหัสที่ระบุ หรือแพ็กเกจถูกปิดไปแล้ว');

      await c.query(
        `update institution_subscription
            set ends_on = least(coalesce(ends_on, 'infinity'::date), $2::date - 1)
          where institution_id = $1
            and (ends_on is null or ends_on >= $2::date)`,
        [inst.id, dto.startsOn],
      );

      const row = (
        await c.query<{ id: string }>(
          `insert into institution_subscription
             (institution_id, plan_id, starts_on, ends_on, status, seats_purchased, note)
           values ($1, $2, $3, $4, coalesce($5, 'active')::subscription_status,
                   coalesce($6, 0), $7)
           returning id, starts_on, ends_on, status, seats_purchased`,
          [inst.id, plan.id, dto.startsOn, dto.endsOn ?? null,
           dto.status ?? null, dto.seatsPurchased ?? null, dto.note ?? null],
        )
      ).rows[0];

      return { institution: inst.name_th, plan: plan.name_th, subscription: row };
    });
  }

}

@Controller('provisioning')
class ProvisioningController {
  constructor(private readonly svc: ProvisioningService) {}

  /**
   * เข้มกว่าเส้นทางอื่นมาก เพราะทุกคำขอที่ผ่านสร้างวิทยาลัยใหม่หนึ่งแห่ง
   * การยิงรัวจะทำให้ฐานข้อมูลเต็มไปด้วยวิทยาลัยที่ไม่มีอยู่จริง
   */
  @Throttle(3, 60)
  @Public()
  @Post('institutions')
  provision(
    @Body() dto: ProvisionDto,
    @Headers('x-provision-key') key?: string,
  ) {
    this.svc.assertKey(key);
    return this.svc.provision(dto);
  }

  /*
   * ─── POST /provisioning/subscriptions และ /provisioning/usage ถูกตัดออกแล้ว ───
   *
   * ทั้งสองเส้นทางย้ายไปที่หน้าจอผู้ให้บริการ (POST /platform/subscriptions
   * และ GET /platform/institutions) ซึ่งรู้ว่า**ใคร**เป็นคนทำและบันทึกไว้ใน
   * platform_action_log ต่างจากกุญแจที่ทั้งทีมใช้ร่วมกัน
   *
   * และ /provisioning/usage ยังยืมบริบท admin ของแต่ละวิทยาลัยมานับสด
   * ซึ่งขัดกับหลักข้อ 5ค โดยตรง — โค้ดที่ยืมบริบทของลูกค้าได้หนึ่งที่
   * คือโค้ดที่อ่านอะไรก็ได้ของลูกค้าได้ทั้งหมด ฝั่ง /platform อ่านจาก
   * usage_snapshot ที่งานประจำวันเก็บไว้แทน
   *
   * ─── ทำไม /provisioning/institutions ยังอยู่ ───
   * เป็นทางฉุกเฉินทางเดียวที่เปิดวิทยาลัยได้เมื่อบัญชีผู้ให้บริการเข้าไม่ได้
   * (ลืมอุปกรณ์ MFA ทั้งทีม) การตัดทิ้งแปลว่าเหลือทางเดียวที่พังพร้อมกันได้
   */
}

@Module({
  // ใช้ AuthService ออกรหัสรีเซ็ตให้ผู้ดูแลคนแรก จึงต้องนำเข้า AuthModule
  // แทนที่จะเขียนตรรกะการออกรหัสซ้ำที่นี่ให้มีโอกาสเพี้ยนไปคนละทาง
  imports: [AuthModule],
  controllers: [ProvisioningController],
  providers: [ProvisioningService],
  exports: [ProvisioningService],
})
export class ProvisioningModule {}

import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpException,
  HttpStatus,
  Injectable,
  Post,
  Query,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsIn,
  IsISO8601,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { createHmac } from 'node:crypto';
import { Public } from '../../common/auth/auth.guard';
import { AppRole } from '../../common/context/request-context';
import { hashNationalId, isValidThaiNationalId } from '../../common/crypto/national-id';
import { generateResetCode, normalizeResetCode } from '../../common/auth/reset-code';
import { DbService } from '../../common/db/db.service';
import { Throttle } from '../../common/throttle/throttle.guard';
import { IsUuid, IsUuidArray } from '../../common/validation/uuid';

/**
 * สมัครเรียนออนไลน์ — เส้นทางเดียวที่คนนอกเขียนข้อมูลเข้าระบบได้
 *
 * กฎทุกข้ออยู่ในฟังก์ชัน `apply_*` ของ 0096 ชั้นนี้ทำแค่สามอย่างที่ฐานข้อมูล
 * ทำเองไม่ได้: สุ่มรหัสลับ · แฮชเลขบัตรและรหัสด้วยกุญแจที่อยู่นอกฐานข้อมูล ·
 * และกันบอทชั้นนอก (honeypot + เวลากรอกขั้นต่ำ + ตัวจำกัดคำขอรายไอพี)
 *
 * ─── ทำไมเพดานต่อไอพีไม่ต่ำกว่านี้ ───
 * ผู้สมัครจำนวนมากกรอกจากห้องคอมพิวเตอร์ของโรงเรียนเดิมในคาบแนะแนว ซึ่งออก
 * เน็ตด้วยไอพีเดียวกันทั้งห้อง เพดานห้าใบต่อชั่วโมงจะล็อกทั้งห้องตั้งแต่คนที่หก
 * ตัวกันจริงของการยิงใบปลอมคือเลขบัตรที่ซ้ำไม่ได้ในรอบเดียวกัน
 *
 * ─── วิทยาลัยมาจากค่าที่ตั้งตอน build ของหน้าสาธารณะ ───
 * ไม่มีเส้นทางไหนคืนรายชื่อวิทยาลัย — `institutionId` ที่ไม่ถูกต้องได้รายการ
 * รอบว่างเปล่า เหมือนวิทยาลัยที่ยังไม่เปิดรับ
 */

const MIN_FILL_MS = 5_000;

class FormFields {
  @IsOptional() @IsString() @MaxLength(30) prefixTh?: string;
  @IsString() @MaxLength(100) firstNameTh: string;
  @IsString() @MaxLength(100) lastNameTh: string;
  @IsISO8601() birthDate: string;
  @IsOptional() @IsIn(['male', 'female', 'other', 'undisclosed']) gender?: string;
  @IsString() @MaxLength(20) phone: string;
  @IsOptional() @IsString() @MaxLength(200) email?: string;
  @IsOptional() @IsString() @MaxLength(500) addressTh?: string;
  @IsOptional() @IsString() @MaxLength(200) priorSchoolTh?: string;
  @IsOptional() @IsString() @MaxLength(100) priorQualificationTh?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(4) priorGpax?: number;
  @IsOptional() @IsString() @MaxLength(100) referralSource?: string;
  @IsOptional() @IsString() @MaxLength(100) fatherFirstNameTh?: string;
  @IsOptional() @IsString() @MaxLength(100) fatherLastNameTh?: string;
  @IsOptional() @IsString() @MaxLength(100) fatherOccupationTh?: string;
  @IsOptional() @IsString() @MaxLength(20) fatherPhone?: string;
  @IsOptional() @IsString() @MaxLength(100) motherFirstNameTh?: string;
  @IsOptional() @IsString() @MaxLength(100) motherLastNameTh?: string;
  @IsOptional() @IsString() @MaxLength(100) motherOccupationTh?: string;
  @IsOptional() @IsString() @MaxLength(20) motherPhone?: string;

  /** curriculum_version_id เรียงตามอันดับ */
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(3) @IsUuidArray()
  choices: string[];
}

class SubmitDto extends FormFields {
  @IsUuid() institutionId: string;
  @IsUuid() roundId: string;
  @Matches(/^[0-9-\s]{13,17}$/, { message: 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก' })
  nationalId: string;

  /** ช่องที่ซ่อนจากคน — คนไม่เห็นจึงไม่กรอก บอทที่กรอกทุกช่องจะกรอก */
  @IsOptional() @IsString() homepageUrl?: string;
  /** เวลาที่หน้าเปิดฟอร์ม (มิลลิวินาที) — บอทที่ยิงตรงไม่ผ่านหน้าไม่มีค่านี้ */
  @IsInt() startedAt: number;
}

class CredentialDto {
  @IsUuid() institutionId: string;
  @IsString() @MaxLength(40) applicationNo: string;
  @IsString() @MaxLength(20) secret: string;
}

class UpdateDto extends FormFields {
  @IsUuid() institutionId: string;
  @IsString() @MaxLength(40) applicationNo: string;
  @IsString() @MaxLength(20) secret: string;
}

type Outcome = { outcome: 'ok' | 'invalid' | 'locked'; retry_after_secs: number; data: unknown };

@Injectable()
export class ApplyService {
  private readonly idSecret: string;
  private readonly accessKey: Buffer;

  constructor(
    private readonly db: DbService,
    config: ConfigService,
  ) {
    // กุญแจเดียวกับที่นำเข้าข้อมูลใช้แฮชเลขบัตร — ต้องตรงกัน มิฉะนั้น
    // admit_applicant() จะจับคู่ผู้สมัครกับ person เดิมไม่ได้
    this.idSecret = config.get<string>('IP_HASH_SECRET') ?? 'vec-sms';
    // แตกสายจาก JWT_SECRET ด้วยป้ายกำกับ หลักเดียวกับ resetCodeKey()
    this.accessKey = createHmac('sha256', config.get<string>('JWT_SECRET') ?? '')
      .update('vec-sms:application-access')
      .digest();
  }

  private ctx(institutionId: string) {
    return {
      institutionId,
      actorId: '00000000-0000-0000-0000-000000000000',
      role: 'auth' as AppRole,
    };
  }

  private hashSecret(secret: string): Buffer {
    return createHmac('sha256', this.accessKey).update(normalizeResetCode(secret)).digest();
  }

  private form(dto: FormFields) {
    return {
      prefix_th: dto.prefixTh, first_name_th: dto.firstNameTh, last_name_th: dto.lastNameTh,
      birth_date: dto.birthDate, gender: dto.gender, phone: dto.phone, email: dto.email,
      address_th: dto.addressTh, prior_school_th: dto.priorSchoolTh,
      prior_qualification_th: dto.priorQualificationTh, prior_gpax: dto.priorGpax,
      referral_source: dto.referralSource,
      father_first_name_th: dto.fatherFirstNameTh, father_last_name_th: dto.fatherLastNameTh,
      father_occupation_th: dto.fatherOccupationTh, father_phone: dto.fatherPhone,
      mother_first_name_th: dto.motherFirstNameTh, mother_last_name_th: dto.motherLastNameTh,
      mother_occupation_th: dto.motherOccupationTh, mother_phone: dto.motherPhone,
    };
  }

  async rounds(institutionId: string) {
    const rows = await this.db.runAs(this.ctx(institutionId), async (c) =>
      (await c.query(`select * from apply_open_rounds()`)).rows,
    );
    // จัดเป็นรอบ → สาขา ให้หน้าจอไม่ต้องรวมเอง
    const byRound = new Map<string, any>();
    for (const r of rows) {
      const round = byRound.get(r.round_id) ?? {
        id: r.round_id, name: r.round_name, appliesFrom: r.applies_from,
        appliesTo: r.applies_to, examOn: r.exam_on, announceOn: r.announce_on, programs: [],
      };
      round.programs.push({ curriculumVersionId: r.curriculum_version_id, name: r.curriculum_th, shift: r.shift });
      byRound.set(r.round_id, round);
    }
    return [...byRound.values()];
  }

  async submit(dto: SubmitDto) {
    // ตอบเหมือนกันทั้งสองกรณี ไม่บอกบอทว่าโดนจับด้วยอะไร
    if (dto.homepageUrl || Date.now() - dto.startedAt < MIN_FILL_MS) {
      throw new BadRequestException('ส่งใบสมัครไม่สำเร็จ กรุณาตรวจข้อมูลแล้วลองใหม่');
    }
    if (!isValidThaiNationalId(dto.nationalId)) {
      throw new BadRequestException('เลขประจำตัวประชาชนไม่ถูกต้อง (ตัวเลขตรวจสอบไม่ตรง)');
    }

    const secret = generateResetCode();
    const no = await this.db.runAs(this.ctx(dto.institutionId), async (c) =>
      (
        await c.query<{ no: string }>(
          `select apply_submit($1, $2::jsonb, $3, $4::uuid[], $5) as no`,
          [dto.roundId, JSON.stringify(this.form(dto)),
           hashNationalId(dto.nationalId, this.idSecret), dto.choices, this.hashSecret(secret)],
        )
      ).rows[0].no,
    );
    // รหัสลับออกจากระบบครั้งนี้ครั้งเดียว — ฐานข้อมูลมีแค่ค่าแฮช
    return { applicationNo: no, secret };
  }

  /** โยน *นอก* runAs เสมอ มิฉะนั้นตัวนับเดาผิดที่ฟังก์ชันเพิ่งเขียนจะถูก rollback */
  private settle(r: Outcome) {
    if (r.outcome === 'locked') {
      throw new HttpException(
        `ใส่รหัสผิดหลายครั้ง กรุณารอ ${Math.ceil(r.retry_after_secs / 60)} นาทีแล้วลองใหม่`,
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (r.outcome !== 'ok') {
      throw new UnauthorizedException('เลขที่ใบสมัครหรือรหัสลับไม่ถูกต้อง');
    }
    return r.data;
  }

  async status(dto: CredentialDto) {
    const r = await this.db.runAs(this.ctx(dto.institutionId), async (c) =>
      (
        await c.query<Outcome>(`select * from apply_lookup($1, $2)`,
          [dto.applicationNo, this.hashSecret(dto.secret)])
      ).rows[0],
    );
    return this.settle(r);
  }

  async update(dto: UpdateDto) {
    const r = await this.db.runAs(this.ctx(dto.institutionId), async (c) =>
      (
        await c.query<Outcome>(`select * from apply_update($1, $2, $3::jsonb, $4::uuid[])`,
          [dto.applicationNo, this.hashSecret(dto.secret),
           JSON.stringify(this.form(dto)), dto.choices])
      ).rows[0],
    );
    return this.settle(r);
  }
}

@Public()
@Controller('apply')
export class ApplyController {
  constructor(private readonly svc: ApplyService) {}

  @Throttle(60, 60)
  @Get('rounds')
  rounds(@Query('institutionId') institutionId: string) {
    if (!/^[0-9a-f-]{36}$/i.test(institutionId ?? '')) return [];
    return this.svc.rounds(institutionId);
  }

  @Throttle(10, 600)
  @Post('applications')
  submit(@Body() dto: SubmitDto) {
    return this.svc.submit(dto);
  }

  /** POST ไม่ใช่ GET — รหัสลับต้องไม่ไปอยู่ใน URL ที่ไปโผล่ใน log ของ proxy */
  @Throttle(20, 600)
  @Post('status')
  status(@Body() dto: CredentialDto) {
    return this.svc.status(dto);
  }

  @Throttle(10, 600)
  @Post('applications/update')
  update(@Body() dto: UpdateDto) {
    return this.svc.update(dto);
  }
}

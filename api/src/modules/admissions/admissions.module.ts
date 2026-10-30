import {
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
  Query,
} from '@nestjs/common';
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
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { hashNationalId } from '../../common/crypto/national-id';
import { ApplyController, ApplyService } from './apply';

/**
 * งานรับสมัครนักศึกษาใหม่
 *
 * ─── ทำไมโมดูลนี้สำคัญกว่าที่เห็น ───
 * ก่อนมีโมดูลนี้ นักศึกษาเข้าสู่ระบบได้สองทาง — นำเข้าไฟล์จากระบบเดิม
 * หรือรัน SQL เอง วิทยาลัยที่เริ่มใช้ระบบตั้งแต่ต้นปีจึงรับนักศึกษาใหม่ไม่ได้เลย
 *
 * ─── เลขบัตรประชาชนไม่ผ่านชั้นนี้แบบอ่านออก ───
 * ฐานข้อมูลเก็บเฉพาะค่าแฮช (หลักเดียวกับ person.national_id_hash ใน 0002)
 * ชั้นนี้แฮชด้วยกุญแจที่อยู่นอกฐานข้อมูล (`hashNationalId()`) แล้วไม่เก็บเลขไว้ที่ไหนอีก
 * ข้อจำกัดเดียวกับการนำเข้าข้อมูล — คอลัมน์ที่เข้ารหัสจริงรอเชื่อม KMS
 * ─── ผู้สมัครกรอกเองอยู่ที่ `apply.ts` ───
 * แยกไฟล์เพราะเป็นเส้นทาง @Public ที่ออกแบบการยืนยันตัวตน การกันบอท
 * และการจำกัดคำขอแยกต่างหาก (0096) ส่วนไฟล์นี้ทุก endpoint ยังเป็นของเจ้าหน้าที่
 */

class CreateRoundDto {
  @IsUuid() academicYearId: string;
  @IsString() code: string;
  @IsString() nameTh: string;
  @IsISO8601() appliesFrom: string;
  @IsISO8601() appliesTo: string;
  @IsOptional() @IsISO8601() examOn?: string;
  @IsOptional() @IsISO8601() announceOn?: string;
  @IsOptional() @IsISO8601() reportFrom?: string;
  @IsOptional() @IsISO8601() reportTo?: string;
  @IsOptional() @IsString() note?: string;
}

class RoundStatusDto {
  @IsIn(['draft', 'open', 'closed', 'announced', 'completed'])
  status: string;
}

class QuotaDto {
  @IsUuid() curriculumVersionId: string;
  @IsInt() @Min(1) seats: number;
  @IsOptional() @IsString() note?: string;
}

class ChoiceDto {
  @IsInt() @Min(1) @Max(5) preference: number;
  @IsUuid() curriculumVersionId: string;
}

class CreateApplicationDto {
  @IsUuid() roundId: string;
  @IsOptional() @IsString() prefixTh?: string;
  @IsString() firstNameTh: string;
  @IsString() lastNameTh: string;

  /** เลขบัตรประชาชนไทยมี 13 หลัก — ชั้นนี้ส่งต่อให้แฮชทันที ไม่เก็บไว้ */
  @IsOptional()
  @Matches(/^[0-9]{13}$/, { message: 'เลขประจำตัวประชาชนต้องเป็นตัวเลข 13 หลัก' })
  nationalId?: string;

  @IsOptional() @IsISO8601() birthDate?: string;
  @IsOptional() @IsIn(['male', 'female', 'other', 'undisclosed']) gender?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() email?: string;
  @IsOptional() @IsString() addressTh?: string;
  @IsOptional() @IsString() priorSchoolTh?: string;
  @IsOptional() @IsString() priorQualificationTh?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(4) priorGpax?: number;
  @IsOptional() @IsString() referralSource?: string;

  @IsOptional() @IsString() fatherPrefixTh?: string;
  @IsOptional() @IsString() fatherFirstNameTh?: string;
  @IsOptional() @IsString() fatherLastNameTh?: string;
  @IsOptional()
  @Matches(/^[0-9]{13}$/, { message: 'เลขประจำตัวประชาชนบิดาต้องเป็นตัวเลข 13 หลัก' })
  fatherNationalId?: string;
  @IsOptional() @IsString() fatherOccupationTh?: string;
  @IsOptional() @IsNumber() @Min(0) fatherIncomeMonthly?: number;
  @IsOptional() @IsString() fatherPhone?: string;

  @IsOptional() @IsString() motherPrefixTh?: string;
  @IsOptional() @IsString() motherFirstNameTh?: string;
  @IsOptional() @IsString() motherLastNameTh?: string;
  @IsOptional()
  @Matches(/^[0-9]{13}$/, { message: 'เลขประจำตัวประชาชนมารดาต้องเป็นตัวเลข 13 หลัก' })
  motherNationalId?: string;
  @IsOptional() @IsString() motherOccupationTh?: string;
  @IsOptional() @IsNumber() @Min(0) motherIncomeMonthly?: number;
  @IsOptional() @IsString() motherPhone?: string;

  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(5)
  @ValidateNested({ each: true }) @Type(() => ChoiceDto)
  choices: ChoiceDto[];
}

class DecisionDto {
  @IsIn(['passed', 'failed', 'waitlisted'], {
    message: 'ผลการคัดเลือกต้องเป็น passed, failed หรือ waitlisted',
  })
  outcome: string;
  @IsOptional() @IsUuid() curriculumVersionId?: string;
  @IsOptional() @IsInt() @Min(1) rankNo?: number;
  @IsOptional() @IsNumber() score?: number;
  @IsOptional() @IsString() note?: string;
}

class AdmitDto {
  @IsString() studentCode: string;
  @IsUuid() academicYearId: string;
  @IsOptional() @IsInt() @Min(1) @Max(6) studyYear?: number;
  @IsOptional() @IsString() groupCode?: string;
}

class DocumentDto {
  @IsString() kind: string;
  @IsOptional() @IsIn(['pending', 'received', 'verified', 'rejected']) status?: string;
  @IsOptional() @IsString() fileKey?: string;
  @IsOptional() @IsString() note?: string;
}

@Injectable()
export class AdmissionsService {
  constructor(private readonly db: DbService) {}

  /**
   * แฮชเลขบัตรด้วยกุญแจเดียวกับการนำเข้าและใบสมัครออนไลน์ (0061)
   * เดิมใช้ digest() เปล่า ซึ่งนอกจากไล่ย้อนได้แล้วยังไม่ตรงกับค่าของ
   * person ที่นำเข้ามา admit_applicant() จึงจับคู่คนเดิมไม่ได้ และใบที่
   * เจ้าหน้าที่กรอกกับใบที่ผู้สมัครกรอกเองจะไม่ชนกันที่ตัวกันยื่นซ้ำ
   */
  private nid(raw?: string): Buffer | null {
    return raw ? hashNationalId(raw, process.env.IP_HASH_SECRET ?? 'vec-sms') : null;
  }

  async createRound(dto: CreateRoundDto) {
    return this.db.queryOne(
      `insert into admission_round
         (institution_id, academic_year_id, code, name_th, applies_from, applies_to,
          exam_on, announce_on, report_from, report_to, note)
       values (current_institution_id(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       returning id, code, name_th, applies_from, applies_to, status`,
      [dto.academicYearId, dto.code, dto.nameTh, dto.appliesFrom, dto.appliesTo,
       dto.examOn ?? null, dto.announceOn ?? null,
       dto.reportFrom ?? null, dto.reportTo ?? null, dto.note ?? null],
    );
  }

  async listRounds() {
    return this.db.query(
      `select ar.id, ar.code, ar.name_th, ar.applies_from, ar.applies_to,
              ar.exam_on, ar.announce_on, ar.status,
              count(a.id)::integer                                   as applications,
              count(a.id) filter (where a.status = 'enrolled')::integer as enrolled
         from admission_round ar
         left join application a on a.round_id = ar.id
        group by ar.id
        order by ar.applies_from desc`,
    );
  }

  async setRoundStatus(roundId: string, dto: RoundStatusDto) {
    const row = await this.db.queryOne(
      `update admission_round set status = $2::admission_round_status
        where id = $1 returning id, code, status`,
      [roundId, dto.status],
    );
    if (!row) throw new NotFoundException('ไม่พบรอบรับสมัครที่ระบุ');
    return row;
  }

  async addQuota(roundId: string, dto: QuotaDto) {
    return this.db.queryOne(
      `insert into admission_quota (round_id, curriculum_version_id, seats, note)
       values ($1, $2, $3, $4)
       returning id, curriculum_version_id, seats`,
      [roundId, dto.curriculumVersionId, dto.seats, dto.note ?? null],
    );
  }

  async summary(roundId: string) {
    return this.db.query(
      `select curriculum_version_id, curriculum_th, shift,
              seats, applied, passed, enrolled, seats_left
         from admission_summary($1)`,
      [roundId],
    );
  }

  /**
   * สร้างใบสมัครพร้อมอันดับที่เลือกในทรานแซกชันเดียว
   *
   * ถ้าแยกกัน จะมีใบสมัครที่ไม่มีอันดับค้างอยู่เมื่อคำขอขาดกลางทาง
   * ซึ่งกินเลขที่ใบสมัครไปแล้วแต่ยื่นไม่ได้ (submit_application บังคับว่า
   * ต้องมีอันดับอย่างน้อยหนึ่ง)
   */
  async createApplication(dto: CreateApplicationDto) {
    return this.db.tx(async (c) => {
      const no = (
        await c.query<{ no: string }>(
          `select next_application_no($1) as no`, [dto.roundId],
        )
      ).rows[0].no;

      const app = (
        await c.query<{ id: string; application_no: string }>(
          `insert into application
             (institution_id, round_id, application_no, prefix_th,
              first_name_th, last_name_th, national_id_hash, birth_date, gender,
              phone, email, address_th, prior_school_th, prior_qualification_th,
              prior_gpax, referral_source,
              father_prefix_th, father_first_name_th, father_last_name_th,
              father_national_id_hash, father_occupation_th, father_income_monthly, father_phone,
              mother_prefix_th, mother_first_name_th, mother_last_name_th,
              mother_national_id_hash, mother_occupation_th, mother_income_monthly, mother_phone)
           values (current_institution_id(), $1, $2, $3, $4, $5,
                   $6::bytea,
                   $7, coalesce($8, 'undisclosed')::gender_kind,
                   $9, $10, $11, $12, $13, $14, $15,
                   $16, $17, $18,
                   $19::bytea,
                   $20, $21, $22,
                   $23, $24, $25,
                   $26::bytea,
                   $27, $28, $29)
           returning id, application_no`,
          [dto.roundId, no, dto.prefixTh ?? null, dto.firstNameTh, dto.lastNameTh,
           this.nid(dto.nationalId), dto.birthDate ?? null, dto.gender ?? null,
           dto.phone ?? null, dto.email ?? null, dto.addressTh ?? null,
           dto.priorSchoolTh ?? null, dto.priorQualificationTh ?? null,
           dto.priorGpax ?? null, dto.referralSource ?? null,
           dto.fatherPrefixTh ?? null, dto.fatherFirstNameTh ?? null, dto.fatherLastNameTh ?? null,
           this.nid(dto.fatherNationalId), dto.fatherOccupationTh ?? null,
           dto.fatherIncomeMonthly ?? null, dto.fatherPhone ?? null,
           dto.motherPrefixTh ?? null, dto.motherFirstNameTh ?? null, dto.motherLastNameTh ?? null,
           this.nid(dto.motherNationalId), dto.motherOccupationTh ?? null,
           dto.motherIncomeMonthly ?? null, dto.motherPhone ?? null],
        )
      ).rows[0];

      for (const ch of dto.choices) {
        await c.query(
          `insert into application_choice (application_id, preference, curriculum_version_id)
           values ($1, $2, $3)`,
          [app.id, ch.preference, ch.curriculumVersionId],
        );
      }

      return { id: app.id, applicationNo: app.application_no, choices: dto.choices.length };
    });
  }

  async listApplications(roundId: string, status?: string) {
    return this.db.query(
      `select a.id, a.application_no,
              trim(coalesce(a.prefix_th,'') || a.first_name_th || ' ' || a.last_name_th) as full_name,
              a.status, a.rank_no, a.score, a.submitted_at, a.reported_on,
              a.student_id, a.referral_source, a.submitted_via,
              cur.name_th as admitted_curriculum
         from application a
         left join curriculum_version cv on cv.id = a.admitted_curriculum_version_id
         left join curriculum cur        on cur.id = cv.curriculum_id
        where a.round_id = $1
          and ($2::text is null or a.status::text = $2)
        order by a.application_no
        limit 500`,
      [roundId, status ?? null],
    );
  }

  async getApplication(id: string) {
    const app = await this.db.queryOne(
      `select a.id, a.application_no, a.prefix_th, a.first_name_th, a.last_name_th,
              a.birth_date, a.gender, a.phone, a.email, a.address_th,
              a.prior_school_th, a.prior_qualification_th, a.prior_gpax,
              a.referral_source, a.status, a.rank_no, a.score, a.decision_note,
              a.submitted_at, a.decided_at, a.reported_on, a.student_id,
              a.father_prefix_th, a.father_first_name_th, a.father_last_name_th,
              a.father_occupation_th, a.father_income_monthly, a.father_phone,
              (a.father_national_id_hash is not null) as father_has_national_id,
              a.mother_prefix_th, a.mother_first_name_th, a.mother_last_name_th,
              a.mother_occupation_th, a.mother_income_monthly, a.mother_phone,
              (a.mother_national_id_hash is not null) as mother_has_national_id
         from application a where a.id = $1`,
      [id],
    );
    if (!app) throw new NotFoundException('ไม่พบใบสมัครที่ระบุ');

    const choices = await this.db.query(
      `select ac.preference, ac.curriculum_version_id, cur.name_th, cur.shift
         from application_choice ac
         join curriculum_version cv on cv.id = ac.curriculum_version_id
         join curriculum cur        on cur.id = cv.curriculum_id
        where ac.application_id = $1
        order by ac.preference`,
      [id],
    );

    const documents = await this.db.query(
      `select kind, status, file_key, note, checked_at
         from application_document where application_id = $1 order by kind`,
      [id],
    );

    return { ...app, choices, documents };
  }

  async submit(id: string) {
    return this.db.queryOne(
      `select id, application_no, status, submitted_at from submit_application($1)`,
      [id],
    );
  }

  async decide(id: string, dto: DecisionDto) {
    return this.db.queryOne(
      `select id, application_no, status, rank_no, score,
              admitted_curriculum_version_id
         from decide_application($1, $2, $3, $4::smallint, $5, $6)`,
      [id, dto.outcome, dto.curriculumVersionId ?? null,
       dto.rankNo ?? null, dto.score ?? null, dto.note ?? null],
    );
  }

  /** จุดเดียวที่ผู้สมัครกลายเป็นนักศึกษา */
  async admit(id: string, dto: AdmitDto) {
    const row = await this.db.queryOne<{ student_id: string }>(
      `select admit_applicant($1, $2, $3, $4::smallint, $5) as student_id`,
      [id, dto.studentCode, dto.academicYearId, dto.studyYear ?? 1, dto.groupCode ?? null],
    );
    return { studentId: row!.student_id, studentCode: dto.studentCode };
  }

  async upsertDocument(id: string, dto: DocumentDto) {
    return this.db.queryOne(
      `insert into application_document
         (application_id, kind, status, file_key, note, checked_by, checked_at)
       values ($1, $2, coalesce($3, 'pending')::document_check_status, $4, $5,
               current_actor_id(), now())
       on conflict (application_id, kind) do update
         set status = excluded.status, file_key = excluded.file_key,
             note = excluded.note, checked_by = excluded.checked_by,
             checked_at = excluded.checked_at
       returning kind, status, file_key`,
      [id, dto.kind, dto.status ?? null, dto.fileKey ?? null, dto.note ?? null],
    );
  }
}

/**
 * ข้อมูลผู้สมัครมีเลขบัตรประชาชนและข้อมูลผู้เยาว์ ครูผู้สอนไม่มีหน้าที่
 * เกี่ยวข้องกับการรับสมัคร จึงไม่อยู่ในรายชื่อ — RLS ในฐานข้อมูลกันซ้ำอีกชั้น
 */
@Roles('registrar', 'academic', 'director', 'admin')
@Controller('admissions')
class AdmissionsController {
  constructor(private readonly svc: AdmissionsService) {}

  @Get('rounds')
  listRounds() {
    return this.svc.listRounds();
  }

  @Audit('admission_round')
  @Post('rounds')
  createRound(@Body() dto: CreateRoundDto) {
    return this.svc.createRound(dto);
  }

  @Audit('admission_round', 'id')
  @Post('rounds/:id/status')
  setStatus(@Param('id', ParseUuidPipe) id: string, @Body() dto: RoundStatusDto) {
    return this.svc.setRoundStatus(id, dto);
  }

  @Audit('admission_quota', 'id')
  @Post('rounds/:id/quotas')
  addQuota(@Param('id', ParseUuidPipe) id: string, @Body() dto: QuotaDto) {
    return this.svc.addQuota(id, dto);
  }

  @Get('rounds/:id/summary')
  summary(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.summary(id);
  }

  @Get('applications')
  list(
    @Query('roundId', ParseUuidPipe) roundId: string,
    @Query('status') status?: string,
  ) {
    return this.svc.listApplications(roundId, status);
  }

  @Audit('application')
  @Post('applications')
  create(@Body() dto: CreateApplicationDto) {
    return this.svc.createApplication(dto);
  }

  @Audit('application', 'id')
  @Get('applications/:id')
  get(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.getApplication(id);
  }

  @Audit('application', 'id')
  @Post('applications/:id/submit')
  submit(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.submit(id);
  }

  @Audit('application', 'id')
  @Post('applications/:id/decision')
  decide(@Param('id', ParseUuidPipe) id: string, @Body() dto: DecisionDto) {
    return this.svc.decide(id, dto);
  }

  /** รับเข้าเป็นนักศึกษา — จำกัดที่งานทะเบียนเพราะสร้างรหัสนักศึกษาจริง */
  @Roles('registrar', 'director', 'admin')
  @Audit('application', 'id')
  @Post('applications/:id/admit')
  admit(@Param('id', ParseUuidPipe) id: string, @Body() dto: AdmitDto) {
    return this.svc.admit(id, dto);
  }

  @Audit('application_document', 'id')
  @Post('applications/:id/documents')
  document(@Param('id', ParseUuidPipe) id: string, @Body() dto: DocumentDto) {
    return this.svc.upsertDocument(id, dto);
  }
}

@Module({
  controllers: [AdmissionsController, ApplyController],
  providers: [AdmissionsService, ApplyService],
  exports: [AdmissionsService],
})
export class AdmissionsModule {}

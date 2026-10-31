import {
  BadRequestException,
  Header,
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

/**
 * งานรับสมัครนักศึกษาใหม่
 *
 * ─── ทำไมโมดูลนี้สำคัญกว่าที่เห็น ───
 * ก่อนมีโมดูลนี้ นักศึกษาเข้าสู่ระบบได้สองทาง — นำเข้าไฟล์จากระบบเดิม
 * หรือรัน SQL เอง วิทยาลัยที่เริ่มใช้ระบบตั้งแต่ต้นปีจึงรับนักศึกษาใหม่ไม่ได้เลย
 *
 * ─── เลขบัตรประชาชนไม่ผ่านชั้นนี้แบบอ่านออก ───
 * ฐานข้อมูลเก็บเฉพาะค่าแฮช (หลักเดียวกับ person.national_id_hash ใน 0002)
 * ชั้นนี้แฮชด้วยกุญแจ (hashNationalId) ก่อนส่งลงฐานข้อมูล แล้วไม่เก็บเลขไว้ที่ไหนอีก (0100)
 * ข้อจำกัดเดียวกับการนำเข้าข้อมูล — คอลัมน์ที่เข้ารหัสจริงรอเชื่อม KMS
 *
 * ─── ยังไม่เปิดให้ผู้สมัครกรอกเอง ───
 * ทุก endpoint ต้องเป็นเจ้าหน้าที่ เพราะการเปิดให้คนนอกสร้างใบสมัครได้เอง
 * ต้องมีการยืนยันตัวตน การกันบอท และการจำกัดจำนวนคำขอที่ออกแบบแยกต่างหาก
 * การเปิดก่อนแล้วค่อยคิดเรื่องนั้นทีหลังคือการเปิดช่องให้ยิงใบสมัครปลอม
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
  @IsOptional() @IsString() provinceTh?: string;

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

  /**
   * สถิติใบสมัครของรอบหนึ่งตามมิติ — SISA "รับสมัคร › ข้อมูลสถิติ" หกเมนู
   * (ผู้ลงทะเบียน · เกรดเฉลี่ย · จังหวัด · ภูมิภาค · สถานศึกษา · การประชาสัมพันธ์)
   * นับทุกใบที่ยื่นแล้ว ใบร่างไม่นับ — ร่างคือสิ่งที่เจ้าหน้าที่ยังกรอกไม่เสร็จ
   */
  async stats(roundId: string, dimension: string) {
    const dim = ADMISSION_DIMENSIONS[dimension];
    if (!dim) throw new BadRequestException('ไม่รู้จักมิติที่ขอ');
    const rows = await this.db.query<{ value: string; applications: string; admitted: string }>(
      `select ${dim.sql} as value, count(*) as applications,
              count(*) filter (where a.status in ('passed', 'enrolled')) as admitted
         from application a
        where a.round_id = $1 and a.status <> 'draft'
        group by 1 order by 2 desc, 1`,
      [roundId],
    );
    let out = rows.map((r) => ({ value: r.value, applications: Number(r.applications), admitted: Number(r.admitted) }));
    if (dimension === 'region') {
      const m = new Map<string, { value: string; applications: number; admitted: number }>();
      for (const r of out) {
        const k = regionOf(r.value || null);
        const cur = m.get(k) ?? { value: k, applications: 0, admitted: 0 };
        cur.applications += r.applications; cur.admitted += r.admitted;
        m.set(k, cur);
      }
      out = [...m.values()].sort((a, b) => b.applications - a.applications);
    }
    return { dimension, label: dim.label, rows: out };
  }

  /**
   * ใบรายงานตัว — SISA "ใบรายงานตัว" ผู้ผ่านการคัดเลือกพิมพ์ไปกรอก/ลงชื่อ
   * วันมอบตัว เป็นเอกสารทำงาน พิมพ์สดทุกครั้ง ไม่มีเลขที่ (หลักข้อ 4ก)
   * ออกได้เฉพาะคนที่ผ่านการคัดเลือกแล้ว — ใบรายงานตัวของคนที่ยังไม่ผ่าน
   * คือกระดาษที่ทำให้ผู้ปกครองเข้าใจผิดว่าลูกได้ที่เรียนแล้ว
   */
  async reportForm(id: string) {
    const a = await this.db.queryOne<{
      application_no: string; full_name: string; status: string; birth_date: string | null;
      prior_school_th: string | null; phone: string | null; curriculum_th: string | null; round_name: string;
      institution_name: string;
    }>(
      `select a.application_no, a.status::text, a.birth_date, a.prior_school_th, a.phone,
              trim(coalesce(a.prefix_th, '') || a.first_name_th || ' ' || a.last_name_th) as full_name,
              (select cur.name_th from curriculum_version cv join curriculum cur on cur.id = cv.curriculum_id
                where cv.id = a.admitted_curriculum_version_id) as curriculum_th,
              r.name_th as round_name,
              (select name_th from institution where id = a.institution_id) as institution_name
         from application a join admission_round r on r.id = a.round_id
        where a.id = $1`,
      [id],
    );
    if (!a) throw new NotFoundException('ไม่พบใบสมัคร');
    if (!['passed', 'enrolled'].includes(a.status)) {
      throw new BadRequestException('ออกใบรายงานตัวได้เฉพาะผู้ที่ผ่านการคัดเลือกแล้ว');
    }
    const line = (label: string, value: string | null) =>
      `<tr><th>${esc(label)}</th><td>${value ? esc(value) : '<span class="blank"></span>'}</td></tr>`;
    return `<!doctype html><html lang="th"><head><meta charset="utf-8"><title>ใบรายงานตัว ${esc(a.application_no)}</title>
<style>
  @page { size: A4 portrait; margin: 18mm; }
  body { font-family: 'TH Sarabun New', 'Sarabun', Tahoma, sans-serif; font-size: 15pt; color: #1c1c24; }
  h1 { font-size: 20pt; text-align: center; margin: 0; } h2 { font-size: 15pt; text-align: center; font-weight: 400; margin: 2pt 0 14pt; }
  table { width: 100%; border-collapse: collapse; } th { text-align: left; width: 34%; font-weight: 600; padding: 6pt 0; vertical-align: top; }
  td { padding: 6pt 0; } .blank { display: inline-block; width: 100%; border-bottom: 0.6pt dotted #555; height: 12pt; }
  .sign { margin-top: 36pt; display: grid; grid-template-columns: 1fr 1fr; gap: 24pt; text-align: center; }
  .sign div { padding-top: 30pt; border-top: 0.6pt dotted #555; }
  @media screen { body { background: #eef1f6; } .sheet { background: #fff; max-width: 210mm; margin: 24px auto; padding: 18mm; } }
</style></head><body><div class="sheet">
<h1>ใบรายงานตัวนักศึกษาใหม่</h1><h2>${esc(a.institution_name)} · ${esc(a.round_name)}</h2>
<table>
${line('เลขที่ใบสมัคร', a.application_no)}
${line('ชื่อ - นามสกุล', a.full_name)}
${line('วันเกิด', a.birth_date)}
${line('หลักสูตรที่ได้รับคัดเลือก', a.curriculum_th)}
${line('สถานศึกษาเดิม', a.prior_school_th)}
${line('โทรศัพท์', a.phone)}
${line('ชื่อผู้ปกครองที่มารายงานตัว', null)}
${line('ความเกี่ยวข้องกับนักศึกษา', null)}
${line('โทรศัพท์ผู้ปกครอง', null)}
${line('วันที่รายงานตัว', null)}
</table>
<div class="sign"><div>ลงชื่อผู้ปกครอง</div><div>ลงชื่อเจ้าหน้าที่รับรายงานตัว</div></div>
</div></body></html>`;
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
  /**
   * ค่าแฮชเลขบัตรแบบมีกุญแจ (HMAC) ตัวเดียวกับระเบียนนักศึกษา (0061) —
   * เดิมส่งเลขเปล่าให้ digest(sha256) ในคำสั่ง SQL ซึ่งไล่ย้อนกลับได้ในไม่กี่นาที
   * และแปลว่าเลขจริงเดินทางไปถึงฐานข้อมูล (ไปโผล่ใน log ของคำสั่งที่ช้าได้) (0100)
   */
  private hashOf(id?: string): Buffer | null {
    return id ? hashNationalId(id, process.env.IP_HASH_SECRET ?? 'vec-sms') : null;
  }

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
              mother_national_id_hash, mother_occupation_th, mother_income_monthly, mother_phone,
              province_th, national_id_hash_v)
           values (current_institution_id(), $1, $2, $3, $4, $5,
                   $6::bytea,
                   $7, coalesce($8, 'undisclosed')::gender_kind,
                   $9, $10, $11, $12, $13, $14, $15,
                   $16, $17, $18,
                   $19::bytea,
                   $20, $21, $22,
                   $23, $24, $25,
                   $26::bytea,
                   $27, $28, $29, nullif(btrim($30), ''), 2)
           returning id, application_no`,
          [dto.roundId, no, dto.prefixTh ?? null, dto.firstNameTh, dto.lastNameTh,
           this.hashOf(dto.nationalId), dto.birthDate ?? null, dto.gender ?? null,
           dto.phone ?? null, dto.email ?? null, dto.addressTh ?? null,
           dto.priorSchoolTh ?? null, dto.priorQualificationTh ?? null,
           dto.priorGpax ?? null, dto.referralSource ?? null,
           dto.fatherPrefixTh ?? null, dto.fatherFirstNameTh ?? null, dto.fatherLastNameTh ?? null,
           this.hashOf(dto.fatherNationalId), dto.fatherOccupationTh ?? null,
           dto.fatherIncomeMonthly ?? null, dto.fatherPhone ?? null,
           dto.motherPrefixTh ?? null, dto.motherFirstNameTh ?? null, dto.motherLastNameTh ?? null,
           this.hashOf(dto.motherNationalId), dto.motherOccupationTh ?? null,
           dto.motherIncomeMonthly ?? null, dto.motherPhone ?? null,
           dto.provinceTh ?? null],
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
              a.student_id, a.referral_source,
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

/**
 * จังหวัด → ภาค (แบ่งหกภาคตามราชบัณฑิตยสถาน) — SISA "ข้อมูลสถิติ › ภูมิภาค"
 * อยู่ที่ชั้นนี้ไม่ใช่ฐานข้อมูล เพราะเป็นข้อเท็จจริงทางภูมิศาสตร์ที่เหมือนกันทุก
 * วิทยาลัย ไม่ใช่กฎธุรกิจ จังหวัดที่สะกดไม่ตรงตกไปอยู่ "ไม่ระบุ" ไม่ถูกเดา
 */
const REGION: Record<string, string[]> = {
  'ภาคเหนือ': ['เชียงราย', 'เชียงใหม่', 'น่าน', 'พะเยา', 'แพร่', 'แม่ฮ่องสอน', 'ลำปาง', 'ลำพูน', 'อุตรดิตถ์'],
  'ภาคตะวันออกเฉียงเหนือ': ['กาฬสินธุ์', 'ขอนแก่น', 'ชัยภูมิ', 'นครพนม', 'นครราชสีมา', 'บึงกาฬ', 'บุรีรัมย์', 'มหาสารคาม',
    'มุกดาหาร', 'ยโสธร', 'ร้อยเอ็ด', 'เลย', 'ศรีสะเกษ', 'สกลนคร', 'สุรินทร์', 'หนองคาย', 'หนองบัวลำภู', 'อำนาจเจริญ',
    'อุดรธานี', 'อุบลราชธานี'],
  'ภาคกลาง': ['กรุงเทพมหานคร', 'กำแพงเพชร', 'ชัยนาท', 'นครนายก', 'นครปฐม', 'นครสวรรค์', 'นนทบุรี', 'ปทุมธานี',
    'พระนครศรีอยุธยา', 'พิจิตร', 'พิษณุโลก', 'เพชรบูรณ์', 'ลพบุรี', 'สมุทรปราการ', 'สมุทรสงคราม', 'สมุทรสาคร',
    'สระบุรี', 'สิงห์บุรี', 'สุโขทัย', 'สุพรรณบุรี', 'อ่างทอง', 'อุทัยธานี'],
  'ภาคตะวันออก': ['จันทบุรี', 'ฉะเชิงเทรา', 'ชลบุรี', 'ตราด', 'ปราจีนบุรี', 'ระยอง', 'สระแก้ว'],
  'ภาคตะวันตก': ['กาญจนบุรี', 'ตาก', 'ประจวบคีรีขันธ์', 'เพชรบุรี', 'ราชบุรี'],
  'ภาคใต้': ['กระบี่', 'ชุมพร', 'ตรัง', 'นครศรีธรรมราช', 'นราธิวาส', 'ปัตตานี', 'พังงา', 'พัทลุง', 'ภูเก็ต', 'ยะลา',
    'ระนอง', 'สงขลา', 'สตูล', 'สุราษฎร์ธานี'],
};
function regionOf(province: string | null): string {
  if (!province) return 'ไม่ระบุ';
  const p = province.replace(/^จ(ังหวัด|\.)\s*/, '').trim();
  return Object.entries(REGION).find(([, list]) => list.includes(p))?.[0] ?? 'ไม่ระบุ';
}

/** มิติของสถิติรับสมัคร — ชื่อมิติเลือกจากรายการตายตัว ไม่ถูกต่อเข้า SQL ตรง ๆ */
const ADMISSION_DIMENSIONS: Record<string, { label: string; sql: string }> = {
  program:  { label: 'หลักสูตรอันดับ 1', sql: `coalesce((select cur.name_th from application_choice ch
               join curriculum_version cv on cv.id = ch.curriculum_version_id
               join curriculum cur on cur.id = cv.curriculum_id
              where ch.application_id = a.id order by ch.preference limit 1), 'ไม่ระบุ')` },
  status:   { label: 'สถานะใบสมัคร', sql: `a.status::text` },
  gender:   { label: 'เพศ', sql: `case a.gender when 'male' then 'ชาย' when 'female' then 'หญิง' else 'ไม่ระบุ' end` },
  gpa:      { label: 'เกรดเฉลี่ยเดิม', sql: `case when a.prior_gpax is null then 'ไม่ระบุ'
               when a.prior_gpax < 2 then '1. ต่ำกว่า 2.00' when a.prior_gpax < 2.5 then '2. 2.00–2.49'
               when a.prior_gpax < 3 then '3. 2.50–2.99' when a.prior_gpax < 3.5 then '4. 3.00–3.49'
               else '5. 3.50–4.00' end` },
  school:   { label: 'สถานศึกษาเดิม', sql: `coalesce(nullif(btrim(a.prior_school_th), ''), 'ไม่ระบุ')` },
  province: { label: 'จังหวัด', sql: `coalesce(nullif(btrim(a.province_th), ''), 'ไม่ระบุ')` },
  region:   { label: 'ภูมิภาค', sql: `coalesce(nullif(btrim(a.province_th), ''), '')` },
  referral: { label: 'รู้จักวิทยาลัยจาก', sql: `coalesce(nullif(btrim(a.referral_source), ''), 'ไม่ระบุ')` },
};

function esc(v: unknown): string {
  return String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

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

  @Get('rounds/:id/stats')
  stats(@Param('id', ParseUuidPipe) id: string, @Query('dimension') dimension = 'program') {
    return this.svc.stats(id, dimension);
  }

  @Header('content-type', 'text/html; charset=utf-8')
  @Get('applications/:id/report-form/print')
  reportForm(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.reportForm(id);
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
  controllers: [AdmissionsController],
  providers: [AdmissionsService],
  exports: [AdmissionsService],
})
export class AdmissionsModule {}

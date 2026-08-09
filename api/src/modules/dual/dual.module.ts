import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import {
  ArrayNotEmpty,
  IsArray,
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
} from 'class-validator';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * ทวิภาคีและการฝึกประสบการณ์สมรรถนะวิชาชีพ
 *
 * ─── ทำไมโมดูลนี้เพิ่งมี ───
 * practicum_log.workplace_id มีคอลัมน์มาตั้งแต่แรกแต่ไม่มีตารางให้อ้างถึง
 * migration 0019 สร้างทะเบียนสถานประกอบการ ข้อตกลง และใบส่งตัว
 * แล้วผูกคีย์นอกให้ ระบบจึงเพิ่งตอบได้ว่านักศึกษาฝึกอยู่ที่ไหน
 *
 * ─── ชั่วโมงที่ยังไม่รับรองไม่ใช่ชั่วโมงที่หายไป ───
 * ทุก endpoint ที่คืนชั่วโมงฝึกแยกสองตัวเสมอ — รับรองแล้วกับรอรับรอง
 * ตัวแรกใช้ตรวจจบ ตัวหลังแสดงในแอปให้นักศึกษาเห็นว่าที่ส่งไปแล้ว
 * ยังรอครูนิเทศอยู่เท่าไร ระบบที่แสดงแค่ตัวเดียวทำให้นักศึกษาคิดว่า
 * ที่บันทึกไปหายไปเฉย ๆ แล้วโทรมาถามทุกสัปดาห์
 */

const WORKPLACE_STATUS = ['draft', 'approved', 'suspended', 'terminated'] as const;
const PLACEMENT_STATUS = ['planned', 'active', 'completed', 'terminated'] as const;
const PRACTICUM_SOURCE = ['student_app', 'supervisor', 'teacher', 'import'] as const;

class CreateWorkplaceDto {
  @IsString() @MaxLength(40) code: string;
  @IsString() nameTh: string;
  @IsOptional() @IsString() nameEn?: string;
  @IsOptional() @IsString() branchTh?: string;
  @IsOptional() @Matches(/^[0-9]{13}$/, { message: 'เลขประจำตัวผู้เสียภาษีต้องเป็นตัวเลข 13 หลัก' })
  taxId?: string;
  @IsOptional() @IsString() industry?: string;
  @IsOptional() @IsString() addressTh?: string;
  @IsOptional() @IsString() province?: string;
  @IsOptional() @IsString() postalCode?: string;
  @IsOptional() @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @IsNumber() @Min(-180) @Max(180) lng?: number;
  @IsOptional() @IsInt() @Min(20) @Max(5000) checkinRadiusM?: number;
  @IsOptional() @IsString() contactName?: string;
  @IsOptional() @IsString() contactPhone?: string;
  @IsOptional() @IsString() contactEmail?: string;
  @IsOptional() @IsInt() @Min(1) capacity?: number;
  @IsOptional() @IsString() note?: string;
}

class UpdateWorkplaceDto {
  @IsOptional() @IsString() nameTh?: string;
  @IsOptional() @IsString() branchTh?: string;
  @IsOptional() @IsString() industry?: string;
  @IsOptional() @IsString() addressTh?: string;
  @IsOptional() @IsString() province?: string;
  @IsOptional() @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @IsNumber() @Min(-180) @Max(180) lng?: number;
  @IsOptional() @IsInt() @Min(20) @Max(5000) checkinRadiusM?: number;
  @IsOptional() @IsString() contactName?: string;
  @IsOptional() @IsString() contactPhone?: string;
  @IsOptional() @IsString() contactEmail?: string;
  @IsOptional() @IsInt() @Min(1) capacity?: number;
  @IsOptional() @IsIn(WORKPLACE_STATUS as unknown as string[]) status?: string;
  @IsOptional() @IsString() note?: string;
}

class SupervisorDto {
  @IsString() fullNameTh: string;
  @IsOptional() @IsString() positionTh?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() email?: string;
  @IsOptional() @IsBoolean() isPrimary?: boolean;
}

class AgreementDto {
  @IsUuid() workplaceId: string;
  @IsString() agreementNo: string;
  @IsISO8601() startsOn: string;
  @IsISO8601() endsOn: string;
  @IsOptional() @IsUuid() curriculumVersionId?: string;
  @IsOptional() @IsISO8601() signedOn?: string;
  @IsOptional() @IsInt() @Min(1) seats?: number;
  @IsOptional() @IsString() scopeTh?: string;
}

class PlacementDto {
  @IsUuid() studentId: string;
  @IsUuid() workplaceId: string;
  @IsISO8601() startsOn: string;
  @IsISO8601() endsOn: string;
  @IsOptional() @IsUuid() agreementId?: string;
  @IsOptional() @IsUuid() termId?: string;
  @IsOptional() @IsUuid() enrollmentId?: string;
  @IsOptional() @IsUuid() supervisorId?: string;
  @IsOptional() @IsUuid() advisorStaffId?: string;
  @IsOptional() @IsNumber() @Min(1) targetHours?: number;
}

class UpdatePlacementDto {
  @IsOptional() @IsIn(PLACEMENT_STATUS as unknown as string[]) status?: string;
  @IsOptional() @IsUuid() supervisorId?: string;
  @IsOptional() @IsUuid() advisorStaffId?: string;
  @IsOptional() @IsISO8601() endsOn?: string;
  @IsOptional() @IsString() terminatedNote?: string;
}

class PracticumLogDto {
  @IsUuid() studentId: string;
  @IsISO8601() workedOn: string;
  @IsNumber() @Min(0.5) @Max(24) hours: number;
  @IsOptional() @IsUuid() placementId?: string;
  @IsOptional() @IsUuid() workplaceId?: string;
  @IsOptional() @IsUuid() enrollmentId?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsIn(PRACTICUM_SOURCE as unknown as string[]) source?: string;
  @IsOptional() @IsNumber() checkinLat?: number;
  @IsOptional() @IsNumber() checkinLng?: number;
}

class VerifyDto {
  @IsArray() @ArrayNotEmpty() @IsUuidArray() logIds: string[];
  @IsOptional() @IsBoolean() verify?: boolean;
}

@Injectable()
export class DualService {
  constructor(private readonly db: DbService) {}

  // ─── สถานประกอบการ ─────────────────────────────────────────────

  async listWorkplaces(status?: string, q?: string) {
    return this.db.query(
      `select w.id, w.code, w.name_th, w.branch_th, w.industry, w.province,
              w.status, w.capacity, w.contact_name, w.contact_phone,
              w.lat, w.lng, w.checkin_radius_m, w.assessed_on, w.approved_at,
              count(sp.id) filter (where sp.status = 'active') as active_students
         from workplace w
         left join student_placement sp on sp.workplace_id = w.id
        where ($1::text is null or w.status::text = $1)
          and ($2::text is null or w.name_th ilike '%' || $2 || '%' or w.code ilike '%' || $2 || '%')
        group by w.id
        order by w.code`,
      [status ?? null, q ?? null],
    );
  }

  async getWorkplace(id: string) {
    return this.db.tx(async (c) => {
      const wp = (
        await c.query(
          `select * from workplace where id = $1`,
          [id],
        )
      ).rows[0];
      if (!wp) throw new ForbiddenException('ไม่พบสถานประกอบการนี้ หรือไม่มีสิทธิ์เข้าถึง');

      const supervisors = (
        await c.query(
          `select id, full_name_th, position_th, phone, email, is_primary, active
             from workplace_supervisor where workplace_id = $1
            order by is_primary desc, full_name_th`,
          [id],
        )
      ).rows;

      const agreements = (
        await c.query(
          `select id, agreement_no, signed_on, starts_on, ends_on, seats, active
             from dual_training_agreement where workplace_id = $1
            order by starts_on desc`,
          [id],
        )
      ).rows;

      return { ...wp, supervisors, agreements };
    });
  }

  async createWorkplace(dto: CreateWorkplaceDto) {
    return this.db.queryOne(
      `insert into workplace
         (institution_id, code, name_th, name_en, branch_th, tax_id, industry,
          address_th, province, postal_code, lat, lng, checkin_radius_m,
          contact_name, contact_phone, contact_email, capacity, note)
       values (current_institution_id(), $1, $2, $3, $4, $5, $6,
               $7, $8, $9, $10, $11, coalesce($12, 300),
               $13, $14, $15, $16, $17)
       returning id, code, name_th, status`,
      [
        dto.code, dto.nameTh, dto.nameEn ?? null, dto.branchTh ?? null,
        dto.taxId ?? null, dto.industry ?? null, dto.addressTh ?? null,
        dto.province ?? null, dto.postalCode ?? null,
        dto.lat ?? null, dto.lng ?? null, dto.checkinRadiusM ?? null,
        dto.contactName ?? null, dto.contactPhone ?? null, dto.contactEmail ?? null,
        dto.capacity ?? null, dto.note ?? null,
      ],
    );
  }

  async updateWorkplace(id: string, dto: UpdateWorkplaceDto) {
    const row = await this.db.queryOne(
      `update workplace
          set name_th          = coalesce($2, name_th),
              branch_th        = coalesce($3, branch_th),
              industry         = coalesce($4, industry),
              address_th       = coalesce($5, address_th),
              province         = coalesce($6, province),
              lat              = coalesce($7, lat),
              lng              = coalesce($8, lng),
              checkin_radius_m = coalesce($9, checkin_radius_m),
              contact_name     = coalesce($10, contact_name),
              contact_phone    = coalesce($11, contact_phone),
              contact_email    = coalesce($12, contact_email),
              capacity         = coalesce($13, capacity),
              status           = coalesce($14::workplace_status, status),
              note             = coalesce($15, note)
        where id = $1
        returning id, code, name_th, status`,
      [
        id, dto.nameTh ?? null, dto.branchTh ?? null, dto.industry ?? null,
        dto.addressTh ?? null, dto.province ?? null, dto.lat ?? null, dto.lng ?? null,
        dto.checkinRadiusM ?? null, dto.contactName ?? null, dto.contactPhone ?? null,
        dto.contactEmail ?? null, dto.capacity ?? null, dto.status ?? null, dto.note ?? null,
      ],
    );
    if (!row) throw new ForbiddenException('ไม่พบสถานประกอบการนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  /**
   * อนุมัติให้รับนักศึกษาได้
   *
   * แยกจาก updateWorkplace เพราะเป็นการรับรองตามระเบียบ ไม่ใช่การแก้ข้อมูล
   * ต้องรู้ว่าใครอนุมัติและเมื่อไร ซึ่งการ PATCH สถานะเฉย ๆ ไม่ได้บันทึกไว้
   */
  async approveWorkplace(id: string, assessedOn?: string) {
    const row = await this.db.queryOne(
      `update workplace
          set status      = 'approved',
              assessed_on = coalesce($2::date, assessed_on, current_date),
              approved_by = (select id from staff where person_id = current_actor_id()),
              approved_at = now()
        where id = $1
        returning id, code, name_th, status, assessed_on, approved_at`,
      [id, assessedOn ?? null],
    );
    if (!row) throw new ForbiddenException('ไม่พบสถานประกอบการนี้ หรือไม่มีสิทธิ์อนุมัติ');
    return row;
  }

  async addSupervisor(workplaceId: string, dto: SupervisorDto) {
    return this.db.queryOne(
      `insert into workplace_supervisor
         (workplace_id, full_name_th, position_th, phone, email, is_primary)
       values ($1, $2, $3, $4, $5, coalesce($6, false))
       returning id, full_name_th, position_th, phone, is_primary`,
      [
        workplaceId, dto.fullNameTh, dto.positionTh ?? null,
        dto.phone ?? null, dto.email ?? null, dto.isPrimary ?? null,
      ],
    );
  }

  // ─── ข้อตกลง ───────────────────────────────────────────────────

  async listAgreements(workplaceId?: string) {
    return this.db.query(
      `select a.id, a.agreement_no, a.signed_on, a.starts_on, a.ends_on,
              a.seats, a.active, a.scope_th,
              w.code as workplace_code, w.name_th as workplace_name,
              count(sp.id) as placements
         from dual_training_agreement a
         join workplace w on w.id = a.workplace_id
         left join student_placement sp on sp.agreement_id = a.id
        where ($1::uuid is null or a.workplace_id = $1)
        group by a.id, w.code, w.name_th
        order by a.starts_on desc`,
      [workplaceId ?? null],
    );
  }

  async createAgreement(dto: AgreementDto) {
    return this.db.queryOne(
      `insert into dual_training_agreement
         (institution_id, workplace_id, curriculum_version_id, agreement_no,
          signed_on, starts_on, ends_on, seats, scope_th)
       values (current_institution_id(), $1, $2, $3, $4, $5, $6, $7, $8)
       returning id, agreement_no, starts_on, ends_on, seats`,
      [
        dto.workplaceId, dto.curriculumVersionId ?? null, dto.agreementNo,
        dto.signedOn ?? null, dto.startsOn, dto.endsOn,
        dto.seats ?? null, dto.scopeTh ?? null,
      ],
    );
  }

  // ─── ใบส่งตัว ──────────────────────────────────────────────────

  async listPlacements(status?: string, workplaceId?: string, termId?: string) {
    return this.db.query(
      `select sp.id, sp.starts_on, sp.ends_on, sp.status, sp.target_hours,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              w.code as workplace_code, w.name_th as workplace_name,
              sup.full_name_th as supervisor_name,
              adv.first_name_th || ' ' || adv.last_name_th as advisor_name,
              coalesce(pl.verified_hours, 0) as verified_hours,
              coalesce(pl.pending_hours, 0)  as pending_hours
         from student_placement sp
         join student   s on s.id = sp.student_id
         join person    p on p.id = s.person_id
         join workplace w on w.id = sp.workplace_id
         left join workplace_supervisor sup on sup.id = sp.supervisor_id
         left join staff  adv_st on adv_st.id = sp.advisor_staff_id
         left join person adv    on adv.id = adv_st.person_id
         left join v_student_practicum pl on pl.student_id = sp.student_id
        where ($1::text is null or sp.status::text = $1)
          and ($2::uuid is null or sp.workplace_id = $2)
          and ($3::uuid is null or sp.term_id = $3)
        order by sp.starts_on desc, s.student_code`,
      [status ?? null, workplaceId ?? null, termId ?? null],
    );
  }

  /**
   * สร้างใบส่งตัว
   *
   * ไม่ตรวจการซ้อนทับช่วงเวลาที่นี่ เพราะ exclusion constraint ในฐานข้อมูล
   * ตรวจให้แล้ว และตรวจได้ทุกทางที่เขียนเข้ามา ไม่ใช่แค่ทางนี้ทางเดียว
   */
  async createPlacement(dto: PlacementDto) {
    return this.db.tx(async (c) => {
      // สถานประกอบการที่ยังไม่ผ่านประเมินรับนักศึกษาไม่ได้ตามระเบียบทวิภาคี
      const wp = (
        await c.query<{ status: string; name_th: string }>(
          `select status, name_th from workplace where id = $1`,
          [dto.workplaceId],
        )
      ).rows[0];

      if (!wp) throw new ForbiddenException('ไม่พบสถานประกอบการนี้ หรือไม่มีสิทธิ์เข้าถึง');
      if (wp.status !== 'approved') {
        throw new ForbiddenException(
          `${wp.name_th} ยังไม่ผ่านการประเมินความพร้อม (สถานะ ${wp.status}) จึงรับนักศึกษาฝึกไม่ได้`,
        );
      }

      const row = (
        await c.query(
          `insert into student_placement
             (student_id, workplace_id, agreement_id, term_id, enrollment_id,
              supervisor_id, advisor_staff_id, starts_on, ends_on, target_hours)
           values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
           returning id, starts_on, ends_on, status, target_hours`,
          [
            dto.studentId, dto.workplaceId, dto.agreementId ?? null,
            dto.termId ?? null, dto.enrollmentId ?? null, dto.supervisorId ?? null,
            dto.advisorStaffId ?? null, dto.startsOn, dto.endsOn, dto.targetHours ?? null,
          ],
        )
      ).rows[0];

      return row;
    });
  }

  async updatePlacement(id: string, dto: UpdatePlacementDto) {
    const row = await this.db.queryOne(
      `update student_placement
          set status           = coalesce($2::placement_status, status),
              supervisor_id    = coalesce($3, supervisor_id),
              advisor_staff_id = coalesce($4, advisor_staff_id),
              ends_on          = coalesce($5::date, ends_on),
              terminated_note  = coalesce($6, terminated_note)
        where id = $1
        returning id, status, starts_on, ends_on`,
      [
        id, dto.status ?? null, dto.supervisorId ?? null,
        dto.advisorStaffId ?? null, dto.endsOn ?? null, dto.terminatedNote ?? null,
      ],
    );
    if (!row) throw new ForbiddenException('ไม่พบใบส่งตัวนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  // ─── ชั่วโมงฝึก ────────────────────────────────────────────────

  async studentPracticum(studentId: string) {
    return this.db.tx(async (c) => {
      const summary = (
        await c.query(
          `select verified_hours, pending_hours, entries, workplaces,
                  last_worked_on, required_hours
             from v_student_practicum where student_id = $1`,
          [studentId],
        )
      ).rows[0] ?? {
        verified_hours: 0, pending_hours: 0, entries: 0,
        workplaces: 0, last_worked_on: null, required_hours: null,
      };

      const logs = (
        await c.query(
          `select pl.id, pl.worked_on, pl.hours, pl.description, pl.source,
                  pl.checkin_at, pl.verified_at,
                  w.name_th as workplace_name
             from practicum_log pl
             left join workplace w on w.id = pl.workplace_id
            where pl.student_id = $1
            order by pl.worked_on desc
            limit 200`,
          [studentId],
        )
      ).rows;

      const placements = (
        await c.query(
          `select sp.id, sp.starts_on, sp.ends_on, sp.status, sp.target_hours,
                  w.name_th as workplace_name
             from student_placement sp
             join workplace w on w.id = sp.workplace_id
            where sp.student_id = $1
            order by sp.starts_on desc`,
          [studentId],
        )
      ).rows;

      return { ...summary, placements, logs };
    });
  }

  async recordLog(dto: PracticumLogDto) {
    return this.db.queryOne(
      `insert into practicum_log
         (student_id, enrollment_id, placement_id, workplace_id, worked_on, hours,
          description, source, checkin_at, checkin_lat, checkin_lng)
       select $1, $2, $3,
              -- ไม่ส่งสถานประกอบการมาก็หยิบจากใบส่งตัวให้ เพราะแอปของนักศึกษา
              -- รู้แค่ว่าตัวเองถูกส่งไปฝึกที่ไหน ไม่ควรต้องรู้ uuid ของที่ฝึก
              coalesce($4, (select sp.workplace_id from student_placement sp where sp.id = $3)),
              $5, $6, $7, coalesce($8::practicum_source, 'student_app'),
              case when $9::numeric is not null then now() end, $9, $10
       returning id, worked_on, hours, workplace_id, verified_at`,
      [
        dto.studentId, dto.enrollmentId ?? null, dto.placementId ?? null,
        dto.workplaceId ?? null, dto.workedOn, dto.hours,
        dto.description ?? null, dto.source ?? null,
        dto.checkinLat ?? null, dto.checkinLng ?? null,
      ],
    );
  }

  async verifyLogs(dto: VerifyDto) {
    const row = await this.db.queryOne<{ n: number }>(
      `select verify_practicum_hours($1::uuid[], $2) as n`,
      [dto.logIds, dto.verify ?? true],
    );
    return {
      affected: Number(row?.n ?? 0),
      verified: dto.verify ?? true,
    };
  }

  /** คิวรอครูนิเทศรับรอง — หน้าจอหลักของครูนิเทศ */
  async pendingVerification(advisorOnly = true) {
    return this.db.query(
      `select pl.id, pl.worked_on, pl.hours, pl.description, pl.source,
              pl.checkin_at, pl.checkin_lat, pl.checkin_lng,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              w.name_th as workplace_name, w.lat as workplace_lat, w.lng as workplace_lng,
              w.checkin_radius_m
         from practicum_log pl
         join student   s on s.id = pl.student_id
         join person    p on p.id = s.person_id
         left join workplace w on w.id = pl.workplace_id
         left join student_placement sp on sp.id = pl.placement_id
         left join staff adv on adv.id = sp.advisor_staff_id
        where pl.verified_at is null
          and ($1::boolean is not true
               or adv.person_id = current_actor_id()
               or is_institution_wide_role())
        order by pl.worked_on desc
        limit 300`,
      [advisorOnly],
    );
  }
}

@Roles('teacher', 'academic', 'registrar', 'director', 'admin')
@Controller('workplaces')
class WorkplaceController {
  constructor(private readonly svc: DualService) {}

  @Get()
  list(@Query('status') status?: string, @Query('q') q?: string) {
    return this.svc.listWorkplaces(status, q);
  }

  @Get(':id')
  get(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.getWorkplace(id);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post()
  create(@Body() dto: CreateWorkplaceDto) {
    return this.svc.createWorkplace(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Patch(':id')
  update(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateWorkplaceDto) {
    return this.svc.updateWorkplace(id, dto);
  }

  @Roles('academic', 'director', 'admin')
  @Post(':id/approve')
  approve(
    @Param('id', ParseUuidPipe) id: string,
    @Body('assessedOn') assessedOn?: string,
  ) {
    return this.svc.approveWorkplace(id, assessedOn);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post(':id/supervisors')
  addSupervisor(
    @Param('id', ParseUuidPipe) id: string,
    @Body() dto: SupervisorDto,
  ) {
    return this.svc.addSupervisor(id, dto);
  }
}

@Roles('teacher', 'academic', 'registrar', 'director', 'admin')
@Controller('dual')
class DualController {
  constructor(private readonly svc: DualService) {}

  @Get('agreements')
  agreements(@Query('workplaceId') workplaceId?: string) {
    return this.svc.listAgreements(workplaceId);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('agreements')
  createAgreement(@Body() dto: AgreementDto) {
    return this.svc.createAgreement(dto);
  }

  @Get('placements')
  placements(
    @Query('status') status?: string,
    @Query('workplaceId') workplaceId?: string,
    @Query('termId') termId?: string,
  ) {
    return this.svc.listPlacements(status, workplaceId, termId);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('placements')
  createPlacement(@Body() dto: PlacementDto) {
    return this.svc.createPlacement(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Patch('placements/:id')
  updatePlacement(
    @Param('id', ParseUuidPipe) id: string,
    @Body() dto: UpdatePlacementDto,
  ) {
    return this.svc.updatePlacement(id, dto);
  }
}

/**
 * นักศึกษาบันทึกชั่วโมงเองได้ แต่รับรองเองไม่ได้
 * ฐานข้อมูลบังคับว่าผู้รับรองต้องเป็นบุคลากรของวิทยาลัย
 */
@Roles('student', 'guardian', 'teacher', 'academic', 'registrar', 'director', 'admin')
@Controller('practicum')
class PracticumController {
  constructor(private readonly svc: DualService) {}

  @Get('students/:studentId')
  student(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.studentPracticum(studentId);
  }

  @Post('logs')
  record(@Body() dto: PracticumLogDto) {
    return this.svc.recordLog(dto);
  }

  @Roles('teacher', 'academic', 'registrar', 'director', 'admin')
  @Get('pending')
  pending(@Query('all') all?: string) {
    return this.svc.pendingVerification(all !== 'true');
  }

  @Roles('teacher', 'academic', 'registrar', 'director', 'admin')
  @Post('verify')
  verify(@Body() dto: VerifyDto) {
    return this.svc.verifyLogs(dto);
  }
}

@Module({
  controllers: [WorkplaceController, DualController, PracticumController],
  providers: [DualService],
  exports: [DualService],
})
export class DualModule {}

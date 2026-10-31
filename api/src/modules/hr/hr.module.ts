import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Injectable,
  Module,
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
  IsNumber,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * งานบุคลากร — โครงสร้างหน่วยงาน ระเบียน ทช.1 การลา และเวลาทำการ
 *
 * ─── ทำไมแยกจากโมดูล staff ───
 * โมดูล staff คุมเรื่องสิทธิ์ในระบบ (ใครเป็น registrar ได้บ้าง) ซึ่งเป็น
 * เรื่องความปลอดภัย ส่วนโมดูลนี้เป็นงานทรัพยากรบุคคล คนละเรื่องกันและ
 * คนละคนดูแล การรวมไว้ด้วยกันจะทำให้ขอบเขตสิทธิ์ของทั้งสองเรื่องพันกัน
 *
 * (เหตุผลทางเทคนิคอีกข้อ — staff.module มี @Get(':id') อยู่แล้ว เส้นทาง
 *  อย่าง /staff/departments จะถูกจับกินเป็น id ตามลำดับที่ประกาศ)
 *
 * ─── ชั้นนี้ไม่ตรวจกฎการลาซ้ำ ───
 * "ผู้ยื่นอนุมัติเองไม่ได้" และ "ใบลาที่อนุมัติแล้วซ้อนวันกันไม่ได้"
 * อยู่ใน trigger กับ exclusion constraint ของ 0035 ทั้งคู่ การตรวจซ้ำที่นี่
 * จะกลายเป็นกฎชุดที่สองที่ค่อย ๆ เพี้ยนไปจากของจริง
 */

const LEAVE_KINDS = [
  'personal', 'sick', 'maternity', 'ordination',
  'military', 'training', 'unpaid', 'other',
] as const;

class CreateDepartmentDto {
  @IsOptional() @IsUuid() parentId?: string;
  @IsString() code: string;
  @IsString() nameTh: string;
  @IsIn(['faculty', 'division', 'department', 'section', 'office'])
  kind: string;
  @IsOptional() @IsUuid() headStaffId?: string;
  @IsOptional() @IsNumber() sortOrder?: number;
}

class AssignmentDto {
  @IsUuid() departmentId: string;
  @IsString() positionTh: string;
  @IsOptional() isPrimary?: boolean;
  @IsOptional() @IsISO8601() effectiveFrom?: string;
  @IsOptional() @IsISO8601() effectiveTo?: string;
}

class StaffRecordDto {
  @IsIn(['education', 'experience', 'training', 'award'])
  kind: string;
  @IsString() titleTh: string;
  @IsOptional() @IsString() organizationTh?: string;
  @IsOptional() @IsString() fieldTh?: string;
  @IsOptional() @IsISO8601() startedOn?: string;
  @IsOptional() @IsISO8601() endedOn?: string;
  @IsOptional() @IsNumber() @Min(0) hours?: number;
  @IsOptional() @IsString() documentNo?: string;
  @IsOptional() @IsString() note?: string;
}

class StaffChildDto {
  @IsString() fullNameTh: string;
  @IsOptional() @IsISO8601() birthDate?: string;
  @IsOptional() @IsUuid() studentId?: string;
  @IsOptional() @IsString() note?: string;
}

class LeaveRequestDto {
  @IsUuid() staffId: string;
  @IsIn(LEAVE_KINDS, { message: 'ประเภทการลาไม่ถูกต้อง' })
  kind: (typeof LEAVE_KINDS)[number];
  @IsISO8601() fromDate: string;
  @IsISO8601() toDate: string;
  @IsNumber() @Min(0.5) days: number;
  @IsString() reason: string;
  @IsOptional() @IsString() documentNo?: string;
}

class LeaveDecisionDto {
  @IsIn(['approved', 'rejected'], { message: 'ผลการพิจารณาต้องเป็น approved หรือ rejected' })
  status: string;
  @IsUuid() decidedBy: string;
  @IsOptional() @IsString() note?: string;
}

class AttendanceRowDto {
  @IsUuid() staffId: string;
  @IsIn(['present', 'late', 'leave', 'absent', 'holiday', 'off_duty'])
  status: string;
  @IsOptional() @IsString() checkIn?: string;
  @IsOptional() @IsString() checkOut?: string;
  @IsOptional() @IsString() note?: string;
}

/** บันทึกเวลาทำการทั้งวิทยาลัยในครั้งเดียว — เพดานเดียวกับงานกลุ่มอื่น */
class AttendanceDayDto {
  @IsISO8601() onDate: string;
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(500)
  @ValidateNested({ each: true }) @Type(() => AttendanceRowDto)
  rows: AttendanceRowDto[];
}

@Injectable()
export class HrService {
  constructor(private readonly db: DbService) {}

  async departments() {
    return this.db.query(
      `select id, parent_id, code, name_th, kind, depth, path_th,
              head_name, staff_count
         from department_tree()`,
    );
  }

  async createDepartment(dto: CreateDepartmentDto) {
    return this.db.queryOne(
      `insert into department
         (institution_id, parent_id, code, name_th, kind, head_staff_id, sort_order)
       values (current_institution_id(), $1, $2, $3, $4::department_kind, $5,
               coalesce($6, 0))
       returning id, code, name_th, kind`,
      [dto.parentId ?? null, dto.code, dto.nameTh, dto.kind,
       dto.headStaffId ?? null, dto.sortOrder ?? null],
    );
  }

  async assign(staffId: string, dto: AssignmentDto) {
    return this.db.queryOne(
      `insert into staff_assignment
         (staff_id, department_id, position_th, is_primary, effective_from, effective_to)
       values ($1, $2, $3, coalesce($4, true), coalesce($5::date, current_date), $6)
       returning id, department_id, position_th, is_primary, effective_from`,
      [staffId, dto.departmentId, dto.positionTh, dto.isPrimary ?? null,
       dto.effectiveFrom ?? null, dto.effectiveTo ?? null],
    );
  }

  /** ระเบียนบุคลากร (ทช.1) — จัดกลุ่มตามประเภทให้พร้อมพิมพ์ */
  async records(staffId: string) {
    const rows = await this.db.query<{ kind: string }>(
      `select id, kind, title_th, organization_th, field_th,
              started_on, ended_on, hours, document_no, note
         from staff_record
        where staff_id = $1
        order by kind, started_on nulls last`,
      [staffId],
    );

    const group = (k: string) => rows.filter((r) => r.kind === k);
    return {
      education: group('education'),
      experience: group('experience'),
      training: group('training'),
      award: group('award'),
      // ชั่วโมงพัฒนาตนเองต่อปีเป็นตัวเลขที่ถูกถามทุกครั้งที่ประเมิน
      trainingHours: group('training').reduce(
        (n, r: any) => n + Number(r.hours ?? 0), 0),
    };
  }

  async addRecord(staffId: string, dto: StaffRecordDto) {
    return this.db.queryOne(
      `insert into staff_record
         (staff_id, kind, title_th, organization_th, field_th,
          started_on, ended_on, hours, document_no, note)
       values ($1, $2::staff_record_kind, $3, $4, $5, $6, $7, $8, $9, $10)
       returning id, kind, title_th`,
      [staffId, dto.kind, dto.titleTh, dto.organizationTh ?? null,
       dto.fieldTh ?? null, dto.startedOn ?? null, dto.endedOn ?? null,
       dto.hours ?? null, dto.documentNo ?? null, dto.note ?? null],
    );
  }

  async children(staffId: string) {
    return this.db.query(
      `select sc.id, sc.full_name_th, sc.birth_date, sc.student_id,
              s.student_code, sc.note
         from staff_child sc
         left join student s on s.id = sc.student_id
        where sc.staff_id = $1
        order by sc.birth_date nulls last`,
      [staffId],
    );
  }

  async addChild(staffId: string, dto: StaffChildDto) {
    return this.db.queryOne(
      `insert into staff_child (staff_id, full_name_th, birth_date, student_id, note)
       values ($1, $2, $3, $4, $5)
       returning id, full_name_th, student_id`,
      [staffId, dto.fullNameTh, dto.birthDate ?? null,
       dto.studentId ?? null, dto.note ?? null],
    );
  }

  async requestLeave(dto: LeaveRequestDto) {
    return this.db.queryOne(
      `insert into staff_leave
         (institution_id, staff_id, kind, from_date, to_date, days, reason,
          document_no, requested_by)
       values (current_institution_id(), $1, $2::leave_kind, $3, $4, $5, $6, $7,
               current_actor_id())
       returning id, kind, from_date, to_date, days, status`,
      [dto.staffId, dto.kind, dto.fromDate, dto.toDate, dto.days,
       dto.reason, dto.documentNo ?? null],
    );
  }

  async listLeaves(status?: string, staffId?: string) {
    return this.db.query(
      `select l.id, l.kind, l.from_date, l.to_date, l.days, l.reason,
              l.status, l.requested_at, l.decided_at, l.decision_note,
              s.staff_code,
              trim(coalesce(p.prefix_th,'') || coalesce(p.first_name_th,'')
                   || ' ' || coalesce(p.last_name_th,'')) as full_name
         from staff_leave l
         join staff s  on s.id = l.staff_id
         join person p on p.id = s.person_id
        where ($1::text is null or l.status::text = $1)
          and ($2::uuid is null or l.staff_id = $2)
        order by l.from_date desc
        limit 200`,
      [status ?? null, staffId ?? null],
    );
  }

  async decideLeave(id: string, dto: LeaveDecisionDto) {
    return this.db.queryOne(
      `update staff_leave
          set status = $2::leave_status, decided_by = $3, decision_note = $4
        where id = $1
        returning id, status, decided_at, decision_note`,
      [id, dto.status, dto.decidedBy, dto.note ?? null],
    );
  }

  /**
   * บันทึกเวลาทำการทั้งวันในครั้งเดียว
   *
   * ใช้ on conflict เพราะการบันทึกซ้ำวันเดิมคือการแก้ไข ไม่ใช่ความผิดพลาด —
   * คนที่มาสายแล้วภายหลังยื่นใบลาย้อนหลังต้องเปลี่ยนสถานะได้
   */
  async recordAttendance(dto: AttendanceDayDto) {
    return this.db.tx(async (c) => {
      let n = 0;
      for (const row of dto.rows) {
        await c.query(
          `insert into staff_attendance
             (institution_id, staff_id, on_date, status, check_in, check_out, note)
           values (current_institution_id(), $1, $2, $3::work_attendance_status,
                   $4::time, $5::time, $6)
           on conflict (staff_id, on_date) do update
             set status = excluded.status, check_in = excluded.check_in,
                 check_out = excluded.check_out, note = excluded.note,
                 recorded_at = now()`,
          [row.staffId, dto.onDate, row.status,
           row.checkIn ?? null, row.checkOut ?? null, row.note ?? null],
        );
        n++;
      }
      return { onDate: dto.onDate, recorded: n };
    });
  }

  async worktime(from: string, to: string) {
    const rows = await this.db.query<{
      present: number; late: number; absent: number; leave_days: string;
    }>(
      `select staff_id, staff_code, full_name, department,
              present, late, on_leave, absent, leave_days
         from staff_worktime_summary($1::date, $2::date)`,
      [from, to],
    );

    return {
      from, to,
      staff: rows.length,
      totals: {
        present: rows.reduce((n, r) => n + Number(r.present), 0),
        late: rows.reduce((n, r) => n + Number(r.late), 0),
        absent: rows.reduce((n, r) => n + Number(r.absent), 0),
        leaveDays: rows.reduce((n, r) => n + Number(r.leave_days), 0),
      },
      rows,
    };
  }
}

/**
 * ระเบียนบุคลากร ใบลา และเวลาทำการเป็นข้อมูลส่วนบุคคลของพนักงาน
 * จึงจำกัดไว้ที่งานบุคคลและผู้บริหาร — RLS กันซ้ำอีกชั้น และเปิดให้
 * บุคลากรเห็นของตัวเองผ่านนโยบาย restrictive ใน 0035
 */
@Roles('registrar', 'director', 'admin')
@Controller('hr')
class HrController {
  constructor(private readonly svc: HrService) {}

  /** โครงสร้างหน่วยงานเปิดกว้างกว่าเรื่องอื่น เพราะทุกคนต้องรู้ว่าสังกัดที่ไหน */
  @Roles('registrar', 'academic', 'teacher', 'director', 'admin')
  @Get('departments')
  departments() {
    return this.svc.departments();
  }

  @Audit('department')
  @Post('departments')
  createDepartment(@Body() dto: CreateDepartmentDto) {
    return this.svc.createDepartment(dto);
  }

  @Audit('staff_assignment', 'id')
  @Post('staff/:id/assignments')
  assign(@Param('id', ParseUuidPipe) id: string, @Body() dto: AssignmentDto) {
    return this.svc.assign(id, dto);
  }

  @Audit('staff_record', 'id')
  @Get('staff/:id/records')
  records(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.records(id);
  }

  @Audit('staff_record', 'id')
  @Post('staff/:id/records')
  addRecord(@Param('id', ParseUuidPipe) id: string, @Body() dto: StaffRecordDto) {
    return this.svc.addRecord(id, dto);
  }

  @Audit('staff_child', 'id')
  @Get('staff/:id/children')
  children(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.children(id);
  }

  @Audit('staff_child', 'id')
  @Post('staff/:id/children')
  addChild(@Param('id', ParseUuidPipe) id: string, @Body() dto: StaffChildDto) {
    return this.svc.addChild(id, dto);
  }

  @Get('leaves')
  listLeaves(@Query('status') status?: string, @Query('staffId') staffId?: string) {
    return this.svc.listLeaves(status, staffId);
  }

  @Audit('staff_leave')
  @Post('leaves')
  requestLeave(@Body() dto: LeaveRequestDto) {
    return this.svc.requestLeave(dto);
  }

  @Audit('staff_leave', 'id')
  @Post('leaves/:id/decision')
  decideLeave(@Param('id', ParseUuidPipe) id: string, @Body() dto: LeaveDecisionDto) {
    return this.svc.decideLeave(id, dto);
  }

  @Audit('staff_attendance')
  @Post('attendance')
  attendance(@Body() dto: AttendanceDayDto) {
    return this.svc.recordAttendance(dto);
  }

  @Get('worktime')
  worktime(@Query('from') from: string, @Query('to') to: string) {
    return this.svc.worktime(from, to);
  }
}

/**
 * รายงานบุคลากรแบบ SISA (หมวดบุคลากร › ข้อมูลบุคลากร · ข้อมูลสถิติ · ฝึกอบรม)
 *
 * มิติของสถิติเลือกจากรายการตายตัวนี้เท่านั้น ชื่อมิติจาก query string ไม่เคย
 * ถูกต่อเข้า SQL ตรง ๆ (หลักเดียวกับ STUDENT_DIMENSIONS ของ /reports)
 *
 * ─── ทำไมอายุงานนับจากการมอบหมายครั้งแรก ───
 * สคีมาไม่มีช่อง "วันเริ่มงาน" แยก ส่วนการมอบหมายตำแหน่งครั้งแรก
 * (staff_assignment.effective_from ที่เก่าที่สุด) คือวันที่บุคลากรเริ่มมีตำแหน่ง
 * ในวิทยาลัยจริง คนที่ยังไม่เคยถูกมอบหมายอยู่ในแถว "ไม่ระบุ" ไม่ถูกเดา
 */
export const STAFF_DIMENSIONS: Record<string, { label: string; sql: string }> = {
  employment: { label: 'ประเภทบุคลากร', sql: `case b.employment_kind when 'civil_servant' then 'ข้าราชการ'
                  when 'permanent' then 'พนักงานประจำ' when 'contract' then 'พนักงานสัญญาจ้าง'
                  when 'part_time' then 'ครูพิเศษ/ไม่เต็มเวลา' when 'industry_expert' then 'ผู้เชี่ยวชาญจากสถานประกอบการ'
                  else b.employment_kind::text end` },
  teacher:    { label: 'ครูผู้สอน / บุคลากรสนับสนุน', sql: `case when b.is_teacher then 'ครูผู้สอน' else 'บุคลากรสนับสนุน' end` },
  department: { label: 'ฝ่าย/หน่วยงาน', sql: `coalesce((select d.name_th from staff_assignment a join department d on d.id = a.department_id
                  where a.staff_id = b.id and a.is_primary and a.effective_to is null limit 1), 'ไม่ระบุ')` },
  position:   { label: 'ตำแหน่ง', sql: `coalesce((select a.position_th from staff_assignment a
                  where a.staff_id = b.id and a.is_primary and a.effective_to is null limit 1), 'ไม่ระบุ')` },
  gender:     { label: 'เพศ', sql: `case b.gender when 'male' then 'ชาย' when 'female' then 'หญิง'
                  when 'other' then 'อื่น ๆ' else 'ไม่ระบุ' end` },
  age:        { label: 'ช่วงอายุ', sql: `case when b.birth_date is null then 'ไม่ระบุ'
                  when age(b.birth_date) < interval '30 years' then '1. ต่ำกว่า 30 ปี'
                  when age(b.birth_date) < interval '40 years' then '2. 30–39 ปี'
                  when age(b.birth_date) < interval '50 years' then '3. 40–49 ปี'
                  when age(b.birth_date) < interval '60 years' then '4. 50–59 ปี'
                  else '5. 60 ปีขึ้นไป' end` },
  service:    { label: 'อายุงาน', sql: `(select case when min(a.effective_from) is null then 'ไม่ระบุ'
                  when age(min(a.effective_from)) < interval '1 year' then '1. ไม่ถึง 1 ปี'
                  when age(min(a.effective_from)) < interval '5 years' then '2. 1–4 ปี'
                  when age(min(a.effective_from)) < interval '10 years' then '3. 5–9 ปี'
                  when age(min(a.effective_from)) < interval '20 years' then '4. 10–19 ปี'
                  else '5. 20 ปีขึ้นไป' end
                  from staff_assignment a where a.staff_id = b.id)` },
  education:  { label: 'วุฒิการศึกษาล่าสุด', sql: `coalesce((select r.title_th from staff_record r
                  where r.staff_id = b.id and r.kind = 'education'
                  order by r.ended_on desc nulls last, r.started_on desc nulls last limit 1), 'ไม่ระบุ')` },
  province:   { label: 'จังหวัดที่อยู่', sql: `coalesce((select a.province_th from person_address a
                  where a.person_id = b.person_id order by case a.kind when 'current' then 1 else 2 end limit 1), 'ไม่ระบุ')` },
};

@Injectable()
export class HrReportsService {
  constructor(private readonly db: DbService) {}

  /** จำนวนบุคลากรตามมิติ × เพศ — รูปเดียวกับตารางสถิติบุคลากรของ SISA */
  async breakdown(dimension: string, activeOnly: boolean) {
    const dim = STAFF_DIMENSIONS[dimension];
    if (!dim) throw new BadRequestException('ไม่รู้จักมิติที่ขอ');
    const rows = await this.db.query<{ value: string; gender: string; staff: string }>(
      `with b as (
         select st.id, st.person_id, st.employment_kind, st.is_teacher, pe.gender, pe.birth_date
           from staff st join person pe on pe.id = st.person_id
          where ($1::boolean is false or st.active))
       select ${dim.sql} as value,
              case b.gender when 'male' then 'ชาย' when 'female' then 'หญิง' else 'ไม่ระบุ' end as gender,
              count(*) as staff
         from b group by 1, 2 order by 1, 2`,
      [activeOnly],
    );
    return { dimension, label: dim.label, rows: rows.map((r) => ({ value: r.value, gender: r.gender, staff: Number(r.staff) })) };
  }

  /** รายชื่อบุคลากรพร้อมข้อมูลที่ SISA แยกเป็นหลายรายงาน — ตำแหน่ง · อายุ · อายุงาน · วุฒิ · ใบอนุญาต */
  async roster(activeOnly: boolean) {
    return this.db.query(
      `select st.id, st.staff_code, st.employment_kind, st.is_teacher, st.license_no, st.license_expires,
              trim(coalesce(pe.prefix_th, '') || coalesce(pe.first_name_th, '') || ' ' || coalesce(pe.last_name_th, '')) as full_name,
              pe.birth_date, extract(year from age(pe.birth_date))::int as age_years,
              (select a.position_th from staff_assignment a where a.staff_id = st.id and a.is_primary and a.effective_to is null limit 1) as position_th,
              (select d.name_th from staff_assignment a join department d on d.id = a.department_id
                where a.staff_id = st.id and a.is_primary and a.effective_to is null limit 1) as department_th,
              (select min(a.effective_from) from staff_assignment a where a.staff_id = st.id) as started_on,
              (select r.title_th from staff_record r where r.staff_id = st.id and r.kind = 'education'
                order by r.ended_on desc nulls last limit 1) as education_th
         from staff st join person pe on pe.id = st.person_id
        where ($1::boolean is false or st.active)
        order by st.staff_code`,
      [activeOnly],
    );
  }

  /** ชั่วโมงอบรมรายคนในช่วงวันที่ — SISA "ฝึกอบรม › ชั่วโมงการฝึกอบรม / ปีการศึกษา" */
  async trainingHours(from?: string, to?: string) {
    return this.db.query(
      `select st.id, st.staff_code,
              trim(coalesce(pe.prefix_th, '') || coalesce(pe.first_name_th, '') || ' ' || coalesce(pe.last_name_th, '')) as full_name,
              count(r.id) as courses, coalesce(sum(r.hours), 0) as hours
         from staff st
         join person pe on pe.id = st.person_id
         left join staff_record r on r.staff_id = st.id and r.kind = 'training'
              and ($1::date is null or r.started_on >= $1::date)
              and ($2::date is null or r.started_on <= $2::date)
        where st.active
        group by st.id, st.staff_code, pe.prefix_th, pe.first_name_th, pe.last_name_th
        order by hours desc, st.staff_code`,
      [from || null, to || null],
    );
  }

  /** วันลาที่อนุมัติแล้วรายคน × ประเภท — SISA "ข้อมูลสถิติ › การลา" */
  async leaveTotals(from?: string, to?: string) {
    return this.db.query(
      `select st.id, st.staff_code,
              trim(coalesce(pe.prefix_th, '') || coalesce(pe.first_name_th, '') || ' ' || coalesce(pe.last_name_th, '')) as full_name,
              l.kind, sum(l.days) as days, count(*) as times
         from staff_leave l
         join staff st on st.id = l.staff_id
         join person pe on pe.id = st.person_id
        where l.status = 'approved'
          and ($1::date is null or l.to_date >= $1::date)
          and ($2::date is null or l.from_date <= $2::date)
        group by st.id, st.staff_code, pe.prefix_th, pe.first_name_th, pe.last_name_th, l.kind
        order by st.staff_code, l.kind`,
      [from || null, to || null],
    );
  }

  /** ผลงานและรางวัลของบุคลากร — SISA "ข้อมูลสถิติ › ข้อมูลผลงานและเกียรติประวัติ" */
  async awards() {
    return this.db.query(
      `select r.id, r.title_th, r.organization_th, r.started_on, r.document_no, st.staff_code,
              trim(coalesce(pe.prefix_th, '') || coalesce(pe.first_name_th, '') || ' ' || coalesce(pe.last_name_th, '')) as full_name
         from staff_record r
         join staff st on st.id = r.staff_id
         join person pe on pe.id = st.person_id
        where r.kind = 'award'
        order by r.started_on desc nulls last
        limit 1000`,
    );
  }
}

/**
 * แยกคอนโทรลเลอร์จาก /hr เพื่อเปิดให้บทบาท hr (งานบุคคล) อ่านรายงานได้
 * — /hr เดิมเปิดแค่ registrar/director/admin ส่วน 0095 ให้ hr อ่านระเบียน
 * บุคลากรได้อยู่แล้ว (TEST 341) จึงไม่มีเหตุผลที่งานบุคคลจะดูรายงานของงาน
 * ตัวเองไม่ได้ รายงานทุกตัวในนี้อ่านอย่างเดียว
 */
@Roles('registrar', 'hr', 'director', 'admin')
@Controller('hr-reports')
export class HrReportsController {
  constructor(private readonly svc: HrReportsService) {}

  @Get('dimensions')
  dimensions() {
    return Object.entries(STAFF_DIMENSIONS).map(([key, d]) => ({ key, label: d.label }));
  }

  @Get('breakdown')
  breakdown(@Query('dimension') dimension: string, @Query('active') active = 'true') {
    return this.svc.breakdown(dimension, active !== 'false');
  }

  @Get('roster')
  roster(@Query('active') active = 'true') {
    return this.svc.roster(active !== 'false');
  }

  @Get('training')
  training(@Query('from') from?: string, @Query('to') to?: string) {
    return this.svc.trainingHours(from, to);
  }

  @Get('leaves')
  leaves(@Query('from') from?: string, @Query('to') to?: string) {
    return this.svc.leaveTotals(from, to);
  }

  @Get('awards')
  awards() {
    return this.svc.awards();
  }
}

@Module({
  controllers: [HrController, HrReportsController],
  providers: [HrService, HrReportsService],
  exports: [HrService],
})
export class HrModule {}

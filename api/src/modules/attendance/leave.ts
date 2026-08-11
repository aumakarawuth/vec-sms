/**
 * การลาของนักศึกษา (0054)
 *
 * ─── ทำไมอยู่ในโมดูลเช็คชื่อ ไม่ใช่โมดูลของตัวเอง ───
 * ใบลาที่อนุมัติแล้วเขียน `attendance_record` จริง มันจึงเป็นทางเข้าที่สอง
 * ของตารางเดียวกันกับที่ `AttendanceController` ดูแลอยู่ การแยกโมดูลจะทำให้
 * ขอบเขตสิทธิ์ของตารางนั้นกระจายอยู่สองที่ ซึ่งเป็นรูปเดียวกับที่ทำให้
 * `enrollment_result` กับ `grade_submission` ขัดกันโดยไม่มีใครเห็น (ข้อ 14)
 *
 * ─── ชั้นนี้ไม่ตัดสินอะไรเลย ───
 * ใครอนุมัติได้ · ใบที่ตัดสินแล้วแก้ได้ไหม · ใบลาทับสถานะ "มาเรียน" ได้ไหม
 * อยู่ใน trigger กับฟังก์ชันของ 0054 ทั้งหมด `@Roles` ที่นี่มีไว้ให้ได้ 403
 * ที่อ่านรู้เรื่องแทน error จากฐานข้อมูล ไม่ใช่เพื่อเป็นด่านจริง
 */
import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Injectable,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { IsIn, IsISO8601, IsOptional, IsString } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

const LEAVE_KINDS = ['sick', 'personal', 'activity'] as const;

class CreateLeaveDto {
  @IsUuid() studentId: string;
  @IsIn(LEAVE_KINDS) kind: string;
  @IsISO8601() fromDate: string;
  @IsISO8601() toDate: string;
  @IsString() reason: string;
  @IsOptional() @IsString() evidenceNote?: string;
}

class DecideLeaveDto {
  @IsIn(['approve', 'reject']) decision: string;
  @IsOptional() @IsString() note?: string;
}

class CancelLeaveDto {
  @IsString() reason: string;
}

@Injectable()
export class StudentLeaveService {
  constructor(private readonly db: DbService) {}

  /**
   * รายการใบลา — RLS เป็นคนตัดว่าเห็นของใครบ้าง
   *
   * นักศึกษาเห็นของตัวเอง · ผู้ปกครองเห็นของบุตรหลาน · ครูที่ปรึกษาเห็นของ
   * เด็กในที่ปรึกษา · บทบาทระดับวิทยาลัยเห็นทั้งหมด — ไม่มีเงื่อนไขไหน
   * เขียนซ้ำที่นี่ เพราะกฎที่เขียนสองที่จะค่อย ๆ เพี้ยนจากกัน
   */
  async list(status: string | undefined, studentId: string | undefined) {
    return this.db.query(
      `select sl.id, sl.student_id, sl.kind, sl.from_date, sl.to_date,
              sl.to_date - sl.from_date + 1 as days,
              sl.reason, sl.evidence_note, sl.status, sl.applied_periods,
              sl.requested_at, sl.decided_at, sl.decision_note,
              sl.guardian_ack_at,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              rq.first_name_th || ' ' || rq.last_name_th as requested_by_name,
              dc.first_name_th || ' ' || dc.last_name_th as decided_by_name,
              ga.first_name_th || ' ' || ga.last_name_th as guardian_ack_name
         from student_leave sl
         join student s on s.id = sl.student_id
         join person  p on p.id = s.person_id
         left join person rq on rq.id = sl.requested_by
         left join person dc on dc.id = sl.decided_by
         left join person ga on ga.id = sl.guardian_ack_by
        where ($1::text is null or sl.status = $1::student_leave_status)
          and ($2::uuid is null or sl.student_id = $2::uuid)
        order by sl.status = 'submitted' desc, sl.from_date desc
        limit 500`,
      [status ?? null, studentId ?? null],
    );
  }

  /**
   * ยื่นใบลา
   *
   * `requested_by` มาจากบริบทเสมอ ไม่ใช่จาก body — ถ้ารับจาก body
   * ใครก็ยื่นในนามคนอื่นได้ แล้วกฎ "ผู้ยื่นอนุมัติเองไม่ได้" จะเลี่ยงได้
   * ด้วยการใส่ชื่อคนอื่นเป็นผู้ยื่น
   */
  async create(dto: CreateLeaveDto) {
    const rows = await this.db.query(
      `insert into student_leave
         (institution_id, student_id, kind, from_date, to_date, reason,
          evidence_note, requested_by)
       values (current_institution_id(), $1, $2::student_leave_kind, $3, $4, $5, $6,
               current_actor_id())
       returning id, status, from_date, to_date`,
      [dto.studentId, dto.kind, dto.fromDate, dto.toDate, dto.reason,
       dto.evidenceNote ?? null],
    );
    return rows[0];
  }

  /**
   * ผู้ปกครองรับรองใบลา
   *
   * ต้องเป็นผู้ปกครองที่ยืนยันตัวตนแล้วและถูกติ๊ก `can_approve_leave`
   * ซึ่งบังคับด้วย `actor_leave_guardian_students()` ในนโยบาย update
   * — คนอื่นจะอัปเดตไม่ถูกแถวเลย จึงได้ศูนย์แถวแทนที่จะได้ข้อผิดพลาด
   */
  async guardianAck(leaveId: string) {
    const rows = await this.db.query(
      `update student_leave
          set guardian_ack_by = current_actor_id(), guardian_ack_at = now()
        where id = $1
          and status = 'submitted'
          and student_id in (select actor_leave_guardian_students())
        returning id, guardian_ack_at`,
      [leaveId],
    );
    if (rows.length === 0) {
      // ศูนย์แถวที่นี่มาจาก RLS ไม่ใช่จากข้อผิดพลาด — ต้องแปลงเป็น 403
      // ที่อ่านรู้เรื่อง มิฉะนั้นผู้ใช้จะเห็น 200 พร้อมค่าว่างแล้วคิดว่าสำเร็จ
      throw new ForbiddenException(
        'รับรองใบลาไม่ได้ — ต้องเป็นผู้ปกครองที่ยืนยันตัวตนแล้วและได้รับสิทธิ์รับรองการลา และใบต้องยังไม่ถูกตัดสิน',
      );
    }
    return rows[0];
  }

  async decide(leaveId: string, dto: DecideLeaveDto) {
    const rows = await this.db.query(
      `select leave_id, status, applied_periods, skipped_present
         from decide_student_leave($1, $2, $3)`,
      [leaveId, dto.decision === 'approve', dto.note ?? null],
    );
    return rows[0];
  }

  async cancel(leaveId: string, dto: CancelLeaveDto) {
    const rows = await this.db.query(
      `select leave_id, reverted from cancel_student_leave($1, $2)`,
      [leaveId, dto.reason],
    );
    return rows[0];
  }

  /** สรุปการลารายคน — คำถามที่ตอบไม่ได้เลยก่อนมี 0054 */
  async summary(studentId: string) {
    return this.db.query(
      `select kind, requests, days, periods
         from v_student_leave_summary
        where student_id = $1
        order by kind`,
      [studentId],
    );
  }
}

@Controller('leaves')
export class StudentLeaveController {
  constructor(private readonly svc: StudentLeaveService) {}

  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'student_affairs', 'director', 'admin',
  )
  @Get()
  list(@Query('status') status?: string, @Query('studentId') studentId?: string) {
    return this.svc.list(status, studentId);
  }

  @Roles('student', 'guardian', 'registrar', 'student_affairs', 'director', 'admin')
  @Audit('student_leave')
  @Post()
  create(@Body() dto: CreateLeaveDto) {
    return this.svc.create(dto);
  }

  @Roles('guardian')
  @Audit('student_leave', 'id')
  @Post(':id/guardian-ack')
  guardianAck(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.guardianAck(id);
  }

  @Roles('registrar', 'student_affairs', 'director', 'admin')
  @Audit('student_leave', 'id')
  @Post(':id/decision')
  decide(@Param('id', ParseUuidPipe) id: string, @Body() dto: DecideLeaveDto) {
    return this.svc.decide(id, dto);
  }

  /**
   * ยกเลิกใบลา — เจ้าของยกเลิกใบที่ยังไม่ถูกตัดสินได้
   * ส่วนใบที่อนุมัติแล้วยกเลิกได้เฉพาะเจ้าหน้าที่ (ฐานข้อมูลบังคับ)
   */
  @Roles('student', 'guardian', 'registrar', 'student_affairs', 'director', 'admin')
  @Audit('student_leave', 'id')
  @Post(':id/cancel')
  cancel(@Param('id', ParseUuidPipe) id: string, @Body() dto: CancelLeaveDto) {
    return this.svc.cancel(id, dto);
  }

  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'student_affairs', 'director', 'admin',
  )
  @Get('summary/:studentId')
  summary(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.summary(studentId);
  }
}

import {
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  Param,
  Post,
} from '@nestjs/common';
import { ArrayMaxSize, ArrayNotEmpty, IsArray, IsIn, IsISO8601, IsOptional, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

const STATUSES = [
  'present', 'late', 'leave_sick', 'leave_personal', 'activity', 'absent',
] as const;
type AttendanceStatus = (typeof STATUSES)[number];

class MarkDto {
  @IsUuid() enrollmentId: string;
  @IsIn(STATUSES as unknown as string[]) status: AttendanceStatus;
  /** เวลาที่ครูกดจริงบนเครื่อง ต่างจากเวลาที่ข้อมูลถึงเซิร์ฟเวอร์ กรณีเช็คชื่อออฟไลน์ */
  @IsOptional() @IsISO8601() capturedAt?: string;
}

class BulkMarkDto {
  /**
   * เพดาน 200 คนต่อคาบ — ห้องที่ใหญ่ที่สุดในวิทยาลัยอาชีวะยังไม่ถึงครึ่ง
   *
   * ไม่มีเพดานแปลว่าคำขอเดียวสร้างพารามิเตอร์ได้เป็นพัน ซึ่งชน
   * เพดาน 65535 ตัวของ PostgreSQL แล้วกลายเป็น 500 แทนที่จะเป็น 400
   */
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200)
  @ValidateNested({ each: true }) @Type(() => MarkDto)
  records: MarkDto[];
}

@Injectable()
export class AttendanceService {
  constructor(private readonly db: DbService) {}

  /**
   * รายชื่อสำหรับหน้าเช็คชื่อ (หน้าจอ P-02)
   *
   * คืน attendance_state มาด้วย เพื่อให้หน้าจอเตือนครูก่อนกดว่านักศึกษาคนนี้
   * ใกล้หมดสิทธิ์สอบแล้ว ไม่ใช่ให้รู้ทีหลังตอนตัดเกรด
   */
  async roster(meetingId: string) {
    const meeting = await this.db.queryOne(
      `select cm.id, cm.meets_on, cm.period_from, cm.period_to, cm.status,
              cs.id as class_section_id, cs.section_no,
              c.code as course_code, c.name_th as course_name
         from class_meeting cm
         join class_section cs on cs.id = cm.class_section_id
         join course c         on c.id  = cs.course_id
        where cm.id = $1`,
      [meetingId],
    );

    const students = await this.db.query(
      `select e.id as enrollment_id,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              ar.status,
              v.pct_projected, v.absences_left, v.attendance_state
         from class_meeting cm
         join enrollment e on e.class_section_id = cm.class_section_id
                          and e.status = 'enrolled'
         join student s    on s.id = e.student_id
         join person  p    on p.id = s.person_id
         left join attendance_record ar on ar.class_meeting_id = cm.id
                                      and ar.enrollment_id     = e.id
         left join v_enrollment_attendance v on v.enrollment_id = e.id
        where cm.id = $1
        order by s.student_code`,
      [meetingId],
    );

    return { meeting, students };
  }

  /**
   * บันทึกทีเดียวทั้งห้อง
   *
   * ค่าเริ่มต้นของทุกคนคือมาเรียน ครูแตะเฉพาะคนที่ไม่ตรง หน้าจอจึงส่งมาทั้งห้อง
   * เสมอเพื่อให้บันทึกซ้ำได้โดยไม่เกิดผลข้างเคียง (idempotent)
   */
  async mark(meetingId: string, dto: BulkMarkDto) {
    return this.db.tx(async (c) => {
      const values = dto.records
        // ต้องระบุชนิดให้ทุกช่อง เพราะ PostgreSQL เดาชนิดจาก VALUES list ที่เป็นพารามิเตอร์ล้วนไม่ได้
        .map((_, i) =>
          `($1::uuid, $${i * 3 + 2}::uuid, $${i * 3 + 3}::attendance_status, $${i * 3 + 4}::timestamptz)`,
        )
        .join(', ');
      const params: unknown[] = [meetingId];
      for (const r of dto.records) {
        params.push(r.enrollmentId, r.status, r.capturedAt ?? null);
      }

      const res = await c.query(
        `insert into attendance_record
           (class_meeting_id, enrollment_id, status, captured_at, source, recorded_by)
         select v.meeting_id, v.enrollment_id, v.status, v.captured_at,
                'teacher_mobile'::attendance_source, current_actor_id()
           from (values ${values}) as v(meeting_id, enrollment_id, status, captured_at)
         on conflict (class_meeting_id, enrollment_id) do update
           set status      = excluded.status,
               captured_at = excluded.captured_at,
               recorded_by = excluded.recorded_by,
               recorded_at = now()
         returning enrollment_id`,
        params,
      );

      // ปิดคาบเรียนแล้วถือว่าสอนจริง ซึ่งทำให้คาบนี้เข้าไปนับในตัวหารของกฎ 80%
      await c.query(
        `update class_meeting set status = 'held', closed_at = now()
          where id = $1 and status <> 'held'`,
        [meetingId],
      );

      return { saved: res.rowCount ?? 0 };
    });
  }

  async forEnrollment(enrollmentId: string) {
    return this.db.queryOne(
      `select periods_held, periods_credited, pct_to_date, pct_final,
              pct_projected, absences_left, attendance_state, min_pct, warn_pct
         from v_enrollment_attendance where enrollment_id = $1`,
      [enrollmentId],
    );
  }
}

/**
 * ─── ตั้งค่าเริ่มต้นเป็นปฏิเสธ แล้วเปิดทีละเส้นทาง ───
 * เดิม controller นี้เป็นตัวเดียวในระบบที่ไม่มี @Roles เลย นักศึกษาจึงเรียก
 * เส้นทางบันทึกการเช็คชื่อได้ และ RLS ก็ไม่ได้กันไว้ (ดู migration 0039)
 * ผลคือแก้ "ขาดเรียน" ของตัวเองเป็น "มาเรียน" ได้ กฎเวลาเรียน 80% จึงไร้ผล
 *
 * ประกาศบทบาทไว้ที่ระดับคลาสเพื่อให้เส้นทางที่เพิ่มเข้ามาใหม่ถูกปิดไว้ก่อน
 * แล้วเปิดเฉพาะเส้นทางที่นักศึกษาต้องใช้จริงด้วย @Roles ที่ระดับเมธอด
 * ซึ่งทับค่าของคลาส — ลืมใส่แล้วแน่นสุด ดีกว่าลืมใส่แล้วเปิดหมด
 */
@Roles('teacher', 'registrar', 'academic', 'student_affairs', 'director', 'admin')
@Controller('attendance')
class AttendanceController {
  constructor(private readonly svc: AttendanceService) {}

  @Get('meetings/:meetingId/roster')
  roster(@Param('meetingId', ParseUuidPipe) meetingId: string) {
    return this.svc.roster(meetingId);
  }

  @Post('meetings/:meetingId')
  mark(
    @Param('meetingId', ParseUuidPipe) meetingId: string,
    @Body() dto: BulkMarkDto,
  ) {
    return this.svc.mark(meetingId, dto);
  }

  /**
   * เวลาเรียนของตัวเอง — นักศึกษาและผู้ปกครองต้องดูได้
   *
   * เป็นเส้นทางเดียวของโมดูลนี้ที่เปิดให้เจ้าของข้อมูล เพราะการรู้ว่าตัวเอง
   * เหลือขาดได้อีกกี่คาบก่อนหมดสิทธิ์สอบ คือเหตุผลหลักที่แอปมีหน้านี้
   * ขอบเขตรายคนกรองด้วย RLS (attendance_scope) ไม่ได้กรองที่นี่
   */
  @Roles('student', 'guardian', 'teacher', 'registrar', 'academic',
         'student_affairs', 'director', 'admin')
  @Get('enrollments/:enrollmentId')
  enrollment(@Param('enrollmentId', ParseUuidPipe) id: string) {
    return this.svc.forEnrollment(id);
  }
}

@Module({
  controllers: [AttendanceController],
  providers: [AttendanceService],
  exports: [AttendanceService],
})
export class AttendanceModule {}

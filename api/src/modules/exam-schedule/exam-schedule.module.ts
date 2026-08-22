import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { IsIn, IsInt, IsISO8601, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * ตารางสอบ — จัดวัน เวลา ห้อง และกรรมการคุมสอบ
 *
 * ─── ทำไมตรวจการชนก่อน insert เสมอ ไม่ใช่แค่พึ่ง exclusion constraint ───
 * exclusion constraint (0075) กันได้แค่ห้องชนกัน — กรรมการคุมสอบชนและ
 * นักศึกษาชนเป็นเงื่อนไขข้ามตารางที่ constraint ตอบไม่ได้ ต้องเรียก
 * exam_conflicts() ก่อนเขียนเสมอ (รูปแบบเดียวกับ TimetableService.moveSlot())
 */

const EXAM_KIND = ['midterm', 'final'] as const;

class CreateExamSessionDto {
  @IsUuid() classSectionId: string;
  @IsIn(EXAM_KIND as unknown as string[]) kind: string;
  @IsISO8601() examDate: string;
  @IsInt() @Min(1) @Max(20) periodFrom: number;
  @IsInt() @Min(1) @Max(20) periodTo: number;
  @IsOptional() @IsUuid() roomId?: string;
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}

class UpdateExamSessionDto {
  @IsOptional() @IsISO8601() examDate?: string;
  @IsOptional() @IsInt() @Min(1) @Max(20) periodFrom?: number;
  @IsOptional() @IsInt() @Min(1) @Max(20) periodTo?: number;
  @IsOptional() @IsUuid() roomId?: string;
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}

class AddProctorDto {
  @IsUuid() staffId: string;
}

@Injectable()
export class ExamScheduleService {
  constructor(private readonly db: DbService) {}

  /**
   * รายการตารางสอบ พร้อมรายชื่อกรรมการคุมสอบซ้อนไว้ในแต่ละแถว
   *
   * ─── ทำไมดึงชื่อวิชา/เลขกลุ่มเรียนผ่าน class_section_display() ไม่ใช่ join ตรง ───
   * class_section มีนโยบาย section_scope ของตัวเอง (0034) ที่เปิดให้เฉพาะ
   * ครูผู้สอน/ผู้สอนคาบ/บทบาทวิชาการเห็น ซึ่งไม่รู้จักกรรมการคุมสอบเลย —
   * ถ้า join ตรง กรรมการที่ไม่ได้สอนวิชานั้นจะถูก inner join ตัดแถว exam_session
   * ที่ตัวเองมีสิทธิ์เห็นอยู่แล้วทิ้งไปเงียบ ๆ (เจอจริงตอนทดสอบ API-204 — ปิดใน 0076)
   */
  async list(termId?: string, classSectionId?: string) {
    return this.db.query(
      `select es.id, es.kind, es.exam_date, es.period_from, es.period_to, es.note,
              es.class_section_id, sec.section_no,
              sec.course_code, sec.course_name,
              r.id as room_id, r.code as room_code, r.name_th as room_name,
              coalesce(
                (select jsonb_agg(jsonb_build_object('staffId', st.id, 'staffCode', st.staff_code,
                                                      'fullName', trim(coalesce(p.prefix_th,'') || p.first_name_th || ' ' || p.last_name_th))
                                   order by p.first_name_th)
                   from exam_proctor ep
                   join staff st on st.id = ep.staff_id
                   join person p on p.id = st.person_id
                  where ep.exam_session_id = es.id),
                '[]'::jsonb
              ) as proctors
         from exam_session es
         cross join lateral class_section_display(es.class_section_id) as sec
         left join room r on r.id = es.room_id
        where ($1::uuid is null or sec.term_id = $1)
          and ($2::uuid is null or es.class_section_id = $2)
        order by es.exam_date, es.period_from, sec.course_code`,
      [termId ?? null, classSectionId ?? null],
    );
  }

  private async loadSession(id: string) {
    const row = await this.db.queryOne<{
      id: string; class_section_id: string; exam_date: string;
      period_from: number; period_to: number;
    }>(
      `select id, class_section_id, exam_date, period_from, period_to from exam_session where id = $1`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบตารางสอบนี้ หรือไม่มีสิทธิ์เข้าถึง');
    return row;
  }

  private async conflicts(
    classSectionId: string, examDate: string, periodFrom: number, periodTo: number,
    roomId: string | null, proctorIds: string[] | null, ignoreSessionId: string | null,
  ) {
    return this.db.query<{ kind: string; message_th: string }>(
      `select kind, message_th
         from exam_conflicts($1, $2::date, $3::smallint, $4::smallint, $5, $6::uuid[], $7)`,
      [classSectionId, examDate, periodFrom, periodTo, roomId, proctorIds, ignoreSessionId],
    );
  }

  private rejectIfConflicts(rows: { kind: string; message_th: string }[]) {
    if (rows.length > 0) {
      throw new BadRequestException({
        message: 'บันทึกตารางสอบไม่ได้ เพราะชนกับรายการต่อไปนี้',
        conflicts: rows.map((r) => r.message_th),
      });
    }
  }

  async create(dto: CreateExamSessionDto) {
    const conflicts = await this.conflicts(
      dto.classSectionId, dto.examDate, dto.periodFrom, dto.periodTo,
      dto.roomId ?? null, null, null,
    );
    this.rejectIfConflicts(conflicts);

    return this.db.queryOne(
      `insert into exam_session
         (institution_id, class_section_id, kind, exam_date, period_from, period_to, room_id, note)
       values (current_institution_id(), $1, $2::exam_kind, $3::date, $4::smallint, $5::smallint, $6, $7)
       returning id, class_section_id, kind, exam_date, period_from, period_to`,
      [
        dto.classSectionId, dto.kind, dto.examDate, dto.periodFrom, dto.periodTo,
        dto.roomId ?? null, dto.note?.trim() ?? null,
      ],
    );
  }

  /** ย้ายกำหนดการสอบ — ตรวจชนใหม่ทั้งห้องและกรรมการคุมสอบที่ผูกอยู่แล้ว */
  async update(id: string, dto: UpdateExamSessionDto) {
    const current = await this.loadSession(id);
    const examDate = dto.examDate ?? current.exam_date;
    const periodFrom = dto.periodFrom ?? current.period_from;
    const periodTo = dto.periodTo ?? current.period_to;

    const proctors = await this.db.query<{ staff_id: string }>(
      `select staff_id from exam_proctor where exam_session_id = $1`,
      [id],
    );

    if (dto.examDate || dto.periodFrom || dto.periodTo || dto.roomId !== undefined) {
      const conflicts = await this.conflicts(
        current.class_section_id, examDate, periodFrom, periodTo,
        dto.roomId ?? null, proctors.map((p) => p.staff_id), id,
      );
      this.rejectIfConflicts(conflicts);
    }

    const row = await this.db.queryOne(
      `update exam_session set
         exam_date   = coalesce($2::date, exam_date),
         period_from = coalesce($3::smallint, period_from),
         period_to   = coalesce($4::smallint, period_to),
         room_id     = coalesce($5, room_id),
         note        = coalesce($6, note),
         updated_at  = now()
       where id = $1
       returning id, exam_date, period_from, period_to, room_id`,
      [id, dto.examDate ?? null, dto.periodFrom ?? null, dto.periodTo ?? null, dto.roomId ?? null, dto.note?.trim() ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบตารางสอบนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async remove(id: string) {
    const row = await this.db.queryOne(`delete from exam_session where id = $1 returning id`, [id]);
    if (!row) throw new NotFoundException('ไม่พบตารางสอบนี้ หรือไม่มีสิทธิ์ลบ');
    return { removed: id };
  }

  async addProctor(id: string, dto: AddProctorDto) {
    const session = await this.loadSession(id);
    const conflicts = await this.conflicts(
      session.class_section_id, session.exam_date, session.period_from, session.period_to,
      null, [dto.staffId], id,
    );
    this.rejectIfConflicts(conflicts);

    return this.db.queryOne(
      `insert into exam_proctor (exam_session_id, staff_id) values ($1, $2)
       returning id, exam_session_id, staff_id`,
      [id, dto.staffId],
    );
  }

  async removeProctor(id: string, staffId: string) {
    const row = await this.db.queryOne(
      `delete from exam_proctor where exam_session_id = $1 and staff_id = $2 returning id`,
      [id, staffId],
    );
    if (!row) throw new NotFoundException('ไม่พบกรรมการคุมสอบรายนี้ในตารางสอบนี้');
    return { removed: true };
  }
}

@Controller('exam-schedule')
class ExamScheduleController {
  constructor(private readonly svc: ExamScheduleService) {}

  @Roles('registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin', 'teacher', 'student', 'guardian')
  @Get()
  list(@Query('termId') termId?: string, @Query('classSectionId') classSectionId?: string) {
    return this.svc.list(termId, classSectionId);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('exam_session')
  @Post()
  create(@Body() dto: CreateExamSessionDto) {
    return this.svc.create(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('exam_session', 'id')
  @Post(':id')
  update(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateExamSessionDto) {
    return this.svc.update(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('exam_session', 'id')
  @Delete(':id')
  remove(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.remove(id);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('exam_proctor', 'id')
  @Post(':id/proctors')
  addProctor(@Param('id', ParseUuidPipe) id: string, @Body() dto: AddProctorDto) {
    return this.svc.addProctor(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('exam_proctor', 'id')
  @Delete(':id/proctors/:staffId')
  removeProctor(@Param('id', ParseUuidPipe) id: string, @Param('staffId', ParseUuidPipe) staffId: string) {
    return this.svc.removeProctor(id, staffId);
  }
}

@Module({
  controllers: [ExamScheduleController],
  providers: [ExamScheduleService],
})
export class ExamScheduleModule {}

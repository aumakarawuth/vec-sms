import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsBoolean,
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
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * งานวิชาการรายปี — รอบสอบซ่อม/เรียนปรับเกรด และการเลื่อนชั้นปีการศึกษา
 *
 * ─── ทั้งสองเรื่องมีรูปแบบเดียวกัน ───
 * เป็นงานที่ทำกับคนทั้งวิทยาลัยพร้อมกัน และมีคนส่วนหนึ่งที่ทำไม่ได้เสมอ
 * (ไม่มีสิทธิ์สอบซ่อม · จบไปแล้ว · เรียนเกินเวลาหลักสูตร) ฟังก์ชันใน
 * ฐานข้อมูลจึงคืนผลรายคนแทนการ raise และชั้นนี้แค่สรุปยอดให้หน้าจอ
 *
 * ถ้า raise เมื่อเจอคนแรกที่ทำไม่ได้ ทั้ง transaction จะ rollback แล้ว
 * งานของคนที่เหลือหายไปด้วย — งานทะเบียนจะติดตายทั้งวิทยาลัยเพราะคนคนเดียว
 */

class CreateRegradeSessionDto {
  @IsUuid() termId: string;
  @IsString() code: string;
  @IsString() nameTh: string;
  @IsIn(['retest', 'restudy'], { message: 'kind ต้องเป็น retest (สอบซ่อม) หรือ restudy (เรียนปรับเกรด)' })
  kind: 'retest' | 'restudy';
  @IsOptional() @IsIn(['PVC', 'PVS', 'TVB']) level?: string;
  @IsISO8601() opensOn: string;
  @IsISO8601() closesOn: string;
  @IsOptional() @IsString() note?: string;
}

class AddRegradeCourseDto {
  @IsUuid() courseId: string;
  @IsOptional() @IsNumber() @Min(0) feeAmount?: number;
  @IsOptional() @IsInt() @Min(1) capacity?: number;
}

class RegisterRegradeDto {
  // เพดานเดียวกับ /registration/register-bulk ด้วยเหตุผลเดียวกัน —
  // คำขอที่ใหญ่กว่านี้จะล็อกตารางค้างไว้จนคนอื่นทำงานไม่ได้
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsUuidArray() studentIds: string[];
}

class RegradeResultDto {
  @IsUuid() toGradeSymbolId: string;
  @IsString() reason: string;
  @IsOptional() @IsString() documentNo?: string;
}

class RolloverDto {
  @IsInt() @Min(2500) @Max(2700) fromYearBe: number;
  @IsInt() @Min(2500) @Max(2700) toYearBe: number;
}

class RolloverGradebookDto {
  @IsUuid() fromTermId: string;
  @IsUuid() toTermId: string;
}

/**
 * จัดชั้นปีและห้องประจำเป็นกลุ่ม
 *
 * เพดานสูงกว่างานอื่น (500) เพราะจัดห้องทำทีละชั้นปีทั้งชั้น ไม่ใช่ทีละห้อง
 * และไม่ได้แตะตารางที่มีการแข่งขันสูงแบบ enrollment
 */
class PlaceStudentsDto {
  @IsUuid() academicYearId: string;
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(500) @IsUuidArray() studentIds: string[];
  @IsInt() @Min(1) @Max(6) studyYear: number;
  @IsOptional() @IsString() groupCode?: string;
}

/** เรียงเลขที่ใหม่ภายในห้องเดียว โดยใช้รหัสนักศึกษาเป็นลำดับที่ตรวจสอบย้อนกลับได้ */
class RenumberClassNumbersDto {
  @IsUuid() academicYearId: string;
  @IsInt() @Min(1) @Max(6) studyYear: number;
  @IsString() @MaxLength(40) groupCode: string;
}

/** ห้องประจำชั้น ไม่ใช่ห้องกายภาพ (`room`) ที่ใช้จัดตารางสอน */
class CreateClassGroupDto {
  @IsUuid() academicYearId: string;
  @IsIn(['PVC', 'PVS', 'TVB']) level: string;
  @IsInt() @Min(1) @Max(6) studyYear: number;
  @IsString() @MaxLength(40) code: string;
  @IsOptional() @IsString() @MaxLength(80) cohort?: string;
  @IsOptional() @IsString() @MaxLength(120) financeGroupTh?: string;
  @IsOptional() @IsArray() @ArrayMaxSize(8) @IsUuidArray() advisorStaffIds?: string[];
}

class UpdateClassGroupDto {
  @IsIn(['PVC', 'PVS', 'TVB']) level: string;
  @IsInt() @Min(1) @Max(6) studyYear: number;
  @IsString() @MaxLength(40) code: string;
  @IsOptional() @IsString() @MaxLength(80) cohort?: string;
  @IsOptional() @IsString() @MaxLength(120) financeGroupTh?: string;
}

@Injectable()
export class RegradeService {
  constructor(private readonly db: DbService) {}

  async createSession(dto: CreateRegradeSessionDto) {
    return this.db.queryOne(
      `insert into regrade_session
         (institution_id, term_id, code, name_th, kind, level, opens_on, closes_on, note)
       values (current_institution_id(), $1, $2, $3, $4::regrade_kind,
               $5::qualification_level, $6, $7, $8)
       returning id, code, name_th, kind, opens_on, closes_on, status`,
      [dto.termId, dto.code, dto.nameTh, dto.kind, dto.level ?? null,
       dto.opensOn, dto.closesOn, dto.note ?? null],
    );
  }

  async listSessions(termId?: string) {
    return this.db.query(
      `select rs.id, rs.code, rs.name_th, rs.kind, rs.level,
              rs.opens_on, rs.closes_on, rs.status,
              count(distinct rsc.id)::integer as courses,
              count(rc.id)::integer            as candidates
         from regrade_session rs
         left join regrade_session_course rsc on rsc.session_id = rs.id
         left join regrade_candidate rc       on rc.session_course_id = rsc.id
        where ($1::uuid is null or rs.term_id = $1)
        group by rs.id
        order by rs.opens_on desc`,
      [termId ?? null],
    );
  }

  /** เปิดรับ — แยกจากการสร้างเพราะต้องผูกรายวิชาให้ครบก่อนจึงเปิด */
  async setStatus(sessionId: string, status: 'draft' | 'open' | 'closed') {
    return this.db.queryOne(
      `update regrade_session set status = $2::regrade_status
        where id = $1
        returning id, code, status`,
      [sessionId, status],
    );
  }

  async addCourse(sessionId: string, dto: AddRegradeCourseDto) {
    return this.db.queryOne(
      `insert into regrade_session_course (session_id, course_id, fee_amount, capacity)
       values ($1, $2, coalesce($3, 0), $4)
       returning id, course_id, fee_amount, capacity`,
      [sessionId, dto.courseId, dto.feeAmount ?? null, dto.capacity ?? null],
    );
  }

  async listCourses(sessionId: string) {
    return this.db.query(
      `select rsc.id, c.code as course_code, c.name_th as course_name, c.credits,
              rsc.fee_amount, rsc.capacity,
              count(rc.id) filter (where rc.status <> 'withdrawn')::integer as registered
         from regrade_session_course rsc
         join course c on c.id = rsc.course_id
         left join regrade_candidate rc on rc.session_course_id = rsc.id
        where rsc.session_id = $1
        group by rsc.id, c.code, c.name_th, c.credits
        order by c.code`,
      [sessionId],
    );
  }

  /** รายชื่อผู้มีสิทธิ์ — คำนวณจากผลการเรียนจริง ไม่ใช่รายชื่อที่เก็บไว้ */
  async eligible(sessionCourseId: string) {
    return this.db.query(
      `select student_id, student_code, full_name, grade_symbol, term_label
         from regrade_eligible($1)`,
      [sessionCourseId],
    );
  }

  async register(sessionCourseId: string, dto: RegisterRegradeDto) {
    const rows = await this.db.query<{
      student_id: string; registered: boolean; reason: string | null;
    }>(
      `select student_id, registered, reason from register_regrade($1, $2::uuid[])`,
      [sessionCourseId, dto.studentIds],
    );

    return {
      requested: dto.studentIds.length,
      succeeded: rows.filter((r) => r.registered).length,
      rejected: rows.filter((r) => !r.registered).length,
      results: rows.map((r) => ({
        studentId: r.student_id,
        registered: r.registered,
        reason: r.reason,
      })),
    };
  }

  async listCandidates(sessionCourseId: string) {
    return this.db.query(
      `select rc.id, s.student_code,
              trim(coalesce(p.prefix_th,'') || coalesce(p.first_name_th,'')
                   || ' ' || coalesce(p.last_name_th,'')) as full_name,
              rc.status, rc.change_request_id, rc.registered_at
         from regrade_candidate rc
         join student s on s.id = rc.student_id
         join person  p on p.id = s.person_id
        where rc.session_course_id = $1
        order by s.student_code`,
      [sessionCourseId],
    );
  }

  /**
   * บันทึกผล — ได้คำร้องแก้เกรดกลับมา ไม่ใช่เกรดที่เปลี่ยนแล้ว
   *
   * เกรดจริงเปลี่ยนเมื่อคำร้องผ่านการอนุมัติสองชั้นผ่าน /gradebook/change-requests
   * ตามทางเดิม รอบสอบซ่อมไม่มีอภิสิทธิ์ข้ามขั้นตอนนั้น
   */
  async recordResult(candidateId: string, dto: RegradeResultDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `select record_regrade_result($1, $2, $3, $4) as id`,
      [candidateId, dto.toGradeSymbolId, dto.reason, dto.documentNo ?? null],
    );
    return {
      changeRequestId: row!.id,
      note: 'ยื่นคำร้องแก้เกรดแล้ว เกรดจะเปลี่ยนเมื่อผ่านการอนุมัติสองชั้น',
    };
  }
}

class TimeslotCheckDto {
  @IsUuid() classSectionId: string;
  @IsInt() @Min(1) @Max(7) dayOfWeek: number;
  @IsInt() @Min(1) @Max(20) periodFrom: number;
  @IsInt() @Min(1) @Max(20) periodTo: number;
  @IsOptional() @IsUuid() roomId?: string;
}

class AddTimeslotDto extends TimeslotCheckDto {}

class MoveTimeslotDto {
  @IsInt() @Min(1) @Max(7) dayOfWeek: number;
  @IsInt() @Min(1) @Max(20) periodFrom: number;
  @IsInt() @Min(1) @Max(20) periodTo: number;
  @IsOptional() @IsUuid() roomId?: string;
}

class AvailabilityDto {
  @IsUuid() staffId: string;
  @IsInt() @Min(1) @Max(7) dayOfWeek: number;
  @IsInt() @Min(1) @Max(20) periodFrom: number;
  @IsInt() @Min(1) @Max(20) periodTo: number;

  /**
   * unavailable = ห้ามวางจริง ๆ · prefer_not = เลี่ยงถ้าได้
   *
   * ค่าเริ่มต้นเป็น unavailable เพราะคนกรอกส่วนใหญ่กรอกเรื่องที่ติดจริง
   * ส่วนคำขอเชิงความสะดวกต้องตั้งใจเลือกเอง — ถ้าสลับกัน ข้อจำกัดที่ห้าม
   * จริงจะถูกบันทึกเป็นแค่คำขอโดยไม่มีใครสังเกต
   */
  @IsOptional() @IsIn(['unavailable', 'prefer_not']) kind?: string;
  @IsOptional() @IsString() @MaxLength(200) reason?: string;
  @IsOptional() @IsUuid() termId?: string;
}

class CreateRoomDto {
  @IsString() @MaxLength(40) code: string;
  @IsString() @MaxLength(200) nameTh: string;
  @IsOptional()
  @IsIn(['classroom', 'workshop', 'lab', 'computer', 'auditorium', 'outdoor'])
  kind?: string;
  @IsOptional() @IsInt() @Min(1) @Max(500) capacity?: number;
  @IsOptional() @IsString() @MaxLength(100) building?: string;
}

@Injectable()
export class TimetableService {
  constructor(private readonly db: DbService) {}

  async createRoom(dto: CreateRoomDto) {
    return this.db.queryOne(
      `insert into room (institution_id, code, name_th, kind, capacity, building)
       values (current_institution_id(), $1, $2, coalesce($3, 'classroom')::room_kind, $4, $5)
       returning id, code, name_th, kind, capacity, building`,
      [dto.code, dto.nameTh, dto.kind ?? null, dto.capacity ?? null, dto.building ?? null],
    );
  }

  async rooms() {
    return this.db.query(
      `select id, code, name_th, kind, capacity, building, active
         from room where active order by code`,
    );
  }

  /** คืนรายการปัญหาทั้งหมด ไม่ใช่ true/false — หน้าจอบอกได้ว่าชนกับอะไร */
  async check(dto: TimeslotCheckDto) {
    const rows = await this.db.query<{ kind: string; message_th: string }>(
      `select kind, message_th, other_section_id
         from timeslot_conflicts($1, $2::smallint, $3::smallint, $4::smallint, $5)`,
      [dto.classSectionId, dto.dayOfWeek, dto.periodFrom, dto.periodTo, dto.roomId ?? null],
    );
    return { canPlace: rows.length === 0, conflicts: rows };
  }

  /**
   * คาบว่างที่วางได้จริง
   *
   * `avoids` บอกว่าคาบนั้นตรงกับที่ครูขอเลี่ยงไว้ (แต่ไม่ได้ห้าม) และ `note`
   * คือเหตุผลที่ครูแจ้ง — หน้าจอต้องแสดงให้คนจัดเห็น มิฉะนั้นเขาจะเลือกคาบ
   * ท้ายรายการโดยไม่รู้ว่ากำลังฝืนคำขอของใครอยู่
   *
   * ส่วนช่วงที่ครูสอนไม่ได้จริง ๆ ถูกตัดออกตั้งแต่ในฐานข้อมูลแล้ว
   */
  async suggest(classSectionId: string, periods: number, roomId?: string, termId?: string) {
    return this.db.query(
      `select day_of_week, period_from, period_to, avoids, note
         from suggest_timeslots($1, $2::smallint, $3, 20, $4)`,
      [classSectionId, periods, roomId ?? null, termId ?? null],
    );
  }

  /** ข้อจำกัดเวลาสอนของครูคนหนึ่ง */
  async availability(staffId: string) {
    return this.db.query(
      `select ta.id, ta.day_of_week, ta.period_from, ta.period_to,
              ta.kind, ta.reason, ta.term_id, t.ordinal as term_ordinal
         from teacher_availability ta
         left join term t on t.id = ta.term_id
        where ta.staff_id = $1
        order by ta.day_of_week, ta.period_from`,
      [staffId],
    );
  }

  async addAvailability(dto: {
    staffId: string;
    dayOfWeek: number;
    periodFrom: number;
    periodTo: number;
    kind?: string;
    reason?: string;
    termId?: string;
  }) {
    return this.db.queryOne(
      `insert into teacher_availability
         (institution_id, staff_id, term_id, day_of_week, period_from, period_to,
          kind, reason, created_by)
       values (current_institution_id(), $1, $2, $3::smallint, $4::smallint, $5::smallint,
               coalesce($6, 'unavailable')::availability_kind, $7, current_actor_id())
       returning id, day_of_week, period_from, period_to, kind`,
      [
        dto.staffId, dto.termId ?? null, dto.dayOfWeek,
        dto.periodFrom, dto.periodTo, dto.kind ?? null, dto.reason ?? null,
      ],
    );
  }

  async removeAvailability(id: string) {
    const r = await this.db.query(
      `delete from teacher_availability where id = $1 returning id`,
      [id],
    );
    if (r.length === 0) {
      throw new ForbiddenException('ไม่พบข้อจำกัดนี้ หรือไม่มีสิทธิ์ลบ');
    }
    return { removed: id };
  }

  /**
   * วางคาบเอง — ตรวจก่อนเขียนเสมอ
   *
   * ฐานข้อมูลมี exclusion constraint กันการทับซ้อนของกลุ่มเรียนเดียวกันอยู่แล้ว
   * แต่การชนของครู ห้อง และกลุ่มนักศึกษาไม่มี constraint ตายตัวได้ เพราะ
   * บางครั้งวิทยาลัยจงใจวางชนแล้วแก้ทีหลัง — จึงตรวจแล้วปฏิเสธที่ชั้นนี้
   * พร้อมบอกว่าชนกับอะไร
   */
  async addSlot(dto: AddTimeslotDto) {
    const conflicts = await this.check(dto);
    if (!conflicts.canPlace) {
      throw new BadRequestException({
        message: 'วางคาบนี้ไม่ได้ เพราะชนกับรายการต่อไปนี้',
        conflicts: conflicts.conflicts.map((c) => c.message_th),
      });
    }
    return this.db.queryOne(
      `insert into section_timeslot
         (class_section_id, day_of_week, period_from, period_to, room_id)
       values ($1, $2::smallint, $3::smallint, $4::smallint, $5)
       returning id, day_of_week, period_from, period_to, room_id`,
      [dto.classSectionId, dto.dayOfWeek, dto.periodFrom, dto.periodTo, dto.roomId ?? null],
    );
  }

  /** ยกเลิกคาบที่วางไว้ — ไม่วางคาบใหม่แทน (ใช้ตอนย้ายไปสอนออนไลน์ หรือยกเลิกจริง ๆ) */
  async removeSlot(id: string) {
    const r = await this.db.query(
      `delete from section_timeslot where id = $1 returning id`,
      [id],
    );
    if (r.length === 0) {
      throw new NotFoundException('ไม่พบคาบนี้ หรือไม่มีสิทธิ์ลบ');
    }
    return { removed: id };
  }

  /**
   * ย้ายคาบที่วางไว้แล้วไปวัน/เวลา/ห้องใหม่
   *
   * ลบคาบเดิมก่อนแล้วค่อยตรวจการชนของคาบใหม่ ภายในทรานแซกชันเดียว —
   * ถ้าตรวจก่อนลบ คาบเดิมของกลุ่มเรียนตัวเองจะโดนนับเป็นคาบที่ชนกันเอง
   * (timeslot_conflicts นับคาบของกลุ่มเรียนตัวเองด้วยโดยตั้งใจ ดู kind='self')
   * ทั้งที่กำลังจะย้ายออกจากคาบนั้นพอดี ถ้าชนคาบใหม่จริงจะ rollback
   * กลับไปมีคาบเดิมอยู่เหมือนไม่มีอะไรเกิดขึ้น
   */
  async moveSlot(id: string, dto: MoveTimeslotDto) {
    return this.db.tx(async (c) => {
      const old = await c.query<{ class_section_id: string }>(
        `delete from section_timeslot where id = $1 returning class_section_id`,
        [id],
      );
      if (old.rows.length === 0) {
        throw new NotFoundException('ไม่พบคาบนี้ หรือไม่มีสิทธิ์ย้าย');
      }
      const sectionId = old.rows[0].class_section_id;

      const conflicts = await c.query<{ kind: string; message_th: string }>(
        `select kind, message_th
           from timeslot_conflicts($1, $2::smallint, $3::smallint, $4::smallint, $5)`,
        [sectionId, dto.dayOfWeek, dto.periodFrom, dto.periodTo, dto.roomId ?? null],
      );
      if (conflicts.rows.length > 0) {
        throw new BadRequestException({
          message: 'ย้ายคาบนี้ไม่ได้ เพราะชนกับรายการต่อไปนี้',
          conflicts: conflicts.rows.map((row) => row.message_th),
        });
      }

      const inserted = await c.query(
        `insert into section_timeslot
           (class_section_id, day_of_week, period_from, period_to, room_id)
         values ($1, $2::smallint, $3::smallint, $4::smallint, $5)
         returning id, day_of_week, period_from, period_to, room_id`,
        [sectionId, dto.dayOfWeek, dto.periodFrom, dto.periodTo, dto.roomId ?? null],
      );
      return inserted.rows[0];
    });
  }

  /**
   * จัดตารางทั้งภาคเรียนอัตโนมัติ
   *
   * คืนรายการวิชาที่วางไม่ครบออกมาด้วย เพราะนั่นคืองานที่เหลือให้คนทำต่อ
   * ตัวจัดที่ยัดลงไปให้ครบแล้วเงียบจะสร้างตารางที่ใช้จริงไม่ได้
   */
  async autoSchedule(termId: string) {
    const rows = await this.db.query<{
      class_section_id: string; label: string; action: string;
      periods_placed: number; note: string | null;
    }>(
      `select class_section_id, label, action, periods_placed, note
         from auto_schedule_term($1)`,
      [termId],
    );

    const by = (a: string) => rows.filter((r) => r.action === a).length;
    return {
      sections: rows.length,
      scheduled: by('scheduled'),
      alreadyFull: by('already_full'),
      partial: by('partial'),
      skipped: by('skipped'),
      periodsPlaced: rows.reduce((n, r) => n + Number(r.periods_placed), 0),
      needsAttention: rows
        .filter((r) => r.note)
        .map((r) => ({ section: r.label, action: r.action, note: r.note })),
    };
  }

  async conflicts(termId: string) {
    const rows = await this.db.query(
      `select class_section_id, label, day_of_week, period_from, period_to,
              kind, message_th
         from timetable_conflicts($1)`,
      [termId],
    );
    return { total: rows.length, conflicts: rows };
  }

  /**
   * ภาระสอนรายบุคคลของหนึ่งภาคเรียน
   *
   * `planned_periods` เป็นจำนวนคาบทั้งภาคและเคยถูกหน้าจอนำไปแสดงเป็น
   * "คาบ/สัปดาห์" ซึ่งผิดหน่วย ที่นี่จึงนับคาบต่อสัปดาห์จาก
   * section_timeslot โดยตรง และแยกยอดทั้งภาคไว้อีกคอลัมน์หนึ่ง
   * ครูที่ยังไม่ได้รับกลุ่มเรียนก็ต้องปรากฏ เพื่อให้ฝ่ายวิชาการเห็นคนที่
   * ภาระเป็นศูนย์ ไม่ใช่เห็นเฉพาะคนที่ถูกมอบหมายแล้วเท่านั้น
   */
  async workload(termId: string) {
    return this.db.query(
      `with section_load as (
         select cs.id, cs.teacher_id, cs.course_id, cs.planned_periods,
                (select count(*) from enrollment e
                  where e.class_section_id = cs.id and e.status = 'enrolled') as enrolled,
                (select coalesce(sum(st.period_to - st.period_from + 1), 0)
                   from section_timeslot st where st.class_section_id = cs.id) as weekly_periods
           from class_section cs
          where cs.term_id = $1
       ), teacher_load as (
         select teacher_id,
                count(*) as section_count,
                count(distinct course_id) as course_count,
                sum(planned_periods) as planned_periods,
                sum(enrolled) as students,
                sum(weekly_periods) as weekly_periods,
                count(*) filter (where weekly_periods = 0) as unscheduled_sections
           from section_load
          where teacher_id is not null
          group by teacher_id
       )
       select s.id as staff_id, s.staff_code,
              trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '') || ' ' ||
                   coalesce(p.last_name_th, '')) as teacher_name,
              d.name_th as department_name, sa.position_th,
              coalesce(tl.section_count, 0) as section_count,
              coalesce(tl.course_count, 0) as course_count,
              coalesce(tl.weekly_periods, 0) as weekly_periods,
              coalesce(tl.planned_periods, 0) as planned_periods,
              coalesce(tl.students, 0) as students,
              coalesce(tl.unscheduled_sections, 0) as unscheduled_sections
         from staff s
         join person p on p.id = s.person_id
         join term t on t.id = $1
         left join teacher_load tl on tl.teacher_id = s.id
         left join lateral (
           select a.department_id, a.position_th
             from staff_assignment a
            where a.staff_id = s.id and a.is_primary
              and a.effective_from <= t.starts_on
              and (a.effective_to is null or a.effective_to >= t.starts_on)
            order by a.effective_from desc limit 1
         ) sa on true
         left join department d on d.id = sa.department_id
        where s.active and s.is_teacher
        order by coalesce(tl.weekly_periods, 0) desc, s.staff_code`,
      [termId],
    );
  }
}

@Injectable()
export class RolloverService {
  constructor(private readonly db: DbService) {}

  /**
   * เลื่อนชั้นปีนักศึกษา แล้วบันทึกผลไว้ใน rollover_log
   *
   * ทำในทรานแซกชันเดียวกันเพื่อให้บันทึกกับผลตรงกันเสมอ — ถ้าแยกกัน
   * จะมีกรณีที่เลื่อนชั้นสำเร็จแต่ไม่มีบันทึกว่าใครกด ซึ่งเป็นคำถามแรก
   * ที่ถูกถามเวลามีคนทักว่าข้อมูลผิด
   */
  async students(dto: RolloverDto) {
    return this.db.tx(async (c) => {
      const rows = (
        await c.query<{
          student_id: string; action: string; study_year: number; note: string | null;
        }>(
          `select student_id, action, study_year, note
             from rollover_students($1::smallint, $2::smallint)`,
          [dto.fromYearBe, dto.toYearBe],
        )
      ).rows;

      const summary = rows.reduce<Record<string, number>>((acc, r) => {
        acc[r.action] = (acc[r.action] ?? 0) + 1;
        return acc;
      }, {});

      await c.query(
        `insert into rollover_log
           (institution_id, from_year_be, to_year_be, summary, ran_by)
         values (current_institution_id(), $1, $2, $3::jsonb, current_actor_id())`,
        [dto.fromYearBe, dto.toYearBe, JSON.stringify(summary)],
      );

      return {
        fromYearBe: dto.fromYearBe,
        toYearBe: dto.toYearBe,
        total: rows.length,
        summary,
        // คืนเฉพาะคนที่ไม่ถูกเลื่อน เพราะนั่นคือรายการที่ต้องมีคนไปตัดสินใจต่อ
        needsAttention: rows
          .filter((r) => r.action !== 'promoted')
          .map((r) => ({ studentId: r.student_id, action: r.action, note: r.note })),
      };
    });
  }

  async feeSchedules(dto: RolloverDto) {
    const row = await this.db.queryOne<{ n: number }>(
      `select rollover_fee_schedules($1::smallint, $2::smallint) as n`,
      [dto.fromYearBe, dto.toYearBe],
    );
    return {
      linesCopied: Number(row?.n ?? 0),
      active: false,
      note: 'คัดลอกแล้วแต่ยังไม่เปิดใช้ — งานการเงินต้องตรวจตัวเลขและเปิดใช้เอง',
    };
  }

  async history() {
    return this.db.query(
      `select id, from_year_be, to_year_be, summary, ran_at
         from rollover_log order by ran_at desc limit 50`,
    );
  }

  /**
   * คัดลอกโครงสร้างสมุดคะแนนข้ามภาคเรียน
   *
   * คืนรายการห้องที่จับคู่ไม่ได้ออกมาด้วย เพราะนั่นคืองานที่ครูต้องไปตั้งเอง
   * ถ้าไม่บอก จะมีห้องที่ไม่มีสมุดคะแนนอยู่เงียบ ๆ จนถึงวันตัดเกรด
   */
  async gradebooks(dto: RolloverGradebookDto) {
    const rows = await this.db.query<{
      to_section_id: string; from_section_id: string | null;
      section_label: string; items_copied: number; note: string | null;
    }>(
      `select to_section_id, from_section_id, section_label, items_copied, note
         from rollover_gradebook_templates($1, $2)`,
      [dto.fromTermId, dto.toTermId],
    );

    return {
      sections: rows.length,
      copied: rows.filter((r) => Number(r.items_copied) > 0).length,
      itemsCopied: rows.reduce((n, r) => n + Number(r.items_copied), 0),
      needsAttention: rows
        .filter((r) => r.note)
        .map((r) => ({ section: r.section_label, note: r.note })),
    };
  }

  async placeStudents(dto: PlaceStudentsDto) {
    const rows = await this.db.query<{
      student_id: string; action: string; note: string | null;
    }>(
      `select student_id, action, note
         from place_students($1, $2::uuid[], $3::smallint, $4)`,
      [dto.academicYearId, dto.studentIds, dto.studyYear, dto.groupCode ?? null],
    );

    return {
      requested: dto.studentIds.length,
      placed: rows.filter((r) => r.action === 'placed').length,
      skipped: rows
        .filter((r) => r.action !== 'placed')
        .map((r) => ({ studentId: r.student_id, action: r.action, note: r.note })),
    };
  }

  async placements(academicYearId: string) {
    return this.db.query(
      `select scp.study_year, scp.group_code, s.student_code, s.class_number,
              trim(coalesce(p.prefix_th,'') || coalesce(p.first_name_th,'')
                   || ' ' || coalesce(p.last_name_th,'')) as full_name
         from student_class_placement scp
         join student s on s.id = scp.student_id
         join person  p on p.id = s.person_id
        where scp.academic_year_id = $1
        order by scp.study_year, scp.group_code nulls last, s.student_code`,
      [academicYearId],
    );
  }

  async renumberClassNumbers(dto: RenumberClassNumbersDto) {
    return this.db.tx(async (c) => {
      const total = (await c.query<{ count: string }>(
        `select count(*)::text as count from student_class_placement
          where academic_year_id = $1 and study_year = $2 and group_code = $3`,
        [dto.academicYearId, dto.studyYear, dto.groupCode],
      )).rows[0];
      const count = Number(total?.count ?? 0);
      if (count === 0) throw new BadRequestException('ไม่พบนักศึกษาในห้องที่เลือก');
      if (count > 99) throw new BadRequestException('ห้องนี้มีมากกว่า 99 คน จึงกำหนดเลขที่ตามรูปแบบระบบไม่ได้');
      await c.query(
        `with numbered as (
           select scp.student_id, row_number() over (order by s.student_code)::smallint as class_number
             from student_class_placement scp
             join student s on s.id = scp.student_id
            where scp.academic_year_id = $1 and scp.study_year = $2 and scp.group_code = $3
         )
         update student s set class_number = n.class_number
           from numbered n where n.student_id = s.id`,
        [dto.academicYearId, dto.studyYear, dto.groupCode],
      );
      return { renumbered: count, order: 'student_code' };
    });
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('regrade')
class RegradeController {
  constructor(private readonly svc: RegradeService) {}

  @Get('sessions')
  listSessions(@Query('termId') termId?: string) {
    return this.svc.listSessions(termId);
  }

  @Audit('regrade_session')
  @Post('sessions')
  createSession(@Body() dto: CreateRegradeSessionDto) {
    return this.svc.createSession(dto);
  }

  @Audit('regrade_session', 'id')
  @Post('sessions/:id/open')
  open(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.setStatus(id, 'open');
  }

  @Audit('regrade_session', 'id')
  @Post('sessions/:id/close')
  close(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.setStatus(id, 'closed');
  }

  @Get('sessions/:id/courses')
  listCourses(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.listCourses(id);
  }

  @Audit('regrade_session_course', 'id')
  @Post('sessions/:id/courses')
  addCourse(@Param('id', ParseUuidPipe) id: string, @Body() dto: AddRegradeCourseDto) {
    return this.svc.addCourse(id, dto);
  }

  @Get('courses/:id/eligible')
  eligible(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.eligible(id);
  }

  @Get('courses/:id/candidates')
  candidates(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.listCandidates(id);
  }

  @Audit('regrade_candidate', 'id')
  @Post('courses/:id/register')
  register(@Param('id', ParseUuidPipe) id: string, @Body() dto: RegisterRegradeDto) {
    return this.svc.register(id, dto);
  }

  @Audit('regrade_candidate', 'id')
  @Post('candidates/:id/result')
  result(@Param('id', ParseUuidPipe) id: string, @Body() dto: RegradeResultDto) {
    return this.svc.recordResult(id, dto);
  }
}

/**
 * การเลื่อนชั้นปีกระทบทุกคนในวิทยาลัยและย้อนกลับยาก จึงจำกัดไว้ที่
 * งานทะเบียนกับผู้บริหารเท่านั้น ไม่เปิดให้บทบาท academic ทั่วไป
 */
@Roles('registrar', 'director', 'admin')
@Controller('rollover')
class RolloverController {
  constructor(private readonly svc: RolloverService) {}

  @Get()
  history() {
    return this.svc.history();
  }

  @Audit('student_class_placement')
  @Post('students')
  students(@Body() dto: RolloverDto) {
    return this.svc.students(dto);
  }

  @Audit('fee_schedule')
  @Post('fee-schedules')
  feeSchedules(@Body() dto: RolloverDto) {
    return this.svc.feeSchedules(dto);
  }

  @Audit('gradebook_item')
  @Post('gradebooks')
  gradebooks(@Body() dto: RolloverGradebookDto) {
    return this.svc.gradebooks(dto);
  }

  @Get('placements')
  placements(@Query('academicYearId', ParseUuidPipe) academicYearId: string) {
    return this.svc.placements(academicYearId);
  }

  /**
   * จัดชั้นปี/ห้องประจำ — เปิดให้ academic ด้วย ต่างจากการเลื่อนชั้นปี
   * เพราะจัดห้องผิดแก้ได้ทันทีด้วยการจัดใหม่ ไม่เหมือนการเลื่อนชั้นที่
   * สร้างข้อมูลของปีการศึกษาใหม่ทั้งชุด
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('student_class_placement')
  @Post('placements')
  place(@Body() dto: PlaceStudentsDto) {
    return this.svc.placeStudents(dto);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('student_class_placement')
  @Post('placements/renumber')
  renumber(@Body() dto: RenumberClassNumbersDto) {
    return this.svc.renumberClassNumbers(dto);
  }
}

@Injectable()
class ClassGroupService {
  constructor(private readonly db: DbService) {}

  async list(academicYearId?: string) {
    return this.db.query(
      `select cg.id, cg.academic_year_id, cg.level, cg.study_year, cg.code, cg.cohort, cg.finance_group_th,
              count(distinct scp.student_id)::int as students,
              coalesce(json_agg(json_build_object('id', st.id, 'nameTh', trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '') || ' ' || coalesce(p.last_name_th, ''))) order by st.staff_code) filter (where st.id is not null), '[]') as advisors
         from class_group cg
         left join class_group_advisor cga on cga.class_group_id = cg.id
         left join staff st on st.id = cga.staff_id
         left join person p on p.id = st.person_id
         left join student_class_placement scp on scp.academic_year_id = cg.academic_year_id and scp.study_year = cg.study_year and scp.group_code = cg.code
        where cg.active and ($1::uuid is null or cg.academic_year_id = $1)
        group by cg.id
        order by cg.level, cg.study_year, cg.code`,
      [academicYearId ?? null],
    );
  }

  async create(dto: CreateClassGroupDto) {
    return this.db.tx(async (c) => {
      const group = await c.query<{ id: string }>(
        `insert into class_group (institution_id, academic_year_id, level, study_year, code, cohort, finance_group_th)
         values (current_institution_id(), $1, $2::qualification_level, $3, $4, $5, $6)
         returning id`,
        [dto.academicYearId, dto.level, dto.studyYear, dto.code.trim(), dto.cohort?.trim() ?? null, dto.financeGroupTh?.trim() ?? null],
      );
      for (const staffId of [...new Set(dto.advisorStaffIds ?? [])]) {
        await c.query('insert into class_group_advisor (class_group_id, staff_id) values ($1, $2)', [group.rows[0].id, staffId]);
      }
      return { id: group.rows[0].id };
    });
  }

  async update(id: string, dto: UpdateClassGroupDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `update class_group set
         level = $2::qualification_level, study_year = $3, code = $4,
         cohort = $5, finance_group_th = $6
       where id = $1
       returning id`,
      [id, dto.level, dto.studyYear, dto.code.trim(), dto.cohort?.trim() ?? null, dto.financeGroupTh?.trim() ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบห้องประจำชั้นนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async remove(id: string) {
    const row = await this.db.queryOne<{ id: string }>(
      `update class_group set active = false where id = $1 returning id`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบห้องประจำชั้นนี้ หรือไม่มีสิทธิ์ลบ');
    return { deleted: true };
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('class-groups')
class ClassGroupController {
  constructor(private readonly svc: ClassGroupService) {}
  @Get() list(@Query('academicYearId') academicYearId?: string) { return this.svc.list(academicYearId); }
  @Audit('class_group') @Post() create(@Body() dto: CreateClassGroupDto) { return this.svc.create(dto); }
  @Audit('class_group', 'id') @Patch(':id') update(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateClassGroupDto) { return this.svc.update(id, dto); }
  @Audit('class_group', 'id') @Delete(':id') remove(@Param('id', ParseUuidPipe) id: string) { return this.svc.remove(id); }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('timetable')
class TimetableController {
  constructor(private readonly svc: TimetableService) {}

  @Get('rooms')
  rooms() {
    return this.svc.rooms();
  }

  @Post('check')
  check(@Body() dto: TimeslotCheckDto) {
    return this.svc.check(dto);
  }

  @Get('suggest')
  suggest(
    @Query('classSectionId', ParseUuidPipe) classSectionId: string,
    @Query('periods') periods?: string,
    @Query('roomId') roomId?: string,
    @Query('termId') termId?: string,
  ) {
    const n = Number(periods ?? 2);
    return this.svc.suggest(
      classSectionId,
      Number.isFinite(n) && n > 0 ? n : 2,
      roomId,
      termId,
    );
  }

  /**
   * ข้อจำกัดเวลาสอนของครู
   *
   * ครูอ่านของตัวเองได้ที่ชั้นฐานข้อมูล แต่เส้นทางนี้กั้นด้วย @Roles ของ
   * controller (งานทะเบียน/วิชาการ) โดยตั้งใจ — ถ้าครูกรอกเองได้ ตารางสอน
   * จะกลายเป็นเรื่องที่ต่อรองกันเอง และคนที่กรอกก่อนได้คาบที่ดีที่สุดเสมอ
   */
  @Get('availability')
  availability(@Query('staffId', ParseUuidPipe) staffId: string) {
    return this.svc.availability(staffId);
  }

  @Audit('teacher_availability')
  @Post('availability')
  addAvailability(@Body() dto: AvailabilityDto) {
    return this.svc.addAvailability(dto);
  }

  @Audit('teacher_availability')
  @Post('availability/:id/remove')
  removeAvailability(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.removeAvailability(id);
  }

  @Audit('section_timeslot')
  @Post('slots')
  addSlot(@Body() dto: AddTimeslotDto) {
    return this.svc.addSlot(dto);
  }

  @Audit('section_timeslot')
  @Post('slots/:id/remove')
  removeSlot(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.removeSlot(id);
  }

  @Audit('section_timeslot')
  @Post('slots/:id/move')
  moveSlot(@Param('id', ParseUuidPipe) id: string, @Body() dto: MoveTimeslotDto) {
    return this.svc.moveSlot(id, dto);
  }

  @Audit('section_timeslot')
  @Post('terms/:termId/auto-schedule')
  auto(@Param('termId', ParseUuidPipe) termId: string) {
    return this.svc.autoSchedule(termId);
  }

  @Get('terms/:termId/conflicts')
  conflicts(@Param('termId', ParseUuidPipe) termId: string) {
    return this.svc.conflicts(termId);
  }

  @Get('terms/:termId/workload')
  workload(@Param('termId', ParseUuidPipe) termId: string) {
    return this.svc.workload(termId);
  }

  /**
   * บันทึกห้องเรียน
   *
   * ห้องเป็นตารางจริงตั้งแต่ 0034 ไม่ใช่ข้อความอิสระ — แต่ไม่เคยมีเส้นทางไหน
   * สร้างห้องเลย วิทยาลัยที่เพิ่งเปิดจึงจัดตารางไม่ได้ เพราะไม่มีห้องให้เลือก
   * และการเทียบห้องด้วยสตริงคือสิ่งที่ 0034 ตั้งใจเลิกไปแล้ว
   */
  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('room')
  @Post('rooms')
  createRoom(@Body() dto: CreateRoomDto) {
    return this.svc.createRoom(dto);
  }
}

/* ═══════════════════════════════════════════════════════════════════
 * ปฏิทินการศึกษาและกลุ่มเรียน
 *
 * ─── ทำไมเพิ่งมามีตรงนี้ ───
 * ทั้งระบบเคยไม่มีเส้นทางไหนคืน "รายการภาคเรียน" หรือ "รายการกลุ่มเรียน"
 * เลยสักเส้น มีแต่เส้นทางที่**รับ** `termId`/`sectionId` เข้าไป และเส้นทางที่
 * คืนกลุ่มเรียนของครูตัวเองใน `GET /staff/:id` เท่านั้น
 *
 * ตราบใดที่ยังเป็นแบบนั้น หน้าจอของงานทะเบียนสร้างไม่ได้เลย เพราะไม่มีทาง
 * ให้เจ้าหน้าที่เลือกภาคเรียนหรือกลุ่มเรียนได้นอกจากพิมพ์ uuid เอง —
 * เรื่องนี้มองไม่เห็นตลอดมาเพราะเทสต์ทุกชุดรู้ uuid ที่ต้องใช้อยู่แล้ว
 * จาก seed และแอปนักศึกษารับค่ามาตอน build
 *
 * `POST /academic/sections` ปิดอีกช่องหนึ่ง — `insert into class_section`
 * เคยมีอยู่ที่เดียวคือในไฟล์เทสต์ของฐานข้อมูล แปลว่าวิทยาลัยที่เปิดใหม่
 * เปิดสอนวิชาแรกไม่ได้เลยถ้าไม่ยิง SQL ตรง
 * ═══════════════════════════════════════════════════════════════════ */

class CreateAcademicYearDto {
  @IsInt() @Min(2500) @Max(2700) yearBe: number;
  @IsISO8601() startsOn: string;
  @IsISO8601() endsOn: string;
}

class CreateTermDto {
  @IsInt() @Min(1) @Max(3) ordinal: number;
  @IsOptional() @IsIn(['regular', 'summer']) kind?: string;
  @IsISO8601() startsOn: string;
  @IsISO8601() endsOn: string;
  @IsOptional() @IsISO8601() addDropEndsOn?: string;
  @IsOptional() @IsISO8601() withdrawEndsOn?: string;
  @IsOptional() @IsISO8601() gradeDueOn?: string;
}

class TermStatusDto {
  @IsIn(['planning', 'registration', 'open', 'grading', 'closed'])
  status: string;
}

class TermCategoryDto {
  @IsString() @MaxLength(80) title: string;
  @IsOptional() @IsInt() sortOrder?: number;
}

/**
 * แก้ไขช่องวันที่ย่อยและข้อมูลจัดกลุ่มของภาคเรียนที่มีอยู่แล้ว — แยกจาก
 * CreateTermDto เพราะตอนสร้างภาคเรียนบังคับแค่ช่วงวันหลัก ส่วนช่องพวกนี้
 * มักตั้งทีหลังตอนวางแผนงานทะเบียนของภาคเรียนนั้นละเอียดขึ้น
 */
class UpdateTermDto {
  @IsOptional() @IsUuid() categoryId?: string | null;
  @IsOptional() @IsString() @MaxLength(40) shortName?: string;
  @IsOptional() @IsInt() sortOrder?: number;
  @IsOptional() @IsBoolean() isNormal?: boolean;
  @IsOptional() @IsISO8601() registrationStartsOn?: string;
  @IsOptional() @IsISO8601() gradebookStartsOn?: string;
  @IsOptional() @IsISO8601() paymentStartsOn?: string;
  @IsOptional() @IsISO8601() paymentEndsOn?: string;
  @IsOptional() @IsISO8601() auditStartsOn?: string;
  @IsOptional() @IsISO8601() auditEndsOn?: string;
}

// PostgreSQL คืนค่า time เป็น "HH:MM:SS" เสมอ แต่ <input type="time"> ส่งกลับ
// มาเป็น "HH:MM" — ต้องรับทั้งสองแบบ มิฉะนั้นแก้ไขแถวเดิมโดยไม่เปลี่ยนเวลา
// จะตกการตรวจสอบ เพราะค่าที่โหลดมาแสดงมีวินาทีติดมาด้วย
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/;

class PeriodDto {
  @IsInt() @Min(1) @Max(20) ordinal: number;
  @IsString() @MaxLength(40) title: string;
  @IsOptional() @IsString() @MaxLength(20) shortName?: string;
  @IsOptional() @Matches(TIME_PATTERN, { message: 'startsAt ต้องเป็นเวลารูปแบบ HH:MM' }) startsAt?: string;
  @IsOptional() @Matches(TIME_PATTERN, { message: 'endsAt ต้องเป็นเวลารูปแบบ HH:MM' }) endsAt?: string;
}

class GradeLevelDto {
  @IsIn(['PVC', 'PVS', 'TVB']) level: string;
  @IsInt() @Min(1) @Max(6) studyYear: number;
  @IsString() @MaxLength(40) title: string;
  @IsOptional() @IsString() @MaxLength(20) shortName?: string;
}

class QualificationLevelLabelDto {
  @IsIn(['PVC', 'PVS', 'TVB']) level: string;
  @IsString() @MaxLength(40) title: string;
  @IsOptional() @IsInt() sortOrder?: number;
}

class CreateSectionDto {
  @IsUuid() termId: string;
  @IsUuid() courseId: string;
  @IsString() @MaxLength(20) sectionNo: string;

  @IsOptional() @IsUuid() teacherId?: string;
  @IsOptional() @IsUuid() roomId?: string;
  @IsOptional() @IsUuid() curriculumVersionId?: string;

  @IsOptional() @IsInt() @Min(1) @Max(500) capacity?: number;
  /**
   * คาบที่วางแผนไว้ทั้งภาค — ตัวหารของกฎเวลาเรียน 80%
   * ไม่ส่งมาจะคิดจากหน่วยกิต × 18 สัปดาห์ ซึ่งเป็นรูปแบบปกติของภาคเรียนปกติ
   */
  @IsOptional() @IsInt() @Min(1) @Max(1000) plannedPeriods?: number;

  @IsOptional() @IsIn(['onsite', 'online', 'hybrid']) deliveryMode?: string;
}

class ReassignSectionDto {
  @IsOptional() @IsUuid() teacherId?: string;
  @IsOptional() @IsUuid() roomId?: string;
}

@Injectable()
export class CatalogService {
  constructor(private readonly db: DbService) {}

  /** ภาคเรียนทั้งหมดของวิทยาลัย — RLS กรองให้เองตามบริบทผู้ใช้ */
  async terms() {
    return this.db.query(
      `select t.id, t.ordinal, t.kind, t.status,
              t.starts_on, t.ends_on,
              t.add_drop_ends_on, t.withdraw_ends_on, t.grade_due_on,
              t.category_id, t.short_name, t.sort_order, t.is_normal,
              t.registration_starts_on, t.gradebook_starts_on,
              t.payment_starts_on, t.payment_ends_on,
              t.audit_starts_on, t.audit_ends_on,
              ay.year_be, ay.id as academic_year_id
         from term t
         join academic_year ay on ay.id = t.academic_year_id
        order by ay.year_be desc, t.ordinal`,
    );
  }

  /** หมวดภาคเรียน (รอบเช้า/รอบบ่าย/ทวิภาคี ฯลฯ) — ว่างได้ วิทยาลัยที่ไม่แยกรอบไม่ต้องสร้าง */
  async termCategories() {
    return this.db.query(
      `select id, title, sort_order
         from term_category
        order by sort_order, title`,
    );
  }

  async createTermCategory(dto: TermCategoryDto) {
    return this.db.queryOne(
      `insert into term_category (institution_id, title, sort_order)
       values (current_institution_id(), $1, coalesce($2, 0))
       returning id, title, sort_order`,
      [dto.title, dto.sortOrder ?? null],
    );
  }

  async updateTermCategory(id: string, dto: TermCategoryDto) {
    const row = await this.db.queryOne(
      `update term_category set title = $2, sort_order = coalesce($3, sort_order)
        where id = $1
       returning id, title, sort_order`,
      [id, dto.title, dto.sortOrder ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบหมวดภาคเรียนนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async deleteTermCategory(id: string) {
    const row = await this.db.queryOne(
      `delete from term_category where id = $1 returning id`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบหมวดภาคเรียนนี้ หรือไม่มีสิทธิ์ลบ');
    return { deleted: true };
  }

  /**
   * แก้ไขช่องวันที่ย่อยและการจัดกลุ่มของภาคเรียนที่มีอยู่แล้ว
   *
   * `category_id` เขียนทับตรง ๆ (ไม่ผ่าน coalesce เหมือนช่องอื่น) เพราะ
   * "ไม่ระบุหมวด" เป็นค่าที่ผู้ใช้เลือกได้จริง — ถ้าใช้ coalesce แล้วส่ง
   * null มาเพื่อล้างหมวด ค่าจะไม่ถูกล้างเลยเพราะ coalesce(null, เดิม) = เดิม
   */
  async updateTerm(id: string, dto: UpdateTermDto) {
    const row = await this.db.queryOne(
      `update term set
         category_id             = $2,
         short_name              = coalesce($3, short_name),
         sort_order              = coalesce($4, sort_order),
         is_normal               = coalesce($5, is_normal),
         registration_starts_on  = coalesce($6, registration_starts_on),
         gradebook_starts_on     = coalesce($7, gradebook_starts_on),
         payment_starts_on       = coalesce($8, payment_starts_on),
         payment_ends_on         = coalesce($9, payment_ends_on),
         audit_starts_on         = coalesce($10, audit_starts_on),
         audit_ends_on           = coalesce($11, audit_ends_on)
       where id = $1
       returning id, category_id, short_name, sort_order, is_normal,
                 registration_starts_on, gradebook_starts_on,
                 payment_starts_on, payment_ends_on,
                 audit_starts_on, audit_ends_on`,
      [
        id, dto.categoryId ?? null, dto.shortName ?? null, dto.sortOrder ?? null,
        dto.isNormal ?? null, dto.registrationStartsOn ?? null, dto.gradebookStartsOn ?? null,
        dto.paymentStartsOn ?? null, dto.paymentEndsOn ?? null,
        dto.auditStartsOn ?? null, dto.auditEndsOn ?? null,
      ],
    );
    if (!row) throw new NotFoundException('ไม่พบภาคเรียนนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  /**
   * คาบเรียน — ผูกเลขลำดับคาบ (ตัวเดียวกับที่ section_timeslot.period_from/
   * period_to ใช้อยู่แล้ว) เข้ากับเวลานาฬิกาจริง เพื่อให้หน้าจัดตารางสอน
   * และตารางสอบแสดงเวลาจริงแทนเลขเปล่า
   */
  async periods() {
    return this.db.query(
      `select id, ordinal, title, short_name, starts_at, ends_at
         from period order by ordinal`,
    );
  }

  async createPeriod(dto: PeriodDto) {
    return this.db.queryOne(
      `insert into period (institution_id, ordinal, title, short_name, starts_at, ends_at)
       values (current_institution_id(), $1, $2, $3, $4, $5)
       returning id, ordinal, title, short_name, starts_at, ends_at`,
      [dto.ordinal, dto.title, dto.shortName ?? null, dto.startsAt ?? null, dto.endsAt ?? null],
    );
  }

  async updatePeriod(id: string, dto: PeriodDto) {
    const row = await this.db.queryOne(
      `update period set
         ordinal    = $2, title = $3, short_name = $4,
         starts_at  = $5, ends_at = $6
       where id = $1
       returning id, ordinal, title, short_name, starts_at, ends_at`,
      [id, dto.ordinal, dto.title, dto.shortName ?? null, dto.startsAt ?? null, dto.endsAt ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบคาบเรียนนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async deletePeriod(id: string) {
    const row = await this.db.queryOne(`delete from period where id = $1 returning id`, [id]);
    if (!row) throw new NotFoundException('ไม่พบคาบเรียนนี้ หรือไม่มีสิทธิ์ลบ');
    return { deleted: true };
  }

  /** ป้ายชื่อชั้นปีในแต่ละระดับ (ปวช.1, ปวช.2, ...) — ตกแต่งการแสดงผล ไม่กระทบการเลื่อนชั้นปี */
  async gradeLevels() {
    return this.db.query(
      `select id, level, study_year, title, short_name
         from grade_level order by level, study_year`,
    );
  }

  async createGradeLevel(dto: GradeLevelDto) {
    return this.db.queryOne(
      `insert into grade_level (institution_id, level, study_year, title, short_name)
       values (current_institution_id(), $1::qualification_level, $2, $3, $4)
       returning id, level, study_year, title, short_name`,
      [dto.level, dto.studyYear, dto.title, dto.shortName ?? null],
    );
  }

  async updateGradeLevel(id: string, dto: GradeLevelDto) {
    const row = await this.db.queryOne(
      `update grade_level set
         level = $2::qualification_level, study_year = $3, title = $4, short_name = $5
       where id = $1
       returning id, level, study_year, title, short_name`,
      [id, dto.level, dto.studyYear, dto.title, dto.shortName ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบระดับชั้นนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async deleteGradeLevel(id: string) {
    const row = await this.db.queryOne(`delete from grade_level where id = $1 returning id`, [id]);
    if (!row) throw new NotFoundException('ไม่พบระดับชั้นนี้ หรือไม่มีสิทธิ์ลบ');
    return { deleted: true };
  }

  /** ป้ายชื่อระดับการศึกษา (ปวช./ปวส./ทล.บ.) — แทนที่ค่าที่เคยฮาร์ดโค้ดไว้ในหน้าจอ */
  async qualificationLevelLabels() {
    return this.db.query(
      `select id, level, title, sort_order
         from qualification_level_label order by sort_order, level`,
    );
  }

  async upsertQualificationLevelLabel(dto: QualificationLevelLabelDto) {
    return this.db.queryOne(
      `insert into qualification_level_label (institution_id, level, title, sort_order)
       values (current_institution_id(), $1::qualification_level, $2, coalesce($3, 0))
       on conflict (institution_id, level) do update
         set title = excluded.title, sort_order = excluded.sort_order
       returning id, level, title, sort_order`,
      [dto.level, dto.title, dto.sortOrder ?? null],
    );
  }

  async deleteQualificationLevelLabel(id: string) {
    const row = await this.db.queryOne(
      `delete from qualification_level_label where id = $1 returning id`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบป้ายชื่อระดับนี้ หรือไม่มีสิทธิ์ลบ');
    return { deleted: true };
  }

  /** ปีการศึกษาทั้งหมด — ใช้เลือกตอนเปิดภาคเรียนใหม่ */
  async years() {
    return this.db.query(
      `select id, year_be, starts_on, ends_on
         from academic_year order by year_be desc`,
    );
  }

  /**
   * เปิดปีการศึกษาใหม่ — ไม่มีเส้นทางนี้เลยตั้งแต่ 0001 (ดูคอมเมนต์หัวไฟล์
   * 0073) วิทยาลัยที่ผ่านปีแรกไปแล้วไม่มีทางเปิดปีถัดไปได้ผ่านหน้าจอ
   */
  async createYear(dto: CreateAcademicYearDto) {
    return this.db.queryOne(
      `insert into academic_year (institution_id, year_be, starts_on, ends_on)
       values (current_institution_id(), $1, $2, $3)
       returning id, year_be, starts_on, ends_on`,
      [dto.yearBe, dto.startsOn, dto.endsOn],
    );
  }

  async createTerm(academicYearId: string, dto: CreateTermDto) {
    return this.db.queryOne(
      `insert into term
         (academic_year_id, ordinal, kind, starts_on, ends_on,
          add_drop_ends_on, withdraw_ends_on, grade_due_on)
       values ($1, $2, coalesce($3, 'regular')::term_kind, $4, $5, $6, $7, $8)
       returning id, ordinal, kind, status, starts_on, ends_on,
                 add_drop_ends_on, withdraw_ends_on, grade_due_on`,
      [
        academicYearId, dto.ordinal, dto.kind ?? null, dto.startsOn, dto.endsOn,
        dto.addDropEndsOn ?? null, dto.withdrawEndsOn ?? null, dto.gradeDueOn ?? null,
      ],
    );
  }

  /** เดินสถานะภาคเรียนทีละขั้น — ลำดับและข้อความปฏิเสธมาจาก advance_term_status() (0073) */
  async setTermStatus(termId: string, status: string) {
    return this.db.queryOne(
      `select id, ordinal, kind, status, starts_on, ends_on
         from advance_term_status($1, $2::term_status)`,
      [termId, status],
    );
  }

  /**
   * กลุ่มเรียนของภาคเรียนหนึ่ง
   *
   * นับผู้ลงทะเบียนด้วย เพราะหน้าจอลงทะเบียนต้องรู้ว่าเต็มหรือยังก่อนกด
   * ไม่ใช่รู้ตอนที่ฐานข้อมูลปฏิเสธ
   */
  async sections(termId: string, q?: string) {
    return this.db.query(
      `select cs.id, cs.section_no, cs.capacity, cs.planned_periods,
              cs.delivery_mode, cs.is_locked,
              co.id as course_id, co.code, co.name_th, co.credits,
              cs.teacher_id,
              coalesce(tp.first_name_th || ' ' || tp.last_name_th, '') as teacher_name,
              r.name_th as room_name,
              count(e.id) filter (where e.status = 'enrolled') as enrolled
         from class_section cs
         join course co on co.id = cs.course_id
         left join staff  ts on ts.id = cs.teacher_id
         left join person tp on tp.id = ts.person_id
         left join room r on r.id = cs.room_id
         left join enrollment e on e.class_section_id = cs.id
        where cs.term_id = $1
          and ($2::text is null
               or co.code ilike '%' || $2 || '%'
               or co.name_th ilike '%' || $2 || '%')
        group by cs.id, co.id, tp.first_name_th, tp.last_name_th, r.name_th
        order by co.code, cs.section_no`,
      [termId, q ?? null],
    );
  }

  /**
   * คาบเรียนของกลุ่มเรียนหนึ่ง — หน้าเช็คชื่อต้องเลือกคาบก่อนเสมอ
   *
   * นับยอดที่บันทึกไปแล้วมาด้วย เพื่อให้ครูเห็นทันทีว่าคาบไหนยังไม่ได้เช็ค
   * โดยไม่ต้องเปิดเข้าไปดูทีละคาบ
   */
  async meetings(sectionId: string) {
    return this.db.query(
      `select cm.id, cm.meets_on, cm.period_from, cm.period_to,
              cm.period_count, cm.status, cm.note,
              count(ar.id) as marked
         from class_meeting cm
         left join attendance_record ar on ar.class_meeting_id = cm.id
        where cm.class_section_id = $1
        group by cm.id
        order by cm.meets_on, cm.period_from`,
      [sectionId],
    );
  }

  /** คาบประจำสัปดาห์ที่วางไว้ให้กลุ่มเรียนหนึ่ง — ใช้ตอนย้าย/ยกเลิกคาบ */
  async timeslots(sectionId: string) {
    return this.db.query(
      `select st.id, st.day_of_week, st.period_from, st.period_to,
              st.room_id, r.code as room_code, r.name_th as room_name
         from section_timeslot st
         left join room r on r.id = st.room_id
        where st.class_section_id = $1
        order by st.day_of_week, st.period_from`,
      [sectionId],
    );
  }

  /** เรียก generate_class_meetings() ซึ่งเดิมไม่มีเส้นทางไหนเรียกเลย */
  async generateMeetings(sectionId: string) {
    const row = await this.db.queryOne<{ n: number }>(
      `select generate_class_meetings($1) as n`,
      [sectionId],
    );
    return { created: Number(row?.n ?? 0) };
  }

  /**
   * เปิดกลุ่มเรียนใหม่
   *
   * ชั้นนี้ทำแค่เติมค่าที่คิดได้เองสองตัว แล้วปล่อยให้ฐานข้อมูลตรวจที่เหลือ
   * ทั้งหมด — วิชาต้องอยู่ในวิทยาลัยเดียวกัน ครูต้องเป็นครูจริง ห้องต้องว่าง
   * และเลขกลุ่มต้องไม่ซ้ำ ล้วนเป็น constraint ที่บังคับกับทุกทางที่เขียนเข้ามา
   */
  async createSection(dto: CreateSectionDto) {
    return this.db.tx(async (c) => {
      const policy = (
        await c.query<{ id: string }>(
          `select id from attendance_policy
            order by effective_from_year_be desc limit 1`,
        )
      ).rows[0];

      if (!policy) {
        // เกิดกับวิทยาลัยที่เพิ่งเปิดและยังไม่ได้รัน db/deploy/reference-data.sql
        throw new BadRequestException(
          'ยังไม่ได้ตั้งนโยบายเวลาเรียนของสถานศึกษานี้ จึงเปิดกลุ่มเรียนไม่ได้ ' +
            '(ดูขั้นตอนที่ 8 ใน DEPLOY-ONLINE.md)',
        );
      }

      const course = (
        await c.query<{ credits: string }>(`select credits from course where id = $1`, [
          dto.courseId,
        ])
      ).rows[0];

      if (!course) throw new BadRequestException('ไม่พบรายวิชานี้ หรือไม่มีสิทธิ์เข้าถึง');

      /*
       * ─── ทำไมต้องหาฉบับหลักสูตรให้ ───
       * `compute_section_grades()` ปฏิเสธกลุ่มเรียนที่ไม่ได้ผูกฉบับหลักสูตร
       * เพราะไม่รู้ว่าใช้ระเบียบวัดผลชุดไหน — แต่ข้อผิดพลาดนั้นโผล่ตอน
       * **ตัดเกรดปลายภาค** ซึ่งห่างจากตอนเปิดกลุ่มเรียนหลายเดือน
       * ปล่อยให้สร้างกลุ่มที่ตัดเกรดไม่ได้จึงเท่ากับซ่อนปัญหาไว้ทั้งภาคเรียน
       *
       * ถ้าไม่ได้ระบุมา และรายวิชานี้อยู่ในฉบับที่ใช้งานอยู่เพียงฉบับเดียว
       * ให้ผูกฉบับนั้น — ไม่ใช่การเดา แต่เป็นกรณีที่มีคำตอบเดียว
       * ถ้ามีหลายฉบับต้องเลือกเอง เพราะนั่นคือการตัดสินใจทางวิชาการจริง ๆ
       */
      let versionId = dto.curriculumVersionId ?? null;
      if (!versionId) {
        const versions = (
          await c.query<{ curriculum_version_id: string }>(
            `select distinct cc.curriculum_version_id
               from curriculum_course cc
               join curriculum_version cv on cv.id = cc.curriculum_version_id
              where cc.course_id = $1 and cv.status = 'active'`,
            [dto.courseId],
          )
        ).rows;

        if (versions.length === 1) versionId = versions[0]!.curriculum_version_id;
        else if (versions.length === 0) {
          throw new BadRequestException(
            'รายวิชานี้ยังไม่อยู่ในฉบับหลักสูตรที่ใช้งานอยู่ จึงเปิดกลุ่มเรียนไม่ได้ ' +
              'เพราะจะตัดเกรดไม่ได้เมื่อถึงปลายภาค',
          );
        } else {
          throw new BadRequestException(
            `รายวิชานี้อยู่ในฉบับหลักสูตรที่ใช้งานอยู่ ${versions.length} ฉบับ ` +
              'ต้องระบุ curriculumVersionId ว่าจะใช้ฉบับไหน',
          );
        }
      }

      // 18 สัปดาห์ต่อภาคเรียนปกติ — ตัวหารของกฎเวลาเรียน 80%
      const planned = dto.plannedPeriods ?? Math.round(Number(course.credits) * 18);

      const row = await c.query(
        `insert into class_section
           (institution_id, term_id, course_id, curriculum_version_id, section_no,
            teacher_id, room_id, capacity, delivery_mode, attendance_policy_id, planned_periods)
         values (current_institution_id(), $1, $2, $3, $4,
                 $5, $6, coalesce($7, 40), coalesce($8, 'onsite')::delivery_mode, $9, $10)
         -- คืนสามค่าที่ชั้นนี้เติมให้เอง เพื่อให้ผู้เรียกยืนยันได้ว่าได้ฉบับ
         -- หลักสูตรและนโยบายเวลาเรียนตัวไหนไป โดยไม่ต้องอ่านซ้ำ
         returning id, section_no, capacity, planned_periods, delivery_mode,
                   curriculum_version_id, attendance_policy_id`,
        [
          dto.termId,
          dto.courseId,
          versionId,
          dto.sectionNo,
          dto.teacherId ?? null,
          dto.roomId ?? null,
          dto.capacity ?? null,
          dto.deliveryMode ?? null,
          policy.id,
          planned,
        ],
      );

      return row.rows[0];
    });
  }

  /**
   * ย้ายผู้สอน/ห้องของกลุ่มเรียนที่เปิดไว้แล้ว
   *
   * ไม่แตะคาบที่วางไว้ใน section_timeslot — ถ้าเปลี่ยนห้องแล้วต้องการให้
   * คาบที่วางไว้ตามไปด้วย ต้องย้ายคาบแยกที่ /timetable/slots/:id/move
   * เพราะห้องของ "กลุ่มเรียน" กับห้องของ "คาบหนึ่ง ๆ" เป็นคนละช่องกัน
   * (กลุ่มเรียนอาจไม่มีคาบตายตัว หรือใช้คนละห้องในแต่ละคาบก็ได้)
   */
  async reassignSection(id: string, dto: ReassignSectionDto) {
    if (dto.teacherId === undefined && dto.roomId === undefined) {
      throw new BadRequestException('ต้องระบุผู้สอนใหม่หรือห้องใหม่อย่างน้อยหนึ่งอย่าง');
    }
    const row = await this.db.queryOne(
      `update class_section
          set teacher_id = coalesce($2, teacher_id),
              room_id    = coalesce($3, room_id)
        where id = $1
        returning id, teacher_id, room_id`,
      [id, dto.teacherId ?? null, dto.roomId ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบกลุ่มเรียนนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }
}

/**
 * อ่านได้ทุกบทบาทของเจ้าหน้าที่ เพราะทุกหน้าจอต้องเลือกภาคเรียนก่อนเสมอ
 * ครูจะเห็นเฉพาะกลุ่มเรียนที่ตัวเองสอนตามนโยบาย RLS ซึ่งเป็นผลที่ต้องการ
 */
@Roles('registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin', 'teacher')
@Controller('academic')
class CatalogController {
  constructor(private readonly svc: CatalogService) {}

  @Get('terms')
  terms() {
    return this.svc.terms();
  }

  @Get('years')
  years() {
    return this.svc.years();
  }

  // เปิดปีการศึกษา/ภาคเรียนใหม่กระทบทั้งวิทยาลัย จำกัดไว้เหมือนการเปิดกลุ่มเรียน
  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('academic_year')
  @Post('years')
  createYear(@Body() dto: CreateAcademicYearDto) {
    return this.svc.createYear(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('term')
  @Post('years/:id/terms')
  createTerm(@Param('id', ParseUuidPipe) id: string, @Body() dto: CreateTermDto) {
    return this.svc.createTerm(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('term', 'id')
  @Post('terms/:id/status')
  setTermStatus(@Param('id', ParseUuidPipe) id: string, @Body() dto: TermStatusDto) {
    return this.svc.setTermStatus(id, dto.status);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('term', 'id')
  @Patch('terms/:id')
  updateTerm(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateTermDto) {
    return this.svc.updateTerm(id, dto);
  }

  @Get('term-categories')
  termCategories() {
    return this.svc.termCategories();
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('term_category')
  @Post('term-categories')
  createTermCategory(@Body() dto: TermCategoryDto) {
    return this.svc.createTermCategory(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('term_category', 'id')
  @Patch('term-categories/:id')
  updateTermCategory(@Param('id', ParseUuidPipe) id: string, @Body() dto: TermCategoryDto) {
    return this.svc.updateTermCategory(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('term_category', 'id')
  @Delete('term-categories/:id')
  deleteTermCategory(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.deleteTermCategory(id);
  }

  @Get('periods')
  periods() {
    return this.svc.periods();
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('period')
  @Post('periods')
  createPeriod(@Body() dto: PeriodDto) {
    return this.svc.createPeriod(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('period', 'id')
  @Patch('periods/:id')
  updatePeriod(@Param('id', ParseUuidPipe) id: string, @Body() dto: PeriodDto) {
    return this.svc.updatePeriod(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('period', 'id')
  @Delete('periods/:id')
  deletePeriod(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.deletePeriod(id);
  }

  @Get('grade-levels')
  gradeLevels() {
    return this.svc.gradeLevels();
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('grade_level')
  @Post('grade-levels')
  createGradeLevel(@Body() dto: GradeLevelDto) {
    return this.svc.createGradeLevel(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('grade_level', 'id')
  @Patch('grade-levels/:id')
  updateGradeLevel(@Param('id', ParseUuidPipe) id: string, @Body() dto: GradeLevelDto) {
    return this.svc.updateGradeLevel(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('grade_level', 'id')
  @Delete('grade-levels/:id')
  deleteGradeLevel(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.deleteGradeLevel(id);
  }

  @Get('qualification-levels')
  qualificationLevelLabels() {
    return this.svc.qualificationLevelLabels();
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('qualification_level_label')
  @Post('qualification-levels')
  upsertQualificationLevelLabel(@Body() dto: QualificationLevelLabelDto) {
    return this.svc.upsertQualificationLevelLabel(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('qualification_level_label', 'id')
  @Delete('qualification-levels/:id')
  deleteQualificationLevelLabel(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.deleteQualificationLevelLabel(id);
  }

  @Get('sections/:sectionId/meetings')
  meetings(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.meetings(sectionId);
  }

  @Get('sections/:sectionId/timeslots')
  timeslots(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.timeslots(sectionId);
  }

  /**
   * สร้างคาบเรียนจริงจากตารางสอนที่วางไว้
   *
   * `generate_class_meetings()` มีในฐานข้อมูลตั้งแต่ 0009 แต่ไม่มีเส้นทางไหน
   * เรียกเลยสักเส้น — คาบเรียนจึงไม่เคยเกิดขึ้น และเมื่อไม่มีคาบก็เช็คชื่อ
   * ไม่ได้ทั้งระบบ ทั้งที่ทั้งชั้นเช็คชื่อและกฎเวลาเรียน 80% พร้อมมานานแล้ว
   * (รูปแบบเดียวกับ take_usage_snapshot ในข้อ 8 ของรายการที่เคยพังเงียบ ๆ)
   *
   * ฟังก์ชันจะปฏิเสธถ้ากลุ่มเรียนนี้มีคาบที่สอนไปแล้ว เพราะการสร้างใหม่
   * แปลว่าลบของเดิมทิ้ง ซึ่งจะลบเวลาเรียนที่บันทึกไว้ไปด้วย
   */
  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('class_meeting')
  @Post('sections/:sectionId/meetings')
  generateMeetings(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.generateMeetings(sectionId);
  }

  @Get('sections')
  sections(@Query('termId', ParseUuidPipe) termId: string, @Query('q') q?: string) {
    return this.svc.sections(termId, q);
  }

  // เปิดกลุ่มเรียนเป็นงานวิชาการ ไม่ใช่งานของครูผู้สอน
  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('class_section')
  @Post('sections')
  create(@Body() dto: CreateSectionDto) {
    return this.svc.createSection(dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Audit('class_section', 'id')
  @Post('sections/:id/reassign')
  reassign(@Param('id', ParseUuidPipe) id: string, @Body() dto: ReassignSectionDto) {
    return this.svc.reassignSection(id, dto);
  }
}

@Module({
  controllers: [RegradeController, RolloverController, TimetableController, CatalogController, ClassGroupController],
  providers: [RegradeService, RolloverService, TimetableService, CatalogService, ClassGroupService],
  exports: [RegradeService, RolloverService, TimetableService, CatalogService, ClassGroupService],
})
export class AcademicModule {}

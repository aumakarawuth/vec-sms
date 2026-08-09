import {
  Body,
  Controller,
  Delete,
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
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { AppRole, Roles } from '../../common/auth/auth.guard';
import { RequestContext } from '../../common/context/request-context';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * สมุดคะแนนและการอนุมัติเกรด
 *
 * ─── ชั้นนี้บางมากโดยตั้งใจ ───
 * การตัดเกรดทั้งหมดอยู่ใน compute_section_grades() และ submit_section_grades()
 * ในฐานข้อมูล ที่นี่แค่เรียกและแปลงรูปแบบ เหตุผลเดียวกับโมดูลอื่น —
 * ถ้ายกกฎขึ้นมาไว้ในโค้ด สคริปต์นำเข้าข้อมูลจากระบบเดิมจะข้ามกฎได้หมด
 *
 * ─── ขอบเขตของครูมาจาก RLS ไม่ใช่จากเงื่อนไขในโค้ด ───
 * ไม่มีที่ไหนในไฟล์นี้เช็คว่า "ครูคนนี้สอนกลุ่มนี้ไหม" เพราะนโยบาย
 * gradebook_item_scope และ section_scope ในฐานข้อมูลกรองให้แล้ว
 * ครูที่ไม่ได้สอนกลุ่มนั้นจะได้ศูนย์แถว ไม่ใช่ข้อมูลของคนอื่น
 */

const CATEGORIES = ['formative', 'midterm', 'final', 'affective', 'practical'] as const;

const STAGES = [
  'teacher_submitted',
  'head_approved',
  'academic_approved',
  'director_approved',
  'locked',
  'returned',
] as const;
type Stage = (typeof STAGES)[number];

/**
 * ใครเลื่อนไปขั้นไหนได้
 *
 * ฐานข้อมูลบังคับ **ลำดับ** ของขั้น ส่วนที่นี่บังคับ **ตัวบุคคล** ของแต่ละขั้น
 * สองอย่างนี้คนละเรื่องกัน และต้องมีทั้งคู่ — ถ้ามีแต่ลำดับ ครูคนเดียว
 * ก็กดผ่านทั้งสายได้เอง ซึ่งทำให้ขั้นตอนอนุมัติไม่มีความหมาย
 */
const STAGE_APPROVERS: Record<Stage, AppRole[]> = {
  teacher_submitted: ['teacher', 'academic', 'admin'],
  head_approved: ['teacher', 'academic', 'director', 'admin'],
  academic_approved: ['academic', 'director', 'admin'],
  director_approved: ['director', 'admin'],
  locked: ['registrar', 'director', 'admin'],
  returned: ['teacher', 'academic', 'director', 'registrar', 'admin'],
};

class CreateItemDto {
  @IsString() nameTh: string;
  @IsOptional() @IsIn(CATEGORIES as unknown as string[]) category?: string;
  @IsNumber() @Min(0.01) maxScore: number;
  @IsNumber() @Min(0) weight: number;
  @IsOptional() @IsUuid() competencyId?: string;
  @IsOptional() @IsISO8601() dueOn?: string;
  @IsOptional() @IsBoolean() publishToStudent?: boolean;
  @IsOptional() @IsInt() sortOrder?: number;
}

class UpdateItemDto {
  @IsOptional() @IsString() nameTh?: string;
  @IsOptional() @IsIn(CATEGORIES as unknown as string[]) category?: string;
  @IsOptional() @IsNumber() @Min(0.01) maxScore?: number;
  @IsOptional() @IsNumber() @Min(0) weight?: number;
  @IsOptional() @IsISO8601() dueOn?: string;
  @IsOptional() @IsBoolean() publishToStudent?: boolean;
  @IsOptional() @IsInt() sortOrder?: number;
}

class ScoreEntryDto {
  @IsUuid() enrollmentId: string;
  // null แปลว่าลบคะแนนที่เคยกรอกไว้ ไม่ใช่ให้ศูนย์คะแนน — สองอย่างนี้
  // ต่างกันมากตอนตัดเกรด เพราะ null ทำให้ได้ ม.ส. ส่วน 0 ทำให้คะแนนตก
  @IsOptional() @IsNumber() @Min(0) score?: number | null;
}

class RecordScoresDto {
  @IsArray() @ArrayNotEmpty() @ValidateNested({ each: true }) @Type(() => ScoreEntryDto)
  scores: ScoreEntryDto[];
}

class AdvanceDto {
  @IsIn(STAGES as unknown as string[]) toStage: Stage;
  @IsOptional() @IsString() note?: string;
}

class ChangeRequestDto {
  @IsUuid() toGradeSymbolId: string;
  @IsString() reason: string;
  @IsOptional() @IsNumber() @Min(0) toRawScore?: number;
  @IsOptional() @IsString() documentNo?: string;
}

class RejectDto {
  @IsString() reason: string;
}

@Injectable()
export class GradebookService {
  constructor(private readonly db: DbService) {}

  // ─── ชิ้นงานในสมุดคะแนน ────────────────────────────────────────

  async listItems(sectionId: string) {
    return this.db.query(
      `select gi.id, gi.name_th, gi.category, gi.max_score, gi.weight,
              gi.competency_id, gi.due_on, gi.publish_to_student, gi.sort_order,
              count(gs.id) filter (where gs.score is not null) as scored_count
         from gradebook_item gi
         left join gradebook_score gs on gs.gradebook_item_id = gi.id
        where gi.class_section_id = $1
        group by gi.id
        order by gi.sort_order, gi.due_on nulls last, gi.name_th`,
      [sectionId],
    );
  }

  async createItem(sectionId: string, dto: CreateItemDto) {
    return this.db.queryOne(
      `insert into gradebook_item
         (class_section_id, name_th, category, max_score, weight,
          competency_id, due_on, publish_to_student, sort_order)
       values ($1, $2, coalesce($3, 'formative')::gradebook_category, $4, $5,
               $6, $7, coalesce($8, false), coalesce($9, 0))
       returning id, name_th, category, max_score, weight, due_on,
                 publish_to_student, sort_order`,
      [
        sectionId, dto.nameTh, dto.category ?? null, dto.maxScore, dto.weight,
        dto.competencyId ?? null, dto.dueOn ?? null,
        dto.publishToStudent ?? null, dto.sortOrder ?? null,
      ],
    );
  }

  async updateItem(itemId: string, dto: UpdateItemDto) {
    const row = await this.db.queryOne(
      `update gradebook_item
          set name_th            = coalesce($2, name_th),
              category           = coalesce($3::gradebook_category, category),
              max_score          = coalesce($4, max_score),
              weight             = coalesce($5, weight),
              due_on             = coalesce($6, due_on),
              publish_to_student = coalesce($7, publish_to_student),
              sort_order         = coalesce($8, sort_order)
        where id = $1
        returning id, name_th, category, max_score, weight, due_on,
                  publish_to_student, sort_order`,
      [
        itemId, dto.nameTh ?? null, dto.category ?? null, dto.maxScore ?? null,
        dto.weight ?? null, dto.dueOn ?? null,
        dto.publishToStudent ?? null, dto.sortOrder ?? null,
      ],
    );
    if (!row) throw new ForbiddenException('ไม่พบชิ้นงานนี้ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async deleteItem(itemId: string) {
    const row = await this.db.queryOne<{ id: string }>(
      `delete from gradebook_item where id = $1 returning id`,
      [itemId],
    );
    if (!row) throw new ForbiddenException('ไม่พบชิ้นงานนี้ หรือไม่มีสิทธิ์ลบ');
    return { deleted: row.id };
  }

  // ─── คะแนน ─────────────────────────────────────────────────────

  /** ตารางคะแนนทั้งกลุ่ม — หน้าจอกรอกคะแนนของครูใช้ชุดนี้ชุดเดียว */
  async scoreSheet(sectionId: string) {
    return this.db.tx(async (c) => {
      const items = (
        await c.query(
          `select id, name_th, category, max_score, weight, publish_to_student
             from gradebook_item where class_section_id = $1
            order by sort_order, due_on nulls last, name_th`,
          [sectionId],
        )
      ).rows;

      const rows = (
        await c.query(
          `select e.id as enrollment_id, s.student_code,
                  p.first_name_th || ' ' || p.last_name_th as full_name,
                  va.pct_final, va.attendance_state,
                  coalesce(
                    jsonb_object_agg(gs.gradebook_item_id, gs.score)
                      filter (where gs.gradebook_item_id is not null),
                    '{}'::jsonb
                  ) as scores
             from enrollment e
             join student s on s.id = e.student_id
             join person  p on p.id = s.person_id
             left join v_enrollment_attendance va on va.enrollment_id = e.id
             left join gradebook_score gs on gs.enrollment_id = e.id
            where e.class_section_id = $1 and e.status = 'enrolled'
            group by e.id, s.student_code, p.first_name_th, p.last_name_th,
                     va.pct_final, va.attendance_state
            order by s.student_code`,
          [sectionId],
        )
      ).rows;

      const weightTotal = items.reduce(
        (sum: number, i: { weight: string }) => sum + Number(i.weight),
        0,
      );

      return { items, students: rows, weightTotal };
    });
  }

  /**
   * กรอกคะแนนทีละหลายคน
   *
   * หน้าจอของครูกรอกทั้งคอลัมน์แล้วกดบันทึกครั้งเดียว ถ้าให้ยิงทีละคน
   * ครูที่สัญญาณไม่ดีในโรงฝึกงานจะเจอสถานะครึ่ง ๆ กลาง ๆ ที่บอกไม่ได้ว่า
   * คนไหนบันทึกแล้วบ้าง ทั้งชุดจึงอยู่ในธุรกรรมเดียว
   */
  async recordScores(itemId: string, dto: RecordScoresDto) {
    return this.db.tx(async (c) => {
      let written = 0;
      let cleared = 0;

      for (const entry of dto.scores) {
        if (entry.score === null || entry.score === undefined) {
          const r = await c.query(
            `delete from gradebook_score
              where gradebook_item_id = $1 and enrollment_id = $2`,
            [itemId, entry.enrollmentId],
          );
          cleared += r.rowCount ?? 0;
          continue;
        }

        const r = await c.query(
          `insert into gradebook_score
             (gradebook_item_id, enrollment_id, score, recorded_by)
           values ($1, $2, $3, current_actor_id())
           on conflict (gradebook_item_id, enrollment_id) do update
             set score = excluded.score,
                 recorded_by = excluded.recorded_by,
                 recorded_at = now()`,
          [itemId, entry.enrollmentId, entry.score],
        );
        written += r.rowCount ?? 0;
      }

      // คะแนนเกินคะแนนเต็มเป็นความผิดพลาดที่เจอบ่อยที่สุดตอนกรอก
      // ปล่อยผ่านแล้วคะแนนถ่วงน้ำหนักจะเกิน 100 โดยไม่มีใครสังเกต
      const over = (
        await c.query<{ n: string }>(
          `select count(*) as n
             from gradebook_score gs join gradebook_item gi on gi.id = gs.gradebook_item_id
            where gs.gradebook_item_id = $1 and gs.score > gi.max_score`,
          [itemId],
        )
      ).rows[0];

      if (Number(over.n) > 0) {
        throw new ForbiddenException(
          `มีคะแนนที่เกินคะแนนเต็มของชิ้นงานนี้ ${over.n} รายการ ตรวจอีกครั้งก่อนบันทึก`,
        );
      }

      return { written, cleared };
    });
  }

  // ─── ตัดเกรดและอนุมัติ ──────────────────────────────────────────

  /** ดูก่อนส่งได้เสมอ ไม่เขียนอะไรลงฐานข้อมูล */
  async preview(sectionId: string) {
    return this.db.query(
      `select * from compute_section_grades($1)`,
      [sectionId],
    );
  }

  async submit(sectionId: string) {
    const row = await this.db.queryOne<{
      submission_id: string;
      results_written: number;
    }>(`select * from submit_section_grades($1)`, [sectionId]);

    return {
      submissionId: row!.submission_id,
      resultsWritten: Number(row!.results_written),
    };
  }

  async submission(sectionId: string) {
    return this.db.tx(async (c) => {
      const sub = (
        await c.query(
          `select id, class_section_id, term_id, stage,
                  submitted_by, submitted_at, locked_at, created_at
             from grade_submission where class_section_id = $1`,
          [sectionId],
        )
      ).rows[0];

      if (!sub) return { stage: 'draft', history: [], results: [] };

      const history = (
        await c.query(
          `select from_stage, to_stage, actor_id, note, occurred_at
             from grade_submission_event
            where submission_id = $1
            order by occurred_at`,
          [sub.id],
        )
      ).rows;

      const results = (
        await c.query(
          `select er.enrollment_id, s.student_code,
                  p.first_name_th || ' ' || p.last_name_th as full_name,
                  er.revision, er.raw_score, er.attendance_pct,
                  sy.symbol, er.grade_point, er.credits_earned
             from enrollment_result er
             join enrollment e   on e.id  = er.enrollment_id
             join student    s   on s.id  = e.student_id
             join person     p   on p.id  = s.person_id
             join grade_symbol sy on sy.id = er.grade_symbol_id
            where e.class_section_id = $1 and er.superseded_by is null
            order by s.student_code`,
          [sectionId],
        )
      ).rows;

      return { ...sub, history, results };
    });
  }

  async advance(submissionId: string, dto: AdvanceDto) {
    const role = RequestContext.get()!.role;
    const allowed = STAGE_APPROVERS[dto.toStage];

    if (!allowed.includes(role)) {
      throw new ForbiddenException(
        `ขั้น "${dto.toStage}" ต้องเป็นบทบาท ${allowed.join(' หรือ ')} จึงจะอนุมัติได้`,
      );
    }

    const row = await this.db.queryOne<{ stage: string }>(
      `select advance_grade_submission($1, $2::submission_stage, $3) as stage`,
      [submissionId, dto.toStage, dto.note ?? null],
    );
    return { submissionId, stage: row!.stage };
  }

  // ─── คำร้องแก้เกรดหลังล็อก ──────────────────────────────────────

  /**
   * ชั้นนี้ไม่ตรวจ dual control เลย เพราะกฎอยู่ในฐานข้อมูลทั้งหมด
   * ทั้งฟังก์ชันและ trigger บน grade_change_request — การตรวจซ้ำที่นี่
   * จะกลายเป็นกฎชุดที่สองที่ค่อย ๆ เพี้ยนไปจากของจริงเมื่อเวลาผ่านไป
   */
  async requestChange(enrollmentId: string, dto: ChangeRequestDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `select request_grade_change($1, $2, $3, $4, $5) as id`,
      [
        enrollmentId, dto.toGradeSymbolId, dto.reason,
        dto.toRawScore ?? null, dto.documentNo ?? null,
      ],
    );
    return this.changeRequest(row!.id);
  }

  async listChangeRequests(status?: string) {
    return this.db.query(
      `select r.id, r.enrollment_id, r.status, r.reason, r.document_no,
              r.to_raw_score, r.created_at,
              r.requested_by, r.approver_1_id, r.approver_2_id,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              co.code as course_code, co.name_th as course_name,
              cur.symbol as from_symbol, want.symbol as to_symbol
         from grade_change_request r
         join enrollment       e    on e.id  = r.enrollment_id
         join student          s    on s.id  = e.student_id
         join person           p    on p.id  = s.person_id
         join class_section    cs   on cs.id = e.class_section_id
         join course           co   on co.id = cs.course_id
         join enrollment_result er  on er.id = r.from_result_id
         join grade_symbol     cur  on cur.id = er.grade_symbol_id
         join grade_symbol     want on want.id = r.to_grade_symbol_id
        where ($1::text is null or r.status::text = $1)
        order by r.created_at desc
        limit 200`,
      [status ?? null],
    );
  }

  async changeRequest(id: string) {
    const row = await this.db.queryOne(
      `select r.id, r.enrollment_id, r.status, r.reason, r.document_no,
              r.to_raw_score, r.created_at, r.applied_result_id,
              r.requested_by, r.approver_1_id, r.approver_1_at,
              r.approver_2_id, r.approver_2_at,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              co.code as course_code, co.name_th as course_name,
              cur.symbol as from_symbol, er.raw_score as from_raw_score,
              want.symbol as to_symbol
         from grade_change_request r
         join enrollment       e    on e.id  = r.enrollment_id
         join student          s    on s.id  = e.student_id
         join person           p    on p.id  = s.person_id
         join class_section    cs   on cs.id = e.class_section_id
         join course           co   on co.id = cs.course_id
         join enrollment_result er  on er.id = r.from_result_id
         join grade_symbol     cur  on cur.id = er.grade_symbol_id
         join grade_symbol     want on want.id = r.to_grade_symbol_id
        where r.id = $1`,
      [id],
    );
    if (!row) throw new ForbiddenException('ไม่พบคำร้องนี้ หรือไม่มีสิทธิ์เข้าถึง');
    return row;
  }

  async approveChange(id: string) {
    const row = await this.db.queryOne<{ status: string }>(
      `select approve_grade_change($1) as status`,
      [id],
    );
    return { id, status: row!.status };
  }

  async rejectChange(id: string, dto: RejectDto) {
    const row = await this.db.queryOne<{ status: string }>(
      `select reject_grade_change($1, $2) as status`,
      [id, dto.reason],
    );
    return { id, status: row!.status };
  }

  /** คำนวณ GPA รายภาคและ GPAX สะสม — เรียกหลังปิดรอบเกรดของภาคเรียน */
  async computeTermSummary(termId: string) {
    const row = await this.db.queryOne<{ n: number }>(
      `select compute_term_summary($1) as n`,
      [termId],
    );
    return { students: Number(row?.n ?? 0) };
  }

  /**
   * ความคืบหน้าการตัดเกรดรายครู
   *
   * เรียงคนที่ค้างมากที่สุดขึ้นก่อนมาจากฐานข้อมูลแล้ว ชั้นนี้จึงไม่จัดเรียงซ้ำ
   * และสรุปยอดรวมให้ด้วย เพราะคำถามแรกของงานทะเบียนคือ "เหลือกี่ห้อง"
   * ไม่ใช่ "ใครเหลือบ้าง"
   */
  async cutoffProgress(termId: string) {
    const rows = await this.db.query<{
      teacher_id: string;
      teacher_name: string;
      sections_total: number;
      submitted: number;
      remaining: number;
      grade_due_on: string | null;
      is_overdue: boolean;
    }>(
      `select teacher_id, teacher_name, sections_total, submitted,
              remaining, grade_due_on, is_overdue
         from grade_cutoff_progress($1)`,
      [termId],
    );

    return {
      sectionsTotal: rows.reduce((n, r) => n + Number(r.sections_total), 0),
      submitted: rows.reduce((n, r) => n + Number(r.submitted), 0),
      remaining: rows.reduce((n, r) => n + Number(r.remaining), 0),
      teachersOverdue: rows.filter((r) => r.is_overdue).length,
      teachers: rows,
    };
  }
}

@Roles('teacher', 'academic', 'registrar', 'director', 'admin')
@Controller('gradebook')
class GradebookController {
  constructor(private readonly svc: GradebookService) {}

  @Get('sections/:sectionId/items')
  items(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.listItems(sectionId);
  }

  @Post('sections/:sectionId/items')
  createItem(
    @Param('sectionId', ParseUuidPipe) sectionId: string,
    @Body() dto: CreateItemDto,
  ) {
    return this.svc.createItem(sectionId, dto);
  }

  @Patch('items/:itemId')
  updateItem(
    @Param('itemId', ParseUuidPipe) itemId: string,
    @Body() dto: UpdateItemDto,
  ) {
    return this.svc.updateItem(itemId, dto);
  }

  @Delete('items/:itemId')
  deleteItem(@Param('itemId', ParseUuidPipe) itemId: string) {
    return this.svc.deleteItem(itemId);
  }

  @Get('sections/:sectionId/scores')
  scores(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.scoreSheet(sectionId);
  }

  @Post('items/:itemId/scores')
  record(
    @Param('itemId', ParseUuidPipe) itemId: string,
    @Body() dto: RecordScoresDto,
  ) {
    return this.svc.recordScores(itemId, dto);
  }

  @Get('sections/:sectionId/preview')
  preview(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.preview(sectionId);
  }

  @Post('sections/:sectionId/submit')
  submit(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.submit(sectionId);
  }

  @Get('sections/:sectionId/submission')
  submission(@Param('sectionId', ParseUuidPipe) sectionId: string) {
    return this.svc.submission(sectionId);
  }

  @Post('submissions/:id/advance')
  advance(@Param('id', ParseUuidPipe) id: string, @Body() dto: AdvanceDto) {
    return this.svc.advance(id, dto);
  }

  // ─── คำร้องแก้เกรดหลังล็อก ──────────────────────────────────────

  @Post('enrollments/:enrollmentId/change-requests')
  requestChange(
    @Param('enrollmentId', ParseUuidPipe) enrollmentId: string,
    @Body() dto: ChangeRequestDto,
  ) {
    return this.svc.requestChange(enrollmentId, dto);
  }

  @Get('change-requests')
  listChangeRequests(@Query('status') status?: string) {
    return this.svc.listChangeRequests(status);
  }

  @Get('change-requests/:id')
  changeRequest(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.changeRequest(id);
  }

  /**
   * ครูอนุมัติไม่ได้โดยเจตนา แม้จะไม่ใช่ผู้ยื่นคำร้องเองก็ตาม
   *
   * ฐานข้อมูลกันแค่ "ผู้ยื่นอนุมัติเองไม่ได้" และ "สองคนต้องคนละคน"
   * ซึ่งยังเปิดช่องให้ครูสองคนในแผนกเดียวกันอนุมัติกันเองไขว้ไปมาได้
   * การแก้เกรดที่ล็อกแล้วควรผ่านสายบริหาร ไม่ใช่จบในห้องพักครู
   */
  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('change-requests/:id/approve')
  approveChange(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.approveChange(id);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('change-requests/:id/reject')
  rejectChange(@Param('id', ParseUuidPipe) id: string, @Body() dto: RejectDto) {
    return this.svc.rejectChange(id, dto);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Post('terms/:termId/summary')
  summary(@Param('termId', ParseUuidPipe) termId: string) {
    return this.svc.computeTermSummary(termId);
  }

  /**
   * ครูคนไหนยังไม่ส่งเกรด — งานทะเบียนเปิดดูก่อนถึงกำหนดส่งทุกครั้ง
   *
   * ไม่เปิดให้บทบาท teacher เพราะเป็นรายการที่เห็นภาระงานของครูทุกคน
   * ครูดูของตัวเองได้จาก /gradebook/sections/:id/submission อยู่แล้ว
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Get('terms/:termId/cutoff-progress')
  cutoffProgress(@Param('termId', ParseUuidPipe) termId: string) {
    return this.svc.cutoffProgress(termId);
  }
}

@Module({
  controllers: [GradebookController],
  providers: [GradebookService],
  exports: [GradebookService],
})
export class GradebookModule {}

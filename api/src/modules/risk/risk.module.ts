import {
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { PageParams, parsePage, toPage } from '../../common/pagination/pagination';

class TermDto {
  @IsUuid() termId: string;
}

class ActionDoneDto {
  @IsOptional() @IsString() result?: string;
  @IsOptional() @IsString() documentNo?: string;
}

@Injectable()
export class RiskService {
  constructor(private readonly db: DbService) {}

  /** งานประจำคืน — คำนวณสัญญาณและคะแนนใหม่ทั้งสถานศึกษา */
  async compute(termId: string) {
    const row = await this.db.queryOne<{ n: number }>(
      `select compute_risk_scores(current_institution_id(), $1) as n`,
      [termId],
    );
    return { evaluated: Number(row?.n ?? 0) };
  }

  /** เปิดเคสให้ระดับส้มและแดง พร้อมเสนอขั้นตอนตามสัญญาณที่พบจริง */
  async openCases(termId: string) {
    const row = await this.db.queryOne<{ n: number }>(
      `select open_intervention_cases(current_institution_id(), $1) as n`,
      [termId],
    );
    return { opened: Number(row?.n ?? 0) };
  }

  /**
   * หน้าจอศูนย์เฝ้าระวังของครูที่ปรึกษา (P-04)
   *
   * signals_th เป็นข้อความไทยที่ต่อกันแล้ว เพราะครูต้องอ่านออกเสียง
   * ให้ผู้ปกครองฟังได้ว่าทำไมถึงโทรมา ไม่ใช่แค่เห็นคะแนนรวม
   */
  async atRisk(termId: string, band: string | undefined, page: PageParams) {
    // ดึงเกินมาหนึ่งแถวเพื่อรู้ว่ายังมีต่อไหม โดยไม่ต้อง count ทั้งตาราง
    //
    // ก่อนหน้านี้ endpoint นี้คืนทุกแถวโดยไม่มีเพดาน ซึ่งทำงานได้ดีกับข้อมูล
    // ตัวอย่างไม่กี่คน แต่วิทยาลัยที่มีนักศึกษาห้าพันคนในช่วงปลายภาค
    // จะมีกลุ่มเสี่ยงหลักพัน การดึงมาทั้งหมดพร้อมสัญญาณเป็นข้อความไทย
    // ทำให้ทั้งหน่วยความจำและเวลาตอบสนองพุ่งพร้อมกัน
    const rows = await this.db.query(
      `select student_id, student_code, full_name, score, band,
              signals_th, signal_count, case_id, case_status, respond_by
         from v_students_at_risk
        where term_id = $1 and ($2::text is null or band::text = $2)
        order by score desc, student_code
        limit $3 offset $4`,
      [termId, band ?? null, page.limit + 1, page.offset],
    );
    return toPage(rows, page);
  }

  async revenueAtRisk(termId: string) {
    return this.db.query(
      `select band, students, current_term_value, revenue_at_risk
         from v_revenue_at_risk
        where term_id = $1
        order by case band when 'red' then 1 else 2 end`,
      [termId],
    );
  }

  async caseDetail(caseId: string) {
    return this.db.tx(async (c) => {
      const kase = (
        await c.query(
          `select ic.id, ic.opened_on, ic.band_at_open, ic.score_at_open,
                  ic.respond_by, ic.status, ic.outcome,
                  s.student_code,
                  p.first_name_th || ' ' || p.last_name_th as full_name
             from intervention_case ic
             join student s on s.id = ic.student_id
             join person  p on p.id = s.person_id
            where ic.id = $1`,
          [caseId],
        )
      ).rows[0];

      const actions = (
        await c.query(
          `select id, kind, due_on, note, suggested_by_system, done_at, result
             from intervention_action where case_id = $1
            order by done_at nulls first, due_on`,
          [caseId],
        )
      ).rows;

      const signals = (
        await c.query(
          `select s.factor_code, s.points, s.message_th, s.measured
             from student_risk_signal s
             join intervention_case ic on ic.student_id = s.student_id
                                      and ic.term_id    = s.term_id
            where ic.id = $1
            order by s.points desc`,
          [caseId],
        )
      ).rows;

      return { ...kase, signals, actions };
    });
  }

  async completeAction(actionId: string, dto: ActionDoneDto) {
    const row = await this.db.queryOne<{ id: string; case_id: string }>(
      `update intervention_action
          set done_at = now(), done_by = current_actor_id(),
              result = coalesce($2, result), document_no = coalesce($3, document_no)
        where id = $1
        returning id, case_id`,
      [actionId, dto.result ?? null, dto.documentNo ?? null],
    );

    // ทุกขั้นตอนเสร็จแล้วให้เลื่อนสถานะเคสเป็นกำลังดำเนินการ
    await this.db.query(
      `update intervention_case set status = 'in_progress'
        where id = $1 and status = 'open'`,
      [row!.case_id],
    );

    return { id: row!.id, caseId: row!.case_id };
  }
}

@Roles('teacher', 'student_affairs', 'academic', 'director', 'admin')
@Controller('risk')
class RiskController {
  constructor(private readonly svc: RiskService) {}

  @Roles('student_affairs', 'academic', 'director', 'admin')
  @Post('compute')
  compute(@Body() dto: TermDto) {
    return this.svc.compute(dto.termId);
  }

  @Roles('student_affairs', 'academic', 'director', 'admin')
  @Post('cases/open')
  open(@Body() dto: TermDto) {
    return this.svc.openCases(dto.termId);
  }

  @Get('students')
  atRisk(
    @Query('termId', ParseUuidPipe) termId: string,
    @Query('band') band?: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    return this.svc.atRisk(termId, band, parsePage(limit, offset));
  }

  @Roles('director', 'admin', 'academic', 'finance')
  @Get('revenue-at-risk')
  revenue(@Query('termId', ParseUuidPipe) termId: string) {
    return this.svc.revenueAtRisk(termId);
  }

  @Get('cases/:id')
  detail(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.caseDetail(id);
  }

  @Post('actions/:id/done')
  done(@Param('id', ParseUuidPipe) id: string, @Body() dto: ActionDoneDto) {
    return this.svc.completeAction(id, dto);
  }
}

@Module({
  controllers: [RiskController],
  providers: [RiskService],
  exports: [RiskService],
})
export class RiskModule {}

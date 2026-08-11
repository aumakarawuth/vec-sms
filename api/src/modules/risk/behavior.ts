/**
 * พฤติกรรม คัดกรอง และเยี่ยมบ้าน (0056)
 *
 * ─── ทำไมโมดูลนี้เพิ่งมีทั้งที่ตารางมีมาตั้งแต่ต้น ───
 * `behavior_record` · `behavior_rule` · `screening_result` · `home_visit`
 * อยู่ในสคีมามาหลายสิบ migration แล้ว และถูกอ่านที่เดียวคือตอนประกอบ
 * payload ของระเบียนสะสม (ปพ.8) — **ไม่มี endpoint ไหนเขียนเลยสักตัว**
 * ตารางจึงว่างตลอด และ ปพ.8 ที่ออกไปก็ว่างตามโดยไม่มีอะไรฟ้อง
 * รูปเดียวกับ `take_usage_snapshot()` (ข้อ 8) และ `generate_class_meetings()`
 *
 * และการที่ไม่มี endpoint ทำให้เข้าใจผิดได้ว่า "ไม่มีใครเขียนตารางนี้ได้"
 * ซึ่งตรงข้ามกับความจริง — ก่อน 0056 นักศึกษาเขียนได้ทั้งเพิ่ม แก้ และลบ
 * ผ่านทางที่ข้าม API ไปเลย (ดูหัวไฟล์ของ 0056)
 *
 * ─── ชั้นนี้ไม่ตัดสินสิทธิ์ ───
 * ใครบันทึกได้ · ใครแก้ได้ · ครูบันทึกของใครได้ อยู่ในนโยบาย RLS และ trigger
 * ของ 0056 ทั้งหมด `@Roles` ที่นี่มีไว้ให้ได้ 403 ที่อ่านรู้เรื่อง
 */
import {
  Body,
  Controller,
  Delete,
  Get,
  Injectable,
  NotFoundException,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import {
  IsIn,
  IsInt,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

class CreateRuleDto {
  @IsString() code: string;
  @IsString() nameTh: string;
  @IsIn(['deduct', 'award']) direction: string;
  @IsInt() @Min(0) @Max(100) points: number;
  @IsOptional() @IsString() triggersAction?: string;
}

class RecordBehaviorDto {
  @IsUuid() studentId: string;
  @IsUuid() ruleId: string;
  @IsOptional() @IsISO8601() occurredOn?: string;
  /** ถ้าไม่ส่งมาจะใช้คะแนนของกฎ — ดูเหตุผลใน service */
  @IsOptional() @IsInt() @Min(0) @Max(100) points?: number;
  @IsOptional() @IsString() detail?: string;
  @IsOptional() @IsString() documentNo?: string;
}

class ScreeningDto {
  @IsUuid() studentId: string;
  @IsString() instrument: string;
  @IsISO8601() assessedOn: string;
  @IsIn(['normal', 'at_risk', 'has_problem', 'special_needs']) band: string;
  @IsOptional() @IsNumber() score?: number;
}

class HomeVisitDto {
  @IsUuid() studentId: string;
  @IsISO8601() visitedOn: string;
  @IsOptional() @IsString() findings?: string;
  @IsOptional() @IsString() followUp?: string;
}

@Injectable()
export class BehaviorService {
  constructor(private readonly db: DbService) {}

  async rules(includeInactive: boolean) {
    return this.db.query(
      `select id, code, name_th, direction, points, triggers_action, active
         from behavior_rule
        where $1::boolean or active
        order by direction, points desc, code`,
      [includeInactive],
    );
  }

  async createRule(dto: CreateRuleDto) {
    const rows = await this.db.query(
      `insert into behavior_rule
         (institution_id, code, name_th, direction, points, triggers_action)
       values (current_institution_id(), $1, $2, $3::behavior_direction, $4, $5)
       returning id, code, name_th, direction, points`,
      [dto.code, dto.nameTh, dto.direction, dto.points, dto.triggersAction ?? null],
    );
    return rows[0];
  }

  async deactivateRule(ruleId: string) {
    /*
     * ปิดกฎแทนการลบ เพราะบันทึกเก่าอ้างกฎนี้อยู่ ถ้าลบทิ้ง ประวัติที่เคย
     * บันทึกไว้จะกลายเป็นแถวที่ไม่รู้ว่าหักด้วยเหตุผลอะไร — และ
     * `v_behavior_balance` ต้อง join กับกฎเพื่อรู้ทิศทาง จึงจะนับผิดทันที
     */
    const rows = await this.db.query(
      `update behavior_rule set active = false where id = $1 returning id, code`,
      [ruleId],
    );
    if (rows.length === 0) throw new NotFoundException('ไม่พบกฎ หรือไม่มีสิทธิ์แก้ไข');
    return rows[0];
  }

  /**
   * บันทึกพฤติกรรม
   *
   * ─── ทำไมคะแนนคัดลอกจากกฎมาเก็บในบันทึก ───
   * `behavior_record.points` เป็นสำเนาของคะแนนที่ใช้จริง ณ วันนั้น ไม่ใช่
   * การอ้างถึงกฎ ถ้าอ่านจากกฎตอนรวมยอด การแก้คะแนนของกฎในภายหลังจะ
   * เปลี่ยนประวัติของทุกคนย้อนหลังทั้งหมด — หลักเดียวกับ `attendance_pct`
   * ที่ตรึงไว้ตอนตัดเกรด (หลักข้อ 5)
   */
  async record(dto: RecordBehaviorDto) {
    return this.db.tx(async (c) => {
      const rule = (
        await c.query<{ points: number; direction: string; name_th: string }>(
          `select points, direction, name_th from behavior_rule
            where id = $1 and active`,
          [dto.ruleId],
        )
      ).rows[0];
      if (!rule) throw new NotFoundException('ไม่พบกฎที่ระบุ หรือกฎถูกปิดใช้งานแล้ว');

      const rows = (
        await c.query(
          `insert into behavior_record
             (student_id, rule_id, occurred_on, points, detail, document_no, recorded_by)
           values ($1, $2, coalesce($3::date, current_date), $4, $5, $6, current_actor_id())
           returning id, occurred_on, points`,
          [dto.studentId, dto.ruleId, dto.occurredOn ?? null,
           dto.points ?? rule.points, dto.detail ?? null, dto.documentNo ?? null],
        )
      ).rows;

      const status = (
        await c.query(
          `select balance, band from v_behavior_status where student_id = $1`,
          [dto.studentId],
        )
      ).rows[0];

      // คืนยอดใหม่มาด้วย เพราะคนบันทึกต้องรู้ทันทีว่าคนนี้ตกเกณฑ์แล้วหรือยัง
      // ถ้าไม่คืน หน้าจอต้องยิงอีกคำขอเพื่อรู้เรื่องเดียวกัน
      return { ...rows[0], rule: rule.name_th, direction: rule.direction, status };
    });
  }

  async removeRecord(recordId: string) {
    const rows = await this.db.query(
      `delete from behavior_record where id = $1 returning id`, [recordId],
    );
    if (rows.length === 0) throw new NotFoundException('ไม่พบบันทึก หรือไม่มีสิทธิ์ลบ');
    return { ok: true };
  }

  /** ประวัติพฤติกรรมรายคน — RLS เป็นคนตัดว่าเห็นของใครได้ */
  async history(studentId: string) {
    return this.db.tx(async (c) => {
      const status = (
        await c.query(
          `select balance, starting_points, warn_below, critical_below, band,
                  deduct_count, award_count, last_record_on
             from v_behavior_status where student_id = $1`,
          [studentId],
        )
      ).rows[0] ?? null;

      const records = (
        await c.query(
          `select br.id, br.occurred_on, br.points, br.detail, br.document_no,
                  br.recorded_at,
                  r.code, r.name_th as rule_th, r.direction,
                  p.first_name_th || ' ' || p.last_name_th as recorded_by_name
             from behavior_record br
             left join behavior_rule r on r.id = br.rule_id
             left join person p on p.id = br.recorded_by
            where br.student_id = $1
            order by br.occurred_on desc, br.recorded_at desc`,
          [studentId],
        )
      ).rows;

      return { status, records };
    });
  }

  /** ผู้ที่คะแนนความประพฤติต่ำกว่าเกณฑ์ — หน้าจอของงานปกครอง */
  async watchlist(band: string | undefined) {
    return this.db.query(
      `select b.student_id, b.balance, b.band, b.deduct_count, b.last_record_on,
              s.student_code,
              p.first_name_th || ' ' || p.last_name_th as full_name
         from v_behavior_status b
         join student s on s.id = b.student_id
         join person  p on p.id = s.person_id
        where ($1::text is null or b.band = $1)
          and b.band <> 'ok'
          and s.status = 'active'
        order by b.balance
        limit 300`,
      [band ?? null],
    );
  }

  /* ─── คัดกรองและเยี่ยมบ้าน ─────────────────────────────────────── */

  async screenings(studentId: string) {
    return this.db.query(
      `select sr.id, sr.instrument, sr.assessed_on, sr.band, sr.score,
              p.first_name_th || ' ' || p.last_name_th as assessed_by_name
         from screening_result sr
         left join person p on p.id = sr.assessed_by
        where sr.student_id = $1
        order by sr.assessed_on desc`,
      [studentId],
    );
  }

  /**
   * บันทึกผลคัดกรอง
   *
   * `detail` (คำตอบรายข้อ) ไม่รับจากชั้นนี้โดยตั้งใจ — เป็นข้อมูลอ่อนไหว
   * ที่ต้องออกแบบว่าใครเห็นได้ก่อน ตอนนี้เก็บเฉพาะระดับผลซึ่งพอสำหรับ
   * การทำงานของครูที่ปรึกษา (หลักเดียวกับที่ ปพ.8 เก็บแค่ระดับผล)
   */
  async addScreening(dto: ScreeningDto) {
    const rows = await this.db.query(
      `insert into screening_result
         (student_id, instrument, assessed_on, band, score, assessed_by)
       values ($1, $2, $3, $4::screening_band, $5, current_actor_id())
       returning id, instrument, assessed_on, band`,
      [dto.studentId, dto.instrument, dto.assessedOn, dto.band, dto.score ?? null],
    );
    return rows[0];
  }

  async homeVisits(studentId: string) {
    return this.db.query(
      `select hv.id, hv.visited_on, hv.findings, hv.follow_up,
              p.first_name_th || ' ' || p.last_name_th as visited_by_name
         from home_visit hv
         left join person p on p.id = hv.visited_by
        where hv.student_id = $1
        order by hv.visited_on desc`,
      [studentId],
    );
  }

  async addHomeVisit(dto: HomeVisitDto) {
    const rows = await this.db.query(
      `insert into home_visit (student_id, visited_on, findings, follow_up, visited_by)
       values ($1, $2, $3, $4, current_actor_id())
       returning id, visited_on`,
      [dto.studentId, dto.visitedOn, dto.findings ?? null, dto.followUp ?? null],
    );
    return rows[0];
  }
}

@Controller('behavior')
export class BehaviorController {
  constructor(private readonly svc: BehaviorService) {}

  // ทุกคนต้องเห็นกฎ — กฎที่ไม่มีใครรู้ล่วงหน้าไม่ใช่กฎ
  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'student_affairs', 'director', 'admin',
  )
  @Get('rules')
  rules(@Query('all') all?: string) {
    return this.svc.rules(all === 'true');
  }

  @Roles('student_affairs', 'director', 'admin')
  @Audit('behavior_rule')
  @Post('rules')
  createRule(@Body() dto: CreateRuleDto) {
    return this.svc.createRule(dto);
  }

  @Roles('student_affairs', 'director', 'admin')
  @Audit('behavior_rule', 'id')
  @Delete('rules/:id')
  deactivateRule(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.deactivateRule(id);
  }

  @Roles('teacher', 'student_affairs', 'registrar', 'academic', 'director', 'admin')
  @Audit('behavior_record')
  @Post('records')
  record(@Body() dto: RecordBehaviorDto) {
    return this.svc.record(dto);
  }

  @Roles('student_affairs', 'director', 'admin')
  @Audit('behavior_record', 'id')
  @Delete('records/:id')
  removeRecord(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.removeRecord(id);
  }

  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'student_affairs', 'director', 'admin',
  )
  @Audit('behavior_record', 'studentId')
  @Get('students/:studentId')
  history(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.history(studentId);
  }

  @Roles('teacher', 'student_affairs', 'academic', 'director', 'admin')
  @Get('watchlist')
  watchlist(@Query('band') band?: string) {
    return this.svc.watchlist(band);
  }

  /*
   * ผลคัดกรองและบันทึกเยี่ยมบ้านเป็นข้อมูลอ่อนไหว — RLS ของ 0045 จำกัดไว้ที่
   * งานปกครอง ผู้บริหาร และเจ้าของเคสอยู่แล้ว `@Roles` ที่นี่จึงกว้างกว่า
   * ได้โดยไม่เปิดอะไรเพิ่ม แต่ตั้งให้แคบไว้เพื่อให้ได้ 403 ที่อ่านรู้เรื่อง
   * แทนอาร์เรย์ว่างที่ดูเหมือน "ยังไม่เคยคัดกรอง"
   */
  @Roles('student_affairs', 'academic', 'director', 'admin')
  @Audit('screening_result', 'studentId')
  @Get('screenings/:studentId')
  screenings(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.screenings(studentId);
  }

  @Roles('student_affairs', 'academic', 'director', 'admin')
  @Audit('screening_result')
  @Post('screenings')
  addScreening(@Body() dto: ScreeningDto) {
    return this.svc.addScreening(dto);
  }

  @Roles('student_affairs', 'academic', 'director', 'admin')
  @Audit('home_visit', 'studentId')
  @Get('home-visits/:studentId')
  homeVisits(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.homeVisits(studentId);
  }

  @Roles('student_affairs', 'academic', 'director', 'admin')
  @Audit('home_visit')
  @Post('home-visits')
  addHomeVisit(@Body() dto: HomeVisitDto) {
    return this.svc.addHomeVisit(dto);
  }
}

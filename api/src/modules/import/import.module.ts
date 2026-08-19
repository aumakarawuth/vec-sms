import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  Param,
  Post,
  Query,
  UnprocessableEntityException,
} from '@nestjs/common';
import {
  ArrayNotEmpty,
  IsArray,
  IsIn,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * นำเข้าข้อมูลจากระบบเดิม
 *
 * ─── ทำไมต้องมีสองขั้น ───
 * ขั้นที่ 1 สร้างรอบนำเข้าและตรวจทุกแถว คืนรายการปัญหาทั้งหมดโดยไม่เขียนอะไร
 * ขั้นที่ 2 นำเข้าจริงเมื่อไม่เหลือปัญหาแล้ว
 *
 * การนำเข้าที่ล้มเหลวกลางคันแล้วเหลือข้อมูลครึ่ง ๆ กลาง ๆ แก้ยากกว่าไม่นำเข้าเลย
 * เพราะเจ้าหน้าที่ไม่รู้ว่าแถวไหนเข้าไปแล้วบ้าง และนักศึกษาที่เข้าไปครึ่งเดียว
 * จะไปโผล่ในรายงานทันทีทั้งที่ข้อมูลยังไม่ครบ
 *
 * ─── ทำไมรับ JSON ไม่ใช่ไฟล์ CSV ───
 * การแปลง CSV ให้ถูกต้องกับภาษาไทยมีกับดักเยอะมาก — encoding (TIS-620
 * ที่ Excel ไทยยังใช้อยู่) ตัวคั่น การขึ้นบรรทัดใหม่ในเซลล์ และ BOM
 * ให้ฝั่งหน้าจอที่รู้บริบทของไฟล์แปลงเป็น JSON แล้วส่งมา ตรวจง่ายกว่ามาก
 * และข้อความผิดพลาดชี้ไปที่แถวได้ตรงกว่าการเดาจากตำแหน่งไบต์
 */

class ImportRowDto {
  @IsNumber() @Min(1) rowNo: number;
  @IsObject() payload: Record<string, unknown>;
}

class CreateImportDto {
  @IsIn(['student', 'academic_history', 'staff']) kind: string;
  @IsOptional() @IsString() sourceName?: string;
  @IsArray() @ArrayNotEmpty() @ValidateNested({ each: true }) @Type(() => ImportRowDto)
  rows: ImportRowDto[];
}

class PriorRecordDto {
  @IsUuid() studentId: string;
  @IsString() sourceTh: string;
  @IsString() courseCode: string;
  @IsString() courseNameTh: string;
  @IsNumber() @Min(0.5) credits: number;
  @IsString() gradeSymbol: string;
  @IsOptional() @IsString() termLabel?: string;
  @IsOptional() @IsNumber() gradePoint?: number;
  @IsOptional() @IsUuid() mappedCourseId?: string;
  @IsOptional() @IsString() note?: string;

  /**
   * โอนผลการเรียน (*1) หรือเทียบโอนความรู้และประสบการณ์ (*2)
   *
   * เป็นตัวกำหนดเครื่องหมายที่พิมพ์ท้ายชื่อวิชาบนใบ รบ. — ถ้าไม่ส่งมา
   * ฐานข้อมูลตั้งเป็น `transferred_experience` ซึ่งเป็นกรณีที่พบบ่อยกว่า
   * และเป็นค่าที่ "ปลอดภัยกว่า" เพราะไม่ได้อ้างว่ามีเกรดเดิมรองรับ
   */
  @IsOptional() @IsIn(['transferred_grade', 'transferred_experience'])
  transferKind?: string;
}

class ApproveTransferDto {
  @IsArray() @ArrayNotEmpty() @IsUuidArray() recordIds: string[];
}

@Injectable()
export class ImportService {
  constructor(private readonly db: DbService) {}

  /** ขั้นที่ 1 — สร้างรอบและตรวจทุกแถว ไม่เขียนข้อมูลจริงเลย */
  async create(dto: CreateImportDto) {
    return this.db.tx(async (c) => {
      const batch = (
        await c.query<{ id: string }>(
          `insert into import_batch
             (institution_id, kind, source_name, created_by, total_rows)
           values (current_institution_id(), $1::import_kind, $2, current_actor_id(), $3)
           returning id`,
          [dto.kind, dto.sourceName ?? null, dto.rows.length],
        )
      ).rows[0];

      for (const row of dto.rows) {
        await c.query(
          `insert into import_row (batch_id, row_no, payload) values ($1, $2, $3::jsonb)`,
          [batch.id, row.rowNo, JSON.stringify(row.payload)],
        );
      }

      return this.validateInTx(c, batch.id, dto.kind);
    });
  }

  /** ตรวจซ้ำได้เรื่อย ๆ หลังแก้ข้อมูล */
  async validate(batchId: string) {
    return this.db.tx(async (c) => {
      const kind = (
        await c.query<{ kind: string }>(`select kind from import_batch where id = $1`, [
          batchId,
        ])
      ).rows[0]?.kind;
      if (!kind) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');
      return this.validateInTx(c, batchId, kind);
    });
  }

  private async validateInTx(
    c: Parameters<Parameters<DbService['tx']>[0]>[0],
    batchId: string,
    kind: string,
  ) {
    // ตรรกะการตรวจอยู่ในฐานข้อมูลทั้งหมด ชั้นนี้แค่สั่งให้ตรวจ
    // เพื่อให้สคริปต์นำเข้าที่รันตรงกับฐานข้อมูลได้ผลเหมือนกัน
    const validator =
      kind === 'student' ? 'validate_student_row'
      : kind === 'staff' ? 'validate_staff_row'
      : kind === 'academic_history' ? 'validate_academic_history_row'
      : null;

    if (validator) {
      await c.query(
        `update import_row r
            set errors = ${validator}(b.institution_id, r.payload),
                ok = cardinality(${validator}(b.institution_id, r.payload)) = 0
           from import_batch b
          where b.id = r.batch_id and r.batch_id = $1`,
        [batchId],
      );
    }

    await c.query(
      `update import_batch b
          set ok_rows    = s.ok_rows,
              error_rows = s.error_rows,
              total_rows = s.total_rows,
              status     = (case when s.error_rows = 0 then 'validated' else 'draft' end)::import_status
         from (select count(*) filter (where ok)     as ok_rows,
                      count(*) filter (where not ok) as error_rows,
                      count(*)                       as total_rows
                 from import_row where batch_id = $1) s
        where b.id = $1 and b.status <> 'applied'`,
      [batchId],
    );

    return this.detail(batchId, c);
  }

  async detail(
    batchId: string,
    client?: Parameters<Parameters<DbService['tx']>[0]>[0],
  ) {
    const run = async (c: Parameters<Parameters<DbService['tx']>[0]>[0]) => {
      const batch = (
        await c.query(
          `select id, kind, source_name, status, total_rows, ok_rows, error_rows,
                  created_at, applied_at, note
             from import_batch where id = $1`,
          [batchId],
        )
      ).rows[0];
      if (!batch) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');

      // คืนเฉพาะแถวที่มีปัญหา เพราะไฟล์พันแถวที่ผ่านหมดไม่มีอะไรให้ดู
      // และการส่งกลับทั้งหมดทำให้หน้าจอค้าง
      const problems = (
        await c.query(
          `select row_no, errors, payload
             from import_row where batch_id = $1 and not ok
            order by row_no limit 500`,
          [batchId],
        )
      ).rows;

      return { ...batch, problems };
    };

    return client ? run(client) : this.db.tx(run);
  }

  async list(kind?: string) {
    return this.db.query(
      `select id, kind, source_name, status, total_rows, ok_rows, error_rows,
              created_at, applied_at
         from import_batch
        where ($1::text is null or kind::text = $1)
        order by created_at desc limit 100`,
      [kind ?? null],
    );
  }

  /**
   * ขั้นที่ 2 — นำเข้าจริง ทั้งชุดหรือไม่เลย
   *
   * เลือกฟังก์ชันตามชนิดของรอบนำเข้า ไม่ใช่ให้ผู้เรียกระบุมา — ถ้าผู้เรียก
   * ระบุได้ จะยิงรอบของบุคลากรเข้าตัวนำเข้านักศึกษาได้ ซึ่งฟังก์ชันจะปฏิเสธ
   * ด้วยข้อความที่ไม่มีใครเข้าใจว่าเกิดอะไรขึ้น
   */
  async apply(batchId: string) {
    return this.db.tx(async (c) => {
      const kind = (
        await c.query<{ kind: string }>(`select kind from import_batch where id = $1`, [
          batchId,
        ])
      ).rows[0]?.kind;
      if (!kind) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');

      const fn =
        kind === 'student' ? 'apply_student_import'
        : kind === 'staff' ? 'apply_staff_import'
        : kind === 'academic_history' ? 'apply_academic_history_import'
        : null;

      if (!fn) {
        throw new UnprocessableEntityException(
          `ยังไม่รองรับการนำเข้าชนิด "${kind}" — ตอนนี้มีนักศึกษา บุคลากร และประวัติการเรียนเดิม`,
        );
      }

      const row = (
        await c.query<{ imported: number; failed: number }>(`select * from ${fn}($1)`, [
          batchId,
        ])
      ).rows[0];

      return { imported: Number(row?.imported ?? 0), failed: Number(row?.failed ?? 0) };
    });
  }

  // ─── ประวัติการเรียนจากสถานศึกษาเดิม ───────────────────────────

  async addPriorRecords(records: PriorRecordDto[]) {
    return this.db.tx(async (c) => {
      let written = 0;
      for (const r of records) {
        const res = await c.query(
          `insert into prior_academic_record
             (student_id, source_th, term_label, course_code, course_name_th,
              credits, grade_symbol, grade_point, mapped_course_id, note,
              transfer_kind, counts_in_gpa)
           values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                   coalesce($11::credit_source_kind, 'transferred_experience'),
                   -- โอนผลการเรียนยกเกรดเดิมมาด้วย จึงนับ GPA ส่วนเทียบโอน
                   -- ความรู้และประสบการณ์ให้หน่วยกิตอย่างเดียว สองค่านี้
                   -- ต้องเดินคู่กันเสมอ มิฉะนั้นใบจะพิมพ์ (*1) ให้วิชาที่
                   -- ไม่มีแต้ม หรือ (*2) ให้วิชาที่มีแต้มอยู่ในตาราง
                   $11 = 'transferred_grade')
           on conflict (student_id, term_label, course_code) do nothing`,
          [
            r.studentId, r.sourceTh, r.termLabel ?? null, r.courseCode,
            r.courseNameTh, r.credits, r.gradeSymbol, r.gradePoint ?? null,
            r.mappedCourseId ?? null, r.note ?? null, r.transferKind ?? null,
          ],
        );
        written += res.rowCount ?? 0;
      }
      return { written, skipped: records.length - written };
    });
  }

  async priorRecords(studentId: string) {
    return this.db.tx(async (c) => {
      const records = (
        await c.query(
          `select pr.id, pr.source_th, pr.term_label, pr.course_code, pr.course_name_th,
                  pr.credits, pr.grade_symbol, pr.grade_point,
                  pr.approved_at, pr.note,
                  co.code as mapped_course_code, co.name_th as mapped_course_name
             from prior_academic_record pr
             left join course co on co.id = pr.mapped_course_id
            where pr.student_id = $1
            order by pr.term_label nulls last, pr.course_code`,
          [studentId],
        )
      ).rows;

      const summary = (
        await c.query(
          `select coalesce(sum(credits) filter (where approved_at is not null and earns_credit), 0)
                    as approved_credits,
                  coalesce(sum(credits) filter (where approved_at is null), 0)
                    as pending_credits,
                  count(*) as entries
             from prior_academic_record where student_id = $1`,
          [studentId],
        )
      ).rows[0];

      return { ...summary, records };
    });
  }

  /**
   * อนุมัติเทียบโอน
   *
   * หน่วยกิตที่ยังไม่อนุมัติไม่ถูกนับ เหมือนชั่วโมงฝึกที่ยังไม่รับรอง
   * เพราะการเทียบโอนเป็นดุลยพินิจของฝ่ายวิชาการ ไม่ใช่ผลอัตโนมัติ
   * ของการนำเข้าไฟล์
   */
  async approveTransfer(dto: ApproveTransferDto) {
    const row = await this.db.queryOne<{ n: string }>(
      `with updated as (
         update prior_academic_record
            set approved_at = now(),
                approved_by = (select id from staff where person_id = current_actor_id())
          where id = any($1::uuid[]) and approved_at is null
          returning 1)
       select count(*)::text as n from updated`,
      [dto.recordIds],
    );
    return { approved: Number(row?.n ?? 0) };
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('import')
class ImportController {
  constructor(private readonly svc: ImportService) {}

  @Get()
  list(@Query('kind') kind?: string) {
    return this.svc.list(kind);
  }

  @Audit('import_batch')
  @Post()
  create(@Body() dto: CreateImportDto) {
    return this.svc.create(dto);
  }

  @Get(':id')
  detail(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.detail(id);
  }

  @Post(':id/validate')
  validate(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.validate(id);
  }

  @Audit('import_batch')
  @Post(':id/apply')
  apply(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.apply(id);
  }
}

@Controller('prior-records')
class PriorRecordController {
  constructor(private readonly svc: ImportService) {}

  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'director', 'admin',
  )
  @Audit('prior_academic_record', 'studentId')
  @Get('students/:studentId')
  forStudent(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.priorRecords(studentId);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Post()
  add(@Body() dto: { records: PriorRecordDto[] }) {
    return this.svc.addPriorRecords(dto.records ?? []);
  }

  @Roles('academic', 'director', 'admin')
  @Audit('prior_academic_record')
  @Post('approve')
  approve(@Body() dto: ApproveTransferDto) {
    return this.svc.approveTransfer(dto);
  }
}

@Module({
  controllers: [ImportController, PriorRecordController],
  providers: [ImportService],
  exports: [ImportService],
})
export class ImportModule {}

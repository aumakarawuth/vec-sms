import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
} from '@nestjs/common';
import { IsIn, IsISO8601, IsNumber, IsOptional, IsString, Matches, Max, Min } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { IssuedDocument, renderDocument } from './templates';

/**
 * เอกสารของงานทะเบียนและรายงานสำหรับหน่วยงานรัฐ
 *
 * ─── ชั้นนี้บางเป็นพิเศษโดยตั้งใจ ───
 * กฎทั้งหมดอยู่ใน 0027 — การจ่ายเลขที่แบบกันชนกัน การตรึงเนื้อหา
 * การห้ามแก้ทับ และข้อบังคับว่าเลขที่ใบประกาศนียบัตรเป็นตัวเลขล้วน
 * ถ้ายกกฎเหล่านี้ขึ้นมาไว้ที่นี่ สคริปต์ย้ายข้อมูลหรือ pgAdmin จะข้ามได้หมด
 *
 * ─── ทำไมการพิมพ์ซ้ำไม่ได้เรียก issue_document ใหม่ ───
 * เอกสารทางราชการหนึ่งใบมีเลขที่เดียว การเรียกออกใหม่คือการออก **เอกสารคนละใบ**
 * ซึ่งกินเลขที่เพิ่มไปอีกหนึ่งเลขทุกครั้งที่มีคนกดพิมพ์ การพิมพ์ซ้ำจึงต้อง
 * อ่าน payload ของใบเดิมผ่าน GET /documents/:id เท่านั้น
 */

const DOCUMENT_KINDS = [
  'transcript',        // ระเบียนแสดงผลการเรียน (รบ.)
  'certificate',       // ใบประกาศนียบัตร
  'certification',     // หนังสือรับรอง
  'grade_report',      // สมุดพก / ใบแจ้งผลการเรียนรายภาค
  'cumulative_record', // ระเบียนสะสม (ปพ.8)
] as const;

class IssueDocumentDto {
  @IsUuid() studentId: string;
  @IsIn(DOCUMENT_KINDS, {
    message:
      'kind ต้องเป็น transcript, certificate, certification, grade_report หรือ cumulative_record',
  })
  kind: (typeof DOCUMENT_KINDS)[number];

  /** ปีการศึกษาของสายเลขที่ ถ้าไม่ส่งมาฐานข้อมูลจะเลือกให้เอง */
  @IsOptional() @IsNumber() @Min(2500) @Max(2700) yearBe?: number;

  /**
   * ภาคเรียนของสมุดพก — บังคับสำหรับ grade_report
   *
   * ฐานข้อมูลปฏิเสธเองถ้าไม่ส่งมา (ดู 0029) ที่นี่จึงไม่ตรวจซ้ำ เพราะกฎ
   * ต้องมีที่เดียว มิฉะนั้นวันที่เงื่อนไขเปลี่ยนจะแก้ไม่ครบทั้งสองที่
   */
  @IsOptional() @IsUuid() termId?: string;
}

class VoidDocumentDto {
  @IsString() reason: string;
}

class CreateApprovalDto {
  @IsISO8601() approvedOn: string;
  @IsOptional() @IsUuid() termId?: string;
  @IsOptional() @IsString() documentNo?: string;
  @IsOptional() @IsString() note?: string;
  @IsUuid() approvedBy: string;
}

class AddGraduateDto {
  @IsUuid() studentId: string;
  @IsUuid() curriculumVersionId: string;
  @IsISO8601() completedOn: string;
  @IsOptional() @IsUuid() completedTermId?: string;
  @IsNumber() @Min(0) @Max(4) gpax: number;
  @IsNumber() @Min(0) creditsEarned: number;
  @IsOptional() @IsString() transcriptNo?: string;

  /**
   * ตรวจซ้ำที่ชั้นนี้ด้วย ไม่ใช่เพราะไม่เชื่อฐานข้อมูล แต่เพื่อให้ผู้ใช้ได้
   * ข้อความที่บอกว่าผิดตรงไหน แทนที่จะได้ constraint violation ดิบ ๆ
   * กฎจริงยังอยู่ที่ฐานข้อมูลและบังคับกับทุกทางที่เข้าถึงข้อมูล
   */
  @IsOptional()
  @Matches(/^[0-9]+$/, {
    message: 'เลขที่ใบประกาศนียบัตรต้องเป็นตัวเลขล้วนตามระเบียบกระทรวง',
  })
  certificateNo?: string;

  @IsOptional() @IsString() professionalStandardNo?: string;
  @IsOptional() @IsString() note?: string;
}

@Injectable()
export class DocumentsService {
  constructor(private readonly db: DbService) {}

  /** ข้อมูลสดสำหรับดูก่อนออกจริง — ยังไม่กินเลขที่เอกสาร */
  async transcriptPreview(studentId: string) {
    return this.db.query(
      `select year_be, term_ordinal, term_label, course_code, course_name_th,
              credits, grade_symbol, grade_point, credits_earned, category_th
         from transcript_data($1)`,
      [studentId],
    );
  }

  async issue(dto: IssueDocumentDto) {
    const row = await this.db.queryOne(
      `select id, doc_no, kind, copy_no, issued_on, payload
         from issue_document($1, $2::document_kind, $3::smallint, $4)`,
      [dto.studentId, dto.kind, dto.yearBe ?? null, dto.termId ?? null],
    );
    return row;
  }

  async listForStudent(studentId: string) {
    return this.db.query(
      `select id, kind, doc_no, copy_no, issued_on, voided_at, void_reason
         from issued_document
        where student_id = $1
        order by issued_on desc, created_at desc`,
      [studentId],
    );
  }

  /** อ่านใบเดิมเพื่อพิมพ์ซ้ำ — เนื้อหามาจาก payload ที่ตรึงไว้ ไม่คำนวณใหม่ */
  async get(id: string) {
    const row = await this.db.queryOne(
      `select id, student_id, kind, doc_no, copy_no, issued_on,
              voided_at, void_reason, payload
         from issued_document where id = $1`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบเอกสารที่ระบุ');
    return row;
  }

  /**
   * หน้ากระดาษพร้อมพิมพ์
   *
   * เนื้อหาทั้งหมดมาจาก payload ของใบเดิม ฟังก์ชันนี้จึงไม่แตะข้อมูลสดเลย
   * แม้แต่ชื่อสถานศึกษา — ถ้าวิทยาลัยเปลี่ยนชื่อปีหน้า ใบเก่าต้องยังพิมพ์
   * ออกมาเป็นชื่อเดิมที่ใช้ตอนออกใบ
   */
  async print(id: string) {
    const doc = (await this.get(id)) as unknown as IssuedDocument;
    try {
      return renderDocument(doc);
    } catch (err) {
      throw new BadRequestException((err as Error).message);
    }
  }

  async void(id: string, dto: VoidDocumentDto) {
    const row = await this.db.queryOne(
      `update issued_document
          set voided_at = now(), void_reason = $2, voided_by = current_actor_id()
        where id = $1
        returning id, doc_no, voided_at, void_reason`,
      [id, dto.reason],
    );
    if (!row) throw new NotFoundException('ไม่พบเอกสารที่ระบุ');
    return row;
  }
}

@Injectable()
export class GraduationService {
  constructor(private readonly db: DbService) {}

  async createApproval(dto: CreateApprovalDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `insert into graduation_approval
         (institution_id, approved_on, term_id, document_no, note, approved_by)
       values (current_institution_id(), $1, $2, $3, $4, $5)
       returning id, approved_on, document_no`,
      [dto.approvedOn, dto.termId ?? null, dto.documentNo ?? null, dto.note ?? null, dto.approvedBy],
    );
    return row;
  }

  async listApprovals() {
    return this.db.query(
      `select ga.id, ga.approved_on, ga.document_no, ga.note,
              count(sg.id)::integer as graduates
         from graduation_approval ga
         left join student_graduation sg on sg.approval_id = ga.id
        group by ga.id
        order by ga.approved_on desc`,
    );
  }

  async addGraduate(approvalId: string, dto: AddGraduateDto) {
    const row = await this.db.queryOne(
      `insert into student_graduation
         (institution_id, student_id, approval_id, curriculum_version_id,
          completed_on, completed_term_id, gpax, credits_earned,
          transcript_no, certificate_no, professional_standard_no, note)
       values (current_institution_id(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       returning id, student_id, certificate_no, transcript_no`,
      [
        dto.studentId, approvalId, dto.curriculumVersionId,
        dto.completedOn, dto.completedTermId ?? null, dto.gpax, dto.creditsEarned,
        dto.transcriptNo ?? null, dto.certificateNo ?? null,
        dto.professionalStandardNo ?? null, dto.note ?? null,
      ],
    );
    return row;
  }

  /**
   * รายงานผู้สำเร็จการศึกษาสำหรับหน่วยงานรัฐ
   *
   * คืนเป็น JSON ไม่ใช่ไฟล์ เพราะ **รูปแบบไฟล์จริงที่ สอศ. รับ**
   * (ลำดับคอลัมน์ ตัวคั่น รหัสอักขระ) ยังไม่ได้ยืนยันกับสเปกฉบับจริง
   * การเดารูปแบบแล้วให้เจ้าหน้าที่ส่งไปเลยอันตรายกว่าการให้ข้อมูลดิบ
   * แล้วให้คนที่รู้สเปกจัดรูปเอง — ดูหมายเหตุขอบเขตที่หัวไฟล์ 0027
   */
  async pvrs(approvalId: string) {
    const rows = await this.db.query(
      `select seq, student_code, full_name, program_name, qualification,
              completed_on, completed_term, exit_reason, approved_on,
              transcript_no, certificate_no, professional_standard_no,
              gpax, credits_earned, note
         from pvrs_rows($1)`,
      [approvalId],
    );

    const missing = rows.filter(
      (r: any) => !r.certificate_no || !r.transcript_no,
    ).length;

    return {
      approvalId,
      total: rows.length,
      // เตือนก่อนส่ง ดีกว่าให้หน่วยงานรัฐตีกลับทั้งชุด
      missingNumbers: missing,
      formatConfirmed: false,
      note: 'ต้องเทียบรูปแบบไฟล์กับสเปก สอศ. ฉบับจริงก่อนส่ง — ข้อมูลในนี้ยังไม่ได้จัดรูปเป็นไฟล์ส่ง',
      rows,
    };
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('documents')
class DocumentsController {
  constructor(private readonly svc: DocumentsService) {}

  @Get('transcript/:studentId')
  preview(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.transcriptPreview(studentId);
  }

  /** ออกเอกสารใหม่ — กินเลขที่หนึ่งเลขทุกครั้ง จึงบันทึกการเข้าถึงไว้ด้วย */
  @Audit('issued_document')
  @Post('issue')
  issue(@Body() dto: IssueDocumentDto) {
    return this.svc.issue(dto);
  }

  @Get('students/:studentId')
  list(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.listForStudent(studentId);
  }

  @Audit('issued_document', 'id')
  @Get(':id')
  get(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.get(id);
  }

  /**
   * คืน HTML พร้อมพิมพ์ ไม่ใช่ JSON — เจ้าหน้าที่เปิดแล้วสั่งพิมพ์ได้ทันที
   * แม่แบบฝัง CSS มาในหน้าเดียว ไม่มีการอ้างอิงไฟล์ภายนอกเลย จึงพิมพ์ได้
   * แม้อินเทอร์เน็ตของวิทยาลัยล่ม
   */
  @Audit('issued_document', 'id')
  @Header('content-type', 'text/html; charset=utf-8')
  @Get(':id/print')
  print(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.print(id);
  }

  @Audit('issued_document', 'id')
  @Post(':id/void')
  void(@Param('id', ParseUuidPipe) id: string, @Body() dto: VoidDocumentDto) {
    return this.svc.void(id, dto);
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('graduation')
class GraduationController {
  constructor(private readonly svc: GraduationService) {}

  @Get('approvals')
  listApprovals() {
    return this.svc.listApprovals();
  }

  @Audit('graduation_approval')
  @Post('approvals')
  createApproval(@Body() dto: CreateApprovalDto) {
    return this.svc.createApproval(dto);
  }

  @Audit('student_graduation', 'id')
  @Post('approvals/:id/students')
  addGraduate(@Param('id', ParseUuidPipe) id: string, @Body() dto: AddGraduateDto) {
    return this.svc.addGraduate(id, dto);
  }

  @Audit('student_graduation', 'id')
  @Get('approvals/:id/pvrs')
  pvrs(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.pvrs(id);
  }
}

@Module({
  controllers: [DocumentsController, GraduationController],
  providers: [DocumentsService, GraduationService],
  exports: [DocumentsService, GraduationService],
})
export class DocumentsModule {}

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
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { IsBoolean, IsIn, IsISO8601, IsNumber, IsOptional, IsString, Matches, Max, Min } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { WorksheetController, WorksheetService } from './worksheets';
import {
  decryptNationalId,
  decryptionKeys,
  formatNationalId,
} from '../../common/crypto/national-id';
import { IssuedDocument, PrintOptions, applyPrintOptions, renderDocument } from './templates';

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

  /**
   * ภาษาของฉบับที่ออก — ฉบับอังกฤษเป็น**เอกสารคนละฉบับ** ที่เดินเลขคนละสาย
   * ไม่ใช่การพิมพ์ใบเดิมด้วยฟอนต์อื่น (ตรงกับ eng_mass_transcript_no ของ SISA)
   * ฐานข้อมูลปฏิเสธเองถ้าข้อมูลภาษาอังกฤษยังกรอกไม่ครบ พร้อมบอกว่าขาดอะไร
   */
  @IsOptional() @IsIn(['th', 'en']) lang?: 'th' | 'en';
}

/**
 * ตัวเลือกตอนพิมพ์ — ส่งมาทาง query string เพราะเป็นเรื่องของการพิมพ์ครั้งนี้
 * ไม่ใช่ของเอกสาร (ดูเหตุผลเต็มที่ `PrintOptions` ใน templates.ts)
 *
 * รับเป็นข้อความแล้วแปลงเองเพราะ `ValidationPipe` ตั้ง
 * `enableImplicitConversion: false` ไว้ทั้งระบบ — ค่าจาก query จึงเป็น string เสมอ
 */
class PrintOptionsDto {
  @IsOptional() @IsIn(['plain', 'letterhead'], {
    message: 'ชนิดกระดาษต้องเป็น plain หรือ letterhead',
  })
  paper?: 'plain' | 'letterhead';

  @IsOptional() @Matches(/^-?\d{1,2}(\.\d+)?$/, {
    message: 'ระยะเลื่อนแนวนอนต้องเป็นตัวเลขหน่วย pt',
  })
  offsetX?: string;

  @IsOptional() @Matches(/^-?\d{1,2}(\.\d+)?$/, {
    message: 'ระยะเลื่อนแนวตั้งต้องเป็นตัวเลขหน่วย pt',
  })
  offsetY?: string;

  /**
   * รูปแบบย่อยของใบ รบ. ตระกูล 62
   *
   * เลือกได้เพราะสองแบบนี้จัดกลุ่มรายวิชาเหมือนกันทุกประการ ต่างแค่ที่วาง
   * สรุปรายภาคกับถ้อยคำหนึ่งคำ — ต่างจากการเลือกตระกูล 67/62 ซึ่งต้องมาจาก
   * รุ่นหลักสูตรใน payload เพราะจัดกลุ่มคนละแบบ
   */
  @IsOptional() @IsIn(['62', 'sorsor', 'en-landscape'], {
    message: 'รูปแบบใบ รบ. ต้องเป็น 62 หรือ sorsor หรือ en-landscape',
  })
  form?: '62' | 'sorsor' | 'en-landscape';
}

class VoidDocumentDto {
  @IsString() reason: string;
}

/*
 * หนังสือถึงผู้ปกครองแยก endpoint จาก `POST /documents/issue` เพราะรับ
 * ข้อมูลคนละชุด (วันนัดพบ · สถานที่ · เหตุผล) และ payload ที่ได้ก็คนละชุด
 * — การยัดลง DTO เดียวกันจะทำให้ทุกช่องเป็น optional แล้วไม่มีอะไรบังคับได้
 * ว่าหนังสือเชิญต้องมีวันนัด (ฐานข้อมูลบังคับอยู่ แต่ผู้ใช้ควรรู้ก่อนกดส่ง)
 */
const LETTER_KINDS = ['absence_notice', 'guardian_invitation', 'conduct_certificate'] as const;

class IssueLetterDto {
  @IsUuid() studentId: string;
  @IsIn(LETTER_KINDS, {
    message: 'kind ต้องเป็น absence_notice, guardian_invitation หรือ conduct_certificate',
  })
  kind: (typeof LETTER_KINDS)[number];

  /** บังคับสำหรับ absence_notice — ฐานข้อมูลปฏิเสธเองถ้าไม่ส่งมา */
  @IsOptional() @IsUuid() termId?: string;

  // หนังสือเชิญผู้ปกครอง
  @IsOptional() @IsISO8601() meetOn?: string;
  @IsOptional() @IsString() meetTime?: string;
  @IsOptional() @IsString() placeTh?: string;
  @IsOptional() @IsString() withTh?: string;
  @IsOptional() @IsString() reasonTh?: string;

  // ใบรับรองความประพฤติ
  @IsOptional() @IsString() purposeTh?: string;

  @IsOptional() @IsString() note?: string;
}

class CreateApprovalDto {
  @IsISO8601() approvedOn: string;
  @IsOptional() @IsUuid() termId?: string;
  @IsOptional() @IsString() documentNo?: string;
  @IsOptional() @IsString() note?: string;
  @IsUuid() approvedBy: string;
}

/**
 * แก้วันสำเร็จการศึกษา — มีช่องเดียวโดยตั้งใจ
 *
 * ตัวเลข gpax กับหน่วยกิตตรึงตอนอนุมัติจบ (หลักข้อ 5) การใส่ไว้ใน DTO
 * เดียวกันจะทำให้แก้พลาดได้ด้วยฟิลด์ที่หลงมาจากฟอร์ม
 */
class CompletedOnDto {
  @IsISO8601() completedOn: string;
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

/**
 * แบบสำรวจภาวะการมีงานทำ — ชุดคำถามทั่วไป ยังไม่เทียบกับแบบฟอร์ม สอศ. จริง
 * (ดูคอมเมนต์เต็มที่ migration 0072) เงื่อนไข "ทำงานแล้วต้องมีสถานประกอบการ"
 * ตรวจซ้ำที่นี่เพื่อข้อความที่อ่านง่ายกว่า check constraint ดิบ ๆ
 */
class RecordSurveyDto {
  @IsUuid() studentId: string;
  @IsIn(['employed', 'employed_and_studying', 'further_study', 'seeking', 'other'])
  status: string;

  @IsOptional() @IsString() employerNameTh?: string;
  @IsOptional() @IsString() jobTitleTh?: string;
  @IsOptional() @IsNumber() @Min(0) monthlyIncome?: number;
  @IsOptional() @IsBoolean() fieldMatchesStudy?: boolean;

  @IsOptional() @IsString() furtherStudyInstitutionTh?: string;
  @IsOptional() @IsString() furtherStudyFieldTh?: string;

  @IsOptional() @IsString() contactPhone?: string;
  @IsOptional() @IsString() note?: string;
  @IsOptional() @IsISO8601() respondedOn?: string;
}

/**
 * เติมเลขประจำตัวประชาชนลงในสำเนาที่กำลังจะพิมพ์
 *
 * ═══ ทำไมถอดตอนพิมพ์ ไม่ใช่ตอนออกใบ ═══
 * `issued_document.payload` **ลบไม่ได้และแก้ไม่ได้** ถ้าเก็บเลขเปล่าลงไป
 * ทุกใบที่เคยออกจะกลายเป็นคลังเลขบัตรที่เอาออกไม่ได้อีกเลย (หลักข้อ 5ก)
 *
 * payload จึงเก็บเฉพาะ**ไบต์ที่เข้ารหัสแล้ว** ส่วนการถอดเกิดในหน่วยความจำ
 * ของคำขอนี้คำขอเดียว แล้วเลขไปอยู่บนกระดาษอย่างเดียว — ไม่เคยถูกเขียน
 * กลับลงฐานข้อมูล และไม่อยู่ใน JSON ที่หน้าจอเห็น
 *
 * และเพราะเป็นไบต์ชุดเดิมเสมอ การพิมพ์ซ้ำในอีกสิบปีจึงได้เลขเดิมเป๊ะ
 * ตราบที่กุญแจใบนั้นยังอยู่ (หลักข้อ 5 — ค่าที่ตรึงไว้ห้ามคำนวณใหม่)
 *
 * ถอดไม่ได้ = เว้นช่องว่างไว้เหมือนเดิม ไม่ใช่พิมพ์ไม่ได้ทั้งใบ เพราะ
 * ส่วนที่เหลือของเอกสารยังถูกต้องและยังใช้งานได้
 */
function withNationalId(doc: IssuedDocument): void {
  const payload = doc.payload as unknown as {
    national_id_enc?: string | null;
    student?: { national_id?: string };
  };
  const hex = payload.national_id_enc;
  if (!hex || !payload.student) return;

  const plain = decryptNationalId(Buffer.from(hex, 'hex'), decryptionKeys(process.env));
  if (plain !== null) payload.student.national_id = formatNationalId(plain);
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
         from issue_document($1, $2::document_kind, $3::smallint, $4, $5)`,
      [dto.studentId, dto.kind, dto.yearBe ?? null, dto.termId ?? null, dto.lang ?? 'th'],
    );
    return row;
  }

  /**
   * ตรวจก่อนกดว่าออกฉบับภาษาอังกฤษได้หรือยัง
   *
   * มีเส้นทางนี้เพราะการรู้ตอนกดว่า "ยังกรอกไม่ครบ" กับการรู้**ก่อน**กด
   * ต่างกันมากสำหรับงานที่ทำทีละหลายสิบคน — เจ้าหน้าที่ที่กดแล้วล้มทีละคน
   * จะเลิกใช้ฟีเจอร์นี้ แล้วกลับไปพิมพ์ด้วยมือ
   */
  async englishReadiness(studentId: string) {
    return this.db.tx(async (c) => {
      const missing = (
        await c.query<{ fields: string[] }>(
          `select missing_english_fields($1) as fields`, [studentId],
        )
      ).rows[0].fields;

      const courses = (
        await c.query<{ code: string; name_th: string }>(
          `select code, name_th from courses_missing_english($1) limit 20`, [studentId],
        )
      ).rows;

      return { ready: missing.length === 0 && courses.length === 0, missing, courses };
    });
  }

  /**
   * ออกหนังสือถึงผู้ปกครองหรือใบรับรองความประพฤติ
   *
   * ส่ง context เป็น jsonb ก้อนเดียวเพราะแต่ละชนิดใช้คนละช่อง การทำเป็น
   * พารามิเตอร์แยกจะได้ลายเซ็นที่มีช่องว่างเปล่าเกินครึ่งทุกครั้งที่เรียก
   */
  async issueLetter(dto: IssueLetterDto) {
    const context: Record<string, string> = {};
    if (dto.meetOn) context.meet_on = dto.meetOn;
    if (dto.meetTime) context.meet_time = dto.meetTime;
    if (dto.placeTh) context.place_th = dto.placeTh;
    if (dto.withTh) context.with_th = dto.withTh;
    if (dto.reasonTh) context.reason_th = dto.reasonTh;
    if (dto.purposeTh) context.purpose_th = dto.purposeTh;
    if (dto.note) context.note = dto.note;

    return this.db.queryOne(
      `select id, doc_no, kind, copy_no, issued_on, payload
         from issue_student_letter($1, $2::document_kind, $3, $4::jsonb)`,
      [dto.studentId, dto.kind, dto.termId ?? null, JSON.stringify(context)],
    );
  }

  /** ผู้ที่เวลาเรียนต่ำกว่าเกณฑ์ พร้อมวันที่เคยออกจดหมายล่าสุด */
  async absenceCandidates(termId: string) {
    return this.db.query(
      `select student_id, student_code, full_name, courses_at_risk,
              worst_pct, last_notice_on
         from absence_notice_candidates($1)`,
      [termId],
    );
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
  async print(id: string, opts?: PrintOptions) {
    const doc = (await this.get(id)) as unknown as IssuedDocument;
    withNationalId(doc);
    try {
      return applyPrintOptions(renderDocument(doc, opts), opts);
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
  /**
   * แก้เฉพาะวันสำเร็จการศึกษา
   *
   * ไม่แตะ `gpax` และ `credits_earned` — สองค่านั้นตรึงตอนอนุมัติจบ
   * ถ้าแก้ได้ที่นี่ ตัวเลขบนใบจะเปลี่ยนได้โดยไม่ผ่านมติอนุมัติจบ (หลักข้อ 5)
   *
   * ─── ใบที่ออกไปแล้วไม่เปลี่ยนตาม และนั่นถูกแล้ว ───
   * `issued_document.payload` ตรึงตั้งแต่วันที่ออก ใบที่พิมพ์ไปก่อนแก้จะ
   * ยังเขียนวันเดิม — ซึ่งเป็นสิ่งที่ต้องเป็น เพราะมีคนถือใบนั้นอยู่
   * ถ้าต้องการใบที่มีวันใหม่ ต้องยกเลิกใบเก่าแล้วออกใหม่อย่างเปิดเผย
   */
  async setCompletedOn(studentId: string, dto: { completedOn: string }) {
    const row = await this.db.queryOne(
      `update student_graduation
          set completed_on = $2::date
        where student_id = $1
      returning student_id, completed_on, gpax, credits_earned`,
      [studentId, dto.completedOn],
    );
    if (!row) {
      throw new NotFoundException(
        'ไม่พบระเบียนสำเร็จการศึกษาของนักศึกษารายนี้ — ต้องอนุมัติจบก่อนจึงจะแก้วันที่ได้',
      );
    }
    return row;
  }

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

  /**
   * รายชื่อผู้สำเร็จการศึกษาพร้อมสถานะแบบสำรวจล่าสุด
   *
   * เริ่มจาก "คนที่ต้องสำรวจ" ไม่ใช่ช่องค้นหา หลักเดียวกับ
   * absence_notice_candidates() — งานสำรวจภาวะงานทำเปิดหน้ามาเพื่อรู้ว่า
   * ใครยังไม่ได้ตอบ ไม่ใช่เพื่อค้นหาคนที่คิดไว้แล้ว
   */
  async surveyCandidates() {
    return this.db.query(
      `select sg.student_id, s.student_code,
              trim(coalesce(p.prefix_th,'') || p.first_name_th || ' ' || p.last_name_th) as full_name,
              sg.completed_on,
              latest.status as latest_status, latest.responded_on as latest_responded_on
         from student_graduation sg
         join student s on s.id = sg.student_id
         join person p  on p.id = s.person_id
         left join lateral (
           select r.status, r.responded_on from graduation_survey_response r
            where r.student_id = sg.student_id
            order by r.responded_on desc, r.created_at desc limit 1
         ) latest on true
        order by sg.completed_on desc, p.first_name_th`,
    );
  }

  async recordSurvey(dto: RecordSurveyDto) {
    return this.db.queryOne(
      `insert into graduation_survey_response
         (institution_id, student_id, graduation_id, status, employer_name_th, job_title_th,
          monthly_income, field_matches_study, further_study_institution_th, further_study_field_th,
          contact_phone, note, responded_on, recorded_by)
       values (
         current_institution_id(), $1,
         (select id from student_graduation where student_id = $1),
         $2, $3, $4, $5, $6, $7, $8, $9, $10, coalesce($11, current_date),
         (select id from staff where person_id = current_actor_id()))
       returning id, status, responded_on`,
      [
        dto.studentId, dto.status, dto.employerNameTh ?? null, dto.jobTitleTh ?? null,
        dto.monthlyIncome ?? null, dto.fieldMatchesStudy ?? null,
        dto.furtherStudyInstitutionTh ?? null, dto.furtherStudyFieldTh ?? null,
        dto.contactPhone ?? null, dto.note ?? null, dto.respondedOn ?? null,
      ],
    );
  }

  /** สรุปตามสถานะล่าสุดของแต่ละคน — คนที่สำรวจซ้ำนับครั้งเดียวจากคำตอบล่าสุด */
  async surveySummary() {
    return this.db.query(
      `select latest.status, count(*)::integer as students
         from student_graduation sg
         join lateral (
           select r.status from graduation_survey_response r
            where r.student_id = sg.student_id
            order by r.responded_on desc, r.created_at desc limit 1
         ) latest on true
        group by latest.status
        order by students desc`,
    );
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

  @Get('english-readiness/:studentId')
  englishReadiness(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.englishReadiness(studentId);
  }

  /*
   * งานปกครองออกหนังสือถึงผู้ปกครองได้ด้วย ซึ่งเป็นบทบาทที่ไม่ได้อยู่ใน
   * @Roles ระดับคลาส — หนังสือแจ้งขาดเรียนและเชิญผู้ปกครองเป็นงานของ
   * ฝ่ายนั้นโดยตรง ไม่ใช่ของงานทะเบียน
   */
  @Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
  @Audit('issued_document')
  @Post('letters')
  issueLetter(@Body() dto: IssueLetterDto) {
    return this.svc.issueLetter(dto);
  }

  @Roles('registrar', 'academic', 'student_affairs', 'teacher', 'director', 'admin')
  @Get('absence-candidates/:termId')
  absenceCandidates(@Param('termId', ParseUuidPipe) termId: string) {
    return this.svc.absenceCandidates(termId);
  }

  // งานปกครองต้องเปิดและพิมพ์หนังสือที่ตัวเองเพิ่งออกได้ — ถ้าออกได้
  // แต่พิมพ์ไม่ได้ ต้องไปขอให้งานทะเบียนกดแทนทุกใบ
  @Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
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
  @Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
  @Audit('issued_document', 'id')
  @Header('content-type', 'text/html; charset=utf-8')
  @Get(':id/print')
  print(@Param('id', ParseUuidPipe) id: string, @Query() q: PrintOptionsDto) {
    return this.svc.print(id, {
      paper: q.paper,
      offsetX: q.offsetX === undefined ? undefined : Number(q.offsetX),
      offsetY: q.offsetY === undefined ? undefined : Number(q.offsetY),
      form: q.form,
    });
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

  /**
   * แก้วันสำเร็จการศึกษาของนักศึกษาที่อนุมัติจบไปแล้ว
   *
   * ─── ทำไมแก้ที่ระเบียนจบ ไม่ใช่ใส่ตอนกดพิมพ์ ───
   * `issued_document.payload` ตรึงตั้งแต่วันที่ออกและแก้ไม่ได้ ถ้าให้กรอก
   * วันที่ตอนพิมพ์ คนที่พิมพ์ผิดจะต้องยกเลิกใบแล้วออกใหม่ ซึ่งกินเลขที่
   * เพิ่มทุกครั้งและทิ้งใบที่ยกเลิกไว้ในระบบถาวร — ส่วนการแก้ที่ระเบียนจบ
   * แก้ได้จนกว่าจะพอใจแล้วค่อยออกใบ
   *
   * และวันสำเร็จการศึกษาเป็น**ข้อเท็จจริงของนักศึกษา** ไม่ใช่ของกระดาษใบนั้น
   * ใบทุกใบที่ออกให้คนคนเดียวกันต้องเขียนวันเดียวกันเสมอ
   *
   * ─── แก้ได้เฉพาะวันที่ ───
   * `gpax` กับ `credits_earned` ตรึงตอนอนุมัติจบโดยตั้งใจ (หลักข้อ 5)
   * ถ้าเปิดให้แก้ที่นี่ ตัวเลขบนใบจะเปลี่ยนได้โดยไม่ผ่านมติอนุมัติจบ
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('student_graduation', 'studentId')
  @Patch('students/:studentId/completed-on')
  setCompletedOn(
    @Param('studentId', ParseUuidPipe) studentId: string,
    @Body() dto: CompletedOnDto,
  ) {
    return this.svc.setCompletedOn(studentId, dto);
  }

  @Roles('registrar', 'student_affairs', 'academic', 'director', 'admin')
  @Get('survey/candidates')
  surveyCandidates() {
    return this.svc.surveyCandidates();
  }

  @Roles('registrar', 'student_affairs', 'academic', 'director', 'admin')
  @Audit('graduation_survey_response', 'studentId')
  @Post('survey')
  recordSurvey(@Body() dto: RecordSurveyDto) {
    return this.svc.recordSurvey(dto);
  }

  @Roles('registrar', 'student_affairs', 'academic', 'director', 'admin')
  @Get('survey/summary')
  surveySummary() {
    return this.svc.surveySummary();
  }
}

@Module({
  controllers: [DocumentsController, GraduationController, WorksheetController],
  providers: [DocumentsService, GraduationService, WorksheetService],
  exports: [DocumentsService, GraduationService],
})
export class DocumentsModule {}

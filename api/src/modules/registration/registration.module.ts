import {
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  Post,
  Query,
} from '@nestjs/common';
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsOptional,
  IsString,
} from 'class-validator';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

class CheckDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsArray() @IsUuidArray() sectionIds: string[] = [];
}

class RegisterDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsArray() @ArrayNotEmpty() @IsUuidArray() sectionIds: string[];
}

/**
 * ลงทะเบียนทั้งห้องในครั้งเดียว
 *
 * เพดาน 200 คนไม่ได้มาจากข้อจำกัดทางเทคนิค แต่มาจากรูปแบบการใช้งานจริง —
 * งานทะเบียนลงทะเบียนเป็นห้อง ซึ่งใหญ่สุดราวสี่สิบคน ตัวเลขที่เกินหลักร้อย
 * แปลว่ามีคนกำลังยิงทั้งวิทยาลัยมาในคำขอเดียว ซึ่งจะกลายเป็น transaction
 * ที่ล็อกตาราง enrollment ค้างไว้นานจนคนอื่นลงทะเบียนไม่ได้ทั้งวิทยาลัย
 */
class RegisterBulkDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsUuidArray() studentIds: string[];
  @IsUuid() termId: string;
  @IsArray() @ArrayNotEmpty() @IsUuidArray() sectionIds: string[];
}

class OverrideDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsString() code: string;
  @IsOptional() @IsUuid() classSectionId?: string;
  @IsString() reason: string;
  @IsOptional() @IsString() documentNo?: string;
  @IsUuid() approvedBy: string;
}

export interface RegistrationProblem {
  code: string;
  severity: 'block' | 'warn' | 'info';
  message_th: string;
  class_section_id: string | null;
  waived: boolean;
  detail: Record<string, unknown>;
}

@Injectable()
export class RegistrationService {
  constructor(private readonly db: DbService) {}

  /**
   * คืนรายการปัญหาทั้งหมดในครั้งเดียว ไม่หยุดที่ข้อแรก
   * เพราะนักศึกษาต้องเห็นทุกอย่างที่ต้องแก้ในรอบเดียว ไม่ใช่แก้ทีละข้อแล้วกดใหม่ห้ารอบ
   */
  async check(dto: CheckDto) {
    const problems = await this.db.query<RegistrationProblem>(
      `select code, severity, message_th, class_section_id, waived, detail
         from check_registration($1, $2, $3::uuid[])
        order by case severity when 'block' then 1 when 'warn' then 2 else 3 end, code`,
      [dto.studentId, dto.termId, dto.sectionIds],
    );

    const blocking = problems.filter((p) => p.severity === 'block' && !p.waived);
    return {
      canRegister: blocking.length === 0,
      blockingCount: blocking.length,
      warningCount: problems.filter((p) => p.severity === 'warn').length,
      problems,
    };
  }

  /**
   * ถ้ายังมีข้อ block ที่ไม่ได้ยกเว้น ฟังก์ชันในฐานข้อมูลจะ raise
   * และ transaction ถูก rollback ทั้งหมด — ไม่มีการเขียนบางส่วนค้างไว้
   */
  async register(dto: RegisterDto) {
    const row = await this.db.queryOne<{ registered: number }>(
      `select register_courses($1, $2, $3::uuid[]) as registered`,
      [dto.studentId, dto.termId, dto.sectionIds],
    );
    return { registered: Number(row?.registered ?? 0) };
  }

  /**
   * ต่างจาก register() ตรงที่คนที่ติดเงื่อนไข **ไม่ทำให้คนอื่นล้มไปด้วย**
   *
   * ฟังก์ชันในฐานข้อมูลจึงไม่ raise แต่คืนผลรายคนออกมา ชั้นนี้แค่แปลงรูป
   * ให้หน้าจอใช้ได้ทันที — ใครลงสำเร็จกี่วิชา ใครติดอะไรบ้าง
   */
  async registerBulk(dto: RegisterBulkDto) {
    const rows = await this.db.query<{
      student_id: string;
      registered: number;
      blockers: string | null;
    }>(
      `select student_id, registered, blockers
         from register_courses_bulk($1::uuid[], $2, $3::uuid[])`,
      [dto.studentIds, dto.termId, dto.sectionIds],
    );

    const results = rows.map((r) => ({
      studentId: r.student_id,
      registered: Number(r.registered),
      blockers: r.blockers ? r.blockers.split('\n') : [],
    }));

    return {
      requested: dto.studentIds.length,
      succeeded: results.filter((r) => r.blockers.length === 0).length,
      blocked: results.filter((r) => r.blockers.length > 0).length,
      results,
    };
  }

  /** หลักสูตรไหนลงทะเบียนไปแล้วกี่เปอร์เซ็นต์ — เรียงจากน้อยไปมากเพื่อให้ห้องที่ตกหล่นอยู่บนสุด */
  async progress(termId: string) {
    return this.db.query(
      `select curriculum_id, curriculum_name, shift,
              students_total, students_registered, pct
         from registration_progress($1)`,
      [termId],
    );
  }

  async createOverride(dto: OverrideDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `insert into registration_override
         (student_id, term_id, code, class_section_id, reason, document_no, approved_by)
       values ($1, $2, $3, $4, $5, $6, $7)
       returning id`,
      [
        dto.studentId, dto.termId, dto.code, dto.classSectionId ?? null,
        dto.reason, dto.documentNo ?? null, dto.approvedBy,
      ],
    );
    return { id: row!.id };
  }
}

@Controller('registration')
class RegistrationController {
  constructor(private readonly svc: RegistrationService) {}

  @Post('check')
  check(@Body() dto: CheckDto) {
    return this.svc.check(dto);
  }

  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.svc.register(dto);
  }

  /**
   * ลงทะเบียนเป็นกลุ่ม — เฉพาะเจ้าหน้าที่
   *
   * นักศึกษาลงทะเบียนให้คนอื่นไม่ได้ จึงไม่เปิดให้บทบาท student เรียก
   * ต่างจาก /register ที่นักศึกษาลงของตัวเองได้ (RLS กันไว้อีกชั้นอยู่แล้ว)
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Post('register-bulk')
  registerBulk(@Body() dto: RegisterBulkDto) {
    return this.svc.registerBulk(dto);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Get('progress')
  progress(@Query('termId', ParseUuidPipe) termId: string) {
    return this.svc.progress(termId);
  }

  /** การยกเว้นกฎต้องมีอำนาจ — RLS ในฐานข้อมูลบังคับซ้ำอีกชั้นหนึ่ง */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Post('overrides')
  override(@Body() dto: OverrideDto) {
    return this.svc.createOverride(dto);
  }
}

@Module({
  controllers: [RegistrationController],
  providers: [RegistrationService],
  exports: [RegistrationService],
})
export class RegistrationModule {}

import { Body, Controller, Get, Injectable, Module, Param, Post, Query } from '@nestjs/common';
import { ArrayNotEmpty, IsArray, IsIn, IsNumber, IsOptional, IsString, Max, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { ParseUuidPipe } from '../../common/validation/uuid';

/**
 * ผลสอบ O-NET/V-NET — โครงตารางทั่วไป (ดูคอมเมนต์เต็มที่ migration 0071)
 *
 * ยังไม่เทียบกับรูปแบบไฟล์จริงที่ สอศ./สทศ. ส่งมา รหัส/ชื่อวิชาจึงเป็น
 * ข้อความอิสระที่กรอกตอนวางข้อมูล ไม่ใช่ตารางอ้างอิงที่ตรึงไว้ล่วงหน้า
 */

class ResultRowDto {
  @IsString() studentCode: string;
  @IsOptional() @IsIn(['onet', 'vnet']) examKind?: string;
  @IsString() examYearBe: string;
  @IsString() subjectCode: string;
  @IsString() subjectTh: string;
  @IsNumber() @Min(0) @Max(100) score: number;
}

class BulkResultsDto {
  @IsArray() @ArrayNotEmpty() @ValidateNested({ each: true }) @Type(() => ResultRowDto)
  rows: ResultRowDto[];
}

@Injectable()
export class OnetService {
  constructor(private readonly db: DbService) {}

  async recordBulk(dto: BulkResultsDto) {
    const rows = await this.db.query<{
      row_no: number; student_code: string; subject_code: string; status: string; detail: string | null;
    }>(
      `select row_no, student_code, subject_code, status, detail
         from record_onet_results_bulk($1::jsonb)`,
      [JSON.stringify(dto.rows)],
    );
    const saved = rows.filter((r) => r.status === 'saved').length;
    return { total: rows.length, saved, failed: rows.length - saved, rows };
  }

  async summary(examYearBe?: string, examKind?: string) {
    return this.db.query(
      `select subject_code, subject_th,
              count(*)                          as students,
              round(avg(score), 2)              as avg_score,
              min(score)                        as min_score,
              max(score)                        as max_score
         from national_exam_result
        where ($1::smallint is null or exam_year_be = $1)
          and ($2::text is null or exam_kind = $2)
        group by subject_code, subject_th
        order by subject_code`,
      [examYearBe ?? null, examKind ?? null],
    );
  }

  async forStudent(studentId: string) {
    return this.db.query(
      `select exam_kind, exam_year_be, subject_code, subject_th, score
         from national_exam_result
        where student_id = $1
        order by exam_year_be desc, subject_code`,
      [studentId],
    );
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('onet')
class OnetController {
  constructor(private readonly svc: OnetService) {}

  @Audit('national_exam_result')
  @Post('bulk')
  recordBulk(@Body() dto: BulkResultsDto) {
    return this.svc.recordBulk(dto);
  }

  @Get('summary')
  summary(@Query('examYearBe') examYearBe?: string, @Query('examKind') examKind?: string) {
    return this.svc.summary(examYearBe, examKind);
  }

  @Roles('registrar', 'academic', 'teacher', 'student', 'guardian', 'director', 'admin')
  @Get('students/:studentId')
  forStudent(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.forStudent(studentId);
  }
}

@Module({
  controllers: [OnetController],
  providers: [OnetService],
})
export class OnetModule {}

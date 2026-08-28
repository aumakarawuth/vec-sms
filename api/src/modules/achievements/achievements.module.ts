import { Body, Controller, Delete, Get, Injectable, Module, NotFoundException, Param, Patch, Post } from '@nestjs/common';
import { IsISO8601, IsOptional, IsString, MaxLength } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { ParseUuidPipe } from '../../common/validation/uuid';

/**
 * ผลงานและเกียรติประวัติของนักศึกษา (0090) — บันทึกเหตุการณ์รางวัล/ผลงาน
 * แยกจาก behavior_record เพราะไม่มียอดสะสม (ดูคอมเมนต์ที่ migration)
 */

class CreateAchievementDto {
  @IsString() @MaxLength(300) titleTh: string;
  @IsOptional() @IsString() @MaxLength(100) categoryTh?: string;
  @IsOptional() @IsString() @MaxLength(100) levelTh?: string;
  @IsOptional() @IsString() @MaxLength(200) issuerTh?: string;
  @IsOptional() @IsISO8601() awardedOn?: string;
  @IsOptional() @IsString() noteTh?: string;
}

class UpdateAchievementDto {
  @IsOptional() @IsString() @MaxLength(300) titleTh?: string;
  @IsOptional() @IsString() @MaxLength(100) categoryTh?: string;
  @IsOptional() @IsString() @MaxLength(100) levelTh?: string;
  @IsOptional() @IsString() @MaxLength(200) issuerTh?: string;
  @IsOptional() @IsISO8601() awardedOn?: string;
  @IsOptional() @IsString() noteTh?: string;
}

@Injectable()
export class AchievementsService {
  constructor(private readonly db: DbService) {}

  async listByStudent(studentId: string) {
    return this.db.query(
      `select id, title_th, category_th, level_th, issuer_th, awarded_on, note_th,
              recorded_by, created_at
         from student_achievement
        where student_id = $1
        order by awarded_on desc, created_at desc`,
      [studentId],
    );
  }

  async create(studentId: string, dto: CreateAchievementDto) {
    return this.db.queryOne(
      `insert into student_achievement
         (student_id, title_th, category_th, level_th, issuer_th, awarded_on, note_th, recorded_by)
       values ($1, $2, $3, $4, $5, coalesce($6, current_date), $7, current_actor_id())
       returning id, title_th, category_th, level_th, issuer_th, awarded_on, note_th`,
      [
        studentId, dto.titleTh.trim(), dto.categoryTh ?? null, dto.levelTh ?? null,
        dto.issuerTh ?? null, dto.awardedOn ?? null, dto.noteTh ?? null,
      ],
    );
  }

  async update(id: string, dto: UpdateAchievementDto) {
    const row = await this.db.queryOne(
      `update student_achievement set
         title_th    = coalesce($2, title_th),
         category_th = coalesce($3, category_th),
         level_th    = coalesce($4, level_th),
         issuer_th   = coalesce($5, issuer_th),
         awarded_on  = coalesce($6, awarded_on),
         note_th     = coalesce($7, note_th)
       where id = $1
       returning id, title_th, category_th, level_th, issuer_th, awarded_on, note_th`,
      [id, dto.titleTh ?? null, dto.categoryTh ?? null, dto.levelTh ?? null,
       dto.issuerTh ?? null, dto.awardedOn ?? null, dto.noteTh ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบผลงาน/เกียรติประวัตินี้');
    return row;
  }

  async remove(id: string) {
    const row = await this.db.queryOne(`delete from student_achievement where id = $1 returning id`, [id]);
    if (!row) throw new NotFoundException('ไม่พบผลงาน/เกียรติประวัตินี้');
    return { deleted: true };
  }
}

@Roles('registrar', 'academic', 'student_affairs', 'teacher', 'director', 'admin')
@Controller('students/:studentId/achievements')
class AchievementsController {
  constructor(private readonly svc: AchievementsService) {}

  @Get()
  list(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.listByStudent(studentId);
  }

  @Audit('student_achievement')
  @Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
  @Post()
  create(@Param('studentId', ParseUuidPipe) studentId: string, @Body() dto: CreateAchievementDto) {
    return this.svc.create(studentId, dto);
  }
}

/*
 * แยกคอนโทรลเลอร์แก้ไข/ลบออกจากเส้นทางที่ผูกกับ studentId เพราะ id ของ
 * บันทึกก็ระบุแถวได้อยู่แล้ว ไม่ต้องพก studentId มาซ้ำในทุกเส้นทาง
 */
@Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
@Controller('achievements')
class AchievementRecordController {
  constructor(private readonly svc: AchievementsService) {}

  @Audit('student_achievement', 'id')
  @Patch(':id')
  update(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateAchievementDto) {
    return this.svc.update(id, dto);
  }

  @Audit('student_achievement', 'id')
  @Delete(':id')
  remove(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.remove(id);
  }
}

@Module({
  controllers: [AchievementsController, AchievementRecordController],
  providers: [AchievementsService],
})
export class AchievementsModule {}

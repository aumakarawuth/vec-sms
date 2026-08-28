import { Body, Controller, Delete, Get, Injectable, Module, NotFoundException, Param, Patch, Post, Query } from '@nestjs/common';
import { IsBoolean, IsISO8601, IsOptional, IsString, MaxLength } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { ParseUuidPipe } from '../../common/validation/uuid';

/**
 * ประกาศ/ข่าวสารถึงนักศึกษา (0091) — รวมสองเมนูเดิมของศูนย์นักศึกษา
 * "การประชาสัมพันธ์" และ "ไปรษณีย์" เป็นระบบเดียว (ดูคอมเมนต์ที่ migration)
 */

class CreateAnnouncementDto {
  @IsString() @MaxLength(300) titleTh: string;
  @IsString() bodyTh: string;
  @IsOptional() @IsString() @MaxLength(100) categoryTh?: string;
  @IsOptional() @IsISO8601() expiresOn?: string;
  /** เผยแพร่ทันทีเมื่อสร้าง — ไม่ส่งมาแปลว่าบันทึกเป็นฉบับร่างก่อน */
  @IsOptional() @IsBoolean() publishNow?: boolean;
}

class UpdateAnnouncementDto {
  @IsOptional() @IsString() @MaxLength(300) titleTh?: string;
  @IsOptional() @IsString() bodyTh?: string;
  @IsOptional() @IsString() @MaxLength(100) categoryTh?: string;
  @IsOptional() @IsISO8601() expiresOn?: string;
}

@Injectable()
export class AnnouncementsService {
  constructor(private readonly db: DbService) {}

  /** รายการทั้งหมดของวิทยาลัย รวมฉบับร่าง — หน้าจอนี้เป็นของเจ้าหน้าที่เท่านั้น */
  async list(includeExpired?: boolean) {
    return this.db.query(
      `select a.id, a.title_th, a.category_th, a.published_at, a.expires_on, a.created_at,
              trim(coalesce(p.prefix_th,'') || p.first_name_th || ' ' || p.last_name_th) as author_name
         from announcement a
         join person p on p.id = a.created_by
        where $1 or a.expires_on is null or a.expires_on >= current_date
        order by coalesce(a.published_at, a.created_at) desc`,
      [includeExpired ?? false],
    );
  }

  async get(id: string) {
    return this.db.queryOne(
      `select id, title_th, body_th, category_th, published_at, expires_on, created_at
         from announcement where id = $1`,
      [id],
    );
  }

  async create(dto: CreateAnnouncementDto) {
    return this.db.queryOne(
      `insert into announcement (institution_id, title_th, body_th, category_th, expires_on, published_at, created_by)
       values (current_institution_id(), $1, $2, $3, $4, case when $5 then now() else null end, current_actor_id())
       returning id, title_th, published_at`,
      [dto.titleTh.trim(), dto.bodyTh, dto.categoryTh ?? null, dto.expiresOn ?? null, dto.publishNow ?? false],
    );
  }

  async update(id: string, dto: UpdateAnnouncementDto) {
    const row = await this.db.queryOne(
      `update announcement set
         title_th    = coalesce($2, title_th),
         body_th     = coalesce($3, body_th),
         category_th = coalesce($4, category_th),
         expires_on  = coalesce($5, expires_on)
       where id = $1
       returning id, title_th, published_at`,
      [id, dto.titleTh ?? null, dto.bodyTh ?? null, dto.categoryTh ?? null, dto.expiresOn ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบประกาศนี้');
    return row;
  }

  /** เผยแพร่ — ตั้งเวลาเป็นตอนนี้ ไม่ทับเวลาเดิมถ้าเผยแพร่ไปแล้ว */
  async publish(id: string) {
    const row = await this.db.queryOne(
      `update announcement set published_at = coalesce(published_at, now())
        where id = $1
      returning id, published_at`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบประกาศนี้');
    return row;
  }

  /** ถอนออกจากการเผยแพร่ — กลับไปเป็นฉบับร่าง */
  async unpublish(id: string) {
    const row = await this.db.queryOne(
      `update announcement set published_at = null where id = $1 returning id, published_at`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบประกาศนี้');
    return row;
  }

  async remove(id: string) {
    const row = await this.db.queryOne(`delete from announcement where id = $1 returning id`, [id]);
    if (!row) throw new NotFoundException('ไม่พบประกาศนี้');
    return { deleted: true };
  }
}

@Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
@Controller('announcements')
class AnnouncementsController {
  constructor(private readonly svc: AnnouncementsService) {}

  @Get()
  list(@Query('includeExpired') includeExpired?: string) {
    return this.svc.list(includeExpired === 'true');
  }

  @Get(':id')
  get(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.get(id);
  }

  @Audit('announcement')
  @Post()
  create(@Body() dto: CreateAnnouncementDto) {
    return this.svc.create(dto);
  }

  @Audit('announcement', 'id')
  @Patch(':id')
  update(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateAnnouncementDto) {
    return this.svc.update(id, dto);
  }

  @Audit('announcement', 'id')
  @Post(':id/publish')
  publish(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.publish(id);
  }

  @Audit('announcement', 'id')
  @Post(':id/unpublish')
  unpublish(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.unpublish(id);
  }

  @Audit('announcement', 'id')
  @Delete(':id')
  remove(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.remove(id);
  }
}

@Module({
  controllers: [AnnouncementsController],
  providers: [AnnouncementsService],
})
export class AnnouncementsModule {}

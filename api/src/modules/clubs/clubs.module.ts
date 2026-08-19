import { Body, Controller, Delete, Get, Injectable, Module, Param, Post, Query } from '@nestjs/common';
import { IsBoolean, IsIn, IsISO8601, IsOptional, IsString, MaxLength } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * วิชาชุมนุม/ชมรม — บันทึกพื้นฐาน
 *
 * ยังไม่ผูกกับเกณฑ์จบ "กิจกรรมเสริมหลักสูตรผ่านทุกภาคเรียน" หรือหน่วยกิต
 * กิจกรรม — ต้องตัดสินใจกติกาการนับ "ผ่าน" ก่อน (ดูคอมเมนต์ที่ 0070)
 */

class CreateClubDto {
  @IsString() @MaxLength(40) code: string;
  @IsString() @MaxLength(200) nameTh: string;
  @IsOptional() @IsString() categoryTh?: string;
  @IsOptional() @IsUuid() advisorStaffId?: string;
  @IsOptional() @IsString() descriptionTh?: string;
}

class UpdateClubDto {
  @IsOptional() @IsString() @MaxLength(200) nameTh?: string;
  @IsOptional() @IsString() categoryTh?: string;
  @IsOptional() @IsUuid() advisorStaffId?: string;
  @IsOptional() @IsString() descriptionTh?: string;
  @IsOptional() @IsBoolean() active?: boolean;
}

class AddMemberDto {
  @IsUuid() studentId: string;
  @IsUuid() academicYearId: string;
  @IsOptional() @IsIn(['member', 'leader']) role?: string;
  @IsOptional() @IsISO8601() joinedOn?: string;
}

@Injectable()
export class ClubsService {
  constructor(private readonly db: DbService) {}

  async list() {
    return this.db.query(
      `select c.id, c.code, c.name_th, c.category_th, c.active,
              st.staff_code as advisor_code,
              trim(coalesce(p.prefix_th,'') || p.first_name_th || ' ' || p.last_name_th) as advisor_name,
              (select count(*) from club_member cm where cm.club_id = c.id and cm.left_on is null) as members
         from club c
         left join staff st  on st.id = c.advisor_staff_id
         left join person p  on p.id = st.person_id
        order by c.active desc, c.name_th`,
    );
  }

  async create(dto: CreateClubDto) {
    return this.db.queryOne(
      `insert into club (institution_id, code, name_th, category_th, advisor_staff_id, description_th)
       values (current_institution_id(), $1, $2, $3, $4, $5)
       returning id, code, name_th`,
      [dto.code.trim(), dto.nameTh.trim(), dto.categoryTh ?? null, dto.advisorStaffId ?? null, dto.descriptionTh ?? null],
    );
  }

  async update(id: string, dto: UpdateClubDto) {
    return this.db.queryOne(
      `update club set
         name_th          = coalesce($2, name_th),
         category_th      = coalesce($3, category_th),
         advisor_staff_id = coalesce($4, advisor_staff_id),
         description_th   = coalesce($5, description_th),
         active           = coalesce($6, active)
       where id = $1
       returning id, code, name_th, active`,
      [id, dto.nameTh ?? null, dto.categoryTh ?? null, dto.advisorStaffId ?? null,
       dto.descriptionTh ?? null, dto.active ?? null],
    );
  }

  async members(clubId: string, academicYearId?: string) {
    return this.db.query(
      `select cm.id, cm.role, cm.joined_on, cm.left_on,
              s.id as student_id, s.student_code,
              trim(coalesce(p.prefix_th,'') || p.first_name_th || ' ' || p.last_name_th) as full_name
         from club_member cm
         join student s on s.id = cm.student_id
         join person p  on p.id = s.person_id
        where cm.club_id = $1
          and ($2::uuid is null or cm.academic_year_id = $2)
        order by cm.role desc, p.first_name_th`,
      [clubId, academicYearId ?? null],
    );
  }

  async addMember(clubId: string, dto: AddMemberDto) {
    return this.db.queryOne(
      `insert into club_member (club_id, student_id, academic_year_id, role, joined_on)
       values ($1, $2, $3, coalesce($4, 'member'), coalesce($5, current_date))
       returning id, student_id, role`,
      [clubId, dto.studentId, dto.academicYearId, dto.role ?? null, dto.joinedOn ?? null],
    );
  }

  async removeMember(clubId: string, memberId: string) {
    const row = await this.db.queryOne(
      `update club_member set left_on = current_date
        where id = $1 and club_id = $2 and left_on is null
      returning id`,
      [memberId, clubId],
    );
    return { removed: !!row };
  }
}

@Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
@Controller('clubs')
class ClubsController {
  constructor(private readonly svc: ClubsService) {}

  @Get()
  list() {
    return this.svc.list();
  }

  @Audit('club')
  @Post()
  create(@Body() dto: CreateClubDto) {
    return this.svc.create(dto);
  }

  @Audit('club', 'id')
  @Post(':id')
  update(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateClubDto) {
    return this.svc.update(id, dto);
  }

  @Get(':id/members')
  members(@Param('id', ParseUuidPipe) id: string, @Query('academicYearId') academicYearId?: string) {
    return this.svc.members(id, academicYearId);
  }

  @Audit('club_member', 'id')
  @Post(':id/members')
  addMember(@Param('id', ParseUuidPipe) id: string, @Body() dto: AddMemberDto) {
    return this.svc.addMember(id, dto);
  }

  @Audit('club_member', 'memberId')
  @Delete(':id/members/:memberId')
  removeMember(
    @Param('id', ParseUuidPipe) id: string,
    @Param('memberId', ParseUuidPipe) memberId: string,
  ) {
    return this.svc.removeMember(id, memberId);
  }
}

@Module({
  controllers: [ClubsController],
  providers: [ClubsService],
})
export class ClubsModule {}

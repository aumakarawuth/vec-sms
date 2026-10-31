import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { IsBoolean, IsIn, IsISO8601, IsOptional, IsString } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { RequestContext } from '../../common/context/request-context';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { PageParams, parsePage, toPage } from '../../common/pagination/pagination';

/**
 * บุคลากรและสิทธิ
 *
 * ─── ทำไมโมดูลนี้สำคัญกว่าที่เห็น ───
 * ก่อน migration 0022 บทบาท registrar, finance, academic, director และ admin
 * ไม่มีทางผูกกับคนจริงได้เลย ทุกคนที่เป็นบุคลากรจะได้ teacher เสมอ
 * นโยบาย RLS ที่เขียนไว้อย่างละเอียดสำหรับบทบาทเหล่านั้นจึงไม่เคยถูกใช้
 *
 * โมดูลนี้คือทางที่ทำให้ระบบสิทธิทั้งระบบมีความหมายขึ้นมาจริง ๆ
 */

const ROLE_KINDS = [
  'registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin',
  'secretary', 'hr',
] as const;

class GrantRoleDto {
  @IsIn(ROLE_KINDS as unknown as string[]) role: string;
  @IsOptional() @IsISO8601() effectiveFrom?: string;
  @IsOptional() @IsISO8601() effectiveTo?: string;
  @IsOptional() @IsString() reason?: string;
}

class RevokeRoleDto {
  @IsString() reason: string;
  /**
   * ตั้งวันสิ้นสุดวาระล่วงหน้าแทนการตัดสิทธิ์ทันที
   * ใช้กับกรณีที่รู้อยู่แล้วว่าวาระจบเมื่อไร เช่นรักษาการถึงสิ้นเดือน
   */
  @IsOptional() @IsISO8601() effectiveTo?: string;
}

/** ข้อมูลที่ฝ่ายบุคคลแก้ได้โดยไม่แตะประวัติสิทธิ์ของบุคลากร */
class UpdateStaffProfileDto {
  @IsOptional() @IsString() phone?: string | null;
  @IsOptional() @IsString() email?: string | null;
  @IsOptional() @IsIn(['civil_servant', 'permanent', 'contract', 'part_time', 'industry_expert']) employmentKind?: string;
  @IsOptional() @IsBoolean() isTeacher?: boolean;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @IsString() licenseNo?: string | null;
  @IsOptional() @IsISO8601() licenseExpires?: string | null;
}

class AuditQueryDto {
  @IsOptional() @IsUuid() subjectId?: string;
  @IsOptional() @IsUuid() actorId?: string;
  @IsOptional() @IsString() entity?: string;
  @IsOptional() @IsISO8601() from?: string;
  @IsOptional() @IsISO8601() to?: string;
}

@Injectable()
export class StaffService {
  constructor(private readonly db: DbService) {}

  async list(q: string | undefined, roleFilter: string | undefined, page: PageParams) {
    const rows = await this.db.query(
      `select st.id, st.staff_code, st.employment_kind, st.is_teacher, st.active,
              p.id as person_id,
              coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '') || ' ' ||
                coalesce(p.last_name_th, '') as full_name,
              p.phone, p.email,
              coalesce(
                array_agg(sr.role::text order by sr.role)
                  filter (where sr.id is not null
                            and sr.revoked_at is null
                            and sr.effective_from <= current_date
                            and (sr.effective_to is null or sr.effective_to >= current_date)),
                '{}'
              ) as roles,
              effective_staff_role(p.id) as effective_role
         from staff st
         join person p on p.id = st.person_id
         left join staff_role sr on sr.staff_id = st.id
        where ($1::text is null
               or p.first_name_th ilike '%' || $1 || '%'
               or p.last_name_th  ilike '%' || $1 || '%'
               or st.staff_code   ilike '%' || $1 || '%')
        group by st.id, p.id
        having ($2::text is null or $2 = any(
          array_agg(sr.role::text) filter (
            where sr.revoked_at is null
              and sr.effective_from <= current_date
              and (sr.effective_to is null or sr.effective_to >= current_date))))
        order by st.staff_code
        limit $3 offset $4`,
      [q ?? null, roleFilter ?? null, page.limit + 1, page.offset],
    );
    return toPage(rows, page);
  }

  async detail(staffId: string) {
    return this.db.tx(async (c) => {
      const staff = (
        await c.query(
          `select st.id, st.staff_code, st.employment_kind, st.is_teacher,
                  st.license_no, st.license_expires, st.active,
                  p.id as person_id,
                  coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '') || ' ' ||
                    coalesce(p.last_name_th, '') as full_name,
                  p.phone, p.email,
                  effective_staff_role(p.id) as effective_role
             from staff st join person p on p.id = st.person_id
            where st.id = $1`,
          [staffId],
        )
      ).rows[0];
      if (!staff) throw new ForbiddenException('ไม่พบบุคลากรนี้ หรือไม่มีสิทธิ์เข้าถึง');

      // ประวัติทั้งหมด ไม่ใช่เฉพาะที่ใช้อยู่ — ผู้ตรวจสอบถามว่า
      // "ตอนอนุมัติเกรดใบนั้นเมื่อปีที่แล้ว คนนี้มีสิทธิ์ไหม"
      const roles = (
        await c.query(
          `select sr.id, sr.role, sr.effective_from, sr.effective_to,
                  sr.reason, sr.created_at, sr.revoked_at, sr.revoke_reason,
                  gp.first_name_th || ' ' || gp.last_name_th as granted_by_name,
                  (sr.revoked_at is null
                   and sr.effective_from <= current_date
                   and (sr.effective_to is null or sr.effective_to >= current_date)) as active_now
             from staff_role sr
             left join staff  gs on gs.id = sr.granted_by
             left join person gp on gp.id = gs.person_id
            where sr.staff_id = $1
            order by sr.effective_from desc, sr.role`,
          [staffId],
        )
      ).rows;

      const sections = (
        await c.query(
          `select cs.id, co.code, co.name_th, cs.section_no,
                  count(e.id) as students
             from class_section cs
             join course co on co.id = cs.course_id
             left join enrollment e on e.class_section_id = cs.id and e.status = 'enrolled'
            where cs.teacher_id = $1
            group by cs.id, co.code, co.name_th, cs.section_no
            order by co.code`,
          [staffId],
        )
      ).rows;

      return { ...staff, roles, sections };
    });
  }

  /** แก้เฉพาะข้อมูลการติดต่อ/การจ้าง/ใบอนุญาต ไม่ใช้เส้นทางนี้มอบสิทธิ์ระบบ */
  async updateProfile(staffId: string, dto: UpdateStaffProfileDto) {
    return this.db.tx(async (c) => {
      const personSets: string[] = [];
      const personValues: unknown[] = [staffId];
      const addPerson = (column: string, value: unknown) => {
        personValues.push(value);
        personSets.push(`${column} = $${personValues.length}`);
      };
      if (dto.phone !== undefined) addPerson('phone', dto.phone || null);
      if (dto.email !== undefined) addPerson('email', dto.email || null);
      if (personSets.length) {
        await c.query(
          `update person p set ${personSets.join(', ')}
             from staff st where st.id = $1 and p.id = st.person_id`,
          personValues,
        );
      }

      const staffSets: string[] = [];
      const staffValues: unknown[] = [staffId];
      const addStaff = (column: string, value: unknown) => {
        staffValues.push(value);
        staffSets.push(`${column} = $${staffValues.length}`);
      };
      if (dto.employmentKind !== undefined) addStaff('employment_kind', dto.employmentKind);
      if (dto.isTeacher !== undefined) addStaff('is_teacher', dto.isTeacher);
      if (dto.active !== undefined) addStaff('active', dto.active);
      if (dto.licenseNo !== undefined) addStaff('license_no', dto.licenseNo || null);
      if (dto.licenseExpires !== undefined) addStaff('license_expires', dto.licenseExpires || null);
      if (staffSets.length) {
        await c.query(`update staff set ${staffSets.join(', ')} where id = $1`, staffValues);
      }
      return { updated: true };
    });
  }

  /**
   * มอบหมายบทบาท
   *
   * ไม่ตรวจการซ้อนช่วงเวลาที่นี่ เพราะ exclusion constraint ในฐานข้อมูล
   * ตรวจให้แล้ว และตรวจได้ทุกทางที่เขียนเข้ามา ไม่ใช่แค่ทางนี้
   */
  async grant(staffId: string, dto: GrantRoleDto) {
    return this.db.queryOne(
      `insert into staff_role
         (staff_id, role, effective_from, effective_to, granted_by, reason)
       values ($1, $2::staff_role_kind, coalesce($3::date, current_date), $4,
               (select id from staff where person_id = current_actor_id()), $5)
       returning id, role, effective_from, effective_to, reason`,
      [staffId, dto.role, dto.effectiveFrom ?? null, dto.effectiveTo ?? null, dto.reason ?? null],
    );
  }

  /**
   * ถอนบทบาท — ปิดสิทธิ์ ไม่ใช่ลบแถว
   *
   * ลบแถวทิ้งทำให้ตอบไม่ได้ว่าเมื่อก่อนใครมีสิทธิ์อะไร ซึ่งเป็นข้อมูล
   * ที่ต้องใช้ตอนตรวจสอบย้อนหลังว่าการอนุมัติในอดีตชอบด้วยสิทธิ์หรือไม่
   *
   * ─── ตัดทันที เว้นแต่ระบุวันสิ้นสุดมา ───
   * ค่าเริ่มต้นคือ revoked_at = now() ซึ่งมีผลเดี๋ยวนั้น เพราะกรณีที่ต้อง
   * ใช้จริงคือพบการใช้สิทธิ์ในทางมิชอบหรือถูกให้ออกจากงาน การรอถึงพรุ่งนี้
   * ไม่ใช่ทางเลือก และบทบาทที่เพิ่งมอบวันนี้ก็ตั้ง effective_to ย้อนหลังไม่ได้
   */
  async revoke(roleId: string, dto: RevokeRoleDto) {
    const row = await this.db.queryOne(
      `update staff_role
          set revoked_at    = case when $2::date is null then now() end,
              revoked_by    = case when $2::date is null
                                   then (select id from staff
                                          where person_id = current_actor_id()) end,
              revoke_reason = case when $2::date is null then $3 end,
              effective_to  = coalesce($2::date, effective_to)
        where id = $1
          and revoked_at is null
          and (effective_to is null or effective_to >= current_date)
        returning id, role, effective_from, effective_to, revoked_at`,
      [roleId, dto.effectiveTo ?? null, dto.reason],
    );
    if (!row) {
      throw new ForbiddenException('ไม่พบบทบาทที่ยังใช้อยู่นี้ หรือไม่มีสิทธิ์ถอน');
    }
    return row;
  }

  /** บทบาทของฉันเอง — หน้าจอไหนก็ตามที่ต้องรู้ว่าตัวเองทำอะไรได้ */
  async me() {
    const ctx = RequestContext.get()!;
    const row = await this.db.queryOne(
      `select $1::text as role,
              effective_staff_role(current_actor_id()) as assigned_role,
              (select st.id from staff st where st.person_id = current_actor_id()) as staff_id,
              coalesce((select array_agg(sr.role::text order by sr.role)
                          from staff_role sr
                          join staff st2 on st2.id = sr.staff_id
                         where st2.person_id = current_actor_id()
                           and sr.revoked_at is null
                           and sr.effective_from <= current_date
                           and (sr.effective_to is null or sr.effective_to >= current_date)),
                       '{}') as roles`,
      [ctx.role],
    );
    return row;
  }

  // ─── บันทึกการเข้าถึง ──────────────────────────────────────────

  async auditLog(filter: AuditQueryDto) {
    return this.db.query(
      `select al.id, al.action, al.entity, al.entity_id, al.route,
              al.actor_role, al.detail, al.occurred_at,
              ap.first_name_th || ' ' || ap.last_name_th as actor_name,
              sp.first_name_th || ' ' || sp.last_name_th as subject_name
         from access_log al
         left join person ap on ap.id = al.actor_id
         left join person sp on sp.id = al.subject_id
        where ($1::uuid is null or al.subject_id = $1)
          and ($2::uuid is null or al.actor_id   = $2)
          and ($3::text is null or al.entity     = $3)
          and ($4::date is null or al.occurred_at >= $4::date)
          and ($5::date is null or al.occurred_at <  $5::date + 1)
        order by al.occurred_at desc
        limit 500`,
      [filter.subjectId ?? null, filter.actorId ?? null, filter.entity ?? null,
       filter.from ?? null, filter.to ?? null],
    );
  }

  /**
   * ใครเข้าถึงข้อมูลของฉันบ้าง
   *
   * PDPA มาตรา 30 ให้สิทธิเจ้าของข้อมูลขอทราบว่าข้อมูลตนถูกใช้อย่างไร
   * RLS บน access_log ยอมให้เห็นเฉพาะแถวที่ subject_id เป็นตัวเอง
   * จึงไม่ต้องกรองซ้ำที่นี่ — และถ้าเผลอกรองผิดก็ยังไม่รั่ว
   */
  async myAccessHistory() {
    return this.db.query(
      `select al.action, al.entity, al.route, al.actor_role, al.occurred_at,
              ap.first_name_th || ' ' || ap.last_name_th as actor_name
         from access_log al
         left join person ap on ap.id = al.actor_id
        where al.subject_id = current_actor_id()
        order by al.occurred_at desc
        limit 200`,
    );
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('staff')
class StaffController {
  constructor(private readonly svc: StaffService) {}

  @Get()
  list(
    @Query('q') q?: string,
    @Query('role') role?: string,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
  ) {
    return this.svc.list(q, role, parsePage(limit, offset));
  }

  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'finance', 'student_affairs', 'director', 'admin',
  )
  @Get('me')
  me() {
    return this.svc.me();
  }

  @Get(':id')
  detail(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.detail(id);
  }

  @Audit('staff_profile')
  @Patch(':id/profile')
  updateProfile(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateStaffProfileDto) {
    return this.svc.updateProfile(id, dto);
  }

  /**
   * มอบหมายและถอนบทบาทเป็นของผู้ดูแลระบบและผู้อำนวยการเท่านั้น
   *
   * ฐานข้อมูลบังคับซ้ำอีกชั้นด้วยนโยบาย staff_role_write เพราะถ้าบทบาทอื่น
   * เขียนตารางนี้ได้ จะยกระดับตัวเองเป็น admin ในคำสั่งเดียว
   * แล้วสิทธิทั้งระบบก็ไม่มีความหมาย
   */
  @Roles('admin', 'director')
  @Audit('staff_role')
  @Post(':id/roles')
  grant(@Param('id', ParseUuidPipe) id: string, @Body() dto: GrantRoleDto) {
    return this.svc.grant(id, dto);
  }

  @Roles('admin', 'director')
  @Audit('staff_role')
  @Patch('roles/:roleId/revoke')
  revoke(@Param('roleId', ParseUuidPipe) roleId: string, @Body() dto: RevokeRoleDto) {
    return this.svc.revoke(roleId, dto);
  }
}

@Controller('audit')
class AuditController {
  constructor(private readonly svc: StaffService) {}

  @Roles('admin', 'director')
  @Get()
  log(@Query() filter: AuditQueryDto) {
    return this.svc.auditLog(filter);
  }

  /** เจ้าของข้อมูลดูได้ว่าใครเข้าถึงข้อมูลตนบ้าง — PDPA มาตรา 30 */
  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'finance', 'student_affairs', 'director', 'admin',
  )
  @Get('me')
  mine() {
    return this.svc.myAccessHistory();
  }
}

@Module({
  controllers: [StaffController, AuditController],
  providers: [StaffService],
  exports: [StaffService],
})
export class StaffModule {}

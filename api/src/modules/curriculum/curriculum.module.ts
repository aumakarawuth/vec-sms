import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import {
  IsIn,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * หลักสูตรฐานสมรรถนะ
 *
 * ─── อ่านได้ทุกบทบาท แก้ได้เฉพาะฝ่ายวิชาการ ───
 * โครงสร้างหลักสูตรเป็นข้อมูลที่ทุกคนต้องใช้ — นักศึกษาดูว่าต้องเรียนอะไรอีก
 * ครูดูว่ารายวิชาที่สอนอยู่หมวดไหน งานทะเบียนใช้ตรวจการลงทะเบียน
 * แต่การแก้กระทบการตรวจจบของทุกคนย้อนหลัง นโยบาย academic_write_only
 * ใน migration 0017 บังคับไว้แล้วอีกชั้น
 *
 * ─── ทำไมการออกฉบับใหม่ต้องเป็นฟังก์ชันในฐานข้อมูล ───
 * ฉบับหลักสูตรหนึ่งมีหมวดวิชาเป็นต้นไม้ รายวิชา สมรรถนะ เส้นทางเข้า
 * และเงื่อนไขจบ การคัดลอกด้วยมือทีละตารางพลาดง่ายมาก และถ้าคัดลอก
 * ไม่ครบจะรู้ตัวตอนนักศึกษารุ่นใหม่ตรวจจบไม่ผ่านโดยไม่มีสาเหตุ
 */

const REQUIREMENT = ['required', 'elective'] as const;
const CATEGORY_KIND = [
  'core_competency', 'vocational', 'voc_basic', 'voc_specific',
  'voc_elective', 'practicum', 'project', 'free_elective', 'activity',
] as const;

class CloneVersionDto {
  @IsInt() @Min(2500) @Max(2700) editionBe: number;
  @IsInt() @Min(2500) @Max(2700) effectiveFromYearBe: number;
  @IsOptional() @IsInt() @Min(2500) @Max(2700) effectiveToYearBe?: number;
  @IsOptional() @IsString() note?: string;
}

class AddCourseDto {
  @IsUuid() courseId: string;
  @IsUuid() curriculumCategoryId: string;
  @IsOptional() @IsIn(REQUIREMENT as unknown as string[]) requirement?: string;
  @IsOptional() @IsInt() @Min(1) @Max(4) suggestedYear?: number;
  @IsOptional() @IsInt() @Min(1) @Max(3) suggestedTerm?: number;
  @IsOptional() @IsInt() sortOrder?: number;
}

/** แก้ทีละรายวิชา — ทุกช่องเป็นตัวเลือก ส่งมาเฉพาะที่จะเปลี่ยน */
class UpdateCourseDto {
  @IsOptional() @IsIn(REQUIREMENT as unknown as string[]) requirement?: string;
  @IsOptional() @IsInt() @Min(1) @Max(4) suggestedYear?: number;
  @IsOptional() @IsInt() @Min(1) @Max(3) suggestedTerm?: number;
  @IsOptional() @IsInt() @Min(0) sortOrder?: number;
}

class ReorderCoursesDto {
  /** ลำดับใหม่ทั้งชุด — ตำแหน่งในอาร์เรย์คือ sort_order ที่จะได้ */
  @IsUuidArray() courseIds: string[];
}

class CategoryDto {
  @IsString() @MaxLength(40) code: string;
  @IsString() nameTh: string;
  @IsIn(CATEGORY_KIND as unknown as string[]) kind: string;
  @IsOptional() @IsUuid() parentId?: string;
  @IsOptional() @IsNumber() @Min(0) minCredits?: number;
  @IsOptional() @IsNumber() @Min(0) maxCredits?: number;
  @IsOptional() @IsInt() sortOrder?: number;
}

@Injectable()
export class CurriculumService {
  constructor(private readonly db: DbService) {}

  /** ต้นไม้ของโปรแกรม → แขนง → หลักสูตร → ฉบับ */
  async listPrograms() {
    return this.db.query(
      `select pt.code as type_code, pt.name_th as type_name,
              pr.id as program_id, pr.code as program_code, pr.name_th as program_name,
              tr.id as track_id, tr.code as track_code, tr.name_th as track_name,
              cu.id as curriculum_id,
              count(cv.id) as versions
         from program_type pt
         join program       pr on pr.program_type_id = pt.id
         left join program_track tr on tr.program_id = pr.id
         left join curriculum    cu on cu.program_track_id = tr.id
         left join curriculum_version cv on cv.curriculum_id = cu.id
        group by pt.code, pt.name_th, pr.id, pr.code, pr.name_th,
                 tr.id, tr.code, tr.name_th, cu.id
        order by pt.code, pr.code, tr.code`,
    );
  }

  async listVersions(curriculumId?: string) {
    return this.db.query(
      `select cv.id, cv.edition_be, cv.effective_from_year_be, cv.effective_to_year_be,
              cv.status, cv.min_total_credits, cv.min_gpax, cv.min_practicum_hours,
              cv.requires_prof_standard, cv.requires_all_activity, cv.normal_duration_terms,
              cv.approved_at,
              gs.code as grade_scheme_code,
              (select count(*) from curriculum_course cc where cc.curriculum_version_id = cv.id) as courses,
              (select count(*) from graduation_rule gr where gr.curriculum_version_id = cv.id)   as rules,
              (select count(*) from student_curriculum sc where sc.curriculum_version_id = cv.id) as students
         from curriculum_version cv
         left join grade_scheme gs on gs.id = cv.grade_scheme_id
        where ($1::uuid is null or cv.curriculum_id = $1)
        order by cv.effective_from_year_be desc, cv.edition_be desc`,
      [curriculumId ?? null],
    );
  }

  /**
   * โครงสร้างเต็มของฉบับหนึ่ง — หมวดวิชาเป็นต้นไม้พร้อมรายวิชาในแต่ละหมวด
   *
   * คืนเป็นโครงสร้างซ้อนชั้นให้เลย เพราะหน้าจอทุกที่ที่ใช้ข้อมูลชุดนี้
   * ต้องประกอบต้นไม้เองอยู่ดี การให้ทุกฝั่งเขียนโค้ดประกอบเองแปลว่า
   * จะมีวิธีประกอบหลายแบบที่ไม่ตรงกัน
   */
  async structure(versionId: string) {
    return this.db.tx(async (c) => {
      const version = (
        await c.query(
          `select cv.*, gs.code as grade_scheme_code, gs.name_th as grade_scheme_name
             from curriculum_version cv
             left join grade_scheme gs on gs.id = cv.grade_scheme_id
            where cv.id = $1`,
          [versionId],
        )
      ).rows[0];
      if (!version) throw new ForbiddenException('ไม่พบฉบับหลักสูตรนี้ หรือไม่มีสิทธิ์เข้าถึง');

      const categories = (
        await c.query(
          `select id, parent_id, kind, code, name_th,
                  min_credits, max_credits, sort_order
             from curriculum_category
            where curriculum_version_id = $1
            order by sort_order, code`,
          [versionId],
        )
      ).rows;

      const courses = (
        await c.query(
          `select cc.id, cc.curriculum_category_id, cc.requirement,
                  cc.suggested_year, cc.suggested_term, cc.sort_order,
                  co.id as course_id, co.code, co.name_th,
                  co.theory_hours, co.practice_hours, co.credits, co.total_hours,
                  co.is_practicum, co.is_project
             from curriculum_course cc
             join course co on co.id = cc.course_id
            where cc.curriculum_version_id = $1
            order by cc.sort_order, co.code`,
          [versionId],
        )
      ).rows;

      const rules = (
        await c.query(
          `select id, kind, name_th, params, threshold, is_blocking, sort_order
             from graduation_rule where curriculum_version_id = $1
            order by sort_order`,
          [versionId],
        )
      ).rows;

      const pathways = (
        await c.query(
          `select ep.id, ep.code, ep.name_th, ep.extra_min_credits, ep.note,
                  count(pb.id) as bridging_courses
             from entry_pathway ep
             left join pathway_bridging_course pb on pb.entry_pathway_id = ep.id
            where ep.curriculum_version_id = $1
            group by ep.id
            order by ep.code`,
          [versionId],
        )
      ).rows;

      // ประกอบต้นไม้ — หมวดวิชาอาชีวะซ้อนสองชั้น (หมวด → กลุ่มวิชา)
      type Cat = Record<string, unknown> & { id: string; parent_id: string | null };
      const byParent = new Map<string | null, Cat[]>();
      for (const cat of categories as Cat[]) {
        const key = cat.parent_id;
        if (!byParent.has(key)) byParent.set(key, []);
        byParent.get(key)!.push(cat);
      }

      const build = (parentId: string | null): unknown[] =>
        (byParent.get(parentId) ?? []).map((cat) => ({
          ...cat,
          courses: courses.filter(
            (co: { curriculum_category_id: string }) =>
              co.curriculum_category_id === cat.id,
          ),
          children: build(cat.id),
        }));

      return {
        ...version,
        categories: build(null),
        // รายวิชาที่ไม่ได้สังกัดหมวดไหนเลย — ผิดปกติ แต่ต้องเห็น ไม่ใช่ซ่อน
        uncategorized: courses.filter(
          (co: { curriculum_category_id: string | null }) => !co.curriculum_category_id,
        ),
        graduationRules: rules,
        entryPathways: pathways,
      };
    });
  }

  /**
   * เกณฑ์หน่วยกิตรายหมวดของนักศึกษาคนหนึ่ง — ใช้ในหน้า "เส้นทางสู่การจบ"
   *
   * v_student_credits_by_category คืนแค่ category_id กับหน่วยกิตที่ได้
   * ต้อง join หมวดวิชาเองเพื่อให้ได้ชื่อและเกณฑ์ขั้นต่ำมาเทียบ
   * หมวดที่ยังไม่ได้หน่วยกิตเลยต้องขึ้นด้วย จึง left join จากฝั่งหมวด
   */
  async studentCredits(studentId: string) {
    return this.db.query(
      `select cat.id as category_id, cat.code as category_code,
              cat.name_th as category_name, cat.kind,
              cat.min_credits, cat.max_credits,
              coalesce(cbc.credits_earned, 0) as credits_earned,
              coalesce(cbc.credits_earned, 0) >= coalesce(cat.min_credits, 0) as satisfied
         from student_curriculum sc
         join curriculum_category cat on cat.curriculum_version_id = sc.curriculum_version_id
         left join v_student_credits_by_category cbc
                on cbc.category_id = cat.id and cbc.student_id = sc.student_id
        where sc.student_id = $1
          and sc.effective_to is null
        order by cat.sort_order, cat.code`,
      [studentId],
    );
  }

  async addCategory(versionId: string, dto: CategoryDto) {
    return this.db.queryOne(
      `insert into curriculum_category
         (curriculum_version_id, parent_id, kind, code, name_th,
          min_credits, max_credits, sort_order)
       values ($1, $2, $3::category_kind, $4, $5, $6, $7, coalesce($8, 0))
       -- kind และ requirement เป็น enum จริงในฐานข้อมูล ไม่ใช่ text
       -- ค่าที่ไม่มีในระเบียบจะถูกปฏิเสธที่ชั้นฐานข้อมูลอีกชั้น
       returning id, code, name_th, kind, min_credits, max_credits`,
      [
        versionId, dto.parentId ?? null, dto.kind, dto.code, dto.nameTh,
        dto.minCredits ?? null, dto.maxCredits ?? null, dto.sortOrder ?? null,
      ],
    );
  }

  async addCourse(versionId: string, dto: AddCourseDto) {
    return this.db.queryOne(
      `insert into curriculum_course
         (curriculum_version_id, curriculum_category_id, course_id,
          requirement, suggested_year, suggested_term, sort_order)
       values ($1, $2, $3, coalesce($4::requirement_kind, 'required'), $5, $6, coalesce($7, 0))
       returning id, requirement, suggested_year, suggested_term`,
      [
        versionId, dto.curriculumCategoryId, dto.courseId,
        dto.requirement ?? null, dto.suggestedYear ?? null,
        dto.suggestedTerm ?? null, dto.sortOrder ?? null,
      ],
    );
  }

  /**
   * แก้ลำดับและภาคเรียนตามแผนของรายวิชาในหลักสูตร
   *
   * ─── ทำไมสองเรื่องนี้อยู่เส้นทางเดียวกัน ───
   * เพราะใบ รบ. ใช้ทั้งคู่พร้อมกัน — `suggestedYear`/`suggestedTerm` เป็นตัว
   * บอกว่ารายวิชาไปอยู่ภาคไหนบนใบ (0063) ส่วน `sortOrder` เป็นตัวบอกลำดับ
   * ภายในภาคนั้น คนที่เปิดหน้าจอมาจัดลำดับคือคนเดียวกับที่ย้ายภาค
   */
  async updateCourse(id: string, dto: UpdateCourseDto) {
    const row = await this.db.queryOne(
      `update curriculum_course
          set suggested_year = coalesce($2, suggested_year),
              suggested_term = coalesce($3, suggested_term),
              sort_order     = coalesce($4, sort_order),
              requirement    = coalesce($5::requirement_kind, requirement)
        where id = $1
      returning id, suggested_year, suggested_term, sort_order, requirement`,
      [id, dto.suggestedYear ?? null, dto.suggestedTerm ?? null,
       dto.sortOrder ?? null, dto.requirement ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบรายวิชาในหลักสูตรฉบับนี้');
    return row;
  }

  /**
   * จัดลำดับรายวิชาใหม่ทั้งชุด
   *
   * ─── ทำไมรับรายการทั้งชุด ไม่ใช่ "เลื่อนขึ้นหนึ่งขั้น" ───
   * เพราะการเลื่อนทีละขั้นต้องอ่านลำดับปัจจุบันมาก่อนแล้วเขียนกลับสองแถว
   * ซึ่งถ้ามีคนสองคนเปิดหน้าจอเดียวกันอยู่ จะสลับกันจนลำดับเพี้ยนโดยไม่มี
   * ใครเห็น — ส่งทั้งชุดแปลว่าคนที่กดบันทึกทีหลังชนะทั้งชุด ซึ่งอธิบายได้
   *
   * และเขียนในทรานแซกชันเดียว มิฉะนั้นการล้มกลางทางจะทิ้งลำดับที่ซ้ำกันไว้
   */
  async reorderCourses(versionId: string, ids: string[]) {
    if (ids.length === 0) throw new BadRequestException('ต้องส่งลำดับรายวิชามาอย่างน้อยหนึ่งตัว');
    return this.db.tx(async (c) => {
      const done = await c.query(
        `update curriculum_course cc
            set sort_order = x.ord
           from unnest($2::uuid[]) with ordinality as x(id, ord)
          where cc.id = x.id
            and cc.curriculum_version_id = $1
        returning cc.id`,
        [versionId, ids],
      );
      if (done.rows.length !== ids.length) {
        throw new BadRequestException(
          `จัดลำดับได้ ${done.rows.length} จาก ${ids.length} รายวิชา — มีรายวิชาที่ไม่ได้อยู่ในหลักสูตรฉบับนี้`,
        );
      }
      return { versionId, reordered: done.rows.length };
    });
  }

  /** ออกฉบับใหม่จากฉบับเดิมทั้งก้อน */
  async cloneVersion(sourceId: string, dto: CloneVersionDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `select clone_curriculum_version($1, $2, $3, $4) as id`,
      [sourceId, dto.editionBe, dto.effectiveFromYearBe, dto.effectiveToYearBe ?? null],
    );
    return this.structure(row!.id);
  }

  async listCourses(q?: string, activeOnly = true) {
    return this.db.query(
      `select id, code, name_th, name_en, theory_hours, practice_hours,
              credits, total_hours, weekly_periods, grading_mode,
              is_practicum, is_project, needs_workshop, active
         from course
        where ($1::text is null or code ilike '%' || $1 || '%' or name_th ilike '%' || $1 || '%')
          and ($2::boolean is not true or active)
        order by code
        limit 500`,
      [q ?? null, activeOnly],
    );
  }
}

@Roles('student', 'guardian', 'teacher', 'academic', 'registrar', 'director', 'admin')
@Controller('curriculum')
class CurriculumController {
  constructor(private readonly svc: CurriculumService) {}

  @Get('programs')
  programs() {
    return this.svc.listPrograms();
  }

  @Get('versions')
  versions(@Query('curriculumId') curriculumId?: string) {
    return this.svc.listVersions(curriculumId);
  }

  @Get('versions/:id')
  structure(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.structure(id);
  }

  @Get('courses')
  courses(@Query('q') q?: string, @Query('all') all?: string) {
    return this.svc.listCourses(q, all !== 'true');
  }

  @Get('students/:studentId/credits')
  credits(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.studentCredits(studentId);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('versions/:id/categories')
  addCategory(@Param('id', ParseUuidPipe) id: string, @Body() dto: CategoryDto) {
    return this.svc.addCategory(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('versions/:id/courses')
  addCourse(@Param('id', ParseUuidPipe) id: string, @Body() dto: AddCourseDto) {
    return this.svc.addCourse(id, dto);
  }

  /**
   * แก้ภาคเรียนตามแผนและลำดับของรายวิชาในหลักสูตร
   *
   * ทั้งสองค่าเป็นตัวกำหนดหน้าตาของใบ รบ. — `suggested_year`/`suggested_term`
   * บอกว่ารายวิชาไปอยู่ภาคไหน (0063) ส่วน `sort_order` บอกลำดับภายในภาคนั้น
   * ก่อนหน้านี้ตั้งได้ครั้งเดียวตอนเพิ่มรายวิชา แก้ทีหลังไม่ได้เลย
   */
  @Roles('academic', 'registrar', 'director', 'admin')
  @Patch('courses/:id')
  updateCourse(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateCourseDto) {
    return this.svc.updateCourse(id, dto);
  }

  @Roles('academic', 'registrar', 'director', 'admin')
  @Post('versions/:id/courses/reorder')
  reorderCourses(
    @Param('id', ParseUuidPipe) id: string,
    @Body() dto: ReorderCoursesDto,
  ) {
    return this.svc.reorderCourses(id, dto.courseIds);
  }

  @Roles('academic', 'director', 'admin')
  @Post('versions/:id/clone')
  clone(@Param('id', ParseUuidPipe) id: string, @Body() dto: CloneVersionDto) {
    return this.svc.cloneVersion(id, dto);
  }
}

@Module({
  controllers: [CurriculumController],
  providers: [CurriculumService],
  exports: [CurriculumService],
})
export class CurriculumModule {}

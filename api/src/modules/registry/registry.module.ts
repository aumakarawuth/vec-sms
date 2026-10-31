/**
 * ตัวนำทางกลางของงานทะเบียน — ประเภทวิชา → สาขา → หลักสูตร → ชั้นปี → ห้อง
 *
 * ─── ทำไมต้องมี ───
 * เปิดหน้าทะเบียนวัดผลของ SISA ครบ 66 หน้าแล้ว (docs/sisa-function-audit) หน้า
 * ส่วนใหญ่เริ่มจากวิธีเดียวกันคือไล่ลงเป็นคอลัมน์ตามห้องเรียน ผู้ใช้จึงเรียนวิธีใช้
 * ครั้งเดียวแล้วใช้ได้ทุกหน้า ของเราแต่ละหน้าเลือกขอบเขตคนละแบบ ซึ่งคือสิ่งที่
 * ผู้ใช้บอกว่า "แต่ละหน้าทำงานไม่เหมือนกัน" — เส้นทางนี้คืนข้อมูลชุดเดียวที่ทุกหน้า
 * ใช้สร้างตัวนำทางแบบเดียวกัน
 *
 * ─── ทำไมคืนแถวแบน ไม่ใช่ต้นไม้ซ้อน ───
 * หน้าจอต้องนับจำนวนนักศึกษาได้ทุกระดับ (ประเภทวิชา · สาขา · หลักสูตร · ชั้นปี)
 * แถวแบนระดับห้องรวมขึ้นได้ทุกระดับโดยไม่ต้องนับซ้ำที่ฐานข้อมูล
 *
 * นักศึกษาที่ยังไม่ผูกหลักสูตรหรือยังไม่ถูกจัดห้องยังอยู่ในผลเสมอ (ช่องว่าง) —
 * ตัดทิ้งแล้วยอดของทุกห้องจะไม่เท่ากับจำนวนนักศึกษาจริง และไม่มีใครเห็นกองที่
 * ต้องจัดการก่อน (หลักเดียวกับหน้าลงทะเบียน)
 */
import { Controller, Get, Injectable, Module, Query } from '@nestjs/common';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { ParseUuidPipe } from '../../common/validation/uuid';

@Injectable()
export class RegistryService {
  constructor(private readonly db: DbService) {}

  async tree(academicYearId: string) {
    const rows = await this.db.query<{
      program_type_id: string | null; program_type_name: string | null;
      program_id: string | null; program_name: string | null; level: string | null;
      curriculum_id: string | null; curriculum_name: string | null; shift: string | null;
      study_year: number | null; level_label: string | null; group_code: string | null; students: string;
    }>(
      `with cur as (
         select distinct on (sc.student_id) sc.student_id, cur.id as curriculum_id, cur.name_th as curriculum_name,
                cur.shift::text as shift, pr.id as program_id, pr.name_th as program_name, pr.level::text as level,
                pt.id as program_type_id, pt.name_th as program_type_name
           from student_curriculum sc
           join curriculum_version cv on cv.id = sc.curriculum_version_id
           join curriculum cur on cur.id = cv.curriculum_id
           join program_track tr on tr.id = cur.program_track_id
           join program pr on pr.id = tr.program_id
           join program_type pt on pt.id = pr.program_type_id
          where sc.effective_to is null
          order by sc.student_id, sc.effective_from desc)
       select cur.program_type_id, cur.program_type_name, cur.program_id, cur.program_name, cur.level,
              cur.curriculum_id, cur.curriculum_name, cur.shift,
              p.study_year, coalesce(gl.short_name, gl.title) as level_label, p.group_code,
              count(*) as students
         from student_class_placement p
         join student s on s.id = p.student_id and s.status in ('active', 'on_leave', 'suspended')
         left join cur on cur.student_id = p.student_id
         left join grade_level gl on gl.level::text = cur.level and gl.study_year = p.study_year
        where p.academic_year_id = $1
        group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
        order by cur.program_type_name nulls last, cur.program_name nulls last, cur.curriculum_name nulls last,
                 p.study_year, p.group_code nulls first`,
      [academicYearId],
    );
    return rows.map((r) => ({
      programTypeId: r.program_type_id, programTypeName: r.program_type_name,
      programId: r.program_id, programName: r.program_name, level: r.level,
      curriculumId: r.curriculum_id, curriculumName: r.curriculum_name, shift: r.shift,
      studyYear: r.study_year, levelLabel: r.level_label, groupCode: r.group_code,
      students: Number(r.students),
    }));
  }

  /** นักศึกษาในห้องหนึ่ง — ระดับสุดท้ายของตัวนำทาง (หน้าที่ไล่ถึงรายคน) */
  async roomStudents(academicYearId: string, groupCode: string | null, curriculumId: string | null) {
    return this.db.query(
      `select s.id, s.student_code, s.class_number, s.status::text as status,
              trim(coalesce(pe.prefix_th, '') || coalesce(pe.first_name_th, '') || ' ' || coalesce(pe.last_name_th, '')) as full_name
         from student_class_placement p
         join student s on s.id = p.student_id
         join person pe on pe.id = s.person_id
        where p.academic_year_id = $1
          and p.group_code is not distinct from $2
          and ($3::uuid is null or exists (
                select 1 from student_curriculum sc join curriculum_version cv on cv.id = sc.curriculum_version_id
                 where sc.student_id = s.id and sc.effective_to is null and cv.curriculum_id = $3))
        order by s.class_number nulls last, s.student_code`,
      [academicYearId, groupCode, curriculumId],
    );
  }
}

@Roles('registrar', 'academic', 'finance', 'student_affairs', 'secretary', 'hr', 'director', 'admin')
@Controller('registry')
export class RegistryController {
  constructor(private readonly svc: RegistryService) {}

  @Get('tree')
  tree(@Query('academicYearId', ParseUuidPipe) academicYearId: string) {
    return this.svc.tree(academicYearId);
  }

  /** groupCode ว่าง = กอง "ยังไม่จัดห้อง" · curriculumId ว่าง = ทุกหลักสูตรในห้องนั้น */
  @Get('room-students')
  roomStudents(
    @Query('academicYearId', ParseUuidPipe) academicYearId: string,
    @Query('groupCode') groupCode?: string,
    @Query('curriculumId') curriculumId?: string,
  ) {
    return this.svc.roomStudents(academicYearId, groupCode || null, curriculumId || null);
  }
}

@Module({
  controllers: [RegistryController],
  providers: [RegistryService],
})
export class RegistryModule {}

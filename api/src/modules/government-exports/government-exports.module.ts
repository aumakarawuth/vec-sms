import { BadRequestException, Body, Controller, Get, Injectable, Module, Post } from '@nestjs/common';
import { IsArray, IsIn, IsOptional, IsString } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray } from '../../common/validation/uuid';

const FORMAT_IDS = [
  'standard', 'gpa61', 'sp48', 'gpa_obec', 'mhesi', 'schoolmis',
  'regis_student', 'regis_personnel', 'regis_course', 'pvis', 'pvrs',
  'vec02', 'unicon',
] as const;
type FormatId = typeof FORMAT_IDS[number];
type Dataset = 'students' | 'timetable' | 'grades' | 'classes' | 'personnel' | 'courses';

const FORMATS: Array<{
  id: FormatId; label: string; agency: string; dataset: Dataset;
  approvalDates: boolean; studentStatuses: boolean;
}> = [
  { id: 'standard', label: 'ส่งออกข้อมูล', agency: 'ไฟล์กลาง', dataset: 'students', approvalDates: false, studentStatuses: false },
  { id: 'gpa61', label: 'GPA61', agency: 'กระทรวงศึกษาธิการ', dataset: 'grades', approvalDates: true, studentStatuses: true },
  { id: 'sp48', label: 'SP48 (PSIS สช.)', agency: 'สำนักงานคณะกรรมการส่งเสริมการศึกษาเอกชน', dataset: 'classes', approvalDates: false, studentStatuses: false },
  { id: 'gpa_obec', label: 'GPA Obec (ปพ.3 ออนไลน์)', agency: 'สำนักงานคณะกรรมการการศึกษาขั้นพื้นฐาน', dataset: 'grades', approvalDates: true, studentStatuses: true },
  { id: 'mhesi', label: 'mhesi (อว.)', agency: 'กระทรวงการอุดมศึกษา วิทยาศาสตร์ วิจัยและนวัตกรรม', dataset: 'grades', approvalDates: true, studentStatuses: true },
  { id: 'schoolmis', label: 'SchoolMIS (สพฐ.)', agency: 'สำนักงานคณะกรรมการการศึกษาขั้นพื้นฐาน', dataset: 'students', approvalDates: false, studentStatuses: true },
  { id: 'regis_student', label: 'REGIS ข้อมูลนักเรียนและผลการเรียน', agency: 'โรงเรียนเอกชน', dataset: 'grades', approvalDates: true, studentStatuses: true },
  { id: 'regis_personnel', label: 'REGIS ข้อมูลบุคลากร', agency: 'โรงเรียนเอกชน', dataset: 'personnel', approvalDates: false, studentStatuses: false },
  { id: 'regis_course', label: 'REGIS ข้อมูลหลักสูตรวิชา', agency: 'โรงเรียนเอกชน', dataset: 'courses', approvalDates: false, studentStatuses: false },
  { id: 'pvis', label: 'ระบบสารสนเทศสถานศึกษาอาชีวศึกษาเอกชน (PVIS)', agency: 'สอศ.', dataset: 'students', approvalDates: false, studentStatuses: true },
  { id: 'pvrs', label: 'ระบบงานทะเบียนวัดผลสถานศึกษาอาชีวศึกษาเอกชน (PVRS)', agency: 'สอศ.', dataset: 'grades', approvalDates: true, studentStatuses: true },
  { id: 'vec02', label: 'ศธ.02', agency: 'สำนักงานคณะกรรมการการอาชีวศึกษา', dataset: 'grades', approvalDates: true, studentStatuses: true },
  { id: 'unicon', label: 'Unicon', agency: 'ระบบเชื่อมโยงข้อมูลการศึกษา', dataset: 'grades', approvalDates: true, studentStatuses: true },
];

class ExportRequestDto {
  @IsIn(FORMAT_IDS) format: FormatId;
  @IsUuid() termId: string;
  @IsOptional() @IsIn(['students', 'timetable', 'grades']) dataset?: Dataset;
  @IsOptional() @IsArray() @IsUuidArray() curriculumVersionIds?: string[];
  @IsOptional() @IsArray() @IsString({ each: true }) approvalDates?: string[];
  @IsOptional() @IsArray() @IsIn(['active', 'graduated', 'inactive'], { each: true })
  studentStatuses?: Array<'active' | 'graduated' | 'inactive'>;
}

interface ExportRow { [key: string]: unknown }

function csvCell(value: unknown): string {
  let text = value === null || value === undefined ? '' : String(value);
  if (/^[=+@]/.test(text)) text = `'${text}`;
  return `"${text.replace(/"/g, '""')}"`;
}

function csv(rows: ExportRow[]): string {
  if (!rows.length) return '\uFEFF';
  const headers = Object.keys(rows[0]);
  return '\uFEFF' + [headers.map(csvCell).join(','), ...rows.map((r) => headers.map((h) => csvCell(r[h])).join(','))].join('\r\n');
}

@Injectable()
class GovernmentExportsService {
  constructor(private readonly db: DbService) {}

  async catalog() {
    const [terms, curricula] = await Promise.all([
      this.db.query(
        `select t.id, ay.year_be, t.ordinal, t.kind, t.status
           from term t join academic_year ay on ay.id = t.academic_year_id
          order by ay.year_be desc, t.ordinal`,
      ),
      this.db.query(
        `select cv.id, cv.edition_be, cv.status, tr.code, c.name_th,
                p.code as program_code, p.name_th as program_name,
                pt.code as program_type_code, pt.name_th as program_type_name
           from curriculum_version cv
           join curriculum c on c.id = cv.curriculum_id
           join program_track tr on tr.id = c.program_track_id
           join program p on p.id = tr.program_id
           join program_type pt on pt.id = p.program_type_id
          order by pt.name_th, p.name_th, cv.edition_be desc`,
      ),
    ]);
    return { formats: FORMATS, terms, curricula };
  }

  private format(id: FormatId) {
    const f = FORMATS.find((x) => x.id === id);
    if (!f) throw new BadRequestException('ไม่รู้จักรูปแบบส่งออก');
    return f;
  }

  private dataset(dto: ExportRequestDto): Dataset {
    const f = this.format(dto.format);
    return dto.format === 'standard' && dto.dataset ? dto.dataset : f.dataset;
  }

  async preview(dto: ExportRequestDto) {
    const rows = await this.rows(dto);
    const counts = await this.db.queryOne<{
      institution_code_missing: boolean; missing_national_id: number; unlocked_grades: number;
    }>(
      `select
         not exists (select 1 from institution where id = current_institution_id() and nullif(btrim(code), '') is not null)
           as institution_code_missing,
         (select count(*)::integer from student s join person p on p.id = s.person_id
           where s.institution_id = current_institution_id() and p.national_id_enc is null) as missing_national_id,
         (select count(*)::integer from grade_submission gs join class_section cs on cs.id = gs.class_section_id
           where cs.institution_id = current_institution_id() and gs.term_id = $1 and gs.stage <> 'locked') as unlocked_grades`,
      [dto.termId],
    );
    const issues: Array<{ level: 'error' | 'warning'; code: string; message: string }> = [];
    if (counts?.institution_code_missing) issues.push({ level: 'error', code: 'INSTITUTION_CODE', message: 'ยังไม่ได้กำหนดรหัสสถานศึกษา' });
    if (counts?.missing_national_id) issues.push({ level: 'error', code: 'NATIONAL_ID', message: `นักศึกษา ${counts.missing_national_id} คนไม่มีเลขประจำตัวประชาชนที่ถอดกลับได้` });
    if (this.dataset(dto) === 'grades' && counts?.unlocked_grades) issues.push({ level: 'warning', code: 'UNLOCKED_GRADES', message: `มีสมุดคะแนน ${counts.unlocked_grades} กลุ่มที่ยังไม่ล็อก` });
    if (!rows.length) issues.push({ level: 'warning', code: 'EMPTY', message: 'ไม่มีข้อมูลตรงกับตัวกรอง' });
    return { format: this.format(dto.format), dataset: this.dataset(dto), rows: rows.length, issues, sample: rows.slice(0, 10) };
  }

  async generate(dto: ExportRequestDto) {
    const readiness = await this.preview(dto);
    const blocking = readiness.issues.filter((issue) => issue.level === 'error');
    if (blocking.length) {
      throw new BadRequestException(`ข้อมูลยังไม่พร้อม: ${blocking.map((issue) => issue.message).join('; ')}`);
    }
    const rows = await this.rows(dto);
    if (!rows.length) throw new BadRequestException('ไม่มีข้อมูลตรงกับตัวกรอง จึงไม่สร้างไฟล์ว่าง');
    const body = csv(rows);
    const term = await this.db.queryOne<{ year_be: number; ordinal: number }>(
      `select ay.year_be, t.ordinal from term t join academic_year ay on ay.id=t.academic_year_id where t.id=$1`, [dto.termId],
    );
    const filename = `${dto.format}-${term?.year_be ?? 'year'}-${term?.ordinal ?? 'term'}.csv`;
    return { filename, mimeType: 'text/csv;charset=utf-8', bytes: Buffer.byteLength(body), contentBase64: Buffer.from(body, 'utf8').toString('base64') };
  }

  private async rows(dto: ExportRequestDto): Promise<ExportRow[]> {
    const dataset = this.dataset(dto);
    const curriculumIds = dto.curriculumVersionIds?.length ? dto.curriculumVersionIds : null;
    if (dataset === 'classes') {
      return this.db.query(
        `select ay.year_be as "ปีการศึกษา", t.ordinal as "ภาคเรียน", cs.section_no as "ห้อง",
                co.code as "รหัสวิชา", co.name_th as "รายวิชา", cs.delivery_mode as "รูปแบบ",
                count(e.id) filter (where e.status='enrolled')::integer as "จำนวนนักศึกษา"
           from class_section cs join term t on t.id=cs.term_id join academic_year ay on ay.id=t.academic_year_id
           join course co on co.id=cs.course_id left join enrollment e on e.class_section_id=cs.id
          where cs.term_id=$1 group by ay.year_be,t.ordinal,cs.id,co.code,co.name_th order by cs.section_no,co.code`, [dto.termId],
      );
    }
    if (dataset === 'personnel') {
      return this.db.query(
        `select st.staff_code as "รหัสบุคลากร", p.prefix_th as "คำนำหน้า", p.first_name_th as "ชื่อ",
                p.last_name_th as "นามสกุล", p.gender as "เพศ", p.birth_date as "วันเกิด",
                p.phone as "โทรศัพท์", p.email as "อีเมล", st.is_teacher as "ครูผู้สอน", st.active as "ใช้งาน"
           from staff st join person p on p.id=st.person_id
          where st.institution_id=current_institution_id() order by st.staff_code`,
      );
    }
    if (dataset === 'courses') {
      return this.db.query(
        `select pt.code as "รหัสประเภทวิชา", pt.name_th as "ประเภทวิชา", p.code as "รหัสสาขา",
                p.name_th as "สาขาวิชา", c.code as "รหัสหลักสูตร", c.name_th as "หลักสูตร",
                cv.edition_be as "ฉบับปี", p.level as "ระดับ", co.code as "รหัสวิชา",
                co.name_th as "รายวิชา", co.credits as "หน่วยกิต"
           from curriculum_version cv join curriculum c on c.id=cv.curriculum_id
           join program_track tr on tr.id=c.program_track_id join program p on p.id=tr.program_id
           join program_type pt on pt.id=p.program_type_id
           left join curriculum_course cc on cc.curriculum_version_id=cv.id left join course co on co.id=cc.course_id
          where ($1::uuid[] is null or cv.id=any($1)) order by pt.code,p.code,c.code,co.code`, [curriculumIds],
      );
    }
    if (dataset === 'timetable') {
      return this.db.query(
        `select ay.year_be as "ปีการศึกษา", t.ordinal as "ภาคเรียน", co.code as "รหัสวิชา",
                co.name_th as "รายวิชา", cs.section_no as "กลุ่มเรียน", cs.room as "ห้องเรียน",
                cs.delivery_mode as "รูปแบบ", st.staff_code as "รหัสครู",
                concat_ws(' ',pe.prefix_th,pe.first_name_th,pe.last_name_th) as "ครูผู้สอน"
           from class_section cs join term t on t.id=cs.term_id join academic_year ay on ay.id=t.academic_year_id
           join course co on co.id=cs.course_id left join staff st on st.id=cs.teacher_id left join person pe on pe.id=st.person_id
          where cs.term_id=$1 order by co.code,cs.section_no`, [dto.termId],
      );
    }
    const statusSql = dto.studentStatuses?.length
      ? dto.studentStatuses.flatMap((x) => x === 'active' ? ['active', 'on_leave'] : x === 'graduated' ? ['graduated'] : ['suspended', 'withdrawn', 'dismissed', 'transferred_out']).filter((x, i, a) => a.indexOf(x) === i)
      : null;
    if (dataset === 'grades') {
      return this.db.query(
        `select i.code as "รหัสสถานศึกษา", ay.year_be as "ปีการศึกษา", t.ordinal as "ภาคเรียน",
                s.student_code as "รหัสนักศึกษา", pe.prefix_th as "คำนำหน้า", pe.first_name_th as "ชื่อ",
                pe.last_name_th as "นามสกุล", pe.birth_date as "วันเกิด", pe.gender as "เพศ",
                s.status as "สถานภาพ", p.level as "ระดับ", p.code as "รหัสสาขา",
                p.name_th as "สาขาวิชา", co.code as "รหัสวิชา", co.name_th as "รายวิชา",
                co.credits as "หน่วยกิต", e.status as "สถานะลงทะเบียน", gs.symbol as "ผลการเรียน",
                er.grade_point as "แต้มระดับ", er.credits_earned as "หน่วยกิตที่ได้", er.attendance_pct as "เวลาเรียนร้อยละ"
           from enrollment e join student s on s.id=e.student_id join person pe on pe.id=s.person_id
           join institution i on i.id=s.institution_id join term t on t.id=e.term_id join academic_year ay on ay.id=t.academic_year_id
           join class_section cs on cs.id=e.class_section_id join course co on co.id=cs.course_id
           left join enrollment_result er on er.enrollment_id=e.id and er.superseded_by is null
           left join grade_symbol gs on gs.id=er.grade_symbol_id
           left join student_curriculum sc on sc.student_id=s.id and sc.effective_to is null
           left join curriculum_version cv on cv.id=sc.curriculum_version_id left join curriculum c on c.id=cv.curriculum_id
           left join program_track tr on tr.id=c.program_track_id left join program p on p.id=tr.program_id
          where e.term_id=$1 and ($2::uuid[] is null or cv.id=any($2)) and ($3::student_status[] is null or s.status=any($3))
          order by s.student_code,co.code`, [dto.termId, curriculumIds, statusSql],
      );
    }
    return this.db.query(
      `select i.code as "รหัสสถานศึกษา", s.student_code as "รหัสนักศึกษา", pe.prefix_th as "คำนำหน้า",
              pe.first_name_th as "ชื่อ", pe.last_name_th as "นามสกุล", pe.birth_date as "วันเกิด",
              pe.gender as "เพศ", pe.phone as "โทรศัพท์", pe.email as "อีเมล", s.status as "สถานภาพ",
              s.admitted_year_be as "ปีที่รับเข้า", p.level as "ระดับ", p.code as "รหัสสาขา",
              p.name_th as "สาขาวิชา", cv.edition_be as "หลักสูตรปี"
         from student s join person pe on pe.id=s.person_id join institution i on i.id=s.institution_id
         left join student_curriculum sc on sc.student_id=s.id and sc.effective_to is null
         left join curriculum_version cv on cv.id=sc.curriculum_version_id left join curriculum c on c.id=cv.curriculum_id
         left join program_track tr on tr.id=c.program_track_id left join program p on p.id=tr.program_id
        where ($1::uuid[] is null or cv.id=any($1)) and ($2::student_status[] is null or s.status=any($2))
        order by s.student_code`, [curriculumIds, statusSql],
    );
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('government-exports')
class GovernmentExportsController {
  constructor(private readonly svc: GovernmentExportsService) {}

  @Get('catalog') catalog() { return this.svc.catalog(); }
  @Post('preview') preview(@Body() dto: ExportRequestDto) { return this.svc.preview(dto); }

  @Audit('government_export')
  @Post('generate') generate(@Body() dto: ExportRequestDto) { return this.svc.generate(dto); }
}

@Module({ controllers: [GovernmentExportsController], providers: [GovernmentExportsService] })
export class GovernmentExportsModule {}

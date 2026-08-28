import { BadRequestException, Controller, Get, Header, Injectable, Module, Query } from '@nestjs/common';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { UUID_PATTERN } from '../../common/validation/uuid';

function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** โครงกระดาษพิมพ์ของรายงาน — ตารางล้วน ไม่ใช่เอกสารราชการที่ต้องวัดกระดาษ */
function reportSheet(title: string, sub: string, body: string): string {
  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>
  @page { size: A4 landscape; margin: 12mm; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', Tahoma, sans-serif;
         font-size: 13pt; color: #000; }
  .title { font-size: 17pt; font-weight: 700; text-align: center; margin: 0 0 2pt; }
  .sub { text-align: center; font-size: 12.5pt; color: #333; margin-bottom: 8pt; }
  table { width: 100%; border-collapse: collapse; margin-top: 6pt; }
  th, td { border: 0.7pt solid #000; padding: 2.5pt 4pt; }
  th { background: #eee; font-weight: 700; font-size: 12pt; }
  td.num { text-align: right; }
  td.mid { text-align: center; }
  .foot { margin-top: 10pt; font-size: 11pt; color: #444; }
  @media screen {
    body { background: #f4f4f4; padding: 16px; }
    .sheet { background: #fff; margin: 0 auto; padding: 12mm; max-width: 297mm; box-shadow: 0 1px 6px rgba(0,0,0,.2); }
  }
</style>
</head>
<body>
<div class="sheet">
<div class="title">${esc(title)}</div>
<div class="sub">${esc(sub)}</div>
${body}
<div class="foot">พิมพ์เมื่อ ${esc(new Date().toLocaleString('th-TH'))} — รายงานนี้แสดงข้อมูล ณ เวลาที่พิมพ์</div>
</div>
</body>
</html>`;
}

/**
 * ข้อมูลสถิติภาพรวม — รวมตัวเลขที่มีอยู่แล้วในแต่ละโมดูลมาไว้จุดเดียว
 *
 * ─── ทำไมเป็นเอนด์พอยต์เดียว ไม่ใช่ให้หน้าจอยิงทีละโมดูล ───
 * หน้าสรุปต้องการแค่ตัวเลขนับ ไม่ใช่รายการเต็ม — ยิง `/students?limit=200`
 * มาเพื่อนับจำนวนคือของเดิมที่เพิ่งแก้ไปแล้วในหน้าลงทะเบียน (ข้อ 19 ใน
 * CLAUDE.md) การนับที่ฐานข้อมูลด้วย count(*) ต่อสถานะไม่ต้องโหลดข้อมูลจริง
 * เลยสักแถว และเร็วกว่าการยิงหลายเอนด์พอยต์แล้วมานับฝั่งเบราว์เซอร์
 */
@Injectable()
export class ReportsService {
  constructor(private readonly db: DbService) {}

  async summary() {
    const row = await this.db.queryOne<{
      students_total: string; students_active: string; students_on_leave: string;
      students_suspended: string; students_graduated: string; students_withdrawn: string;
      staff_total: string; staff_teachers: string;
      ar_outstanding: string; invoices_unpaid: string;
      risk_open_cases: string;
      curriculum_active_versions: string;
    }>(
      `select
         (select count(*) from student)                                  as students_total,
         (select count(*) from student where status = 'active')          as students_active,
         (select count(*) from student where status = 'on_leave')        as students_on_leave,
         (select count(*) from student where status = 'suspended')       as students_suspended,
         (select count(*) from student where status = 'graduated')       as students_graduated,
         (select count(*) from student
           where status in ('withdrawn', 'transferred_out', 'dismissed')) as students_withdrawn,
         (select count(*) from staff)                                    as staff_total,
         (select count(*) from staff where is_teacher)                   as staff_teachers,
         (select coalesce(sum(total - paid_total), 0) from invoice
           where status in ('issued', 'partially_paid'))                 as ar_outstanding,
         (select count(*) from invoice
           where status in ('issued', 'partially_paid'))                 as invoices_unpaid,
         (select count(*) from intervention_case
           where status in ('open', 'in_progress', 'escalated'))         as risk_open_cases,
         (select count(*) from curriculum_version where status = 'active')
                                                                          as curriculum_active_versions`,
    );

    return {
      students: {
        total: Number(row?.students_total ?? 0),
        active: Number(row?.students_active ?? 0),
        onLeave: Number(row?.students_on_leave ?? 0),
        suspended: Number(row?.students_suspended ?? 0),
        graduated: Number(row?.students_graduated ?? 0),
        withdrawn: Number(row?.students_withdrawn ?? 0),
      },
      staff: {
        total: Number(row?.staff_total ?? 0),
        teachers: Number(row?.staff_teachers ?? 0),
      },
      finance: {
        arOutstanding: Number(row?.ar_outstanding ?? 0),
        invoicesUnpaid: Number(row?.invoices_unpaid ?? 0),
      },
      risk: {
        openCases: Number(row?.risk_open_cases ?? 0),
      },
      curriculum: {
        activeVersions: Number(row?.curriculum_active_versions ?? 0),
      },
    };
  }

  /**
   * รายงานผลการเรียน — เลือกขอบเขตได้สามแบบ (ภาคเรียนเดียว / ทั้งปีการศึกษา /
   * ทุกภาคเรียน) และกรอง "เฉพาะที่ไม่ผ่าน" ได้ — เป็นแบบสอบถามอ่านอย่างเดียว
   * ไม่ใช่กฎธุรกิจ จึงเขียนที่ชั้น API ตรง ๆ แบบเดียวกับ rooms()/roomPlan()
   * ในโมดูลลงทะเบียน ไม่ต้องมีฟังก์ชันในฐานข้อมูล
   */
  async grades(opts: { termId?: string; academicYearId?: string; allTerms?: boolean; onlyFailed?: boolean }) {
    const conditions: string[] = [];
    const params: unknown[] = [];
    if (opts.termId) {
      params.push(opts.termId);
      conditions.push(`t.id = $${params.length}`);
    } else if (opts.academicYearId) {
      params.push(opts.academicYearId);
      conditions.push(`t.academic_year_id = $${params.length}`);
    } else if (!opts.allTerms) {
      throw new BadRequestException('ต้องระบุ termId, academicYearId หรือ allTerms=true อย่างใดอย่างหนึ่ง');
    }
    if (opts.onlyFailed) conditions.push('not gsym.earns_credit');
    const where = conditions.length ? `and ${conditions.join(' and ')}` : '';

    return this.db.query(
      `select s.student_code,
              trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                   || ' ' || coalesce(p.last_name_th, '')) as full_name,
              c.code as course_code, c.name_th as course_name, c.credits,
              gsym.symbol as grade_symbol, gsym.earns_credit,
              'ภาคเรียนที่ ' || t.ordinal || '/' || ay.year_be as term_label
         from enrollment e
         join class_section cs      on cs.id = e.class_section_id
         join course c               on c.id  = cs.course_id
         join term t                 on t.id  = e.term_id
         join academic_year ay       on ay.id = t.academic_year_id
         join student s              on s.id  = e.student_id
         join person p               on p.id  = s.person_id
         join enrollment_result er   on er.enrollment_id = e.id and er.superseded_by is null
         join grade_symbol gsym      on gsym.id = er.grade_symbol_id
        where e.status = 'enrolled' ${where}
        order by s.student_code, c.code`,
      params,
    );
  }

  /**
   * นักศึกษาที่มีผลการเรียนไม่ผ่านเกณฑ์ — รวมจาก student_failed_courses()
   * (0089) ที่ตอบคำถาม "นักศึกษาคนนี้ยังไม่ผ่านวิชาอะไรบ้าง" อยู่แล้ว
   * ที่นี่กวาดทุกคนที่ยัง active มาต่อกันเป็นรายงานเดียว
   */
  async failingStudents() {
    return this.db.query(
      `select s.student_code,
              trim(coalesce(p.prefix_th, '') || coalesce(p.first_name_th, '')
                   || ' ' || coalesce(p.last_name_th, '')) as full_name,
              count(*) as failed_count,
              string_agg(f.course_code || ' ' || f.course_name, ', ' order by f.course_code) as failed_courses
         from student s
         join person p on p.id = s.person_id
         cross join lateral student_failed_courses(s.id) f
        where s.status = 'active'
        group by s.id, s.student_code, p.prefix_th, p.first_name_th, p.last_name_th
        order by failed_count desc, s.student_code`,
    );
  }

  /** จำนวนนักศึกษาต่อหลักสูตร — ใช้ตอบว่าสาขาไหนคนเยอะ/น้อยโดยไม่ต้องนับเอง */
  async byCurriculum() {
    return this.db.query(
      `select cur.name_th as curriculum_name, cv.edition_be, cur.shift,
              count(sc.student_id) filter (where s.status = 'active') as active_students
         from curriculum_version cv
         join curriculum cur on cur.id = cv.curriculum_id
         left join student_curriculum sc on sc.curriculum_version_id = cv.id
         left join student s on s.id = sc.student_id
        where cv.status = 'active'
        group by cur.name_th, cv.edition_be, cur.shift, cv.id
        order by active_students desc, cur.name_th`,
    );
  }
}

@Roles('registrar', 'academic', 'finance', 'student_affairs', 'director', 'admin')
@Controller('reports')
export class ReportsController {
  constructor(private readonly svc: ReportsService) {}

  @Get('summary')
  summary() {
    return this.svc.summary();
  }

  @Get('by-curriculum')
  byCurriculum() {
    return this.svc.byCurriculum();
  }

  @Get('grades')
  grades(
    @Query('termId') termId?: string,
    @Query('academicYearId') academicYearId?: string,
    @Query('allTerms') allTerms?: string,
    @Query('onlyFailed') onlyFailed?: string,
  ) {
    if (termId && !UUID_PATTERN.test(termId)) throw new BadRequestException('termId ต้องเป็นรหัสรูปแบบ UUID');
    if (academicYearId && !UUID_PATTERN.test(academicYearId)) {
      throw new BadRequestException('academicYearId ต้องเป็นรหัสรูปแบบ UUID');
    }
    return this.svc.grades({
      termId: termId || undefined,
      academicYearId: academicYearId || undefined,
      allTerms: allTerms === 'true',
      onlyFailed: onlyFailed === 'true',
    });
  }

  @Get('failing-students')
  failingStudents() {
    return this.svc.failingStudents();
  }

  @Header('content-type', 'text/html; charset=utf-8')
  @Get('grades/print')
  async gradesPrint(
    @Query('termId') termId?: string,
    @Query('academicYearId') academicYearId?: string,
    @Query('allTerms') allTerms?: string,
    @Query('onlyFailed') onlyFailed?: string,
    @Query('scopeLabel') scopeLabel?: string,
  ) {
    if (termId && !UUID_PATTERN.test(termId)) throw new BadRequestException('termId ต้องเป็นรหัสรูปแบบ UUID');
    if (academicYearId && !UUID_PATTERN.test(academicYearId)) {
      throw new BadRequestException('academicYearId ต้องเป็นรหัสรูปแบบ UUID');
    }
    const rows = await this.svc.grades({
      termId: termId || undefined,
      academicYearId: academicYearId || undefined,
      allTerms: allTerms === 'true',
      onlyFailed: onlyFailed === 'true',
    });

    const body = `<table>
  <thead>
    <tr>
      <th style="width:5%">ที่</th>
      <th style="width:12%">รหัสนักศึกษา</th>
      <th style="width:20%">ชื่อ — นามสกุล</th>
      <th style="width:10%">รหัสวิชา</th>
      <th>ชื่อวิชา</th>
      <th style="width:8%">นก.</th>
      <th style="width:8%">ผลการเรียน</th>
      <th style="width:14%">ภาคเรียน</th>
    </tr>
  </thead>
  <tbody>${
    rows.length === 0
      ? '<tr><td colspan="8" class="mid">— ไม่มีข้อมูลตามเงื่อนไขที่เลือก —</td></tr>'
      : rows
          .map(
            (r: Record<string, unknown>, i: number) => `<tr>
      <td class="mid">${i + 1}</td>
      <td>${esc(r.student_code)}</td>
      <td>${esc(r.full_name)}</td>
      <td>${esc(r.course_code)}</td>
      <td>${esc(r.course_name)}</td>
      <td class="num">${esc(r.credits)}</td>
      <td class="mid">${esc(r.grade_symbol)}</td>
      <td>${esc(r.term_label)}</td>
    </tr>`,
          )
          .join('')
  }</tbody>
</table>`;

    return reportSheet(
      onlyFailed === 'true' ? 'รายงานผลการเรียน — เฉพาะที่ไม่ผ่าน' : 'รายงานผลการเรียน',
      `${scopeLabel ?? ''} — ${rows.length} รายการ`,
      body,
    );
  }

  @Header('content-type', 'text/html; charset=utf-8')
  @Get('failing-students/print')
  async failingStudentsPrint() {
    const rows = await this.svc.failingStudents();

    const body = `<table>
  <thead>
    <tr>
      <th style="width:6%">ที่</th>
      <th style="width:14%">รหัสนักศึกษา</th>
      <th style="width:20%">ชื่อ — นามสกุล</th>
      <th style="width:10%">จำนวนวิชาที่ตก</th>
      <th>รายวิชาที่ยังไม่ผ่าน</th>
    </tr>
  </thead>
  <tbody>${
    rows.length === 0
      ? '<tr><td colspan="5" class="mid">— ไม่มีนักศึกษาที่ผลการเรียนไม่ผ่านเกณฑ์ —</td></tr>'
      : rows
          .map(
            (r: Record<string, unknown>, i: number) => `<tr>
      <td class="mid">${i + 1}</td>
      <td>${esc(r.student_code)}</td>
      <td>${esc(r.full_name)}</td>
      <td class="num">${esc(r.failed_count)}</td>
      <td>${esc(r.failed_courses)}</td>
    </tr>`,
          )
          .join('')
  }</tbody>
</table>`;

    return reportSheet('นักศึกษาที่ผลการเรียนไม่ผ่านเกณฑ์', `${rows.length} คน`, body);
  }
}

@Module({
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}

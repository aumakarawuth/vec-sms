import { BadRequestException, Controller, Get, Header, Injectable, Module, Param, Query } from '@nestjs/common';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { thaiDate } from '../documents/templates';
import { ParseUuidPipe, UUID_PATTERN } from '../../common/validation/uuid';

function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * โครงกระดาษพิมพ์ของรายงาน — ตารางล้วน ไม่ใช่เอกสารราชการที่ต้องวัดกระดาษ
 *
 * ─── ทำไมเส้นแนวนอนบาง ๆ แทนกรอบตารางทึบ ───
 * กรอบดำทุกช่อง (0.7pt solid ทั้งตาราง) ทำให้ตาต้องแยกเส้นตารางออกจาก
 * ตัวเลขก่อนอ่านได้ ยิ่งคอลัมน์เยอะยิ่งเป็นเส้นตาหมากรุกที่ล้าตา — เปลี่ยน
 * เป็นเส้นคั่นแถวบาง ๆ สีเทาอ่อน (ตามแบบตารางบนหน้าจอที่ใช้อยู่แล้วทั้งระบบ
 * ใน styles.css) กับแถบสีสลับบาง ๆ ให้ตามองเห็นแนวแถวได้โดยไม่ต้องมีเส้น
 */
function reportSheet(title: string, sub: string, body: string): string {
  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>
  @page { size: A4 landscape; margin: 14mm; }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', Tahoma, sans-serif;
         font-size: 13pt; color: #1c1c24; }
  header.report-head { display: flex; align-items: baseline; justify-content: space-between;
    gap: 12pt; padding-bottom: 8pt; margin-bottom: 10pt; border-bottom: 1.4pt solid #1c1c24; }
  .title { font-size: 18pt; font-weight: 700; margin: 0; }
  .sub { font-size: 11.5pt; color: #6b6f7d; margin: 2pt 0 0; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 5pt 8pt; text-align: left; }
  th { font-weight: 700; font-size: 10.5pt; letter-spacing: .2pt; color: #6b6f7d;
       border-bottom: 1pt solid #1c1c24; }
  tbody tr { border-bottom: 0.5pt solid #e3e5ec; }
  tbody tr:nth-child(even) { background: #f7f8fb; }
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
  td.mid, th.mid { text-align: center; }
  tr.group-row td { border-bottom: 1pt solid #1c1c24; padding-top: 10pt; font-weight: 700; background: #fff; }
  .tag { display: inline-block; padding: 1.5pt 7pt; margin: 1pt 3pt 1pt 0; border-radius: 999pt;
         font-size: 10pt; background: #eef0f7; color: #444a5c; }
  .tag.danger { background: #fbe7e5; color: #a4342b; }
  .foot { margin-top: 12pt; font-size: 10pt; color: #8b8f9c; }
  @media screen {
    body { background: #eef1f6; padding: 24px; }
    .sheet { background: #fff; margin: 0 auto; padding: 16mm; max-width: 297mm;
             border-radius: 10px; box-shadow: 0 4px 24px rgba(30,34,54,.1); }
  }
</style>
</head>
<body>
<div class="sheet">
<header class="report-head">
  <h1 class="title">${esc(title)}</h1>
  <p class="sub">${esc(sub)}</p>
</header>
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
              array_agg(f.course_code order by f.course_code) as failed_course_codes
         from student s
         join person p on p.id = s.person_id
         cross join lateral student_failed_courses(s.id) f
        where s.status = 'active'
        group by s.id, s.student_code, p.prefix_th, p.first_name_th, p.last_name_th
        order by failed_count desc, s.student_code`,
    );
  }

  /**
   * ตรวจสอบหลักสูตร — วิชาทุกตัวในแผนของนักศึกษาคนหนึ่ง เทียบกับที่เรียนจริง
   *
   * ใช้ฉบับหลักสูตรล่าสุดที่ผูกไว้ (`student_curriculum.effective_from`
   * มากสุด) หลักเดียวกับ `registrationSlip()` ใน worksheets.ts — ต่อวิชา
   * หนึ่งอาจลงหลายครั้ง (เรียนซ้ำ) เอาความพยายามล่าสุดมาแสดง (created_at
   * มากสุด) เพื่อให้เห็นสถานะปัจจุบันจริง ไม่ใช่ครั้งแรกที่เคยลง
   */
  async curriculumCheck(studentId: string) {
    return this.db.query(
      `with sc as (
         select cv.id as curriculum_version_id
           from student_curriculum stc
           join curriculum_version cv on cv.id = stc.curriculum_version_id
          where stc.student_id = $1
          order by stc.effective_from desc nulls last
          limit 1
       )
       select cc.suggested_year, cc.suggested_term, cc.requirement,
              cat.name_th as category_name,
              c.code as course_code, c.name_th as course_name, c.credits,
              e.status as enrollment_status,
              gsym.symbol as grade_symbol, gsym.earns_credit
         from sc
         join curriculum_course cc   on cc.curriculum_version_id = sc.curriculum_version_id
         join curriculum_category cat on cat.id = cc.curriculum_category_id
         join course c                on c.id  = cc.course_id
         left join lateral (
           select e2.id, e2.status
             from enrollment e2
             join class_section cs2 on cs2.id = e2.class_section_id
            where e2.student_id = $1 and cs2.course_id = cc.course_id
            order by e2.created_at desc
            limit 1
         ) e on true
         left join enrollment_result er on er.enrollment_id = e.id and er.superseded_by is null
         left join grade_symbol gsym    on gsym.id = er.grade_symbol_id
        order by cc.suggested_year nulls last, cc.suggested_term nulls last, cc.sort_order`,
      [studentId],
    );
  }

  /**
   * เวลาเรียนรายสัปดาห์ — สรุปคาบที่สอนจริงและสถิติการเข้าเรียนของกลุ่มเรียน
   * หนึ่งกลุ่ม แบ่งเป็นสัปดาห์ นับสัปดาห์ที่ 1 จากคาบแรกที่สอนจริงของกลุ่มนั้น
   * (ไม่ใช่วันเปิดภาคเรียน เพราะบางกลุ่มอาจเริ่มสอนช้ากว่าวันเปิดภาคจริง)
   */
  async weeklyAttendance(classSectionId: string) {
    return this.db.query(
      `with meetings as (
         select id, meets_on,
                (meets_on - min(meets_on) over ())::int / 7 + 1 as week_no
           from class_meeting
          where class_section_id = $1 and status = 'held'
       ),
       weeks as (
         select week_no, min(meets_on) as starts_on, max(meets_on) as ends_on, count(*) as meetings_held
           from meetings
          group by week_no
       )
       select w.week_no, w.starts_on, w.ends_on, w.meetings_held,
              count(ar.*) filter (where ar.status = 'present')  as present_count,
              count(ar.*) filter (where ar.status = 'late')     as late_count,
              count(ar.*) filter (where ar.status = 'absent')   as absent_count,
              count(ar.*) filter (where ar.status::text like 'leave%') as leave_count
         from weeks w
         join meetings m on m.week_no = w.week_no
         left join attendance_record ar on ar.class_meeting_id = m.id
        group by w.week_no, w.starts_on, w.ends_on, w.meetings_held
        order by w.week_no`,
      [classSectionId],
    );
  }

  /** จำนวนนักศึกษาต่อหลักสูตร — ใช้ตอบว่าสาขาไหนคนเยอะ/น้อยโดยไม่ต้องนับเอง */
  /**
   * จำนวนนักศึกษาแยกตามมิติหนึ่ง × ชั้นปี — ทุกเมนู "ข้อมูลสถิติ" ของ SISA
   * คือตารางรูปนี้ (แถว = ค่าของมิติ · คอลัมน์ = ชั้นปี) ต่างกันแค่มิติ
   * ชั้นปีมาจากการจัดห้องของปีการศึกษาที่เลือก คนที่ยังไม่ถูกจัดได้ชั้นปีว่าง
   * และยังถูกนับเสมอ — ตัดทิ้งแล้วยอดรวมจะไม่เท่ากับจำนวนนักศึกษาจริง
   */
  async studentBreakdown(dimension: string, academicYearId: string, status: string) {
    const dim = STUDENT_DIMENSIONS[dimension];
    const where = STATUS_FILTER[status];
    if (!dim || !where) throw new BadRequestException('ไม่รู้จักมิติหรือสถานะที่ขอ');
    const rows = await this.db.query<{ value: string; study_year: number | null; students: string }>(
      `with b as (
         select s.id, s.person_id, s.travel_mode, s.parents_marital,
                pe.gender, pe.birth_date, pe.nationality,
                p.study_year, p.group_code
           from student s
           join person pe on pe.id = s.person_id
           left join student_class_placement p
             on p.student_id = s.id and p.academic_year_id = $1
          where ${where})
       select ${dim.sql} as value, b.study_year, count(*) as students
         from b
        group by 1, 2
        order by 1, 2 nulls first`,
      [academicYearId],
    );
    return {
      dimension,
      label: dim.label,
      rows: rows.map((r) => ({ value: r.value, studyYear: r.study_year, students: Number(r.students) })),
    };
  }

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


/**
 * มิติของรายงานสถิตินักศึกษาแบบ SISA ("ข้อมูลสถิติ" 19 เมนู) — แต่ละมิติคือ
 * นิพจน์ SQL ที่เขียนตายตัวไว้ที่นี่ ชื่อมิติจาก query string ใช้เลือกคีย์
 * เท่านั้น ไม่เคยถูกต่อเข้าไปใน SQL ตรง ๆ
 *
 * ─── ทำไมมิติอ่อนไหวแยกออกมา ───
 * ศาสนา เชื้อชาติ ความพิการ และน้ำหนักส่วนสูงอยู่ใน `person_sensitive` ซึ่ง RLS
 * ให้เห็นทั้งวิทยาลัยเฉพาะ registrar/student_affairs/director/admin (0053)
 * บทบาทอื่นเรียกได้ก็จะได้ตัวเลขที่นับเฉพาะแถวที่ตัวเองเห็น — ยอดผิดโดยไม่มี
 * อะไรฟ้อง จึงปฏิเสธตรง ๆ ดีกว่าคืนตัวเลขที่ดูเหมือนถูก
 */
export const STUDENT_DIMENSIONS: Record<string, { label: string; sql: string; sensitive?: boolean }> = {
  room:        { label: 'ห้อง', sql: `coalesce(b.group_code, 'ยังไม่จัดห้อง')` },
  program:     { label: 'สาขาวิชา/หลักสูตร', sql: `coalesce((select cur.name_th from student_curriculum sc
                    join curriculum_version cv on cv.id = sc.curriculum_version_id
                    join curriculum cur on cur.id = cv.curriculum_id
                   where sc.student_id = b.id and sc.effective_to is null
                   order by sc.effective_from desc limit 1), 'ยังไม่ผูกหลักสูตร')` },
  gender:      { label: 'เพศ', sql: `case b.gender when 'male' then 'ชาย' when 'female' then 'หญิง'
                    when 'other' then 'อื่น ๆ' else 'ไม่ระบุ' end` },
  age:         { label: 'อายุ (ปี)', sql: `coalesce(extract(year from age(current_date, b.birth_date))::int::text, 'ไม่ระบุ')` },
  nationality: { label: 'สัญชาติ', sql: `coalesce(nullif(b.nationality, ''), 'ไม่ระบุ')` },
  province:    { label: 'จังหวัด (ตามทะเบียนบ้าน)', sql: `coalesce((select a.province_th from person_address a
                   where a.person_id = b.person_id and a.kind = 'registered' limit 1), 'ไม่ระบุ')` },
  travel:      { label: 'พาหนะที่ใช้มาเรียน', sql: `case b.travel_mode when 'walk' then 'เดิน'
                    when 'motorcycle' then 'จักรยานยนต์' when 'car' then 'รถยนต์'
                    when 'paid_transit' then 'รถโดยสาร (เสียค่าใช้จ่าย)' when 'free_transit' then 'รถโดยสาร (ไม่เสียค่าใช้จ่าย)'
                    when 'loaned_bicycle' then 'จักรยานยืมเรียน' when 'school_van' then 'รถรับส่งของสถานศึกษา'
                    when 'guardian' then 'ผู้ปกครองรับส่ง' when 'other' then 'อื่น ๆ' else 'ไม่ระบุ' end` },
  marital:     { label: 'สถานภาพบิดา-มารดา', sql: `case b.parents_marital when 'together' then 'อยู่ด้วยกัน'
                    when 'separated' then 'แยกกันอยู่' when 'divorced' then 'หย่าร้าง'
                    when 'father_deceased' then 'บิดาเสียชีวิต' when 'mother_deceased' then 'มารดาเสียชีวิต'
                    when 'both_deceased' then 'เสียชีวิตทั้งคู่' when 'unknown' then 'ไม่ทราบ' else 'ไม่ระบุ' end` },
  fatherJob:   { label: 'อาชีพบิดา', sql: `coalesce((select nullif(sp.occupation_th, '') from student_parent sp
                   where sp.student_id = b.id and sp.role = 'father'), 'ไม่ระบุ')` },
  motherJob:   { label: 'อาชีพมารดา', sql: `coalesce((select nullif(sp.occupation_th, '') from student_parent sp
                   where sp.student_id = b.id and sp.role = 'mother'), 'ไม่ระบุ')` },
  income:      { label: 'รายได้บิดา-มารดารวมต่อเดือน', sql: `(select case
                    when sum(sp.income_monthly) is null then 'ไม่ระบุ'
                    when sum(sp.income_monthly) < 5000 then '1. ต่ำกว่า 5,000'
                    when sum(sp.income_monthly) < 10000 then '2. 5,000–9,999'
                    when sum(sp.income_monthly) < 20000 then '3. 10,000–19,999'
                    when sum(sp.income_monthly) < 50000 then '4. 20,000–49,999'
                    else '5. 50,000 ขึ้นไป' end
                   from student_parent sp where sp.student_id = b.id)` },
  priorSchool: { label: 'สถานศึกษาเดิม', sql: `coalesce((select nullif(pe.school_th, '') from student_prior_education pe
                   where pe.student_id = b.id order by pe.completed_year_be desc nulls last limit 1), 'ไม่ระบุ')` },
  religion:    { label: 'ศาสนา', sensitive: true, sql: `coalesce((select nullif(ps.religion, '') from person_sensitive ps
                   where ps.person_id = b.person_id), 'ไม่ระบุ')` },
  ethnicity:   { label: 'เชื้อชาติ', sensitive: true, sql: `coalesce((select nullif(ps.ethnicity, '') from person_sensitive ps
                   where ps.person_id = b.person_id), 'ไม่ระบุ')` },
  disability:  { label: 'ความพิการ', sensitive: true, sql: `coalesce((select ps.disability::text from person_sensitive ps
                   where ps.person_id = b.person_id), 'ไม่มี/ไม่ระบุ')` },
  bmi:         { label: 'ดัชนีมวลกาย (BMI)', sensitive: true, sql: `(select case
                    when ps.weight_kg is null or ps.height_cm is null then 'ไม่ระบุ'
                    when ps.weight_kg / power(ps.height_cm / 100, 2) < 18.5 then '1. ผอม (ต่ำกว่า 18.5)'
                    when ps.weight_kg / power(ps.height_cm / 100, 2) < 23 then '2. สมส่วน (18.5–22.9)'
                    when ps.weight_kg / power(ps.height_cm / 100, 2) < 25 then '3. ท้วม (23–24.9)'
                    else '4. อ้วน (25 ขึ้นไป)' end
                   from (select 1) one left join person_sensitive ps on ps.person_id = b.person_id)` },
};

const STATUS_FILTER: Record<string, string> = {
  active:    `s.status = 'active'`,
  current:   `s.status in ('active', 'on_leave', 'suspended')`,
  graduated: `s.status = 'graduated'`,
  left:      `s.status in ('withdrawn', 'transferred_out', 'dismissed')`,
  all:       `true`,
};

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

  @Get('students/dimensions')
  studentDimensions() {
    return Object.entries(STUDENT_DIMENSIONS).map(([key, d]) => ({ key, label: d.label, sensitive: !!d.sensitive }));
  }

  @Get('students/breakdown')
  studentBreakdown(
    @Query('dimension') dimension: string,
    @Query('academicYearId', ParseUuidPipe) academicYearId: string,
    @Query('status') status = 'active',
  ) {
    if (STUDENT_DIMENSIONS[dimension]?.sensitive) {
      throw new BadRequestException('มิตินี้อยู่ในข้อมูลอ่อนไหว ใช้เส้นทาง students/breakdown-sensitive');
    }
    return this.svc.studentBreakdown(dimension, academicYearId, status);
  }

  /** เฉพาะบทบาทที่ RLS ให้เห็นข้อมูลอ่อนไหวทั้งวิทยาลัย — ดูเหตุผลที่ STUDENT_DIMENSIONS */
  @Roles('registrar', 'student_affairs', 'director', 'admin')
  @Get('students/breakdown-sensitive')
  studentBreakdownSensitive(
    @Query('dimension') dimension: string,
    @Query('academicYearId', ParseUuidPipe) academicYearId: string,
    @Query('status') status = 'active',
  ) {
    if (!STUDENT_DIMENSIONS[dimension]?.sensitive) {
      throw new BadRequestException('มิตินี้ไม่ใช่ข้อมูลอ่อนไหว ใช้เส้นทาง students/breakdown');
    }
    return this.svc.studentBreakdown(dimension, academicYearId, status);
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

    // จัดกลุ่มตามนักศึกษา — แถวหัวกลุ่มคั่นแทนการพิมพ์รหัส/ชื่อซ้ำทุกแถววิชา
    let groupsHtml = '';
    let currentStudent = '';
    for (const r of rows as Record<string, unknown>[]) {
      if (r.student_code !== currentStudent) {
        currentStudent = r.student_code as string;
        groupsHtml += `<tr class="group-row"><td colspan="5">${esc(r.student_code)} — ${esc(r.full_name)}</td></tr>`;
      }
      groupsHtml += `<tr>
      <td>${esc(r.course_code)}</td>
      <td>${esc(r.course_name)}</td>
      <td class="num">${esc(r.credits)}</td>
      <td class="mid">${r.earns_credit ? esc(r.grade_symbol) : `<span class="tag danger">${esc(r.grade_symbol)}</span>`}</td>
      <td>${esc(r.term_label)}</td>
    </tr>`;
    }

    const body = `<table>
  <thead>
    <tr>
      <th style="width:12%">รหัสวิชา</th>
      <th>ชื่อวิชา</th>
      <th style="width:8%">นก.</th>
      <th style="width:10%">ผลการเรียน</th>
      <th style="width:16%">ภาคเรียน</th>
    </tr>
  </thead>
  <tbody>${rows.length === 0 ? '<tr><td colspan="5" class="mid">— ไม่มีข้อมูลตามเงื่อนไขที่เลือก —</td></tr>' : groupsHtml}</tbody>
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
      <td>${(r.failed_course_codes as string[]).map((c) => `<span class="tag danger">${esc(c)}</span>`).join('')}</td>
    </tr>`,
          )
          .join('')
  }</tbody>
</table>`;

    return reportSheet('นักศึกษาที่ผลการเรียนไม่ผ่านเกณฑ์', `${rows.length} คน`, body);
  }

  @Get('curriculum-check/:studentId')
  curriculumCheck(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.curriculumCheck(studentId);
  }

  @Header('content-type', 'text/html; charset=utf-8')
  @Get('curriculum-check/:studentId/print')
  async curriculumCheckPrint(
    @Param('studentId', ParseUuidPipe) studentId: string,
    @Query('studentLabel') studentLabel?: string,
  ) {
    const rows = await this.svc.curriculumCheck(studentId);
    const STATUS_LABEL: Record<string, string> = {
      enrolled: 'กำลังเรียน', dropped: 'ถอนแล้ว', completed: 'เรียนจบแล้ว',
    };

    const body = `<table>
  <thead>
    <tr>
      <th style="width:4%">ที่</th>
      <th style="width:10%">รหัสวิชา</th>
      <th>ชื่อวิชา</th>
      <th style="width:16%">หมวดวิชา</th>
      <th style="width:6%">นก.</th>
      <th style="width:8%">ปี/ภาคที่แนะนำ</th>
      <th style="width:16%">สถานะ</th>
    </tr>
  </thead>
  <tbody>${
    rows.length === 0
      ? '<tr><td colspan="7" class="mid">— นักศึกษาคนนี้ยังไม่ได้ผูกหลักสูตร —</td></tr>'
      : rows
          .map((r: Record<string, unknown>, i: number) => {
            const status = r.grade_symbol
              ? (r.earns_credit ? 'ผ่านแล้ว' : 'ไม่ผ่าน')
              : (STATUS_LABEL[r.enrollment_status as string] ?? 'ยังไม่ลง');
            const tagKind = r.grade_symbol && !r.earns_credit ? 'danger' : '';
            return `<tr>
      <td class="mid">${i + 1}</td>
      <td>${esc(r.course_code)}</td>
      <td>${esc(r.course_name)}</td>
      <td>${esc(r.category_name)}</td>
      <td class="num">${esc(r.credits)}</td>
      <td class="mid">${r.suggested_year ? `${esc(r.suggested_year)}/${esc(r.suggested_term ?? '—')}` : '—'}</td>
      <td><span class="tag ${tagKind}">${esc(status)}${r.grade_symbol ? ` (${esc(r.grade_symbol)})` : ''}</span></td>
    </tr>`;
          })
          .join('')
  }</tbody>
</table>`;

    return reportSheet('ตรวจสอบหลักสูตร', `${studentLabel ?? studentId} — ${rows.length} วิชา`, body);
  }

  @Get('weekly-attendance/:classSectionId')
  weeklyAttendance(@Param('classSectionId', ParseUuidPipe) classSectionId: string) {
    return this.svc.weeklyAttendance(classSectionId);
  }

  @Header('content-type', 'text/html; charset=utf-8')
  @Get('weekly-attendance/:classSectionId/print')
  async weeklyAttendancePrint(
    @Param('classSectionId', ParseUuidPipe) classSectionId: string,
    @Query('sectionLabel') sectionLabel?: string,
  ) {
    const rows = await this.svc.weeklyAttendance(classSectionId);

    const body = `<table>
  <thead>
    <tr>
      <th style="width:9%">สัปดาห์ที่</th>
      <th style="width:19%">ช่วงวันที่</th>
      <th style="width:10%">คาบที่สอน</th>
      <th style="width:11%">มาเรียน</th>
      <th style="width:11%">มาสาย</th>
      <th style="width:11%">ขาดเรียน</th>
      <th style="width:9%">ลา</th>
      <th>อัตรามาเรียน</th>
    </tr>
  </thead>
  <tbody>${
    rows.length === 0
      ? '<tr><td colspan="8" class="mid">— กลุ่มเรียนนี้ยังไม่มีคาบที่สอนจริง —</td></tr>'
      : rows
          .map((r: Record<string, unknown>) => {
            const present = Number(r.present_count);
            const total = present + Number(r.late_count) + Number(r.absent_count) + Number(r.leave_count);
            const pct = total > 0 ? Math.round((present / total) * 100) : null;
            const tagKind = pct === null ? '' : pct >= 80 ? '' : 'danger';
            return `<tr>
      <td class="mid">${esc(r.week_no)}</td>
      <td class="mid">${esc(thaiDate(r.starts_on as string))} – ${esc(thaiDate(r.ends_on as string))}</td>
      <td class="num">${esc(r.meetings_held)}</td>
      <td class="num">${esc(r.present_count)}</td>
      <td class="num">${esc(r.late_count)}</td>
      <td class="num">${esc(r.absent_count)}</td>
      <td class="num">${esc(r.leave_count)}</td>
      <td>${pct === null ? '—' : `<span class="tag ${tagKind}">${pct}%</span>`}</td>
    </tr>`;
          })
          .join('')
  }</tbody>
</table>`;

    return reportSheet('เวลาเรียนรายสัปดาห์', `${sectionLabel ?? classSectionId} — ${rows.length} สัปดาห์`, body);
  }
}

@Module({
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}

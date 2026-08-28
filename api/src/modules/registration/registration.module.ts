import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  IsArray,
  IsOptional,
  IsString,
} from 'class-validator';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

class CheckDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsArray() @IsUuidArray() sectionIds: string[] = [];
}

class RegisterDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsArray() @ArrayNotEmpty() @IsUuidArray() sectionIds: string[];
}

/**
 * ลงทะเบียนทั้งห้องในครั้งเดียว
 *
 * เพดาน 200 คนไม่ได้มาจากข้อจำกัดทางเทคนิค แต่มาจากรูปแบบการใช้งานจริง —
 * งานทะเบียนลงทะเบียนเป็นห้อง ซึ่งใหญ่สุดราวสี่สิบคน ตัวเลขที่เกินหลักร้อย
 * แปลว่ามีคนกำลังยิงทั้งวิทยาลัยมาในคำขอเดียว ซึ่งจะกลายเป็น transaction
 * ที่ล็อกตาราง enrollment ค้างไว้นานจนคนอื่นลงทะเบียนไม่ได้ทั้งวิทยาลัย
 */
class RegisterBulkDto {
  @IsArray() @ArrayNotEmpty() @ArrayMaxSize(200) @IsUuidArray() studentIds: string[];
  @IsUuid() termId: string;
  @IsArray() @ArrayNotEmpty() @IsUuidArray() sectionIds: string[];
}

class OverrideDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsString() code: string;
  @IsOptional() @IsUuid() classSectionId?: string;
  @IsString() reason: string;
  @IsOptional() @IsString() documentNo?: string;
  @IsUuid() approvedBy: string;
}

/**
 * เพดานรายชื่อในหนึ่งห้อง
 *
 * สูงกว่าเพดานของการลงทะเบียนเป็นกลุ่ม (200) โดยตั้งใจ เพราะการ**ดู**
 * รายชื่อกับการ**เขียน**ในทรานแซกชันเดียวคนละเรื่องกัน — ห้องที่เกิน 200 คน
 * ต้องเห็นได้ว่ามีกี่คนจริง ๆ ถึงจะรู้ว่าต้องไปจัดห้องก่อน
 */
const ROSTER_LIMIT = 500;

export interface RegistrationProblem {
  code: string;
  severity: 'block' | 'warn' | 'info';
  message_th: string;
  class_section_id: string | null;
  waived: boolean;
  detail: Record<string, unknown>;
}

@Injectable()
export class RegistrationService {
  constructor(private readonly db: DbService) {}

  /**
   * คืนรายการปัญหาทั้งหมดในครั้งเดียว ไม่หยุดที่ข้อแรก
   * เพราะนักศึกษาต้องเห็นทุกอย่างที่ต้องแก้ในรอบเดียว ไม่ใช่แก้ทีละข้อแล้วกดใหม่ห้ารอบ
   */
  async check(dto: CheckDto) {
    const problems = await this.db.query<RegistrationProblem>(
      `select code, severity, message_th, class_section_id, waived, detail
         from check_registration($1, $2, $3::uuid[])
        order by case severity when 'block' then 1 when 'warn' then 2 else 3 end, code`,
      [dto.studentId, dto.termId, dto.sectionIds],
    );

    const blocking = problems.filter((p) => p.severity === 'block' && !p.waived);
    return {
      canRegister: blocking.length === 0,
      blockingCount: blocking.length,
      warningCount: problems.filter((p) => p.severity === 'warn').length,
      problems,
    };
  }

  /**
   * ถ้ายังมีข้อ block ที่ไม่ได้ยกเว้น ฟังก์ชันในฐานข้อมูลจะ raise
   * และ transaction ถูก rollback ทั้งหมด — ไม่มีการเขียนบางส่วนค้างไว้
   */
  async register(dto: RegisterDto) {
    const row = await this.db.queryOne<{ registered: number }>(
      `select register_courses($1, $2, $3::uuid[]) as registered`,
      [dto.studentId, dto.termId, dto.sectionIds],
    );
    return { registered: Number(row?.registered ?? 0) };
  }

  /**
   * ต่างจาก register() ตรงที่คนที่ติดเงื่อนไข **ไม่ทำให้คนอื่นล้มไปด้วย**
   *
   * ฟังก์ชันในฐานข้อมูลจึงไม่ raise แต่คืนผลรายคนออกมา ชั้นนี้แค่แปลงรูป
   * ให้หน้าจอใช้ได้ทันที — ใครลงสำเร็จกี่วิชา ใครติดอะไรบ้าง
   */
  async registerBulk(dto: RegisterBulkDto) {
    const rows = await this.db.query<{
      student_id: string;
      registered: number;
      blockers: string | null;
    }>(
      `select student_id, registered, blockers
         from register_courses_bulk($1::uuid[], $2, $3::uuid[])`,
      [dto.studentIds, dto.termId, dto.sectionIds],
    );

    const results = rows.map((r) => ({
      studentId: r.student_id,
      registered: Number(r.registered),
      blockers: r.blockers ? r.blockers.split('\n') : [],
    }));

    return {
      requested: dto.studentIds.length,
      succeeded: results.filter((r) => r.blockers.length === 0).length,
      blocked: results.filter((r) => r.blockers.length > 0).length,
      results,
    };
  }

  /**
   * วิชาที่นักศึกษาคนหนึ่งยังไม่ผ่าน — ใช้กรองรายวิชาในหน้าลงทะเบียนรายคน
   * ให้เห็นเฉพาะวิชาที่ต้องเรียนเสริม/เรียนซ้ำจริง ๆ ดูเหตุผลที่ 0089
   */
  async failedCourses(studentId: string) {
    return this.db.query(
      `select course_id, course_code, course_name, grade_symbol, term_label
         from student_failed_courses($1)`,
      [studentId],
    );
  }

  /** หลักสูตรไหนลงทะเบียนไปแล้วกี่เปอร์เซ็นต์ — เรียงจากน้อยไปมากเพื่อให้ห้องที่ตกหล่นอยู่บนสุด */
  async progress(termId: string) {
    return this.db.query(
      `select curriculum_id, curriculum_name, shift,
              students_total, students_registered, pct
         from registration_progress($1)`,
      [termId],
    );
  }

  /**
   * ห้องประจำทั้งหมดของปีการศึกษาที่ภาคเรียนนี้สังกัด พร้อมความคืบหน้า
   *
   * ─── ทำไมงานทะเบียนต้องเริ่มจากห้อง ไม่ใช่จากรายชื่อคน ───
   * วิทยาลัยที่มีนักศึกษาพันคนมีห้องราวสามสิบห้อง คนอ่านรายการสามสิบแถวได้
   * ทั้งหน้าจอ แต่รายชื่อพันคนไม่มีใครอ่าน — และหน้าจอเดิมโหลดมาแค่ 200 คนแรก
   * ตามรหัส ซึ่งเป็นชุดคนที่ไม่ตรงกับห้องไหน ชั้นไหน หรือหลักสูตรไหนเลย
   *
   * ─── ทำไมตัวหารนับเฉพาะคนที่ยัง active ───
   * หลักเดียวกับ `registration_progress()` — คนที่พักการเรียนหรือลาออกไปแล้ว
   * ลงทะเบียนไม่ได้อยู่แล้ว (0009 ปฏิเสธตั้งแต่ `check_registration`)
   * ถ้านับรวมด้วย ทุกห้องจะค้างอยู่ที่เก้าสิบกว่าเปอร์เซ็นต์ตลอดกาล
   * แล้วตัวเลขจะเลิกบอกว่าเหลืองานหรือไม่เหลือ
   *
   * ห้องที่ยังไม่ได้จัด (`group_code is null`) เป็นแถวหนึ่งเหมือนห้องอื่น
   * ไม่ใช่ถูกกรองทิ้ง เพราะนั่นคือกองที่ต้องจัดการก่อนใครเพื่อน
   */
  async rooms(termId: string) {
    return this.db.query(
      `with t as (
         select id, academic_year_id from term where id = $1
       ),
       roster as (
         select scp.academic_year_id, scp.study_year, scp.group_code, s.id as student_id
           from student_class_placement scp
           join t on t.academic_year_id = scp.academic_year_id
           join student s on s.id = scp.student_id
          where s.status = 'active'
       ),
       registered as (
         select distinct e.student_id
           from enrollment e
          where e.term_id = $1 and e.status = 'enrolled'
       )
       select r.academic_year_id, r.study_year, r.group_code,
              count(*)::integer as students_total,
              count(*) filter (where reg.student_id is not null)::integer as students_registered,
              count(*) filter (where reg.student_id is null)::integer     as students_pending,
              round(100.0 * count(*) filter (where reg.student_id is not null)
                    / nullif(count(*), 0), 2) as pct
         from roster r
         left join registered reg on reg.student_id = r.student_id
        group by r.academic_year_id, r.study_year, r.group_code
        -- ห้องที่ยังไม่ครบอยู่บนสุด ตามหลักเดียวกับ registration_progress()
        order by 7 nulls first, r.study_year, r.group_code nulls first`,
      [termId],
    );
  }

  /**
   * รายชื่อของห้องหนึ่ง + รายวิชาที่ห้องนั้นควรลงในภาคเรียนนี้
   *
   * ─── ทำไมชุดวิชามาจากแผนการเรียน ไม่ใช่ให้ติ๊กเอง ───
   * `curriculum_course.suggested_year/suggested_term` คือแผนการเรียนที่
   * หลักสูตรกำหนดไว้อยู่แล้ว การให้เจ้าหน้าที่ติ๊กสิบสองวิชาเองทุกห้อง
   * คืองานที่ทำซ้ำสามสิบรอบต่อภาคเรียน และเป็นจุดที่ติ๊กตกหล่นได้ง่ายที่สุด
   * โดยไม่มีอะไรฟ้องจนกว่านักศึกษาจะไปดูตารางเรียนตัวเอง
   *
   * ─── ทำไม `students_in_plan` ต้องคืนออกไปด้วย ───
   * ห้องหนึ่งมีนักศึกษาที่สังกัดหลักสูตรคนละฉบับได้จริง (คนตกซ้ำชั้น ·
   * คนย้ายหลักสูตร) วิชาที่มาจากแผนของคนสองคนในห้องสี่สิบคน **ไม่ใช่วิชา
   * ของทั้งห้อง** ถ้าคืนมาปนกันเฉย ๆ เจ้าหน้าที่จะกดลงทั้งห้องแล้วอีก
   * สามสิบแปดคนได้วิชาที่ไม่อยู่ในแผนตัวเองติดไปด้วย
   *
   * ─── ทำไมไม่เดากลุ่มเรียนให้เงียบ ๆ ───
   * `class_section.section_no` เป็นห้องของ**รายวิชา** ส่วน `group_code` เป็น
   * ห้อง**ประจำ** (0031 เขียนกำกับไว้เอง) สองค่านี้บังเอิญหน้าตาเหมือนกัน
   * คือ `1/1` แต่ไม่มีอะไรผูกกันจริง การจับคู่จึงเทียบแบบ**ตรงตัวอักษร
   * เท่านั้น** และคืนเหตุผลออกไปด้วยว่าเดามาจากอะไร — เทียบแบบตัดช่องว่าง
   * หรือตัดศูนย์นำหน้าคือกับดักเดียวกับ "ห้อง 301" กับ "301" ก่อน 0034
   * ซึ่งจับคู่ผิดแล้วไม่มีอาการจนถึงวันเช็คชื่อ
   */
  async roomPlan(p: { termId: string; studyYear: number; groupCode: string | null }) {
    const term = await this.db.queryOne<{
      id: string; ordinal: number; academic_year_id: string; year_be: number;
    }>(
      `select t.id, t.ordinal, t.academic_year_id, ay.year_be
         from term t join academic_year ay on ay.id = t.academic_year_id
        where t.id = $1`,
      [p.termId],
    );
    if (!term) throw new NotFoundException('ไม่พบภาคเรียน หรือไม่มีสิทธิ์เข้าถึง');

    /*
     * นับก่อนดึงรายชื่อ เพราะรายชื่อมีเพดาน
     *
     * ห้องปกติมีสี่สิบคน แต่กองที่ยังไม่ได้จัดห้อง (`group_code is null`)
     * ของวิทยาลัยที่เพิ่งเริ่มใช้ระบบคือ**นักศึกษาทั้งวิทยาลัย** — ถ้าดึงมา
     * ทั้งหมดโดยไม่มีเพดาน หน้าจอจะได้พันแถวในคำขอเดียวซึ่งเป็นอาการที่
     * ทดสอบกับข้อมูลตัวอย่างสิบแถวแล้วไม่มีวันเห็น ส่วนการตัดเงียบ ๆ ก็แย่
     * พอกัน เพราะกดลงทะเบียนแล้วจะได้เฉพาะสองร้อยคนแรกโดยไม่มีอะไรบอก
     * — จึงตัดพร้อมคืนจำนวนจริงออกไปให้หน้าจอบอกผู้ใช้ได้
     */
    const counts = await this.db.queryOne<{
      total: number; active: number; plannable: number;
    }>(
      /*
       * `plannable` คือคนที่ผูกหลักสูตรแล้ว ซึ่งเป็นตัวหารของคำถามว่า
       * "วิชานี้เป็นของทั้งห้องไหม"
       *
       * ─── ทำไมไม่ใช้จำนวนคนที่ลงทะเบียนได้เป็นตัวหาร ───
       * นักศึกษาที่ยังไม่ถูกผูกหลักสูตร (เพิ่งมอบตัว งานทะเบียนยังไม่ผูก)
       * ไม่มีแผนการเรียนให้เทียบ ถ้านับรวมเป็นตัวหาร คนเดียวในห้องสี่สิบคน
       * จะทำให้ทุกวิชากลายเป็น "ไม่ใช่ของทั้งห้อง" แล้วหน้าจอจะไม่ติ๊กอะไร
       * ให้เลยสักวิชา — เจ้าหน้าที่จะสรุปว่าระบบไม่ทำงาน ทั้งที่สิ่งที่ต้องแก้
       * คือไปผูกหลักสูตรให้คนคนนั้น
       *
       * (เห็นตอนกดดูหน้าจอจริงกับข้อมูลที่มีคนแบบนี้อยู่หนึ่งคน ไม่ใช่ตอนอ่านโค้ด)
       */
      `select count(*)::integer as total,
              count(*) filter (where s.status = 'active')::integer as active,
              count(*) filter (
                where s.status = 'active'
                  and exists (select 1 from student_curriculum sc
                               where sc.student_id = s.id
                                 and (sc.effective_to is null
                                      or sc.effective_to >= current_date))
              )::integer as plannable
         from student_class_placement scp
         join student s on s.id = scp.student_id
        where scp.academic_year_id = $1
          and scp.study_year = $2::smallint
          and scp.group_code is not distinct from $3::text`,
      [term.academic_year_id, p.studyYear, p.groupCode],
    );

    const students = await this.db.query<{
      id: string; student_code: string; full_name: string;
      status: string; registered: number; has_curriculum: boolean;
    }>(
      // `is not distinct from` เพราะห้องที่ยังไม่ได้จัดคือ group_code = null
      // ซึ่ง `= null` จะไม่คืนแถวไหนเลยโดยไม่มีอะไรฟ้อง
      `select s.id, s.student_code, s.status,
              trim(coalesce(p.prefix_th,'') || coalesce(p.first_name_th,'')
                   || ' ' || coalesce(p.last_name_th,'')) as full_name,
              (select count(*) from enrollment e
                where e.student_id = s.id and e.term_id = $1
                  and e.status = 'enrolled')::integer as registered,
              -- คนที่ยังไม่ผูกหลักสูตรจะถูก check_registration ปฏิเสธด้วย
              -- NO_CURRICULUM เสมอ หน้าจอต้องบอกล่วงหน้า ไม่ใช่ให้กดแล้วค่อยรู้
              exists (select 1 from student_curriculum sc
                       where sc.student_id = s.id
                         and (sc.effective_to is null
                              or sc.effective_to >= current_date)) as has_curriculum
         from student_class_placement scp
         join student s on s.id = scp.student_id
         join person  p on p.id = s.person_id
        where scp.academic_year_id = $2
          and scp.study_year = $3::smallint
          and scp.group_code is not distinct from $4::text
        order by s.student_code
        limit ${ROSTER_LIMIT}`,
      [p.termId, term.academic_year_id, p.studyYear, p.groupCode],
    );

    const plan = await this.db.query<{
      course_id: string; code: string; name_th: string; credits: string;
      any_required: boolean; students_in_plan: number;
    }>(
      // ชั้นปีของห้องคือปีในแผนการเรียน — คนที่เรียนไม่ตามแผนต้องลงรายคน
      // ที่แท็บอีกใบ ไม่ใช่ให้ทั้งห้องได้ชุดวิชาที่กว้างขึ้นตามคนที่ตกค้าง
      `select cc.course_id, co.code, co.name_th, co.credits,
              bool_or(cc.requirement = 'required') as any_required,
              count(distinct s.id)::integer as students_in_plan
         from student_class_placement scp
         join student s on s.id = scp.student_id and s.status = 'active'
         join student_curriculum sc on sc.student_id = s.id
              and (sc.effective_to is null or sc.effective_to >= current_date)
         join curriculum_course cc on cc.curriculum_version_id = sc.curriculum_version_id
         join course co on co.id = cc.course_id
        where scp.academic_year_id = $1
          and scp.study_year = $2::smallint
          and scp.group_code is not distinct from $3::text
          and cc.suggested_year = $2::smallint
          and cc.suggested_term = $4::smallint
        group by cc.course_id, co.code, co.name_th, co.credits
        order by co.code`,
      // ไม่ส่ง termId มาด้วยทั้งที่คำสั่งข้างบนส่ง — PostgreSQL ล้มทันที
      // ถ้ามีพารามิเตอร์ที่ไม่ถูกอ้างถึงในคำสั่ง จึงนับเลขแยกทุกคำสั่ง
      [term.academic_year_id, p.studyYear, p.groupCode, term.ordinal],
    );

    const sections = await this.db.query<{
      id: string; course_id: string; section_no: string; capacity: number;
      is_locked: boolean; teacher_name: string; enrolled: number;
    }>(
      `select cs.id, cs.course_id, cs.section_no, cs.capacity, cs.is_locked,
              coalesce(tp.first_name_th || ' ' || tp.last_name_th, '') as teacher_name,
              count(e.id) filter (where e.status = 'enrolled')::integer as enrolled
         from class_section cs
         left join staff  ts on ts.id = cs.teacher_id
         left join person tp on tp.id = ts.person_id
         left join enrollment e on e.class_section_id = cs.id
        where cs.term_id = $1
          and cs.course_id = any($2::uuid[])
        group by cs.id, tp.first_name_th, tp.last_name_th
        order by cs.section_no`,
      [p.termId, plan.map((c) => c.course_id)],
    );

    // นับจากคำสั่งนับ ไม่ใช่จากรายชื่อที่ถูกตัด — มิฉะนั้นห้องที่ใหญ่เกิน
    // เพดานจะรายงานว่ามีคนลงทะเบียนได้ 500 คนพอดีทุกครั้ง
    const activeCount = Number(counts?.active ?? 0);
    const plannable = Number(counts?.plannable ?? 0);

    const courses = plan.map((c) => {
      const mine = sections.filter((s) => s.course_id === c.course_id);
      const open = mine.filter((s) => !s.is_locked);

      // เทียบตรงตัวอักษรเท่านั้น และบอกที่มาของการเดาเสมอ
      const byCode = p.groupCode
        ? open.find((s) => s.section_no === p.groupCode)
        : undefined;
      const only = open.length === 1 ? open[0] : undefined;
      const picked = byCode ?? only;

      return {
        courseId: c.course_id,
        code: c.code,
        nameTh: c.name_th,
        credits: c.credits,
        required: c.any_required,
        studentsInPlan: Number(c.students_in_plan),
        // วิชาที่มาจากแผนของคนไม่กี่คนในห้อง ต้องดูออกก่อนกด ไม่ใช่หลังกด
        // เทียบกับคนที่**มีแผน** ไม่ใช่ทุกคนที่ลงทะเบียนได้ (ดูเหตุผลที่คำสั่งนับ)
        wholeRoom: Number(c.students_in_plan) === plannable && plannable > 0,
        sections: mine.map((s) => ({
          id: s.id,
          sectionNo: s.section_no,
          capacity: s.capacity,
          enrolled: Number(s.enrolled),
          teacherName: s.teacher_name,
          isLocked: s.is_locked,
        })),
        suggestedSectionId: picked?.id ?? null,
        suggestedReason: byCode
          ? 'รหัสกลุ่มเรียนตรงกับรหัสห้อง'
          : only
            ? 'วิชานี้เปิดกลุ่มเดียว'
            : null,
      };
    });

    return {
      term: { id: term.id, ordinal: term.ordinal, yearBe: term.year_be },
      room: {
        academicYearId: term.academic_year_id,
        studyYear: p.studyYear,
        groupCode: p.groupCode,
      },
      students: students.map((s) => ({
        id: s.id,
        studentCode: s.student_code,
        fullName: s.full_name,
        status: s.status,
        registered: Number(s.registered),
        hasCurriculum: s.has_curriculum,
      })),
      studentsTotal: Number(counts?.total ?? 0),
      /** รายชื่อถูกตัดไหม — หน้าจอต้องบอกผู้ใช้ ไม่ใช่แสดง 500 จาก 1,240 เฉย ๆ */
      studentsTruncated: Number(counts?.total ?? 0) > students.length,
      registerable: activeCount,
      /** คนที่ผูกหลักสูตรแล้ว — ตัวหารของ `wholeRoom` */
      plannable,
      /** ที่เหลือคือคนที่ยังผูกหลักสูตรไม่ได้ ซึ่งลงทะเบียนไม่ผ่านแน่นอน */
      withoutCurriculum: activeCount - plannable,
      courses,
      /*
       * แผนว่างเปล่าเกิดได้จริงและไม่ใช่ความผิดพลาด — ภาคเรียนปรับพื้นฐาน
       * (ordinal 0) กับภาคฤดูร้อนไม่มีวิชาในแผน และหลักสูตรที่ยังไม่ได้กรอก
       * แผนการเรียนก็เช่นกัน หน้าจอต้องบอกว่าเป็นอย่างไหน ไม่ใช่ขึ้นตารางว่าง
       */
      planEmptyReason:
        courses.length > 0
          ? null
          : Number(counts?.total ?? 0) === 0
            ? 'ยังไม่มีนักศึกษาในห้องนี้'
            : `หลักสูตรของห้องนี้ไม่มีรายวิชาที่กำหนดไว้สำหรับภาคเรียนที่ ${term.ordinal} ของชั้นปี ${p.studyYear} — เลือกวิชาเองได้ที่ปุ่มเพิ่มรายวิชา`,
    };
  }

  async createOverride(dto: OverrideDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `insert into registration_override
         (student_id, term_id, code, class_section_id, reason, document_no, approved_by)
       values ($1, $2, $3, $4, $5, $6, $7)
       returning id`,
      [
        dto.studentId, dto.termId, dto.code, dto.classSectionId ?? null,
        dto.reason, dto.documentNo ?? null, dto.approvedBy,
      ],
    );
    return { id: row!.id };
  }
}

@Controller('registration')
class RegistrationController {
  constructor(private readonly svc: RegistrationService) {}

  @Post('check')
  check(@Body() dto: CheckDto) {
    return this.svc.check(dto);
  }

  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.svc.register(dto);
  }

  /**
   * ลงทะเบียนเป็นกลุ่ม — เฉพาะเจ้าหน้าที่
   *
   * นักศึกษาลงทะเบียนให้คนอื่นไม่ได้ จึงไม่เปิดให้บทบาท student เรียก
   * ต่างจาก /register ที่นักศึกษาลงของตัวเองได้ (RLS กันไว้อีกชั้นอยู่แล้ว)
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Post('register-bulk')
  registerBulk(@Body() dto: RegisterBulkDto) {
    return this.svc.registerBulk(dto);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Get('progress')
  progress(@Query('termId', ParseUuidPipe) termId: string) {
    return this.svc.progress(termId);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Get('students/:id/failed-courses')
  failedCourses(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.failedCourses(id);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Get('rooms')
  rooms(@Query('termId', ParseUuidPipe) termId: string) {
    return this.svc.rooms(termId);
  }

  /**
   * ─── ทำไมไม่ส่ง groupCode มาแปลว่า "ห้องที่ยังไม่ได้จัด" ไม่ใช่ "ทุกห้อง" ───
   * เส้นทางนี้ทำงานกับห้องเดียวเสมอ เพราะผลลัพธ์คือชุดวิชาที่จะกดลงให้คน
   * ทั้งห้อง การตีความว่า "ทุกห้องในชั้นปีนั้น" จะทำให้คนกดปุ่มเดียวแล้ว
   * ลงทะเบียนให้คนหลายร้อยคนพร้อมกันโดยไม่ได้ตั้งใจ — ซึ่งย้อนกลับด้วยการ
   * ถอนรายวิชาทีละคนเท่านั้น
   *
   * และปีการศึกษาอ่านจากภาคเรียนที่ส่งมา ไม่ให้ส่งแยก เพราะห้องของปี 2568
   * กับภาคเรียนของปี 2569 เป็นคำขอที่ไม่มีความหมาย แต่ถ้ารับสองค่าแยกกัน
   * มันจะส่งมาแบบนั้นได้และคืนรายชื่อผิดรุ่นออกไปโดยไม่มีอะไรทัก
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Get('rooms/plan')
  roomPlan(
    @Query('termId', ParseUuidPipe) termId: string,
    @Query('studyYear') studyYear?: string,
    @Query('groupCode') groupCode?: string,
  ) {
    const n = Number(studyYear);
    if (!Number.isInteger(n) || n < 1 || n > 6) {
      throw new BadRequestException('studyYear ต้องเป็นจำนวนเต็ม 1 ถึง 6');
    }
    return this.svc.roomPlan({
      termId,
      studyYear: n,
      groupCode: groupCode ? groupCode : null,
    });
  }

  /** การยกเว้นกฎต้องมีอำนาจ — RLS ในฐานข้อมูลบังคับซ้ำอีกชั้นหนึ่ง */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Post('overrides')
  override(@Body() dto: OverrideDto) {
    return this.svc.createOverride(dto);
  }
}

@Module({
  controllers: [RegistrationController],
  providers: [RegistrationService],
  exports: [RegistrationService],
})
export class RegistrationModule {}

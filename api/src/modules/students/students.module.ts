import {
  BadRequestException,
  Controller,
  Get,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Query,
} from '@nestjs/common';
import { DbService } from '../../common/db/db.service';
import { ParseUuidPipe } from '../../common/validation/uuid';

@Injectable()
export class StudentsService {
  constructor(private readonly db: DbService) {}

  /**
   * ไม่มีเงื่อนไข institution_id ในคำสั่งนี้โดยตั้งใจ
   * เพราะ Row-Level Security กรองให้แล้วจากค่า app.institution_id
   * ถ้าเผลอลืมใส่เงื่อนไขที่ชั้นแอป ผลลัพธ์คือศูนย์แถว ไม่ใช่ข้อมูลของวิทยาลัยอื่น
   */
  /**
   * ค้นหานักศึกษา
   *
   * ─── ทำไมแยกการค้นหาออกเป็น CTE แทนที่จะ OR รวมกัน ───
   * เดิมเขียนเป็น `where code ilike ... or first_name ilike ... or last_name ilike ...`
   * ซึ่งอ่านง่ายกว่า แต่ OR ที่คร่อมสองตาราง (student กับ person) ทำให้
   * PostgreSQL ต้อง join ทั้งสองตารางให้ครบก่อนแล้วค่อยกรอง — ใช้ดัชนีไม่ได้เลย
   *
   * เรื่องนี้สำคัญเป็นพิเศษกับระบบหลายผู้เช่า เพราะทุกวิทยาลัยใช้ตารางเดียวกัน
   * การค้นหาของวิทยาลัยที่มีนักศึกษา 200 คน จึงสแกนแถวของทุกวิทยาลัยรวมกัน
   * แล้วค่อยให้ RLS กรองทิ้ง ยิ่งขายลูกค้าเพิ่ม ลูกค้าเดิมยิ่งช้าลง
   *
   * แยกเป็นสองสาขาแล้วรวมด้วย union ทำให้แต่ละสาขาใช้ดัชนี trigram ของตัวเองได้
   * (ดู migration 0024 — ilike '%คำ%' ใช้ดัชนี btree ไม่ได้เพราะไม่ได้ขึ้นต้นด้วยคำค้น)
   */
  async list(q: string | undefined, limit: number) {
    return this.db.query(
      `with matched as (
         select s2.id from student s2
          where $1::text is null or s2.student_code ilike '%' || $1 || '%'
         union
         select s3.id from student s3
           join person p3 on p3.id = s3.person_id
          where $1::text is not null
            and (p3.first_name_th ilike '%' || $1 || '%'
              or p3.last_name_th  ilike '%' || $1 || '%')
       )
       select s.id, s.student_code, s.status,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              pr.name_th as program_name, pr.level
         from matched m
         join student s on s.id = m.id
         join person  p on p.id = s.person_id
         left join student_curriculum sc on sc.student_id = s.id and sc.effective_to is null
         left join curriculum_version cv on cv.id = sc.curriculum_version_id
         left join curriculum cu on cu.id = cv.curriculum_id
         left join program_track pt on pt.id = cu.program_track_id
         left join program pr on pr.id = pt.program_id
        order by s.student_code
        limit $2`,
      [q ?? null, limit],
    );
  }

  async get(id: string) {
    const row = await this.db.queryOne(
      `select s.id, s.student_code, s.status, s.admitted_year_be,
              p.first_name_th, p.last_name_th, p.birth_date,
              cv.edition_be as curriculum_edition,
              cu.name_th    as curriculum_name,
              pr.level
         from student s
         join person p on p.id = s.person_id
         left join student_curriculum sc on sc.student_id = s.id and sc.effective_to is null
         left join curriculum_version cv on cv.id = sc.curriculum_version_id
         left join curriculum cu on cu.id = cv.curriculum_id
         left join program_track pt on pt.id = cu.program_track_id
         left join program pr on pr.id = pt.program_id
        where s.id = $1`,
      [id],
    );
    if (!row) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์เข้าถึง');
    return row;
  }

  /** เวลาเรียนรายวิชา — ข้อมูลของหน้าจอ A-02 ในแอปนักศึกษา */
  async attendance(studentId: string, termId: string) {
    return this.db.query(
      `select c.code, c.name_th,
              v.pct_to_date, v.pct_projected, v.absences_left,
              v.attendance_state, v.min_pct
         from enrollment e
         join class_section cs on cs.id = e.class_section_id
         join course c         on c.id  = cs.course_id
         join v_enrollment_attendance v on v.enrollment_id = e.id
        where e.student_id = $1 and e.term_id = $2 and e.status = 'enrolled'
        order by v.pct_projected asc`,
      [studentId, termId],
    );
  }

  /** เส้นทางสู่การจบ — ข้อมูลของหน้าจอ A-03 */
  async graduation(studentId: string) {
    return this.db.query(
      `select kind, name_th, required, achieved, satisfied, is_blocking
         from evaluate_graduation($1)`,
      [studentId],
    );
  }

  /**
   * ตารางเรียนของวันที่ระบุ — ข้อมูลของหน้าจอ A-01 ในแอปนักศึกษา
   *
   * อ่านจาก class_meeting ซึ่งเป็นคาบจริงในปฏิทิน ไม่ใช่ section_timeslot
   * ที่เป็นแบบแผนรายสัปดาห์ เพราะคาบจริงหักวันหยุดและรวมการเปลี่ยนแปลงแล้ว
   */
  async schedule(studentId: string, onDate: string) {
    return this.db.query(
      `select cm.id as meeting_id, cm.meets_on, cm.period_from, cm.period_to, cm.status,
              c.code as course_code, c.name_th as course_name,
              -- ห้องของคาบนั้นมาก่อนห้องประจำของกลุ่มเรียน เพราะบางคาบ
              -- ย้ายไปโรงฝึกงาน ซึ่งเป็นห้องที่นักศึกษาต้องไปจริง
              coalesce(slot_room.name_th, default_room.name_th) as room,
              cs.section_no,
              p.first_name_th || ' ' || p.last_name_th as teacher_name
         from enrollment e
         join class_section cs on cs.id = e.class_section_id
         join class_meeting cm on cm.class_section_id = cs.id and cm.meets_on = $2::date
         join course c on c.id = cs.course_id
         left join staff st on st.id = cs.teacher_id
         left join person p on p.id = st.person_id
         left join room default_room on default_room.id = cs.room_id
         left join lateral (
           select r.name_th
             from section_timeslot ts
             join room r on r.id = ts.room_id
            where ts.class_section_id = cs.id
              and ts.day_of_week = extract(isodow from cm.meets_on)
              and cm.period_from between ts.period_from and ts.period_to
            limit 1
         ) slot_room on true
        where e.student_id = $1 and e.status = 'enrolled'
        order by cm.period_from`,
      [studentId, onDate],
    );
  }

  /** ใบแจ้งหนี้ทั้งหมดพร้อมงวด — ข้อมูลของหน้าจอ A-04 */
  async invoices(studentId: string) {
    return this.db.tx(async (c) => {
      const invoices = (
        await c.query(
          `select id, invoice_no, term_id, issued_on, due_on,
                  total, paid_total, total - paid_total as outstanding,
                  status, ref1, ref2
             from invoice
            where student_id = $1 and status <> 'void'
            order by issued_on desc`,
          [studentId],
        )
      ).rows;

      if (invoices.length === 0) return [];

      const installments = (
        await c.query(
          `select invoice_id, seq, due_on, amount, paid_amount, penalty, status
             from installment
            where invoice_id = any($1::uuid[])
            order by invoice_id, seq`,
          [invoices.map((i: { id: string }) => i.id)],
        )
      ).rows as { invoice_id: string }[];

      return invoices.map((inv: { id: string }) => ({
        ...inv,
        installments: installments.filter((n) => n.invoice_id === inv.id),
      }));
    });
  }

  async balance(studentId: string) {
    const row = await this.db.queryOne(
      `select billed, paid, outstanding, next_due_on, days_overdue
         from v_student_balance where student_id = $1`,
      [studentId],
    );
    return row ?? { billed: 0, paid: 0, outstanding: 0, next_due_on: null, days_overdue: null };
  }
}

@Controller('students')
class StudentsController {
  constructor(private readonly svc: StudentsService) {}

  @Get()
  list(@Query('q') q?: string, @Query('limit') limit?: string) {
    return this.svc.list(q, Math.min(Number(limit ?? 50), 200));
  }

  @Get(':id')
  get(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.get(id);
  }

  @Get(':id/attendance')
  attendance(
    @Param('id', ParseUuidPipe) id: string,
    @Query('termId', ParseUuidPipe) termId: string,
  ) {
    return this.svc.attendance(id, termId);
  }

  @Get(':id/graduation')
  graduation(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.graduation(id);
  }

  @Get(':id/balance')
  balance(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.balance(id);
  }

  @Get(':id/schedule')
  schedule(
    @Param('id', ParseUuidPipe) id: string,
    @Query('date') date?: string,
  ) {
    const on = date ?? new Date().toISOString().slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(on)) {
      throw new BadRequestException('date ต้องอยู่ในรูปแบบ YYYY-MM-DD');
    }
    return this.svc.schedule(id, on);
  }

  @Get(':id/invoices')
  invoices(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.invoices(id);
  }
}

@Module({
  controllers: [StudentsController],
  providers: [StudentsService],
  exports: [StudentsService],
})
export class StudentsModule {}

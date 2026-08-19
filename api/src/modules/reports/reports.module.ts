import { Controller, Get, Injectable, Module } from '@nestjs/common';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';

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
}

@Module({
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}

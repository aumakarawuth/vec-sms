import { BadRequestException, Body, Controller, Get, Injectable, Module, NotFoundException, Param, Post, Query } from '@nestjs/common';
import { IsNumber, IsOptional, IsString, Min } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * ค่าซ่อมรายวิชา (0093) — ลงทะเบียนซ่อม → ออกยอดให้การเงิน → รอชำระเงิน →
 * ซ่อนจากสมุดคะแนนจนกว่าจะชำระ (ดูคอมเมนต์เต็มที่ migration)
 *
 * ─── ทำไมมีเส้นทางลงทะเบียน+ออกยอดรวมกันเป็นคำขอเดียว ───
 * `register_courses()` (0009) คืนแค่จำนวนที่ลงสำเร็จ ไม่คืน enrollment_id
 * เพราะออกแบบไว้สำหรับการลงทะเบียนปกติที่ไม่ต้องรู้ id กลับมา — ที่นี่ต้อง
 * เอา enrollment_id ไปออกยอดต่อ จึงลงทะเบียนแล้วค้นกลับด้วย
 * (student_id, class_section_id) ซึ่ง unique อยู่แล้ว แทนที่จะแก้ฟังก์ชัน
 * เดิมที่ผ่านการทดสอบแล้วให้คืนค่าเพิ่ม
 */

class SetPolicyDto {
  @IsNumber() @Min(0) feePerCredit: number;
}

class RegisterRetakeDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsUuid() sectionId: string;
}

class ConfirmPaymentDto {
  @IsString() method: string;
  @IsOptional() @IsString() note?: string;
}

class WaiveDto {
  @IsString() note: string;
}

@Injectable()
export class RetakeFeeService {
  constructor(private readonly db: DbService) {}

  async getPolicy() {
    return this.db.queryOne(
      `select institution_id, fee_per_credit, updated_at from retake_fee_policy
        where institution_id = current_institution_id()`,
    );
  }

  async setPolicy(dto: SetPolicyDto) {
    return this.db.queryOne(
      `insert into retake_fee_policy (institution_id, fee_per_credit, updated_by)
       values (current_institution_id(), $1, current_actor_id())
       on conflict (institution_id) do update
         set fee_per_credit = excluded.fee_per_credit,
             updated_at = now(), updated_by = excluded.updated_by
       returning institution_id, fee_per_credit, updated_at`,
      [dto.feePerCredit],
    );
  }

  /** ลงทะเบียนซ่อมพร้อมออกยอดค่าซ่อมในทรานแซกชันเดียว */
  async registerWithFee(dto: RegisterRetakeDto) {
    return this.db.tx(async (c) => {
      const reg = (
        await c.query<{ registered: number }>(
          `select register_courses($1, $2, array[$3]::uuid[]) as registered`,
          [dto.studentId, dto.termId, dto.sectionId],
        )
      ).rows[0];
      if (!reg || Number(reg.registered) === 0) {
        throw new BadRequestException('ลงทะเบียนไม่สำเร็จ — ตรวจเงื่อนไขการลงทะเบียนก่อน (เช่น ลงซ้ำวิชาเดิมในภาคนี้ไปแล้ว)');
      }

      const enrollment = (
        await c.query<{ id: string }>(
          `select id from enrollment where student_id = $1 and class_section_id = $2`,
          [dto.studentId, dto.sectionId],
        )
      ).rows[0];
      if (!enrollment) {
        throw new BadRequestException('ลงทะเบียนสำเร็จแต่ไม่พบรายการที่เพิ่งลง — ลองใหม่อีกครั้ง');
      }

      const charge = (
        await c.query(
          `select id, credits, rate_per_credit, amount, status from charge_retake_fee($1)`,
          [enrollment.id],
        )
      ).rows[0];

      return { enrollmentId: enrollment.id, charge };
    });
  }

  async listByStudent(studentId: string) {
    return this.db.query(
      `select crc.id, crc.credits, crc.rate_per_credit, crc.amount, crc.status,
              crc.paid_at, crc.method, crc.note, crc.created_at,
              c.code as course_code, c.name_th as course_name,
              cs.section_no
         from course_retake_charge crc
         join enrollment e     on e.id = crc.enrollment_id
         join class_section cs on cs.id = e.class_section_id
         join course c         on c.id = cs.course_id
        where crc.student_id = $1
        order by crc.created_at desc`,
      [studentId],
    );
  }

  /** รายการรอชำระทั้งหมดของวิทยาลัย — งานการเงินใช้ไล่เก็บเงิน */
  async listPending() {
    return this.db.query(
      `select crc.id, crc.amount, crc.created_at,
              s.student_code, trim(coalesce(p.prefix_th,'') || p.first_name_th || ' ' || p.last_name_th) as student_name,
              c.code as course_code, c.name_th as course_name
         from course_retake_charge crc
         join student s on s.id = crc.student_id
         join person p  on p.id = s.person_id
         join enrollment e     on e.id = crc.enrollment_id
         join class_section cs on cs.id = e.class_section_id
         join course c         on c.id = cs.course_id
        where crc.status = 'pending'
        order by crc.created_at`,
    );
  }

  async confirmPayment(id: string, dto: ConfirmPaymentDto) {
    const row = await this.db.queryOne(
      `select id, status, paid_at, amount from confirm_retake_payment($1, $2, $3)`,
      [id, dto.method, dto.note ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบรายการค่าซ่อมนี้');
    return row;
  }

  async waive(id: string, dto: WaiveDto) {
    const row = await this.db.queryOne(
      `select id, status, paid_at, note from waive_retake_fee($1, $2)`,
      [id, dto.note],
    );
    if (!row) throw new NotFoundException('ไม่พบรายการค่าซ่อมนี้');
    return row;
  }
}

@Controller('retake-fee')
class RetakeFeeController {
  constructor(private readonly svc: RetakeFeeService) {}

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('policy')
  getPolicy() {
    return this.svc.getPolicy();
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('retake_fee_policy')
  @Post('policy')
  setPolicy(@Body() dto: SetPolicyDto) {
    return this.svc.setPolicy(dto);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('course_retake_charge')
  @Post('register')
  registerWithFee(@Body() dto: RegisterRetakeDto) {
    return this.svc.registerWithFee(dto);
  }

  @Get('students/:studentId')
  listByStudent(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.listByStudent(studentId);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('pending')
  listPending(@Query() _q: Record<string, never>) {
    return this.svc.listPending();
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('course_retake_charge', 'id')
  @Post(':id/confirm-payment')
  confirmPayment(@Param('id', ParseUuidPipe) id: string, @Body() dto: ConfirmPaymentDto) {
    return this.svc.confirmPayment(id, dto);
  }

  @Roles('finance', 'director', 'admin')
  @Audit('course_retake_charge', 'id')
  @Post(':id/waive')
  waive(@Param('id', ParseUuidPipe) id: string, @Body() dto: WaiveDto) {
    return this.svc.waive(id, dto);
  }
}

@Module({
  controllers: [RetakeFeeController],
  providers: [RetakeFeeService],
})
export class RetakeFeeModule {}

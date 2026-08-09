import { Controller, Get, Injectable, Module } from '@nestjs/common';
import { Roles } from '../../common/auth/auth.guard';
import { RequestContext } from '../../common/context/request-context';
import { DbService } from '../../common/db/db.service';

/**
 * แพ็กเกจและปริมาณใช้งานของวิทยาลัยตัวเอง — อ่านอย่างเดียว
 *
 * ─── ทำไมไม่มีเส้นทางแก้ไขเลย ───
 * ถ้าวิทยาลัยเพิ่มที่นั่งให้ตัวเองได้ ก็เท่ากับซื้อแพ็กเกจฟรี นโยบาย RLS
 * ใน 0038 ปฏิเสธการเขียนจากบริบทที่มีวิทยาลัยอยู่แล้ว ชั้นนี้จึงไม่มี
 * endpoint เขียนให้เผลอเรียก — การเปลี่ยนแพ็กเกจอยู่ที่เส้นทางผู้ให้บริการ
 *
 * ─── ทำไมวิทยาลัยต้องเห็นตัวเลขของตัวเอง ───
 * ใบเรียกเก็บที่ลูกค้าตรวจสอบเองไม่ได้คือใบที่จะถูกเถียงทุกงวด
 * ตัวเลขที่นี่มาจากฟังก์ชันเดียวกับที่ผู้ให้บริการใช้ ไม่ใช่คนละสูตร
 */
@Injectable()
export class SubscriptionService {
  constructor(private readonly db: DbService) {}

  async plans() {
    return this.db.query(
      `select code, name_th, max_students, max_staff,
              price_per_year, price_per_student, enforcement, grace_percent, features
         from plan where active order by sort_order, price_per_year`,
    );
  }

  async current(institutionId: string) {
    const sub = await this.db.queryOne(
      `select subscription_id, plan_code, plan_name_th, status,
              max_students, max_staff, enforcement, grace_percent, seats_purchased
         from active_plan($1)`,
      [institutionId],
    );

    const usage = await this.db.queryOne(
      `select plan_code, plan_name_th, status, enforcement,
              students_active, students_limit, students_allowed, over_students,
              staff_active, staff_limit
         from institution_usage($1)`,
      [institutionId],
    );

    return {
      subscription: sub,
      usage,
      // บอกให้ชัดว่าตอนนี้อยู่ในสถานะไหน แทนที่จะให้หน้าจอไปตีความเอง
      state: !sub
        ? 'ยังไม่ได้ผูกแพ็กเกจ — ยังใช้งานได้ตามปกติ'
        : Number((usage as { over_students?: number })?.over_students ?? 0) > 0
          ? 'ใช้เกินที่ซื้อไว้'
          : 'อยู่ในโควตา',
    };
  }

  /** ประวัติปริมาณใช้งาน — ใช้ตรวจสอบใบเรียกเก็บย้อนหลัง */
  async history(institutionId: string) {
    return this.db.query(
      `select taken_on, students_active, staff_active, documents_issued, applications
         from usage_snapshot
        where institution_id = $1
        order by taken_on desc
        limit 400`,
      [institutionId],
    );
  }
}

@Roles('admin', 'director')
@Controller('subscription')
class SubscriptionController {
  constructor(private readonly svc: SubscriptionService) {}

  /** รายการแพ็กเกจที่มีให้เลือก — ต้องอ่านได้ มิฉะนั้นจะไม่รู้ว่าอัปเกรดเป็นอะไรได้ */
  @Get('plans')
  plans() {
    return this.svc.plans();
  }

  @Get()
  current() {
    return this.svc.current(RequestContext.get()!.institutionId);
  }

  @Get('usage-history')
  history() {
    return this.svc.history(RequestContext.get()!.institutionId);
  }
}

@Module({
  controllers: [SubscriptionController],
  providers: [SubscriptionService],
  exports: [SubscriptionService],
})
export class SubscriptionModule {}

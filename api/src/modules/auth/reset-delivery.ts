import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * การส่งรหัสรีเซ็ตออกไปหาผู้ใช้
 *
 * ─── ทำไมแยกเป็นชั้นของตัวเอง แทนที่จะเรียกผู้ให้บริการตรง ๆ ───
 * ระบบนี้ยังไม่ได้ผูกกับผู้ให้บริการอีเมลหรือ SMS รายใด และการเลือก
 * ผู้ให้บริการเป็นเรื่องของแต่ละวิทยาลัย (บางแห่งมี Google Workspace อยู่แล้ว
 * บางแห่งซื้อโควตา SMS รายปี) ชั้นนี้ทำให้เพิ่มผู้ให้บริการทีหลังได้โดย
 * ไม่ต้องแตะตรรกะการรีเซ็ต ซึ่งเป็นส่วนที่ทดสอบไว้แน่นที่สุด
 *
 * ─── ทำไมค่าเริ่มต้นคือ "ไม่มีช่องทาง" ไม่ใช่ "เขียนลง log" ───
 * ถ้าค่าเริ่มต้นเขียนลง log ระบบจะดูเหมือนทำงานได้ครบ — ผู้ใช้กดขอรีเซ็ต
 * ได้ เห็นข้อความว่าส่งแล้ว แต่ไม่มีรหัสไปถึงใครเลย **และไม่มีอะไรฟ้อง**
 * ซึ่งเป็นความล้มเหลวแบบเงียบที่หลักข้อ 6 ของโปรเจกต์นี้ห้ามไว้
 *
 * เมื่อไม่ได้ตั้งค่า ระบบจะบอกผู้ใช้ตรง ๆ ว่าให้ติดต่องานทะเบียน
 * ซึ่งเป็นความจริง และช่องทางเคาน์เตอร์ก็ยังใช้ได้เต็มรูปแบบอยู่แล้ว
 */

export interface ResetMessage {
  channel: 'email' | 'sms';
  /** ปลายทางที่ปิดบังแล้ว — ค่าจริงอยู่ที่ผู้ส่งไปหยิบเอง ไม่ผ่านชั้นนี้ */
  destinationHint: string;
  code: string;
  expiresAt: Date;
  institutionId: string;
  personId: string;
}

export type DeliveryMode = 'none' | 'log';

@Injectable()
export class ResetDelivery {
  private readonly logger = new Logger(ResetDelivery.name);

  constructor(private readonly config: ConfigService) {}

  get mode(): DeliveryMode {
    return this.config.get<string>('RESET_DELIVERY') === 'log' ? 'log' : 'none';
  }

  get available(): boolean {
    return this.mode !== 'none';
  }

  /**
   * ส่งรหัสออกไป
   *
   * ผู้ให้บริการจริงที่จะมาเสียบตรงนี้ในอนาคตควร **เข้าคิว** ไม่ใช่ยิงตรง
   * ด้วยเหตุผลสองข้อ — เวลาที่ใช้ส่งจะกลายเป็นตัวบอกว่ารหัสประจำตัวไหน
   * มีอยู่จริง (คำขอที่หาบัญชีไม่เจอจะตอบเร็วกว่าอย่างเห็นได้ชัด)
   * และผู้ให้บริการที่ล่มชั่วคราวจะทำให้คำขอของผู้ใช้ล้มไปด้วย
   */
  async send(message: ResetMessage): Promise<void> {
    if (this.mode === 'log') {
      // เฉพาะเครื่องพัฒนา — production-guard ปฏิเสธไม่ให้บูตถ้าตั้งค่านี้ในระบบจริง
      this.logger.warn(
        `[เครื่องพัฒนาเท่านั้น] รหัสรีเซ็ตของ person=${message.personId} ` +
          `ช่องทาง ${message.channel} → ${message.destinationHint} ` +
          `คือ ${message.code} หมดอายุ ${message.expiresAt.toLocaleString('th-TH')}`,
      );
    }
  }
}

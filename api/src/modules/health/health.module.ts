import { Controller, Get, Module } from '@nestjs/common';
import { DbService } from '../../common/db/db.service';
import { Public } from '../../common/auth/auth.guard';
import { NoThrottle } from '../../common/throttle/throttle.guard';

@Controller('health')
class HealthController {
  constructor(private readonly db: DbService) {}

  // ระบบตรวจสอบยิง endpoint นี้ถี่โดยตั้งใจ การจำกัดจะทำให้ health check
  // ล้มเหลวเองแล้วแพลตฟอร์มจะรีสตาร์ท service ทิ้งโดยไม่มีอะไรผิดจริง
  @NoThrottle()
  @Public()
  @Get()
  async check() {
    const db = await this.db.ping();
    return {
      status: 'ok',
      database: db.ok ? 'up' : 'down',
      serverVersion: db.version.split(' ').slice(0, 2).join(' '),
      time: new Date().toISOString(),
    };
  }
}

@Module({ controllers: [HealthController] })
export class HealthModule {}

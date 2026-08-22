import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';

import { DbModule } from './common/db/db.module';
import { AuthGuard } from './common/auth/auth.guard';
import { ContextInterceptor } from './common/context/context.interceptor';
import { PgExceptionFilter } from './common/filters/pg-exception.filter';
import { ThrottleGuard } from './common/throttle/throttle.guard';
import { AuditInterceptor } from './common/audit/audit.interceptor';

import { HealthModule } from './modules/health/health.module';
import { AuthModule } from './modules/auth/auth.module';
import { StudentsModule } from './modules/students/students.module';
import { RegistrationModule } from './modules/registration/registration.module';
import { AttendanceModule } from './modules/attendance/attendance.module';
import { FinanceModule } from './modules/finance/finance.module';
import { RiskModule } from './modules/risk/risk.module';
import { JobsModule } from './modules/jobs/jobs.module';
import { GradebookModule } from './modules/gradebook/gradebook.module';
import { CurriculumModule } from './modules/curriculum/curriculum.module';
import { DualModule } from './modules/dual/dual.module';
import { StaffModule } from './modules/staff/staff.module';
import { ImportModule } from './modules/import/import.module';
import { DocumentsModule } from './modules/documents/documents.module';
import { AcademicModule } from './modules/academic/academic.module';
import { AdmissionsModule } from './modules/admissions/admissions.module';
import { HrModule } from './modules/hr/hr.module';
import { ProvisioningModule } from './modules/provisioning/provisioning.module';
import { PlatformModule } from './modules/platform/platform.module';
import { SubscriptionModule } from './modules/subscription/subscription.module';
import { GovernmentExportsModule } from './modules/government-exports/government-exports.module';
import { ReportsModule } from './modules/reports/reports.module';
import { ClubsModule } from './modules/clubs/clubs.module';
import { OnetModule } from './modules/onet/onet.module';
import { ExamScheduleModule } from './modules/exam-schedule/exam-schedule.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        signOptions: { expiresIn: config.get('JWT_TTL') ?? '12h' },
      }),
    }),
    DbModule,

    HealthModule,
    AuthModule,
    StudentsModule,
    RegistrationModule,
    AttendanceModule,
    FinanceModule,
    RiskModule,
    GradebookModule,
    CurriculumModule,
    DualModule,
    StaffModule,
    ImportModule,
    DocumentsModule,
    AcademicModule,
    AdmissionsModule,
    HrModule,
    ProvisioningModule,
    PlatformModule,
    SubscriptionModule,
    GovernmentExportsModule,
    ReportsModule,
    ClubsModule,
    OnetModule,
    ExamScheduleModule,
    JobsModule,
  ],
  providers: [
    // ลำดับสำคัญ: จำกัดจำนวนครั้งก่อนตรวจ token เพราะการตรวจ token
    // ที่ปลอมมาก็กินซีพียู การปล่อยให้ยิงรัวก่อนแล้วค่อยปฏิเสธจึงไม่ช่วยอะไร
    { provide: APP_GUARD, useClass: ThrottleGuard },

    // จากนั้น guard ตรวจ token และเติม req.userContext
    // แล้ว interceptor จึงย้ายบริบทเข้า AsyncLocalStorage ให้ DbService ใช้
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_INTERCEPTOR, useClass: ContextInterceptor },

    // ต้องมาหลัง ContextInterceptor เพราะบันทึกการเข้าถึงเขียนผ่าน DbService
    // ซึ่งต้องมีบริบทผู้ใช้อยู่ใน AsyncLocalStorage แล้ว
    { provide: APP_INTERCEPTOR, useClass: AuditInterceptor },
    { provide: APP_FILTER, useClass: PgExceptionFilter },
  ],
})
export class AppModule {}

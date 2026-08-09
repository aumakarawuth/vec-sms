import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { AuthedRequest } from '../auth/auth.guard';
import { RequestContext } from './request-context';

/**
 * ย้ายบริบทที่ AuthGuard ตรวจแล้วเข้าไปใน AsyncLocalStorage
 *
 * ต้องเป็น interceptor ไม่ใช่ middleware เพราะ middleware ทำงานก่อน guard
 * ตอนนั้นยังไม่รู้ว่าผู้ใช้เป็นใคร ส่วน interceptor ทำงานหลัง guard ผ่านแล้ว
 * และครอบทั้ง handler ทำให้ทุก query ที่เกิดในคำขอนี้เห็นบริบทเสมอ
 */
@Injectable()
export class ContextInterceptor implements NestInterceptor {
  intercept(ctx: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    if (!req.userContext) {
      return next.handle();
    }
    return RequestContext.run(req.userContext, () => next.handle());
  }
}

import {
  CanActivate,
  ExecutionContext,
  Injectable,
  SetMetadata,
  UnauthorizedException,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import { AppRole, UserContext } from '../context/request-context';

export type { AppRole };

export const PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(PUBLIC_KEY, true);

export const ROLES_KEY = 'roles';
export const Roles = (...roles: AppRole[]) => SetMetadata(ROLES_KEY, roles);

export const MFA_CHALLENGE_KEY = 'allowMfaChallenge';

/**
 * ยอมรับ token ชั่วคราวจากขั้นล็อกอิน (stage=mfa) กับเส้นทางนี้
 *
 * ─── ใช้ได้เฉพาะขั้นตอน "ตั้งค่า" MFA เท่านั้น ───
 * บทบาทที่ถูกบังคับยืนยันสองชั้นจะได้แต่ token ชั่วคราวจนกว่าจะยืนยันเสร็จ
 * ถ้าเส้นทางตั้งค่าไม่รับ token ชั่วคราว คนที่ยังไม่เคยตั้งจะตั้งไม่ได้เลย
 * และเข้าระบบไม่ได้ตลอดไป — ซึ่งเกิดกับผู้ดูแลคนแรกของทุกวิทยาลัยที่เปิดใหม่
 *
 * **ห้ามติดกับเส้นทางอื่นเด็ดขาด** token ชั่วคราวได้มาด้วยรหัสผ่านอย่างเดียว
 * ถ้ามันใช้กับเส้นทางที่แตะข้อมูลได้ ชั้นที่สองจะไม่มีความหมายอะไรเลย
 */
export const AllowMfaChallenge = () => SetMetadata(MFA_CHALLENGE_KEY, true);

/** เก็บบริบทไว้บน request เพื่อให้ middleware ตัวถัดไปหยิบไปใส่ AsyncLocalStorage */
export interface AuthedRequest extends Request {
  userContext?: UserContext;
}

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(PUBLIC_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (isPublic) return true;

    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedException('ต้องแนบ Bearer token');
    }

    let payload: { sub: string; inst: string; role: AppRole; stage?: string };
    try {
      payload = await this.jwt.verifyAsync(header.slice(7));
    } catch {
      throw new UnauthorizedException('token ไม่ถูกต้องหรือหมดอายุ');
    }

    if (!payload.inst || !payload.sub || !payload.role) {
      throw new UnauthorizedException('token ขาดข้อมูลสถานศึกษา ผู้ใช้ หรือบทบาท');
    }

    /*
     * token ระหว่างรอยืนยันสองชั้นใช้ได้เฉพาะเส้นทางที่ติด
     * @AllowMfaChallenge() ไว้ ซึ่งมีแค่ขั้นตอนตั้งค่า MFA
     *
     * ข้อนี้คือทั้งหมดของ MFA — ถ้า token ชั่วคราวที่ออกให้หลังตรวจรหัสผ่าน
     * ใช้แทน access token ได้ ชั้นที่สองจะกลายเป็นแค่หน้าจอที่ข้ามได้
     * ด้วยการเรียก endpoint อื่นตรง ๆ โดยไม่ต้องใส่รหัสอะไรเลย
     *
     * แต่ถ้าปิดหมดทุกเส้นทางรวมถึงเส้นทางตั้งค่าเอง คนที่ยังไม่เคยตั้ง MFA
     * จะไม่มีวันตั้งได้ และเข้าระบบไม่ได้อีกเลย
     */
    const mfaPending = payload.stage === 'mfa';
    if (mfaPending) {
      const allowed = this.reflector.getAllAndOverride<boolean>(MFA_CHALLENGE_KEY, [
        ctx.getHandler(),
        ctx.getClass(),
      ]);
      if (!allowed) {
        throw new UnauthorizedException(
          'token นี้ใช้ได้เฉพาะขั้นยืนยันตัวตนสองชั้น ต้องยืนยันให้เสร็จก่อน',
        );
      }
    }

    req.userContext = {
      institutionId: payload.inst,
      actorId: payload.sub,
      role: payload.role,
      requestId: req.header('x-request-id') ?? undefined,
      mfaPending: mfaPending || undefined,
    };

    const required = this.reflector.getAllAndOverride<AppRole[]>(ROLES_KEY, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (required?.length && !required.includes(payload.role)) {
      throw new ForbiddenException(
        `ต้องเป็นบทบาท ${required.join(' หรือ ')} จึงจะใช้คำสั่งนี้ได้`,
      );
    }

    return true;
  }
}

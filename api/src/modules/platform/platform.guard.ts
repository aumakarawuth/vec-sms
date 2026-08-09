import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { AuthedRequest } from '../../common/auth/auth.guard';
import { AppRole, UserContext } from '../../common/context/request-context';

/**
 * ประตูของฝั่งผู้ให้บริการ
 *
 * ─── ทำไมไม่ใช้ AuthGuard เดิม ───
 * AuthGuard บังคับว่า token ต้องมี `inst` เสมอ ซึ่งถูกต้องสำหรับผู้ใช้ทุกคน
 * ของทุกวิทยาลัย แต่ผู้ให้บริการไม่ได้อยู่ในวิทยาลัยไหน การยัด inst ปลอม
 * ลงไปให้ผ่าน guard เดิมคือการสร้าง "วิทยาลัยปลอม" ที่จะโผล่ในรายงาน
 * ในโควตา และในการนับยอดขายตลอดไป
 *
 * ─── กำแพงสองทาง ซึ่งเป็นหัวใจของไฟล์นี้ ───
 * token สองชนิดต้องข้ามฝั่งกันไม่ได้ทั้งคู่
 *
 *   token ของวิทยาลัย → เส้นทาง /platform/*  : ไม่มี kind='platform' จึงถูกปฏิเสธที่นี่
 *   token ของผู้ให้บริการ → เส้นทางของวิทยาลัย : ไม่มี inst จึงถูก AuthGuard ปฏิเสธ
 *
 * ถ้าขาดข้อใดข้อหนึ่ง admin ของวิทยาลัยหนึ่งจะเรียกหน้าจอข้ามวิทยาลัยได้
 * หรือผู้ให้บริการจะอ่านข้อมูลนักศึกษาได้ ทั้งคู่เป็นเหตุร้ายแรง
 * (เทสต์ PLAT-01 และ PLAT-02 ยิงจริงทั้งสองทาง)
 */

export type PlatformRole = 'owner' | 'billing' | 'support';

/**
 * บทบาทที่ส่งให้ฐานข้อมูลผ่าน app.role
 *
 * ไม่ได้อยู่ใน AppRole เพราะไม่ใช่บทบาทในวิทยาลัย — cast เหมือนที่
 * AuthService ทำกับบทบาท 'auth' ตอนตรวจรหัสผ่าน ค่าทั้งสองนี้เป็นครึ่งหนึ่ง
 * ของเงื่อนไข is_platform_context() ในฐานข้อมูล (อีกครึ่งคือไม่มีวิทยาลัย)
 */
export const PLATFORM_DB_ROLE = 'platform' as AppRole;
export const PLATFORM_AUTH_DB_ROLE = 'platform_auth' as AppRole;

/**
 * บริบทฐานข้อมูลของผู้ให้บริการ
 *
 * institutionId ต้องเป็นสตริงว่าง ไม่ใช่ UUID ศูนย์ — `current_institution_id()`
 * แปลงค่าว่างเป็น null ซึ่งเป็นเงื่อนไขที่นโยบายทั้งหมดของฝั่งนี้ใช้
 * UUID ศูนย์จะกลายเป็นวิทยาลัยที่ไม่มีอยู่จริง แล้วทุกอย่างจะถูกปฏิเสธ
 * โดยไม่มีใครเข้าใจว่าทำไม
 */
export function platformCtx(actorId = ''): UserContext {
  return { institutionId: '', actorId, role: PLATFORM_DB_ROLE };
}

/** บริบทช่วงตรวจรหัสผ่าน — ยังไม่รู้ว่าเป็นใคร จึงยังไม่มี actor */
export function platformAuthCtx(): UserContext {
  return { institutionId: '', actorId: '', role: PLATFORM_AUTH_DB_ROLE };
}

export const PLATFORM_PUBLIC_KEY = 'platformPublic';
/** เส้นทางที่ยังไม่มี token ได้ เช่น ล็อกอิน ตั้งรหัสผ่านครั้งแรก */
export const PlatformPublic = () => SetMetadata(PLATFORM_PUBLIC_KEY, true);

export const PLATFORM_ROLES_KEY = 'platformRoles';
export const PlatformRoles = (...roles: PlatformRole[]) =>
  SetMetadata(PLATFORM_ROLES_KEY, roles);

export const PLATFORM_MFA_KEY = 'platformAllowMfaChallenge';
/**
 * ยอมรับ token ชั่วคราวจากขั้นล็อกอินกับเส้นทางนี้
 *
 * บทเรียนจาก 0036 ข้อ 6 — บัญชีที่ยังไม่ได้ตั้ง MFA จะได้แต่ token ชั่วคราว
 * ถ้าเส้นทาง "ตั้งค่า MFA" ไม่ยอมรับ token ชั่วคราว วงจรจะปิดสนิท
 * ไม่มีทางเข้าเลยสักทาง และกระทบผู้ให้บริการคนแรกซึ่งคือทุกคนตอนติดตั้ง
 *
 * **ห้ามติดกับเส้นทางอื่นเด็ดขาด** token ชั่วคราวได้มาด้วยรหัสผ่านอย่างเดียว
 */
export const AllowPlatformMfaChallenge = () => SetMetadata(PLATFORM_MFA_KEY, true);

/** สิ่งที่อยู่ใน token ของผู้ให้บริการ */
export interface PlatformClaims {
  sub: string;
  kind: 'platform';
  prole?: PlatformRole;
  stage?: 'mfa';
}

export interface PlatformRequest extends AuthedRequest {
  platform?: { userId: string; role?: PlatformRole; mfaPending: boolean };
}

@Injectable()
export class PlatformGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    if (
      this.reflector.getAllAndOverride<boolean>(PLATFORM_PUBLIC_KEY, [
        ctx.getHandler(),
        ctx.getClass(),
      ])
    ) {
      return true;
    }

    const req = ctx.switchToHttp().getRequest<PlatformRequest>();
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedException('ต้องแนบ Bearer token ของผู้ให้บริการ');
    }

    let claims: PlatformClaims;
    try {
      claims = await this.jwt.verifyAsync<PlatformClaims>(header.slice(7));
    } catch {
      throw new UnauthorizedException('token ไม่ถูกต้องหรือหมดอายุ');
    }

    // ─── ด่านที่กัน token ของวิทยาลัยไม่ให้เข้ามา ───
    // token ทั้งสองชนิดเซ็นด้วยกุญแจเดียวกัน จึงตรวจลายเซ็นผ่านทั้งคู่
    // สิ่งที่แยกได้คือ claim นี้ ซึ่งออกให้เฉพาะเส้นทางล็อกอินของฝั่งนี้
    if (claims.kind !== 'platform' || !claims.sub) {
      throw new ForbiddenException(
        'token นี้เป็นของผู้ใช้ในสถานศึกษา ใช้กับหน้าจอผู้ให้บริการไม่ได้',
      );
    }

    const mfaPending = claims.stage === 'mfa';
    if (mfaPending) {
      const allowed = this.reflector.getAllAndOverride<boolean>(PLATFORM_MFA_KEY, [
        ctx.getHandler(),
        ctx.getClass(),
      ]);
      if (!allowed) {
        throw new UnauthorizedException(
          'token นี้ใช้ได้เฉพาะขั้นยืนยันตัวตนสองชั้น ต้องยืนยันให้เสร็จก่อน',
        );
      }
    }

    req.platform = { userId: claims.sub, role: claims.prole, mfaPending };
    req.userContext = platformCtx(claims.sub);

    const required = this.reflector.getAllAndOverride<PlatformRole[]>(
      PLATFORM_ROLES_KEY,
      [ctx.getHandler(), ctx.getClass()],
    );
    if (required?.length && (!claims.prole || !required.includes(claims.prole))) {
      throw new ForbiddenException(
        `ต้องเป็นผู้ดูแลระดับ ${required.join(' หรือ ')} จึงจะใช้คำสั่งนี้ได้`,
      );
    }

    return true;
  }
}

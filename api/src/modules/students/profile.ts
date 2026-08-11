/**
 * ระเบียนนักศึกษาฉบับเต็ม — แปดกลุ่มข้อมูลตาม migration 0053
 *
 * ─── ทำไมข้อมูลอ่อนไหวคืน null แทนที่จะคืน 403 ───
 * ครูผู้สอนที่ไม่ใช่ที่ปรึกษาอ่านข้อมูลสุขภาพไม่ได้ ซึ่งถูกต้อง แต่เขา
 * **ต้อง**เปิดระเบียนนักศึกษาได้ตามปกติเพื่อดูเรื่องอื่น ถ้าชั้นนี้โยน 403
 * เมื่ออ่านข้อมูลอ่อนไหวไม่ได้ ทั้งหน้าจอจะพังทั้งที่ผู้ใช้มีสิทธิ์เกือบทุกส่วน
 * จึงคืน `sensitive: null` แล้วให้หน้าจอบอกว่า "ไม่มีสิทธิ์ดูส่วนนี้"
 *
 * และนี่ไม่ใช่การเลี่ยงกฎ — RLS เป็นคนตัดสิน ชั้นนี้แค่ไม่แปลง "ศูนย์แถว"
 * เป็นข้อผิดพลาด การกรองเกิดที่ฐานข้อมูลเสมอ ต่อให้เรียกผ่าน pgAdmin ก็ได้ผลเดียวกัน
 *
 * ─── ทำไมไม่มี endpoint ไหนคืนเลขบัตรประชาชน ───
 * ทั้ง `person` และ `student_parent` เก็บเฉพาะค่าแฮช ชั้นนี้จึงรับเลขเข้าไป
 * ส่งให้ `digest()` ในคำสั่ง SQL แล้วไม่เก็บไว้ที่ไหนอีก — กรอกได้แต่อ่านกลับไม่ได้
 * เป็นข้อจำกัดที่ตั้งใจ ไม่ใช่ข้อมูลหาย
 *
 * ─── ทำไมการบันทึกเป็น upsert ไม่ใช่ insert/update แยกกัน ───
 * ทั้งสามตารางมี unique ตามธรรมชาติอยู่แล้ว (`person_id` · `(person_id, kind)` ·
 * `(student_id, role)`) หน้าจอจึงส่งฟอร์มทั้งใบมาได้โดยไม่ต้องรู้ว่าแถวมีอยู่หรือยัง
 * ถ้าแยกสองเส้นทาง หน้าจอต้องเดา แล้วจะเดาผิดตอนสองคนกรอกพร้อมกัน
 */
import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Injectable,
  NotFoundException,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import {
  IsIn,
  IsISO8601,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  Max,
  Min,
} from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import {
  decryptNationalId,
  decryptionKeys,
  encryptNationalId,
  formatNationalId,
  hashNationalId,
  isValidThaiNationalId,
  normalizeNationalId,
} from '../../common/crypto/national-id';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';

const ADDRESS_KINDS = ['registered', 'current', 'work'] as const;
const PARENT_ROLES = ['father', 'mother'] as const;
const PARENT_STATUS = ['alive', 'deceased', 'unknown'] as const;
const MARITAL = [
  'together', 'separated', 'divorced',
  'father_deceased', 'mother_deceased', 'both_deceased', 'unknown',
] as const;
const DISABILITY = [
  'none', 'vision', 'hearing', 'intellectual', 'physical',
  'learning', 'speech', 'behavioral', 'autistic', 'multiple',
] as const;
const TRAVEL = [
  'walk', 'motorcycle', 'car', 'paid_transit', 'free_transit',
  'loaned_bicycle', 'school_van', 'guardian', 'other',
] as const;

class UpdateProfileDto {
  // person
  @IsOptional() @IsString() prefixEn?: string;
  @IsOptional() @IsString() nicknameTh?: string;
  @IsOptional() @IsString() nicknameEn?: string;
  @IsOptional() @IsString() nationality?: string;
  @IsOptional() @IsString() lineId?: string;
  @IsOptional() @IsString() facebook?: string;
  @IsOptional() @IsString() birthPlaceTh?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() email?: string;

  // student
  @IsOptional() @IsInt() @Min(1) @Max(30) siblingsCount?: number;
  @IsOptional() @IsInt() @Min(1) @Max(30) birthOrder?: number;
  @IsOptional() @IsInt() @Min(0) @Max(30) siblingsStudying?: number;
  @IsOptional() @IsIn(MARITAL) parentsMarital?: string;
  @IsOptional() @IsInt() @Min(1) @Max(99) classNumber?: number;
  @IsOptional() @IsIn(TRAVEL) travelMode?: string;
  @IsOptional() @IsString() talentTh?: string;

  /**
   * เลขประจำตัวประชาชนของนักศึกษา — ใบ รบ. พิมพ์เลขนี้เต็มบนกระดาษ
   *
   * รับเข้าอย่างเดียว **ไม่เคยส่งกลับ** ในการอ่านระเบียนตามปกติ
   * ผู้ที่มีสิทธิ์ดูต้องเรียก `GET /students/:id/national-id` ซึ่งบันทึกลง
   * access_log ทุกครั้งว่าใครเปิดดูของใคร (PDPA ม.37)
   */
  @IsOptional() @IsString() nationalId?: string;
}

class SensitiveDto {
  @IsOptional() @IsString() ethnicity?: string;
  @IsOptional() @IsString() religion?: string;
  @IsOptional() @IsIn(['A', 'B', 'AB', 'O']) bloodType?: string;
  @IsOptional() @IsString() drugAllergy?: string;
  @IsOptional() @IsString() chronicDisease?: string;
  @IsOptional() @IsNumber() @Min(10) @Max(300) weightKg?: number;
  @IsOptional() @IsNumber() @Min(50) @Max(250) heightCm?: number;
  @IsOptional() @IsString() distinguishing?: string;
  @IsOptional() @IsIn(DISABILITY) disability?: string;
  @IsOptional() @IsString() disabilityNote?: string;
  @IsOptional() @IsString() note?: string;
}

class AddressDto {
  @IsIn(ADDRESS_KINDS) kind: string;
  @IsString() addressLine: string;
  @IsOptional() @IsString() subdistrictTh?: string;
  @IsOptional() @IsString() districtTh?: string;
  @IsOptional() @IsString() provinceTh?: string;
  @IsOptional() @IsString() postalCode?: string;
}

class ParentDto {
  @IsIn(PARENT_ROLES) role: string;
  @IsOptional() @IsString() prefixTh?: string;
  @IsString() firstNameTh: string;
  @IsOptional() @IsString() lastNameTh?: string;
  @IsOptional() @IsString() nationalId?: string;
  @IsOptional() @IsISO8601() birthDate?: string;
  @IsOptional() @IsString() occupationTh?: string;
  @IsOptional() @IsNumber() @Min(0) incomeMonthly?: number;
  @IsOptional() @IsIn(PARENT_STATUS) status?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() workPhone?: string;
  @IsOptional() @IsString() email?: string;
  @IsOptional() @IsString() addressLine?: string;
  @IsOptional() @IsString() subdistrictTh?: string;
  @IsOptional() @IsString() districtTh?: string;
  @IsOptional() @IsString() provinceTh?: string;
  @IsOptional() @IsString() postalCode?: string;
}

class PriorEducationDto {
  @IsString() levelTh: string;
  @IsOptional() @IsInt() @Min(2400) @Max(2700) completedYearBe?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(4) gpax?: number;
  @IsOptional() @IsString() programTh?: string;
  @IsOptional() @IsString() programTypeTh?: string;
  @IsOptional() @IsString() schoolTh?: string;
  @IsOptional() @IsString() provinceTh?: string;
  @IsOptional() @IsString() note?: string;
}

class AssignAdvisorDto {
  @IsUuid() staffId: string;
  @IsOptional() @IsUuid() academicYearId?: string;
  @IsOptional() isPrimary?: boolean;
  @IsOptional() @IsString() note?: string;
}

/** ตรงกับ enum `student_status` ในฐานข้อมูล — กฎจริงอยู่ที่นั่น ที่นี่ไว้บอกผู้ใช้ */
const STUDENT_STATUS = [
  'active', 'on_leave', 'suspended', 'withdrawn',
  'transferred_out', 'dismissed', 'graduated',
] as const;

class StatusChangeDto {
  @IsIn(STUDENT_STATUS) status: string;
  /** วันที่มีผล — ใบ รบ. พิมพ์ค่านี้ในช่อง "ออกจากสถานศึกษาเมื่อ" */
  @IsISO8601() effectiveOn: string;
  /**
   * เหตุผล — ใบ รบ. พิมพ์ในช่อง "เหตุที่ออก"
   *
   * บังคับกรอกเมื่อเป็นสถานะที่แปลว่าออกจากสถานศึกษา เพราะใบที่พิมพ์
   * "เหตุที่ออก" ว่างไว้คือเอกสารที่ตอบคำถามของคนอ่านไม่ได้ และตอนที่
   * นักศึกษามาขอใบก็สายเกินกว่าจะย้อนไปถามว่าตอนนั้นเกิดอะไรขึ้น
   */
  @IsOptional() @IsString() reason?: string;
  /** เลขที่คำสั่ง/หนังสือที่อ้างอิง */
  @IsOptional() @IsString() documentNo?: string;
}

@Injectable()
export class StudentProfileService {
  /*
   * ─── อ่านกุญแจจาก env ตรง ๆ ───
   * ต้องรู้ตั้งแต่จังหวะสร้างออบเจ็กต์ว่ามีกุญแจหรือไม่ เพื่อให้สภาพ
   * "ยังไม่ได้ตั้งกุญแจ" ตอบผู้ใช้ได้ตรง ๆ ที่จุดบันทึก
   */
  private readonly nationalIdKey = process.env.NATIONAL_ID_KEY ?? '';
  private readonly hashSecret = process.env.IP_HASH_SECRET ?? 'vec-sms';

  constructor(private readonly db: DbService) {}

  /**
   * เลขประจำตัวประชาชนฉบับเต็ม — เส้นทางแยกที่บันทึกทุกครั้งที่มีคนเปิดดู
   *
   * ─── ทำไมไม่ส่งมากับระเบียนตามปกติ ───
   * ระเบียนนักศึกษาถูกเปิดดูวันละหลายสิบครั้งเพื่อดูเรื่องอื่น ถ้าเลขบัตร
   * ติดไปด้วยทุกครั้ง `access_log` จะบอกไม่ได้เลยว่าใคร**ตั้งใจ**ดูเลขบัตร
   * ของใคร — ซึ่งเป็นสิ่งเดียวที่หลักฐาน 90 วันตาม PDPA ม.37 ต้องตอบให้ได้
   *
   * และหน้าจอส่วนใหญ่ไม่ต้องใช้ตัวเลข ต้องการแค่รู้ว่า "กรอกแล้วหรือยัง"
   * ซึ่ง `has_national_id` ตอบได้อยู่แล้วโดยไม่เปิดเผยอะไร
   */
  async readNationalId(studentId: string) {
    const row = await this.db.queryOne<{ enc: Buffer | null }>(
      `select p.national_id_enc as enc
         from student s join person p on p.id = s.person_id
        where s.id = $1`,
      [studentId],
    );
    if (!row) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์เข้าถึง');
    if (!row.enc) return { nationalId: null, reason: 'ยังไม่ได้กรอกเลขประจำตัวประชาชน' };

    const plain = decryptNationalId(Buffer.from(row.enc), decryptionKeys(process.env));
    if (plain === null) {
      /*
       * ถอดไม่ได้แปลว่ากุญแจที่ใช้เข้ารหัสแถวนี้ไม่อยู่ในเครื่องแล้ว
       * บอกตรง ๆ ดีกว่าตอบว่า "ยังไม่ได้กรอก" ซึ่งจะทำให้เจ้าหน้าที่ไป
       * กรอกทับ แล้วค่าเดิมหายไปโดยไม่มีใครรู้ว่าเคยมี
       */
      return {
        nationalId: null,
        reason: 'ถอดรหัสไม่ได้ — กุญแจที่ใช้เข้ารหัสแถวนี้ไม่อยู่ในระบบแล้ว',
      };
    }
    return { nationalId: plain, formatted: formatNationalId(plain) };
  }

  /**
   * ระเบียนฉบับเต็มในคำขอเดียว
   *
   * รวมหกคำสั่งไว้ในทรานแซกชันเดียวแทนที่จะให้หน้าจอยิงหกครั้ง เพราะ
   * ต้นทุนของคำสั่งในสคีมานี้อยู่ที่**การวางแผน** ไม่ใช่การอ่านข้อมูล
   * (นโยบาย RLS ถูกกางออกทุกครั้ง) หกคำขอ = หกรอบ HTTP + หกชุดแผน
   */
  async full(studentId: string) {
    return this.db.tx(async (c) => {
      const head = (
        await c.query(
          `select s.id, s.student_code, s.status, s.admitted_year_be,
                  s.siblings_count, s.birth_order, s.siblings_studying,
                  s.parents_marital, s.class_number, s.travel_mode, s.talent_th,
                  p.id as person_id, p.prefix_th, p.first_name_th, p.last_name_th,
                  p.prefix_en, p.first_name_en, p.last_name_en,
                  p.nickname_th, p.nickname_en, p.nationality,
                  p.birth_date, p.gender, p.phone, p.email,
                  p.line_id, p.facebook, p.birth_place_th
             from student s
             join person p on p.id = s.person_id
            where s.id = $1`,
          [studentId],
        )
      ).rows[0];

      if (!head) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์เข้าถึง');

      // ศูนย์แถวที่นี่แปลว่า "ไม่มีสิทธิ์" หรือ "ยังไม่ได้กรอก" ซึ่งแยกกัน
      // ไม่ได้จากฝั่งนี้ — หน้าจอถามสิทธิ์แยกด้วย canSeeSensitive
      const sensitive = (
        await c.query(
          `select ethnicity, religion, blood_type, drug_allergy, chronic_disease,
                  weight_kg, height_cm, distinguishing, disability, disability_note,
                  note, updated_at
             from person_sensitive where person_id = $1`,
          [head.person_id],
        )
      ).rows[0];

      const canSeeSensitive = (
        await c.query<{ ok: boolean }>(
          `select may_see_sensitive($1) as ok`, [head.person_id],
        )
      ).rows[0].ok;

      const addresses = (
        await c.query(
          `select id, kind, address_line, subdistrict_th, district_th,
                  province_th, postal_code
             from person_address where person_id = $1 order by kind`,
          [head.person_id],
        )
      ).rows;

      const parents = (
        await c.query(
          `select id, role, prefix_th, first_name_th, last_name_th, birth_date,
                  occupation_th, income_monthly, status, phone, work_phone, email,
                  address_line, subdistrict_th, district_th, province_th, postal_code,
                  national_id_hash is not null as has_national_id
             from student_parent where student_id = $1 order by role`,
          [studentId],
        )
      ).rows;

      const priorEducation = (
        await c.query(
          `select id, level_th, completed_year_be, gpax, program_th, program_type_th,
                  school_th, province_th, verified_at, note
             from student_prior_education where student_id = $1
            order by completed_year_be nulls last, level_th`,
          [studentId],
        )
      ).rows;

      const advisors = (
        await c.query(
          `select sa.id, sa.staff_id, sa.is_primary, sa.assigned_on, sa.ended_on, sa.note,
                  p.first_name_th || ' ' || p.last_name_th as advisor_name,
                  ay.year_be
             from student_advisor sa
             join staff st on st.id = sa.staff_id
             join person p on p.id = st.person_id
             left join academic_year ay on ay.id = sa.academic_year_id
            where sa.student_id = $1
            order by sa.ended_on nulls first, sa.assigned_on desc`,
          [studentId],
        )
      ).rows;

      // ผู้ปกครองที่เข้าระบบได้ (คนละเรื่องกับบิดามารดาใน student_parent)
      const guardians = (
        await c.query(
          `select sg.id, sg.relation, sg.is_primary, sg.verified_at,
                  sg.can_view_grades, sg.can_view_finance, sg.can_approve_leave,
                  p.first_name_th || ' ' || p.last_name_th as guardian_name,
                  p.phone
             from student_guardian sg
             join person p on p.id = sg.person_id
            where sg.student_id = $1
            order by sg.is_primary desc`,
          [studentId],
        )
      ).rows;

      return {
        ...head,
        sensitive: sensitive ?? null,
        canSeeSensitive,
        addresses,
        parents,
        priorEducation,
        advisors,
        guardians,
      };
    });
  }

  /**
   * แก้ข้อมูลทั่วไป — แตะสองตาราง จึงต้องอยู่ในทรานแซกชันเดียว
   *
   * `coalesce($n, col)` ทำให้ช่องที่ไม่ได้ส่งมาไม่ถูกล้าง ซึ่งจำเป็นเพราะ
   * หน้าจอส่งเฉพาะแท็บที่กำลังแก้ ไม่ได้ส่งทั้งระเบียน
   */
  async updateProfile(studentId: string, dto: UpdateProfileDto) {
    return this.db.tx(async (c) => {
      const row = (
        await c.query<{ person_id: string }>(
          `select person_id from student where id = $1`, [studentId],
        )
      ).rows[0];
      if (!row) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์เข้าถึง');

      /*
       * ─── เลขบัตรเข้ารหัสที่ชั้นนี้ ไม่ใช่ในฐานข้อมูล ───
       * กุญแจต้องอยู่นอกฐานข้อมูล มิฉะนั้นจะรั่วไปพร้อมกับ dump แล้ว
       * การเข้ารหัสกลายเป็นของประดับ (ข้อยกเว้นของหลักข้อ 1 ที่ตั้งใจ)
       *
       * ถ้ายังไม่ได้ตั้งกุญแจ **ปฏิเสธไปตรง ๆ** ไม่ใช่เก็บแต่ค่าแฮชแล้ว
       * ตอบว่าสำเร็จ — เพราะเจ้าหน้าที่จะเข้าใจว่ากรอกครบแล้ว แล้วไปเจอ
       * ตอนพิมพ์ใบ รบ. ว่าช่องเลขบัตรว่างทุกใบ โดยไม่มีอะไรบอกว่าเพราะอะไร
       * (หลักเดียวกับ RESET_DELIVERY ที่ค่าเริ่มต้นคือปิด ไม่ใช่ทำเป็นส่งแล้วเงียบ)
       */
      const nid = dto.nationalId === undefined ? null : normalizeNationalId(dto.nationalId);
      if (nid !== null) {
        if (!isValidThaiNationalId(nid)) {
          throw new BadRequestException('เลขประจำตัวประชาชนไม่ถูกต้องตามหลักตรวจสอบ');
        }
        if (!this.nationalIdKey) {
          throw new BadRequestException(
            'ระบบยังไม่ได้ตั้งกุญแจเข้ารหัสเลขประจำตัวประชาชน (NATIONAL_ID_KEY) ' +
              'จึงเก็บเลขบัตรไม่ได้ — ใบ รบ. ที่ออกไปจะไม่มีเลขบัตรบนกระดาษ',
          );
        }
      }

      await c.query(
        `update person set
           national_id_enc    = coalesce($11, national_id_enc),
           national_id_hash   = coalesce($12, national_id_hash),
           national_id_hash_v = case when $11::bytea is null then national_id_hash_v else 2 end,
           prefix_en      = coalesce($2, prefix_en),
           nickname_th    = coalesce($3, nickname_th),
           nickname_en    = coalesce($4, nickname_en),
           nationality    = coalesce($5, nationality),
           line_id        = coalesce($6, line_id),
           facebook       = coalesce($7, facebook),
           birth_place_th = coalesce($8, birth_place_th),
           phone          = coalesce($9, phone),
           email          = coalesce($10, email)
         where id = $1`,
        [row.person_id, dto.prefixEn ?? null, dto.nicknameTh ?? null,
         dto.nicknameEn ?? null, dto.nationality ?? null, dto.lineId ?? null,
         dto.facebook ?? null, dto.birthPlaceTh ?? null, dto.phone ?? null,
         dto.email ?? null,
         nid === null ? null : encryptNationalId(nid, this.nationalIdKey as string),
         nid === null ? null : hashNationalId(nid, this.hashSecret)],
      );

      await c.query(
        `update student set
           siblings_count    = coalesce($2, siblings_count),
           birth_order       = coalesce($3, birth_order),
           siblings_studying = coalesce($4, siblings_studying),
           parents_marital   = coalesce($5::marital_status_kind, parents_marital),
           class_number      = coalesce($6, class_number),
           travel_mode       = coalesce($7::travel_mode_kind, travel_mode),
           talent_th         = coalesce($8, talent_th)
         where id = $1`,
        [studentId, dto.siblingsCount ?? null, dto.birthOrder ?? null,
         dto.siblingsStudying ?? null, dto.parentsMarital ?? null,
         dto.classNumber ?? null, dto.travelMode ?? null, dto.talentTh ?? null],
      );

      return { ok: true };
    });
  }

  async saveSensitive(studentId: string, dto: SensitiveDto) {
    return this.db.tx(async (c) => {
      const row = (
        await c.query<{ person_id: string }>(
          `select person_id from student where id = $1`, [studentId],
        )
      ).rows[0];
      if (!row) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์เข้าถึง');

      await c.query(
        `insert into person_sensitive
           (person_id, institution_id, ethnicity, religion, blood_type,
            drug_allergy, chronic_disease, weight_kg, height_cm, distinguishing,
            disability, disability_note, note)
         values ($1, current_institution_id(), $2, $3, $4, $5, $6, $7, $8, $9,
                 $10::disability_kind, $11, $12)
         on conflict (person_id) do update set
           ethnicity       = coalesce(excluded.ethnicity,       person_sensitive.ethnicity),
           religion        = coalesce(excluded.religion,        person_sensitive.religion),
           blood_type      = coalesce(excluded.blood_type,      person_sensitive.blood_type),
           drug_allergy    = coalesce(excluded.drug_allergy,    person_sensitive.drug_allergy),
           chronic_disease = coalesce(excluded.chronic_disease, person_sensitive.chronic_disease),
           weight_kg       = coalesce(excluded.weight_kg,       person_sensitive.weight_kg),
           height_cm       = coalesce(excluded.height_cm,       person_sensitive.height_cm),
           distinguishing  = coalesce(excluded.distinguishing,  person_sensitive.distinguishing),
           disability      = coalesce(excluded.disability,      person_sensitive.disability),
           disability_note = coalesce(excluded.disability_note, person_sensitive.disability_note),
           note            = coalesce(excluded.note,            person_sensitive.note),
           updated_at      = now()`,
        [row.person_id, dto.ethnicity ?? null, dto.religion ?? null,
         dto.bloodType ?? null, dto.drugAllergy ?? null, dto.chronicDisease ?? null,
         dto.weightKg ?? null, dto.heightCm ?? null, dto.distinguishing ?? null,
         dto.disability ?? null, dto.disabilityNote ?? null, dto.note ?? null],
      );

      return { ok: true };
    });
  }

  async saveAddress(studentId: string, dto: AddressDto) {
    return this.db.tx(async (c) => {
      const row = (
        await c.query<{ person_id: string }>(
          `select person_id from student where id = $1`, [studentId],
        )
      ).rows[0];
      if (!row) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์เข้าถึง');

      const saved = (
        await c.query(
          `insert into person_address
             (institution_id, person_id, kind, address_line, subdistrict_th,
              district_th, province_th, postal_code)
           values (current_institution_id(), $1, $2::address_kind, $3, $4, $5, $6, $7)
           on conflict (person_id, kind) do update set
             address_line   = excluded.address_line,
             subdistrict_th = excluded.subdistrict_th,
             district_th    = excluded.district_th,
             province_th    = excluded.province_th,
             postal_code    = excluded.postal_code,
             updated_at     = now()
           returning id`,
          [row.person_id, dto.kind, dto.addressLine, dto.subdistrictTh ?? null,
           dto.districtTh ?? null, dto.provinceTh ?? null, dto.postalCode ?? null],
        )
      ).rows[0];

      return saved;
    });
  }

  async deleteAddress(addressId: string) {
    const done = await this.db.query(
      `delete from person_address where id = $1 returning id`, [addressId],
    );
    if (done.length === 0) throw new NotFoundException('ไม่พบที่อยู่ หรือไม่มีสิทธิ์ลบ');
    return { ok: true };
  }

  async saveParent(studentId: string, dto: ParentDto) {
    const saved = await this.db.query(
      `insert into student_parent
         (institution_id, student_id, role, prefix_th, first_name_th, last_name_th,
          national_id_hash, birth_date, occupation_th, income_monthly, status,
          phone, work_phone, email, address_line, subdistrict_th, district_th,
          province_th, postal_code)
       values (current_institution_id(), $1, $2::parent_role, $3, $4, $5,
               case when $6::text is not null then digest($6::text, 'sha256') end,
               $7, $8, $9, coalesce($10, 'alive')::parent_status,
               $11, $12, $13, $14, $15, $16, $17, $18)
       on conflict (student_id, role) do update set
         prefix_th        = excluded.prefix_th,
         first_name_th    = excluded.first_name_th,
         last_name_th     = excluded.last_name_th,
         -- ไม่ล้างค่าแฮชเดิมเมื่อฟอร์มไม่ได้ส่งเลขบัตรมา — อ่านกลับไม่ได้
         -- อยู่แล้ว หน้าจอจึงส่งกลับมาไม่ได้แม้จะแก้ช่องอื่น
         national_id_hash = coalesce(excluded.national_id_hash, student_parent.national_id_hash),
         birth_date       = excluded.birth_date,
         occupation_th    = excluded.occupation_th,
         income_monthly   = excluded.income_monthly,
         status           = excluded.status,
         phone            = excluded.phone,
         work_phone       = excluded.work_phone,
         email            = excluded.email,
         address_line     = excluded.address_line,
         subdistrict_th   = excluded.subdistrict_th,
         district_th      = excluded.district_th,
         province_th      = excluded.province_th,
         postal_code      = excluded.postal_code,
         updated_at       = now()
       returning id`,
      [studentId, dto.role, dto.prefixTh ?? null, dto.firstNameTh,
       dto.lastNameTh ?? null, dto.nationalId ?? null, dto.birthDate ?? null,
       dto.occupationTh ?? null, dto.incomeMonthly ?? null, dto.status ?? null,
       dto.phone ?? null, dto.workPhone ?? null, dto.email ?? null,
       dto.addressLine ?? null, dto.subdistrictTh ?? null, dto.districtTh ?? null,
       dto.provinceTh ?? null, dto.postalCode ?? null],
    );
    if (saved.length === 0) {
      throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์บันทึก');
    }
    return saved[0];
  }

  async deleteParent(parentId: string) {
    const done = await this.db.query(
      `delete from student_parent where id = $1 returning id`, [parentId],
    );
    if (done.length === 0) throw new NotFoundException('ไม่พบข้อมูล หรือไม่มีสิทธิ์ลบ');
    return { ok: true };
  }

  async savePriorEducation(studentId: string, dto: PriorEducationDto) {
    const saved = await this.db.query(
      `insert into student_prior_education
         (institution_id, student_id, level_th, completed_year_be, gpax,
          program_th, program_type_th, school_th, province_th, note)
       values (current_institution_id(), $1, $2, $3, $4, $5, $6, $7, $8, $9)
       on conflict (student_id, level_th) do update set
         completed_year_be = excluded.completed_year_be,
         gpax              = excluded.gpax,
         program_th        = excluded.program_th,
         program_type_th   = excluded.program_type_th,
         school_th         = excluded.school_th,
         province_th       = excluded.province_th,
         note              = excluded.note
       returning id`,
      [studentId, dto.levelTh, dto.completedYearBe ?? null, dto.gpax ?? null,
       dto.programTh ?? null, dto.programTypeTh ?? null, dto.schoolTh ?? null,
       dto.provinceTh ?? null, dto.note ?? null],
    );
    if (saved.length === 0) {
      throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์บันทึก');
    }
    return saved[0];
  }

  /**
   * ตรวจวุฒิแล้ว — บันทึกว่าใครตรวจและเมื่อไร
   *
   * แยกจากการแก้ข้อมูลเพราะเป็นการ**รับรอง** ไม่ใช่การกรอก คนที่กรอก
   * ประวัติเข้าระบบกับคนที่ยืนยันว่าตรงกับใบจริงเป็นคนละหน้าที่
   */
  async verifyPriorEducation(rowId: string) {
    const done = await this.db.query(
      `update student_prior_education
          set verified_at = now(), verified_by = current_actor_id()
        where id = $1 returning id, verified_at`,
      [rowId],
    );
    if (done.length === 0) throw new NotFoundException('ไม่พบข้อมูล หรือไม่มีสิทธิ์แก้ไข');
    return done[0];
  }

  async deletePriorEducation(rowId: string) {
    const done = await this.db.query(
      `delete from student_prior_education where id = $1 returning id`, [rowId],
    );
    if (done.length === 0) throw new NotFoundException('ไม่พบข้อมูล หรือไม่มีสิทธิ์ลบ');
    return { ok: true };
  }

  /**
   * มอบหมายที่ปรึกษา
   *
   * ─── ทำไมต้องปิดของเดิมก่อน ไม่ใช่ปล่อยให้ชนดัชนี ───
   * `student_advisor_primary` เป็น unique บางส่วนของ (student, ปีการศึกษา)
   * ที่ยังไม่สิ้นสุด การเปลี่ยนที่ปรึกษาจึงต้องปิดของเดิมด้วย `ended_on`
   * ไม่ใช่ลบทิ้ง เพราะต้องรู้ย้อนหลังว่าใครดูแลอยู่ตอนเกิดเรื่อง
   */
  async assignAdvisor(studentId: string, dto: AssignAdvisorDto) {
    return this.db.tx(async (c) => {
      const primary = dto.isPrimary !== false;

      if (primary) {
        await c.query(
          `update student_advisor set ended_on = current_date
            where student_id = $1 and is_primary and ended_on is null
              and academic_year_id is not distinct from $2::uuid`,
          [studentId, dto.academicYearId ?? null],
        );
      }

      const saved = (
        await c.query(
          `insert into student_advisor
             (institution_id, student_id, staff_id, academic_year_id, is_primary, note)
           values (current_institution_id(), $1, $2, $3, $4, $5)
           returning id`,
          [studentId, dto.staffId, dto.academicYearId ?? null, primary, dto.note ?? null],
        )
      ).rows[0];

      return saved;
    });
  }

  /**
   * มอบหมายที่ปรึกษาทั้งห้องพร้อมกัน
   *
   * ─── ทำไมคืนผลรายคนแทนที่จะ raise ───
   * หลักเดียวกับ `register_courses_bulk` — คนหนึ่งล้ม (เช่นมีที่ปรึกษาอยู่แล้ว
   * ในปีเดียวกัน) ต้องไม่ทำให้ทั้งห้องมอบหมายไม่ได้
   */
  async assignAdvisorBulk(dto: AssignAdvisorDto & { studentIds: string[] }) {
    const results: { studentId: string; ok: boolean; message?: string }[] = [];
    for (const sid of dto.studentIds) {
      try {
        await this.assignAdvisor(sid, dto);
        results.push({ studentId: sid, ok: true });
      } catch (e) {
        results.push({ studentId: sid, ok: false, message: (e as Error).message });
      }
    }
    return { total: dto.studentIds.length, ok: results.filter((r) => r.ok).length, results };
  }

  async endAdvisor(rowId: string) {
    const done = await this.db.query(
      `update student_advisor set ended_on = current_date
        where id = $1 and ended_on is null returning id, ended_on`,
      [rowId],
    );
    if (done.length === 0) {
      throw new NotFoundException('ไม่พบรายการ หรือสิ้นสุดไปแล้ว หรือไม่มีสิทธิ์แก้ไข');
    }
    return done[0];
  }

  /**
   * เปลี่ยนสถานะนักศึกษา — trigger `student_status_guard()` เขียนประวัติให้เอง
   *
   * ตั้งสี่ช่องพร้อมกันใน `update` คำสั่งเดียว เพราะ trigger อ่านทั้งสี่ค่า
   * จากแถวใหม่ ถ้าแยกเป็นสองคำสั่ง (เปลี่ยนสถานะก่อน แล้วค่อยเติมเหตุผล)
   * ประวัติแถวที่ trigger เพิ่งเขียนจะได้เหตุผลเป็น null ตลอดไป
   */
  async changeStatus(studentId: string, dto: StatusChangeDto) {
    /*
     * ─── บังคับเหตุผลเฉพาะสถานะที่แปลว่าออกจากสถานศึกษา ───
     * เพราะสี่สถานะนี้คือชุดที่ใบ รบ. พิมพ์ในช่อง "เหตุที่ออก" (0062)
     * ส่วนการกลับมาเรียนต่อหรือลาพักไม่ต้องมีเหตุผลบนเอกสารทางการ
     * — บังคับทุกสถานะจะกลายเป็นการขอข้อมูลที่ไม่มีใครใช้ แล้วคนกรอกจะ
     * ใส่จุดเดียวไปให้พ้น ๆ ซึ่งแย่กว่าไม่ถาม
     */
    const leaving = ['withdrawn', 'transferred_out', 'dismissed', 'graduated'];
    if (leaving.includes(dto.status) && !(dto.reason ?? '').trim()) {
      throw new BadRequestException(
        'ต้องระบุเหตุผล เพราะสถานะนี้จะถูกพิมพ์ในช่อง "เหตุที่ออก" บนใบ ระเบียนแสดงผลการเรียน',
      );
    }
    const row = await this.db.queryOne(
      `update student
          set status             = $2::student_status,
              status_since       = $3::date,
              status_reason      = $4,
              status_document_no = $5
        where id = $1
      returning id, status, status_since, status_reason, status_document_no`,
      [studentId, dto.status, dto.effectiveOn, dto.reason ?? null, dto.documentNo ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบนักศึกษา หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async statusHistory(studentId: string) {
    return this.db.query(
      `select h.to_status, h.from_status, h.effective_on, h.reason,
              h.document_no, h.recorded_at
         from student_status_history h
        where h.student_id = $1
        order by h.effective_on desc, h.recorded_at desc`,
      [studentId],
    );
  }

  /**
   * รายชื่อเด็กในที่ปรึกษาของผู้ใช้ปัจจุบัน
   *
   * ไม่รับ staffId เป็นพารามิเตอร์โดยตั้งใจ — ถ้ารับ ครูคนหนึ่งจะขอรายชื่อ
   * ของครูอีกคนได้ ซึ่ง RLS ยอมให้ผ่าน (บทบาทระดับวิทยาลัยเห็นทั้งหมด
   * แต่ครูเห็นเฉพาะของตัวเอง — ครูจะได้ศูนย์แถวโดยไม่มีอะไรอธิบาย)
   * งานทะเบียนที่ต้องดูของครูคนอื่นใช้หน้าจอมอบหมาย ไม่ใช่หน้านี้
   */
  async myAdvisees() {
    return this.db.query(
      `select s.id, s.student_code, s.class_number,
              p.first_name_th || ' ' || p.last_name_th as full_name,
              s.status, sa.assigned_on,
              ay.year_be
         from student_advisor sa
         join student s on s.id = sa.student_id
         join person  p on p.id = s.person_id
         join staff  st on st.id = sa.staff_id
         left join academic_year ay on ay.id = sa.academic_year_id
        where st.person_id = current_actor_id() and sa.ended_on is null
        order by s.student_code`,
    );
  }

  /** รายชื่อที่ปรึกษาทั้งวิทยาลัยพร้อมจำนวนเด็กที่ดูแล — หน้าจอของงานทะเบียน */
  async advisorLoad() {
    return this.db.query(
      `select st.id as staff_id,
              p.first_name_th || ' ' || p.last_name_th as advisor_name,
              count(*) filter (where sa.ended_on is null) as advisees
         from student_advisor sa
         join staff  st on st.id = sa.staff_id
         join person p  on p.id  = st.person_id
        group by st.id, p.first_name_th, p.last_name_th
        having count(*) filter (where sa.ended_on is null) > 0
        order by advisees desc`,
    );
  }
}

@Controller('students')
class StudentProfileController {
  constructor(private readonly svc: StudentProfileService) {}

  /**
   * ต้องประกาศก่อน `:id/...` ทุกเส้นทาง มิฉะนั้น Nest จะจับ 'advisees'
   * เป็นค่า `:id` แล้ว ParseUuidPipe จะปฏิเสธด้วย 400 ที่อธิบายอะไรไม่ได้เลย
   */
  @Get('advisees')
  myAdvisees() {
    return this.svc.myAdvisees();
  }

  @Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
  @Get('advisor-load')
  advisorLoad() {
    return this.svc.advisorLoad();
  }

  @Get(':id/profile')
  full(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.full(id);
  }

  /**
   * เลขประจำตัวประชาชนฉบับเต็ม
   *
   * บทบาทเดียวกับที่แก้ระเบียนได้ — ครูที่ปรึกษาไม่ต้องใช้เลขนี้เพื่อดูแล
   * นักศึกษา และ `@Audit` ทำให้ทุกครั้งที่มีคนเปิดดูมีชื่อคนเปิดอยู่ใน
   * access_log พร้อมว่าเป็นของนักศึกษาคนไหน
   */
  @Roles('registrar', 'director', 'admin')
  @Audit('student', 'id')
  @Get(':id/national-id')
  nationalId(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.readNationalId(id);
  }

  @Roles('registrar', 'student_affairs', 'admin')
  @Audit('student', 'id')
  @Patch(':id/profile')
  updateProfile(@Param('id', ParseUuidPipe) id: string, @Body() dto: UpdateProfileDto) {
    return this.svc.updateProfile(id, dto);
  }

  @Roles('registrar', 'student_affairs', 'admin')
  @Audit('person_sensitive', 'id')
  @Post(':id/sensitive')
  saveSensitive(@Param('id', ParseUuidPipe) id: string, @Body() dto: SensitiveDto) {
    return this.svc.saveSensitive(id, dto);
  }

  @Roles('registrar', 'student_affairs', 'admin')
  @Audit('person_address', 'id')
  @Post(':id/addresses')
  saveAddress(@Param('id', ParseUuidPipe) id: string, @Body() dto: AddressDto) {
    return this.svc.saveAddress(id, dto);
  }

  @Roles('registrar', 'student_affairs', 'admin')
  @Audit('person_address', 'addressId')
  @Delete(':id/addresses/:addressId')
  deleteAddress(@Param('addressId', ParseUuidPipe) addressId: string) {
    return this.svc.deleteAddress(addressId);
  }

  @Roles('registrar', 'student_affairs', 'admin')
  @Audit('student_parent', 'id')
  @Post(':id/parents')
  saveParent(@Param('id', ParseUuidPipe) id: string, @Body() dto: ParentDto) {
    return this.svc.saveParent(id, dto);
  }

  @Roles('registrar', 'student_affairs', 'admin')
  @Audit('student_parent', 'parentId')
  @Delete(':id/parents/:parentId')
  deleteParent(@Param('parentId', ParseUuidPipe) parentId: string) {
    return this.svc.deleteParent(parentId);
  }

  @Roles('registrar', 'academic', 'admin')
  @Audit('student_prior_education', 'id')
  @Post(':id/prior-education')
  savePriorEducation(@Param('id', ParseUuidPipe) id: string, @Body() dto: PriorEducationDto) {
    return this.svc.savePriorEducation(id, dto);
  }

  @Roles('registrar', 'academic', 'admin')
  @Audit('student_prior_education', 'rowId')
  @Post(':id/prior-education/:rowId/verify')
  verifyPriorEducation(@Param('rowId', ParseUuidPipe) rowId: string) {
    return this.svc.verifyPriorEducation(rowId);
  }

  @Roles('registrar', 'academic', 'admin')
  @Audit('student_prior_education', 'rowId')
  @Delete(':id/prior-education/:rowId')
  deletePriorEducation(@Param('rowId', ParseUuidPipe) rowId: string) {
    return this.svc.deletePriorEducation(rowId);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('student_advisor', 'id')
  @Post(':id/advisors')
  assignAdvisor(@Param('id', ParseUuidPipe) id: string, @Body() dto: AssignAdvisorDto) {
    return this.svc.assignAdvisor(id, dto);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('student_advisor', 'rowId')
  @Delete(':id/advisors/:rowId')
  endAdvisor(@Param('rowId', ParseUuidPipe) rowId: string) {
    return this.svc.endAdvisor(rowId);
  }

  /**
   * เปลี่ยนสถานะนักศึกษาพร้อม**วันที่และเหตุผล**
   *
   * ─── ทำไมต้องเป็นเส้นทางของตัวเอง ไม่ใช่ช่องหนึ่งใน PATCH /profile ───
   * เพราะการเปลี่ยนสถานะเขียนประวัติที่ลบไม่ได้ (`student_status_history`)
   * และเป็นข้อมูลที่ใช้ยันจำนวนนักศึกษาตอนขอเงินอุดหนุน — ต่างจากการแก้
   * ชื่อเล่นหรือเบอร์โทรที่แก้กี่ครั้งก็ได้ การรวมไว้ในเส้นทางเดียวกัน
   * แปลว่าคนที่กดแก้ที่อยู่จะเปลี่ยนสถานะพลาดได้ด้วยฟิลด์ที่หลงมา
   *
   * และช่อง "เหตุที่ออก" บนใบ รบ. อ่านจากประวัตินี้ (0062) — ก่อนหน้านี้
   * ไม่มีที่ให้กรอกเลย คอลัมน์ `reason` จึงเป็น null ทุกแถวตั้งแต่ 0002
   */
  @Roles('registrar', 'academic', 'director', 'admin')
  @Audit('student', 'id')
  @Post(':id/status')
  changeStatus(@Param('id', ParseUuidPipe) id: string, @Body() dto: StatusChangeDto) {
    return this.svc.changeStatus(id, dto);
  }

  /**
   * ประวัติการเปลี่ยนสถานะ — ลบไม่ได้ จึงใช้ยันย้อนหลังได้
   *
   * มีเส้นทางอ่านเพราะช่อง "เหตุที่ออก" บนใบ รบ. มาจากที่นี่ ถ้าเจ้าหน้าที่
   * เห็นค่าบนใบแล้วสงสัย ต้องตามกลับมาดูได้ว่าใครกรอกไว้เมื่อไร มิฉะนั้น
   * ค่าที่พิมพ์ลงกระดาษจะไม่มีที่มาให้ตรวจ
   */
  @Roles('registrar', 'academic', 'student_affairs', 'director', 'admin')
  @Get(':id/status-history')
  statusHistory(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.statusHistory(id);
  }
}

/**
 * มอบหมายที่ปรึกษาเป็นกลุ่ม — แยก controller เพราะไม่ได้ผูกกับนักศึกษาคนเดียว
 * เส้นทางใต้ `/students/:id/` จะบังคับให้ต้องมี id ที่ไม่มีความหมายกับงานนี้
 */
@Roles('registrar', 'academic', 'director', 'admin')
@Controller('advisors')
class AdvisorsController {
  constructor(private readonly svc: StudentProfileService) {}

  @Audit('student_advisor')
  @Post('bulk')
  bulk(@Body() dto: AssignAdvisorDto & { studentIds: string[] }) {
    if (!Array.isArray(dto.studentIds) || dto.studentIds.length === 0) {
      throw new BadRequestException('ต้องระบุ studentIds อย่างน้อยหนึ่งคน');
    }
    if (dto.studentIds.length > 200) {
      throw new BadRequestException('มอบหมายได้ครั้งละไม่เกิน 200 คน');
    }
    return this.svc.assignAdvisorBulk(dto);
  }
}

export const PROFILE_CONTROLLERS = [StudentProfileController, AdvisorsController];

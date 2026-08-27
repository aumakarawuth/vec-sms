import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  Injectable,
  Module,
  Param,
  Post,
  Query,
  UnprocessableEntityException,
} from '@nestjs/common';
import {
  ArrayNotEmpty,
  IsArray,
  IsIn,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import {
  encryptNationalId,
  hashNationalId,
  isValidThaiNationalId,
  normalizeNationalId,
} from '../../common/crypto/national-id';
import { DbService } from '../../common/db/db.service';
import { IsUuid, IsUuidArray, ParseUuidPipe } from '../../common/validation/uuid';

/**
 * นำเข้าข้อมูลจากระบบเดิม
 *
 * ─── ทำไมต้องมีสองขั้น ───
 * ขั้นที่ 1 สร้างรอบนำเข้าและตรวจทุกแถว คืนรายการปัญหาทั้งหมดโดยไม่เขียนอะไร
 * ขั้นที่ 2 นำเข้าจริงเมื่อไม่เหลือปัญหาแล้ว
 *
 * การนำเข้าที่ล้มเหลวกลางคันแล้วเหลือข้อมูลครึ่ง ๆ กลาง ๆ แก้ยากกว่าไม่นำเข้าเลย
 * เพราะเจ้าหน้าที่ไม่รู้ว่าแถวไหนเข้าไปแล้วบ้าง และนักศึกษาที่เข้าไปครึ่งเดียว
 * จะไปโผล่ในรายงานทันทีทั้งที่ข้อมูลยังไม่ครบ
 *
 * ─── ทำไมรับ JSON ไม่ใช่ไฟล์ CSV ───
 * การแปลง CSV ให้ถูกต้องกับภาษาไทยมีกับดักเยอะมาก — encoding (TIS-620
 * ที่ Excel ไทยยังใช้อยู่) ตัวคั่น การขึ้นบรรทัดใหม่ในเซลล์ และ BOM
 * ให้ฝั่งหน้าจอที่รู้บริบทของไฟล์แปลงเป็น JSON แล้วส่งมา ตรวจง่ายกว่ามาก
 * และข้อความผิดพลาดชี้ไปที่แถวได้ตรงกว่าการเดาจากตำแหน่งไบต์
 */

class ImportRowDto {
  @IsNumber() @Min(1) rowNo: number;
  @IsObject() payload: Record<string, unknown>;
}

class CreateImportDto {
  @IsIn(['student', 'academic_history', 'staff', 'grade']) kind: string;
  @IsOptional() @IsString() sourceName?: string;
  @IsArray() @ArrayNotEmpty() @ValidateNested({ each: true }) @Type(() => ImportRowDto)
  rows: ImportRowDto[];
}

class PriorRecordDto {
  @IsUuid() studentId: string;
  @IsString() sourceTh: string;
  @IsString() courseCode: string;
  @IsString() courseNameTh: string;
  @IsNumber() @Min(0.5) credits: number;
  @IsString() gradeSymbol: string;
  @IsOptional() @IsString() termLabel?: string;
  @IsOptional() @IsNumber() gradePoint?: number;
  @IsOptional() @IsUuid() mappedCourseId?: string;
  @IsOptional() @IsString() note?: string;

  /**
   * โอนผลการเรียน (*1) หรือเทียบโอนความรู้และประสบการณ์ (*2)
   *
   * เป็นตัวกำหนดเครื่องหมายที่พิมพ์ท้ายชื่อวิชาบนใบ รบ. — ถ้าไม่ส่งมา
   * ฐานข้อมูลตั้งเป็น `transferred_experience` ซึ่งเป็นกรณีที่พบบ่อยกว่า
   * และเป็นค่าที่ "ปลอดภัยกว่า" เพราะไม่ได้อ้างว่ามีเกรดเดิมรองรับ
   */
  @IsOptional() @IsIn(['transferred_grade', 'transferred_experience'])
  transferKind?: string;
}

class ApproveTransferDto {
  @IsArray() @ArrayNotEmpty() @IsUuidArray() recordIds: string[];
}

@Injectable()
export class ImportService {
  /* ─── กุญแจอยู่นอกฐานข้อมูล — หลักเดียวกับ students/profile.ts ─── */
  private readonly nationalIdKey = process.env.NATIONAL_ID_KEY ?? '';
  private readonly hashSecret = process.env.IP_HASH_SECRET ?? 'vec-sms';

  constructor(private readonly db: DbService) {}

  /**
   * เข้ารหัส/แฮชเลขประจำตัวประชาชนทุกช่องในแถวก่อนส่งเข้า
   * `apply_student_import()` — ฟังก์ชันในฐานข้อมูลไม่มีกุญแจและไม่ควรมี
   * (ดูคอมเมนต์บนสุดของ 0087) จึงต้องทำที่ชั้นนี้ หลักเดียวกับ
   * `students/profile.ts` ที่แก้ระเบียนทีละคน — ต่างกันแค่ทำเป็นชุด
   *
   * ─── ทำไมนักศึกษาเข้ารหัสด้วย แต่บิดามารดา/ผู้ปกครองแฮชอย่างเดียว ───
   * ใบ รบ. พิมพ์เลขบัตรของ**นักศึกษา**เท่านั้น จึงมีแค่ช่องนี้ที่ต้อง
   * ถอดรหัสกลับมาได้ ส่วนอีกสามช่องใช้แค่ค้นหา/กันซ้ำ ไม่มีอะไรต้องพิมพ์
   *
   * ─── ทำไมไม่ `throw` เมื่อเลขบัตรไม่ผ่านหลักที่ 13 อีกต่อไป ───
   * เดิม throw ตรงนี้ทำให้ `create()` ล้มทั้งคำขอตั้งแต่แถวแรกที่เลขบัตรพัง
   * — ไฟล์นำเข้าจริงเป็นพันแถวมักมีเลขบัตรปลอม/พิมพ์ผิดปนอยู่บ้างเสมอ
   * (เจอจริงกับ student.csv ที่แนบมา) การล้มทั้งไฟล์เพราะแถวเดียวบังคับให้
   * เจ้าหน้าที่ต้องไล่แก้ทีละแถวนอกระบบก่อนนำเข้าได้แม้แต่รอบแรก
   * ปล่อยผ่านตรงนี้แทน (ไม่ใส่ hash/enc ให้ช่องที่ผิด) แล้วให้
   * `validate_student_row` ที่ตรวจ checksum อยู่แล้วจับเป็นปัญหารายแถว
   * ตามกลไกเดิมของสองขั้นตอน (ตรวจ → เห็นรายการปัญหา → เลือกนำเข้าเฉพาะ
   * แถวที่ผ่าน) เลขที่ไม่ผ่านจึงไม่ถูกเข้ารหัส/แฮชและไม่ถูกเขียนลง
   * `person.national_id_enc`/`national_id_hash` เลย (ช่องว่างเปล่า ไม่ใช่
   * ค่าปลอมที่ดูเหมือนใช้ได้) — เหตุผลเดียวกับที่ `consume_password_reset()`
   * ค้นหาก่อนแฮชทีหลังใน CLAUDE.md
   */
  private encryptNationalIdFields(payload: Record<string, unknown>): Record<string, unknown> {
    const out = { ...payload };
    const own = typeof out.national_id === 'string' ? out.national_id.trim() : '';
    if (own && isValidThaiNationalId(own)) {
      if (!this.nationalIdKey) {
        throw new BadRequestException(
          'ระบบยังไม่ได้ตั้งกุญแจเข้ารหัสเลขประจำตัวประชาชน (NATIONAL_ID_KEY) ' +
            'จึงนำเข้าแถวที่มีเลขบัตรไม่ได้ — ลบคอลัมน์เลขบัตรออกก่อน หรือให้ผู้ดูแลระบบตั้งกุญแจ',
        );
      }
      const n = normalizeNationalId(own);
      out.national_id_hash_hex = hashNationalId(n, this.hashSecret).toString('hex');
      out.national_id_enc_hex = encryptNationalId(n, this.nationalIdKey).toString('hex');
    }

    for (const prefix of ['father', 'mother', 'guardian']) {
      const key = `${prefix}_national_id`;
      const raw = typeof out[key] === 'string' ? (out[key] as string).trim() : '';
      if (raw && isValidThaiNationalId(raw)) {
        out[`${prefix}_national_id_hash_hex`] =
          hashNationalId(normalizeNationalId(raw), this.hashSecret).toString('hex');
      }
    }

    return out;
  }

  /** ขั้นที่ 1 — สร้างรอบและตรวจทุกแถว ไม่เขียนข้อมูลจริงเลย */
  async create(dto: CreateImportDto) {
    return this.db.tx(async (c) => {
      const batch = (
        await c.query<{ id: string }>(
          `insert into import_batch
             (institution_id, kind, source_name, created_by, total_rows)
           values (current_institution_id(), $1::import_kind, $2, current_actor_id(), $3)
           returning id`,
          [dto.kind, dto.sourceName ?? null, dto.rows.length],
        )
      ).rows[0];

      for (const row of dto.rows) {
        // เข้ารหัส/แฮชเลขบัตรตอนสร้างแถวครั้งเดียว — apply_student_import()
        // ไม่มีกุญแจและไม่ควรมี (ดูคอมเมนต์บนสุดของ 0087)
        const payload = dto.kind === 'student'
          ? this.encryptNationalIdFields(row.payload)
          : row.payload;
        await c.query(
          `insert into import_row (batch_id, row_no, payload) values ($1, $2, $3::jsonb)`,
          [batch.id, row.rowNo, JSON.stringify(payload)],
        );
      }

      return this.validateInTx(c, batch.id, dto.kind);
    });
  }

  /** ตรวจซ้ำได้เรื่อย ๆ หลังแก้ข้อมูล */
  async validate(batchId: string) {
    return this.db.tx(async (c) => {
      const kind = (
        await c.query<{ kind: string }>(`select kind from import_batch where id = $1`, [
          batchId,
        ])
      ).rows[0]?.kind;
      if (!kind) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');
      return this.validateInTx(c, batchId, kind);
    });
  }

  private async validateInTx(
    c: Parameters<Parameters<DbService['tx']>[0]>[0],
    batchId: string,
    kind: string,
  ) {
    // ตรรกะการตรวจอยู่ในฐานข้อมูลทั้งหมด ชั้นนี้แค่สั่งให้ตรวจ
    // เพื่อให้สคริปต์นำเข้าที่รันตรงกับฐานข้อมูลได้ผลเหมือนกัน
    const validator =
      kind === 'student' ? 'validate_student_row'
      : kind === 'staff' ? 'validate_staff_row'
      : kind === 'academic_history' ? 'validate_academic_history_row'
      : kind === 'grade' ? 'validate_grade_import_row'
      : null;

    if (validator) {
      await c.query(
        `update import_row r
            set errors = ${validator}(b.institution_id, r.payload),
                ok = cardinality(${validator}(b.institution_id, r.payload)) = 0
           from import_batch b
          where b.id = r.batch_id and r.batch_id = $1`,
        [batchId],
      );
    }

    // เลขประจำตัวประชาชนซ้ำกันเองภายในไฟล์เดียว (คนละแถว คนละ student_code)
    // — validate_student_row() ตรวจได้แค่ "ซ้ำกับที่มีอยู่แล้วในฐานข้อมูล"
    // เพราะมองทีละแถว ไม่เห็นแถวอื่นในไฟล์เดียวกัน ถ้าไม่ตรวจตรงนี้ ทั้งสอง
    // แถวจะผ่านการตรวจแล้วไปชน unique constraint ตอน apply_student_import()
    // insert จริง ซึ่งจะโยน error ดิบของ PostgreSQL (ชื่อ constraint ล้วน)
    // แล้วล้มทั้งรอบนำเข้า ทั้งที่เพิ่งบอกผู้ใช้ว่า "ตรวจผ่านครบ" ไปหยก ๆ
    if (kind === 'student') {
      // ตรวจเงื่อนไขที่ฐานข้อมูลบังคับไว้ แต่ validator SQL รุ่นเก่าไม่รู้จัก
      // ไว้ชั้น API เพื่อให้ migration ที่เคย deploy แล้วไม่ต้องถูกแก้ย้อนหลัง
      // และผู้ใช้เห็นปัญหาก่อนกดนำเข้าจริง ไม่ใช่เจอชื่อ unique constraint ดิบ ๆ
      await c.query(
        `update import_row r
            set errors = array_append(r.errors, 'เลขประจำตัวประชาชนซ้ำกับคนที่มีอยู่แล้วในระบบ'),
                ok = false
           from import_batch b
          where b.id = r.batch_id and r.batch_id = $1
            and r.payload ? 'national_id_hash_hex'
            and exists (
              select 1 from person p
               where p.institution_id = b.institution_id
                 and p.national_id_hash = decode(r.payload->>'national_id_hash_hex', 'hex')
            )`,
        [batchId],
      );

      await c.query(
        `update import_row r
            set errors = array_append(r.errors, 'มีชื่อผู้ปกครองแต่ไม่มีนามสกุลผู้ปกครอง'),
                ok = false
           where r.batch_id = $1
             and nullif(btrim(r.payload->>'guardian_first_name_th'), '') is not null
             and nullif(btrim(r.payload->>'guardian_last_name_th'), '') is null`,
        [batchId],
      );

      await c.query(
        `with dup as (
           select row_no, national_id_hash_hex,
                  array_agg(row_no) over (partition by national_id_hash_hex) as rows_with_same_id
             from (select row_no, payload->>'national_id_hash_hex' as national_id_hash_hex
                     from import_row where batch_id = $1) t
            where national_id_hash_hex is not null
         )
         update import_row r
            set errors = array_append(r.errors,
                  format('เลขประจำตัวประชาชนซ้ำกับแถวที่ %s ในไฟล์เดียวกัน',
                         array_to_string(array_remove(d.rows_with_same_id, d.row_no), ', '))),
                ok = false
           from dup d
          where r.batch_id = $1 and r.row_no = d.row_no
            and cardinality(d.rows_with_same_id) > 1`,
        [batchId],
      );
    }

    await c.query(
      `update import_batch b
          set ok_rows    = s.ok_rows,
              error_rows = s.error_rows,
              total_rows = s.total_rows,
              status     = (case when s.error_rows = 0 then 'validated' else 'failed' end)::import_status
         from (select count(*) filter (where ok)     as ok_rows,
                      count(*) filter (where not ok) as error_rows,
                      count(*)                       as total_rows
                 from import_row where batch_id = $1) s
        where b.id = $1 and b.status <> 'applied'`,
      [batchId],
    );

    return this.detail(batchId, c);
  }

  async detail(
    batchId: string,
    client?: Parameters<Parameters<DbService['tx']>[0]>[0],
  ) {
    const run = async (c: Parameters<Parameters<DbService['tx']>[0]>[0]) => {
      const batch = (
        await c.query(
          `select id, kind, source_name, status, total_rows, ok_rows, error_rows,
                  created_at, applied_at, note
             from import_batch where id = $1`,
          [batchId],
        )
      ).rows[0];
      if (!batch) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');

      // คืนเฉพาะแถวที่มีปัญหา เพราะไฟล์พันแถวที่ผ่านหมดไม่มีอะไรให้ดู
      // และการส่งกลับทั้งหมดทำให้หน้าจอค้าง
      const problems = (
        await c.query(
          `select row_no, errors, payload
             from import_row where batch_id = $1 and not ok
            order by row_no limit 500`,
          [batchId],
        )
      ).rows;

      return { ...batch, problems };
    };

    return client ? run(client) : this.db.tx(run);
  }

  async list(kind?: string) {
    return this.db.query(
      `select id, kind, source_name, status, total_rows, ok_rows, error_rows,
              created_at, applied_at
         from import_batch
        where ($1::text is null or kind::text = $1)
        order by created_at desc limit 100`,
      [kind ?? null],
    );
  }

  /**
   * ลบรอบนำเข้าที่ยังไม่ได้กดนำเข้าจริง — ทุกครั้งที่กด "ตรวจอย่างเดียว" หรือ
   * ลองไฟล์ใหม่ระบบสร้างรอบใหม่เสมอ (ไม่ใช้ซ้ำของเดิม) รอบที่ตรวจแล้วพบว่าผิด
   * แล้วเจ้าหน้าที่แก้ไฟล์ไปอัปโหลดใหม่จึงค้างอยู่ในตารางประวัติเรื่อย ๆ
   * โดยไม่มีทางลบทิ้ง — ลบได้เฉพาะรอบที่ยังไม่ถูกนำเข้าจริง เพราะรอบที่นำเข้า
   * แล้วคือหลักฐานว่าเคยเขียนอะไรลงไปบ้าง (`applied_at` ใช้ตรวจสอบย้อนหลังได้)
   */
  async remove(batchId: string) {
    const row = await this.db.queryOne<{ status: string }>(
      `select status from import_batch where id = $1`,
      [batchId],
    );
    if (!row) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');
    if (row.status === 'applied') {
      throw new BadRequestException('รอบนี้นำเข้าจริงไปแล้ว ลบไม่ได้ — เป็นหลักฐานว่าเคยเขียนอะไรลงไปบ้าง');
    }
    await this.db.query(`delete from import_batch where id = $1`, [batchId]);
  }

  /**
   * ขั้นที่ 2 — นำเข้าจริง ทั้งชุดหรือไม่เลย
   *
   * เลือกฟังก์ชันตามชนิดของรอบนำเข้า ไม่ใช่ให้ผู้เรียกระบุมา — ถ้าผู้เรียก
   * ระบุได้ จะยิงรอบของบุคลากรเข้าตัวนำเข้านักศึกษาได้ ซึ่งฟังก์ชันจะปฏิเสธ
   * ด้วยข้อความที่ไม่มีใครเข้าใจว่าเกิดอะไรขึ้น
   */
  async apply(batchId: string) {
    return this.db.tx(async (c) => {
      const kind = (
        await c.query<{ kind: string }>(`select kind from import_batch where id = $1`, [
          batchId,
        ])
      ).rows[0]?.kind;
      if (!kind) throw new ForbiddenException('ไม่พบรอบนำเข้านี้ หรือไม่มีสิทธิ์เข้าถึง');

      const fn =
        kind === 'student' ? 'apply_student_import'
        : kind === 'staff' ? 'apply_staff_import'
        : kind === 'academic_history' ? 'apply_academic_history_import'
        : kind === 'grade' ? 'apply_grade_import'
        : null;

      if (!fn) {
        throw new UnprocessableEntityException(
          `ยังไม่รองรับการนำเข้าชนิด "${kind}" — ตอนนี้มีนักศึกษา บุคลากร ประวัติการเรียนเดิม และผลการเรียน`,
        );
      }

      // ตรวจซ้ำทันทีใน transaction เดียวกับการนำเข้าจริงด้วย เพราะผลตรวจเดิม
      // อาจล้าสมัยหลังผู้ใช้อัปโหลดไฟล์ (เช่น มีคนอื่นเพิ่มเลขบัตรเดียวกันแล้ว)
      // และ apply_student_import() รุ่นที่ deploy อยู่ตรวจทีละแถว จึงมองไม่เห็น
      // เลขบัตรซ้ำกันภายใน batch เอง
      const checked = await this.validateInTx(c, batchId, kind);
      if (Number(checked.error_rows) > 0) {
        throw new BadRequestException(
          `รอบนำเข้านี้มี ${checked.error_rows} แถวที่ต้องแก้ไขก่อนนำเข้าจริง`,
        );
      }

      const row = (
        await c.query<{ imported: number; failed: number }>(`select * from ${fn}($1)`, [
          batchId,
        ])
      ).rows[0];

      return { imported: Number(row?.imported ?? 0), failed: Number(row?.failed ?? 0) };
    });
  }

  // ─── ประวัติการเรียนจากสถานศึกษาเดิม ───────────────────────────

  async addPriorRecords(records: PriorRecordDto[]) {
    return this.db.tx(async (c) => {
      let written = 0;
      for (const r of records) {
        const res = await c.query(
          `insert into prior_academic_record
             (student_id, source_th, term_label, course_code, course_name_th,
              credits, grade_symbol, grade_point, mapped_course_id, note,
              transfer_kind, counts_in_gpa)
           values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                   coalesce($11::credit_source_kind, 'transferred_experience'),
                   -- โอนผลการเรียนยกเกรดเดิมมาด้วย จึงนับ GPA ส่วนเทียบโอน
                   -- ความรู้และประสบการณ์ให้หน่วยกิตอย่างเดียว สองค่านี้
                   -- ต้องเดินคู่กันเสมอ มิฉะนั้นใบจะพิมพ์ (*1) ให้วิชาที่
                   -- ไม่มีแต้ม หรือ (*2) ให้วิชาที่มีแต้มอยู่ในตาราง
                   $11 = 'transferred_grade')
           on conflict (student_id, term_label, course_code) do nothing`,
          [
            r.studentId, r.sourceTh, r.termLabel ?? null, r.courseCode,
            r.courseNameTh, r.credits, r.gradeSymbol, r.gradePoint ?? null,
            r.mappedCourseId ?? null, r.note ?? null, r.transferKind ?? null,
          ],
        );
        written += res.rowCount ?? 0;
      }
      return { written, skipped: records.length - written };
    });
  }

  async priorRecords(studentId: string) {
    return this.db.tx(async (c) => {
      const records = (
        await c.query(
          `select pr.id, pr.source_th, pr.term_label, pr.course_code, pr.course_name_th,
                  pr.credits, pr.grade_symbol, pr.grade_point,
                  pr.approved_at, pr.note,
                  co.code as mapped_course_code, co.name_th as mapped_course_name
             from prior_academic_record pr
             left join course co on co.id = pr.mapped_course_id
            where pr.student_id = $1
            order by pr.term_label nulls last, pr.course_code`,
          [studentId],
        )
      ).rows;

      const summary = (
        await c.query(
          `select coalesce(sum(credits) filter (where approved_at is not null and earns_credit), 0)
                    as approved_credits,
                  coalesce(sum(credits) filter (where approved_at is null), 0)
                    as pending_credits,
                  count(*) as entries
             from prior_academic_record where student_id = $1`,
          [studentId],
        )
      ).rows[0];

      return { ...summary, records };
    });
  }

  /**
   * อนุมัติเทียบโอน
   *
   * หน่วยกิตที่ยังไม่อนุมัติไม่ถูกนับ เหมือนชั่วโมงฝึกที่ยังไม่รับรอง
   * เพราะการเทียบโอนเป็นดุลยพินิจของฝ่ายวิชาการ ไม่ใช่ผลอัตโนมัติ
   * ของการนำเข้าไฟล์
   */
  async approveTransfer(dto: ApproveTransferDto) {
    const row = await this.db.queryOne<{ n: string }>(
      `with updated as (
         update prior_academic_record
            set approved_at = now(),
                approved_by = (select id from staff where person_id = current_actor_id())
          where id = any($1::uuid[]) and approved_at is null
          returning 1)
       select count(*)::text as n from updated`,
      [dto.recordIds],
    );
    return { approved: Number(row?.n ?? 0) };
  }
}

@Roles('registrar', 'academic', 'director', 'admin')
@Controller('import')
class ImportController {
  constructor(private readonly svc: ImportService) {}

  @Get()
  list(@Query('kind') kind?: string) {
    return this.svc.list(kind);
  }

  @Audit('import_batch')
  @Post()
  create(@Body() dto: CreateImportDto) {
    return this.svc.create(dto);
  }

  @Get(':id')
  detail(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.detail(id);
  }

  @Post(':id/validate')
  validate(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.validate(id);
  }

  @Audit('import_batch')
  @Post(':id/apply')
  apply(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.apply(id);
  }

  @Audit('import_batch')
  @Delete(':id')
  remove(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.remove(id);
  }
}

@Controller('prior-records')
class PriorRecordController {
  constructor(private readonly svc: ImportService) {}

  @Roles(
    'student', 'guardian', 'teacher', 'registrar',
    'academic', 'director', 'admin',
  )
  @Audit('prior_academic_record', 'studentId')
  @Get('students/:studentId')
  forStudent(@Param('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.priorRecords(studentId);
  }

  @Roles('registrar', 'academic', 'director', 'admin')
  @Post()
  add(@Body() dto: { records: PriorRecordDto[] }) {
    return this.svc.addPriorRecords(dto.records ?? []);
  }

  @Roles('academic', 'director', 'admin')
  @Audit('prior_academic_record')
  @Post('approve')
  approve(@Body() dto: ApproveTransferDto) {
    return this.svc.approveTransfer(dto);
  }
}

@Module({
  controllers: [ImportController, PriorRecordController],
  providers: [ImportService],
  exports: [ImportService],
})
export class ImportModule {}

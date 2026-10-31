/**
 * การตั้งค่าระดับวิทยาลัยแบบ SISA "การตั้งค่า" — ข้อมูลพื้นฐาน (0098) และ
 * ข้อความประจำสถานศึกษาที่พิมพ์บนเอกสาร (institution_document_text · 0057)
 *
 * ข้อความบนเอกสารมีตารางและ RLS มาตั้งแต่ 0057 แต่ไม่เคยมีเส้นทางให้แก้เลย
 * วิทยาลัยจึงเปลี่ยนเกณฑ์การสำเร็จการศึกษาหรือชื่อผู้ลงนามบนใบ รบ. ไม่ได้
 * นอกจากเปิด pgAdmin เอง — รูปเดียวกับบทเรียนข้อ 20/24
 */
import {
  BadRequestException, Body, Controller, Get, Injectable, Module, NotFoundException, Param, Patch, Post, Query,
} from '@nestjs/common';
import { IsBoolean, IsIn, IsInt, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { ParseUuidPipe } from '../../common/validation/uuid';

const CATEGORIES = ['prefix', 'religion', 'nationality', 'ethnicity', 'occupation', 'bank', 'school', 'qualification'] as const;

/**
 * คีย์ที่แม่แบบเอกสารอ่านจริง — รายการปิด เพราะคีย์ที่สะกดผิดจะถูกบันทึกได้
 * แต่ไม่มีแม่แบบไหนอ่าน เจ้าหน้าที่จะเห็นว่าแก้แล้วแต่กระดาษไม่เปลี่ยน
 */
export const DOCUMENT_TEXT_KEYS: { key: string; label: string }[] = [
  { key: 'transcript_criteria_1', label: 'เกณฑ์การสำเร็จการศึกษา ข้อ 1' },
  { key: 'transcript_criteria_2', label: 'เกณฑ์การสำเร็จการศึกษา ข้อ 2' },
  { key: 'transcript_criteria_3', label: 'เกณฑ์การสำเร็จการศึกษา ข้อ 3' },
  { key: 'transcript_criteria_4', label: 'เกณฑ์การสำเร็จการศึกษา ข้อ 4' },
  { key: 'transcript_criteria_5', label: 'เกณฑ์การสำเร็จการศึกษา ข้อ 5' },
  { key: 'transcript_note_1', label: 'หมายเหตุ (*1)' },
  { key: 'transcript_note_2', label: 'หมายเหตุ (*2)' },
  { key: 'transcript_note_3', label: 'หมายเหตุ (*3)' },
  { key: 'transcript_note_4', label: 'หมายเหตุ (*4)' },
  { key: 'transcript_note_5', label: 'หมายเหตุ (*5)' },
  { key: 'transcript_signer_registrar', label: 'ชื่อนายทะเบียนที่ลงนามบนใบ รบ.' },
  { key: 'transcript_signer_director', label: 'ชื่อผู้อำนวยการที่ลงนามบนใบ รบ.' },
];

class OptionDto {
  @IsIn(CATEGORIES as unknown as string[]) category: string;
  @IsString() @MinLength(1) @MaxLength(200) labelTh: string;
  @IsOptional() @IsString() @MaxLength(200) labelEn?: string;
  @IsOptional() @IsString() @MaxLength(20) code?: string;
  @IsOptional() @IsInt() sortOrder?: number;
}

class OptionPatchDto {
  @IsOptional() @IsString() @MinLength(1) @MaxLength(200) labelTh?: string;
  @IsOptional() @IsString() @MaxLength(200) labelEn?: string;
  @IsOptional() @IsString() @MaxLength(20) code?: string;
  @IsOptional() @IsInt() sortOrder?: number;
  @IsOptional() @IsBoolean() active?: boolean;
}

class DocumentTextDto {
  @IsString() key: string;
  @IsOptional() @IsString() @MaxLength(500) textTh?: string;
  @IsOptional() @IsString() @MaxLength(500) textEn?: string;
}

@Injectable()
export class SettingsService {
  constructor(private readonly db: DbService) {}

  options(category?: string) {
    if (category && !(CATEGORIES as readonly string[]).includes(category)) {
      throw new BadRequestException('ไม่รู้จักหมวดข้อมูลพื้นฐานนี้');
    }
    return this.db.query(
      `select id, category, code, label_th, label_en, sort_order, active
         from reference_option
        where ($1::text is null or category = $1)
        order by category, sort_order, label_th`,
      [category ?? null],
    );
  }

  async addOption(dto: OptionDto) {
    return this.db.queryOne(
      `insert into reference_option (institution_id, category, code, label_th, label_en, sort_order)
       values (current_institution_id(), $1, $2, btrim($3), nullif(btrim($4), ''), coalesce($5, 0))
       returning id, category, code, label_th, label_en, sort_order, active`,
      [dto.category, dto.code ?? null, dto.labelTh, dto.labelEn ?? null, dto.sortOrder ?? null],
    );
  }

  /** ปิดแทนการลบ — ข้อมูลนักศึกษาเก่าที่ใช้คำนั้นอยู่ยังต้องอ่านออกว่ามาจากรายการไหน */
  async updateOption(id: string, dto: OptionPatchDto) {
    const row = await this.db.queryOne(
      `update reference_option set
         label_th   = coalesce(btrim($2), label_th),
         label_en   = coalesce($3, label_en),
         code       = coalesce($4, code),
         sort_order = coalesce($5, sort_order),
         active     = coalesce($6, active)
       where id = $1
       returning id, category, code, label_th, label_en, sort_order, active`,
      [id, dto.labelTh ?? null, dto.labelEn ?? null, dto.code ?? null, dto.sortOrder ?? null, dto.active ?? null],
    );
    if (!row) throw new NotFoundException('ไม่พบรายการ หรือไม่มีสิทธิ์แก้ไข');
    return row;
  }

  async documentTexts() {
    const rows = await this.db.query<{ key: string; text_th: string | null; text_en: string | null; updated_at: string }>(
      `select key, text_th, text_en, updated_at from institution_document_text`,
    );
    return DOCUMENT_TEXT_KEYS.map((k) => {
      const r = rows.find((x) => x.key === k.key);
      return { ...k, textTh: r?.text_th ?? null, textEn: r?.text_en ?? null, updatedAt: r?.updated_at ?? null };
    });
  }

  async setDocumentText(dto: DocumentTextDto) {
    if (!DOCUMENT_TEXT_KEYS.some((k) => k.key === dto.key)) {
      throw new BadRequestException('ไม่รู้จักข้อความนี้ — แม่แบบเอกสารจะไม่อ่านค่าที่บันทึก');
    }
    return this.db.queryOne(
      `insert into institution_document_text (institution_id, key, text_th, text_en)
       values (current_institution_id(), $1, nullif(btrim($2), ''), nullif(btrim($3), ''))
       on conflict (institution_id, key) do update
         set text_th = excluded.text_th, text_en = excluded.text_en, updated_at = now()
       returning key, text_th, text_en, updated_at`,
      [dto.key, dto.textTh ?? null, dto.textEn ?? null],
    );
  }
}

@Controller('settings')
export class SettingsController {
  constructor(private readonly svc: SettingsService) {}

  /** อ่านได้ทุกบทบาทเจ้าหน้าที่ — ครูต้องเห็นตัวเลือกตอนกรอกข้อมูลนักศึกษา */
  @Roles('registrar', 'academic', 'finance', 'student_affairs', 'secretary', 'hr', 'teacher', 'director', 'admin')
  @Get('options')
  options(@Query('category') category?: string) {
    return this.svc.options(category);
  }

  @Roles('registrar', 'director', 'admin')
  @Audit('reference_option')
  @Post('options')
  addOption(@Body() dto: OptionDto) {
    return this.svc.addOption(dto);
  }

  @Roles('registrar', 'director', 'admin')
  @Audit('reference_option', 'id')
  @Patch('options/:id')
  updateOption(@Param('id', ParseUuidPipe) id: string, @Body() dto: OptionPatchDto) {
    return this.svc.updateOption(id, dto);
  }

  @Roles('registrar', 'director', 'admin')
  @Get('document-texts')
  documentTexts() {
    return this.svc.documentTexts();
  }

  @Roles('registrar', 'director', 'admin')
  @Audit('institution_document_text')
  @Post('document-texts')
  setDocumentText(@Body() dto: DocumentTextDto) {
    return this.svc.setDocumentText(dto);
  }
}

@Module({
  controllers: [SettingsController],
  providers: [SettingsService],
})
export class SettingsModule {}

import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ArrayNotEmpty, IsArray, IsBoolean, IsIn, IsISO8601, IsInt, IsNumber, IsOptional, IsString, Max, MaxLength, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { Audit } from '../../common/audit/audit.interceptor';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { renderDocument, type IssuedDocument } from '../documents/templates';

const METHODS = [
  'cash', 'bank_transfer', 'promptpay', 'credit_card', 'counter_service',
  'direct_debit', 'gov_subsidy', 'student_loan', 'scholarship', 'adjustment',
] as const;

const FEE_ITEM_KINDS = [
  'tuition', 'lab_material', 'activity', 'insurance', 'uniform', 'book', 'exam', 'dormitory', 'other',
] as const;

const QUALIFICATION_LEVELS = ['PVC', 'PVS', 'TVB'] as const;

const FUNDING_KINDS = [
  'scholarship', 'sibling', 'staff_child', 'gov_subsidy', 'student_loan', 'employer', 'other',
] as const;

class LateFeePolicyDto {
  @IsInt() @Min(2500) @Max(2700) effectiveFromYearBe: number;
  @IsOptional() @IsInt() @Min(0) @Max(365) graceDays?: number;
  @IsOptional() @IsNumber() @Min(0) flatAmount?: number;
  @IsOptional() @IsNumber() @Min(0) dailyAmount?: number;
  @IsOptional() @IsNumber() @Min(0) maxAmount?: number;
  @IsOptional() @IsInt() @Min(0) @Max(365) holdAfterDays?: number;
  @IsOptional() @IsBoolean() blocksTranscriptAfterHold?: boolean;
}

class FeeItemDto {
  @IsString() @MaxLength(20) code: string;
  @IsString() @MaxLength(200) nameTh: string;
  @IsIn(FEE_ITEM_KINDS as unknown as string[]) kind: string;
  @IsOptional() @IsBoolean() subsidised?: boolean;
  @IsOptional() @IsBoolean() refundable?: boolean;
}

/**
 * level/studyYear/programId เว้นว่างได้ทั้งสามช่อง = "รวม" ใช้กับทุกค่าของ
 * มิตินั้น (ดู 0080) — เจาะจงได้เท่าที่วิทยาลัยต้องการจริง ไม่บังคับครบ
 */
class FeeScheduleDto {
  @IsUuid() academicYearId: string;
  @IsOptional() @IsIn(QUALIFICATION_LEVELS as unknown as string[]) level?: string;
  @IsOptional() @IsInt() @Min(1) @Max(4) studyYear?: number;
  @IsOptional() @IsUuid() programId?: string;
  @IsOptional() @IsString() @MaxLength(100) announcementNo?: string;
  @IsOptional() @IsISO8601() announcedOn?: string;
}

class FeeScheduleLineDto {
  @IsUuid() feeItemId: string;
  @IsInt() @Min(1) @Max(3) termOrdinal: number;
  @IsNumber() @Min(0) amount: number;
}

class SetFeeScheduleLinesDto {
  @IsArray() @ArrayNotEmpty() @ValidateNested({ each: true }) @Type(() => FeeScheduleLineDto)
  lines: FeeScheduleLineDto[];
}

class FundingSourceDto {
  @IsIn(FUNDING_KINDS as unknown as string[]) kind: string;
  @IsString() @MaxLength(200) nameTh: string;
  @IsOptional() @IsString() @MaxLength(100) externalRef?: string;
}

/**
 * feeItemId เว้นว่าง = ลดทุกรายการในใบแจ้งหนี้ (ทุนที่ตั้งใจลดทั้งใบ) ·
 * ระบุ = ลดเฉพาะรายการนั้น (เช่น ลดค่าแรกเข้าอย่างเดียว) — ดู 0080
 * ต้องมี percentOff หรือ amount อย่างใดอย่างหนึ่งเสมอ (constraint บังคับอยู่แล้ว
 * แต่ตรวจซ้ำที่นี่เพื่อให้ข้อความผิดพลาดอ่านง่ายกว่าข้อความจาก constraint)
 */
class StudentFundingDto {
  @IsUuid() fundingSourceId: string;
  @IsUuid() academicYearId: string;
  @IsOptional() @IsUuid() termId?: string;
  @IsOptional() @IsUuid() feeItemId?: string;
  @IsOptional() @IsNumber() @Min(0) @Max(100) percentOff?: number;
  @IsOptional() @IsNumber() @Min(0) amount?: number;
  @IsOptional() @IsString() @MaxLength(100) documentNo?: string;
  @IsOptional() @IsString() @MaxLength(500) note?: string;
}

class IssueInvoiceDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsOptional() @IsInt() @Min(1) @Max(6) installments?: number;
}

/**
 * ─── ทำไมไม่มี receiptNo ให้กรอกอีกแล้ว ───
 * เลขที่ใบเสร็จออกโดย `issue_receipt()` จากสายเลขของสถานศึกษา ไม่ใช่ค่าที่
 * เจ้าหน้าที่พิมพ์เข้ามา — ของเดิมพิมพ์เลขซ้ำกันสองใบก็ได้ เว้นว่างก็ได้
 * และไม่มีอะไรผูกเลขนั้นกับกระดาษที่พิมพ์ออกไปเลย
 *
 * ฟิลด์ที่ไม่รู้จักถูกปฏิเสธด้วย 400 อยู่แล้ว (API-23) ผู้เรียกเก่าจึงรู้ตัว
 * ทันทีแทนที่จะส่งเลขมาแล้วถูกเมินเงียบ ๆ
 */
class PaymentDto {
  @IsUuid() studentId: string;
  @IsNumber() @Min(0.01) amount: number;
  @IsIn(METHODS as unknown as string[]) method: string;
  @IsOptional() @IsISO8601() receivedOn?: string;
  @IsOptional() @IsString() bankRef?: string;
  @IsOptional() @IsString() note?: string;
}

class BankTxnDto {
  @IsISO8601() postedAt: string;
  @IsNumber() amount: number;
  @IsOptional() @IsString() counterparty?: string;
  @IsOptional() @IsString() bankRef?: string;
  @IsOptional() @IsString() ref1?: string;
  @IsOptional() @IsString() ref2?: string;
}

class ImportBankDto {
  @IsArray() @ArrayNotEmpty() @ValidateNested({ each: true }) @Type(() => BankTxnDto)
  transactions: BankTxnDto[];
}

/** ไม่ระบุ studentId = ยอมรับข้อเสนอเดิมของรายการนี้ */
class ConfirmMatchDto {
  @IsOptional() @IsUuid() studentId?: string;
}

@Injectable()
export class FinanceService {
  constructor(private readonly db: DbService) {}

  async issueInvoice(dto: IssueInvoiceDto) {
    const row = await this.db.queryOne<{ id: string }>(
      `select issue_invoice($1, $2, $3) as id`,
      [dto.studentId, dto.termId, dto.installments ?? 1],
    );
    return this.getInvoice(row!.id);
  }

  async getInvoice(id: string) {
    return this.db.tx(async (c) => {
      const inv = (
        await c.query(
          `select id, invoice_no, issued_on, due_on, subtotal, discount_total,
                  total, paid_total, status, ref1, ref2
             from invoice where id = $1`,
          [id],
        )
      ).rows[0];

      const lines = (
        await c.query(
          `select description, amount, discount, amount - discount as net
             from invoice_line where invoice_id = $1 order by description`,
          [id],
        )
      ).rows;

      const installments = (
        await c.query(
          `select seq, due_on, amount, paid_amount, penalty, status
             from installment where invoice_id = $1 order by seq`,
          [id],
        )
      ).rows;

      return { ...inv, lines, installments };
    });
  }

  /**
   * สร้างรายการรับเงินแล้วตัดยอดทันทีในธุรกรรมเดียว
   * ถ้าตัดยอดล้มเหลว รายการรับเงินจะไม่ถูกบันทึกด้วย
   */
  async recordPayment(dto: PaymentDto) {
    return this.db.tx(async (c) => {
      const pay = await c.query<{ id: string }>(
        `insert into payment
           (institution_id, student_id, received_on, amount, method, bank_ref, note, received_by)
         select s.institution_id, s.id, coalesce($2::date, current_date), $3, $4::payment_method,
                $5, $6, current_actor_id()
           from student s where s.id = $1
         returning id`,
        [
          dto.studentId, dto.receivedOn ?? null, dto.amount,
          dto.method, dto.bankRef ?? null, dto.note ?? null,
        ],
      );

      const paymentId = pay.rows[0].id;
      // post_payment() ออกใบเสร็จให้ในตัว — กฎ "รับเงินแล้วต้องมีใบเสร็จ"
      // อยู่ที่ฐานข้อมูล ไม่ใช่ที่นี่ (0068)
      const left = await c.query<{ remaining: string }>(
        `select post_payment($1) as remaining`,
        [paymentId],
      );

      const receipt = await c.query<{ id: string; doc_no: string }>(
        `select id, doc_no from issued_document
          where kind = 'receipt' and payload ->> 'payment_id' = $1
            and voided_at is null
          limit 1`,
        [paymentId],
      );

      const balance = await c.query(
        `select outstanding, next_due_on, days_overdue
           from v_student_balance where student_id = $1`,
        [dto.studentId],
      );

      return {
        paymentId,
        // คืนเลขที่กับรหัสใบเสร็จออกไปด้วย เพราะสิ่งแรกที่เจ้าหน้าที่ต้องทำ
        // ต่อจากกดรับเงินคือพิมพ์ใบให้ผู้ปกครองที่ยืนรออยู่ตรงนั้น
        receipt: receipt.rows[0] ?? null,
        overpaid: Number(left.rows[0].remaining),
        balance: balance.rows[0] ?? { outstanding: 0 },
      };
    });
  }

  async importBankTransactions(dto: ImportBankDto) {
    return this.db.tx(async (c) => {
      let inserted = 0;
      for (const t of dto.transactions) {
        const r = await c.query(
          `insert into bank_transaction
             (institution_id, posted_at, amount, counterparty, bank_ref, ref1, ref2)
           values (current_institution_id(), $1, $2, $3, $4, $5, $6)
           on conflict do nothing`,
          [t.postedAt, t.amount, t.counterparty ?? null, t.bankRef ?? null, t.ref1 ?? null, t.ref2 ?? null],
        );
        inserted += r.rowCount ?? 0;
      }
      return { imported: inserted, skipped: dto.transactions.length - inserted };
    });
  }

  /** ตัดยอดเองเฉพาะที่มั่นใจสูง ที่เหลือขึ้นเป็นข้อเสนอให้เจ้าหน้าที่กดยืนยัน */
  async reconcile() {
    const row = await this.db.queryOne<{
      auto_matched: number; suggested: number; unmatched: number;
    }>(
      `select * from reconcile_bank_transactions(current_institution_id())`,
    );
    return {
      autoMatched: Number(row?.auto_matched ?? 0),
      suggested: Number(row?.suggested ?? 0),
      unmatched: Number(row?.unmatched ?? 0),
    };
  }

  /** รายการที่ระบบจับคู่ไม่ได้ — หน้าจอ P-05 แสดงเฉพาะชุดนี้ ไม่ใช่ทั้งหมด */
  async pendingMatches() {
    return this.db.query(
      `select bt.id, bt.posted_at, bt.amount, bt.counterparty, bt.ref1, bt.ref2,
              bt.state, bt.confidence, bt.match_reason,
              i.id as invoice_id, i.invoice_no, s.student_code,
              p.first_name_th || ' ' || p.last_name_th as student_name
         from bank_transaction bt
         left join invoice i on i.id = bt.matched_invoice_id
         left join student s on s.id = i.student_id
         left join person  p on p.id = s.person_id
        where bt.state in ('unmatched', 'suggested')
        order by bt.posted_at desc
        limit 200`,
    );
  }

  /**
   * เจ้าหน้าที่ยืนยันข้อเสนอ (หรือระบุใบแจ้งหนี้เองถ้าข้อเสนอผิดหรือยังไม่มี)
   *
   * รับเงินจริงและออกใบเสร็จผ่าน post_payment() เหมือนรับชำระปกติทุกประการ —
   * ไม่มีทางลัดที่ข้ามใบเสร็จไปได้ (0068)
   */
  async confirmMatch(id: string, studentId?: string) {
    return this.db.tx(async (c) => {
      const pay = await c.query<{ id: string }>(
        `select confirm_bank_match($1, $2) as id`,
        [id, studentId ?? null],
      );
      const paymentId = pay.rows[0].id;

      const receipt = await c.query<{ id: string; doc_no: string }>(
        `select id, doc_no from issued_document
          where kind = 'receipt' and payload ->> 'payment_id' = $1
            and voided_at is null
          limit 1`,
        [paymentId],
      );

      return { paymentId, receipt: receipt.rows[0] ?? null };
    });
  }

  /** ทำเครื่องหมายว่ารายการนี้ไม่ใช่ค่าเทอม — ไม่ลบทิ้ง เพื่อตรวจสอบย้อนหลังได้ */
  async ignoreMatch(id: string) {
    await this.db.query(`select ignore_bank_match($1)`, [id]);
    return { ignored: id };
  }

  /** ตั้งเป็นงานประจำวัน งานทะเบียนไม่ต้องรู้จักใบแจ้งหนี้เลย */
  async refreshHolds() {
    const row = await this.db.queryOne<{ placed: number; released: number }>(
      `select * from refresh_finance_holds(current_institution_id())`,
    );
    return { placed: Number(row?.placed ?? 0), released: Number(row?.released ?? 0) };
  }

  /**
   * ใบเสร็จที่ออกให้นักศึกษาคนหนึ่ง — ปิดเมนู "พิมพ์ใบเสร็จย้อนหลัง"
   *
   * ─── ทำไมอ่านยอดจาก payload ไม่ใช่ join กลับไปที่ payment ───
   * ตัวเลขบนกระดาษคือตัวเลข ณ วันที่ออกใบ ถ้าดึงจาก `payment` ตอนนี้แล้ว
   * วันหนึ่งมีการแก้ไขรายการ (คืนเงิน · ปรับปรุง) รายการในหน้าจอจะไม่ตรงกับ
   * ใบที่ผู้ปกครองถืออยู่ โดยที่ทั้งสองฝั่งดูถูกต้องในสายตาตัวเอง
   */
  async receipts(studentId: string) {
    return this.db.query(
      `select d.id, d.doc_no, d.issued_on, d.voided_at, d.void_reason,
              (d.payload -> 'payment' ->> 'amount')::numeric as amount,
              d.payload -> 'payment' ->> 'method'            as method,
              d.payload ->> 'amount_text'                    as amount_text
         from issued_document d
        where d.kind = 'receipt' and d.student_id = $1
        order by d.issued_on desc, d.doc_no desc
        limit 200`,
      [studentId],
    );
  }

  /**
   * หน้ากระดาษของใบเสร็จหนึ่งใบ
   *
   * ─── ทำไมไม่ใช้ `GET /documents/:id/print` ที่มีอยู่แล้ว ───
   * เส้นทางนั้นเปิดให้ registrar/academic/student_affairs/director/admin
   * ซึ่ง**ไม่มี finance** — งานการเงินจึงออกใบเสร็จได้แต่พิมพ์ไม่ได้ ส่วนการ
   * เติม finance เข้าไปในเส้นทางนั้นแปลว่างานการเงินพิมพ์ใบ รบ. กับระเบียน
   * สะสมของใครก็ได้ด้วย ซึ่งเป็นข้อมูลคนละเรื่องกับหน้าที่ของตำแหน่ง
   *
   * ทางนี้จึงพิมพ์ได้เฉพาะ kind = 'receipt' และปฏิเสธใบชนิดอื่นอย่างชัดเจน
   */
  async printReceipt(id: string) {
    const doc = await this.db.queryOne<IssuedDocument>(
      `select id, kind, doc_no, copy_no, issued_on, voided_at, void_reason, payload
         from issued_document where id = $1`,
      [id],
    );
    if (!doc) throw new NotFoundException('ไม่พบใบเสร็จ หรือไม่มีสิทธิ์เข้าถึง');
    if (doc.kind !== 'receipt') {
      throw new BadRequestException('เส้นทางนี้พิมพ์ได้เฉพาะใบเสร็จรับเงิน');
    }
    return renderDocument(doc);
  }

  async aging() {
    return this.db.query(
      `select bucket, students, amount from v_ar_aging
        order by case bucket
                   when 'ยังไม่ครบกำหนด' then 1
                   when 'เกิน 1–30 วัน'  then 2
                   when 'เกิน 31–60 วัน' then 3
                   else 4 end`,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // นโยบายค่าปรับและการระงับสิทธิ์ — เดิมตั้งได้ทาง SQL ตรงเท่านั้น (0094)
  // ─────────────────────────────────────────────────────────────────
  async latePolicy() {
    return this.db.queryOne(
      `select id, effective_from_year_be, grace_days, flat_amount, daily_amount,
              max_amount, hold_after_days, blocks_transcript_after_hold
         from late_fee_policy where institution_id = current_institution_id()
        order by effective_from_year_be desc limit 1`,
    );
  }

  async setLatePolicy(dto: LateFeePolicyDto) {
    return this.db.queryOne(
      `insert into late_fee_policy
         (institution_id, effective_from_year_be, grace_days, flat_amount,
          daily_amount, max_amount, hold_after_days, blocks_transcript_after_hold)
       values (current_institution_id(), $1, coalesce($2, 7), coalesce($3, 0),
               coalesce($4, 0), $5, coalesce($6, 30), coalesce($7, false))
       on conflict (institution_id, effective_from_year_be) do update
         set grace_days = excluded.grace_days,
             flat_amount = excluded.flat_amount,
             daily_amount = excluded.daily_amount,
             max_amount = excluded.max_amount,
             hold_after_days = excluded.hold_after_days,
             blocks_transcript_after_hold = excluded.blocks_transcript_after_hold
       returning id, effective_from_year_be, grace_days, flat_amount, daily_amount,
                 max_amount, hold_after_days, blocks_transcript_after_hold`,
      [
        dto.effectiveFromYearBe,
        dto.graceDays ?? null,
        dto.flatAmount ?? null,
        dto.dailyAmount ?? null,
        dto.maxAmount ?? null,
        dto.holdAfterDays ?? null,
        dto.blocksTranscriptAfterHold ?? null,
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // รายงานรายรับ — ไม่เคยมีเส้นทางไหนตอบคำถามนี้มาก่อน (0094)
  // นับเฉพาะเงินที่กระทบยอดแล้ว (reconciled) ผ่าน v_revenue_daily
  // ─────────────────────────────────────────────────────────────────
  async revenue(from?: string, to?: string) {
    const rows = await this.db.query<{ method: string; payment_count: string; amount: string }>(
      `select method, sum(payment_count) as payment_count, sum(amount) as amount
         from v_revenue_daily
        where institution_id = current_institution_id()
          and ($1::date is null or received_on >= $1::date)
          and ($2::date is null or received_on <= $2::date)
        group by method
        order by amount desc`,
      [from ?? null, to ?? null],
    );
    const total = rows.reduce((sum, r) => sum + Number(r.amount), 0);
    return {
      from: from ?? null,
      to: to ?? null,
      total,
      byMethod: rows.map((r) => ({ method: r.method, count: Number(r.payment_count), amount: Number(r.amount) })),
    };
  }

  // ─────────────────────────────────────────────────────────────────
  // โครงสร้างค่าธรรมเนียม — ไม่เคยมีเส้นทางสร้างเลยตั้งแต่ 0010 (0080)
  // ─────────────────────────────────────────────────────────────────
  async feeItems() {
    return this.db.query(
      `select id, code, name_th, kind, subsidised, refundable
         from fee_item order by kind, code`,
    );
  }

  async createFeeItem(dto: FeeItemDto) {
    return this.db.queryOne(
      `insert into fee_item (institution_id, code, name_th, kind, subsidised, refundable)
       values (current_institution_id(), $1, $2, $3::fee_item_kind, coalesce($4, false), coalesce($5, false))
       returning id, code, name_th, kind, subsidised, refundable`,
      [dto.code.trim(), dto.nameTh.trim(), dto.kind, dto.subsidised ?? null, dto.refundable ?? null],
    );
  }

  /** program_name/level_label ว่าง = "รวม" ตามที่หน้าจอต้องแสดง (0080) */
  async feeSchedules(academicYearId: string) {
    return this.db.query(
      `select fs.id, fs.level, fs.study_year, fs.program_id, p.name_th as program_name,
              fs.announcement_no, fs.announced_on, fs.active,
              count(fsl.id)::int as line_count
         from fee_schedule fs
         left join program p on p.id = fs.program_id
         left join fee_schedule_line fsl on fsl.fee_schedule_id = fs.id
        where fs.academic_year_id = $1
        group by fs.id, p.name_th
        order by fs.level nulls first, fs.study_year nulls first, p.name_th nulls first`,
      [academicYearId],
    );
  }

  async createFeeSchedule(dto: FeeScheduleDto) {
    return this.db.queryOne(
      `insert into fee_schedule
         (institution_id, academic_year_id, level, study_year, program_id, announcement_no, announced_on)
       values (current_institution_id(), $1, $2::qualification_level, $3, $4, $5, $6)
       returning id, level, study_year, program_id, announcement_no, announced_on, active`,
      [dto.academicYearId, dto.level ?? null, dto.studyYear ?? null, dto.programId ?? null,
       dto.announcementNo ?? null, dto.announcedOn ?? null],
    );
  }

  async feeScheduleLines(id: string) {
    return this.db.query(
      `select fsl.id, fsl.fee_item_id, fi.name_th as fee_item_name, fsl.term_ordinal, fsl.amount
         from fee_schedule_line fsl
         join fee_item fi on fi.id = fsl.fee_item_id
        where fsl.fee_schedule_id = $1
        order by fsl.term_ordinal, fi.code`,
      [id],
    );
  }

  /** ตั้งค่าทีละหลายรายการในคำขอเดียว — แก้ราคาซ้ำเดิมได้ ไม่สร้างรายการซ้อน */
  async setFeeScheduleLines(id: string, dto: SetFeeScheduleLinesDto) {
    return this.db.tx(async (c) => {
      for (const line of dto.lines) {
        await c.query(
          `insert into fee_schedule_line (fee_schedule_id, fee_item_id, term_ordinal, amount)
           values ($1, $2, $3, $4)
           on conflict (fee_schedule_id, fee_item_id, term_ordinal)
             do update set amount = excluded.amount`,
          [id, line.feeItemId, line.termOrdinal, line.amount],
        );
      }
      const rows = await c.query(
        `select fsl.id, fsl.fee_item_id, fi.name_th as fee_item_name, fsl.term_ordinal, fsl.amount
           from fee_schedule_line fsl
           join fee_item fi on fi.id = fsl.fee_item_id
          where fsl.fee_schedule_id = $1
          order by fsl.term_ordinal, fi.code`,
        [id],
      );
      return rows.rows;
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // ส่วนลด ทุน และแหล่งเงินภายนอก — ไม่เคยมีเส้นทางสร้างเลยตั้งแต่ 0010 (0080)
  // ─────────────────────────────────────────────────────────────────
  async fundingSources() {
    return this.db.query(
      `select id, kind, name_th, external_ref, active
         from funding_source order by kind, name_th`,
    );
  }

  async createFundingSource(dto: FundingSourceDto) {
    return this.db.queryOne(
      `insert into funding_source (institution_id, kind, name_th, external_ref)
       values (current_institution_id(), $1::funding_kind, $2, $3)
       returning id, kind, name_th, external_ref, active`,
      [dto.kind, dto.nameTh.trim(), dto.externalRef?.trim() ?? null],
    );
  }

  async studentFunding(studentId: string) {
    return this.db.query(
      `select sf.id, sf.funding_source_id, f.name_th as funding_name, f.kind,
              sf.academic_year_id, sf.term_id, sf.fee_item_id, fi.name_th as fee_item_name,
              sf.percent_off, sf.amount, sf.document_no, sf.note, sf.approved_at
         from student_funding sf
         join funding_source f on f.id = sf.funding_source_id
         left join fee_item fi on fi.id = sf.fee_item_id
        where sf.student_id = $1
        order by sf.approved_at desc nulls first`,
      [studentId],
    );
  }

  /**
   * มอบส่วนลด/ทุน — เฉพาะบทบาทระดับวิทยาลัยเรียกได้ (RLS บังคับซ้ำอีกชั้น)
   * การกระทำนี้เองคือการอนุมัติ จึงประทับ approved_by/approved_at ให้ทันที
   * ไม่มีขั้นรอตรวจแยกต่างหาก เพราะคนที่กดได้ต้องผ่าน @Roles มาแล้ว
   */
  async grantFunding(studentId: string, dto: StudentFundingDto) {
    if (dto.percentOff == null && dto.amount == null) {
      throw new BadRequestException('ต้องระบุเปอร์เซ็นต์หรือจำนวนเงินส่วนลดอย่างน้อยหนึ่งอย่าง');
    }
    return this.db.queryOne(
      `insert into student_funding
         (student_id, funding_source_id, academic_year_id, term_id, fee_item_id,
          percent_off, amount, approved_by, approved_at, document_no, note)
       values ($1, $2, $3, $4, $5, $6, $7, current_actor_id(), now(), $8, $9)
       returning id, funding_source_id, academic_year_id, term_id, fee_item_id,
                 percent_off, amount, document_no, note, approved_at`,
      [studentId, dto.fundingSourceId, dto.academicYearId, dto.termId ?? null, dto.feeItemId ?? null,
       dto.percentOff ?? null, dto.amount ?? null, dto.documentNo ?? null, dto.note ?? null],
    );
  }

  async revokeFunding(id: string) {
    const done = await this.db.query(
      `delete from student_funding where id = $1 returning id`, [id],
    );
    if (done.length === 0) throw new NotFoundException('ไม่พบรายการส่วนลดนี้ หรือถูกลบไปแล้ว');
    return { ok: true };
  }
}

@Roles('finance', 'director', 'admin')
@Controller('finance')
class FinanceController {
  constructor(private readonly svc: FinanceService) {}

  /*
   * ─── ทำไมเส้นทางกลุ่มนี้เปิดให้ 'registrar' ด้วย ทั้งที่ทั้งคอนโทรลเลอร์
   * จำกัดที่ finance ───
   * RLS ของ `invoice`/`invoice_line`/`fee_item`/`fee_schedule`/
   * `funding_source`/`student_funding` (0041 · 0080) เขียนไว้ชัดเจนแล้วว่า
   * registrar เขียนได้ — งานรับสมัครต้องตั้งค่าเทอมนักศึกษาใหม่ ให้ส่วนลด
   * และผูกทุนได้ทันทีตอนรับเข้า ไม่ต้องรอโอนงานไปให้การเงินทำแทน
   * ก่อนหน้านี้ @Roles ของคอนโทรลเลอร์แคบกว่าที่ฐานข้อมูลอนุญาตไว้แล้ว
   * ทำให้ registrar โดน 403 ทั้งที่ RLS ยอมอยู่แล้ว (รูปเดียวกับข้อ 14
   * ในบทเรียน — @Roles ที่แคบกว่าฐานข้อมูลจริง)
   * ส่วนรับชำระ/ใบเสร็จ/กระทบยอดธนาคารยังเป็นงานของฝ่ายการเงินล้วน
   * จึงไม่แตะ — คนละงานกับตอนรับสมัคร
   */
  @Roles('finance', 'registrar', 'director', 'admin')
  @Post('invoices')
  issue(@Body() dto: IssueInvoiceDto) {
    return this.svc.issueInvoice(dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('invoices')
  invoice(@Query('id') id: string) {
    return this.svc.getInvoice(id);
  }

  @Post('payments')
  pay(@Body() dto: PaymentDto) {
    return this.svc.recordPayment(dto);
  }

  /*
   * ─── ใบเสร็จยังเป็นของฝ่ายการเงินล้วน ไม่ขยายให้ registrar ───
   * ต่างจากใบแจ้งหนี้/ส่วนลด/ทุนด้านบน — API-194 ยืนยันไว้แล้วว่างานทะเบียน
   * ออกใบ รบ. ได้แต่ไม่ใช่คนรับเงิน การเปิดใบเสร็จ (หลักฐานว่า "รับเงินแล้ว")
   * เป็นคนละงานกับการตั้งยอดที่ต้องเก็บ (invoice) — ตั้งใจแยกไว้
   */
  @Get('receipts')
  receipts(@Query('studentId', ParseUuidPipe) studentId: string) {
    return this.svc.receipts(studentId);
  }

  /**
   * คืน HTML พร้อมพิมพ์ ไม่ใช่ JSON — และติด `@Audit` เหมือนการพิมพ์เอกสาร
   * ชนิดอื่น เพราะ "ใครพิมพ์ใบเสร็จของใครเมื่อไร" เป็นคำถามที่ต้องตอบได้
   * เวลามีใบเสร็จลอยอยู่หลายใบ
   */
  @Audit('issued_document', 'id')
  @Header('content-type', 'text/html; charset=utf-8')
  @Get('receipts/:id/print')
  printReceipt(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.printReceipt(id);
  }

  @Post('bank-transactions')
  importBank(@Body() dto: ImportBankDto) {
    return this.svc.importBankTransactions(dto);
  }

  @Post('reconcile')
  reconcile() {
    return this.svc.reconcile();
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('reconcile/pending')
  pending() {
    return this.svc.pendingMatches();
  }

  @Audit('bank_transaction', 'id')
  @Post('reconcile/:id/confirm')
  confirmMatch(@Param('id', ParseUuidPipe) id: string, @Body() dto: ConfirmMatchDto) {
    return this.svc.confirmMatch(id, dto.studentId);
  }

  @Audit('bank_transaction', 'id')
  @Post('reconcile/:id/ignore')
  ignoreMatch(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.ignoreMatch(id);
  }

  @Post('holds/refresh')
  holds() {
    return this.svc.refreshHolds();
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('ar-aging')
  aging() {
    return this.svc.aging();
  }

  @Roles('finance', 'director', 'admin')
  @Get('late-policy')
  latePolicy() {
    return this.svc.latePolicy();
  }

  @Roles('finance', 'director', 'admin')
  @Audit('late_fee_policy')
  @Post('late-policy')
  setLatePolicy(@Body() dto: LateFeePolicyDto) {
    return this.svc.setLatePolicy(dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('revenue')
  revenue(@Query('from') from?: string, @Query('to') to?: string) {
    return this.svc.revenue(from, to);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('fee-items')
  feeItems() {
    return this.svc.feeItems();
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('fee_item')
  @Post('fee-items')
  createFeeItem(@Body() dto: FeeItemDto) {
    return this.svc.createFeeItem(dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('fee-schedules')
  feeSchedules(@Query('academicYearId', ParseUuidPipe) academicYearId: string) {
    return this.svc.feeSchedules(academicYearId);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('fee_schedule')
  @Post('fee-schedules')
  createFeeSchedule(@Body() dto: FeeScheduleDto) {
    return this.svc.createFeeSchedule(dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('fee-schedules/:id/lines')
  feeScheduleLines(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.feeScheduleLines(id);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('fee_schedule', 'id')
  @Post('fee-schedules/:id/lines')
  setFeeScheduleLines(@Param('id', ParseUuidPipe) id: string, @Body() dto: SetFeeScheduleLinesDto) {
    return this.svc.setFeeScheduleLines(id, dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('funding-sources')
  fundingSources() {
    return this.svc.fundingSources();
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('funding_source')
  @Post('funding-sources')
  createFundingSource(@Body() dto: FundingSourceDto) {
    return this.svc.createFundingSource(dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Get('students/:id/funding')
  studentFunding(@Param('id', ParseUuidPipe) id: string) {
    return this.svc.studentFunding(id);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('student_funding', 'id')
  @Post('students/:id/funding')
  grantFunding(@Param('id', ParseUuidPipe) id: string, @Body() dto: StudentFundingDto) {
    return this.svc.grantFunding(id, dto);
  }

  @Roles('finance', 'registrar', 'director', 'admin')
  @Audit('student_funding', 'fundingId')
  @Delete('students/:id/funding/:fundingId')
  revokeFunding(@Param('fundingId', ParseUuidPipe) fundingId: string) {
    return this.svc.revokeFunding(fundingId);
  }
}

@Module({
  controllers: [FinanceController],
  providers: [FinanceService],
  exports: [FinanceService],
})
export class FinanceModule {}

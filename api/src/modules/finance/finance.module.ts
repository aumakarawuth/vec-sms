import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
  Query,
} from '@nestjs/common';
import { ArrayNotEmpty, IsArray, IsIn, IsISO8601, IsInt, IsNumber, IsOptional, IsString, Max, Min, ValidateNested } from 'class-validator';
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
              i.invoice_no, s.student_code,
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
}

@Roles('finance', 'director', 'admin')
@Controller('finance')
class FinanceController {
  constructor(private readonly svc: FinanceService) {}

  @Post('invoices')
  issue(@Body() dto: IssueInvoiceDto) {
    return this.svc.issueInvoice(dto);
  }

  @Get('invoices')
  invoice(@Query('id') id: string) {
    return this.svc.getInvoice(id);
  }

  @Post('payments')
  pay(@Body() dto: PaymentDto) {
    return this.svc.recordPayment(dto);
  }

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

  @Get('reconcile/pending')
  pending() {
    return this.svc.pendingMatches();
  }

  @Post('holds/refresh')
  holds() {
    return this.svc.refreshHolds();
  }

  @Get('ar-aging')
  aging() {
    return this.svc.aging();
  }
}

@Module({
  controllers: [FinanceController],
  providers: [FinanceService],
  exports: [FinanceService],
})
export class FinanceModule {}

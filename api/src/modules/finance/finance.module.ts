import {
  Body,
  Controller,
  Get,
  Injectable,
  Module,
  Post,
  Query,
} from '@nestjs/common';
import { ArrayNotEmpty, IsArray, IsIn, IsISO8601, IsInt, IsNumber, IsOptional, IsString, Max, Min, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid } from '../../common/validation/uuid';

const METHODS = [
  'cash', 'bank_transfer', 'promptpay', 'credit_card', 'counter_service',
  'direct_debit', 'gov_subsidy', 'student_loan', 'scholarship', 'adjustment',
] as const;

class IssueInvoiceDto {
  @IsUuid() studentId: string;
  @IsUuid() termId: string;
  @IsOptional() @IsInt() @Min(1) @Max(6) installments?: number;
}

class PaymentDto {
  @IsUuid() studentId: string;
  @IsNumber() @Min(0.01) amount: number;
  @IsIn(METHODS as unknown as string[]) method: string;
  @IsOptional() @IsISO8601() receivedOn?: string;
  @IsOptional() @IsString() receiptNo?: string;
  @IsOptional() @IsString() bankRef?: string;
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
           (institution_id, student_id, received_on, amount, method, receipt_no, bank_ref, received_by)
         select s.institution_id, s.id, coalesce($2::date, current_date), $3, $4::payment_method,
                $5, $6, current_actor_id()
           from student s where s.id = $1
         returning id`,
        [
          dto.studentId, dto.receivedOn ?? null, dto.amount,
          dto.method, dto.receiptNo ?? null, dto.bankRef ?? null,
        ],
      );

      const paymentId = pay.rows[0].id;
      const left = await c.query<{ remaining: string }>(
        `select post_payment($1) as remaining`,
        [paymentId],
      );

      const balance = await c.query(
        `select outstanding, next_due_on, days_overdue
           from v_student_balance where student_id = $1`,
        [dto.studentId],
      );

      return {
        paymentId,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import 'async_view.dart';

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key, required this.session});
  final Session session;

  Future<Fetched<List<Invoice>>> _load() async {
    final r =
        await session.api.getCached('/students/${session.studentId}/invoices');
    return Fetched(
      (r.data as List)
          .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
          .toList(),
      fromCache: r.fromCache,
      cachedAt: r.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<Invoice>>(
        load: _load,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        builder: (context, invoices) =>
            _FinanceBody(invoice: invoices.isEmpty ? null : invoices.first),
      );
}

class _FinanceBody extends StatelessWidget {
  const _FinanceBody({required this.invoice});
  final Invoice? invoice;

  @override
  Widget build(BuildContext context) {
    final due = invoice?.nextDue;
    final amount = due?.remaining ?? 3500;
    final installments = invoice?.installments;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Spacer(),
        const Text('การเงินของฉัน',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const Spacer(),
        Icon(Icons.receipt_long_outlined, color: context.c.ink2)
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFFFF0F2), Color(0xFFFFE4E8)]),
            borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('ยอดที่ต้องชำระ:',
                    style: TextStyle(
                        color: Color(0xFFD92F4B), fontWeight: FontWeight.w700)),
                Text(Fmt.money(amount),
                    style: const TextStyle(
                        color: Color(0xFFC91435),
                        fontSize: 30,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text('กำหนดชำระภายใน',
                    style: TextStyle(color: Color(0xFFD94B62), fontSize: 12)),
                Row(children: [
                  const Icon(Icons.calendar_month, size: 17),
                  const SizedBox(width: 5),
                  Text(
                      due?.dueOn == null
                          ? '31 พ.ค. 2567'
                          : Fmt.dateShort(due!.dueOn!),
                      style: const TextStyle(fontWeight: FontWeight.w700))
                ])
              ])),
          const Icon(Icons.account_balance_wallet_rounded,
              size: 58, color: Color(0xFFE85870))
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFEAF3FF), Color(0xFFF3F7FF)]),
            borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('ชำระผ่าน PromptPay',
                    style: TextStyle(
                        color: Color(0xFF315DD5), fontWeight: FontWeight.w700)),
                const Text('สแกน QR หรือโอนเข้าบัญชี',
                    style: TextStyle(fontSize: 12, color: Color(0xFF68738D))),
                const SizedBox(height: 8),
                const Text('เลขอ้างอิง 1',
                    style: TextStyle(fontSize: 10, color: Color(0xFF68738D))),
                Text(invoice?.ref1 ?? '6730201001',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                if (invoice?.ref2 != null) ...[
                  const Text('เลขอ้างอิง 2',
                      style: TextStyle(fontSize: 10, color: Color(0xFF68738D))),
                  Text(invoice!.ref2!,
                      style: const TextStyle(fontWeight: FontWeight.w700))
                ]
              ])),
          Column(children: [
            const Icon(Icons.qr_code_2_rounded,
                size: 44, color: Color(0xFF315DD5)),
            TextButton(
                onPressed: () => Clipboard.setData(
                    ClipboardData(text: invoice?.ref1 ?? '6730201001')),
                child: const Text('คัดลอก'))
          ])
        ]),
      ),
      const SizedBox(height: 14),
      const Text('รายการแบ่งชำระ',
          style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (installments == null || installments.isEmpty) ...const [
        _Installment(1, 1750, '31 พ.ค. 2567', false, true),
        _Installment(2, 1750, '30 มิ.ย. 2567', false, false),
        _Installment(3, 1750, '31 ก.ค. 2567', false, false),
        _Installment(4, 1750, '30 เม.ย. 2567', true, false),
      ] else
        for (final item in installments)
          _Installment(
              item.seq,
              item.remaining > 0 ? item.remaining : item.amount,
              item.dueOn == null ? '—' : Fmt.dateShort(item.dueOn!),
              item.isPaid,
              due?.seq == item.seq),
    ]);
  }
}

class _Installment extends StatelessWidget {
  const _Installment(
      this.number, this.amount, this.date, this.paid, this.primary);
  final int number;
  final num amount;
  final String date;
  final bool paid, primary;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: context.c.sunk,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color(0x100F0D2A), blurRadius: 8)
            ]),
        child: Row(children: [
          CircleAvatar(
              radius: 13,
              backgroundColor: paid
                  ? context.c.ok
                  : (primary ? context.c.sel : const Color(0xFFE8E9EF)),
              child: paid
                  ? const Icon(Icons.check, color: Colors.white, size: 17)
                  : Text('$number',
                      style: TextStyle(
                          color: primary ? Colors.white : context.c.ink2,
                          fontSize: 12,
                          fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Text('งวดที่ $number',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(Fmt.money(amount),
                      style: const TextStyle(fontWeight: FontWeight.w600))
                ]),
                Text(date,
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF77758A)))
              ])),
          const SizedBox(width: 8),
          Text(paid ? 'จ่ายแล้ว' : (primary ? 'ยังไม่ชำระ' : 'รอชำระ'),
              style: TextStyle(
                  fontSize: 10,
                  color: paid
                      ? context.c.ok
                      : (primary ? context.c.crit : context.c.sel)))
        ]),
      );
}

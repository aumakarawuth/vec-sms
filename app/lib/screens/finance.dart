import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'async_view.dart';

/// หน้าจอ A-04 — การเงิน
class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key, required this.session});
  final Session session;

  Future<Fetched<List<Invoice>>> _load() async {
    final r = await session.api.getCached('/students/${session.studentId}/invoices');
    return Fetched(
      (r.data as List).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList(),
      fromCache: r.fromCache,
      cachedAt: r.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<List<Invoice>>(
      load: _load,
      builder: (context, invoices) {
        final open = invoices.where((i) => i.outstanding > 0).toList();

        if (open.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Gap.sm),
              const ScreenHeader(kicker: 'การเงิน', title: 'ไม่มียอดค้างชำระ'),
              const SizedBox(height: Gap.lg),
              const StatusDot('ชำระครบทุกใบแจ้งหนี้แล้ว', tone: Tone.ok),
              if (invoices.isNotEmpty) ...[
                const SizedBox(height: Gap.xl),
                GroupHeader('ประวัติ ${invoices.length} ใบ'),
                const SizedBox(height: Gap.md),
                for (final inv in invoices)
                  InfoRow(inv.invoiceNo, value: Fmt.money(inv.total)),
              ],
            ],
          );
        }

        final inv = open.first;
        final due = inv.nextDue;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.sm),
            ScreenHeader(
              kicker: due?.dueOn != null
                  ? 'งวดที่ ${due!.seq} · ครบกำหนด ${Fmt.dateShort(due.dueOn!)}'
                  : 'ยอดค้างชำระ',
              title: '',
            ),
            Figure(
              Fmt.money(due?.remaining ?? inv.outstanding),
              tone: (due?.isOverdue ?? false) ? Tone.crit : Tone.warn,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'ยอดค้างทั้งใบ ${Fmt.money(inv.outstanding)} จาก ${Fmt.money(inv.total)}',
              style: t.bodySmall,
            ),

            const SizedBox(height: Gap.xl),
            const GroupHeader('ชำระผ่านพร้อมเพย์'),
            const SizedBox(height: Gap.md),
            _PaymentRefs(invoice: inv),

            const SizedBox(height: Gap.xl),
            GroupHeader('งวดผ่อนชำระ ${inv.installments.length} งวด'),
            const SizedBox(height: Gap.sm),
            for (final n in inv.installments)
              InfoRow(
                'งวดที่ ${n.seq} · ${n.dueOn != null ? Fmt.dateShort(n.dueOn!) : '—'}',
                trailing: n.isPaid
                    ? const StatusDot('จ่ายแล้ว', tone: Tone.ok)
                    : Text(
                        Fmt.money(n.remaining),
                        style: t.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: n.isOverdue ? context.c.crit : context.c.ink,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),

            const SizedBox(height: Gap.xl),
            Text(
              'นำเลขอ้างอิงไปกรอกในแอปธนาคาร หัวข้อจ่ายบิล '
              'ยอดจะตัดอัตโนมัติภายในไม่กี่นาทีหลังโอน',
              style: t.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

/// เลขอ้างอิงสำหรับ PromptPay Bill Payment
///
/// แอปไม่ได้สร้างภาพ QR เอง เพราะรหัสผู้รับชำระ (Biller ID) ออกโดยธนาคาร
/// และตัวเลข checksum ของ EMVCo ต้องสร้างฝั่งเซิร์ฟเวอร์ให้ตรงกับที่ธนาคารรับ
/// การเดาเองมีโอกาสได้ QR ที่สแกนแล้วเงินไปผิดบัญชี ซึ่งแก้ยากกว่ามาก
class _PaymentRefs extends StatelessWidget {
  const _PaymentRefs({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RefRow(label: 'เลขอ้างอิง 1 (รหัสนักศึกษา)', value: invoice.ref1),
        _RefRow(label: 'เลขอ้างอิง 2 (เลขที่ใบแจ้งหนี้)', value: invoice.ref2),
        _RefRow(label: 'เลขที่ใบแจ้งหนี้', value: invoice.invoiceNo),
      ],
    );
  }
}

class _RefRow extends StatelessWidget {
  const _RefRow({required this.label, required this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          const SizedBox(width: Gap.md),
          Text(
            value ?? '—',
            style: t.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: Gap.md),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('คัดลอก $value แล้ว'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text('คัดลอก',
                  style: t.bodySmall?.copyWith(color: context.c.sel)),
            ),
          ],
        ],
      ),
    );
  }
}

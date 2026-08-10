import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';
import 'async_view.dart';

/// A-06 โหมดฝึกอาชีพ
///
/// ─── ทำไมเป็นหน้าอ่านอย่างเดียว ───
/// ชั่วโมงฝึกอาชีพเป็นหนึ่งในกฎการจบ (`practicum_hours`) และนับเฉพาะรายการ
/// ที่ครูนิเทศรับรองแล้ว ถ้านักศึกษาบันทึกชั่วโมงเองได้ กฎข้อนั้นจะกลายเป็น
/// ตัวเลขที่เจ้าตัวกรอกเอง — ซึ่งเป็นรูปแบบเดียวกับที่ 0041 เพิ่งปิดไป
/// (นักศึกษาให้คะแนนตัวเอง) migration 0045 จึงปิดการเขียน practicum_log
/// ไว้ที่ฐานข้อมูลด้วย ไม่ใช่แค่ไม่มีปุ่มในแอป
///
/// สิ่งที่นักศึกษาต้องรู้จากหน้านี้คือ "อีกกี่ชั่วโมงถึงจะครบ" และ
/// "อันไหนที่ครูยังไม่รับรอง" ซึ่งเป็นสองคำถามที่ทำให้ต้องไปตามครู
class PracticumScreen extends StatelessWidget {
  const PracticumScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<Map<String, dynamic>>(
      load: () async {
        final data = await session.api
            .getCached('/practicum/students/${session.studentId}');
        return Fetched(
          Map<String, dynamic>.from(data.data as Map),
          fromCache: data.fromCache,
          cachedAt: data.cachedAt,
        );
      },
      builder: (context, data) {
        final rows = (data['logs'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final verified = Fmt.toNum(data['verified_hours']) ?? 0;
        final pending = Fmt.toNum(data['pending_hours']) ?? 0;
        final required = Fmt.toNum(data['required_hours']);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenHeader(
              kicker: 'ฝึกอาชีพ',
              title: 'ชั่วโมงฝึกอาชีพ',
              subtitle: 'นับเฉพาะชั่วโมงที่ครูนิเทศรับรองแล้ว',
            ),
            const SizedBox(height: Gap.xl),
            Row(
              children: [
                Expanded(
                  child: Figure(
                    Fmt.count(verified),
                    caption: 'ชั่วโมงที่รับรองแล้ว',
                    tone: required != null && verified >= required
                        ? Tone.ok
                        : Tone.neutral,
                  ),
                ),
                if (pending > 0)
                  Expanded(
                    child: Figure(
                      Fmt.count(pending),
                      caption: 'รอครูรับรอง',
                      tone: Tone.warn,
                      small: true,
                    ),
                  ),
              ],
            ),
            if (required != null && required > 0) ...[
              const SizedBox(height: Gap.lg),
              Meter(
                // Meter รับค่า 0..1 ไม่ใช่ค่าดิบกับเพดาน
                value: (verified / required).clamp(0, 1).toDouble(),
                tone: verified >= required ? Tone.ok : Tone.neutral,
                label: 'ความคืบหน้าเทียบเกณฑ์ ${Fmt.count(required)} ชั่วโมง',
              ),
              if (verified < required) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  'เหลืออีก ${Fmt.count(required - verified)} ชั่วโมง',
                  style: t.bodyMedium,
                ),
              ],
            ],
            if (pending > 0) ...[
              const SizedBox(height: Gap.xl),
              const Notice(
                title: 'มีชั่วโมงที่ครูยังไม่รับรอง',
                body: 'ชั่วโมงที่รอรับรองยังไม่ถูกนับในเกณฑ์การจบ '
                    'ถ้ารอนานผิดปกติให้ติดต่อครูนิเทศ',
                tone: Tone.warn,
              ),
            ],
            const SizedBox(height: Gap.xl),
            const GroupHeader('บันทึกการฝึก'),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.lg),
                child: Text('ยังไม่มีบันทึกการฝึกอาชีพ', style: t.bodyMedium),
              ),
            for (final r in rows) ...[
              Divider(height: 1, color: context.c.rule),
              InfoRow(
                '${Fmt.dateShortOf(r['worked_on'])} · ${Fmt.count(r['hours'])} ชม.',
                value: r['verified_at'] != null ? 'รับรองแล้ว' : 'รอรับรอง',
                tone: r['verified_at'] != null ? Tone.ok : Tone.warn,
              ),
            ],
            Divider(height: 1, color: context.c.rule),
            const SizedBox(height: Gap.xl),
            Text(
              'บันทึกและการรับรองทำโดยครูนิเทศ นักศึกษาแก้ไขเองไม่ได้ — '
              'ชั่วโมงฝึกอาชีพเป็นเกณฑ์การจบ ตัวเลขที่เจ้าตัวกรอกเองใช้ไม่ได้',
              style: t.labelSmall,
            ),
          ],
        );
      },
    );
  }
}

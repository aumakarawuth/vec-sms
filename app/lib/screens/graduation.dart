import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'async_view.dart';

/// หน้าจอ A-03 — เส้นทางสู่การจบ
///
/// แก้ปัญหาที่นักศึกษาอาชีวะจำนวนมากรู้ตัวว่าขาดอะไรตอนปีสุดท้าย
/// โดยเฉพาะกิจกรรมเสริมหลักสูตรที่ต้องผ่านทุกภาคเรียน ซึ่งเป็นสาเหตุ
/// ที่ทำให้ไม่จบทั้งที่หน่วยกิตครบแล้ว
class GraduationScreen extends StatelessWidget {
  const GraduationScreen({super.key, required this.session});
  final Session session;

  Future<Fetched<List<GraduationRule>>> _load() async {
    final r = await session.api.getCached('/students/${session.studentId}/graduation');
    return Fetched(
      (r.data as List)
          .map((e) => GraduationRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      fromCache: r.fromCache,
      cachedAt: r.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<List<GraduationRule>>(
      load: _load,
      builder: (context, rules) {
        final credits = rules.where((r) => r.kind == 'credits_total').firstOrNull;
        final gpax = rules.where((r) => r.kind == 'gpax_min').firstOrNull;
        final done = rules.where((r) => r.satisfied).length;
        final blocking = rules.where((r) => r.blocking).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.sm),
            ScreenHeader(
              kicker: session.programName,
              title: 'เส้นทางสู่การจบ',
              subtitle: 'ผ่านแล้ว $done จาก ${rules.length} เงื่อนไข',
            ),

            const SizedBox(height: Gap.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (credits != null)
                  Expanded(
                    child: Figure(
                      Fmt.count(credits.achieved),
                      small: true,
                      caption: 'จาก ${Fmt.count(credits.required)} หน่วยกิต',
                    ),
                  ),
                if (gpax != null)
                  Expanded(
                    child: Figure(
                      gpax.achieved.toStringAsFixed(2),
                      small: true,
                      tone: gpax.satisfied ? Tone.ok : Tone.warn,
                      caption: 'GPAX ปัจจุบัน',
                    ),
                  ),
              ],
            ),

            if (credits != null) ...[
              const SizedBox(height: Gap.lg),
              Meter(
                label: 'หน่วยกิตสะสม',
                value: credits.progress,
                tone: Tone.neutral,
              ),
            ],

            const SizedBox(height: Gap.xl),
            GroupHeader('เงื่อนไขจบ ${blocking.length} ข้อ'),
            const SizedBox(height: Gap.sm),
            for (final r in rules)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(r.name, style: t.bodyMedium)),
                    const SizedBox(width: Gap.md),
                    _RuleStatus(rule: r),
                  ],
                ),
              ),

            const SizedBox(height: Gap.xl),
            Text(
              'เงื่อนไขที่ยังไม่ผ่านไม่ได้แปลว่าจบไม่ได้ '
              'บางข้อประเมินในชั้นปีสุดท้าย เช่น มาตรฐานวิชาชีพและการฝึกประสบการณ์',
              style: t.bodySmall,
            ),
          ],
        );
      },
    );
  }
}

class _RuleStatus extends StatelessWidget {
  const _RuleStatus({required this.rule});
  final GraduationRule rule;

  @override
  Widget build(BuildContext context) {
    if (rule.satisfied) return const StatusDot('ผ่าน', tone: Tone.ok);

    // กฎแบบนับถอยหลัง ค่าที่ได้คือ "จำนวนที่ยังค้าง" ยิ่งน้อยยิ่งดี
    if (rule.isCountdown) {
      final n = rule.achieved.toInt();
      return StatusDot('ค้าง $n', tone: n > 0 ? Tone.warn : Tone.ok);
    }

    if (rule.achieved <= 0) {
      return const StatusDot('ยังไม่ถึงเวลา', tone: Tone.neutral);
    }

    return StatusDot(
      '${(rule.progress * 100).toStringAsFixed(0)}%',
      tone: Tone.info,
    );
  }
}

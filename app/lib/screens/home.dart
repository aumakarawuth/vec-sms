import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'async_view.dart';

/// หน้าจอ A-01 — เรียงตามสิ่งที่ต้องทำวันนี้ ไม่ใช่ตามโมดูลของระบบ
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session, this.onOpenTab});

  final Session session;
  final void Function(int index)? onOpenTab;

  Future<Fetched<_HomeData>> _load() async {
    final sid = session.studentId!;
    final today = DateTime.now();
    final date =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final schedule = await session.api.getCached('/students/$sid/schedule?date=$date');
    final attendance =
        await session.api.getCached('/students/$sid/attendance?termId=${session.termId}');
    final balance = await session.api.getCached('/students/$sid/balance');

    return Fetched(
      _HomeData(
        periods: (schedule.data as List)
            .map((e) => Period.fromJson(e as Map<String, dynamic>))
            .toList(),
        courses: (attendance.data as List)
            .map((e) => CourseAttendance.fromJson(e as Map<String, dynamic>))
            .toList(),
        balance: Balance.fromJson(balance.data as Map<String, dynamic>),
      ),
      fromCache: schedule.fromCache || attendance.fromCache || balance.fromCache,
      cachedAt: schedule.cachedAt ?? attendance.cachedAt ?? balance.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<_HomeData>(
      load: _load,
      builder: (context, d) {
        final worst = d.worstCourse;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.sm),
            ScreenHeader(
              kicker: Fmt.dateWithWeekday(DateTime.now()),
              title: 'สวัสดี ${session.displayName ?? ''}'.trim(),
              subtitle: [session.programName, session.studentCode]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' · '),
            ),

            // เตือนเรื่องเวลาเรียนก่อนอย่างอื่น เพราะเป็นสิ่งเดียวที่ทำให้
            // นักศึกษาหมดสิทธิ์สอบโดยไม่รู้ตัว
            if (worst != null && worst.state != AttendanceState.ok) ...[
              const SizedBox(height: Gap.xl),
              Notice(
                title: '${worst.name} เวลาเรียน ${Fmt.percent(worst.pctProjected)}',
                body: worst.absencesLeft > 0
                    ? 'ขาดอีก ${worst.absencesLeft} คาบจะหมดสิทธิ์สอบวิชานี้'
                    : 'ต่ำกว่าเกณฑ์ ${worst.minPct.toStringAsFixed(0)}% แล้ว',
                tone: toneOfAttendance(worst.state),
              ),
            ],

            const SizedBox(height: Gap.xl),
            GroupHeader(
              d.periods.isEmpty ? 'วันนี้ไม่มีคาบเรียน' : 'คาบเรียนวันนี้',
              trailing: d.periods.isEmpty
                  ? null
                  : Text('${d.periods.length} คาบ', style: t.bodySmall),
            ),
            const SizedBox(height: Gap.md),
            if (d.periods.isEmpty)
              Text('ตรวจสอบตารางเรียนได้ที่แท็บตาราง', style: t.bodyMedium)
            else
              for (final p in d.periods) _PeriodRow(period: p),

            const SizedBox(height: Gap.xl),
            GroupHeader(
              'การเงิน',
              trailing: GestureDetector(
                onTap: () => onOpenTab?.call(3),
                child: Text('ดูรายละเอียด',
                    style: t.bodySmall?.copyWith(color: context.c.ink2)),
              ),
            ),
            const SizedBox(height: Gap.md),
            if (d.balance.outstanding <= 0)
              const StatusDot('ชำระครบแล้ว', tone: Tone.ok)
            else
              Figure(
                Fmt.money(d.balance.outstanding),
                tone: d.balance.isOverdue ? Tone.crit : Tone.warn,
                small: true,
                caption: d.balance.isOverdue
                    ? 'เกินกำหนดชำระ ${d.balance.daysOverdue} วัน'
                    : d.balance.nextDueOn != null
                        ? 'ครบกำหนด ${Fmt.dateShort(d.balance.nextDueOn!)}'
                        : null,
              ),
          ],
        );
      },
    );
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.period});
  final Period period;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(period.periodLabel,
                style: t.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(period.courseName,
                    style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                Text(
                  [period.room, period.teacherName]
                      .where((e) => e != null && e.isNotEmpty)
                      .join(' · '),
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeData {
  _HomeData({required this.periods, required this.courses, required this.balance});
  final List<Period> periods;
  final List<CourseAttendance> courses;
  final Balance balance;

  /// วิชาที่เวลาเรียนต่ำที่สุด — ตัวที่ต้องเตือนก่อน
  CourseAttendance? get worstCourse {
    if (courses.isEmpty) return null;
    final sorted = [...courses]
      ..sort((a, b) => a.pctProjected.compareTo(b.pctProjected));
    return sorted.first;
  }
}

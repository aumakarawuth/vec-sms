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

    final schedule =
        await session.api.getCached('/students/$sid/schedule?date=$date');
    final attendance = await session.api
        .getCached('/students/$sid/attendance?termId=${session.termId}');
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
      fromCache:
          schedule.fromCache || attendance.fromCache || balance.fromCache,
      cachedAt: schedule.cachedAt ?? attendance.cachedAt ?? balance.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<_HomeData>(
      load: _load,
      padding: EdgeInsets.zero,
      builder: (context, d) {
        final worst = d.worstCourse;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroHeader(
              name: session.displayName ?? 'นักศึกษา',
              subtitle: [session.programName, session.studentCode]
                  .where((e) => e != null && e.isNotEmpty)
                  .join(' · '),
            ),
            Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -24),
                        child: _OverviewCard(
                          periodCount: d.periods.isEmpty ? 4 : d.periods.length,
                          attendance: d.periods.isEmpty
                              ? 82
                              : (worst?.pctProjected ?? 82),
                          absencesLeft: d.periods.isEmpty
                              ? 2
                              : (worst?.absencesLeft ?? 2),
                          mock: d.periods.isEmpty || worst == null,
                        ),
                      ),
                      const GroupHeader('คาบเรียนวันนี้'),
                      if (d.periods.isEmpty)
                        const Column(children: [
                          _MockPeriodRow(
                              time: '08:30\n10:20',
                              course: 'การบัญชีเบื้องต้น 1',
                              detail: 'อ.กมลวรรณ · อาคาร 2 ห้อง 2102',
                              icon: Icons.menu_book_rounded),
                          _MockPeriodRow(
                              time: '10:30\n12:20',
                              course: 'การตลาดดิจิทัล',
                              detail: 'อ.ชานนท์ · อาคาร 3 ห้อง 3305',
                              icon: Icons.campaign_rounded),
                          _MockPeriodRow(
                              time: '13:00\n14:50',
                              course: 'ภาษาอังกฤษเพื่ออาชีพ',
                              detail: 'อ.ณัฐธิดา · อาคาร 1 ห้อง 1103',
                              icon: Icons.translate_rounded),
                          _MockPeriodRow(
                              time: '15:00\n16:50',
                              course: 'คอมพิวเตอร์ธุรกิจ',
                              detail: 'อ.วีรพล · อาคาร 4 ห้อง 4401',
                              icon: Icons.desktop_windows_rounded),
                        ])
                      else
                        for (final p in d.periods) _PeriodRow(period: p),
                    ])),
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
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: context.c.sunk, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFFEDEAFF),
                borderRadius: BorderRadius.circular(15)),
            child: Text(period.periodLabel,
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(
                    color: context.c.sel,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 12),
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

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.name, required this.subtitle});
  final String name, subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 54),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF7664EA), Color(0xFF5B4CD2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
          bottom: false,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('สวัสดีตอนเช้า',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .72),
                            fontSize: 12))
                  ])),
              Container(
                  width: 72,
                  height: 72,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3)),
                  child: Image.asset('assets/images/student-avatar.png',
                      fit: BoxFit.cover)),
            ]),
          ])),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard(
      {required this.periodCount,
      required this.attendance,
      required this.absencesLeft,
      required this.mock});
  final int periodCount, absencesLeft;
  final num attendance;
  final bool mock;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
            color: context.c.sunk,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x160F0D2A),
                  blurRadius: 20,
                  offset: Offset(0, 7))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('ภาพรวมวันนี้',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            if (mock) const MockBadge()
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
                child: _OverviewTile(
                    icon: Icons.calendar_month_rounded,
                    value: '$periodCount',
                    label: 'วิชาวันนี้',
                    bg: const Color(0xFFF1F0FF),
                    color: const Color(0xFF6657E8))),
            const SizedBox(width: 8),
            Expanded(
                child: _OverviewTile(
                    icon: Icons.schedule_rounded,
                    value: Fmt.percent(attendance),
                    label: 'เวลาเรียนต่ำสุด',
                    bg: const Color(0xFFE8F8F0),
                    color: const Color(0xFF28A66F))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _OverviewTile(
                    icon: Icons.warning_amber_rounded,
                    value: 'ใกล้ครบเวลา',
                    label: 'เหลือ $absencesLeft ครั้ง',
                    bg: const Color(0xFFFFF2D5),
                    color: const Color(0xFFE49A28))),
            const SizedBox(width: 8),
            const Expanded(
                child: _OverviewTile(
                    icon: Icons.notifications_none_rounded,
                    value: 'ประกาศ',
                    label: '2 รายการใหม่',
                    bg: Color(0xFFE8F2FF),
                    color: Color(0xFF5984E8))),
          ]),
        ]),
      );
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile(
      {required this.icon,
      required this.value,
      required this.label,
      required this.bg,
      required this.color});
  final IconData icon;
  final String value, label;
  final Color bg, color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall)
              ]))
        ]),
      );
}

class _MockPeriodRow extends StatelessWidget {
  const _MockPeriodRow(
      {required this.time,
      required this.course,
      required this.detail,
      required this.icon});
  final String time, course, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
            color: context.c.sunk,
            border: Border(left: BorderSide(color: context.c.sel, width: 3)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(color: Color(0x0D0F0D2A), blurRadius: 10)
            ]),
        child: Row(children: [
          SizedBox(
              width: 47,
              child: Text(time,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.c.sel, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(course,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(detail, style: Theme.of(context).textTheme.labelSmall)
              ])),
          Icon(icon, color: context.c.sel, size: 27)
        ]),
      );
}

class _HomeData {
  _HomeData(
      {required this.periods, required this.courses, required this.balance});
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

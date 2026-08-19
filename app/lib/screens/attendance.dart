import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'async_view.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key, required this.session});
  final Session session;

  Future<Fetched<List<CourseAttendance>>> _load() async {
    final r = await session.api.getCached(
        '/students/${session.studentId}/attendance?termId=${session.termId}');
    return Fetched(
      (r.data as List)
          .map((e) => CourseAttendance.fromJson(e as Map<String, dynamic>))
          .toList(),
      fromCache: r.fromCache,
      cachedAt: r.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<CourseAttendance>>(
        load: _load,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        builder: (context, value) {
          final courses = [...value]
            ..sort((a, b) => a.pctProjected.compareTo(b.pctProjected));
          return _AttendanceBody(courses: courses);
        },
      );
}

class _AttendanceBody extends StatelessWidget {
  const _AttendanceBody({required this.courses});
  final List<CourseAttendance> courses;

  @override
  Widget build(BuildContext context) {
    final worst = courses.isEmpty ? null : courses.first;
    final pct = worst?.pctProjected ?? 82;
    final below = worst != null && pct < worst.minPct;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PageTitle('เวลาเรียนของฉัน', Icons.calendar_month_outlined),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: const Color(0xFFF0EFFF),
                borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              RingProgress(
                  value: pct / 100,
                  center: Fmt.percent(pct),
                  caption: 'เวลาเรียนรวม',
                  size: 126),
              const SizedBox(width: 18),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('สถิติเวลาเรียน',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    const Text('ภาคเรียนที่ 1/2567',
                        style:
                            TextStyle(color: Color(0xFF77758A), fontSize: 12)),
                    const SizedBox(height: 10),
                    const Text('เข้าเรียน',
                        style: TextStyle(color: Color(0xFF77758A))),
                    Text('${(pct * 2).round()} คาบ',
                        style: TextStyle(
                            color: context.c.ok,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
                    const Text('ทั้งหมด',
                        style: TextStyle(color: Color(0xFF77758A))),
                    Text('200 คาบ',
                        style: TextStyle(
                            color: context.c.sel,
                            fontWeight: FontWeight.w800,
                            fontSize: 18)),
                  ])),
            ]),
          ),
          const SizedBox(height: 14),
          Notice(
              title: below
                  ? 'ต่ำกว่าเกณฑ์แล้ว'
                  : 'เหลือสิทธิ์การขาดได้อีก ${worst?.absencesLeft ?? 2} คาบเท่านั้น',
              body: below
                  ? 'ยื่นคำร้องขอเข้าดุลยพินิจและติดต่ออาจารย์ผู้สอน'
                  : 'หากเกินจะถูกประเมินผลไม่ผ่านรายวิชา',
              tone: Tone.crit),
          const SizedBox(height: 16),
          const Row(children: [
            Expanded(child: _Tab('รายวิชาทั้งหมด', true)),
            SizedBox(width: 7),
            Expanded(child: _Tab('ต่ำกว่า 80%', false)),
            SizedBox(width: 7),
            Expanded(child: _Tab('ทั้งหมด', false)),
          ]),
          const SizedBox(height: 10),
          if (courses.isEmpty) ...const [
            _Course('การบัญชีเบื้องต้น 1', 'อ.กมลวรรณ', .88,
                Icons.menu_book_outlined),
            _Course('การตลาดดิจิทัล', 'อ.ชานนท์', .82, Icons.campaign_outlined),
            _Course('ภาษาอังกฤษเพื่ออาชีพ', 'อ.ณัฐธิดา', .79,
                Icons.translate_outlined),
            _Course('คอมพิวเตอร์ธุรกิจ', 'อ.วีรพล', .85,
                Icons.desktop_windows_outlined),
          ] else
            for (final c in courses)
              _Course(
                  c.name, '', c.pctProjected / 100, Icons.menu_book_outlined),
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.info_outline, size: 16, color: Color(0xFF77758A)),
            SizedBox(width: 6),
            Expanded(
              child: Text('ข้อมูลอัปเดตล่าสุด 20 พ.ค. 2567 08:30 น.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF77758A))),
            )
          ]),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.text, this.icon);
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(children: [
        const SizedBox(width: 24),
        Expanded(
          child: Text(text,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        ),
        Icon(icon, color: context.c.ink2)
      ]);
}

class _Tab extends StatelessWidget {
  const _Tab(this.text, this.selected);
  final String text;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
          color: selected ? context.c.sel : const Color(0xFFF3F3FA),
          borderRadius: BorderRadius.circular(99)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : context.c.ink2,
              fontWeight: FontWeight.w600)));
}

class _Course extends StatelessWidget {
  const _Course(this.name, this.teacher, this.value, this.icon);
  final String name, teacher;
  final double value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final warn = value < .8;
    final color = warn ? const Color(0xFFFFA000) : context.c.ok;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: context.c.sunk,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [
            BoxShadow(color: Color(0x100F0D2A), blurRadius: 10)
          ]),
      child: Column(children: [
        Row(children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 19)),
          const SizedBox(width: 9),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (teacher.isNotEmpty)
                  Text(teacher,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF77758A)))
              ])),
          Text('${(value * 100).round()}%',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 17))
        ]),
        const SizedBox(height: 7),
        ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: const Color(0xFFF0F1F5),
                color: color))
      ]),
    );
  }
}

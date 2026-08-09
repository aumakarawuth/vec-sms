import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'async_view.dart';

/// หน้าจอ A-02 — มาตรวัดเวลาเรียน
///
/// นี่คือฟีเจอร์กันหลุดที่สำคัญที่สุดในแอป ตามระเบียบ ปวช./ปวส.
/// เวลาเรียนต่ำกว่า 80% ของรายวิชาใดจะหมดสิทธิ์เข้ารับการประเมินสรุปผล
/// นักศึกษาส่วนใหญ่ไม่รู้ตัวจนกระทั่งสายเกินแก้ หน้าจอนี้จึงบอกตรง ๆ
/// ว่า "ขาดได้อีกกี่คาบ" ไม่ใช่แค่แสดงเปอร์เซ็นต์
class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key, required this.session});
  final Session session;

  Future<Fetched<List<CourseAttendance>>> _load() async {
    final r = await session.api
        .getCached('/students/${session.studentId}/attendance?termId=${session.termId}');
    return Fetched(
      (r.data as List)
          .map((e) => CourseAttendance.fromJson(e as Map<String, dynamic>))
          .toList(),
      fromCache: r.fromCache,
      cachedAt: r.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<List<CourseAttendance>>(
      load: _load,
      builder: (context, courses) {
        if (courses.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Gap.sm),
              const ScreenHeader(
                kicker: 'เวลาเรียน',
                title: 'ยังไม่มีรายวิชา',
              ),
              const SizedBox(height: Gap.lg),
              Text('เมื่อลงทะเบียนแล้วเวลาเรียนแต่ละวิชาจะแสดงที่นี่',
                  style: t.bodyMedium),
            ],
          );
        }

        final sorted = [...courses]
          ..sort((a, b) => a.pctProjected.compareTo(b.pctProjected));
        final worst = sorted.first;
        final atRisk =
            sorted.where((c) => c.state != AttendanceState.ok).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.sm),
            ScreenHeader(
              kicker: 'เกณฑ์ผ่าน ${worst.minPct.toStringAsFixed(0)}% ของทุกรายวิชา',
              title: 'เวลาเรียนของฉัน',
            ),

            const SizedBox(height: Gap.xl),
            Figure(
              Fmt.percent(worst.pctProjected),
              tone: toneOfAttendance(worst.state),
              caption: 'วิชาที่ต่ำที่สุด — ${worst.name}',
            ),
            const SizedBox(height: Gap.sm),
            Text(
              worst.state == AttendanceState.ok
                  ? 'ยังไม่มีวิชาไหนเสี่ยงหมดสิทธิ์สอบ'
                  : worst.absencesLeft > 0
                      ? 'ขาดได้อีก ${worst.absencesLeft} คาบเท่านั้น'
                      : 'ต่ำกว่าเกณฑ์แล้ว ต้องยื่นคำร้องต่อสถานศึกษา',
              style: t.bodyMedium?.copyWith(
                color: worst.state == AttendanceState.ok
                    ? context.c.ink2
                    : toneColor(context, toneOfAttendance(worst.state)),
              ),
            ),

            if (atRisk.length > 1) ...[
              const SizedBox(height: Gap.xl),
              Notice(
                title: 'มี ${atRisk.length} รายวิชาที่ต้องระวัง',
                body: atRisk.map((c) => c.name).join(' · '),
                tone: Tone.warn,
              ),
            ],

            const SizedBox(height: Gap.xl),
            GroupHeader('ทั้งหมด ${courses.length} รายวิชา'),
            const SizedBox(height: Gap.lg),
            for (final c in sorted) ...[
              Meter(
                label: c.name,
                value: c.pctProjected / 100,
                tone: toneOfAttendance(c.state),
                note: switch (c.state) {
                  AttendanceState.ok => c.absencesLeft > 0
                      ? 'ขาดได้อีก ${c.absencesLeft} คาบ'
                      : null,
                  AttendanceState.warning =>
                    'ขาดได้อีก ${c.absencesLeft} คาบ ก่อนตกเกณฑ์',
                  AttendanceState.discretion =>
                    'ต่ำกว่าเกณฑ์ ยื่นคำร้องเข้าดุลยพินิจได้',
                  AttendanceState.failed =>
                    'หมดสิทธิ์เข้ารับการประเมินสรุปผลรายวิชานี้',
                },
              ),
              const SizedBox(height: Gap.xl),
            ],
          ],
        );
      },
    );
  }
}

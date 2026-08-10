import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fmt.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';
import 'async_view.dart';

/// A-07 โหมดผู้ปกครอง
///
/// ─── ทำไมไม่ใช่แค่ "แอปเดียวกันแต่ล็อกอินคนละบัญชี" ───
/// ผู้ปกครองเห็นได้เท่าที่ `student_guardian` อนุญาตไว้เป็นรายคน —
/// `can_view_grades` กับ `can_view_finance` แยกกัน และต้อง `verified_at`
/// แล้วเท่านั้น หน้าจอจึงต้องรับมือกับกรณีที่เห็นบางส่วนอย่างสุภาพ
/// ไม่ใช่ขึ้น "ไม่มีสิทธิ์" เต็มหน้า
///
/// ─── สิ่งที่ผู้ปกครองแก้ไม่ได้ ───
/// ทุกอย่าง — หน้านี้อ่านอย่างเดียวทั้งหน้า สิทธิ์ของผู้ปกครองถูกกำหนดโดย
/// งานทะเบียน และแม้แต่นักศึกษาเองก็แก้ `student_guardian` ของตัวเองไม่ได้
/// ตั้งแต่ 0045 (เดิมปิดไม่ให้พ่อแม่เห็นเกรดตัวเองได้)
class GuardianScreen extends StatelessWidget {
  const GuardianScreen({super.key, required this.session});

  final Session session;

  /// ─── ทำไมต้องยิงทีละส่วนแล้วทนกับ 403 ───
  /// สิทธิ์ของผู้ปกครองแยกเป็นรายเรื่อง (can_view_grades · can_view_finance)
  /// การยิงรวมทีเดียวแล้วเจอ 403 หนึ่งเรื่องจะทำให้ทั้งหน้าว่างเปล่า
  /// ทั้งที่อีกสองเรื่องดูได้ — ผู้ปกครองที่เปิดมาดูว่าลูกขาดเรียนหรือเปล่า
  /// จะไม่เห็นอะไรเลยเพราะยังไม่ได้รับสิทธิ์ดูการเงิน
  Future<Fetched<Map<String, dynamic>>> _load() async {
    final sid = session.studentId!;

    Future<T?> allowed<T>(Future<T> Function() fn) async {
      try {
        return await fn();
      } on ApiException catch (e) {
        // 403 = ยังไม่ได้รับสิทธิ์ในเรื่องนี้ ซึ่งเป็นสถานะปกติ ไม่ใช่ข้อผิดพลาด
        if (e.isForbidden) return null;
        rethrow;
      }
    }

    final attendance = await allowed(() async {
      final r = await session.api
          .get('/students/$sid/attendance?termId=${session.termId}');
      final rows = (r as List<dynamic>).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return <String, dynamic>{};
      // แสดงวิชาที่เสี่ยงที่สุด เพราะเป็นเรื่องที่ผู้ปกครองต้องรู้ก่อน
      rows.sort((a, b) =>
          (Fmt.toNum(a['absences_left']) ?? 99).compareTo(
              Fmt.toNum(b['absences_left']) ?? 99));
      return rows.first;
    });

    final finance = await allowed(() async {
      final r = await session.api.get('/students/$sid/balance');
      return Map<String, dynamic>.from(r as Map);
    });

    final grades = await allowed(() async {
      final r = await session.api.get('/students/$sid/graduation');
      return Map<String, dynamic>.from(r as Map);
    });

    return Fetched({
      if (attendance != null && attendance.isNotEmpty) 'attendance': attendance,
      if (finance != null) 'finance': finance,
      if (grades != null) 'grades': grades,
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<Map<String, dynamic>>(
      load: () => _load(),
      builder: (context, data) {
        final grades = data['grades'] as Map<String, dynamic>?;
        final finance = data['finance'] as Map<String, dynamic>?;
        final attendance = data['attendance'] as Map<String, dynamic>?;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              kicker: session.studentCode,
              title: session.displayName ?? 'นักศึกษา',
              subtitle: session.programName,
            ),

            // ── เวลาเรียน — เห็นได้เสมอ เพราะเป็นเรื่องความปลอดภัยของเด็ก ──
            if (attendance != null) ...[
              const SizedBox(height: Gap.xl),
              const GroupHeader('เวลาเรียน'),
              const SizedBox(height: Gap.md),
              InfoRow('เข้าเรียน', value: Fmt.percent(attendance['pct_to_date'])),
              InfoRow(
                'ขาดได้อีก',
                value: '${Fmt.count(attendance['absences_left'])} คาบ',
                tone: (Fmt.toNum(attendance['absences_left']) ?? 99) <= 2
                    ? Tone.crit
                    : Tone.neutral,
              ),
            ],

            // ── ผลการเรียน — เฉพาะผู้ปกครองที่ได้รับสิทธิ์ ──
            const SizedBox(height: Gap.xl),
            const GroupHeader('ผลการเรียน'),
            const SizedBox(height: Gap.md),
            if (grades == null)
              const _Restricted(
                what: 'ผลการเรียน',
                why: 'บัญชีผู้ปกครองนี้ยังไม่ได้รับสิทธิ์ดูผลการเรียน',
              )
            else ...[
              InfoRow('เกรดเฉลี่ยสะสม', value: Fmt.toNum(grades['gpax'])?.toStringAsFixed(2) ?? '—'),
              InfoRow('หน่วยกิตสะสม', value: Fmt.count(grades['credits_earned'])),
            ],

            // ── การเงิน — เฉพาะผู้ปกครองที่ได้รับสิทธิ์ ──
            const SizedBox(height: Gap.xl),
            const GroupHeader('การเงิน'),
            const SizedBox(height: Gap.md),
            if (finance == null)
              const _Restricted(
                what: 'ข้อมูลการเงิน',
                why: 'บัญชีผู้ปกครองนี้ยังไม่ได้รับสิทธิ์ดูข้อมูลการเงิน',
              )
            else ...[
              InfoRow('ยอดค้างชำระ', value: Fmt.money(finance['balance']),
                  tone: (Fmt.toNum(finance['balance']) ?? 0) > 0 ? Tone.warn : Tone.ok),
              if (finance['next_due_on'] != null)
                InfoRow('งวดถัดไป', value: Fmt.dateShortOf(finance['next_due_on'])),
            ],

            const SizedBox(height: Gap.xxl),
            Text(
              'หน้านี้อ่านอย่างเดียว การเปลี่ยนสิทธิ์ของผู้ปกครองทำที่งานทะเบียน '
              'เท่านั้น — นักศึกษาแก้เองไม่ได้ และผู้ปกครองก็แก้เองไม่ได้',
              style: t.labelSmall,
            ),
          ],
        );
      },
    );
  }
}

/// ส่วนที่บัญชีนี้ไม่ได้รับสิทธิ์ดู
///
/// บอกว่า "ยังไม่ได้รับสิทธิ์" ไม่ใช่ "ไม่มีข้อมูล" — สองอย่างนี้ต่างกัน
/// สำหรับผู้ปกครองที่กำลังสงสัยว่าลูกมีหนี้ค้างหรือเปล่า
class _Restricted extends StatelessWidget {
  const _Restricted({required this.what, required this.why});

  final String what;
  final String why;

  @override
  Widget build(BuildContext context) {
    return Notice(
      title: 'ยังไม่ได้รับสิทธิ์ดู$what',
      body: '$why — ติดต่องานทะเบียนของวิทยาลัยเพื่อขอสิทธิ์',
    );
  }
}

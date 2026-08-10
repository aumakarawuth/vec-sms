import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/fmt.dart';
import '../core/secure_store.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';
import 'async_view.dart';

/// A-05 เช็คอินเข้าเรียน
///
/// ─── สิ่งที่หน้าจอนี้ทำไม่ได้โดยตั้งใจ ───
/// ปุ่มนี้ส่งได้แค่ **คำขอ** ไม่ได้บันทึกเวลาเรียน — เวลาเรียนเกิดขึ้นเมื่อ
/// ครูผู้สอนยืนยันเท่านั้น (migration 0047)
///
/// เหตุผลอยู่ใน 0039: ก่อนหน้านั้นนักศึกษาแก้เวลาเรียนของตัวเองได้จริง
/// กฎ 80% จึงไม่มีผลกับใครที่รู้วิธี การเพิ่มปุ่มเช็คอินให้นักศึกษาต้องไม่
/// ทำให้ช่องนั้นกลับมาทางอ้อม หน้าจอจึงบอกสถานะตรง ๆ ว่า "รอครูยืนยัน"
/// ไม่ใช่ทำเป็นว่าเช็คชื่อสำเร็จแล้ว
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({
    super.key,
    required this.session,
    required this.deviceIdentity,
  });

  final Session session;

  /// ตัวระบุเครื่องเดียวกับที่ใช้ผูกบัญชีตอนเข้าสู่ระบบ — ครูจะได้เห็นว่า
  /// คำขอส่งมาจากเครื่องที่ผูกไว้หรือเครื่องอื่น
  final DeviceIdentity deviceIdentity;

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  String? _busyMeeting;
  String? _error;

  Future<Fetched<List<Map<String, dynamic>>>> _load() async {
    final today = DateTime.now();
    final date = '${today.year}-${_two(today.month)}-${_two(today.day)}';
    final data = await widget.session.api
        .getCached('/students/${widget.session.studentId}/schedule?date=$date');
    final rows = (data.data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Fetched(rows, fromCache: data.fromCache, cachedAt: data.cachedAt);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _checkin(Map<String, dynamic> meeting) async {
    setState(() {
      _busyMeeting = meeting['meeting_id']?.toString();
      _error = null;
    });
    try {
      await widget.session.api.post('/attendance/checkin', {
        'meetingId': meeting['meeting_id'],
        'enrollmentId': meeting['enrollment_id'],
        // ตัวระบุเครื่องเดิมกับที่ใช้ผูกบัญชี ครูจะได้เห็นว่าส่งมาจากเครื่องไหน
        'deviceId': await widget.deviceIdentity.get(),
      });
      await _key.currentState?.reload();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on OfflineException {
      setState(() => _error = 'ต่อเซิร์ฟเวอร์ไม่ได้ — เช็คอินต้องมีสัญญาณ');
    } finally {
      if (mounted) setState(() => _busyMeeting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<List<Map<String, dynamic>>>(
      key: _key,
      load: _load,
      builder: (context, rows) {
        // เส้นทาง schedule รับวันที่มาแล้ว จึงเป็นคาบของวันนี้ทั้งหมด
        final today = rows;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              kicker: Fmt.dateWithWeekday(DateTime.now()),
              title: 'เช็คอินเข้าเรียน',
              subtitle: 'เวลาเรียนจะถูกบันทึกเมื่อครูผู้สอนยืนยัน',
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.lg),
              Notice(title: 'เช็คอินไม่สำเร็จ', body: _error, tone: Tone.crit),
            ],
            const SizedBox(height: Gap.xl),
            if (today.isEmpty)
              const Notice(
                title: 'วันนี้ไม่มีคาบเรียน',
                body: 'ตารางเรียนของวันนี้ว่าง — ถ้าคิดว่าไม่ถูกต้อง '
                    'ให้ตรวจกับครูที่ปรึกษา',
                tone: Tone.neutral,
              )
            else
              for (final m in today) ...[
                Divider(height: 1, color: context.c.rule),
                _MeetingRow(
                  meeting: m,
                  busy: _busyMeeting == m['meeting_id']?.toString(),
                  onCheckin: () => _checkin(m),
                ),
              ],
            Divider(height: 1, color: context.c.rule),
            const SizedBox(height: Gap.xl),
            Text(
              'การกดเช็คอินเป็นการแจ้งครูว่ามาถึงแล้ว ไม่ใช่การบันทึกเวลาเรียนเอง '
              'ถ้าครูยังไม่ยืนยัน คาบนั้นจะยังไม่ถูกนับ',
              style: t.labelSmall,
            ),
          ],
        );
      },
    );
  }

}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.meeting,
    required this.busy,
    required this.onCheckin,
  });

  final Map<String, dynamic> meeting;
  final bool busy;
  final VoidCallback onCheckin;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = meeting['checkin_status'] != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meeting['course_name']?.toString() ??
                      meeting['course_code']?.toString() ??
                      'คาบเรียน',
                  style: t.titleMedium,
                ),
                Text(
                  [
                    if (meeting['period_from'] != null)
                      'คาบ ${meeting['period_from']}',
                    if (meeting['room'] != null) '${meeting['room']}',
                  ].join(' · '),
                  style: t.bodySmall,
                ),
                if (done) ...[
                  const SizedBox(height: Gap.xs),
                  StatusDot(
                    switch (meeting['checkin_status'].toString()) {
                      'accepted' => 'ครูยืนยันแล้ว',
                      'rejected' => 'ครูไม่รับคำขอ',
                      _ => 'รอครูยืนยัน',
                    },
                    tone: switch (meeting['checkin_status'].toString()) {
                      'accepted' => Tone.ok,
                      'rejected' => Tone.crit,
                      _ => Tone.warn,
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.md),
          if (!done)
            SizedBox(
              width: 110,
              child: PrimaryButton(
                busy ? 'กำลังส่ง' : 'เช็คอิน',
                onPressed: busy ? null : onCheckin,
              ),
            ),
        ],
      ),
    );
  }
}

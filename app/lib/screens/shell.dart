import 'package:flutter/material.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';
import '../core/secure_store.dart';
import 'attendance.dart';
import 'checkin.dart';
import 'finance.dart';
import 'graduation.dart';
import 'guardian.dart';
import 'home.dart';
import 'practicum.dart';

/// โครงหลักของแอป — แท็บล่างเป็นตัวอักษรล้วน ไม่มีไอคอน
///
/// ผู้ใช้คือนักศึกษาอายุ 15–18 ปี และผู้ปกครองที่อายุมาก
/// ไอคอนที่ประดิษฐ์ขึ้นเองมักถูกตีความผิด ส่วนคำไทยสั้น ๆ อ่านได้ทันที
/// และไม่มีเมนูซ่อน เพราะสิ่งที่ซ่อนคือสิ่งที่หาไม่เจอ
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.deviceIdentity,
  });
  final Session session;
  final DeviceIdentity deviceIdentity;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /*
   * ─── ทำไมแท็บของนักศึกษากับผู้ปกครองไม่เหมือนกัน ───
   * ผู้ปกครองเช็คอินแทนลูกไม่ได้ (ไม่มีเหตุผลใดที่ควรทำได้) และไม่ต้อง
   * บันทึกชั่วโมงฝึกอาชีพ สองแท็บนั้นจึงไม่มีในโหมดผู้ปกครอง
   *
   * ส่วนแท็บ "ลูกของฉัน" รวมเรื่องที่ผู้ปกครองเปิดมาดูจริง ๆ ไว้หน้าเดียว
   * และทนกับกรณีที่ได้รับสิทธิ์ไม่ครบทุกเรื่อง
   */
  bool get _isGuardian => widget.session.isGuardianMode;

  List<String> get _labels => _isGuardian
      ? ['หน้าแรก', 'ลูกของฉัน', 'เวลาเรียน', 'การเงิน', 'ฉัน']
      : ['หน้าแรก', 'เช็คอิน', 'เวลาเรียน', 'ฝึกอาชีพ', 'การจบ', 'ฉัน'];

  void _openTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = _isGuardian
        ? [
            HomeScreen(session: s, onOpenTab: _openTab),
            GuardianScreen(session: s),
            AttendanceScreen(session: s),
            FinanceScreen(session: s),
            _ProfileScreen(session: s),
          ]
        : [
            HomeScreen(session: s, onOpenTab: _openTab),
            CheckinScreen(session: s, deviceIdentity: widget.deviceIdentity),
            AttendanceScreen(session: s),
            PracticumScreen(session: s),
            GraduationScreen(session: s),
            _ProfileScreen(session: s),
          ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: _TextTabBar(
        labels: _labels,
        index: _index,
        onTap: _openTab,
      ),
    );
  }
}

class _TextTabBar extends StatelessWidget {
  const _TextTabBar({
    required this.labels,
    required this.index,
    required this.onTap,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.c.bg,
        border: Border(top: BorderSide(color: context.c.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Center(
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight:
                              i == index ? FontWeight.w600 : FontWeight.w400,
                          color: i == index ? context.c.ink : context.c.ink4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
      children: [
        ScreenHeader(
          kicker: session.studentCode,
          title: session.displayName ?? 'ฉัน',
          subtitle: session.programName,
        ),
        const SizedBox(height: Gap.xl),
        const GroupHeader('บัญชี'),
        const SizedBox(height: Gap.md),
        InfoRow('รหัสนักศึกษา', value: session.studentCode),
        InfoRow('สาขาวิชา', value: session.programName ?? '—'),
        const SizedBox(height: Gap.xxl),
        PrimaryButton(
          'ออกจากระบบ',
          ghost: true,
          onPressed: () => session.signOut(),
        ),
        const SizedBox(height: Gap.md),
        Text(
          'การออกจากระบบจะลบข้อมูลที่บันทึกไว้ในเครื่องทั้งหมด '
          'รวมถึงผลการเรียนและยอดค้างชำระที่แคชไว้สำหรับใช้ตอนไม่มีสัญญาณ',
          style: t.bodySmall,
        ),
      ],
    );
  }
}

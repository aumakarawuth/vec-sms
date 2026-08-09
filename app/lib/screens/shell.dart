import 'package:flutter/material.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';
import 'attendance.dart';
import 'finance.dart';
import 'graduation.dart';
import 'home.dart';

/// โครงหลักของแอป — แท็บล่างเป็นตัวอักษรล้วน ไม่มีไอคอน
///
/// ผู้ใช้คือนักศึกษาอายุ 15–18 ปี และผู้ปกครองที่อายุมาก
/// ไอคอนที่ประดิษฐ์ขึ้นเองมักถูกตีความผิด ส่วนคำไทยสั้น ๆ อ่านได้ทันที
/// และไม่มีเมนูซ่อน เพราะสิ่งที่ซ่อนคือสิ่งที่หาไม่เจอ
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.session});
  final Session session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _labels = ['หน้าแรก', 'เวลาเรียน', 'การจบ', 'การเงิน', 'ฉัน'];

  void _openTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = [
      HomeScreen(session: s, onOpenTab: _openTab),
      AttendanceScreen(session: s),
      GraduationScreen(session: s),
      FinanceScreen(session: s),
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

import 'package:flutter/material.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/secure_store.dart';
import 'attendance.dart';
import 'finance.dart';
import 'graduation.dart';
import 'home.dart';
import 'profile.dart';

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

  List<String> get _labels => const [
        'หน้าแรก',
        'เวลาเรียน',
        'การเงิน',
        'ผลการเรียน',
        'ฉัน',
      ];

  void _openTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final pages = [
      HomeScreen(session: s, onOpenTab: _openTab),
      AttendanceScreen(session: s),
      FinanceScreen(session: s),
      GraduationScreen(session: s),
      ProfileScreen(
        session: s,
        deviceIdentity: widget.deviceIdentity,
        showStudentTools: !_isGuardian,
      ),
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
    const icons = [
      Icons.home_rounded,
      Icons.schedule_rounded,
      Icons.account_balance_wallet_rounded,
      Icons.school_rounded,
      Icons.person_rounded,
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.c.sunk,
        boxShadow: const [
          BoxShadow(
              color: Color(0x140F0D2A), blurRadius: 18, offset: Offset(0, -4))
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 7),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icons[i],
                              size: i == index ? 23 : 21,
                              color:
                                  i == index ? context.c.sel : context.c.ink4,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                fontWeight: i == index
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color:
                                    i == index ? context.c.sel : context.c.ink3,
                              ),
                            ),
                          ]),
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

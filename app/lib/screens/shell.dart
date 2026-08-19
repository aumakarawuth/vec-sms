import 'package:flutter/material.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';
import '../core/secure_store.dart';
import 'attendance.dart';
import 'checkin.dart';
import 'finance.dart';
import 'graduation.dart';
import 'home.dart';
import 'practicum.dart';
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

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen({
    required this.session,
    required this.deviceIdentity,
    required this.showStudentTools,
  });
  final Session session;
  final DeviceIdentity deviceIdentity;
  final bool showStudentTools;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.xl),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFECEAFE), Color(0xFFF8F7FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFFD47F),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                (session.displayName?.isNotEmpty ?? false)
                    ? session.displayName!.characters.first
                    : 'น',
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF51418E)),
              ),
            ),
            const SizedBox(height: Gap.md),
            Text(session.displayName ?? 'ฉัน',
                style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Gap.xs),
            Text(
                [session.studentCode, session.programName]
                    .where((e) => e != null && e.isNotEmpty)
                    .join(' · '),
                style: t.bodySmall,
                textAlign: TextAlign.center),
          ]),
        ),
        const SizedBox(height: Gap.xl),
        const GroupHeader('เมนูของฉัน'),
        const SizedBox(height: Gap.md),
        if (showStudentTools) ...[
          _ProfileMenu(
            icon: Icons.qr_code_scanner_rounded,
            label: 'เช็คอินเข้าเรียน',
            value: 'ส่งคำขอเช็คอินและรอครูยืนยัน',
            onTap: () => _open(
              context,
              CheckinScreen(session: session, deviceIdentity: deviceIdentity),
            ),
          ),
          _ProfileMenu(
            icon: Icons.work_outline_rounded,
            label: 'ฝึกอาชีพ',
            value: 'ชั่วโมงที่รับรองแล้วและรายการรอตรวจ',
            onTap: () => _open(context, PracticumScreen(session: session)),
          ),
        ],
        _ProfileMenu(
            icon: Icons.person_outline_rounded,
            label: 'ข้อมูลส่วนตัว',
            value: session.studentCode ?? '—',
            onTap: null),
        _ProfileMenu(
            icon: Icons.school_outlined,
            label: 'สาขาวิชา',
            value: session.programName ?? '—',
            onTap: null),
        const _ProfileMenu(
            icon: Icons.shield_outlined,
            label: 'ความปลอดภัย',
            value: 'รหัสผ่านและอุปกรณ์',
            onTap: null),
        const _ProfileMenu(
            icon: Icons.help_outline_rounded,
            label: 'ขอความช่วยเหลือ',
            value: 'ติดต่องานทะเบียน',
            onTap: null),
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

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(),
          body: SafeArea(child: screen),
        ),
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu(
      {required this.icon,
      required this.label,
      required this.value,
      this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Material(
          color: context.c.sunk,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(children: [
                Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                        color: Color(0xFFECEAFE), shape: BoxShape.circle),
                    child: Icon(icon, color: context.c.sel, size: 20)),
                const SizedBox(width: Gap.md),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(label,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(value, style: Theme.of(context).textTheme.bodySmall)
                    ])),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, color: context.c.ink4),
              ]),
            ),
          ),
        ),
      );
}

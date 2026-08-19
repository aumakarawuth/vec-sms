import 'package:flutter/material.dart';
import '../core/session.dart';
import '../core/secure_store.dart';
import '../core/theme.dart';
import 'checkin.dart';
import 'practicum.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {super.key,
      required this.session,
      required this.deviceIdentity,
      required this.showStudentTools});
  final Session session;
  final DeviceIdentity deviceIdentity;
  final bool showStudentTools;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
        const Center(
            child: Text('ฉัน',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
        const SizedBox(height: 14),
        Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFEFEAFF), Color(0xFFF7F4FF)]),
                borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Stack(clipBehavior: Clip.none, children: [
                CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.white,
                    backgroundImage:
                        const AssetImage('assets/images/student-avatar.png')),
                Positioned(
                    right: -2,
                    bottom: 2,
                    child: CircleAvatar(
                        radius: 15,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.camera_alt_rounded,
                            size: 17, color: context.c.sel)))
              ]),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(session.displayName ?? 'นภัสกร รัตนพงศ์',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('รหัสนักศึกษา',
                        style:
                            TextStyle(fontSize: 11, color: Color(0xFF77758A))),
                    Text(session.studentCode ?? '6730201001',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('ระดับชั้น',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF77758A))),
                            Text('ปวส.2/1',
                                style: TextStyle(fontWeight: FontWeight.w600))
                          ])),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('สาขาวิชา',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF77758A))),
                            Text(session.programName ?? 'การบัญชี',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))
                          ]))
                    ])
                  ]))
            ])),
        const SizedBox(height: 16),
        const Text('ข้อมูลส่วนตัว',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        _Group(children: [
          const _Menu(Icons.person_outline, 'ข้อมูลส่วนตัว'),
          const _Menu(Icons.home_outlined, 'ที่อยู่'),
          const _Menu(Icons.people_outline, 'ข้อมูลผู้ปกครอง'),
          const _Menu(Icons.phone_outlined, 'ติดต่อฉุกเฉิน')
        ]),
        const SizedBox(height: 16),
        const Text('ความปลอดภัย',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        _Group(children: [
          const _Menu(Icons.lock_outline, 'เปลี่ยนรหัสผ่าน'),
          const _Menu(Icons.shield_outlined, 'ตั้งค่าความปลอดภัย')
        ]),
        if (showStudentTools) ...[
          const SizedBox(height: 16),
          const Text('ตั้งค่า', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          _Group(children: [
            _Menu(Icons.qr_code_scanner_rounded, 'เช็คอินเข้าเรียน',
                onTap: () => _open(
                    context,
                    CheckinScreen(
                        session: session, deviceIdentity: deviceIdentity))),
            _Menu(Icons.work_outline_rounded, 'ฝึกอาชีพ',
                onTap: () => _open(context, PracticumScreen(session: session)))
          ])
        ],
        const SizedBox(height: 16),
        const Text('ช่วยเหลือ', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        _Group(children: [
          const _Menu(Icons.help_outline, 'คำถามที่พบบ่อย'),
          const _Menu(Icons.support_agent_outlined, 'ติดต่อเรา')
        ]),
      ]);
  static void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              Scaffold(appBar: AppBar(), body: SafeArea(child: page))));
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E8EF))),
      child: Column(children: children));
}

class _Menu extends StatelessWidget {
  const _Menu(this.icon, this.label, {this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 21, color: context.c.ink2),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            Icon(Icons.chevron_right_rounded, color: context.c.ink4)
          ])));
}

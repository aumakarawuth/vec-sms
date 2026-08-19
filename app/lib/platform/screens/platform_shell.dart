import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets.dart';
import '../platform_session.dart';
import 'audit.dart';
import 'institutions.dart';
import 'plans.dart';
import 'users.dart';

/// โครงหลักของหน้าจอผู้ให้บริการ
///
/// ─── ทำไมแถบเมนูอยู่ด้านข้าง ไม่ใช่ด้านล่างเหมือนแอปนักศึกษา ───
/// หน้าจอนี้ใช้บนเดสก์ท็อปเป็นหลัก (คนทำงานหน้าคอม ไม่ใช่คนเดินอยู่ในวิทยาลัย)
/// และมีตารางกว้าง ๆ ที่ต้องการความสูงของจอทั้งหมด แถบล่างจะกินพื้นที่
/// ในแนวที่ขาดอยู่แล้ว ส่วนบนจอแคบจะสลับไปใช้แถบล่างแทน
class PlatformShell extends StatefulWidget {
  const PlatformShell({super.key, required this.session});

  final PlatformSession session;

  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;

    // บัญชีระดับ support ไม่มีหน้าจอบัญชีผู้ดูแล — ซ่อนทั้งแท็บดีกว่าให้กด
    // แล้วเจอข้อความปฏิเสธ (เซิร์ฟเวอร์ยังปฏิเสธอยู่ดีถ้ามีใครเรียกตรง)
    final tabs = <_Tab>[
      _Tab('วิทยาลัย', (c) => InstitutionsScreen(session: s)),
      _Tab('แพ็กเกจ', (c) => PlansScreen(session: s)),
      if (s.role.canManageUsers)
        _Tab('บัญชีผู้ดูแล', (c) => PlatformUsersScreen(session: s)),
      _Tab('บันทึก', (c) => PlatformAuditScreen(session: s)),
      _Tab('ฉัน', (c) => _ProfilePane(session: s)),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 720;
            final body = ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: IndexedStack(
                index: index,
                children: [for (final t in tabs) t.build(context)],
              ),
            );

            if (!wide) {
              return Column(
                children: [
                  Expanded(child: body),
                  _BottomTabs(
                    labels: [for (final t in tabs) t.label],
                    index: index,
                    onTap: (i) => setState(() => _index = i),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SideTabs(
                  labels: [for (final t in tabs) t.label],
                  index: index,
                  onTap: (i) => setState(() => _index = i),
                  session: s,
                ),
                Expanded(child: Center(child: body)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.build);
  final String label;
  final Widget Function(BuildContext) build;
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({
    required this.labels,
    required this.index,
    required this.onTap,
    required this.session,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onTap;
  final PlatformSession session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: context.c.sunk,
        border: Border(right: BorderSide(color: context.c.rule)),
      ),
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.md, Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ผู้ให้บริการระบบ', style: t.labelSmall),
          const SizedBox(height: Gap.xs),
          Text(session.displayName ?? session.username ?? '—',
              style: t.titleMedium),
          Text(session.role.label, style: t.bodySmall),
          const SizedBox(height: Gap.xl),
          for (var i = 0; i < labels.length; i++)
            InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: Gap.xs),
                padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md, vertical: Gap.md),
                decoration: BoxDecoration(
                  color:
                      i == index ? const Color(0xFFEDEAFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  labels[i],
                  style: t.bodyLarge?.copyWith(
                    fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
                    color: i == index ? context.c.sel : context.c.ink3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
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
        color: context.c.sunk,
        border: Border(top: BorderSide(color: context.c.rule)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x140F0D2A), blurRadius: 18, offset: Offset(0, -4))
        ],
      ),
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
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
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
    );
  }
}

class _ProfilePane extends StatelessWidget {
  const _ProfilePane({required this.session});

  final PlatformSession session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
      children: [
        ScreenHeader(
          kicker: session.username,
          title: session.displayName ?? 'บัญชีของฉัน',
          subtitle: session.role.label,
        ),
        const SizedBox(height: Gap.xl),
        const GroupHeader('ขอบเขตของบัญชีนี้'),
        const SizedBox(height: Gap.md),
        const InfoRow('อ่านข้อมูลนักศึกษาของวิทยาลัย',
            value: 'ไม่ได้', tone: Tone.ok),
        const InfoRow('อ่านข้อมูลบุคลากรของวิทยาลัย',
            value: 'ไม่ได้', tone: Tone.ok),
        const InfoRow('เข้าระบบแทนผู้ใช้ของวิทยาลัย',
            value: 'ไม่ได้', tone: Tone.ok),
        InfoRow('ระงับและคืนสิทธิ์การใช้งาน',
            value: session.role.canWrite ? 'ได้' : 'ไม่ได้'),
        InfoRow('ดูแลบัญชีผู้ดูแลด้วยกันเอง',
            value: session.role.canManageUsers ? 'ได้' : 'ไม่ได้'),
        const SizedBox(height: Gap.lg),
        Text(
          'ข้อจำกัดสามข้อแรกไม่ได้มาจากหน้าจอนี้ แต่มาจาก Row-Level Security '
          'ในฐานข้อมูล — บัญชีนี้ไม่มีสังกัดวิทยาลัย ทุกตารางที่เก็บข้อมูลของ '
          'วิทยาลัยจึงคืนศูนย์แถวเสมอ ต่อให้มีใครเขียนโค้ดเรียกก็ตาม',
          style: t.labelSmall,
        ),
        const SizedBox(height: Gap.xxl),
        PrimaryButton('ออกจากระบบ', ghost: true, onPressed: session.signOut),
        const SizedBox(height: Gap.md),
        Text(
          'หน้าจอนี้ไม่เก็บ token ลงเครื่องเลย ปิดแท็บหรือรีเฟรชหน้าก็ต้อง '
          'เข้าสู่ระบบใหม่ — แลกความสะดวกกับการที่ไม่มี token ค้างให้ใครหยิบไปใช้',
          style: t.labelSmall,
        ),
      ],
    );
  }
}

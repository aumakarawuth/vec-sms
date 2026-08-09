import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../screens/async_view.dart';
import '../../widgets.dart';
import '../console_widgets.dart';
import '../platform_session.dart';

/// บัญชีของผู้ให้บริการด้วยกันเอง — เห็นและแก้ได้เฉพาะระดับ owner
///
/// ─── ทำไมสร้างบัญชีแล้วได้ "รหัสตั้งค่า" ไม่ใช่รหัสผ่าน ───
/// หลักเดียวกับทั้งระบบ (0025 · 0037 · 0040) — คนที่สร้างบัญชีให้ต้องไม่รู้
/// รหัสผ่านของเจ้าตัวแม้แต่วินาทีเดียว มิฉะนั้นบันทึกการกระทำจะชี้ผิดคนได้
/// เมื่อมีใครใช้บัญชีนั้นทำอะไรลงไป
class PlatformUsersScreen extends StatefulWidget {
  const PlatformUsersScreen({super.key, required this.session});

  final PlatformSession session;

  @override
  State<PlatformUsersScreen> createState() => _PlatformUsersScreenState();
}

class _PlatformUsersScreenState extends State<PlatformUsersScreen> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<Fetched<List<Map<String, dynamic>>>> _load() async {
    final data = await widget.session.api.get('/platform/users') as List<dynamic>;
    return Fetched(data.map((e) => Map<String, dynamic>.from(e as Map)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    if (!widget.session.role.canManageUsers) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
        children: const [
          ScreenHeader(kicker: 'ผู้ให้บริการ', title: 'บัญชีผู้ดูแล'),
          SizedBox(height: Gap.xl),
          Notice(
            title: 'ต้องเป็นระดับ owner จึงจะเปิดหน้านี้ได้',
            body: 'การดูแลบัญชีของกันเองแยกจากงานประจำวันโดยตั้งใจ '
                'บัญชีที่ตอบปัญหาลูกค้าไม่จำเป็นต้องแต่งตั้งใครได้',
          ),
        ],
      );
    }

    return AsyncView<List<Map<String, dynamic>>>(
      key: _key,
      load: _load,
      builder: (context, users) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenHeader(
              kicker: 'ผู้ให้บริการ',
              title: 'บัญชีผู้ดูแล',
              subtitle: 'บัญชีเหล่านี้อยู่นอกวิทยาลัยทุกแห่ง',
            ),
            const SizedBox(height: Gap.xl),
            for (final u in users) ...[
              Divider(height: 1, color: context.c.rule),
              ConsoleRow(
                title: '${u['display_name']} (${u['username']})',
                subtitle: '${PlatformRole.parse(u['role']?.toString()).label}'
                    '${u['last_login_at'] == null ? ' · ยังไม่เคยเข้าระบบ' : ' · เข้าล่าสุด ${Fmt.dateShortOf(u['last_login_at'])}'}',
                badge: _badgeOf(u),
                tone: u['disabled_at'] != null ? Tone.crit : Tone.warn,
                onTap: () => _openActions(u),
              ),
            ],
            Divider(height: 1, color: context.c.rule),
            const SizedBox(height: Gap.xl),
            PrimaryButton(
              'สร้างบัญชีใหม่',
              ghost: true,
              onPressed: _create,
            ),
            const SizedBox(height: Gap.lg),
            Text(
              'ต้องเหลือบัญชีระดับ owner ที่ใช้งานได้อย่างน้อยหนึ่งบัญชีเสมอ '
              'มิฉะนั้นจะไม่มีใครแต่งตั้งใครได้อีกเลย — ฐานข้อมูลปฏิเสธการถอด '
              'owner คนสุดท้ายให้อยู่แล้ว',
              style: t.labelSmall,
            ),
          ],
        );
      },
    );
  }

  static String? _badgeOf(Map<String, dynamic> u) {
    if (u['disabled_at'] != null) return 'ถูกระงับ';
    if (u['awaiting_setup'] == true) return 'รอตั้งรหัสผ่าน';
    if (u['mfa_ready'] != true) return 'ยังไม่ได้ตั้งแอปยืนยันสองชั้น';
    return null;
  }

  /// ─── ทำไมไม่รับ BuildContext เป็นพารามิเตอร์ ───
  /// เมธอดที่รับ context เข้ามาแล้วใช้ต่อหลัง await ทำให้ตัววิเคราะห์เตือน
  /// (use_build_context_synchronously) เพราะการเช็ค mounted ของ State
  /// ไม่ได้การันตี context ที่ถูกส่งเข้ามาจากที่อื่น ใช้ context ของ State
  /// เองแล้วเช็ค mounted จึงเป็นคู่ที่ตรวจสอบได้จริง
  Future<void> _create() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CreateUserDialog(session: widget.session),
    );
    if (created == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _SetupCodeDialog(
        username: created['username'].toString(),
        code: created['setupCode'].toString(),
      ),
    );
    await _key.currentState?.reload();
  }

  Future<void> _openActions(Map<String, dynamic> u) async {
    final disabled = u['disabled_at'] != null;
    final me = u['username']?.toString() == widget.session.username;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.c.bg,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!me)
              ListTile(
                title: Text(disabled ? 'เปิดใช้งานบัญชี' : 'ระงับบัญชี'),
                onTap: () => Navigator.of(context).pop(disabled ? 'enable' : 'disable'),
              ),
            if (!me)
              ListTile(
                title: const Text('ออกรหัสตั้งค่าใหม่ (ลืมรหัสผ่าน)'),
                subtitle: const Text('รหัสผ่านเดิมและ session ทั้งหมดจะถูกยกเลิกทันที'),
                onTap: () => Navigator.of(context).pop('reset'),
              ),
            if (me)
              const ListTile(
                title: Text('นี่คือบัญชีของท่านเอง'),
                subtitle: Text('ระงับหรือออกรหัสตั้งค่าให้ตัวเองไม่ได้ '
                    'เพื่อไม่ให้ session ที่ถูกขโมยยึดบัญชีถาวร'),
              ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;
    final id = u['id'].toString();

    try {
      if (action == 'reset') {
        final res = await widget.session.api
            .post('/platform/users/$id/reset', {}) as Map<String, dynamic>;
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => _SetupCodeDialog(
            username: u['username'].toString(),
            code: res['setupCode'].toString(),
          ),
        );
      } else {
        await widget.session.api.post(
          '/platform/users/$id/state',
          {'disabled': action == 'disable'},
        );
      }
      await _key.currentState?.reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.session});

  final PlatformSession session;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _username = TextEditingController();
  final _display = TextEditingController();
  final _email = TextEditingController();
  PlatformRole _role = PlatformRole.support;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _display.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.session.api.post('/platform/users', {
        'username': _username.text.trim(),
        'displayName': _display.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        'role': _role.name,
      }) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(res);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on OfflineException {
      setState(() => _error = 'ต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.c.bg,
      title: const Text('สร้างบัญชีผู้ดูแล'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const GroupHeader('ชื่อผู้ใช้'),
              ConsoleField(controller: _username, enabled: !_busy, hint: 'vendor.support'),
              const SizedBox(height: Gap.lg),
              const GroupHeader('ชื่อที่แสดง'),
              ConsoleField(controller: _display, enabled: !_busy),
              const SizedBox(height: Gap.lg),
              const GroupHeader('อีเมล (ไม่บังคับ)'),
              ConsoleField(controller: _email, enabled: !_busy),
              const SizedBox(height: Gap.lg),
              const GroupHeader('บทบาท'),
              // เขียนเป็นรายการที่กดเลือกเองแทน RadioListTile เพราะ API
              // ตัวนั้นถูกประกาศเลิกใช้ตั้งแต่ Flutter 3.32 และตัวแทนของมัน
              // (RadioGroup) ผูกกับ Material มากกว่าที่หน้าจอนี้ต้องการ
              for (final r in PlatformRole.values)
                _RoleOption(
                  role: r,
                  selected: _role == r,
                  enabled: !_busy,
                  onTap: () => setState(() => _role = r),
                ),
              if (_error != null) ...[
                const SizedBox(height: Gap.md),
                Notice(title: 'สร้างบัญชีไม่สำเร็จ', body: _error, tone: Tone.crit),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'กำลังสร้าง' : 'สร้าง'),
        ),
      ],
    );
  }
}

/// ตัวเลือกบทบาทหนึ่งตัว — จุดกลมหน้าข้อความ ไม่มีสีเพิ่ม
class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.role,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PlatformRole role;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.c;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 5, right: Gap.md),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.ink : c.rule2, width: 1.5),
                color: selected ? c.ink : Colors.transparent,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.label,
                    style: t.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    switch (role) {
                      PlatformRole.owner =>
                        'ทำได้ทุกอย่าง รวมถึงดูแลบัญชีผู้ดูแลด้วยกันเอง',
                      PlatformRole.billing =>
                        'แพ็กเกจ สัญญา เปิดวิทยาลัย ระงับและคืนสิทธิ์',
                      PlatformRole.support => 'อ่านอย่างเดียว ใช้ตอบคำถามลูกค้า',
                    },
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// แสดงรหัสตั้งค่าที่ออกให้ครั้งเดียว
///
/// ปิดหน้านี้แล้วดูซ้ำไม่ได้ เพราะฐานข้อมูลเก็บไว้เป็นค่าแฮชเท่านั้น
/// ต้องบอกผู้ใช้ให้ชัดก่อนกดปิด มิฉะนั้นจะต้องออกรหัสใหม่ทั้งชุด
class _SetupCodeDialog extends StatelessWidget {
  const _SetupCodeDialog({required this.username, required this.code});

  final String username;
  final String code;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: context.c.bg,
      title: const Text('รหัสตั้งค่า'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CopyableValue(label: 'สำหรับบัญชี $username', value: code),
            const SizedBox(height: Gap.lg),
            Text(
              'ส่งรหัสนี้ให้เจ้าตัวตั้งรหัสผ่านเอง มีอายุหนึ่งชั่วโมง ใส่ผิดได้ห้าครั้ง '
              'และดูซ้ำไม่ได้หลังปิดหน้าต่างนี้ เพราะฐานข้อมูลเก็บไว้เป็นค่าแฮชเท่านั้น',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('คัดลอกแล้ว ปิดหน้าต่าง'),
        ),
      ],
    );
  }
}

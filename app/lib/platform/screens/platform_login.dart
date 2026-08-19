import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets.dart';
import '../console_widgets.dart';
import '../platform_session.dart';

/// หน้าเข้าสู่ระบบของผู้ให้บริการ
///
/// ─── ทำไมเป็นสามขั้นในหน้าจอเดียว ───
/// รหัสผ่าน → (ตั้งแอป authenticator ถ้ายังไม่เคย) → รหัสหกหลัก
/// ทั้งสามขั้นเป็นการเข้าสู่ระบบครั้งเดียวกัน การพาไปคนละหน้าจอทำให้ผู้ใช้
/// เข้าใจว่าล้มเหลวแล้วเริ่มใหม่ ทั้งที่กำลังไปได้ดี
///
/// ─── ทำไมไม่มี QR ให้สแกน ───
/// การวาด QR ต้องพึ่งไลบรารีเพิ่ม ซึ่งขัดกับหลักของโปรเจกต์ที่พึ่งไลบรารี
/// ให้น้อยที่สุด แอป authenticator ทุกตัวรับการพิมพ์ความลับด้วยมือได้อยู่แล้ว
/// และผู้ใช้หน้าจอนี้มีไม่กี่คน ตั้งครั้งเดียวจบ
class PlatformLoginScreen extends StatefulWidget {
  const PlatformLoginScreen({super.key, required this.session});

  final PlatformSession session;

  @override
  State<PlatformLoginScreen> createState() => _PlatformLoginScreenState();
}

class _PlatformLoginScreenState extends State<PlatformLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _code.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on OfflineException {
      setState(() =>
          _error = 'ต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบเครือข่ายหรือที่อยู่ API');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
        final user = _username.text.trim();
        if (user.isEmpty || _password.text.isEmpty) {
          throw ApiException(400, 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
        }
        await widget.session.signIn(user, _password.text);
        // ขั้นตั้งแอป authenticator ต้องขอความลับทันที ผู้ใช้จะได้เห็นสิ่งที่
        // ต้องพิมพ์ลงแอปโดยไม่ต้องกดปุ่มเพิ่มอีกครั้ง
        if (widget.session.stage == PlatformStage.needsEnrollment) {
          await widget.session.beginEnrollment();
        }
      });

  Future<void> _submitCode() => _run(() async {
        final code = _code.text.trim();
        if (code.length < 6) throw ApiException(400, 'กรอกรหัสหกหลักจากแอป');
        if (widget.session.stage == PlatformStage.needsEnrollment) {
          await widget.session.confirmEnrollment(code);
        } else {
          await widget.session.verifyCode(code);
        }
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // หน้าจอนี้ใช้บนเดสก์ท็อปเป็นหลัก ปล่อยให้ฟอร์มกว้างเต็มจอ
            // ทำให้สายตาต้องกวาดไกลโดยไม่ได้อะไรเพิ่ม
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xxl),
              children: [
                const ScreenHeader(
                  kicker: 'ผู้ให้บริการระบบ',
                  title: 'หน้าจอผู้ดูแลข้ามวิทยาลัย',
                  subtitle:
                      'บัญชีนี้ไม่มีสิทธิ์อ่านข้อมูลนักศึกษาหรือบุคลากรของวิทยาลัยใด',
                ),
                const SizedBox(height: Gap.xxl),
                if (s.stage == PlatformStage.signedOut)
                  ..._passwordStep(context)
                else
                  ..._codeStep(context, s),
                if (_error != null) ...[
                  const SizedBox(height: Gap.xl),
                  Notice(
                      title: 'ทำรายการไม่สำเร็จ',
                      body: _error,
                      tone: Tone.crit),
                ],
                const SizedBox(height: Gap.xxl),
                Text(
                  'ทุกการกระทำในหน้าจอนี้ถูกบันทึกพร้อมชื่อบัญชี และบันทึกนั้น '
                  'แก้ไม่ได้แม้แต่ผู้ดูแลระบบเอง',
                  style: t.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return [
      const GroupHeader('ชื่อผู้ใช้'),
      ConsoleField(
        controller: _username,
        hint: 'vendor.owner',
        enabled: !_busy,
        onSubmitted: (_) => _passwordFocus.requestFocus(),
      ),
      const SizedBox(height: Gap.xl),
      GroupHeader(
        'รหัสผ่าน',
        trailing: GestureDetector(
          onTap: () => setState(() => _obscure = !_obscure),
          child: Text(_obscure ? 'แสดง' : 'ซ่อน',
              style: t.bodySmall?.copyWith(color: context.c.sel)),
        ),
      ),
      ConsoleField(
        controller: _password,
        focusNode: _passwordFocus,
        hint: '••••••••',
        obscure: _obscure,
        enabled: !_busy,
        onSubmitted: (_) => _signIn(),
      ),
      const SizedBox(height: Gap.xxl),
      PrimaryButton(
        _busy ? 'กำลังตรวจสอบ' : 'เข้าสู่ระบบ',
        onPressed: _busy ? null : _signIn,
      ),
      const SizedBox(height: Gap.md),
      PrimaryButton(
        'ตั้งรหัสผ่านครั้งแรก',
        ghost: true,
        onPressed: _busy
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlatformSetupScreen(session: widget.session),
                  ),
                ),
      ),
    ];
  }

  List<Widget> _codeStep(BuildContext context, PlatformSession s) {
    final enrolling = s.stage == PlatformStage.needsEnrollment;
    final t = Theme.of(context).textTheme;

    return [
      if (enrolling) ...[
        const Notice(
          title: 'ต้องตั้งแอป authenticator ก่อน',
          body: 'บัญชีฝั่งผู้ให้บริการต้องยืนยันสองชั้นเสมอ ไม่มีทางปิด '
              'เพราะบัญชีเดียวเห็นข้อมูลธุรกิจของลูกค้าทุกราย',
          tone: Tone.warn,
        ),
        const SizedBox(height: Gap.xl),
        if (s.enrollmentSecret != null)
          CopyableValue(
              label: 'ความลับสำหรับพิมพ์ลงแอป', value: s.enrollmentSecret!),
        const SizedBox(height: Gap.lg),
        Text(
          'เปิดแอป authenticator แล้วเพิ่มบัญชีแบบกรอกรหัสด้วยตนเอง '
          'ตั้งเป็นแบบใช้เวลา (TOTP) หกหลัก แล้วกรอกรหัสที่ได้ด้านล่าง',
          style: t.bodySmall,
        ),
        const SizedBox(height: Gap.xl),
      ],
      GroupHeader(enrolling ? 'รหัสยืนยันจากแอป' : 'รหัสหกหลักจากแอป'),
      ConsoleField(
        controller: _code,
        hint: '000000',
        enabled: !_busy,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _submitCode(),
      ),
      const SizedBox(height: Gap.xxl),
      PrimaryButton(
        _busy ? 'กำลังยืนยัน' : (enrolling ? 'ยืนยันและเข้าใช้งาน' : 'ยืนยัน'),
        onPressed: _busy ? null : _submitCode,
      ),
      const SizedBox(height: Gap.md),
      PrimaryButton(
        'ยกเลิก',
        ghost: true,
        onPressed: _busy
            ? null
            : () {
                _code.clear();
                _password.clear();
                widget.session.expire();
              },
      ),
    ];
  }
}

/// ตั้งรหัสผ่านครั้งแรกด้วยรหัสตั้งค่าที่ได้รับมา
///
/// รหัสตั้งค่าออกให้ครั้งเดียว มีอายุหนึ่งชั่วโมง และใส่ผิดได้ห้าครั้ง —
/// ตัวนับอยู่ในฐานข้อมูลเพื่อให้นับข้าม instance ได้ (consume_platform_setup)
class PlatformSetupScreen extends StatefulWidget {
  const PlatformSetupScreen({super.key, required this.session});

  final PlatformSession session;

  @override
  State<PlatformSetupScreen> createState() => _PlatformSetupScreenState();
}

class _PlatformSetupScreenState extends State<PlatformSetupScreen> {
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _done;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await widget.session.claimSetup(
        user: _username.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      setState(() => _done = message);
    } on OfflineException {
      setState(() => _error = 'ต่อเซิร์ฟเวอร์ไม่ได้');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งรหัสผ่านครั้งแรก')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
            children: [
              Text(
                'ระบบไม่เคยตั้งรหัสผ่านให้ใคร ผู้ดูแลที่สร้างบัญชีให้ท่าน '
                'จะได้รับเพียงรหัสตั้งค่าที่ใช้ได้ครั้งเดียว จึงไม่มีทางรู้รหัสผ่านของท่าน',
                style: t.bodyMedium,
              ),
              const SizedBox(height: Gap.xl),
              const GroupHeader('ชื่อผู้ใช้'),
              ConsoleField(
                  controller: _username, enabled: !_busy, hint: 'vendor.owner'),
              const SizedBox(height: Gap.xl),
              const GroupHeader('รหัสตั้งค่า'),
              ConsoleField(
                  controller: _code, enabled: !_busy, hint: 'XXXX-XXXX'),
              const SizedBox(height: Gap.xl),
              const GroupHeader('รหัสผ่านใหม่'),
              ConsoleField(
                controller: _password,
                enabled: !_busy,
                obscure: true,
                hint: 'อย่างน้อย 12 ตัวอักษร',
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: Gap.xl),
                Notice(
                    title: 'ตั้งรหัสผ่านไม่สำเร็จ',
                    body: _error,
                    tone: Tone.crit),
              ],
              if (_done != null) ...[
                const SizedBox(height: Gap.xl),
                Notice(title: 'ตั้งรหัสผ่านแล้ว', body: _done, tone: Tone.ok),
              ],
              const SizedBox(height: Gap.xxl),
              PrimaryButton(
                _busy ? 'กำลังบันทึก' : 'ตั้งรหัสผ่าน',
                onPressed: _busy || _done != null ? null : _submit,
              ),
              if (_done != null) ...[
                const SizedBox(height: Gap.md),
                PrimaryButton(
                  'กลับไปเข้าสู่ระบบ',
                  ghost: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

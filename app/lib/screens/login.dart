import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/secure_store.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets.dart';

/// หน้าเข้าสู่ระบบ
///
/// ใช้รหัสประจำตัวกับรหัสผ่านที่งานทะเบียนออกให้ และบังคับเปลี่ยนรหัสผ่าน
/// ตอนเข้าครั้งแรก
///
/// เมื่อวิทยาลัยพร้อมใช้ ThaID หรือ Google Workspace ให้เพิ่มปุ่มที่หน้านี้
/// และเรียกเมธอดใหม่ใน Session ส่วนหน้าจออื่นไม่ต้องแก้ เพราะทุกหน้าอ่านข้อมูล
/// จาก Session เท่านั้น ไม่ได้ยุ่งกับวิธียืนยันตัวตน
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.deviceIdentity,
    required this.institutionId,
    required this.termId,
  });

  final Session session;
  final DeviceIdentity deviceIdentity;
  final String institutionId;
  final String termId;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    final password = _password.text;

    if (code.isEmpty || password.isEmpty) {
      setState(() => _error = 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final deviceId = await widget.deviceIdentity.get();
      await widget.session.signIn(
        institutionId: widget.institutionId,
        username: code,
        password: password,
        termId: widget.termId,
        deviceId: deviceId,
        deviceLabel: DeviceIdentity.label(),
        platform: DeviceIdentity.platform(),
      );
    } on OfflineException {
      setState(() => _error =
          'ติดต่อ API ไม่ได้ (${widget.session.api.baseUrl})\nตรวจสอบว่าเปิด API แล้วและใช้ URL ให้ตรงกับอุปกรณ์');
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
      body: Container(
        color: context.c.bg,
        child: Stack(children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 260,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF7668E8), Color(0xFF5548C8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(34)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Gap.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                    decoration: BoxDecoration(
                      color: context.c.sunk,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x330F0D2A),
                          blurRadius: 32,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _LoginBrand(),
                        const SizedBox(height: Gap.xxl),
                        /*
             * ─── ทำไมไม่ใช่แป้นตัวเลขและไม่ใช่คำว่า "รหัสประจำตัว" เฉย ๆ ───
             * ช่องนี้ถูกส่งไปเป็น `username` ซึ่งงานทะเบียนตั้งเป็นอะไรก็ได้
             * ผ่าน `POST /auth/credentials` — ไม่มีอะไรบังคับให้เป็นตัวเลข
             * และ**ผู้ปกครองไม่มีรหัสประจำตัวอยู่แล้ว** แป้นตัวเลขจึงแปลว่า
             * ผู้ปกครองบนโทรศัพท์พิมพ์ชื่อผู้ใช้ตัวเองไม่ได้เลยสักตัวอักษร
             */
                        const GroupHeader('รหัสประจำตัวหรือชื่อผู้ใช้'),
                        _Field(
                          controller: _code,
                          hint: '69201010001',
                          enabled: !_busy,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                        ),
                        const SizedBox(height: Gap.xl),
                        GroupHeader(
                          'รหัสผ่าน',
                          trailing: GestureDetector(
                            onTap: () => setState(() => _obscure = !_obscure),
                            child: Text(
                              _obscure ? 'แสดง' : 'ซ่อน',
                              style:
                                  t.bodySmall?.copyWith(color: context.c.sel),
                            ),
                          ),
                        ),
                        _Field(
                          controller: _password,
                          focusNode: _passwordFocus,
                          hint: '••••••••',
                          enabled: !_busy,
                          obscure: _obscure,
                          onSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Gap.xl),
                          Notice(
                              title: 'เข้าสู่ระบบไม่สำเร็จ',
                              body: _error,
                              tone: Tone.crit),
                        ],
                        const SizedBox(height: Gap.xxl),
                        PrimaryButton(
                          _busy ? 'กำลังตรวจสอบ' : 'เข้าสู่ระบบ',
                          onPressed: _busy ? null : _submit,
                        ),
                        const SizedBox(height: Gap.md),
                        PrimaryButton(
                          'ลืมรหัสผ่าน',
                          ghost: true,
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ForgotPasswordScreen(
                                        session: widget.session,
                                        institutionId: widget.institutionId,
                                        username: _code.text.trim(),
                                      ),
                                    ),
                                  ),
                        ),
                        const SizedBox(height: Gap.xl),
                        Text(
                          'รหัสผ่านชุดแรกออกโดยงานทะเบียน ระบบจะให้ตั้งรหัสใหม่ตอนเข้าครั้งแรก\n'
                          'บัญชีนี้ใช้ได้กับเครื่องเดียว การเปลี่ยนเครื่องต้องแจ้งงานทะเบียน',
                          style: t.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7668E8), Color(0xFF5548C8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.school_rounded, color: Colors.white, size: 32),
      ),
      const SizedBox(height: Gap.lg),
      Text('เข้าสู่ระบบ', style: t.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: Gap.xs),
      Text(
        'วิทยาลัยอาชีวศึกษา · สำหรับนักศึกษาและผู้ปกครอง',
        style: t.bodySmall,
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.enabled,
    this.focusNode,
    this.obscure = false,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool enabled, obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: keyboardType,
      style: t.bodyLarge?.copyWith(
        fontSize: 16,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          obscure ? Icons.lock_outline_rounded : Icons.person_outline_rounded,
          color: context.c.ink3,
        ),
      ),
      onSubmitted: onSubmitted,
    );
  }
}

/// ลืมรหัสผ่าน — ขอรหัสรีเซ็ตแล้วตั้งรหัสผ่านใหม่ด้วยตนเอง
///
/// ─── ทำไมเป็นรหัสสั้น ไม่ใช่ลิงก์ในอีเมล ───
/// นักศึกษาอาชีวะจำนวนมากไม่มีอีเมลของตัวเองตอนเข้าเรียน ลิงก์รีเซ็ตทาง
/// อีเมลจึงครอบคลุมคนไม่ถึงครึ่ง หน้านี้จึงรับรหัสสั้นที่มาได้สองทาง —
/// ระบบส่งให้เอง หรือเจ้าหน้าที่งานทะเบียนอ่านให้ฟังทางโทรศัพท์
///
/// ─── ทำไมมีสองขั้นในหน้าเดียว ───
/// ถ้าแยกเป็นสองหน้า คนที่ได้รหัสจากงานทะเบียนมาแล้วจะต้องผ่านหน้าขอรหัส
/// ก่อนโดยไม่จำเป็น และคนที่กดขอเองก็ต้องหาทางกลับเข้ามากรอกรหัสอีกรอบ
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.session,
    required this.institutionId,
    this.username = '',
  });

  final Session session;
  final String institutionId;

  /// รหัสประจำตัวที่พิมพ์ค้างไว้ที่หน้าเข้าสู่ระบบ — ไม่ต้องพิมพ์ซ้ำ
  final String username;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { request, enterCode, done }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _code = TextEditingController(text: widget.username);
  final _resetCode = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  _Step _step = _Step.request;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    _resetCode.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final username = _code.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'กรุณากรอกรหัสประจำตัว');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      final message = await widget.session.requestPasswordReset(
        institutionId: widget.institutionId,
        username: username,
      );
      setState(() {
        _info = message;
        _step = _Step.enterCode;
      });
    } on OfflineException {
      setState(() => _error = 'ต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบสัญญาณอินเทอร์เน็ต');
    } on ApiException catch (e) {
      // 503 แปลว่าวิทยาลัยนี้ยังไม่ได้เปิดช่องทางส่งอัตโนมัติ ซึ่งไม่ใช่
      // ความผิดพลาด แต่เป็นทางที่ต้องใช้งานทะเบียนแทน พาไปขั้นกรอกรหัสเลย
      // เพื่อให้คนที่โทรไปขอมาแล้วกรอกได้ทันทีโดยไม่ต้องหาทางเข้ามาใหม่
      setState(() {
        if (e.statusCode == 503) {
          _info = e.message;
          _step = _Step.enterCode;
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitReset() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'รหัสผ่านใหม่ทั้งสองช่องไม่ตรงกัน');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.session.resetPassword(
        institutionId: widget.institutionId,
        username: _code.text.trim(),
        code: _resetCode.text.trim(),
        newPassword: _next.text,
      );
      setState(() => _step = _Step.done);
    } on OfflineException {
      setState(() => _error = 'ต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบสัญญาณอินเทอร์เน็ต');
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
      appBar: AppBar(title: const Text('ลืมรหัสผ่าน')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xxl),
          children: switch (_step) {
            _Step.request => _requestFields(t),
            _Step.enterCode => _resetFields(t),
            _Step.done => _doneFields(t),
          },
        ),
      ),
    );
  }

  List<Widget> _requestFields(TextTheme t) => [
        const ScreenHeader(
          kicker: 'กู้คืนบัญชี',
          title: 'ขอรหัสรีเซ็ต',
          subtitle: 'ระบบจะส่งรหัสไปที่อีเมลหรือเบอร์โทรที่แจ้งไว้กับวิทยาลัย',
        ),
        const SizedBox(height: Gap.xxl),
        // ส่งเป็น `username` เหมือนหน้าเข้าสู่ระบบ จึงต้องพิมพ์ตัวอักษรได้ด้วย
        const GroupHeader('รหัสประจำตัวหรือชื่อผู้ใช้'),
        _Field(
          controller: _code,
          hint: '69201010001',
          enabled: !_busy,
          onSubmitted: (_) => _request(),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.xl),
          Notice(title: 'ขอรหัสไม่สำเร็จ', body: _error, tone: Tone.crit),
        ],
        const SizedBox(height: Gap.xxl),
        PrimaryButton(
          _busy ? 'กำลังส่ง' : 'ขอรหัสรีเซ็ต',
          onPressed: _busy ? null : _request,
        ),
        const SizedBox(height: Gap.md),
        PrimaryButton(
          'มีรหัสจากงานทะเบียนแล้ว',
          ghost: true,
          onPressed:
              _busy ? null : () => setState(() => _step = _Step.enterCode),
        ),
        const SizedBox(height: Gap.xl),
        Text(
          'ถ้าไม่มีอีเมลหรือเบอร์โทรบันทึกไว้ ให้ติดต่องานทะเบียนเพื่อขอรหัสรีเซ็ต '
          'เจ้าหน้าที่จะบอกรหัสให้ แต่จะไม่ทราบรหัสผ่านใหม่ที่ท่านตั้ง',
          style: t.bodySmall,
        ),
      ];

  List<Widget> _resetFields(TextTheme t) => [
        const ScreenHeader(
          kicker: 'กู้คืนบัญชี',
          title: 'ตั้งรหัสผ่านใหม่',
          subtitle: 'กรอกรหัสรีเซ็ตที่ได้รับ แล้วตั้งรหัสผ่านใหม่ของท่านเอง',
        ),
        if (_info != null) ...[
          const SizedBox(height: Gap.xl),
          Notice(title: 'รหัสรีเซ็ต', body: _info, tone: Tone.info),
        ],
        const SizedBox(height: Gap.xxl),
        const GroupHeader('รหัสประจำตัวหรือชื่อผู้ใช้'),
        _Field(
          controller: _code,
          hint: '69201010001',
          enabled: !_busy,
        ),
        const SizedBox(height: Gap.xl),
        const GroupHeader('รหัสรีเซ็ต'),
        _Field(
          controller: _resetCode,
          hint: 'ABCD-2345',
          enabled: !_busy,
          // ตัวพิมพ์เล็กหรือใหญ่ และมีขีดคั่นหรือไม่ ฝั่งเซิร์ฟเวอร์รับได้หมด
          // จึงไม่ต้องบังคับผู้ใช้ให้พิมพ์ตรงรูปแบบเป๊ะ ๆ
          keyboardType: TextInputType.visiblePassword,
        ),
        const SizedBox(height: Gap.xl),
        const GroupHeader('รหัสผ่านใหม่'),
        _Field(
          controller: _next,
          hint: 'อย่างน้อย 8 ตัวอักษร',
          enabled: !_busy,
          obscure: true,
        ),
        const SizedBox(height: Gap.xl),
        const GroupHeader('ยืนยันรหัสผ่านใหม่'),
        _Field(
          controller: _confirm,
          hint: '••••••••',
          enabled: !_busy,
          obscure: true,
          onSubmitted: (_) => _submitReset(),
        ),
        if (_error != null) ...[
          const SizedBox(height: Gap.xl),
          Notice(
              title: 'ตั้งรหัสผ่านใหม่ไม่สำเร็จ',
              body: _error,
              tone: Tone.crit),
        ],
        const SizedBox(height: Gap.xxl),
        PrimaryButton(
          _busy ? 'กำลังบันทึก' : 'ตั้งรหัสผ่านใหม่',
          onPressed: _busy ? null : _submitReset,
        ),
        const SizedBox(height: Gap.md),
        PrimaryButton(
          'ขอรหัสใหม่',
          ghost: true,
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = _Step.request;
                    _error = null;
                    _info = null;
                  }),
        ),
        const SizedBox(height: Gap.xl),
        Text(
          'รหัสรีเซ็ตใช้ได้ครั้งเดียวและหมดอายุใน 30 นาที '
          'กรอกผิดหลายครั้งรหัสจะถูกยกเลิกและต้องขอใหม่',
          style: t.bodySmall,
        ),
      ];

  List<Widget> _doneFields(TextTheme t) => [
        const ScreenHeader(
          kicker: 'กู้คืนบัญชี',
          title: 'ตั้งรหัสผ่านใหม่แล้ว',
          subtitle: 'เข้าสู่ระบบด้วยรหัสผ่านที่เพิ่งตั้งได้เลย',
        ),
        const SizedBox(height: Gap.xl),
        const Notice(
          title: 'ออกจากระบบทุกอุปกรณ์แล้ว',
          body:
              'เพื่อความปลอดภัย ระบบเพิกถอนการเข้าใช้งานของทุกเครื่องที่ค้างอยู่ '
              'ถ้าท่านสงสัยว่ามีคนอื่นใช้บัญชีนี้ ให้แจ้งงานทะเบียนด้วย',
          tone: Tone.ok,
        ),
        const SizedBox(height: Gap.xxl),
        PrimaryButton(
          'กลับไปหน้าเข้าสู่ระบบ',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ];
}

/// บังคับตั้งรหัสผ่านใหม่ตอนเข้าครั้งแรก
///
/// รหัสผ่านชุดแรกออกโดยเจ้าหน้าที่ จึงมีคนอื่นรู้เสมอ
/// การบังคับเปลี่ยนก่อนใช้งานจริงจึงเป็นขั้นตอนที่ข้ามไม่ได้
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.session});
  final Session session;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'รหัสผ่านใหม่ทั้งสองช่องไม่ตรงกัน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(_current.text, _next.text);
      // เปลี่ยนสำเร็จแล้วเซิร์ฟเวอร์เพิกถอนทุก session ผู้ใช้จะกลับไปหน้าเข้าสู่ระบบ
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xxl, Gap.lg, Gap.xxl),
          children: [
            const ScreenHeader(
              kicker: 'เข้าใช้ครั้งแรก',
              title: 'ตั้งรหัสผ่านใหม่',
              subtitle: 'รหัสชุดแรกออกโดยเจ้าหน้าที่ จึงต้องเปลี่ยนก่อนใช้งาน',
            ),
            const SizedBox(height: Gap.xxl),
            const GroupHeader('รหัสผ่านเดิม'),
            _Field(
                controller: _current,
                hint: '••••••••',
                enabled: !_busy,
                obscure: true),
            const SizedBox(height: Gap.xl),
            const GroupHeader('รหัสผ่านใหม่'),
            _Field(
                controller: _next,
                hint: 'อย่างน้อย 8 ตัวอักษร',
                enabled: !_busy,
                obscure: true),
            const SizedBox(height: Gap.xl),
            const GroupHeader('ยืนยันรหัสผ่านใหม่'),
            _Field(
                controller: _confirm,
                hint: '••••••••',
                enabled: !_busy,
                obscure: true),
            if (_error != null) ...[
              const SizedBox(height: Gap.xl),
              Notice(
                  title: 'เปลี่ยนรหัสผ่านไม่สำเร็จ',
                  body: _error,
                  tone: Tone.crit),
            ],
            const SizedBox(height: Gap.xxl),
            PrimaryButton(
              _busy ? 'กำลังบันทึก' : 'บันทึกรหัสผ่านใหม่',
              onPressed: _busy ? null : _submit,
            ),
            const SizedBox(height: Gap.xl),
            Text(
              'หลังเปลี่ยนรหัสผ่าน ระบบจะออกจากระบบทุกอุปกรณ์เพื่อความปลอดภัย '
              'แล้วให้เข้าสู่ระบบใหม่ด้วยรหัสที่เพิ่งตั้ง',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';

import 'platform_api.dart';

/// บทบาทของบัญชีผู้ให้บริการ — ตรงกับ enum platform_role ในฐานข้อมูล
enum PlatformRole {
  owner,
  billing,
  support;

  static PlatformRole parse(String? raw) => switch (raw) {
        'owner' => PlatformRole.owner,
        'billing' => PlatformRole.billing,
        _ => PlatformRole.support,
      };

  String get label => switch (this) {
        PlatformRole.owner => 'ผู้ดูแลระบบ',
        PlatformRole.billing => 'ฝ่ายบัญชี',
        PlatformRole.support => 'ฝ่ายสนับสนุน',
      };

  /// เขียนอะไรที่กระทบลูกค้าได้ไหม — ระงับ คืนสิทธิ์ ผูกแพ็กเกจ เปิดวิทยาลัย
  ///
  /// หน้าจอซ่อนปุ่มตามค่านี้เพื่อไม่ให้กดแล้วเจอ 403 แต่**ตัวที่บังคับจริง
  /// คือฝั่งเซิร์ฟเวอร์** (@PlatformRoles) การซ่อนปุ่มเป็นเรื่องของ UX
  /// ไม่ใช่มาตรการความปลอดภัย — ใครแก้ตัวแปรในเบราว์เซอร์ก็เห็นปุ่มได้
  bool get canWrite => this != PlatformRole.support;

  /// ดูแลบัญชีผู้ให้บริการด้วยกันเองได้ไหม
  bool get canManageUsers => this == PlatformRole.owner;
}

/// ขั้นตอนที่ผู้ใช้อยู่ตอนนี้
enum PlatformStage {
  /// ยังไม่ได้เข้าสู่ระบบ
  signedOut,

  /// ผ่านรหัสผ่านแล้ว แต่ยังไม่ได้ตั้งแอป authenticator
  needsEnrollment,

  /// ผ่านรหัสผ่านแล้ว รอใส่รหัสหกหลัก
  needsCode,

  /// เข้าใช้งานได้เต็มรูปแบบ
  ready,
}

/// สถานะการเข้าใช้งานของหน้าจอผู้ให้บริการ
///
/// ─── ทำไมไม่มีทางลัดข้ามชั้นที่สอง ───
/// เซิร์ฟเวอร์ไม่เคยคืน access token จากรหัสผ่านอย่างเดียวเลยสักกรณี
/// (ดู PlatformAuthService) คลาสนี้จึงไม่มีเส้นทางไหนที่ทำให้ stage
/// กลายเป็น ready ได้โดยไม่ผ่าน confirm หรือ verify
class PlatformSession extends ChangeNotifier {
  PlatformSession({required this.api});

  final PlatformApi api;

  PlatformStage stage = PlatformStage.signedOut;
  PlatformRole role = PlatformRole.support;
  String? username;
  String? displayName;

  /// token ชั่วคราวระหว่างรอยืนยันสองชั้น — ใช้ได้เฉพาะเส้นทางตั้งค่า MFA
  String? _challenge;

  /// ความลับ TOTP ที่เพิ่งออกให้ตอนตั้งค่า แสดงให้ผู้ใช้พิมพ์ลงแอป authenticator
  String? enrollmentSecret;
  String? enrollmentUri;

  bool get isSignedIn => stage == PlatformStage.ready && api.hasToken;

  /// เข้าสู่ระบบด้วยรหัสผ่าน — ได้แค่ challenge token เสมอ
  Future<void> signIn(String user, String password) async {
    final res = await api.post('/platform/login', {
      'username': user,
      'password': password,
    }) as Map<String, dynamic>;

    _challenge = res['challengeToken']?.toString();
    username = user;
    role = PlatformRole.parse(res['role']?.toString());

    if (_challenge == null) {
      // ถ้าวันหน้ามีใครแก้เซิร์ฟเวอร์ให้คืน token จริงจากรหัสผ่านอย่างเดียว
      // ให้หน้าจอนี้ปฏิเสธเสียงดัง ดีกว่าปล่อยผ่านเงียบ ๆ แล้วชั้นที่สองหายไป
      throw StateError('เซิร์ฟเวอร์ไม่ได้ส่ง challenge token กลับมา');
    }

    stage = res['enrollmentRequired'] == true
        ? PlatformStage.needsEnrollment
        : PlatformStage.needsCode;
    notifyListeners();
  }

  /// ขอความลับ TOTP ใหม่ — ยังไม่ถือว่าเปิดใช้จนกว่าจะยืนยันด้วยรหัสจริง
  Future<void> beginEnrollment() async {
    final res = await api.postAs(_challenge!, '/platform/mfa/enroll')
        as Map<String, dynamic>;
    enrollmentUri = res['otpauthUri']?.toString();
    enrollmentSecret = _secretOf(enrollmentUri);
    notifyListeners();
  }

  /// ยืนยันรหัสครั้งแรก — สำเร็จแล้วได้ token จริงเลย ไม่ต้องล็อกอินใหม่
  Future<void> confirmEnrollment(String code) async {
    final res =
        await api.postAs(_challenge!, '/platform/mfa/confirm', {'code': code})
            as Map<String, dynamic>;
    _adopt(res);
  }

  /// แลก challenge token + รหัสจากแอป เป็น token จริง
  Future<void> verifyCode(String code) async {
    final res = await api.post('/platform/mfa/verify', {
      'challengeToken': _challenge,
      'code': code,
    }) as Map<String, dynamic>;
    _adopt(res);
  }

  void _adopt(Map<String, dynamic> res) {
    api.setTokens(
      access: res['accessToken']?.toString(),
      refresh: res['refreshToken']?.toString(),
    );
    role = PlatformRole.parse(res['role']?.toString());
    displayName = res['displayName']?.toString();
    username = res['username']?.toString() ?? username;
    _challenge = null;
    enrollmentSecret = null;
    enrollmentUri = null;
    stage = PlatformStage.ready;
    notifyListeners();
  }

  /// ตั้งรหัสผ่านครั้งแรกด้วยรหัสตั้งค่าที่ผู้ดูแลออกให้
  Future<String> claimSetup({
    required String user,
    required String code,
    required String newPassword,
  }) async {
    final res = await api.post('/platform/setup', {
      'username': user,
      'code': code,
      'newPassword': newPassword,
    }) as Map<String, dynamic>;
    return res['message']?.toString() ?? 'ตั้งรหัสผ่านแล้ว';
  }

  Future<void> signOut() async {
    final refresh = api.refreshToken;
    if (refresh != null) {
      try {
        await api.post('/platform/logout', {'refreshToken': refresh});
      } catch (_) {
        // ตั้งใจกลืนข้อผิดพลาด — การออกจากระบบต้องสำเร็จเสมอในมุมของผู้ใช้
        // และ token ในหน่วยความจำหายไปพร้อมหน้าเว็บอยู่แล้ว
      }
    }
    api.clear();
    stage = PlatformStage.signedOut;
    _challenge = null;
    enrollmentSecret = null;
    enrollmentUri = null;
    displayName = null;
    notifyListeners();
  }

  /// ถูกเตะออกเพราะ token หมดอายุ — กลับไปหน้าเข้าสู่ระบบโดยไม่ต้องยิงอะไร
  void expire() {
    api.clear();
    stage = PlatformStage.signedOut;
    _challenge = null;
    notifyListeners();
  }

  static String? _secretOf(String? uri) {
    if (uri == null) return null;
    final m = RegExp(r'secret=([A-Z2-7]+)').firstMatch(uri);
    return m?.group(1);
  }
}

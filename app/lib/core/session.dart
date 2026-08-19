import 'package:flutter/foundation.dart';
import 'api.dart';

/// สถานะการเข้าใช้งานของแอป
///
/// ใช้ ChangeNotifier ที่มากับ Flutter เอง ไม่พึ่งไลบรารีจัดการสถานะภายนอก
/// เพราะสถานะของแอปนี้มีไม่กี่ตัวและอายุยาว การลดจำนวนไลบรารีทำให้อัปเกรด
/// Flutter รุ่นถัดไปได้โดยไม่ต้องรอไลบรารีตามมา
class Session extends ChangeNotifier {
  Session({required this.api, required KeyValueStore store}) : _store = store;

  final ApiClient api;
  final KeyValueStore _store;

  String? studentId;
  String? termId;
  String? displayName;
  String? studentCode;
  String? programName;
  bool mustChangePassword = false;

  /// บทบาทที่เซิร์ฟเวอร์คืนมาตอนเข้าสู่ระบบ
  ///
  /// แอปตัวเดียวใช้ได้ทั้งนักศึกษาและผู้ปกครอง แต่แท็บไม่เหมือนกัน —
  /// ผู้ปกครองเช็คอินแทนลูกไม่ได้และไม่ต้องบันทึกชั่วโมงฝึกอาชีพ
  ///
  /// เก็บไว้เพื่อเลือกหน้าจอเท่านั้น **ไม่ใช่มาตรการความปลอดภัย** —
  /// สิทธิ์จริงมาจาก token และ RLS ฝั่งเซิร์ฟเวอร์ ผู้ปกครองที่แก้ค่านี้
  /// ในเครื่องตัวเองจะเห็นแท็บเพิ่ม แต่ทุกคำขอยังถูกปฏิเสธเหมือนเดิม
  String? role;

  bool get isGuardianMode => role == 'guardian';

  bool get isSignedIn => api.token != null && studentId != null;

  void handleUnauthorized() {
    studentId = null;
    termId = null;
    notifyListeners();
  }

  static const _kStudent = 'session.studentId';
  static const _kTerm = 'session.termId';
  static const _kName = 'session.name';
  static const _kCode = 'session.code';
  static const _kProgram = 'session.program';
  static const _kMustChange = 'session.mustChange';
  static const _kRole = 'session.role';

  Future<void> restore() async {
    await api.loadToken();
    studentId = await _store.read(_kStudent);
    termId = await _store.read(_kTerm);
    displayName = await _store.read(_kName);
    studentCode = await _store.read(_kCode);
    programName = await _store.read(_kProgram);
    mustChangePassword = (await _store.read(_kMustChange)) == '1';
    role = await _store.read(_kRole);
    notifyListeners();
  }

  /// เข้าสู่ระบบด้วยรหัสประจำตัวและรหัสผ่าน
  ///
  /// ส่งตัวระบุอุปกรณ์ไปด้วยเสมอ ฝั่งเซิร์ฟเวอร์ผูกบัญชีนักศึกษาไว้กับเครื่องเดียว
  /// การเข้าจากเครื่องใหม่จะถูกปฏิเสธจนกว่างานทะเบียนจะอนุมัติ
  /// ซึ่งเป็นมาตรการกันการยืมบัญชีกันเช็คอินแทน
  Future<void> signIn({
    required String institutionId,
    required String username,
    required String password,
    required String termId,
    required String deviceId,
    String? deviceLabel,
    String? platform,
  }) async {
    final res = await api.post('/auth/login', {
      'institutionId': institutionId,
      'username': username,
      'password': password,
      'deviceId': deviceId,
      if (deviceLabel != null) 'deviceLabel': deviceLabel,
      if (platform != null) 'platform': platform,
    }) as Map<String, dynamic>;

    await api.setTokens(
      access: res['accessToken'].toString(),
      refresh: res['refreshToken'].toString(),
    );
    mustChangePassword = res['mustChangePassword'] == true;
    await _store.write(_kMustChange, mustChangePassword ? '1' : '0');
    role = res['role']?.toString();
    if (role != null) await _store.write(_kRole, role!);

    /*
     * ─── ห้ามหาตัวเองด้วยการเทียบชื่อผู้ใช้กับรหัสประจำตัว ───
     * `GET /students` ถูก RLS กรองมาแล้วว่าบัญชีนี้เห็นใครได้บ้าง — นักศึกษา
     * เห็นแถวเดียวคือตัวเอง ผู้ปกครองเห็นเฉพาะบุตรที่ผูกและยืนยันแล้ว
     * คำถาม "คนนี้คือใคร" เซิร์ฟเวอร์ตอบไปแล้ว แอปต้องไม่ตอบใหม่เอง
     *
     * เดิมเทียบ `student_code == username` ซึ่งเดาว่าชื่อผู้ใช้**คือ**รหัส
     * ประจำตัวเสมอ แต่ `POST /auth/credentials` ให้งานทะเบียนตั้งชื่อผู้ใช้
     * เป็นอะไรก็ได้ และไม่มีอะไรในระบบบังคับข้อตกลงนั้นสักชั้นเดียว ผลคือ
     *   · นักศึกษาที่ชื่อผู้ใช้ไม่ตรงรหัส เข้าไม่ได้เลยทั้งที่รหัสผ่านถูก
     *   · **ผู้ปกครองเข้าไม่ได้เลยสักคน** เพราะชื่อผู้ใช้ของผู้ปกครอง
     *     ไม่มีวันเท่ากับรหัสประจำตัวของบุตร — โหมดผู้ปกครองทั้งโหมด
     *     จึงไม่เคยมีใครเข้าถึงได้
     * ทั้งสองอาการโผล่เป็น "ไม่พบข้อมูลนักศึกษาของรหัสนี้" หลังล็อกอินผ่านแล้ว
     * ซึ่งอ่านเหมือนข้อมูลหาย ไม่เหมือนแอปเทียบผิดช่อง
     */
    final students = (await api.get('/students') as List<dynamic>)
        .cast<Map<String, dynamic>>();
    if (students.isEmpty) {
      throw ApiException(
          404, 'บัญชีนี้ยังไม่ได้ผูกกับนักศึกษาคนใด ติดต่องานทะเบียน');
    }
    // ผู้ปกครองที่มีบุตรหลายคนยังเห็นได้ทีละคน — ทั้งแอปถือ studentId เดียว
    final me = students.first;

    studentId = me['id'].toString();
    displayName = me['full_name']?.toString();
    studentCode = me['student_code']?.toString();
    programName = me['program_name']?.toString();
    this.termId = termId;

    await _store.write(_kStudent, studentId!);
    await _store.write(_kTerm, termId);
    if (displayName != null) await _store.write(_kName, displayName!);
    if (studentCode != null) await _store.write(_kCode, studentCode!);
    if (programName != null) await _store.write(_kProgram, programName!);

    notifyListeners();
  }

  /// ล้างข้อมูลทั้งหมดออกจากเครื่อง
  ///
  /// โทรศัพท์ของนักศึกษาถูกยืมและถูกขโมยบ่อย การออกจากระบบจึงต้องลบ
  /// ทั้ง token และข้อมูลที่แคชไว้ ไม่ใช่แค่ลืม token
  Future<void> changePassword(String current, String next) async {
    await api.post('/auth/change-password', {
      'currentPassword': current,
      'newPassword': next,
    });
    // เซิร์ฟเวอร์เพิกถอนทุก session หลังเปลี่ยนรหัสผ่าน ต้องเข้าสู่ระบบใหม่
    await signOut();
  }

  /// ขอรหัสรีเซ็ตรหัสผ่าน
  ///
  /// ไม่ต้องเข้าสู่ระบบก่อน และคืนข้อความที่เซิร์ฟเวอร์เขียนไว้ให้แสดงตรง ๆ
  /// ข้อความนั้นเหมือนกันทุกกรณีโดยเจตนา — ถ้าต่างกันระหว่าง "ส่งแล้ว" กับ
  /// "ไม่พบบัญชี" ใครก็ตามที่ยิงรายการรหัสประจำตัวเข้ามาจะได้รายชื่อบัญชี
  /// ที่มีอยู่จริงทั้งวิทยาลัยกลับไป แอปจึงต้องไม่ตีความหรือเดาเพิ่มเอง
  Future<String> requestPasswordReset({
    required String institutionId,
    required String username,
  }) async {
    final res = await api.post('/auth/forgot-password', {
      'institutionId': institutionId,
      'username': username,
    }) as Map<String, dynamic>;
    return res['message']?.toString() ??
        'ถ้ามีบัญชีนี้อยู่ ระบบได้ส่งรหัสรีเซ็ตไปให้แล้ว';
  }

  /// ใช้รหัสรีเซ็ตตั้งรหัสผ่านใหม่ โดยไม่ต้องรู้รหัสผ่านเดิม
  ///
  /// สำเร็จแล้วเซิร์ฟเวอร์เพิกถอนทุก session จึงต้องล้างของที่ค้างในเครื่องด้วย
  /// เผื่อกรณีที่เครื่องนี้ยังมี token เก่าค้างอยู่จากบัญชีเดียวกัน
  Future<void> resetPassword({
    required String institutionId,
    required String username,
    required String code,
    required String newPassword,
  }) async {
    await api.post('/auth/reset-password', {
      'institutionId': institutionId,
      'username': username,
      'code': code,
      'newPassword': newPassword,
    });
    if (isSignedIn) await signOut();
  }

  Future<void> signOut() async {
    await api.signOut();
    for (final k in [
      _kStudent,
      _kTerm,
      _kName,
      _kCode,
      _kProgram,
      _kMustChange,
      _kRole
    ]) {
      await _store.remove(k);
    }
    studentId = null;
    termId = null;
    displayName = null;
    studentCode = null;
    programName = null;
    mustChangePassword = false;
    role = null;
    notifyListeners();
  }
}

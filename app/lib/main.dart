import 'package:flutter/material.dart';

import 'core/api.dart';
import 'core/secure_store.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'screens/login.dart';
import 'screens/shell.dart';

/// ค่าที่ต้องตั้งตอนสร้างแอปให้แต่ละวิทยาลัย
///
/// ส่งผ่าน --dart-define ตอน build เพื่อไม่ต้องแก้โค้ด
///   flutter build apk --dart-define=API_BASE_URL=https://api.example.ac.th/api/v1
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
  static const institutionId = String.fromEnvironment(
    'INSTITUTION_ID',
    defaultValue: '11111111-1111-1111-1111-111111111111',
  );
  static const termId = String.fromEnvironment(
    'TERM_ID',
    defaultValue: '33333333-3333-3333-3333-333333333331',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await SecureStore.open();
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl, store: store)
    ..setInstitution(AppConfig.institutionId);
  final session = Session(api: api, store: store);
  await session.restore();

  runApp(VecSmsApp(session: session, deviceIdentity: DeviceIdentity(store)));
}

class VecSmsApp extends StatelessWidget {
  const VecSmsApp({super.key, required this.session, required this.deviceIdentity});
  final Session session;
  final DeviceIdentity deviceIdentity;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'วิทยาลัยอาชีวศึกษา',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // ผู้ปกครองจำนวนมากตั้งตัวอักษรใหญ่ จำกัดเพดานไว้ไม่ให้เลย์เอาต์พัง
      // แต่ยังรองรับถึงสองเท่าตามหลักการเข้าถึงได้
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 2.0,
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.isSignedIn) {
            return LoginScreen(
              session: session,
              deviceIdentity: deviceIdentity,
              institutionId: AppConfig.institutionId,
              termId: AppConfig.termId,
            );
          }
          // รหัสผ่านชุดแรกมีเจ้าหน้าที่รู้ด้วยเสมอ จึงต้องเปลี่ยนก่อนเข้าใช้จริง
          if (session.mustChangePassword) {
            return ChangePasswordScreen(session: session);
          }
          return AppShell(session: session);
        },
      ),
    );
  }
}

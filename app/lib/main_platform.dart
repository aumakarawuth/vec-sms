import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'platform/platform_api.dart';
import 'platform/platform_session.dart';
import 'platform/screens/platform_login.dart';
import 'platform/screens/platform_shell.dart';

/// จุดเริ่มของ **แอปผู้ให้บริการ** — คนละแอปกับที่ส่งให้วิทยาลัย
///
/// ─── ทำไมเป็นคนละ entrypoint ไม่ใช่หน้าจอในแอปเดิม ───
/// แอปเดิมถูกส่งให้นักศึกษาและผู้ปกครองทุกวิทยาลัย ถ้าหน้าจอผู้ให้บริการ
/// อยู่ในบันเดิลเดียวกัน ทุกเครื่องที่ติดตั้งแอปจะมีหน้าล็อกอินของระบบ
/// หลังบ้านติดไปด้วย ซึ่งเป็นพื้นที่โจมตีที่ไม่จำเป็นและเป็นแผนที่ให้ผู้โจมตี
/// เห็นว่าระบบหลังบ้านมีอะไรบ้าง
///
/// สร้างด้วย
///   flutter build web -t lib/main_platform.dart \
///     --dart-define=API_BASE_URL=https://api.example.ac.th/api/v1 \
///     --output build/platform
///
/// แล้ว deploy ไปคนละโดเมนกับแอปของวิทยาลัย (หรือหลัง VPN ของผู้ให้บริการ)
class PlatformConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ไม่มีการอ่าน token ที่เก็บไว้ เพราะไม่เคยเก็บลงเครื่อง (ดู PlatformApi)
  final session = PlatformSession(
    api: PlatformApi(baseUrl: PlatformConfig.apiBaseUrl),
  );

  runApp(PlatformConsoleApp(session: session));
}

class PlatformConsoleApp extends StatelessWidget {
  const PlatformConsoleApp({super.key, required this.session});

  final PlatformSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ผู้ดูแลข้ามวิทยาลัย',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => session.isSignedIn
            ? PlatformShell(session: session)
            : PlatformLoginScreen(session: session),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vec_sms_app/core/api.dart';
import 'package:vec_sms_app/core/theme.dart';
import 'package:vec_sms_app/platform/platform_api.dart';
import 'package:vec_sms_app/platform/platform_session.dart';
import 'package:vec_sms_app/platform/screens/audit.dart';
import 'package:vec_sms_app/platform/screens/institutions.dart';
import 'package:vec_sms_app/platform/screens/platform_login.dart';
import 'package:vec_sms_app/platform/screens/users.dart';
import 'package:vec_sms_app/widgets.dart';

/// เซิร์ฟเวอร์จำลองที่ตอบตามเส้นทาง — คืนสถานะได้ด้วยเพื่อทดสอบ 401
MockClient mockPlatform(
  Map<String, Object?> routes, {
  Map<String, int> status = const {},
  void Function(String path)? onCall,
}) {
  return MockClient((req) async {
    final path = '${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}'
        .replaceFirst('/api/v1', '');
    onCall?.call(path);
    for (final entry in routes.entries) {
      if (path.startsWith(entry.key)) {
        return http.Response(
          jsonEncode(entry.value),
          status[entry.key] ?? 200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }
    return http.Response(
      jsonEncode({'statusCode': 404, 'message': 'ไม่พบข้อมูล'}),
      404,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

PlatformSession makeSession(
  MockClient client, {
  PlatformRole role = PlatformRole.owner,
  bool signedIn = true,
}) {
  final session = PlatformSession(
    api: PlatformApi(baseUrl: '/api/v1', httpClient: client),
  );
  if (signedIn) {
    session.api.setTokens(access: 'access-token', refresh: 'refresh-token');
    session.stage = PlatformStage.ready;
    session.role = role;
    session.username = 'vendor.owner';
    session.displayName = 'เจ้าของระบบ';
  }
  return session;
}

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  // ── ขอบเขตของบทบาท ────────────────────────────────────────────────
  group('บทบาทฝั่งผู้ให้บริการ', () {
    test('PLATAPP-01 อ่านบทบาทจากเซิร์ฟเวอร์และรู้ว่าใครเขียนอะไรได้', () {
      expect(PlatformRole.parse('owner'), PlatformRole.owner);
      expect(PlatformRole.parse('billing'), PlatformRole.billing);
      // ค่าที่ไม่รู้จักต้องตกไปที่สิทธิ์ต่ำสุดเสมอ ไม่ใช่สิทธิ์สูงสุด
      expect(PlatformRole.parse('ไม่รู้จัก'), PlatformRole.support);
      expect(PlatformRole.parse(null), PlatformRole.support);

      expect(PlatformRole.owner.canWrite, isTrue);
      expect(PlatformRole.billing.canWrite, isTrue);
      expect(PlatformRole.support.canWrite, isFalse);
      expect(PlatformRole.billing.canManageUsers, isFalse);
      expect(PlatformRole.owner.canManageUsers, isTrue);
    });
  });

  // ── การเข้าสู่ระบบสองชั้น ──────────────────────────────────────────
  group('การเข้าสู่ระบบของผู้ให้บริการ', () {
    test('PLATAPP-02 รหัสผ่านอย่างเดียวไม่เคยทำให้เข้าใช้งานได้', () async {
      final session = makeSession(
        mockPlatform({
          '/platform/login': {
            'mfaRequired': true,
            'enrollmentRequired': false,
            'role': 'billing',
            'challengeToken': 'challenge-1',
          },
        }),
        signedIn: false,
      );

      await session.signIn('vendor.billing', 'รหัสผ่านที่ถูกต้อง');

      expect(session.stage, PlatformStage.needsCode);
      expect(session.isSignedIn, isFalse,
          reason: 'ผ่านรหัสผ่านแล้วยังต้องไม่ถือว่าเข้าระบบได้');
      expect(session.api.hasToken, isFalse, reason: 'ยังต้องไม่มี access token');
      expect(session.role, PlatformRole.billing);
    });

    test('PLATAPP-03 บัญชีที่ยังไม่ตั้ง MFA ถูกพาไปขั้นตั้งค่า', () async {
      final session = makeSession(
        mockPlatform({
          '/platform/login': {
            'mfaRequired': true,
            'enrollmentRequired': true,
            'role': 'owner',
            'challengeToken': 'challenge-2',
          },
          '/platform/mfa/enroll': {
            'otpauthUri': 'otpauth://totp/VEC?secret=JBSWY3DPEHPK3PXP&issuer=VEC',
          },
        }),
        signedIn: false,
      );

      await session.signIn('vendor.owner', 'รหัสผ่าน');
      expect(session.stage, PlatformStage.needsEnrollment);

      await session.beginEnrollment();
      expect(session.enrollmentSecret, 'JBSWY3DPEHPK3PXP',
          reason: 'ต้องดึงความลับออกจาก otpauth URI มาให้ผู้ใช้พิมพ์ลงแอปได้');
      expect(session.isSignedIn, isFalse);
    });

    test('PLATAPP-04 ยืนยันรหัสครั้งแรกแล้วได้ token จริงเลย', () async {
      final session = makeSession(
        mockPlatform({
          '/platform/login': {
            'mfaRequired': true,
            'enrollmentRequired': true,
            'role': 'owner',
            'challengeToken': 'challenge-3',
          },
          '/platform/mfa/enroll': {'otpauthUri': 'otpauth://totp/x?secret=ABCDEFGH'},
          '/platform/mfa/confirm': {
            'accessToken': 'real-token',
            'refreshToken': 'real-refresh',
            'role': 'owner',
            'displayName': 'เจ้าของระบบ',
            'username': 'vendor.owner',
          },
        }),
        signedIn: false,
      );

      await session.signIn('vendor.owner', 'รหัสผ่าน');
      await session.beginEnrollment();
      await session.confirmEnrollment('123456');

      // บทเรียนจาก 0036 ข้อ 6 — ตั้งค่าเสร็จต้องเข้าใช้งานได้เลย
      // ไม่ใช่ให้กลับไปล็อกอินใหม่แล้วเสี่ยงติดอยู่วงนอก
      expect(session.isSignedIn, isTrue);
      expect(session.api.accessToken, 'real-token');
      expect(session.displayName, 'เจ้าของระบบ');
      expect(session.enrollmentSecret, isNull,
          reason: 'ความลับต้องถูกลบออกจากหน่วยความจำหลังตั้งค่าเสร็จ');
    });

    test('PLATAPP-05 เซิร์ฟเวอร์ที่ข้ามชั้นที่สองต้องถูกปฏิเสธเสียงดัง', () async {
      // ถ้าวันหน้ามีใครแก้ฝั่งเซิร์ฟเวอร์ให้คืน token จริงจากรหัสผ่านอย่างเดียว
      // แอปต้องไม่ยอมรับเงียบ ๆ มิฉะนั้นชั้นที่สองหายไปโดยไม่มีอะไรฟ้อง
      final session = makeSession(
        mockPlatform({
          '/platform/login': {'accessToken': 'ไม่ควรได้แบบนี้', 'role': 'owner'},
        }),
        signedIn: false,
      );

      await expectLater(
        session.signIn('vendor.owner', 'รหัสผ่าน'),
        throwsA(isA<StateError>()),
      );
      expect(session.isSignedIn, isFalse);
    });

    test('PLATAPP-06 ออกจากระบบล้าง token ทิ้งทั้งหมด', () async {
      final session = makeSession(mockPlatform({'/platform/logout': {'revoked': 1}}));
      expect(session.api.hasToken, isTrue);

      await session.signOut();

      expect(session.api.hasToken, isFalse);
      expect(session.api.refreshToken, isNull);
      expect(session.stage, PlatformStage.signedOut);
    });
  });

  // ── ตัวเชื่อม API ─────────────────────────────────────────────────
  group('การเชื่อมต่อของหน้าจอผู้ให้บริการ', () {
    test('PLATAPP-07 token หมดอายุแล้วหมุนใหม่อัตโนมัติหนึ่งครั้ง', () async {
      final calls = <String>[];
      var firstTry = true;

      final client = MockClient((req) async {
        final path = req.url.path.replaceFirst('/api/v1', '');
        calls.add(path);

        if (path == '/platform/refresh') {
          return http.Response(
            jsonEncode({'accessToken': 'ใหม่', 'refreshToken': 'ใหม่กว่า'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (path == '/platform/institutions' && firstTry) {
          firstTry = false;
          return http.Response(
            jsonEncode({'statusCode': 401, 'message': 'หมดอายุ'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({'rows': []}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final session = makeSession(client);
      final data = await session.api.get('/platform/institutions');

      expect(data, isA<Map<String, dynamic>>());
      expect(calls, [
        '/platform/institutions',
        '/platform/refresh',
        '/platform/institutions',
      ]);
      expect(session.api.accessToken, 'ใหม่');
    });

    test('PLATAPP-08 หมุน token ไม่สำเร็จได้ข้อความภาษาไทยที่บอกให้เข้าใหม่', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({'statusCode': 401, 'message': 'token ไม่ถูกต้อง'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));
      final session = makeSession(client);

      await expectLater(
        session.api.get('/platform/institutions'),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('เข้าสู่ระบบใหม่'),
        )),
      );
    });
  });

  // ── หน้าจอ ────────────────────────────────────────────────────────
  group('หน้าจอผู้ให้บริการ', () {
    testWidgets('PLATAPP-09 หน้าเข้าสู่ระบบบอกขอบเขตของบัญชีตั้งแต่หน้าแรก',
        (tester) async {
      final session = makeSession(mockPlatform({}), signedIn: false);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: PlatformLoginScreen(session: session),
      ));

      expect(find.text('หน้าจอผู้ดูแลข้ามวิทยาลัย'), findsOneWidget);
      expect(
        find.textContaining('ไม่มีสิทธิ์อ่านข้อมูลนักศึกษา'),
        findsOneWidget,
        reason: 'ผู้ใช้ต้องเห็นตั้งแต่หน้าแรกว่าบัญชีนี้ทำอะไรไม่ได้บ้าง',
      );
      expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    });

    testWidgets('PLATAPP-10 รายชื่อวิทยาลัยขึ้นสถานะระงับและเกินโควตา',
        (tester) async {
      final session = makeSession(mockPlatform({
        '/platform/institutions': {
          'institutions': 2,
          'suspended': 1,
          'unassigned': 0,
          'overQuota': 1,
          'note': 'ตัวเลขมาจากภาพนิ่ง',
          'rows': [
            {
              'id': '11111111-1111-1111-1111-111111111111',
              'code': '1312345678',
              'name_th': 'วิทยาลัยเทคโนโลยีทดสอบ',
              'plan_code': 'standard',
              'plan_name_th': 'มาตรฐาน',
              'students_active': 480,
              'over_students': 30,
              'usage_taken_on': '2026-08-09',
              'suspended_at': null,
            },
            {
              'id': '22222222-2222-2222-2222-222222222222',
              'code': '1398765432',
              'name_th': 'วิทยาลัยอาชีวศึกษาทดสอบ',
              'plan_code': null,
              'plan_name_th': null,
              'students_active': 120,
              'over_students': 0,
              'usage_taken_on': null,
              'suspended_at': '2026-08-01T00:00:00Z',
              'suspended_reason': 'ค้างชำระ',
            },
          ],
        },
      }));

      await tester.pumpWidget(wrap(InstitutionsScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.textContaining('วิทยาลัยเทคโนโลยีทดสอบ'), findsOneWidget);
      expect(find.text('เกินโควตา 30 คน'), findsOneWidget);
      // ต้องหาที่ป้ายสถานะของแถว ไม่ใช่ที่คำอธิบายตัวเลขสรุปด้านบน
      // ซึ่งใช้คำเดียวกัน — find.text เฉย ๆ จะเจอทั้งสองที่แล้วเทสต์ผ่าน
      // ทั้งที่ป้ายในแถวหายไป
      expect(find.widgetWithText(StatusDot, 'ถูกระงับ'), findsOneWidget);
      // ต้องบอกว่าตัวเลขมาจากภาพนิ่ง ไม่ใช่ค่าสด มิฉะนั้นจะเข้าใจผิดตอนออกบิล
      expect(find.textContaining('ภาพนิ่ง'), findsWidgets);
    });

    testWidgets('PLATAPP-11 บัญชีอ่านอย่างเดียวไม่เห็นปุ่มที่กระทบลูกค้า',
        (tester) async {
      Map<String, Object?> detail() => {
            '/platform/institutions/': {
              'institution': {
                'id': '11111111-1111-1111-1111-111111111111',
                'code': '1312345678',
                'name_th': 'วิทยาลัยเทคโนโลยีทดสอบ',
                'suspended_at': null,
              },
              'subscriptions': [],
              'usage': [],
              'provisioning': [],
              'actions': [],
            },
          };

      // ระดับ support — ต้องไม่มีปุ่มระงับ
      final support = makeSession(mockPlatform(detail()), role: PlatformRole.support);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: InstitutionDetailScreen(
          session: support,
          institutionId: '11111111-1111-1111-1111-111111111111',
          title: 'วิทยาลัยเทคโนโลยีทดสอบ',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ระงับการใช้งาน'), findsNothing);

      // ระดับ billing — ต้องมี
      final billing = makeSession(mockPlatform(detail()), role: PlatformRole.billing);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: InstitutionDetailScreen(
          session: billing,
          institutionId: '11111111-1111-1111-1111-111111111111',
          title: 'วิทยาลัยเทคโนโลยีทดสอบ',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ระงับการใช้งาน'), findsOneWidget);
    });

    testWidgets('PLATAPP-12 หน้าบัญชีผู้ดูแลปิดสำหรับบทบาทที่ไม่ใช่ owner',
        (tester) async {
      final session = makeSession(mockPlatform({}), role: PlatformRole.billing);
      await tester.pumpWidget(wrap(PlatformUsersScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.textContaining('ต้องเป็นระดับ owner'), findsOneWidget);
      expect(find.text('สร้างบัญชีใหม่'), findsNothing);
    });

    testWidgets('PLATAPP-13 บันทึกการกระทำแสดงเป็นภาษาไทยพร้อมผู้กระทำ',
        (tester) async {
      final session = makeSession(mockPlatform({
        '/platform/audit': [
          {
            'username': 'vendor.owner',
            'action': 'suspend_institution',
            'detail': {'reason': 'ค้างชำระ'},
            'occurred_at': '2026-08-09T10:30:00Z',
            'institution_code': '1312345678',
            'institution_name': 'วิทยาลัยเทคโนโลยีทดสอบ',
          },
          {
            'username': 'vendor.owner',
            'action': 'การกระทำที่ยังไม่ได้แปล',
            'detail': {},
            'occurred_at': '2026-08-09T09:00:00Z',
          },
        ],
      }));

      await tester.pumpWidget(wrap(PlatformAuditScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('ระงับการใช้งาน'), findsOneWidget);
      expect(find.textContaining('vendor.owner'), findsWidgets);
      // การกระทำที่ยังไม่มีคำแปลต้องแสดงค่าดิบ ไม่ใช่หายไปจากรายการ
      expect(find.text('การกระทำที่ยังไม่ได้แปล'), findsOneWidget);
      expect(
        find.textContaining('แก้ไม่ได้และลบไม่ได้'),
        findsOneWidget,
      );
    });

    testWidgets('PLATAPP-14 หน้าจอบอกว่าอ่านข้อมูลของวิทยาลัยไม่ได้', (tester) async {
      // ข้อความนี้ไม่ใช่การตกแต่ง — เป็นสิ่งที่ทำให้คนใช้งานรู้ว่าจะขอให้
      // ผู้ให้บริการ "เข้าไปดูให้หน่อย" ไม่ได้ ซึ่งเป็นคำขอที่เกิดขึ้นจริง
      final session = makeSession(mockPlatform({}), signedIn: false);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: PlatformLoginScreen(session: session),
      ));

      expect(find.byType(ScreenHeader), findsOneWidget);
      expect(find.textContaining('บันทึกพร้อมชื่อบัญชี'), findsOneWidget);
    });
  });
}

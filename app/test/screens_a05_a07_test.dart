import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vec_sms_app/core/api.dart';
import 'package:vec_sms_app/core/secure_store.dart';
import 'package:vec_sms_app/core/session.dart';
import 'package:vec_sms_app/core/theme.dart';
import 'package:vec_sms_app/screens/checkin.dart';
import 'package:vec_sms_app/screens/guardian.dart';
import 'package:vec_sms_app/screens/practicum.dart';
import 'package:vec_sms_app/widgets.dart';

const _sid = '10000000-0000-0000-0000-000000000011';

MockClient mockApi(Map<String, Object?> routes, {Map<String, int> status = const {}}) {
  return MockClient((req) async {
    final path = '${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}'
        .replaceFirst('/api/v1', '');
    for (final entry in routes.entries) {
      if (path.startsWith(entry.key)) {
        return http.Response(jsonEncode(entry.value), status[entry.key] ?? 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
    }
    return http.Response(
      jsonEncode({'statusCode': 404, 'message': 'ไม่พบข้อมูล'}),
      404,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

Session makeSession(MockClient client, {String role = 'student'}) {
  final store = MemoryStore();
  final api = ApiClient(baseUrl: '/api/v1', store: store, httpClient: client);
  return Session(api: api, store: store)
    ..studentId = _sid
    ..termId = '33333333-3333-3333-3333-333333333331'
    ..displayName = 'ปิยะพงศ์ ศรีสุข'
    ..studentCode = '69201010001'
    ..role = role;
}

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  group('A-05 เช็คอิน', () {
    testWidgets('APP-25 หน้าจอบอกชัดว่ายังไม่ใช่การบันทึกเวลาเรียน',
        (tester) async {
      /*
       * ข้อความนี้ไม่ใช่การตกแต่ง — 0039 ปิดช่องที่นักศึกษาแก้เวลาเรียน
       * ของตัวเองได้ ปุ่มเช็คอินจึงต้องไม่ทำให้ผู้ใช้เข้าใจว่าเช็คชื่อสำเร็จแล้ว
       * มิฉะนั้นคนจะเลิกไปหาครูเมื่อครูยังไม่ยืนยัน แล้วขาดเรียนโดยไม่รู้ตัว
       */
      final session = makeSession(mockApi({
        '/students/$_sid/schedule': [
          {
            'meeting_id': 'aaaa1111-1111-1111-1111-111111111111',
            'enrollment_id': 'bbbb2222-2222-2222-2222-222222222222',
            'course_name': 'งานเครื่องยนต์เล็ก',
            'period_from': 3,
            'room': 'โรงฝึกงานช่างยนต์',
            'checkin_status': null,
          },
        ],
      }));

      await tester.pumpWidget(wrap(CheckinScreen(
        session: session,
        deviceIdentity: DeviceIdentity(MemoryStore()),
      )));
      await tester.pumpAndSettle();

      expect(find.text('เช็คอินเข้าเรียน'), findsOneWidget);
      expect(find.textContaining('เมื่อครูผู้สอนยืนยัน'), findsOneWidget);
      expect(find.textContaining('ไม่ใช่การบันทึกเวลาเรียนเอง'), findsOneWidget);
      expect(find.text('เช็คอิน'), findsOneWidget);
    });

    testWidgets('APP-26 คาบที่ส่งคำขอแล้วขึ้นว่ารอครูยืนยัน และไม่มีปุ่มซ้ำ',
        (tester) async {
      final session = makeSession(mockApi({
        '/students/$_sid/schedule': [
          {
            'meeting_id': 'aaaa1111-1111-1111-1111-111111111111',
            'enrollment_id': 'bbbb2222-2222-2222-2222-222222222222',
            'course_name': 'งานเครื่องยนต์เล็ก',
            'period_from': 3,
            'checkin_status': 'pending',
          },
        ],
      }));

      await tester.pumpWidget(wrap(CheckinScreen(
        session: session,
        deviceIdentity: DeviceIdentity(MemoryStore()),
      )));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(StatusDot, 'รอครูยืนยัน'), findsOneWidget);
      // กดซ้ำไม่ได้ — ฐานข้อมูลกันไว้อยู่แล้ว แต่ปุ่มที่กดแล้วไม่เกิดอะไร
      // ทำให้ผู้ใช้กดรัวจนคิดว่าระบบพัง
      expect(find.text('เช็คอิน'), findsNothing);
    });

    testWidgets('APP-27 วันที่ไม่มีคาบเรียนบอกตรง ๆ ไม่ใช่หน้าว่าง', (tester) async {
      final session = makeSession(mockApi({'/students/$_sid/schedule': []}));

      await tester.pumpWidget(wrap(CheckinScreen(
        session: session,
        deviceIdentity: DeviceIdentity(MemoryStore()),
      )));
      await tester.pumpAndSettle();

      expect(find.text('วันนี้ไม่มีคาบเรียน'), findsOneWidget);
    });
  });

  group('A-06 ฝึกอาชีพ', () {
    testWidgets('APP-28 แยกชั่วโมงที่รับรองแล้วออกจากที่รอรับรอง',
        (tester) async {
      /*
       * กฎการจบนับเฉพาะชั่วโมงที่ครูนิเทศรับรองแล้ว ถ้าหน้าจอรวมสองอย่าง
       * เป็นตัวเลขเดียว นักศึกษาจะเข้าใจว่าครบแล้วทั้งที่ยังไม่ครบ
       * แล้วไปรู้ตอนตรวจจบซึ่งสายเกินแก้
       */
      final session = makeSession(mockApi({
        '/practicum/students/$_sid': {
          'verified_hours': 120,
          'pending_hours': 40,
          'required_hours': 320,
          'logs': [
            {'worked_on': '2026-08-01', 'hours': 8, 'verified_at': '2026-08-02'},
            {'worked_on': '2026-08-08', 'hours': 8, 'verified_at': null},
          ],
        },
      }));

      await tester.pumpWidget(wrap(PracticumScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('120'), findsOneWidget);
      expect(find.text('ชั่วโมงที่รับรองแล้ว'), findsOneWidget);
      expect(find.text('รอครูรับรอง'), findsOneWidget);
      expect(find.textContaining('เหลืออีก 200 ชั่วโมง'), findsOneWidget);
      expect(find.textContaining('ยังไม่ถูกนับในเกณฑ์การจบ'), findsOneWidget);
    });

    testWidgets('APP-29 บอกว่านักศึกษาแก้เองไม่ได้', (tester) async {
      final session = makeSession(mockApi({
        '/practicum/students/$_sid': {
          'verified_hours': 0, 'pending_hours': 0, 'logs': [],
        },
      }));

      await tester.pumpWidget(wrap(PracticumScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.textContaining('นักศึกษาแก้ไขเองไม่ได้'), findsOneWidget);
    });
  });

  group('A-07 โหมดผู้ปกครอง', () {
    testWidgets('APP-30 เห็นเฉพาะเรื่องที่ได้รับสิทธิ์ ส่วนที่เหลือบอกเหตุผล',
        (tester) async {
      /*
       * ข้อนี้คือหัวใจของหน้าจอ — ผู้ปกครองที่ได้สิทธิ์ดูเวลาเรียนแต่ไม่ได้
       * สิทธิ์ดูการเงิน ต้องยังเห็นเวลาเรียน ไม่ใช่เจอหน้าว่างทั้งหน้า
       * เพราะคำขอเดียวถูกปฏิเสธ
       */
      final session = makeSession(
        mockApi(
          {
            '/students/$_sid/attendance': [
              {'pct_to_date': '82.5', 'absences_left': 2},
            ],
            '/students/$_sid/balance': {'statusCode': 403, 'message': 'ไม่มีสิทธิ์'},
            '/students/$_sid/graduation': {'statusCode': 403, 'message': 'ไม่มีสิทธิ์'},
          },
          status: {
            '/students/$_sid/balance': 403,
            '/students/$_sid/graduation': 403,
          },
        ),
        role: 'guardian',
      );

      await tester.pumpWidget(wrap(GuardianScreen(session: session)));
      await tester.pumpAndSettle();

      // เรื่องที่ได้รับสิทธิ์ต้องแสดง
      expect(find.text('82.5%'), findsOneWidget);
      expect(find.text('2 คาบ'), findsOneWidget);

      // เรื่องที่ยังไม่ได้รับสิทธิ์ต้องบอกว่า "ยังไม่ได้รับสิทธิ์"
      // ไม่ใช่ "ไม่มีข้อมูล" — สองอย่างนี้ต่างกันสำหรับผู้ปกครอง
      expect(find.widgetWithText(Notice, 'ยังไม่ได้รับสิทธิ์ดูข้อมูลการเงิน'),
          findsOneWidget);
      expect(find.widgetWithText(Notice, 'ยังไม่ได้รับสิทธิ์ดูผลการเรียน'),
          findsOneWidget);
    });

    testWidgets('APP-31 หน้าผู้ปกครองอ่านอย่างเดียว ไม่มีปุ่มแก้อะไรเลย',
        (tester) async {
      final session = makeSession(
        mockApi({
          '/students/$_sid/attendance': [
            {'pct_to_date': '95.0', 'absences_left': 8},
          ],
          '/students/$_sid/balance': {'balance': '0', 'next_due_on': null},
          '/students/$_sid/graduation': {'gpax': '3.25', 'credits_earned': 42},
        }),
        role: 'guardian',
      );

      await tester.pumpWidget(wrap(GuardianScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('3.25'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('อ่านอย่างเดียว'), findsOneWidget);
    });
  });
}

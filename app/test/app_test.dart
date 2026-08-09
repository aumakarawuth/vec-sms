import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:vec_sms_app/core/api.dart';
import 'package:vec_sms_app/core/fmt.dart';
import 'package:vec_sms_app/core/session.dart';
import 'package:vec_sms_app/core/theme.dart';
import 'package:vec_sms_app/models.dart';
import 'package:vec_sms_app/screens/attendance.dart';
import 'package:vec_sms_app/screens/finance.dart';
import 'package:vec_sms_app/screens/graduation.dart';
import 'package:vec_sms_app/screens/login.dart';
import 'package:vec_sms_app/widgets.dart';

const _term = '33333333-3333-3333-3333-333333333331';
const _sid = '10000000-0000-0000-0000-000000000011';

/// เซิร์ฟเวอร์จำลองที่ตอบเหมือน API จริง รวมถึงส่งค่า numeric เป็นสตริง
MockClient mockApi({
  Map<String, Object?> routes = const {},
  Set<String> offline = const {},
}) {
  return MockClient((req) async {
    final path = '${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}'
        .replaceFirst('/api/v1', '');
    if (offline.any(path.startsWith)) {
      throw const SocketExceptionStub();
    }
    for (final entry in routes.entries) {
      if (path.startsWith(entry.key)) {
        return http.Response(jsonEncode(entry.value), 200,
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

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

Session makeSession(MockClient client, {KeyValueStore? store}) {
  final s = store ?? MemoryStore();
  final api = ApiClient(baseUrl: '/api/v1', store: s, httpClient: client);
  final session = Session(api: api, store: s)
    ..studentId = _sid
    ..termId = _term
    ..displayName = 'ปิยะพงศ์ ศรีสุข'
    ..studentCode = '69201010001'
    ..programName = 'ช่างยนต์';
  return session;
}

Widget wrap(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  // ── การจัดรูปแบบข้อมูล ────────────────────────────────────────────
  group('การแปลงค่าและรูปแบบไทย', () {
    test('APP-01 อ่านค่า numeric ที่ PostgreSQL ส่งมาเป็นสตริงได้', () {
      // pg ส่ง numeric กลับมาเป็นสตริงเสมอ ถ้าอ่านไม่รองรับแอปจะพังเงียบ ๆ
      expect(Fmt.toNum('12600.00'), 12600.0);
      expect(Fmt.toNum(12600), 12600);
      expect(Fmt.toNum(null), isNull);
      expect(Fmt.toNum('ไม่ใช่ตัวเลข'), isNull);
    });

    test('APP-02 วันที่ใช้ปีพุทธศักราชเสมอ', () {
      final d = DateTime(2026, 8, 8);
      expect(Fmt.dateFull(d), '8 สิงหาคม 2569');
      expect(Fmt.dateShort(d), '8 ส.ค. 2569');
      expect(Fmt.dateWithWeekday(d), startsWith('เสาร์'));
    });

    test('APP-03 จำนวนเงินและเปอร์เซ็นต์', () {
      expect(Fmt.money('12600.00'), '฿12,600');
      expect(Fmt.money(null), '—');
      expect(Fmt.percent('84.5'), '84.5%');
    });

    test('APP-04 บอกอายุข้อมูลที่แคชไว้', () {
      final now = DateTime(2026, 8, 8, 12, 0);
      expect(Fmt.ago(now.subtract(const Duration(seconds: 30)), now: now), 'เมื่อสักครู่');
      expect(Fmt.ago(now.subtract(const Duration(minutes: 12)), now: now), '12 นาทีที่แล้ว');
      expect(Fmt.ago(now.subtract(const Duration(hours: 3)), now: now), '3 ชั่วโมงที่แล้ว');
    });
  });

  // ── ตัวเชื่อม API ─────────────────────────────────────────────────
  group('การเชื่อมต่อ API', () {
    test('APP-05 ส่งข้อความผิดพลาดภาษาไทยจากเซิร์ฟเวอร์ต่อให้ผู้ใช้', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'statusCode': 422,
              'message': 'ลงทะเบียนไม่ได้ ติดเงื่อนไขต่อไปนี้\n[HOLD_FINANCE] ค้างชำระ',
            }),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));
      final api = ApiClient(baseUrl: '', store: MemoryStore(), httpClient: client);

      expect(
        () => api.get('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 422)
            .having((e) => e.message, 'message', contains('ค้างชำระ'))),
      );
    });

    test('APP-06 รวมรายการข้อผิดพลาดจาก ValidationPipe เป็นข้อความเดียว', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'statusCode': 400,
              'message': ['studentId ต้องเป็นรหัสรูปแบบ UUID', 'termId ห้ามว่าง'],
            }),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));
      final api = ApiClient(baseUrl: '', store: MemoryStore(), httpClient: client);
      try {
        await api.get('/x');
        fail('ควรโยนข้อผิดพลาด');
      } on ApiException catch (e) {
        expect(e.message, contains('UUID'));
        expect(e.message, contains('termId'));
      }
    });

    test('APP-07 ต่อไม่ได้ให้ใช้ข้อมูลที่แคชไว้แทนหน้าจอว่าง', () async {
      final store = MemoryStore();
      var online = true;
      final client = MockClient((req) async {
        if (!online) throw const SocketExceptionStub();
        return http.Response(
          jsonEncode([
            {'code': '20101-2003', 'name_th': 'งานเครื่องยนต์เล็ก', 'pct_projected': '94.4'}
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = ApiClient(baseUrl: '', store: store, httpClient: client);

      final first = await api.getCached('/students/x/attendance');
      expect(first.fromCache, isFalse);

      online = false;
      final second = await api.getCached('/students/x/attendance');
      expect(second.fromCache, isTrue, reason: 'ต้องหยิบข้อมูลเก่ามาแสดง');
      expect((second.data as List).length, 1);
      expect(second.cachedAt, isNotNull);
    });

    test('APP-08 ออฟไลน์และไม่เคยมีข้อมูลเลย ต้องแจ้งผู้ใช้ ไม่ใช่เงียบ', () async {
      final api = ApiClient(
        baseUrl: '',
        store: MemoryStore(),
        httpClient: MockClient((_) async => throw const SocketExceptionStub()),
      );
      expect(() => api.getCached('/x'), throwsA(isA<OfflineException>()));
    });

    test('APP-09 ออกจากระบบแล้วลบทั้ง token และข้อมูลที่แคชไว้', () async {
      final store = MemoryStore();
      final client = MockClient((req) async => http.Response(
            jsonEncode([
              {'code': 'X', 'name_th': 'วิชา', 'pct_projected': '90'}
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));
      final api = ApiClient(baseUrl: '', store: store, httpClient: client);
      await api.setTokens(access: 'abc', refresh: 'def', institutionId: 'inst-1');
      await store.write('session.studentId', _sid);

      await api.getCached('/students/x/attendance');
      expect(await store.read('cache:/students/x/attendance'), isNotNull);

      final session = Session(api: api, store: store)..studentId = _sid;
      await session.signOut();

      expect(await store.read('auth.token'), isNull);
      expect(await store.read('auth.refresh'), isNull);
      expect(await store.read('session.studentId'), isNull);
      // แคชมีผลการเรียนและยอดค้างชำระ ต้องลบด้วย ไม่ใช่แค่ลืม token
      expect(await store.read('cache:/students/x/attendance'), isNull,
          reason: 'ต้องลบข้อมูลที่แคชไว้ด้วย');
      expect(session.isSignedIn, isFalse);
    });

    test('APP-09b access token หมดอายุแล้วต่ออายุเองและยิงซ้ำ', () async {
      final store = MemoryStore();
      final calls = <String>[];
      var accessValid = false;

      final client = MockClient((req) async {
        final path = req.url.path;
        calls.add(path);

        if (path.endsWith('/auth/refresh')) {
          accessValid = true;
          return http.Response(
            jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (!accessValid) {
          return http.Response(
            jsonEncode({'statusCode': 401, 'message': 'หมดอายุ'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final api = ApiClient(baseUrl: '', store: store, httpClient: client);
      await api.setTokens(access: 'old', refresh: 'r1', institutionId: 'inst-1');

      final res = await api.get('/students') as Map<String, dynamic>;
      expect(res['ok'], isTrue);
      expect(calls, ['/students', '/auth/refresh', '/students'],
          reason: 'ต้องต่ออายุแล้วยิงคำขอเดิมซ้ำหนึ่งครั้ง');
      expect(await store.read('auth.token'), 'new-access');
      expect(await store.read('auth.refresh'), 'new-refresh');
    });

    test('APP-09c คำขอหลายรายการพร้อมกันต้องต่ออายุครั้งเดียว', () async {
      // ถ้ายิง refresh พร้อมกันหลายครั้ง ครั้งหลังจะเจอ token ที่ถูกหมุนไปแล้ว
      // เซิร์ฟเวอร์จะตีความว่าเป็นการใช้ token ซ้ำและเตะผู้ใช้ออกทันที
      final store = MemoryStore();
      var refreshCalls = 0;
      var accessValid = false;

      final client = MockClient((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          accessValid = true;
          return http.Response(
            jsonEncode({'accessToken': 'a2', 'refreshToken': 'r2'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (!accessValid) {
          return http.Response(
            jsonEncode({'statusCode': 401, 'message': 'หมดอายุ'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final api = ApiClient(baseUrl: '', store: store, httpClient: client);
      await api.setTokens(access: 'a1', refresh: 'r1', institutionId: 'inst-1');

      await Future.wait([
        api.get('/students'),
        api.get('/students/x/balance'),
        api.get('/students/x/graduation'),
      ]);

      expect(refreshCalls, 1, reason: 'ต้องต่ออายุครั้งเดียวแม้มีสามคำขอพร้อมกัน');
    });
  });

  // ── ตรรกะของโมเดล ────────────────────────────────────────────────
  group('ตรรกะการตรวจจบ', () {
    test('APP-10 กฎแบบนับถอยหลังตีความกลับด้าน', () {
      // สามกฎนี้ค่าที่ได้คือ "จำนวนที่ยังค้าง" ยิ่งน้อยยิ่งดี
      final pending = GraduationRule.fromJson({
        'kind': 'cocurricular_all_terms',
        'name_th': 'กิจกรรมเสริมหลักสูตร',
        'required': '0',
        'achieved': '2',
        'satisfied': false,
        'is_blocking': true,
      });
      expect(pending.isCountdown, isTrue);
      expect(pending.progress, 0);

      final credits = GraduationRule.fromJson({
        'kind': 'credits_total',
        'name_th': 'หน่วยกิตรวม',
        'required': '106',
        'achieved': '42',
        'satisfied': false,
        'is_blocking': true,
      });
      expect(credits.isCountdown, isFalse);
      expect(credits.progress, closeTo(0.396, 0.01));
    });

    test('APP-11 หางวดถัดไปที่ต้องจ่าย', () {
      final inv = Invoice.fromJson({
        'id': 'x',
        'invoice_no': 'INV-2569-000001',
        'total': '12600.00',
        'paid_total': '4200.00',
        'outstanding': '8400.00',
        'status': 'partially_paid',
        'ref1': '69201010001',
        'ref2': '2569000001',
        'installments': [
          {'seq': 1, 'amount': '4200.00', 'paid_amount': '4200.00', 'status': 'paid'},
          {'seq': 2, 'amount': '4200.00', 'paid_amount': '0', 'status': 'pending'},
          {'seq': 3, 'amount': '4200.00', 'paid_amount': '0', 'status': 'pending'},
        ],
      });
      expect(inv.nextDue?.seq, 2);
      expect(inv.nextDue?.remaining, 4200.0);
      expect(inv.installments.first.isPaid, isTrue);
    });
  });

  // ── หน้าจอ ────────────────────────────────────────────────────────
  group('หน้าจอแอป', () {
    testWidgets('APP-12 หน้าเวลาเรียนบอกจำนวนคาบที่ขาดได้อีก', (tester) async {
      final session = makeSession(mockApi(routes: {
        '/students/$_sid/attendance': [
          {
            'code': '20101-2003',
            'name_th': 'งานเครื่องยนต์เล็ก',
            'pct_to_date': '80.00',
            'pct_projected': '84.00',
            'absences_left': 2,
            'attendance_state': 'warning',
            'min_pct': '80.00',
          },
          {
            'code': '20000-1401',
            'name_th': 'คณิตศาสตร์ช่างอุตสาหกรรม',
            'pct_to_date': '96.00',
            'pct_projected': '98.00',
            'absences_left': 9,
            'attendance_state': 'ok',
            'min_pct': '80.00',
          },
        ],
      }));

      await tester.pumpWidget(wrap(AttendanceScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('84.0%'), findsOneWidget);
      expect(find.textContaining('ขาดได้อีก 2 คาบเท่านั้น'), findsOneWidget);
      expect(find.text('เวลาเรียนของฉัน'), findsOneWidget);
      // วิชาที่แย่ที่สุดต้องขึ้นก่อน
      expect(find.textContaining('งานเครื่องยนต์เล็ก'), findsWidgets);
    });

    testWidgets('APP-13 หน้าเวลาเรียนเตือนเมื่อหมดสิทธิ์สอบแล้ว', (tester) async {
      final session = makeSession(mockApi(routes: {
        '/students/$_sid/attendance': [
          {
            'code': '20101-2003',
            'name_th': 'งานเครื่องยนต์เล็ก',
            'pct_to_date': '70.00',
            'pct_projected': '77.50',
            'absences_left': 0,
            'attendance_state': 'discretion',
            'min_pct': '80.00',
          },
        ],
      }));

      await tester.pumpWidget(wrap(AttendanceScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.textContaining('ต่ำกว่าเกณฑ์แล้ว'), findsOneWidget);
      expect(find.textContaining('ยื่นคำร้อง'), findsWidgets);
    });

    testWidgets('APP-14 หน้าการจบแสดงเงื่อนไขครบทุกข้อ', (tester) async {
      final session = makeSession(mockApi(routes: {
        '/students/$_sid/graduation': [
          {'kind': 'credits_total', 'name_th': 'หน่วยกิตสะสมรวม', 'required': '106',
           'achieved': '42', 'satisfied': false, 'is_blocking': true},
          {'kind': 'gpax_min', 'name_th': 'GPAX ไม่ต่ำกว่า 2.00', 'required': '2.00',
           'achieved': '2.94', 'satisfied': true, 'is_blocking': true},
          {'kind': 'cocurricular_all_terms', 'name_th': 'กิจกรรมเสริมหลักสูตร',
           'required': '0', 'achieved': '1', 'satisfied': false, 'is_blocking': true},
        ],
      }));

      await tester.pumpWidget(wrap(GraduationScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('เส้นทางสู่การจบ'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('2.94'), findsOneWidget);
      expect(find.textContaining('ผ่านแล้ว 1 จาก 3'), findsOneWidget);
      expect(find.text('ค้าง 1'), findsOneWidget);
    });

    testWidgets('APP-15 หน้าการเงินแสดงงวดถัดไปและเลขอ้างอิงพร้อมเพย์', (tester) async {
      final session = makeSession(mockApi(routes: {
        '/students/$_sid/invoices': [
          {
            'id': 'i1',
            'invoice_no': 'INV-2569-000001',
            'due_on': '2026-06-10',
            'total': '12600.00',
            'paid_total': '4200.00',
            'outstanding': '8400.00',
            'status': 'partially_paid',
            'ref1': '69201010001',
            'ref2': '2569000001',
            'installments': [
              {'seq': 1, 'due_on': '2026-06-10', 'amount': '4200.00',
               'paid_amount': '4200.00', 'status': 'paid'},
              {'seq': 2, 'due_on': '2026-08-09', 'amount': '4200.00',
               'paid_amount': '0', 'status': 'pending'},
            ],
          },
        ],
      }));

      await tester.pumpWidget(wrap(FinanceScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('฿4,200'), findsWidgets);
      expect(find.textContaining('งวดที่ 2'), findsWidgets);
      expect(find.text('2569000001'), findsOneWidget);
      expect(find.text('69201010001'), findsOneWidget);
      expect(find.text('จ่ายแล้ว'), findsOneWidget);
    });

    testWidgets('APP-16 ออฟไลน์แล้วยังเห็นข้อมูลเก่าพร้อมแถบแจ้ง', (tester) async {
      final store = MemoryStore();
      var online = true;
      final client = MockClient((req) async {
        if (!online) throw const SocketExceptionStub();
        return http.Response(
          jsonEncode([
            {
              'code': '20101-2003',
              'name_th': 'งานเครื่องยนต์เล็ก',
              'pct_to_date': '90.00',
              'pct_projected': '95.00',
              'absences_left': 5,
              'attendance_state': 'ok',
              'min_pct': '80.00',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final session = makeSession(client, store: store);
      // โหลดครั้งแรกตอนออนไลน์เพื่อให้มีข้อมูลในแคช
      await tester.pumpWidget(wrap(AttendanceScreen(session: session)));
      await tester.pumpAndSettle();
      expect(find.textContaining('ต่อเซิร์ฟเวอร์ไม่ได้'), findsNothing);

      // ตัดสัญญาณแล้วเปิดใหม่
      online = false;
      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pumpWidget(wrap(AttendanceScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.textContaining('กำลังแสดงข้อมูลที่บันทึกไว้'), findsOneWidget);
      expect(find.text('95.0%'), findsOneWidget);
    });

    testWidgets('APP-17 ผิดพลาดจริงต้องแสดงข้อความและปุ่มลองใหม่', (tester) async {
      final session = makeSession(MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 403, 'message': 'ไม่มีสิทธิ์ดูข้อมูลนี้'}),
            403,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )));

      await tester.pumpWidget(wrap(AttendanceScreen(session: session)));
      await tester.pumpAndSettle();

      expect(find.text('เปิดข้อมูลไม่สำเร็จ'), findsOneWidget);
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    });

    testWidgets('APP-18 สถานะแยกด้วยรูปทรง ไม่พึ่งสีอย่างเดียว', (tester) async {
      await tester.pumpWidget(wrap(const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusDot('ปกติ', tone: Tone.ok),
          StatusDot('เฝ้าระวัง', tone: Tone.warn),
          StatusDot('วิกฤต', tone: Tone.crit),
        ],
      )));
      await tester.pump();

      // ทุกระดับวาดด้วย CustomPaint คนละรูปทรง
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('ปกติ'), findsOneWidget);
      expect(find.text('วิกฤต'), findsOneWidget);
    });

    testWidgets('APP-19 รองรับตัวอักษรใหญ่สองเท่าโดยเลย์เอาต์ไม่พัง', (tester) async {
      final session = makeSession(mockApi(routes: {
        '/students/$_sid/attendance': [
          {
            'code': '20101-2003',
            'name_th': 'งานเครื่องยนต์เล็ก',
            'pct_to_date': '80.00',
            'pct_projected': '84.00',
            'absences_left': 2,
            'attendance_state': 'warning',
            'min_pct': '80.00',
          },
        ],
      }));

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(body: AttendanceScreen(session: session)),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('เวลาเรียนของฉัน'), findsOneWidget);
    });

    testWidgets('APP-20 ธีมมืดใช้ได้ทั้งแอป', (tester) async {
      final session = makeSession(mockApi(routes: {
        '/students/$_sid/graduation': [
          {'kind': 'gpax_min', 'name_th': 'GPAX', 'required': '2.00',
           'achieved': '2.94', 'satisfied': true, 'is_blocking': true},
        ],
      }));

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: GraduationScreen(session: session)),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('ผ่าน'), findsOneWidget);
    });
  });

  group('ลืมรหัสผ่าน', () {
    /// เซิร์ฟเวอร์จำลองที่คุมสถานะตอบกลับได้ และจดคำขอที่ได้รับไว้ตรวจสอบ
    MockClient resetApi({
      int forgot = 201,
      String forgotMessage = 'ถ้ามีบัญชีนี้อยู่และมีอีเมลหรือเบอร์โทรบันทึกไว้ '
          'ระบบได้ส่งรหัสรีเซ็ตไปให้แล้ว',
      int reset = 201,
      String resetMessage = 'ตั้งรหัสผ่านใหม่เรียบร้อย',
      List<Map<String, dynamic>>? seen,
    }) {
      return MockClient((req) async {
        final path = req.url.path.replaceFirst('/api/v1', '');
        seen?.add({'path': path, 'body': jsonDecode(req.body)});
        final json = {'content-type': 'application/json; charset=utf-8'};

        if (path.endsWith('/auth/forgot-password')) {
          return http.Response(
            jsonEncode({'requested': true, 'message': forgotMessage}),
            forgot,
            headers: json,
          );
        }
        if (path.endsWith('/auth/reset-password')) {
          return http.Response(
            jsonEncode({'reset': reset < 300, 'message': resetMessage}),
            reset,
            headers: json,
          );
        }
        return http.Response(jsonEncode({'message': 'ไม่พบข้อมูล'}), 404, headers: json);
      });
    }

    Future<void> pumpForgot(WidgetTester tester, Session session) async {
      // จอทดสอบมาตรฐานสูง 600 พิกเซล ซึ่งสั้นกว่าฟอร์มขั้นตั้งรหัสผ่านใหม่
      // ช่องล่าง ๆ กับปุ่มจะไม่ถูกสร้างเลยเพราะ ListView สร้างเฉพาะที่มองเห็น
      // ขยายจอแทนการเลื่อนทีละขั้น เพื่อให้เทสต์ยังอ่านว่าทดสอบพฤติกรรมอะไร
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ForgotPasswordScreen(
          session: session,
          institutionId: '11111111-1111-1111-1111-111111111111',
          username: '69201010001',
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('APP-21 ขอรหัสแล้วแสดงข้อความจากเซิร์ฟเวอร์ตรง ๆ ไม่ตีความเอง', (tester) async {
      // ข้อความนี้เหมือนกันทั้งกรณีที่มีบัญชีและไม่มีโดยเจตนา ถ้าแอปเดา
      // แล้วเขียนข้อความของตัวเอง เช่น "ส่งไปที่อีเมลของคุณแล้ว" จะกลาย
      // เป็นตัวบอกว่ารหัสประจำตัวไหนมีอยู่จริง ซึ่งเป็นสิ่งที่ฝั่งเซิร์ฟเวอร์
      // อุตส่าห์ปิดไว้
      final seen = <Map<String, dynamic>>[];
      await pumpForgot(tester, makeSession(resetApi(seen: seen)));

      await tester.tap(find.widgetWithText(PrimaryButton, 'ขอรหัสรีเซ็ต'));
      await tester.pumpAndSettle();

      expect(seen.single['path'], '/auth/forgot-password');
      expect((seen.single['body'] as Map)['username'], '69201010001');
      expect(find.textContaining('ถ้ามีบัญชีนี้อยู่'), findsOneWidget);
      expect(find.text('ตั้งรหัสผ่านใหม่'), findsWidgets,
          reason: 'ต้องพาไปขั้นกรอกรหัสต่อทันที ไม่ใช่ค้างอยู่หน้าเดิม');
    });

    testWidgets('APP-22 วิทยาลัยที่ยังไม่เปิดช่องทางส่ง ต้องพาไปกรอกรหัสจากงานทะเบียน',
        (tester) async {
      // 503 ที่นี่ไม่ใช่ความผิดพลาด แต่แปลว่า "ต้องใช้ทางงานทะเบียนแทน"
      // ถ้าแอปแสดงเป็นข้อผิดพลาดสีแดงแล้วจบ ผู้ใช้จะไม่รู้ว่ายังมีทางออก
      // และเป็นกรณีเริ่มต้นของทุกวิทยาลัยที่ยังไม่ได้ผูกผู้ให้บริการอีเมล
      await pumpForgot(
        tester,
        makeSession(resetApi(
          forgot: 503,
          forgotMessage: 'วิทยาลัยนี้ยังไม่ได้เปิดการรีเซ็ตรหัสผ่านด้วยตนเอง '
              'กรุณาติดต่องานทะเบียนเพื่อขอรหัสรีเซ็ต',
        )),
      );

      await tester.tap(find.widgetWithText(PrimaryButton, 'ขอรหัสรีเซ็ต'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ติดต่องานทะเบียน'), findsWidgets);
      expect(find.text('รหัสรีเซ็ต'), findsWidgets,
          reason: 'ต้องมีช่องกรอกรหัสให้เลย เพราะผู้ใช้จะโทรไปขอแล้วกลับมากรอก');
      expect(find.widgetWithText(PrimaryButton, 'ตั้งรหัสผ่านใหม่'), findsOneWidget);
    });

    testWidgets('APP-23 รหัสผ่านสองช่องไม่ตรงกันต้องบอกก่อน ไม่ยิงคำขอทิ้ง', (tester) async {
      // รหัสรีเซ็ตใช้ได้ครั้งเดียวและมีโควตาการกรอกผิด การปล่อยให้ยิงไป
      // ทั้งที่รู้อยู่แล้วว่าจะพลาด เท่ากับเผาโควตาของผู้ใช้ไปฟรี ๆ
      final seen = <Map<String, dynamic>>[];
      await pumpForgot(tester, makeSession(resetApi(seen: seen)));

      await tester.tap(find.widgetWithText(PrimaryButton, 'มีรหัสจากงานทะเบียนแล้ว'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), 'ABCD-2345');
      await tester.enterText(find.byType(TextField).at(2), 'Rahat-Mai-2569');
      await tester.enterText(find.byType(TextField).at(3), 'Rahat-Mai-256');
      await tester.tap(find.widgetWithText(PrimaryButton, 'ตั้งรหัสผ่านใหม่'));
      await tester.pumpAndSettle();

      expect(seen, isEmpty, reason: 'ต้องไม่ยิงคำขอเลยเมื่อรู้อยู่แล้วว่าไม่ตรงกัน');
      expect(find.textContaining('ไม่ตรงกัน'), findsOneWidget);
    });

    testWidgets('APP-24 ตั้งรหัสใหม่สำเร็จแล้วล้าง token และบอกว่าออกทุกอุปกรณ์', (tester) async {
      final store = MemoryStore();
      final seen = <Map<String, dynamic>>[];
      final session = makeSession(resetApi(seen: seen), store: store);
      await session.api.setTokens(access: 'abc', refresh: 'def', institutionId: 'inst-1');

      await pumpForgot(tester, session);
      await tester.tap(find.widgetWithText(PrimaryButton, 'มีรหัสจากงานทะเบียนแล้ว'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), 'ABCD-2345');
      await tester.enterText(find.byType(TextField).at(2), 'Rahat-Mai-2569');
      await tester.enterText(find.byType(TextField).at(3), 'Rahat-Mai-2569');
      await tester.tap(find.widgetWithText(PrimaryButton, 'ตั้งรหัสผ่านใหม่'));
      await tester.pumpAndSettle();

      final sent = seen.firstWhere((r) => r['path'] == '/auth/reset-password');
      expect((sent['body'] as Map)['code'], 'ABCD-2345');
      expect((sent['body'] as Map).containsKey('currentPassword'), isFalse,
          reason: 'การรีเซ็ตต้องไม่ต้องรู้รหัสผ่านเดิม มิฉะนั้นคนที่ลืมก็ยังใช้ไม่ได้');

      expect(await store.read('auth.token'), isNull,
          reason: 'เซิร์ฟเวอร์เพิกถอนทุก session แล้ว token ที่ค้างในเครื่องต้องหายไปด้วย');
      expect(find.textContaining('ออกจากระบบทุกอุปกรณ์'), findsWidgets);
    });
  });
}

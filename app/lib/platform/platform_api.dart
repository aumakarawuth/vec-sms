import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/api.dart' show ApiException, OfflineException;

/// ตัวเชื่อมกับเส้นทาง /platform/* ของ API
///
/// ─── ทำไมไม่ใช้ ApiClient ตัวเดิม ───
/// ApiClient ผูกกับวิทยาลัยตลอด — เก็บ institutionId ไว้และส่งไปด้วยทุกครั้ง
/// ที่หมุน token ส่วนฝั่งผู้ให้บริการไม่มีวิทยาลัยเลยแม้แต่ค่าเดียว
/// การยัด institutionId ปลอมให้ผ่านของเดิมคือการเริ่มโกหกตัวเองตั้งแต่ชั้นแรก
///
/// ─── ทำไม token อยู่ในหน่วยความจำอย่างเดียว ไม่เก็บลงเครื่อง ───
/// บัญชีในหน้าจอนี้ระงับวิทยาลัยได้ทั้งแห่ง และเห็นตัวเลขธุรกิจของลูกค้า
/// ทุกราย ถ้าเก็บ token ลงที่เก็บของเบราว์เซอร์ คนที่นั่งเครื่องเดิมต่อ
/// หรือสคริปต์ที่หลุดเข้ามาในหน้าเว็บ จะหยิบไปใช้ได้ทันที
///
/// ราคาที่จ่ายคือ **รีเฟรชหน้าแล้วต้องเข้าสู่ระบบใหม่** ซึ่งยอมรับได้
/// เพราะผู้ใช้หน้าจอนี้มีไม่กี่คนและเปิดวันละไม่กี่ครั้ง ต่างจากแอปนักศึกษา
/// ที่เปิดวันละหลายสิบครั้งบนโทรศัพท์ส่วนตัว
class PlatformApi {
  PlatformApi({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;

  String? _access;
  String? _refresh;
  Future<void>? _refreshing;

  String? get accessToken => _access;
  bool get hasToken => _access != null;
  String? get refreshToken => _refresh;

  void setTokens({required String? access, required String? refresh}) {
    _access = access;
    _refresh = refresh;
  }

  void clear() {
    _access = null;
    _refresh = null;
  }

  Future<dynamic> get(String path) => send('GET', path);

  Future<dynamic> post(String path, [Object? body]) => send('POST', path, body);

  /// ยิงคำขอโดยใช้ token ที่ระบุมาแทน token ปัจจุบัน
  ///
  /// ใช้กับขั้นตอนตั้งค่า MFA ซึ่งถือ challenge token อยู่ในมือแต่ยังไม่ใช่
  /// token จริง — ถ้าเผลอเก็บลง _access ไปก่อน คำขออื่นที่ไม่เกี่ยวข้องจะถูก
  /// ปฏิเสธด้วย 401 แล้วดูเหมือนระบบพัง ทั้งที่เป็นพฤติกรรมที่ถูกต้อง
  Future<dynamic> postAs(String token, String path, [Object? body]) =>
      send('POST', path, body, false, token);

  /// หมุน access token ด้วย refresh token
  ///
  /// รวมคำขอที่เกิดพร้อมกันให้เหลือครั้งเดียว มิฉะนั้นหน้าจอที่โหลดสามคำขอ
  /// พร้อมกันจะยิง refresh สามครั้ง แล้วสองครั้งหลังจะเจอ token ที่ถูกหมุน
  /// ไปแล้ว ซึ่งเซิร์ฟเวอร์ตีความว่าเป็นการใช้ token ซ้ำและเพิกถอนทุก session
  Future<void> _refreshAccessToken() {
    return _refreshing ??= () async {
      try {
        final res = await send('POST', '/platform/refresh',
            {'refreshToken': _refresh}, false) as Map<String, dynamic>;
        _access = res['accessToken']?.toString();
        _refresh = res['refreshToken']?.toString();
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<dynamic> send(
    String method,
    String path, [
    Object? body,
    bool allowRefresh = true,
    String? overrideToken,
  ]) async {
    final token = overrideToken ?? _access;
    http.Response res;
    try {
      final req = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll({
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        });
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http.send(req).timeout(timeout);
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const OfflineException();
    } catch (_) {
      throw const OfflineException();
    }

    final text = utf8.decode(res.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);

    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    if (res.statusCode == 401 && allowRefresh && _refresh != null) {
      try {
        await _refreshAccessToken();
      } catch (_) {
        throw ApiException(401, 'หมดเวลาใช้งาน กรุณาเข้าสู่ระบบใหม่');
      }
      return send(method, path, body, false);
    }

    throw ApiException(res.statusCode, _messageOf(decoded, res.statusCode));
  }

  String _messageOf(dynamic decoded, int status) {
    if (decoded is Map && decoded['message'] != null) {
      final m = decoded['message'];
      // ValidationPipe ของ Nest ส่ง message เป็นรายการเมื่อข้อมูลเข้าไม่ถูกต้อง
      if (m is List) return m.map((e) => e.toString()).join('\n');
      return m.toString();
    }
    return switch (status) {
      401 => 'หมดเวลาใช้งาน กรุณาเข้าสู่ระบบใหม่',
      403 => 'บัญชีนี้ไม่มีสิทธิ์ทำรายการนี้',
      404 => 'ไม่พบข้อมูล',
      _ => 'เกิดข้อผิดพลาด ($status)',
    };
  }

  void close() => _http.close();
}

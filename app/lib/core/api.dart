import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// ข้อผิดพลาดที่ฝั่งเซิร์ฟเวอร์ตอบกลับมา
///
/// ข้อความจากฐานข้อมูลเป็นภาษาไทยที่เขียนไว้ให้ผู้ใช้อ่านรู้เรื่องอยู่แล้ว
/// เช่น "ลงทะเบียนไม่ได้ ติดเงื่อนไขต่อไปนี้..." แอปจึงแสดงต่อได้เลย
/// ไม่ต้องแปลหรือเขียนข้อความของตัวเองซ้ำ
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get isAuth => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

/// ต่อเซิร์ฟเวอร์ไม่ได้ — อาจไม่มีสัญญาณ หรือเซิร์ฟเวอร์ล่ม
///
/// แยกจาก ApiException เพราะแอปต้องปฏิบัติต่างกัน:
/// ออฟไลน์ให้แสดงข้อมูลที่แคชไว้พร้อมบอกว่าเป็นข้อมูลเก่า
/// ส่วนข้อผิดพลาดจากเซิร์ฟเวอร์ให้แสดงข้อความจริง
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() => 'ต่อเซิร์ฟเวอร์ไม่ได้';
}

/// ที่เก็บค่าแบบคีย์-ค่า แยกเป็น interface เพื่อให้เทสต์ใช้ตัวในหน่วยความจำได้
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> remove(String key) async => _m.remove(key);
}

/// ผลลัพธ์ที่บอกด้วยว่ามาจากเครือข่ายหรือจากแคช
class Fetched<T> {
  const Fetched(this.data, {this.fromCache = false, this.cachedAt});
  final T data;
  final bool fromCache;
  final DateTime? cachedAt;
}

/// ตัวเชื่อมกับ API
///
/// รับ http.Client เข้ามาได้เพื่อให้เทสต์ฉีดตัวจำลองแทนได้
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required KeyValueStore store,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 12),
  })  : _store = store,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final KeyValueStore _store;
  final http.Client _http;
  final Duration timeout;

  String? _token;
  String? _refresh;
  String? _institutionId;
  Future<void>? _refreshing;

  String? get token => _token;

  static const _tokenKey = 'auth.token';
  static const _refreshKey = 'auth.refresh';
  static const _instKey = 'auth.institution';
  static const _cachePrefix = 'cache:';
  static const _cacheIndexKey = 'cache.keys';

  Future<void> loadToken() async {
    _token = await _store.read(_tokenKey);
    _refresh = await _store.read(_refreshKey);
    _institutionId = await _store.read(_instKey);
  }

  Future<void> setTokens({
    required String access,
    required String refresh,
    String? institutionId,
  }) async {
    _token = access;
    _refresh = refresh;
    await _store.write(_tokenKey, access);
    await _store.write(_refreshKey, refresh);
    if (institutionId != null) {
      _institutionId = institutionId;
      await _store.write(_instKey, institutionId);
    }
  }

  void setInstitution(String id) => _institutionId = id;

  /// ออกจากระบบ — ลบทั้ง token และข้อมูลที่แคชไว้ทั้งหมด
  ///
  /// ต้องลบแคชด้วย ไม่ใช่แค่ลืม token เพราะแคชมีผลการเรียนและยอดค้างชำระ
  /// ซึ่งคนถัดไปที่หยิบเครื่องไปจะอ่านได้ทันทีถ้าเหลือทิ้งไว้
  Future<void> signOut() async {
    if (_refresh != null && _institutionId != null) {
      // แจ้งเซิร์ฟเวอร์ให้เพิกถอนด้วย แต่ถ้าออฟไลน์ก็ยังต้องล้างในเครื่องอยู่ดี
      try {
        await post('/auth/logout', {
          'institutionId': _institutionId,
          'refreshToken': _refresh,
        });
      } catch (_) {
        // ตั้งใจกลืนข้อผิดพลาด การออกจากระบบต้องสำเร็จเสมอในมุมของผู้ใช้
      }
    }
    await clearCache();
    _token = null;
    _refresh = null;
    await _store.remove(_tokenKey);
    await _store.remove(_refreshKey);
  }

  Future<void> clearCache() async {
    final index = await _store.read(_cacheIndexKey);
    if (index != null && index.isNotEmpty) {
      for (final k in (jsonDecode(index) as List).cast<String>()) {
        await _store.remove(k);
      }
    }
    await _store.remove(_cacheIndexKey);
  }

  Future<void> _rememberCacheKey(String key) async {
    final raw = await _store.read(_cacheIndexKey);
    final keys = raw == null ? <String>[] : (jsonDecode(raw) as List).cast<String>();
    if (!keys.contains(key)) {
      keys.add(key);
      await _store.write(_cacheIndexKey, jsonEncode(keys));
    }
  }

  /// ต่ออายุ access token ด้วย refresh token
  ///
  /// รวมคำขอที่เกิดพร้อมกันให้เหลือครั้งเดียว มิฉะนั้นหน้าจอที่โหลดสามคำขอ
  /// พร้อมกันจะยิง refresh สามครั้ง แล้วสองครั้งหลังจะเจอ token ที่ถูกหมุน
  /// ไปแล้วและถูกตีความว่าเป็นการใช้ token ซ้ำ ทำให้ถูกเตะออกจากระบบ
  Future<void> _refreshAccessToken() {
    return _refreshing ??= () async {
      try {
        final res = await _send('POST', '/auth/refresh', {
          'institutionId': _institutionId,
          'refreshToken': _refresh,
        }, false) as Map<String, dynamic>;
        await setTokens(
          access: res['accessToken'].toString(),
          refresh: res['refreshToken'].toString(),
        );
      } finally {
        _refreshing = null;
      }
    }();
  }

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_token != null) 'authorization': 'Bearer $_token',
      };

  /// อ่านข้อมูล พร้อมเก็บสำเนาไว้ใช้ตอนออฟไลน์
  ///
  /// โรงฝึกงานเป็นอาคารคอนกรีตหนาที่สัญญาณเข้าไม่ถึง และนักศึกษาฝึกอาชีพ
  /// อยู่ในโรงงานต่างจังหวัด การเปิดแอปแล้วเจอหน้าจอว่างเปล่าจึงยอมรับไม่ได้
  Future<Fetched<dynamic>> getCached(String path) async {
    final cacheKey = '$_cachePrefix$path';
    try {
      final data = await get(path);
      await _store.write(
        cacheKey,
        jsonEncode({'at': DateTime.now().toIso8601String(), 'data': data}),
      );
      await _rememberCacheKey(cacheKey);
      return Fetched(data);
    } on OfflineException {
      final raw = await _store.read(cacheKey);
      if (raw == null) rethrow;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return Fetched(
        decoded['data'],
        fromCache: true,
        cachedAt: DateTime.tryParse(decoded['at'] as String? ?? ''),
      );
    }
  }

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);

  Future<dynamic> _send(
    String method,
    String path, [
    Object? body,
    bool allowRefresh = true,
  ]) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
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

    // access token หมดอายุ ลองต่ออายุหนึ่งครั้งแล้วยิงซ้ำ
    if (res.statusCode == 401 &&
        allowRefresh &&
        _refresh != null &&
        _institutionId != null &&
        !path.startsWith('/auth/')) {
      try {
        await _refreshAccessToken();
      } catch (_) {
        throw ApiException(401, 'กรุณาเข้าสู่ระบบใหม่');
      }
      return _send(method, path, body, false);
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
      401 => 'กรุณาเข้าสู่ระบบใหม่',
      403 => 'ไม่มีสิทธิ์ดูข้อมูลนี้',
      404 => 'ไม่พบข้อมูล',
      _ => 'เกิดข้อผิดพลาด ($status)',
    };
  }

  void close() => _http.close();
}

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// ที่เก็บข้อมูลบนเครื่องแบบเข้ารหัส
///
/// ─── ทำไมต้องเข้ารหัส ───
/// แอปเก็บ token ผลการเรียน และยอดค้างชำระไว้ในเครื่องเพื่อให้ใช้ตอนไม่มีสัญญาณ
/// โทรศัพท์ของนักศึกษาถูกยืมและถูกขโมยบ่อย ถ้าเก็บเป็นข้อความธรรมดา
/// ใครที่หยิบเครื่องไปได้จะอ่านผลการเรียนและข้อมูลการเงินได้ทันที
///
/// ─── ทำไมไม่ใช้ shared_preferences ───
/// shared_preferences เก็บเป็นไฟล์ XML ธรรมดาบน Android และ NSUserDefaults
/// บน iOS ทั้งสองอ่านได้ด้วยเครื่องมือทั่วไป ไม่ได้เข้ารหัสให้
///
/// ─── วิธีที่ใช้ ───
/// ฝากการเข้ารหัสไว้กับระบบปฏิบัติการ — Android ใช้ EncryptedSharedPreferences
/// ที่มีกุญแจอยู่ใน Keystore ส่วน iOS ใช้ Keychain ที่อ่านได้เฉพาะตอนปลดล็อกแล้ว
/// ไม่เขียนอัลกอริทึมเข้ารหัสเอง เพราะการจัดการกุญแจเองผิดพลาดง่ายกว่ามาก
///
/// ─── ข้อจำกัดที่ต้องรู้ ───
/// ปกป้องได้เมื่อเครื่องล็อกอยู่และเมื่อถูกถอดหน่วยความจำไปอ่าน
/// แต่ไม่ได้ปกป้องจากเครื่องที่ถูก root หรือ jailbreak
/// การตรวจ root และการล็อกแอปด้วยไบโอเมตริกเป็นงานคนละชั้นที่ต้องทำเพิ่ม
class SecureStore implements KeyValueStore {
  SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  static Future<SecureStore> open() async {
    return SecureStore(
      const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          // อ่านได้เฉพาะหลังปลดล็อกเครื่องครั้งแรก และไม่ถูกสำรองขึ้น iCloud
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      ),
    );
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

/// ตัวระบุอุปกรณ์ที่แอปสุ่มเองและเก็บไว้
///
/// ไม่ใช้รหัสประจำเครื่องของระบบปฏิบัติการ เช่น Android ID หรือ IDFV
/// เพราะเป็นข้อมูลส่วนบุคคลตามแนวทางของทั้งสองแพลตฟอร์ม และบางรุ่นเปลี่ยนค่า
/// เองเมื่ออัปเดตระบบ ค่าที่แอปสุ่มเองเหมาะกว่า เพราะสิ่งที่ระบบต้องรู้คือ
/// "เครื่องเดิมหรือเปล่า" ไม่ใช่ "เครื่องนี้คือเครื่องไหนในโลก"
class DeviceIdentity {
  DeviceIdentity(this._store);
  final KeyValueStore _store;

  static const _key = 'device.id';

  Future<String> get() async {
    final existing = await _store.read(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _newId();
    await _store.write(_key, generated);
    return generated;
  }

  /// ล้างตัวระบุอุปกรณ์ ใช้ตอนผู้ใช้กดลืมเครื่องนี้
  Future<void> reset() => _store.remove(_key);

  static String _newId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// ชื่อเครื่องที่เจ้าหน้าที่อ่านเข้าใจ ใช้ตอนพิจารณาอนุมัติอุปกรณ์
  static String label() {
    if (kIsWeb) return 'เว็บเบราว์เซอร์';
    try {
      if (Platform.isAndroid)
        return 'Android ${Platform.operatingSystemVersion}';
      if (Platform.isIOS) return 'iOS ${Platform.operatingSystemVersion}';
      return Platform.operatingSystem;
    } catch (_) {
      return 'อุปกรณ์ไม่ทราบรุ่น';
    }
  }

  static String platform() {
    if (kIsWeb) return 'web';
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }
}

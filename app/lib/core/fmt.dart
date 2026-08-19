import 'package:intl/intl.dart';

/// การจัดรูปแบบตัวเลขและวันที่แบบไทย
///
/// แยกออกมาเป็นไฟล์เดียวเพราะเป็นจุดที่ผิดพลาดง่ายและต้องเหมือนกันทั้งแอป
/// โดยเฉพาะปีพุทธศักราช ซึ่งทุกเอกสารของสถานศึกษาใช้ พ.ศ. ไม่ใช่ ค.ศ.
class Fmt {
  static final _baht = NumberFormat('#,##0.##', 'th');
  static final _int = NumberFormat('#,##0', 'th');

  /// PostgreSQL ส่งค่าชนิด numeric กลับมาเป็นสตริง ไม่ใช่ตัวเลข
  /// การอ่านค่าจึงต้องรองรับทั้งสองแบบเสมอ มิฉะนั้นแอปจะพังเงียบ ๆ
  static num? toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  static String money(dynamic v) {
    final n = toNum(v);
    return n == null ? '—' : '฿${_baht.format(n)}';
  }

  static String count(dynamic v) {
    final n = toNum(v);
    return n == null ? '—' : _int.format(n);
  }

  static String percent(dynamic v, {int digits = 1}) {
    final n = toNum(v);
    return n == null ? '—' : '${n.toStringAsFixed(digits)}%';
  }

  static const _months = [
    'มกราคม',
    'กุมภาพันธ์',
    'มีนาคม',
    'เมษายน',
    'พฤษภาคม',
    'มิถุนายน',
    'กรกฎาคม',
    'สิงหาคม',
    'กันยายน',
    'ตุลาคม',
    'พฤศจิกายน',
    'ธันวาคม',
  ];
  static const _monthsShort = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  static const _weekdays = [
    'จันทร์',
    'อังคาร',
    'พุธ',
    'พฤหัสบดี',
    'ศุกร์',
    'เสาร์',
    'อาทิตย์',
  ];

  /// 8 สิงหาคม 2569 — ปีพุทธศักราชเสมอ
  static String dateFull(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year + 543}';

  /// 8 ส.ค. 2569
  static String dateShort(DateTime d) =>
      '${d.day} ${_monthsShort[d.month - 1]} ${d.year + 543}';

  /// ศุกร์ 8 สิงหาคม 2569
  static String dateWithWeekday(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${dateFull(d)}';

  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// รับได้ทั้งสตริง ISO และ DateTime เพราะ API ส่ง date กลับมาเป็นสตริง
  static DateTime? parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static String dateShortOf(dynamic v) {
    final d = parseDate(v);
    return d == null ? '—' : dateShort(d);
  }

  /// "เมื่อสักครู่" · "12 นาทีที่แล้ว" · "3 ชั่วโมงที่แล้ว" · "8 ส.ค. 2569"
  /// ใช้บอกอายุของข้อมูลที่แสดงจากแคชตอนออฟไลน์
  static String ago(DateTime when, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(when);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
    return dateShort(when);
  }
}

import 'package:flutter/material.dart';

/// ระบบสีของแอป — ตรงกับที่ใช้ในฝั่งเว็บ
///
/// หลักเดียวที่ถือ: อินเทอร์เฟซเป็นขาว ดำ เทา
/// สีปรากฏเฉพาะเมื่อมีบางอย่างต้องการความสนใจเท่านั้น
/// ถ้าหน้าจอมีสีอยู่แล้วทุกที่ สีเตือนจะไม่มีน้ำหนัก
class AppColors {
  const AppColors({
    required this.bg,
    required this.sunk,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.ink4,
    required this.rule,
    required this.rule2,
    required this.ok,
    required this.warn,
    required this.crit,
    required this.sel,
  });

  final Color bg, sunk, ink, ink2, ink3, ink4, rule, rule2, ok, warn, crit, sel;

  static const light = AppColors(
    bg: Color(0xFFF8F9FD),
    sunk: Color(0xFFFFFFFF),
    ink: Color(0xFF27243A),
    ink2: Color(0xFF69657B),
    ink3: Color(0xFF9290A2),
    ink4: Color(0xFFC4C1D0),
    rule: Color(0xFFEAE8F3),
    rule2: Color(0xFFD9D5E8),
    ok: Color(0xFF36A875),
    warn: Color(0xFFE49A28),
    crit: Color(0xFFE05D66),
    sel: Color(0xFF6657E8),
  );

  static const dark = AppColors(
    bg: Color(0xFF0E0E0F),
    sunk: Color(0xFF151517),
    ink: Color(0xFFEDEDEB),
    ink2: Color(0xFFA0A2A6),
    ink3: Color(0xFF75777B),
    ink4: Color(0xFF4E5054),
    rule: Color(0xFF232326),
    rule2: Color(0xFF333437),
    ok: Color(0xFF5FA37D),
    warn: Color(0xFFD2A04A),
    crit: Color(0xFFD9736A),
    sel: Color(0xFF8AACD6),
  );
}

/// ตัวช่วยหยิบชุดสีตามธีมปัจจุบัน
extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
}

/// ระยะห่างตามสเกล 4 พิกเซล
class Gap {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  // ตัวอักษรไทยต้องใช้ระยะบรรทัดไม่ต่ำกว่า 1.6 เพราะสระบนและวรรณยุกต์ซ้อนกันสองชั้น
  // ถ้าใช้ค่าเริ่มต้นของ Material ตัววรรณยุกต์จะไปชนบรรทัดบน
  TextStyle t(double size, FontWeight w, Color color, {double h = 1.6}) =>
      TextStyle(fontSize: size, fontWeight: w, color: color, height: h);

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.rule,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.sel,
      brightness: brightness,
      surface: c.bg,
    ),
    useMaterial3: true,
    fontFamily: 'Leelawadee UI',
    fontFamilyFallback: const ['Noto Sans Thai', 'Sarabun', 'sans-serif'],
    textTheme: TextTheme(
      // ตัวเลขหลัก — น้ำหนักบางขนาดใหญ่ คือจุดนำสายตาเดียวของแต่ละหน้าจอ
      displayLarge: t(44, FontWeight.w700, c.ink, h: 1.05),
      displayMedium: t(32, FontWeight.w700, c.ink, h: 1.1),
      titleLarge: t(21, FontWeight.w700, c.ink, h: 1.3),
      titleMedium: t(15, FontWeight.w600, c.ink, h: 1.5),
      bodyLarge: t(15, FontWeight.w400, c.ink),
      bodyMedium: t(13.5, FontWeight.w400, c.ink2),
      bodySmall: t(12, FontWeight.w400, c.ink3, h: 1.5),
      labelSmall: t(11.5, FontWeight.w400, c.ink3, h: 1.4),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t(20, FontWeight.w600, c.ink, h: 1.3),
      iconTheme: IconThemeData(color: c.ink2),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    cardTheme: CardThemeData(
      color: c.sunk,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.sunk,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(color: c.ink4, fontSize: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.rule)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.sel, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c.crit)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.bg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}

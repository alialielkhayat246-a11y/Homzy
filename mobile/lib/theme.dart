import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Homzy brand system — kept 1:1 with the web chat UI (frontend/index.html)
/// and the official identity sheet (see docs/PROJECT_PLAN.md → Brand).
class Brand {
  static const navy = Color(0xFF0D1B2A); // primary dark / text
  static const blue = Color(0xFF2563EB); // primary accent
  static const blueLight = Color(0xFFE0F2FE);
  static const green = Color(0xFF22C55E); // success / AI status
  static const gray = Color(0xFFF3F4F6); // background
  static const line = Color(0xFFE6E8EC);
  static const muted = Color(0xFF6B7280);

  static const tagline = 'Your guide to finding the right home.';

  /// Poppins for Latin, Cairo for Arabic. We let google_fonts pull both and
  /// use Poppins as the base; Arabic text falls back to Cairo via [arabic].
  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.poppinsTextTheme(base);

  /// Apply Cairo to a text style for Arabic content.
  static TextStyle arabic([TextStyle? style]) =>
      GoogleFonts.cairo(textStyle: style);
}

ThemeData buildHomzyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.blue,
      primary: Brand.blue,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Brand.gray,
  );
  return base.copyWith(
    textTheme: Brand.textTheme(base.textTheme).apply(
      bodyColor: Brand.navy,
      displayColor: Brand.navy,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Brand.navy,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Brand.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
  );
}

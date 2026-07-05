import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Homzy brand system — 2026 identity refresh.
/// Navy + coral on a warm cream canvas, Cairo type for a clean bilingual look.
class Brand {
  static const navy = Color(0xFF0B1D36); // primary dark / headers / text
  static const coral = Color(0xFFFF686B); // primary accent / CTA / hearts
  static const coralLight = Color(0xFFFFE7E7);
  static const cream = Color(0xFFF7F2EE); // app background
  static const green = Color(0xFF22C55E); // success / WhatsApp / active
  static const amber = Color(0xFFF59E0B); // pending / under-review status
  static const red = Color(0xFFDC2626); // errors / destructive
  static const muted = Color(0xFF6B7280); // secondary text
  static const line = Color(0xFFEBE5DE); // hairline on cream
  static const card = Color(0xFFFFFFFF); // surfaces

  // Legacy aliases kept so not-yet-restyled screens still compile.
  static const blue = navy;
  static const blueLight = coralLight;
  static const gray = cream;

  static const tagline = 'بيتك يبدأ من هنا';

  /// Cairo everywhere — renders Arabic beautifully and Latin cleanly, so one
  /// family keeps the bilingual UI consistent.
  static TextTheme textTheme(TextTheme base) => GoogleFonts.cairoTextTheme(base);

  /// Explicit Cairo style helper (kept for call sites that request it).
  static TextStyle arabic([TextStyle? style]) =>
      GoogleFonts.cairo(textStyle: style);

  /// A coral (accent) elevated-button style for primary calls to action.
  static ButtonStyle get coralButton => ElevatedButton.styleFrom(
        backgroundColor: coral,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      );
}

ThemeData buildHomzyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.navy,
      primary: Brand.navy,
      secondary: Brand.coral,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Brand.cream,
  );
  return base.copyWith(
    textTheme: Brand.textTheme(base.textTheme).apply(
      bodyColor: Brand.navy,
      displayColor: Brand.navy,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.cream,
      foregroundColor: Brand.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
          color: Brand.navy, fontSize: 17, fontWeight: FontWeight.w700),
    ),
    // Default filled button = navy (the design's most common action button).
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.navy, width: 1.4),
      ),
    ),
  );
}

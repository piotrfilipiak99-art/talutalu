import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static bool _isDark = true;
  static bool get isDark => _isDark;
  static void setDark(bool value) => _isDark = value;

  // Brand accent — kept identical across both themes.
  static const primary = Color(0xFF7C5CFC);
  static const primaryGlow = Color(0x267C5CFC);

  // ── Dark palette ─────────────────────────────────────────────────────────────
  static const darkBg = Color(0xFF09090F);
  static const darkSurface = Color(0xFF12121A);
  static const darkCard = Color(0xFF1C1C28);
  static const darkBorder = Color(0xFF2C2C3E);
  static const darkPrimarySoft = Color(0xFFC2AFFF);
  static const darkText = Color(0xFFF2F0FF);
  static const darkText2 = Color(0xFF9490B0);
  static const darkText3 = Color(0xFF4C4868);

  // ── Light palette ────────────────────────────────────────────────────────────
  // Muted lavender-gray rather than near-white — a stark white/off-white
  // pairing read as too bright/glary; a deeper base makes the (still white)
  // cards pop instead of everything blending into one flat bright surface.
  static const lightBg = Color(0xFFEDEBF2);
  static const lightSurface = Color(0xFFE3E0EA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFD8D5E1);
  static const lightPrimarySoft = Color(0xFF6A4FE0);
  static const lightText = Color(0xFF1E1B2E);
  static const lightText2 = Color(0xFF625E76);
  static const lightText3 = Color(0xFF9C97AC);

  // Mode-aware accessors — every screen reads colors through these, so
  // flipping [setDark] repaints the whole app once the tree rebuilds.
  static Color get bg => _isDark ? darkBg : lightBg;
  static Color get surface => _isDark ? darkSurface : lightSurface;
  static Color get card => _isDark ? darkCard : lightCard;
  static Color get border => _isDark ? darkBorder : lightBorder;
  static Color get primarySoft => _isDark ? darkPrimarySoft : lightPrimarySoft;
  static Color get text => _isDark ? darkText : lightText;
  static Color get text2 => _isDark ? darkText2 : lightText2;
  static Color get text3 => _isDark ? darkText3 : lightText3;
}

class AppTheme {
  AppTheme._();

  static ThemeData themeFor(bool isDark) => ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        colorScheme: isDark
            ? const ColorScheme.dark(
                surface: AppColors.darkSurface,
                primary: AppColors.primary,
                secondary: AppColors.darkPrimarySoft,
              )
            : const ColorScheme.light(
                surface: AppColors.lightSurface,
                primary: AppColors.primary,
                secondary: AppColors.lightPrimarySoft,
              ),
        textTheme: GoogleFonts.dmSansTextTheme(
                isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme)
            .copyWith(
          displayLarge: GoogleFonts.cormorantGaramond(
            color: isDark ? AppColors.darkText : AppColors.lightText,
            fontSize: 64,
            fontWeight: FontWeight.w300,
            letterSpacing: -2,
            height: 1.0,
          ),
          displayMedium: GoogleFonts.cormorantGaramond(
            color: isDark ? AppColors.darkText : AppColors.lightText,
            fontSize: 48,
            fontWeight: FontWeight.w300,
            letterSpacing: -1.5,
            height: 1.05,
          ),
          headlineLarge: GoogleFonts.cormorantGaramond(
            color: isDark ? AppColors.darkText : AppColors.lightText,
            fontSize: 36,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          headlineMedium: GoogleFonts.cormorantGaramond(
            color: isDark ? AppColors.darkText : AppColors.lightText,
            fontSize: 28,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          bodyLarge: GoogleFonts.dmSans(
            color: isDark ? AppColors.darkText : AppColors.lightText,
            fontSize: 16,
            height: 1.7,
          ),
          bodyMedium: GoogleFonts.dmSans(
            color: isDark ? AppColors.darkText2 : AppColors.lightText2,
            fontSize: 14,
            height: 1.5,
          ),
          labelLarge: GoogleFonts.dmSans(
            color: isDark ? AppColors.darkText : AppColors.lightText,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          labelMedium: GoogleFonts.dmSans(
            color: isDark ? AppColors.darkText2 : AppColors.lightText2,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
          ),
          labelSmall: GoogleFonts.dmSans(
            color: isDark ? AppColors.darkText3 : AppColors.lightText3,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          hintStyle: GoogleFonts.dmSans(
              color: isDark ? AppColors.darkText3 : AppColors.lightText3,
              fontSize: 15),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        useMaterial3: true,
      );

  static ThemeData get dark => themeFor(true);
  static ThemeData get light => themeFor(false);
}

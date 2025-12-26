import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class SafeCheckTheme {
  static const double _borderRadius = 24.0;
  static const double _inputRadius = 16.0;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        primary: AppColors.primaryBlue,
        secondary: AppColors.infoCyan,
        surface: AppColors.backgroundLight,
        onSurface: AppColors.textPrimary,
        error: AppColors.dangerRed,
        surfaceContainer: AppColors.surfaceLight,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displaySmall: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          side: const BorderSide(color: AppColors.borderLight, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          elevation: 4,
          shadowColor: AppColors.primaryBlue.withValues(alpha: 0.3),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFillLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(
            color: AppColors.primaryBlue,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(color: AppColors.dangerRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(color: AppColors.dangerRed, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        brightness: Brightness.dark,
        primary: AppColors.primaryBlue,
        secondary: AppColors.infoCyan,
        error: AppColors.dangerRed,
        surface: AppColors.backgroundDark,
        onSurface: AppColors.textPrimaryDark,
        surfaceContainer: AppColors.surfaceDark,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displaySmall: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryDark,
            ),
            headlineMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryDark,
            ),
            bodyLarge: GoogleFonts.inter(color: AppColors.textPrimaryDark),
            bodyMedium: GoogleFonts.inter(color: AppColors.textSecondaryDark),
          ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          elevation: 4,
          shadowColor: AppColors.primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
        fillColor: AppColors.borderDark.withValues(alpha: 0.3),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(color: AppColors.primaryBlue),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_inputRadius),
          borderSide: const BorderSide(color: AppColors.dangerRed),
        ),
        hintStyle: GoogleFonts.inter(color: AppColors.textSecondaryDark),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondaryDark),
      ),
    );
  }
}

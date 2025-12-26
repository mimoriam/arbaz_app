import 'package:flutter/material.dart';

class AppColors {
  // Private constructor to prevent instantiation
  AppColors._();

  // Primary Palette
  static const Color primaryBlue = Color(0xFF246BFD);
  static const Color primaryBlueLight = Color(0xFFE9F0FF);

  // Status & Actions
  static const Color successGreen = Color(0xFF22C55E);
  static const Color dangerRed = Color(0xFFF43F5E);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color infoCyan = Color(0xFF06B6D4);

  // Neutral / Backgrounds (Light)
  static const Color surfaceLight = Colors.white;
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color inputFillLight = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  // Neutral / Backgrounds (Dark)
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color borderDark = Color(0xFF334155);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  // Specialized Colors
  static const Color vaultCard = Color(0xFF111827);
  static const Color energyYellow = Color(0xFFFACC15);
}

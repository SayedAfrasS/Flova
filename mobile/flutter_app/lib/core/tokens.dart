import 'package:flutter/material.dart';

abstract class FlovaTokens {
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F7F8);
  static const section = Color(0xFFF3F4F6);
  static const accent = Color(0xFF2563EB);
  static const accentHover = Color(0xFF1D4ED8);
  static const violet = Color(0xFF6366F1);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const ink = Color(0xFF111827);
  static const ink2 = Color(0xFF6B7280);
  static const ink3 = Color(0xFF9CA3AF);
  static const line = Color(0xFFE5E7EB);
  static const rControl = 12.0;
  static const rCard = 16.0;
  static const rPanel = 20.0;
}

ThemeData flovaTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: FlovaTokens.canvas,
      colorScheme: const ColorScheme.light(
        primary: FlovaTokens.accent,
        onPrimary: Colors.white,
        surface: FlovaTokens.canvas,
        onSurface: FlovaTokens.ink,
        secondaryContainer: FlovaTokens.section,
        outline: FlovaTokens.line,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: FlovaTokens.ink, height: 1.15),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: FlovaTokens.ink),
        bodyLarge: TextStyle(fontSize: 16, color: FlovaTokens.ink2),
        bodyMedium: TextStyle(fontSize: 14, color: FlovaTokens.ink2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FlovaTokens.accent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlovaTokens.rControl)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FlovaTokens.ink,
          side: const BorderSide(color: FlovaTokens.line),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlovaTokens.rControl)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
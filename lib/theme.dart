import 'package:flutter/material.dart';

class AppColors {
  static const green = Color(0xFF279C56);
  static const blue = Color(0xFF180D3B);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light();

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.green,
      colorScheme: base.colorScheme.copyWith( 
        primary: AppColors.blue,
        secondary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.black87),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      // ✅ Use CardThemeData for newer Flutter versions
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        margin: EdgeInsets.all(0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
          ),
          elevation: 4,
          shadowColor: Colors.black26,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white, width: 2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

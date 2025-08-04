import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkGreen = Color(0xFF2d3930);
  static const Color brown = Color(0xFF796043);
  static const Color lightGrey = Color(0xFFE6E6E6);
  static const Color darkText = Color(0xFF312A23);
  static const Color offWhite = Color(0xFFF8F8F8);
  static const Color pageBackground = Color(0xFFf4f4f4);
  static const Color statusPrenhe = Color(0xFF2196F3);
  static const Color statusVazia = Color(0xFFF44336);
  static const Color statusDiagnostico = Color(0xFF4CAF50);

  static ThemeData get theme {
    return ThemeData(
      colorScheme: const ColorScheme.light(
        primary: darkGreen,
        secondary: brown,
        surface: offWhite,
        background: pageBackground,
        error: statusVazia,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkText,
        onBackground: darkText,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: pageBackground,
      fontFamily: 'Inter',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        modalBackgroundColor: Color.fromRGBO(248, 248, 248, 0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 4,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.bold),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brown,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: const CardThemeData(
        color: offWhite,
        elevation: 1,
        margin: EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightGrey,
        hintStyle: TextStyle(color: darkText.withOpacity(0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      ),
    );
  }
}
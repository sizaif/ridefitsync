import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // 品牌色 - Strava Orange
  static const Color accent = Color(0xFFFC4C02);
  static const Color accentLight = Color(0xFFFF8243);

  // 兼容旧代码的毛玻璃参数
  static const double glassBlur = 10.0;
  static const double glassOpacity = 0.08;
  static const double glassBorderOpacity = 0.15;
  static const double glassBorderRadius = 16.0;

  // 状态色
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFC107);

  // 平台品牌色
  static const Color onelapColor = Color(0xFF0155FF);
  static const Color stravaColor = Color(0xFFFC4C02);
  static const Color igpColor = Color(0xFFFF3C1F);
  static const Color xingzheColor = Color(0xFF0155FF);
  static const Color giantColor = Color(0xFFFF9800);

  /// 浅色主题（默认，与 ref/strava_auto 一致）
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.grey.withOpacity(0.1),
            width: 1,
          ),
        ),
        color: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.withOpacity(0.1),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// 深色主题（与 ref/strava_auto 一致）
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        color: const Color(0xFF1E1E1E),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.1),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// 兼容旧代码的背景渐变
  static BoxDecoration get backgroundGradient {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
      ),
    );
  }
}

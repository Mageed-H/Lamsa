import 'package:flutter/material.dart';

class AppTheme {
  // تعريف الألوان الأساسية (Pink Theme)
  static const Color primaryColor = Color(0xFFE91E63); // وردي نابض بالحياة
  static const Color secondaryColor = Color(0xFFF8BBD0); // وردي فاتح
  static const Color backgroundColor = Color(0xFFFCE4EC); // وردي أفتح للخلفية
  static const Color surfaceColor = Colors.white; // للبطاقات (Cards)
  static const Color textPrimary = Color(0xFF212121); // أسود داكن للنصوص
  static const Color textSecondary = Color(0xFF757575); // رصاصي للنصوص الثانوية
  static const Color errorColor = Color(0xFFD32F2F); // أحمر للأخطاء والحذف
  static const Color successColor = Color(0xFF388E3C); // أخضر للنجاح والأرباح
  static const Color warningColor = Color(0xFFFF9800); // برتقالي للتحذيرات والتعليق
  static const Color highlightColor = Color(0xFFFCE4EC); // وردي فاتح للتحديد
  static const Color searchFieldColor = Color(0xFFFCE4EC); // وردي فاتح لحقل البحث
  static const Color neutralColor = Color(0xFF9E9E9E); // رصاصي للعناصر المحايدة
  static const Color neutralLightColor = Color(0xFFF5F5F5); // رصاصي فاتح للخلفيات

  // تعريف الـ ThemeData اللي راح نربطه بـ MaterialApp
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
      ),
      // خط Cairo العربي (مُضمّن محلياً مع التطبيق)
      fontFamily: 'Cairo',
    );
  }
}
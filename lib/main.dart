import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/main_layout.dart';
import 'core/database/database_helper.dart';

void main() async {
  // التأكد من تهيئة الفلتر قبل تشغيل أي كود برمجي
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة قاعدة بيانات SQLite قبل فتح التطبيق حتى تكون جاهزة للاستعلامات السريعة
  await DatabaseHelper.instance.database;
  
  runApp(const CashierApp());
}

class CashierApp extends StatelessWidget {
  const CashierApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام الكاشير',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // دعم اللغة العربية من اليمين لليسار بشكل إجباري لكل التطبيق
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const MainLayout(),
    );
  }
}
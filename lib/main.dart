import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform, File;
import 'core/theme/app_theme.dart';
import 'core/widgets/main_layout.dart';
import 'core/database/database_helper.dart';
import 'core/services/error_logger.dart';

void main() async {
  // التأكد من تهيئة الفلتر قبل تشغيل أي كود برمجي
  WidgetsFlutterBinding.ensureInitialized();

  // ─── شبكة أمان عامة: لا خطأ يضيع بدون تسجيل ───
  // أخطاء إطار Flutter (build/layout) — نعرضها أيضاً بالكونسول للتطوير
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorLogger.instance.logError(
      details.exception,
      details.stack,
      context: 'إطار Flutter: ${details.library}',
    );
  };
  // أخطاء غير ملتقطة في الـ zones والمنصة
  PlatformDispatcher.instance.onError = (e, st) {
    ErrorLogger.instance.logError(e, st, context: 'خطأ غير ملتقط');
    return true; // نمنع انهيار التطبيق — نسجل فقط
  };

  // على الديسكتوب نستخدم FFI عشان يشتغل sqflite — على الموبايل ما نحتاجه
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // تهيئة قاعدة بيانات SQLite قبل فتح التطبيق حتى تكون جاهزة للاستعلامات السريعة
  await DatabaseHelper.instance.database;

  // ─── إعادة تعيين الرموز: أنشئ ملف reset_pins.flag بجانب الـ exe ───
  // (Flutter Windows لا يمرر command-line args بشكل موثوق في release)
  try {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final flagFile = File('$exeDir${Platform.pathSeparator}reset_pins.flag');
    if (await flagFile.exists()) {
      await flagFile.delete();
      await DatabaseHelper.instance.setSetting('dev_pin_hash', '');
      await DatabaseHelper.instance.setSetting('products_pin', '');
      await DatabaseHelper.instance.setSetting('sales_pin', '');
      await DatabaseHelper.instance.setSetting('debts_pin', '');
      await DatabaseHelper.instance.setSetting('customers_pin', '');
      await DatabaseHelper.instance.setSetting('top_selling_pin', '');
      await DatabaseHelper.instance.setSetting('expenses_pin', '');
      // تسجيل النتيجة بجانب الملف المحذوف
      await File('$exeDir${Platform.pathSeparator}reset_pins_result.txt')
          .writeAsString('تم تصفير جميع الرموز بنجاح ✓\n${DateTime.now()}');
    }
  } catch (_) {}

  // إعادة حساب نقاط الولاء (إصلاح بيانات قديمة)
  () async {
    try { await DatabaseHelper.instance.recalculateAllCustomerPoints(); } catch (_) {}
  }();

  // نسخ احتياطي تلقائي يومي — لا يعطل بدء التشغيل أبداً
  () async {
    try {
      final path = await DatabaseHelper.instance.autoBackupIfNeeded();
      if (path != null) {
        await ErrorLogger.instance.info('تم إنشاء نسخة احتياطية تلقائية', data: {'path': path});
      }
    } catch (e) {
      await ErrorLogger.instance.error('خطأ في النسخ الاحتياطي التلقائي', data: {'error': '$e'});
    }
  }();

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
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart' as sqlite3_open;

/// خدمة تشفير قاعدة البيانات (SQLCipher)
///
/// - يولّد مفتاح تشفير عشوائي (32 بايت) عند أول تشغيل ويحفظه في ملف مخفي
/// - يحمّل sqlcipher.dll إن وُجد بجانب التطبيق، وإلا يستخدم sqlite3.dll العادي
/// - إذا لم يتوفر SQLCipher يعمل التطبيق بدون تشفير (وضع آمن) مع تسجيل تحذير
class DbEncryption {
  DbEncryption._();

  static bool _overrideApplied = false;
  static String? _cachedKey;
  static bool? _available;

  /// هل المنصة ويندوز ديسكتوب
  static bool get isDesktop => !kIsWeb && Platform.isWindows;

  /// هل sqlcipher.dll موجود بجانب التطبيق
  static bool get cipherAvailable {
    if (_available != null) return _available!;
    if (!isDesktop) return _available = false;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      _available = File(p.join(exeDir, 'sqlcipher.dll')).existsSync();
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  /// تحميل مكتبة SQLite المناسبة قبل أي فتح لقاعدة البيانات
  ///
  /// يجب استدعاؤها مرة واحدة قبل أول عملية على القاعدة.
  /// إذا وُجد sqlcipher.dll يُحمَّل بدلاً من sqlite3.dll العادي.
  static void applyLibraryOverride() {
    if (_overrideApplied || kIsWeb || !Platform.isWindows) return;
    _overrideApplied = true;
    sqlite3_open.open.overrideFor(sqlite3_open.OperatingSystem.windows, () {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final cipherPath = p.join(exeDir, 'sqlcipher.dll');
      if (File(cipherPath).existsSync()) {
        return DynamicLibrary.open(cipherPath);
      }
      // الرجوع للمكتبة الافتراضية المرفقة مع التطبيق
      return DynamicLibrary.open('sqlite3.dll');
    });
  }

  /// مسار ملف المفتاح المخفي
  static String get _keyFilePath {
    final appData = Platform.environment['APPDATA']
        ?? Platform.environment['HOME']
        ?? '.';
    return p.join(appData, 'CashierSystem', '.dbkey');
  }

  /// الحصول على مفتاح التشفير — ينشئه تلقائياً عند أول تشغيل
  ///
  /// يعيد null إذا كان التشفير غير متوفر (لا يوجد sqlcipher.dll)
  static Future<String?> getKey() async {
    if (!cipherAvailable) return null;
    if (_cachedKey != null) return _cachedKey;

    final keyFile = File(_keyFilePath);
    if (await keyFile.exists()) {
      try {
        final stored = await keyFile.readAsString();
        final key = stored.trim();
        if (key.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(key)) {
          _cachedKey = key.toLowerCase();
          return _cachedKey;
        }
        // ملف تالف — نولّد مفتاحاً جديداً (تحذير: القاعدة القديمة لن تُفتح)
        // ignore: avoid_print
        print('CRITICAL: ملف مفتاح التشفير تالف!');
      } catch (_) {}
    }

    // توليد مفتاح جديد عشوائي 256-bit
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    await keyFile.parent.create(recursive: true);
    await keyFile.writeAsString(hex);
    // إخفاء الملف على ويندوز
    if (Platform.isWindows) {
      try {
        await Process.run('attrib', ['+h', _keyFilePath]);
      } catch (_) {}
    }

    _cachedKey = hex;
    return _cachedKey;
  }

  /// صيغة PRAGMA key بصيغة hex الآمنة
  static String keyPragma(String hexKey) =>
      "PRAGMA key = \"x'$hexKey'\";";

  /// صيغة PRAGMA rekey لتشفير قاعدة نصية موجودة
  static String rekeyPragma(String hexKey) =>
      "PRAGMA rekey = \"x'$hexKey'\";";

  /// قراءة أول 16 بايت من ملف قاعدة بيانات لتحديد نوعه
  ///
  /// يعيد true إذا كان الملف نصياً غير مشفر (SQLite format 3)
  static Future<bool> isPlaintextDb(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      final raf = await f.open(mode: FileMode.read);
      try {
        final header = await raf.read(16);
        const magic = 'SQLite format 3\x00';
        if (header.length < 16) return false;
        for (var i = 0; i < 16; i++) {
          if (header[i] != magic.codeUnitAt(i)) return false;
        }
        return true;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// ترميز base64 (للاستخدام المستقبلي)
  static String encodeKey(List<int> bytes) => base64Encode(bytes);
}

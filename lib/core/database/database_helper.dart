import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3_lib;
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import '../../features/products/data/models/product_model.dart';
import '../security/db_encryption.dart';
import '../services/error_logger.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// مفتاح التشفير الحالي (null = بدون تشفير)
  String? _dbKey;

  /// إشعارات منفصلة لكل نوع بيانات — كل صفحة تسمع فقط لتغييراتها
  static final ValueNotifier<int> productsRevision = ValueNotifier(0);
  static final ValueNotifier<int> salesRevision = ValueNotifier(0);
  static final ValueNotifier<int> debtsRevision = ValueNotifier(0);
  static final ValueNotifier<int> expensesRevision = ValueNotifier(0);
  /// للتوافق مع الكود القديم — يarten جميع الإشعارات
  static final ValueNotifier<int> revision = ValueNotifier(0);

  DatabaseHelper._init();

  static void _notifyAll() {
    revision.value++;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cashier_system.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // تحميل مكتبة SQLCipher إن وُجدت — قبل أي فتح للقاعدة
    DbEncryption.applyLibraryOverride();

    String dbPath;
    // على الديسكتوب نستخدم AppData عشان Program Files ما يسمح بالكتابة
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final appDataDir = Platform.environment['APPDATA']
          ?? Platform.environment['HOME']
          ?? '.';
      final cashierDir = Directory(join(appDataDir, 'CashierSystem'));
      if (!await cashierDir.exists()) {
        await cashierDir.create(recursive: true);
      }
      dbPath = cashierDir.path;
    } else {
      dbPath = await getDatabasesPath();
    }
    final path = join(dbPath, filePath);

    // ─── إدارة التشفير ───
    _dbKey = await DbEncryption.getKey();

    if (_dbKey != null && DbEncryption.cipherAvailable) {
      final isPlain = await DbEncryption.isPlaintextDb(path);
      if (isPlain && await File(path).exists()) {
        // قاعدة نصية قديمة → نشفرها في مكانها (ترحيل لمرة واحدة)
        try {
          await _encryptExistingDb(path, _dbKey!);
          await ErrorLogger.instance.info('تم تشفير قاعدة البيانات بنجاح (ترحيل تلقائي)');
        } catch (e) {
          await ErrorLogger.instance.error('فشل تشفير قاعدة البيانات — ستعمل بدون تشفير', data: {'error': '$e'});
          _dbKey = null; // نكمل بدون تشفير حتى لا يتعطل التطبيق
        }
      }
    } else {
      await ErrorLogger.instance.warning(
        'التشفير غير مفعّل — ضع sqlcipher.dll بجانب التطبيق لتفعيله',
      );
      _dbKey = null;
    }

    return await openDatabase(
      path,
      version: 14, // الإصدار 14: رقم الوصل
      onConfigure: _onConfigure, // مفتاح التشفير + العلاقات (Foreign Keys)
      onCreate: _createDB,
      onUpgrade: _upgradeDB, // التحديث الآمن
    );
  }

  /// تشفير قاعدة بيانات نصية موجودة باستخدام PRAGMA rekey
  Future<void> _encryptExistingDb(String path, String hexKey) async {
    final db = sqlite3_lib.sqlite3.open(path);
    try {
      db.execute(DbEncryption.rekeyPragma(hexKey));
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      db.dispose();
    }
  }

  /// مسار ملف قاعدة البيانات
  Future<String> getDbFilePath() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final appDataDir = Platform.environment['APPDATA'] 
          ?? Platform.environment['HOME'] 
          ?? '.';
      return join(appDataDir, 'CashierSystem', 'cashier_system.db');
    }
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'cashier_system.db');
  }

  static String get _backupDir {
    if (Platform.isWindows) {
      // محاولة استخدام D:\ أولاً، ثم مجلد المستخدم
      final dDrive = Directory(r'D:\');
      if (dDrive.existsSync()) return r'D:\.cashier_backup';
    }
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    return '$home${Platform.pathSeparator}.cashier_backup';
  }

  /// نسخ احتياطي لقاعدة البيانات في مجلد مخفي
  ///
  /// بعد النسخ يتم التحقق من سلامة النسخة تلقائياً — إذا فشل التحقق تُحذف النسخة ويرمى خطأ.
  Future<String> backupDatabase({String prefix = 'cashier_backup_'}) async {
    final srcPath = await getDbFilePath();
    final srcFile = File(srcPath);
    if (!await srcFile.exists()) throw Exception('ملف قاعدة البيانات غير موجود');

    // إنشاء المجلد إذا لم يكن موجوداً
    final dir = Directory(_backupDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      // جعل المجلد مخفياً على ويندوز
      if (Platform.isWindows) {
        await Process.run('attrib', ['+h', _backupDir]);
      }
    }

    final now = DateTime.now();
    final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
    final destPath = join(_backupDir, '$prefix$stamp.db');

    // إغلاق وإعادة فتح لضمان سلامة البيانات
    final db = await database;
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    await srcFile.copy(destPath);

    // ─── تحقق تلقائي فوري ───
    final verification = await verifyBackup(destPath);
    if (!verification.isValid) {
      try {
        await File(destPath).delete();
      } catch (_) {}
      throw Exception('فشل التحقق من سلامة النسخة: ${verification.message}');
    }

    // حفظ بصمة SHA-256 بجانب الملف
    await _writeChecksumSidecar(destPath);
    return destPath;
  }

  /// نسخ احتياطي تلقائي يومي — يُنفذ مرة واحدة يومياً عند أول تشغيل
  ///
  /// يعيد مسار النسخة إن أُنشئت، أو null إذا كان هناك نسخة اليوم بالفعل.
  Future<String?> autoBackupIfNeeded() async {
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final last = await getSetting('last_auto_backup', defaultValue: '');
      if (last == today) return null;

      final path = await backupDatabase(prefix: 'auto_');
      await setSetting('last_auto_backup', today);
      await _pruneOldAutoBackups();
      await ErrorLogger.instance.info('نسخ احتياطي تلقائي يومي', data: {'path': path});
      return path;
    } catch (e) {
      // لا نعطل بدء التطبيق أبداً بسبب فشل النسخ الاحتياطي
      await ErrorLogger.instance.error('فشل النسخ الاحتياطي التلقائي', data: {'error': '$e'});
      return null;
    }
  }

  /// الاحتفاظ بآخر [maxKeep] نسخ تلقائية وحذف الأقدم
  static const int maxAutoBackups = 7;

  Future<void> _pruneOldAutoBackups() async {
    try {
      final dir = Directory(_backupDir);
      if (!await dir.exists()) return;
      final autos = <File>[];
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.db')) {
          final name = f.uri.pathSegments.last;
          if (name.startsWith('auto_')) autos.add(f);
        }
      }
      autos.sort((a, b) => b.path.compareTo(a.path)); // الأحدث أولاً
      for (var i = maxAutoBackups; i < autos.length; i++) {
        try {
          await autos[i].delete();
          final sidecar = File('${autos[i].path}.sha256');
          if (await sidecar.exists()) await sidecar.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// قائمة ملفات النسخ الاحتياطي
  Future<List<FileSystemEntity>> listBackups() async {
    final dir = Directory(_backupDir);
    if (!await dir.exists()) return [];
    final files = await dir.list().where((f) => f.path.endsWith('.db')).toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // الأحدث أولاً
    return files;
  }

  // ═══════════ التحقق من النسخ الاحتياطية ═══════════

  /// حساب SHA-256 لملف (بث تدريجي لتوفير الذاكرة)
  static Future<String> computeFileSha256(String path) async {
    final output = _DigestSink();
    final input = crypto.sha256.startChunkedConversion(output);
    await for (final chunk in File(path).openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.digest.toString();
  }

  /// كتابة ملف بصمة بجانب النسخة الاحتياطية
  static Future<void> _writeChecksumSidecar(String dbPath) async {
    try {
      final hash = await computeFileSha256(dbPath);
      await File('$dbPath.sha256').writeAsString(hash);
    } catch (_) {}
  }

  /// التحقق من صلاحية نسخة احتياطية
  ///
  /// يفحص: وجود الملف وحجمه، تكامل البيانات الداخلية، وجود الجداول الأساسية.
  Future<BackupVerificationResult> verifyBackup(String path) async {
    // 1. وجود الملف وحجمه
    final file = File(path);
    if (!await file.exists()) {
      return BackupVerificationResult(false, 'الملف غير موجود');
    }
    final size = await file.length();
    if (size < 4096) {
      return BackupVerificationResult(false, 'حجم الملف صغير جداً ($size بايت) — ملف تالف');
    }

    // 2. تحديد نوع الملف (مشفر أم نصي)
    final plain = await DbEncryption.isPlaintextDb(path);

    // 3. التحقق من بصمة SHA-256 إن وجدت
    final sidecar = File('$path.sha256');
    String? hashNote;
    if (await sidecar.exists()) {
      try {
        final expected = (await sidecar.readAsString()).trim();
        final actual = await computeFileSha256(path);
        if (expected != actual) {
          return BackupVerificationResult(
            false,
            'بصمة SHA-256 لا تتطابق — الملف عدّل أو تالف',
          );
        }
        hashNote = 'البصمة متطابقة ✓';
      } catch (_) {}
    }

    // 4. الفتح والتكامل الداخلي
    sqlite3_lib.Database? raw;
    try {
      raw = sqlite3_lib.sqlite3.open(path);

      // تطبيق مفتاح التشفير على الملفات المشفرة
      if (!plain && _dbKey != null) {
        raw.execute(DbEncryption.keyPragma(_dbKey!));
      }

      // اختبار قراءة حقيقية بعد المفتاح — يفشل هنا لو المفتاح/التشفير خاطئ
      final integrity = raw.select('PRAGMA integrity_check');
      if (integrity.isEmpty ||
          integrity.first.values.first.toString().toLowerCase() != 'ok') {
        return BackupVerificationResult(false, 'فشل فحص integrity_check');
      }

      // 5. الجداول الأساسية موجودة؟
      const requiredTables = [
        'products', 'categories', 'sales', 'sale_items', 'settings', 'debts',
      ];
      final counts = <String, int>{};
      for (final t in requiredTables) {
        final exists = raw.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [t],
        );
        if (exists.isEmpty) {
          return BackupVerificationResult(false, 'جدول "$t" مفقود من النسخة');
        }
        counts[t] = raw.select('SELECT COUNT(*) c FROM $t').first['c'] as int;
      }

      return BackupVerificationResult(
        true,
        hashNote ?? 'سلامة كاملة ✓ (بدون بصمة محفوظة)',
        tableCounts: counts,
      );
    } catch (e) {
      final hint = (!plain && _dbKey == null)
          ? ' — قد تكون مشفرة والمفتاح غير متوفر'
          : '';
      return BackupVerificationResult(false, 'تعذر فتح الملف$hint: $e');
    } finally {
      try {
        raw?.dispose();
      } catch (_) {}
    }
  }

  /// استيراد قاعدة بيانات من ملف نسخة احتياطية — **ذرّي وآمن**
  ///
  /// الترتيب: تحقق النسخة الأصلية ← إغلاق القاعدة ← نسخ إلى ملف مؤقت ←
  /// تحقق المؤقت ← الاحتفاظ بنسخة أمان من الحالي ← تبديل ذرّي (rename) ←
  /// فتح. عند أي فشل: تراجع تلقائي للنسخة السابقة ولا تُلمس البيانات.
  Future<bool> restoreDatabase(String backupPath) async {
    File? tmpFile;
    String? bakPath;
    try {
      // ─── 1. تحقق النسخة المصدر ───
      final verification = await verifyBackup(backupPath);
      if (!verification.isValid) {
        await ErrorLogger.instance.error(
          'رُفض استيراد نسخة تالفة',
          data: {'path': backupPath, 'reason': verification.message},
        );
        return false;
      }

      final destPath = await getDbFilePath();

      // checkpoint قبل الإغلاق لضمان كتابة كل شيء في الملف الرئيسي
      if (_database != null) {
        try {
          await _database!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          await _database!.close();
        } catch (_) {}
        _database = null;
      }

      // ─── 2. نسخ إلى ملف مؤقت بجانب الوجهة (نفس القرص = rename ذرّي) ───
      tmpFile = File('$destPath.restore_tmp');
      if (await tmpFile.exists()) await tmpFile.delete();
      await File(backupPath).copy(tmpFile.path);

      // ─── 3. تحقق الملف المنسوخ (ليس الأصلي فقط) ───
      final tmpCheck = await verifyBackup(tmpFile.path);
      if (!tmpCheck.isValid) {
        throw Exception('النسخة فشلت بعد النسخ: ${tmpCheck.message}');
      }

      // ─── 4. نسخة أمان من القاعدة الحية + تنظيف WAL/SHM القديمة ───
      final live = File(destPath);
      if (await live.exists()) {
        bakPath = '$destPath.bak_before_restore';
        final oldBak = File(bakPath);
        if (await oldBak.exists()) await oldBak.delete();
        await live.rename(bakPath);
      }
      for (final suffix in ['-wal', '-shm']) {
        final f = File('$destPath$suffix');
        if (await f.exists()) await f.delete();
      }

      // ─── 5. التبديل الذرّي ───
      await tmpFile.rename(destPath);
      tmpFile = null; // نجح النقل

      // ─── 6. فتح القاعدة الجديدة ───
      _database = await _initDB('cashier_system.db');
      revision.value++;
      await ErrorLogger.instance.info('تم استيراد نسخة احتياطية بنجاح', data: {'path': backupPath});
      return true;
    } catch (e) {
      await ErrorLogger.instance.error('فشل الاستيراد — تراجع للنسخة السابقة', data: {'error': '$e'});
      // ─── Rollback: إرجاع نسخة الأمان إن كان التبديل قد بدأ ───
      try {
        final destPath = await getDbFilePath();
        if (bakPath != null) {
          final bak = File(bakPath);
          if (await bak.exists()) {
            final broken = File(destPath);
            if (await broken.exists()) await broken.delete();
            await bak.rename(destPath);
          }
        }
      } catch (rollbackErr) {
        await ErrorLogger.instance.critical('فشل حتى التراجع!', data: {'rollback': '$rollbackErr'});
      }
      return false;
    } finally {
      // تنظيف الملفات المؤقتة مهما حدث
      try {
        if (tmpFile != null && await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
    }
  }

  // أول أمر على كل اتصال: مفتاح التشفير (إن كان مفعلاً) ثم Foreign Keys
  Future _onConfigure(Database db) async {
    if (_dbKey != null) {
      await db.execute(DbEncryption.keyPragma(_dbKey!));
    }
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _createDB(Database db, int version) async {
    // 1. جدول المنتجات
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        color TEXT,
        size TEXT,
        price INTEGER NOT NULL,
        purchase_price INTEGER NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        barcode TEXT,
        is_custom_barcode INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_product_barcode ON products (barcode);');

    // إذا كان الإصدار الأول هو نفسه الأخير (تثبيت جديد)، ننشئ الجداول الجديدة فوراً
    await _createV2Tables(db);
    await _createV4Tables(db);
    await _createV5Tables(db);
    await _createV6Tables(db);
    await _createV7Tables(db);
    await _createV8Tables(db);
    await _createV9Tables(db);
    await _createV10Tables(db);
    await _createV11Tables(db);
    await _createV12Tables(db);
    await _createV13Tables(db);
    await _createV14Tables(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createV2Tables(db);
    }
    if (oldVersion < 3) {
      // إضافة عمود سعر الشراء بدون حذف البيانات القديمة
      await db.execute('ALTER TABLE products ADD COLUMN purchase_price INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      await _createV4Tables(db);
      // نقل الباركودات الموجودة في جدول products إلى الجدول الجديد
      await db.execute('''
        INSERT OR IGNORE INTO product_barcodes (product_id, barcode)
        SELECT id, barcode FROM products WHERE barcode IS NOT NULL AND barcode != ''
      ''');
    }
    if (oldVersion < 5) {
      await _createV5Tables(db);
    }
    if (oldVersion < 6) {
      await _createV6Tables(db);
    }
    if (oldVersion < 7) {
      await _createV7Tables(db);
    }
    if (oldVersion < 8) {
      await _createV8Tables(db);
    }
    if (oldVersion < 9) {
      await _createV9Tables(db);
    }
    if (oldVersion < 10) {
      await _createV10Tables(db);
    }
    if (oldVersion < 11) {
      await _createV11Tables(db);
    }
    if (oldVersion < 12) {
      await _createV12Tables(db);
    }
    if (oldVersion < 13) {
      await _createV13Tables(db);
    }
    if (oldVersion < 14) {
      await _createV14Tables(db);
    }
  }

  Future _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_barcodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        barcode TEXT NOT NULL UNIQUE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_barcode ON product_barcodes (barcode);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pb_product ON product_barcodes (product_id);');
  }

  // دالة مساعدة لإنشاء جداول التحديث الجديد (الإصدار 2)
  Future _createV2Tables(Database db) async {
    // 2. جدول الأقسام (Categories)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
    
    // إضافة أقسام افتراضية للمحل
    await db.insert('categories', {'name': 'مكياج'});
    await db.insert('categories', {'name': 'عطور'});
    await db.insert('categories', {'name': 'عناية بالبشرة'});

    // 3. جدول الطلبات المعلقة (الفاتورة الأساسية)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suspended_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note TEXT, -- ملاحظة للتعرف على الزبونة
        created_at TEXT NOT NULL
      )
    ''');

    // 4. جدول منتجات الفاتورة المعلقة (تفاصيل الفاتورة)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suspended_order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES suspended_orders (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
      )
    ''');
  }

  // ============================================================
  // دوال إدارة الباركودات المتعددة (product_barcodes)
  // ============================================================
  Future<List<Map<String, dynamic>>> getBarcodesForProduct(int productId) async {
    try {
      final db = await instance.database;
      return await db.query('product_barcodes',
          where: 'product_id = ?', whereArgs: [productId], orderBy: 'id ASC');
    } catch (e) {
      return [];
    }
  }

  Future<int> addBarcode(int productId, String barcode) async {
    try {
      final db = await instance.database;
      return await db.insert('product_barcodes', {
        'product_id': productId,
        'barcode': barcode,
      }, conflictAlgorithm: ConflictAlgorithm.fail);
    } catch (e) {
      print('Error adding barcode: $e');
      return -1;
    }
  }

  Future<int> updateBarcode(int barcodeId, String newBarcode) async {
    try {
      final db = await instance.database;
      return await db.update('product_barcodes', {'barcode': newBarcode},
          where: 'id = ?', whereArgs: [barcodeId]);
    } catch (e) {
      print('Error updating barcode: $e');
      return -1;
    }
  }

  Future<int> removeBarcode(int barcodeId) async {
    try {
      final db = await instance.database;
      return await db.delete('product_barcodes',
          where: 'id = ?', whereArgs: [barcodeId]);
    } catch (e) {
      return 0;
    }
  }

  Future close() async {
    final db = await instance.database;
    await db.close();
    _database = null;
  }

  // ==========================================================
  // دوال الإدخال والقراءة (القديمة الخاصة بالمنتجات)
  // ==========================================================
  Future<int> insertProduct(ProductModel product) async {
    try {
      final db = await instance.database;
      int productId = -1;
      await db.transaction((txn) async {
        productId = await txn.insert('products', product.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (product.barcode.isNotEmpty) {
          await txn.insert('product_barcodes', {
            'product_id': productId,
            'barcode': product.barcode,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
      if (productId > 0) { productsRevision.value++; _notifyAll(); }
      return productId;
    } catch (e) {
      print('Error inserting product: $e');
      return -1;
    }
  }

  Future<List<ProductModel>> getAllProducts() async {
    try {
      final db = await instance.database;
      final maps = await db.query('products', orderBy: 'id DESC');
      return maps.map((map) => ProductModel.fromMap(map)).toList();
    } catch (e) {
      print('Error fetching products: $e');
      return []; 
    }
  }

  Future<ProductModel?> getProductByBarcode(String barcode) async {
    try {
      final db = await instance.database;
      // بحث أولاً في جدول الباركودات المتعددة
      final maps = await db.rawQuery('''
        SELECT p.* FROM products p
        INNER JOIN product_barcodes pb ON pb.product_id = p.id
        WHERE pb.barcode = ?
        LIMIT 1
      ''', [barcode]);
      if (maps.isNotEmpty) return ProductModel.fromMap(maps.first);
      // بحث احتياطي في products.barcode مباشرة
      final fallback = await db.query('products',
          where: 'barcode = ?', whereArgs: [barcode], limit: 1);
      if (fallback.isNotEmpty) return ProductModel.fromMap(fallback.first);
      return null;
    } catch (e) {
      print('Error fetching product by barcode: $e');
      return null;
    }
  }

  Future<int> updateProduct(ProductModel product) async {
    try {
      final db = await instance.database;
      final rows = await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
      if (rows > 0) {
        // مزامنة products.barcode من أول باركود في product_barcodes (المصدر الأساسي)
        final existingBarcodes = await db.query('product_barcodes',
            where: 'product_id = ?', whereArgs: [product.id], orderBy: 'id ASC', limit: 1);
        if (existingBarcodes.isNotEmpty) {
          final firstBarcode = existingBarcodes.first['barcode'] as String;
          if (firstBarcode != product.barcode) {
            await db.update('products', {'barcode': firstBarcode},
                where: 'id = ?', whereArgs: [product.id]);
          }
        }
        productsRevision.value++;
        _notifyAll();
      }
      return rows;
    } catch (e) {
      print('Error updating product: $e');
      return 0; 
    }
  }

  // ==========================================================
  // دوال الأقسام الجديدة (Categories CRUD)
  // ==========================================================
  Future<int> insertCategory(String name) async {
    try {
      final db = await instance.database;
      return await db.insert('categories', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (e) {
      print('Error inserting category: $e');
      return -1;
    }
  }

  Future<List<String>> getAllCategories() async {
    try {
      final db = await instance.database;
      final maps = await db.query('categories', orderBy: 'name ASC');
      return maps.map((map) => map['name'] as String).toList();
    } catch (e) {
      print('Error fetching categories: $e');
      return [];
    }
  }

  Future<int> updateCategory(String oldName, String newName) async {
    try {
      final db = await instance.database;
      final rows = await db.update(
        'categories',
        {'name': newName},
        where: 'name = ?',
        whereArgs: [oldName],
      );
      if (rows > 0) {
        await db.update('products', {'category': newName}, where: 'category = ?', whereArgs: [oldName]);
        productsRevision.value++;
        _notifyAll();
      }
      return rows;
    } catch (e) {
      print('Error updating category: $e');
      return 0;
    }
  }

  Future<int> deleteCategory(String name) async {
    try {
      final db = await instance.database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM products WHERE category = ?', [name]),
      );
      if (count != null && count > 0) return -1;
      final rows = await db.delete('categories', where: 'name = ?', whereArgs: [name]);
      if (rows > 0) { productsRevision.value++; _notifyAll(); }
      return rows;
    } catch (e) {
      print('Error deleting category: $e');
      return 0;
    }
  }

  // ==========================================================
  // دوال مساعدة للباركود والحذف
  // ==========================================================
  Future<bool> barcodeExists(String barcode) async {
    if (barcode.isEmpty) return false;
    try {
      final db = await instance.database;
      final result = await db.query('product_barcodes',
          where: 'barcode = ?', whereArgs: [barcode], limit: 1);
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<int> deleteProduct(int id) async {
    try {
      final db = await instance.database;
      final rows = await db.delete('products', where: 'id = ?', whereArgs: [id]);
      if (rows > 0) { productsRevision.value++; _notifyAll(); }
      return rows;
    } catch (e) {
      print('Error deleting product: $e');
      return 0;
    }
  }

  // ==========================================================
  // دوال الفواتير المعلقة (Suspended Orders)
  // ==========================================================
  Future<int> saveSuspendedOrder(List<Map<String, dynamic>> cart, String note, {int discountAmount = 0, bool isDiscountPercent = false}) async {
    try {
      final db = await instance.database;
      int orderId = -1;
      await db.transaction((txn) async {
        orderId = await txn.insert('suspended_orders', {
          'note': note.trim().isEmpty ? null : note.trim(),
          'created_at': DateTime.now().toIso8601String(),
          'discount_amount': discountAmount,
          'is_discount_percent': isDiscountPercent ? 1 : 0,
        });
        for (final item in cart) {
          final product = item['product'] as ProductModel;
          await txn.insert('suspended_order_items', {
            'order_id': orderId,
            'product_id': product.id,
            'quantity': item['quantity'] as int,
            'unit_price': product.price,
          });
        }
      });
      return orderId;
    } catch (e) {
      await ErrorLogger.instance.error('فشل تعليق الفاتورة', data: {'error': '$e'});
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getSuspendedOrders() async {
    try {
      final db = await instance.database;
      return await db.query('suspended_orders', orderBy: 'created_at DESC');
    } catch (e) {
      print('Error fetching suspended orders: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getSuspendedOrderCartWithWarning(int orderId) async {
    try {
      final db = await instance.database;
      final items = await db.query('suspended_order_items',
          where: 'order_id = ?', whereArgs: [orderId]);
      final List<Map<String, dynamic>> cart = [];
      int missingCount = 0;
      for (final item in items) {
        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int;
        final unitPrice = item['unit_price'] as int;
        final productMaps =
            await db.query('products', where: 'id = ?', whereArgs: [productId]);
        if (productMaps.isNotEmpty) {
          // استخدام السعر المحفوظ وقت التعليق بدل السعر الحالي
          final product = ProductModel.fromMap(productMaps.first);
          final snapshotProduct = product.copyWith(price: unitPrice);
          cart.add({
            'product': snapshotProduct,
            'quantity': quantity,
          });
        } else {
          missingCount++;
        }
      }
      return {'cart': cart, 'missing': missingCount};
    } catch (e) {
      print('Error fetching suspended order cart: $e');
      return {'cart': <Map<String, dynamic>>[], 'missing': 0};
    }
  }

  Future<bool> deleteSuspendedOrder(int orderId) async {
    try {
      final db = await instance.database;
      final rows = await db.delete('suspended_orders', where: 'id = ?', whereArgs: [orderId]);
      return rows > 0;
    } catch (e) {
      await ErrorLogger.instance.error('فشل حذف فاتورة معلقة', data: {'order_id': orderId, 'error': '$e'});
      return false;
    }
  }

  // ==========================================================
  // الحفظ التلقائي للسلة (Draft)
  // ==========================================================

  /// حفظ السلة الحالية كمسودة تلقائية (بدون مطالبة المستخدم)
  Future<void> saveAutoDraft(List<Map<String, dynamic>> cart, {int discountAmount = 0, bool isDiscountPercent = false}) async {
    if (cart.isEmpty) return;
    try {
      final db = await instance.database;
      // حذف المسودة التلقائية القديمة
      await db.delete('suspended_orders', where: 'note = ?', whereArgs: ['__auto_draft__']);
      // حفظ مسودة جديدة
      await db.transaction((txn) async {
        final orderId = await txn.insert('suspended_orders', {
          'note': '__auto_draft__',
          'created_at': DateTime.now().toIso8601String(),
          'discount_amount': discountAmount,
          'is_discount_percent': isDiscountPercent ? 1 : 0,
        });
        for (final item in cart) {
          final product = item['product'] as ProductModel;
          await txn.insert('suspended_order_items', {
            'order_id': orderId,
            'product_id': product.id,
            'quantity': item['quantity'] as int,
            'unit_price': product.price,
          });
        }
      });
    } catch (_) {}
  }

  /// استرجاع المسودة التلقائية (إذا وُجدت)
  Future<Map<String, dynamic>?> loadAutoDraft() async {
    try {
      final db = await instance.database;
      final orders = await db.query('suspended_orders', where: 'note = ?', whereArgs: ['__auto_draft__'], limit: 1);
      if (orders.isEmpty) return null;
      final orderId = orders.first['id'] as int;
      final items = await db.query('suspended_order_items', where: 'order_id = ?', whereArgs: [orderId]);
      final List<Map<String, dynamic>> cart = [];
      for (final item in items) {
        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int;
        final unitPrice = item['unit_price'] as int;
        final productMaps = await db.query('products', where: 'id = ?', whereArgs: [productId]);
        if (productMaps.isNotEmpty) {
          final product = ProductModel.fromMap(productMaps.first).copyWith(price: unitPrice);
          cart.add({'product': product, 'quantity': quantity});
        }
      }
      if (cart.isEmpty) {
        await db.delete('suspended_orders', where: 'id = ?', whereArgs: [orderId]);
        return null;
      }
      return {
        'cart': cart,
        'discount_amount': orders.first['discount_amount'] as int? ?? 0,
        'is_discount_percent': (orders.first['is_discount_percent'] as int? ?? 0) == 1,
        'order_id': orderId,
      };
    } catch (_) {
      return null;
    }
  }

  /// حذف المسودة التلقائية بعد استرجاعها
  Future<void> clearAutoDraft(int orderId) async {
    try {
      final db = await instance.database;
      await db.delete('suspended_order_items', where: 'order_id = ?', whereArgs: [orderId]);
      await db.delete('suspended_orders', where: 'id = ?', whereArgs: [orderId]);
    } catch (_) {}
  }

  // ==========================================================
  // جداول المبيعات (v5)
  // ==========================================================
  Future _createV5Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_amount INTEGER NOT NULL,
        total_profit INTEGER NOT NULL DEFAULT 0,
        items_count INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date ON sales (created_at);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL,
        purchase_price INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
      )
    ''');
  }

  // ==========================================================
  // دوال المبيعات (Sales)
  // ==========================================================

  /// إتمام عملية البيع: حفظ الفاتورة + تخفيض المخزون (Transactional)
  Future<int> completeSale(List<Map<String, dynamic>> cart, {int discountValue = 0}) async {
    try {
    final db = await instance.database;
    int saleId = -1;
    await db.transaction((txn) async {
      int subtotal = 0;
      int itemsProfit = 0;
      int itemsCount = 0;

      for (final item in cart) {
        final product = item['product'] as ProductModel;
        final qty = item['quantity'] as int;
        final itemPrice = (item['custom_price'] as int?) ?? product.price;
        final itemDiscount = (item['item_discount'] as int?) ?? 0;
        final effectivePrice = itemPrice - itemDiscount;
        subtotal += effectivePrice * qty;
        itemsProfit += (effectivePrice - product.purchasePrice) * qty;
        itemsCount += qty;
      }

      final clampedProfit = (itemsProfit - discountValue).clamp(0, itemsProfit);
      // توليد رقم الوصل
      final lastSale = await txn.rawQuery('SELECT id FROM sales ORDER BY id DESC LIMIT 1');
      final nextId = (lastSale.isEmpty ? 0 : lastSale.first['id'] as int) + 1;
      final receiptNumber = 'R${nextId.toString().padLeft(6, '0')}';
      saleId = await txn.insert('sales', {
        'total_amount': subtotal - discountValue,
        'total_profit': clampedProfit,
        'items_count': itemsCount,
        'discount_amount': discountValue,
        'receipt_number': receiptNumber,
        'created_at': DateTime.now().toIso8601String(),
      });

      for (final item in cart) {
        final product = item['product'] as ProductModel;
        final qty = item['quantity'] as int;
        final itemPrice = (item['custom_price'] as int?) ?? product.price;
        final itemDiscount = (item['item_discount'] as int?) ?? 0;
        final effectivePrice = itemPrice - itemDiscount;
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': product.id,
          'product_name': product.name,
          'quantity': qty,
          'unit_price': effectivePrice,
          'purchase_price': product.purchasePrice,
        });
        // تخفيض المخزون (حماية من السالب)
        final updated = await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?',
          [qty, product.id, qty],
        );
        if (updated == 0) {
          throw Exception('المخزون غير كافٍ للمنتج "${product.name}"');
        }
      }
    });
    if (saleId > 0) { salesRevision.value++; productsRevision.value++; _notifyAll(); }
    return saleId;
    } catch (e, st) {
      print('ERROR completeSale: $e');
      print(st);
      return -1;
    }
  }

  /// جلب تفاصيل فاتورة معينة
  Future<List<Map<String, dynamic>>> getSaleItems(int saleId) async {
    try {
      final db = await instance.database;
      return await db.query('sale_items',
          where: 'sale_id = ?', whereArgs: [saleId]);
    } catch (e) {
      return [];
    }
  }

  /// ملخص المبيعات (اليوم + الكل)
  Future<Map<String, int>> getSalesSummary() async {
    try {
      final db = await instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final todayResult = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0) as revenue, COALESCE(SUM(total_profit), 0) as profit, COUNT(*) as count FROM sales WHERE created_at LIKE ?",
        ['$today%'],
      );
      final allResult = await db.rawQuery(
        'SELECT COALESCE(SUM(total_amount), 0) as revenue, COALESCE(SUM(total_profit), 0) as profit, COUNT(*) as count FROM sales',
      );

      return {
        'today_revenue': todayResult.first['revenue'] as int? ?? 0,
        'today_profit': todayResult.first['profit'] as int? ?? 0,
        'today_count': todayResult.first['count'] as int? ?? 0,
        'all_revenue': allResult.first['revenue'] as int? ?? 0,
        'all_profit': allResult.first['profit'] as int? ?? 0,
        'all_count': allResult.first['count'] as int? ?? 0,
      };
    } catch (e) {
      return {'today_revenue': 0, 'today_profit': 0, 'today_count': 0, 'all_revenue': 0, 'all_profit': 0, 'all_count': 0};
    }
  }

  /// جلب مبيعات ضمن فترة زمنية
  Future<List<Map<String, dynamic>>> getSalesByDateRange(String from, String to) async {
    try {
      final db = await instance.database;
      return await db.query('sales',
          where: "created_at >= ? AND created_at < ?",
          whereArgs: [from, to],
          orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  /// البحث برقم الوصل
  Future<List<Map<String, dynamic>>> searchSalesByReceipt(String query) async {
    try {
      final db = await instance.database;
      return await db.query('sales',
          where: "receipt_number LIKE ?",
          whereArgs: ['%$query%'],
          orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  /// ملخص مبيعات ضمن فترة زمنية
  Future<Map<String, int>> getSalesSummaryByDateRange(String from, String to) async {
    try {
      final db = await instance.database;
      final result = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0) as revenue, COALESCE(SUM(total_profit), 0) as profit, COUNT(*) as count FROM sales WHERE created_at >= ? AND created_at < ?",
        [from, to],
      );
      return {
        'revenue': result.first['revenue'] as int? ?? 0,
        'profit': result.first['profit'] as int? ?? 0,
        'count': result.first['count'] as int? ?? 0,
      };
    } catch (e) {
      return {'revenue': 0, 'profit': 0, 'count': 0};
    }
  }

  // ==========================================================
  // جدول الإعدادات (v6)
  // ==========================================================
  Future _createV6Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    // القيم الافتراضية
    final defaults = {
      'store_name': 'أحلى الحلوين',
      'store_phone': '',
      'currency': 'دينار',
      'low_stock_threshold': '5',
      'default_barcode_copies': '1',
      'receipt_footer': 'شكراً لزيارتكم',
    };
    for (final entry in defaults.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future _createV7Tables(Database db) async {
    final batch = db.batch();
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_title_font_size', '14')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_body_font_size', '9')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_paper_width_mm', '78')");
    await batch.commit(noResult: true);
  }

  Future _createV8Tables(Database db) async {
    // إعدادات أبعاد الباركود + هوامش الطباعة + الطابعة الافتراضية
    final batch = db.batch();
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('barcode_label_width_mm', '40')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('barcode_label_height_mm', '25')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('barcode_padding_top_mm', '2')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('barcode_padding_bottom_mm', '2')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('barcode_padding_left_mm', '2')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('barcode_padding_right_mm', '2')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_margin_mm', '3')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('default_printer_url', '')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('default_printer_name', '')");
    await batch.commit(noResult: true);
  }

  // ==========================================================
  // دوال الإعدادات (Settings CRUD)
  // ==========================================================

  /// جلب قيمة إعداد معين (مع قيمة افتراضية إذا لم يوجد)
  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    try {
      final db = await instance.database;
      final result = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
      if (result.isNotEmpty) return result.first['value'] as String;
      return defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  /// حفظ قيمة إعداد (INSERT OR REPLACE)
  Future<void> setSetting(String key, String value) async {
    try {
      final db = await instance.database;
      await db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('Error saving setting $key: $e');
    }
  }

  /// جلب كل الإعدادات كـ Map
  Future<Map<String, String>> getAllSettings() async {
    try {
      final db = await instance.database;
      final rows = await db.query('settings');
      return {for (final r in rows) r['key'] as String: r['value'] as String};
    } catch (e) {
      return {};
    }
  }

  // ==========================================================
  // الإصدار 9: حفظ الخصم
  // ==========================================================
  Future _createV9Tables(Database db) async {
    // إضافة أعمدة بأمان — نتجاهل الخطأ إذا العمود موجود مسبقاً
    try { await db.execute('ALTER TABLE sales ADD COLUMN discount_amount INTEGER DEFAULT 0'); } catch (_) {}
    try { await db.execute('ALTER TABLE suspended_orders ADD COLUMN discount_amount INTEGER DEFAULT 0'); } catch (_) {}
    try { await db.execute('ALTER TABLE suspended_orders ADD COLUMN is_discount_percent INTEGER DEFAULT 0'); } catch (_) {}
  }

  // ==========================================================
  // الإصدار 10: جدول الديون
  // ==========================================================
  Future _createV10Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        phone TEXT,
        amount INTEGER NOT NULL,
        paid INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        sale_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_customer ON debts (customer_name);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_date ON debts (created_at);');
  }

  // ==========================================================
  // الإصدار 11: جدول سجل الدفعات
  // ==========================================================
  Future _createV11Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dp_debt ON debt_payments (debt_id);');
  }

  // ==========================================================
  // الإصدار 12: ديون المحل والمصروفات
  // ==========================================================
  Future _createV12Tables(Database db) async {
    // ديون المحل (المطلوب من المحل للمندوبين/الشركات)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shop_debts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_name TEXT NOT NULL,
        phone TEXT,
        amount INTEGER NOT NULL,
        paid INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sd_supplier ON shop_debts (supplier_name);');

    // سجل دفعات ديون المحل
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shop_debt_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        debt_id INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (debt_id) REFERENCES shop_debts (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sdp_debt ON shop_debt_payments (debt_id);');

    // المصروفات العامة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount INTEGER NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses (created_at);');
  }

  // ==========================================================
  // الإصدار 13: سجل تصحيح الجرد
  // ==========================================================
  Future _createV13Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        old_stock INTEGER NOT NULL,
        new_stock INTEGER NOT NULL,
        difference INTEGER NOT NULL,
        reason TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sa_product ON stock_adjustments (product_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sa_date ON stock_adjustments (created_at);');
  }

  Future _createV14Tables(Database db) async {
    try { await db.execute('ALTER TABLE sales ADD COLUMN receipt_number TEXT'); } catch (_) {}
    // ترقيم الفواتور القديمة
    await db.rawUpdate('''
      UPDATE sales SET receipt_number = 'R' || id WHERE receipt_number IS NULL
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_receipt ON sales (receipt_number);');
  }

  /// تصحيح جرد منتج يدوياً مع تسجيل السبب
  ///
  /// يعيد true عند النجاح. يُرفض التعديل إذا كان الرقم سالباً أو لم يتغير.
  Future<bool> adjustStock(int productId, int newStock, String reason) async {
    if (newStock < 0) return false;
    try {
      final db = await instance.database;
      return await db.transaction((txn) async {
        final rows = await txn.query('products', where: 'id = ?', whereArgs: [productId]);
        if (rows.isEmpty) return false;
        final product = ProductModel.fromMap(rows.first);
        final oldStock = product.stock;
        if (newStock == oldStock) return false;

        await txn.update(
          'products',
          {'stock': newStock},
          where: 'id = ?',
          whereArgs: [productId],
        );

        final now = DateTime.now().toIso8601String();
        await txn.insert('stock_adjustments', {
          'product_id': productId,
          'product_name': product.name,
          'old_stock': oldStock,
          'new_stock': newStock,
          'difference': newStock - oldStock,
          'reason': reason.trim(),
          'created_at': now,
        });
        return true;
      });
    } catch (e) {
      await ErrorLogger.instance.error('فشل تصحيح الجرد', data: {'product_id': productId, 'error': '$e'});
      return false;
    }
  }

  /// سجل تصحيحات الجرد لمنتج معين (الأحدث أولاً)
  Future<List<Map<String, dynamic>>> getAdjustmentsForProduct(int productId) async {
    try {
      final db = await instance.database;
      return await db.query(
        'stock_adjustments',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'created_at DESC',
        limit: 50,
      );
    } catch (_) {
      return [];
    }
  }

  /// سجل تصحيحات الجرد لجميع المنتجات (الأحدث أولاً)
  Future<List<Map<String, dynamic>>> getAllAdjustments() async {
    try {
      final db = await instance.database;
      return await db.rawQuery('''
        SELECT sa.*, p.name as product_name
        FROM stock_adjustments sa
        LEFT JOIN products p ON sa.product_id = p.id
        ORDER BY sa.created_at DESC
        LIMIT 100
      ''');
    } catch (_) {
      return [];
    }
  }

  /// جلب بيانات الخصم من فاتورة معلقة
  Future<Map<String, int>> getSuspendedOrderDiscount(int orderId) async {
    try {
      final db = await instance.database;
      final rows = await db.query('suspended_orders', where: 'id = ?', whereArgs: [orderId]);
      if (rows.isEmpty) return {'discount_amount': 0, 'is_discount_percent': 0};
      return {
        'discount_amount': rows.first['discount_amount'] as int? ?? 0,
        'is_discount_percent': rows.first['is_discount_percent'] as int? ?? 0,
      };
    } catch (e) {
      return {'discount_amount': 0, 'is_discount_percent': 0};
    }
  }

  /// إرجاع فاتورة كاملة: حذف البيع + إعادة المخزون (Transactional)
  Future<bool> returnSale(int saleId) async {
    try {
      final db = await instance.database;
      await db.transaction((txn) async {
        final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        for (final item in items) {
          final productId = item['product_id'] as int;
          final qty = item['quantity'] as int;
          await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [qty, productId]);
        }
        await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
      });
      salesRevision.value++;
      productsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error returning sale: $e');
      return false;
    }
  }

  /// إرجاع جزئي: returnQtys = {sale_item_id: qty_to_return}
  /// يرجع المخزون ويعدّل الفاتورة (أو يحذفها إذا رجعت كلها)
  Future<bool> partialReturnSale(int saleId, Map<int, int> returnQtys) async {
    if (returnQtys.isEmpty) return false;
    try {
      final db = await instance.database;
      await db.transaction((txn) async {
        int returnedAmount = 0;
        int returnedProfit = 0;
        int returnedCount = 0;

        for (final entry in returnQtys.entries) {
          final itemId = entry.key;
          final retQty = entry.value;
          if (retQty <= 0) continue;

          final rows = await txn.query('sale_items', where: 'id = ?', whereArgs: [itemId]);
          if (rows.isEmpty) continue;
          final row = rows.first;

          final productId = row['product_id'] as int;
          final currentQty = row['quantity'] as int;
          final unitPrice = row['unit_price'] as int;
          final purchasePrice = row['purchase_price'] as int? ?? 0;
          final actualReturn = retQty.clamp(0, currentQty);

          if (actualReturn <= 0) continue;

          // إعادة المخزون
          await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [actualReturn, productId]);

          if (actualReturn >= currentQty) {
            // حذف البند بالكامل
            await txn.delete('sale_items', where: 'id = ?', whereArgs: [itemId]);
          } else {
            // تقليل الكمية
            await txn.update('sale_items', {'quantity': currentQty - actualReturn},
                where: 'id = ?', whereArgs: [itemId]);
          }

          returnedAmount += unitPrice * actualReturn;
          returnedProfit += (unitPrice - purchasePrice) * actualReturn;
          returnedCount += actualReturn;
        }

        // تحديث أو حذف الفاتورة الرئيسية
        final remainingItems = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
        if (remainingItems.isEmpty) {
          await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
        } else {
          // تحديث المبلغ والربح والعدد
          await txn.rawUpdate('''
            UPDATE sales SET
              total_amount = total_amount - ?,
              total_profit = MAX(0, total_profit - ?),
              items_count = items_count - ?
            WHERE id = ?
          ''', [returnedAmount, returnedProfit, returnedCount, saleId]);
        }
      });
      salesRevision.value++;
      productsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error partial return: $e');
      return false;
    }
  }

  /// جلب كل الباركودات مجمّعة حسب المنتج (للبحث السريع)
  Future<Map<int, List<String>>> getAllBarcodesByProduct() async {
    try {
      final db = await instance.database;
      final rows = await db.query('product_barcodes');
      final Map<int, List<String>> map = {};
      for (final r in rows) {
        final pid = r['product_id'] as int;
        final bc = r['barcode'] as String;
        map.putIfAbsent(pid, () => []).add(bc);
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  // ==========================================================
  // دوال الديون (Debts CRUD)
  // ==========================================================

  /// إضافة دين جديد
  Future<int> insertDebt({
    required String customerName,
    String? phone,
    required int amount,
    String? note,
    int? saleId,
  }) async {
    try {
      final db = await instance.database;
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('debts', {
        'customer_name': customerName.trim(),
        'phone': phone?.trim(),
        'amount': amount,
        'paid': 0,
        'note': note?.trim(),
        'sale_id': saleId,
        'created_at': now,
        'updated_at': now,
      });
      if (id > 0) { debtsRevision.value++; _notifyAll(); }
      return id;
    } catch (e) {
      print('Error inserting debt: $e');
      return -1;
    }
  }

  /// جلب كل الديون (مرتبة من الأحدث)
  Future<List<Map<String, dynamic>>> getAllDebts() async {
    try {
      final db = await instance.database;
      return await db.query('debts', orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  /// جلب الديون غير المسددة فقط
  Future<List<Map<String, dynamic>>> getUnpaidDebts() async {
    try {
      final db = await instance.database;
      return await db.query(
        'debts',
        where: 'amount > paid',
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      return [];
    }
  }

  /// جلب دين واحد بالتفاصيل
  Future<Map<String, dynamic>?> getDebtById(int id) async {
    try {
      final db = await instance.database;
      final rows = await db.query('debts', where: 'id = ?', whereArgs: [id]);
      return rows.isNotEmpty ? rows.first : null;
    } catch (e) {
      return null;
    }
  }

  /// تسجيل دفعة على دين
  Future<bool> payDebt(int debtId, int payAmount) async {
    try {
      final db = await instance.database;
      await db.transaction((txn) async {
        final rows = await txn.query('debts', where: 'id = ?', whereArgs: [debtId]);
        if (rows.isEmpty) return;

        final currentPaid = rows.first['paid'] as int? ?? 0;
        final totalAmount = rows.first['amount'] as int? ?? 0;
        final newPaid = (currentPaid + payAmount).clamp(0, totalAmount);

        await txn.update(
          'debts',
          {
            'paid': newPaid,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [debtId],
        );

        // تسجيل الدفعة في جدول السجل
        await txn.insert('debt_payments', {
          'debt_id': debtId,
          'amount': payAmount,
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      debtsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error paying debt: $e');
      return false;
    }
  }

  /// تعديل دين
  Future<bool> updateDebt(int debtId, {
    String? customerName,
    String? phone,
    int? amount,
    int? paid,
    String? note,
  }) async {
    try {
      final db = await instance.database;
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (customerName != null) updates['customer_name'] = customerName.trim();
      if (phone != null) updates['phone'] = phone.trim();
      if (amount != null) updates['amount'] = amount;
      if (paid != null) updates['paid'] = paid;
      if (note != null) updates['note'] = note.trim();

      await db.update('debts', updates, where: 'id = ?', whereArgs: [debtId]);
      debtsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error updating debt: $e');
      return false;
    }
  }

  /// حذف دين
  Future<bool> deleteDebt(int debtId) async {
    try {
      final db = await instance.database;
      await db.delete('debts', where: 'id = ?', whereArgs: [debtId]);
      debtsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error deleting debt: $e');
      return false;
    }
  }

  /// جلب سجل الدفعات لدين معين
  Future<List<Map<String, dynamic>>> getDebtPayments(int debtId) async {
    try {
      final db = await instance.database;
      return await db.query(
        'debt_payments',
        where: 'debt_id = ?',
        whereArgs: [debtId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      return [];
    }
  }

  /// ملخص الديون (الإجمالي + المدفوع + المتبقي + عدد)
  Future<Map<String, int>> getDebtsSummary() async {
    try {
      final db = await instance.database;
      final result = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total, COALESCE(SUM(paid), 0) as paid, COUNT(*) as count FROM debts',
      );
      final total = result.first['total'] as int? ?? 0;
      final paid = result.first['paid'] as int? ?? 0;
      final count = result.first['count'] as int? ?? 0;
      return {
        'total': total,
        'paid': paid,
        'remaining': total - paid,
        'count': count,
      };
    } catch (e) {
      return {'total': 0, 'paid': 0, 'remaining': 0, 'count': 0};
    }
  }

  /// رأس المال الحقيقي = مجموع (المخزون × سعر الشراء) لكل المنتجات
  Future<int> getTotalInventoryValue() async {
    try {
      final db = await instance.database;
      final result = await db.rawQuery(
        'SELECT COALESCE(SUM(stock * purchase_price), 0) as total FROM products',
      );
      return result.first['total'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ==========================================================
  // دوال ديون المحل (Shop Debts)
  // ==========================================================

  Future<int> insertShopDebt({
    required String supplierName,
    String? phone,
    required int amount,
    String? note,
  }) async {
    try {
      final db = await instance.database;
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('shop_debts', {
        'supplier_name': supplierName.trim(),
        'phone': phone?.trim(),
        'amount': amount,
        'paid': 0,
        'note': note?.trim(),
        'created_at': now,
        'updated_at': now,
      });
      if (id > 0) { debtsRevision.value++; _notifyAll(); }
      return id;
    } catch (e) {
      print('Error inserting shop debt: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getAllShopDebts() async {
    try {
      final db = await instance.database;
      return await db.query('shop_debts', orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  Future<bool> payShopDebt(int debtId, int payAmount) async {
    try {
      final db = await instance.database;
      await db.transaction((txn) async {
        final rows = await txn.query('shop_debts', where: 'id = ?', whereArgs: [debtId]);
        if (rows.isEmpty) return;
        final currentPaid = rows.first['paid'] as int? ?? 0;
        final totalAmount = rows.first['amount'] as int? ?? 0;
        final newPaid = (currentPaid + payAmount).clamp(0, totalAmount);
        await txn.update('shop_debts', {
          'paid': newPaid,
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [debtId]);
        await txn.insert('shop_debt_payments', {
          'debt_id': debtId,
          'amount': payAmount,
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      debtsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error paying shop debt: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getShopDebtPayments(int debtId) async {
    try {
      final db = await instance.database;
      return await db.query('shop_debt_payments',
          where: 'debt_id = ?', whereArgs: [debtId], orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  Future<bool> updateShopDebt(int debtId, {String? supplierName, String? phone, int? amount, String? note}) async {
    try {
      final db = await instance.database;
      final updates = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
      if (supplierName != null) updates['supplier_name'] = supplierName.trim();
      if (phone != null) updates['phone'] = phone.trim();
      if (amount != null) updates['amount'] = amount;
      if (note != null) updates['note'] = note.trim();
      await db.update('shop_debts', updates, where: 'id = ?', whereArgs: [debtId]);
      debtsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error updating shop debt: $e');
      return false;
    }
  }

  Future<bool> deleteShopDebt(int debtId) async {
    try {
      final db = await instance.database;
      await db.delete('shop_debts', where: 'id = ?', whereArgs: [debtId]);
      debtsRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error deleting shop debt: $e');
      return false;
    }
  }

  Future<Map<String, int>> getShopDebtsSummary() async {
    try {
      final db = await instance.database;
      final result = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total, COALESCE(SUM(paid), 0) as paid, COUNT(*) as count FROM shop_debts',
      );
      final total = result.first['total'] as int? ?? 0;
      final paid = result.first['paid'] as int? ?? 0;
      return {
        'total': total,
        'paid': paid,
        'remaining': total - paid,
        'count': result.first['count'] as int? ?? 0,
      };
    } catch (e) {
      return {'total': 0, 'paid': 0, 'remaining': 0, 'count': 0};
    }
  }

  // ==========================================================
  // دوال المصروفات (Expenses)
  // ==========================================================

  Future<int> insertExpense({
    required String category,
    required int amount,
    String? note,
  }) async {
    try {
      final db = await instance.database;
      final id = await db.insert('expenses', {
        'category': category.trim(),
        'amount': amount,
        'note': note?.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (id > 0) { expensesRevision.value++; _notifyAll(); }
      return id;
    } catch (e) {
      print('Error inserting expense: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getAllExpenses() async {
    try {
      final db = await instance.database;
      return await db.query('expenses', orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  Future<bool> deleteExpense(int id) async {
    try {
      final db = await instance.database;
      await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
      expensesRevision.value++;
      _notifyAll();
      return true;
    } catch (e) {
      print('Error deleting expense: $e');
      return false;
    }
  }

  Future<Map<String, int>> getExpensesSummary() async {
    try {
      final db = await instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final todayResult = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE created_at LIKE ?",
        ['$today%'],
      );
      final allResult = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM expenses',
      );
      return {
        'today': todayResult.first['total'] as int? ?? 0,
        'all': allResult.first['total'] as int? ?? 0,
      };
    } catch (e) {
      return {'today': 0, 'all': 0};
    }
  }

  Future<List<Map<String, dynamic>>> getExpensesByDateRange(String from, String to) async {
    try {
      final db = await instance.database;
      return await db.query('expenses',
          where: "created_at >= ? AND created_at < ?",
          whereArgs: [from, to],
          orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, int>> getExpensesSummaryByDateRange(String from, String to) async {
    try {
      final db = await instance.database;
      final result = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE created_at >= ? AND created_at < ?",
        [from, to],
      );
      return {'total': result.first['total'] as int? ?? 0};
    } catch (e) {
      return {'total': 0};
    }
  }

  /// بيانات الرسم البياني — مبيعات وأرباح آخر [days] يوم
  Future<List<Map<String, dynamic>>> getDailySalesChart({int days = 7}) async {
    try {
      final db = await instance.database;
      final today = DateTime.now();
      final from = today.subtract(Duration(days: days - 1));
      final fromStr = '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}';

      final rows = await db.rawQuery('''
        SELECT substr(created_at, 1, 10) as day,
               COALESCE(SUM(total_amount), 0) as revenue,
               COALESCE(SUM(total_profit), 0) as profit
        FROM sales
        WHERE created_at >= ?
        GROUP BY day
      ''', [fromStr]);

      // نملأ الأيام الفارغة بصفر
      final byDay = {for (final r in rows) r['day'] as String: r};
      final result = <Map<String, dynamic>>[];
      for (var i = 0; i < days; i++) {
        final d = from.add(Duration(days: i));
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final row = byDay[key];
        result.add({
          'day': key,
          'label': '${d.day}/${d.month}',
          'revenue': row?['revenue'] as int? ?? 0,
          'profit': row?['profit'] as int? ?? 0,
        });
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getZReportData() async {
    try {
      final db = await instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final sales = await db.rawQuery(
        "SELECT COALESCE(SUM(total_amount), 0) as revenue, COALESCE(SUM(total_profit), 0) as profit, COALESCE(SUM(items_count), 0) as items, COUNT(*) as count FROM sales WHERE created_at LIKE ?",
        ['$today%'],
      );
      final expenses = await db.rawQuery(
        "SELECT COALESCE(SUM(amount), 0) as total FROM expenses WHERE created_at LIKE ?",
        ['$today%'],
      );
      final debtsPaid = await db.rawQuery(
        "SELECT COALESCE(SUM(dp.amount), 0) as total FROM debt_payments dp JOIN debts d ON dp.debt_id = d.id WHERE dp.created_at LIKE ?",
        ['$today%'],
      );
      final shopDebtsPaid = await db.rawQuery(
        "SELECT COALESCE(SUM(sdp.amount), 0) as total FROM shop_debt_payments sdp JOIN shop_debts sd ON sdp.shop_debt_id = sd.id WHERE sdp.created_at LIKE ?",
        ['$today%'],
      );

      final topProducts = await db.rawQuery(
        """SELECT si.product_name, SUM(si.quantity) as total_qty, SUM(si.unit_price * si.quantity) as total_revenue
           FROM sale_items si
           JOIN sales s ON si.sale_id = s.id
           WHERE s.created_at LIKE ?
           GROUP BY si.product_name
           ORDER BY total_qty DESC
           LIMIT 5""",
        ['$today%'],
      );

      return {
        'revenue': sales.first['revenue'] as int? ?? 0,
        'profit': sales.first['profit'] as int? ?? 0,
        'items_sold': sales.first['items'] as int? ?? 0,
        'sales_count': sales.first['count'] as int? ?? 0,
        'expenses': expenses.first['total'] as int? ?? 0,
        'debts_collected': debtsPaid.first['total'] as int? ?? 0,
        'shop_debts_collected': shopDebtsPaid.first['total'] as int? ?? 0,
        'top_products': topProducts,
      };
    } catch (e) {
      return {
        'revenue': 0, 'profit': 0, 'items_sold': 0, 'sales_count': 0,
        'expenses': 0, 'debts_collected': 0, 'shop_debts_collected': 0,
        'top_products': <Map<String, dynamic>>[],
      };
    }
  }

  // ─── Paginated Queries ───

  Future<List<Map<String, dynamic>>> getDebtsPaginated(int page, int pageSize) async {
    try {
      final db = await instance.database;
      final offset = page * pageSize;
      return await db.query('debts', orderBy: 'created_at DESC', limit: pageSize, offset: offset);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getShopDebtsPaginated(int page, int pageSize) async {
    try {
      final db = await instance.database;
      final offset = page * pageSize;
      return await db.query('shop_debts', orderBy: 'created_at DESC', limit: pageSize, offset: offset);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getExpensesPaginated(int page, int pageSize) async {
    try {
      final db = await instance.database;
      final offset = page * pageSize;
      return await db.query('expenses', orderBy: 'created_at DESC', limit: pageSize, offset: offset);
    } catch (e) {
      return [];
    }
  }

  Future<List<ProductModel>> getProductsPaginated(int page, int pageSize) async {
    try {
      final db = await instance.database;
      final offset = page * pageSize;
      final maps = await db.query('products', orderBy: 'created_at DESC', limit: pageSize, offset: offset);
      return maps.map((m) => ProductModel.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSalesPaginated(int page, int pageSize, {String? from, String? to}) async {
    try {
      final db = await instance.database;
      final offset = page * pageSize;
      String where = '';
      List<dynamic> args = [];
      if (from != null && to != null) {
        where = 'created_at >= ? AND created_at < ?';
        args = [from, to];
      }
      return await db.query('sales', where: where.isEmpty ? null : where, whereArgs: args.isEmpty ? null : args, orderBy: 'created_at DESC', limit: pageSize, offset: offset);
    } catch (e) {
      return [];
    }
  }
}

/// نتيجة التحقق من نسخة احتياطية
class BackupVerificationResult {
  final bool isValid;
  final String message;
  final Map<String, int> tableCounts;

  const BackupVerificationResult(
    this.isValid,
    this.message, {
    this.tableCounts = const {},
  });

  @override
  String toString() =>
      isValid ? 'صالحة ✓ ($message)' : 'غير صالحة ✗ ($message)';
}

/// Sink داخلي لجمع نتيجة هاش SHA-256 التدريجي
class _DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest _digest;
  crypto.Digest get digest => _digest;

  @override
  void add(crypto.Digest data) => _digest = data;

  @override
  void close() {}
}

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  // Singleton pattern لضمان نسخة واحدة من قاعدة البيانات
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cashier_system.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // نفتح قاعدة البيانات ونحدد الإصدار الأول
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // إنشاء جدول المنتجات (Products)
    // لاحظ: price نوعه INTEGER لضمان دقة الحسابات المالية
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        color TEXT,
        size TEXT,
        price INTEGER NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        barcode TEXT,
        is_custom_barcode INTEGER DEFAULT 0
      )
    ''');

    // إنشاء Index حقل الباركود حتى سرعة البحث بجهاز الباركود تصير بأجزاء من الثانية
    await db.execute('''
      CREATE INDEX idx_product_barcode ON products (barcode);
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // هنا مستقبلاً نضيف أعمدة جديدة بدون ما نحذف البيانات القديمة (Safe Migrations)
    // مثال:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE products ADD COLUMN discount INTEGER DEFAULT 0');
    // }
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
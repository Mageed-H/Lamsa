import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../features/products/data/models/product_model.dart';

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
// ==========================================================
  // دوال الإدخال والقراءة والتحديث (CRUD Operations)
  // ==========================================================

  // 1. إضافة منتج جديد (Create)
  Future<int> insertProduct(ProductModel product) async {
    try {
      final db = await instance.database;
      return await db.insert(
        'products',
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace, // لحماية النظام من التوقف إذا صار تعارض
      );
    } catch (e) {
      // تطبيقاً لقاعدة الـ Global Logging (حالياً نطبعها بالكونسول، ومستقبلاً نربطها بملف log)
      print('Error inserting product: $e'); 
      return -1; // إرجاع -1 يدل على فشل العملية بدل انهيار التطبيق
    }
  }

  // 2. قراءة كل المنتجات (Read All) - تفيدنا بشاشة الجرد والمخزن
  Future<List<ProductModel>> getAllProducts() async {
    try {
      final db = await instance.database;
      final maps = await db.query('products', orderBy: 'id DESC');
      return maps.map((map) => ProductModel.fromMap(map)).toList();
    } catch (e) {
      print('Error fetching products: $e');
      return []; // إرجاع لستة فارغة بدل الكراش
    }
  }

  // 3. البحث عن منتج بواسطة الباركود - هاي أهم دالة لشاشة الكاشير السريعة!
  Future<ProductModel?> getProductByBarcode(String barcode) async {
    try {
      final db = await instance.database;
      final maps = await db.query(
        'products',
        where: 'barcode = ?',
        whereArgs: [barcode], // استخدام Parameterized Queries لأمان البيانات
      );

      if (maps.isNotEmpty) {
        return ProductModel.fromMap(maps.first);
      }
      return null; // إذا الباركود ما موجود
    } catch (e) {
      print('Error fetching product by barcode: $e');
      return null;
    }
  }

  // 4. تحديث منتج (Update) - تفيدنا بتحديث الكمية (Stock) بعد البيع أو تحديث السعر
  Future<int> updateProduct(ProductModel product) async {
    try {
      final db = await instance.database;
      return await db.update(
        'products',
        product.toMap(),
        where: 'id = ?',
        whereArgs: [product.id], // Parameterized Queries
      );
    } catch (e) {
      print('Error updating product: $e');
      return 0; // إرجاع 0 يعني لم يتم تحديث أي صف
    }
  }


}
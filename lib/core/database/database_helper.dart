import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../features/products/data/models/product_model.dart';

class DatabaseHelper {
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

    return await openDatabase(
      path,
      version: 2, // رفعنا الإصدار إلى 2
      onConfigure: _onConfigure, // تفعيل العلاقات (Foreign Keys)
      onCreate: _createDB,
      onUpgrade: _upgradeDB, // التحديث الآمن
    );
  }

  // تفعيل الـ Foreign Keys في SQLite
  Future _onConfigure(Database db) async {
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
        stock INTEGER NOT NULL DEFAULT 0,
        barcode TEXT,
        is_custom_barcode INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_product_barcode ON products (barcode);');

    // إذا كان الإصدار الأول هو نفسه الأخير (تثبيت جديد)، ننشئ الجداول الجديدة فوراً
    await _createV2Tables(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // إذا كان المستخدم عنده الإصدار 1، راح تتنفذ هاي الدالة وتضيف الجداول بدون ما تحذف المنتجات القديمة
      await _createV2Tables(db);
    }
  }

  // دالة مساعدة لإنشاء جداول التحديث الجديد (الإصدار 2)
  Future _createV2Tables(Database db) async {
    // 2. جدول الأقسام (Categories)
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
    
    // إضافة أقسام افتراضية للمحل
    await db.insert('categories', {'name': 'ملافع'});
    await db.insert('categories', {'name': 'داخليات'});

    // 3. جدول الطلبات المعلقة (الفاتورة الأساسية)
    await db.execute('''
      CREATE TABLE suspended_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note TEXT, -- ملاحظة للتعرف على الزبونة
        created_at TEXT NOT NULL
      )
    ''');

    // 4. جدول منتجات الفاتورة المعلقة (تفاصيل الفاتورة)
    await db.execute('''
      CREATE TABLE suspended_order_items (
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

  Future close() async {
    final db = await instance.database;
    db.close();
  }

  // ==========================================================
  // دوال الإدخال والقراءة (القديمة الخاصة بالمنتجات)
  // ==========================================================
  Future<int> insertProduct(ProductModel product) async {
    try {
      final db = await instance.database;
      return await db.insert('products', product.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
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
      final maps = await db.query('products', where: 'barcode = ?', whereArgs: [barcode]);
      if (maps.isNotEmpty) return ProductModel.fromMap(maps.first);
      return null; 
    } catch (e) {
      print('Error fetching product by barcode: $e');
      return null;
    }
  }

  Future<int> updateProduct(ProductModel product) async {
    try {
      final db = await instance.database;
      return await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
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
}
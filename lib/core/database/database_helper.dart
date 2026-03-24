import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import '../../features/products/data/models/product_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// يُستخدم لإشعار الصفحات بأي تغيير في البيانات (مبيعات، منتجات...)
  static final ValueNotifier<int> revision = ValueNotifier(0);

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
      version: 7, // الإصدار 7: إعدادات الطباعة (خط + عرض ورقة)
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
    db.close();
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
      if (productId > 0) revision.value++;
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
      final maps = await db.rawQuery('''
        SELECT p.* FROM products p
        INNER JOIN product_barcodes pb ON pb.product_id = p.id
        WHERE pb.barcode = ?
        LIMIT 1
      ''', [barcode]);
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
      final rows = await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
      if (rows > 0) revision.value++;
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
      if (rows > 0) revision.value++;
      return rows;
    } catch (e) {
      print('Error deleting product: $e');
      return 0;
    }
  }

  // ==========================================================
  // دوال الفواتير المعلقة (Suspended Orders)
  // ==========================================================
  Future<int> saveSuspendedOrder(List<Map<String, dynamic>> cart, String note) async {
    final db = await instance.database;
    int orderId = -1;
    await db.transaction((txn) async {
      orderId = await txn.insert('suspended_orders', {
        'note': note.trim().isEmpty ? null : note.trim(),
        'created_at': DateTime.now().toIso8601String(),
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

  Future<List<Map<String, dynamic>>> getSuspendedOrderCart(int orderId) async {
    try {
      final db = await instance.database;
      final items = await db.query('suspended_order_items',
          where: 'order_id = ?', whereArgs: [orderId]);
      final List<Map<String, dynamic>> cart = [];
      for (final item in items) {
        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int;
        final productMaps =
            await db.query('products', where: 'id = ?', whereArgs: [productId]);
        if (productMaps.isNotEmpty) {
          cart.add({
            'product': ProductModel.fromMap(productMaps.first),
            'quantity': quantity,
          });
        }
      }
      return cart;
    } catch (e) {
      print('Error fetching suspended order cart: $e');
      return [];
    }
  }

  Future<void> deleteSuspendedOrder(int orderId) async {
    try {
      final db = await instance.database;
      await db.delete('suspended_orders', where: 'id = ?', whereArgs: [orderId]);
    } catch (e) {
      print('Error deleting suspended order: $e');
    }
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
  Future<int> completeSale(List<Map<String, dynamic>> cart) async {
    final db = await instance.database;
    int saleId = -1;
    await db.transaction((txn) async {
      int totalAmount = 0;
      int totalProfit = 0;
      int itemsCount = 0;

      for (final item in cart) {
        final product = item['product'] as ProductModel;
        final qty = item['quantity'] as int;
        totalAmount += product.price * qty;
        totalProfit += product.profit * qty;
        itemsCount += qty;
      }

      saleId = await txn.insert('sales', {
        'total_amount': totalAmount,
        'total_profit': totalProfit,
        'items_count': itemsCount,
        'created_at': DateTime.now().toIso8601String(),
      });

      for (final item in cart) {
        final product = item['product'] as ProductModel;
        final qty = item['quantity'] as int;
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': product.id,
          'product_name': product.name,
          'quantity': qty,
          'unit_price': product.price,
          'purchase_price': product.purchasePrice,
        });
        // تخفيض المخزون
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [qty, product.id],
        );
      }
    });
    if (saleId > 0) revision.value++;
    return saleId;
  }

  /// جلب كل المبيعات
  Future<List<Map<String, dynamic>>> getAllSales() async {
    try {
      final db = await instance.database;
      return await db.query('sales', orderBy: 'created_at DESC');
    } catch (e) {
      return [];
    }
  }

  /// جلب مبيعات اليوم فقط
  Future<List<Map<String, dynamic>>> getTodaySales() async {
    try {
      final db = await instance.database;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return await db.query('sales',
          where: "created_at LIKE ?",
          whereArgs: ['$today%'],
          orderBy: 'created_at DESC');
    } catch (e) {
      return [];
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
      'store_name': 'لمسة',
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
    // إضافة إعدادات الطباعة الجديدة
    final batch = db.batch();
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_title_font_size', '14')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_body_font_size', '9')");
    batch.rawInsert("INSERT OR IGNORE INTO settings (key, value) VALUES ('receipt_paper_width_mm', '78')");
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
}
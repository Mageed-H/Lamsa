class ProductModel {
  final int? id;
  final String name;
  final String category;
  final String color;
  final String size;
  final int price; // نوع INTEGER مثل ما اتفقنا للدقة المالية
  final int stock;
  final String barcode;
  final bool isCustomBarcode;

  ProductModel({
    this.id,
    required this.name,
    required this.category,
    this.color = '', // قيمة افتراضية لتجنب الـ Null
    this.size = '',  // قيمة افتراضية لتجنب الـ Null
    required this.price,
    this.stock = 0,
    this.barcode = '',
    this.isCustomBarcode = false,
  });

  // تحويل الكائن إلى Map لخزنه في SQLite
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'color': color,
      'size': size,
      'price': price,
      'stock': stock,
      'barcode': barcode,
      // SQLite ما تدعم البولين (bool) بشكل مباشر، فنحوله إلى 1 أو 0
      'is_custom_barcode': isCustomBarcode ? 1 : 0, 
    };
  }

  // إنشاء كائن من Map قادم من SQLite مع حماية صارمة من الـ Null
  factory ProductModel.fromMap(Map<String, Object?> map) {
    return ProductModel(
      id: map['id'] as int?,
      name: map['name'] as String? ?? 'بدون اسم',
      category: map['category'] as String? ?? 'عام',
      color: map['color'] as String? ?? '',
      size: map['size'] as String? ?? '',
      price: map['price'] as int? ?? 0,
      stock: map['stock'] as int? ?? 0,
      barcode: map['barcode'] as String? ?? '',
      isCustomBarcode: (map['is_custom_barcode'] as int? ?? 0) == 1,
    );
  }

  // دالة لتسهيل تحديث بيانات معينة في الكائن
  ProductModel copyWith({
    int? id,
    String? name,
    String? category,
    String? color,
    String? size,
    int? price,
    int? stock,
    String? barcode,
    bool? isCustomBarcode,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      color: color ?? this.color,
      size: size ?? this.size,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      barcode: barcode ?? this.barcode,
      isCustomBarcode: isCustomBarcode ?? this.isCustomBarcode,
    );
  }
}
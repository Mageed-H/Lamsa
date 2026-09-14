import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:cashier_system/core/widgets/custom_button.dart';
import 'package:cashier_system/core/widgets/custom_text_field.dart';
import 'package:cashier_system/features/products/data/models/product_model.dart';
import 'package:cashier_system/features/products/presentation/widgets/barcode_printer_widget.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({Key? key}) : super(key: key);

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _selectionAnimController;
  late Animation<double> _selectionSlideAnimation;
  final _formKey = GlobalKey<FormState>();

  // Controllers لحقول الإدخال
  final _nameController = TextEditingController();
  final _colorController = TextEditingController();
  final _sizeController = TextEditingController();
  final _priceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _barcodeController = TextEditingController();

  // Focus nodes للتنقل بالإنتر
  final _nameFocusNode = FocusNode();
  final _colorFocusNode = FocusNode();
  final _sizeFocusNode = FocusNode();
  final _purchasePriceFocusNode = FocusNode();
  final _priceFocusNode = FocusNode();
  final _stockFocusNode = FocusNode();
  final _barcodeFocusNode = FocusNode();

  // متغيرات الأقسام (Categories)
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isCustomBarcode = false;

  // قائمة المنتجات
  List<ProductModel> _allProducts = [];
  bool _isLoadingProducts = false;

  // بيانات آخر منتج تم حفظه (لاسترجاعه)
  String _lastName = '';
  String _lastCategory = '';
  int _lastPurchasePrice = 0;
  int _lastPrice = 0;

  // باركودات متعددة أثناء الإضافة
  final List<String> _extraBarcodes = [];

  // سكانر تبويب القائمة
  final _listScanController = TextEditingController();
  final _listScanFocusNode = FocusNode();
  final _listScrollController = ScrollController();
  int? _highlightedProductIndex;

  // بحث القائمة
  String _listSearchQuery = '';

  // باركودات ثانوية للبحث
  Map<int, List<String>> _secondaryBarcodes = {};

  // تحديد متعدد
  bool _isSelectionMode = false;
  final Set<int> _selectedProductIds = {};
  int _bulkOperationType = 0; // 0=إضافة, 1=خصم, 2=تعيين
  final _bulkQtyController = TextEditingController();
  final _bulkSellPriceController = TextEditingController();
  final _bulkBuyPriceController = TextEditingController();
  int _bulkPriceMode = 2; // 0=زيادة%, 1=خصم%, 2=سعر ثابت

  // سحب لتحديد_RANGE
  final GlobalKey _listKey = GlobalKey();
  int _dragAnchorIndex = -1;
  bool _isDragSelecting = false;
  Timer? _autoScrollTimer;
  double _autoScrollDirection = 0; // -1=أعلى, 1=أسفل, 0=إيقاف

  // ─── الفلاتر والترتيب ───
  Map<int, Map<String, dynamic>> _productSalesStats = {};
  String _sortBy = 'name'; // name, price, stock, profit, sold, lastSold
  bool _sortAsc = true;
  bool _showFilters = false;

  // فلاتر المخزون
  String _filterStock = ''; // '', 'zero', 'low', 'medium', 'high'
  // فلترة السعر
  int? _filterPriceMin;
  int? _filterPriceMax;
  // فلترة الربح
  int? _filterProfitMin;
  int? _filterProfitMax;
  // فلترة اللون
  String _filterColor = '';
  // فلترة القياس
  String _filterSize = '';
  // فلترة القسم
  String _filterCategory = '';
  // فلترة المبيعات
  bool _filterOnlySold = false;
  bool _filterNeverSold = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectionAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _selectionSlideAnimation = CurvedAnimation(
      parent: _selectionAnimController,
      curve: Curves.easeOutCubic,
    );
    DatabaseHelper.productsRevision.addListener(_loadAllProducts);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nameFocusNode.requestFocus();
        });
      } else if (_tabController.index == 1) {
        _loadAllProducts();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _listScanFocusNode.requestFocus();
        });
      }
    });
    _loadCategories();
    _loadAllProducts();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _selectionAnimController.dispose();
    DatabaseHelper.productsRevision.removeListener(_loadAllProducts);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _nameController.dispose();
    _colorController.dispose();
    _sizeController.dispose();
    _priceController.dispose();
    _purchasePriceController.dispose();
    _stockController.dispose();
    _barcodeController.dispose();
    _nameFocusNode.dispose();
    _colorFocusNode.dispose();
    _sizeFocusNode.dispose();
    _purchasePriceFocusNode.dispose();
    _priceFocusNode.dispose();
    _stockFocusNode.dispose();
    _barcodeFocusNode.dispose();
    _listScanController.dispose();
    _listScanFocusNode.dispose();
    _listScrollController.dispose();
    _bulkQtyController.dispose();
    _bulkSellPriceController.dispose();
    _bulkBuyPriceController.dispose();
    _autoScrollTimer?.cancel();
    super.dispose();
  }

  // جلب الأقسام من SQLite
  Future<void> _loadCategories() async {
    final categories = await DatabaseHelper.instance.getAllCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        if (_categories.isNotEmpty && _selectedCategory == null) {
          _selectedCategory = _categories.first;
        }
      });
    }
  }

  Future<void> _loadAllProducts() async {
    if (!mounted) return;
    setState(() => _isLoadingProducts = true);
    try {
      final products = await DatabaseHelper.instance.getAllProducts();
      final barcodesMap = await DatabaseHelper.instance.getAllBarcodesByProduct();
      final salesStats = await DatabaseHelper.instance.getProductSalesStats();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _secondaryBarcodes = barcodesMap;
          _productSalesStats = salesStats;
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  // إضافة قسم جديد (Category)
  Future<void> _addNewCategory() async {
    final catController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة قسم جديد', style: TextStyle(color: AppTheme.primaryColor)),
        content: TextField(
          controller: catController,
          decoration: const InputDecoration(hintText: 'مثال: عطور '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              if (catController.text.trim().isNotEmpty) {
                await DatabaseHelper.instance.insertCategory(catController.text.trim());
                if (context.mounted) Navigator.pop(context);
                _loadCategories(); // تحديث القائمة بعد الإضافة
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // توليد باركود محلي فريد (رقمي 11 رقم يبدأ بـ 000 لتجنب التعارض مع EAN/UPC)
  Future<void> _generateCustomBarcode() async {
    String barcode;
    bool exists;
    do {
      final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
      // نأخذ آخر 8 أرقام من الـ timestamp
      final suffix = uniqueId.substring(uniqueId.length - 8);
      barcode = '000$suffix'; // دائماً 11 رقم (ما يطابق EAN-8/13 أو UPC-A)
      exists = await DatabaseHelper.instance.barcodeExists(barcode);
      if (exists) await Future.delayed(const Duration(milliseconds: 2));
    } while (exists);
    setState(() {
      _barcodeController.text = barcode;
      _isCustomBarcode = true;
    });
  }

  // دالة الحفظ
  Future<void> _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء اختيار قسم أو إضافة قسم جديد')));
        return;
      }

      // تحقق: سعر البيع أكبر من سعر الشراء
      final sellPrice = int.tryParse(_priceController.text.trim()) ?? 0;
      final buyPrice = int.tryParse(_purchasePriceController.text.trim()) ?? 0;
      if (sellPrice <= buyPrice) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('سعر البيع يجب أن يكون أكبر من سعر الشراء!'),
            backgroundColor: AppTheme.errorColor,
          ));
        }
        return;
      }

      // التحقق من تكرار الباركود قبل الحفظ
      final barcode = _barcodeController.text.trim();
      if (barcode.isNotEmpty) {
        final exists = await DatabaseHelper.instance.barcodeExists(barcode);
        if (exists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('هذا الباركود مستخدم مسبقاً! غيّره أو ولّد باركود جديد'),
              backgroundColor: AppTheme.errorColor,
            ));
          }
          return;
        }
      }

      // تحضير كائن المنتج للحفظ (مع حماية صارمة من أخطاء التحويل)
      final newProduct = ProductModel(
        name: _nameController.text.trim(),
        category: _selectedCategory!,
        color: _colorController.text.trim(),
        size: _sizeController.text.trim(),
        price: sellPrice,
        purchasePrice: buyPrice,
        stock: int.tryParse(_stockController.text.trim()) ?? 0,
        barcode: _barcodeController.text.trim(),
        isCustomBarcode: _isCustomBarcode,
      );

      final result = await DatabaseHelper.instance.insertProduct(newProduct);

      if (result != -1) {
        // حفظ بيانات آخر منتج (لاسترجاعه لاحقاً)
        _lastName = _nameController.text.trim();
        _lastCategory = _selectedCategory!;
        _lastPurchasePrice = buyPrice;
        _lastPrice = sellPrice;

        // حفظ الباركودات الإضافية
        if (result > 0 && _extraBarcodes.isNotEmpty) {
          for (final extraBarcode in _extraBarcodes) {
            await DatabaseHelper.instance.addBarcode(result, extraBarcode);
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المنتج بنجاح!'), backgroundColor: AppTheme.successColor));
        // مسح جميع الحقول
        _nameController.clear();
        _colorController.clear();
        _sizeController.clear();
        _purchasePriceController.clear();
        _priceController.clear();
        _stockController.clear();
        _barcodeController.clear();
        setState(() {
          _isCustomBarcode = false;
          _extraBarcodes.clear();
        });
        await _loadAllProducts();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء الحفظ!'), backgroundColor: AppTheme.errorColor));
      }
    }
  }

  // استرجاع بيانات آخر منتج
  void _restoreLastProduct() {
    if (_lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يوجد منتج سابق للاسترجاع'),
        backgroundColor: AppTheme.warningColor,
      ));
      return;
    }
    setState(() {
      _nameController.text = _lastName;
      _selectedCategory = _lastCategory;
      _purchasePriceController.text = _lastPurchasePrice > 0 ? _lastPurchasePrice.toString() : '';
      _priceController.text = _lastPrice > 0 ? _lastPrice.toString() : '';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تم استرجاع بيانات "$_lastName"'),
      backgroundColor: AppTheme.successColor,
    ));
  }

  // ─── تحويل اسم اللون لـ Color ───
  Color _parseColor(String name) {
    const map = {
      'أحمر': Colors.red, 'اخضر': Colors.green,
      'أزرق': Colors.blue, 'اسود': Colors.black, 'أبيض': Colors.white,
      'اصفر': Colors.yellow, 'برتقالي': Colors.orange, 'بنفسجي': Colors.purple,
      'وردي': Colors.pink, 'بني': Colors.brown, 'رمادي': Colors.grey,
      'سماوي': Colors.lightBlue, 'نعناعي': Colors.teal, 'بيج': Color(0xFFF5F5DC),
      'ذهبي': Color(0xFFFFD700), 'فضي': Color(0xFFC0C0C0),
    };
    final lower = name.toLowerCase().trim();
    for (final entry in map.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return AppTheme.textSecondary;
  }

  // ─── تصدير المنتجات قليلة المخزون PDF ───
  Future<void> _exportLowStockPdf() async {
    final db = await DatabaseHelper.instance.database;
    final products = await db.query('products', orderBy: 'category ASC, stock ASC');
    final lowStock = products.where((p) => (p['stock'] as int? ?? 0) <= 5).toList();
    if (lowStock.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد منتجات قليلة المخزون (5 أو أقل)'), backgroundColor: AppTheme.warningColor),
        );
      }
      return;
    }

    // ─── تحديد المنتجات ───
    final selectedIds = lowStock.map((p) => p['id'] as int).toSet();
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber, color: AppTheme.errorColor),
              const SizedBox(width: 8),
              const Text('المنتجات قليلة المخزون', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${selectedIds.length}/${lowStock.length}', style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor)),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Column(
              children: [
                // أزرار تحديد الكل / إلغاء الكل
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => setDialogState(() {
                        selectedIds.addAll(lowStock.map((p) => p['id'] as int));
                      }),
                      child: const Text('تحديد الكل', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => setDialogState(() => selectedIds.clear()),
                      child: const Text('إلغاء الكل', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: lowStock.length,
                    itemBuilder: (ctx, i) {
                      final p = lowStock[i];
                      final id = p['id'] as int;
                      final name = p['name'] as String? ?? '';
                      final category = p['category'] as String? ?? '';
                      final stock = p['stock'] as int? ?? 0;
                      final color = p['color'] as String? ?? '';
                      final isSelected = selectedIds.contains(id);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedIds.add(id);
                          } else {
                            selectedIds.remove(id);
                          }
                        }),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(category, style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
                            ),
                            const SizedBox(width: 6),
                            Text('المخزون: $stock', style: TextStyle(
                              fontSize: 11,
                              color: stock == 0 ? AppTheme.errorColor : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                            )),
                            if (color.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.circle, size: 10, color: _parseColor(color)),
                              const SizedBox(width: 2),
                              Text(color, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                            ],
                          ],
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      );
                    },
                  ),
                ),
                const Divider(),
                // حقل الملاحظات
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'ملاحظات (تظهر في نهاية التقرير)...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: Text('تصدير ${selectedIds.length} منتج', style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // ─── تصفية المنتجات المحددة ───
    final selected = lowStock.where((p) => selectedIds.contains(p['id'] as int)).toList();
    // ترتيب حسب القسم
    selected.sort((a, b) {
      final catA = (a['category'] as String?) ?? '';
      final catB = (b['category'] as String?) ?? '';
      final catCompare = catA.compareTo(catB);
      if (catCompare != 0) return catCompare;
      return (a['stock'] as int? ?? 0).compareTo(b['stock'] as int? ?? 0);
    });

    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      final arabicFont = pw.Font.ttf(fontData);
      final doc = pw.Document();
      final now = DateTime.now();
      final dateStr = '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
      final notes = notesCtrl.text.trim();

      pw.TextStyle body({bool bold = false, double fontSize = 10}) => pw.TextStyle(
        font: arabicFont, fontSize: fontSize,
        fontWeight: bold ? pw.FontWeight.bold : null,
      );

      // تجميع حسب القسم
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final p in selected) {
        final cat = (p['category'] as String?) ?? 'غير محدد';
        grouped.putIfAbsent(cat, () => []).add(p);
      }

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) => [
          pw.Center(child: pw.Text('المنتجات قليلة المخزون', style: pw.TextStyle(font: arabicFont, fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text('$dateStr  |  ${selected.length} منتج', style: body())),
          pw.SizedBox(height: 16),

          // ─── الجدول ───
          pw.TableHelper.fromTextArray(
            headerStyle: body(bold: true, fontSize: 11),
            cellStyle: body(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headers: ['#', 'المخزون', 'اللون', 'القسم', 'المنتج'],
            cellAlignment: pw.Alignment.centerRight,
            data: selected.asMap().entries.map((e) {
              final i = e.key + 1;
              final p = e.value;
              final name = (p['name'] as String?) ?? '';
              final category = (p['category'] as String?) ?? '';
              final stock = (p['stock'] as int? ?? 0);
              final color = (p['color'] as String?) ?? '';
              return [
                '$i',
                '$stock',
                color.isNotEmpty ? color : '—',
                category,
                name,
              ];
            }).toList(),
          ),

          // ─── الملاحظات ───
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.5),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('ملاحظات:', style: body(bold: true)),
                  pw.SizedBox(height: 4),
                  pw.Text(notes, style: body()),
                ],
              ),
            ),
          ],
        ],
      ));

      final pdfBytes = await doc.save();
      final safeName = 'Low_Stock_$dateStr.pdf'.replaceAll('/', '-');
      final userProfile = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      final sep = Platform.pathSeparator;
      final desktop = '$userProfile${sep}Desktop';
      final desktopDir = Directory(desktop);
      if (!await desktopDir.exists()) await desktopDir.create(recursive: true);
      final file = File('$desktop$sep$safeName');
      await file.writeAsBytes(pdfBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ التقرير على سطح المكتب ✓\n$safeName (${selected.length} منتج)'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // إضافة باركود إضافي أثناء إضافة منتج جديد
  Future<void> _addExtraBarcode() async {
    final ctrl = TextEditingController();
    final rawBarcode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة باركود إضافي', style: TextStyle(color: AppTheme.primaryColor)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'امسح أو أدخل الباركود',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.qr_code),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    final barcode = rawBarcode?.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
    if (barcode == null || barcode.isEmpty) return;

    // التحقق من عدم التكرار
    if (_barcodeController.text.trim() == barcode || _extraBarcodes.contains(barcode)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('هذا الباركود مضاف مسبقاً!'),
          backgroundColor: AppTheme.warningColor,
        ));
      }
      return;
    }

    final exists = await DatabaseHelper.instance.barcodeExists(barcode);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('هذا الباركود مستخدم مسبقاً في منتج آخر!'),
          backgroundColor: AppTheme.errorColor,
        ));
      }
      return;
    }

    setState(() => _extraBarcodes.add(barcode));
  }

  void _removeExtraBarcode(String barcode) {
    setState(() => _extraBarcodes.remove(barcode));
  }

  // ─── مدققو الحقول الرقمية — يرفضون الحروف والأرقام العربية والسالب ───
  static String? _validatePositiveInt(String? val) {
    final v = val?.trim() ?? '';
    if (v.isEmpty) return 'هذا الحقل مطلوب';
    final n = int.tryParse(v);
    if (n == null) return 'أدخل رقماً صحيحاً فقط';
    if (n <= 0) return 'يجب أن يكون أكبر من صفر';
    if (n > 999999999) return 'رقم كبير جداً';
    return null;
  }

  static String? _validateNonNegativeInt(String? val) {
    final v = val?.trim() ?? '';
    if (v.isEmpty) return 'هذا الحقل مطلوب';
    final n = int.tryParse(v);
    if (n == null) return 'أدخل رقماً صحيحاً فقط';
    if (n < 0) return 'لا يمكن أن يكون سالباً';
    if (n > 999999999) return 'رقم كبير جداً';
    return null;
  }

  // تنظيف مدخلات الماسح الضوئي من الرموز الزائدة
  String _cleanBarcode(String raw) {
    return raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  }

  // عند مسح باركود في تبويب القائمة → يتنقل للمنتج ويلوّنه
  // يبحث بجدول product_barcodes لدعم الباركودات المتعددة
  Future<void> _onProductsListScan(String barcode) async {
    final cleanBarcode = _cleanBarcode(barcode);
    if (cleanBarcode.isEmpty) {
      _listScanFocusNode.requestFocus();
      return;
    }
    _listScanController.clear();
    // بحث عبر قاعدة البيانات لدعم الباركودات المتعددة
    final product = await DatabaseHelper.instance.getProductByBarcode(cleanBarcode);
    final index = product != null
        ? _allProducts.indexWhere((p) => p.id == product.id)
        : -1;
    if (index >= 0) {
      if (_listScrollController.hasClients) {
        _listScrollController.animateTo(
          index * 96.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
      setState(() => _highlightedProductIndex = index);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlightedProductIndex = null);
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('المنتج غير موجود في القائمة!',
              style: TextStyle(fontFamily: 'Tahoma')),
          backgroundColor: AppTheme.errorColor,
          duration: Duration(seconds: 2),
        ));
      }
    }
    _listScanFocusNode.requestFocus();
  }

  // حوار تعديل المنتج
  void _showEditDialog(ProductModel product) {
    showDialog(
      context: context,
      builder: (ctx) => _EditProductDialog(
        product: product,
        onSaved: _loadAllProducts,
      ),
    );
  }

  void _confirmDelete(ProductModel product) {
    final profit = product.price - product.purchasePrice;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 28),
            const SizedBox(width: 8),
            const Text('تأكيد الحذف', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  _deleteDetailRow(Icons.category, 'القسم', product.category),
                  if (product.color.isNotEmpty) _deleteDetailRow(Icons.palette, 'اللون', product.color),
                  if (product.size.isNotEmpty) _deleteDetailRow(Icons.straighten, 'القياس', product.size),
                  _deleteDetailRow(Icons.attach_money, 'سعر الشراء', '${product.purchasePrice} د'),
                  _deleteDetailRow(Icons.sell, 'سعر البيع', '${product.price} د'),
                  _deleteDetailRow(Icons.trending_up, 'الربح', '$profit د', color: profit > 0 ? AppTheme.successColor : AppTheme.errorColor),
                  _deleteDetailRow(Icons.inventory, 'المخزون', '${product.stock} قطعة'),
                  if (product.barcode.isNotEmpty) _deleteDetailRow(Icons.qr_code, 'الباركود', product.barcode),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.warningColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'سيتم حفظ المنتج في سجل الحذف ويمكنك استرجاعه لاحقاً.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('حذف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () async {
              final success = await DatabaseHelper.instance.deleteProductWithLog(product.id!);
              if (ctx.mounted) Navigator.pop(ctx);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم حذف "${product.name}" — يمكن استرجاعه من سجل الحذف'),
                    backgroundColor: AppTheme.warningColor,
                    action: SnackBarAction(
                      label: 'استرجاع',
                      textColor: Colors.white,
                      onPressed: _showDeleteLog,
                    ),
                  ),
                );
                _loadAllProducts();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _deleteDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Expanded(
            child: Text(value, style: TextStyle(
              color: color ?? AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            )),
          ),
        ],
      ),
    );
  }

  // ─── اختصار Ctrl+R لاسترجاع آخر منتج ───
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyR) {
      _restoreLastProduct();
      return true;
    }
    return false;
  }

  // ─── سجل الحذف والاسترجاع ───
  void _showDeleteLog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => _DeleteLogSheet(scrollController: scrollController),
      ),
    ).then((_) => _loadAllProducts());
  }

  // تكرار منتج كـ variant جديد (same name, category, prices — clear color/size/barcode)
  void _duplicateAsVariant(ProductModel product) {
    _tabController.animateTo(0); // الانتقال لتبويب الإضافة
    setState(() {
      _nameController.text = product.name;
      _selectedCategory = product.category;
      _purchasePriceController.text = product.purchasePrice.toString();
      _priceController.text = product.price.toString();
      _colorController.clear();
      _sizeController.clear();
      _stockController.clear();
      _barcodeController.clear();
      _extraBarcodes.clear();
      _isCustomBarcode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('تم نسخ "${product.name}" — أضف لون/قياس وباركود جديد'),
      backgroundColor: AppTheme.successColor,
    ));
  }

  // سجل التعديلات العالمي لجميع المنتجات

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedProductIds.clear();
          });
          _bulkQtyController.clear();
          _bulkSellPriceController.clear();
          _bulkBuyPriceController.clear();
          _selectionAnimController.reverse();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isSelectionMode
              ? 'تحديد ${_selectedProductIds.length} منتج'
              : 'إدارة المنتجات'),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.add_box), text: 'إضافة منتج'),
              Tab(icon: Icon(Icons.list_alt), text: 'قائمة المنتجات'),
            ],
          ),
          actions: [
            if (_tabController.index == 1 && !_isSelectionMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) {
                  if (v == 'low_stock') _exportLowStockPdf();
                  if (v == 'adjustment_log') _showAllAdjustmentLog();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'low_stock', child: Row(children: [Icon(Icons.warning_amber, size: 18, color: AppTheme.errorColor), SizedBox(width: 8), Text('تصدير المنتجات قليلة المخزون')])),
                  PopupMenuItem(value: 'adjustment_log', child: Row(children: [Icon(Icons.history, size: 18, color: AppTheme.primaryColor), SizedBox(width: 8), Text('سجل تصحيحات الجرد')])),
                ],
              ),
            if (_tabController.index == 1 && _isSelectionMode) ...[
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedProductIds.clear();
                  });
                  _bulkQtyController.clear();
                  _bulkSellPriceController.clear();
                  _bulkBuyPriceController.clear();
                  _selectionAnimController.reverse();
                },
                tooltip: 'إلغاء التحديد',
              ),
            ],
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAddProductTab(),
            _buildProductsListTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildAddProductTab() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
            // 1. اختيار القسم
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'القسم',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: AppTheme.surfaceColor,
                    ),
                    items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                    onChanged: (val) => setState(() => _selectedCategory = val),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(color: AppTheme.primaryColor, borderRadius: BorderRadius.circular(12)),
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: _addNewCategory,
                    tooltip: 'إضافة قسم جديد',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. تفاصيل المنتج
            CustomTextField(
              label: 'اسم المنتج (مثال: عطر جادور)',
              controller: _nameController,
              icon: Icons.shopping_bag,
              focusNode: _nameFocusNode,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _colorFocusNode.requestFocus(),
              validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم المنتج' : null,
            ),
            Row(
              children: [
                Expanded(child: CustomTextField(
                  label: 'اللون (اختياري)',
                  controller: _colorController,
                  icon: Icons.color_lens,
                  focusNode: _colorFocusNode,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _sizeFocusNode.requestFocus(),
                )),
                const SizedBox(width: 16),
                Expanded(child: CustomTextField(
                  label: 'القياس (اختياري)',
                  controller: _sizeController,
                  icon: Icons.straighten,
                  focusNode: _sizeFocusNode,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _purchasePriceFocusNode.requestFocus(),
                )),
              ],
            ),

            // 3. الأسعار (شراء + بيع)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('الأسعار:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            ),
            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: 'سعر الشراء (دينار)',
                    controller: _purchasePriceController,
                    keyboardType: TextInputType.number,
                    icon: Icons.trending_down,
                    focusNode: _purchasePriceFocusNode,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _priceFocusNode.requestFocus(),
                    validator: _validatePositiveInt,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomTextField(
                    label: 'سعر البيع (دينار)',
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    icon: Icons.trending_up,
                    focusNode: _priceFocusNode,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _stockFocusNode.requestFocus(),
                    validator: _validatePositiveInt,
                  ),
                ),
              ],
            ),
            CustomTextField(
              label: 'الكمية (المخزون الأولي)',
              controller: _stockController,
              keyboardType: TextInputType.number,
              icon: Icons.inventory,
              focusNode: _stockFocusNode,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _barcodeFocusNode.requestFocus(),
              validator: _validateNonNegativeInt,
            ),
            const Divider(height: 32, thickness: 1),

            // 4. الباركود
            const Text('إعدادات الباركود:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: CustomTextField(
                    label: 'رقم الباركود (امسح أو ولّد)',
                    controller: _barcodeController,
                    icon: Icons.qr_code,
                    focusNode: _barcodeFocusNode,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saveProduct(),
                    validator: (val) => val == null || val.isEmpty ? 'يرجى مسح أو توليد باركود' : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.autorenew),
                    label: const Text('توليد محلي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _generateCustomBarcode,
                  ),
                ),
              ],
            ),

            // 4.1 باركودات إضافية
            if (_extraBarcodes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _extraBarcodes.map((b) => Chip(
                  label: Text(b, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeExtraBarcode(b),
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                )).toList(),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addExtraBarcode,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة باركود إضافي'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            ),

            const SizedBox(height: 32),

            // 5. أزرار الحفظ والاسترجاع
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: CustomButton(
                    text: 'حفظ المنتج في المخزن',
                    icon: Icons.save,
                    onPressed: _saveProduct,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondaryColor,
                      foregroundColor: AppTheme.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('استرجاع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: _restoreLastProduct,
                  ),
                ),
              ],
            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductsListTab() {
    // ─── البحث الذكي ───
    List<ProductModel> filteredProducts = _allProducts;
    if (_listSearchQuery.isNotEmpty) {
      final query = _listSearchQuery.toLowerCase();
      final words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty) {
        filteredProducts = _allProducts.where((p) {
          final name = p.name.toLowerCase();
          final color = p.color.toLowerCase();
          final size = p.size.toLowerCase();
          final barcode = p.barcode.toLowerCase();
          final secondaryBarcodes = _secondaryBarcodes[p.id] ?? [];
          final hasMatchingSecondaryBarcode = secondaryBarcodes.any((bc) =>
            words.every((word) => bc.toLowerCase().contains(word))
          );
          return words.every((word) =>
            name.contains(word) ||
            color.contains(word) ||
            size.contains(word) ||
            barcode.contains(word)
          ) || hasMatchingSecondaryBarcode;
        }).toList();
      }
    }

    // ─── تطبيق الفلاتر ───
    // فلترة المخزون
    if (_filterStock.isNotEmpty) {
      filteredProducts = filteredProducts.where((p) {
        switch (_filterStock) {
          case 'zero': return p.stock == 0;
          case 'low': return p.stock > 0 && p.stock <= 5;
          case 'medium': return p.stock > 5 && p.stock <= 20;
          case 'high': return p.stock > 20;
          default: return true;
        }
      }).toList();
    }
    // فلترة السعر
    if (_filterPriceMin != null) {
      filteredProducts = filteredProducts.where((p) => p.price >= _filterPriceMin!).toList();
    }
    if (_filterPriceMax != null) {
      filteredProducts = filteredProducts.where((p) => p.price <= _filterPriceMax!).toList();
    }
    // فلترة الربح
    if (_filterProfitMin != null) {
      filteredProducts = filteredProducts.where((p) => (p.price - p.purchasePrice) >= _filterProfitMin!).toList();
    }
    if (_filterProfitMax != null) {
      filteredProducts = filteredProducts.where((p) => (p.price - p.purchasePrice) <= _filterProfitMax!).toList();
    }
    // فلترة اللون
    if (_filterColor.isNotEmpty) {
      filteredProducts = filteredProducts.where((p) => p.color == _filterColor).toList();
    }
    // فلترة القياس
    if (_filterSize.isNotEmpty) {
      filteredProducts = filteredProducts.where((p) => p.size == _filterSize).toList();
    }
    // فلترة القسم
    if (_filterCategory.isNotEmpty) {
      filteredProducts = filteredProducts.where((p) => p.category == _filterCategory).toList();
    }
    // فلترة المبيعات
    if (_filterOnlySold) {
      filteredProducts = filteredProducts.where((p) =>
        _productSalesStats.containsKey(p.id) && (_productSalesStats[p.id]!['total_sold'] as int) > 0
      ).toList();
    }
    if (_filterNeverSold) {
      filteredProducts = filteredProducts.where((p) =>
        !_productSalesStats.containsKey(p.id) || (_productSalesStats[p.id]!['total_sold'] as int) == 0
      ).toList();
    }

    // ─── الترتيب ───
    filteredProducts.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'price':
          cmp = a.price.compareTo(b.price);
          break;
        case 'stock':
          cmp = a.stock.compareTo(b.stock);
          break;
        case 'profit':
          cmp = (a.price - a.purchasePrice).compareTo(b.price - b.purchasePrice);
          break;
        case 'sold':
          final aSold = _productSalesStats[a.id]?['total_sold'] ?? 0;
          final bSold = _productSalesStats[b.id]?['total_sold'] ?? 0;
          cmp = (aSold as int).compareTo(bSold as int);
          break;
        case 'lastSold':
          final aDate = _productSalesStats[a.id]?['last_sold_date'] ?? '';
          final bDate = _productSalesStats[b.id]?['last_sold_date'] ?? '';
          cmp = aDate.compareTo(bDate);
          break;
        case 'name':
        default:
          cmp = a.name.compareTo(b.name);
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });

    // ─── جمع القيم الإحصائية ───
    final totalProducts = filteredProducts.length;
    final totalStockValue = filteredProducts.fold<int>(0, (sum, p) => sum + (p.price * p.stock));
    final totalStockQty = filteredProducts.fold<int>(0, (sum, p) => sum + p.stock);

    return Column(
      children: [
        // ─── حقل البحث + أزرار الفلتر والترتيب ───
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _listScanController,
                  focusNode: _listScanFocusNode,
                  decoration: InputDecoration(
                    labelText: 'بحث بالاسم أو اللون أو القياس أو الباركود',
                    prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: AppTheme.searchFieldColor,
                  ),
                  onChanged: (val) => setState(() => _listSearchQuery = val),
                  onSubmitted: _onProductsListScan,
                ),
              ),
              const SizedBox(width: 8),
              // زر الفلتر
              IconButton.filled(
                onPressed: () => setState(() => _showFilters = !_showFilters),
                style: IconButton.styleFrom(
                  backgroundColor: _showFilters ? AppTheme.primaryColor : AppTheme.neutralLightColor,
                  foregroundColor: _showFilters ? Colors.white : AppTheme.primaryColor,
                ),
                icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
                tooltip: 'الفلاتر',
              ),
              const SizedBox(width: 4),
              // زر الترتيب
              IconButton.filled(
                onPressed: _showSortDialog,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.neutralLightColor,
                  foregroundColor: AppTheme.primaryColor,
                ),
                icon: const Icon(Icons.sort),
                tooltip: 'الترتيب',
              ),
            ],
          ),
        ),
        // ─── الإحصائيات السريعة ───
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _buildStatChip('$totalProducts', 'منتج', AppTheme.primaryColor),
              const SizedBox(width: 6),
              _buildStatChip('$totalStockQty', 'قطعة', AppTheme.warningColor),
              const SizedBox(width: 6),
              _buildStatChip('${totalStockValue.toStringAsFixed(0)} د', 'قيمة', AppTheme.successColor),
              const Spacer(),
              GestureDetector(
                onTap: _showDeleteLog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.errorColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_sweep, size: 14, color: AppTheme.errorColor),
                      const SizedBox(width: 4),
                      const Text('سجل الحذف', style: TextStyle(color: AppTheme.errorColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // ─── شريط الفلاتر (يظهر/يختفي) ───
        if (_showFilters) _buildFilterBar(),
        // ─── قائمة المنتجات ───
        Expanded(
          child: _isLoadingProducts
              ? const Center(child: CircularProgressIndicator())
              : _allProducts.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد منتجات بعد.\nأضف منتجات من تبويب "إضافة منتج".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                      ),
                    )
                  : filteredProducts.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد نتائج مطابقة للبحث.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                      key: _listKey,
                      controller: _listScrollController,
                      itemExtent: 96.0,
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                          final p = filteredProducts[index];
                          final profit = p.price - p.purchasePrice;
                          final isHighlighted = _highlightedProductIndex == index;
                          final isSelected = _selectedProductIds.contains(p.id);
                          
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryColor.withOpacity(0.05)
                                  : (isHighlighted ? AppTheme.highlightColor : AppTheme.surfaceColor),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryColor
                                    : Colors.grey.withOpacity(0.2),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? AppTheme.primaryColor.withOpacity(0.15)
                                      : Colors.black.withOpacity(0.05),
                                  blurRadius: isSelected ? 8 : 2,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPressStart: (details) {
                                final pid = p.id;
                                if (pid == null) return;
                                setState(() {
                                  _isDragSelecting = true;
                                  _dragAnchorIndex = index;
                                  if (!_isSelectionMode) {
                                    _isSelectionMode = true;
                                    _selectionAnimController.forward();
                                  }
                                  _selectedProductIds.add(pid);
                                });
                              },
                              onLongPressMoveUpdate: (details) {
                                if (!_isDragSelecting || _dragAnchorIndex < 0) return;
                                final listObj = _listKey.currentContext?.findRenderObject();
                                if (listObj == null || !listObj.attached) return;
                                final listBox = listObj as RenderBox;
                                final listTop = listBox.localToGlobal(Offset.zero).dy;
                                final listHeight = listBox.size.height;
                                final scrollOffset = _listScrollController.hasClients ? _listScrollController.offset : 0.0;
                                final fingerY = details.globalPosition.dy - listTop + scrollOffset;
                                final fingerRelativeY = details.globalPosition.dy - listTop;
                                final currentIndex = (fingerY / 96.0).floor().clamp(0, filteredProducts.length - 1);
                                final start = _dragAnchorIndex < currentIndex ? _dragAnchorIndex : currentIndex;
                                final end = _dragAnchorIndex < currentIndex ? currentIndex : _dragAnchorIndex;
                                setState(() {
                                  for (var i = start; i <= end; i++) {
                                    final id = filteredProducts[i].id;
                                    if (id != null) _selectedProductIds.add(id);
                                  }
                                });
                                // Auto-scroll
                                const edgeSize = 60.0;
                                if (fingerRelativeY < edgeSize) {
                                  _startAutoScroll(-1);
                                } else if (fingerRelativeY > listHeight - edgeSize) {
                                  _startAutoScroll(1);
                                } else {
                                  _stopAutoScroll();
                                }
                              },
                              onLongPressEnd: (_) {
                                _stopAutoScroll();
                                _isDragSelecting = false;
                                _dragAnchorIndex = -1;
                                if (_selectedProductIds.isEmpty && _isSelectionMode) {
                                  setState(() {
                                    _isSelectionMode = false;
                                    _selectionAnimController.reverse();
                                  });
                                }
                              },
                              child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              leading: _isSelectionMode
                                  ? AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected ? AppTheme.primaryColor : Colors.grey.withOpacity(0.4),
                                          width: 2,
                                        ),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                                          : null,
                                    )
                                  : CircleAvatar(
                                      backgroundColor: p.stock > 0
                                          ? AppTheme.primaryColor.withOpacity(0.15)
                                          : AppTheme.errorColor.withOpacity(0.15),
                                      child: Text('${p.stock}',
                                          style: TextStyle(
                                            color: p.stock > 0 ? AppTheme.primaryColor : AppTheme.errorColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          )),
                                    ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${_selectedProductIds.length}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.category}${p.color.isNotEmpty ? " | ${p.color}" : ""}${p.size.isNotEmpty ? " | ${p.size}" : ""}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'شراء: ${p.purchasePrice} | بيع: ${p.price} | ربح: $profit د',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: profit > 0 ? AppTheme.successColor : AppTheme.errorColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              onTap: _isSelectionMode
                                  ? () {
                                      final pid = p.id;
                                      if (pid == null) return;
                                      setState(() {
                                        if (_selectedProductIds.contains(pid)) {
                                          _selectedProductIds.remove(pid);
                                          if (_selectedProductIds.isEmpty) {
                                            _isSelectionMode = false;
                                            _selectionAnimController.reverse();
                                          }
                                        } else {
                                          _selectedProductIds.add(pid);
                                        }
                                      });
                                    }
                                  : null,
trailing: _isSelectionMode
                                  ? const SizedBox.shrink()
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.copy, color: AppTheme.primaryColor),
                                          onPressed: () => _duplicateAsVariant(p),
                                          tooltip: 'تكرار كـ variant',
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.print, color: p.barcode.isNotEmpty ? AppTheme.successColor : AppTheme.neutralColor),
                                          onPressed: p.barcode.isNotEmpty
                                              ? () => BarcodePrinterWidget.show(context, barcode: p.barcode, productName: p.name, price: p.price)
                                              : () {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('لا يوجد باركود لهذا المنتج!'), backgroundColor: AppTheme.errorColor),
                                                  );
                                                },
                                          tooltip: 'طباعة باركود',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
                                          onPressed: () => _showEditDialog(p),
                                          tooltip: 'تعديل',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.inventory, color: AppTheme.warningColor),
                                          onPressed: () => _showStockAdjustDialog(p),
                                          tooltip: 'تصحيح الجرد',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                                          onPressed: () => _confirmDelete(p),
                                          tooltip: 'حذف',
                                        ),
                                        ],
                                     ),
                           ), // ListTile
                           ), // GestureDetector
                           ), // Material
                         );
                      },
                     ),
        ),
        // ─── شريط التحديد السفلي (Animated) ───
        AnimatedBuilder(
          animation: _selectionSlideAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, (1 - _selectionSlideAnimation.value) * 100),
              child: Opacity(
                opacity: _selectionSlideAnimation.value,
                child: child,
              ),
            );
          },
          child: _isSelectionMode
              ? Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ─── Header ───
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${_selectedProductIds.length}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'منتج محدد',
                              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  _isSelectionMode = false;
                                  _selectedProductIds.clear();
                                  _bulkQtyController.clear();
                                });
                                _selectionAnimController.reverse();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ─── Operation Cards ───
                        Row(
                          children: [
                            _buildOperationCard(0, 'إضافة', Icons.add_circle_outline, AppTheme.successColor),
                            const SizedBox(width: 6),
                            _buildOperationCard(1, 'خصم', Icons.remove_circle_outline, AppTheme.errorColor),
                            const SizedBox(width: 6),
                            _buildOperationCard(2, 'تعيين', Icons.edit_notifications_outlined, AppTheme.primaryColor),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildOperationCard(3, 'حذف', Icons.delete_outline, AppTheme.errorColor),
                            const SizedBox(width: 6),
                            _buildOperationCard(4, 'القسم', Icons.category_outlined, AppTheme.warningColor),
                            const SizedBox(width: 6),
                            _buildOperationCard(5, 'اللون', Icons.palette_outlined, AppTheme.primaryColor),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildOperationCard(6, 'السعر', Icons.attach_money, AppTheme.successColor),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // ─── Quantity Input + Apply ───
                        if (_bulkOperationType <= 2)
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bulkQtyController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    hintText: _bulkOperationType == 0
                                        ? '+ كمية للإضافة'
                                        : _bulkOperationType == 1
                                            ? '- كمية للخصم'
                                            : '= الكمية الجديدة',
                                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                                    prefixIcon: Icon(
                                      _bulkOperationType == 0
                                          ? Icons.add
                                          : _bulkOperationType == 1
                                              ? Icons.remove
                                              : Icons.drag_handle,
                                      color: _bulkOperationType == 0
                                          ? AppTheme.successColor
                                          : _bulkOperationType == 1
                                              ? AppTheme.errorColor
                                              : AppTheme.primaryColor,
                                      size: 20,
                                    ),
                                    filled: true,
                                    fillColor: AppTheme.neutralLightColor,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () => _applyBulkOperation(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _bulkOperationType == 0
                                      ? AppTheme.successColor
                                      : _bulkOperationType == 1
                                          ? AppTheme.errorColor
                                          : AppTheme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                child: const Text('تطبيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                            ],
                          )
                        else if (_bulkOperationType == 6)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ─── أوضاع السعر (3 أزرار) ───
                              Row(
                                children: [
                                  _buildPriceModeChip(0, 'زيادة %', Icons.trending_up, AppTheme.successColor),
                                  const SizedBox(width: 6),
                                  _buildPriceModeChip(1, 'خصم %', Icons.trending_down, AppTheme.errorColor),
                                  const SizedBox(width: 6),
                                  _buildPriceModeChip(2, 'سعر ثابت', Icons.attach_money, AppTheme.primaryColor),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // ─── حقل السعر ───
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _bulkSellPriceController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        hintText: _bulkPriceMode == 2
                                            ? 'سعر البيع الجديد'
                                            : _bulkPriceMode == 0
                                                ? '+ مبلغ الزيادة على البيع'
                                                : '- مبلغ الخصم من البيع',
                                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 11),
                                        prefixIcon: Icon(
                                          _bulkPriceMode == 0
                                              ? Icons.trending_up
                                              : _bulkPriceMode == 1
                                                  ? Icons.trending_down
                                                  : Icons.sell,
                                          color: AppTheme.successColor,
                                          size: 18,
                                        ),
                                        filled: true,
                                        fillColor: AppTheme.neutralLightColor,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _bulkBuyPriceController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        hintText: _bulkPriceMode == 2
                                            ? 'سعر الشراء الجديد'
                                            : _bulkPriceMode == 0
                                                ? '+ مبلغ الزيادة على الشراء'
                                                : '- مبلغ الخصم من الشراء',
                                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 11),
                                        prefixIcon: Icon(
                                          _bulkPriceMode == 0
                                              ? Icons.trending_up
                                              : _bulkPriceMode == 1
                                                  ? Icons.trending_down
                                                  : Icons.shopping_cart,
                                          color: AppTheme.warningColor,
                                          size: 18,
                                        ),
                                        filled: true,
                                        fillColor: AppTheme.neutralLightColor,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _applyBulkOperation(),
                                  icon: Icon(
                                    _bulkPriceMode == 0
                                        ? Icons.trending_up
                                        : _bulkPriceMode == 1
                                            ? Icons.trending_down
                                            : Icons.attach_money,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _bulkPriceMode == 0
                                        ? 'زيادة على ${_selectedProductIds.length} منتج'
                                        : _bulkPriceMode == 1
                                            ? 'خصم من ${_selectedProductIds.length} منتج'
                                            : 'تعيين سعر ثابت لـ ${_selectedProductIds.length} منتج',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _bulkPriceMode == 0
                                        ? AppTheme.successColor
                                        : _bulkPriceMode == 1
                                            ? AppTheme.errorColor
                                            : AppTheme.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _applyBulkOperation(),
                                    icon: Icon(
                                      _bulkOperationType == 3
                                          ? Icons.delete_forever
                                          : _bulkOperationType == 4
                                              ? Icons.category
                                              : _bulkOperationType == 5
                                                  ? Icons.palette
                                                  : Icons.attach_money,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _bulkOperationType == 3
                                        ? 'حذف ${_selectedProductIds.length} منتج'
                                        : _bulkOperationType == 4
                                            ? 'تغيير القسم'
                                            : _bulkOperationType == 5
                                                ? 'تغيير اللون'
                                                : 'تطبيق الأسعار',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _bulkOperationType == 3
                                        ? AppTheme.errorColor
                                        : _bulkOperationType == 4
                                            ? AppTheme.warningColor
                                            : _bulkOperationType == 5
                                                ? AppTheme.primaryColor
                                                : AppTheme.successColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ─── رقاقة إحصائية ───
  Widget _buildStatChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ─── شريط الفلاتر ───
  Widget _buildFilterBar() {
    final colors = _allProducts.map((p) => p.color).where((c) => c.isNotEmpty).toSet().toList()..sort();
    final sizes = _allProducts.map((p) => p.size).where((s) => s.isNotEmpty).toSet().toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.neutralLightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // فلترة المخزون
          Row(
            children: [
              const Text('المخزون: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 4),
              _buildFilterChip('الكل', _filterStock == '', () => setState(() => _filterStock = '')),
              _buildFilterChip('صفر', _filterStock == 'zero', () => setState(() => _filterStock = 'zero')),
              _buildFilterChip('قليل ≤5', _filterStock == 'low', () => setState(() => _filterStock = 'low')),
              _buildFilterChip('متوسط', _filterStock == 'medium', () => setState(() => _filterStock = 'medium')),
              _buildFilterChip('كثير >20', _filterStock == 'high', () => setState(() => _filterStock = 'high')),
            ],
          ),
          const SizedBox(height: 8),
          // فلترة السعر والربح
          Row(
            children: [
              const Text('السعر: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 4),
              _buildPriceFilterChip('أقل من 10', _filterPriceMax == 10, () {
                setState(() { _filterPriceMin = null; _filterPriceMax = _filterPriceMax == 10 ? null : 10; });
              }),
              _buildPriceFilterChip('10-50', _filterPriceMin == 10 && _filterPriceMax == 50, () {
                setState(() { _filterPriceMin = 10; _filterPriceMax = 50; });
              }),
              _buildPriceFilterChip('50-100', _filterPriceMin == 50 && _filterPriceMax == 100, () {
                setState(() { _filterPriceMin = 50; _filterPriceMax = 100; });
              }),
              _buildPriceFilterChip('أكثر من 100', _filterPriceMin == 100, () {
                setState(() { _filterPriceMin = _filterPriceMin == 100 ? null : 100; _filterPriceMax = null; });
              }),
            ],
          ),
          const SizedBox(height: 8),
          // فلترة اللون والقياس
          Row(
            children: [
              if (colors.isNotEmpty) ...[
                const Text('اللون: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('الكل', _filterColor == '', () => setState(() => _filterColor = '')),
                        ...colors.map((c) => _buildFilterChip(c, _filterColor == c, () => setState(() => _filterColor = _filterColor == c ? '' : c))),
                      ],
                    ),
                  ),
                ),
              ],
              if (sizes.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Text('القياس: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 4),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('الكل', _filterSize == '', () => setState(() => _filterSize = '')),
                        ...sizes.map((s) => _buildFilterChip(s, _filterSize == s, () => setState(() => _filterSize = _filterSize == s ? '' : s))),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // فلترة المبيعات
          Row(
            children: [
              const Text('المبيعات: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 4),
              _buildFilterChip('مباع فقط', _filterOnlySold, () {
                setState(() { _filterOnlySold = !_filterOnlySold; if (_filterOnlySold) _filterNeverSold = false; });
              }),
              _buildFilterChip('لم يُبع', _filterNeverSold, () {
                setState(() { _filterNeverSold = !_filterNeverSold; if (_filterNeverSold) _filterOnlySold = false; });
              }),
              const Spacer(),
              if (_hasActiveFilters())
                TextButton.icon(
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('مسح الكل', style: TextStyle(fontSize: 12)),
                  onPressed: _clearAllFilters,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.successColor : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppTheme.successColor : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _filterStock.isNotEmpty ||
        _filterPriceMin != null || _filterPriceMax != null ||
        _filterProfitMin != null || _filterProfitMax != null ||
        _filterColor.isNotEmpty || _filterSize.isNotEmpty ||
        _filterCategory.isNotEmpty ||
        _filterOnlySold || _filterNeverSold;
  }

  void _clearAllFilters() {
    setState(() {
      _filterStock = '';
      _filterPriceMin = null;
      _filterPriceMax = null;
      _filterProfitMin = null;
      _filterProfitMax = null;
      _filterColor = '';
      _filterSize = '';
      _filterCategory = '';
      _filterOnlySold = false;
      _filterNeverSold = false;
    });
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ترتيب المنتجات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              _buildSortOption('name', 'الاسم', Icons.sort_by_alpha, setSheetState),
              _buildSortOption('price', 'السعر', Icons.attach_money, setSheetState),
              _buildSortOption('stock', 'المخزون', Icons.inventory, setSheetState),
              _buildSortOption('profit', 'الربح', Icons.trending_up, setSheetState),
              _buildSortOption('sold', 'الأكثر مبيعاً', Icons.star, setSheetState),
              _buildSortOption('lastSold', 'آخر بيع', Icons.access_time, setSheetState),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('الاتجاه: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('تصاعدي ↑', style: TextStyle(fontSize: 12)),
                    selected: _sortAsc,
                    onSelected: (_) => setSheetState(() => _sortAsc = true),
                    selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('تنازلي ↓', style: TextStyle(fontSize: 12)),
                    selected: !_sortAsc,
                    onSelected: (_) => setSheetState(() => _sortAsc = false),
                    selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Widget _buildSortOption(String value, String label, IconData icon, StateSetter setSheetState) {
    final isSelected = _sortBy == value;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary, size: 20),
      title: Text(label, style: TextStyle(
        color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      )),
      trailing: isSelected ? Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20) : null,
      onTap: () {
        setSheetState(() {
          if (_sortBy == value) {
            _sortAsc = !_sortAsc;
          } else {
            _sortBy = value;
            _sortAsc = true;
          }
        });
        setState(() {});
      },
    );
  }

  // ─── بطاقة العملية ───
  Widget _buildOperationCard(int type, String label, IconData icon, Color color) {
    final isSelected = _bulkOperationType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _bulkOperationType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : AppTheme.neutralLightColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.grey.withOpacity(0.2),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── بطاقة وضع السعر ───
  Widget _buildPriceModeChip(int mode, String label, IconData icon, Color color) {
    final isSelected = _bulkPriceMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _bulkPriceMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : AppTheme.neutralLightColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.grey.withOpacity(0.2),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── العملية المجمعة ───
  Future<void> _applyBulkOperation() async {
    if (_selectedProductIds.isEmpty) return;

    // العمليات 0,1,2 تحتاج كمية
    if (_bulkOperationType <= 2) {
      final qty = int.tryParse(_bulkQtyController.text);
      if (qty == null || qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل كمية صحيحة أكبر من صفر'), backgroundColor: AppTheme.errorColor),
        );
        return;
      }
    }

    // ─── حذف جماعي ───
    if (_bulkOperationType == 3) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد الحذف الجماعي', style: TextStyle(color: AppTheme.errorColor)),
          content: Text('هل تريد حذف ${_selectedProductIds.length} منتج محدد؟\nسيتم حفظها في سجل الحذف.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف الكل'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      int deleted = 0;
      for (final id in _selectedProductIds) {
        final success = await DatabaseHelper.instance.deleteProductWithLog(id);
        if (success) deleted++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حذف $deleted منتج'), backgroundColor: AppTheme.successColor),
        );
        _selectedProductIds.clear();
        _isSelectionMode = false;
        _loadAllProducts();
      }
      return;
    }

    // ─── تغيير القسم ───
    if (_bulkOperationType == 4) {
      final categories = await DatabaseHelper.instance.getAllCategories();
      if (categories.isEmpty || !mounted) return;
      String? selectedCat;
      final confirmed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تغيير القسم للجميع'),
          content: StatefulBuilder(
            builder: (ctx, setDialogState) => DropdownButtonFormField<String>(
              value: selectedCat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setDialogState(() => selectedCat = v),
              decoration: const InputDecoration(labelText: 'اختر القسم'),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, selectedCat),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      );
      if (confirmed == null || confirmed.isEmpty || !mounted) return;
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        for (final id in _selectedProductIds) {
          await txn.update('products', {'category': confirmed}, where: 'id = ?', whereArgs: [id]);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تغيير قسم ${_selectedProductIds.length} منتج إلى "$confirmed"'), backgroundColor: AppTheme.successColor),
        );
        _selectedProductIds.clear();
        _isSelectionMode = false;
        _loadAllProducts();
      }
      return;
    }

    // ─── تغيير اللون ───
    if (_bulkOperationType == 5) {
      final colorCtrl = TextEditingController();
      final confirmed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تغيير اللون للجميع'),
          content: TextField(
            controller: colorCtrl,
            decoration: const InputDecoration(labelText: 'اللون الجديد', hintText: 'مثال: أحمر'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, colorCtrl.text.trim()),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      );
      colorCtrl.dispose();
      if (confirmed == null || confirmed.isEmpty || !mounted) return;
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        for (final id in _selectedProductIds) {
          await txn.update('products', {'color': confirmed}, where: 'id = ?', whereArgs: [id]);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تغيير لون ${_selectedProductIds.length} منتج إلى "$confirmed"'), backgroundColor: AppTheme.successColor),
        );
        _selectedProductIds.clear();
        _isSelectionMode = false;
        _loadAllProducts();
      }
      return;
    }

    // ─── تطبيق الأسعار ───
    if (_bulkOperationType == 6) {
      final sellValue = double.tryParse(_bulkSellPriceController.text);
      final buyValue = double.tryParse(_bulkBuyPriceController.text);
      if (sellValue == null && buyValue == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل قيمة سعر البيع أو الشراء على الأقل'), backgroundColor: AppTheme.errorColor),
        );
        return;
      }
      final modeLabel = _bulkPriceMode == 0 ? 'زيادة' : _bulkPriceMode == 1 ? 'خصم' : 'سعر ثابت';
      final parts = <String>[];
      if (sellValue != null) parts.add('البيع ($sellValue د.ع)');
      if (buyValue != null) parts.add('الشراء ($buyValue د.ع)');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('تأكيد $modeLabel', style: TextStyle(color: AppTheme.primaryColor)),
          content: Text('سيتم تطبيق $modeLabel على ${parts.join(' + ')} لـ ${_selectedProductIds.length} منتج محدد.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        final db = await DatabaseHelper.instance.database;
        await db.transaction((txn) async {
          for (final id in _selectedProductIds) {
            final rows = await txn.query('products', columns: ['sell_price', 'purchase_price'], where: 'id = ?', whereArgs: [id]);
            if (rows.isEmpty) continue;
            final currentSell = (rows.first['sell_price'] as num?)?.toDouble() ?? 0;
            final currentBuy = (rows.first['purchase_price'] as num?)?.toDouble() ?? 0;
            final updates = <String, dynamic>{};
            if (sellValue != null) {
              switch (_bulkPriceMode) {
                case 0: updates['sell_price'] = currentSell + sellValue; break;
                case 1: updates['sell_price'] = (currentSell - sellValue).clamp(0.0, 999999999.0); break;
                default: updates['sell_price'] = sellValue;
              }
            }
            if (buyValue != null) {
              switch (_bulkPriceMode) {
                case 0: updates['purchase_price'] = currentBuy + buyValue; break;
                case 1: updates['purchase_price'] = (currentBuy - buyValue).clamp(0.0, 999999999.0); break;
                default: updates['purchase_price'] = buyValue;
              }
            }
            if (updates.isNotEmpty) await txn.update('products', updates, where: 'id = ?', whereArgs: [id]);
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم تطبيق $modeLabel على ${_selectedProductIds.length} منتج'), backgroundColor: AppTheme.successColor),
          );
          _selectedProductIds.clear();
          _isSelectionMode = false;
          _bulkSellPriceController.clear();
          _bulkBuyPriceController.clear();
          _loadAllProducts();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.errorColor),
          );
        }
      }
    }

    // ─── إضافة / خصم / تعيين كمية ───
    final qty = int.tryParse(_bulkQtyController.text) ?? 0;
    final opName = _bulkOperationType == 0 ? 'إضافة' : _bulkOperationType == 1 ? 'خصم' : 'تعيين';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد $opName $qty', style: TextStyle(color: AppTheme.primaryColor)),
        content: Text('سيتم $opName $qty على ${_selectedProductIds.length} منتج محدد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final db = await DatabaseHelper.instance.database;
      await db.transaction((txn) async {
        for (final id in _selectedProductIds) {
          final rows = await txn.query('products', columns: ['stock', 'name'], where: 'id = ?', whereArgs: [id]);
          if (rows.isEmpty) continue;
          final currentStock = (rows.first['stock'] as int?) ?? 0;
          final productName = (rows.first['name'] as String?) ?? '';
          int newStock;
          switch (_bulkOperationType) {
            case 0: newStock = currentStock + qty; break;
            case 1: newStock = (currentStock - qty).clamp(0, 999999); break;
            default: newStock = qty;
          }
          await txn.update('products', {'stock': newStock}, where: 'id = ?', whereArgs: [id]);
          await txn.insert('stock_adjustments', {
            'product_id': id,
            'product_name': productName,
            'old_stock': currentStock,
            'new_stock': newStock,
            'difference': newStock - currentStock,
            'reason': 'جمع: $opName $qty',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم $opName $qty على ${_selectedProductIds.length} منتج'), backgroundColor: AppTheme.successColor),
        );
        _selectedProductIds.clear();
        _isSelectionMode = false;
        _bulkQtyController.clear();
        _loadAllProducts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _startAutoScroll(double direction) {
    if (_autoScrollDirection == direction && _autoScrollTimer != null) return;
    _stopAutoScroll();
    _autoScrollDirection = direction;
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_listScrollController.hasClients) return;
      final maxScroll = _listScrollController.position.maxScrollExtent;
      final currentScroll = _listScrollController.offset;
      final step = direction * 8.0;
      final newScroll = (currentScroll + step).clamp(0.0, maxScroll);
      _listScrollController.jumpTo(newScroll);
    });
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
  }

  // ─── حوار تصحيح الجرد ───
  Future<void> _showStockAdjustDialog(ProductModel product) async {
    final qtyCtrl = TextEditingController(text: '${product.stock}');
    String reason = 'عدّ صندوق';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final newStock = int.tryParse(qtyCtrl.text) ?? product.stock;
          final diff = newStock - product.stock;
          return AlertDialog(
            title: Text('تصحيح الجرد — ${product.name}',
                style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.neutralLightColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(children: [
                          Text('${product.stock}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          const Text('الحالي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ]),
                        const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
                        Column(children: [
                          Text('$newStock',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                                  color: diff == 0 ? AppTheme.textSecondary : (diff > 0 ? AppTheme.successColor : AppTheme.errorColor))),
                          const Text('الجديد', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ]),
                        if (diff != 0)
                          Column(children: [
                            Text(diff > 0 ? '+$diff' : '$diff',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                                    color: diff > 0 ? AppTheme.successColor : AppTheme.errorColor)),
                            const Text('الفرق', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'الكمية الصحيحة',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory_2),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  const Text('سبب التصحيح:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...['عدّ صندوق', 'تالف / تلف', 'منتهي الصلاحية', 'مسروق / مفقود'].map((r) =>
                    RadioListTile<String>(
                      value: r,
                      groupValue: reason,
                      activeColor: AppTheme.primaryColor,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(r, style: const TextStyle(fontSize: 14)),
                      onChanged: (v) => setDialogState(() => reason = v!),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (diff != 0 && newStock >= 0) ? AppTheme.warningColor : AppTheme.neutralColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: (diff != 0 && newStock >= 0) ? () => Navigator.pop(ctx, true) : null,
                icon: const Icon(Icons.check),
                label: const Text('تطبيق التصحيح'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final newStock = int.tryParse(qtyCtrl.text) ?? -1;
    final pid = product.id;
    if (pid == null) return;
    final ok = await DatabaseHelper.instance.adjustStock(pid, newStock, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'تم تصحيح الجرد ✓ (${product.name}: ${product.stock} ← $newStock)' : 'فشل التصحيح — تأكد من الرقم'),
        backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
      ),
    );
    if (ok) _showAdjustmentHistory(pid);
  }

  /// عرض سجل تصحيحات الجرد لمنتج
  Future<void> _showAdjustmentHistory(int productId) async {
    final adjustments = await DatabaseHelper.instance.getAdjustmentsForProduct(productId);
    if (!mounted || adjustments.isEmpty) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          const Center(child: Text('سجل تصحيحات الجرد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor))),
          const SizedBox(height: 12),
          ...adjustments.map((a) {
            final diff = a['difference'] as int? ?? 0;
            return ListTile(
              leading: Icon(
                diff > 0 ? Icons.add_circle : Icons.remove_circle,
                color: diff > 0 ? AppTheme.successColor : AppTheme.errorColor,
              ),
              title: Text('${a['old_stock']} ← ${a['new_stock']} (${a['reason']})', style: const TextStyle(fontSize: 13)),
              subtitle: Text((a['created_at'] as String).substring(0, 16).replaceAll('T', ' '), style: const TextStyle(fontSize: 11)),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showAllAdjustmentLog() async {
    final adjustments = await DatabaseHelper.instance.getAllAdjustments();
    if (!mounted) return;
    if (adjustments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد تصحيحات جرد بعد'), backgroundColor: AppTheme.textSecondary));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('سجل تصحيحات الجرد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor))),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: adjustments.length,
                itemBuilder: (ctx, i) {
                  final a = adjustments[i];
                  final name = a['product_name'] as String? ?? 'منتج محذوف';
                  final diff = a['difference'] as int? ?? 0;
                  final oldStock = a['old_stock'] as int? ?? 0;
                  final newStock = a['new_stock'] as int? ?? 0;
                  final reason = a['reason'] as String? ?? '';
                  final date = (a['created_at'] as String? ?? '').substring(0, 16).replaceAll('T', ' ');
                  return ListTile(
                    leading: Icon(
                      diff > 0 ? Icons.add_circle : Icons.remove_circle,
                      color: diff > 0 ? AppTheme.successColor : AppTheme.errorColor,
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('$oldStock ← $newStock  |  $reason', style: const TextStyle(fontSize: 11)),
                    trailing: Text(date, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── واجهة سجل الحذف ───
class _DeleteLogSheet extends StatefulWidget {
  final ScrollController scrollController;
  const _DeleteLogSheet({required this.scrollController});

  @override
  State<_DeleteLogSheet> createState() => _DeleteLogSheetState();
}

class _DeleteLogSheetState extends State<_DeleteLogSheet> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final logs = await DatabaseHelper.instance.getDeleteLog(limit: 200);
    if (mounted) setState(() { _logs = logs; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.delete_sweep, color: AppTheme.errorColor, size: 24),
                const SizedBox(width: 8),
                const Text('سجل الحذف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const Spacer(),
                Text('${_logs.length} منتج محذوف', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, color: AppTheme.successColor, size: 48),
                            SizedBox(height: 8),
                            Text('لا توجد منتجات محذوفة', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _logs.length,
                        itemBuilder: (ctx, index) {
                          final log = _logs[index];
                          final profit = ((log['price'] ?? 0) as int) - ((log['purchase_price'] ?? 0) as int);
                          final deletedAt = (log['deleted_at'] as String).substring(0, 16).replaceAll('T', ' ');
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(log['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                                      PopupMenuButton<String>(
                                        onSelected: (action) => _handleLogAction(action, log),
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(value: 'restore', child: Row(
                                            children: [Icon(Icons.restore, color: AppTheme.successColor, size: 18), SizedBox(width: 8), Text('استرجاع')],
                                          )),
                                          const PopupMenuItem(value: 'permanent', child: Row(
                                            children: [Icon(Icons.delete_forever, color: AppTheme.errorColor, size: 18), SizedBox(width: 8), Text('حذف نهائي')],
                                          )),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8, runSpacing: 2,
                                    children: [
                                      if ((log['category'] as String?)?.isNotEmpty == true) _logChip(Icons.category, log['category']),
                                      if ((log['color'] as String?)?.isNotEmpty == true) _logChip(Icons.palette, log['color']),
                                      if ((log['size'] as String?)?.isNotEmpty == true) _logChip(Icons.straighten, log['size']),
                                      _logChip(Icons.attach_money, '${log['price'] ?? 0} د'),
                                      _logChip(Icons.inventory, '${log['stock'] ?? 0} قطعة'),
                                      if (profit > 0) _logChip(Icons.trending_up, '$profit ربح', color: AppTheme.successColor),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.access_time, size: 12, color: AppTheme.textSecondary),
                                      const SizedBox(width: 4),
                                      Text(deletedAt, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                      const Spacer(),
                                      if ((log['barcode'] as String?)?.isNotEmpty == true)
                                        Text('باركود: ${log['barcode']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _logChip(IconData icon, String label, {Color? color}) {
    return Chip(
      avatar: Icon(icon, size: 14, color: color ?? AppTheme.primaryColor),
      label: Text(label, style: TextStyle(fontSize: 11, color: color ?? AppTheme.textPrimary)),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Future<void> _handleLogAction(String action, Map<String, dynamic> log) async {
    if (action == 'restore') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('استرجاع المنتج', style: TextStyle(color: AppTheme.successColor)),
          content: Text('هل تريد استرجاع "${log['product_name']}"؟\nسيعود للقائمة مع كل بياناته.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استرجاع'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final success = await DatabaseHelper.instance.restoreFromDeleteLog(log['id'] as int);
        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم استرجاع "${log['product_name']}" بنجاح'), backgroundColor: AppTheme.successColor),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('فشل الاسترجاع — المنتج قد يكون موجوداً بالفعل'), backgroundColor: AppTheme.errorColor),
            );
          }
          _loadLogs();
        }
      }
    } else if (action == 'permanent') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف نهائي', style: TextStyle(color: AppTheme.errorColor)),
          content: Text('هل تريد حذف "${log['product_name']}" نهائياً؟\nلا يمكن التراجع عن هذا الإجراء.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await DatabaseHelper.instance.permanentDeleteLog(log['id'] as int);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الحذف نهائيًا'), backgroundColor: AppTheme.errorColor),
          );
          _loadLogs();
        }
      }
    }
  }
}

// ============================================================
// نافذة تعديل المنتج مع إدارة الباركودات
// ============================================================
class _EditProductDialog extends StatefulWidget {
  final ProductModel product;
  final VoidCallback onSaved;

  const _EditProductDialog({required this.product, required this.onSaved});

  @override
  State<_EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<_EditProductDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _stockCtrl;

  List<Map<String, dynamic>> _barcodes = [];
  bool _barcodesLoading = true;

  String? _selectedCategory;
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product.name);
    _colorCtrl = TextEditingController(text: widget.product.color);
    _sizeCtrl = TextEditingController(text: widget.product.size);
    _priceCtrl = TextEditingController(text: widget.product.price.toString());
    _purchasePriceCtrl = TextEditingController(text: widget.product.purchasePrice.toString());
    _stockCtrl = TextEditingController(text: widget.product.stock.toString());
    _selectedCategory = widget.product.category;
    _loadBarcodes();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    _sizeCtrl.dispose();
    _priceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await DatabaseHelper.instance.getAllCategories();
    if (mounted) setState(() => _categories = categories);
  }

  Future<void> _loadBarcodes() async {
    final list = await DatabaseHelper.instance.getBarcodesForProduct(widget.product.id!);
    if (mounted) setState(() { _barcodes = List<Map<String, dynamic>>.from(list); _barcodesLoading = false; });
  }

  // تنظيف مدخلات الماسح الضوئي من الرموز الزائدة
  String _cleanBarcode(String raw) {
    return raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  }

  Future<void> _addBarcode() async {
    final ctrl = TextEditingController();
    final rawBarcode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة باركود', style: TextStyle(color: AppTheme.primaryColor)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'امسح أو أدخل الباركود',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.qr_code),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    final barcode = rawBarcode != null ? _cleanBarcode(rawBarcode) : null;
    if (barcode == null || barcode.isEmpty) return;
    final exists = await DatabaseHelper.instance.barcodeExists(barcode);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا الباركود مستخدم مسبقاً!'), backgroundColor: AppTheme.errorColor),
        );
      }
      return;
    }
    final result = await DatabaseHelper.instance.addBarcode(widget.product.id!, barcode);
    if (result != -1) { await _loadBarcodes(); }
  }

  Future<void> _editBarcode(Map<String, dynamic> entry) async {
    final ctrl = TextEditingController(text: entry['barcode'] as String);
    final rawBarcode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الباركود', style: TextStyle(color: AppTheme.primaryColor)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.qr_code),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    final newBarcode = rawBarcode != null ? _cleanBarcode(rawBarcode) : null;
    if (newBarcode == null || newBarcode.isEmpty || newBarcode == entry['barcode']) { return; }
    final exists = await DatabaseHelper.instance.barcodeExists(newBarcode);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا الباركود مستخدم مسبقاً!'), backgroundColor: AppTheme.errorColor),
        );
      }
      return;
    }
    await DatabaseHelper.instance.updateBarcode(entry['id'] as int, newBarcode);
    await _loadBarcodes();
  }

  Future<void> _deleteBarcode(Map<String, dynamic> entry) async {
    if (_barcodes.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب أن يبقى باركود واحد على الأقل!'), backgroundColor: AppTheme.errorColor),
      );
      return;
    }
    await DatabaseHelper.instance.removeBarcode(entry['id'] as int);
    await _loadBarcodes();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'تعديل: ${widget.product.name}',
        style: const TextStyle(color: AppTheme.primaryColor, fontSize: 16),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              // قائمة منسدلة للقسم
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()),
                items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _colorCtrl, decoration: const InputDecoration(labelText: 'اللون', border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _sizeCtrl, decoration: const InputDecoration(labelText: 'القياس', border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: _purchasePriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'سعر الشراء', border: OutlineInputBorder()),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'سعر البيع', border: OutlineInputBorder()),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _stockCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'الكمية الإجمالية',
                  border: const OutlineInputBorder(),
                  helperText: 'الكمية الحالية: ${widget.product.stock}',
                ),
              ),
              const SizedBox(height: 16),
              // ── قسم الباركودات ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الباركودات',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 14),
                        ),
                        TextButton.icon(
                          onPressed: _addBarcode,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('إضافة'),
                          style: TextButton.styleFrom(foregroundColor: AppTheme.successColor),
                        ),
                      ],
                    ),
                    if (_barcodesLoading)
                      const Center(
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    else if (_barcodes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('لا توجد باركودات', style: TextStyle(color: AppTheme.neutralColor)),
                      )
                    else
                      ..._barcodes.map((b) => Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.neutralLightColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.qr_code_2, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                b['barcode'] as String,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.print, size: 18, color: AppTheme.successColor),
                              onPressed: () => BarcodePrinterWidget.show(context, barcode: b['barcode'] as String, productName: widget.product.name, price: widget.product.price),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'طباعة',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryColor),
                              onPressed: () => _editBarcode(b),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'تعديل',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                              onPressed: () => _deleteBarcode(b),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
          onPressed: () async {
            // ─── تحقق صريح — لا تحويلات صامتة ───
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اسم المنتج مطلوب'), backgroundColor: AppTheme.errorColor),
              );
              return;
            }
            final price = int.tryParse(_priceCtrl.text.trim());
            final purchase = int.tryParse(_purchasePriceCtrl.text.trim());
            final stock = int.tryParse(_stockCtrl.text.trim());
            String? error;
            if (price == null || price <= 0) {
              error = 'سعر البيع يجب أن يكون رقماً أكبر من صفر';
            } else if (purchase == null || purchase < 0) {
              error = 'سعر الشراء غير صالح';
            } else if (stock == null || stock < 0) {
              error = 'المخزون يجب أن يكون رقماً غير سالب';
            } else if (price < purchase) {
              error = 'سعر البيع أقل من سعر الشراء!';
            }
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error), backgroundColor: AppTheme.errorColor),
              );
              return;
            }

            final updated = widget.product.copyWith(
              name: name,
              category: _selectedCategory ?? widget.product.category,
              color: _colorCtrl.text.trim(),
              size: _sizeCtrl.text.trim(),
              price: price,
              purchasePrice: purchase,
              stock: stock,
            );
            final rows = await DatabaseHelper.instance.updateProduct(updated);
            if (!context.mounted) return;
            if (rows > 0) {
              Navigator.pop(context);
              widget.onSaved();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('فشل حفظ التعديلات'), backgroundColor: AppTheme.errorColor),
              );
            }
          },
          child: const Text('حفظ التعديلات'),
        ),
      ],
    );
  }
}
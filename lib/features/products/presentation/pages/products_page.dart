import 'package:flutter/material.dart';
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

class _ProductsPageState extends State<ProductsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    DatabaseHelper.productsRevision.addListener(_loadAllProducts);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _barcodeFocusNode.requestFocus();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    DatabaseHelper.productsRevision.removeListener(_loadAllProducts);
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
    final products = await DatabaseHelper.instance.getAllProducts();
    if (mounted) {
      setState(() {
        _allProducts = products;
        _isLoadingProducts = false;
      });
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
        _loadAllProducts();
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "${product.name}"؟\nالباركود: ${product.barcode}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseHelper.instance.deleteProduct(product.id!);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadAllProducts();
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
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
  Future<void> _showGlobalAdjustmentHistory() async {
    final adjustments = await DatabaseHelper.instance.getAllAdjustments();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            const Center(child: Text('سجل التعديلات العالمي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor))),
            const SizedBox(height: 12),
            if (adjustments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('لا توجد تعديلات مسجلة', style: TextStyle(color: AppTheme.textSecondary))),
              )
            else
              ...adjustments.map((a) {
                final diff = a['difference'] as int? ?? 0;
                final productName = a['product_name'] as String? ?? 'منتج محذوف';
                return ListTile(
                  leading: Icon(
                    diff > 0 ? Icons.add_circle : Icons.remove_circle,
                    color: diff > 0 ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                  title: Text(productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    '${a['old_stock']} ← ${a['new_stock']} (${a['reason']})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    (a['created_at'] as String).substring(0, 16).replaceAll('T', ' '),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المنتجات'),
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
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAddProductTab(),
          _buildProductsListTab(),
        ],
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
    // بحث ذكي بالاسم واللون والقياس
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
          return words.every((word) =>
            name.contains(word) ||
            color.contains(word) ||
            size.contains(word) ||
            barcode.contains(word)
          );
        }).toList();
      }
    }

    return Column(
      children: [
        // حقل البحث الذكي
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filteredProducts.length} منتج في المخزن',
                  style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.history, color: AppTheme.warningColor),
                    onPressed: _showGlobalAdjustmentHistory,
                    tooltip: 'سجل التعديلات العالمي',
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
                    onPressed: _loadAllProducts,
                    tooltip: 'تحديث',
                  ),
                ],
              ),
            ],
          ),
        ),
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
                      controller: _listScrollController,
                      itemExtent: 96.0,
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final p = filteredProducts[index];
                        final profit = p.price - p.purchasePrice;
                        final isHighlighted = _highlightedProductIndex == index;
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          color: isHighlighted ? AppTheme.highlightColor : null,
                          elevation: isHighlighted ? 4 : 1,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: p.stock > 0 ? AppTheme.primaryColor : AppTheme.errorColor,
                              child: Text('${p.stock}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                            trailing: Row(
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
                          ),
                        );
                      },
                     ),
        ),
      ],
    );
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
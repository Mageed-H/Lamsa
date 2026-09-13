import 'package:flutter/material.dart';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:cashier_system/features/products/data/models/product_model.dart';
import 'package:cashier_system/core/services/error_logger.dart';

class PosPage extends StatefulWidget {
  const PosPage({Key? key}) : super(key: key);

  /// تحديث حالة ظهور الصفحة — يُستدعى من MainLayout عند تبديل التبويب
  static void setPageVisible(bool visible) {
    _PosPageState.instance?.setPageVisible(visible);
  }

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  // static instance للوصول من مستمع دورة الحياة
  static _PosPageState? instance;

  // هل الصفحة ظاهرة حالياً؟ (يُحدّث من MainLayout عند تبديل التبويب)
  bool _isPageVisible = true;

  // للتحكم بحقل الباركود وبقاء التركيز (Focus) عليه دائماً
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  // سلة المشتريات (الفاتورة الحالية): نحفظ بيها المنتج والكمية
  final List<Map<String, dynamic>> _cart = [];
  bool _hasSuspendedOrders = false;
  // منتجات المخزون المنخفض
  List<ProductModel> _lowStockProducts = [];
  // قائمة جميع المنتجات (للبحث)
  List<ProductModel> _allProducts = [];
  // الخصم
  int _discountAmount = 0;
  bool _isDiscountPercent = false;
  // آخر فاتورة (لإعادة الطباعة)
  List<Map<String, dynamic>>? _lastPrintCart;
  int _lastPrintSubtotal = 0;
  int _lastPrintDiscount = 0;
  int _lastPrintTotal = 0;
  int _lastPrintGiven = 0;
  int _lastPrintChange = 0;
  int? _lastPrintSaleId;
  String? _lastPrintCustomerName;
  // تصفية المنتجات
  String? _posSelectedCategory;
  // بحث بالاسم/اللون/القياس
  String _posSearchQuery = '';
  // معرّف المسودة التلقائية الحالية
  int? _autoDraftOrderId;

  @override
  void initState() {
    super.initState();
    instance = this;
    DatabaseHelper.productsRevision.addListener(_loadAllProducts);
    // مستمع يرجع التركيز تلقائياً لحقل الباركود كل ما يضيع
    _barcodeFocusNode.addListener(_autoRefocus);
    // مراقب دورة حياة التطبيق — يحفظ السلة تلقائياً عند الخروج
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    // أول ما تفتح الشاشة، نخلي التركيز تلقائياً على حقل الباركود
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
      _checkSuspendedOrders();
      _loadAllProducts();
      _restoreAutoDraft();
    });
  }

  @override
  void dispose() {
    instance = null;
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    DatabaseHelper.productsRevision.removeListener(_loadAllProducts);
    _barcodeFocusNode.removeListener(_autoRefocus);
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  // مراقب دورة حياة التطبيق — يحفظ السلة عند الخروج للخلفية
  final _lifecycleObserver = _PosLifecycleObserver();

  // تنظيف مدخلات الماسح الضوئي من الرموز الزائدة (مثل {#\ اللي تطلع من تبديل أنماط Code128)
  String _cleanBarcode(String raw) {
    return raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  }

  // الدالة السحرية اللي تشتغل من نضرب الباركود بالجهاز
  Future<void> _onBarcodeScanned(String barcode) async {
    try {
    final cleanBarcode = _cleanBarcode(barcode);
    if (cleanBarcode.isEmpty) {
      _keepFocus();
      return;
    }

    // نبحث عن المنتج بقاعدة البيانات المحلية (بسرعة البرق)
    final product = await DatabaseHelper.instance.getProductByBarcode(
      cleanBarcode,
    );

    if (product != null) {
      // فحص المخزون قبل الإضافة
      final int currentInCart = _cart
          .where((i) => (i['product'] as ProductModel).id == product.id)
          .fold<int>(0, (s, i) => s + (i['quantity'] as int));
      if (currentInCart >= product.stock) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا يمكن إضافة المزيد! المخزون من “${product.name}” = ${product.stock} قطعة',
              ),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        _barcodeController.clear();
        _keepFocus();
        return;
      }
      setState(() {
        // إذا المنتج موجود مسبقاً بالفاتورة، نزيد الكمية فقط
        int index = _cart.indexWhere(
          (item) => (item['product'] as ProductModel).id == product.id,
        );
        if (index >= 0) {
          _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + 1;
        } else {
          // إذا منتج جديد، نضيفه للفاتورة بكمية 1
          _cart.add({'product': product, 'quantity': 1});
        }
        _posSearchQuery = '';
      });

      // فحص المخزون وتنبيه إذا كان قليلاً
      final thresholdStr = await DatabaseHelper.instance.getSetting(
        'low_stock_threshold',
        defaultValue: '5',
      );
      final threshold = int.tryParse(thresholdStr) ?? 5;
      final totalInCart = _cart
          .where((i) => (i['product'] as ProductModel).id == product.id)
          .fold<int>(0, (s, i) => s + (i['quantity'] as int));
      final remaining = product.stock - totalInCart;
      if (remaining <= threshold && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remaining <= 0
                  ? '⚠️ تحذير: مخزون "${product.name}" نفد بالكامل!'
                  : '⚠️ تنبيه: المخزون المتبقي من "${product.name}" = $remaining قطعة فقط!',
            ),
            backgroundColor: remaining <= 0
                ? AppTheme.errorColor
                : AppTheme.warningColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      // تطبيق Robustness: إذا الباركود غلط، ننبه الكاشير بدون ما يكرش النظام
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'المنتج غير موجود في قاعدة البيانات!',
              style: TextStyle(fontFamily: 'Tahoma'),
            ),
            backgroundColor: AppTheme.errorColor,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    // نفرغ الحقل ونرجع التركيز عليه استعداداً للقطعة اللي بعدها
    _barcodeController.clear();
    _keepFocus();
    } catch (e, st) {
      await ErrorLogger.instance.logError(e, st, context: 'مسح باركود');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في المسح: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
      _barcodeController.clear();
      _keepFocus();
    }
  }

  // دالة مساعدة للحفاظ على التركيز
  void _keepFocus() {
    if (!_isPageVisible || !mounted) return;
    FocusScope.of(context).requestFocus(_barcodeFocusNode);
  }

  // تحديث حالة الظهور — يُستدعى من MainLayout عند تبديل التبويب
  void setPageVisible(bool visible) {
    _isPageVisible = visible;
    if (!visible && mounted) {
      // لما الصفحة تختفي، نزيل المؤشر من حقل الباركود
      _barcodeFocusNode.unfocus();
    }
  }

  // حفظ السلة تلقائياً عند الخروج للخلفية
  void _saveAutoDraft() {
    if (_cart.isNotEmpty) {
      DatabaseHelper.instance.saveAutoDraft(
        _cart,
        discountAmount: _discountAmount,
        isDiscountPercent: _isDiscountPercent,
      );
    }
  }

  // استرجاع المسودة التلقائية عند بدء التطبيق
  Future<void> _restoreAutoDraft() async {
    final draft = await DatabaseHelper.instance.loadAutoDraft();
    if (draft == null || !mounted) return;
    final cart = draft['cart'] as List<Map<String, dynamic>>;
    if (cart.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع السلة', style: TextStyle(color: AppTheme.primaryColor)),
        content: Text('وجدنا سلة محفوظة من آخر مرة (${cart.length} صنف).\nهل تريد استرجاعها؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، استرجاع'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _cart.addAll(cart);
        _discountAmount = draft['discount_amount'] as int? ?? 0;
        _isDiscountPercent = draft['is_discount_percent'] as bool? ?? false;
      });
      _autoDraftOrderId = draft['order_id'] as int?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استرجاع السلة (${cart.length} صنف)'), backgroundColor: AppTheme.successColor),
      );
    } else {
      // حذف المسودة إذا المستخدم رفض الاسترجاع
      final orderId = draft['order_id'] as int?;
      if (orderId != null) {
        await DatabaseHelper.instance.clearAutoDraft(orderId);
      }
    }
  }

  // إضافة منتج مباشرة من الكروت (بدون باركود)
  void _addProductToCart(ProductModel product) {
    final int currentInCart = _cart
        .where((i) => (i['product'] as ProductModel).id == product.id)
        .fold<int>(0, (s, i) => s + (i['quantity'] as int));
    if (currentInCart >= product.stock) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لا يمكن إضافة المزيد! المخزون من "${product.name}" = ${product.stock} قطعة'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    setState(() {
      int index = _cart.indexWhere((item) => (item['product'] as ProductModel).id == product.id);
      if (index >= 0) {
        _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + 1;
      } else {
        _cart.add({'product': product, 'quantity': 1});
      }
    });
  }

  List<ProductModel> get _filteredPosProducts {
    var list = _allProducts;

    // فلترة حسب القسم المحدد
    if (_posSelectedCategory != null && _posSelectedCategory!.isNotEmpty) {
      list = list.where((p) => p.category == _posSelectedCategory).toList();
    }

    // فلترة ذكية بالاسم/اللون/القياس
    if (_posSearchQuery.isNotEmpty) {
      final query = _posSearchQuery.toLowerCase();
      final words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty) {
        list = list.where((p) {
          final name = p.name.toLowerCase();
          final color = p.color.toLowerCase();
          final size = p.size.toLowerCase();
          return words.every((word) =>
            name.contains(word) ||
            color.contains(word) ||
            size.contains(word)
          );
        }).toList();
      }
    }

    return list;
  }

  // يرجع التركيز تلقائياً لحقل الباركود بعد كل فريم إذا ضاع
  // لكن فقط إذا الصفحة هي الـ route النشط (ما يسرق الفوكس من الحوارات)
  void _autoRefocus() {
    if (!_isPageVisible || !_barcodeFocusNode.hasFocus || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isPageVisible && !_barcodeFocusNode.hasFocus) {
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent) {
          _barcodeFocusNode.requestFocus();
        }
      }
    });
  }

  Future<void> _checkSuspendedOrders() async {
    final orders = await DatabaseHelper.instance.getSuspendedOrders();
    if (mounted) setState(() => _hasSuspendedOrders = orders.isNotEmpty);
  }

  // تعليق الفاتورة وحفظها في القاعدة
  Future<void> _suspendOrder() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الفاتورة فارغة، لا يوجد ما يُعلّق!')),
      );
      return;
    }
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تعليق الفاتورة',
          style: TextStyle(color: AppTheme.warningColor),
        ),
        content: TextField(
          controller: noteController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ملاحظة اختيارية (مثال: زبونة بالباب)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تعليق'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final orderId = await DatabaseHelper.instance.saveSuspendedOrder(
        _cart,
        noteController.text,
        discountAmount: _discountAmount,
        isDiscountPercent: _isDiscountPercent,
      );
      // فشل الحفظ: السلة تبقى كما هي — الكاشير لا يخسر شيئاً
      if (orderId <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل تعليق الفاتورة! السلة محفوظة — حاول مجدداً'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        _keepFocus();
        return;
      }
      setState(() {
        _cart.clear();
        _discountAmount = 0;
        _isDiscountPercent = false;
        _hasSuspendedOrders = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعليق الفاتورة بنجاح ✓'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      _keepFocus();
    }
  }

  // تقليل كمية منتج في السلة (أو حذفه إذا وصل لـ 0)
  void _decreaseQty(int index) {
    setState(() {
      if ((_cart[index]['quantity'] as int) > 1) {
        _cart[index]['quantity'] = (_cart[index]['quantity'] as int) - 1;
      } else {
        _cart.removeAt(index);
      }
    });
    _keepFocus();
  }

  // زيادة كمية منتج في السلة
  void _increaseQty(int index) {
    final product = _cart[index]['product'] as ProductModel;
    final qty = _cart[index]['quantity'] as int;
    if (qty >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن إضافة المزيد! المخزون من “${product.name}” = ${product.stock} قطعة',
          ),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 2),
        ),
      );
      _keepFocus();
      return;
    }
    setState(() {
      _cart[index]['quantity'] = qty + 1;
    });
    _keepFocus();
  }

  // تعديل سعر منتج في السلة
  void _editItemPrice(int index) {
    final item = _cart[index];
    final product = item['product'] as ProductModel;
    final currentPrice = (item['custom_price'] as int?) ?? product.price;
    final priceCtrl = TextEditingController(text: '$currentPrice');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعديل سعر — ${product.name}', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('السعر الأصلي: ${product.price} دينار', style: const TextStyle(color: AppTheme.textSecondary)),
            Text('سعر الشراء: ${product.purchasePrice} دينار (الحد الأدنى)', style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'السعر الجديد',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _cart[index].remove('custom_price'));
              Navigator.pop(ctx);
            },
            child: const Text('إعادة الأصلي', style: TextStyle(color: AppTheme.errorColor)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              final newPrice = int.tryParse(priceCtrl.text.trim());
              if (newPrice == null || newPrice <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('أدخل سعراً صحيحاً'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              if (newPrice < product.purchasePrice) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('السعر لا يمكن أن يقل عن سعر الشراء (${product.purchasePrice} دينار)'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
                return;
              }
              setState(() => _cart[index]['custom_price'] = newPrice);
              Navigator.pop(ctx);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    ).then((_) => _keepFocus());
  }

  void _editItemDiscount(int index) {
    final item = _cart[index];
    final product = item['product'] as ProductModel;
    final currentPrice = (item['custom_price'] as int?) ?? product.price;
    final currentDiscount = (item['item_discount'] as int?) ?? 0;
    final discountCtrl = TextEditingController(text: currentDiscount > 0 ? '$currentDiscount' : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('خصم على — ${product.name}', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('السعر: $currentPrice دينار', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: discountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'مبلغ الخصم (دينار)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.discount),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _cart[index].remove('item_discount'));
              Navigator.pop(ctx);
            },
            child: const Text('إزالة الخصم', style: TextStyle(color: AppTheme.errorColor)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              final discount = int.tryParse(discountCtrl.text.trim()) ?? 0;
              if (discount < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('الخصم لا يمكن أن يكون سالباً'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              if (discount >= currentPrice) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('الخصم لا يمكن أن يساوي أو يتجاوز السعر'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              setState(() {
                if (discount > 0) {
                  _cart[index]['item_discount'] = discount;
                } else {
                  _cart[index].remove('item_discount');
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    ).then((_) => _keepFocus());
  }

  // حوار بيع بالدين: اختيار عميل + إنشاء الدين
  Future<void> _showDebtSaleDialog() async {
    if (_cart.isEmpty) return;

    final int total = _finalTotal;
    final int discountVal = _discountValue;
    final customers = await DatabaseHelper.instance.getDebtCustomers();
    String searchQuery = '';
    String? selectedCustomer;
    String? selectedPhone;
    final newCustomerController = TextEditingController();
    final newPhoneController = TextEditingController();
    bool useNewCustomer = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredCustomers = customers.where((c) {
            if (searchQuery.isEmpty) return true;
            final name = (c['customer_name'] as String).toLowerCase();
            final phone = (c['phone'] as String?)?.toLowerCase() ?? '';
            return name.contains(searchQuery.toLowerCase()) || phone.contains(searchQuery.toLowerCase());
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.person_add_outlined, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('بيع بالدين', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // المبلغ
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المبلغ المستحق:', style: TextStyle(fontSize: 14)),
                        Text('$total دينار', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // التبديل بين عميل موجود / عميل جديد
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('عميل موجود', style: TextStyle(fontSize: 12)),
                        selected: !useNewCustomer,
                        onSelected: (_) => setDialogState(() => useNewCustomer = false),
                        selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('عميل جديد', style: TextStyle(fontSize: 12)),
                        selected: useNewCustomer,
                        onSelected: (_) => setDialogState(() => useNewCustomer = true),
                        selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!useNewCustomer) ...[
                    // بحث
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو رقم الهاتف...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setDialogState(() => searchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    // قائمة العملاء
                    if (filteredCustomers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('لا يوجد عملاء', style: TextStyle(color: AppTheme.textSecondary))),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredCustomers.length,
                          itemBuilder: (ctx, i) {
                            final c = filteredCustomers[i];
                            final name = c['customer_name'] as String;
                            final phone = (c['phone'] as String?) ?? '';
                            final remaining = c['remaining'] as int;
                            final isSelected = selectedCustomer == name;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: AppTheme.primaryColor.withOpacity(0.1),
                              leading: CircleAvatar(
                                backgroundColor: isSelected ? AppTheme.primaryColor : AppTheme.neutralLightColor,
                                child: Text(name[0], style: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(phone.isNotEmpty ? phone : 'بدون هاتف', style: const TextStyle(fontSize: 11)),
                              trailing: Text('$remaining د', style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              onTap: () => setDialogState(() {
                                selectedCustomer = name;
                                selectedPhone = phone;
                              }),
                            );
                          },
                        ),
                      ),
                  ] else ...[
                    // عميل جديد
                    TextField(
                      controller: newCustomerController,
                      decoration: InputDecoration(
                        labelText: 'اسم العميل *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPhoneController,
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف (اختياري)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('تأكيد البيع بالدين'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  if (useNewCustomer) {
                    if (newCustomerController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('أدخل اسم العميل'), backgroundColor: AppTheme.errorColor),
                      );
                      return;
                    }
                    selectedCustomer = newCustomerController.text.trim();
                    selectedPhone = newPhoneController.text.trim();
                  }
                  if (selectedCustomer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اختر عميل أو أدخل اسم جديد'), backgroundColor: AppTheme.errorColor),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) {
      newCustomerController.dispose();
      newPhoneController.dispose();
      _keepFocus();
      return;
  }

    // تنفيذ البيع بالدين
    try {
      final cartSnapshot = List<Map<String, dynamic>>.from(_cart);
      final saleId = await DatabaseHelper.instance.completeSale(_cart, discountValue: discountVal);

      if (saleId > 0) {
        // إنشاء الدين مرتبط بالفاتورة
        await DatabaseHelper.instance.insertDebt(
          customerName: selectedCustomer!,
          phone: selectedPhone?.isNotEmpty == true ? selectedPhone : null,
          amount: total,
          note: 'فاتورة #$saleId',
          saleId: saleId,
        );

        if (mounted) {
          _lastPrintCart = cartSnapshot;
          _lastPrintSubtotal = _subtotal;
          _lastPrintDiscount = _discountValue;
          _lastPrintTotal = total;
          _lastPrintGiven = 0;
          _lastPrintChange = 0;
          _lastPrintSaleId = saleId;
          _lastPrintCustomerName = selectedCustomer;
          setState(() {
            _cart.clear();
            _discountAmount = 0;
            _isDiscountPercent = false;
          });

          // طباعة الفاتورة
          try {
            await _printInvoice(cartSnapshot, _subtotal, _discountValue, total, 0, 0, saleId: saleId, customerName: selectedCustomer);
          } catch (e, st) {
            await ErrorLogger.instance.logError(e, st, context: 'طباعة فاتورة دين');
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم البيع بالدين ✓ | العميل: $selectedCustomer | المبلغ: $total د'),
              backgroundColor: AppTheme.primaryColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء إتمام البيع!'), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (e, st) {
      await ErrorLogger.instance.logError(e, st, context: 'بيع بالدين');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
    newCustomerController.dispose();
    newPhoneController.dispose();
    _keepFocus();
  }

  // حوار الدفع: حساب الفكة + اختيار الطباعة
  Future<void> _showPaymentDialog() async {
    if (_cart.isEmpty) return;

    final int subtotal = _subtotal;
    final int discountVal = _discountValue;
    final int total = _finalTotal;
    final amountController = TextEditingController(text: '$total');
    bool shouldPrint = true;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final given = int.tryParse(amountController.text) ?? 0;
          final change = (given - total).clamp(0, 9999999);
          final canConfirm = given >= total;

          return AlertDialog(
            title: const Text(
              'إتمام الدفع',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // عرض الخصم إذا كان موجوداً
                if (discountVal > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$subtotal دينار',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const Text(
                        'قبل الخصم:',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '- $discountVal دينار',
                        style: const TextStyle(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'الخصم:',
                        style: TextStyle(color: AppTheme.errorColor),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                ],
                // المجموع الكلي
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإجمالي:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$total دينار',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // حقل المبلغ المعطى
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المعطى',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                // الباقي (الفكة)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: canConfirm
                        ? AppTheme.successColor.withValues(alpha: 0.12)
                        : AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: canConfirm
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الباقي (الفكة):',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        canConfirm ? '$change دينار' : 'المبلغ غير كافٍ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: canConfirm
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // خيار الطباعة
                GestureDetector(
                  onTap: () => setDialogState(() => shouldPrint = !shouldPrint),
                  child: Row(
                    children: [
                      Checkbox(
                        value: shouldPrint,
                        onChanged: (v) =>
                            setDialogState(() => shouldPrint = v ?? true),
                        activeColor: AppTheme.primaryColor,
                      ),
                      const Icon(
                        Icons.receipt_long,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'طباعة فاتورة',
                        style: TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canConfirm
                      ? AppTheme.successColor
                      : AppTheme.neutralColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  'تأكيد الدفع',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      amountController.dispose();
      _keepFocus();
      return;
    }

    final int given = int.tryParse(amountController.text) ?? total;
    final int changeAmount = (given - total).clamp(0, 9999999);
    amountController.dispose();

    try {
      final cartSnapshot = List<Map<String, dynamic>>.from(_cart);
      final saleId = await DatabaseHelper.instance.completeSale(
        _cart,
        discountValue: discountVal,
      );

      if (saleId > 0 && mounted) {
        _lastPrintCart = cartSnapshot;
        _lastPrintSubtotal = subtotal;
        _lastPrintDiscount = discountVal;
        _lastPrintTotal = total;
        _lastPrintGiven = given;
        _lastPrintChange = changeAmount;
        _lastPrintSaleId = saleId;
        setState(() {
          _cart.clear();
          _discountAmount = 0;
          _isDiscountPercent = false;
        });

        // مسح المسودة التلقائية بعد البيع الناجح
        if (_autoDraftOrderId != null) {
          await DatabaseHelper.instance.clearAutoDraft(_autoDraftOrderId!);
          _autoDraftOrderId = null;
        }

        // الطباعة منفصلة عن البيع — فشلها لا يعني فشل البيع
        var printFailed = false;
        if (shouldPrint) {
          try {
            await _printInvoice(cartSnapshot, subtotal, discountVal, total, given, changeAmount, saleId: saleId);
          } catch (e, st) {
            printFailed = true;
            await ErrorLogger.instance.logError(e, st, context: 'طباعة بعد بيع ناجح');
          }
        }

        if (mounted) {
          final remainingStock = cartSnapshot.map((i) {
            final p = i['product'] as ProductModel;
            final qty = i['quantity'] as int;
            return '${p.name} (${p.stock - qty})';
          }).join('  |  ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تم البيع بنجاح ✓${changeAmount > 0 ? '  |  الباقي: $changeAmount د' : ''}'),
                  const SizedBox(height: 4),
                  Text('المتبقي: $remainingStock', style: const TextStyle(fontSize: 12)),
                  if (printFailed) ...[
                    const SizedBox(height: 4),
                    const Text('⚠️ فشلت الطباعة — البيانات محفوظة، أعد الطباعة من الزر العلوي',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
              backgroundColor: printFailed ? AppTheme.warningColor : AppTheme.successColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء إتمام البيع!'), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (e, st) {
      await ErrorLogger.instance.logError(e, st, context: 'إتمام البيع - _showPaymentDialog');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ حادث: $e'), backgroundColor: AppTheme.errorColor, duration: const Duration(seconds: 5)),
        );
      }
    }
    _keepFocus();
  }

  // طباعة فاتورة البيع — وصل بتصميم جديد ٤ أعمدة
  Future<void> _printInvoice(
    List<Map<String, dynamic>> cart,
    int subtotal,
    int discountValue,
    int finalTotal,
    int given,
    int change,
    {int? saleId, String? customerName}
  ) async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    final storeName = settings['store_name'] ?? 'أحلى الحلوين';
    final storePhone = settings['store_phone'] ?? '';
    final currency = settings['currency'] ?? 'دينار';
    final footer = settings['receipt_footer'] ?? 'شكراً لزيارتكم';
    final qrSvgCache = settings['qr_svg_cache'] ?? '';
    final titleFs =
        double.tryParse(settings['receipt_title_font_size'] ?? '14') ?? 14.0;
    final bodyFs =
        double.tryParse(settings['receipt_body_font_size'] ?? '9') ?? 9.0;
    final paperW =
        double.tryParse(settings['receipt_paper_width_mm'] ?? '78') ?? 78.0;
    final marginTop =
        double.tryParse(
          settings['receipt_margin_top_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final marginBottom =
        double.tryParse(
          settings['receipt_margin_bottom_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final marginLeft =
        double.tryParse(
          settings['receipt_margin_left_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final marginRight =
        double.tryParse(
          settings['receipt_margin_right_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final savedPrinterUrl =
        settings['receipt_printer_url'] ??
        settings['default_printer_url'] ??
        '';
    final savedPrinterName =
        settings['receipt_printer_name'] ??
        settings['default_printer_name'] ??
        '';

    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    final aroFont = pw.Font.ttf(fontData);

    final now = DateTime.now();
    final dtStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // عكس ترتيب المواد (الأحدث إضافةً يظهر أعلى)
    final reversed = cart.reversed.toList();
    final itemCount = cart.fold<int>(0, (s, i) => s + (i['quantity'] as int));

    // حساب ارتفاع الورقة تلقائياً بناءً على عدد المواد
    final rowH = bodyFs * 1.5 + 5.0;
    final phoneH = storePhone.isNotEmpty ? 8.0 : 0.0;
    final discountH = discountValue > 0 ? 16.0 : 0.0;
    final changeH = given > finalTotal ? 16.0 : 0.0;
    final qrH = qrSvgCache.isNotEmpty ? 24.0 : 0.0;
    final pageH =
        52.0 +
        phoneH +
        reversed.length * (rowH + 3.0) +
        discountH +
        changeH +
        qrH +
        46.0;

    final pageFormat = PdfPageFormat(
      paperW * PdfPageFormat.mm,
      pageH * PdfPageFormat.mm,
      marginTop: marginTop * PdfPageFormat.mm,
      marginBottom: marginBottom * PdfPageFormat.mm,
      marginLeft: marginLeft * PdfPageFormat.mm,
      marginRight: marginRight * PdfPageFormat.mm,
    );

    pw.TextStyle body() => pw.TextStyle(font: aroFont, fontSize: bodyFs);
    pw.TextStyle bodyBold() => pw.TextStyle(
      font: aroFont,
      fontSize: bodyFs,
      fontWeight: pw.FontWeight.bold,
    );
    pw.TextStyle titleSt() => pw.TextStyle(
      font: aroFont,
      fontSize: titleFs,
      fontWeight: pw.FontWeight.bold,
    );
    pw.TextStyle subTitleSt() =>
        pw.TextStyle(font: aroFont, fontSize: titleFs - 2);

    final solidDiv = pw.Divider(thickness: 0.5, color: PdfColors.black);
    // فاصل منقط يمتد على كامل عرض الفاتورة
    final dottedDiv = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: List.generate(
          80,
          (i) => pw.Expanded(
            child: pw.Container(
              height: 1,
              color: i.isEven ? PdfColors.black : PdfColors.white,
            ),
          ),
        ),
      ),
    );
    // فاصل رأسي رفيع بين الأعمدة
    // final vSep = pw.Container(width: 0.4, color: PdfColors.grey500);

    // بناء بنود الفاتورة
    final List<pw.Widget> itemWidgets = [];
    for (var i = 0; i < reversed.length; i++) {
      final item = reversed[i];
      final product = item['product'] as ProductModel;
      final qty = item['quantity'] as int;
      final itemPrice = (item['custom_price'] as int?) ?? product.price;
      final itemDiscount = (item['item_discount'] as int?) ?? 0;
      final effectivePrice = itemPrice - itemDiscount;
      final rowTotal = effectivePrice * qty;
      itemWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(
                  product.name,
                  style: body(),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
              // vSep,
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'x$qty',
                  style: body(),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              // vSep,
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  '$itemPrice',
                  style: body(),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              // vSep,
              pw.Expanded(
                flex: 3,
                child: pw.Text(
                  '$rowTotal',
                  style: bodyBold(),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],

          ),
        ),
      );
      if (i < reversed.length - 1) itemWidgets.add(dottedDiv);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(right: 4, left: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // اسم المحل
              pw.Text(
                storeName,
                style: titleSt(),
                textDirection: pw.TextDirection.rtl,
              ),
              if (storePhone.isNotEmpty)
                pw.Text(
                  storePhone,
                  style: subTitleSt(),
                  textDirection: pw.TextDirection.rtl,
                ),
              pw.SizedBox(height: 3),
              solidDiv,
              // التاريخ والوقت
              pw.Text(dtStr, style: body()),
              // رقم الوصل
              if (saleId != null) ...[
                pw.SizedBox(height: 2),
                pw.Text('رقم الوصل: R${saleId.toString().padLeft(6, '0')}', style: bodyBold(), textDirection: pw.TextDirection.rtl),
              ],
              // اسم العميل (إذا كان بيع بالدين)
              if (customerName != null && customerName.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.pink50,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text('العميل: $customerName', style: bodyBold(), textDirection: pw.TextDirection.rtl),
                ),
              ],
              solidDiv,
              pw.SizedBox(height: 2),
              // رأس الجدول (ترتيب RTL: اسم المادة | العدد | السعر | الإجمالي)
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      'اسم المادة',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'العدد',
                      style: bodyBold(),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'السعر',
                      style: bodyBold(),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'الإجمالي',
                      style: bodyBold(),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(
                height: 2,
                child: pw.Divider(thickness: 0.8, color: PdfColors.black),
              ),
              // بنود الفاتورة
              ...itemWidgets,
              solidDiv,
              pw.SizedBox(height: 2),
              // الخصم (إذا كان هناك خصم)
              if (discountValue > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('$subtotal $currency', style: body()),
                    pw.Text(
                      'المجموع:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '- $discountValue $currency',
                      style: pw.TextStyle(
                        font: aroFont,
                        fontSize: bodyFs,
                        color: PdfColors.red,
                      ),
                    ),
                    pw.Text(
                      'الخصم:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5),
              ],
              // الإجمالي النهائي
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('$finalTotal $currency', style: titleSt()),
                  pw.Text(
                    '${discountValue > 0 ? 'الصافي' : 'الإجمالي'} ($itemCount قطعة):',
                    style: subTitleSt(),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
              ),
              // المدفوع والباقي
              if (given > finalTotal) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('$given $currency', style: body()),
                    pw.Text(
                      'المدفوع:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '$change $currency',
                      style: pw.TextStyle(
                        font: aroFont,
                        fontSize: bodyFs + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'الباقي:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ],
              dottedDiv,
              pw.SizedBox(height: 4),
              if (qrSvgCache.isNotEmpty) ...[  
                pw.Center(
                  child: pw.SvgImage(svg: qrSvgCache, width: 60, height: 60),
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Text(
                footer,
                style: body(),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    if (savedPrinterUrl.isNotEmpty) {
      try {
        final ok = await Printing.directPrintPdf(
          printer: Printer(url: savedPrinterUrl, name: savedPrinterName),
          onLayout: (_) async => await Isolate.run(() => doc.save()),
        );
        if (ok) return;
      } catch (_) {}
    }
    await Printing.layoutPdf(onLayout: (_) async {
      return await Isolate.run(() => doc.save());
    });
  }

  // عرض المنتجات ذات المخزون المنخفض
  void _showLowStockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor),
            const SizedBox(width: 8),
            Text(
              'المخزون المنخفض (${_lowStockProducts.length})',
              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _lowStockProducts.isEmpty
              ? const Center(child: Text('لا توجد منتجات بمخزون منخفض ✓', style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold)))
              : ListView.separated(
                  itemCount: _lowStockProducts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final p = _lowStockProducts[index];
                    final isZero = p.stock <= 0;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isZero ? Icons.error : Icons.warning,
                        color: isZero ? AppTheme.errorColor : AppTheme.warningColor,
                      ),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${p.category} ${p.color.isNotEmpty ? '- ${p.color}' : ''} ${p.size.isNotEmpty ? '- ${p.size}' : ''}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isZero ? AppTheme.errorColor : AppTheme.warningColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${p.stock}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // عرض الفواتير المعلقة واستئنافها
  Future<void> _showSuspendedOrders() async {
    final orders = await DatabaseHelper.instance.getSuspendedOrders();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                'الفواتير المعلقة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            Expanded(
              child: orders.isEmpty
                  ? const Center(child: Text('لا توجد فواتير معلقة'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: orders.length,
                      itemBuilder: (_, i) {
                        final order = orders[i];
                        final orderId = order['id'] as int;
                        final note = order['note'] as String? ?? 'بدون ملاحظة';
                        final createdAt = (order['created_at'] as String)
                            .substring(0, 16)
                            .replaceAll('T', '  ');
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.pause_circle,
                              color: AppTheme.warningColor,
                              size: 32,
                            ),
                            title: Text(
                              note,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(createdAt),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    final result = await DatabaseHelper
                                        .instance
                                        .getSuspendedOrderCartWithWarning(orderId);
                                    final suspendedCart = result['cart'] as List<Map<String, dynamic>>;
                                    final missingCount = result['missing'] as int;
                                    final discountInfo = await DatabaseHelper
                                        .instance
                                        .getSuspendedOrderDiscount(orderId);

                                    // ─── السلة أولاً ثم الحذف ───
                                    // لو انقطع التطبيق بعد الإضافة وقبل الحذف:
                                    // الفاتورة تبقى معلقة (تكرار محتمل أفضل من ضياع)
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    setState(() {
                                      _cart.addAll(suspendedCart);
                                      _discountAmount =
                                          discountInfo['discount_amount'] ?? 0;
                                      _isDiscountPercent =
                                          (discountInfo['is_discount_percent'] ??
                                              0) ==
                                          1;
                                    });

                                    final deleted = await DatabaseHelper.instance
                                        .deleteSuspendedOrder(orderId);
                                    if (!deleted) {
                                      await ErrorLogger.instance.warning(
                                        'استؤنفت فاتورة لكن فشل حذفها المعلق — قد تتكرر',
                                        data: {'order_id': orderId},
                                      );
                                    }
                                    if (missingCount > 0 && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('تنبيه: $missingCount منتج محذوف تم تجاهله من الفاتورة المعلقة'),
                                          backgroundColor: AppTheme.warningColor,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                    _checkSuspendedOrders();
                                    _keepFocus();
                                  },
                                  child: const Text(
                                    'استئناف',
                                    style: TextStyle(
                                      color: AppTheme.successColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: AppTheme.errorColor,
                                  ),
                                  onPressed: () async {
                                    await DatabaseHelper.instance
                                        .deleteSuspendedOrder(orderId);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _checkSuspendedOrders();
                                    _showSuspendedOrders();
                                  },
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
      ),
    );
    _checkSuspendedOrders();
  }

  // سكانر الكاميرا (على الموبايل فقط)
  Future<void> _openCameraScanner() async {
    bool scanned = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('امسح الباركود'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              if (scanned) return;
              if (capture.barcodes.isNotEmpty) {
                final code = capture.barcodes.first.rawValue;
                if (code != null) {
                  scanned = true;
                  Navigator.pop(ctx);
                  _onBarcodeScanned(code);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // ─── تحميل جميع المنتجات ───
  Future<void> _loadAllProducts() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    final thresholdStr = await DatabaseHelper.instance.getSetting(
      'low_stock_threshold',
      defaultValue: '5',
    );
    final threshold = int.tryParse(thresholdStr) ?? 5;
    final lowStock = products.where((p) => p.stock <= threshold && p.stock >= 0).toList();
    if (mounted) {
      setState(() {
        _allProducts = products;
        _lowStockProducts = lowStock;
      });
    }
  }

  // ─── حوار الخصم ───
  Future<void> _showDiscountDialog() async {
    final ctrl = TextEditingController(
      text: _discountAmount > 0 ? '$_discountAmount' : '',
    );
    bool isPercent = _isDiscountPercent;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('خصم على الفاتورة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('مبلغ ثابت')),
                  ButtonSegment(value: true, label: Text('نسبة مئوية %')),
                ],
                selected: {isPercent},
                onSelectionChanged: (s) => setS(() => isPercent = s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: isPercent ? 'نسبة الخصم' : 'مبلغ الخصم',
                  border: const OutlineInputBorder(),
                  suffixText: isPercent ? '%' : 'دينار',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              onPressed: () {
                setState(() {
                  _discountAmount = 0;
                  _isDiscountPercent = false;
                });
                Navigator.pop(ctx);
              },
              child: const Text('إزالة الخصم'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final v = int.tryParse(ctrl.text) ?? 0;
                setState(() {
                  _discountAmount = v.clamp(0, isPercent ? 100 : _subtotal);
                  _isDiscountPercent = isPercent;
                });
                Navigator.pop(ctx);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    _keepFocus();
  }

  // ─── حوار البحث عن منتج ───
  Future<void> _showProductSearchDialog() async {
    final ctrl = TextEditingController();
    String query = '';
    // تحميل كل الباركودات لدعم البحث بالباركودات المتعددة
    final barcodeMap = await DatabaseHelper.instance.getAllBarcodesByProduct();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setS) {
          final filtered = query.isEmpty
              ? _allProducts
              : _allProducts.where((p) {
                  if (p.name.toLowerCase().contains(query.toLowerCase())) {
                    return true;
                  }
                  final barcodes = barcodeMap[p.id] ?? [];
                  return barcodes.any((bc) => bc.contains(query));
                }).toList();
          return AlertDialog(
            title: const Text('بحث عن منتج'),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              width: 440,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'ابحث بالاسم أو الباركود...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setS(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final inCart = _cart
                            .where(
                              (c) => (c['product'] as ProductModel).id == p.id,
                            )
                            .fold<int>(0, (s, c) => s + (c['quantity'] as int));
                        final remaining = p.stock - inCart;
                        return ListTile(
                          dense: true,
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${p.price} دينار — متبقي: $remaining',
                          ),
                          trailing: remaining > 0
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: AppTheme.successColor,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      final idx = _cart.indexWhere(
                                        (c) =>
                                            (c['product'] as ProductModel).id ==
                                            p.id,
                                      );
                                      if (idx >= 0) {
                                        _cart[idx]['quantity'] =
                                            (_cart[idx]['quantity'] as int) + 1;
                                      } else {
                                        _cart.add({
                                          'product': p,
                                          'quantity': 1,
                                        });
                                      }
                                    });
                                    setS(() {});
                                  },
                                )
                              : const Icon(
                                  Icons.remove_circle_outline,
                                  color: AppTheme.errorColor,
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    _keepFocus();
  }

  // ─── حساب الإجماليات ───
  int get _subtotal => _cart.fold(0, (s, i) {
    final p = i['product'] as ProductModel;
    final itemPrice = (i['custom_price'] as int?) ?? p.price;
    final itemDiscount = (i['item_discount'] as int?) ?? 0;
    return s + ((itemPrice - itemDiscount) * (i['quantity'] as int));
  });

  int get _discountValue {
    if (_discountAmount <= 0) return 0;
    if (_isDiscountPercent) return _subtotal * _discountAmount ~/ 100;
    return _discountAmount.clamp(0, _subtotal);
  }

  int get _finalTotal => _subtotal - _discountValue;

  @override
  Widget build(BuildContext context) {
    final categories = <String>['الكل'];
    for (final p in _allProducts) {
      if (!categories.contains(p.category)) categories.add(p.category);
    }
    final filteredProducts = _filteredPosProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'نقطة البيع (الكاشير)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_lastPrintCart != null)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: () async {
                try {
                  await _printInvoice(
                    _lastPrintCart!, _lastPrintSubtotal, _lastPrintDiscount,
                    _lastPrintTotal, _lastPrintGiven, _lastPrintChange,
                    saleId: _lastPrintSaleId, customerName: _lastPrintCustomerName,
                  );
                } catch (e, st) {
                  await ErrorLogger.instance.logError(e, st, context: 'إعادة طباعة آخر فاتورة');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('فشلت الطباعة — تأكد من الطابعة: $e'),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                  }
                }
              },
              tooltip: 'طباعة آخر فاتورة',
            ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.pause_circle_outline),
                if (_hasSuspendedOrders)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      width: 10, height: 10,
                      decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            onPressed: _showSuspendedOrders,
            tooltip: 'الفواتير المعلقة',
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.inventory_2_outlined),
                if (_lowStockProducts.isNotEmpty)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(color: AppTheme.warningColor, shape: BoxShape.circle),
                      child: Text(
                        '${_lowStockProducts.length}',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showLowStockDialog,
            tooltip: 'المخزون المنخفض',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showProductSearchDialog,
            tooltip: 'بحث عن منتج',
          ),
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: _openCameraScanner,
              tooltip: 'مسح بالكاميرا',
            ),
        ],
      ),
      body: Row(
          children: [
            // ── الجزء الأيسر: السلة + الدفع ──
            Expanded(
              flex: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _keepFocus,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(color: AppTheme.primaryColor.withOpacity(0.2), width: 1),
                    ),
                  ),
                  child: Column(
                    children: [
                    // حقل الباركود
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        controller: _barcodeController,
                        focusNode: _barcodeFocusNode,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'امسح الباركود...',
                          prefixIcon: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: AppTheme.surfaceColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (val) => setState(() => _posSearchQuery = val),
                        onSubmitted: _onBarcodeScanned,
                      ),
                    ),
                    // عنوان السلة
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_cart, size: 18, color: AppTheme.primaryColor),
                          const SizedBox(width: 6),
                          Text(
                            'الفاتورة (${_cart.length} صنف)',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                          ),
                          const Spacer(),
                          if (_cart.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _cart.clear();
                                  _discountAmount = 0;
                                  _isDiscountPercent = false;
                                });
                                // مسح المسودة التلقائية
                                if (_autoDraftOrderId != null) {
                                  DatabaseHelper.instance.clearAutoDraft(_autoDraftOrderId!);
                                  _autoDraftOrderId = null;
                                }
                              },
                              child: const Text('مسح الكل', style: TextStyle(color: AppTheme.errorColor, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    // قائمة المنتجات بالسلة
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(
                              child: Text(
                                'الفاتورة فارغة',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              itemCount: _cart.length,
                              itemBuilder: (context, index) {
                                final item = _cart[index];
                                final product = item['product'] as ProductModel;
                                final qty = item['quantity'] as int;
                                final itemPrice = (item['custom_price'] as int?) ?? product.price;
                                final itemDiscount = (item['item_discount'] as int?) ?? 0;
                                final effectivePrice = itemPrice - itemDiscount;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                product.name,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => _editItemPrice(index),
                                              child: Text(
                                                '$itemPrice د.ع',
                                                style: TextStyle(
                                                  color: (item['custom_price'] != null) ? AppTheme.warningColor : AppTheme.primaryColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  decoration: itemDiscount > 0 ? TextDecoration.lineThrough : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            _qtyBtn(Icons.remove_circle, AppTheme.warningColor, () => _decreaseQty(index)),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              child: Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                                            ),
                                            _qtyBtn(Icons.add_circle, AppTheme.successColor, () => _increaseQty(index)),
                                            const Spacer(),
                                            if (itemDiscount > 0)
                                              GestureDetector(
                                                onTap: () => _editItemDiscount(index),
                                                child: Text(
                                                  '$effectivePrice د.ع',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.successColor),
                                                ),
                                              ),
                                            if (itemDiscount > 0) const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () => _editItemDiscount(index),
                                              child: Icon(Icons.discount, size: 16, color: itemDiscount > 0 ? AppTheme.errorColor : AppTheme.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // لوحة الدفع السفلية
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -3)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_discountValue > 0) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$_discountValue د.ع خصم', style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('الصافي: $_finalTotal د.ع', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (_discountValue == 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('الإجمالي:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(
                                  '$_finalTotal د.ع',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _posActionBtn(Icons.discount_outlined, _discountValue > 0 ? AppTheme.errorColor : AppTheme.textSecondary, _showDiscountDialog),
                              const SizedBox(width: 4),
                              _posActionBtn(Icons.pause_circle_filled, AppTheme.warningColor, _suspendOrder),
                              const SizedBox(width: 4),
                              _posActionBtn(Icons.person_add_outlined, AppTheme.primaryColor, _showDebtSaleDialog),
                              const SizedBox(width: 4),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.successColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  icon: const Icon(Icons.point_of_sale, size: 18),
                                  label: const Text('دفع', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  onPressed: _cart.isEmpty ? null : _showPaymentDialog,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
            // ── الجزء الأيمن: المنتجات على شكل كروت ──
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // فلتر الأقسام
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: AppTheme.surfaceColor,
                    child: SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final cat = categories[i];
                          final selected = (i == 0 && _posSelectedCategory == null) || _posSelectedCategory == cat;
                          return ChoiceChip(
                            label: Text(cat, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textPrimary)),
                            selected: selected,
                            selectedColor: AppTheme.primaryColor,
                            backgroundColor: Colors.white,
                            onSelected: (_) {
                              setState(() {
                                _posSelectedCategory = (i == 0) ? null : cat;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  // شبكة المنتجات
                  Expanded(
                    child: filteredProducts.isEmpty
                        ? const Center(child: Text('لا توجد منتجات', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossCount = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 600 ? 3 : 2);
                              return GridView.builder(
                                padding: const EdgeInsets.all(10),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossCount,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 0.85,
                                ),
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final p = filteredProducts[index];
                                  final inCart = _cart
                                      .where((i) => (i['product'] as ProductModel).id == p.id)
                                      .fold<int>(0, (s, i) => s + (i['quantity'] as int));
                                  return GestureDetector(
                                    onTap: () => _addProductToCart(p),
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 56, height: 56,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                p.name.isNotEmpty ? p.name[0] : '?',
                                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              p.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (p.color.isNotEmpty || p.size.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                [if (p.color.isNotEmpty) p.color, if (p.size.isNotEmpty) p.size].join(' — '),
                                                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${p.price} د.ع',
                                            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'متوفر: ${p.stock}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: p.stock <= 0 ? AppTheme.errorColor : AppTheme.textSecondary,
                                            ),
                                          ),
                                          if (inCart > 0)
                                            Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'بالسلة: $inCart',
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

Widget _qtyBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _posActionBtn(IconData icon, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: c, size: 22),
      ),
    );
  }
}

// مستمع دورة حياة التطبيق — يحفظ السلة تلقائياً عند الخروج
class _PosLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند الخروج للخلفية أو إيقاف التطبيق، نحفظ السلة
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _PosPageState.instance?._saveAutoDraft();
    }
  }
}

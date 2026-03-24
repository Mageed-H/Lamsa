import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';
import 'package:lamsa/features/products/data/models/product_model.dart';

class PosPage extends StatefulWidget {
  const PosPage({Key? key}) : super(key: key);

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  // للتحكم بحقل الباركود وبقاء التركيز (Focus) عليه دائماً
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  // سلة المشتريات (الفاتورة الحالية): نحفظ بيها المنتج والكمية
  final List<Map<String, dynamic>> _cart = [];
  bool _hasSuspendedOrders = false;

  @override
  void initState() {
    super.initState();
    // أول ما تفتح الشاشة، نخلي التركيز تلقائياً على حقل الباركود
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
      _checkSuspendedOrders();
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  // الدالة السحرية اللي تشتغل من نضرب الباركود بالجهاز
  Future<void> _onBarcodeScanned(String barcode) async {
    if (barcode.trim().isEmpty) {
      _keepFocus();
      return;
    }

    // نبحث عن المنتج بقاعدة البيانات المحلية (بسرعة البرق)
    final product = await DatabaseHelper.instance.getProductByBarcode(barcode.trim());

    if (product != null) {
      setState(() {
        // إذا المنتج موجود مسبقاً بالفاتورة، نزيد الكمية فقط
        int index = _cart.indexWhere((item) => (item['product'] as ProductModel).id == product.id);
        if (index >= 0) {
          _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + 1;
        } else {
          // إذا منتج جديد، نضيفه للفاتورة بكمية 1
          _cart.add({'product': product, 'quantity': 1});
        }
      });
    } else {
      // تطبيق Robustness: إذا الباركود غلط، ننبه الكاشير بدون ما يكرش النظام
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المنتج غير موجود في قاعدة البيانات!', style: TextStyle(fontFamily: 'Tahoma')),
          backgroundColor: AppTheme.errorColor,
          duration: Duration(seconds: 2),
        ),
      );
    }

    // نفرغ الحقل ونرجع التركيز عليه استعداداً للقطعة اللي بعدها
    _barcodeController.clear();
    _keepFocus();
  }

  // دالة مساعدة للحفاظ على التركيز
  void _keepFocus() {
    FocusScope.of(context).requestFocus(_barcodeFocusNode);
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
        title: const Text('تعليق الفاتورة', style: TextStyle(color: AppTheme.warningColor)),
        content: TextField(
          controller: noteController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ملاحظة اختيارية (مثال: زبونة بالباب)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تعليق'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.saveSuspendedOrder(_cart, noteController.text);
      setState(() {
        _cart.clear();
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

  // عرض الفواتير المعلقة واستئنافها
  Future<void> _showSuspendedOrders() async {
    final orders = await DatabaseHelper.instance.getSuspendedOrders();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text('الفواتير المعلقة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
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
                        final createdAt = (order['created_at'] as String).substring(0, 16).replaceAll('T', '  ');
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.pause_circle, color: AppTheme.warningColor, size: 32),
                            title: Text(note, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(createdAt),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    final suspendedCart = await DatabaseHelper.instance.getSuspendedOrderCart(orderId);
                                    await DatabaseHelper.instance.deleteSuspendedOrder(orderId);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    setState(() => _cart.addAll(suspendedCart));
                                    _checkSuspendedOrders();
                                    _keepFocus();
                                  },
                                  child: const Text('استئناف', style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppTheme.errorColor),
                                  onPressed: () async {
                                    await DatabaseHelper.instance.deleteSuspendedOrder(orderId);
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
              if (capture.barcodes.isNotEmpty) {
                final code = capture.barcodes.first.rawValue;
                if (code != null) {
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

  // حساب المجموع الكلي الدقيق للفاتورة (Financial Precision)
  int get _totalAmount {
    return _cart.fold(0, (sum, item) {
      final product = item['product'] as ProductModel;
      final qty = item['quantity'] as int;
      return sum + (product.price * qty);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نقطة البيع (الكاشير)', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          // زر الفواتير المعلقة مع نقطة حمراء دليل
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.pause_circle_outline),
                if (_hasSuspendedOrders)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            onPressed: _showSuspendedOrders,
            tooltip: 'الفواتير المعلقة',
          ),
          // زر الكاميرا يظهر على الموبايل فقط
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: _openCameraScanner,
              tooltip: 'مسح بالكاميرا',
            ),
        ],
      ),
      // نستخدم GestureDetector حتى إذا الكاشير لمس الشاشة بالغلط، يرجع التركيز للباركود
      body: GestureDetector(
        onTap: _keepFocus,
        child: Column(
          children: [
            // 1. حقل قراءة الباركود (المستمع الدائم)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _barcodeController,
                focusNode: _barcodeFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'قم بمسح الباركود هنا...',
                  prefixIcon: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: AppTheme.surfaceColor,
                ),
                onSubmitted: _onBarcodeScanned, // يتنفذ تلقائياً من يخلص جهاز السكانر قراءة
              ),
            ),

            // 2. قائمة المنتجات في الفاتورة الحالية (سيتم نقلها لملف invoice_list_widget لاحقاً)
            Expanded(
              child: _cart.isEmpty
                  ? const Center(
                      child: Text('الفاتورة فارغة، قم بمسح منتج للبدء', style: TextStyle(color: AppTheme.textSecondary, fontSize: 18)),
                    )
                  : ListView.builder(
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        final product = item['product'] as ProductModel;
                        final qty = item['quantity'] as int;

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: ListTile(
                            title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${product.price} دينار | القياس: ${product.size} | اللون: ${product.color}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('x$qty', style: const TextStyle(fontSize: 18, color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppTheme.errorColor),
                                  onPressed: () {
                                    setState(() {
                                      _cart.removeAt(index);
                                      _keepFocus();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // 3. لوحة التحكم السفلية (سيتم نقلها لملف pos_control_panel لاحقاً)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الإجمالي:', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('$_totalAmount دينار', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          icon: const Icon(Icons.cancel),
                          label: const Text('إلغاء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            setState(() => _cart.clear());
                            _keepFocus();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          icon: const Icon(Icons.pause_circle_filled),
                          label: const Text('تعليق', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: _suspendOrder,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          icon: const Icon(Icons.print),
                          label: const Text('دفع وطباعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            // لوجك الدفع وتخفيض الكمية (Stock) من القاعدة
                          },
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
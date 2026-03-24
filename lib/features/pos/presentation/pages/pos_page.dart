import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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

      // فحص المخزون وتنبيه إذا كان قليلاً
      final thresholdStr = await DatabaseHelper.instance.getSetting('low_stock_threshold', defaultValue: '5');
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
            backgroundColor: remaining <= 0 ? AppTheme.errorColor : AppTheme.warningColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
    setState(() {
      _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + 1;
    });
    _keepFocus();
  }

  // حوار الدفع: حساب الفكة + اختيار الطباعة
  Future<void> _showPaymentDialog() async {
    if (_cart.isEmpty) return;

    final total = _totalAmount;
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
            title: const Text('إتمام الدفع', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // المجموع الكلي
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('المجموع:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('$total دينار',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  ],
                ),
                const SizedBox(height: 16),
                // حقل المبلغ المعطى
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: canConfirm
                        ? AppTheme.successColor.withValues(alpha: 0.12)
                        : AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: canConfirm ? AppTheme.successColor : AppTheme.errorColor,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الباقي (الفكة):', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        canConfirm ? '$change دينار' : 'المبلغ غير كافٍ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: canConfirm ? AppTheme.successColor : AppTheme.errorColor,
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
                        onChanged: (v) => setDialogState(() => shouldPrint = v ?? true),
                        activeColor: AppTheme.primaryColor,
                      ),
                      const Icon(Icons.receipt_long, size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      const Text('طباعة فاتورة', style: TextStyle(fontSize: 15)),
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
                  backgroundColor: canConfirm ? AppTheme.successColor : AppTheme.neutralColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
                icon: const Icon(Icons.check_circle),
                label: const Text('تأكيد الدفع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

    final cartSnapshot = List<Map<String, dynamic>>.from(_cart);
    final saleId = await DatabaseHelper.instance.completeSale(_cart);

    if (saleId > 0 && mounted) {
      final totalProfit = cartSnapshot.fold<int>(0, (s, i) {
        final p = i['product'] as ProductModel;
        return s + (p.profit * (i['quantity'] as int));
      });
      setState(() => _cart.clear());

      if (shouldPrint) {
        await _printInvoice(cartSnapshot, total, given, changeAmount);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم البيع بنجاح ✓  |  الربح: $totalProfit د'
              '${changeAmount > 0 ? '  |  الباقي: $changeAmount د' : ''}',
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ أثناء إتمام البيع!'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
    _keepFocus();
  }

  // طباعة فاتورة البيع كـ PDF
  Future<void> _printInvoice(
    List<Map<String, dynamic>> cart,
    int total,
    int given,
    int change,
  ) async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    final storeName = settings['store_name'] ?? 'لمسة';
    final storePhone = settings['store_phone'] ?? '';
    final currency = settings['currency'] ?? 'دينار';
    final footer = settings['receipt_footer'] ?? 'شكراً لزيارتكم';

    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    final arabicFont = pw.Font.ttf(fontData);

    final now = DateTime.now();
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final itemCount = cart.fold<int>(0, (s, i) => s + (i['quantity'] as int));
    // ارتفاع تقريبي للفاتورة بناءً على عدد المنتجات
    final pageHeight = (80 + cart.length * 18 + 80).toDouble() * PdfPageFormat.mm;
    final pageFormat = PdfPageFormat(
      78 * PdfPageFormat.mm,
      pageHeight,
      marginAll: 4 * PdfPageFormat.mm,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // اسم المحل
            pw.Text(
              storeName,
              style: pw.TextStyle(fontSize: 14, font: arabicFont, fontWeight: pw.FontWeight.bold),
              textDirection: pw.TextDirection.rtl,
            ),
            if (storePhone.isNotEmpty)
              pw.Text(
                storePhone,
                style: pw.TextStyle(fontSize: 9, font: arabicFont),
                textDirection: pw.TextDirection.rtl,
              ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.5),
            // التاريخ والوقت
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(timeStr, style: pw.TextStyle(fontSize: 8, font: arabicFont)),
                pw.Text(dateStr, style: pw.TextStyle(fontSize: 8, font: arabicFont)),
              ],
            ),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 2),
            // المنتجات
            ...cart.map((item) {
              final product = item['product'] as ProductModel;
              final qty = item['quantity'] as int;
              final subtotal = product.price * qty;
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '$subtotal $currency',
                      style: pw.TextStyle(fontSize: 9, font: arabicFont),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        '${product.name}  x$qty',
                        style: pw.TextStyle(fontSize: 9, font: arabicFont),
                        textDirection: pw.TextDirection.rtl,
                        textAlign: pw.TextAlign.right,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 0.8),
            // المجموع
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '$total $currency',
                  style: pw.TextStyle(fontSize: 13, font: arabicFont, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'المجموع ($itemCount قطعة):',
                  style: pw.TextStyle(fontSize: 11, font: arabicFont, fontWeight: pw.FontWeight.bold),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
            // المدفوع والباقي (إذا دفع أكثر)
            if (given > total) ...([
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('$given $currency', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
                  pw.Text('المدفوع:', style: pw.TextStyle(fontSize: 10, font: arabicFont), textDirection: pw.TextDirection.rtl),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('$change $currency',
                      style: pw.TextStyle(fontSize: 11, font: arabicFont, fontWeight: pw.FontWeight.bold)),
                  pw.Text('الباقي:', style: pw.TextStyle(fontSize: 11, font: arabicFont, fontWeight: pw.FontWeight.bold), textDirection: pw.TextDirection.rtl),
                ],
              ),
            ]),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Text(
              footer,
              style: pw.TextStyle(fontSize: 10, font: arabicFont),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => doc.save());
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
                            subtitle: Text('${product.price} دينار | ${product.price * qty} إجمالي'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // زر تقليل الكمية
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: AppTheme.warningColor, size: 26),
                                  onPressed: () => _decreaseQty(index),
                                  tooltip: 'تقليل',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                // عرض الكمية
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    '$qty',
                                    style: const TextStyle(fontSize: 20, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                // زر زيادة الكمية
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: AppTheme.successColor, size: 26),
                                  onPressed: () => _increaseQty(index),
                                  tooltip: 'زيادة',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 6),
                                // زر حذف
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
                                  onPressed: () {
                                    setState(() => _cart.removeAt(index));
                                    _keepFocus();
                                  },
                                  tooltip: 'حذف',
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
                          onPressed: _cart.isEmpty ? null : _showPaymentDialog,
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
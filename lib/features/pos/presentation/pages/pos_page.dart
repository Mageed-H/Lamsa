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

  @override
  void initState() {
    super.initState();
    DatabaseHelper.revision.addListener(_loadAllProducts);
    // مستمع يرجع التركيز تلقائياً لحقل الباركود كل ما يضيع
    _barcodeFocusNode.addListener(_autoRefocus);
    // أول ما تفتح الشاشة، نخلي التركيز تلقائياً على حقل الباركود
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
      _checkSuspendedOrders();
      _loadAllProducts();
    });
  }

  @override
  void dispose() {
    DatabaseHelper.revision.removeListener(_loadAllProducts);
    _barcodeFocusNode.removeListener(_autoRefocus);
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  // تنظيف مدخلات الماسح الضوئي من الرموز الزائدة (مثل {#\ اللي تطلع من تبديل أنماط Code128)
  String _cleanBarcode(String raw) {
    return raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  }

  // الدالة السحرية اللي تشتغل من نضرب الباركود بالجهاز
  Future<void> _onBarcodeScanned(String barcode) async {
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
  }

  // دالة مساعدة للحفاظ على التركيز
  void _keepFocus() {
    FocusScope.of(context).requestFocus(_barcodeFocusNode);
  }

  // يرجع التركيز تلقائياً لحقل الباركود بعد كل فريم إذا ضاع
  // لكن فقط إذا الصفحة هي الـ route النشط (ما يسرق الفوكس من الحوارات)
  void _autoRefocus() {
    if (!_barcodeFocusNode.hasFocus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_barcodeFocusNode.hasFocus) {
          final route = ModalRoute.of(context);
          if (route != null && route.isCurrent) {
            _barcodeFocusNode.requestFocus();
          }
        }
      });
    }
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
      await DatabaseHelper.instance.saveSuspendedOrder(
        _cart,
        noteController.text,
        discountAmount: _discountAmount,
        isDiscountPercent: _isDiscountPercent,
      );
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

    final cartSnapshot = List<Map<String, dynamic>>.from(_cart);
    final saleId = await DatabaseHelper.instance.completeSale(
      _cart,
      discountValue: discountVal,
    );

    if (saleId > 0 && mounted) {
      // حفظ بيانات آخر فاتورة لإعادة الطباعة
      _lastPrintCart = cartSnapshot;
      _lastPrintSubtotal = subtotal;
      _lastPrintDiscount = discountVal;
      _lastPrintTotal = total;
      _lastPrintGiven = given;
      _lastPrintChange = changeAmount;
      setState(() {
        _cart.clear();
        _discountAmount = 0;
        _isDiscountPercent = false;
      });

      if (shouldPrint) {
        await _printInvoice(
          cartSnapshot,
          subtotal,
          discountVal,
          total,
          given,
          changeAmount,
        );
      }

      if (mounted) {
        final remainingStock = cartSnapshot
            .map((i) {
              final p = i['product'] as ProductModel;
              final qty = i['quantity'] as int;
              return '${p.name} (${p.stock - qty})';
            })
            .join('  |  ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تم البيع بنجاح ✓'
                  '${changeAmount > 0 ? '  |  الباقي: $changeAmount د' : ''}',
                ),
                const SizedBox(height: 4),
                Text(
                  'المتبقي: $remainingStock',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
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

  // طباعة فاتورة البيع — وصل بتصميم جديد ٤ أعمدة
  Future<void> _printInvoice(
    List<Map<String, dynamic>> cart,
    int subtotal,
    int discountValue,
    int finalTotal,
    int given,
    int change,
  ) async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    final storeName = settings['store_name'] ?? 'لمسة';
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
      final rowTotal = product.price * qty;
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
                  '${product.price}',
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
          onLayout: (_) => doc.save(),
        );
        if (ok) return;
      } catch (_) {}
    }
    await Printing.layoutPdf(onLayout: (_) => doc.save());
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
                                    await DatabaseHelper.instance
                                        .deleteSuspendedOrder(orderId);
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
    return s + (p.price * (i['quantity'] as int));
  });

  int get _discountValue {
    if (_discountAmount <= 0) return 0;
    if (_isDiscountPercent) return _subtotal * _discountAmount ~/ 100;
    return _discountAmount.clamp(0, _subtotal);
  }

  int get _finalTotal => _subtotal - _discountValue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'نقطة البيع (الكاشير)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // زر إعادة طباعة آخر فاتورة
          if (_lastPrintCart != null)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: () => _printInvoice(
                _lastPrintCart!,
                _lastPrintSubtotal,
                _lastPrintDiscount,
                _lastPrintTotal,
                _lastPrintGiven,
                _lastPrintChange,
              ),
              tooltip: 'طباعة آخر فاتورة',
            ),
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
                      decoration: const BoxDecoration(
                        color: AppTheme.errorColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showSuspendedOrders,
            tooltip: 'الفواتير المعلقة',
          ),
          // زر المخزون المنخفض مع عدد المنتجات
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.inventory_2_outlined),
                if (_lowStockProducts.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(
                        color: AppTheme.warningColor,
                        shape: BoxShape.circle,
                      ),
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
          // زر البحث عن منتج
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showProductSearchDialog,
            tooltip: 'بحث عن منتج',
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
                  prefixIcon: const Icon(
                    Icons.qr_code_scanner,
                    color: AppTheme.primaryColor,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceColor,
                ),
                onSubmitted:
                    _onBarcodeScanned, // يتنفذ تلقائياً من يخلص جهاز السكانر قراءة
              ),
            ),

            // 2. قائمة المنتجات في الفاتورة الحالية (سيتم نقلها لملف invoice_list_widget لاحقاً)
            Expanded(
              child: _cart.isEmpty
                  ? const Center(
                      child: Text(
                        'الفاتورة فارغة، قم بمسح منتج للبدء',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 18,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _cart.length,
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        final product = item['product'] as ProductModel;
                        final qty = item['quantity'] as int;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(
                              product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${product.price} دينار | ${product.price * qty} إجمالي',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // زر تقليل الكمية
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle,
                                    color: AppTheme.warningColor,
                                    size: 26,
                                  ),
                                  onPressed: () => _decreaseQty(index),
                                  tooltip: 'تقليل',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                // عرض الكمية
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    '$qty',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                // زر زيادة الكمية
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: AppTheme.successColor,
                                    size: 26,
                                  ),
                                  onPressed: () => _increaseQty(index),
                                  tooltip: 'زيادة',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 6),
                                // زر حذف
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppTheme.errorColor,
                                  ),
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // صف الخصم (يظهر فقط عند وجود خصم)
                  if (_discountValue > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$_subtotal دينار',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            decoration: TextDecoration.lineThrough,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'خصم: -$_discountValue دينار',
                          style: const TextStyle(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  // صف الإجمالي
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _discountValue > 0 ? 'الصافي:' : 'الإجمالي:',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$_finalTotal دينار',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // صف الأزرار
                  Row(
                    children: [
                      // زر الخصم
                      IconButton(
                        icon: Icon(
                          Icons.discount_outlined,
                          color: _discountValue > 0
                              ? AppTheme.errorColor
                              : AppTheme.textSecondary,
                          size: 28,
                        ),
                        onPressed: _cart.isEmpty ? null : _showDiscountDialog,
                        tooltip: 'خصم',
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.errorColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.cancel),
                          label: const Text(
                            'إلغاء',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _cart.clear();
                              _discountAmount = 0;
                              _isDiscountPercent = false;
                            });
                            _keepFocus();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.warningColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.pause_circle_filled),
                          label: const Text(
                            'تعليق',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _suspendOrder,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.point_of_sale),
                          label: const Text(
                            'دفع',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
    );
  }
}

import 'package:flutter/material.dart';
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
  List<Map<String, dynamic>> _cart = [];

  @override
  void initState() {
    super.initState();
    // أول ما تفتح الشاشة، نخلي التركيز تلقائياً على حقل الباركود
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
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
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          icon: const Icon(Icons.pause_circle_filled),
                          label: const Text('تعليق', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          onPressed: () {
                            // سيتم ربطها بجدول suspended_orders لاحقاً
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
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
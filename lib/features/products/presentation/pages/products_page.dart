import 'package:flutter/material.dart';
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';
import 'package:lamsa/core/widgets/custom_button.dart';
import 'package:lamsa/core/widgets/custom_text_field.dart';
import 'package:lamsa/features/products/data/models/product_model.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({Key? key}) : super(key: key);

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers لحقول الإدخال
  final _nameController = TextEditingController();
  final _colorController = TextEditingController();
  final _sizeController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _barcodeController = TextEditingController();

  // متغيرات الأقسام (Categories)
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isCustomBarcode = false; // لمعرفة هل الباركود محلي أو عالمي

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _colorController.dispose();
    _sizeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  // جلب الأقسام من SQLite
  Future<void> _loadCategories() async {
    final categories = await DatabaseHelper.instance.getAllCategories();
    setState(() {
      _categories = categories;
      if (_categories.isNotEmpty && _selectedCategory == null) {
        _selectedCategory = _categories.first;
      }
    });
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
          decoration: const InputDecoration(hintText: 'مثال: جواريب نسائية'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              if (catController.text.trim().isNotEmpty) {
                await DatabaseHelper.instance.insertCategory(catController.text.trim());
                Navigator.pop(context);
                _loadCategories(); // تحديث القائمة بعد الإضافة
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // توليد باركود محلي فريد
  void _generateCustomBarcode() {
    final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      // الباركود المحلي يبدأ بـ LOC- متبوع برقم فريد يعتمد على الوقت
      _barcodeController.text = 'LOC-${uniqueId.substring(uniqueId.length - 8)}';
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

      // تحضير كائن المنتج للحفظ (مع حماية صارمة من أخطاء التحويل)
      final newProduct = ProductModel(
        name: _nameController.text.trim(),
        category: _selectedCategory!,
        color: _colorController.text.trim(),
        size: _sizeController.text.trim(),
        price: int.tryParse(_priceController.text.trim()) ?? 0, // Financial Precision
        stock: int.tryParse(_stockController.text.trim()) ?? 0,
        barcode: _barcodeController.text.trim(),
        isCustomBarcode: _isCustomBarcode,
      );

      final result = await DatabaseHelper.instance.insertProduct(newProduct);

      if (result != -1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المنتج بنجاح!'), backgroundColor: Colors.green));
        // تفريغ الحقول لمنتج جديد
        _nameController.clear();
        _colorController.clear();
        _sizeController.clear();
        _priceController.clear();
        _stockController.clear();
        _barcodeController.clear();
        setState(() => _isCustomBarcode = false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء الحفظ!'), backgroundColor: AppTheme.errorColor));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المنتجات')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
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

              // 2. تفاصيل المنتج الأساسية
              CustomTextField(
                label: 'اسم المنتج (مثال: ملفع كويتي)',
                controller: _nameController,
                icon: Icons.shopping_bag,
                validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال اسم المنتج' : null,
              ),
              Row(
                children: [
                  Expanded(child: CustomTextField(label: 'اللون (اختياري)', controller: _colorController, icon: Icons.color_lens)),
                  const SizedBox(width: 16),
                  Expanded(child: CustomTextField(label: 'القياس (اختياري)', controller: _sizeController, icon: Icons.straighten)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: CustomTextField(
                      label: 'السعر (دينار)',
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      icon: Icons.attach_money,
                      validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال السعر' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: CustomTextField(
                      label: 'الكمية (المخزون)',
                      controller: _stockController,
                      keyboardType: TextInputType.number,
                      icon: Icons.inventory,
                      validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال الكمية' : null,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32, thickness: 1),

              // 3. قسم الباركود
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
              const SizedBox(height: 32),

              // 4. زر الحفظ
              CustomButton(
                text: 'حفظ المنتج في المخزن',
                icon: Icons.save,
                onPressed: _saveProduct,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
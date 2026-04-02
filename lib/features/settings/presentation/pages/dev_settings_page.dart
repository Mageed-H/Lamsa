import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';

/// صفحة إعدادات المطور — لا تظهر في القائمة الرئيسية
/// يُفتح عبر: Ctrl + Alt + Shift ثم اكتب  d e v m h
class DevSettingsPage extends StatefulWidget {
  const DevSettingsPage({Key? key}) : super(key: key);

  @override
  State<DevSettingsPage> createState() => _DevSettingsPageState();
}

class _DevSettingsPageState extends State<DevSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers لكل إعداد
  final _storeNameCtrl = TextEditingController();
  final _storePhoneCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController();
  final _defaultCopiesCtrl = TextEditingController();
  final _receiptFooterCtrl = TextEditingController();
  // إعدادات الطباعة
  final _titleFontCtrl = TextEditingController();
  final _bodyFontCtrl = TextEditingController();
  final _paperWidthCtrl = TextEditingController();
  // أبعاد الباركود + هوامش
  final _barcodeWCtrl = TextEditingController();
  final _barcodeHCtrl = TextEditingController();
  final _barcodePadCtrl = TextEditingController();
  final _receiptMarginCtrl = TextEditingController();
  // الطابعة الافتراضية
  String _defaultPrinterName = '';
  String _defaultPrinterUrl = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _storePhoneCtrl.dispose();
    _currencyCtrl.dispose();
    _lowStockCtrl.dispose();
    _defaultCopiesCtrl.dispose();
    _receiptFooterCtrl.dispose();
    _titleFontCtrl.dispose();
    _bodyFontCtrl.dispose();
    _paperWidthCtrl.dispose();
    _barcodeWCtrl.dispose();
    _barcodeHCtrl.dispose();
    _barcodePadCtrl.dispose();
    _receiptMarginCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    if (!mounted) return;
    setState(() {
      _storeNameCtrl.text = settings['store_name'] ?? 'لمسة';
      _storePhoneCtrl.text = settings['store_phone'] ?? '';
      _currencyCtrl.text = settings['currency'] ?? 'دينار';
      _lowStockCtrl.text = settings['low_stock_threshold'] ?? '5';
      _defaultCopiesCtrl.text = settings['default_barcode_copies'] ?? '1';
      _receiptFooterCtrl.text = settings['receipt_footer'] ?? 'شكراً لزيارتكم';
      _titleFontCtrl.text = settings['receipt_title_font_size'] ?? '14';
      _bodyFontCtrl.text = settings['receipt_body_font_size'] ?? '9';
      _paperWidthCtrl.text = settings['receipt_paper_width_mm'] ?? '78';
      _barcodeWCtrl.text = settings['barcode_label_width_mm'] ?? '60';
      _barcodeHCtrl.text = settings['barcode_label_height_mm'] ?? '35';
      _barcodePadCtrl.text = settings['barcode_inner_padding_mm'] ?? '3';
      _receiptMarginCtrl.text = settings['receipt_margin_mm'] ?? '3';
      _defaultPrinterUrl = settings['default_printer_url'] ?? '';
      _defaultPrinterName = settings['default_printer_name'] ?? '';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    await Future.wait([
      DatabaseHelper.instance.setSetting('store_name', _storeNameCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('store_phone', _storePhoneCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('currency', _currencyCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('low_stock_threshold', _lowStockCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('default_barcode_copies', _defaultCopiesCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_footer', _receiptFooterCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_title_font_size', _titleFontCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_body_font_size', _bodyFontCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_paper_width_mm', _paperWidthCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('barcode_label_width_mm', _barcodeWCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('barcode_label_height_mm', _barcodeHCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('barcode_inner_padding_mm', _barcodePadCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_margin_mm', _receiptMarginCtrl.text.trim()),
    ]);

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓  تم حفظ الإعدادات بنجاح'),
        backgroundColor: AppTheme.successColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ─── اختيار طابعة افتراضية ───
  Future<void> _pickDefaultPrinter() async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer != null && mounted) {
      await Future.wait([
        DatabaseHelper.instance.setSetting('default_printer_url', printer.url),
        DatabaseHelper.instance.setSetting('default_printer_name', printer.name),
      ]);
      setState(() {
        _defaultPrinterUrl = printer.url;
        _defaultPrinterName = printer.name;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ تم حفظ الطابعة: ${printer.name}'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _clearDefaultPrinter() async {
    await Future.wait([
      DatabaseHelper.instance.setSetting('default_printer_url', ''),
      DatabaseHelper.instance.setSetting('default_printer_name', ''),
    ]);
    if (mounted) setState(() { _defaultPrinterUrl = ''; _defaultPrinterName = ''; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚙️  إعدادات المطور'),
        backgroundColor: const Color(0xFF37474F), // رمادي داكن
        foregroundColor: Colors.white,
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('DEV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF263238),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader('🏪  بيانات المحل'),
                  _buildSettingField(
                    controller: _storeNameCtrl,
                    label: 'اسم المحل',
                    hint: 'مثال: لمسة',
                    icon: Icons.store,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'لا يمكن أن يكون فارغاً' : null,
                  ),
                  _buildSettingField(
                    controller: _storePhoneCtrl,
                    label: 'رقم هاتف المحل',
                    hint: 'مثال: 07901234567',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  _buildSettingField(
                    controller: _currencyCtrl,
                    label: 'وحدة العملة',
                    hint: 'مثال: دينار أو IQD',
                    icon: Icons.currency_exchange,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'لا يمكن أن يكون فارغاً' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('📦  إعدادات المخزون'),
                  _buildSettingField(
                    controller: _lowStockCtrl,
                    label: 'حد تنبيه نفاد المخزون (قطعة)',
                    hint: 'مثال: 5',
                    icon: Icons.warning_amber,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 0) return 'أدخل رقماً صحيحاً ≥ 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🖨️  إعدادات الطباعة'),
                  _buildSettingField(
                    controller: _defaultCopiesCtrl,
                    label: 'عدد نسخ الباركود الافتراضي',
                    hint: 'مثال: 1',
                    icon: Icons.print,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 999) return 'أدخل رقماً بين 1 و 999';
                      return null;
                    },
                  ),
                  _buildSettingField(
                    controller: _receiptFooterCtrl,
                    label: 'نص ذيل الفاتورة',
                    hint: 'مثال: شكراً لزيارتكم',
                    icon: Icons.receipt_long,
                    maxLines: 2,
                  ),
                  _buildSettingField(
                    controller: _titleFontCtrl,
                    label: 'حجم خط العنوان (اسم المحل / الإجمالي)',
                    hint: 'افتراضي: 14',
                    icon: Icons.format_size,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 6 || n > 30) return 'أدخل رقماً بين 6 و 30';
                      return null;
                    },
                  ),
                  _buildSettingField(
                    controller: _bodyFontCtrl,
                    label: 'حجم خط بنود الفاتورة',
                    hint: 'افتراضي: 9',
                    icon: Icons.text_fields,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 5 || n > 20) return 'أدخل رقماً بين 5 و 20';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🧾  طباعة الفاتورة — أبعاد الصفحة'),
                  _buildSettingField(
                    controller: _paperWidthCtrl,
                    label: 'عرض ورقة الطباعة (ملم)',
                    hint: 'مثال: 78 (للثيرمال) أو 80',
                    icon: Icons.straighten,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 50 || n > 210) return 'أدخل عرضاً بين 50 و 210 ملم';
                      return null;
                    },
                  ),
                  _buildSettingField(
                    controller: _receiptMarginCtrl,
                    label: 'هامش الفاتورة من جميع الجوانب (ملم)',
                    hint: 'افتراضي: 3',
                    icon: Icons.margin,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0 || n > 20) return 'أدخل قيمة بين 0 و 20 ملم';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🏷️  طباعة الباركود — أبعاد البطاقة'),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodeWCtrl,
                          label: 'عرض البطاقة (ملم)',
                          hint: 'افتراضي: 60',
                          icon: Icons.crop_landscape,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 20 || n > 200) return 'بين 20–200';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodeHCtrl,
                          label: 'ارتفاع البطاقة (ملم)',
                          hint: 'افتراضي: 35',
                          icon: Icons.crop_portrait,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 10 || n > 100) return 'بين 10–100';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  _buildSettingField(
                    controller: _barcodePadCtrl,
                    label: 'هامش داخل بطاقة الباركود (ملم)',
                    hint: 'افتراضي: 3',
                    icon: Icons.padding,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 0 || n > 15) return 'بين 0–15 ملم';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🖨️  الطابعة الافتراضية'),
                  // بطاقة الطابعة
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF37474F),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.print, color: Colors.amber.shade400, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('الطابعة المحفوظة',
                                  style: TextStyle(color: Colors.white60, fontSize: 11)),
                              Text(
                                _defaultPrinterName.isEmpty ? 'لم يتم الاختيار' : _defaultPrinterName,
                                style: TextStyle(
                                  color: _defaultPrinterName.isEmpty
                                      ? Colors.white38
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text('اختيار',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: _pickDefaultPrinter,
                        ),
                        if (_defaultPrinterUrl.isNotEmpty) ...[  
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                            tooltip: 'حذف الطابعة المحفوظة',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _clearDefaultPrinter,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _defaultPrinterUrl.isEmpty
                          ? 'ℹ️ عند اختيار طابعة، ستُطبع الفواتير والباركودات مباشرةً دون طلب الاختيار في كل مرة.'
                          : '✅ الطباعة ستذهب مباشرةً ل: $_defaultPrinterName',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSaving ? null : _saveSettings,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        _isSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // معلومات النظام
                  // _buildInfoCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.amber,
          fontWeight: FontWeight.bold,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white60),
          hintStyle: const TextStyle(color: Colors.white30),
          prefixIcon: Icon(icon, color: Colors.amber.shade400, size: 20),
          filled: true,
          fillColor: const Color(0xFF37474F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.amber.shade600, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.errorColor),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.5),
          ),
          errorStyle: const TextStyle(color: Color(0xFFFF7070)),
        ),
      ),
    );
  }

  // Widget _buildInfoCard() {
  //   return Container(
  //     padding: const EdgeInsets.all(12),
  //     decoration: BoxDecoration(
  //       color: const Color(0xFF1C2B30),
  //       borderRadius: BorderRadius.circular(10),
  //       border: Border.all(color: Colors.white12),
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const Text('ℹ️  معلومات', style: TextStyle(color: Colors.white38, fontSize: 12)),
  //         const SizedBox(height: 6),
  //         const Text(
  //           'هذه الصفحة للمطور فقط.\nلفتحها: اضغط Ctrl + Alt + Shift ثم اكتب: d e v m h',
  //           style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.6),
  //         ),
  //       ],
  //     ),
  //   );
  // }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:barcode/barcode.dart' as bc;
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:cashier_system/core/services/error_logger.dart';
import 'package:cashier_system/core/services/pin_hash.dart';
import 'package:cashier_system/core/services/activation_service.dart';
import 'package:cashier_system/core/services/dev_lock_service.dart';
import 'package:cashier_system/features/z_report/presentation/pages/z_report_page.dart';

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
  final _barcodePadTopCtrl = TextEditingController();
  final _barcodePadBottomCtrl = TextEditingController();
  final _barcodePadLeftCtrl = TextEditingController();
  final _barcodePadRightCtrl = TextEditingController();
  final _receiptMarginTopCtrl = TextEditingController();
  final _receiptMarginBottomCtrl = TextEditingController();
  final _receiptMarginLeftCtrl = TextEditingController();
  final _receiptMarginRightCtrl = TextEditingController();
  // رابط QR Code للفاتورة
  final _qrUrlCtrl = TextEditingController();
  // رموز الحماية
  final _productsPinCtrl = TextEditingController();
  final _salesPinCtrl = TextEditingController();
  final _debtsPinCtrl = TextEditingController();
  final _activationCodeCtrl = TextEditingController();
  final _devPinCtrl = TextEditingController();
  String _selectedLogLevel = 'info';
  // طابعة الفواتير
  String _receiptPrinterName = '';
  String _receiptPrinterUrl = '';
  // طابعة الباركود
  String _barcodePrinterName = '';
  String _barcodePrinterUrl = '';
  // الأقسام
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadCategories();
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
    _barcodePadTopCtrl.dispose();
    _barcodePadBottomCtrl.dispose();
    _barcodePadLeftCtrl.dispose();
    _barcodePadRightCtrl.dispose();
    _receiptMarginTopCtrl.dispose();
    _receiptMarginBottomCtrl.dispose();
    _receiptMarginLeftCtrl.dispose();
    _receiptMarginRightCtrl.dispose();
    _qrUrlCtrl.dispose();
    _productsPinCtrl.dispose();
    _salesPinCtrl.dispose();
    _debtsPinCtrl.dispose();
    _activationCodeCtrl.dispose();
    _devPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    if (!mounted) return;
    setState(() {
      _storeNameCtrl.text = settings['store_name'] ?? 'أحلى الحلوين';
      _storePhoneCtrl.text = settings['store_phone'] ?? '';
      _currencyCtrl.text = settings['currency'] ?? 'دينار';
      _lowStockCtrl.text = settings['low_stock_threshold'] ?? '5';
      _defaultCopiesCtrl.text = settings['default_barcode_copies'] ?? '1';
      _receiptFooterCtrl.text = settings['receipt_footer'] ?? 'شكراً لزيارتكم';
      _titleFontCtrl.text = settings['receipt_title_font_size'] ?? '14';
      _bodyFontCtrl.text = settings['receipt_body_font_size'] ?? '9';
      _paperWidthCtrl.text = settings['receipt_paper_width_mm'] ?? '78';
      _barcodeWCtrl.text = settings['barcode_label_width_mm'] ?? '40';
      _barcodeHCtrl.text = settings['barcode_label_height_mm'] ?? '25';
      _barcodePadTopCtrl.text = settings['barcode_padding_top_mm'] ?? settings['barcode_inner_padding_mm'] ?? '2';
      _barcodePadBottomCtrl.text = settings['barcode_padding_bottom_mm'] ?? settings['barcode_inner_padding_mm'] ?? '2';
      _barcodePadLeftCtrl.text = settings['barcode_padding_left_mm'] ?? settings['barcode_inner_padding_mm'] ?? '2';
      _barcodePadRightCtrl.text = settings['barcode_padding_right_mm'] ?? settings['barcode_inner_padding_mm'] ?? '2';
      _receiptMarginTopCtrl.text = settings['receipt_margin_top_mm'] ?? settings['receipt_margin_mm'] ?? '5';
      _receiptMarginBottomCtrl.text = settings['receipt_margin_bottom_mm'] ?? settings['receipt_margin_mm'] ?? '5';
      _receiptMarginLeftCtrl.text = settings['receipt_margin_left_mm'] ?? settings['receipt_margin_mm'] ?? '5';
      _receiptMarginRightCtrl.text = settings['receipt_margin_right_mm'] ?? settings['receipt_margin_mm'] ?? '5';
      _qrUrlCtrl.text = settings['qr_url'] ?? '';
      _productsPinCtrl.text = settings['products_pin'] ?? '';
      _salesPinCtrl.text = settings['sales_pin'] ?? '';
      _debtsPinCtrl.text = settings['debts_pin'] ?? '';
      _selectedLogLevel = settings['log_level'] ?? 'info';
      ErrorLogger.instance.minLevel = LogLevel.fromString(_selectedLogLevel);
      // طابعة الفواتير — fallback للقيمة القديمة
      _receiptPrinterUrl = settings['receipt_printer_url'] ?? settings['default_printer_url'] ?? '';
      _receiptPrinterName = settings['receipt_printer_name'] ?? settings['default_printer_name'] ?? '';
      // طابعة الباركود
      _barcodePrinterUrl = settings['barcode_printer_url'] ?? '';
      _barcodePrinterName = settings['barcode_printer_name'] ?? '';
      _isLoading = false;
    });
  }

  Future<void> _loadCategories() async {
    final cats = await DatabaseHelper.instance.getAllCategories();
    if (mounted) setState(() => _categories = cats);
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة قسم جديد', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'اسم القسم', border: OutlineInputBorder())),
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
    if (name != null && name.isNotEmpty) {
      final id = await DatabaseHelper.instance.insertCategory(name);
      if (id > 0) {
        _loadCategories();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة القسم: $name'), backgroundColor: AppTheme.successColor));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('هذا القسم موجود مسبقاً'), backgroundColor: AppTheme.errorColor));
      }
    }
  }

  Future<void> _editCategory(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل القسم', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم الجديد', border: OutlineInputBorder())),
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
    if (newName != null && newName.isNotEmpty && newName != oldName) {
      final rows = await DatabaseHelper.instance.updateCategory(oldName, newName);
      if (rows > 0) {
        _loadCategories();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تعديل القسم إلى: $newName'), backgroundColor: AppTheme.successColor));
      }
    }
  }

  Future<void> _deleteCategory(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف القسم "$name"', style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من حذف هذا القسم؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await DatabaseHelper.instance.deleteCategory(name);
      if (result == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن حذف القسم لوجود منتجات به'), backgroundColor: AppTheme.errorColor),
        );
        }
      } else {
        _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حذف القسم: $name'), backgroundColor: AppTheme.successColor),
        );
        }
      }
    }
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
      DatabaseHelper.instance.setSetting('barcode_padding_top_mm', _barcodePadTopCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('barcode_padding_bottom_mm', _barcodePadBottomCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('barcode_padding_left_mm', _barcodePadLeftCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('barcode_padding_right_mm', _barcodePadRightCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_margin_top_mm', _receiptMarginTopCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_margin_bottom_mm', _receiptMarginBottomCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_margin_left_mm', _receiptMarginLeftCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('receipt_margin_right_mm', _receiptMarginRightCtrl.text.trim()),
      DatabaseHelper.instance.setSetting('products_pin', _productsPinCtrl.text.trim().isEmpty ? '' : PinHash.hash(_productsPinCtrl.text.trim())),
      DatabaseHelper.instance.setSetting('sales_pin', _salesPinCtrl.text.trim().isEmpty ? '' : PinHash.hash(_salesPinCtrl.text.trim())),
      DatabaseHelper.instance.setSetting('debts_pin', _debtsPinCtrl.text.trim().isEmpty ? '' : PinHash.hash(_debtsPinCtrl.text.trim())),
      DatabaseHelper.instance.setSetting('log_level', _selectedLogLevel),
    ]);

    // توليد QR SVG وحفظه بالكاش إذا الرابط تغير
    await _regenerateQrCache();

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

  // ─── توليد QR وحفظه ───
  Future<void> _regenerateQrCache() async {
    final url = _qrUrlCtrl.text.trim();
    if (url.isEmpty) {
      await DatabaseHelper.instance.setSetting('qr_svg_cache', '');
      await DatabaseHelper.instance.setSetting('qr_url', '');
      return;
    }
    // نشيك إذا الرابط تغير عن المحفوظ
    final oldUrl = await DatabaseHelper.instance.getSetting('qr_url');
    final oldCache = await DatabaseHelper.instance.getSetting('qr_svg_cache');
    if (oldUrl == url && oldCache.isNotEmpty) return;
    // توليد SVG جديد
    final qrBarcode = bc.Barcode.qrCode();
    final svg = qrBarcode.toSvg(url, width: 150, height: 150);
    await DatabaseHelper.instance.setSetting('qr_url', url);
    await DatabaseHelper.instance.setSetting('qr_svg_cache', svg);
  }

  // ─── طابعة الفواتير ───
  Future<void> _pickReceiptPrinter() async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer != null && mounted) {
      await Future.wait([
        DatabaseHelper.instance.setSetting('receipt_printer_url', printer.url),
        DatabaseHelper.instance.setSetting('receipt_printer_name', printer.name),
      ]);
      setState(() {
        _receiptPrinterUrl = printer.url;
        _receiptPrinterName = printer.name;
      });
    }
  }

  Future<void> _clearReceiptPrinter() async {
    await Future.wait([
      DatabaseHelper.instance.setSetting('receipt_printer_url', ''),
      DatabaseHelper.instance.setSetting('receipt_printer_name', ''),
    ]);
    if (mounted) setState(() { _receiptPrinterUrl = ''; _receiptPrinterName = ''; });
  }

  // ─── طابعة الباركود ───
  Future<void> _pickBarcodePrinter() async {
    final printer = await Printing.pickPrinter(context: context);
    if (printer != null && mounted) {
      await Future.wait([
        DatabaseHelper.instance.setSetting('barcode_printer_url', printer.url),
        DatabaseHelper.instance.setSetting('barcode_printer_name', printer.name),
      ]);
      setState(() {
        _barcodePrinterUrl = printer.url;
        _barcodePrinterName = printer.name;
      });
    }
  }

  Future<void> _clearBarcodePrinter() async {
    await Future.wait([
      DatabaseHelper.instance.setSetting('barcode_printer_url', ''),
      DatabaseHelper.instance.setSetting('barcode_printer_name', ''),
    ]);
    if (mounted) setState(() { _barcodePrinterUrl = ''; _barcodePrinterName = ''; });
  }

  Future<void> _backupDatabase() async {
    try {
      final path = await DatabaseHelper.instance.backupDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم النسخ الاحتياطي والتحقق من سلامته ✓\n$path'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في النسخ الاحتياطي: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _importDatabase() async {
    // اختيار طريقة الاستيراد: من المجلد المخفي أو من ملف خارجي
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: const Text('اختر مصدر النسخة الاحتياطية:'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton.icon(
            icon: const Icon(Icons.folder_special, size: 18),
            label: const Text('من النسخ المحفوظة'),
            onPressed: () => Navigator.pop(ctx, 'backups'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.file_open, size: 18),
            label: const Text('من ملف خارجي'),
            onPressed: () => Navigator.pop(ctx, 'file'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    String? selectedPath;

    if (choice == 'backups') {
      final backups = await DatabaseHelper.instance.listBackups();
      if (backups.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد نسخ احتياطية محفوظة'), backgroundColor: AppTheme.errorColor),
          );
        }
        return;
      }
      if (!mounted) return;
      selectedPath = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('اختر نسخة احتياطية'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (_, i) {
                final name = backups[i].path.split(Platform.pathSeparator).last;
                return ListTile(
                  leading: const Icon(Icons.storage, color: AppTheme.primaryColor),
                  title: Text(name, style: const TextStyle(fontSize: 13)),
                  onTap: () => Navigator.pop(ctx, backups[i].path),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء'))],
        ),
      );
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'اختر ملف النسخة الاحتياطية',
      );
      selectedPath = result?.files.single.path;
    }

    if (selectedPath == null || !mounted) return;

    // تأكيد الاستيراد
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ تأكيد الاستيراد', style: TextStyle(color: AppTheme.errorColor)),
        content: const Text('سيتم استبدال قاعدة البيانات الحالية بالكامل.\nيُنصح بعمل نسخة احتياطية قبل المتابعة.\n\nهل أنت متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الاستيراد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await DatabaseHelper.instance.restoreDatabase(selectedPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'تم استيراد النسخة الاحتياطية بنجاح ✓\nأعد تشغيل التطبيق لتحديث البيانات.' : 'فشل الاستيراد!'),
          backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
          duration: const Duration(seconds: 5),
        ),
      );
    }
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
                    hint: 'مثال: أحلى الحلوين',
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
                  _buildSectionHeader('📂  إدارة الأقسام'),
                  ..._categories.map((cat) => Card(
                    color: const Color(0xFF37474F),
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(cat, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.amber, size: 20),
                            tooltip: 'تعديل',
                            onPressed: () => _editCategory(cat),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: AppTheme.errorColor, size: 20),
                            tooltip: 'حذف',
                            onPressed: () => _deleteCategory(cat),
                          ),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        side: const BorderSide(color: AppTheme.primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة قسم جديد', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _addCategory,
                    ),
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
                  _buildSectionHeader('📋  إعدادات السجل'),
                  DropdownButtonFormField<String>(
                    value: _selectedLogLevel,
                    decoration: const InputDecoration(
                      labelText: 'مستوى السجل',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.article),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'debug', child: Text('DEBUG — تفصيلي جداً')),
                      DropdownMenuItem(value: 'info', child: Text('INFO — أحداث مهمة')),
                      DropdownMenuItem(value: 'warning', child: Text('WARNING — تحذيرات')),
                      DropdownMenuItem(value: 'error', child: Text('ERROR — أخطاء')),
                      DropdownMenuItem(value: 'critical', child: Text('CRITICAL — حرج')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _selectedLogLevel = v;
                          ErrorLogger.instance.minLevel = LogLevel.fromString(v);
                        });
                      }
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
                    controller: _qrUrlCtrl,
                    label: 'رابط QR Code (يظهر بالفاتورة)',
                    hint: 'مثال: https://instagram.com/yourpage',
                    icon: Icons.qr_code,
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
                  const Text('هوامش الفاتورة (ملم):', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSettingField(
                          controller: _receiptMarginTopCtrl,
                          label: 'أعلى',
                          hint: '5',
                          icon: Icons.arrow_upward,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 20) return '0-20';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSettingField(
                          controller: _receiptMarginBottomCtrl,
                          label: 'أسفل',
                          hint: '5',
                          icon: Icons.arrow_downward,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 20) return '0-20';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSettingField(
                          controller: _receiptMarginRightCtrl,
                          label: 'يمين',
                          hint: '5',
                          icon: Icons.arrow_forward,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 20) return '0-20';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSettingField(
                          controller: _receiptMarginLeftCtrl,
                          label: 'يسار',
                          hint: '5',
                          icon: Icons.arrow_back,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 20) return '0-20';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🏷️  طباعة الباركود — أبعاد البطاقة'),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodeWCtrl,
                          label: 'عرض البطاقة (ملم)',
                          hint: 'افتراضي: 40',
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
                          hint: 'افتراضي: 25',
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
                  const SizedBox(height: 8),
                  const Text('هوامش بطاقة الباركود (ملم)', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodePadTopCtrl,
                          label: 'أعلى',
                          hint: '2',
                          icon: Icons.border_top,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 15) return '0–15';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodePadBottomCtrl,
                          label: 'أسفل',
                          hint: '2',
                          icon: Icons.border_bottom,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 15) return '0–15';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodePadLeftCtrl,
                          label: 'يسار',
                          hint: '2',
                          icon: Icons.border_left,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 15) return '0–15';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSettingField(
                          controller: _barcodePadRightCtrl,
                          label: 'يمين',
                          hint: '2',
                          icon: Icons.border_right,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n < 0 || n > 15) return '0–15';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🧾  طابعة الفواتير'),
                  _buildPrinterCard(
                    name: _receiptPrinterName,
                    url: _receiptPrinterUrl,
                    onPick: _pickReceiptPrinter,
                    onClear: _clearReceiptPrinter,
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🏷️  طابعة الباركود'),
                  _buildPrinterCard(
                    name: _barcodePrinterName,
                    url: _barcodePrinterUrl,
                    onPick: _pickBarcodePrinter,
                    onClear: _clearBarcodePrinter,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 12),
                    child: Text(
                      'ℹ️ يمكنك تعيين طابعة مختلفة للفواتير وأخرى للباركود.\nإذا لم تُحدد طابعة، سيظهر حوار الاختيار في كل مرة.',
                      style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🔒  رموز الحماية (PIN)'),
                  _buildSettingField(
                    controller: _productsPinCtrl,
                    label: 'رمز صفحة المنتجات',
                    hint: 'اتركه فارغاً لإلغاء القفل',
                    icon: Icons.lock,
                    keyboardType: TextInputType.number,
                  ),
                  _buildSettingField(
                    controller: _salesPinCtrl,
                    label: 'رمز صفحة المبيعات',
                    hint: 'اتركه فارغاً لإلغاء القفل',
                    icon: Icons.lock,
                    keyboardType: TextInputType.number,
                  ),
                  _buildSettingField(
                    controller: _debtsPinCtrl,
                    label: 'رمز صفحة الديون',
                    hint: 'اتركه فارغاً لإلغاء القفل',
                    icon: Icons.lock,
                    keyboardType: TextInputType.number,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'ℹ️ إذا حددت رمزاً، سيُطلب عند الدخول لصفحة المنتجات أو المبيعات أو الديون.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🔐  قفل صفحة المطور'),
                  _buildDevLockSection(),
                  const SizedBox(height: 16),
                  _buildSectionHeader('🔑  التفعيل'),
                  _buildActivationSection(),
                  const SizedBox(height: 16),
                  _buildSectionHeader('💾  النسخ الاحتياطي'),
                  // زر النسخ الاحتياطي
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.backup),
                      label: const Text('نسخ احتياطي لقاعدة البيانات', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _backupDatabase,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // زر الاستيراد
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.amber.shade400,
                        side: BorderSide(color: Colors.amber.shade700),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.restore),
                      label: const Text('استيراد نسخة احتياطية', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _importDatabase,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 12),
                    child: Text(
                      'ℹ️ النسخ الاحتياطي يُحفظ في مجلد مخفي على D:\\\n'
                      'الاستيراد يستبدل قاعدة البيانات الحالية بالكامل.',
                      style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader('📊  التقارير'),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.summarize),
                      label: const Text('تقرير نهاية اليوم (Z-Report)', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ZReportPage()),
                        );
                      },
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

  // ─── قفل صفحة المطور ───
  Widget _buildDevLockSection() {
    return FutureBuilder<bool>(
      future: DevLockService.instance.isSetup(),
      builder: (ctx, snap) {
        final isSetup = snap.data ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSetup ? const Color(0xFF1B5E20).withOpacity(0.3) : const Color(0xFF37474F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSetup ? Colors.green.shade400 : Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(
                    isSetup ? Icons.lock : Icons.lock_open,
                    color: isSetup ? Colors.green : Colors.white38,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isSetup ? 'القفل مُفعّل ✅' : 'القفل غير مُفعّل',
                    style: TextStyle(
                      color: isSetup ? Colors.green : Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSettingField(
              controller: _devPinCtrl,
              label: 'كلمة سر المطور',
              hint: 'مثال: secret123@',
              icon: Icons.vpn_key,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'ℹ️ لفتح صفحة المطور اكتب: كلمة_السر + الوقت الحالي\n'
                'مثال: secret123@202609140314\n'
                'الوقت بنظام 24 ساعة: YYYYMMDDHHmm\n'
                'الكود يتغير كل دقيقة ±',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تفعيل القفل', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final secret = _devPinCtrl.text.trim();
                      if (secret.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('أدخل كلمة السر أولاً'), backgroundColor: AppTheme.errorColor),
                        );
                        return;
                      }
                      await DevLockService.instance.setSecret(secret);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم تفعيل القفل بنجاح ✅'), backgroundColor: AppTheme.successColor),
                        );
                      }
                    },
                  ),
                ),
                if (isSetup) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        side: BorderSide(color: Colors.red.shade700),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('إلغاء القفل', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('إلغاء القفل', style: TextStyle(color: AppTheme.errorColor)),
                            content: const Text('هل أنت متأكد؟ سيصبح بإمكان الجميع الدخول لصفحة المطور.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('إلغاء القفل'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await DatabaseHelper.instance.setSetting('dev_pin_hash', '');
                          _devPinCtrl.clear();
                          if (mounted) {
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم إلغاء القفل'), backgroundColor: AppTheme.warningColor),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  // ─── قسم التفعيل ───
  Widget _buildActivationSection() {
    return FutureBuilder<DateTime?>(
      future: ActivationService.instance.getExpiryDate(),
      builder: (ctx, snap) {
        final expiry = snap.data;
        final isExpired = expiry != null && DateTime.now().isAfter(expiry);
        final isActive = expiry != null && !isExpired;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // حالة التفعيل
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF1B5E20).withOpacity(0.3)
                    : isExpired
                        ? const Color(0xFFB71C1C).withOpacity(0.3)
                        : const Color(0xFF37474F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive
                      ? Colors.green.shade400
                      : isExpired
                          ? Colors.red.shade400
                          : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isActive ? Icons.check_circle : isExpired ? Icons.error : Icons.lock_outline,
                    color: isActive ? Colors.green : isExpired ? Colors.red : Colors.white38,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isActive ? 'التطبيق مفعّل ✅' : isExpired ? 'التفعيلة منتهية ❌' : 'التطبيق غير مفعّل',
                          style: TextStyle(
                            color: isActive ? Colors.green : isExpired ? Colors.red : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (expiry != null)
                          Text(
                            'تاريخ الانتهاء: ${expiry.year}/${expiry.month.toString().padLeft(2, '0')}/${expiry.day.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: isActive ? Colors.green.shade200 : Colors.red.shade200,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // إدخال التفعيلة
            _buildSettingField(
              controller: _activationCodeCtrl,
              label: 'أدخل كود التفعيل',
              hint: 'الصق الكود هنا...',
              icon: Icons.vpn_key,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('تفعيل', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final code = _activationCodeCtrl.text.trim();
                      if (code.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('أدخل كود التفعيل أولاً'), backgroundColor: AppTheme.errorColor),
                        );
                        return;
                      }
                      final (valid, expiry) = ActivationService.instance.validateCode(code);
                      if (!valid || expiry == null) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('الكود غير صالح!'), backgroundColor: AppTheme.errorColor),
                          );
                        }
                        return;
                      }
                      await ActivationService.instance.saveCode(code);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم التفعيل بنجاح!\nالصلاحية تنتهي: ${expiry.year}/${expiry.month}/${expiry.day}'),
                            backgroundColor: AppTheme.successColor,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                      side: BorderSide(color: Colors.red.shade700),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('حذف التفعيلة', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('حذف التفعيلة', style: TextStyle(color: AppTheme.errorColor)),
                          content: const Text('هل أنت متأكد؟ سيتوقف التطبيق عن العمل بعد الحذف.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('حذف'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ActivationService.instance.clearCode();
                        _activationCodeCtrl.clear();
                        if (mounted) {
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم حذف التفعيلة'), backgroundColor: AppTheme.warningColor),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'ℹ️ كود التفعيل يُولّد من الطرف المطور وتحديد تاريخ انتهاء الصلاحية.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        );
      },
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

  // Widget _buildInfoCard() { ... }

  Widget _buildPrinterCard({
    required String name,
    required String url,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Container(
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
                Text(
                  name.isEmpty ? 'لم يتم الاختيار' : name,
                  style: TextStyle(
                    color: name.isEmpty ? Colors.white38 : Colors.white,
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
            label: const Text('اختيار', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: onPick,
          ),
          if (url.isNotEmpty) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red, size: 18),
              tooltip: 'إزالة',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

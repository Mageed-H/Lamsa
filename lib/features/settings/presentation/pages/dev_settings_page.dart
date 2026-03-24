import 'package:flutter/material.dart';
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
                  _buildInfoCard(),
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2B30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ℹ️  معلومات', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 6),
          const Text(
            'هذه الصفحة للمطور فقط.\nلفتحها: اضغط Ctrl + Alt + Shift ثم اكتب: d e v m h',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.6),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';

class LoyaltySettingsPage extends StatefulWidget {
  const LoyaltySettingsPage({Key? key}) : super(key: key);

  @override
  State<LoyaltySettingsPage> createState() => _LoyaltySettingsPageState();
}

class _LoyaltySettingsPageState extends State<LoyaltySettingsPage> {
  Map<String, dynamic> _settings = {};
  bool _isLoading = true;

  final _pointsPerDinarCtrl = TextEditingController();
  final _pointsToDiscountCtrl = TextEditingController();
  final _discountPerPointCtrl = TextEditingController();
  final _giftThresholdCtrl = TextEditingController();
  final _giftDescCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final s = await DatabaseHelper.instance.getLoyaltySettings();
    _settings = s;
    _pointsPerDinarCtrl.text = '${s['points_per_dinar']}';
    _pointsToDiscountCtrl.text = '${s['points_to_discount']}';
    _discountPerPointCtrl.text = '${s['discount_per_point']}';
    _giftThresholdCtrl.text = '${s['gift_threshold']}';
    _giftDescCtrl.text = '${s['gift_description']}';
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    await DatabaseHelper.instance.updateLoyaltySettings(
      pointsPerDinar: int.tryParse(_pointsPerDinarCtrl.text) ?? 1,
      pointsToDiscount: int.tryParse(_pointsToDiscountCtrl.text) ?? 10,
      discountPerPoint: int.tryParse(_discountPerPointCtrl.text) ?? 100,
      giftThreshold: int.tryParse(_giftThresholdCtrl.text) ?? 50,
      giftDescription: _giftDescCtrl.text.isNotEmpty ? _giftDescCtrl.text : 'هدايا',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات'), backgroundColor: AppTheme.successColor),
      );
    }
  }

  @override
  void dispose() {
    _pointsPerDinarCtrl.dispose();
    _pointsToDiscountCtrl.dispose();
    _discountPerPointCtrl.dispose();
    _giftThresholdCtrl.dispose();
    _giftDescCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات نظام الولاء'),
        centerTitle: true,
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard(
                  title: 'نظام النقاط',
                  icon: Icons.star,
                  color: AppTheme.warningColor,
                  children: [
                    _buildSettingField(
                      controller: _pointsPerDinarCtrl,
                      label: 'نقاط لكل 1000 دينار',
                      hint: '1 = نقطة كل 1000 د.ع',
                      icon: Icons.looks_one,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('المشتريات الحالية', '${_settings['points_per_dinar'] ?? 1} نقطة / 1000 د.ع'),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCard(
                  title: 'تحويل النقاط لخصم',
                  icon: Icons.discount,
                  color: AppTheme.successColor,
                  children: [
                    _buildSettingField(
                      controller: _pointsToDiscountCtrl,
                      label: 'النقاط المطلوبة لخصم',
                      hint: '10 نقاط',
                      icon: Icons.arrow_downward,
                    ),
                    const SizedBox(height: 8),
                    _buildSettingField(
                      controller: _discountPerPointCtrl,
                      label: 'قيمة الخصم لكل نقطة (دينار)',
                      hint: '100 دينار',
                      icon: Icons.monetization_on,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('مثال', '${_settings['points_to_discount'] ?? 10} نقاط = ${(_settings['points_to_discount'] ?? 10) * (_settings['discount_per_point'] ?? 100)} د.ع خصم'),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCard(
                  title: 'نظام الهدايا',
                  icon: Icons.card_giftcard,
                  color: AppTheme.primaryColor,
                  children: [
                    _buildSettingField(
                      controller: _giftThresholdCtrl,
                      label: 'نقاط مطلوبة للهدية التلقائية',
                      hint: '50 نقطة',
                      icon: Icons.redeem,
                    ),
                    const SizedBox(height: 8),
                    _buildSettingField(
                      controller: _giftDescCtrl,
                      label: 'وصف الهدية التلقائية',
                      hint: 'هدايا',
                      icon: Icons.description,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('مثال', 'كل ${_settings['gift_threshold'] ?? 50} نقطة = هدية "${_settings['gift_description'] ?? 'هدايا'}" تلقائية'),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ الإعدادات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    onPressed: _saveSettings,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSummaryCard(),
              ],
            ),
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Color color, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ]),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingField({required TextEditingController controller, required String label, required String hint, required IconData icon}) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Icon(Icons.info_outline, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
      ],
    );
  }

  Widget _buildSummaryCard() {
    final ppd = int.tryParse(_pointsPerDinarCtrl.text) ?? 1;
    final ptd = int.tryParse(_pointsToDiscountCtrl.text) ?? 10;
    final dpp = int.tryParse(_discountPerPointCtrl.text) ?? 100;
    final gt = int.tryParse(_giftThresholdCtrl.text) ?? 50;
    return Card(
      color: AppTheme.primaryColor.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.calculate, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text('ملخص الإعدادات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            ]),
            const Divider(),
            _buildInfoRow('شراء 10,000 د.ع', '${((10000 / 1000) * ppd).floor()} نقطة'),
            _buildInfoRow('خصم $ptd نقاط', '${ptd * dpp} د.ع'),
            _buildInfoRow('هدية كل $gt نقطة', _giftDescCtrl.text.isNotEmpty ? _giftDescCtrl.text : 'هدايا'),
          ],
        ),
      ),
    );
  }
}

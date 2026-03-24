import 'package:flutter/material.dart';
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({Key? key}) : super(key: key);

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  Map<String, int> _summary = {};
  List<Map<String, dynamic>> _todaySales = [];
  List<Map<String, dynamic>> _allSales = [];
  bool _showAllSales = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final summary = await DatabaseHelper.instance.getSalesSummary();
    final today = await DatabaseHelper.instance.getTodaySales();
    final all = await DatabaseHelper.instance.getAllSales();
    if (mounted) {
      setState(() {
        _summary = summary;
        _todaySales = today;
        _allSales = all;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ملخص اليوم
                  _buildSummaryCard(
                    title: 'مبيعات اليوم',
                    icon: Icons.today,
                    revenue: _summary['today_revenue'] ?? 0,
                    profit: _summary['today_profit'] ?? 0,
                    count: _summary['today_count'] ?? 0,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 12),
                  // الملخص الكلي
                  _buildSummaryCard(
                    title: 'إجمالي المبيعات',
                    icon: Icons.analytics,
                    revenue: _summary['all_revenue'] ?? 0,
                    profit: _summary['all_profit'] ?? 0,
                    count: _summary['all_count'] ?? 0,
                    color: AppTheme.successColor,
                  ),
                  const SizedBox(height: 20),
                  // تبديل عرض اليوم / الكل
                  Row(
                    children: [
                      Expanded(
                        child: _buildToggleButton('اليوم', !_showAllSales, () => setState(() => _showAllSales = false)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildToggleButton('الكل', _showAllSales, () => setState(() => _showAllSales = true)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // قائمة الفواتير
                  ...(_showAllSales ? _allSales : _todaySales).map((sale) => _buildSaleCard(sale)),
                  if ((_showAllSales ? _allSales : _todaySales).isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          _showAllSales ? 'لا توجد مبيعات بعد' : 'لا توجد مبيعات اليوم',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required IconData icon,
    required int revenue,
    required int profit,
    required int count,
    required Color color,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('الإيرادات', '$revenue د', AppTheme.primaryColor),
                _buildStatColumn('الأرباح', '$profit د', AppTheme.successColor),
                _buildStatColumn('الفواتير', '$count', AppTheme.textPrimary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : AppTheme.neutralLightColor,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSaleCard(Map<String, dynamic> sale) {
    final saleId = sale['id'] as int;
    final totalAmount = sale['total_amount'] as int? ?? 0;
    final totalProfit = sale['total_profit'] as int? ?? 0;
    final itemsCount = sale['items_count'] as int? ?? 0;
    final createdAt = (sale['created_at'] as String? ?? '').replaceAll('T', '  ');
    final timeStr = createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor,
          child: Text('$itemsCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text('$totalAmount دينار', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('ربح: $totalProfit د  |  $timeStr', style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_left, color: AppTheme.textSecondary),
        onTap: () => _showSaleDetails(saleId, totalAmount, timeStr),
      ),
    );
  }

  Future<void> _showSaleDetails(int saleId, int totalAmount, String time) async {
    final items = await DatabaseHelper.instance.getSaleItems(saleId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('فاتورة #$saleId', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                Text(time, style: const TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
            const Divider(),
            ...items.map((item) {
              final name = item['product_name'] as String? ?? '';
              final qty = item['quantity'] as int? ?? 0;
              final unitPrice = item['unit_price'] as int? ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
                    Text('x$qty', style: const TextStyle(color: AppTheme.primaryColor)),
                    const SizedBox(width: 16),
                    Text('${unitPrice * qty} د', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المجموع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('$totalAmount دينار', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

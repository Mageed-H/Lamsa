import 'package:flutter/material.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';

class CustomerDetailsPage extends StatefulWidget {
  final String customerName;
  const CustomerDetailsPage({Key? key, required this.customerName}) : super(key: key);

  @override
  State<CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _sales = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final stats = await DatabaseHelper.instance.getCustomerStats(widget.customerName);
    final items = await DatabaseHelper.instance.getCustomerItems(widget.customerName);
    final sales = await DatabaseHelper.instance.getCustomerSales(widget.customerName);
    if (mounted) {
      setState(() {
        _stats = stats;
        _items = items;
        _sales = sales;
        _isLoading = false;
      });
    }
  }

  Future<void> _showSaleDetails(int saleId, int totalAmount, int discountAmount, String time) async {
    final items = await DatabaseHelper.instance.getSaleItems(saleId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('فاتورة #R${saleId.toString().padLeft(6, '0')}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                Text(time, style: const TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
            const Divider(),
            // بنود الفاتورة
            ...items.map((item) {
              final name = item['product_name'] as String? ?? '';
              final qty = item['quantity'] as int? ?? 0;
              final unitPrice = item['unit_price'] as int? ?? 0;
              final purchasePrice = item['purchase_price'] as int? ?? 0;
              final itemTotal = unitPrice * qty;
              final profit = (unitPrice - purchasePrice) * qty;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('السعر: $unitPrice د  |  الكمية: $qty', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$itemTotal د', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
                        Text('ربح: $profit', style: TextStyle(fontSize: 11, color: profit > 0 ? AppTheme.successColor : AppTheme.textSecondary)),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const Divider(),
            // الخصم
            if (discountAmount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الخصم', style: TextStyle(fontSize: 14, color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                    Text('- $discountAmount دينار', style: const TextStyle(fontSize: 14, color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            // الإجمالي
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الإجمالي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('$totalAmount دينار', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerName, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'تحديث'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stats['total_sales'] == 0
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off, size: 48, color: AppTheme.textSecondary),
                      SizedBox(height: 8),
                      Text('لا توجد مبيعات لهذا العميل', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildStatsSection(),
                      const SizedBox(height: 16),
                      _buildItemsSection(),
                      const SizedBox(height: 16),
                      _buildSalesSection(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatsSection() {
    final totalSpent = _stats['total_spent'] as int? ?? 0;
    final totalProfit = _stats['total_profit'] as int? ?? 0;
    final totalSales = _stats['total_sales'] as int? ?? 0;
    final totalItems = _stats['total_items'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text(widget.customerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: _statItem('إجمالي المشتريات', '$totalSpent دينار', AppTheme.primaryColor)),
                Expanded(child: _statItem('عدد الفواتير', '$totalSales', AppTheme.successColor)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _statItem('إجمالي القطع', '$totalItems', AppTheme.warningColor)),
                Expanded(child: _statItem('الربح الصافي', '$totalProfit دينار', AppTheme.successColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildItemsSection() {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_bag, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text('المنتجات المشتراة (${_items.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ..._items.map((item) {
              final name = item['product_name'] as String? ?? '';
              final qty = item['total_qty'] as int? ?? 0;
              final unitPrice = item['unit_price'] as int? ?? 0;
              final totalCost = item['total_cost'] as int? ?? 0;
              final profit = item['item_profit'] as int? ?? 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('السعر: $unitPrice د  |  الكمية: $qty', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$totalCost د', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
                        Text('ربح: $profit', style: TextStyle(fontSize: 11, color: profit > 0 ? AppTheme.successColor : AppTheme.textSecondary)),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesSection() {
    if (_sales.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text('الفواتير (${_sales.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(),
            ..._sales.map((sale) {
              final id = sale['id'] as int;
              final amount = sale['total_amount'] as int? ?? 0;
              final itemsCount = sale['items_count'] as int? ?? 0;
              final discountAmount = sale['discount_amount'] as int? ?? 0;
              final receipt = sale['receipt_number'] as String? ?? 'R${id.toString().padLeft(6, '0')}';
              final createdAt = (sale['created_at'] as String? ?? '').replaceAll('T', '  ');
              final timeStr = createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryColor.withAlpha(30),
                  child: Text('$itemsCount', style: const TextStyle(color: AppTheme.primaryColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                title: Text('$amount دينار', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('$receipt  |  $timeStr', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                trailing: const Icon(Icons.chevron_left, color: AppTheme.textSecondary),
                onTap: () => _showSaleDetails(id, amount, discountAmount, timeStr),
              );
            }),
          ],
        ),
      ),
    );
  }
}

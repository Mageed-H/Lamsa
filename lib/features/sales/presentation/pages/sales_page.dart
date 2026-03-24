import 'package:flutter/material.dart';
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';

enum SalesFilter { today, thisWeek, thisMonth, customMonth, all }

class SalesPage extends StatefulWidget {
  const SalesPage({Key? key}) : super(key: key);

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  Map<String, int> _summary = {};
  List<Map<String, dynamic>> _sales = [];
  Map<String, int> _filterSummary = {};
  bool _isLoading = true;
  SalesFilter _activeFilter = SalesFilter.today;
  DateTime? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // حساب بداية ونهاية الفترة حسب الفلتر
  (String from, String to) _getDateRange(SalesFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case SalesFilter.today:
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        return (today.toIso8601String(), tomorrow.toIso8601String());
      case SalesFilter.thisWeek:
        final weekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday % 7));
        final weekEnd = weekStart.add(const Duration(days: 7));
        return (weekStart.toIso8601String(), weekEnd.toIso8601String());
      case SalesFilter.thisMonth:
        final monthStart = DateTime(now.year, now.month, 1);
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        return (monthStart.toIso8601String(), monthEnd.toIso8601String());
      case SalesFilter.customMonth:
        final m = _selectedMonth ?? now;
        final monthStart = DateTime(m.year, m.month, 1);
        final monthEnd = DateTime(m.year, m.month + 1, 1);
        return (monthStart.toIso8601String(), monthEnd.toIso8601String());
      case SalesFilter.all:
        return ('2000-01-01', '2100-01-01');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final summary = await DatabaseHelper.instance.getSalesSummary();
    final range = _getDateRange(_activeFilter);
    final sales = await DatabaseHelper.instance.getSalesByDateRange(range.$1, range.$2);
    final filterSummary = await DatabaseHelper.instance.getSalesSummaryByDateRange(range.$1, range.$2);
    if (mounted) {
      setState(() {
        _summary = summary;
        _sales = sales;
        _filterSummary = filterSummary;
        _isLoading = false;
      });
    }
  }

  void _setFilter(SalesFilter filter) {
    setState(() => _activeFilter = filter);
    _loadData();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      helpText: 'اختر شهر',
    );
    if (picked != null) {
      _selectedMonth = DateTime(picked.year, picked.month, 1);
      _setFilter(SalesFilter.customMonth);
    }
  }

  String _getFilterLabel() {
    switch (_activeFilter) {
      case SalesFilter.today: return 'اليوم';
      case SalesFilter.thisWeek: return 'هذا الأسبوع';
      case SalesFilter.thisMonth: return 'هذا الشهر';
      case SalesFilter.customMonth:
        if (_selectedMonth != null) {
          return '${_selectedMonth!.year}/${_selectedMonth!.month}';
        }
        return 'شهر محدد';
      case SalesFilter.all: return 'الكل';
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
                  // فلاتر الوقت
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('اليوم', SalesFilter.today, Icons.today),
                        const SizedBox(width: 6),
                        _buildFilterChip('هذا الأسبوع', SalesFilter.thisWeek, Icons.date_range),
                        const SizedBox(width: 6),
                        _buildFilterChip('هذا الشهر', SalesFilter.thisMonth, Icons.calendar_month),
                        const SizedBox(width: 6),
                        _buildMonthPickerChip(),
                        const SizedBox(width: 6),
                        _buildFilterChip('الكل', SalesFilter.all, Icons.all_inclusive),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ملخص الفترة المحددة
                  if (_activeFilter != SalesFilter.today && _activeFilter != SalesFilter.all)
                    _buildPeriodSummary(),
                  // عنوان القائمة
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'فواتير ${_getFilterLabel()} (${_sales.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary),
                    ),
                  ),
                  // قائمة الفواتير
                  ..._sales.map((sale) => _buildSaleCard(sale)),
                  if (_sales.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'لا توجد مبيعات في ${_getFilterLabel()}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, SalesFilter filter, IconData icon) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => _setFilter(filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : AppTheme.neutralLightColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: isActive ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthPickerChip() {
    final isActive = _activeFilter == SalesFilter.customMonth;
    final label = isActive && _selectedMonth != null
        ? '${_selectedMonth!.year}/${_selectedMonth!.month}'
        : 'شهر محدد';
    return GestureDetector(
      onTap: _pickMonth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : AppTheme.neutralLightColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_calendar, size: 16, color: isActive ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: isActive ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSummary() {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.highlightColor.withAlpha(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatColumn('الإيرادات', '${_filterSummary['revenue'] ?? 0} د', AppTheme.primaryColor),
            _buildStatColumn('الأرباح', '${_filterSummary['profit'] ?? 0} د', AppTheme.successColor),
            _buildStatColumn('الفواتير', '${_filterSummary['count'] ?? 0}', AppTheme.textPrimary),
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

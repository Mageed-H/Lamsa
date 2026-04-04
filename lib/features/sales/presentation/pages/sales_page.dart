import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';

enum SalesFilter { today, thisWeek, thisMonth, customMonth, customRange, all }

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
  DateTimeRange? _selectedRange;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.revision.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    DatabaseHelper.revision.removeListener(_loadData);
    super.dispose();
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
      case SalesFilter.customRange:
        if (_selectedRange != null) {
          final from = DateTime(_selectedRange!.start.year, _selectedRange!.start.month, _selectedRange!.start.day);
          final to = DateTime(_selectedRange!.end.year, _selectedRange!.end.month, _selectedRange!.end.day).add(const Duration(days: 1));
          return (from.toIso8601String(), to.toIso8601String());
        }
        return ('2000-01-01', '2100-01-01');
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _selectedRange ?? DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now,
      ),
      helpText: 'اختر الفترة',
      saveText: 'تطبيق',
      cancelText: 'إلغاء',
    );
    if (picked != null) {
      _selectedRange = picked;
      _setFilter(SalesFilter.customRange);
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
      case SalesFilter.customRange:
        if (_selectedRange != null) {
          final s = _selectedRange!.start;
          final e = _selectedRange!.end;
          return '${s.month}/${s.day} - ${e.month}/${e.day}';
        }
        return 'فترة محددة';
      case SalesFilter.all: return 'الكل';
    }
  }

  // ─── نسخ احتياطي لقاعدة البيانات ───
  Future<void> _backupDatabase() async {
    try {
      final path = await DatabaseHelper.instance.backupDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم النسخ الاحتياطي بنجاح ✓\n$path', style: const TextStyle(fontSize: 12)),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل النسخ الاحتياطي: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ─── تصدير تقرير المبيعات كـ PDF ───
  Future<void> _exportSalesReport() async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    final storeName = settings['store_name'] ?? 'لمسة';
    final currency = settings['currency'] ?? 'دينار';

    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    final arabicFont = pw.Font.ttf(fontData);

    final filterLabel = _getFilterLabel();
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // اسم الفلتر بالإنكليزي للملف
    String filterTag;
    switch (_activeFilter) {
      case SalesFilter.today: filterTag = 'Today';
      case SalesFilter.thisWeek: filterTag = 'Week';
      case SalesFilter.thisMonth: filterTag = 'Month';
      case SalesFilter.customMonth: filterTag = 'Month_Custom';
      case SalesFilter.customRange: filterTag = 'Range';
      case SalesFilter.all: filterTag = 'All';
    }

    // تحديد الملخص حسب الفلتر
    int reportRevenue, reportProfit, reportCount;
    if (_activeFilter == SalesFilter.today) {
      reportRevenue = _summary['today_revenue'] ?? 0;
      reportProfit = _summary['today_profit'] ?? 0;
      reportCount = _summary['today_count'] ?? 0;
    } else if (_activeFilter == SalesFilter.all) {
      reportRevenue = _summary['all_revenue'] ?? 0;
      reportProfit = _summary['all_profit'] ?? 0;
      reportCount = _summary['all_count'] ?? 0;
    } else {
      reportRevenue = _filterSummary['revenue'] ?? 0;
      reportProfit = _filterSummary['profit'] ?? 0;
      reportCount = _filterSummary['count'] ?? 0;
    }
    final reportCapital = reportRevenue - reportProfit;

    pw.TextStyle hStyle() => pw.TextStyle(font: arabicFont, fontSize: 20, fontWeight: pw.FontWeight.bold);
    pw.TextStyle subStyle() => pw.TextStyle(font: arabicFont, fontSize: 12);
    pw.TextStyle cellStyle({bool bold = false}) =>
        pw.TextStyle(font: arabicFont, fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null);

    pw.Widget pdfCell(String text, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text, style: cellStyle(bold: bold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
    );

    pw.Widget statBox(String label, String value) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(children: [
        pw.Text(value, style: pw.TextStyle(font: arabicFont, fontSize: 16, fontWeight: pw.FontWeight.bold), textDirection: pw.TextDirection.rtl),
        pw.SizedBox(height: 4),
        pw.Text(label, style: pw.TextStyle(font: arabicFont, fontSize: 10), textDirection: pw.TextDirection.rtl),
      ]),
    );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Center(child: pw.Text(storeName, style: hStyle(), textDirection: pw.TextDirection.rtl)),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('تقرير المبيعات — $filterLabel', style: subStyle(), textDirection: pw.TextDirection.rtl)),
          pw.Center(child: pw.Text(dateStr, style: subStyle())),
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              statBox('الإيرادات', '$reportRevenue $currency'),
              statBox('رأس المال', '$reportCapital $currency'),
              statBox('الأرباح', '$reportProfit $currency'),
              statBox('الفواتير', '$reportCount'),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(0.8),
              6: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pdfCell('القطع', bold: true),
                  pdfCell('الخصم', bold: true),
                  pdfCell('الربح', bold: true),
                  pdfCell('رأس المال', bold: true),
                  pdfCell('المبلغ', bold: true),
                  pdfCell('#', bold: true),
                  pdfCell('التاريخ', bold: true),
                ],
              ),
              ..._sales.map((sale) {
                final id = sale['id'] as int;
                final amount = sale['total_amount'] as int? ?? 0;
                final profit = sale['total_profit'] as int? ?? 0;
                final cost = amount - profit;
                final items = sale['items_count'] as int? ?? 0;
                final discount = sale['discount_amount'] as int? ?? 0;
                final date = (sale['created_at'] as String? ?? '').replaceAll('T', ' ');
                final ds = date.length >= 16 ? date.substring(0, 16) : date;
                return pw.TableRow(children: [
                  pdfCell('$items'),
                  pdfCell(discount > 0 ? '$discount' : '-'),
                  pdfCell('$profit'),
                  pdfCell('$cost'),
                  pdfCell('$amount'),
                  pdfCell('$id'),
                  pdfCell(ds),
                ]);
              }),
            ],
          ),
        ],
      ),
    );

    // حفظ الملف على سطح المكتب
    final pdfBytes = await doc.save();
    final safeDate = dateStr.replaceAll('/', '-');
    final fileName = 'Sales_Report_${filterTag}_$safeDate.pdf';
    final userProfile = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
    final sep = Platform.pathSeparator;
    final desktop = '$userProfile${sep}Desktop';
    final desktopDir = Directory(desktop);
    if (!await desktopDir.exists()) await desktopDir.create(recursive: true);
    final file = File('$desktop$sep$fileName');
    await file.writeAsBytes(pdfBytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ التقرير على سطح المكتب ✓\n$fileName'),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup),
            onPressed: _backupDatabase,
            tooltip: 'نسخ احتياطي',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _sales.isEmpty ? null : _exportSalesReport,
            tooltip: 'تصدير تقرير PDF',
          ),
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
                        _buildDateRangeChip(),
                        const SizedBox(width: 6),
                        _buildFilterChip('الكل', SalesFilter.all, Icons.all_inclusive),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ملخص الفترة المحددة
                  if (_activeFilter != SalesFilter.today && _activeFilter != SalesFilter.all)
                    _buildPeriodSummary(),
                  if (_activeFilter == SalesFilter.customRange && _selectedRange != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_selectedRange!.start.year}/${_selectedRange!.start.month}/${_selectedRange!.start.day}  ←  ${_selectedRange!.end.year}/${_selectedRange!.end.month}/${_selectedRange!.end.day}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
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

  Widget _buildDateRangeChip() {
    final isActive = _activeFilter == SalesFilter.customRange;
    final label = isActive && _selectedRange != null
        ? '${_selectedRange!.start.month}/${_selectedRange!.start.day} - ${_selectedRange!.end.month}/${_selectedRange!.end.day}'
        : 'فترة محددة';
    return GestureDetector(
      onTap: _pickDateRange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : AppTheme.neutralLightColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_outlined, size: 16, color: isActive ? Colors.white : AppTheme.textSecondary),
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
    final rev = _filterSummary['revenue'] ?? 0;
    final pro = _filterSummary['profit'] ?? 0;
    final capital = rev - pro;
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
            _buildStatColumn('الإيرادات', '$rev د', AppTheme.primaryColor),
            _buildStatColumn('رأس المال', '$capital د', AppTheme.warningColor),
            _buildStatColumn('الأرباح', '$pro د', AppTheme.successColor),
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
    final capital = revenue - profit;
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
                _buildStatColumn('رأس المال', '$capital د', AppTheme.warningColor),
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
    final discountAmount = sale['discount_amount'] as int? ?? 0;
    final createdAt = (sale['created_at'] as String? ?? '').replaceAll('T', '  ');
    final timeStr = createdAt.length >= 16 ? createdAt.substring(0, 16) : createdAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor,
          child: Text('$itemsCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Text('$totalAmount دينار', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (discountAmount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('خصم $discountAmount', style: const TextStyle(color: AppTheme.errorColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        subtitle: Text('ربح: $totalProfit د  |  $timeStr', style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_left, color: AppTheme.textSecondary),
        onTap: () => _showSaleDetails(saleId, totalAmount, discountAmount, timeStr),
      ),
    );
  }

  Future<void> _showSaleDetails(int saleId, int totalAmount, int discountAmount, String time) async {
    final items = await DatabaseHelper.instance.getSaleItems(saleId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SaleDetailsSheet(
        saleId: saleId,
        totalAmount: totalAmount,
        discountAmount: discountAmount,
        time: time,
        items: items,
        onReturnDone: () {
          _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم الإرجاع وإعادة المخزون بنجاح ✓'),
                backgroundColor: AppTheme.successColor,
              ),
            );
          }
        },
      ),
    );
  }
}

// ─── BottomSheet تفاصيل الفاتورة مع إرجاع جزئي ───
class _SaleDetailsSheet extends StatefulWidget {
  final int saleId;
  final int totalAmount;
  final int discountAmount;
  final String time;
  final List<Map<String, dynamic>> items;
  final VoidCallback onReturnDone;

  const _SaleDetailsSheet({
    required this.saleId,
    required this.totalAmount,
    required this.discountAmount,
    required this.time,
    required this.items,
    required this.onReturnDone,
  });

  @override
  State<_SaleDetailsSheet> createState() => _SaleDetailsSheetState();
}

class _SaleDetailsSheetState extends State<_SaleDetailsSheet> {
  // كمية الإرجاع لكل بند: {sale_item_id: return_qty}
  late Map<int, int> _returnQtys;
  bool _isReturning = false;

  @override
  void initState() {
    super.initState();
    _returnQtys = {
      for (final item in widget.items) item['id'] as int: 0,
    };
  }

  int get _totalReturnCount => _returnQtys.values.fold(0, (s, v) => s + v);

  int get _totalReturnAmount {
    int total = 0;
    for (final item in widget.items) {
      final id = item['id'] as int;
      final unitPrice = item['unit_price'] as int? ?? 0;
      total += unitPrice * (_returnQtys[id] ?? 0);
    }
    return total;
  }

  bool get _isReturnAll {
    for (final item in widget.items) {
      final id = item['id'] as int;
      final qty = item['quantity'] as int? ?? 0;
      if ((_returnQtys[id] ?? 0) != qty) return false;
    }
    return true;
  }

  Future<void> _doReturn() async {
    // فلترة الأصفار
    final toReturn = Map<int, int>.fromEntries(
      _returnQtys.entries.where((e) => e.value > 0),
    );
    if (toReturn.isEmpty) return;

    final label = _isReturnAll ? 'إرجاع الفاتورة كاملة' : 'إرجاع $_totalReturnCount قطعة';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(label, style: const TextStyle(color: AppTheme.errorColor)),
        content: Text(
          _isReturnAll
              ? 'سيتم حذف الفاتورة بالكامل وإرجاع المخزون.\nهل أنت متأكد؟'
              : 'سيتم إرجاع $_totalReturnCount قطعة بقيمة $_totalReturnAmount دينار وإعادتها للمخزون.\nهل أنت متأكد؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('تأكيد الإرجاع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isReturning = true);
    final success = _isReturnAll
        ? await DatabaseHelper.instance.returnSale(widget.saleId)
        : await DatabaseHelper.instance.partialReturnSale(widget.saleId, toReturn);
    if (context.mounted) Navigator.pop(context);
    if (success) widget.onReturnDone();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('فاتورة #${widget.saleId}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              Text(widget.time, style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
          const Divider(),
          // بنود الفاتورة مع أزرار إرجاع جزئي
          ...widget.items.map((item) {
            final itemId = item['id'] as int;
            final name = item['product_name'] as String? ?? '';
            final qty = item['quantity'] as int? ?? 0;
            final unitPrice = item['unit_price'] as int? ?? 0;
            final retQty = _returnQtys[itemId] ?? 0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('${unitPrice * qty} د  |  x$qty', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  // أزرار إرجاع
                  Container(
                    decoration: BoxDecoration(
                      color: retQty > 0 ? AppTheme.errorColor.withValues(alpha: 0.08) : AppTheme.neutralLightColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          color: AppTheme.errorColor,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: retQty > 0
                              ? () => setState(() => _returnQtys[itemId] = retQty - 1)
                              : null,
                        ),
                        Text(
                          '$retQty',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: retQty > 0 ? AppTheme.errorColor : AppTheme.textSecondary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          color: AppTheme.errorColor,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: retQty < qty
                              ? () => setState(() => _returnQtys[itemId] = retQty + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (widget.discountAmount > 0) ...[
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الخصم', style: TextStyle(fontSize: 14, color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                Text('- ${widget.discountAmount} دينار', style: const TextStyle(fontSize: 14, color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('المجموع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${widget.totalAmount} دينار', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            ],
          ),
          const SizedBox(height: 12),
          // شريط الإرجاع (يظهر فقط لما تختار كمية)
          if (_totalReturnCount > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isReturnAll ? 'إرجاع كامل' : 'إرجاع $_totalReturnCount قطعة',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.errorColor),
                  ),
                  Text(
                    '$_totalReturnAmount دينار',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.errorColor, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // زر الإرجاع
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _totalReturnCount > 0 ? AppTheme.errorColor : AppTheme.neutralColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _isReturning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.undo),
              label: Text(
                _totalReturnCount > 0
                    ? (_isReturnAll ? 'إرجاع الفاتورة كاملة' : 'تأكيد الإرجاع الجزئي')
                    : 'اختر القطع المراد إرجاعها',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _totalReturnCount > 0 && !_isReturning ? _doReturn : null,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TopSellingPage extends StatefulWidget {
  const TopSellingPage({Key? key}) : super(key: key);

  @override
  State<TopSellingPage> createState() => _TopSellingPageState();
}

class _TopSellingPageState extends State<TopSellingPage> {
  List<Map<String, dynamic>> _topProducts = [];
  Map<String, dynamic> _generalStats = {};
  bool _isLoading = true;

  // ─── فلاتر ───
  int _limit = 20;
  String? _filterCategory;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  bool _showFilters = false;

  // قائمة الأقسام
  List<String> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // جلب الأقسام
    final cats = await DatabaseHelper.instance.getAllCategories();
    _categories = cats.where((c) => c.isNotEmpty).toList();

    // تاريخ البداية والنهاية بصيغة string
    String? startDate;
    String? endDate;
    if (_filterStartDate != null) {
      startDate = _filterStartDate!.toIso8601String().substring(0, 10);
    }
    if (_filterEndDate != null) {
      // نضيف يوم كامل ليوم الانتهاء يشمل كامل اليوم
      endDate = _filterEndDate!.add(const Duration(days: 1)).toIso8601String().substring(0, 10);
    }

    final topProducts = await DatabaseHelper.instance.getTopSellingProducts(
      limit: _limit,
      category: _filterCategory,
      startDate: startDate,
      endDate: endDate,
    );
    final generalStats = await DatabaseHelper.instance.getGeneralSalesStats(
      startDate: startDate,
      endDate: endDate,
    );
    if (mounted) {
      setState(() {
        _topProducts = topProducts;
        _generalStats = generalStats;
        _isLoading = false;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _filterCategory = null;
      _filterStartDate = null;
      _filterEndDate = null;
      _limit = 20;
    });
    _loadData();
  }

  bool get _hasActiveFilters =>
      _filterCategory != null || _filterStartDate != null || _filterEndDate != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأكثر مبيعاً', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
            tooltip: 'الفلاتر',
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 0) {
                _showLimitDialog();
              } else if (v == 1) {
                _exportPDF();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    const Icon(Icons.format_list_numbered, size: 18),
                    const SizedBox(width: 8),
                    Text('الحد: $_limit'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: AppTheme.errorColor, size: 18),
                    const SizedBox(width: 8),
                    const Text('تصدير PDF'),
                  ],
                ),
              ),
            ],
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
                  // ─── شريط الفلاتر ───
                  if (_showFilters) _buildFilterBar(),
                  // ─── روابط الفلاتر النشطة ───
                  if (_hasActiveFilters) _buildActiveFilterChips(),
                  // ─── الإحصائيات العامة ───
                  _buildGeneralStats(),
                  const SizedBox(height: 16),
                  // ─── عنوان القائمة ───
                  Row(
                    children: [
                      const Text('المنتجات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      Text('${_topProducts.length} منتج', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ─── قائمة المنتجات ───
                  if (_topProducts.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.trending_up, size: 48, color: AppTheme.textSecondary),
                            SizedBox(height: 8),
                            Text('لا توجد بيانات مبيعات', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(_topProducts.length, (i) => _buildProductCard(i, _topProducts[i])),
                ],
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════════════
  // فلاتر
  // ═══════════════════════════════════════════════════

  Widget _buildFilterBar() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                const Text('الفلاتر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (_hasActiveFilters)
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('مسح الكل'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ─── القسم ───
            DropdownButtonFormField<String>(
              value: _filterCategory,
              decoration: InputDecoration(
                labelText: 'القسم',
                prefixIcon: const Icon(Icons.category, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                ..._categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
              ],
              onChanged: (v) {
                setState(() => _filterCategory = v);
                _loadData();
              },
            ),
            const SizedBox(height: 10),
            // ─── التاريخ ───
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    label: 'من تاريخ',
                    date: _filterStartDate,
                    onTap: () => _pickDate(isStart: true),
                    onClear: () { setState(() => _filterStartDate = null); _loadData(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDateField(
                    label: 'إلى تاريخ',
                    date: _filterEndDate,
                    onTap: () => _pickDate(isStart: false),
                    onClear: () { setState(() => _filterEndDate = null); _loadData(); },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today, size: 16),
          suffixIcon: date != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: onClear,
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        child: Text(
          date != null ? '${date.day}/${date.month}/${date.year}' : 'اختر',
          style: TextStyle(
            color: date != null ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_filterStartDate ?? now) : (_filterEndDate ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _filterStartDate = picked;
        } else {
          _filterEndDate = picked;
        }
      });
      _loadData();
    }
  }

  Widget _buildActiveFilterChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (_filterCategory != null)
            Chip(
              label: Text('القسم: $_filterCategory', style: const TextStyle(fontSize: 12)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () { setState(() => _filterCategory = null); _loadData(); },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          if (_filterStartDate != null)
            Chip(
              label: Text('من: ${_filterStartDate!.day}/${_filterStartDate!.month}/${_filterStartDate!.year}', style: const TextStyle(fontSize: 12)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () { setState(() => _filterStartDate = null); _loadData(); },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          if (_filterEndDate != null)
            Chip(
              label: Text('إلى: ${_filterEndDate!.day}/${_filterEndDate!.month}/${_filterEndDate!.year}', style: const TextStyle(fontSize: 12)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () { setState(() => _filterEndDate = null); _loadData(); },
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }

  void _showLimitDialog() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('عرض أعلى...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ...[10, 20, 50, 100].map((n) => ListTile(
                    leading: Icon(
                      _limit == n ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: AppTheme.primaryColor,
                    ),
                    title: Text('$n منتج'),
                    onTap: () {
                      setState(() => _limit = n);
                      Navigator.pop(ctx);
                      _loadData();
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // الإحصائيات العامة
  // ═══════════════════════════════════════════════════

  Widget _buildGeneralStats() {
    final totalRevenue = (_generalStats['total_revenue'] ?? 0) as int;
    final totalProfit = (_generalStats['total_profit'] ?? 0) as int;
    final totalItems = (_generalStats['total_items'] ?? 0) as int;
    final totalSales = (_generalStats['total_sales'] ?? 0) as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('إحصائيات المبيعات العامة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatCard('إجمالي المبيعات', '$totalSales فاتورة', Icons.receipt_long, AppTheme.primaryColor),
            const SizedBox(width: 8),
            _buildStatCard('الإيراد', '${_formatNumber(totalRevenue)} د', Icons.attach_money, AppTheme.successColor),
            const SizedBox(width: 8),
            _buildStatCard('الربح', '${_formatNumber(totalProfit)} د', Icons.trending_up, AppTheme.warningColor),
            const SizedBox(width: 8),
            _buildStatCard('القطع المباعة', '$totalItems', Icons.shopping_cart, AppTheme.errorColor),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // كرت المنتج
  // ═══════════════════════════════════════════════════

  Widget _buildProductCard(int rank, Map<String, dynamic> product) {
    final name = product['name'] as String? ?? '';
    final category = product['category'] as String? ?? '';
    final colorStr = product['color'] as String? ?? '';
    final totalSold = (product['total_sold'] ?? 0) as int;
    final totalRevenue = (product['total_revenue'] ?? 0) as int;
    final totalProfit = (product['total_profit'] ?? 0) as int;

    Color rankColor;
    if (rank == 0) {
      rankColor = const Color(0xFFFFD700);
    } else if (rank == 1) {
      rankColor = const Color(0xFFC0C0C0);
    } else if (rank == 2) {
      rankColor = const Color(0xFFCD7F32);
    } else {
      rankColor = AppTheme.textSecondary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // الترتيب
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: rankColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: rankColor.withOpacity(0.3)),
              ),
              child: Center(
                child: Text('${rank + 1}', style: TextStyle(color: rankColor, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
            const SizedBox(width: 12),
            // معلومات المنتج
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // اللون
                      if (colorStr.isNotEmpty) ...[
                        _parseColorDot(colorStr),
                        const SizedBox(width: 6),
                      ],
                      // الاسم
                      Expanded(
                        child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ],
                  ),
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(category, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildMiniStat(Icons.shopping_bag, '$totalSold قطعة', AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      _buildMiniStat(Icons.attach_money, '${_formatNumber(totalRevenue)} د', AppTheme.successColor),
                      const SizedBox(width: 12),
                      _buildMiniStat(Icons.trending_up, '${_formatNumber(totalProfit)} د', AppTheme.warningColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parseColorDot(String colorStr) {
    final c = _hexToColor(colorStr);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: c == Colors.white ? Colors.grey : c, width: 1.5),
      ),
    );
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  Widget _buildMiniStat(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  // ═══════════════════════════════════════════════════
  // تصدير PDF
  // ═══════════════════════════════════════════════════

  Future<void> _exportPDF() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      final aroFont = pw.Font.ttf(fontData);
      final doc = pw.Document();

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('تقرير الأكثر مبيعاً', style: pw.TextStyle(font: aroFont, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('تاريخ: ${DateTime.now().toString().substring(0, 16)}', style: pw.TextStyle(font: aroFont, fontSize: 10)),
                if (_hasActiveFilters) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('فلاتر: ${_buildFilterSummaryText()}', style: pw.TextStyle(font: aroFont, fontSize: 10)),
                ],
                pw.SizedBox(height: 16),
                // الإحصائيات العامة
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8)),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      _pdfStat('المبيعات', '${_generalStats['total_sales'] ?? 0}', aroFont),
                      _pdfStat('الإيراد', '${_generalStats['total_revenue'] ?? 0} د', aroFont),
                      _pdfStat('الربح', '${_generalStats['total_profit'] ?? 0} د', aroFont),
                      _pdfStat('القطع', '${_generalStats['total_items'] ?? 0}', aroFont),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                // جدول المنتجات
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: aroFont, fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: pw.TextStyle(font: aroFont, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  cellAlignment: pw.Alignment.centerRight,
                  headerAlignment: pw.Alignment.centerRight,
                  headers: ['#', 'المنتج', 'اللون', 'القسم', 'الكمية', 'الإيراد', 'الربح'],
                  data: _topProducts.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final p = e.value;
                    return [
                      '$i',
                      '${p['name']}',
                      '${p['color'] ?? ''}',
                      '${p['category'] ?? ''}',
                      '${p['total_sold']}',
                      '${p['total_revenue']} د',
                      '${p['total_profit']} د',
                    ];
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ));

      await Printing.layoutPdf(onLayout: (format) async => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير PDF: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  pw.Widget _pdfStat(String label, String value, pw.Font font) {
    return pw.Column(
      children: [
        pw.Text(value, style: pw.TextStyle(font: font, fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8)),
      ],
    );
  }

  String _buildFilterSummaryText() {
    final parts = <String>[];
    if (_filterCategory != null) parts.add('قسم: $_filterCategory');
    if (_filterStartDate != null) parts.add('من: ${_filterStartDate!.day}/${_filterStartDate!.month}/${_filterStartDate!.year}');
    if (_filterEndDate != null) parts.add('إلى: ${_filterEndDate!.day}/${_filterEndDate!.month}/${_filterEndDate!.year}');
    return parts.join(' | ');
  }
}

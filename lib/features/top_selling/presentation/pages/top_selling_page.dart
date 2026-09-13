import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:csv/csv.dart';

class TopSellingPage extends StatefulWidget {
  const TopSellingPage({Key? key}) : super(key: key);

  @override
  State<TopSellingPage> createState() => _TopSellingPageState();
}

class _TopSellingPageState extends State<TopSellingPage> {
  List<Map<String, dynamic>> _topProducts = [];
  Map<String, dynamic> _generalStats = {};
  bool _isLoading = true;
  int _limit = 20;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final topProducts = await DatabaseHelper.instance.getTopSellingProducts(limit: _limit);
    final generalStats = await DatabaseHelper.instance.getGeneralSalesStats();
    if (mounted) {
      setState(() {
        _topProducts = topProducts;
        _generalStats = generalStats;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأكثر مبيعاً', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) => setState(() { _limit = v; _loadData(); }),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 10, child: Text('أعلى 10')),
              const PopupMenuItem(value: 20, child: Text('أعلى 20')),
              const PopupMenuItem(value: 50, child: Text('أعلى 50')),
              const PopupMenuItem(value: 100, child: Text('الكل')),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download),
            onSelected: (v) {
              if (v == 'pdf') _exportPDF();
              if (v == 'csv') _exportCSV();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'pdf', child: Row(
                children: [Icon(Icons.picture_as_pdf, color: AppTheme.errorColor, size: 18), SizedBox(width: 8), Text('تصدير PDF')],
              )),
              const PopupMenuItem(value: 'csv', child: Row(
                children: [Icon(Icons.table_chart, color: AppTheme.successColor, size: 18), SizedBox(width: 8), Text('تصدير CSV')],
              )),
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
                  // ─── الإحصائيات العامة ───
                  _buildGeneralStats(),
                  const SizedBox(height: 16),
                  // ─── قائمة المنتجات ───
                  if (_topProducts.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Icon(Icons.trending_up, size: 48, color: AppTheme.textSecondary),
                            SizedBox(height: 8),
                            Text('لا توجد بيانات مبيعات بعد', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
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

  Widget _buildProductCard(int rank, Map<String, dynamic> product) {
    final name = product['name'] as String? ?? '';
    final totalSold = (product['total_sold'] ?? 0) as int;
    final totalRevenue = (product['total_revenue'] ?? 0) as int;
    final totalProfit = (product['total_profit'] ?? 0) as int;

    Color rankColor;
    if (rank == 0) {
      rankColor = const Color(0xFFFFD700); // ذهبي
    } else if (rank == 1) {
      rankColor = const Color(0xFFC0C0C0); // فضي
    } else if (rank == 2) {
      rankColor = const Color(0xFFCD7F32); // برونزي
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
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

  // ─── تصدير PDF ───
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
                  headers: ['#', 'المنتج', 'الكمية', 'الإيراد', 'الربح'],
                  data: _topProducts.asMap().entries.map((e) {
                    final i = e.key + 1;
                    final p = e.value;
                    return [
                      '$i',
                      '${p['name']}',
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

  // ─── تصدير CSV ───
  Future<void> _exportCSV() async {
    try {
      final rows = <List<String>>[
        ['#', 'المنتج', 'الكمية المباعة', 'إجمالي الإيراد', 'إجمالي الربح'],
      ];
      for (var i = 0; i < _topProducts.length; i++) {
        final p = _topProducts[i];
        rows.add([
          '${i + 1}',
          '${p['name']}',
          '${p['total_sold']}',
          '${p['total_revenue']}',
          '${p['total_profit']}',
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/top_selling_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ الملف: ${file.path}'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير CSV: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

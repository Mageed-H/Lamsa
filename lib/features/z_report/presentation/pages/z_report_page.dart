import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';

class ZReportPage extends StatefulWidget {
  const ZReportPage({Key? key}) : super(key: key);

  @override
  State<ZReportPage> createState() => _ZReportPageState();
}

class _ZReportPageState extends State<ZReportPage> {
  Map<String, dynamic> _data = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getZReportData();
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  String _todayDate() {
    final now = DateTime.now();
    return '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final revenue = _data['revenue'] as int? ?? 0;
    final profit = _data['profit'] as int? ?? 0;
    final expenses = _data['expenses'] as int? ?? 0;
    final netCash = revenue - expenses;
    final salesCount = _data['sales_count'] as int? ?? 0;
    final itemsSold = _data['items_sold'] as int? ?? 0;
    final debtsCollected = _data['debts_collected'] as int? ?? 0;
    final shopDebtsCollected = _data['shop_debts_collected'] as int? ?? 0;
    final topProducts = (_data['top_products'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير نهاية اليوم', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _data.isEmpty ? null : _printZReport,
            tooltip: 'طباعة التقرير',
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
                  // التاريخ
                  Center(
                    child: Text(
                      _todayDate(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // الإيرادات vs المصروفات
                  Row(
                    children: [
                      Expanded(child: _buildBigStat('إيراد المبيعات', revenue, AppTheme.successColor, Icons.attach_money)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildBigStat('المصروفات', expenses, AppTheme.errorColor, Icons.receipt_long)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // صافي الكاش
                  Card(
                    color: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              const Text('صافي الكاش', style: TextStyle(color: Colors.white70, fontSize: 14)),
                              Text(
                                '$netCash د.ع',
                                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // الأرقام الفرعية
                  Row(
                    children: [
                      Expanded(child: _buildSmallStat('عدد المبيعات', '$salesCount', AppTheme.primaryColor)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildSmallStat('القطع المباعة', '$itemsSold', AppTheme.warningColor)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildSmallStat('الربح', '$profit د.ع', AppTheme.successColor)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (debtsCollected > 0 || shopDebtsCollected > 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('الديون المسددة اليوم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            if (debtsCollected > 0)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('ديون الزبائن', style: TextStyle(fontSize: 13)),
                                  Text('$debtsCollected د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.successColor)),
                                ],
                              ),
                            if (shopDebtsCollected > 0)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('ديون المحل', style: TextStyle(fontSize: 13)),
                                  Text('$shopDebtsCollected د.ع', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.successColor)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  // أفضل المنتجات
                  if (topProducts.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.star, color: AppTheme.warningColor, size: 20),
                                SizedBox(width: 8),
                                Text('أفضل المنتجات مبيعاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...topProducts.asMap().entries.map((entry) {
                              final p = entry.value;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                                      child: Text(
                                        '${entry.key + 1}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(p['product_name'] ?? '', style: const TextStyle(fontSize: 13))),
                                    Text('x${p['total_qty']}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                    const SizedBox(width: 12),
                                    Text('${p['total_revenue'] ?? 0} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildBigStat(String label, int value, Color color, IconData icon) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(
              '$value د.ع',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallStat(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Future<void> _printZReport() async {
    try {
      final arabic = await PdfGoogleFonts.cairoRegular();
      final arabicBold = await PdfGoogleFonts.cairoBold();
      final revenue = _data['revenue'] as int? ?? 0;
      final profit = _data['profit'] as int? ?? 0;
      final expenses = _data['expenses'] as int? ?? 0;
      final netCash = revenue - expenses;
      final salesCount = _data['sales_count'] as int? ?? 0;
      final itemsSold = _data['items_sold'] as int? ?? 0;
      final topProducts = (_data['top_products'] as List?) ?? [];

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('تقرير نهاية اليوم',
                style: pw.TextStyle(font: arabicBold, fontSize: 20)),
          ),
          pw.Text(_todayDate(), style: pw.TextStyle(font: arabic, fontSize: 14)),
          pw.SizedBox(height: 16),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            color: PdfColors.green50,
            child: pw.Text('صافي الكاش: $netCash دينار',
                style: pw.TextStyle(font: arabicBold, fontSize: 16)),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('إيراد المبيعات: $revenue', style: pw.TextStyle(font: arabic, fontSize: 12)),
              pw.Text('المصروفات: $expenses', style: pw.TextStyle(font: arabic, fontSize: 12)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('عدد المبيعات: $salesCount', style: pw.TextStyle(font: arabic, fontSize: 12)),
              pw.Text('القطع المباعة: $itemsSold', style: pw.TextStyle(font: arabic, fontSize: 12)),
              pw.Text('الربح: $profit', style: pw.TextStyle(font: arabic, fontSize: 12)),
            ],
          ),
          if (topProducts.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('أفضل المنتجات مبيعاً',
                style: pw.TextStyle(font: arabicBold, fontSize: 14)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: arabicBold, fontSize: 11),
              cellStyle: pw.TextStyle(font: arabic, fontSize: 10),
              headers: ['المنتج', 'الكمية', 'الإيراد'],
              data: topProducts.map((p) => [
                '${p['product_name'] ?? ''}',
                '${p['total_qty'] ?? 0}',
                '${p['total_revenue'] ?? 0} د.ع',
              ]).toList(),
            ),
          ],
        ],
      ));

      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

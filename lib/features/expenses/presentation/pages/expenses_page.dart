import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:lamsa/core/database/database_helper.dart';
import 'package:lamsa/core/theme/app_theme.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({Key? key}) : super(key: key);

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<Map<String, dynamic>> _expenses = [];
  Map<String, int> _summary = {};
  bool _isLoading = true;

  /// العرض التدريجي — عدد الأيام الظاهرة
  int _visibleDays = 7;

  static const List<String> _expenseCategories = [
    'يوميات',
    'مشتريات',
    'إيجار',
    'رواتب',
    'فواتير (كهرباء/ماء/غاز)',
    'صيانة',
    'نقل وشحن',
    'إعلانات',
    'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    DatabaseHelper.expensesRevision.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    DatabaseHelper.expensesRevision.removeListener(_loadData);
    super.dispose();
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(0, 16).replaceAll('T', '  ') : iso;
    }
  }

  String _formatDateShort(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final expenses = await DatabaseHelper.instance.getAllExpenses();
    final summary = await DatabaseHelper.instance.getExpensesSummary();
    if (mounted) {
      setState(() {
        _expenses = expenses;
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  Future<void> _printExpensesPdf() async {
    try {
      final arabic = await PdfGoogleFonts.cairoRegular();
      final arabicBold = await PdfGoogleFonts.cairoBold();
      final grouped = _expensesByDay;

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('تقرير المصروفات',
                style: pw.TextStyle(font: arabicBold, fontSize: 20)),
          ),
          pw.SizedBox(height: 8),
          pw.Text('إجمالي المصروفات: ${_summary['all'] ?? 0} دينار',
              style: pw.TextStyle(font: arabicBold, fontSize: 14)),
          pw.Text('مصروفات اليوم: ${_summary['today'] ?? 0} دينار',
              style: pw.TextStyle(font: arabic, fontSize: 14)),
          pw.SizedBox(height: 16),
          ...grouped.entries.map((entry) {
            final dayTotal = entry.value.fold<int>(
                0, (s, e) => s + (e['amount'] as int? ?? 0));
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  color: PdfColors.red50,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(entry.key,
                          style: pw.TextStyle(
                              font: arabicBold, fontSize: 12)),
                      pw.Text('$dayTotal دينار',
                          style: pw.TextStyle(
                              font: arabicBold, fontSize: 12)),
                    ],
                  ),
                ),
                ...entry.value.map((e) => pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          vertical: 2, horizontal: 8),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                              width: 0.3, color: PdfColors.grey300),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                              '${e['category'] ?? ''} - ${e['note'] ?? ''}',
                              style: pw.TextStyle(
                                  font: arabic, fontSize: 10)),
                          pw.Text('${e['amount'] ?? 0} دينار',
                              style: pw.TextStyle(
                                  font: arabic, fontSize: 10)),
                        ],
                      ),
                    )),
                pw.SizedBox(height: 10),
              ],
            );
          }),
        ],
      ));

      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في طباعة التقرير: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ─── حوار إضافة مصروف ───
  Future<void> _showAddExpenseDialog() async {
    String? selectedCategory = _expenseCategories.first;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'إضافة مصروف',
            style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'نوع المصروف',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: _expenseCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedCategory = val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (دينار) *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (amountCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('الرجاء إدخال المبلغ'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                  return;
                }
                final amount = int.tryParse(amountCtrl.text.trim());
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('الرجاء إدخال مبلغ صحيح'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
      final result = await DatabaseHelper.instance.insertExpense(
        category: selectedCategory ?? 'أخرى',
        amount: amount,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted && result > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة المصروف بنجاح'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    }
  }

  // ─── تأكيد الحذف ───
  Future<void> _confirmDelete(Map<String, dynamic> expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف', style: TextStyle(color: AppTheme.errorColor)),
        content: const Text('هل تريد حذف هذا المصروف؟'),
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
      final ok = await DatabaseHelper.instance.deleteExpense(expense['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'تم حذف المصروف' : 'فشل الحذف — حاول مجدداً'),
            backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ─── تجميع المصروفات حسب اليوم ───
  Map<String, List<Map<String, dynamic>>> get _expensesByDay {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final e in _expenses) {
      final dateKey = _formatDateShort(e['created_at'] as String?);
      grouped.putIfAbsent(dateKey, () => []).add(e);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _expensesByDay;
    final days = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصروفات', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _expenses.isEmpty ? null : _printExpensesPdf,
            tooltip: 'طباعة تقرير المصروفات',
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
                  // ملخص المصروفات
                  _buildSummaryCard(),
                  const SizedBox(height: 16),
                  // زر إضافة مصروف
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة مصروف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      onPressed: _showAddExpenseDialog,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // المصروفات مجمّعة حسب اليوم — عرض تدريجي (7 أيام في المرة)
                  if (days.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'لا توجد مصروفات بعد',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ),
                    )
                  else ...[
                    ...days.take(_visibleDays).map((day) => _buildDaySection(day, grouped[day]!)),
                    if (days.length > _visibleDays)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _visibleDays += 7),
                          icon: const Icon(Icons.expand_more),
                          label: Text('عرض أيام أكثر (${days.length - _visibleDays} يوم متبقي)'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    final today = _summary['today'] ?? 0;
    final all = _summary['all'] ?? 0;

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
                const Icon(Icons.receipt_long, color: AppTheme.primaryColor, size: 28),
                const SizedBox(width: 8),
                const Text('ملخص المصروفات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('مصروفات اليوم', '$today', AppTheme.warningColor),
                _buildStatColumn('إجمالي المصروفات', '$all', AppTheme.errorColor),
                _buildStatColumn('عدد المصروفات', '${_expenses.length}', AppTheme.textPrimary),
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

  Widget _buildDaySection(String day, List<Map<String, dynamic>> dayExpenses) {
    final dayTotal = dayExpenses.fold<int>(0, (s, e) => s + (e['amount'] as int? ?? 0));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  day,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$dayTotal د',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          ...dayExpenses.map((e) {
            final category = e['category'] as String? ?? '';
            final amount = e['amount'] as int? ?? 0;
            final note = e['note'] as String? ?? '';
            final time = _formatDate(e['created_at'] as String?);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.warningColor.withValues(alpha: 0.15),
                child: const Icon(Icons.receipt, color: AppTheme.warningColor, size: 18),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(category, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('$amount دينار', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.errorColor)),
                ],
              ),
              subtitle: Row(
                children: [
                  Text(time, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  if (note.isNotEmpty) ...[
                    const Text(' | ', style: TextStyle(color: AppTheme.textSecondary)),
                    Expanded(
                      child: Text(note, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 20),
                onPressed: () => _confirmDelete(e),
                tooltip: 'حذف',
              ),
            );
          }),
        ],
      ),
    );
  }
}

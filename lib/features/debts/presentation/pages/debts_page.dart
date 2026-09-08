import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:cashier_system/features/shop_debts/presentation/pages/shop_debts_page.dart';

class DebtsPage extends StatefulWidget {
  const DebtsPage({Key? key}) : super(key: key);

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

enum DebtsFilter { unpaid, paid, all }

class _DebtsPageState extends State<DebtsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _debts = [];
  Map<String, int> _summary = {};
  bool _isLoading = true;
  DebtsFilter _activeFilter = DebtsFilter.unpaid;

  /// العرض التدريجي — عدد البطاقات الظاهرة حالياً
  int _visibleDebts = 30;

  /// تنسيق التاريخ: 2026/08/19 11:37 (بدون ثواني)
  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length >= 16 ? iso.substring(0, 16).replaceAll('T', '  ') : iso;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    DatabaseHelper.debtsRevision.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    DatabaseHelper.debtsRevision.removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final debts = await DatabaseHelper.instance.getAllDebts();
    final summary = await DatabaseHelper.instance.getDebtsSummary();
    if (mounted) {
      setState(() {
        _debts = debts;
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredDebts {
    switch (_activeFilter) {
      case DebtsFilter.paid:
        return _debts.where((d) => (d['paid'] as int? ?? 0) >= (d['amount'] as int? ?? 0)).toList();
      case DebtsFilter.unpaid:
        return _debts.where((d) => (d['paid'] as int? ?? 0) < (d['amount'] as int? ?? 0)).toList();
      case DebtsFilter.all:
        return _debts;
    }
  }

  // ─── حوار إضافة دين جديد ───
  Future<void> _showAddDebtDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'إضافة دين جديد',
            style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم الزبون *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف (اختياري)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'مبلغ الدين (دينار) *',
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
                if (nameCtrl.text.trim().isEmpty || amountCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('الرجاء إدخال اسم الزبون ومبلغ الدين'),
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
      final result = await DatabaseHelper.instance.insertDebt(
        customerName: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        amount: amount,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted) {
        if (result > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إضافة الدين بنجاح'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('حدث خطأ أثناء إضافة الدين'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  // ─── حوار تسجيل دفعة ───
  Future<void> _showPayDebtDialog(Map<String, dynamic> debt) async {
    final debtId = debt['id'] as int;
    final customerName = debt['customer_name'] as String;
    final totalAmount = debt['amount'] as int;
    final paidAmount = debt['paid'] as int? ?? 0;
    final remaining = totalAmount - paidAmount;

    final payCtrl = TextEditingController(text: '$remaining');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final payAmount = int.tryParse(payCtrl.text) ?? 0;
          final canPay = payAmount > 0 && payAmount <= remaining;

          return AlertDialog(
            title: Text(
              'تسجيل دفعة — $customerName',
              style: const TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.neutralLightColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              '$totalAmount',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                            ),
                            const Text('الإجمالي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              '$paidAmount',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.successColor),
                            ),
                            const Text('المدفوع', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              '$remaining',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.errorColor),
                            ),
                            const Text('المتبقي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: payCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      labelText: 'مبلغ الدفعة',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  // أزرار مبلغ سريع
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickPayButton('النصف', remaining ~/ 2, payCtrl, setDialogState),
                      _buildQuickPayButton('الكل', remaining, payCtrl, setDialogState),
                    ],
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
                  backgroundColor: canPay ? AppTheme.successColor : AppTheme.neutralColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: canPay ? () => Navigator.pop(ctx, true) : null,
                child: const Text('تأكيد الدفعة'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final payAmount = int.tryParse(payCtrl.text.trim()) ?? 0;
      final success = await DatabaseHelper.instance.payDebt(debtId, payAmount);
      if (mounted) {
        if (success) {
          final newRemaining = remaining - payAmount;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newRemaining <= 0
                    ? 'تم سداد الدين بالكامل ✓'
                    : 'تم الدفع بنجاح | المتبقي: $newRemaining دينار',
              ),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل تسجيل الدفعة! لم يُخصم شيء — حاول مجدداً'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Widget _buildQuickPayButton(String label, int amount, TextEditingController ctrl, Function setDialogState) {
    return OutlinedButton(
      onPressed: () {
        ctrl.text = '$amount';
        setDialogState(() {});
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        side: const BorderSide(color: AppTheme.primaryColor),
      ),
      child: Text(label),
    );
  }

  // ─── حوار تعديل الدين ───
  Future<void> _showEditDebtDialog(Map<String, dynamic> debt) async {
    final nameCtrl = TextEditingController(text: debt['customer_name'] as String);
    final phoneCtrl = TextEditingController(text: debt['phone'] as String? ?? '');
    final amountCtrl = TextEditingController(text: '${debt['amount']}');
    final noteCtrl = TextEditingController(text: debt['note'] as String? ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'تعديل الدين',
          style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الزبون',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'مبلغ الدين',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة',
                  border: OutlineInputBorder(),
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
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('اسم الزبون مطلوب'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              final amount = int.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح أكبر من صفر'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final amount = int.tryParse(amountCtrl.text.trim()) ?? debt['amount'];
      final ok = await DatabaseHelper.instance.updateDebt(
        debt['id'] as int,
        customerName: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        amount: amount,
        note: noteCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'تم تحديث الدين ✓' : 'فشل التحديث — حاول مجدداً'),
            backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ─── تأكيد الحذف ───
  Future<void> _confirmDelete(Map<String, dynamic> debt) async {
    final customerName = debt['customer_name'] as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف', style: TextStyle(color: AppTheme.errorColor)),
        content: Text('هل تريد حذف دين "$customerName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await DatabaseHelper.instance.deleteDebt(debt['id'] as int);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'تم حذف الدين' : 'فشل الحذف — حاول مجدداً'),
            backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // ─── تصدير ديون الزبائن PDF ───
  Future<void> _exportDebtsPdf() async {
    try {
      final arabic = await PdfGoogleFonts.cairoRegular();
      final arabicBold = await PdfGoogleFonts.cairoBold();
      final debts = _filteredDebts;
      final doc = pw.Document();

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text('تقرير ديون الزبائن',
                style: pw.TextStyle(font: arabicBold, fontSize: 20)),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
              'الإجمالي: ${_summary['total'] ?? 0} | المدفوع: ${_summary['paid'] ?? 0} | المتبقي: ${_summary['remaining'] ?? 0}',
              style: pw.TextStyle(font: arabic, fontSize: 12)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: arabicBold, fontSize: 11),
            cellStyle: pw.TextStyle(font: arabic, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red50),
            headers: ['الزبون', 'الهاتف', 'المبلغ', 'المدفوع', 'المتبقي', 'الحالة'],
            data: debts.map((d) {
              final total = d['amount'] as int;
              final paid = d['paid'] as int? ?? 0;
              final remaining = total - paid;
              return [
                d['customer_name'] ?? '',
                d['phone'] ?? '',
                '$total',
                '$paid',
                '$remaining',
                remaining <= 0 ? 'مسدد' : 'غير مسدد',
              ];
            }).toList(),
          ),
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

  // ─── تصدير ديون الزبائن CSV ───
  Future<void> _exportDebtsCsv() async {
    try {
      final debts = _filteredDebts;
      final rows = <List<String>>[
        ['الزبون', 'الهاتف', 'المبلغ', 'المدفوع', 'المتبقي', 'الحالة', 'ملاحظة', 'تاريخ الإنشاء'],
        ...debts.map((d) {
          final total = d['amount'] as int;
          final paid = d['paid'] as int? ?? 0;
          final remaining = total - paid;
          return [
            '${d['customer_name'] ?? ''}',
            '${d['phone'] ?? ''}',
            '$total',
            '$paid',
            '$remaining',
            remaining <= 0 ? 'مسدد' : 'غير مسدد',
            '${d['note'] ?? ''}',
            '${d['created_at'] ?? ''}',
          ];
        }),
      ];
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/debts_report.csv');
      await file.writeAsString(csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الحفظ: ${file.path}'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // ─── عرض تفاصيل الدين ───
  void _showDebtDetails(Map<String, dynamic> debt) async {
    final debtId = debt['id'] as int;
    final totalAmount = debt['amount'] as int;
    final paidAmount = debt['paid'] as int? ?? 0;
    final remaining = totalAmount - paidAmount;
    final createdAt = _formatDate(debt['created_at'] as String?);
    final updatedAt = _formatDate(debt['updated_at'] as String?);
    final phone = debt['phone'] as String? ?? '';
    final note = debt['note'] as String? ?? '';
    final isPaid = remaining <= 0;

    // جلب سجل الدفعات
    final payments = await DatabaseHelper.instance.getDebtPayments(debtId);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.neutralColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    debt['customer_name'] as String,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPaid ? AppTheme.successColor : AppTheme.errorColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isPaid ? 'مسدد' : 'غير مسدد',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(phone, style: const TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.neutralLightColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '$totalAmount',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                        const Text('الإجمالي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$paidAmount',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.successColor),
                        ),
                        const Text('المدفوع', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$remaining',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? AppTheme.successColor : AppTheme.errorColor,
                          ),
                        ),
                        const Text('المتبقي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (note.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.note, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(note, style: const TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text('أنشئ: $createdAt', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.update, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text('آخر تحديث: $updatedAt', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
              // ─── سجل الدفعات ───
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.history, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'سجل الدفعات (${payments.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...payments.map((p) {
                  final payAmount = p['amount'] as int;
                  final payDate = _formatDate(p['created_at'] as String?);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, size: 16, color: AppTheme.successColor),
                            const SizedBox(width: 8),
                            Text(
                              '$payAmount دينار',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.successColor),
                            ),
                          ],
                        ),
                        Text(
                          payDate,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  );
                }),
              ] else if (paidAmount > 0) ...[
                // حالة قديمة — دفعات بدون سجل
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppTheme.warningColor),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هناك مدفوعات مسجلة لكن بدون تفاصيل تواريخ',
                          style: TextStyle(color: AppTheme.warningColor, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (!isPaid)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.payments),
                    label: const Text('تسجيل دفعة', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showPayDebtDialog(debt);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الديون', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'ديون الزبائن'),
            Tab(icon: Icon(Icons.business), text: 'ديون المحل'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'pdf') _exportDebtsPdf();
              if (v == 'csv') _exportDebtsCsv();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf, size: 18), SizedBox(width: 8), Text('تصدير PDF')])),
              PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.table_chart, size: 18), SizedBox(width: 8), Text('تصدير CSV')])),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تبويب ديون الزبائن
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildSummaryCard(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildFilterChip('غير مسدد', DebtsFilter.unpaid, Icons.money_off),
                          const SizedBox(width: 8),
                          _buildFilterChip('تم التسديد', DebtsFilter.paid, Icons.check_circle_outline),
                          const SizedBox(width: 8),
                          _buildFilterChip('الكل', DebtsFilter.all, Icons.all_inclusive),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                          label: const Text('إضافة دين جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onPressed: _showAddDebtDialog,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_filteredDebts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              _activeFilter == DebtsFilter.all
                                  ? 'لا توجد ديون'
                                  : _activeFilter == DebtsFilter.paid
                                      ? 'لا توجد ديون مسددة'
                                      : 'لا توجد ديون غير مسدة',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                            ),
                          ),
                        )
                      else ...[
                        // عرض تدريجي — 30 عنصر في المرة لسلاسة أكبر مع القوائم الضخمة
                        ..._filteredDebts.take(_visibleDebts).map((debt) => _buildDebtCard(debt)),
                        if (_filteredDebts.length > _visibleDebts)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _visibleDebts += 30),
                              icon: const Icon(Icons.expand_more),
                              label: Text('عرض المزيد (${_filteredDebts.length - _visibleDebts} متبقية)'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
          // تبويب ديون المحل
          const ShopDebtsPage(),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total = _summary['total'] ?? 0;
    final paid = _summary['paid'] ?? 0;
    final remaining = _summary['remaining'] ?? 0;
    final count = _summary['count'] ?? 0;

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
                const Icon(Icons.account_balance_wallet, color: AppTheme.primaryColor, size: 28),
                const SizedBox(width: 8),
                const Text('ملخص الديون', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count دين',
                    style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('الإجمالي', '$total', AppTheme.primaryColor),
                _buildStatColumn('المدفوع', '$paid', AppTheme.successColor),
                _buildStatColumn('المتبقي', '$remaining', AppTheme.errorColor),
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

  Widget _buildFilterChip(String label, DebtsFilter filter, IconData icon) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() {
        _activeFilter = filter;
        _visibleDebts = 30; // إعادة ضبط العرض التدريجي عند تغيير الفلتر
      }),
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
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtCard(Map<String, dynamic> debt) {
    final customerName = debt['customer_name'] as String;
    final totalAmount = debt['amount'] as int;
    final paidAmount = debt['paid'] as int? ?? 0;
    final remaining = totalAmount - paidAmount;
    final isPaid = remaining <= 0;
    final createdAt = _formatDate(debt['created_at'] as String?);
    final phone = debt['phone'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPaid ? AppTheme.successColor : AppTheme.errorColor,
          child: Text(
            customerName.substring(0, 1),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                customerName,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPaid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('مسدد', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$totalAmount دينار',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (!isPaid) ...[
                  const Text(' | ', style: TextStyle(color: AppTheme.textSecondary)),
                  Text(
                    'متبقي: $remaining',
                    style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                if (phone.isNotEmpty) ...[
                  const Icon(Icons.phone, size: 12, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(phone, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(width: 8),
                ],
                Text(createdAt, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPaid)
              IconButton(
                icon: const Icon(Icons.payments, color: AppTheme.successColor),
                onPressed: () => _showPayDebtDialog(debt),
                tooltip: 'تسجيل دفعة',
              ),
            IconButton(
              icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
              onPressed: () => _showEditDebtDialog(debt),
              tooltip: 'تعديل',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor),
              onPressed: () => _confirmDelete(debt),
              tooltip: 'حذف',
            ),
          ],
        ),
        onTap: () => _showDebtDetails(debt),
      ),
    );
  }
}

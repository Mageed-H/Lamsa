import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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
  List<Map<String, dynamic>> _groupedDebts = [];
  List<String> _customerNames = [];
  Map<String, int> _summary = {};
  List<Map<String, dynamic>> _shopDebts = [];
  Map<String, int> _shopSummary = {};
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
    _tabController.addListener(() => setState(() {}));
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
    final grouped = await DatabaseHelper.instance.getDebtsGroupedByName();
    final names = await DatabaseHelper.instance.getDebtCustomerNames();
    final summary = await DatabaseHelper.instance.getDebtsSummary();
    final shopDebts = await DatabaseHelper.instance.getAllShopDebts();
    final shopSummary = await DatabaseHelper.instance.getShopDebtsSummary();
    if (mounted) {
      setState(() {
        _debts = debts;
        _groupedDebts = grouped;
        _customerNames = names;
        _summary = summary;
        _shopDebts = shopDebts;
        _shopSummary = shopSummary;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredGroupedDebts {
    switch (_activeFilter) {
      case DebtsFilter.paid:
        return _groupedDebts.where((g) => (g['total_paid'] as int) >= (g['total_amount'] as int)).toList();
      case DebtsFilter.unpaid:
        return _groupedDebts.where((g) => (g['total_paid'] as int) < (g['total_amount'] as int)).toList();
      case DebtsFilter.all:
        return _groupedDebts;
    }
  }

  // ─── حوار إضافة دين جديد ───
  Future<void> _showAddDebtDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? selectedExistingName;
    bool isNewCustomer = true;

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
                // ─── اختيار زبون موجود أو جديد ───
                if (_customerNames.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('زبون جديد', style: TextStyle(fontSize: 13)),
                          value: true,
                          groupValue: isNewCustomer,
                          onChanged: (v) => setDialogState(() {
                            isNewCustomer = v!;
                            if (isNewCustomer) {
                              selectedExistingName = null;
                              nameCtrl.clear();
                              phoneCtrl.clear();
                            }
                          }),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<bool>(
                          title: const Text('زبون موجود', style: TextStyle(fontSize: 13)),
                          value: false,
                          groupValue: isNewCustomer,
                          onChanged: (v) => setDialogState(() {
                            isNewCustomer = v!;
                            if (!isNewCustomer && _customerNames.isNotEmpty) {
                              selectedExistingName = _customerNames.first;
                              nameCtrl.text = _customerNames.first;
                            }
                          }),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                  if (!isNewCustomer) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedExistingName,
                      items: _customerNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                      onChanged: (v) => setDialogState(() {
                        selectedExistingName = v;
                        nameCtrl.text = v ?? '';
                      }),
                      decoration: const InputDecoration(
                        labelText: 'اختر الزبون',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_search),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                if (isNewCustomer) ...[
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
                ],
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

  // ─── إضافة دين لزبون موجود ───
  Future<void> _showAddDebtForCustomer(String customerName, String phone) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'إضافة فاتورة — $customerName',
          style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phone.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.neutralLightColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone, size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(phone, style: const TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
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
              final amount = int.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح'), backgroundColor: AppTheme.errorColor),
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
      final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
      final result = await DatabaseHelper.instance.insertDebt(
        customerName: customerName,
        phone: phone.isEmpty ? null : phone,
        amount: amount,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted) {
        if (result > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إضافة فاتورة جديدة لـ $customerName بنجاح'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حدث خطأ أثناء إضافة الدين'), backgroundColor: AppTheme.errorColor),
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

  // ─── تصدير PDF حسب التبويب المفتوح ───
  Future<void> _exportDebtsPdf() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      final arabicFont = pw.Font.ttf(fontData);
      final doc = pw.Document();
      final isCustomerTab = _tabController.index == 0;
      final debts = isCustomerTab ? _debts : _shopDebts;
      final title = isCustomerTab ? 'تقرير ديون الزبائن' : 'تقرير ديون المحل';
      final headers = isCustomerTab
          ? ['الزبون', 'الهاتف', 'المبلغ', 'المدفوع', 'المتبقي', 'الحالة']
          : ['المورد', 'الهاتف', 'المبلغ', 'المدفوع', 'المتبقي', 'الحالة'];
      final summary = isCustomerTab ? _summary : _shopSummary;

      pw.TextStyle bodyStyle({bool bold = false}) => pw.TextStyle(
        font: arabicFont,
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : null,
      );

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(title,
                style: pw.TextStyle(font: arabicFont, fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
              'الإجمالي: ${summary['total'] ?? 0} | المدفوع: ${summary['paid'] ?? 0} | المتبقي: ${summary['remaining'] ?? 0}',
              style: bodyStyle()),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: bodyStyle(bold: true),
            cellStyle: bodyStyle(),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red50),
            headers: headers,
            data: debts.map((d) {
              final total = d['amount'] as int;
              final paid = d['paid'] as int? ?? 0;
              final remaining = total - paid;
              final name = isCustomerTab ? (d['customer_name'] ?? '') : (d['supplier_name'] ?? '');
              return [
                name,
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

      // حفظ الملف على سطح المكتب
      final pdfBytes = await doc.save();
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final safeName = isCustomerTab ? 'Customer_Debts_$dateStr.pdf' : 'Shop_Debts_$dateStr.pdf';
      final userProfile = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
      final sep = Platform.pathSeparator;
      final desktop = '$userProfile${sep}Desktop';
      final desktopDir = Directory(desktop);
      if (!await desktopDir.exists()) await desktopDir.create(recursive: true);
      final file = File('$desktop$sep$safeName');
      await file.writeAsBytes(pdfBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ التقرير على سطح المكتب ✓\n$safeName'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
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
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf, size: 18), SizedBox(width: 8), Text('تصدير PDF')])),
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
                      if (_filteredGroupedDebts.isEmpty)
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
                        ..._filteredGroupedDebts.take(_visibleDebts).map((group) => _buildGroupedDebtCard(group)),
                        if (_filteredGroupedDebts.length > _visibleDebts)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _visibleDebts += 30),
                              icon: const Icon(Icons.expand_more),
                              label: Text('عرض المزيد (${_filteredGroupedDebts.length - _visibleDebts} متبقية)'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
          // تبويب ديون المحل
          const ShopDebtsPage(isEmbedded: true),
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

  // ─── بطاقة زبون مع كل فواتيره ───
  Widget _buildGroupedDebtCard(Map<String, dynamic> group) {
    final customerName = group['customer_name'] as String;
    final phone = group['phone'] as String? ?? '';
    final debts = group['debts'] as List<Map<String, dynamic>>;
    final totalAmount = group['total_amount'] as int;
    final totalPaid = group['total_paid'] as int;
    final totalRemaining = totalAmount - totalPaid;
    final isFullyPaid = totalRemaining <= 0;
    final unpaidCount = debts.where((d) {
      final rem = (d['amount'] as int) - ((d['paid'] as int?) ?? 0);
      return rem > 0;
    }).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: !isFullyPaid,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: CircleAvatar(
            backgroundColor: isFullyPaid ? AppTheme.successColor : AppTheme.errorColor,
            radius: 24,
            child: Text(
              customerName.substring(0, 1),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  customerName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isFullyPaid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('مسدد', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                )
              else if (unpaidCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$unpaidCount غير مسدّد', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'المجموع: $totalAmount',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'المدفوع: $totalPaid',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.successColor),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'المتبقي: $totalRemaining',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isFullyPaid ? AppTheme.successColor : AppTheme.errorColor,
                    ),
                  ),
                ],
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 12, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(phone, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            // ─── قائمة الفواتير ───
            ...debts.map((debt) {
              final debtId = debt['id'] as int;
              final debtAmount = debt['amount'] as int;
              final debtPaid = (debt['paid'] as int?) ?? 0;
              final debtRemaining = debtAmount - debtPaid;
              final debtPaidOff = debtRemaining <= 0;
              final createdAt = _formatDate(debt['created_at'] as String?);
              final note = debt['note'] as String? ?? '';
              final saleId = debt['sale_id'] as int?;
              return _DebtInvoiceCard(
                debt: debt,
                debtAmount: debtAmount,
                debtPaid: debtPaid,
                debtRemaining: debtRemaining,
                debtPaidOff: debtPaidOff,
                createdAt: createdAt,
                note: note,
                saleId: saleId,
                onPay: () => _showPayDebtDialog(debt),
                onEdit: () => _showEditDebtDialog(debt),
                onDelete: () => _confirmDelete(debt),
              );
            }),
            // ─── زر إضافة فاتورة جديدة لنفس الزبون ───
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: const BorderSide(color: AppTheme.primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text('إضافة فاتورة جديدة لـ $customerName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _showAddDebtForCustomer(customerName, phone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── بطاقة فاتورة دين مع تفاصيل المادة ───
class _DebtInvoiceCard extends StatefulWidget {
  final Map<String, dynamic> debt;
  final int debtAmount;
  final int debtPaid;
  final int debtRemaining;
  final bool debtPaidOff;
  final String createdAt;
  final String note;
  final int? saleId;
  final VoidCallback onPay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DebtInvoiceCard({
    required this.debt,
    required this.debtAmount,
    required this.debtPaid,
    required this.debtRemaining,
    required this.debtPaidOff,
    required this.createdAt,
    required this.note,
    this.saleId,
    required this.onPay,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DebtInvoiceCard> createState() => _DebtInvoiceCardState();
}

class _DebtInvoiceCardState extends State<_DebtInvoiceCard> {
  List<Map<String, dynamic>> _saleItems = [];
  bool _isLoadingItems = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.saleId != null && widget.saleId! > 0) {
      _loadSaleItems();
    }
  }

  Future<void> _loadSaleItems() async {
    setState(() => _isLoadingItems = true);
    final items = await DatabaseHelper.instance.getSaleItems(widget.saleId!);
    if (mounted) {
      setState(() {
        _saleItems = items;
        _isLoadingItems = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSaleItems = _saleItems.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: widget.debtPaidOff
            ? AppTheme.successColor.withValues(alpha: 0.06)
            : AppTheme.neutralLightColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.debtPaidOff
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : AppTheme.errorColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── رأس الفاتورة ───
          Row(
            children: [
              Icon(
                widget.debtPaidOff ? Icons.check_circle : Icons.receipt_long,
                size: 16,
                color: widget.debtPaidOff ? AppTheme.successColor : AppTheme.errorColor,
              ),
              const SizedBox(width: 6),
              if (widget.saleId != null && widget.saleId! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'R${widget.saleId.toString().padLeft(6, '0')}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${widget.debtAmount} دينار',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: widget.debtPaidOff ? AppTheme.successColor : AppTheme.primaryColor,
                  ),
                ),
              ),
              Text(
                widget.createdAt,
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
            ],
          ),
          if (widget.debtPaid > 0 && !widget.debtPaidOff) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.check, size: 12, color: AppTheme.successColor),
                const SizedBox(width: 4),
                Text(
                  'مدفوع: ${widget.debtPaid} | متبقي: ${widget.debtRemaining}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
          if (widget.note.isNotEmpty && !widget.note.startsWith('فاتورة')) ...[
            const SizedBox(height: 4),
            Text(
              widget.note,
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // ─── تفاصيل المواد ───
          if (hasSaleItems) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'عرض تفاصيل الفاتورة (${_saleItems.length} صنف)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              // رأس الجدول
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                color: AppTheme.neutralLightColor,
                child: const Row(
                  children: [
                    Expanded(flex: 4, child: Text('المادة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('العدد', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Expanded(flex: 3, child: Text('السعر', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    Expanded(flex: 3, child: Text('الإجمالي', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                  ],
                ),
              ),
              // المواد
              ..._saleItems.map((item) {
                final name = item['product_name'] as String? ?? '';
                final qty = item['quantity'] as int? ?? 0;
                final unitPrice = item['unit_price'] as int? ?? 0;
                final rowTotal = unitPrice * qty;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                      Expanded(flex: 2, child: Text('x$qty', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(flex: 3, child: Text('$unitPrice', style: const TextStyle(fontSize: 11), textAlign: TextAlign.center)),
                      Expanded(flex: 3, child: Text('$rowTotal', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    ],
                  ),
                );
              }),
            ],
          ] else if (widget.saleId != null && _isLoadingItems) ...[
            const SizedBox(height: 6),
            const SizedBox(
              height: 16, width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          // ─── أزرار الفرد ───
          const SizedBox(height: 6),
          Row(
            children: [
              if (!widget.debtPaidOff)
                SizedBox(
                  height: 28,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.payments, size: 14),
                    label: const Text('تسديد', style: TextStyle(fontSize: 11)),
                    onPressed: widget.onPay,
                  ),
                ),
              const SizedBox(width: 6),
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('تعديل', style: TextStyle(fontSize: 11)),
                  onPressed: widget.onEdit,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('حذف', style: TextStyle(fontSize: 11)),
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

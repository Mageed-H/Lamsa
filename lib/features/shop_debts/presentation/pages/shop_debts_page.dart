import 'package:flutter/material.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';

class ShopDebtsPage extends StatefulWidget {
  final bool isEmbedded;
  const ShopDebtsPage({Key? key, this.isEmbedded = false}) : super(key: key);

  @override
  State<ShopDebtsPage> createState() => _ShopDebtsPageState();
}

class _ShopDebtsPageState extends State<ShopDebtsPage> {
  List<Map<String, dynamic>> _debts = [];
  Map<String, int> _summary = {};
  bool _isLoading = true;

  /// العرض التدريجي — عدد البطاقات الظاهرة
  int _visibleDebts = 30;

  @override
  void initState() {
    super.initState();
    DatabaseHelper.debtsRevision.addListener(_loadData);
    _loadData();
  }

  @override
  void dispose() {
    DatabaseHelper.debtsRevision.removeListener(_loadData);
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final debts = await DatabaseHelper.instance.getAllShopDebts();
    final summary = await DatabaseHelper.instance.getShopDebtsSummary();
    if (mounted) {
      setState(() {
        _debts = debts;
        _summary = summary;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddDebtDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة دين على المحل', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم المندوب/الشركة *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || amountCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال الاسم والمبلغ'), backgroundColor: AppTheme.errorColor),
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
      final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
      final result = await DatabaseHelper.instance.insertShopDebt(
        supplierName: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        amount: amount,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result > 0 ? 'تم إضافة الدين بنجاح' : 'فشل حفظ الدين — حاول مجدداً'),
            backgroundColor: result > 0 ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _showPayDebtDialog(Map<String, dynamic> debt) async {
    final debtId = debt['id'] as int;
    final supplierName = debt['supplier_name'] as String;
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
            title: Text('تسديد دين — $supplierName', style: const TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.neutralLightColor, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(children: [
                          Text('$totalAmount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                          const Text('الإجمالي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ]),
                        Column(children: [
                          Text('$paidAmount', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.successColor)),
                          const Text('المدفوع', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ]),
                        Column(children: [
                          Text('$remaining', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.errorColor)),
                          const Text('المتبقي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        ]),
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
                      labelText: 'مبلغ التسديد',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        onPressed: () { payCtrl.text = '${remaining ~/ 2}'; setDialogState(() {}); },
                        child: const Text('النصف'),
                      ),
                      OutlinedButton(
                        onPressed: () { payCtrl.text = '$remaining'; setDialogState(() {}); },
                        child: const Text('الكل'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canPay ? AppTheme.successColor : AppTheme.neutralColor,
                  foregroundColor: Colors.white,
                ),
                onPressed: canPay ? () => Navigator.pop(ctx, true) : null,
                child: const Text('تأكيد'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final payAmount = int.tryParse(payCtrl.text.trim()) ?? 0;
      final success = await DatabaseHelper.instance.payShopDebt(debtId, payAmount);
      if (mounted) {
        if (success) {
          final newRemaining = remaining - payAmount;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newRemaining <= 0 ? 'تم سداد الدين بالكامل ✓' : 'تم التسديد | المتبقي: $newRemaining دينار'),
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

  void _showDebtDetails(Map<String, dynamic> debt) async {
    final debtId = debt['id'] as int;
    final totalAmount = debt['amount'] as int;
    final paidAmount = debt['paid'] as int? ?? 0;
    final remaining = totalAmount - paidAmount;
    final phone = debt['phone'] as String? ?? '';
    final note = debt['note'] as String? ?? '';
    final isPaid = remaining <= 0;

    final payments = await DatabaseHelper.instance.getShopDebtPayments(debtId);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.neutralColor, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(debt['supplier_name'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: isPaid ? AppTheme.successColor : AppTheme.errorColor, borderRadius: BorderRadius.circular(12)),
                    child: Text(isPaid ? 'مسدد' : 'غير مسدد', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.phone, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text(phone, style: const TextStyle(color: AppTheme.textSecondary)),
                ]),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.neutralLightColor, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      Text('$totalAmount', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      const Text('الإجمالي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
                    Column(children: [
                      Text('$paidAmount', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.successColor)),
                      const Text('المدفوع', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
                    Column(children: [
                      Text('$remaining', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isPaid ? AppTheme.successColor : AppTheme.errorColor)),
                      const Text('المتبقي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
                  ],
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.note, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note, style: const TextStyle(color: AppTheme.textSecondary))),
                ]),
              ],
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(children: [
                  const Icon(Icons.history, size: 18, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text('سجل التسديدات (${payments.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 14)),
                ]),
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
                        Row(children: [
                          const Icon(Icons.check_circle, size: 16, color: AppTheme.successColor),
                          const SizedBox(width: 8),
                          Text('$payAmount دينار', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.successColor)),
                        ]),
                        Text(payDate, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 20),
              if (!isPaid)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: const Icon(Icons.payments),
                    label: const Text('تسجيل تسديد', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () { Navigator.pop(ctx); _showPayDebtDialog(debt); },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditDebtDialog(Map<String, dynamic> debt) async {
    final nameCtrl = TextEditingController(text: debt['supplier_name'] as String);
    final phoneCtrl = TextEditingController(text: debt['phone'] as String? ?? '');
    final amountCtrl = TextEditingController(text: '${debt['amount']}');
    final noteCtrl = TextEditingController(text: debt['note'] as String? ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الدين', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المندوب/الشركة', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظة', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('اسم المورد مطلوب'), backgroundColor: AppTheme.errorColor),
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
      final ok = await DatabaseHelper.instance.updateShopDebt(
        debt['id'] as int,
        supplierName: nameCtrl.text.trim(),
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

  Future<void> _confirmDelete(Map<String, dynamic> debt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف', style: TextStyle(color: AppTheme.errorColor)),
        content: Text('هل تريد حذف دين "${debt['supplier_name']}"؟'),
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
      final ok = await DatabaseHelper.instance.deleteShopDebt(debt['id'] as int);
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

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (widget.isEmbedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ديون المحل', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'تحديث'),
        ],
      ),
      body: content,
    );
  }
  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.account_balance, color: AppTheme.primaryColor, size: 28),
                    const SizedBox(width: 8),
                    const Text('ملخص ديون المحل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [
                        Text('${_summary['total'] ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                        const Text('الإجمالي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ]),
                      Column(children: [
                        Text('${_summary['paid'] ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.successColor)),
                        const Text('المدفوع', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ]),
                      Column(children: [
                        Text('${_summary['remaining'] ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.errorColor)),
                        const Text('المتبقي', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
              label: const Text('إضافة دين على المحل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _showAddDebtDialog,
            ),
          ),
          const SizedBox(height: 16),
          if (_debts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(child: Text('لا توجد ديون على المحل', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16))),
            )
          else ...[
            ..._debts.take(_visibleDebts).map((debt) {
              final supplierName = debt['supplier_name'] as String;
              final totalAmount = debt['amount'] as int;
              final paidAmount = debt['paid'] as int? ?? 0;
              final remaining = totalAmount - paidAmount;
              final isPaid = remaining <= 0;
              final phone = debt['phone'] as String? ?? '';
              final createdAt = _formatDate(debt['created_at'] as String?);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPaid ? AppTheme.successColor : AppTheme.errorColor,
                    child: Text(supplierName.substring(0, 1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(supplierName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      if (isPaid)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.successColor, borderRadius: BorderRadius.circular(8)),
                          child: const Text('مسدد', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('$totalAmount دينار', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (!isPaid) ...[
                          const Text(' | ', style: TextStyle(color: AppTheme.textSecondary)),
                          Text('متبقي: $remaining', style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ]),
                      Row(children: [
                        if (phone.isNotEmpty) ...[
                          const Icon(Icons.phone, size: 12, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(phone, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(width: 8),
                        ],
                        Text(createdAt, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                      ]),
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
                          tooltip: 'تسديد',
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
            }),
            if (_debts.length > _visibleDebts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visibleDebts += 30),
                  icon: const Icon(Icons.expand_more),
                  label: Text('عرض المزيد (${_debts.length - _visibleDebts} متبقية)'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

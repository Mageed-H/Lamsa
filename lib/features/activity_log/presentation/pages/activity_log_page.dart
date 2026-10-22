import 'package:flutter/material.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';

/// سجل التعديلات الشامل — عرض كل العمليات مع إمكانية الاسترجاع (فردي وتجمعي)

class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String _entityFilter = '';
  String _search = '';
  int _dateFilter = 0; // 0=الكل, 1=اليوم, 2=آخر 7 أيام, 3=آخر 30 يوم
  final _searchCtrl = TextEditingController();

  static const _entityTabs = [
    ('', 'الكل'),
    ('product', 'منتجات'),
    ('product_field', 'تعديلات منتجات'),
    ('stock', 'المخزون'),
    ('category', 'الأقسام'),
    ('customer', 'الزبائن'),
    ('sale', 'الفواتير'),
    ('expense', 'المصروفات'),
    ('debt', 'ديون المحل'),
    ('setting', 'الإعدادات'),
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    DateTime? fromDate;
    if (_dateFilter == 1) {
      final now = DateTime.now();
      fromDate = DateTime(now.year, now.month, now.day);
    } else if (_dateFilter == 2) {
      fromDate = DateTime.now().subtract(const Duration(days: 7));
    } else if (_dateFilter == 3) {
      fromDate = DateTime.now().subtract(const Duration(days: 30));
    }
    final logs = await DatabaseHelper.instance.getActivityLogs(
      entity: _entityFilter,
      search: _search,
      fromDate: fromDate,
    );
    if (mounted) setState(() { _logs = logs; _loading = false; });
  }

  String _formatDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} — '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _actionLabel(String action) => switch (action) {
    'add' => 'إضافة',
    'edit' => 'تعديل',
    'delete' => 'حذف',
    'stock' => 'تصحيح جرد',
    'sale' => 'بيع',
    'return' => 'إرجاع',
    'debt_add' => 'إضافة دين',
    _ => action,
  };

  IconData _actionIcon(Map<String, dynamic> log) => switch (log['action'] as String) {
    'add' => Icons.add_circle,
    'delete' => Icons.delete,
    'stock' => Icons.inventory,
    'debt_add' => Icons.account_balance_wallet,
    'sale' => Icons.shopping_cart,
    'return' => Icons.undo,
    _ => Icons.edit,
  };

  Color _actionColor(String action) => switch (action) {
    'add' => AppTheme.successColor,
    'delete' => AppTheme.errorColor,
    'stock' => Colors.orange,
    'sale' => AppTheme.primaryColor,
    'return' => Colors.deepOrange,
    _ => AppTheme.primaryColor,
  };

  String _fieldLabel(String? field) => switch (field) {
    'name' => 'الاسم',
    'category' => 'القسم',
    'color' => 'اللون',
    'size' => 'الحجم',
    'barcode' => 'الباركود',
    'price' => 'سعر البيع',
    'purchase_price' => 'سعر الشراء',
    'stock' => 'الجرد',
    'phone' => 'الهاتف',
    'address' => 'العنوان',
    'notes' => 'ملاحظات',
    'amount' => 'المبلغ',
    null || '' => '',
    _ => field,
  };

  Future<void> _restoreSingle(Map<String, dynamic> log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع العملية؟', style: TextStyle(color: AppTheme.primaryColor)),
        content: Text('سيتم التراجع عن: ${log['entity_name'] ?? ''}${log['field'] != null ? ' (${_fieldLabel(log['field'] as String?)})' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استرجاع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final count = await DatabaseHelper.instance.restoreActivityLogs([log['id'] as int]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count > 0 ? 'تم الاسترجاع بنجاح' : 'لا يمكن استرجاع هذه العملية (ربما حُذف العنصر أو تم سابقاً)'),
      backgroundColor: count > 0 ? AppTheme.successColor : AppTheme.errorColor,
    ));
    _loadLogs();
  }

  /// استرجاع فعيلة جماعية: الكل أو تحديد جزء منها
  Future<void> _restoreGroup(String group) async {
    // جلب كل السجلات غير المسترجعة من هذه الفعيلة
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('activity_log',
        where: 'bulk_group = ? AND undone = 0', whereArgs: [group], orderBy: 'id ASC');
    if (!mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يوجد شيء للاسترجاع في هذه الفعيلة'),
        backgroundColor: AppTheme.errorColor,
      ));
      return;
    }
    final selected = {for (final r in rows) r['id'] as int};

    final restoreIds = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('استرجاع فعيلة: $group', style: const TextStyle(color: AppTheme.primaryColor, fontSize: 16)),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setDialogState(() => selected.addAll({for (final r in rows) r['id'] as int})),
                      child: const Text('تحديد الكل'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setDialogState(() => selected.clear()),
                      child: const Text('مسح التحديد'),
                    ),
                    const Spacer(),
                    Text('محدد: ${selected.length} / ${rows.length}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (ctx, i) {
                      final row = rows[i];
                      final id = row['id'] as int;
                      final checked = selected.contains(id);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          '${_actionLabel(row['action'] as String)} — ${row['entity_name'] ?? ''}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${_fieldLabel(row['field'] as String?).isNotEmpty ? '${_fieldLabel(row['field'] as String?)}: ' : ''}${row['old_value'] ?? ''} ← ${row['new_value'] ?? ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.neutralLightColor,
              ),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, Set<int>.from(selected)),
              child: Text('استرجاع المحدد (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (restoreIds == null || restoreIds.isEmpty) return;

    // ترتيب تصاعدي: الأقدم أولاً حتى يصح الترجيع التسلسلي
    final ids = restoreIds.toList()..sort();
    final count = await DatabaseHelper.instance.restoreActivityLogs(ids);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(count > 0
          ? 'تم استرجاع $count من ${ids.length} عملية محددة'
          : 'تعذر الاسترجاع — ربما العناصر محذوفة أو مسترجعة سابقاً'),
      backgroundColor: count > 0 ? AppTheme.successColor : AppTheme.errorColor,
    ));
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('سجل التعديلات الشامل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: AppTheme.surfaceColor,
          foregroundColor: AppTheme.textPrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadLogs,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildFilters(),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () {
                      _searchCtrl.clear();
                      _search = '';
                      _loadLogs();
                    })
                  : null,
            ),
            onChanged: (v) { _search = v; _loadLogs(); },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              children: [
                for (final tab in _entityTabs) _buildChip(tab.$1, tab.$2),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDateChip(0, 'كل الوقت'),
              _buildDateChip(1, 'اليوم'),
              _buildDateChip(2, 'آخر 7 أيام'),
              _buildDateChip(3, 'آخر 30 يوم'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String value, String label) {
    final selected = _entityFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textPrimary)),
        selected: selected,
        selectedColor: AppTheme.primaryColor,
        backgroundColor: AppTheme.neutralLightColor,
        onSelected: (_) { setState(() => _entityFilter = value); _loadLogs(); },
      ),
    );
  }

  Widget _buildDateChip(int value, String label) {
    final selected = _dateFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : AppTheme.textSecondary)),
        selected: selected,
        selectedColor: AppTheme.primaryColor,
        backgroundColor: AppTheme.neutralLightColor,
        onSelected: (_) { setState(() => _dateFilter = value); _loadLogs(); },
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text('لا يوجد سجل بعد', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        return _buildLogCard(log);
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final action = log['action'] as String;
    final undoable = (log['undoable'] as int? ?? 0) == 1;
    final undone = (log['undone'] as int? ?? 0) == 1;
    final isBulk = (log['is_bulk'] as int? ?? 0) == 1;
    final bulkGroup = log['bulk_group'] as String?;
    final field = log['field'] as String?;
    final oldValue = log['old_value'] as String?;
    final newValue = log['new_value'] as String?;

    String title = '${_actionLabel(action)} — ${log['entity_name'] ?? ''}';
    String? details;
    if (field != null && _fieldLabel(field).isNotEmpty) {
      details = '${_fieldLabel(field)}: ${oldValue ?? ''} ← ${newValue ?? ''}';
    } else if (newValue != null && newValue.isNotEmpty) {
      details = newValue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: undone ? AppTheme.successColor.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_actionIcon(log), color: _actionColor(action), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                if (isBulk && !undone)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      bulkGroup?.isNotEmpty == true ? bulkGroup! : 'جماعي',
                      style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor),
                    ),
                  ),
                if (undone)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('مسترجع ✓', style: TextStyle(fontSize: 11, color: AppTheme.successColor)),
                  ),
              ],
            ),
            if (details != null && details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 30),
                child: Text(details, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 30),
              child: Row(
                children: [
                  Icon(Icons.access_time, size: 13, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(_formatDate(log['created_at'] as String), style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const Spacer(),
                  if (undoable && !undone)
                    TextButton.icon(
                      onPressed: () => _restoreSingle(log),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('استرجاع', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (isBulk && !undone && (bulkGroup?.isNotEmpty ?? false))
                    TextButton.icon(
                      onPressed: () => _restoreGroup(bulkGroup!),
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text('استرجاع الفعيلة (تحديد)', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.successColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

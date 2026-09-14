import 'package:flutter/material.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:cashier_system/features/customers/presentation/pages/customer_details_page.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({Key? key}) : super(key: key);

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    final customers = await DatabaseHelper.instance.getAllCustomers();
    if (mounted) {
      setState(() {
        _customers = customers;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _customers;
    return _customers.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      final phone = (c['phone'] as String? ?? '').toLowerCase();
      return name.contains(_search.toLowerCase()) || phone.contains(_search.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة العملاء', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCustomers,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // شريط البحث
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو الجوال...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _search = ''),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                // العدد
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text('${_filtered.length} عميل', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showAddDialog(),
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('إضافة عميل'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // القائمة
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline, size: 48, color: AppTheme.textSecondary),
                              SizedBox(height: 8),
                              Text('لا يوجد عملاء', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _buildCustomerCard(_filtered[i]),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    final id = customer['id'] as int;
    final name = customer['name'] as String? ?? '';
    final phone = customer['phone'] as String? ?? '';
    final address = customer['address'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withAlpha(30),
          child: Text(
            name.isNotEmpty ? name[0] : '?',
            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          [if (phone.isNotEmpty) phone, if (address.isNotEmpty) address].join(' | '),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CustomerDetailsPage(customerName: name)),
          );
        },
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _showEditDialog(customer);
            if (v == 'delete') _deleteCustomer(id, name);
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'edit', child: Row(
              children: [Icon(Icons.edit, size: 18, color: AppTheme.primaryColor), SizedBox(width: 8), Text('تعديل')],
            )),
            const PopupMenuItem(value: 'delete', child: Row(
              children: [Icon(Icons.delete, size: 18, color: AppTheme.errorColor), SizedBox(width: 8), Text('حذف')],
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final result = await _showCustomerForm();
    if (result != null) {
      final id = await DatabaseHelper.instance.insertCustomer(
        result['name']!,
        phone: result['phone']!,
        address: result['address']!,
        notes: result['notes']!,
      );
      if (id == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اسم العميل موجود مسبقاً'), backgroundColor: AppTheme.errorColor),
          );
        }
      } else if (id > 0) {
        _loadCustomers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمت إضافة العميل'), backgroundColor: AppTheme.successColor),
          );
        }
      }
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> customer) async {
    final result = await _showCustomerForm(
      name: customer['name'] as String? ?? '',
      phone: customer['phone'] as String? ?? '',
      address: customer['address'] as String? ?? '',
      notes: customer['notes'] as String? ?? '',
    );
    if (result != null) {
      await DatabaseHelper.instance.updateCustomer(
        customer['id'] as int,
        name: result['name']!,
        phone: result['phone']!,
        address: result['address']!,
        notes: result['notes']!,
      );
      _loadCustomers();
    }
  }

  Future<Map<String, String>?> _showCustomerForm({
    String name = '',
    String phone = '',
    String address = '',
    String notes = '',
  }) async {
    final nameCtrl = TextEditingController(text: name);
    final phoneCtrl = TextEditingController(text: phone);
    final addressCtrl = TextEditingController(text: address);
    final notesCtrl = TextEditingController(text: notes);

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          name.isEmpty ? 'إضافة عميل' : 'تعديل العميل',
          style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'اسم العميل *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الجوال',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('اسم العميل مطلوب'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              Navigator.pop(ctx, {
                'name': nameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
                'address': addressCtrl.text.trim(),
                'notes': notesCtrl.text.trim(),
              });
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomer(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف العميل "$name"', style: const TextStyle(color: AppTheme.errorColor)),
        content: const Text('هل أنت متأكد من حذف هذا العميل؟'),
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
    if (confirmed != true) return;

    final result = await DatabaseHelper.instance.deleteCustomer(id);
    if (result == -2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن حذف العميل لوجود ديون مسجلة'), backgroundColor: AppTheme.errorColor),
        );
      }
    } else {
      _loadCustomers();
    }
  }
}

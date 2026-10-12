import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/database_helper.dart';
// import '../services/error_logger.dart';
import '../services/pin_hash.dart';
import '../services/dev_lock_service.dart';
import '../widgets/error_boundary.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/products/presentation/pages/products_page.dart';
import '../../features/sales/presentation/pages/sales_page.dart';
import '../../features/debts/presentation/pages/debts_page.dart';
import '../../features/customers/presentation/pages/customers_page.dart';
import '../../features/top_selling/presentation/pages/top_selling_page.dart';
import '../../features/expenses/presentation/pages/expenses_page.dart';
import '../../features/settings/presentation/pages/dev_settings_page.dart';
import '../theme/app_theme.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  // الصفحات المقفلة: مفاتيح تم التحقق منها بنجاح في هذه الجلسة
  // لا يُضاف المفتاح إلا بعد إدخال PIN صحيح — القفل الفارغ لا يُثبّت
  final Set<String> _sessionUnlockedKeys = <String>{};

  // تسلسل الأحرف السري لفتح صفحة المطور: Ctrl+Alt+Shift + d e v m h
  static const _devSequence = [
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyV,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.keyH,
  ];
  int _devProgress = 0;

  // استخدام IndexedStack ضروري جداً للحفاظ على الفاتورة مفتوحة عند التنقل للأقسام الأخرى
  final List<Widget> _pages = [
    const PosPage(), // شاشة الكاشير (Index 0)
    const ProductsPage(), // شاشة إدارة المنتجات (Index 1)
    const SalesPage(), // شاشة المبيعات (Index 2)
    const DebtsPage(), // شاشة الديون (Index 3)
    const CustomersPage(), // شاشة العملاء (Index 4)
    const TopSellingPage(), // شاشة الأكثر مبيعاً (Index 5)
    const ExpensesPage(), // شاشة المصروفات (Index 6)
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  // ─── حوار طلب الرمز ───
  Future<bool> _askForPin(String settingKey, String pageTitle) async {
    final savedPin = await DatabaseHelper.instance.getSetting(settingKey, defaultValue: '');
    if (savedPin.isEmpty) return true; // لا يوجد رمز = مفتوح (لا يُثبّت شيء)
    if (_sessionUnlockedKeys.contains(settingKey)) return true; // تم التحقق مسبقاً هذه الجلسة

    final pinCtrl = TextEditingController();
    String errorText = '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void tryPin() {
            if (PinHash.verify(pinCtrl.text, savedPin)) {
              Navigator.pop(ctx, true);
            } else {
              setDialogState(() {
                errorText = 'الرمز غير صحيح، حاول مرة أخرى';
                pinCtrl.clear();
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.lock, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                Text('رمز الدخول — $pageTitle'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: '••••',
                    border: const OutlineInputBorder(),
                    errorText: errorText.isEmpty ? null : errorText,
                  ),
                  onChanged: (_) {
                    if (errorText.isNotEmpty) {
                      setDialogState(() => errorText = '');
                    }
                  },
                  onSubmitted: (_) => tryPin(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                onPressed: tryPin,
                child: const Text('دخول'),
              ),
            ],
          );
        },
      ),
    );

    final ok = result == true;
    if (ok) _sessionUnlockedKeys.add(settingKey); // ثبّت فقط بعد نجاح التحقق
    return ok;
  }

  Future<void> _onTabTap(int index) async {
    if (index == _currentIndex) return;

    // فحص PIN للصفحات المقفلة
    const tabPins = <int, (String, String)>{
      1: ('products_pin', 'المنتجات'),
      2: ('sales_pin', 'المبيعات'),
      3: ('debts_pin', 'الديون'),
      4: ('customers_pin', 'العملاء'),
      5: ('top_selling_pin', 'الأكثر مبيعاً'),
      6: ('expenses_pin', 'المصروفات'),
    };

    final pinInfo = tabPins[index];
    if (pinInfo != null) {
      final ok = await _askForPin(pinInfo.$1, pinInfo.$2);
      if (!ok) return;
    }

    setState(() => _currentIndex = index);

    // إعلام الصفحة الأولى (الكاشير) بظهورها أو إخفائها
    PosPage.setPageVisible(_currentIndex == 0);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed;
    final isAlt = kb.isAltPressed;
    final isShift = kb.isShiftPressed;

    if (isCtrl && isAlt && isShift) {
      if (event.logicalKey == _devSequence[_devProgress]) {
        _devProgress++;
        if (_devProgress == _devSequence.length) {
          _devProgress = 0;
          // فتح صفحة المطور بعد اكتمال التسلسل
          WidgetsBinding.instance.addPostFrameCallback((_) => _openDevSettings());
        }
        return true;
      } else {
        // إعادة تعيين وفحص إذا كان هذا الحرف بداية التسلسل
        _devProgress = event.logicalKey == _devSequence[0] ? 1 : 0;
        return false;
      }
    } else {
      _devProgress = 0;
      return false;
    }
  }

  void _openDevSettings() async {
    if (!mounted) return;

    // فحص القفل
    final isLocked = await DevLockService.instance.isSetup();
    if (isLocked && mounted) {
      final entered = await showDialog<bool>(
        context: context,
        builder: (ctx) => _DevLockDialog(),
      );
      if (entered != true) return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: _pages.asMap().entries.map((entry) {
          final contexts = ['الكاشير', 'المنتجات', 'المبيعات', 'الديون', 'العملاء', 'الأكثر مبيعاً', 'المصروفات'];
          return Offstage(
            offstage: entry.key != _currentIndex,
            child: ErrorBoundary(
              pageName: contexts[entry.key],
              child: entry.value,
            ),
          );
        }).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
        selectedItemColor: AppTheme.primaryColor,
        unselectedItemColor: AppTheme.textSecondary,
        backgroundColor: AppTheme.surfaceColor,
        elevation: 10,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'الكاشير',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2),
            label: 'المخزن',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'المبيعات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'الديون',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'العملاء',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'الأكثر مبيعاً',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'المصروفات',
          ),
        ],
      ),
    );
  }
}

/// حوار فتح قفل صفحة المطور
class _DevLockDialog extends StatefulWidget {
  @override
  State<_DevLockDialog> createState() => _DevLockDialogState();
}

class _DevLockDialogState extends State<_DevLockDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final input = _ctrl.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'أدخل كلمة المرور');
      return;
    }
    // إضافة الوقت الحالي تلقائياً (YYYYMMDDHHmm)
    final now = DateTime.now();
    final timeStr = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final fullInput = '$input$timeStr';
    final ok = await DevLockService.instance.verify(fullInput);
    if (ok) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _error = 'كلمة السر خاطئة');
      _ctrl.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🔒  قفل المطور', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            focusNode: _focus,
            obscureText: true,
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(
              hintText: 'أدخل كلمة المرور فقط',
              prefixIcon: const Icon(Icons.vpn_key, size: 18),
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
          onPressed: _verify,
          child: const Text('فتح'),
        ),
      ],
    );
  }
}
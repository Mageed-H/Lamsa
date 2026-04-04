import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/database_helper.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/products/presentation/pages/products_page.dart';
import '../../features/sales/presentation/pages/sales_page.dart';
import '../../features/settings/presentation/pages/dev_settings_page.dart';
import '../theme/app_theme.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  // الصفحات المقفلة/المفتوحة: true = مفتوح بعد إدخال PIN هذه الجلسة
  bool _productsUnlocked = false;
  bool _salesUnlocked = false;

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
    if (savedPin.isEmpty) return true; // لا يوجد رمز = مفتوح

    final pinCtrl = TextEditingController();
    String errorText = '';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void tryPin() {
            if (pinCtrl.text == savedPin) {
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
    return result == true;
  }

  Future<void> _onTabTap(int index) async {
    if (index == _currentIndex) return;

    // فحص PIN للمنتجات
    if (index == 1 && !_productsUnlocked) {
      final ok = await _askForPin('products_pin', 'المنتجات');
      if (!ok) return;
      _productsUnlocked = true;
    }

    // فحص PIN للمبيعات
    if (index == 2 && !_salesUnlocked) {
      final ok = await _askForPin('sales_pin', 'المبيعات');
      if (!ok) return;
      _salesUnlocked = true;
    }

    setState(() => _currentIndex = index);
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

  void _openDevSettings() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DevSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
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
            label: 'المخزن والمنتجات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'المبيعات',
          ),
        ],
      ),
    );
  }
}
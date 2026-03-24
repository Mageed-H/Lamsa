import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
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
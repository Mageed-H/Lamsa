import 'package:flutter/material.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/products/presentation/pages/products_page.dart';
import '../theme/app_theme.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({Key? key}) : super(key: key);

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  // استخدام IndexedStack ضروري جداً للحفاظ على الفاتورة مفتوحة عند التنقل للأقسام الأخرى
  final List<Widget> _pages = [
    const PosPage(), // شاشة الكاشير (Index 0)
    const ProductsPage(), // شاشة إدارة المنتجات (Index 1)
    const Center(child: Text('شاشة المبيعات (قريباً)', style: TextStyle(fontSize: 24, color: AppTheme.primaryColor))), // (Index 2)
  ];

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
import 'package:flutter/material.dart';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cashier_system/core/database/database_helper.dart';
import 'package:cashier_system/core/theme/app_theme.dart';
import 'package:cashier_system/features/products/data/models/product_model.dart';
import 'package:cashier_system/core/services/error_logger.dart';
import 'package:cashier_system/features/sales/presentation/pages/sales_page.dart';

class PosPage extends StatefulWidget {
  const PosPage({Key? key}) : super(key: key);

  /// طھط­ط¯ظٹط« ط­ط§ظ„ط© ط¸ظ‡ظˆط± ط§ظ„طµظپط­ط© â€” ظٹظڈط³طھط¯ط¹ظ‰ ظ…ظ† MainLayout ط¹ظ†ط¯ طھط¨ط¯ظٹظ„ ط§ظ„طھط¨ظˆظٹط¨
  static void setPageVisible(bool visible) {
    _PosPageState.instance?.setPageVisible(visible);
  }

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  // static instance ظ„ظ„ظˆطµظˆظ„ ظ…ظ† ظ…ط³طھظ…ط¹ ط¯ظˆط±ط© ط§ظ„ط­ظٹط§ط©
  static _PosPageState? instance;

  // ظ‡ظ„ ط§ظ„طµظپط­ط© ط¸ط§ظ‡ط±ط© ط­ط§ظ„ظٹط§ظ‹طں (ظٹظڈط­ط¯ظ‘ط« ظ…ظ† MainLayout ط¹ظ†ط¯ طھط¨ط¯ظٹظ„ ط§ظ„طھط¨ظˆظٹط¨)
  bool _isPageVisible = true;

  // ظ„ظ„طھط­ظƒظ… ط¨ط­ظ‚ظ„ ط§ظ„ط¨ط§ط±ظƒظˆط¯ ظˆط¨ظ‚ط§ط، ط§ظ„طھط±ظƒظٹط² (Focus) ط¹ظ„ظٹظ‡ ط¯ط§ط¦ظ…ط§ظ‹
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  // ط³ظ„ط© ط§ظ„ظ…ط´طھط±ظٹط§طھ (ط§ظ„ظپط§طھظˆط±ط© ط§ظ„ط­ط§ظ„ظٹط©): ظ†ط­ظپط¸ ط¨ظٹظ‡ط§ ط§ظ„ظ…ظ†طھط¬ ظˆط§ظ„ظƒظ…ظٹط©
  final List<Map<String, dynamic>> _cart = [];
  bool _hasSuspendedOrders = false;
  // ظ…ظ†طھط¬ط§طھ ط§ظ„ظ…ط®ط²ظˆظ† ط§ظ„ظ…ظ†ط®ظپط¶
  List<ProductModel> _lowStockProducts = [];
  // ظ‚ط§ط¦ظ…ط© ط¬ظ…ظٹط¹ ط§ظ„ظ…ظ†طھط¬ط§طھ (ظ„ظ„ط¨ط­ط«)
  List<ProductModel> _allProducts = [];
  // ط§ظ„ط®طµظ…
  int _discountAmount = 0;
  bool _isDiscountPercent = false;
  // ط¢ط®ط± ظپط§طھظˆط±ط© (ظ„ط¥ط¹ط§ط¯ط© ط§ظ„ط·ط¨ط§ط¹ط©)
  List<Map<String, dynamic>>? _lastPrintCart;
  int _lastPrintSubtotal = 0;
  int _lastPrintDiscount = 0;
  int _lastPrintTotal = 0;
  int _lastPrintGiven = 0;
  int _lastPrintChange = 0;
  int? _lastPrintSaleId;
  String? _lastPrintCustomerName;
  // طھطµظپظٹط© ط§ظ„ظ…ظ†طھط¬ط§طھ
  String? _posSelectedCategory;
  // ط¨ط­ط« ط¨ط§ظ„ط§ط³ظ…/ط§ظ„ظ„ظˆظ†/ط§ظ„ظ‚ظٹط§ط³
  String _posSearchQuery = '';
  // ظ…ط¹ط±ظ‘ظپ ط§ظ„ظ…ط³ظˆط¯ط© ط§ظ„طھظ„ظ‚ط§ط¦ظٹط© ط§ظ„ط­ط§ظ„ظٹط©
  int? _autoDraftOrderId;

  @override
  void initState() {
    super.initState();
    instance = this;
    DatabaseHelper.productsRevision.addListener(_loadAllProducts);
    // ظ…ط³طھظ…ط¹ ظٹط±ط¬ط¹ ط§ظ„طھط±ظƒظٹط² طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ظ„ط­ظ‚ظ„ ط§ظ„ط¨ط§ط±ظƒظˆط¯ ظƒظ„ ظ…ط§ ظٹط¶ظٹط¹
    _barcodeFocusNode.addListener(_autoRefocus);
    // ظ…ط±ط§ظ‚ط¨ ط¯ظˆط±ط© ط­ظٹط§ط© ط§ظ„طھط·ط¨ظٹظ‚ â€” ظٹط­ظپط¸ ط§ظ„ط³ظ„ط© طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ط¹ظ†ط¯ ط§ظ„ط®ط±ظˆط¬
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    // ط£ظˆظ„ ظ…ط§ طھظپطھط­ ط§ظ„ط´ط§ط´ط©طŒ ظ†ط®ظ„ظٹ ط§ظ„طھط±ظƒظٹط² طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ط¹ظ„ظ‰ ط­ظ‚ظ„ ط§ظ„ط¨ط§ط±ظƒظˆط¯
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_barcodeFocusNode);
      _checkSuspendedOrders();
      _loadAllProducts();
      _restoreAutoDraft();
    });
  }

  @override
  void dispose() {
    instance = null;
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    DatabaseHelper.productsRevision.removeListener(_loadAllProducts);
    _barcodeFocusNode.removeListener(_autoRefocus);
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  // ظ…ط±ط§ظ‚ط¨ ط¯ظˆط±ط© ط­ظٹط§ط© ط§ظ„طھط·ط¨ظٹظ‚ â€” ظٹط­ظپط¸ ط§ظ„ط³ظ„ط© ط¹ظ†ط¯ ط§ظ„ط®ط±ظˆط¬ ظ„ظ„ط®ظ„ظپظٹط©
  final _lifecycleObserver = _PosLifecycleObserver();

  // طھظ†ط¸ظٹظپ ظ…ط¯ط®ظ„ط§طھ ط§ظ„ظ…ط§ط³ط­ ط§ظ„ط¶ظˆط¦ظٹ ظ…ظ† ط§ظ„ط±ظ…ظˆط² ط§ظ„ط²ط§ط¦ط¯ط© (ظ…ط«ظ„ {#\ ط§ظ„ظ„ظٹ طھط·ظ„ط¹ ظ…ظ† طھط¨ط¯ظٹظ„ ط£ظ†ظ…ط§ط· Code128)
  String _cleanBarcode(String raw) {
    return raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9\-]'), '');
  }

  // ط§ظ„ط¯ط§ظ„ط© ط§ظ„ط³ط­ط±ظٹط© ط§ظ„ظ„ظٹ طھط´طھط؛ظ„ ظ…ظ† ظ†ط¶ط±ط¨ ط§ظ„ط¨ط§ط±ظƒظˆط¯ ط¨ط§ظ„ط¬ظ‡ط§ط²
  Future<void> _onBarcodeScanned(String barcode) async {
    try {
    final cleanBarcode = _cleanBarcode(barcode);
    if (cleanBarcode.isEmpty) {
      _keepFocus();
      return;
    }

    // ظ†ط¨ط­ط« ط¹ظ† ط§ظ„ظ…ظ†طھط¬ ط¨ظ‚ط§ط¹ط¯ط© ط§ظ„ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط­ظ„ظٹط© (ط¨ط³ط±ط¹ط© ط§ظ„ط¨ط±ظ‚)
    final product = await DatabaseHelper.instance.getProductByBarcode(
      cleanBarcode,
    );

    if (product != null) {
      // ظپط­طµ ط§ظ„ظ…ط®ط²ظˆظ† ظ‚ط¨ظ„ ط§ظ„ط¥ط¶ط§ظپط©
      final int currentInCart = _cart
          .where((i) => (i['product'] as ProductModel).id == product.id)
          .fold<int>(0, (s, i) => s + (i['quantity'] as int));
      if (currentInCart >= product.stock) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'ظ„ط§ ظٹظ…ظƒظ† ط¥ط¶ط§ظپط© ط§ظ„ظ…ط²ظٹط¯! ط§ظ„ظ…ط®ط²ظˆظ† ظ…ظ† â€œ${product.name}â€‌ = ${product.stock} ظ‚ط·ط¹ط©',
              ),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        _barcodeController.clear();
        _keepFocus();
        return;
      }
      setState(() {
        // ط¥ط°ط§ ط§ظ„ظ…ظ†طھط¬ ظ…ظˆط¬ظˆط¯ ظ…ط³ط¨ظ‚ط§ظ‹ ط¨ط§ظ„ظپط§طھظˆط±ط©طŒ ظ†ط²ظٹط¯ ط§ظ„ظƒظ…ظٹط© ظپظ‚ط·
        int index = _cart.indexWhere(
          (item) => (item['product'] as ProductModel).id == product.id,
        );
        if (index >= 0) {
          _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + 1;
        } else {
          // ط¥ط°ط§ ظ…ظ†طھط¬ ط¬ط¯ظٹط¯طŒ ظ†ط¶ظٹظپظ‡ ظ„ظ„ظپط§طھظˆط±ط© ط¨ظƒظ…ظٹط© 1
          _cart.add({'product': product, 'quantity': 1});
        }
        _posSearchQuery = '';
      });

      // ظپط­طµ ط§ظ„ظ…ط®ط²ظˆظ† ظˆطھظ†ط¨ظٹظ‡ ط¥ط°ط§ ظƒط§ظ† ظ‚ظ„ظٹظ„ط§ظ‹
      final thresholdStr = await DatabaseHelper.instance.getSetting(
        'low_stock_threshold',
        defaultValue: '5',
      );
      final threshold = int.tryParse(thresholdStr) ?? 5;
      final totalInCart = _cart
          .where((i) => (i['product'] as ProductModel).id == product.id)
          .fold<int>(0, (s, i) => s + (i['quantity'] as int));
      final remaining = product.stock - totalInCart;
      if (remaining <= threshold && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remaining <= 0
                  ? 'âڑ ï¸ڈ طھط­ط°ظٹط±: ظ…ط®ط²ظˆظ† "${product.name}" ظ†ظپط¯ ط¨ط§ظ„ظƒط§ظ…ظ„!'
                  : 'âڑ ï¸ڈ طھظ†ط¨ظٹظ‡: ط§ظ„ظ…ط®ط²ظˆظ† ط§ظ„ظ…طھط¨ظ‚ظٹ ظ…ظ† "${product.name}" = $remaining ظ‚ط·ط¹ط© ظپظ‚ط·!',
            ),
            backgroundColor: remaining <= 0
                ? AppTheme.errorColor
                : AppTheme.warningColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      // طھط·ط¨ظٹظ‚ Robustness: ط¥ط°ط§ ط§ظ„ط¨ط§ط±ظƒظˆط¯ ط؛ظ„ط·طŒ ظ†ظ†ط¨ظ‡ ط§ظ„ظƒط§ط´ظٹط± ط¨ط¯ظˆظ† ظ…ط§ ظٹظƒط±ط´ ط§ظ„ظ†ط¸ط§ظ…
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ط§ظ„ظ…ظ†طھط¬ ط؛ظٹط± ظ…ظˆط¬ظˆط¯ ظپظٹ ظ‚ط§ط¹ط¯ط© ط§ظ„ط¨ظٹط§ظ†ط§طھ!',
              style: TextStyle(fontFamily: 'Tahoma'),
            ),
            backgroundColor: AppTheme.errorColor,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    // ظ†ظپط±ط؛ ط§ظ„ط­ظ‚ظ„ ظˆظ†ط±ط¬ط¹ ط§ظ„طھط±ظƒظٹط² ط¹ظ„ظٹظ‡ ط§ط³طھط¹ط¯ط§ط¯ط§ظ‹ ظ„ظ„ظ‚ط·ط¹ط© ط§ظ„ظ„ظٹ ط¨ط¹ط¯ظ‡ط§
    _barcodeController.clear();
    _keepFocus();
    } catch (e, st) {
      await ErrorLogger.instance.logError(e, st, context: 'ظ…ط³ط­ ط¨ط§ط±ظƒظˆط¯');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ط®ط·ط£ ظپظٹ ط§ظ„ظ…ط³ط­: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
      _barcodeController.clear();
      _keepFocus();
    }
  }

  // ط¯ط§ظ„ط© ظ…ط³ط§ط¹ط¯ط© ظ„ظ„ط­ظپط§ط¸ ط¹ظ„ظ‰ ط§ظ„طھط±ظƒظٹط²
  void _keepFocus() {
    if (!_isPageVisible || !mounted) return;
    FocusScope.of(context).requestFocus(_barcodeFocusNode);
  }

  // طھط­ط¯ظٹط« ط­ط§ظ„ط© ط§ظ„ط¸ظ‡ظˆط± â€” ظٹظڈط³طھط¯ط¹ظ‰ ظ…ظ† MainLayout ط¹ظ†ط¯ طھط¨ط¯ظٹظ„ ط§ظ„طھط¨ظˆظٹط¨
  void setPageVisible(bool visible) {
    _isPageVisible = visible;
    if (visible && mounted) {
      _loadAllProducts();
    } else if (!visible && mounted) {
      // ظ„ظ…ط§ ط§ظ„طµظپط­ط© طھط®طھظپظٹطŒ ظ†ط²ظٹظ„ ط§ظ„ظ…ط¤ط´ط± ظ…ظ† ط­ظ‚ظ„ ط§ظ„ط¨ط§ط±ظƒظˆط¯
      _barcodeFocusNode.unfocus();
    }
  }

  // ط­ظپط¸ ط§ظ„ط³ظ„ط© طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ط¹ظ†ط¯ ط§ظ„ط®ط±ظˆط¬ ظ„ظ„ط®ظ„ظپظٹط©
  void _saveAutoDraft() {
    if (_cart.isNotEmpty) {
      DatabaseHelper.instance.saveAutoDraft(
        _cart,
        discountAmount: _discountAmount,
        isDiscountPercent: _isDiscountPercent,
      );
    }
  }

  // ط§ط³طھط±ط¬ط§ط¹ ط§ظ„ظ…ط³ظˆط¯ط© ط§ظ„طھظ„ظ‚ط§ط¦ظٹط© ط¹ظ†ط¯ ط¨ط¯ط، ط§ظ„طھط·ط¨ظٹظ‚
  Future<void> _restoreAutoDraft() async {
    final draft = await DatabaseHelper.instance.loadAutoDraft();
    if (draft == null || !mounted) return;
    final cart = draft['cart'] as List<Map<String, dynamic>>;
    if (cart.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ط§ط³طھط±ط¬ط§ط¹ ط§ظ„ط³ظ„ط©', style: TextStyle(color: AppTheme.primaryColor)),
        content: Text('ظˆط¬ط¯ظ†ط§ ط³ظ„ط© ظ…ط­ظپظˆط¸ط© ظ…ظ† ط¢ط®ط± ظ…ط±ط© (${cart.length} طµظ†ظپ).\nظ‡ظ„ طھط±ظٹط¯ ط§ط³طھط±ط¬ط§ط¹ظ‡ط§طں'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ظ„ط§')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ظ†ط¹ظ…طŒ ط§ط³طھط±ط¬ط§ط¹'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _cart.addAll(cart);
        _discountAmount = draft['discount_amount'] as int? ?? 0;
        _isDiscountPercent = draft['is_discount_percent'] as bool? ?? false;
      });
      _autoDraftOrderId = draft['order_id'] as int?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('طھظ… ط§ط³طھط±ط¬ط§ط¹ ط§ظ„ط³ظ„ط© (${cart.length} طµظ†ظپ)'), backgroundColor: AppTheme.successColor),
      );
    } else {
      // ط­ط°ظپ ط§ظ„ظ…ط³ظˆط¯ط© ط¥ط°ط§ ط§ظ„ظ…ط³طھط®ط¯ظ… ط±ظپط¶ ط§ظ„ط§ط³طھط±ط¬ط§ط¹
      final orderId = draft['order_id'] as int?;
      if (orderId != null) {
        await DatabaseHelper.instance.clearAutoDraft(orderId);
      }
    }
  }

  // ط¥ط¶ط§ظپط© ظ…ظ†طھط¬ ظ…ط¨ط§ط´ط±ط© ظ…ظ† ط§ظ„ظƒط±ظˆطھ (ط¨ط¯ظˆظ† ط¨ط§ط±ظƒظˆط¯)
  void _addProductToCart(ProductModel product) {
    final int currentInCart = _cart
        .where((i) => (i['product'] as ProductModel).id == product.id)
        .fold<int>(0, (s, i) => s + (i['quantity'] as int));
    if (currentInCart >= product.stock) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ظ„ط§ ظٹظ…ظƒظ† ط¥ط¶ط§ظپط© ط§ظ„ظ…ط²ظٹط¯! ط§ظ„ظ…ط®ط²ظˆظ† ظ…ظ† "${product.name}" = ${product.stock} ظ‚ط·ط¹ط©'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    setState(() {
      int index = _cart.indexWhere((item) => (item['product'] as ProductModel).id == product.id);
      if (index >= 0) {
        _cart[index]['quantity'] = (_cart[index]['quantity'] as int) + 1;
      } else {
        _cart.add({'product': product, 'quantity': 1});
      }
    });
  }

  List<ProductModel> get _filteredPosProducts {
    var list = _allProducts;

    // ظپظ„طھط±ط© ط­ط³ط¨ ط§ظ„ظ‚ط³ظ… ط§ظ„ظ…ط­ط¯ط¯
    if (_posSelectedCategory != null && _posSelectedCategory!.isNotEmpty) {
      list = list.where((p) => p.category == _posSelectedCategory).toList();
    }

    // ظپظ„طھط±ط© ط°ظƒظٹط© ط¨ط§ظ„ط§ط³ظ…/ط§ظ„ظ„ظˆظ†/ط§ظ„ظ‚ظٹط§ط³
    if (_posSearchQuery.isNotEmpty) {
      final query = _posSearchQuery.toLowerCase();
      final words = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty) {
        list = list.where((p) {
          final name = p.name.toLowerCase();
          final color = p.color.toLowerCase();
          final size = p.size.toLowerCase();
          return words.every((word) =>
            name.contains(word) ||
            color.contains(word) ||
            size.contains(word)
          );
        }).toList();
      }
    }

    return list;
  }

  // ظٹط±ط¬ط¹ ط§ظ„طھط±ظƒظٹط² طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ظ„ط­ظ‚ظ„ ط§ظ„ط¨ط§ط±ظƒظˆط¯ ط¨ط¹ط¯ ظƒظ„ ظپط±ظٹظ… ط¥ط°ط§ ط¶ط§ط¹
  // ظ„ظƒظ† ظپظ‚ط· ط¥ط°ط§ ط§ظ„طµظپط­ط© ظ‡ظٹ ط§ظ„ظ€ route ط§ظ„ظ†ط´ط· (ظ…ط§ ظٹط³ط±ظ‚ ط§ظ„ظپظˆظƒط³ ظ…ظ† ط§ظ„ط­ظˆط§ط±ط§طھ)
  void _autoRefocus() {
    if (!_isPageVisible || !_barcodeFocusNode.hasFocus || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isPageVisible && !_barcodeFocusNode.hasFocus) {
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent) {
          _barcodeFocusNode.requestFocus();
        }
      }
    });
  }

  Future<void> _checkSuspendedOrders() async {
    final orders = await DatabaseHelper.instance.getSuspendedOrders();
    if (mounted) setState(() => _hasSuspendedOrders = orders.isNotEmpty);
  }

  // طھط¹ظ„ظٹظ‚ ط§ظ„ظپط§طھظˆط±ط© ظˆط­ظپط¸ظ‡ط§ ظپظٹ ط§ظ„ظ‚ط§ط¹ط¯ط©
  Future<void> _suspendOrder() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ط§ظ„ظپط§طھظˆط±ط© ظپط§ط±ط؛ط©طŒ ظ„ط§ ظٹظˆط¬ط¯ ظ…ط§ ظٹظڈط¹ظ„ظ‘ظ‚!')),
      );
      return;
    }
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'طھط¹ظ„ظٹظ‚ ط§ظ„ظپط§طھظˆط±ط©',
          style: TextStyle(color: AppTheme.warningColor),
        ),
        content: TextField(
          controller: noteController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ظ…ظ„ط§ط­ط¸ط© ط§ط®طھظٹط§ط±ظٹط© (ظ…ط«ط§ظ„: ط²ط¨ظˆظ†ط© ط¨ط§ظ„ط¨ط§ط¨)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warningColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('طھط¹ظ„ظٹظ‚'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final orderId = await DatabaseHelper.instance.saveSuspendedOrder(
        _cart,
        noteController.text,
        discountAmount: _discountAmount,
        isDiscountPercent: _isDiscountPercent,
      );
      // ظپط´ظ„ ط§ظ„ط­ظپط¸: ط§ظ„ط³ظ„ط© طھط¨ظ‚ظ‰ ظƒظ…ط§ ظ‡ظٹ â€” ط§ظ„ظƒط§ط´ظٹط± ظ„ط§ ظٹط®ط³ط± ط´ظٹط¦ط§ظ‹
      if (orderId <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ظپط´ظ„ طھط¹ظ„ظٹظ‚ ط§ظ„ظپط§طھظˆط±ط©! ط§ظ„ط³ظ„ط© ظ…ط­ظپظˆط¸ط© â€” ط­ط§ظˆظ„ ظ…ط¬ط¯ط¯ط§ظ‹'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        _keepFocus();
        return;
      }
      setState(() {
        _cart.clear();
        _discountAmount = 0;
        _isDiscountPercent = false;
        _hasSuspendedOrders = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('طھظ… طھط¹ظ„ظٹظ‚ ط§ظ„ظپط§طھظˆط±ط© ط¨ظ†ط¬ط§ط­ âœ“'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
      }
      _keepFocus();
    }
  }

  // طھظ‚ظ„ظٹظ„ ظƒظ…ظٹط© ظ…ظ†طھط¬ ظپظٹ ط§ظ„ط³ظ„ط© (ط£ظˆ ط­ط°ظپظ‡ ط¥ط°ط§ ظˆطµظ„ ظ„ظ€ 0)
  void _decreaseQty(int index) {
    setState(() {
      if ((_cart[index]['quantity'] as int) > 1) {
        _cart[index]['quantity'] = (_cart[index]['quantity'] as int) - 1;
      } else {
        _cart.removeAt(index);
      }
    });
    _keepFocus();
  }

  // ط²ظٹط§ط¯ط© ظƒظ…ظٹط© ظ…ظ†طھط¬ ظپظٹ ط§ظ„ط³ظ„ط©
  void _increaseQty(int index) {
    final product = _cart[index]['product'] as ProductModel;
    final qty = _cart[index]['quantity'] as int;
    if (qty >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ظ„ط§ ظٹظ…ظƒظ† ط¥ط¶ط§ظپط© ط§ظ„ظ…ط²ظٹط¯! ط§ظ„ظ…ط®ط²ظˆظ† ظ…ظ† â€œ${product.name}â€‌ = ${product.stock} ظ‚ط·ط¹ط©',
          ),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 2),
        ),
      );
      _keepFocus();
      return;
    }
    setState(() {
      _cart[index]['quantity'] = qty + 1;
    });
    _keepFocus();
  }

  // طھط¹ط¯ظٹظ„ ط³ط¹ط± ظ…ظ†طھط¬ ظپظٹ ط§ظ„ط³ظ„ط©
  void _editItemPrice(int index) {
    final item = _cart[index];
    final product = item['product'] as ProductModel;
    final currentPrice = (item['custom_price'] as int?) ?? product.price;
    final priceCtrl = TextEditingController(text: '$currentPrice');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('طھط¹ط¯ظٹظ„ ط³ط¹ط± â€” ${product.name}', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ط§ظ„ط³ط¹ط± ط§ظ„ط£طµظ„ظٹ: ${product.price} ط¯ظٹظ†ط§ط±', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'ط§ظ„ط³ط¹ط± ط§ظ„ط¬ط¯ظٹط¯',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _cart[index].remove('custom_price'));
              Navigator.pop(ctx);
            },
            child: const Text('ط¥ط¹ط§ط¯ط© ط§ظ„ط£طµظ„ظٹ', style: TextStyle(color: AppTheme.errorColor)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ط¥ظ„ط؛ط§ط،')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              final newPrice = int.tryParse(priceCtrl.text.trim());
              if (newPrice == null || newPrice <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('ط£ط¯ط®ظ„ ط³ط¹ط±ط§ظ‹ طµط­ظٹط­ط§ظ‹'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              if (newPrice < product.purchasePrice) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('ط§ظ„ط³ط¹ط± ظ„ط§ ظٹظ…ظƒظ† ط£ظ† ظٹظ‚ظ„ ط¹ظ† ط³ط¹ط± ط§ظ„ط´ط±ط§ط، '),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
                return;
              }
              setState(() => _cart[index]['custom_price'] = newPrice);
              Navigator.pop(ctx);
            },
            child: const Text('طھط·ط¨ظٹظ‚'),
          ),
        ],
      ),
    ).then((_) => _keepFocus());
  }

  void _editItemDiscount(int index) {
    final item = _cart[index];
    final product = item['product'] as ProductModel;
    final currentPrice = (item['custom_price'] as int?) ?? product.price;
    final currentDiscount = (item['item_discount'] as int?) ?? 0;
    final discountCtrl = TextEditingController(text: currentDiscount > 0 ? '$currentDiscount' : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ط®طµظ… ط¹ظ„ظ‰ â€” ${product.name}', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ط§ظ„ط³ط¹ط±: $currentPrice ط¯ظٹظ†ط§ط±', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: discountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'ظ…ط¨ظ„ط؛ ط§ظ„ط®طµظ… (ط¯ظٹظ†ط§ط±)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.discount),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _cart[index].remove('item_discount'));
              Navigator.pop(ctx);
            },
            child: const Text('ط¥ط²ط§ظ„ط© ط§ظ„ط®طµظ…', style: TextStyle(color: AppTheme.errorColor)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ط¥ظ„ط؛ط§ط،')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            onPressed: () {
              final discount = int.tryParse(discountCtrl.text.trim()) ?? 0;
              if (discount < 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('ط§ظ„ط®طµظ… ظ„ط§ ظٹظ…ظƒظ† ط£ظ† ظٹظƒظˆظ† ط³ط§ظ„ط¨ط§ظ‹'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              if (discount >= currentPrice) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('ط§ظ„ط®طµظ… ظ„ط§ ظٹظ…ظƒظ† ط£ظ† ظٹط³ط§ظˆظٹ ط£ظˆ ظٹطھط¬ط§ظˆط² ط§ظ„ط³ط¹ط±'), backgroundColor: AppTheme.errorColor),
                );
                return;
              }
              setState(() {
                if (discount > 0) {
                  _cart[index]['item_discount'] = discount;
                } else {
                  _cart[index].remove('item_discount');
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('طھط·ط¨ظٹظ‚'),
          ),
        ],
      ),
    ).then((_) => _keepFocus());
  }

  // ط­ظˆط§ط± ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ†: ط§ط®طھظٹط§ط± ط¹ظ…ظٹظ„ + ط¥ظ†ط´ط§ط، ط§ظ„ط¯ظٹظ†
  Future<void> _showDebtSaleDialog() async {
    if (_cart.isEmpty) return;

    final int total = _finalTotal;
    final int discountVal = _discountValue;
    final customers = await DatabaseHelper.instance.getDebtCustomers();
    String searchQuery = '';
    String? selectedCustomer;
    String? selectedPhone;
    final newCustomerController = TextEditingController();
    final newPhoneController = TextEditingController();
    bool useNewCustomer = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filteredCustomers = customers.where((c) {
            if (searchQuery.isEmpty) return true;
            final name = (c['customer_name'] as String).toLowerCase();
            final phone = (c['phone'] as String?)?.toLowerCase() ?? '';
            return name.contains(searchQuery.toLowerCase()) || phone.contains(searchQuery.toLowerCase());
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.person_add_outlined, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ†', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ط§ظ„ظ…ط¨ظ„ط؛
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('ط§ظ„ظ…ط¨ظ„ط؛ ط§ظ„ظ…ط³طھط­ظ‚:', style: TextStyle(fontSize: 14)),
                        Text('$total ط¯ظٹظ†ط§ط±', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ط§ظ„طھط¨ط¯ظٹظ„ ط¨ظٹظ† ط¹ظ…ظٹظ„ ظ…ظˆط¬ظˆط¯ / ط¹ظ…ظٹظ„ ط¬ط¯ظٹط¯
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('ط¹ظ…ظٹظ„ ظ…ظˆط¬ظˆط¯', style: TextStyle(fontSize: 12)),
                        selected: !useNewCustomer,
                        onSelected: (_) => setDialogState(() => useNewCustomer = false),
                        selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('ط¹ظ…ظٹظ„ ط¬ط¯ظٹط¯', style: TextStyle(fontSize: 12)),
                        selected: useNewCustomer,
                        onSelected: (_) => setDialogState(() => useNewCustomer = true),
                        selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!useNewCustomer) ...[
                    // ط¨ط­ط«
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'ط¨ط­ط« ط¨ط§ظ„ط§ط³ظ… ط£ظˆ ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setDialogState(() => searchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    // ظ‚ط§ط¦ظ…ط© ط§ظ„ط¹ظ…ظ„ط§ط،
                    if (filteredCustomers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('ظ„ط§ ظٹظˆط¬ط¯ ط¹ظ…ظ„ط§ط،', style: TextStyle(color: AppTheme.textSecondary))),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredCustomers.length,
                          itemBuilder: (ctx, i) {
                            final c = filteredCustomers[i];
                            final name = c['customer_name'] as String;
                            final phone = (c['phone'] as String?) ?? '';
                            final remaining = c['remaining'] as int;
                            final isSelected = selectedCustomer == name;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: AppTheme.primaryColor.withOpacity(0.1),
                              leading: CircleAvatar(
                                backgroundColor: isSelected ? AppTheme.primaryColor : AppTheme.neutralLightColor,
                                child: Text(name[0], style: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text(phone.isNotEmpty ? phone : 'ط¨ط¯ظˆظ† ظ‡ط§طھظپ', style: const TextStyle(fontSize: 11)),
                              trailing: Text('$remaining ط¯', style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              onTap: () => setDialogState(() {
                                selectedCustomer = name;
                                selectedPhone = phone;
                              }),
                            );
                          },
                        ),
                      ),
                  ] else ...[
                    // ط¹ظ…ظٹظ„ ط¬ط¯ظٹط¯
                    TextField(
                      controller: newCustomerController,
                      decoration: InputDecoration(
                        labelText: 'ط§ط³ظ… ط§ظ„ط¹ظ…ظٹظ„ *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPhoneController,
                      decoration: InputDecoration(
                        labelText: 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ (ط§ط®طھظٹط§ط±ظٹ)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ط¥ظ„ط؛ط§ط،'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('طھط£ظƒظٹط¯ ط§ظ„ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ†'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  if (useNewCustomer) {
                    if (newCustomerController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ط£ط¯ط®ظ„ ط§ط³ظ… ط§ظ„ط¹ظ…ظٹظ„'), backgroundColor: AppTheme.errorColor),
                      );
                      return;
                    }
                    selectedCustomer = newCustomerController.text.trim();
                    selectedPhone = newPhoneController.text.trim();
                  }
                  if (selectedCustomer == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ط§ط®طھط± ط¹ظ…ظٹظ„ ط£ظˆ ط£ط¯ط®ظ„ ط§ط³ظ… ط¬ط¯ظٹط¯'), backgroundColor: AppTheme.errorColor),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) {
      newCustomerController.dispose();
      newPhoneController.dispose();
      _keepFocus();
      return;
  }

    // طھظ†ظپظٹط° ط§ظ„ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ†
    try {
      final cartSnapshot = List<Map<String, dynamic>>.from(_cart);
      final saleId = await DatabaseHelper.instance.completeSale(_cart, discountValue: discountVal, customerName: selectedCustomer ?? '');

      if (saleId > 0) {
        // ط¥ظ†ط´ط§ط، ط§ظ„ط¯ظٹظ† ظ…ط±طھط¨ط· ط¨ط§ظ„ظپط§طھظˆط±ط©
        await DatabaseHelper.instance.insertDebt(
          customerName: selectedCustomer!,
          phone: selectedPhone?.isNotEmpty == true ? selectedPhone : null,
          amount: total,
          note: 'ظپط§طھظˆط±ط© #$saleId',
          saleId: saleId,
        );

        // ط­ظپط¸ ط§ظ„ط¹ظ…ظٹظ„ ظپظٹ ط¬ط¯ظˆظ„ ط§ظ„ط¹ظ…ظ„ط§ط، ط¥ط°ط§ ط¬ط¯ظٹط¯ (insertCustomer ظٹطھط­ظ‚ظ‚ ظ…ظ† ط§ظ„طھظƒط±ط§ط±)
        await DatabaseHelper.instance.insertCustomer(
          selectedCustomer!,
          phone: selectedPhone ?? '',
        );

        // ظƒط³ط¨ ظ†ظ‚ط§ط· ط§ظ„ظˆظ„ط§ط،
        if (selectedCustomer != null && selectedCustomer!.isNotEmpty) {
          await DatabaseHelper.instance.earnLoyaltyPoints(selectedCustomer!, total);
        }

        if (mounted) {
          _lastPrintCart = cartSnapshot;
          _lastPrintSubtotal = _subtotal;
          _lastPrintDiscount = _discountValue;
          _lastPrintTotal = total;
          _lastPrintGiven = 0;
          _lastPrintChange = 0;
          _lastPrintSaleId = saleId;
          _lastPrintCustomerName = selectedCustomer;
          setState(() {
            _cart.clear();
            _discountAmount = 0;
            _isDiscountPercent = false;
          });

          // ط·ط¨ط§ط¹ط© ط§ظ„ظپط§طھظˆط±ط©
          try {
            await _printInvoice(cartSnapshot, _subtotal, _discountValue, total, 0, 0, saleId: saleId, customerName: selectedCustomer);
          } catch (e, st) {
            await ErrorLogger.instance.logError(e, st, context: 'ط·ط¨ط§ط¹ط© ظپط§طھظˆط±ط© ط¯ظٹظ†');
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('طھظ… ط§ظ„ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ† âœ“ | ط§ظ„ط¹ظ…ظٹظ„: $selectedCustomer | ط§ظ„ظ…ط¨ظ„ط؛: $total ط¯'),
              backgroundColor: AppTheme.primaryColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ط­ط¯ط« ط®ط·ط£ ط£ط«ظ†ط§ط، ط¥طھظ…ط§ظ… ط§ظ„ط¨ظٹط¹!'), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (e, st) {
      await ErrorLogger.instance.logError(e, st, context: 'ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ†');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ط®ط·ط£: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
    newCustomerController.dispose();
    newPhoneController.dispose();
    _keepFocus();
  }

  // ط­ظˆط§ط± ط§ظ„ط¯ظپط¹: ط­ط³ط§ط¨ ط§ظ„ظپظƒط© + ط§ط®طھظٹط§ط± ط§ظ„ط·ط¨ط§ط¹ط©
  Future<void> _showPaymentDialog() async {
    if (_cart.isEmpty) return;

    final int subtotal = _subtotal;
    int discountVal = _discountValue;
    int total = _finalTotal;
    final amountController = TextEditingController(text: '$total');
    bool shouldPrint = true;
    bool isCustomer = false;
    String customerName = '';
    String customerPhone = '';
    bool applyCustomerDiscount = false;
    int customerDiscountPercent = 0;
    bool usePointsDiscount = false;
    int pointsDiscountAmount = 0;
    final customerCtrl = TextEditingController();
    List<Map<String, dynamic>> allCustomerData = [];

    // طھط­ظ…ظٹظ„ ط£ط³ظ…ط§ط، ظˆط£ط±ظ‚ط§ظ… ط§ظ„ط¹ظ…ظ„ط§ط،
    final dbCustomers = await DatabaseHelper.instance.getAllCustomers();
    final debtNames = await DatabaseHelper.instance.getDebtCustomerNames();
    final debtPhones = await DatabaseHelper.instance.getDebtCustomerPhones();
    for (final c in dbCustomers) {
      allCustomerData.add({'name': c['name'] as String, 'phone': c['phone'] as String? ?? '', 'loyalty_points': c['loyalty_points'] as int? ?? 0});
    }
    for (int i = 0; i < debtNames.length; i++) {
      if (!allCustomerData.any((c) => c['name'] == debtNames[i])) {
        allCustomerData.add({'name': debtNames[i], 'phone': i < debtPhones.length ? debtPhones[i] : ''});
      }
    }

    void recalcTotal(int subtotal, TextEditingController ctrl) {
      discountVal = _discountValue;
      if (applyCustomerDiscount) {
        discountVal += subtotal * customerDiscountPercent ~/ 100;
      }
      if (usePointsDiscount) {
        discountVal += pointsDiscountAmount;
      }
      total = subtotal - discountVal;
      ctrl.text = '$total';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final given = int.tryParse(amountController.text) ?? 0;
          final change = (given - total).clamp(0, 9999999);
          final canConfirm = given >= total;

          return AlertDialog(
            title: const Text(
              'ط¥طھظ…ط§ظ… ط§ظ„ط¯ظپط¹',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ط¹ط±ط¶ ط§ظ„ط®طµظ… ط¥ط°ط§ ظƒط§ظ† ظ…ظˆط¬ظˆط¯ط§ظ‹
                if (discountVal > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$subtotal ط¯ظٹظ†ط§ط±',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      const Text(
                        'ظ‚ط¨ظ„ ط§ظ„ط®طµظ…:',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '- $discountVal ط¯ظٹظ†ط§ط±',
                        style: const TextStyle(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'ط§ظ„ط®طµظ…:',
                        style: TextStyle(color: AppTheme.errorColor),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                ],
                // ط§ظ„ظ…ط¬ظ…ظˆط¹ ط§ظ„ظƒظ„ظٹ
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$total ط¯ظٹظ†ط§ط±',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // ط­ظ‚ظ„ ط§ظ„ظ…ط¨ظ„ط؛ ط§ظ„ظ…ط¹ط·ظ‰
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'ط§ظ„ظ…ط¨ظ„ط؛ ط§ظ„ظ…ط¹ط·ظ‰',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payments),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                // ط§ظ„ط¨ط§ظ‚ظٹ (ط§ظ„ظپظƒط©)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: canConfirm
                        ? AppTheme.successColor.withValues(alpha: 0.12)
                        : AppTheme.errorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: canConfirm
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ط§ظ„ط¨ط§ظ‚ظٹ (ط§ظ„ظپظƒط©):',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        canConfirm ? '$change ط¯ظٹظ†ط§ط±' : 'ط§ظ„ظ…ط¨ظ„ط؛ ط؛ظٹط± ظƒط§ظپظچ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: canConfirm
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ط®ظٹط§ط± ط§ظ„ط·ط¨ط§ط¹ط©
                GestureDetector(
                  onTap: () => setDialogState(() => shouldPrint = !shouldPrint),
                  child: Row(
                    children: [
                      Checkbox(
                        value: shouldPrint,
                        onChanged: (v) =>
                            setDialogState(() => shouldPrint = v ?? true),
                        activeColor: AppTheme.primaryColor,
                      ),
                      const Icon(
                        Icons.receipt_long,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'ط·ط¨ط§ط¹ط© ظپط§طھظˆط±ط©',
                        style: TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                // ط®ظٹط§ط± ط§ظ„ط¹ظ…ظٹظ„
                GestureDetector(
                  onTap: () => setDialogState(() {
                    isCustomer = !isCustomer;
                    if (!isCustomer) customerName = '';
                  }),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isCustomer,
                        onChanged: (v) => setDialogState(() {
                          isCustomer = v ?? false;
                          if (!isCustomer) customerName = '';
                        }),
                        activeColor: AppTheme.primaryColor,
                      ),
                      const Icon(Icons.person, size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      const Text('ط¹ظ…ظٹظ„', style: TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
                if (isCustomer) ...[
                  const SizedBox(height: 8),
                  Autocomplete<Map<String, dynamic>>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) return const Iterable<Map<String, dynamic>>.empty();
                      final q = textEditingValue.text.toLowerCase();
                      return allCustomerData.where((c) {
                        final name = (c['name'] as String).toLowerCase();
                        final phone = (c['phone'] as String).toLowerCase();
                        return name.contains(q) || phone.contains(q);
                      });
                    },
                    displayStringForOption: (c) => '${c['name']}${(c['phone'] as String).isNotEmpty ? ' (${c['phone']})' : ''}',
                    onSelected: (c) {
                      customerName = c['name'] as String;
                      customerPhone = c['phone'] as String? ?? '';
                      customerCtrl.text = customerName;
                      setDialogState(() {});
                    },
                    fieldViewBuilder: (context, fieldController, focusNode, onSubmitted) {
                      return TextField(
                        controller: fieldController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'ط§ط³ظ… ط§ظ„ط¹ظ…ظٹظ„',
                          hintText: 'ط§ط¨ط­ط« ط¨ط§ظ„ط§ط³ظ… ط£ظˆ ط§ظ„ط¬ظˆط§ظ„...',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person, size: 18),
                          suffixIcon: customerName.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    fieldController.clear();
                                    customerName = '';
                                    customerPhone = '';
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) {
                          customerName = val;
                          customerPhone = '';
                          applyCustomerDiscount = false;
                          usePointsDiscount = false;
                          pointsDiscountAmount = 0;
                          discountVal = _discountValue;
                          total = subtotal - discountVal;
                          amountController.text = '$total';
                          setDialogState(() {});
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topRight,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (ctx, i) {
                                final c = options.elementAt(i);
                                final name = c['name'] as String;
                                final phone = c['phone'] as String;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person, size: 18),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: phone.isNotEmpty ? Text(phone, style: const TextStyle(fontSize: 12)) : null,
                                  onTap: () => onSelected(c),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (customerName.isNotEmpty && !allCustomerData.any((c) => c['name'] == customerName))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'ط³ظٹطھظ… ط¥ط¶ط§ظپط© "$customerName" ظƒط¹ظ…ظٹظ„ ط¬ط¯ظٹط¯',
                        style: TextStyle(color: AppTheme.warningColor, fontSize: 12),
                      ),
                    ),
                  if (customerName.isNotEmpty && allCustomerData.any((c) => c['name'] == customerName))
                    FutureBuilder<int>(
                      future: DatabaseHelper.instance.getCustomerDiscount(customerName),
                      builder: (ctx, snap) {
                        final disc = snap.data ?? 0;
                        if (disc <= 0) return const SizedBox.shrink();
                        if (!applyCustomerDiscount) customerDiscountPercent = disc;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                applyCustomerDiscount = !applyCustomerDiscount;
                                recalcTotal(subtotal, amountController);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: applyCustomerDiscount ? AppTheme.successColor : AppTheme.successColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.successColor),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  applyCustomerDiscount ? Icons.check_circle : Icons.discount,
                                  size: 14,
                                  color: applyCustomerDiscount ? Colors.white : AppTheme.successColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  applyCustomerDiscount ? 'ط®طµظ… $disc% ظ…ط·ط¨ظ‚ âœ“' : 'ط®طµظ… ط®ط§طµ: $disc%',
                                  style: TextStyle(
                                    color: applyCustomerDiscount ? Colors.white : AppTheme.successColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  if (customerName.isNotEmpty && allCustomerData.any((c) => c['name'] == customerName))
                    Builder(
                      builder: (ctx) {
                        final custData = allCustomerData.firstWhere((c) => c['name'] == customerName, orElse: () => {});
                        final pts = custData['loyalty_points'] as int? ?? 0;
                        if (pts <= 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                usePointsDiscount = !usePointsDiscount;
                                pointsDiscountAmount = usePointsDiscount ? pts * 100 : 0;
                                recalcTotal(subtotal, amountController);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: usePointsDiscount ? AppTheme.warningColor : AppTheme.warningColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.warningColor),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  usePointsDiscount ? Icons.check_circle : Icons.stars,
                                  size: 14,
                                  color: usePointsDiscount ? Colors.white : AppTheme.warningColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  usePointsDiscount ? 'طµط±ظپ $pts ظ†ظ‚ط·ط© âœ“' : 'ًں’° $pts ظ†ظ‚ط·ط© ظ…طھط§ط­ط©',
                                  style: TextStyle(
                                    color: usePointsDiscount ? Colors.white : AppTheme.warningColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ط¥ظ„ط؛ط§ط،'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: canConfirm
                      ? AppTheme.successColor
                      : AppTheme.neutralColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  'طھط£ظƒظٹط¯ ط§ظ„ط¯ظپط¹',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) {
      amountController.dispose();
      _keepFocus();
      return;
    }

    final int given = int.tryParse(amountController.text) ?? total;
    final int changeAmount = (given - total).clamp(0, 9999999);
    amountController.dispose();

    try {
      final cartSnapshot = List<Map<String, dynamic>>.from(_cart);
      final saleId = await DatabaseHelper.instance.completeSale(
        _cart,
        discountValue: discountVal,
        customerName: customerName,
      );

      // ط­ظپط¸ ط§ظ„ط¹ظ…ظٹظ„ ط§ظ„ط¬ط¯ظٹط¯ (insertCustomer ظٹطھط­ظ‚ظ‚ ظ…ظ† ط§ظ„طھظƒط±ط§ط± ط¨ظ†ظپط³ظ‡ ظˆظٹط±ط¬ط¹ -1)
      if (customerName.isNotEmpty && saleId > 0) {
        await DatabaseHelper.instance.insertCustomer(customerName, phone: customerPhone);
      }

      // طµط±ظپ ظ†ظ‚ط§ط· ط§ظ„ظˆظ„ط§ط،
      if (usePointsDiscount && customerName.isNotEmpty && saleId > 0 && pointsDiscountAmount > 0) {
        final settings = await DatabaseHelper.instance.getLoyaltySettings();
        final dpp = settings['discount_per_point'] as int;
        final pointsToSpend = pointsDiscountAmount ~/ dpp;
        if (pointsToSpend > 0) {
          await DatabaseHelper.instance.spendPointsForDiscount(customerName, pointsToSpend);
        }
      }

      // ظƒط³ط¨ ظ†ظ‚ط§ط· ط§ظ„ظˆظ„ط§ط،
      if (customerName.isNotEmpty && saleId > 0) {
        await DatabaseHelper.instance.earnLoyaltyPoints(customerName, total);
      }

      if (saleId > 0 && mounted) {
        _lastPrintCart = cartSnapshot;
        _lastPrintSubtotal = subtotal;
        _lastPrintDiscount = discountVal;
        _lastPrintTotal = total;
        _lastPrintGiven = given;
        _lastPrintChange = changeAmount;
        _lastPrintSaleId = saleId;
        setState(() {
          _cart.clear();
          _discountAmount = 0;
          _isDiscountPercent = false;
        });

        // ظ…ط³ط­ ط§ظ„ظ…ط³ظˆط¯ط© ط§ظ„طھظ„ظ‚ط§ط¦ظٹط© ط¨ط¹ط¯ ط§ظ„ط¨ظٹط¹ ط§ظ„ظ†ط§ط¬ط­
        if (_autoDraftOrderId != null) {
          await DatabaseHelper.instance.clearAutoDraft(_autoDraftOrderId!);
          _autoDraftOrderId = null;
        }

        // ط§ظ„ط·ط¨ط§ط¹ط© ظ…ظ†ظپطµظ„ط© ط¹ظ† ط§ظ„ط¨ظٹط¹ â€” ظپط´ظ„ظ‡ط§ ظ„ط§ ظٹط¹ظ†ظٹ ظپط´ظ„ ط§ظ„ط¨ظٹط¹
        var printFailed = false;
        if (shouldPrint) {
          try {
            await _printInvoice(cartSnapshot, subtotal, discountVal, total, given, changeAmount, saleId: saleId);
          } catch (e, st) {
            printFailed = true;
            await ErrorLogger.instance.logError(e, st, context: 'ط·ط¨ط§ط¹ط© ط¨ط¹ط¯ ط¨ظٹط¹ ظ†ط§ط¬ط­');
          }
        }

        if (mounted) {
          final remainingStock = cartSnapshot.map((i) {
            final p = i['product'] as ProductModel;
            final qty = i['quantity'] as int;
            return '${p.name} (${p.stock - qty})';
          }).join('  |  ');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('طھظ… ط§ظ„ط¨ظٹط¹ ط¨ظ†ط¬ط§ط­ âœ“${changeAmount > 0 ? '  |  ط§ظ„ط¨ط§ظ‚ظٹ: $changeAmount ط¯' : ''}'),
                  const SizedBox(height: 4),
                  Text('ط§ظ„ظ…طھط¨ظ‚ظٹ: $remainingStock', style: const TextStyle(fontSize: 12)),
                  if (printFailed) ...[
                    const SizedBox(height: 4),
                    const Text('âڑ ï¸ڈ ظپط´ظ„طھ ط§ظ„ط·ط¨ط§ط¹ط© â€” ط§ظ„ط¨ظٹط§ظ†ط§طھ ظ…ط­ظپظˆط¸ط©طŒ ط£ط¹ط¯ ط§ظ„ط·ط¨ط§ط¹ط© ظ…ظ† ط§ظ„ط²ط± ط§ظ„ط¹ظ„ظˆظٹ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
              backgroundColor: printFailed ? AppTheme.warningColor : AppTheme.successColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ط­ط¯ط« ط®ط·ط£ ط£ط«ظ†ط§ط، ط¥طھظ…ط§ظ… ط§ظ„ط¨ظٹط¹!'), backgroundColor: AppTheme.errorColor),
        );
      }
    } catch (e, st) {
      await ErrorLogger.instance.logError(e, st, context: 'ط¥طھظ…ط§ظ… ط§ظ„ط¨ظٹط¹ - _showPaymentDialog');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ط®ط·ط£ ط­ط§ط¯ط«: $e'), backgroundColor: AppTheme.errorColor, duration: const Duration(seconds: 5)),
        );
      }
    }
    _keepFocus();
  }

  // ط·ط¨ط§ط¹ط© ظپط§طھظˆط±ط© ط§ظ„ط¨ظٹط¹ â€” ظˆطµظ„ ط¨طھطµظ…ظٹظ… ط¬ط¯ظٹط¯ ظ¤ ط£ط¹ظ…ط¯ط©
  Future<void> _printInvoice(
    List<Map<String, dynamic>> cart,
    int subtotal,
    int discountValue,
    int finalTotal,
    int given,
    int change,
    {int? saleId, String? customerName}
  ) async {
    final settings = await DatabaseHelper.instance.getAllSettings();
    final storeName = settings['store_name'] ?? 'ط£ط­ظ„ظ‰ ط§ظ„ط­ظ„ظˆظٹظ†';
    final storePhone = settings['store_phone'] ?? '';
    final currency = settings['currency'] ?? 'ط¯ظٹظ†ط§ط±';
    final footer = settings['receipt_footer'] ?? 'ط´ظƒط±ط§ظ‹ ظ„ط²ظٹط§ط±طھظƒظ…';
    final qrSvgCache = settings['qr_svg_cache'] ?? '';
    final titleFs =
        double.tryParse(settings['receipt_title_font_size'] ?? '14') ?? 14.0;
    final bodyFs =
        double.tryParse(settings['receipt_body_font_size'] ?? '9') ?? 9.0;
    final paperW =
        double.tryParse(settings['receipt_paper_width_mm'] ?? '78') ?? 78.0;
    final marginTop =
        double.tryParse(
          settings['receipt_margin_top_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final marginBottom =
        double.tryParse(
          settings['receipt_margin_bottom_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final marginLeft =
        double.tryParse(
          settings['receipt_margin_left_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final marginRight =
        double.tryParse(
          settings['receipt_margin_right_mm'] ??
              settings['receipt_margin_mm'] ??
              '5',
        ) ??
        5.0;
    final savedPrinterUrl =
        settings['receipt_printer_url'] ??
        settings['default_printer_url'] ??
        '';
    final savedPrinterName =
        settings['receipt_printer_name'] ??
        settings['default_printer_name'] ??
        '';

    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    final aroFont = pw.Font.ttf(fontData);

    final now = DateTime.now();
    final dtStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // ط¹ظƒط³ طھط±طھظٹط¨ ط§ظ„ظ…ظˆط§ط¯ (ط§ظ„ط£ط­ط¯ط« ط¥ط¶ط§ظپط©ظ‹ ظٹط¸ظ‡ط± ط£ط¹ظ„ظ‰)
    final reversed = cart.reversed.toList();
    final itemCount = cart.fold<int>(0, (s, i) => s + (i['quantity'] as int));

    // ط­ط³ط§ط¨ ط§ط±طھظپط§ط¹ ط§ظ„ظˆط±ظ‚ط© طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ط¨ظ†ط§ط،ظ‹ ط¹ظ„ظ‰ ط¹ط¯ط¯ ط§ظ„ظ…ظˆط§ط¯
    final rowH = bodyFs * 1.5 + 5.0;
    final phoneH = storePhone.isNotEmpty ? 8.0 : 0.0;
    final discountH = discountValue > 0 ? 16.0 : 0.0;
    final changeH = given > finalTotal ? 16.0 : 0.0;
    final qrH = qrSvgCache.isNotEmpty ? 24.0 : 0.0;
    final pageH =
        52.0 +
        phoneH +
        reversed.length * (rowH + 3.0) +
        discountH +
        changeH +
        qrH +
        46.0;

    final pageFormat = PdfPageFormat(
      paperW * PdfPageFormat.mm,
      pageH * PdfPageFormat.mm,
      marginTop: marginTop * PdfPageFormat.mm,
      marginBottom: marginBottom * PdfPageFormat.mm,
      marginLeft: marginLeft * PdfPageFormat.mm,
      marginRight: marginRight * PdfPageFormat.mm,
    );

    pw.TextStyle body() => pw.TextStyle(font: aroFont, fontSize: bodyFs);
    pw.TextStyle bodyBold() => pw.TextStyle(
      font: aroFont,
      fontSize: bodyFs,
      fontWeight: pw.FontWeight.bold,
    );
    pw.TextStyle titleSt() => pw.TextStyle(
      font: aroFont,
      fontSize: titleFs,
      fontWeight: pw.FontWeight.bold,
    );
    pw.TextStyle subTitleSt() =>
        pw.TextStyle(font: aroFont, fontSize: titleFs - 2);

    final solidDiv = pw.Divider(thickness: 0.5, color: PdfColors.black);
    // ظپط§طµظ„ ظ…ظ†ظ‚ط· ظٹظ…طھط¯ ط¹ظ„ظ‰ ظƒط§ظ…ظ„ ط¹ط±ط¶ ط§ظ„ظپط§طھظˆط±ط©
    final dottedDiv = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: List.generate(
          80,
          (i) => pw.Expanded(
            child: pw.Container(
              height: 1,
              color: i.isEven ? PdfColors.black : PdfColors.white,
            ),
          ),
        ),
      ),
    );
    // ظپط§طµظ„ ط±ط£ط³ظٹ ط±ظپظٹط¹ ط¨ظٹظ† ط§ظ„ط£ط¹ظ…ط¯ط©
    // final vSep = pw.Container(width: 0.4, color: PdfColors.grey500);

    // ط¨ظ†ط§ط، ط¨ظ†ظˆط¯ ط§ظ„ظپط§طھظˆط±ط©
    final List<pw.Widget> itemWidgets = [];
    for (var i = 0; i < reversed.length; i++) {
      final item = reversed[i];
      final product = item['product'] as ProductModel;
      final qty = item['quantity'] as int;
      final itemPrice = (item['custom_price'] as int?) ?? product.price;
      final itemDiscount = (item['item_discount'] as int?) ?? 0;
      final effectivePrice = itemPrice - itemDiscount;
      final rowTotal = effectivePrice * qty;
      // final extras = [if (product.color.isNotEmpty) product.color, if (product.size.isNotEmpty) product.size].join(' ');
      itemWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: 3,
                child: pw.Text('$rowTotal', style: bodyBold(), textAlign: pw.TextAlign.center),
              ),
              pw.Expanded(
                flex: 3,
                child: pw.Text('$itemPrice', style: body(), textAlign: pw.TextAlign.center),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text('x$qty', style: body(), textAlign: pw.TextAlign.center),
              ),
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  children: [
                    pw.Text(
                      product.name,
                      style: body(),
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.center,
                      overflow: pw.TextOverflow.clip,
                    ),
                    // if (extras.isNotEmpty)
                    //   pw.Text(
                    //     extras,
                    //     style: pw.TextStyle(font: aroFont, fontSize: bodyFs - 1, color: PdfColors.grey600),
                    //     textDirection: pw.TextDirection.rtl,
                    //     textAlign: pw.TextAlign.center,
                    //   ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      if (i < reversed.length - 1) itemWidgets.add(dottedDiv);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(right: 4, left: 4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ط§ط³ظ… ط§ظ„ظ…ط­ظ„
              pw.Text(
                storeName,
                style: titleSt(),
                textDirection: pw.TextDirection.rtl,
              ),
              if (storePhone.isNotEmpty)
                pw.Text(
                  storePhone,
                  style: subTitleSt(),
                  textDirection: pw.TextDirection.rtl,
                ),
              pw.SizedBox(height: 3),
              solidDiv,
              // ط§ظ„طھط§ط±ظٹط® ظˆط§ظ„ظˆظ‚طھ
              pw.Text(dtStr, style: body()),
              // ط±ظ‚ظ… ط§ظ„ظˆطµظ„
              if (saleId != null) ...[
                pw.SizedBox(height: 2),
                pw.Text('ط±ظ‚ظ… ط§ظ„ظˆطµظ„: R${saleId.toString().padLeft(6, '0')}', style: bodyBold(), textDirection: pw.TextDirection.rtl),
              ],
              // ط§ط³ظ… ط§ظ„ط¹ظ…ظٹظ„ (ط¥ط°ط§ ظƒط§ظ† ط¨ظٹط¹ ط¨ط§ظ„ط¯ظٹظ†)
              if (customerName != null && customerName.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.pink50,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text('ط§ظ„ط¹ظ…ظٹظ„: $customerName', style: bodyBold(), textDirection: pw.TextDirection.rtl),
                ),
              ],
              solidDiv,
              pw.SizedBox(height: 2),
              // ط±ط£ط³ ط§ظ„ط¬ط¯ظˆظ„ (طھط±طھظٹط¨ RTL: ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ | ط§ظ„ط³ط¹ط± | ط§ظ„ط¹ط¯ط¯ | ط§ط³ظ… ط§ظ„ظ…ط§ط¯ط©)
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ',
                      style: bodyBold(),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'ط§ظ„ط³ط¹ط±',
                      style: bodyBold(),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'ط§ظ„ط¹ط¯ط¯',
                      style: bodyBold(),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),

                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      'ط§ط³ظ… ط§ظ„ظ…ط§ط¯ط©',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(
                height: 2,
                child: pw.Divider(thickness: 0.8, color: PdfColors.black),
              ),
              // ط¨ظ†ظˆط¯ ط§ظ„ظپط§طھظˆط±ط©
              ...itemWidgets,
              solidDiv,
              pw.SizedBox(height: 2),
              // ط§ظ„ط®طµظ… (ط¥ط°ط§ ظƒط§ظ† ظ‡ظ†ط§ظƒ ط®طµظ…)
              if (discountValue > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('$subtotal $currency', style: body()),
                    pw.Text(
                      'ط§ظ„ظ…ط¬ظ…ظˆط¹:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '- $discountValue $currency',
                      style: body(),
                    ),
                    pw.Text(
                      'ط§ظ„ط®طµظ…:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.Divider(thickness: 0.5),
              ],
              // ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ظ†ظ‡ط§ط¦ظٹ
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('$finalTotal $currency', style: titleSt()),
                  pw.Text(
                    '${discountValue > 0 ? 'ط§ظ„طµط§ظپظٹ' : 'ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ'} ($itemCount ظ‚ط·ط¹ط©):',
                    style: subTitleSt(),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
              ),
              // ط§ظ„ظ…ط¯ظپظˆط¹ ظˆط§ظ„ط¨ط§ظ‚ظٹ
              if (given > finalTotal) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('$given $currency', style: body()),
                    pw.Text(
                      'ط§ظ„ظ…ط¯ظپظˆط¹:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '$change $currency',
                      style: pw.TextStyle(
                        font: aroFont,
                        fontSize: bodyFs + 1,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'ط§ظ„ط¨ط§ظ‚ظٹ:',
                      style: bodyBold(),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ],
              dottedDiv,
              pw.SizedBox(height: 4),
              if (qrSvgCache.isNotEmpty) ...[  
                pw.Center(
                  child: pw.SvgImage(svg: qrSvgCache, width: 60, height: 60),
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Text(
                footer,
                style: body(),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    if (savedPrinterUrl.isNotEmpty) {
      try {
        final ok = await Printing.directPrintPdf(
          printer: Printer(url: savedPrinterUrl, name: savedPrinterName),
          onLayout: (_) async => await Isolate.run(() => doc.save()),
        );
        if (ok) return;
    } catch (e) {
      debugPrint('POS _loadAllProducts error: $e');
    }
    }
    await Printing.layoutPdf(onLayout: (_) async {
      return await Isolate.run(() => doc.save());
    });
  }

  // ط¹ط±ط¶ ط§ظ„ظ…ظ†طھط¬ط§طھ ط°ط§طھ ط§ظ„ظ…ط®ط²ظˆظ† ط§ظ„ظ…ظ†ط®ظپط¶
  void _showLowStockDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor),
            const SizedBox(width: 8),
            Text(
              'ط§ظ„ظ…ط®ط²ظˆظ† ط§ظ„ظ…ظ†ط®ظپط¶ (${_lowStockProducts.length})',
              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _lowStockProducts.isEmpty
              ? const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ظ…ظ†طھط¬ط§طھ ط¨ظ…ط®ط²ظˆظ† ظ…ظ†ط®ظپط¶ âœ“', style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold)))
              : ListView.separated(
                  itemCount: _lowStockProducts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final p = _lowStockProducts[index];
                    final isZero = p.stock <= 0;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isZero ? Icons.error : Icons.warning,
                        color: isZero ? AppTheme.errorColor : AppTheme.warningColor,
                      ),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${p.category} ${p.color.isNotEmpty ? '- ${p.color}' : ''} ${p.size.isNotEmpty ? '- ${p.size}' : ''}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isZero ? AppTheme.errorColor : AppTheme.warningColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${p.stock}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ط¥ط؛ظ„ط§ظ‚'),
          ),
        ],
      ),
    );
  }

  // ط¹ط±ط¶ ط§ظ„ظپظˆط§طھظٹط± ط§ظ„ظ…ط¹ظ„ظ‚ط© ظˆط§ط³طھط¦ظ†ط§ظپظ‡ط§
  Future<void> _showSuspendedOrders() async {
    final orders = await DatabaseHelper.instance.getSuspendedOrders();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: const Text(
                'ط§ظ„ظپظˆط§طھظٹط± ط§ظ„ظ…ط¹ظ„ظ‚ط©',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            Expanded(
              child: orders.isEmpty
                  ? const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ظپظˆط§طھظٹط± ظ…ط¹ظ„ظ‚ط©'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: orders.length,
                      itemBuilder: (_, i) {
                        final order = orders[i];
                        final orderId = order['id'] as int;
                        final note = order['note'] as String? ?? 'ط¨ط¯ظˆظ† ظ…ظ„ط§ط­ط¸ط©';
                        final createdAt = (order['created_at'] as String)
                            .substring(0, 16)
                            .replaceAll('T', '  ');
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: const Icon(
                              Icons.pause_circle,
                              color: AppTheme.warningColor,
                              size: 32,
                            ),
                            title: Text(
                              note,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(createdAt),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () async {
                                    final result = await DatabaseHelper
                                        .instance
                                        .getSuspendedOrderCartWithWarning(orderId);
                                    final suspendedCart = result['cart'] as List<Map<String, dynamic>>;
                                    final missingCount = result['missing'] as int;
                                    final discountInfo = await DatabaseHelper
                                        .instance
                                        .getSuspendedOrderDiscount(orderId);

                                    // â”€â”€â”€ ط§ظ„ط³ظ„ط© ط£ظˆظ„ط§ظ‹ ط«ظ… ط§ظ„ط­ط°ظپ â”€â”€â”€
                                    // ظ„ظˆ ط§ظ†ظ‚ط·ط¹ ط§ظ„طھط·ط¨ظٹظ‚ ط¨ط¹ط¯ ط§ظ„ط¥ط¶ط§ظپط© ظˆظ‚ط¨ظ„ ط§ظ„ط­ط°ظپ:
                                    // ط§ظ„ظپط§طھظˆط±ط© طھط¨ظ‚ظ‰ ظ…ط¹ظ„ظ‚ط© (طھظƒط±ط§ط± ظ…ط­طھظ…ظ„ ط£ظپط¶ظ„ ظ…ظ† ط¶ظٹط§ط¹)
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    setState(() {
                                      _cart.addAll(suspendedCart);
                                      _discountAmount =
                                          discountInfo['discount_amount'] ?? 0;
                                      _isDiscountPercent =
                                          (discountInfo['is_discount_percent'] ??
                                              0) ==
                                          1;
                                    });

                                    final deleted = await DatabaseHelper.instance
                                        .deleteSuspendedOrder(orderId);
                                    if (!deleted) {
                                      await ErrorLogger.instance.warning(
                                        'ط§ط³طھط¤ظ†ظپطھ ظپط§طھظˆط±ط© ظ„ظƒظ† ظپط´ظ„ ط­ط°ظپظ‡ط§ ط§ظ„ظ…ط¹ظ„ظ‚ â€” ظ‚ط¯ طھطھظƒط±ط±',
                                        data: {'order_id': orderId},
                                      );
                                    }
                                    if (missingCount > 0 && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('طھظ†ط¨ظٹظ‡: $missingCount ظ…ظ†طھط¬ ظ…ط­ط°ظˆظپ طھظ… طھط¬ط§ظ‡ظ„ظ‡ ظ…ظ† ط§ظ„ظپط§طھظˆط±ط© ط§ظ„ظ…ط¹ظ„ظ‚ط©'),
                                          backgroundColor: AppTheme.warningColor,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                    _checkSuspendedOrders();
                                    _keepFocus();
                                  },
                                  child: const Text(
                                    'ط§ط³طھط¦ظ†ط§ظپ',
                                    style: TextStyle(
                                      color: AppTheme.successColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: AppTheme.errorColor,
                                  ),
                                  onPressed: () async {
                                    await DatabaseHelper.instance
                                        .deleteSuspendedOrder(orderId);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _checkSuspendedOrders();
                                    _showSuspendedOrders();
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    _checkSuspendedOrders();
  }

  // ط³ظƒط§ظ†ط± ط§ظ„ظƒط§ظ…ظٹط±ط§ (ط¹ظ„ظ‰ ط§ظ„ظ…ظˆط¨ط§ظٹظ„ ظپظ‚ط·)
  Future<void> _openCameraScanner() async {
    bool scanned = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('ط§ظ…ط³ط­ ط§ظ„ط¨ط§ط±ظƒظˆط¯'),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: MobileScanner(
            onDetect: (capture) {
              if (scanned) return;
              if (capture.barcodes.isNotEmpty) {
                final code = capture.barcodes.first.rawValue;
                if (code != null) {
                  scanned = true;
                  Navigator.pop(ctx);
                  _onBarcodeScanned(code);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€ طھط­ظ…ظٹظ„ ط¬ظ…ظٹط¹ ط§ظ„ظ…ظ†طھط¬ط§طھ â”€â”€â”€
  Future<void> _loadAllProducts() async {
    try {
      final products = await DatabaseHelper.instance.getAllProducts();
      final thresholdStr = await DatabaseHelper.instance.getSetting(
        'low_stock_threshold',
        defaultValue: '5',
      );
      final threshold = int.tryParse(thresholdStr) ?? 5;
      final lowStock = products.where((p) => p.stock <= threshold && p.stock >= 0).toList();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _lowStockProducts = lowStock;
        });
      }
    } catch (_) {}
  }

  // â”€â”€â”€ ط­ظˆط§ط± ط§ظ„ط®طµظ… â”€â”€â”€
  Future<void> _showDiscountDialog() async {
    final ctrl = TextEditingController(
      text: _discountAmount > 0 ? '$_discountAmount' : '',
    );
    bool isPercent = _isDiscountPercent;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('ط®طµظ… ط¹ظ„ظ‰ ط§ظ„ظپط§طھظˆط±ط©'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('ظ…ط¨ظ„ط؛ ط«ط§ط¨طھ')),
                  ButtonSegment(value: true, label: Text('ظ†ط³ط¨ط© ظ…ط¦ظˆظٹط© %')),
                ],
                selected: {isPercent},
                onSelectionChanged: (s) => setS(() => isPercent = s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: isPercent ? 'ظ†ط³ط¨ط© ط§ظ„ط®طµظ…' : 'ظ…ط¨ظ„ط؛ ط§ظ„ط®طµظ…',
                  border: const OutlineInputBorder(),
                  suffixText: isPercent ? '%' : 'ط¯ظٹظ†ط§ط±',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
              onPressed: () {
                setState(() {
                  _discountAmount = 0;
                  _isDiscountPercent = false;
                });
                Navigator.pop(ctx);
              },
              child: const Text('ط¥ط²ط§ظ„ط© ط§ظ„ط®طµظ…'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ط¥ظ„ط؛ط§ط،'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final v = int.tryParse(ctrl.text) ?? 0;
                setState(() {
                  _discountAmount = v.clamp(0, isPercent ? 100 : _subtotal);
                  _isDiscountPercent = isPercent;
                });
                Navigator.pop(ctx);
              },
              child: const Text('طھط·ط¨ظٹظ‚'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    _keepFocus();
  }


  // â”€â”€â”€ ط­ط³ط§ط¨ ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹط§طھ â”€â”€â”€
  int get _subtotal => _cart.fold(0, (s, i) {
    final p = i['product'] as ProductModel;
    final itemPrice = (i['custom_price'] as int?) ?? p.price;
    final itemDiscount = (i['item_discount'] as int?) ?? 0;
    return s + ((itemPrice - itemDiscount) * (i['quantity'] as int));
  });

  int get _discountValue {
    if (_discountAmount <= 0) return 0;
    if (_isDiscountPercent) return _subtotal * _discountAmount ~/ 100;
    return _discountAmount.clamp(0, _subtotal);
  }

  int get _finalTotal => _subtotal - _discountValue;

  @override
  Widget build(BuildContext context) {
    final categories = <String>['ط§ظ„ظƒظ„'];
    for (final p in _allProducts) {
      if (!categories.contains(p.category)) categories.add(p.category);
    }
    final filteredProducts = _filteredPosProducts;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ظ†ظ‚ط·ط© ط§ظ„ط¨ظٹط¹ (ط§ظ„ظƒط§ط´ظٹط±)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_lastPrintCart != null)
            IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: () async {
                try {
                  await _printInvoice(
                    _lastPrintCart!, _lastPrintSubtotal, _lastPrintDiscount,
                    _lastPrintTotal, _lastPrintGiven, _lastPrintChange,
                    saleId: _lastPrintSaleId, customerName: _lastPrintCustomerName,
                  );
                } catch (e, st) {
                  await ErrorLogger.instance.logError(e, st, context: 'ط¥ط¹ط§ط¯ط© ط·ط¨ط§ط¹ط© ط¢ط®ط± ظپط§طھظˆط±ط©');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('ظپط´ظ„طھ ط§ظ„ط·ط¨ط§ط¹ط© â€” طھط£ظƒط¯ ظ…ظ† ط§ظ„ط·ط§ط¨ط¹ط©: $e'),
                        backgroundColor: AppTheme.errorColor,
                      ),
                    );
                  }
                }
              },
              tooltip: 'ط·ط¨ط§ط¹ط© ط¢ط®ط± ظپط§طھظˆط±ط©',
            ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.pause_circle_outline),
                if (_hasSuspendedOrders)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      width: 10, height: 10,
                      decoration: const BoxDecoration(color: AppTheme.errorColor, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            onPressed: _showSuspendedOrders,
            tooltip: 'ط§ظ„ظپظˆط§طھظٹط± ط§ظ„ظ…ط¹ظ„ظ‚ط©',
          ),
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.inventory_2_outlined),
                if (_lowStockProducts.isNotEmpty)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: const BoxDecoration(color: AppTheme.warningColor, shape: BoxShape.circle),
                      child: Text(
                        '${_lowStockProducts.length}',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showLowStockDialog,
            tooltip: 'ط§ظ„ظ…ط®ط²ظˆظ† ط§ظ„ظ…ظ†ط®ظپط¶',
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesPage(showProfit: false)),
              );
            },
            tooltip: 'ط§ظ„ظپظˆط§طھظٹط± ط§ظ„ظ‚ط¯ظٹظ…ط©',
          ),
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: _openCameraScanner,
              tooltip: 'ظ…ط³ط­ ط¨ط§ظ„ظƒط§ظ…ظٹط±ط§',
            ),
        ],
      ),
      body: Row(
          children: [
            // â”€â”€ ط§ظ„ط¬ط²ط، ط§ظ„ط£ظٹط³ط±: ط§ظ„ط³ظ„ط© + ط§ظ„ط¯ظپط¹ â”€â”€
            Expanded(
              flex: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _keepFocus,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(color: AppTheme.primaryColor.withOpacity(0.2), width: 1),
                    ),
                  ),
                  child: Column(
                    children: [
                    // ط­ظ‚ظ„ ط§ظ„ط¨ط§ط±ظƒظˆط¯
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        controller: _barcodeController,
                        focusNode: _barcodeFocusNode,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'ط§ظ…ط³ط­ ط§ظ„ط¨ط§ط±ظƒظˆط¯...',
                          prefixIcon: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: AppTheme.surfaceColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (val) => setState(() => _posSearchQuery = val),
                        onSubmitted: _onBarcodeScanned,
                      ),
                    ),
                    // ط¹ظ†ظˆط§ظ† ط§ظ„ط³ظ„ط©
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_cart, size: 18, color: AppTheme.primaryColor),
                          const SizedBox(width: 6),
                          Text(
                            'ط§ظ„ظپط§طھظˆط±ط© (${_cart.length} طµظ†ظپ)',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                          ),
                          const Spacer(),
                          if (_cart.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _cart.clear();
                                  _discountAmount = 0;
                                  _isDiscountPercent = false;
                                });
                                // ظ…ط³ط­ ط§ظ„ظ…ط³ظˆط¯ط© ط§ظ„طھظ„ظ‚ط§ط¦ظٹط©
                                if (_autoDraftOrderId != null) {
                                  DatabaseHelper.instance.clearAutoDraft(_autoDraftOrderId!);
                                  _autoDraftOrderId = null;
                                }
                              },
                              child: const Text('ظ…ط³ط­ ط§ظ„ظƒظ„', style: TextStyle(color: AppTheme.errorColor, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    // ظ‚ط§ط¦ظ…ط© ط§ظ„ظ…ظ†طھط¬ط§طھ ط¨ط§ظ„ط³ظ„ط©
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(
                              child: Text(
                                'ط§ظ„ظپط§طھظˆط±ط© ظپط§ط±ط؛ط©',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              itemCount: _cart.length,
                              itemBuilder: (context, index) {
                                final item = _cart[index];
                                final product = item['product'] as ProductModel;
                                final qty = item['quantity'] as int;
                                final itemPrice = (item['custom_price'] as int?) ?? product.price;
                                final itemDiscount = (item['item_discount'] as int?) ?? 0;
                                final effectivePrice = itemPrice - itemDiscount;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    product.name,
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (product.color.isNotEmpty || product.size.isNotEmpty)
                                                    Row(
                                                      children: [
                                                        if (product.color.isNotEmpty) ...[
                                                          Icon(Icons.circle, size: 8, color: _posParseColor(product.color)),
                                                          const SizedBox(width: 3),
                                                          Text(product.color, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                                                        ],
                                                        if (product.color.isNotEmpty && product.size.isNotEmpty)
                                                          const Text(' | ', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                                                        if (product.size.isNotEmpty)
                                                          Text(product.size, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => _editItemPrice(index),
                                              child: Text(
                                                '$itemPrice ط¯.ط¹',
                                                style: TextStyle(
                                                  color: (item['custom_price'] != null) ? AppTheme.warningColor : AppTheme.primaryColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  decoration: itemDiscount > 0 ? TextDecoration.lineThrough : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            _qtyBtn(Icons.remove_circle, AppTheme.warningColor, () => _decreaseQty(index)),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6),
                                              child: Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
                                            ),
                                            _qtyBtn(Icons.add_circle, AppTheme.successColor, () => _increaseQty(index)),
                                            const Spacer(),
                                            if (itemDiscount > 0)
                                              GestureDetector(
                                                onTap: () => _editItemDiscount(index),
                                                child: Text(
                                                  '$effectivePrice ط¯.ط¹',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.successColor),
                                                ),
                                              ),
                                            if (itemDiscount > 0) const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () => _editItemDiscount(index),
                                              child: Icon(Icons.discount, size: 16, color: itemDiscount > 0 ? AppTheme.errorColor : AppTheme.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // ظ„ظˆط­ط© ط§ظ„ط¯ظپط¹ ط§ظ„ط³ظپظ„ظٹط©
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -3)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_discountValue > 0) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$_discountValue ط¯.ط¹ ط®طµظ…', style: const TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('ط§ظ„طµط§ظپظٹ: $_finalTotal ط¯.ط¹', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryColor)),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (_discountValue == 0)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('ط§ظ„ط¥ط¬ظ…ط§ظ„ظٹ:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                Text(
                                  '$_finalTotal ط¯.ط¹',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _posActionBtn(Icons.discount_outlined, _discountValue > 0 ? AppTheme.errorColor : AppTheme.textSecondary, _showDiscountDialog),
                              const SizedBox(width: 4),
                              _posActionBtn(Icons.pause_circle_filled, AppTheme.warningColor, _suspendOrder),
                              const SizedBox(width: 4),
                              _posActionBtn(Icons.person_add_outlined, AppTheme.primaryColor, _showDebtSaleDialog),
                              const SizedBox(width: 4),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.successColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  icon: const Icon(Icons.point_of_sale, size: 18),
                                  label: const Text('ط¯ظپط¹', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  onPressed: _cart.isEmpty ? null : _showPaymentDialog,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
            // â”€â”€ ط§ظ„ط¬ط²ط، ط§ظ„ط£ظٹظ…ظ†: ط§ظ„ظ…ظ†طھط¬ط§طھ ط¹ظ„ظ‰ ط´ظƒظ„ ظƒط±ظˆطھ â”€â”€
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // ظپظ„طھط± ط§ظ„ط£ظ‚ط³ط§ظ…
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: AppTheme.surfaceColor,
                    child: SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final cat = categories[i];
                          final selected = (i == 0 && _posSelectedCategory == null) || _posSelectedCategory == cat;
                          return ChoiceChip(
                            label: Text(cat, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppTheme.textPrimary)),
                            selected: selected,
                            selectedColor: AppTheme.primaryColor,
                            backgroundColor: Colors.white,
                            onSelected: (_) {
                              setState(() {
                                _posSelectedCategory = (i == 0) ? null : cat;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  // ط´ط¨ظƒط© ط§ظ„ظ…ظ†طھط¬ط§طھ
                  Expanded(
                    child: filteredProducts.isEmpty
                        ? const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ظ…ظ†طھط¬ط§طھ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final crossCount = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 600 ? 3 : 2);
                              return GridView.builder(
                                padding: const EdgeInsets.all(10),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossCount,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 0.85,
                                ),
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final p = filteredProducts[index];
                                  final inCart = _cart
                                      .where((i) => (i['product'] as ProductModel).id == p.id)
                                      .fold<int>(0, (s, i) => s + (i['quantity'] as int));
                                  return GestureDetector(
                                    onTap: () => _addProductToCart(p),
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 56, height: 56,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                p.name.isNotEmpty ? p.name[0] : '?',
                                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Text(
                                              p.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (p.color.isNotEmpty || p.size.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                [if (p.color.isNotEmpty) p.color, if (p.size.isNotEmpty) p.size].join(' â€” '),
                                                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${p.price} ط¯.ط¹',
                                            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'ظ…طھظˆظپط±: ${p.stock}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: p.stock <= 0 ? AppTheme.errorColor : AppTheme.textSecondary,
                                            ),
                                          ),
                                          if (inCart > 0)
                                            Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColor,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'ط¨ط§ظ„ط³ظ„ط©: $inCart',
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

Color _posParseColor(String name) {
  const map = {
    'ط£ط­ظ…ط±': Colors.red, 'ط§ط®ط¶ط±': Colors.green,
    'ط£ط²ط±ظ‚': Colors.blue, 'ط§ط³ظˆط¯': Colors.black, 'ط£ط¨ظٹط¶': Colors.white,
    'ط§طµظپط±': Colors.yellow, 'ط¨ط±طھظ‚ط§ظ„ظٹ': Colors.orange, 'ط¨ظ†ظپط³ط¬ظٹ': Colors.purple,
    'ظˆط±ط¯ظٹ': Colors.pink, 'ط¨ظ†ظٹ': Colors.brown, 'ط±ظ…ط§ط¯ظٹ': Colors.grey,
    'ط³ظ…ط§ظˆظٹ': Colors.lightBlue, 'ظ†ط¹ظ†ط§ط¹ظٹ': Colors.teal,
    'ط°ظ‡ط¨ظٹ': Color(0xFFFFD700), 'ظپط¶ظٹ': Color(0xFFC0C0C0),
  };
  final lower = name.toLowerCase().trim();
  for (final entry in map.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return AppTheme.textSecondary;
}

Widget _qtyBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _posActionBtn(IconData icon, Color c, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: c, size: 22),
      ),
    );
  }
}

// ظ…ط³طھظ…ط¹ ط¯ظˆط±ط© ط­ظٹط§ط© ط§ظ„طھط·ط¨ظٹظ‚ â€” ظٹط­ظپط¸ ط§ظ„ط³ظ„ط© طھظ„ظ‚ط§ط¦ظٹط§ظ‹ ط¹ظ†ط¯ ط§ظ„ط®ط±ظˆط¬
class _PosLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ط¹ظ†ط¯ ط§ظ„ط®ط±ظˆط¬ ظ„ظ„ط®ظ„ظپظٹط© ط£ظˆ ط¥ظٹظ‚ط§ظپ ط§ظ„طھط·ط¨ظٹظ‚طŒ ظ†ط­ظپط¸ ط§ظ„ط³ظ„ط©
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _PosPageState.instance?._saveAutoDraft();
    }
  }
}

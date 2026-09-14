import 'dart:convert';
import 'package:cashier_system/core/database/database_helper.dart';

/// نظام تفعيل مبني على الوقت — التفعيلة تحدد تاريخ انتهاء الصلاحية
/// التشفير: base64(secret + timestamp)
class ActivationService {
  ActivationService._();
  static final ActivationService instance = ActivationService._();

  static const _secret = 'LAMSA激活2024';

  /// توليد تفعيلة من تاريخ انتهاء الصلاحية
  String generateCode(DateTime expiryDate) {
    final ts = expiryDate.millisecondsSinceEpoch;
    final raw = '$_secret|$ts';
    return base64Encode(utf8.encode(raw));
  }

  /// التحقق من صحة التفعيلة وجلب تاريخ الانتهاء
  /// returns: (isValid, expiryDate)
  (bool, DateTime?) validateCode(String code) {
    try {
      final decoded = utf8.decode(base64Decode(code));
      final parts = decoded.split('|');
      if (parts.length != 2) return (false, null);
      if (parts[0] != _secret) return (false, null);
      final ts = int.tryParse(parts[1]);
      if (ts == null) return (false, null);
      final expiry = DateTime.fromMillisecondsSinceEpoch(ts);
      return (true, expiry);
    } catch (_) {
      return (false, null);
    }
  }

  /// هل التطبيق فعّل حالياً؟
  Future<bool> isActivated() async {
    final code = await DatabaseHelper.instance.getSetting('activation_code');
    if (code.isEmpty) return false;
    final result = validateCode(code);
    if (!result.$1) return false;
    return DateTime.now().isBefore(result.$2!);
  }

  /// تاريخ انتهاء الصلاحية
  Future<DateTime?> getExpiryDate() async {
    final code = await DatabaseHelper.instance.getSetting('activation_code');
    if (code.isEmpty) return null;
    final result = validateCode(code);
    return result.$2;
  }

  /// حفظ التفعيلة
  Future<void> saveCode(String code) async {
    await DatabaseHelper.instance.setSetting('activation_code', code);
  }

  /// حذف التفعيلة
  Future<void> clearCode() async {
    await DatabaseHelper.instance.setSetting('activation_code', '');
  }
}

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cashier_system/core/database/database_helper.dart';

/// قفل صفحة المطور — يعتمد على كلمة سر + الوقت الحالي (24 ساعة)
/// التنسيق: كلمة_السر + YYYYMMDDHHmm
/// مثال: secret123@202609140314
class DevLockService {
  DevLockService._();
  static final DevLockService instance = DevLockService._();

  /// حفظ كلمة السر (كـ hash)
  Future<void> setSecret(String secret) async {
    final hash = _hash(secret);
    await DatabaseHelper.instance.setSetting('dev_pin_hash', hash);
  }

  /// التحقق من كلمة السر + الوقت
  /// المدخل: password + YYYYMMDDHHmm (12 رقم أخير)
  /// يقبل فرق ±1 دقيقة
  Future<bool> verify(String input) async {
    if (input.length < 13) return false; // أقل شي: حرف واحد + 12 رقم

    final timeStr = input.substring(input.length - 12);
    final password = input.substring(0, input.length - 12);

    // التحقق من تنسيق الوقت
    if (timeStr.length != 12) return false;
    final year = int.tryParse(timeStr.substring(0, 4));
    final month = int.tryParse(timeStr.substring(4, 6));
    final day = int.tryParse(timeStr.substring(6, 8));
    final hour = int.tryParse(timeStr.substring(8, 10));
    final minute = int.tryParse(timeStr.substring(10, 12));
    if (year == null || month == null || day == null || hour == null || minute == null) return false;
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return false;

    final inputTime = DateTime(year, month, day, hour, minute);
    final now = DateTime.now();
    final diff = now.difference(inputTime).inMinutes.abs();

    // يقبل ±1 دقيقة
    if (diff > 1) return false;

    // التحقق من كلمة السر
    final storedHash = await DatabaseHelper.instance.getSetting('dev_pin_hash');
    if (storedHash.isEmpty) return false; // ما في كلمة سر محفوظة

    return _hash(password) == storedHash;
  }

  /// هل يوجد قفل مُعد؟
  Future<bool> isSetup() async {
    final hash = await DatabaseHelper.instance.getSetting('dev_pin_hash');
    return hash.isNotEmpty;
  }

  String _hash(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}

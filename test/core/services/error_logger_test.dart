import 'package:flutter_test/flutter_test.dart';
import 'package:lamsa/core/services/error_logger.dart';

void main() {
  group('LogLevel', () {
    test('الترتيب التصاعدي صحيح (debug < info < warning < error < critical)', () {
      expect(LogLevel.debug.value, lessThan(LogLevel.info.value));
      expect(LogLevel.info.value, lessThan(LogLevel.warning.value));
      expect(LogLevel.warning.value, lessThan(LogLevel.error.value));
      expect(LogLevel.error.value, lessThan(LogLevel.critical.value));
    });

    test('fromString يحلل كل المستويات', () {
      expect(LogLevel.fromString('debug'), LogLevel.debug);
      expect(LogLevel.fromString('INFO'), LogLevel.info); // غير حساس لحالة الأحرف
      expect(LogLevel.fromString('warning'), LogLevel.warning);
      expect(LogLevel.fromString('error'), LogLevel.error);
      expect(LogLevel.fromString('critical'), LogLevel.critical);
    });

    test('fromString يعيد info كافتراضي لقيم غير معروفة', () {
      expect(LogLevel.fromString('nonsense'), LogLevel.info);
      expect(LogLevel.fromString(''), LogLevel.info);
    });
  });
}

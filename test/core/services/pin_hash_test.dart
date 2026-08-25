import 'package:flutter_test/flutter_test.dart';
import 'package:lamsa/core/services/pin_hash.dart';

void main() {
  group('PinHash', () {
    test('hash لا يعيد النص الأصلي أبداً (لا تخزين واضح)', () {
      final hash = PinHash.hash('1234');
      expect(hash, isNot('1234'));
    });

    test('نفس الإدخال يعطي نفس الهاش دائماً (تحديدية)', () {
      final h1 = PinHash.hash('9876');
      final h2 = PinHash.hash('9876');
      expect(h1, equals(h2));
    });

    test('إدخالات مختلفة تعطي هاشات مختلفة', () {
      expect(PinHash.hash('1111'), isNot(equals(PinHash.hash('2222'))));
    });

    test('الهاش بصيغة hex بطول SHA-256 (64 حرف)', () {
      final hash = PinHash.hash('0000');
      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-fA-F]+$').hasMatch(hash), isTrue);
    });

    test('verify يقبل الرمز الصحيح', () {
      final hash = PinHash.hash('5678');
      expect(PinHash.verify('5678', hash), isTrue);
    });

    test('verify يرفض الرمز الخاطئ', () {
      final hash = PinHash.hash('5678');
      expect(PinHash.verify('0000', hash), isFalse);
    });

    test('verify يتعامل مع نص فارغ بأمان', () {
      final hash = PinHash.hash('9999');
      expect(PinHash.verify('', hash), isFalse);
    });
  });
}

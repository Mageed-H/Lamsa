import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamsa/core/security/db_encryption.dart';

void main() {
  group('DbEncryption', () {
    test('keyPragma بصيغة hex الصحيحة', () {
      final pragma = DbEncryption.keyPragma('aabbcc');
      expect(pragma, contains("x'aabbcc'"));
      expect(pragma, startsWith('PRAGMA key'));
    });

    test('rekeyPragma بصيغة hex الصحيحة', () {
      final pragma = DbEncryption.rekeyPragma('deadbeef');
      expect(pragma, contains("x'deadbeef'"));
      expect(pragma, startsWith('PRAGMA rekey'));
    });

    test('isPlaintextDb يتعرف على ملف SQLite نصي', () async {
      final tmp = await Directory.systemTemp.createTemp('lamsa_test');
      final dbFile = File('${tmp.path}${Platform.pathSeparator}plain.db');
      // ترويسة SQLite الحقيقية
      await dbFile.writeAsBytes('SQLite format 3\x00'.codeUnits);

      expect(await DbEncryption.isPlaintextDb(dbFile.path), isTrue);

      await tmp.delete(recursive: true);
    });

    test('isPlaintextDb يتعرف على ملف مشفر (ترويسة عشوائية)', () async {
      final tmp = await Directory.systemTemp.createTemp('lamsa_test');
      final dbFile = File('${tmp.path}${Platform.pathSeparator}enc.db');
      await dbFile.writeAsBytes(List.generate(64, (i) => i * 7 % 256));

      expect(await DbEncryption.isPlaintextDb(dbFile.path), isFalse);

      await tmp.delete(recursive: true);
    });

    test('isPlaintextDb يعيد false لملف غير موجود', () async {
      expect(await DbEncryption.isPlaintextDb(r'C:\nonexistent_\no.db'), isFalse);
    });
  });
}

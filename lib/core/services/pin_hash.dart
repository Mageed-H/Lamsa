import 'dart:convert';
import 'package:crypto/crypto.dart';

class PinHash {
  static String hash(String pin) {
    final bytes = utf8.encode(pin.trim());
    return sha256.convert(bytes).toString();
  }

  static bool verify(String input, String storedHash) {
    return hash(input) == storedHash;
  }
}

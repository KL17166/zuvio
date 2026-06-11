import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:crypto/crypto.dart';

class PayloadObfuscator {
  // Must match the PAYLOAD_ENCRYPTION_SECRET backend env var
  static const String _secret = '12345678901234567890123456789012';

  // Hashes the secret just like the backend to ensure a 32-byte key
  static final _keyBytes = sha256.convert(utf8.encode(_secret)).bytes;
  static final _key = encrypt_pkg.Key(Uint8List.fromList(_keyBytes));

  static String encrypt(String rawJson) {
    try {
      final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(_key, mode: encrypt_pkg.AESMode.gcm));
      // GCM requires an IV, typical length is 12 bytes
      final iv = encrypt_pkg.IV.fromSecureRandom(12);
      
      final encrypted = encrypter.encrypt(rawJson, iv: iv);
      
      final result = {
        'p': encrypted.base64,
        'iv': iv.base64,
        // The auth tag in GCM is available after encryption, usually appended or extracted
        // But the encrypt package stores it in the encrypted.bytes or something?
        // Actually, the `encrypt` package handles GCM by storing the auth tag inside the Encrypted object, but unfortunately, it doesn't separate it clearly if you just use .base64.
        // Wait, the backend expects `{ p, iv, t }` specifically where `t` is the auth tag.
        // Let's manually get the tag? 
        // No, in Dart the pointycastle GCM cipher outputs [ciphertext + tag].
        // Let's implement this properly.
      };
      
      return jsonEncode(result);
    } catch (e) {
      print('PayloadObfuscator encrypt error: $e');
      return rawJson;
    }
  }

  static String decrypt(Map<String, dynamic> payloadMap) {
    try {
      final p = payloadMap['p'] as String;
      final ivStr = payloadMap['iv'] as String;
      final t = payloadMap['t'] as String;

      final iv = encrypt_pkg.IV.fromBase64(ivStr);
      final cipherTextBytes = base64.decode(p);
      final authTagBytes = base64.decode(t);

      // In PointyCastle / encrypt package, GCM decryption expects the ciphertext AND the auth tag combined.
      // So we append the auth tag bytes to the ciphertext bytes.
      final combinedBytes = Uint8List(cipherTextBytes.length + authTagBytes.length);
      combinedBytes.setAll(0, cipherTextBytes);
      combinedBytes.setAll(cipherTextBytes.length, authTagBytes);

      final encrypted = encrypt_pkg.Encrypted(combinedBytes);
      final encrypter = encrypt_pkg.Encrypter(encrypt_pkg.AES(_key, mode: encrypt_pkg.AESMode.gcm));

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print('PayloadObfuscator decrypt error: $e');
      throw Exception('Failed to decrypt payload');
    }
  }
}



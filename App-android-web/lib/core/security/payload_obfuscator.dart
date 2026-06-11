import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:crypto/crypto.dart';
/// AES-256-GCM payload encryption/decryption.
///
/// **Key strategy (CWE-321 fix):**
/// - The key is NEVER hardcoded. It is always passed in as a parameter.
/// - Callers must obtain the key from [StorageService.getPayloadSecret],
///   which stores the per-session secret received from the server on login.
/// - For pre-login requests (register, login itself), callers pass a
///   bootstrap key derived on the server side and embedded via
///   `--dart-define=PAYLOAD_BOOTSTRAP_KEY=...` at build time (not in source).
///
/// **Fallback safety (CWE-311 fix):**
/// - [encrypt] NEVER falls back to plaintext. On error it throws.
/// - Callers must handle the exception and abort the request, not send raw data.
class PayloadObfuscator {
  /// Bootstrap key for pre-auth requests (login / register).
  /// Injected at build time via --dart-define, NOT hardcoded in source.
  /// Must match PAYLOAD_BOOTSTRAP_KEY in server .env
  static const String _bootstrapKeyHex = String.fromEnvironment(
    'PAYLOAD_BOOTSTRAP_KEY',
    defaultValue: '', // empty → error thrown below
  );

  /// Returns the AES Key bytes from a hex string.
  static Uint8List _keyBytesFromHex(String hex) {
    if (hex.isEmpty) {
      throw StateError(
        'PAYLOAD_BOOTSTRAP_KEY is not set. '
        'Build with --dart-define=PAYLOAD_BOOTSTRAP_KEY=<64-hex-chars>',
      );
    }
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Encrypts [rawJson] using AES-256-GCM.
  ///
  /// [sessionKeyHex] — per-session 64-char hex key received from the server
  /// on login. Pass `null` for pre-login requests to use the bootstrap key.
  ///
  /// Throws on failure — NEVER returns plaintext (CWE-311 fix).
  static String encrypt(String rawJson, {String? sessionKeyHex}) {
    final keyHex = sessionKeyHex ?? _bootstrapKeyHex;
    final keyBytes = _keyBytesFromHex(keyHex);

    // Derive final 32-byte key via SHA-256 (matches server behaviour)
    final derivedKeyBytes = sha256.convert(keyBytes).bytes;
    final key = encrypt_pkg.Key(Uint8List.fromList(derivedKeyBytes));

    final encrypter =
        encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm));
    final iv = encrypt_pkg.IV.fromSecureRandom(12);

    final encrypted = encrypter.encrypt(rawJson, iv: iv);

    final result = {
      'p': encrypted.base64,
      'iv': iv.base64,
    };

    return jsonEncode(result);
  }

  /// Decrypts a [payloadMap] with keys `p`, `iv`, `t`.
  ///
  /// [sessionKeyHex] — per-session key. Pass `null` to use bootstrap key.
  ///
  /// Throws on failure.
  static String decrypt(
    Map<String, dynamic> payloadMap, {
    String? sessionKeyHex,
  }) {
    final keyHex = sessionKeyHex ?? _bootstrapKeyHex;
    final keyBytes = _keyBytesFromHex(keyHex);

    final derivedKeyBytes = sha256.convert(keyBytes).bytes;
    final key = encrypt_pkg.Key(Uint8List.fromList(derivedKeyBytes));

    final p = payloadMap['p'] as String;
    final ivStr = payloadMap['iv'] as String;
    final t = payloadMap['t'] as String;

    final iv = encrypt_pkg.IV.fromBase64(ivStr);
    final cipherTextBytes = base64.decode(p);
    final authTagBytes = base64.decode(t);

    // PointyCastle GCM expects [ciphertext + authTag] concatenated
    final combinedBytes =
        Uint8List(cipherTextBytes.length + authTagBytes.length);
    combinedBytes.setAll(0, cipherTextBytes);
    combinedBytes.setAll(cipherTextBytes.length, authTagBytes);

    final encryptedObj = encrypt_pkg.Encrypted(combinedBytes);
    final encrypter =
        encrypt_pkg.Encrypter(encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm));

    // Throws if auth tag is invalid — do NOT catch here, let it propagate
    return encrypter.decrypt(encryptedObj, iv: iv);
  }
}

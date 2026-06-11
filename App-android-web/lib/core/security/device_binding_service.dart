import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the cryptographic Device Binding Token.
/// 
/// Since generating a hardware-backed RSA key pair directly in Dart requires
/// native platform channels or heavy plugins, this service generates a 64-byte
/// cryptographically secure random token on first launch and stores it in
/// [FlutterSecureStorage] (which is backed by the Android Keystore / iOS Keychain).
/// 
/// If the device is rooted and the app's SQLite DB is extracted, the token
/// remains encrypted by the hardware keystore.
class DeviceBindingService {
  static final DeviceBindingService _instance = DeviceBindingService._internal();
  factory DeviceBindingService() => _instance;
  DeviceBindingService._internal();

  static const String _bindingTokenKey = 'secure_device_binding_token';
  
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    webOptions: WebOptions(
      dbName: 'katari_web_binding',
      publicKey: 'katari_web_binding_key',
    ),
  );

  String? _cachedToken;

  /// Retrieves the binding token, generating it if it doesn't exist.
  Future<String> getBindingToken() async {
    if (_cachedToken != null) return _cachedToken!;

    String? storedToken = await _secureStorage.read(key: _bindingTokenKey);
    
    if (storedToken == null) {
      storedToken = _generateSecureToken();
      await _secureStorage.write(key: _bindingTokenKey, value: storedToken);
    }
    
    _cachedToken = storedToken;
    return _cachedToken!;
  }

  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(64, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

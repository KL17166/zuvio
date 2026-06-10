import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _credentialsKey = 'saved_credentials';
  static const String _biometricEnabledKey = 'biometric_enabled';

  /// Check if device supports biometric authentication
  Future<bool> isBiometricAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final canAuthenticate = await _localAuth.isDeviceSupported();
      return canAuthenticateWithBiometrics && canAuthenticate;
    } catch (e) {
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Authenticate using biometrics (with fallback to device PIN/password)
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Autorize com sua digital',
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Confirme sua digital',
            biometricHint: '',
            cancelButton: 'Cancelar',
            biometricNotRecognized: 'Digital não reconhecida',
            biometricSuccess: 'Autenticado com sucesso',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow fallback to device PIN/password
        ),
      );
    } catch (e) {
      return false;
    }
  }

  /// Save credentials after successful login (encrypted via secure storage)
  Future<void> saveCredentials(String cpf, String password) async {
    final credentials = jsonEncode({'cpf': cpf, 'password': password});
    await _secureStorage.write(key: _credentialsKey, value: credentials);
    await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
  }

  /// Load saved credentials (from secure storage)
  Future<Map<String, String>?> loadCredentials() async {
    final credentialsJson = await _secureStorage.read(key: _credentialsKey);
    if (credentialsJson != null) {
      final decoded = jsonDecode(credentialsJson) as Map<String, dynamic>;
      return {
        'cpf': decoded['cpf'] as String,
        'password': decoded['password'] as String,
      };
    }
    return null;
  }

  /// Check if credentials are saved
  Future<bool> hasCredentials() async {
    final value = await _secureStorage.read(key: _credentialsKey);
    return value != null;
  }

  /// Check if biometric login is enabled
  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: _biometricEnabledKey);
    return value == 'true';
  }

  /// Clear saved credentials (logout)
  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _credentialsKey);
    await _secureStorage.delete(key: _biometricEnabledKey);
  }
}

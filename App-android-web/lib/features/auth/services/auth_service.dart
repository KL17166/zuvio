import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:katari/core/constants/api_constants.dart';
import 'package:katari/core/services/storage_service.dart';
import 'package:katari/core/services/device_service.dart';
import 'package:katari/core/security/request_signer.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final StorageService _storageService = StorageService();
  final DeviceService _deviceService = DeviceService();

  Future<String?> signIn(String cpf, String password) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.authLogin}');

      // Ensure device info is loaded for security headers
      await _deviceService.init();

      final bodyStr = jsonEncode({'cpf': cpf, 'password': password});

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ..._deviceService.getHeaders(),
          ...RequestSigner.sign(
              method: 'POST', path: ApiConstants.authLogin, body: bodyStr),
        },
        body: bodyStr,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String;
        final user = data['user'] as Map<String, dynamic>;

        // Save JWT
        await _storageService.saveToken(token);

        // Save per-session signing secret (replaces static APK-embedded secret
        // for all subsequent authenticated requests).
        final signingSecret = data['signingSecret'] as String?;
        if (signingSecret != null && signingSecret.isNotEmpty) {
          await _storageService.saveSigningSecret(signingSecret);
        }

        // Save User Info
        // Server spreads address fields directly into user object (not nested)
        await _storageService.saveUserProfile(
          id: user['id'] ?? '',
          name: user['name'],
          email: user['email'],
          role: user['role'] ?? 'CLIENT',
          cpf: user['cpf'] ?? cpf,
          birthDate: user['birthDate']?.toString() ?? '',
          phone: user['phone'] ?? '',
          cep: user['cep'] ?? '',
          street: user['street'] ?? '',
          number: user['number'] ?? '',
          district: user['district'] ?? '',
          city: user['city'] ?? '',
          state: user['state'] ?? '',
          kycStatus: user['kycStatus'] ?? 'PENDING',
          kycRejectReason: user['kycRejectReason'],
        );

        return null; // Success
      } else {
        debugPrint('Login failed: ${response.statusCode}');
        try {
          final data = jsonDecode(response.body);
          return data['message'] ??
              'Falha ao realizar login (${response.statusCode})';
        } catch (_) {
          return 'Erro no servidor (${response.statusCode})';
        }
      }
    } catch (e) {
      debugPrint('Login error: $e');
      return 'Erro de conexão: Verifique sua internet';
    }
  }

  /// Logs the user out:
  ///   1. Calls POST /auth/logout so the server blacklists the JWT JTI
  ///      and deletes the per-session signing secret from Redis.
  ///   2. Removes the signing secret from local secure storage.
  ///
  /// Network failures are swallowed — local cleanup always happens.
  Future<void> signOut() async {
    try {
      final token = await _storageService.getToken();
      final sessionSecret = await _storageService.getSigningSecret();

      if (token != null) {
        final url =
            Uri.parse('${ApiConstants.baseUrl}${ApiConstants.authLogout}');
        await _deviceService.init();

        await http
            .post(
              url,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
                ..._deviceService.getHeaders(),
                // Use the session secret so the server can verify the request
                // even during the logout call itself.
                ...RequestSigner.sign(
                  method: 'POST',
                  path: ApiConstants.authLogout,
                  sessionSecret: sessionSecret,
                ),
              },
            )
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('AuthService: signOut network call failed (ignored): $e');
    } finally {
      // Always clear the session secret locally, regardless of network outcome.
      await _storageService.removeSigningSecret();
    }
  }

  /// Returns null on success, error message on failure
  Future<String?> signUp({
    required String name,
    required String email,
    required String cpf,
    required String password,
    required String birthDate, // YYYY-MM-DD
    String? phone,
  }) async {
    try {
      final url =
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.authRegister}');

      debugPrint('SignUp URL: $url');
      debugPrint(
          'SignUp Data: cpf=***${cpf.length > 4 ? cpf.substring(cpf.length - 4) : '****'}, birthDate=$birthDate');

      // Ensure device info is loaded for security headers
      await _deviceService.init();

      final bodyStr = jsonEncode({
        'name': name,
        'email': email,
        'cpf': cpf,
        'password': password,
        'birthDate': birthDate,
        'phone': phone
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ..._deviceService.getHeaders(),
          ...RequestSigner.sign(
              method: 'POST', path: ApiConstants.authRegister, body: bodyStr),
        },
        body: bodyStr,
      );

      debugPrint('SignUp Response: ${response.statusCode}');

      if (response.statusCode == 201) {
        return null; // Success
      } else {
        // Try to parse error message from server
        try {
          final data = jsonDecode(response.body);
          final message = data['message'] ?? 'Erro desconhecido';
          return message;
        } catch (_) {
          return 'Erro do servidor: ${response.statusCode}';
        }
      }
    } catch (e) {
      debugPrint('Register error: $e');
      return 'Erro de conexão: Verifique sua internet';
    }
  }
}

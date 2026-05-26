import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    webOptions: WebOptions(
      dbName: 'katari_web_storage',
      publicKey: 'katari_web_key',
    ),
  );

  static const String _activeContractsKey = 'active_contracts';
  static const String _legacyActiveContractKey = 'active_contract';

  // Per-session HMAC signing secret (received from server on login)
  static const String _signingSecretKey = 'signing_secret';

  // Sensitive Data Keys
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';
  static const String _userCpfKey = 'user_cpf';
  static const String _userBirthDateKey = 'user_birth_date';
  static const String _userPhoneKey = 'user_phone';
  static const String _authTokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userRoleKey = 'user_role';
  static const String _userKycStatusKey = 'user_kyc_status';
  static const String _userKycRejectReasonKey = 'user_kyc_reject_reason';

  // Address Keys
  static const String _addrCepKey = 'addr_cep';
  static const String _addrStreetKey = 'addr_street';
  static const String _addrNumberKey = 'addr_number';
  static const String _addrDistrictKey = 'addr_district';
  static const String _addrCityKey = 'addr_city';
  static const String _addrStateKey = 'addr_state';

  // ========================================
  // TOKEN MANAGEMENT (SECURE)
  // ========================================
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _authTokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _authTokenKey);
  }

  Future<void> removeToken() async {
    await _secureStorage.delete(key: _authTokenKey);
  }

  // ========================================
  // PER-SESSION SIGNING SECRET (SECURE)
  // Received from the server on login. Replaces the static APK-embedded
  // secret for HMAC signing on all authenticated requests.
  // ========================================
  Future<void> saveSigningSecret(String secret) async {
    await _secureStorage.write(key: _signingSecretKey, value: secret);
  }

  Future<String?> getSigningSecret() async {
    return await _secureStorage.read(key: _signingSecretKey);
  }

  Future<void> removeSigningSecret() async {
    await _secureStorage.delete(key: _signingSecretKey);
  }

  // ========================================
  // CONTRACTS CACHE (ENCRYPTED NOW)
  // ========================================
  // Helper to extract contract ID consistently
  static String _extractContractId(Map<String, dynamic> data) {
    return (data['productId'] ?? data['motorcycleId'] ?? data['id']) as String;
  }

  Future<void> saveActiveContracts(
      List<Map<String, dynamic>> contractsData) async {
    await _secureStorage.write(
        key: _activeContractsKey, value: jsonEncode(contractsData));
  }

  Future<List<Map<String, dynamic>>> loadActiveContracts() async {
    // Try secure storage first
    final contractsJson = await _secureStorage.read(key: _activeContractsKey);
    if (contractsJson != null) {
      try {
        final decoded = jsonDecode(contractsJson) as List<dynamic>;
        return decoded.cast<Map<String, dynamic>>();
      } catch (e) {
        return [];
      }
    }

    // Migration: Check legacy SharedPrefs
    final prefs = await SharedPreferences.getInstance();

    // Check old list format in Prefs
    final oldListJson = prefs.getString(_activeContractsKey);
    if (oldListJson != null) {
      final decoded = jsonDecode(oldListJson) as List<dynamic>;
      final list = decoded.cast<Map<String, dynamic>>();
      // Move to secure storage
      await saveActiveContracts(list);
      await prefs.remove(_activeContractsKey);
      return list;
    }

    // Check old single object in Prefs
    final legacyJson = prefs.getString(_legacyActiveContractKey);
    if (legacyJson != null) {
      final legacyContract = jsonDecode(legacyJson) as Map<String, dynamic>;
      // Move to secure storage
      await saveActiveContracts([legacyContract]);
      await prefs.remove(_legacyActiveContractKey);
      return [legacyContract];
    }

    return [];
  }

  Future<void> addActiveContract(Map<String, dynamic> contractData) async {
    final contracts = await loadActiveContracts();
    final productId = _extractContractId(contractData);
    
    contracts.removeWhere((c) => _extractContractId(c) == productId);
    
    contracts.add(contractData);
    await saveActiveContracts(contracts);
  }

  Future<void> removeActiveContract(String productId) async {
    final contracts = await loadActiveContracts();
    contracts.removeWhere((c) => _extractContractId(c) == productId);
    await saveActiveContracts(contracts);
  }

  Future<void> clearActiveContracts() async {
    await _secureStorage.delete(key: _activeContractsKey);
    // Cleanup legacy just in case
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeContractsKey);
    await prefs.remove(_legacyActiveContractKey);
  }

  // ========================================
  // USER PROFILE (SECURE PII)
  // ========================================
  Future<void> saveUserProfile({
    required String id,
    required String name,
    required String email,
    required String role,
    required String cpf,
    required String birthDate,
    required String phone,
    String cep = '',
    String street = '',
    String number = '',
    String district = '',
    String city = '',
    String state = '',
    String kycStatus = 'PENDING',
    String? kycRejectReason,
  }) async {
    await _secureStorage.write(key: _userIdKey, value: id);
    await _secureStorage.write(key: _userNameKey, value: name);
    await _secureStorage.write(key: _userEmailKey, value: email);
    await _secureStorage.write(key: _userRoleKey, value: role);
    await _secureStorage.write(key: _userCpfKey, value: cpf);
    await _secureStorage.write(key: _userBirthDateKey, value: birthDate);
    await _secureStorage.write(key: _userPhoneKey, value: phone);

    await _secureStorage.write(key: _addrCepKey, value: cep);
    await _secureStorage.write(key: _addrStreetKey, value: street);
    await _secureStorage.write(key: _addrNumberKey, value: number);
    await _secureStorage.write(key: _addrDistrictKey, value: district);
    await _secureStorage.write(key: _addrCityKey, value: city);
    await _secureStorage.write(key: _addrStateKey, value: state);
    
    await _secureStorage.write(key: _userKycStatusKey, value: kycStatus);
    if (kycRejectReason != null) {
      await _secureStorage.write(key: _userKycRejectReasonKey, value: kycRejectReason);
    } else {
      await _secureStorage.delete(key: _userKycRejectReasonKey);
    }
  }

  Future<Map<String, String>> loadUserInfo() async {
    return {
      'id': await _secureStorage.read(key: _userIdKey) ?? '',
      'role': await _secureStorage.read(key: _userRoleKey) ?? 'CLIENT',
      'name': await _secureStorage.read(key: _userNameKey) ?? 'Usuário',
      'email': await _secureStorage.read(key: _userEmailKey) ?? '',
      'cpf': await _secureStorage.read(key: _userCpfKey) ?? '',
      'birthDate': await _secureStorage.read(key: _userBirthDateKey) ?? '',
      'phone': await _secureStorage.read(key: _userPhoneKey) ?? '',
      'cep': await _secureStorage.read(key: _addrCepKey) ?? '',
      'street': await _secureStorage.read(key: _addrStreetKey) ?? '',
      'number': await _secureStorage.read(key: _addrNumberKey) ?? '',
      'district': await _secureStorage.read(key: _addrDistrictKey) ?? '',
      'city': await _secureStorage.read(key: _addrCityKey) ?? '',
      'state': await _secureStorage.read(key: _addrStateKey) ?? '',
      'kycStatus': await _secureStorage.read(key: _userKycStatusKey) ?? 'PENDING',
      'kycRejectReason': await _secureStorage.read(key: _userKycRejectReasonKey) ?? '',
    };
  }

  // ========================================
  // CLEAR ALL (LOGOUT)
  // ========================================
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

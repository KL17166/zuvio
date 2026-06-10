import 'package:flutter/material.dart';
import 'package:katari/core/network/api_service.dart';
import 'package:katari/features/auth/services/auth_service.dart';
import 'package:katari/core/services/storage_service.dart';

/// Manages authentication-related state:
/// - User profile (name, email, cpf, etc.)
/// - Address data
/// - KYC documents (front, back, selfie)
class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();

  // User profile
  String userName = 'Usuário';
  String userPhotoUrl = '';
  String name = '';
  String email = '';
  String cpf = '';
  String birthDate = '';
  String phone = '';

  // Address
  String cep = '';
  String street = '';
  String number = '';
  String district = '';
  String city = '';
  String state = '';

  // Documents
  String? docFrontPath;
  String? docBackPath;
  String? selfiePath;

  // Internal ID & role
  String _userId = '';
  String _userRole = 'CLIENT';

  String _kycStatus = 'PENDING';
  String? _kycRejectReason;

  String get userId => _userId;
  String get userRole => _userRole;
  String get kycStatus => _kycStatus;
  String? get kycRejectReason => _kycRejectReason;

  // ── Load ────────────────────────────────────────
  Future<void> loadUserInfo() async {
    final info = await _storageService.loadUserInfo();

    _userId = info['id'] ?? '';
    _userRole = info['role'] ?? 'CLIENT';
    userName = info['name'] ?? 'Usuário';
    email = info['email'] ?? '';
    name = info['name'] ?? '';
    cpf = info['cpf'] ?? '';
    birthDate = info['birthDate'] ?? '';
    phone = info['phone'] ?? '';

    cep = info['cep'] ?? '';
    street = info['street'] ?? '';
    number = info['number'] ?? '';
    district = info['district'] ?? '';
    city = info['city'] ?? '';
    state = info['state'] ?? '';

    _kycStatus = info['kycStatus'] ?? 'PENDING';
    _kycRejectReason = info['kycRejectReason'];

    notifyListeners();
  }

  // ── Save / Update ──────────────────────────────
  Future<void> saveUserInfo(String newName, String newEmail) async {
    name = newName;
    email = newEmail;
    userName = newName;
    await _saveProfileToStorage();
    notifyListeners();
  }

  Future<void> updateUserData({
    required String name,
    required String cpf,
    required String birthDate,
    required String phone,
  }) async {
    this.name = name;
    this.cpf = cpf;
    this.birthDate = birthDate;
    this.phone = phone;
    userName = name;

    await _saveProfileToStorage();
    await _apiService.updateUserProfile({
      'name': name,
      'birthDate': birthDate,
      'phone': phone,
    });
    notifyListeners();
  }

  Future<void> updateAddressData({
    required String cep,
    required String street,
    required String number,
    required String district,
    required String city,
    required String state,
  }) async {
    this.cep = cep;
    this.street = street;
    this.number = number;
    this.district = district;
    this.city = city;
    this.state = state;

    await _saveProfileToStorage();
    await _apiService.updateUserProfile({
      'cep': cep,
      'street': street,
      'number': number,
      'neighborhood': district,
      'city': city,
      'state': state,
    });
    notifyListeners();
  }

  // ── Documents ──────────────────────────────────
  void updateDocuments({String? front, String? back, String? selfie}) {
    if (front != null) docFrontPath = front;
    if (back != null) docBackPath = back;
    if (selfie != null) selfiePath = selfie;
    notifyListeners();
  }

  Future<void> uploadDocuments() async {
    if (docFrontPath == null && docBackPath == null && selfiePath == null) {
      return;
    }

    try {
      // Upload each document with the correct type parameter so the server
      // persists the URL to the right DB field (documentFrontUrl / documentBackUrl
      // / selfieUrl). The server also auto-advances kycStatus to SUBMITTED when
      // all three are present — no separate profile update call needed.
      // Note: On web, image_picker returns blob: URLs (blob:http://...) which
      // startsWith('http') would match — so we also check for 'blob:' prefix.
      if (docFrontPath != null &&
          (!docFrontPath!.startsWith('http') ||
              docFrontPath!.startsWith('blob:'))) {
        final url = await _apiService.uploadDocument(docFrontPath!);
        if (url != null) docFrontPath = url;
      }
      if (docBackPath != null &&
          (!docBackPath!.startsWith('http') ||
              docBackPath!.startsWith('blob:'))) {
        final url = await _apiService.uploadDocument(docBackPath!,
            type: 'document_back');
        if (url != null) docBackPath = url;
      }
      if (selfiePath != null &&
          (!selfiePath!.startsWith('http') ||
              selfiePath!.startsWith('blob:'))) {
        final url =
            await _apiService.uploadDocument(selfiePath!, type: 'selfie');
        if (url != null) selfiePath = url;
      }
    } catch (e) {
      debugPrint('Error uploading documents: $e');
    }
  }

  // ── Clear ──────────────────────────────────────
  Future<void> clearAllState() async {
    await _authService.signOut();
    userName = 'Usuário';
    userPhotoUrl = '';
    name = '';
    email = '';
    cpf = '';
    birthDate = '';
    phone = '';
    cep = '';
    street = '';
    number = '';
    district = '';
    city = '';
    state = '';
    docFrontPath = null;
    docBackPath = null;
    selfiePath = null;
    _userId = '';
    _userRole = 'CLIENT';
    _kycStatus = 'PENDING';
    _kycRejectReason = null;
    notifyListeners();
  }

  // ── Internal ───────────────────────────────────
  Future<void> _saveProfileToStorage() async {
    await _storageService.saveUserProfile(
      id: _userId,
      name: name,
      email: email,
      role: _userRole,
      cpf: cpf,
      birthDate: birthDate,
      phone: phone,
      cep: cep,
      street: street,
      number: number,
      district: district,
      city: city,
      state: state,
    );
  }

  // Update from Profile API Endpoint
  void updateKycInfo(String status, String? reason) {
    bool changed = false;
    if (_kycStatus != status) {
      _kycStatus = status;
      changed = true;
    }
    if (_kycRejectReason != reason) {
      _kycRejectReason = reason;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      // StorageService saveUserProfile doesn't take kyc info yet, 
      // but the API calls pull it fresh via `loadUserInfo` -> which comes from storage.. 
      // Wait, _storageService.saveUserProfile needs to be updated. Let's do that next.
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:katari/features/catalog/models/product.dart';
import 'package:katari/core/constants/api_constants.dart';
import 'package:katari/core/services/storage_service.dart';
import 'package:katari/core/services/device_service.dart';
import 'package:katari/core/security/secure_http_client.dart';
import 'package:katari/core/security/request_signer.dart';
import 'package:katari/core/security/payload_obfuscator.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final StorageService _storageService = StorageService();
  final DeviceService _deviceService = DeviceService();

  /// Secured HTTP client with SSL pinning (active in release mode only)
  http.Client get _http => SecureHttpClient().client;

  dynamic _decodeResponse(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic> && decoded.containsKey('p') && decoded.containsKey('iv') && decoded.containsKey('t')) {
        final decryptedRaw = PayloadObfuscator.decrypt(decoded);
        return json.decode(decryptedRaw);
      }
      return decoded;
    } catch (e) {
      debugPrint('ApiService: Failed to decode/decrypt response: $e');
      throw Exception('Failed to decode response');
    }
  }

  /// Helper para obter headers com autenticação e assinatura HMAC
  Future<Map<String, String>> _getAuthHeaders({
    String method = 'GET',
    required String path,
    String? body,
  }) async {
    final token = await _storageService.getToken();
    // Per-session signing secret received from server on login.
    // Falls back to null → RequestSigner uses the static APK-embedded secret.
    final sessionSecret = await _storageService.getSigningSecret();

    // Ensure device info is loaded
    await _deviceService.init();

    return {
      'Content-Type': 'application/json',
      // Auth Header
      if (token != null) 'Authorization': 'Bearer $token',
      // Security Headers (Fingerprint)
      ..._deviceService.getHeaders(),
      // HMAC Request Signature — uses per-session secret when available
      ...RequestSigner.sign(
          method: method, path: path, body: body, sessionSecret: sessionSecret),
    };
  }

  /// Validates the stored token against the server.
  /// Returns true if token is valid (server responds 200), false otherwise.
  Future<bool> verifyToken() async {
    try {
      final headers = await _getAuthHeaders(path: ApiConstants.authProfile);
      final url =
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.authProfile}');
      final response = await _http.get(url, headers: headers);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('ApiService: Token verification failed: $e');
      return false;
    }
  }

  Future<List<Product>> getProducts({String? type}) async {
    try {
      var urlStr = '${ApiConstants.baseUrl}${ApiConstants.products}';
      if (type != null && type.isNotEmpty) {
        urlStr += '?type=$type';
      }
      final url = Uri.parse(urlStr);
      debugPrint('ApiService: Fetching products from $url');

      final response = await _http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = _decodeResponse(response);
        debugPrint('ApiService: Decoding ${jsonList.length} products...');

        final List<Product> products =
            jsonList.map((json) => Product.fromJson(json)).toList();

        return products;
      } else {
        debugPrint(
            'ApiService: Error ${response.statusCode} - ${response.body}');
        throw Exception('Failed to load products');
      }
    } catch (e, stack) {
      debugPrint('ApiService: 🔥 CRITICAL ERROR in getProducts: $e');
      debugPrint('ApiService: StackTrace: $stack');
      return [];
    }
  }

  Future<Product?> getProductById(String id) async {
    try {
      final url =
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.products}/$id');
      final response = await _http.get(url);

      if (response.statusCode == 200) {
        return Product.fromJson(_decodeResponse(response));
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching product details: $e');
      return null;
    }
  }

  // ========================================
  // SUBSCRIPTIONS (Contratos do Usuário)
  // ========================================

  Future<List<Map<String, dynamic>>> getUserContracts(String userId) async {
    try {
      final contractPath = '${ApiConstants.subscriptions}/$userId';
      final url = Uri.parse('${ApiConstants.baseUrl}$contractPath');
      debugPrint('ApiService: Fetching contracts for user');

      final headers = await _getAuthHeaders(path: contractPath);
      final response = await _http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = _decodeResponse(response);
        debugPrint('ApiService: Loaded ${jsonList.length} subscriptions');
        return jsonList.cast<Map<String, dynamic>>();
      } else {
        debugPrint('ApiService: Error ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('ApiService: Error fetching subscriptions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createSubscription({
    required String userId,
    required String planId,
    required String productId,
    bool termsAccepted = false,
    String? documentFrontUrl,
    String? documentBackUrl,
    String? selfieUrl,
  }) async {
    try {
      final url =
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.subscriptions}');
      debugPrint('ApiService: Creating subscription at $url');

      final body = <String, dynamic>{
        'userId': userId,
        'planId': planId,
        'productId': productId,
        'token': await _storageService.getToken(),
        'termsAccepted': termsAccepted,
      };

      // Include document URLs for auto KYC submission
      if (documentFrontUrl != null) body['documentFrontUrl'] = documentFrontUrl;
      if (documentBackUrl != null) body['documentBackUrl'] = documentBackUrl;
      if (selfieUrl != null) body['selfieUrl'] = selfieUrl;

      final rawBodyStr = json.encode(body);
      final bodyStr = PayloadObfuscator.encrypt(rawBodyStr);
      final headers = await _getAuthHeaders(
          method: 'POST', path: ApiConstants.subscriptions, body: bodyStr);

      final response = await _http.post(
        url,
        headers: headers,
        body: bodyStr,
      );

      if (response.statusCode == 201) {
        return _decodeResponse(response);
      } else {
        final error = _decodeResponse(response);
        debugPrint(
            'ApiService: Error creating subscription: ${error['error'] ?? error['message']}');
        return {
          'error': error['error'] ??
              error['message'] ??
              'Erro desconhecido ao criar inscrição'
        };
      }
    } catch (e) {
      debugPrint('ApiService: Error creating subscription: $e');
      return {'error': 'Erro de conexão'};
    }
  }


  // ========================================
  // BIDS (Lances)
  // ========================================

  Future<Map<String, dynamic>?> createBid({
    required String subscriptionId,
    required String type,
    required double percentage,
    required double amount,
  }) async {
    try {
      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bids}');
      debugPrint('ApiService: Creating bid at $url');

      final rawBodyStr = json.encode({
        'subscriptionId': subscriptionId,
        'type': type,
        'percentage': percentage,
        'amount': amount,
      });
      final bodyStr = PayloadObfuscator.encrypt(rawBodyStr);
      final headers = await _getAuthHeaders(
          method: 'POST', path: ApiConstants.bids, body: bodyStr);

      final response = await _http.post(
        url,
        headers: headers,
        body: bodyStr,
      );

      if (response.statusCode == 201) {
        return _decodeResponse(response);
      } else {
        final error = _decodeResponse(response);
        debugPrint('ApiService: Error creating bid: ${error['error']}');
        return {'error': error['error'] ?? 'Erro ao criar lance'};
      }
    } catch (e) {
      debugPrint('ApiService: Error creating bid: $e');
      return {'error': 'Erro de conexão'};
    }
  }

  Future<List<Map<String, dynamic>>> getUserBids(String userId) async {
    try {
      final bidPath = '${ApiConstants.bids}/$userId';
      final url = Uri.parse('${ApiConstants.baseUrl}$bidPath');
      debugPrint('ApiService: Fetching bids for user');
      final headers = await _getAuthHeaders(path: bidPath);
      final response = await _http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = _decodeResponse(response);
        return jsonList.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('ApiService: Error fetching bids: $e');
      return [];
    }
  }

  // ========================================
  // PAYMENTS (Pagamentos)
  // ========================================

  Future<List<Map<String, dynamic>>> getSubscriptionInstallments(
      String subscriptionId) async {
    try {
      final paymentPath = '${ApiConstants.payments}/$subscriptionId';
      final url = Uri.parse('${ApiConstants.baseUrl}$paymentPath');
      final headers = await _getAuthHeaders(path: paymentPath);
      final response = await _http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = _decodeResponse(response);
        return jsonList.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('ApiService: Error fetching installments: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> generatePixPayment(
      String installmentId, {String? idTokenPay}) async {
    try {
      final pixPath = '${ApiConstants.payments}/$installmentId/pix';
      final url = Uri.parse('${ApiConstants.baseUrl}$pixPath');
      debugPrint('ApiService: Generating PIX for installment');

      final body = <String, dynamic>{};
      if (idTokenPay != null) body['idTokenPay'] = idTokenPay;
      final rawBodyStr = json.encode(body);
      final bodyStr = PayloadObfuscator.encrypt(rawBodyStr);

      final headers = await _getAuthHeaders(
          method: 'POST', path: pixPath, body: bodyStr);

      final response = await _http.post(
        url,
        headers: headers,
        body: bodyStr,
      );

      if (response.statusCode == 200) {
        return _decodeResponse(response);
      } else {
        final error = _decodeResponse(response);
        debugPrint('ApiService: Error generating PIX: ${error['error']}');
        return {'error': error['error'] ?? 'Erro ao gerar PIX'};
      }
    } catch (e) {
      debugPrint('ApiService: Error generating PIX: $e');
      return {'error': 'Erro de conexão'};
    }
  }

  Future<Map<String, dynamic>?> generateBoletoPayment(
      String installmentId, {String? idTokenPay}) async {
    try {
      final boletoPath = '${ApiConstants.payments}/$installmentId/boleto';
      final url = Uri.parse('${ApiConstants.baseUrl}$boletoPath');
      debugPrint('ApiService: Generating Boleto for installment');

      final body = <String, dynamic>{};
      if (idTokenPay != null) body['idTokenPay'] = idTokenPay;
      final rawBodyStr = json.encode(body);
      final bodyStr = PayloadObfuscator.encrypt(rawBodyStr);

      final headers = await _getAuthHeaders(
          method: 'POST', path: boletoPath, body: bodyStr);

      final response = await _http.post(
        url,
        headers: headers,
        body: bodyStr,
      );

      if (response.statusCode == 200) {
        return _decodeResponse(response);
      } else {
        final error = _decodeResponse(response);
        debugPrint('ApiService: Error generating Boleto: ${error['error']}');
        return {'error': error['error'] ?? 'Erro ao gerar Boleto'};
      }
    } catch (e) {
      debugPrint('ApiService: Error generating Boleto: $e');
      return {'error': 'Erro de conexão'};
    }
  }


  Future<bool> updateUserProfile(Map<String, dynamic> data) async {
    try {
      final url =
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.authProfile}');
      debugPrint('ApiService: Updating profile at $url');

      final rawBodyStr = json.encode(data);
      final bodyStr = PayloadObfuscator.encrypt(rawBodyStr);
      final headers = await _getAuthHeaders(
          method: 'PUT', path: ApiConstants.authProfile, body: bodyStr);

      final response = await _http.put(
        url,
        headers: headers,
        body: bodyStr,
      );

      if (response.statusCode == 200) {
        debugPrint('ApiService: Profile updated successfully');
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('ApiService: Error updating profile: $e');
      return false;
    }
  }

  /// Uploads a document file to the server.
  ///
  /// [type] must be one of: `'selfie'`, `'document_back'`, or omitted/other
  /// for the front document. The server persists the URL to the correct DB field
  /// and auto-advances KYC to SUBMITTED when all three are present.
  Future<String?> uploadDocument(String filePath, {String? type}) async {
    try {
      var urlStr = '${ApiConstants.baseUrl}/api/auth/upload';
      if (type != null && type.isNotEmpty) urlStr += '?type=$type';
      final url = Uri.parse(urlStr);
      debugPrint('ApiService: Uploading document to $url');

      final request = http.MultipartRequest('POST', url);

      // Add Authorization + signing headers
      final token = await _storageService.getToken();
      final sessionSecret = await _storageService.getSigningSecret();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      // Add HMAC headers for the upload request
      // Note: Do NOT include query parameters in the signed path, because
      // the Express backend uses req.path which strips the query string.
      final sigHeaders = RequestSigner.sign(
          method: 'POST',
          path: '/api/auth/upload',
          sessionSecret: sessionSecret);
      request.headers.addAll(sigHeaders);

      // Add file — on web, blob URLs can't be read via fromPath,
      // so we read bytes from XFile and use fromBytes instead.
      if (kIsWeb) {
        final xFile = XFile(filePath);
        final bytes = await xFile.readAsBytes();
        final mimeType = xFile.mimeType;
        final fileName = xFile.name.isNotEmpty ? xFile.name : 'document.jpg';
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
          contentType: MediaType('image', mimeType != null && mimeType.contains('png') ? 'png' : 'jpeg'),
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = _decodeResponse(response);
        return data['url'];
      } else {
        debugPrint('ApiService: Error uploading file: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('ApiService: Error uploading file: $e');
      return null;
    }
  }
}


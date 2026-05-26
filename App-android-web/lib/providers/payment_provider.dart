import 'package:flutter/material.dart';
import 'package:katari/data/services/api_service.dart';

/// Manages payment state:
/// - PIX generation and payment data
/// - Payment flow for checkout and installments
class PaymentProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _paymentData;
  bool _isLoading = false;

  // ── Getters ────────────────────────────────────
  Map<String, dynamic>? get paymentData => _paymentData;
  bool get isLoading => _isLoading;

  // ── PIX Generation ─────────────────────────────
  /// Generates a PIX payment for the first installment of a new contract.
  Future<void> payFirstInstallment({
    required String installmentId,
    String? idTokenPay,
    required String method,
  }) async {
    if (method == 'PIX') {
      await generatePixForInstallment(installmentId, idTokenPay: idTokenPay);
    } else if (method == 'BOLETO') {
      await generateBoletoForInstallment(installmentId, idTokenPay: idTokenPay);
    } else {
      throw Exception('Método de pagamento não implementado: $method');
    }
  }

  /// Generates PIX for any installment (used by payments screen)
  Future<void> generatePixForInstallment(
    String installmentId, {
    String? idTokenPay,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _apiService.generatePixPayment(
        installmentId,
        idTokenPay: idTokenPay,
      );

      if (result != null && !result.containsKey('error')) {
        _paymentData = {
          'type': 'PIX',
          'installmentId': installmentId,
          'idTokenPay': idTokenPay,
          'paymentId': result['paymentId'],
          'qrCodeBase64': result['qrCode'],
          'copyPasteCode': result['copyPaste'],
          'amount': result['amount'],
          'expirationDate': result['expirationDate'],
          'provider': result['provider'],
          'message': result['message'],
        };
      } else {
        throw Exception(result?['error'] ?? 'Erro ao gerar PIX');
      }
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Generates Boleto for any installment (used by payments screen)
  Future<void> generateBoletoForInstallment(
    String installmentId, {
    String? idTokenPay,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _apiService.generateBoletoPayment(
        installmentId,
        idTokenPay: idTokenPay,
      );

      if (result != null && !result.containsKey('error')) {
        _paymentData = {
          'type': 'BOLETO',
          'installmentId': installmentId,
          'idTokenPay': idTokenPay,
          'paymentId': result['paymentId'],
          'barCode': result['copyPaste'], // Assuming the API returns digitable line in copyPaste field
          'amount': result['amount'],
          'expirationDate': result['expirationDate'],
          'provider': result['provider'],
          'message': result['message'],
        };
      } else {
        throw Exception(result?['error'] ?? 'Erro ao gerar Boleto');
      }
    } catch (e) {
      debugPrint(e.toString());
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Clear ──────────────────────────────────────
  void clearPayment() {
    _paymentData = null;
    notifyListeners();
  }

  void clearAllState() {
    _paymentData = null;
    _isLoading = false;
    notifyListeners();
  }
}

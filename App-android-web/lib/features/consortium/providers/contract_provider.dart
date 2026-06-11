import 'package:flutter/material.dart';
import 'package:katari/features/catalog/models/product.dart';
import 'package:katari/features/consortium/models/active_contract.dart';
import 'package:katari/features/consortium/models/consortium_plan.dart';
import 'package:katari/core/network/api_service.dart';
import 'package:katari/core/services/storage_service.dart';

/// Manages contract/subscription state:
/// - Active contracts, subscription creation
/// - Installment tracking for checkout flow
class ContractProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  List<ActiveContract> _activeContracts = [];
  bool _isLoading = false;
  DateTime? _lastLoadTime; // Cache: prevents hammering the API

  // Cooldown: won't re-fetch from server more than once per 30 seconds
  static const _cacheDuration = Duration(seconds: 30);

  // Checkout flow state
  String? _currentSubscriptionId;
  String? _firstInstallmentId;
  String? _firstInstallmentToken;
  double? _firstInstallmentValue;

  // ── Getters ────────────────────────────────────
  List<ActiveContract> get activeContracts => _activeContracts;
  bool get hasActiveContracts => _activeContracts.isNotEmpty;
  ActiveContract? get activeContract =>
      _activeContracts.isNotEmpty ? _activeContracts.first : null;
  bool get isLoading => _isLoading;
  double get firstInstallmentValue => _firstInstallmentValue ?? 0.0;
  String? get firstInstallmentId => _firstInstallmentId;
  String? get firstInstallmentToken => _firstInstallmentToken;
  String? get currentSubscriptionId => _currentSubscriptionId;

  bool isProductContracted(String productId) {
    return _activeContracts.any((c) => c.product.id == productId);
  }

  // ── Contract Creation ──────────────────────────
  /// Creates a subscription for the given product.
  /// Requires [userId] from AuthProvider, [plan] from ProductProvider,
  /// and optional document URLs from AuthProvider.
  Future<void> contractProduct({
    required Product product,
    required ConsortiumPlan plan,
    required String userId,
    String? docFrontPath,
    String? docBackPath,
    String? selfiePath,
    required Future<void> Function() uploadDocuments,
  }) async {
    if (isProductContracted(product.id)) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Upload documents
      await uploadDocuments();

      // 2. Create subscription
      final result = await _apiService.createSubscription(
        userId: userId,
        planId: plan.id,
        productId: product.id,
        termsAccepted: true,
        documentFrontUrl:
            docFrontPath?.startsWith('http') == true ? docFrontPath : null,
        documentBackUrl:
            docBackPath?.startsWith('http') == true ? docBackPath : null,
        selfieUrl:
            selfiePath?.startsWith('http') == true ? selfiePath : null,
      );

      if (result != null && !result.containsKey('error')) {
        _currentSubscriptionId = result['subscriptionId'];

        // Extract installment value from plan
        if (result['plan'] != null &&
            result['plan']['monthlyInstallment'] != null) {
          final val = result['plan']['monthlyInstallment'];
          if (val is num) {
            _firstInstallmentValue = val.toDouble();
          } else if (val is String) {
            _firstInstallmentValue =
                double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
          }
        }

        if (result['installments'] != null &&
            (result['installments'] as List).isNotEmpty) {
          final installments = result['installments'] as List;

          installments.sort((a, b) {
            final numA = a['number'] is String
                ? int.tryParse(a['number']) ?? 0
                : (a['number'] as int? ?? 0);
            final numB = b['number'] is String
                ? int.tryParse(b['number']) ?? 0
                : (b['number'] as int? ?? 0);
            return numA.compareTo(numB);
          });

          _firstInstallmentId = installments.first['id'];
          _firstInstallmentToken = installments.first['idTokenPay'];

          // Fallback to installment amount
          if (_firstInstallmentValue == null || _firstInstallmentValue == 0) {
            if (installments.first['amount'] != null) {
              final val = installments.first['amount'];
              if (val is num) {
                _firstInstallmentValue = val.toDouble();
              } else if (val is String) {
                _firstInstallmentValue =
                    double.tryParse(val.replaceAll(',', '.')) ?? 0.0;
              }
            }
          }
        }

        // Refresh from server (force: bypass 30s cooldown — we just created a contract)
        await loadUserContracts(userId: userId, force: true);
      } else {
        throw Exception(
            result?['error'] ?? 'Erro desconhecido ao criar contrato');
      }
    } catch (e) {
      debugPrint('Error contracting: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── Load Contracts ─────────────────────────────
  Future<void> loadUserContracts({
    required String userId,
    List<Product>? products,
    bool notifyLoading = true,
    bool force = false, // set true to bypass cooldown (e.g. after contract creation)
  }) async {
    if (userId.isEmpty) return;

    // Throttle: skip API call if last fetch was less than 30 seconds ago
    if (!force && _lastLoadTime != null) {
      final elapsed = DateTime.now().difference(_lastLoadTime!);
      if (elapsed < _cacheDuration) {
        debugPrint('ContractProvider: Skipping load — cache valid (${elapsed.inSeconds}s ago)');
        return;
      }
    }

    if (notifyLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final serverContracts = await _apiService.getUserContracts(userId);
      _lastLoadTime = DateTime.now(); // Update cache timestamp after successful call

      if (serverContracts.isNotEmpty) {
        final parsed = <ActiveContract>[];
        for (final json in serverContracts) {
          try {
            final contract = ActiveContract.fromJson(json);
            // Skip contracts whose product was deleted (id will be empty string)
            if (contract.product.id.isEmpty) {
              debugPrint('ContractProvider: Skipping orphan contract (deleted product)');
              continue;
            }
            parsed.add(contract);
          } catch (e) {
            debugPrint('ContractProvider: Skipping malformed contract: $e');
          }
        }
        _activeContracts = parsed;

        await _storageService.clearActiveContracts();
        for (var contract in _activeContracts) {
          await _saveContractToStorage(contract);
        }
      } else {
        if (products != null) {
          await _loadLocalContracts(products);
        }
      }
    } catch (e) {
      debugPrint('ContractProvider: Error syncing contracts: $e');
      if (products != null) {
        await _loadLocalContracts(products);
      }
    } finally {
      if (notifyLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> checkPaymentStatus() async {
    if (_currentSubscriptionId == null || _firstInstallmentId == null) {
      return false;
    }

    try {
      final installments = await _apiService
          .getSubscriptionInstallments(_currentSubscriptionId!);
      if (installments.isEmpty) return false;

      final installment = installments.firstWhere(
        (i) => i['id'] == _firstInstallmentId,
        orElse: () => <String, dynamic>{},
      );

      if (installment.isNotEmpty && installment['status'] == 'PAID') {
        return true;
      }
    } catch (e) {
      debugPrint('Error checking payment status: $e');
    }
    return false;
  }

  // ── Internal ───────────────────────────────────
  Future<void> _saveContractToStorage(ActiveContract contract) async {
    final contractData = {
      'productId': contract.product.id,
      'productName': contract.product.name,
      'productImageUrl': contract.product.imageUrl,
      'productPrice': contract.product.price,
      'productMonthlyPrice': contract.product.monthlyPrice,
      'motorcycleId': contract.product.id,
      'totalInstallments': contract.totalInstallments,
      'currentInstallment': contract.currentInstallment,
      'nextPaymentAmount': contract.nextPaymentAmount,
      'dueDate': contract.dueDate.toIso8601String(),
      'status': contract.status,
      'contractDate': contract.contractDate.toIso8601String(),
      'groupNumber': contract.groupNumber,
      'quotaNumber': contract.quotaNumber,
      'paidInstallments': contract.paidInstallments.toList(),
    };
    await _storageService.addActiveContract(contractData);
  }

  Future<void> _loadLocalContracts(List<Product> products) async {
    final contractsData = await _storageService.loadActiveContracts();
    if (contractsData.isNotEmpty && products.isNotEmpty) {
      _activeContracts = [];
      for (final data in contractsData) {
        final productId =
            (data['productId'] ?? data['motorcycleId'] ?? data['id']) as String;
        try {
          final matches = products.where((p) => p.id == productId);
          if (matches.isEmpty) continue;
          final product = matches.first;

          Set<int> paid = {};
          if (data['paidInstallments'] != null) {
            paid = (data['paidInstallments'] as List)
                .map((e) => e as int)
                .toSet();
          }

          _activeContracts.add(ActiveContract(
            product: product,
            totalInstallments: data['totalInstallments'],
            currentInstallment: data['currentInstallment'],
            nextPaymentAmount: (data['nextPaymentAmount'] as num).toDouble(),
            dueDate: DateTime.parse(data['dueDate']),
            status: data['status'],
            contractDate: DateTime.parse(data['contractDate']),
            groupNumber: data['groupNumber'],
            quotaNumber: data['quotaNumber'],
            paidInstallments: paid,
          ));
        } catch (e) {
          debugPrint('Error restoring contract: $e');
        }
      }
    }
  }

  // ── Clear ──────────────────────────────────────
  void clearAllState() {
    _activeContracts = [];
    _isLoading = false;
    _currentSubscriptionId = null;
    _firstInstallmentId = null;
    _firstInstallmentToken = null;
    _firstInstallmentValue = null;
    notifyListeners();
  }
}

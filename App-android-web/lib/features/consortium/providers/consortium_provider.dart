import 'package:flutter/material.dart';
import 'package:katari/features/catalog/models/product.dart';
import 'package:katari/features/catalog/models/product_category.dart';
import 'package:katari/features/consortium/models/active_contract.dart';
import 'package:katari/features/consortium/models/consortium_plan.dart';
import 'package:katari/features/auth/providers/auth_provider.dart';
import 'package:katari/features/catalog/providers/product_provider.dart';
import 'package:katari/features/consortium/providers/contract_provider.dart';
import 'package:katari/features/checkout/providers/payment_provider.dart';

/// FACADE — Delegates to the 4 focused providers for backward compatibility.
///
/// Screens can use [ConsortiumProvider] as before, but internally all
/// state is managed by [AuthProvider], [ProductProvider], [ContractProvider],
/// and [PaymentProvider]. New screens should use the focused providers directly.
///
/// This file can be removed once all screens migrate to the new providers.
class ConsortiumProvider with ChangeNotifier {
  final AuthProvider _auth;
  final ProductProvider _product;
  final ContractProvider _contract;
  final PaymentProvider _payment;

  ConsortiumProvider({
    required AuthProvider authProvider,
    required ProductProvider productProvider,
    required ContractProvider contractProvider,
    required PaymentProvider paymentProvider,
  })  : _auth = authProvider,
        _product = productProvider,
        _contract = contractProvider,
        _payment = paymentProvider {
    // Forward change notifications from all sub-providers
    _auth.addListener(_onSubProviderChanged);
    _product.addListener(_onSubProviderChanged);
    _contract.addListener(_onSubProviderChanged);
    _payment.addListener(_onSubProviderChanged);
  }

  void _onSubProviderChanged() => notifyListeners();

  @override
  void dispose() {
    _auth.removeListener(_onSubProviderChanged);
    _product.removeListener(_onSubProviderChanged);
    _contract.removeListener(_onSubProviderChanged);
    _payment.removeListener(_onSubProviderChanged);
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  // AUTH PROVIDER DELEGATES
  // ═══════════════════════════════════════════════
  String get userName => _auth.userName;
  String get userPhotoUrl => _auth.userPhotoUrl;
  String get name => _auth.name;
  set name(String v) => _auth.name = v;
  String get email => _auth.email;
  set email(String v) => _auth.email = v;
  String get cpf => _auth.cpf;
  set cpf(String v) => _auth.cpf = v;
  String get birthDate => _auth.birthDate;
  set birthDate(String v) => _auth.birthDate = v;
  String get phone => _auth.phone;
  set phone(String v) => _auth.phone = v;

  String get cep => _auth.cep;
  String get street => _auth.street;
  String get number => _auth.number;
  String get district => _auth.district;
  String get city => _auth.city;
  String get state => _auth.state;

  String? get docFrontPath => _auth.docFrontPath;
  String? get docBackPath => _auth.docBackPath;
  String? get selfiePath => _auth.selfiePath;

  String get userId => _auth.userId;
  String get userRole => _auth.userRole;

  Future<void> loadUserInfo() => _auth.loadUserInfo();
  Future<void> saveUserInfo(String name, String email) =>
      _auth.saveUserInfo(name, email);
  Future<void> updateUserData({
    required String name,
    required String cpf,
    required String birthDate,
    required String phone,
  }) =>
      _auth.updateUserData(
          name: name, cpf: cpf, birthDate: birthDate, phone: phone);
  Future<void> updateAddressData({
    required String cep,
    required String street,
    required String number,
    required String district,
    required String city,
    required String state,
  }) =>
      _auth.updateAddressData(
          cep: cep,
          street: street,
          number: number,
          district: district,
          city: city,
          state: state);
  void updateDocuments({String? front, String? back, String? selfie}) =>
      _auth.updateDocuments(front: front, back: back, selfie: selfie);
  Future<void> uploadDocuments() => _auth.uploadDocuments();

  // ═══════════════════════════════════════════════
  // PRODUCT PROVIDER DELEGATES
  // ═══════════════════════════════════════════════
  List<Product> get products => _product.products;
  Product? get selectedProduct => _product.selectedProduct;
  ConsortiumPlan? get selectedPlan => _product.selectedPlan;
  bool get isLoading =>
      _product.isLoading || _contract.isLoading || _payment.isLoading;
  String get searchQuery => _product.searchQuery;
  ProductType get selectedCategory => _product.selectedCategory;
  String? get selectedSubCategory => _product.selectedSubCategory;
  List<Product> get filteredProducts => _product.filteredProducts;
  List<Product> get featuredProducts => _product.featuredProducts;
  List<Product> get popularProducts => _product.popularProducts;
  List<Product> get bestOffers => _product.bestOffers;

  Future<void> fetchProducts({bool notifyLoading = true}) =>
      _product.fetchProducts(notifyLoading: notifyLoading);
  void selectProduct(Product product) => _product.selectProduct(product);
  void selectPlan(ConsortiumPlan plan) => _product.selectPlan(plan);
  void updateSearchQuery(String query) => _product.updateSearchQuery(query);
  void clearSearch() => _product.clearSearch();
  void updateCategoryFilter(ProductType category) =>
      _product.updateCategoryFilter(category);
  void updateSubCategoryFilter(String? subCategory) =>
      _product.updateSubCategoryFilter(subCategory);
  void clearFilters() => _product.clearFilters();

  // ═══════════════════════════════════════════════
  // CONTRACT PROVIDER DELEGATES
  // ═══════════════════════════════════════════════
  List<ActiveContract> get activeContracts => _contract.activeContracts;
  bool get hasActiveContracts => _contract.hasActiveContracts;
  ActiveContract? get activeContract => _contract.activeContract;
  double get firstInstallmentValue => _contract.firstInstallmentValue;

  bool isProductContracted(String productId) =>
      _contract.isProductContracted(productId);

  Future<void> contractProduct(Product product) => _contract.contractProduct(
        product: product,
        plan: _product.selectedPlan!,
        userId: _auth.userId,
        docFrontPath: _auth.docFrontPath,
        docBackPath: _auth.docBackPath,
        selfiePath: _auth.selfiePath,
        uploadDocuments: _auth.uploadDocuments,
      );

  Future<void> loadUserContracts({bool notifyLoading = true}) =>
      _contract.loadUserContracts(
        userId: _auth.userId,
        products: _product.products,
        notifyLoading: notifyLoading,
      );

  Future<bool> checkPaymentStatus() => _contract.checkPaymentStatus();

  // ═══════════════════════════════════════════════
  // PAYMENT PROVIDER DELEGATES
  // ═══════════════════════════════════════════════
  Map<String, dynamic>? get paymentData => _payment.paymentData;

  Future<void> payFirstInstallment(String method) =>
      _payment.payFirstInstallment(
        installmentId: _contract.firstInstallmentId!,
        idTokenPay: _contract.firstInstallmentToken,
        method: method,
      );

  Future<void> generatePixForInstallment(String installmentId,
          {String? idTokenPay}) =>
      _payment.generatePixForInstallment(installmentId,
          idTokenPay: idTokenPay);

  Future<void> generateBoletoForInstallment(String installmentId,
          {String? idTokenPay}) =>
      _payment.generateBoletoForInstallment(installmentId,
          idTokenPay: idTokenPay);

  // ═══════════════════════════════════════════════
  // CROSS-CUTTING
  // ═══════════════════════════════════════════════
  void clearSelection() {
    _product.clearSelection();
    _payment.clearPayment();
  }

  void clearAllState() {
    _auth.clearAllState();
    _product.clearAllState();
    _contract.clearAllState();
    _payment.clearAllState();
  }

  /// Optimized loading for Home Screen
  Future<void> loadHomeData() async {
    await _auth.loadUserInfo();
    await _product.fetchProducts(notifyLoading: false);
    await _contract.loadUserContracts(
      userId: _auth.userId,
      products: _product.products,
      notifyLoading: false,
    );
    notifyListeners();
  }
}

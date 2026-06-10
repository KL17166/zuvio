import 'package:flutter/material.dart';
import 'package:katari/features/catalog/models/product.dart';
import 'package:katari/features/catalog/models/product_category.dart';
import 'package:katari/features/consortium/models/consortium_plan.dart';
import 'package:katari/core/network/api_service.dart';

/// Manages product catalog state:
/// - Product list, fetching, search, filters
/// - Product & plan selection
class ProductProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<Product> _products = [];
  Product? _selectedProduct;
  ConsortiumPlan? _selectedPlan;
  bool _isLoading = false;

  // Search / filter
  String _searchQuery = '';
  ProductType _selectedCategory = ProductType.todos;
  String? _selectedSubCategory;

  // ── Getters ────────────────────────────────────
  List<Product> get products => _products;
  Product? get selectedProduct => _selectedProduct;
  ConsortiumPlan? get selectedPlan => _selectedPlan;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  ProductType get selectedCategory => _selectedCategory;
  String? get selectedSubCategory => _selectedSubCategory;

  List<Product> get filteredProducts {
    return _products.where((p) {
      final matchesSearch = p.matchesSearch(_searchQuery);
      final matchesType = p.matchesType(_selectedCategory);
      final matchesSubCat =
          _selectedSubCategory == null || p.category == _selectedSubCategory;
      return matchesSearch && matchesType && matchesSubCat;
    }).toList();
  }

  List<Product> get featuredProducts =>
      _products.where((p) => p.isFeatured).toList();

  List<Product> get popularProducts =>
      _products.where((p) => p.isPopular).toList();

  List<Product> get bestOffers {
    final sorted = List<Product>.from(_products);
    sorted.sort((a, b) => a.monthlyPrice.compareTo(b.monthlyPrice));
    return sorted.take(5).toList();
  }

  // ── Actions ────────────────────────────────────
  Future<void> fetchProducts({bool notifyLoading = true}) async {
    if (notifyLoading) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _products = await _apiService.getProducts();
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (notifyLoading) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void selectProduct(Product product) {
    _selectedProduct = product;
    _selectedPlan = null;
    notifyListeners();
  }

  void selectPlan(ConsortiumPlan plan) {
    _selectedPlan = plan;
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  void updateCategoryFilter(ProductType category) {
    _selectedCategory = category;
    _selectedSubCategory = null;
    notifyListeners();
  }

  void updateSubCategoryFilter(String? subCategory) {
    _selectedSubCategory = subCategory;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedCategory = ProductType.todos;
    _selectedSubCategory = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedProduct = null;
    _selectedPlan = null;
    notifyListeners();
  }

  // ── Clear ──────────────────────────────────────
  void clearAllState() {
    _products = [];
    _selectedProduct = null;
    _selectedPlan = null;
    _isLoading = false;
    _searchQuery = '';
    _selectedCategory = ProductType.todos;
    _selectedSubCategory = null;
    notifyListeners();
  }
}

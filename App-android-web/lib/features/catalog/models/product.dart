import 'package:katari/features/catalog/models/product_category.dart';
import 'package:katari/features/consortium/models/consortium_plan.dart';

class Product {
  final String id;
  final String name;
  final String imageUrl;
  final List<String> imageUrls;
  final double price;
  final bool active;
  final List<ConsortiumPlan> plans;

  // Classification
  final String description;
  final ProductType type;
  final String category; // Sub-category (sport, sedan, gaming, etc.)
  final bool isFeatured;
  final bool isPopular;

  // Universal optional fields
  final String? brand;
  final String? model;
  final int? year;
  final int minDuration;
  final int maxDuration;

  // Flexible specs — JSON with type-specific details
  final Map<String, dynamic> specs;

  Product({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.imageUrls,
    required this.price,
    required this.active,
    required this.plans,
    required this.description,
    required this.type,
    required this.category,
    required this.isFeatured,
    required this.isPopular,
    this.brand,
    this.model,
    this.year,
    required this.minDuration,
    required this.maxDuration,
    this.specs = const {},
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    // Safe parsing helper
    T? safeParse<T>(dynamic value) {
      if (value == null) return null;
      if (value is T) return value;
      if (T == double) {
        if (value is num) return value.toDouble() as T;
        if (value is String) return double.tryParse(value) as T?;
      }
      if (T == int && value is num) return value.toInt() as T;
      if (T == String) return value.toString() as T;
      return null;
    }

    // Parse imageUrls
    var imageUrlsParsed = <String>[];
    if (json['imageUrls'] != null) {
      if (json['imageUrls'] is List) {
        imageUrlsParsed =
            (json['imageUrls'] as List).map((e) => e.toString()).toList();
      } else if (json['imageUrls'] is String) {
        try {
          imageUrlsParsed = [json['imageUrls'].toString()];
        } catch (_) {}
      }
    }

    final String? singleUrl = safeParse<String>(json['imageUrl']);

    // Parse specs
    Map<String, dynamic> specs = {};
    if (json['specs'] != null) {
      if (json['specs'] is Map) {
        specs = Map<String, dynamic>.from(json['specs']);
      }
    }

    // Checking for legacy top-level fields and adding them to specs if missing
    final legacyFields = [
      'displacement',
      'mileage',
      'engineType',
      'power',
      'torque',
      'transmission',
      'frontBrake',
      'rearBrake',
      'weight',
      'fuelCapacity',
      'consumption'
    ];

    for (var key in legacyFields) {
      if (!specs.containsKey(key) && json[key] != null) {
        specs[key] = json[key];
      }
    }

    // Determine type
    final typeStr = safeParse<String>(json['type']) ?? 'MOTO';

    return Product(
      id: safeParse<String>(json['id']) ?? '',
      name: safeParse<String>(json['name']) ?? 'Produto sem nome',
      imageUrl: (singleUrl != null && singleUrl.startsWith('http'))
          ? singleUrl
          : (imageUrlsParsed.isNotEmpty &&
                  imageUrlsParsed[0].startsWith('http'))
              ? imageUrlsParsed[0]
              : 'https://placehold.co/600x400/png?text=Produto',
      imageUrls: imageUrlsParsed,
      price: safeParse<double>(json['price']) ?? 0.0,
      active: safeParse<bool>(json['active']) ?? true,
      plans: (json['plans'] as List?)
              ?.map((e) => ConsortiumPlan.fromJson(e))
              .toList() ??
          [],
      description: safeParse<String>(json['description']) ?? '',
      type: ProductType.fromString(typeStr),
      category: safeParse<String>(json['category']) ?? '',
      isFeatured: safeParse<bool>(json['isFeatured']) ?? false,
      isPopular: safeParse<bool>(json['isPopular']) ?? false,
      brand: safeParse<String>(json['brand']),
      model: safeParse<String>(json['model']),
      year: safeParse<int>(json['year']),
      minDuration: safeParse<int>(json['minDuration']) ?? 0,
      maxDuration: safeParse<int>(json['maxDuration']) ?? 0,
      specs: specs,
    );
  }

  // Helper to get the best monthly price (lowest installment)
  double get monthlyPrice {
    if (plans.isEmpty) return 0.0;
    return plans
        .map((p) => p.monthlyInstallment)
        .reduce((curr, next) => curr < next ? curr : next);
  }

  // UI Helpers
  String get priceLabel => 'Parcelas a partir de';

  String get typeLabel => type.displayName;

  String get typeIcon => type.icon;

  /// Returns the formatted display name for the subcategory
  String get categoryDisplayName => SubCategory.displayNameFor(category);

  /// Returns a subtitle string (e.g. "Honda • 2024" or "Gaming • PC")
  String get subtitle {
    final parts = <String>[];
    if (brand != null && brand!.isNotEmpty) parts.add(brand!);
    if (year != null) parts.add(year.toString());
    if (parts.isEmpty && category.isNotEmpty) parts.add(category);
    return parts.join(' • ');
  }

  /// Returns a list of labeled spec pairs for display
  List<MapEntry<String, String>> get displaySpecs {
    return specs.entries
        .where((e) => e.value != null && e.value.toString().isNotEmpty)
        .map((e) => MapEntry(_formatSpecKey(e.key), e.value.toString()))
        .toList();
  }

  static String _formatSpecKey(String key) {
    // Convert camelCase or snake_case to readable label
    return key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  bool matchesSearch(String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    return name.toLowerCase().contains(lowerQuery) ||
        description.toLowerCase().contains(lowerQuery) ||
        (brand?.toLowerCase().contains(lowerQuery) ?? false);
  }

  bool matchesType(ProductType filterType) {
    return filterType == ProductType.todos || type == filterType;
  }
}

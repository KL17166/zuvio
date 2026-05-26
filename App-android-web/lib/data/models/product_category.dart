/// Product type categories — matches backend `type` field
enum ProductType {
  todos,
  moto,
  carro,
  cartaCredito,
  eletronico,
  imovel,
  servico;

  String get displayName {
    switch (this) {
      case ProductType.todos:
        return 'Todos';
      case ProductType.moto:
        return 'Motos';
      case ProductType.carro:
        return 'Carros';
      case ProductType.cartaCredito:
        return 'Cartas de Crédito';
      case ProductType.eletronico:
        return 'Eletrônicos';
      case ProductType.imovel:
        return 'Imóveis';
      case ProductType.servico:
        return 'Serviços';
    }
  }

  String get icon {
    switch (this) {
      case ProductType.todos:
        return '';
      case ProductType.moto:
        return '';
      case ProductType.carro:
        return '';
      case ProductType.cartaCredito:
        return '';
      case ProductType.eletronico:
        return '';
      case ProductType.imovel:
        return '';
      case ProductType.servico:
        return '';
    }
  }

  /// Maps backend string to enum value
  static ProductType fromString(String value) {
    switch (value.toUpperCase()) {
      case 'MOTO':
        return ProductType.moto;
      case 'CARRO':
        return ProductType.carro;
      case 'CARTA_CREDITO':
        return ProductType.cartaCredito;
      case 'ELETRONICO':
        return ProductType.eletronico;
      case 'IMOVEL':
        return ProductType.imovel;
      case 'SERVICO':
        return ProductType.servico;
      default:
        return ProductType.moto;
    }
  }

  /// Converts enum to backend string
  String toBackendString() {
    switch (this) {
      case ProductType.todos:
        return '';
      case ProductType.moto:
        return 'MOTO';
      case ProductType.carro:
        return 'CARRO';
      case ProductType.cartaCredito:
        return 'CARTA_CREDITO';
      case ProductType.eletronico:
        return 'ELETRONICO';
      case ProductType.imovel:
        return 'IMOVEL';
      case ProductType.servico:
        return 'SERVICO';
    }
  }

  /// Returns the subcategories available for this product type
  List<SubCategory> get subCategories {
    switch (this) {
      case ProductType.todos:
        return [];
      case ProductType.moto:
        return SubCategory.motoCategories;
      case ProductType.carro:
        return SubCategory.carroCategories;
      case ProductType.cartaCredito:
        return SubCategory.cartaCreditoCategories;
      case ProductType.eletronico:
        return SubCategory.eletronicoCategories;
      case ProductType.imovel:
        return SubCategory.imovelCategories;
      case ProductType.servico:
        return SubCategory.servicoCategories;
    }
  }
}

/// Represents a subcategory within a product type.
/// The [key] matches the backend `category` field value.
class SubCategory {
  final String key;
  final String displayName;
  final String icon;

  const SubCategory({
    required this.key,
    required this.displayName,
    this.icon = '',
  });

  // ──────────── MOTO ────────────
  static const List<SubCategory> motoCategories = [
    SubCategory(key: 'sport', displayName: 'Esportiva'),
    SubCategory(key: 'trail', displayName: 'Trail'),
    SubCategory(key: 'custom', displayName: 'Custom'),
    SubCategory(key: 'urbana', displayName: 'Urbana'),
    SubCategory(key: 'scooter', displayName: 'Scooter'),
    SubCategory(key: 'touring', displayName: 'Touring'),
  ];

  // ──────────── CARRO ────────────
  static const List<SubCategory> carroCategories = [
    SubCategory(key: 'sedan', displayName: 'Sedan'),
    SubCategory(key: 'suv', displayName: 'SUV'),
    SubCategory(key: 'hatch', displayName: 'Hatch'),
    SubCategory(key: 'pickup', displayName: 'Pickup'),
    SubCategory(key: 'esportivo', displayName: 'Esportivo'),
    SubCategory(key: 'utilitario', displayName: 'Utilitário'),
  ];

  // ──────────── CARTA DE CRÉDITO ────────────
  static const List<SubCategory> cartaCreditoCategories = [
    SubCategory(key: 'veiculo', displayName: 'Veículo'),
    SubCategory(key: 'imovel', displayName: 'Imóvel'),
    SubCategory(key: 'servicos', displayName: 'Serviços'),
    SubCategory(key: 'livre', displayName: 'Livre'),
  ];

  // ──────────── ELETRÔNICO ────────────
  static const List<SubCategory> eletronicoCategories = [
    SubCategory(key: 'celular', displayName: 'Celular'),
    SubCategory(key: 'notebook', displayName: 'Notebook'),
    SubCategory(key: 'gaming', displayName: 'Gaming'),
    SubCategory(key: 'eletrodomestico', displayName: 'Eletrodoméstico'),
    SubCategory(key: 'tv', displayName: 'TV'),
  ];

  // ──────────── IMÓVEL ────────────
  static const List<SubCategory> imovelCategories = [
    SubCategory(key: 'casa', displayName: 'Casa'),
    SubCategory(key: 'apartamento', displayName: 'Apartamento'),
    SubCategory(key: 'terreno', displayName: 'Terreno'),
    SubCategory(key: 'comercial', displayName: 'Comercial'),
  ];

  // ──────────── SERVIÇO ────────────
  static const List<SubCategory> servicoCategories = [
    SubCategory(key: 'reforma', displayName: 'Reforma'),
    SubCategory(key: 'viagem', displayName: 'Viagem'),
    SubCategory(key: 'educacao', displayName: 'Educação'),
    SubCategory(key: 'saude', displayName: 'Saúde'),
    SubCategory(key: 'festa', displayName: 'Festa'),
  ];

  /// Master lookup: find display name for any category key across all types.
  /// Returns the key capitalized if not found.
  static String displayNameFor(String key) {
    for (final list in [
      motoCategories,
      carroCategories,
      cartaCreditoCategories,
      eletronicoCategories,
      imovelCategories,
      servicoCategories,
    ]) {
      for (final sub in list) {
        if (sub.key == key) return sub.displayName;
      }
    }
    // Fallback: capitalize first letter
    if (key.isEmpty) return '';
    return '${key[0].toUpperCase()}${key.substring(1)}';
  }
}

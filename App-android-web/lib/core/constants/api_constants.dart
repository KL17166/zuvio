class ApiConstants {
  // âœ… API CONFIGURATION (Updated automatically by start_tunnel.ps1)
  static const String _tunnelUrl = 'https://cut-formal-lotus-places.trycloudflare.com';

  static String get baseUrl {
    return _tunnelUrl;
  }

  // Auth
  static const String authRegister = '/api/auth/register';
  static const String authLogin = '/api/auth/login';
  static const String authLogout = '/api/auth/logout';
  static const String authProfile = '/api/auth/profile';

  // Products
  static const String products = '/api/products';

  // Subscriptions (Contratos)
  static const String subscriptions = '/api/subscriptions';

  // Bids (Lances)
  static const String bids = '/api/bids';

  // Payments (Parcelas)
  static const String payments = '/api/payments';
}

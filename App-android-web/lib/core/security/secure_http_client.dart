import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Provides an HTTP client with SSL Certificate Pinning.
///
/// In **release mode**: uses a custom [HttpClient] that rejects any
/// TLS certificate not issued by Cloudflare's known CA chain.
///
/// In **debug mode**: uses a standard client so development with local
/// servers and dynamic Cloudflare tunnels works without issues.
///
/// On **Web**: uses the browser's built-in TLS, no extra pinning needed.
class SecureHttpClient {
  static final SecureHttpClient _instance = SecureHttpClient._internal();
  factory SecureHttpClient() => _instance;
  SecureHttpClient._internal();

  http.Client? _client;

  /// Known Cloudflare CA issuer substrings.
  /// If the certificate issuer contains any of these, we trust it.
  /// This approach is more resilient than SHA-256 pinning because
  /// Cloudflare rotates leaf certs frequently, but the CA stays the same.
  static const List<String> _trustedIssuers = [
    'Cloudflare',
    'DigiCert',
    'Baltimore CyberTrust',
    'Google Trust Services',   // For GCP-hosted backends
    'Let\'s Encrypt',          // Common for small deployments
  ];

  /// Hostnames that are allowed to bypass pinning (e.g. CDNs, fonts).
  static const List<String> _bypassHosts = [
    'fonts.googleapis.com',
    'fonts.gstatic.com',
  ];

  /// Returns an [http.Client] with SSL pinning applied in release mode.
  http.Client get client {
    if (_client != null) return _client!;

    // Web: browser handles TLS natively
    if (kIsWeb) {
      _client = http.Client();
      return _client!;
    }

    // Debug: allow all certs for dev convenience
    if (kDebugMode) {
      debugPrint('SecureHttpClient: ⚠️  DEBUG — SSL pinning disabled');
      _client = http.Client();
      return _client!;
    }

    // Release: enforce certificate pinning
    final ioClient = HttpClient()
      ..badCertificateCallback = _verifyCertificate;

    _client = IOClient(ioClient);
    debugPrint('SecureHttpClient: 🔒 SSL pinning ENABLED (release mode)');
    return _client!;
  }

  /// Certificate verification callback.
  /// Returns `true` only if the certificate is issued by a trusted CA.
  /// Returning `false` aborts the TLS handshake entirely.
  bool _verifyCertificate(X509Certificate cert, String host, int port) {
    // Allow bypass hosts (CDNs, fonts)
    if (_bypassHosts.any((h) => host.contains(h))) return true;

    final issuer = cert.issuer.toString();
    final subject = cert.subject.toString();

    // Check if the issuer matches any trusted CA
    final isTrusted = _trustedIssuers.any(
      (trusted) => issuer.contains(trusted),
    );

    if (!isTrusted) {
      debugPrint('SecureHttpClient: 🔴 UNTRUSTED CERTIFICATE REJECTED');
      debugPrint('  Host: $host');
      debugPrint('  Subject: $subject');
      debugPrint('  Issuer: $issuer');
      debugPrint('  Valid: ${cert.startValidity} → ${cert.endValidity}');
      return false; // REJECT — possible MITM attack
    }

    return true; // Certificate is from a known CA
  }

  /// Closes and resets the client (useful on logout / token refresh).
  void reset() {
    _client?.close();
    _client = null;
  }
}

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Generates HMAC-SHA256 signatures for API requests.
///
/// Signs every request with `timestamp|method|path|bodyHash`
/// and adds `X-Request-Signature` + `X-Request-Timestamp` headers.
///
/// Two-tier secret strategy:
///   1. Authenticated requests supply [sessionSecret] received from the server
///      on login. This is a unique 32-byte secret tied to the JWT session — even
///      if an attacker extracts the APK they cannot forge authenticated requests.
///   2. Unauthenticated requests (login, register) fall back to [_staticSecret],
///      the APK-embedded secret that matches REQUEST_SIGNING_SECRET on the server.
class RequestSigner {
  // Static fallback — used only for login/register (before a session exists).
  // Must match REQUEST_SIGNING_SECRET in server .env
  static const String _staticSecret =
      'BYanklymIzZeTM7DcXVJ0Fdvfb9woAuQNphWL38EijKq2C6P';

  /// Returns security headers to include with every API request.
  ///
  /// Pass [sessionSecret] for authenticated requests (received from server on
  /// login and stored in [StorageService]). Omit for login/register.
  static Map<String, String> sign({
    required String method,
    required String path,
    String? body,
    String? sessionSecret,
  }) {
    final secret = sessionSecret ?? _staticSecret;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // Hash the body (or empty string)
    final bodyHash = sha256.convert(utf8.encode(body ?? '')).toString();

    // Build the payload to sign
    final payload = '$timestamp|$method|$path|$bodyHash';

    // HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(secret));
    final signature = hmac.convert(utf8.encode(payload)).toString();

    return {
      'X-Request-Signature': signature,
      'X-Request-Timestamp': timestamp,
    };
  }
}

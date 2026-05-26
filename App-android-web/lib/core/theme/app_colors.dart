import 'package:flutter/material.dart';

/// Single source of truth for every colour used in the app.
///
/// Static constants are raw hex values.
/// Theme-aware helpers (methods that take a [BuildContext])
/// Theme-aware helpers (methods that take a [BuildContext])
/// return the standard theme values.
abstract final class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFFFF6D00);
  static const Color primaryLight = Color(0xFFFF9E40);

  static const Color secondary      = Color(0xFF263238);
  static const Color secondaryLight = Color(0xFF4F5B62);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success          = Color(0xFF2E7D32);
  static const Color successLight     = Color(0xFF4CAF50);
  static const Color successContainer = Color(0xFFE8F5E9);

  static const Color warning          = Color(0xFFF57F17);
  static const Color warningLight     = Color(0xFFFFB300);
  static const Color warningContainer = Color(0xFFFFF8E1);

  static const Color error          = Color(0xFFD32F2F);
  static const Color errorLight     = Color(0xFFEF5350);
  static const Color errorContainer = Color(0xFFFFEBEE);

  static const Color info          = Color(0xFF0288D1);
  static const Color infoLight     = Color(0xFF29B6F6);
  static const Color infoContainer = Color(0xFFE1F5FE);

  // ── Neutrals ──────────────────────────────────────────────────────────────
  static const Color backgroundLight      = Color(0xFFF5F5F5);
  static const Color surfaceLight         = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight  = Color(0xFFF8F8F8);
  static const Color borderLight          = Color(0xFFE0E0E0);
  static const Color borderStrongLight    = Color(0xFFBDBDBD);
  static const Color onSurfaceLight       = Color(0xFF1A1A1A);
  static const Color onSurfaceMedLight    = Color(0xFF616161);
  static const Color onSurfaceLowLight    = Color(0xFF9E9E9E);

  // ── Theme helpers (legacy wrappers mapping to Light modes) ─────────────────
  static Color background(BuildContext ctx) => backgroundLight;
  static Color surface(BuildContext ctx) => surfaceLight;
  static Color surfaceVariant(BuildContext ctx) => surfaceVariantLight;
  static Color border(BuildContext ctx) => borderLight;
  static Color borderStrong(BuildContext ctx) => borderStrongLight;
  static Color onSurface(BuildContext ctx) => onSurfaceLight;
  static Color onSurfaceMed(BuildContext ctx) => onSurfaceMedLight;
  static Color onSurfaceLow(BuildContext ctx) => onSurfaceLowLight;
  
  static Color successColor(BuildContext ctx) => success;
  static Color successContainerColor(BuildContext ctx) => successContainer;
  static Color errorColor(BuildContext ctx) => error;
  static Color errorContainerColor(BuildContext ctx) => errorContainer;
  static Color warningColor(BuildContext ctx) => warning;
  static Color warningContainerColor(BuildContext ctx) => warningContainer;
  static Color infoColor(BuildContext ctx) => info;
  static Color infoContainerColor(BuildContext ctx) => infoContainer;
}

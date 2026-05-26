import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Centralised typography system.
///
/// Every method that takes a [BuildContext] resolves colours from the active
/// theme, so styles automatically adapt to the app's context.
///
/// Prefer the context-based variants in widget code. Use the static
/// [appBarTitle] / [badge] constants where you don't have a context.
abstract final class AppTextStyles {
  // ── Display ───────────────────────────────────────────────────────────────
  static TextStyle displayLarge(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface(ctx),
        height: 1.2,
      );

  static TextStyle displayMedium(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface(ctx),
        height: 1.2,
      );

  // ── Headings ──────────────────────────────────────────────────────────────
  static TextStyle headingLarge(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface(ctx),
        height: 1.3,
      );

  static TextStyle headingMedium(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface(ctx),
        height: 1.3,
      );

  static TextStyle headingSmall(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface(ctx),
        height: 1.3,
      );

  // ── Subheading ────────────────────────────────────────────────────────────
  static TextStyle subheading(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurfaceMed(ctx),
        height: 1.4,
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  static TextStyle bodyLarge(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.onSurface(ctx),
        height: 1.5,
      );

  static TextStyle bodyMedium(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.onSurface(ctx),
        height: 1.5,
      );

  static TextStyle bodySmall(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.normal,
        color: AppColors.onSurfaceMed(ctx),
        height: 1.5,
      );

  // ── Caption / Label ───────────────────────────────────────────────────────
  static TextStyle caption(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.onSurfaceLow(ctx),
        height: 1.4,
      );

  static TextStyle label(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurfaceMed(ctx),
        letterSpacing: 0.5,
        height: 1.4,
      );

  // ── Button ────────────────────────────────────────────────────────────────
  static TextStyle button({Color color = Colors.white}) => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0.5,
      );

  static TextStyle buttonSmall({Color color = Colors.white}) =>
      GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0.5,
      );

  // ── Price / Financial ─────────────────────────────────────────────────────
  static TextStyle priceLarge(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface(ctx),
        letterSpacing: -0.5,
      );

  static TextStyle priceMedium(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface(ctx),
        letterSpacing: -0.5,
      );

  static TextStyle priceHighlight(BuildContext ctx) => GoogleFonts.outfit(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      );

  // ── Static (no context needed) ────────────────────────────────────────────
  static const TextStyle appBarTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.white,
    letterSpacing: 0.2,
  );

  static const TextStyle appBarTitleAlt = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.secondary,
    letterSpacing: 0.2,
  );

  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: Colors.white,
    letterSpacing: 0.5,
  );
}

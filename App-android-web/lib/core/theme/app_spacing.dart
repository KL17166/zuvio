/// Spacing constants — single source of truth for every gap, padding,
/// border-radius, and fixed dimension used across the app.
///
/// Never use raw numeric literals for spacing or radius in screen/widget code.
/// Always use these tokens.
abstract final class AppSpacing {
  // ── Base scale ────────────────────────────────────────────────────────────
  static const double xs  =  4.0;
  static const double sm  =  8.0;
  static const double md  = 16.0;
  static const double lg  = 24.0;
  static const double xl  = 32.0;
  static const double xxl = 48.0;

  // ── Semantic layout ───────────────────────────────────────────────────────
  static const double screenPadding     = md;   // horizontal page margin
  static const double cardPadding       = md;   // internal card padding
  static const double cardPaddingLarge  = lg;   // large card/form padding
  static const double sectionGap        = lg;   // gap between page sections
  static const double itemGap           = sm;   // gap between list items
  static const double formFieldGap      = md;   // gap between form fields
  static const double inlineGap         = xs;   // tight inline spacing

  // ── Component sizes ───────────────────────────────────────────────────────
  static const double buttonHeight      = 56.0;
  static const double buttonHeightSm    = 44.0;
  static const double iconBoxSize       = 44.0;  // icon container (md padding)
  static const double iconBoxSizeSm     = 36.0;  // small icon container
  static const double avatarRadius      = 48.0;

  // ── Border radii ──────────────────────────────────────────────────────────
  static const double radiusXs   =  4.0;
  static const double radiusSm   =  8.0;
  static const double radiusMd   = 12.0;
  static const double radiusLg   = 16.0;
  static const double radiusXl   = 20.0;
  static const double radiusXxl  = 24.0;
  static const double radiusFull = 9999.0;

  // ── Elevation / border width ──────────────────────────────────────────────
  static const double elevationNone   = 0.0;
  static const double elevationLow    = 1.0;
  static const double elevationMedium = 2.0;
  static const double elevationHigh   = 4.0;
  static const double borderWidth     = 1.0;
  static const double borderWidthFocus = 2.0;
}

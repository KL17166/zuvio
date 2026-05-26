import 'package:flutter/material.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_spacing.dart';

/// Unified card component — surface colour, border radius, and elevation are
/// all sourced from [AppColors] and [AppSpacing] so the card looks correct in
/// both the app's standard aesthetics without any extra configuration.
///
/// Use [onTap] to make the card tappable with a ripple effect.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.elevation = AppSpacing.elevationMedium,
    this.radius = AppSpacing.radiusLg,
    this.borderColor,
    this.color,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double elevation;
  final double radius;
  final Color? borderColor;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = color ?? AppColors.surface(context);
    final effectiveBorderColor = borderColor ?? AppColors.border(context);
    final hasExplicitBorder = borderColor != null;

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(radius),
        border: hasExplicitBorder
            ? Border.all(color: effectiveBorderColor, width: AppSpacing.borderWidth)
            : Border.all(
                color: AppColors.border(context),
                width: AppSpacing.borderWidth,
              ),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: elevation * 4,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// A thin info box used for notices, tips, and status messages.
///
/// Comes in four semantic variants: info, success, warning, error.
enum InfoBoxVariant { info, success, warning, error }

class AppInfoBox extends StatelessWidget {
  const AppInfoBox({
    super.key,
    required this.message,
    this.title,
    this.variant = InfoBoxVariant.info,
    this.icon,
  });

  final String message;
  final String? title;
  final InfoBoxVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, defaultIcon) = switch (variant) {
      InfoBoxVariant.info => (
          AppColors.infoContainerColor(context),
          AppColors.infoColor(context).withValues(alpha: 0.3),
          AppColors.infoColor(context),
          Icons.info_outline,
        ),
      InfoBoxVariant.success => (
          AppColors.successContainerColor(context),
          AppColors.successColor(context).withValues(alpha: 0.3),
          AppColors.successColor(context),
          Icons.check_circle_outline,
        ),
      InfoBoxVariant.warning => (
          AppColors.warningContainerColor(context),
          AppColors.warningColor(context).withValues(alpha: 0.3),
          AppColors.warningColor(context),
          Icons.warning_amber_outlined,
        ),
      InfoBoxVariant.error => (
          AppColors.errorContainerColor(context),
          AppColors.errorColor(context).withValues(alpha: 0.3),
          AppColors.errorColor(context),
          Icons.error_outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  message,
                  style: TextStyle(fontSize: 13, color: fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

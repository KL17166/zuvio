import 'package:flutter/material.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_spacing.dart';
import 'package:katari/core/theme/app_text_styles.dart';

enum AppButtonVariant { primary, secondary, destructive, ghost }

/// Unified button component.
///
/// Use [AppButtonVariant] to select the visual style:
/// - **primary** — solid orange, white text (default CTA)
/// - **secondary** — outlined orange, orange text
/// - **destructive** — solid red, white text (logout, delete)
/// - **ghost** — transparent, coloured text only
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.height = AppSpacing.buttonHeight,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _loaderColor(context),
            ),
          )
        : icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text(label, style: AppTextStyles.button()),
                ],
              )
            : Text(label, style: AppTextStyles.button(color: _textColor(context)));

    final button = SizedBox(
      height: height,
      width: fullWidth ? double.infinity : null,
      child: switch (variant) {
        AppButtonVariant.primary => ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: AppSpacing.elevationNone,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
            child: child,
          ),
        AppButtonVariant.secondary => OutlinedButton(
            onPressed: isLoading ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(
                color: AppColors.primary,
                width: AppSpacing.borderWidth,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  )
                : Text(label,
                    style: AppTextStyles.button(color: AppColors.primary)),
          ),
        AppButtonVariant.destructive => ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: AppSpacing.elevationNone,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
            child: child,
          ),
        AppButtonVariant.ghost => TextButton(
            onPressed: isLoading ? null : onPressed,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  )
                : Text(label,
                    style: AppTextStyles.button(color: AppColors.primary)),
          ),
      },
    );

    return button;
  }

  Color _loaderColor(BuildContext context) => switch (variant) {
        AppButtonVariant.secondary || AppButtonVariant.ghost => AppColors.primary,
        _ => Colors.white,
      };

  Color _textColor(BuildContext context) => switch (variant) {
        AppButtonVariant.secondary || AppButtonVariant.ghost => AppColors.primary,
        AppButtonVariant.destructive => Colors.white,
        _ => Colors.white,
      };
}

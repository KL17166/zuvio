import 'package:flutter/material.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_spacing.dart';
import 'package:katari/shared/widgets/app_button.dart';

/// Standard error-state layout: icon → message → optional retry button.
///
/// Use this wherever an async operation fails and the user should be given
/// the option to retry.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.message = 'Algo deu errado. Tente novamente.',
    this.retryLabel = 'TENTAR NOVAMENTE',
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.errorContainerColor(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 56,
              color: AppColors.errorColor(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Ops! Algo deu errado',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.onSurfaceMed(context),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: retryLabel,
              onPressed: onRetry,
              fullWidth: false,
            ),
          ],
        ],
      ),
    );
  }
}

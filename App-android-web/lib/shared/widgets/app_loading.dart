import 'package:flutter/material.dart';
import 'package:katari/core/theme/app_colors.dart';
import 'package:katari/core/theme/app_spacing.dart';

/// Inline loading spinner — drop this wherever an async operation is running.
///
/// ```dart
/// if (_isLoading) const AppLoadingIndicator()
/// ```
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color ?? AppColors.primary,
      ),
    );
  }
}

/// Full-screen loading overlay — use when the entire screen is loading data.
///
/// ```dart
/// if (_isLoading) const AppLoadingScreen()
/// ```
class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoadingIndicator(size: 48, strokeWidth: 3),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.onSurfaceMed(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading shimmer card — a grey placeholder while card content loads.
class AppShimmerCard extends StatefulWidget {
  const AppShimmerCard({
    super.key,
    this.height = 100,
    this.borderRadius = AppSpacing.radiusLg,
  });

  final double height;
  final double borderRadius;

  @override
  State<AppShimmerCard> createState() => _AppShimmerCardState();
}

class _AppShimmerCardState extends State<AppShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: Color.lerp(
            const Color(0xFFEEEEEE),
            const Color(0xFFF5F5F5),
            _animation.value,
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Modal dialog shown while the app searches for a nearby driver.
///
/// Displays an animated pulsing radar and a working "إلغاء الطلب" button.
/// After a short simulated search the dialog pops with `true` (driver found)
/// so the caller can navigate to the active-trip screen. Cancelling pops with
/// `null`.
class FindingDriverDialog extends StatefulWidget {
  const FindingDriverDialog({super.key});

  @override
  State<FindingDriverDialog> createState() => _FindingDriverDialogState();
}

class _FindingDriverDialogState extends State<FindingDriverDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    // Simulate a driver being found after a few seconds.
    _searchTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => _buildRadar(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('جاري البحث عن سائق', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'يرجى الانتظار حتى نجد لك سائقًا قريبًا',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeightMd,
                child: OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('إلغاء الطلب'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadar() {
    return CustomPaint(
      painter: _RadarPainter(
        progress: _pulse.value,
        color: AppColors.primaryGreen,
      ),
      child: Center(
        child: Icon(
          Icons.directions_car_rounded,
          color: AppColors.primaryGreen,
          size: 40,
        ),
      ),
    );
  }
}

/// Paints a pulsing radar: expanding concentric rings plus a sweeping beam.
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    // Expanding pulse rings.
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxRadius * t;
      final alpha = (1 - t) * 0.5;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(center, radius.clamp(0.0, maxRadius), paint);
    }

    // Radar beam sweep.
    final beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.35);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius - 2),
      progress * 2 * math.pi,
      math.pi / 3,
      false,
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Screen shown while a trip is in progress.
///
/// Shows a live elapsed-time timer, a map placeholder, the driver's info and
/// active Call / Chat actions. The "تمت الرحلة" button moves the passenger to
/// the rating screen.
class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  void _completeTrip() {
    Navigator.pushReplacementNamed(context, '/rating');
  }

  void _callDriver() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('جارٍ الاتصال بالسائق...')));
  }

  void _chatDriver() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('فتح المحادثة مع السائق...')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('الرحلة الحالية'),
        backgroundColor: AppColors.darkBg,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Map placeholder
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  gradient: LinearGradient(
                    colors: [AppColors.cardBg, AppColors.surface],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.map_rounded,
                    size: 96,
                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),

            // Route card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Column(
                children: [
                  _routeRow(
                    Icons.trip_origin_rounded,
                    'موقع الانطلاق',
                    'شارع التسعين، التجمع الخامس',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _routeRow(
                    Icons.location_on_rounded,
                    'الوجهة',
                    'مطار القاهرة الدولي',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Driver card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primaryContainer,
                    child: Icon(Icons.person, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('أحمد محمد', style: AppTextStyles.titleMedium),
                        Text(
                          'Hyundai Elantra · ١٢٣٤ أ ب ج',
                          style: AppTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.star_rounded, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('4.8', style: AppTextStyles.titleSmall),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Trip-in-progress + timer
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.timer_outlined, color: AppColors.primaryGreen),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'الرحلة جارية',
                        style: AppTextStyles.titleSmall?.copyWith(
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _elapsedLabel,
                    style: AppTextStyles.titleLarge?.copyWith(
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Call / Chat
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      icon: Icons.call_rounded,
                      label: 'اتصال',
                      onTap: _callDriver,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.chat_bubble_rounded,
                      label: 'محادثة',
                      onTap: _chatDriver,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Complete trip
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.xl,
              ),
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeightLg,
                child: FilledButton.icon(
                  onPressed: _completeTrip,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    'تمت الرحلة',
                    style: AppTextStyles.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: AppColors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryGreen, size: AppSpacing.iconMd),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primaryGreen, size: AppSpacing.iconMd),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: AppTextStyles.bodyMedium),
          ],
        ),
      ),
    );
  }
}

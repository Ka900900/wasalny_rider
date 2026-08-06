import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/price_formatter.dart';

/// Optional ride context passed to the rating screen from the active trip.
class TripRatingArgs {
  final double? fare;
  final String? driverName;

  const TripRatingArgs({this.fare, this.driverName});
}

/// Post-trip rating screen.
///
/// Provides an interactive 5-star rating, an optional feedback text box and a
/// "إرسال التقييم" button that returns the passenger to the home screen.
class TripRatingScreen extends StatefulWidget {
  const TripRatingScreen({super.key, this.args});

  /// Ride context (fare / driver name) shown at the top, if available.
  final TripRatingArgs? args;

  @override
  State<TripRatingScreen> createState() => _TripRatingScreenState();
}

class _TripRatingScreenState extends State<TripRatingScreen> {
  int _rating = 0;
  final _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  /// Small summary of the trip context (driver + fare), if provided.
  String get _rideSummary {
    final args = widget.args;
    final driver = args?.driverName;
    final fare = args?.fare;
    final parts = <String>[
      if (driver != null && driver.isNotEmpty) 'سائقك: $driver',
      if (fare != null) 'التكلفة: ${formatEGP(fare)}',
    ];
    return parts.join(' · ');
  }

  void _submit() {
    final feedback = _feedbackController.text.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          feedback.isEmpty
              ? 'شكرًا لتقييمك بمقدار $_rating نجوم'
              : 'شكرًا لتقييمك بمقدار $_rating نجوم ومشاركة ملاحظاتك',
        ),
        backgroundColor: AppColors.primaryGreen,
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('تقييم الرحلة'),
        backgroundColor: AppColors.darkBg,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.primaryGreen,
                size: 64,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'كيف كانت رحلتك؟',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'قيّم تجربتك مع السائق',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              if (widget.args != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _rideSummary,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),

              // Interactive star rating
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return IconButton(
                    onPressed: () => setState(() => _rating = star),
                    iconSize: 44,
                    icon: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: star <= _rating
                          ? AppColors.warning
                          : AppColors.textMuted,
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Feedback
              TextField(
                controller: _feedbackController,
                maxLines: 4,
                maxLength: 300,
                decoration: InputDecoration(
                  hintText: 'أخبرنا عن تجربتك (اختياري)',
                  filled: true,
                  fillColor: AppColors.cardBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Submit
              SizedBox(
                height: AppSpacing.buttonHeightLg,
                child: FilledButton.icon(
                  onPressed: _rating == 0 ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    'إرسال التقييم',
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
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Selection returned by [RideOptionsSheet].
typedef RideSelection = ({String type, String payment, double fare});

/// Bottom sheet where the passenger picks a ride type (Economy / VIP),
/// a payment method (Cash / Card) and confirms the request.
///
/// Pops with a [RideSelection] record on confirm, or `null` when dismissed.
class RideOptionsSheet extends StatefulWidget {
  const RideOptionsSheet({super.key, this.destination});

  /// Destination label shown at the top of the sheet.
  final String? destination;

  @override
  State<RideOptionsSheet> createState() => _RideOptionsSheetState();
}

class _RideOptionsSheetState extends State<RideOptionsSheet> {
  String _selectedType = 'economy'; // 'economy' | 'vip'
  String _selectedPayment = 'cash'; // 'cash' | 'card'

  double get _fare => _selectedType == 'vip' ? 75.0 : 40.0;

  void _confirm() {
    Navigator.of(
      context,
    ).pop((type: _selectedType, payment: _selectedPayment, fare: _fare));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXxl),
        ),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'اختر نوع الرحلة',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Destination
            _buildDestinationCard(),
            const SizedBox(height: AppSpacing.xl),

            // Ride type cards
            Row(
              children: [
                Expanded(
                  child: _buildRideCard(
                    type: 'economy',
                    label: 'وصلني توفير',
                    desc: 'حتى 4 ركاب',
                    icon: Icons.directions_car_rounded,
                    fare: 40,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildRideCard(
                    type: 'vip',
                    label: 'وصلني VIP',
                    desc: 'خدمة مميزة',
                    icon: Icons.stars_rounded,
                    fare: 75,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Payment method
            Text('طريقة الدفع', style: AppTextStyles.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _buildPaymentChip(
                    'cash',
                    'كاش',
                    Icons.payments_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildPaymentChip(
                    'card',
                    'بطاقة',
                    Icons.credit_card_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Fare estimate
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('التكلفة التقديرية', style: AppTextStyles.bodyMedium),
                Text(
                  '$_fare جنيه',
                  style: AppTextStyles.titleMedium?.copyWith(
                    color: AppColors.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Confirm button
            SizedBox(
              height: AppSpacing.buttonHeightLg,
              child: FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  'تأكيد الطلب',
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
    );
  }

  Widget _buildDestinationCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded, color: AppColors.primaryGreen),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              widget.destination ?? 'إلى أين تريد الذهاب؟',
              style: AppTextStyles.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideCard({
    required String type,
    required String label,
    required String desc,
    required IconData icon,
    required double fare,
  }) {
    final selected = _selectedType == type;
    return InkWell(
      onTap: () => setState(() => _selectedType = type),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primaryGreen : AppColors.textMuted,
              size: 32,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSmall?.copyWith(
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$fare جنيه',
              style: AppTextStyles.titleMedium?.copyWith(
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentChip(String value, String label, IconData icon) {
    final selected = _selectedPayment == value;
    return InkWell(
      onTap: () => setState(() => _selectedPayment = value),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: AppSpacing.iconMd,
              color: selected ? AppColors.primaryGreen : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTextStyles.bodyMedium?.copyWith(
                color: selected
                    ? AppColors.primaryGreen
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

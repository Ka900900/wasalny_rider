import 'dart:math';

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Selection returned by [RideOptionsSheet].
typedef RideSelection = ({
  String type,
  String payment,
  double fare,
  double pickupLat,
  double pickupLng,
  String pickupAddress,
  double dropoffLat,
  double dropoffLng,
  String dropoffAddress,
});

/// A popular destination the passenger can pick from.
class _PlaceOption {
  final String name;
  final double lat;
  final double lng;

  const _PlaceOption(this.name, this.lat, this.lng);
}

const List<_PlaceOption> _popularPlaces = [
  _PlaceOption('مطار القاهرة الدولي', 30.1219, 31.4056),
  _PlaceOption('وسط البلد (ميدان التحرير)', 30.0444, 31.2357),
  _PlaceOption('مدينة نصر', 30.0561, 31.3209),
  _PlaceOption('التجمع الخامس', 30.0082, 31.4408),
  _PlaceOption('مدينة 6 أكتوبر', 29.9686, 30.9470),
  _PlaceOption('الشيخ زايد', 30.0459, 31.0040),
  _PlaceOption('المعادي', 29.9598, 31.2497),
  _PlaceOption('مصر الجديدة', 30.1007, 31.3408),
];

/// Bottom sheet where the passenger picks a destination, a ride type
/// (Economy / VIP), a payment method (Cash / Card) and confirms the request.
///
/// Pops with a [RideSelection] record on confirm, or `null` when dismissed.
class RideOptionsSheet extends StatefulWidget {
  const RideOptionsSheet({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
  });

  /// Rider's current location (used for the fare estimate).
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;

  @override
  State<RideOptionsSheet> createState() => _RideOptionsSheetState();
}

class _RideOptionsSheetState extends State<RideOptionsSheet> {
  String _selectedType = 'economy'; // 'economy' | 'vip'
  String _selectedPayment = 'cash'; // 'cash' | 'card'
  _PlaceOption? _destination;

  static double _deg2rad(double deg) => deg * (pi / 180);

  /// Approximate distance (km) between pickup and the selected destination
  /// using the Haversine formula. Falls back to 4 km when no destination is
  /// selected yet.
  double get _distanceKm {
    final dest = _destination;
    if (dest == null) return 4.0;
    const earthRadius = 6371.0;
    final dLat = _deg2rad(dest.lat - widget.pickupLat);
    final dLng = _deg2rad(dest.lng - widget.pickupLng);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(widget.pickupLat)) *
            cos(_deg2rad(dest.lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final km = earthRadius * c;
    return km < 1.0 ? 1.0 : km;
  }

  /// Dynamic fare estimate for a given ride type:
  /// economy = 15 EGP base + 5/km, VIP = 30 + 8/km.
  double _fareForType(String type) {
    final km = _distanceKm;
    return type == 'vip'
        ? (30 + 8 * km).roundToDouble()
        : (15 + 5 * km).roundToDouble();
  }

  double get _fare => _fareForType(_selectedType);

  void _confirm() {
    final dest = _destination;
    if (dest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار الوجهة أولاً'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    Navigator.of(context).pop((
      type: _selectedType,
      payment: _selectedPayment,
      fare: _fare,
      pickupLat: widget.pickupLat,
      pickupLng: widget.pickupLng,
      pickupAddress: widget.pickupAddress,
      dropoffLat: dest.lat,
      dropoffLng: dest.lng,
      dropoffAddress: dest.name,
    ));
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

            // Pickup (current location)
            _buildPickupCard(),
            const SizedBox(height: AppSpacing.xl),

            // Destination selector
            Text('اختر الوجهة', style: AppTextStyles.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final place in _popularPlaces) _buildPlaceChip(place),
              ],
            ),
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
                    fare: _fareForType('economy'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildRideCard(
                    type: 'vip',
                    label: 'وصلني VIP',
                    desc: 'خدمة مميزة',
                    icon: Icons.stars_rounded,
                    fare: _fareForType('vip'),
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

  Widget _buildPickupCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.trip_origin_rounded, color: AppColors.primaryGreen),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'موقع الانطلاق: ${widget.pickupAddress}',
              style: AppTextStyles.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceChip(_PlaceOption place) {
    final selected = _destination?.name == place.name;
    return InkWell(
      onTap: () => setState(() => _destination = place),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_rounded,
              size: AppSpacing.iconSm,
              color: selected ? AppColors.primaryGreen : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              place.name,
              style: AppTextStyles.labelSmall?.copyWith(
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

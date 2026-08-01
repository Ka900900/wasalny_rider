import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/places_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

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

/// Bottom sheet where the passenger searches for a real destination (via
/// Nominatim / OpenStreetMap), picks a ride type (Economy / Comfort /
/// Premium), a payment method (Cash / Card) and confirms the request.
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
  String _selectedType = 'economy'; // 'economy' | 'comfort' | 'premium'
  String _selectedPayment = 'cash'; // 'cash' | 'card'
  PlaceResult? _destination;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  bool _searching = false;
  List<PlaceResult> _results = const [];

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

  /// Dynamic fare estimate (EGP) for a given ride type.
  ///
  /// Mirrors the backend pricing (~7 EGP/km in normal hours, 15 in peak)
  /// so the estimate stays close to the final price:
  /// economy = 7/km, comfort = 9/km, premium = 13/km.
  double _fareForType(String type) {
    final km = _distanceKm;
    final ratePerKm = switch (type) {
      'comfort' => 9.0,
      'premium' => 13.0,
      _ => 7.0, // 'economy'
    };
    return (ratePerKm * km).roundToDouble();
  }

  double get _fare => _fareForType(_selectedType);

  /// Debounced (450 ms) real search against Nominatim while the user types.
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searching = false;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await PlacesService.instance.search(q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = results;
      });
      logInfo('RideOptionsSheet', 'found ${results.length} places for "$q"');
    });
  }

  void _selectDestination(PlaceResult place) {
    setState(() {
      _destination = place;
      _results = const [];
      _searchController.text = place.displayName;
    });
    _searchFocus.unfocus();
  }

  void _confirm() {
    final dest = _destination;
    if (dest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار وجهة من نتائج البحث أولاً'),
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
      dropoffAddress: dest.displayName,
    ));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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
        bottom:
            MediaQuery.of(context).padding.bottom +
            MediaQuery.of(context).viewInsets.bottom +
            AppSpacing.xl,
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

            // Destination search — real places via Nominatim
            Text('إلى أين تريد الذهاب؟', style: AppTextStyles.titleMedium),
            const SizedBox(height: AppSpacing.md),
            _buildSearchField(),
            if (_searching || _results.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _buildSearchResults(),
            ],
            const SizedBox(height: AppSpacing.xl),

            // Ride type cards — Economy / Comfort / Premium, matching the
            // backend's allowed values. The family/xl tier is intentionally
            // not shown to riders.
            Row(
              children: [
                Expanded(
                  child: _buildRideCard(
                    type: 'economy',
                    label: 'وصلني توفير',
                    desc: 'اقتصادي',
                    icon: Icons.directions_car_rounded,
                    fare: _fareForType('economy'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _buildRideCard(
                    type: 'comfort',
                    label: 'وصلني مريح',
                    desc: 'راحة أعلى',
                    icon: Icons.airline_seat_recline_normal_rounded,
                    fare: _fareForType('comfort'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _buildRideCard(
                    type: 'premium',
                    label: 'وصلني VIP',
                    desc: 'ممتاز',
                    icon: Icons.stars_rounded,
                    fare: _fareForType('premium'),
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

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'ابحث عن وجهة...',
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.primaryGreen,
        ),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: SizedBox(
                  width: AppSpacing.iconSm,
                  height: AppSpacing.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : (_searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null),
        filled: true,
        fillColor: AppColors.cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      children: [for (final place in _results) _buildResultTile(place)],
    );
  }

  Widget _buildResultTile(PlaceResult place) {
    final selected = _destination?.displayName == place.displayName;
    return InkWell(
      onTap: () => _selectDestination(place),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryContainer : AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.place_rounded,
              size: AppSpacing.iconSm,
              color: selected ? AppColors.primaryGreen : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                place.displayName,
                style: AppTextStyles.bodySmall?.copyWith(
                  color: selected
                      ? AppColors.primaryGreen
                      : AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
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
              size: 28,
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

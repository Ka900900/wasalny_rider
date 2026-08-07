import 'dart:async';

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/places_service.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/utils/price_formatter.dart';

/// Selection returned by [RideOptionsSheet].
typedef RideSelection = ({
  String type,
  String payment,
  double? fare,
  double pickupLat,
  double pickupLng,
  String pickupAddress,
  double dropoffLat,
  double dropoffLng,
  String dropoffAddress,

  /// `true` عند الضغط على «عرض على الخريطة» — تُفتح الخريطة الرئيسية لمعاينة
  /// المسار (نقطة الالتقاط → الوجهة) بدلاً من تأكيد الطلب.
  bool showOnMap,
});

/// Bottom sheet where the passenger searches for a real destination (via
/// Nominatim / OpenStreetMap), picks a ride type (Economy / Comfort /
/// Premium / Motorcycle / Scooter), a payment method (Cash / Card) and
/// confirms the request.
///
/// Pops with a [RideSelection] record on confirm, or `null` when dismissed.
class RideOptionsSheet extends StatefulWidget {
  const RideOptionsSheet({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    this.initialDestination,
    this.initialType = 'economy',
    this.initialPayment = 'cash',
  });

  /// Rider's current location (used for the fare estimate).
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;

  /// عند العودة من معاينة الخريطة: وجهة محفوظة تُستعاد مع نوع الرحلة وطريقة
  /// الدفع حتى لا يضيع اختيار المستخدم عند متابعة تأكيد الطلب.
  final PlaceResult? initialDestination;
  final String initialType;
  final String initialPayment;

  @override
  State<RideOptionsSheet> createState() => _RideOptionsSheetState();
}

class _RideOptionsSheetState extends State<RideOptionsSheet> {
  String _selectedType =
      'economy'; // 'economy' | 'comfort' | 'premium' | 'motorcycle' | 'scooter'
  String _selectedPayment = 'cash'; // 'cash' | 'card'
  PlaceResult? _destination;

  /// تتابع يزداد عند كل اختيار وجهة جديدة. يُستخدم لتجاهل نتائج جلب أسعار
  /// قديمة (لوجهة سابقة) حتى لا نعرض سعراً لوجهة غير الحالية.
  int _destinationSeq = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  bool _searching = false;
  List<PlaceResult> _results = const [];
  // Fare responses per ride type returned by the backend.
  final Map<String, Map<String, dynamic>?> _fareResponses = {};
  final Map<String, bool> _loadingFare = {};

  /// أنواع الرحلات التي فشل جلب سعرها من الخادم (لا نعرض سعراً وهمياً).
  final Set<String> _fareFailed = {};

  /// التكلفة التقديرية (بالجنيه) لنوع رحلة معيّن من الـ Backend، أو `null`
  /// إذا لم تتوفر بعد أو فشل جلبها. لا نستخدم أي سعر محلي وهمي.
  double? _getDisplayedFare(String type) {
    final resp = _fareResponses[type];
    if (resp == null) return null;
    final fp = resp['finalPrice'];
    if (fp is num) return fp.toDouble();
    if (fp is String && fp.trim().isNotEmpty) {
      return double.tryParse(fp.trim());
    }
    return null;
  }

  Future<void> _fetchFareForType(String type) async {
    // Avoid duplicate simultaneous fetches
    if (_loadingFare[type] == true) return;
    // نلتقط رقم الوجهة الحالية: إذا تغيّرت الوجهة أثناء الجلب نتجاهل النتيجة
    // القديمة (لا نعرض سعراً لوجهة سابقة).
    final seq = _destinationSeq;
    setState(() => _loadingFare[type] = true);
    try {
      final resp = await ApiService.instance.getRideFare(
        originLat: widget.pickupLat,
        originLng: widget.pickupLng,
        destLat: _destination!.lat,
        destLng: _destination!.lng,
        rideType: type,
      );
      if (!mounted || seq != _destinationSeq) return;
      setState(() {
        _fareResponses[type] = resp;
        _fareFailed.remove(type);
      });
    } catch (e) {
      logWarning('RideOptionsSheet', 'getRideFare failed for $type: $e');
      if (!mounted || seq != _destinationSeq) return;
      // لا نعرض سعراً وهمياً عند فشل الشبكة — نعرض «غير متاح» فقط.
      setState(() {
        _fareResponses[type] = null;
        _fareFailed.add(type);
      });
    } finally {
      // لا نمسح حالة تحميل جلبٍ أحدث لنفس النوع بعد تغيير الوجهة.
      if (mounted && seq == _destinationSeq) {
        setState(() => _loadingFare[type] = false);
      }
    }
  }

  Future<void> _fetchAllFares() async {
    final types = ['economy', 'comfort', 'premium', 'motorcycle', 'scooter'];
    final futures = <Future>[];
    for (final t in types) {
      futures.add(_fetchFareForType(t));
    }
    await Future.wait(futures);
  }

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
      // صفّر حالة الأسعار من الوجهة السابقة فور اختيار وجهة جديدة — لا نعرض
      // أسعاراً قديمة أثناء جلب أسعار الوجهة الحالية من الـ Backend.
      _destinationSeq++;
      _fareResponses.clear();
      _fareFailed.clear();
      _loadingFare.clear();
    });
    _searchFocus.unfocus();
    // Fetch fares for all available types when a destination is selected
    _fetchAllFares();
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
    // إذا كان تقدير السعر لا يزال قيد الجلب، نطلب الانتظار بدلاً من تأكيد
    // طلب بسعر غير معروف (لن نعرض أبداً سعراً وهمياً).
    if (_loadingFare[_selectedType] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جارٍ حساب التكلفة، انتظر قليلاً...'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final displayedFare = _getDisplayedFare(_selectedType);
    Navigator.of(context).pop((
      type: _selectedType,
      payment: _selectedPayment,
      fare: displayedFare,
      pickupLat: widget.pickupLat,
      pickupLng: widget.pickupLng,
      pickupAddress: widget.pickupAddress,
      dropoffLat: dest.lat,
      dropoffLng: dest.lng,
      dropoffAddress: dest.displayName,
      showOnMap: false,
    ));
  }

  /// يغلق الشيت ويفتح الخريطة الرئيسية لمعاينة المسار (نقطة الالتقاط → الوجهة)
  /// دون تأكيد الطلب. الشاشة الرئيسية تحفظ الوجهة/النوع/الدفع للعودة لاحقاً.
  void _showOnMap() {
    final dest = _destination;
    if (dest == null) return;
    Navigator.of(context).pop((
      type: _selectedType,
      payment: _selectedPayment,
      fare: _getDisplayedFare(_selectedType),
      pickupLat: widget.pickupLat,
      pickupLng: widget.pickupLng,
      pickupAddress: widget.pickupAddress,
      dropoffLat: dest.lat,
      dropoffLng: dest.lng,
      dropoffAddress: dest.displayName,
      showOnMap: true,
    ));
  }

  @override
  void initState() {
    super.initState();
    // عند العودة من معاينة الخريطة (وجهة محفوظة): استعد الاختيار وأعد جلب
    // الأسعار من الـ Backend فقط (لا نعرض سعراً وهمياً أبداً).
    final initial = widget.initialDestination;
    if (initial != null) {
      _destination = initial;
      _searchController.text = initial.displayName;
      _selectedType = widget.initialType;
      _selectedPayment = widget.initialPayment;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchAllFares();
      });
    }
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

            // Ride type cards — Economy / Comfort / Premium / Motorcycle /
            // Scooter, matching the backend's allowed values. The family/xl
            // tier is intentionally not shown to riders.
            Row(
              children: [
                Expanded(
                  child: _buildRideCard(
                    type: 'economy',
                    label: 'وصلني توفير',
                    desc: 'اقتصادي',
                    icon: Icons.directions_car_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _buildRideCard(
                    type: 'comfort',
                    label: 'وصلني مريح',
                    desc: 'راحة أعلى',
                    icon: Icons.airline_seat_recline_normal_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _buildRideCard(
                    type: 'premium',
                    label: 'وصلني VIP',
                    desc: 'ممتاز',
                    icon: Icons.stars_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Motorcycle / Scooter — cheaper two-wheeler options.
            Row(
              children: [
                Expanded(
                  child: _buildRideCard(
                    type: 'motorcycle',
                    label: 'موتوسيكل',
                    desc: 'أسرع وأوفر',
                    icon: Icons.two_wheeler_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _buildRideCard(
                    type: 'scooter',
                    label: 'سكوتر',
                    desc: 'الأوفر',
                    icon: Icons.electric_scooter_rounded,
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

            // Fare estimate (من الـ Backend فقط)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('التكلفة التقديرية', style: AppTextStyles.bodyMedium),
                _buildEstimateLabel(),
              ],
            ),
            // معاينة المسار على الخريطة الرئيسية (تظهر بعد اختيار الوجهة فقط)
            if (_destination != null) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: AppSpacing.buttonHeightMd,
                child: OutlinedButton.icon(
                  onPressed: _showOnMap,
                  icon: const Icon(Icons.route_rounded),
                  label: const Text('عرض على الخريطة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
              ),
            ],
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

  /// عنوان «التكلفة التقديرية» للنوع المحدد: قبل اختيار الوجهة نطلب اختيارها
  /// أولاً بدلاً من عرض أي رقم. بعد اختيارها نعرض سعر الـ Backend أو حالة
  /// الجلب/الفشل.
  Widget _buildEstimateLabel() {
    if (_destination == null) {
      return Text(
        'اختر الوجهة أولاً',
        style: AppTextStyles.bodySmall?.copyWith(color: AppColors.textMuted),
      );
    }
    return _buildFareLabel(_selectedType);
  }

  /// نص السعر لنوع رحلة معيّن: يعرض سعر الـ Backend، أو مؤشر تحميل، أو
  /// «غير متاح» عند فشل الشبكة، أو «—» قبل توفر البيانات. لا نعرض سعراً
  /// وهمياً أبداً.
  Widget _buildFareLabel(String type) {
    if (_loadingFare[type] == true && _fareResponses[type] == null) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final fare = _getDisplayedFare(type);
    if (fare != null) {
      return Text(
        formatEGP(fare),
        style: AppTextStyles.titleMedium?.copyWith(
          color: AppColors.primaryGreen,
        ),
      );
    }
    return Text(
      _fareFailed.contains(type) ? 'غير متاح' : '—',
      style: AppTextStyles.titleMedium?.copyWith(color: AppColors.textMuted),
    );
  }

  Widget _buildRideCard({
    required String type,
    required String label,
    required String desc,
    required IconData icon,
  }) {
    final selected = _selectedType == type;
    return InkWell(
      onTap: () {
        setState(() => _selectedType = type);
        if (_destination != null && _fareResponses[type] == null) {
          _fetchFareForType(type);
        }
      },
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
            _buildFareLabel(type),
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

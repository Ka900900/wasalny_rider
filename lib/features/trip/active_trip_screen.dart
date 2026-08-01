import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart' as osm;
import 'package:url_launcher/url_launcher.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/features/chat/chat_screen.dart';
import 'package:wasalny_rider/features/trip/trip_rating_screen.dart';

/// Arguments passed from the ride-options flow to [ActiveTripScreen].
class ActiveTripArgs {
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;

  /// Backend-compatible ride type: `'economy'` | `'comfort'` | `'premium'`.
  final String rideType;

  /// Payment method: `'cash'` (كاش) or `'card'` (بطاقة).
  final String payment;

  final double fare;

  /// Backend ride id — used as the trip chat room.
  final String? rideId;

  /// Captain (driver) id — used as the chat receiver.
  final String? driverId;

  /// Captain display name.
  final String? driverName;

  /// Captain phone number (used by the call button via `tel:`).
  final String? driverPhone;

  /// Captain car description (model / plate).
  final String? driverCar;

  const ActiveTripArgs({
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddress,
    required this.rideType,
    required this.payment,
    required this.fare,
    this.rideId,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.driverCar,
  });
}

/// Screen shown while a trip is in progress.
///
/// Renders a live OSM map with the rider's pickup point, the drop-off point,
/// a drawn route and a simulated driver that drives along the route, plus a
/// live elapsed-time timer, driver info and Call / Chat actions. The
/// "تمت الرحلة" button moves the passenger to the rating screen.
class ActiveTripScreen extends StatefulWidget {
  const ActiveTripScreen({super.key, this.args});

  /// Ride data passed from the ride-options flow. When `null`, a sample
  /// Cairo trip is used (e.g. when the screen is opened directly).
  final ActiveTripArgs? args;

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  static const ActiveTripArgs _defaultArgs = ActiveTripArgs(
    pickupLat: 30.0444,
    pickupLng: 31.2357,
    pickupAddress: 'موقعك الحالي — ميدان التحرير',
    dropoffLat: 30.1219,
    dropoffLng: 31.4056,
    dropoffAddress: 'مطار القاهرة الدولي',
    rideType: 'economy',
    payment: 'cash',
    fare: 40,
    driverName: 'أحمد محمد',
    driverCar: 'Hyundai Elantra · ١٢٣٤ أ ب ج',
  );

  /// Captain name from the real ride data (falls back to a neutral label).
  String get _driverName =>
      _args.driverName?.isNotEmpty == true ? _args.driverName! : 'الكابتن';

  /// Captain car description (falls back when no data is available).
  String get _driverCar => _args.driverCar?.isNotEmpty == true
      ? _args.driverCar!
      : 'لا توجد بيانات السيارة';

  /// Whether a usable captain phone number is available for calling.
  bool get _hasDriverPhone =>
      _args.driverPhone != null && _args.driverPhone!.trim().isNotEmpty;

  /// Whether the ride + captain ids are available for the trip chat.
  bool get _canChat =>
      (_args.rideId != null && _args.rideId!.isNotEmpty) &&
      (_args.driverId != null && _args.driverId!.isNotEmpty);

  /// Arabic label shown for the backend ride type.
  String get _rideTypeLabel => switch (_args.rideType) {
    'comfort' => 'وصلني مريح',
    'premium' => 'وصلني VIP',
    _ => 'وصلني توفير', // 'economy'
  };

  late final ActiveTripArgs _args;
  late final osm.MapController mapController;

  Timer? _timer;
  int _elapsedSeconds = 0;

  bool _mapReady = false;

  // Simulated driver animation
  Timer? _driverTimer;
  List<osm.GeoPoint> _route = const [];
  int _routeIndex = 0;
  osm.GeoPoint? _driverPoint;

  @override
  void initState() {
    super.initState();
    _args = widget.args ?? _defaultArgs;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    mapController = osm.MapController.withPosition(
      initPosition: osm.GeoPoint(
        latitude: _args.pickupLat,
        longitude: _args.pickupLng,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _driverTimer?.cancel();
    mapController.dispose();
    super.dispose();
  }

  String get _elapsedLabel {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _onMapReady(bool isReady) async {
    if (!isReady) return;
    setState(() => _mapReady = true);
    await _buildRoute();
  }

  /// Adds the pickup / drop-off markers, draws an interpolated route and
  /// starts the simulated driver animation.
  Future<void> _buildRoute() async {
    try {
      // Rider marker at the pickup point
      await mapController.addMarker(
        osm.GeoPoint(latitude: _args.pickupLat, longitude: _args.pickupLng),
        markerIcon: const osm.MarkerIcon(
          icon: Icon(
            Icons.person_pin_circle_rounded,
            color: AppColors.primaryGreen,
            size: 42,
          ),
        ),
      );

      // Drop-off marker
      await mapController.addMarker(
        osm.GeoPoint(latitude: _args.dropoffLat, longitude: _args.dropoffLng),
        markerIcon: const osm.MarkerIcon(
          icon: Icon(
            Icons.location_on_rounded,
            color: AppColors.primary,
            size: 42,
          ),
        ),
      );

      // Interpolated path pickup → drop-off
      _route = _interpolate(
        osm.GeoPoint(latitude: _args.pickupLat, longitude: _args.pickupLng),
        osm.GeoPoint(latitude: _args.dropoffLat, longitude: _args.dropoffLng),
      );
      await mapController.drawRoadManually(
        _route,
        osm.RoadOption(roadColor: AppColors.primaryGreen, roadWidth: 5),
      );

      // Driver marker starts a little off the pickup point
      final driverStart = osm.GeoPoint(
        latitude: _args.pickupLat + 0.0012,
        longitude: _args.pickupLng + 0.0012,
      );
      await mapController.addMarker(
        driverStart,
        markerIcon: const osm.MarkerIcon(
          icon: Icon(
            Icons.local_taxi_rounded,
            color: AppColors.primary,
            size: 38,
          ),
        ),
      );
      _driverPoint = driverStart;
      _routeIndex = 0;

      _startDriverAnimation();
    } catch (e) {
      logError('ActiveTripScreen', 'Failed to build route: $e', e);
    }
  }

  /// Smoothly moves the driver marker along the interpolated route.
  void _startDriverAnimation() {
    _driverTimer?.cancel();
    _driverTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted || _route.isEmpty || _driverPoint == null) return;
      if (_routeIndex >= _route.length) {
        _driverTimer?.cancel();
        return;
      }
      final next = _route[_routeIndex++];
      mapController.changeLocationMarker(
        oldLocation: _driverPoint!,
        newLocation: next,
      );
      _driverPoint = next;
    });
  }

  /// Builds a gentle curved path between two points so the simulated route
  /// doesn't look like a rigid straight line.
  List<osm.GeoPoint> _interpolate(osm.GeoPoint a, osm.GeoPoint b) {
    const segments = 30;
    final points = <osm.GeoPoint>[];
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final bulge = sin(t * pi) * 0.0025;
      points.add(
        osm.GeoPoint(
          latitude: a.latitude + (b.latitude - a.latitude) * t + bulge,
          longitude:
              a.longitude + (b.longitude - a.longitude) * t - bulge * 0.8,
        ),
      );
    }
    return points;
  }

  void _completeTrip() {
    Navigator.pushReplacementNamed(
      context,
      '/rating',
      arguments: TripRatingArgs(fare: _args.fare, driverName: _driverName),
    );
  }

  Future<void> _callDriver() async {
    final phone = _args.driverPhone;
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم هاتف الكابتن غير متاح حالياً'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone.trim());
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح تطبيق الاتصال')),
        );
      }
    } catch (e) {
      logError('ActiveTripScreen', 'launchUrl tel failed: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر فتح تطبيق الاتصال')),
        );
      }
    }
  }

  void _chatDriver() {
    final tripId = _args.rideId;
    final driverId = _args.driverId;
    if (tripId == null ||
        tripId.isEmpty ||
        driverId == null ||
        driverId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('بيانات الكابتن غير متاحة للمحادثة حالياً'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          tripId: tripId,
          receiverId: driverId,
          receiverName: _driverName,
        ),
      ),
    );
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
            // Live OSM map with route + simulated driver
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: osm.OSMFlutter(
                          controller: mapController,
                          osmOption: osm.OSMOption(
                            userTrackingOption:
                                const osm.UserTrackingOption.withoutUserPosition(
                                  enableTracking: false,
                                ),
                            zoomOption: const osm.ZoomOption(
                              initZoom: 13,
                              minZoomLevel: 3,
                              maxZoomLevel: 19,
                              stepZoom: 1,
                            ),
                          ),
                          onMapIsReady: _onMapReady,
                        ),
                      ),
                      if (!_mapReady)
                        const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                    ],
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
                    _args.pickupAddress,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _routeRow(
                    Icons.location_on_rounded,
                    'الوجهة',
                    _args.dropoffAddress,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Ride summary (type / payment / fare)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  _infoChip(Icons.directions_car_rounded, _rideTypeLabel),
                  const SizedBox(width: AppSpacing.sm),
                  _infoChip(
                    Icons.payments_rounded,
                    _args.payment == 'cash' ? 'كاش' : 'بطاقة',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _infoChip(
                    Icons.price_check_rounded,
                    '${_args.fare.round()} جنيه',
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
                        Text(_driverName, style: AppTextStyles.titleMedium),
                        Text(_driverCar, style: AppTextStyles.bodySmall),
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
                      // No phone number → greyed out; tapping shows a message.
                      enabled: _hasDriverPhone,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _actionButton(
                      icon: Icons.chat_bubble_rounded,
                      label: 'محادثة',
                      onTap: _chatDriver,
                      enabled: _canChat,
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

  Widget _infoChip(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primaryGreen, size: AppSpacing.iconMd),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    // A disabled (greyed) button still responds to taps so it can show a
    // clear message explaining why the action is unavailable.
    final foreground = enabled ? AppColors.primaryGreen : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: enabled
                ? AppColors.border
                : AppColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: AppSpacing.iconMd),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTextStyles.bodyMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

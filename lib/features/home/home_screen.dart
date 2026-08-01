import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart' as osm;
import 'package:geolocator/geolocator.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/services/places_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/features/home/finding_driver_dialog.dart';
import 'package:wasalny_rider/features/home/ride_options_sheet.dart';
import 'package:wasalny_rider/features/trip/active_trip_screen.dart';

/// Main rider home screen with an interactive map and a "Request Ride" button.
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  late final osm.MapController mapController;
  bool _mapReady = false;
  bool _locationGranted = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  osm.GeoPoint? _riderMarkerPoint;
  Timer? _mapReadyFallbackTimer;
  Timer? _locationPollTimer;

  /// Whether the map camera should keep following the rider in real time.
  bool _followUser = true;

  /// Timestamp of the last programmatic camera move, used to ignore the
  /// region-change events that our own follow/recenter moves trigger.
  DateTime? _lastProgrammaticMove;

  /// Guards against overlapping addMarker/changeLocationMarker calls — the
  /// position stream and the web poll timer can both fire concurrently.
  bool _updatingMarker = false;

  /// Timestamp of the last logged marker failure, used to throttle repeated
  /// console errors on web (Leaflet DOM not ready / marker removed).
  DateTime? _lastMarkerErrorLogged;

  /// Reverse-geocoded human-readable address of the rider's current
  /// location, updated (throttled) whenever the position moves.
  String _pickupAddress = '';
  DateTime? _lastReverseGeocodeAt;
  osm.GeoPoint? _lastReverseGeocodePoint;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    mapController = osm.MapController.withPosition(
      initPosition: osm.GeoPoint(
        latitude: 30.0444,
        longitude: 31.2357,
      ), // Cairo
    );
    mapController.listenerRegionIsChanging.addListener(_onRegionChanged);
    _startMapReadyFallback();
  }

  @override
  void dispose() {
    _mapReadyFallbackTimer?.cancel();
    _locationPollTimer?.cancel();
    _positionStream?.cancel();
    mapController.listenerRegionIsChanging.removeListener(_onRegionChanged);
    mapController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final granted = await Geolocator.requestPermission();
        if (granted == LocationPermission.denied ||
            granted == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تطبيق Waslny يحتاج إلى صلاحية الموقع لعرض الخريطة',
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
          return;
        }
      }

      _locationGranted = true;
      await _getCurrentLocation();
      _startLocationUpdates();
    } catch (e) {
      // Geolocation APIs can throw on web (e.g. browser blocks geolocation) —
      // don't let that crash the home screen.
      logError('RiderHomeScreen', 'Location permission error: $e', e);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      var position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      // Best-effort refinement: right after launch the first fix is often
      // coarse, so re-request until it's accurate (or we give up trying).
      for (var attempt = 0; attempt < 2; attempt++) {
        if (position.accuracy <= 50) break;
        try {
          final refined = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
          if (refined.accuracy < position.accuracy) {
            position = refined;
          } else {
            break;
          }
        } catch (_) {
          break; // keep the current fix if refinement fails
        }
      }
      logInfo(
        'RiderHomeScreen',
        '📍 Current location: ${position.latitude}, ${position.longitude} '
            '(accuracy: ${position.accuracy.toStringAsFixed(0)}m)',
      );

      // Updates the marker and (in follow mode) re-centers the camera.
      await _updateRiderLocation(position);
    } catch (e) {
      logError('RiderHomeScreen', 'Failed to get location: $e', e);
    }
  }

  /// Adds / moves the rider marker on the map for the given [position].
  ///
  /// Protected against the web (Leaflet) failure mode where the map DOM isn't
  /// ready yet or the marker element is gone (e.g. during rebuild/dispose):
  /// - Marker calls are skipped unless the map is ready and the widget is
  ///   mounted.
  /// - Concurrent updates (position stream + web poll timer) are serialised
  ///   with [_updatingMarker] so addMarker/changeLocationMarker never overlap.
  /// - On failure [_riderMarkerPoint] is reset to null so the next attempt
  ///   re-adds a fresh marker instead of calling changeLocationMarker against
  ///   a stale point that no longer exists in the DOM.
  /// - Repeated failures are logged at most once every 5 seconds so the
  ///   console isn't flooded while the map is settling.
  Future<void> _updateRiderLocation(Position position) async {
    if (!mounted) return;
    // Keep the on-screen "current location" text in sync with live updates.
    setState(() => _currentPosition = position);
    // Refresh the human-readable address (throttled to respect Nominatim
    // fair-use — geocodes only after meaningful movement / cooldown).
    _updatePickupAddress(position);
    if (!_mapReady || _updatingMarker) return;
    final point = osm.GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    _updatingMarker = true;
    try {
      if (_riderMarkerPoint == null) {
        await mapController.addMarker(
          point,
          markerIcon: const osm.MarkerIcon(
            icon: Icon(Icons.my_location, color: AppColors.primary, size: 32),
          ),
        );
      } else {
        await mapController.changeLocationMarker(
          oldLocation: _riderMarkerPoint!,
          newLocation: point,
        );
      }
      _riderMarkerPoint = point;
    } catch (e) {
      // The marker element may have been removed from the DOM (Leaflet
      // rebuild/dispose on web). Drop the tracked point so the next attempt
      // re-adds a fresh marker instead of moving a stale one.
      _riderMarkerPoint = null;
      _logMarkerErrorThrottled(e);
    } finally {
      _updatingMarker = false;
    }

    // Real-time follow: keep the camera centered on the rider (only when the
    // marker itself was updated successfully).
    if (_followUser && _riderMarkerPoint != null) {
      _lastProgrammaticMove = DateTime.now();
      try {
        await mapController.moveTo(point);
      } catch (e) {
        _logMarkerErrorThrottled(e);
      }
    }
  }

  /// Reverse-geocodes the rider's current position into a readable address
  /// (via [PlacesService]). Throttled so Nominatim isn't hammered: at most
  /// once every 10 seconds, and only after the position moved >200 m.
  Future<void> _updatePickupAddress(Position position) async {
    final now = DateTime.now();
    final lastAt = _lastReverseGeocodeAt;
    final lastPoint = _lastReverseGeocodePoint;
    if (lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 10)) {
      return;
    }
    if (lastPoint != null) {
      final moved = Geolocator.distanceBetween(
        lastPoint.latitude,
        lastPoint.longitude,
        position.latitude,
        position.longitude,
      );
      if (moved < 200) return;
    }
    final address = await PlacesService.instance.reverseGeocode(
      position.latitude,
      position.longitude,
    );
    if (!mounted) return;
    setState(() {
      _pickupAddress = address;
      _lastReverseGeocodeAt = now;
      _lastReverseGeocodePoint = osm.GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    });
  }

  /// Logs a marker/camera failure at most once every 5 seconds so repeated
  /// web (Leaflet) errors don't flood the console.
  void _logMarkerErrorThrottled(Object error) {
    final now = DateTime.now();
    final last = _lastMarkerErrorLogged;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastMarkerErrorLogged = now;
    logWarning('RiderHomeScreen', 'Failed to update rider marker: $error');
  }

  /// Subscribes to live position updates and keeps the rider marker in sync.
  void _startLocationUpdates() {
    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 2, // meters — smooth real-time tracking
          ),
        ).listen((position) {
          if (mounted) _updateRiderLocation(position);
        });

    // The web geolocation stream can be quiet/unreliable — poll periodically
    // so the marker keeps moving in real time on Chrome.
    if (kIsWeb) {
      _locationPollTimer?.cancel();
      _locationPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) _getCurrentLocation();
      });
    }
  }

  /// Re-centers the map on the rider's current position and re-enables
  /// follow mode.
  ///
  /// Re-fetches the location with the best available accuracy (rather than
  /// reusing a possibly stale fix), moves the rider marker, re-centers the
  /// camera with animation and refreshes the on-screen "current location"
  /// text. If the fresh fix fails (GPS off, permission denied, timeout) a
  /// clear Arabic [SnackBar] is shown instead of failing silently.
  Future<void> _recenter() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;

      // Re-enable follow mode, then refresh the marker + location text (and
      // re-center the camera when following).
      setState(() => _followUser = true);
      _lastProgrammaticMove = DateTime.now();
      await _updateRiderLocation(position);

      // Guarantee an animated camera move to the fresh fix even if follow
      // was previously disabled by the user panning the map.
      if (_mapReady) {
        _lastProgrammaticMove = DateTime.now();
        try {
          await mapController.moveTo(
            osm.GeoPoint(
              latitude: position.latitude,
              longitude: position.longitude,
            ),
            animate: true,
          );
        } catch (e) {
          logError('RiderHomeScreen', 'Failed to recenter map: $e', e);
        }
      }
    } catch (e) {
      logError('RiderHomeScreen', 'Failed to re-fetch location: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر تحديد موقعك الحالي، تحقق من إعدادات الموقع'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Called when the visible map region changes. If the map was moved by the
  /// user (not by our own follow/recenter moves) and drifted away from the
  /// rider, stop auto-following so the user can freely explore the map.
  void _onRegionChanged() {
    if (!_followUser) return;
    // Wait until the rider marker has been placed once.
    if (_riderMarkerPoint == null) return;
    // Ignore region changes caused by our own camera moves.
    final lastMove = _lastProgrammaticMove;
    if (lastMove != null &&
        DateTime.now().difference(lastMove) <
            const Duration(milliseconds: 800)) {
      return;
    }
    final region = mapController.listenerRegionIsChanging.value;
    final position = _currentPosition;
    if (region == null || position == null) return;
    final distance = Geolocator.distanceBetween(
      region.center.latitude,
      region.center.longitude,
      position.latitude,
      position.longitude,
    );
    if (distance > 100) {
      setState(() => _followUser = false);
      logInfo('RiderHomeScreen', 'Follow disabled — user moved the map');
    }
  }

  void _onMapReady(bool isReady) {
    if (!isReady) return;
    setState(() => _mapReady = true);
    if (_locationGranted && _currentPosition != null) {
      _getCurrentLocation();
    }
  }

  /// On web, `flutter_osm_plugin` does not always fire
  /// [OSMFlutter.onMapIsReady] — the callback can be silently skipped on
  /// Chrome/Web — so `_mapReady` would stay `false` and the loading spinner
  /// would cover the screen forever. As a safety net, force the UI ready
  /// after a short delay and place the rider marker if a fix is available.
  void _startMapReadyFallback() {
    if (!kIsWeb) return;
    _mapReadyFallbackTimer?.cancel();
    _mapReadyFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _mapReady) return;
      logInfo('RiderHomeScreen', 'Map ready fallback (web) — forcing UI ready');
      setState(() => _mapReady = true);
      if (_locationGranted && _currentPosition != null) {
        // Places the rider marker and (follow mode) centers the camera.
        _updateRiderLocation(_currentPosition!);
      }
    });
  }

  /// Top-bar action icon that navigates to the given named route.
  Widget _topBarIcon(IconData icon, String route) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primaryBg.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: AppColors.textPrimary,
          size: AppSpacing.iconMd,
        ),
      ),
    );
  }

  /// Tappable destination search bar that opens the ride-options sheet.
  Widget _buildSearchBar() {
    return InkWell(
      onTap: _requestRide,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: AppColors.shadowSm,
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.primaryGreen),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'إلى أين تريد الذهاب؟',
                style: AppTextStyles.bodyLarge?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Icon(Icons.tune_rounded, color: AppColors.primaryGreen),
          ],
        ),
      ),
    );
  }

  Future<void> _requestRide() => _openRideOptions();

  /// Compact button that re-centers the map on the rider's current position
  /// (and re-enables follow mode). Visually highlights when following.
  Widget _recenterButton() {
    final following = _followUser;
    return SizedBox(
      width: AppSpacing.buttonHeightLg,
      height: AppSpacing.buttonHeightLg,
      child: ElevatedButton(
        onPressed: _recenter,
        style: ElevatedButton.styleFrom(
          backgroundColor: following ? AppColors.primary : AppColors.cardBg,
          foregroundColor: following
              ? AppColors.textOnPrimary
              : AppColors.primaryGreen,
          padding: EdgeInsets.zero,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: Icon(
          following
              ? Icons.my_location_rounded
              : Icons.location_searching_rounded,
        ),
      ),
    );
  }

  /// Opens the ride-options bottom sheet, sends a REAL ride request to the
  /// backend, then shows the "searching for driver" dialog (socket events +
  /// 4s polling fallback) and navigates to the active trip only when a
  /// driver is actually found.
  Future<void> _openRideOptions() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى الانتظار حتى يتم تحديد موقعك الحالي'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final current = _currentPosition!;
    final result = await showModalBottomSheet<RideSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RideOptionsSheet(
        pickupLat: current.latitude,
        pickupLng: current.longitude,
        pickupAddress: _pickupAddress.isNotEmpty
            ? _pickupAddress
            : '${current.latitude.toStringAsFixed(4)}, '
                  '${current.longitude.toStringAsFixed(4)}',
      ),
    );
    if (result == null || !mounted) return;

    // Send a REAL ride request to the backend. On failure we stop — there is
    // no simulated fallback anymore.
    late final Map<String, dynamic> rideResponse;
    try {
      rideResponse = await ApiService.instance.requestRide(
        pickupLat: result.pickupLat,
        pickupLng: result.pickupLng,
        pickupAddress: result.pickupAddress,
        dropoffLat: result.dropoffLat,
        dropoffLng: result.dropoffLng,
        dropoffAddress: result.dropoffAddress,
        rideType: result.type,
        paymentMethod: result.payment,
      );
      logInfo('HomeScreen', 'ride request submitted successfully');
    } catch (e) {
      logError('HomeScreen', 'requestRide failed: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل إرسال الطلب، حاول مرة أخرى'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    // Extract the backend ride id so we can watch / cancel this ride.
    final rideId = _extractRideId(rideResponse);
    if (rideId == null || rideId.isEmpty) {
      logWarning('HomeScreen', 'no ride id in response: $rideResponse');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم تأكيد الرحلة، حاول مرة أخرى'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    logInfo('HomeScreen', 'ride created — id: $rideId');

    // Real driver search: socket events + 4s polling fallback. Only navigate
    // to the active trip when a driver is actually found.
    final found = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FindingDriverDialog(rideId: rideId),
    );

    if (found == true && mounted) {
      Navigator.pushNamed(
        context,
        '/active-trip',
        arguments: ActiveTripArgs(
          pickupLat: result.pickupLat,
          pickupLng: result.pickupLng,
          pickupAddress: result.pickupAddress,
          dropoffLat: result.dropoffLat,
          dropoffLng: result.dropoffLng,
          dropoffAddress: result.dropoffAddress,
          rideType: result.type,
          payment: result.payment,
          fare: result.fare,
        ),
      );
    }
  }

  /// Extracts the ride id from a `POST /rides/request` response, supporting
  /// `id`, `rideId`, `data.id`, `data.rideId` and `ride.id` shapes (string or
  /// numeric ids).
  /// Explicitly prefers `response['ride']['id']` (backend documented shape),
  /// then falls back to other common id fields.
  String? _extractRideId(Map<String, dynamic> response) {
    // 1) Backend shape: { message, ride: { id, status, ... } }
    final ride = response['ride'];
    if (ride is Map) {
      final id = _asStringId(ride['id']);
      if (id != null) return id;
    }
    // 2) Top-level id / rideId
    final direct = response['id'] ?? response['rideId'];
    final directId = _asStringId(direct);
    if (directId != null) return directId;
    // 3) Nested under data
    final data = response['data'];
    if (data is Map) {
      final nestedRide = data['ride'];
      if (nestedRide is Map) {
        final id = _asStringId(nestedRide['id']);
        if (id != null) return id;
      }
      final nested = data['id'] ?? data['rideId'];
      final nestedId = _asStringId(nested);
      if (nestedId != null) return nestedId;
    }
    return null;
  }

  /// Coerces a JSON id (String or num) into a non-empty String, else null.
  String? _asStringId(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is num) return value.toString();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Stack(
        children: [
          // Map
          osm.OSMFlutter(
            controller: mapController,
            osmOption: osm.OSMOption(
              userTrackingOption:
                  const osm.UserTrackingOption.withoutUserPosition(
                    enableTracking: false,
                  ),
              zoomOption: const osm.ZoomOption(
                initZoom: 14,
                minZoomLevel: 10,
                maxZoomLevel: 19,
                stepZoom: 1,
              ),
            ),
            onMapIsReady: _onMapReady,
          ),

          // Top bar with app name
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + AppSpacing.sm,
                bottom: AppSpacing.md,
                left: AppSpacing.lg,
                right: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primaryBg.withValues(alpha: 0.95),
                    AppColors.primaryBg.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.directions_car_rounded,
                              color: AppColors.primary,
                              size: AppSpacing.iconMd,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Waslny',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: AppColors.textPrimary),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Rider',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      _topBarIcon(Icons.history_rounded, '/history'),
                      const SizedBox(width: AppSpacing.sm),
                      _topBarIcon(
                        Icons.notifications_rounded,
                        '/notifications',
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _topBarIcon(Icons.person_rounded, '/profile'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildSearchBar(),
                ],
              ),
            ),
          ),

          // Bottom: Request Ride button + current location info
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: AppSpacing.xxl,
                right: AppSpacing.xxl,
                top: AppSpacing.xxl,
                bottom: MediaQuery.of(context).padding.bottom + AppSpacing.xxl,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.primaryBg.withValues(alpha: 0.95),
                    AppColors.primaryBg.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Location info (when available)
                  if (_currentPosition != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: AppSpacing.iconMd,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _pickupAddress.isNotEmpty
                                  ? 'موقعك الحالي: $_pickupAddress'
                                  : 'موقعك الحالي: ${_currentPosition!.latitude.toStringAsFixed(4)}, '
                                        '${_currentPosition!.longitude.toStringAsFixed(4)}',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Request Ride button + recenter
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: AppSpacing.buttonHeightLg,
                          child: ElevatedButton.icon(
                            onPressed: _requestRide,
                            icon: const Icon(Icons.taxi_alert_rounded),
                            label: Text(
                              'اطلب رحلة',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: AppColors.textOnPrimary),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.textOnPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusLg,
                                ),
                              ),
                              elevation: 4,
                              shadowColor: AppColors.primaryDark.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _recenterButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Map loading indicator
          if (!_mapReady)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

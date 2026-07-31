import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart' as osm;
import 'package:geolocator/geolocator.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
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
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    mapController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
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
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      logInfo(
        'RiderHomeScreen',
        '📍 Current location: ${position.latitude}, ${position.longitude}',
      );

      await _updateRiderLocation(position);

      // Move the map to the current location on first fix
      if (_mapReady) {
        await mapController.moveTo(
          osm.GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        );
      }
    } catch (e) {
      logError('RiderHomeScreen', 'Failed to get location: $e', e);
    }
  }

  /// Adds / moves the rider marker on the map for the given [position].
  Future<void> _updateRiderLocation(Position position) async {
    if (!mounted) return;
    _currentPosition = position;
    final point = osm.GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    if (!_mapReady) return;
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
      logError('RiderHomeScreen', 'Failed to update rider marker: $e', e);
    }
  }

  /// Subscribes to live position updates and keeps the rider marker in sync.
  void _startLocationUpdates() {
    _positionStream?.cancel();
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // meters
          ),
        ).listen((position) {
          if (mounted) _updateRiderLocation(position);
        });
  }

  /// Re-centers the map on the rider's current position.
  Future<void> _recenter() async {
    final position = _currentPosition;
    if (position == null || !_mapReady) return;
    await mapController.moveTo(
      osm.GeoPoint(latitude: position.latitude, longitude: position.longitude),
      animate: true,
    );
  }

  void _onMapReady(bool isReady) {
    if (!isReady) return;
    setState(() => _mapReady = true);
    if (_locationGranted && _currentPosition != null) {
      _getCurrentLocation();
    }
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

  /// Compact button that re-centers the map on the rider's current position.
  Widget _recenterButton() {
    return SizedBox(
      width: AppSpacing.buttonHeightLg,
      height: AppSpacing.buttonHeightLg,
      child: ElevatedButton(
        onPressed: _recenter,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cardBg,
          foregroundColor: AppColors.primaryGreen,
          padding: EdgeInsets.zero,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: const Icon(Icons.my_location_rounded),
      ),
    );
  }

  /// Opens the ride-options bottom sheet, then the "searching for driver"
  /// radar dialog, and finally navigates to the active trip when a driver is
  /// found.
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
        pickupAddress:
            '${current.latitude.toStringAsFixed(4)}, '
            '${current.longitude.toStringAsFixed(4)}',
      ),
    );
    if (result == null || !mounted) return;

    // Create the ride on the backend with a backend-compatible payload.
    // If the request fails we still continue with the simulated flow so the
    // user experience never breaks.
    try {
      await ApiService.instance.requestRide(
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
      logWarning(
        'HomeScreen',
        'requestRide failed — continuing simulation: $e',
      );
    }

    // The awaited request may have taken a while — bail out if the screen
    // was disposed in the meantime.
    if (!mounted) return;

    // Searching-for-driver radar dialog (auto-dismisses when a driver is found).
    final found = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FindingDriverDialog(),
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
                              'موقعك الحالي: ${_currentPosition!.latitude.toStringAsFixed(4)}, '
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

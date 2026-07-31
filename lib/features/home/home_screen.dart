import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart' as osm;
import 'package:geolocator/geolocator.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/features/home/finding_driver_dialog.dart';
import 'package:wasalny_rider/features/home/ride_options_sheet.dart';

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
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _currentPosition = position;
      logInfo(
        'RiderHomeScreen',
        '📍 Current location: ${position.latitude}, ${position.longitude}',
      );

      // Move the map to the current location
      if (_mapReady) {
        await mapController.moveTo(
          osm.GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
        );
        // Add a marker for the rider's location
        await mapController.addMarker(
          osm.GeoPoint(
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          markerIcon: const osm.MarkerIcon(
            icon: Icon(Icons.my_location, color: AppColors.primary, size: 32),
          ),
        );
      }
    } catch (e) {
      logError('RiderHomeScreen', 'Failed to get location: $e', e);
    }
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

    final result = await showModalBottomSheet<RideSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RideOptionsSheet(),
    );
    if (result == null || !mounted) return;

    // Searching-for-driver radar dialog (auto-dismisses when a driver is found).
    final found = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FindingDriverDialog(),
    );

    if (found == true && mounted) {
      Navigator.pushNamed(context, '/active-trip');
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

                  // Request Ride button
                  SizedBox(
                    width: double.infinity,
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

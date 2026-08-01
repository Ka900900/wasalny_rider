import 'package:dio/dio.dart';

import 'package:wasalny_rider/core/utils/logger.dart';

/// A single place/address returned by the Nominatim (OpenStreetMap) search.
class PlaceResult {
  final String displayName;
  final double lat;
  final double lng;

  const PlaceResult({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}

/// Real place/address search via the public Nominatim (OpenStreetMap)
/// geocoder.
///
/// Search (`/search`) resolves a free-text query into geocoded places
/// (restricted to Egypt via `countrycodes=eg`), and reverse geocoding
/// (`/reverse`) turns a lat/lng pair into a human-readable address. Uses its
/// own [Dio] instance so the app's auth interceptor and backend base URL are
/// never involved.
class PlacesService {
  PlacesService._();

  /// Global access point for the places service.
  static final PlacesService instance = PlacesService._();

  static const String _nominatimBase = 'https://nominatim.openstreetmap.org';

  final Dio _dio = Dio(
    BaseOptions(
      // Nominatim requires a descriptive User-Agent identifying the app.
      headers: const {
        'User-Agent':
            'WaslnyRider/1.0 (ride-hailing rider app; contact: dev@waslny.app)',
        'Accept-Language': 'ar,en',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  /// Searches [query] on Nominatim, returning up to [limit] places.
  ///
  /// On error returns an empty list (never throws).
  Future<List<PlaceResult>> search(
    String query, {
    String countryCodes = 'eg',
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final response = await _dio.get<dynamic>(
        '$_nominatimBase/search',
        queryParameters: {
          'q': q,
          'format': 'json',
          'countrycodes': countryCodes,
          'limit': limit,
          'addressdetails': 1,
        },
      );
      final data = response.data;
      if (data is! List) return const [];
      final results = <PlaceResult>[];
      for (final item in data) {
        if (item is! Map) continue;
        final lat = double.tryParse('${item['lat']}');
        final lng = double.tryParse('${item['lon']}');
        final name = item['display_name'];
        if (lat != null && lng != null && name is String && name.isNotEmpty) {
          results.add(PlaceResult(displayName: name, lat: lat, lng: lng));
        }
      }
      return results;
    } catch (e) {
      logWarning('PlacesService', 'Nominatim search failed for "$q": $e');
      return const [];
    }
  }

  /// Reverse-geocodes [lat]/[lng] into a human-readable address.
  ///
  /// Falls back to a `"lat, lng"` string when the request fails or returns
  /// no address.
  Future<String> reverseGeocode(double lat, double lng) async {
    final fallback = '$lat, $lng';
    try {
      final response = await _dio.get<dynamic>(
        '$_nominatimBase/reverse',
        queryParameters: {'lat': lat, 'lon': lng, 'format': 'json', 'zoom': 18},
      );
      final data = response.data;
      if (data is Map) {
        final displayName = data['display_name'];
        if (displayName is String && displayName.isNotEmpty) {
          return displayName;
        }
      }
      return fallback;
    } catch (e) {
      logWarning('PlacesService', 'Nominatim reverse geocode failed: $e');
      return fallback;
    }
  }
}

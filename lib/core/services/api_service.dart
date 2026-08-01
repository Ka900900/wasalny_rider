// ignore_for_file: use_null_aware_elements

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wasalny_rider/core/constants/api_constants.dart';
import 'package:wasalny_rider/core/network/dio_client.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// HTTP API client for communicating with the Waslny Backend API.
///
/// Handles authentication via JWT token stored in memory and persisted
/// to [SharedPreferences] so the session survives app restarts.
class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  // Same backend as the Captain app
  static const String _baseUrl = ApiConstants.baseUrl;

  /// Public base URL used by other services.
  static String get baseUrl => _baseUrl;

  /// Toggle the custom backend API on/off.
  /// Set to `true` once your backend server is running and reachable.
  static const bool backendEnabled = true;

  String? _token;

  /// Local-storage key under which the JWT is persisted so it survives app
  /// restarts (avoids 401 on cold start before the user re-logs in).
  static const String _tokenStorageKey = 'api_jwt_token';

  // ── Token Management ─────────────────────────────────

  void saveToken(String token) {
    _token = token;
    _persistToken(token);
  }

  /// Persists the JWT to local storage (fire-and-forget, never blocks UI).
  Future<void> _persistToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenStorageKey, token);
    } catch (e) {
      logError('ApiService', 'saveToken persist failed: $e', e);
    }
  }

  /// Restores the persisted JWT into memory. Call once during app startup
  /// (e.g. from the splash screen) so authenticated requests work even
  /// before the user explicitly re-authenticates.
  Future<void> loadToken() async {
    if (hasToken) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenStorageKey);
    } catch (e) {
      logError('ApiService', 'loadToken failed: $e', e);
    }
  }

  String? getToken() => _token;

  /// Public wrapper used by other services to make sure a JWT is present
  /// in memory before sending an authenticated request.
  Future<void> ensureTokenReady() => _ensureTokenLoaded();

  void clearToken() {
    _token = null;
    _clearPersistedToken();
  }

  Future<void> _clearPersistedToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenStorageKey);
    } catch (e) {
      logError('ApiService', 'clearToken persist failed: $e', e);
    }
  }

  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Decodes the stored JWT and returns the `userId` claim from its payload,
  /// or `null` if the token is missing / malformed.
  String? get userId {
    if (_token == null) return null;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return null;
      // Normalise Base64‑URL → Base64 (padding + URL‑safe chars).
      var payload = parts[1];
      payload = payload.padRight(
        payload.length + (4 - payload.length % 4) % 4,
        '=',
      );
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      final decoded = utf8.decode(base64.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['userId'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Ensures a JWT is present in memory before sending an authenticated
  /// request. If the in-memory token is missing (e.g. after a cold start),
  /// it attempts to restore it from local storage to avoid 401 errors.
  Future<void> _ensureTokenLoaded() async {
    if (hasToken) return;
    await loadToken();
  }

  /// Shortcut to the shared Dio instance.
  Dio get _dio => DioClient.instance.dio;

  // ── Auth Endpoints ───────────────────────────────────

  /// Sign in / register via Firebase ID Token.
  ///
  /// Sends the Firebase ID Token (obtained after Google Sign-In) to the
  /// backend. The backend verifies the token with Firebase Admin SDK, looks
  /// up / creates the user in PostgreSQL, and returns the application's own
  /// JWT. Optional Google profile data (`name`, `email`, `photoUrl`) is
  /// forwarded so the `User` record stays in sync with the Google account.
  Future<Map<String, dynamic>> signInWithFirebase(
    String firebaseIdToken, {
    String? name,
    String? email,
    String? photoUrl,
  }) async {
    if (!backendEnabled) return <String, dynamic>{'success': true};
    final response = await _dio.post(
      '/auth/firebase-login',
      data: {
        'firebaseIdToken': firebaseIdToken,
        if (name != null && name.isNotEmpty) 'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      },
    );
    final result = response.data as Map<String, dynamic>;
    if (result['token'] != null) {
      saveToken(result['token'] as String);
    }
    return result;
  }

  /// Sign in with email + password via `POST /auth/login`.
  ///
  /// The backend verifies the credentials and returns the app JWT in the
  /// top-level `token` field, which is persisted automatically.
  Future<Map<String, dynamic>> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!backendEnabled) return <String, dynamic>{'success': true};
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    final result = response.data as Map<String, dynamic>;
    final token = _extractToken(result);
    if (token != null) saveToken(token);
    return result;
  }

  /// Register a new rider with email + password via `POST /auth/register`.
  ///
  /// Sends `email`, `password`, `firstName` and `lastName`. The backend
  /// returns a JWT on success, which is saved automatically (the rider is
  /// signed in right away).
  Future<Map<String, dynamic>> registerWithEmailPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    if (!backendEnabled) return <String, dynamic>{'success': true};
    final response = await _dio.post(
      '/auth/register',
      data: {
        'email': email.trim(),
        'password': password,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
      },
    );
    final result = response.data as Map<String, dynamic>;
    final token = _extractToken(result);
    if (token != null) saveToken(token);
    return result;
  }

  /// Register / refresh the rider's FCM token on the backend.
  Future<bool> updateFcmTokenToServer(String token) async {
    if (!backendEnabled) return false;
    if (token.isEmpty) return false;
    try {
      await _dio.post('/auth/register-fcm-token', data: {'fcmToken': token});
      logInfo('ApiService', '✅ FCM token registered with backend');
      return true;
    } on DioException catch (e) {
      logWarning(
        'ApiService',
        'updateFcmTokenToServer failed: ${e.response?.statusCode} ${e.response?.data}',
      );
      return false;
    } catch (e) {
      logError('ApiService', 'updateFcmTokenToServer error: $e', e);
      return false;
    }
  }

  // ── User Endpoints ───────────────────────────────────

  /// Get user profile.
  ///
  /// The backend returns profile data at the top level of the response
  /// (no `riderProfile` wrapper – the rider has no vehicle).
  /// Expected fields: `id`, `firstName`, `lastName`, `avatarUrl`,
  /// `role` = `'RIDER'`.
  Future<Map<String, dynamic>> getProfile() async {
    if (!backendEnabled) return <String, dynamic>{};
    await _ensureTokenLoaded();
    final response = await _dio.get('/user/profile');
    return response.data as Map<String, dynamic>;
  }

  /// Update user profile.
  Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? avatarUrl,
  }) async {
    if (!backendEnabled) return <String, dynamic>{'success': true};
    final response = await _dio.put(
      '/user/profile/update',
      data: {
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // ── Ride Endpoints (Rider) ────────────────────────────

  /// Request a new ride.
  ///
  /// Sends the pickup/dropoff coordinates and addresses plus the
  /// backend-compatible `rideType` (`economy` | `comfort` | `premium`) and
  /// `paymentMethod` (`cash` | `card`) in the body expected by the backend
  /// (`originLat`/`originLng`, `destLat`/`destLng`, `pickupAddress`,
  /// `destinationAddress`, `rideType`, `paymentMethod`).
  Future<Map<String, dynamic>> requestRide({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    required String rideType,
    required String paymentMethod,
  }) async {
    if (!backendEnabled) return <String, dynamic>{'success': true};
    await _ensureTokenLoaded();
    final response = await _dio.post(
      '/rides/request',
      data: {
        'originLat': pickupLat,
        'originLng': pickupLng,
        'destLat': dropoffLat,
        'destLng': dropoffLng,
        'pickupAddress': pickupAddress,
        'destinationAddress': dropoffAddress,
        'rideType': rideType,
        'paymentMethod': paymentMethod,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  /// Cancel a ride.
  ///
  /// Tries `PUT /rides/cancel/$rideId` first (matches the backend route),
  /// then falls back to `POST /rides/cancel/$rideId` if PUT is rejected
  /// (405 / 404 / 400 / 501).
  Future<bool> cancelRide(String rideId) async {
    if (!backendEnabled) return true;
    try {
      await _dio.put('/rides/cancel/$rideId');
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 405 || status == 404 || status == 400 || status == 501) {
        try {
          await _dio.post('/rides/cancel/$rideId');
          return true;
        } on DioException catch (postError) {
          logWarning(
            'ApiService',
            'cancelRide failed (POST fallback): '
            '${postError.response?.statusCode} ${postError.response?.data}',
          );
          return false;
        }
      }
      logWarning(
        'ApiService',
        'cancelRide failed: $status ${e.response?.data}',
      );
      return false;
    } catch (e) {
      logError('ApiService', 'cancelRide error: $e', e);
      return false;
    }
  }

  /// Get current ride status.
  Future<Map<String, dynamic>> getCurrentRide() async {
    if (!backendEnabled) return <String, dynamic>{};
    await _ensureTokenLoaded();
    final response = await _dio.get('/rides/current');
    return response.data as Map<String, dynamic>;
  }

  /// Get ride history for the current rider.
  Future<Map<String, dynamic>> getRideHistory() async {
    if (!backendEnabled) return <String, dynamic>{};
    await _ensureTokenLoaded();
    final response = await _dio.get('/rides/history');
    return response.data as Map<String, dynamic>;
  }

  // ── Helper ───────────────────────────────────────────

  /// Extracts the JWT from an auth response, supporting both a top-level
  /// `token` field and a nested `data.token` shape (defensive).
  String? _extractToken(Map<String, dynamic> result) {
    final token = result['token'];
    if (token is String && token.isNotEmpty) return token;
    final data = result['data'];
    if (data is Map) {
      final nested = data['token'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
    return null;
  }
}

/// Centralised API configuration for the Waslny Rider app.
///
/// All network endpoints are relative to [baseUrl] (the `/api/v1` prefix is
/// included). Keep the backend URL in a single place so it is easy to switch
/// between development / staging / production.
class ApiConstants {
  ApiConstants._();

  /// Base URL for the Waslny backend (Railway production instance).
  static const String baseUrl =
      'https://wasalny-backend-production.up.railway.app/api/v1';

  // ── Auth endpoints ─────────────────────────────────
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String firebaseLogin = '/auth/firebase-login';
  static const String registerFcm = '/auth/register-fcm-token';

  // ── User endpoints ─────────────────────────────────
  static const String profile = '/user/profile';
  static const String updateProfile = '/user/profile/update';

  // ── Ride endpoints ─────────────────────────────────
  static const String requestRide = '/rides/request';
  static const String cancelRide = '/rides/cancel/';
  static const String currentRide = '/rides/current';
  static const String rideHistory = '/rides/history';
}

import 'package:dio/dio.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// Dio interceptor that automatically injects the Bearer JWT token from
/// [ApiService] into every outgoing request's `Authorization` header.
///
/// Also watches for 401 responses and clears the stored token when the
/// session is no longer valid (forces the user to re-authenticate).
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final api = ApiService.instance;

    // Inject the Bearer token if we have one.
    if (api.hasToken) {
      options.headers['Authorization'] = 'Bearer ${api.getToken()}';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // If the server returned 401 Unauthorized our token is likely expired
    // or revoked — clear it so subsequent requests don't retry with a dead
    // token. The auth-gate screens will redirect to login.
    if (err.response?.statusCode == 401) {
      logWarning(
        'AuthInterceptor',
        'Received 401 — clearing stored JWT token.',
      );
      ApiService.instance.clearToken();
    }

    handler.next(err);
  }
}

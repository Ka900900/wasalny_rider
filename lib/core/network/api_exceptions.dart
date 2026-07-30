/// Centralised API exception handling for the Waslny Rider app.
///
/// Provides [ApiException] plus a factory that maps low-level [DioException]
/// values into user-friendly Arabic messages.
library;

import 'package:dio/dio.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ApiException
// ═════════════════════════════════════════════════════════════════════════════

/// Exception thrown when an API request fails.
class ApiException implements Exception {
  /// User-facing error message (Arabic).
  final String message;

  /// HTTP status code, or `-1` for non-HTTP errors.
  final int statusCode;

  /// Optional backend error code (e.g. `"TOKEN_EXPIRED"`).
  final String? errorCode;

  const ApiException({
    required this.message,
    this.statusCode = -1,
    this.errorCode,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';

  // ── Factory from DioException ──────────────────────────────────

  /// Creates an [ApiException] from a [DioException] by inspecting its
  /// type and response status code.
  factory ApiException.fromDioException(DioException e) {
    // ── Timeout ──────────────────────────────────────────────────
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        message: 'انتهت مهلة الاتصال. تحقق من اتصالك بالإنترنت وحاول مرة أخرى.',
        statusCode: -1,
        errorCode: 'TIMEOUT',
      );
    }

    // ── No internet / connection refused ─────────────────────────
    if (e.type == DioExceptionType.connectionError) {
      return const ApiException(
        message: 'تعذر الاتصال بالخادم. تأكد من اتصالك بالإنترنت.',
        statusCode: -1,
        errorCode: 'CONNECTION_ERROR',
      );
    }

    // ── Canceled ─────────────────────────────────────────────────
    if (e.type == DioExceptionType.cancel) {
      return const ApiException(
        message: 'تم إلغاء الطلب.',
        statusCode: -1,
        errorCode: 'CANCELLED',
      );
    }

    // ── Response errors (4xx, 5xx) ───────────────────────────────
    final response = e.response;
    if (response != null) {
      final statusCode = response.statusCode ?? -1;
      final body = response.data;

      // Try to extract a backend-provided error message.
      String? backendMessage;
      if (body is Map<String, dynamic>) {
        backendMessage = body['error'] as String? ?? body['message'] as String?;
      }

      switch (statusCode) {
        case 400:
          return ApiException(
            message: backendMessage ?? 'طلب غير صالح. يرجى التحقق من البيانات.',
            statusCode: statusCode,
            errorCode: 'BAD_REQUEST',
          );
        case 401:
          return ApiException(
            message:
                backendMessage ??
                'انتهت صلاحية الجلسة. يرجى تسجيل الدخول مرة أخرى.',
            statusCode: statusCode,
            errorCode: 'UNAUTHORIZED',
          );
        case 403:
          return ApiException(
            message: backendMessage ?? 'ليس لديك صلاحية للوصول إلى هذا المورد.',
            statusCode: statusCode,
            errorCode: 'FORBIDDEN',
          );
        case 404:
          return ApiException(
            message: backendMessage ?? 'المورد المطلوب غير موجود.',
            statusCode: statusCode,
            errorCode: 'NOT_FOUND',
          );
        case 409:
          return ApiException(
            message:
                backendMessage ?? 'تعارض في البيانات. يرجى المحاولة مرة أخرى.',
            statusCode: statusCode,
            errorCode: 'CONFLICT',
          );
        case 422:
          return ApiException(
            message:
                backendMessage ?? 'بيانات غير صالحة. يرجى التحقق من المدخلات.',
            statusCode: statusCode,
            errorCode: 'UNPROCESSABLE_ENTITY',
          );
        case 429:
          return const ApiException(
            message:
                'طلبات كثيرة جداً. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.',
            statusCode: 429,
            errorCode: 'RATE_LIMIT',
          );
        case 500:
          return const ApiException(
            message: 'خطأ داخلي في الخادم. يرجى المحاولة لاحقاً.',
            statusCode: 500,
            errorCode: 'SERVER_ERROR',
          );
        default:
          return ApiException(
            message: backendMessage ?? 'حدث خطأ غير متوقع ($statusCode).',
            statusCode: statusCode,
          );
      }
    }

    // ── Fallback ─────────────────────────────────────────────────
    return const ApiException(
      message: 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.',
      statusCode: -1,
      errorCode: 'UNKNOWN',
    );
  }
}

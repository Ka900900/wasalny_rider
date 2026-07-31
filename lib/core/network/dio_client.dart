import 'package:dio/dio.dart';
import 'package:logging/logging.dart' as l;

import 'package:wasalny_rider/core/constants/api_constants.dart';
import 'package:wasalny_rider/core/network/auth_interceptor.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// Centralised Dio HTTP client for the Waslny Rider app.
///
/// Provides a pre-configured [Dio] singleton with:
/// - Base URL pointing to the Waslny backend (`/api/v1`)
/// - Connection & receive timeouts
/// - [AuthInterceptor] for automatic Bearer token injection
/// - A custom logging interceptor for debugging
///
/// ## Usage
/// ```dart
/// // Initialise once at app startup (e.g. in SplashScreen or main).
/// DioClient.instance.init();
///
/// // Then anywhere in the app:
/// final response = await DioClient.instance.dio.get('/some/endpoint');
/// ```
class DioClient {
  // ── Singleton ──────────────────────────────────────────────────
  DioClient._();
  static final DioClient instance = DioClient._();

  // ── Configuration constants ────────────────────────────────────
  static const Duration _defaultConnectTimeout = Duration(seconds: 15);
  static const Duration _defaultReceiveTimeout = Duration(seconds: 30);

  /// The underlying [Dio] instance. Must call [init] before using.
  late final Dio dio;

  /// Whether the client has been initialised.
  bool _initialised = false;
  bool get isInitialised => _initialised;

  // ── Initialisation ─────────────────────────────────────────────

  /// Initialises the Dio client with the given [baseUrl].
  ///
  /// Safe to call multiple times — subsequent calls are no-ops once
  /// the client is initialised (unless [force] is `true`).
  void init({String baseUrl = ApiConstants.baseUrl, bool force = false}) {
    if (_initialised && !force) return;

    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: _defaultConnectTimeout,
        receiveTimeout: _defaultReceiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Order matters: AuthInterceptor runs first so the token is set
    // before the request is logged.
    dio.interceptors.addAll([AuthInterceptor(), _LoggingInterceptor()]);

    _initialised = true;
    logInfo('DioClient', '✅ Dio client initialised — baseUrl: $baseUrl');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Logger interceptor
// ═════════════════════════════════════════════════════════════════════════════

/// Dio interceptor that logs every request and response using the app's
/// own logging framework ([package:logging] via [logger.dart]).
class _LoggingInterceptor extends Interceptor {
  final _logger = l.Logger('Dio');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.fine(
      '➡️ ${options.method} ${options.uri}\n'
      'Headers: ${_sanitiseHeaders(options.headers)}\n'
      'Body: ${options.data}',
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logger.fine(
      '⬅️ ${response.statusCode} ${response.requestOptions.uri}\n'
      'Response: ${_truncate(response.data)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.warning(
      '❌ ${err.response?.statusCode ?? 'NO_RESPONSE'} '
      '${err.requestOptions.uri}\n'
      'Error: ${err.message}\n'
      'Response: ${_truncate(err.response?.data)}',
    );
    handler.next(err);
  }

  /// Truncates large response bodies so the logs stay readable.
  String _truncate(dynamic data) {
    final s = data?.toString() ?? '';
    return s.length > 2000 ? '${s.substring(0, 2000)}… (${s.length} chars)' : s;
  }

  /// Masks sensitive headers (e.g. Authorization) in logs.
  Map<String, dynamic> _sanitiseHeaders(Map<String, dynamic> headers) {
    final sanitised = Map<String, dynamic>.from(headers);
    if (sanitised.containsKey('Authorization')) {
      sanitised['Authorization'] = 'Bearer ***';
    }
    return sanitised;
  }
}

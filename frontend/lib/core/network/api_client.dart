import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// Dio-backed HTTP client with:
///  - automatic Bearer token attachment,
///  - silent refresh-and-retry on 401 (single retry),
///  - mapping of the backend error envelope to typed [ApiException],
///  - a session-expired callback so the UI can route back to login.
class ApiClient {
  ApiClient(this._tokens) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'Accept': 'application/json'},
      ),
    );
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  final TokenStorage _tokens;
  late final Dio _dio;

  /// Called when the refresh token is unusable (session must end).
  void Function()? onSessionExpired;

  Dio get dio => _dio;

  Future<void> _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Never override an explicitly supplied Authorization header.
    if (options.headers.containsKey('Authorization')) {
      handler.next(options);
      return;
    }
    final token = await _tokens.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode ?? 0;
    final path = err.requestOptions.path;

    // Try a single silent refresh for 401s (never for the refresh itself).
    if (status == 401 && path != '/api/auth/refresh' && err.requestOptions.extra['retried'] != true) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final opts = err.requestOptions;
        opts.extra['retried'] = true;
        final token = await _tokens.accessToken;
        opts.headers['Authorization'] = 'Bearer $token';
        try {
          final response = await _dio.fetch(opts);
          handler.resolve(response);
          return;
        } on DioException catch (e) {
          handler.next(e);
          return;
        }
      } else {
        _tokens.clear();
        onSessionExpired?.call();
        handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            response: err.response,
            error: SessionExpiredException(),
            type: DioExceptionType.unknown,
          ),
        );
        return;
      }
    }

    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final res = await _dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'retried': true}),
      );
      final data = res.data['data'] as Map<String, dynamic>?;
      if (data == null) return false;
      final access = data['accessToken'] as String?;
      final refresh = data['refreshToken'] as String?;
      if (access == null || refresh == null) return false;
      await _tokens.saveTokens(accessToken: access, refreshToken: refresh);
      return true;
    } on DioException {
      return false;
    }
  }

  /// Map any error to a typed [ApiException] / [NetworkException].
  Object mapError(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final res = error.response;
      if (res != null) {
        final body = res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : null;
        final errObj = (body?['error'] ?? {}) as Map<String, dynamic>;
        return ApiException(
          statusCode: res.statusCode ?? 0,
          code: (errObj['code'] as String?) ?? 'HTTP_${res.statusCode}',
          message: (errObj['message'] as String?) ?? res.statusMessage ?? 'Request failed.',
          details: (errObj['details'] as List?) ?? const [],
        );
      }
      return NetworkException(error.message ?? 'Network error.');
    }
    return NetworkException(error.toString());
  }

  /// Typed convenience for JSON endpoints (backend wraps data under `data`).
  Future<Map<String, dynamic>> getData(
    String path, {
    Map<String, dynamic>? query,
    bool Function(int code)? expectedStatus,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data?['data'] as Map<String, dynamic>? ?? (res.data ?? {});
    } catch (e) {
      throw mapError(e);
    }
  }

  /// Full body of a GET (keeps `pagination` metadata next to `data`).
  Future<Map<String, dynamic>> getEnvelope(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  /// The `data` payload of a GET, which may be a map or a list.
  Future<dynamic> getBody(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      final body = res.data as Map<String, dynamic>? ?? const {};
      return body['data'];
    } on DioException catch (e) {
      throw mapError(e);
    } on TypeError {
      throw NetworkException('Unexpected response shape for $path.');
    }
  }

  Future<dynamic> postBody(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await _dio.post<dynamic>(path, data: body);
      return (res.data as Map<String, dynamic>? ?? const {})['data'];
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  Future<dynamic> patchBody(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await _dio.patch<dynamic>(path, data: body);
      return (res.data as Map<String, dynamic>? ?? const {})['data'];
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  Future<dynamic> deleteBody(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await _dio.delete<dynamic>(path, data: body);
      return (res.data as Map<String, dynamic>? ?? const {})['data'];
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  Future<dynamic> putAsBody(String path, {Map<String, dynamic>? body}) async {
    try {
      final res = await _dio.put<dynamic>(path, data: body);
      return (res.data as Map<String, dynamic>? ?? const {})['data'];
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  /// Multipart upload via Dio (bytes are used uniformly on web and desktop).
  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, dynamic>? fields,
  }) async {
    try {
      final form = FormData();
      form.files.add(MapEntry(
        'file',
        MultipartFile.fromBytes(bytes, filename: filename, contentType: MediaType.parse(contentType)),
      ));
      fields?.forEach((k, v) => form.fields.add(MapEntry(k, v.toString())));
      final res = await _dio.post<Map<String, dynamic>>(path, data: form);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw mapError(e);
    }
  }
}
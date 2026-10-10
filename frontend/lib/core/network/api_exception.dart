/// Typed API error mapped from the backend error envelope:
/// `{ success: false, error: { code, message, details? } }`.
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const [],
  });

  final int statusCode;
  final String code;
  final String message;
  final List<dynamic> details;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isValidation => statusCode == 400;
  bool get isAuthorizationFailure => isUnauthorized || isForbidden;

  @override
  String toString() => 'ApiException($statusCode $code): $message';
}

/// Raised by the Dio interceptor when a refresh attempt itself fails, forcing
/// the session to end.
class SessionExpiredException extends ApiException {
  SessionExpiredException()
      : super(statusCode: 401, code: 'SESSION_EXPIRED', message: 'Session expired. Please sign in again.');
}

/// A network-level failure (server unreachable, timeout, etc).
class NetworkException implements Exception {
  NetworkException(this.message);
  final String message;

  @override
  String toString() => 'NetworkException: $message';
}
import 'dart:convert';

import '../core/network/api_client.dart';
import '../core/network/api_exception.dart';
import '../core/storage/token_storage.dart';
import '../models/models.dart';

/// Authentication and session management against the backend API.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  /// Persists the pair and cached user so the app can bootstrap from storage.
  Future<void> persistSession(AuthData data) async {
    await _tokens.saveTokens(
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      userJson: data.user == null ? null : jsonEncode(data.user!.toJson()),
    );
  }

  Future<AuthData> login({required String email, required String password}) async {
    final data = await _api.postBody(
      '/api/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return AuthData.fromJson((data as Map<String, dynamic>? ?? const {}));
  }

  Future<AuthData> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    String role = 'patient',
    Map<String, dynamic>? doctorProfile,
    Map<String, dynamic>? patientProfile,
  }) async {
    final data = await _api.postBody(
      '/api/auth/register',
      body: {
        'email': email.trim(),
        'password': password,
        'name': name.trim(),
        'role': role,
        'phone': phone,
        'doctorProfile': ?doctorProfile,
        'patientProfile': ?patientProfile,
      },
    );
    return AuthData.fromJson((data as Map<String, dynamic>? ?? const {}));
  }

  /// Returns the development reset token when present (dev mode demo flow).
  Future<String?> forgotPassword(String email) async {
    final data = await _api.postBody('/api/auth/forgot-password', body: {'email': email.trim()});
    final map = data as Map<String, dynamic>? ?? const {};
    return (map['developmentResetToken'] as String?) ?? (map['resetToken'] as String?);
  }

  Future<void> resetPassword({required String token, required String password}) async {
    await _api.postBody('/api/auth/reset-password', body: {'token': token, 'password': password});
  }

  Future<void> logout() async {
    final refresh = await _tokens.refreshToken;
    try {
      if (refresh != null && refresh.isNotEmpty) {
        await _api.postBody('/api/auth/logout', body: {'refreshToken': refresh});
      }
    } on ApiException {
      // Even a failed logout (expired token etc.) must clear the local session.
    } finally {
      await _tokens.clear();
    }
  }

  /// Restore a cached session (tokens + user) without hitting the network.
  Future<User?> restoreSession() async {
    // Load the persisted session into memory first so the token this instance
    // sends always matches the cached user this instance displays. Without
    // this, a second app window/tab logging in would overwrite the shared
    // storage and this instance would send the wrong role's token.
    await _tokens.loadSession();
    final userJson = await _tokens.userJson;
    if (userJson == null || userJson.isEmpty || userJson == 'null') return null;
    try {
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, dynamic>) return null;
      return User.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
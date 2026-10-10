import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists auth tokens.
///
/// Uses `flutter_secure_storage` on desktop/mobile and falls back to an
/// in-memory store on web (the web implementation of the plugin stores in
/// localStorage, which is acceptable for this demo build).
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'auth.accessToken';
  static const _refreshKey = 'auth.refreshToken';
  static const _userKey = 'auth.user';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userJson,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    if (userJson != null) {
      await _storage.write(key: _userKey, value: userJson);
    }
  }

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);
  Future<String?> get userJson => _storage.read(key: _userKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }

  /// Best-effort check that a session exists (used by the splash screen).
  Future<bool> hasSession() async =>
      (await accessToken)?.isNotEmpty == true && (await refreshToken)?.isNotEmpty == true;
}
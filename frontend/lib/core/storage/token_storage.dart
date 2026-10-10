import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists auth tokens.
///
/// Uses `flutter_secure_storage` on desktop/mobile and falls back to an
/// in-memory store on web (the web implementation of the plugin stores in
/// localStorage, which is acceptable for this demo build).
///
/// **Why an in-memory mirror:** on web the plugin persists to localStorage,
/// which is shared by every tab/window of the same browser profile, and on
/// desktop it persists to the OS keychain, which is shared by every app
/// instance. Without a mirror, a second app instance that logs in would
/// overwrite the shared backend storage and the first instance would quietly
/// start sending *that* token while still showing *its* screens — producing
/// false "Your account role cannot access this resource." errors. Reading only
/// from memory (after [loadSession]) guarantees a running instance always sends
/// the token that matches the user it is displaying.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'auth.accessToken';
  static const _refreshKey = 'auth.refreshToken';
  static const _userKey = 'auth.user';

  // In-memory mirror of the persisted session (see class docs).
  String? _accessToken;
  String? _refreshToken;
  String? _user;

  /// Snapshot the persisted session into memory. Call once at bootstrap so all
  /// later reads stay bound to this instance's own session.
  Future<void> loadSession() async {
    _accessToken = await _storage.read(key: _accessKey);
    _refreshToken = await _storage.read(key: _refreshKey);
    _user = await _storage.read(key: _userKey);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userJson,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (userJson != null) {
      _user = userJson;
    }
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    if (userJson != null) {
      await _storage.write(key: _userKey, value: userJson);
    }
  }

  Future<String?> get accessToken async =>
      _accessToken ?? _storage.read(key: _accessKey);
  Future<String?> get refreshToken async =>
      _refreshToken ?? _storage.read(key: _refreshKey);
  Future<String?> get userJson async =>
      _user ?? _storage.read(key: _userKey);

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }

  /// Best-effort check that a session exists (used by the splash screen).
  Future<bool> hasSession() async =>
      (await accessToken)?.isNotEmpty == true &&
      (await refreshToken)?.isNotEmpty == true;
}
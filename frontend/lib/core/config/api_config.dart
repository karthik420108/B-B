/// App-wide configuration.
///
/// The API base URL can be overridden at build/run time with
/// `--dart-define=API_BASE_URL=https://example.com`.
class ApiConfig {
  ApiConfig._();

  /// Backend base URL. Override for deployed environments:
  /// `flutter run --dart-define=API_BASE_URL=https://api.example.com`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:4000',
  );

  /// Human-readable name of the environment, shown in the settings screen.
  static String get envLabel {
    const fromEnv = String.fromEnvironment('ENV_LABEL');
    return fromEnv.isNotEmpty ? fromEnv : 'development';
  }
}
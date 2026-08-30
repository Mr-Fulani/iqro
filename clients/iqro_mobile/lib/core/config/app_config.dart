class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.fallbackDownloadUrl,
    required this.environment,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://staging.iqro.forum',
      ),
      fallbackDownloadUrl: String.fromEnvironment(
        'APP_DOWNLOAD_URL',
        defaultValue: 'https://iqro.forum',
      ),
      environment: String.fromEnvironment('APP_ENV', defaultValue: 'staging'),
    );
  }

  final String apiBaseUrl;
  final String fallbackDownloadUrl;
  final String environment;

  String get apiV1 => '$apiBaseUrl/api/v1';
  bool get isProduction => environment == 'production';
}

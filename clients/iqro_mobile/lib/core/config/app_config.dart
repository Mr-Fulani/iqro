import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.fallbackDownloadUrl,
    required this.environment,
  });

  factory AppConfig.fromEnvironment() {
    return AppConfig.validate(
      apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
      fallbackDownloadUrl: const String.fromEnvironment(
        'APP_DOWNLOAD_URL',
        defaultValue: 'https://iqro.forum',
      ),
      environment: const String.fromEnvironment('APP_ENV'),
      releaseMode: kReleaseMode,
    );
  }

  factory AppConfig.validate({
    required String apiBaseUrl,
    required String fallbackDownloadUrl,
    required String environment,
    required bool releaseMode,
  }) {
    var resolvedEnvironment = environment.trim().toLowerCase();
    if (resolvedEnvironment.isEmpty) {
      if (releaseMode) {
        throw StateError('APP_ENV is required for release builds');
      }
      resolvedEnvironment = 'staging';
    }
    if (resolvedEnvironment != 'staging' &&
        resolvedEnvironment != 'production') {
      throw const FormatException('APP_ENV must be staging or production');
    }

    var resolvedApiBaseUrl = apiBaseUrl.trim();
    if (resolvedApiBaseUrl.isEmpty) {
      if (releaseMode) {
        throw StateError('API_BASE_URL is required for release builds');
      }
      resolvedApiBaseUrl = 'https://staging.iqro.forum';
    }
    final apiOrigin = Uri.tryParse(resolvedApiBaseUrl);
    if (apiOrigin == null ||
        apiOrigin.scheme != 'https' ||
        apiOrigin.host.isEmpty ||
        apiOrigin.hasPort ||
        apiOrigin.userInfo.isNotEmpty ||
        (apiOrigin.path.isNotEmpty && apiOrigin.path != '/') ||
        apiOrigin.hasQuery ||
        apiOrigin.hasFragment) {
      throw const FormatException(
        'API_BASE_URL must be a clean HTTPS origin without a path',
      );
    }
    final expectedHost = resolvedEnvironment == 'production'
        ? 'iqro.forum'
        : 'staging.iqro.forum';
    if (apiOrigin.host != expectedHost) {
      throw FormatException(
        'API_BASE_URL host must match the $resolvedEnvironment environment',
      );
    }

    final downloadUrl = Uri.tryParse(fallbackDownloadUrl.trim());
    if (downloadUrl == null ||
        downloadUrl.scheme != 'https' ||
        downloadUrl.host.isEmpty ||
        downloadUrl.userInfo.isNotEmpty ||
        downloadUrl.hasFragment ||
        !_downloadHosts.contains(downloadUrl.host)) {
      throw const FormatException(
        'APP_DOWNLOAD_URL must use an approved HTTPS download host',
      );
    }
    return AppConfig(
      apiBaseUrl: 'https://${apiOrigin.host}',
      fallbackDownloadUrl: downloadUrl.toString(),
      environment: resolvedEnvironment,
    );
  }

  static const _downloadHosts = <String>{
    'iqro.forum',
    'play.google.com',
    'apps.apple.com',
  };

  final String apiBaseUrl;
  final String fallbackDownloadUrl;
  final String environment;

  String get apiV1 => '$apiBaseUrl/api/v1';
  bool get isProduction => environment == 'production';
}

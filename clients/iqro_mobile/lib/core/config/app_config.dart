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
      releaseMode: kReleaseMode || kProfileMode,
      androidEmulator: defaultTargetPlatform == TargetPlatform.android,
    );
  }

  factory AppConfig.validate({
    required String apiBaseUrl,
    required String fallbackDownloadUrl,
    required String environment,
    required bool releaseMode,
    bool androidEmulator = false,
  }) {
    var resolvedEnvironment = environment.trim().toLowerCase();
    if (resolvedEnvironment.isEmpty) {
      if (releaseMode) {
        throw StateError('APP_ENV is required for release builds');
      }
      resolvedEnvironment = 'local';
    }
    if (resolvedEnvironment != 'local' &&
        resolvedEnvironment != 'staging' &&
        resolvedEnvironment != 'production') {
      throw const FormatException(
        'APP_ENV must be local, staging or production',
      );
    }
    final local = resolvedEnvironment == 'local';
    if (local && releaseMode) {
      throw const FormatException('Local API is allowed only in debug builds');
    }

    var resolvedApiBaseUrl = apiBaseUrl.trim();
    if (resolvedApiBaseUrl.isEmpty) {
      if (releaseMode) {
        throw StateError('API_BASE_URL is required for release builds');
      }
      resolvedApiBaseUrl = local
          ? 'http://${androidEmulator ? '10.0.2.2' : '127.0.0.1'}:8000'
          : 'https://staging.iqro.forum';
    }
    final apiOrigin = Uri.tryParse(resolvedApiBaseUrl);
    if (apiOrigin == null ||
        !(apiOrigin.scheme == 'https' ||
            (local && apiOrigin.scheme == 'http')) ||
        apiOrigin.host.isEmpty ||
        (!local && apiOrigin.hasPort) ||
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
    if (local
        ? !isLocalDevelopmentHost(apiOrigin.host)
        : apiOrigin.host != expectedHost) {
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
      apiBaseUrl: apiOrigin.origin,
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
  bool get isLocal => environment == 'local';
}

bool isLocalDevelopmentHost(String host) {
  if (host == 'localhost' ||
      host == '::1' ||
      host == '[::1]' ||
      host.endsWith('.local')) {
    return true;
  }
  final parts = host.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
    return false;
  }
  return parts[0] == 127 ||
      parts[0] == 10 ||
      (parts[0] == 192 && parts[1] == 168) ||
      (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
}

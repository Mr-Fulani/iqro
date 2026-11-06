import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/network/api_client.dart';

/// The newest build named in the admin (`/app/release`): the fallback for when
/// Google Play has not told this phone about an update yet, which can take a day.
abstract interface class AppReleaseSource {
  /// Null when unknown: no network, or 0 («не проверять») in the admin.
  Future<int?> latestAndroidVersionCode();

  /// This build's code, the number in brackets of «1.0.5 (6)».
  Future<int?> installedVersionCode();
}

class ApiAppReleaseSource implements AppReleaseSource {
  ApiAppReleaseSource(this._api);

  final ApiClient _api;

  @override
  Future<int?> latestAndroidVersionCode() async {
    try {
      final payload = await _api.get('/app/release', public: true);
      final code = payload is Map ? payload['android_version_code'] : null;
      return code is int && code > 0 ? code : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<int?> installedVersionCode() async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } on Object {
      return null;
    }
  }
}

/// «1.0.5 (6)»: the version and, in brackets, the build code testers compare
/// with Google Play.
final appVersionLabelProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version} (${info.buildNumber})';
  } on Object {
    return null;
  }
});

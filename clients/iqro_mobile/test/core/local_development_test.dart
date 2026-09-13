import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/public_asset_uri.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cleartext network permission is confined to debug platform configuration',
    () {
      final debug = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();
      final release = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(debug, contains('android:usesCleartextTraffic="true"'));
      expect(release, contains('android:usesCleartextTraffic="false"'));
      final iosDebug = File('ios/Runner/Info-Debug.plist').readAsStringSync();
      final iosRelease = File('ios/Runner/Info.plist').readAsStringSync();
      expect(iosDebug, contains('<key>NSAllowsLocalNetworking</key>'));
      expect(iosRelease, isNot(contains('<key>NSAllowsArbitraryLoads</key>')));
      expect(iosRelease, isNot(contains('<key>NSAllowsLocalNetworking</key>')));
    },
  );
  AppConfig config(
    String origin, {
    bool release = false,
    bool android = false,
  }) => AppConfig.validate(
    apiBaseUrl: origin,
    environment: 'local',
    fallbackDownloadUrl: 'https://iqro.forum',
    releaseMode: release,
    androidEmulator: android,
  );

  test(
    'local default addresses distinguish Android emulator and iOS simulator',
    () {
      expect(config('', android: true).apiV1, 'http://10.0.2.2:8000/api/v1');
      expect(config('').apiV1, 'http://127.0.0.1:8000/api/v1');
      expect(config('http://192.168.1.20:8000').isLocal, isTrue);
      expect(config('http://[::1]:8000').apiBaseUrl, 'http://[::1]:8000');
      expect(
        () => config('http://localhost:8000', release: true),
        throwsFormatException,
      );
    },
  );

  test(
    'local API does not authorize public cleartext origins or URL credentials',
    () {
      for (final origin in [
        'http://example.com:8000',
        'http://8.8.8.8:8000',
        'http://172.32.1.1:8000',
        'http://192.168.1.300:8000',
        'http://user:pass@localhost:8000',
        'http://localhost:8000/api',
        'http://localhost:8000?token=secret',
      ]) {
        expect(() => config(origin), throwsFormatException, reason: origin);
      }
    },
  );

  test('relative media resolves to device API origin and cannot escape it', () {
    final base = Uri.parse('http://10.0.2.2:8000/api/v1');
    final image = resolvePublicAssetUri('/media/mushafs/p1.webp', base);
    expect(image.toString(), 'http://10.0.2.2:8000/media/mushafs/p1.webp');
    expect(
      isApprovedPublicAssetUri(image, allowedHosts: {}, localApiBase: base),
      isTrue,
    );
    expect(isApprovedPublicAssetUri(image, allowedHosts: {}), isFalse);
    for (final address in [
      'http://10.0.2.2:8001/media/p.webp',
      'http://127.0.0.1:8000/media/p.webp',
      'http://10.0.2.2:8000/admin/',
      'http://10.0.2.2:8000/media/p.webp?token=x',
      'http://user:pass@10.0.2.2:8000/media/p.webp',
    ]) {
      expect(
        isApprovedPublicAssetUri(
          Uri.parse(address),
          allowedHosts: {},
          localApiBase: base,
        ),
        isFalse,
        reason: address,
      );
    }
    expect(
      isApprovedPublicAssetUri(
        Uri.parse('https://media.iqro.forum/p.webp'),
        allowedHosts: {'media.iqro.forum'},
      ),
      isTrue,
    );
  });

  test(
    'old visual preference migrates without touching reading preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = PreferencesStore(preferences);
      await store.write(
        store.read().copyWith(mushafVariant: 'scan', locale: 'tr'),
      );
      expect(store.read().mushafVariant, defaultMushafVariant);
      expect(store.read().locale, 'tr');
      expect(MushafIdentity.fromPreference('scan'), MushafIdentity.primary);
      expect(
        MushafIdentity.primary.apiPath,
        '/quran/mushaf-renditions/kfgqpc-hafs',
      );
    },
  );
}

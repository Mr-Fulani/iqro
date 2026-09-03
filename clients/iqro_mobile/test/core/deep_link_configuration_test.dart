import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/router.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';

void main() {
  test('Dua links use the stable collection identity', () {
    const entry = DuaEntry(
      id: '0192d920-4cb5-7e72-9a4d-000000000007',
      sourceNumber: 7,
      collection: 'hisn-al-muslim',
      categoryTitle: 'Morning',
      arabicText: 'دعاء',
      meaning: '',
      transliteration: '',
      repetitions: 1,
      sourceLabel: '',
    );

    expect(duaEntryRoute(entry), '/dua/hisn-al-muslim/7');
    expect(isDuaEntryId(entry.id), isTrue);
    expect(isDuaEntryId('waking-up'), isFalse);
  });

  test('Android accepts custom and verified HTTPS Dua links', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:name="android.intent.action.VIEW"'));
    expect(manifest, contains('android:name="flutter_deeplinking_enabled"'));
    expect(manifest, contains('android:scheme="iqro"'));
    expect(manifest, contains('android:host="open"'));
    expect(manifest, contains('android:host="iqro.forum"'));
    expect(manifest, contains('android:host="staging.iqro.forum"'));
    expect(manifest, contains('android:pathPrefix="/dua/"'));
    for (final locale in const <String>['ru', 'en', 'ar', 'tr']) {
      expect(manifest, contains('android:pathPrefix="/$locale/dua/"'));
    }
    expect(RegExp(r'android:autoVerify="true"').allMatches(manifest).length, 2);
  });

  test('localized web Dua links normalize to cold mobile routes', () {
    for (final locale in const <String>['ru', 'en', 'ar', 'tr']) {
      expect(
        normalizeLocalizedDuaDeepLink(
          Uri.parse('https://staging.iqro.forum/$locale/dua/hisn-al-muslim/7'),
        ),
        '/dua/hisn-al-muslim/7',
      );
      expect(
        normalizeLocalizedDuaDeepLink(
          Uri.parse(
            'https://iqro.forum/$locale/dua/hisn-al-muslim/categories/morning',
          ),
        ),
        '/dua/hisn-al-muslim/categories/morning',
      );
      expect(
        normalizeLocalizedDuaDeepLink(
          Uri.parse('https://iqro.forum/$locale/dua/waking-up'),
        ),
        '/dua/waking-up',
      );
    }
    expect(
      normalizeLocalizedDuaDeepLink(
        Uri.parse('https://iqro.forum/fr/dua/hisn-al-muslim/7'),
      ),
      isNull,
    );
  });

  test('iOS accepts the IQRO scheme and declares both associated domains', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    expect(plist, contains('<string>iqro</string>'));
    expect(plist, contains('<key>FlutterDeepLinkingEnabled</key>'));
    expect(entitlements, contains('<string>applinks:iqro.forum</string>'));
    expect(
      entitlements,
      contains('<string>applinks:staging.iqro.forum</string>'),
    );
    expect(
      RegExp(
        r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;',
      ).allMatches(project).length,
      3,
    );
  });
}

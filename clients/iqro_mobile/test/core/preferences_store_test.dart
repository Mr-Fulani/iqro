import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'supported Mushaf choices persist and unknown choices migrate',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = PreferencesStore(await SharedPreferences.getInstance());
      const value = AppPreferences(
        onboardingComplete: true,
        locale: 'ar',
        themeMode: ThemeMode.dark,
        readerMode: ReaderMode.mushaf,
        mushafVariant: '5',
        goal: 'reading',
        dailyUnit: DailyUnit.ayahs,
        dailyTarget: 12,
      );

      await store.write(value);
      final restored = store.read();

      expect(restored.locale, 'ar');
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.readerMode, ReaderMode.mushaf);
      expect(restored.mushafVariant, '5');
      expect(restored.dailyTarget, 12);

      await store.write(value.copyWith(mushafVariant: '11'));
      expect(store.read().mushafVariant, defaultMushafVariant);
    },
  );
}

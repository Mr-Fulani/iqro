import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native Mushaf preference persists without touching recitation or haptics',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = PreferencesStore(await SharedPreferences.getInstance());
      await store.write(
        store.read().copyWith(
          mushafVariant: 'native:qcf-v2-hafs',
          preferredRecitationId: 'chosen-reciter',
          readerHaptics: true,
        ),
      );
      expect(store.read().mushafVariant, 'native:qcf-v2-hafs');
      expect(store.read().preferredRecitationId, 'chosen-reciter');
      expect(store.read().readerHaptics, isTrue);
      for (final invalid in [
        'native:../page',
        'native:',
        'native:a/b',
        'native:A',
        'native:a?b',
      ]) {
        await store.write(store.read().copyWith(mushafVariant: invalid));
        expect(store.read().mushafVariant, defaultMushafVariant);
      }
    },
  );

  test(
    'Hijri adjustment is bounded and persists independently of locale',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'hijri_adjustment': 50,
      });
      final store = PreferencesStore(await SharedPreferences.getInstance());
      expect(store.read().hijriAdjustment, 2);
      await store.write(
        store.read().copyWith(hijriAdjustment: -1, locale: 'ar'),
      );
      expect(store.read().hijriAdjustment, -1);
    },
  );

  test('page haptics default on and an explicit opt-out persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = PreferencesStore(await SharedPreferences.getInstance());
    expect(store.read().readerHaptics, isTrue);
    await store.write(store.read().copyWith(readerHaptics: false));
    expect(store.read().readerHaptics, isFalse);
  });

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
        readerArabicFontSize: 36,
        readerLineHeight: 2.2,
        readerAyahSpacing: 16,
        readerFocusMode: true,
        preferredTranslationSourceId: 45,
        preferredTafsirSourceId: 170,
        preferredRecitationId: 'recitation-id',
        preferredAudioQuality: 'high',
      );

      await store.write(value);
      final restored = store.read();

      expect(restored.locale, 'ar');
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.readerMode, ReaderMode.mushaf);
      expect(restored.mushafVariant, defaultMushafVariant);
      expect(restored.dailyTarget, 12);
      expect(restored.readerArabicFontSize, 36);
      expect(restored.readerLineHeight, 2.2);
      expect(restored.readerAyahSpacing, 16);
      expect(restored.readerFocusMode, isTrue);
      expect(restored.preferredTranslationSourceId, 45);
      expect(restored.preferredTafsirSourceId, 170);
      expect(restored.preferredRecitationId, 'recitation-id');
      expect(restored.preferredAudioQuality, 'high');

      await store.write(value.copyWith(mushafVariant: '11'));
      expect(store.read().mushafVariant, defaultMushafVariant);
    },
  );

  test('reader typography safely clamps malformed stored values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_arabic_font_size': 200.0,
      'reader_line_height': -3.0,
      'reader_ayah_spacing': double.nan,
    });
    final store = PreferencesStore(await SharedPreferences.getInstance());

    final restored = store.read();

    expect(restored.readerArabicFontSize, maxReaderArabicFontSize);
    expect(restored.readerLineHeight, minReaderLineHeight);
    expect(restored.readerAyahSpacing, defaultReaderAyahSpacing);
    expect(restored.readerFocusMode, isFalse);
  });

  test('unknown audio quality falls back to automatic selection', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'audio_quality': 'unpublished-ultra',
    });
    final store = PreferencesStore(await SharedPreferences.getInstance());

    expect(store.read().preferredAudioQuality, defaultPreferredAudioQuality);
  });

  test(
    'recitation preferences migrate independently after the legacy fallback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reader_recitation_id': 'legacy-recitation',
      });
      final store = PreferencesStore(await SharedPreferences.getInstance());

      final migrated = store.read();
      expect(migrated.listeningRecitationId, 'legacy-recitation');
      expect(migrated.mushafRecitationId, 'legacy-recitation');
      expect(migrated.memorizationDefaultRecitationId, 'legacy-recitation');

      await store.write(
        migrated.copyWith(
          listeningRecitationId: 'listening-recitation',
          mushafRecitationId: 'mushaf-recitation',
          memorizationDefaultRecitationId: 'memorization-recitation',
        ),
      );

      expect(store.read().listeningRecitationId, 'listening-recitation');
      expect(store.read().mushafRecitationId, 'mushaf-recitation');
      expect(
        store.read().memorizationDefaultRecitationId,
        'memorization-recitation',
      );

      await store.write(
        store.read().copyWith(
          memorizationDefaultRecitationId: 'memorization-2',
        ),
      );
      expect(store.read().listeningRecitationId, 'listening-recitation');
      expect(store.read().mushafRecitationId, 'mushaf-recitation');
      expect(store.read().memorizationDefaultRecitationId, 'memorization-2');
    },
  );

  test('recitation choices are isolated by account and role', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_recitation_id': 'legacy-recitation',
    });
    final store = PreferencesStore(await SharedPreferences.getInstance());

    await store.migrateLegacyRecitationsForUser('user-a');
    expect(
      store.readForAccount('user-a').listeningRecitationId,
      'legacy-recitation',
    );
    expect(store.readForAccount('user-b').listeningRecitationId, isNull);
    expect(store.readForAccount(null).mushafRecitationId, isNull);

    await store.writeAccountRecitation(
      'user-a',
      RecitationPreferenceRole.listening,
      'audio-a',
    );
    await store.writeAccountRecitation(
      'user-a',
      RecitationPreferenceRole.mushaf,
      'mushaf-a',
    );
    await store.writeAccountRecitation(
      'user-a',
      RecitationPreferenceRole.memorization,
      'memory-a',
    );
    await store.writeAccountRecitation(
      'user-b',
      RecitationPreferenceRole.listening,
      'audio-b',
    );
    await store.migrateLegacyRecitationsForUser('user-b');

    final a = store.readForAccount('user-a');
    final b = store.readForAccount('user-b');
    expect(a.listeningRecitationId, 'audio-a');
    expect(a.mushafRecitationId, 'mushaf-a');
    expect(a.memorizationDefaultRecitationId, 'memory-a');
    expect(b.listeningRecitationId, 'audio-b');
    expect(b.mushafRecitationId, isNull);
    expect(b.memorizationDefaultRecitationId, isNull);

    await store.writeAccountRecitation(
      'user-c',
      RecitationPreferenceRole.listening,
      'audio-c',
    );
    await store.transferAccountRecitations('user-a', 'user-c');
    final c = store.readForAccount('user-c');
    expect(c.listeningRecitationId, 'audio-c');
    expect(c.mushafRecitationId, 'mushaf-a');
    expect(c.memorizationDefaultRecitationId, 'memory-a');
  });
}

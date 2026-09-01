import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderMode { text, mushaf }

enum DailyUnit { minutes, pages, ayahs }

class AppPreferences {
  const AppPreferences({
    required this.onboardingComplete,
    required this.locale,
    required this.themeMode,
    required this.readerMode,
    required this.mushafVariant,
    required this.goal,
    required this.dailyUnit,
    required this.dailyTarget,
    this.preferredTranslationSourceId,
    this.preferredTafsirSourceId,
    this.preferredRecitationId,
  });

  const AppPreferences.defaults()
    : onboardingComplete = false,
      locale = 'ru',
      themeMode = ThemeMode.system,
      readerMode = ReaderMode.text,
      mushafVariant = defaultMushafVariant,
      goal = 'reading',
      dailyUnit = DailyUnit.pages,
      dailyTarget = 6,
      preferredTranslationSourceId = null,
      preferredTafsirSourceId = null,
      preferredRecitationId = null;

  final bool onboardingComplete;
  final String locale;
  final ThemeMode themeMode;
  final ReaderMode readerMode;
  final String mushafVariant;
  final String goal;
  final DailyUnit dailyUnit;
  final int dailyTarget;
  final int? preferredTranslationSourceId;
  final int? preferredTafsirSourceId;
  final String? preferredRecitationId;

  AppPreferences copyWith({
    bool? onboardingComplete,
    String? locale,
    ThemeMode? themeMode,
    ReaderMode? readerMode,
    String? mushafVariant,
    String? goal,
    DailyUnit? dailyUnit,
    int? dailyTarget,
    int? preferredTranslationSourceId,
    int? preferredTafsirSourceId,
    String? preferredRecitationId,
  }) {
    return AppPreferences(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      locale: locale ?? this.locale,
      themeMode: themeMode ?? this.themeMode,
      readerMode: readerMode ?? this.readerMode,
      mushafVariant: mushafVariant ?? this.mushafVariant,
      goal: goal ?? this.goal,
      dailyUnit: dailyUnit ?? this.dailyUnit,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      preferredTranslationSourceId:
          preferredTranslationSourceId ?? this.preferredTranslationSourceId,
      preferredTafsirSourceId:
          preferredTafsirSourceId ?? this.preferredTafsirSourceId,
      preferredRecitationId:
          preferredRecitationId ?? this.preferredRecitationId,
    );
  }
}

class PreferencesStore {
  PreferencesStore(this._preferences);

  static const supportedLocales = <String>{'ru', 'en', 'ar', 'tr'};
  // Additional Mushafs become selectable only after the backend publishes
  // verified native page assets and hit maps for the mobile client.
  static const supportedMushafVariants = <String>{defaultMushafVariant};
  final SharedPreferences _preferences;

  AppPreferences read() {
    final locale = _preferences.getString('locale') ?? 'ru';
    return AppPreferences(
      onboardingComplete: _preferences.getBool('onboarding_complete') ?? false,
      locale: supportedLocales.contains(locale) ? locale : 'ru',
      themeMode: _themeFromName(
        _preferences.getString('theme_mode') ?? 'system',
      ),
      readerMode: _preferences.getString('reader_mode') == 'mushaf'
          ? ReaderMode.mushaf
          : ReaderMode.text,
      mushafVariant: _mushafVariant(_preferences.getString('mushaf_variant')),
      goal: _preferences.getString('primary_goal') ?? 'reading',
      dailyUnit: _unitFromName(_preferences.getString('daily_unit') ?? 'pages'),
      dailyTarget: _preferences.getInt('daily_target') ?? 6,
      preferredTranslationSourceId: _preferences.getInt(
        'reader_translation_source_id',
      ),
      preferredTafsirSourceId: _preferences.getInt('reader_tafsir_source_id'),
      preferredRecitationId: _preferences.getString('reader_recitation_id'),
    );
  }

  Future<void> write(AppPreferences value) async {
    await Future.wait(<Future<bool>>[
      _preferences.setBool('onboarding_complete', value.onboardingComplete),
      _preferences.setString('locale', value.locale),
      _preferences.setString('theme_mode', value.themeMode.name),
      _preferences.setString('reader_mode', value.readerMode.name),
      _preferences.setString('mushaf_variant', value.mushafVariant),
      _preferences.setString('primary_goal', value.goal),
      _preferences.setString('daily_unit', value.dailyUnit.name),
      _preferences.setInt('daily_target', value.dailyTarget),
      if (value.preferredTranslationSourceId != null)
        _preferences.setInt(
          'reader_translation_source_id',
          value.preferredTranslationSourceId!,
        ),
      if (value.preferredTafsirSourceId != null)
        _preferences.setInt(
          'reader_tafsir_source_id',
          value.preferredTafsirSourceId!,
        ),
      if (value.preferredRecitationId != null)
        _preferences.setString(
          'reader_recitation_id',
          value.preferredRecitationId!,
        ),
    ]);
  }

  static ThemeMode _themeFromName(String value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  static DailyUnit _unitFromName(String value) {
    return DailyUnit.values.firstWhere(
      (unit) => unit.name == value,
      orElse: () => DailyUnit.pages,
    );
  }

  static String _mushafVariant(String? value) {
    return supportedMushafVariants.contains(value)
        ? value!
        : defaultMushafVariant;
  }
}

const defaultMushafVariant = 'scan';

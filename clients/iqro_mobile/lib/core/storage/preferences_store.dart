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
  });

  const AppPreferences.defaults()
    : onboardingComplete = false,
      locale = 'ru',
      themeMode = ThemeMode.system,
      readerMode = ReaderMode.text,
      mushafVariant = defaultMushafVariant,
      goal = 'reading',
      dailyUnit = DailyUnit.pages,
      dailyTarget = 6;

  final bool onboardingComplete;
  final String locale;
  final ThemeMode themeMode;
  final ReaderMode readerMode;
  final String mushafVariant;
  final String goal;
  final DailyUnit dailyUnit;
  final int dailyTarget;

  AppPreferences copyWith({
    bool? onboardingComplete,
    String? locale,
    ThemeMode? themeMode,
    ReaderMode? readerMode,
    String? mushafVariant,
    String? goal,
    DailyUnit? dailyUnit,
    int? dailyTarget,
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
    );
  }
}

class PreferencesStore {
  PreferencesStore(this._preferences);

  static const supportedLocales = <String>{'ru', 'en', 'ar', 'tr'};
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
      mushafVariant:
          _preferences.getString('mushaf_variant') ?? defaultMushafVariant,
      goal: _preferences.getString('primary_goal') ?? 'reading',
      dailyUnit: _unitFromName(_preferences.getString('daily_unit') ?? 'pages'),
      dailyTarget: _preferences.getInt('daily_target') ?? 6,
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
}

const defaultMushafVariant = 'scan';

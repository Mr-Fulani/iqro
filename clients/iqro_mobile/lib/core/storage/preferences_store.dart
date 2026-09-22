import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderMode { text, mushaf }

enum DailyUnit { minutes, pages, ayahs }

const defaultReaderArabicFontSize = 30.0;
const minReaderArabicFontSize = 24.0;
const maxReaderArabicFontSize = 40.0;
const defaultReaderLineHeight = 1.9;
const minReaderLineHeight = 1.5;
const maxReaderLineHeight = 2.4;
const defaultReaderAyahSpacing = 10.0;
const minReaderAyahSpacing = 4.0;
const maxReaderAyahSpacing = 20.0;
const defaultPreferredAudioQuality = 'auto';
const supportedAudioQualityPreferences = <String>{
  defaultPreferredAudioQuality,
  'economy',
  'standard',
  'high',
};

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
    this.readerArabicFontSize = defaultReaderArabicFontSize,
    this.readerLineHeight = defaultReaderLineHeight,
    this.readerAyahSpacing = defaultReaderAyahSpacing,
    this.readerFocusMode = false,
    this.readerHaptics = true,
    this.hijriAdjustment = 0,
    this.preferredTranslationSourceId,
    this.preferredTafsirSourceId,
    this.preferredRecitationId,
    this.listeningRecitationId,
    this.mushafRecitationId,
    this.memorizationDefaultRecitationId,
    this.preferredAudioQuality = defaultPreferredAudioQuality,
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
      readerArabicFontSize = defaultReaderArabicFontSize,
      readerLineHeight = defaultReaderLineHeight,
      readerAyahSpacing = defaultReaderAyahSpacing,
      readerFocusMode = false,
      readerHaptics = true,
      hijriAdjustment = 0,
      preferredTranslationSourceId = null,
      preferredTafsirSourceId = null,
      preferredRecitationId = null,
      listeningRecitationId = null,
      mushafRecitationId = null,
      memorizationDefaultRecitationId = null,
      preferredAudioQuality = defaultPreferredAudioQuality;

  final bool onboardingComplete;
  final String locale;
  final ThemeMode themeMode;
  final ReaderMode readerMode;
  final String mushafVariant;
  final String goal;
  final DailyUnit dailyUnit;
  final int dailyTarget;
  final double readerArabicFontSize;
  final double readerLineHeight;
  final double readerAyahSpacing;
  final bool readerFocusMode;
  final bool readerHaptics;
  final int hijriAdjustment;
  final int? preferredTranslationSourceId;
  final int? preferredTafsirSourceId;

  /// Legacy alias kept for old callers and persisted clients.
  ///
  /// New code must use [listeningRecitationId], [mushafRecitationId], or
  /// [memorizationDefaultRecitationId] according to the playback role.
  final String? preferredRecitationId;
  final String? listeningRecitationId;
  final String? mushafRecitationId;
  final String? memorizationDefaultRecitationId;
  final String preferredAudioQuality;

  AppPreferences copyWith({
    bool? onboardingComplete,
    String? locale,
    ThemeMode? themeMode,
    ReaderMode? readerMode,
    String? mushafVariant,
    String? goal,
    DailyUnit? dailyUnit,
    int? dailyTarget,
    double? readerArabicFontSize,
    double? readerLineHeight,
    double? readerAyahSpacing,
    bool? readerFocusMode,
    bool? readerHaptics,
    int? hijriAdjustment,
    int? preferredTranslationSourceId,
    int? preferredTafsirSourceId,
    String? preferredRecitationId,
    String? listeningRecitationId,
    String? mushafRecitationId,
    String? memorizationDefaultRecitationId,
    String? preferredAudioQuality,
  }) {
    final nextListening =
        listeningRecitationId ??
        preferredRecitationId ??
        this.listeningRecitationId;
    return AppPreferences(
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      locale: locale ?? this.locale,
      themeMode: themeMode ?? this.themeMode,
      readerMode: readerMode ?? this.readerMode,
      mushafVariant: mushafVariant ?? this.mushafVariant,
      goal: goal ?? this.goal,
      dailyUnit: dailyUnit ?? this.dailyUnit,
      dailyTarget: dailyTarget ?? this.dailyTarget,
      readerArabicFontSize: readerArabicFontSize ?? this.readerArabicFontSize,
      readerLineHeight: readerLineHeight ?? this.readerLineHeight,
      readerAyahSpacing: readerAyahSpacing ?? this.readerAyahSpacing,
      readerFocusMode: readerFocusMode ?? this.readerFocusMode,
      readerHaptics: readerHaptics ?? this.readerHaptics,
      hijriAdjustment: (hijriAdjustment ?? this.hijriAdjustment).clamp(-2, 2),
      preferredTranslationSourceId:
          preferredTranslationSourceId ?? this.preferredTranslationSourceId,
      preferredTafsirSourceId:
          preferredTafsirSourceId ?? this.preferredTafsirSourceId,
      preferredRecitationId: preferredRecitationId ?? nextListening,
      listeningRecitationId: nextListening,
      mushafRecitationId: mushafRecitationId ?? this.mushafRecitationId,
      memorizationDefaultRecitationId:
          memorizationDefaultRecitationId ??
          this.memorizationDefaultRecitationId,
      preferredAudioQuality:
          preferredAudioQuality ?? this.preferredAudioQuality,
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
    final legacyRecitationId = _preferences.getString('reader_recitation_id');
    final listeningRecitationId =
        _preferences.getString('audio_listening_recitation_id') ??
        legacyRecitationId;
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
      readerArabicFontSize: _boundedDouble(
        'reader_arabic_font_size',
        defaultReaderArabicFontSize,
        minReaderArabicFontSize,
        maxReaderArabicFontSize,
      ),
      readerLineHeight: _boundedDouble(
        'reader_line_height',
        defaultReaderLineHeight,
        minReaderLineHeight,
        maxReaderLineHeight,
      ),
      readerAyahSpacing: _boundedDouble(
        'reader_ayah_spacing',
        defaultReaderAyahSpacing,
        minReaderAyahSpacing,
        maxReaderAyahSpacing,
      ),
      readerFocusMode: _preferences.getBool('reader_focus_mode') ?? false,
      readerHaptics: _preferences.getBool('reader_haptics') ?? true,
      hijriAdjustment: (_preferences.getInt('hijri_adjustment') ?? 0).clamp(
        -2,
        2,
      ),
      preferredTranslationSourceId: _preferences.getInt(
        'reader_translation_source_id',
      ),
      preferredTafsirSourceId: _preferences.getInt('reader_tafsir_source_id'),
      // Migrate the old single choice to each role exactly once by using it
      // as the fallback. Subsequent writes persist independent values.
      preferredRecitationId: listeningRecitationId,
      listeningRecitationId: listeningRecitationId,
      mushafRecitationId:
          _preferences.getString('mushaf_recitation_id') ?? legacyRecitationId,
      memorizationDefaultRecitationId:
          _preferences.getString('memorization_recitation_id') ??
          legacyRecitationId,
      preferredAudioQuality: _audioQuality(
        _preferences.getString('audio_quality'),
      ),
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
      _preferences.setDouble(
        'reader_arabic_font_size',
        value.readerArabicFontSize,
      ),
      _preferences.setDouble('reader_line_height', value.readerLineHeight),
      _preferences.setDouble('reader_ayah_spacing', value.readerAyahSpacing),
      _preferences.setBool('reader_focus_mode', value.readerFocusMode),
      _preferences.setBool('reader_haptics', value.readerHaptics),
      _preferences.setInt(
        'hijri_adjustment',
        value.hijriAdjustment.clamp(-2, 2),
      ),
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
      if (value.listeningRecitationId != null)
        _preferences.setString(
          'audio_listening_recitation_id',
          value.listeningRecitationId!,
        ),
      if (value.mushafRecitationId != null)
        _preferences.setString(
          'mushaf_recitation_id',
          value.mushafRecitationId!,
        ),
      if (value.memorizationDefaultRecitationId != null)
        _preferences.setString(
          'memorization_recitation_id',
          value.memorizationDefaultRecitationId!,
        ),
      _preferences.setString('audio_quality', value.preferredAudioQuality),
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

  double _boundedDouble(
    String key,
    double fallback,
    double minimum,
    double maximum,
  ) {
    final raw = _preferences.get(key);
    if (raw is! num || !raw.toDouble().isFinite) return fallback;
    return raw.toDouble().clamp(minimum, maximum).toDouble();
  }

  static String _mushafVariant(String? value) {
    return supportedMushafVariants.contains(value) ||
            (value != null &&
                value.length <= 71 &&
                RegExp(r'^native:[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value))
        ? value!
        : defaultMushafVariant;
  }

  static String _audioQuality(String? value) {
    return supportedAudioQualityPreferences.contains(value)
        ? value!
        : defaultPreferredAudioQuality;
  }
}

const defaultMushafVariant = 'auto';

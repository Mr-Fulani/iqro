import 'package:flutter/foundation.dart';

/// «Learn» shows every text; «Practice» keeps the image, the Arabic text and
/// the audio only.
enum SalahMode { learn, practice }

/// What the step player shows. It lasts for the app session.
@immutable
class SalahDisplay {
  const SalahDisplay({
    this.mode = SalahMode.learn,
    this.showArabic = true,
    this.showTransliteration = true,
    this.showTranslation = true,
  });

  final SalahMode mode;
  final bool showArabic;
  final bool showTransliteration;
  final bool showTranslation;

  bool get learning => mode == SalahMode.learn;

  // Practice still shows the Arabic text: it is what is being practised.
  bool get arabicVisible => showArabic || !learning;
  bool get transliterationVisible => learning && showTransliteration;
  bool get translationVisible => learning && showTranslation;

  SalahDisplay copyWith({
    SalahMode? mode,
    bool? showArabic,
    bool? showTransliteration,
    bool? showTranslation,
  }) => SalahDisplay(
    mode: mode ?? this.mode,
    showArabic: showArabic ?? this.showArabic,
    showTransliteration: showTransliteration ?? this.showTransliteration,
    showTranslation: showTranslation ?? this.showTranslation,
  );

  @override
  bool operator ==(Object other) =>
      other is SalahDisplay &&
      other.mode == mode &&
      other.showArabic == showArabic &&
      other.showTransliteration == showTransliteration &&
      other.showTranslation == showTranslation;

  @override
  int get hashCode =>
      Object.hash(mode, showArabic, showTransliteration, showTranslation);
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Amiri Quran is bundled with its OFL license', () async {
    final font = await rootBundle.load('assets/fonts/AmiriQuran-Regular.ttf');
    await (FontLoader(
      IqroTheme.arabicFontFamily,
    )..addFont(Future.value(font))).load();

    final license = await rootBundle.loadString(
      'assets/fonts/AmiriQuran-OFL.txt',
    );
    expect(license, contains('SIL Open Font License, Version 1.1'));
  });

  test('serif headings fall back to Amiri Quran for Arabic glyphs', () {
    for (final theme in [IqroTheme.light(), IqroTheme.dark()]) {
      for (final style in [
        theme.textTheme.displaySmall,
        theme.textTheme.headlineMedium,
      ]) {
        expect(style?.fontFamilyFallback, [IqroTheme.arabicFontFamily]);
      }
    }
  });
}

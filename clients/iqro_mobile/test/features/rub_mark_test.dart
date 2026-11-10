import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/quran/quran_models.dart';
import 'package:iqro_mobile/features/quran/rub_mark.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

QuranDivision _rub(int number, int surah, int ayah) => QuranDivision(
  number: number,
  startAyah: QuranAyahReference(id: '', surah: surah, ayah: ayah),
  endAyah: QuranAyahReference(id: '', surah: surah, ayah: ayah + 1),
  startPage: 1,
  endPage: 1,
  hizbNumber: (number - 1) ~/ 4 + 1,
  quarterNumber: (number - 1) % 4 + 1,
);

QuranAyahReference _ayah(int surah, int ayah) =>
    QuranAyahReference(id: '', surah: surah, ayah: ayah);

void main() {
  test('labels name the juz, the hizb and its quarters', () async {
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    // Hizb 9 opens juz 5 (4:24); its quarters start at 4:36, 4:58, 4:74.
    expect(rubMarkLabel(ru, _rub(33, 4, 24)), 'Джуз 5');
    expect(rubMarkLabel(ru, _rub(34, 4, 36)), '¼ Хизб 9');
    expect(rubMarkLabel(ru, _rub(35, 4, 58)), '½ Хизб 9');
    expect(rubMarkLabel(ru, _rub(36, 4, 74)), '¾ Хизб 9');
    // Hizb 10 is the second half of juz 5.
    expect(rubMarkLabel(ru, _rub(37, 4, 88)), 'Хизб 10');
    expect(rubMarkLabel(ar, _rub(35, 4, 58)), 'نصف الحزب 9');
  });

  test('a page shows the quarter whose first ayah is on it', () {
    final rubs = [_rub(34, 4, 36), _rub(35, 4, 58)];
    expect(rubStartingIn([_ayah(4, 57), _ayah(4, 58)], rubs), rubs[1]);
    expect(rubStartingIn([_ayah(4, 59), _ayah(4, 60)], rubs), isNull);
    expect(rubStartingIn(const [], rubs), isNull);
  });

  testWidgets('a quarter is announced again once the reader comes back', (
    tester,
  ) async {
    final controller = RubMarkController();
    addTearDown(controller.dispose);
    final first = _rub(35, 4, 58);
    final second = _rub(36, 4, 74);

    controller.reached(first);
    expect(controller.mark, first);
    await tester.pump(rubMarkDuration);
    expect(controller.mark, isNull);

    // Still in view: nothing new to say.
    controller.reached(first);
    expect(controller.mark, isNull);

    // Left it and came back.
    controller.reached(null);
    controller.reached(first);
    expect(controller.mark, first);

    controller.reached(second);
    expect(controller.mark, second);
    await tester.pump(rubMarkDuration);
  });
}

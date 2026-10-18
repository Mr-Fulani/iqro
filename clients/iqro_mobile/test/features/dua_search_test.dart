import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/text/arabic_digits.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:iqro_mobile/features/dua/dua_search.dart';

DuaCategory _chapter(int number, String title) => DuaCategory(
  id: 'c$number',
  slug: 'chapter-$number',
  title: title,
  entryCount: 1,
  collection: 'hisn-al-muslim',
  sourceNumber: number,
);

void main() {
  final chapters = <DuaCategory>[
    _chapter(
      26,
      'СЛОВА МОЛЬБЫ, ПРОИЗНОСИМЫЕ ВО ВРЕМЯ МОЛИТВЫ ИСПРАШИВАНИЯ ПОМОЩИ',
    ),
    _chapter(32, 'СЛОВА ОБРАЩЕНИЯ К АЛЛАХУ С МОЛЬБОЙ ВО ВРЕМЯ ВИТРА'),
    _chapter(125, 'ЧТО ДОЛЖЕН СКАЗАТЬ ТОТ, КТО ОПАСАЕТСЯ СГЛАЗИТЬ НЕЧТО'),
  ];

  List<int> found(String query) => duaChaptersMatching(
    query,
    chapters,
  ).map((chapter) => chapter.sourceNumber).toList();

  test('istikhara is found by the name people know it by', () {
    for (final query in <String>[
      'истихара',
      'Истихару',
      'istikharah',
      'istihare',
      'استخارة',
    ]) {
      expect(found(query), <int>[26], reason: query);
    }
  });

  test('qunut leads to the witr chapter', () {
    expect(found('кунут'), <int>[32]);
  });

  test('a word of a chapter title finds it', () {
    expect(found('сглаз'), <int>[125]);
  });

  test('too short a query finds no chapter', () {
    expect(found('ис'), isEmpty);
  });

  test('ayah numbers are written in Arabic-Indic digits', () {
    expect(arabicIndicDigits(7), '٧');
    expect(arabicIndicDigits(255), '٢٥٥');
    expect(arabicIndicDigits(10), '١٠');
  });
}

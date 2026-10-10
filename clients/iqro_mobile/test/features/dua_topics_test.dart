import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/dua/dua_repository.dart';
import 'package:iqro_mobile/features/dua/dua_topics.dart';

void main() {
  test('every chapter is accessible in the agreed 19 topics', () {
    expect(duaTopics, hasLength(19));
    for (var number = 1; number <= 132; number++) {
      final category = DuaCategory(
        id: '$number',
        slug: 'chapter-$number',
        title: '',
        entryCount: 1,
        collection: 'hisn-al-muslim',
        sourceNumber: number,
      );
      expect(
        duaTopics.where((topic) => topic.includesCategory(category)),
        hasLength(number == 27 ? 2 : 1),
        reason: 'Chapter $number',
      );
    }
  });

  test(
    'morning and evening classification respects collection and source time notes',
    () {
      final morning = duaTopics.singleWhere((topic) => topic.id == 'morning');
      final evening = duaTopics.singleWhere((topic) => topic.id == 'evening');
      DuaEntry entry(int number, {String collection = 'hisn-al-muslim'}) =>
          DuaEntry(
            id: '$number',
            sourceNumber: number,
            collection: collection,
            categoryTitle: '',
            arabicText: '',
            meaning: '',
            transliteration: '',
            repetitions: 1,
            sourceLabel: '',
          );
      expect(morning.includesEntry(entry(97)), isFalse);
      expect(evening.includesEntry(entry(97)), isTrue);
      for (final number in [93, 94, 95]) {
        expect(morning.includesEntry(entry(number)), isTrue);
        expect(evening.includesEntry(entry(number)), isFalse);
      }
      expect(morning.includesEntry(entry(96)), isTrue);
      expect(evening.includesEntry(entry(96)), isTrue);
      expect(
        morning.includesEntry(
          entry(75, collection: 'supplications-from-quran'),
        ),
        isFalse,
      );
      expect(morning.entryNumbers, hasLength(23));
      expect(evening.entryNumbers, hasLength(21));
      expect({
        ...morning.entryNumbers!,
        ...evening.entryNumbers!,
      }, hasLength(24));
    },
  );
}

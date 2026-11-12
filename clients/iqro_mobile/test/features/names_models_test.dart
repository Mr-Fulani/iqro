import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/names/names_models.dart';

import 'names_test_data.dart';

void main() {
  test('the contract example parses', () {
    final document = namesDocument();
    expect(document.slug, 'asma-al-husna');
    expect(document.version, 'example-1');
    expect(document.names.map((name) => name.position), <int>[1, 2, 3, 4]);
    final first = document.names.first;
    expect(first.label, 'Ар-Рахман');
    expect((first.ayah!.surah, first.ayah!.ayah, first.ayah!.word), (55, 1, 1));
    expect(first.hasVoice, isTrue);
    expect(first.tafsirSource, 'Пример: книга толкований');
    // A name of two words has an ayah but no word to play; a name from the
    // Sunnah has neither.
    expect(document.names[2].ayah, isNotNull);
    expect(document.names[2].hasVoice, isFalse);
    expect(document.names[3].ayah, isNull);
    expect(document.names[3].tafsirSource, contains('другая книга'));
  });

  test('a list that does not fit the contract is rejected', () {
    Map<String, Object?> broken(void Function(List<Object?> names) change) {
      final json = namesFixture();
      change(json['names']! as List<Object?>);
      return json;
    }

    Map<String, Object?> name(List<Object?> names, int index) =>
        names[index]! as Map<String, Object?>;

    for (final payload in <Object?>[
      null,
      <String, Object?>{...namesFixture(), 'names': <Object?>[]},
      broken((names) => name(names, 1)['position'] = 5),
      broken((names) => name(names, 1)['slug'] = 'ar-rahman'),
      broken((names) => name(names, 0)['slug'] = 'Ar Rahman'),
      broken((names) => name(names, 0)['arabic'] = ''),
      broken((names) => name(names, 0).remove('tafsir')),
      broken((names) => name(names, 0).remove('tafsir_source')),
      broken((names) => (name(names, 0)['ayah']! as Map)['surah'] = 0),
      broken((names) => (name(names, 0)['ayah']! as Map)['word'] = '1'),
    ]) {
      expect(() => NamesDocument.fromJson(payload), throwsFormatException);
    }
  });

  test('the Arabic document shows the name itself', () {
    final json = namesFixture();
    ((json['names']! as List).first as Map)['transliteration'] = '';
    final name = NamesDocument.fromJson(json).names.first;
    expect(name.label, name.arabic);
    expect(stripHarakat('الرَّحْمَٰنُ'), 'الرحمن');
  });

  test('the wheel goes round and takes the short way', () {
    expect(wheelIndex(0, 99), 0);
    expect(wheelIndex(99, 99), 0);
    expect(wheelIndex(-1, 99), 98);
    expect(wheelIndex(100.4, 99), 1);
    expect(wheelTarget(0, 1, 99), 1);
    expect(wheelTarget(0, 98, 99), -1);
    expect(wheelTarget(98, 0, 99), 99);
    expect(wheelTarget(198, 5, 99), 203);
    expect(wheelTarget(-1, 0, 99), 0);
  });
}

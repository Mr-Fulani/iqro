import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';

Map<String, Object?> salahFixture() =>
    jsonDecode(
          File('test/fixtures/salah_course_document.json').readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  test('parses the contract example document', () {
    final document = SalahCourseDocument.fromJson(salahFixture());

    expect(document.schemaVersion, 1);
    expect(document.course.slug, 'hanbali-umdah');
    expect(document.course.version, '2026-10-18');
    expect(document.course.language, 'ru');
    expect(document.course.sourceTitle, 'Умдат аль-фикх (Ибн Кудама)');
    expect(document.course.publishedAt, DateTime.utc(2026, 10, 18, 10, 5));
    expect(document.sections.map((section) => section.slug), <String>[
      'basics',
      'purification',
      'five-prayers',
    ]);
    expect(document.orderedLessons.map((lesson) => lesson.slug), <String>[
      'what-is-salah',
      'wudu',
      'fajr',
    ]);

    final fajr = document.lesson('fajr')!;
    expect(fajr.kind, 'prayer');
    expect(fajr.prayer?.code, 'fajr');
    expect(fajr.prayer?.kind, 'fard');
    expect(fajr.prayer?.rakats, 2);
    expect(fajr.steps, hasLength(5));
    final ruku = fajr.steps[fajr.indexOfStep('fajr.r1.ruku')];
    expect(ruku.kind, 'recitation');
    expect(ruku.position, 'ruku');
    expect(ruku.ruling, 'rukn');
    expect(ruku.rakat, 1);
    expect(ruku.repeat, 3);
    expect(ruku.details, isNotNull);
    expect(document.stepFormulas(ruku).single.id, 'ruku-tasbih');
    expect(document.stepMedia(ruku)?.alt, contains('поясном поклоне'));

    final info = document.lesson('what-is-salah')!.steps.single;
    expect(info.media, isNull);
    expect(info.rakat, isNull);
    expect(info.formulas, isEmpty);

    final fatiha = document.formulas['fatiha']!;
    expect(fatiha.transliteration, isNull);
    expect(fatiha.source.kind, 'quran');
    expect(fatiha.source.surah, 1);
    expect(fatiha.source.ayahTo, 7);
    expect(fatiha.audio?.segments, hasLength(2));
    expect(fatiha.audio?.segments.last.startMs, 6000);
    final tasbih = document.formulas['ruku-tasbih']!;
    expect(tasbih.repetitions, 3);
    expect(tasbih.source.collection, 'hisn-al-muslim');
    expect(tasbih.source.sourceNumber, 33);
    expect(document.formulas['taslim']!.audio, isNull);

    final media = document.media['wudu-face']!;
    expect(media.width, 720);
    expect(media.height, 720);
    expect(media.aspectRatio, 1);
    expect(media.bytes, 41210);
  });

  test('ignores unknown fields and references the document lacks', () {
    final json = salahFixture();
    json['future_field'] = <String, Object?>{'any': 'thing'};
    (json['course']! as Map)['signature'] = 'x';
    final sections = json['sections']! as List;
    (sections.first as Map)['lessons'] = <Object?>['what-is-salah', 'gone'];
    final lessons = json['lessons']! as List;
    final firstStep = ((lessons.first as Map)['steps']! as List).first as Map;
    firstStep['formulas'] = <Object?>['missing-formula'];
    firstStep['media'] = 'missing-media';
    firstStep['karaoke'] = <Object?>[];

    final document = SalahCourseDocument.fromJson(json);
    final step = document.lesson('what-is-salah')!.steps.first;

    expect(document.sectionLessons(document.sections.first), hasLength(1));
    expect(document.stepFormulas(step), isEmpty);
    expect(document.stepMedia(step), isNull);
  });

  test('rejects an incompatible schema version', () {
    final json = salahFixture()..['schema_version'] = 2;
    expect(
      () => SalahCourseDocument.fromJson(json),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SalahCourseDocument.fromJson(salahFixture()..remove('course')),
      throwsA(isA<FormatException>()),
    );
  });
}

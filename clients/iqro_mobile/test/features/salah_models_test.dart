import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/courses/course_models.dart';
import 'package:iqro_mobile/features/salah/salah_models.dart';

Map<String, Object?> salahFixture() =>
    jsonDecode(
          File('test/fixtures/salah_course_document.json').readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  test('a lesson carries its video, slides and banner in the format of the '
      'thematic courses', () {
    final document = SalahCourseDocument.fromJson(salahFixture());
    final media = document.lesson('wudu')!.media;
    expect(media.map((block) => block.runtimeType), [
      LessonVideoMedia,
      LessonSlidesMedia,
      LessonBannerMedia,
    ]);
    final video = (media.first as LessonVideoMedia).video;
    expect(video.spokenLanguage, 'ru');
    expect(video.poster.width, 1280);
    final slide = (media[1] as LessonSlidesMedia).slides.single;
    expect(slide.caption, 'Порядок омовения: лицо, руки, голова, ноги');
    // A lesson without media, as documents built before them, has none.
    expect(document.lesson('fajr')!.media, isEmpty);
    final older = salahFixture();
    for (final lesson in older['lessons']! as List<Object?>) {
      (lesson! as Map<String, Object?>).remove('media');
    }
    expect(SalahCourseDocument.fromJson(older).lesson('wudu')!.media, isEmpty);
  });

  test('the course has «Author and sources» and a lesson its sources; '
      'documents built before have none', () {
    final document = SalahCourseDocument.fromJson(salahFixture());
    expect(
      document.course.source,
      'По книге «Умдат аль-фикх» Ибн Кудамы аль-Макдиси, ханбалитский мазхаб.',
    );
    expect(document.lesson('fajr')!.sources, <String>[
      'Ибн Кудама. Умдат аль-фикх, «Книга молитвы».',
      'Аль-Бухари, 757; Муслим, 397 — хадис о том, кто плохо молился.',
    ]);
    expect(document.lesson('wudu')!.sources, isEmpty);

    final older = salahFixture();
    (older['course']! as Map<String, Object?>)['source'] = 7;
    final fajr = (older['lessons']! as List<Object?>).last!;
    (fajr as Map<String, Object?>)['sources'] = <Object?>[
      '',
      '  Умдат аль-фикх  ',
      3,
    ];
    final parsed = SalahCourseDocument.fromJson(older);
    expect(parsed.course.source, isEmpty);
    expect(parsed.lesson('fajr')!.sources, <String>['Умдат аль-фикх']);
  });

  test('a step carries its «?» and «!» notes and its own voice-over', () {
    final document = SalahCourseDocument.fromJson(salahFixture());
    final steps = document.lesson('fajr')!.steps;
    final ruku = steps.firstWhere((step) => step.slug == 'fajr.r1.ruku');

    expect(ruku.notes.map((note) => note.kind), <SalahNoteKind>[
      SalahNoteKind.help,
      SalahNoteKind.warning,
    ]);
    expect(ruku.notes.first.text, startsWith('Спина и голова'));
    expect(ruku.audio?.url, endsWith('.m4a'));
    expect(steps.first.notes, isEmpty);
    expect(steps.first.audio, isNull);
  });

  test('malformed notes and recordings are left out', () {
    final step = SalahStep.fromJson(<String, Object?>{
      'slug': 'fajr.r1.ruku',
      'title': 'Руку',
      'instruction': '',
      'notes': <Object?>[
        <String, Object?>{'kind': 'warning', 'text': 'Важно'},
        <String, Object?>{'kind': 'tip', 'text': 'Новый вид'},
        <String, Object?>{'kind': 'help', 'text': '  '},
        'text',
        null,
      ],
      'audio': <String, Object?>{'url': ''},
    });

    expect(
      step.notes.map((note) => (note.kind, note.text)),
      <(SalahNoteKind, String)>[
        (SalahNoteKind.warning, 'Важно'),
        (SalahNoteKind.help, 'Новый вид'),
      ],
    );
    expect(step.audio, isNull);
    expect(
      SalahStep.fromJson(<String, Object?>{
        'slug': 'a.b',
        'notes': 'broken',
        'audio': 'broken',
      }).notes,
      isEmpty,
    );
  });

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
    expect(fajr.prayer?.kind, 'fard');
    expect(fajr.prayer?.kindTitle, 'Фард');
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
    expect(tasbih.caption, '«Хисн аль-Муслим», № 33');
    expect(fatiha.caption, isNull);
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

  test('accepts prayer kinds and rulings from a newer course', () {
    final json = salahFixture();
    final lessons = json['lessons']! as List;
    final fajr =
        lessons.firstWhere((lesson) => (lesson as Map)['slug'] == 'fajr')
            as Map;
    fajr['prayer'] = <String, Object?>{
      'code': 'eid',
      'kind': 'eid',
      'kind_title': 'Праздничный',
      'rakats': 2,
    };
    ((fajr['steps']! as List).first as Map)['ruling'] = 'mustahabb';

    final prayer = SalahCourseDocument.fromJson(json).lesson('fajr')!;

    expect(prayer.prayer?.kind, 'eid');
    expect(prayer.prayer?.kindTitle, 'Праздничный');
    expect(prayer.steps.first.ruling, 'mustahabb');
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

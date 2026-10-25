import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/listening_queue.dart';
import 'package:iqro_mobile/features/audio/reciter_catalog.dart';

// The same cases as services/web/lib/listening-queue.test.ts: both platforms
// follow docs/audio-listening-queue.md.
void main() {
  // A partial recording: Al-Fatiha, Ya-Sin and the 30th juz.
  final partial = <int>[
    1,
    36,
    for (var surah = 78; surah <= 114; surah++) surah,
  ];

  test('a recording holds its listed surahs in order, '
      'and the whole Quran when the list is missing', () {
    expect(heldSurahs(<int>[36, 1, 36, 0, 115]), <int>[1, 36]);
    expect(heldSurahs(null), hasLength(quranSurahCount));
    expect(heldSurahs(const <int>[]), hasLength(quranSurahCount));
    expect(recitationHeldSurahs(null), hasLength(quranSurahCount));
  });

  test('after a surah the queue stops, moves on to the next held surah, '
      'or loops', () {
    expect(surahAfter(partial, 36, ListeningQueueMode.stop), isNull);
    expect(surahAfter(partial, 1, ListeningQueueMode.next), 36);
    expect(surahAfter(partial, 36, ListeningQueueMode.next), 78);
    expect(surahAfter(partial, 114, ListeningQueueMode.next), isNull);
    expect(surahAfter(partial, 114, ListeningQueueMode.loop), 1);
    expect(surahAfter(<int>[36], 36, ListeningQueueMode.loop), 36);
    expect(surahAfter(heldSurahs(null), 2, ListeningQueueMode.next), 3);
  });

  test('the previous and next buttons skip missing surahs '
      'and cross the ends only in the loop mode', () {
    expect(adjacentQueueSurah(partial, 78, -1, ListeningQueueMode.next), 36);
    expect(adjacentQueueSurah(partial, 1, -1, ListeningQueueMode.next), isNull);
    expect(adjacentQueueSurah(partial, 1, -1, ListeningQueueMode.loop), 114);
    expect(
      adjacentQueueSurah(partial, 114, 1, ListeningQueueMode.stop),
      isNull,
    );
    expect(adjacentQueueSurah(partial, null, 1, ListeningQueueMode.next), null);
    expect(stepHeldSurah(const <int>[], 1, 1, wrap: true), isNull);
  });

  test('switching recordings keeps the surah when it is held, '
      'else the next one, else the last', () {
    expect(nearestHeldSurah(partial, 36), 36);
    expect(nearestHeldSurah(partial, 2), 36);
    expect(nearestHeldSurah(<int>[1, 36], 50), 36);
    expect(nearestHeldSurah(const <int>[], 50), isNull);
  });

  test('the queue list folds each run of missing surahs into one row', () {
    expect(listeningQueueRows(<int>[1, 3, 114]), const <ListeningQueueRow>[
      ListeningQueueSurahRow(1),
      ListeningQueueGapRow(2, 2),
      ListeningQueueSurahRow(3),
      ListeningQueueGapRow(4, 113),
      ListeningQueueSurahRow(114),
    ]);
    expect(
      listeningQueueRows(<int>[2, 3]).last,
      const ListeningQueueGapRow(4, 114),
    );
    expect(
      listeningQueueRows(<int>[2, 3]).first,
      const ListeningQueueGapRow(1, 1),
    );
    expect(
      listeningQueueRows(heldSurahs(null)).whereType<ListeningQueueGapRow>(),
      isEmpty,
    );
  });

  test('playing the whole Quran turns the stop mode into moving on', () {
    expect(wholeQuranMode(ListeningQueueMode.stop), ListeningQueueMode.next);
    expect(wholeQuranMode(ListeningQueueMode.next), ListeningQueueMode.next);
    expect(wholeQuranMode(ListeningQueueMode.loop), ListeningQueueMode.loop);
  });

  test('modes are saved by their names', () {
    expect(ListeningQueueMode.values.map((mode) => mode.name), <String>[
      'stop',
      'next',
      'loop',
    ]);
    expect(listeningQueueModeNamed('loop'), ListeningQueueMode.loop);
    expect(listeningQueueModeNamed('shuffle'), isNull);
    expect(listeningQueueModeNamed(null), isNull);
    expect(defaultListeningQueueMode, ListeningQueueMode.next);
  });

  test(
    'the variants are the reciter\'s listening recordings, one per style',
    () {
      Recitation recitation(
        String id,
        String style, {
        String reciterId = 'reciter',
        bool listen = true,
        List<int> surahs = const <int>[],
      }) => Recitation.fromJson(<String, Object?>{
        'id': id,
        'code': id,
        'style': style,
        'reciter': <String, Object?>{'id': reciterId, 'slug': reciterId},
        'quran_edition': <String, Object?>{'riwayah': "Hafs 'an Asim"},
        'rights': <String, Object?>{'stream': true},
        'coverage': <String, Object?>{
          'surah_count': surahs.isEmpty ? 114 : surahs.length,
          'surah_numbers': surahs,
        },
        'capabilities': <String, Object?>{
          'listen': listen,
          'ayah_playback': false,
          'memorization': false,
          'offline': false,
        },
      });
      final recitations = <Recitation>[
        recitation('mujawwad', 'mujawwad', surahs: const <int>[1, 36]),
        recitation('murattal', 'murattal'),
        recitation('murattal-2', 'murattal'),
        recitation('timed', 'muallim', listen: false),
        recitation('other', 'murattal', reciterId: 'other'),
      ];
      final person = groupRecitersByPerson(<Reciter>[
        recitations.first.reciter,
      ]).single;

      final variants = listeningVariants(
        person,
        recitations,
        currentId: 'murattal-2',
      );

      expect(variants.map((item) => item.id), <String>[
        'murattal-2',
        'mujawwad',
      ]);
      expect(variants.first.riwayah, "Hafs 'an Asim");
      expect(recitationHeldSurahs(variants.last), <int>[1, 36]);
    },
  );
}

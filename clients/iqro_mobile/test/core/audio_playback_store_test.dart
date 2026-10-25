import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_playback_store.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';
import 'package:iqro_mobile/features/audio/listening_queue.dart';

void main() {
  test('playback snapshot survives a JSON round trip', () {
    final savedAt = DateTime.utc(2026, 9, 1, 12, 30);
    final snapshot = AudioPlaybackSnapshot(
      playback: const SurahPlayback(
        track: AudioTrack(
          id: 'track-2',
          recitationId: 'recitation-1',
          surah: 2,
          url: 'https://iqro.forum/media/2.mp3',
          duration: Duration(minutes: 7),
          offlineDownloadAllowed: false,
        ),
        segments: <AudioSegment>[
          AudioSegment(
            ayahId: 'ayah-7',
            surah: 2,
            ayah: 7,
            start: Duration(seconds: 31),
            end: Duration(seconds: 38),
          ),
        ],
      ),
      reciter: const Reciter(
        id: 'reciter-1',
        slug: 'reciter',
        nameAr: 'قارئ',
        nameEn: 'Reciter',
        nameRu: 'Чтец',
        nameTr: 'Kari',
        biographyAr: '',
        biographyEn: '',
        biographyRu: '',
        biographyTr: '',
        portraitUrl: 'https://iqro.forum/media/reciter.webp',
      ),
      surahName: 'Аль-Бакара',
      position: const Duration(seconds: 34),
      speed: 1.25,
      repeatEnabled: true,
      rangeStartAyah: 7,
      rangeEndAyah: 7,
      savedAt: savedAt,
      queueMode: ListeningQueueMode.loop,
    );

    final restored = AudioPlaybackSnapshot.fromJson(snapshot.toJson());

    expect(restored.playback.track.id, 'track-2');
    expect(restored.playback.track.url, snapshot.playback.track.url);
    expect(restored.playback.segmentFor(7)?.start, const Duration(seconds: 31));
    expect(restored.reciter.nameRu, 'Чтец');
    expect(restored.reciter.portraitUrl, snapshot.reciter.portraitUrl);
    expect(restored.surahName, 'Аль-Бакара');
    expect(restored.position, const Duration(seconds: 34));
    expect(restored.speed, 1.25);
    expect(restored.repeatEnabled, isTrue);
    expect(restored.rangeStartAyah, 7);
    expect(restored.rangeEndAyah, 7);
    expect(restored.savedAt, savedAt);
    expect(snapshot.toJson()['queue_mode'], 'loop');
    expect(restored.queueMode, ListeningQueueMode.loop);
  });

  test('a version 1 snapshot from before the queue still reads', () {
    final json = <String, Object?>{
      'version': 1,
      'playback': <String, Object?>{
        'track': <String, Object?>{
          'id': 'track-1',
          'recitation_id': 'recitation-1',
          'surah_number': 1,
          'duration_ms': 60000,
          'asset': <String, Object?>{'url': 'https://iqro.forum/media/1.mp3'},
        },
        'segments': <Object?>[],
      },
      'reciter': <String, Object?>{'id': 'reciter-1', 'slug': 'reciter'},
      'surah_name': 'Аль-Фатиха',
      'position_ms': 1200,
      'speed': 1,
      'repeat_enabled': false,
      'saved_at': '2026-09-01T12:30:00.000Z',
    };

    final restored = AudioPlaybackSnapshot.fromJson(json);

    expect(restored.playback.track.id, 'track-1');
    expect(restored.position, const Duration(milliseconds: 1200));
    expect(restored.queueMode, isNull);
    expect(restored.toJson().containsKey('queue_mode'), isFalse);
    expect(
      AudioPlaybackSnapshot.fromJson(<String, Object?>{
        ...json,
        'queue_mode': 'shuffle',
      }).queueMode,
      isNull,
    );
  });

  test('playback snapshot rejects an unsupported format', () {
    expect(
      () =>
          AudioPlaybackSnapshot.fromJson(const <String, Object?>{'version': 2}),
      throwsFormatException,
    );
  });
}

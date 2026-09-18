import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_playback_store.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';

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
  });

  test('playback snapshot rejects an unsupported format', () {
    expect(
      () =>
          AudioPlaybackSnapshot.fromJson(const <String, Object?>{'version': 2}),
      throwsFormatException,
    );
  });
}

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';

void main() {
  test('Dua audio URL accepts an absolute HTTPS media URL', () {
    final uri = validateIqroStreamingAudioUrl(
      'https://media.example.test/dua/1.mp3?signature=abc',
    );

    expect(uri.host, 'media.example.test');
    expect(uri.path, '/dua/1.mp3');
    expect(uri.queryParameters['signature'], 'abc');
  });

  test('Dua audio URL rejects unsafe or malformed values', () {
    for (final value in <String>[
      '',
      'http://media.example.test/dua/1.mp3',
      '/dua/1.mp3',
      'https://user:secret@media.example.test/dua/1.mp3',
      ' https://media.example.test/dua/1.mp3',
      'https://media.example.test/dua/a b.mp3',
    ]) {
      expect(
        () => validateIqroStreamingAudioUrl(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('Dua MediaItem is attached to the audio source', () {
    final uri = Uri.parse('https://media.example.test/dua/1.mp3');
    final mediaItem = buildIqroStandaloneMediaItem(
      id: 'dua:hisn-al-muslim:1',
      title: 'Morning remembrance',
      contentType: 'dua',
      artist: 'Reader',
      duration: const Duration(seconds: 12),
      extras: const <String, dynamic>{
        'collection': 'hisn-al-muslim',
        'content_type': 'not-dua',
      },
    );
    final source = buildIqroStandaloneAudioSource(
      uri: uri,
      mediaItem: mediaItem,
    );

    expect(source.uri, uri);
    expect(source.tag, same(mediaItem));
    expect(source.tag, isA<MediaItem>());
    expect(mediaItem.artist, 'Reader');
    expect(mediaItem.duration, const Duration(seconds: 12));
    expect(mediaItem.extras?['content_type'], 'dua');
    expect(mediaItem.extras?['collection'], 'hisn-al-muslim');
  });

  test('Dua playback position clamps only to known duration', () {
    expect(
      clampIqroAudioPosition(
        const Duration(seconds: -1),
        const Duration(seconds: 10),
      ),
      Duration.zero,
    );
    expect(
      clampIqroAudioPosition(
        const Duration(seconds: 11),
        const Duration(seconds: 10),
      ),
      const Duration(seconds: 10),
    );
    expect(
      clampIqroAudioPosition(const Duration(seconds: 11), Duration.zero),
      const Duration(seconds: 11),
    );
  });

  test('Dua audio state exposes bounded progress and remaining time', () {
    final uri = Uri.parse('https://media.example.test/dua/1.mp3');
    const mediaItem = MediaItem(id: 'dua:1', title: 'Dua');
    final beforeStart = IqroStandaloneAudioState(
      uri: uri,
      mediaItem: mediaItem,
      position: Duration(seconds: -1),
      duration: Duration(seconds: 10),
    );
    final afterEnd = IqroStandaloneAudioState(
      uri: uri,
      mediaItem: mediaItem,
      position: Duration(seconds: 12),
      duration: Duration(seconds: 10),
      error: 'old error',
    );

    expect(beforeStart.progress, 0);
    expect(beforeStart.remaining, const Duration(seconds: 10));
    expect(afterEnd.progress, 1);
    expect(afterEnd.remaining, Duration.zero);
    expect(afterEnd.copyWith(clearError: true).error, isNull);
  });
}

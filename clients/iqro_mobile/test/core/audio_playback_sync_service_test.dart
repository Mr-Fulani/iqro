import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/audio/audio_playback_store.dart';
import 'package:iqro_mobile/core/audio/audio_playback_sync_service.dart';
import 'package:iqro_mobile/features/audio/audio_models.dart';

void main() {
  final syncedAt = DateTime.utc(2026, 9, 1, 8);

  test(
    'uploads a local-only position and downloads a remote-only position',
    () {
      expect(
        decideAudioPlaybackSync(
          local: _local(savedAt: syncedAt),
          remote: null,
          metadata: null,
        ),
        AudioPlaybackSyncAction.uploadLocal,
      );
      expect(
        decideAudioPlaybackSync(
          local: null,
          remote: _remote(clientUpdatedAt: syncedAt),
          metadata: null,
        ),
        AudioPlaybackSyncAction.downloadRemote,
      );
    },
  );

  test('does nothing when neither side changed after the last sync', () {
    expect(
      decideAudioPlaybackSync(
        local: _local(savedAt: syncedAt),
        remote: _remote(clientUpdatedAt: syncedAt, revision: 4),
        metadata: AudioPlaybackSyncMetadata(
          serverRevision: 4,
          localSavedAt: syncedAt,
        ),
      ),
      AudioPlaybackSyncAction.none,
    );
  });

  test('uploads a local change when the server revision is unchanged', () {
    expect(
      decideAudioPlaybackSync(
        local: _local(savedAt: syncedAt.add(const Duration(minutes: 2))),
        remote: _remote(clientUpdatedAt: syncedAt, revision: 4),
        metadata: AudioPlaybackSyncMetadata(
          serverRevision: 4,
          localSavedAt: syncedAt,
        ),
      ),
      AudioPlaybackSyncAction.uploadLocal,
    );
  });

  test('downloads a remote change when the local snapshot is unchanged', () {
    expect(
      decideAudioPlaybackSync(
        local: _local(savedAt: syncedAt),
        remote: _remote(
          clientUpdatedAt: syncedAt.add(const Duration(minutes: 2)),
          revision: 5,
        ),
        metadata: AudioPlaybackSyncMetadata(
          serverRevision: 4,
          localSavedAt: syncedAt,
        ),
      ),
      AudioPlaybackSyncAction.downloadRemote,
    );
  });

  test('resolves concurrent changes by the latest client timestamp', () {
    final metadata = AudioPlaybackSyncMetadata(
      serverRevision: 4,
      localSavedAt: syncedAt,
    );
    expect(
      decideAudioPlaybackSync(
        local: _local(savedAt: syncedAt.add(const Duration(minutes: 3))),
        remote: _remote(
          clientUpdatedAt: syncedAt.add(const Duration(minutes: 2)),
          revision: 5,
        ),
        metadata: metadata,
      ),
      AudioPlaybackSyncAction.uploadLocal,
    );
    expect(
      decideAudioPlaybackSync(
        local: _local(savedAt: syncedAt.add(const Duration(minutes: 2))),
        remote: _remote(
          clientUpdatedAt: syncedAt.add(const Duration(minutes: 3)),
          revision: 5,
        ),
        metadata: metadata,
      ),
      AudioPlaybackSyncAction.downloadRemote,
    );
  });

  test('never restores a withdrawn track over the local player', () {
    expect(
      decideAudioPlaybackSync(
        local: _local(savedAt: syncedAt),
        remote: _remote(clientUpdatedAt: syncedAt, playbackAvailable: false),
        metadata: null,
      ),
      AudioPlaybackSyncAction.none,
    );
  });

  test('strictly validates the remote playback contract', () {
    expect(
      () => RemoteAudioPlaybackPosition.fromJson(<String, Object?>{
        'track_id': 'track-1',
        'recitation_id': 'recitation-1',
        'surah_number': 1,
        'duration_ms': 10,
        'position_ms': 11,
        'speed': 1,
        'revision': 1,
        'client_updated_at': syncedAt.toIso8601String(),
        'playback_available': true,
        'reciter': _reciter.toJson(),
      }),
      throwsFormatException,
    );
  });
}

const _reciter = Reciter(
  id: 'reciter-1',
  slug: 'reciter',
  nameAr: 'قارئ',
  nameEn: 'Reciter',
  nameRu: 'Чтец',
  nameTr: 'Okuyucu',
  biographyAr: '',
  biographyEn: '',
  biographyRu: '',
  biographyTr: '',
);

AudioPlaybackSnapshot _local({required DateTime savedAt}) =>
    AudioPlaybackSnapshot(
      playback: const SurahPlayback(
        track: AudioTrack(
          id: 'track-1',
          recitationId: 'recitation-1',
          surah: 1,
          url: 'https://example.test/001.mp3',
          duration: Duration(minutes: 1),
          offlineDownloadAllowed: false,
        ),
        segments: <AudioSegment>[],
      ),
      reciter: _reciter,
      surahName: 'Al-Fatihah',
      position: const Duration(seconds: 10),
      speed: 1,
      repeatEnabled: false,
      savedAt: savedAt,
    );

RemoteAudioPlaybackPosition _remote({
  required DateTime clientUpdatedAt,
  int revision = 1,
  bool playbackAvailable = true,
}) => RemoteAudioPlaybackPosition(
  trackId: 'track-1',
  recitationId: 'recitation-1',
  surah: 1,
  durationMs: 60_000,
  positionMs: 10_000,
  speed: 1,
  repeatEnabled: false,
  revision: revision,
  clientUpdatedAt: clientUpdatedAt,
  playbackAvailable: playbackAvailable,
  reciter: _reciter,
  surahNames: const <String, String>{'en': 'Al-Fatihah'},
);

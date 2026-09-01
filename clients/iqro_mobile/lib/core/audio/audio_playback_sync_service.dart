import '../../features/audio/audio_models.dart';
import '../../features/audio/audio_repository.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../storage/local_database.dart';
import '../utils/json_helpers.dart';
import 'audio_playback_store.dart';

enum AudioPlaybackSyncAction { none, uploadLocal, downloadRemote }

enum AudioPlaybackSyncStatus {
  idle,
  uploaded,
  downloaded,
  offline,
  unsupported,
  conflict,
  failed,
}

class AudioPlaybackSyncReport {
  const AudioPlaybackSyncReport(this.status, {this.message});

  final AudioPlaybackSyncStatus status;
  final String? message;

  bool get shouldRetry => status == AudioPlaybackSyncStatus.failed;
}

class RemoteAudioPlaybackPosition {
  const RemoteAudioPlaybackPosition({
    required this.trackId,
    required this.recitationId,
    required this.surah,
    required this.durationMs,
    required this.positionMs,
    required this.speed,
    required this.repeatEnabled,
    required this.revision,
    required this.clientUpdatedAt,
    required this.playbackAvailable,
    required this.reciter,
    required this.surahNames,
    this.rangeStartAyah,
    this.rangeEndAyah,
  });

  factory RemoteAudioPlaybackPosition.fromJson(Map<String, Object?> json) {
    final reciterJson = json['reciter'];
    final namesJson = json['surah_names'];
    final clientUpdatedAt = DateTime.tryParse(
      json['client_updated_at']?.toString() ?? '',
    );
    final value = RemoteAudioPlaybackPosition(
      trackId: json['track_id']?.toString() ?? '',
      recitationId: json['recitation_id']?.toString() ?? '',
      surah: (json['surah_number'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? -1,
      speed: (json['speed'] as num?)?.toDouble() ?? 1,
      repeatEnabled: json['repeat_enabled'] == true,
      rangeStartAyah: (json['range_start_ayah'] as num?)?.toInt(),
      rangeEndAyah: (json['range_end_ayah'] as num?)?.toInt(),
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      clientUpdatedAt:
          clientUpdatedAt?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0),
      playbackAvailable: json['playback_available'] == true,
      reciter: reciterJson is Map
          ? Reciter.fromJson(Map<String, Object?>.from(reciterJson))
          : const Reciter(
              id: '',
              slug: '',
              nameAr: '',
              nameEn: '',
              nameRu: '',
              nameTr: '',
              biographyAr: '',
              biographyEn: '',
              biographyRu: '',
              biographyTr: '',
            ),
      surahNames: namesJson is Map
          ? Map<String, String>.fromEntries(
              namesJson.entries.map(
                (entry) =>
                    MapEntry(entry.key.toString(), entry.value.toString()),
              ),
            )
          : const <String, String>{},
    );
    final rangePaired =
        (value.rangeStartAyah == null) == (value.rangeEndAyah == null);
    if (value.trackId.isEmpty ||
        value.recitationId.isEmpty ||
        value.reciter.id.isEmpty ||
        value.surah < 1 ||
        value.surah > 114 ||
        value.durationMs <= 0 ||
        value.positionMs < 0 ||
        value.positionMs > value.durationMs ||
        value.speed < 0.5 ||
        value.speed > 2 ||
        value.revision <= 0 ||
        clientUpdatedAt == null ||
        !rangePaired ||
        (value.rangeStartAyah != null &&
            value.rangeStartAyah! > value.rangeEndAyah!)) {
      throw const FormatException('Invalid remote audio playback position');
    }
    return value;
  }

  final String trackId;
  final String recitationId;
  final int surah;
  final int durationMs;
  final int positionMs;
  final double speed;
  final bool repeatEnabled;
  final int? rangeStartAyah;
  final int? rangeEndAyah;
  final int revision;
  final DateTime clientUpdatedAt;
  final bool playbackAvailable;
  final Reciter reciter;
  final Map<String, String> surahNames;

  String surahNameFor(String locale) =>
      surahNames[locale]?.trim().isNotEmpty == true
      ? surahNames[locale]!
      : surahNames['en'] ?? surahNames['ar'] ?? 'Surah $surah';
}

class AudioPlaybackSyncMetadata {
  const AudioPlaybackSyncMetadata({
    required this.serverRevision,
    required this.localSavedAt,
  });

  factory AudioPlaybackSyncMetadata.fromJson(Map<String, Object?> json) {
    final savedAt = DateTime.tryParse(json['local_saved_at']?.toString() ?? '');
    final revision = (json['server_revision'] as num?)?.toInt() ?? 0;
    if (savedAt == null || revision <= 0) {
      throw const FormatException('Invalid audio playback sync metadata');
    }
    return AudioPlaybackSyncMetadata(
      serverRevision: revision,
      localSavedAt: savedAt.toUtc(),
    );
  }

  final int serverRevision;
  final DateTime localSavedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'server_revision': serverRevision,
    'local_saved_at': localSavedAt.toUtc().toIso8601String(),
  };
}

AudioPlaybackSyncAction decideAudioPlaybackSync({
  required AudioPlaybackSnapshot? local,
  required RemoteAudioPlaybackPosition? remote,
  required AudioPlaybackSyncMetadata? metadata,
}) {
  if (remote == null) {
    return local == null
        ? AudioPlaybackSyncAction.none
        : AudioPlaybackSyncAction.uploadLocal;
  }
  if (!remote.playbackAvailable) {
    return local != null && local.playback.track.id != remote.trackId
        ? AudioPlaybackSyncAction.uploadLocal
        : AudioPlaybackSyncAction.none;
  }
  if (local == null) return AudioPlaybackSyncAction.downloadRemote;
  if (metadata == null) {
    return local.savedAt.isAfter(remote.clientUpdatedAt)
        ? AudioPlaybackSyncAction.uploadLocal
        : AudioPlaybackSyncAction.downloadRemote;
  }
  final localChanged = local.savedAt != metadata.localSavedAt;
  final remoteChanged = remote.revision != metadata.serverRevision;
  if (!localChanged && !remoteChanged) return AudioPlaybackSyncAction.none;
  if (localChanged && !remoteChanged) {
    return AudioPlaybackSyncAction.uploadLocal;
  }
  if (!localChanged && remoteChanged) {
    return AudioPlaybackSyncAction.downloadRemote;
  }
  return local.savedAt.isAfter(remote.clientUpdatedAt)
      ? AudioPlaybackSyncAction.uploadLocal
      : AudioPlaybackSyncAction.downloadRemote;
}

class AudioPlaybackSyncService {
  AudioPlaybackSyncService({
    required ApiClient api,
    required LocalDatabase database,
    required AudioRepository audio,
    required AudioPlaybackStore store,
    required String Function() locale,
  }) : _api = api,
       _database = database,
       _audio = audio,
       _store = store,
       _locale = locale;

  static const metadataStateKey = 'audio_playback_sync_v1';

  final ApiClient _api;
  final LocalDatabase _database;
  final AudioRepository _audio;
  final AudioPlaybackStore _store;
  final String Function() _locale;
  Future<AudioPlaybackSyncReport>? _flight;

  Future<AudioPlaybackSyncReport> synchronize() {
    final current = _flight;
    if (current != null) return current;
    final next = _synchronize(allowConflictRetry: true);
    _flight = next;
    return next.whenComplete(() => _flight = null);
  }

  Future<AudioPlaybackSyncReport> _synchronize({
    required bool allowConflictRetry,
  }) async {
    try {
      final local = await _store.read();
      final remote = await _readRemote();
      final metadata = await _readMetadata();
      final action = decideAudioPlaybackSync(
        local: local,
        remote: remote,
        metadata: metadata,
      );
      switch (action) {
        case AudioPlaybackSyncAction.none:
          return const AudioPlaybackSyncReport(AudioPlaybackSyncStatus.idle);
        case AudioPlaybackSyncAction.uploadLocal:
          if (local == null) {
            return const AudioPlaybackSyncReport(AudioPlaybackSyncStatus.idle);
          }
          final uploaded = await _upload(
            local,
            baseRevision: remote?.revision ?? 0,
          );
          await _writeMetadata(uploaded.revision, local.savedAt);
          return const AudioPlaybackSyncReport(
            AudioPlaybackSyncStatus.uploaded,
          );
        case AudioPlaybackSyncAction.downloadRemote:
          if (remote == null || !remote.playbackAvailable) {
            return const AudioPlaybackSyncReport(AudioPlaybackSyncStatus.idle);
          }
          final downloaded = await _download(remote, local: local);
          await _store.write(downloaded);
          await _writeMetadata(remote.revision, downloaded.savedAt);
          return const AudioPlaybackSyncReport(
            AudioPlaybackSyncStatus.downloaded,
          );
      }
    } on ApiException catch (error) {
      if (error.isOffline) {
        return AudioPlaybackSyncReport(
          AudioPlaybackSyncStatus.offline,
          message: error.message,
        );
      }
      if (error.statusCode == 404) {
        return const AudioPlaybackSyncReport(
          AudioPlaybackSyncStatus.unsupported,
        );
      }
      if (error.statusCode == 409 && allowConflictRetry) {
        return _synchronize(allowConflictRetry: false);
      }
      if (error.statusCode == 409) {
        return AudioPlaybackSyncReport(
          AudioPlaybackSyncStatus.conflict,
          message: error.message,
        );
      }
      return AudioPlaybackSyncReport(
        AudioPlaybackSyncStatus.failed,
        message: error.message,
      );
    } on Object catch (error) {
      return AudioPlaybackSyncReport(
        AudioPlaybackSyncStatus.failed,
        message: error.toString(),
      );
    }
  }

  Future<RemoteAudioPlaybackPosition?> _readRemote() async {
    final envelope = jsonMap(await _api.get('/me/audio-playback-position'));
    final raw = envelope['position'];
    return raw is Map
        ? RemoteAudioPlaybackPosition.fromJson(Map<String, Object?>.from(raw))
        : null;
  }

  Future<RemoteAudioPlaybackPosition> _upload(
    AudioPlaybackSnapshot local, {
    required int baseRevision,
  }) async {
    final envelope = jsonMap(
      await _api.put(
        '/me/audio-playback-position',
        data: <String, Object?>{
          'base_revision': baseRevision,
          'track_id': local.playback.track.id,
          'position_ms': local.position.inMilliseconds,
          'speed': local.speed,
          'repeat_enabled': local.repeatEnabled,
          'range_start_ayah': local.rangeStartAyah,
          'range_end_ayah': local.rangeEndAyah,
          'client_updated_at': local.savedAt.toUtc().toIso8601String(),
        },
      ),
    );
    final raw = envelope['position'];
    if (raw is! Map) {
      throw const FormatException('Missing uploaded audio playback position');
    }
    return RemoteAudioPlaybackPosition.fromJson(Map<String, Object?>.from(raw));
  }

  Future<AudioPlaybackSnapshot> _download(
    RemoteAudioPlaybackPosition remote, {
    required AudioPlaybackSnapshot? local,
  }) async {
    final canReuseLocal =
        local?.playback.track.id == remote.trackId &&
        (remote.rangeStartAyah == null ||
            (local!.playback.segmentFor(remote.rangeStartAyah!) != null &&
                local.playback.segmentFor(remote.rangeEndAyah!) != null));
    final playback = canReuseLocal
        ? local!.playback
        : await _audio.playback(
            recitationId: remote.recitationId,
            surah: remote.surah,
          );
    if (playback.track.id != remote.trackId) {
      throw const FormatException(
        'Remote playback track does not match catalog',
      );
    }
    final maximum = playback.track.duration == Duration.zero
        ? remote.durationMs
        : playback.track.duration.inMilliseconds;
    return AudioPlaybackSnapshot(
      playback: playback,
      reciter: remote.reciter,
      surahName: remote.surahNameFor(_locale()),
      position: Duration(milliseconds: remote.positionMs.clamp(0, maximum)),
      speed: remote.speed,
      repeatEnabled: remote.repeatEnabled,
      rangeStartAyah: remote.rangeStartAyah,
      rangeEndAyah: remote.rangeEndAyah,
      savedAt: remote.clientUpdatedAt,
    );
  }

  Future<AudioPlaybackSyncMetadata?> _readMetadata() async {
    final value = await _database.readState(metadataStateKey);
    if (value == null) return null;
    try {
      return AudioPlaybackSyncMetadata.fromJson(value);
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeMetadata(int revision, DateTime savedAt) =>
      _database.writeState(
        metadataStateKey,
        AudioPlaybackSyncMetadata(
          serverRevision: revision,
          localSavedAt: savedAt.toUtc(),
        ).toJson(),
      );
}

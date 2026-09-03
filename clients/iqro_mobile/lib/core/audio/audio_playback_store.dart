import '../../features/audio/audio_models.dart';
import '../auth/account_scope.dart';
import '../storage/local_database.dart';

class AudioPlaybackSnapshot {
  const AudioPlaybackSnapshot({
    required this.playback,
    required this.reciter,
    required this.surahName,
    required this.position,
    required this.speed,
    required this.repeatEnabled,
    required this.savedAt,
    this.rangeStartAyah,
    this.rangeEndAyah,
  });

  factory AudioPlaybackSnapshot.fromJson(Map<String, Object?> json) {
    final playbackJson = json['playback'];
    final reciterJson = json['reciter'];
    if (json['version'] != 1 || playbackJson is! Map || reciterJson is! Map) {
      throw const FormatException('Unsupported audio playback snapshot');
    }
    final playback = SurahPlayback.fromJson(
      Map<String, Object?>.from(playbackJson),
    );
    final reciter = Reciter.fromJson(Map<String, Object?>.from(reciterJson));
    final positionMilliseconds = (json['position_ms'] as num?)?.toInt() ?? 0;
    final speed = (json['speed'] as num?)?.toDouble() ?? 1;
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    if (playback.track.id.isEmpty ||
        playback.track.url.isEmpty ||
        reciter.id.isEmpty ||
        savedAt == null) {
      throw const FormatException('Incomplete audio playback snapshot');
    }
    return AudioPlaybackSnapshot(
      playback: playback,
      reciter: reciter,
      surahName: json['surah_name']?.toString() ?? '',
      position: Duration(
        milliseconds: positionMilliseconds.clamp(0, 1 << 53).toInt(),
      ),
      speed: speed.clamp(0.5, 2).toDouble(),
      repeatEnabled: json['repeat_enabled'] == true,
      rangeStartAyah: (json['range_start_ayah'] as num?)?.toInt(),
      rangeEndAyah: (json['range_end_ayah'] as num?)?.toInt(),
      savedAt: savedAt.toUtc(),
    );
  }

  final SurahPlayback playback;
  final Reciter reciter;
  final String surahName;
  final Duration position;
  final double speed;
  final bool repeatEnabled;
  final int? rangeStartAyah;
  final int? rangeEndAyah;
  final DateTime savedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'playback': playback.toJson(),
    'reciter': reciter.toJson(),
    'surah_name': surahName,
    'position_ms': position.inMilliseconds,
    'speed': speed,
    'repeat_enabled': repeatEnabled,
    'range_start_ayah': rangeStartAyah,
    'range_end_ayah': rangeEndAyah,
    'saved_at': savedAt.toUtc().toIso8601String(),
  };
}

class AudioPlaybackStore {
  AudioPlaybackStore(this._database, {AccountScopeSnapshot? accountScope})
    : _boundScope = accountScope == null
          ? null
          : Future<AccountScopeSnapshot>.value(accountScope);

  static const stateKey = 'audio_playback_v1';
  final LocalDatabase _database;
  Future<AccountScopeSnapshot>? _boundScope;

  Future<AccountScopeSnapshot> _defaultScope() =>
      _boundScope ??= _captureDefaultScope();

  Future<AccountScopeSnapshot> _captureDefaultScope() async {
    try {
      return await _database.captureAccount();
    } on Object {
      // A first-launch network failure must not poison this store forever.
      _boundScope = null;
      rethrow;
    }
  }

  Future<AudioPlaybackSnapshot?> read({
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _defaultScope();
    final json = await _database.readState(stateKey, accountScope: scope);
    if (json == null) return null;
    return AudioPlaybackSnapshot.fromJson(json);
  }

  Future<void> write(
    AudioPlaybackSnapshot snapshot, {
    AccountScopeSnapshot? accountScope,
  }) async {
    final scope = accountScope ?? await _defaultScope();
    await _database.writeState(
      stateKey,
      snapshot.toJson(),
      accountScope: scope,
    );
  }

  Future<void> clear({AccountScopeSnapshot? accountScope}) async {
    final scope = accountScope ?? await _defaultScope();
    await _database.deleteState(stateKey, accountScope: scope);
  }
}

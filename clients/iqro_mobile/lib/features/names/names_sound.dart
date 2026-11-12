import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/audio/audio_controller.dart';
import '../audio/audio_models.dart';
import '../audio/audio_repository.dart';
import '../audio/reciter_catalog.dart';
import '../quran/word_range.dart' show wordTimingFallbackRecitations;
import 'names_models.dart';

/// The short mechanical click of the wheel.
abstract interface class NamesClick {
  void play();

  Future<void> dispose();
}

/// A few players take turns, so a click can start before the previous one has
/// ended. They stay out of the audio session: a click must not pause the
/// Quran that plays.
class AssetNamesClick implements NamesClick {
  static const _asset = 'assets/sounds/names_tick.wav';
  static const _voices = 3;

  final _players = <AudioPlayer>[];
  var _next = 0;
  var _failed = false;

  Future<AudioPlayer?> _player() async {
    if (_failed) return null;
    if (_players.length < _voices) {
      try {
        final player = AudioPlayer(handleAudioSessionActivation: false);
        await player.setAsset(_asset);
        _players.add(player);
        return player;
      } on Object {
        // No sound on this device: the wheel turns silently.
        _failed = true;
        return null;
      }
    }
    return _players[_next++ % _voices];
  }

  @override
  void play() {
    unawaited(() async {
      try {
        final player = await _player();
        if (player == null) return;
        await player.seek(Duration.zero);
        unawaited(player.play());
      } on Object {
        // The click is a nicety.
      }
    }());
  }

  @override
  Future<void> dispose() async {
    for (final player in _players) {
      await player.dispose();
    }
    _players.clear();
  }
}

/// A light tap under the finger for every name that passes the needle.
void namesHaptic() {
  unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
}

/// Plays one bundled recording of a name.
abstract interface class NamesClipPlayer {
  /// Completes when the recording has ended or was stopped.
  Future<void> play(String asset);

  Future<void> stop();

  Future<void> dispose();
}

/// A player of its own, outside the audio session: a name is a second long
/// and must start at once.
class AssetNamesClipPlayer implements NamesClipPlayer {
  AudioPlayer? _player;

  @override
  Future<void> play(String asset) async {
    final player = _player ??= AudioPlayer(handleAudioSessionActivation: false);
    await player.stop();
    await player.setAsset(asset);
    await player.play();
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> dispose() async => _player?.dispose();
}

/// Says a name. A name with a recording of its own (`assets/names_audio/`)
/// sounds at once, in every language; another name is said by a reciter: the
/// word of its ayah, cut from the surah track by the word timings, as
/// «Прослушать слово» in the Mushaf does.
class NamesVoice extends ChangeNotifier {
  NamesVoice({
    required AudioController Function() audio,
    required AudioRepository repository,
    required Future<Set<String>> recorded,
    NamesClipPlayer? clips,
  }) : _audio = audio,
       _repository = repository,
       _clipPlayer = clips ?? AssetNamesClipPlayer() {
    unawaited(
      recorded.then((slugs) {
        _recorded = slugs;
        if (!_disposed) notifyListeners();
      }, onError: (Object _) {}),
    );
  }

  final AudioController Function() _audio;
  final AudioRepository _repository;
  final NamesClipPlayer _clipPlayer;
  final owner = Object();
  final _clips = <String, Future<_Clip?>>{};
  Future<List<Recitation>>? _voices;
  var _recorded = const <String>{};
  var _disposed = false;
  String? _missing;
  String? _playing;

  static const _folder = 'assets/names_audio/';

  /// The slugs of the names recorded in the app's assets.
  static Future<Set<String>> recordedNames(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return <String>{
      for (final asset in manifest.listAssets())
        if (asset.startsWith(_folder) && asset.endsWith('.mp3'))
          asset.substring(_folder.length, asset.length - 4),
    };
  }

  /// The slug of a name no reciter has a recording of, once it was asked for.
  String? get missing => _missing;

  /// The slug of the name whose own recording sounds now.
  String? get playing => _playing;

  /// Whether the card has «Слушать» for [name].
  bool canSay(DivineName name) =>
      _recorded.contains(name.slug) || name.hasVoice;

  static String clipId(DivineName name) => 'names:${name.slug}';

  /// The teaching voice first, then the reciters with word timings.
  Future<List<Recitation>> _candidates() => _voices ??= () async {
    final recitations = await _repository.recitationsForRole(
      AudioRecitationRole.ayahPlayback,
    );
    final first = tajweedCourseRecitation(recitations);
    return <Recitation>[
      ?first,
      for (final voice in wordTimingFallbackRecitations(recitations))
        if (voice.id != first?.id) voice,
    ];
  }();

  Future<_Clip?> _clip(DivineName name) {
    final ayah = name.ayah!;
    return _clips.putIfAbsent(name.slug, () async {
      try {
        for (final voice in await _candidates()) {
          final AyahPlayback playback;
          try {
            playback = await _repository.ayahPlayback(
              recitationId: voice.id,
              surah: ayah.surah,
              ayah: ayah.ayah,
            );
          } on Object {
            continue;
          }
          final word = playback.words[ayah.word];
          if (word != null && word.end > word.start) {
            return (
              url: playback.track.url,
              start: word.start,
              end: word.end,
              reciter: voice.reciter.nameEn,
            );
          }
        }
      } on Object {
        // Falls through: nothing to play now.
      }
      return null;
    });
  }

  /// Plays [name]; a name with nothing to play stays silent.
  Future<void> play(DivineName name, {required String album}) async {
    if (_recorded.contains(name.slug)) {
      _setMissing(null);
      _setPlaying(name.slug);
      try {
        await _clipPlayer.play('$_folder${name.slug}.mp3');
      } on Object {
        // No sound on this device.
      }
      if (_playing == name.slug) _setPlaying(null);
      return;
    }
    if (!name.hasVoice) return;
    final clip = await _clip(name);
    if (clip == null) {
      // It may be a lost connection: the next press asks again.
      unawaited(_clips.remove(name.slug));
      _setMissing(name.slug);
      return;
    }
    _setMissing(null);
    try {
      await _audio().loadStandalone(
        id: clipId(name),
        url: clip.url,
        title: name.arabic,
        album: album,
        contentType: 'names',
        artist: clip.reciter,
        owner: owner,
        clipStart: clip.start,
        clipEnd: clip.end,
      );
    } on Object {
      _setMissing(name.slug);
    }
  }

  Future<void> stop() async {
    _setPlaying(null);
    await _clipPlayer.stop();
    await _audio().stopStandaloneOf(owner);
  }

  void _setMissing(String? slug) {
    if (_missing == slug || _disposed) return;
    _missing = slug;
    notifyListeners();
  }

  void _setPlaying(String? slug) {
    if (_playing == slug || _disposed) return;
    _playing = slug;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_clipPlayer.dispose());
    super.dispose();
  }
}

typedef _Clip = ({String url, Duration start, Duration end, String reciter});

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../audio/audio_models.dart';
import '../audio/audio_repository.dart';
import 'tajweed_course_models.dart';

typedef TajweedAyahAudio = ({String recitationId, AyahPlayback playback});

/// The clips of one lesson in the shared player, as in the stage 2
/// breakdown: the lesson owns them, a step change stops them, the speed is
/// shared by the fragments and the whole ayah.
class TajweedCourseSound extends ChangeNotifier {
  TajweedCourseSound({
    required AudioController Function() audio,
    required AudioRepository repository,
    required Future<String?> Function() recitation,
  }) : _audio = audio,
       _repository = repository,
       _resolveRecitation = recitation;

  final AudioController Function() _audio;
  final AudioRepository _repository;
  final Future<String?> Function() _resolveRecitation;
  final owner = Object();
  final _ayahs = <String, Future<TajweedAyahAudio?>>{};
  late final Future<String?> _recitation = _recitationId();

  var _slow = false;
  String? _failed;

  bool get slow => _slow;

  /// The clip that failed to start.
  String? get failed => _failed;

  Future<String?> _recitationId() async {
    try {
      return await _resolveRecitation();
    } on Object {
      return null;
    }
  }

  /// The reciter's track and timings of [example]'s ayah; null without them.
  Future<TajweedAyahAudio?> ayah(TajweedCourseExample example) =>
      _ayahs.putIfAbsent(example.verseKey, () async {
        try {
          final recitationId = await _recitation;
          if (recitationId == null) return null;
          final playback = await _repository.ayahPlayback(
            recitationId: recitationId,
            surah: example.surah,
            ayah: example.ayah,
          );
          return (recitationId: recitationId, playback: playback);
        } on Object {
          // Without timings the example simply has nothing to play.
          return null;
        }
      });

  String clipId(TajweedAyahAudio audio, String verseKey, String part) =>
      'tajweed-course:${audio.recitationId}:$verseKey:$part';

  Future<void> play(
    TajweedAyahAudio audio,
    String id, {
    required String title,
    required String album,
    required ({Duration start, Duration end}) clip,
  }) async {
    _failed = null;
    notifyListeners();
    try {
      await _audio().loadStandalone(
        id: id,
        url: audio.playback.track.url,
        title: title,
        album: album,
        contentType: 'tajweed',
        owner: owner,
        speed: _slow ? .75 : 1,
        clipStart: clip.start,
        clipEnd: clip.end,
      );
    } on Object {
      _failed = id;
      notifyListeners();
    }
  }

  Future<void> stop(String id) => _audio().stopStandalone(id, owner: owner);

  /// Stops whichever clip of the lesson sounds. Safe during a build.
  Future<void> stopAll() => _audio().stopStandaloneOf(owner);

  /// Hides the failure of a clip, as a step change does.
  void clearFailure() {
    if (_failed == null) return;
    _failed = null;
    notifyListeners();
  }

  void setSlow(bool value, {String? playing}) {
    _slow = value;
    notifyListeners();
    if (playing != null) {
      unawaited(
        _audio().setStandaloneSpeed(playing, value ? .75 : 1, owner: owner),
      );
    }
  }
}

/// «Listen to the fragment» with «0.75×», and «Listen to the whole ayah»
/// unless [wholeAyah] is false. Without the reciter's timings the buttons
/// are not there.
class TajweedCourseSoundControls extends ConsumerWidget {
  const TajweedCourseSoundControls({
    required this.sound,
    required this.example,
    required this.occurrence,
    required this.part,
    this.wholeAyah = true,
    super.key,
  });

  final TajweedCourseSound sound;
  final TajweedCourseExample example;
  final TajweedOccurrence occurrence;

  /// Names the fragment's clip.
  final String part;
  final bool wholeAyah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(
      audioControllerProvider.select((state) {
        final standalone = state.standalone;
        return standalone == null
            ? null
            : (
                id: standalone.mediaItem.id,
                active: standalone.playing || standalone.loading,
                failed: standalone.error != null,
              );
      }),
    );
    return ListenableBuilder(
      listenable: sound,
      builder: (context, _) => FutureBuilder<TajweedAyahAudio?>(
        future: sound.ayah(example),
        builder: (context, snapshot) {
          final audio = snapshot.data;
          if (audio == null) return const SizedBox.shrink();
          final playback = audio.playback;
          final fragment = tajweedOccurrenceTiming(playback.words, occurrence);
          final whole =
              !wholeAyah || playback.start == null || playback.end == null
              ? null
              : (start: playback.start!, end: playback.end!);
          final fragmentId = sound.clipId(audio, example.verseKey, part);
          final ayahId = sound.clipId(audio, example.verseKey, 'ayah');
          bool active(String id) => clip?.id == id && clip!.active;
          final failed =
              sound.failed == fragmentId ||
              sound.failed == ayahId ||
              (clip != null &&
                  clip.failed &&
                  (clip.id == fragmentId || clip.id == ayahId));
          final album = 'IQRO · ${context.l10n.tajweedCourseTitle}';
          final current = clip != null && clip.active ? clip.id : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (fragment != null)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('tajweed-course-listen'),
                        onPressed: active(fragmentId)
                            ? () => sound.stop(fragmentId)
                            : () => sound.play(
                                audio,
                                fragmentId,
                                title: example.verseKey,
                                album: album,
                                clip: fragment,
                              ),
                        icon: Icon(
                          active(fragmentId)
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          active(fragmentId)
                              ? context.l10n.tajweedStop
                              : context.l10n.tajweedListen,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const ValueKey('tajweed-course-slow'),
                      label: Text(context.l10n.tajweedSlow),
                      tooltip: context.l10n.tajweedSlowLabel,
                      selected: sound.slow,
                      onSelected: (value) => sound.setSlow(
                        value,
                        playing: current == fragmentId || current == ayahId
                            ? current
                            : null,
                      ),
                    ),
                  ],
                ),
              if (whole != null)
                Center(
                  child: TextButton.icon(
                    key: const ValueKey('tajweed-course-play-ayah'),
                    onPressed: active(ayahId)
                        ? () => sound.stop(ayahId)
                        : () => sound.play(
                            audio,
                            ayahId,
                            title: example.verseKey,
                            album: album,
                            clip: whole,
                          ),
                    icon: Icon(
                      active(ayahId)
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      active(ayahId)
                          ? context.l10n.tajweedStop
                          : context.l10n.tajweedPlayAyah,
                    ),
                  ),
                ),
              if (failed)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    context.l10n.tajweedAudioError,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

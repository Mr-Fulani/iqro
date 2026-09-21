import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/preferences_store.dart';
import '../quran/quran_models.dart';
import 'audio_models.dart';
import 'reciter_catalog.dart';
import 'reciter_portraits.dart';
import 'premium_reciter_portrait.dart';

typedef _ReciterSelection = ({ReciterPerson person, Recitation recitation});

typedef PlayerChromeSnapshot = ({
  AudioTrack? track,
  Reciter? reciter,
  AudioPlaybackSource source,
  AudioPlaybackChannel channel,
  String surahName,
  bool playing,
  bool buffering,
  Duration duration,
  double speed,
  bool repeatEnabled,
  int? sleepTimerMinutes,
  List<AudioSegment> segments,
  int? activeAyah,
  int? rangeStartAyah,
  int? rangeEndAyah,
});

PlayerChromeSnapshot playerChromeSnapshot(IqroAudioState state) => (
  track: state.track,
  reciter: state.reciter,
  source: state.source,
  channel: state.channel,
  surahName: state.surahName,
  playing: state.playing,
  buffering: state.buffering,
  duration: state.duration,
  speed: state.speed,
  repeatEnabled: state.repeatEnabled,
  sleepTimerMinutes: state.sleepTimerMinutes,
  segments: state.segments,
  activeAyah: state.activeAyah,
  rangeStartAyah: state.rangeStartAyah,
  rangeEndAyah: state.rangeEndAyah,
);

IqroAudioState _audioStateFromChrome(PlayerChromeSnapshot chrome) =>
    IqroAudioState(
      track: chrome.track,
      reciter: chrome.reciter,
      source: chrome.source,
      channel: chrome.channel,
      surahName: chrome.surahName,
      playing: chrome.playing,
      buffering: chrome.buffering,
      duration: chrome.duration,
      speed: chrome.speed,
      repeatEnabled: chrome.repeatEnabled,
      sleepTimerMinutes: chrome.sleepTimerMinutes,
      segments: chrome.segments,
      activeAyah: chrome.activeAyah,
      rangeStartAyah: chrome.rangeStartAyah,
      rangeEndAyah: chrome.rangeEndAyah,
    );

String _recitationStyleLabel(BuildContext context, String style) =>
    switch (style) {
      'murattal' => context.l10n.styleMurattal,
      'mujawwad' => context.l10n.styleMujawwad,
      'muallim' => context.l10n.styleMuallim,
      _ => style,
    };

String _audioQualityLabel(BuildContext context, String quality) =>
    switch (quality) {
      'economy' => context.l10n.qualityEconomy,
      'standard' => context.l10n.qualityStandard,
      'high' => context.l10n.qualityHigh,
      _ => context.l10n.qualityAutomatic,
    };

Duration? compatibleRecitationPosition({
  required IqroAudioState current,
  required SurahPlayback target,
}) {
  final ayah = current.displayedAyah;
  final currentSegment = current.segmentForAyah(ayah);
  final targetSegment = target.segmentFor(ayah ?? 0);
  if (currentSegment == null || targetSegment == null) return null;
  final currentLength = currentSegment.end - currentSegment.start;
  final targetLength = targetSegment.end - targetSegment.start;
  if (currentLength <= Duration.zero || targetLength <= Duration.zero) {
    return null;
  }
  final elapsedMicroseconds = (current.position - currentSegment.start)
      .inMicroseconds
      .clamp(0, currentLength.inMicroseconds);
  final progress = elapsedMicroseconds / currentLength.inMicroseconds;
  final mappedMicroseconds =
      targetSegment.start.inMicroseconds +
      (targetLength.inMicroseconds * progress).round();
  return Duration(
    microseconds: mappedMicroseconds.clamp(
      targetSegment.start.inMicroseconds,
      targetSegment.end.inMicroseconds - 1,
    ),
  );
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  var _changingSurah = false;
  var _changingReciter = false;
  var _changingQuality = false;
  String? _ownerId;
  var _surahRequest = 0;
  var _reciterRequest = 0;
  var _qualityRequest = 0;

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(sessionProvider).valueOrNull?.userId;
    if (_ownerId != ownerId) {
      _ownerId = ownerId;
      _surahRequest += 1;
      _reciterRequest += 1;
      _qualityRequest += 1;
      _changingSurah = false;
      _changingReciter = false;
      _changingQuality = false;
    }
    final state = _audioStateFromChrome(
      ref.watch(audioControllerProvider.select(playerChromeSnapshot)),
    );
    final controller = ref.read(audioControllerProvider.notifier);
    final locale = Localizations.localeOf(context).languageCode;
    final currentSurah = state.track?.surah;
    final surahs =
        ref.watch(quranCatalogProvider).valueOrNull?.surahs ?? const <Surah>[];
    final reciters = ref.watch(recitersProvider).valueOrNull;
    final recitations = ref.watch(audioRecitationsProvider).valueOrNull;
    final currentRecitation = _recitationById(
      recitations,
      state.track?.recitationId,
    );
    final preferredQuality = ref.watch(
      appPreferencesProvider.select((value) => value.preferredAudioQuality),
    );
    final currentAyah = state.displayedAyah;
    final reciter = state.reciter;
    final portraitUrl = reciter == null
        ? null
        : resolveReciterPortraitUrl(
            reciter,
            apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
            reciters: reciters,
          );
    return Scaffold(
      backgroundColor: const Color(0xFF061D18),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Column(
          children: <Widget>[
            Text(
              context.l10n.nowPlaying,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              context.l10n.quranSubtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .6),
                fontSize: 11,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 28),
          child: Column(
            children: <Widget>[
              _Artwork(url: portraitUrl),
              const SizedBox(height: 28),
              IqroEyebrow(
                '${context.l10n.surah} ${state.track?.surah ?? '—'} · '
                '${context.l10n.ayah} ${currentAyah ?? '—'}',
                light: true,
              ),
              const SizedBox(height: 8),
              _SurahTitleButton(
                title: state.active ? state.surahName : context.l10n.noAudio,
                enabled:
                    state.active &&
                    surahs.isNotEmpty &&
                    !_changingSurah &&
                    !_changingReciter &&
                    !_changingQuality,
                onTap: () => _chooseSurah(surahs, currentSurah),
              ),
              const SizedBox(height: 8),
              _ReciterButton(
                name:
                    state.reciter?.nameFor(locale) ??
                    context.l10n.chooseReciter,
                style: currentRecitation == null
                    ? null
                    : _recitationStyleLabel(context, currentRecitation.style),
                loading: _changingReciter,
                enabled:
                    state.active &&
                    reciters != null &&
                    recitations != null &&
                    !_changingSurah &&
                    !_changingReciter &&
                    !_changingQuality,
                onTap: () => _chooseReciter(
                  reciters: reciters ?? const <Reciter>[],
                  recitations: recitations ?? const <Recitation>[],
                  currentRecitation: currentRecitation,
                ),
              ),
              const SizedBox(height: 26),
              _PlayerTransport(
                sourceChangeInProgress:
                    _changingSurah || _changingReciter || _changingQuality,
                onPreviousSurah: () => _changeSurah(-1),
                onNextSurah: () => _changeSurah(1),
              ),
              const SizedBox(height: 24),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.25,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  _PlayerOption(
                    icon: Icons.speed,
                    title: context.l10n.speed,
                    value: '${state.speed}×',
                    onTap: () => _chooseSpeed(context, controller, state.speed),
                  ),
                  _PlayerOption(
                    icon: Icons.timer_outlined,
                    title: context.l10n.sleepTimer,
                    value: state.sleepTimerMinutes == null
                        ? context.l10n.off
                        : '${state.sleepTimerMinutes} ${context.l10n.minutes}',
                    onTap: () => _chooseTimer(context, controller),
                  ),
                  _PlayerOption(
                    icon: Icons.layers_outlined,
                    title: context.l10n.range,
                    value: _rangeValue(context, state),
                    onTap: state.segments.isEmpty
                        ? null
                        : () => _chooseRange(context, controller, state),
                  ),
                  _PlayerOption(
                    icon: Icons.repeat,
                    title: context.l10n.repeat,
                    value: state.repeatEnabled
                        ? context.l10n.repeatOn
                        : context.l10n.repeatOff,
                    onTap: controller.toggleRepeat,
                  ),
                  _PlayerOption(
                    icon: Icons.graphic_eq_rounded,
                    title: context.l10n.audioQuality,
                    value: _qualityValue(
                      context,
                      state.track,
                      preferredQuality,
                    ),
                    onTap:
                        state.track != null &&
                            state.track!.renditions.isNotEmpty &&
                            !_changingSurah &&
                            !_changingReciter &&
                            !_changingQuality
                        ? () => _chooseQuality(
                            controller: controller,
                            state: state,
                            preferredQuality: preferredQuality,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Recitation? _recitationById(List<Recitation>? recitations, String? id) {
    if (recitations == null || id == null) return null;
    for (final recitation in recitations) {
      if (recitation.id == id) return recitation;
    }
    return null;
  }

  String _qualityValue(
    BuildContext context,
    AudioTrack? track,
    String preferredQuality,
  ) {
    final label = preferredQuality == defaultPreferredAudioQuality
        ? context.l10n.qualityAutomatic
        : _audioQualityLabel(
            context,
            track?.renditionQuality ?? preferredQuality,
          );
    final bitrate = track?.bitrateKbps;
    return bitrate == null || bitrate <= 0
        ? label
        : '$label · ${context.l10n.audioBitrate(bitrate)}';
  }

  Future<void> _chooseReciter({
    required List<Reciter> reciters,
    required List<Recitation> recitations,
    required Recitation? currentRecitation,
  }) async {
    if (_changingSurah ||
        _changingReciter ||
        _changingQuality ||
        reciters.isEmpty) {
      return;
    }
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_sessionMatches(scope)) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final player = ref.read(audioControllerProvider);
    if (!player.active || !_isCurrentController(scope, controller)) return;
    final people = groupRecitersByPerson(reciters);
    if (people.isEmpty || recitations.isEmpty) return;
    final selection = await showModalBottomSheet<_ReciterSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: _ReciterPickerSheet(
          people: people,
          recitations: recitations,
          currentRecitationId: player.track?.recitationId,
          initialStyle: currentRecitation?.style ?? defaultRecitationStyle,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
        ),
      ),
    );
    if (selection == null ||
        selection.recitation.id == player.track?.recitationId ||
        !_isCurrentController(scope, controller)) {
      return;
    }
    await _loadReciter(
      selection,
      expectedScope: scope,
      expectedController: controller,
    );
  }

  Future<void> _loadReciter(
    _ReciterSelection selection, {
    required AccountScopeSnapshot expectedScope,
    required AudioController expectedController,
  }) async {
    if (_changingSurah || _changingReciter || _changingQuality) return;
    if (!_isCurrentController(expectedScope, expectedController)) return;
    final current = ref.read(audioControllerProvider);
    final surah = current.track?.surah;
    if (surah == null) return;
    final request = ++_reciterRequest;
    setState(() => _changingReciter = true);
    try {
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: selection.recitation.id, surah: surah);
      if (!_isCurrentReciterRequest(
            expectedScope,
            expectedController,
            request,
          ) ||
          ref.read(audioControllerProvider).track?.id != current.track?.id) {
        return;
      }
      final mappedPosition = compatibleRecitationPosition(
        current: current,
        target: playback,
      );
      final preserveRange =
          current.hasActiveRange &&
          playback.segmentFor(current.rangeStartAyah ?? 0) != null &&
          playback.segmentFor(current.rangeEndAyah ?? 0) != null;
      await expectedController.loadPlayback(
        playback: playback,
        reciter: reciterWithPersonPortrait(
          selection.recitation.reciter,
          apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
          reciters: selection.person.sources,
        ),
        channel: current.channel,
        surahName: current.surahName,
        startAyah: preserveRange ? current.rangeStartAyah : null,
        endAyah: preserveRange ? current.rangeEndAyah : null,
        autoplay: false,
      );
      if (!_isCurrentReciterRequest(
        expectedScope,
        expectedController,
        request,
      )) {
        return;
      }
      if (mappedPosition != null) {
        await expectedController.seek(mappedPosition);
      }
      if (!_isCurrentReciterRequest(
        expectedScope,
        expectedController,
        request,
      )) {
        return;
      }
      if (current.playing) await expectedController.toggle();
      if (!_isCurrentReciterRequest(
        expectedScope,
        expectedController,
        request,
      )) {
        return;
      }
      if (current.channel == AudioPlaybackChannel.listening) {
        unawaited(
          ref
              .read(appPreferencesProvider.notifier)
              .setListeningRecitation(selection.recitation.id),
        );
      }
    } on AccountScopeChanged {
      return;
    } on Object {
      if (!_isCurrentReciterRequest(
        expectedScope,
        expectedController,
        request,
      )) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
    } finally {
      if (mounted && request == _reciterRequest) {
        setState(() => _changingReciter = false);
      }
    }
  }

  Future<void> _changeSurah(int direction) async {
    final player = ref.read(audioControllerProvider);
    final currentSurah = player.track?.surah;
    if (currentSurah == null) return;

    final targetSurah = currentSurah + direction;
    await _loadSurah(targetSurah);
  }

  Future<void> _chooseSurah(List<Surah> surahs, int? currentSurah) async {
    if (_changingSurah ||
        _changingReciter ||
        _changingQuality ||
        surahs.isEmpty) {
      return;
    }
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_sessionMatches(scope)) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final targetSurah = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: _SurahPickerSheet(surahs: surahs, currentSurah: currentSurah),
      ),
    );
    if (!_isCurrentController(scope, controller) ||
        targetSurah == null ||
        targetSurah == currentSurah) {
      return;
    }
    await _loadSurah(
      targetSurah,
      expectedScope: scope,
      expectedController: controller,
    );
  }

  Future<void> _loadSurah(
    int targetSurah, {
    AccountScopeSnapshot? expectedScope,
    AudioController? expectedController,
  }) async {
    if (_changingSurah ||
        _changingReciter ||
        _changingQuality ||
        targetSurah < 1 ||
        targetSurah > 114) {
      return;
    }
    final scope =
        expectedScope ?? ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_sessionMatches(scope)) return;
    final controller =
        expectedController ?? ref.read(audioControllerProvider.notifier);
    if (controller == null) return;
    if (!_isCurrentController(scope, controller)) return;
    final player = ref.read(audioControllerProvider);
    final reciter = player.reciter;
    final recitationId = player.track?.recitationId;
    if (reciter == null || recitationId == null) return;

    final locale = Localizations.localeOf(context).languageCode;
    var surahName = '${context.l10n.surah} $targetSurah';
    final catalog = ref.read(quranCatalogProvider).valueOrNull;
    if (catalog != null) {
      for (final surah in catalog.surahs) {
        if (surah.number == targetSurah) {
          surahName = surah.nameFor(locale);
          break;
        }
      }
    }

    final request = ++_surahRequest;
    setState(() => _changingSurah = true);
    try {
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: recitationId, surah: targetSurah);
      if (!_isCurrentSurahRequest(scope, controller, request)) return;
      await controller.loadPlayback(
        playback: playback,
        reciter: reciter,
        channel: player.channel,
        surahName: surahName,
      );
    } on AccountScopeChanged {
      return;
    } on Object {
      if (!_isCurrentSurahRequest(scope, controller, request)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
    } finally {
      if (mounted && request == _surahRequest) {
        setState(() => _changingSurah = false);
      }
    }
  }

  Future<void> _chooseSpeed(
    BuildContext context,
    AudioController controller,
    double current,
  ) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentController(scope, controller)) return;
    final speed = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final value in const <double>[.75, 1, 1.25, 1.5, 2])
                ListTile(
                  leading: Icon(
                    value == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text('$value×'),
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (speed != null && _isCurrentController(scope, controller)) {
      await controller.setSpeed(speed);
    }
  }

  Future<void> _chooseQuality({
    required AudioController controller,
    required IqroAudioState state,
    required String preferredQuality,
  }) async {
    final track = state.track;
    final reciter = state.reciter;
    if (track == null || reciter == null || track.renditions.isEmpty) return;
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentController(scope, controller)) return;
    final qualities = track.renditions
        .map((item) => item.quality)
        .where(supportedAudioQualityPreferences.contains)
        .toSet()
        .toList(growable: false);
    final selection = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => _AudioQualitySheet(
        renditions: track.renditions,
        qualities: qualities,
        selected: preferredQuality,
      ),
    );
    if (selection == null ||
        selection == preferredQuality ||
        !_isCurrentController(scope, controller)) {
      return;
    }
    await ref
        .read(appPreferencesProvider.notifier)
        .setPreferredAudioQuality(selection);
    if (!_isCurrentController(scope, controller)) return;
    final current = ref.read(audioControllerProvider);
    final currentTrack = current.track;
    final currentReciter = current.reciter;
    if (currentTrack == null ||
        currentReciter == null ||
        currentTrack.id != track.id) {
      return;
    }
    final targetTrack = currentTrack.withPreferredQuality(selection);
    if (targetTrack.url == currentTrack.url) return;
    final request = ++_qualityRequest;
    setState(() => _changingQuality = true);
    try {
      await controller.loadPlayback(
        playback: SurahPlayback(track: targetTrack, segments: current.segments),
        reciter: currentReciter,
        channel: current.channel,
        surahName: current.surahName,
        startAyah: current.rangeStartAyah,
        endAyah: current.rangeEndAyah,
        autoplay: false,
      );
      if (!_isCurrentQualityRequest(scope, controller, request)) return;
      await controller.seek(current.position);
      if (!_isCurrentQualityRequest(scope, controller, request)) return;
      if (current.playing) await controller.toggle();
    } on AccountScopeChanged {
      return;
    } on Object {
      if (!_isCurrentQualityRequest(scope, controller, request) || !mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
    } finally {
      if (mounted && request == _qualityRequest) {
        setState(() => _changingQuality = false);
      }
    }
  }

  Future<void> _chooseTimer(
    BuildContext context,
    AudioController controller,
  ) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentController(scope, controller)) return;
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(context.l10n.off),
              onTap: () => Navigator.pop(context, 0),
            ),
            for (final value in const <int>[10, 20, 30, 60])
              ListTile(
                title: Text('$value ${context.l10n.minutes}'),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (!_isCurrentController(scope, controller)) return;
    controller.setSleepTimer(
      minutes == null || minutes == 0 ? null : Duration(minutes: minutes),
    );
  }

  String _rangeValue(BuildContext context, IqroAudioState state) {
    if (state.segments.isEmpty) return context.l10n.noAudio;
    final start = state.rangeStartAyah ?? state.segments.first.ayah;
    final end = state.rangeEndAyah ?? state.segments.last.ayah;
    return start == end
        ? '${context.l10n.ayah} $start'
        : '${context.l10n.ayah} $start–$end';
  }

  Future<void> _chooseRange(
    BuildContext context,
    AudioController controller,
    IqroAudioState state,
  ) async {
    final scope = ref.read(localDatabaseProvider).accountScope.current;
    if (scope == null || !_isCurrentController(scope, controller)) return;
    final ayahs = state.segments.map((item) => item.ayah).toSet().toList()
      ..sort();
    if (ayahs.isEmpty) return;
    final minimum = ayahs.first;
    final maximum = ayahs.last;
    var values = RangeValues(
      (state.rangeStartAyah ?? minimum).clamp(minimum, maximum).toDouble(),
      (state.rangeEndAyah ?? maximum).clamp(minimum, maximum).toDouble(),
    );
    final selected = await showModalBottomSheet<List<int>>(
      context: context,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.l10n.range,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${context.l10n.ayah} ${values.start.round()}–${values.end.round()}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              RangeSlider(
                values: values,
                min: minimum.toDouble(),
                max: maximum.toDouble(),
                divisions: maximum - minimum,
                labels: RangeLabels(
                  '${values.start.round()}',
                  '${values.end.round()}',
                ),
                onChanged: (next) => setSheetState(() => values = next),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, <int>[
                    values.start.round(),
                    values.end.round(),
                  ]),
                  child: Text(context.l10n.done),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !_isCurrentController(scope, controller)) return;
    try {
      await controller.setAyahRange(selected[0], selected[1]);
    } on Object {
      if (!_isCurrentController(scope, controller) || !context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
    }
  }

  bool _sessionMatches(AccountScopeSnapshot scope) =>
      ref.read(sessionProvider).valueOrNull?.userId == scope.userId;

  bool _isCurrentController(
    AccountScopeSnapshot scope,
    AudioController controller,
  ) {
    return mounted &&
        _sessionMatches(scope) &&
        ref.read(localDatabaseProvider).accountScope.isCurrent(scope) &&
        identical(ref.read(audioControllerProvider.notifier), controller);
  }

  bool _isCurrentSurahRequest(
    AccountScopeSnapshot scope,
    AudioController controller,
    int request,
  ) => request == _surahRequest && _isCurrentController(scope, controller);

  bool _isCurrentReciterRequest(
    AccountScopeSnapshot scope,
    AudioController controller,
    int request,
  ) => request == _reciterRequest && _isCurrentController(scope, controller);

  bool _isCurrentQualityRequest(
    AccountScopeSnapshot scope,
    AudioController controller,
    int request,
  ) => request == _qualityRequest && _isCurrentController(scope, controller);
}

class _PlayerTransport extends ConsumerStatefulWidget {
  const _PlayerTransport({
    required this.sourceChangeInProgress,
    required this.onPreviousSurah,
    required this.onNextSurah,
  });

  final bool sourceChangeInProgress;
  final VoidCallback onPreviousSurah;
  final VoidCallback onNextSurah;

  @override
  ConsumerState<_PlayerTransport> createState() => _PlayerTransportState();
}

class _PlayerTransportState extends ConsumerState<_PlayerTransport> {
  static const _metaStyle = TextStyle(color: Color(0x99FFFFFF), fontSize: 11);

  double? _seekPreviewMilliseconds;
  ({String? trackId, int? startAyah, int? endAyah})? _renderedIdentity;
  ({String? trackId, int? startAyah, int? endAyah})? _dragIdentity;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final durationMs = state.effectiveDuration.inMilliseconds;
    final playbackIdentity = (
      trackId: state.track?.id,
      startAyah: state.rangeStartAyah,
      endAyah: state.rangeEndAyah,
    );
    if (_renderedIdentity != playbackIdentity) {
      _renderedIdentity = playbackIdentity;
      _seekPreviewMilliseconds = null;
      // A source/range replacement invalidates a gesture that started on the
      // previous timeline. Its eventual pointer-up must not seek a new source.
      _dragIdentity = null;
    }
    final livePositionMs = state.relativePosition.inMilliseconds.clamp(
      0,
      durationMs == 0 ? 1 : durationMs,
    );
    final positionMs = (_seekPreviewMilliseconds ?? livePositionMs.toDouble())
        .clamp(0, durationMs <= 0 ? 1 : durationMs)
        .toDouble();
    final currentSurah = state.track?.surah;
    final controlsEnabled =
        state.active && !state.buffering && !widget.sourceChangeInProgress;

    return Column(
      children: <Widget>[
        Slider(
          value: positionMs,
          min: 0,
          max: durationMs <= 0 ? 1 : durationMs.toDouble(),
          onChangeStart: state.active && durationMs > 0
              ? (value) {
                  setState(() {
                    _dragIdentity = playbackIdentity;
                    _seekPreviewMilliseconds = value;
                  });
                }
              : null,
          onChanged: state.active && durationMs > 0
              ? (value) {
                  if (_dragIdentity == null) return;
                  setState(() => _seekPreviewMilliseconds = value);
                }
              : null,
          onChangeEnd: state.active && durationMs > 0
              ? (value) {
                  final identity = _dragIdentity;
                  setState(() {
                    _dragIdentity = null;
                    _seekPreviewMilliseconds = null;
                  });
                  if (identity?.trackId == null) return;
                  unawaited(
                    controller.seekInActiveRange(
                      Duration(milliseconds: value.round()),
                      expectedTrackId: identity!.trackId!,
                      expectedStartAyah: identity.startAyah,
                      expectedEndAyah: identity.endAyah,
                    ),
                  );
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                _duration(Duration(milliseconds: positionMs.round())),
                style: _metaStyle,
              ),
              Text(_duration(state.effectiveDuration), style: _metaStyle),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              onPressed: controlsEnabled
                  ? () => controller.seekInActiveRange(
                      Duration(
                        milliseconds: (positionMs.round() - 10000).clamp(
                          0,
                          durationMs,
                        ),
                      ),
                    )
                  : null,
              color: Colors.white,
              iconSize: 28,
              icon: const Icon(Icons.replay_10),
            ),
            IconButton(
              tooltip: context.l10n.previousSurah,
              onPressed:
                  controlsEnabled && currentSurah != null && currentSurah > 1
                  ? widget.onPreviousSurah
                  : null,
              color: Colors.white,
              icon: const Icon(Icons.skip_previous),
            ),
            SizedBox(
              width: 72,
              height: 72,
              child: IconButton.filled(
                tooltip: state.playing ? context.l10n.pause : context.l10n.play,
                onPressed: controlsEnabled ? controller.toggle : null,
                iconSize: 38,
                icon: state.buffering || widget.sourceChangeInProgress
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(state.playing ? Icons.pause : Icons.play_arrow),
              ),
            ),
            IconButton(
              tooltip: context.l10n.nextSurah,
              onPressed:
                  controlsEnabled && currentSurah != null && currentSurah < 114
                  ? widget.onNextSurah
                  : null,
              color: Colors.white,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              onPressed: controlsEnabled
                  ? () => controller.seekInActiveRange(
                      Duration(
                        milliseconds: (positionMs.round() + 10000).clamp(
                          0,
                          durationMs,
                        ),
                      ),
                    )
                  : null,
              color: Colors.white,
              iconSize: 28,
              icon: const Icon(Icons.forward_10),
            ),
          ],
        ),
      ],
    );
  }

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _AudioQualitySheet extends StatelessWidget {
  const _AudioQualitySheet({
    required this.renditions,
    required this.qualities,
    required this.selected,
  });

  final List<AudioRendition> renditions;
  final List<String> qualities;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final defaultRendition = renditions
        .where((item) => item.isDefault)
        .firstOrNull;
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (value) => Navigator.pop(context, value),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
              child: Text(
                context.l10n.audioQuality,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            RadioListTile<String>(
              value: defaultPreferredAudioQuality,
              title: Text(context.l10n.qualityAutomatic),
              subtitle: defaultRendition == null
                  ? null
                  : Text(_renditionDetails(context, defaultRendition)),
            ),
            for (final quality in qualities)
              RadioListTile<String>(
                value: quality,
                title: Text(_audioQualityLabel(context, quality)),
                subtitle: Text(
                  _renditionDetails(
                    context,
                    renditions.firstWhere((item) => item.quality == quality),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _renditionDetails(BuildContext context, AudioRendition rendition) {
    final bitrate = context.l10n.audioBitrate(rendition.bitrateKbps);
    final codec = rendition.codec.trim().toUpperCase();
    return codec.isEmpty ? bitrate : '$bitrate · $codec';
  }
}

class _ReciterButton extends StatelessWidget {
  const _ReciterButton({
    required this.name,
    required this.style,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final String name;
  final String? style;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? Colors.white.withValues(alpha: .82)
        : Colors.white.withValues(alpha: .48);
    return Semantics(
      button: enabled,
      label: context.l10n.chooseReciter,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 6, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (style != null)
                        Text(
                          style!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .5),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                if (loading)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(Icons.expand_more_rounded, color: foreground, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReciterPickerSheet extends StatefulWidget {
  const _ReciterPickerSheet({
    required this.people,
    required this.recitations,
    required this.currentRecitationId,
    required this.initialStyle,
    required this.apiBaseUrl,
  });

  final List<ReciterPerson> people;
  final List<Recitation> recitations;
  final String? currentRecitationId;
  final String initialStyle;
  final String apiBaseUrl;

  @override
  State<_ReciterPickerSheet> createState() => _ReciterPickerSheetState();
}

class _ReciterPickerSheetState extends State<_ReciterPickerSheet> {
  late String _style;

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final styles = orderedRecitationStyles(widget.recitations);
    final selectedStyle = styles.contains(_style)
        ? _style
        : styles.firstOrNull ?? defaultRecitationStyle;
    final people = widget.people
        .where(
          (person) =>
              recitationForPersonStyle(
                person,
                widget.recitations,
                selectedStyle,
              ) !=
              null,
        )
        .toList(growable: false);
    return Column(
      children: <Widget>[
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 10, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.l10n.chooseReciter,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final style in styles)
                  ChoiceChip(
                    label: Text(_recitationStyleLabel(context, style)),
                    selected: style == selectedStyle,
                    onSelected: (_) => setState(() => _style = style),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = switch (constraints.maxWidth) {
                < 380 => 3,
                < 700 => 4,
                _ => 6,
              };
              return GridView.builder(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 20),
                itemCount: people.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 132,
                ),
                itemBuilder: (context, index) {
                  final person = people[index];
                  final recitation = recitationForPersonStyle(
                    person,
                    widget.recitations,
                    selectedStyle,
                    preferredId: widget.currentRecitationId,
                  )!;
                  return _PickerReciterCard(
                    person: person,
                    locale: locale,
                    portraitUrl: resolveReciterPortraitUrl(
                      person.portraitSource,
                      apiBaseUrl: widget.apiBaseUrl,
                    ),
                    selected: recitation.id == widget.currentRecitationId,
                    onTap: () => Navigator.pop<_ReciterSelection>(context, (
                      person: person,
                      recitation: recitation,
                    )),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PickerReciterCard extends StatelessWidget {
  const _PickerReciterCard({
    required this.person,
    required this.locale,
    required this.portraitUrl,
    required this.selected,
    required this.onTap,
  });

  final ReciterPerson person;
  final String locale;
  final String? portraitUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: person.primary.nameFor(locale),
      child: Material(
        color: selected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    PremiumReciterPortrait(
                      url: portraitUrl,
                      size: 70,
                      initials: person.primary.initials,
                      selected: selected,
                    ),
                    if (selected)
                      PositionedDirectional(
                        end: -2,
                        bottom: -2,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: colorScheme.primary,
                          child: Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  person.primary.nameFor(locale),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SurahTitleButton extends StatelessWidget {
  const _SurahTitleButton({
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled
        ? Colors.white
        : Colors.white.withValues(alpha: .62);
    return Semantics(
      button: enabled,
      label: context.l10n.chooseSurah,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 8, 5),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 5,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(color: foreground),
                ),
                Icon(Icons.expand_more_rounded, color: foreground, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SurahPickerSheet extends StatefulWidget {
  const _SurahPickerSheet({required this.surahs, required this.currentSurah});

  final List<Surah> surahs;
  final int? currentSurah;

  @override
  State<_SurahPickerSheet> createState() => _SurahPickerSheetState();
}

class _SurahPickerSheetState extends State<_SurahPickerSheet> {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _scrollController = ScrollController(
      initialScrollOffset: ((widget.currentSurah ?? 1) - 1) * 68.0,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? widget.surahs
        : widget.surahs
              .where(
                (surah) =>
                    surah.number.toString().contains(normalizedQuery) ||
                    surah.nameAr.toLowerCase().contains(normalizedQuery) ||
                    surah.nameEn.toLowerCase().contains(normalizedQuery) ||
                    surah.nameRu.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);
    return Column(
      children: <Widget>[
        const SizedBox(height: 10),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 10, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.l10n.chooseSurah,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.l10n.search,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: normalizedQuery.isEmpty ? _scrollController : null,
            itemExtent: 68,
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final surah = filtered[index];
              final selected = surah.number == widget.currentSurah;
              final primaryName = surah.nameFor(locale);
              final secondaryName = locale == 'ar'
                  ? surah.nameEn
                  : surah.nameAr;
              return ListTile(
                selected: selected,
                leading: CircleAvatar(child: Text('${surah.number}')),
                title: Text(
                  primaryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  secondaryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: locale == 'ar'
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                ),
                trailing: selected ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, surah.number),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return PremiumReciterPortrait(url: url, size: 210, selected: true);
  }
}

class _PlayerOption extends StatelessWidget {
  const _PlayerOption({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D3029),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFFB6E8D9)),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

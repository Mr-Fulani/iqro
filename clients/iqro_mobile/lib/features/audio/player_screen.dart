import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../quran/quran_models.dart';
import 'reciter_portraits.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  var _changingSurah = false;
  double? _seekPreviewMilliseconds;
  ({String? trackId, int? startAyah, int? endAyah})? _renderedIdentity;
  ({String? trackId, int? startAyah, int? endAyah})? _dragIdentity;
  String? _ownerId;
  var _surahRequest = 0;

  @override
  Widget build(BuildContext context) {
    final ownerId = ref.watch(sessionProvider).valueOrNull?.userId;
    if (_ownerId != ownerId) {
      _ownerId = ownerId;
      _surahRequest += 1;
      _changingSurah = false;
      _seekPreviewMilliseconds = null;
      _dragIdentity = null;
    }
    final state = ref.watch(audioControllerProvider);
    final controller = ref.read(audioControllerProvider.notifier);
    final locale = Localizations.localeOf(context).languageCode;
    final currentSurah = state.track?.surah;
    final surahs =
        ref.watch(quranCatalogProvider).valueOrNull?.surahs ?? const <Surah>[];
    final controlsEnabled = state.active && !state.buffering && !_changingSurah;
    final durationMs = state.effectiveDuration.inMilliseconds;
    final playbackIdentity = (
      trackId: state.track?.id,
      startAyah: state.rangeStartAyah,
      endAyah: state.rangeEndAyah,
    );
    if (_renderedIdentity != playbackIdentity) {
      _renderedIdentity = playbackIdentity;
      _seekPreviewMilliseconds = null;
      // A source/range replacement invalidates any gesture that started on
      // the previous timeline. Its eventual pointer-up must not seek the new
      // source, even if Flutter rebuilds the Slider mid-drag.
      _dragIdentity = null;
    }
    final livePositionMs = state.relativePosition.inMilliseconds.clamp(
      0,
      durationMs == 0 ? 1 : durationMs,
    );
    final positionMs = (_seekPreviewMilliseconds ?? livePositionMs.toDouble())
        .clamp(0, durationMs <= 0 ? 1 : durationMs)
        .toDouble();
    final currentAyah = state.displayedAyah;
    final reciter = state.reciter;
    final portraitUrl = reciter == null
        ? null
        : resolveReciterPortraitUrl(
            reciter,
            apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
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
                enabled: state.active && surahs.isNotEmpty && !_changingSurah,
                onTap: () => _chooseSurah(surahs, currentSurah),
              ),
              const SizedBox(height: 8),
              Text(
                state.reciter?.nameFor(locale) ?? context.l10n.chooseReciter,
                style: TextStyle(color: Colors.white.withValues(alpha: .65)),
              ),
              const SizedBox(height: 26),
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
                        controlsEnabled &&
                            currentSurah != null &&
                            currentSurah > 1
                        ? () => _changeSurah(-1)
                        : null,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: IconButton.filled(
                      tooltip: state.playing
                          ? context.l10n.pause
                          : context.l10n.play,
                      onPressed: controlsEnabled ? controller.toggle : null,
                      iconSize: 38,
                      icon: state.buffering || _changingSurah
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : Icon(
                              state.playing ? Icons.pause : Icons.play_arrow,
                            ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.nextSurah,
                    onPressed:
                        controlsEnabled &&
                            currentSurah != null &&
                            currentSurah < 114
                        ? () => _changeSurah(1)
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _metaStyle = TextStyle(color: Color(0x99FFFFFF), fontSize: 11);

  static String _duration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _changeSurah(int direction) async {
    final player = ref.read(audioControllerProvider);
    final currentSurah = player.track?.surah;
    if (currentSurah == null) return;

    final targetSurah = currentSurah + direction;
    await _loadSurah(targetSurah);
  }

  Future<void> _chooseSurah(List<Surah> surahs, int? currentSurah) async {
    if (_changingSurah || surahs.isEmpty) return;
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
    if (_changingSurah || targetSurah < 1 || targetSurah > 114) return;
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
    final fallback = const ColoredBox(
      color: Color(0xFF255E51),
      child: Center(
        child: Icon(Icons.person_rounded, size: 72, color: Color(0xFFB6E8D9)),
      ),
    );
    return Container(
      width: 210,
      height: 210,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: <Color>[
            Color(0xFF2E7463),
            Color(0xFF0C392F),
            Color(0xFF061D18),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: ClipOval(
        child: url == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (context, url) => fallback,
                errorWidget: (context, url, error) => fallback,
              ),
      ),
    );
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/iqro_icon.dart';
import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/audio/playback_speed.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/preferences_store.dart';
import 'audio_models.dart';
import 'listening_queue.dart';
import 'premium_reciter_portrait.dart';
import 'reciter_portraits.dart';

final miniPlayerCollapsedProvider = StateProvider<bool>((ref) => true);

/// True while the fold hint slides the bar aside, as a finger swiping it would.
final miniPlayerHintNudgeProvider = StateProvider<bool>((ref) => false);

/// The bar is 66 dp tall, so a short swipe in any direction rolls it up; the
/// site uses the same reach (services/web/lib/mini-player.ts).
const _swipeCollapseDistance = 32.0;
const _swipeCollapseFlick = 16.0;
const _swipeCollapseVelocity = 500.0;

/// A swipe of [distance] dp, whichever way, at [velocity] dp/s.
bool _swipeRollsUp(double distance, double velocity) =>
    distance >= _swipeCollapseDistance ||
    (distance >= _swipeCollapseFlick && velocity >= _swipeCollapseVelocity);

/// Until someone folds the bar themselves, it shows how on Home: it slides
/// aside as if swiped, rolls up and comes back, at most every
/// [miniPlayerHintGap] and [miniPlayerHintLimit] times in all.
const miniPlayerHintGap = Duration(hours: 6);
const miniPlayerHintDelay = Duration(milliseconds: 2500);
const miniPlayerHintHold = Duration(milliseconds: 1600);
const miniPlayerHintNudge = Duration(milliseconds: 280);

bool miniPlayerHintDue({
  required int shown,
  required DateTime? lastShownAt,
  required DateTime now,
}) =>
    shown < miniPlayerHintLimit &&
    (lastShownAt == null || now.difference(lastShownAt) >= miniPlayerHintGap);

/// Plays the fold once and leaves the bar as it found it: a folded bar opens,
/// waits, slides aside and folds; an open one slides aside, folds, waits and
/// opens. Anything the person does meanwhile ends it.
class MiniPlayerHint {
  MiniPlayerHint.show(WidgetRef ref) : _ref = ref {
    final folded = _collapsed.state;
    if (folded) {
      _collapsed.state = false;
      _after(miniPlayerHintHold, () => _fold(then: null));
    } else {
      _fold(then: () => _collapsed.state = false);
    }
  }

  final WidgetRef _ref;
  Timer? _timer;
  var _expected = false;

  StateController<bool> get _collapsed =>
      _ref.read(miniPlayerCollapsedProvider.notifier);
  StateController<bool> get _nudge =>
      _ref.read(miniPlayerHintNudgeProvider.notifier);

  void _fold({required VoidCallback? then}) {
    _nudge.state = true;
    _after(miniPlayerHintNudge, () {
      _nudge.state = false;
      _collapsed.state = true;
      if (then != null) _after(miniPlayerHintHold, then);
    });
  }

  void _after(Duration delay, VoidCallback step) {
    _expected = _collapsed.state;
    _timer = Timer(delay, () {
      if (_collapsed.state != _expected) return cancel();
      step();
      _expected = _collapsed.state;
    });
  }

  void cancel() {
    _timer?.cancel();
    if (_nudge.state) _nudge.state = false;
  }

  /// Stops the timer only, for a disposed owner that may not read providers.
  void stop() => _timer?.cancel();
}

class IqroMiniPlayer extends ConsumerStatefulWidget {
  const IqroMiniPlayer({
    this.allowCollapse = true,
    this.mushafControls = false,
    this.onReciterTap,
    this.onRepeatTap,
    this.onSwipeAway,
    super.key,
  });

  /// Mushaf has its own reader controls, so its inline player stays expanded.
  final bool allowCollapse;

  /// The Mushaf's player reads its page, so no surah skipping. The portrait
  /// opens the reciters ([onReciterTap]); under the title are the speed and
  /// the ayah repeat ([onRepeatTap]).
  final bool mushafControls;
  final VoidCallback? onReciterTap;
  final VoidCallback? onRepeatTap;

  /// Where the bar does not fold itself, a swipe hands it to the screen, as
  /// the Mushaf does with its round play button.
  final VoidCallback? onSwipeAway;

  @override
  ConsumerState<IqroMiniPlayer> createState() => _IqroMiniPlayerState();
}

class _IqroMiniPlayerState extends ConsumerState<IqroMiniPlayer> {
  var _changingSurah = false;
  var _changeRequest = 0;
  AudioController? _visibleController;

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(audioControllerProvider.notifier);
    // The mini player shows no progress, so position ticks must not rebuild it.
    final player = ref.watch(
      audioControllerProvider.select(
        widget.mushafControls
            ? iqroAudioPresentation
            : controller.listeningPresentation,
      ),
    );
    final standalone = player.standalone;
    if (!identical(_visibleController, controller)) {
      _visibleController = controller;
      _changeRequest += 1;
      _changingSurah = false;
    }
    final locale = Localizations.localeOf(context).languageCode;
    final currentSurah = player.track?.surah;
    final reciter = player.reciter;
    final catalog = ref.watch(recitersProvider).valueOrNull;
    final portraitUrl = reciter == null
        ? null
        : resolveReciterPortraitUrl(
            reciter,
            apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
            reciters: catalog,
          );
    final thumbnailUrl = reciter == null
        ? null
        : resolveReciterThumbnailUrl(
            reciter,
            apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
            reciters: catalog,
          );
    final controlsEnabled =
        (player.track != null || standalone != null) &&
        !player.buffering &&
        !_changingSurah;
    // The catalog only matters once there is a surah to move from.
    final held = recitationHeldSurahs(
      player.track == null
          ? null
          : _recitationById(
              ref.watch(audioRecitationsProvider).valueOrNull,
              player.track?.recitationId,
            ),
    );
    final navigationMode = _navigationMode(
      player.channel,
      ref.watch(audioControllerProvider.select((value) => value.queueMode)),
    );
    final collapsed =
        widget.allowCollapse && ref.watch(miniPlayerCollapsedProvider);
    final artwork = standalone == null
        ? PremiumReciterPortrait(
            url: portraitUrl,
            thumbnailUrl: thumbnailUrl,
            size: 44,
          )
        : Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF163C33),
              shape: BoxShape.circle,
            ),
            child: const IqroIcon(
              Icons.menu_book_rounded,
              color: Color(0xFFB6E8D9),
              size: 24,
            ),
          );
    final track = player.track;
    final catalogName = track == null
        ? null
        : ref
              .watch(quranCatalogProvider)
              .valueOrNull
              ?.surahs
              .where((item) => item.number == track.surah)
              .firstOrNull
              ?.nameFor(locale);
    // The ayah of the Mushaf's page that sounds: "Аят 2:10 · Аль-Бакара".
    final mushaf = widget.mushafControls
        ? ref.watch(
            audioControllerProvider.select(
              (value) => (
                ayah: value.displayedAyah,
                speed: value.speed,
                repeat: value.repeatEnabled,
              ),
            ),
          )
        : null;
    final mushafAyah = mushaf?.ayah;
    final title =
        standalone?.title ??
        (track == null
            ? context.l10n.audioTitle
            : mushafAyah != null
            ? '${context.l10n.ayah} ${track.surah}:$mushafAyah · '
                  '${catalogName ?? player.surahName}'
            : surahDisplayTitle(
                track.surah,
                catalogName ?? player.surahName,
                surahWord: context.l10n.surah,
              ));
    final subtitle = standalone == null
        ? reciter?.nameFor(locale) ?? context.l10n.chooseReciter
        : standalone.artist ?? standalone.album ?? context.l10n.audioTitle;
    void setCollapsed(bool value) {
      ref.read(miniPlayerCollapsedProvider.notifier).state = value;
    }

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 0),
        child: _CollapsiblePlayer(
          collapsed: collapsed,
          nudged:
              widget.allowCollapse && ref.watch(miniPlayerHintNudgeProvider),
          onCollapse: widget.allowCollapse
              ? () => setCollapsed(true)
              : widget.onSwipeAway,
          onSwipe:
              widget.onSwipeAway ??
              () {
                setCollapsed(true);
                // Once folded by hand, the bar stops showing how.
                try {
                  unawaited(
                    ref
                        .read(appPreferencesProvider.notifier)
                        .markPlayerHintLearned(),
                  );
                } on Object {
                  // A missing preference store only means the hint may show again.
                }
              },
          onExpand: () => setCollapsed(false),
          playing: player.playing,
          // The reciter's button makes the Mushaf's bar taller than 66 dp.
          fitContent: widget.mushafControls,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x52030F0C),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.white.withValues(alpha: .16)),
              ),
              child: ListTile(
                minTileHeight: 66,
                // The speed and repeat buttons make a taller second line.
                isThreeLine: widget.mushafControls,
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  8,
                  0,
                  6,
                  0,
                ),
                leading: widget.mushafControls && standalone == null
                    ? _ReciterPortraitButton(
                        name: subtitle,
                        onPressed: widget.onReciterTap,
                        child: artwork,
                      )
                    : artwork,
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: mushaf != null && standalone == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: <Widget>[
                            _MushafChip(
                              key: const ValueKey('mushaf-player-speed'),
                              tooltip: context.l10n.speed,
                              onPressed: player.track == null
                                  ? null
                                  : () => unawaited(
                                      controller.setSpeed(
                                        nextPlayerSpeed(mushaf.speed),
                                      ),
                                    ),
                              child: Text(
                                '${playbackSpeedLabel(mushaf.speed)}×',
                              ),
                            ),
                            const SizedBox(width: 6),
                            _MushafChip(
                              key: const ValueKey('mushaf-player-repeat'),
                              tooltip: mushaf.repeat
                                  ? context.l10n.repeatOn
                                  : context.l10n.repeatSelectedAyah,
                              selected: mushaf.repeat,
                              onPressed: widget.onRepeatTap,
                              child: const Icon(
                                Icons.repeat_one_rounded,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .68),
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .68),
                        ),
                      ),
                trailing: SizedBox(
                  width: widget.mushafControls ? 48 : 144,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (!widget.mushafControls)
                        _MiniPlayerControl(
                          tooltip: context.l10n.previousSurah,
                          icon: Icons.skip_previous_rounded,
                          onPressed:
                              controlsEnabled &&
                                  adjacentQueueSurah(
                                        held,
                                        currentSurah,
                                        -1,
                                        navigationMode,
                                      ) !=
                                      null
                              ? () => _changeSurah(-1)
                              : null,
                        ),
                      _MiniPlayerControl(
                        controlKey: const ValueKey('mini-player-play-toggle'),
                        tooltip: player.playing
                            ? context.l10n.pause
                            : context.l10n.play,
                        icon: player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        emphasized: true,
                        loading: player.buffering || _changingSurah,
                        onPressed: player.track == null
                            ? () => context.push('/app?tab=3')
                            : controlsEnabled
                            ? widget.mushafControls
                                  ? controller.toggle
                                  : _toggleListening
                            : null,
                      ),
                      if (!widget.mushafControls)
                        _MiniPlayerControl(
                          tooltip: context.l10n.nextSurah,
                          icon: Icons.skip_next_rounded,
                          onPressed:
                              controlsEnabled &&
                                  adjacentQueueSurah(
                                        held,
                                        currentSurah,
                                        1,
                                        navigationMode,
                                      ) !=
                                      null
                              ? () => _changeSurah(1)
                              : null,
                        ),
                    ],
                  ),
                ),
                onTap: widget.mushafControls ? null : _openListeningPlayer,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleListening() async {
    final controller = ref.read(audioControllerProvider.notifier);
    final current = ref.read(audioControllerProvider);
    if (current.channel == AudioPlaybackChannel.listening &&
        current.standalone == null &&
        current.track != null) {
      await controller.toggle();
    } else {
      await controller.activateListening();
    }
  }

  Future<void> _openListeningPlayer() async {
    final controller = ref.read(audioControllerProvider.notifier);
    if (!controller.hasListeningPlayback) {
      context.push('/app?tab=3');
      return;
    }
    final current = ref.read(audioControllerProvider);
    if (current.channel != AudioPlaybackChannel.listening ||
        current.standalone != null ||
        current.track == null) {
      if (!await controller.activateListening(play: false)) return;
    }
    if (mounted &&
        identical(controller, ref.read(audioControllerProvider.notifier))) {
      context.push('/player');
    }
  }

  Future<void> _changeSurah(int direction) async {
    if (_changingSurah) return;
    final database = ref.read(localDatabaseProvider);
    final accountScope = database.accountScope.current;
    if (accountScope == null) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final navigationEpoch = controller.navigationEpoch;
    final source = ref.read(audioControllerProvider);
    final request = ++_changeRequest;
    final current = ref.read(audioControllerProvider);
    final player = widget.mushafControls
        ? iqroAudioPresentation(current)
        : controller.listeningPresentation(current);
    final reciter = player.reciter;
    final recitationId = player.track?.recitationId;
    final currentSurah = player.track?.surah;
    if (reciter == null || recitationId == null || currentSurah == null) return;
    final recitation = _recitationById(
      ref.read(audioRecitationsProvider).valueOrNull,
      recitationId,
    );
    // A listening recording may hold only some surahs: skip to the next one
    // it has. The Audio tab's loop mode also crosses the ends.
    final targetSurah = adjacentQueueSurah(
      recitationHeldSurahs(recitation),
      currentSurah,
      direction,
      _navigationMode(player.channel, current.queueMode),
    );
    if (targetSurah == null) return;

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

    setState(() => _changingSurah = true);
    try {
      final playback = await ref
          .read(audioRepositoryProvider)
          .playback(recitationId: recitationId, surah: targetSurah);
      if (!_isCurrentRequest(
        database: database,
        accountScope: accountScope,
        controller: controller,
        request: request,
        navigationEpoch: navigationEpoch,
        source: source,
      )) {
        return;
      }
      await controller.loadPlayback(
        playback: playback,
        reciter: reciter,
        channel: player.channel,
        surahName: surahName,
      );
    } on Object {
      if (!mounted) return;
      if (!_isCurrentRequest(
        database: database,
        accountScope: accountScope,
        controller: controller,
        request: request,
        navigationEpoch: navigationEpoch,
        source: source,
      )) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.noAudio)));
    } finally {
      if (mounted && request == _changeRequest) {
        setState(() => _changingSurah = false);
      }
    }
  }

  Recitation? _recitationById(List<Recitation>? recitations, String? id) {
    for (final item in recitations ?? const <Recitation>[]) {
      if (item.id == id) return item;
    }
    return null;
  }

  ListeningQueueMode _navigationMode(
    AudioPlaybackChannel channel,
    ListeningQueueMode queueMode,
  ) => channel == AudioPlaybackChannel.listening
      ? queueMode
      : ListeningQueueMode.next;

  bool _isCurrentRequest({
    required LocalDatabase database,
    required AccountScopeSnapshot accountScope,
    required AudioController controller,
    required int request,
    required int navigationEpoch,
    required IqroAudioState source,
  }) {
    if (!mounted || request != _changeRequest) return false;
    if (!database.accountScope.isCurrent(accountScope)) return false;
    if (!identical(controller, ref.read(audioControllerProvider.notifier)) ||
        controller.navigationEpoch != navigationEpoch) {
      return false;
    }
    final current = ref.read(audioControllerProvider);
    return current.channel == source.channel &&
        current.track?.id == source.track?.id &&
        current.standalone?.mediaItem.id == source.standalone?.mediaItem.id;
  }

  @override
  void dispose() {
    _changeRequest += 1;
    super.dispose();
  }
}

/// The Mushaf player's portrait opens its reciters; a small arrow on it
/// says so.
class _ReciterPortraitButton extends StatelessWidget {
  const _ReciterPortraitButton({
    required this.name,
    required this.onPressed,
    required this.child,
  });

  final String name;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${context.l10n.chooseReciter}: $name',
      excludeSemantics: true,
      child: Tooltip(
        message: context.l10n.chooseReciter,
        child: InkResponse(
          key: const ValueKey('mushaf-player-reciter'),
          onTap: onPressed,
          radius: 28,
          child: SizedBox.square(
            dimension: 48,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                child,
                const PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: Color(0xFF08241D),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Mushaf player's speed and repeat: small round-ended buttons.
class _MushafChip extends StatelessWidget {
  const _MushafChip({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? const Color(0xFF08241D) : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? const Color(0xFF9BDECB)
              : Colors.white.withValues(alpha: .14),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 30),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerControl extends StatelessWidget {
  const _MiniPlayerControl({
    this.controlKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
    this.loading = false,
  });

  final Key? controlKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: controlKey,
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      style: emphasized
          ? IconButton.styleFrom(
              backgroundColor: const Color(0xFF9BDECB),
              foregroundColor: const Color(0xFF08241D),
              disabledBackgroundColor: const Color(0x339BDECB),
            )
          : IconButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white24,
            ),
      icon: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: emphasized ? 25 : 23),
    );
  }
}

/// A swipe on the bar in any direction rolls it into the round button and a
/// tap on the button unrolls it. Screen readers get "collapse" as an action.
class _CollapsiblePlayer extends StatefulWidget {
  const _CollapsiblePlayer({
    required this.collapsed,
    required this.nudged,
    required this.onCollapse,
    required this.onSwipe,
    required this.onExpand,
    required this.playing,
    required this.child,
    this.fitContent = false,
  });

  final bool collapsed;

  /// A bar that never folds into the button takes the height of its content.
  final bool fitContent;

  /// The fold hint slides the bar towards the corner it folds into.
  final bool nudged;

  /// Null where the bar never collapses (the Mushaf's inline player).
  final VoidCallback? onCollapse;
  final VoidCallback onSwipe;
  final VoidCallback onExpand;
  final bool playing;
  final Widget child;

  @override
  State<_CollapsiblePlayer> createState() => _CollapsiblePlayerState();
}

class _CollapsiblePlayerState extends State<_CollapsiblePlayer> {
  var _drag = Offset.zero;

  void _startDrag(DragStartDetails _) => _drag = Offset.zero;

  void _updateDrag(DragUpdateDetails details) => _drag += details.delta;

  void _endDrag(DragEndDetails details) {
    if (_swipeRollsUp(
      _drag.distance,
      details.velocity.pixelsPerSecond.distance,
    )) {
      widget.onSwipe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final onCollapse = widget.onCollapse;
    final playing = widget.playing;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: collapsed ? 1 : 0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubicEmphasized,
        child: onCollapse == null
            ? widget.child
            : Semantics(
                customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
                  CustomSemanticsAction(
                    label: MaterialLocalizations.of(
                      context,
                    ).expandedIconTapHint,
                  ): onCollapse,
                },
                child: GestureDetector(
                  key: const ValueKey('mini-player-bar'),
                  behavior: HitTestBehavior.translucent,
                  onPanStart: _startDrag,
                  onPanUpdate: _updateDrag,
                  onPanEnd: _endDrag,
                  child: AnimatedSlide(
                    offset: widget.nudged
                        ? Offset(
                            Directionality.of(context) == TextDirection.rtl
                                ? -.18
                                : .18,
                            0,
                          )
                        : Offset.zero,
                    duration: miniPlayerHintNudge,
                    curve: Curves.easeOutCubic,
                    child: widget.child,
                  ),
                ),
              ),
        builder: (context, progress, panel) {
          if (widget.fitContent) return panel!;
          final width = constraints.maxWidth;
          return Align(
            alignment: AlignmentDirectional.bottomEnd,
            heightFactor: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17 + 9 * progress),
              child: SizedBox(
                width: width + (60 - width) * progress,
                height: 66 + (60 - 66) * progress,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      excluding: collapsed,
                      child: IgnorePointer(
                        ignoring: collapsed,
                        child: OverflowBox(
                          alignment: AlignmentDirectional.bottomEnd,
                          minWidth: width,
                          maxWidth: width,
                          minHeight: 66,
                          maxHeight: 66,
                          child: Opacity(
                            opacity: (1 - progress).clamp(0.0, 1.0),
                            child: panel,
                          ),
                        ),
                      ),
                    ),
                    ExcludeSemantics(
                      excluding: !collapsed,
                      child: IgnorePointer(
                        ignoring: !collapsed,
                        child: Opacity(
                          opacity: ((progress - .2) / .8).clamp(0.0, 1.0),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: SizedBox.square(
                              dimension: 60,
                              child: IconButton.filled(
                                key: const ValueKey('mini-player-expand'),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).collapsedIconTapHint,
                                onPressed: widget.onExpand,
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  shape: const CircleBorder(),
                                ),
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: playing ? 34 : 38,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_controller.dart';
import '../../core/auth/account_scope.dart';
import '../../core/design_system/iqro_widgets.dart';
import '../../core/storage/local_database.dart';
import 'premium_reciter_portrait.dart';
import 'reciter_portraits.dart';

final miniPlayerCollapsedProvider = StateProvider<bool>((ref) => true);

class IqroMiniPlayer extends ConsumerStatefulWidget {
  const IqroMiniPlayer({this.allowCollapse = true, super.key});

  /// Mushaf has its own reader controls, so its inline player stays expanded.
  final bool allowCollapse;

  @override
  ConsumerState<IqroMiniPlayer> createState() => _IqroMiniPlayerState();
}

class _IqroMiniPlayerState extends ConsumerState<IqroMiniPlayer> {
  var _changingSurah = false;
  var _changeRequest = 0;
  AudioController? _visibleController;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(
      audioControllerProvider.select(iqroAudioPresentation),
    );
    final controller = ref.read(audioControllerProvider.notifier);
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
    final controlsEnabled =
        player.track != null && !player.buffering && !_changingSurah;
    final collapsed =
        widget.allowCollapse && ref.watch(miniPlayerCollapsedProvider);
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
          onExpand: () => setCollapsed(false),
          playing: player.playing,
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
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  8,
                  0,
                  6,
                  0,
                ),
                leading: widget.allowCollapse
                    ? SizedBox(
                        width: 96,
                        child: Row(
                          children: <Widget>[
                            PremiumReciterPortrait(
                              url: portraitUrl,
                              size: 44,
                              initials: reciter?.initials,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              key: const ValueKey('mini-player-collapse'),
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).expandedIconTapHint,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: .12,
                                ),
                                foregroundColor: Colors.white,
                                shape: const CircleBorder(),
                              ),
                              onPressed: () => setCollapsed(true),
                              icon: const Icon(
                                Icons.keyboard_double_arrow_down_rounded,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      )
                    : PremiumReciterPortrait(
                        url: portraitUrl,
                        size: 44,
                        initials: reciter?.initials,
                      ),
                title: Text(
                  player.track == null
                      ? context.l10n.audioTitle
                      : player.surahName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  reciter?.nameFor(locale) ?? context.l10n.chooseReciter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: .68)),
                ),
                trailing: SizedBox(
                  width: 144,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      _MiniPlayerControl(
                        tooltip: context.l10n.previousSurah,
                        icon: Icons.skip_previous_rounded,
                        onPressed:
                            controlsEnabled &&
                                currentSurah != null &&
                                currentSurah > 1
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
                            ? () => ref
                                  .read(audioControllerProvider.notifier)
                                  .toggle()
                            : null,
                      ),
                      _MiniPlayerControl(
                        tooltip: context.l10n.nextSurah,
                        icon: Icons.skip_next_rounded,
                        onPressed:
                            controlsEnabled &&
                                currentSurah != null &&
                                currentSurah < 114
                            ? () => _changeSurah(1)
                            : null,
                      ),
                    ],
                  ),
                ),
                onTap: () => context.push(
                  player.track == null ? '/app?tab=3' : '/player',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeSurah(int direction) async {
    if (_changingSurah) return;
    final database = ref.read(localDatabaseProvider);
    final accountScope = database.accountScope.current;
    if (accountScope == null) return;
    final controller = ref.read(audioControllerProvider.notifier);
    final request = ++_changeRequest;
    final player = ref.read(audioControllerProvider);
    final reciter = player.reciter;
    final recitationId = player.track?.recitationId;
    final currentSurah = player.track?.surah;
    if (reciter == null || recitationId == null || currentSurah == null) return;
    final targetSurah = currentSurah + direction;
    if (targetSurah < 1 || targetSurah > 114) return;

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
      )) {
        return;
      }
      await controller.loadPlayback(
        playback: playback,
        reciter: reciter,
        surahName: surahName,
      );
    } on Object {
      if (!mounted) return;
      if (!_isCurrentRequest(
        database: database,
        accountScope: accountScope,
        controller: controller,
        request: request,
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

  bool _isCurrentRequest({
    required LocalDatabase database,
    required AccountScopeSnapshot accountScope,
    required AudioController controller,
    required int request,
  }) {
    if (!mounted || request != _changeRequest) return false;
    if (!database.accountScope.isCurrent(accountScope)) return false;
    return identical(controller, ref.read(audioControllerProvider.notifier));
  }

  @override
  void dispose() {
    _changeRequest += 1;
    super.dispose();
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

class _CollapsiblePlayer extends StatelessWidget {
  const _CollapsiblePlayer({
    required this.collapsed,
    required this.onExpand,
    required this.playing,
    required this.child,
  });

  final bool collapsed;
  final VoidCallback onExpand;
  final bool playing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: collapsed ? 1 : 0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubicEmphasized,
        child: child,
        builder: (context, progress, panel) {
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
                                onPressed: onExpand,
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

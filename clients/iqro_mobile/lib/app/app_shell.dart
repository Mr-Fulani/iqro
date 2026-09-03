import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/audio/audio_controller.dart';
import '../core/auth/account_scope.dart';
import '../core/design_system/iqro_widgets.dart';
import '../core/storage/local_database.dart';
import '../features/audio/audio_screen.dart';
import '../features/audio/reciter_portraits.dart';
import '../features/home/home_screen.dart';
import '../features/more/more_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/quran/quran_screen.dart';
import 'providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({this.initialIndex = 0, super.key});
  final int initialIndex;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late var _index = widget.initialIndex.clamp(0, 4);

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(audioControllerProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          HomeScreen(),
          QuranScreen(),
          PlanScreen(),
          AudioScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (player.active) const _MiniPlayer(),
            NavigationBar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: <NavigationDestination>[
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: context.l10n.navHome,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.menu_book_outlined),
                  selectedIcon: const Icon(Icons.menu_book),
                  label: context.l10n.navQuran,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.track_changes_outlined),
                  selectedIcon: const Icon(Icons.track_changes),
                  label: context.l10n.navPlan,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.headphones_outlined),
                  selectedIcon: const Icon(Icons.headphones),
                  label: context.l10n.navAudio,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.grid_view_outlined),
                  selectedIcon: const Icon(Icons.grid_view),
                  label: context.l10n.navMore,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends ConsumerStatefulWidget {
  const _MiniPlayer();

  @override
  ConsumerState<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<_MiniPlayer> {
  var _changingSurah = false;
  var _changeRequest = 0;
  AudioController? _visibleController;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(audioControllerProvider);
    final controller = ref.watch(audioControllerProvider.notifier);
    if (!identical(_visibleController, controller)) {
      _visibleController = controller;
      _changeRequest += 1;
      _changingSurah = false;
    }
    final locale = Localizations.localeOf(context).languageCode;
    final currentSurah = player.track?.surah;
    final reciter = player.reciter;
    final portraitUrl = reciter == null
        ? null
        : resolveReciterPortraitUrl(
            reciter,
            apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
          );
    final controlsEnabled =
        player.active && !player.buffering && !_changingSurah;
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
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
                leading: _MiniPlayerPortrait(
                  portraitUrl: portraitUrl,
                  name: reciter?.nameFor(locale) ?? '',
                ),
                title: Text(
                  player.surahName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  reciter?.nameFor(locale) ?? '',
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
                        tooltip: player.playing
                            ? context.l10n.pause
                            : context.l10n.play,
                        icon: player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        emphasized: true,
                        loading: player.buffering || _changingSurah,
                        onPressed: controlsEnabled
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
                onTap: () => context.push('/player'),
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

class _MiniPlayerPortrait extends StatelessWidget {
  const _MiniPlayerPortrait({required this.portraitUrl, required this.name});

  final String? portraitUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: const Color(0xFF163C33),
      child: const Center(
        child: Icon(Icons.person_rounded, color: Color(0xFF9BDECB)),
      ),
    );
    return Semantics(
      image: true,
      label: name,
      child: Container(
        width: 48,
        height: 48,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF9BDECB), width: 1.5),
        ),
        child: ClipOval(
          child: portraitUrl == null
              ? fallback
              : CachedNetworkImage(
                  imageUrl: portraitUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => fallback,
                  errorWidget: (context, url, error) => fallback,
                ),
        ),
      ),
    );
  }
}

class _MiniPlayerControl extends StatelessWidget {
  const _MiniPlayerControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
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

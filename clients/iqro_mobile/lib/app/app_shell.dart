import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design_system/iqro_icon.dart';
import '../core/design_system/iqro_lazy_indexed_stack.dart';
import '../core/design_system/iqro_widgets.dart';
import '../features/announcements/announcement_controller.dart';
import '../features/app_update/app_update_card.dart';
import '../features/audio/audio_screen.dart';
import '../features/audio/mini_player.dart';
import '../features/home/home_screen.dart';
import '../features/more/more_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/quran/quran_screen.dart';
import '../features/quran/surah_name_art.dart';
import '../features/reminders/reminder_sound_dialog.dart';
import '../features/settings/analytics_consent.dart';
import 'providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({this.initialIndex = 0, this.child, super.key});
  final int initialIndex;
  final Widget? child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  late var _index = widget.initialIndex.clamp(0, 4);
  Timer? _playerHintTimer;
  MiniPlayerHint? _playerHint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The Audio tab is built only when first opened; warm what it shows.
    // The Mushaf's surah-name font is fetched once (on the first launch) and
    // then read from disk, so surah lists open with the calligraphy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(warmAudioCatalog(context, ref));
      unawaited(ref.read(surahHeaderFontProvider.future));
      unawaited(checkReminderSoundOnce(context, ref));
      _schedulePlayerHint();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerHintTimer?.cancel();
    _playerHint?.stop();
    super.dispose();
  }

  /// An open mini player folds when another tab opens; Home may show the hint.
  void _switchedTab(int next) {
    _stopPlayerHint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(miniPlayerCollapsedProvider.notifier).state = true;
      if (next == 0) _schedulePlayerHint();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedulePlayerHint();
    } else if (state == AppLifecycleState.paused) {
      _stopPlayerHint();
    }
  }

  void _schedulePlayerHint() {
    _stopPlayerHint();
    _playerHintTimer = Timer(miniPlayerHintDelay, _showPlayerHint);
  }

  void _stopPlayerHint() {
    _playerHintTimer?.cancel();
    _playerHintTimer = null;
    _playerHint?.cancel();
    _playerHint = null;
  }

  /// Once in a while the mini player folds and unfolds by itself on Home, so
  /// people learn that a swipe folds it (mini_player.dart).
  void _showPlayerHint() {
    _playerHintTimer = null;
    if (!mounted || _index != 0 || widget.child != null) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final now = DateTime.now();
    try {
      final preferences = ref.read(appPreferencesProvider);
      if (!miniPlayerHintDue(
        shown: preferences.playerHintsShown,
        lastShownAt: preferences.playerHintShownAt,
        now: now,
      )) {
        return;
      }
      unawaited(ref.read(appPreferencesProvider.notifier).notePlayerHint(now));
    } on Object {
      // Without stored preferences there is no telling how often it showed.
      return;
    }
    _playerHint = MiniPlayerHint.show(ref);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      final next = widget.initialIndex.clamp(0, 4);
      if (next != _index) _switchedTab(next);
      _index = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tabs switch with `go`, so the system back button found nothing to pop and
    // closed the app from any tab. Back from another tab now returns Home;
    // from Home it exits as before. Screens pushed over the shell pop first.
    final backToHome = widget.child == null && _index != 0;
    return PopScope(
      canPop: !backToHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && backToHome) context.go('/app?tab=0');
      },
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    // Unread news shows as a dot on More, where «What's new» lives.
    final signedIn = announcementSignedIn(
      ref.watch(sessionProvider.select((value) => value.valueOrNull)),
    );
    final unreadNews =
        ref.watch(
          announcementsProvider.select(
            (value) => value.unread(signedIn: signedIn),
          ),
        ) >
        0;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: <Widget>[
          widget.child ??
              IqroLazyIndexedStack(
                index: _index,
                builders: <WidgetBuilder>[
                  (_) => const HomeScreen(),
                  (_) => const QuranScreen(),
                  (_) => const PlanScreen(),
                  (_) => const AudioScreen(),
                  (_) => const MoreScreen(),
                ],
              ),
          // The tab bar is 72 dp plus the system inset under it (48 dp for
          // three-button navigation edge-to-edge). The Scaffold measures it
          // and hands the body that height as its bottom padding.
          Builder(
            builder: (context) => PositionedDirectional(
              start: 0,
              end: 0,
              bottom: MediaQuery.paddingOf(context).bottom,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppUpdateCard(),
                  AnalyticsConsentCard(),
                  IqroMiniPlayer(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            NavigationBar(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .96),
              selectedIndex: _index,
              onDestinationSelected: (value) {
                // Leaving a screen of the tab (After prayer under Plan) counts too.
                if (value != _index || widget.child != null) {
                  _switchedTab(value);
                }
                context.go('/app?tab=$value');
              },
              destinations: <NavigationDestination>[
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: context.l10n.navHome,
                ),
                NavigationDestination(
                  icon: const IqroIcon(Icons.menu_book_outlined),
                  selectedIcon: const IqroIcon(Icons.menu_book),
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
                  icon: Badge(
                    isLabelVisible: unreadNews,
                    child: const Icon(Icons.grid_view_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: unreadNews,
                    child: const Icon(Icons.grid_view),
                  ),
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
